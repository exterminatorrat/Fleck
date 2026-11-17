import AppKit
import FleckCore
import Testing

@testable import FleckApp

enum EditorEmphasisHistorySubject: Sendable {
  case underline
  case strikethrough

  var key: NSAttributedString.Key {
    switch self {
    case .underline: .underlineStyle
    case .strikethrough: .strikethroughStyle
    }
  }
}

private let emphasisSubjects: [EditorEmphasisHistorySubject] = [.underline, .strikethrough]

private func emphasisValue(
  _ emphasis: EditorEmphasisHistorySubject,
  at location: Int,
  in storage: NSTextStorage
) -> Int {
  storage.attribute(emphasis.key, at: location, effectiveRange: nil) as? Int ?? 0
}

@MainActor
private func emphasisToggle(
  _ emphasis: EditorEmphasisHistorySubject,
  _ commands: EditorCommands
) {
  switch emphasis {
  case .underline: commands.toggleUnderline()
  case .strikethrough: commands.toggleStrikethrough()
  }
}

@MainActor
private func emphasisEditor(_ body: String) -> (NSWindow, ListAwareTextView, EditorCommands) {
  let frame = NSRect(x: 0, y: 0, width: 420, height: 220)
  let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
  let textView = ListAwareTextView(frame: frame)
  window.contentView = textView
  textView.isEditable = true
  textView.isSelectable = true
  textView.allowsUndo = true
  textView.reduceMotion = true
  textView.textStorage?.setAttributedString(
    NSAttributedString(string: body, attributes: [
      .font: NSFont.systemFont(ofSize: 17),
      .paragraphStyle: EditorTypography.defaultParagraphStyle(fontSize: 17),
    ])
  )
  let commands = EditorCommands()
  commands.configureBodyDefaults(family: ".AppleSystemUIFont", size: 17)
  commands.textView = textView
  window.makeFirstResponder(textView)
  return (window, textView, commands)
}

@MainActor
private func groupedUndoManager(_ textView: NSTextView) throws -> UndoManager {
  let undoManager = try #require(textView.undoManager)
  undoManager.groupsByEvent = false
  try #require(undoManager.groupingLevel == 0)
  return undoManager
}

@MainActor
private func withUndoGroup(_ undoManager: UndoManager, _ action: () -> Void) {
  undoManager.beginUndoGrouping()
  action()
  undoManager.endUndoGrouping()
}

@Test(arguments: emphasisSubjects)
@MainActor func selectedEmphasisToggleRestoresFullSnapshotAndSelection(
  emphasis: EditorEmphasisHistorySubject
) throws {
  let body = "Café 👩🏽‍💻 inline\nSecond styled run"
  let (window, textView, commands) = emphasisEditor(body)
  defer { withExtendedLifetime(window) {} }
  let storage = try #require(textView.textStorage)
  let document = body as NSString
  let inline = document.range(of: "inline")
  let emoji = document.range(of: "👩🏽‍💻")
  let secondLine = document.range(of: "Second styled run")
  let secondParagraph = NSMutableParagraphStyle()
  secondParagraph.headIndent = 24
  secondParagraph.firstLineHeadIndent = 8
  secondParagraph.textLists = [NSTextList(markerFormat: .decimal, options: 0)]
  storage.addAttributes(
    [
      .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold),
      .foregroundColor: NSColor.systemRed,
      .link: try #require(URL(string: "https://example.com/flec238")),
    ],
    range: inline
  )
  storage.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: emoji)
  storage.addAttributes(
    [
      .font: NSFont.systemFont(ofSize: 21),
      .paragraphStyle: secondParagraph,
    ],
    range: secondLine
  )
  let firstParagraphStyle = try #require(
    storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
  )
  #expect(firstParagraphStyle.headIndent != secondParagraph.headIndent)
  let original = NSAttributedString(attributedString: storage)
  let selection = NSRange(location: 0, length: document.length)
  textView.setSelectedRange(selection)
  let undoManager = try groupedUndoManager(textView)
  undoManager.removeAllActions()

  withUndoGroup(undoManager) { emphasisToggle(emphasis, commands) }

  for location in 0..<document.length {
    #expect(emphasisValue(emphasis, at: location, in: storage) == NSUnderlineStyle.single.rawValue)
  }
  let changed = NSAttributedString(attributedString: storage)
  #expect(undoManager.canUndo)
  textView.setSelectedRange(NSRange(location: 0, length: 0))

  undoManager.undo()
  #expect(textView.attributedString().isEqual(to: original))
  #expect(textView.selectedRange() == selection)
  #expect(textView.string.utf16.elementsEqual(body.utf16))
  let restoredSecond = try #require(
    storage.attribute(.paragraphStyle, at: secondLine.location, effectiveRange: nil)
      as? NSParagraphStyle
  )
  #expect(restoredSecond.headIndent == 24)
  #expect(restoredSecond.textLists.count == 1)
  #expect(undoManager.canRedo)

  undoManager.redo()
  #expect(textView.attributedString().isEqual(to: changed))
  #expect(textView.selectedRange() == selection)
  #expect(textView.string.utf16.elementsEqual(body.utf16))
}

@Test(arguments: emphasisSubjects)
@MainActor func selectedEmphasisOnMixedSelectionEnablesAndUndoRestoresMix(
  emphasis: EditorEmphasisHistorySubject
) throws {
  let body = "mixed run here"
  let (window, textView, commands) = emphasisEditor(body)
  defer { withExtendedLifetime(window) {} }
  let storage = try #require(textView.textStorage)
  let document = body as NSString
  let run = document.range(of: "run")
  storage.addAttribute(
    emphasis.key,
    value: NSUnderlineStyle.single.rawValue,
    range: run
  )
  storage.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: run)
  let original = NSAttributedString(attributedString: storage)
  let selection = NSRange(location: 0, length: document.length)
  textView.setSelectedRange(selection)
  let undoManager = try groupedUndoManager(textView)
  undoManager.removeAllActions()

  withUndoGroup(undoManager) { emphasisToggle(emphasis, commands) }

  for location in 0..<document.length {
    #expect(emphasisValue(emphasis, at: location, in: storage) == NSUnderlineStyle.single.rawValue)
  }
  let changed = NSAttributedString(attributedString: storage)
  #expect(undoManager.canUndo)
  textView.setSelectedRange(NSRange(location: 0, length: 0))

  undoManager.undo()
  #expect(textView.attributedString().isEqual(to: original))
  #expect(textView.selectedRange() == selection)
  #expect(
    emphasisValue(emphasis, at: run.location, in: storage) == NSUnderlineStyle.single.rawValue
  )
  #expect(emphasisValue(emphasis, at: 0, in: storage) == 0)
  #expect(textView.string.utf16.elementsEqual(body.utf16))
  #expect(undoManager.canRedo)

  undoManager.redo()
  #expect(textView.attributedString().isEqual(to: changed))
  #expect(textView.selectedRange() == selection)
  #expect(textView.string.utf16.elementsEqual(body.utf16))
}

@Test(arguments: emphasisSubjects)
@MainActor func selectedEmphasisToggleDisablesFullSelectionAndUndoRestores(
  emphasis: EditorEmphasisHistorySubject
) throws {
  let body = "fully styled run"
  let (window, textView, commands) = emphasisEditor(body)
  defer { withExtendedLifetime(window) {} }
  let storage = try #require(textView.textStorage)
  let document = body as NSString
  storage.addAttribute(
    emphasis.key,
    value: NSUnderlineStyle.single.rawValue,
    range: NSRange(location: 0, length: document.length)
  )
  let original = NSAttributedString(attributedString: storage)
  let selection = NSRange(location: 0, length: document.length)
  textView.setSelectedRange(selection)
  let undoManager = try groupedUndoManager(textView)
  undoManager.removeAllActions()

  withUndoGroup(undoManager) { emphasisToggle(emphasis, commands) }

  for location in 0..<document.length {
    #expect(emphasisValue(emphasis, at: location, in: storage) == 0)
  }
  let changed = NSAttributedString(attributedString: storage)
  #expect(undoManager.canUndo)
  textView.setSelectedRange(NSRange(location: 0, length: 0))

  undoManager.undo()
  #expect(textView.attributedString().isEqual(to: original))
  #expect(textView.selectedRange() == selection)
  #expect(
    emphasisValue(emphasis, at: 0, in: storage) == NSUnderlineStyle.single.rawValue
  )
  #expect(textView.string.utf16.elementsEqual(body.utf16))
  #expect(undoManager.canRedo)

  undoManager.redo()
  #expect(textView.attributedString().isEqual(to: changed))
  #expect(textView.selectedRange() == selection)
  #expect(emphasisValue(emphasis, at: 0, in: storage) == 0)
  #expect(textView.string.utf16.elementsEqual(body.utf16))
}

@Test(arguments: emphasisSubjects)
@MainActor func selectedEmphasisUndoDoesNotSwallowEarlierTyping(
  emphasis: EditorEmphasisHistorySubject
) throws {
  let body = "alpha beta"
  let (window, textView, commands) = emphasisEditor(body)
  defer { withExtendedLifetime(window) {} }
  let storage = try #require(textView.textStorage)
  let undoManager = try groupedUndoManager(textView)
  undoManager.removeAllActions()
  textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
  withUndoGroup(undoManager) {
    textView.insertText(" omega", replacementRange: textView.selectedRange())
  }
  #expect(textView.string == "alpha beta omega")
  let afterTyping = NSAttributedString(attributedString: storage)
  let beta = (textView.string as NSString).range(of: "beta")
  textView.setSelectedRange(beta)

  withUndoGroup(undoManager) { emphasisToggle(emphasis, commands) }
  textView.setSelectedRange(NSRange(location: 0, length: 0))

  undoManager.undo()
  #expect(textView.string == "alpha beta omega")
  #expect(textView.attributedString().isEqual(to: afterTyping))
  #expect(textView.selectedRange() == beta)
  #expect(undoManager.canUndo)

  undoManager.undo()
  #expect(textView.string.utf16.elementsEqual(body.utf16))
  #expect(!undoManager.canUndo)
}

@Test(arguments: emphasisSubjects)
@MainActor func emphasisRedoIsInvalidatedByNextEdit(
  emphasis: EditorEmphasisHistorySubject
) throws {
  let body = "redo target"
  let (window, textView, commands) = emphasisEditor(body)
  defer { withExtendedLifetime(window) {} }
  let storage = try #require(textView.textStorage)
  let target = (body as NSString).range(of: "target")
  textView.setSelectedRange(target)
  let undoManager = try groupedUndoManager(textView)
  undoManager.removeAllActions()

  withUndoGroup(undoManager) { emphasisToggle(emphasis, commands) }
  textView.setSelectedRange(NSRange(location: 0, length: 0))

  undoManager.undo()
  #expect(textView.selectedRange() == target)
  #expect(undoManager.canRedo)

  textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
  withUndoGroup(undoManager) {
    textView.insertText("!", replacementRange: textView.selectedRange())
  }
  #expect(textView.string == "redo target!")
  #expect(!undoManager.canRedo)
  #expect(undoManager.canUndo)
  #expect(emphasisValue(emphasis, at: 0, in: storage) == 0)
}

@Test(arguments: emphasisSubjects)
@MainActor func caretEmphasisToggleRegistersNoUndoEntryAndTypesWithAttribute(
  emphasis: EditorEmphasisHistorySubject
) throws {
  let body = "caret line"
  let (window, textView, commands) = emphasisEditor(body)
  defer { withExtendedLifetime(window) {} }
  let storage = try #require(textView.textStorage)
  let caret = textView.string.utf16.count
  textView.setSelectedRange(NSRange(location: caret, length: 0))
  let undoManager = try groupedUndoManager(textView)
  undoManager.removeAllActions()

  emphasisToggle(emphasis, commands)
  #expect(textView.typingAttributes[emphasis.key] as? Int == NSUnderlineStyle.single.rawValue)
  #expect(!undoManager.canUndo)

  emphasisToggle(emphasis, commands)
  #expect(textView.typingAttributes[emphasis.key] as? Int == 0)
  #expect(!undoManager.canUndo)

  emphasisToggle(emphasis, commands)
  withUndoGroup(undoManager) {
    textView.insertText("X", replacementRange: textView.selectedRange())
  }
  #expect(textView.string == "caret lineX")
  #expect(emphasisValue(emphasis, at: caret, in: storage) == NSUnderlineStyle.single.rawValue)

  undoManager.undo()
  #expect(textView.string.utf16.elementsEqual(body.utf16))
}

@Test @MainActor func selectedEmphasisToggleKeepsExistingBodyCommandGuards() throws {
  let (window, textView, commands) = emphasisEditor("guarded body")
  defer { withExtendedLifetime(window) {} }
  let storage = try #require(textView.textStorage)
  textView.setSelectedRange(NSRange(location: 0, length: 7))
  let original = NSAttributedString(attributedString: storage)
  let undoManager = try groupedUndoManager(textView)

  undoManager.removeAllActions()
  textView.isEditable = false
  commands.toggleUnderline()
  commands.toggleStrikethrough()
  #expect(textView.attributedString().isEqual(to: original))
  #expect(!undoManager.canUndo)
  textView.isEditable = true

  commands.areBodyCommandsBlocked = true
  commands.toggleUnderline()
  commands.toggleStrikethrough()
  #expect(textView.attributedString().isEqual(to: original))
  #expect(!undoManager.canUndo)
  commands.areBodyCommandsBlocked = false

  commands.isBodyCommandContextBlocked = true
  commands.toggleUnderline()
  commands.toggleStrikethrough()
  #expect(textView.attributedString().isEqual(to: original))
  #expect(!undoManager.canUndo)
  commands.isBodyCommandContextBlocked = false

  #expect(commands.beginFocusedDictation())
  commands.toggleUnderline()
  commands.toggleStrikethrough()
  #expect(textView.attributedString().isEqual(to: original))
  #expect(!undoManager.canUndo)
  commands.cancelFocusedDictation()
  #expect(!commands.isFocusedDictationActive)
}

@Test @MainActor func selectedEmphasisToggleRejectsTitleEditingFocus() throws {
  let frame = NSRect(x: 0, y: 0, width: 420, height: 220)
  let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
  let title = NSTextField(string: "Title")
  let textView = ListAwareTextView(frame: frame)
  textView.isEditable = true
  textView.isSelectable = true
  textView.allowsUndo = true
  textView.textStorage?.setAttributedString(
    NSAttributedString(string: "title guard", attributes: [
      .font: NSFont.systemFont(ofSize: 17),
      .paragraphStyle: EditorTypography.defaultParagraphStyle(fontSize: 17),
    ])
  )
  window.contentView = NativeEditorDocumentView(titleField: title, textView: textView)
  defer { withExtendedLifetime(window) {} }
  let commands = EditorCommands()
  commands.textView = textView
  #expect(window.makeFirstResponder(title))
  #expect(commands.isTitleEditing)
  textView.setSelectedRange(NSRange(location: 0, length: 5))
  let storage = try #require(textView.textStorage)
  let original = NSAttributedString(attributedString: storage)
  let undoManager = try groupedUndoManager(textView)
  undoManager.removeAllActions()

  commands.toggleUnderline()
  commands.toggleStrikethrough()
  #expect(textView.attributedString().isEqual(to: original))
  #expect(!undoManager.canUndo)
}

@Test @MainActor func emphasisTogglePreservesUnicodeChecklistAndLinkMetadata() throws {
  let noteID = try #require(UUID(uuidString: "0A1B2C3D-0000-4000-8000-00000000C238"))
  let noteLink = NoteLinkFormatter.markdown(label: "Plan", targetNoteID: noteID)
  let body = "● deploy 👩🏽‍💻 ready\n○ next \(noteLink)"
  let (window, textView, commands) = emphasisEditor(body)
  defer { withExtendedLifetime(window) {} }
  let storage = try #require(textView.textStorage)
  let document = body as NSString
  let doneContent = document.range(of: "deploy 👩🏽‍💻 ready")
  let ready = document.range(of: "ready")
  let nextContent = document.range(of: "next")
  let webLink = try #require(URL(string: "https://example.com/flec238"))
  storage.addAttribute(
    .strikethroughStyle,
    value: NSUnderlineStyle.single.rawValue,
    range: doneContent
  )
  storage.addAttribute(.link, value: webLink, range: ready)
  let original = NSAttributedString(attributedString: storage)
  let undoManager = try groupedUndoManager(textView)
  undoManager.removeAllActions()

  textView.setSelectedRange(doneContent)
  withUndoGroup(undoManager) { commands.toggleUnderline() }
  #expect(
    emphasisValue(.underline, at: doneContent.location, in: storage)
      == NSUnderlineStyle.single.rawValue
  )
  #expect(
    emphasisValue(.strikethrough, at: doneContent.location, in: storage)
      == NSUnderlineStyle.single.rawValue
  )
  #expect(emphasisValue(.strikethrough, at: 0, in: storage) == 0)
  #expect(textView.string.utf16.elementsEqual(body.utf16))

  undoManager.undo()
  #expect(textView.attributedString().isEqual(to: original))
  #expect(textView.selectedRange() == doneContent)
  #expect(storage.attribute(.link, at: ready.location, effectiveRange: nil) as? URL == webLink)
  #expect(NoteLinkParser.links(in: textView.string).map(\.targetNoteID) == [noteID])
  #expect(textView.string.utf16.elementsEqual(body.utf16))
  let restored = try NoteRichTextCodec.decode(NoteRichTextCodec.encode(storage))
  #expect(
    restored.string.utf16.elementsEqual(body.precomposedStringWithCanonicalMapping.utf16)
  )
  #expect(
    restored.attribute(.strikethroughStyle, at: doneContent.location, effectiveRange: nil)
      as? Int == NSUnderlineStyle.single.rawValue
  )
  #expect(
    (restored.attribute(.underlineStyle, at: doneContent.location, effectiveRange: nil) as? Int
      ?? 0) == 0
  )

  undoManager.removeAllActions()
  textView.setSelectedRange(nextContent)
  withUndoGroup(undoManager) { commands.toggleStrikethrough() }
  #expect(
    emphasisValue(.strikethrough, at: nextContent.location, in: storage)
      == NSUnderlineStyle.single.rawValue
  )
  #expect(emphasisValue(.strikethrough, at: 0, in: storage) == 0)
  #expect(textView.string.utf16.elementsEqual(body.utf16))
  let toggled = try NoteRichTextCodec.decode(NoteRichTextCodec.encode(storage))
  #expect(
    toggled.string.utf16.elementsEqual(body.precomposedStringWithCanonicalMapping.utf16)
  )
  #expect(
    toggled.attribute(.strikethroughStyle, at: nextContent.location, effectiveRange: nil) as? Int
      == NSUnderlineStyle.single.rawValue
  )

  undoManager.undo()
  #expect(textView.attributedString().isEqual(to: original))
  #expect(textView.selectedRange() == nextContent)
  #expect(NoteLinkParser.links(in: textView.string).map(\.targetNoteID) == [noteID])
  #expect(textView.string.utf16.elementsEqual(body.utf16))
}
