#if os(macOS)
  import AppKit
  import Combine
  import Foundation
  import MenuBarNotesCore
  import ServiceManagement

  @MainActor
  final class AppState: ObservableObject, DictationSaving {
    enum SaveStatus: Equatable {
      case idle
      case saving
      case saved
    }

    @Published var workspace = Workspace()
    @Published var preferences = AppPreferences()
    @Published var saveError: String?
    @Published private(set) var saveStatus = SaveStatus.idle
    @Published private(set) var trashedNotes: [TrashedNote] = []

    private let store: LocalStore
    private var saveTask: Task<Void, Never>?
    private var saveStatusResetTask: Task<Void, Never>?
    private var pendingTrashNotes: [UUID: Note] = [:]

    init(store: LocalStore? = nil) {
      let appSupport = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first!
      self.store = store ?? LocalStore(rootURL: appSupport.appendingPathComponent("MenuBarNotes"))
      workspace.ensureNoteExists()
      Task { await load() }
    }

    var selectedNote: Note? {
      guard let id = workspace.selectedNoteID else { return nil }
      return workspace.notes.first(where: { $0.id == id })
    }

    func activeDestinations() -> [DictationDestination] {
      workspace.notes.map {
        DictationDestination(noteID: $0.id, title: $0.displayTitle)
      }
    }

    func saveSmartCapture(
      text: String,
      captureID: UUID,
      destinationID: UUID?
    ) async throws -> DictationInsertionReceipt {
      let destinationIndex: Int
      if let destinationID,
        let index = workspace.notes.firstIndex(where: { $0.id == destinationID })
      {
        destinationIndex = index
      } else if let index = workspace.notes.firstIndex(where: {
        $0.title.caseInsensitiveCompare("Inbox") == .orderedSame
      }) {
        destinationIndex = index
      } else {
        workspace.notes.append(Note(title: "Inbox"))
        destinationIndex = workspace.notes.index(before: workspace.notes.endIndex)
      }

      let appended = NoteTextAppender.appending(
        text,
        to: workspace.notes[destinationIndex],
        defaults: NoteTextAppendDefaults(
          fontFamily: preferences.fontFamily,
          fontSize: preferences.fontSize
        )
      )
      workspace.notes[destinationIndex].body = appended.body
      workspace.notes[destinationIndex].richTextRTF = appended.richTextRTF
      workspace.notes[destinationIndex].modifiedAt = Date()
      let noteID = workspace.notes[destinationIndex].id
      try await saveCurrentState()
      return DictationInsertionReceipt(
        captureID: captureID,
        noteID: noteID,
        insertedSuffix: appended.insertedSuffix
      )
    }

    func undoSmartCapture(_ receipt: DictationInsertionReceipt) async -> Bool {
      guard let index = workspace.notes.firstIndex(where: { $0.id == receipt.noteID }) else {
        return false
      }
      workspace.selectedNoteID = receipt.noteID
      let note = workspace.notes[index]
      guard
        !receipt.insertedSuffix.isEmpty,
        note.body.hasSuffix(receipt.insertedSuffix),
        let richTextRTF = removingSuffix(receipt.insertedSuffix, from: note.richTextRTF)
      else {
        return false
      }

      workspace.notes[index].body = String(note.body.dropLast(receipt.insertedSuffix.count))
      workspace.notes[index].richTextRTF = richTextRTF
      workspace.notes[index].modifiedAt = Date()
      do {
        try await saveCurrentState()
        return true
      } catch {
        workspace.notes[index] = note
        return false
      }
    }

    func flushFocusedDictationSave() async throws {
      try await saveCurrentState()
    }

    func select(_ id: UUID) {
      workspace.selectedNoteID = id
      scheduleSave()
    }

    func addNote() {
      workspace.addNote()
      scheduleSave()
    }

    func importNote(_ note: Note) {
      workspace.addNote(note)
      scheduleSave()
    }

    func moveToTrash(_ id: UUID) {
      guard let note = workspace.notes.first(where: { $0.id == id }) else { return }
      pendingTrashNotes[id] = note
      workspace.deleteNote(id: id)
      saveNow()
    }

    func selectAdjacentNote(forward: Bool) {
      workspace.selectAdjacent(forward: forward)
      scheduleSave()
    }

    func moveNote(_ id: UUID, to destination: Int) {
      workspace.moveNote(id: id, to: destination)
      scheduleSave()
    }

    func togglePinned(_ id: UUID) {
      workspace.togglePinned(id: id)
      scheduleSave()
    }

    func updateSelected(title: String? = nil, body: String? = nil) {
      guard let id = workspace.selectedNoteID else { return }
      workspace.updateNote(id: id, title: title, body: body)
      scheduleSave()
    }

    func updateSelectedRichTextRTF(_ rtf: Data?) {
      guard let id = workspace.selectedNoteID,
        let index = workspace.notes.firstIndex(where: { $0.id == id })
      else { return }
      workspace.notes[index].richTextRTF = rtf
      workspace.notes[index].modifiedAt = Date()
      scheduleSave()
    }

    func setSelectedTabColor(_ hex: String?) {
      guard let id = workspace.selectedNoteID else { return }
      workspace.setTabColor(id: id, hex: hex)
      scheduleSave()
    }

    func toggleList(_ style: MarkdownEditing.ListStyle) {
      guard let note = selectedNote else { return }
      updateSelected(body: MarkdownEditing.togglingList(in: note.body, style: style))
    }

    func updatePreferences(_ update: (inout AppPreferences) -> Void) {
      update(&preferences)
      scheduleSave()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
      do {
        if enabled {
          try SMAppService.mainApp.register()
        } else {
          try SMAppService.mainApp.unregister()
        }
        updatePreferences { $0.launchAtLogin = enabled }
        saveError = nil
      } catch {
        saveError = "Could not update launch at login: \(error.localizedDescription)"
      }
    }

    func saveNow() {
      saveTask?.cancel()
      markSaveStarted()
      let snapshot = saveSnapshot()
      saveTask = Task {
        try? await persist(snapshot)
      }
    }

    func refreshTrash() async {
      do {
        trashedNotes = try await store.loadTrash()
        saveError = nil
      } catch {
        saveError = error.localizedDescription
      }
    }

    func restore(_ trashedNote: TrashedNote) {
      saveTask?.cancel()
      resetSaveStatus()
      pendingTrashNotes.removeValue(forKey: trashedNote.id)
      trashedNotes.removeAll { $0.id == trashedNote.id }
      workspace.addNote(trashedNote.note)
      let workspace = workspace
      let preferences = preferences
      let store = store
      Task {
        do {
          _ = try await store.restore(
            trashedNote,
            into: workspace,
            preferences: preferences
          )
          trashedNotes = try await store.loadTrash()
          saveError = nil
        } catch {
          if let refreshedTrash = try? await store.loadTrash() {
            trashedNotes = refreshedTrash
          }
          saveError = error.localizedDescription
        }
      }
    }

    private func load() async {
      do {
        workspace = try await store.loadWorkspace()
        preferences = try await store.loadPreferences()
        trashedNotes = try await store.loadTrash()
        saveError = nil
      } catch {
        saveError = error.localizedDescription
      }
    }

    private func scheduleSave() {
      saveTask?.cancel()
      markSaveStarted()
      let snapshot = saveSnapshot()
      saveTask = Task {
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        try? await persist(snapshot)
      }
    }

    private func saveCurrentState() async throws {
      saveTask?.cancel()
      saveTask = nil
      markSaveStarted()
      try await persist(saveSnapshot())
    }

    private typealias SaveSnapshot = (
      workspace: Workspace,
      preferences: AppPreferences,
      trashedNotes: [Note]
    )

    private func saveSnapshot() -> SaveSnapshot {
      (workspace, preferences, Array(pendingTrashNotes.values))
    }

    private func persist(_ snapshot: SaveSnapshot) async throws {
      do {
        try await store.save(
          workspace: snapshot.workspace,
          preferences: snapshot.preferences,
          trashedNotes: snapshot.trashedNotes
        )
        guard !Task.isCancelled else { throw CancellationError() }
        for note in snapshot.trashedNotes {
          pendingTrashNotes.removeValue(forKey: note.id)
        }
        if !snapshot.trashedNotes.isEmpty {
          trashedNotes = try await store.loadTrash()
        }
        saveError = nil
        markSaveSucceeded()
      } catch let error as CancellationError {
        throw error
      } catch {
        saveError = error.localizedDescription
        markSaveFailed()
        throw error
      }
    }

    private func removingSuffix(_ suffix: String, from richTextRTF: Data?) -> Data? {
      guard
        let richTextRTF,
        let attributed = try? NSMutableAttributedString(
          data: richTextRTF,
          options: [.documentType: NSAttributedString.DocumentType.rtf],
          documentAttributes: nil
        ),
        attributed.string.hasSuffix(suffix)
      else { return nil }
      let suffixLength = suffix.utf16.count
      attributed.deleteCharacters(
        in: NSRange(location: attributed.length - suffixLength, length: suffixLength)
      )
      return try? attributed.data(
        from: NSRange(location: 0, length: attributed.length),
        documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
      )
    }

    private func markSaveStarted() {
      saveStatusResetTask?.cancel()
      saveStatus = .saving
    }

    private func markSaveSucceeded() {
      saveStatus = .saved
      saveStatusResetTask?.cancel()
      saveStatusResetTask = Task {
        try? await Task.sleep(for: .seconds(1.2))
        guard !Task.isCancelled else { return }
        saveStatus = .idle
      }
    }

    private func markSaveFailed() {
      resetSaveStatus()
    }

    private func resetSaveStatus() {
      saveStatusResetTask?.cancel()
      saveStatus = .idle
    }
  }
#endif
