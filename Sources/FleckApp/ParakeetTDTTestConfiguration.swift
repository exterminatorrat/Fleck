#if os(macOS) && CLEAN_DICTATION_ENHANCED_CANDIDATE
import Foundation

enum ParakeetTDTTestConfigurationError: Error, Equatable {
  case missingResource(String)
  case unreadableResource(String)
  case invalidManifest
  case unexpectedManifestIdentity
  case invalidSourceRepository
}

enum ParakeetTDTTestConfiguration {
  private static let sourceRepositoryString =
    "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml"
  private static let expectedModelID =
    "FluidInference/parakeet-tdt-0.6b-v2-coreml"
  static let localRepositoryName = "parakeet-tdt-0.6b-v2"
  private static let expectedRevision =
    "ee09c569f73759e6d44c9bd16766f477b2b36d39"
  private static let expectedManifestTotal: Int64 = 464_413_247
  private static let expectedManifestFileCount = 21

  static let runtimeABI =
    "FluidAudio/v0.15.5@19600a485baa4998812e4654b70d2bab8f2c9949"
  static let conversion = "CoreML"
  static let quantization = "FP16"
  static let license = "CC-BY-4.0"
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
          manifest.files.count == expectedManifestFileCount else {
      throw ParakeetTDTTestConfigurationError.unexpectedManifestIdentity
    }
    guard let sourceRepository = URL(string: sourceRepositoryString) else {
      throw ParakeetTDTTestConfigurationError.invalidSourceRepository
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
      role: .asr,
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
      name: "EnhancedModelManifest",
      fileExtension: "json",
      applicationResourceRoot: applicationResourceRoot,
      moduleBundle: moduleBundle
    )
    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch {
      throw ParakeetTDTTestConfigurationError.unreadableResource(url.lastPathComponent)
    }
    do {
      return try JSONDecoder().decode(EnhancedModelManifest.self, from: data)
    } catch {
      throw ParakeetTDTTestConfigurationError.invalidManifest
    }
  }

  private static func loadNotices(
    applicationResourceRoot: URL?,
    moduleBundle: Bundle?
  ) throws -> String {
    let url = try resourceURL(
      name: "ThirdPartyNotices",
      fileExtension: "md",
      applicationResourceRoot: applicationResourceRoot,
      moduleBundle: moduleBundle
    )
    do {
      return try String(contentsOf: url, encoding: .utf8)
    } catch {
      throw ParakeetTDTTestConfigurationError.unreadableResource(url.lastPathComponent)
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
      throw ParakeetTDTTestConfigurationError.missingResource(resource)
    } catch {
      throw ParakeetTDTTestConfigurationError.unreadableResource(
        "\(name).\(fileExtension)"
      )
    }
  }
}
#endif
