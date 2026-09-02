import Darwin
import Foundation

private let maximumJSONLineBytes = 1_048_576

private struct ProtocolFailure: Error, CustomStringConvertible {
  let requestID: String
  let code: String
  let message: String

  var description: String { code }
}

private enum TopLevelJSONKeyScanner {
  static func validate(_ data: Data) throws {
    var parser = Parser(bytes: Array(data))
    parser.skipWhitespace()
    guard parser.consume(0x7B) else { throw malformed() }

    var keys = Set<String>()
    parser.skipWhitespace()
    if !parser.consume(0x7D) {
      while true {
        parser.skipWhitespace()
        let key = try parser.parseString()
        guard keys.insert(key).inserted else { throw duplicate() }
        parser.skipWhitespace()
        guard parser.consume(0x3A) else { throw malformed() }
        try parser.parseValue(depth: 0)
        parser.skipWhitespace()
        if parser.consume(0x7D) { break }
        guard parser.consume(0x2C) else { throw malformed() }
      }
    }
    parser.skipWhitespace()
    guard parser.isAtEnd else { throw malformed() }
  }

  private static func malformed() -> ProtocolFailure {
    ProtocolFailure(requestID: "protocol-error", code: "malformed-json", message: "malformed-json")
  }

  private static func duplicate() -> ProtocolFailure {
    ProtocolFailure(requestID: "protocol-error", code: "duplicate-json-key", message: "duplicate-json-key")
  }

  private struct Parser {
    let bytes: [UInt8]
    var index = 0

    var isAtEnd: Bool { index == bytes.count }

    mutating func skipWhitespace() {
      while index < bytes.count,
        bytes[index] == 0x20 || bytes[index] == 0x09 || bytes[index] == 0x0A || bytes[index] == 0x0D {
        index += 1
      }
    }

    mutating func consume(_ byte: UInt8) -> Bool {
      guard index < bytes.count, bytes[index] == byte else { return false }
      index += 1
      return true
    }

    mutating func parseString() throws -> String {
      guard consume(0x22) else { throw TopLevelJSONKeyScanner.malformed() }
      var decoded = Data()
      while index < bytes.count {
        let byte = bytes[index]
        index += 1
        switch byte {
        case 0x22:
          guard let value = String(data: decoded, encoding: .utf8) else {
            throw TopLevelJSONKeyScanner.malformed()
          }
          return value
        case 0x5C:
          guard index < bytes.count else { throw TopLevelJSONKeyScanner.malformed() }
          let escape = bytes[index]
          index += 1
          switch escape {
          case 0x22, 0x5C, 0x2F:
            decoded.append(escape)
          case 0x62:
            decoded.append(0x08)
          case 0x66:
            decoded.append(0x0C)
          case 0x6E:
            decoded.append(0x0A)
          case 0x72:
            decoded.append(0x0D)
          case 0x74:
            decoded.append(0x09)
          case 0x75:
            try appendUnicodeEscape(to: &decoded)
          default:
            throw TopLevelJSONKeyScanner.malformed()
          }
        case 0x00...0x1F:
          throw TopLevelJSONKeyScanner.malformed()
        default:
          decoded.append(byte)
        }
      }
      throw TopLevelJSONKeyScanner.malformed()
    }

    mutating func parseValue(depth: Int) throws {
      guard depth <= 64 else { throw TopLevelJSONKeyScanner.malformed() }
      skipWhitespace()
      guard index < bytes.count else { throw TopLevelJSONKeyScanner.malformed() }
      switch bytes[index] {
      case 0x22:
        _ = try parseString()
      case 0x7B:
        try parseObject(depth: depth + 1)
      case 0x5B:
        try parseArray(depth: depth + 1)
      case 0x74:
        try consumeLiteral(Array("true".utf8))
      case 0x66:
        try consumeLiteral(Array("false".utf8))
      case 0x6E:
        try consumeLiteral(Array("null".utf8))
      default:
        try parsePrimitive()
      }
    }

    mutating func parseObject(depth: Int) throws {
      guard consume(0x7B) else { throw TopLevelJSONKeyScanner.malformed() }
      skipWhitespace()
      if consume(0x7D) { return }
      while true {
        skipWhitespace()
        _ = try parseString()
        skipWhitespace()
        guard consume(0x3A) else { throw TopLevelJSONKeyScanner.malformed() }
        try parseValue(depth: depth)
        skipWhitespace()
        if consume(0x7D) { return }
        guard consume(0x2C) else { throw TopLevelJSONKeyScanner.malformed() }
      }
    }

    mutating func parseArray(depth: Int) throws {
      guard consume(0x5B) else { throw TopLevelJSONKeyScanner.malformed() }
      skipWhitespace()
      if consume(0x5D) { return }
      while true {
        try parseValue(depth: depth)
        skipWhitespace()
        if consume(0x5D) { return }
        guard consume(0x2C) else { throw TopLevelJSONKeyScanner.malformed() }
      }
    }

    mutating func consumeLiteral(_ literal: [UInt8]) throws {
      guard index + literal.count <= bytes.count,
        Array(bytes[index..<(index + literal.count)]) == literal
      else {
        throw TopLevelJSONKeyScanner.malformed()
      }
      index += literal.count
    }

    mutating func parsePrimitive() throws {
      let start = index
      while index < bytes.count,
        ![0x20, 0x09, 0x0A, 0x0D, 0x2C, 0x5D, 0x7D].contains(bytes[index]) {
        index += 1
      }
      guard index > start else { throw TopLevelJSONKeyScanner.malformed() }
    }

    mutating func appendUnicodeEscape(to data: inout Data) throws {
      let first = try readHexQuad()
      if (0xD800...0xDBFF).contains(first) {
        guard consume(0x5C), consume(0x75) else { throw TopLevelJSONKeyScanner.malformed() }
        let second = try readHexQuad()
        guard (0xDC00...0xDFFF).contains(second) else { throw TopLevelJSONKeyScanner.malformed() }
        let scalarValue = 0x1_0000 + ((first - 0xD800) << 10) + (second - 0xDC00)
        try appendUnicodeScalar(scalarValue, to: &data)
      } else if (0xDC00...0xDFFF).contains(first) {
        throw TopLevelJSONKeyScanner.malformed()
      } else {
        try appendUnicodeScalar(first, to: &data)
      }
    }

    mutating func readHexQuad() throws -> UInt32 {
      guard index + 4 <= bytes.count else { throw TopLevelJSONKeyScanner.malformed() }
      var value: UInt32 = 0
      for _ in 0..<4 {
        guard let digit = hexValue(bytes[index]) else { throw TopLevelJSONKeyScanner.malformed() }
        value = (value << 4) | digit
        index += 1
      }
      return value
    }

    func appendUnicodeScalar(_ value: UInt32, to data: inout Data) throws {
      guard let scalar = UnicodeScalar(value) else { throw TopLevelJSONKeyScanner.malformed() }
      data.append(contentsOf: String(scalar).utf8)
    }

    func hexValue(_ byte: UInt8) -> UInt32? {
      switch byte {
      case 0x30...0x39: return UInt32(byte - 0x30)
      case 0x41...0x46: return UInt32(byte - 0x41 + 10)
      case 0x61...0x66: return UInt32(byte - 0x61 + 10)
      default: return nil
      }
    }
  }
}

private enum RequestOperation {
  case load
  case transcribe
  case unload
  case shutdown
}

private struct EvaluationRequest {
  let requestID: String
  let operation: RequestOperation
  let audioPath: String?

  private struct Raw: Decodable {
    let schemaVersion: Int
    let requestID: String
    let operation: String
    let audioPath: String?
    let sampleRate: Int?
    let localeIdentifier: String?
    let contextPhrases: [String]
    let transcript: String?
    let protectedForms: [String]
    let cleanupMode: String?
    let targetRequestID: String?

    private enum CodingKeys: String, CodingKey {
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

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
      requestID = try container.decode(String.self, forKey: .requestID)
      operation = try container.decode(String.self, forKey: .operation)
      audioPath = try container.decodeIfPresent(String.self, forKey: .audioPath)
      sampleRate = try container.decodeIfPresent(Int.self, forKey: .sampleRate)
      localeIdentifier = try container.decodeIfPresent(String.self, forKey: .localeIdentifier)
      contextPhrases = try container.decodeIfPresent([String].self, forKey: .contextPhrases) ?? []
      transcript = try container.decodeIfPresent(String.self, forKey: .transcript)
      protectedForms = try container.decodeIfPresent([String].self, forKey: .protectedForms) ?? []
      cleanupMode = try container.decodeIfPresent(String.self, forKey: .cleanupMode)
      targetRequestID = try container.decodeIfPresent(String.self, forKey: .targetRequestID)
    }
  }

  static func decode(_ data: Data) throws -> EvaluationRequest {
    guard data.count <= maximumJSONLineBytes,
      !data.contains(0x0A),
      !data.contains(0x0D),
      !data.isEmpty
    else {
      throw ProtocolFailure(requestID: "protocol-error", code: "invalid-json-line", message: "invalid-json-line")
    }

    try TopLevelJSONKeyScanner.validate(data)
    let candidateID = requestIDCandidate(data)

    do {
      guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw ProtocolFailure(requestID: candidateID, code: "invalid-json-object", message: "invalid-json-object")
      }
      let allowedKeys: Set<String> = [
        "schemaVersion", "requestID", "operation", "audioPath", "sampleRate",
        "localeIdentifier", "contextPhrases", "transcript", "protectedForms",
        "cleanupMode", "targetRequestID",
      ]
      if object.keys.contains(where: { !allowedKeys.contains($0) }) {
        throw ProtocolFailure(requestID: candidateID, code: "unsupported-field", message: "unsupported-field")
      }
      let raw = try JSONDecoder().decode(Raw.self, from: data)
      try validateScalar(raw.requestID, field: "requestID", requestID: candidateID)
      guard raw.schemaVersion == 1 else {
        throw ProtocolFailure(requestID: candidateID, code: "unsupported-schema-version", message: "unsupported-schema-version")
      }
      try validatePhrases(raw.contextPhrases, field: "contextPhrases", requestID: candidateID)
      try validatePhrases(raw.protectedForms, field: "protectedForms", requestID: candidateID)
      if let targetRequestID = raw.targetRequestID {
        try validateScalar(targetRequestID, field: "targetRequestID", requestID: candidateID)
      }

      switch raw.operation {
      case "load":
        try requireLifecycleFields(raw, requestID: candidateID)
        return EvaluationRequest(requestID: candidateID, operation: .load, audioPath: nil)
      case "unload":
        try requireLifecycleFields(raw, requestID: candidateID)
        return EvaluationRequest(requestID: candidateID, operation: .unload, audioPath: nil)
      case "shutdown":
        try requireLifecycleFields(raw, requestID: candidateID)
        return EvaluationRequest(requestID: candidateID, operation: .shutdown, audioPath: nil)
      case "transcribe":
        guard raw.audioPath != nil, raw.sampleRate != nil, raw.localeIdentifier != nil,
          raw.transcript == nil, raw.cleanupMode == nil, raw.targetRequestID == nil
        else {
          throw ProtocolFailure(requestID: candidateID, code: "invalid-request", message: "invalid-request")
        }
        guard raw.contextPhrases.isEmpty else {
          throw ProtocolFailure(
            requestID: candidateID,
            code: "context-unsupported-by-sherpa-qwen3-offline-api",
            message: "context-unsupported-by-sherpa-qwen3-offline-api"
          )
        }
        guard raw.protectedForms.isEmpty else {
          throw ProtocolFailure(requestID: candidateID, code: "unsupported-field", message: "unsupported-field")
        }
        guard raw.sampleRate == 16_000 else {
          throw ProtocolFailure(requestID: candidateID, code: "sample-rate-must-be-16000", message: "sample-rate-must-be-16000")
        }
        guard let audioPath = raw.audioPath, isSafeAbsolutePath(audioPath) else {
          throw ProtocolFailure(requestID: candidateID, code: "invalid-audio-path", message: "invalid-audio-path")
        }
        guard let locale = raw.localeIdentifier, ["auto", "en", "en-us", "zh", "zh-cn"].contains(locale.lowercased()) else {
          throw ProtocolFailure(requestID: candidateID, code: "unsupported-locale", message: "unsupported-locale")
        }
        try validateScalar(audioPath, field: "audioPath", requestID: candidateID)
        try validateScalar(locale, field: "localeIdentifier", requestID: candidateID)
        return EvaluationRequest(requestID: candidateID, operation: .transcribe, audioPath: audioPath)
      case "cancel", "clean":
        throw ProtocolFailure(requestID: candidateID, code: "unsupported-operation", message: "unsupported-operation")
      default:
        throw ProtocolFailure(requestID: candidateID, code: "unsupported-operation", message: "unsupported-operation")
      }
    } catch let failure as ProtocolFailure {
      throw failure
    } catch {
      throw ProtocolFailure(requestID: candidateID, code: "malformed-json", message: "malformed-json")
    }
  }

  private static func requireLifecycleFields(_ raw: Raw, requestID: String) throws {
    guard raw.audioPath == nil,
      raw.sampleRate == nil,
      raw.localeIdentifier == nil,
      raw.contextPhrases.isEmpty,
      raw.transcript == nil,
      raw.protectedForms.isEmpty,
      raw.cleanupMode == nil,
      raw.targetRequestID == nil
    else {
      throw ProtocolFailure(requestID: requestID, code: "invalid-request", message: "invalid-request")
    }
  }

  private static func validatePhrases(_ values: [String], field: String, requestID: String) throws {
    guard values.count <= 100 else {
      throw ProtocolFailure(requestID: requestID, code: "too-many-phrases", message: "too-many-phrases")
    }
    var seen = Set<String>()
    for value in values {
      try validateScalar(value, field: field, requestID: requestID)
      guard seen.insert(value).inserted else {
        throw ProtocolFailure(requestID: requestID, code: "duplicate-phrase", message: "duplicate-phrase")
      }
    }
  }

  private static func validateScalar(_ value: String, field: String, requestID: String) throws {
    guard !value.isEmpty, value.utf8.count <= 65_536,
      value.unicodeScalars.allSatisfy({ $0 != "\0" && $0 != "\n" && $0 != "\r" })
    else {
      throw ProtocolFailure(requestID: requestID, code: "invalid-request", message: "invalid-request")
    }
    _ = field
  }

  private static func isSafeAbsolutePath(_ path: String) -> Bool {
    guard path.first == "/", !path.contains("://"), !path.contains("\0"), !path.contains("\n"), !path.contains("\r") else {
      return false
    }
    let components = path.split(separator: "/", omittingEmptySubsequences: false)
    return !components.contains(where: { $0.isEmpty && $0 != components.first || $0 == "." || $0 == ".." })
  }

  private static func requestIDCandidate(_ data: Data) -> String {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let requestID = object["requestID"] as? String,
      !requestID.isEmpty,
      requestID.utf8.count <= 128,
      requestID.unicodeScalars.allSatisfy({ $0 != "\0" && $0 != "\n" && $0 != "\r" })
    else {
      return "protocol-error"
    }
    return requestID
  }
}

private final class JSONLineInput {
  private static let maximumInputBytes = 16 * 1_024 * 1_024
  private static let maximumRequestCount = 512
  private let handle: FileHandle
  private var finished = false
  private var inputBytes = 0
  private var requestCount = 0

  init(handle: FileHandle = .standardInput) {
    self.handle = handle
  }

  func nextLine() throws -> Data? {
    guard !finished else { return nil }
    var line = Data()
    while true {
      guard let chunk = try handle.read(upToCount: 1), !chunk.isEmpty else {
        finished = true
        return line.isEmpty ? nil : try finish(line, terminatedByNewline: false)
      }
      let byte = chunk[chunk.startIndex]
      if byte == 0x0A {
        return try finish(line, terminatedByNewline: true)
      }
      line.append(byte)
      guard line.count < maximumJSONLineBytes else {
        throw ProtocolFailure(requestID: "protocol-error", code: "line-too-large", message: "line-too-large")
      }
    }
  }

  private func finish(_ line: Data, terminatedByNewline: Bool) throws -> Data {
    let consumedBytes = line.count + (terminatedByNewline ? 1 : 0)
    guard requestCount < Self.maximumRequestCount,
      inputBytes + consumedBytes <= Self.maximumInputBytes
    else {
      throw ProtocolFailure(requestID: "protocol-error", code: "stdin-bound-exceeded", message: "stdin-bound-exceeded")
    }
    inputBytes += consumedBytes
    requestCount += 1
    return line
  }
}

private enum JSONLineOutput {
  static func write(_ object: [String: Any]) throws {
    var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    guard data.count < maximumJSONLineBytes, !data.contains(0x0A), !data.contains(0x0D) else {
      throw ProtocolFailure(requestID: "protocol-error", code: "output-bound-exceeded", message: "output-bound-exceeded")
    }
    data.append(0x0A)
    try FileHandle.standardOutput.write(contentsOf: data)
  }
}

private struct CLIArguments {
  let preparedRoot: String
  let probeBlockedDecode: Bool

  init(_ arguments: [String]) throws {
    var preparedRoot: String?
    var probeBlockedDecode = false
    var index = 1
    while index < arguments.count {
      switch arguments[index] {
      case "--prepared-root":
        guard index + 1 < arguments.count, preparedRoot == nil else {
          throw ProtocolFailure(requestID: "protocol-error", code: "invalid-cli", message: "invalid-cli")
        }
        preparedRoot = arguments[index + 1]
        index += 2
      case "--probe-blocked-decode":
        guard !probeBlockedDecode else {
          throw ProtocolFailure(requestID: "protocol-error", code: "invalid-cli", message: "invalid-cli")
        }
        probeBlockedDecode = true
        index += 1
      default:
        throw ProtocolFailure(requestID: "protocol-error", code: "unsupported-argument", message: "unsupported-argument")
      }
    }
    guard let preparedRoot else {
      throw ProtocolFailure(requestID: "protocol-error", code: "prepared-root-required", message: "prepared-root-required")
    }
    self.preparedRoot = preparedRoot
    self.probeBlockedDecode = probeBlockedDecode
  }
}

@main
struct QwenSherpaNativeEvaluationMain {
  static func main() {
    do {
      let arguments = try CLIArguments(CommandLine.arguments)
      try run(arguments)
    } catch let failure as ProtocolFailure {
      writeDiagnostic(failure.code)
      Darwin.exit(2)
    } catch {
      writeDiagnostic("native-evaluation-failure")
      Darwin.exit(2)
    }
  }

  private static func run(_ arguments: CLIArguments) throws {
    let input = JSONLineInput()
    var recognizer: QwenSherpaRecognizer?
    defer { recognizer?.close() }

    while let line = try input.nextLine() {
      do {
        let request = try EvaluationRequest.decode(line)
        switch request.operation {
        case .load:
          guard recognizer == nil else {
            try failure(requestID: request.requestID, code: "already-loaded", message: "already-loaded")
            continue
          }
          do {
            recognizer = try QwenSherpaRecognizer.load(preparedRoot: arguments.preparedRoot)
            try JSONLineOutput.write([
              "schemaVersion": 1,
              "event": "ready",
              "requestID": request.requestID,
              "runtimeVersion": QwenSherpaRecognizer.runtimeVersion,
              "modelRevision": QwenSherpaRecognizer.modelRevision,
            ])
            writeDiagnostic("capabilities resultSemantics=batch-final-only supportsCancellation=false supportsCooperativeDecodeCancellation=false supportsHotwords=false releaseAdmitted=false")
          } catch let error as QwenSherpaRecognizerError {
            try failure(requestID: request.requestID, code: error.code, message: error.description)
          }
        case .transcribe:
          guard let recognizer, let audioPath = request.audioPath else {
            try failure(requestID: request.requestID, code: "not-loaded", message: "not-loaded")
            continue
          }
          do {
            let result = try recognizer.transcribe(
              audioPath: audioPath,
              blockBeforeDecode: arguments.probeBlockedDecode
            )
            try JSONLineOutput.write([
              "schemaVersion": 1,
              "event": "final",
              "requestID": request.requestID,
              "transcript": result.transcript,
            ])
            writeDiagnostic("measurement requestID=\(request.requestID) elapsedMs=\(String(format: "%.1f", result.elapsedMilliseconds))")
          } catch let error as QwenSherpaRecognizerError {
            try failure(requestID: request.requestID, code: error.code, message: error.description)
          }
        case .unload:
          recognizer?.close()
          recognizer = nil
          try unloaded(requestID: request.requestID)
        case .shutdown:
          recognizer?.close()
          recognizer = nil
          try unloaded(requestID: request.requestID)
          return
        }
      } catch let protocolFailure as ProtocolFailure {
        try failure(requestID: protocolFailure.requestID, code: protocolFailure.code, message: protocolFailure.message)
      }
    }
  }

  private static func failure(requestID: String, code: String, message: String) throws {
    try JSONLineOutput.write([
      "schemaVersion": 1,
      "event": "failure",
      "requestID": requestID,
      "code": code,
      "message": message,
    ])
  }

  private static func unloaded(requestID: String) throws {
    try JSONLineOutput.write([
      "schemaVersion": 1,
      "event": "unloaded",
      "requestID": requestID,
    ])
  }

  private static func writeDiagnostic(_ message: String) {
    let bounded = String(message.prefix(4_096))
    FileHandle.standardError.write(Data((bounded + "\n").utf8))
  }
}
