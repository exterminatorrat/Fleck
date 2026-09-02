import Foundation
import FleckCore

enum DictationPhase: Equatable {
  case idle
  case arming
  case listening(mode: DictationMode, engine: DictationSpeechEngine)
  case finalizing
  case cleaning
  case routing
  case saved(DictationDestination)
  case failed(String)
}

enum DictationPipelineStage: Equatable, Sendable {
  case capture
  case polish
  case organize
  case save
}

struct DictationCoordinatorContext: Equatable, Sendable {
  let sessionID: UUID
  let mode: DictationMode
  let pipelineStage: DictationPipelineStage
  let cleanupOutcome: DictationCleanupOutcome?
  let failureStage: DictationPipelineStage?
}

enum DictationTerminalOutcome: Equatable {
  case saved(
    mode: DictationMode,
    cleanup: DictationCleanupOutcome,
    destination: DictationDestination?
  )
  case noSpeech
  case failed(String)
  case cancelled
}

struct DictationCoordinatorEvent: Equatable {
  let phase: DictationPhase
  let terminal: DictationTerminalOutcome?
  let context: DictationCoordinatorContext?

  init(
    phase: DictationPhase,
    terminal: DictationTerminalOutcome?,
    context: DictationCoordinatorContext? = nil
  ) {
    self.phase = phase
    self.terminal = terminal
    self.context = context
  }
}

struct DictationShortcutSession: Equatable, Hashable, Sendable {
  let id: UUID
}

enum DictationRecoveryAction: Equatable {
  case undo
  case copy
  case openHistory
  case openDestination(UUID)
}

enum DictationRecoveryResult: Equatable {
  case completed
  case copy(String)
  case openHistory
  case openDestination(UUID)
}

enum DictationDestinationChoiceResult: Equatable {
  case completed
  case failed(status: String, message: String)
}

@MainActor
final class DictationCoordinator {
  typealias CaptureContextProvider = @MainActor (
    UUID, UInt64, DictationSpeechEngine
  ) async throws -> LocalWritingCaptureContext

  private struct PendingRoutingAmbiguity {
    var ambiguity: DictationRoutingAmbiguity
    var receipt: DictationInsertionReceipt
    var record: DictationHistoryRecord
    let inboxID: UUID
    let savesHistory: Bool
  }

  private struct PreviousPresentation {
    let copyableTranscript: String?
    let recoveryReceipt: DictationInsertionReceipt?
    let recoveryAction: DictationRecoveryAction?
    let pendingRoutingAmbiguity: PendingRoutingAmbiguity?
    let routingAmbiguity: DictationRoutingAmbiguity?
  }

  private struct PhysicalReleaseReceipt {
    let gesture: DictationPhysicalGesture
    let isShort: Bool
  }

  private struct Capture {
    let id: UUID
    let mode: DictationMode
    let selectedEngine: DictationSpeechEngine
    let contextGeneration: UInt64
    let editor: (any FocusedDictationEditing)?
    let destination: DictationDestination?
    let startedAt: Date
    var engine: (any SpeechEngine)?
    var processingSession: (any DictationProcessingSession)?
    var captureContext: LocalWritingCaptureContext?
    var captureContextTask: Task<LocalWritingCaptureContext, Error>?
    var startupTask: Task<Void, Never>?
    var processingUpdatesTask: Task<Void, Never>?
    var generation: UInt64 = 0
    var stablePrefix = ""
    var pipelineStage: DictationPipelineStage = .capture
    var cleanupOutcome: DictationCleanupOutcome?
    var isStarting = true
    var isFinishing = false
    var isSourceFinishing = false
    var releaseRequested = false
    var holdAccepted = true
    var cancelRequested = false
    var routingTask: Task<DictationRoutingDecision, Never>?
    var processingSessionCancellationTask: Task<Void, Never>?
    var isTerminating = false
    var editorCancelled = false
    var focusedCommitReceipt: FocusedDictationCommitReceipt?
    var focusedPersistenceReceipt: FocusedDictationPersistenceReceipt?
    var focusedEditorRollbackSucceeded = false
    var focusedPersistenceCompensated = false
    var stopOrigin: DictationStopOrigin?
    var previousPresentation: PreviousPresentation?
    var physicalReleaseReceipt: PhysicalReleaseReceipt?
    var deferredStartupFailureMessage: String?
    var deferredStartupFailureTask: Task<Void, Never>?
    var deferredFinishTask: Task<Void, Never>?
  }

  private let engineProvider: any SpeechEngineProviding
  private let preferredEngine: @MainActor () -> DictationSpeechEngine
  private let cleaner: any TranscriptCleaning
  private let router: any DestinationRouting
  private let saver: any DictationSaving
  private let historyController: DictationHistoryController
  private let historyEnabled: @MainActor () -> Bool
  private let processing: (any DictationProcessing)?
  private let captureContextProvider: CaptureContextProvider?
  private let clock: DictationClock
  private let holdThreshold: Duration
  private let holdSleeper: @Sendable (Duration) async -> Void

  private var capture: Capture?
  private var shortcutID: UUID?
  private var holdTask: Task<Void, Never>?
  private var activeShortcutSessions = Set<UUID>()
  private var shortcutTerminalWaiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]
  private var terminalWaiters: [CheckedContinuation<Void, Never>] = []
  private var eventObserver: (@MainActor (DictationCoordinatorEvent) -> Void)?
  private var levelObserver: (@MainActor (Float) -> Void)?
  private var pendingRoutingAmbiguity: PendingRoutingAmbiguity?
  private var nextCaptureContextGeneration: UInt64 = 1

  private(set) var phase: DictationPhase = .idle
  private(set) var copyableTranscript: String?
  private(set) var recoveryReceipt: DictationInsertionReceipt?
  private(set) var recoveryAction: DictationRecoveryAction?
  private(set) var recoveryOperationInFlight = false
  private(set) var routingAmbiguity: DictationRoutingAmbiguity?
  private(set) var latestRuntimeMeasurements = DictationRuntimeMeasurements.empty
  private(set) var latestProcessingResult: DictationProcessingResult?
  private var latestMeasurementCaptureID: UUID?

  var canConfigureShortcut: Bool {
    capture == nil && shortcutID == nil && activeShortcutSessions.isEmpty
      && !recoveryOperationInFlight
  }

  init(
    engineProvider: any SpeechEngineProviding,
    preferredEngine: @escaping @MainActor () -> DictationSpeechEngine,
    cleaner: any TranscriptCleaning,
    router: any DestinationRouting,
    saver: any DictationSaving,
    historyStore: DictationHistoryStore,
    historyEnabled: @escaping @MainActor () -> Bool,
    processing: (any DictationProcessing)? = nil,
    captureContextProvider: CaptureContextProvider? = nil,
    clock: DictationClock = .live,
    holdThreshold: Duration = .milliseconds(180),
    holdSleeper: @escaping @Sendable (Duration) async -> Void = { duration in
      try? await Task.sleep(for: duration)
    }
  ) {
    self.engineProvider = engineProvider
    self.preferredEngine = preferredEngine
    self.cleaner = cleaner
    self.router = router
    self.saver = saver
    historyController = DictationHistoryController(store: historyStore)
    self.historyEnabled = historyEnabled
    self.processing = processing
    self.captureContextProvider = captureContextProvider
    self.clock = clock
    self.holdThreshold = holdThreshold
    self.holdSleeper = holdSleeper
  }

  init(
    engineProvider: any SpeechEngineProviding,
    preferredEngine: @escaping @MainActor () -> DictationSpeechEngine,
    cleaner: any TranscriptCleaning,
    router: any DestinationRouting,
    saver: any DictationSaving,
    historyController: DictationHistoryController,
    historyEnabled: @escaping @MainActor () -> Bool,
    processing: (any DictationProcessing)? = nil,
    captureContextProvider: CaptureContextProvider? = nil,
    clock: DictationClock = .live,
    holdThreshold: Duration = .milliseconds(180),
    holdSleeper: @escaping @Sendable (Duration) async -> Void = { duration in
      try? await Task.sleep(for: duration)
    }
  ) {
    self.engineProvider = engineProvider
    self.preferredEngine = preferredEngine
    self.cleaner = cleaner
    self.router = router
    self.saver = saver
    self.historyController = historyController
    self.historyEnabled = historyEnabled
    self.processing = processing
    self.captureContextProvider = captureContextProvider
    self.clock = clock
    self.holdThreshold = holdThreshold
    self.holdSleeper = holdSleeper
  }

  func setEventObserver(
    _ observer: (@MainActor (DictationCoordinatorEvent) -> Void)?
  ) {
    eventObserver = observer
  }

  func setLevelObserver(
    _ observer: (@MainActor (Float) -> Void)?
  ) {
    levelObserver = observer
  }

  @discardableResult
  func beginShortcut(
    editor: (any FocusedDictationEditing)?,
    destination: DictationDestination? = nil,
    physicalGesture: DictationPhysicalGesture = .absent
  ) -> DictationShortcutSession? {
    let session = DictationShortcutSession(id: UUID())
    return beginShortcut(
      session: session,
      editor: editor,
      destination: destination,
      physicalGesture: physicalGesture
    ) ? session : nil
  }

  @discardableResult
  func beginShortcut(
    session: DictationShortcutSession,
    editor: (any FocusedDictationEditing)?,
    destination: DictationDestination?,
    physicalGesture: DictationPhysicalGesture = .absent
  ) -> Bool {
    guard capture == nil, shortcutID == nil, !recoveryOperationInFlight,
      !activeShortcutSessions.contains(session.id)
    else {
      return false
    }
    let selectedEngine = preferredEngine()
    let contextGeneration = allocateCaptureContextGeneration()
    let focusedEditor = editor?.canBeginFocusedDictation == true ? editor : nil
    let previousPresentation = previousPresentationSnapshot()
    guard reserveCapture(
      id: session.id,
      mode: focusedEditor == nil ? .smartCapture : .focused,
      editor: focusedEditor,
      destination: focusedEditor == nil ? nil : destination,
      physicalGesture: physicalGesture,
      selectedEngine: selectedEngine,
      contextGeneration: contextGeneration,
      clearsPreviousPresentation: false
    ) else {
      return false
    }
    shortcutID = session.id
    let contextTask: Task<LocalWritingCaptureContext, Error>?
    if processing != nil, let captureContextProvider {
      contextTask = Task {
        try await captureContextProvider(session.id, contextGeneration, selectedEngine)
      }
    } else {
      contextTask = nil
    }
    if var active = capture, active.id == session.id {
      active.holdAccepted = false
      active.captureContextTask = contextTask
      active.previousPresentation = previousPresentation
      capture = active
    }
    activeShortcutSessions.insert(session.id)
    setPhase(.arming)
    holdTask = Task { [weak self, holdSleeper, holdThreshold] in
      await holdSleeper(holdThreshold)
      guard !Task.isCancelled else { return }
      await self?.holdThresholdElapsed(session.id)
    }
    let startupTask = Task { @MainActor [weak self, contextTask] in
      guard let self else { return }
      await self.startShortcutCapture(session.id, contextTask: contextTask)
    }
    if var active = capture, active.id == session.id {
      active.startupTask = startupTask
      capture = active
    }
    return true
  }

  @discardableResult
  func beginHandsFreeShortcut(
    editor: (any FocusedDictationEditing)?,
    destination: DictationDestination? = nil,
    physicalGesture: DictationPhysicalGesture = .absent
  ) -> DictationShortcutSession? {
    let session = DictationShortcutSession(id: UUID())
    return beginHandsFreeShortcut(
      session: session,
      editor: editor,
      destination: destination,
      physicalGesture: physicalGesture
    ) ? session : nil
  }

  @discardableResult
  func beginHandsFreeShortcut(
    session: DictationShortcutSession,
    editor: (any FocusedDictationEditing)?,
    destination: DictationDestination?,
    physicalGesture: DictationPhysicalGesture = .absent
  ) -> Bool {
    guard capture == nil, shortcutID == nil, !recoveryOperationInFlight,
      !activeShortcutSessions.contains(session.id)
    else {
      return false
    }
    let focusedEditor = editor?.canBeginFocusedDictation == true ? editor : nil
    activeShortcutSessions.insert(session.id)
    guard reserveCapture(
      id: session.id,
      mode: focusedEditor == nil ? .smartCapture : .focused,
      editor: focusedEditor,
      destination: focusedEditor == nil ? nil : destination,
      physicalGesture: physicalGesture
    ) else {
      activeShortcutSessions.remove(session.id)
      return false
    }
    Task { [weak self] in
      await self?.startReservedCapture(session.id)
    }
    return true
  }

  func finishHandsFreeShortcut(
    _ session: DictationShortcutSession,
    stopOrigin: DictationStopOrigin
  ) async {
    guard activeShortcutSessions.contains(session.id), capture?.id == session.id else {
      return
    }
    if capture?.isStarting == true {
      await cancelActiveCapture(session.id)
      return
    }
    await finish(stopOrigin: stopOrigin)
  }

  func finishHandsFreeShortcut(_ session: DictationShortcutSession) async {
    await finishHandsFreeShortcut(
      session,
      stopOrigin: .toolbarAction(clock.now())
    )
  }

  func recordPhysicalRelease(
    _ session: DictationShortcutSession,
    physicalGesture: DictationPhysicalGesture
  ) {
    guard activeShortcutSessions.contains(session.id),
      var active = capture,
      active.id == session.id,
      active.previousPresentation != nil,
      active.physicalReleaseReceipt == nil,
      let pressedAt = physicalGesture.pressedAt,
      let releasedAt = physicalGesture.releasedAt
    else { return }
    let receipt = PhysicalReleaseReceipt(
      gesture: physicalGesture,
      isShort: pressedAt.duration(to: releasedAt) < holdThreshold
    )
    active.physicalReleaseReceipt = receipt
    if !receipt.isShort, active.stopOrigin == nil {
      active.stopOrigin = .physicalRelease(releasedAt)
    }
    scheduleDeferredFinishIfReady(&active)
    capture = active
    guard receipt.isShort else {
      recordMeasurement(.physicalRelease, at: releasedAt, captureID: session.id)
      if active.deferredStartupFailureMessage != nil {
        acceptArmedShortcut(session.id)
      }
      return
    }

    requestCancellation(session.id, at: clock.now())
    holdTask?.cancel()
    if let previousPresentation = capture?.previousPresentation {
      restorePreviousPresentation(previousPresentation)
    }
  }

  func endShortcut(
    _ session: DictationShortcutSession,
    physicalGesture: DictationPhysicalGesture
  ) async {
    guard activeShortcutSessions.contains(session.id) else { return }
    let resolvedGesture = capture?.id == session.id
      ? capture?.physicalReleaseReceipt?.gesture ?? physicalGesture
      : physicalGesture
    if let pressedAt = resolvedGesture.pressedAt,
      let releasedAt = resolvedGesture.releasedAt,
      pressedAt.duration(to: releasedAt) < holdThreshold
    {
      if shortcutID == session.id {
        await cancelArmedShortcut(session.id)
      } else if capture?.id == session.id {
        if let previousPresentation = takePreviousPresentation(session.id) {
          restorePreviousPresentation(previousPresentation)
        }
        await cancelActiveCapture(session.id)
      }
      return
    }
    if shortcutID == session.id {
      guard let pressedAt = resolvedGesture.pressedAt,
        let releasedAt = resolvedGesture.releasedAt,
        pressedAt.duration(to: releasedAt) >= holdThreshold
      else {
        await cancelArmedShortcut(session.id)
        return
      }
      acceptArmedShortcut(session.id)
    }
    guard capture?.id == session.id else { return }
    if let releasedAt = resolvedGesture.releasedAt {
      _ = takePreviousPresentation(session.id)
      recordMeasurement(.physicalRelease, at: releasedAt, captureID: session.id)
      await finish(stopOrigin: .physicalRelease(releasedAt))
    }
  }

  func endShortcut(_ session: DictationShortcutSession) async {
    guard activeShortcutSessions.contains(session.id) else { return }
    if shortcutID == session.id {
      await cancelArmedShortcut(session.id)
      return
    }
    guard capture?.id == session.id else { return }
    if capture?.isStarting == true {
      Task { [weak self] in
        await self?.cancelActiveCapture(session.id)
      }
      return
    }
    _ = takePreviousPresentation(session.id)
    await finish()
  }

  func cancelShortcut(_ session: DictationShortcutSession) async {
    guard activeShortcutSessions.contains(session.id) else { return }
    guard shortcutID == session.id || capture?.id == session.id else { return }
    await cancel()
  }

  func waitForShortcutTerminal(_ session: DictationShortcutSession) async {
    guard activeShortcutSessions.contains(session.id) else { return }
    await withCheckedContinuation { continuation in
      if activeShortcutSessions.contains(session.id) {
        shortcutTerminalWaiters[session.id, default: []].append(continuation)
      } else {
        continuation.resume()
      }
    }
  }

  func waitForTerminal() async {
    guard capture != nil || shortcutID != nil else { return }
    await withCheckedContinuation { continuation in
      if capture != nil || shortcutID != nil {
        terminalWaiters.append(continuation)
      } else {
        continuation.resume()
      }
    }
  }

  func start(
    mode: DictationMode,
    editor: (any FocusedDictationEditing)? = nil,
    destination: DictationDestination? = nil
  ) async {
    await startCapture(id: UUID(), mode: mode, editor: editor, destination: destination)
  }

  private func startCapture(
    id: UUID,
    mode: DictationMode,
    editor: (any FocusedDictationEditing)?,
    destination: DictationDestination?,
    physicalGesture: DictationPhysicalGesture = .absent,
    selectedEngine: DictationSpeechEngine? = nil,
    contextGeneration: UInt64? = nil,
    captureContext: LocalWritingCaptureContext? = nil
  ) async {
    guard reserveCapture(
      id: id,
      mode: mode,
      editor: editor,
      destination: destination,
      physicalGesture: physicalGesture,
      selectedEngine: selectedEngine,
      contextGeneration: contextGeneration,
      captureContext: captureContext
    ) else {
      return
    }
    await startReservedCapture(id)
  }

  private func reserveCapture(
    id: UUID,
    mode: DictationMode,
    editor: (any FocusedDictationEditing)?,
    destination: DictationDestination?,
    physicalGesture: DictationPhysicalGesture,
    selectedEngine fixedEngine: DictationSpeechEngine? = nil,
    contextGeneration fixedContextGeneration: UInt64? = nil,
    captureContext: LocalWritingCaptureContext? = nil,
    clearsPreviousPresentation: Bool = true
  ) -> Bool {
    guard capture == nil, shortcutID == nil, !recoveryOperationInFlight else {
      return false
    }
    let selectedEngine = fixedEngine ?? preferredEngine()
    if clearsPreviousPresentation {
      clearPreviousPresentation()
    }
    latestMeasurementCaptureID = id
    latestRuntimeMeasurements = .empty
    latestProcessingResult = nil
    if let pressedAt = physicalGesture.pressedAt {
      recordMeasurement(.physicalPress, at: pressedAt, captureID: id)
    }
    if let releasedAt = physicalGesture.releasedAt {
      recordMeasurement(.physicalRelease, at: releasedAt, captureID: id)
    }
    let focusedEditor = mode == .focused
      ? (editor?.canBeginFocusedDictation == true ? editor : nil)
      : nil
    let contextGeneration = fixedContextGeneration ?? allocateCaptureContextGeneration()
    capture = Capture(
      id: id,
      mode: mode,
      selectedEngine: selectedEngine,
      contextGeneration: contextGeneration,
      editor: focusedEditor,
      destination: mode == .focused ? destination : nil,
      startedAt: Date(),
      captureContext: captureContext
    )
    setPhase(.arming)
    guard mode != .focused || (
      focusedEditor?.canBeginFocusedDictation == true && focusedEditor?.beginFocusedDictation() == true
    ) else {
      let terminalContext = contextForCapture(
        capture!,
        failureStage: .capture
      )
      capture = nil
      completeShortcutSession(id)
      publishTerminal(
        phase: .failed("Unable to begin focused dictation."),
        outcome: .failed("Unable to begin focused dictation."),
        context: terminalContext
      )
      return false
    }
    return true
  }

  private func startShortcutCapture(
    _ id: UUID,
    contextTask: Task<LocalWritingCaptureContext, Error>?
  ) async {
    if let contextTask {
      do {
        let context = try await contextTask.value
        guard let current = capture, current.id == id else { return }
        guard context.captureID == id,
          context.generation == current.contextGeneration,
          context.speechEngine == current.selectedEngine
        else {
          throw StreamingDictationProcessorError.captureContextMismatch
        }
        guard await continueCapture(id) else { return }
        guard var active = capture, active.id == id else { return }
        active.captureContext = context
        capture = active
      } catch {
        await handleStartupFailure(id, error: error)
        return
      }
    }
    await startReservedCapture(id)
  }

  private func startReservedCapture(_ id: UUID) async {
    guard let reservedCapture = capture, reservedCapture.id == id else { return }
    let mode = reservedCapture.mode
    let selectedEngine = reservedCapture.selectedEngine
    if let processing {
      await startProcessingCapture(
        id,
        mode: mode,
        engine: selectedEngine,
        processing: processing
      )
      return
    }
    let engine: any SpeechEngine
    do {
      engine = try await engineProvider.engineForCapture(preferred: selectedEngine)
    } catch {
      await handleStartupFailure(id, error: error)
      return
    }
    guard var activeCapture = capture, activeCapture.id == id else {
      await release(engine)
      return
    }
    activeCapture.engine = engine
    activeCapture.isStarting = false
    capture = activeCapture
    guard await continueCapture(id) else { return }

    setStarting(id, true)
    do {
      try await engine.start(
        provisional: { [weak self] text in
          guard let self, self.isActive(id), self.capture?.holdAccepted == true,
            mode == .focused
          else { return }
          self.capture?.editor?.updateFocusedDictation(provisionalText: text)
        },
        level: { [weak self] level in
          guard let self, self.isActive(id), self.capture?.holdAccepted == true else { return }
          self.levelObserver?(level)
        }
      )
    } catch {
      await handleStartupFailure(id, error: error)
      return
    }
    guard let current = finishStarting(id) else { return }
    guard await continueCapture(id) else { return }
    if current.holdAccepted {
      setPhase(.listening(mode: mode, engine: engine.kind))
    }
    if current.releaseRequested, let stopOrigin = current.stopOrigin {
      await finish(stopOrigin: stopOrigin)
    }
  }

  private func startProcessingCapture(
    _ id: UUID,
    mode: DictationMode,
    engine: DictationSpeechEngine,
    processing: any DictationProcessing
  ) async {
    if capture?.captureContext == nil {
      guard let captureContextProvider else {
        await handleStartupFailure(
          id,
          error: StreamingDictationProcessorError.captureContextMismatch
        )
        return
      }
      let context: LocalWritingCaptureContext
      do {
        guard let reserved = capture, reserved.id == id else { return }
        context = try await captureContextProvider(
          id,
          reserved.contextGeneration,
          engine
        )
        guard context.captureID == id,
          context.generation == reserved.contextGeneration,
          context.speechEngine == engine
        else {
          throw StreamingDictationProcessorError.captureContextMismatch
        }
      } catch {
        await handleStartupFailure(id, error: error)
        return
      }
      guard await continueCapture(id) else { return }
      guard var active = capture, active.id == id else { return }
      active.captureContext = context
      capture = active
    }

    await processing.prepare(for: .immediateCapture)
    guard await continueCapture(id) else { return }

    let session: any DictationProcessingSession
    do {
      guard let context = capture?.captureContext else {
        throw StreamingDictationProcessorError.captureContextMismatch
      }
      let configuration = DictationProcessingConfiguration(
        mode: mode,
        captureContext: context
      )
      session = try await processing.begin(
        configuration: configuration,
        level: { [weak self] level in
          guard let self, self.isActive(id), self.capture?.holdAccepted == true else { return }
          self.levelObserver?(level)
        },
        startAuthorized: { [weak self] in
          self?.isStartAuthorized(id) == true
        }
      )
    } catch {
      await handleStartupFailure(id, error: error)
      return
    }

    guard var activeCapture = capture, activeCapture.id == id else {
      await session.cancel()
      return
    }
    activeCapture.processingSession = session
    activeCapture.isStarting = false
    capture = activeCapture
    guard await continueCapture(id) else { return }
    guard let current = capture, current.id == id else { return }
    guard await continueCapture(id) else { return }
    if current.holdAccepted {
      startProcessingUpdates(id, session: session)
      setPhase(.listening(mode: mode, engine: engine))
    }
    if current.releaseRequested, let stopOrigin = current.stopOrigin {
      await finish(stopOrigin: stopOrigin)
    }
  }

  private func startProcessingUpdates(
    _ id: UUID,
    session: any DictationProcessingSession
  ) {
    guard var capture, capture.id == id else { return }
    capture.processingUpdatesTask = Task { @MainActor [weak self] in
      do {
        for try await update in session.updates {
          guard let self else { return }
          guard self.applyProcessingUpdate(update, to: id) else { return }
        }
      } catch {
        return
      }
    }
    self.capture = capture
  }

  private func applyProcessingUpdate(
    _ update: DictationTextUpdate,
    to id: UUID
  ) -> Bool {
    guard var capture, capture.id == id else { return false }
    guard !capture.cancelRequested,
      !capture.isTerminating,
      !capture.isFinishing
    else { return false }
    guard update.generation > capture.generation,
      update.stableText.hasPrefix(capture.stablePrefix)
    else {
      return true
    }
    capture.generation = update.generation
    capture.stablePrefix = update.stableText
    let editor = capture.editor
    let mode = capture.mode
    self.capture = capture
    if mode == .focused {
      editor?.updateFocusedDictation(provisionalText: update.displayText)
    }
    return true
  }

  private func drainProcessingUpdates(_ id: UUID) async {
    guard let activeCapture = capture,
      activeCapture.id == id,
      let task = activeCapture.processingUpdatesTask
    else { return }
    task.cancel()
    await task.value
    guard var capture, capture.id == id else { return }
    capture.processingUpdatesTask = nil
    self.capture = capture
  }

  func finish() async {
    let stopOrigin = DictationStopOrigin.toolbarAction(clock.now())
    await finish(stopOrigin: stopOrigin)
  }

  private func finish(stopOrigin proposedOrigin: DictationStopOrigin) async {
    guard var capture, !capture.isTerminating, !capture.cancelRequested,
      capture.deferredStartupFailureMessage == nil
    else { return }
    if capture.stopOrigin == nil {
      capture.stopOrigin = proposedOrigin
      if let releasedAt = proposedOrigin.physicalReleaseAt {
        recordMeasurement(.physicalRelease, at: releasedAt, captureID: capture.id)
      }
    }
    guard let stopOrigin = capture.stopOrigin else { return }
    if activeShortcutSessions.contains(capture.id),
      capture.previousPresentation != nil,
      (!capture.holdAccepted || capture.physicalReleaseReceipt == nil)
    {
      capture.releaseRequested = true
      self.capture = capture
      return
    }
    if capture.isStarting {
      capture.releaseRequested = true
      self.capture = capture
      return
    }
    guard !capture.isFinishing else { return }
    guard capture.engine != nil || capture.processingSession != nil else { return }
    capture.isFinishing = true
    self.capture = capture
    setPhase(.finalizing)

    if let processingSession = capture.processingSession {
      await finishProcessingCapture(
        capture.id,
        session: processingSession,
        stopOrigin: stopOrigin
      )
      return
    }

    guard let engine = capture.engine else { return }

    setSourceFinishing(capture.id, true)
    let rawText: String?
    do {
      rawText = try await engine.finish(stopOrigin: stopOrigin)
      setSourceFinishing(capture.id, false)
    } catch {
      setSourceFinishing(capture.id, false)
      guard await continueCapture(capture.id) else { return }
      await terminate(
        capture.id,
        phase: .failed(message(for: error)),
        cancelEditor: capture.mode == .focused,
        failureStage: .capture
      )
      return
    }
    guard await continueCapture(capture.id) else { return }
    guard let rawText = nonempty(rawText) else {
      await terminate(
        capture.id,
        phase: .failed("No speech detected."),
        cancelEditor: capture.mode == .focused,
        outcome: .noSpeech,
        failureStage: .capture
      )
      return
    }

    let savesHistory = historyEnabled()
    var record = DictationHistoryRecord(
      id: capture.id,
      mode: capture.mode,
      engine: engine.kind,
      startedAt: capture.startedAt,
      completedAt: Date(),
      rawTranscript: rawText,
      cleanupOutcome: .pending,
      destination: capture.mode == .focused ? capture.destination : nil,
      insertionOutcome: .pending
    )
    setCleanupOutcome(.pending, captureID: capture.id)
    guard let historyIsDurable = await updateHistory(
      record,
      captureID: capture.id,
      enabled: savesHistory
    ) else { return }

    setPhase(.cleaning)
    let cleanedText: String
    do {
      cleanedText = try await cleaner.clean(rawText)
      guard await continueCapture(capture.id) else { return }
      record.cleanedTranscript = cleanedText
      record.cleanupOutcome = .cleaned
      setCleanupOutcome(.cleaned, captureID: capture.id)
    } catch {
      guard await continueCapture(capture.id) else { return }
      cleanedText = rawText
      record.cleanupOutcome = .usedRaw
      setCleanupOutcome(.usedRaw, captureID: capture.id)
    }

    if capture.mode == .focused {
      await finishFocused(
        capture.id,
        text: cleanedText,
        record: record,
        savesHistory: savesHistory,
        historyIsDurable: historyIsDurable
      )
    } else {
      await finishSmart(
        capture.id,
        text: cleanedText,
        record: record,
        savesHistory: savesHistory,
        historyIsDurable: historyIsDurable
      )
    }
  }

  private func finishProcessingCapture(
    _ id: UUID,
    session: any DictationProcessingSession,
    stopOrigin: DictationStopOrigin
  ) async {
    let result: DictationProcessingResult
    do {
      result = try await session.finish(stopOrigin: stopOrigin)
    } catch {
      await drainProcessingUpdates(id)
      guard await continueCapture(id) else { return }
      guard let capture, capture.id == id else { return }
      await terminate(
        id,
        phase: .failed(message(for: error)),
        cancelEditor: capture.mode == .focused,
        outcome: (error as? StreamingDictationProcessorError) == .noSpeech ? .noSpeech : nil,
        failureStage: .capture
      )
      return
    }

    await drainProcessingUpdates(id)
    guard await continueCapture(id) else { return }
    guard let capture, capture.id == id else { return }
    if let expectedContext = capture.captureContext {
      let acknowledgementIsAccepted: Bool
      switch result.recognitionContextAcknowledgement {
      case .applied(let context), .unsupported(let context):
        acknowledgementIsAccepted = context == expectedContext
      case .rejected, nil:
        acknowledgementIsAccepted = false
      }
      guard result.captureContext == expectedContext,
        acknowledgementIsAccepted
      else {
        await terminate(
          id,
          phase: .failed(message(for: StreamingDictationProcessorError.captureContextMismatch)),
          cancelEditor: capture.mode == .focused,
          failureStage: .capture
        )
        return
      }
    }
    latestProcessingResult = result
    overlay(result.measurements, captureID: id)

    let savesHistory = historyEnabled()
    let record = DictationHistoryRecord(
      id: id,
      mode: capture.mode,
      engine: capture.selectedEngine,
      startedAt: capture.startedAt,
      completedAt: Date(),
      rawTranscript: result.rawTranscript,
      cleanedTranscript: result.cleanedTranscript,
      cleanupOutcome: result.cleanupOutcome,
      destination: capture.mode == .focused ? capture.destination : nil,
      insertionOutcome: .pending
    )
    setPhase(.cleaning)
    guard let historyIsDurable = await updateHistory(
      record,
      captureID: id,
      enabled: savesHistory
    ) else { return }

    if capture.mode == .focused {
      await finishFocused(
        id,
        text: result.insertedText,
        record: record,
        savesHistory: savesHistory,
        historyIsDurable: historyIsDurable
      )
    } else {
      await finishSmart(
        id,
        text: result.insertedText,
        record: record,
        savesHistory: savesHistory,
        historyIsDurable: historyIsDurable
      )
    }
  }

  func cancel() async {
    if let id = shortcutID {
      await cancelArmedShortcut(id)
    }
    guard let capture, !capture.isTerminating, !capture.cancelRequested else {
      return
    }
    await cancelActiveCapture(capture.id)
  }

  private func cancelActiveCapture(_ id: UUID) async {
    guard let capture, capture.id == id, !capture.isTerminating else { return }
    guard capture.processingSession != nil || !capture.isSourceFinishing else {
      return
    }
    let captureContextTask = capture.captureContextTask
    let startupTask = capture.startupTask
    let deferredStartupFailureTask = capture.deferredStartupFailureTask
    let deferredFinishTask = capture.deferredFinishTask
    requestCancellation(id, at: clock.now())

    captureContextTask?.cancel()
    startupTask?.cancel()
    deferredStartupFailureTask?.cancel()
    deferredFinishTask?.cancel()
    _ = await captureContextTask?.result
    await startupTask?.value
    await deferredStartupFailureTask?.value

    guard let current = self.capture, current.id == id, !current.isTerminating else {
      return
    }
    if let routingTask = current.routingTask {
      routingTask.cancel()
      _ = await routingTask.value
      if var latest = self.capture, latest.id == id {
        latest.routingTask = nil
        self.capture = latest
      }
      await deferredFinishTask?.value
      await completeCancellation(id)
    } else if current.processingSession != nil {
      await cancelProcessingSession(id)
      await deferredFinishTask?.value
      await completeCancellation(id)
    } else {
      await deferredFinishTask?.value
      _ = await compensateFocusedPersistence(id)
      guard let current = self.capture, current.id == id, !current.isTerminating else {
        return
      }
      guard !current.isStarting, !current.isFinishing else { return }
      await completeCancellation(id)
    }
  }

  private func setSourceFinishing(_ id: UUID, _ isFinishing: Bool) {
    guard var capture, capture.id == id else { return }
    capture.isSourceFinishing = isFinishing
    self.capture = capture
  }

  private func holdThresholdElapsed(_ id: UUID) async {
    guard shortcutID == id else { return }
    acceptArmedShortcut(id)
  }

  private func acceptArmedShortcut(_ id: UUID) {
    guard shortcutID == id, var active = capture, active.id == id,
      !active.cancelRequested
    else { return }
    active.holdAccepted = true
    clearArmedShortcut()
    if let failureMessage = active.deferredStartupFailureMessage {
      let cancelEditor = active.mode == .focused
      active.deferredStartupFailureTask = Task { @MainActor [weak self] in
        await self?.completeDeferredStartupFailure(
          id,
          message: failureMessage,
          cancelEditor: cancelEditor
        )
      }
      capture = active
      return
    }
    clearPreviousPresentation()
    scheduleDeferredFinishIfReady(&active)
    capture = active
    if let session = active.processingSession {
      startProcessingUpdates(id, session: session)
    }
    if !active.isStarting {
      setPhase(.listening(mode: active.mode, engine: active.selectedEngine))
    }
  }

  private func scheduleDeferredFinishIfReady(_ active: inout Capture) {
    guard active.holdAccepted,
      active.physicalReleaseReceipt?.isShort == false,
      active.releaseRequested,
      active.deferredFinishTask == nil,
      let stopOrigin = active.stopOrigin
    else { return }
    active.deferredFinishTask = Task { @MainActor [weak self] in
      await Task.yield()
      guard !Task.isCancelled else { return }
      await self?.finish(stopOrigin: stopOrigin)
    }
  }

  private func cancelArmedShortcut(_ id: UUID) async {
    guard shortcutID == id, let active = capture, active.id == id else { return }
    let pendingContext = active.captureContextTask
    let pendingStartup = active.startupTask
    let pendingThreshold = holdTask
    requestCancellation(id, at: clock.now())
    clearArmedShortcut()
    pendingThreshold?.cancel()
    pendingContext?.cancel()
    pendingStartup?.cancel()
    _ = await pendingContext?.result
    await pendingStartup?.value
    guard self.capture?.id == id else { return }
    await cancelProcessingSession(id)
    await completeCancellation(id)
  }

  private func clearArmedShortcut() {
    shortcutID = nil
    holdTask = nil
  }

  private func clearPreviousPresentation() {
    copyableTranscript = nil
    recoveryReceipt = nil
    recoveryAction = nil
    pendingRoutingAmbiguity = nil
    routingAmbiguity = nil
  }

  private func requestCancellation(_ id: UUID, at instant: ContinuousClock.Instant) {
    guard var active = capture, active.id == id, !active.cancelRequested else { return }
    active.cancelRequested = true
    if active.processingSession != nil {
      active.generation &+= 1
    }
    capture = active
    recordMeasurement(.cancellationRequested, at: instant, captureID: id)
    rollbackEditor(id)
  }

  private func previousPresentationSnapshot() -> PreviousPresentation {
    PreviousPresentation(
      copyableTranscript: copyableTranscript,
      recoveryReceipt: recoveryReceipt,
      recoveryAction: recoveryAction,
      pendingRoutingAmbiguity: pendingRoutingAmbiguity,
      routingAmbiguity: routingAmbiguity
    )
  }

  private func takePreviousPresentation(_ id: UUID) -> PreviousPresentation? {
    guard var active = capture, active.id == id else { return nil }
    let previousPresentation = active.previousPresentation
    active.previousPresentation = nil
    capture = active
    return previousPresentation
  }

  private func restorePreviousPresentation(_ previousPresentation: PreviousPresentation) {
    copyableTranscript = previousPresentation.copyableTranscript
    recoveryReceipt = previousPresentation.recoveryReceipt
    recoveryAction = previousPresentation.recoveryAction
    pendingRoutingAmbiguity = previousPresentation.pendingRoutingAmbiguity
    routingAmbiguity = previousPresentation.routingAmbiguity
  }

  private func allocateCaptureContextGeneration() -> UInt64 {
    let generation = nextCaptureContextGeneration
    nextCaptureContextGeneration &+= 1
    return generation
  }

  private func isStartAuthorized(_ id: UUID) -> Bool {
    guard let capture, capture.id == id else { return false }
    return !capture.cancelRequested && !capture.isTerminating
  }

  private func finishFocused(
    _ id: UUID,
    text: String,
    record: DictationHistoryRecord,
    savesHistory: Bool,
    historyIsDurable: Bool
  ) async {
    guard let capture, capture.id == id else { return }
    var record = record
    setPipelineStage(.save, captureID: id)
    guard let commitReceipt = capture.editor?.commitFocusedDictation(text: text) else {
      record.insertionOutcome = .unsaved
      guard let durable = await updateHistory(record, captureID: id, enabled: savesHistory)
      else { return }
      await unsaved(
        id,
        text: text,
        historyIsDurable: durable || historyIsDurable,
        failureStage: .save
      )
      return
    }
    recordMeasurement(.insertionCommitted, at: clock.now(), captureID: id)
    setFocusedCommitReceipt(commitReceipt, captureID: id)
    publishSaveContext(captureID: id)
    do {
      let persistenceReceipt = try await saver.flushFocusedDictationSave(captureID: id)
      recordMeasurement(.persistenceCompleted, at: clock.now(), captureID: id)
      setFocusedPersistenceReceipt(persistenceReceipt, captureID: id)
      if isCancellationRequested(id) {
        _ = await compensateFocusedPersistence(id)
        await completeCancellation(id)
        return
      }
      guard await continueCapture(id) else { return }
      record.insertionOutcome = .saved
      guard await updateHistory(record, captureID: id, enabled: savesHistory) != nil else { return }
      finalizeFocusedCommit(id)
      await terminate(
        id,
        phase: .idle,
        cancelEditor: false,
        outcome: .saved(
          mode: .focused,
          cleanup: record.cleanupOutcome,
          destination: record.destination
        )
      )
    } catch {
      guard await continueCapture(id) else { return }
      record.insertionOutcome = .unsaved
      guard let durable = await updateHistory(record, captureID: id, enabled: savesHistory)
      else { return }
      await unsaved(
        id,
        text: text,
        historyIsDurable: durable || historyIsDurable,
        failureStage: .save
      )
    }
  }

  private func finishSmart(
    _ id: UUID,
    text: String,
    record: DictationHistoryRecord,
    savesHistory: Bool,
    historyIsDurable: Bool
  ) async {
    guard await continueCapture(id) else { return }
    var record = record
    setPhase(.routing)
    let candidates = saver.activeDestinations()
    let inbox = candidates.first {
      $0.destination.title.caseInsensitiveCompare("Inbox") == .orderedSame
    }
    guard var activeCapture = capture, activeCapture.id == id else { return }
    recordMeasurement(.routingRequested, at: clock.now(), captureID: id)
    let routingTask = Task { [router] in
      await router.route(
        transcript: text,
        candidates: candidates,
        inboxID: inbox?.destination.noteID
      )
    }
    activeCapture.routingTask = routingTask
    capture = activeCapture
    let routingDecision = await routingTask.value
    if var latest = capture, latest.id == id {
      latest.routingTask = nil
      capture = latest
    }
    guard await continueCapture(id) else { return }
    recordMeasurement(.routingDecision, at: clock.now(), captureID: id)
    let ambiguityChoices: [DictationRoutingChoice]?
    let destinationID: UUID?
    switch routingDecision {
    case .resolved(let routedID)
      where routedID != inbox?.destination.noteID
        && candidates.contains(where: { $0.destination.noteID == routedID }):
      destinationID = routedID
      ambiguityChoices = nil
    case .ambiguous(let choices):
      destinationID = inbox?.destination.noteID
      ambiguityChoices = choices
    default:
      destinationID = inbox?.destination.noteID
      ambiguityChoices = nil
    }

    do {
      // A receipt is the save commit boundary: a later cancellation must compensate it.
      publishSaveContext(captureID: id)
      let receipt = try await saver.saveSmartCapture(
        text: text,
        captureID: id,
        destinationID: destinationID
      )
      let saveCompletedAt = clock.now()
      recordMeasurement(.insertionCommitted, at: saveCompletedAt, captureID: id)
      recordMeasurement(.persistenceCompleted, at: saveCompletedAt, captureID: id)
      record.insertionOutcome = .saved
      let createdInbox = destinationID == nil
        ? DictationDestination(noteID: receipt.noteID, title: "Inbox")
        : nil
      record.destination = candidates.first {
        $0.destination.noteID == receipt.noteID
      }?.destination ?? createdInbox
      if isCancellationRequested(id) {
        await cancelCommittedSmartCapture(
          id,
          record: record,
          text: text,
          receipt: receipt,
          candidates: candidates,
          savesHistory: savesHistory
        )
        return
      }
      guard isActive(id) else { return }
      recoveryReceipt = receipt
      recoveryAction = .undo
      if savesHistory {
        _ = await historyController.save(record)
      }
      if isCancellationRequested(id) {
        await cancelCommittedSmartCapture(
          id,
          record: record,
          text: text,
          receipt: receipt,
          candidates: candidates,
          savesHistory: savesHistory
        )
        return
      }
      guard isActive(id) else { return }
      if let ambiguityChoices,
        receipt.noteID == (inbox?.destination.noteID ?? createdInbox?.noteID)
      {
        let ambiguity = DictationRoutingAmbiguity(
          captureID: id,
          choices: Array(ambiguityChoices.prefix(4))
        )
        pendingRoutingAmbiguity = PendingRoutingAmbiguity(
          ambiguity: ambiguity,
          receipt: receipt,
          record: record,
          inboxID: receipt.noteID,
          savesHistory: savesHistory
        )
        routingAmbiguity = ambiguity
        recordMeasurement(.ambiguityPresented, at: clock.now(), captureID: id)
      }
      if let destination = record.destination {
        await terminate(
          id,
          phase: .saved(destination),
          cancelEditor: false,
          outcome: .saved(
            mode: .smartCapture,
            cleanup: record.cleanupOutcome,
            destination: destination
          )
        )
      } else {
        await terminate(
          id,
          phase: .idle,
          cancelEditor: false,
          outcome: .saved(
            mode: .smartCapture,
            cleanup: record.cleanupOutcome,
            destination: nil
          )
        )
      }
    } catch {
      guard await continueCapture(id) else { return }
      record.insertionOutcome = .unsaved
      record.destination = candidates.first { $0.destination.noteID == destinationID }?.destination
      guard let durable = await updateHistory(record, captureID: id, enabled: savesHistory)
      else { return }
      await unsaved(
        id,
        text: text,
        historyIsDurable: durable || historyIsDurable,
        failureStage: .save
      )
    }
  }

  private func unsaved(
    _ id: UUID,
    text: String,
    historyIsDurable: Bool,
    failureStage: DictationPipelineStage
  ) async {
    guard let capture, capture.id == id else { return }
    if historyIsDurable {
      recoveryAction = .openHistory
    } else {
      copyableTranscript = text
      recoveryAction = .copy
    }
    await terminate(
      id,
      phase: .failed("Unable to save dictation."),
      cancelEditor: capture.mode == .focused,
      failureStage: failureStage
    )
  }

  private func preserveFailedUndoRecovery(
    _ id: UUID,
    record: DictationHistoryRecord,
    text: String,
    receipt: DictationInsertionReceipt,
    candidates: [DictationRoutingCandidate],
    savesHistory: Bool
  ) async {
    guard let capture, capture.id == id, !capture.isTerminating else { return }
    var record = record
    record.insertionOutcome = .saved
    record.destination = candidates.first { $0.destination.noteID == receipt.noteID }?.destination
    if savesHistory { await historyController.save(record) }
    guard self.capture?.id == id else { return }
    recoveryReceipt = receipt
    copyableTranscript = text
    recoveryAction = .openDestination(receipt.noteID)
    await terminate(
      id,
      phase: .failed("Dictation was saved but could not be undone."),
      cancelEditor: false
    )
  }

  private func cancelCommittedSmartCapture(
    _ id: UUID,
    record: DictationHistoryRecord,
    text: String,
    receipt: DictationInsertionReceipt,
    candidates: [DictationRoutingCandidate],
    savesHistory: Bool
  ) async {
    guard isCancellationRequested(id) else { return }
    if await saver.undoSmartCapture(receipt) {
      recordMeasurement(.compensationCompleted, at: clock.now(), captureID: id)
      recoveryReceipt = nil
      recoveryAction = nil
      clearRoutingAmbiguity(captureID: id)
      await completeCancellation(id)
    } else {
      await preserveFailedUndoRecovery(
        id,
        record: record,
        text: text,
        receipt: receipt,
        candidates: candidates,
        savesHistory: savesHistory
      )
    }
  }

  private func updateHistory(
    _ record: DictationHistoryRecord,
    captureID: UUID,
    enabled: Bool
  ) async -> Bool? {
    guard enabled else {
      return await continueCapture(captureID) ? false : nil
    }
    let saved = await historyController.save(record)
    return await continueCapture(captureID) ? saved : nil
  }

  private func completeCancellation(_ id: UUID) async {
    guard isCancellationRequested(id) else { return }
    guard let capture, capture.id == id else { return }
    if capture.processingSession != nil {
      await cancelProcessingSession(id)
      guard let current = self.capture, current.id == id, !current.isTerminating else {
        return
      }
    }
    guard let current = self.capture, current.id == id else { return }
    guard current.focusedCommitReceipt == nil
      || current.focusedEditorRollbackSucceeded
    else {
      await failUnsafeFocusedCancellation(id)
      return
    }
    guard await compensateFocusedPersistence(id) else {
      await failUnsafeFocusedCancellation(id)
      return
    }
    await terminate(id, phase: .idle, cancelEditor: true, deleteHistory: true)
    recordMeasurement(.cancellationDrained, at: clock.now(), captureID: id)
    freezeMeasurements(captureID: id)
  }

  private func cancelProcessingSession(_ id: UUID) async {
    guard var capture, capture.id == id,
      let session = capture.processingSession
    else { return }
    if let task = capture.processingSessionCancellationTask {
      await task.value
      return
    }
    let task = Task { @MainActor [weak self, session] in
      await session.cancel()
      await self?.drainProcessingUpdates(id)
    }
    capture.processingSessionCancellationTask = task
    self.capture = capture
    await task.value
  }

  private func failUnsafeFocusedCancellation(_ id: UUID) async {
    guard let capture, capture.id == id else { return }
    if let noteID = capture.destination?.noteID {
      recoveryAction = .openDestination(noteID)
    }
    await terminate(
      id,
      phase: .failed("Dictation could not be cancelled safely. The text was preserved."),
      cancelEditor: false
    )
  }

  private func terminate(
    _ id: UUID,
    phase: DictationPhase,
    cancelEditor: Bool,
    deleteHistory: Bool = false,
    outcome: DictationTerminalOutcome? = nil,
    failureStage: DictationPipelineStage? = nil
  ) async {
    guard var capture, capture.id == id, !capture.isTerminating else { return }
    capture.isTerminating = true
    self.capture = capture
    if cancelEditor { rollbackEditor(id) }
    var terminalPhase = phase
    var terminalOutcome = outcome
    var terminalFailureStage = failureStage
    if deleteHistory, !(await historyController.delete(id)) {
      let message = "Dictation cancellation could not remove its History transcript."
      recoveryAction = .openHistory
      terminalPhase = .failed(message)
      terminalOutcome = .failed(message)
      terminalFailureStage = nil
    }
    guard let current = self.capture, current.id == id else { return }
    let terminalContext = contextForCapture(
      current,
      failureStage: terminalFailureStage
    )
    if let engine = current.engine { await release(engine) }
    guard self.capture?.id == id else { return }
    self.capture = nil
    levelObserver?(0)
    completeShortcutSession(id)
    let resolvedOutcome = terminalOutcome ?? inferredTerminalOutcome(for: terminalPhase)
    publishTerminal(
      phase: terminalPhase,
      outcome: resolvedOutcome,
      context: terminalContext
    )
  }

  private func release(_ engine: any SpeechEngine) async {
    await engine.cancel()
    await engine.releaseResources()
  }

  private func continueCapture(_ id: UUID) async -> Bool {
    guard let capture, capture.id == id, !capture.isTerminating else { return false }
    guard capture.cancelRequested else { return true }
    await completeCancellation(id)
    return false
  }

  private func finishStarting(_ id: UUID) -> Capture? {
    guard var capture, capture.id == id else { return nil }
    capture.isStarting = false
    self.capture = capture
    return capture
  }

  private func handleStartupFailure(_ id: UUID, error: Error) async {
    guard let current = finishStarting(id) else { return }
    if current.cancelRequested {
      await completeCancellation(id)
      return
    }
    if current.holdAccepted {
      await terminate(
        id,
        phase: .failed(message(for: error)),
        cancelEditor: current.mode == .focused,
        failureStage: .capture
      )
    } else {
      guard var active = capture, active.id == id else { return }
      active.deferredStartupFailureMessage = message(for: error)
      let physicalReleaseAccepted = active.physicalReleaseReceipt?.isShort == false
      capture = active
      if physicalReleaseAccepted {
        acceptArmedShortcut(id)
      }
    }
  }

  private func completeDeferredStartupFailure(
    _ id: UUID,
    message: String,
    cancelEditor: Bool
  ) async {
    guard let current = capture, current.id == id, !current.cancelRequested else { return }
    if let engine = current.engine {
      await release(engine)
    }
    guard var active = capture, active.id == id else { return }
    active.engine = nil
    capture = active
    guard !Task.isCancelled, !active.cancelRequested else { return }
    clearPreviousPresentation()
    await terminate(
      id,
      phase: .failed(message),
      cancelEditor: cancelEditor,
      failureStage: .capture
    )
  }

  private func setStarting(_ id: UUID, _ isStarting: Bool) {
    guard var capture, capture.id == id else { return }
    capture.isStarting = isStarting
    self.capture = capture
  }

  private func rollbackEditor(_ id: UUID) {
    guard var capture, capture.id == id, !capture.editorCancelled else { return }
    if let receipt = capture.focusedCommitReceipt {
      capture.focusedEditorRollbackSucceeded =
        capture.editor?.rollbackCommittedFocusedDictation(receipt) == true
    } else {
      capture.editor?.cancelFocusedDictation()
      capture.focusedEditorRollbackSucceeded = true
    }
    capture.editorCancelled = true
    self.capture = capture
  }

  private func compensateFocusedPersistence(_ id: UUID) async -> Bool {
    guard let current = capture, current.id == id else { return false }
    guard let receipt = current.focusedPersistenceReceipt else { return true }
    guard !current.focusedPersistenceCompensated else { return true }
    guard current.focusedEditorRollbackSucceeded else { return false }
    let compensated = await saver.compensateFocusedDictationSave(receipt)
    if compensated {
      recordMeasurement(.compensationCompleted, at: clock.now(), captureID: id)
    }
    guard var latest = capture, latest.id == id else { return false }
    latest.focusedPersistenceCompensated = compensated
    capture = latest
    return compensated
  }

  private func setFocusedCommitReceipt(
    _ receipt: FocusedDictationCommitReceipt,
    captureID: UUID
  ) {
    guard var capture, capture.id == captureID else { return }
    capture.focusedCommitReceipt = receipt
    self.capture = capture
  }

  private func setFocusedPersistenceReceipt(
    _ receipt: FocusedDictationPersistenceReceipt,
    captureID: UUID
  ) {
    guard var capture, capture.id == captureID else { return }
    capture.focusedPersistenceReceipt = receipt
    self.capture = capture
  }

  private func setPipelineStage(
    _ stage: DictationPipelineStage,
    captureID: UUID
  ) {
    guard var capture, capture.id == captureID else { return }
    capture.pipelineStage = stage
    self.capture = capture
  }

  private func setCleanupOutcome(
    _ cleanupOutcome: DictationCleanupOutcome,
    captureID: UUID
  ) {
    guard var capture, capture.id == captureID else { return }
    capture.cleanupOutcome = cleanupOutcome
    self.capture = capture
  }

  private func publishSaveContext(captureID: UUID) {
    guard var capture, capture.id == captureID, !capture.isTerminating else { return }
    capture.pipelineStage = .save
    self.capture = capture
    eventObserver?(DictationCoordinatorEvent(
      phase: phase,
      terminal: nil,
      context: contextForCapture(capture)
    ))
  }

  private func finalizeFocusedCommit(_ id: UUID) {
    guard let capture, capture.id == id,
      let receipt = capture.focusedCommitReceipt
    else { return }
    capture.editor?.finalizeCommittedFocusedDictation(receipt)
  }

  private func isActive(_ id: UUID) -> Bool {
    guard let capture, capture.id == id else { return false }
    return !capture.cancelRequested && !capture.isTerminating
  }

  private func isCancellationRequested(_ id: UUID) -> Bool {
    capture?.id == id && capture?.cancelRequested == true
  }

  private func nonempty(_ text: String?) -> String? {
    guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return text
  }

  func performRecoveryAction() async -> DictationRecoveryResult? {
    guard canConfigureShortcut, let action = recoveryAction else { return nil }
    recoveryOperationInFlight = true
    recoveryAction = nil
    defer { recoveryOperationInFlight = false }
    switch action {
    case .undo:
      guard let receipt = recoveryReceipt else { return nil }
      if await saver.undoSmartCapture(receipt) {
        recordMeasurement(.compensationCompleted, at: clock.now(), captureID: receipt.captureID)
        recoveryReceipt = nil
        copyableTranscript = nil
        clearRoutingAmbiguity(captureID: receipt.captureID)
        guard await historyController.delete(receipt.captureID) else {
          recoveryAction = .openHistory
          return .openHistory
        }
        return .completed
      }
      recoveryAction = .openDestination(receipt.noteID)
      return .openDestination(receipt.noteID)
    case .copy:
      guard let copyableTranscript else { return nil }
      return .copy(copyableTranscript)
    case .openHistory:
      return .openHistory
    case .openDestination(let noteID):
      return .openDestination(noteID)
    }
  }

  func chooseDestination(
    captureID: UUID,
    noteID: UUID?
  ) async -> DictationDestinationChoiceResult? {
    guard canConfigureShortcut,
      var pending = pendingRoutingAmbiguity,
      pending.ambiguity.captureID == captureID,
      pending.receipt.captureID == captureID,
      recoveryReceipt == pending.receipt
    else { return nil }

    recoveryOperationInFlight = true
    defer { recoveryOperationInFlight = false }

    guard let noteID else {
      guard pending.receipt.noteID == pending.inboxID else { return nil }
      clearRoutingAmbiguity(captureID: captureID)
      return .completed
    }
    guard let requestedChoice = pending.ambiguity.choices.first(where: {
      $0.destination.noteID == noteID
    }) else { return nil }

    let activeDestinations = saver.activeDestinations()
    let activeChoices = pending.ambiguity.choices.filter { choice in
      activeDestinations.contains { $0.destination == choice.destination }
    }
    if activeChoices != pending.ambiguity.choices {
      pending.ambiguity = .init(captureID: captureID, choices: activeChoices)
      pendingRoutingAmbiguity = pending
      routingAmbiguity = pending.ambiguity
    }

    let currentTitle = pending.record.destination?.title ?? "Inbox"
    let savedSummary = pending.record.cleanupOutcome == .cleaned
      ? "Still saved to \(currentTitle)."
      : "Still saved to \(currentTitle) without cleanup."
    let visibleSavedSummary = pending.record.cleanupOutcome == .cleaned
      ? "\(currentTitle) saved"
      : "\(currentTitle) saved raw"
    let canKeepCurrent = pending.receipt.noteID == pending.inboxID
    guard let choice = activeChoices.first(where: {
      $0.destination == requestedChoice.destination
    }) else {
      let hasAlternative = !activeChoices.isEmpty
      let recovery: String
      let visibleRecovery: String
      if hasAlternative {
        recovery = canKeepCurrent
          ? "Choose another note or keep this dictation in Inbox."
          : "Choose another note."
        visibleRecovery = "retry"
      } else if canKeepCurrent {
        recovery = "Keep this dictation in Inbox or use Undo."
        visibleRecovery = "keep/undo"
      } else {
        recovery = "Use Undo to recover this dictation."
        visibleRecovery = "undo"
      }
      return .failed(
        status: "\(visibleSavedSummary) · \(visibleRecovery)",
        message: "\(savedSummary) \(requestedChoice.destination.title) is no longer available. \(recovery)"
      )
    }

    if pending.receipt.noteID != noteID {
      guard let movedReceipt = await saver.moveSmartCapture(
        pending.receipt,
        to: noteID
      ), movedReceipt.captureID == captureID,
        movedReceipt.noteID == noteID
      else {
        let recovery = canKeepCurrent
          ? "Choose a destination to retry or keep this dictation in Inbox."
          : "Choose a destination to retry."
        return .failed(
          status: "\(visibleSavedSummary) · retry",
          message: "\(savedSummary) Could not move to \(choice.destination.title). \(recovery)"
        )
      }
      recordMeasurement(.ambiguityMoved, at: clock.now(), captureID: captureID)
      pending.receipt = movedReceipt
      pending.record.destination = choice.destination
      pendingRoutingAmbiguity = pending
      recoveryReceipt = movedReceipt
      recoveryAction = .undo
      setPhase(.saved(choice.destination))
    }

    if pending.savesHistory,
      !(await historyController.save(pending.record))
    {
      pendingRoutingAmbiguity = pending
      routingAmbiguity = pending.ambiguity
      let movedSummary = pending.record.cleanupOutcome == .cleaned
        ? "Still saved to \(choice.destination.title)."
        : "Still saved to \(choice.destination.title) without cleanup."
      let visibleMovedSummary = pending.record.cleanupOutcome == .cleaned
        ? "\(choice.destination.title) saved"
        : "\(choice.destination.title) saved raw"
      return .failed(
        status: "\(visibleMovedSummary) · retry",
        message: "\(movedSummary) Dictation History could not be updated. Retry \(choice.destination.title) or choose another note."
      )
    }
    clearRoutingAmbiguity(captureID: captureID)
    return .completed
  }

  private func clearRoutingAmbiguity(captureID: UUID) {
    guard pendingRoutingAmbiguity?.ambiguity.captureID == captureID else { return }
    pendingRoutingAmbiguity = nil
    routingAmbiguity = nil
  }

  private func recordMeasurement(
    _ stage: DictationRuntimeMeasurements.Stage,
    at instant: ContinuousClock.Instant,
    captureID: UUID
  ) {
    guard latestMeasurementCaptureID == captureID else { return }
    latestRuntimeMeasurements = latestRuntimeMeasurements.recording(stage, at: instant)
  }

  private func overlay(
    _ measurements: DictationRuntimeMeasurements,
    captureID: UUID
  ) {
    guard latestMeasurementCaptureID == captureID else { return }
    latestRuntimeMeasurements = latestRuntimeMeasurements.overlaying(measurements)
  }

  private func freezeMeasurements(captureID: UUID) {
    guard latestMeasurementCaptureID == captureID else { return }
    latestRuntimeMeasurements = latestRuntimeMeasurements.terminal()
  }

  private func message(for error: Error) -> String {
    if case StreamingDictationProcessorError.noSpeech = error {
      return "No speech detected."
    }
    return (error as NSError).localizedDescription
  }

  private func completeShortcutSession(_ id: UUID) {
    guard activeShortcutSessions.remove(id) != nil else { return }
    let waiters = shortcutTerminalWaiters.removeValue(forKey: id) ?? []
    waiters.forEach { $0.resume() }
  }

  private func setPhase(_ phase: DictationPhase) {
    if let pipelineStage = pipelineStage(for: phase), var capture {
      capture.pipelineStage = pipelineStage
      self.capture = capture
    }
    guard self.phase != phase else { return }
    self.phase = phase
    eventObserver?(DictationCoordinatorEvent(
      phase: phase,
      terminal: nil,
      context: currentContext()
    ))
  }

  private func publishTerminal(
    phase: DictationPhase,
    outcome: DictationTerminalOutcome,
    context: DictationCoordinatorContext? = nil
  ) {
    self.phase = phase
    eventObserver?(DictationCoordinatorEvent(
      phase: phase,
      terminal: outcome,
      context: context
    ))
    let waiters = terminalWaiters
    terminalWaiters.removeAll()
    waiters.forEach { $0.resume() }
  }

  private func inferredTerminalOutcome(for phase: DictationPhase) -> DictationTerminalOutcome {
    if case .failed(let message) = phase {
      return .failed(message)
    }
    return .cancelled
  }

  private func pipelineStage(for phase: DictationPhase) -> DictationPipelineStage? {
    switch phase {
    case .arming, .listening, .finalizing:
      return .capture
    case .cleaning:
      return .polish
    case .routing:
      return .organize
    case .saved:
      return .save
    case .idle, .failed:
      return nil
    }
  }

  private func currentContext() -> DictationCoordinatorContext? {
    if let capture {
      return contextForCapture(capture)
    }
    return nil
  }

  private func contextForCapture(
    _ capture: Capture,
    failureStage: DictationPipelineStage? = nil
  ) -> DictationCoordinatorContext {
    DictationCoordinatorContext(
      sessionID: capture.id,
      mode: capture.mode,
      pipelineStage: capture.pipelineStage,
      cleanupOutcome: capture.cleanupOutcome,
      failureStage: failureStage
    )
  }
}
