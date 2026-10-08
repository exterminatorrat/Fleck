import Foundation

public enum FleckColorTheme: String, Codable, CaseIterable, Identifiable, Sendable {
  case monochrome
  case capy
  case absolutely
  case oled
  case codex
  case github
  case linear
  case notion

  public var id: Self { self }

  public var title: String {
    switch self {
    case .monochrome: "Fleck Monochrome"
    case .capy: "Capy"
    case .absolutely: "Absolutely"
    case .oled: "OLED"
    case .codex: "Codex"
    case .github: "GitHub"
    case .linear: "Linear"
    case .notion: "Notion"
    }
  }
}

public enum FleckThemeAppearance: String, Codable, CaseIterable, Sendable {
  case light
  case dark
}

public enum FleckThemeColor: String, CaseIterable, Sendable {
  case window
  case sidebar
  case editorOpaque
  case card
  case raised
  case border
  case textPrimary
  case textSecondary
  case caption
  case selectionFill
  case selectionText
  case accent
  case accentText
  case hoverFill
  case focusRing
  case link
  case success
  case warning
  case error
  case capsuleSurface
  case capsuleText
  case capsuleBorder
}

public struct FleckThemePalette: Equatable, Sendable {
  public let family: FleckColorTheme
  public let appearance: FleckThemeAppearance
  private let colors: [FleckThemeColor: String]

  public subscript(_ color: FleckThemeColor) -> String {
    colors[color]!
  }

  public static func resolve(
    family: FleckColorTheme,
    appearance: FleckThemeAppearance
  ) -> Self {
    let isDark = appearance == .dark
    let values: [FleckThemeColor: (String, String)] = [
      .window: ("#FFFFFF", "#18191A"),
      .sidebar: ("#F2F4F6", "#222426"),
      .editorOpaque: ("#FFFFFF", "#191A1B"),
      .card: ("#FFFFFF", "#212224"),
      .raised: ("#FFFFFF", "#2B2D30"),
      .border: ("#767C82", "#888D92"),
      .textPrimary: ("#17191C", "#F2F2F0"),
      .textSecondary: ("#515960", "#BCC0C3"),
      .caption: ("#535B62", "#AEB3B7"),
      .selectionFill: ("#D8DBDE", "#3B3E42"),
      .selectionText: ("#17191C", "#F5F5F2"),
      .accent: ("#42474D", "#D4D7DA"),
      .accentText: ("#FFFFFF", "#202224"),
      .hoverFill: ("#E7EAED", "#2A2C2F"),
      .focusRing: ("#42474D", "#D4D7DA"),
      .link: ("#42474D", "#D4D7DA"),
      .success: ("#216E3A", "#77D99B"),
      .warning: ("#825300", "#FFD166"),
      .error: ("#B42318", "#FF8580"),
      .capsuleSurface: ("#FFFFFF", "#242628"),
      .capsuleText: ("#17191C", "#F2F2F0"),
      .capsuleBorder: ("#767C82", "#888D92"),
    ]
    let colors = values.mapValues { isDark ? $0.1 : $0.0 }

    switch family {
    case .monochrome:
      return Self(family: family, appearance: appearance, colors: colors)
    case .capy:
      return Self(family: family, appearance: appearance, colors: Self.colors(
        window: ("#FFFFFF", "#101A19"), sidebar: ("#F2F4F6", "#182421"),
        editorOpaque: ("#FFFFFF", "#111B1A"), card: ("#FFFFFF", "#1A2725"),
        raised: ("#FFFFFF", "#293532"), border: ("#767C82", "#84928E"),
        textPrimary: ("#17191C", "#EFF8F5"), textSecondary: ("#515960", "#B6C7C2"),
        caption: ("#535B62", "#A8BBB5"), selectionFill: ("#BDE9E2", "#245951"),
        selectionText: ("#0B3632", "#F2FFFC"), accent: ("#006B63", "#74D5C8"),
        accentText: ("#FFFFFF", "#10302B"), hoverFill: ("#E7EAED", "#283431"),
        focusRing: ("#006B63", "#74D5C8"), link: ("#006B63", "#74D5C8"),
        success: ("#216E3A", "#77D99B"), warning: ("#825300", "#FFD166"),
        error: ("#B42318", "#FF8580"), capsuleSurface: ("#FFFFFF", "#1B2926"),
        capsuleText: ("#17191C", "#F2FFFC"), capsuleBorder: ("#767C82", "#84928E"),
        isDark: isDark))
    case .absolutely:
      return Self(family: family, appearance: appearance, colors: Self.colors(
        window: ("#FFFFFF", "#1B1513"), sidebar: ("#F2F4F6", "#261D1A"),
        editorOpaque: ("#FFFFFF", "#1C1614"), card: ("#FFFFFF", "#261E1A"),
        raised: ("#FFFFFF", "#342923"), border: ("#767C82", "#8F807A"),
        textPrimary: ("#17191C", "#FFF4EF"), textSecondary: ("#515960", "#D0BEB5"),
        caption: ("#535B62", "#C1AEA5"), selectionFill: ("#FFD7C8", "#77382B"),
        selectionText: ("#3B170E", "#FFF3ED"), accent: ("#A33C2D", "#FF9B7A"),
        accentText: ("#FFFFFF", "#33150E"), hoverFill: ("#E7EAED", "#30241F"),
        focusRing: ("#A33C2D", "#FF9B7A"), link: ("#A33C2D", "#FF9B7A"),
        success: ("#216E3A", "#77D99B"), warning: ("#825300", "#FFD166"),
        error: ("#B42318", "#FF8580"), capsuleSurface: ("#FFFFFF", "#291F1B"),
        capsuleText: ("#17191C", "#FFF4EF"), capsuleBorder: ("#767C82", "#8F807A"),
        isDark: isDark))
    case .oled:
      return Self(family: family, appearance: appearance, colors: Self.colors(
        window: ("#FFFFFF", "#000000"), sidebar: ("#F2F4F6", "#0B0B0C"),
        editorOpaque: ("#FFFFFF", "#000000"), card: ("#FFFFFF", "#000000"),
        raised: ("#FFFFFF", "#151517"), border: ("#767C82", "#777777"),
        textPrimary: ("#17191C", "#F5F5F7"), textSecondary: ("#515960", "#C3C3C8"),
        caption: ("#535B62", "#B1B1B8"), selectionFill: ("#DCE4EF", "#223957"),
        selectionText: ("#182432", "#F4F8FF"), accent: ("#344554", "#A8C7FA"),
        accentText: ("#FFFFFF", "#111A26"), hoverFill: ("#E7EAED", "#151517"),
        focusRing: ("#344554", "#A8C7FA"), link: ("#344554", "#A8C7FA"),
        success: ("#216E3A", "#77D99B"), warning: ("#825300", "#FFD166"),
        error: ("#B42318", "#FF8580"), capsuleSurface: ("#FFFFFF", "#101012"),
        capsuleText: ("#17191C", "#F5F5F7"), capsuleBorder: ("#767C82", "#777777"),
        isDark: isDark))
    case .codex:
      return Self(family: family, appearance: appearance, colors: Self.colors(
        window: ("#FFFFFF", "#101922"), sidebar: ("#F2F4F6", "#18232B"),
        editorOpaque: ("#FFFFFF", "#111A22"), card: ("#FFFFFF", "#1B252D"),
        raised: ("#FFFFFF", "#28363F"), border: ("#767C82", "#84939D"),
        textPrimary: ("#17191C", "#F0F7FA"), textSecondary: ("#515960", "#B8C7CD"),
        caption: ("#535B62", "#A8BAC1"), selectionFill: ("#CCEBF6", "#1B495C"),
        selectionText: ("#103548", "#EDF9FF"), accent: ("#0D648B", "#83D1F1"),
        accentText: ("#FFFFFF", "#12303B"), hoverFill: ("#E7EAED", "#273842"),
        focusRing: ("#0D648B", "#83D1F1"), link: ("#0D648B", "#83D1F1"),
        success: ("#216E3A", "#77D99B"), warning: ("#825300", "#FFD166"),
        error: ("#B42318", "#FF8580"), capsuleSurface: ("#FFFFFF", "#1A252D"),
        capsuleText: ("#17191C", "#F0F7FA"), capsuleBorder: ("#767C82", "#84939D"),
        isDark: isDark))
    case .github:
      return Self(family: family, appearance: appearance, colors: Self.colors(
        window: ("#FFFFFF", "#0D1117"), sidebar: ("#F2F4F6", "#161B22"),
        editorOpaque: ("#FFFFFF", "#0D1117"), card: ("#FFFFFF", "#161B22"),
        raised: ("#FFFFFF", "#21262D"), border: ("#767C82", "#8B949E"),
        textPrimary: ("#17191C", "#F0F6FC"), textSecondary: ("#515960", "#B1BAC4"),
        caption: ("#535B62", "#A6AFB9"), selectionFill: ("#CFE5FF", "#153D69"),
        selectionText: ("#112C4A", "#E9F4FF"), accent: ("#135FA7", "#79C0FF"),
        accentText: ("#FFFFFF", "#10243A"), hoverFill: ("#E7EAED", "#202732"),
        focusRing: ("#135FA7", "#79C0FF"), link: ("#135FA7", "#79C0FF"),
        success: ("#216E3A", "#77D99B"), warning: ("#825300", "#FFD166"),
        error: ("#B42318", "#FF8580"), capsuleSurface: ("#FFFFFF", "#161B22"),
        capsuleText: ("#17191C", "#F0F6FC"), capsuleBorder: ("#767C82", "#8B949E"),
        isDark: isDark))
    case .linear:
      return Self(family: family, appearance: appearance, colors: Self.colors(
        window: ("#FFFFFF", "#161619"), sidebar: ("#F2F4F6", "#1F1F23"),
        editorOpaque: ("#FFFFFF", "#17171A"), card: ("#FFFFFF", "#202024"),
        raised: ("#FFFFFF", "#2D2D33"), border: ("#767C82", "#8C8C96"),
        textPrimary: ("#17191C", "#F2F2F7"), textSecondary: ("#515960", "#C0BEC9"),
        caption: ("#535B62", "#AEACB9"), selectionFill: ("#E1DCFF", "#423865"),
        selectionText: ("#2B2358", "#F5F2FF"), accent: ("#5547A5", "#C0B6FF"),
        accentText: ("#FFFFFF", "#231A4E"), hoverFill: ("#E7EAED", "#2A2A30"),
        focusRing: ("#5547A5", "#C0B6FF"), link: ("#5547A5", "#C0B6FF"),
        success: ("#216E3A", "#77D99B"), warning: ("#825300", "#FFD166"),
        error: ("#B42318", "#FF8580"), capsuleSurface: ("#FFFFFF", "#202024"),
        capsuleText: ("#17191C", "#F2F2F7"), capsuleBorder: ("#767C82", "#8C8C96"),
        isDark: isDark))
    case .notion:
      return Self(family: family, appearance: appearance, colors: Self.colors(
        window: ("#FFFFFF", "#15191A"), sidebar: ("#F2F4F6", "#1E2224"),
        editorOpaque: ("#FFFFFF", "#161A1B"), card: ("#FFFFFF", "#1E2224"),
        raised: ("#FFFFFF", "#292E30"), border: ("#767C82", "#899093"),
        textPrimary: ("#17191C", "#F3F5F4"), textSecondary: ("#515960", "#B9C0BE"),
        caption: ("#535B62", "#A9B1AF"), selectionFill: ("#D8E6F1", "#224565"),
        selectionText: ("#172A3A", "#F1F8FD"), accent: ("#365978", "#91C8F2"),
        accentText: ("#FFFFFF", "#142536"), hoverFill: ("#E7EAED", "#282E30"),
        focusRing: ("#365978", "#91C8F2"), link: ("#365978", "#91C8F2"),
        success: ("#216E3A", "#77D99B"), warning: ("#825300", "#FFD166"),
        error: ("#B42318", "#FF8580"), capsuleSurface: ("#FFFFFF", "#1E2224"),
        capsuleText: ("#17191C", "#F3F5F4"), capsuleBorder: ("#767C82", "#899093"),
        isDark: isDark))
    }
  }

  private init(
    family: FleckColorTheme,
    appearance: FleckThemeAppearance,
    colors: [FleckThemeColor: String]
  ) {
    self.family = family
    self.appearance = appearance
    self.colors = colors
  }

  private static func colors(
    window: (String, String), sidebar: (String, String),
    editorOpaque: (String, String), card: (String, String),
    raised: (String, String), border: (String, String),
    textPrimary: (String, String), textSecondary: (String, String),
    caption: (String, String), selectionFill: (String, String),
    selectionText: (String, String), accent: (String, String),
    accentText: (String, String), hoverFill: (String, String),
    focusRing: (String, String), link: (String, String),
    success: (String, String), warning: (String, String), error: (String, String),
    capsuleSurface: (String, String), capsuleText: (String, String),
    capsuleBorder: (String, String), isDark: Bool
  ) -> [FleckThemeColor: String] {
    [
      .window: isDark ? window.1 : window.0,
      .sidebar: isDark ? sidebar.1 : sidebar.0,
      .editorOpaque: isDark ? editorOpaque.1 : editorOpaque.0,
      .card: isDark ? card.1 : card.0,
      .raised: isDark ? raised.1 : raised.0,
      .border: isDark ? border.1 : border.0,
      .textPrimary: isDark ? textPrimary.1 : textPrimary.0,
      .textSecondary: isDark ? textSecondary.1 : textSecondary.0,
      .caption: isDark ? caption.1 : caption.0,
      .selectionFill: isDark ? selectionFill.1 : selectionFill.0,
      .selectionText: isDark ? selectionText.1 : selectionText.0,
      .accent: isDark ? accent.1 : accent.0,
      .accentText: isDark ? accentText.1 : accentText.0,
      .hoverFill: isDark ? hoverFill.1 : hoverFill.0,
      .focusRing: isDark ? focusRing.1 : focusRing.0,
      .link: isDark ? link.1 : link.0,
      .success: isDark ? success.1 : success.0,
      .warning: isDark ? warning.1 : warning.0,
      .error: isDark ? error.1 : error.0,
      .capsuleSurface: isDark ? capsuleSurface.1 : capsuleSurface.0,
      .capsuleText: isDark ? capsuleText.1 : capsuleText.0,
      .capsuleBorder: isDark ? capsuleBorder.1 : capsuleBorder.0,
    ]
  }
}
