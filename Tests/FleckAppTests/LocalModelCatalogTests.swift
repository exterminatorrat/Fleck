import Foundation
import Testing

@testable import FleckApp

private enum LocalCatalogFixtures {
  static let revisionA = String(repeating: "a", count: 40)
  static let revisionB = String(repeating: "b", count: 40)
  static let checksumA = String(repeating: "1", count: 64)
  static let checksumB = String(repeating: "2", count: 64)

  static func artifact(
    modelID: String = "example/parakeet",
    revision: String = revisionA,
    artifactURL: URL? = nil,
    runtimeABI: String = "runtime-a",
    requiredPaths: [String] = ["model.bin"],
    files: [RawLocalModelArtifactFile] = [
      .init(path: "model.bin", byteCount: 4, sha256: checksumA)
    ],
    downloadBytes: Int64 = 4,
    installedBytes: Int64 = 8
  ) -> RawLocalModelArtifactIdentity {
    .init(
      sourceRepository: URL(string: "https://example.invalid/repository")!,
      artifactURL: artifactURL,
      modelID: modelID,
      revision: revision,
      runtimeABI: runtimeABI,
      conversion: "native",
      quantization: "fp16",
      requiredPaths: requiredPaths,
      files: files,
      downloadBytes: downloadBytes,
      installedBytes: installedBytes
    )
  }

  static func profile(
    family: String = "parakeetTDT",
    profileID: String = "parakeet.en.dictation",
    role: String = "dictation",
    distribution: String = "fleckManaged",
    artifact: RawLocalModelArtifactIdentity? = artifact(),
    configurationABI: String = "writing-v1",
    architectures: [String] = ["arm64"],
    minimumOSMajor: Int = 14,
    maximumOSMajor: Int = 16,
    languages: [String] = ["en"],
    minimumRAMBytes: Int64 = 4,
    workingRAMBytes: Int64 = 8,
    storageBytes: Int64 = 8,
    license: String = "ccBy40Reviewed",
    evidence: String = "identityVerified",
    admission: String = "notAdmitted",
    claimScope: String = "general",
    speakerCohort: String = "generalAdult",
    acousticCohort: String = "general",
    buildCapability: String = "developmentQuality"
  ) -> RawLocalModelProfile {
    .init(
      family: family,
      profileID: profileID,
      role: role,
      distribution: distribution,
      artifact: artifact,
      compatibility: .init(
        configurationABI: configurationABI,
        architectures: architectures,
        minimumOSMajor: minimumOSMajor,
        maximumOSMajor: maximumOSMajor,
        languages: languages
      ),
      resources: .init(
        minimumRAMBytes: minimumRAMBytes,
        workingRAMBytes: workingRAMBytes,
        storageBytes: storageBytes
      ),
      license: license,
      evidence: evidence,
      admission: admission,
      claimScope: claimScope,
      speakerCohort: speakerCohort,
      acousticCohort: acousticCohort,
      buildCapability: buildCapability
    )
  }

  static func cleanup(
    artifact: RawLocalModelArtifactIdentity = artifact(
      modelID: "example/gemma",
      revision: revisionB,
      runtimeABI: "runtime-b",
      requiredPaths: ["weights.bin"],
      files: [.init(path: "weights.bin", byteCount: 6, sha256: checksumB)],
      downloadBytes: 6,
      installedBytes: 10
    )
  ) -> RawLocalModelProfile {
    profile(
      family: "gemma3",
      profileID: "gemma.en.cleanup",
      role: "cleanup",
      artifact: artifact,
      storageBytes: 10,
      license: "gemmaTermsReviewed"
    )
  }

  static func configuration(
    profiles: [RawLocalModelProfile]? = nil
  ) -> RawLocalModelConfiguration {
    .init(
      key: "parakeet-gemma.en.v1",
      requiredRoles: ["dictation", "cleanup"],
      profiles: profiles ?? [profile(), cleanup()]
    )
  }

  static func environment(
    architecture: LocalModelHardwareArchitecture = .arm64,
    osMajor: Int = 15,
    languages: Set<String> = ["en"],
    buildCapability: LocalModelBuildCapability = .developmentQuality
  ) -> LocalModelBuildEnvironment {
    .init(
      architecture: architecture,
      osMajor: osMajor,
      languages: languages,
      buildCapability: buildCapability
    )
  }

  static func replacing(
    _ source: RawLocalModelProfile,
    family: String? = nil,
    profileID: String? = nil,
    role: String? = nil,
    distribution: String? = nil,
    configurationABI: String? = nil,
    architectures: [String]? = nil,
    minimumOSMajor: Int? = nil,
    maximumOSMajor: Int? = nil,
    languages: [String]? = nil,
    license: String? = nil,
    evidence: String? = nil,
    admission: String? = nil,
    claimScope: String? = nil,
    speakerCohort: String? = nil,
    acousticCohort: String? = nil,
    buildCapability: String? = nil
  ) -> RawLocalModelProfile {
    profile(
      family: family ?? source.family,
      profileID: profileID ?? source.profileID,
      role: role ?? source.role,
      distribution: distribution ?? source.distribution,
      artifact: source.artifact,
      configurationABI: configurationABI ?? source.compatibility.configurationABI,
      architectures: architectures ?? source.compatibility.architectures,
      minimumOSMajor: minimumOSMajor ?? source.compatibility.minimumOSMajor,
      maximumOSMajor: maximumOSMajor ?? source.compatibility.maximumOSMajor,
      languages: languages ?? source.compatibility.languages,
      minimumRAMBytes: source.resources.minimumRAMBytes,
      workingRAMBytes: source.resources.workingRAMBytes,
      storageBytes: source.resources.storageBytes,
      license: license ?? source.license,
      evidence: evidence ?? source.evidence,
      admission: admission ?? source.admission,
      claimScope: claimScope ?? source.claimScope,
      speakerCohort: speakerCohort ?? source.speakerCohort,
      acousticCohort: acousticCohort ?? source.acousticCohort,
      buildCapability: buildCapability ?? source.buildCapability
    )
  }

  static func descriptor(
    role: AdmittedModelRole,
    modelID: String,
    revision: String,
    runtimeABI: String,
    license: String,
    path: String,
    byteCount: Int64,
    checksum: String
  ) throws -> AdmittedModelDescriptor {
    try AdmittedModelDescriptor(validating: .init(
      role: role,
      modelID: modelID,
      revision: revision,
      runtimeABI: runtimeABI,
      conversion: "native",
      quantization: "exact",
      license: license,
      notices: "reviewed notice",
      source: URL(string: "https://example.invalid/\(modelID)")!,
      files: [.init(path: path, byteCount: byteCount, sha256: checksum)],
      downloadBytes: byteCount,
      installedBytes: byteCount,
      languages: ["en"],
      architectures: ["arm64"]
    ))
  }
}

@Suite struct LocalModelCatalogTests {
  @Test func catalogRejectsMutableRevisionAndArtifactURL() {
    let mutable = LocalCatalogFixtures.profile(
      artifact: LocalCatalogFixtures.artifact(revision: "main")
    )
    #expect(throws: LocalModelCatalogError.mutableRevision("main")) {
      _ = try LocalModelCatalog.validate(
        LocalCatalogFixtures.configuration(profiles: [mutable, LocalCatalogFixtures.cleanup()]),
        for: LocalCatalogFixtures.environment()
      )
    }

    let directURL = URL(string: "https://example.invalid/model.bin")!
    let downloadable = LocalCatalogFixtures.profile(
      artifact: LocalCatalogFixtures.artifact(artifactURL: directURL)
    )
    #expect(throws: LocalModelCatalogError.artifactURLNotAllowed(directURL)) {
      _ = try LocalModelCatalog.validate(
        LocalCatalogFixtures.configuration(profiles: [downloadable, LocalCatalogFixtures.cleanup()]),
        for: LocalCatalogFixtures.environment()
      )
    }
  }

  @Test func catalogRejectsUnsafeArtifactPathsAndManifestCollisions() {
    let unsafe = LocalCatalogFixtures.artifact(
      requiredPaths: ["../model.bin"],
      files: [.init(path: "../model.bin", byteCount: 4, sha256: LocalCatalogFixtures.checksumA)]
    )
    #expect(throws: LocalModelCatalogError.unsafeArtifactPath("../model.bin")) {
      _ = try LocalModelCatalog.validate(
        LocalCatalogFixtures.configuration(profiles: [
          LocalCatalogFixtures.profile(artifact: unsafe), LocalCatalogFixtures.cleanup()
        ]),
        for: LocalCatalogFixtures.environment()
      )
    }

    let colliding = LocalCatalogFixtures.artifact(
      requiredPaths: ["Model.bin", "model.bin"],
      files: [
        .init(path: "Model.bin", byteCount: 2, sha256: LocalCatalogFixtures.checksumA),
        .init(path: "model.bin", byteCount: 2, sha256: LocalCatalogFixtures.checksumB)
      ]
    )
    #expect(throws: LocalModelCatalogError.artifactPathCollision("model.bin")) {
      _ = try LocalModelCatalog.validate(
        LocalCatalogFixtures.configuration(profiles: [
          LocalCatalogFixtures.profile(artifact: colliding), LocalCatalogFixtures.cleanup()
        ]),
        for: LocalCatalogFixtures.environment()
      )
    }
  }

  @Test func catalogRejectsMissingAndExtraArtifactFiles() {
    let missing = LocalCatalogFixtures.artifact(requiredPaths: ["model.bin", "tokenizer.json"])
    #expect(throws: LocalModelCatalogError.artifactSetMismatch) {
      _ = try LocalModelCatalog.validate(
        LocalCatalogFixtures.configuration(profiles: [
          LocalCatalogFixtures.profile(artifact: missing), LocalCatalogFixtures.cleanup()
        ]),
        for: LocalCatalogFixtures.environment()
      )
    }

    let extra = LocalCatalogFixtures.artifact(requiredPaths: [])
    #expect(throws: LocalModelCatalogError.artifactSetMismatch) {
      _ = try LocalModelCatalog.validate(
        LocalCatalogFixtures.configuration(profiles: [
          LocalCatalogFixtures.profile(artifact: extra), LocalCatalogFixtures.cleanup()
        ]),
        for: LocalCatalogFixtures.environment()
      )
    }
  }

  @Test func catalogRejectsCheckedByteArithmeticOverflow() {
    let aggregateOverflow = LocalCatalogFixtures.artifact(
      requiredPaths: ["one.bin", "two.bin"],
      files: [
        .init(path: "one.bin", byteCount: Int64.max, sha256: LocalCatalogFixtures.checksumA),
        .init(path: "two.bin", byteCount: 1, sha256: LocalCatalogFixtures.checksumB)
      ],
      downloadBytes: Int64.max,
      installedBytes: Int64.max
    )
    #expect(throws: LocalModelCatalogError.byteCountOverflow) {
      _ = try LocalModelCatalog.validate(
        LocalCatalogFixtures.configuration(profiles: [
          LocalCatalogFixtures.profile(artifact: aggregateOverflow), LocalCatalogFixtures.cleanup()
        ]),
        for: LocalCatalogFixtures.environment()
      )
    }

    let capacityOverflow = LocalCatalogFixtures.artifact(
      files: [.init(path: "model.bin", byteCount: 1, sha256: LocalCatalogFixtures.checksumA)],
      downloadBytes: 1,
      installedBytes: Int64.max
    )
    #expect(throws: LocalModelCatalogError.byteCountOverflow) {
      _ = try LocalModelCatalog.validate(
        LocalCatalogFixtures.configuration(profiles: [
          LocalCatalogFixtures.profile(artifact: capacityOverflow), LocalCatalogFixtures.cleanup()
        ]),
        for: LocalCatalogFixtures.environment()
      )
    }
  }

  @Test func catalogRejectsUnknownLicenseEvidenceAndAdmissionValues() {
    let invalidValues: [(RawLocalModelProfile, LocalModelCatalogError)] = [
      (
        LocalCatalogFixtures.replacing(LocalCatalogFixtures.profile(), license: "unknown"),
        .invalidValue(field: "license", value: "unknown")
      ),
      (
        LocalCatalogFixtures.replacing(LocalCatalogFixtures.profile(), evidence: "unknown"),
        .invalidValue(field: "evidence", value: "unknown")
      ),
      (
        LocalCatalogFixtures.replacing(LocalCatalogFixtures.profile(), admission: "unknown"),
        .invalidValue(field: "admission", value: "unknown")
      )
    ]
    for (profile, expectedError) in invalidValues {
      #expect(throws: expectedError) {
        _ = try LocalModelCatalog.validate(
          LocalCatalogFixtures.configuration(profiles: [profile, LocalCatalogFixtures.cleanup()]),
          for: LocalCatalogFixtures.environment()
        )
      }
    }

    let mismatched = LocalCatalogFixtures.replacing(
      LocalCatalogFixtures.profile(),
      admission: "signedDistributionAccepted"
    )
    #expect(throws: LocalModelCatalogError.evidenceAdmissionMismatch) {
      _ = try LocalModelCatalog.validate(
        LocalCatalogFixtures.configuration(profiles: [mismatched, LocalCatalogFixtures.cleanup()]),
        for: LocalCatalogFixtures.environment()
      )
    }
  }

  @Test func catalogRejectsSystemProfilesWithManagedArtifacts() {
    let system = LocalCatalogFixtures.profile(
      family: "appleSpeech",
      profileID: "apple.system.dictation",
      distribution: "system",
      license: "system",
      evidence: "platform",
      admission: "notAdmitted",
      buildCapability: "ordinarySafe"
    )
    #expect(throws: LocalModelCatalogError.unmanagedArtifact) {
      _ = try LocalModelCatalog.validate(
        LocalCatalogFixtures.configuration(profiles: [system, LocalCatalogFixtures.cleanup()]),
        for: LocalCatalogFixtures.environment(buildCapability: .ordinarySafe)
      )
    }

    let deterministic = LocalCatalogFixtures.profile(
      family: "rules",
      profileID: "fleck.deterministic.dictation",
      distribution: "deterministic",
      license: "fleckOwned",
      evidence: "deterministic",
      admission: "notAdmitted",
      buildCapability: "ordinarySafe"
    )
    #expect(throws: LocalModelCatalogError.unmanagedArtifact) {
      _ = try LocalModelCatalog.validate(
        LocalCatalogFixtures.configuration(profiles: [deterministic, LocalCatalogFixtures.cleanup()]),
        for: LocalCatalogFixtures.environment(buildCapability: .ordinarySafe)
      )
    }
  }

  @Test func catalogRejectsIncompatibleCompoundRoles() {
    let duplicate = LocalCatalogFixtures.replacing(
      LocalCatalogFixtures.cleanup(),
      profileID: "other.cleanup",
      role: "dictation"
    )
    #expect(throws: LocalModelCatalogError.duplicateRole(.dictation)) {
      _ = try LocalModelCatalog.validate(
        LocalCatalogFixtures.configuration(profiles: [LocalCatalogFixtures.profile(), duplicate]),
        for: LocalCatalogFixtures.environment()
      )
    }

    #expect(throws: LocalModelCatalogError.missingMandatoryRole(.cleanup)) {
      _ = try LocalModelCatalog.validate(
        LocalCatalogFixtures.configuration(profiles: [LocalCatalogFixtures.profile()]),
        for: LocalCatalogFixtures.environment()
      )
    }

    let incompatible = LocalCatalogFixtures.replacing(
      LocalCatalogFixtures.cleanup(),
      configurationABI: "writing-v2"
    )
    #expect(throws: LocalModelCatalogError.incompatibleConfigurationABI) {
      _ = try LocalModelCatalog.validate(
        LocalCatalogFixtures.configuration(profiles: [LocalCatalogFixtures.profile(), incompatible]),
        for: LocalCatalogFixtures.environment()
      )
    }

    let ordinaryProfiles = [
      LocalCatalogFixtures.replacing(
        LocalCatalogFixtures.profile(),
        evidence: "releaseAdmitted",
        admission: "releaseAdmitted",
        buildCapability: "ordinarySafe"
      ),
      LocalCatalogFixtures.replacing(
        LocalCatalogFixtures.cleanup(),
        evidence: "releaseAdmitted",
        admission: "releaseAdmitted",
        buildCapability: "ordinarySafe"
      )
    ]
    #expect(throws: LocalModelCatalogError.incompatibleBuildCapability) {
      _ = try LocalModelCatalog.validate(
        LocalCatalogFixtures.configuration(profiles: ordinaryProfiles),
        for: LocalCatalogFixtures.environment()
      )
    }
  }

  @Test func catalogRejectsHardwareOSAndLanguageMismatch() {
    let x86Profiles = [
      LocalCatalogFixtures.replacing(
        LocalCatalogFixtures.profile(),
        architectures: ["x86_64"]
      ),
      LocalCatalogFixtures.replacing(
        LocalCatalogFixtures.cleanup(),
        architectures: ["x86_64"]
      )
    ]
    #expect(throws: LocalModelCatalogError.incompatibleHardware) {
      _ = try LocalModelCatalog.validate(
        LocalCatalogFixtures.configuration(profiles: x86Profiles),
        for: LocalCatalogFixtures.environment(architecture: .x86_64)
      )
    }

    let mismatches: [(LocalModelBuildEnvironment, LocalModelCatalogError)] = [
      (LocalCatalogFixtures.environment(osMajor: 17), .incompatibleOS),
      (LocalCatalogFixtures.environment(languages: ["zh-Hans"]), .incompatibleLanguage)
    ]
    for (environment, expectedError) in mismatches {
      #expect(throws: expectedError) {
        _ = try LocalModelCatalog.validate(
          LocalCatalogFixtures.configuration(),
          for: environment
        )
      }
    }
  }

  @Test func catalogRejectsClaimSpeakerAndAcousticCohortMismatch() {
    let mismatches: [(RawLocalModelProfile, LocalModelCatalogError)] = [
      (
        LocalCatalogFixtures.replacing(LocalCatalogFixtures.cleanup(), claimScope: "ownerPrivate"),
        .claimScopeMismatch
      ),
      (
        LocalCatalogFixtures.replacing(LocalCatalogFixtures.cleanup(), speakerCohort: "owner"),
        .speakerCohortMismatch
      ),
      (
        LocalCatalogFixtures.replacing(LocalCatalogFixtures.cleanup(), acousticCohort: "quiet"),
        .acousticCohortMismatch
      )
    ]
    for (cleanup, expectedError) in mismatches {
      #expect(throws: expectedError) {
        _ = try LocalModelCatalog.validate(
          LocalCatalogFixtures.configuration(profiles: [LocalCatalogFixtures.profile(), cleanup]),
          for: LocalCatalogFixtures.environment()
        )
      }
    }
  }

  @Test func catalogRejectsOwnerPrivateEvidenceInOrdinaryBuilds() {
    let privateProfile = LocalCatalogFixtures.replacing(
      LocalCatalogFixtures.profile(),
      evidence: "identityVerified",
      admission: "notAdmitted",
      claimScope: "ownerPrivate",
      buildCapability: "ordinarySafe"
    )
    #expect(throws: LocalModelCatalogError.ownerPrivateEvidenceForbidden) {
      _ = try LocalModelCatalog.validate(
        LocalCatalogFixtures.configuration(profiles: [privateProfile, LocalCatalogFixtures.cleanup()]),
        for: LocalCatalogFixtures.environment(buildCapability: .ordinarySafe)
      )
    }
  }

  @Test func configurationDigestIsCanonicalAcrossInputOrder() throws {
    let dictation = LocalCatalogFixtures.profile(artifact: LocalCatalogFixtures.artifact(
      requiredPaths: ["tokenizer.json", "model.bin"],
      files: [
        .init(path: "tokenizer.json", byteCount: 2, sha256: LocalCatalogFixtures.checksumB),
        .init(path: "model.bin", byteCount: 2, sha256: LocalCatalogFixtures.checksumA)
      ]
    ))
    let cleanup = LocalCatalogFixtures.cleanup()
    let first = try LocalModelCatalog.validate(
      LocalCatalogFixtures.configuration(profiles: [dictation, cleanup]),
      for: LocalCatalogFixtures.environment()
    )
    let reorderedDictation = LocalCatalogFixtures.profile(artifact: LocalCatalogFixtures.artifact(
      requiredPaths: ["model.bin", "tokenizer.json"],
      files: [
        .init(path: "model.bin", byteCount: 2, sha256: LocalCatalogFixtures.checksumA),
        .init(path: "tokenizer.json", byteCount: 2, sha256: LocalCatalogFixtures.checksumB)
      ]
    ))
    let second = try LocalModelCatalog.validate(
      LocalCatalogFixtures.configuration(profiles: [cleanup, reorderedDictation]),
      for: LocalCatalogFixtures.environment()
    )
    let laterEvidenceProfiles = [dictation, cleanup].map {
      LocalCatalogFixtures.replacing(
        $0,
        evidence: "twoDeviceAccepted",
        admission: "twoDeviceAccepted"
      )
    }
    let laterEvidence = try LocalModelCatalog.validate(
      LocalCatalogFixtures.configuration(profiles: laterEvidenceProfiles),
      for: LocalCatalogFixtures.environment()
    )
    let changedRuntime = LocalCatalogFixtures.profile(
      artifact: LocalCatalogFixtures.artifact(runtimeABI: "runtime-changed")
    )
    let changedIdentity = try LocalModelCatalog.validate(
      LocalCatalogFixtures.configuration(profiles: [changedRuntime, cleanup]),
      for: LocalCatalogFixtures.environment()
    )

    #expect(first.key == "parakeet-gemma.en.v1")
    #expect(first.digest.count == 64)
    #expect(first.digest == second.digest)
    #expect(first.digest == laterEvidence.digest)
    #expect(first.digest != changedIdentity.digest)
    #expect(first.profiles == second.profiles)
  }

  @Test func legacyParakeetAndGemmaDescriptorsAdaptWithoutBehaviorChange() throws {
    let parakeet = try LocalCatalogFixtures.descriptor(
      role: .asr,
      modelID: "FluidInference/parakeet-tdt-0.6b-v2-coreml",
      revision: LocalCatalogFixtures.revisionA,
      runtimeABI: "FluidAudio/v0.15.5",
      license: "CC-BY-4.0",
      path: "parakeet.mlmodelc/model.mil",
      byteCount: 4,
      checksum: LocalCatalogFixtures.checksumA
    )
    let gemma = try LocalCatalogFixtures.descriptor(
      role: .cleanup,
      modelID: "mlx-community/gemma-3-1b-it-qat-4bit",
      revision: LocalCatalogFixtures.revisionB,
      runtimeABI: "mlx-swift-lm@revision",
      license: "Gemma Terms of Use",
      path: "model.safetensors",
      byteCount: 6,
      checksum: LocalCatalogFixtures.checksumB
    )

    let parakeetRaw = RawLocalModelProfile(
      adapting: parakeet,
      family: .parakeetTDT,
      profileID: "parakeet.en.dictation",
      configurationABI: "writing-v1",
      minimumOSMajor: 14,
      maximumOSMajor: 16,
      resources: .init(minimumRAMBytes: 4, workingRAMBytes: 8, storageBytes: 4),
      license: .ccBy40Reviewed,
      evidence: .identityVerified,
      admission: .notAdmitted,
      claimScope: .general,
      speakerCohort: .generalAdult,
      acousticCohort: .general,
      buildCapability: .developmentQuality
    )
    let gemmaRaw = RawLocalModelProfile(
      adapting: gemma,
      family: .gemma3,
      profileID: "gemma.en.cleanup",
      configurationABI: "writing-v1",
      minimumOSMajor: 14,
      maximumOSMajor: 16,
      resources: .init(minimumRAMBytes: 4, workingRAMBytes: 8, storageBytes: 6),
      license: .gemmaTermsReviewed,
      evidence: .identityVerified,
      admission: .notAdmitted,
      claimScope: .general,
      speakerCohort: .generalAdult,
      acousticCohort: .general,
      buildCapability: .developmentQuality
    )
    let configuration = try LocalModelCatalog.validate(
      .init(
        key: "parakeet-gemma.en.v1",
        requiredRoles: ["dictation", "cleanup"],
        profiles: [parakeetRaw, gemmaRaw]
      ),
      for: LocalCatalogFixtures.environment()
    )

    #expect(parakeet.role == .asr)
    #expect(gemma.role == .cleanup)
    #expect(parakeet.files.map(\.path) == ["parakeet.mlmodelc/model.mil"])
    #expect(gemma.files.map(\.path) == ["model.safetensors"])
    #expect(configuration.profiles.map(\.role) == [.cleanup, .dictation])
    #expect(configuration.profiles.allSatisfy { $0.evidence == .identityVerified })
    #expect(configuration.profiles.allSatisfy { $0.admission == .notAdmitted })
    #expect(configuration.profiles.allSatisfy { $0.buildCapability == .developmentQuality })
    #expect(configuration.profiles.first(where: { $0.role == .dictation })?.artifact?.modelID == parakeet.modelID)
    #expect(configuration.profiles.first(where: { $0.role == .cleanup })?.artifact?.modelID == gemma.modelID)
  }
}
