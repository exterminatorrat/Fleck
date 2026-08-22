import Darwin
import Foundation

private struct ContractFailure: Error, CustomStringConvertible {
  let message: String

  var description: String { message }
}

private struct TestArguments {
  let repoRoot: URL
  let preparedRoot: URL?
  let helper: URL?
  let staticOnly: Bool

  init(_ arguments: [String]) throws {
    var repoRoot: URL?
    var preparedRoot: URL?
    var helper: URL?
    var staticOnly = false
    var index = 1

    while index < arguments.count {
      switch arguments[index] {
      case "--repo-root":
        guard index + 1 < arguments.count, repoRoot == nil else {
          throw ContractFailure(message: "invalid --repo-root arguments")
        }
        repoRoot = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        index += 2
      case "--prepared-root":
        guard index + 1 < arguments.count, preparedRoot == nil else {
          throw ContractFailure(message: "invalid --prepared-root arguments")
        }
        preparedRoot = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        index += 2
      case "--helper":
        guard index + 1 < arguments.count, helper == nil else {
          throw ContractFailure(message: "invalid --helper arguments")
        }
        helper = URL(fileURLWithPath: arguments[index + 1])
        index += 2
      case "--static-only":
        staticOnly = true
        index += 1
      default:
        throw ContractFailure(message: "unknown test argument: \(arguments[index])")
      }
    }

    guard let repoRoot else {
      throw ContractFailure(message: "--repo-root is required")
    }
    self.repoRoot = repoRoot
    self.preparedRoot = preparedRoot
    self.helper = helper
    self.staticOnly = staticOnly
  }
}

private struct ProcessResult {
  let status: Int32
  let stdout: Data
  let stderr: Data
}

@main
struct NativeEvaluationContractTests {
  static func main() {
    do {
      let arguments = try TestArguments(CommandLine.arguments)
      try run(arguments)
      print("native-evaluation-contract-tests:pass")
    } catch {
      FileHandle.standardError.write(Data("native-evaluation-contract-tests:fail \(error)\n".utf8))
      Darwin.exit(1)
    }
  }

  private static func run(_ arguments: TestArguments) throws {
    try runStaticContractChecks(repoRoot: arguments.repoRoot)
    guard !arguments.staticOnly else { return }
    guard let preparedRoot = arguments.preparedRoot, let helper = arguments.helper else {
      throw ContractFailure(message: "dynamic tests require --prepared-root and --helper")
    }
    try runNativeProtocolChecks(repoRoot: arguments.repoRoot, preparedRoot: preparedRoot, helper: helper)
    try runDuplicateKeyChecks(preparedRoot: preparedRoot, helper: helper)
    try runInventoryFailureChecks(preparedRoot: preparedRoot, helper: helper)
    try runTamperedRuntimeCheck(preparedRoot: preparedRoot, helper: helper)
    try runBuildPathChecks(repoRoot: arguments.repoRoot, preparedRoot: preparedRoot)
    try runForcedTerminationCheck(preparedRoot: preparedRoot, helper: helper)
  }

  private static func runStaticContractChecks(repoRoot: URL) throws {
    let nativeDirectory = repoRoot
      .appendingPathComponent("Tools/LocalDictationCandidateAdapters/Spikes/QwenASR/NativeEvaluation", isDirectory: true)
    let testsDirectory = repoRoot
      .appendingPathComponent("Tools/LocalDictationCandidateAdapters/Spikes/QwenASR/Tests", isDirectory: true)
    let paths = [
      nativeDirectory.appendingPathComponent("main.swift"),
      nativeDirectory.appendingPathComponent("QwenSherpaRecognizer.swift"),
      nativeDirectory.appendingPathComponent("SherpaOnnx-Bridging-Header.h"),
      nativeDirectory.appendingPathComponent("build.sh"),
      testsDirectory.appendingPathComponent("NativeEvaluationContractTests.swift"),
      testsDirectory.appendingPathComponent("run-native-evaluation-contract-tests.sh"),
    ]

    for path in paths {
      guard FileManager.default.fileExists(atPath: path.path) else {
        throw ContractFailure(message: "missing-owned-file:\(path.lastPathComponent)")
      }
    }

    let main = try read(nativeDirectory.appendingPathComponent("main.swift"))
    let recognizer = try read(nativeDirectory.appendingPathComponent("QwenSherpaRecognizer.swift"))
    let bridge = try read(nativeDirectory.appendingPathComponent("SherpaOnnx-Bridging-Header.h"))
    let build = try read(nativeDirectory.appendingPathComponent("build.sh"))
    let runner = try read(testsDirectory.appendingPathComponent("run-native-evaluation-contract-tests.sh"))

    for required in [
      "installed-artifact-inventory.json",
      "releaseAdmitted",
      "batch-final-only",
      "supportsCancellation",
      "context-unsupported-by-sherpa-qwen3-offline-api",
      "measurement",
      "elapsedMs",
      "native-decode-blocked",
      "unsupported-argument",
      "duplicate-json-key",
    ] {
      try require(main.contains(required) || recognizer.contains(required), "missing-contract-token:\(required)")
    }
    for required in [
      "SHA256",
      "destinationOfSymbolicLink",
      "installedSymlinks",
      "resample",
      "conv_frontend",
      "SherpaOnnxDecodeOfflineStream",
      "SherpaOnnxDestroyOfflineRecognizer",
      "FleckSherpaOpenVerified",
      "FleckSherpaOfflineResultText",
    ] {
      try require(recognizer.contains(required) || bridge.contains(required), "missing-native-safety-token:\(required)")
    }
    for required in [
      "arm64-apple-macosx13.0",
      "--prepared-root",
      "--output-root",
      "-import-objc-header",
      "-F",
      "macos-arm64_x86_64",
    ] {
      try require(build.contains(required), "missing-build-contract-token:\(required)")
    }

    try require(bridge.contains("#import <SherpaOnnxC/sherpa-onnx/c-api/c-api.h>"), "bridging-header-drift")
    try require(bridge.contains("FleckSherpaOpenVerified") && bridge.contains("dlsym") && bridge.contains("memcpy"), "verified-symbol-table-missing")
    for directCall in [
      "SherpaOnnxCreateOfflineRecognizer(",
      "SherpaOnnxCreateOfflineStream(",
      "SherpaOnnxAcceptWaveformOffline(",
      "SherpaOnnxDecodeOfflineStream(",
      "SherpaOnnxGetOfflineStreamResult(",
      "SherpaOnnxDestroyOfflineRecognizer(",
      "SherpaOnnxDestroyOfflineStream(",
      "SherpaOnnxDestroyOfflineRecognizerResult(",
    ] {
      try require(!recognizer.contains(directCall), "direct-sherpa-call-present-\(directCall)")
    }
    try require(!build.contains("-framework SherpaOnnxC") && !build.contains("-rpath"), "pre-main-sherpa-link-present")
    try require(!main.contains(".partial") && !main.contains("event: \"partial\""), "partial-event-emission-present")
    try require(!build.contains("Package.swift"), "package-build-wiring-present")
    let forbiddenNetworkTools = ["cu" + "rl", "w" + "get"]
    try require(forbiddenNetworkTools.allSatisfy { !build.lowercased().contains($0) }, "network-fetch-present")
    try require(!build.lowercased().contains("cp ") && !build.lowercased().contains("ditto"), "runtime-copy-present")
    try require(runner.contains("mktemp") && runner.contains("diff --check"), "runner-does-not-use-external-output-discipline")
  }

  private static func runNativeProtocolChecks(repoRoot: URL, preparedRoot: URL, helper: URL) throws {
    let fixtureRoot = preparedRoot
      .appendingPathComponent("model/sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25/test_wavs", isDirectory: true)
    let silenceURL = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("fleck-qwen-native-silence-\(UUID().uuidString).wav")
    try writeSilence(to: silenceURL)
    defer { try? FileManager.default.removeItem(at: silenceURL) }

    let english = fixtureRoot.appendingPathComponent("rap1.wav")
    let mandarin = fixtureRoot.appendingPathComponent("noise2.wav")
    let mixed = fixtureRoot.appendingPathComponent("codeswitch.wav")
    let requests: [[String: Any]] = [
      request(id: "load-1", operation: "load"),
      request(id: "english", operation: "transcribe", audio: english.path, locale: "en-US"),
      request(id: "mandarin", operation: "transcribe", audio: mandarin.path, locale: "zh-CN"),
      request(id: "mixed", operation: "transcribe", audio: mixed.path, locale: "auto"),
      request(id: "silence", operation: "transcribe", audio: silenceURL.path, locale: "auto"),
      request(id: "invalid-context", operation: "transcribe", audio: english.path, locale: "en-US", context: ["must-not-be-applied"]),
      request(id: "cancel-1", operation: "cancel", target: "english"),
      request(id: "unload-1", operation: "unload"),
      request(id: "load-2", operation: "load"),
      request(id: "repeat", operation: "transcribe", audio: english.path, locale: "en-US"),
      request(id: "unload-2", operation: "unload"),
      request(id: "shutdown-1", operation: "shutdown"),
    ]
    let started = DispatchTime.now().uptimeNanoseconds
    let result = try runProcess(executable: helper, arguments: ["--prepared-root", preparedRoot.path], input: encodeLines(requests), timeout: 180)
    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
    try require(result.status == 0, "native-helper-exit-\(result.status):\(string(result.stderr))")
    try require(!string(result.stderr).contains(preparedRoot.path), "external-root-leaked-in-stderr")

    let events = try decodeEvents(result.stdout)
    let expected: [(String, String)] = [
      ("ready", "load-1"),
      ("final", "english"),
      ("final", "mandarin"),
      ("final", "mixed"),
      ("final", "silence"),
      ("failure", "invalid-context"),
      ("failure", "cancel-1"),
      ("unloaded", "unload-1"),
      ("ready", "load-2"),
      ("final", "repeat"),
      ("unloaded", "unload-2"),
      ("unloaded", "shutdown-1"),
    ]
    try require(events.count == expected.count, "unexpected-event-count-\(events.count)")
    for (index, expectedEvent) in expected.enumerated() where index < events.count {
      let event = events[index]
      try require(event["event"] as? String == expectedEvent.0, "event-\(index)-kind")
      try require(event["requestID"] as? String == expectedEvent.1, "event-\(index)-request-id")
      try require((event["event"] as? String) != "partial", "partial-event-observed")
    }

    let finals = events.filter { $0["event"] as? String == "final" }
    try require(finals.count == 5, "final-count-\(finals.count)")
    for event in finals {
      guard let transcript = event["transcript"] as? String else {
        throw ContractFailure(message: "final-transcript-missing")
      }
      try require(transcript.utf8.count <= 65_536, "transcript-bound-exceeded")
      let record: [String: Any] = [
        "case": event["requestID"] as? String ?? "unknown",
        "transcript": transcript,
      ]
      print(String(data: try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]), encoding: .utf8) ?? "{}")
    }
    print("native-run elapsedMs=\(String(format: "%.1f", elapsed))")
    let measurements = string(result.stderr).split(separator: "\n").filter { $0.contains("measurement requestID=") }
    try require(measurements.count >= 5, "native-measurements-missing-\(measurements.count)")
    for measurement in measurements {
      print("native-\(measurement)")
    }
  }

  private static func runDuplicateKeyChecks(preparedRoot: URL, helper: URL) throws {
    let lines = [
      "{\"schemaVersion\":1,\"requestID\":\"safe-id\",\"requestID\":\"attacker-id\",\"operation\":\"load\"}",
      "{\"schemaVersion\":1,\"requestID\":\"operation-id\",\"operation\":\"load\",\"oper\\u0061tion\":\"shutdown\"}",
      "{\"schemaVersion\":1,\"reques\\u0074ID\":\"escaped-id\",\"requestID\":\"attacker-id\",\"operation\":\"load\"}",
      "{\"schemaVersion\":1,\"requestID\":\"schema-id\",\"operation\":\"load\",\"schemaVersion\":1}",
    ]
    let input = Data((lines.joined(separator: "\n") + "\n").utf8)
    let result = try runProcess(
      executable: helper,
      arguments: ["--prepared-root", preparedRoot.path],
      input: input,
      timeout: 10
    )
    try require(result.status == 0, "duplicate-key-exit-\(result.status)")
    let events = try decodeEvents(result.stdout)
    try require(events.count == lines.count, "duplicate-key-event-count-\(events.count)")
    for event in events {
      try require(event["event"] as? String == "failure", "duplicate-key-not-failure")
      try require(event["requestID"] as? String == "protocol-error", "duplicate-key-request-id-leaked")
      try require(event["code"] as? String == "duplicate-json-key", "duplicate-key-code")
    }
    let output = string(result.stdout)
    for attackerID in ["safe-id", "attacker-id", "operation-id", "escaped-id", "schema-id"] {
      try require(!output.contains(attackerID), "duplicate-key-id-leaked-\(attackerID)")
    }
  }

  private static func runInventoryFailureChecks(preparedRoot: URL, helper: URL) throws {
    let temporaryRoot = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("fleck-qwen-invalid-root-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }

    let inventoryURL = preparedRoot.appendingPathComponent("installed-artifact-inventory.json")
    let copiedInventory = temporaryRoot.appendingPathComponent("installed-artifact-inventory.json")
    try FileManager.default.copyItem(at: inventoryURL, to: copiedInventory)
    let runtimeDirectory = temporaryRoot.appendingPathComponent("runtime", isDirectory: true)
    try FileManager.default.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)
    try Data("extra\n".utf8).write(to: runtimeDirectory.appendingPathComponent("extra.txt"), options: .atomic)

    let result = try runProcess(
      executable: helper,
      arguments: ["--prepared-root", temporaryRoot.path],
      input: encodeLines([request(id: "bad-load", operation: "load"), request(id: "bad-shutdown", operation: "shutdown")]),
      timeout: 10
    )
    try require(result.status == 0, "invalid-root-exit-\(result.status)")
    let events = try decodeEvents(result.stdout)
    try require(events.first?["event"] as? String == "failure", "invalid-root-not-rejected")
    try require(events.first?["code"] as? String == "artifact-inventory-mismatch", "invalid-root-error-code")
    try require(!string(result.stderr).contains(temporaryRoot.path), "invalid-root-leaked-in-stderr")

    var data = try Data(contentsOf: inventoryURL)
    data[0] ^= 1
    let changedRoot = temporaryRoot.appendingPathComponent("changed", isDirectory: true)
    try FileManager.default.createDirectory(at: changedRoot, withIntermediateDirectories: true)
    try data.write(to: changedRoot.appendingPathComponent("installed-artifact-inventory.json"), options: .atomic)
    let changedResult = try runProcess(
      executable: helper,
      arguments: ["--prepared-root", changedRoot.path],
      input: encodeLines([request(id: "changed-load", operation: "load")]),
      timeout: 10
    )
    try require(changedResult.status == 0, "changed-inventory-exit-\(changedResult.status)")
    let changedEvents = try decodeEvents(changedResult.stdout)
    try require(changedEvents.first?["code"] as? String == "inventory-identity-mismatch", "changed-inventory-not-rejected")

    let symlinkRoot = temporaryRoot.appendingPathComponent("root-link")
    try FileManager.default.createSymbolicLink(atPath: symlinkRoot.path, withDestinationPath: temporaryRoot.path)
    let symlinkResult = try runProcess(
      executable: helper,
      arguments: ["--prepared-root", symlinkRoot.path],
      input: encodeLines([request(id: "symlink-load", operation: "load")]),
      timeout: 10
    )
    try require(symlinkResult.status == 0, "symlink-root-exit-\(symlinkResult.status)")
    let symlinkEvents = try decodeEvents(symlinkResult.stdout)
    try require(symlinkEvents.first?["code"] as? String == "invalid-prepared-root", "symlink-root-not-rejected")

    let substituted = try runProcess(
      executable: helper,
      arguments: ["--runtime-root", preparedRoot.appendingPathComponent("runtime").path],
      input: Data(),
      timeout: 10
    )
    try require(substituted.status != 0, "runtime-substitution-accepted")
    try require(string(substituted.stderr).contains("unsupported-argument"), "runtime-substitution-error-code")
    try require(!string(substituted.stderr).contains(preparedRoot.path), "runtime-substitution-leaked-root")
  }

  private static func runTamperedRuntimeCheck(preparedRoot: URL, helper: URL) throws {
    let temporaryRoot = try makeTemporaryDirectory(prefix: "fleck-qwen-tampered-runtime")
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }
    try clonePreparedRoot(preparedRoot, to: temporaryRoot)

    let runtimeBinary = temporaryRoot
      .appendingPathComponent("runtime/sherpa-onnx.xcframework/macos-arm64_x86_64/SherpaOnnxC.framework/Versions/A/SherpaOnnxC")
    var data = try Data(contentsOf: runtimeBinary)
    guard !data.isEmpty else { throw ContractFailure(message: "tampered-runtime-empty") }
    data[0] ^= 1
    try data.write(to: runtimeBinary, options: .atomic)

    let result = try runProcess(
      executable: helper,
      arguments: ["--prepared-root", temporaryRoot.path],
      input: encodeLines([request(id: "tampered-load", operation: "load")]),
      timeout: 10,
      environment: ["FLECK_QWEN_NATIVE_OPEN_PROBE": "1"]
    )
    try require(result.status == 0, "tampered-runtime-exit-\(result.status)")
    let events = try decodeEvents(result.stdout)
    try require(events.first?["event"] as? String == "failure", "tampered-runtime-not-failure")
    try require(events.first?["code"] as? String == "artifact-inventory-mismatch", "tampered-runtime-error-code")
    try require(!string(result.stdout).contains("ready"), "tampered-runtime-ready-emitted")
    try require(!string(result.stderr).contains("native-dlopen-attempted"), "tampered-runtime-dlopen-attempted")
    print("tampered-runtime:rejected-before-dlopen")
  }

  private static func runBuildPathChecks(repoRoot: URL, preparedRoot: URL) throws {
    let buildScript = repoRoot
      .appendingPathComponent("Tools/LocalDictationCandidateAdapters/Spikes/QwenASR/NativeEvaluation/build.sh")
    let temporaryRoot = try makeTemporaryDirectory(prefix: "fleck-qwen-build-paths")
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }

    let repoSubdirectory = repoRoot.appendingPathComponent("Tools", isDirectory: true)
    let repoAlias = temporaryRoot.appendingPathComponent("repo-alias")
    try FileManager.default.createSymbolicLink(at: repoAlias, withDestinationURL: repoRoot)

    let outputTarget = temporaryRoot.appendingPathComponent("output-target", isDirectory: true)
    try FileManager.default.createDirectory(at: outputTarget, withIntermediateDirectories: true)
    let outputAncestorAlias = temporaryRoot.appendingPathComponent("output-ancestor-alias")
    try FileManager.default.createSymbolicLink(at: outputAncestorAlias, withDestinationURL: outputTarget)

    let preparedAlias = temporaryRoot.appendingPathComponent("prepared-alias")
    try FileManager.default.createSymbolicLink(at: preparedAlias, withDestinationURL: preparedRoot)

    let cases: [(String, URL, URL, URL)] = [
      ("repo-root", repoRoot, repoRoot, repoRoot.appendingPathComponent("qwen-sherpa-native-evaluation")),
      ("repo-subdirectory", repoSubdirectory, repoSubdirectory, repoSubdirectory.appendingPathComponent("qwen-sherpa-native-evaluation")),
      ("symlink-to-repo", repoAlias, repoRoot, repoRoot.appendingPathComponent("qwen-sherpa-native-evaluation")),
      ("symlinked-output-ancestor", outputAncestorAlias.appendingPathComponent("child"), outputTarget, outputTarget.appendingPathComponent("child/qwen-sherpa-native-evaluation")),
    ]
    for (label, outputRoot, mutationDirectory, outputFile) in cases {
      try assertBuildPathRejected(
        label: label,
        buildScript: buildScript,
        preparedRoot: preparedRoot,
        outputRoot: outputRoot,
        mutationDirectory: mutationDirectory,
        outputFile: outputFile
      )
    }

    try assertBuildPathRejected(
      label: "symlinked-prepared-root",
      buildScript: buildScript,
      preparedRoot: preparedAlias,
      outputRoot: temporaryRoot.appendingPathComponent("prepared-output"),
      mutationDirectory: temporaryRoot,
      outputFile: temporaryRoot.appendingPathComponent("prepared-output/qwen-sherpa-native-evaluation")
    )
    print("build-path-rejections:pass")
  }

  private static func assertBuildPathRejected(
    label: String,
    buildScript: URL,
    preparedRoot: URL,
    outputRoot: URL,
    mutationDirectory: URL,
    outputFile: URL
  ) throws {
    let before = try directEntries(of: mutationDirectory)
    let outputExisted = FileManager.default.fileExists(atPath: outputFile.path)
    try require(!outputExisted, "build-path-preexisting-output-\(label)")
    let result = try runProcess(
      executable: URL(fileURLWithPath: "/bin/sh"),
      arguments: [buildScript.path, "--prepared-root", preparedRoot.path, "--output-root", outputRoot.path],
      input: Data(),
      timeout: 10
    )
    try require(result.status != 0, "build-path-accepted-\(label)")
    let after = try directEntries(of: mutationDirectory)
    try require(after == before, "build-path-mutated-\(label)")
    try require(!FileManager.default.fileExists(atPath: outputFile.path), "build-path-output-created-\(label)")
  }

  private static func makeTemporaryDirectory(prefix: String) throws -> URL {
    let basePath: String? = NSTemporaryDirectory().withCString { source in
      var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
      guard buffer.withUnsafeMutableBufferPointer({ realpath(source, $0.baseAddress) != nil }) else {
        return nil
      }
      return String(cString: buffer)
    }
    guard let basePath else { throw ContractFailure(message: "temporary-root-canonicalization-failed") }
    let base = URL(fileURLWithPath: basePath, isDirectory: true)
    let directory = base.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    return directory
  }

  private static func clonePreparedRoot(_ source: URL, to destination: URL) throws {
    try FileManager.default.copyItem(
      at: source.appendingPathComponent("installed-artifact-inventory.json"),
      to: destination.appendingPathComponent("installed-artifact-inventory.json")
    )
    try cloneArtifactTree(
      source: source.appendingPathComponent("runtime", isDirectory: true),
      destination: destination.appendingPathComponent("runtime", isDirectory: true)
    )
    try cloneArtifactTree(
      source: source.appendingPathComponent("model", isDirectory: true),
      destination: destination.appendingPathComponent("model", isDirectory: true)
    )
  }

  private static func cloneArtifactTree(source: URL, destination: URL) throws {
    if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: source.path) {
      try FileManager.default.createSymbolicLink(atPath: destination.path, withDestinationPath: target)
      return
    }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
      throw ContractFailure(message: "clone-source-missing-\(source.lastPathComponent)")
    }
    if isDirectory.boolValue {
      try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
      for name in try FileManager.default.contentsOfDirectory(atPath: source.path) {
        try cloneArtifactTree(
          source: source.appendingPathComponent(name),
          destination: destination.appendingPathComponent(name)
        )
      }
    } else {
      try FileManager.default.linkItem(at: source, to: destination)
    }
  }

  private static func directEntries(of directory: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
  }

  private static func runForcedTerminationCheck(preparedRoot: URL, helper: URL) throws {
    let fixture = preparedRoot
      .appendingPathComponent("model/sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25/test_wavs/rap1.wav")
    let input = Pipe()
    let output = Pipe()
    let error = Pipe()
    let process = Process()
    process.executableURL = helper
    process.arguments = ["--prepared-root", preparedRoot.path, "--probe-blocked-decode"]
    process.standardInput = input
    process.standardOutput = output
    process.standardError = error

    let marker = DispatchSemaphore(value: 0)
    let stderrLock = NSLock()
    var stderrData = Data()
    error.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      guard !data.isEmpty else { return }
      stderrLock.lock()
      stderrData.append(data)
      let hasMarker = stderrData.range(of: Data("native-decode-blocked".utf8)) != nil
      stderrLock.unlock()
      if hasMarker { marker.signal() }
    }

    try process.run()
    try input.fileHandleForWriting.write(contentsOf: encodeLines([
      request(id: "probe-load", operation: "load"),
      request(id: "probe-transcribe", operation: "transcribe", audio: fixture.path, locale: "en-US"),
    ]))

    guard marker.wait(timeout: .now() + 180) == .success else {
      process.terminate()
      process.waitUntilExit()
      error.fileHandleForReading.readabilityHandler = nil
      throw ContractFailure(message: "blocked-decode-marker-timeout")
    }

    let terminationStart = Date()
    process.terminate()
    while process.isRunning && Date().timeIntervalSince(terminationStart) < 5 {
      RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    if process.isRunning {
      _ = Darwin.kill(process.processIdentifier, SIGKILL)
      process.waitUntilExit()
      error.fileHandleForReading.readabilityHandler = nil
      throw ContractFailure(message: "forced-termination-deadline-exceeded")
    }
    error.fileHandleForReading.readabilityHandler = nil
    let stdoutData = output.fileHandleForReading.readDataToEndOfFile()
    let finalEvents = try decodeEvents(stdoutData).filter { $0["event"] as? String == "final" }
    try require(finalEvents.isEmpty, "late-final-after-forced-termination")
    stderrLock.lock()
    let capturedStderr = stderrData
    stderrLock.unlock()
    try require(string(capturedStderr).contains("native-decode-blocked"), "blocked-decode-evidence-missing")
    print("cancellation classification=process-level-forced-termination-not-cooperative")
  }

  private static func request(
    id: String,
    operation: String,
    audio: String? = nil,
    locale: String? = nil,
    context: [String] = [],
    target: String? = nil
  ) -> [String: Any] {
    var value: [String: Any] = [
      "schemaVersion": 1,
      "requestID": id,
      "operation": operation,
      "contextPhrases": context,
      "protectedForms": [],
    ]
    if let audio { value["audioPath"] = audio }
    if let locale {
      value["sampleRate"] = 16_000
      value["localeIdentifier"] = locale
    }
    if let target { value["targetRequestID"] = target }
    return value
  }

  private static func encodeLines(_ requests: [[String: Any]]) throws -> Data {
    var data = Data()
    for request in requests {
      data.append(try JSONSerialization.data(withJSONObject: request, options: [.sortedKeys]))
      data.append(0x0A)
    }
    return data
  }

  private static func decodeEvents(_ data: Data) throws -> [[String: Any]] {
    let text = string(data)
    var events: [[String: Any]] = []
    for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
      guard let lineData = line.data(using: .utf8),
        let object = try JSONSerialization.jsonObject(with: lineData) as? [String: Any]
      else {
        throw ContractFailure(message: "invalid-event-json")
      }
      try require((object["schemaVersion"] as? NSNumber)?.intValue == 1, "event-schema-version")
      events.append(object)
    }
    return events
  }

  private static func runProcess(
    executable: URL,
    arguments: [String],
    input: Data,
    timeout: TimeInterval,
    environment: [String: String] = [:]
  ) throws -> ProcessResult {
    let process = Process()
    let inputPipe = Pipe()
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.executableURL = executable
    process.arguments = arguments
    process.standardInput = inputPipe
    process.standardOutput = outputPipe
    process.standardError = errorPipe
    if !environment.isEmpty {
      var mergedEnvironment = ProcessInfo.processInfo.environment
      for (key, value) in environment {
        mergedEnvironment[key] = value
      }
      process.environment = mergedEnvironment
    }
    try process.run()
    if !input.isEmpty {
      try inputPipe.fileHandleForWriting.write(contentsOf: input)
    }
    inputPipe.fileHandleForWriting.closeFile()
    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning {
      guard Date() < deadline else {
        process.terminate()
        process.waitUntilExit()
        throw ContractFailure(message: "process-timeout:\(executable.lastPathComponent)")
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    return ProcessResult(
      status: process.terminationStatus,
      stdout: outputPipe.fileHandleForReading.readDataToEndOfFile(),
      stderr: errorPipe.fileHandleForReading.readDataToEndOfFile()
    )
  }

  private static func writeSilence(to url: URL) throws {
    let sampleCount = 16_000 * 2
    var data = Data("RIFF".utf8)
    appendUInt32LE(&data, UInt32(36 + sampleCount * 2))
    data.append(contentsOf: Data("WAVEfmt ".utf8))
    appendUInt32LE(&data, 16)
    appendUInt16LE(&data, 1)
    appendUInt16LE(&data, 1)
    appendUInt32LE(&data, 16_000)
    appendUInt32LE(&data, 32_000)
    appendUInt16LE(&data, 2)
    appendUInt16LE(&data, 16)
    data.append(contentsOf: Data("data".utf8))
    appendUInt32LE(&data, UInt32(sampleCount * 2))
    data.append(contentsOf: Data(repeating: 0, count: sampleCount * 2))
    try data.write(to: url, options: .atomic)
  }

  private static func appendUInt16LE(_ data: inout Data, _ value: UInt16) {
    data.append(UInt8(value & 0xff))
    data.append(UInt8(value >> 8))
  }

  private static func appendUInt32LE(_ data: inout Data, _ value: UInt32) {
    data.append(UInt8(value & 0xff))
    data.append(UInt8((value >> 8) & 0xff))
    data.append(UInt8((value >> 16) & 0xff))
    data.append(UInt8(value >> 24))
  }

  private static func read(_ url: URL) throws -> String {
    guard let value = String(data: try Data(contentsOf: url), encoding: .utf8) else {
      throw ContractFailure(message: "non-utf8-source:\(url.lastPathComponent)")
    }
    return value
  }

  private static func string(_ data: Data) -> String {
    String(data: data, encoding: .utf8) ?? "<non-utf8>"
  }

  private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw ContractFailure(message: message) }
  }
}
