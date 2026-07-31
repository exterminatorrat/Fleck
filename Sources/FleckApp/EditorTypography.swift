#if os(macOS)
  import AppKit
  import SwiftUI

  enum EditorTypography {
    static let defaultLineHeight: CGFloat = 27

    static func bodyFont(
      family: String,
      size: CGFloat,
      fontProvider: (String, CGFloat) -> NSFont? = { family, size in
        NSFont(name: family, size: size)
      }
    ) -> NSFont {
      guard family != ".AppleSystemUIFont" else {
        return .systemFont(ofSize: size)
      }
      guard let font = fontProvider(family, size), font.familyName == family else {
        return .systemFont(ofSize: size)
      }
      return font
    }

    static func defaultParagraphStyle(fontSize: CGFloat) -> NSParagraphStyle {
      let style = NSMutableParagraphStyle()
      let lineHeight = fontSize / 17 * defaultLineHeight
      style.minimumLineHeight = lineHeight
      style.maximumLineHeight = lineHeight
      return style
    }

    static func defaultAttributes(
      family: String,
      size: CGFloat
    ) -> [NSAttributedString.Key: Any] {
      [
        .font: bodyFont(family: family, size: size),
        .paragraphStyle: defaultParagraphStyle(fontSize: size),
      ]
    }

    static func titleFont(family: String) -> Font {
      family == ".AppleSystemUIFont"
        ? .title3.weight(.semibold)
        : .custom(family, size: 20).weight(.semibold)
    }
  }
#endif
