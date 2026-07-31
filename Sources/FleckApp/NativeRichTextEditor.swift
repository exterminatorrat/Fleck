#if os(macOS)
  import AppKit
  import SwiftUI

  /// The small command surface shared by the SwiftUI toolbar and the AppKit editor.
  /// It deliberately keeps the text system inside AppKit instead of mirroring selection
  /// state through SwiftUI on every keystroke.
  @MainActor
  final class EditorCommands: ObservableObject {
    private struct FocusedDictationTransaction {
      var originalSelection: NSRange
      let originalAttributedSelection: NSAttributedString
      var provisionalRange: NSRange
      var undoGroupOpen = false
    }

    private struct CommittedFocusedDictation {
      let receipt: FocusedDictationCommitReceipt
      let originalSelection: NSRange
      let originalAttributedSelection: NSAttributedString
      let finalRange: NSRange
      let finalAttributedText: NSAttributedString
    }

    private static let focusedDictationAttribute = NSAttributedString.Key(
      "FleckFocusedDictationProvisional"
    )

    @Published private(set) var isBold = false
    @Published private(set) var isItalic = false
    @Published private(set) var isUnderlined = false

    weak var textView: NSTextView? {
      didSet {
        guard focusedDictation != nil else { return }
        guard let origin = focusedDictationTextView else {
          clearFocusedDictation()
          return
        }
        if textView !== origin { cancelFocusedDictation() }
      }
    }
    private var focusedDictation: FocusedDictationTransaction?
    private var committedFocusedDictation: CommittedFocusedDictation?
    private var activeFocusedUndoReceipts = Set<FocusedDictationCommitReceipt>()
    private weak var focusedDictationTextView: NSTextView?
    private weak var focusedDictationStorage: NSTextStorage?
    private var focusedDictationTextViewID: ObjectIdentifier?
    private var focusedDictationStorageID: ObjectIdentifier?
    private var focusedDictationEditObserver: NSObjectProtocol?
    private var isApplyingFocusedDictationEdit = false

    var isFocusedDictationActive: Bool { focusedDictation != nil }

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

    func attributedBindingSnapshot(for textView: NSTextView) -> NSAttributedString? {
      guard let storage = textView.textStorage else { return nil }
      guard let transaction = focusedDictation,
        let (origin, originStorage) = focusedDictationOrigin(),
        origin === textView,
        originStorage === storage,
        NSMaxRange(transaction.provisionalRange) <= storage.length
      else {
        return NSAttributedString(attributedString: storage)
      }

      let snapshot = NSMutableAttributedString(attributedString: storage)
      snapshot.replaceCharacters(
        in: transaction.provisionalRange,
        with: transaction.originalAttributedSelection
      )
      return snapshot
    }

    private func focusedDictationOrigin() -> (NSTextView, NSTextStorage)? {
      guard let textView = focusedDictationTextView,
        let storage = focusedDictationStorage,
        let textViewID = focusedDictationTextViewID,
        let storageID = focusedDictationStorageID,
        ObjectIdentifier(textView) == textViewID,
        ObjectIdentifier(storage) == storageID,
        textView.textStorage === storage
      else { return nil }
      return (textView, storage)
    }

    private func clearFocusedDictation(keepingOrigin: Bool = false) {
      stopObservingFocusedDictationEdits()
      focusedDictation = nil
      guard !keepingOrigin else { return }
      committedFocusedDictation = nil
      focusedDictationTextView = nil
      focusedDictationStorage = nil
      focusedDictationTextViewID = nil
      focusedDictationStorageID = nil
    }

    private func replaceFocusedDictationRange(
      in textView: NSTextView,
      storage: NSTextStorage,
      _ range: NSRange,
      with replacement: NSAttributedString,
      selection: NSRange
    ) {
      guard textView.textStorage === storage, NSMaxRange(range) <= storage.length else { return }
      withoutUndoRegistration(textView) {
        storage.replaceCharacters(in: range, with: replacement)
      }
      textView.setSelectedRange(selection)
    }

    private func replaceFocusedDictationUndo(
      in textView: NSTextView,
      storage: NSTextStorage,
      range: NSRange,
      replacement: NSAttributedString,
      selection: NSRange,
      inverseRange: NSRange,
      inverseReplacement: NSAttributedString,
      inverseSelection: NSRange
    ) {
      guard textView.textStorage === storage, NSMaxRange(range) <= storage.length else { return }
      replaceFocusedDictationRange(
        in: textView,
        storage: storage,
        range,
        with: replacement,
        selection: selection
      )
      textView.undoManager?.registerUndo(withTarget: self) { [weak textView, weak storage] commands in
        guard let textView, let storage else { return }
        commands.replaceFocusedDictationUndo(
          in: textView,
          storage: storage,
          range: inverseRange,
          replacement: inverseReplacement,
          selection: inverseSelection,
          inverseRange: range,
          inverseReplacement: replacement,
          inverseSelection: selection
        )
      }
      textView.didChangeText()
    }

    private func withoutUndoRegistration(_ textView: NSTextView, _ changes: () -> Void) {
      let undoManager = textView.undoManager
      undoManager?.disableUndoRegistration()
      changes()
      undoManager?.enableUndoRegistration()
    }

    private func observeFocusedDictationEdits(in storage: NSTextStorage) {
      focusedDictationEditObserver = NotificationCenter.default.addObserver(
        forName: NSTextStorage.didProcessEditingNotification,
        object: storage,
        queue: nil
      ) { [weak self] notification in
        guard let storage = notification.object as? NSTextStorage else { return }
        let editedRange = storage.editedRange
        let changeInLength = storage.changeInLength
        MainActor.assumeIsolated {
          guard let self, !self.isApplyingFocusedDictationEdit,
            var transaction = self.focusedDictation
          else { return }

          if NSMaxRange(editedRange) <= transaction.provisionalRange.location {
            transaction.provisionalRange.location += changeInLength
            transaction.originalSelection.location += changeInLength
            self.focusedDictation = transaction
          }
        }
      }
    }

    private func stopObservingFocusedDictationEdits() {
      if let focusedDictationEditObserver {
        NotificationCenter.default.removeObserver(focusedDictationEditObserver)
      }
      focusedDictationEditObserver = nil
    }

  }

  extension EditorCommands: FocusedDictationEditing {
    var canBeginFocusedDictation: Bool {
      textView?.textStorage != nil
        && focusedDictation == nil
        && committedFocusedDictation == nil
    }

    func beginFocusedDictation() -> Bool {
      guard let textView, let storage = textView.textStorage, focusedDictation == nil else {
        return false
      }
      let selection = textView.selectedRange()
      guard NSMaxRange(selection) <= storage.length else { return false }

      focusedDictation = FocusedDictationTransaction(
        originalSelection: selection,
        originalAttributedSelection: storage.attributedSubstring(from: selection),
        provisionalRange: selection
      )
      focusedDictationTextView = textView
      focusedDictationStorage = storage
      focusedDictationTextViewID = ObjectIdentifier(textView)
      focusedDictationStorageID = ObjectIdentifier(storage)
      observeFocusedDictationEdits(in: storage)
      return true
    }

    func updateFocusedDictation(provisionalText: String) {
      guard var transaction = focusedDictation else { return }
      guard let (textView, storage) = focusedDictationOrigin(), self.textView === textView,
        NSMaxRange(transaction.provisionalRange) <= storage.length
      else {
        cancelFocusedDictation()
        return
      }
      let provisional = NSMutableAttributedString(
        string: provisionalText,
        attributes: textView.typingAttributes
      )
      provisional.addAttribute(
        Self.focusedDictationAttribute,
        value: true,
        range: NSRange(location: 0, length: provisional.length)
      )
      provisional.addAttribute(
        .backgroundColor,
        value: NSColor.selectedContentBackgroundColor.withAlphaComponent(0.25),
        range: NSRange(location: 0, length: provisional.length)
      )

      isApplyingFocusedDictationEdit = true
      withoutUndoRegistration(textView) {
        storage.replaceCharacters(in: transaction.provisionalRange, with: provisional)
      }
      isApplyingFocusedDictationEdit = false
      transaction.provisionalRange.length = provisional.length
      focusedDictation = transaction
      textView.setSelectedRange(NSRange(location: NSMaxRange(transaction.provisionalRange), length: 0))
    }

    func commitFocusedDictation(text: String) -> FocusedDictationCommitReceipt? {
      guard var transaction = focusedDictation else { return nil }
      guard let (textView, storage) = focusedDictationOrigin(), self.textView === textView,
        NSMaxRange(transaction.provisionalRange) <= storage.length
      else {
        cancelFocusedDictation()
        return nil
      }
      let finalText = NSMutableAttributedString(string: text, attributes: textView.typingAttributes)
      finalText.removeAttribute(
        Self.focusedDictationAttribute,
        range: NSRange(location: 0, length: finalText.length)
      )
      let finalRange = NSRange(location: transaction.provisionalRange.location, length: finalText.length)

      isApplyingFocusedDictationEdit = true
      withoutUndoRegistration(textView) {
        storage.replaceCharacters(in: transaction.provisionalRange, with: finalText)
      }
      isApplyingFocusedDictationEdit = false
      let receipt = FocusedDictationCommitReceipt()
      committedFocusedDictation = CommittedFocusedDictation(
        receipt: receipt,
        originalSelection: transaction.originalSelection,
        originalAttributedSelection: transaction.originalAttributedSelection,
        finalRange: finalRange,
        finalAttributedText: finalText
      )
      activeFocusedUndoReceipts.insert(receipt)
      clearFocusedDictation(keepingOrigin: true)

      if let undoManager = textView.undoManager {
        undoManager.beginUndoGrouping()
        transaction.undoGroupOpen = true
        let originalRange = NSRange(
          location: transaction.originalSelection.location,
          length: transaction.originalAttributedSelection.length
        )
        undoManager.registerUndo(withTarget: self) { [weak textView, weak storage] commands in
          guard let textView, let storage,
            commands.activeFocusedUndoReceipts.contains(receipt)
          else { return }
          commands.replaceFocusedDictationUndo(
            in: textView,
            storage: storage,
            range: finalRange,
            replacement: transaction.originalAttributedSelection,
            selection: transaction.originalSelection,
            inverseRange: originalRange,
            inverseReplacement: finalText,
            inverseSelection: NSRange(location: NSMaxRange(finalRange), length: 0)
          )
        }
        undoManager.setActionName("Dictation")
        undoManager.endUndoGrouping()
        transaction.undoGroupOpen = false
      }
      textView.setSelectedRange(NSRange(location: NSMaxRange(finalRange), length: 0))
      textView.didChangeText()
      return receipt
    }

    func cancelFocusedDictation() {
      guard let transaction = focusedDictation else { return }
      guard let (textView, storage) = focusedDictationOrigin(),
        NSMaxRange(transaction.provisionalRange) <= storage.length
      else {
        clearFocusedDictation()
        return
      }
      isApplyingFocusedDictationEdit = true
      replaceFocusedDictationRange(
        in: textView,
        storage: storage,
        transaction.provisionalRange,
        with: transaction.originalAttributedSelection,
        selection: transaction.originalSelection
      )
      isApplyingFocusedDictationEdit = false
      clearFocusedDictation()
    }

    func rollbackCommittedFocusedDictation(
      _ receipt: FocusedDictationCommitReceipt
    ) -> Bool {
      guard let committed = committedFocusedDictation,
        committed.receipt == receipt,
        let (textView, storage) = focusedDictationOrigin(),
        NSMaxRange(committed.finalRange) <= storage.length,
        storage.attributedSubstring(from: committed.finalRange)
          .isEqual(to: committed.finalAttributedText)
      else { return false }
      activeFocusedUndoReceipts.remove(receipt)
      replaceFocusedDictationRange(
        in: textView,
        storage: storage,
        committed.finalRange,
        with: committed.originalAttributedSelection,
        selection: committed.originalSelection
      )
      textView.didChangeText()
      clearFocusedDictation()
      return true
    }

    func finalizeCommittedFocusedDictation(
      _ receipt: FocusedDictationCommitReceipt
    ) {
      guard committedFocusedDictation?.receipt == receipt else { return }
      clearFocusedDictation()
    }
  }

  struct NativeRichTextEditor: NSViewRepresentable {
    let text: String
    let richTextRTF: Data?
    let onChange: (String, Data?) -> Void
    let fontFamily: String
    let fontSize: Double
    let textColorHex: String?
    let backgroundColorHex: String?
    let accentColorHex: String
    let reduceMotion: Bool
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
      textView.checklistAccentColor = NSColor(hex: accentColorHex) ?? .controlAccentColor
      textView.reduceMotion = reduceMotion
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
      textView.checklistAccentColor = NSColor(hex: accentColorHex) ?? .controlAccentColor
      textView.reduceMotion = reduceMotion
      applyColors(to: textView)
      if !applyExternalContentIfNeeded(to: textView, coordinator: context.coordinator),
        context.coordinator.fontFamily != fontFamily
        || context.coordinator.fontSize != fontSize
      {
        applyTypingFont(to: textView)
      }
      context.coordinator.fontFamily = fontFamily
      context.coordinator.fontSize = fontSize
    }

    @discardableResult
    func applyExternalContentIfNeeded(
      to textView: NSTextView,
      coordinator: Coordinator
    ) -> Bool {
      if coordinator.text == text, coordinator.richTextRTF == richTextRTF {
        coordinator.lastModelText = text
        coordinator.lastModelRichTextRTF = richTextRTF
        return false
      }
      if coordinator.hasPendingLocalEdit,
        coordinator.lastModelText == text,
        coordinator.lastModelRichTextRTF == richTextRTF
      {
        return false
      }
      let modelChanged =
        coordinator.lastModelText != text
        || coordinator.lastModelRichTextRTF != richTextRTF
      if modelChanged, commands.isFocusedDictationActive {
        commands.cancelFocusedDictation()
      }
      guard !commands.isFocusedDictationActive, modelChanged || textView.string != text else {
        return false
      }
      let selection = textView.selectedRange()
      loadContent(into: textView)
      textView.setSelectedRange(
        NSRange(location: min(selection.location, text.utf16.count), length: 0)
      )
      coordinator.text = text
      coordinator.richTextRTF = richTextRTF
      coordinator.lastModelText = text
      coordinator.lastModelRichTextRTF = richTextRTF
      return true
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
      EditorTypography.bodyFont(
        family: fontFamily,
        size: fontSize
      )
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
      var attributes = textView.typingAttributes
      attributes.merge(
        EditorTypography.defaultAttributes(
          family: fontFamily,
          size: fontSize
        ),
        uniquingKeysWith: { _, new in new }
      )
      textView.typingAttributes = attributes
    }

    private func applyDefaultFont(to textView: NSTextView) {
      let font = configuredFont()
      applyTypingFont(to: textView)
      textView.font = font
      guard let storage = textView.textStorage, storage.length > 0 else { return }
      storage.addAttributes(
        EditorTypography.defaultAttributes(
          family: fontFamily,
          size: fontSize
        ),
        range: NSRange(location: 0, length: storage.length)
      )
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
      var parent: NativeRichTextEditor
      var fontFamily: String
      var fontSize: Double
      var text: String
      var richTextRTF: Data?
      var lastModelText: String
      var lastModelRichTextRTF: Data?
      var hasPendingLocalEdit: Bool {
        text != lastModelText || richTextRTF != lastModelRichTextRTF
      }
      @MainActor
      init(parent: NativeRichTextEditor) {
        self.parent = parent
        fontFamily = parent.fontFamily
        fontSize = parent.fontSize
        text = parent.text
        richTextRTF = parent.richTextRTF
        lastModelText = parent.text
        lastModelRichTextRTF = parent.richTextRTF
      }

      func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        guard let snapshot = parent.commands.attributedBindingSnapshot(for: textView) else { return }
        let updatedRTF = try? snapshot.data(
          from: NSRange(location: 0, length: snapshot.length),
          documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        text = snapshot.string
        richTextRTF = updatedRTF
        parent.onChange(snapshot.string, updatedRTF)
        parent.commands.refreshFormattingState()
      }

      func textViewDidChangeSelection(_ notification: Notification) {
        parent.commands.refreshFormattingState()
      }
    }
  }

  extension NSColor {
    convenience init?(hex: String?) {
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

  final class ListAwareTextView: NSTextView {
    var automaticLists = true
    var checklistAccentColor = NSColor.controlAccentColor {
      didSet { needsDisplay = true }
    }
    var reduceMotion = false
    private weak var checklistCompletionOverlay: ChecklistCompletionOverlay?

    var checklistCompletionOverlayCount: Int {
      subviews.filter { $0 is ChecklistCompletionOverlay }.count
    }

    private func removeChecklistCompletionOverlay() {
      checklistCompletionOverlay?.removeFromSuperview()
    }

    private func showChecklistCompletionAnimation(for markerRange: NSRange) {
      removeChecklistCompletionOverlay()
      guard !reduceMotion, let rect = checklistMarkerRect(for: markerRange) else { return }
      let overlay = ChecklistCompletionOverlay(frame: rect, accentColor: checklistAccentColor)
      checklistCompletionOverlay = overlay
      addSubview(overlay)
      overlay.start { [weak overlay] in
        overlay?.removeFromSuperview()
      }
    }

    func checklistMarkerRect(for markerRange: NSRange) -> NSRect? {
      guard let layoutManager, let textContainer,
        markerRange.location != NSNotFound,
        NSMaxRange(markerRange) <= (string as NSString).length
      else { return nil }

      layoutManager.ensureLayout(for: textContainer)
      let glyphRange = layoutManager.glyphRange(
        forCharacterRange: markerRange,
        actualCharacterRange: nil
      )
      guard glyphRange.length > 0 else { return nil }
      let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
      let diameter = max(10, min(glyphRect.width, glyphRect.height))
      return NSRect(
        x: glyphRect.midX - diameter / 2,
        y: glyphRect.midY - diameter / 2,
        width: diameter,
        height: diameter
      ).integral
    }

    func checklistHitRect(for markerRange: NSRange) -> NSRect? {
      checklistMarkerRect(for: markerRange)?.insetBy(dx: -4, dy: -3)
    }

    override func draw(_ dirtyRect: NSRect) {
      super.draw(dirtyRect)

      for markerRange in completedChecklistMarkerRanges(in: dirtyRect) {
        guard let rect = checklistMarkerRect(for: markerRange), rect.intersects(dirtyRect) else {
          continue
        }
        ChecklistMarkerDrawing.drawCompleted(
          in: rect,
          accentColor: checklistAccentColor,
          flipped: isFlipped
        )
      }
    }

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
      let paragraphNumberStyle = numberStyleMetadata(at: paragraphRange.location)
      guard
        let parsed = EditorListEngine.parse(
          paragraph,
          preferredNumberStyle: paragraphNumberStyle
        )
      else {
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

      guard
        let continuation = EditorListEngine.continuation(
          after: paragraph,
          preferredNumberStyle: paragraphNumberStyle
        )
      else {
        super.insertNewline(sender)
        return
      }
      performUndoGroup {
        guard let storage = textStorage else { return }
        let replacement = "\n" + continuation
        let insertionRange = selectedRange()
        let relativeInsertion = insertionRange.location - paragraphRange.location
        let attributedParagraph = NSMutableAttributedString(
          attributedString: storage.attributedSubstring(from: paragraphRange)
        )
        attributedParagraph.insert(
          NSAttributedString(string: replacement, attributes: typingAttributes),
          at: relativeInsertion
        )
        attributedParagraph.removeAttribute(
          .strikethroughStyle,
          range: NSRange(
            location: relativeInsertion,
            length: attributedParagraph.length - relativeInsertion
          )
        )
        _ = replaceAttributedText(
          in: paragraphRange,
          with: attributedParagraph,
          selecting: NSRange(
            location: insertionRange.location + replacement.utf16.count,
            length: 0
          )
        )
        typingAttributes[.strikethroughStyle] = 0
        renumberNumberedList(
          around: NSRange(
            location: paragraphRange.location,
            length: attributedParagraph.length
          )
        )
      }
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
      performUndoGroup {
        replaceSelectedLines(
          lineRange,
          original: original,
          with: changed
        )
        synchronizeNumberStyleMetadata(
          in: NSRange(location: lineRange.location, length: changed.utf16.count),
          explicitStyle: style.numberStyle
        )
        if case .number = style {
          renumberNumberedList(
            around: NSRange(location: lineRange.location, length: changed.utf16.count)
          )
        }
      }
    }

    func toggleAutomaticList(_ family: EditorListFamily) {
      let ns = string as NSString
      let lineRange = ns.lineRange(for: selectedRange())
      let original = ns.substring(with: lineRange)
      let changed = EditorListEngine.toggleAutomatic(family: family, in: original)
      performUndoGroup {
        replaceSelectedLines(
          lineRange,
          original: original,
          with: changed
        )
        synchronizeNumberStyleMetadata(
          in: NSRange(location: lineRange.location, length: changed.utf16.count),
          useAutomaticDepth: family == .numbers
        )
        if family == .numbers {
          renumberNumberedList(
            around: NSRange(location: lineRange.location, length: changed.utf16.count)
          )
        }
      }
    }

    private func indentSelectedLines(removing: Bool) {
      let ns = string as NSString
      let range = ns.lineRange(for: selectedRange())
      let original = ns.substring(with: range)
      let changed = EditorListEngine.indent(original, removing: removing)
      guard changed != original else { return }
      performUndoGroup {
        replaceSelectedLines(range, original: original, with: changed)
        synchronizeNumberStyleMetadata(
          in: NSRange(location: range.location, length: changed.utf16.count),
          useAutomaticDepth: true
        )
        renumberNumberedList(
          around: NSRange(location: range.location, length: changed.utf16.count)
        )
      }
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
      guard checklistHitRect(for: markerRange)?.contains(point) == true else {
        super.mouseDown(with: event)
        return
      }

      _ = toggleChecklist(
        markerRange: markerRange,
        contentLength: parsed.content.utf16.count,
        currentlyCompleted: parsed.isChecklistComplete
      )
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
      let attributed = attributedListReplacement(in: range, with: replacement)
      _ = replaceAttributedText(
        in: range,
        with: attributed,
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

    @discardableResult
    private func replaceAttributedText(
      in range: NSRange,
      with replacement: NSAttributedString,
      selecting selection: NSRange,
      updateAttributes: ((NSTextStorage, NSRange) -> Void)? = nil
    ) -> Bool {
      guard shouldChangeText(in: range, replacementString: replacement.string),
        let storage = textStorage
      else { return false }

      let insertedRange = NSRange(location: range.location, length: replacement.length)
      storage.beginEditing()
      storage.replaceCharacters(in: range, with: replacement)
      updateAttributes?(storage, insertedRange)
      storage.endEditing()
      setSelectedRange(selection)
      didChangeText()
      return true
    }

    private func attributedListReplacement(
      in range: NSRange,
      with replacement: String
    ) -> NSAttributedString {
      guard let storage = textStorage else { return NSAttributedString(string: replacement) }
      let source = storage.attributedSubstring(from: range)
      let sourceLines = source.string.split(
        separator: "\n",
        omittingEmptySubsequences: false
      ).map(String.init)
      let replacementLines = replacement.split(
        separator: "\n",
        omittingEmptySubsequences: false
      ).map(String.init)
      guard sourceLines.count == replacementLines.count else {
        return NSAttributedString(string: replacement, attributes: typingAttributes)
      }

      let result = NSMutableAttributedString()
      var sourceLocation = 0
      for index in sourceLines.indices {
        let sourceLine = sourceLines[index]
        let replacementLine = replacementLines[index]
        let sourceLength = sourceLine.utf16.count
        let sourcePrefixLength = listPrefixLength(in: sourceLine)
        let replacementPrefixLength = listPrefixLength(in: replacementLine)
        let attributesLocation = min(
          sourceLocation + sourcePrefixLength,
          max(0, source.length - 1)
        )
        let attributes =
          source.length > 0
          ? source.attributes(at: attributesLocation, effectiveRange: nil)
          : typingAttributes
        let replacementNSString = replacementLine as NSString
        let replacementPrefix = replacementNSString.substring(
          with: NSRange(location: 0, length: replacementPrefixLength)
        )
        result.append(NSAttributedString(string: replacementPrefix, attributes: attributes))
        let contentLength = max(0, sourceLength - sourcePrefixLength)
        if contentLength > 0 {
          result.append(
            source.attributedSubstring(
              from: NSRange(
                location: sourceLocation + sourcePrefixLength,
                length: contentLength
              )
            )
          )
        }
        sourceLocation += sourceLength
        if index < sourceLines.index(before: sourceLines.endIndex) {
          let newlineAttributes =
            sourceLocation < source.length
            ? source.attributes(at: sourceLocation, effectiveRange: nil)
            : attributes
          result.append(NSAttributedString(string: "\n", attributes: newlineAttributes))
          sourceLocation += 1
        }
      }
      return result
    }

    private func listPrefixLength(in line: String) -> Int {
      if let parsed = EditorListEngine.parse(line) {
        return (parsed.depth * 4) + line.dropFirst(parsed.depth * 4)
          .prefix(while: { $0 != " " }).utf16.count + 1
      }
      return line.prefix(while: { $0 == " " }).utf16.count
    }

    @discardableResult
    private func toggleChecklist(
      markerRange: NSRange,
      contentLength: Int,
      currentlyCompleted: Bool
    ) -> Bool {
      let contentRange = NSRange(
        location: NSMaxRange(markerRange) + 1,
        length: contentLength
      )
      let selection = selectedRange()
      let completed = !currentlyCompleted
      undoManager?.beginUndoGrouping()
      defer { undoManager?.endUndoGrouping() }
      registerStrikethroughUndo(
        enabled: currentlyCompleted,
        range: contentRange
      )
      let changed = replaceText(
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
      guard changed else { return false }
      if completed {
        showChecklistCompletionAnimation(for: markerRange)
      } else {
        removeChecklistCompletionOverlay()
      }
      return true
    }

    private func registerStrikethroughUndo(enabled: Bool, range: NSRange) {
      undoManager?.registerUndo(withTarget: self) { target in
        target.registerStrikethroughUndo(enabled: !enabled, range: range)
        target.removeChecklistCompletionOverlay()
        guard let storage = target.textStorage, range.length > 0 else { return }
        if enabled {
          storage.addAttribute(
            .strikethroughStyle,
            value: NSUnderlineStyle.single.rawValue,
            range: range
          )
        } else {
          storage.removeAttribute(.strikethroughStyle, range: range)
        }
        target.didChangeText()
      }
    }

    private func completedChecklistMarkerRanges(in dirtyRect: NSRect) -> [NSRange] {
      guard let layoutManager, let textContainer, layoutManager.numberOfGlyphs > 0 else {
        return []
      }
      let containerRect = dirtyRect.offsetBy(
        dx: -textContainerOrigin.x,
        dy: -textContainerOrigin.y
      )
      let glyphRange = layoutManager.glyphRange(
        forBoundingRect: containerRect,
        in: textContainer
      )
      guard glyphRange.length > 0 else { return [] }

      let characterRange = layoutManager.characterRange(
        forGlyphRange: glyphRange,
        actualGlyphRange: nil
      )
      let ns = string as NSString
      let visibleEnd = min(ns.length, NSMaxRange(characterRange))
      var location = min(characterRange.location, ns.length)
      var markerRanges: [NSRange] = []

      while location < visibleEnd {
        let paragraphRange = ns.paragraphRange(
          for: NSRange(location: location, length: 0)
        )
        let paragraph = ns.substring(with: paragraphRange)
          .trimmingCharacters(in: .newlines)
        if let parsed = EditorListEngine.parse(paragraph),
          parsed.style == .checklist,
          parsed.isChecklistComplete
        {
          markerRanges.append(
            NSRange(
              location: paragraphRange.location + (parsed.depth * 4),
              length: 1
            )
          )
        }
        let nextLocation = NSMaxRange(paragraphRange)
        guard nextLocation > location else { break }
        location = nextLocation
      }

      return markerRanges
    }

    private func renumberNumberedList(around affectedRange: NSRange) {
      guard let blockRange = numberedBlockRange(around: affectedRange) else { return }
      let ns = string as NSString
      let original = ns.substring(with: blockRange)
      let renumbered = EditorListEngine.renumber(
        original,
        preferredNumberStyle: numberStyleMetadata(at: affectedRange.location)
      )
      guard original != renumbered else { return }
      let selection = selectedRange()
      let attributed = attributedListReplacement(in: blockRange, with: renumbered)
      _ = replaceAttributedText(in: blockRange, with: attributed, selecting: selection)
    }

    private func numberedBlockRange(around affectedRange: NSRange) -> NSRange? {
      let ns = string as NSString
      guard ns.length > 0 else { return nil }
      var block = ns.lineRange(for: NSRange(
        location: min(affectedRange.location, ns.length),
        length: min(affectedRange.length, max(0, ns.length - affectedRange.location))
      ))
      let selectedLines = ns.substring(with: block)
        .split(separator: "\n", omittingEmptySubsequences: true)
      guard selectedLines.contains(where: {
        guard let parsed = EditorListEngine.parse(String($0)) else { return false }
        if case .number = parsed.style { return true }
        return false
      }) else { return nil }

      while block.location > 0 {
        let previous = ns.lineRange(
          for: NSRange(location: block.location - 1, length: 0)
        )
        let line = ns.substring(with: previous).trimmingCharacters(in: .newlines)
        guard let parsed = EditorListEngine.parse(line), case .number = parsed.style else {
          break
        }
        block = NSUnionRange(block, previous)
      }
      while NSMaxRange(block) < ns.length {
        let next = ns.lineRange(
          for: NSRange(location: NSMaxRange(block), length: 0)
        )
        let line = ns.substring(with: next).trimmingCharacters(in: .newlines)
        guard let parsed = EditorListEngine.parse(line), case .number = parsed.style else {
          break
        }
        block = NSUnionRange(block, next)
      }
      return block
    }

    private func synchronizeNumberStyleMetadata(
      in range: NSRange,
      explicitStyle: EditorNumberStyle? = nil,
      useAutomaticDepth: Bool = false
    ) {
      guard let storage = textStorage, storage.length > 0 else { return }
      let ns = string as NSString
      var location = range.location
      let end = min(NSMaxRange(range), ns.length)
      while location <= end, location < ns.length {
        let paragraphRange = ns.paragraphRange(
          for: NSRange(location: location, length: 0)
        )
        let line = ns.substring(with: paragraphRange).trimmingCharacters(in: .newlines)
        let parsed = EditorListEngine.parse(line, preferredNumberStyle: explicitStyle)
        let style: EditorNumberStyle?
        if let explicitStyle, parsed.map({ if case .number = $0.style { true } else { false } }) == true {
          style = explicitStyle
        } else if useAutomaticDepth, let parsed,
          case .number = parsed.style
        {
          style = EditorListEngine.automaticNumber(depth: parsed.depth)
        } else {
          style = nil
        }
        let existing =
          (storage.attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil)
            as? NSParagraphStyle) ?? .default
        let paragraphStyle = existing.mutableCopy() as! NSMutableParagraphStyle
        paragraphStyle.textLists = style.map {
          [
            NSTextList(
              markerFormat: $0.markerFormat,
              options: 0
            )
          ]
        } ?? []
        storage.addAttribute(.paragraphStyle, value: paragraphStyle, range: paragraphRange)
        location = NSMaxRange(paragraphRange)
      }
    }

    private func numberStyleMetadata(at location: Int) -> EditorNumberStyle? {
      guard let storage = textStorage, storage.length > 0 else { return nil }
      let safeLocation = min(location, storage.length - 1)
      guard
        let paragraphStyle = storage.attribute(
          .paragraphStyle,
          at: safeLocation,
          effectiveRange: nil
        ) as? NSParagraphStyle,
        let format = paragraphStyle.textLists.last?.markerFormat
      else { return nil }
      return EditorNumberStyle(markerFormat: format)
    }

    private func performUndoGroup(_ action: () -> Void) {
      undoManager?.beginUndoGrouping()
      action()
      undoManager?.endUndoGrouping()
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
      var actions = super.accessibilityCustomActions() ?? []
      if selectedChecklistLocation() != nil {
        actions.append(
          NSAccessibilityCustomAction(
            name: "Toggle checklist item",
            target: self,
            selector: #selector(toggleSelectedChecklist)
          )
        )
      }
      return actions
    }

    @objc func toggleSelectedChecklist() -> Bool {
      guard let item = selectedChecklistLocation() else { return false }
      return toggleChecklist(
        markerRange: item.markerRange,
        contentLength: item.contentLength,
        currentlyCompleted: item.completed
      )
    }

    private func selectedChecklistLocation() -> (
      markerRange: NSRange, contentLength: Int, completed: Bool
    )? {
      let ns = string as NSString
      let cursor = min(selectedRange().location, ns.length)
      let range = ns.paragraphRange(for: NSRange(location: cursor, length: 0))
      let paragraph = ns.substring(with: range).trimmingCharacters(in: .newlines)
      guard let parsed = EditorListEngine.parse(paragraph), parsed.style == .checklist else {
        return nil
      }
      return (
        NSRange(location: range.location + (parsed.depth * 4), length: 1),
        parsed.content.utf16.count,
        parsed.isChecklistComplete
      )
    }
  }

  extension EditorNumberStyle {
    fileprivate var markerFormat: NSTextList.MarkerFormat {
      switch self {
      case .decimal: return .decimal
      case .alphabetic: return .lowercaseAlpha
      case .roman: return .lowercaseRoman
      }
    }

    fileprivate init?(markerFormat: NSTextList.MarkerFormat) {
      switch markerFormat {
      case .decimal: self = .decimal
      case .lowercaseAlpha: self = .alphabetic
      case .lowercaseRoman: self = .roman
      default: return nil
      }
    }
  }
#endif
