import Foundation
import MenuBarNotesCore

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

struct DictationShortcutSession: Equatable, Hashable, Sendable {
  let id: UUID
}

@MainActor
final class DictationCoordinator {
  private struct Capture {
    let id: UUID
    let mode: DictationMode
    let editor: (any FocusedDictationEditing)?
    let startedAt: Date
    var engine: (any SpeechEngine)?
    var isStarting = true
    var isFinishing = false
    var releaseRequested = false
    var cancelRequested = false
    var isTerminating = false
    var editorCancelled = false
  }

  private let engineProvider: any SpeechEngineProviding
  private let preferredEngine: @MainActor () -> DictationSpeechEngine
  private let cleaner: any TranscriptCleaning
  private let router: any DestinationRouting
  private let saver: any DictationSaving
  private let historyStore: DictationHistoryStore
  private let historyEnabled: @MainActor () -> Bool
  private let holdThreshold: Duration
  private let holdSleeper: @Sendable (Duration) async -> Void

  private var capture: Capture?
  private var shortcutID: UUID?
  private var shortcutEditor: (any FocusedDictationEditing)?
  private var holdTask: Task<Void, Never>?
  private var activeShortcutSessions = Set<UUID>()
  private var shortcutTerminalWaiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]

  private(set) var phase: DictationPhase = .idle
  private(set) var copyableTranscript: String?
  private(set) var recoveryReceipt: DictationInsertionReceipt?

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
    self.historyStore = historyStore
    self.historyEnabled = historyEnabled
    self.holdThreshold = holdThreshold
    self.holdSleeper = holdSleeper
  }

  @discardableResult
  func beginShortcut(editor: (any FocusedDictationEditing)?) -> DictationShortcutSession? {
    guard capture == nil, shortcutID == nil else { return nil }
    let id = UUID()
    shortcutID = id
    shortcutEditor = editor
    activeShortcutSessions.insert(id)
    phase = .arming
    holdTask = Task { [weak self, holdSleeper, holdThreshold] in
      await holdSleeper(holdThreshold)
      guard !Task.isCancelled else { return }
      await self?.holdThresholdElapsed(id)
    }
    return DictationShortcutSession(id: id)
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
      holdTask?.cancel()
      holdTask = nil
      phase = .idle
      completeShortcutSession(session.id)
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

  func start(mode: DictationMode, editor: (any FocusedDictationEditing)? = nil) async {
    await startCapture(id: UUID(), mode: mode, editor: editor)
  }

  private func startCapture(
    id: UUID,
    mode: DictationMode,
    editor: (any FocusedDictationEditing)?
  ) async {
    guard capture == nil, shortcutID == nil else { return }
    copyableTranscript = nil
    recoveryReceipt = nil
    phase = .arming

    let focusedEditor = mode == .focused ? editor : nil
    capture = Capture(id: id, mode: mode, editor: focusedEditor, startedAt: Date())
    guard mode != .focused || (
      focusedEditor?.canBeginFocusedDictation == true && focusedEditor?.beginFocusedDictation() == true
    ) else {
      capture = nil
      phase = .failed("Unable to begin focused dictation.")
      completeShortcutSession(id)
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
    phase = .listening(mode: mode, engine: engine.kind)
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
    phase = .finalizing

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
      insertionOutcome: .pending
    )
    guard await updateHistory(record, captureID: capture.id, enabled: savesHistory) else { return }

    phase = .cleaning
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
      await finishFocused(capture.id, text: cleanedText, record: record, savesHistory: savesHistory)
    } else {
      await finishSmart(capture.id, text: cleanedText, record: record, savesHistory: savesHistory)
    }
  }

  func cancel() async {
    if let id = shortcutID {
      shortcutID = nil
      shortcutEditor = nil
      holdTask?.cancel()
      holdTask = nil
      phase = .idle
      completeShortcutSession(id)
    }
    guard var capture, !capture.isTerminating, !capture.cancelRequested else { return }
    capture.cancelRequested = true
    self.capture = capture
    rollbackEditor(capture.id)
    try? await historyStore.delete(id: capture.id)
    guard let current = self.capture, current.id == capture.id, !current.isTerminating else { return }
    guard !current.isStarting, !current.isFinishing else { return }
    await completeCancellation(capture.id)
  }

  private func holdThresholdElapsed(_ id: UUID) async {
    guard shortcutID == id else { return }
    let editor = shortcutEditor
    shortcutID = nil
    shortcutEditor = nil
    holdTask = nil
    await startCapture(
      id: id,
      mode: editor == nil ? .smartCapture : .focused,
      editor: editor
    )
  }

  private func finishFocused(
    _ id: UUID,
    text: String,
    record: DictationHistoryRecord,
    savesHistory: Bool
  ) async {
    guard let capture, capture.id == id else { return }
    var record = record
    guard capture.editor?.commitFocusedDictation(text: text) == true else {
      record.insertionOutcome = .unsaved
      guard await updateHistory(record, captureID: id, enabled: savesHistory) else { return }
      await unsaved(id, text: text, savesHistory: savesHistory)
      return
    }
    do {
      try await saver.flushFocusedDictationSave()
      guard await continueCapture(id) else { return }
      record.insertionOutcome = .saved
      guard await updateHistory(record, captureID: id, enabled: savesHistory) else { return }
      await terminate(id, phase: .idle, cancelEditor: false)
    } catch {
      guard await continueCapture(id) else { return }
      record.insertionOutcome = .unsaved
      guard await updateHistory(record, captureID: id, enabled: savesHistory) else { return }
      await unsaved(id, text: text, savesHistory: savesHistory)
    }
  }

  private func finishSmart(
    _ id: UUID,
    text: String,
    record: DictationHistoryRecord,
    savesHistory: Bool
  ) async {
    guard await continueCapture(id) else { return }
    var record = record
    phase = .routing
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
      if isCancellationRequested(id) {
        if await saver.undoSmartCapture(receipt) {
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
        return
      }
      guard isActive(id) else { return }
      record.insertionOutcome = .saved
      record.destination = candidates.first { $0.noteID == receipt.noteID }
      guard await updateHistory(record, captureID: id, enabled: savesHistory) else { return }
      if let destination = record.destination {
        await terminate(id, phase: .saved(destination), cancelEditor: false)
      } else {
        await terminate(id, phase: .idle, cancelEditor: false)
      }
    } catch {
      guard await continueCapture(id) else { return }
      record.insertionOutcome = .unsaved
      record.destination = candidates.first { $0.noteID == destinationID }
      guard await updateHistory(record, captureID: id, enabled: savesHistory) else { return }
      await unsaved(id, text: text, savesHistory: savesHistory)
    }
  }

  private func unsaved(_ id: UUID, text: String, savesHistory: Bool) async {
    guard let capture, capture.id == id else { return }
    if !savesHistory { copyableTranscript = text }
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
    if savesHistory { try? await historyStore.save(record) }
    guard self.capture?.id == id else { return }
    recoveryReceipt = receipt
    copyableTranscript = text
    await terminate(
      id,
      phase: .failed("Dictation was saved but could not be undone."),
      cancelEditor: false
    )
  }

  private func updateHistory(
    _ record: DictationHistoryRecord,
    captureID: UUID,
    enabled: Bool
  ) async -> Bool {
    guard enabled else { return await continueCapture(captureID) }
    try? await historyStore.save(record)
    return await continueCapture(captureID)
  }

  private func completeCancellation(_ id: UUID) async {
    guard isCancellationRequested(id) else { return }
    await terminate(id, phase: .idle, cancelEditor: true, deleteHistory: true)
  }

  private func terminate(
    _ id: UUID,
    phase: DictationPhase,
    cancelEditor: Bool,
    deleteHistory: Bool = false
  ) async {
    guard var capture, capture.id == id, !capture.isTerminating else { return }
    capture.isTerminating = true
    self.capture = capture
    if cancelEditor { rollbackEditor(id) }
    if deleteHistory { try? await historyStore.delete(id: id) }
    guard let current = self.capture, current.id == id else { return }
    if let engine = current.engine { await release(engine) }
    guard self.capture?.id == id else { return }
    self.capture = nil
    self.phase = phase
    completeShortcutSession(id)
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
    capture.editor?.cancelFocusedDictation()
    capture.editorCancelled = true
    self.capture = capture
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

  private func message(for error: Error) -> String {
    (error as NSError).localizedDescription
  }

  private func completeShortcutSession(_ id: UUID) {
    guard activeShortcutSessions.remove(id) != nil else { return }
    let waiters = shortcutTerminalWaiters.removeValue(forKey: id) ?? []
    waiters.forEach { $0.resume() }
  }
}
