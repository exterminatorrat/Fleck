import Foundation
import Testing

@Test func selectedNoteTabUsesWhiteInBothAppearances() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let source = try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/NotesPanel.swift"),
    encoding: .utf8
  )
  let tabStrip = try #require(
    source.components(separatedBy: "private var tabStrip").last?
      .components(separatedBy: "private var motion").first
  )

  #expect(tabStrip.contains("note.id == appState.workspace.selectedNoteID || colorScheme == .dark"))
  #expect(tabStrip.contains("? Color.white : Color.black"))
}
