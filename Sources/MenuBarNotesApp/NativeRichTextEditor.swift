#if os(macOS)
  import AppKit
  import SwiftUI

  /// The small command surface shared by the SwiftUI toolbar and the AppKit editor.
  /// It deliberately keeps the text system inside AppKit instead of mirroring selection
  /// state through SwiftUI on every keystroke.
  @MainActor
  final class EditorCommands: ObservableObject {
    @Published private(set) var isBold = false
    @Published private(set) var isItalic = false
    @Published private(set) var isUnderlined = false

    weak var textView: NSTextView?

    func toggleBold() {
      toggleFontTrait(.boldFontMask)
      refreshFormattingState()
    }

    func toggleItalic() {
      toggleFontTrait(.italicFontMask)
      refreshFormattingState()
    }

    func toggleUnderline() {
      toggleAttribute(.underlineStyle, enabledValue: NSUnderlineStyle.single.rawValue)
      refreshFormattingState()
    }

    func toggleStrikethrough() {
      toggleAttribute(.strikethroughStyle, enabledValue: NSUnderlineStyle.single.rawValue)
    }

    func applyFontFamily(_ family: String) {
      guard let textView else { return }
      mutateSelection(defaultValue: NSFont.systemFont(ofSize: textView.font?.pointSize ?? 14)) {
        font, _ in
        NSFontManager.shared.convert(font, toFamily: family)
      }
      refreshFormattingState()
    }

    func applyList(_ style: EditorListStyle) {
      (textView as? ListAwareTextView)?.toggleList(style)
    }

    func applyAutomaticList(_ family: EditorListFamily) {
      (textView as? ListAwareTextView)?.toggleAutomaticList(family)
    }

    func undo() { textView?.undoManager?.undo() }
    func redo() { textView?.undoManager?.redo() }

    func refreshFormattingState() {
      guard let textView else {
        isBold = false
        isItalic = false
        isUnderlined = false
        return
      }

      let range = textView.selectedRange()
      let attributes: [NSAttributedString.Key: Any]
      if range.length > 0, let storage = textView.textStorage, storage.length > 0 {
        attributes = storage.attributes(
          at: min(range.location, storage.length - 1),
          effectiveRange: nil
        )
      } else {
        attributes = textView.typingAttributes
      }

      let font = attributes[.font] as? NSFont
      let traits = font.map { NSFontManager.shared.traits(of: $0) } ?? []
      isBold = traits.contains(.boldFontMask)
      isItalic = traits.contains(.italicFontMask)
      isUnderlined = (attributes[.underlineStyle] as? Int ?? 0) != 0
    }

    private func toggleFontTrait(_ trait: NSFontTraitMask) {
      guard let textView else { return }
      let manager = NSFontManager.shared
      mutateSelection(defaultValue: NSFont.systemFont(ofSize: textView.font?.pointSize ?? 14)) {
        font, attributes in
        let existing = manager.traits(of: font)
        if existing.contains(trait) {
          return manager.convert(font, toNotHaveTrait: trait)
        }
        return manager.convert(font, toHaveTrait: trait)
      }
    }

    private func mutateSelection(
      defaultValue: NSFont,
      transform: (NSFont, [NSAttributedString.Key: Any]) -> NSFont
    ) {
      guard let textView else { return }
      let range = textView.selectedRange()
      if range.length == 0 {
        let current = textView.typingAttributes[.font] as? NSFont ?? defaultValue
        textView.typingAttributes[.font] = transform(current, textView.typingAttributes)
        return
      }
      textView.textStorage?.beginEditing()
      textView.textStorage?.enumerateAttributes(in: range) { attributes, subrange, _ in
        let current = attributes[.font] as? NSFont ?? defaultValue
        textView.textStorage?.addAttribute(
          .font, value: transform(current, attributes), range: subrange)
      }
      textView.textStorage?.endEditing()
      textView.didChangeText()
    }

    private func toggleAttribute(_ key: NSAttributedString.Key, enabledValue: Int) {
      guard let textView else { return }
      let range = textView.selectedRange()
      if range.length == 0 {
        let isEnabled = (textView.typingAttributes[key] as? Int ?? 0) != 0
        textView.typingAttributes[key] = isEnabled ? 0 : enabledValue
        return
      }
      let isEnabled =
        (textView.textStorage?.attribute(key, at: range.location, effectiveRange: nil) as? Int ?? 0)
        != 0
      textView.textStorage?.addAttribute(key, value: isEnabled ? 0 : enabledValue, range: range)
      textView.didChangeText()
    }
  }

  struct NativeRichTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var richTextRTF: Data?
    let fontFamily: String
    let fontSize: Double
    let textColorHex: String?
    let backgroundColorHex: String?
    let automaticLists: Bool
    let commands: EditorCommands

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
      let scrollView = NSScrollView()
      scrollView.hasVerticalScroller = true
      scrollView.drawsBackground = false
      scrollView.autohidesScrollers = true

      let textView = ListAwareTextView(frame: scrollView.contentView.bounds)
      textView.delegate = context.coordinator
      textView.isRichText = true
      textView.importsGraphics = false
      textView.allowsUndo = true
      textView.isAutomaticSpellingCorrectionEnabled = true
      textView.isContinuousSpellCheckingEnabled = true
      textView.drawsBackground = false
      textView.textContainerInset = NSSize(width: 16, height: 10)
      textView.textContainer?.lineFragmentPadding = 0
      textView.isVerticallyResizable = true
      textView.isHorizontallyResizable = false
      textView.minSize = NSSize(width: 0, height: scrollView.contentView.bounds.height)
      textView.maxSize = NSSize(
        width: CGFloat.greatestFiniteMagnitude,
        height: CGFloat.greatestFiniteMagnitude
      )
      textView.autoresizingMask = [.width]
      textView.textContainer?.widthTracksTextView = true
      textView.textContainer?.containerSize = NSSize(
        width: scrollView.contentView.bounds.width,
        height: .greatestFiniteMagnitude
      )
      textView.setAccessibilityLabel("Note body")
      loadContent(into: textView)
      textView.automaticLists = automaticLists
      applyColors(to: textView)
      scrollView.documentView = textView
      commands.textView = textView
      commands.refreshFormattingState()
      return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
      guard let textView = scrollView.documentView as? ListAwareTextView else { return }
      context.coordinator.parent = self
      commands.textView = textView
      textView.automaticLists = automaticLists
      applyColors(to: textView)
      if context.coordinator.richTextRTF != richTextRTF || textView.string != text {
        let selection = textView.selectedRange()
        loadContent(into: textView)
        textView.setSelectedRange(
          NSRange(location: min(selection.location, text.utf16.count), length: 0))
      } else if context.coordinator.fontFamily != fontFamily
        || context.coordinator.fontSize != fontSize
      {
        applyTypingFont(to: textView)
      }
      context.coordinator.fontFamily = fontFamily
      context.coordinator.fontSize = fontSize
      context.coordinator.richTextRTF = richTextRTF
    }

    private func loadContent(into textView: NSTextView) {
      if let richTextRTF,
        let attributed = try? NSAttributedString(
          data: richTextRTF,
          options: [.documentType: NSAttributedString.DocumentType.rtf],
          documentAttributes: nil
        )
      {
        textView.textStorage?.setAttributedString(attributed)
        applyTypingFont(to: textView)
        return
      }
      textView.string = text
      applyDefaultFont(to: textView)
    }

    private func configuredFont() -> NSFont {
      let systemFont = NSFont.systemFont(ofSize: fontSize)
      return NSFontManager.shared.convert(systemFont, toFamily: fontFamily)
    }

    private func applyColors(to textView: NSTextView) {
      textView.textColor = NSColor(hex: textColorHex) ?? .textColor
      if let background = NSColor(hex: backgroundColorHex) {
        textView.drawsBackground = true
        textView.backgroundColor = background
      } else {
        textView.drawsBackground = false
      }
    }

    private func applyTypingFont(to textView: NSTextView) {
      let font = configuredFont()
      textView.typingAttributes[.font] = font
    }

    private func applyDefaultFont(to textView: NSTextView) {
      let font = configuredFont()
      applyTypingFont(to: textView)
      textView.font = font
      guard let storage = textView.textStorage, storage.length > 0 else { return }
      storage.addAttribute(.font, value: font, range: NSRange(location: 0, length: storage.length))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
      var parent: NativeRichTextEditor
      var fontFamily: String
      var fontSize: Double
      var richTextRTF: Data?
      @MainActor
      init(parent: NativeRichTextEditor) {
        self.parent = parent
        fontFamily = parent.fontFamily
        fontSize = parent.fontSize
        richTextRTF = parent.richTextRTF
      }

      func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        guard let storage = textView.textStorage else { return }
        let updatedRTF = try? storage.data(
          from: NSRange(location: 0, length: storage.length),
          documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        richTextRTF = updatedRTF
        parent.text = textView.string
        parent.richTextRTF = updatedRTF
        parent.commands.refreshFormattingState()
      }

      func textViewDidChangeSelection(_ notification: Notification) {
        parent.commands.refreshFormattingState()
      }
    }
  }

  extension NSColor {
    fileprivate convenience init?(hex: String?) {
      guard let hex else { return nil }
      let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
      guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
      self.init(
        calibratedRed: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: 1
      )
    }
  }

  private final class ListAwareTextView: NSTextView {
    var automaticLists = true

    override func insertNewline(_ sender: Any?) {
      guard automaticLists, selectedRange().length == 0 else {
        super.insertNewline(sender)
        return
      }

      let ns = string as NSString
      let cursor = min(selectedRange().location, ns.length)
      let paragraphRange = ns.paragraphRange(for: NSRange(location: cursor, length: 0))
      let rawParagraph = ns.substring(with: paragraphRange)
      let paragraph = rawParagraph.trimmingCharacters(in: .newlines)
      guard let parsed = EditorListEngine.parse(paragraph) else {
        super.insertNewline(sender)
        return
      }

      if parsed.content.isEmpty {
        let indent = String(repeating: "    ", count: parsed.depth)
        let trailingNewline = rawParagraph.hasSuffix("\n") ? "\n" : ""
        _ = replaceText(
          in: paragraphRange,
          with: indent + trailingNewline,
          selecting: NSRange(location: paragraphRange.location + indent.utf16.count, length: 0)
        )
        return
      }

      guard let continuation = EditorListEngine.continuation(after: paragraph) else {
        super.insertNewline(sender)
        return
      }
      let replacement = "\n" + continuation
      let insertionRange = selectedRange()
      let insertedRange = NSRange(
        location: insertionRange.location,
        length: replacement.utf16.count
      )
      _ = replaceText(
        in: insertionRange,
        with: replacement,
        selecting: NSRange(location: NSMaxRange(insertedRange), length: 0)
      ) { storage, _ in
        storage.removeAttribute(.strikethroughStyle, range: insertedRange)
      }
      typingAttributes[.strikethroughStyle] = 0
    }

    override func insertTab(_ sender: Any?) { indentSelectedLines(removing: false) }
    override func insertBacktab(_ sender: Any?) { indentSelectedLines(removing: true) }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
      let effectiveRange =
        replacementRange.location == NSNotFound ? selectedRange() : replacementRange
      if automaticLists,
        effectiveRange.length == 0,
        insertString as? String == " "
      {
        let ns = string as NSString
        let cursor = min(effectiveRange.location, ns.length)
        let lineRange = ns.lineRange(for: NSRange(location: cursor, length: 0))
        let prefixRange = NSRange(
          location: lineRange.location,
          length: cursor - lineRange.location
        )
        let typedPrefix = ns.substring(with: prefixRange) + " "
        if let normalized = EditorListEngine.normalizeTypedPrefix(typedPrefix) {
          _ = replaceText(
            in: prefixRange,
            with: normalized,
            selecting: NSRange(
              location: prefixRange.location + normalized.utf16.count,
              length: 0
            )
          )
          return
        }
      }
      super.insertText(insertString, replacementRange: replacementRange)
    }

    func toggleList(_ style: EditorListStyle) {
      let ns = string as NSString
      let lineRange = ns.lineRange(for: selectedRange())
      let original = ns.substring(with: lineRange)
      let changed = EditorListEngine.toggle(style: style, in: original)
      replaceSelectedLines(
        lineRange,
        original: original,
        with: changed
      )
    }

    func toggleAutomaticList(_ family: EditorListFamily) {
      let ns = string as NSString
      let lineRange = ns.lineRange(for: selectedRange())
      let original = ns.substring(with: lineRange)
      let changed = EditorListEngine.toggleAutomatic(family: family, in: original)
      replaceSelectedLines(
        lineRange,
        original: original,
        with: changed
      )
    }

    private func indentSelectedLines(removing: Bool) {
      let ns = string as NSString
      let range = ns.lineRange(for: selectedRange())
      let original = ns.substring(with: range)
      let changed = EditorListEngine.indent(original, removing: removing)
      replaceSelectedLines(range, original: original, with: changed)
    }

    override func mouseDown(with event: NSEvent) {
      guard let layoutManager, let textContainer else {
        super.mouseDown(with: event)
        return
      }

      let point = convert(event.locationInWindow, from: nil)
      let textPoint = NSPoint(
        x: point.x - textContainerOrigin.x,
        y: point.y - textContainerOrigin.y
      )
      guard textPoint.x >= 0, textPoint.y >= 0, layoutManager.numberOfGlyphs > 0 else {
        super.mouseDown(with: event)
        return
      }

      let glyphIndex = layoutManager.glyphIndex(for: textPoint, in: textContainer)
      let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
      let ns = string as NSString
      guard characterIndex < ns.length else {
        super.mouseDown(with: event)
        return
      }

      let paragraphRange = ns.paragraphRange(
        for: NSRange(location: characterIndex, length: 0)
      )
      let paragraph = ns.substring(with: paragraphRange).trimmingCharacters(in: .newlines)
      guard let parsed = EditorListEngine.parse(paragraph),
        parsed.style == .checklist
      else {
        super.mouseDown(with: event)
        return
      }

      let markerRange = NSRange(
        location: paragraphRange.location + (parsed.depth * 4),
        length: 1
      )
      let glyphRange = layoutManager.glyphRange(
        forCharacterRange: markerRange,
        actualCharacterRange: nil
      )
      var markerRect = layoutManager.boundingRect(
        forGlyphRange: glyphRange,
        in: textContainer
      )
      markerRect.origin.x += textContainerOrigin.x
      markerRect.origin.y += textContainerOrigin.y
      guard markerRect.insetBy(dx: -4, dy: -3).contains(point) else {
        super.mouseDown(with: event)
        return
      }

      let contentRange = NSRange(
        location: NSMaxRange(markerRange) + 1,
        length: parsed.content.utf16.count
      )
      let selection = selectedRange()
      let completed = !parsed.isChecklistComplete
      _ = replaceText(
        in: markerRange,
        with: completed ? "●" : "○",
        selecting: selection
      ) { storage, _ in
        guard contentRange.length > 0 else { return }
        if completed {
          storage.addAttribute(
            .strikethroughStyle,
            value: NSUnderlineStyle.single.rawValue,
            range: contentRange
          )
        } else {
          storage.removeAttribute(.strikethroughStyle, range: contentRange)
        }
      }
    }

    private func replaceSelectedLines(
      _ range: NSRange,
      original: String,
      with replacement: String
    ) {
      let clearsCompletedChecklist = original
        .split(separator: "\n", omittingEmptySubsequences: false)
        .contains { EditorListEngine.parse(String($0))?.isChecklistComplete == true }
      let replacementRange = NSRange(
        location: range.location,
        length: replacement.utf16.count
      )
      _ = replaceText(
        in: range,
        with: replacement,
        selecting: replacementRange
      ) { storage, insertedRange in
        if clearsCompletedChecklist {
          storage.removeAttribute(.strikethroughStyle, range: insertedRange)
        }
      }
    }

    @discardableResult
    private func replaceText(
      in range: NSRange,
      with replacement: String,
      selecting selection: NSRange,
      updateAttributes: ((NSTextStorage, NSRange) -> Void)? = nil
    ) -> Bool {
      guard shouldChangeText(in: range, replacementString: replacement),
        let storage = textStorage
      else { return false }

      let insertedRange = NSRange(location: range.location, length: replacement.utf16.count)
      storage.beginEditing()
      storage.replaceCharacters(in: range, with: replacement)
      updateAttributes?(storage, insertedRange)
      storage.endEditing()
      setSelectedRange(selection)
      didChangeText()
      return true
    }
  }
#endif
