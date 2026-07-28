import Foundation
import Testing

@testable import MenuBarNotesCore

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
