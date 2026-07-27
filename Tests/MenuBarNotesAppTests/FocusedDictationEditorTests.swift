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

  #expect(editor.commitFocusedDictation(text: "final"))
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
  #expect(editor.commitFocusedDictation(text: "final"))
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
  #expect(editor.commitFocusedDictation(text: "final"))

  #expect(textView.string == "!before finalafter")
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
