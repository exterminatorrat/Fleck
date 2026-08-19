import Foundation

public enum QwenASRRoute: String, CaseIterable, Sendable {
  case sherpa

  public var capabilities: QwenASRCapabilities {
    QwenASRCapabilities(
      supportsTrueStreaming: false,
      emitsRollingWindowPartials: false,
      supportsRollingWindowPartials: false,
      supportsBoundedContext: false,
      coreMLSupportsContext: false,
      supportsLoadCancellation: false,
      supportsDecodeCancellation: false
    )
  }
}

public struct QwenASRCapabilities: Equatable, Sendable {
  public let supportsTrueStreaming: Bool
  public let emitsRollingWindowPartials: Bool
  public let supportsRollingWindowPartials: Bool
  public let supportsBoundedContext: Bool
  public let coreMLSupportsContext: Bool
  public let supportsLoadCancellation: Bool
  public let supportsDecodeCancellation: Bool

  public var supportsCancellation: Bool {
    supportsLoadCancellation && supportsDecodeCancellation
  }

  public var resultSemantics: String {
    "batch-final-only"
  }
}

public enum ArtifactAdmissionError: Error, Equatable, CustomStringConvertible {
  case artifactIdentityUnadmitted
  case incompleteInstalledIdentity([String])
  case archiveIdentityMismatch(String)
  case invalidRelativePath(String)
  case invalidSHA256(String)
  case invalidSize(String)
  case invalidArchiveFileName
  case invalidArchiveURL

  public var description: String {
    switch self {
    case .artifactIdentityUnadmitted:
      return "artifact-identity-unadmitted"
    case .incompleteInstalledIdentity(let paths):
      return "incomplete-installed-identity:\(paths.joined(separator: ","))"
    case .archiveIdentityMismatch(let field):
      return "archive-identity-mismatch:\(field)"
    case .invalidRelativePath(let path):
      return "invalid-artifact-path:\(path)"
    case .invalidSHA256(let path):
      return "invalid-artifact-sha256:\(path)"
    case .invalidSize(let path):
      return "invalid-artifact-size:\(path)"
    case .invalidArchiveFileName:
      return "invalid-archive-file-name"
    case .invalidArchiveURL:
      return "invalid-archive-url"
    }
  }
}

public struct ArtifactIdentity: Equatable, Sendable {
  public let relativePath: String
  public let sha256: String
  public let size: Int64

  public init(relativePath: String, sha256: String, size: Int64) throws {
    guard Self.isSafeRelativePath(relativePath) else {
      throw ArtifactAdmissionError.invalidRelativePath(relativePath)
    }
    guard sha256.utf8.count == 64,
      sha256.utf8.allSatisfy({ byte in
        (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)
      })
    else {
      throw ArtifactAdmissionError.invalidSHA256(relativePath)
    }
    guard size > 0 else {
      throw ArtifactAdmissionError.invalidSize(relativePath)
    }
    self.relativePath = relativePath
    self.sha256 = sha256
    self.size = size
  }

  private static func isSafeRelativePath(_ path: String) -> Bool {
    guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("://") else {
      return false
    }
    let components = path.split(separator: "/", omittingEmptySubsequences: false)
    return !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
  }
}

public struct QwenASRArchiveMetadata: Equatable, Sendable {
  public let fileName: String
  public let url: String
  public let sha256: String
  public let sizeBytes: Int64

  public var size: Int64 {
    sizeBytes
  }

  public init(
    fileName: String,
    url: String,
    sha256: String,
    sizeBytes: Int64
  ) throws {
    guard !fileName.isEmpty, !fileName.contains("/") else {
      throw ArtifactAdmissionError.invalidArchiveFileName
    }
    guard let parsedURL = URL(string: url), parsedURL.scheme == "https", parsedURL.host != nil else {
      throw ArtifactAdmissionError.invalidArchiveURL
    }
    guard sha256.utf8.count == 64,
      sha256.utf8.allSatisfy({ byte in
        (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)
      })
    else {
      throw ArtifactAdmissionError.invalidSHA256(fileName)
    }
    guard sizeBytes > 0 else {
      throw ArtifactAdmissionError.invalidSize(fileName)
    }
    self.fileName = fileName
    self.url = url
    self.sha256 = sha256
    self.sizeBytes = sizeBytes
  }

  public static let sherpaRuntime = make(
    fileName: "sherpa-onnx-v1.13.4-macos-shared-onnxruntime-static.xcframework.zip",
    url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/xcframework/sherpa-onnx-v1.13.4-macos-shared-onnxruntime-static.xcframework.zip",
    sha256: "ef7daa86a1e5f5dcb0ccf53e4e475c3ae24414652c9ae9c3912a82140c86fb1a",
    sizeBytes: 17_716_081
  )

  public static let sherpaModel = make(
    fileName: "sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25.tar.bz2",
    url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25.tar.bz2",
    sha256: "393f8a14e2f5fb96746aaab342997a40641001fbd5bf9592a080a8329178ee96",
    sizeBytes: 878_702_423
  )

  public func requireMatches(_ expected: QwenASRArchiveMetadata) throws {
    guard self == expected else {
      throw ArtifactAdmissionError.archiveIdentityMismatch(fileName)
    }
  }

  private static func make(
    fileName: String,
    url: String,
    sha256: String,
    sizeBytes: Int64
  ) -> QwenASRArchiveMetadata {
    do {
      return try QwenASRArchiveMetadata(
        fileName: fileName,
        url: url,
        sha256: sha256,
        sizeBytes: sizeBytes
      )
    } catch {
      preconditionFailure("immutable Qwen archive metadata is invalid: \(error)")
    }
  }
}

public struct QwenASRRuntimeMetadata: Equatable, Sendable {
  public let upstreamRepository: String
  public let release: String
  public let sourceCommit: String
  public let license: String
  public let swiftToolchain: String
  public let cAPI: String
  public let platform: String
  public let architecture: String
  public let provider: String
  public let threadCount: Int
  public let abi: String
  public let expectedLayout: [String]
  public let archive: QwenASRArchiveMetadata

  public static let sherpa = QwenASRRuntimeMetadata(
    upstreamRepository: "k2-fsa/sherpa-onnx",
    release: "v1.13.4",
    sourceCommit: "142807252687d81b40d6315f23470a1512a00de3",
    license: "Apache-2.0",
    swiftToolchain: "Swift 6.3.3",
    cAPI: "sherpa-onnx C API",
    platform: "macOS",
    architecture: "arm64",
    provider: "cpu",
    threadCount: 2,
    abi: "arm64-apple-macosx13.0",
    expectedLayout: [
      "SherpaOnnxC.framework/SherpaOnnxC",
      "SherpaOnnxC.framework/Headers/sherpa-onnx/c-api/c-api.h",
    ],
    archive: .sherpaRuntime
  )
}

public struct QwenASRModelMetadata: Equatable, Sendable {
  public let ownerRepository: String
  public let ownerRevision: String
  public let ownerLicense: String
  public let ownerModelFile: String
  public let ownerModelFileSHA256: String
  public let convertedArchive: QwenASRArchiveMetadata
  public let expectedLayout: [String]

  public static let sherpaQwen3ASR06BInt8 = QwenASRModelMetadata(
    ownerRepository: "Qwen/Qwen3-ASR-0.6B",
    ownerRevision: "5eb144179a02acc5e5ba31e748d22b0cf3e303b0",
    ownerLicense: "Apache-2.0",
    ownerModelFile: "model.safetensors",
    ownerModelFileSHA256: "79d6cbd4c98c7bbffe9db2edac07f56cd6637d0d5944b27f6c2b8353840323ea",
    convertedArchive: .sherpaModel,
    expectedLayout: [
      "conv_frontend.onnx",
      "encoder.int8.onnx",
      "decoder.int8.onnx",
      "tokenizer/vocab.json",
      "tokenizer/merges.txt",
      "tokenizer/tokenizer_config.json",
    ]
  )
}

public enum InstalledArtifactIdentityStatus: Equatable, Sendable {
  case incomplete([String])
  case complete
}

public struct ArtifactManifest: Equatable, Sendable {
  public let route: QwenASRRoute
  public let backend: String
  public let artifacts: [ArtifactIdentity]
  public let runtimeMetadata: QwenASRRuntimeMetadata
  public let modelMetadata: QwenASRModelMetadata
  public let runtimeArchive: QwenASRArchiveMetadata
  public let modelArchive: QwenASRArchiveMetadata

  public var runtime: QwenASRRuntimeMetadata {
    runtimeMetadata
  }

  public var model: QwenASRModelMetadata {
    modelMetadata
  }

  public var expectedRuntimePaths: [String] {
    runtimeMetadata.expectedLayout
  }

  public var expectedModelPaths: [String] {
    modelMetadata.expectedLayout
  }

  public var installedIdentityStatus: InstalledArtifactIdentityStatus {
    let present = Set(artifacts.map(\.relativePath))
    let expected = expectedRuntimePaths + expectedModelPaths
    let missing = expected.filter { !present.contains($0) }
    return missing.isEmpty ? .complete : .incomplete(missing)
  }

  public var admitted: Bool {
    false
  }

  private init(
    route: QwenASRRoute,
    backend: String,
    runtimeMetadata: QwenASRRuntimeMetadata,
    modelMetadata: QwenASRModelMetadata,
    artifacts: [ArtifactIdentity]
  ) {
    self.route = route
    self.backend = backend
    self.runtimeMetadata = runtimeMetadata
    self.modelMetadata = modelMetadata
    runtimeArchive = runtimeMetadata.archive
    modelArchive = modelMetadata.convertedArchive
    self.artifacts = artifacts
  }

  public static func unadmitted(route: QwenASRRoute, backend: String) -> ArtifactManifest {
    ArtifactManifest(
      route: route,
      backend: backend,
      runtimeMetadata: .sherpa,
      modelMetadata: .sherpaQwen3ASR06BInt8,
      artifacts: []
    )
  }

  public func requireAdmitted() throws {
    guard runtimeArchive == QwenASRRuntimeMetadata.sherpa.archive else {
      throw ArtifactAdmissionError.archiveIdentityMismatch("runtime-archive")
    }
    guard modelArchive == QwenASRModelMetadata.sherpaQwen3ASR06BInt8.convertedArchive else {
      throw ArtifactAdmissionError.archiveIdentityMismatch("model-archive")
    }
    guard case .complete = installedIdentityStatus else {
      if case .incomplete(let paths) = installedIdentityStatus {
        if artifacts.isEmpty {
          throw ArtifactAdmissionError.artifactIdentityUnadmitted
        }
        throw ArtifactAdmissionError.incompleteInstalledIdentity(paths)
      }
      throw ArtifactAdmissionError.artifactIdentityUnadmitted
    }
  }

  public func withNativeLoad<T>(_ body: () throws -> T) throws -> T {
    try requireAdmitted()
    return try body()
  }
}

public enum QwenASRArtifactManifests {
  public static let sherpa = ArtifactManifest.unadmitted(route: .sherpa, backend: "sherpa-onnx")
  public static let all = [sherpa]
}

public enum StartupPathError: Error, Equatable, CustomStringConvertible {
  case notAbsolute(String)
  case networkURL(String)
  case missing(String)
  case notDirectory(String)
  case notRegularFile(String)
  case emptyFile(String)
  case outsideRoot(String)
  case invalidArgument

  public var description: String {
    switch self {
    case .notAbsolute(let field): return "not-absolute:\(field)"
    case .networkURL(let field): return "network-url:\(field)"
    case .missing(let field): return "missing:\(field)"
    case .notDirectory(let field): return "not-directory:\(field)"
    case .notRegularFile(let field): return "not-regular-file:\(field)"
    case .emptyFile(let field): return "empty-file:\(field)"
    case .outsideRoot(let field): return "outside-root:\(field)"
    case .invalidArgument: return "invalid-argument"
    }
  }
}

public enum StartupPathPolicy {
  public static func requireLocalDirectory(_ rawPath: String, field: String) throws -> URL {
    guard rawPath.first == "/" else {
      throw StartupPathError.notAbsolute(field)
    }
    guard !rawPath.contains("://") else {
      throw StartupPathError.networkURL(field)
    }

    let lexicalURL = URL(fileURLWithPath: rawPath).standardizedFileURL
    let resolvedURL = lexicalURL.resolvingSymlinksInPath().standardizedFileURL
    guard lexicalURL.path == resolvedURL.path else {
      throw StartupPathError.outsideRoot(field)
    }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: resolvedURL.path, isDirectory: &isDirectory) else {
      throw StartupPathError.missing(field)
    }
    guard isDirectory.boolValue else {
      throw StartupPathError.notDirectory(field)
    }
    return resolvedURL
  }

  public static func requireContainedFile(
    _ rawPath: String,
    within root: URL,
    field: String
  ) throws -> URL {
    guard rawPath.first == "/" else {
      throw StartupPathError.notAbsolute(field)
    }
    guard !rawPath.contains("://") else {
      throw StartupPathError.networkURL(field)
    }
    let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
    let resolvedFile = URL(fileURLWithPath: rawPath).resolvingSymlinksInPath().standardizedFileURL
    let rootPrefix = resolvedRoot.path.hasSuffix("/") ? resolvedRoot.path : resolvedRoot.path + "/"
    guard resolvedFile.path.hasPrefix(rootPrefix) else {
      throw StartupPathError.outsideRoot(field)
    }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: resolvedFile.path, isDirectory: &isDirectory) else {
      throw StartupPathError.missing(field)
    }
    guard !isDirectory.boolValue else {
      throw StartupPathError.notRegularFile(field)
    }
    return resolvedFile
  }

  public static func requireNonEmptyContainedFile(
    _ rawPath: String,
    within root: URL,
    field: String
  ) throws -> URL {
    let file = try requireContainedFile(rawPath, within: root, field: field)
    let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
    guard (attributes[.size] as? NSNumber)?.int64Value ?? 0 > 0 else {
      throw StartupPathError.emptyFile(field)
    }
    return file
  }
}

public enum BoundedContextError: Error, Equatable, CustomStringConvertible {
  case tooManyPhrases
  case emptyPhrase
  case duplicatePhrase(String)
  case commaInPhrase

  public var description: String {
    switch self {
    case .tooManyPhrases: return "too-many-phrases"
    case .emptyPhrase: return "empty-phrase"
    case .duplicatePhrase(let value): return "duplicate-phrase:\(value)"
    case .commaInPhrase: return "comma-in-phrase"
    }
  }
}

public enum BoundedContext {
  public static func hotwordArgument(_ phrases: [String]) throws -> String {
    guard phrases.count <= 100 else {
      throw BoundedContextError.tooManyPhrases
    }

    var seen = Set<String>()
    for phrase in phrases {
      guard !phrase.isEmpty else {
        throw BoundedContextError.emptyPhrase
      }
      guard !phrase.contains(",") else {
        throw BoundedContextError.commaInPhrase
      }
      guard seen.insert(phrase).inserted else {
        throw BoundedContextError.duplicatePhrase(phrase)
      }
    }
    return phrases.joined(separator: ",")
  }
}
