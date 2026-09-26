import AppKit
import Foundation
import Testing

@testable import FleckApp

@Test func selectedNoteTabLabelInkContrastsWithCapsuleFillInLightAndDark() throws {
  let cases: [(NSColor, NSColor, NSColor)] = [
    (
      .white,
      try #require(NSColor(hex: "#F2F3F5")),
      .black
    ),
    (
      try #require(NSColor(hex: "#1C1C1E")),
      try #require(NSColor(hex: "#282A2E")),
      .white
    ),
  ]

  for (surfaceColor, tabColor, expectedInk) in cases {
    let capsuleFill = NoteTabInk.selectedCapsuleFill(
      tabColor: tabColor,
      surfaceColor: surfaceColor
    )
    let ink = NoteTabInk.selectedLabelColor(tabColor: tabColor, surfaceColor: surfaceColor)

    #expect(capsuleFill.alphaComponent == 1)
    #expect(FleckColorContrast.contrastRatio(ink, against: capsuleFill) >= 4.5)
    #expect(ink.usingColorSpace(.sRGB)?.isEqual(expectedInk.usingColorSpace(.sRGB)) == true)
  }
}

@Test func selectedNoteTabUsesContrastSafeInkAgainstItsCapsuleFill() throws {
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
  let selectedLabelInk = try #require(
    source.components(separatedBy: "private func selectedTabLabelInk").last?
      .components(separatedBy: "@ViewBuilder").first
  )

  #expect(tabStrip.contains("selectedTabLabelInk(for: note)"))
  #expect(tabStrip.contains("selectedTabCapsuleFill(for: $0)"))
  #expect(selectedLabelInk.contains("NoteTabInk.selectedLabelColor("))
  #expect(!tabStrip.contains("note.id == appState.workspace.selectedNoteID || colorScheme == .dark"))
}
