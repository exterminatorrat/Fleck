import AppKit
import Foundation
import FleckCore
import SwiftUI
import Testing

@testable import FleckApp

@Test @MainActor
func WorkspaceSearchHostingPreservesSearchResultsAndNoteStateAcrossAccentUpdates()
  async throws
{
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("workspace-search-highlight-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let state = AppState(store: LocalStore(rootURL: root), saveOperation: { _, _, _ in })
  await state.waitUntilInitialLoad()
  let accentHex = "#E64A19"
  state.updatePreferences { $0.accentHex = accentHex }
  state.updateSelected(title: "Café cafe CAFE — untouched", body: "No body match")
  let titleNoteID = try #require(state.selectedNote?.id)

  let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
  let searchController = WorkspaceSearchController()
  let host = NSHostingView(
    rootView: NotesPanel(
      dictationRuntime: runtime,
      sizing: .container,
      searchController: searchController
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
  await settleWorkspaceSearchHost(host)

  searchController.present()
  await settleWorkspaceSearchHost(host)
  searchController.setQuery("cafe", in: state.workspace.notes)
  await settleWorkspaceSearchHost(host)

  #expect(searchController.results.map(\.noteID) == [titleNoteID])
  let initialResult = try #require(searchController.results.first)
  #expect(initialResult.displayTitle == "Café cafe CAFE — untouched")
  #expect(initialResult.snippet == initialResult.displayTitle)

  state.updatePreferences { $0.accentHex = "#007AFF" }
  await settleWorkspaceSearchHost(host)
  #expect(searchController.results.first?.displayTitle == initialResult.displayTitle)
  #expect(searchController.results.first?.snippet == initialResult.snippet)
  #expect(state.selectedNote?.title == "Café cafe CAFE — untouched")
  #expect(state.selectedNote?.body == "No body match")

  searchController.setQuery("   \n", in: state.workspace.notes)
  await settleWorkspaceSearchHost(host)
  #expect(searchController.results.isEmpty)

  searchController.dismiss()
  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
}

@Test @MainActor
func WorkspaceSearchHostingRestoresTheRealEditorStateAfterEscape() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("workspace-search-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let state = AppState(store: LocalStore(rootURL: root), saveOperation: { _, _, _ in })
  await state.waitUntilInitialLoad()

  let text = "Keep this rich text"
  let selectedRange = NSRange(location: 5, length: 4)
  let font = try #require(NSFont(name: "Helvetica-Bold", size: 18))
  let attributed = NSMutableAttributedString(string: text)
  attributed.addAttributes(
    [.font: font, .foregroundColor: NSColor.systemRed],
    range: NSRange(location: 0, length: text.utf16.count)
  )
  let rtfAttributes: [NSAttributedString.DocumentAttributeKey: Any] = [
    .documentType: NSAttributedString.DocumentType.rtf
  ]
  let rtf = try attributed.data(
    from: NSRange(location: 0, length: attributed.length),
    documentAttributes: rtfAttributes
  )
  state.updateSelected(body: text, richTextRTF: rtf)

  let commands = EditorCommands()
  let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
  let searchController = WorkspaceSearchController()
  let host = NSHostingView(
    rootView: NotesPanel(
      dictationRuntime: runtime,
      sizing: .container,
      editorCommands: commands,
      searchController: searchController
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
  await settleWorkspaceSearchHost(host)

  let textView = try #require(hostedWorkspaceSearchDescendant(in: host, as: ListAwareTextView.self))
  #expect(window.makeFirstResponder(textView))
  #expect(window.firstResponder === textView)
  textView.setSelectedRange(selectedRange)
  textView.typingAttributes[NSAttributedString.Key.underlineStyle] = NSUnderlineStyle.single.rawValue
  commands.refreshFormattingState()
  commands.applyBackgroundColor(.systemYellow)
  #expect(commands.beginFocusedDictation())

  let expectedRTF = try #require(
    try textView.textStorage?.data(
      from: NSRange(location: 0, length: textView.textStorage?.length ?? 0),
      documentAttributes: rtfAttributes
    )
  )
  let expectedTypingAttributes = textView.typingAttributes
  let expectedSelectedNoteID = state.workspace.selectedNoteID
  let expectedUndoAvailability = textView.undoManager?.canUndo
  let expectedActiveState = commands.isFocusedDictationActive
  #expect(expectedUndoAvailability == true)
  #expect(expectedActiveState)

  searchController.present()
  await settleWorkspaceSearchHost(host)
  searchController.setQuery("rich", in: state.workspace.notes)
  await settleWorkspaceSearchHost(host)
  searchController.moveHighlight(.down)
  #expect(searchController.handleKey(.escape))
  await settleWorkspaceSearchHost(host)

  #expect(!searchController.isPresented)
  #expect(commands.textView === textView)
  #expect(textView.string == text)
  #expect(textView.selectedRange() == selectedRange)
  #expect(
    NSDictionary(dictionary: textView.typingAttributes)
      .isEqual(to: expectedTypingAttributes)
  )
  let actualRTF = try #require(
    try textView.textStorage?.data(
      from: NSRange(location: 0, length: textView.textStorage?.length ?? 0),
      documentAttributes: rtfAttributes
    )
  )
  #expect(actualRTF == expectedRTF)
  #expect(textView.undoManager?.canUndo == expectedUndoAvailability)
  #expect(commands.isFocusedDictationActive == expectedActiveState)
  #expect(state.workspace.selectedNoteID == expectedSelectedNoteID)
  #expect(window.firstResponder === textView)

  commands.cancelFocusedDictation()
  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
}

@Test @MainActor
func WorkspaceSearchHostingRestoresTheTargetEditorAfterCrossNoteActivation()
  async throws
{
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("workspace-search-cross-note-editor-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let state = AppState(store: LocalStore(rootURL: root), saveOperation: { _, _, _ in })
  await state.waitUntilInitialLoad()
  state.updateSelected(title: "Original title", body: "Original body")
  let originalID = try #require(state.selectedNote?.id)
  let target = Note(
    id: UUID(uuidString: "00000000-0000-0000-0000-0000000000a1")!,
    title: "Target title",
    body: "Target body"
  )
  state.importNote(target)
  state.select(originalID)

  let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
  let searchController = WorkspaceSearchController()
  let host = NSHostingView(
    rootView: NotesPanel(
      dictationRuntime: runtime,
      sizing: .container,
      searchController: searchController
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
  await settleWorkspaceSearchHost(host)

  let originalEditor = try #require(
    hostedWorkspaceSearchDescendant(in: host, as: ListAwareTextView.self)
  )
  #expect(originalEditor.string == "Original body")
  #expect(window.makeFirstResponder(originalEditor))
  searchController.present(for: originalID)
  await settleWorkspaceSearchHost(host)
  searchController.setQuery("Target", in: state.workspace.notes)
  await settleWorkspaceSearchHost(host)
  #expect(searchController.results.map(\.noteID) == [target.id])

  var activations: [UUID] = []
  #expect(
    searchController.activateResult(
      target.id,
      currentNoteIDs: Set(state.workspace.notes.map(\.id)),
      activate: { noteID in
        activations.append(noteID)
        state.select(noteID)
      }
    )
  )
  await settleWorkspaceSearchHost(host)

  #expect(activations == [target.id])
  #expect(state.workspace.selectedNoteID == target.id)
  #expect(!searchController.isPresented)
  let targetEditor = try #require(
    hostedWorkspaceSearchDescendants(in: host, as: ListAwareTextView.self)
      .first { $0.string == target.body }
  )
  #expect(targetEditor !== originalEditor)
  #expect(window.firstResponder === targetEditor)

  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
}

@Test @MainActor
func WorkspaceSearchHostingRestoresTheTargetTitleFieldAfterCrossNoteActivation()
  async throws
{
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("workspace-search-cross-note-title-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let state = AppState(store: LocalStore(rootURL: root), saveOperation: { _, _, _ in })
  await state.waitUntilInitialLoad()
  state.updateSelected(title: "Original title", body: "Original body")
  let originalID = try #require(state.selectedNote?.id)
  let target = Note(
    id: UUID(uuidString: "00000000-0000-0000-0000-0000000000a2")!,
    title: "Goal",
    body: "Target body"
  )
  state.importNote(target)
  state.select(originalID)

  let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
  let searchController = WorkspaceSearchController()
  let host = NSHostingView(
    rootView: NotesPanel(
      dictationRuntime: runtime,
      sizing: .container,
      searchController: searchController
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
  await settleWorkspaceSearchHost(host)

  let originalTitleField = try #require(
    hostedWorkspaceSearchDescendants(in: host, as: NSTextField.self)
      .first { $0.stringValue == "Original title" && $0.frame.width > 200 }
  )
  #expect(window.makeFirstResponder(originalTitleField))
  let originalFieldEditor = try #require(window.firstResponder as? NSTextView)
  let originalSelection = NSRange(location: 2, length: 5)
  originalFieldEditor.setSelectedRange(originalSelection)
  #expect(originalTitleField.currentEditor() === originalFieldEditor)

  searchController.present(for: originalID)
  await settleWorkspaceSearchHost(host)
  searchController.setQuery("Goal", in: state.workspace.notes)
  await settleWorkspaceSearchHost(host)
  #expect(searchController.results.map(\.noteID) == [target.id])

  var activations: [UUID] = []
  #expect(
    searchController.activateResult(
      target.id,
      currentNoteIDs: Set(state.workspace.notes.map(\.id)),
      activate: { noteID in
        activations.append(noteID)
        state.select(noteID)
      }
    )
  )
  await settleWorkspaceSearchHost(host)

  #expect(activations == [target.id])
  #expect(state.workspace.selectedNoteID == target.id)
  #expect(!searchController.isPresented)
  let targetTitleField = try #require(
    hostedWorkspaceSearchDescendants(in: host, as: NSTextField.self)
      .first { $0.stringValue == target.title && $0.frame.width > 200 }
  )
  let targetFieldEditor = try #require(targetTitleField.currentEditor() as? NSTextView)
  #expect(window.firstResponder === targetFieldEditor)
  #expect(targetFieldEditor.selectedRange() != originalSelection)
  #expect(NSMaxRange(targetFieldEditor.selectedRange()) <= target.title.utf16.count)
  #expect(targetTitleField.stringValue == target.title)

  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
}

@Test @MainActor
func WorkspaceSearchHostingRestoresTitleFieldEditorAndIsolatesUnderlyingControls()
  async throws
{
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("workspace-search-title-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let state = AppState(store: LocalStore(rootURL: root), saveOperation: { _, _, _ in })
  await state.waitUntilInitialLoad()
  state.updateSelected(title: "Editable title")

  let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
  let searchController = WorkspaceSearchController()
  let host = NSHostingView(
    rootView: NotesPanel(
      dictationRuntime: runtime,
      sizing: .container,
      searchController: searchController
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
  await settleWorkspaceSearchHost(host)

  let editor = try #require(hostedWorkspaceSearchDescendant(in: host, as: ListAwareTextView.self))
  let titleField = try #require(
    hostedWorkspaceSearchDescendants(in: host, as: NSTextField.self)
      .first { $0.stringValue == "Editable title" && $0.frame.width > 200 }
  )
  #expect(window.makeFirstResponder(titleField))
  let originalFieldEditor = try #require(window.firstResponder as? NSTextView)
  let selectedRange = NSRange(location: 2, length: 6)
  originalFieldEditor.setSelectedRange(selectedRange)
  #expect(titleField.currentEditor() === originalFieldEditor)

  searchController.present()
  await settleWorkspaceSearchHost(host)
  searchController.setQuery("Editable", in: state.workspace.notes)
  await settleWorkspaceSearchHost(host)

  let queryField = try #require(
    hostedWorkspaceSearchDescendants(in: host, as: NSTextField.self)
      .first { $0.placeholderString == "Search notes" }
  )
  #expect(hostedWorkspaceSearchDescendant(in: host, as: ListAwareTextView.self) === editor)
  #expect(!titleField.isEnabled)
  #expect(!titleField.isAccessibilityElement())
  #expect(window.makeFirstResponder(queryField))
  for _ in 0..<12 {
    window.selectNextKeyView(nil)
    #expect(window.firstResponder !== titleField)
    #expect(window.firstResponder !== editor)
    #expect((window.firstResponder as? NSTextView)?.delegate !== titleField)
  }
  #expect(searchController.isPresented)

  searchController.dismiss()
  await settleWorkspaceSearchHost(host)
  let restoredFieldEditor = try #require(window.firstResponder as? NSTextView)
  #expect(restoredFieldEditor === originalFieldEditor)
  #expect(titleField.currentEditor() === originalFieldEditor)
  #expect(restoredFieldEditor.selectedRange() == selectedRange)
  #expect(titleField.stringValue == "Editable title")
  #expect(window.firstResponder !== editor)

  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
}

@Test @MainActor
func WorkspaceSearchHostingReturnSelectsOnlyTheCurrentUUID() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("workspace-search-return-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let state = AppState(store: LocalStore(rootURL: root), saveOperation: { _, _, _ in })
  await state.waitUntilInitialLoad()
  let originalID = try #require(state.selectedNote?.id)
  let target = Note(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!,
    title: "Target note",
    body: "A body-only match"
  )
  state.importNote(target)
  state.select(originalID)
  #expect(state.workspace.notes.contains(where: { $0.id == target.id }))

  let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
  let searchController = WorkspaceSearchController()
  let host = NSHostingView(
    rootView: NotesPanel(
      dictationRuntime: runtime,
      sizing: .container,
      searchController: searchController
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
  await settleWorkspaceSearchHost(host)

  searchController.present()
  await settleWorkspaceSearchHost(host)
  searchController.setQuery("Target", in: state.workspace.notes)
  await settleWorkspaceSearchHost(host)
  #expect(searchController.results.map(\.noteID) == [target.id])

  var activations: [UUID] = []
  #expect(
    searchController.handleKey(
      .return,
      currentNoteIDs: Set(state.workspace.notes.map(\.id)),
      activate: { noteID in
        activations.append(noteID)
        state.select(noteID)
      }
    )
  )
  #expect(activations == [target.id])
  #expect(state.workspace.selectedNoteID == target.id)
  #expect(!searchController.isPresented)

  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
}

@Test @MainActor
func WorkspaceSearchHostingKeepsResultsScrollableInProductionOverlay()
  async throws
{
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("workspace-search-palette-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let state = AppState(store: LocalStore(rootURL: root), saveOperation: { _, _, _ in })
  await state.waitUntilInitialLoad()
  let originalID = try #require(state.selectedNote?.id)
  for index in 0..<80 {
    state.importNote(
      Note(
        title: "Result " + String(index),
        body: "Scrollable result body " + String(index)
      )
    )
  }
  state.select(originalID)
  #expect(state.workspace.notes.count == 81)

  let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
  let searchController = WorkspaceSearchController(searchOperation: { _, notes, limit in
    notes.dropFirst().prefix(limit).map { note in
      WorkspaceSearchResult(
        noteID: note.id,
        displayTitle: note.displayTitle,
        snippet: note.body,
        match: WorkspaceSearchMatch(field: .title, location: 0, length: 1),
        score: 1
      )
    }
  })
  let host = NSHostingView(
    rootView: NotesPanel(
      dictationRuntime: runtime,
      sizing: .container,
      searchController: searchController
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
  await settleWorkspaceSearchHost(host)
  let editor = try #require(hostedWorkspaceSearchDescendant(in: host, as: ListAwareTextView.self))
  #expect(window.makeFirstResponder(editor))
  #expect(window.firstResponder === editor)
  let initialScrollViews = hostedWorkspaceSearchScrollViews(in: host)
  let initialScrollViewIDs = Set(initialScrollViews.map { ObjectIdentifier($0) })

  searchController.present()
  await settleWorkspaceSearchHost(host)
  searchController.setQuery("Result", in: state.workspace.notes)
  await settleWorkspaceSearchHost(host)
  try await Task.sleep(for: .milliseconds(20))
  await settleWorkspaceSearchHost(host)
  #expect(searchController.results.count == 50)

  let scrollViews = hostedWorkspaceSearchScrollViews(in: host)
  #expect(scrollViews.count == initialScrollViews.count + 1)
  let newPaletteScrollViews = scrollViews.filter {
    !initialScrollViewIDs.contains(ObjectIdentifier($0))
  }
  #expect(newPaletteScrollViews.count == 1)
  let resultScrollView = try #require(newPaletteScrollViews.first)

  let firstBounds = resultScrollView.contentView.bounds
  for _ in 0..<12 {
    searchController.moveHighlight(.down)
    await settleWorkspaceSearchHost(host)
  }
  await settleWorkspaceSearchHost(host)
  #expect(searchController.highlightedNoteID == searchController.results[12].noteID)
  #expect(resultScrollView.contentView.bounds.origin.y > firstBounds.origin.y)

  searchController.dismiss()
  await settleWorkspaceSearchHost(host)
  #expect(!searchController.isPresented)
  #expect(window.firstResponder === editor)

  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
}

@MainActor
private func hostedWorkspaceSearchDescendant<T: NSView>(in view: NSView, as type: T.Type) -> T? {
  if let match = view as? T { return match }
  for subview in view.subviews {
    if let match = hostedWorkspaceSearchDescendant(in: subview, as: type) { return match }
  }
  return nil
}

@MainActor
private func hostedWorkspaceSearchDescendants<T: NSView>(in view: NSView, as type: T.Type) -> [T] {
  var matches: [T] = []
  if let match = view as? T { matches.append(match) }
  for subview in view.subviews {
    matches.append(contentsOf: hostedWorkspaceSearchDescendants(in: subview, as: type))
  }
  return matches
}

@MainActor
private func hostedWorkspaceSearchScrollViews(in view: NSView) -> [NSScrollView] {
  var scrollViews: [NSScrollView] = []
  if let scrollView = view as? NSScrollView {
    scrollViews.append(scrollView)
  }
  for subview in view.subviews {
    scrollViews.append(contentsOf: hostedWorkspaceSearchScrollViews(in: subview))
  }
  return scrollViews
}

@MainActor
private func settleWorkspaceSearchHost(_ view: NSView) async {
  for _ in 0..<40 {
    view.layoutSubtreeIfNeeded()
    await Task.yield()
  }
}
