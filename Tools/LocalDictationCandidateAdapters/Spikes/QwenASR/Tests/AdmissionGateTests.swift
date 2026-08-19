import Foundation
import Darwin

@main
struct AdmissionGateTests {
  static func main() throws {
    testSherpaIsFinalOnlyAndCannotClaimUnsupportedCapabilities()
    testPinnedMetadataIncludesOfficialArchiveSizesAndUnknownInstalledIdentities()
    try testMalformedAndMismatchedIdentityIsRejected()
    try testPreflightRejectsUnadmittedAndForgedIdentitiesBeforeHelperLaunch()
    try testTenCasePlanUsesOnlySherpaFinalOnlyClaims()
    try testAdmissionProtocolSelfTestDeclaresNoFakeCancellation()
    try testStartupPathsAreAbsoluteContainedAndSymlinkSafe()
    try testContextIsBoundedAndDeterministic()
    try testWaveReaderAcceptsLocalPCM16AndRejectsWrongRate()
    print("qwen admission gate tests passed: 9")
  }

  private static func testSherpaIsFinalOnlyAndCannotClaimUnsupportedCapabilities() {
    expect(QwenASRRoute.allCases == [.sherpa], "only the sherpa route is in scope")
    let capabilities = QwenASRRoute.sherpa.capabilities
    expect(!capabilities.supportsTrueStreaming, "sherpa must not claim true streaming")
    expect(!capabilities.emitsRollingWindowPartials, "sherpa emits no partials")
    expect(capabilities.resultSemantics == "batch-final-only", "sherpa must be final-only")
    expect(!capabilities.supportsBoundedContext, "sherpa rejects per-request context")
    expect(!capabilities.supportsCancellation, "sherpa has no active-decode cancellation hook")
    expect(!capabilities.supportsLoadCancellation, "sherpa has no load cancellation hook")
    expect(!capabilities.supportsDecodeCancellation, "sherpa has no decode cancellation hook")
  }

  private static func testPinnedMetadataIncludesOfficialArchiveSizesAndUnknownInstalledIdentities() {
    let manifest = QwenASRArtifactManifests.sherpa
    expect(QwenASRArtifactManifests.all.count == 1, "only one Qwen route must be catalogued")
    expect(manifest.runtimeArchive.fileName == "sherpa-onnx-v1.13.4-macos-shared-onnxruntime-static.xcframework.zip", "runtime archive name drifted")
    expect(manifest.runtimeArchive.sha256 == "ef7daa86a1e5f5dcb0ccf53e4e475c3ae24414652c9ae9c3912a82140c86fb1a", "runtime archive digest drifted")
    expect(manifest.runtimeArchive.sizeBytes == 17_716_081, "runtime archive size drifted")
    expect(manifest.modelArchive.fileName == "sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25.tar.bz2", "model archive name drifted")
    expect(manifest.modelArchive.sha256 == "393f8a14e2f5fb96746aaab342997a40641001fbd5bf9592a080a8329178ee96", "model archive digest drifted")
    expect(manifest.modelArchive.sizeBytes == 878_702_423, "model archive size drifted")
    expect(manifest.runtimeMetadata.sourceCommit == "142807252687d81b40d6315f23470a1512a00de3", "runtime commit drifted")
    expect(manifest.runtimeMetadata.architecture == "arm64", "runtime architecture drifted")
    expect(manifest.runtimeMetadata.provider == "cpu", "runtime provider drifted")
    expect(manifest.runtimeMetadata.threadCount == 2, "runtime thread count drifted")
    expect(manifest.runtimeMetadata.cAPI == "sherpa-onnx C API", "runtime API drifted")
    expect(manifest.runtimeMetadata.abi == "arm64-apple-macosx13.0", "runtime ABI drifted")
    expect(manifest.modelMetadata.ownerRevision == "5eb144179a02acc5e5ba31e748d22b0cf3e303b0", "owner revision drifted")
    expect(manifest.modelMetadata.ownerModelFileSHA256 == "79d6cbd4c98c7bbffe9db2edac07f56cd6637d0d5944b27f6c2b8353840323ea", "owner provenance digest drifted")
    expect(manifest.artifacts.isEmpty, "unpacked identities must remain unknown")
    guard case .incomplete(let missing) = manifest.installedIdentityStatus else {
      fatalError("unpacked identities must be incomplete")
    }
    expect(missing == manifest.expectedRuntimePaths + manifest.expectedModelPaths, "missing identity list must be explicit")
    expectThrows(ArtifactAdmissionError.self) {
      try manifest.requireAdmitted()
    }
    var nativeLoadCalled = false
    expectThrows(ArtifactAdmissionError.self) {
      try manifest.withNativeLoad {
        nativeLoadCalled = true
      }
    }
    expect(!nativeLoadCalled, "incomplete identities must stop before native load")
  }

  private static func testMalformedAndMismatchedIdentityIsRejected() throws {
    expectThrows(ArtifactAdmissionError.self) {
      _ = try ArtifactIdentity(relativePath: "payload.bin", sha256: "not-a-sha256", size: 7)
    }
    expectThrows(ArtifactAdmissionError.self) {
      _ = try ArtifactIdentity(relativePath: "../payload.bin", sha256: String(repeating: "0", count: 64), size: 7)
    }
    expectThrows(ArtifactAdmissionError.self) {
      _ = try ArtifactIdentity(relativePath: "payload.bin", sha256: String(repeating: "0", count: 64), size: 0)
    }
    expectThrows(ArtifactAdmissionError.self) {
      _ = try QwenASRArchiveMetadata(
        fileName: "runtime.zip",
        url: "https" + ":" + "/" + "/example.invalid/runtime.zip",
        sha256: String(repeating: "0", count: 64),
        sizeBytes: 0
      )
    }
    let wrongRuntime = try QwenASRArchiveMetadata(
      fileName: QwenASRArtifactManifests.sherpa.runtimeArchive.fileName,
      url: QwenASRArtifactManifests.sherpa.runtimeArchive.url,
      sha256: QwenASRArtifactManifests.sherpa.runtimeArchive.sha256,
      sizeBytes: QwenASRArtifactManifests.sherpa.runtimeArchive.sizeBytes + 1
    )
    expectThrows(ArtifactAdmissionError.self) {
      try wrongRuntime.requireMatches(QwenASRArtifactManifests.sherpa.runtimeArchive)
    }

    let forgedIdentities = try (
      QwenASRArtifactManifests.sherpa.expectedRuntimePaths
        + QwenASRArtifactManifests.sherpa.expectedModelPaths
    ).map {
      try ArtifactIdentity(relativePath: $0, sha256: String(repeating: "0", count: 64), size: 1)
    }
    expect(forgedIdentities.count == QwenASRArtifactManifests.sherpa.expectedRuntimePaths.count
      + QwenASRArtifactManifests.sherpa.expectedModelPaths.count,
      "forged identities should cover the expected paths only in the test")
    expect(QwenASRArtifactManifests.sherpa.artifacts.isEmpty, "caller identities must not enter the current manifest")
    var nativeLoadCalled = false
    expectThrows(ArtifactAdmissionError.self) {
      try QwenASRArtifactManifests.sherpa.withNativeLoad {
        nativeLoadCalled = true
      }
    }
    expect(!nativeLoadCalled, "forged complete paths and hashes must not enable native load")
  }

  private static func testPreflightRejectsUnadmittedAndForgedIdentitiesBeforeHelperLaunch() throws {
    let descriptor = QwenASRHelperDescriptor(executablePath: "/future/qwen-sherpa-helper")
    var helperLaunchCount = 0
    expectThrows(ArtifactAdmissionError.self) {
      try QwenASRPreflight.launchIfAdmitted(
        manifest: QwenASRArtifactManifests.sherpa,
        descriptor: descriptor
      ) { _ in
        helperLaunchCount += 1
      }
    }
    expect(helperLaunchCount == 0, "unadmitted preflight must not invoke the helper probe")

    let forgedIdentities = try (
      QwenASRArtifactManifests.sherpa.expectedRuntimePaths
        + QwenASRArtifactManifests.sherpa.expectedModelPaths
    ).map {
      try ArtifactIdentity(relativePath: $0, sha256: String(repeating: "f", count: 64), size: 1)
    }
    expect(forgedIdentities.count == QwenASRArtifactManifests.sherpa.expectedRuntimePaths.count
      + QwenASRArtifactManifests.sherpa.expectedModelPaths.count,
      "forged identities must cover every expected path in the probe")
    expect(QwenASRArtifactManifests.sherpa.artifacts.isEmpty, "forged identities must not mutate the catalog")
    expectThrows(ArtifactAdmissionError.self) {
      try QwenASRPreflight.launchIfAdmitted(
        manifest: QwenASRArtifactManifests.sherpa,
        descriptor: descriptor
      ) { _ in
        helperLaunchCount += 1
      }
    }
    expect(helperLaunchCount == 0, "forged identities must not invoke the helper probe")
  }

  private static func testTenCasePlanUsesOnlySherpaFinalOnlyClaims() throws {
    let planURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Cases/ten-case-plan.jsonl")
    let lines = try String(contentsOf: planURL, encoding: .utf8)
      .split(whereSeparator: \.isNewline)
    expect(lines.count == 10, "ten-case plan must contain ten cases")
    var records = [[String: Any]]()
    for line in lines {
      guard let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
        fatalError("ten-case plan record must be a JSON object")
      }
      records.append(object)
      let routeCapabilities = object["routeCapabilities"] as? [String: Any]
      expect(routeCapabilities?.count == 1, "case plan must not declare another route")
      let capabilities = routeCapabilities?["sherpa"] as? [String: Any]
      expect(capabilities?["resultSemantics"] as? String == "batch-final-only", "sherpa must declare batch-final-only")
      expect(capabilities?["claimsRollingWindowPartials"] as? Bool == false, "sherpa must not claim rolling-window partials")
      expect(object["evaluationOnlyContextPhrases"] is [Any], "context phrases must be evaluation metadata")
      expect((object["appliedContextPhrases"] as? [Any])?.isEmpty == true, "context phrases must not be applied")
      expect(object["contextPhrases"] == nil, "ambiguous applied context phrases must be removed")
      expect(object["claimsPartials"] == nil, "ambiguous claimsPartials must be removed")
    }

    let cancellationRecords = records.filter { ($0["id"] as? String) == "cancellation-active-decode" }
    expect(cancellationRecords.count == 1, "plan must contain exactly one cancellation declaration")
    let cancellationDeclarations = records.filter {
      $0["cancellationPoint"] != nil || $0["cancellationClaim"] != nil
    }
    expect(cancellationDeclarations.count == 1, "plan must not contain stale cancellation declarations")
    let cancellation = cancellationRecords[0]
    expect(cancellation["cancellationPoint"] as? String == "during-active-decode", "cancellation point must be active decode")
    expect(cancellation["cancellationClaim"] as? String == "unsupported-by-batch-routes", "cancellation must remain unsupported")
  }

  private static func testAdmissionProtocolSelfTestDeclaresNoFakeCancellation() throws {
    let protocolURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("run-admission-protocol.sh")
    let source = try String(contentsOf: protocolURL, encoding: .utf8)
    expect(source.contains("--self-test"), "admission protocol must expose a self-test")
    expect(source.contains("unsupported-active-cancellation-refused"), "self-test must name cancellation refusal")
    expect(!source.contains("emit_cancel"), "protocol must not send sequential fake cancellation")
  }

  private static func testStartupPathsAreAbsoluteContainedAndSymlinkSafe() throws {
    let temporary = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("qwen-admission-gate-tests-\(UUID().uuidString)", isDirectory: true)
    let outside = temporary.deletingLastPathComponent()
      .appendingPathComponent("qwen-admission-gate-outside-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    defer {
      try? FileManager.default.removeItem(at: temporary)
      try? FileManager.default.removeItem(at: outside)
    }

    _ = try StartupPathPolicy.requireLocalDirectory(temporary.path, field: "model-root")
    let marker = temporary.appendingPathComponent("marker.txt")
    try Data("marker".utf8).write(to: marker)
    _ = try StartupPathPolicy.requireContainedFile(marker.path, within: temporary, field: "model-file")
    let outsideMarker = outside.appendingPathComponent("outside.txt")
    try Data("outside".utf8).write(to: outsideMarker)
    let escape = temporary.appendingPathComponent("escape.txt")
    try FileManager.default.createSymbolicLink(at: escape, withDestinationURL: outsideMarker)
    expectThrows(StartupPathError.self) {
      _ = try StartupPathPolicy.requireContainedFile(escape.path, within: temporary, field: "model-file")
    }
    let rootEscape = temporary.appendingPathComponent("root-escape", isDirectory: true)
    try FileManager.default.createSymbolicLink(at: rootEscape, withDestinationURL: outside)
    expectThrows(StartupPathError.self) {
      _ = try StartupPathPolicy.requireLocalDirectory(rootEscape.path, field: "model-root")
    }
    expectThrows(StartupPathError.self) {
      _ = try StartupPathPolicy.requireLocalDirectory("relative/model", field: "model-root")
    }
    expectThrows(StartupPathError.self) {
      _ = try StartupPathPolicy.requireLocalDirectory(
        "https" + ":" + "/" + "/example.invalid/model",
        field: "model-root"
      )
    }
    expectThrows(StartupPathError.self) {
      _ = try StartupPathPolicy.requireContainedFile("/tmp/outside-model-file", within: temporary, field: "model-file")
    }

    let fifo = temporary.appendingPathComponent("not-a-regular-file")
    expect(Darwin.mkfifo(fifo.path, mode_t(S_IRUSR | S_IWUSR)) == 0, "fifo fixture must be created")
    var fifoRejected = false
    do {
      _ = try StartupPathPolicy.requireContainedFile(fifo.path, within: temporary, field: "model-file")
    } catch let error as StartupPathError {
      fifoRejected = error == .notRegularFile("model-file")
    }
    expect(fifoRejected, "FIFO must be rejected as a non-regular file")
  }

  private static func testContextIsBoundedAndDeterministic() throws {
    let hotwords = try BoundedContext.hotwordArgument(["Fleck", "SwiftUI"])
    expect(hotwords == "Fleck,SwiftUI", "context order must be stable")
    expectThrows(BoundedContextError.self) {
      _ = try BoundedContext.hotwordArgument(Array(repeating: "term", count: 101))
    }
    expectThrows(BoundedContextError.self) {
      _ = try BoundedContext.hotwordArgument(["Fleck", "Fleck"])
    }
  }

  private static func testWaveReaderAcceptsLocalPCM16AndRejectsWrongRate() throws {
    let temporary = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("qwen-admission-wave-tests-\(UUID().uuidString).wav")
    try makePCM16Wave(at: temporary, sampleRate: 16_000, samples: [0, 16_384, -16_384])
    defer { try? FileManager.default.removeItem(at: temporary) }

    let wave = try WaveReader.read(temporary, expectedSampleRate: 16_000)
    expect(wave.sampleRate == 16_000, "wave reader must preserve sample rate")
    expect(wave.samples.count == 3, "wave reader must decode every mono sample")
    expect(abs(wave.samples[1] - 0.5) < 0.0001, "wave reader must normalize PCM16")
    expectThrows(WaveReaderError.self) {
      _ = try WaveReader.read(temporary, expectedSampleRate: 8_000)
    }
  }

  private static func makePCM16Wave(at url: URL, sampleRate: Int, samples: [Int16]) throws {
    var data = Data()
    data.append(contentsOf: Array("RIFF".utf8))
    appendUInt32LE(&data, UInt32(36 + samples.count * 2))
    data.append(contentsOf: Array("WAVE".utf8))
    data.append(contentsOf: Array("fmt ".utf8))
    appendUInt32LE(&data, 16)
    appendUInt16LE(&data, 1)
    appendUInt16LE(&data, 1)
    appendUInt32LE(&data, UInt32(sampleRate))
    appendUInt32LE(&data, UInt32(sampleRate * 2))
    appendUInt16LE(&data, 2)
    appendUInt16LE(&data, 16)
    data.append(contentsOf: Array("data".utf8))
    appendUInt32LE(&data, UInt32(samples.count * 2))
    for sample in samples {
      appendUInt16LE(&data, UInt16(bitPattern: sample))
    }
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

  private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
  }

  private static func expectThrows<E: Error>(_ type: E.Type, _ body: () throws -> Void) {
    do {
      try body()
      fatalError("expected \(type) to be thrown")
    } catch is E {
      return
    } catch {
      fatalError("expected \(type), got \(error)")
    }
  }
}
