import CryptoKit
import Darwin
import Foundation

#if !arch(arm64)
#error("Nemotron native evaluation requires macOS arm64")
#endif

private struct ExpectedRuntimeFile: Equatable {
  let path: String
  let size: Int64
  let sha256: String
}

private struct ExpectedRuntimeSymlink: Equatable {
  let path: String
  let target: String
}

private struct RuntimeSnapshot {
  var files: [String: URL] = [:]
  var symlinks: [String: String] = [:]
  let root: URL
  let library: URL
}

private struct FileObjectIdentity: Equatable {
  let device: UInt64
  let inode: UInt64
  let mode: UInt32
  let size: Int64
}

private struct VerifiedDescriptor {
  let path: URL
  let fd: Int32
  let identity: FileObjectIdentity
}

// Descriptor-backed immutable snapshots reverify after each native use.

struct NemotronTranscriptionResult {
  let transcript: String
  let partialCount: Int
  let requestToFirstPartialMs: Double?
  let feedCadenceMs: Double?
  let feedEndToFinalMs: Double
}

enum NemotronRecognizerError: Error, CustomStringConvertible {
  case invalidPath(String)
  case modelIdentityMismatch
  case sourceIdentityMismatch
  case runtimeIdentityMismatch
  case nativeRuntimeUnavailable
  case nativeRecognizerUnavailable
  case nativeStreamUnavailable
  case nativeCallFailed(String)
  case invalidAudio
  case audioTooLarge
  case unsupportedAudioFormat
  case audioHasNoSamples
  case unsupportedLocale
  case transcriptTooLarge
  case transcriptContainsControlCharacter
  case midStreamFinal
  case missingFinal
  case multipleFinals

  var code: String {
    switch self {
    case .invalidPath(let kind): return "invalid-\(kind)-path"
    case .modelIdentityMismatch: return "model-identity-mismatch"
    case .sourceIdentityMismatch: return "source-identity-mismatch"
    case .runtimeIdentityMismatch: return "runtime-identity-mismatch"
    case .nativeRuntimeUnavailable: return "native-runtime-unavailable"
    case .nativeRecognizerUnavailable: return "native-recognizer-unavailable"
    case .nativeStreamUnavailable: return "native-stream-unavailable"
    case .nativeCallFailed(let operation): return "native-call-failed-\(operation)"
    case .invalidAudio: return "invalid-audio"
    case .audioTooLarge: return "audio-too-large"
    case .unsupportedAudioFormat: return "unsupported-audio-format"
    case .audioHasNoSamples: return "audio-has-no-samples"
    case .unsupportedLocale: return "unsupported-locale"
    case .transcriptTooLarge: return "transcript-too-large"
    case .transcriptContainsControlCharacter: return "transcript-contains-control-character"
    case .midStreamFinal: return "mid-stream-final"
    case .missingFinal: return "missing-final"
    case .multipleFinals: return "multiple-finals"
    }
  }

  var description: String { code }
}

final class NemotronRecognizer {
  static let runtimeVersion = "nemo-speech-asr 1.0.0"
  static let modelRevision = "1c8deaecc64b91f034d73e08dd8b64625eb3395d"
  static let modelFileName = "nemotron-3.5-asr-streaming-0.6b.q8_0.gguf"
  static let modelSHA256 = "a5c435f294eea8f88ce68dd27b8c3bfea7f777cb2fbba04fcd30eaa555f429ae"
  static let modelSize: Int64 = 741_548_352
  static let sourceCommit = "5be7bfb104802131e61fe679b3f1401b27270216"
  static let chunkSamples = 2_560
  static let chunkNanoseconds: UInt64 = 160_000_000
  static let maximumWAVBytes = 128 * 1_024 * 1_024
  static let maximumSamples = 16_000 * 10 * 60
  static let maximumTranscriptBytes = 65_536

  private static let expectedSubmodules: [String: String] = [
    "ggml": "c03b4e2bcece5134827881af90242086daf75be5",
    "llama.cpp": "560445bf34c87356ad0f8d80fb03ec5488850b65",
    "proto/riva-common": "71df98266725320a6b6b3a9f32a6da832dc93691",
    "third_party/cpp-httplib": "62d899feac3cf9215a55f2b43da250fdd98d2156",
    "third_party/cppjieba": "b3602bef7d1f67521a61788a74fb5801a0e62cd3",
    "third_party/cppjieba/deps/limonp": "9d74077dfcdf8073536c97a00bb79d7a3c3fdaba",
    "third_party/flashlight-text": "49e163ab1e7b8108922512c294ab8513b89f404c",
    "third_party/kenlm": "4cb443e60b7bf2c0ddf3c745378f76cb59e254e5",
    "third_party/open_jtalk": "1e52154e6677d02dcb4b7f15453e65b5ca1cb6aa",
  ]

  private static let expectedRuntimeFiles: [ExpectedRuntimeFile] = [
    ExpectedRuntimeFile(
      path: "libggml-base.0.12.0.dylib", size: 705_448,
      sha256: "f825adbdbdd1745636fda09a871cb002d59427629f42a9bfdc09418ef4063dcf"),
    ExpectedRuntimeFile(
      path: "libggml-blas.0.12.0.dylib", size: 58_776,
      sha256: "1b0c7cfd6d4d2c7562846f3ce1c3f1d45018b8469779debdc2b6070b035be12b"),
    ExpectedRuntimeFile(
      path: "libggml-cpu.0.12.0.dylib", size: 845_712,
      sha256: "5ab19ec0d8cc775a15330121e4f354ebce67d77bc0bfb913982b557eff08fc1c"),
    ExpectedRuntimeFile(
      path: "libggml-metal.0.12.0.dylib", size: 832_280,
      sha256: "b8228101985dbf9e54311b4363596d77acfb4ce5d042124d2032e91ba5a119f0"),
    ExpectedRuntimeFile(
      path: "libggml.0.12.0.dylib", size: 59_808,
      sha256: "6a6705c44b9419cfa419eda03de830d4dfca1e2d20a7f465201a1246a87dd329"),
    ExpectedRuntimeFile(
      path: "libnemo_speech_asr.dylib", size: 2_070_312,
      sha256: "6a21cae0e7b6a99b8927978aef49df93a5bcfd5d540800ee5007ecea76a7acb5"),
    ExpectedRuntimeFile(
      path: "libnemo_speech_asr_c.1.dylib", size: 96_032,
      sha256: "d01ce228946526ca1a0aa6d90cbcbdc63ba047e5f755947ee5aa180bde0db4e4"),
    ExpectedRuntimeFile(
      path: "nemo-speech", size: 364_280,
      sha256: "e995d84e2b6ea7a25b1fc2edf36dc908680687ebf4a0de207d386b54ad78f8b3"),
  ]

  private static let expectedRuntimeSymlinks: [ExpectedRuntimeSymlink] = [
    ExpectedRuntimeSymlink(path: "libggml-base.0.dylib", target: "libggml-base.0.12.0.dylib"),
    ExpectedRuntimeSymlink(path: "libggml-base.dylib", target: "libggml-base.0.dylib"),
    ExpectedRuntimeSymlink(path: "libggml-blas.0.dylib", target: "libggml-blas.0.12.0.dylib"),
    ExpectedRuntimeSymlink(path: "libggml-blas.dylib", target: "libggml-blas.0.dylib"),
    ExpectedRuntimeSymlink(path: "libggml-cpu.0.dylib", target: "libggml-cpu.0.12.0.dylib"),
    ExpectedRuntimeSymlink(path: "libggml-cpu.dylib", target: "libggml-cpu.0.dylib"),
    ExpectedRuntimeSymlink(path: "libggml-metal.0.dylib", target: "libggml-metal.0.12.0.dylib"),
    ExpectedRuntimeSymlink(path: "libggml-metal.dylib", target: "libggml-metal.0.dylib"),
    ExpectedRuntimeSymlink(path: "libggml.0.dylib", target: "libggml.0.12.0.dylib"),
    ExpectedRuntimeSymlink(path: "libggml.dylib", target: "libggml.0.dylib"),
    ExpectedRuntimeSymlink(path: "libnemo_speech_asr_c.dylib", target: "libnemo_speech_asr_c.1.dylib"),
  ]

  private var symbolTable: UnsafeMutableRawPointer?
  private var recognizer: UnsafeMutableRawPointer?
  private let snapshotRoot: URL
  private let runtimeSnapshotRoot: URL

  private init(
    symbolTable: UnsafeMutableRawPointer,
    recognizer: UnsafeMutableRawPointer,
    snapshotRoot: URL,
    runtimeSnapshotRoot: URL
  ) {
    self.symbolTable = symbolTable
    self.recognizer = recognizer
    self.snapshotRoot = snapshotRoot
    self.runtimeSnapshotRoot = runtimeSnapshotRoot
  }

  static func load(modelPath: String, runtimePath: String, sourcePath: String) throws -> NemotronRecognizer {
    let snapshotRoot = try makeSnapshotDirectory(prefix: "nemotron-load")
    var table: UnsafeMutableRawPointer?
    do {
      let modelDescriptor = try openRegularFile(modelPath, kind: "model")
      defer { Darwin.close(modelDescriptor.fd) }
      guard modelDescriptor.path.lastPathComponent == modelFileName else {
        throw NemotronRecognizerError.modelIdentityMismatch
      }
      let modelIdentity = try descriptorIdentity(modelDescriptor.fd, kind: "model")
      guard modelIdentity.0.size == modelSize, modelIdentity.1 == modelSHA256 else {
        throw NemotronRecognizerError.modelIdentityMismatch
      }
      testPause(stage: "after-model-descriptor")
      let modelSnapshot = try snapshotFile(
        descriptor: modelDescriptor,
        destination: snapshotRoot.appendingPathComponent(modelFileName),
        expectedSize: modelSize,
        expectedSHA256: modelSHA256,
        kind: "model"
      )

      let sourceDescriptor = try openDirectory(sourcePath, kind: "source")
      defer { Darwin.close(sourceDescriptor.fd) }
      try verifySourceIdentity(at: sourceDescriptor.path, descriptor: sourceDescriptor)
      testPause(stage: "after-source-identity")

      let runtimeDescriptor = try openDirectory(runtimePath, kind: "runtime")
      defer { Darwin.close(runtimeDescriptor.fd) }
      let runtimeSnapshot = try verifyRuntimeIdentity(
        at: runtimeDescriptor.path,
        descriptor: runtimeDescriptor,
        snapshotRoot: snapshotRoot.appendingPathComponent("runtime", isDirectory: true)
      )
      testPause(stage: "after-runtime-snapshot")

      try verifySnapshotFile(
        modelSnapshot,
        expectedSize: modelSize,
        expectedSHA256: modelSHA256,
        kind: "model"
      )
      try verifyRuntimeSnapshot(runtimeSnapshot)
      guard let openedTable = runtimeSnapshot.library.path.withCString({ libraryPath in
        runtimeSnapshot.root.path.withCString { snapshotPath in
          FleckNemoOpenRuntimeVerified(libraryPath, snapshotPath)
        }
      }) else {
        throw NemotronRecognizerError.nativeRuntimeUnavailable
      }
      table = openedTable
      guard runtimeSnapshot.root.path.withCString({
        FleckNemoVerifyRuntimeProvenance(openedTable, $0)
      }) != 0 else {
        throw NemotronRecognizerError.runtimeIdentityMismatch
      }
      Self.writeDiagnostic("runtime-provenance=private-snapshot")
      guard let nativeRecognizer = modelSnapshot.path.withCString({
        FleckNemoCreateRecognizer(openedTable, $0, 0)
      }) else {
        throw NemotronRecognizerError.nativeRecognizerUnavailable
      }
      guard runtimeSnapshot.root.path.withCString({
        FleckNemoVerifyRuntimeProvenance(openedTable, $0)
      }) != 0 else {
        FleckNemoDestroyRecognizer(openedTable, nativeRecognizer)
        throw NemotronRecognizerError.runtimeIdentityMismatch
      }
      try verifySnapshotFile(
        modelSnapshot,
        expectedSize: modelSize,
        expectedSHA256: modelSHA256,
        kind: "model"
      )
      try verifyRuntimeSnapshot(runtimeSnapshot)
      try verifySourceIdentity(at: sourceDescriptor.path, descriptor: sourceDescriptor)
      return NemotronRecognizer(
        symbolTable: openedTable,
        recognizer: nativeRecognizer,
        snapshotRoot: snapshotRoot,
        runtimeSnapshotRoot: runtimeSnapshot.root
      )
    } catch {
      if let table { FleckNemoCloseVerified(table) }
      try? FileManager.default.removeItem(at: snapshotRoot)
      throw error
    }
  }

  func transcribe(
    requestID: String,
    audioPath: String,
    localeIdentifier: String,
    blockBeforeDecode: Bool,
    onPartial: (Int, String) throws -> Void
  ) throws -> NemotronTranscriptionResult {
    guard let symbolTable, let recognizer else {
      throw NemotronRecognizerError.nativeRecognizerUnavailable
    }
    let requestStarted = DispatchTime.now().uptimeNanoseconds
    let audioDescriptor = try Self.openRegularFile(audioPath, kind: "audio")
    defer { Darwin.close(audioDescriptor.fd) }
    let audioIdentity = try Self.descriptorIdentity(audioDescriptor.fd, kind: "audio")
    guard audioIdentity.0.size > 0, audioIdentity.0.size <= Int64(Self.maximumWAVBytes) else {
      throw NemotronRecognizerError.audioTooLarge
    }
    let audioSnapshotRoot = try Self.makeSnapshotDirectory(prefix: "nemotron-audio")
    defer { try? FileManager.default.removeItem(at: audioSnapshotRoot) }
    Self.testPause(stage: "after-audio-descriptor")
    let audioSnapshot = try Self.snapshotFile(
      descriptor: audioDescriptor,
      destination: audioSnapshotRoot.appendingPathComponent("input.wav"),
      expectedSize: audioIdentity.0.size,
      expectedSHA256: audioIdentity.1,
      kind: "audio"
    )
    try Self.verifySnapshotFile(
      audioSnapshot,
      expectedSize: audioIdentity.0.size,
      expectedSHA256: audioIdentity.1,
      kind: "audio"
    )
    let audio = try Self.readAudio(audioSnapshot, expectedIdentity: audioIdentity)
    let languageCode = Self.nativeLanguageCode(localeIdentifier)
    guard runtimeSnapshotRoot.path.withCString({
      FleckNemoVerifyRuntimeProvenance(symbolTable, $0)
    }) != 0 else {
      throw NemotronRecognizerError.runtimeIdentityMismatch
    }

    let stream: UnsafeMutableRawPointer? = requestID.withCString { requestCString in
      if let languageCode {
        return languageCode.withCString { languageCString in
          FleckNemoCreateStream(symbolTable, recognizer, requestCString, languageCString)
        }
      }
      return FleckNemoCreateStream(symbolTable, recognizer, requestCString, nil)
    }
    guard let stream else { throw NemotronRecognizerError.nativeStreamUnavailable }
    var streamClosed = false
    defer {
      if !streamClosed { FleckNemoCloseStream(symbolTable, stream) }
    }
    guard runtimeSnapshotRoot.path.withCString({
      FleckNemoVerifyRuntimeProvenance(symbolTable, $0)
    }) != 0 else {
      throw NemotronRecognizerError.runtimeIdentityMismatch
    }

    var lastPartial = ""
    var partialCount = 0
    var nextPartialSequence = 0
    var firstPartialAt: UInt64?
    var finalCount = 0
    var finalTranscript: String?
    var finalObservedAt: UInt64?

    func drain(afterFeedEnd: Bool) throws {
      while true {
        var result: UnsafeMutableRawPointer?
        let status = FleckNemoNext(symbolTable, stream, &result)
        guard status == 0 else { throw NemotronRecognizerError.nativeCallFailed("stream-next") }
        guard let result else { return }
        defer { FleckNemoDestroyResult(symbolTable, result) }

        let transcript = try Self.nativeTranscript(symbolTable: symbolTable, result: result)
        if FleckNemoIsFinal(symbolTable, result) != 0 {
          guard afterFeedEnd else { throw NemotronRecognizerError.midStreamFinal }
          finalCount += 1
          guard finalCount == 1 else { throw NemotronRecognizerError.multipleFinals }
          finalTranscript = transcript
          finalObservedAt = DispatchTime.now().uptimeNanoseconds
        } else if !transcript.isEmpty, transcript != lastPartial {
          lastPartial = transcript
          if firstPartialAt == nil {
            firstPartialAt = DispatchTime.now().uptimeNanoseconds
          }
          let sequence = nextPartialSequence
          nextPartialSequence += 1
          partialCount += 1
          try onPartial(sequence, transcript)
        }
      }
    }

    let feedStarted = DispatchTime.now().uptimeNanoseconds
    var nextFeedDeadline = feedStarted
    var offset = 0
    var feedCount = 0
    var blocked = false
    while offset < audio.samples.count {
      Self.sleepUntil(nextFeedDeadline)
      let end = min(offset + Self.chunkSamples, audio.samples.count)
      let count = end - offset
      let status = audio.samples.withUnsafeBufferPointer { samples in
        FleckNemoPush(symbolTable, stream, samples.baseAddress!.advanced(by: offset), count, 16_000)
      }
      guard status == 0 else { throw NemotronRecognizerError.nativeCallFailed("stream-push") }
      offset = end
      feedCount += 1
      nextFeedDeadline += Self.chunkNanoseconds
      if blockBeforeDecode, !blocked {
        blocked = true
        let decodeEntered = DispatchSemaphore(value: 0)
        let decodeReturned = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
          Self.writeDiagnostic("native-decode-entry")
          decodeEntered.signal()
          var result: UnsafeMutableRawPointer?
          _ = FleckNemoNext(symbolTable, stream, &result)
          if let result {
            FleckNemoDestroyResult(symbolTable, result)
          }
          Self.writeDiagnostic("native-decode-returned")
          decodeReturned.signal()
        }
        decodeEntered.wait()
        guard decodeReturned.wait(timeout: .now() + 0.001) == .timedOut else {
          throw NemotronRecognizerError.nativeCallFailed("decode-probe-returned-before-marker")
        }
        Self.writeDiagnostic("native-decode-in-flight")
        Self.writeDiagnostic("native-decode-blocked")
        while true { _ = Darwin.pause() }
      }
      try drain(afterFeedEnd: false)
    }

    let feedEndedAt = DispatchTime.now().uptimeNanoseconds
    let finishStatus = FleckNemoFinish(symbolTable, stream)
    guard finishStatus == 0 else { throw NemotronRecognizerError.nativeCallFailed("stream-finish") }
    try drain(afterFeedEnd: true)
    guard finalCount == 1, let finalTranscript, let finalObservedAt else {
      throw NemotronRecognizerError.missingFinal
    }
    FleckNemoCloseStream(symbolTable, stream)
    streamClosed = true
    guard runtimeSnapshotRoot.path.withCString({
      FleckNemoVerifyRuntimeProvenance(symbolTable, $0)
    }) != 0 else {
      throw NemotronRecognizerError.runtimeIdentityMismatch
    }
    Self.writeDiagnostic("runtime-provenance=private-snapshot-after-use")

    let firstPartialMs = firstPartialAt.map {
      Double($0 - requestStarted) / 1_000_000
    }
    let feedCadenceMs = feedCount > 1
      ? Double(feedEndedAt - feedStarted) / Double(feedCount - 1) / 1_000_000
      : nil
    let feedEndToFinalMs = Double(finalObservedAt - feedEndedAt) / 1_000_000
    return NemotronTranscriptionResult(
      transcript: finalTranscript,
      partialCount: partialCount,
      requestToFirstPartialMs: firstPartialMs,
      feedCadenceMs: feedCadenceMs,
      feedEndToFinalMs: feedEndToFinalMs
    )
  }

  func close() {
    if let symbolTable {
      if let recognizer {
        FleckNemoDestroyRecognizer(symbolTable, recognizer)
      }
      FleckNemoCloseVerified(symbolTable)
      self.symbolTable = nil
    }
    recognizer = nil
    try? FileManager.default.removeItem(at: snapshotRoot)
  }

  deinit { close() }
}

private extension NemotronRecognizer {
  static func openDirectory(_ rawPath: String, kind: String) throws -> VerifiedDescriptor {
    try openDescriptor(rawPath, kind: kind, directory: true)
  }

  static func openRegularFile(_ rawPath: String, kind: String) throws -> VerifiedDescriptor {
    try openDescriptor(rawPath, kind: kind, directory: false)
  }

  static func openDescriptor(_ rawPath: String, kind: String, directory: Bool) throws -> VerifiedDescriptor {
    guard isSafeAbsolutePath(rawPath) else {
      throw NemotronRecognizerError.invalidPath(kind)
    }
    guard let canonical = realpath(rawPath, nil) else {
      throw NemotronRecognizerError.invalidPath(kind)
    }
    let canonicalPath = String(cString: canonical)
    free(canonical)
    guard canonicalPath == rawPath else { throw NemotronRecognizerError.invalidPath(kind) }
    let lexical = URL(fileURLWithPath: rawPath, isDirectory: directory)
    var pathStat = stat()
    guard Darwin.lstat(lexical.path, &pathStat) == 0 else {
      throw NemotronRecognizerError.invalidPath(kind)
    }
    let pathIdentity = objectIdentity(pathStat)
    let expectedMode = directory ? UInt32(S_IFDIR) : UInt32(S_IFREG)
    guard pathIdentity.mode & UInt32(S_IFMT) == expectedMode else {
      throw NemotronRecognizerError.invalidPath(kind)
    }
    let flags = O_RDONLY | O_CLOEXEC | O_NOFOLLOW | (directory ? O_DIRECTORY : 0)
    let fd = Darwin.open(lexical.path, flags, 0)
    guard fd >= 0 else { throw NemotronRecognizerError.invalidPath(kind) }
    var descriptorStat = stat()
    guard Darwin.fstat(fd, &descriptorStat) == 0 else {
      Darwin.close(fd)
      throw NemotronRecognizerError.invalidPath(kind)
    }
    let descriptorIdentity = objectIdentity(descriptorStat)
    guard sameObject(pathIdentity, descriptorIdentity),
      descriptorIdentity.mode & UInt32(S_IFMT) == expectedMode else {
      Darwin.close(fd)
      throw NemotronRecognizerError.invalidPath(kind)
    }
    return VerifiedDescriptor(path: lexical, fd: fd, identity: descriptorIdentity)
  }

  static func isSafeAbsolutePath(_ path: String) -> Bool {
    guard path.first == "/", !path.contains("://"), !path.contains("\0"),
      !path.contains("\n"), !path.contains("\r") else { return false }
    let components = path.split(separator: "/", omittingEmptySubsequences: false)
    return !components.contains { component in
      component.isEmpty && component != components.first || component == "." || component == ".."
    }
  }

  static func isSafeRelativePath(_ path: String) -> Bool {
    guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("://") else { return false }
    let components = path.split(separator: "/", omittingEmptySubsequences: false)
    return !components.contains { $0.isEmpty || $0 == "." || $0 == ".." }
  }

  static func verifyRuntimeIdentity(
    at root: URL,
    descriptor: VerifiedDescriptor,
    snapshotRoot: URL
  ) throws -> RuntimeSnapshot {
    let expectedFiles = Dictionary(uniqueKeysWithValues: expectedRuntimeFiles.map { ($0.path, $0) })
    let expectedSymlinks = Dictionary(uniqueKeysWithValues: expectedRuntimeSymlinks.map { ($0.path, $0.target) })
    guard expectedFiles.count == expectedRuntimeFiles.count,
      expectedSymlinks.count == expectedRuntimeSymlinks.count else {
      throw NemotronRecognizerError.runtimeIdentityMismatch
    }

    try ensureDescriptorMatchesPath(descriptor, kind: "runtime")
    try FileManager.default.createDirectory(
      at: snapshotRoot,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: NSNumber(value: 0o700)]
    )
    var snapshot = RuntimeSnapshot(
      root: snapshotRoot,
      library: snapshotRoot.appendingPathComponent("libnemo_speech_asr_c.1.dylib")
    )
    try walk(root, relativeDirectory: "", into: &snapshot)
    guard Set(snapshot.files.keys) == Set(expectedFiles.keys),
      Set(snapshot.symlinks.keys) == Set(expectedSymlinks.keys) else {
      throw NemotronRecognizerError.runtimeIdentityMismatch
    }

    var totalBytes: Int64 = 0
    for (path, expected) in expectedFiles {
      guard let url = snapshot.files[path] else {
        throw NemotronRecognizerError.runtimeIdentityMismatch
      }
      let fileDescriptor = try openRegularFile(url.path, kind: "runtime")
      defer { Darwin.close(fileDescriptor.fd) }
      let identity = try descriptorIdentity(fileDescriptor.fd, kind: "runtime")
      guard identity.0.size == expected.size, identity.1 == expected.sha256 else {
        throw NemotronRecognizerError.runtimeIdentityMismatch
      }
      snapshot.files[path] = try snapshotFile(
        descriptor: fileDescriptor,
        destination: snapshotRoot.appendingPathComponent(path),
        expectedSize: expected.size,
        expectedSHA256: expected.sha256,
        kind: "runtime"
      )
      totalBytes += expected.size
    }
    for (path, target) in expectedSymlinks {
      guard snapshot.symlinks[path] == target, isSafeRelativePath(target) else {
        throw NemotronRecognizerError.runtimeIdentityMismatch
      }
      let destination = snapshotRoot.appendingPathComponent(path)
      try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: NSNumber(value: 0o700)]
      )
      try FileManager.default.createSymbolicLink(atPath: destination.path, withDestinationPath: target)
    }
    guard totalBytes == 5_032_648 else {
      throw NemotronRecognizerError.runtimeIdentityMismatch
    }
    try ensureDescriptorMatchesPath(descriptor, kind: "runtime")
    return snapshot
  }

  static func walk(_ directory: URL, relativeDirectory: String, into snapshot: inout RuntimeSnapshot) throws {
    let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    for name in names {
      guard isSafeRelativePath(name) else { throw NemotronRecognizerError.runtimeIdentityMismatch }
      let child = directory.appendingPathComponent(name)
      let relativePath = relativeDirectory.isEmpty ? name : "\(relativeDirectory)/\(name)"
      if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: child.path) {
        guard snapshot.symlinks[relativePath] == nil, isSafeRelativePath(target) else {
          throw NemotronRecognizerError.runtimeIdentityMismatch
        }
        snapshot.symlinks[relativePath] = target
        continue
      }
      let attributes = try? FileManager.default.attributesOfItem(atPath: child.path)
      guard let type = attributes?[.type] as? FileAttributeType else {
        throw NemotronRecognizerError.runtimeIdentityMismatch
      }
      if type == .typeDirectory {
        try walk(child, relativeDirectory: relativePath, into: &snapshot)
      } else if type == .typeRegular {
        guard snapshot.files[relativePath] == nil else {
          throw NemotronRecognizerError.runtimeIdentityMismatch
        }
        snapshot.files[relativePath] = child
      } else {
        throw NemotronRecognizerError.runtimeIdentityMismatch
      }
    }
  }

  static func verifySourceIdentity(at source: URL, descriptor: VerifiedDescriptor) throws {
    do {
      try ensureDescriptorMatchesPath(descriptor, kind: "source")
      let head = try git(["rev-parse", "--verify", "HEAD"], at: source).trimmingCharacters(in: .whitespacesAndNewlines)
      guard head == sourceCommit else { throw NemotronRecognizerError.sourceIdentityMismatch }
      try ensureDescriptorMatchesPath(descriptor, kind: "source")
      guard try git(["status", "--porcelain=v1", "--untracked-files=all"], at: source).isEmpty else {
        throw NemotronRecognizerError.sourceIdentityMismatch
      }
      try ensureDescriptorMatchesPath(descriptor, kind: "source")
      let lines = try git(["submodule", "status", "--recursive"], at: source)
        .split(whereSeparator: \.isNewline)
      var observed: [String: String] = [:]
      for line in lines where !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        guard let state = line.first, state == " " else {
          throw NemotronRecognizerError.sourceIdentityMismatch
        }
        let fields = line.dropFirst().split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard fields.count >= 2 else { throw NemotronRecognizerError.sourceIdentityMismatch }
        observed[String(fields[1])] = String(fields[0])
      }
      guard observed == expectedSubmodules else {
        throw NemotronRecognizerError.sourceIdentityMismatch
      }
      try ensureDescriptorMatchesPath(descriptor, kind: "source")
    } catch let error as NemotronRecognizerError {
      throw error
    } catch {
      throw NemotronRecognizerError.sourceIdentityMismatch
    }
  }

  static func git(_ arguments: [String], at directory: URL) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["--no-optional-locks", "-C", directory.path] + arguments
    process.environment = [
      "GIT_CONFIG_NOSYSTEM": "1",
      "GIT_CONFIG_GLOBAL": "/dev/null",
      "GIT_TERMINAL_PROMPT": "0",
    ]
    let output = Pipe()
    let error = Pipe()
    process.standardOutput = output
    process.standardError = error
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw NemotronRecognizerError.sourceIdentityMismatch
    }
    return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
  }

  static func objectIdentity(_ value: stat) -> FileObjectIdentity {
    FileObjectIdentity(
      device: UInt64(value.st_dev),
      inode: UInt64(value.st_ino),
      mode: UInt32(value.st_mode),
      size: Int64(value.st_size)
    )
  }

  static func sameObject(_ lhs: FileObjectIdentity, _ rhs: FileObjectIdentity) -> Bool {
    lhs.device == rhs.device && lhs.inode == rhs.inode &&
      lhs.mode & UInt32(S_IFMT) == rhs.mode & UInt32(S_IFMT)
  }

  static func descriptorIdentity(_ fd: Int32, kind: String) throws -> (FileObjectIdentity, String) {
    var before = stat()
    guard Darwin.fstat(fd, &before) == 0,
      objectIdentity(before).mode & UInt32(S_IFMT) == UInt32(S_IFREG) else {
      throw identityError(kind)
    }
    guard Darwin.lseek(fd, 0, SEEK_SET) >= 0 else { throw identityError(kind) }
    var hasher = SHA256()
    let bufferSize = 1_048_576
    let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 1)
    defer { buffer.deallocate() }
    while true {
      let count = Darwin.read(fd, buffer, bufferSize)
      guard count >= 0 else { throw identityError(kind) }
      guard count > 0 else { break }
      hasher.update(data: Data(bytes: buffer, count: count))
    }
    guard Darwin.lseek(fd, 0, SEEK_SET) >= 0 else { throw identityError(kind) }
    var after = stat()
    guard Darwin.fstat(fd, &after) == 0,
      sameObject(objectIdentity(before), objectIdentity(after)) else {
      throw identityError(kind)
    }
    let identity = objectIdentity(after)
    let digest = hasher.finalize().map { String(format: "%02x", Int($0)) }.joined()
    return (identity, digest)
  }

  static func snapshotFile(
    descriptor: VerifiedDescriptor,
    destination: URL,
    expectedSize: Int64,
    expectedSHA256: String,
    kind: String
  ) throws -> URL {
    guard descriptor.identity.size == expectedSize else { throw identityError(kind) }
    let parent = destination.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: parent,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: NSNumber(value: 0o700)]
    )
    let outputFD = Darwin.open(
      destination.path,
      O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
      mode_t(0o600)
    )
    guard outputFD >= 0 else { throw identityError(kind) }
    var outputClosed = false
    do {
      try copyDescriptor(descriptor.fd, to: outputFD, kind: kind)
      guard Darwin.fchmod(outputFD, mode_t(0o400)) == 0, Darwin.fsync(outputFD) == 0 else {
        throw identityError(kind)
      }
      Darwin.close(outputFD)
      outputClosed = true
      try verifySnapshotFile(
        destination,
        expectedSize: expectedSize,
        expectedSHA256: expectedSHA256,
        kind: kind
      )
      return destination
    } catch {
      if !outputClosed { Darwin.close(outputFD) }
      try? FileManager.default.removeItem(at: destination)
      throw error
    }
  }

  static func copyDescriptor(_ sourceFD: Int32, to destinationFD: Int32, kind: String) throws {
    guard Darwin.lseek(sourceFD, 0, SEEK_SET) >= 0 else { throw identityError(kind) }
    let bufferSize = 1_048_576
    let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 1)
    defer { buffer.deallocate() }
    while true {
      let count = Darwin.read(sourceFD, buffer, bufferSize)
      guard count >= 0 else { throw identityError(kind) }
      guard count > 0 else { break }
      var written = 0
      while written < count {
        let result = Darwin.write(destinationFD, buffer.advanced(by: written), count - written)
        guard result > 0 else { throw identityError(kind) }
        written += result
      }
    }
    guard Darwin.lseek(sourceFD, 0, SEEK_SET) >= 0 else { throw identityError(kind) }
  }

  static func verifySnapshotFile(
    _ url: URL,
    expectedSize: Int64,
    expectedSHA256: String,
    kind: String
  ) throws {
    let descriptor = try openRegularFile(url.path, kind: kind)
    defer { Darwin.close(descriptor.fd) }
    let observed = try descriptorIdentity(descriptor.fd, kind: kind)
    guard observed.0.size == expectedSize, observed.1 == expectedSHA256,
      descriptor.identity.mode & UInt32(S_IFMT) == UInt32(S_IFREG) else {
      throw identityError(kind)
    }
  }

  static func verifyRuntimeSnapshot(_ snapshot: RuntimeSnapshot) throws {
    var totalBytes: Int64 = 0
    for expected in expectedRuntimeFiles {
      guard let url = snapshot.files[expected.path] else {
        throw NemotronRecognizerError.runtimeIdentityMismatch
      }
      try verifySnapshotFile(
        url,
        expectedSize: expected.size,
        expectedSHA256: expected.sha256,
        kind: "runtime"
      )
      totalBytes += expected.size
    }
    guard totalBytes == 5_032_648 else {
      throw NemotronRecognizerError.runtimeIdentityMismatch
    }
  }

  static func makeSnapshotDirectory(prefix: String) throws -> URL {
    guard let canonicalBase = realpath(NSTemporaryDirectory(), nil) else {
      throw NemotronRecognizerError.invalidPath("snapshot")
    }
    let basePath = String(cString: canonicalBase)
    free(canonicalBase)
    let base = URL(fileURLWithPath: basePath, isDirectory: true)
    let directory = base.appendingPathComponent("fleck-\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: false,
      attributes: [.posixPermissions: NSNumber(value: 0o700)]
    )
    return directory
  }

  static func identityError(_ kind: String) -> NemotronRecognizerError {
    switch kind {
    case "model": return .modelIdentityMismatch
    case "source": return .sourceIdentityMismatch
    case "audio": return .invalidAudio
    default: return .runtimeIdentityMismatch
    }
  }

  static func ensureDescriptorMatchesPath(_ descriptor: VerifiedDescriptor, kind: String) throws {
    var current = stat()
    guard Darwin.lstat(descriptor.path.path, &current) == 0 else { throw identityError(kind) }
    let identity = objectIdentity(current)
    guard sameObject(descriptor.identity, identity),
      identity.mode & UInt32(S_IFMT) == descriptor.identity.mode & UInt32(S_IFMT) else {
      throw identityError(kind)
    }
  }

  static func readAudio(_ url: URL, expectedIdentity: (FileObjectIdentity, String)) throws -> PCM16Wave {
    guard expectedIdentity.0.size > 0 else {
      throw NemotronRecognizerError.invalidAudio
    }
    guard expectedIdentity.0.size <= Int64(maximumWAVBytes) else {
      throw NemotronRecognizerError.audioTooLarge
    }
    do {
      let audio = try WaveReader.read(url, expectedSampleRate: 16_000)
      guard audio.channels == 1 else { throw NemotronRecognizerError.unsupportedAudioFormat }
      guard !audio.samples.isEmpty else { throw NemotronRecognizerError.audioHasNoSamples }
      guard audio.samples.count <= maximumSamples else { throw NemotronRecognizerError.audioTooLarge }
      guard audio.samples.allSatisfy(\.isFinite) else { throw NemotronRecognizerError.invalidAudio }
      try verifySnapshotFile(
        url,
        expectedSize: expectedIdentity.0.size,
        expectedSHA256: expectedIdentity.1,
        kind: "audio"
      )
      return audio
    } catch let error as NemotronRecognizerError {
      throw error
    } catch {
      throw NemotronRecognizerError.invalidAudio
    }
  }

  static func testPause(stage: String) {
    let environment = ProcessInfo.processInfo.environment
    guard environment["FLECK_NEMOTRON_TEST_PAUSE"] == stage,
      let marker = environment["FLECK_NEMOTRON_TEST_MARKER"],
      let release = environment["FLECK_NEMOTRON_TEST_RELEASE"] else { return }
    FileManager.default.createFile(atPath: marker, contents: Data())
    while !FileManager.default.fileExists(atPath: release) {
      usleep(10_000)
    }
  }

  static func nativeTranscript(symbolTable: UnsafeMutableRawPointer, result: UnsafeMutableRawPointer) throws -> String {
    guard let pointer = FleckNemoTranscript(symbolTable, result) else {
      throw NemotronRecognizerError.nativeCallFailed("result-transcript")
    }
    let transcript = String(cString: pointer)
    guard transcript.utf8.count <= maximumTranscriptBytes else {
      throw NemotronRecognizerError.transcriptTooLarge
    }
    guard transcript.unicodeScalars.allSatisfy({ $0 != "\0" && $0 != "\n" && $0 != "\r" }) else {
      throw NemotronRecognizerError.transcriptContainsControlCharacter
    }
    return transcript
  }

  static func nativeLanguageCode(_ localeIdentifier: String) -> String? {
    switch localeIdentifier.lowercased() {
    case "auto": return nil
    case "en", "en-us": return "en-US"
    case "zh", "zh-cn": return "zh-CN"
    default: return localeIdentifier
    }
  }

  static func sleepUntil(_ deadline: UInt64) {
    let now = DispatchTime.now().uptimeNanoseconds
    guard deadline > now else { return }
    Thread.sleep(forTimeInterval: Double(deadline - now) / 1_000_000_000)
  }

  static func writeDiagnostic(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
  }
}
