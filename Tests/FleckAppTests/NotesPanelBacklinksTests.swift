import AppKit
import FleckCore
import SwiftUI
import Testing

@testable import FleckApp

@Test @MainActor
func NotesPanelDoubleBracketPickerInsertsAndDerivesBacklink() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("notes-panel-backlinks-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let folder = try Folder(id: UUID(), name: "Work")
  let source = Note(id: UUID(), title: "Source", body: "Before ")
  let target = Note(id: UUID(), title: "Target", body: "Target body", folderID: folder.id)
  let state = AppState(
    store: LocalStore(rootURL: root),
    saveOperation: { _, _, _, _ in .committed }
  )
  await state.waitUntilInitialLoad()
  state.workspace = Workspace(
    notes: [source, target],
    selectedNoteID: source.id,
    folders: [folder]
  )

  let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
  let commands = EditorCommands()
  let searchController = WorkspaceSearchController()
  let picker = NoteLinkPickerController()
  let backlinks = BacklinkController()
  let host = NSHostingView(
    rootView: NotesPanel(
      dictationRuntime: runtime,
      sizing: .container,
      editorCommands: commands,
      searchController: searchController,
      noteLinkPickerController: picker,
      backlinkController: backlinks
    )
    .environmentObject(state)
  )
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 640, height: 430),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = host
  window.makeKeyAndOrderFront(nil)
  await settleBacklinksHost(host)

  let editor = try #require(hostedBacklinksDescendant(in: host, as: ListAwareTextView.self))
  #expect(window.makeFirstResponder(editor))
  editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
  editor.insertText("[[", replacementRange: editor.selectedRange())
  await settleBacklinksHost(host)
  #expect(picker.isPresented)

  picker.setQuery(target.title, in: state.workspace.notes)
  await settleBacklinksHost(host)
  let queryField = try #require(
    hostedBacklinksDescendants(in: host, as: NSTextField.self)
      .first { $0.placeholderString == "Link to note" }
  )
  #expect(window.makeFirstResponder(queryField))
  let returnEvent = try #require(
    NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: window.windowNumber,
      context: nil,
      characters: "\r",
      charactersIgnoringModifiers: "\r",
      isARepeat: false,
      keyCode: 36
    )
  )
  window.sendEvent(returnEvent)
  await settleBacklinksHost(host)

  let token = NoteLinkFormatter.markdown(label: target.displayTitle, targetNoteID: target.id)
  #expect(state.selectedNote?.body == "Before \(token)")
  #expect(!picker.isPresented)
  #expect(backlinks.incoming(to: target.id).map(\.sourceNoteID) == [source.id])

  state.select(target.id)
  await settleBacklinksHost(host)
  #expect(state.folderID(for: target.id) == folder.id)
  #expect(backlinks.incoming(to: target.id).map(\.sourceNoteID) == [source.id])

  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
}

@Test @MainActor
func NotesPanelBacklinksDisclosurePreservesExactEditorState() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("notes-panel-backlinks-state-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let target = Note(id: UUID(), title: "Target", body: "Target body")
  let source = Note(
    id: UUID(),
    title: "Source",
    body: NoteLinkFormatter.markdown(label: "Target", targetNoteID: target.id)
  )
  let state = AppState(
    store: LocalStore(rootURL: root),
    saveOperation: { _, _, _, _ in .committed }
  )
  await state.waitUntilInitialLoad()
  state.workspace = Workspace(notes: [target, source], selectedNoteID: target.id)
  let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
  let commands = EditorCommands()
  let backlinks = BacklinkController()
  let host = NSHostingView(
    rootView: NotesPanel(
      dictationRuntime: runtime,
      sizing: .container,
      editorCommands: commands,
      backlinkController: backlinks
    )
    .environmentObject(state)
  )
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 640, height: 900),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = host
  window.makeKeyAndOrderFront(nil)
  await settleBacklinksHost(host)

  let editor = try #require(hostedBacklinksDescendant(in: host, as: ListAwareTextView.self))
  #expect(window.makeFirstResponder(editor))
  editor.setSelectedRange(NSRange(location: 2, length: 4))
  editor.typingAttributes[.foregroundColor] = NSColor.systemBlue
  editor.undoManager?.registerUndo(withTarget: editor) { _ in }
  let originalSelection = editor.selectedRange()
  let originalTypingAttributes = NSDictionary(dictionary: editor.typingAttributes)
  let originalWorkspace = state.workspace
  let originalGeneration = state.persistenceGeneration
  let originalEditor = editor
  let disclosure = try #require(
    hostedBacklinksDescendants(in: host, as: NSButton.self)
      .first { $0.title.contains("Linked from") }
  )

  disclosure.performClick(nil)
  await settleBacklinksHost(host)
  #expect(hostedBacklinksDescendant(in: host, as: ListAwareTextView.self) === originalEditor)
  #expect(editor.selectedRange() == originalSelection)
  #expect(NSDictionary(dictionary: editor.typingAttributes).isEqual(to: originalTypingAttributes))
  #expect(state.workspace == originalWorkspace)
  #expect(state.persistenceGeneration == originalGeneration)

  disclosure.performClick(nil)
  await settleBacklinksHost(host)
  #expect(hostedBacklinksDescendant(in: host, as: ListAwareTextView.self) === originalEditor)
  #expect(editor.selectedRange() == originalSelection)

  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
}

@Test @MainActor
func NotesPanelSearchAndLinkPickerAreMutuallyExclusiveAndInert() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("notes-panel-backlinks-overlays-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let source = Note(id: UUID(), title: "Source", body: "Body")
  let target = Note(id: UUID(), title: "Target", body: "Target")
  let state = AppState(
    store: LocalStore(rootURL: root),
    saveOperation: { _, _, _, _ in .committed }
  )
  await state.waitUntilInitialLoad()
  state.workspace = Workspace(notes: [source, target], selectedNoteID: source.id)
  let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
  let searchController = WorkspaceSearchController()
  let picker = NoteLinkPickerController()
  let host = NSHostingView(
    rootView: NotesPanel(
      dictationRuntime: runtime,
      sizing: .container,
      searchController: searchController,
      noteLinkPickerController: picker
    )
    .environmentObject(state)
  )
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 640, height: 430),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = host
  window.makeKeyAndOrderFront(nil)
  await settleBacklinksHost(host)

  searchController.present(for: source.id)
  await settleBacklinksHost(host)
  #expect(searchController.isPresented)
  picker.present(sourceNoteID: source.id, replacementRange: NSRange(location: 0, length: 0))
  await settleBacklinksHost(host)
  #expect(searchController.isPresented)
  #expect(!picker.isPresented)

  searchController.dismiss()
  await settleBacklinksHost(host)
  picker.present(sourceNoteID: source.id, replacementRange: NSRange(location: 0, length: 0))
  await settleBacklinksHost(host)
  #expect(picker.isPresented)

  let expectedWorkspace = state.workspace
  let expectedGeneration = state.persistenceGeneration
  let commandF = try #require(
    NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: [.command],
      timestamp: 0,
      windowNumber: window.windowNumber,
      context: nil,
      characters: "f",
      charactersIgnoringModifiers: "f",
      isARepeat: false,
      keyCode: 3
    )
  )
  NSApp.sendEvent(commandF)
  await settleBacklinksHost(host)

  #expect(picker.isPresented)
  #expect(!searchController.isPresented)
  #expect(state.workspace == expectedWorkspace)
  #expect(state.persistenceGeneration == expectedGeneration)

  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
}

@MainActor
private func hostedBacklinksDescendant<T: NSView>(in view: NSView, as type: T.Type) -> T? {
  if let match = view as? T { return match }
  for subview in view.subviews {
    if let match = hostedBacklinksDescendant(in: subview, as: type) { return match }
  }
  return nil
}

@MainActor
private func hostedBacklinksDescendants<T: NSView>(in view: NSView, as type: T.Type) -> [T] {
  var matches: [T] = []
  if let match = view as? T { matches.append(match) }
  for subview in view.subviews {
    matches.append(contentsOf: hostedBacklinksDescendants(in: subview, as: type))
  }
  return matches
}

@MainActor
private func settleBacklinksHost(_ view: NSView) async {
  for _ in 0..<40 {
    view.layoutSubtreeIfNeeded()
    await Task.yield()
  }
}
