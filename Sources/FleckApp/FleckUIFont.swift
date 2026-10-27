#if os(macOS)
  import AppKit
  import Combine
  import SwiftUI

  struct FleckUIFont: Equatable, Sendable {
    static let system = FleckUIFont(fontName: nil)
    let fontName: String?

    func font(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> Font {
      guard let fontName else {
        let font = Font.system(style)
        return weight.map { font.weight($0) } ?? font
      }
      let size: CGFloat
      switch style {
      case .largeTitle: size = 26
      case .title: size = 22
      case .title2: size = 17
      case .title3: size = 15
      case .headline, .body: size = 13
      case .subheadline, .callout: size = 12
      case .caption: size = 11
      case .footnote, .caption2: size = 10
      @unknown default: size = 13
      }
      let font = Font.custom(fontName, size: size, relativeTo: style)
      return font.weight(weight ?? (style == .headline ? .semibold : .regular))
    }

    func font(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
      guard let fontName else { return .system(size: size, weight: weight, design: design) }
      return .custom(fontName, fixedSize: size).weight(weight)
    }
  }

  @MainActor
  final class FleckUIFontCatalog: ObservableObject {
    private let installedFamilies: () -> [String]
    private let fontNameForFamily: (String) -> String?
    private var hasResolvedSelection = false
    private var selectedFamily: String?
    private var resolved = FleckUIFont.system

    init(installedFamilies: @escaping () -> [String], fontNameForFamily: @escaping (String) -> String?) {
      self.installedFamilies = installedFamilies
      self.fontNameForFamily = fontNameForFamily
    }

    convenience init() {
      self.init(
        installedFamilies: { NSFontManager.shared.availableFontFamilies },
        fontNameForFamily: {
          NSFontManager.shared.font(withFamily: $0, traits: [], weight: 5, size: 13)?.fontName
        }
      )
    }

    func typography(for family: String?) -> FleckUIFont {
      guard !hasResolvedSelection || selectedFamily != family else { return resolved }
      hasResolvedSelection = true
      selectedFamily = family
      if let family, installedFamilies().contains(family), let name = fontNameForFamily(family) {
        resolved = FleckUIFont(fontName: name)
      } else {
        resolved = .system
      }
      return resolved
    }
  }

  private struct FleckUIFontEnvironmentKey: EnvironmentKey {
    static let defaultValue = FleckUIFont.system
  }

  extension EnvironmentValues {
    var fleckUIFont: FleckUIFont {
      get { self[FleckUIFontEnvironmentKey.self] }
      set { self[FleckUIFontEnvironmentKey.self] = newValue }
    }
  }

  @MainActor
  private struct FleckUIFontRoot: ViewModifier {
    @StateObject private var catalog = FleckUIFontCatalog()
    let family: String?

    func body(content: Content) -> some View {
      let typography = catalog.typography(for: family)
      content
        .environment(\.fleckUIFont, typography)
        .transformEnvironment(\.font) { font in
          guard typography.fontName != nil else { return }
          font = typography.font(.body)
        }
    }
  }

  private struct FleckUIFontStyle: ViewModifier {
    @Environment(\.fleckUIFont) private var typography
    let style: Font.TextStyle
    let weight: Font.Weight?

    func body(content: Content) -> some View {
      content.font(typography.font(style, weight: weight))
    }
  }

  extension View {
    func fleckUIFontFamily(_ family: String?) -> some View {
      modifier(FleckUIFontRoot(family: family))
    }

    func fleckUIFont(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> some View {
      modifier(FleckUIFontStyle(style: style, weight: weight))
    }
  }
#endif
