import Foundation
import Testing

@testable import FleckApp

private enum TransitionFixtures {
  static let digestA = String(repeating: "a", count: 64)
  static let digestB = String(repeating: "b", count: 64)
  static let digestC = String(repeating: "c", count: 64)
  static let digestD = String(repeating: "d", count: 64)
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
    admissionDigest: String = digestA,
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

  static func raw(
    schemaVersion: Int = 1,
    predecessor: LocalModelTransitionReleaseIdentity = predecessor,
    successor: LocalModelTransitionReleaseIdentity = successor,
    dependencies: [LocalModelPredecessorCorpusDependency] = [dependency()],
    lineageValid: Bool = true,
    referenceRoles: [String] = ["install", "retainForRollback"],
    sideBySideBytes: Int64 = 100,
    stagingBytes: Int64 = 60,
    rollbackBytes: Int64 = 40,
    availableBytes: Int64 = 100,
    rollbackDurationMilliseconds: Int64 = 86_400_000
  ) -> RawLocalModelUpdateTransition {
    .init(
      schemaVersion: schemaVersion,
      predecessor: predecessor,
      successor: successor,
      successorPromotionRecordDigest: digestD,
      predecessorCorpusDependencies: dependencies,
      lineageValid: lineageValid,
      referenceRoles: referenceRoles,
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
}

@Suite struct LocalModelUpdateTransitionTests {
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
       .duplicateCorpusDependency(TransitionFixtures.digestA)),
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
        admissionDigest: TransitionFixtures.digestB,
        checkpointDigest: TransitionFixtures.digestC,
        headDigest: TransitionFixtures.digestD,
        sealDigest: String(repeating: "e", count: 64),
        signerDigest: String(repeating: "f", count: 64)
      ),
    ]
    let first = try TransitionFixtures.validate(TransitionFixtures.raw(
      predecessor: predecessor,
      dependencies: dependencies,
      referenceRoles: ["install", "retainForRollback", "shared"]
    ))
    let setsReordered = try TransitionFixtures.validate(TransitionFixtures.raw(
      predecessor: reorderedSets,
      dependencies: dependencies,
      referenceRoles: ["shared", "retainForRollback", "install"]
    ))
    #expect(first.identityDigest == setsReordered.identityDigest)

    let reversedDependencies = Array(dependencies.reversed().enumerated()).map {
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
      dependencies: reversedDependencies,
      referenceRoles: ["install", "retainForRollback", "shared"]
    ))
    #expect(first.identityDigest != orderChanged.identityDigest)
  }

  @Test func transitionMetadataIsNonselectableAndUpdateIsNeverInferred() throws {
    let transition = try TransitionFixtures.validate()
    let successorConfiguration = LocalModelConfiguration(
      key: transition.successor.configurationKey,
      digest: transition.successor.configurationDigest,
      profiles: []
    )
    let withoutTransition = try LocalModelCatalogSnapshot.validated(
      buildCapability: .signedDistributionCandidate,
      configurations: [successorConfiguration],
      promotionManagedProfileIDs: [],
      transitions: []
    )
    #expect(!withoutTransition.isUpdateAvailable)

    let withTransition = try LocalModelCatalogSnapshot.validated(
      buildCapability: .signedDistributionCandidate,
      configurations: [successorConfiguration],
      promotionManagedProfileIDs: [],
      transitions: [transition]
    )
    #expect(withTransition.isUpdateAvailable)
    #expect(withTransition.configuration(key: transition.predecessor.configurationKey) == nil)
    #expect(withTransition.profile(id: transition.predecessor.profileIdentityDigests[0]) == nil)
  }

  @Test func snapshotsRejectMultipleOrWrongCapabilityTransitions() throws {
    let transition = try TransitionFixtures.validate()
    for capability in [
      LocalModelBuildCapability.ordinarySafe,
      .developmentQuality,
    ] {
      #expect(throws: LocalModelCatalogSnapshotError.transitionNotAllowed) {
        _ = try LocalModelCatalogSnapshot.validated(
          buildCapability: capability,
          configurations: [],
          promotionManagedProfileIDs: [],
          transitions: [transition]
        )
      }
    }
    #expect(throws: LocalModelCatalogSnapshotError.multipleTransitions) {
      _ = try LocalModelCatalogSnapshot.validated(
        buildCapability: .signedDistributionCandidate,
        configurations: [],
        promotionManagedProfileIDs: [],
        transitions: [transition, transition]
      )
    }
  }
}
