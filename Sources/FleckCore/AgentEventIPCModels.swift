import Foundation

public enum AgentEventSubscriptionTTL: Equatable, Sendable, Codable {
  case standard
  case milliseconds(Int)

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: AgentEventIPCCodingKey.self)
    guard container.allKeys.count == 1, let key = container.allKeys.first else {
      throw agentEventIPCDecodingError(decoder)
    }
    switch key.stringValue {
    case "default":
      let value = try container.nestedContainer(
        keyedBy: AgentEventIPCCodingKey.self,
        forKey: key
      )
      guard value.allKeys.isEmpty else { throw agentEventIPCDecodingError(decoder) }
      self = .standard
    case "milliseconds":
      let milliseconds = try container.decode(Int.self, forKey: key)
      guard (60_000...604_800_000).contains(milliseconds) else {
        throw agentEventIPCDecodingError(decoder)
      }
      self = .milliseconds(milliseconds)
    default:
      throw agentEventIPCDecodingError(decoder)
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: AgentEventIPCCodingKey.self)
    switch self {
    case .standard:
      _ = container.nestedContainer(
        keyedBy: AgentEventIPCCodingKey.self,
        forKey: AgentEventIPCCodingKey("default")
      )
    case .milliseconds(let value):
      guard (60_000...604_800_000).contains(value) else {
        throw agentEventIPCEncodingError(encoder)
      }
      try container.encode(value, forKey: AgentEventIPCCodingKey("milliseconds"))
    }
  }

  public var requestedSeconds: TimeInterval? {
    guard case .milliseconds(let value) = self else { return nil }
    return TimeInterval(value) / 1_000
  }
}

public struct AgentEventSubscriptionRequest: Equatable, Sendable, Codable {
  public let event: AgentEventName
  public let scope: AgentEventScope
  public let callbackURL: String
  public let signingSecret: String
  public let ttl: AgentEventSubscriptionTTL

  public init(
    event: AgentEventName,
    scope: AgentEventScope,
    callbackURL: String,
    signingSecret: String,
    ttl: AgentEventSubscriptionTTL = .standard
  ) {
    self.event = event
    self.scope = scope
    self.callbackURL = callbackURL
    self.signingSecret = signingSecret
    self.ttl = ttl
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: AgentEventIPCCodingKey.self)
    try container.requireExactKeys(
      ["event", "scope", "callbackURL", "signingSecret", "ttl"],
      decoder: decoder
    )
    event = try container.decode(AgentEventName.self, forKey: AgentEventIPCCodingKey("event"))
    scope = try container.decode(AgentEventScope.self, forKey: AgentEventIPCCodingKey("scope"))
    callbackURL = try container.decode(String.self, forKey: AgentEventIPCCodingKey("callbackURL"))
    signingSecret = try container.decode(
      String.self,
      forKey: AgentEventIPCCodingKey("signingSecret")
    )
    ttl = try container.decode(
      AgentEventSubscriptionTTL.self, forKey: AgentEventIPCCodingKey("ttl"))
    guard Self.isValidCallbackURL(callbackURL), Self.isValidSigningSecret(signingSecret) else {
      throw agentEventIPCDecodingError(decoder)
    }
  }

  public func encode(to encoder: any Encoder) throws {
    guard Self.isValidCallbackURL(callbackURL), Self.isValidSigningSecret(signingSecret) else {
      throw agentEventIPCEncodingError(encoder)
    }
    var container = encoder.container(keyedBy: AgentEventIPCCodingKey.self)
    try container.encode(event, forKey: AgentEventIPCCodingKey("event"))
    try container.encode(scope, forKey: AgentEventIPCCodingKey("scope"))
    try container.encode(callbackURL, forKey: AgentEventIPCCodingKey("callbackURL"))
    try container.encode(signingSecret, forKey: AgentEventIPCCodingKey("signingSecret"))
    try container.encode(ttl, forKey: AgentEventIPCCodingKey("ttl"))
  }

  private static func isValidCallbackURL(_ value: String) -> Bool {
    guard
      value.utf8.count <= 2_048,
      value.unicodeScalars.allSatisfy({
        !CharacterSet.controlCharacters.contains($0)
          && !CharacterSet.whitespacesAndNewlines.contains($0)
      }),
      let components = URLComponents(string: value),
      components.scheme?.lowercased() == "https",
      let host = components.host,
      !host.isEmpty,
      components.user == nil,
      components.password == nil,
      components.fragment == nil,
      components.port.map({ (1...65_535).contains($0) }) ?? true
    else {
      return false
    }
    return true
  }

  private static func isValidSigningSecret(_ value: String) -> Bool {
    guard value.hasPrefix("whsec_"),
      let data = Data(base64Encoded: String(value.dropFirst(6)), options: []),
      (24...64).contains(data.count)
    else {
      return false
    }
    return data.base64EncodedString() == String(value.dropFirst(6))
  }
}

public struct AgentEventUnsubscribeRequest: Equatable, Sendable, Codable {
  public let event: AgentEventName
  public let scope: AgentEventScope
  public let callbackURL: String

  public init(event: AgentEventName, scope: AgentEventScope, callbackURL: String) {
    self.event = event
    self.scope = scope
    self.callbackURL = callbackURL
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: AgentEventIPCCodingKey.self)
    try container.requireExactKeys(["event", "scope", "callbackURL"], decoder: decoder)
    event = try container.decode(AgentEventName.self, forKey: AgentEventIPCCodingKey("event"))
    scope = try container.decode(AgentEventScope.self, forKey: AgentEventIPCCodingKey("scope"))
    callbackURL = try container.decode(String.self, forKey: AgentEventIPCCodingKey("callbackURL"))
    guard AgentEventSubscriptionRequest.isValidCallbackURLForIPC(callbackURL) else {
      throw agentEventIPCDecodingError(decoder)
    }
  }

  public func encode(to encoder: any Encoder) throws {
    guard AgentEventSubscriptionRequest.isValidCallbackURLForIPC(callbackURL) else {
      throw agentEventIPCEncodingError(encoder)
    }
    var container = encoder.container(keyedBy: AgentEventIPCCodingKey.self)
    try container.encode(event, forKey: AgentEventIPCCodingKey("event"))
    try container.encode(scope, forKey: AgentEventIPCCodingKey("scope"))
    try container.encode(callbackURL, forKey: AgentEventIPCCodingKey("callbackURL"))
  }
}

public struct AgentEventPendingReceipt: Equatable, Sendable, Codable {
  public let subscriptionID: String
  public let status: String
  public let expiresAt: Date
  public let revision: UInt64
  public let grantRevision: UInt64

  public init(
    subscriptionID: String,
    expiresAt: Date,
    revision: UInt64,
    grantRevision: UInt64
  ) {
    self.subscriptionID = subscriptionID
    status = "pending"
    self.expiresAt = expiresAt
    self.revision = revision
    self.grantRevision = grantRevision
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: AgentEventIPCCodingKey.self)
    try container.requireExactKeys(
      ["subscriptionID", "status", "expiresAt", "revision", "grantRevision"],
      decoder: decoder
    )
    subscriptionID = try container.decode(
      String.self,
      forKey: AgentEventIPCCodingKey("subscriptionID")
    )
    status = try container.decode(String.self, forKey: AgentEventIPCCodingKey("status"))
    expiresAt = try container.decode(Date.self, forKey: AgentEventIPCCodingKey("expiresAt"))
    revision = try container.decode(UInt64.self, forKey: AgentEventIPCCodingKey("revision"))
    grantRevision = try container.decode(
      UInt64.self,
      forKey: AgentEventIPCCodingKey("grantRevision")
    )
    guard
      Self.isValidSubscriptionID(subscriptionID),
      status == "pending",
      expiresAt.timeIntervalSince1970.isFinite,
      revision > 0,
      grantRevision > 0
    else {
      throw agentEventIPCDecodingError(decoder)
    }
  }

  public func encode(to encoder: any Encoder) throws {
    guard
      Self.isValidSubscriptionID(subscriptionID),
      status == "pending",
      expiresAt.timeIntervalSince1970.isFinite,
      revision > 0,
      grantRevision > 0
    else {
      throw agentEventIPCEncodingError(encoder)
    }
    var container = encoder.container(keyedBy: AgentEventIPCCodingKey.self)
    try container.encode(subscriptionID, forKey: AgentEventIPCCodingKey("subscriptionID"))
    try container.encode(status, forKey: AgentEventIPCCodingKey("status"))
    try container.encode(expiresAt, forKey: AgentEventIPCCodingKey("expiresAt"))
    try container.encode(revision, forKey: AgentEventIPCCodingKey("revision"))
    try container.encode(grantRevision, forKey: AgentEventIPCCodingKey("grantRevision"))
  }

  private static func isValidSubscriptionID(_ value: String) -> Bool {
    value.hasPrefix("evt_")
      && value.count == 68
      && value.utf8.dropFirst(4).allSatisfy {
        (48...57).contains($0) || (97...102).contains($0)
      }
  }
}

public struct AgentEventVerifiedSubscriptionReceipt: Equatable, Sendable, Codable {
  public let subscriptionID: String
  public let status: String
  public let refreshBefore: Date
  public let revision: UInt64
  public let grantRevision: UInt64

  public init(
    subscriptionID: String,
    refreshBefore: Date,
    revision: UInt64,
    grantRevision: UInt64
  ) {
    self.subscriptionID = subscriptionID
    status = "verified"
    self.refreshBefore = refreshBefore
    self.revision = revision
    self.grantRevision = grantRevision
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: AgentEventIPCCodingKey.self)
    try container.requireExactKeys(
      ["subscriptionID", "status", "refreshBefore", "revision", "grantRevision"],
      decoder: decoder
    )
    subscriptionID = try container.decode(
      String.self,
      forKey: AgentEventIPCCodingKey("subscriptionID")
    )
    status = try container.decode(String.self, forKey: AgentEventIPCCodingKey("status"))
    refreshBefore = try container.decode(Date.self, forKey: AgentEventIPCCodingKey("refreshBefore"))
    revision = try container.decode(UInt64.self, forKey: AgentEventIPCCodingKey("revision"))
    grantRevision = try container.decode(
      UInt64.self,
      forKey: AgentEventIPCCodingKey("grantRevision")
    )
    guard
      Self.isValidSubscriptionID(subscriptionID),
      status == "verified",
      refreshBefore.timeIntervalSince1970.isFinite,
      revision > 0,
      grantRevision > 0
    else {
      throw agentEventIPCDecodingError(decoder)
    }
  }

  public func encode(to encoder: any Encoder) throws {
    guard
      Self.isValidSubscriptionID(subscriptionID),
      status == "verified",
      refreshBefore.timeIntervalSince1970.isFinite,
      revision > 0,
      grantRevision > 0
    else {
      throw agentEventIPCEncodingError(encoder)
    }
    var container = encoder.container(keyedBy: AgentEventIPCCodingKey.self)
    try container.encode(subscriptionID, forKey: AgentEventIPCCodingKey("subscriptionID"))
    try container.encode(status, forKey: AgentEventIPCCodingKey("status"))
    try container.encode(refreshBefore, forKey: AgentEventIPCCodingKey("refreshBefore"))
    try container.encode(revision, forKey: AgentEventIPCCodingKey("revision"))
    try container.encode(grantRevision, forKey: AgentEventIPCCodingKey("grantRevision"))
  }

  private static func isValidSubscriptionID(_ value: String) -> Bool {
    value.hasPrefix("evt_")
      && value.count == 68
      && value.utf8.dropFirst(4).allSatisfy {
        (48...57).contains($0) || (97...102).contains($0)
      }
  }
}

extension AgentEventSubscriptionRequest {
  static func isValidCallbackURLForIPC(_ value: String) -> Bool {
    isValidCallbackURL(value)
  }
}

extension AgentEventCatalog {
  public static func events(
    noteScopeAvailable: Bool,
    folderScopeAvailable: Bool
  ) -> [AgentEventDescriptor] {
    guard noteScopeAvailable || folderScopeAvailable else { return [] }
    let noteScope = AgentEventJSONSchema(
      type: "object",
      properties: [
        "note_id": AgentEventJSONSchemaProperty(type: "string", format: "uuid")
      ],
      required: ["note_id"],
      additionalProperties: false
    )
    let folderScope = AgentEventJSONSchema(
      type: "object",
      properties: [
        "folder_id": AgentEventJSONSchemaProperty(type: "string", format: "uuid")
      ],
      required: ["folder_id"],
      additionalProperties: false
    )
    var availableScopes: [AgentEventJSONSchema] = []
    var scopeProperties: [String: AgentEventJSONSchemaProperty] = [:]
    if noteScopeAvailable {
      availableScopes.append(noteScope)
      scopeProperties["note_id"] = AgentEventJSONSchemaProperty(type: "string", format: "uuid")
    }
    if folderScopeAvailable {
      availableScopes.append(folderScope)
      scopeProperties["folder_id"] = AgentEventJSONSchemaProperty(type: "string", format: "uuid")
    }
    let scopeSchema = AgentEventJSONSchema(
      type: "object",
      description: "Select one note or one explicitly granted folder.",
      properties: scopeProperties,
      additionalProperties: false,
      oneOf: availableScopes
    )
    return events.map {
      AgentEventDescriptor(
        name: $0.name,
        description: $0.description,
        inputSchema: scopeSchema,
        payloadSchema: $0.payloadSchema
      )
    }
  }
}

func validateAgentEventIPCCommand(from decoder: any Decoder, caseKey: String) throws {
  switch caseKey {
  case "prepareEventSubscription":
    _ = try AgentEventSubscriptionRequest(from: decoder)
  case "removeEventSubscription":
    _ = try AgentEventUnsubscribeRequest(from: decoder)
  default:
    throw agentEventIPCDecodingError(decoder)
  }
}

func validateAgentEventIPCResponse(from decoder: any Decoder, caseKey: String) throws {
  let container = try decoder.container(keyedBy: AgentEventIPCCodingKey.self)
  switch caseKey {
  case "events":
    try container.requireExactKeys(["events"], decoder: decoder)
    var events = try container.nestedUnkeyedContainer(forKey: AgentEventIPCCodingKey("events"))
    var names: Set<AgentEventName> = []
    while !events.isAtEnd {
      let descriptorDecoder = try events.superDecoder()
      try validateAgentEventDescriptor(from: descriptorDecoder)
      let descriptor = try AgentEventDescriptor(from: descriptorDecoder)
      guard names.insert(descriptor.name).inserted else {
        throw agentEventIPCDecodingError(descriptorDecoder)
      }
    }
  case "pendingEventSubscription":
    try container.requireExactKeys(["receipt"], decoder: decoder)
    _ = try AgentEventPendingReceipt(
      from: container.superDecoder(forKey: AgentEventIPCCodingKey("receipt"))
    )
  case "verifiedEventSubscription":
    try container.requireExactKeys(["receipt"], decoder: decoder)
    _ = try AgentEventVerifiedSubscriptionReceipt(
      from: container.superDecoder(forKey: AgentEventIPCCodingKey("receipt"))
    )
  case "eventUnsubscribed":
    try container.requireExactKeys([], decoder: decoder)
  default:
    throw agentEventIPCDecodingError(decoder)
  }
}

private func validateAgentEventDescriptor(from decoder: any Decoder) throws {
  let container = try decoder.container(keyedBy: AgentEventIPCCodingKey.self)
  try container.requireExactKeys(
    ["name", "description", "inputSchema", "payloadSchema"],
    decoder: decoder
  )
  _ = try container.decode(AgentEventName.self, forKey: AgentEventIPCCodingKey("name"))
  _ = try container.decode(String.self, forKey: AgentEventIPCCodingKey("description"))
  try validateAgentEventJSONSchema(
    from: container.superDecoder(forKey: AgentEventIPCCodingKey("inputSchema"))
  )
  try validateAgentEventJSONSchema(
    from: container.superDecoder(forKey: AgentEventIPCCodingKey("payloadSchema"))
  )
}

private func validateAgentEventJSONSchema(from decoder: any Decoder) throws {
  let container = try decoder.container(keyedBy: AgentEventIPCCodingKey.self)
  try container.requireKeys(
    required: ["type"],
    optional: ["description", "properties", "required", "additionalProperties", "oneOf"],
    decoder: decoder
  )
  if container.contains(AgentEventIPCCodingKey("properties")) {
    let properties = try container.nestedContainer(
      keyedBy: AgentEventIPCCodingKey.self,
      forKey: AgentEventIPCCodingKey("properties")
    )
    for key in properties.allKeys {
      try validateAgentEventJSONSchemaProperty(
        from: properties.superDecoder(forKey: key)
      )
    }
  }
  if container.contains(AgentEventIPCCodingKey("oneOf")) {
    var alternatives = try container.nestedUnkeyedContainer(
      forKey: AgentEventIPCCodingKey("oneOf")
    )
    while !alternatives.isAtEnd {
      try validateAgentEventJSONSchema(from: alternatives.superDecoder())
    }
  }
}

private func validateAgentEventJSONSchemaProperty(from decoder: any Decoder) throws {
  let container = try decoder.container(keyedBy: AgentEventIPCCodingKey.self)
  try container.requireKeys(
    required: ["type"],
    optional: ["format", "items", "enum", "uniqueItems", "minItems", "maxItems", "minimum"],
    decoder: decoder
  )
  guard container.contains(AgentEventIPCCodingKey("items")) else { return }
  let items = try container.nestedContainer(
    keyedBy: AgentEventIPCCodingKey.self,
    forKey: AgentEventIPCCodingKey("items")
  )
  try items.requireKeys(required: ["type"], optional: ["enum"], decoder: decoder)
}

private struct AgentEventIPCCodingKey: CodingKey, Hashable {
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

extension KeyedDecodingContainer where Key == AgentEventIPCCodingKey {
  fileprivate func requireExactKeys(_ expected: Set<String>, decoder: any Decoder) throws {
    guard Set(allKeys.map(\.stringValue)) == expected else {
      throw agentEventIPCDecodingError(decoder)
    }
  }

  fileprivate func requireKeys(
    required: Set<String>,
    optional: Set<String>,
    decoder: any Decoder
  ) throws {
    let keys = Set(allKeys.map(\.stringValue))
    guard required.isSubset(of: keys), keys.isSubset(of: required.union(optional)) else {
      throw agentEventIPCDecodingError(decoder)
    }
  }
}

private func agentEventIPCDecodingError(_ decoder: any Decoder) -> DecodingError {
  .dataCorrupted(
    DecodingError.Context(
      codingPath: decoder.codingPath,
      debugDescription: "Event IPC payload is invalid."
    )
  )
}

private func agentEventIPCEncodingError(_ encoder: any Encoder) -> EncodingError {
  .invalidValue(
    "event IPC payload",
    EncodingError.Context(
      codingPath: encoder.codingPath,
      debugDescription: "Event IPC payload is invalid."
    )
  )
}
