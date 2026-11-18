import AppKit
import FleckCore
import Testing

@testable import FleckApp

@MainActor
private func undoEditor(_ text: String) -> (ListAwareTextView, NSWindow, EditorCommands) {
  let frame = NSRect(x: 0, y: 0, width: 420, height: 200)
  let view = ListAwareTextView(frame: frame)
  let window = NSWindow(
    contentRect: frame,
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.isReleasedWhenClosed = false
  window.contentView = view
  view.allowsUndo = true
  view.textStorage?.setAttributedString(
    NSAttributedString(string: text, attributes: [
      .font: NSFont.systemFont(ofSize: 17),
      .paragraphStyle: EditorTypography.defaultParagraphStyle(fontSize: 17),
    ])
  )
  window.makeKeyAndOrderFront(nil)
  window.makeFirstResponder(view)
  let commands = EditorCommands()
  commands.textView = view
  return (view, window, commands)
}

@MainActor
private func agentEditor(
  _ text: String,
  richTextRTF: Data? = nil,
  commands: EditorCommands,
  onChange: @escaping (String, Data?) -> Void = { _, _ in }
) -> NativeRichTextEditor {
  NativeRichTextEditor(
    text: text,
    richTextRTF: richTextRTF,
    onChange: onChange,
    fontFamily: "Helvetica",
    fontSize: 17,
    textColorHex: nil,
    backgroundColorHex: nil,
    accentColorHex: "#007AFF",
    reduceMotion: true,
    automaticLists: false,
    commands: commands
  )
}

@Test @MainActor func oneUndoRemovesTheWholeDictationPassage() throws {
  let (view, window, commands) = undoEditor("Before  after")
  defer { closeEditorTestWindow(window) }
  view.setSelectedRange(NSRange(location: 7, length: 0))
  let original = try #require(view.textStorage.map { NSAttributedString(attributedString: $0) })
  view.undoManager?.removeAllActions()

  #expect(commands.beginFocusedDictation())
  commands.updateFocusedDictation(provisionalText: "spoken")
  commands.updateFocusedDictation(provisionalText: "spoken words")
  let receipt = try #require(commands.commitFocusedDictation(text: "spoken words"))
  commands.finalizeCommittedFocusedDictation(receipt)
  #expect(view.string == "Before spoken words after")

  let undo = try #require(view.undoManager)
  #expect(undo.undoActionName == "Dictation")
  undo.undo()

  #expect(view.string == "Before  after")
  #expect(NSAttributedString(attributedString: try #require(view.textStorage)).isEqual(to: original))
  #expect(view.selectedRange() == NSRange(location: 7, length: 0))
}

@Test @MainActor func oneUndoRestoresAnAgentParagraphWithItsActionName() throws {
  let commands = EditorCommands()
  let original = "First paragraph\n\nSecond paragraph"
  let (view, window, _) = undoEditor(original)
  defer { closeEditorTestWindow(window) }
  let coordinator = agentEditor(original, commands: commands).makeCoordinator()
  coordinator.text = original
  coordinator.richTextRTF = nil
  coordinator.lastModelText = original
  coordinator.lastModelRichTextRTF = nil
  view.undoManager?.removeAllActions()
  let secondParagraph = (original as NSString).range(of: "Second")
  view.setSelectedRange(NSRange(location: secondParagraph.location, length: 0))
  let priorSelection = view.selectedRange()
  let priorStorage = try #require(
    view.textStorage.map { NSAttributedString(attributedString: $0) }
  )

  let updated = "First paragraph\n\nSecond thought replaced"
  let editor = agentEditor(updated, commands: commands)
  #expect(editor.applyExternalContentIfNeeded(to: view, coordinator: coordinator))
  #expect(view.string == updated)
  #expect(view.selectedRange() == priorSelection)

  let undo = try #require(view.undoManager)
  #expect(undo.undoActionName == "Agent Edit")
  undo.undo()

  #expect(view.string == original)
  #expect(view.selectedRange() == priorSelection)
  #expect(NSAttributedString(attributedString: try #require(view.textStorage)).isEqual(to: priorStorage))
}

@Test @MainActor func agentParagraphEditKeepsTheBodyFont() throws {
  let commands = EditorCommands()
  let original = "Alpha line\nBeta line"
  let (view, window, _) = undoEditor(original)
  defer { closeEditorTestWindow(window) }
  let coordinator = agentEditor(original, commands: commands).makeCoordinator()
  coordinator.text = original
  coordinator.richTextRTF = nil
  coordinator.lastModelText = original
  coordinator.lastModelRichTextRTF = nil

  let updated = "Alpha line\nBeta line rewritten"
  #expect(agentEditor(updated, commands: commands).applyExternalContentIfNeeded(
    to: view, coordinator: coordinator
  ))

  let storage = try #require(view.textStorage)
  let font = try #require(storage.attribute(.font, at: storage.length - 1, effectiveRange: nil) as? NSFont)
  let expected = EditorTypography.bodyFont(family: "Helvetica", size: 17)
  #expect(font.familyName == expected.familyName)
  #expect(font.pointSize == 17)
}

@Test @MainActor func wholeDocumentRewriteStillReloadsInsteadOfBecomingOneUndoStep() throws {
  let commands = EditorCommands()
  let original = "One two three"
  let (view, window, _) = undoEditor(original)
  defer { closeEditorTestWindow(window) }
  let coordinator = agentEditor(original, commands: commands).makeCoordinator()
  coordinator.text = original
  coordinator.richTextRTF = nil
  coordinator.lastModelText = original
  coordinator.lastModelRichTextRTF = nil
  view.undoManager?.removeAllActions()

  let replaced = "Completely different wording here"
  #expect(agentEditor(replaced, commands: commands).applyExternalContentIfNeeded(
    to: view, coordinator: coordinator
  ))
  #expect(view.string == replaced)
  #expect(view.undoManager?.canUndo == false)
}

@Test @MainActor func modelEditsDoNotEchoButUndoAndTypingStillPublish() throws {
  let original = "First paragraph\n\nSecond paragraph"
  let (view, window, commands) = undoEditor(original)
  defer { closeEditorTestWindow(window) }
  var reportedBodies: [String] = []
  let editor = agentEditor(original, commands: commands) { body, _ in
    reportedBodies.append(body)
  }
  let coordinator = editor.makeCoordinator()
  view.delegate = coordinator
  let undo = try #require(view.undoManager)
  undo.removeAllActions()

  let updated = original + " extended"
  let external = agentEditor(updated, commands: commands) { body, _ in
    reportedBodies.append(body)
  }
  coordinator.parent = external
  #expect(external.applyExternalContentIfNeeded(to: view, coordinator: coordinator))
  #expect(view.string == updated)
  #expect(reportedBodies.isEmpty)
  #expect(undo.undoActionName == "Agent Edit")

  undo.undo()
  #expect(view.string == original)
  #expect(reportedBodies.last == original)

  reportedBodies.removeAll()
  view.insertText("!", replacementRange: NSRange(location: (original as NSString).length, length: 0))
  #expect(reportedBodies == [original + "!"])
}

@Test @MainActor func modelTextEditsPreserveFormattingChangesOutsideTheirReplacement() throws {
  let original = "Keep prefix\nReplace old\nKeep suffix"
  let updated = "Keep prefix\nReplace new\nKeep suffix"

  for formattedText in ["Keep prefix", "Keep suffix"] {
    let (view, window, commands) = undoEditor(original)
    defer { closeEditorTestWindow(window) }
    let coordinator = agentEditor(original, commands: commands).makeCoordinator()
    let target = NSMutableAttributedString(
      string: updated,
      attributes: EditorTypography.defaultAttributes(family: "Helvetica", size: 17)
    )
    let formattedRange = (updated as NSString).range(of: formattedText)
    target.addAttribute(
      .underlineStyle,
      value: NSUnderlineStyle.single.rawValue,
      range: formattedRange
    )
    let rtf = try NoteRichTextCodec.encode(target)
    let external = agentEditor(updated, richTextRTF: rtf, commands: commands)

    #expect(external.applyExternalContentIfNeeded(to: view, coordinator: coordinator))
    #expect(view.string == updated)
    let storage = try #require(view.textStorage)
    #expect(
      storage.attribute(.underlineStyle, at: formattedRange.location, effectiveRange: nil) as? Int
        == NSUnderlineStyle.single.rawValue
    )
  }
}

@Test @MainActor func richModelEditWithMatchingSurroundingFormattingKeepsSingleUndo() throws {
  let original = "First paragraph\n\nSecond paragraph"
  let (view, window, commands) = undoEditor(original)
  defer { closeEditorTestWindow(window) }
  let initialRTF = try NoteRichTextCodec.encode(try #require(view.textStorage))
  let initialContent = try NoteRichTextCodec.decode(initialRTF)
  view.textStorage?.setAttributedString(initialContent)
  let coordinator = agentEditor(
    original, richTextRTF: initialRTF, commands: commands
  ).makeCoordinator()
  let target = NSMutableAttributedString(attributedString: initialContent)
  target.replaceCharacters(in: (original as NSString).range(of: "Second"), with: "Revised")
  let targetRTF = try NoteRichTextCodec.encode(target)
  let undo = try #require(view.undoManager)
  undo.removeAllActions()

  let external = agentEditor(target.string, richTextRTF: targetRTF, commands: commands)
  #expect(external.applyExternalContentIfNeeded(to: view, coordinator: coordinator))
  #expect(view.string == "First paragraph\n\nRevised paragraph")
  #expect(undo.undoActionName == "Agent Edit")
  undo.undo()
  #expect(view.string == original)
}
