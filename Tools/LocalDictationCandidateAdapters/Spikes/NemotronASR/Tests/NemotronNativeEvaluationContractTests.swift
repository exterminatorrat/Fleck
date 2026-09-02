import Darwin
import Foundation

private struct ContractFailure: Error, CustomStringConvertible {
  let message: String

  var description: String { message }
}

private struct TestArguments {
  let repoRoot: URL
  let sourcePath: URL?
  let modelPath: URL?
  let runtimePath: URL?
  let englishPath: URL?
  let mandarinPath: URL?
  let mixedPath: URL?
  let silencePath: URL?
  let helper: URL?
  let staticOnly: Bool

  init(_ arguments: [String]) throws {
    var values: [String: URL] = [:]
    var repoRoot: URL?
    var helper: URL?
    var staticOnly = false
    var index = 1

    while index < arguments.count {
      switch arguments[index] {
      case "--repo-root":
        guard index + 1 < arguments.count, repoRoot == nil else {
          throw ContractFailure(message: "invalid-repo-root-arguments")
        }
        repoRoot = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        index += 2
      case "--source-path", "--model-path", "--runtime-path", "--english-path",
        "--mandarin-path", "--mixed-path", "--silence-path":
        guard index + 1 < arguments.count, values[arguments[index]] == nil else {
          throw ContractFailure(message: "invalid-path-arguments")
        }
        values[arguments[index]] = URL(fileURLWithPath: arguments[index + 1])
        index += 2
      case "--helper":
        guard index + 1 < arguments.count, helper == nil else {
          throw ContractFailure(message: "invalid-helper-arguments")
        }
        helper = URL(fileURLWithPath: arguments[index + 1])
        index += 2
      case "--static-only":
        guard !staticOnly else { throw ContractFailure(message: "duplicate-static-only") }
        staticOnly = true
        index += 1
      default:
        throw ContractFailure(message: "unsupported-argument:\(arguments[index])")
      }
    }

    guard let repoRoot else { throw ContractFailure(message: "repo-root-required") }
    self.repoRoot = repoRoot
    self.sourcePath = values["--source-path"]
    self.modelPath = values["--model-path"]
    self.runtimePath = values["--runtime-path"]
    self.englishPath = values["--english-path"]
    self.mandarinPath = values["--mandarin-path"]
    self.mixedPath = values["--mixed-path"]
    self.silencePath = values["--silence-path"]
    self.helper = helper
    self.staticOnly = staticOnly
  }
}

private struct ProcessResult {
  let status: Int32
  let stdout: Data
  let stderr: Data
}

private struct BlockedDecodeEvidence {
  let status: Int32
  let stdout: Data
  let stderr: String
  let events: [String]
}

private struct NativeCase {
  let requestID: String
  let audioPath: URL
  let locale: String
}

private enum SharedAdapterProcessEvent {
  case partial(sequence: Int)
  case measurement
  case final
}

/// Mirrors the terminal/order guards in LocalDictationCandidateRunner/AdapterProcess.accept.
private struct SharedAdapterProcessAcceptanceMirror {
  private(set) var terminal = false
  private var lastPartialSequence = -1

  mutating func accept(_ event: SharedAdapterProcessEvent) throws {
    switch event {
    case .partial(let sequence):
      guard !terminal else {
        throw ContractFailure(message: "shared-runner-partial-after-terminal")
      }
      guard sequence > lastPartialSequence else {
        throw ContractFailure(message: "shared-runner-partial-sequence")
      }
      lastPartialSequence = sequence
    case .measurement:
      guard !terminal else {
        throw ContractFailure(message: "measurement-after-final")
      }
    case .final:
      guard !terminal else {
        throw ContractFailure(message: "shared-runner-duplicate-final")
      }
      terminal = true
    }
  }
}

@main
struct NemotronNativeEvaluationContractTests {
  static func main() {
    do {
      let arguments = try TestArguments(CommandLine.arguments)
      try run(arguments)
      print("nemotron-native-evaluation-contract-tests:pass")
    } catch {
      FileHandle.standardError.write(
        Data("nemotron-native-evaluation-contract-tests:fail \(error)\n".utf8)
      )
      Darwin.exit(1)
    }
  }

  private static func run(_ arguments: TestArguments) throws {
    try runStaticContractChecks(repoRoot: arguments.repoRoot)
    try runSharedRunnerAcceptanceBoundaryContract()
    guard !arguments.staticOnly else { return }
    guard let sourcePath = arguments.sourcePath,
      let modelPath = arguments.modelPath,
      let runtimePath = arguments.runtimePath,
      let englishPath = arguments.englishPath,
      let mandarinPath = arguments.mandarinPath,
      let mixedPath = arguments.mixedPath,
      let silencePath = arguments.silencePath,
      let helper = arguments.helper
    else {
      throw ContractFailure(message: "dynamic-tests-require-exact-external-inputs")
    }
    try require(FileManager.default.fileExists(atPath: sourcePath.path), "source-path-missing")
    try require(FileManager.default.fileExists(atPath: modelPath.path), "model-path-missing")
    try require(FileManager.default.fileExists(atPath: runtimePath.path), "runtime-path-missing")
    for path in [englishPath, mandarinPath, mixedPath, silencePath] {
      try require(FileManager.default.fileExists(atPath: path.path), "audio-path-missing:\(path.lastPathComponent)")
    }

    try runFakeStreamingContract(sourcePath: sourcePath)
    try runRuntimeProvenanceContract(runtimePath: runtimePath)
    try runLateReturnEvidenceContract()
    try runNativeProtocolChecks(
      helper: helper,
      modelPath: modelPath,
      runtimePath: runtimePath,
      sourcePath: sourcePath,
      cases: [
        NativeCase(requestID: "english", audioPath: englishPath, locale: "en-US"),
        NativeCase(requestID: "mandarin", audioPath: mandarinPath, locale: "zh-CN"),
        NativeCase(requestID: "mixed", audioPath: mixedPath, locale: "auto"),
        NativeCase(requestID: "silence", audioPath: silencePath, locale: "auto"),
        NativeCase(requestID: "repeat", audioPath: englishPath, locale: "en-US"),
      ]
    )
    try runProtocolFailureChecks(helper: helper, modelPath: modelPath, runtimePath: runtimePath, sourcePath: sourcePath)
    try runIdentityAndPathChecks(
      helper: helper,
      modelPath: modelPath,
      runtimePath: runtimePath,
      sourcePath: sourcePath
    )
    try runConcurrentSubstitutionChecks(
      helper: helper,
      modelPath: modelPath,
      runtimePath: runtimePath,
      sourcePath: sourcePath,
      audioPath: silencePath
    )
    try runBuildPathChecks(repoRoot: arguments.repoRoot, sourcePath: sourcePath)
    try runForcedTerminationCheck(
      helper: helper,
      modelPath: modelPath,
      runtimePath: runtimePath,
      sourcePath: sourcePath,
      audioPath: englishPath
    )
  }

  private static func runStaticContractChecks(repoRoot: URL) throws {
    let native = repoRoot
      .appendingPathComponent("Tools/LocalDictationCandidateAdapters/Spikes/NemotronASR/NativeEvaluation", isDirectory: true)
    let tests = repoRoot
      .appendingPathComponent("Tools/LocalDictationCandidateAdapters/Spikes/NemotronASR/Tests", isDirectory: true)
    let paths = [
      native.appendingPathComponent("NemoSpeechASR-Bridging-Header.h"),
      native.appendingPathComponent("NemotronRecognizer.swift"),
      native.appendingPathComponent("main.swift"),
      native.appendingPathComponent("build.sh"),
      tests.appendingPathComponent("NemotronNativeEvaluationContractTests.swift"),
      tests.appendingPathComponent("run-nemotron-native-evaluation-contract-tests.sh"),
    ]
    for path in paths {
      try require(FileManager.default.fileExists(atPath: path.path), "missing-owned-file:\(path.lastPathComponent)")
    }
    let buildMode = try FileManager.default.attributesOfItem(
      atPath: native.appendingPathComponent("build.sh").path
    )[.posixPermissions] as? NSNumber
    let runnerMode = try FileManager.default.attributesOfItem(
      atPath: tests.appendingPathComponent("run-nemotron-native-evaluation-contract-tests.sh").path
    )[.posixPermissions] as? NSNumber
    try require((buildMode?.intValue ?? 0) & 0o111 != 0, "executable-mode-mismatch:build.sh")
    try require((runnerMode?.intValue ?? 0) & 0o111 != 0, "executable-mode-mismatch:run-nemotron-native-evaluation-contract-tests.sh")

    let bridge = try read(native.appendingPathComponent("NemoSpeechASR-Bridging-Header.h"))
    let recognizer = try read(native.appendingPathComponent("NemotronRecognizer.swift"))
    let main = try read(native.appendingPathComponent("main.swift"))
    let build = try read(native.appendingPathComponent("build.sh"))
    let runner = try read(tests.appendingPathComponent("run-nemotron-native-evaluation-contract-tests.sh"))
    let contractTests = try read(tests.appendingPathComponent("NemotronNativeEvaluationContractTests.swift"))

    for token in [
      "nemo_speech_asr_create", "nemo_speech_asr_destroy",
      "nemo_speech_asr_streaming_recognize", "nemo_speech_asr_stream_push_f32",
      "nemo_speech_asr_stream_finish", "nemo_speech_asr_stream_next",
      "nemo_speech_asr_stream_close", "nemo_speech_asr_result_is_final",
      "nemo_speech_asr_result_transcript", "nemo_speech_asr_result_destroy",
      "dladdr", "dlsym", "realpath", "_dyld_image_count", "RTLD_GLOBAL",
      "FleckNemoOpenRuntimeVerified", "FleckNemoVerifyRuntimeProvenance",
      "st_dev", "st_ino", "FLECK_NEMOTRON_NATIVE_OPEN_PROBE",
    ] {
      try require(bridge.contains(token), "missing-bridge-token:\(token)")
    }
    for token in [
      "CryptoKit", "SHA256", "modelSHA256", "modelSize", "sourceCommit",
      "expectedSubmodules", "expectedRuntimeFiles", "expectedRuntimeSymlinks",
      "totalBytes", "destinationOfSymbolicLink", "sourceIdentityMismatch",
      "requestToFirstPartialMs", "feedCadenceMs", "feedEndToFinalMs",
      "chunkSamples", "chunkNanoseconds", "native-decode-entry", "native-decode-in-flight",
      "native-decode-blocked",
      "descriptor", "fstat", "O_NOFOLLOW", "immutable", "snapshot", "reverify",
      "runtime-provenance",
    ] {
      try require(recognizer.contains(token), "missing-recognizer-token:\(token)")
    }
    for token in [
      "real-time-cadence", "160", "observed-partials-only",
      "supportsCancellation=false", "supportsCooperativeDecodeCancellation=false",
      "cancellation-unsupported", "admission=false", "integration=false",
      "package=false", "release=false", "releaseAdmitted=false", "loadAttempted",
    ] {
      try require(main.contains(token), "missing-main-token:\(token)")
    }
    for token in [
      "a5c435f294eea8f88ce68dd27b8c3bfea7f777cb2fbba04fcd30eaa555f429ae",
      "e995d84e2b6ea7a25b1fc2edf36dc908680687ebf4a0de207d386b54ad78f8b3",
      "5be7bfb104802131e61fe679b3f1401b27270216",
      "71df98266725320a6b6b3a9f32a6da832dc93691",
    ] {
      try require(recognizer.contains(token) || build.contains(token), "missing-pinned-identity:\(token)")
    }
    for token in [
      "arm64-apple-macosx14.0", "--source-path", "--output-root",
      "-import-objc-header", "-Xcc", "-I", "CandidateAdapterModels.swift",
      "JSONLinesCodec.swift", "WaveReader.swift", "source-worktree-dirty",
      "snapshot", "source-anchor", "build-input", "openat", "linkat", "O_EXCL", "fstat",
    ] {
      try require(build.contains(token), "missing-build-token:\(token)")
    }
    try require(!build.contains("Package.swift"), "package-build-wiring-present")
    try require(!build.contains("libnemo_speech") && !build.contains(" -l") && !build.contains("-Xlinker"), "native-link-present")
    try require(!build.contains("mv -f"), "non-exclusive-output-publication-present")
    for forbidden in ["curl", "wget", "download", "python", "npm", "swift package"] {
      try require(!build.lowercased().contains(forbidden), "forbidden-build-token:\(forbidden)")
    }
    try require(!main.contains("event: \"cancelled\""), "cancelled-event-emission-present")
    try require(!main.contains("case .cancelled"), "cancelled-event-branch-present")
    try require(
      runner.contains("diff --check") && runner.contains("mktemp") &&
        runner.contains("concurrent-substitution") && runner.contains("blocked-decode-in-flight"),
      "runner-scope-discipline-missing"
    )
    for token in [
      "BlockedDecodeEvidence", "DispatchGroup", "availableData",
      "supervisor-terminate-requested", "supervisor-kill-requested", "late-return-evidence",
      "SharedAdapterProcessAcceptanceMirror", "measurements-before-final", "measurement-after-final",
    ] {
      try require(contractTests.contains(token), "missing-blocked-evidence-token:\(token)")
    }
  }

  private static func runSharedRunnerAcceptanceBoundaryContract() throws {
    var compatible = SharedAdapterProcessAcceptanceMirror()
    try compatible.accept(.partial(sequence: 0))
    try compatible.accept(.partial(sequence: 1))
    try compatible.accept(.measurement)
    try compatible.accept(.measurement)
    try compatible.accept(.final)
    try require(compatible.terminal, "shared-runner-compatible-sequence-not-terminal")

    var incompatible = SharedAdapterProcessAcceptanceMirror()
    try incompatible.accept(.final)
    do {
      try incompatible.accept(.measurement)
      throw ContractFailure(message: "post-final-measurement-accepted")
    } catch let failure as ContractFailure {
      try require(failure.message == "measurement-after-final", "post-final-measurement-wrong-rejection:\(failure.message)")
    }
    print("shared-runner-boundary measurements-before-final=pass post-final-measurement=rejected")
  }

  private static func runNativeProtocolChecks(
    helper: URL,
    modelPath: URL,
    runtimePath: URL,
    sourcePath: URL,
    cases: [NativeCase]
  ) throws {
    var requests: [[String: Any]] = [request(id: "load-1", operation: "load")]
    requests.append(contentsOf: cases.map {
      request(id: $0.requestID, operation: "transcribe", audio: $0.audioPath.path, locale: $0.locale)
    })
    requests.append(request(id: "cancel-1", operation: "cancel", target: "repeat"))
    requests.append(request(id: "unload-1", operation: "unload"))
    requests.append(request(id: "load-2", operation: "load"))
    requests.append(request(id: "shutdown-1", operation: "shutdown"))

    let started = DispatchTime.now().uptimeNanoseconds
    let result = try runProcess(
      executable: helper,
      arguments: helperArguments(modelPath: modelPath, runtimePath: runtimePath, sourcePath: sourcePath),
      input: try encodeLines(requests),
      timeout: 360
    )
    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
    try require(result.status == 0, "native-helper-exit:\(result.status):\(string(result.stderr))")
    let events = try decodeEvents(result.stdout)
    try require(!events.contains { $0["event"] as? String == "cancelled" }, "cancelled-event-observed")
    try require(string(result.stderr).contains("runtime-provenance=private-snapshot-after-use"), "runtime-provenance-after-use-not-observed")

    var cursor = 0
    try expectEvent(events, cursor: &cursor, kind: "ready", requestID: "load-1")
    for nativeCase in cases {
      var partials: [(Int, String)] = []
      while cursor < events.count,
        events[cursor]["event"] as? String == "partial",
        events[cursor]["requestID"] as? String == nativeCase.requestID {
        let event = events[cursor]
        guard let sequence = (event["sequence"] as? NSNumber)?.intValue,
          let transcript = event["transcript"] as? String
        else {
          throw ContractFailure(message: "partial-fields-missing:\(nativeCase.requestID)")
        }
        partials.append((sequence, transcript))
        cursor += 1
      }
      var measurements: [String: Double] = [:]
      while cursor < events.count, events[cursor]["event"] as? String == "measurement" {
        let measurement = events[cursor]
        try require(measurement["requestID"] as? String == nativeCase.requestID, "measurement-request-id:\(nativeCase.requestID)")
        guard let name = measurement["name"] as? String,
          let value = (measurement["value"] as? NSNumber)?.doubleValue
        else {
          throw ContractFailure(message: "measurement-fields-missing:\(nativeCase.requestID)")
        }
        try require(value.isFinite && value >= 0, "measurement-invalid:\(nativeCase.requestID):\(name)")
        measurements[name] = value
        cursor += 1
      }

      try require(cursor < events.count, "missing-final:\(nativeCase.requestID)")
      let final = events[cursor]
      try require(final["event"] as? String == "final", "final-order:\(nativeCase.requestID)")
      try require(final["requestID"] as? String == nativeCase.requestID, "final-request-id:\(nativeCase.requestID)")
      guard let finalTranscript = final["transcript"] as? String else {
        throw ContractFailure(message: "final-transcript-missing:\(nativeCase.requestID)")
      }
      cursor += 1
      if cursor < events.count,
        events[cursor]["event"] as? String == "measurement",
        events[cursor]["requestID"] as? String == nativeCase.requestID {
        throw ContractFailure(message: "measurement-after-final:\(nativeCase.requestID)")
      }

      for (index, partial) in partials.enumerated() {
        try require(partial.0 == index, "partial-sequence:\(nativeCase.requestID)")
        try require(!partial.1.isEmpty, "empty-partial:\(nativeCase.requestID)")
        if index > 0 {
          try require(partial.1 != partials[index - 1].1, "unchanged-partial:\(nativeCase.requestID)")
        }
      }
      try require(measurements["partialCount"] == Double(partials.count), "partial-count-mismatch:\(nativeCase.requestID)")
      try require(measurements["feedEndToFinalMs"] != nil, "feed-end-final-timing-missing:\(nativeCase.requestID)")
      try require(measurements["feedCadenceMs"] != nil, "feed-cadence-missing:\(nativeCase.requestID)")
      if let cadence = measurements["feedCadenceMs"] {
        try require(cadence >= 150, "feed-cadence-too-fast:\(nativeCase.requestID):\(cadence)")
      }
      if partials.isEmpty {
        try require(measurements["requestToFirstPartialMs"] == nil, "unobserved-first-partial-timing:\(nativeCase.requestID)")
      } else {
        try require(measurements["requestToFirstPartialMs"] != nil, "first-partial-timing-missing:\(nativeCase.requestID)")
      }
      let boundedTranscript = String(finalTranscript.prefix(160))
        .replacingOccurrences(of: "\n", with: " ")
      let cadenceDescription = format(measurements["feedCadenceMs"])
      let feedFinalDescription = format(measurements["feedEndToFinalMs"])
      print("nemotron case=\(nativeCase.requestID) partials=\(partials.count) final=\(boundedTranscript) feedCadenceMs=\(cadenceDescription) feedEndToFinalMs=\(feedFinalDescription)")
    }

    try expectFailure(events, cursor: &cursor, requestID: "cancel-1", code: "cancellation-unsupported")
    try expectEvent(events, cursor: &cursor, kind: "unloaded", requestID: "unload-1")
    try expectFailure(events, cursor: &cursor, requestID: "load-2", code: "load-already-attempted")
    try expectEvent(events, cursor: &cursor, kind: "unloaded", requestID: "shutdown-1")
    try require(cursor == events.count, "unexpected-trailing-events:\(events.count - cursor)")
    let elapsedDescription = String(format: "%.1f", elapsed)
    print("nemotron protocol elapsedMs=\(elapsedDescription) partial-truth=observed-native-interims-only cancellation=unsupported")
  }

  private static func runProtocolFailureChecks(
    helper: URL,
    modelPath: URL,
    runtimePath: URL,
    sourcePath: URL
  ) throws {
    let malformedLines = [
      "{\"schemaVersion\":1,\"requestID\":\"safe-id\",\"requestID\":\"attacker-id\",\"operation\":\"load\"}",
      "{\"schemaVersion\":1,\"requestID\":\"operation-id\",\"operation\":\"load\",\"oper\\u0061tion\":\"shutdown\"}",
      "{\"schemaVersion\":1,\"reques\\u0074ID\":\"escaped-id\",\"requestID\":\"attacker-id\",\"operation\":\"load\"}",
      "{\"schemaVersion\":1,\"requestID\":\"schema-id\",\"operation\":\"load\",\"schemaVersion\":1}",
      "{\"schemaVersion\":1,\"requestID\":\"unknown-id\",\"operation\":\"load\",\"rogue\":true}",
      "[\"not-an-object\"]",
    ]
    let result = try runProcess(
      executable: helper,
      arguments: helperArguments(modelPath: modelPath, runtimePath: runtimePath, sourcePath: sourcePath),
      input: Data((malformedLines.joined(separator: "\n") + "\n").utf8),
      timeout: 20,
      environment: ["FLECK_NEMOTRON_NATIVE_OPEN_PROBE": "1"]
    )
    try require(result.status == 0, "malformed-protocol-exit:\(result.status)")
    let events = try decodeEvents(result.stdout)
    try require(events.count == malformedLines.count, "malformed-protocol-event-count:\(events.count)")
    for event in events {
      try require(event["event"] as? String == "failure", "malformed-protocol-not-failure")
      try require(event["requestID"] as? String == "protocol-error", "malformed-protocol-id-leaked")
    }
    let codes = events.compactMap { $0["code"] as? String }
    try require(codes.count == malformedLines.count, "malformed-protocol-codes")
    try require(codes[0..<4].allSatisfy { $0 == "duplicate-json-key" }, "duplicate-key-contract")
    try require(codes[4] == "unknown-field", "unknown-field-contract")
    try require(codes[5] == "malformed-json", "malformed-json-contract")
    try require(!string(result.stderr).contains("native-dlopen-attempted"), "malformed-triggered-native-load")

    let flood = String(repeating: "x", count: 1_048_576 + 1) + "\n"
    let floodResult = try runProcess(
      executable: helper,
      arguments: helperArguments(modelPath: modelPath, runtimePath: runtimePath, sourcePath: sourcePath),
      input: Data(flood.utf8),
      timeout: 20
    )
    try require(floodResult.status == 2, "flood-exit:\(floodResult.status)")
    let floodEvents = try decodeEvents(floodResult.stdout)
    try require(floodEvents.count == 1, "flood-event-count")
    try require(floodEvents[0]["code"] as? String == "line-too-large", "flood-code")

    let requestFlood = String(repeating: "x\n", count: 513)
    let requestFloodResult = try runProcess(
      executable: helper,
      arguments: helperArguments(modelPath: modelPath, runtimePath: runtimePath, sourcePath: sourcePath),
      input: Data(requestFlood.utf8),
      timeout: 20
    )
    try require(requestFloodResult.status == 2, "request-flood-exit:\(requestFloodResult.status)")
    let requestFloodEvents = try decodeEvents(requestFloodResult.stdout)
    try require(requestFloodEvents.count == 513, "request-flood-event-count:\(requestFloodEvents.count)")
    try require(requestFloodEvents.last?["code"] as? String == "stdin-flood", "request-flood-code")

    let orderResult = try runProcess(
      executable: helper,
      arguments: helperArguments(modelPath: modelPath, runtimePath: runtimePath, sourcePath: sourcePath),
      input: try encodeLines([
        request(id: "before-load-transcribe", operation: "transcribe", audio: "/private/tmp/missing.wav", locale: "en-US"),
        request(id: "before-load-unload", operation: "unload"),
        request(id: "before-load-shutdown", operation: "shutdown"),
      ]),
      timeout: 20
    )
    try require(orderResult.status == 0, "order-exit:\(orderResult.status)")
    let orderEvents = try decodeEvents(orderResult.stdout)
    try require(orderEvents.count == 3, "order-event-count")
    try require(orderEvents[0]["code"] as? String == "not-loaded", "transcribe-before-load-code")
    try require(orderEvents[1]["code"] as? String == "invalid-order", "unload-before-load-code")
    try require(orderEvents[2]["code"] as? String == "invalid-order", "shutdown-before-load-code")
    print("protocol strict-json=duplicate-unknown-malformed order=fail-closed flood=fail-closed")
  }

  private static func runIdentityAndPathChecks(
    helper: URL,
    modelPath: URL,
    runtimePath: URL,
    sourcePath: URL
  ) throws {
    let otool = try runProcess(
      executable: URL(fileURLWithPath: "/usr/bin/otool"),
      arguments: ["-L", helper.path],
      input: Data(),
      timeout: 10
    )
    try require(otool.status == 0, "otool-helper-failed")
    let linked = string(otool.stdout)
    try require(!linked.contains("libnemo_speech_asr") && !linked.contains(runtimePath.path), "native-pre-main-link-present")

    let temporaryRoot = try makeTemporaryDirectory(prefix: "fleck-nemotron-identity")
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }

    let badModel = temporaryRoot.appendingPathComponent(NemotronRecognizerModelFileName)
    try Data("not-the-pinned-model".utf8).write(to: badModel, options: .atomic)
    try assertLoadRejected(
      helper: helper, modelPath: badModel, runtimePath: runtimePath, sourcePath: sourcePath,
      code: "model-identity-mismatch", label: "model-identity", probe: true
    )

    let modelAlias = temporaryRoot.appendingPathComponent("model-alias")
    try FileManager.default.createSymbolicLink(atPath: modelAlias.path, withDestinationPath: modelPath.path)
    try assertLoadRejected(
      helper: helper, modelPath: modelAlias, runtimePath: runtimePath, sourcePath: sourcePath,
      code: "invalid-model-path", label: "model-symlink", probe: true
    )

    let sourceAlias = temporaryRoot.appendingPathComponent("source-alias")
    try FileManager.default.createSymbolicLink(atPath: sourceAlias.path, withDestinationPath: sourcePath.path)
    try assertLoadRejected(
      helper: helper, modelPath: modelPath, runtimePath: runtimePath, sourcePath: sourceAlias,
      code: "invalid-source-path", label: "source-symlink", probe: true
    )

    let runtimeAlias = temporaryRoot.appendingPathComponent("runtime-alias")
    try FileManager.default.createSymbolicLink(atPath: runtimeAlias.path, withDestinationPath: runtimePath.path)
    try assertLoadRejected(
      helper: helper, modelPath: modelPath, runtimePath: runtimeAlias, sourcePath: sourcePath,
      code: "invalid-runtime-path", label: "runtime-symlink", probe: true
    )

    let extraRuntime = temporaryRoot.appendingPathComponent("runtime-extra", isDirectory: true)
    try cloneRuntime(from: runtimePath, to: extraRuntime)
    try Data("unexpected".utf8).write(to: extraRuntime.appendingPathComponent("extra"), options: .atomic)
    try assertLoadRejected(
      helper: helper, modelPath: modelPath, runtimePath: extraRuntime, sourcePath: sourcePath,
      code: "runtime-identity-mismatch", label: "runtime-extra", probe: true
    )

    let tamperedRuntime = temporaryRoot.appendingPathComponent("runtime-tampered", isDirectory: true)
    try cloneRuntime(from: runtimePath, to: tamperedRuntime)
    let tamperedFile = tamperedRuntime.appendingPathComponent("libnemo_speech_asr_c.1.dylib")
    var tamperedData = try Data(contentsOf: tamperedFile)
    tamperedData[0] ^= 1
    try tamperedData.write(to: tamperedFile, options: .atomic)
    try assertLoadRejected(
      helper: helper, modelPath: modelPath, runtimePath: tamperedRuntime, sourcePath: sourcePath,
      code: "runtime-identity-mismatch", label: "runtime-tamper", probe: true
    )

    let escapingRuntime = temporaryRoot.appendingPathComponent("runtime-escaping", isDirectory: true)
    try cloneRuntime(from: runtimePath, to: escapingRuntime)
    try FileManager.default.createSymbolicLink(
      atPath: escapingRuntime.appendingPathComponent("escape").path,
      withDestinationPath: "/private/tmp"
    )
    try assertLoadRejected(
      helper: helper, modelPath: modelPath, runtimePath: escapingRuntime, sourcePath: sourcePath,
      code: "runtime-identity-mismatch", label: "runtime-absolute-symlink", probe: true
    )

    let danglingRuntime = temporaryRoot.appendingPathComponent("runtime-dangling", isDirectory: true)
    try cloneRuntime(from: runtimePath, to: danglingRuntime)
    try FileManager.default.createSymbolicLink(
      atPath: danglingRuntime.appendingPathComponent("dangling").path,
      withDestinationPath: "missing-target"
    )
    try assertLoadRejected(
      helper: helper, modelPath: modelPath, runtimePath: danglingRuntime, sourcePath: sourcePath,
      code: "runtime-identity-mismatch", label: "runtime-dangling-symlink", probe: true
    )
    print("identity-before-load:tamper-symlink-path-rejections-pass native-dlopen=0")
  }

  private static func runConcurrentSubstitutionChecks(
    helper: URL,
    modelPath: URL,
    runtimePath: URL,
    sourcePath: URL,
    audioPath: URL
  ) throws {
    let temporaryRoot = try makeTemporaryDirectory(prefix: "fleck-nemotron-concurrent-substitution")
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }

    let modelRaceDirectory = temporaryRoot.appendingPathComponent("model-race", isDirectory: true)
    try FileManager.default.createDirectory(at: modelRaceDirectory, withIntermediateDirectories: false)
    let modelRacePath = modelRaceDirectory.appendingPathComponent(NemotronRecognizerModelFileName)
    try FileManager.default.linkItem(at: modelPath, to: modelRacePath)
    let modelResult = try runPausedProcess(
      executable: helper,
      arguments: helperArguments(modelPath: modelRacePath, runtimePath: runtimePath, sourcePath: sourcePath),
      input: try encodeLines([
        request(id: "race-model-load", operation: "load"),
        request(id: "race-model-shutdown", operation: "shutdown"),
      ]),
      stage: "after-model-descriptor",
      timeout: 180
    ) {
      try replaceFile(at: modelRacePath, contents: Data("substituted-model".utf8))
    }
    try require(modelResult.status == 0, "model-substitution-process:\(modelResult.status):\(string(modelResult.stderr))")
    let modelEvents = try decodeEvents(modelResult.stdout)
    try require(modelEvents.contains { $0["event"] as? String == "ready" }, "model-substitution-used-unverified-object")
    try require(modelEvents.last?["event"] as? String == "unloaded", "model-substitution-shutdown")

    let runtimeRaceDirectory = temporaryRoot.appendingPathComponent("runtime-race", isDirectory: true)
    try cloneRuntime(from: runtimePath, to: runtimeRaceDirectory)
    let runtimeRaceDylib = runtimeRaceDirectory.appendingPathComponent("libnemo_speech_asr_c.1.dylib")
    let runtimeResult = try runPausedProcess(
      executable: helper,
      arguments: helperArguments(modelPath: modelPath, runtimePath: runtimeRaceDirectory, sourcePath: sourcePath),
      input: try encodeLines([
        request(id: "race-runtime-load", operation: "load"),
        request(id: "race-runtime-shutdown", operation: "shutdown"),
      ]),
      stage: "after-runtime-snapshot",
      timeout: 180
    ) {
      try replaceFile(at: runtimeRaceDylib, contents: Data("substituted-runtime".utf8))
    }
    try require(runtimeResult.status == 0, "runtime-substitution-process:\(runtimeResult.status):\(string(runtimeResult.stderr))")
    let runtimeEvents = try decodeEvents(runtimeResult.stdout)
    try require(runtimeEvents.contains { $0["event"] as? String == "ready" }, "runtime-substitution-used-unverified-object")
    try require(runtimeEvents.last?["event"] as? String == "unloaded", "runtime-substitution-shutdown")

    let dependencyRaceDirectory = temporaryRoot.appendingPathComponent("runtime-dependency-race", isDirectory: true)
    try cloneRuntime(from: runtimePath, to: dependencyRaceDirectory)
    let dependencyRaceDylib = dependencyRaceDirectory.appendingPathComponent("libggml-base.0.12.0.dylib")
    let dependencyResult = try runPausedProcess(
      executable: helper,
      arguments: helperArguments(modelPath: modelPath, runtimePath: dependencyRaceDirectory, sourcePath: sourcePath),
      input: try encodeLines([
        request(id: "race-dependency-load", operation: "load"),
        request(id: "race-dependency-shutdown", operation: "shutdown"),
      ]),
      stage: "after-runtime-snapshot",
      timeout: 180
    ) {
      try replaceFile(at: dependencyRaceDylib, contents: Data("substituted-runtime-dependency".utf8))
    }
    try require(dependencyResult.status == 0, "dependency-substitution-process:\(dependencyResult.status):\(string(dependencyResult.stderr))")
    let dependencyEvents = try decodeEvents(dependencyResult.stdout)
    try require(dependencyEvents.contains { $0["event"] as? String == "ready" }, "dependency-substitution-used-external-object")
    try require(dependencyEvents.last?["event"] as? String == "unloaded", "dependency-substitution-shutdown")
    try require(string(dependencyResult.stderr).contains("runtime-provenance=private-snapshot"), "dependency-substitution-provenance-not-observed")

    let audioRaceDirectory = temporaryRoot.appendingPathComponent("audio-race", isDirectory: true)
    try FileManager.default.createDirectory(at: audioRaceDirectory, withIntermediateDirectories: false)
    let audioRacePath = audioRaceDirectory.appendingPathComponent(audioPath.lastPathComponent)
    try FileManager.default.linkItem(at: audioPath, to: audioRacePath)
    let audioResult = try runPausedProcess(
      executable: helper,
      arguments: helperArguments(modelPath: modelPath, runtimePath: runtimePath, sourcePath: sourcePath),
      input: try encodeLines([
        request(id: "race-audio-load", operation: "load"),
        request(id: "race-audio-transcribe", operation: "transcribe", audio: audioRacePath.path, locale: "auto"),
        request(id: "race-audio-shutdown", operation: "shutdown"),
      ]),
      stage: "after-audio-descriptor",
      timeout: 180
    ) {
      try replaceFile(at: audioRacePath, contents: Data("substituted-audio".utf8))
    }
    try require(audioResult.status == 0, "audio-substitution-process:\(audioResult.status):\(string(audioResult.stderr))")
    let audioEvents = try decodeEvents(audioResult.stdout)
    try require(audioEvents.contains { $0["event"] as? String == "ready" }, "audio-substitution-load")
    try require(audioEvents.contains { $0["event"] as? String == "final" && $0["requestID"] as? String == "race-audio-transcribe" }, "audio-substitution-used-unverified-object")
    try require(audioEvents.last?["event"] as? String == "unloaded", "audio-substitution-shutdown")
    print("concurrent-substitution model=descriptor-snapshot runtime=dylib-snapshot dependency=private-runtime-snapshot audio=descriptor-snapshot")
  }

  private static func runRuntimeProvenanceContract(runtimePath: URL) throws {
    let temporaryRoot = try makeTemporaryDirectory(prefix: "fleck-nemotron-runtime-provenance")
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }
    let expectedSnapshot = temporaryRoot.appendingPathComponent("runtime-snapshot", isDirectory: true)
    try cloneRuntime(from: runtimePath, to: expectedSnapshot)
    let externalLibrary = runtimePath.appendingPathComponent("libnemo_speech_asr_c.1.dylib")
    guard let table = externalLibrary.path.withCString({ FleckNemoOpenVerified($0) }) else {
      throw ContractFailure(message: "external-provenance-fixture-open-failed")
    }
    defer { FleckNemoCloseVerified(table) }
    let accepted = expectedSnapshot.path.withCString {
      FleckNemoVerifyRuntimeProvenance(table, $0)
    }
    try require(accepted == 0, "external-dependency-provenance-accepted")
    print("runtime-provenance negative-external-dependency=reject-pass")
  }

  private static func runBuildPathChecks(repoRoot: URL, sourcePath: URL) throws {
    let buildScript = repoRoot
      .appendingPathComponent("Tools/LocalDictationCandidateAdapters/Spikes/NemotronASR/NativeEvaluation/build.sh")
    let temporaryRoot = try makeTemporaryDirectory(prefix: "fleck-nemotron-build-paths")
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }

    let sourceAlias = temporaryRoot.appendingPathComponent("source-alias")
    try FileManager.default.createSymbolicLink(atPath: sourceAlias.path, withDestinationPath: sourcePath.path)
    let outputTarget = temporaryRoot.appendingPathComponent("output-target", isDirectory: true)
    try FileManager.default.createDirectory(at: outputTarget, withIntermediateDirectories: false)
    let outputAlias = temporaryRoot.appendingPathComponent("output-alias")
    try FileManager.default.createSymbolicLink(atPath: outputAlias.path, withDestinationPath: outputTarget.path)

    let cases: [(String, String, String)] = [
      ("repo-output", sourcePath.path, repoRoot.path),
      ("source-alias", sourceAlias.path, temporaryRoot.appendingPathComponent("source-output").path),
      ("output-alias", sourcePath.path, outputAlias.appendingPathComponent("child").path),
    ]
    for (label, source, output) in cases {
      let before = try directEntries(of: temporaryRoot)
      let result = try runProcess(
        executable: URL(fileURLWithPath: "/bin/bash"),
        arguments: [buildScript.path, "--source-path", source, "--output-root", output],
        input: Data(),
        timeout: 15
      )
      try require(result.status != 0, "build-path-accepted:\(label)")
      let after = try directEntries(of: temporaryRoot)
      try require(after == before, "build-path-mutated:\(label)")
    }
    try runBuildConcurrentSubstitutionChecks(repoRoot: repoRoot, sourcePath: sourcePath)
    print("build path aliases/output-inside-repo:rejected-without-mutation")
  }

  private static func runBuildConcurrentSubstitutionChecks(repoRoot: URL, sourcePath: URL) throws {
    let buildScript = repoRoot
      .appendingPathComponent("Tools/LocalDictationCandidateAdapters/Spikes/NemotronASR/NativeEvaluation/build.sh")
    let temporaryRoot = try makeTemporaryDirectory(prefix: "fleck-nemotron-build-races")
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }

    let sourceRace = temporaryRoot.appendingPathComponent("source-race", isDirectory: true)
    try cloneSource(from: sourcePath, to: sourceRace)
    let sourceRaceOutput = temporaryRoot.appendingPathComponent("source-race-output", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceRaceOutput, withIntermediateDirectories: false)
    let sourceResult = try runPausedProcess(
      executable: URL(fileURLWithPath: "/bin/bash"),
      arguments: [buildScript.path, "--source-path", sourceRace.path, "--output-root", sourceRaceOutput.path],
      input: Data(),
      stage: "after-source-identity",
      timeout: 30
    ) {
      try replaceDirectory(at: sourceRace)
    }
    try require(sourceResult.status != 0, "source-substitution-accepted")
    let sourceRaceOutputEntries = try directEntries(of: sourceRaceOutput)
    try require(sourceRaceOutputEntries.isEmpty, "source-substitution-wrote-output")

    let inputRace = temporaryRoot.appendingPathComponent("input-race", isDirectory: true)
    try cloneSource(from: sourcePath, to: inputRace)
    let inputRaceOutput = temporaryRoot.appendingPathComponent("input-race-output", isDirectory: true)
    try FileManager.default.createDirectory(at: inputRaceOutput, withIntermediateDirectories: false)
    let inputResult = try runPausedProcess(
      executable: URL(fileURLWithPath: "/bin/bash"),
      arguments: [buildScript.path, "--source-path", inputRace.path, "--output-root", inputRaceOutput.path],
      input: Data(),
      stage: "after-build-input-snapshot",
      timeout: 30
    ) {
      try replaceFile(
        at: inputRace.appendingPathComponent("include/nemo_speech/asr.h"),
        contents: Data("#error substituted-build-input\n".utf8)
      )
    }
    try require(inputResult.status != 0, "build-input-substitution-accepted")
    let inputRaceOutputEntries = try directEntries(of: inputRaceOutput)
    try require(inputRaceOutputEntries.isEmpty, "build-input-substitution-wrote-output")

    let outputParent = temporaryRoot.appendingPathComponent("output-parent", isDirectory: true)
    let outputRoot = outputParent.appendingPathComponent("approved-output", isDirectory: true)
    try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)
    let outputResult = try runPausedProcess(
      executable: URL(fileURLWithPath: "/bin/bash"),
      arguments: [buildScript.path, "--source-path", sourcePath.path, "--output-root", outputRoot.path],
      input: Data(),
      stage: "before-publish",
      timeout: 30
    ) {
      try replaceDirectory(at: outputParent)
      try FileManager.default.createDirectory(
        at: outputParent.appendingPathComponent("approved-output", isDirectory: true),
        withIntermediateDirectories: false
      )
    }
    try require(outputResult.status != 0, "output-parent-substitution-accepted")
    let replacementOutputEntries = try directEntries(
      of: outputParent.appendingPathComponent("approved-output")
    )
    try require(replacementOutputEntries.isEmpty, "output-parent-substitution-redirected-write")
    print("concurrent-substitution source=anchored build-input=snapshot output-parent=fd-exclusive-no-redirect")
  }

  private static func runForcedTerminationCheck(
    helper: URL,
    modelPath: URL,
    runtimePath: URL,
    sourcePath: URL,
    audioPath: URL
  ) throws {
    let evidence = try collectBlockedDecodeEvidence(
      executable: helper,
      arguments: helperArguments(
        modelPath: modelPath, runtimePath: runtimePath, sourcePath: sourcePath
      ) + ["--probe-blocked-decode"],
      input: try encodeLines([
      request(id: "probe-load", operation: "load"),
      request(id: "probe-transcribe", operation: "transcribe", audio: audioPath.path, locale: "en-US"),
      ]),
      markerTimeout: 180,
      preTerminationDelay: 0
    )
    let events = try decodeEvents(evidence.stdout)
    try require(evidence.status != 0, "blocked-decode-was-not-force-terminated")
    try require(!events.contains { $0["event"] as? String == "final" }, "late-final-after-forced-termination")
    try require(!events.contains { $0["event"] as? String == "cancelled" }, "cancelled-after-forced-termination")
    do {
      try assertBlockedDecodeEvidence(evidence, label: "blocked-decode")
      print("cancellation classification=unsupported-cooperative-active-decode blocked-decode-in-flight terminate-requested-before-return process-force-terminated late-final=0")
    } catch let failure as ContractFailure
      where failure.message == "blocked-decode-native-decode-returned-before-termination" {
      try require(evidence.status != 0, "blocked-decode-fail-closed-was-not-force-terminated")
      try require(evidence.events.contains("supervisor-kill-requested"), "blocked-decode-fail-closed-missing-kill")
      print("cancellation classification=unsupported-cooperative-active-decode blocked-decode-marker=observed native-call-returned-before-supervisor-kill=fail-closed process-force-terminated late-final=0")
    }
  }

  private static func collectBlockedDecodeEvidence(
    executable: URL,
    arguments: [String],
    input: Data,
    markerTimeout: TimeInterval,
    preTerminationDelay: TimeInterval
  ) throws -> BlockedDecodeEvidence {
    let inputPipe = Pipe()
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.standardInput = inputPipe
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    let marker = DispatchSemaphore(value: 0)
    let stderrReaderGroup = DispatchGroup()
    let stderrLock = NSLock()
    var stderrData = Data()
    var stderrLineBuffer = Data()
    var stderrEvents: [String] = []
    var readerStarted = false
    var readerJoined = false

    func joinReader() {
      guard readerStarted, !readerJoined else { return }
      stderrReaderGroup.wait()
      readerJoined = true
    }

    try process.run()
    readerStarted = true
    stderrReaderGroup.enter()
    DispatchQueue.global(qos: .utility).async {
      defer { stderrReaderGroup.leave() }
      while true {
        let data = errorPipe.fileHandleForReading.availableData
        guard !data.isEmpty else { break }
        var hasMarker = false
        stderrLock.lock()
        stderrData.append(data)
        stderrLineBuffer.append(data)
        while let newline = stderrLineBuffer.firstIndex(of: 0x0A) {
          let lineEnd = stderrLineBuffer.index(after: newline)
          let lineData = Data(stderrLineBuffer[..<newline])
          stderrLineBuffer.removeSubrange(..<lineEnd)
          if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
            stderrEvents.append(line)
          }
        }
        hasMarker = stderrData.range(of: Data("native-decode-blocked".utf8)) != nil
        stderrLock.unlock()
        if hasMarker { marker.signal() }
      }
      stderrLock.lock()
      if !stderrLineBuffer.isEmpty,
        let line = String(data: stderrLineBuffer, encoding: .utf8), !line.isEmpty {
        stderrEvents.append(line)
      }
      stderrLock.unlock()
    }

    defer {
      if process.isRunning {
        _ = Darwin.kill(process.processIdentifier, SIGKILL)
        process.waitUntilExit()
      }
      joinReader()
    }

    if !input.isEmpty {
      try inputPipe.fileHandleForWriting.write(contentsOf: input)
    }
    inputPipe.fileHandleForWriting.closeFile()

    let markerDeadline = Date().addingTimeInterval(markerTimeout)
    var markerObserved = false
    while !markerObserved && process.isRunning && Date() < markerDeadline {
      if marker.wait(timeout: .now() + 0.1) == .success {
        markerObserved = true
        break
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
    guard markerObserved else {
      if process.isRunning {
        _ = Darwin.kill(process.processIdentifier, SIGKILL)
        process.waitUntilExit()
      }
      joinReader()
      stderrLock.lock()
      let diagnostic = string(stderrData)
      stderrLock.unlock()
      throw ContractFailure(message: "blocked-decode-marker-timeout:\(diagnostic)")
    }
    try require(process.isRunning, "blocked-decode-exited-before-termination")

    if preTerminationDelay > 0 {
      let delayDeadline = Date().addingTimeInterval(preTerminationDelay)
      while Date() < delayDeadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
      }
    }

    stderrLock.lock()
    stderrEvents.append("supervisor-terminate-requested")
    stderrEvents.append("supervisor-kill-requested")
    stderrLock.unlock()
    try require(Darwin.kill(process.processIdentifier, SIGKILL) == 0, "blocked-decode-kill-request-failed")
    process.waitUntilExit()

    joinReader()
    stderrLock.lock()
    let capturedStderr = stderrData
    let capturedEvents = stderrEvents
    stderrLock.unlock()
    return BlockedDecodeEvidence(
      status: process.terminationStatus,
      stdout: outputPipe.fileHandleForReading.readDataToEndOfFile(),
      stderr: string(capturedStderr),
      events: capturedEvents
    )
  }

  private static func assertBlockedDecodeEvidence(
    _ evidence: BlockedDecodeEvidence,
    label: String
  ) throws {
    guard let entry = evidence.events.firstIndex(of: "native-decode-entry"),
      let inFlight = evidence.events.firstIndex(of: "native-decode-in-flight"),
      let blocked = evidence.events.firstIndex(of: "native-decode-blocked"),
      let termination = evidence.events.firstIndex(of: "supervisor-terminate-requested") else {
      throw ContractFailure(message: "\(label)-marker-order-missing")
    }
    try require(entry < inFlight, "\(label)-entry-order")
    try require(inFlight < blocked, "\(label)-in-flight-order")
    try require(blocked < termination, "\(label)-termination-before-marker")
    if let returned = evidence.events.firstIndex(of: "native-decode-returned") {
      let timing = returned < termination ? "before-termination" : "after-termination"
      throw ContractFailure(message: "\(label)-native-decode-returned-\(timing)")
    }
  }

  private static func runLateReturnEvidenceContract() throws {
    let temporaryRoot = try makeTemporaryDirectory(prefix: "fleck-nemotron-late-return")
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }
    let fakeSource = temporaryRoot.appendingPathComponent("fake-blocked-decode.c")
    let fakeProcess = temporaryRoot.appendingPathComponent("fake-blocked-decode")
    try Data(fakeBlockedDecodeProcessSource.utf8).write(to: fakeSource, options: .atomic)
    let compile = try runProcess(
      executable: URL(fileURLWithPath: "/usr/bin/clang"),
      arguments: [
        "-target", "arm64-apple-macosx14.0", "-O2", "-Wall", "-Werror",
        fakeSource.path, "-o", fakeProcess.path,
      ],
      input: Data(),
      timeout: 30
    )
    try require(compile.status == 0, "late-return-fake-build:\(string(compile.stderr))")

    let evidence = try collectBlockedDecodeEvidence(
      executable: fakeProcess,
      arguments: [],
      input: Data(),
      markerTimeout: 10,
      preTerminationDelay: 0.100
    )
    guard let returned = evidence.events.firstIndex(of: "native-decode-returned"),
      let termination = evidence.events.firstIndex(of: "supervisor-terminate-requested") else {
      throw ContractFailure(message: "late-return-evidence-missing")
    }
    try require(returned < termination, "late-return-was-not-before-termination")
    try require(evidence.events.contains("supervisor-kill-requested"), "late-return-fake-was-not-forcibly-terminated")
    do {
      try assertBlockedDecodeEvidence(evidence, label: "late-return-evidence")
      throw ContractFailure(message: "late-return-evidence-accepted")
    } catch let failure as ContractFailure {
      try require(
        failure.message == "late-return-evidence-native-decode-returned-before-termination",
        "late-return-wrong-rejection:\(failure.message)"
      )
    }
    print("blocked-decode late-return-evidence=rejected-after-synchronous-stderr-drain")
  }

  private static func runFakeStreamingContract(sourcePath: URL) throws {
    let temporaryRoot = try makeTemporaryDirectory(prefix: "fleck-nemotron-fake-contract")
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }
    let fakeSource = temporaryRoot.appendingPathComponent("fake-nemo.c")
    let fakeLibrary = temporaryRoot.appendingPathComponent("libfake-nemo.dylib")
    try Data(fakeLibrarySource.utf8).write(to: fakeSource, options: .atomic)
    let compile = try runProcess(
      executable: URL(fileURLWithPath: "/usr/bin/clang"),
      arguments: [
        "-dynamiclib", "-arch", "arm64", "-I", sourcePath.appendingPathComponent("include").path,
        fakeSource.path, "-o", fakeLibrary.path,
      ],
      input: Data(),
      timeout: 30
    )
    try require(compile.status == 0, "fake-contract-library-build:\(string(compile.stderr))")

    for mode in ["zero", "one", "many"] {
      setenv("FLECK_FAKE_RESULTS", mode, 1)
      defer { unsetenv("FLECK_FAKE_RESULTS") }
      guard let table = fakeLibrary.path.withCString({ FleckNemoOpenVerified($0) }) else {
        throw ContractFailure(message: "fake-symbol-provenance-rejected:\(mode)")
      }
      guard let recognizer = "/private/tmp/fake-model.gguf".withCString({
        FleckNemoCreateRecognizer(table, $0, 0)
      }) else {
        FleckNemoCloseVerified(table)
        throw ContractFailure(message: "fake-recognizer-create:\(mode)")
      }
      guard let stream = "fake-request".withCString({
        FleckNemoCreateStream(table, recognizer, $0, nil)
      }) else {
        FleckNemoDestroyRecognizer(table, recognizer)
        FleckNemoCloseVerified(table)
        throw ContractFailure(message: "fake-stream-create:\(mode)")
      }

      var partials: [String] = []
      var finals = 0
      func drain() throws {
        while true {
          var result: UnsafeMutableRawPointer?
          let status = FleckNemoNext(table, stream, &result)
          try require(status == 0, "fake-stream-next:\(mode)")
          guard let result else { return }
          defer { FleckNemoDestroyResult(table, result) }
          guard let pointer = FleckNemoTranscript(table, result) else {
            throw ContractFailure(message: "fake-transcript-pointer:\(mode)")
          }
          let transcript = String(cString: pointer)
          if FleckNemoIsFinal(table, result) != 0 {
            finals += 1
            try require(transcript == "final", "fake-final-text:\(mode)")
          } else {
            try require(!transcript.isEmpty, "fake-empty-partial:\(mode)")
            if let previous = partials.last {
              try require(previous != transcript, "fake-unchanged-partial:\(mode)")
            }
            partials.append(transcript)
          }
        }
      }

      let samples = [Float](repeating: 0, count: 2_560)
      for _ in 0..<3 {
        let status = samples.withUnsafeBufferPointer { buffer in
          FleckNemoPush(table, stream, buffer.baseAddress, buffer.count, 16_000)
        }
        try require(status == 0, "fake-stream-push:\(mode)")
        try drain()
      }
      try require(FleckNemoFinish(table, stream) == 0, "fake-stream-finish:\(mode)")
      try drain()
      try require(finals == 1, "fake-final-count:\(mode):\(finals)")
      let expectedPartialCount = mode == "zero" ? 0 : (mode == "one" ? 1 : 3)
      try require(partials.count == expectedPartialCount, "fake-partial-count:\(mode):\(partials.count)")
      FleckNemoCloseStream(table, stream)
      FleckNemoDestroyRecognizer(table, recognizer)
      FleckNemoCloseVerified(table)
    }
    print("fake contract library symbol-provenance=pass partials=zero/one/many final-order=pass")
  }

  private static func assertLoadRejected(
    helper: URL,
    modelPath: URL,
    runtimePath: URL,
    sourcePath: URL,
    code: String,
    label: String,
    probe: Bool
  ) throws {
    let result = try runProcess(
      executable: helper,
      arguments: helperArguments(modelPath: modelPath, runtimePath: runtimePath, sourcePath: sourcePath),
      input: try encodeLines([request(id: "load-\(label)", operation: "load")]),
      timeout: 30,
      environment: probe ? ["FLECK_NEMOTRON_NATIVE_OPEN_PROBE": "1"] : [:]
    )
    try require(result.status == 0, "rejection-exit:\(label):\(result.status)")
    let events = try decodeEvents(result.stdout)
    try require(events.count == 1, "rejection-event-count:\(label)")
    try require(events[0]["event"] as? String == "failure", "rejection-event-kind:\(label)")
    try require(events[0]["code"] as? String == code, "rejection-code:\(label):\(events[0]["code"] as? String ?? "missing")")
    try require(!events.contains { $0["event"] as? String == "ready" }, "rejection-ready:\(label)")
    if probe {
      try require(!string(result.stderr).contains("native-dlopen-attempted"), "rejection-dlopen:\(label)")
    }
  }

  private static func helperArguments(modelPath: URL, runtimePath: URL, sourcePath: URL) -> [String] {
    [
      "--model-path", modelPath.path,
      "--runtime-path", runtimePath.path,
      "--source-path", sourcePath.path,
    ]
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
    var events: [[String: Any]] = []
    for line in string(data).split(separator: "\n", omittingEmptySubsequences: true) {
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

  private static func expectEvent(
    _ events: [[String: Any]],
    cursor: inout Int,
    kind: String,
    requestID: String
  ) throws {
    try require(cursor < events.count, "missing-event:\(kind):\(requestID)")
    let event = events[cursor]
    try require(event["event"] as? String == kind, "event-kind:\(kind):\(requestID)")
    try require(event["requestID"] as? String == requestID, "event-request-id:\(kind):\(requestID)")
    cursor += 1
  }

  private static func expectFailure(
    _ events: [[String: Any]],
    cursor: inout Int,
    requestID: String,
    code: String
  ) throws {
    try expectEvent(events, cursor: &cursor, kind: "failure", requestID: requestID)
    try require(events[cursor - 1]["code"] as? String == code, "failure-code:\(requestID)")
  }

  private static func runPausedProcess(
    executable: URL,
    arguments: [String],
    input: Data,
    stage: String,
    timeout: TimeInterval,
    mutate: () throws -> Void
  ) throws -> ProcessResult {
    let pauseRoot = try makeTemporaryDirectory(prefix: "fleck-nemotron-pause")
    defer { try? FileManager.default.removeItem(at: pauseRoot) }
    let marker = pauseRoot.appendingPathComponent("marker")
    let release = pauseRoot.appendingPathComponent("release")
    let process = Process()
    let inputPipe = Pipe()
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.executableURL = executable
    process.arguments = arguments
    process.standardInput = inputPipe
    process.standardOutput = outputPipe
    process.standardError = errorPipe
    var environment = ProcessInfo.processInfo.environment
    environment["FLECK_NEMOTRON_TEST_PAUSE"] = stage
    environment["FLECK_NEMOTRON_TEST_MARKER"] = marker.path
    environment["FLECK_NEMOTRON_TEST_RELEASE"] = release.path
    environment["FLECK_NEMOTRON_BUILD_TEST_PAUSE"] = stage
    environment["FLECK_NEMOTRON_BUILD_TEST_MARKER"] = marker.path
    environment["FLECK_NEMOTRON_BUILD_TEST_RELEASE"] = release.path
    process.environment = environment

    let outputGroup = DispatchGroup()
    let errorGroup = DispatchGroup()
    var stdout = Data()
    var stderr = Data()
    let outputLock = NSLock()
    let errorLock = NSLock()
    outputGroup.enter()
    DispatchQueue.global(qos: .utility).async {
      let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
      outputLock.lock()
      stdout = data
      outputLock.unlock()
      outputGroup.leave()
    }
    errorGroup.enter()
    DispatchQueue.global(qos: .utility).async {
      let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
      errorLock.lock()
      stderr = data
      errorLock.unlock()
      errorGroup.leave()
    }

    try process.run()
    defer {
      if process.isRunning {
        _ = Darwin.kill(process.processIdentifier, SIGKILL)
        process.waitUntilExit()
      }
    }
    try inputPipe.fileHandleForWriting.write(contentsOf: input)
    inputPipe.fileHandleForWriting.closeFile()
    let deadline = Date().addingTimeInterval(timeout)
    while !FileManager.default.fileExists(atPath: marker.path) {
      guard process.isRunning, Date() < deadline else {
        outputGroup.wait()
        errorGroup.wait()
        errorLock.lock()
        let diagnostic = string(stderr)
        errorLock.unlock()
        throw ContractFailure(message: "pause-marker-timeout:\(stage):\(diagnostic)")
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
    try mutate()
    FileManager.default.createFile(atPath: release.path, contents: Data())

    while process.isRunning {
      guard Date() < deadline else {
        throw ContractFailure(message: "paused-process-timeout:\(stage)")
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    outputGroup.wait()
    errorGroup.wait()
    outputLock.lock()
    let capturedStdout = stdout
    outputLock.unlock()
    errorLock.lock()
    let capturedStderr = stderr
    errorLock.unlock()
    return ProcessResult(status: process.terminationStatus, stdout: capturedStdout, stderr: capturedStderr)
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
      var merged = ProcessInfo.processInfo.environment
      for (key, value) in environment { merged[key] = value }
      process.environment = merged
    }

    let outputGroup = DispatchGroup()
    let errorGroup = DispatchGroup()
    var stdout = Data()
    var stderr = Data()
    let outputLock = NSLock()
    let errorLock = NSLock()
    outputGroup.enter()
    DispatchQueue.global(qos: .utility).async {
      let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
      outputLock.lock()
      stdout = data
      outputLock.unlock()
      outputGroup.leave()
    }
    errorGroup.enter()
    DispatchQueue.global(qos: .utility).async {
      let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
      errorLock.lock()
      stderr = data
      errorLock.unlock()
      errorGroup.leave()
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
    outputGroup.wait()
    errorGroup.wait()
    outputLock.lock()
    let capturedStdout = stdout
    outputLock.unlock()
    errorLock.lock()
    let capturedStderr = stderr
    errorLock.unlock()
    return ProcessResult(status: process.terminationStatus, stdout: capturedStdout, stderr: capturedStderr)
  }

  private static func makeTemporaryDirectory(prefix: String) throws -> URL {
    let temporaryBase = NSTemporaryDirectory()
    guard let canonicalBase = realpath(temporaryBase, nil) else {
      throw ContractFailure(message: "temporary-root-canonicalization-failed")
    }
    defer { free(canonicalBase) }
    let directory = URL(fileURLWithPath: String(cString: canonicalBase), isDirectory: true)
      .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    return directory
  }

  private static func replaceFile(at path: URL, contents: Data) throws {
    let replacement = path.deletingLastPathComponent()
      .appendingPathComponent(".replacement-\(UUID().uuidString)")
    try contents.write(to: replacement, options: .atomic)
    guard replacement.path.withCString({ source in
      path.path.withCString { destination in Darwin.rename(source, destination) == 0 }
    }) else {
      throw ContractFailure(message: "replacement-rename-failed:\(path.lastPathComponent)")
    }
  }

  private static func replaceDirectory(at path: URL) throws {
    let moved = path.deletingLastPathComponent()
      .appendingPathComponent(".moved-\(UUID().uuidString)", isDirectory: true)
    guard path.path.withCString({ source in
      moved.path.withCString { destination in Darwin.rename(source, destination) == 0 }
    }) else {
      throw ContractFailure(message: "directory-replacement-rename-failed:\(path.lastPathComponent)")
    }
    try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)
  }

  private static func cloneSource(from source: URL, to destination: URL) throws {
    let result = try runProcess(
      executable: URL(fileURLWithPath: "/bin/cp"),
      arguments: ["-cR", source.path, destination.path],
      input: Data(),
      timeout: 180
    )
    try require(result.status == 0, "source-clone:\(string(result.stderr))")
  }

  private static func cloneRuntime(from source: URL, to destination: URL) throws {
    try cloneTree(source: source, destination: destination)
  }

  private static func cloneTree(source: URL, destination: URL) throws {
    if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: source.path) {
      try FileManager.default.createSymbolicLink(atPath: destination.path, withDestinationPath: target)
      return
    }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
      throw ContractFailure(message: "clone-source-missing:\(source.lastPathComponent)")
    }
    if isDirectory.boolValue {
      try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
      for name in try FileManager.default.contentsOfDirectory(atPath: source.path) {
        try cloneTree(source: source.appendingPathComponent(name), destination: destination.appendingPathComponent(name))
      }
    } else {
      try FileManager.default.linkItem(at: source, to: destination)
    }
  }

  private static func directEntries(of directory: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
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

  private static func format(_ value: Double?) -> String {
    guard let value else { return "unobserved" }
    return String(format: "%.1f", value)
  }

  private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw ContractFailure(message: message) }
  }
}

private let NemotronRecognizerModelFileName = "nemotron-3.5-asr-streaming-0.6b.q8_0.gguf"

private let fakeBlockedDecodeProcessSource = #"""
#include <signal.h>
#include <stdio.h>
#include <unistd.h>

static void ignore_term(int signal_number) { (void)signal_number; }
static void fake_native_decode(void) { usleep(20 * 1000); }

int main(void) {
    signal(SIGTERM, ignore_term);
    fputs("native-decode-entry\nnative-decode-in-flight\nnative-decode-blocked\n", stderr);
    fflush(stderr);
    fake_native_decode();
    fputs("native-decode-returned\n", stderr);
    fflush(stderr);
    for (;;) pause();
}
"""#

private let fakeLibrarySource = #"""
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "nemo_speech/asr.h"

struct nemo_speech_asr_recognizer { int marker; };
struct nemo_speech_asr_stream {
    size_t pushes;
    bool finished;
    bool pending;
    bool final_emitted;
    char pending_text[64];
};
struct nemo_speech_asr_result { bool is_final; char *text; };

static char *copy_text(const char *text) {
    size_t length = strlen(text) + 1;
    char *copy = (char *)malloc(length);
    if (copy != NULL) memcpy(copy, text, length);
    return copy;
}

NEMO_SPEECH_ASR_API nemo_speech_asr_status nemo_speech_asr_create(
    const nemo_speech_asr_recognizer_config *cfg,
    nemo_speech_asr_recognizer **out) {
    (void)cfg;
    if (out == NULL) return NEMO_SPEECH_ASR_ERROR_INVALID_ARGUMENT;
    *out = (nemo_speech_asr_recognizer *)calloc(1, sizeof(**out));
    return *out == NULL ? NEMO_SPEECH_ASR_ERROR_OUT_OF_MEMORY : NEMO_SPEECH_ASR_OK;
}

NEMO_SPEECH_ASR_API void nemo_speech_asr_destroy(nemo_speech_asr_recognizer *recognizer) {
    free(recognizer);
}

NEMO_SPEECH_ASR_API nemo_speech_asr_status nemo_speech_asr_streaming_recognize(
    nemo_speech_asr_recognizer *recognizer,
    const nemo_speech_asr_recognition_options *options,
    nemo_speech_asr_stream **out) {
    (void)recognizer;
    (void)options;
    if (out == NULL) return NEMO_SPEECH_ASR_ERROR_INVALID_ARGUMENT;
    *out = (nemo_speech_asr_stream *)calloc(1, sizeof(**out));
    return *out == NULL ? NEMO_SPEECH_ASR_ERROR_OUT_OF_MEMORY : NEMO_SPEECH_ASR_OK;
}

NEMO_SPEECH_ASR_API nemo_speech_asr_status nemo_speech_asr_stream_push_f32(
    nemo_speech_asr_stream *stream, const float *samples, size_t n_samples, int32_t sample_rate) {
    if (stream == NULL || samples == NULL || n_samples != 2560 || sample_rate != 16000)
        return NEMO_SPEECH_ASR_ERROR_INVALID_ARGUMENT;
    stream->pushes += 1;
    const char *mode = getenv("FLECK_FAKE_RESULTS");
    if (mode != NULL && strcmp(mode, "zero") != 0 &&
        (strcmp(mode, "one") != 0 || stream->pushes == 1)) {
        stream->pending = true;
        if (strcmp(mode, "one") == 0) {
            snprintf(stream->pending_text, sizeof(stream->pending_text), "one");
        } else {
            snprintf(stream->pending_text, sizeof(stream->pending_text), "partial-%zu", stream->pushes);
        }
    }
    return NEMO_SPEECH_ASR_OK;
}

NEMO_SPEECH_ASR_API nemo_speech_asr_status nemo_speech_asr_stream_finish(nemo_speech_asr_stream *stream) {
    if (stream == NULL) return NEMO_SPEECH_ASR_ERROR_INVALID_ARGUMENT;
    stream->finished = true;
    return NEMO_SPEECH_ASR_OK;
}

NEMO_SPEECH_ASR_API nemo_speech_asr_status nemo_speech_asr_stream_next(
    nemo_speech_asr_stream *stream, nemo_speech_asr_result **out) {
    if (stream == NULL || out == NULL) return NEMO_SPEECH_ASR_ERROR_INVALID_ARGUMENT;
    *out = NULL;
    if (stream->pending) {
        stream->pending = false;
        *out = (nemo_speech_asr_result *)calloc(1, sizeof(**out));
        if (*out == NULL) return NEMO_SPEECH_ASR_ERROR_OUT_OF_MEMORY;
        (*out)->text = copy_text(stream->pending_text);
        if ((*out)->text == NULL) { free(*out); *out = NULL; return NEMO_SPEECH_ASR_ERROR_OUT_OF_MEMORY; }
        return NEMO_SPEECH_ASR_OK;
    }
    if (stream->finished && !stream->final_emitted) {
        stream->final_emitted = true;
        *out = (nemo_speech_asr_result *)calloc(1, sizeof(**out));
        if (*out == NULL) return NEMO_SPEECH_ASR_ERROR_OUT_OF_MEMORY;
        (*out)->is_final = true;
        (*out)->text = copy_text("final");
        if ((*out)->text == NULL) { free(*out); *out = NULL; return NEMO_SPEECH_ASR_ERROR_OUT_OF_MEMORY; }
    }
    return NEMO_SPEECH_ASR_OK;
}

NEMO_SPEECH_ASR_API void nemo_speech_asr_stream_close(nemo_speech_asr_stream *stream) { free(stream); }
NEMO_SPEECH_ASR_API bool nemo_speech_asr_result_is_final(const nemo_speech_asr_result *result) { return result != NULL && result->is_final; }
NEMO_SPEECH_ASR_API const char *nemo_speech_asr_result_transcript(const nemo_speech_asr_result *result, size_t alt) { return result != NULL && alt == 0 ? result->text : NULL; }
NEMO_SPEECH_ASR_API void nemo_speech_asr_result_destroy(nemo_speech_asr_result *result) { if (result != NULL) { free(result->text); free(result); } }
NEMO_SPEECH_ASR_API const char *nemo_speech_asr_last_error(void) { return "fake-error"; }
NEMO_SPEECH_ASR_API const char *nemo_speech_asr_version(void) { return "fake-version"; }
"""#
