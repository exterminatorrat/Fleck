import Foundation
import Testing

@Suite("ChromeHoverFill")
struct ChromeHoverFillTests {
  @Test func sharedHoverWashMatchesTheChromeButtonTreatment() throws {
    let source = try themeSnapshotSource()
    let modifier = try #require(
      source.components(separatedBy: "private struct FleckHoverFill").last?
        .components(separatedBy: "extension View").first
    )

    #expect(modifier.contains("@Environment(\\.isEnabled) private var isEnabled"))
    #expect(modifier.contains("@Environment(\\.fleckThemeSnapshot) private var theme"))
    #expect(modifier.contains("@State private var isHovered = false"))
    #expect(modifier.contains("if isEnabled, isHovered, isAllowed"))
    #expect(modifier.contains("theme.increasedContrast ? 0.18 : 0.08"))
    #expect(modifier.contains(".onHover { isHovered = $0 }"))
    #expect(!modifier.contains(".padding("))
    #expect(!modifier.contains(".frame("))
  }

  @Test func mainUIRowAndIconButtonsOptIn() throws {
    let source = try notesPanelSource()
    let anchors = [
      "nativeNoteDropAnchor(.folder(folder.id))",
      "accessibilityIdentifier(\"folder-trash\")",
      "accessibilityIdentifier(\"folder-unfiled\")",
      "accessibilityIdentifier(\"folder-new\")",
      "accessibilityLabel(\"Create folder\")",
      "accessibilityLabel(\"Cancel new folder\")",
      "accessibilityLabel(\"Reveal earlier folders\")",
      "accessibilityLabel(\"Reveal later folders\")",
      "accessibilityLabel(\"Reveal earlier tabs\")",
      "accessibilityLabel(\"Reveal later tabs\")",
      "accessibilityIdentifier(\"note-tab-",
      #".help("Dismiss \(label)")"#,
      "isUnfiledCompact ? \"Expand Unfiled\" : \"Collapse Unfiled\"",
    ]

    for anchor in anchors {
      #expect(
        hoverFillPrecedes(anchor, in: source),
        "missing hover fill for \(anchor)"
      )
    }
  }

  @Test func selectedNoteTabKeepsItsOwnCapsule() throws {
    let source = try notesPanelSource()

    #expect(source.contains("in: Capsule()"))
    #expect(source.contains("isAllowed: note.id != appState.workspace.selectedNoteID"))
  }

  private func hoverFillPrecedes(_ anchor: String, in source: String) -> Bool {
    guard let range = source.range(of: anchor) else { return false }
    let precedingLines = source[..<range.lowerBound]
      .split(separator: "\n", omittingEmptySubsequences: false)
      .suffix(6)
      .joined(separator: "\n")
    return precedingLines.contains(".fleckHoverFill")
  }

  private func themeSnapshotSource() throws -> String {
    try repositorySource("Sources/FleckApp/FleckThemeSnapshot.swift")
  }

  private func notesPanelSource() throws -> String {
    try repositorySource("Sources/FleckApp/NotesPanel.swift")
  }

  private func repositorySource(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
  }
}
