import AppKit
import Foundation
import FleckCore
import SwiftUI
import Testing

@testable import FleckApp

@Suite(.serialized)
struct WorkspaceSearchHostingTests {

@Test @MainActor
func WorkspaceSearchPresentationSelectsPointerAndKeyboardMotionKinds() {
  #expect(
    WorkspaceSearchPresentationKind.resolve(
      activation: .pointer,
      reduceMotion: false
    ) == .inline
  )
  #expect(
    WorkspaceSearchPresentationKind.resolve(
      activation: .pointer,
      reduceMotion: true
    ) == .crossfade
  )
  #expect(
    WorkspaceSearchPresentationKind.resolve(
      activation: .keyboard,
      reduceMotion: false
    ) == .instant
  )
  #expect(
    WorkspaceSearchPresentationKind.resolve(
      activation: .keyboard,
      reduceMotion: true
    ) == .instant
  )
  #expect(WorkspaceSearchPresentationKind.inline.interactionSource == .pointer)
  #expect(WorkspaceSearchPresentationKind.crossfade.interactionSource == .pointer)
  #expect(WorkspaceSearchPresentationKind.instant.interactionSource == .keyboard)
  #expect(WorkspaceSearchPresentationKind.inline.usesAnimatedDismissal)
  #expect(WorkspaceSearchPresentationKind.crossfade.usesAnimatedDismissal)
  #expect(!WorkspaceSearchPresentationKind.instant.usesAnimatedDismissal)

  let controller = WorkspaceSearchController()
  controller.present(presentation: .inline)
  #expect(controller.presentationKind == .inline)
  controller.dismiss()
  controller.present(presentation: .crossfade)
  #expect(controller.presentationKind == .crossfade)
}

@Test
func WorkspaceSearchHostingUsesNoMatchedGeometryWiring() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let notesPanel = try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/NotesPanel.swift"),
    encoding: .utf8
  )
  let searchView = try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/WorkspaceSearchView.swift"),
    encoding: .utf8
  )

  #expect(!notesPanel.contains("WorkspaceSearchTransition"))
  #expect(!searchView.contains("WorkspaceSearchTransition"))
  #expect(!searchView.contains("matchedGeometryEffect"))
}

@Test @MainActor
func WorkspaceSearchHostingUsesACompactTrailingSurfaceAt640Points() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("workspace-search-compact-640-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let state = AppState(store: LocalStore(rootURL: root), saveOperation: { _, _, _ in })
  await state.waitUntilInitialLoad()
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

  searchController.present(presentation: .inline)
  await settleWorkspaceSearchHost(host)
  let queryField = try #require(
    hostedWorkspaceSearchDescendants(in: host, as: NSTextField.self)
      .first { $0.placeholderString == "Search notes" }
  )
  let queryFrame = queryField.convert(queryField.bounds, to: host)

  #expect(queryFrame.width <= 320)
  #expect(queryFrame.minX >= host.bounds.maxX - 370)
  #expect(queryFrame.maxX <= host.bounds.maxX - 10)

  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
}

@Test @MainActor
func WorkspaceSearchHostingKeepsCompactSurfaceInsideMinimumWidth() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("workspace-search-compact-380-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let state = AppState(store: LocalStore(rootURL: root), saveOperation: { _, _, _ in })
  await state.waitUntilInitialLoad()
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
    contentRect: NSRect(x: 0, y: 0, width: 380, height: 430),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = host
  window.makeKeyAndOrderFront(nil)
  await settleWorkspaceSearchHost(host)

  searchController.present(presentation: .inline)
  await settleWorkspaceSearchHost(host)
  let queryField = try #require(
    hostedWorkspaceSearchDescendants(in: host, as: NSTextField.self)
      .first { $0.placeholderString == "Search notes" }
  )
  let queryFrame = queryField.convert(queryField.bounds, to: host)

  #expect(queryFrame.width <= 320)
  #expect(queryFrame.minX >= 10)
  #expect(queryFrame.maxX <= host.bounds.maxX - 10)

  let hStackSpacing: CGFloat = 8
  let closeGlyphWidth: CGFloat = 15
  let dismissPoint = NSPoint(
    x: queryFrame.maxX + hStackSpacing + closeGlyphWidth / 2,
    y: queryFrame.midY
  )
  #expect(dismissPoint.x >= host.bounds.maxX - 40)
  #expect(dismissPoint.x <= host.bounds.maxX - 10)
  clickWorkspaceSearchControl(host.convert(dismissPoint, to: nil), in: window)
  await settleWorkspaceSearchHost(host)
  #expect(!searchController.isPresented)

  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
}

@Test
func WorkspaceSearchDismissalsUseNotesPanelAnimationContract() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let notesPanel = try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/NotesPanel.swift"),
    encoding: .utf8
  )
  let searchView = try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/WorkspaceSearchView.swift"),
    encoding: .utf8
  )

  #expect(notesPanel.contains("onDismiss: dismissWorkspaceSearch"))
  #expect(notesPanel.contains("searchController.presentationKind.usesAnimatedDismissal"))
  #expect(notesPanel.contains("motion.presentationAnimation(for: presentation.interactionSource)"))
  #expect(!notesPanel.contains("value: searchController.isPresented"))
  #expect(searchView.contains("let onDismiss: () -> Void"))
  #expect(searchView.contains("onDismiss: onDismiss"))
  #expect(searchView.contains("onDismiss()"))
}

@Test @MainActor
func WorkspaceSearchHostingPointerDismissRestoresEditorFocus() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("workspace-search-pointer-focus-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let note = Note(title: "Focus title", body: "Keep this body")
  let state = AppState(
    store: LocalStore(rootURL: root),
    saveOperation: { _, _, _, _ in .committed }
  )
  await state.waitUntilInitialLoad()
  state.workspace = Workspace(notes: [note], selectedNoteID: note.id)

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

  let editor = try #require(
    hostedWorkspaceSearchDescendants(in: host, as: ListAwareTextView.self)
      .first { $0.string == note.body }
  )
  #expect(window.makeFirstResponder(editor))
  let bodySelection = NSRange(location: 2, length: 4)
  editor.setSelectedRange(bodySelection)

  let searchButton = try #require(workspaceSearchTrigger(in: host))
  clickWorkspaceSearchControl(searchButton, in: window)
  await settleWorkspaceSearchHost(host)

  #expect(searchController.isPresented)
  #expect(searchController.presentationKind == .inline)
  sendWorkspaceSearchEscape(to: window)
  await settleWorkspaceSearchHost(host)

  #expect(!searchController.isPresented)
  #expect(commands.textView === editor)
  #expect(editor.selectedRange() == bodySelection)
  #expect(window.firstResponder === editor)

  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
}

@Test @MainActor
func WorkspaceSearchHostingImmediateReopenSurvivesOldDisappearance() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("workspace-search-reopen-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let state = AppState(
    store: LocalStore(rootURL: root),
    saveOperation: { _, _, _, _ in .committed }
  )
  await state.waitUntilInitialLoad()
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

  searchController.present(presentation: .inline)
  let firstPresentationID = searchController.presentationID
  await settleWorkspaceSearchHost(host)
  searchController.dismiss()
  searchController.present(presentation: .instant)
  let reopenedPresentationID = searchController.presentationID
  #expect(reopenedPresentationID != firstPresentationID)
  searchController.dismiss(ifPresentationID: firstPresentationID)
  #expect(searchController.isPresented)
  searchController.setQuery("still open", in: state.workspace.notes)
  await settleWorkspaceSearchHost(host)
  try await Task.sleep(for: .milliseconds(400))
  await settleWorkspaceSearchHost(host)

  #expect(searchController.isPresented)
  #expect(searchController.presentationKind == .instant)
  #expect(searchController.query == "still open")

  searchController.dismiss()
  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
}

@Test @MainActor
func WorkspaceSearchHostingImmediateReopenKeepsQueryFocusAfterOldRestoreRetry()
  async throws
{
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("workspace-search-focus-reopen-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let note = Note(title: "Focus title", body: "Keep this body")
  let state = AppState(
    store: LocalStore(rootURL: root),
    saveOperation: { _, _, _, _ in .committed }
  )
  await state.waitUntilInitialLoad()
  state.workspace = Workspace(notes: [note], selectedNoteID: note.id)

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

  let editor = try #require(
    hostedWorkspaceSearchDescendants(in: host, as: ListAwareTextView.self)
      .first { $0.string == note.body }
  )
  #expect(window.makeFirstResponder(editor))

  searchController.present(for: note.id)
  await settleWorkspaceSearchHost(host)
  let firstQueryField = try #require(
    hostedWorkspaceSearchDescendants(in: host, as: NSTextField.self)
      .first { $0.placeholderString == "Search notes" }
  )
  #expect(window.makeFirstResponder(firstQueryField))

  searchController.dismiss()
  searchController.present(for: note.id)
  var reopenedField: NSTextField?
  for _ in 0..<8 {
    host.layoutSubtreeIfNeeded()
    reopenedField = hostedWorkspaceSearchDescendants(in: host, as: NSTextField.self)
      .first { $0.placeholderString == "Search notes" }
    if reopenedField != nil { break }
    await Task.yield()
  }
  let reopenedQueryField = try #require(reopenedField)
  #expect(window.makeFirstResponder(reopenedQueryField))
  let reopenedQueryEditor = try #require(
    reopenedQueryField.currentEditor() as? NSTextView
  )
  #expect(window.firstResponder === reopenedQueryEditor)

  try await Task.sleep(for: .milliseconds(400))
  await settleWorkspaceSearchHost(host)

  #expect(searchController.isPresented)
  #expect(window.firstResponder === reopenedQueryEditor)
  #expect(reopenedQueryField.currentEditor() === reopenedQueryEditor)

  searchController.dismiss()
  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
}

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
  let searchDeadline = ContinuousClock.now + .seconds(1)
  while
    (!searchController.resultsAreCurrent
      || searchController.results.map(\.noteID) != [titleNoteID]),
    ContinuousClock.now < searchDeadline
  {
    await Task.yield()
  }
  #expect(
    searchController.resultsAreCurrent
      && searchController.results.map(\.noteID) == [titleNoteID],
    "Timed out waiting for the current workspace search result"
  )

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
func WorkspaceSearchHostingLinkPickerIsIndependentAndBlocksTheOtherOverlay() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("workspace-search-link-picker-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let state = AppState(store: LocalStore(rootURL: root), saveOperation: { _, _, _ in })
  await state.waitUntilInitialLoad()
  let sourceID = try #require(state.workspace.selectedNoteID)

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
  await settleWorkspaceSearchHost(host)

  let sourceRevision = try #require(state.workspace.notes.first { $0.id == sourceID }?.revision)
  picker.present(
    sourceNoteID: sourceID,
    replacementRange: NSRange(location: 0, length: 0),
    sourceRevision: sourceRevision
  )
  await settleWorkspaceSearchHost(host)
  #expect(picker.isPresented)
  searchController.present(for: sourceID)
  await settleWorkspaceSearchHost(host)
  #expect(picker.isPresented)
  #expect(!searchController.isPresented)

  picker.dismiss()
  await settleWorkspaceSearchHost(host)
  searchController.present(for: sourceID)
  await settleWorkspaceSearchHost(host)
  #expect(searchController.isPresented)
  picker.present(
    sourceNoteID: sourceID,
    replacementRange: NSRange(location: 0, length: 0),
    sourceRevision: sourceRevision
  )
  await settleWorkspaceSearchHost(host)
  #expect(searchController.isPresented)
  #expect(!picker.isPresented)

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

@Test @MainActor
func WorkspaceSearchHostingActivatesNamedFolderResultThroughProductionScope()
  async throws
{
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("workspace-search-folder-activation-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let work = try Folder(
    id: UUID(uuidString: "00000000-0000-0000-0000-0000000000b1")!,
    name: "Work"
  )
  let unfiled = Note(
    id: UUID(uuidString: "00000000-0000-0000-0000-0000000000b2")!,
    title: "Unfiled note",
    body: "Unfiled body"
  )
  var target = Note(
    id: UUID(uuidString: "00000000-0000-0000-0000-0000000000b3")!,
    title: "Named folder target",
    body: "Folder body"
  )
  target.folderID = work.id

  let state = AppState(store: LocalStore(rootURL: root), saveOperation: { _, _, _, _ in .committed })
  await state.waitUntilInitialLoad()
  state.workspace = Workspace(
    notes: [unfiled, target],
    selectedNoteID: unfiled.id,
    folders: [work]
  )

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

  let unfiledEditor = try #require(
    hostedWorkspaceSearchDescendants(in: host, as: ListAwareTextView.self)
      .first { $0.string == unfiled.body }
  )
  #expect(window.makeFirstResponder(unfiledEditor))
  commands.textView?.setSelectedRange(NSRange(location: 0, length: 0))
  commands.refreshFormattingState()

  searchController.present(for: unfiled.id)
  await settleWorkspaceSearchHost(host)
  searchController.setQuery(target.title, in: state.workspace.notes)
  await settleWorkspaceSearchHost(host)
  #expect(searchController.results.map(\.noteID) == [target.id])
  let queryField = try #require(
    hostedWorkspaceSearchDescendants(in: host, as: NSTextField.self)
      .first { $0.placeholderString == "Search notes" }
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
  await settleWorkspaceSearchHost(host)

  #expect(state.workspace.selectedNoteID == target.id)
  #expect(state.folderID(for: target.id) == work.id)
  #expect(!searchController.isPresented)
  let targetEditor = try #require(
    hostedWorkspaceSearchDescendants(in: host, as: ListAwareTextView.self)
      .first { $0.string == target.body }
  )
  #expect(commands.textView === targetEditor)
  #expect(window.firstResponder === targetEditor)

  let newNoteEvent = try #require(
    NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: [.command],
      timestamp: 0,
      windowNumber: window.windowNumber,
      context: nil,
      characters: "t",
      charactersIgnoringModifiers: "t",
      isARepeat: false,
      keyCode: 17
    )
  )
  NSApp.sendEvent(newNoteEvent)
  await settleWorkspaceSearchHost(host)
  let createdNoteID = try #require(state.workspace.selectedNoteID)
  let createdNote = try #require(
    state.workspace.notes.first { $0.id == createdNoteID }
  )
  #expect(createdNote.id != target.id)
  #expect(createdNote.folderID == work.id)

  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
}

@Test @MainActor
func WorkspaceSearchHostingBlocksEveryShortcutWhilePresented() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("workspace-search-shortcuts-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let work = try Folder(id: UUID(), name: "Work")
  let first = Note(title: "First", body: "First body")
  let second = Note(title: "Second", body: "Second body")
  let hidden = Note(title: "Hidden", body: "Hidden body", folderID: work.id)
  let state = AppState(store: LocalStore(rootURL: root), saveOperation: { _, _, _, _ in .committed })
  await state.waitUntilInitialLoad()
  state.workspace = Workspace(
    notes: [first, second, hidden],
    selectedNoteID: first.id,
    folders: [work]
  )
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

  let expectedWorkspace = state.workspace
  let expectedSelectedNoteID = state.workspace.selectedNoteID
  let expectedScope = state.folderScopeForSelectedNote()
  let expectedGeneration = state.persistenceGeneration
  searchController.present(for: first.id)
  await settleWorkspaceSearchHost(host)
  searchController.setQuery("First", in: state.workspace.notes)
  await settleWorkspaceSearchHost(host)
  let queryField = try #require(
    hostedWorkspaceSearchDescendants(in: host, as: NSTextField.self)
      .first { $0.placeholderString == "Search notes" }
  )
  #expect(window.makeFirstResponder(queryField))
  let queryFieldEditor = try #require(window.firstResponder as? NSTextView)
  #expect(queryField.currentEditor() === queryFieldEditor)

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
    await settleWorkspaceSearchHost(host)
  }

  #expect(searchController.isPresented)
  #expect(searchController.query == "First")
  #expect(window.firstResponder === queryFieldEditor)
  #expect(queryField.currentEditor() === queryFieldEditor)
  #expect(state.workspace == expectedWorkspace)
  #expect(state.workspace.selectedNoteID == expectedSelectedNoteID)
  #expect(state.folderScopeForSelectedNote() == expectedScope)
  #expect(state.persistenceGeneration == expectedGeneration)
  #expect(window.isVisible)
  #expect(
    !hostedWorkspaceSearchDescendants(in: host, as: NSButton.self)
      .contains { $0.title == "Confirm" }
  )

  searchController.dismiss()
  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
}

@Test @MainActor
func WorkspaceSearchHostingDismissPreservesFocusScopeWorkspaceAndSaveGeneration()
  async throws
{
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("workspace-search-dismiss-state-" + UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let work = try Folder(id: UUID(), name: "Work")
  let note = Note(title: "Focus note", body: "Keep this body", folderID: work.id)
  let state = AppState(store: LocalStore(rootURL: root), saveOperation: { _, _, _, _ in .committed })
  await state.waitUntilInitialLoad()
  state.workspace = Workspace(notes: [note], selectedNoteID: note.id, folders: [work])

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

  let editor = try #require(
    hostedWorkspaceSearchDescendants(in: host, as: ListAwareTextView.self)
      .first { $0.string == note.body }
  )
  #expect(window.makeFirstResponder(editor))
  let bodySelection = NSRange(location: 2, length: 4)
  editor.setSelectedRange(bodySelection)
  editor.typingAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
  commands.refreshFormattingState()
  let expectedTypingAttributes = NSDictionary(dictionary: editor.typingAttributes)
  let expectedWorkspace = state.workspace
  let expectedGeneration = state.persistenceGeneration
  let expectedScope = state.folderScopeForSelectedNote()

  searchController.present(for: note.id)
  await settleWorkspaceSearchHost(host)
  searchController.dismiss()
  await settleWorkspaceSearchHost(host)

  #expect(state.workspace == expectedWorkspace)
  #expect(state.persistenceGeneration == expectedGeneration)
  #expect(state.folderScopeForSelectedNote() == expectedScope)
  #expect(state.workspace.selectedNoteID == note.id)
  #expect(commands.textView === editor)
  #expect(editor.selectedRange() == bodySelection)
  #expect(NSDictionary(dictionary: editor.typingAttributes).isEqual(to: expectedTypingAttributes))
  #expect(window.firstResponder === editor)

  let titleField = try #require(
    hostedWorkspaceSearchDescendants(in: host, as: NSTextField.self)
      .first { $0.stringValue == note.title && $0.frame.width > 200 }
  )
  #expect(window.makeFirstResponder(titleField))
  let titleEditor = try #require(window.firstResponder as? NSTextView)
  let titleSelection = NSRange(location: 1, length: 3)
  titleEditor.setSelectedRange(titleSelection)
  let expectedTitle = titleField.stringValue

  searchController.present(for: note.id)
  await settleWorkspaceSearchHost(host)
  searchController.dismiss()
  await settleWorkspaceSearchHost(host)

  #expect(state.workspace == expectedWorkspace)
  #expect(state.persistenceGeneration == expectedGeneration)
  #expect(state.folderScopeForSelectedNote() == expectedScope)
  #expect(titleField.stringValue == expectedTitle)
  let restoredTitleEditor = try #require(window.firstResponder as? NSTextView)
  #expect(restoredTitleEditor === titleEditor)
  #expect(restoredTitleEditor.selectedRange() == titleSelection)

  window.contentView = nil
  window.orderOut(nil)
  await runtime.shutdown()
}

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
private func workspaceSearchTrigger(in view: NSView) -> NSView? {
  let headerControls = hostedWorkspaceSearchDescendants(in: view, as: NSView.self)
    .filter { control in
      guard String(describing: type(of: control)) == "KeyViewProxy" else { return false }
      let frame = control.convert(control.bounds, to: view)
      return frame.minY < 40 && frame.minX > view.bounds.midX
    }
    .sorted {
      $0.convert($0.bounds, to: view).minX < $1.convert($1.bounds, to: view).minX
    }
  return headerControls.dropFirst().first
}

@MainActor
private func clickWorkspaceSearchControl(_ control: NSView, in window: NSWindow) {
  let point = control.convert(
    NSPoint(x: control.bounds.midX, y: control.bounds.midY),
    to: nil
  )
  clickWorkspaceSearchControl(point, in: window)
}

@MainActor
private func clickWorkspaceSearchControl(_ point: NSPoint, in window: NSWindow) {
  let screenPoint = window.convertPoint(toScreen: point)
  for eventType in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
    guard let event = NSEvent.mouseEvent(
      with: eventType,
      location: screenPoint,
      modifierFlags: [],
      timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: window.windowNumber,
      context: nil,
      eventNumber: 0,
      clickCount: 1,
      pressure: eventType == .leftMouseDown ? 1 : 0
    ) else { continue }
    NSApp.sendEvent(event)
  }
}

@MainActor
private func sendWorkspaceSearchEscape(to window: NSWindow) {
  guard let event = NSEvent.keyEvent(
    with: .keyDown,
    location: .zero,
    modifierFlags: [],
    timestamp: ProcessInfo.processInfo.systemUptime,
    windowNumber: window.windowNumber,
    context: nil,
    characters: "\u{1b}",
    charactersIgnoringModifiers: "\u{1b}",
    isARepeat: false,
    keyCode: 53
  ) else { return }
  window.sendEvent(event)
}

@MainActor
private func settleWorkspaceSearchHost(_ view: NSView) async {
  for _ in 0..<40 {
    view.layoutSubtreeIfNeeded()
    await Task.yield()
  }
}
