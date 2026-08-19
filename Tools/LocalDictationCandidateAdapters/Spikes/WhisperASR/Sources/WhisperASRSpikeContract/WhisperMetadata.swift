public struct WhisperModelMetadata: Equatable, Sendable {
  public let repository: String
  public let revision: String
  public let fileName: String
  public let fileSHA256: String
  public let fileSizeBytes: Int64
  public let license: String

  fileprivate init(
    repository: String,
    revision: String,
    fileName: String,
    fileSHA256: String,
    fileSizeBytes: Int64,
    license: String
  ) {
    self.repository = repository
    self.revision = revision
    self.fileName = fileName
    self.fileSHA256 = fileSHA256
    self.fileSizeBytes = fileSizeBytes
    self.license = license
  }

  public static let ggmlSmall = WhisperModelMetadata(
    repository: "ggerganov/whisper.cpp",
    revision: "80da2d8bfee42b0e836fc3a9890373e5defc00a6",
    fileName: "ggml-small.bin",
    fileSHA256: "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b",
    fileSizeBytes: 487_601_967,
    license: "MIT"
  )
}

public struct WhisperBuildIntent: Equatable, Sendable {
  public let cmakeDefinitions: [String]

  fileprivate init(cmakeDefinitions: [String]) {
    self.cmakeDefinitions = cmakeDefinitions
  }

  public static let macOSMetalStatic = WhisperBuildIntent(cmakeDefinitions: [
    "BUILD_SHARED_LIBS=OFF",
    "GGML_METAL=ON",
    "GGML_METAL_EMBED_LIBRARY=ON",
    "WHISPER_CURL=OFF",
    "WHISPER_BUILD_SERVER=OFF",
    "WHISPER_COREML=OFF",
    "WHISPER_OPENVINO=OFF",
    "WHISPER_SDL2=OFF",
    "GGML_OPENMP=OFF",
    "GGML_BLAS=OFF",
    "CMAKE_OSX_DEPLOYMENT_TARGET=14.0",
  ])
}

public enum WhisperCompiledRuntimeStatus: String, Equatable, Sendable {
  case unadmitted
}

public enum WhisperRuntimeAdmissionError: Error, Equatable, Sendable {
  case compiledRuntimeIdentityUnavailable
}

public struct WhisperCompiledRuntimeMetadata: Equatable, Sendable {
  public let status: WhisperCompiledRuntimeStatus

  private init(status: WhisperCompiledRuntimeStatus) {
    self.status = status
  }

  public static let unadmitted = WhisperCompiledRuntimeMetadata(status: .unadmitted)

  public var isAdmitted: Bool {
    false
  }

  public func requireAdmitted() throws {
    throw WhisperRuntimeAdmissionError.compiledRuntimeIdentityUnavailable
  }
}

public struct WhisperSourceRuntimeMetadata: Equatable, Sendable {
  public let repository: String
  public let release: String
  public let sourceCommit: String
  public let license: String
  public let buildIntent: WhisperBuildIntent
  public let compiledRuntime: WhisperCompiledRuntimeMetadata

  fileprivate init(
    repository: String,
    release: String,
    sourceCommit: String,
    license: String,
    buildIntent: WhisperBuildIntent,
    compiledRuntime: WhisperCompiledRuntimeMetadata
  ) {
    self.repository = repository
    self.release = release
    self.sourceCommit = sourceCommit
    self.license = license
    self.buildIntent = buildIntent
    self.compiledRuntime = compiledRuntime
  }

  public static let whisperCpp = WhisperSourceRuntimeMetadata(
    repository: "ggml-org/whisper.cpp",
    release: "v1.9.2",
    sourceCommit: "306c88f4d1286aec1bf96e544632897886af5501",
    license: "MIT",
    buildIntent: .macOSMetalStatic,
    compiledRuntime: .unadmitted
  )
}

public struct WhisperASRMetadata: Equatable, Sendable {
  public let model: WhisperModelMetadata
  public let sourceRuntime: WhisperSourceRuntimeMetadata

  private init(
    model: WhisperModelMetadata,
    sourceRuntime: WhisperSourceRuntimeMetadata
  ) {
    self.model = model
    self.sourceRuntime = sourceRuntime
  }

  public static let candidate = WhisperASRMetadata(
    model: .ggmlSmall,
    sourceRuntime: .whisperCpp
  )

  public var nativeRuntimeAdmitted: Bool {
    sourceRuntime.compiledRuntime.isAdmitted
  }

  public var modelQualityAdmitted: Bool {
    false
  }

  public var admitted: Bool {
    nativeRuntimeAdmitted && modelQualityAdmitted
  }
}
