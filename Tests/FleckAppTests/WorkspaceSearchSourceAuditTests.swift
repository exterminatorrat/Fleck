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
    "accent: Color(hex: appState.preferences.accentHex) ?? .accentColor",
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
  #expect(searchView.components(separatedBy: "accent: accent").count - 1 == 2)
  #expect(
    searchView.contains(#".accessibilityLabel("\(result.displayTitle), \(result.snippet)")"#)
  )
  #expect(!searchView.contains(".sheet("))
  #expect(!searchView.contains("NativeRichTextEditor("))
  #expect(!searchView.contains("WorkspaceSearchKeyResponder"))
  #expect(!searchView.contains("WorkspaceSearchEngine.search(query: query, in: notes, limit: 50)"))
}
