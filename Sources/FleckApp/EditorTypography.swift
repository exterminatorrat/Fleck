#if os(macOS)
  import AppKit

  enum EditorTypography {
    static let defaultLineHeight: CGFloat = 27
    static let bodyParagraphSpacing: CGFloat = 8
    static let maxIndentPoints: CGFloat = 240
    static let indentSpaces = 4
    static let systemFamily = ".AppleSystemUIFont"

    struct HeadingMetrics: Equatable {
      let scale: CGFloat
      let spacingBefore: CGFloat
      let spacingAfter: CGFloat
    }

    static let headingMetrics: [HeadingMetrics] = [
      HeadingMetrics(scale: 1.6, spacingBefore: 16, spacingAfter: 8),
      HeadingMetrics(scale: 1.35, spacingBefore: 12, spacingAfter: 6),
      HeadingMetrics(scale: 1.15, spacingBefore: 8, spacingAfter: 4),
    ]

    struct PresetSpacing: Equatable {
      let before: CGFloat
      let after: CGFloat
    }

    static let quoteParagraphSpacing: CGFloat = 8
    static let codeParagraphSpacing: CGFloat = 4

    static func presetScale(for style: EditorTextStyle) -> CGFloat {
      switch style {
      case .heading1, .heading2, .heading3:
        headingMetrics(forStyleIndex: style.headingLevel - 1).scale
      case .normal, .quote, .code:
        1
      }
    }

    static func presetSpacing(for style: EditorTextStyle) -> PresetSpacing {
      switch style {
      case .normal:
        return PresetSpacing(before: 0, after: bodyParagraphSpacing)
      case .heading1, .heading2, .heading3:
        let metrics = headingMetrics(forStyleIndex: style.headingLevel - 1)
        return PresetSpacing(before: metrics.spacingBefore, after: metrics.spacingAfter)
      case .quote:
        return PresetSpacing(before: quoteParagraphSpacing, after: quoteParagraphSpacing)
      case .code:
        return PresetSpacing(before: codeParagraphSpacing, after: codeParagraphSpacing)
      }
    }

    static func presetFont(
      for style: EditorTextStyle,
      family: String,
      size: CGFloat,
      scale: CGFloat? = nil
    ) -> NSFont {
      let fontSize = size * (scale ?? presetScale(for: style))
      if style == .code { return .monospacedSystemFont(ofSize: fontSize, weight: .regular) }
      let manager = NSFontManager.shared
      var font = manager.convert(
        bodyFont(family: family, size: fontSize),
        toNotHaveTrait: [.boldFontMask, .italicFontMask]
      )
      switch style {
      case .heading1, .heading2, .heading3:
        font = manager.convert(font, toHaveTrait: .boldFontMask)
      case .quote:
        font = manager.convert(font, toHaveTrait: .italicFontMask)
      case .normal, .code:
        break
      }
      return font
    }

    static func applyPresetFields(
      _ paragraph: NSMutableParagraphStyle,
      for style: EditorTextStyle,
      family: String,
      size: CGFloat
    ) {
      let spacing = presetSpacing(for: style)
      let presetLineHeight = lineHeight(fontSize: size * presetScale(for: style))
      paragraph.minimumLineHeight = presetLineHeight
      paragraph.maximumLineHeight = presetLineHeight
      paragraph.lineHeightMultiple = 0
      paragraph.paragraphSpacingBefore = spacing.before
      paragraph.paragraphSpacing = spacing.after
      paragraph.defaultTabInterval = indentWidth(font: bodyFont(family: family, size: size))
    }

    static func presetParagraphStyle(
      for style: EditorTextStyle,
      family: String,
      size: CGFloat
    ) -> NSParagraphStyle {
      let paragraph = NSMutableParagraphStyle()
      applyPresetFields(paragraph, for: style, family: family, size: size)
      return paragraph
    }

    static func fontsVisuallyMatch(_ lhs: NSFont, _ rhs: NSFont) -> Bool {
      fontFamiliesVisuallyMatch(lhs.familyName, rhs.familyName)
        && abs(lhs.pointSize - rhs.pointSize) < 0.05
        && NSFontManager.shared.traits(of: lhs).intersection([.boldFontMask, .italicFontMask])
          == NSFontManager.shared.traits(of: rhs).intersection([.boldFontMask, .italicFontMask])
    }

    static func fontFamiliesVisuallyMatch(_ lhs: String?, _ rhs: String?) -> Bool {
      if lhs == rhs { return true }
      return Set([lhs, rhs].compactMap { $0 }) == Set([".AppleSystemUIFont", "Helvetica Neue"])
    }

    /// Reports whether a paragraph still uses the text system's own tab stops.
    /// AppKit materialises the default stops on read, so an untouched paragraph
    /// answers with the same table as a fresh style rather than an empty array.
    static func hasOnlyDefaultTabStops(_ paragraph: NSParagraphStyle) -> Bool {
      let stops = paragraph.tabStops ?? []
      guard !stops.isEmpty else { return true }
      let defaults = NSMutableParagraphStyle().tabStops ?? []
      return stops.count == defaults.count
        && zip(stops, defaults).allSatisfy { $0.isEqual($1) }
    }

    static func indentWidth(font: NSFont?) -> CGFloat {
      let font = font ?? .systemFont(ofSize: 17)
      let spaceWidth = (" " as NSString).size(withAttributes: [.font: font]).width
      guard spaceWidth.isFinite, spaceWidth > 0 else {
        return CGFloat(indentSpaces) * 0.25 * font.pointSize
      }
      return spaceWidth * CGFloat(indentSpaces)
    }

    static func lineHeight(fontSize: CGFloat) -> CGFloat {
      fontSize / 17 * defaultLineHeight
    }

    static func headingMetrics(forStyleIndex index: Int) -> HeadingMetrics {
      headingMetrics[min(max(index, 0), headingMetrics.count - 1)]
    }

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

    /// Presets for the built-in system family. Production code passes an
    /// explicit family so a note never mixes two grids.
    static func systemDefaultParagraphStyle(fontSize: CGFloat) -> NSParagraphStyle {
      defaultParagraphStyle(family: systemFamily, fontSize: fontSize)
    }

    static func defaultParagraphStyle(family: String, fontSize: CGFloat) -> NSParagraphStyle {
      let style = NSMutableParagraphStyle()
      let lineHeight = lineHeight(fontSize: fontSize)
      style.minimumLineHeight = lineHeight
      style.maximumLineHeight = lineHeight
      style.defaultTabInterval = indentWidth(font: bodyFont(family: family, size: fontSize))
      return style
    }

    static func bodyParagraphStyle(family: String, fontSize: CGFloat) -> NSParagraphStyle {
      let style = (defaultParagraphStyle(family: family, fontSize: fontSize).mutableCopy()
        as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
      style.paragraphSpacing = bodyParagraphSpacing
      return style
    }

    static func defaultAttributes(
      family: String,
      size: CGFloat
    ) -> [NSAttributedString.Key: Any] {
      [
        .font: bodyFont(family: family, size: size),
        .paragraphStyle: bodyParagraphStyle(family: family, fontSize: size),
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
