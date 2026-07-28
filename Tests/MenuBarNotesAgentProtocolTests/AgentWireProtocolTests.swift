import Foundation
import MenuBarNotesAgentProtocol
import MenuBarNotesCore
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
    requestID: requestID,
    result: .sharedNotes(notes: [])
  )
  let failure = AgentWireResponse.failure(
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

@Test func endpointHasOneCanonicalApplicationSupportPath() {
  let support = AgentBridgeEndpoint.applicationSupportURL().path
  let socket = AgentBridgeEndpoint.socketURL().path

  #expect(support.hasSuffix("/Application Support/MenuBarNotes"))
  #expect(socket == support + "/AgentBridge/motes.sock")
}

private func makeRequest(requestID: UUID = UUID()) -> AgentWireRequest {
  AgentWireRequest(
    requestID: requestID,
    profileID: UUID(),
    credentialBase64: Data(repeating: 7, count: 32).base64EncodedString(),
    command: .listSharedNotes
  )
}
