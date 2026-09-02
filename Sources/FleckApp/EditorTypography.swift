#if os(macOS)
  import AppKit

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

    static func titleNSFont(family: String) -> NSFont {
      let size: CGFloat = 20
      guard family != ".AppleSystemUIFont" else {
        return .systemFont(ofSize: size, weight: .semibold)
      }
      let base = bodyFont(family: family, size: size)
      guard base.familyName == family else {
        return .systemFont(ofSize: size, weight: .semibold)
      }
      let descriptor = NSFontDescriptor(
        fontAttributes: [
          .family: family,
          .traits: [
            NSFontDescriptor.TraitKey.weight: NSFont.Weight.semibold.rawValue
          ],
        ]
      )
      return NSFont(descriptor: descriptor, size: size)
        ?? .systemFont(ofSize: size, weight: .semibold)
    }
  }
#endif
