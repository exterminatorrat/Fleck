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
