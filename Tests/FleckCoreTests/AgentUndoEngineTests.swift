import Foundation
import Testing

@testable import FleckCore

@Test func undoAppliesAtTheExactOriginalRange() throws {
  let draft = try AgentNoteMutationEngine.replaceLines(
    in: "One\nTwo\nThree",
    startLine: 2,
    endLine: 2,
    expectedTextSHA256:
      "94a72c074cfe574742c9e99e863322f73feff82981d065ff65a0308f44f19f62",
    replacement: "Changed",
    maximumBytes: 65_536
  )

  #expect(
    try AgentUndoEngine.inverting(draft.patch, in: draft.body)
      == "One\nTwo\nThree"
  )
}

@Test func undoFindsOneRelocatedContextQualifiedOccurrence() throws {
  let draft = try AgentNoteMutationEngine.replaceLines(
    in: "Prefix\nTarget\nSuffix",
    startLine: 2,
    endLine: 2,
    expectedTextSHA256:
      "978354db0c00fc78c3a5524f462a73bc425df3fb2767e51a5f46352ae26ae6f9",
    replacement: "Changed",
    maximumBytes: 65_536
  )
  let movedBody = "Header that shifts the range\n" + draft.body

  #expect(
    try AgentUndoEngine.inverting(draft.patch, in: movedBody)
      == "Header that shifts the range\nPrefix\nTarget\nSuffix"
  )
}

@Test func undoDraftReturnsTheResolvedRangeAndInversePatch() throws {
  let forward = try AgentNoteMutationEngine.replaceLines(
    in: "Alpha\nTarget\nOmega",
    startLine: 2,
    endLine: 2,
    expectedTextSHA256:
      "978354db0c00fc78c3a5524f462a73bc425df3fb2767e51a5f46352ae26ae6f9",
    replacement: "Changed",
    maximumBytes: 65_536
  )
  let currentBody = "Human preface\n" + forward.body
  let resolvedRange = NSRange(
    location: "Human preface\nAlpha\n".utf16.count,
    length: "Changed".utf16.count
  )

  let undo = try AgentUndoEngine.draft(
    inverting: forward.patch,
    in: currentBody
  )

  #expect(undo.body == "Human preface\nAlpha\nTarget\nOmega")
  #expect(
    undo.patch
      == AgentTextPatch(
        beforeText: "Changed",
        afterText: "Target",
        range: resolvedRange,
        prefixContext: "Human preface\nAlpha\n",
        suffixContext: "\nOmega"
      )
  )
}

@Test func undoDraftIdentifiesTheContextQualifiedRunAmongIdenticalText() throws {
  let forward = try AgentNoteMutationEngine.replaceLines(
    in: "Left\nTarget\nRight",
    startLine: 2,
    endLine: 2,
    expectedTextSHA256:
      "978354db0c00fc78c3a5524f462a73bc425df3fb2767e51a5f46352ae26ae6f9",
    replacement: "Shared",
    maximumBytes: 65_536
  )
  let currentBody = "Shared\n" + forward.body
  let resolvedRange = NSRange(
    location: "Shared\nLeft\n".utf16.count,
    length: "Shared".utf16.count
  )
  let styleKey = NSAttributedString.Key("fixtureStyle")
  let attributedBody = NSMutableAttributedString(string: currentBody)
  attributedBody.addAttribute(
    styleKey,
    value: "human",
    range: NSRange(location: 0, length: "Shared".utf16.count)
  )
  attributedBody.addAttribute(
    styleKey,
    value: "agent",
    range: resolvedRange
  )

  let undo = try AgentUndoEngine.draft(
    inverting: forward.patch,
    in: currentBody
  )

  #expect(undo.patch.range == resolvedRange)
  #expect(undo.patch.beforeText == "Shared")
  #expect(undo.patch.afterText == "Target")
  #expect(undo.patch.prefixContext == "Shared\nLeft\n")
  #expect(undo.patch.suffixContext == "\nRight")
  #expect(undo.body == "Shared\nLeft\nTarget\nRight")
  #expect(attributedBody.attribute(styleKey, at: 0, effectiveRange: nil) as? String == "human")
  #expect(
    attributedBody.attribute(
      styleKey,
      at: resolvedRange.location,
      effectiveRange: nil
    ) as? String == "agent"
  )

  attributedBody.replaceCharacters(
    in: undo.patch.range,
    with: undo.patch.afterText
  )
  #expect(attributedBody.string == undo.body)
  #expect(attributedBody.attribute(styleKey, at: 0, effectiveRange: nil) as? String == "human")
}

@Test func undoRejectsWhenReplacementIsGone() throws {
  let patch = AgentTextPatch(
    beforeText: "Before",
    afterText: "After",
    range: NSRange(location: 2, length: 6),
    prefixContext: "P",
    suffixContext: "S"
  )

  do {
    _ = try AgentUndoEngine.inverting(patch, in: "PChangedS")
    Issue.record("Expected unsafe undo")
  } catch let error as AgentWorkspaceError {
    #expect(error.code == .unsafeUndo)
  }
}

@Test func undoRejectsMultipleContextQualifiedOccurrences() {
  let patch = AgentTextPatch(
    beforeText: "Before",
    afterText: "After",
    range: NSRange(location: 100, length: 6),
    prefixContext: "P",
    suffixContext: "S"
  )

  #expect(throws: AgentWorkspaceError.self) {
    try AgentUndoEngine.inverting(patch, in: "PAfterS and PAfterS")
  }
}

@Test func undoNeverFuzzyMatchesSimilarReplacementText() {
  let patch = AgentTextPatch(
    beforeText: "Before",
    afterText: "After",
    range: NSRange(location: 1, length: 6),
    prefixContext: "P",
    suffixContext: "S"
  )

  #expect(throws: AgentWorkspaceError.self) {
    try AgentUndoEngine.inverting(patch, in: "PAftexS")
  }
}

@Test func undoRequiresAnExactUTF16ReplacementMatch() {
  let patch = AgentTextPatch(
    beforeText: "Before",
    afterText: "\u{00E9}",
    range: NSRange(location: 0, length: 1),
    prefixContext: "",
    suffixContext: ""
  )

  #expect(throws: AgentWorkspaceError.self) {
    try AgentUndoEngine.inverting(patch, in: "e\u{0301}")
  }
}

@Test func undoRequiresBothContextsForFallback() {
  let patch = AgentTextPatch(
    beforeText: "Before",
    afterText: "After",
    range: NSRange(location: 100, length: 6),
    prefixContext: "P",
    suffixContext: "S"
  )

  #expect(throws: AgentWorkspaceError.self) {
    try AgentUndoEngine.inverting(patch, in: "PAfterWrong")
  }
  #expect(throws: AgentWorkspaceError.self) {
    try AgentUndoEngine.inverting(patch, in: "WrongAfterS")
  }
}

@Test func exactOriginalMatchWinsEvenWhenAnotherSafeCandidateExists() throws {
  let patch = AgentTextPatch(
    beforeText: "Before",
    afterText: "After",
    range: NSRange(location: 1, length: 6),
    prefixContext: "P",
    suffixContext: "S"
  )

  #expect(
    try AgentUndoEngine.inverting(patch, in: "PAfterS and PAfterS")
      == "PBeforeS and PAfterS"
  )
}

@Test func undoRestoresADeletionAtAnEmptyReplacementRange() throws {
  let task = AgentNoteMutationEngine.tasks(in: "○ Keep\n● Remove")[1]
  let draft = try AgentNoteMutationEngine.removeTask(
    task,
    in: "○ Keep\n● Remove"
  )

  #expect(draft.patch.afterText == "")
  #expect(
    try AgentUndoEngine.inverting(draft.patch, in: draft.body)
      == "○ Keep\n● Remove"
  )
}

@Test func undoUsesUTF16LocationsWithoutSplittingUnicode() throws {
  let draft = try AgentNoteMutationEngine.replaceLines(
    in: "😀\nTarget\nEnd",
    startLine: 2,
    endLine: 2,
    expectedTextSHA256:
      "978354db0c00fc78c3a5524f462a73bc425df3fb2767e51a5f46352ae26ae6f9",
    replacement: "✅",
    maximumBytes: 65_536
  )

  #expect(draft.patch.range == NSRange(location: 3, length: 6))
  #expect(try AgentUndoEngine.inverting(draft.patch, in: draft.body) == "😀\nTarget\nEnd")
}

@Test func undoRestoresStoredNewlineSequencesExactly() throws {
  let original = "One\r\nTwo\rThree"
  let appended = try AgentNoteMutationEngine.append(
    text: "Agent\r\nUpdate",
    to: original,
    maximumBytes: 65_536
  )

  #expect(appended.body == original + "\n\nAgent\nUpdate")
  #expect(appended.patch.range == NSRange(location: 14, length: 0))
  #expect(try AgentUndoEngine.inverting(appended.patch, in: appended.body) == original)

  let replaced = try AgentNoteMutationEngine.replaceLines(
    in: original,
    startLine: 2,
    endLine: 3,
    expectedTextSHA256:
      "ce032d1a4fe8f9cea24fd385a1322b4eb82f9851cde5213b28561d06b98dd1f9",
    replacement: "Changed\r\nAgain",
    maximumBytes: 65_536
  )

  #expect(replaced.patch.beforeText == "Two\rThree")
  #expect(replaced.patch.afterText == "Changed\nAgain")
  #expect(replaced.body == "One\r\nChanged\nAgain")
  #expect(try AgentUndoEngine.inverting(replaced.patch, in: replaced.body) == original)
}

@Test func wholeBodyDeletionUndoRequiresTheBodyToRemainEmpty() throws {
  let task = AgentNoteMutationEngine.tasks(in: "○ Only")[0]
  let deletion = try AgentNoteMutationEngine.removeTask(task, in: "○ Only")

  #expect(deletion.body == "")
  #expect(deletion.patch.afterText == "")
  #expect(deletion.patch.prefixContext == "")
  #expect(deletion.patch.suffixContext == "")
  #expect(try AgentUndoEngine.inverting(deletion.patch, in: "") == "○ Only")
  #expect(throws: AgentWorkspaceError.self) {
    try AgentUndoEngine.inverting(deletion.patch, in: "Unrelated")
  }
}
