import Foundation
import FleckAgentProtocol
import FleckCore
import Testing

@Test func agentWireRequestRoundTripsWithCorrelationAndVersion() throws {
  let request = makeRequest()
  var frame = try AgentWireFraming.encode(request)
  let decoded = try #require(
    AgentWireFraming.decodeFrame(AgentWireRequest.self, from: &frame)
  )

  #expect(decoded == request)
  #expect(decoded.protocolVersion == 1)
  #expect(frame.isEmpty)
}

@Test(arguments: [0, 2])
func agentWireRequestCarriesUnsupportedVersionsForServerRejection(
  _ version: Int
) throws {
  let request = AgentWireRequest(
    protocolVersion: version,
    requestID: UUID(),
    profileID: UUID(),
    credentialBase64: Data(repeating: 7, count: 32).base64EncodedString(),
    command: .listSharedNotes
  )
  var frame = try AgentWireFraming.encode(request)

  #expect(
    try AgentWireFraming.decodeFrame(
      AgentWireRequest.self,
      from: &frame
    )?.protocolVersion == version
  )
}

@Test func agentWireResponseCarriesVersionForClientValidation() throws {
  let response = AgentWireResponse.success(
    protocolVersion: 1,
    requestID: UUID(),
    result: .sharedNotes(notes: [])
  )
  let encoded = try JSONEncoder().encode(response)
  var object = try #require(
    JSONSerialization.jsonObject(with: encoded) as? [String: Any]
  )
  object["protocolVersion"] = 2
  let future = try JSONSerialization.data(withJSONObject: object)

  #expect(
    try JSONDecoder().decode(
      AgentWireResponse.self,
      from: future
    ).protocolVersion == 2
  )
}

@Test func agentWireResponseFactoriesCorrelateExclusivePayloads() throws {
  let requestID = UUID()
  let success = AgentWireResponse.success(
    protocolVersion: 1,
    requestID: requestID,
    result: .sharedNotes(notes: [])
  )
  let failure = AgentWireResponse.failure(
    protocolVersion: 1,
    requestID: requestID,
    error: AgentWorkspaceError(code: .invalidPayload)
  )

  #expect(success.protocolVersion == 1)
  #expect(success.requestID == requestID)
  #expect(success.result == .sharedNotes(notes: []))
  #expect(success.error == nil)
  #expect(failure.requestID == requestID)
  #expect(failure.result == nil)
  #expect(failure.error?.code == .invalidPayload)
}

@Test func agentWireFramingCanonicalizesEquivalentFailureBytes() async throws {
  let response = AgentWireResponse.failure(
    protocolVersion: 1,
    requestID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
    error: AgentWorkspaceError(code: .noteNotFound)
  )
  let frames = try await withThrowingTaskGroup(
    of: Data.self,
    returning: [Data].self
  ) { group in
    for _ in 0..<128 {
      group.addTask {
        try AgentWireFraming.encode(response)
      }
    }
    var frames: [Data] = []
    for try await frame in group {
      frames.append(frame)
    }
    return frames
  }

  #expect(Set(frames).count == 1)
}

@Test(arguments: [
  #"{"protocolVersion":1,"requestID":"00000000-0000-0000-0000-000000000001","result":{"sharedNotes":{"notes":[]}},"error":{"code":"invalid_payload"}}"#,
  #"{"protocolVersion":1,"requestID":"00000000-0000-0000-0000-000000000001"}"#,
])
func agentWireResponseRejectsNonexclusivePayloads(_ json: String) {
  #expect(throws: (any Error).self) {
    try JSONDecoder().decode(
      AgentWireResponse.self,
      from: Data(json.utf8)
    )
  }
}

@Test func fragmentedAndCoalescedFramesDecodeOneAtATime() throws {
  let first = makeRequest()
  let second = makeRequest(requestID: UUID())
  let firstFrame = try AgentWireFraming.encode(first)
  let secondFrame = try AgentWireFraming.encode(second)
  var fragmented = Data(firstFrame.prefix(3))

  #expect(
    try AgentWireFraming.decodeFrame(
      AgentWireRequest.self,
      from: &fragmented
    ) == nil
  )
  fragmented.append(firstFrame.dropFirst(3))
  fragmented.append(secondFrame)

  #expect(
    try AgentWireFraming.decodeFrame(
      AgentWireRequest.self,
      from: &fragmented
    ) == first
  )
  #expect(
    try AgentWireFraming.decodeFrame(
      AgentWireRequest.self,
      from: &fragmented
    ) == second
  )
  #expect(fragmented.isEmpty)
}

@Test(arguments: [0, AgentWireFraming.maximumFrameBytes + 1])
func invalidDeclaredFrameLengthsAreRejectedImmediately(_ length: Int) {
  var value = UInt32(length).bigEndian
  var buffer = withUnsafeBytes(of: &value) { Data($0) }

  #expect(throws: (any Error).self) {
    try AgentWireFraming.decodeFrame(
      AgentWireRequest.self,
      from: &buffer
    )
  }
  #expect(buffer.count == 4)
}

@Test func malformedJSONFrameIsRejected() {
  let payload = Data("{".utf8)
  var length = UInt32(payload.count).bigEndian
  var frame = withUnsafeBytes(of: &length) { Data($0) }
  frame.append(payload)

  #expect(throws: (any Error).self) {
    try AgentWireFraming.decodeFrame(
      AgentWireRequest.self,
      from: &frame
    )
  }
}

@Test func canonicalEndpointsUseFleckAndFleckSocket() {
  let support = AgentBridgeEndpoint.applicationSupportURL().path
  let socket = AgentBridgeEndpoint.socketURL().path

  #expect(support.hasSuffix("/Application Support/Fleck"))
  #expect(socket == support + "/AgentBridge/fleck.sock")
}

private func makeRequest(
  requestID: UUID = UUID(),
  protocolVersion: Int = 1
) -> AgentWireRequest {
  AgentWireRequest(
    protocolVersion: protocolVersion,
    requestID: requestID,
    profileID: UUID(),
    credentialBase64: Data(repeating: 7, count: 32).base64EncodedString(),
    command: .listSharedNotes
  )
}

@Suite("AgentWireProtocolV2Tests")
struct AgentWireProtocolV2Tests {
  @Test(arguments: [1, 2])
  func supportedVersionsRoundTrip(_ version: Int) throws {
    let request = AgentWireRequest(
      protocolVersion: version,
      requestID: UUID(),
      profileID: UUID(),
      credentialBase64: Data(repeating: 7, count: 32).base64EncodedString(),
      command: version == 1 ? .listSharedNotes : .getCapabilities
    )
    var frame = try AgentWireFraming.encode(request)

    #expect(
      try AgentWireFraming.decodeFrame(
        AgentWireRequest.self,
        from: &frame
      ) == request
    )
  }

  @Test func capabilityDiscoveryIsV2Only() {
    #expect(AgentWorkspaceCommand.listSharedNotes.isSupported(wireVersion: 1))
    #expect(AgentWorkspaceCommand.listSharedNotes.isSupported(wireVersion: 2))
    #expect(!AgentWorkspaceCommand.getCapabilities.isSupported(wireVersion: 1))
    #expect(AgentWorkspaceCommand.getCapabilities.isSupported(wireVersion: 2))
  }

  @Test func capabilityResponseIsV2Only() {
    let capabilities = AgentWorkspaceResponse.capabilities(
      summary: AgentCapabilitySummary(
        grantRevision: 4,
        availableCapabilities: [.listNotes]
      )
    )

    #expect(!capabilities.isSupported(wireVersion: 1))
    #expect(capabilities.isSupported(wireVersion: 2))
    #expect(
      AgentWorkspaceResponse.sharedNotes(notes: [])
        .isSupported(wireVersion: 1)
    )
  }

  @Test func everyCurrentCommandHasExplicitWireVersionContract() {
    let context = AgentWriteContext(
      noteID: UUID(),
      expectedRevision: 4,
      operationID: UUID()
    )
    let commands: [(String, AgentWorkspaceCommand)] = [
      ("listSharedNotes", .listSharedNotes),
      (
        "readNote",
        .readNote(request: .init(noteID: UUID(), startLine: 2, maxLines: 4))
      ),
      (
        "appendText",
        .appendText(request: .init(context: context, text: "append"))
      ),
      (
        "insertText",
        .insertText(
          request: .init(context: context, beforeLine: 2, text: "insert")
        )
      ),
      (
        "replaceLines",
        .replaceLines(
          request: .init(
            context: context,
            startLine: 2,
            endLine: 3,
            expectedTextSHA256: String(repeating: "a", count: 64),
            text: "replace"
          )
        )
      ),
      ("listTasks", .listTasks(request: .init(noteID: UUID()))),
      (
        "addTask",
        .addTask(
          request: .init(
            context: context,
            afterTaskHandle: "prior",
            text: "task"
          )
        )
      ),
      (
        "renameTask",
        .renameTask(
          request: .init(context: context, taskHandle: "task", text: "renamed")
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
            changeID: UUID(),
            expectedRevision: 4,
            operationID: UUID()
          )
        )
      ),
      ("getCapabilities", .getCapabilities),
    ]

    for version in [0, 1, 2, 3] {
      for (name, command) in commands {
        let expected = name == "getCapabilities"
          ? version == 2
          : version == 1 || version == 2
        #expect(command.isSupported(wireVersion: version) == expected)
      }
    }
  }

  @Test func everyCurrentResponseHasExplicitWireVersionContract() {
    let noteID = UUID()
    let changeID = UUID()
    let date = Date(timeIntervalSince1970: 100)
    let receipt = AgentWriteReceipt(
      changeID: changeID,
      noteID: noteID,
      previousRevision: 3,
      resultingRevision: 4,
      taskHandle: "task"
    )
    let patch = AgentTextPatch(
      beforeText: "before",
      afterText: "after",
      range: NSRange(location: 0, length: 6),
      prefixContext: "prefix",
      suffixContext: "suffix"
    )
    let activity = AgentActivitySummary(
      changeID: changeID,
      noteID: noteID,
      noteTitle: "Title",
      actor: .integration(profileID: UUID(), displayName: "Agent"),
      originatingActor: .localUser,
      createdAt: date,
      operation: .replaceLines,
      patch: patch,
      previousRevision: 3,
      resultingRevision: 4,
      canUndo: true
    )
    let responses: [(String, AgentWorkspaceResponse)] = [
      (
        "sharedNotes",
        .sharedNotes(
          notes: [
            AgentNoteSummary(
              noteID: noteID,
              title: "Title",
              revision: 4,
              modifiedAt: date
            )
          ]
        )
      ),
      (
        "note",
        .note(
          page: AgentNotePage(
            noteID: noteID,
            title: "Title",
            revision: 4,
            body: "Body",
            startLine: 1,
            endLine: 1,
            totalLineCount: 1,
            nextLine: nil,
            modifiedAt: date
          )
        )
      ),
      (
        "tasks",
        .tasks(
          tasks: [
            AgentTaskSummary(
              taskHandle: "task",
              text: "Task",
              completed: false,
              line: 1,
              indentation: ""
            )
          ]
        )
      ),
      ("write", .write(receipt: receipt)),
      ("activity", .activity(entries: [activity])),
      ("undo", .undo(receipt: receipt)),
      (
        "capabilities",
        .capabilities(
          summary: AgentCapabilitySummary(
            grantRevision: 4,
            availableCapabilities: [.listNotes]
          )
        )
      ),
    ]

    for version in [0, 1, 2, 3] {
      for (name, response) in responses {
        let expected = name == "capabilities"
          ? version == 2
          : version == 1 || version == 2
        #expect(response.isSupported(wireVersion: version) == expected)
      }
    }
  }

  @Test func strictDecodingRejectsUnknownFieldsInEveryCommandDTO() throws {
    let context = AgentWriteContext(
      noteID: UUID(),
      expectedRevision: 4,
      operationID: UUID()
    )
    let cases: [(AgentWorkspaceCommand, [[JSONPathComponent]])] = [
      (
        .readNote(request: .init(noteID: UUID(), startLine: 2, maxLines: 4)),
        [[.key("readNote"), .key("request")]]
      ),
      (
        .appendText(request: .init(context: context, text: "append")),
        [
          [.key("appendText"), .key("request")],
          [.key("appendText"), .key("request"), .key("context")],
        ]
      ),
      (
        .insertText(
          request: .init(context: context, beforeLine: 2, text: "insert")
        ),
        [
          [.key("insertText"), .key("request")],
          [.key("insertText"), .key("request"), .key("context")],
        ]
      ),
      (
        .replaceLines(
          request: .init(
            context: context,
            startLine: 2,
            endLine: 3,
            expectedTextSHA256: String(repeating: "a", count: 64),
            text: "replace"
          )
        ),
        [
          [.key("replaceLines"), .key("request")],
          [.key("replaceLines"), .key("request"), .key("context")],
        ]
      ),
      (
        .listTasks(request: .init(noteID: UUID())),
        [[.key("listTasks"), .key("request")]]
      ),
      (
        .addTask(
          request: .init(context: context, afterTaskHandle: "prior", text: "task")
        ),
        [
          [.key("addTask"), .key("request")],
          [.key("addTask"), .key("request"), .key("context")],
        ]
      ),
      (
        .renameTask(
          request: .init(context: context, taskHandle: "task", text: "renamed")
        ),
        [
          [.key("renameTask"), .key("request")],
          [.key("renameTask"), .key("request"), .key("context")],
        ]
      ),
      (
        .setTaskState(
          request: .init(context: context, taskHandle: "task", completed: true)
        ),
        [
          [.key("setTaskState"), .key("request")],
          [.key("setTaskState"), .key("request"), .key("context")],
        ]
      ),
      (
        .removeTask(request: .init(context: context, taskHandle: "task")),
        [
          [.key("removeTask"), .key("request")],
          [.key("removeTask"), .key("request"), .key("context")],
        ]
      ),
      (
        .undoChange(
          request: .init(
            changeID: UUID(),
            expectedRevision: 4,
            operationID: UUID()
          )
        ),
        [[.key("undoChange"), .key("request")]]
      ),
    ]

    for (command, paths) in cases {
      for path in paths {
        let data = try dataByAddingUnknownField(
          to: command,
          at: path
        )
        #expect(throws: (any Error).self) {
          try JSONDecoder().decode(AgentWorkspaceCommand.self, from: data)
        }
      }
    }
  }

  @Test func strictDecodingRejectsUnknownFieldsInEveryResponseDTO() throws {
    let noteID = UUID()
    let changeID = UUID()
    let date = Date(timeIntervalSince1970: 100)
    let receipt = AgentWriteReceipt(
      changeID: changeID,
      noteID: noteID,
      previousRevision: 3,
      resultingRevision: 4,
      taskHandle: "task"
    )
    let patch = AgentTextPatch(
      beforeText: "before",
      afterText: "after",
      range: NSRange(location: 0, length: 6),
      prefixContext: "prefix",
      suffixContext: "suffix"
    )
    let activityIntegration = AgentActivitySummary(
      changeID: changeID,
      noteID: noteID,
      noteTitle: "Title",
      actor: .integration(profileID: UUID(), displayName: "Agent"),
      originatingActor: .integration(profileID: UUID(), displayName: "Origin"),
      createdAt: date,
      operation: .replaceLines,
      patch: patch,
      previousRevision: 3,
      resultingRevision: 4,
      canUndo: true
    )
    let activityLocal = AgentActivitySummary(
      changeID: changeID,
      noteID: noteID,
      noteTitle: "Title",
      actor: .localUser,
      originatingActor: .localUser,
      createdAt: date,
      operation: .replaceLines,
      patch: patch,
      previousRevision: 3,
      resultingRevision: 4,
      canUndo: true
    )
    let cases: [(AgentWorkspaceResponse, [[JSONPathComponent]])] = [
      (
        .sharedNotes(
          notes: [
            AgentNoteSummary(
              noteID: noteID,
              title: "Title",
              revision: 4,
              modifiedAt: date
            )
          ]
        ),
        [[.key("sharedNotes"), .key("notes"), .index(0)]]
      ),
      (
        .note(
          page: AgentNotePage(
            noteID: noteID,
            title: "Title",
            revision: 4,
            body: "Body",
            startLine: 1,
            endLine: 1,
            totalLineCount: 1,
            nextLine: nil,
            modifiedAt: date
          )
        ),
        [[.key("note"), .key("page")]]
      ),
      (
        .tasks(
          tasks: [
            AgentTaskSummary(
              taskHandle: "task",
              text: "Task",
              completed: false,
              line: 1,
              indentation: ""
            )
          ]
        ),
        [[.key("tasks"), .key("tasks"), .index(0)]]
      ),
      (
        .write(receipt: receipt),
        [[.key("write"), .key("receipt")]]
      ),
      (
        .undo(receipt: receipt),
        [[.key("undo"), .key("receipt")]]
      ),
      (
        .activity(entries: [activityIntegration]),
        [
          [.key("activity"), .key("entries"), .index(0)],
          [
            .key("activity"), .key("entries"), .index(0), .key("actor"),
            .key("integration"),
          ],
          [
            .key("activity"), .key("entries"), .index(0),
            .key("originatingActor"), .key("integration"),
          ],
          [.key("activity"), .key("entries"), .index(0), .key("patch")],
          [
            .key("activity"), .key("entries"), .index(0), .key("patch"),
            .key("range"), .appendUnknown,
          ],
        ]
      ),
      (
        .activity(entries: [activityLocal]),
        [
          [
            .key("activity"), .key("entries"), .index(0), .key("actor"),
            .key("localUser"),
          ],
          [
            .key("activity"), .key("entries"), .index(0),
            .key("originatingActor"), .key("localUser"),
          ],
        ]
      ),
      (
        .capabilities(
          summary: AgentCapabilitySummary(
            grantRevision: 4,
            availableCapabilities: [.listNotes]
          )
        ),
        [[.key("capabilities"), .key("summary")]]
      ),
    ]

    for (response, paths) in cases {
      for path in paths {
        let data = try dataByAddingUnknownField(
          to: response,
          at: path
        )
        #expect(throws: (any Error).self) {
          try JSONDecoder().decode(AgentWorkspaceResponse.self, from: data)
        }
      }
    }
  }

  @Test func strictDecodingRejectsMissingAndExtraCasePayloadKeys() {
    let commandPayloads = [
      Data(#"{"readNote":{}}"#.utf8),
      Data(#"{"readNote":{"unexpected":true}}"#.utf8),
    ]
    for data in commandPayloads {
      #expect(throws: (any Error).self) {
        try JSONDecoder().decode(AgentWorkspaceCommand.self, from: data)
      }
    }

    let responsePayloads = [
      Data(#"{"note":{}}"#.utf8),
      Data(#"{"note":{"unexpected":true}}"#.utf8),
    ]
    for data in responsePayloads {
      #expect(throws: (any Error).self) {
        try JSONDecoder().decode(AgentWorkspaceResponse.self, from: data)
      }
    }
  }

  @Test(arguments: [1, 2])
  func responsesEchoAcceptedRequestVersion(_ version: Int) {
    let requestID = UUID()
    let success = AgentWireResponse.success(
      protocolVersion: version,
      requestID: requestID,
      result: version == 2
        ? .capabilities(
          summary: AgentCapabilitySummary(
            grantRevision: 4,
            availableCapabilities: [.listNotes]
          )
        )
        : .sharedNotes(notes: [])
    )
    let failure = AgentWireResponse.failure(
      protocolVersion: version,
      requestID: requestID,
      error: AgentWorkspaceError(code: .invalidPayload)
    )

    #expect(success.protocolVersion == version)
    #expect(failure.protocolVersion == version)
  }

  @Test func capabilitySummaryEncodingIsSortedAndRejectsDuplicates() throws {
    let summary = AgentCapabilitySummary(
      grantRevision: 4,
      availableCapabilities: [.writeNotes, .listNotes]
    )
    let encoded = try AgentWireFraming.encode(
      AgentWireResponse.success(
        protocolVersion: 2,
        requestID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        result: .capabilities(summary: summary)
      )
    )
    let json = String(decoding: encoded.dropFirst(4), as: UTF8.self)
    #expect(json.contains(#"["notes.list","notes.write"]"#))

    let duplicate = Data(
      #"{"protocolVersion":2,"requestID":"00000000-0000-0000-0000-000000000001","result":{"capabilities":{"summary":{"grantRevision":4,"availableCapabilities":["notes.list","notes.list"]}}}}"#.utf8
    )
    var frame = withLengthPrefix(duplicate)
    #expect(throws: (any Error).self) {
      _ = try AgentWireFraming.decodeFrame(
        AgentWireResponse.self,
        from: &frame
      )
    }
  }

  @Test func strictDecodingRejectsUnknownEnvelopeAndCaseFields() throws {
    let requestData = try JSONEncoder().encode(
      AgentWireRequest(
        protocolVersion: 2,
        requestID: UUID(),
        profileID: UUID(),
        credentialBase64: Data(repeating: 7, count: 32).base64EncodedString(),
        command: .getCapabilities
      )
    )
    var requestObject = try #require(
      JSONSerialization.jsonObject(with: requestData) as? [String: Any]
    )
    requestObject["unexpected"] = true
    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(
        AgentWireRequest.self,
        from: JSONSerialization.data(withJSONObject: requestObject)
      )
    }

    let command = Data(#"{"getCapabilities":{"unexpected":{}}}"#.utf8)
    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(AgentWorkspaceCommand.self, from: command)
    }
  }

  private func withLengthPrefix(_ payload: Data) -> Data {
    var length = UInt32(payload.count).bigEndian
    var frame = withUnsafeBytes(of: &length) { Data($0) }
    frame.append(payload)
    return frame
  }
}

private enum JSONPathComponent {
  case key(String)
  case index(Int)
  case appendUnknown
}

private enum StrictDecodingTestError: Error {
  case invalidJSONPath
}

private func dataByAddingUnknownField<T: Encodable>(
  to value: T,
  at path: [JSONPathComponent]
) throws -> Data {
  var object: Any = try JSONSerialization.jsonObject(
    with: JSONEncoder().encode(value)
  )
  try addUnknownField(to: &object, path: path[...])
  return try JSONSerialization.data(
    withJSONObject: object,
    options: [.sortedKeys]
  )
}

private func addUnknownField(
  to value: inout Any,
  path: ArraySlice<JSONPathComponent>
) throws {
  guard let component = path.first else {
    guard var object = value as? [String: Any] else {
      throw StrictDecodingTestError.invalidJSONPath
    }
    object["unexpected"] = true
    value = object
    return
  }

  switch component {
  case .key(let key):
    guard
      var object = value as? [String: Any],
      var child = object[key]
    else {
      throw StrictDecodingTestError.invalidJSONPath
    }
    try addUnknownField(to: &child, path: path.dropFirst())
    object[key] = child
    value = object
  case .index(let index):
    guard var array = value as? [Any], array.indices.contains(index) else {
      throw StrictDecodingTestError.invalidJSONPath
    }
    var child = array[index]
    try addUnknownField(to: &child, path: path.dropFirst())
    array[index] = child
    value = array
  case .appendUnknown:
    guard var array = value as? [Any], path.dropFirst().isEmpty else {
      throw StrictDecodingTestError.invalidJSONPath
    }
    array.append(["unexpected": true])
    value = array
  }
}
