#if os(macOS)
  import Foundation
  import FleckAgentProtocol
  import FleckCore

  struct AgentWorkspaceClient: Sendable {
    typealias CredentialLoader = @Sendable (UUID) throws -> String
    typealias Sender = @Sendable (AgentWireRequest) throws -> AgentWorkspaceResponse

    let profileID: UUID
    let loadCredential: CredentialLoader
    let send: Sender

    init(
      profileID: UUID,
      loadCredential: @escaping CredentialLoader = { profileID in
        try BridgeCredentialStore().load(profileID: profileID)
      },
      send: @escaping Sender = { request in
        try AgentIPCClient().send(request)
      }
    ) {
      self.profileID = profileID
      self.loadCredential = loadCredential
      self.send = send
    }

    func capabilities() throws -> AgentCapabilitySummary {
      let response = try send(request(for: .getCapabilities))
      guard case .capabilities(let summary) = response else {
        throw AgentIPCClientError.invalidFrame
      }
      return summary
    }

    func execute(_ command: AgentWorkspaceCommand) throws -> AgentWorkspaceResponse {
      try send(request(for: command))
    }

    private func request(for command: AgentWorkspaceCommand) throws -> AgentWireRequest {
      AgentWireRequest(
        requestID: UUID(),
        profileID: profileID,
        credentialBase64: try loadCredential(profileID),
        command: command
      )
    }
  }
#endif
