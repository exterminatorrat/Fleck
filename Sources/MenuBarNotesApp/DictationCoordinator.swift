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

@MainActor
final class DictationCoordinator {
  private struct Capture {
    let id: UUID
    let mode: DictationMode
    let editor: (any FocusedDictationEditing)?
    let startedAt: Date
    var engine: (any SpeechEngine)?
    var isFinishing = false
    var releaseRequested = false
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

  private(set) var phase: DictationPhase = .idle
  private(set) var copyableTranscript: String?

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

  func beginShortcut(editor: (any FocusedDictationEditing)?) {
    guard capture == nil, shortcutID == nil else { return }
    let id = UUID()
    shortcutID = id
    shortcutEditor = editor
    phase = .arming
    holdTask = Task { [weak self, holdSleeper, holdThreshold] in
      await holdSleeper(holdThreshold)
      guard !Task.isCancelled else { return }
      await self?.holdThresholdElapsed(id)
    }
  }

  func endShortcut() async {
    if shortcutID != nil {
      shortcutID = nil
      shortcutEditor = nil
      holdTask?.cancel()
      holdTask = nil
      phase = .idle
      return
    }
    await finish()
  }

  func start(mode: DictationMode, editor: (any FocusedDictationEditing)? = nil) async {
    guard capture == nil, shortcutID == nil else { return }
    copyableTranscript = nil
    phase = .arming

    let id = UUID()
    let focusedEditor = mode == .focused ? editor : nil
    capture = Capture(id: id, mode: mode, editor: focusedEditor, startedAt: Date())
    guard mode != .focused || (
      focusedEditor?.canBeginFocusedDictation == true && focusedEditor?.beginFocusedDictation() == true
    ) else {
      capture = nil
      phase = .failed("Unable to begin focused dictation.")
      return
    }

    let engine: any SpeechEngine
    do {
      engine = try await engineProvider.engineForCapture(preferred: preferredEngine())
    } catch {
      guard isCurrent(id) else { return }
      await end(id, phase: .failed(message(for: error)), cancelEditor: mode == .focused)
      return
    }
    guard var activeCapture = capture, activeCapture.id == id else {
      await release(engine)
      return
    }
    activeCapture.engine = engine
    capture = activeCapture
    if activeCapture.releaseRequested {
      await end(id, phase: .failed("No speech detected."), cancelEditor: mode == .focused)
      return
    }

    do {
      try await engine.start(
        provisional: { [weak self] text in
          guard let self, self.isCurrent(id), mode == .focused else { return }
          self.capture?.editor?.updateFocusedDictation(provisionalText: text)
        },
        level: { _ in }
      )
      guard let current = capture, current.id == id else { return }
      phase = .listening(mode: mode, engine: engine.kind)
      if current.releaseRequested { await finish() }
    } catch {
      guard isCurrent(id) else { return }
      await end(id, phase: .failed(message(for: error)), cancelEditor: mode == .focused)
    }
  }

  func finish() async {
    guard var capture, !capture.isFinishing else { return }
    guard let engine = capture.engine else {
      capture.releaseRequested = true
      self.capture = capture
      return
    }
    capture.isFinishing = true
    self.capture = capture
    phase = .finalizing

    let rawText: String?
    do {
      rawText = try await engine.finish()
    } catch {
      guard isCurrent(capture.id) else { return }
      await end(capture.id, phase: .failed(message(for: error)), cancelEditor: capture.mode == .focused)
      return
    }
    guard isCurrent(capture.id) else { return }
    guard let rawText = nonempty(rawText) else {
      await end(capture.id, phase: .failed("No speech detected."), cancelEditor: capture.mode == .focused)
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
      guard isCurrent(capture.id) else { return }
      record.cleanedTranscript = cleanedText
      record.cleanupOutcome = .cleaned
    } catch {
      guard isCurrent(capture.id) else { return }
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
    if shortcutID != nil {
      shortcutID = nil
      shortcutEditor = nil
      holdTask?.cancel()
      holdTask = nil
      phase = .idle
    }
    guard let capture else { return }
    await end(capture.id, phase: .idle, cancelEditor: capture.mode == .focused)
  }

  private func holdThresholdElapsed(_ id: UUID) async {
    guard shortcutID == id else { return }
    let editor = shortcutEditor
    shortcutID = nil
    shortcutEditor = nil
    holdTask = nil
    await start(mode: editor == nil ? .smartCapture : .focused, editor: editor)
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
      guard isCurrent(id) else { return }
      record.insertionOutcome = .saved
      guard await updateHistory(record, captureID: id, enabled: savesHistory) else { return }
      await end(id, phase: .idle, cancelEditor: false)
    } catch {
      guard isCurrent(id) else { return }
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
    guard isCurrent(id) else { return }
    var record = record
    phase = .routing
    let candidates = saver.activeDestinations()
    let inbox = candidates.first { $0.title.caseInsensitiveCompare("Inbox") == .orderedSame }
    let routedID = await router.route(
      transcript: text,
      candidates: candidates,
      inboxID: inbox?.noteID
    )
    guard isCurrent(id) else { return }
    let destinationID = candidates.contains { $0.noteID == routedID } ? routedID : inbox?.noteID

    do {
      let receipt = try await saver.saveSmartCapture(
        text: text,
        captureID: id,
        destinationID: destinationID
      )
      guard isCurrent(id) else { return }
      record.insertionOutcome = .saved
      record.destination = candidates.first { $0.noteID == receipt.noteID }
      guard await updateHistory(record, captureID: id, enabled: savesHistory) else { return }
      if let destination = record.destination {
        await end(id, phase: .saved(destination), cancelEditor: false)
      } else {
        await end(id, phase: .idle, cancelEditor: false)
      }
    } catch {
      guard isCurrent(id) else { return }
      record.insertionOutcome = .unsaved
      record.destination = candidates.first { $0.noteID == destinationID }
      guard await updateHistory(record, captureID: id, enabled: savesHistory) else { return }
      await unsaved(id, text: text, savesHistory: savesHistory)
    }
  }

  private func unsaved(_ id: UUID, text: String, savesHistory: Bool) async {
    guard let capture, capture.id == id else { return }
    if !savesHistory { copyableTranscript = text }
    await end(id, phase: .failed("Unable to save dictation."), cancelEditor: capture.mode == .focused)
  }

  private func updateHistory(
    _ record: DictationHistoryRecord,
    captureID: UUID,
    enabled: Bool
  ) async -> Bool {
    guard enabled else { return isCurrent(captureID) }
    try? await historyStore.save(record)
    return isCurrent(captureID)
  }

  private func end(_ id: UUID, phase: DictationPhase, cancelEditor: Bool) async {
    guard let capture, capture.id == id else { return }
    self.capture = nil
    if cancelEditor { capture.editor?.cancelFocusedDictation() }
    self.phase = phase
    if let engine = capture.engine { await release(engine) }
  }

  private func release(_ engine: any SpeechEngine) async {
    await engine.cancel()
    await engine.releaseResources()
  }

  private func isCurrent(_ id: UUID) -> Bool {
    capture?.id == id
  }

  private func nonempty(_ text: String?) -> String? {
    guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return text
  }

  private func message(for error: Error) -> String {
    (error as NSError).localizedDescription
  }
}
