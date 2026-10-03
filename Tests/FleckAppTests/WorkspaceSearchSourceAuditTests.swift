import Foundation
import Testing

@testable import FleckApp

@Test
func WorkspaceSearchSourceAuditUsesTheProductionPanelAndNativeOverlay() throws {
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

  for required in [
    "WorkspaceSearchView(",
    "searchController.present(for: appState.workspace.selectedNoteID)",
    "accent: theme.color(.accent)",
    ".keyboardShortcut(\"f\", modifiers: .command)",
    ".accessibilityLabel(\"Search notes\")",
    ".help(\"Search notes",
    ".overlay",
    ".allowsHitTesting(!searchController.isPresented)",
    ".disabled(searchController.isPresented)",
    ".accessibilityHidden(searchController.isPresented)",
  ] {
    #expect(notesPanel.contains(required), Comment(rawValue: required))
  }
  for required in [
    "TextField(",
    ".onKeyPress(.upArrow)",
    ".onKeyPress(.downArrow)",
    ".onKeyPress(.return)",
    ".onKeyPress(.escape)",
    "accessibilityValue",
    "Selected",
    "Not selected",
    "Set<UUID>",
    "ScrollView",
    "LazyVStack",
    ".onMoveCommand",
    ".onExitCommand",
  ] {
    #expect(searchView.contains(required), Comment(rawValue: required))
  }
  #expect(
    searchView.components(
      separatedBy: "Text(\n                          workspaceSearchHighlightedAttributedString("
    ).count - 1 == 2
  )
  #expect(searchView.components(separatedBy: "underlineMatches: isSelected").count - 1 == 2)
  #expect(
    searchView.components(
      separatedBy: "accent: isSelected ? theme.color(.selectionText) : accent"
    ).count - 1 == 2
  )
  #expect(
    searchView.contains(#".accessibilityLabel("\(result.displayTitle), \(result.snippet)")"#)
  )
  #expect(!searchView.contains(".sheet("))
  #expect(!searchView.contains("NativeRichTextEditor("))
  #expect(!searchView.contains("WorkspaceSearchKeyResponder"))
  #expect(!searchView.contains("WorkspaceSearchEngine.search(query: query, in: notes, limit: 50)"))
  #expect(!notesPanel.contains("WorkspaceSearchTransition"))
  #expect(!searchView.contains("WorkspaceSearchTransition"))
  #expect(!searchView.contains("matchedGeometryEffect"))
  #expect(notesPanel.contains("workspaceSearchPresentationTransition"))
  #expect(notesPanel.contains("scale(scale: 0.98, anchor: .topTrailing)"))
  #expect(searchView.contains(".frame(maxWidth: 360"))
  #expect(searchView.contains(".padding(.horizontal, 10)"))
  #expect(searchView.contains(".padding(.top, 8)"))

  let formattingBar = try #require(notesPanel.components(separatedBy: "private struct FormattingBar: View").last)
  let formattingBarSurface = try #require(
    formattingBar
      .components(separatedBy: "private struct FormattingBarSurface: ViewModifier")
      .dropFirst()
      .first?
      .components(separatedBy: "private struct PinnedWritingSurface")
      .first
  )
  #expect(!formattingBar.contains(".background(.bar)"))
  #expect(formattingBar.contains(".modifier(FormattingBarSurface(isPinned: isPinned))"))
  #expect(formattingBarSurface.contains("@Environment(\\.fleckThemeSnapshot) private var theme"))
  #expect(formattingBarSurface.contains("FleckChromeMaterialPolicy.current("))
  #expect(formattingBarSurface.contains("case .liquidGlass"))
  #expect(formattingBarSurface.contains("case .opaque"))
}

@Test
func WorkspaceSearchSourceAuditDoesNotOutlineTheQueryFieldSeparatelyFromItsPanel() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let searchView = try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/WorkspaceSearchView.swift"),
    encoding: .utf8
  )
  let queryField = try #require(
    searchView
      .components(separatedBy: "TextField(\"Search notes\"")
      .dropFirst()
      .first?
      .components(separatedBy: ".onKeyPress(.upArrow)")
      .first
  )

  #expect(queryField.contains(".textFieldStyle(.plain)"))
  #expect(queryField.contains(".focused($isQueryFocused)"))
  #expect(queryField.contains(".accessibilityLabel(\"Search notes\")"))
  #expect(queryField.contains(".accessibilityHint(\"Search note titles and bodies\")"))
  #expect(!queryField.contains(".fleckNeutralControlOutline("))
  #expect(searchView.contains(".fill(.regularMaterial)"))
  #expect(searchView.contains(".strokeBorder(.quaternary)"))
}

@Test
func WorkspaceSearchSourceAuditRetainsFolderAwareUnderlayAndNewNoteRouting() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let source = try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/NotesPanel.swift"),
    encoding: .utf8
  )

  #expect(source.contains("folderNavigator"))
  #expect(source.contains("scopedEditor"))
  #expect(source.contains(".allowsHitTesting(!searchController.isPresented)"))
  #expect(source.contains(".accessibilityHidden(searchController.isPresented)"))
  #expect(source.contains("appState.addNote(inFolderID: activeFolderID)"))
  #expect(source.contains("currentNoteIDs:"))
  #expect(source.contains("activateNoteAndScope"))
}
