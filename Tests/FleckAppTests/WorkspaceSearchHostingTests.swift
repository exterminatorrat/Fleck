import AppKit
import Foundation
import FleckCore
import SwiftUI
import Testing

@testable import FleckApp

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

@MainActor
private func hostedWorkspaceSearchDescendant<T: NSView>(in view: NSView, as type: T.Type) -> T? {
  if let match = view as? T { return match }
  for subview in view.subviews {
    if let match = hostedWorkspaceSearchDescendant(in: subview, as: type) { return match }
  }
  return nil
}

@MainActor
private func settleWorkspaceSearchHost(_ view: NSView) async {
  for _ in 0..<40 {
    view.layoutSubtreeIfNeeded()
    await Task.yield()
  }
}
