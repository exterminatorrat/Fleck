#if os(macOS) && CLEAN_DICTATION_ENHANCED_CANDIDATE
import Foundation

enum GemmaCleanupTestConfigurationError: Error, Equatable {
  case missingResource(String)
  case unreadableResource(String)
  case invalidManifest
  case unexpectedManifestIdentity
  case invalidSourceRepository
}

enum GemmaCleanupTestConfiguration {
  private static let sourceRepositoryString =
    "https://huggingface.co/mlx-community/gemma-3-1b-it-qat-4bit"
  private static let expectedModelID =
    "mlx-community/gemma-3-1b-it-qat-4bit"
  private static let expectedRevision =
    "15fed4eafb456c6fcb2a1165f19ac609670ed14b"
  private static let expectedManifestTotal: Int64 = 771_863_021
  private static let expectedManifestFileCount = 10
  private static let expectedManifestFiles = [
    EnhancedModelFile(
      path: ".gitattributes",
      byteCount: 1_570,
      sha256: "34448b82c17d60fec9b65b1f093c115ddbaadc04beb1b0140b6bfed2e012a930"
    ),
    EnhancedModelFile(
      path: "README.md",
      byteCount: 1_202,
      sha256: "ef1b7148ef260594ac05c36885f6471182f78416ee0d49c76851e7ebe56f4009"
    ),
    EnhancedModelFile(
      path: "added_tokens.json",
      byteCount: 35,
      sha256: "50b2f405ba56a26d4913fd772089992252d7f942123cc0a034d96424221ba946"
    ),
    EnhancedModelFile(
      path: "config.json",
      byteCount: 1_105,
      sha256: "eb080baebedaa32151a71988721a64f0be067fc6cd7e20ca16ba11231f822533"
    ),
    EnhancedModelFile(
      path: "model.safetensors",
      byteCount: 732_577_304,
      sha256: "b6010f6b03a83f973ca8708eb5784d5b0f80c0e7e9143dbb4c95d0eefe39c837"
    ),
    EnhancedModelFile(
      path: "model.safetensors.index.json",
      byteCount: 50_542,
      sha256: "b479eca1f14de16218fc5f45aa270d008944cd3f261f78e90f9b718c8857faef"
    ),
    EnhancedModelFile(
      path: "special_tokens_map.json",
      byteCount: 662,
      sha256: "2f7b0adf4fb469770bb1490e3e35df87b1dc578246c5e7e6fc76ecf33213a397"
    ),
    EnhancedModelFile(
      path: "tokenizer.json",
      byteCount: 33_384_568,
      sha256: "4667f2089529e8e7657cfb6d1c19910ae71ff5f28aa7ab2ff2763330affad795"
    ),
    EnhancedModelFile(
      path: "tokenizer.model",
      byteCount: 4_689_074,
      sha256: "1299c11d7cf632ef3b4e11937501358ada021bbdf7c47638d13c0ee982f2e79c"
    ),
    EnhancedModelFile(
      path: "tokenizer_config.json",
      byteCount: 1_156_959,
      sha256: "be9d72bdf5021aa82d67c3cc60cb0f8ddcc759d4d3f05eb129b9fcc345fc94b7"
    ),
  ]

  static let localRepositoryName = "gemma-3-1b-it-qat-4bit"
  static let mlxSwiftLMRevision =
    "bd4b7434e6bdb588c7ef55706ff8904cb7fd4c57"
  static let mlxSwiftVersion = "0.31.6"
  static let swiftTransformersVersion = "1.3.0"
  static let runtimeABI =
    "mlx-swift-lm@\(mlxSwiftLMRevision);mlx-swift@\(mlxSwiftVersion);swift-transformers@\(swiftTransformersVersion)"
  static let conversion = "MLX"
  static let quantization = "QAT 4-bit"
  static let license = "Gemma Terms of Use"
  static let languages = ["en"]
  static let architectures = ["arm64"]

  @MainActor
  static func make(
    admittedBaseRoot: URL,
    capacityProvider: @escaping @Sendable () throws -> Int64 = {
      try EnhancedModelManager.liveAvailableCapacity()
    },
    architectureProvider: @escaping @Sendable () -> Bool = {
      EnhancedModelManager.isAppleSilicon()
    },
    modelMutationWillBegin: @escaping @Sendable () async -> Void = {},
    startup: @escaping @MainActor () async throws -> Void,
    calibrate: @escaping @MainActor () async throws -> Void,
    applicationResourceRoot: URL? = Bundle.main.resourceURL,
    moduleBundle: Bundle? = FleckAppResourceBundle.defaultModuleBundle()
  ) throws -> AdmittedModelSignedConfiguration {
    let manifest = try loadManifest(
      applicationResourceRoot: applicationResourceRoot,
      moduleBundle: moduleBundle
    )
    guard manifest.schemaVersion == 1,
          manifest.modelID == expectedModelID,
          manifest.revision == expectedRevision,
          manifest.totalByteCount == expectedManifestTotal,
          manifest.files.count == expectedManifestFileCount,
          manifest.files == expectedManifestFiles else {
      throw GemmaCleanupTestConfigurationError.unexpectedManifestIdentity
    }
    guard let sourceRepository = URL(string: sourceRepositoryString) else {
      throw GemmaCleanupTestConfigurationError.invalidSourceRepository
    }
    let notices = try loadNotices(
      applicationResourceRoot: applicationResourceRoot,
      moduleBundle: moduleBundle
    )
    let files = manifest.files.map {
      AdmittedModelFile(
        path: $0.path,
        byteCount: $0.byteCount,
        sha256: $0.sha256
      )
    }
    let rawDescriptor = RawAdmittedModelDescriptor(
      role: .cleanup,
      modelID: manifest.modelID,
      revision: manifest.revision,
      runtimeABI: runtimeABI,
      conversion: conversion,
      quantization: quantization,
      license: license,
      notices: notices,
      source: sourceRepository,
      files: files,
      downloadBytes: manifest.totalByteCount,
      installedBytes: manifest.totalByteCount,
      languages: languages,
      architectures: architectures
    )
    let descriptor = try AdmittedModelDescriptor(validating: rawDescriptor)
    let artifactIdentity = EnhancedModelArtifactIdentity(
      role: .cleanup,
      sourceRepository: sourceRepository,
      modelID: descriptor.modelID,
      revision: descriptor.revision,
      license: descriptor.license,
      runtimeABI: descriptor.runtimeABI,
      conversion: descriptor.conversion,
      quantization: descriptor.quantization,
      files: files,
      downloadBytes: manifest.totalByteCount,
      installedBytes: descriptor.installedBytes,
      requiredCapacityBytes: descriptor.requiredCapacityBytes
    )
    try AdmittedModelArtifactBinding.validate(
      descriptor: descriptor,
      artifact: artifactIdentity,
      manifest: manifest
    )

    let architectureSupported = architectureProvider()
    let hardware = AdmittedModelHardwareProfile(
      architecture: architectureSupported ? "arm64" : "x86_64",
      requestedLanguages: Set(languages),
      availableBytes: try capacityProvider()
    )
    let manager = try EnhancedModelManager(
      admittedBaseRoot: admittedBaseRoot,
      descriptor: descriptor,
      manifest: manifest,
      artifactIdentity: artifactIdentity,
      trustedManifests: [manifest],
      capacityProvider: capacityProvider,
      architectureProvider: { architectureSupported },
      cleanupWillBegin: modelMutationWillBegin,
      removalWillBegin: modelMutationWillBegin,
      localRepositoryName: localRepositoryName
    )
    return AdmittedModelSignedConfiguration(
      rawDescriptor: rawDescriptor,
      hardware: hardware,
      manager: manager,
      startup: startup,
      calibrate: calibrate
    )
  }

  private static func loadManifest(
    applicationResourceRoot: URL?,
    moduleBundle: Bundle?
  ) throws -> EnhancedModelManifest {
    let url = try resourceURL(
      name: "GemmaCleanupModelManifest",
      fileExtension: "json",
      applicationResourceRoot: applicationResourceRoot,
      moduleBundle: moduleBundle
    )
    do {
      return try JSONDecoder().decode(
        EnhancedModelManifest.self,
        from: Data(contentsOf: url)
      )
    } catch is DecodingError {
      throw GemmaCleanupTestConfigurationError.invalidManifest
    } catch {
      throw GemmaCleanupTestConfigurationError.unreadableResource(
        url.lastPathComponent
      )
    }
  }

  private static func loadNotices(
    applicationResourceRoot: URL?,
    moduleBundle: Bundle?
  ) throws -> String {
    let url = try resourceURL(
      name: "GemmaCleanupNotice",
      fileExtension: "md",
      applicationResourceRoot: applicationResourceRoot,
      moduleBundle: moduleBundle
    )
    do {
      return try String(contentsOf: url, encoding: .utf8)
    } catch {
      throw GemmaCleanupTestConfigurationError.unreadableResource(
        url.lastPathComponent
      )
    }
  }

  private static func resourceURL(
    name: String,
    fileExtension: String,
    applicationResourceRoot: URL?,
    moduleBundle: Bundle?
  ) throws -> URL {
    do {
      return try FleckAppResourceBundle.url(
        forResource: name,
        withExtension: fileExtension,
        applicationResourceRoot: applicationResourceRoot,
        moduleBundle: moduleBundle
      )
    } catch FleckAppResourceBundleError.missingResource(let resource) {
      throw GemmaCleanupTestConfigurationError.missingResource(resource)
    } catch {
      throw GemmaCleanupTestConfigurationError.unreadableResource(
        "\(name).\(fileExtension)"
      )
    }
  }
}
#endif
