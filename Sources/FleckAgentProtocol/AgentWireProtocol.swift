import Foundation
import FleckCore

public struct AgentWireRequest: Codable, Equatable, Sendable {
  public static let currentProtocolVersion = 2
  public static let supportedProtocolVersions = [1, 2]

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

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: AgentWireCodingKey.self)
    try container.requireExactKeys([
      "protocolVersion", "requestID", "profileID", "credentialBase64", "command",
    ])
    protocolVersion = try container.decode(
      Int.self,
      forKey: AgentWireCodingKey("protocolVersion")
    )
    requestID = try container.decode(
      UUID.self,
      forKey: AgentWireCodingKey("requestID")
    )
    profileID = try container.decode(
      UUID.self,
      forKey: AgentWireCodingKey("profileID")
    )
    credentialBase64 = try container.decode(
      String.self,
      forKey: AgentWireCodingKey("credentialBase64")
    )
    command = try container.decode(
      AgentWorkspaceCommand.self,
      forKey: AgentWireCodingKey("command")
    )
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: AgentWireCodingKey.self)
    try container.encode(
      protocolVersion,
      forKey: AgentWireCodingKey("protocolVersion")
    )
    try container.encode(requestID, forKey: AgentWireCodingKey("requestID"))
    try container.encode(profileID, forKey: AgentWireCodingKey("profileID"))
    try container.encode(
      credentialBase64,
      forKey: AgentWireCodingKey("credentialBase64")
    )
    try container.encode(command, forKey: AgentWireCodingKey("command"))
  }
}

public struct AgentWireResponse: Codable, Equatable, Sendable {
  public static let currentProtocolVersion = 2
  public static let supportedProtocolVersions = [1, 2]

  public let protocolVersion: Int
  public let requestID: UUID
  public let result: AgentWorkspaceResponse?
  public let error: AgentWorkspaceError?

  private init(
    protocolVersion: Int,
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
    protocolVersion: Int,
    requestID: UUID,
    result: AgentWorkspaceResponse
  ) -> AgentWireResponse {
    AgentWireResponse(
      protocolVersion: protocolVersion,
      requestID: requestID,
      result: result,
      error: nil
    )
  }

  public static func failure(
    protocolVersion: Int,
    requestID: UUID,
    error: AgentWorkspaceError
  ) -> AgentWireResponse {
    AgentWireResponse(
      protocolVersion: protocolVersion,
      requestID: requestID,
      result: nil,
      error: error
    )
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: AgentWireCodingKey.self)
    let keys = Set(container.allKeys.map(\.stringValue))
    let resultKeys = ["protocolVersion", "requestID", "result"]
    let errorKeys = ["protocolVersion", "requestID", "error"]
    guard keys == Set(resultKeys) || keys == Set(errorKeys) else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: container.codingPath,
          debugDescription: "Response must contain one complete payload."
        )
      )
    }
    protocolVersion = try container.decode(
      Int.self,
      forKey: AgentWireCodingKey("protocolVersion")
    )
    requestID = try container.decode(
      UUID.self,
      forKey: AgentWireCodingKey("requestID")
    )
    result = try container.decodeIfPresent(
      AgentWorkspaceResponse.self,
      forKey: AgentWireCodingKey("result")
    )
    error = try container.decodeIfPresent(
      AgentWorkspaceError.self,
      forKey: AgentWireCodingKey("error")
    )
    guard (result == nil) != (error == nil) else {
      throw DecodingError.dataCorruptedError(
        forKey: AgentWireCodingKey("result"),
        in: container,
        debugDescription: "Response must contain exactly one of result or error."
      )
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: AgentWireCodingKey.self)
    try container.encode(
      protocolVersion,
      forKey: AgentWireCodingKey("protocolVersion")
    )
    try container.encode(requestID, forKey: AgentWireCodingKey("requestID"))
    try container.encodeIfPresent(
      result,
      forKey: AgentWireCodingKey("result")
    )
    try container.encodeIfPresent(error, forKey: AgentWireCodingKey("error"))
  }
}

private struct AgentWireCodingKey: CodingKey, Hashable {
  let stringValue: String
  let intValue: Int?

  init(_ stringValue: String) {
    self.stringValue = stringValue
    intValue = nil
  }

  init?(stringValue: String) {
    self.init(stringValue)
  }

  init?(intValue: Int) {
    stringValue = String(intValue)
    self.intValue = intValue
  }
}

private extension KeyedDecodingContainer where Key == AgentWireCodingKey {
  func requireExactKeys(_ expected: Set<String>) throws {
    guard Set(allKeys.map(\.stringValue)) == expected else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: codingPath,
          debugDescription: "Unexpected or missing wire fields."
        )
      )
    }
  }
}
