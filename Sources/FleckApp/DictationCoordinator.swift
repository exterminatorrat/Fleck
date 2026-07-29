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

enum DictationTerminalOutcome: Equatable {
  case saved(
    mode: DictationMode,
    cleanup: DictationCleanupOutcome,
    destination: DictationDestination?
  )
  case failed(String)
  case cancelled
}

struct DictationCoordinatorEvent: Equatable {
  let phase: DictationPhase
  let terminal: DictationTerminalOutcome?
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

@MainActor
final class DictationCoordinator {
  private struct Capture {
    let id: UUID
    let mode: DictationMode
    let editor: (any FocusedDictationEditing)?
    let destination: DictationDestination?
    let startedAt: Date
    var engine: (any SpeechEngine)?
    var isStarting = true
    var isFinishing = false
    var releaseRequested = false
    var cancelRequested = false
    var isTerminating = false
    var editorCancelled = false
    var focusedCommitReceipt: FocusedDictationCommitReceipt?
    var focusedPersistenceReceipt: FocusedDictationPersistenceReceipt?
    var focusedEditorRollbackSucceeded = false
    var focusedPersistenceCompensated = false
  }

  private let engineProvider: any SpeechEngineProviding
  private let preferredEngine: @MainActor () -> DictationSpeechEngine
  private let cleaner: any TranscriptCleaning
  private let router: any DestinationRouting
  private let saver: any DictationSaving
  private let historyController: DictationHistoryController
  private let historyEnabled: @MainActor () -> Bool
  private let holdThreshold: Duration
  private let holdSleeper: @Sendable (Duration) async -> Void

  private var capture: Capture?
  private var shortcutID: UUID?
  private var shortcutEditor: (any FocusedDictationEditing)?
  private var shortcutDestination: DictationDestination?
  private var holdTask: Task<Void, Never>?
  private var activeShortcutSessions = Set<UUID>()
  private var shortcutTerminalWaiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]
  private var terminalWaiters: [CheckedContinuation<Void, Never>] = []
  private var eventObserver: (@MainActor (DictationCoordinatorEvent) -> Void)?

  private(set) var phase: DictationPhase = .idle
  private(set) var copyableTranscript: String?
  private(set) var recoveryReceipt: DictationInsertionReceipt?
  private(set) var recoveryAction: DictationRecoveryAction?
  private(set) var recoveryOperationInFlight = false

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
    self.holdThreshold = holdThreshold
    self.holdSleeper = holdSleeper
  }

  func setEventObserver(
    _ observer: (@MainActor (DictationCoordinatorEvent) -> Void)?
  ) {
    eventObserver = observer
  }

  @discardableResult
  func beginShortcut(
    editor: (any FocusedDictationEditing)?,
    destination: DictationDestination? = nil
  ) -> DictationShortcutSession? {
    guard capture == nil, shortcutID == nil, !recoveryOperationInFlight else {
      return nil
    }
    let id = UUID()
    shortcutID = id
    shortcutEditor = editor
    shortcutDestination = destination
    activeShortcutSessions.insert(id)
    setPhase(.arming)
    holdTask = Task { [weak self, holdSleeper, holdThreshold] in
      await holdSleeper(holdThreshold)
      guard !Task.isCancelled else { return }
      await self?.holdThresholdElapsed(id)
    }
    return DictationShortcutSession(id: id)
  }

  func beginHandsFreeShortcut(
    editor: (any FocusedDictationEditing)?,
    destination: DictationDestination? = nil
  ) async -> DictationShortcutSession? {
    guard capture == nil, shortcutID == nil, !recoveryOperationInFlight else {
      return nil
    }
    let session = DictationShortcutSession(id: UUID())
    activeShortcutSessions.insert(session.id)
    let focusedEditor = editor?.canBeginFocusedDictation == true ? editor : nil
    await startCapture(
      id: session.id,
      mode: focusedEditor == nil ? .smartCapture : .focused,
      editor: focusedEditor,
      destination: focusedEditor == nil ? nil : destination
    )
    guard activeShortcutSessions.contains(session.id), capture?.id == session.id else {
      return nil
    }
    return session
  }

  func finishHandsFreeShortcut(_ session: DictationShortcutSession) async {
    guard activeShortcutSessions.contains(session.id), capture?.id == session.id else {
      return
    }
    await finish()
  }

  func endShortcut() async {
    if let shortcutID {
      await endShortcut(DictationShortcutSession(id: shortcutID))
      return
    }
    await finish()
  }

  func endShortcut(_ session: DictationShortcutSession) async {
    guard activeShortcutSessions.contains(session.id) else { return }
    if shortcutID == session.id {
      shortcutID = nil
      shortcutEditor = nil
      shortcutDestination = nil
      holdTask?.cancel()
      holdTask = nil
      completeShortcutSession(session.id)
      publishTerminal(phase: .idle, outcome: .cancelled)
      return
    }
    guard capture?.id == session.id else { return }
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
    destination: DictationDestination?
  ) async {
    guard capture == nil, shortcutID == nil, !recoveryOperationInFlight else {
      return
    }
    copyableTranscript = nil
    recoveryReceipt = nil
    recoveryAction = nil
    setPhase(.arming)

    let focusedEditor = mode == .focused ? editor : nil
    capture = Capture(
      id: id,
      mode: mode,
      editor: focusedEditor,
      destination: mode == .focused ? destination : nil,
      startedAt: Date()
    )
    guard mode != .focused || (
      focusedEditor?.canBeginFocusedDictation == true && focusedEditor?.beginFocusedDictation() == true
    ) else {
      capture = nil
      completeShortcutSession(id)
      publishTerminal(
        phase: .failed("Unable to begin focused dictation."),
        outcome: .failed("Unable to begin focused dictation.")
      )
      return
    }

    let engine: any SpeechEngine
    do {
      engine = try await engineProvider.engineForCapture(preferred: preferredEngine())
    } catch {
      guard finishStarting(id) != nil else { return }
      guard await continueCapture(id) else { return }
      await terminate(id, phase: .failed(message(for: error)), cancelEditor: mode == .focused)
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
    if activeCapture.releaseRequested {
      await terminate(id, phase: .failed("No speech detected."), cancelEditor: mode == .focused)
      return
    }

    setStarting(id, true)
    do {
      try await engine.start(
        provisional: { [weak self] text in
          guard let self, self.isActive(id), mode == .focused else { return }
          self.capture?.editor?.updateFocusedDictation(provisionalText: text)
        },
        level: { _ in }
      )
    } catch {
      guard finishStarting(id) != nil else { return }
      guard await continueCapture(id) else { return }
      await terminate(id, phase: .failed(message(for: error)), cancelEditor: mode == .focused)
      return
    }
    guard let current = finishStarting(id) else { return }
    guard await continueCapture(id) else { return }
    setPhase(.listening(mode: mode, engine: engine.kind))
    if current.releaseRequested { await finish() }
  }

  func finish() async {
    guard var capture, !capture.isTerminating, !capture.cancelRequested else { return }
    if capture.isStarting {
      capture.releaseRequested = true
      self.capture = capture
      return
    }
    guard !capture.isFinishing, let engine = capture.engine else { return }
    capture.isFinishing = true
    self.capture = capture
    setPhase(.finalizing)

    let rawText: String?
    do {
      rawText = try await engine.finish()
    } catch {
      guard await continueCapture(capture.id) else { return }
      await terminate(capture.id, phase: .failed(message(for: error)), cancelEditor: capture.mode == .focused)
      return
    }
    guard await continueCapture(capture.id) else { return }
    guard let rawText = nonempty(rawText) else {
      await terminate(capture.id, phase: .failed("No speech detected."), cancelEditor: capture.mode == .focused)
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
    } catch {
      guard await continueCapture(capture.id) else { return }
      cleanedText = rawText
      record.cleanupOutcome = .usedRaw
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

  func cancel() async {
    if let id = shortcutID {
      shortcutID = nil
      shortcutEditor = nil
      shortcutDestination = nil
      holdTask?.cancel()
      holdTask = nil
      completeShortcutSession(id)
      publishTerminal(phase: .idle, outcome: .cancelled)
    }
    guard var capture, !capture.isTerminating, !capture.cancelRequested else { return }
    capture.cancelRequested = true
    self.capture = capture
    rollbackEditor(capture.id)
    _ = await compensateFocusedPersistence(capture.id)
    guard let current = self.capture, current.id == capture.id, !current.isTerminating else { return }
    guard !current.isStarting, !current.isFinishing else { return }
    await completeCancellation(capture.id)
  }

  private func holdThresholdElapsed(_ id: UUID) async {
    guard shortcutID == id else { return }
    let editor = shortcutEditor
    let destination = shortcutDestination
    shortcutID = nil
    shortcutEditor = nil
    shortcutDestination = nil
    holdTask = nil
    await startCapture(
      id: id,
      mode: editor == nil ? .smartCapture : .focused,
      editor: editor,
      destination: destination
    )
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
    guard let commitReceipt = capture.editor?.commitFocusedDictation(text: text) else {
      record.insertionOutcome = .unsaved
      guard let durable = await updateHistory(record, captureID: id, enabled: savesHistory)
      else { return }
      await unsaved(id, text: text, historyIsDurable: durable || historyIsDurable)
      return
    }
    setFocusedCommitReceipt(commitReceipt, captureID: id)
    do {
      let persistenceReceipt = try await saver.flushFocusedDictationSave(captureID: id)
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
      await unsaved(id, text: text, historyIsDurable: durable || historyIsDurable)
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
    let inbox = candidates.first { $0.title.caseInsensitiveCompare("Inbox") == .orderedSame }
    let routedID = await router.route(
      transcript: text,
      candidates: candidates,
      inboxID: inbox?.noteID
    )
    guard await continueCapture(id) else { return }
    let destinationID = candidates.contains { $0.noteID == routedID } ? routedID : inbox?.noteID

    do {
      // A receipt is the save commit boundary: a later cancellation must compensate it.
      let receipt = try await saver.saveSmartCapture(
        text: text,
        captureID: id,
        destinationID: destinationID
      )
      record.insertionOutcome = .saved
      record.destination = candidates.first { $0.noteID == receipt.noteID }
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
      record.destination = candidates.first { $0.noteID == destinationID }
      guard let durable = await updateHistory(record, captureID: id, enabled: savesHistory)
      else { return }
      await unsaved(id, text: text, historyIsDurable: durable || historyIsDurable)
    }
  }

  private func unsaved(_ id: UUID, text: String, historyIsDurable: Bool) async {
    guard let capture, capture.id == id else { return }
    if historyIsDurable {
      recoveryAction = .openHistory
    } else {
      copyableTranscript = text
      recoveryAction = .copy
    }
    await terminate(id, phase: .failed("Unable to save dictation."), cancelEditor: capture.mode == .focused)
  }

  private func preserveFailedUndoRecovery(
    _ id: UUID,
    record: DictationHistoryRecord,
    text: String,
    receipt: DictationInsertionReceipt,
    candidates: [DictationDestination],
    savesHistory: Bool
  ) async {
    guard let capture, capture.id == id, !capture.isTerminating else { return }
    var record = record
    record.insertionOutcome = .saved
    record.destination = candidates.first { $0.noteID == receipt.noteID }
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
    candidates: [DictationDestination],
    savesHistory: Bool
  ) async {
    guard isCancellationRequested(id) else { return }
    if await saver.undoSmartCapture(receipt) {
      recoveryReceipt = nil
      recoveryAction = nil
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
    guard capture.focusedCommitReceipt == nil
      || capture.focusedEditorRollbackSucceeded
    else {
      await failUnsafeFocusedCancellation(id)
      return
    }
    guard await compensateFocusedPersistence(id) else {
      await failUnsafeFocusedCancellation(id)
      return
    }
    await terminate(id, phase: .idle, cancelEditor: true, deleteHistory: true)
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
    outcome: DictationTerminalOutcome? = nil
  ) async {
    guard var capture, capture.id == id, !capture.isTerminating else { return }
    capture.isTerminating = true
    self.capture = capture
    if cancelEditor { rollbackEditor(id) }
    var terminalPhase = phase
    var terminalOutcome = outcome
    if deleteHistory, !(await historyController.delete(id)) {
      let message = "Dictation cancellation could not remove its History transcript."
      recoveryAction = .openHistory
      terminalPhase = .failed(message)
      terminalOutcome = .failed(message)
    }
    guard let current = self.capture, current.id == id else { return }
    if let engine = current.engine { await release(engine) }
    guard self.capture?.id == id else { return }
    self.capture = nil
    completeShortcutSession(id)
    let resolvedOutcome = terminalOutcome ?? inferredTerminalOutcome(for: terminalPhase)
    publishTerminal(phase: terminalPhase, outcome: resolvedOutcome)
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
        recoveryReceipt = nil
        copyableTranscript = nil
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

  private func message(for error: Error) -> String {
    (error as NSError).localizedDescription
  }

  private func completeShortcutSession(_ id: UUID) {
    guard activeShortcutSessions.remove(id) != nil else { return }
    let waiters = shortcutTerminalWaiters.removeValue(forKey: id) ?? []
    waiters.forEach { $0.resume() }
  }

  private func setPhase(_ phase: DictationPhase) {
    guard self.phase != phase else { return }
    self.phase = phase
    eventObserver?(DictationCoordinatorEvent(phase: phase, terminal: nil))
  }

  private func publishTerminal(
    phase: DictationPhase,
    outcome: DictationTerminalOutcome
  ) {
    self.phase = phase
    eventObserver?(DictationCoordinatorEvent(phase: phase, terminal: outcome))
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
}
