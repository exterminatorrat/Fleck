import CryptoKit
import Darwin
import Foundation

#if !arch(arm64)
#error("Whisper small control benchmark requires macOS arm64")
#endif

private let sandboxProfile = "(version 1) (allow default) (deny network*)"
private let environmentPath = "/usr/bin:/bin"
private let maximumCaseCount = 36
private let expectedModelFileType = 1
private let expectedQuantization = "mostly-F16/float16 (ggml ftype=1)"
private let outputNames = [
  "candidate-benchmark-evidence-v2.json",
  "model-evaluation-run-input-v1.json",
  "transcripts.jsonl",
  "diagnostics.json",
]

@main
private struct WhisperSmallCorpusBenchmark {
  static func main() {
    do {
      let options = try CommandLineOptions(arguments: Array(CommandLine.arguments.dropFirst()))
      if options.help {
        print(CommandLineOptions.usage)
        return
      }
      if options.selfTest {
        try SelfTests.run()
        return
      }
      try BenchmarkRunner(options: options).run()
    } catch let error as BenchmarkError {
      writeError("whisper-small-benchmark-failure: \(error.description)\n")
      Darwin.exit(2)
    } catch {
      writeError("whisper-small-benchmark-failure: \(error)\n")
      Darwin.exit(2)
    }
  }

  private static func writeError(_ message: String) {
    FileHandle.standardError.write(Data(message.utf8))
  }
}

private enum BenchmarkError: Error, CustomStringConvertible {
  case usage(String)
  case contract(String)
  case identity(String)
  case process(String)
  case publication(String)

  var description: String {
    switch self {
    case .usage(let message): return "usage: \(message)"
    case .contract(let message): return "contract: \(message)"
    case .identity(let message): return "identity: \(message)"
    case .process(let message): return "process: \(message)"
    case .publication(let message): return "publication: \(message)"
    }
  }
}

private struct CommandLineOptions {
  var controlPath: String?
  var repoRoot: String?
  var outputRoot: String?
  var selfTest = false
  var help = false

  static let usage = """
  Usage:
    run-whisper-small-corpus-benchmark.sh --control CONTROL.json --repo-root FLECK_ROOT --output-root EVIDENCE_ROOT
    run-whisper-small-corpus-benchmark.sh --self-test
  """

  init(arguments: [String]) throws {
    var index = 0
    while index < arguments.count {
      let argument = arguments[index]
      switch argument {
      case "--help", "-h":
        help = true
      case "--self-test":
        selfTest = true
      case "--control":
        controlPath = try Self.value(after: argument, arguments: arguments, index: &index)
      case "--repo-root":
        repoRoot = try Self.value(after: argument, arguments: arguments, index: &index)
      case "--output-root":
        outputRoot = try Self.value(after: argument, arguments: arguments, index: &index)
      default:
        throw BenchmarkError.usage("unknown argument \(argument)")
      }
      index += 1
    }

    if selfTest || help { return }
    guard let controlPath, let repoRoot, let outputRoot else {
      throw BenchmarkError.usage(Self.usage)
    }
    guard !controlPath.isEmpty, !repoRoot.isEmpty, !outputRoot.isEmpty else {
      throw BenchmarkError.usage(Self.usage)
    }
  }

  private static func value(
    after option: String,
    arguments: [String],
    index: inout Int
  ) throws -> String {
    index += 1
    guard index < arguments.count, !arguments[index].isEmpty,
      !arguments[index].hasPrefix("--")
    else {
      throw BenchmarkError.usage("\(option) requires a value")
    }
    return arguments[index]
  }
}

private struct Control: Decodable {
  let schemaVersion: Int
  let runID: String
  let candidate: CandidateControl
  let corpus: CorpusControl
  let execution: ExecutionControl

  func resolvingExternalPaths() throws -> Control {
    Control(
      schemaVersion: schemaVersion,
      runID: runID,
      candidate: CandidateControl(
        model: ModelControl(
          id: candidate.model.id,
          revision: candidate.model.revision,
          path: try requiredExternalPath(candidate.model.path, environmentKey: "FLECK_WHISPER_SMALL_MODEL_PATH"),
          byteCount: candidate.model.byteCount,
          sha256: candidate.model.sha256,
          fileType: candidate.model.fileType,
          quantization: candidate.model.quantization,
          license: candidate.model.license
        ),
        runtime: RuntimeControl(
          id: candidate.runtime.id,
          version: candidate.runtime.version,
          sourceCommit: candidate.runtime.sourceCommit,
          sourcePath: try requiredExternalPath(candidate.runtime.sourcePath, environmentKey: "FLECK_WHISPER_CPP_SOURCE_PATH"),
          cliPath: try requiredExternalPath(candidate.runtime.cliPath, environmentKey: "FLECK_WHISPER_CLI_PATH"),
          cliByteCount: candidate.runtime.cliByteCount,
          cliSHA256: candidate.runtime.cliSHA256,
          buildCachePath: try requiredExternalPath(candidate.runtime.buildCachePath, environmentKey: "FLECK_WHISPER_BUILD_CACHE_PATH"),
          architecture: candidate.runtime.architecture,
          license: candidate.runtime.license,
          buildFlags: candidate.runtime.buildFlags
        )
      ),
      corpus: CorpusControl(
        manifestPath: corpus.manifestPath,
        validationRoot: try requiredExternalPath(corpus.validationRoot, environmentKey: "FLECK_FLEURS_VALIDATION_ROOT"),
        compositeRoot: try requiredExternalPath(corpus.compositeRoot, environmentKey: "FLECK_FLEURS_COMPOSITE_ROOT"),
        manifestID: corpus.manifestID,
        sourceRevision: corpus.sourceRevision,
        license: corpus.license,
        expectedCounts: corpus.expectedCounts
      ),
      execution: execution
    )
  }
}

private func requiredExternalPath(_ placeholder: String, environmentKey: String) throws -> String {
  guard placeholder == "${\(environmentKey)}" else {
    throw BenchmarkError.contract("external path must use ${\(environmentKey)} in the tracked control")
  }
  guard let value = ProcessInfo.processInfo.environment[environmentKey], !value.isEmpty else {
    throw BenchmarkError.usage("set \(environmentKey) to the existing external artifact path; no download is performed")
  }
  return value
}

private struct CandidateControl: Decodable {
  let model: ModelControl
  let runtime: RuntimeControl
}

private struct ModelControl: Decodable {
  let id: String
  let revision: String
  let path: String
  let byteCount: Int64
  let sha256: String
  let fileType: Int
  let quantization: String
  let license: String
}

private struct RuntimeControl: Decodable {
  let id: String
  let version: String
  let sourceCommit: String
  let sourcePath: String
  let cliPath: String
  let cliByteCount: Int64
  let cliSHA256: String
  let buildCachePath: String
  let architecture: String
  let license: String
  let buildFlags: [String: String]
}

private struct CorpusControl: Decodable {
  let manifestPath: String
  let validationRoot: String
  let compositeRoot: String
  let manifestID: String
  let sourceRevision: String
  let license: String
  let expectedCounts: [String: Int]
}

private struct ExecutionControl: Decodable {
  let expectedWarmCaseCount: Int
  let coldCaseIDs: [String]
  let cancellationCaseID: String
  let maximumStdoutBytes: Int
  let maximumStderrBytes: Int
  let maximumJSONBytes: Int
  let pollMilliseconds: Int
  let warmTimeoutSeconds: Int
  let coldTimeoutSeconds: Int
  let cancellationTimeoutSeconds: Int
}

private struct CorpusManifest: Decodable {
  let schemaVersion: Int
  let manifestID: String
  let immutable: Bool
  let source: CorpusSource
  let cases: [ManifestCase]
}

private struct CorpusSource: Decodable {
  let dataset: String
  let revision: String
  let license: String
}

private struct ManifestCase: Decodable {
  let id: String
  let sourceFile: String
  let language: String
  let sourceClass: String
  let audioSHA256: String
  let audioDurationMilliseconds: Int
  let audioBytes: Int64
  let reference: String
  let protectedExpectations: [ManifestExpectation]
  let naturalCodeSwitch: Bool
  let codeSwitchSpans: [ManifestSpan]?
}

private struct ManifestExpectation: Decodable {
  let kind: String
  let text: String
  let comparison: String
}

private struct ManifestSpan: Decodable {
  let startSample: Int
  let endSample: Int
  let language: String
  let reference: String
  let sourceCaseID: String
}

private struct PreparedCase {
  let id: String
  let sourceFile: String
  let language: String
  let sourceClass: String
  let audioSHA256: String
  let audioDurationMilliseconds: Double
  let reference: String
  let protectedExpectations: [ManifestExpectation]
  let codeSwitchSpans: [ManifestSpan]
  let audioURL: URL
}

private struct ParsedCLIOutput {
  let raw: [String: Any]
  let rawSegments: [[String: Any]]
  let rawHypothesis: String
  let hypothesis: String
  let detectedLanguage: String
  let modelFileType: Int
}

private struct OutputObservation {
  let caseID: String
  let parsed: ParsedCLIOutput
  let completedAtNanoseconds: UInt64
  let processStartToCompletionMilliseconds: Double
  let completionIntervalMilliseconds: Double
}

private struct NativeTiming {
  let loadMilliseconds: Double?
  let totalMilliseconds: Double?
}

private struct ProcessCapture {
  let data: Data
  let totalBytes: Int
  let truncated: Bool

  var preview: String {
    String(decoding: data, as: UTF8.self)
      .replacingOccurrences(of: "\0", with: "")
  }
}

private struct ResourcePeaks {
  let residentBytes: Int64
  let physicalFootprintBytes: Int64
}

private struct ProcessRecord {
  let pid: Int32
  let exitCode: Int32
  let terminationReason: String
  let wallMilliseconds: Double
  let resourcePeaks: ResourcePeaks
  let stdout: ProcessCapture
  let stderr: ProcessCapture
  let nativeTiming: NativeTiming
}

private struct InferenceRun {
  let observations: [OutputObservation]
  let process: ProcessRecord
  let expectedCaseIDs: [String]
  let cancellation: CancellationResult?
}

private struct CancellationResult {
  let caseID: String
  let markerSeen: Bool
  let markerDescription: String
  let killSent: Bool
  let processExited: Bool
  let noLateOutput: Bool
  let outcome: String
  let exitCode: Int32
}

private struct PreparedPlan {
  let control: Control
  let repoRoot: URL
  let outputRoot: URL
  let manifest: CorpusManifest
  let cases: [PreparedCase]
  let hardware: Hardware
  let modelSHA256: String
  let cliSHA256: String
  let modelBytes: Int64
  let cliBytes: Int64
}

private struct Hardware {
  let hwModel: String
  let chip: String
  let architecture: String
  let memoryBytes: Int64
  let osBuild: String
}

private final class BoundedPipeReader: @unchecked Sendable {
  private let handle: FileHandle
  private let maximumBytes: Int
  private let onChunk: ((Data) -> Void)?
  private let group = DispatchGroup()
  private let lock = NSLock()
  private var captured = Data()
  private var totalBytes = 0
  private var truncated = false

  init(handle: FileHandle, maximumBytes: Int, onChunk: ((Data) -> Void)? = nil) {
    self.handle = handle
    self.maximumBytes = maximumBytes
    self.onChunk = onChunk
  }

  func start() {
    group.enter()
    DispatchQueue.global(qos: .utility).async { [self] in
      defer { group.leave() }
      while true {
        let chunk = handle.readData(ofLength: 1)
        guard !chunk.isEmpty else { return }
        onChunk?(chunk)
        lock.lock()
        totalBytes += chunk.count
        let remaining = maximumBytes - captured.count
        if remaining > 0 {
          captured.append(chunk.prefix(remaining))
        }
        if chunk.count > max(remaining, 0) {
          truncated = true
        }
        lock.unlock()
      }
    }
  }

  func wait() -> ProcessCapture {
    group.wait()
    lock.lock()
    defer { lock.unlock() }
    return ProcessCapture(data: captured, totalBytes: totalBytes, truncated: truncated)
  }
}

private final class MarkerObserver: @unchecked Sendable {
  private let marker: String
  private let lock = NSLock()
  private var onFound: (() -> Void)?
  private var rollingText = ""
  private var found = false
  private var foundAtNanoseconds: UInt64?

  init(marker: String) {
    self.marker = marker
  }

  func setOnFound(_ callback: @escaping () -> Void) {
    lock.lock()
    onFound = callback
    let alreadyFound = found
    lock.unlock()
    if alreadyFound { callback() }
  }

  func append(_ data: Data) {
    let text = String(decoding: data, as: UTF8.self)
    var callback: (() -> Void)?
    lock.lock()
    rollingText.append(text)
    if rollingText.count > 32_768 {
      rollingText = String(rollingText.suffix(32_768))
    }
    if !found, rollingText.contains(marker) {
      found = true
      foundAtNanoseconds = DispatchTime.now().uptimeNanoseconds
      callback = onFound
    }
    lock.unlock()
    callback?()
  }

  var seen: Bool {
    lock.lock()
    defer { lock.unlock() }
    return found
  }

  var seenAt: UInt64? {
    lock.lock()
    defer { lock.unlock() }
    return foundAtNanoseconds
  }
}

private final class ProcessKillController: @unchecked Sendable {
  private let lock = NSLock()
  private var processIdentifier: Int32 = 0
  private var sent = false

  func setProcessIdentifier(_ value: Int32) {
    lock.lock()
    processIdentifier = value
    lock.unlock()
  }

  @discardableResult
  func send() -> Bool {
    lock.lock()
    guard !sent, processIdentifier > 0 else {
      let alreadySent = sent
      lock.unlock()
      return alreadySent
    }
    let result = Darwin.kill(processIdentifier, SIGKILL)
    if result == 0 { sent = true }
    let succeeded = sent
    lock.unlock()
    return succeeded
  }

  var didSend: Bool {
    lock.lock()
    defer { lock.unlock() }
    return sent
  }
}

private final class ProcessResourceSampler: @unchecked Sendable {
  private let processIdentifier: Int32
  private let interval: TimeInterval
  private let lock = NSLock()
  private let group = DispatchGroup()
  private var stopped = false
  private var peakResidentBytes: Int64 = 0
  private var peakPhysicalFootprintBytes: Int64 = 0

  init(processIdentifier: Int32, interval: TimeInterval) {
    self.processIdentifier = processIdentifier
    self.interval = interval
  }

  func start() throws {
    let initial = try Self.sample(processIdentifier: processIdentifier)
    record(initial)
    group.enter()
    DispatchQueue.global(qos: .utility).async { [self] in
      defer { group.leave() }
      while true {
        lock.lock()
        let shouldStop = stopped
        lock.unlock()
        if shouldStop { return }
        if let sample = try? Self.sample(processIdentifier: processIdentifier) {
          record(sample)
        }
        Thread.sleep(forTimeInterval: interval)
      }
    }
  }

  func stop() throws -> ResourcePeaks {
    lock.lock()
    stopped = true
    lock.unlock()
    group.wait()
    lock.lock()
    defer { lock.unlock() }
    return ResourcePeaks(
      residentBytes: peakResidentBytes,
      physicalFootprintBytes: peakPhysicalFootprintBytes
    )
  }

  private func record(_ sample: ResourcePeaks) {
    lock.lock()
    peakResidentBytes = max(peakResidentBytes, sample.residentBytes)
    peakPhysicalFootprintBytes = max(
      peakPhysicalFootprintBytes,
      sample.physicalFootprintBytes
    )
    lock.unlock()
  }

  private static func sample(processIdentifier: Int32) throws -> ResourcePeaks {
    guard processIdentifier > 0 else {
      throw BenchmarkError.process("invalid child process identifier")
    }
    var usage = rusage_info_v4()
    let result = withUnsafeMutablePointer(to: &usage) { pointer in
      pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
        proc_pid_rusage(processIdentifier, RUSAGE_INFO_V4, $0)
      }
    }
    guard result == 0 else {
      throw BenchmarkError.process(
        "proc_pid_rusage failed for \(processIdentifier) with errno \(Darwin.errno)"
      )
    }
    guard let resident = Int64(exactly: usage.ri_resident_size),
      let physical = Int64(exactly: usage.ri_phys_footprint),
      resident >= 0, physical >= 0
    else {
      throw BenchmarkError.process("invalid resource sample")
    }
    return ResourcePeaks(residentBytes: resident, physicalFootprintBytes: physical)
  }
}

private final class BenchmarkRunner {
  private let options: CommandLineOptions

  init(options: CommandLineOptions) {
    self.options = options
  }

  func run() throws {
    guard let controlPath = options.controlPath,
      let repoRootPath = options.repoRoot,
      let outputRootPath = options.outputRoot
    else {
      throw BenchmarkError.usage(CommandLineOptions.usage)
    }

    let controlData = try Data(contentsOf: URL(fileURLWithPath: controlPath))
    try StrictJSON.validate(controlData, maximumBytes: 1_048_576)
    let control = try JSONDecoder().decode(Control.self, from: controlData).resolvingExternalPaths()
    let repoRoot = try canonicalDirectory(repoRootPath, label: "repository root")
    let outputRoot = try prepareOutputRoot(
      outputRootPath,
      repoRoot: repoRoot,
      createIfMissing: false
    )
    let plan = try preparePlan(
      control: control,
      repoRoot: repoRoot,
      outputRoot: outputRoot
    )
    try validateFinalTargets(in: outputRoot)
    try requireSandboxEnforcement()

    let workingRoot = outputRoot.appendingPathComponent(
      ".working-\(UUID().uuidString)",
      isDirectory: true
    )
    try createFreshDirectory(workingRoot)

    let warmDirectory = workingRoot.appendingPathComponent("warm", isDirectory: true)
    let warmRun = try runInference(
      plan: plan,
      cases: plan.cases,
      outputDirectory: warmDirectory,
      timeoutSeconds: control.execution.warmTimeoutSeconds,
      cancellation: false
    )
    guard warmRun.process.exitCode == 0,
      warmRun.observations.count == maximumCaseCount,
      warmRun.observations.map(\.caseID) == plan.cases.map(\.id)
    else {
      throw BenchmarkError.process("warm run did not complete the exact 36-case order")
    }

    var coldRuns: [String: InferenceRun] = [:]
    for caseID in control.execution.coldCaseIDs {
      guard let evaluationCase = plan.cases.first(where: { $0.id == caseID }) else {
        throw BenchmarkError.contract("cold case is absent from the prepared corpus: \(caseID)")
      }
      let coldDirectory = workingRoot.appendingPathComponent(
        "cold-\(caseID)",
        isDirectory: true
      )
      let coldRun = try runInference(
        plan: plan,
        cases: [evaluationCase],
        outputDirectory: coldDirectory,
        timeoutSeconds: control.execution.coldTimeoutSeconds,
        cancellation: false
      )
      guard coldRun.process.exitCode == 0,
        coldRun.observations.count == 1,
        coldRun.observations[0].caseID == caseID
      else {
        throw BenchmarkError.process("cold run did not complete \(caseID) exactly once")
      }
      guard coldRuns[caseID] == nil else {
        throw BenchmarkError.contract("duplicate cold run for \(caseID)")
      }
      coldRuns[caseID] = coldRun
    }
    guard coldRuns.count == 5 else {
      throw BenchmarkError.contract("five fresh cold runs are required")
    }

    let cancellationDirectory = workingRoot.appendingPathComponent(
      "cancellation",
      isDirectory: true
    )
    guard let cancellationCase = plan.cases.first(where: {
      $0.id == control.execution.cancellationCaseID
    }) else {
      throw BenchmarkError.contract("cancellation case is absent from the prepared corpus")
    }
    let cancellationRun = try runInference(
      plan: plan,
      cases: [cancellationCase],
      outputDirectory: cancellationDirectory,
      timeoutSeconds: control.execution.cancellationTimeoutSeconds,
      cancellation: true
    )
    guard let cancellation = cancellationRun.cancellation else {
      throw BenchmarkError.process("cancellation result was not captured")
    }

    let finalData = try buildPublicationData(
      plan: plan,
      warmRun: warmRun,
      coldRuns: coldRuns,
      cancellation: cancellation,
      workingRoot: workingRoot
    )
    let published = try AtomicPublisher.publish(
      finalData,
      outputRoot: outputRoot,
      workingRoot: workingRoot
    )
    try FileManager.default.removeItem(at: workingRoot)
    print("published whisper small control evidence: \(published.joined(separator: ", "))")
  }

  private func preparePlan(
    control: Control,
    repoRoot: URL,
    outputRoot: URL
  ) throws -> PreparedPlan {
    try validateControl(control)
    let manifestURL = resolve(control.corpus.manifestPath, relativeTo: repoRoot)
    _ = try canonicalRegularFile(manifestURL.path, label: "corpus manifest")
    let manifestData = try Data(contentsOf: manifestURL)
    try StrictJSON.validate(manifestData, maximumBytes: 8_388_608)
    let manifest = try JSONDecoder().decode(CorpusManifest.self, from: manifestData)
    let cases = try prepareCases(control: control, manifest: manifest)
    let modelSHA256 = try validateModel(control.candidate.model)
    let cliSHA256 = try validateCLI(control.candidate.runtime)
    try validateSource(control.candidate.runtime)
    let hardware = try validateHardware(control.candidate.runtime.architecture)
    return PreparedPlan(
      control: control,
      repoRoot: repoRoot,
      outputRoot: outputRoot,
      manifest: manifest,
      cases: cases,
      hardware: hardware,
      modelSHA256: modelSHA256,
      cliSHA256: cliSHA256,
      modelBytes: control.candidate.model.byteCount,
      cliBytes: control.candidate.runtime.cliByteCount
    )
  }

  private func validateControl(_ control: Control) throws {
    let candidate = control.candidate
    let model = candidate.model
    let runtime = candidate.runtime
    let corpus = control.corpus
    let execution = control.execution
    guard control.schemaVersion == 1 else {
      throw BenchmarkError.contract("unsupported control schema")
    }
    guard !control.runID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw BenchmarkError.contract("control runID is empty")
    }
    guard model.id == "ggerganov/whisper.cpp:ggml-small.bin",
      model.revision == "80da2d8bfee42b0e836fc3a9890373e5defc00a6",
      model.byteCount == 487_601_967,
      model.sha256 == "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b",
      model.fileType == expectedModelFileType,
      model.quantization == expectedQuantization,
      model.license == "MIT"
    else {
      throw BenchmarkError.identity("model control identity is not the pinned Whisper small control")
    }
    guard runtime.id == "whisper.cpp",
      runtime.version == "v1.9.2",
      runtime.sourceCommit == "306c88f4d1286aec1bf96e544632897886af5501",
      runtime.cliByteCount == 3_271_592,
      runtime.cliSHA256 == "cbde25b4d8db46feeab59355809725ff11ec4039b3251a1997ddd3a187901e03",
      runtime.architecture == "arm64",
      runtime.license == "MIT"
    else {
      throw BenchmarkError.identity("runtime control identity is not the pinned Whisper CLI")
    }
    let expectedBuildFlags = [
      "BUILD_SHARED_LIBS": "OFF",
      "CMAKE_BUILD_TYPE": "Release",
      "CMAKE_OSX_ARCHITECTURES": "",
      "CMAKE_OSX_DEPLOYMENT_TARGET": "14.0",
      "GGML_BLAS": "OFF",
      "GGML_METAL": "ON",
      "GGML_METAL_EMBED_LIBRARY": "ON",
      "GGML_OPENMP": "OFF",
      "WHISPER_COREML": "OFF",
      "WHISPER_CURL": "OFF",
      "WHISPER_BUILD_SERVER": "OFF",
      "WHISPER_OPENVINO": "OFF",
      "WHISPER_SDL2": "OFF",
      "WHISPER_BUILD_TESTS": "OFF",
      "WHISPER_BUILD_EXAMPLES": "ON",
    ]
    guard runtime.buildFlags == expectedBuildFlags else {
      throw BenchmarkError.identity("build safety flags do not match the pinned static Metal build")
    }
    guard corpus.manifestPath == "Tools/LocalDictationCandidateAdapters/Benchmarks/Corpus/manifest-v1.json",
      corpus.manifestID == "fleurs-a3c817c-local-dictation-corpus-v1",
      corpus.sourceRevision == "a3c817cbf7c08863e0c472861c7c39e27ce7f38e",
      corpus.license == "CC-BY-4.0",
      corpus.expectedCounts == ["english": 12, "mandarin": 12, "mixed": 12]
    else {
      throw BenchmarkError.contract("corpus control pins are not exact")
    }
    guard execution.expectedWarmCaseCount == maximumCaseCount,
      execution.coldCaseIDs.count == 5,
      execution.cancellationCaseID == "mixed-01",
      execution.maximumStdoutBytes > 0,
      execution.maximumStderrBytes >= execution.maximumStdoutBytes,
      execution.maximumJSONBytes > 0,
      execution.pollMilliseconds > 0,
      execution.warmTimeoutSeconds > 0,
      execution.coldTimeoutSeconds > 0,
      execution.cancellationTimeoutSeconds > 0
    else {
      throw BenchmarkError.contract("execution controls are incomplete")
    }
    let coldLanguages = execution.coldCaseIDs.map { id in
      if id.hasPrefix("en_us-") { return "english" }
      if id.hasPrefix("cmn_hans_cn-") { return "mandarin" }
      if id.hasPrefix("mixed-") { return "mixed" }
      return "unknown"
    }
    guard coldLanguages.filter({ $0 == "english" }).count == 2,
      coldLanguages.filter({ $0 == "mandarin" }).count == 2,
      coldLanguages.filter({ $0 == "mixed" }).count == 1,
      !coldLanguages.contains("unknown")
    else {
      throw BenchmarkError.contract("cold controls must be two English, two Mandarin, and one composite")
    }
  }

  private func prepareCases(
    control: Control,
    manifest: CorpusManifest
  ) throws -> [PreparedCase] {
    guard manifest.schemaVersion == 1, manifest.immutable,
      manifest.manifestID == control.corpus.manifestID,
      manifest.source.dataset == "google/fleurs",
      manifest.source.revision == control.corpus.sourceRevision,
      manifest.source.license == control.corpus.license
    else {
      throw BenchmarkError.contract("corpus manifest provenance does not match the control")
    }

    let selected = manifest.cases.filter {
      $0.sourceClass == "publicHuman" || $0.sourceClass == "publicHumanComposite"
    }
    guard selected.count == maximumCaseCount else {
      throw BenchmarkError.contract("corpus must contain exactly 36 speech cases")
    }
    let englishCount = selected.filter { $0.language == "english" && $0.sourceClass == "publicHuman" }.count
    let mandarinCount = selected.filter { $0.language == "mandarin" && $0.sourceClass == "publicHuman" }.count
    let mixedCount = selected.filter { $0.language == "mixed" && $0.sourceClass == "publicHumanComposite" }.count
    guard englishCount == 12, mandarinCount == 12, mixedCount == 12 else {
      throw BenchmarkError.contract("corpus classes must be 12 English, 12 Mandarin, and 12 composite")
    }

    var seenIDs = Set<String>()
    return try selected.map { manifestCase in
      guard seenIDs.insert(manifestCase.id).inserted else {
        throw BenchmarkError.contract("duplicate corpus case ID \(manifestCase.id)")
      }
      guard !manifestCase.naturalCodeSwitch else {
        throw BenchmarkError.contract("natural code-switch claims are forbidden")
      }
      guard validHash(manifestCase.audioSHA256), manifestCase.audioDurationMilliseconds > 0,
        manifestCase.audioBytes > 0
      else {
        throw BenchmarkError.contract("invalid audio identity for \(manifestCase.id)")
      }
      let rootPath: String
      if manifestCase.sourceClass == "publicHumanComposite" {
        rootPath = control.corpus.compositeRoot
        guard manifestCase.language == "mixed",
          let spans = manifestCase.codeSwitchSpans,
          spans.count == 2,
          spans.map(\.language).contains("en_us"),
          spans.map(\.language).contains("cmn_hans_cn")
        else {
          throw BenchmarkError.contract("composite case \(manifestCase.id) is not an artificial EN/ZH pair")
        }
      } else {
        rootPath = control.corpus.validationRoot
        guard manifestCase.language == "english" || manifestCase.language == "mandarin",
          (manifestCase.codeSwitchSpans ?? []).isEmpty
        else {
          throw BenchmarkError.contract("non-composite case \(manifestCase.id) has invalid language spans")
        }
      }
      let root = try canonicalDirectory(rootPath, label: "corpus root")
      let audioURL = try resolveContainedAudio(
        relativePath: manifestCase.sourceFile,
        root: root,
        expectedBytes: manifestCase.audioBytes,
        expectedSHA256: manifestCase.audioSHA256,
        expectedDurationMilliseconds: manifestCase.audioDurationMilliseconds,
        label: manifestCase.id
      )
      return PreparedCase(
        id: manifestCase.id,
        sourceFile: manifestCase.sourceFile,
        language: manifestCase.language,
        sourceClass: manifestCase.sourceClass,
        audioSHA256: manifestCase.audioSHA256,
        audioDurationMilliseconds: Double(manifestCase.audioDurationMilliseconds),
        reference: manifestCase.reference,
        protectedExpectations: manifestCase.protectedExpectations,
        codeSwitchSpans: manifestCase.codeSwitchSpans ?? [],
        audioURL: audioURL
      )
    }
  }

  private func validateModel(_ model: ModelControl) throws -> String {
    let url = try canonicalRegularFile(model.path, label: "model")
    let receipt = try hashFile(url)
    guard receipt.bytes == model.byteCount, receipt.sha256 == model.sha256 else {
      throw BenchmarkError.identity("model byte count or SHA-256 mismatch")
    }
    let header = try readPrefix(url, count: 48)
    guard header.count >= 48,
      Array(header.prefix(4)) == [0x6c, 0x6d, 0x67, 0x67]
    else {
      throw BenchmarkError.identity("model is not the expected ggml file")
    }
    let fileType = Int(readUInt32LE(header, offset: 44))
    guard fileType == model.fileType, fileType == expectedModelFileType else {
      throw BenchmarkError.identity("model ftype is not the expected float16 control value")
    }
    guard model.quantization == expectedQuantization else {
      throw BenchmarkError.identity("model quantization label is not truthful")
    }
    return receipt.sha256
  }

  private func validateCLI(_ runtime: RuntimeControl) throws -> String {
    let url = try canonicalRegularFile(runtime.cliPath, label: "whisper CLI")
    guard access(url.path, X_OK) == 0 else {
      throw BenchmarkError.identity("whisper CLI is not executable")
    }
    let receipt = try hashFile(url)
    guard receipt.bytes == runtime.cliByteCount, receipt.sha256 == runtime.cliSHA256 else {
      throw BenchmarkError.identity("whisper CLI byte count or SHA-256 mismatch")
    }
    try validateArm64MachO(url)
    let version = try runLocalCommand(
      executable: "/usr/bin/sandbox-exec",
      arguments: ["-p", sandboxProfile, url.path, "--version"],
      environment: ["PATH": environmentPath, "LC_ALL": "C"]
    )
    guard version.exitCode == 0,
      version.stdout.contains("whisper.cpp version: 1.9.2")
    else {
      throw BenchmarkError.identity("whisper CLI version is not v1.9.2")
    }
    return receipt.sha256
  }

  private func validateSource(_ runtime: RuntimeControl) throws {
    let source = try canonicalDirectory(runtime.sourcePath, label: "whisper source")
    let cache = try canonicalRegularFile(runtime.buildCachePath, label: "whisper CMake cache")
    let topLevel = try runLocalCommand(
      executable: "/usr/bin/git",
      arguments: ["-C", source.path, "rev-parse", "--show-toplevel"]
    )
    let head = try runLocalCommand(
      executable: "/usr/bin/git",
      arguments: ["-C", source.path, "rev-parse", "HEAD"]
    )
    let status = try runLocalCommand(
      executable: "/usr/bin/git",
      arguments: ["-C", source.path, "status", "--porcelain=v1"]
    )
    let tag = try runLocalCommand(
      executable: "/usr/bin/git",
      arguments: ["-C", source.path, "describe", "--tags", "--exact-match"]
    )
    guard topLevel.exitCode == 0,
      URL(fileURLWithPath: topLevel.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        .standardizedFileURL.path == source.path,
      head.exitCode == 0,
      head.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == runtime.sourceCommit,
      status.exitCode == 0,
      status.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      tag.exitCode == 0,
      tag.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == runtime.version
    else {
      throw BenchmarkError.identity("whisper source is not the exact clean tagged commit")
    }

    let cacheText = try String(contentsOf: cache, encoding: .utf8)
    let expectedFlags = runtime.buildFlags
    for (key, value) in expectedFlags {
      guard cmakeValue(cacheText, key: key) == value else {
        throw BenchmarkError.identity("CMakeCache flag \(key) is not \(value)")
      }
    }
    guard cmakeValue(cacheText, key: "WHISPER_BUILD_EXAMPLES") == "ON" else {
      throw BenchmarkError.identity("CMakeCache does not identify the CLI example build")
    }
  }

  private func validateHardware(_ expectedArchitecture: String) throws -> Hardware {
    let architecture = machineArchitecture()
    guard architecture == expectedArchitecture else {
      throw BenchmarkError.identity("host architecture is \(architecture), expected \(expectedArchitecture)")
    }
    return Hardware(
      hwModel: sysctlString("hw.model") ?? "unknown",
      chip: sysctlString("machdep.cpu.brand_string") ?? "Apple Silicon",
      architecture: architecture,
      memoryBytes: sysctlInt64("hw.memsize") ?? 0,
      osBuild: sysctlString("kern.osproductversion") ?? ProcessInfo.processInfo.operatingSystemVersionString
    )
  }

  private func runInference(
    plan: PreparedPlan,
    cases: [PreparedCase],
    outputDirectory: URL,
    timeoutSeconds: Int,
    cancellation: Bool
  ) throws -> InferenceRun {
    guard !cases.isEmpty else {
      throw BenchmarkError.process("cannot launch with an empty case set")
    }
    try createFreshDirectory(outputDirectory)
    let expectedCaseIDs = cases.map(\.id)
    let outputURLs = try cases.map { evaluationCase in
      guard evaluationCase.id.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else {
        throw BenchmarkError.contract("unsafe output case ID \(evaluationCase.id)")
      }
      let outputURL = outputDirectory.appendingPathComponent("\(evaluationCase.id).json")
      guard !FileManager.default.fileExists(atPath: outputURL.path) else {
        throw BenchmarkError.publication("refusing a preexisting CLI output target \(outputURL.path)")
      }
      return outputURL
    }

    var cliArguments = [
      "-m", plan.control.candidate.model.path,
      "-l", "auto",
      "-t", "4",
      "-p", "1",
      "-nt",
      "-oj",
    ]
    for outputURL in outputURLs {
      cliArguments.append(contentsOf: ["-of", outputURL.deletingPathExtension().path])
    }
    cliArguments.append(contentsOf: cases.map(\.audioURL.path))

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    let marker = cancellation
      ? MarkerObserver(marker: "main: processing '\(cases[0].audioURL.path)'")
      : nil
    let killController = cancellation ? ProcessKillController() : nil
    let stdoutReader = BoundedPipeReader(
      handle: stdoutPipe.fileHandleForReading,
      maximumBytes: plan.control.execution.maximumStdoutBytes
    )
    let stderrReader = BoundedPipeReader(
      handle: stderrPipe.fileHandleForReading,
      maximumBytes: plan.control.execution.maximumStderrBytes,
      onChunk: marker?.append
    )
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
    process.arguments = ["-p", sandboxProfile, plan.control.candidate.runtime.cliPath] + cliArguments
    process.environment = ["PATH": environmentPath, "LC_ALL": "C"]
    process.currentDirectoryURL = plan.repoRoot
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    stdoutReader.start()
    stderrReader.start()
    let start = DispatchTime.now().uptimeNanoseconds
    do {
      try process.run()
    } catch {
      _ = stdoutReader.wait()
      _ = stderrReader.wait()
      throw BenchmarkError.process("failed to launch sandboxed whisper CLI: \(error)")
    }
    let pid = process.processIdentifier
    killController?.setProcessIdentifier(pid)
    marker?.setOnFound { [killController] in
      _ = killController?.send()
    }
    let sampler = ProcessResourceSampler(processIdentifier: pid, interval: 0.05)
    try sampler.start()

    var observations: [OutputObservation] = []
    var observedIDs = Set<String>()
    var previousCompletion = start
    var killSent = false
    var timedOut = false
    let deadline = start + UInt64(timeoutSeconds) * 1_000_000_000

    while process.isRunning {
      let now = DispatchTime.now().uptimeNanoseconds
      if !cancellation || !killSent {
        try observeOutputs(
          cases: cases,
          outputURLs: outputURLs,
          expectedModelPath: plan.control.candidate.model.path,
          maximumJSONBytes: plan.control.execution.maximumJSONBytes,
          startNanoseconds: start,
          previousCompletionNanoseconds: &previousCompletion,
          observations: &observations,
          observedIDs: &observedIDs
        )
      }
      if cancellation, !killSent, marker?.seen == true {
        guard killController?.send() == true else {
          throw BenchmarkError.process("forced cancellation could not send SIGKILL")
        }
        killSent = true
      }
      if now >= deadline {
        timedOut = true
        if cancellation {
          killSent = killController?.send() == true
        } else {
          _ = kill(pid, SIGKILL)
          killSent = true
        }
        break
      }
      Thread.sleep(forTimeInterval: Double(plan.control.execution.pollMilliseconds) / 1_000.0)
    }
    process.waitUntilExit()
    let end = DispatchTime.now().uptimeNanoseconds
    let resourcePeaks = try sampler.stop()
    let stdout = stdoutReader.wait()
    let stderr = stderrReader.wait()
    let nativeTiming = parseNativeTiming(stderr.preview)

    if !cancellation {
      try observeOutputs(
        cases: cases,
        outputURLs: outputURLs,
        expectedModelPath: plan.control.candidate.model.path,
        maximumJSONBytes: plan.control.execution.maximumJSONBytes,
        startNanoseconds: start,
        previousCompletionNanoseconds: &previousCompletion,
        observations: &observations,
        observedIDs: &observedIDs
      )
    }

    guard !stdout.truncated, !stderr.truncated else {
      throw BenchmarkError.process("bounded CLI output was flooded")
    }
    if timedOut {
      throw BenchmarkError.process("CLI timed out and was force-terminated")
    }

    let processRecord = ProcessRecord(
      pid: pid,
      exitCode: process.terminationStatus,
      terminationReason: process.terminationReason == .exit ? "exit" : "signal",
      wallMilliseconds: elapsedMilliseconds(from: start, to: end),
      resourcePeaks: resourcePeaks,
      stdout: stdout,
      stderr: stderr,
      nativeTiming: nativeTiming
    )

    if cancellation {
      Thread.sleep(forTimeInterval: 0.25)
      let lateOutput = outputURLs.contains { FileManager.default.fileExists(atPath: $0.path) }
      let markerSeen = marker?.seen == true
      let sentKill = killController?.didSend == true || killSent
      let forced = markerSeen && sentKill && process.terminationReason != .exit && !lateOutput
      let cancellationResult = CancellationResult(
        caseID: cases[0].id,
        markerSeen: markerSeen,
        markerDescription: markerSeen
          ? "positive processing-start diagnostic"
          : "processing-start marker was not observed",
        killSent: sentKill,
        processExited: !process.isRunning,
        noLateOutput: !lateOutput,
        outcome: forced ? "forced" : "inconclusive",
        exitCode: process.terminationStatus
      )
      return InferenceRun(
        observations: observations,
        process: processRecord,
        expectedCaseIDs: expectedCaseIDs,
        cancellation: cancellationResult
      )
    }

    guard process.terminationReason == .exit, process.terminationStatus == 0 else {
      throw BenchmarkError.process(
        "CLI exited unsuccessfully (\(process.terminationStatus)): \(stderr.preview.prefix(512))"
      )
    }
    guard observations.map(\.caseID) == expectedCaseIDs else {
      throw BenchmarkError.process("CLI output order or cardinality did not match inputs")
    }
    let actualEntries = try FileManager.default.contentsOfDirectory(
      at: outputDirectory,
      includingPropertiesForKeys: nil
    ).map(\.lastPathComponent).sorted()
    let expectedEntries = outputURLs.map(\.lastPathComponent).sorted()
    guard actualEntries == expectedEntries else {
      throw BenchmarkError.process("CLI emitted unexpected or missing output files")
    }
    return InferenceRun(
      observations: observations,
      process: processRecord,
      expectedCaseIDs: expectedCaseIDs,
      cancellation: nil
    )
  }

  private func observeOutputs(
    cases: [PreparedCase],
    outputURLs: [URL],
    expectedModelPath: String,
    maximumJSONBytes: Int,
    startNanoseconds: UInt64,
    previousCompletionNanoseconds: inout UInt64,
    observations: inout [OutputObservation],
    observedIDs: inout Set<String>
  ) throws {
    for (index, outputURL) in outputURLs.enumerated() {
      let evaluationCase = cases[index]
      guard !observedIDs.contains(evaluationCase.id) else { continue }
      guard FileManager.default.fileExists(atPath: outputURL.path) else { continue }
      let type = lstatType(outputURL.path)
      guard type == S_IFREG else {
        throw BenchmarkError.process("CLI output is not a regular file: \(outputURL.path)")
      }
      let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
      let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
      guard size <= maximumJSONBytes else {
        throw BenchmarkError.process("CLI JSON output exceeded the bounded parse size")
      }
      guard size > 0 else { continue }
      do {
        let data = try Data(contentsOf: outputURL)
        try StrictJSON.validate(data, maximumBytes: maximumJSONBytes)
        let parsed = try parseCLIOutput(data, expectedModelPath: expectedModelPath)
        let completedAt = DispatchTime.now().uptimeNanoseconds
        let observation = OutputObservation(
          caseID: evaluationCase.id,
          parsed: parsed,
          completedAtNanoseconds: completedAt,
          processStartToCompletionMilliseconds: elapsedMilliseconds(
            from: startNanoseconds,
            to: completedAt
          ),
          completionIntervalMilliseconds: elapsedMilliseconds(
            from: previousCompletionNanoseconds,
            to: completedAt
          )
        )
        previousCompletionNanoseconds = completedAt
        observations.append(observation)
        observedIDs.insert(evaluationCase.id)
      } catch let error as BenchmarkError {
        if observations.count == cases.count || !FileManager.default.fileExists(atPath: outputURL.path) {
          throw error
        }
      } catch {
        if observations.count == cases.count || !FileManager.default.fileExists(atPath: outputURL.path) {
          throw BenchmarkError.process("malformed CLI output for \(evaluationCase.id): \(error)")
        }
      }
    }
  }

  private func buildPublicationData(
    plan: PreparedPlan,
    warmRun: InferenceRun,
    coldRuns: [String: InferenceRun],
    cancellation: CancellationResult,
    workingRoot: URL
  ) throws -> [String: Data] {
    let warmByID = Dictionary(uniqueKeysWithValues: warmRun.observations.map { ($0.caseID, $0) })
    let coldByID = coldRuns.compactMapValues { $0.observations.first }
    let coldIDs = Set(plan.control.execution.coldCaseIDs)
    let warmPeak = warmRun.process.resourcePeaks
    let completedCases = plan.cases.map { evaluationCase -> [String: Any] in
      let warmObservation = warmByID[evaluationCase.id]!
      let coldObservation = coldByID[evaluationCase.id]
      let selectedTiming = coldIDs.contains(evaluationCase.id)
        ? (coldObservation ?? warmObservation)
        : warmObservation
      let selectedPeaks = coldIDs.contains(evaluationCase.id)
        ? (coldRuns[evaluationCase.id]?.process.resourcePeaks ?? warmPeak)
        : warmPeak
      return evidenceCase(
        evaluationCase,
        hypothesis: warmObservation.parsed.hypothesis,
        observation: selectedTiming,
        peaks: selectedPeaks,
        timingSource: coldIDs.contains(evaluationCase.id)
          ? "five-fresh-cold-single-file"
          : "one-process-warm-output-completion-interval",
        warmObservation: warmObservation,
        coldObservation: coldObservation
      )
    }
    let accuracy = scoreAccuracy(plan.cases, warmByID)
    let evidence = try evidenceObject(
      plan: plan,
      cases: completedCases,
      warmRun: warmRun,
      coldRuns: coldRuns,
      cancellation: cancellation,
      accuracy: accuracy,
      workingRoot: workingRoot
    )
    let modelInput = try modelEvaluationInput(
      plan: plan,
      warmByID: warmByID,
      warmPeaks: warmPeak
    )
    let transcripts = try transcriptLines(
      plan: plan,
      warmByID: warmByID,
      coldByID: coldByID,
      warmRun: warmRun,
      coldRuns: coldRuns
    )
    let diagnostics = try diagnosticsObject(
      plan: plan,
      warmRun: warmRun,
      coldRuns: coldRuns,
      cancellation: cancellation,
      workingRoot: workingRoot
    )
    return [
      "candidate-benchmark-evidence-v2.json": try jsonData(evidence),
      "model-evaluation-run-input-v1.json": try jsonData(modelInput),
      "transcripts.jsonl": transcripts,
      "diagnostics.json": try jsonData(diagnostics),
    ]
  }

  private func evidenceCase(
    _ evaluationCase: PreparedCase,
    hypothesis: String,
    observation: OutputObservation,
    peaks: ResourcePeaks,
    timingSource: String,
    warmObservation: OutputObservation,
    coldObservation: OutputObservation?
  ) -> [String: Any] {
    let spans = evaluationCase.codeSwitchSpans.map { span in
      [
        "startMilliseconds": Double(span.startSample) / 16.0,
        "endMilliseconds": Double(span.endSample) / 16.0,
        "language": span.language == "en_us" ? "english" : "mandarin",
        "matched": codeSwitchSpanMatches(span.reference, hypothesis: hypothesis),
      ] as [String: Any]
    }
    var result: [String: Any] = [
      "id": evaluationCase.id,
      "language": evaluationCase.language,
      "sourceClass": evaluationCase.sourceClass,
      "audioSHA256": evaluationCase.audioSHA256,
      "audioDurationMilliseconds": evaluationCase.audioDurationMilliseconds,
      "reference": evaluationCase.reference,
      "hypothesis": hypothesis,
      "protectedExpectations": evaluationCase.protectedExpectations.map(expectationObject),
      "claimsNaturalCodeSwitch": false,
      "codeSwitchSpans": spans,
      "captureTemperature": 0.0,
      "timing": [
        "fileDecodeMilliseconds": observation.completionIntervalMilliseconds,
        "firstPartialMilliseconds": NSNull(),
        "isCold": coldObservation != nil && timingSource == "five-fresh-cold-single-file",
      ] as [String: Any],
      "peakResidentBytes": peaks.residentBytes,
      "peakPhysicalFootprintBytes": peaks.physicalFootprintBytes,
      "outcome": "transcribed",
      "cancellation": [
        "outcome": "notCancelled",
        "noLateOutput": false,
      ] as [String: Any],
      "timingSource": timingSource,
      "warmTiming": timingObject(warmObservation, isCold: false),
    ]
    if let coldObservation {
      result["coldTiming"] = timingObject(coldObservation, isCold: true)
    }
    return result
  }

  private func evidenceObject(
    plan: PreparedPlan,
    cases: [[String: Any]],
    warmRun: InferenceRun,
    coldRuns: [String: InferenceRun],
    cancellation: CancellationResult,
    accuracy: AccuracyMetrics,
    workingRoot: URL
  ) throws -> [String: Any] {
    let caseObjects = cases
    let coldTimings = caseObjects.compactMap { object -> Double? in
      guard let timing = object["timing"] as? [String: Any],
        (timing["isCold"] as? Bool) == true,
        let value = timing["fileDecodeMilliseconds"] as? Double else { return nil }
      return value
    }
    let warmTimings = caseObjects.compactMap { object -> Double? in
      guard let timing = object["timing"] as? [String: Any],
        (timing["isCold"] as? Bool) != true,
        let value = timing["fileDecodeMilliseconds"] as? Double else { return nil }
      return value
    }
    let peakResident = max(
      warmRun.process.resourcePeaks.residentBytes,
      coldRuns.values.map { $0.process.resourcePeaks.residentBytes }.max() ?? 0,
      cases.compactMap { ($0["peakResidentBytes"] as? NSNumber)?.int64Value }.max() ?? 0
    )
    let peakPhysical = max(
      warmRun.process.resourcePeaks.physicalFootprintBytes,
      coldRuns.values.map { $0.process.resourcePeaks.physicalFootprintBytes }.max() ?? 0,
      cases.compactMap { ($0["peakPhysicalFootprintBytes"] as? NSNumber)?.int64Value }.max() ?? 0
    )
    let loadMilliseconds = warmRun.process.nativeTiming.loadMilliseconds ?? 0
    let inferMilliseconds = max(0, warmRun.process.wallMilliseconds - loadMilliseconds)
    let lastCompletion = warmRun.observations.last?.processStartToCompletionMilliseconds ?? 0
    let teardownMilliseconds = max(0, warmRun.process.wallMilliseconds - lastCompletion)
    let reloadMilliseconds = coldRuns.values.reduce(0.0) { $0 + $1.process.wallMilliseconds }
    let lifecycle = [
      "load": lifecyclePhase(
        outcome: "succeeded",
        duration: loadMilliseconds,
        peaks: warmRun.process.resourcePeaks
      ),
      "infer": lifecyclePhase(
        outcome: "succeeded",
        duration: inferMilliseconds,
        peaks: warmRun.process.resourcePeaks
      ),
      "unload": lifecyclePhase(
        outcome: "succeeded",
        duration: teardownMilliseconds,
        peaks: warmRun.process.resourcePeaks
      ),
      "reload": lifecyclePhase(
        outcome: coldRuns.count == 5 ? "succeeded" : "failed",
        duration: reloadMilliseconds,
        peaks: ResourcePeaks(
          residentBytes: coldRuns.values.map { $0.process.resourcePeaks.residentBytes }.max() ?? 0,
          physicalFootprintBytes: coldRuns.values.map { $0.process.resourcePeaks.physicalFootprintBytes }.max() ?? 0
        )
      ),
    ] as [String: Any]
    let phaseSuccesses = coldRuns.count == 5
    let runID = "\(plan.control.runID)-\(Int(Date().timeIntervalSince1970))"
    let caseBindings = plan.cases.map {
      ["caseID": $0.id, "audioSHA256": $0.audioSHA256] as [String: Any]
    }
    let outputCompletion = plan.cases.compactMap { evaluationCase -> [String: Any]? in
      guard let warm = warmRun.observations.first(where: { $0.caseID == evaluationCase.id }) else {
        return nil
      }
      return [
        "caseID": evaluationCase.id,
        "isCold": false,
        "processOrdinal": 1,
        "processStartToOutputCompletionMilliseconds": warm.processStartToCompletionMilliseconds,
        "outputCompletionIntervalMilliseconds": warm.completionIntervalMilliseconds,
        "measurementLabel": "process-start-to-observed-valid-json-output-completion",
        "nativeDecodeMilliseconds": NSNull(),
        "stopToFinalMilliseconds": NSNull(),
      ]
    }
    let coldTimingEvidence = plan.control.execution.coldCaseIDs.compactMap { caseID -> [String: Any]? in
      guard let run = coldRuns[caseID], let observation = run.observations.first else { return nil }
      return [
        "caseID": caseID,
        "isCold": true,
        "processOrdinal": 2 + plan.control.execution.coldCaseIDs.firstIndex(of: caseID)!,
        "coldEndToEndMilliseconds": observation.processStartToCompletionMilliseconds,
        "outputCompletionIntervalMilliseconds": observation.completionIntervalMilliseconds,
        "nativeModelLoadMilliseconds": run.process.nativeTiming.loadMilliseconds.map { $0 as Any } ?? NSNull(),
        "nativeTotalMilliseconds": run.process.nativeTiming.totalMilliseconds.map { $0 as Any } ?? NSNull(),
        "measurementLabel": "process-start-to-observed-valid-json-output-completion",
      ]
    }
    let cancellationObject = cancellationObject(cancellation)
    let evidence: [String: Any] = [
      "schemaVersion": 2,
      "runID": runID,
      "claimScope": "candidateBenchmark",
      "evidenceClasses": ["publicHuman", "publicHumanComposite"],
      "candidate": [
        "modelID": plan.control.candidate.model.id,
        "modelRevision": plan.control.candidate.model.revision,
        "runtimeID": plan.control.candidate.runtime.id,
        "runtimeRevision": plan.control.candidate.runtime.sourceCommit,
        "quantization": plan.control.candidate.model.quantization,
        "license": plan.control.candidate.runtime.license,
      ] as [String: Any],
      "artifacts": [
        "archiveReceipt": [
          "id": "whisper-small-model",
          "revision": plan.control.candidate.model.revision,
          "sha256": plan.modelSHA256,
          "byteCount": plan.modelBytes,
        ] as [String: Any],
        "artifactReceipt": [
          "id": "whisper-cli-arm64-metal-static",
          "revision": plan.control.candidate.runtime.sourceCommit,
          "sha256": plan.cliSHA256,
          "byteCount": plan.cliBytes,
        ] as [String: Any],
        "installedFiles": [
          [
            "path": "whisper/ggml-small.bin",
            "sha256": plan.modelSHA256,
            "byteCount": plan.modelBytes,
          ],
          [
            "path": "whisper/whisper-cli",
            "sha256": plan.cliSHA256,
            "byteCount": plan.cliBytes,
          ],
        ] as [[String: Any]],
        "totalInstalledBytes": plan.modelBytes + plan.cliBytes,
      ] as [String: Any],
      "hardware": [
        "hwModel": plan.hardware.hwModel,
        "chip": plan.hardware.chip,
        "architecture": plan.hardware.architecture,
        "memoryBytes": plan.hardware.memoryBytes,
        "osBuild": plan.hardware.osBuild,
      ] as [String: Any],
      "corpus": [
        "manifestID": plan.manifest.manifestID,
        "revision": plan.manifest.source.revision,
        "license": plan.manifest.source.license,
        "caseBindings": caseBindings,
      ] as [String: Any],
      "privacy": [
        "policy": "offline candidate benchmark",
        "mechanism": "/usr/bin/sandbox-exec profile with network denied",
        "enforced": true,
        "claimsVerifiedOffline": true,
        "unexpectedConnectionCount": 0,
      ] as [String: Any],
      "aggregate": [
        "accuracy": [
          "englishWER": accuracy.englishWER.map { $0 as Any } ?? NSNull(),
          "mandarinCER": accuracy.mandarinCER.map { $0 as Any } ?? NSNull(),
          "mixedMER": accuracy.mixedMER.map { $0 as Any } ?? NSNull(),
          "codeSwitchSpanAccuracy": accuracy.codeSwitchSpanAccuracy.map { $0 as Any } ?? NSNull(),
          "protectedViolationCount": accuracy.protectedViolationCount,
        ] as [String: Any],
        "latency": [
          "coldP50Milliseconds": nearestRank(coldTimings, percentile: 0.50).map { $0 as Any } ?? NSNull(),
          "coldP95Milliseconds": nearestRank(coldTimings, percentile: 0.95).map { $0 as Any } ?? NSNull(),
          "warmP50Milliseconds": nearestRank(warmTimings, percentile: 0.50).map { $0 as Any } ?? NSNull(),
          "warmP95Milliseconds": nearestRank(warmTimings, percentile: 0.95).map { $0 as Any } ?? NSNull(),
        ] as [String: Any],
        "fileDecodeRTF": fileDecodeRTF(plan.cases, caseObjects),
        "peakResidentBytes": peakResident,
        "peakPhysicalFootprintBytes": peakPhysical,
        "totalStorageBytes": plan.modelBytes + plan.cliBytes,
        "lifecycleSummary": [
          "loadSucceeded": true,
          "inferSucceeded": true,
          "unloadSucceeded": true,
          "reloadSucceeded": phaseSuccesses,
          "allSucceeded": phaseSuccesses,
        ] as [String: Any],
      ] as [String: Any],
      "gate": [
        "automatedCandidatePass": false,
        "failureReasons": [
          "developer-only control benchmark; no admission decision",
          "batch-final-only CLI; no streaming or partial evidence",
          "forced cancellation is process termination, not cooperative cancellation",
        ],
        "releaseAdmitted": false,
      ] as [String: Any],
      "cases": caseObjects,
      "lifecycle": lifecycle,
      "benchmarkSemantics": [
        "runtimeVersion": plan.control.candidate.runtime.version,
        "sourceCommit": plan.control.candidate.runtime.sourceCommit,
        "translation": false,
        "language": "auto",
        "modelFileType": expectedModelFileType,
        "quantization": expectedQuantization,
        "resultSemantics": "batch-final-only",
        "claimsPartials": false,
        "nativeDecodeTimingObserved": false,
        "outputCompletionMeasurement": "valid JSON file observation",
        "warmProcessCount": 1,
        "warmInputCaseCount": maximumCaseCount,
        "coldProcessCount": coldRuns.count,
        "retryCount": 0,
        "warmOutputCompletion": outputCompletion,
        "coldOutputCompletion": coldTimingEvidence,
        "forcedCancellation": cancellationObject,
        "lifecycleTiming": [
          "loadMilliseconds": plan.cases.isEmpty ? NSNull() : (warmRun.process.nativeTiming.loadMilliseconds.map { $0 as Any } ?? NSNull()),
          "loadSource": "upstream whisper_print_timings diagnostic when present",
          "inferSource": "process wall interval after directly observed load diagnostic",
          "unloadSource": "process exit after final output; native unload duration not claimed",
          "reloadSource": "five fresh process launches",
        ] as [String: Any],
      ] as [String: Any],
    ]
    return evidence
  }

  private func modelEvaluationInput(
    plan: PreparedPlan,
    warmByID: [String: OutputObservation],
    warmPeaks: ResourcePeaks
  ) throws -> [String: Any] {
    let cases = plan.cases.map { evaluationCase -> [String: Any] in
      let observation = warmByID[evaluationCase.id]!
      return [
        "id": evaluationCase.id,
        "language": evaluationCase.language,
        "reference": evaluationCase.reference,
        "hypothesis": observation.parsed.hypothesis,
        "protectedExpectations": evaluationCase.protectedExpectations.map(expectationObject),
        "timing": [
          "isCold": false,
          "firstPartialMilliseconds": NSNull(),
          "stopToFinalMilliseconds": NSNull(),
          "stopToInsertionMilliseconds": NSNull(),
          "measurementSemantics": "one-process warm output-completion interval; not native decode timing",
        ] as [String: Any],
        "peakResidentBytes": warmPeaks.residentBytes,
      ]
    }
    return [
      "schemaVersion": 1,
      "modelID": plan.control.candidate.model.id,
      "revision": plan.control.candidate.model.revision,
      "runtime": plan.control.candidate.runtime.id,
      "quantization": plan.control.candidate.model.quantization,
      "hardware": plan.hardware.hwModel,
      "unexpectedNetworkConnectionCount": 0,
      "cases": cases,
      "benchmarkSemantics": [
        "transcriptSource": "warm-one-process",
        "resultSemantics": "batch-final-only",
        "claimsPartials": false,
        "timingLabel": "process-start-to-observed-valid-json-output-completion",
      ] as [String: Any],
    ]
  }

  private func transcriptLines(
    plan: PreparedPlan,
    warmByID: [String: OutputObservation],
    coldByID: [String: OutputObservation],
    warmRun: InferenceRun,
    coldRuns: [String: InferenceRun]
  ) throws -> Data {
    var data = Data()
    for (index, evaluationCase) in plan.cases.enumerated() {
      let warm = warmByID[evaluationCase.id]!
      let object: [String: Any] = [
        "schemaVersion": 1,
        "recordType": "transcript",
        "ordinal": index + 1,
        "caseID": evaluationCase.id,
        "sourceClass": evaluationCase.sourceClass,
        "language": evaluationCase.language,
        "sourceFile": evaluationCase.sourceFile,
        "audioSHA256": evaluationCase.audioSHA256,
        "reference": evaluationCase.reference,
        "rawHypothesis": warm.parsed.rawHypothesis,
        "hypothesis": warm.parsed.hypothesis,
        "rawSegments": warm.parsed.rawSegments,
        "detectedLanguage": warm.parsed.detectedLanguage,
        "modelFileType": warm.parsed.modelFileType,
        "parameters": [
          "language": "auto",
          "translation": false,
        ] as [String: Any],
        "timing": [
          "isCold": false,
          "processStartToOutputCompletionMilliseconds": warm.processStartToCompletionMilliseconds,
          "outputCompletionIntervalMilliseconds": warm.completionIntervalMilliseconds,
          "measurementLabel": "process-start-to-observed-valid-json-output-completion",
          "firstPartialMilliseconds": NSNull(),
          "stopToFinalMilliseconds": NSNull(),
        ] as [String: Any],
        "coldComparison": coldByID[evaluationCase.id].map { cold in
          [
            "isCold": true,
            "processStartToOutputCompletionMilliseconds": cold.processStartToCompletionMilliseconds,
            "outputCompletionIntervalMilliseconds": cold.completionIntervalMilliseconds,
            "measurementLabel": "process-start-to-observed-valid-json-output-completion",
            "hypothesis": cold.parsed.hypothesis,
            "sameHypothesisAsWarm": cold.parsed.hypothesis == warm.parsed.hypothesis,
          ] as [String: Any]
        } ?? NSNull(),
      ]
      let line = try jsonLineData(object)
      data.append(line)
      data.append(0x0a)
    }
    return data
  }

  private func diagnosticsObject(
    plan: PreparedPlan,
    warmRun: InferenceRun,
    coldRuns: [String: InferenceRun],
    cancellation: CancellationResult,
    workingRoot: URL
  ) throws -> [String: Any] {
    func processObject(_ record: ProcessRecord) -> [String: Any] {
      [
        "pid": record.pid,
        "exitCode": record.exitCode,
        "terminationReason": record.terminationReason,
        "wallMilliseconds": record.wallMilliseconds,
        "peakResidentBytes": record.resourcePeaks.residentBytes,
        "peakPhysicalFootprintBytes": record.resourcePeaks.physicalFootprintBytes,
        "stdoutByteCount": record.stdout.totalBytes,
        "stdoutCapturedBytes": record.stdout.data.count,
        "stdoutTruncated": record.stdout.truncated,
        "stdoutPreview": String(record.stdout.preview.prefix(4096)),
        "stderrByteCount": record.stderr.totalBytes,
        "stderrCapturedBytes": record.stderr.data.count,
        "stderrTruncated": record.stderr.truncated,
        "stderrPreview": String(record.stderr.preview.prefix(4096)),
        "nativeModelLoadMilliseconds": record.nativeTiming.loadMilliseconds.map { $0 as Any } ?? NSNull(),
        "nativeTotalMilliseconds": record.nativeTiming.totalMilliseconds.map { $0 as Any } ?? NSNull(),
      ]
    }
    return [
      "schemaVersion": 1,
      "bounded": true,
      "retryCount": 0,
      "workingRoot": workingRoot.lastPathComponent,
      "environment": [
        "PATH": environmentPath,
        "LC_ALL": "C",
        "proxyVariablesStripped": true,
      ] as [String: Any],
      "offline": [
        "sandboxExecutable": "/usr/bin/sandbox-exec",
        "profile": sandboxProfile,
        "networkDenied": true,
        "enforced": true,
        "unexpectedNetworkConnectionCount": 0,
      ] as [String: Any],
      "identity": [
        "modelPath": plan.control.candidate.model.path,
        "modelSHA256": plan.modelSHA256,
        "modelBytes": plan.modelBytes,
        "modelFileType": expectedModelFileType,
        "quantization": expectedQuantization,
        "runtimeID": plan.control.candidate.runtime.id,
        "runtimeVersion": plan.control.candidate.runtime.version,
        "sourcePath": plan.control.candidate.runtime.sourcePath,
        "sourceCommit": plan.control.candidate.runtime.sourceCommit,
        "cliPath": plan.control.candidate.runtime.cliPath,
        "cliSHA256": plan.cliSHA256,
        "cliBytes": plan.cliBytes,
        "architecture": plan.hardware.architecture,
        "sourceClean": true,
        "buildFlags": plan.control.candidate.runtime.buildFlags,
      ] as [String: Any],
      "warm": [
        "invocationCount": 1,
        "inputCaseCount": maximumCaseCount,
        "outputOrder": warmRun.expectedCaseIDs,
        "process": processObject(warmRun.process),
      ] as [String: Any],
      "cold": [
        "invocationCount": coldRuns.count,
        "caseIDs": plan.control.execution.coldCaseIDs,
        "freshProcessIDs": coldRuns.values.map { $0.process.pid },
        "processes": coldRuns.keys.sorted().map { caseID in
          ["caseID": caseID, "process": processObject(coldRuns[caseID]!.process)] as [String: Any]
        },
      ] as [String: Any],
      "cancellation": cancellationObject(cancellation),
      "claims": [
        "claimsPartials": false,
        "resultSemantics": "batch-final-only",
        "translation": false,
        "language": "auto",
        "coldTiming": "process-start-through-observed-valid-json-output",
        "warmTiming": "per-file output-completion interval observed in one process",
        "nativeDecodeTimingClaimed": false,
        "cooperativeCancellationClaimed": false,
      ] as [String: Any],
      "publication": [
        "atomicPerFile": true,
        "finalTargets": outputNames,
        "overwriteRefused": true,
        "noRetry": true,
      ] as [String: Any],
      "flags": [
        "automatedCandidatePass": false,
        "releaseAdmitted": false,
        "integration": false,
        "package": false,
        "release": false,
      ] as [String: Any],
    ]
  }
}

private struct AccuracyMetrics {
  let englishWER: Double?
  let mandarinCER: Double?
  let mixedMER: Double?
  let codeSwitchSpanAccuracy: Double?
  let protectedViolationCount: Int
}

private struct HashReceipt {
  let sha256: String
  let bytes: Int64
}

private enum AtomicPublisher {
  static func publish(
    _ dataByName: [String: Data],
    outputRoot: URL,
    workingRoot: URL
  ) throws -> [String] {
    guard Set(dataByName.keys) == Set(outputNames) else {
      throw BenchmarkError.publication("publication set is not the exact four-file set")
    }
    try validateFinalTargets(in: outputRoot)
    var published: [String] = []
    for name in outputNames {
      guard let data = dataByName[name] else {
        throw BenchmarkError.publication("missing publication data for \(name)")
      }
      let temporary = workingRoot.appendingPathComponent(
        ".\(name).\(UUID().uuidString).partial"
      )
      guard !FileManager.default.fileExists(atPath: temporary.path) else {
        throw BenchmarkError.publication("temporary publication target already exists")
      }
      try data.write(to: temporary, options: .atomic)
      guard lstatType(temporary.path) == S_IFREG else {
        throw BenchmarkError.publication("temporary publication file is not regular")
      }
      let finalURL = outputRoot.appendingPathComponent(name)
      guard linkFile(temporary.path, finalURL.path) else {
        throw BenchmarkError.publication(
          "atomic publication refused target without retry: \(name)"
        )
      }
      guard lstatType(finalURL.path) == S_IFREG else {
        throw BenchmarkError.publication("published target is not a regular file")
      }
      _ = unlink(temporary.path)
      published.append(name)
    }
    return published
  }
}

private enum SelfTests {
  static func run() throws {
    var passed = 0
    try testIdentityGate(); passed += 1
    try testQuantizationTruth(); passed += 1
    try testWarmAndColdShape(); passed += 1
    try testTimingLabels(); passed += 1
    try testOutputParsingAndOrder(); passed += 1
    try testBoundedFloodAndDuplicateKeys(); passed += 1
    try testForcedCancellationTruth(); passed += 1
    try testOfflineEnforcement(); passed += 1
    try testPublicationRaceAndNoRetry(); passed += 1
    print("SELF-TEST PASS: \(passed) fake-only Whisper benchmark contract checks")
  }

  private static func testIdentityGate() throws {
    var header = Data(repeating: 0, count: 48)
    header[0] = 0x6c; header[1] = 0x6d; header[2] = 0x67; header[3] = 0x67
    writeUInt32LE(expectedModelFileType, into: &header, offset: 44)
    try validateModelHeader(header, expectedFileType: expectedModelFileType)
    header[44] = 2
    try requireTestFailure { try validateModelHeader(header, expectedFileType: expectedModelFileType) }
  }

  private static func testQuantizationTruth() throws {
    try requireTest(expectedQuantization == "mostly-F16/float16 (ggml ftype=1)")
    try requireTestFailure { try validateQuantization("compressed-other", fileType: 1) }
    try requireTestFailure { try validateQuantization(expectedQuantization, fileType: 2) }
  }

  private static func testWarmAndColdShape() throws {
    let warm = (1...36).map { "case-\($0)" }
    let cold = ["en_us-01", "en_us-02", "cmn_hans_cn-01", "cmn_hans_cn-02", "mixed-01"]
    try validateRunShape(warmCaseIDs: warm, coldCaseIDs: cold)
    try requireTestFailure { try validateRunShape(warmCaseIDs: warm + ["case-1"], coldCaseIDs: cold) }
    try requireTest(warm.count == 36 && cold.count == 5)
  }

  private static func testTimingLabels() throws {
    let warm = timingLabel(isCold: false)
    let cold = timingLabel(isCold: true)
    try requireTest(warm.contains("one-process") && cold.contains("process-start"))
    try requireTestFailure { try validateTimingLabel("native decode duration") }
    try requireTestFailure { try validateTimingLabel("stop-to-final") }
  }

  private static func testOutputParsingAndOrder() throws {
    let expected = ["en_us-01", "en_us-02", "mixed-01"]
    try validateOutputOrder(expected: expected, observed: expected)
    try requireTestFailure {
      try validateOutputOrder(expected: expected, observed: ["en_us-02", "en_us-01", "mixed-01"])
    }
    let json = Data("{\"model\":{\"ftype\":1},\"params\":{\"translate\":false}}".utf8)
    try StrictJSON.validate(json, maximumBytes: 1024)
    let jsonLine = try jsonLineData(["id": "case-1"])
    try requireTest(!jsonLine.contains(0x0a) && !jsonLine.contains(0x0d))
  }

  private static func testBoundedFloodAndDuplicateKeys() throws {
    try requireTestFailure {
      try StrictJSON.validate(Data("{\"a\":1,\"a\":2}".utf8), maximumBytes: 1024)
    }
    try requireTestFailure {
      try StrictJSON.validate(Data(repeating: 0x20, count: 65), maximumBytes: 64)
    }
  }

  private static func testForcedCancellationTruth() throws {
    try requireTest(assessCancellation(markerSeen: true, killSent: true, exitedBySignal: true, noLateOutput: true) == "forced")
    try requireTest(assessCancellation(markerSeen: false, killSent: true, exitedBySignal: true, noLateOutput: true) == "inconclusive")
    try requireTest(assessCancellation(markerSeen: true, killSent: false, exitedBySignal: true, noLateOutput: true) == "inconclusive")
    try requireTest(assessCancellation(markerSeen: true, killSent: true, exitedBySignal: true, noLateOutput: false) == "inconclusive")
  }

  private static func testOfflineEnforcement() throws {
    try requireSandboxEnforcement()
    try requireTest(sandboxProfile.contains("deny network*"))
    try requireTest(environmentPath == "/usr/bin:/bin")
  }

  private static func testPublicationRaceAndNoRetry() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("whisper-small-contract-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let working = root.appendingPathComponent("working", isDirectory: true)
    try FileManager.default.createDirectory(at: working, withIntermediateDirectories: true)
    let target = root.appendingPathComponent(outputNames[0])
    try Data("preexisting".utf8).write(to: target)
    let data = Dictionary(uniqueKeysWithValues: outputNames.map { ($0, Data("x".utf8)) })
    try requireTestFailure { _ = try AtomicPublisher.publish(data, outputRoot: root, workingRoot: working) }
    let preserved = try String(contentsOf: target, encoding: .utf8)
    try requireTest(preserved == "preexisting")
  }

  private static func requireTest(_ condition: @autoclosure () -> Bool) throws {
    guard condition() else { throw BenchmarkError.contract("self-test assertion failed") }
  }

  private static func requireTestFailure(_ body: () throws -> Void) throws {
    do {
      try body()
    } catch {
      return
    }
    throw BenchmarkError.contract("self-test expected a fail-closed error")
  }
}

private enum StrictJSON {
  static func validate(_ data: Data, maximumBytes: Int) throws {
    guard data.count <= maximumBytes else {
      throw BenchmarkError.contract("JSON exceeds bounded size")
    }
    var parser = Parser(bytes: Array(data))
    try parser.parseDocument()
  }

  private struct Parser {
    let bytes: [UInt8]
    var index = 0

    mutating func parseDocument() throws {
      skipWhitespace()
      try parseValue(depth: 0)
      skipWhitespace()
      guard index == bytes.count else { throw BenchmarkError.contract("trailing JSON bytes") }
    }

    mutating func parseValue(depth: Int) throws {
      guard depth <= 64, index < bytes.count else {
        throw BenchmarkError.contract("malformed JSON")
      }
      skipWhitespace()
      guard index < bytes.count else { throw BenchmarkError.contract("malformed JSON") }
      switch bytes[index] {
      case 0x22:
        _ = try parseString()
      case 0x7b:
        try parseObject(depth: depth + 1)
      case 0x5b:
        try parseArray(depth: depth + 1)
      case 0x74:
        try consumeLiteral(Array("true".utf8))
      case 0x66:
        try consumeLiteral(Array("false".utf8))
      case 0x6e:
        try consumeLiteral(Array("null".utf8))
      default:
        try parsePrimitive()
      }
    }

    mutating func parseObject(depth: Int) throws {
      guard consume(0x7b) else { throw BenchmarkError.contract("malformed JSON object") }
      var keys = Set<String>()
      skipWhitespace()
      if consume(0x7d) { return }
      while true {
        skipWhitespace()
        let key = try parseString()
        guard keys.insert(key).inserted else {
          throw BenchmarkError.contract("duplicate JSON object key")
        }
        skipWhitespace()
        guard consume(0x3a) else { throw BenchmarkError.contract("malformed JSON object") }
        try parseValue(depth: depth)
        skipWhitespace()
        if consume(0x7d) { return }
        guard consume(0x2c) else { throw BenchmarkError.contract("malformed JSON object") }
      }
    }

    mutating func parseArray(depth: Int) throws {
      guard consume(0x5b) else { throw BenchmarkError.contract("malformed JSON array") }
      skipWhitespace()
      if consume(0x5d) { return }
      while true {
        try parseValue(depth: depth)
        skipWhitespace()
        if consume(0x5d) { return }
        guard consume(0x2c) else { throw BenchmarkError.contract("malformed JSON array") }
      }
    }

    mutating func parseString() throws -> String {
      guard consume(0x22) else { throw BenchmarkError.contract("malformed JSON string") }
      var decoded = Data()
      while index < bytes.count {
        let byte = bytes[index]
        index += 1
        switch byte {
        case 0x22:
          guard let string = String(data: decoded, encoding: .utf8) else {
            throw BenchmarkError.contract("invalid UTF-8 JSON string")
          }
          return string
        case 0x5c:
          guard index < bytes.count else { throw BenchmarkError.contract("malformed JSON escape") }
          let escape = bytes[index]
          index += 1
          switch escape {
          case 0x22, 0x5c, 0x2f: decoded.append(escape)
          case 0x62: decoded.append(0x08)
          case 0x66: decoded.append(0x0c)
          case 0x6e: decoded.append(0x0a)
          case 0x72: decoded.append(0x0d)
          case 0x74: decoded.append(0x09)
          case 0x75: try appendUnicodeEscape(to: &decoded)
          default: throw BenchmarkError.contract("unknown JSON escape")
          }
        case 0x00...0x1f:
          throw BenchmarkError.contract("control character in JSON string")
        default:
          decoded.append(byte)
        }
      }
      throw BenchmarkError.contract("unterminated JSON string")
    }

    mutating func parsePrimitive() throws {
      let start = index
      while index < bytes.count,
        ![0x20, 0x09, 0x0a, 0x0d, 0x2c, 0x5d, 0x7d].contains(bytes[index])
      {
        index += 1
      }
      guard index > start else { throw BenchmarkError.contract("malformed JSON primitive") }
    }

    mutating func consumeLiteral(_ literal: [UInt8]) throws {
      guard index + literal.count <= bytes.count,
        Array(bytes[index..<(index + literal.count)]) == literal
      else { throw BenchmarkError.contract("malformed JSON literal") }
      index += literal.count
    }

    mutating func appendUnicodeEscape(to data: inout Data) throws {
      let first = try readHexQuad()
      if (0xd800...0xdbff).contains(first) {
        guard consume(0x5c), consume(0x75) else { throw BenchmarkError.contract("invalid surrogate") }
        let second = try readHexQuad()
        guard (0xdc00...0xdfff).contains(second) else { throw BenchmarkError.contract("invalid surrogate") }
        let scalar = 0x1_0000 + ((first - 0xd800) << 10) + (second - 0xdc00)
        try appendUnicodeScalar(scalar, to: &data)
      } else if (0xdc00...0xdfff).contains(first) {
        throw BenchmarkError.contract("unpaired surrogate")
      } else {
        try appendUnicodeScalar(first, to: &data)
      }
    }

    mutating func readHexQuad() throws -> UInt32 {
      guard index + 4 <= bytes.count else { throw BenchmarkError.contract("short Unicode escape") }
      var value: UInt32 = 0
      for _ in 0..<4 {
        guard let digit = hexValue(bytes[index]) else { throw BenchmarkError.contract("invalid Unicode escape") }
        value = (value << 4) | digit
        index += 1
      }
      return value
    }

    func appendUnicodeScalar(_ value: UInt32, to data: inout Data) throws {
      guard let scalar = UnicodeScalar(value) else { throw BenchmarkError.contract("invalid Unicode scalar") }
      data.append(contentsOf: String(scalar).utf8)
    }

    mutating func consume(_ byte: UInt8) -> Bool {
      guard index < bytes.count, bytes[index] == byte else { return false }
      index += 1
      return true
    }

    mutating func skipWhitespace() {
      while index < bytes.count,
        bytes[index] == 0x20 || bytes[index] == 0x09 || bytes[index] == 0x0a || bytes[index] == 0x0d
      { index += 1 }
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

private func parseCLIOutput(_ data: Data, expectedModelPath: String) throws -> ParsedCLIOutput {
  let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
  guard let root = object as? [String: Any],
    let model = root["model"] as? [String: Any],
    let params = root["params"] as? [String: Any],
    let result = root["result"] as? [String: Any],
    let transcription = root["transcription"] as? [[String: Any]],
    let modelFileType = (model["ftype"] as? NSNumber)?.intValue,
    modelFileType == expectedModelFileType,
    (model["type"] as? String) == "small",
    (model["multilingual"] as? Bool) == true,
    (params["model"] as? String) == expectedModelPath,
    (params["language"] as? String) == "auto",
    (params["translate"] as? Bool) == false,
    let detectedLanguage = result["language"] as? String,
    !detectedLanguage.isEmpty
  else {
    throw BenchmarkError.process("CLI JSON identity or final-only parameters are invalid")
  }
  var segments: [[String: Any]] = []
  var rawText = ""
  var previousOffset = -1
  for value in transcription {
    guard let text = value["text"] as? String else {
      throw BenchmarkError.process("CLI JSON transcription segment has no text")
    }
    if let offsets = value["offsets"] as? [String: Any],
      let from = (offsets["from"] as? NSNumber)?.intValue,
      let to = (offsets["to"] as? NSNumber)?.intValue
    {
      guard from >= previousOffset, to >= from else {
        throw BenchmarkError.process("CLI transcription offsets are unordered")
      }
      previousOffset = to
    }
    segments.append(value)
    rawText.append(text)
  }
  guard rawText.unicodeScalars.allSatisfy({ $0 != "\0" && $0 != "\r" }) else {
    throw BenchmarkError.process("CLI transcription contains control characters")
  }
  return ParsedCLIOutput(
    raw: root,
    rawSegments: segments,
    rawHypothesis: rawText,
    hypothesis: rawText.trimmingCharacters(in: .whitespacesAndNewlines),
    detectedLanguage: detectedLanguage,
    modelFileType: modelFileType
  )
}

private func scoreAccuracy(
  _ cases: [PreparedCase],
  _ observations: [String: OutputObservation]
) -> AccuracyMetrics {
  var edits: [String: Int] = [:]
  var units: [String: Int] = [:]
  var matchedSpans = 0
  var totalSpans = 0
  var protectedViolations = 0
  for evaluationCase in cases {
    guard let observation = observations[evaluationCase.id] else { continue }
    let language = evaluationCase.language
    let referenceTokens = scoreTokens(evaluationCase.reference, language: language)
    let hypothesisTokens = scoreTokens(observation.parsed.hypothesis, language: language)
    guard !referenceTokens.isEmpty else { continue }
    let distance = levenshtein(referenceTokens, hypothesisTokens)
    edits[language, default: 0] += distance
    units[language, default: 0] += referenceTokens.count
    for expectation in evaluationCase.protectedExpectations {
      if !protectedExpectationMatches(expectation, hypothesis: observation.parsed.hypothesis) {
        protectedViolations += 1
      }
    }
    for span in evaluationCase.codeSwitchSpans {
      totalSpans += 1
      if codeSwitchSpanMatches(span.reference, hypothesis: observation.parsed.hypothesis) {
        matchedSpans += 1
      }
    }
  }
  func rate(_ language: String) -> Double? {
    guard let editCount = edits[language], let unitCount = units[language], unitCount > 0 else { return nil }
    return Double(editCount) / Double(unitCount)
  }
  return AccuracyMetrics(
    englishWER: rate("english"),
    mandarinCER: rate("mandarin"),
    mixedMER: rate("mixed"),
    codeSwitchSpanAccuracy: totalSpans == 0 ? nil : Double(matchedSpans) / Double(totalSpans),
    protectedViolationCount: protectedViolations
  )
}

private func scoreTokens(_ text: String, language: String) -> [String] {
  switch language {
  case "english": return wordTokens(text.lowercased(with: Locale(identifier: "en_US_POSIX")))
  case "mandarin":
    return text.filter { character in
      !character.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
        && !character.unicodeScalars.contains { CharacterSet.punctuationCharacters.contains($0) }
    }.map(String.init)
  case "mixed": return mixedTokens(text.lowercased(with: Locale(identifier: "en_US_POSIX")))
  default: return []
  }
}

private func wordTokens(_ text: String) -> [String] {
  var result: [String] = []
  var word = ""
  let characters = Array(text)
  var index = 0
  func flush() {
    if !word.isEmpty { result.append(word); word.removeAll(keepingCapacity: true) }
  }
  while index < characters.count {
    let character = characters[index]
    guard isLetterOrDigit(character) else { index += 1; continue }
    word.append(character); index += 1
    while index < characters.count {
      let next = characters[index]
      if isLetterOrDigit(next) {
        word.append(next); index += 1
      } else if isApostrophe(next), index + 1 < characters.count,
        isLetterOrDigit(characters[index + 1])
      {
        word.append(next); index += 1
      } else { break }
    }
    flush()
  }
  flush()
  return result
}

private func mixedTokens(_ text: String) -> [String] {
  var result: [String] = []
  var word = ""
  let characters = Array(text)
  var index = 0
  func flush() {
    if !word.isEmpty { result.append(word); word.removeAll(keepingCapacity: true) }
  }
  while index < characters.count {
    let character = characters[index]
    if isHan(character) { flush(); result.append(String(character)); index += 1; continue }
    guard isLetterOrDigit(character) else { flush(); index += 1; continue }
    word.append(character); index += 1
    while index < characters.count {
      let next = characters[index]
      if isLetterOrDigit(next), !isHan(next) {
        word.append(next); index += 1
      } else if isApostrophe(next), index + 1 < characters.count,
        isLetterOrDigit(characters[index + 1]), !isHan(characters[index + 1])
      {
        word.append(next); index += 1
      } else { break }
    }
    flush()
  }
  flush()
  return result
}

private func levenshtein<T: Equatable>(_ lhs: [T], _ rhs: [T]) -> Int {
  if lhs.isEmpty { return rhs.count }
  if rhs.isEmpty { return lhs.count }
  var previous = Array(0...rhs.count)
  for (leftIndex, left) in lhs.enumerated() {
    var current = Array(repeating: 0, count: rhs.count + 1)
    current[0] = leftIndex + 1
    for (rightIndex, right) in rhs.enumerated() {
      current[rightIndex + 1] = min(
        previous[rightIndex + 1] + 1,
        current[rightIndex] + 1,
        previous[rightIndex] + (left == right ? 0 : 1)
      )
    }
    previous = current
  }
  return previous[rhs.count]
}

private func isLetterOrDigit(_ character: Character) -> Bool {
  character.unicodeScalars.contains {
    CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
  }
}

private func isHan(_ character: Character) -> Bool {
  character.unicodeScalars.contains { $0.properties.isIdeographic || $0.properties.isUnifiedIdeograph }
}

private func isApostrophe(_ character: Character) -> Bool {
  character.unicodeScalars.count == 1
    && [0x27, 0x2019, 0x02bc, 0xff07].contains(character.unicodeScalars.first!.value)
}

private func protectedExpectationMatches(_ expectation: ManifestExpectation, hypothesis: String) -> Bool {
  switch expectation.comparison {
  case "exact": return hypothesis.contains(expectation.text)
  default:
    let normalize: (String) -> String = { value in
      value.lowercased(with: Locale(identifier: "en_US_POSIX"))
        .split(whereSeparator: { $0.isWhitespace })
        .joined(separator: " ")
    }
    return normalize(hypothesis).contains(normalize(expectation.text))
  }
}

private func codeSwitchSpanMatches(_ reference: String, hypothesis: String) -> Bool {
  hypothesis.lowercased(with: Locale(identifier: "en_US_POSIX"))
    .contains(reference.lowercased(with: Locale(identifier: "en_US_POSIX")))
}

private func expectationObject(_ expectation: ManifestExpectation) -> [String: Any] {
  ["kind": expectation.kind, "text": expectation.text, "comparison": expectation.comparison]
}

private func timingObject(_ observation: OutputObservation, isCold: Bool) -> [String: Any] {
  [
    "isCold": isCold,
    "processStartToOutputCompletionMilliseconds": observation.processStartToCompletionMilliseconds,
    "outputCompletionIntervalMilliseconds": observation.completionIntervalMilliseconds,
    "measurementLabel": "process-start-to-observed-valid-json-output-completion",
    "nativeDecodeMilliseconds": NSNull(),
    "stopToFinalMilliseconds": NSNull(),
  ]
}

private func lifecyclePhase(
  outcome: String,
  duration: Double,
  peaks: ResourcePeaks
) -> [String: Any] {
  [
    "outcome": outcome,
    "durationMilliseconds": max(0, duration),
    "peakResidentBytes": peaks.residentBytes,
    "peakPhysicalFootprintBytes": peaks.physicalFootprintBytes,
  ]
}

private func cancellationObject(_ cancellation: CancellationResult) -> [String: Any] {
  [
    "caseID": cancellation.caseID,
    "outcome": cancellation.outcome,
    "markerSeen": cancellation.markerSeen,
    "markerDescription": cancellation.markerDescription,
    "killSent": cancellation.killSent,
    "signal": cancellation.killSent ? "SIGKILL" : NSNull(),
    "processExited": cancellation.processExited,
    "exitCode": cancellation.exitCode,
    "noLateOutput": cancellation.noLateOutput,
    "cooperative": false,
    "claim": cancellation.outcome == "forced"
      ? "forced process termination after positive processing-start diagnostic"
      : "inconclusive marker or termination race; no cancellation claim",
  ]
}

private func fileDecodeRTF(_ cases: [PreparedCase], _ objects: [[String: Any]]) -> Any {
  var totalMilliseconds = 0.0
  var totalAudioMilliseconds = 0.0
  for (evaluationCase, object) in zip(cases, objects) {
    guard let timing = object["timing"] as? [String: Any],
      let milliseconds = timing["fileDecodeMilliseconds"] as? Double else { continue }
    totalMilliseconds += milliseconds
    totalAudioMilliseconds += evaluationCase.audioDurationMilliseconds
  }
  guard totalAudioMilliseconds > 0 else { return NSNull() }
  return totalMilliseconds / totalAudioMilliseconds
}

private func nearestRank(_ values: [Double], percentile: Double) -> Double? {
  guard !values.isEmpty else { return nil }
  let sorted = values.sorted()
  let rank = Int(ceil(percentile * Double(sorted.count)))
  return sorted[min(max(rank - 1, 0), sorted.count - 1)]
}

private func timingLabel(isCold: Bool) -> String {
  isCold
    ? "process-start-to-observed-valid-json-output-completion (fresh process)"
    : "one-process warm output-completion interval"
}

private func validateTimingLabel(_ label: String) throws {
  guard label.contains("process-start-to-observed-valid-json-output-completion")
    || label.contains("one-process warm output-completion interval")
  else {
    throw BenchmarkError.contract("timing label is not an output-completion label")
  }
}

private func validateOutputOrder(expected: [String], observed: [String]) throws {
  guard expected.count == observed.count, expected == observed else {
    throw BenchmarkError.process("output order mismatch")
  }
}

private func validateRunShape(warmCaseIDs: [String], coldCaseIDs: [String]) throws {
  guard warmCaseIDs.count == 36,
    Set(warmCaseIDs).count == warmCaseIDs.count,
    coldCaseIDs.count == 5,
    Set(coldCaseIDs).count == coldCaseIDs.count,
    coldCaseIDs.filter({ $0.hasPrefix("en_us-") }).count == 2,
    coldCaseIDs.filter({ $0.hasPrefix("cmn_hans_cn-") }).count == 2,
    coldCaseIDs.filter({ $0.hasPrefix("mixed-") }).count == 1
  else {
    throw BenchmarkError.contract("warm/cold run shape mismatch")
  }
}

private func validateModelHeader(_ data: Data, expectedFileType: Int) throws {
  guard data.count >= 48,
    Array(data.prefix(4)) == [0x6c, 0x6d, 0x67, 0x67],
    Int(readUInt32LE(data, offset: 44)) == expectedFileType
  else {
    throw BenchmarkError.identity("model header mismatch")
  }
}

private func validateQuantization(_ quantization: String, fileType: Int) throws {
  guard quantization == expectedQuantization, fileType == expectedModelFileType else {
    throw BenchmarkError.identity("quantization truth mismatch")
  }
}

private func assessCancellation(
  markerSeen: Bool,
  killSent: Bool,
  exitedBySignal: Bool,
  noLateOutput: Bool
) -> String {
  markerSeen && killSent && exitedBySignal && noLateOutput ? "forced" : "inconclusive"
}

private func prepareOutputRoot(
  _ rawPath: String,
  repoRoot: URL,
  createIfMissing: Bool
) throws -> URL {
  guard rawPath.hasPrefix("/") else {
    throw BenchmarkError.publication("output root must be absolute")
  }
  let standardized = URL(fileURLWithPath: rawPath).standardizedFileURL
  guard !isInside(standardized, root: repoRoot), standardized.path != repoRoot.path else {
    throw BenchmarkError.publication("output root may not be inside the repository")
  }
  let components = standardized.path.split(separator: "/").map { $0.lowercased() }
  guard !components.contains(where: { [".build", "deriveddata", "products"].contains($0) }),
    !standardized.path.lowercased().hasSuffix(".app")
  else {
    throw BenchmarkError.publication("output root resembles an app/build output")
  }
  if lstatType(standardized.path) == S_IFDIR {
    let resolved = standardized.resolvingSymlinksInPath().standardizedFileURL
    guard resolved.path == standardized.path else {
      throw BenchmarkError.publication("output root may not be a symlink")
    }
    let entries = try FileManager.default.contentsOfDirectory(atPath: standardized.path)
    guard entries.isEmpty else {
      throw BenchmarkError.publication("output root must be empty and have no preexisting targets")
    }
    return standardized
  }
  guard createIfMissing || lstatType(standardized.path) == 0 else {
    throw BenchmarkError.publication("output root is not a directory")
  }
  if createIfMissing {
    let parent = standardized.deletingLastPathComponent()
    _ = try canonicalDirectory(parent.path, label: "output parent")
    try FileManager.default.createDirectory(at: standardized, withIntermediateDirectories: false)
    return try prepareOutputRoot(rawPath, repoRoot: repoRoot, createIfMissing: false)
  }
  let parent = standardized.deletingLastPathComponent()
  _ = try canonicalDirectory(parent.path, label: "output parent")
  try FileManager.default.createDirectory(at: standardized, withIntermediateDirectories: false)
  return try prepareOutputRoot(rawPath, repoRoot: repoRoot, createIfMissing: false)
}

private func validateFinalTargets(in outputRoot: URL) throws {
  for name in outputNames {
    let path = outputRoot.appendingPathComponent(name).path
    guard lstatType(path) == 0 else {
      throw BenchmarkError.publication("preexisting final target refused: \(name)")
    }
  }
}

private func createFreshDirectory(_ url: URL) throws {
  guard lstatType(url.path) == 0 else {
    throw BenchmarkError.publication("refusing a preexisting working directory \(url.path)")
  }
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
  guard url.resolvingSymlinksInPath().standardizedFileURL.path == url.standardizedFileURL.path else {
    throw BenchmarkError.publication("working directory became a symlink")
  }
}

private func resolve(_ path: String, relativeTo root: URL) -> URL {
  if path.hasPrefix("/") { return URL(fileURLWithPath: path).standardizedFileURL }
  return root.appendingPathComponent(path).standardizedFileURL
}

private func canonicalDirectory(_ rawPath: String, label: String) throws -> URL {
  let url = try canonicalExisting(rawPath, label: label)
  guard lstatType(url.path) == S_IFDIR else {
    throw BenchmarkError.identity("\(label) is not a directory")
  }
  return url
}

private func canonicalRegularFile(_ rawPath: String, label: String) throws -> URL {
  let url = try canonicalExisting(rawPath, label: label)
  guard lstatType(url.path) == S_IFREG else {
    throw BenchmarkError.identity("\(label) is not a regular file")
  }
  return url
}

private func canonicalExisting(_ rawPath: String, label: String) throws -> URL {
  guard rawPath.hasPrefix("/") else {
    throw BenchmarkError.identity("\(label) must be an absolute path")
  }
  let url = URL(fileURLWithPath: rawPath).standardizedFileURL
  guard url.path == rawPath else {
    throw BenchmarkError.identity("\(label) is not canonical: \(rawPath)")
  }
  guard lstatType(url.path) != 0 else {
    throw BenchmarkError.identity("\(label) does not exist")
  }
  guard url.resolvingSymlinksInPath().standardizedFileURL.path == url.path else {
    throw BenchmarkError.identity("\(label) may not be a symlink")
  }
  return url
}

private func resolveContainedAudio(
  relativePath: String,
  root: URL,
  expectedBytes: Int64,
  expectedSHA256: String,
  expectedDurationMilliseconds: Int,
  label: String
) throws -> URL {
  let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
  guard !relativePath.isEmpty, !relativePath.hasPrefix("/"),
    !components.contains(where: { $0 == "." || $0 == ".." })
  else {
    throw BenchmarkError.identity("audio path is not safely relative for \(label)")
  }
  let url = try canonicalRegularFile(root.appendingPathComponent(relativePath).path, label: "audio \(label)")
  guard isInside(url, root: root) else {
    throw BenchmarkError.identity("audio path escapes its corpus root for \(label)")
  }
  let receipt = try hashFile(url)
  guard receipt.bytes == expectedBytes, receipt.sha256 == expectedSHA256 else {
    throw BenchmarkError.identity("audio hash or byte count mismatch for \(label)")
  }
  try validateWAV(url, expectedDurationMilliseconds: expectedDurationMilliseconds, label: label)
  return url
}

private func validateWAV(_ url: URL, expectedDurationMilliseconds: Int, label: String) throws {
  let data = try Data(contentsOf: url, options: .mappedIfSafe)
  guard data.count >= 12, data[0..<4].elementsEqual(Data("RIFF".utf8)),
    data[8..<12].elementsEqual(Data("WAVE".utf8))
  else { throw BenchmarkError.identity("audio is not RIFF/WAVE for \(label)") }
  var offset = 12
  var format: (code: UInt16, channels: UInt16, rate: UInt32, blockAlign: UInt16, bits: UInt16)?
  var dataBytes: Int?
  while offset + 8 <= data.count {
    let chunkSize = Int(readUInt32LE(data, offset: offset + 4))
    let payloadStart = offset + 8
    guard chunkSize >= 0, payloadStart <= data.count, chunkSize <= data.count - payloadStart else {
      throw BenchmarkError.identity("truncated WAV chunk for \(label)")
    }
    let chunkID = data[offset..<(offset + 4)]
    if chunkID.elementsEqual(Data("fmt ".utf8)), chunkSize >= 16 {
      format = (
        readUInt16LE(data, offset: payloadStart),
        readUInt16LE(data, offset: payloadStart + 2),
        readUInt32LE(data, offset: payloadStart + 4),
        readUInt16LE(data, offset: payloadStart + 12),
        readUInt16LE(data, offset: payloadStart + 14)
      )
    } else if chunkID.elementsEqual(Data("data".utf8)), dataBytes == nil {
      dataBytes = chunkSize
    }
    offset = payloadStart + chunkSize + (chunkSize % 2)
  }
  guard let format, let dataBytes,
    format.code == 3, format.channels == 1, format.rate == 16_000,
    format.blockAlign == 4, format.bits == 32,
    dataBytes % 4 == 0,
    dataBytes / 4 == expectedDurationMilliseconds * 16
  else { throw BenchmarkError.identity("audio is not the exact 16 kHz mono Float32 WAV for \(label)") }
}

private func validateArm64MachO(_ url: URL) throws {
  let data = try readPrefix(url, count: 8)
  guard data.count == 8 else { throw BenchmarkError.identity("CLI Mach-O header is truncated") }
  let magic = readUInt32LE(data, offset: 0)
  let cpu = readUInt32LE(data, offset: 4)
  guard magic == 0xfeedfacf, cpu == 0x0100000c else {
    throw BenchmarkError.identity("CLI is not a thin arm64 Mach-O")
  }
}

private func hashFile(_ url: URL) throws -> HashReceipt {
  let handle = try FileHandle(forReadingFrom: url)
  var hasher = SHA256()
  var count: Int64 = 0
  while true {
    let data = try handle.read(upToCount: 1_048_576)
    guard let data, !data.isEmpty else { break }
    hasher.update(data: data)
    count += Int64(data.count)
  }
  try handle.close()
  return HashReceipt(
    sha256: hasher.finalize().map { String(format: "%02x", $0) }.joined(),
    bytes: count
  )
}

private func readPrefix(_ url: URL, count: Int) throws -> Data {
  let handle = try FileHandle(forReadingFrom: url)
  let data = try handle.read(upToCount: count) ?? Data()
  try handle.close()
  return data
}

private func validHash(_ value: String) -> Bool {
  value.count == 64 && value.unicodeScalars.allSatisfy {
    ("0"..."9").contains($0) || ("a"..."f").contains($0)
  }
}

private func lstatType(_ path: String) -> UInt16 {
  var info = Darwin.stat()
  guard lstat(path, &info) == 0 else { return 0 }
  return info.st_mode & S_IFMT
}

private func isInside(_ child: URL, root: URL) -> Bool {
  let rootPath = root.standardizedFileURL.path
  let childPath = child.standardizedFileURL.path
  return childPath == rootPath || childPath.hasPrefix(rootPath + "/")
}

private func cmakeValue(_ cache: String, key: String) -> String? {
  for line in cache.split(whereSeparator: \.isNewline) {
    let prefix = "\(key):"
    guard line.hasPrefix(prefix), let equals = line.firstIndex(of: "=") else { continue }
    return String(line[line.index(after: equals)...])
  }
  return nil
}

private struct LocalCommandOutput {
  let exitCode: Int32
  let stdout: String
  let stderr: String
}

private func runLocalCommand(
  executable: String,
  arguments: [String],
  currentDirectory: URL? = nil,
  environment: [String: String]? = nil
) throws -> LocalCommandOutput {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: executable)
  process.arguments = arguments
  process.currentDirectoryURL = currentDirectory
  process.environment = environment
  let stdoutPipe = Pipe()
  let stderrPipe = Pipe()
  process.standardOutput = stdoutPipe
  process.standardError = stderrPipe
  try process.run()
  process.waitUntilExit()
  return LocalCommandOutput(
    exitCode: process.terminationStatus,
    stdout: String(decoding: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
    stderr: String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
  )
}

private func requireSandboxEnforcement() throws {
  guard access("/usr/bin/sandbox-exec", X_OK) == 0 else {
    throw BenchmarkError.identity("sandbox-exec offline enforcement is unavailable")
  }
  let result = try runLocalCommand(
    executable: "/usr/bin/sandbox-exec",
    arguments: ["-p", sandboxProfile, "/usr/bin/true"],
    environment: ["PATH": environmentPath, "LC_ALL": "C"]
  )
  guard result.exitCode == 0 else {
    throw BenchmarkError.identity("sandbox-exec offline enforcement could not be applied")
  }
}

private func parseNativeTiming(_ stderr: String) -> NativeTiming {
  func value(for label: String) -> Double? {
    for line in stderr.split(whereSeparator: \.isNewline) where line.contains("\(label) =") {
      guard let equals = line.firstIndex(of: "=") else { continue }
      let tail = line[line.index(after: equals)...]
      if let token = tail.split(whereSeparator: { $0 == " " || $0 == "\t" }).first,
        let value = Double(token), value.isFinite, value >= 0
      { return value }
    }
    return nil
  }
  return NativeTiming(loadMilliseconds: value(for: "load time"), totalMilliseconds: value(for: "total time"))
}

private func elapsedMilliseconds(from start: UInt64, to end: UInt64) -> Double {
  guard end >= start else { return 0 }
  return Double(end - start) / 1_000_000.0
}

private func sysctlString(_ name: String) -> String? {
  var size = 0
  guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
  var bytes = [UInt8](repeating: 0, count: size)
  guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return nil }
  return String(cString: bytes)
}

private func sysctlInt64(_ name: String) -> Int64? {
  var value: Int64 = 0
  var size = MemoryLayout<Int64>.size
  guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
  return value
}

private func machineArchitecture() -> String {
  var info = utsname()
  uname(&info)
  return withUnsafeBytes(of: &info.machine) { rawBuffer in
    String(decoding: rawBuffer, as: UTF8.self).trimmingCharacters(in: .controlCharacters)
  }
}

private func readUInt16LE(_ data: Data, offset: Int) -> UInt16 {
  UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
}

private func readUInt32LE(_ data: Data, offset: Int) -> UInt32 {
  UInt32(data[offset])
    | (UInt32(data[offset + 1]) << 8)
    | (UInt32(data[offset + 2]) << 16)
    | (UInt32(data[offset + 3]) << 24)
}

private func writeUInt32LE(_ value: Int, into data: inout Data, offset: Int) {
  let value = UInt32(value)
  data[offset] = UInt8(value & 0xff)
  data[offset + 1] = UInt8((value >> 8) & 0xff)
  data[offset + 2] = UInt8((value >> 16) & 0xff)
  data[offset + 3] = UInt8((value >> 24) & 0xff)
}

private func jsonData(_ object: Any) throws -> Data {
  guard JSONSerialization.isValidJSONObject(object) else {
    throw BenchmarkError.publication("invalid JSON publication object")
  }
  let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
  try StrictJSON.validate(data, maximumBytes: max(data.count, 1))
  return data
}

private func jsonLineData(_ object: Any) throws -> Data {
  guard JSONSerialization.isValidJSONObject(object) else {
    throw BenchmarkError.publication("invalid JSON line publication object")
  }
  let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
  try StrictJSON.validate(data, maximumBytes: max(data.count, 1))
  guard !data.contains(0x0a), !data.contains(0x0d) else {
    throw BenchmarkError.publication("JSONL record unexpectedly contains a newline")
  }
  return data
}

private func linkFile(_ source: String, _ destination: String) -> Bool {
  source.withCString { sourcePointer in
    destination.withCString { destinationPointer in
      Darwin.link(sourcePointer, destinationPointer) == 0
    }
  }
}

@discardableResult
private func unlink(_ path: String) -> Int32 {
  path.withCString { Darwin.unlink($0) }
}
