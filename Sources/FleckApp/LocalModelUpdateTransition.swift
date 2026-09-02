import CryptoKit
import Foundation

struct LocalModelTransitionArtifactManifest: Equatable, Sendable {
  let manifestDigest: String
  let revision: String
  let closedFileSetDigest: String
  let installedBytes: Int64
}

struct LocalModelTransitionReleaseIdentity: Equatable, Sendable {
  let packageDigest: String
  let admissionRecordDigest: String
  let admission: LocalModelAdmissionState
  let configurationKey: String
  let configurationDigest: String
  let profileIdentityDigests: [String]
  let artifactManifests: [LocalModelTransitionArtifactManifest]
  let installationReceiptSchemaVersion: Int
  let runtimeCompatibilityRevision: String
  let trustPolicySequence: UInt64
  let trustPolicyCheckpointDigest: String
}

struct LocalModelPredecessorCorpusDependency: Equatable, Sendable {
  let position: Int
  let predecessorAdmissionDigest: String
  let corpusLedgerCheckpointDigest: String
  let corpusLedgerHeadEventDigest: String
  let corpusAdmissionSealDigest: String
  let evaluationSignerFingerprintDigest: String
  let isCurrent: Bool
  let invalidated: Bool
}

struct RawLocalModelRollbackPolicy: Equatable, Sendable {
  let sideBySideBytes: Int64
  let stagingBytes: Int64
  let rollbackBytes: Int64
  let availableBytes: Int64
  let retentionDurationMilliseconds: Int64
}

struct RawLocalModelTransitionArtifactDescriptor: Equatable, Sendable {
  let manifestDigest: String
  let side: String
  let role: String
  let closedFileSetDigest: String
  let installedBytes: Int64
}

enum LocalModelTransitionArtifactSide: String, Equatable, Hashable, Sendable {
  case predecessor
  case successor
}

enum LocalModelTransitionArtifactRole: String, Equatable, Sendable {
  case install
  case retainForRollback
  case shared
}

struct LocalModelTransitionArtifactDescriptor: Equatable, Sendable {
  let manifestDigest: String
  let side: LocalModelTransitionArtifactSide
  let role: LocalModelTransitionArtifactRole
  let closedFileSetDigest: String
  let installedBytes: Int64
}

struct RawLocalModelUpdateTransition: Equatable, Sendable {
  let schemaVersion: Int
  let predecessor: LocalModelTransitionReleaseIdentity
  let predecessorUpdateRecordDigest: String
  let successor: LocalModelTransitionReleaseIdentity
  let successorPromotionRecordDigest: String
  let predecessorCorpusDependencies: [LocalModelPredecessorCorpusDependency]
  let lineageValid: Bool
  let artifactDescriptors: [RawLocalModelTransitionArtifactDescriptor]
  let rollback: RawLocalModelRollbackPolicy
}

struct LocalModelRollbackPolicy: Equatable, Sendable {
  let sideBySideBytes: Int64
  let stagingBytes: Int64
  let rollbackBytes: Int64
  let retentionDurationMilliseconds: Int64
}

enum LocalModelUpdateTransitionError: Error, Equatable, Sendable {
  case unsupportedSchema
  case invalidDigest(String)
  case invalidReleaseIdentity
  case predecessorEqualsSuccessor
  case predecessorNotReleaseAdmitted
  case successorMismatch
  case missingArtifactManifest
  case duplicateArtifactManifest(String)
  case mutableArtifactRevision(String)
  case missingCorpusDependency
  case duplicateCorpusDependency(String)
  case reorderedCorpusDependency
  case staleCorpusDependency
  case invalidatedCorpusLineage
  case trustAnchorMismatch
  case staleTrustCheckpoint
  case incompatibleReceiptSchema
  case incompatibleRuntime
  case invalidArtifactDescriptor
  case invalidArtifactDescriptorSide(String)
  case invalidArtifactDescriptorRole(String)
  case missingArtifactDescriptor(LocalModelTransitionArtifactSide, String)
  case extraArtifactDescriptor(LocalModelTransitionArtifactSide, String)
  case duplicateArtifactDescriptor(LocalModelTransitionArtifactSide, String)
  case artifactDescriptorManifestMismatch(LocalModelTransitionArtifactSide, String)
  case artifactDescriptorRoleMismatch(LocalModelTransitionArtifactSide, String)
  case inconsistentSharedArtifactManifest(String)
  case invalidRollbackPolicy
  case insufficientRollbackReserve
  case byteCountOverflow
}

private struct LocalModelTransitionArtifactDescriptorKey: Hashable {
  let side: LocalModelTransitionArtifactSide
  let manifestDigest: String
}

struct LocalModelUpdateTransition: Equatable, Sendable {
  static let schemaVersion = 1
  static let installationReceiptSchemaVersion = 1
  static let runtimeCompatibilityRevision = "fleck.local-writing-runtime.v1"

  let identityDigest: String
  let predecessor: LocalModelTransitionReleaseIdentity
  let predecessorUpdateRecordDigest: String
  let successor: LocalModelTransitionReleaseIdentity
  let successorPromotionRecordDigest: String
  let predecessorCorpusDependencies: [LocalModelPredecessorCorpusDependency]
  let artifactDescriptors: [LocalModelTransitionArtifactDescriptor]
  let rollback: LocalModelRollbackPolicy

  private init(
    identityDigest: String,
    predecessor: LocalModelTransitionReleaseIdentity,
    predecessorUpdateRecordDigest: String,
    successor: LocalModelTransitionReleaseIdentity,
    successorPromotionRecordDigest: String,
    predecessorCorpusDependencies: [LocalModelPredecessorCorpusDependency],
    artifactDescriptors: [LocalModelTransitionArtifactDescriptor],
    rollback: LocalModelRollbackPolicy
  ) {
    self.identityDigest = identityDigest
    self.predecessor = predecessor
    self.predecessorUpdateRecordDigest = predecessorUpdateRecordDigest
    self.successor = successor
    self.successorPromotionRecordDigest = successorPromotionRecordDigest
    self.predecessorCorpusDependencies = predecessorCorpusDependencies
    self.artifactDescriptors = artifactDescriptors
    self.rollback = rollback
  }

  static func validating(
    _ raw: RawLocalModelUpdateTransition,
    expectedSuccessor: LocalModelTransitionReleaseIdentity,
    currentTrustPolicySequence: UInt64,
    currentTrustPolicyCheckpointDigest: String
  ) throws -> LocalModelUpdateTransition {
    guard raw.schemaVersion == schemaVersion else {
      throw LocalModelUpdateTransitionError.unsupportedSchema
    }
    try validateDigest(raw.predecessorUpdateRecordDigest)
    try validateDigest(raw.successorPromotionRecordDigest)
    try validateDigest(currentTrustPolicyCheckpointDigest)

    let predecessor = try canonicalRelease(raw.predecessor)
    let successor = try canonicalRelease(raw.successor)
    let expectedSuccessor = try canonicalRelease(expectedSuccessor)
    guard predecessor.packageDigest != successor.packageDigest
            || predecessor.configurationDigest != successor.configurationDigest else {
      throw LocalModelUpdateTransitionError.predecessorEqualsSuccessor
    }
    guard predecessor.admission == .releaseAdmitted else {
      throw LocalModelUpdateTransitionError.predecessorNotReleaseAdmitted
    }
    guard successor == expectedSuccessor,
          successor.admission == .twoDeviceAccepted,
          raw.successorPromotionRecordDigest == successor.admissionRecordDigest else {
      throw LocalModelUpdateTransitionError.successorMismatch
    }
    guard predecessor.trustPolicySequence <= currentTrustPolicySequence,
          successor.trustPolicySequence <= currentTrustPolicySequence else {
      throw LocalModelUpdateTransitionError.staleTrustCheckpoint
    }
    guard predecessor.trustPolicySequence == currentTrustPolicySequence,
          successor.trustPolicySequence == currentTrustPolicySequence else {
      throw LocalModelUpdateTransitionError.staleTrustCheckpoint
    }
    guard predecessor.trustPolicyCheckpointDigest == currentTrustPolicyCheckpointDigest,
          successor.trustPolicyCheckpointDigest == currentTrustPolicyCheckpointDigest else {
      throw LocalModelUpdateTransitionError.trustAnchorMismatch
    }
    guard predecessor.installationReceiptSchemaVersion
            == installationReceiptSchemaVersion,
          successor.installationReceiptSchemaVersion
            == installationReceiptSchemaVersion else {
      throw LocalModelUpdateTransitionError.incompatibleReceiptSchema
    }
    guard predecessor.runtimeCompatibilityRevision == runtimeCompatibilityRevision,
          successor.runtimeCompatibilityRevision == runtimeCompatibilityRevision else {
      throw LocalModelUpdateTransitionError.incompatibleRuntime
    }
    guard raw.lineageValid else {
      throw LocalModelUpdateTransitionError.invalidatedCorpusLineage
    }

    let dependencies = try validateDependencies(
      raw.predecessorCorpusDependencies,
      predecessorAdmissionDigest: predecessor.admissionRecordDigest
    )
    let artifactDescriptors = try validateArtifactDescriptors(
      raw.artifactDescriptors,
      predecessorManifests: predecessor.artifactManifests,
      successorManifests: successor.artifactManifests
    )
    let rollback = try validateRollback(
      raw.rollback,
      predecessorInstalledBytes: installedBytes(predecessor.artifactManifests),
      successorInstalledBytes: installedBytes(successor.artifactManifests)
    )
    let identityDigest = try canonicalDigest(
      predecessor: predecessor,
      predecessorUpdateRecordDigest: raw.predecessorUpdateRecordDigest,
      successor: successor,
      successorPromotionRecordDigest: raw.successorPromotionRecordDigest,
      dependencies: dependencies,
      artifactDescriptors: artifactDescriptors,
      rollback: rollback
    )
    return .init(
      identityDigest: identityDigest,
      predecessor: predecessor,
      predecessorUpdateRecordDigest: raw.predecessorUpdateRecordDigest,
      successor: successor,
      successorPromotionRecordDigest: raw.successorPromotionRecordDigest,
      predecessorCorpusDependencies: dependencies,
      artifactDescriptors: artifactDescriptors,
      rollback: rollback
    )
  }

  private static func canonicalRelease(
    _ release: LocalModelTransitionReleaseIdentity
  ) throws -> LocalModelTransitionReleaseIdentity {
    for digest in [
      release.packageDigest,
      release.admissionRecordDigest,
      release.configurationDigest,
      release.trustPolicyCheckpointDigest,
    ] + release.profileIdentityDigests {
      try validateDigest(digest)
    }
    guard !release.configurationKey.isEmpty,
          release.configurationKey == release.configurationKey
            .trimmingCharacters(in: .whitespacesAndNewlines),
          release.trustPolicySequence > 0,
          !release.profileIdentityDigests.isEmpty,
          Set(release.profileIdentityDigests).count
            == release.profileIdentityDigests.count else {
      throw LocalModelUpdateTransitionError.invalidReleaseIdentity
    }
    guard !release.artifactManifests.isEmpty else {
      throw LocalModelUpdateTransitionError.missingArtifactManifest
    }
    var seen = Set<String>()
    for manifest in release.artifactManifests {
      try validateDigest(manifest.manifestDigest)
      try validateDigest(manifest.closedFileSetDigest)
      guard seen.insert(manifest.manifestDigest).inserted else {
        throw LocalModelUpdateTransitionError.duplicateArtifactManifest(
          manifest.manifestDigest
        )
      }
      guard isImmutableRevision(manifest.revision) else {
        throw LocalModelUpdateTransitionError.mutableArtifactRevision(manifest.revision)
      }
      guard manifest.installedBytes > 0 else {
        throw LocalModelUpdateTransitionError.invalidReleaseIdentity
      }
    }
    return .init(
      packageDigest: release.packageDigest,
      admissionRecordDigest: release.admissionRecordDigest,
      admission: release.admission,
      configurationKey: release.configurationKey,
      configurationDigest: release.configurationDigest,
      profileIdentityDigests: release.profileIdentityDigests.sorted(),
      artifactManifests: release.artifactManifests.sorted {
        $0.manifestDigest < $1.manifestDigest
      },
      installationReceiptSchemaVersion: release.installationReceiptSchemaVersion,
      runtimeCompatibilityRevision: release.runtimeCompatibilityRevision,
      trustPolicySequence: release.trustPolicySequence,
      trustPolicyCheckpointDigest: release.trustPolicyCheckpointDigest
    )
  }

  private static func validateDependencies(
    _ dependencies: [LocalModelPredecessorCorpusDependency],
    predecessorAdmissionDigest: String
  ) throws -> [LocalModelPredecessorCorpusDependency] {
    guard !dependencies.isEmpty else {
      throw LocalModelUpdateTransitionError.missingCorpusDependency
    }
    var seen = Set<String>()
    for (position, dependency) in dependencies.enumerated() {
      guard dependency.position == position else {
        throw LocalModelUpdateTransitionError.reorderedCorpusDependency
      }
      for digest in [
        dependency.predecessorAdmissionDigest,
        dependency.corpusLedgerCheckpointDigest,
        dependency.corpusLedgerHeadEventDigest,
        dependency.corpusAdmissionSealDigest,
        dependency.evaluationSignerFingerprintDigest,
      ] {
        try validateDigest(digest)
      }
      guard seen.insert(dependency.predecessorAdmissionDigest).inserted else {
        throw LocalModelUpdateTransitionError.duplicateCorpusDependency(
          dependency.predecessorAdmissionDigest
        )
      }
      guard dependency.isCurrent else {
        throw LocalModelUpdateTransitionError.staleCorpusDependency
      }
      guard !dependency.invalidated else {
        throw LocalModelUpdateTransitionError.invalidatedCorpusLineage
      }
    }
    guard dependencies[0].predecessorAdmissionDigest == predecessorAdmissionDigest else {
      throw LocalModelUpdateTransitionError.invalidatedCorpusLineage
    }
    return dependencies
  }

  private static func validateArtifactDescriptors(
    _ rawDescriptors: [RawLocalModelTransitionArtifactDescriptor],
    predecessorManifests: [LocalModelTransitionArtifactManifest],
    successorManifests: [LocalModelTransitionArtifactManifest]
  ) throws -> [LocalModelTransitionArtifactDescriptor] {
    let predecessorByDigest = Dictionary(
      uniqueKeysWithValues: predecessorManifests.map { ($0.manifestDigest, $0) }
    )
    let successorByDigest = Dictionary(
      uniqueKeysWithValues: successorManifests.map { ($0.manifestDigest, $0) }
    )

    let sharedDigests = Set(predecessorByDigest.keys)
      .intersection(successorByDigest.keys)
      .sorted()
    for digest in sharedDigests {
      guard let predecessor = predecessorByDigest[digest],
            let successor = successorByDigest[digest],
            predecessor.revision == successor.revision,
            predecessor.closedFileSetDigest == successor.closedFileSetDigest,
            predecessor.installedBytes == successor.installedBytes else {
        throw LocalModelUpdateTransitionError.inconsistentSharedArtifactManifest(digest)
      }
    }

    var seen = Set<LocalModelTransitionArtifactDescriptorKey>()
    var descriptors: [LocalModelTransitionArtifactDescriptor] = []
    for rawDescriptor in rawDescriptors {
      try validateDigest(rawDescriptor.manifestDigest)
      try validateDigest(rawDescriptor.closedFileSetDigest)
      guard rawDescriptor.installedBytes > 0 else {
        throw LocalModelUpdateTransitionError.invalidArtifactDescriptor
      }
      guard let side = LocalModelTransitionArtifactSide(
        rawValue: rawDescriptor.side
      ) else {
        throw LocalModelUpdateTransitionError.invalidArtifactDescriptorSide(
          rawDescriptor.side
        )
      }
      guard let role = LocalModelTransitionArtifactRole(
        rawValue: rawDescriptor.role
      ) else {
        throw LocalModelUpdateTransitionError.invalidArtifactDescriptorRole(
          rawDescriptor.role
        )
      }
      let key = LocalModelTransitionArtifactDescriptorKey(
        side: side,
        manifestDigest: rawDescriptor.manifestDigest
      )
      guard seen.insert(key).inserted else {
        throw LocalModelUpdateTransitionError.duplicateArtifactDescriptor(
          side,
          rawDescriptor.manifestDigest
        )
      }

      let sideManifests = side == .predecessor
        ? predecessorByDigest : successorByDigest
      guard let manifest = sideManifests[rawDescriptor.manifestDigest] else {
        throw LocalModelUpdateTransitionError.extraArtifactDescriptor(
          side,
          rawDescriptor.manifestDigest
        )
      }
      guard rawDescriptor.closedFileSetDigest == manifest.closedFileSetDigest,
            rawDescriptor.installedBytes == manifest.installedBytes else {
        throw LocalModelUpdateTransitionError.artifactDescriptorManifestMismatch(
          side,
          rawDescriptor.manifestDigest
        )
      }

      let appearsOnOtherSide = side == .predecessor
        ? successorByDigest[rawDescriptor.manifestDigest] != nil
        : predecessorByDigest[rawDescriptor.manifestDigest] != nil
      let expectedRole: LocalModelTransitionArtifactRole
      if appearsOnOtherSide {
        expectedRole = .shared
      } else if side == .predecessor {
        expectedRole = .retainForRollback
      } else {
        expectedRole = .install
      }
      guard role == expectedRole else {
        throw LocalModelUpdateTransitionError.artifactDescriptorRoleMismatch(
          side,
          rawDescriptor.manifestDigest
        )
      }
      descriptors.append(.init(
        manifestDigest: rawDescriptor.manifestDigest,
        side: side,
        role: role,
        closedFileSetDigest: rawDescriptor.closedFileSetDigest,
        installedBytes: rawDescriptor.installedBytes
      ))
    }

    for (side, manifests) in [
      (LocalModelTransitionArtifactSide.predecessor, predecessorManifests),
      (.successor, successorManifests),
    ] {
      for manifest in manifests where !seen.contains(.init(
        side: side,
        manifestDigest: manifest.manifestDigest
      )) {
        throw LocalModelUpdateTransitionError.missingArtifactDescriptor(
          side,
          manifest.manifestDigest
        )
      }
    }

    return descriptors.sorted {
      ($0.side.rawValue, $0.manifestDigest) < ($1.side.rawValue, $1.manifestDigest)
    }
  }

  private static func validateRollback(
    _ raw: RawLocalModelRollbackPolicy,
    predecessorInstalledBytes: Int64,
    successorInstalledBytes: Int64
  ) throws -> LocalModelRollbackPolicy {
    guard raw.sideBySideBytes > 0,
          raw.stagingBytes > 0,
          raw.rollbackBytes > 0,
          raw.availableBytes > 0,
          raw.retentionDurationMilliseconds > 0 else {
      throw LocalModelUpdateTransitionError.invalidRollbackPolicy
    }
    let (required, overflow) = raw.stagingBytes.addingReportingOverflow(
      raw.rollbackBytes
    )
    guard !overflow else {
      throw LocalModelUpdateTransitionError.byteCountOverflow
    }
    guard raw.sideBySideBytes == required,
          raw.rollbackBytes >= predecessorInstalledBytes,
          raw.stagingBytes >= successorInstalledBytes,
          raw.availableBytes >= required else {
      throw LocalModelUpdateTransitionError.insufficientRollbackReserve
    }
    return .init(
      sideBySideBytes: raw.sideBySideBytes,
      stagingBytes: raw.stagingBytes,
      rollbackBytes: raw.rollbackBytes,
      retentionDurationMilliseconds: raw.retentionDurationMilliseconds
    )
  }

  private static func installedBytes(
    _ manifests: [LocalModelTransitionArtifactManifest]
  ) throws -> Int64 {
    try manifests.reduce(0) { total, manifest in
      let (sum, overflow) = total.addingReportingOverflow(manifest.installedBytes)
      guard !overflow else {
        throw LocalModelUpdateTransitionError.byteCountOverflow
      }
      return sum
    }
  }

  private static func validateDigest(_ digest: String) throws {
    guard digest.count == 64,
          digest.allSatisfy({ "0123456789abcdef".contains($0) }),
          digest.contains(where: { $0 != "0" }) else {
      throw LocalModelUpdateTransitionError.invalidDigest(digest)
    }
  }

  private static func isImmutableRevision(_ revision: String) -> Bool {
    revision.count == 40
      && revision.allSatisfy { "0123456789abcdef".contains($0) }
  }

  private static func canonicalDigest(
    predecessor: LocalModelTransitionReleaseIdentity,
    predecessorUpdateRecordDigest: String,
    successor: LocalModelTransitionReleaseIdentity,
    successorPromotionRecordDigest: String,
    dependencies: [LocalModelPredecessorCorpusDependency],
    artifactDescriptors: [LocalModelTransitionArtifactDescriptor],
    rollback: LocalModelRollbackPolicy
  ) throws -> String {
    var encoder = LocalModelTransitionCanonicalEncoder()
    try encoder.append("fleck.local-model-update-transition.v1")
    try encoder.appendRelease(predecessor)
    try encoder.append(predecessorUpdateRecordDigest)
    try encoder.appendRelease(successor)
    try encoder.append(successorPromotionRecordDigest)
    try encoder.appendCount(dependencies.count)
    for dependency in dependencies {
      try encoder.append(String(dependency.position))
      try encoder.append(dependency.predecessorAdmissionDigest)
      try encoder.append(dependency.corpusLedgerCheckpointDigest)
      try encoder.append(dependency.corpusLedgerHeadEventDigest)
      try encoder.append(dependency.corpusAdmissionSealDigest)
      try encoder.append(dependency.evaluationSignerFingerprintDigest)
    }
    try encoder.appendCount(artifactDescriptors.count)
    for descriptor in artifactDescriptors {
      try encoder.append(descriptor.manifestDigest)
      try encoder.append(descriptor.side.rawValue)
      try encoder.append(descriptor.role.rawValue)
      try encoder.append(descriptor.closedFileSetDigest)
      try encoder.append(String(descriptor.installedBytes))
    }
    try encoder.append(String(rollback.sideBySideBytes))
    try encoder.append(String(rollback.stagingBytes))
    try encoder.append(String(rollback.rollbackBytes))
    try encoder.append(String(rollback.retentionDurationMilliseconds))
    return SHA256.hash(data: encoder.data)
      .map { String(format: "%02x", $0) }
      .joined()
  }
}

private struct LocalModelTransitionCanonicalEncoder {
  private(set) var data = Data()

  mutating func appendRelease(
    _ release: LocalModelTransitionReleaseIdentity
  ) throws {
    try append(release.packageDigest)
    try append(release.admissionRecordDigest)
    try append(release.admission.rawValue)
    try append(release.configurationKey)
    try append(release.configurationDigest)
    try append(release.profileIdentityDigests)
    try appendCount(release.artifactManifests.count)
    for manifest in release.artifactManifests {
      try append(manifest.manifestDigest)
      try append(manifest.revision)
      try append(manifest.closedFileSetDigest)
      try append(String(manifest.installedBytes))
    }
    try append(String(release.installationReceiptSchemaVersion))
    try append(release.runtimeCompatibilityRevision)
    try append(String(release.trustPolicySequence))
    try append(release.trustPolicyCheckpointDigest)
  }

  mutating func append(_ values: [String]) throws {
    try appendCount(values.count)
    for value in values { try append(value) }
  }

  mutating func appendCount(_ count: Int) throws {
    guard let count = UInt64(exactly: count) else {
      throw LocalModelUpdateTransitionError.byteCountOverflow
    }
    appendLength(count)
  }

  mutating func append(_ value: String) throws {
    let bytes = Data(value.utf8)
    guard let count = UInt64(exactly: bytes.count) else {
      throw LocalModelUpdateTransitionError.byteCountOverflow
    }
    appendLength(count)
    data.append(bytes)
  }

  private mutating func appendLength(_ length: UInt64) {
    var bigEndian = length.bigEndian
    withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
  }
}
