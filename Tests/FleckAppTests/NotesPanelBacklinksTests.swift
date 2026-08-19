import AppKit
import FleckCore
import SwiftUI
import Testing

@testable import FleckApp

@Test @MainActor
func NotesPanelBacklinksPopoverReclaimsEditorSpace() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("notes-panel-backlinks-popover-" + UUID().uuidString, isDirectory: true)
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
  let backlinks = BacklinkController()
  let host = NSHostingView(
    rootView: NotesPanel(
      dictationRuntime: runtime,
      sizing: .container,
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
  let editorScrollView = try #require(hostedBacklinksEditorScrollView(in: host))
  let toolbarControls = hostedBacklinksToolbarControls(in: host)
  // Catches removing the header trigger and restoring the persistent bottom disclosure.
  #expect(editorScrollView.frame.height >= 200)

  let originalEditor = editor
  let originalString = editor.string
  let backlinksControl = try #require(toolbarControls.first)
  clickHostedBacklinksControl(backlinksControl, in: window)
  await settleBacklinksHost(host)

  #expect(backlinks.isExpanded)
  #expect(hostedBacklinksDescendant(in: host, as: ListAwareTextView.self) === originalEditor)
  #expect(editor.string == originalString)
  #expect(window.childWindows?.contains(where: { $0.isVisible }) == true)

  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
}

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
  editor.typingAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
  commands.refreshFormattingState()
  commands.applyBackgroundColor(.systemYellow)
  await settleBacklinksHost(host)

  let rtfAttributes: [NSAttributedString.DocumentAttributeKey: Any] = [
    .documentType: NSAttributedString.DocumentType.rtf
  ]
  let originalString = editor.string
  let originalAttributed = NSAttributedString(
    attributedString: try #require(editor.textStorage)
  )
  let originalRTF = try #require(
    try editor.textStorage?.data(
      from: NSRange(location: 0, length: editor.textStorage?.length ?? 0),
      documentAttributes: rtfAttributes
    )
  )
  let undoManager = try #require(editor.undoManager)
  let originalSelection = editor.selectedRange()
  let originalTypingAttributes = NSDictionary(dictionary: editor.typingAttributes)
  let originalCanUndo = undoManager.canUndo
  let originalCanRedo = undoManager.canRedo
  let originalWorkspace = state.workspace
  let originalGeneration = state.persistenceGeneration
  let originalEditor = editor
  let originalCommandsTextView = commands.textView
  let originalCommandsActiveState = commands.isFocusedDictationActive
  #expect(originalCanUndo)
  #expect(originalCommandsTextView === originalEditor)
  backlinks.toggleDisclosure()
  await settleBacklinksHost(host)
  #expect(backlinks.isExpanded)
  #expect(hostedBacklinksDescendant(in: host, as: ListAwareTextView.self) === originalEditor)
  #expect(editor.string == originalString)
  #expect(NSAttributedString(attributedString: try #require(editor.textStorage)).isEqual(to: originalAttributed))
  #expect(
    try editor.textStorage?.data(
      from: NSRange(location: 0, length: editor.textStorage?.length ?? 0),
      documentAttributes: rtfAttributes
    ) == originalRTF
  )
  #expect(editor.selectedRange() == originalSelection)
  #expect(NSDictionary(dictionary: editor.typingAttributes).isEqual(to: originalTypingAttributes))
  #expect(editor.undoManager === undoManager)
  #expect(editor.undoManager?.canUndo == originalCanUndo)
  #expect(editor.undoManager?.canRedo == originalCanRedo)
  #expect(commands.textView === originalCommandsTextView)
  #expect(commands.isFocusedDictationActive == originalCommandsActiveState)
  #expect(state.workspace == originalWorkspace)
  #expect(state.persistenceGeneration == originalGeneration)

  backlinks.toggleDisclosure()
  await settleBacklinksHost(host)
  #expect(!backlinks.isExpanded)
  #expect(hostedBacklinksDescendant(in: host, as: ListAwareTextView.self) === originalEditor)
  #expect(editor.string == originalString)
  #expect(NSAttributedString(attributedString: try #require(editor.textStorage)).isEqual(to: originalAttributed))
  #expect(
    try editor.textStorage?.data(
      from: NSRange(location: 0, length: editor.textStorage?.length ?? 0),
      documentAttributes: rtfAttributes
    ) == originalRTF
  )
  #expect(editor.selectedRange() == originalSelection)
  #expect(NSDictionary(dictionary: editor.typingAttributes).isEqual(to: originalTypingAttributes))
  #expect(editor.undoManager === undoManager)
  #expect(editor.undoManager?.canUndo == originalCanUndo)
  #expect(editor.undoManager?.canRedo == originalCanRedo)
  #expect(commands.textView === originalCommandsTextView)
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
  state.updatePreferences {
    $0.shortcuts = [
      Shortcut(action: .togglePanel, key: "p", modifiers: ["command", "shift"]),
      Shortcut(action: .newNote, key: "n", modifiers: ["command"]),
      Shortcut(action: .closeNote, key: "w", modifiers: ["command"]),
      Shortcut(action: .nextNote, key: "tab", modifiers: ["control"]),
      Shortcut(action: .previousNote, key: "tab", modifiers: ["control", "shift"]),
    ]
  }
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
  picker.present(
    sourceNoteID: source.id,
    replacementRange: NSRange(location: 0, length: 0),
    sourceRevision: source.revision
  )
  await settleBacklinksHost(host)
  #expect(searchController.isPresented)
  #expect(!picker.isPresented)

  searchController.dismiss()
  await settleBacklinksHost(host)
  picker.present(
    sourceNoteID: source.id,
    replacementRange: NSRange(location: 0, length: 0),
    sourceRevision: source.revision
  )
  await settleBacklinksHost(host)
  #expect(picker.isPresented)

  let expectedWorkspace = state.workspace
  let expectedSelectedNoteID = state.workspace.selectedNoteID
  let expectedScope = state.folderScopeForSelectedNote()
  let expectedGeneration = state.persistenceGeneration
  picker.setQuery("Target", in: state.workspace.notes)
  await settleBacklinksHost(host)
  let queryField = try #require(
    hostedBacklinksDescendants(in: host, as: NSTextField.self)
      .first { $0.placeholderString == "Link to note" }
  )
  #expect(window.makeFirstResponder(queryField))
  let queryFieldEditor = try #require(window.firstResponder as? NSTextView)

  let shortcuts: [(keyCode: UInt16, characters: String, modifiers: NSEvent.ModifierFlags)] = [
    (45, "n", [.command]),
    (13, "w", [.command]),
    (48, "\t", [.control]),
    (48, "\t", [.control, .shift]),
    (35, "p", [.command, .shift]),
  ]
  for shortcut in shortcuts {
    let event = try #require(
      NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: shortcut.modifiers,
        timestamp: 0,
        windowNumber: window.windowNumber,
        context: nil,
        characters: shortcut.characters,
        charactersIgnoringModifiers: shortcut.characters,
        isARepeat: false,
        keyCode: shortcut.keyCode
      )
    )
    NSApp.sendEvent(event)
    await settleBacklinksHost(host)
  }

  #expect(picker.isPresented)
  #expect(picker.query == "Target")
  #expect(window.firstResponder === queryFieldEditor)
  #expect(queryField.currentEditor() === queryFieldEditor)
  #expect(state.workspace == expectedWorkspace)
  #expect(state.workspace.selectedNoteID == expectedSelectedNoteID)
  #expect(state.folderScopeForSelectedNote() == expectedScope)
  #expect(state.persistenceGeneration == expectedGeneration)
  #expect(window.isVisible)

  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
}

@Test @MainActor
func NotesPanelLinkPickerRejectsStaleSourceRevisionWithoutEditing() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("notes-panel-backlinks-stale-picker-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let source = Note(id: UUID(), title: "Source", body: "Original body", revision: 3)
  let target = Note(id: UUID(), title: "Target", body: "Target body")
  let state = AppState(
    store: LocalStore(rootURL: root),
    saveOperation: { _, _, _, _ in .committed }
  )
  await state.waitUntilInitialLoad()
  state.workspace = Workspace(notes: [source, target], selectedNoteID: source.id)
  let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
  let picker = NoteLinkPickerController()
  let host = NSHostingView(
    rootView: NotesPanel(
      dictationRuntime: runtime,
      sizing: .container,
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

  picker.present(
    sourceNoteID: source.id,
    replacementRange: NSRange(location: 0, length: 4),
    sourceRevision: source.revision
  )
  await settleBacklinksHost(host)
  picker.setQuery(target.title, in: state.workspace.notes)
  await settleBacklinksHost(host)
  #expect(picker.results.map(\.noteID) == [target.id])

  state.updateSelected(body: "Changed body")
  await settleBacklinksHost(host)
  let expectedBody = try #require(state.selectedNote?.body)
  let expectedGeneration = state.persistenceGeneration
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

  #expect(!picker.isPresented)
  #expect(state.selectedNote?.body == expectedBody)
  #expect(state.persistenceGeneration == expectedGeneration)

  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
}

@Test @MainActor
func NotesPanelCommandClickOpensLiveLinkThroughNamedFolderScope() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("notes-panel-backlinks-folder-link-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let folder = try Folder(id: UUID(), name: "Work")
  let target = Note(id: UUID(), title: "Folder target", body: "Target body", folderID: folder.id)
  let source = Note(
    id: UUID(),
    title: "Source",
    body: "See " + NoteLinkFormatter.markdown(label: target.displayTitle, targetNoteID: target.id)
  )
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
  let host = NSHostingView(
    rootView: NotesPanel(
      dictationRuntime: runtime,
      sizing: .container,
      editorCommands: commands
    )
    .environmentObject(state)
  )
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 700, height: 900),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = host
  window.makeKeyAndOrderFront(nil)
  await settleBacklinksHost(host)

  let editor = try #require(
    hostedBacklinksDescendant(in: host, as: ListAwareTextView.self)
  )
  let link = try #require(NoteLinkParser.links(in: editor.string).first)
  let container = try #require(editor.textContainer)
  editor.layoutManager?.ensureLayout(for: container)
  let glyphRange = editor.layoutManager?.glyphRange(
    forCharacterRange: link.range,
    actualCharacterRange: nil
  ) ?? NSRange(location: 0, length: 0)
  let linkRect = try #require(
    editor.layoutManager?.boundingRect(forGlyphRange: glyphRange, in: container)
  )
  let point = editor.convert(
    NSPoint(
      x: linkRect.midX + editor.textContainerOrigin.x,
      y: linkRect.midY + editor.textContainerOrigin.y
    ),
    to: nil
  )
  let event = try #require(
    NSEvent.mouseEvent(
      with: .leftMouseDown,
      location: point,
      modifierFlags: [.command],
      timestamp: 0,
      windowNumber: window.windowNumber,
      context: nil,
      eventNumber: 4,
      clickCount: 1,
      pressure: 1
    )
  )
  editor.mouseDown(with: event)
  await settleBacklinksHost(host)

  #expect(state.workspace.selectedNoteID == target.id)
  #expect(state.folderScopeForSelectedNote() == folder.id)
  #expect(state.visibleNotes(in: folder.id).contains { $0.id == target.id })
  let targetEditor = try #require(
    hostedBacklinksDescendants(in: host, as: ListAwareTextView.self)
      .first { $0.string == target.body }
  )
  #expect(commands.textView === targetEditor)
  #expect(window.firstResponder === targetEditor)

  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
}

@Test @MainActor
func NotesPanelCrossNoteNavigationDoesNotReuseDismantledEditorUndo() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("notes-panel-cross-note-undo-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let folder = try Folder(id: UUID(), name: "Work")
  let source = Note(id: UUID(), title: "Source", body: "Before ", folderID: folder.id)
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
  let picker = NoteLinkPickerController()
  let backlinks = BacklinkController()
  let host = NSHostingView(
    rootView: NotesPanel(
      dictationRuntime: runtime,
      sizing: .container,
      editorCommands: commands,
      noteLinkPickerController: picker,
      backlinkController: backlinks
    )
    .environmentObject(state)
  )
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 700, height: 900),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = host
  window.makeKeyAndOrderFront(nil)
  await settleBacklinksHost(host)

  let sourceEditor = try #require(
    hostedBacklinksDescendant(in: host, as: ListAwareTextView.self)
  )
  #expect(window.makeFirstResponder(sourceEditor))
  sourceEditor.setSelectedRange(NSRange(location: sourceEditor.string.utf16.count, length: 0))
  sourceEditor.insertText("[[", replacementRange: sourceEditor.selectedRange())
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
  let sourceBody = "Before \(token)"
  #expect(state.selectedNote?.body == sourceBody)
  #expect(!picker.isPresented)

  let link = try #require(NoteLinkParser.links(in: sourceEditor.string).first)
  let container = try #require(sourceEditor.textContainer)
  sourceEditor.layoutManager?.ensureLayout(for: container)
  let glyphRange = sourceEditor.layoutManager?.glyphRange(
    forCharacterRange: link.range,
    actualCharacterRange: nil
  ) ?? NSRange(location: 0, length: 0)
  let linkRect = try #require(
    sourceEditor.layoutManager?.boundingRect(forGlyphRange: glyphRange, in: container)
  )
  let point = sourceEditor.convert(
    NSPoint(
      x: linkRect.midX + sourceEditor.textContainerOrigin.x,
      y: linkRect.midY + sourceEditor.textContainerOrigin.y
    ),
    to: nil
  )
  let click = try #require(
    NSEvent.mouseEvent(
      with: .leftMouseDown,
      location: point,
      modifierFlags: [.command],
      timestamp: 0,
      windowNumber: window.windowNumber,
      context: nil,
      eventNumber: 7,
      clickCount: 1,
      pressure: 1
    )
  )
  sourceEditor.mouseDown(with: click)
  await settleBacklinksHost(host)

  #expect(state.workspace.selectedNoteID == target.id)
  let targetEditor = try #require(
    hostedBacklinksDescendants(in: host, as: ListAwareTextView.self)
      .first { $0.string == target.body }
  )
  #expect(commands.textView === targetEditor)
  #expect(sourceEditor.onOpenNoteLink == nil)
  #expect(sourceEditor.undoManager == nil)
  #expect(backlinks.incoming(to: target.id).map(\.sourceNoteID) == [source.id])
  backlinks.toggleDisclosure()
  await settleBacklinksHost(host)

  let backlink = try #require(backlinks.incoming(to: target.id).first)
  state.select(backlink.sourceNoteID)
  await settleBacklinksHost(host)

  let returnedEditor = try #require(
    hostedBacklinksDescendants(in: host, as: ListAwareTextView.self)
      .first { $0 !== sourceEditor && $0.string == sourceBody }
  )
  #expect(state.workspace.selectedNoteID == source.id)
  #expect(commands.textView === returnedEditor)
  #expect(sourceEditor.string == sourceBody)
  #expect(targetEditor.string == target.body)

  commands.undo()
  await settleBacklinksHost(host)
  #expect(commands.textView === returnedEditor)
  #expect(sourceEditor.string == sourceBody)
  #expect(returnedEditor.string == sourceBody)
  #expect(state.workspace.notes.first(where: { $0.id == source.id })?.body == sourceBody)
  #expect(state.workspace.notes.first(where: { $0.id == target.id })?.body == target.body)

  commands.redo()
  await settleBacklinksHost(host)
  #expect(commands.textView === returnedEditor)
  #expect(sourceEditor.string == sourceBody)
  #expect(returnedEditor.string == sourceBody)
  #expect(state.workspace.notes.first(where: { $0.id == source.id })?.body == sourceBody)
  #expect(state.workspace.notes.first(where: { $0.id == target.id })?.body == target.body)

  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
}

@Test @MainActor
func BacklinksAndPickerRowsAnnounceFolderContextAndContent() async throws {
  let folderID = UUID()
  let sourceID = UUID()
  let targetID = UUID()
  let entry = BacklinkSource(
    sourceNoteID: sourceID,
    sourceDisplayTitle: "Source note",
    sourceFolderID: folderID,
    targetNoteID: targetID,
    excerpt: "A useful excerpt",
    referenceCount: 2,
    sourceModifiedAt: Date()
  )
  #expect(
    BacklinksView.accessibilityLabel(for: entry, folderName: "Work")
      == "Source note, Work, A useful excerpt, 2 references"
  )

  let result = WorkspaceSearchResult(
    noteID: targetID,
    displayTitle: "Target note",
    snippet: "Target snippet",
    match: WorkspaceSearchMatch(field: .title, location: 0, length: 1),
    score: 1
  )
  #expect(
    NoteLinkPickerView.accessibilityLabel(for: result, folderName: "Work")
      == "Target note, Work, Target snippet"
  )
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
private func hostedBacklinksEditorScrollView(in view: NSView) -> NSScrollView? {
  if let scrollView = view as? NSScrollView,
    hostedBacklinksDescendant(in: scrollView, as: ListAwareTextView.self) != nil
  {
    return scrollView
  }
  for subview in view.subviews {
    if let scrollView = hostedBacklinksEditorScrollView(in: subview) { return scrollView }
  }
  return nil
}

@MainActor
private func hostedBacklinksToolbarControls(in view: NSView) -> [NSView] {
  hostedBacklinksDescendants(in: view, as: NSView.self)
    .filter { control in
      guard String(describing: type(of: control)) == "KeyViewProxy" else { return false }
      let frame = control.convert(control.bounds, to: view)
      return frame.minY < 40 && frame.minX > view.bounds.midX
    }
    .sorted { lhs, rhs in
      lhs.convert(lhs.bounds, to: view).minX < rhs.convert(rhs.bounds, to: view).minX
    }
}

@MainActor
private func clickHostedBacklinksControl(_ control: NSView, in window: NSWindow) {
  let point = control.convert(
    NSPoint(x: control.bounds.midX, y: control.bounds.midY),
    to: nil
  )
  for eventType in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
    guard let event = NSEvent.mouseEvent(
      with: eventType,
      location: point,
      modifierFlags: [],
      timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: window.windowNumber,
      context: nil,
      eventNumber: 0,
      clickCount: 1,
      pressure: eventType == .leftMouseDown ? 1 : 0
    ) else { continue }
    window.sendEvent(event)
  }
}

@MainActor
private func settleBacklinksHost(_ view: NSView) async {
  for _ in 0..<40 {
    view.layoutSubtreeIfNeeded()
    await Task.yield()
  }
}
