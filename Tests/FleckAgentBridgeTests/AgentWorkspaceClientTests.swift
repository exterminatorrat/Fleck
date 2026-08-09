import Foundation
import FleckAgentProtocol
import FleckCore
import Testing

@testable import FleckAgentBridge

@Suite("Agent workspace client")
struct AgentWorkspaceClientTests {
  private let profileID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
  private let credential = Data(repeating: 7, count: 32).base64EncodedString()

  @Test func capabilitiesLoadsCredentialAndSendsV2GetCapabilities() throws {
    let summary = AgentCapabilitySummary(
      grantRevision: 4,
      availableCapabilities: [.listNotes, .readNotes]
    )
    let client = AgentWorkspaceClient(
      profileID: profileID,
      loadCredential: { requestedProfileID in
        #expect(requestedProfileID == self.profileID)
        return self.credential
      },
      send: { request in
        #expect(request.protocolVersion == 2)
        #expect(request.profileID == self.profileID)
        #expect(request.credentialBase64 == self.credential)
        #expect(request.command == .getCapabilities)
        return .capabilities(summary: summary)
      }
    )

    #expect(try client.capabilities() == summary)
  }

  @Test func executeLoadsCredentialAndSendsV2Command() throws {
    let command = AgentWorkspaceCommand.listSharedNotes
    let response = AgentWorkspaceResponse.sharedNotes(notes: [])
    let client = AgentWorkspaceClient(
      profileID: profileID,
      loadCredential: { requestedProfileID in
        #expect(requestedProfileID == self.profileID)
        return self.credential
      },
      send: { request in
        #expect(request.protocolVersion == 2)
        #expect(request.profileID == self.profileID)
        #expect(request.credentialBase64 == self.credential)
        #expect(request.command == command)
        return response
      }
    )

    #expect(try client.execute(command) == response)
  }

  @Test func capabilitiesRejectsTheWrongResponseCaseWithContentFreeBridgeError() {
    let client = AgentWorkspaceClient(
      profileID: profileID,
      loadCredential: { _ in self.credential },
      send: { _ in .sharedNotes(notes: []) }
    )

    #expect(throws: AgentIPCClientError.invalidFrame) {
      _ = try client.capabilities()
    }
  }
}
