import Foundation
import Testing

@testable import FleckCore

@Suite("Agent event IPC contract")
struct AgentEventIPCContractTests {
  private static let noteID = "00000000-0000-4000-8000-000000000101"
  private static let folderID = "00000000-0000-4000-8000-000000000102"
  private static let validSecret = "whsec_" + Data(repeating: 0x5a, count: 24).base64EncodedString()

  @Test func eventCommandsAreStrictAndV2Only() throws {
    let list = try? decodeCommand(#"{"listEvents":{}}"#)
    #expect(list != nil)
    guard let list else { return }
    #expect(try encodedJSON(list) == #"{"listEvents":{}}"#)
    #expect(!list.isSupported(wireVersion: 1))
    #expect(list.isSupported(wireVersion: 2))

    let prepare = try? decodeCommand(Self.prepareCommand())
    #expect(prepare != nil)
    guard let prepare else { return }
    #expect(prepare.isSupported(wireVersion: 2))
    let remove = try? decodeCommand(Self.removeCommand())
    #expect(remove != nil)
    guard let remove else { return }
    #expect(remove.isSupported(wireVersion: 2))

    let invalidCommands = [
      Self.prepareCommand(scope: #"{"note_id":"\#(Self.noteID)","folder_id":"\#(Self.folderID)"}"#),
      Self.prepareCommand(callbackURL: "http://example.test/hook"),
      Self.prepareCommand(signingSecret: "whsec_not-base64"),
      Self.prepareCommand(ttl: #"{"milliseconds":59999}"#),
      Self.prepareCommand(extra: #", "unexpected": true"#),
      Self.prepareCommand(event: "note.deleted"),
      Self.removeCommand(extra: #", "unexpected": true"#),
    ]
    for json in invalidCommands {
      #expect(throws: (any Error).self) { try decodeCommand(json) }
    }

    let oldCommand: AgentWorkspaceCommand = .listSharedNotes
    #expect(try encodedJSON(oldCommand) == #"{"listSharedNotes":{}}"#)
  }

  @Test func eventResponsesAreStrictAndV2Only() throws {
    let catalog = try? decodeResponse(Self.catalogResponse())
    #expect(catalog != nil)
    guard let catalog else { return }
    #expect(catalog.isSupported(wireVersion: 2))
    #expect(!catalog.isSupported(wireVersion: 1))

    let pending = try? decodeResponse(
      #"{"pendingEventSubscription":{"receipt":{"subscriptionID":"evt_0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","status":"pending","expiresAt":0,"revision":1,"grantRevision":1}}}"#
    )
    #expect(pending != nil)
    guard let pending else { return }
    #expect(pending.isSupported(wireVersion: 2))
    let pendingJSON = try encodedJSON(pending)
    #expect(pendingJSON.contains("\"status\":\"pending\""))
    #expect(try decodeResponse(#"{"eventUnsubscribed":{}}"#).isSupported(wireVersion: 2))
    let oldResponse: AgentWorkspaceResponse = .sharedNotes(notes: [])
    #expect(try encodedJSON(oldResponse) == #"{"sharedNotes":{"notes":[]}}"#)

    let invalidResponses = [
      #"{"events":{"events":[]},"eventUnsubscribed":{}}"#,
      #"{"events":{"events":[{"name":"note.created","description":"safe","inputSchema":{"type":"object","x-private":true},"payloadSchema":{"type":"object"}}]}}"#,
      #"{"events":{"events":[{"name":"note.created","description":"safe","privateNoteID":"00000000-0000-4000-8000-000000000101","inputSchema":{"type":"object"},"payloadSchema":{"type":"object"}}]}}"#,
      #"{"eventUnsubscribed":{"subscriptionID":"evt_private"}}"#,
    ]
    for json in invalidResponses {
      #expect(throws: (any Error).self) { try decodeResponse(json) }
    }
  }

  @Test func verifiedSubscriptionReceiptsRoundTripStrictlyAndRejectMalformedFields() throws {
    let receipt = AgentEventVerifiedSubscriptionReceipt(
      subscriptionID: "evt_" + String(repeating: "a", count: 64),
      refreshBefore: Date(timeIntervalSince1970: 1_800_000_000),
      revision: 2,
      grantRevision: 3
    )
    let response = AgentWorkspaceResponse.verifiedEventSubscription(receipt: receipt)
    let encoded = try encodedJSON(response)
    #expect(try decodeResponse(encoded) == response)
    #expect(response.isSupported(wireVersion: 2))
    #expect(!response.isSupported(wireVersion: 1))

    let validID = "evt_" + String(repeating: "a", count: 64)
    let invalidResponses = [
      #"{"verifiedEventSubscription":{"receipt":{"subscriptionID":"\#(validID)","status":"pending","refreshBefore":1800000000,"revision":2,"grantRevision":3}}}"#,
      #"{"verifiedEventSubscription":{"receipt":{"subscriptionID":"\#(validID)","status":"verified","refreshBefore":1800000000,"revision":2,"grantRevision":3,"unexpected":true}}}"#,
      #"{"verifiedEventSubscription":{"receipt":{"subscriptionID":"evt_\#(String(repeating: "A", count: 64))","status":"verified","refreshBefore":1800000000,"revision":2,"grantRevision":3}}}"#,
      #"{"verifiedEventSubscription":{"receipt":{"subscriptionID":"\#(validID)","status":"verified","refreshBefore":1800000000,"revision":0,"grantRevision":3}}}"#,
      #"{"verifiedEventSubscription":{"receipt":{"subscriptionID":"\#(validID)","status":"verified","refreshBefore":1800000000,"revision":2,"grantRevision":0}}}"#,
    ]
    for json in invalidResponses {
      #expect(throws: (any Error).self) { try decodeResponse(json) }
    }
  }

  @Test func eventFailuresAreStrictAndV2Only() throws {
    let callbackFailure = AgentWorkspaceError.callbackEndpointFailure(reason: .challengeFailed)
    let encodedCallbackFailure = try encodedJSON(callbackFailure)
    #expect(callbackFailure.code == .internalSaveFailure)
    #expect(try decodeWorkspaceError(encodedCallbackFailure) == callbackFailure)
    #expect(callbackFailure.isSupported(wireVersion: 2))
    #expect(!callbackFailure.isSupported(wireVersion: 1))

    let rotationFailure = AgentWorkspaceError.signingKeyRotationInProgress(retryAfterMs: 90_000)
    #expect(rotationFailure.code == .writeTooLarge)
    #expect(rotationFailure.eventFailure?.reason == .signingKeyRotationInProgress)
    #expect(rotationFailure.eventFailure?.retryAfterMs == 60_000)
    #expect(rotationFailure.isSupported(wireVersion: 2))
    #expect(!rotationFailure.isSupported(wireVersion: 1))

    let invalidFailures = [
      #"{"code":"internal_save_failure","eventFailure":{"reason":"challenge_failed","retryAfterMs":1}}"#,
      #"{"code":"write_too_large","eventFailure":{"reason":"signing_key_rotation_in_progress"}}"#,
      #"{"code":"write_too_large","eventFailure":{"reason":"signing_key_rotation_in_progress","retryAfterMs":null}}"#,
      #"{"code":"write_too_large","eventFailure":{"reason":"signing_key_rotation_in_progress","retryAfterMs":60001}}"#,
      #"{"code":"permission_revoked","eventFailure":{"reason":"timeout"}}"#,
      #"{"code":"internal_save_failure","eventFailure":null}"#,
      #"{"code":"internal_save_failure","eventFailure":{"reason":"timeout","url":"https://example.test/hook"}}"#,
    ]
    for json in invalidFailures {
      #expect(throws: (any Error).self) { try decodeWorkspaceError(json) }
    }
  }

  private func decodeCommand(_ json: String) throws -> AgentWorkspaceCommand {
    try JSONDecoder().decode(AgentWorkspaceCommand.self, from: Data(json.utf8))
  }

  private func decodeResponse(_ json: String) throws -> AgentWorkspaceResponse {
    try JSONDecoder().decode(AgentWorkspaceResponse.self, from: Data(json.utf8))
  }

  private func decodeWorkspaceError(_ json: String) throws -> AgentWorkspaceError {
    try JSONDecoder().decode(AgentWorkspaceError.self, from: Data(json.utf8))
  }

  private func encodedJSON<T: Encodable>(_ value: T) throws -> String {
    String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
  }

  private static func prepareCommand(
    event: String = "note.updated",
    scope: String = #"{"note_id":"\#(noteID)"}"#,
    callbackURL: String = "https://example.test/hook",
    signingSecret: String = validSecret,
    ttl: String = #"{"default":{}}"#,
    extra: String = ""
  ) -> String {
    #"{"prepareEventSubscription":{"request":{"event":"\#(event)","scope":\#(scope),"callbackURL":"\#(callbackURL)","signingSecret":"\#(signingSecret)","ttl":\#(ttl)\#(extra)}}}"#
  }

  private static func removeCommand(extra: String = "") -> String {
    #"{"removeEventSubscription":{"request":{"event":"note.updated","scope":{"note_id":"\#(noteID)"},"callbackURL":"https://example.test/hook"\#(extra)}}}"#
  }

  private static func catalogResponse() -> String {
    #"{"events":{"events":[{"name":"note.created","description":"A new authorized note was created.","inputSchema":{"type":"object","properties":{"note_id":{"type":"string","format":"uuid"}},"required":["note_id"],"additionalProperties":false,"oneOf":[{"type":"object","properties":{"note_id":{"type":"string","format":"uuid"}},"required":["note_id"],"additionalProperties":false}]},"payloadSchema":{"type":"object","properties":{"note_id":{"type":"string"}},"required":["note_id"],"additionalProperties":false}}]}}"#
  }
}
