#if os(macOS) && CLEAN_DICTATION_ENHANCED_CANDIDATE
import Foundation

struct GemmaCleanupModelQualification: Equatable, Sendable {
  let family: String
  let identity: AdmittedModelImmutableIdentity
  let resources: LocalModelResourceEnvelope
  let license: LocalModelLicenseState
  let cleanupEvidence: LocalModelEvidenceTier
  let smartFilingEvidence: LocalModelEvidenceTier?
  let admission: LocalModelAdmissionState
}

enum GemmaCleanup8BitModelSpecification {
  static let family = "Gemma3Text"
  static let modelID = "mlx-community/gemma-3-1b-it-8bit"
  static let revision = "7b963136f21d05ca8b367c93a9c47a7944ad281a"
  static let sourceRepository =
    URL(string: "https://huggingface.co/mlx-community/gemma-3-1b-it-8bit")!
  static let localRepositoryName = "gemma-3-1b-it-8bit"
  static let conversion = "MLX"
  static let quantization = "standard8bit/group64"
  static let license = "Gemma Terms of Use"
  static let notices =
    "This custom-licensed third-party model is not covered by Fleck's MPL-2.0 license. Review the Google Gemma Terms of Use before installation: https://ai.google.dev/gemma/terms. Text cleanup and Smart Capture filing must use the same selected model through the existing Gemma cleanup gate."
  static let manifest = EnhancedModelManifest(
    schemaVersion: 1,
    modelID: "mlx-community/gemma-3-1b-it-8bit",
    revision: "7b963136f21d05ca8b367c93a9c47a7944ad281a",
    totalByteCount: 1_422_735_116,
    files: [
      .init(
        path: ".gitattributes",
        byteCount: 1_570,
        sha256: "34448b82c17d60fec9b65b1f093c115ddbaadc04beb1b0140b6bfed2e012a930"
      ),
      .init(
        path: "README.md",
        byteCount: 1_168,
        sha256: "e2d846a168ab74055ec08627f0f2c7c55a85f926dfa9774d869c50bf2a9895d8"
      ),
      .init(
        path: "added_tokens.json",
        byteCount: 35,
        sha256: "50b2f405ba56a26d4913fd772089992252d7f942123cc0a034d96424221ba946"
      ),
      .init(
        path: "config.json",
        byteCount: 1_098,
        sha256: "11609c5a184ab6c9dfc05cbff358e91b14116f150676997cbe5e0642a5102296"
      ),
      .init(
        path: "model.safetensors",
        byteCount: 1_383_448_829,
        sha256: "c0795eea60413fc455178c1d81f78bcf382af17ca530da4ddcf3838bc63746e8"
      ),
      .init(
        path: "model.safetensors.index.json",
        byteCount: 50_543,
        sha256: "b29b2ad4ed2d6e49e18c27d16f4762de972fc6ae7ebc54c720368db7e3cd6c58"
      ),
      .init(
        path: "preprocessor_config.json",
        byteCount: 570,
        sha256: "f688d6bb20c5017601c4011de7ca656da8485b540b05013efdaf986c0fcc918d"
      ),
      .init(
        path: "special_tokens_map.json",
        byteCount: 662,
        sha256: "2f7b0adf4fb469770bb1490e3e35df87b1dc578246c5e7e6fc76ecf33213a397"
      ),
      .init(
        path: "tokenizer.json",
        byteCount: 33_384_568,
        sha256: "4667f2089529e8e7657cfb6d1c19910ae71ff5f28aa7ab2ff2763330affad795"
      ),
      .init(
        path: "tokenizer.model",
        byteCount: 4_689_074,
        sha256: "1299c11d7cf632ef3b4e11937501358ada021bbdf7c47638d13c0ee982f2e79c"
      ),
      .init(
        path: "tokenizer_config.json",
        byteCount: 1_156_999,
        sha256: "bfe25c2735e395407beb78456ea9a6984a1f00d8c16fa04a8b75f2a614cf53e1"
      ),
    ]
  )
  static let rawDescriptor = RawAdmittedModelDescriptor(
    role: .cleanup,
    modelID: modelID,
    revision: revision,
    runtimeABI: GemmaCleanupTestConfiguration.runtimeABI,
    conversion: conversion,
    quantization: quantization,
    license: license,
    notices: notices,
    source: sourceRepository,
    files: manifest.files.map {
      AdmittedModelFile(path: $0.path, byteCount: $0.byteCount, sha256: $0.sha256)
    },
    downloadBytes: manifest.totalByteCount,
    installedBytes: manifest.totalByteCount,
    languages: GemmaCleanupTestConfiguration.languages,
    architectures: GemmaCleanupTestConfiguration.architectures
  )
}

enum GemmaCleanupModelSelection {
  static func resolveQualifiedAlternative(
    pendingModelID: String?,
    role: AdmittedModelRole,
    qualification: GemmaCleanupModelQualification?,
    architectureSupported: Bool,
    physicalMemoryBytes: UInt64,
    availableDiskBytes: Int64
  ) -> AdmittedModelDescriptor? {
    guard pendingModelID == GemmaCleanup8BitModelSpecification.modelID,
          role == .cleanup,
          architectureSupported,
          let qualification,
          qualification.family == GemmaCleanup8BitModelSpecification.family,
          qualification.license == .gemmaTermsReviewed,
          qualification.cleanupEvidence == .fleckQualified,
          qualification.smartFilingEvidence == .some(.fleckQualified),
          qualification.admission == .notAdmitted else {
      return nil
    }

    let resources = qualification.resources
    guard resources.applicability == .measured,
          resources.minimumRAMBytes > 0,
          resources.workingRAMBytes >= resources.minimumRAMBytes,
          resources.storageBytes > 0,
          let workingRAMBytes = UInt64(exactly: resources.workingRAMBytes),
          physicalMemoryBytes >= workingRAMBytes,
          let descriptor = try? AdmittedModelDescriptor(
            validating: GemmaCleanup8BitModelSpecification.rawDescriptor
          ),
          descriptor.architectures.contains("arm64"),
          qualification.identity == descriptor.immutableIdentity,
          resources.storageBytes >= descriptor.installedBytes,
          availableDiskBytes >= max(
            resources.storageBytes,
            descriptor.requiredCapacityBytes
          ) else {
      return nil
    }
    return descriptor
  }
}
#endif
