import Foundation
import Testing

@testable import FleckCore

@Test func everyAgentCommandRoundTripsWithStableCaseName() throws {
  let noteID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  let operationID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
  let changeID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
  let context = AgentWriteContext(
    noteID: noteID,
    expectedRevision: 7,
    operationID: operationID
  )
  let commands: [(String, AgentWorkspaceCommand)] = [
    ("getCapabilities", .getCapabilities),
    ("listSharedNotes", .listSharedNotes),
    (
      "readNote",
      .readNote(
        request: .init(noteID: noteID, startLine: 2, maxLines: 20)
      )
    ),
    (
      "appendText",
      .appendText(request: .init(context: context, text: "Append"))
    ),
    (
      "insertText",
      .insertText(
        request: .init(context: context, beforeLine: 3, text: "Insert")
      )
    ),
    (
      "replaceLines",
      .replaceLines(
        request: .init(
          context: context,
          startLine: 2,
          endLine: 4,
          expectedTextSHA256: "observed",
          text: "Replace"
        )
      )
    ),
    ("listTasks", .listTasks(request: .init(noteID: noteID))),
    (
      "addTask",
      .addTask(
        request: .init(context: context, afterTaskHandle: "after", text: "Add")
      )
    ),
    (
      "renameTask",
      .renameTask(
        request: .init(context: context, taskHandle: "task", text: "Rename")
      )
    ),
    (
      "setTaskState",
      .setTaskState(
        request: .init(context: context, taskHandle: "task", completed: true)
      )
    ),
    (
      "removeTask",
      .removeTask(request: .init(context: context, taskHandle: "task"))
    ),
    ("listActivity", .listActivity),
    (
      "undoChange",
      .undoChange(
        request: .init(
          changeID: changeID,
          expectedRevision: 7,
          operationID: operationID
        )
      )
    ),
  ]
  let encoder = JSONEncoder()
  let decoder = JSONDecoder()

  for (caseName, command) in commands {
    let data = try encoder.encode(command)
    let object = try #require(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    #expect(Set(object.keys) == [caseName])
    #expect(try decoder.decode(AgentWorkspaceCommand.self, from: data) == command)
    if case .getCapabilities = command {
      let text = String(decoding: data, as: UTF8.self)
      #expect(!text.contains(noteID.uuidString))
      #expect(!text.contains("body"))
    }
  }
}

@Test func everyAgentResponseRoundTrips() throws {
  let noteID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  let changeID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
  let profileID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
  let date = Date(timeIntervalSince1970: 100)
  let receipt = AgentWriteReceipt(
    changeID: changeID,
    noteID: noteID,
    previousRevision: 4,
    resultingRevision: 5,
    taskHandle: "updated"
  )
  let patch = AgentTextPatch(
    beforeText: "Before",
    afterText: "After",
    range: NSRange(location: 2, length: 6),
    prefixContext: "P",
    suffixContext: "S"
  )
  let responses: [AgentWorkspaceResponse] = [
    .capabilities(
      summary: AgentCapabilitySummary(
        grantRevision: 4,
        availableCapabilities: [.listNotes, .readNotes]
      )
    ),
    .sharedNotes(
      notes: [
        .init(
          noteID: noteID,
          title: "Note",
          revision: 5,
          modifiedAt: date
        )
      ]
    ),
    .note(
      page: .init(
        noteID: noteID,
        title: "Note",
        revision: 5,
        body: "Body",
        startLine: 1,
        endLine: 1,
        totalLineCount: 1,
        nextLine: nil,
        modifiedAt: date
      )
    ),
    .tasks(
      tasks: [
        .init(
          taskHandle: "task",
          text: "Do it",
          completed: false,
          line: 1,
          indentation: ""
        )
      ]
    ),
    .write(receipt: receipt),
    .activity(
      entries: [
        .init(
          changeID: changeID,
          noteID: noteID,
          noteTitle: "Note",
          actor: .integration(profileID: profileID, displayName: "Codex"),
          createdAt: date,
          operation: .appendText,
          patch: patch,
          previousRevision: 4,
          resultingRevision: 5,
          canUndo: true
        )
      ]
    ),
    .undo(receipt: receipt),
  ]
  let encoder = JSONEncoder()
  let decoder = JSONDecoder()

  for response in responses {
    let data = try encoder.encode(response)
    #expect(try decoder.decode(AgentWorkspaceResponse.self, from: data) == response)
  }
}

@Test func errorVocabularyIsExact() {
  #expect(
    AgentWorkspaceErrorCode.allCases.map(\.rawValue) == [
      "note_not_found",
      "permission_revoked",
      "revision_conflict",
      "task_handle_expired",
      "unsafe_undo",
      "fleck_unavailable",
      "write_too_large",
      "response_too_large",
      "invalid_operation",
      "invalid_payload",
      "internal_save_failure",
      "capability_denied",
      "protocol_version_unsupported",
    ]
  )
}

@Test func activityActorsRoundTripAndCommitProofContainsNoBodyText() throws {
  let profileID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  let actors: [AgentActivityActor] = [
    .integration(profileID: profileID, displayName: "Codex"),
    .localUser,
  ]
  let encoder = JSONEncoder()
  let decoder = JSONDecoder()

  for actor in actors {
    let data = try encoder.encode(actor)
    #expect(try decoder.decode(AgentActivityActor.self, from: data) == actor)
  }

  let proof = AgentWorkspaceCommitProof(
    changeID: UUID(),
    noteID: UUID(),
    resultingRevision: 2,
    bodySHA256: "hash-only",
    actor: actors[0],
    operationID: UUID(),
    expiresAt: Date(timeIntervalSince1970: 200)
  )
  let data = try encoder.encode(proof)
  let json = String(decoding: data, as: UTF8.self)

  #expect(try decoder.decode(AgentWorkspaceCommitProof.self, from: data) == proof)
  #expect(!json.contains("beforeText"))
  #expect(!json.contains("afterText"))
  #expect(!json.contains("body\":"))
}

@Test func appendUsesParagraphBoundaryAndBuildsPatch() throws {
  let draft = try AgentNoteMutationEngine.append(
    text: "Agent update",
    to: "Existing",
    maximumBytes: 65_536
  )

  #expect(draft.body == "Existing\n\nAgent update")
  #expect(draft.patch.beforeText == "")
  #expect(draft.patch.afterText == "\n\nAgent update")
  #expect(draft.patch.range == NSRange(location: 8, length: 0))
  #expect(draft.patch.prefixContext == "Existing")
  #expect(draft.patch.suffixContext == "")
}

@Test func commandTextNormalizesNewlinesWithoutRewritingStoredBodies() throws {
  let appended = try AgentNoteMutationEngine.append(
    text: "A\r\nB\rC",
    to: "Existing\rLine",
    maximumBytes: 65_536
  )
  let inserted = try AgentNoteMutationEngine.insert(
    text: "A\r\nB",
    beforeLine: 2,
    in: "One\rTwo",
    maximumBytes: 65_536
  )
  let replaced = try AgentNoteMutationEngine.replaceLines(
    in: "One\r\nTwo",
    startLine: 2,
    endLine: 2,
    expectedTextSHA256:
      "94a72c074cfe574742c9e99e863322f73feff82981d065ff65a0308f44f19f62",
    replacement: "A\rB",
    maximumBytes: 65_536
  )

  #expect(appended.body == "Existing\rLine\n\nA\nB\nC")
  #expect(inserted.body == "One\rA\nB\nTwo")
  #expect(replaced.body == "One\r\nA\nB")
}

@Test func insertionUsesOneBasedLineBoundaries() throws {
  let atStart = try AgentNoteMutationEngine.insert(
    text: "Zero",
    beforeLine: 1,
    in: "One\nTwo",
    maximumBytes: 65_536
  )
  let atEnd = try AgentNoteMutationEngine.insert(
    text: "Three",
    beforeLine: 3,
    in: "One\nTwo",
    maximumBytes: 65_536
  )
  let intoEmpty = try AgentNoteMutationEngine.insert(
    text: "Only",
    beforeLine: 1,
    in: "",
    maximumBytes: 65_536
  )

  #expect(atStart.body == "Zero\nOne\nTwo")
  #expect(atStart.patch.range == NSRange(location: 0, length: 0))
  #expect(atStart.patch.afterText == "Zero\n")
  #expect(atEnd.body == "One\nTwo\nThree")
  #expect(atEnd.patch.range == NSRange(location: 7, length: 0))
  #expect(atEnd.patch.afterText == "\nThree")
  #expect(intoEmpty.body == "Only")
  #expect(intoEmpty.patch.range == NSRange(location: 0, length: 0))
  #expect(intoEmpty.patch.afterText == "Only")
}

@Test func insertionRejectsOutOfBoundsLines() {
  for line in [0, 4] {
    #expect(throws: AgentWorkspaceError.self) {
      try AgentNoteMutationEngine.insert(
        text: "No",
        beforeLine: line,
        in: "One\nTwo",
        maximumBytes: 65_536
      )
    }
  }
  #expect(throws: AgentWorkspaceError.self) {
    try AgentNoteMutationEngine.insert(
      text: "No",
      beforeLine: 2,
      in: "",
      maximumBytes: 65_536
    )
  }
}

@Test func replaceUsesOneBasedInclusiveLinesAndExactUTF16Range() throws {
  let draft = try AgentNoteMutationEngine.replaceLines(
    in: "😀 One\nTwo\nThree",
    startLine: 2,
    endLine: 3,
    expectedTextSHA256:
      "df5bec8f75db4b6d25c5f32b904fb8d0faca846071d8d4a8df7341d591ae5a9b",
    replacement: "Changed",
    maximumBytes: 65_536
  )

  #expect(draft.body == "😀 One\nChanged")
  #expect(draft.patch.beforeText == "Two\nThree")
  #expect(draft.patch.afterText == "Changed")
  #expect(draft.patch.range == NSRange(location: 7, length: 9))
}

@Test func replaceAllowsTheSingleValidationLineInAnEmptyBody() throws {
  let draft = try AgentNoteMutationEngine.replaceLines(
    in: "",
    startLine: 1,
    endLine: 1,
    expectedTextSHA256:
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    replacement: "Now present",
    maximumBytes: 65_536
  )

  #expect(draft.body == "Now present")
  #expect(draft.patch.range == NSRange(location: 0, length: 0))
}

@Test func replaceRejectsWrongObservedHash() {
  #expect(throws: AgentWorkspaceError.self) {
    try AgentNoteMutationEngine.replaceLines(
      in: "One\nTwo\nThree",
      startLine: 2,
      endLine: 2,
      expectedTextSHA256: "wrong",
      replacement: "Changed",
      maximumBytes: 65_536
    )
  }
}

@Test func replacementRejectsEveryInvalidInclusiveRange() {
  let hash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

  for range in [(0, 1), (2, 1), (1, 3)] {
    #expect(throws: AgentWorkspaceError.self) {
      try AgentNoteMutationEngine.replaceLines(
        in: "One\nTwo",
        startLine: range.0,
        endLine: range.1,
        expectedTextSHA256: hash,
        replacement: "No",
        maximumBytes: 65_536
      )
    }
  }
}

@Test func allTextMutationsEnforceUTF8PayloadBytesAfterNormalization() throws {
  let exactly64KiB = String(repeating: "é", count: 32_768)
  let over64KiB = exactly64KiB + "a"
  _ = try AgentNoteMutationEngine.append(
    text: exactly64KiB,
    to: "",
    maximumBytes: 65_536
  )
  _ = try AgentNoteMutationEngine.insert(
    text: exactly64KiB,
    beforeLine: 1,
    in: "",
    maximumBytes: 65_536
  )
  _ = try AgentNoteMutationEngine.replaceLines(
    in: "",
    startLine: 1,
    endLine: 1,
    expectedTextSHA256:
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    replacement: exactly64KiB,
    maximumBytes: 65_536
  )

  #expect(throws: AgentWorkspaceError.self) {
    try AgentNoteMutationEngine.append(
      text: over64KiB,
      to: "",
      maximumBytes: 65_536
    )
  }
  #expect(throws: AgentWorkspaceError.self) {
    try AgentNoteMutationEngine.insert(
      text: over64KiB,
      beforeLine: 1,
      in: "",
      maximumBytes: 65_536
    )
  }
  #expect(throws: AgentWorkspaceError.self) {
    try AgentNoteMutationEngine.replaceLines(
      in: "",
      startLine: 1,
      endLine: 1,
      expectedTextSHA256:
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      replacement: over64KiB,
      maximumBytes: 65_536
    )
  }

  let normalizedUnderLimit = String(repeating: "\r\n", count: 32_768)
  _ = try AgentNoteMutationEngine.append(
    text: normalizedUnderLimit,
    to: "",
    maximumBytes: 65_536
  )
}

@Test func generatedStructuralTextCountsTowardTheMutationLimit() throws {
  _ = try AgentNoteMutationEngine.append(
    text: String(repeating: "a", count: 65_534),
    to: "Existing",
    maximumBytes: 65_536
  )
  _ = try AgentNoteMutationEngine.insert(
    text: String(repeating: "a", count: 65_535),
    beforeLine: 1,
    in: "Existing",
    maximumBytes: 65_536
  )
  _ = try AgentNoteMutationEngine.addTask(
    text: String(repeating: "a", count: 65_532),
    after: nil,
    in: "",
    maximumBytes: 65_536
  )
  let nested = AgentNoteMutationEngine.tasks(in: "    ○ Existing")[0]
  _ = try AgentNoteMutationEngine.addTask(
    text: String(repeating: "a", count: 65_527),
    after: nested,
    in: "    ○ Existing",
    maximumBytes: 65_536
  )

  #expect(throws: AgentWorkspaceError.self) {
    try AgentNoteMutationEngine.append(
      text: String(repeating: "a", count: 65_535),
      to: "Existing",
      maximumBytes: 65_536
    )
  }
  #expect(throws: AgentWorkspaceError.self) {
    try AgentNoteMutationEngine.insert(
      text: String(repeating: "a", count: 65_536),
      beforeLine: 1,
      in: "Existing",
      maximumBytes: 65_536
    )
  }
  #expect(throws: AgentWorkspaceError.self) {
    try AgentNoteMutationEngine.addTask(
      text: String(repeating: "a", count: 65_533),
      after: nil,
      in: "",
      maximumBytes: 65_536
    )
  }
  #expect(throws: AgentWorkspaceError.self) {
    try AgentNoteMutationEngine.addTask(
      text: String(repeating: "a", count: 65_528),
      after: nested,
      in: "    ○ Existing",
      maximumBytes: 65_536
    )
  }
}

@Test func patchesBoundContextToThirtyTwoCharacters() throws {
  let prefix = String(repeating: "P", count: 40)
  let suffix = String(repeating: "S", count: 40)
  let draft = try AgentNoteMutationEngine.replaceLines(
    in: "\(prefix)\nTarget\n\(suffix)",
    startLine: 2,
    endLine: 2,
    expectedTextSHA256:
      "978354db0c00fc78c3a5524f462a73bc425df3fb2767e51a5f46352ae26ae6f9",
    replacement: "Changed",
    maximumBytes: 65_536
  )

  #expect(draft.patch.prefixContext.count == 32)
  #expect(draft.patch.suffixContext.count == 32)
  #expect(draft.patch.prefixContext == String(repeating: "P", count: 31) + "\n")
  #expect(draft.patch.suffixContext == "\n" + String(repeating: "S", count: 31))
}

@Test func checklistParsingAcceptsOnlyReadableFourSpaceIndentation() {
  let tasks = AgentNoteMutationEngine.tasks(
    in: """
    ○ First
        ● Nested
            ○ Deep
      ○ Two spaces
    \t○ Tabbed
    - Not a task
    """
  )

  #expect(tasks.map(\.line) == [1, 2, 3])
  #expect(tasks.map(\.text) == ["First", "Nested", "Deep"])
  #expect(tasks.map(\.completed) == [false, true, false])
  #expect(tasks.map(\.indentation) == ["", "    ", "        "])
}

@Test func checklistParsingDoesNotAddHiddenIDs() {
  let body = "○ First\n● Done"
  let tasks = AgentNoteMutationEngine.tasks(in: body)

  #expect(tasks.map(\.text) == ["First", "Done"])
  #expect(tasks.map(\.completed) == [false, true])
  #expect(body == "○ First\n● Done")
  #expect(!body.contains("<!--"))
}

@Test func taskAddRenameAndStatePreserveReadableStructure() throws {
  let body = "○ Top\n    ● Nested\nTail"
  let nested = try #require(AgentNoteMutationEngine.tasks(in: body).last)
  let added = try AgentNoteMutationEngine.addTask(
    text: "New",
    after: nested,
    in: body,
    maximumBytes: 65_536
  )
  let addedTask = try #require(added.updatedTask)

  #expect(added.body == "○ Top\n    ● Nested\n    ○ New\nTail")
  #expect(addedTask.indentation == "    ")
  #expect(!addedTask.completed)

  let renamed = try AgentNoteMutationEngine.renameTask(
    addedTask,
    text: "Renamed",
    in: added.body,
    maximumBytes: 65_536
  )
  let renamedTask = try #require(renamed.updatedTask)
  #expect(renamed.body == "○ Top\n    ● Nested\n    ○ Renamed\nTail")
  #expect(renamedTask.indentation == "    ")
  #expect(!renamedTask.completed)

  let completed = try AgentNoteMutationEngine.setTaskState(
    renamedTask,
    completed: true,
    in: renamed.body
  )
  #expect(completed.body == "○ Top\n    ● Nested\n    ● Renamed\nTail")
  #expect(completed.updatedTask?.text == "Renamed")
  #expect(completed.updatedTask?.indentation == "    ")
}

@Test func topLevelTaskAdditionHandlesEmptyAndNonemptyBodies() throws {
  let empty = try AgentNoteMutationEngine.addTask(
    text: "First",
    after: nil,
    in: "",
    maximumBytes: 65_536
  )
  let nonempty = try AgentNoteMutationEngine.addTask(
    text: "Task",
    after: nil,
    in: "Paragraph",
    maximumBytes: 65_536
  )

  #expect(empty.body == "○ First")
  #expect(nonempty.body == "Paragraph\n○ Task")
}

@Test func taskTextMutationsEnforceUTF8Limit() {
  let over64KiB = String(repeating: "é", count: 32_769)
  let task = AgentNoteMutationEngine.tasks(in: "○ Existing")[0]

  #expect(throws: AgentWorkspaceError.self) {
    try AgentNoteMutationEngine.addTask(
      text: over64KiB,
      after: nil,
      in: "",
      maximumBytes: 65_536
    )
  }
  #expect(throws: AgentWorkspaceError.self) {
    try AgentNoteMutationEngine.renameTask(
      task,
      text: over64KiB,
      in: "○ Existing",
      maximumBytes: 65_536
    )
  }
}

@Test func removingTasksDoesNotLeaveOrConsumeAdjacentLines() throws {
  let body = "○ First\nMiddle\n● Last"
  let first = AgentNoteMutationEngine.tasks(in: body)[0]
  let last = AgentNoteMutationEngine.tasks(in: body)[1]
  let removedFirst = try AgentNoteMutationEngine.removeTask(first, in: body)
  let removedLast = try AgentNoteMutationEngine.removeTask(last, in: body)
  let only = AgentNoteMutationEngine.tasks(in: "○ Only")[0]
  let removedOnly = try AgentNoteMutationEngine.removeTask(only, in: "○ Only")

  #expect(removedFirst.body == "Middle\n● Last")
  #expect(removedLast.body == "○ First\nMiddle")
  #expect(removedOnly.body == "")
}

@Test func taskEditsRejectAStaleOrNonTaskLocation() {
  let stale = AgentParsedTask(
    line: 2,
    indentation: "",
    completed: false,
    text: "Missing"
  )

  #expect(throws: AgentWorkspaceError.self) {
    try AgentNoteMutationEngine.renameTask(
      stale,
      text: "No",
      in: "○ Real\nPlain",
      maximumBytes: 65_536
    )
  }
  #expect(throws: AgentWorkspaceError.self) {
    try AgentNoteMutationEngine.setTaskState(stale, completed: true, in: "Plain")
  }
  #expect(throws: AgentWorkspaceError.self) {
    try AgentNoteMutationEngine.removeTask(stale, in: "Plain")
  }
}
