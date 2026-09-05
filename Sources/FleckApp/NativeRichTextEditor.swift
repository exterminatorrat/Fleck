#if os(macOS)
  import AppKit
  import FleckCore
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
    @Published private(set) var currentFontFamily: String?
    @Published private(set) var currentFontSize: CGFloat?
    @Published private(set) var isFontFamilyMixed = false
    @Published private(set) var isFontSizeMixed = false
    @Published private(set) var currentForegroundColor: NSColor?
    @Published private(set) var currentBackgroundColor: NSColor?
    @Published private(set) var isForegroundColorMixed = false
    @Published private(set) var isBackgroundColorMixed = false

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

    func applyForegroundColor(_ color: NSColor?) {
      applyColor(color, key: .foregroundColor)
    }

    func applyBackgroundColor(_ color: NSColor?) {
      applyColor(color, key: .backgroundColor)
    }

    @discardableResult
    func applyFontSize(_ size: CGFloat) -> Bool {
      guard size.isFinite, (1...512).contains(size), let textView else { return false }
      mutateSelection(defaultValue: NSFont.systemFont(ofSize: textView.font?.pointSize ?? 14)) {
        font, _ in
        NSFontManager.shared.convert(font, toSize: size)
      }
      refreshFormattingState()
      return true
    }

    func applyList(_ style: EditorListStyle) {
      (textView as? ListAwareTextView)?.toggleList(style)
    }

    func applyAutomaticList(_ family: EditorListFamily) {
      (textView as? ListAwareTextView)?.toggleAutomaticList(family)
    }

    func undo() { textView?.undoManager?.undo() }
    func redo() { textView?.undoManager?.redo() }

    @discardableResult
    func insertNoteLink(
      replacing range: NSRange,
      label: String,
      targetNoteID: UUID
    ) -> Bool {
      guard let textView,
        range.location != NSNotFound,
        range.location >= 0,
        NSMaxRange(range) <= (textView.string as NSString).length
      else {
        return false
      }

      let replacement = NoteLinkFormatter.markdown(label: label, targetNoteID: targetNoteID)
      textView.insertText(replacement, replacementRange: range)
      textView.setSelectedRange(
        NSRange(location: range.location + replacement.utf16.count, length: 0)
      )
      return true
    }

    func noteLinkAtSelection() -> NoteLink? {
      guard let textView else { return nil }
      let selection = textView.selectedRange()
      guard selection.location != NSNotFound,
        selection.location >= 0,
        NSMaxRange(selection) <= (textView.string as NSString).length
      else {
        return nil
      }
      if selection.length == 0 {
        return NoteLinkParser.link(
          atUTF16Location: selection.location,
          in: textView.string
        )
      }
      return NoteLinkParser.links(in: textView.string).first {
        NSIntersectionRange($0.range, selection).length > 0
      }
    }

    func refreshFormattingState() {
      guard let textView else {
        isBold = false
        isItalic = false
        isUnderlined = false
        currentFontFamily = nil
        currentFontSize = nil
        isFontFamilyMixed = false
        isFontSizeMixed = false
        currentForegroundColor = nil
        currentBackgroundColor = nil
        isForegroundColorMixed = false
        isBackgroundColorMixed = false
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

      guard range.length > 0, let storage = textView.textStorage, storage.length > 0 else {
        currentFontFamily = font?.familyName
        currentFontSize = font?.pointSize
        isFontFamilyMixed = false
        isFontSizeMixed = false
        currentForegroundColor = attributes[.foregroundColor] as? NSColor
        currentBackgroundColor = attributes[.backgroundColor] as? NSColor
        isForegroundColorMixed = false
        isBackgroundColorMixed = false
        return
      }

      var family: String?
      var size: CGFloat?
      var familyMixed = false
      var sizeMixed = false
      var foreground: NSColor?
      var background: NSColor?
      var foregroundWasSet = false
      var backgroundWasSet = false
      var foregroundMixed = false
      var backgroundMixed = false
      storage.enumerateAttributes(in: range) { attributes, _, _ in
        let runFont = attributes[.font] as? NSFont
        let runFamily = runFont?.familyName
        let runSize = runFont?.pointSize
        if family == nil {
          family = runFamily
        } else if family != runFamily {
          familyMixed = true
        }
        if size == nil {
          size = runSize
        } else if size != runSize {
          sizeMixed = true
        }
        let runForeground = attributes[.foregroundColor] as? NSColor
        if !foregroundWasSet {
          foreground = runForeground
          foregroundWasSet = true
        } else if !colorsMatch(foreground, runForeground) {
          foregroundMixed = true
        }
        let runBackground = attributes[.backgroundColor] as? NSColor
        if !backgroundWasSet {
          background = runBackground
          backgroundWasSet = true
        } else if !colorsMatch(background, runBackground) {
          backgroundMixed = true
        }
      }
      currentFontFamily = familyMixed ? nil : family
      currentFontSize = sizeMixed ? nil : size
      isFontFamilyMixed = familyMixed
      isFontSizeMixed = sizeMixed
      currentForegroundColor = foregroundMixed ? nil : foreground
      currentBackgroundColor = backgroundMixed ? nil : background
      isForegroundColorMixed = foregroundMixed
      isBackgroundColorMixed = backgroundMixed
    }

    private func colorsMatch(_ lhs: NSColor?, _ rhs: NSColor?) -> Bool {
      switch (lhs, rhs) {
      case let (lhs?, rhs?):
        if let lhs = lhs.usingColorSpace(.sRGB), let rhs = rhs.usingColorSpace(.sRGB) {
          let tolerance: CGFloat = 0.0005
          return abs(lhs.redComponent - rhs.redComponent) <= tolerance
            && abs(lhs.greenComponent - rhs.greenComponent) <= tolerance
            && abs(lhs.blueComponent - rhs.blueComponent) <= tolerance
            && abs(lhs.alphaComponent - rhs.alphaComponent) <= tolerance
        }
        return lhs.isEqual(rhs)
      case (nil, nil):
        return true
      default:
        return false
      }
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
      (textView as? ListAwareTextView)?.clearNoteLinkPresentation()
      let range = textView.selectedRange()
      if range.length == 0 {
        let current = textView.typingAttributes[.font] as? NSFont ?? defaultValue
        textView.typingAttributes[.font] = transform(current, textView.typingAttributes)
        return
      }
      textView.textStorage?.beginEditing()
      let original = textView.textStorage?.attributedSubstring(from: range)
      textView.textStorage?.enumerateAttributes(in: range) { attributes, subrange, _ in
        let current = attributes[.font] as? NSFont ?? defaultValue
        textView.textStorage?.addAttribute(
          .font, value: transform(current, attributes), range: subrange)
      }
      textView.textStorage?.endEditing()
      if let original { registerUndo(in: textView, range: range, replacement: original) }
      textView.didChangeText()
    }

    private func applyColor(_ color: NSColor?, key: NSAttributedString.Key) {
      guard let textView else { return }
      (textView as? ListAwareTextView)?.clearNoteLinkPresentation()
      let range = textView.selectedRange()
      if range.length == 0 {
        textView.typingAttributes[key] = color
        refreshFormattingState()
        return
      }
      guard let storage = textView.textStorage else { return }
      let original = storage.attributedSubstring(from: range)
      if let color {
        storage.addAttribute(key, value: color, range: range)
      } else {
        storage.removeAttribute(key, range: range)
      }
      registerUndo(in: textView, range: range, replacement: original)
      textView.didChangeText()
      refreshFormattingState()
    }

    private func registerUndo(in textView: NSTextView, range: NSRange, replacement: NSAttributedString) {
      textView.undoManager?.registerUndo(withTarget: self) { [weak textView] commands in
        guard let textView else { return }
        commands.restoreAttributes(in: textView, range: range, replacement: replacement)
      }
    }

    private func restoreAttributes(in textView: NSTextView, range: NSRange, replacement: NSAttributedString) {
      guard let storage = textView.textStorage else { return }
      (textView as? ListAwareTextView)?.clearNoteLinkPresentation()
      let current = storage.attributedSubstring(from: range)
      registerUndo(in: textView, range: range, replacement: current)
      storage.replaceCharacters(in: range, with: replacement)
      textView.setSelectedRange(range)
      textView.didChangeText()
      refreshFormattingState()
    }

    private func toggleAttribute(_ key: NSAttributedString.Key, enabledValue: Int) {
      guard let textView else { return }
      (textView as? ListAwareTextView)?.clearNoteLinkPresentation()
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
      (textView as? ListAwareTextView)?.clearNoteLinkPresentation()
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

  private final class NoteTitleCell: NSTextFieldCell {
    var accentColor: NSColor = .controlAccentColor {
      didSet { fieldEditor?.insertionPointColor = accentColor }
    }
    private weak var fieldEditor: NSTextView?
    private var originalCaretColor: NSColor?

    override func setUpFieldEditorAttributes(_ textObj: NSText) -> NSText {
      let editor = super.setUpFieldEditorAttributes(textObj)
      if let editor = editor as? NSTextView {
        if fieldEditor !== editor {
          originalCaretColor = editor.insertionPointColor
          fieldEditor = editor
        }
        editor.insertionPointColor = accentColor
      }
      return editor
    }

    override func endEditing(_ textObj: NSText) {
      restoreCaretColor()
      super.endEditing(textObj)
    }

    func restoreCaretColor() {
      // AppKit reuses this editor for other controls in the same window.
      if let originalCaretColor {
        fieldEditor?.insertionPointColor = originalCaretColor
      }
      fieldEditor = nil
      originalCaretColor = nil
    }
  }

  final class NativeEditorDocumentView: NSView {
    let titleField: NSTextField
    let textView: ListAwareTextView

    override var isFlipped: Bool { true }

    init(titleField: NSTextField, textView: ListAwareTextView) {
      self.titleField = titleField
      self.textView = textView
      super.init(frame: .zero)
      autoresizingMask = [.width]
      addSubview(titleField)
      addSubview(textView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    func updateLayout(width: CGFloat, minimumHeight: CGFloat) {
      let width = max(0, width)
      let titleHeight = max(24, titleField.fittingSize.height)
      let titleFrame = NSRect(
        x: 16,
        y: 12,
        width: max(0, width - 32),
        height: titleHeight
      )
      titleField.frame = titleFrame

      let bodyY = titleFrame.maxY
      textView.frame = NSRect(x: 0, y: bodyY, width: width, height: 1)
      textView.textContainer?.containerSize = NSSize(
        width: width,
        height: .greatestFiniteMagnitude
      )
      textView.sizeToFit()
      textView.setFrameSize(NSSize(width: width, height: textView.frame.height))
      if let textContainer = textView.textContainer,
        let layoutManager = textView.layoutManager
      {
        layoutManager.ensureLayout(for: textContainer)
      }
      let usedHeight = textView.textContainer.flatMap { textContainer in
        textView.layoutManager?.usedRect(for: textContainer).height
      } ?? 0
      let textInsets = textView.textContainerInset.height * 2
      let contentHeight = max(1, usedHeight + textInsets)
      let minimumBodyHeight = max(0, minimumHeight - bodyY - 10)
      let bodyHeight = max(contentHeight, minimumBodyHeight)
      textView.setFrameSize(NSSize(width: width, height: bodyHeight))

      var documentFrame = frame
      documentFrame.size = NSSize(
        width: width,
        height: max(minimumHeight, bodyY + bodyHeight + 10)
      )
      frame = documentFrame
    }
  }

  fileprivate final class NativeEditorScrollView: NSScrollView {
    private var isLayingOutDocument = false

    override func layout() {
      super.layout()
      guard !isLayingOutDocument,
        let documentView = documentView as? NativeEditorDocumentView
      else { return }
      isLayingOutDocument = true
      defer { isLayingOutDocument = false }
      let contentOrigin = contentView.bounds.origin
      documentView.updateLayout(
        width: contentView.bounds.width,
        minimumHeight: contentView.bounds.height
      )
      contentView.scroll(to: contentOrigin)
      reflectScrolledClipView(contentView)
      scrollerStyle = .overlay
      verticalScroller?.controlSize = .mini
    }

    func relayoutDocument() {
      needsLayout = true
      layoutSubtreeIfNeeded()
    }
  }

  struct NativeRichTextEditor: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled

    let text: String
    let richTextRTF: Data?
    let title: String
    let titleFontFamily: String
    let onTitleChange: (String) -> Void
    let onTitleFocusChange: (Bool) -> Void
    let onChange: (String, Data?) -> Void
    let fontFamily: String
    let fontSize: Double
    let textColorHex: String?
    let backgroundColorHex: String?
    let accentColorHex: String
    let reduceMotion: Bool
    let automaticLists: Bool
    let commands: EditorCommands
    let isVisible: Bool
    let liveNoteIDs: Set<UUID>
    let onRequestNoteLink: ((NSRange) -> Void)?
    let onOpenNoteLink: ((UUID) -> Void)?
    let onUnavailableNoteLink: (() -> Void)?

    init(
      text: String,
      richTextRTF: Data?,
      title: String = "",
      titleFontFamily: String? = nil,
      onTitleChange: @escaping (String) -> Void = { _ in },
      onTitleFocusChange: @escaping (Bool) -> Void = { _ in },
      onChange: @escaping (String, Data?) -> Void,
      fontFamily: String,
      fontSize: Double,
      textColorHex: String?,
      backgroundColorHex: String?,
      accentColorHex: String,
      reduceMotion: Bool,
      automaticLists: Bool,
      commands: EditorCommands,
      isVisible: Bool = true,
      liveNoteIDs: Set<UUID> = [],
      onRequestNoteLink: ((NSRange) -> Void)? = nil,
      onOpenNoteLink: ((UUID) -> Void)? = nil,
      onUnavailableNoteLink: (() -> Void)? = nil
    ) {
      self.text = text
      self.richTextRTF = richTextRTF
      self.title = title
      self.titleFontFamily = titleFontFamily ?? fontFamily
      self.onTitleChange = onTitleChange
      self.onTitleFocusChange = onTitleFocusChange
      self.onChange = onChange
      self.fontFamily = fontFamily
      self.fontSize = fontSize
      self.textColorHex = textColorHex
      self.backgroundColorHex = backgroundColorHex
      self.accentColorHex = accentColorHex
      self.reduceMotion = reduceMotion
      self.automaticLists = automaticLists
      self.commands = commands
      self.isVisible = isVisible
      self.liveNoteIDs = liveNoteIDs
      self.onRequestNoteLink = onRequestNoteLink
      self.onOpenNoteLink = onOpenNoteLink
      self.onUnavailableNoteLink = onUnavailableNoteLink
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
      let scrollView = NativeEditorScrollView()
      scrollView.hasVerticalScroller = true
      scrollView.drawsBackground = false
      scrollView.autohidesScrollers = true

      let titleField = NSTextField()
      let titleCell = NoteTitleCell(textCell: "")
      titleCell.accentColor = NSColor(hex: accentColorHex) ?? .controlAccentColor
      titleField.cell = titleCell
      titleField.placeholderString = "Note title"
      titleField.stringValue = title
      titleField.isEditable = true
      titleField.isSelectable = true
      titleField.isEnabled = isEnabled
      titleField.isBordered = false
      titleField.drawsBackground = false
      titleField.focusRingType = .none
      titleField.font = EditorTypography.titleNSFont(family: titleFontFamily)
      titleField.usesSingleLineMode = true
      titleField.cell?.lineBreakMode = .byTruncatingTail
      titleField.setAccessibilityLabel("Note title")
      titleField.setAccessibilityElement(isEnabled)
      titleField.delegate = context.coordinator

      let textView = ListAwareTextView(frame: .zero)
      textView.delegate = context.coordinator
      textView.isRichText = true
      textView.importsGraphics = false
      textView.allowsUndo = true
      textView.isAutomaticSpellingCorrectionEnabled = true
      textView.isContinuousSpellCheckingEnabled = true
      textView.drawsBackground = false
      textView.textContainerInset = NSSize(width: 16, height: 8)
      textView.textContainer?.lineFragmentPadding = 0
      textView.isVerticallyResizable = true
      textView.isHorizontallyResizable = false
      textView.minSize = .zero
      textView.maxSize = NSSize(
        width: CGFloat.greatestFiniteMagnitude,
        height: CGFloat.greatestFiniteMagnitude
      )
      textView.autoresizingMask = []
      textView.textContainer?.widthTracksTextView = true
      textView.textContainer?.heightTracksTextView = false
      textView.textContainer?.containerSize = NSSize(
        width: 0,
        height: CGFloat.greatestFiniteMagnitude
      )
      textView.setAccessibilityLabel("Note body")
      loadContent(into: textView)
      textView.automaticLists = automaticLists
      textView.checklistAccentColor = NSColor(hex: accentColorHex) ?? .controlAccentColor
      textView.reduceMotion = reduceMotion
      applyColors(to: textView)
      Self.applyAccentAppearance(to: textView, accentColorHex: accentColorHex)
      configureNoteLinks(on: textView)
      let documentView = NativeEditorDocumentView(
        titleField: titleField,
        textView: textView
      )
      scrollView.documentView = documentView
      documentView.autoresizingMask = [.width]
      context.coordinator.scrollView = scrollView
      if let undoManager = textView.undoManager {
        context.coordinator.undoManager = undoManager
      }
      if isVisible {
        commands.textView = textView
        commands.refreshFormattingState()
      }
      scrollView.relayoutDocument()
      scrollView.contentView.scroll(
        to: NSPoint(x: scrollView.contentView.bounds.origin.x, y: 0)
      )
      scrollView.reflectScrolledClipView(scrollView.contentView)
      return scrollView
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
      guard let documentView = nsView.documentView as? NativeEditorDocumentView else { return }
      let textView = documentView.textView
      let commands = coordinator.parent.commands
      (documentView.titleField.cell as? NoteTitleCell)?.restoreCaretColor()
      documentView.titleField.delegate = nil
      textView.clearNoteLinkPresentation()
      textView.onRequestNoteLink = nil
      textView.onOpenNoteLink = nil
      textView.onUnavailableNoteLink = nil
      textView.delegate = nil
      let undoManager = textView.undoManager ?? coordinator.undoManager
      undoManager?.removeAllActions(withTarget: textView)
      if let storage = textView.textStorage {
        undoManager?.removeAllActions(withTarget: storage)
      }
      coordinator.undoManager = nil
      coordinator.scrollView = nil
      if commands.textView === textView {
        commands.textView = nil
      }
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
      guard let scrollView = scrollView as? NativeEditorScrollView,
        let documentView = scrollView.documentView as? NativeEditorDocumentView
      else { return }
      let textView = documentView.textView
      context.coordinator.parent = self
      context.coordinator.scrollView = scrollView
      if let undoManager = textView.undoManager {
        context.coordinator.undoManager = undoManager
      }
      if isVisible {
        commands.textView = textView
      }
      textView.automaticLists = automaticLists
      textView.checklistAccentColor = NSColor(hex: accentColorHex) ?? .controlAccentColor
      textView.reduceMotion = reduceMotion
      (documentView.titleField.cell as? NoteTitleCell)?.accentColor =
        NSColor(hex: accentColorHex) ?? .controlAccentColor
      documentView.titleField.isEnabled = isEnabled
      documentView.titleField.setAccessibilityElement(isEnabled)
      documentView.titleField.font = EditorTypography.titleNSFont(family: titleFontFamily)
      if documentView.titleField.stringValue != title {
        documentView.titleField.stringValue = title
      }
      textView.clearNoteLinkPresentation()
      let reloadedContent = applyExternalContentIfNeeded(to: textView, coordinator: context.coordinator)
      applyColors(to: textView)
      Self.applyAccentAppearance(to: textView, accentColorHex: accentColorHex)
      configureNoteLinks(on: textView)
      if !reloadedContent,
        context.coordinator.fontFamily != fontFamily
        || context.coordinator.fontSize != fontSize
      {
        applyTypingFont(to: textView)
      }
      context.coordinator.fontFamily = fontFamily
      context.coordinator.fontSize = fontSize
      scrollView.relayoutDocument()
    }

    private func configureNoteLinks(on textView: ListAwareTextView) {
      textView.liveNoteIDs = liveNoteIDs
      textView.onRequestNoteLink = onRequestNoteLink
      textView.onOpenNoteLink = onOpenNoteLink
      textView.onUnavailableNoteLink = onUnavailableNoteLink
      textView.refreshNoteLinks(
        accentColorHex: accentColorHex,
        liveNoteIDs: liveNoteIDs
      )
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
      (textView as? ListAwareTextView)?.cancelPasteOptions()
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
      Self.applyAppearance(
        to: textView,
        textColorHex: textColorHex,
        backgroundColorHex: backgroundColorHex
      )
    }

    static func applyAppearance(
      to textView: NSTextView,
      textColorHex: String?,
      backgroundColorHex: String?
    ) {
      (textView as? ListAwareTextView)?.clearNoteLinkPresentation()
      applyDefaultForegroundColor(
        NSColor(hex: textColorHex) ?? .textColor,
        to: textView
      )
      if let background = NSColor(hex: backgroundColorHex) {
        textView.drawsBackground = true
        textView.backgroundColor = background
      } else {
        textView.drawsBackground = false
      }
    }

    static func applyAccentAppearance(to textView: NSTextView, accentColorHex: String) {
      let accent = NSColor(hex: accentColorHex) ?? .controlAccentColor
      textView.insertionPointColor = accent
      var selectionAttributes = textView.selectedTextAttributes
      selectionAttributes[.backgroundColor] = accent.withAlphaComponent(0.35)
      textView.selectedTextAttributes = selectionAttributes
    }

    private static func applyDefaultForegroundColor(_ color: NSColor, to textView: NSTextView) {
      guard let storage = textView.textStorage, let layoutManager = textView.layoutManager else {
        return
      }
      let range = NSRange(location: 0, length: storage.length)
      layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
      storage.enumerateAttributes(in: range) { attributes, subrange, _ in
        let foregroundColor = attributes[.foregroundColor] as? NSColor
        guard foregroundColor == nil || foregroundColor?.isEqual(NSColor.textColor) == true else {
          return
        }
        layoutManager.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: subrange)
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

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, NSTextFieldDelegate {
      var parent: NativeRichTextEditor
      weak var undoManager: UndoManager?
      fileprivate weak var scrollView: NativeEditorScrollView?
      var fontFamily: String
      var fontSize: Double
      var text: String
      var richTextRTF: Data?
      var lastModelText: String
      var lastModelRichTextRTF: Data?
      private var lastReportedNoteLinkTrigger: (text: String, range: NSRange)?
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
        if let undoManager = textView.undoManager {
          self.undoManager = undoManager
        }
        (textView as? ListAwareTextView)?.clearNoteLinkPresentation()
        parent.applyColors(to: textView)
        guard let snapshot = parent.commands.attributedBindingSnapshot(for: textView) else { return }
        let updatedRTF = try? snapshot.data(
          from: NSRange(location: 0, length: snapshot.length),
          documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        text = snapshot.string
        richTextRTF = updatedRTF
        if let linkTextView = textView as? ListAwareTextView {
          linkTextView.refreshNoteLinks(
            accentColorHex: parent.accentColorHex,
            liveNoteIDs: parent.liveNoteIDs
          )
        }
        parent.onChange(snapshot.string, updatedRTF)
        parent.commands.refreshFormattingState()

        if let trigger = noteLinkTrigger(in: textView) {
          if lastReportedNoteLinkTrigger?.text != snapshot.string
            || lastReportedNoteLinkTrigger?.range != trigger
          {
            lastReportedNoteLinkTrigger = (snapshot.string, trigger)
            parent.onRequestNoteLink?(trigger)
          }
        } else {
          lastReportedNoteLinkTrigger = nil
        }
        scrollView?.relayoutDocument()
      }

      func controlTextDidBeginEditing(_ notification: Notification) {
        parent.onTitleFocusChange(true)
      }

      func controlTextDidEndEditing(_ notification: Notification) {
        parent.onTitleFocusChange(false)
      }

      func controlTextDidChange(_ notification: Notification) {
        guard let titleField = notification.object as? NSTextField else { return }
        parent.onTitleChange(titleField.stringValue)
      }

      func textViewDidChangeSelection(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        if noteLinkTrigger(in: textView) == nil {
          lastReportedNoteLinkTrigger = nil
        }
        parent.commands.refreshFormattingState()
      }

      private func noteLinkTrigger(in textView: NSTextView) -> NSRange? {
        guard !textView.hasMarkedText(), textView.selectedRange().length == 0 else {
          return nil
        }
        let cursor = textView.selectedRange().location
        guard cursor >= 2, cursor <= (textView.string as NSString).length else { return nil }
        let trigger = NSRange(location: cursor - 2, length: 2)
        return (textView.string as NSString).substring(with: trigger) == "[[" ? trigger : nil
      }
    }
  }

  enum PasteOption: Int, CaseIterable, Equatable {
    case keepSourceFormatting
    case pasteTextOnly
    case mergeFormatting

    var title: String {
      switch self {
      case .keepSourceFormatting: return "Keep Source Formatting"
      case .mergeFormatting: return "Merge Formatting"
      case .pasteTextOnly: return "Paste Text Only"
      }
    }
  }

  final class ListAwareTextView: NSTextView {
    private static let noteLinkSeparatorMenuTag = 0xF1EC
    private static let noteLinkRequestMenuTag = 0xF1ED
    private static let noteLinkOpenMenuTag = 0xF1EE

    var automaticLists = true
    var liveNoteIDs: Set<UUID> = []
    var onRequestNoteLink: ((NSRange) -> Void)?
    var onOpenNoteLink: ((UUID) -> Void)?
    var onUnavailableNoteLink: (() -> Void)?
    var checklistAccentColor = NSColor.controlAccentColor {
      didSet { needsDisplay = true }
    }
    var reduceMotion = false
    private weak var checklistCompletionOverlay: ChecklistCompletionOverlay?
    private struct TemporaryAttributeSlice {
      let key: NSAttributedString.Key
      let range: NSRange
      let value: Any?
    }

    private struct TemporaryNoteLinkPresentation {
      let foregroundColor: [TemporaryAttributeSlice]
      let underlineStyle: [TemporaryAttributeSlice]
    }

    private struct ChecklistItem {
      let markerRange: NSRange
      let contentRange: NSRange
      let completed: Bool
    }

    private var temporaryNoteLinkPresentations: [TemporaryNoteLinkPresentation] = []
    private var temporaryChecklistSlices: [TemporaryAttributeSlice] = []
    private var checklistTrackingArea: NSTrackingArea?
    private var hoveredChecklistMarkerRange: NSRange?
    private var checklistPresentationNeedsRefresh = true
    private struct PendingPaste {
      let range: NSRange
      let nativeText: NSAttributedString
      let plainText: String
      let destinationAttributes: [NSAttributedString.Key: Any]
      let hasRichFormatting: Bool
      let hasAttachments: Bool
    }

    private struct PasteContext {
      let replacementRange: NSRange
      let destinationAttributes: [NSAttributedString.Key: Any]
      let originalDocumentLength: Int
      let changeGeneration: Int
    }

    private var pendingPaste: PendingPaste?
    private var pasteOptionsButton: NSButton?
    private var isApplyingPasteOption = false
    private var textChangeGeneration = 0
    private var pasteOptionsBoundsObserver: NSObjectProtocol?
    private var pasteOptionsFocusObservers: [NSObjectProtocol] = []
    private var pasteOptionsClickMonitor: Any?
    private var isPasteOptionsMenuVisible = false

    var hasPasteOptions: Bool { pendingPaste != nil }

    var pasteOptionMenuTitles: [String] {
      PasteOption.allCases.map(\.title)
    }

    var pasteOptionEnabledStates: [Bool] {
      PasteOption.allCases.map(isPasteOptionEnabled)
    }

    static func pasteTextOnly(
      _ text: String,
      destinationAttributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
      NSAttributedString(string: text, attributes: destinationAttributes)
    }

    static func mergePaste(
      _ source: NSAttributedString,
      destinationAttributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
      let result = NSMutableAttributedString()
      let semanticKeys: [NSAttributedString.Key] = [
        .underlineStyle,
        .strikethroughStyle,
        .link
      ]
      source.enumerateAttributes(
        in: NSRange(location: 0, length: source.length),
        options: []
      ) { sourceAttributes, range, _ in
        var attributes = destinationAttributes
        for key in semanticKeys {
          attributes.removeValue(forKey: key)
          if let value = sourceAttributes[key] { attributes[key] = value }
        }
        if let sourceFont = sourceAttributes[.font] as? NSFont,
          let destinationFont = destinationAttributes[.font] as? NSFont
        {
          attributes[.font] = mergedFont(
            sourceFont: sourceFont,
            destinationFont: destinationFont
          )
        }
        let fragment = source.attributedSubstring(from: range)
        result.append(NSAttributedString(string: fragment.string, attributes: attributes))
      }
      return result
    }

    private static func mergedFont(sourceFont: NSFont, destinationFont: NSFont) -> NSFont {
      var result = destinationFont
      for trait: NSFontTraitMask in [.boldFontMask, .italicFontMask] {
        if NSFontManager.shared.traits(of: sourceFont).contains(trait) {
          result = NSFontManager.shared.convert(result, toHaveTrait: trait)
        } else {
          result = NSFontManager.shared.convert(result, toNotHaveTrait: trait)
        }
      }
      return result
    }

    private func clearChecklistPresentation() {
      if let layoutManager {
        restoreTemporaryAttributeSlices(
          temporaryChecklistSlices,
          in: layoutManager,
          textLength: (string as NSString).length
        )
      }
      temporaryChecklistSlices = []
      checklistPresentationNeedsRefresh = true
    }

    func refreshChecklistPresentation() {
      clearChecklistPresentation()
      checklistPresentationNeedsRefresh = false
      guard let storage = textStorage, let layoutManager, storage.length > 0 else {
        needsDisplay = true
        return
      }

      let linkRanges = NoteLinkParser.links(in: string).map(\.range)
      for markerRange in emptyListMarkerRanges() {
        temporaryChecklistSlices.append(contentsOf: temporaryAttributeSlices(
          .foregroundColor,
          in: markerRange,
          layoutManager: layoutManager
        ))
        let effectiveColor = effectiveForegroundColor(
          at: markerRange.location,
          storage: storage,
          layoutManager: layoutManager
        )
        layoutManager.addTemporaryAttribute(
          .foregroundColor,
          value: effectiveColor.withAlphaComponent(
            effectiveColor.alphaComponent * ChecklistMarkerDrawing.emptyListMarkerOpacity
          ),
          forCharacterRange: markerRange
        )
      }
      for item in checklistItems() {
        temporaryChecklistSlices.append(contentsOf: temporaryAttributeSlices(
          .foregroundColor,
          in: item.markerRange,
          layoutManager: layoutManager
        ))
        layoutManager.addTemporaryAttribute(
          .foregroundColor,
          value: NSColor.clear,
          forCharacterRange: item.markerRange
        )

        guard item.completed, item.contentRange.length > 0 else { continue }
        for range in rangesExcluding(item.contentRange, ranges: linkRanges) {
          temporaryChecklistSlices.append(contentsOf: temporaryAttributeSlices(
            .foregroundColor,
            in: range,
            layoutManager: layoutManager
          ))
          temporaryChecklistSlices.append(contentsOf: temporaryAttributeSlices(
            .strikethroughColor,
            in: range,
            layoutManager: layoutManager
          ))
          applyChecklistRecession(in: range, storage: storage, layoutManager: layoutManager)
        }
      }
    }

    func clearNoteLinkPresentation() {
      clearChecklistPresentation()
      guard let layoutManager else {
        temporaryNoteLinkPresentations = []
        return
      }
      restoreTemporaryNoteLinkPresentations(
        in: layoutManager,
        textLength: (string as NSString).length
      )
      temporaryNoteLinkPresentations = []
      needsDisplay = true
    }

    func refreshNoteLinks(accentColorHex: String, liveNoteIDs: Set<UUID>) {
      self.liveNoteIDs = liveNoteIDs
      clearNoteLinkPresentation()
      guard let layoutManager, let textContainer else { return }
      let textLength = (string as NSString).length

      let links = NoteLinkParser.links(in: string)
      guard !links.isEmpty, textLength > 0 else {
        refreshChecklistPresentation()
        needsDisplay = true
        return
      }
      layoutManager.ensureLayout(for: textContainer)
      let accent = NSColor(hex: accentColorHex) ?? .controlAccentColor
      for link in links {
        let presentation = TemporaryNoteLinkPresentation(
          foregroundColor: temporaryAttributeSlices(
            .foregroundColor,
            in: link.range,
            layoutManager: layoutManager
          ),
          underlineStyle: temporaryAttributeSlices(
            .underlineStyle,
            in: link.range,
            layoutManager: layoutManager
          )
        )
        let color = liveNoteIDs.contains(link.targetNoteID) ? accent : .systemOrange
        layoutManager.addTemporaryAttribute(
          .foregroundColor,
          value: color,
          forCharacterRange: link.range
        )
        layoutManager.addTemporaryAttribute(
          .underlineStyle,
          value: liveNoteIDs.contains(link.targetNoteID)
            ? NSUnderlineStyle.single.rawValue
            : NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue,
          forCharacterRange: link.range
        )
        temporaryNoteLinkPresentations.append(presentation)
      }
      refreshChecklistPresentation()
      needsDisplay = true
    }

    private func temporaryAttributeSlices(
      _ key: NSAttributedString.Key,
      in range: NSRange,
      layoutManager: NSLayoutManager
    ) -> [TemporaryAttributeSlice] {
      guard range.length > 0 else { return [] }
      var slices: [TemporaryAttributeSlice] = []
      var location = range.location
      let end = NSMaxRange(range)
      while location < end {
        var effectiveRange = NSRange(location: location, length: 0)
        let value = layoutManager.temporaryAttribute(
          key,
          atCharacterIndex: location,
          effectiveRange: &effectiveRange
        )
        let effectiveEnd = max(location + 1, min(end, NSMaxRange(effectiveRange)))
        slices.append(
          TemporaryAttributeSlice(
            key: key,
            range: NSRange(location: location, length: effectiveEnd - location),
            value: value
          )
        )
        location = effectiveEnd
      }
      return slices
    }

    private func restoreTemporaryNoteLinkPresentations(
      in layoutManager: NSLayoutManager,
      textLength: Int
    ) {
      for presentation in temporaryNoteLinkPresentations {
        restoreTemporaryAttributeSlices(
          presentation.foregroundColor,
          in: layoutManager,
          textLength: textLength
        )
        restoreTemporaryAttributeSlices(
          presentation.underlineStyle,
          in: layoutManager,
          textLength: textLength
        )
      }
    }

    private func restoreTemporaryAttributeSlices(
      _ slices: [TemporaryAttributeSlice],
      in layoutManager: NSLayoutManager,
      textLength: Int
    ) {
      for slice in slices {
        guard slice.range.location < textLength else { continue }
        let range = NSRange(
          location: slice.range.location,
          length: min(slice.range.length, textLength - slice.range.location)
        )
        guard range.length > 0 else { continue }
        if let value = slice.value {
          layoutManager.addTemporaryAttribute(slice.key, value: value, forCharacterRange: range)
        } else {
          layoutManager.removeTemporaryAttribute(slice.key, forCharacterRange: range)
        }
      }
    }

    var checklistCompletionOverlayCount: Int {
      subviews.filter { $0 is ChecklistCompletionOverlay }.count
    }

    private func removeChecklistCompletionOverlay() {
      checklistCompletionOverlay?.removeFromSuperview()
    }

    private func showChecklistCompletionAnimation(
      for markerRange: NSRange,
      contentLength: Int
    ) {
      removeChecklistCompletionOverlay()
      guard !reduceMotion, let rect = checklistMarkerRect(for: markerRange) else { return }
      let overlay = ChecklistCompletionOverlay(frame: rect, accentColor: checklistAccentColor)
      overlay.layer?.opacity = Float(
        contentLength == 0 ? ChecklistMarkerDrawing.emptyListMarkerOpacity : 1
      )
      checklistCompletionOverlay = overlay
      addSubview(overlay)
      overlay.start { [weak overlay] in
        overlay?.removeFromSuperview()
      }
    }

    func checklistMarkerRect(for markerRange: NSRange) -> NSRect? {
      guard let layoutManager, let textContainer,
        markerRange.location != NSNotFound,
        markerRange.location >= 0,
        NSMaxRange(markerRange) <= (string as NSString).length,
        markerRange.location + 2 <= (string as NSString).length
      else { return nil }

      layoutManager.ensureLayout(for: textContainer)
      let glyphRange = layoutManager.glyphRange(
        forCharacterRange: NSRange(location: markerRange.location, length: 2),
        actualCharacterRange: nil
      )
      guard glyphRange.length > 0 else { return nil }
      let slotRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
      var markerSlotRect = slotRect
      let ns = string as NSString
      if let item = checklistItem(
        in: ns.paragraphRange(for: markerRange),
        string: ns
      ), item.contentRange.length > 0, let storage = textStorage
      {
        let content = ns.substring(with: item.contentRange)
        var firstVisibleContentRange: NSRange?
        content.enumerateSubstrings(
          in: content.startIndex..<content.endIndex,
          options: [.byComposedCharacterSequences]
        ) { substring, range, _, stop in
          guard let substring,
            !substring.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          else { return }
          let relativeRange = NSRange(range, in: content)
          firstVisibleContentRange = NSRange(
            location: item.contentRange.location + relativeRange.location,
            length: relativeRange.length
          )
          stop = true
        }

        if let contentRange = firstVisibleContentRange,
          let contentFont = (
            storage.attribute(.font, at: contentRange.location, effectiveRange: nil) as? NSFont
          ) ?? font
        {
          let contentGlyphRange = layoutManager.glyphRange(
            forCharacterRange: contentRange,
            actualCharacterRange: nil
          )
          if contentGlyphRange.length > 0,
            contentGlyphRange.location < layoutManager.numberOfGlyphs
          {
            let contentGlyph = contentGlyphRange.location
            let lineFragmentRect = layoutManager.lineFragmentRect(
              forGlyphAt: contentGlyph,
              effectiveRange: nil
            )
            let baselineY = textContainerOrigin.y
              + lineFragmentRect.minY
              + layoutManager.location(forGlyphAt: contentGlyph).y
            let visibleInkMidY = baselineY
              - contentFont.boundingRect(
                forCGGlyph: layoutManager.cgGlyph(at: contentGlyph)
              ).midY
            markerSlotRect.origin.y += visibleInkMidY - markerSlotRect.midY
          }
        }
      }
      return ChecklistMarkerDrawing.markerRect(around: markerSlotRect)
    }

    func checklistHitRect(for markerRange: NSRange) -> NSRect? {
      guard let markerRect = checklistMarkerRect(for: markerRange) else { return nil }
      return ChecklistMarkerDrawing.hitRect(around: markerRect)
    }

    override func draw(_ dirtyRect: NSRect) {
      if checklistPresentationNeedsRefresh { refreshChecklistPresentation() }
      NSGraphicsContext.saveGraphicsState()
      super.draw(dirtyRect)
      NSGraphicsContext.restoreGraphicsState()

      for item in checklistItems(in: dirtyRect) {
        guard let rect = checklistMarkerRect(for: item.markerRange), rect.intersects(dirtyRect) else {
          continue
        }
        let isHovered = hoveredChecklistMarkerRange == item.markerRange
        let hoverColor = checklistAccentColor.withAlphaComponent(isHovered ? 0.14 : 0)
        let opacity = item.contentRange.length == 0
          ? ChecklistMarkerDrawing.emptyListMarkerOpacity
          : 1
        if item.completed {
          ChecklistMarkerDrawing.drawCompleted(
            in: rect,
            accentColor: checklistAccentColor,
            flipped: isFlipped,
            hoverColor: isHovered ? hoverColor : nil,
            opacity: opacity
          )
        } else {
          ChecklistMarkerDrawing.drawOpen(
            in: rect,
            strokeColor: .secondaryLabelColor,
            hoverColor: isHovered ? hoverColor : nil,
            opacity: opacity
          )
        }
      }
    }

    override func deleteBackward(_ sender: Any?) {
      let selection = selectedRange()
      let ns = string as NSString
      guard selection.length == 0, selection.location > 0, selection.location <= ns.length else {
        super.deleteBackward(sender)
        return
      }

      let paragraphRange = ns.paragraphRange(
        for: NSRange(location: selection.location, length: 0)
      )
      guard let item = checklistItem(in: paragraphRange, string: ns),
        item.contentRange.length == 0,
        selection.location == item.contentRange.location
      else {
        super.deleteBackward(sender)
        return
      }

      performUndoGroup {
        _ = replaceText(
          in: NSRange(
            location: item.markerRange.location,
            length: item.markerRange.length + 1
          ),
          with: "",
          selecting: NSRange(location: item.markerRange.location, length: 0)
        )
      }
    }

    override func resetCursorRects() {
      super.resetCursorRects()
      for item in checklistItems(in: visibleRect) {
        guard let hitRect = checklistHitRect(for: item.markerRange) else { continue }
        addCursorRect(hitRect, cursor: .arrow)
      }
    }

    override func updateTrackingAreas() {
      super.updateTrackingAreas()
      if let checklistTrackingArea {
        removeTrackingArea(checklistTrackingArea)
      }
      let trackingArea = NSTrackingArea(
        rect: bounds,
        options: [.activeInKeyWindow, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
        owner: self,
        userInfo: ["fleckChecklistMarker": true]
      )
      checklistTrackingArea = trackingArea
      addTrackingArea(trackingArea)
    }

    override func mouseMoved(with event: NSEvent) {
      updateHoveredChecklistMarker(at: convert(event.locationInWindow, from: nil))
      super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
      updateHoveredChecklistMarker(at: nil)
      super.mouseExited(with: event)
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

    override func paste(_ sender: Any?) {
      cancelPasteOptions()
      guard let context = pasteContext() else {
        super.paste(sender)
        return
      }

      let pasteboard = NSPasteboard.general
      let plainText = pasteboard.string(forType: .string)
      let hasRichFormatting = pasteboard.data(forType: .rtf) != nil
        || pasteboard.data(forType: .rtfd) != nil
        || pasteboard.data(forType: .html) != nil

      performPaste(
        context: context,
        plainText: plainText,
        hasRichFormatting: hasRichFormatting
      ) {
        super.paste(sender)
      }
    }

    func insertPastedTextForTesting(
      _ attributedText: NSAttributedString,
      plainText: String? = nil,
      hasRichFormatting: Bool = true
    ) {
      cancelPasteOptions()
      guard let context = pasteContext() else { return }
      performPaste(
        context: context,
        plainText: plainText ?? attributedText.string,
        hasRichFormatting: hasRichFormatting
      ) {
        _ = replaceAttributedText(
          in: context.replacementRange,
          with: attributedText,
          selecting: NSRange(
            location: context.replacementRange.location + attributedText.length,
            length: 0
          )
        )
      }
    }

    private func performPaste(
      context: PasteContext,
      plainText: String?,
      hasRichFormatting: Bool,
      insertion: () -> Void
    ) {
      insertion()
      guard textChangeGeneration > context.changeGeneration else { return }
      guard let updatedStorage = textStorage else { return }
      let insertedLength = updatedStorage.length
        - context.originalDocumentLength
        + context.replacementRange.length
      finishPaste(
        insertedRange: NSRange(
          location: context.replacementRange.location,
          length: insertedLength
        ),
        plainText: plainText,
        destinationAttributes: context.destinationAttributes,
        hasRichFormatting: hasRichFormatting
      )
    }

    private func pasteContext() -> PasteContext? {
      guard let storage = textStorage else { return nil }
      let selected = selectedRange()
      guard selected.location != NSNotFound,
        selected.location >= 0,
        selected.location <= storage.length
      else { return nil }
      let replacementLength = min(selected.length, storage.length - selected.location)
      let replacementRange = NSRange(location: selected.location, length: replacementLength)
      return PasteContext(
        replacementRange: replacementRange,
        destinationAttributes: pasteDestinationAttributes(for: replacementRange),
        originalDocumentLength: storage.length,
        changeGeneration: textChangeGeneration
      )
    }

    private func finishPaste(
      insertedRange: NSRange,
      plainText: String?,
      destinationAttributes: [NSAttributedString.Key: Any],
      hasRichFormatting: Bool
    ) {
      guard let updatedStorage = textStorage,
        insertedRange.length > 0,
        insertedRange.location >= 0,
        NSMaxRange(insertedRange) <= updatedStorage.length
      else { return }
      let nativeText = updatedStorage.attributedSubstring(from: insertedRange)
      pendingPaste = PendingPaste(
        range: insertedRange,
        nativeText: nativeText,
        plainText: plainText ?? nativeText.string,
        destinationAttributes: destinationAttributes,
        hasRichFormatting: hasRichFormatting,
        hasAttachments: Self.containsAttachment(in: nativeText)
      )
      showPasteOptions()
    }

    private static func containsAttachment(in text: NSAttributedString) -> Bool {
      var containsAttachment = false
      text.enumerateAttribute(
        .attachment,
        in: NSRange(location: 0, length: text.length),
        options: []
      ) { value, _, stop in
        guard value != nil else { return }
        containsAttachment = true
        stop.pointee = true
      }
      return containsAttachment
    }

    func applyPasteOption(_ option: PasteOption) {
      guard let pendingPaste else { return }
      guard isPasteOptionEnabled(option) else { return }
      guard option != .keepSourceFormatting else {
        cancelPasteOptions()
        return
      }
      let replacement: NSAttributedString
      switch option {
      case .keepSourceFormatting:
        replacement = pendingPaste.nativeText
      case .mergeFormatting:
        replacement = Self.mergePaste(
          pendingPaste.nativeText,
          destinationAttributes: pendingPaste.destinationAttributes
        )
      case .pasteTextOnly:
        replacement = Self.pasteTextOnly(
          pendingPaste.plainText,
          destinationAttributes: pendingPaste.destinationAttributes
        )
      }
      guard let storage = textStorage,
        pendingPaste.range.location >= 0,
        NSMaxRange(pendingPaste.range) <= storage.length
      else {
        cancelPasteOptions()
        return
      }

      isApplyingPasteOption = true
      performUndoGroup {
        _ = replaceAttributedText(
          in: pendingPaste.range,
          with: replacement,
          selecting: NSRange(
            location: pendingPaste.range.location + replacement.length,
            length: 0
          )
        )
      }
      isApplyingPasteOption = false
      cancelPasteOptions()
    }

    func cancelPasteOptions() {
      pendingPaste = nil
      pasteOptionsButton?.removeFromSuperview()
      pasteOptionsButton = nil
      removePasteOptionsClickMonitor()
    }

    func isPasteOptionEnabled(_ option: PasteOption) -> Bool {
      guard let pendingPaste else { return false }
      switch option {
      case .keepSourceFormatting:
        return true
      case .mergeFormatting:
        guard pendingPaste.hasRichFormatting, !pendingPaste.hasAttachments else { return false }
        let merged = Self.mergePaste(
          pendingPaste.nativeText,
          destinationAttributes: pendingPaste.destinationAttributes
        )
        return !merged.isEqual(to: pendingPaste.nativeText)
      case .pasteTextOnly:
        guard pendingPaste.hasRichFormatting, !pendingPaste.hasAttachments else { return false }
        let textOnly = Self.pasteTextOnly(
          pendingPaste.plainText,
          destinationAttributes: pendingPaste.destinationAttributes
        )
        return !textOnly.isEqual(to: pendingPaste.nativeText)
      }
    }

    private func pasteDestinationAttributes(
      for range: NSRange
    ) -> [NSAttributedString.Key: Any] {
      if range.length > 0,
        let storage = textStorage,
        range.location < storage.length
      {
        return storage.attributes(at: range.location, effectiveRange: nil)
      }
      return typingAttributes
    }

    private func showPasteOptions() {
      guard let pendingPaste else { return }
      guard let anchor = pasteOptionsAnchorRect(for: pendingPaste.range) else {
        cancelPasteOptions()
        return
      }
      let button = NSButton(frame: .zero)
      button.setButtonType(.momentaryPushIn)
      button.bezelStyle = .texturedRounded
      button.isBordered = true
      button.image = NSImage(
        systemSymbolName: "doc.on.clipboard",
        accessibilityDescription: "Paste options"
      )
      button.title = "⌄"
      button.imagePosition = .imageLeading
      button.imageScaling = .scaleProportionallyDown
      button.font = NSFont.systemFont(ofSize: 11, weight: .medium)
      button.contentTintColor = .secondaryLabelColor
      button.setAccessibilityElement(true)
      button.setAccessibilityLabel("Paste options")
      button.setAccessibilityHelp("Choose how the pasted content is formatted")
      button.target = self
      button.action = #selector(showPasteOptionsMenu(_:))
      addSubview(button)
      pasteOptionsButton = button
      positionPasteOptionsButton(anchor: anchor)
      guard self.pendingPaste != nil, pasteOptionsButton != nil else { return }
      installPasteOptionsClickMonitor()
    }

    private func pasteOptionsAnchorRect(for range: NSRange) -> NSRect? {
      guard let layoutManager, let textContainer,
        range.location >= 0,
        range.location <= (string as NSString).length
      else { return nil }
      layoutManager.ensureLayout(for: textContainer)
      let stringLength = (string as NSString).length
      let endpoint = min(NSMaxRange(range), stringLength)
      let glyphIndex: Int
      if endpoint < stringLength {
        glyphIndex = layoutManager.glyphIndexForCharacter(at: endpoint)
      } else {
        guard endpoint > 0 else { return nil }
        glyphIndex = layoutManager.glyphIndexForCharacter(at: endpoint - 1)
      }
      guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }
      return layoutManager
        .boundingRect(
          forGlyphRange: NSRange(location: glyphIndex, length: 1),
          in: textContainer
        )
        .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }

    private func positionPasteOptionsButton(anchor: NSRect) {
      guard let button = pasteOptionsButton else { return }
      let visible = visibleRect.isEmpty ? bounds : visibleRect
      let size = NSSize(width: 36, height: 24)
      guard !visible.isEmpty, anchor.intersects(visible) else {
        cancelPasteOptions()
        return
      }
      var origin = NSPoint(x: anchor.maxX - size.width, y: anchor.maxY + 4)
      origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
      if origin.y + size.height > visible.maxY {
        origin.y = anchor.minY - size.height - 4
      }
      origin.y = min(max(origin.y, visible.minY + 4), visible.maxY - size.height - 4)
      button.frame = NSRect(origin: origin, size: size)
    }

    @objc private func showPasteOptionsMenu(_ sender: NSButton) {
      let menu = NSMenu(title: "Paste Options")
      menu.autoenablesItems = false
      for option in PasteOption.allCases {
        let item = NSMenuItem(
          title: option.title,
          action: #selector(selectPasteOptionFromMenu(_:)),
          keyEquivalent: ""
        )
        item.target = self
        item.representedObject = option.rawValue
        item.isEnabled = isPasteOptionEnabled(option)
        item.state = option == .keepSourceFormatting ? .on : .off
        menu.addItem(item)
      }
      isPasteOptionsMenuVisible = true
      defer {
        isPasteOptionsMenuVisible = false
        cancelPasteOptions()
      }
      menu.popUp(
        positioning: nil,
        at: NSPoint(x: 0, y: sender.bounds.maxY),
        in: sender
      )
    }

    @objc private func selectPasteOptionFromMenu(_ sender: NSMenuItem) {
      guard let rawValue = sender.representedObject as? Int,
        let option = PasteOption(rawValue: rawValue)
      else { return }
      applyPasteOption(option)
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

    @objc func requestNoteLinkFromMenu(_ sender: Any?) {
      onRequestNoteLink?(selectedRange())
    }

    @objc func openNoteLinkFromMenu(_ sender: Any?) {
      guard let link = noteLinkAtSelection() else { return }
      if liveNoteIDs.contains(link.targetNoteID) {
        onOpenNoteLink?(link.targetNoteID)
      } else {
        onUnavailableNoteLink?()
      }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
      let menu = super.menu(for: event) ?? NSMenu()
      menu.items
        .filter {
          $0.tag == Self.noteLinkSeparatorMenuTag
            || $0.tag == Self.noteLinkRequestMenuTag
            || $0.tag == Self.noteLinkOpenMenuTag
        }
        .forEach(menu.removeItem)

      let separator = NSMenuItem.separator()
      separator.tag = Self.noteLinkSeparatorMenuTag
      menu.addItem(separator)
      let requestItem = menu.addItem(
        withTitle: "Link to Note…",
        action: #selector(requestNoteLinkFromMenu(_:)),
        keyEquivalent: ""
      )
      requestItem.tag = Self.noteLinkRequestMenuTag
      requestItem.target = self
      if noteLinkAtSelection() != nil {
        let openItem = menu.addItem(
          withTitle: "Open Note Link",
          action: #selector(openNoteLinkFromMenu(_:)),
          keyEquivalent: ""
        )
        openItem.tag = Self.noteLinkOpenMenuTag
        openItem.target = self
      }
      return menu
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
      switch menuItem.action {
      case #selector(requestNoteLinkFromMenu(_:)):
        return isEditable
      case #selector(openNoteLinkFromMenu(_:)):
        guard let link = noteLinkAtSelection() else { return false }
        return liveNoteIDs.contains(link.targetNoteID)
      default:
        return super.validateMenuItem(menuItem)
      }
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
      switch item.action {
      case #selector(requestNoteLinkFromMenu(_:)):
        return isEditable
      case #selector(openNoteLinkFromMenu(_:)):
        guard let link = noteLinkAtSelection() else { return false }
        return liveNoteIDs.contains(link.targetNoteID)
      default:
        return super.validateUserInterfaceItem(item)
      }
    }

    private func noteLinkAtSelection() -> NoteLink? {
      let selection = selectedRange()
      guard selection.location != NSNotFound,
        selection.location >= 0,
        NSMaxRange(selection) <= (string as NSString).length
      else {
        return nil
      }
      if selection.length == 0 {
        return NoteLinkParser.link(atUTF16Location: selection.location, in: string)
      }
      return NoteLinkParser.links(in: string).first {
        NSIntersectionRange($0.range, selection).length > 0
      }
    }

    override func shouldChangeText(
      in affectedCharRange: NSRange,
      replacementString: String?
    ) -> Bool {
      guard super.shouldChangeText(
        in: affectedCharRange,
        replacementString: replacementString
      ) else {
        return false
      }
      clearNoteLinkPresentation()
      if !isApplyingPasteOption { cancelPasteOptions() }
      return true
    }

    override func didChangeText() {
      textChangeGeneration += 1
      super.didChangeText()
    }

    override func setSelectedRange(_ range: NSRange) {
      let changed = range != selectedRange()
      super.setSelectedRange(range)
      if changed, !isApplyingPasteOption { cancelPasteOptions() }
    }

    override func setSelectedRanges(
      _ ranges: [NSValue],
      affinity: NSSelectionAffinity,
      stillSelecting flag: Bool
    ) {
      let previousRanges = selectedRanges
      super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: flag)
      guard !isApplyingPasteOption else { return }
      let currentRanges = selectedRanges
      guard previousRanges.count != currentRanges.count
        || zip(previousRanges, currentRanges).contains(where: { !$0.isEqual(to: $1) })
      else { return }
      cancelPasteOptions()
    }

    override func cancelOperation(_ sender: Any?) {
      guard hasPasteOptions else {
        super.cancelOperation(sender)
        return
      }
      cancelPasteOptions()
    }

    override func resignFirstResponder() -> Bool {
      cancelPasteOptions()
      return super.resignFirstResponder()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
      if newWindow == nil {
        removePasteOptionsBoundsObserver()
        removePasteOptionsFocusObservers()
        cancelPasteOptions()
      }
      super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      removePasteOptionsBoundsObserver()
      removePasteOptionsFocusObservers()
      removePasteOptionsClickMonitor()
      guard let window else { return }
      installPasteOptionsFocusObservers(for: window)
      if let clipView = enclosingScrollView?.contentView {
        clipView.postsBoundsChangedNotifications = true
        pasteOptionsBoundsObserver = NotificationCenter.default.addObserver(
          forName: NSView.boundsDidChangeNotification,
          object: clipView,
          queue: .main
        ) { [weak self] _ in
          DispatchQueue.main.async { [weak self] in
            self?.updatePasteOptionsPlacement()
          }
        }
      }
      if pendingPaste != nil, pasteOptionsButton != nil {
        installPasteOptionsClickMonitor()
      }
    }

    isolated deinit {
      if let observer = pasteOptionsBoundsObserver {
        NotificationCenter.default.removeObserver(observer)
      }
      pasteOptionsFocusObservers.forEach(NotificationCenter.default.removeObserver)
      if let monitor = pasteOptionsClickMonitor {
        NSEvent.removeMonitor(monitor)
      }
    }

    override func layout() {
      super.layout()
      updatePasteOptionsPlacement()
    }

    private func updatePasteOptionsPlacement() {
      guard let pendingPaste else { return }
      guard let anchor = pasteOptionsAnchorRect(for: pendingPaste.range) else {
        cancelPasteOptions()
        return
      }
      positionPasteOptionsButton(anchor: anchor)
    }

    private func removePasteOptionsBoundsObserver() {
      if let pasteOptionsBoundsObserver {
        NotificationCenter.default.removeObserver(pasteOptionsBoundsObserver)
        self.pasteOptionsBoundsObserver = nil
      }
    }

    private func installPasteOptionsClickMonitor() {
      guard pasteOptionsClickMonitor == nil else { return }
      pasteOptionsClickMonitor = NSEvent.addLocalMonitorForEvents(
        matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
      ) { [weak self] event in
        guard let self else { return event }
        MainActor.assumeIsolated {
          guard !self.isPasteOptionsMenuVisible,
            !self.isPasteOptionsEventInsideTextView(event)
          else { return }
          self.cancelPasteOptions()
        }
        return event
      }
    }

    private func isPasteOptionsEventInsideTextView(_ event: NSEvent) -> Bool {
      guard let textWindow = window, event.windowNumber == textWindow.windowNumber else {
        return false
      }
      let point = event.window == nil
        ? event.locationInWindow
        : convert(event.locationInWindow, from: nil)
      return bounds.contains(point)
    }

    private func removePasteOptionsClickMonitor() {
      if let pasteOptionsClickMonitor {
        NSEvent.removeMonitor(pasteOptionsClickMonitor)
        self.pasteOptionsClickMonitor = nil
      }
    }

    private func installPasteOptionsFocusObservers(for window: NSWindow) {
      let notificationCenter = NotificationCenter.default
      pasteOptionsFocusObservers = [
        notificationCenter.addObserver(
          forName: NSWindow.didResignKeyNotification,
          object: window,
          queue: .main
        ) { [weak self] _ in
          MainActor.assumeIsolated {
            self?.cancelPasteOptions()
          }
        },
        notificationCenter.addObserver(
          forName: NSApplication.didResignActiveNotification,
          object: NSApplication.shared,
          queue: .main
        ) { [weak self] _ in
          MainActor.assumeIsolated {
            self?.cancelPasteOptions()
          }
        }
      ]
    }

    private func removePasteOptionsFocusObservers() {
      pasteOptionsFocusObservers.forEach(NotificationCenter.default.removeObserver)
      pasteOptionsFocusObservers.removeAll()
    }

    func noteLinkTarget(atViewPoint point: NSPoint) -> UUID? {
      guard let layoutManager, let textContainer,
        point.x >= textContainerOrigin.x,
        point.y >= textContainerOrigin.y,
        layoutManager.numberOfGlyphs > 0
      else {
        return nil
      }
      let textPoint = NSPoint(
        x: point.x - textContainerOrigin.x,
        y: point.y - textContainerOrigin.y
      )
      let glyphIndex = layoutManager.glyphIndex(for: textPoint, in: textContainer)
      guard glyphIndex < layoutManager.numberOfGlyphs,
        layoutManager
          .boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1),
            in: textContainer
          )
          .contains(textPoint)
      else {
        return nil
      }
      let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
      guard characterIndex < (string as NSString).length else { return nil }
      return NoteLinkParser.link(atUTF16Location: characterIndex, in: string)?.targetNoteID
    }

    override func mouseDown(with event: NSEvent) {
      cancelPasteOptions()
      guard let layoutManager, let textContainer else {
        super.mouseDown(with: event)
        return
      }

      let point = convert(event.locationInWindow, from: nil)
      let textPoint = NSPoint(
        x: point.x - textContainerOrigin.x,
        y: point.y - textContainerOrigin.y
      )
      guard layoutManager.numberOfGlyphs > 0 else {
        super.mouseDown(with: event)
        return
      }

      let glyphPoint = NSPoint(
        x: max(0, textPoint.x),
        y: max(0, textPoint.y)
      )
      let glyphIndex = layoutManager.glyphIndex(for: glyphPoint, in: textContainer)
      guard glyphIndex < layoutManager.numberOfGlyphs else {
        super.mouseDown(with: event)
        return
      }
      let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
      let ns = string as NSString
      guard characterIndex < ns.length else {
        super.mouseDown(with: event)
        return
      }

      if event.modifierFlags.contains(.command),
        let targetNoteID = noteLinkTarget(atViewPoint: point)
      {
        if liveNoteIDs.contains(targetNoteID) {
          onOpenNoteLink?(targetNoteID)
        } else {
          onUnavailableNoteLink?()
        }
        return
      }

      let paragraphRange = ns.paragraphRange(
        for: NSRange(location: characterIndex, length: 0)
      )
      guard let item = checklistItem(in: paragraphRange, string: ns) else {
        super.mouseDown(with: event)
        return
      }

      guard checklistHitRect(for: item.markerRange)?.contains(point) == true else {
        super.mouseDown(with: event)
        return
      }

      _ = toggleChecklist(
        markerRange: item.markerRange,
        contentLength: item.contentRange.length,
        currentlyCompleted: item.completed
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
      let originalParagraph = original.trimmingCharacters(in: .newlines)
      let isSingleEmptyListRemoval =
        (replacement.isEmpty || replacement == "\n")
        && (original == originalParagraph || original == originalParagraph + "\n")
        && EditorListEngine.parse(originalParagraph)?.content.isEmpty == true
      let selection: NSRange
      if original.isEmpty || original == "\n" {
        let offset = replacement.hasSuffix("\n")
          ? replacement.utf16.count - 1
          : replacement.utf16.count
        selection = NSRange(location: range.location + offset, length: 0)
      } else if isSingleEmptyListRemoval {
        selection = NSRange(location: range.location, length: 0)
      } else {
        selection = replacementRange
      }
      let attributed = attributedListReplacement(in: range, with: replacement)
      _ = replaceAttributedText(
        in: range,
        with: attributed,
        selecting: selection
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
        showChecklistCompletionAnimation(
          for: markerRange,
          contentLength: contentLength
        )
      } else {
        removeChecklistCompletionOverlay()
      }
      return true
    }

    private func checklistItems(in dirtyRect: NSRect? = nil) -> [ChecklistItem] {
      let ns = string as NSString
      guard ns.length > 0 else { return [] }
      let characterRange: NSRange
      if let dirtyRect {
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
        characterRange = layoutManager.characterRange(
          forGlyphRange: glyphRange,
          actualGlyphRange: nil
        )
      } else {
        characterRange = NSRange(location: 0, length: ns.length)
      }

      var location = min(characterRange.location, ns.length)
      let end = min(ns.length, NSMaxRange(characterRange))
      var items: [ChecklistItem] = []
      while location < end {
        let paragraphRange = ns.paragraphRange(
          for: NSRange(location: location, length: 0)
        )
        if let item = checklistItem(in: paragraphRange, string: ns) { items.append(item) }
        let nextLocation = NSMaxRange(paragraphRange)
        guard nextLocation > location else { break }
        location = nextLocation
      }
      return items
    }

    private func emptyListMarkerRanges() -> [NSRange] {
      let ns = string as NSString
      guard ns.length > 0 else { return [] }
      var location = 0
      var ranges: [NSRange] = []
      while location < ns.length {
        let paragraphRange = ns.paragraphRange(
          for: NSRange(location: location, length: 0)
        )
        if let item = parsedListItem(in: paragraphRange, string: ns),
          item.parsed.content.isEmpty
        {
          switch item.parsed.style {
          case .bullet, .number:
            ranges.append(item.markerRange)
          case .checklist:
            break
          }
        }
        let nextLocation = NSMaxRange(paragraphRange)
        guard nextLocation > location else { break }
        location = nextLocation
      }
      return ranges
    }

    private func checklistItem(in paragraphRange: NSRange, string ns: NSString) -> ChecklistItem? {
      guard let item = parsedListItem(in: paragraphRange, string: ns),
        item.parsed.style == .checklist
      else {
        return nil
      }
      return ChecklistItem(
        markerRange: item.markerRange,
        contentRange: item.contentRange,
        completed: item.parsed.isChecklistComplete
      )
    }

    private func parsedListItem(in paragraphRange: NSRange, string ns: NSString) -> (
      markerRange: NSRange,
      contentRange: NSRange,
      parsed: ParsedEditorListLine
    )? {
      let paragraph = ns.substring(with: paragraphRange).trimmingCharacters(in: .newlines)
      guard let parsed = EditorListEngine.parse(paragraph) else { return nil }
      let markerStart = parsed.depth * 4
      guard markerStart < paragraph.utf16.count else { return nil }
      let remainder = paragraph.dropFirst(markerStart)
      guard let separator = remainder.firstIndex(of: " ") else { return nil }
      let markerLength = remainder[..<separator].utf16.count
      let markerRange = NSRange(
        location: paragraphRange.location + markerStart,
        length: markerLength
      )
      return (
        markerRange: markerRange,
        contentRange: NSRange(
          location: NSMaxRange(markerRange) + 1,
          length: parsed.content.utf16.count
        ),
        parsed: parsed
      )
    }

    private func rangesExcluding(
      _ range: NSRange,
      ranges excludedRanges: [NSRange]
    ) -> [NSRange] {
      let end = NSMaxRange(range)
      var location = range.location
      var result: [NSRange] = []
      for excluded in excludedRanges.sorted(by: { $0.location < $1.location }) {
        guard excluded.location < end else { break }
        let overlapStart = max(location, excluded.location)
        let overlapEnd = min(end, NSMaxRange(excluded))
        guard overlapEnd > location else { continue }
        if overlapStart > location {
          result.append(NSRange(location: location, length: overlapStart - location))
        }
        location = overlapEnd
        if location == end { break }
      }
      if location < end {
        result.append(NSRange(location: location, length: end - location))
      }
      return result
    }

    private func applyChecklistRecession(
      in range: NSRange,
      storage: NSTextStorage,
      layoutManager: NSLayoutManager
    ) {
      guard range.length > 0 else { return }
      storage.enumerateAttribute(.foregroundColor, in: range) { value, subrange, _ in
        let effectiveColor = (
          layoutManager.temporaryAttribute(
            .foregroundColor,
            atCharacterIndex: subrange.location,
            effectiveRange: nil
          ) as? NSColor
        ) ?? (value as? NSColor) ?? .textColor
        let recessionColor = effectiveColor.withAlphaComponent(
          effectiveColor.alphaComponent * 0.72
        )
        layoutManager.addTemporaryAttribute(
          .foregroundColor,
          value: recessionColor,
          forCharacterRange: subrange
        )
        layoutManager.addTemporaryAttribute(
          .strikethroughColor,
          value: recessionColor,
          forCharacterRange: subrange
        )
      }
    }

    private func effectiveForegroundColor(
      at location: Int,
      storage: NSTextStorage,
      layoutManager: NSLayoutManager
    ) -> NSColor {
      (layoutManager.temporaryAttribute(
        .foregroundColor,
        atCharacterIndex: location,
        effectiveRange: nil
      ) as? NSColor)
        ?? (storage.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor)
        ?? .textColor
    }

    private func updateHoveredChecklistMarker(at point: NSPoint?) {
      let hovered = point.flatMap { point -> NSRange? in
        guard let layoutManager, let textContainer, layoutManager.numberOfGlyphs > 0 else {
          return nil
        }
        let textPoint = NSPoint(
          x: max(0, point.x - textContainerOrigin.x),
          y: max(0, point.y - textContainerOrigin.y)
        )
        let glyphIndex = layoutManager.glyphIndex(for: textPoint, in: textContainer)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        let ns = string as NSString
        guard characterIndex < ns.length,
          let item = checklistItem(
            in: ns.paragraphRange(for: NSRange(location: characterIndex, length: 0)),
            string: ns
          ),
          checklistHitRect(for: item.markerRange)?.contains(point) == true
        else { return nil }
        return item.markerRange
      }
      guard hovered != hoveredChecklistMarkerRange else { return }
      hoveredChecklistMarkerRange = hovered
      needsDisplay = true
    }

    private func registerStrikethroughUndo(enabled: Bool, range: NSRange) {
      undoManager?.registerUndo(withTarget: self) { target in
        target.registerStrikethroughUndo(enabled: !enabled, range: range)
        target.removeChecklistCompletionOverlay()
        target.clearChecklistPresentation()
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
