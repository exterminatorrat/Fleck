import Foundation
import Testing

@testable import FleckApp

private enum DescriptorValidationFixtures {
  static let neutralAdmitted = makeValidated(
    modelID: "example/neutral",
    languages: ["en-US", "zh-CN"]
  )

  static let admittedASR = makeValidated(
    modelID: "example/asr",
    languages: ["en-US"]
  )

  static func makeValidated(
    modelID: String,
    languages: [String]
  ) -> AdmittedModelDescriptor {
    try! AdmittedModelDescriptor(validating: RawAdmittedModelDescriptor(
      role: .asr,
      modelID: modelID,
      revision: "revision",
      runtimeABI: "runtime",
      conversion: "conversion",
      quantization: "quantized",
      license: "license",
      notices: "notices",
      source: URL(string: "https://example.invalid/repository")!,
      files: [
        .init(
          path: "model.bin",
          byteCount: 4,
          sha256: String(repeating: "a", count: 64)
        )
      ],
      downloadBytes: 4,
      installedBytes: 8,
      languages: languages,
      architectures: ["arm64"]
    ))
  }

  static func raw(
    _ descriptor: AdmittedModelDescriptor
  ) -> RawAdmittedModelDescriptor {
    make(descriptor)
  }

  static func make(
    _ descriptor: AdmittedModelDescriptor,
    role: AdmittedModelRole? = nil,
    modelID: String? = nil,
    revision: String? = nil,
    runtimeABI: String? = nil,
    conversion: String? = nil,
    quantization: String? = nil,
    license: String? = nil,
    notices: String? = nil,
    source: URL? = nil,
    files: [AdmittedModelFile]? = nil,
    downloadBytes: Int64? = nil,
    installedBytes: Int64? = nil,
    languages: [String]? = nil,
    architectures: [String]? = nil
  ) -> RawAdmittedModelDescriptor {
    RawAdmittedModelDescriptor(
      role: role ?? descriptor.role,
      modelID: modelID ?? descriptor.modelID,
      revision: revision ?? descriptor.revision,
      runtimeABI: runtimeABI ?? descriptor.runtimeABI,
      conversion: conversion ?? descriptor.conversion,
      quantization: quantization ?? descriptor.quantization,
      license: license ?? descriptor.license,
      notices: notices ?? descriptor.notices,
      source: source ?? descriptor.source,
      files: files ?? descriptor.files,
      downloadBytes: downloadBytes ?? descriptor.downloadBytes,
      installedBytes: installedBytes ?? descriptor.installedBytes,
      languages: languages ?? descriptor.languages,
      architectures: architectures ?? descriptor.architectures
    )
  }
}

@Test func ordinaryConfigurationShowsBuiltInState() {
  let catalog = AdmittedModelCatalog(
    signedDescriptor: nil,
    hardware: .init(
      architecture: "arm64",
      requestedLanguages: ["en-US"],
      availableBytes: 16_000_000_000
    )
  )
  #expect(catalog.recommendation() == .builtIn)
}

@Test func admittedConfigurationProducesExactlyOneRecommendation() {
  let descriptor = DescriptorValidationFixtures.admittedASR
  let catalog = AdmittedModelCatalog(
    signedDescriptor: descriptor,
    hardware: .init(
      architecture: "arm64",
      requestedLanguages: ["en-US"],
      availableBytes: descriptor.requiredCapacityBytes + 1
    )
  )
  #expect(catalog.recommendation() == .recommended(descriptor))
}

@Test func descriptorRoleIsPartOfImmutableIdentity() throws {
  let asr = DescriptorValidationFixtures.admittedASR
  let cleanup = try AdmittedModelDescriptor(validating: DescriptorValidationFixtures.make(
    asr,
    role: .cleanup
  ))

  #expect(asr.immutableIdentity != cleanup.immutableIdentity)
}

@Test func defaultASRCatalogRejectsCleanupDescriptor() throws {
  let asr = DescriptorValidationFixtures.admittedASR
  let cleanup = try AdmittedModelDescriptor(validating: DescriptorValidationFixtures.make(
    asr,
    role: .cleanup
  ))
  let catalog = AdmittedModelCatalog(
    signedDescriptor: cleanup,
    hardware: .init(
      architecture: cleanup.architectures[0],
      requestedLanguages: [cleanup.languages[0]],
      availableBytes: cleanup.requiredCapacityBytes
    )
  )

  #expect(catalog.recommendation() == .builtIn)
}

@Test func cleanupCatalogAcceptsOnlyCleanupDescriptor() throws {
  let asr = DescriptorValidationFixtures.admittedASR
  let cleanup = try AdmittedModelDescriptor(validating: DescriptorValidationFixtures.make(
    asr,
    role: .cleanup
  ))
  let hardware = AdmittedModelHardwareProfile(
    architecture: cleanup.architectures[0],
    requestedLanguages: [cleanup.languages[0]],
    availableBytes: cleanup.requiredCapacityBytes
  )

  let cleanupCatalog = AdmittedModelCatalog(
    signedDescriptor: cleanup,
    hardware: hardware,
    expectedRole: .cleanup
  )
  let mismatchedCatalog = AdmittedModelCatalog(
    signedDescriptor: asr,
    hardware: hardware,
    expectedRole: .cleanup
  )

  #expect(cleanupCatalog.recommendation() == .recommended(cleanup))
  #expect(mismatchedCatalog.recommendation() == .builtIn)
}

@Test func mixedRequestedLanguagesDoNotPassAnEnglishOnlyDescriptor() {
  let descriptor = DescriptorValidationFixtures.admittedASR
  #expect(descriptor.languages == ["en-US"])
  let catalog = AdmittedModelCatalog(
    signedDescriptor: descriptor,
    hardware: .init(
      architecture: descriptor.architectures[0],
      requestedLanguages: ["en-US", "zh-CN"],
      availableBytes: descriptor.requiredCapacityBytes
    )
  )
  #expect(catalog.recommendation() == .builtIn)
}

@Test func unsupportedHardwareFallsBackToBuiltIn() {
  let catalog = AdmittedModelCatalog(
    signedDescriptor: DescriptorValidationFixtures.admittedASR,
    hardware: .init(
      architecture: "x86_64",
      requestedLanguages: ["zh-CN"],
      availableBytes: 1
    )
  )
  #expect(catalog.recommendation() == .builtIn)
}

@Test func spaceAboveDownloadBytesButBelowStagingRequirementFallsBackToBuiltIn() {
  let descriptor = DescriptorValidationFixtures.neutralAdmitted
  let availableBytes = descriptor.downloadBytes + 1
  #expect(availableBytes > descriptor.downloadBytes)
  #expect(availableBytes < descriptor.requiredCapacityBytes)
  let catalog = AdmittedModelCatalog(
    signedDescriptor: descriptor,
    hardware: .init(
      architecture: descriptor.architectures[0],
      requestedLanguages: [descriptor.languages[0]],
      availableBytes: availableBytes
    )
  )
  #expect(catalog.recommendation() == .builtIn)
}

@Test func invalidSignedDescriptorInputsAreRejected() {
  let valid = DescriptorValidationFixtures.neutralAdmitted
  #expect(throws: AdmittedModelDescriptorError.emptyIdentity) {
    _ = try AdmittedModelDescriptor(validating: DescriptorValidationFixtures.make(valid, modelID: ""))
  }
  #expect(throws: AdmittedModelDescriptorError.emptyRevision) {
    _ = try AdmittedModelDescriptor(validating: DescriptorValidationFixtures.make(valid, revision: ""))
  }
  #expect(throws: AdmittedModelDescriptorError.emptyLicense) {
    _ = try AdmittedModelDescriptor(validating: DescriptorValidationFixtures.make(valid, license: ""))
  }
  #expect(throws: AdmittedModelDescriptorError.emptyRuntimeABI) {
    _ = try AdmittedModelDescriptor(validating: DescriptorValidationFixtures.make(valid, runtimeABI: "   "))
  }
  #expect(throws: AdmittedModelDescriptorError.emptyConversion) {
    _ = try AdmittedModelDescriptor(validating: DescriptorValidationFixtures.make(valid, conversion: "\t"))
  }
  #expect(throws: AdmittedModelDescriptorError.emptyQuantization) {
    _ = try AdmittedModelDescriptor(validating: DescriptorValidationFixtures.make(valid, quantization: "\n"))
  }
  let invalidSources: [URL] = [
    URL(string: "relative/repository")!,
    URL(string: "http://example.invalid/repository")!,
    URL(string: "https://user:pass@example.invalid/repository")!,
    URL(string: "https://example.invalid/repository#fragment")!,
    URL(string: "https://example.invalid/repository/../escape")!,
    URL(string: "https://example.invalid/repository/%2e%2e/escape")!,
    URL(string: "https://example.invalid/repository/%252e%252e/escape")!,
    URL(string: "https://example.invalid/repository?download=true")!
  ]
  for source in invalidSources {
    #expect(throws: AdmittedModelDescriptorError.invalidSource) {
      _ = try AdmittedModelDescriptor(validating: DescriptorValidationFixtures.make(valid, source: source))
    }
  }
  #expect(throws: AdmittedModelDescriptorError.unsafePath("../escape.bin")) {
    _ = try AdmittedModelDescriptor(validating: DescriptorValidationFixtures.make(
      valid,
      files: [ .init(path: "../escape.bin", byteCount: 4, sha256: String(repeating: "a", count: 64)) ],
      downloadBytes: 4,
      installedBytes: 4
    ))
  }
  for path in [
    "", "/absolute.bin", "%2fabsolute.bin", ".", "..", "a//b",
    "a/./b", "a/../b", "a\\b", "a\\..\\b", "a/%2e%2e/b",
    "a/%252e%252e/b", "%6dodel.bin"
  ] {
    #expect(throws: AdmittedModelDescriptorError.unsafePath(path)) {
      _ = try AdmittedModelDescriptor(validating: DescriptorValidationFixtures.make(
        valid,
        files: [ .init(
          path: path,
          byteCount: 4,
          sha256: String(repeating: "a", count: 64)
        ) ],
        downloadBytes: 4,
        installedBytes: 4
      ))
    }
  }
  #expect(throws: AdmittedModelDescriptorError.duplicateFilePath("model.bin")) {
    _ = try AdmittedModelDescriptor(validating: DescriptorValidationFixtures.make(
      valid,
      files: [
        .init(path: "model.bin", byteCount: 4, sha256: String(repeating: "a", count: 64)),
        .init(path: "model.bin", byteCount: 4, sha256: String(repeating: "b", count: 64))
      ],
      downloadBytes: 8,
      installedBytes: 8
    ))
  }
  #expect(throws: AdmittedModelDescriptorError.invalidByteCount) {
    _ = try AdmittedModelDescriptor(validating: DescriptorValidationFixtures.make(valid, downloadBytes: -1))
  }
  #expect(throws: AdmittedModelDescriptorError.invalidChecksum("abc")) {
    _ = try AdmittedModelDescriptor(validating: DescriptorValidationFixtures.make(
      valid,
      files: [ .init(path: "model.bin", byteCount: 4, sha256: "abc") ],
      downloadBytes: 4,
      installedBytes: 4
    ))
  }
  #expect(throws: AdmittedModelDescriptorError.aggregateMismatch) {
    _ = try AdmittedModelDescriptor(validating: DescriptorValidationFixtures.make(valid, installedBytes: 1))
  }
  #expect(throws: AdmittedModelDescriptorError.requiredCapacityOverflow) {
    _ = try AdmittedModelDescriptor(validating: DescriptorValidationFixtures.make(
      valid,
      downloadBytes: 1,
      installedBytes: Int64.max
    ))
  }
  #expect(throws: AdmittedModelDescriptorError.fileAggregateOverflow) {
    _ = try AdmittedModelDescriptor(validating: DescriptorValidationFixtures.make(
      valid,
      files: [
        .init(path: "one.bin", byteCount: Int64.max, sha256: String(repeating: "a", count: 64)),
        .init(path: "two.bin", byteCount: 1, sha256: String(repeating: "b", count: 64))
      ],
      downloadBytes: Int64.max / 2,
      installedBytes: Int64.max / 2
    ))
  }
  #expect(throws: AdmittedModelDescriptorError.emptySupport) {
    _ = try AdmittedModelDescriptor(validating: DescriptorValidationFixtures.make(valid, languages: [], architectures: []))
  }
}

@Test func descriptorStoresCanonicalTrimmedIdentityFields() throws {
  let descriptor = try AdmittedModelDescriptor(validating: DescriptorValidationFixtures.make(
    DescriptorValidationFixtures.neutralAdmitted,
    modelID: " model ",
    revision: " revision ",
    runtimeABI: " runtime ",
    conversion: " conversion ",
    quantization: " quantized ",
    license: " license "
  ))
  #expect(descriptor.modelID == "model")
  #expect(descriptor.revision == "revision")
  #expect(descriptor.runtimeABI == "runtime")
  #expect(descriptor.conversion == "conversion")
  #expect(descriptor.quantization == "quantized")
  #expect(descriptor.license == "license")
}

@Test func doubleEncodedRepositoryTraversalIsRejected() {
  #expect(throws: AdmittedModelDescriptorError.invalidSource) {
    _ = try AdmittedModelDescriptor(validating: DescriptorValidationFixtures.make(
      DescriptorValidationFixtures.neutralAdmitted,
      source: URL(string: "https://example.invalid/repository/%252e%252e/escape")!
    ))
  }
}
