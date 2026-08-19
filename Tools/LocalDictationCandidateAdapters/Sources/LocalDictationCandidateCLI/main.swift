import CryptoKit
import Darwin
import Foundation
import LocalDictationCandidateProtocol
import LocalDictationCandidateRunner

@main
struct LocalDictationCandidateCLI {
  static func main() async {
    exit(await run(Array(CommandLine.arguments.dropFirst())))
  }

  static func run(
    _ arguments: [String],
    eventTimeout: Duration = .seconds(30)
  ) async -> Int32 {
    do {
      switch try Command.parse(arguments) {
      case .validateAdmission(let manifest, let schema):
        let manifestData = try readRegularFile(path: manifest)
        let schemaData = try readRegularFile(path: schema)
        try AdmissionSchema.validate(instanceData: manifestData, schemaData: schemaData)
        let value = try decodeManifest(manifestData)
        try value.validate()
        print(
          "admission valid: 10 immutable cases; release evidence: \(value.releaseEvidenceStatus)"
        )
        return 0
      case .run(let manifest, let adapter, let runtimeRoot, let modelRoot, let output):
        let manifestData = try readRegularFile(path: manifest)
        let value = try decodeManifest(manifestData)
        try value.validate()
        let adapterURL = try resolveExecutable(path: adapter)
        let runtimeRootURL = try validateModelRoot(path: runtimeRoot)
        let modelRootURL = try validateModelRoot(path: modelRoot)
        try validateNewOutput(path: output)
        let report = try await runCandidate(
          manifest: value,
          adapterURL: adapterURL,
          runtimeRootURL: runtimeRootURL,
          modelRootURL: modelRootURL,
          manifestPath: manifest,
          eventTimeout: eventTimeout
        )
        try writeExclusive(report, to: output)
        print("candidate run recorded: \(output)")
        return 0
      }
    } catch let error as CLIError {
      fputs("admission error: \(error.description)\n", stderr)
      return 2
    } catch {
      fputs("admission error: invalid input\n", stderr)
      return 2
    }
  }
}

private enum Command {
  case validateAdmission(manifest: String, schema: String)
  case run(manifest: String, adapter: String, runtimeRoot: String, modelRoot: String, output: String)

  static func parse(_ arguments: [String]) throws -> Command {
    guard let name = arguments.first else {
      throw CLIError.argument("one command is required")
    }
    var values: [String: String] = [:]
    var index = 1
    while index < arguments.count {
      let flag = arguments[index]
      guard flag.hasPrefix("--"), index + 1 < arguments.count else {
        throw CLIError.argument("missing value for \(flag)")
      }
      let value = arguments[index + 1]
      guard !value.hasPrefix("--") else {
        throw CLIError.argument("missing value for \(flag)")
      }
      guard values[flag] == nil else {
        throw CLIError.argument("duplicate flag \(flag)")
      }
      values[flag] = value
      index += 2
    }

    switch name {
    case "validate-admission":
      guard Set(values.keys) == Set(["--manifest", "--schema"])
      else {
        throw CLIError.argument("validate-admission requires --manifest and --schema")
      }
      return .validateAdmission(
        manifest: try required(values, "--manifest"),
        schema: try required(values, "--schema")
      )
    case "run":
      let requiredFlags: Set<String> = ["--manifest", "--adapter", "--runtime-root", "--model-root", "--output"]
      guard Set(values.keys) == requiredFlags else {
        throw CLIError.argument("run requires --manifest, --adapter, --runtime-root, --model-root, and --output")
      }
      return .run(
        manifest: try required(values, "--manifest"),
        adapter: try required(values, "--adapter"),
        runtimeRoot: try required(values, "--runtime-root"),
        modelRoot: try required(values, "--model-root"),
        output: try required(values, "--output")
      )
    default:
      throw CLIError.argument("unknown command \(name)")
    }
  }

  private static func required(_ values: [String: String], _ flag: String) throws -> String {
    guard let value = values[flag], !value.isEmpty else {
      throw CLIError.argument("missing value for \(flag)")
    }
    return value
  }
}

enum CLIError: Error, Equatable, CustomStringConvertible {
  case argument(String)
  case file(String, String)
  case invalidManifest(String)
  case unsafePath(String)
  case outputExists(String)
  case lifecycle(String)

  var description: String {
    switch self {
    case .argument(let detail): return "argument: \(detail)"
    case .file(let path, let detail): return "file: \(path) \(detail)"
    case .invalidManifest(let detail): return "manifest: \(detail)"
    case .unsafePath(let detail): return "unsafe-path: \(detail)"
    case .outputExists(let path): return "output-exists: \(path)"
    case .lifecycle(let detail): return "lifecycle: \(detail)"
    }
  }
}

private struct AdmissionCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int? = nil

  init(stringValue: String) {
    self.stringValue = stringValue
  }

  init?(intValue: Int) {
    return nil
  }
}

private func strictKeys(
  _ container: KeyedDecodingContainer<AdmissionCodingKey>,
  allowed: Set<String>
) throws {
  if let key = container.allKeys.first(where: { !allowed.contains($0.stringValue) }) {
    throw CLIError.invalidManifest("unknown-key:\(key.stringValue)")
  }
}

private struct AudioAdmission: Decodable {
  let status: String
  let provenance: String
  let consentRecord: String

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: AdmissionCodingKey.self)
    try strictKeys(container, allowed: ["status", "provenance", "consentRecord"])
    status = try container.decode(String.self, forKey: AdmissionCodingKey(stringValue: "status"))
    provenance = try container.decode(String.self, forKey: AdmissionCodingKey(stringValue: "provenance"))
    consentRecord = try container.decode(String.self, forKey: AdmissionCodingKey(stringValue: "consentRecord"))
  }
}

private struct AdmissionCase: Decodable {
  let id: String
  let role: String
  let expectedLanguage: String
  let expectedCategory: String
  let audioPath: String
  let audioSHA256: String
  let evaluationOnlyContextPhrases: [String]
  let cancellationPoint: String
  let captureTemperature: String
  let claimsPartials: Bool

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: AdmissionCodingKey.self)
    let allowed: Set<String> = [
      "id", "role", "expectedLanguage", "expectedCategory", "audioPath",
      "audioSHA256", "evaluationOnlyContextPhrases", "cancellationPoint",
      "captureTemperature", "claimsPartials",
    ]
    try strictKeys(container, allowed: allowed)
    id = try container.decode(String.self, forKey: AdmissionCodingKey(stringValue: "id"))
    role = try container.decode(String.self, forKey: AdmissionCodingKey(stringValue: "role"))
    expectedLanguage = try container.decode(String.self, forKey: AdmissionCodingKey(stringValue: "expectedLanguage"))
    expectedCategory = try container.decode(String.self, forKey: AdmissionCodingKey(stringValue: "expectedCategory"))
    audioPath = try container.decode(String.self, forKey: AdmissionCodingKey(stringValue: "audioPath"))
    audioSHA256 = try container.decode(String.self, forKey: AdmissionCodingKey(stringValue: "audioSHA256"))
    evaluationOnlyContextPhrases = try container.decode(
      [String].self,
      forKey: AdmissionCodingKey(stringValue: "evaluationOnlyContextPhrases")
    )
    cancellationPoint = try container.decode(String.self, forKey: AdmissionCodingKey(stringValue: "cancellationPoint"))
    captureTemperature = try container.decode(String.self, forKey: AdmissionCodingKey(stringValue: "captureTemperature"))
    claimsPartials = try container.decode(Bool.self, forKey: AdmissionCodingKey(stringValue: "claimsPartials"))
  }
}

private struct AdmissionManifest: Decodable {
  let schemaVersion: Int
  let manifestID: String
  let revision: String
  let immutable: Bool
  let audioAdmission: AudioAdmission
  let cases: [AdmissionCase]

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: AdmissionCodingKey.self)
    let allowed: Set<String> = [
      "schemaVersion", "manifestID", "revision", "immutable", "audioAdmission", "cases",
    ]
    try strictKeys(container, allowed: allowed)
    schemaVersion = try container.decode(Int.self, forKey: AdmissionCodingKey(stringValue: "schemaVersion"))
    manifestID = try container.decode(String.self, forKey: AdmissionCodingKey(stringValue: "manifestID"))
    revision = try container.decode(String.self, forKey: AdmissionCodingKey(stringValue: "revision"))
    immutable = try container.decode(Bool.self, forKey: AdmissionCodingKey(stringValue: "immutable"))
    audioAdmission = try container.decode(AudioAdmission.self, forKey: AdmissionCodingKey(stringValue: "audioAdmission"))
    cases = try container.decode([AdmissionCase].self, forKey: AdmissionCodingKey(stringValue: "cases"))
  }

  var releaseEvidenceStatus: String {
    audioAdmission.status == "admitted"
      ? "eligible-for-real-audio-review"
      : "refused-no-admitted-real-audio"
  }

  func validate() throws {
    guard schemaVersion == 1 else {
      throw CLIError.invalidManifest("unsupported-schema-version")
    }
    guard immutable else {
      throw CLIError.invalidManifest("manifest-must-be-immutable")
    }
    try validateString(manifestID, field: "manifestID")
    try validateString(revision, field: "revision")
    guard audioAdmission.status == "admitted" || audioAdmission.status == "synthetic-only" else {
      throw CLIError.invalidManifest("audio-admission-status")
    }
    try validateString(audioAdmission.provenance, field: "audioAdmission.provenance")
    try validateString(audioAdmission.consentRecord, field: "audioAdmission.consentRecord")

    let expectedRoles = [
      "english-technical-prose",
      "english-developer-command",
      "mandarin-prose-numbers-units",
      "mandarin-technical-terms",
      "english-mandarin-switch",
      "mandarin-english-switch",
      "personal-dictionary-aliases",
      "silence-noise-hallucination",
      "cancellation-active-decode",
      "repeated-load-inference-unload-reload",
    ]
    guard cases.count == expectedRoles.count else {
      throw CLIError.invalidManifest("case-count")
    }
    guard cases.map(\.role) == expectedRoles else {
      throw CLIError.invalidManifest("case-roles-are-not-immutable")
    }
    guard Set(cases.map(\.id)).count == cases.count else {
      throw CLIError.invalidManifest("duplicate-case-id")
    }

    for (index, item) in cases.enumerated() {
      guard item.id == expectedRoles[index] else {
        throw CLIError.invalidManifest("case-id-\(index + 1)")
      }
      try validateString(item.id, field: "cases[\(index)].id")
      try validateString(item.role, field: "cases[\(index)].role")
      try validateString(item.expectedLanguage, field: "cases[\(index)].expectedLanguage")
      try validateString(item.expectedCategory, field: "cases[\(index)].expectedCategory")
      try validateString(item.audioPath, field: "cases[\(index)].audioPath")
      guard item.audioPath.first == "/", !item.audioPath.contains("://") else {
        throw CLIError.unsafePath("audio-path")
      }
      guard item.audioSHA256.count == 64,
        item.audioSHA256.allSatisfy({ $0.isHexDigit })
      else {
        throw CLIError.invalidManifest("audio-hash-\(index + 1)")
      }
      guard item.evaluationOnlyContextPhrases.count <= 100 else {
        throw CLIError.invalidManifest("context-phrase-count-\(index + 1)")
      }
      guard Set(item.evaluationOnlyContextPhrases).count == item.evaluationOnlyContextPhrases.count else {
        throw CLIError.invalidManifest("duplicate-context-phrase-\(index + 1)")
      }
      for phrase in item.evaluationOnlyContextPhrases {
        try validateString(phrase, field: "cases[\(index)].evaluationOnlyContextPhrases")
      }
      guard ["not-applicable", "after-first-partial", "during-active-decode"].contains(item.cancellationPoint) else {
        throw CLIError.invalidManifest("cancellation-point-\(index + 1)")
      }
      guard ["cold", "warm"].contains(item.captureTemperature) else {
        throw CLIError.invalidManifest("capture-temperature-\(index + 1)")
      }

      let audioURL = URL(fileURLWithPath: item.audioPath)
      if FileManager.default.fileExists(atPath: audioURL.path) {
        let attributes = try? FileManager.default.attributesOfItem(atPath: audioURL.path)
        guard attributes?[.type] as? FileAttributeType == .typeRegular else {
          throw CLIError.invalidManifest("audio-not-regular-\(index + 1)")
        }
        guard try sha256(audioURL) == item.audioSHA256.lowercased() else {
          throw CLIError.invalidManifest("audio-hash-\(index + 1)")
        }
      } else if audioAdmission.status == "admitted" {
        throw CLIError.invalidManifest("admitted-audio-missing-\(index + 1)")
      }
    }
  }
}

private enum AdmissionSchema {
  static func validate(instanceData: Data, schemaData: Data) throws {
    let instance: Any
    let schema: Any
    do {
      instance = try JSONSerialization.jsonObject(with: instanceData)
      schema = try JSONSerialization.jsonObject(with: schemaData)
    } catch {
      throw CLIError.invalidManifest("invalid-json-or-schema")
    }
    guard let schemaObject = schema as? [String: Any],
      schemaObject["type"] as? String == "object",
      schemaObject["additionalProperties"] as? Bool == false,
      let required = schemaObject["required"] as? [String],
      Set(required) == Set(["schemaVersion", "manifestID", "revision", "immutable", "audioAdmission", "cases"])
    else {
      throw CLIError.invalidManifest("invalid-schema-contract")
    }
    if let issue = unknownKey(instance: instance, schema: schemaObject, path: "") {
      throw CLIError.invalidManifest("unknown-key:\(issue)")
    }
  }

  private static func unknownKey(
    instance: Any,
    schema: [String: Any],
    path: String
  ) -> String? {
    if let object = instance as? [String: Any],
      let properties = schema["properties"] as? [String: Any] {
      for key in object.keys.sorted() {
        guard let childSchema = properties[key] as? [String: Any] else {
          if schema["additionalProperties"] as? Bool == false {
            return path + "/" + key
          }
          continue
        }
        if let issue = unknownKey(
          instance: object[key] as Any,
          schema: childSchema,
          path: path + "/" + key
        ) {
          return issue
        }
      }
    } else if let array = instance as? [Any], let itemSchema = schema["items"] as? [String: Any] {
      for (index, value) in array.enumerated() {
        if let issue = unknownKey(
          instance: value,
          schema: itemSchema,
          path: path + "/" + String(index)
        ) {
          return issue
        }
      }
    }
    return nil
  }
}

struct MeasurementArtifact: Codable, Sendable {
  let name: String
  let value: Double
  let unit: String
}

struct EvaluationContextPlan: Equatable, Sendable {
  let evaluationOnlyPhrases: [String]
  let appliedPhrases: [String]
}

func evaluationContextPlan(for phrases: [String]) -> EvaluationContextPlan {
  EvaluationContextPlan(evaluationOnlyPhrases: phrases, appliedPhrases: [])
}

func cancellationCaseStatus(for terminationPath: AdapterProcessTerminationPath) throws -> String {
  guard terminationPath == .cooperativeCancellation else {
    throw CLIError.lifecycle("cancellation-not-cooperative")
  }
  return "cancelled"
}

func requireCooperativeShutdown(_ terminationPath: AdapterProcessTerminationPath) throws {
  guard terminationPath == .cooperativeShutdown else {
    throw CLIError.lifecycle("shutdown-not-cooperative")
  }
}

private struct AdmissionCaseResult: Codable, Sendable {
  let caseID: String
  let status: String
  let claimedPartials: Bool
  let evaluationOnlyContextPhrases: [String]
  let appliedContextPhrases: [String]
  let measurementArtifacts: [MeasurementArtifact]
}

private struct AdmissionRunReport: Codable, Sendable {
  let schemaVersion: Int
  let manifestID: String
  let manifestRevision: String
  let releaseEvidenceStatus: String
  let audioAdmissionStatus: String
  let runtimeRevision: String
  let modelRevision: String
  let executableSHA256: String
  let libraryHashes: [String: String]
  let modelHashes: [String: String]
  let commandLine: [String]
  let operatingSystem: String
  let hardwareIdentity: String
  let networkIsolationMethod: String
  let startedAt: String
  let endedAt: String
  let childExitStatus: Int32?
  let cases: [AdmissionCaseResult]
}

private func decodeManifest(_ data: Data) throws -> AdmissionManifest {
  do {
    return try JSONDecoder().decode(AdmissionManifest.self, from: data)
  } catch let error as CLIError {
    throw error
  } catch {
    throw CLIError.invalidManifest("invalid-json-or-values")
  }
}

private func readRegularFile(path: String) throws -> Data {
  let url = URL(fileURLWithPath: path)
  guard url.isFileURL, url.path.first == "/" else {
    throw CLIError.unsafePath(path)
  }
  let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
  guard attributes?[.type] as? FileAttributeType == .typeRegular else {
    throw CLIError.file(path, "not-regular")
  }
  do {
    return try Data(contentsOf: url)
  } catch {
    throw CLIError.file(path, "read-failed")
  }
}

private func resolveExecutable(path: String) throws -> URL {
  let url = URL(fileURLWithPath: path)
  guard url.path.first == "/" else {
    throw CLIError.unsafePath("adapter-must-be-absolute")
  }
  let resolved = url.resolvingSymlinksInPath().standardizedFileURL
  guard FileManager.default.isExecutableFile(atPath: resolved.path) else {
    throw CLIError.unsafePath("adapter-not-executable")
  }
  let attributes = try? FileManager.default.attributesOfItem(atPath: resolved.path)
  guard attributes?[.type] as? FileAttributeType == .typeRegular else {
    throw CLIError.unsafePath("adapter-not-regular")
  }
  return resolved
}

private func validateModelRoot(path: String) throws -> URL {
  let url = URL(fileURLWithPath: path)
  guard url.path.first == "/" else {
    throw CLIError.unsafePath("model-root-must-be-absolute")
  }
  let standardized = url.standardizedFileURL
  let resolved = standardized.resolvingSymlinksInPath().standardizedFileURL
  guard standardized.path == resolved.path else {
    throw CLIError.unsafePath("model-root-symlink-escape")
  }
  let attributes = try? FileManager.default.attributesOfItem(atPath: standardized.path)
  guard attributes?[.type] as? FileAttributeType == .typeDirectory else {
    throw CLIError.unsafePath("model-root-not-directory")
  }
  guard let enumerator = FileManager.default.enumerator(
    at: standardized,
    includingPropertiesForKeys: nil,
    options: [.skipsPackageDescendants]
  ) else {
    return standardized
  }
  for case let item as URL in enumerator {
    let itemAttributes = try? FileManager.default.attributesOfItem(atPath: item.path)
    guard itemAttributes?[.type] as? FileAttributeType == .typeSymbolicLink else { continue }
    let target = item.resolvingSymlinksInPath().standardizedFileURL.path
    guard target == standardized.path || target.hasPrefix(standardized.path + "/") else {
      throw CLIError.unsafePath("model-root-symlink-escape")
    }
  }
  return standardized
}

private func validateNewOutput(path: String) throws {
  let url = URL(fileURLWithPath: path)
  guard url.path.first == "/" else {
    throw CLIError.unsafePath("output-must-be-absolute")
  }
  guard !FileManager.default.fileExists(atPath: url.path) else {
    throw CLIError.outputExists(path)
  }
  let parent = url.deletingLastPathComponent()
  let attributes = try? FileManager.default.attributesOfItem(atPath: parent.path)
  guard attributes?[.type] as? FileAttributeType == .typeDirectory else {
    throw CLIError.file(parent.path, "output-parent-not-directory")
  }
}

private func runCandidate(
  manifest: AdmissionManifest,
  adapterURL: URL,
  runtimeRootURL: URL,
  modelRootURL: URL,
  manifestPath: String,
  eventTimeout: Duration
) async throws -> AdmissionRunReport {
  let startedAt = timestamp(Date())
  let process = AdapterProcess(
    redactedRoots: [
      runtimeRootURL,
      modelRootURL,
      URL(fileURLWithPath: manifestPath).deletingLastPathComponent(),
    ]
  )
  let stream = await process.events()
  try await process.start(
    executableURL: adapterURL,
    arguments: [
      "--runtime-root", runtimeRootURL.path,
      "--model-root", modelRootURL.path,
    ],
    environment: ["PATH": "/usr/bin:/bin", "LC_ALL": "C"]
  )

  do {

  var runtimeRevision = "unreported"
  var modelRevision = "unreported"
  var results: [AdmissionCaseResult] = []

  let loadID = "load-initial"
  try await process.send(request(id: loadID, operation: .load))
  let loadResult = try await nextEvent(
    stream,
    requestID: loadID,
    timeout: eventTimeout,
    matching: { $0.kind == .ready }
  )
  if case .ready(_, let runtime, let model) = loadResult.event {
    runtimeRevision = runtime
    modelRevision = model
  }

  for item in manifest.cases {
    let requestID = "case-\(item.id)"
    let contextPlan = evaluationContextPlan(for: item.evaluationOnlyContextPhrases)
    try await process.send(
      request(
        id: requestID,
        operation: .transcribe,
        audioPath: item.audioPath,
        localeIdentifier: item.expectedLanguage,
        contextPhrases: contextPlan.appliedPhrases
      )
    )
    if item.cancellationPoint == "during-active-decode" {
      let cancellationPath = try await process.cancel(requestID: requestID, timeout: .seconds(2))
      results.append(
        AdmissionCaseResult(
          caseID: item.id,
          status: try cancellationCaseStatus(for: cancellationPath),
          claimedPartials: item.claimsPartials,
          evaluationOnlyContextPhrases: contextPlan.evaluationOnlyPhrases,
          appliedContextPhrases: contextPlan.appliedPhrases,
          measurementArtifacts: []
        )
      )
    } else {
      let caseResult = try await nextEvent(
        stream,
        requestID: requestID,
        timeout: eventTimeout,
        matching: { $0.kind == .final }
      )
      results.append(
        AdmissionCaseResult(
          caseID: item.id,
          status: "completed",
          claimedPartials: item.claimsPartials,
          evaluationOnlyContextPhrases: contextPlan.evaluationOnlyPhrases,
          appliedContextPhrases: contextPlan.appliedPhrases,
          measurementArtifacts: caseResult.measurements
        )
      )
    }

    if item.role == "repeated-load-inference-unload-reload" {
      let unloadID = "unload-\(item.id)"
      try await process.send(request(id: unloadID, operation: .unload))
      _ = try await nextEvent(
        stream,
        requestID: unloadID,
        timeout: eventTimeout,
        matching: { $0.kind == .unloaded }
      )
      let reloadID = "reload-\(item.id)"
      try await process.send(request(id: reloadID, operation: .load))
      _ = try await nextEvent(
        stream,
        requestID: reloadID,
        timeout: eventTimeout,
        matching: { $0.kind == .ready }
      )
      let reloadTranscribeID = "reload-transcribe-\(item.id)"
      try await process.send(
        request(
          id: reloadTranscribeID,
          operation: .transcribe,
          audioPath: item.audioPath,
          localeIdentifier: item.expectedLanguage,
          contextPhrases: contextPlan.appliedPhrases
        )
      )
      _ = try await nextEvent(
        stream,
        requestID: reloadTranscribeID,
        timeout: eventTimeout,
        matching: { $0.kind == .final }
      )
      let finalUnloadID = "final-unload-\(item.id)"
      try await process.send(request(id: finalUnloadID, operation: .unload))
      _ = try await nextEvent(
        stream,
        requestID: finalUnloadID,
        timeout: eventTimeout,
        matching: { $0.kind == .unloaded }
      )
    }
  }

  let shutdownPath = try await process.shutdown(timeout: .seconds(2))
  try requireCooperativeShutdown(shutdownPath)
  let diagnostics = await process.diagnostics()
  let hashMapping = try reportHashMapping(
    runtimeRootURL: runtimeRootURL,
    modelRootURL: modelRootURL
  )
  return AdmissionRunReport(
    schemaVersion: 1,
    manifestID: manifest.manifestID,
    manifestRevision: manifest.revision,
    releaseEvidenceStatus: manifest.releaseEvidenceStatus,
    audioAdmissionStatus: manifest.audioAdmission.status,
    runtimeRevision: runtimeRevision,
    modelRevision: modelRevision,
    executableSHA256: try sha256(adapterURL),
    libraryHashes: hashMapping.libraryHashes,
    modelHashes: hashMapping.modelHashes,
    commandLine: [adapterURL.path],
    operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
    hardwareIdentity: hardwareIdentity(),
    networkIsolationMethod: "not-enforced-by-harness",
    startedAt: startedAt,
    endedAt: timestamp(Date()),
    childExitStatus: diagnostics.childExitStatus,
    cases: results
  )
  } catch {
    await process.terminate()
    throw error
  }
}

private func request(
  id: String,
  operation: CandidateAdapterOperation,
  audioPath: String? = nil,
  localeIdentifier: String? = nil,
  contextPhrases: [String] = []
) -> CandidateAdapterRequest {
  CandidateAdapterRequest(
    schemaVersion: 1,
    requestID: id,
    operation: operation,
    audioPath: audioPath,
    sampleRate: audioPath == nil ? nil : 16_000,
    localeIdentifier: localeIdentifier,
    contextPhrases: contextPhrases,
    transcript: nil,
    protectedForms: [],
    cleanupMode: nil
  )
}

private enum EventWaitError: Error, Sendable {
  case timeout
  case failure
  case ended
  case measurementOverflow
  case stdoutOverflow
}

private let maximumMeasurementArtifacts = 256

func nextEvent(
  _ stream: AsyncThrowingStream<CandidateAdapterEvent, Error>,
  requestID: String,
  timeout: Duration,
  matching: @Sendable @escaping (CandidateAdapterEvent) -> Bool
) async throws -> EventWaitResult {
  do {
    return try await withThrowingTaskGroup(of: EventWaitResult.self) { group in
      group.addTask {
        var measurements: [MeasurementArtifact] = []
        do {
          for try await event in stream {
            if case .measurement(let eventRequestID, let name, let value, let unit) = event,
              eventRequestID == requestID {
              guard measurements.count < maximumMeasurementArtifacts else {
                throw EventWaitError.measurementOverflow
              }
              measurements.append(MeasurementArtifact(name: name, value: value, unit: unit))
              continue
            }
            guard event.requestID == requestID else { continue }
            if case .failure = event {
              throw EventWaitError.failure
            }
            if matching(event) {
              return EventWaitResult(event: event, measurements: measurements)
            }
          }
        } catch let error as EventWaitError {
          throw error
        } catch let error as AdapterProcessError {
          if case .stdoutFlood = error {
            throw EventWaitError.stdoutOverflow
          }
          throw EventWaitError.ended
        } catch {
          throw EventWaitError.ended
        }
        throw EventWaitError.ended
      }
      group.addTask {
        try await Task.sleep(for: timeout)
        throw EventWaitError.timeout
      }
      guard let result = try await group.next() else {
        throw EventWaitError.ended
      }
      group.cancelAll()
      return result
    }
  } catch let error as EventWaitError {
    switch error {
    case .timeout:
      throw CLIError.lifecycle("event-timeout")
    case .failure:
      throw CLIError.lifecycle("adapter-failure")
    case .ended:
      throw CLIError.lifecycle("event-stream-ended")
    case .measurementOverflow:
      throw CLIError.lifecycle("measurement-overflow")
    case .stdoutOverflow:
      throw CLIError.lifecycle("stdout-overflow")
    }
  } catch {
    throw error
  }
}

struct EventWaitResult: Sendable {
  let event: CandidateAdapterEvent
  let measurements: [MeasurementArtifact]
}

private func sha256(_ url: URL) throws -> String {
  let data: Data
  do {
    data = try Data(contentsOf: url, options: [.mappedIfSafe])
  } catch {
    throw CLIError.file(url.path, "read-failed")
  }
  return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func hashFiles(in root: URL) throws -> [String: String] {
  let resolvedRoot = canonicalURL(root)
  guard let enumerator = FileManager.default.enumerator(
    at: resolvedRoot,
    includingPropertiesForKeys: nil,
    options: [.skipsPackageDescendants]
  ) else {
    return [:]
  }
  var hashes: [String: String] = [:]
  for case let item as URL in enumerator {
    let attributes = try? FileManager.default.attributesOfItem(atPath: item.path)
    guard attributes?[.type] as? FileAttributeType == .typeRegular else { continue }
    let relative = String(item.path.dropFirst(resolvedRoot.path.count))
      .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    hashes[relative] = try sha256(item)
  }
  return hashes
}

private func canonicalURL(_ url: URL) -> URL {
  guard let pointer = Darwin.realpath(url.path, nil) else {
    return url.standardizedFileURL
  }
  defer { free(pointer) }
  return URL(fileURLWithPath: String(cString: pointer), isDirectory: true)
}

struct ReportHashMapping: Equatable, Sendable {
  let libraryHashes: [String: String]
  let modelHashes: [String: String]
}

func reportHashMapping(runtimeRootURL: URL, modelRootURL: URL) throws -> ReportHashMapping {
  ReportHashMapping(
    libraryHashes: try hashFiles(in: runtimeRootURL),
    modelHashes: try hashFiles(in: modelRootURL)
  )
}

private func writeExclusive(_ report: AdmissionRunReport, to path: String) throws {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
  let data = try encoder.encode(report)
  let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
  guard descriptor >= 0 else {
    throw CLIError.outputExists(path)
  }
  let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
  do {
    try handle.write(contentsOf: data)
    try handle.close()
  } catch {
    try? handle.close()
    throw CLIError.file(path, "write-failed")
  }
}

private func validateString(_ value: String, field: String) throws {
  guard !value.isEmpty,
    !value.unicodeScalars.contains(where: { $0 == "\0" || $0 == "\n" || $0 == "\r" })
  else {
    throw CLIError.invalidManifest("invalid-\(field)")
  }
}

private func timestamp(_ date: Date) -> String {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  return formatter.string(from: date)
}

private func hardwareIdentity() -> String {
  #if arch(arm64)
  return "arm64;logical-processors=\(ProcessInfo.processInfo.processorCount)"
  #else
  return "unknown;logical-processors=\(ProcessInfo.processInfo.processorCount)"
  #endif
}
