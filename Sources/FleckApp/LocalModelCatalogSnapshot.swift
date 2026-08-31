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
  case missingValidatedResourceRecords
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
      throw LocalModelCatalogSnapshotError.missingValidatedResourceRecords
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
      resources: .init(
        applicability: .notApplicable,
        minimumRAMBytes: 0,
        workingRAMBytes: 0,
        storageBytes: 0
      ),
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
      resources: .init(
        applicability: .notApplicable,
        minimumRAMBytes: 0,
        workingRAMBytes: 0,
        storageBytes: 0
      ),
      license: .fleckOwned,
      evidence: .deterministic,
      capability: capability,
      minimumOSMajor: 14
    )
  }

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
}
