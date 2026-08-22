import CryptoKit
import Darwin
import Foundation

#if !arch(arm64)
#error("Qwen native evaluation requires macOS arm64")
#endif

enum QwenSherpaRecognizerError: Error, CustomStringConvertible {
  case invalidPreparedRoot
  case inventoryIdentityMismatch
  case malformedInventory
  case artifactInventoryMismatch
  case nativeRuntimeIdentityMismatch
  case nativeRecognizerUnavailable
  case invalidAudio
  case audioTooLarge
  case unsupportedAudioFormat
  case unsupportedAudioSampleRate
  case audioHasNoSamples
  case transcriptTooLarge
  case transcriptContainsControlCharacter
  case nativeDecodeFailed

  var code: String {
    switch self {
    case .invalidPreparedRoot: return "invalid-prepared-root"
    case .inventoryIdentityMismatch: return "inventory-identity-mismatch"
    case .malformedInventory: return "malformed-inventory"
    case .artifactInventoryMismatch: return "artifact-inventory-mismatch"
    case .nativeRuntimeIdentityMismatch: return "native-runtime-identity-mismatch"
    case .nativeRecognizerUnavailable: return "native-recognizer-unavailable"
    case .invalidAudio: return "invalid-audio"
    case .audioTooLarge: return "audio-too-large"
    case .unsupportedAudioFormat: return "unsupported-audio-format"
    case .unsupportedAudioSampleRate: return "unsupported-audio-sample-rate"
    case .audioHasNoSamples: return "audio-has-no-samples"
    case .transcriptTooLarge: return "transcript-too-large"
    case .transcriptContainsControlCharacter: return "transcript-contains-control-character"
    case .nativeDecodeFailed: return "native-decode-failed"
    }
  }

  var description: String { code }
}

struct QwenTranscriptionResult {
  let transcript: String
  let elapsedMilliseconds: Double
}

final class QwenSherpaRecognizer {
  static let runtimeVersion = "v1.13.4"
  static let modelRevision = "sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25"
  static let maximumWAVBytes = 128 * 1_024 * 1_024
  static let maximumSamples = 16_000 * 10 * 60
  static let maximumTranscriptBytes = 65_536

  private static let expectedInventorySHA256 = "27fa7f977fbfaeedc02c3a4dadef42411883349af6750f417700b9967a37a5d1"
  private static let expectedInventorySize = 7_680
  private static let expectedCandidate = "qwen3-asr-0.6b-int8"
  private static let expectedInventoryStatus = "verified-extracted-artifacts-only-unadmitted"
  private static let expectedRuntimeArchive = ArtifactArchive(
    fileName: "sherpa-onnx-v1.13.4-macos-shared-onnxruntime-static.xcframework.zip",
    sha256: "ef7daa86a1e5f5dcb0ccf53e4e475c3ae24414652c9ae9c3912a82140c86fb1a",
    sizeBytes: 17_716_081
  )
  private static let expectedModelArchive = ArtifactArchive(
    fileName: "sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25.tar.bz2",
    sha256: "393f8a14e2f5fb96746aaab342997a40641001fbd5bf9592a080a8329178ee96",
    sizeBytes: 878_702_423
  )

  private var symbolTable: UnsafeMutableRawPointer?
  private var recognizer: OpaquePointer?

  private init(symbolTable: UnsafeMutableRawPointer, recognizer: OpaquePointer) {
    self.symbolTable = symbolTable
    self.recognizer = recognizer
  }

  static func load(preparedRoot rawRoot: String) throws -> QwenSherpaRecognizer {
    let root = try requirePreparedRoot(rawRoot)
    let paths = try verifyInventory(at: root)
    guard let symbolTable = paths.runtimeBinary.path.withCString({
      FleckSherpaOpenVerified($0)
    }) else {
      throw QwenSherpaRecognizerError.nativeRuntimeIdentityMismatch
    }
    do {
      let nativeRecognizer = try createNativeRecognizer(paths: paths, symbolTable: symbolTable)
      return QwenSherpaRecognizer(symbolTable: symbolTable, recognizer: nativeRecognizer)
    } catch {
      FleckSherpaCloseVerified(symbolTable)
      throw error
    }
  }

  func transcribe(audioPath rawAudioPath: String, blockBeforeDecode: Bool) throws -> QwenTranscriptionResult {
    guard let symbolTable, let recognizer else {
      throw QwenSherpaRecognizerError.nativeRecognizerUnavailable
    }
    let audioURL = try Self.requireAudioURL(rawAudioPath)
    let audio = try PCM16WAV.read(audioURL)
    guard !audio.samples.isEmpty else {
      throw QwenSherpaRecognizerError.audioHasNoSamples
    }

    guard let stream = FleckSherpaCreateOfflineStream(symbolTable, recognizer) else {
      throw QwenSherpaRecognizerError.nativeDecodeFailed
    }
    defer { FleckSherpaDestroyOfflineStream(symbolTable, stream) }

    audio.samples.withUnsafeBufferPointer { buffer in
      FleckSherpaAcceptWaveformOffline(
        symbolTable,
        stream,
        Int32(audio.sampleRate),
        buffer.baseAddress,
        Int32(buffer.count)
      )
    }

    let started = DispatchTime.now().uptimeNanoseconds
    if blockBeforeDecode {
      let decodeStarted = DispatchSemaphore(value: 0)
      DispatchQueue.global(qos: .userInitiated).async {
        decodeStarted.signal()
        FleckSherpaDecodeOfflineStream(symbolTable, recognizer, stream)
      }
      decodeStarted.wait()
      FileHandle.standardError.write(Data("native-decode-blocked\n".utf8))
      while true {
        _ = Darwin.pause()
      }
    }
    FleckSherpaDecodeOfflineStream(symbolTable, recognizer, stream)
    guard let result = FleckSherpaGetOfflineStreamResult(symbolTable, stream) else {
      throw QwenSherpaRecognizerError.nativeDecodeFailed
    }
    defer { FleckSherpaDestroyOfflineRecognizerResult(symbolTable, result) }
    guard let text = FleckSherpaOfflineResultText(symbolTable, result) else {
      throw QwenSherpaRecognizerError.nativeDecodeFailed
    }
    let transcript = String(cString: text)
    guard transcript.utf8.count <= Self.maximumTranscriptBytes else {
      throw QwenSherpaRecognizerError.transcriptTooLarge
    }
    guard transcript.unicodeScalars.allSatisfy({ scalar in
      scalar != "\0" && scalar != "\n" && scalar != "\r"
    }) else {
      throw QwenSherpaRecognizerError.transcriptContainsControlCharacter
    }
    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
    return QwenTranscriptionResult(transcript: transcript, elapsedMilliseconds: elapsed)
  }

  func close() {
    if let symbolTable {
      if let recognizer {
        FleckSherpaDestroyOfflineRecognizer(symbolTable, recognizer)
      }
      FleckSherpaCloseVerified(symbolTable)
      self.symbolTable = nil
    }
    self.recognizer = nil
  }

  deinit {
    close()
  }
}

private struct ArtifactArchive: Decodable, Equatable {
  let fileName: String
  let sha256: String
  let sizeBytes: Int64
}

private struct ArtifactFile: Decodable {
  let path: String
  let sha256: String
  let sizeBytes: Int64
}

private struct ArtifactSymlink: Decodable {
  let path: String
  let target: String
}

private struct InstalledArtifactInventory: Decodable {
  let archives: [ArtifactArchive]
  let candidate: String
  let installedFiles: [ArtifactFile]
  let installedSymlinks: [ArtifactSymlink]
  let releaseAdmitted: Bool
  let schemaVersion: Int
  let status: String
  let totalInstalledBytes: Int64
}

private struct VerifiedArtifactPaths {
  let convFrontend: URL
  let encoder: URL
  let decoder: URL
  let tokenizer: URL
  let runtimeBinary: URL
}

private struct ArtifactSnapshot {
  var files: [String: URL] = [:]
  var symlinks: [String: String] = [:]
}

private struct PCM16WAV {
  let sampleRate: Int
  let samples: [Float]

  static func read(_ url: URL) throws -> PCM16WAV {
    let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
    let byteCount = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    guard byteCount > 0 else { throw QwenSherpaRecognizerError.invalidAudio }
    guard byteCount <= Int64(QwenSherpaRecognizer.maximumWAVBytes) else {
      throw QwenSherpaRecognizerError.audioTooLarge
    }
    guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
      throw QwenSherpaRecognizerError.invalidAudio
    }
    guard data.count <= QwenSherpaRecognizer.maximumWAVBytes else {
      throw QwenSherpaRecognizerError.audioTooLarge
    }
    guard data.count >= 12,
      data[0..<4].elementsEqual(Data("RIFF".utf8)),
      data[8..<12].elementsEqual(Data("WAVE".utf8))
    else {
      throw QwenSherpaRecognizerError.invalidAudio
    }

    var offset = 12
    var format: (code: UInt16, channels: UInt16, sampleRate: Int, blockAlign: UInt16, bits: UInt16)?
    var sampleRange: Range<Int>?
    while offset + 8 <= data.count {
      let chunkSize = Int(readUInt32(data, at: offset + 4))
      let payloadStart = offset + 8
      guard chunkSize >= 0, payloadStart <= data.count, chunkSize <= data.count - payloadStart else {
        throw QwenSherpaRecognizerError.invalidAudio
      }
      let payloadEnd = payloadStart + chunkSize
      let chunkID = data[offset..<offset + 4]
      if chunkID.elementsEqual(Data("fmt ".utf8)), chunkSize >= 16 {
        format = (
          code: readUInt16(data, at: payloadStart),
          channels: readUInt16(data, at: payloadStart + 2),
          sampleRate: Int(readUInt32(data, at: payloadStart + 4)),
          blockAlign: readUInt16(data, at: payloadStart + 12),
          bits: readUInt16(data, at: payloadStart + 14)
        )
      } else if chunkID.elementsEqual(Data("data".utf8)), sampleRange == nil {
        sampleRange = payloadStart..<payloadEnd
      }
      let paddedEnd = payloadEnd + (chunkSize & 1)
      guard paddedEnd <= data.count else {
        throw QwenSherpaRecognizerError.invalidAudio
      }
      offset = paddedEnd
    }

    guard let format, let sampleRange else {
      throw QwenSherpaRecognizerError.invalidAudio
    }
    guard format.channels == 1, format.sampleRate == 16_000 || format.sampleRate == 44_100 else {
      throw QwenSherpaRecognizerError.unsupportedAudioSampleRate
    }

    let sourceSamples: [Float]
    switch (format.code, format.bits, format.blockAlign) {
    case (1, 16, 2):
      guard sampleRange.count.isMultiple(of: 2) else {
        throw QwenSherpaRecognizerError.invalidAudio
      }
      sourceSamples = stride(from: sampleRange.lowerBound, to: sampleRange.upperBound, by: 2).map { index in
        let value = Int16(bitPattern: readUInt16(data, at: index))
        return Float(value) / 32_768
      }
    case (3, 32, 4):
      guard format.sampleRate == 16_000, sampleRange.count.isMultiple(of: 4) else {
        throw QwenSherpaRecognizerError.unsupportedAudioFormat
      }
      sourceSamples = stride(from: sampleRange.lowerBound, to: sampleRange.upperBound, by: 4).map { index in
        Float(bitPattern: readUInt32(data, at: index))
      }
      guard sourceSamples.allSatisfy({ $0.isFinite && abs($0) <= 1 }) else {
        throw QwenSherpaRecognizerError.invalidAudio
      }
    default:
      throw QwenSherpaRecognizerError.unsupportedAudioFormat
    }

    guard !sourceSamples.isEmpty else {
      throw QwenSherpaRecognizerError.audioHasNoSamples
    }
    guard sourceSamples.count <= QwenSherpaRecognizer.maximumSamples else {
      throw QwenSherpaRecognizerError.audioTooLarge
    }
    if format.sampleRate == 16_000 {
      return PCM16WAV(sampleRate: 16_000, samples: sourceSamples)
    }
    return PCM16WAV(sampleRate: 16_000, samples: resampleTo16k(sourceSamples, from: format.sampleRate))
  }

  private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
    UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
  }

  private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
    UInt32(data[offset]) |
      (UInt32(data[offset + 1]) << 8) |
      (UInt32(data[offset + 2]) << 16) |
      (UInt32(data[offset + 3]) << 24)
  }

  private static func resampleTo16k(_ source: [Float], from sampleRate: Int) -> [Float] {
    let outputCount = max(1, Int((Double(source.count) * 16_000 / Double(sampleRate)).rounded()))
    let ratio = Double(sampleRate) / 16_000
    return (0..<outputCount).map { outputIndex in
      let position = Double(outputIndex) * ratio
      let lower = min(source.count - 1, Int(position))
      let upper = min(source.count - 1, lower + 1)
      let fraction = Float(position - Double(lower))
      return source[lower] + (source[upper] - source[lower]) * fraction
    }
  }
}

private extension QwenSherpaRecognizer {
  static func requirePreparedRoot(_ rawRoot: String) throws -> URL {
    guard isSafeAbsolutePath(rawRoot) else {
      throw QwenSherpaRecognizerError.invalidPreparedRoot
    }
    let lexical = URL(fileURLWithPath: rawRoot, isDirectory: true).standardizedFileURL
    let resolved = lexical.resolvingSymlinksInPath().standardizedFileURL
    guard lexical.path == resolved.path else {
      throw QwenSherpaRecognizerError.invalidPreparedRoot
    }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: lexical.path, isDirectory: &isDirectory), isDirectory.boolValue else {
      throw QwenSherpaRecognizerError.invalidPreparedRoot
    }
    return lexical
  }

  static func requireAudioURL(_ rawPath: String) throws -> URL {
    guard isSafeAbsolutePath(rawPath) else {
      throw QwenSherpaRecognizerError.invalidAudio
    }
    let lexical = URL(fileURLWithPath: rawPath).standardizedFileURL
    let resolved = lexical.resolvingSymlinksInPath().standardizedFileURL
    guard lexical.path == resolved.path else {
      throw QwenSherpaRecognizerError.invalidAudio
    }
    let attributes = try? FileManager.default.attributesOfItem(atPath: lexical.path)
    guard attributes?[.type] as? FileAttributeType == .typeRegular else {
      throw QwenSherpaRecognizerError.invalidAudio
    }
    return lexical
  }

  static func isSafeAbsolutePath(_ path: String) -> Bool {
    guard path.first == "/", !path.contains("://"), !path.contains("\0"), !path.contains("\n"), !path.contains("\r") else {
      return false
    }
    let components = path.split(separator: "/", omittingEmptySubsequences: false)
    return !components.contains(where: { $0 == "." || $0 == ".." || $0.isEmpty && $0 != components.first })
  }

  static func verifyInventory(at root: URL) throws -> VerifiedArtifactPaths {
    let inventoryURL = root.appendingPathComponent("installed-artifact-inventory.json")
    let inventoryIdentity = try fileIdentity(inventoryURL)
    guard inventoryIdentity.size == expectedInventorySize, inventoryIdentity.sha256 == expectedInventorySHA256 else {
      throw QwenSherpaRecognizerError.inventoryIdentityMismatch
    }
    guard let data = try? Data(contentsOf: inventoryURL, options: .mappedIfSafe),
      let inventory = try? JSONDecoder().decode(InstalledArtifactInventory.self, from: data)
    else {
      throw QwenSherpaRecognizerError.malformedInventory
    }
    guard inventory.schemaVersion == 1,
      inventory.candidate == expectedCandidate,
      inventory.status == expectedInventoryStatus,
      inventory.releaseAdmitted == false,
      inventory.archives.count == 2,
      inventory.archives.contains(expectedRuntimeArchive),
      inventory.archives.contains(expectedModelArchive)
    else {
      throw QwenSherpaRecognizerError.malformedInventory
    }
    guard inventory.installedFiles.allSatisfy({ file in
      isSafeRelativePath(file.path) &&
        file.sha256.count == 64 &&
        file.sha256.utf8.allSatisfy { byte in
          (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)
        } &&
        file.sizeBytes > 0
    }) else {
      throw QwenSherpaRecognizerError.malformedInventory
    }

    let filesByPath = Dictionary(uniqueKeysWithValues: inventory.installedFiles.map { ($0.path, $0) })
    let linksByPath = Dictionary(uniqueKeysWithValues: inventory.installedSymlinks.map { ($0.path, $0) })
    guard filesByPath.count == inventory.installedFiles.count,
      linksByPath.count == inventory.installedSymlinks.count,
      Set(filesByPath.keys).isDisjoint(with: Set(linksByPath.keys))
    else {
      throw QwenSherpaRecognizerError.malformedInventory
    }
    for path in Array(filesByPath.keys) + Array(linksByPath.keys) {
      guard isSafeRelativePath(path), path.hasPrefix("runtime/") || path.hasPrefix("model/") else {
        throw QwenSherpaRecognizerError.malformedInventory
      }
    }
    for link in inventory.installedSymlinks {
      guard isSafeRelativePath(link.target), !link.target.hasPrefix("/") else {
        throw QwenSherpaRecognizerError.malformedInventory
      }
    }

    let topLevel = Set((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [])
    guard topLevel == ["installed-artifact-inventory.json", "runtime", "model"] else {
      throw QwenSherpaRecognizerError.artifactInventoryMismatch
    }
    let runtimeRoot = root.appendingPathComponent("runtime")
    let modelDirectory = root.appendingPathComponent("model")
    guard (try? FileManager.default.destinationOfSymbolicLink(atPath: inventoryURL.path)) == nil,
      (try? FileManager.default.destinationOfSymbolicLink(atPath: runtimeRoot.path)) == nil,
      (try? FileManager.default.destinationOfSymbolicLink(atPath: modelDirectory.path)) == nil,
      isDirectory(runtimeRoot),
      isDirectory(modelDirectory)
    else {
      throw QwenSherpaRecognizerError.artifactInventoryMismatch
    }

    var snapshot = ArtifactSnapshot()
    try walk(runtimeRoot, relativeDirectory: "runtime", into: &snapshot)
    try walk(modelDirectory, relativeDirectory: "model", into: &snapshot)
    guard Set(snapshot.files.keys) == Set(filesByPath.keys),
      Set(snapshot.symlinks.keys) == Set(linksByPath.keys)
    else {
      throw QwenSherpaRecognizerError.artifactInventoryMismatch
    }

    var totalBytes: Int64 = 0
    for (path, expected) in filesByPath {
      guard let url = snapshot.files[path] else {
        throw QwenSherpaRecognizerError.artifactInventoryMismatch
      }
      let actual = try fileIdentity(url)
      guard actual.size == expected.sizeBytes, actual.sha256 == expected.sha256 else {
        throw QwenSherpaRecognizerError.artifactInventoryMismatch
      }
      totalBytes += actual.size
    }
    for (path, expected) in linksByPath {
      guard snapshot.symlinks[path] == expected.target else {
        throw QwenSherpaRecognizerError.artifactInventoryMismatch
      }
    }
    guard totalBytes == inventory.totalInstalledBytes else {
      throw QwenSherpaRecognizerError.artifactInventoryMismatch
    }

    let runtimeSlice = root.appendingPathComponent("runtime/sherpa-onnx.xcframework/macos-arm64_x86_64", isDirectory: true)
    let runtimeBinary = runtimeSlice.appendingPathComponent("SherpaOnnxC.framework/Versions/A/SherpaOnnxC")
    let modelRoot = root.appendingPathComponent("model/sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25", isDirectory: true)
    let paths = VerifiedArtifactPaths(
      convFrontend: modelRoot.appendingPathComponent("conv_frontend.onnx"),
      encoder: modelRoot.appendingPathComponent("encoder.int8.onnx"),
      decoder: modelRoot.appendingPathComponent("decoder.int8.onnx"),
      tokenizer: modelRoot.appendingPathComponent("tokenizer", isDirectory: true),
      runtimeBinary: runtimeBinary
    )
    guard isDirectory(paths.tokenizer),
      isRegularFile(paths.convFrontend),
      isRegularFile(paths.encoder),
      isRegularFile(paths.decoder),
      isRegularFile(paths.runtimeBinary)
    else {
      throw QwenSherpaRecognizerError.nativeRuntimeIdentityMismatch
    }
    return paths
  }

  static func createNativeRecognizer(
    paths: VerifiedArtifactPaths,
    symbolTable: UnsafeMutableRawPointer
  ) throws -> OpaquePointer {
    let provider = "cpu"
    let decodingMethod = "greedy_search"
    return try paths.convFrontend.path.withCString { convFrontend in
      try paths.encoder.path.withCString { encoder in
        try paths.decoder.path.withCString { decoder in
          try paths.tokenizer.path.withCString { tokenizer in
            try provider.withCString { provider in
              try decodingMethod.withCString { decodingMethod in
                var config = SherpaOnnxOfflineRecognizerConfig()
                config.feat_config.sample_rate = 16_000
                config.feat_config.feature_dim = 80
                config.model_config.num_threads = 2
                config.model_config.provider = provider
                config.model_config.debug = 0
                config.model_config.qwen3_asr.conv_frontend = convFrontend
                config.model_config.qwen3_asr.encoder = encoder
                config.model_config.qwen3_asr.decoder = decoder
                config.model_config.qwen3_asr.tokenizer = tokenizer
                config.model_config.qwen3_asr.max_total_len = 4_096
                config.model_config.qwen3_asr.max_new_tokens = 512
                config.model_config.qwen3_asr.temperature = 0
                config.model_config.qwen3_asr.top_p = 1
                config.model_config.qwen3_asr.seed = 0
                config.decoding_method = decodingMethod
                guard let recognizer = FleckSherpaCreateOfflineRecognizer(symbolTable, &config) else {
                  throw QwenSherpaRecognizerError.nativeRecognizerUnavailable
                }
                return recognizer
              }
            }
          }
        }
      }
    }
  }

  static func walk(_ directory: URL, relativeDirectory: String, into snapshot: inout ArtifactSnapshot) throws {
    for name in try FileManager.default.contentsOfDirectory(atPath: directory.path) {
      let child = directory.appendingPathComponent(name)
      let relativePath = relativeDirectory + "/" + name
      if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: child.path) {
        guard snapshot.symlinks[relativePath] == nil else {
          throw QwenSherpaRecognizerError.artifactInventoryMismatch
        }
        snapshot.symlinks[relativePath] = target
        continue
      }
      var isDir: ObjCBool = false
      guard FileManager.default.fileExists(atPath: child.path, isDirectory: &isDir) else {
        throw QwenSherpaRecognizerError.artifactInventoryMismatch
      }
      if isDir.boolValue {
        try walk(child, relativeDirectory: relativePath, into: &snapshot)
      } else if isRegularFile(child) {
        guard snapshot.files[relativePath] == nil else {
          throw QwenSherpaRecognizerError.artifactInventoryMismatch
        }
        snapshot.files[relativePath] = child
      } else {
        throw QwenSherpaRecognizerError.artifactInventoryMismatch
      }
    }
  }

  static func fileIdentity(_ url: URL) throws -> (size: Int64, sha256: String) {
    guard isRegularFile(url) else {
      throw QwenSherpaRecognizerError.artifactInventoryMismatch
    }
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    guard let size = (attributes[.size] as? NSNumber)?.int64Value else {
      throw QwenSherpaRecognizerError.artifactInventoryMismatch
    }
    var hasher = SHA256()
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
      hasher.update(data: data)
    }
    let digest = hasher.finalize().map { String(format: "%02x", Int($0)) }.joined()
    return (size: size, sha256: digest)
  }

  static func isSafeRelativePath(_ path: String) -> Bool {
    guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("://") else { return false }
    let components = path.split(separator: "/", omittingEmptySubsequences: false)
    return !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
  }

  static func isDirectory(_ url: URL) -> Bool {
    var isDir: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
  }

  static func isRegularFile(_ url: URL) -> Bool {
    let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
    return attributes?[.type] as? FileAttributeType == .typeRegular
  }
}
