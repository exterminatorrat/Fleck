import AppKit
import MenuBarNotesCore
import Testing

@testable import MenuBarNotesApp

@Test @MainActor func agentAppendPreservesExistingFormattingAndUsesEditorDefaults() throws {
  let source = NSMutableAttributedString(string: "Existing")
  source.addAttributes(
    [
      .font: NSFont.boldSystemFont(ofSize: 18),
      .underlineStyle: NSUnderlineStyle.single.rawValue,
    ],
    range: NSRange(location: 0, length: source.length)
  )
  let note = Note(
    body: source.string,
    richTextRTF: try rtf(source),
    revision: 4
  )
  let draft = try AgentNoteMutationEngine.append(text: "Added", to: note.body)

  let result = try AgentRichTextMutator.applying(
    draft,
    operation: .appendText,
    to: note,
    preferences: AppPreferences(fontFamily: "Menlo", fontSize: 17),
    now: Date(timeIntervalSince1970: 100)
  )
  let decoded = try attributed(result)

  #expect(result.body == "Existing\n\nAdded")
  #expect(result.revision == 5)
  #expect(
    (decoded.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int)
      == NSUnderlineStyle.single.rawValue
  )
  let addedFont = try #require(
    decoded.attribute(.font, at: "Existing\n\n".utf16.count, effectiveRange: nil) as? NSFont
  )
  #expect(addedFont.familyName == "Menlo")
  #expect(addedFont.pointSize == 17)
}

@Test @MainActor func agentInsertionPreservesAttributedRunsOutsideExactRange() throws {
  let source = NSMutableAttributedString(string: "First\nThird")
  source.addAttribute(.foregroundColor, value: NSColor.red, range: NSRange(location: 0, length: 5))
  source.addAttribute(.foregroundColor, value: NSColor.blue, range: NSRange(location: 6, length: 5))
  let note = Note(body: source.string, richTextRTF: try rtf(source), revision: 1)
  let draft = try AgentNoteMutationEngine.insert(text: "Second", beforeLine: 2, in: note.body)

  let result = try AgentRichTextMutator.applying(
    draft,
    operation: .insertText,
    to: note,
    preferences: .init()
  )
  let decoded = try attributed(result)

  #expect(decoded.string == "First\nSecond\nThird")
  #expect(decoded.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .red)
  #expect(
    decoded.attribute(
      .foregroundColor,
      at: "First\nSecond\n".utf16.count,
      effectiveRange: nil
    ) as? NSColor == .blue
  )
}

@Test @MainActor func agentReplacementAppliesDefaultsOnlyToNewText() throws {
  let source = NSMutableAttributedString(string: "Before\nTarget\nAfter")
  source.addAttribute(
    .font,
    value: NSFont.boldSystemFont(ofSize: 22),
    range: NSRange(location: 0, length: source.length)
  )
  let note = Note(body: source.string, richTextRTF: try rtf(source))
  let draft = try AgentNoteMutationEngine.replaceLines(
    in: note.body,
    startLine: 2,
    endLine: 2,
    expectedTextSHA256:
      "978354db0c00fc78c3a5524f462a73bc425df3fb2767e51a5f46352ae26ae6f9",
    replacement: "Fresh"
  )

  let result = try AgentRichTextMutator.applying(
    draft,
    operation: .replaceLines,
    to: note,
    preferences: AppPreferences(fontFamily: "Menlo", fontSize: 16)
  )
  let decoded = try attributed(result)

  let beforeFont = try #require(decoded.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
  let freshFont = try #require(
    decoded.attribute(.font, at: "Before\n".utf16.count, effectiveRange: nil) as? NSFont
  )
  #expect(NSFontManager.shared.traits(of: beforeFont).contains(.boldFontMask))
  #expect(freshFont.familyName == "Menlo")
  #expect(freshFont.pointSize == 16)
}

@Test @MainActor func taskCompletionStrikesOnlyContentAndReopenRemovesOnlyThatStrike() throws {
  let source = NSMutableAttributedString(string: "    ○ Ship release")
  source.addAttribute(
    .underlineStyle,
    value: NSUnderlineStyle.single.rawValue,
    range: NSRange(location: 6, length: "Ship release".utf16.count)
  )
  let note = Note(body: source.string, richTextRTF: try rtf(source))
  let task = try #require(AgentNoteMutationEngine.tasks(in: note.body).first)
  let completed = try AgentNoteMutationEngine.setTaskState(task, completed: true, in: note.body)

  let completedNote = try AgentRichTextMutator.applying(
    completed,
    operation: .setTaskState,
    to: note,
    preferences: .init()
  )
  let completedText = try attributed(completedNote)
  #expect(
    (completedText.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int ?? 0) == 0)
  #expect(
    (completedText.attribute(.strikethroughStyle, at: 4, effectiveRange: nil) as? Int ?? 0) == 0)
  #expect(
    (completedText.attribute(.strikethroughStyle, at: 6, effectiveRange: nil) as? Int)
      == NSUnderlineStyle.single.rawValue
  )

  let reopenedTask = try #require(AgentNoteMutationEngine.tasks(in: completedNote.body).first)
  let reopened = try AgentNoteMutationEngine.setTaskState(
    reopenedTask,
    completed: false,
    in: completedNote.body
  )
  let reopenedNote = try AgentRichTextMutator.applying(
    reopened,
    operation: .setTaskState,
    to: completedNote,
    preferences: .init()
  )
  let reopenedText = try attributed(reopenedNote)
  #expect(
    (reopenedText.attribute(.strikethroughStyle, at: 6, effectiveRange: nil) as? Int ?? 0) == 0
  )
  #expect(
    (reopenedText.attribute(.underlineStyle, at: 6, effectiveRange: nil) as? Int)
      == NSUnderlineStyle.single.rawValue
  )
}

@Test @MainActor func renamingCompletedTaskReappliesStrikeOnlyToContent() throws {
  let source = NSMutableAttributedString(string: "    ● Finished")
  source.addAttribute(
    .strikethroughStyle,
    value: NSUnderlineStyle.single.rawValue,
    range: NSRange(location: 6, length: "Finished".utf16.count)
  )
  let note = Note(body: source.string, richTextRTF: try rtf(source))
  let task = try #require(AgentNoteMutationEngine.tasks(in: note.body).first)
  let draft = try AgentNoteMutationEngine.renameTask(
    task,
    text: "Renamed",
    in: note.body
  )

  let result = try AgentRichTextMutator.applying(
    draft,
    operation: .renameTask,
    to: note,
    preferences: .init()
  )
  let decoded = try attributed(result)

  #expect(decoded.string == "    ● Renamed")
  #expect(
    (decoded.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int ?? 0) == 0
  )
  #expect(
    (decoded.attribute(.strikethroughStyle, at: 4, effectiveRange: nil) as? Int ?? 0) == 0
  )
  #expect(
    (decoded.attribute(.strikethroughStyle, at: 6, effectiveRange: nil) as? Int)
      == NSUnderlineStyle.single.rawValue
  )
}

@Test @MainActor func renamingOpenTaskLeavesItsContentUnstruck() throws {
  let source = NSMutableAttributedString(string: "    ○ Open")
  let note = Note(body: source.string, richTextRTF: try rtf(source))
  let task = try #require(AgentNoteMutationEngine.tasks(in: note.body).first)
  let draft = try AgentNoteMutationEngine.renameTask(
    task,
    text: "Still open",
    in: note.body
  )

  let result = try AgentRichTextMutator.applying(
    draft,
    operation: .renameTask,
    to: note,
    preferences: .init()
  )
  let decoded = try attributed(result)

  #expect(decoded.string == "    ○ Still open")
  #expect(
    (decoded.attribute(.strikethroughStyle, at: 6, effectiveRange: nil) as? Int ?? 0) == 0
  )
}

@Test @MainActor func removingTaskPreservesAdjacentRichText() throws {
  let source = NSMutableAttributedString(string: "○ Remove\n○ Keep")
  source.addAttribute(.foregroundColor, value: NSColor.blue, range: NSRange(location: 9, length: 6))
  let note = Note(body: source.string, richTextRTF: try rtf(source))
  let task = try #require(AgentNoteMutationEngine.tasks(in: note.body).first)
  let draft = try AgentNoteMutationEngine.removeTask(task, in: note.body)

  let result = try AgentRichTextMutator.applying(
    draft,
    operation: .removeTask,
    to: note,
    preferences: .init()
  )
  let decoded = try attributed(result)

  #expect(decoded.string == "○ Keep")
  #expect(decoded.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .blue)
}

@Test @MainActor func relocatedUndoMutatesOnlyResolvedAttributedRun() throws {
  let original = "Left\nTarget\nRight"
  let forward = try AgentNoteMutationEngine.replaceLines(
    in: original,
    startLine: 2,
    endLine: 2,
    expectedTextSHA256:
      "978354db0c00fc78c3a5524f462a73bc425df3fb2767e51a5f46352ae26ae6f9",
    replacement: "Shared"
  )
  let body = "Shared\n" + forward.body
  let source = NSMutableAttributedString(string: body)
  source.addAttribute(.foregroundColor, value: NSColor.red, range: NSRange(location: 0, length: 6))
  let resolvedLocation = "Shared\nLeft\n".utf16.count
  source.addAttribute(
    .foregroundColor,
    value: NSColor.blue,
    range: NSRange(location: resolvedLocation, length: 6)
  )
  let note = Note(body: body, richTextRTF: try rtf(source), revision: 8)
  let undo = try AgentUndoEngine.draft(inverting: forward.patch, in: body)

  let result = try AgentRichTextMutator.applying(
    undo,
    operation: .undoChange,
    to: note,
    preferences: .init()
  )
  let decoded = try attributed(result)

  #expect(decoded.string == "Shared\nLeft\nTarget\nRight")
  #expect(decoded.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .red)
}

@Test @MainActor func genericUndoDoesNotNormalizeChecklistFormatting() throws {
  let original = "● Done"
  let forward = try AgentNoteMutationEngine.replaceLines(
    in: original,
    startLine: 1,
    endLine: 1,
    expectedTextSHA256:
      "f2ccae298380b0f0001fbc532e6ae44d8cafae5ab2f1994429d886af1ad47a42",
    replacement: "● Changed"
  )
  let source = NSAttributedString(string: forward.body)
  let note = Note(body: forward.body, richTextRTF: try rtf(source), revision: 2)
  let undo = try AgentUndoEngine.draft(inverting: forward.patch, in: note.body)

  let result = try AgentRichTextMutator.applying(
    undo,
    operation: .undoChange,
    to: note,
    preferences: .init()
  )
  let decoded = try attributed(result)

  #expect(decoded.string == original)
  #expect(
    (decoded.attribute(.strikethroughStyle, at: 2, effectiveRange: nil)
      as? Int ?? 0) == 0
  )
}

@Test @MainActor func staleRTFSidecarIsRejectedWithoutProducingAResult() throws {
  let stale = NSAttributedString(string: "Different")
  let note = Note(body: "Expected", richTextRTF: try rtf(stale))
  let draft = try AgentNoteMutationEngine.append(text: "Added", to: note.body)

  #expect(throws: AgentWorkspaceError(code: .motesUnavailable)) {
    try AgentRichTextMutator.applying(
      draft,
      operation: .appendText,
      to: note,
      preferences: .init()
    )
  }
}

@Test @MainActor func newlineMismatchBetweenBodyAndRTFIsRejectedExactly() throws {
  let note = Note(
    body: "First\r\nSecond",
    richTextRTF: try rtf(NSAttributedString(string: "First\nSecond"))
  )
  let draft = try AgentNoteMutationEngine.append(text: "Added", to: note.body)

  #expect(throws: AgentWorkspaceError(code: .motesUnavailable)) {
    try AgentRichTextMutator.applying(
      draft,
      operation: .appendText,
      to: note,
      preferences: .init()
    )
  }
}

@MainActor
private func rtf(_ value: NSAttributedString) throws -> Data {
  try value.data(
    from: NSRange(location: 0, length: value.length),
    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
  )
}

@MainActor
private func attributed(_ note: Note) throws -> NSAttributedString {
  try NSAttributedString(
    data: #require(note.richTextRTF),
    options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: nil
  )
}
