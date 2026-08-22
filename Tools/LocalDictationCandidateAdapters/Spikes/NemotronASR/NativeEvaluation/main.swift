import Darwin
import Foundation

private struct ProtocolFailure: Error, CustomStringConvertible {
  let code: String
  let message: String

  var description: String { code }
}

private enum StrictJSONError: Error {
  case malformed
  case duplicateKey
}

private enum StrictJSON {
  static func validateObject(_ data: Data) throws {
    guard (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else {
      throw StrictJSONError.malformed
    }
    var scanner = Scanner(bytes: Array(data))
    try scanner.readObject()
    scanner.skipWhitespace()
    guard scanner.index == scanner.bytes.count else { throw StrictJSONError.malformed }
  }

  private struct Scanner {
    let bytes: [UInt8]
    var index = 0

    mutating func readObject() throws {
      try consume(0x7B)
      skipWhitespace()
      var keys = Set<String>()
      if consumeIf(0x7D) { return }
      while true {
        skipWhitespace()
        let key = try readString()
        guard keys.insert(key).inserted else { throw StrictJSONError.duplicateKey }
        skipWhitespace()
        try consume(0x3A)
        try readValue()
        skipWhitespace()
        if consumeIf(0x7D) { return }
        try consume(0x2C)
      }
    }

    mutating func readArray() throws {
      try consume(0x5B)
      skipWhitespace()
      if consumeIf(0x5D) { return }
      while true {
        try readValue()
        skipWhitespace()
        if consumeIf(0x5D) { return }
        try consume(0x2C)
      }
    }

    mutating func readValue() throws {
      skipWhitespace()
      guard index < bytes.count else { throw StrictJSONError.malformed }
      switch bytes[index] {
      case 0x22:
        _ = try readString()
      case 0x7B:
        try readObject()
      case 0x5B:
        try readArray()
      case 0x74:
        try consumeLiteral(Array("true".utf8))
      case 0x66:
        try consumeLiteral(Array("false".utf8))
      case 0x6E:
        try consumeLiteral(Array("null".utf8))
      default:
        let start = index
        while index < bytes.count,
          ![0x20, 0x09, 0x0A, 0x0D, 0x2C, 0x5D, 0x7D].contains(bytes[index]) {
          index += 1
        }
        guard index > start else { throw StrictJSONError.malformed }
      }
    }

    mutating func readString() throws -> String {
      let start = index
      try consume(0x22)
      while index < bytes.count {
        let byte = bytes[index]
        if byte == 0x22 {
          index += 1
          let token = Data(bytes[start..<index])
          guard let value = try? JSONSerialization.jsonObject(with: token, options: [.fragmentsAllowed]) as? String else {
            throw StrictJSONError.malformed
          }
          return value
        }
        if byte < 0x20 { throw StrictJSONError.malformed }
        if byte == 0x5C {
          index += 1
          guard index < bytes.count else { throw StrictJSONError.malformed }
          if bytes[index] == 0x75 {
            guard index + 4 < bytes.count else { throw StrictJSONError.malformed }
            index += 4
          }
        }
        index += 1
      }
      throw StrictJSONError.malformed
    }

    mutating func consumeLiteral(_ literal: [UInt8]) throws {
      guard index + literal.count <= bytes.count,
        Array(bytes[index..<(index + literal.count)]) == literal else {
        throw StrictJSONError.malformed
      }
      index += literal.count
    }

    mutating func consume(_ expected: UInt8) throws {
      guard consumeIf(expected) else { throw StrictJSONError.malformed }
    }

    mutating func consumeIf(_ expected: UInt8) -> Bool {
      guard index < bytes.count, bytes[index] == expected else { return false }
      index += 1
      return true
    }

    mutating func skipWhitespace() {
      while index < bytes.count && [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) {
        index += 1
      }
    }
  }
}

private final class JSONLineInput {
  private static let maximumInputBytes = 16 * 1_024 * 1_024
  private static let maximumRequestCount = 512
  private let handle: FileHandle
  private var finished = false
  private var inputBytes = 0
  private var requestCount = 0

  init(handle: FileHandle = .standardInput) { self.handle = handle }

  func nextLine() throws -> Data? {
    guard !finished else { return nil }
    var line = Data()
    while true {
      guard let chunk = try handle.read(upToCount: 1), !chunk.isEmpty else {
        finished = true
        return line.isEmpty ? nil : try finish(line, terminatedByNewline: false)
      }
      let byte = chunk[chunk.startIndex]
      if byte == 0x0A { return try finish(line, terminatedByNewline: true) }
      line.append(byte)
      guard line.count < JSONLinesCodec.maximumLineBytes else {
        throw ProtocolFailure(code: "line-too-large", message: "line-too-large")
      }
    }
  }

  private func finish(_ line: Data, terminatedByNewline: Bool) throws -> Data {
    let consumed = line.count + (terminatedByNewline ? 1 : 0)
    guard requestCount < Self.maximumRequestCount,
      inputBytes + consumed <= Self.maximumInputBytes else {
      throw ProtocolFailure(code: "stdin-flood", message: "stdin-flood")
    }
    inputBytes += consumed
    requestCount += 1
    return line
  }
}

private enum JSONLineOutput {
  static func write(_ event: CandidateAdapterEvent) throws {
    let data = try JSONLinesCodec.encode(event)
    try FileHandle.standardOutput.write(contentsOf: data)
  }
}

private struct CLIArguments {
  let modelPath: String
  let runtimePath: String
  let sourcePath: String
  let probeBlockedDecode: Bool

  init(_ arguments: [String]) throws {
    var values: [String: String] = [:]
    var probeBlockedDecode = false
    var index = 1
    while index < arguments.count {
      switch arguments[index] {
      case "--model-path", "--runtime-path", "--source-path":
        guard index + 1 < arguments.count, values[arguments[index]] == nil else {
          throw ProtocolFailure(code: "invalid-cli", message: "invalid-cli")
        }
        values[arguments[index]] = arguments[index + 1]
        index += 2
      case "--probe-blocked-decode":
        guard !probeBlockedDecode else {
          throw ProtocolFailure(code: "invalid-cli", message: "invalid-cli")
        }
        probeBlockedDecode = true
        index += 1
      default:
        throw ProtocolFailure(code: "unsupported-argument", message: "unsupported-argument")
      }
    }
    guard let modelPath = values["--model-path"],
      let runtimePath = values["--runtime-path"],
      let sourcePath = values["--source-path"] else {
      throw ProtocolFailure(code: "model-runtime-source-required", message: "model-runtime-source-required")
    }
    self.modelPath = modelPath
    self.runtimePath = runtimePath
    self.sourcePath = sourcePath
    self.probeBlockedDecode = probeBlockedDecode
  }
}

private enum RequestDecoder {
  static func decode(_ data: Data) throws -> CandidateAdapterRequest {
    guard !data.isEmpty else {
      throw ProtocolFailure(code: "malformed-json", message: "malformed-json")
    }
    do {
      try StrictJSON.validateObject(data)
    } catch StrictJSONError.duplicateKey {
      throw ProtocolFailure(code: "duplicate-json-key", message: "duplicate-json-key")
    } catch {
      throw ProtocolFailure(code: "malformed-json", message: "malformed-json")
    }
    do {
      return try JSONLinesCodec.decodeRequest(data)
    } catch let error as CandidateAdapterProtocolError {
      throw ProtocolFailure(code: code(for: error), message: code(for: error))
    } catch {
      throw ProtocolFailure(code: "malformed-json", message: "malformed-json")
    }
  }

  private static func code(for error: CandidateAdapterProtocolError) -> String {
    switch error {
    case .unknownKey: return "unknown-field"
    case .unsupportedSchemaVersion: return "unsupported-schema-version"
    case .invalidOperationFields, .invalidEventFields, .invalidField,
      .nonLocalPath, .duplicateValue, .tooManyContextPhrases:
      return "invalid-request"
    case .embeddedNewline, .emptyLine, .lineTooLarge, .malformedJSON:
      return "malformed-json"
    }
  }
}

@main
struct NemotronNativeEvaluationMain {
  static func main() {
    do {
      let arguments = try CLIArguments(CommandLine.arguments)
      try run(arguments)
    } catch let failure as ProtocolFailure {
      try? writeFailure(requestID: "protocol-error", code: failure.code, message: failure.message)
      Darwin.exit(2)
    } catch {
      try? writeFailure(requestID: "protocol-error", code: "native-evaluation-failure", message: "native-evaluation-failure")
      Darwin.exit(2)
    }
  }

  private static func run(_ arguments: CLIArguments) throws {
    let input = JSONLineInput()
    var recognizer: NemotronRecognizer?
    var loadAttempted = false
    defer { recognizer?.close() }

    do {
      while let line = try input.nextLine() {
        do {
          let request = try RequestDecoder.decode(line)
          switch request.operation {
          case .load:
            guard !loadAttempted else {
              try writeFailure(requestID: request.requestID, code: "load-already-attempted", message: "load-already-attempted")
              continue
            }
            loadAttempted = true
            do {
              recognizer = try NemotronRecognizer.load(
                modelPath: arguments.modelPath,
                runtimePath: arguments.runtimePath,
                sourcePath: arguments.sourcePath
              )
              try JSONLineOutput.write(.ready(
                requestID: request.requestID,
                runtimeVersion: NemotronRecognizer.runtimeVersion,
                modelRevision: NemotronRecognizer.modelRevision
              ))
              writeDiagnostic("capabilities real-time-cadence=160ms observed-partials-only supportsCancellation=false supportsCooperativeDecodeCancellation=false modelLicense=OpenMDW-1.1 runtimeLicense=Apache-2.0 admission=false integration=false package=false release=false releaseAdmitted=false")
            } catch let error as NemotronRecognizerError {
              try writeFailure(requestID: request.requestID, code: error.code, message: error.description)
            }
          case .transcribe:
            guard let recognizer else {
              try writeFailure(requestID: request.requestID, code: "not-loaded", message: "not-loaded")
              continue
            }
            guard request.sampleRate == 16_000 else {
              try writeFailure(requestID: request.requestID, code: "sample-rate-must-be-16000", message: "sample-rate-must-be-16000")
              continue
            }
            guard let locale = request.localeIdentifier,
              ["auto", "en", "en-us", "zh", "zh-cn"].contains(locale.lowercased()) else {
              try writeFailure(requestID: request.requestID, code: "unsupported-locale", message: "unsupported-locale")
              continue
            }
            guard request.contextPhrases.isEmpty else {
              try writeFailure(requestID: request.requestID, code: "unsupported-context", message: "unsupported-context")
              continue
            }
            guard let audioPath = request.audioPath else {
              try writeFailure(requestID: request.requestID, code: "invalid-request", message: "invalid-request")
              continue
            }
            do {
              let result = try recognizer.transcribe(
                requestID: request.requestID,
                audioPath: audioPath,
                localeIdentifier: locale,
                blockBeforeDecode: arguments.probeBlockedDecode,
                onPartial: { sequence, transcript in
                  try JSONLineOutput.write(.partial(
                    requestID: request.requestID,
                    sequence: sequence,
                    transcript: transcript
                  ))
                }
              )
              if let value = result.requestToFirstPartialMs {
                try JSONLineOutput.write(.measurement(
                  requestID: request.requestID,
                  name: "requestToFirstPartialMs",
                  value: value,
                  unit: "ms"
                ))
              }
              if let value = result.feedCadenceMs {
                try JSONLineOutput.write(.measurement(
                  requestID: request.requestID,
                  name: "feedCadenceMs",
                  value: value,
                  unit: "ms"
                ))
              }
              try JSONLineOutput.write(.measurement(
                requestID: request.requestID,
                name: "feedEndToFinalMs",
                value: result.feedEndToFinalMs,
                unit: "ms"
              ))
              try JSONLineOutput.write(.measurement(
                requestID: request.requestID,
                name: "partialCount",
                value: Double(result.partialCount),
                unit: "count"
              ))
              try JSONLineOutput.write(.final(requestID: request.requestID, transcript: result.transcript))
              writeDiagnostic("measurement requestID=\(request.requestID) requestToFirstPartialMs=\(format(result.requestToFirstPartialMs)) feedEndToFinalMs=\(String(format: "%.1f", result.feedEndToFinalMs)) partialCount=\(result.partialCount)")
            } catch let error as NemotronRecognizerError {
              try writeFailure(requestID: request.requestID, code: error.code, message: error.description)
            }
          case .cancel:
            try writeFailure(requestID: request.requestID, code: "cancellation-unsupported", message: "cancellation-unsupported")
          case .clean:
            try writeFailure(requestID: request.requestID, code: "unsupported-operation", message: "unsupported-operation")
          case .unload:
            guard recognizer != nil else {
              try writeFailure(requestID: request.requestID, code: "invalid-order", message: "invalid-order")
              continue
            }
            recognizer?.close()
            recognizer = nil
            try JSONLineOutput.write(.unloaded(requestID: request.requestID))
          case .shutdown:
            guard loadAttempted else {
              try writeFailure(requestID: request.requestID, code: "invalid-order", message: "invalid-order")
              continue
            }
            recognizer?.close()
            recognizer = nil
            try JSONLineOutput.write(.unloaded(requestID: request.requestID))
            return
          }
        } catch let failure as ProtocolFailure {
          try writeFailure(requestID: "protocol-error", code: failure.code, message: failure.message)
        }
      }
    } catch let failure as ProtocolFailure {
      throw failure
    }
  }

  private static func writeFailure(requestID: String, code: String, message: String) throws {
    try JSONLineOutput.write(.failure(requestID: requestID, code: code, message: message))
  }

  private static func writeDiagnostic(_ message: String) {
    let bounded = String(message.prefix(4_096))
    FileHandle.standardError.write(Data((bounded + "\n").utf8))
  }

  private static func format(_ value: Double?) -> String {
    guard let value else { return "unobserved" }
    return String(format: "%.1f", value)
  }
}
