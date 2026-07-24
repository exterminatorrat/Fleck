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
    @Published private(set) var isStrikethrough = false

    private weak var textView: ListAwareTextView?

    fileprivate func connect(to textView: ListAwareTextView) {
      self.textView = textView
      refreshState()
    }

    func toggleBold() { toggleFontTrait(.boldFontMask) }
    func toggleItalic() { toggleFontTrait(.italicFontMask) }

    func toggleUnderline() {
      toggleAttribute(.underlineStyle, enabledValue: NSUnderlineStyle.single.rawValue)
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
    }

    func applyList(_ style: EditorListStyle) {
      textView?.toggleList(style)
    }

    func undo() { textView?.undoManager?.undo() }
    func redo() { textView?.undoManager?.redo() }

    func refreshState() {
      guard let textView else { return }
      let attributes = activeAttributes(in: textView)
      let font = attributes[.font] as? NSFont ?? textView.font ?? .systemFont(ofSize: 14)
      let traits = NSFontManager.shared.traits(of: font)
      isBold = traits.contains(.boldFontMask)
      isItalic = traits.contains(.italicFontMask)
      isUnderlined = attributeIsEnabled(attributes[.underlineStyle])
      isStrikethrough = attributeIsEnabled(attributes[.strikethroughStyle])
    }

    private func activeAttributes(in textView: NSTextView) -> [NSAttributedString.Key: Any] {
      let range = textView.selectedRange()
      guard range.length > 0, let storage = textView.textStorage, storage.length > 0 else {
        return textView.typingAttributes
      }
      return storage.attributes(
        at: min(range.location, storage.length - 1),
        effectiveRange: nil
      )
    }

    private func attributeIsEnabled(_ value: Any?) -> Bool {
      (value as? NSNumber)?.intValue != 0
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
        refreshState()
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
      refreshState()
    }

    private func toggleAttribute(_ key: NSAttributedString.Key, enabledValue: Int) {
      guard let textView else { return }
      let range = textView.selectedRange()
      if range.length == 0 {
        let isEnabled = (textView.typingAttributes[key] as? Int ?? 0) != 0
        textView.typingAttributes[key] = isEnabled ? 0 : enabledValue
        refreshState()
        return
      }
      let isEnabled =
        (textView.textStorage?.attribute(key, at: range.location, effectiveRange: nil) as? Int ?? 0)
        != 0
      textView.textStorage?.addAttribute(key, value: isEnabled ? 0 : enabledValue, range: range)
      textView.didChangeText()
      refreshState()
    }
  }

  enum EditorListStyle {
    case bullets
    case numbers
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
        height: CGFloat.greatestFiniteMagnitude
      )
      textView.setAccessibilityLabel("Note body")
      loadContent(into: textView)
      applyColors(to: textView)
      textView.automaticLists = automaticLists
      applyColors(to: textView)
      scrollView.documentView = textView
      commands.connect(to: textView)
      return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
      guard let textView = scrollView.documentView as? ListAwareTextView else { return }
      context.coordinator.parent = self
      commands.connect(to: textView)
      textView.automaticLists = automaticLists
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

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
      var parent: NativeRichTextEditor
      var fontFamily: String
      var fontSize: Double
      var richTextRTF: Data?
      init(parent: NativeRichTextEditor) {
        self.parent = parent
        fontFamily = parent.fontFamily
        fontSize = parent.fontSize
        richTextRTF = parent.richTextRTF
      }

      func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        parent.text = textView.string
        guard let storage = textView.textStorage else { return }
        parent.richTextRTF = try? storage.data(
          from: NSRange(location: 0, length: storage.length),
          documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        richTextRTF = parent.richTextRTF
        parent.commands.refreshState()
      }

      func textViewDidChangeSelection(_ notification: Notification) {
        parent.commands.refreshState()
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

  fileprivate final class ListAwareTextView: NSTextView {
    var automaticLists = true

    override func insertNewline(_ sender: Any?) {
      guard automaticLists, let continuation = currentListContinuation() else {
        super.insertNewline(sender)
        return
      }
      if continuation.isEmptyItem {
        textStorage?.replaceCharacters(in: continuation.paragraphRange, with: "")
        didChangeText()
      } else {
        insertText("\n\(continuation.nextPrefix)", replacementRange: selectedRange())
      }
    }

    override func insertTab(_ sender: Any?) { indentSelectedLines(removing: false) }
    override func insertBacktab(_ sender: Any?) { indentSelectedLines(removing: true) }

    func toggleList(_ style: EditorListStyle) {
      let ns = string as NSString
      let selection = selectedRange()
      let lineRange = ns.lineRange(for: selection)
      let original = ns.substring(with: lineRange)
      let lines = original.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
      let marker = try? NSRegularExpression(pattern: #"^\s*(?:[-*+] |\d+[.)] )"#)
      let allMarked = lines.filter { !$0.isEmpty }.allSatisfy {
        marker?.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil
      }
      var number = 1
      let changed = lines.map { line -> String in
        let range = NSRange(line.startIndex..., in: line)
        let stripped =
          marker?.stringByReplacingMatches(in: line, range: range, withTemplate: "") ?? line
        guard !allMarked, !stripped.isEmpty else { return stripped }
        defer { number += 1 }
        return style == .bullets ? "- \(stripped)" : "\(number). \(stripped)"
      }.joined(separator: "\n")
      textStorage?.replaceCharacters(in: lineRange, with: changed)
      setSelectedRange(NSRange(location: lineRange.location, length: (changed as NSString).length))
      didChangeText()
    }

    private func currentListContinuation() -> (
      paragraphRange: NSRange, nextPrefix: String, isEmptyItem: Bool
    )? {
      let ns = string as NSString
      let cursor = selectedRange().location
      let paragraphRange = ns.paragraphRange(for: NSRange(location: cursor, length: 0))
      let paragraph = ns.substring(with: paragraphRange).trimmingCharacters(in: .newlines)
      let expression = try? NSRegularExpression(pattern: #"^(\s*)([-*+]|(\d+)[.)])\s(.*)$"#)
      guard
        let match = expression?.firstMatch(
          in: paragraph, range: NSRange(paragraph.startIndex..., in: paragraph)),
        let indentRange = Range(match.range(at: 1), in: paragraph),
        let markerRange = Range(match.range(at: 2), in: paragraph),
        let contentRange = Range(match.range(at: 4), in: paragraph)
      else { return nil }
      let indent = String(paragraph[indentRange])
      let marker = String(paragraph[markerRange])
      let content = String(paragraph[contentRange])
      let nextMarker: String
      if match.range(at: 3).location != NSNotFound,
        let numberRange = Range(match.range(at: 3), in: paragraph),
        let number = Int(paragraph[numberRange])
      {
        nextMarker = "\(number + 1)."
      } else {
        nextMarker = marker
      }
      return (paragraphRange, "\(indent)\(nextMarker) ", content.isEmpty)
    }

    private func indentSelectedLines(removing: Bool) {
      let ns = string as NSString
      let range = ns.lineRange(for: selectedRange())
      let original = ns.substring(with: range)
      let lines = original.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
      let changed = lines.map { line in
        if removing { return line.hasPrefix("    ") ? String(line.dropFirst(4)) : line }
        return line.isEmpty ? line : "    " + line
      }.joined(separator: "\n")
      textStorage?.replaceCharacters(in: range, with: changed)
      setSelectedRange(NSRange(location: range.location, length: (changed as NSString).length))
      didChangeText()
    }
  }
#endif
