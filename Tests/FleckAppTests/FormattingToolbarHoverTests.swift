import Foundation
import Testing

@Suite("FormattingToolbarHover")
struct FormattingToolbarHoverTests {
  @Test func sharedStyleOwnsPerButtonHoverWithoutChangingGeometry() throws {
    let source = try notesPanelSource()
    let style = try #require(
      source.components(separatedBy: "private struct CrispToolbarButtonStyle").last?
        .components(separatedBy: "private struct SaveFeedbackView").first
    )

    #expect(style.contains("CrispToolbarButtonBody(configuration: configuration, motion: motion)"))
    #expect(style.contains("@Environment(\\.isEnabled) private var isEnabled"))
    #expect(style.contains("@State private var isHovered = false"))
    #expect(style.contains(".onHover { isHovered = $0 }"))
    #expect(style.contains("isEnabled && isHovered"))
    #expect(style.contains("Color.primary.opacity(0.10)"))
    #expect(style.contains("RoundedRectangle(cornerRadius: 5)"))
    #expect(style.contains(".scaleEffect(configuration.isPressed ? motion.pressScale : 1)"))
    #expect(style.contains(".animation(motion.quick, value: configuration.isPressed)"))
    #expect(!style.contains(".padding("))
    #expect(!style.contains(".frame("))
    #expect(!style.contains(".overlay("))
  }

  @Test func existingIconTargetsAndSelectedStateRemainIntact() throws {
    let source = try notesPanelSource()
    let marker = try #require(
      source.components(separatedBy: "struct HighlighterMarkerIcon: View").last?
        .components(separatedBy: "private struct ToolbarIconLabel").first
    )
    let icon = try #require(
      source.components(separatedBy: "private struct ToolbarIconLabel").last?
        .components(separatedBy: "#endif").first
    )

    #expect(marker.contains(".frame(width: 28, height: 26)"))
    #expect(marker.contains(".contentShape(RoundedRectangle(cornerRadius: 5))"))
    #expect(icon.contains(".frame(width: 28, height: 26)"))
    #expect(icon.contains("isActive ? theme.color(.selectionFill) : .clear"))
    #expect(icon.contains(".contentShape(RoundedRectangle(cornerRadius: 5))"))
  }

  @Test func fontSizeFieldUsesNeutralKeyboardFocusStyling() throws {
    let source = try notesPanelSource()
    let field = try #require(
      source.components(separatedBy: "private func fontSizeField(").last?
        .components(separatedBy: "private var isFontTitleTarget").first
    )

    #expect(field.contains(".textFieldStyle(.plain)"))
    #expect(field.contains(".focusEffectDisabled()"))
    #expect(field.contains(".focused($isFontSizeFocused)"))
    #expect(field.contains(".fleckNeutralControlOutline("))
    #expect(field.contains("isFocused: isFontSizeFocused"))
    #expect(field.contains("idleOpacity: 0.22"))
    #expect(!field.contains(".textFieldStyle(.roundedBorder)"))
    #expect(field.contains(".onSubmit { applyFontSizeText(targetNoteID: targetNoteID) }"))
    #expect(field.contains("if wasFocused && !isFocused {"))
    #expect(field.contains("applyFontSizeText(targetNoteID: targetNoteID)"))
  }

  private func notesPanelSource() throws -> String {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return try String(
      contentsOf: root.appendingPathComponent("Sources/FleckApp/NotesPanel.swift"),
      encoding: .utf8
    )
  }
}
