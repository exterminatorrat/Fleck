import Foundation
import Testing

@testable import FleckApp

private enum TransitionFixtures {
  static let digestA = String(repeating: "a", count: 64)
  static let digestB = String(repeating: "b", count: 64)
  static let digestC = String(repeating: "c", count: 64)
  static let digestD = String(repeating: "d", count: 64)
  static let digestE = String(repeating: "e", count: 64)
  static let digestF = String(repeating: "f", count: 64)
  static let zeroDigest = String(repeating: "0", count: 64)
  static let revisionA = String(repeating: "1", count: 40)
  static let revisionB = String(repeating: "2", count: 40)

  static func manifest(
    digest: String = digestA,
    revision: String = revisionA,
    closedFileSetDigest: String = digestB,
    installedBytes: Int64 = 40
  ) -> LocalModelTransitionArtifactManifest {
    .init(
      manifestDigest: digest,
      revision: revision,
      closedFileSetDigest: closedFileSetDigest,
      installedBytes: installedBytes
    )
  }

  static func release(
    packageDigest: String,
    admission: LocalModelAdmissionState,
    configurationKey: String,
    configurationDigest: String,
    profileIdentityDigests: [String],
    artifactManifests: [LocalModelTransitionArtifactManifest],
    receiptSchema: Int = 1,
    runtime: String = LocalModelUpdateTransition.runtimeCompatibilityRevision,
    trustSequence: UInt64 = 7,
    trustCheckpoint: String = digestD
  ) -> LocalModelTransitionReleaseIdentity {
    .init(
      packageDigest: packageDigest,
      admissionRecordDigest: admission == .releaseAdmitted ? digestB : digestC,
      admission: admission,
      configurationKey: configurationKey,
      configurationDigest: configurationDigest,
      profileIdentityDigests: profileIdentityDigests,
      artifactManifests: artifactManifests,
      installationReceiptSchemaVersion: receiptSchema,
      runtimeCompatibilityRevision: runtime,
      trustPolicySequence: trustSequence,
      trustPolicyCheckpointDigest: trustCheckpoint
    )
  }

  static let predecessor = release(
    packageDigest: digestA,
    admission: .releaseAdmitted,
    configurationKey: "previous.en.v1",
    configurationDigest: digestB,
    profileIdentityDigests: [digestA],
    artifactManifests: [manifest()]
  )
  static let successor = release(
    packageDigest: digestC,
    admission: .twoDeviceAccepted,
    configurationKey: "promoted.en.v1",
    configurationDigest: digestC,
    profileIdentityDigests: [digestB],
    artifactManifests: [manifest(
      digest: digestC,
      revision: revisionB,
      closedFileSetDigest: digestD
    )]
  )

  static func dependency(
    position: Int = 0,
    admissionDigest: String = digestB,
    checkpointDigest: String = digestB,
    headDigest: String = digestC,
    sealDigest: String = digestD,
    signerDigest: String = String(repeating: "e", count: 64),
    isCurrent: Bool = true,
    invalidated: Bool = false
  ) -> LocalModelPredecessorCorpusDependency {
    .init(
      position: position,
      predecessorAdmissionDigest: admissionDigest,
      corpusLedgerCheckpointDigest: checkpointDigest,
      corpusLedgerHeadEventDigest: headDigest,
      corpusAdmissionSealDigest: sealDigest,
      evaluationSignerFingerprintDigest: signerDigest,
      isCurrent: isCurrent,
      invalidated: invalidated
    )
  }

  static func descriptor(
    manifest: LocalModelTransitionArtifactManifest,
    side: String,
    role: String
  ) -> RawLocalModelTransitionArtifactDescriptor {
    .init(
      manifestDigest: manifest.manifestDigest,
      side: side,
      role: role,
      closedFileSetDigest: manifest.closedFileSetDigest,
      installedBytes: manifest.installedBytes
    )
  }

  static func descriptors(
    predecessor: LocalModelTransitionReleaseIdentity = predecessor,
    successor: LocalModelTransitionReleaseIdentity = successor
  ) -> [RawLocalModelTransitionArtifactDescriptor] {
    let predecessorDigests = Set(predecessor.artifactManifests.map(\.manifestDigest))
    let successorDigests = Set(successor.artifactManifests.map(\.manifestDigest))
    return predecessor.artifactManifests.map {
      descriptor(
        manifest: $0,
        side: "predecessor",
        role: successorDigests.contains($0.manifestDigest)
          ? "shared" : "retainForRollback"
      )
    } + successor.artifactManifests.map {
      descriptor(
        manifest: $0,
        side: "successor",
        role: predecessorDigests.contains($0.manifestDigest) ? "shared" : "install"
      )
    }
  }

  static func raw(
    schemaVersion: Int = 1,
    predecessor: LocalModelTransitionReleaseIdentity = predecessor,
    predecessorUpdateRecordDigest: String = digestE,
    successor: LocalModelTransitionReleaseIdentity = successor,
    successorPromotionRecordDigest: String = digestC,
    dependencies: [LocalModelPredecessorCorpusDependency] = [dependency()],
    lineageValid: Bool = true,
    artifactDescriptors: [RawLocalModelTransitionArtifactDescriptor]? = nil,
    sideBySideBytes: Int64 = 100,
    stagingBytes: Int64 = 60,
    rollbackBytes: Int64 = 40,
    availableBytes: Int64 = 100,
    rollbackDurationMilliseconds: Int64 = 86_400_000
  ) -> RawLocalModelUpdateTransition {
    .init(
      schemaVersion: schemaVersion,
      predecessor: predecessor,
      predecessorUpdateRecordDigest: predecessorUpdateRecordDigest,
      successor: successor,
      successorPromotionRecordDigest: successorPromotionRecordDigest,
      predecessorCorpusDependencies: dependencies,
      lineageValid: lineageValid,
      artifactDescriptors: artifactDescriptors ?? descriptors(
        predecessor: predecessor,
        successor: successor
      ),
      rollback: .init(
        sideBySideBytes: sideBySideBytes,
        stagingBytes: stagingBytes,
        rollbackBytes: rollbackBytes,
        availableBytes: availableBytes,
        retentionDurationMilliseconds: rollbackDurationMilliseconds
      )
    )
  }

  static func validate(
    _ raw: RawLocalModelUpdateTransition = raw(),
    expectedSuccessor: LocalModelTransitionReleaseIdentity = successor,
    currentTrustSequence: UInt64 = 7,
    currentTrustCheckpoint: String = digestD
  ) throws -> LocalModelUpdateTransition {
    try LocalModelUpdateTransition.validating(
      raw,
      expectedSuccessor: expectedSuccessor,
      currentTrustPolicySequence: currentTrustSequence,
      currentTrustPolicyCheckpointDigest: currentTrustCheckpoint
    )
  }

  static let signedEnvironment = LocalModelBuildEnvironment(
    architecture: .arm64,
    osMajor: 26,
    languages: ["en"],
    buildCapability: .signedDistributionCandidate,
    claimScope: .general,
    speakerCohort: .generalAdult,
    acousticCohort: .general
  )

  static func signedProfile(
    id: String,
    role: LocalModelCatalogRole
  ) -> RawLocalModelProfile {
    .init(
      family: LocalModelFamily.rules.rawValue,
      profileID: id,
      role: role.rawValue,
      distribution: LocalModelDistribution.deterministic.rawValue,
      artifact: nil,
      compatibility: .init(
        configurationABI: "fleck.local-writing.v1",
        architectures: [LocalModelHardwareArchitecture.arm64.rawValue],
        minimumOSMajor: 14,
        maximumOSMajor: 26,
        languages: ["en"]
      ),
      resources: .init(
        applicability: .notApplicable,
        minimumRAMBytes: 0,
        workingRAMBytes: 0,
        storageBytes: 0
      ),
      license: LocalModelLicenseState.fleckOwned.rawValue,
      evidence: LocalModelEvidenceTier.deterministic.rawValue,
      admission: LocalModelAdmissionState.notAdmitted.rawValue,
      claimScope: LocalModelClaimScope.general.rawValue,
      speakerCohort: LocalModelSpeakerCohort.generalAdult.rawValue,
      acousticCohort: LocalModelAcousticCohort.general.rawValue,
      buildCapability: LocalModelBuildCapability.signedDistributionCandidate.rawValue
    )
  }

  static let signedConfiguration = RawLocalModelConfiguration(
    key: "promoted.en.v1",
    requiredRoles: ["dictation", "cleanup", "routing"],
    profiles: [
      signedProfile(id: "signed-dictation", role: .dictation),
      signedProfile(id: "signed-cleanup", role: .cleanup),
      signedProfile(id: "signed-routing", role: .routing),
    ]
  )

  static func signedPromotion(
    transitionSuccessor: LocalModelTransitionReleaseIdentity? = nil
  ) -> LocalModelPromotionTuple {
    .init(
      configurations: [signedConfiguration],
      managedProfileIDs: [],
      transitionSuccessor: transitionSuccessor
    )
  }

  static func signedTransitionInputs() throws -> (
    promotion: LocalModelPromotionTuple,
    transition: LocalModelUpdateTransition
  ) {
    let snapshot = try LocalModelCatalogSnapshot.make(
      for: signedEnvironment,
      promotion: signedPromotion()
    )
    guard let configuration = snapshot.configurations.first else {
      throw LocalModelCatalogSnapshotError.transitionSuccessorMismatch
    }
    let exactSuccessor = release(
      packageDigest: digestC,
      admission: .twoDeviceAccepted,
      configurationKey: configuration.key,
      configurationDigest: configuration.digest,
      profileIdentityDigests: [digestB],
      artifactManifests: [manifest(
        digest: digestC,
        revision: revisionB,
        closedFileSetDigest: digestD
      )]
    )
    return (
      signedPromotion(transitionSuccessor: exactSuccessor),
      try validate(raw(successor: exactSuccessor), expectedSuccessor: exactSuccessor)
    )
  }
}

@Suite struct LocalModelUpdateTransitionTests {
  @Test func rawTransitionCarriesPredecessorUpdateRecordIdentity() {
    #expect(TransitionFixtures.raw().predecessorUpdateRecordDigest
      == TransitionFixtures.digestE)
  }

  @Test func validatedTransitionCarriesPredecessorUpdateRecordIdentity() throws {
    #expect(try TransitionFixtures.validate().predecessorUpdateRecordDigest
      == TransitionFixtures.digestE)
  }

  @Test func transitionRejectsMissingOrInvalidPredecessorUpdateRecordDigest() {
    for digest in ["", "not-a-digest", TransitionFixtures.zeroDigest] {
      #expect(throws: LocalModelUpdateTransitionError.invalidDigest(digest)) {
        _ = try TransitionFixtures.validate(TransitionFixtures.raw(
          predecessorUpdateRecordDigest: digest
        ))
      }
    }
  }

  @Test func transitionDigestBindsPredecessorUpdateRecord() throws {
    let first = try TransitionFixtures.validate()
    let mutated = try TransitionFixtures.validate(TransitionFixtures.raw(
      predecessorUpdateRecordDigest: TransitionFixtures.digestF
    ))
    #expect(first.identityDigest != mutated.identityDigest)
  }

  @Test func transitionRejectsPromotionDigestNotBoundToSuccessor() {
    #expect(throws: LocalModelUpdateTransitionError.successorMismatch) {
      _ = try TransitionFixtures.validate(TransitionFixtures.raw(
        successorPromotionRecordDigest: TransitionFixtures.digestD
      ))
    }
  }

  @Test func transitionConstructionAuthorityIsPrivateAndValidatingRemainsUsable() throws {
    let sourceURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sources/FleckApp/LocalModelUpdateTransition.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)
    let transitionBody = try #require(source.components(
      separatedBy: "struct LocalModelUpdateTransition: Equatable, Sendable {"
    ).last)
    let declaration = try #require(transitionBody.components(
      separatedBy: "  static func validating("
    ).first)

    #expect(declaration.components(separatedBy: "\n  private init(").count - 1 == 1)
    #expect(!declaration.contains("\n  init("))

    let transition = try TransitionFixtures.validate()
    #expect(transition.predecessor == TransitionFixtures.predecessor)
    #expect(transition.successor == TransitionFixtures.successor)
    #expect(transition.identityDigest.count == 64)
  }

  @Test func transitionRejectsFabricatedOrUnknownDescriptorRolesAndSides() {
    let descriptors = TransitionFixtures.descriptors()
    let fabricatedShared = RawLocalModelTransitionArtifactDescriptor(
      manifestDigest: descriptors[0].manifestDigest,
      side: descriptors[0].side,
      role: "shared",
      closedFileSetDigest: descriptors[0].closedFileSetDigest,
      installedBytes: descriptors[0].installedBytes
    )
    #expect(throws: LocalModelUpdateTransitionError.artifactDescriptorRoleMismatch(
      .predecessor,
      TransitionFixtures.digestA
    )) {
      _ = try TransitionFixtures.validate(TransitionFixtures.raw(
        artifactDescriptors: [fabricatedShared, descriptors[1]]
      ))
    }

    let unknownSide = RawLocalModelTransitionArtifactDescriptor(
      manifestDigest: descriptors[0].manifestDigest,
      side: "elsewhere",
      role: descriptors[0].role,
      closedFileSetDigest: descriptors[0].closedFileSetDigest,
      installedBytes: descriptors[0].installedBytes
    )
    #expect(throws: LocalModelUpdateTransitionError.invalidArtifactDescriptorSide(
      "elsewhere"
    )) {
      _ = try TransitionFixtures.validate(TransitionFixtures.raw(
        artifactDescriptors: [unknownSide, descriptors[1]]
      ))
    }

    let unknownRole = RawLocalModelTransitionArtifactDescriptor(
      manifestDigest: descriptors[0].manifestDigest,
      side: descriptors[0].side,
      role: "download",
      closedFileSetDigest: descriptors[0].closedFileSetDigest,
      installedBytes: descriptors[0].installedBytes
    )
    #expect(throws: LocalModelUpdateTransitionError.invalidArtifactDescriptorRole(
      "download"
    )) {
      _ = try TransitionFixtures.validate(TransitionFixtures.raw(
        artifactDescriptors: [unknownRole, descriptors[1]]
      ))
    }

    let wrongSide = RawLocalModelTransitionArtifactDescriptor(
      manifestDigest: descriptors[0].manifestDigest,
      side: "successor",
      role: "install",
      closedFileSetDigest: descriptors[0].closedFileSetDigest,
      installedBytes: descriptors[0].installedBytes
    )
    #expect(throws: LocalModelUpdateTransitionError.extraArtifactDescriptor(
      .successor,
      TransitionFixtures.digestA
    )) {
      _ = try TransitionFixtures.validate(TransitionFixtures.raw(
        artifactDescriptors: [wrongSide, descriptors[1]]
      ))
    }
  }

  @Test func transitionRejectsMissingExtraOrDuplicateArtifactDescriptors() {
    let descriptors = TransitionFixtures.descriptors()
    #expect(throws: LocalModelUpdateTransitionError.missingArtifactDescriptor(
      .successor,
      TransitionFixtures.digestC
    )) {
      _ = try TransitionFixtures.validate(TransitionFixtures.raw(
        artifactDescriptors: [descriptors[0]]
      ))
    }

    let extra = RawLocalModelTransitionArtifactDescriptor(
      manifestDigest: TransitionFixtures.digestF,
      side: "successor",
      role: "install",
      closedFileSetDigest: TransitionFixtures.digestA,
      installedBytes: 1
    )
    #expect(throws: LocalModelUpdateTransitionError.extraArtifactDescriptor(
      .successor,
      TransitionFixtures.digestF
    )) {
      _ = try TransitionFixtures.validate(TransitionFixtures.raw(
        artifactDescriptors: descriptors + [extra]
      ))
    }

    #expect(throws: LocalModelUpdateTransitionError.duplicateArtifactDescriptor(
      .predecessor,
      TransitionFixtures.digestA
    )) {
      _ = try TransitionFixtures.validate(TransitionFixtures.raw(
        artifactDescriptors: [descriptors[0], descriptors[0], descriptors[1]]
      ))
    }
  }

  @Test func transitionRejectsDescriptorManifestFieldMismatches() {
    let descriptors = TransitionFixtures.descriptors()
    for mismatch in [
      RawLocalModelTransitionArtifactDescriptor(
        manifestDigest: descriptors[0].manifestDigest,
        side: descriptors[0].side,
        role: descriptors[0].role,
        closedFileSetDigest: TransitionFixtures.digestF,
        installedBytes: descriptors[0].installedBytes
      ),
      RawLocalModelTransitionArtifactDescriptor(
        manifestDigest: descriptors[0].manifestDigest,
        side: descriptors[0].side,
        role: descriptors[0].role,
        closedFileSetDigest: descriptors[0].closedFileSetDigest,
        installedBytes: descriptors[0].installedBytes + 1
      ),
    ] {
      #expect(throws: LocalModelUpdateTransitionError.artifactDescriptorManifestMismatch(
        .predecessor,
        TransitionFixtures.digestA
      )) {
        _ = try TransitionFixtures.validate(TransitionFixtures.raw(
          artifactDescriptors: [mismatch, descriptors[1]]
        ))
      }
    }

    let invalidDigest = RawLocalModelTransitionArtifactDescriptor(
      manifestDigest: "not-a-digest",
      side: descriptors[0].side,
      role: descriptors[0].role,
      closedFileSetDigest: descriptors[0].closedFileSetDigest,
      installedBytes: descriptors[0].installedBytes
    )
    #expect(throws: LocalModelUpdateTransitionError.invalidDigest("not-a-digest")) {
      _ = try TransitionFixtures.validate(TransitionFixtures.raw(
        artifactDescriptors: [invalidDigest, descriptors[1]]
      ))
    }

    let nonpositiveBytes = RawLocalModelTransitionArtifactDescriptor(
      manifestDigest: descriptors[0].manifestDigest,
      side: descriptors[0].side,
      role: descriptors[0].role,
      closedFileSetDigest: descriptors[0].closedFileSetDigest,
      installedBytes: 0
    )
    #expect(throws: LocalModelUpdateTransitionError.invalidArtifactDescriptor) {
      _ = try TransitionFixtures.validate(TransitionFixtures.raw(
        artifactDescriptors: [nonpositiveBytes, descriptors[1]]
      ))
    }
  }

  @Test func transitionAcceptsIdenticalSharedManifestOnBothSides() throws {
    let sharedManifest = TransitionFixtures.manifest()
    let predecessor = TransitionFixtures.release(
      packageDigest: TransitionFixtures.digestA,
      admission: .releaseAdmitted,
      configurationKey: "previous.en.v1",
      configurationDigest: TransitionFixtures.digestB,
      profileIdentityDigests: [TransitionFixtures.digestA],
      artifactManifests: [sharedManifest]
    )
    let successor = TransitionFixtures.release(
      packageDigest: TransitionFixtures.digestC,
      admission: .twoDeviceAccepted,
      configurationKey: "promoted.en.v1",
      configurationDigest: TransitionFixtures.digestC,
      profileIdentityDigests: [TransitionFixtures.digestB],
      artifactManifests: [sharedManifest]
    )
    let transition = try TransitionFixtures.validate(
      TransitionFixtures.raw(predecessor: predecessor, successor: successor),
      expectedSuccessor: successor
    )

    #expect(transition.artifactDescriptors.map(\.role) == [.shared, .shared])
    #expect(transition.artifactDescriptors.map(\.side) == [.predecessor, .successor])
  }

  @Test func transitionRejectsInconsistentSharedManifestIdentity() {
    let sharedPredecessorManifest = TransitionFixtures.manifest()
    let sharedSuccessorManifest = TransitionFixtures.manifest(
      revision: TransitionFixtures.revisionB
    )
    let predecessor = TransitionFixtures.release(
      packageDigest: TransitionFixtures.digestA,
      admission: .releaseAdmitted,
      configurationKey: "previous.en.v1",
      configurationDigest: TransitionFixtures.digestB,
      profileIdentityDigests: [TransitionFixtures.digestA],
      artifactManifests: [sharedPredecessorManifest]
    )
    let successor = TransitionFixtures.release(
      packageDigest: TransitionFixtures.digestC,
      admission: .twoDeviceAccepted,
      configurationKey: "promoted.en.v1",
      configurationDigest: TransitionFixtures.digestC,
      profileIdentityDigests: [TransitionFixtures.digestB],
      artifactManifests: [sharedSuccessorManifest]
    )

    #expect(throws: LocalModelUpdateTransitionError.inconsistentSharedArtifactManifest(
      TransitionFixtures.digestA
    )) {
      _ = try TransitionFixtures.validate(
        TransitionFixtures.raw(predecessor: predecessor, successor: successor),
        expectedSuccessor: successor
      )
    }
  }

  @Test func transitionCanonicalizesAndBindsArtifactDescriptors() throws {
    let descriptors = TransitionFixtures.descriptors()
    let canonical = try TransitionFixtures.validate(TransitionFixtures.raw(
      artifactDescriptors: descriptors
    ))
    let reordered = try TransitionFixtures.validate(TransitionFixtures.raw(
      artifactDescriptors: Array(descriptors.reversed())
    ))
    #expect(canonical.identityDigest == reordered.identityDigest)
    #expect(canonical.artifactDescriptors.map(\.side) == [.predecessor, .successor])

    let changedManifest = TransitionFixtures.manifest(
      digest: TransitionFixtures.digestC,
      revision: TransitionFixtures.revisionB,
      closedFileSetDigest: TransitionFixtures.digestD,
      installedBytes: 41
    )
    let changedSuccessor = TransitionFixtures.release(
      packageDigest: TransitionFixtures.digestC,
      admission: .twoDeviceAccepted,
      configurationKey: "promoted.en.v1",
      configurationDigest: TransitionFixtures.digestC,
      profileIdentityDigests: [TransitionFixtures.digestB],
      artifactManifests: [changedManifest]
    )
    let mutated = try TransitionFixtures.validate(
      TransitionFixtures.raw(
        successor: changedSuccessor,
        artifactDescriptors: TransitionFixtures.descriptors(
          successor: changedSuccessor
        )
      ),
      expectedSuccessor: changedSuccessor
    )
    #expect(canonical.identityDigest != mutated.identityDigest)
  }

  @Test func transitionRejectsWrongReleaseAndTrustAuthority() {
    #expect(throws: LocalModelUpdateTransitionError.predecessorEqualsSuccessor) {
      _ = try TransitionFixtures.validate(TransitionFixtures.raw(
        predecessor: TransitionFixtures.successor
      ))
    }
    #expect(throws: LocalModelUpdateTransitionError.predecessorNotReleaseAdmitted) {
      _ = try TransitionFixtures.validate(TransitionFixtures.raw(
        predecessor: TransitionFixtures.release(
          packageDigest: TransitionFixtures.digestA,
          admission: .twoDeviceAccepted,
          configurationKey: "previous.en.v1",
          configurationDigest: TransitionFixtures.digestB,
          profileIdentityDigests: [TransitionFixtures.digestA],
          artifactManifests: [TransitionFixtures.manifest()]
        )
      ))
    }
    #expect(throws: LocalModelUpdateTransitionError.successorMismatch) {
      _ = try TransitionFixtures.validate(
        TransitionFixtures.raw(),
        expectedSuccessor: TransitionFixtures.predecessor
      )
    }
    #expect(throws: LocalModelUpdateTransitionError.trustAnchorMismatch) {
      _ = try TransitionFixtures.validate(
        TransitionFixtures.raw(),
        currentTrustCheckpoint: String(repeating: "f", count: 64)
      )
    }
    #expect(throws: LocalModelUpdateTransitionError.staleTrustCheckpoint) {
      _ = try TransitionFixtures.validate(
        TransitionFixtures.raw(),
        currentTrustSequence: 8
      )
    }
  }

  @Test func transitionRejectsMissingDuplicateMutableOrUnsafeManifests() {
    let invalid: [(LocalModelTransitionReleaseIdentity, LocalModelUpdateTransitionError)] = [
      (
        TransitionFixtures.release(
          packageDigest: TransitionFixtures.digestA,
          admission: .releaseAdmitted,
          configurationKey: "previous.en.v1",
          configurationDigest: TransitionFixtures.digestB,
          profileIdentityDigests: [TransitionFixtures.digestA],
          artifactManifests: []
        ),
        .missingArtifactManifest
      ),
      (
        TransitionFixtures.release(
          packageDigest: TransitionFixtures.digestA,
          admission: .releaseAdmitted,
          configurationKey: "previous.en.v1",
          configurationDigest: TransitionFixtures.digestB,
          profileIdentityDigests: [TransitionFixtures.digestA],
          artifactManifests: [TransitionFixtures.manifest(), TransitionFixtures.manifest()]
        ),
        .duplicateArtifactManifest(TransitionFixtures.digestA)
      ),
      (
        TransitionFixtures.release(
          packageDigest: TransitionFixtures.digestA,
          admission: .releaseAdmitted,
          configurationKey: "previous.en.v1",
          configurationDigest: TransitionFixtures.digestB,
          profileIdentityDigests: [TransitionFixtures.digestA],
          artifactManifests: [TransitionFixtures.manifest(revision: "main")]
        ),
        .mutableArtifactRevision("main")
      ),
      (
        TransitionFixtures.release(
          packageDigest: TransitionFixtures.digestA,
          admission: .releaseAdmitted,
          configurationKey: "previous.en.v1",
          configurationDigest: TransitionFixtures.digestB,
          profileIdentityDigests: [TransitionFixtures.digestA],
          artifactManifests: [TransitionFixtures.manifest(installedBytes: 0)]
        ),
        .invalidReleaseIdentity
      ),
      (
        TransitionFixtures.release(
          packageDigest: TransitionFixtures.digestA,
          admission: .releaseAdmitted,
          configurationKey: "previous.en.v1",
          configurationDigest: TransitionFixtures.digestB,
          profileIdentityDigests: ["not-a-digest"],
          artifactManifests: [TransitionFixtures.manifest()]
        ),
        .invalidDigest("not-a-digest")
      ),
    ]
    for (predecessor, error) in invalid {
      #expect(throws: error) {
        _ = try TransitionFixtures.validate(TransitionFixtures.raw(predecessor: predecessor))
      }
    }
  }

  @Test func transitionRejectsMissingDuplicateReorderedStaleOrInvalidatedDependencies() {
    let duplicate = TransitionFixtures.dependency(position: 1)
    let reorderedFirst = TransitionFixtures.dependency(
      position: 1,
      admissionDigest: TransitionFixtures.digestB
    )
    let reorderedSecond = TransitionFixtures.dependency(
      position: 0,
      admissionDigest: TransitionFixtures.digestA
    )
    let invalid: [([LocalModelPredecessorCorpusDependency], LocalModelUpdateTransitionError)] = [
      ([], .missingCorpusDependency),
      ([TransitionFixtures.dependency(), duplicate],
       .duplicateCorpusDependency(TransitionFixtures.digestB)),
      ([reorderedFirst, reorderedSecond], .reorderedCorpusDependency),
      ([TransitionFixtures.dependency(isCurrent: false)], .staleCorpusDependency),
      ([TransitionFixtures.dependency(invalidated: true)], .invalidatedCorpusLineage),
    ]
    for (dependencies, error) in invalid {
      #expect(throws: error) {
        _ = try TransitionFixtures.validate(TransitionFixtures.raw(
          dependencies: dependencies
        ))
      }
    }
    #expect(throws: LocalModelUpdateTransitionError.invalidatedCorpusLineage) {
      _ = try TransitionFixtures.validate(TransitionFixtures.raw(lineageValid: false))
    }
  }

  @Test func transitionRejectsCurrentCorpusEvidenceForAnotherRelease() {
    let currentEvidenceForY = TransitionFixtures.dependency(
      admissionDigest: TransitionFixtures.successor.admissionRecordDigest
    )

    #expect(throws: LocalModelUpdateTransitionError.invalidatedCorpusLineage) {
      _ = try TransitionFixtures.validate(TransitionFixtures.raw(
        dependencies: [currentEvidenceForY]
      ))
    }
  }

  @Test func transitionRejectsIncompatibleReceiptRuntimeAndInsufficientRollbackReserve() {
    let incompatibleReceipt = TransitionFixtures.release(
      packageDigest: TransitionFixtures.digestA,
      admission: .releaseAdmitted,
      configurationKey: "previous.en.v1",
      configurationDigest: TransitionFixtures.digestB,
      profileIdentityDigests: [TransitionFixtures.digestA],
      artifactManifests: [TransitionFixtures.manifest()],
      receiptSchema: 2
    )
    #expect(throws: LocalModelUpdateTransitionError.incompatibleReceiptSchema) {
      _ = try TransitionFixtures.validate(TransitionFixtures.raw(
        predecessor: incompatibleReceipt
      ))
    }
    let incompatibleRuntime = TransitionFixtures.release(
      packageDigest: TransitionFixtures.digestA,
      admission: .releaseAdmitted,
      configurationKey: "previous.en.v1",
      configurationDigest: TransitionFixtures.digestB,
      profileIdentityDigests: [TransitionFixtures.digestA],
      artifactManifests: [TransitionFixtures.manifest()],
      runtime: "old-runtime"
    )
    #expect(throws: LocalModelUpdateTransitionError.incompatibleRuntime) {
      _ = try TransitionFixtures.validate(TransitionFixtures.raw(
        predecessor: incompatibleRuntime
      ))
    }
    #expect(throws: LocalModelUpdateTransitionError.insufficientRollbackReserve) {
      _ = try TransitionFixtures.validate(TransitionFixtures.raw(
        availableBytes: 99
      ))
    }
  }

  @Test func transitionRejectsManifestUnderProvisionedRollbackAndStaging() {
    let oversizedPredecessor = TransitionFixtures.release(
      packageDigest: TransitionFixtures.digestA,
      admission: .releaseAdmitted,
      configurationKey: "previous.en.v1",
      configurationDigest: TransitionFixtures.digestB,
      profileIdentityDigests: [TransitionFixtures.digestA],
      artifactManifests: [TransitionFixtures.manifest(installedBytes: 41)]
    )
    #expect(throws: LocalModelUpdateTransitionError.insufficientRollbackReserve) {
      _ = try TransitionFixtures.validate(TransitionFixtures.raw(
        predecessor: oversizedPredecessor
      ))
    }

    let oversizedSuccessor = TransitionFixtures.release(
      packageDigest: TransitionFixtures.digestC,
      admission: .twoDeviceAccepted,
      configurationKey: "promoted.en.v1",
      configurationDigest: TransitionFixtures.digestC,
      profileIdentityDigests: [TransitionFixtures.digestB],
      artifactManifests: [TransitionFixtures.manifest(
        digest: TransitionFixtures.digestC,
        revision: TransitionFixtures.revisionB,
        closedFileSetDigest: TransitionFixtures.digestD,
        installedBytes: 61
      )]
    )
    #expect(throws: LocalModelUpdateTransitionError.insufficientRollbackReserve) {
      _ = try TransitionFixtures.validate(
        TransitionFixtures.raw(successor: oversizedSuccessor),
        expectedSuccessor: oversizedSuccessor
      )
    }
  }

  @Test func transitionRejectsManifestByteOverflowAndZeroDigest() {
    let overflowingPredecessor = TransitionFixtures.release(
      packageDigest: TransitionFixtures.digestA,
      admission: .releaseAdmitted,
      configurationKey: "previous.en.v1",
      configurationDigest: TransitionFixtures.digestB,
      profileIdentityDigests: [TransitionFixtures.digestA],
      artifactManifests: [
        TransitionFixtures.manifest(installedBytes: Int64.max),
        TransitionFixtures.manifest(
          digest: TransitionFixtures.digestB,
          revision: TransitionFixtures.revisionB,
          closedFileSetDigest: TransitionFixtures.digestC,
          installedBytes: 1
        ),
      ]
    )
    #expect(throws: LocalModelUpdateTransitionError.byteCountOverflow) {
      _ = try TransitionFixtures.validate(TransitionFixtures.raw(
        predecessor: overflowingPredecessor
      ))
    }

    let zeroIdentityPredecessor = TransitionFixtures.release(
      packageDigest: TransitionFixtures.zeroDigest,
      admission: .releaseAdmitted,
      configurationKey: "previous.en.v1",
      configurationDigest: TransitionFixtures.digestB,
      profileIdentityDigests: [TransitionFixtures.digestA],
      artifactManifests: [TransitionFixtures.manifest()]
    )
    #expect(throws: LocalModelUpdateTransitionError.invalidDigest(
      TransitionFixtures.zeroDigest
    )) {
      _ = try TransitionFixtures.validate(TransitionFixtures.raw(
        predecessor: zeroIdentityPredecessor
      ))
    }
  }

  @Test func transitionDigestCanonicalizesSetsButPreservesDependencyOrder() throws {
    let manifestB = TransitionFixtures.manifest(
      digest: TransitionFixtures.digestB,
      revision: TransitionFixtures.revisionB,
      closedFileSetDigest: TransitionFixtures.digestC
    )
    let predecessor = TransitionFixtures.release(
      packageDigest: TransitionFixtures.digestA,
      admission: .releaseAdmitted,
      configurationKey: "previous.en.v1",
      configurationDigest: TransitionFixtures.digestB,
      profileIdentityDigests: [TransitionFixtures.digestA, TransitionFixtures.digestB],
      artifactManifests: [TransitionFixtures.manifest(), manifestB]
    )
    let reorderedSets = TransitionFixtures.release(
      packageDigest: TransitionFixtures.digestA,
      admission: .releaseAdmitted,
      configurationKey: "previous.en.v1",
      configurationDigest: TransitionFixtures.digestB,
      profileIdentityDigests: [TransitionFixtures.digestB, TransitionFixtures.digestA],
      artifactManifests: [manifestB, TransitionFixtures.manifest()]
    )
    let dependencies = [
      TransitionFixtures.dependency(),
      TransitionFixtures.dependency(
        position: 1,
        admissionDigest: TransitionFixtures.digestA,
        checkpointDigest: TransitionFixtures.digestC,
        headDigest: TransitionFixtures.digestD,
        sealDigest: String(repeating: "e", count: 64),
        signerDigest: String(repeating: "f", count: 64)
      ),
      TransitionFixtures.dependency(
        position: 2,
        admissionDigest: TransitionFixtures.digestC,
        checkpointDigest: TransitionFixtures.digestD,
        headDigest: String(repeating: "e", count: 64),
        sealDigest: String(repeating: "f", count: 64),
        signerDigest: TransitionFixtures.digestA
      ),
    ]
    let first = try TransitionFixtures.validate(TransitionFixtures.raw(
      predecessor: predecessor,
      dependencies: dependencies,
      artifactDescriptors: TransitionFixtures.descriptors(predecessor: predecessor),
      sideBySideBytes: 140,
      rollbackBytes: 80,
      availableBytes: 140
    ))
    let setsReordered = try TransitionFixtures.validate(TransitionFixtures.raw(
      predecessor: reorderedSets,
      dependencies: dependencies,
      artifactDescriptors: Array(TransitionFixtures.descriptors(
        predecessor: reorderedSets
      ).reversed()),
      sideBySideBytes: 140,
      rollbackBytes: 80,
      availableBytes: 140
    ))
    #expect(first.identityDigest == setsReordered.identityDigest)

    let transitiveOrderChanged = [dependencies[0], dependencies[2], dependencies[1]]
      .enumerated().map {
        LocalModelPredecessorCorpusDependency(
          position: $0.offset,
          predecessorAdmissionDigest: $0.element.predecessorAdmissionDigest,
          corpusLedgerCheckpointDigest: $0.element.corpusLedgerCheckpointDigest,
          corpusLedgerHeadEventDigest: $0.element.corpusLedgerHeadEventDigest,
          corpusAdmissionSealDigest: $0.element.corpusAdmissionSealDigest,
          evaluationSignerFingerprintDigest: $0.element.evaluationSignerFingerprintDigest,
          isCurrent: true,
          invalidated: false
        )
      }
    let orderChanged = try TransitionFixtures.validate(TransitionFixtures.raw(
      predecessor: predecessor,
      dependencies: transitiveOrderChanged,
      artifactDescriptors: TransitionFixtures.descriptors(predecessor: predecessor),
      sideBySideBytes: 140,
      rollbackBytes: 80,
      availableBytes: 140
    ))
    #expect(first.identityDigest != orderChanged.identityDigest)
  }

  @Test func transitionMetadataIsNonselectableAndUpdateIsNeverInferred() throws {
    let withoutTransition = try LocalModelCatalogSnapshot.make(
      for: TransitionFixtures.signedEnvironment,
      promotion: TransitionFixtures.signedPromotion()
    )
    #expect(!withoutTransition.isUpdateAvailable)

    let inputs = try TransitionFixtures.signedTransitionInputs()
    let withTransition = try LocalModelCatalogSnapshot.make(
      for: TransitionFixtures.signedEnvironment,
      promotion: inputs.promotion,
      transitions: [inputs.transition]
    )
    #expect(withTransition.isUpdateAvailable)
    #expect(withTransition.configuration(
      key: inputs.transition.predecessor.configurationKey
    ) == nil)
    #expect(withTransition.profile(
      id: inputs.transition.predecessor.profileIdentityDigests[0]
    ) == nil)
  }

  @Test func snapshotsRejectMultipleOrWrongCapabilityTransitions() throws {
    let inputs = try TransitionFixtures.signedTransitionInputs()
    let ordinary = LocalModelBuildEnvironment(
      architecture: .arm64,
      osMajor: 26,
      languages: ["en"],
      buildCapability: .ordinarySafe,
      claimScope: .general,
      speakerCohort: .generalAdult,
      acousticCohort: .general
    )
    #expect(throws: LocalModelCatalogSnapshotError.transitionNotAllowed) {
      _ = try LocalModelCatalogSnapshot.make(
        for: ordinary,
        transitions: [inputs.transition]
      )
    }
    #expect(throws: LocalModelCatalogSnapshotError.multipleTransitions) {
      _ = try LocalModelCatalogSnapshot.make(
        for: TransitionFixtures.signedEnvironment,
        promotion: inputs.promotion,
        transitions: [inputs.transition, inputs.transition]
      )
    }
  }
}
