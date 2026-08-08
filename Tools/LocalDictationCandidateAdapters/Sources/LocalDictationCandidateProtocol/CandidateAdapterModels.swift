import Foundation

private struct CandidateAdapterCodingKey: CodingKey, Hashable {
  let stringValue: String
  let intValue: Int?

  init(stringValue: String) {
    self.stringValue = stringValue
    intValue = nil
  }

  init?(intValue: Int) {
    return nil
  }
}

private func candidateAdapterKey(_ value: String) -> CandidateAdapterCodingKey {
  CandidateAdapterCodingKey(stringValue: value)
}

public enum CandidateAdapterProtocolError: Error, Equatable, Sendable, CustomStringConvertible {
  case embeddedNewline
  case emptyLine
  case lineTooLarge
  case malformedJSON
  case unknownKey(String)
  case unsupportedSchemaVersion(Int)
  case invalidField(String)
  case nonLocalPath(String)
  case duplicateValue(String)
  case tooManyContextPhrases
  case invalidOperationFields(CandidateAdapterOperation)
  case invalidEventFields(CandidateAdapterEventKind)

  public var description: String {
    switch self {
    case .embeddedNewline: return "embedded newline"
    case .emptyLine: return "empty line"
    case .lineTooLarge: return "line too large"
    case .malformedJSON: return "malformed JSON"
    case .unknownKey(let key): return "unknown key: \(key)"
    case .unsupportedSchemaVersion(let version):
      return "unsupported schema version: \(version)"
    case .invalidField(let field): return "invalid field: \(field)"
    case .nonLocalPath(let path): return "non-local path: \(path)"
    case .duplicateValue(let value): return "duplicate value: \(value)"
    case .tooManyContextPhrases: return "too many context phrases"
    case .invalidOperationFields(let operation):
      return "invalid fields for operation: \(operation.rawValue)"
    case .invalidEventFields(let event):
      return "invalid fields for event: \(event.rawValue)"
    }
  }
}

public enum CandidateAdapterOperation: String, Codable, CaseIterable, Equatable, Sendable {
  case load
  case transcribe
  case clean
  case cancel
  case unload
  case shutdown
}

public enum CandidateAdapterCleanupMode: String, Codable, CaseIterable, Equatable, Sendable {
  case off
  case conservative
  case standard
}

public struct CandidateAdapterRequest: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let requestID: String
  public let operation: CandidateAdapterOperation
  public let audioPath: String?
  public let sampleRate: Int?
  public let localeIdentifier: String?
  public let contextPhrases: [String]
  public let transcript: String?
  public let protectedForms: [String]
  public let cleanupMode: CandidateAdapterCleanupMode?
  public let targetRequestID: String?

  public init(
    schemaVersion: Int,
    requestID: String,
    operation: CandidateAdapterOperation,
    audioPath: String?,
    sampleRate: Int?,
    localeIdentifier: String?,
    contextPhrases: [String],
    transcript: String?,
    protectedForms: [String],
    cleanupMode: CandidateAdapterCleanupMode?,
    targetRequestID: String? = nil
  ) {
    self.schemaVersion = schemaVersion
    self.requestID = requestID
    self.operation = operation
    self.audioPath = audioPath
    self.sampleRate = sampleRate
    self.localeIdentifier = localeIdentifier
    self.contextPhrases = contextPhrases
    self.transcript = transcript
    self.protectedForms = protectedForms
    self.cleanupMode = cleanupMode
    self.targetRequestID = targetRequestID
  }

  public func validate() throws {
    guard schemaVersion == 1 else {
      throw CandidateAdapterProtocolError.unsupportedSchemaVersion(schemaVersion)
    }
    try Self.validateIdentifier(requestID, field: "requestID")
    try Self.validatePhrases(contextPhrases, field: "contextPhrases")
    try Self.validatePhrases(protectedForms, field: "protectedForms")
    if let transcript {
      try Self.validateScalar(transcript, field: "transcript", allowEmpty: true)
    }
    if let targetRequestID {
      try Self.validateIdentifier(targetRequestID, field: "targetRequestID")
    }

    switch operation {
    case .load, .unload, .shutdown:
      guard audioPath == nil, sampleRate == nil, localeIdentifier == nil,
        contextPhrases.isEmpty, transcript == nil, protectedForms.isEmpty,
        cleanupMode == nil, targetRequestID == nil
      else {
        throw CandidateAdapterProtocolError.invalidOperationFields(operation)
      }
    case .transcribe:
      guard let audioPath, let sampleRate, let localeIdentifier,
        transcript == nil, protectedForms.isEmpty, cleanupMode == nil,
        targetRequestID == nil
      else {
        throw CandidateAdapterProtocolError.invalidOperationFields(operation)
      }
      try Self.validateLocalPath(audioPath)
      guard (8_000...192_000).contains(sampleRate) else {
        throw CandidateAdapterProtocolError.invalidField("sampleRate")
      }
      try Self.validateScalar(localeIdentifier, field: "localeIdentifier")
    case .clean:
      guard let transcript, cleanupMode != nil, audioPath == nil,
        sampleRate == nil, localeIdentifier == nil, contextPhrases.isEmpty,
        targetRequestID == nil
      else {
        throw CandidateAdapterProtocolError.invalidOperationFields(operation)
      }
      try Self.validateScalar(transcript, field: "transcript", allowEmpty: true)
    case .cancel:
      guard let targetRequestID, audioPath == nil, sampleRate == nil,
        localeIdentifier == nil, contextPhrases.isEmpty, transcript == nil,
        protectedForms.isEmpty, cleanupMode == nil
      else {
        throw CandidateAdapterProtocolError.invalidOperationFields(operation)
      }
      try Self.validateIdentifier(targetRequestID, field: "targetRequestID")
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case schemaVersion
    case requestID
    case operation
    case audioPath
    case sampleRate
    case localeIdentifier
    case contextPhrases
    case transcript
    case protectedForms
    case cleanupMode
    case targetRequestID
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CandidateAdapterCodingKey.self)
    try Self.rejectUnknownKeys(container)
    schemaVersion = try container.decode(Int.self, forKey: candidateAdapterKey("schemaVersion"))
    requestID = try container.decode(String.self, forKey: candidateAdapterKey("requestID"))
    operation = try container.decode(CandidateAdapterOperation.self, forKey: candidateAdapterKey("operation"))
    audioPath = try container.decodeIfPresent(String.self, forKey: candidateAdapterKey("audioPath"))
    sampleRate = try container.decodeIfPresent(Int.self, forKey: candidateAdapterKey("sampleRate"))
    localeIdentifier = try container.decodeIfPresent(String.self, forKey: candidateAdapterKey("localeIdentifier"))
    contextPhrases = try container.decodeIfPresent([String].self, forKey: candidateAdapterKey("contextPhrases")) ?? []
    transcript = try container.decodeIfPresent(String.self, forKey: candidateAdapterKey("transcript"))
    protectedForms = try container.decodeIfPresent([String].self, forKey: candidateAdapterKey("protectedForms")) ?? []
    cleanupMode = try container.decodeIfPresent(CandidateAdapterCleanupMode.self, forKey: candidateAdapterKey("cleanupMode"))
    targetRequestID = try container.decodeIfPresent(String.self, forKey: candidateAdapterKey("targetRequestID"))
    try validate()
  }

  public func encode(to encoder: Encoder) throws {
    try validate()
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(schemaVersion, forKey: .schemaVersion)
    try container.encode(requestID, forKey: .requestID)
    try container.encode(operation, forKey: .operation)
    try container.encodeIfPresent(audioPath, forKey: .audioPath)
    try container.encodeIfPresent(sampleRate, forKey: .sampleRate)
    try container.encodeIfPresent(localeIdentifier, forKey: .localeIdentifier)
    try container.encode(contextPhrases, forKey: .contextPhrases)
    try container.encodeIfPresent(transcript, forKey: .transcript)
    try container.encode(protectedForms, forKey: .protectedForms)
    try container.encodeIfPresent(cleanupMode, forKey: .cleanupMode)
    try container.encodeIfPresent(targetRequestID, forKey: .targetRequestID)
  }

  private static func rejectUnknownKeys(
    _ container: KeyedDecodingContainer<CandidateAdapterCodingKey>
  ) throws {
    let allowed = Set(CodingKeys.allCases.map(\.stringValue))
    if let key = container.allKeys.first(where: { !allowed.contains($0.stringValue) }) {
      throw CandidateAdapterProtocolError.unknownKey(key.stringValue)
    }
  }

  private static func validateIdentifier(_ value: String, field: String) throws {
    try validateScalar(value, field: field)
    guard value.count <= 128 else {
      throw CandidateAdapterProtocolError.invalidField(field)
    }
  }

  private static func validatePhrases(_ values: [String], field: String) throws {
    guard values.count <= 100 else {
      if field == "contextPhrases" {
        throw CandidateAdapterProtocolError.tooManyContextPhrases
      }
      throw CandidateAdapterProtocolError.invalidField(field)
    }
    var seen = Set<String>()
    for value in values {
      try validateScalar(value, field: field)
      guard seen.insert(value).inserted else {
        throw CandidateAdapterProtocolError.duplicateValue(value)
      }
    }
  }

  fileprivate static func validateScalar(
    _ value: String,
    field: String,
    allowEmpty: Bool = false
  ) throws {
    guard allowEmpty || !value.isEmpty else {
      throw CandidateAdapterProtocolError.invalidField(field)
    }
    guard value.unicodeScalars.allSatisfy({ scalar in
      scalar != "\n" && scalar != "\r" && scalar != "\0"
    }) else {
      throw CandidateAdapterProtocolError.embeddedNewline
    }
  }

  private static func validateLocalPath(_ path: String) throws {
    guard path.first == "/", !path.contains("://") else {
      throw CandidateAdapterProtocolError.nonLocalPath(path)
    }
    try validateScalar(path, field: "audioPath")
  }
}

public enum CandidateAdapterEventKind: String, Codable, CaseIterable, Equatable, Sendable {
  case ready
  case partial
  case `final`
  case cancelled
  case unloaded
  case measurement
  case failure
}

public enum CandidateAdapterEvent: Codable, Equatable, Sendable {
  case ready(requestID: String, runtimeVersion: String, modelRevision: String)
  case partial(requestID: String, sequence: Int, transcript: String)
  case `final`(requestID: String, transcript: String)
  case cancelled(requestID: String)
  case unloaded(requestID: String)
  case measurement(requestID: String, name: String, value: Double, unit: String)
  case failure(requestID: String, code: String, message: String)

  public var requestID: String {
    switch self {
    case .ready(let requestID, _, _),
      .partial(let requestID, _, _),
      .final(let requestID, _),
      .cancelled(let requestID),
      .unloaded(let requestID),
      .measurement(let requestID, _, _, _),
      .failure(let requestID, _, _):
      return requestID
    }
  }

  public var kind: CandidateAdapterEventKind {
    switch self {
    case .ready: return .ready
    case .partial: return .partial
    case .final: return .final
    case .cancelled: return .cancelled
    case .unloaded: return .unloaded
    case .measurement: return .measurement
    case .failure: return .failure
    }
  }

  public func validate() throws {
    try CandidateAdapterRequest.validateScalar(requestID, field: "requestID")
    switch self {
    case .ready(_, let runtimeVersion, let modelRevision):
      try CandidateAdapterRequest.validateScalar(runtimeVersion, field: "runtimeVersion")
      try CandidateAdapterRequest.validateScalar(modelRevision, field: "modelRevision")
    case .partial(_, let sequence, let transcript):
      guard sequence >= 0 else {
        throw CandidateAdapterProtocolError.invalidField("sequence")
      }
      try CandidateAdapterRequest.validateScalar(transcript, field: "transcript", allowEmpty: true)
    case .final(_, let transcript):
      try CandidateAdapterRequest.validateScalar(transcript, field: "transcript", allowEmpty: true)
    case .cancelled, .unloaded:
      break
    case .measurement(_, let name, let value, let unit):
      try CandidateAdapterRequest.validateScalar(name, field: "name")
      try CandidateAdapterRequest.validateScalar(unit, field: "unit")
      guard value.isFinite else {
        throw CandidateAdapterProtocolError.invalidField("value")
      }
    case .failure(_, let code, let message):
      try CandidateAdapterRequest.validateScalar(code, field: "code")
      try CandidateAdapterRequest.validateScalar(message, field: "message", allowEmpty: true)
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case schemaVersion
    case event
    case requestID
    case runtimeVersion
    case modelRevision
    case sequence
    case transcript
    case name
    case value
    case unit
    case code
    case message
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CandidateAdapterCodingKey.self)
    let allowed = Set(CodingKeys.allCases.map(\.stringValue))
    if let key = container.allKeys.first(where: { !allowed.contains($0.stringValue) }) {
      throw CandidateAdapterProtocolError.unknownKey(key.stringValue)
    }
    let schemaVersion = try container.decode(Int.self, forKey: candidateAdapterKey("schemaVersion"))
    guard schemaVersion == 1 else {
      throw CandidateAdapterProtocolError.unsupportedSchemaVersion(schemaVersion)
    }
    let kind = try container.decode(CandidateAdapterEventKind.self, forKey: candidateAdapterKey("event"))
    let requestID = try container.decode(String.self, forKey: candidateAdapterKey("requestID"))
    switch kind {
    case .ready:
      try Self.requireOnly(container, kind: kind, keys: ["schemaVersion", "event", "requestID", "runtimeVersion", "modelRevision"])
      self = .ready(
        requestID: requestID,
        runtimeVersion: try container.decode(String.self, forKey: candidateAdapterKey("runtimeVersion")),
        modelRevision: try container.decode(String.self, forKey: candidateAdapterKey("modelRevision"))
      )
    case .partial:
      try Self.requireOnly(container, kind: kind, keys: ["schemaVersion", "event", "requestID", "sequence", "transcript"])
      self = .partial(
        requestID: requestID,
        sequence: try container.decode(Int.self, forKey: candidateAdapterKey("sequence")),
        transcript: try container.decode(String.self, forKey: candidateAdapterKey("transcript"))
      )
    case .final:
      try Self.requireOnly(container, kind: kind, keys: ["schemaVersion", "event", "requestID", "transcript"])
      self = .final(
        requestID: requestID,
        transcript: try container.decode(String.self, forKey: candidateAdapterKey("transcript"))
      )
    case .cancelled:
      try Self.requireOnly(container, kind: kind, keys: ["schemaVersion", "event", "requestID"])
      self = .cancelled(requestID: requestID)
    case .unloaded:
      try Self.requireOnly(container, kind: kind, keys: ["schemaVersion", "event", "requestID"])
      self = .unloaded(requestID: requestID)
    case .measurement:
      try Self.requireOnly(container, kind: kind, keys: ["schemaVersion", "event", "requestID", "name", "value", "unit"])
      self = .measurement(
        requestID: requestID,
        name: try container.decode(String.self, forKey: candidateAdapterKey("name")),
        value: try container.decode(Double.self, forKey: candidateAdapterKey("value")),
        unit: try container.decode(String.self, forKey: candidateAdapterKey("unit"))
      )
    case .failure:
      try Self.requireOnly(container, kind: kind, keys: ["schemaVersion", "event", "requestID", "code", "message"])
      self = .failure(
        requestID: requestID,
        code: try container.decode(String.self, forKey: candidateAdapterKey("code")),
        message: try container.decode(String.self, forKey: candidateAdapterKey("message"))
      )
    }
    try validate()
  }

  public func encode(to encoder: Encoder) throws {
    try validate()
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(1, forKey: .schemaVersion)
    try container.encode(kind, forKey: .event)
    try container.encode(requestID, forKey: .requestID)
    switch self {
    case .ready(_, let runtimeVersion, let modelRevision):
      try container.encode(runtimeVersion, forKey: .runtimeVersion)
      try container.encode(modelRevision, forKey: .modelRevision)
    case .partial(_, let sequence, let transcript):
      try container.encode(sequence, forKey: .sequence)
      try container.encode(transcript, forKey: .transcript)
    case .final(_, let transcript):
      try container.encode(transcript, forKey: .transcript)
    case .cancelled, .unloaded:
      break
    case .measurement(_, let name, let value, let unit):
      try container.encode(name, forKey: .name)
      try container.encode(value, forKey: .value)
      try container.encode(unit, forKey: .unit)
    case .failure(_, let code, let message):
      try container.encode(code, forKey: .code)
      try container.encode(message, forKey: .message)
    }
  }

  private static func requireOnly(
    _ container: KeyedDecodingContainer<CandidateAdapterCodingKey>,
    kind: CandidateAdapterEventKind,
    keys: Set<String>
  ) throws {
    let present = Set(container.allKeys.map(\.stringValue))
    if present != keys {
      throw CandidateAdapterProtocolError.invalidEventFields(kind)
    }
  }
}
