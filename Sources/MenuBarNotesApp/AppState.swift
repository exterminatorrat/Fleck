#if os(macOS)
  import Combine
  import Foundation
  import MenuBarNotesCore
  import ServiceManagement

  @MainActor
  final class AppState: ObservableObject {
    @Published var workspace = Workspace()
    @Published var preferences = AppPreferences()
    @Published var saveError: String?

    private let store: LocalStore
    private var saveTask: Task<Void, Never>?

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

    func deleteSelectedNote() {
      guard let id = workspace.selectedNoteID else { return }
      workspace.deleteNote(id: id)
      scheduleSave()
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
      let workspace = workspace
      let preferences = preferences
      let store = store
      saveTask = Task {
        do {
          try await store.save(workspace: workspace, preferences: preferences)
          guard !Task.isCancelled else { return }
          saveError = nil
        } catch {
          guard !Task.isCancelled else { return }
          saveError = error.localizedDescription
        }
      }
    }

    private func load() async {
      do {
        workspace = try await store.loadWorkspace()
        preferences = try await store.loadPreferences()
        saveError = nil
      } catch {
        saveError = error.localizedDescription
      }
    }

    private func scheduleSave() {
      saveTask?.cancel()
      let workspace = workspace
      let preferences = preferences
      let store = store
      saveTask = Task {
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        do {
          try await store.save(workspace: workspace, preferences: preferences)
          guard !Task.isCancelled else { return }
          saveError = nil
        } catch {
          guard !Task.isCancelled else { return }
          saveError = error.localizedDescription
        }
      }
    }
  }
#endif
