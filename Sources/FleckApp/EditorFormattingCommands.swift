#if os(macOS)
  import AppKit
  import FleckCore

  enum EditorTextStyle: String, CaseIterable, Hashable {
    case normal = "Normal"
    case heading1 = "Heading 1"
    case heading2 = "Heading 2"
    case heading3 = "Heading 3"
    case quote = "Quote"
    case code = "Code"
  }

  enum EditorLineSpacing: String, CaseIterable, Hashable {
    case single = "Single"
    case oneAndHalf = "1.5 Lines"
    case double = "Double"

    var multiple: CGFloat {
      switch self {
      case .single: 1
      case .oneAndHalf: 1.5
      case .double: 2
      }
    }
  }

  enum EditorBaseline: String, CaseIterable, Hashable {
    case normal = "Baseline"
    case superscript = "Superscript"
    case subscriptText = "Subscript"

    var value: Int {
      switch self {
      case .normal: 0
      case .superscript: 1
      case .subscriptText: -1
      }
    }
  }

  enum EditorTextCase: String, CaseIterable, Hashable {
    case sentence = "Sentence case"
    case lowercase = "lowercase"
    case uppercase = "UPPERCASE"
  }

  enum EditorFindAction: Equatable {
    case showFind
    case showReplace
    case nextMatch
    case previousMatch

    var nativeAction: NSTextFinder.Action {
      switch self {
      case .showFind: .showFindInterface
      case .showReplace: .showReplaceInterface
      case .nextMatch: .nextMatch
      case .previousMatch: .previousMatch
      }
    }
  }

  private enum ParagraphTarget {
    case typing
    case range(NSRange)
  }

  @MainActor
  extension EditorCommands {
    private static var visualAttributeKeys: [NSAttributedString.Key] {
      [
        .font, .foregroundColor, .backgroundColor,
        .underlineStyle, .underlineColor,
        .strikethroughStyle, .strikethroughColor,
        .superscript, .baselineOffset, .kern, .ligature,
        .obliqueness, .expansion, .shadow, .strokeColor, .strokeWidth,
      ]
    }

    var canPerformBodyCommand: Bool {
      guard let textView else { return false }
      return textView.isEditable && textView.isSelectable
        && !areBodyCommandsBlocked && !isBodyCommandContextBlocked
        && !isTitleEditing && !isFocusedDictationActive
    }

    func configureBodyDefaults(family: String, size: CGFloat) {
      bodyFontFamily = family
      bodyFontSize = size
    }

    @discardableResult
    func applyTextStyle(_ style: EditorTextStyle) -> Bool {
      guard canPerformBodyCommand, let textView,
        let target = paragraphTarget(in: textView)
      else { return false }
      let font = font(for: style)

      switch target {
      case .typing:
        textView.typingAttributes[.font] = font
        textView.typingAttributes[.paragraphStyle] = styledParagraph(
          textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle,
          style: style
        )
        refreshFormattingState()
        return true
      case .range(let range):
        return mutateAttributedRange(range, in: textView) { replacement in
          replacement.addAttribute(
            .font,
            value: font,
            range: NSRange(location: 0, length: replacement.length)
          )
          enumerateParagraphs(in: replacement.string) { paragraphRange in
            let existing = replacement.attribute(
              .paragraphStyle,
              at: min(paragraphRange.location, max(0, replacement.length - 1)),
              effectiveRange: nil
            ) as? NSParagraphStyle
            replacement.addAttribute(
              .paragraphStyle,
              value: styledParagraph(existing, style: style),
              range: paragraphRange
            )
          }
        }
      }
    }

    @discardableResult
    func applyAlignment(_ alignment: NSTextAlignment) -> Bool {
      mutateParagraphs { $0.alignment = alignment }
    }

    @discardableResult
    func applyLineSpacing(_ spacing: EditorLineSpacing) -> Bool {
      mutateParagraphs {
        $0.minimumLineHeight = 0
        $0.maximumLineHeight = 0
        $0.lineHeightMultiple = spacing.multiple
      }
    }

    @discardableResult
    func applyParagraphSpacingBefore(_ points: CGFloat) -> Bool {
      guard points.isFinite else { return false }
      return mutateParagraphs { $0.paragraphSpacingBefore = min(max(points, 0), 36) }
    }

    @discardableResult
    func applyParagraphSpacingAfter(_ points: CGFloat) -> Bool {
      guard points.isFinite else { return false }
      return mutateParagraphs { $0.paragraphSpacing = min(max(points, 0), 36) }
    }

    @discardableResult
    func increaseIndent() -> Bool { adjustIndent(removing: false) }

    @discardableResult
    func decreaseIndent() -> Bool { adjustIndent(removing: true) }

    @discardableResult
    private func adjustIndent(removing: Bool) -> Bool {
      guard canPerformBodyCommand, let textView else { return false }
      if let listTextView = textView as? ListAwareTextView,
        listTextView.selectionContainsListParagraph
      {
        return listTextView.adjustSelectedParagraphIndent(removing: removing)
      }
      return mutateParagraphs {
        let next = removing ? $0.headIndent - 24 : $0.headIndent + 24
        $0.headIndent = min(max(next, 0), 240)
        $0.firstLineHeadIndent = min(max(
          removing ? $0.firstLineHeadIndent - 24 : $0.firstLineHeadIndent + 24,
          0
        ), 240)
      }
    }

    @discardableResult
    func clearTextFormatting() -> Bool {
      guard canPerformBodyCommand, let textView else { return false }
      let defaultFont = EditorTypography.bodyFont(family: bodyFontFamily, size: bodyFontSize)
      let range = textView.selectedRange()
      if range.length == 0 {
        for key in Self.visualAttributeKeys { textView.typingAttributes.removeValue(forKey: key) }
        textView.typingAttributes[.font] = defaultFont
        refreshFormattingState()
        return true
      }
      return mutateAttributedRange(range, in: textView) { replacement in
        let fullRange = NSRange(location: 0, length: replacement.length)
        for key in Self.visualAttributeKeys { replacement.removeAttribute(key, range: fullRange) }
        replacement.addAttribute(.font, value: defaultFont, range: fullRange)
      }
    }

    @discardableResult
    func copyFormatting() -> Bool {
      guard canPerformBodyCommand, let textView else { return false }
      let selection = textView.selectedRange()
      let source: [NSAttributedString.Key: Any]
      if selection.length > 0, let storage = textView.textStorage,
        selection.location < storage.length
      {
        source = storage.attributes(at: selection.location, effectiveRange: nil)
      } else {
        source = textView.typingAttributes
      }
      copiedFormatting = source.filter { Self.visualAttributeKeys.contains($0.key) }
      canPasteFormatting = true
      return true
    }

    @discardableResult
    func pasteFormatting() -> Bool {
      guard canPerformBodyCommand, let textView, let copiedFormatting else { return false }
      let range = textView.selectedRange()
      if range.length == 0 {
        for key in Self.visualAttributeKeys { textView.typingAttributes.removeValue(forKey: key) }
        textView.typingAttributes.merge(copiedFormatting) { _, copied in copied }
        refreshFormattingState()
        return true
      }
      return mutateAttributedRange(range, in: textView) { replacement in
        let fullRange = NSRange(location: 0, length: replacement.length)
        for key in Self.visualAttributeKeys { replacement.removeAttribute(key, range: fullRange) }
        replacement.addAttributes(copiedFormatting, range: fullRange)
      }
    }

    func cancelCopiedFormatting() {
      copiedFormatting = nil
      canPasteFormatting = false
    }

    @discardableResult
    func setBaseline(_ baseline: EditorBaseline) -> Bool {
      guard canPerformBodyCommand, let textView else { return false }
      let range = textView.selectedRange()
      if range.length == 0 {
        textView.typingAttributes[.superscript] = baseline.value
        refreshFormattingState()
        return true
      }
      return mutateAttributedRange(range, in: textView) { replacement in
        replacement.addAttribute(
          .superscript,
          value: baseline.value,
          range: NSRange(location: 0, length: replacement.length)
        )
      }
    }

    @discardableResult
    func transformCase(_ textCase: EditorTextCase) -> Bool {
      guard canPerformBodyCommand, let textView, let storage = textView.textStorage else {
        return false
      }
      let selection = textView.selectedRange()
      guard selection.length > 0, NSMaxRange(selection) <= storage.length else { return false }
      let composedRange = (textView.string as NSString).rangeOfComposedCharacterSequences(
        for: selection
      )
      let source = storage.attributedSubstring(from: composedRange)
      let replacement = EditorAttributedCaseTransformer.transform(
        source,
        mode: textCase,
        protectedRanges: protectedCaseRanges(in: textView.string, selection: composedRange)
          .map { NSRange(location: $0.location - composedRange.location, length: $0.length) }
      )
      guard replacement != source else { return false }
      return replaceAttributedRange(
        composedRange,
        in: textView,
        with: replacement,
        selection: NSRange(location: composedRange.location, length: replacement.length)
      )
    }

    @discardableResult
    func performFind(_ action: EditorFindAction) -> Bool {
      guard canPerformBodyCommand, let textView, textView.usesFindBar else { return false }
      let sender = NSMenuItem()
      sender.tag = action.nativeAction.rawValue
      textView.performTextFinderAction(sender)
      return true
    }

    static func containsAttachment(in range: NSRange, storage: NSAttributedString) -> Bool {
      guard range.length > 0, range.location >= 0, NSMaxRange(range) <= storage.length else {
        return false
      }
      var found = false
      storage.enumerateAttribute(.attachment, in: range) { value, _, stop in
        guard value != nil else { return }
        found = true
        stop.pointee = true
      }
      return found
    }

    @discardableResult
    func applyWebLink(
      url: URL,
      range: NSRange,
      displayText: String?,
      expectedTextView: NSTextView,
      expectedStorage: NSTextStorage
    ) -> Bool {
      guard canPerformBodyCommand, textView === expectedTextView,
        expectedTextView.textStorage === expectedStorage,
        range.location >= 0, NSMaxRange(range) <= expectedStorage.length,
        !Self.containsAttachment(in: range, storage: expectedStorage)
      else { return false }

      if range.length == 0 {
        let display = displayText?.isEmpty == false ? displayText! : url.absoluteString
        var attributes = expectedTextView.typingAttributes
        attributes.removeValue(forKey: .attachment)
        attributes[.link] = url
        let replacement = NSAttributedString(
          string: display,
          attributes: attributes
        )
        return replaceAttributedRange(
          range,
          in: expectedTextView,
          with: replacement,
          selection: NSRange(location: range.location, length: replacement.length)
        )
      }

      if let displayText, !displayText.isEmpty,
        displayText != expectedStorage.attributedSubstring(from: range).string
      {
        var attributes = expectedStorage.attributes(at: range.location, effectiveRange: nil)
        attributes[.link] = url
        return replaceAttributedRange(
          range,
          in: expectedTextView,
          with: NSAttributedString(string: displayText, attributes: attributes),
          selection: NSRange(location: range.location, length: displayText.utf16.count)
        )
      }
      return mutateAttributedRange(range, in: expectedTextView) { replacement in
        replacement.addAttribute(
          .link,
          value: url,
          range: NSRange(location: 0, length: replacement.length)
        )
      }
    }

    @discardableResult
    func removeWebLink(
      range: NSRange,
      expectedTextView: NSTextView,
      expectedStorage: NSTextStorage
    ) -> Bool {
      guard canPerformBodyCommand, textView === expectedTextView,
        expectedTextView.textStorage === expectedStorage, range.length > 0,
        range.location >= 0, NSMaxRange(range) <= expectedStorage.length,
        !Self.containsAttachment(in: range, storage: expectedStorage)
      else { return false }
      return mutateAttributedRange(range, in: expectedTextView) { replacement in
        replacement.removeAttribute(
          .link,
          range: NSRange(location: 0, length: replacement.length)
        )
      }
    }

    func refreshExpandedFormattingState() {
      guard let textView else {
        currentTextStyle = nil
        isTextStyleMixed = false
        currentAlignment = nil
        isAlignmentMixed = false
        currentLineSpacing = nil
        currentParagraphSpacingBefore = nil
        currentParagraphSpacingAfter = nil
        currentBaseline = nil
        return
      }
      guard let target = paragraphTarget(in: textView) else {
        currentTextStyle = nil
        currentAlignment = nil
        isTextStyleMixed = false
        isAlignmentMixed = false
        currentLineSpacing = nil
        currentParagraphSpacingBefore = nil
        currentParagraphSpacingAfter = nil
        currentBaseline = nil
        return
      }
      let styles: [NSParagraphStyle]
      switch target {
      case .typing:
        styles = [(textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle) ?? .default]
      case .range(let range):
        guard let storage = textView.textStorage, storage.length > 0 else {
          currentTextStyle = nil
          currentAlignment = .left
          isAlignmentMixed = false
          return
        }
        var values: [NSParagraphStyle] = []
        enumerateParagraphs(in: (textView.string as NSString).substring(with: range)) {
          paragraphRange in
          let location = min(range.location + paragraphRange.location, storage.length - 1)
          values.append(
            (storage.attribute(.paragraphStyle, at: location, effectiveRange: nil)
              as? NSParagraphStyle) ?? .default
          )
        }
        styles = values
      }
      let alignments = Set(styles.map(\.alignment))
      currentAlignment = alignments.count == 1 ? alignments.first : nil
      isAlignmentMixed = alignments.count > 1
      let resolvedLineSpacings = styles.map { style -> EditorLineSpacing? in
        let multiple = style.lineHeightMultiple == 0 ? 1 : style.lineHeightMultiple
        return EditorLineSpacing.allCases.first { abs($0.multiple - multiple) < 0.01 }
      }
      let lineSpacings = Set(resolvedLineSpacings.compactMap { $0 })
      currentLineSpacing = resolvedLineSpacings.allSatisfy { $0 != nil }
        && lineSpacings.count == 1 ? lineSpacings.first : nil
      let beforeValues = Set(styles.map(\.paragraphSpacingBefore))
      currentParagraphSpacingBefore = beforeValues.count == 1 ? beforeValues.first : nil
      let afterValues = Set(styles.map(\.paragraphSpacing))
      currentParagraphSpacingAfter = afterValues.count == 1 ? afterValues.first : nil
      currentBaseline = selectedBaseline(in: textView)
      currentTextStyle = matchingTextStyle(in: textView)
      isTextStyleMixed = currentTextStyle == nil
    }

    private func selectedBaseline(in textView: NSTextView) -> EditorBaseline? {
      let selection = textView.selectedRange()
      if selection.length == 0 {
        let value = textView.typingAttributes[.superscript] as? Int ?? 0
        return EditorBaseline.allCases.first { $0.value == value }
      }
      guard let storage = textView.textStorage else { return nil }
      var values = Set<Int>()
      storage.enumerateAttribute(.superscript, in: selection) { value, _, _ in
        values.insert(value as? Int ?? 0)
      }
      guard values.count == 1, let value = values.first else { return nil }
      return EditorBaseline.allCases.first { $0.value == value }
    }

    private func matchingTextStyle(in textView: NSTextView) -> EditorTextStyle? {
      guard let target = paragraphTarget(in: textView) else { return nil }
      switch target {
      case .typing:
        guard let actual = textView.typingAttributes[.font] as? NSFont else { return nil }
        let paragraph = textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        return EditorTextStyle.allCases.first {
          fontsVisuallyMatch(actual, font(for: $0))
            && paragraphsVisuallyMatch(paragraph, styledParagraph(paragraph, style: $0))
        }
      case .range(let range):
        guard let storage = textView.textStorage else { return nil }
        return EditorTextStyle.allCases.first { style in
          let expectedFont = font(for: style)
          var matches = true
          storage.enumerateAttribute(.font, in: range) { value, _, stop in
            guard let actual = value as? NSFont,
              fontsVisuallyMatch(actual, expectedFont)
            else {
              matches = false
              stop.pointee = true
              return
            }
          }
          guard matches else { return false }
          let substring = (textView.string as NSString).substring(with: range)
          enumerateParagraphs(in: substring) { paragraphRange in
            guard matches else { return }
            let location = min(range.location + paragraphRange.location, storage.length - 1)
            let actual = storage.attribute(.paragraphStyle, at: location, effectiveRange: nil)
              as? NSParagraphStyle
            matches = paragraphsVisuallyMatch(
              actual,
              styledParagraph(actual, style: style)
            )
          }
          return matches
        }
      }
    }

    private func fontsVisuallyMatch(_ lhs: NSFont, _ rhs: NSFont) -> Bool {
      fontFamiliesVisuallyMatch(lhs.familyName, rhs.familyName)
        && abs(lhs.pointSize - rhs.pointSize) < 0.01
        && NSFontManager.shared.traits(of: lhs).intersection([.boldFontMask, .italicFontMask])
          == NSFontManager.shared.traits(of: rhs).intersection([.boldFontMask, .italicFontMask])
    }

    private func fontFamiliesVisuallyMatch(_ lhs: String?, _ rhs: String?) -> Bool {
      if lhs == rhs { return true }
      return Set([lhs, rhs].compactMap { $0 }) == Set([".AppleSystemUIFont", "Helvetica Neue"])
    }

    private func paragraphsVisuallyMatch(
      _ lhs: NSParagraphStyle?,
      _ rhs: NSParagraphStyle
    ) -> Bool {
      let lhs = lhs ?? .default
      return abs(lhs.minimumLineHeight - rhs.minimumLineHeight) < 0.01
        && abs(lhs.maximumLineHeight - rhs.maximumLineHeight) < 0.01
        && abs(lhs.lineHeightMultiple - rhs.lineHeightMultiple) < 0.01
        && abs(lhs.paragraphSpacingBefore - rhs.paragraphSpacingBefore) < 0.01
        && abs(lhs.paragraphSpacing - rhs.paragraphSpacing) < 0.01
    }

    private func font(for style: EditorTextStyle) -> NSFont {
      let size: CGFloat
      switch style {
      case .normal, .quote, .code: size = bodyFontSize
      case .heading1: size = bodyFontSize * 1.75
      case .heading2: size = bodyFontSize * 1.5
      case .heading3: size = bodyFontSize * 1.25
      }
      if style == .code { return .monospacedSystemFont(ofSize: size, weight: .regular) }
      var font = EditorTypography.bodyFont(family: bodyFontFamily, size: size)
      let manager = NSFontManager.shared
      font = manager.convert(font, toNotHaveTrait: [.boldFontMask, .italicFontMask])
      if [.heading1, .heading2, .heading3].contains(style) {
        font = manager.convert(font, toHaveTrait: .boldFontMask)
      } else if style == .quote {
        font = manager.convert(font, toHaveTrait: .italicFontMask)
      }
      return font
    }

    private func styledParagraph(
      _ paragraph: NSParagraphStyle?,
      style: EditorTextStyle
    ) -> NSParagraphStyle {
      let result = ((paragraph ?? .default).mutableCopy() as? NSMutableParagraphStyle)
        ?? NSMutableParagraphStyle()
      let defaultLineHeight = font(for: style).pointSize / 17
        * EditorTypography.defaultLineHeight
      result.minimumLineHeight = defaultLineHeight
      result.maximumLineHeight = defaultLineHeight
      result.lineHeightMultiple = 0
      switch style {
      case .normal:
        result.paragraphSpacingBefore = 0
        result.paragraphSpacing = 0
      case .heading1:
        result.paragraphSpacingBefore = 12
        result.paragraphSpacing = 8
      case .heading2:
        result.paragraphSpacingBefore = 10
        result.paragraphSpacing = 6
      case .heading3:
        result.paragraphSpacingBefore = 8
        result.paragraphSpacing = 4
      case .quote:
        result.paragraphSpacingBefore = 6
        result.paragraphSpacing = 6
      case .code:
        result.paragraphSpacingBefore = 4
        result.paragraphSpacing = 4
      }
      return result
    }

    private func mutateParagraphs(
      _ mutation: (NSMutableParagraphStyle) -> Void
    ) -> Bool {
      guard canPerformBodyCommand, let textView,
        let target = paragraphTarget(in: textView)
      else { return false }
      switch target {
      case .typing:
        let style = ((textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle)
          ?? .default).mutableCopy() as! NSMutableParagraphStyle
        mutation(style)
        textView.typingAttributes[.paragraphStyle] = style
        refreshFormattingState()
        return true
      case .range(let range):
        return mutateAttributedRange(range, in: textView) { replacement in
          enumerateParagraphs(in: replacement.string) { paragraphRange in
            let location = min(paragraphRange.location, max(0, replacement.length - 1))
            let style = ((replacement.attribute(
              .paragraphStyle,
              at: location,
              effectiveRange: nil
            ) as? NSParagraphStyle) ?? .default).mutableCopy() as! NSMutableParagraphStyle
            mutation(style)
            replacement.addAttribute(.paragraphStyle, value: style, range: paragraphRange)
          }
        }
      }
    }

    private func paragraphTarget(in textView: NSTextView) -> ParagraphTarget? {
      guard let storage = textView.textStorage else { return nil }
      let selection = textView.selectedRange()
      guard selection.location != NSNotFound, selection.location >= 0,
        NSMaxRange(selection) <= storage.length
      else { return nil }
      let ns = textView.string as NSString
      if ns.length == 0 {
        return .typing
      }
      if selection.length == 0, selection.location == ns.length,
        ns.paragraphRange(for: selection).length == 0
      {
        return .typing
      }
      let start = min(selection.location, max(0, ns.length - 1))
      let end = selection.length > 0
        ? min(max(start, NSMaxRange(selection) - 1), max(0, ns.length - 1))
        : start
      return .range(NSUnionRange(
        ns.paragraphRange(for: NSRange(location: start, length: 0)),
        ns.paragraphRange(for: NSRange(location: end, length: 0))
      ))
    }

    private func enumerateParagraphs(in string: String, _ body: (NSRange) -> Void) {
      let ns = string as NSString
      guard ns.length > 0 else { return }
      var location = 0
      while location < ns.length {
        let range = ns.paragraphRange(for: NSRange(location: location, length: 0))
        body(range)
        let next = NSMaxRange(range)
        guard next > location else { break }
        location = next
      }
    }

    private func mutateAttributedRange(
      _ range: NSRange,
      in textView: NSTextView,
      mutation: (NSMutableAttributedString) -> Void
    ) -> Bool {
      guard let storage = textView.textStorage, range.location >= 0,
        range.length > 0, NSMaxRange(range) <= storage.length
      else { return false }
      let source = storage.attributedSubstring(from: range)
      let replacement = NSMutableAttributedString(attributedString: source)
      mutation(replacement)
      guard replacement != source else { return false }
      return replaceAttributedRange(
        range,
        in: textView,
        with: replacement,
        selection: textView.selectedRange()
      )
    }

    private func replaceAttributedRange(
      _ range: NSRange,
      in textView: NSTextView,
      with replacement: NSAttributedString,
      selection: NSRange
    ) -> Bool {
      guard let storage = textView.textStorage, textView.isEditable,
        range.location >= 0, NSMaxRange(range) <= storage.length
      else { return false }
      let undoManager = textView.undoManager
      undoManager?.disableUndoRegistration()
      guard textView.shouldChangeText(in: range, replacementString: replacement.string) else {
        undoManager?.enableUndoRegistration()
        return false
      }
      let original = storage.attributedSubstring(from: range)
      let originalSelection = textView.selectedRange()
      (textView as? ListAwareTextView)?.clearNoteLinkPresentation()
      storage.beginEditing()
      storage.replaceCharacters(in: range, with: replacement)
      storage.endEditing()
      undoManager?.enableUndoRegistration()
      textView.setSelectedRange(selection)
      registerReplacementUndo(
        textView: textView,
        storage: storage,
        range: NSRange(location: range.location, length: replacement.length),
        replacement: original,
        selection: originalSelection,
        inverseRange: NSRange(location: range.location, length: original.length),
        inverseReplacement: replacement,
        inverseSelection: selection
      )
      textView.didChangeText()
      refreshFormattingState()
      return true
    }

    private func registerReplacementUndo(
      textView: NSTextView,
      storage: NSTextStorage,
      range: NSRange,
      replacement: NSAttributedString,
      selection: NSRange,
      inverseRange: NSRange,
      inverseReplacement: NSAttributedString,
      inverseSelection: NSRange
    ) {
      textView.undoManager?.registerUndo(withTarget: textView) {
        [weak self, weak storage] textView in
        guard let self, let storage, textView.textStorage === storage,
          range.location >= 0, NSMaxRange(range) <= storage.length
        else { return }
        (textView as? ListAwareTextView)?.clearNoteLinkPresentation()
        textView.undoManager?.disableUndoRegistration()
        storage.beginEditing()
        storage.replaceCharacters(in: range, with: replacement)
        storage.endEditing()
        textView.undoManager?.enableUndoRegistration()
        textView.setSelectedRange(selection)
        self.registerReplacementUndo(
          textView: textView,
          storage: storage,
          range: inverseRange,
          replacement: inverseReplacement,
          selection: inverseSelection,
          inverseRange: range,
          inverseReplacement: replacement,
          inverseSelection: selection
        )
        textView.didChangeText()
        self.refreshFormattingState()
      }
    }

    private func protectedCaseRanges(in string: String, selection: NSRange) -> [NSRange] {
      let ns = string as NSString
      var ranges: [NSRange] = []
      var location = 0
      while location < ns.length {
        let paragraph = ns.paragraphRange(for: NSRange(location: location, length: 0))
        let line = ns.substring(with: paragraph).trimmingCharacters(in: .newlines)
        if let parsed = EditorListEngine.parse(line) {
          let prefixLength = (parsed.depth * 4) + line.dropFirst(parsed.depth * 4)
            .prefix(while: { $0 != " " }).utf16.count + 1
          ranges.append(NSRange(location: paragraph.location, length: prefixLength))
        }
        location = NSMaxRange(paragraph)
      }
      for link in NoteLinkParser.links(in: string) {
        let opening = NSRange(location: link.range.location, length: 1)
        let labelClose = link.destinationRange.location - 2
        ranges.append(opening)
        ranges.append(NSRange(location: labelClose, length: 2))
        ranges.append(link.destinationRange)
        ranges.append(NSRange(location: NSMaxRange(link.destinationRange), length: 1))
      }
      ranges.append(contentsOf: InlineNoteImageStore.referenceRanges(in: string))
      return ranges.compactMap {
        let intersection = NSIntersectionRange($0, selection)
        return intersection.length > 0 ? intersection : nil
      }
    }
  }

  enum EditorAttributedCaseTransformer {
    private static let rootLocale = Locale(identifier: "und")

    enum ScalarOperation {
      case lowercase
      case uppercase
      case lowercaseThenUppercase
    }

    static func transform(
      _ source: NSAttributedString,
      mode: EditorTextCase,
      protectedRanges: [NSRange]
    ) -> NSAttributedString {
      let ns = source.string as NSString
      guard ns.length > 0 else { return source }
      let protected = IndexSet(protectedRanges.flatMap { Array($0.location..<NSMaxRange($0)) })
      let sentenceStarts = mode == .sentence
        ? sentenceStartLocations(in: source.string, excluding: protected)
        : IndexSet()
      let result = NSMutableAttributedString()
      var location = 0
      while location < ns.length {
        let composed = ns.rangeOfComposedCharacterSequence(at: location)
        if protected.intersects(integersIn: composed.location..<NSMaxRange(composed)) {
          result.append(source.attributedSubstring(from: composed))
          location = NSMaxRange(composed)
        } else {
          var end = NSMaxRange(composed)
          while end < ns.length {
            let next = ns.rangeOfComposedCharacterSequence(at: end)
            guard !protected.intersects(integersIn: next.location..<NSMaxRange(next))
            else { break }
            end = NSMaxRange(next)
          }
          guard let transformed = transformedRun(
            source,
            range: NSRange(location: location, length: end - location),
            mode: mode,
            sentenceStarts: sentenceStarts
          ) else { return source }
          result.append(transformed)
          location = end
        }
      }
      return result
    }

    private static func transformedRun(
      _ source: NSAttributedString,
      range: NSRange,
      mode: EditorTextCase,
      sentenceStarts: IndexSet
    ) -> NSAttributedString? {
      let sourceString = (source.string as NSString).substring(with: range)
      switch mode {
      case .uppercase:
        return mappedOutput(
          sourceString.uppercased(with: rootLocale),
          source: source,
          sourceRange: range,
          operation: { _ in .uppercase }
        )
      case .lowercase:
        return mappedOutput(
          sourceString.lowercased(with: rootLocale),
          source: source,
          sourceRange: range,
          operation: { _ in .lowercase }
        )
      case .sentence:
        let starts = sentenceStarts
          .filter { $0 >= range.location && $0 < NSMaxRange(range) }
        let boundaries = Array(Set([range.location, NSMaxRange(range)] + starts)).sorted()
        let sourceNSString = source.string as NSString
        let result = NSMutableAttributedString()
        for (start, end) in zip(boundaries, boundaries.dropFirst()) where start < end {
          let sourceRange = NSRange(location: start, length: end - start)
          var output = sourceNSString.substring(with: sourceRange)
            .lowercased(with: rootLocale)
          var capitalizedSourceRange: NSRange?
          if sentenceStarts.contains(start), !output.isEmpty {
            let outputNSString = output as NSString
            let firstOutput = outputNSString.rangeOfComposedCharacterSequence(at: 0)
            output = outputNSString.replacingCharacters(
              in: firstOutput,
              with: outputNSString.substring(with: firstOutput)
                .uppercased(with: rootLocale)
            )
            capitalizedSourceRange = sourceNSString.rangeOfComposedCharacterSequence(at: start)
          }
          guard let mapped = mappedOutput(
            output,
            source: source,
            sourceRange: sourceRange,
            operation: { location in
              guard let capitalizedSourceRange,
                NSLocationInRange(location, capitalizedSourceRange)
              else { return .lowercase }
              return .lowercaseThenUppercase
            }
          ) else { return nil }
          result.append(mapped)
        }
        return result
      }
    }

    static func mappedOutput(
      _ output: String,
      source: NSAttributedString,
      sourceRange: NSRange,
      operation: (Int) -> ScalarOperation
    ) -> NSAttributedString? {
      let sourceNSString = source.string as NSString
      guard sourceRange.length > 0,
        sourceRange.location >= 0,
        NSMaxRange(sourceRange) <= source.length,
        sourceNSString.rangeOfComposedCharacterSequences(for: sourceRange) == sourceRange
      else { return nil }

      let outputNSString = output as NSString
      var outputScalarBoundaries = IndexSet(integer: 0)
      var outputScalarOffset = 0
      for scalar in output.unicodeScalars {
        outputScalarOffset += String(scalar).utf16.count
        outputScalarBoundaries.insert(outputScalarOffset)
      }
      guard outputScalarOffset == outputNSString.length else { return nil }

      let result = NSMutableAttributedString()
      let sourceFragment = sourceNSString.substring(with: sourceRange)
      var sourceOffset = sourceRange.location
      var outputOffset = 0
      for scalar in sourceFragment.unicodeScalars {
        let scalarString = String(scalar)
        let independentlyMapped: String
        switch operation(sourceOffset) {
        case .lowercase:
          independentlyMapped = scalarString.lowercased(with: rootLocale)
        case .uppercase:
          independentlyMapped = scalarString.uppercased(with: rootLocale)
        case .lowercaseThenUppercase:
          independentlyMapped = scalarString
            .lowercased(with: rootLocale)
            .uppercased(with: rootLocale)
        }
        let mappedLength = independentlyMapped.utf16.count
        let (mappedEnd, overflowed) = outputOffset.addingReportingOverflow(mappedLength)
        guard !overflowed,
          mappedEnd <= outputNSString.length,
          outputScalarBoundaries.contains(outputOffset),
          outputScalarBoundaries.contains(mappedEnd)
        else { return nil }
        if mappedLength > 0 {
          result.append(NSAttributedString(
            string: outputNSString.substring(
              with: NSRange(location: outputOffset, length: mappedLength)
            ),
            attributes: source.attributes(at: sourceOffset, effectiveRange: nil)
          ))
        }
        sourceOffset += scalarString.utf16.count
        outputOffset = mappedEnd
      }
      guard sourceOffset == NSMaxRange(sourceRange),
        outputOffset == outputNSString.length,
        result.string == output
      else { return nil }
      return result
    }

    private static func sentenceStartLocations(
      in string: String,
      excluding protected: IndexSet
    ) -> IndexSet {
      let ns = string as NSString
      var result = IndexSet()
      let terminalPattern = try? NSRegularExpression(
        pattern: #"\p{Sentence_Terminal}|\R"#
      )
      var needsCapital = true
      var location = 0
      while location < ns.length {
        let composed = ns.rangeOfComposedCharacterSequence(at: location)
        let fragment = ns.substring(with: composed)
        if needsCapital,
          !protected.intersects(integersIn: composed.location..<NSMaxRange(composed)),
          isCased(fragment)
        {
          result.insert(composed.location)
          needsCapital = false
        }
        if terminalPattern?.firstMatch(
          in: fragment,
          range: NSRange(location: 0, length: (fragment as NSString).length)
        ) != nil {
          needsCapital = true
        }
        location = NSMaxRange(composed)
      }
      return result
    }

    private static func isCased(_ string: String) -> Bool {
      string.lowercased(with: rootLocale) != string.uppercased(with: rootLocale)
    }
  }
#endif
