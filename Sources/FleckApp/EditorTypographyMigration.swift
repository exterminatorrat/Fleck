#if os(macOS)
  import AppKit

  /// Moves paragraphs that still carry one of the app's own untouched earlier
  /// typography presets onto the current preset table when a note is opened.
  ///
  /// Only exact preset signatures match. A paragraph with custom spacing, line
  /// height, indent, tab stops, a real text list, or an alignment other than the
  /// left-to-right default is left exactly as persisted, and a paragraph whose
  /// font and spacing disagree is treated as ambiguous and left alone. Anything
  /// the preset does not own — line spacing, writing direction, blocks — is
  /// carried over untouched. The migration rewrites text storage only, so
  /// nothing reaches disk until the note is edited, and a second pass over
  /// migrated content changes nothing.
  ///
  /// Signatures are compared against the current editor font and size, so a note
  /// last edited with a different editor font is left as it is.
  enum EditorTypographyMigration {
    struct Signature: Equatable {
      let style: EditorTextStyle
      let scale: CGFloat
      let spacingBefore: CGFloat
      let spacingAfter: CGFloat
    }

    private struct Candidate {
      let style: EditorTextStyle
      let lineHeight: CGFloat
      let spacingBefore: CGFloat
      let spacingAfter: CGFloat
      let font: NSFont

      func matches(runFont: NSFont, paragraph: NSParagraphStyle) -> Bool {
        guard
          abs(paragraph.paragraphSpacingBefore - spacingBefore)
            < EditorTypographyMigration.tolerance,
          abs(paragraph.paragraphSpacing - spacingAfter)
            < EditorTypographyMigration.tolerance,
          abs(paragraph.minimumLineHeight - lineHeight)
            < EditorTypographyMigration.tolerance,
          abs(paragraph.maximumLineHeight - lineHeight)
            < EditorTypographyMigration.tolerance,
          abs(paragraph.lineHeightMultiple) < EditorTypographyMigration.tolerance
        else { return false }
        return EditorTypography.fontsVisuallyMatch(runFont, font)
      }
    }

    static let tolerance: CGFloat = 0.05

    static let legacySignatures: [Signature] = [
      Signature(style: .normal, scale: 1, spacingBefore: 0, spacingAfter: 0),
      Signature(style: .heading1, scale: 1.75, spacingBefore: 12, spacingAfter: 8),
      Signature(style: .heading2, scale: 1.5, spacingBefore: 10, spacingAfter: 6),
      Signature(style: .heading3, scale: 1.25, spacingBefore: 8, spacingAfter: 4),
      Signature(style: .quote, scale: 1, spacingBefore: 6, spacingAfter: 6),
      Signature(style: .code, scale: 1, spacingBefore: 4, spacingAfter: 4),
    ]

    static var currentSignatures: [Signature] {
      EditorTextStyle.allCases.map { style in
        let spacing = EditorTypography.presetSpacing(for: style)
        return Signature(
          style: style,
          scale: EditorTypography.presetScale(for: style),
          spacingBefore: spacing.before,
          spacingAfter: spacing.after
        )
      }
    }

    @discardableResult
    static func migrate(
      _ storage: NSTextStorage,
      family: String,
      size: CGFloat,
      isListParagraph: (NSRange) -> Bool
    ) -> Int {
      let candidates = (legacySignatures + currentSignatures).map { signature in
        Candidate(
          style: signature.style,
          lineHeight: EditorTypography.lineHeight(fontSize: size * signature.scale),
          spacingBefore: signature.spacingBefore,
          spacingAfter: signature.spacingAfter,
          font: EditorTypography.presetFont(
            for: signature.style,
            family: family,
            size: size,
            scale: signature.scale
          )
        )
      }
      let text = storage.string as NSString
      var migrated = 0
      var location = 0
      storage.beginEditing()
      while location < text.length {
        let paragraphRange = text.paragraphRange(
          for: NSRange(location: location, length: 0)
        )
        location = max(NSMaxRange(paragraphRange), location + 1)
        guard paragraphRange.length > 0, !isListParagraph(paragraphRange) else { continue }
        guard !text.substring(with: paragraphRange).contains("\t") else { continue }
        guard
          let style = presetStyle(
            in: storage,
            paragraphRange: paragraphRange,
            candidates: candidates
          )
        else { continue }
        if restyle(
          storage,
          paragraphRange: paragraphRange,
          style: style,
          family: family,
          size: size
        ) {
          migrated += 1
        }
      }
      storage.endEditing()
      return migrated
    }

    private static func presetStyle(
      in storage: NSTextStorage,
      paragraphRange: NSRange,
      candidates: [Candidate]
    ) -> EditorTextStyle? {
      var fontRange = NSRange()
      var styleRange = NSRange()
      guard
        let font = storage.attribute(
          .font,
          at: paragraphRange.location,
          effectiveRange: &fontRange
        ) as? NSFont,
        let paragraph = storage.attribute(
          .paragraphStyle,
          at: paragraphRange.location,
          effectiveRange: &styleRange
        ) as? NSParagraphStyle,
        covers(fontRange, paragraphRange),
        covers(styleRange, paragraphRange),
        hasDefaultGeometry(paragraph)
      else { return nil }
      let matches = candidates.filter {
        $0.matches(runFont: font, paragraph: paragraph)
      }
      guard let first = matches.first,
        matches.allSatisfy({ $0.style == first.style })
      else { return nil }
      return first.style
    }

    private static func restyle(
      _ storage: NSTextStorage,
      paragraphRange: NSRange,
      style: EditorTextStyle,
      family: String,
      size: CGFloat
    ) -> Bool {
      let existing = storage.attribute(
        .paragraphStyle,
        at: paragraphRange.location,
        effectiveRange: nil
      ) as? NSParagraphStyle
      let existingFont = storage.attribute(
        .font,
        at: paragraphRange.location,
        effectiveRange: nil
      ) as? NSFont
      let desiredFont = EditorTypography.presetFont(for: style, family: family, size: size)
      let desiredSpacing = EditorTypography.presetSpacing(for: style)
      let desiredLineHeight = EditorTypography.lineHeight(
        fontSize: size * EditorTypography.presetScale(for: style)
      )
      let desiredTabInterval = EditorTypography.indentWidth(
        font: EditorTypography.bodyFont(family: family, size: size)
      )
      let metricsMatch = existing.map {
        abs($0.paragraphSpacingBefore - desiredSpacing.before) < tolerance
          && abs($0.paragraphSpacing - desiredSpacing.after) < tolerance
          && abs($0.minimumLineHeight - desiredLineHeight) < tolerance
          && abs($0.maximumLineHeight - desiredLineHeight) < tolerance
          && abs($0.lineHeightMultiple) < tolerance
          && abs($0.defaultTabInterval - desiredTabInterval) < tolerance
      } ?? false
      let fontMatches = existingFont.map {
        EditorTypography.fontsVisuallyMatch($0, desiredFont)
      } ?? false
      guard !(metricsMatch && fontMatches) else { return false }
      if !fontMatches {
        storage.addAttribute(.font, value: desiredFont, range: paragraphRange)
      }
      let paragraph =
        ((existing?.mutableCopy()) as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
      EditorTypography.applyPresetFields(
        paragraph,
        for: style,
        family: family,
        size: size
      )
      storage.addAttribute(.paragraphStyle, value: paragraph, range: paragraphRange)
      return true
    }

    private static func covers(_ range: NSRange, _ paragraphRange: NSRange) -> Bool {
      range.location <= paragraphRange.location
        && NSMaxRange(range) >= NSMaxRange(paragraphRange)
    }

    private static func hasDefaultGeometry(_ paragraph: NSParagraphStyle) -> Bool {
      (paragraph.alignment == .natural || paragraph.alignment == .left)
        && abs(paragraph.headIndent) < 0.01
        && abs(paragraph.firstLineHeadIndent) < 0.01
        && abs(paragraph.tailIndent) < 0.01
        && EditorTypography.hasOnlyDefaultTabStops(paragraph)
        && paragraph.textLists.isEmpty
    }
  }

#endif
