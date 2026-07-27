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
    let engine: any SpeechEngine
    let editor: (any FocusedDictationEditing)?
    let startedAt: Date
  }

  private let engineProvider: any SpeechEngineProviding
  private let preferredEngine: @MainActor () -> DictationSpeechEngine
  private let cleaner: any TranscriptCleaning
  private let router: any DestinationRouting
  private let saver: any DictationSaving
  private let historyStore: DictationHistoryStore
  private let historyEnabled: @MainActor () -> Bool
  private let holdThreshold: Duration

  private var capture: Capture?
  private var shortcutEditor: (any FocusedDictationEditing)?
  private var shortcutPending = false

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
    holdThreshold: Duration = .milliseconds(180)
  ) {
    self.engineProvider = engineProvider
    self.preferredEngine = preferredEngine
    self.cleaner = cleaner
    self.router = router
    self.saver = saver
    self.historyStore = historyStore
    self.historyEnabled = historyEnabled
    self.holdThreshold = holdThreshold
  }

  func beginShortcut(editor: (any FocusedDictationEditing)?) {
    guard capture == nil, !shortcutPending else { return }
    shortcutPending = true
    shortcutEditor = editor
    phase = .arming
  }

  func endShortcut(heldFor: Duration) async {
    guard shortcutPending else { return }
    let editor = shortcutEditor
    shortcutPending = false
    shortcutEditor = nil
    guard heldFor >= holdThreshold else {
      phase = .idle
      return
    }
    phase = .idle
    await start(mode: editor == nil ? .smartCapture : .focused, editor: editor)
  }

  func start(mode: DictationMode, editor: (any FocusedDictationEditing)? = nil) async {
    guard capture == nil, !shortcutPending else { return }
    copyableTranscript = nil
    phase = .arming

    let focusedEditor: (any FocusedDictationEditing)?
    if mode == .focused {
      guard let editor, editor.canBeginFocusedDictation, editor.beginFocusedDictation() else {
        phase = .failed("Unable to begin focused dictation.")
        return
      }
      focusedEditor = editor
    } else {
      focusedEditor = nil
    }

    let requestedEngine = preferredEngine()
    let engine: any SpeechEngine
    do {
      engine = try await engineProvider.engineForCapture(preferred: requestedEngine)
    } catch {
      focusedEditor?.cancelFocusedDictation()
      phase = .failed(message(for: error))
      return
    }

    let id = UUID()
    let activeCapture = Capture(
      id: id,
      mode: mode,
      engine: engine,
      editor: focusedEditor,
      startedAt: Date()
    )
    capture = activeCapture
    do {
      try await engine.start(
        provisional: { [weak self] text in
          guard let self, self.capture?.id == id, mode == .focused else { return }
          self.capture?.editor?.updateFocusedDictation(provisionalText: text)
        },
        level: { _ in }
      )
      guard capture?.id == id else { return }
      phase = .listening(mode: mode, engine: engine.kind)
    } catch {
      await end(activeCapture, phase: .failed(message(for: error)), cancelEditor: true)
    }
  }

  func finish() async {
    guard let capture else { return }
    phase = .finalizing

    let rawText: String?
    do {
      rawText = try await capture.engine.finish()
    } catch {
      await end(capture, phase: .failed(message(for: error)), cancelEditor: capture.mode == .focused)
      return
    }
    guard self.capture?.id == capture.id else { return }
    guard let rawText = nonempty(rawText) else {
      await end(capture, phase: .failed("No speech detected."), cancelEditor: capture.mode == .focused)
      return
    }

    let savesHistory = historyEnabled()
    var record = DictationHistoryRecord(
      id: capture.id,
      mode: capture.mode,
      engine: capture.engine.kind,
      startedAt: capture.startedAt,
      completedAt: Date(),
      rawTranscript: rawText,
      cleanupOutcome: .pending,
      insertionOutcome: .pending
    )
    if savesHistory { try? await historyStore.save(record) }

    phase = .cleaning
    let cleanedText: String
    do {
      cleanedText = try await cleaner.clean(rawText)
      record.cleanedTranscript = cleanedText
      record.cleanupOutcome = .cleaned
    } catch {
      cleanedText = rawText
      record.cleanupOutcome = .usedRaw
    }
    guard self.capture?.id == capture.id else { return }

    if capture.mode == .focused {
      await finishFocused(capture, text: cleanedText, record: record, savesHistory: savesHistory)
    } else {
      await finishSmart(capture, text: cleanedText, record: record, savesHistory: savesHistory)
    }
  }

  func cancel() async {
    guard let capture else {
      if shortcutPending {
        shortcutPending = false
        shortcutEditor = nil
        phase = .idle
      }
      return
    }
    await end(capture, phase: .idle, cancelEditor: capture.mode == .focused)
  }

  private func finishFocused(
    _ capture: Capture,
    text: String,
    record: DictationHistoryRecord,
    savesHistory: Bool
  ) async {
    var record = record
    guard capture.editor?.commitFocusedDictation(text: text) == true else {
      record.insertionOutcome = .unsaved
      await updateHistory(record, enabled: savesHistory)
      await unsaved(capture, text: text, record: record, savesHistory: savesHistory)
      return
    }
    do {
      try await saver.flushFocusedDictationSave()
      record.insertionOutcome = .saved
      await updateHistory(record, enabled: savesHistory)
      await end(capture, phase: .idle, cancelEditor: false)
    } catch {
      record.insertionOutcome = .unsaved
      await updateHistory(record, enabled: savesHistory)
      await unsaved(capture, text: text, record: record, savesHistory: savesHistory)
    }
  }

  private func finishSmart(
    _ capture: Capture,
    text: String,
    record: DictationHistoryRecord,
    savesHistory: Bool
  ) async {
    var record = record
    phase = .routing
    let candidates = saver.activeDestinations()
    let inbox = candidates.first { $0.title.caseInsensitiveCompare("Inbox") == .orderedSame }
    let routedID = await router.route(
      transcript: text,
      candidates: candidates,
      inboxID: inbox?.noteID
    )
    let destinationID = candidates.contains { $0.noteID == routedID } ? routedID : inbox?.noteID

    do {
      let receipt = try await saver.saveSmartCapture(
        text: text,
        captureID: capture.id,
        destinationID: destinationID
      )
      record.insertionOutcome = .saved
      record.destination = candidates.first { $0.noteID == receipt.noteID }
      await updateHistory(record, enabled: savesHistory)
      if let destination = record.destination {
        await end(capture, phase: .saved(destination), cancelEditor: false)
      } else {
        await end(capture, phase: .idle, cancelEditor: false)
      }
    } catch {
      record.insertionOutcome = .unsaved
      record.destination = candidates.first { $0.noteID == destinationID }
      await updateHistory(record, enabled: savesHistory)
      await unsaved(capture, text: text, record: record, savesHistory: savesHistory)
    }
  }

  private func unsaved(
    _ capture: Capture,
    text: String,
    record: DictationHistoryRecord,
    savesHistory: Bool
  ) async {
    if !savesHistory { copyableTranscript = text }
    await end(capture, phase: .failed("Unable to save dictation."), cancelEditor: false)
  }

  private func updateHistory(_ record: DictationHistoryRecord, enabled: Bool) async {
    guard enabled else { return }
    try? await historyStore.save(record)
  }

  private func end(_ capture: Capture, phase: DictationPhase, cancelEditor: Bool) async {
    guard self.capture?.id == capture.id else { return }
    self.capture = nil
    if cancelEditor { capture.editor?.cancelFocusedDictation() }
    await capture.engine.cancel()
    await capture.engine.releaseResources()
    self.phase = phase
  }

  private func nonempty(_ text: String?) -> String? {
    guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return text
  }

  private func message(for error: Error) -> String {
    (error as NSError).localizedDescription
  }
}
