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

    private struct Preset {
      let style: EditorTextStyle
      let font: NSFont
      let metrics: EditorTypography.PresetParagraphMetrics
    }

    private struct Candidate {
      let target: Preset
      let font: NSFont
      let metrics: EditorTypography.PresetParagraphMetrics

      func matches(runFont: NSFont, paragraph: NSParagraphStyle) -> Bool {
        metrics.matches(paragraph, tolerance: EditorTypographyMigration.tolerance)
          && EditorTypography.fontsVisuallyMatch(runFont, font)
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

    @discardableResult
    static func migrate(
      _ storage: NSTextStorage,
      family: String,
      size: CGFloat,
      isListParagraph: (NSRange) -> Bool
    ) -> Int {
      guard storage.length > 0 else { return 0 }
      let tabInterval = EditorTypography.indentWidth(
        font: EditorTypography.bodyFont(family: family, size: size)
      )
      let candidates = EditorTextStyle.allCases.flatMap { style -> [Candidate] in
        let target = Preset(
          style: style,
          font: EditorTypography.presetFont(for: style, family: family, size: size),
          metrics: EditorTypography.presetParagraphMetrics(for: style, size: size)
        )
        let legacy = legacySignatures.filter { $0.style == style }.map { signature in
          Candidate(
            target: target,
            font: EditorTypography.presetFont(
              for: style,
              family: family,
              size: size,
              scale: signature.scale
            ),
            metrics: EditorTypography.PresetParagraphMetrics(
              lineHeight: EditorTypography.lineHeight(fontSize: size * signature.scale),
              spacingBefore: signature.spacingBefore,
              spacingAfter: signature.spacingAfter
            )
          )
        }
        return legacy + [Candidate(target: target, font: target.font, metrics: target.metrics)]
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
          let preset = matchingPreset(
            in: storage,
            paragraphRange: paragraphRange,
            candidates: candidates
          )
        else { continue }
        if restyle(
          storage,
          paragraphRange: paragraphRange,
          preset: preset,
          tabInterval: tabInterval
        ) {
          migrated += 1
        }
      }
      storage.endEditing()
      return migrated
    }

    private static func matchingPreset(
      in storage: NSTextStorage,
      paragraphRange: NSRange,
      candidates: [Candidate]
    ) -> Preset? {
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
      var match: Preset?
      for candidate in candidates where candidate.matches(runFont: font, paragraph: paragraph) {
        if let match, match.style != candidate.target.style { return nil }
        match = candidate.target
      }
      return match
    }

    private static func restyle(
      _ storage: NSTextStorage,
      paragraphRange: NSRange,
      preset: Preset,
      tabInterval: CGFloat
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
      let metricsMatch = existing.map {
        preset.metrics.matches($0, tolerance: tolerance)
          && abs($0.defaultTabInterval - tabInterval) < tolerance
      } ?? false
      let fontMatches = existingFont.map {
        EditorTypography.fontsVisuallyMatch($0, preset.font)
      } ?? false
      guard !(metricsMatch && fontMatches) else { return false }
      if !fontMatches {
        storage.addAttribute(.font, value: preset.font, range: paragraphRange)
      }
      let paragraph =
        ((existing?.mutableCopy()) as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
      preset.metrics.apply(to: paragraph)
      paragraph.defaultTabInterval = tabInterval
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
