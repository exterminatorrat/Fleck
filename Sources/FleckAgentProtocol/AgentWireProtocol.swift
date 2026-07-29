import Foundation
import FleckCore

public struct AgentWireRequest: Codable, Equatable, Sendable {
  public static let currentProtocolVersion = 1

  public let protocolVersion: Int
  public let requestID: UUID
  public let profileID: UUID
  public let credentialBase64: String
  public let command: AgentWorkspaceCommand

  public init(
    protocolVersion: Int = currentProtocolVersion,
    requestID: UUID,
    profileID: UUID,
    credentialBase64: String,
    command: AgentWorkspaceCommand
  ) {
    self.protocolVersion = protocolVersion
    self.requestID = requestID
    self.profileID = profileID
    self.credentialBase64 = credentialBase64
    self.command = command
  }
}

public struct AgentWireResponse: Codable, Equatable, Sendable {
  public static let currentProtocolVersion = 1

  public let protocolVersion: Int
  public let requestID: UUID
  public let result: AgentWorkspaceResponse?
  public let error: AgentWorkspaceError?

  private init(
    protocolVersion: Int = currentProtocolVersion,
    requestID: UUID,
    result: AgentWorkspaceResponse?,
    error: AgentWorkspaceError?
  ) {
    self.protocolVersion = protocolVersion
    self.requestID = requestID
    self.result = result
    self.error = error
  }

  public static func success(
    requestID: UUID,
    result: AgentWorkspaceResponse
  ) -> AgentWireResponse {
    AgentWireResponse(requestID: requestID, result: result, error: nil)
  }

  public static func failure(
    requestID: UUID,
    error: AgentWorkspaceError
  ) -> AgentWireResponse {
    AgentWireResponse(requestID: requestID, result: nil, error: error)
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    protocolVersion = try container.decode(Int.self, forKey: .protocolVersion)
    requestID = try container.decode(UUID.self, forKey: .requestID)
    result = try container.decodeIfPresent(
      AgentWorkspaceResponse.self,
      forKey: .result
    )
    error = try container.decodeIfPresent(
      AgentWorkspaceError.self,
      forKey: .error
    )
    guard (result == nil) != (error == nil) else {
      throw DecodingError.dataCorruptedError(
        forKey: .result,
        in: container,
        debugDescription: "Response must contain exactly one of result or error."
      )
    }
  }
}
