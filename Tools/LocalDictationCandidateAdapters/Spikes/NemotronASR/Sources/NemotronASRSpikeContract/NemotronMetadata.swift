public struct NemotronModelMetadata: Equatable, Sendable {
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

  public static let nemotron35ASRStreaming06B = NemotronModelMetadata(
    repository: "nvidia/nemotron-3.5-asr-streaming-0.6b",
    revision: "1c8deaecc64b91f034d73e08dd8b64625eb3395d",
    fileName: "nemotron-3.5-asr-streaming-0.6b.q8_0.gguf",
    fileSHA256: "a5c435f294eea8f88ce68dd27b8c3bfea7f777cb2fbba04fcd30eaa555f429ae",
    fileSizeBytes: 741_548_352,
    license: "OpenMDW-1.1"
  )
}

public struct NemotronDependencyPin: Equatable, Sendable {
  public let name: String
  public let commit: String

  fileprivate init(name: String, commit: String) {
    self.name = name
    self.commit = commit
  }
}

public struct NemotronBuildPreset: Equatable, Sendable {
  public let name: String
  public let accelerator: String
  public let configuration: String
  public let generator: String
  public let cxxStandard: String
  public let cmakeDefinitions: [String]

  fileprivate init(
    name: String,
    accelerator: String,
    configuration: String,
    generator: String,
    cxxStandard: String,
    cmakeDefinitions: [String]
  ) {
    self.name = name
    self.accelerator = accelerator
    self.configuration = configuration
    self.generator = generator
    self.cxxStandard = cxxStandard
    self.cmakeDefinitions = cmakeDefinitions
  }
}

public enum NemotronCompiledRuntimeStatus: String, Equatable, Sendable {
  case unadmitted
}

public enum NemotronRuntimeAdmissionError: Error, Equatable, Sendable {
  case compiledRuntimeIdentityUnavailable
}

public struct NemotronCompiledRuntimeMetadata: Equatable, Sendable {
  public let status: NemotronCompiledRuntimeStatus
  public let dylibArchiveFileName: String?
  public let dylibArchiveSHA256: String?
  public let dylibArchiveSizeBytes: Int64?
  public let unpackedFileIdentities: [String]

  private init(
    status: NemotronCompiledRuntimeStatus,
    dylibArchiveFileName: String?,
    dylibArchiveSHA256: String?,
    dylibArchiveSizeBytes: Int64?,
    unpackedFileIdentities: [String]
  ) {
    self.status = status
    self.dylibArchiveFileName = dylibArchiveFileName
    self.dylibArchiveSHA256 = dylibArchiveSHA256
    self.dylibArchiveSizeBytes = dylibArchiveSizeBytes
    self.unpackedFileIdentities = unpackedFileIdentities
  }

  public static let unadmitted = NemotronCompiledRuntimeMetadata(
    status: .unadmitted,
    dylibArchiveFileName: nil,
    dylibArchiveSHA256: nil,
    dylibArchiveSizeBytes: nil,
    unpackedFileIdentities: []
  )

  public var isAdmitted: Bool {
    false
  }

  public func requireAdmitted() throws {
    throw NemotronRuntimeAdmissionError.compiledRuntimeIdentityUnavailable
  }
}

public struct NemotronSpeechRuntimeMetadata: Equatable, Sendable {
  public let repository: String
  public let sourceCommit: String
  public let upstreamVersion: String
  public let stableCHeader: String
  public let abi: String
  public let license: String
  public let noticeFiles: [String]
  public let dependencies: [NemotronDependencyPin]
  public let buildPresets: [NemotronBuildPreset]
  public let compiledRuntime: NemotronCompiledRuntimeMetadata

  fileprivate init(
    repository: String,
    sourceCommit: String,
    upstreamVersion: String,
    stableCHeader: String,
    abi: String,
    license: String,
    noticeFiles: [String],
    dependencies: [NemotronDependencyPin],
    buildPresets: [NemotronBuildPreset],
    compiledRuntime: NemotronCompiledRuntimeMetadata
  ) {
    self.repository = repository
    self.sourceCommit = sourceCommit
    self.upstreamVersion = upstreamVersion
    self.stableCHeader = stableCHeader
    self.abi = abi
    self.license = license
    self.noticeFiles = noticeFiles
    self.dependencies = dependencies
    self.buildPresets = buildPresets
    self.compiledRuntime = compiledRuntime
  }

  public static let nemoSpeechCpp = NemotronSpeechRuntimeMetadata(
    repository: "NVIDIA/NeMo-Speech.cpp",
    sourceCommit: "5be7bfb104802131e61fe679b3f1401b27270216",
    upstreamVersion: "1.0.0",
    stableCHeader: "include/nemo_speech/asr.h",
    abi: "nemo-speech-asr 1.0.0",
    license: "Apache-2.0",
    noticeFiles: ["NOTICE", "THIRD_PARTY_NOTICES.md"],
    dependencies: [
      NemotronDependencyPin(name: "ggml", commit: "c03b4e2bcece5134827881af90242086daf75be5"),
      NemotronDependencyPin(name: "llama.cpp", commit: "560445bf34c87356ad0f8d80fb03ec5488850b65"),
      NemotronDependencyPin(name: "riva-common", commit: "71df98266725320a6b6b3a9f32a6da832dc93691f"),
      NemotronDependencyPin(name: "cpp-httplib", commit: "62d899feac3cf9215a55f2b43da250fdd98d2153"),
      NemotronDependencyPin(name: "cppjieba", commit: "b3602bef7d1f67521a61788a74fb5801a0e62cd3"),
      NemotronDependencyPin(name: "flashlight-text", commit: "49e163ab1e7b8108922512c294ab8513b89f404c"),
      NemotronDependencyPin(name: "kenlm", commit: "4cb443e60b7bf2c0ddf3c745378f76cb59e254e5"),
      NemotronDependencyPin(name: "open_jtalk", commit: "1e52154e6677d02dcb4b7f15453e65b5ca1cb6aa"),
    ],
    buildPresets: [
      NemotronBuildPreset(
        name: "CPU Release / Ninja / C++17",
        accelerator: "CPU",
        configuration: "Release",
        generator: "Ninja",
        cxxStandard: "C++17",
        cmakeDefinitions: ["GGML_METAL=OFF"]
      ),
      NemotronBuildPreset(
        name: "Metal Release / Ninja / C++17",
        accelerator: "Metal",
        configuration: "Release",
        generator: "Ninja",
        cxxStandard: "C++17",
        cmakeDefinitions: ["GGML_METAL=ON"]
      ),
    ],
    compiledRuntime: .unadmitted
  )
}

public struct NemotronASRMetadata: Equatable, Sendable {
  public let model: NemotronModelMetadata
  public let sourceRuntime: NemotronSpeechRuntimeMetadata

  private init(
    model: NemotronModelMetadata,
    sourceRuntime: NemotronSpeechRuntimeMetadata
  ) {
    self.model = model
    self.sourceRuntime = sourceRuntime
  }

  public static let candidate = NemotronASRMetadata(
    model: .nemotron35ASRStreaming06B,
    sourceRuntime: .nemoSpeechCpp
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
