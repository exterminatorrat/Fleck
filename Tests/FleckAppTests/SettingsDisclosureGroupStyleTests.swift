import Foundation
import Testing

@testable import FleckApp

@Suite("Settings disclosure group style")
struct SettingsDisclosureGroupStyleTests {
  @Test func styleUsesOneFullWidthButtonAndKeepsContentOutsideIt() throws {
    let style = try source(named: "SettingsDisclosureGroupStyle.swift")

    #expect(style.contains("struct SettingsDisclosureGroupStyle: DisclosureGroupStyle"))
    #expect(style.components(separatedBy: "Button {").count - 1 == 1)
    let buttonStart = try #require(style.range(of: "        Button {"))
    let buttonEnd = try #require(
      style.range(
        of: "\n        }\n        .buttonStyle(.plain)",
        range: buttonStart.upperBound..<style.endIndex
      )
    )
    let button = style[buttonStart.lowerBound..<buttonEnd.upperBound]
    #expect(
      button.hasPrefix(
        "        Button {\n"
          + "          configuration.isExpanded.toggle()\n"
          + "        } label: {"
      ))
    #expect(
      button.contains(
        "          HStack(spacing: 8) {\n"
          + "            Image(systemName: configuration.isExpanded ? \"chevron.down\" : \"chevron.right\")"
      ))
    #expect(button.contains("configuration.label\n            Spacer(minLength: 0)"))
    #expect(
      button.contains(
        "          }\n"
          + "          .padding(.horizontal, 8)\n"
          + "          .padding(.vertical, 6)\n"
          + "          .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)\n"
          + "          .contentShape(Rectangle())"
      ))
    #expect(style.contains(".buttonStyle(.plain)"))
    #expect(style.contains(".accessibilityHidden(true)"))
    #expect(
      style.contains(
        ".accessibilityValue(configuration.isExpanded ? \"Expanded\" : \"Collapsed\")"
      ))

    let contentStart = try #require(
      style.range(
        of: "\n        if configuration.isExpanded {",
        range: buttonStart.upperBound..<style.endIndex
      )
    )
    #expect(
      !style[buttonStart.lowerBound..<contentStart.lowerBound].contains("configuration.content"))
    #expect(style[contentStart.lowerBound...].contains("configuration.content"))
    #expect(!style.contains("onTapGesture"))
    #expect(!style.contains("animation("))
    #expect(!style.contains("background("))
  }

  @Test func settingsRoutesTheSharedStyleOnceAcrossAllFourCurrentDisclosures() throws {
    let settings = try source(named: "SettingsView.swift")
    let agents = try source(named: "AgentSettingsView.swift")
    let about = try source(named: "AboutSettingsView.swift")
    let modifier = ".disclosureGroupStyle(SettingsDisclosureGroupStyle())"

    for (text, expectedCount) in [(settings, 1), (agents, 2), (about, 1)] {
      #expect(text.components(separatedBy: modifier).count - 1 == expectedCount)
    }
    for (text, start, end) in [
      (
        settings, "        DisclosureGroup(DictationSettingsGroup.privacy.rawValue)",
        "\n    private var readiness:"
      ),
      (agents, "        DisclosureGroup(\"Activity\")", "        DisclosureGroup(\"Access\")"),
      (agents, "        DisclosureGroup(\"Access\")", "\n    private var connectorStatus:"),
      (about, "        DisclosureGroup(\"Full build metadata\")", "        HStack(spacing: 10)"),
    ] {
      let startRange = try #require(text.range(of: start))
      let endRange = try #require(
        text.range(of: end, range: startRange.upperBound..<text.endIndex)
      )
      let disclosure = text[startRange.lowerBound..<endRange.lowerBound]
      #expect(disclosure.components(separatedBy: modifier).count - 1 == 1)
    }
    let transfer = try #require(settings.range(of: "DisclosureGroup(\"Transfer\")"))
    #expect(!settings[transfer.lowerBound...].contains(modifier))
  }

  private func source(named name: String) throws -> String {
    let sourceDirectory = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sources/FleckApp")
    return try String(contentsOf: sourceDirectory.appendingPathComponent(name), encoding: .utf8)
  }
}
