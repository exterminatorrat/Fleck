import FleckAgentProtocol
import FleckCore
import Foundation
import Testing

@Suite("Agent event wire protocol")
struct AgentEventWireProtocolTests {
  private let requestID = "00000000-0000-4000-8000-000000000201"
  private let profileID = "00000000-0000-4000-8000-000000000202"

  @Test func eventCommandsRoundTripAsVersionTwoAndCannotWidenVersionOne() throws {
    let versionTwo = try? decodeRequest(protocolVersion: 2)
    #expect(versionTwo != nil)
    guard let versionTwo else { return }
    #expect(versionTwo.protocolVersion == 2)
    #expect(try JSONEncoder().encode(versionTwo.command).contains(Data("listEvents".utf8)))
    #expect(versionTwo.command.isSupported(wireVersion: 2))
    #expect(!versionTwo.command.isSupported(wireVersion: 1))

    let versionOne = try? decodeRequest(protocolVersion: 1)
    #expect(versionOne != nil)
    guard let versionOne else { return }
    #expect(versionOne.protocolVersion == 1)
    #expect(!versionOne.command.isSupported(wireVersion: versionOne.protocolVersion))
  }

  @Test func eventResponsesUseExclusiveStrictFramesAndPreserveLegacyFixtures() throws {
    let responseData = Data(
      #"{"protocolVersion":2,"requestID":"\#(requestID)","result":{"eventUnsubscribed":{}}}"#.utf8
    )
    let response = try? JSONDecoder().decode(AgentWireResponse.self, from: responseData)
    #expect(response != nil)
    guard let response else { return }
    #expect(response.requestID.uuidString.lowercased() == requestID)
    #expect(response.result?.isSupported(wireVersion: 2) == true)
    #expect(response.result?.isSupported(wireVersion: 1) == false)

    var framed = try AgentWireFraming.encode(response)
    let decoded = try #require(AgentWireFraming.decodeFrame(AgentWireResponse.self, from: &framed))
    #expect(decoded == response)
    #expect(framed.isEmpty)

    let mixed = Data(
      #"{"protocolVersion":2,"requestID":"\#(requestID)","result":{"eventUnsubscribed":{}},"error":{"code":"invalid_operation"}}"#
        .utf8
    )
    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(AgentWireResponse.self, from: mixed)
    }

    let oldCommand = String(
      decoding: try JSONEncoder().encode(AgentWorkspaceCommand.listSharedNotes),
      as: UTF8.self
    )
    let oldResponse = String(
      decoding: try JSONEncoder().encode(AgentWorkspaceResponse.sharedNotes(notes: [])),
      as: UTF8.self
    )
    #expect(oldCommand == #"{"listSharedNotes":{}}"#)
    #expect(oldResponse == #"{"sharedNotes":{"notes":[]}}"#)
  }

  @Test func verifiedSubscriptionResponseRoundTripsOnlyForVersionTwo() throws {
    let wireRequestID = try #require(UUID(uuidString: requestID))
    let result = AgentWorkspaceResponse.verifiedEventSubscription(
      receipt: AgentEventVerifiedSubscriptionReceipt(
        subscriptionID: "evt_" + String(repeating: "b", count: 64),
        refreshBefore: Date(timeIntervalSince1970: 1_800_000_000),
        revision: 2,
        grantRevision: 3
      )
    )
    let versionTwo = AgentWireResponse.success(
      protocolVersion: 2,
      requestID: wireRequestID,
      result: result
    )
    let decodedVersionTwo = try JSONDecoder().decode(
      AgentWireResponse.self,
      from: JSONEncoder().encode(versionTwo)
    )
    #expect(decodedVersionTwo == versionTwo)
    #expect(decodedVersionTwo.result?.isSupported(wireVersion: 2) == true)

    let versionOne = AgentWireResponse.success(
      protocolVersion: 1,
      requestID: wireRequestID,
      result: result
    )
    let decodedVersionOne = try JSONDecoder().decode(
      AgentWireResponse.self,
      from: JSONEncoder().encode(versionOne)
    )
    #expect(decodedVersionOne.result?.isSupported(wireVersion: 1) == false)
  }

  @Test func eventFailureFramesAreAcceptedOnlyForVersionTwo() throws {
    let wireRequestID = try #require(UUID(uuidString: requestID))
    let failures = [
      AgentWorkspaceError.callbackEndpointFailure(reason: .challengeFailed),
      AgentWorkspaceError.signingKeyRotationInProgress(retryAfterMs: 90_000),
    ]

    for failure in failures {
      let versionTwo = AgentWireResponse.failure(
        protocolVersion: 2,
        requestID: wireRequestID,
        error: failure
      )
      let encodedVersionTwo = try JSONEncoder().encode(versionTwo)
      #expect(
        try JSONDecoder().decode(AgentWireResponse.self, from: encodedVersionTwo) == versionTwo
      )

      for protocolVersion in [1, 3] {
        let incompatible = AgentWireResponse.failure(
          protocolVersion: protocolVersion,
          requestID: wireRequestID,
          error: failure
        )
        #expect(throws: (any Error).self) { try JSONEncoder().encode(incompatible) }

        var object = try #require(
          JSONSerialization.jsonObject(with: encodedVersionTwo) as? [String: Any]
        )
        object["protocolVersion"] = protocolVersion
        let incompatibleJSON = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: (any Error).self) {
          try JSONDecoder().decode(AgentWireResponse.self, from: incompatibleJSON)
        }
      }
    }

    let legacyFailure = AgentWireResponse.failure(
      protocolVersion: 3,
      requestID: wireRequestID,
      error: AgentWorkspaceError(code: .protocolVersionUnsupported)
    )
    let encodedLegacyFailure = try JSONEncoder().encode(legacyFailure)
    #expect(
      try JSONDecoder().decode(AgentWireResponse.self, from: encodedLegacyFailure) == legacyFailure
    )

    let versionOneFailure = AgentWireResponse.failure(
      protocolVersion: 1,
      requestID: wireRequestID,
      error: AgentWorkspaceError(code: .permissionRevoked, recoveryAction: "Reconnect the profile.")
    )
    let encodedVersionOneFailure = try JSONEncoder().encode(versionOneFailure)
    #expect(
      try JSONDecoder().decode(AgentWireResponse.self, from: encodedVersionOneFailure)
        == versionOneFailure
    )
  }

  private func decodeRequest(protocolVersion: Int) throws -> AgentWireRequest {
    let json =
      #"{"protocolVersion":\#(protocolVersion),"requestID":"\#(requestID)","profileID":"\#(profileID)","credentialBase64":"AA==","command":{"listEvents":{}}}"#
    return try JSONDecoder().decode(AgentWireRequest.self, from: Data(json.utf8))
  }
}
