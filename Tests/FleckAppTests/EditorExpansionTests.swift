import AppKit
import FleckCore
import SwiftUI
import Testing

@testable import FleckApp

@MainActor
private func expansionEditor(_ string: String) -> (NSWindow, ListAwareTextView, EditorCommands) {
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 480, height: 240),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  let textView = ListAwareTextView(frame: window.contentView?.bounds ?? .zero)
  window.contentView = textView
  textView.isEditable = true
  textView.isSelectable = true
  textView.allowsUndo = true
  textView.string = string
  let commands = EditorCommands()
  commands.configureBodyDefaults(family: ".AppleSystemUIFont", size: 16)
  commands.textView = textView
  return (window, textView, commands)
}

@MainActor
private func expansionDescendant<T: NSView>(in view: NSView, as type: T.Type) -> T? {
  if let match = view as? T { return match }
  for child in view.subviews {
    if let match = expansionDescendant(in: child, as: type) { return match }
  }
  return nil
}

private final class RecordingFinderTextView: NSTextView {
  var finderActionTags: [Int] = []

  override func performTextFinderAction(_ sender: Any?) {
    finderActionTags.append((sender as? NSMenuItem)?.tag ?? -1)
  }
}

@Test @MainActor func reviewWebLinkTargetRejectsSwitchAwayAndBack() throws {
  let (window, textView, commands) = expansionEditor("Selected")
  defer { withExtendedLifetime(window) {} }
  textView.setSelectedRange(NSRange(location: 0, length: 8))
  let note = Note(title: "Note", body: "Selected", revision: 4)
  let target = try #require(EditorWebLinkTarget(note: note, commands: commands))
  let other = ListAwareTextView(frame: .zero)
  commands.textView = other
  commands.textView = textView
  #expect(!target.isValid(note: note, isEditorVisible: true, commands: commands))
}

@Test @MainActor func reviewSentenceCaseRecognizesUnicodeSentenceTerminators() {
  let (window, textView, commands) = expansionEditor("hello。WORLD！next？LAST")
  defer { withExtendedLifetime(window) {} }
  textView.setSelectedRange(NSRange(location: 0, length: textView.string.utf16.count))
  #expect(commands.transformCase(.sentence))
  #expect(textView.string == "Hello。World！Next？Last")
}

@Test @MainActor func reviewCaseConversionPreservesAttributesWithinComposedCharacters() throws {
  let (window, textView, commands) = expansionEditor("e\u{301}x")
  defer { withExtendedLifetime(window) {} }
  let link = try #require(URL(string: "https://example.com/accent"))
  textView.textStorage?.addAttribute(.link, value: link, range: NSRange(location: 1, length: 1))
  textView.textStorage?.addAttribute(.underlineStyle, value: 1, range: NSRange(location: 1, length: 1))
  textView.setSelectedRange(NSRange(location: 0, length: 3))
  #expect(commands.transformCase(.uppercase))
  #expect(textView.string == "E\u{301}X")
  #expect(textView.textStorage?.attribute(.link, at: 1, effectiveRange: nil) as? URL == link)
  #expect(textView.textStorage?.attribute(.underlineStyle, at: 1, effectiveRange: nil) as? Int == 1)
}

@Test @MainActor func reviewEveryPresetRemainsVisuallyRecognizableAfterRTFAtDefaultSize() throws {
  for style in EditorTextStyle.allCases {
    let (window, textView, commands) = expansionEditor("Preset")
    defer { withExtendedLifetime(window) {} }
    commands.configureBodyDefaults(family: ".AppleSystemUIFont", size: 17)
    textView.setSelectedRange(NSRange(location: 0, length: 6))
    #expect(commands.applyTextStyle(style))
    let source = try #require(textView.textStorage)
    let data = try source.data(
      from: NSRange(location: 0, length: source.length),
      documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
    )
    let restored = try NSAttributedString(
      data: data,
      options: [.documentType: NSAttributedString.DocumentType.rtf],
      documentAttributes: nil
    )
    source.setAttributedString(restored)
    textView.setSelectedRange(NSRange(location: 0, length: 6))
    commands.refreshFormattingState()
    #expect(commands.currentTextStyle == style)
  }
}

@Test func reviewToolbarIndentNeverInfersManualStyleFromDepth() {
  #expect(EditorListEngine.indentPreservingStyle(
    "        i. Manual Roman", removing: false, preferredNumberStyle: .roman
  ) == "            i. Manual Roman")
  #expect(EditorListEngine.indentPreservingStyle(
    "1. Manual Decimal", removing: false, preferredNumberStyle: .decimal
  ) == "    1. Manual Decimal")
  #expect(EditorListEngine.indentPreservingStyle(
    "    ◦ Manual Circle", removing: false
  ) == "        ◦ Manual Circle")
}

@Test @MainActor func reviewTitleUndoStillRoutesToItsActiveUndoManager() throws {
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 480, height: 240),
    styleMask: [.titled], backing: .buffered, defer: false
  )
  let title = NSTextField(string: "Title")
  let body = ListAwareTextView(frame: .zero)
  body.string = "Body"
  let document = NativeEditorDocumentView(titleField: title, textView: body)
  window.contentView = document
  let commands = EditorCommands()
  commands.textView = body
  #expect(window.makeFirstResponder(title))
  #expect(commands.isTitleEditing)
  let editor = try #require(title.currentEditor())
  let manager = try #require(commands.activeUndoManager)
  manager.groupsByEvent = false
  manager.beginUndoGrouping()
  manager.registerUndo(withTarget: editor) { editor in editor.string = "Restored" }
  manager.endUndoGrouping()
  #expect(manager.canUndo)
  commands.undo()
  #expect(editor.string == "Restored")
}

@Test @MainActor func webLinkTargetCancellationAndBlockingArePermanentlyInvalidating() throws {
  let (window, textView, commands) = expansionEditor("Selected")
  defer { withExtendedLifetime(window) {} }
  textView.setSelectedRange(NSRange(location: 0, length: 8))
  let note = Note(title: "Note", body: "Selected", revision: 4)
  let cancelled = try #require(EditorWebLinkTarget(note: note, commands: commands))
  cancelled.cancel()
  #expect(!cancelled.isValid(note: note, isEditorVisible: true, commands: commands))

  let blocked = try #require(EditorWebLinkTarget(note: note, commands: commands))
  commands.areBodyCommandsBlocked = true
  commands.areBodyCommandsBlocked = false
  #expect(!blocked.isValid(note: note, isEditorVisible: true, commands: commands))

  let noteSwitch = try #require(EditorWebLinkTarget(note: note, commands: commands))
  commands.invalidateEditorSession()
  #expect(!noteSwitch.isValid(note: note, isEditorVisible: true, commands: commands))

  let titleFocus = try #require(EditorWebLinkTarget(note: note, commands: commands))
  commands.isBodyCommandContextBlocked = true
  commands.isBodyCommandContextBlocked = false
  #expect(!titleFocus.isValid(note: note, isEditorVisible: true, commands: commands))
}

@Test @MainActor func noteLinkPermitRequiresOneValidatedPickerGenerationAndIsSingleUse() throws {
  func prepareValidatedTarget(
    textView: ListAwareTextView,
    commands: EditorCommands,
    note: Note
  ) throws -> EditorNoteLinkTarget {
    textView.setSelectedRange(NSRange(location: 0, length: 8))
    let target = try #require(
      EditorNoteLinkTarget(
        note: note,
        range: textView.selectedRange(),
        commands: commands
      )
    )
    commands.areBodyCommandsBlocked = true
    textView.isEditable = false
    textView.isSelectable = false
    #expect(target.capturePickerBlock(commands: commands))
    #expect(target.isValidAfterPickerDismissal(
      note: note,
      isEditorVisible: true,
      commands: commands
    ))
    commands.areBodyCommandsBlocked = false
    textView.isEditable = true
    textView.isSelectable = true
    return target
  }

  do {
    let (window, textView, commands) = expansionEditor("Selected")
    defer { withExtendedLifetime(window) {} }
    let note = Note(title: "Note", body: "Selected", revision: 7)
    let target = try #require(EditorNoteLinkTarget(
      note: note,
      range: NSRange(location: 0, length: 8),
      commands: commands
    ))
    #expect(!target.apply(label: "Bypass", targetNoteID: UUID(), commands: commands))
    commands.areBodyCommandsBlocked = true
    #expect(!target.capturePickerBlock(commands: commands))
    #expect(textView.string == "Selected")
  }

  do {
    let (window, textView, commands) = expansionEditor("Selected")
    defer { withExtendedLifetime(window) {} }
    let note = Note(title: "Note", body: "Selected", revision: 7)
    let target = try prepareValidatedTarget(textView: textView, commands: commands, note: note)
    commands.invalidateEditorSession()
    #expect(!target.apply(label: "Invalidated", targetNoteID: UUID(), commands: commands))
    #expect(textView.string == "Selected")
  }

  do {
    let (window, textView, commands) = expansionEditor("Selected")
    defer { withExtendedLifetime(window) {} }
    let note = Note(title: "Note", body: "Selected", revision: 7)
    let target = try prepareValidatedTarget(textView: textView, commands: commands, note: note)
    commands.areBodyCommandsBlocked = true
    commands.areBodyCommandsBlocked = false
    #expect(!target.apply(label: "Extra", targetNoteID: UUID(), commands: commands))
    #expect(textView.string == "Selected")
  }

  do {
    let (window, textView, commands) = expansionEditor("Selected")
    defer { withExtendedLifetime(window) {} }
    let note = Note(title: "Note", body: "Selected", revision: 7)
    let target = try prepareValidatedTarget(textView: textView, commands: commands, note: note)
    textView.isEditable = false
    #expect(!target.apply(label: "First", targetNoteID: UUID(), commands: commands))
    textView.isEditable = true
    #expect(!target.apply(label: "Second", targetNoteID: UUID(), commands: commands))
    #expect(textView.string == "Selected")
  }

  do {
    let (window, textView, commands) = expansionEditor("Selected")
    defer { withExtendedLifetime(window) {} }
    let note = Note(title: "Note", body: "Selected", revision: 7)
    textView.setSelectedRange(NSRange(location: 0, length: 8))
    let target = try #require(EditorNoteLinkTarget(
      note: note,
      range: textView.selectedRange(),
      commands: commands
    ))
    commands.areBodyCommandsBlocked = true
    textView.isEditable = false
    textView.isSelectable = false
    #expect(target.capturePickerBlock(commands: commands))
    var revised = note
    revised.revision += 1
    #expect(!target.isValidAfterPickerDismissal(
      note: revised,
      isEditorVisible: true,
      commands: commands
    ))
    commands.areBodyCommandsBlocked = false
    textView.isEditable = true
    textView.isSelectable = true
    #expect(!target.apply(label: "Stale", targetNoteID: UUID(), commands: commands))
    #expect(textView.string == "Selected")
  }

  do {
    let (window, textView, commands) = expansionEditor("Selected")
    defer { withExtendedLifetime(window) {} }
    let note = Note(title: "Note", body: "Selected", revision: 7)
    let target = try prepareValidatedTarget(textView: textView, commands: commands, note: note)
    let targetNoteID = UUID()
    #expect(target.apply(label: "Linked", targetNoteID: targetNoteID, commands: commands))
    let once = textView.string
    #expect(!target.apply(label: "Again", targetNoteID: UUID(), commands: commands))
    #expect(textView.string == once)
    #expect(NoteLinkParser.links(in: once).first?.targetNoteID == targetNoteID)
  }
}

@Test @MainActor func editorHistoryAllowsTitleRedoButRejectsBlockedAndHiddenSessions() throws {
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 480, height: 240),
    styleMask: [.titled], backing: .buffered, defer: false
  )
  let title = NSTextField(string: "Title")
  let body = ListAwareTextView(frame: .zero)
  body.string = "Body"
  window.contentView = NativeEditorDocumentView(titleField: title, textView: body)
  let commands = EditorCommands()
  commands.textView = body
  #expect(window.makeFirstResponder(title))
  let editor = try #require(title.currentEditor() as? NSTextView)
  editor.selectAll(nil)
  editor.insertText("Changed", replacementRange: editor.selectedRange())
  let manager = try #require(commands.activeUndoManager)
  #expect(manager.canUndo)

  commands.undo()
  #expect(editor.string == "Title")
  #expect(manager.canRedo)
  commands.redo()
  #expect(editor.string == "Changed")

  commands.areBodyCommandsBlocked = true
  commands.undo()
  #expect(editor.string == "Changed")
  commands.areBodyCommandsBlocked = false
  commands.textView = nil
  commands.undo()
  #expect(editor.string == "Changed")
}

@Test @MainActor func paragraphCommandsExcludeParagraphAtSelectionEndAndHandleTrailingEmptyParagraph() throws {
  let (_, textView, commands) = expansionEditor("First\nSecond\n")
  textView.setSelectedRange(NSRange(location: 0, length: 6))

  #expect(commands.applyAlignment(.center))
  #expect(
    (textView.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
      as? NSParagraphStyle)?.alignment == .center
  )
  #expect(
    (textView.textStorage?.attribute(.paragraphStyle, at: 6, effectiveRange: nil)
      as? NSParagraphStyle)?.alignment != .center
  )

  textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
  #expect(commands.applyParagraphSpacingAfter(18))
  #expect(
    (textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.paragraphSpacing == 18
  )

  for terminator in ["\r\n", "\r", "\u{2029}"] {
    let source = "Item" + terminator
    let (_, trailingView, trailingCommands) = expansionEditor(source)
    let original = NSAttributedString(attributedString: try #require(trailingView.textStorage))
    trailingView.setSelectedRange(NSRange(location: source.utf16.count, length: 0))
    #expect(trailingCommands.applyAlignment(.right))
    #expect(trailingCommands.applyTextStyle(.heading2))
    #expect(trailingCommands.increaseIndent())
    #expect(trailingView.attributedString().isEqual(to: original))
    let typingStyle = trailingView.typingAttributes[.paragraphStyle] as? NSParagraphStyle
    #expect(typingStyle?.alignment == .right)
    #expect(typingStyle?.headIndent == 24)
    #expect((trailingView.typingAttributes[.font] as? NSFont)?.pointSize == 24)
  }
}

@Test @MainActor func emptyBodyStylesAndParagraphControlsUpdateTypingAttributesOnly() throws {
  let (_, textView, commands) = expansionEditor("")
  textView.setSelectedRange(NSRange(location: 0, length: 0))
  #expect(commands.applyTextStyle(.code))
  #expect(commands.applyAlignment(.right))
  #expect(commands.applyLineSpacing(.double))
  #expect(textView.string.isEmpty)
  let font = try #require(textView.typingAttributes[.font] as? NSFont)
  let paragraph = try #require(textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle)
  #expect(font.fontDescriptor.symbolicTraits.contains(.monoSpace))
  #expect(paragraph.alignment == .right)
  #expect(paragraph.lineHeightMultiple == 2)
}

@Test @MainActor func paragraphSpacingControlsClampToDocumentedBoundsAndRejectNonfiniteValues() throws {
  let (_, textView, commands) = expansionEditor("Bounds")
  textView.setSelectedRange(NSRange(location: 0, length: 6))
  #expect(commands.applyParagraphSpacingBefore(-6))
  #expect(commands.applyParagraphSpacingAfter(42))
  let paragraph = try #require(textView.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
  #expect(paragraph.paragraphSpacingBefore == 0)
  #expect(paragraph.paragraphSpacing == 36)
  #expect(!commands.applyParagraphSpacingAfter(.nan))
}

@Test @MainActor func visualStylesPreserveLinksAndRoundTripConcreteAttributes() throws {
  let (_, textView, commands) = expansionEditor("Heading\nBody")
  let link = try #require(URL(string: "https://example.com/path"))
  textView.textStorage?.addAttribute(.link, value: link, range: NSRange(location: 0, length: 7))
  textView.setSelectedRange(NSRange(location: 0, length: 7))

  #expect(commands.applyTextStyle(.heading1))
  let font = try #require(textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
  #expect(font.pointSize == 28)
  #expect(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
  #expect(textView.textStorage?.attribute(.link, at: 0, effectiveRange: nil) as? URL == link)

  let data = try #require(try textView.textStorage?.data(
    from: NSRange(location: 0, length: textView.textStorage?.length ?? 0),
    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
  ))
  let restored = try NSAttributedString(
    data: data,
    options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: nil
  )
  let restoredFont = try #require(restored.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
  #expect(restoredFont.pointSize == 28)
  #expect(NSFontManager.shared.traits(of: restoredFont).contains(.boldFontMask))
  #expect(restored.attribute(.link, at: 0, effectiveRange: nil) as? URL == link)
}

@Test @MainActor func everyVisualStyleAppliesItsCentralizedFontAndParagraphPreset() throws {
  let expectations: [(EditorTextStyle, CGFloat, NSFontTraitMask, CGFloat, CGFloat)] = [
    (.normal, 16, [], 0, 0),
    (.heading1, 28, .boldFontMask, 12, 8),
    (.heading2, 24, .boldFontMask, 10, 6),
    (.heading3, 20, .boldFontMask, 8, 4),
    (.quote, 16, .italicFontMask, 6, 6),
    (.code, 16, [], 4, 4),
  ]
  for (style, size, trait, before, after) in expectations {
    let (_, textView, commands) = expansionEditor("Preset")
    textView.setSelectedRange(NSRange(location: 0, length: 6))
    #expect(commands.applyTextStyle(style))
    let font = try #require(textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
    let paragraph = try #require(textView.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
    #expect(font.pointSize == size)
    #expect(
      NSFontManager.shared.traits(of: font).intersection([.boldFontMask, .italicFontMask])
        == trait
    )
    #expect(paragraph.paragraphSpacingBefore == before)
    #expect(paragraph.paragraphSpacing == after)
    #expect(paragraph.minimumLineHeight >= font.pointSize)
    #expect(paragraph.maximumLineHeight == paragraph.minimumLineHeight)
    if style == .code {
      #expect(font.fontDescriptor.symbolicTraits.contains(.monoSpace))
    }
    #expect(commands.currentTextStyle == style)
  }
}

@Test @MainActor func paragraphSpacingLineSpacingAndBaselineSurviveRTFRoundTrip() throws {
  let (_, textView, commands) = expansionEditor("Round trip")
  textView.setSelectedRange(NSRange(location: 0, length: 10))
  #expect(commands.applyLineSpacing(.oneAndHalf))
  #expect(commands.applyParagraphSpacingBefore(12))
  #expect(commands.applyParagraphSpacingAfter(18))
  #expect(commands.setBaseline(.subscriptText))

  let data = try #require(try textView.textStorage?.data(
    from: NSRange(location: 0, length: 10),
    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
  ))
  let restored = try NSAttributedString(
    data: data,
    options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: nil
  )
  let paragraph = try #require(restored.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
  #expect(abs(paragraph.lineHeightMultiple - 1.5) < 0.01)
  #expect(paragraph.paragraphSpacingBefore == 12)
  #expect(paragraph.paragraphSpacing == 18)
  #expect(restored.attribute(.superscript, at: 0, effectiveRange: nil) as? Int == -1)
}

@Test @MainActor func paragraphAndBaselineMutationsAreSingleUndoSteps() throws {
  let (_, textView, commands) = expansionEditor("One\nTwo")
  textView.setSelectedRange(NSRange(location: 0, length: textView.string.utf16.count))
  let undoManager = try #require(textView.undoManager)
  let commandsUnderTest: [() -> Bool] = [
    { commands.applyLineSpacing(.oneAndHalf) },
    { commands.applyParagraphSpacingBefore(12) },
    { commands.applyParagraphSpacingAfter(18) },
    { commands.setBaseline(.superscript) },
  ]

  for apply in commandsUnderTest {
    undoManager.removeAllActions()
    let before = NSAttributedString(attributedString: try #require(textView.textStorage))
    let beforeSelection = textView.selectedRange()
    #expect(!undoManager.canUndo)
    #expect(!undoManager.canRedo)

    #expect(apply())
    let after = NSAttributedString(attributedString: try #require(textView.textStorage))
    let afterSelection = textView.selectedRange()
    #expect(!after.isEqual(to: before))
    #expect(afterSelection == beforeSelection)
    #expect(undoManager.canUndo)
    #expect(!undoManager.canRedo)

    undoManager.undo()
    #expect(try #require(textView.textStorage).isEqual(to: before))
    #expect(textView.selectedRange() == beforeSelection)
    #expect(!undoManager.canUndo)
    #expect(undoManager.canRedo)

    undoManager.redo()
    #expect(try #require(textView.textStorage).isEqual(to: after))
    #expect(textView.selectedRange() == afterSelection)
    #expect(undoManager.canUndo)
    #expect(!undoManager.canRedo)
  }
}

@Test @MainActor func clearAndPainterUseOnlyVisualAttributesAndInvalidateAcrossEditors() throws {
  let (_, source, commands) = expansionEditor("Source Target")
  let link = try #require(URL(string: "https://example.com"))
  source.textStorage?.addAttributes(
    [
      .font: NSFont.boldSystemFont(ofSize: 22),
      .foregroundColor: NSColor.systemRed,
      .backgroundColor: NSColor.systemYellow,
      .underlineStyle: NSUnderlineStyle.single.rawValue,
      .link: link,
    ],
    range: NSRange(location: 0, length: 6)
  )
  let semanticKey = NSAttributedString.Key("FleckSemanticFixture")
  source.textStorage?.addAttribute(semanticKey, value: "keep", range: NSRange(location: 7, length: 6))
  source.textStorage?.addAttribute(.link, value: link, range: NSRange(location: 7, length: 6))
  source.setSelectedRange(NSRange(location: 0, length: 6))

  #expect(commands.copyFormatting())
  #expect(commands.canPasteFormatting)
  source.setSelectedRange(NSRange(location: 7, length: 6))
  #expect(commands.pasteFormatting())
  #expect(source.textStorage?.attribute(.link, at: 7, effectiveRange: nil) as? URL == link)
  #expect(source.textStorage?.attribute(semanticKey, at: 7, effectiveRange: nil) as? String == "keep")
  #expect((source.textStorage?.attribute(.font, at: 7, effectiveRange: nil) as? NSFont)?.pointSize == 22)

  commands.cancelCopiedFormatting()
  #expect(!commands.canPasteFormatting)
  source.setSelectedRange(NSRange(location: 0, length: 6))
  #expect(commands.copyFormatting())

  source.setSelectedRange(NSRange(location: 7, length: 6))
  #expect(commands.clearTextFormatting())
  #expect(source.textStorage?.attribute(.link, at: 7, effectiveRange: nil) as? URL == link)
  #expect(source.textStorage?.attribute(semanticKey, at: 7, effectiveRange: nil) as? String == "keep")
  #expect((source.textStorage?.attribute(.font, at: 7, effectiveRange: nil) as? NSFont)?.pointSize == 16)
  #expect(source.textStorage?.attribute(.backgroundColor, at: 7, effectiveRange: nil) == nil)

  let other = ListAwareTextView(frame: .zero)
  other.string = "Other"
  commands.textView = other
  #expect(!commands.canPasteFormatting)
}

@Test @MainActor func newFormattingCommandsRejectReadonlyAndFocusedDictationTargets() {
  let (window, textView, commands) = expansionEditor("Body")
  defer { withExtendedLifetime(window) {} }
  textView.setSelectedRange(NSRange(location: 0, length: 4))
  textView.isEditable = false
  #expect(!commands.applyTextStyle(.quote))
  #expect(!commands.clearTextFormatting())

  textView.isEditable = true
  let beforeDictationGuard = NSAttributedString(attributedString: textView.attributedString())
  #expect(commands.beginFocusedDictation())
  #expect(!commands.applyAlignment(.right))
  #expect(!commands.transformCase(.uppercase))
  commands.toggleBold()
  #expect(textView.attributedString().isEqual(to: beforeDictationGuard))
  commands.cancelFocusedDictation()
  #expect(commands.applyAlignment(.right))
  let beforeBlockedCommands = NSAttributedString(attributedString: textView.attributedString())
  commands.areBodyCommandsBlocked = true
  #expect(!commands.applyParagraphSpacingAfter(12))
  commands.toggleBold()
  commands.toggleItalic()
  commands.toggleUnderline()
  commands.toggleStrikethrough()
  commands.applyFontFamily("Menlo")
  commands.applyForegroundColor(.systemRed)
  commands.applyBackgroundColor(.systemYellow)
  #expect(!commands.applyFontSize(24))
  commands.applyAutomaticList(.bullets)
  commands.applyList(.checklist)
  commands.undo()
  commands.redo()
  #expect(!commands.insertNoteLink(replacing: textView.selectedRange(), label: "X", targetNoteID: UUID()))
  #expect(textView.attributedString().isEqual(to: beforeBlockedCommands))
}

@Test @MainActor func newFormattingCommandsRejectTitleFieldFocus() throws {
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 480, height: 240),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  let title = NSTextField(string: "Title")
  let body = ListAwareTextView(frame: .zero)
  body.string = "Body"
  body.setSelectedRange(NSRange(location: 0, length: 4))
  let document = NativeEditorDocumentView(titleField: title, textView: body)
  window.contentView = document
  let commands = EditorCommands()
  commands.textView = body
  let beforeTitleGuard = NSAttributedString(attributedString: body.attributedString())

  #expect(window.makeFirstResponder(title))
  #expect(commands.isTitleEditing)
  #expect(!commands.applyAlignment(.center))
  #expect(!commands.clearTextFormatting())
  commands.toggleBold()
  commands.applyAutomaticList(.numbers)
  #expect(body.string == "Body")
  #expect(body.attributedString().isEqual(to: beforeTitleGuard))
}

@Test @MainActor func textStyleStateRequiresAllVisualPresetAttributesToMatch() {
  let (_, textView, commands) = expansionEditor("Heading")
  textView.setSelectedRange(NSRange(location: 0, length: 7))
  #expect(commands.applyTextStyle(.heading2))
  #expect(commands.currentTextStyle == .heading2)

  let custom = ((textView.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
    as? NSParagraphStyle) ?? .default).mutableCopy() as! NSMutableParagraphStyle
  custom.paragraphSpacing = 35
  textView.textStorage?.addAttribute(
    .paragraphStyle,
    value: custom,
    range: NSRange(location: 0, length: 7)
  )
  commands.refreshFormattingState()
  #expect(commands.currentTextStyle == nil)
}

@Test @MainActor func unicodeCaseExpansionPreservesRunsWebLinksAndNoteTargets() throws {
  let noteID = UUID()
  let token = NoteLinkFormatter.markdown(label: "straße", targetNoteID: noteID)
  let (_, textView, commands) = expansionEditor("aß i\u{307} \(token)")
  let webLink = try #require(URL(string: "https://example.com"))
  textView.textStorage?.addAttribute(.link, value: webLink, range: NSRange(location: 0, length: 2))
  textView.textStorage?.addAttribute(
    .foregroundColor,
    value: NSColor.systemPurple,
    range: NSRange(location: 3, length: 2)
  )
  let originalSelection = NSRange(location: 0, length: textView.string.utf16.count)
  textView.setSelectedRange(originalSelection)

  #expect(commands.transformCase(.uppercase))
  #expect(textView.string.hasPrefix("ASS I\u{307} "))
  let noteLink = try #require(NoteLinkParser.links(in: textView.string).first)
  #expect(noteLink.targetNoteID == noteID)
  #expect(noteLink.label == "STRASSE")
  #expect(textView.textStorage?.attribute(.link, at: 0, effectiveRange: nil) as? URL == webLink)
  #expect(textView.textStorage?.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? NSColor == .systemPurple)
  #expect(textView.selectedRange().location == 0)
  #expect(textView.selectedRange().length == textView.string.utf16.count)

  try #require(textView.undoManager).undo()
  #expect(textView.string == "aß i\u{307} \(token)")
  #expect(textView.selectedRange() == originalSelection)
  try #require(textView.undoManager).redo()
  #expect(textView.string.hasPrefix("ASS I\u{307} "))
}

@Test @MainActor func caseTransformNeverRewritesAPartialNoteLinkDestination() {
  let noteID = UUID()
  let token = NoteLinkFormatter.markdown(label: "Target", targetNoteID: noteID)
  let (_, textView, commands) = expansionEditor(token)
  let destination = NoteLinkParser.links(in: token)[0].destinationRange
  textView.setSelectedRange(NSRange(location: destination.location + 2, length: 8))
  #expect(!commands.transformCase(.uppercase))
  #expect(textView.string == token)
  #expect(NoteLinkParser.links(in: textView.string).first?.targetNoteID == noteID)
}

@Test @MainActor func caseTransformPreservesManualListMarkersAndRejectsCaret() {
  let (_, textView, commands) = expansionEditor("i. roman\nA plain")
  textView.setSelectedRange(NSRange(location: 0, length: textView.string.utf16.count))
  #expect(commands.transformCase(.uppercase))
  #expect(textView.string == "i. ROMAN\nA PLAIN")
  textView.setSelectedRange(NSRange(location: 0, length: 0))
  #expect(!commands.transformCase(.lowercase))
}

@Test @MainActor func everyCaseModeProtectsUnavailableCanonicalImageReferences() throws {
  let reference = "![MiXeD Alt](file:///definitely/missing/MiXeD%20Folder/PhotoABC.PNG)"
  let cases: [(String, EditorTextCase, String)] = [
    ("before \(reference) after", .uppercase, "BEFORE \(reference) AFTER"),
    ("BEFORE \(reference) AFTER", .lowercase, "before \(reference) after"),
    ("hELLO. \(reference) wORLD", .sentence, "Hello. \(reference) World"),
  ]

  for (source, mode, expected) in cases {
    let (window, textView, commands) = expansionEditor(source)
    defer { withExtendedLifetime(window) {} }
    textView.setSelectedRange(NSRange(location: 0, length: source.utf16.count))
    #expect(commands.transformCase(mode))
    #expect(textView.string == expected)

    let data = try #require(try textView.textStorage?.data(
      from: NSRange(location: 0, length: textView.string.utf16.count),
      documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
    ))
    let restored = try NSAttributedString(
      data: data,
      options: [.documentType: NSAttributedString.DocumentType.rtf],
      documentAttributes: nil
    )
    #expect(restored.string == expected)
    #expect(restored.string.contains(reference))
  }

  for mode in EditorTextCase.allCases {
    let (window, textView, commands) = expansionEditor(reference)
    defer { withExtendedLifetime(window) {} }
    let partial = (reference as NSString).range(of: "PhotoABC")
    textView.setSelectedRange(NSRange(location: partial.location + 1, length: 5))
    let original = NSAttributedString(attributedString: try #require(textView.textStorage))
    let undoManager = try #require(textView.undoManager)
    undoManager.removeAllActions()
    #expect(!commands.transformCase(mode))
    #expect(try #require(textView.textStorage).isEqual(to: original))
    #expect(!undoManager.canUndo)
  }
}

@Test @MainActor func lowercaseUsesContextualUnicodeAndExpandsComposedSelectionSafely() {
  let (_, textView, commands) = expansionEditor("ΟΣ e\u{301}X")
  textView.setSelectedRange(NSRange(location: 0, length: 2))
  #expect(commands.transformCase(.lowercase))
  #expect(textView.string == "ος e\u{301}X")

  textView.setSelectedRange(NSRange(location: 4, length: 1))
  #expect(commands.transformCase(.uppercase))
  #expect(textView.string == "ος E\u{301}X")
  #expect(textView.selectedRange() == NSRange(location: 3, length: 2))
}

@Test @MainActor func sentenceCaseCapitalizesEachUnicodeSentenceAndPreservesPunctuation() {
  let (_, textView, commands) = expansionEditor("hELLO. über! ßETA? τέλος。中文 lAST")
  textView.setSelectedRange(NSRange(location: 0, length: textView.string.utf16.count))
  #expect(commands.transformCase(.sentence))
  #expect(textView.string == "Hello. Über! SSeta? Τέλος。中文 Last")
}

@Test @MainActor func lowercaseExpansionPreservesScalarRunAttributesAndUndoSelection() throws {
  let (window, textView, commands) = expansionEditor("İX")
  defer { withExtendedLifetime(window) {} }
  let link = try #require(URL(string: "https://example.com/dotted-i"))
  textView.textStorage?.addAttribute(.link, value: link, range: NSRange(location: 0, length: 1))
  let original = NSAttributedString(attributedString: try #require(textView.textStorage))
  textView.setSelectedRange(NSRange(location: 0, length: 2))

  #expect(commands.transformCase(.lowercase))
  #expect(textView.string == "i\u{307}x")
  #expect(textView.textStorage?.attribute(.link, at: 0, effectiveRange: nil) as? URL == link)
  #expect(textView.textStorage?.attribute(.link, at: 1, effectiveRange: nil) as? URL == link)
  #expect(textView.selectedRange() == NSRange(location: 0, length: 3))

  try #require(textView.undoManager).undo()
  #expect(textView.attributedString().isEqual(to: original))
  #expect(textView.selectedRange() == NSRange(location: 0, length: 2))
  try #require(textView.undoManager).redo()
  #expect(textView.string == "i\u{307}x")
  #expect(textView.selectedRange() == NSRange(location: 0, length: 3))
}

@Test @MainActor func defaultUnicodeCaseMappingPreservesScalarProvenanceAndUndo() throws {
  let originKey = NSAttributedString.Key("SyntheticCaseOrigin")
  func tagged(_ string: String) -> NSAttributedString {
    let result = NSMutableAttributedString(string: string)
    for location in 0..<result.length {
      result.addAttribute(originKey, value: location, range: NSRange(location: location, length: 1))
    }
    return result
  }
  func origins(_ string: NSAttributedString) -> [Int] {
    (0..<string.length).map {
      string.attribute(originKey, at: $0, effectiveRange: nil) as? Int ?? -1
    }
  }

  let cases: [(String, EditorTextCase, String, [Int])] = [
    ("i\u{307}\u{301}x", .uppercase, "I\u{307}\u{301}X", [0, 1, 2, 3]),
    ("I\u{301}X", .lowercase, "i\u{301}x", [0, 1, 2]),
    ("I\u{301}\u{301}X", .lowercase, "i\u{301}\u{301}x", [0, 1, 2, 3]),
    ("I\u{307}\u{301}X", .lowercase, "i\u{307}\u{301}x", [0, 1, 2, 3]),
    ("I\u{307}X", .lowercase, "i\u{307}x", [0, 1, 2]),
    ("I\u{307}i", .lowercase, "i\u{307}i", [0, 1, 2]),
    (
      "I\u{307}\u{301}I\u{307}\u{301}", .lowercase,
      "i\u{307}\u{301}i\u{307}\u{301}", [0, 1, 2, 3, 4, 5]
    ),
    ("I\u{307}iI\u{307}i", .lowercase, "i\u{307}ii\u{307}i", [0, 1, 2, 3, 4, 5]),
    (
      "I\u{307}i I\u{307}i", .lowercase,
      "i\u{307}i i\u{307}i", [0, 1, 2, 3, 4, 5, 6]
    ),
    ("I\u{345}\u{301}", .lowercase, "i\u{345}\u{301}", [0, 1, 2]),
    (
      "I\u{345}\u{301}I\u{345}\u{301}", .lowercase,
      "i\u{345}\u{301}i\u{345}\u{301}", [0, 1, 2, 3, 4, 5]
    ),
    ("I\u{345}\u{307}i", .lowercase, "i\u{345}\u{307}i", [0, 1, 2, 3]),
    ("ΟΣ", .lowercase, "ος", [0, 1]),
    ("α\u{301}υη\u{301}", .uppercase, "Α\u{301}ΥΗ\u{301}", [0, 1, 2, 3, 4]),
    ("ι\u{301}\u{308}\u{301}X", .uppercase, "Ι\u{301}\u{308}\u{301}X", [0, 1, 2, 3, 4]),
    ("α\u{301}υ", .uppercase, "Α\u{301}Υ", [0, 1, 2]),
    ("ήηή", .uppercase, "ΉΗΉ", [0, 1, 2]),
    ("ßETA", .sentence, "SSeta", [0, 0, 1, 2, 3]),
    ("aß İ ﬃ", .uppercase, "ASS İ FFI", [0, 1, 1, 2, 3, 4, 5, 5, 5]),
    ("𐐀😄", .lowercase, "𐐨😄", [0, 0, 2, 2]),
  ]

  for (source, mode, expected, expectedOrigins) in cases {
    let transformed = EditorAttributedCaseTransformer.transform(
      tagged(source),
      mode: mode,
      protectedRanges: []
    )
    #expect(transformed.string == expected)
    #expect(origins(transformed) == expectedOrigins)

    let (window, textView, commands) = expansionEditor(source)
    defer { withExtendedLifetime(window) {} }
    textView.textStorage?.setAttributedString(tagged(source))
    textView.setSelectedRange(NSRange(location: 0, length: source.utf16.count))
    let original = NSAttributedString(attributedString: try #require(textView.textStorage))
    #expect(commands.transformCase(mode))
    #expect(textView.string == expected)
    #expect(textView.selectedRange() == NSRange(location: 0, length: expected.utf16.count))
    #expect(origins(textView.attributedString()) == expectedOrigins)
    try #require(textView.undoManager).undo()
    #expect(textView.attributedString().isEqual(to: original))
    #expect(textView.selectedRange() == NSRange(location: 0, length: source.utf16.count))
    try #require(textView.undoManager).redo()
    #expect(textView.string == expected)
    #expect(origins(textView.attributedString()) == expectedOrigins)
  }
}

@Test @MainActor func caseMappingInvariantFailureRejectsBeforeMutationOrUndo() throws {
  let originKey = NSAttributedString.Key("SyntheticRejectedCaseOrigin")
  let source = NSAttributedString(string: "ß", attributes: [originKey: 7])
  let rejected = EditorAttributedCaseTransformer.mappedOutput(
    "Z",
    source: source,
    sourceRange: NSRange(location: 0, length: source.length),
    operation: { _ in .uppercase }
  )
  #expect(rejected == nil)
  #expect(source.string == "ß")
  #expect(source.attribute(originKey, at: 0, effectiveRange: nil) as? Int == 7)

  let (window, textView, commands) = expansionEditor("Z")
  defer { withExtendedLifetime(window) {} }
  textView.textStorage?.addAttribute(originKey, value: 9, range: NSRange(location: 0, length: 1))
  textView.setSelectedRange(NSRange(location: 0, length: 1))
  let original = NSAttributedString(attributedString: try #require(textView.textStorage))
  let undoManager = try #require(textView.undoManager)
  undoManager.removeAllActions()
  #expect(!commands.transformCase(.uppercase))
  #expect(textView.attributedString().isEqual(to: original))
  #expect(textView.selectedRange() == NSRange(location: 0, length: 1))
  #expect(!undoManager.canUndo)
}

@Test @MainActor func defaultUnicodeRepeatedGreekLettersKeepDistinctVisualsAndLinks() throws {
  let (window, textView, commands) = expansionEditor("ήηή")
  defer { withExtendedLifetime(window) {} }
  let colors: [NSColor] = [.systemRed, .systemBlue, .systemGreen]
  let urls = (0..<3).map { URL(string: "https://example.com/origin/\($0)")! }
  for location in 0..<3 {
    textView.textStorage?.addAttributes(
      [
        .font: NSFont.systemFont(ofSize: CGFloat(16 + location)),
        .foregroundColor: colors[location],
        .link: urls[location],
      ],
      range: NSRange(location: location, length: 1)
    )
  }
  let source = NSAttributedString(attributedString: try #require(textView.textStorage))
  textView.setSelectedRange(NSRange(location: 0, length: 3))
  #expect(commands.transformCase(.uppercase))
  #expect(textView.string == "ΉΗΉ")
  #expect(textView.selectedRange() == NSRange(location: 0, length: 3))
  for location in 0..<3 {
    #expect(textView.textStorage?.attribute(.font, at: location, effectiveRange: nil) as? NSFont
      == source.attribute(.font, at: location, effectiveRange: nil) as? NSFont)
    #expect(textView.textStorage?.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
      == colors[location])
    #expect(textView.textStorage?.attribute(.link, at: location, effectiveRange: nil) as? URL
      == urls[location])
  }
  let changed = NSAttributedString(attributedString: try #require(textView.textStorage))
  let undoManager = try #require(textView.undoManager)
  undoManager.undo()
  #expect(textView.attributedString().isEqual(to: source))
  #expect(textView.selectedRange() == NSRange(location: 0, length: 3))
  undoManager.redo()
  #expect(textView.attributedString().isEqual(to: changed))
  #expect(textView.selectedRange() == NSRange(location: 0, length: 3))
}

@Test func defaultUnicodeCaseMappingHandlesDistributedGreekContextLinearly() {
  let source = String(repeating: "ΟΣ ", count: 10_000)
  let key = NSAttributedString.Key("SyntheticLongCaseRun")
  let attributed = NSAttributedString(string: source, attributes: [key: "preserved"])
  let result = EditorAttributedCaseTransformer.transform(
    attributed,
    mode: .lowercase,
    protectedRanges: []
  )
  #expect(result.length == source.utf16.count)
  #expect(result.string == String(repeating: "ος ", count: 10_000))
  #expect(result.attribute(key, at: 0, effectiveRange: nil) as? String == "preserved")
  #expect(result.attribute(key, at: result.length - 1, effectiveRange: nil) as? String == "preserved")
}

@Test @MainActor func legacyEmphasisStateReportsMixedSelectionsAndConvergesOnToggle() throws {
  let (window, textView, commands) = expansionEditor("AB")
  defer { withExtendedLifetime(window) {} }
  let manager = NSFontManager.shared
  let regular = NSFont.systemFont(ofSize: 17)
  let boldItalic = manager.convert(
    manager.convert(regular, toHaveTrait: .boldFontMask),
    toHaveTrait: .italicFontMask
  )
  textView.textStorage?.addAttribute(.font, value: regular, range: NSRange(location: 0, length: 1))
  textView.textStorage?.addAttribute(.font, value: boldItalic, range: NSRange(location: 1, length: 1))
  textView.textStorage?.addAttribute(.underlineStyle, value: 1, range: NSRange(location: 1, length: 1))
  textView.textStorage?.addAttribute(.strikethroughStyle, value: 1, range: NSRange(location: 1, length: 1))
  textView.setSelectedRange(NSRange(location: 0, length: 2))
  commands.refreshFormattingState()

  #expect(commands.isBoldMixed)
  #expect(commands.isItalicMixed)
  #expect(commands.isUnderlineMixed)
  #expect(commands.isStrikethroughMixed)
  #expect(!commands.isBold)
  #expect(!commands.isItalic)
  #expect(!commands.isUnderlined)
  #expect(!commands.isStrikethrough)

  commands.toggleBold()
  commands.toggleItalic()
  commands.toggleUnderline()
  commands.toggleStrikethrough()
  commands.refreshFormattingState()
  #expect(commands.isBold && !commands.isBoldMixed)
  #expect(commands.isItalic && !commands.isItalicMixed)
  #expect(commands.isUnderlined && !commands.isUnderlineMixed)
  #expect(commands.isStrikethrough && !commands.isStrikethroughMixed)
}

@Test @MainActor func caretStrikethroughToggleRefreshesCommandState() {
  let (_, textView, commands) = expansionEditor("Caret")
  textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
  commands.refreshFormattingState()
  #expect(!commands.isStrikethrough)
  #expect(!commands.isStrikethroughMixed)

  commands.toggleStrikethrough()
  #expect(
    textView.typingAttributes[.strikethroughStyle] as? Int
      == NSUnderlineStyle.single.rawValue
  )
  #expect(commands.isStrikethrough)
  #expect(!commands.isStrikethroughMixed)

  commands.toggleStrikethrough()
  #expect(textView.typingAttributes[.strikethroughStyle] as? Int == 0)
  #expect(!commands.isStrikethrough)
  #expect(!commands.isStrikethroughMixed)
}

@Test @MainActor func mixedParagraphIndentPreservesManualListFamiliesAndPlainTextBytes() throws {
  let (_, textView, commands) = expansionEditor("i. Roman\n▪ Square\n○ Done\nPlain")
  let romanParagraph = NSMutableParagraphStyle()
  romanParagraph.textLists = [NSTextList(markerFormat: .lowercaseRoman, options: 0)]
  textView.textStorage?.addAttribute(
    .paragraphStyle,
    value: romanParagraph,
    range: NSRange(location: 0, length: 9)
  )
  textView.textStorage?.addAttribute(
    .link,
    value: try #require(URL(string: "https://example.com")),
    range: NSRange(location: 3, length: 5)
  )
  let original = NSAttributedString(attributedString: try #require(textView.textStorage))
  textView.setSelectedRange(NSRange(location: 0, length: textView.string.utf16.count))

  #expect(commands.increaseIndent())
  #expect(textView.string == "    i. Roman\n    ▪ Square\n    ○ Done\nPlain")
  #expect(textView.textStorage?.attribute(.link, at: 7, effectiveRange: nil) as? URL == URL(string: "https://example.com"))
  let plainLocation = (textView.string as NSString).range(of: "Plain").location
  #expect(
    (textView.textStorage?.attribute(.paragraphStyle, at: plainLocation, effectiveRange: nil)
      as? NSParagraphStyle)?.headIndent == 24
  )

  try #require(textView.undoManager).undo()
  #expect(textView.string == "i. Roman\n▪ Square\n○ Done\nPlain")
  #expect(textView.textStorage?.attributedSubstring(from: NSRange(location: 0, length: original.length)) == original)
}

@Test @MainActor func toolbarListIndentPreservesLiteralBytesAcrossUndoRedo() throws {
  let cases = [
    ("7) Seven", "    7) Seven"),
    ("iv. Four", "    iv. Four"),
    ("c. Alpha", "    c. Alpha"),
    ("- [x] Done", "    - [x] Done"),
    ("- [X] Done", "    - [X] Done"),
    ("- [ ] Open", "    - [ ] Open"),
    ("7) 七🙂 e\u{301}", "    7) 七🙂 e\u{301}"),
  ]

  for (source, expected) in cases {
    let (window, textView, commands) = expansionEditor(source)
    defer { withExtendedLifetime(window) {} }
    let original = NSAttributedString(attributedString: try #require(textView.textStorage))
    textView.setSelectedRange(NSRange(location: 0, length: source.utf16.count))
    #expect(commands.increaseIndent())
    #expect(textView.string == expected)
    #expect(textView.selectedRange() == NSRange(location: 0, length: expected.utf16.count))
    try #require(textView.undoManager).undo()
    #expect(textView.attributedString().isEqual(to: original))
    #expect(textView.selectedRange() == NSRange(location: 0, length: source.utf16.count))
    try #require(textView.undoManager).redo()
    #expect(textView.string == expected)
    #expect(commands.decreaseIndent())
    #expect(textView.attributedString().isEqual(to: original))
  }
}

@Test @MainActor func toolbarMixedIndentPreservesMetadataAndSelectionBoundary() throws {
  let source = "Adjacent\n7) Seven\niv. Römån🙂\nc. Alphabetic\nPlain Ω\nTrailing"
  let (window, textView, commands) = expansionEditor(source)
  defer { withExtendedLifetime(window) {} }
  let storage = try #require(textView.textStorage)
  let semanticKey = NSAttributedString.Key("SyntheticListSemantic")
  let ns = source as NSString
  let decimalRange = ns.lineRange(for: NSRange(location: ns.range(of: "7)").location, length: 0))
  let romanRange = ns.lineRange(for: NSRange(location: ns.range(of: "iv.").location, length: 0))
  let alphaRange = ns.lineRange(for: NSRange(location: ns.range(of: "c.").location, length: 0))
  let plainRange = ns.lineRange(for: NSRange(location: ns.range(of: "Plain").location, length: 0))
  for (range, marker, tag) in [
    (decimalRange, NSTextList.MarkerFormat.decimal, "decimal"),
    (romanRange, NSTextList.MarkerFormat.lowercaseRoman, "roman"),
    (alphaRange, NSTextList.MarkerFormat.lowercaseAlpha, "alpha"),
  ] {
    let style = NSMutableParagraphStyle()
    style.textLists = [NSTextList(markerFormat: marker, options: 0)]
    storage.addAttributes(
      [.paragraphStyle: style, semanticKey: tag],
      range: NSRange(location: range.location, length: range.length - 1)
    )
  }
  storage.addAttribute(
    semanticKey,
    value: "unicode",
    range: ns.range(of: "Römån🙂")
  )
  let original = NSAttributedString(attributedString: storage)
  let selection = NSRange(
    location: decimalRange.location,
    length: NSMaxRange(plainRange) - decimalRange.location
  )
  textView.setSelectedRange(selection)

  #expect(commands.increaseIndent())
  #expect(
    textView.string
      == "Adjacent\n    7) Seven\n    iv. Römån🙂\n    c. Alphabetic\nPlain Ω\nTrailing"
  )
  let changed = try #require(textView.textStorage)
  for (originalRange, addedOffset) in [
    (decimalRange, 4),
    (romanRange, 8),
    (alphaRange, 12),
  ] {
    let originalLine = original.attributedSubstring(
      from: NSRange(location: originalRange.location, length: originalRange.length - 1)
    )
    let changedLine = changed.attributedSubstring(
      from: NSRange(
        location: originalRange.location + addedOffset,
        length: originalRange.length - 1
      )
    )
    #expect(changedLine.isEqual(to: originalLine))
  }
  let plainStyle = changed.attribute(
    .paragraphStyle,
    at: plainRange.location + 12,
    effectiveRange: nil
  ) as? NSParagraphStyle
  #expect(plainStyle?.headIndent == 24)
  #expect(textView.string.hasPrefix("Adjacent\n"))
  #expect(textView.string.hasSuffix("\nTrailing"))

  try #require(textView.undoManager).undo()
  #expect(textView.attributedString().isEqual(to: original))
  #expect(textView.selectedRange() == selection)
  try #require(textView.undoManager).redo()
  #expect(textView.string.hasSuffix("Plain Ω\nTrailing"))
}

@Test @MainActor func toolbarListIndentPreservesNonLFParagraphTerminators() throws {
  let cases = [
    "7) One\r\n8) Two",
    "7) One\r8) Two",
    "7) One\u{2029}8) Two",
  ]
  let key = NSAttributedString.Key("SyntheticTerminatorOrigin")
  for source in cases {
    let (window, textView, commands) = expansionEditor(source)
    defer { withExtendedLifetime(window) {} }
    let storage = try #require(textView.textStorage)
    for location in 0..<storage.length {
      storage.addAttribute(key, value: location, range: NSRange(location: location, length: 1))
    }
    let original = NSAttributedString(attributedString: storage)
    textView.setSelectedRange(NSRange(location: 0, length: storage.length))
    #expect(commands.increaseIndent())

    let sourceNSString = source as NSString
    var secondStart = 0
    var firstEnd = 0
    sourceNSString.getParagraphStart(
      nil,
      end: &firstEnd,
      contentsEnd: nil,
      for: NSRange(location: 0, length: 0)
    )
    sourceNSString.getParagraphStart(
      &secondStart,
      end: nil,
      contentsEnd: nil,
      for: NSRange(location: firstEnd, length: 0)
    )
    let expected = NSMutableAttributedString(attributedString: original)
    for location in [secondStart, 0] {
      expected.insert(
        NSAttributedString(
          string: "    ",
          attributes: original.attributes(at: location, effectiveRange: nil)
        ),
        at: location
      )
    }
    #expect(textView.attributedString().isEqual(to: expected))
    try #require(textView.undoManager).undo()
    #expect(textView.attributedString().isEqual(to: original))
    try #require(textView.undoManager).redo()
    #expect(textView.attributedString().isEqual(to: expected))
  }

  let mixed = "7) One\r\nPlain Ω\r\n8) Two"
  let (window, textView, commands) = expansionEditor(mixed)
  defer { withExtendedLifetime(window) {} }
  textView.setSelectedRange(NSRange(location: 0, length: mixed.utf16.count))
  #expect(commands.increaseIndent())
  #expect(textView.string == "    7) One\r\nPlain Ω\r\n    8) Two")
  let plainLocation = (textView.string as NSString).range(of: "Plain Ω").location
  let plainStyle = textView.textStorage?.attribute(
    .paragraphStyle,
    at: plainLocation,
    effectiveRange: nil
  ) as? NSParagraphStyle
  #expect(plainStyle?.headIndent == 24)
}

@Test @MainActor func webLinkTargetRejectsRevisionAndVisibilityChanges() throws {
  let (_, textView, commands) = expansionEditor("Selected")
  textView.setSelectedRange(NSRange(location: 0, length: 8))
  let note = Note(title: "Note", body: "Selected", revision: 4)
  let target = try #require(EditorWebLinkTarget(note: note, commands: commands))
  var changed = note
  changed.revision = 5
  #expect(!target.apply(urlText: "https://example.com", displayText: nil, note: changed, isEditorVisible: true, commands: commands))
  #expect(!target.apply(urlText: "https://example.com", displayText: nil, note: note, isEditorVisible: false, commands: commands))
  #expect(textView.textStorage?.attribute(.link, at: 0, effectiveRange: nil) == nil)
}

@Test @MainActor func noteLinkTargetRequiresOnlyItsCapturedPickerTransition() throws {
  let note = Note(title: "Source", body: "[[", revision: 4)
  let (_, textView, commands) = expansionEditor("[[")
  let target = try #require(
    EditorNoteLinkTarget(
      note: note,
      range: NSRange(location: 0, length: 2),
      commands: commands
    )
  )
  commands.areBodyCommandsBlocked = true
  textView.isEditable = false
  textView.isSelectable = false
  #expect(target.capturePickerBlock(commands: commands))
  #expect(
    target.isValidAfterPickerDismissal(
      note: note,
      isEditorVisible: true,
      commands: commands
    )
  )

  commands.areBodyCommandsBlocked = false
  textView.isEditable = true
  textView.isSelectable = true
  let targetNoteID = UUID()
  #expect(target.apply(label: "Target", targetNoteID: targetNoteID, commands: commands))
  #expect(textView.string == NoteLinkFormatter.markdown(label: "Target", targetNoteID: targetNoteID))

  let (_, editedView, editedCommands) = expansionEditor("[[")
  let editedTarget = try #require(
    EditorNoteLinkTarget(
      note: note,
      range: NSRange(location: 0, length: 2),
      commands: editedCommands
    )
  )
  editedCommands.areBodyCommandsBlocked = true
  #expect(editedTarget.capturePickerBlock(commands: editedCommands))
  editedView.textStorage?.replaceCharacters(in: NSRange(location: 0, length: 1), with: "{")
  #expect(
    !editedTarget.isValidAfterPickerDismissal(
      note: note,
      isEditorVisible: true,
      commands: editedCommands
    )
  )

  let (_, switchedView, switchedCommands) = expansionEditor("[[")
  let switchedTarget = try #require(
    EditorNoteLinkTarget(
      note: note,
      range: NSRange(location: 0, length: 2),
      commands: switchedCommands
    )
  )
  switchedCommands.areBodyCommandsBlocked = true
  #expect(switchedTarget.capturePickerBlock(commands: switchedCommands))
  switchedCommands.textView = ListAwareTextView(frame: .zero)
  #expect(
    !switchedTarget.isValidAfterPickerDismissal(
      note: note,
      isEditorVisible: true,
      commands: switchedCommands
    )
  )
  withExtendedLifetime(switchedView) {}
}

@Test @MainActor func nativeEditorBuildsBodyFinderInsideItsOwningScrollView() throws {
  let commands = EditorCommands()
  let editor = NativeRichTextEditor(
    text: "Find body",
    richTextRTF: nil,
    onChange: { _, _ in },
    fontFamily: ".AppleSystemUIFont",
    fontSize: 17,
    textColorHex: nil,
    backgroundColorHex: nil,
    accentColorHex: "#FFD600",
    reduceMotion: true,
    automaticLists: true,
    commands: commands
  )
  let host = NSHostingView(rootView: editor.frame(width: 480, height: 240))
  host.frame = NSRect(x: 0, y: 0, width: 480, height: 240)
  let window = NSWindow(
    contentRect: host.frame,
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = host
  host.layoutSubtreeIfNeeded()
  let textView = try #require(expansionDescendant(in: host, as: ListAwareTextView.self))
  #expect(textView.usesFindBar)
  #expect(textView.enclosingScrollView != nil)
  #expect(commands.textView === textView)
  #expect(window.makeFirstResponder(textView))
}

@Test func webLinkValidationAcceptsOnlyAbsoluteHTTPURLsWithHosts() {
  #expect(EditorWebLink.validatedURL("https://example.com/path")?.absoluteString == "https://example.com/path")
  #expect(EditorWebLink.validatedURL("http://localhost:8080") != nil)
  #expect(EditorWebLink.validatedURL("https://[::1]/path") != nil)
  #expect(EditorWebLink.validatedURL("example.com") == nil)
  #expect(EditorWebLink.validatedURL("fleck://note/abc") == nil)
  #expect(EditorWebLink.validatedURL("https:///missing-host") == nil)
  #expect(EditorWebLink.validatedURL("https://exa mple.com") == nil)
  #expect(EditorWebLink.validatedURL("https://.") == nil)
  #expect(EditorWebLink.validatedURL("https://-invalid.example") == nil)
  #expect(EditorWebLink.validatedURL("https://invalid-.example") == nil)
  #expect(EditorWebLink.validatedURL("https://invalid_host.example") == nil)
  #expect(EditorWebLink.validatedURL("https://[::::]/") == nil)
  #expect(EditorWebLink.validatedURL("https://example.com/\u{0007}") == nil)
}

@Test @MainActor func webLinkTargetRejectsSelectionMovementEditsAndEditorSwitches() throws {
  let (_, textView, commands) = expansionEditor("Selected")
  textView.setSelectedRange(NSRange(location: 0, length: 8))
  let note = Note(title: "Note", body: "Selected", revision: 4)
  let target = try #require(EditorWebLinkTarget(note: note, commands: commands))
  textView.setSelectedRange(NSRange(location: 1, length: 0))
  #expect(!target.apply(urlText: "https://example.com", displayText: nil, note: note, isEditorVisible: true, commands: commands))

  textView.setSelectedRange(NSRange(location: 0, length: 8))
  let editedTarget = try #require(EditorWebLinkTarget(note: note, commands: commands))
  textView.insertText("Changed", replacementRange: NSRange(location: 0, length: 8))
  #expect(!editedTarget.apply(urlText: "https://example.com", displayText: nil, note: note, isEditorVisible: true, commands: commands))

  textView.string = "Selected"
  textView.setSelectedRange(NSRange(location: 0, length: 8))
  let switchedTarget = try #require(EditorWebLinkTarget(note: note, commands: commands))
  commands.textView = ListAwareTextView(frame: .zero)
  #expect(!switchedTarget.apply(urlText: "https://example.com", displayText: nil, note: note, isEditorVisible: true, commands: commands))
}

@Test @MainActor func webLinkInsertionEditingAndRemovalPreserveDisplayAttributes() async throws {
  let (window, textView, commands) = expansionEditor("Mixed")
  defer { withExtendedLifetime(window) {} }
  textView.textStorage?.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 19), range: NSRange(location: 0, length: 2))
  textView.setSelectedRange(NSRange(location: 0, length: 5))
  let note = Note(title: "Note", body: "Mixed", revision: 1)
  let target = try #require(EditorWebLinkTarget(note: note, commands: commands))

  #expect(target.apply(urlText: "https://example.com/one", displayText: nil, note: note, isEditorVisible: true, commands: commands))
  #expect(textView.textStorage?.attribute(.link, at: 0, effectiveRange: nil) as? URL == URL(string: "https://example.com/one"))
  #expect((textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 19)

  textView.setSelectedRange(NSRange(location: 1, length: 2))
  let edit = try #require(EditorWebLinkTarget(note: note, commands: commands))
  #expect(edit.existingURL == URL(string: "https://example.com/one"))
  #expect(edit.existingDisplayText == "Mixed")
  #expect(edit.range == NSRange(location: 0, length: 5))
  #expect(edit.apply(urlText: "https://example.com/two", displayText: nil, note: note, isEditorVisible: true, commands: commands))
  #expect(textView.textStorage?.attribute(.link, at: 0, effectiveRange: nil) as? URL == URL(string: "https://example.com/two"))
  #expect(textView.textStorage?.attribute(.link, at: 4, effectiveRange: nil) as? URL == URL(string: "https://example.com/two"))

  await Task.yield()
  textView.setSelectedRange(NSRange(location: 2, length: 0))
  let removal = try #require(EditorWebLinkTarget(note: note, commands: commands))
  #expect(removal.remove(note: note, isEditorVisible: true, commands: commands))
  #expect(textView.textStorage?.attribute(.link, at: 0, effectiveRange: nil) == nil)
  await Task.yield()
  try #require(textView.undoManager).undo()
  #expect(textView.textStorage?.attribute(.link, at: 0, effectiveRange: nil) as? URL == URL(string: "https://example.com/two"))
  try #require(textView.undoManager).redo()
  #expect(textView.textStorage?.attribute(.link, at: 0, effectiveRange: nil) == nil)
}

@Test @MainActor func webLinkCaretInsertionUsesDisplayTextOrValidatedURL() throws {
  let (_, textView, commands) = expansionEditor("")
  let note = Note(title: "Note", body: "", revision: 0)
  let displayTarget = try #require(EditorWebLinkTarget(note: note, commands: commands))
  #expect(displayTarget.apply(
    urlText: "https://example.com/path",
    displayText: "Example",
    note: note,
    isEditorVisible: true,
    commands: commands
  ))
  #expect(textView.string == "Example")
  #expect(textView.textStorage?.attribute(.link, at: 0, effectiveRange: nil) as? URL == URL(string: "https://example.com/path"))

  textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
  let urlTarget = try #require(EditorWebLinkTarget(note: note, commands: commands))
  #expect(urlTarget.apply(
    urlText: "http://localhost:8080",
    displayText: nil,
    note: note,
    isEditorVisible: true,
    commands: commands
  ))
  #expect(textView.string == "Examplehttp://localhost:8080")
}

@Test @MainActor func webLinkTargetRejectsProtectedNoteLinkMarkdown() {
  let noteID = UUID()
  let markdown = NoteLinkFormatter.markdown(label: "Target", targetNoteID: noteID)
  let (window, textView, commands) = expansionEditor(markdown)
  defer { withExtendedLifetime(window) {} }
  let note = Note(title: "Source", body: markdown, revision: 1)
  textView.setSelectedRange(NSRange(location: 2, length: 3))
  #expect(EditorWebLinkTarget(note: note, commands: commands) == nil)
  textView.setSelectedRange(NSRange(location: 0, length: markdown.utf16.count))
  #expect(EditorWebLinkTarget(note: note, commands: commands) == nil)
}

@Test @MainActor func nativeBodyEditorEnablesFindBarAndRoutesFinderActions() {
  let textView = RecordingFinderTextView(frame: .zero)
  textView.string = "Find this text"
  textView.usesFindBar = true
  let commands = EditorCommands()
  commands.textView = textView
  #expect(textView.usesFindBar)
  #expect(commands.performFind(.showFind))
  #expect(commands.performFind(.showReplace))
  #expect(commands.performFind(.nextMatch))
  #expect(commands.performFind(.previousMatch))
  #expect(textView.finderActionTags == [
    NSTextFinder.Action.showFindInterface.rawValue,
    NSTextFinder.Action.showReplaceInterface.rawValue,
    NSTextFinder.Action.nextMatch.rawValue,
    NSTextFinder.Action.previousMatch.rawValue,
  ])
  commands.areBodyCommandsBlocked = true
  #expect(textView.finderActionTags.last == NSTextFinder.Action.hideFindInterface.rawValue)
  commands.areBodyCommandsBlocked = false
  #expect(commands.beginFocusedDictation())
  #expect(textView.finderActionTags.last == NSTextFinder.Action.hideFindInterface.rawValue)
  commands.cancelFocusedDictation()
  textView.isEditable = false
  #expect(!commands.performFind(.showReplace))
}

@Test func toolbarItemsKeepExpandedMenusBeforeTrailingDeleteAtEveryPrefix() {
  let items = FormattingToolbarItem.allCases
  #expect(Array(items.suffix(5)) == [.textStyles, .text, .paragraph, .tools, .delete])
  let overflowableItems = Array(items.dropLast())
  let candidates = FormattingToolbarOverflowPolicy.candidateVisibleCounts(
    itemCount: overflowableItems.count
  )
  #expect(candidates == Array(stride(from: overflowableItems.count, through: 0, by: -1)))
  for visibleCount in candidates {
    let visible = Array(overflowableItems.prefix(visibleCount))
    let overflow = Array(overflowableItems.dropFirst(visibleCount))
    #expect(visible + overflow == overflowableItems)
    #expect(!visible.contains(.delete))
    #expect(!overflow.contains(.delete))
  }
}
