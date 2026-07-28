import AppKit
import Testing

@testable import MenuBarNotesApp

@Test @MainActor func focusedDictationInsertsAtTheCapturedCaret() throws {
  let (commands, textView) = makeFocusedEditor(body: "before after")
  textView.setSelectedRange(NSRange(location: 7, length: 0))
  let editor: any FocusedDictationEditing = commands

  #expect(editor.beginFocusedDictation())
  editor.updateFocusedDictation(provisionalText: "draft ")

  #expect(textView.string == "before draft after")
}

@Test @MainActor func focusedDictationDefersSelectedTextReplacementUntilCommit() throws {
  let (commands, textView) = makeFocusedEditor(body: "Keep replace me please")
  textView.setSelectedRange(NSRange(location: 5, length: 10))
  let editor: any FocusedDictationEditing = commands

  #expect(editor.beginFocusedDictation())
  editor.updateFocusedDictation(provisionalText: "draft")
  #expect(textView.string == "Keep draft please")

  #expect(editor.commitFocusedDictation(text: "final") != nil)
  #expect(textView.string == "Keep final please")
}

@Test @MainActor func focusedDictationReplacesOnlyItsCurrentProvisionalRange() throws {
  let (commands, textView) = makeFocusedEditor(body: "before after")
  textView.setSelectedRange(NSRange(location: 7, length: 0))
  let editor: any FocusedDictationEditing = commands

  #expect(editor.beginFocusedDictation())
  editor.updateFocusedDictation(provisionalText: "first ")
  editor.updateFocusedDictation(provisionalText: "second ")

  #expect(textView.string == "before second after")
}

@Test @MainActor func focusedDictationCancellationRestoresAttributedSelectionWithoutBindingChange() throws {
  let (commands, textView) = makeFocusedEditor(body: "Keep replace me please")
  let selectedRange = NSRange(location: 5, length: 10)
  textView.textStorage?.addAttribute(.foregroundColor, value: NSColor.systemRed, range: selectedRange)
  textView.setSelectedRange(selectedRange)
  let delegate = ChangeRecordingDelegate()
  textView.delegate = delegate
  let editor: any FocusedDictationEditing = commands

  #expect(editor.beginFocusedDictation())
  editor.updateFocusedDictation(provisionalText: "draft")
  editor.cancelFocusedDictation()

  #expect(textView.string == "Keep replace me please")
  #expect(textView.selectedRange() == selectedRange)
  #expect(
    textView.textStorage?.attribute(.foregroundColor, at: selectedRange.location, effectiveRange: nil)
      as? NSColor == NSColor.systemRed
  )
  #expect(delegate.changeCount == 0)
}

@Test @MainActor func focusedDictationCommitIsOneUndoOperation() throws {
  let (commands, textView) = makeFocusedEditor(body: "Keep replace me please")
  let selectedRange = NSRange(location: 5, length: 10)
  textView.setSelectedRange(selectedRange)
  let editor: any FocusedDictationEditing = commands

  #expect(editor.beginFocusedDictation())
  editor.updateFocusedDictation(provisionalText: "draft")
  #expect(editor.commitFocusedDictation(text: "final") != nil)
  #expect(textView.string == "Keep final please")

  let undoManager = try #require(textView.undoManager)
  #expect(undoManager.canUndo)
  undoManager.undo()

  #expect(textView.string == "Keep replace me please")
  #expect(!undoManager.canUndo)
}

@Test @MainActor func focusedDictationPreservesUserEditsOutsideTheProvisionalRange() throws {
  let (commands, textView) = makeFocusedEditor(body: "before after")
  textView.setSelectedRange(NSRange(location: 7, length: 0))
  let editor: any FocusedDictationEditing = commands

  #expect(editor.beginFocusedDictation())
  editor.updateFocusedDictation(provisionalText: "draft")
  textView.textStorage?.replaceCharacters(in: NSRange(location: 0, length: 0), with: "!")
  editor.updateFocusedDictation(provisionalText: "second")
  #expect(editor.commitFocusedDictation(text: "final") != nil)

  #expect(textView.string == "!before finalafter")
}

@Test @MainActor func focusedDictationCancelsItsOriginWhenTheEditorViewChanges() {
  let (commands, origin) = makeFocusedEditor(body: "Replace this")
  origin.setSelectedRange(NSRange(location: 0, length: 7))
  let editor: any FocusedDictationEditing = commands
  #expect(editor.beginFocusedDictation())
  editor.updateFocusedDictation(provisionalText: "Draft")

  let replacementView = NSTextView(frame: .zero)
  replacementView.string = "Other note"
  commands.textView = replacementView

  #expect(origin.string == "Replace this")
  #expect(origin.selectedRange() == NSRange(location: 0, length: 7))
  #expect(replacementView.string == "Other note")
  #expect(editor.commitFocusedDictation(text: "Final") == nil)
}

@Test @MainActor func focusedDictationDelegateSnapshotsExcludeProvisionalTextAndCancelCannotReloadIt()
  throws
{
  let (commands, textView) = makeFocusedEditor(body: "before replace after")
  textView.setSelectedRange(NSRange(location: 7, length: 7))
  let delegate = BindingRecordingDelegate(commands: commands)
  textView.delegate = delegate
  let editor: any FocusedDictationEditing = commands
  #expect(editor.beginFocusedDictation())
  editor.updateFocusedDictation(provisionalText: "Draft")

  textView.textStorage?.replaceCharacters(in: NSRange(location: 0, length: 0), with: "!")
  textView.didChangeText()

  #expect(delegate.bodies == ["!before replace after"])
  #expect(try #require(delegate.rtf.last).contains(Data("Draft".utf8)) == false)

  editor.cancelFocusedDictation()
  #expect(textView.string == "!before replace after")
  #expect(delegate.bodies.last == textView.string)
}

@Test @MainActor func focusedDictationUndoAndRedoEmitBindingUpdates() throws {
  let (commands, textView) = makeFocusedEditor(body: "Replace this")
  textView.setSelectedRange(NSRange(location: 0, length: 7))
  let delegate = BindingRecordingDelegate(commands: commands)
  textView.delegate = delegate
  let editor: any FocusedDictationEditing = commands
  #expect(editor.beginFocusedDictation())
  editor.updateFocusedDictation(provisionalText: "Draft")
  #expect(editor.commitFocusedDictation(text: "Final") != nil)

  let undoManager = try #require(textView.undoManager)
  undoManager.undo()
  undoManager.redo()

  #expect(delegate.bodies == ["Final this", "Replace this", "Final this"])
  #expect(delegate.rtf.count == 3)
}

@Test @MainActor func focusedDictationCancellationTracksTheOriginalSelectionAfterEarlierEdits() {
  let (commands, textView) = makeFocusedEditor(body: "before replace after")
  textView.setSelectedRange(NSRange(location: 7, length: 7))
  let editor: any FocusedDictationEditing = commands
  #expect(editor.beginFocusedDictation())
  editor.updateFocusedDictation(provisionalText: "Draft")

  textView.textStorage?.replaceCharacters(in: NSRange(location: 0, length: 0), with: "!")
  editor.cancelFocusedDictation()

  #expect(textView.selectedRange() == NSRange(location: 8, length: 7))
}

@MainActor
private func makeFocusedEditor(body: String) -> (EditorCommands, NSTextView) {
  let commands = EditorCommands()
  let textView = NSTextView(frame: .zero)
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = textView
  textView.allowsUndo = true
  textView.string = body
  commands.textView = textView
  return (commands, textView)
}

@MainActor
private final class ChangeRecordingDelegate: NSObject, NSTextViewDelegate {
  var changeCount = 0

  func textDidChange(_ notification: Notification) {
    changeCount += 1
  }
}

@MainActor
private final class BindingRecordingDelegate: NSObject, NSTextViewDelegate {
  let commands: EditorCommands
  var bodies: [String] = []
  var rtf: [Data] = []

  init(commands: EditorCommands) {
    self.commands = commands
  }

  func textDidChange(_ notification: Notification) {
    guard let textView = notification.object as? NSTextView,
      let snapshot = commands.attributedBindingSnapshot(for: textView)
    else { return }
    bodies.append(snapshot.string)
    rtf.append(try! snapshot.data(
      from: NSRange(location: 0, length: snapshot.length),
      documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
    ))
  }
}
