import Foundation

struct LocalModelPromotionTuple: Equatable, Sendable {
  let configurations: [RawLocalModelConfiguration]
  let managedProfileIDs: Set<String>
  let transitionSuccessor: LocalModelTransitionReleaseIdentity?
}

enum LocalModelCatalogSnapshotError: Error, Equatable, Sendable {
  case unsupportedEnvironment
  case promotionRequired
  case promotionNotAllowed
  case promotionProfileMismatch
  case buildCapabilityUnavailable
  case duplicateConfiguration(String)
  case inconsistentProfile(String)
  case transitionNotAllowed
  case multipleTransitions
  case transitionSuccessorMismatch
}

struct LocalModelCatalogSnapshot: Equatable, Sendable {
  let buildCapability: LocalModelBuildCapability
  let configurations: [LocalModelConfiguration]
  let transitions: [LocalModelUpdateTransition]

  private init(
    buildCapability: LocalModelBuildCapability,
    configurations: [LocalModelConfiguration],
    transitions: [LocalModelUpdateTransition]
  ) {
    self.buildCapability = buildCapability
    self.configurations = configurations
    self.transitions = transitions
  }

  var isUpdateAvailable: Bool { transitions.count == 1 }

  func configuration(key: String) -> LocalModelConfiguration? {
    configurations.first { $0.key == key }
  }

  func profile(id: String) -> LocalModelProfile? {
    configurations.lazy.flatMap(\.profiles).first { $0.profileID == id }
  }

  static func make(
    for environment: LocalModelBuildEnvironment,
    promotion: LocalModelPromotionTuple? = nil,
    transitions: [LocalModelUpdateTransition] = []
  ) throws -> LocalModelCatalogSnapshot {
    guard (14...26).contains(environment.osMajor) else {
      throw LocalModelCatalogSnapshotError.unsupportedEnvironment
    }

    let rawConfigurations: [RawLocalModelConfiguration]
    let promotedIDs: Set<String>
    switch environment.buildCapability {
    case .ordinarySafe:
      guard promotion == nil else {
        throw LocalModelCatalogSnapshotError.promotionNotAllowed
      }
      rawConfigurations = safeConfigurations(
        capability: .ordinarySafe,
        osMajor: environment.osMajor
      )
      promotedIDs = []
    case .developmentQuality:
      guard promotion == nil else {
        throw LocalModelCatalogSnapshotError.promotionNotAllowed
      }
      #if CLEAN_DICTATION_ENHANCED_CANDIDATE_REQUESTED
      rawConfigurations = safeConfigurations(
        capability: .developmentQuality,
        osMajor: environment.osMajor
      ) + developmentConfigurations()
      promotedIDs = []
      #else
      throw LocalModelCatalogSnapshotError.buildCapabilityUnavailable
      #endif
    case .signedDistributionCandidate:
      guard let promotion else {
        throw LocalModelCatalogSnapshotError.promotionRequired
      }
      rawConfigurations = promotion.configurations
      promotedIDs = promotion.managedProfileIDs
    }

    let configurations = try rawConfigurations.map {
      try LocalModelCatalog.validate($0, for: environment)
    }
    let snapshot = try validated(
      buildCapability: environment.buildCapability,
      configurations: configurations,
      promotionManagedProfileIDs: promotedIDs,
      transitions: transitions
    )
    if let transition = transitions.first {
      guard let expectedSuccessor = promotion?.transitionSuccessor,
            transition.successor == expectedSuccessor,
            snapshot.configuration(key: transition.successor.configurationKey)?.digest
              == transition.successor.configurationDigest else {
        throw LocalModelCatalogSnapshotError.transitionSuccessorMismatch
      }
    }
    return snapshot
  }

  private static func validated(
    buildCapability: LocalModelBuildCapability,
    configurations: [LocalModelConfiguration],
    promotionManagedProfileIDs: Set<String>,
    transitions: [LocalModelUpdateTransition]
  ) throws -> LocalModelCatalogSnapshot {
    guard transitions.count <= 1 else {
      throw LocalModelCatalogSnapshotError.multipleTransitions
    }
    guard transitions.isEmpty || buildCapability == .signedDistributionCandidate else {
      throw LocalModelCatalogSnapshotError.transitionNotAllowed
    }
    if let transition = transitions.first {
      guard configurations.contains(where: {
        $0.key == transition.successor.configurationKey
          && $0.digest == transition.successor.configurationDigest
      }) else {
        throw LocalModelCatalogSnapshotError.transitionSuccessorMismatch
      }
    }

    var configurationKeys = Set<String>()
    var profiles: [String: LocalModelProfile] = [:]
    for configuration in configurations {
      guard configurationKeys.insert(configuration.key).inserted else {
        throw LocalModelCatalogSnapshotError.duplicateConfiguration(configuration.key)
      }
      for profile in configuration.profiles {
        guard profile.buildCapability == buildCapability else {
          throw LocalModelCatalogSnapshotError.inconsistentProfile(profile.profileID)
        }
        if let existing = profiles[profile.profileID], existing != profile {
          throw LocalModelCatalogSnapshotError.inconsistentProfile(profile.profileID)
        }
        profiles[profile.profileID] = profile
      }
    }

    let actualManagedIDs = Set(profiles.values
      .filter { $0.distribution == .fleckManaged }
      .map(\.profileID))
    if buildCapability == .signedDistributionCandidate {
      guard actualManagedIDs == promotionManagedProfileIDs else {
        throw LocalModelCatalogSnapshotError.promotionProfileMismatch
      }
    } else {
      guard promotionManagedProfileIDs.isEmpty else {
        throw LocalModelCatalogSnapshotError.promotionNotAllowed
      }
    }
    return .init(
      buildCapability: buildCapability,
      configurations: configurations.sorted { $0.key < $1.key },
      transitions: transitions
    )
  }

  private static func safeConfigurations(
    capability: LocalModelBuildCapability,
    osMajor: Int
  ) -> [RawLocalModelConfiguration] {
    let speech = systemProfile(
      family: .appleSpeech,
      id: "apple-speech-en-system",
      role: .dictation,
      capability: capability,
      minimumOSMajor: 14
    )
    let deterministicCleanup = deterministicProfile(
      id: "deterministic-faithful-cleanup",
      role: .cleanup,
      capability: capability
    )
    let deterministicRouting = deterministicProfile(
      id: "deterministic-local-routing",
      role: .routing,
      capability: capability
    )
    var configurations = [configuration(
      key: "built-in-safe.en.v1",
      profiles: [speech, deterministicCleanup, deterministicRouting]
    )]
    guard osMajor == 26 else { return configurations }

    let foundationCleanup = systemProfile(
      family: .appleFoundation,
      id: "apple-foundation-cleanup-system-macos26",
      role: .cleanup,
      capability: capability,
      minimumOSMajor: 26
    )
    let foundationRouting = systemProfile(
      family: .appleFoundation,
      id: "apple-foundation-routing-system-macos26",
      role: .routing,
      capability: capability,
      minimumOSMajor: 26
    )
    configurations.append(contentsOf: [
      configuration(
        key: "apple-foundation-cleanup.en.macos26.v1",
        profiles: [speech, foundationCleanup, deterministicRouting]
      ),
      configuration(
        key: "apple-foundation-routing.en.macos26.v1",
        profiles: [speech, deterministicCleanup, foundationRouting]
      ),
      configuration(
        key: "apple-foundation-both.en.macos26.v1",
        profiles: [speech, foundationCleanup, foundationRouting]
      ),
    ])
    return configurations
  }

  #if CLEAN_DICTATION_ENHANCED_CANDIDATE_REQUESTED
  private static func developmentConfigurations() -> [RawLocalModelConfiguration] {
    let parakeet = managedProfile(
      family: .parakeetTDT,
      id: "parakeet-v2-en-coreml-batch",
      role: .dictation,
      artifact: parakeetArtifact(),
      license: .ccBy40Reviewed
    )
    let gemmaCleanup = managedProfile(
      family: .gemma3,
      id: "gemma3-1b-it-mlx-qat4-cleanup",
      role: .cleanup,
      artifact: gemmaArtifact(),
      license: .gemmaTermsReviewed
    )
    let gemmaRouting = managedProfile(
      family: .gemma3,
      id: "gemma3-1b-routing-mlx-qat4",
      role: .routing,
      artifact: gemmaArtifact(),
      license: .gemmaTermsReviewed
    )
    let deterministicCleanup = deterministicProfile(
      id: "deterministic-faithful-cleanup",
      role: .cleanup,
      capability: .developmentQuality
    )
    let deterministicRouting = deterministicProfile(
      id: "deterministic-local-routing",
      role: .routing,
      capability: .developmentQuality
    )
    return [
      configuration(
        key: "parakeet-v2-deterministic.en.v1",
        profiles: [parakeet, deterministicCleanup, deterministicRouting]
      ),
      configuration(
        key: "parakeet-v2-gemma-cleanup.en.v1",
        profiles: [parakeet, gemmaCleanup, deterministicRouting]
      ),
      configuration(
        key: "parakeet-v2-gemma-routing.en.v1",
        profiles: [parakeet, deterministicCleanup, gemmaRouting]
      ),
      configuration(
        key: "parakeet-v2-gemma-both.en.v1",
        profiles: [parakeet, gemmaCleanup, gemmaRouting]
      ),
    ]
  }
  #endif

  private static func configuration(
    key: String,
    profiles: [RawLocalModelProfile]
  ) -> RawLocalModelConfiguration {
    .init(
      key: key,
      requiredRoles: ["dictation", "cleanup", "routing"],
      profiles: profiles
    )
  }

  private static func systemProfile(
    family: LocalModelFamily,
    id: String,
    role: LocalModelCatalogRole,
    capability: LocalModelBuildCapability,
    minimumOSMajor: Int
  ) -> RawLocalModelProfile {
    profile(
      family: family,
      id: id,
      role: role,
      distribution: .system,
      artifact: nil,
      resources: .init(minimumRAMBytes: 1, workingRAMBytes: 1, storageBytes: 0),
      license: .system,
      evidence: .platform,
      capability: capability,
      minimumOSMajor: minimumOSMajor
    )
  }

  private static func deterministicProfile(
    id: String,
    role: LocalModelCatalogRole,
    capability: LocalModelBuildCapability
  ) -> RawLocalModelProfile {
    profile(
      family: .rules,
      id: id,
      role: role,
      distribution: .deterministic,
      artifact: nil,
      resources: .init(minimumRAMBytes: 1, workingRAMBytes: 1, storageBytes: 0),
      license: .fleckOwned,
      evidence: .deterministic,
      capability: capability,
      minimumOSMajor: 14
    )
  }

  #if CLEAN_DICTATION_ENHANCED_CANDIDATE_REQUESTED
  private static func managedProfile(
    family: LocalModelFamily,
    id: String,
    role: LocalModelCatalogRole,
    artifact: RawLocalModelArtifactIdentity,
    license: LocalModelLicenseState
  ) -> RawLocalModelProfile {
    let (workingBytes, overflow) = artifact.downloadBytes.addingReportingOverflow(
      artifact.installedBytes
    )
    precondition(!overflow)
    return profile(
      family: family,
      id: id,
      role: role,
      distribution: .fleckManaged,
      artifact: artifact,
      resources: .init(
        minimumRAMBytes: artifact.downloadBytes,
        workingRAMBytes: workingBytes,
        storageBytes: artifact.installedBytes
      ),
      license: license,
      evidence: .identityVerified,
      capability: .developmentQuality,
      minimumOSMajor: 14
    )
  }
  #endif

  private static func profile(
    family: LocalModelFamily,
    id: String,
    role: LocalModelCatalogRole,
    distribution: LocalModelDistribution,
    artifact: RawLocalModelArtifactIdentity?,
    resources: LocalModelResourceEnvelope,
    license: LocalModelLicenseState,
    evidence: LocalModelEvidenceTier,
    capability: LocalModelBuildCapability,
    minimumOSMajor: Int
  ) -> RawLocalModelProfile {
    .init(
      family: family.rawValue,
      profileID: id,
      role: role.rawValue,
      distribution: distribution.rawValue,
      artifact: artifact,
      compatibility: .init(
        configurationABI: "fleck.local-writing.v1",
        architectures: [LocalModelHardwareArchitecture.arm64.rawValue],
        minimumOSMajor: minimumOSMajor,
        maximumOSMajor: 26,
        languages: ["en"]
      ),
      resources: resources,
      license: license.rawValue,
      evidence: evidence.rawValue,
      admission: LocalModelAdmissionState.notAdmitted.rawValue,
      claimScope: LocalModelClaimScope.general.rawValue,
      speakerCohort: LocalModelSpeakerCohort.generalAdult.rawValue,
      acousticCohort: LocalModelAcousticCohort.general.rawValue,
      buildCapability: capability.rawValue
    )
  }

  #if CLEAN_DICTATION_ENHANCED_CANDIDATE_REQUESTED
  private static func parakeetArtifact() -> RawLocalModelArtifactIdentity {
    let files: [RawLocalModelArtifactFile] = [
      .init(path: "Preprocessor.mlmodelc/analytics/coremldata.bin", byteCount: 243, sha256: "03ab3c1327a054c54c07a40325db967ec574f2c91dcc8192bfa44aa561bcf2d8"),
      .init(path: "Preprocessor.mlmodelc/coremldata.bin", byteCount: 494, sha256: "d88ea1fc349459c9e100d6a96688c5b29a1f0d865f544be103001724b986b6d6"),
      .init(path: "Preprocessor.mlmodelc/metadata.json", byteCount: 2_974, sha256: "fb16c581ff5e1b962e7cb2181ed892cd32f9f84c12b6e80ff3e089f28e35bcbb"),
      .init(path: "Preprocessor.mlmodelc/model.mil", byteCount: 27_166, sha256: "3e06d16fd061294c8a75be68c43a3b1ed1f593d4a9c35249e9cdbccadc59721e"),
      .init(path: "Preprocessor.mlmodelc/weights/weight.bin", byteCount: 298_880, sha256: "a5f7df6c7f47147ae9486fe18cc7792f9a44d093ec3c6a11e91ef2dc363c48dc"),
      .init(path: "Encoder.mlmodelc/analytics/coremldata.bin", byteCount: 243, sha256: "42e638870d73f26b332918a3496ce36793fbb413a81cbd3d16ba01328637a105"),
      .init(path: "Encoder.mlmodelc/coremldata.bin", byteCount: 485, sha256: "4def7aa848599ad0e17a8b9a982edcdbf33cf92e1f4b798de32e2ca0bc74b030"),
      .init(path: "Encoder.mlmodelc/metadata.json", byteCount: 2_926, sha256: "58222fbc48c13c49d9715567803cd50cb9c23e4360462e0f8ffcea59a2c73c63"),
      .init(path: "Encoder.mlmodelc/model.mil", byteCount: 959_769, sha256: "ed7b19156ca29fa7dfd6891deb9fda4b0e8893f68597c985d135736546a43808"),
      .init(path: "Encoder.mlmodelc/weights/weight.bin", byteCount: 445_187_200, sha256: "4adc7ad44f9d05e1bffeb2b06d3bb02861a5c7602dff63a6b494aed3bf8a6c3e"),
      .init(path: "Decoder.mlmodelc/analytics/coremldata.bin", byteCount: 243, sha256: "46de1a6fe2e49d19a2125bc91acf020df7f2aea84ba821532aade8427a440b05"),
      .init(path: "Decoder.mlmodelc/coremldata.bin", byteCount: 554, sha256: "d200ca07694a347f6d02a3886a062ae839831e094e443222f2e48a14945966a8"),
      .init(path: "Decoder.mlmodelc/metadata.json", byteCount: 3_427, sha256: "90a279b822496316458febc0ce761ab05954fadd9d66aa97bea077a35fc8f2b2"),
      .init(path: "Decoder.mlmodelc/model.mil", byteCount: 13_106, sha256: "7b95a5a6b672c652000348a67b6d4d92bb8e176b978c6666fe73c28a4d7ec579"),
      .init(path: "Decoder.mlmodelc/weights/weight.bin", byteCount: 14_429_952, sha256: "27d26890221d82322c1092fd99d7b40578e435d5cf4b83c887c42603caf97aba"),
      .init(path: "JointDecision.mlmodelc/analytics/coremldata.bin", byteCount: 243, sha256: "f1183ba213bb94a918c8d2cad19ab045320618f97f6ca662245b3936d7b090f7"),
      .init(path: "JointDecision.mlmodelc/coremldata.bin", byteCount: 534, sha256: "e2c6752f1c8cf2d3f6f26ec93195c9bfa759ad59edf9f806696a138154f96f11"),
      .init(path: "JointDecision.mlmodelc/metadata.json", byteCount: 2_936, sha256: "ba8d309417b9acd4a175fdb15687de6a941db2f5b06666a60e7cf3cc8e2d3c3c"),
      .init(path: "JointDecision.mlmodelc/model.mil", byteCount: 9_722, sha256: "93bf82042235127cb81ab537dcae47a1c2e7e242ce4ffdaf772981b45eedc4f0"),
      .init(path: "JointDecision.mlmodelc/weights/weight.bin", byteCount: 3_453_388, sha256: "ca22a65903a05e64137677da608077578a8606090a598abf4875fa6199aaa19d"),
      .init(path: "parakeet_vocab.json", byteCount: 18_762, sha256: "57019fe3c745772ca83a1b048a4bb951cd51329504ea33d4d83316b96e279a97"),
    ]
    return .init(
      sourceRepository: URL(string: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml")!,
      artifactURL: nil,
      modelID: "FluidInference/parakeet-tdt-0.6b-v2-coreml",
      revision: "ee09c569f73759e6d44c9bd16766f477b2b36d39",
      runtimeABI: "FluidAudio/v0.15.5@19600a485baa4998812e4654b70d2bab8f2c9949",
      conversion: "CoreML",
      quantization: "FP16",
      requiredPaths: files.map(\.path),
      files: files,
      downloadBytes: 464_413_247,
      installedBytes: 464_413_247
    )
  }

  private static func gemmaArtifact() -> RawLocalModelArtifactIdentity {
    let files: [RawLocalModelArtifactFile] = [
      .init(path: ".gitattributes", byteCount: 1_570, sha256: "34448b82c17d60fec9b65b1f093c115ddbaadc04beb1b0140b6bfed2e012a930"),
      .init(path: "README.md", byteCount: 1_202, sha256: "ef1b7148ef260594ac05c36885f6471182f78416ee0d49c76851e7ebe56f4009"),
      .init(path: "added_tokens.json", byteCount: 35, sha256: "50b2f405ba56a26d4913fd772089992252d7f942123cc0a034d96424221ba946"),
      .init(path: "config.json", byteCount: 1_105, sha256: "eb080baebedaa32151a71988721a64f0be067fc6cd7e20ca16ba11231f822533"),
      .init(path: "model.safetensors", byteCount: 732_577_304, sha256: "b6010f6b03a83f973ca8708eb5784d5b0f80c0e7e9143dbb4c95d0eefe39c837"),
      .init(path: "model.safetensors.index.json", byteCount: 50_542, sha256: "b479eca1f14de16218fc5f45aa270d008944cd3f261f78e90f9b718c8857faef"),
      .init(path: "special_tokens_map.json", byteCount: 662, sha256: "2f7b0adf4fb469770bb1490e3e35df87b1dc578246c5e7e6fc76ecf33213a397"),
      .init(path: "tokenizer.json", byteCount: 33_384_568, sha256: "4667f2089529e8e7657cfb6d1c19910ae71ff5f28aa7ab2ff2763330affad795"),
      .init(path: "tokenizer.model", byteCount: 4_689_074, sha256: "1299c11d7cf632ef3b4e11937501358ada021bbdf7c47638d13c0ee982f2e79c"),
      .init(path: "tokenizer_config.json", byteCount: 1_156_959, sha256: "be9d72bdf5021aa82d67c3cc60cb0f8ddcc759d4d3f05eb129b9fcc345fc94b7"),
    ]
    return .init(
      sourceRepository: URL(string: "https://huggingface.co/mlx-community/gemma-3-1b-it-qat-4bit")!,
      artifactURL: nil,
      modelID: "mlx-community/gemma-3-1b-it-qat-4bit",
      revision: "15fed4eafb456c6fcb2a1165f19ac609670ed14b",
      runtimeABI: "mlx-swift-lm@bd4b7434e6bdb588c7ef55706ff8904cb7fd4c57;mlx-swift@0.31.6;swift-transformers@1.3.0",
      conversion: "MLX",
      quantization: "QAT 4-bit",
      requiredPaths: files.map(\.path),
      files: files,
      downloadBytes: 771_863_021,
      installedBytes: 771_863_021
    )
  }
  #endif
}
