import Foundation
import Testing

@testable import FleckCore

@Test func everyPaletteTokenMatchesItsApprovedDesignDocument() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

  for family in FleckColorTheme.allCases {
    let design = try String(
      contentsOf: root.appendingPathComponent("docs/themes/\(family.rawValue)/design.md"),
      encoding: .utf8
    )
    var documented: [String: (String, String)] = [:]
    for line in design.components(separatedBy: .newlines) {
      let cells = line.split(separator: "|").map {
        $0.trimmingCharacters(in: .whitespacesAndNewlines)
      }
      guard cells.count == 3,
        cells[0].hasPrefix("`") && cells[0].hasSuffix("`"),
        cells[1].hasPrefix("`") && cells[1].hasSuffix("`"),
        cells[2].hasPrefix("`") && cells[2].hasSuffix("`")
      else { continue }
      let role = String(cells[0].dropFirst().dropLast())
      documented[role] = (
        String(cells[1].dropFirst().dropLast()),
        String(cells[2].dropFirst().dropLast())
      )
    }

    #expect(documented.count == FleckThemeColor.allCases.count)
    for appearance in FleckThemeAppearance.allCases {
      let palette = FleckThemePalette.resolve(family: family, appearance: appearance)
      for role in FleckThemeColor.allCases {
        let values = try #require(documented[role.rawValue])
        #expect(palette[role] == (appearance == .light ? values.0 : values.1))
      }
    }
  }
}

@Test func paletteForegroundsMeetTextAndInterfaceContrastRequirements() {
  let surfaces: [FleckThemeColor] = [
    .window, .sidebar, .editorOpaque, .card, .raised, .capsuleSurface,
  ]
  let text: [FleckThemeColor] = [
    .textPrimary, .textSecondary, .caption, .link, .success, .warning, .error,
  ]

  for family in FleckColorTheme.allCases {
    for appearance in FleckThemeAppearance.allCases {
      let palette = FleckThemePalette.resolve(family: family, appearance: appearance)
      for foreground in text {
        for background in surfaces {
          #expect(contrast(palette[foreground], against: palette[background]) >= 4.5)
        }
      }
      #expect(contrast(palette[.selectionText], against: palette[.selectionFill]) >= 4.5)
      #expect(contrast(palette[.accentText], against: palette[.accent]) >= 4.5)
      #expect(contrast(palette[.capsuleText], against: palette[.capsuleSurface]) >= 4.5)

      for foreground in [FleckThemeColor.border, .focusRing, .accent, .link, .capsuleBorder] {
        for background in surfaces {
          #expect(contrast(palette[foreground], against: palette[background]) >= 3)
        }
      }
    }
  }
}

@Test func palettesKeepTheSharedLightStructureAndOledTrueBlack() {
  for family in FleckColorTheme.allCases {
    let light = FleckThemePalette.resolve(family: family, appearance: .light)
    #expect(light[.window] == "#FFFFFF")
    #expect(light[.editorOpaque] == "#FFFFFF")
    #expect(light[.card] == "#FFFFFF")
    #expect(light[.raised] == "#FFFFFF")
    #expect(light[.sidebar] == "#F2F4F6")
  }
  let oledDark = FleckThemePalette.resolve(family: .oled, appearance: .dark)
  #expect(oledDark[.window] == "#000000")
  #expect(oledDark[.editorOpaque] == "#000000")
}

private func contrast(_ foreground: String, against background: String) -> Double {
  let foreground = luminance(foreground)
  let background = luminance(background)
  return (max(foreground, background) + 0.05) / (min(foreground, background) + 0.05)
}

private func luminance(_ hex: String) -> Double {
  let values = [1, 3, 5].map { index in
    Double(Int(hex.dropFirst(index).prefix(2), radix: 16)!) / 255
  }
  func linear(_ value: Double) -> Double {
    value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
  }
  return zip(values, [0.2126, 0.7152, 0.0722]).reduce(0) {
    $0 + linear($1.0) * $1.1
  }
}
