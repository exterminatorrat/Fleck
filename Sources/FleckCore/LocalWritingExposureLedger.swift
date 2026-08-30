import CryptoKit
import Darwin
import Foundation

public enum LocalWritingExposureLedgerError: String, Error, Equatable, Sendable,
  CustomStringConvertible
{
  case conflict
  case corruption
  case nonCanonicalData
  case identityMismatch
  case invalidOrder
  case invalidation
  case permissions
  case ioFailure

  public var description: String { rawValue }
}

public enum LocalWritingExposureEventKind: String, Equatable, Sendable {
  case candidateExposure
  case materialLineageInvalidation
}

public enum LocalWritingExposureExecutionStratum: String, Equatable, Sendable {
  case e1, e2, e3
}

public enum LocalWritingMaterialLineageInvalidationReason: String, Equatable,
  Sendable
{
  case oracleCorrectedAfterExposure
  case exposedMaterialDeleted
  case sourceMaterialIntegrityFailed
}

public struct LocalWritingCandidateExposure: Equatable, Sendable {
  public let corpusID: UUID
  public let caseID: UUID
  public let materialLineageID: UUID
  public let candidateIdentitySHA256: String
  public let configurationIdentitySHA256: String
  public let roleProfileIdentitySHA256: String
  public let executionIdentitySHA256: String
  public let executionStratum: LocalWritingExposureExecutionStratum

  public init(
    corpusID: UUID,
    caseID: UUID,
    materialLineageID: UUID,
    candidateIdentitySHA256: String,
    configurationIdentitySHA256: String,
    roleProfileIdentitySHA256: String,
    executionIdentitySHA256: String,
    executionStratum: LocalWritingExposureExecutionStratum
  ) throws {
    guard isExposureDigest(candidateIdentitySHA256),
      isExposureDigest(configurationIdentitySHA256),
      isExposureDigest(roleProfileIdentitySHA256),
      isExposureDigest(executionIdentitySHA256)
    else { throw LocalWritingExposureLedgerError.identityMismatch }
    self.corpusID = corpusID
    self.caseID = caseID
    self.materialLineageID = materialLineageID
    self.candidateIdentitySHA256 = candidateIdentitySHA256
    self.configurationIdentitySHA256 = configurationIdentitySHA256
    self.roleProfileIdentitySHA256 = roleProfileIdentitySHA256
    self.executionIdentitySHA256 = executionIdentitySHA256
    self.executionStratum = executionStratum
  }
}

public struct LocalWritingMaterialLineageInvalidation: Equatable, Sendable {
  public let corpusID: UUID
  public let caseID: UUID
  public let materialLineageID: UUID
  public let reason: LocalWritingMaterialLineageInvalidationReason

  public init(
    corpusID: UUID,
    caseID: UUID,
    materialLineageID: UUID,
    reason: LocalWritingMaterialLineageInvalidationReason
  ) throws {
    self.corpusID = corpusID
    self.caseID = caseID
    self.materialLineageID = materialLineageID
    self.reason = reason
  }
}

public enum LocalWritingExposureEventPayload: Equatable, Sendable {
  case candidateExposure(LocalWritingCandidateExposure)
  case materialLineageInvalidation(LocalWritingMaterialLineageInvalidation)

  public var kind: LocalWritingExposureEventKind {
    switch self {
    case .candidateExposure: .candidateExposure
    case .materialLineageInvalidation: .materialLineageInvalidation
    }
  }
}

public struct LocalWritingExposureEventEnvelope: Equatable, Sendable {
  public let schemaVersion: Int
  public let sequence: UInt64
  public let previousEventSHA256: String
  public let eventSHA256: String
  public let payload: LocalWritingExposureEventPayload

  fileprivate init(
    sequence: UInt64,
    previousEventSHA256: String,
    eventSHA256: String,
    payload: LocalWritingExposureEventPayload
  ) {
    schemaVersion = 1
    self.sequence = sequence
    self.previousEventSHA256 = previousEventSHA256
    self.eventSHA256 = eventSHA256
    self.payload = payload
  }
}

public struct LocalWritingExposureLedgerCheckpoint: Equatable, Sendable {
  public let schemaVersion: Int
  public let corpusID: UUID
  public let eventCount: UInt64
  public let currentHeadSHA256: String

  fileprivate init(
    corpusID: UUID,
    eventCount: UInt64,
    currentHeadSHA256: String
  ) {
    schemaVersion = 1
    self.corpusID = corpusID
    self.eventCount = eventCount
    self.currentHeadSHA256 = currentHeadSHA256
  }

  public var canonicalData: Data {
    Data(
      "{\"corpusID\":\"\(canonicalExposureUUID(corpusID))\",\"currentHeadSHA256\":\"\(currentHeadSHA256)\",\"eventCount\":\(eventCount),\"schemaVersion\":1}".utf8
    )
  }
}

public struct LocalWritingExposureLedgerExtension: Equatable, Sendable {
  public let schemaVersion: Int
  public let corpusID: UUID
  public let parentCheckpoint: LocalWritingExposureLedgerCheckpoint
  public let childCheckpoint: LocalWritingExposureLedgerCheckpoint
  public let canonicalData: Data

  fileprivate init(
    corpusID: UUID,
    parentCheckpoint: LocalWritingExposureLedgerCheckpoint,
    childCheckpoint: LocalWritingExposureLedgerCheckpoint,
    canonicalData: Data
  ) {
    schemaVersion = 1
    self.corpusID = corpusID
    self.parentCheckpoint = parentCheckpoint
    self.childCheckpoint = childCheckpoint
    self.canonicalData = canonicalData
  }
}

public struct LocalWritingExposureLedgerVerification: Equatable, Sendable {
  public let checkpoint: LocalWritingExposureLedgerCheckpoint
  public let events: [LocalWritingExposureEventEnvelope]
  private let genesisSHA256: String

  fileprivate init(
    checkpoint: LocalWritingExposureLedgerCheckpoint,
    events: [LocalWritingExposureEventEnvelope],
    genesisSHA256: String
  ) {
    self.checkpoint = checkpoint
    self.events = events
    self.genesisSHA256 = genesisSHA256
  }

  public func isAncestor(_ headSHA256: String) -> Bool {
    headSHA256 == genesisSHA256 || events.contains { $0.eventSHA256 == headSHA256 }
  }

  public func hasLaterInvalidation(
    materialLineageID: UUID,
    after consumedHeadSHA256: String
  ) -> Bool {
    guard let consumedIndex = index(of: consumedHeadSHA256) else { return true }
    return events.enumerated().contains { index, event in
      guard index > consumedIndex,
        case .materialLineageInvalidation(let invalidation) = event.payload
      else { return false }
      return invalidation.materialLineageID == materialLineageID
    }
  }

  public func scoringEligibility(
    exposure: LocalWritingCandidateExposure,
    consumedAt consumedHeadSHA256: String
  ) -> LocalWritingScoringEligibility {
    guard exposure.corpusID == checkpoint.corpusID,
      let consumedIndex = index(of: consumedHeadSHA256),
      events.enumerated().contains(where: { index, event in
        guard index <= consumedIndex,
          case .candidateExposure(let existing) = event.payload
        else { return false }
        return existing == exposure
      })
    else {
      return .diagnosticOnlyPostExposure
    }
    let invalidated = events.contains { event in
      guard case .materialLineageInvalidation(let invalidation) = event.payload else {
        return false
      }
      return invalidation.caseID == exposure.caseID
        && invalidation.materialLineageID == exposure.materialLineageID
    }
    return invalidated ? .diagnosticOnlyPostExposure : .admissionEligible
  }

  private func index(of headSHA256: String) -> Int? {
    if headSHA256 == genesisSHA256 { return -1 }
    return events.firstIndex { $0.eventSHA256 == headSHA256 }
  }

  fileprivate func checkpoint(
    at eventCount: UInt64
  ) -> LocalWritingExposureLedgerCheckpoint? {
    guard eventCount <= UInt64(events.count) else { return nil }
    let head = eventCount == 0
      ? genesisSHA256
      : events[Int(eventCount - 1)].eventSHA256
    return LocalWritingExposureLedgerCheckpoint(
      corpusID: checkpoint.corpusID,
      eventCount: eventCount,
      currentHeadSHA256: head
    )
  }
}

enum LocalWritingExposureLedgerFaultPoint: Equatable, Sendable {
  case afterLockAcquired
  case afterStageSync
  case afterStageWriteCloseBeforeReadOpen
  case beforeRename
  case afterRenameBeforeDirectorySync
}

public final class LocalWritingExposureLedger: @unchecked Sendable {
  static let maximumLedgerBytes = 4 * 1_024 * 1_024
  private static let maximumLineBytes = 2_048

  public let ledgerURL: URL
  public let lockURL: URL
  public let corpusID: UUID
  var faultHook: ((LocalWritingExposureLedgerFaultPoint) throws -> Void)?
  var directorySyncObserver: (() -> Void)?
  private let directoryURL: URL
  private let directoryDescriptor: Int32
  private let directoryIdentity: AuthorityIdentity
  private let ledgerName: String
  private let lockName: String
  private let lockIdentity: AuthorityIdentity

  private init(
    ledgerURL: URL,
    corpusID: UUID,
    directoryDescriptor: Int32,
    directoryIdentity: AuthorityIdentity,
    lockIdentity: AuthorityIdentity
  ) {
    self.ledgerURL = ledgerURL
    lockURL = ledgerURL.appendingPathExtension("lock")
    self.corpusID = corpusID
    directoryURL = ledgerURL.deletingLastPathComponent()
    self.directoryDescriptor = directoryDescriptor
    self.directoryIdentity = directoryIdentity
    ledgerName = ledgerURL.lastPathComponent
    lockName = lockURL.lastPathComponent
    self.lockIdentity = lockIdentity
  }

  deinit {
    Darwin.close(directoryDescriptor)
  }

  public static func create(at ledgerURL: URL, corpusID: UUID) throws -> Self {
    let directory = try openDirectoryAuthority(for: ledgerURL)
    var directoryTransferred = false
    defer {
      if !directoryTransferred { Darwin.close(directory.descriptor) }
    }
    let ledgerName = ledgerURL.lastPathComponent
    let lockURL = ledgerURL.appendingPathExtension("lock")
    let lockName = lockURL.lastPathComponent
    try requireAbsent(name: ledgerName, in: directory.descriptor)
    try requireAbsent(name: lockName, in: directory.descriptor)
    try requireDirectoryIdentity(
      directory.identity,
      descriptor: directory.descriptor,
      url: ledgerURL.deletingLastPathComponent()
    )

    let lockDescriptor = Darwin.openat(
      directory.descriptor,
      lockName,
      O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW,
      mode_t(0o600)
    )
    guard lockDescriptor >= 0 else { throw mappedSystemError() }
    var keepLock = false
    var createdLockIdentity: AuthorityIdentity?
    defer {
      Darwin.close(lockDescriptor)
      if !keepLock,
        let createdLockIdentity,
        (try? authorityIdentity(name: lockName, in: directory.descriptor))
          == createdLockIdentity
      {
        Darwin.unlinkat(directory.descriptor, lockName, 0)
      }
    }
    guard fchmod(lockDescriptor, 0o600) == 0 else {
      throw LocalWritingExposureLedgerError.ioFailure
    }
    let lockIdentity = try validateAuthorityDescriptor(lockDescriptor)
    createdLockIdentity = lockIdentity
    guard fsync(lockDescriptor) == 0 else {
      throw LocalWritingExposureLedgerError.ioFailure
    }
    try requireNamedIdentity(
      lockIdentity,
      name: lockName,
      in: directory.descriptor
    )
    try requireDirectoryIdentity(
      directory.identity,
      descriptor: directory.descriptor,
      url: ledgerURL.deletingLastPathComponent()
    )

    let header = try canonicalHeader(corpusID: corpusID)
    let ledgerDescriptor = Darwin.openat(
      directory.descriptor,
      ledgerName,
      O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
      mode_t(0o600)
    )
    guard ledgerDescriptor >= 0 else { throw mappedSystemError() }
    var keepLedger = false
    var createdLedgerIdentity: AuthorityIdentity?
    defer {
      Darwin.close(ledgerDescriptor)
      if !keepLedger,
        let createdLedgerIdentity,
        (try? authorityIdentity(name: ledgerName, in: directory.descriptor))
          == createdLedgerIdentity
      {
        Darwin.unlinkat(directory.descriptor, ledgerName, 0)
      }
    }
    guard fchmod(ledgerDescriptor, 0o600) == 0 else {
      throw LocalWritingExposureLedgerError.ioFailure
    }
    let ledgerIdentity = try validateAuthorityDescriptor(ledgerDescriptor)
    createdLedgerIdentity = ledgerIdentity
    try writeAll(header, to: ledgerDescriptor)
    guard fsync(ledgerDescriptor) == 0 else {
      throw LocalWritingExposureLedgerError.ioFailure
    }
    try requireNamedIdentity(
      ledgerIdentity,
      name: ledgerName,
      in: directory.descriptor
    )
    try requireDirectoryIdentity(
      directory.identity,
      descriptor: directory.descriptor,
      url: ledgerURL.deletingLastPathComponent()
    )
    try requireNamedIdentity(
      lockIdentity,
      name: lockName,
      in: directory.descriptor
    )
    try syncDirectory(directory.descriptor)
    keepLedger = true
    keepLock = true

    let store = Self(
      ledgerURL: ledgerURL,
      corpusID: corpusID,
      directoryDescriptor: directory.descriptor,
      directoryIdentity: directory.identity,
      lockIdentity: lockIdentity
    )
    directoryTransferred = true
    _ = try store.verify(expectedCorpusID: corpusID)
    return store
  }

  public static func open(at ledgerURL: URL) throws -> Self {
    let directory = try openDirectoryAuthority(for: ledgerURL)
    var directoryTransferred = false
    defer {
      if !directoryTransferred { Darwin.close(directory.descriptor) }
    }
    let lockURL = ledgerURL.appendingPathExtension("lock")
    let ledgerName = ledgerURL.lastPathComponent
    let lockName = lockURL.lastPathComponent
    let ledgerIdentity = try authorityIdentity(
      name: ledgerName,
      in: directory.descriptor
    )
    let lockIdentity = try authorityIdentity(
      name: lockName,
      in: directory.descriptor
    )
    let data = try readAuthorityFile(
      name: ledgerName,
      expectedIdentity: ledgerIdentity,
      in: directory.descriptor
    )
    try requireDirectoryIdentity(
      directory.identity,
      descriptor: directory.descriptor,
      url: ledgerURL.deletingLastPathComponent()
    )
    try requireNamedIdentity(
      lockIdentity,
      name: lockName,
      in: directory.descriptor
    )
    let verification = try verifyData(data, expectedCorpusID: nil)
    let store = Self(
      ledgerURL: ledgerURL,
      corpusID: verification.checkpoint.corpusID,
      directoryDescriptor: directory.descriptor,
      directoryIdentity: directory.identity,
      lockIdentity: lockIdentity
    )
    directoryTransferred = true
    _ = try store.verify(expectedCorpusID: verification.checkpoint.corpusID)
    return store
  }

  public func checkpoint() throws -> LocalWritingExposureLedgerCheckpoint {
    try verify(expectedCorpusID: corpusID).checkpoint
  }

  public func verify(
    expectedCorpusID: UUID
  ) throws -> LocalWritingExposureLedgerVerification {
    try withExclusiveLock { ledgerIdentity in
      let bytes = try Self.readAuthorityFile(
        name: ledgerName,
        expectedIdentity: ledgerIdentity,
        in: directoryDescriptor
      )
      return try Self.verifyData(bytes, expectedCorpusID: expectedCorpusID)
    }
  }

  public static func verifyExtension(
    canonicalData: Data
  ) throws -> LocalWritingExposureLedgerExtension {
    try verifyExtensionData(canonicalData)
  }

  public static func verifyCheckpoint(
    canonicalData: Data
  ) throws -> LocalWritingExposureLedgerCheckpoint {
    guard !canonicalData.isEmpty, canonicalData.count <= maximumLineBytes else {
      throw LocalWritingExposureLedgerError.corruption
    }
    let wire: CheckpointWire = try decodeCanonical(
      CheckpointWire.self,
      from: canonicalData
    )
    return try wire.checkpoint()
  }

  public func exportExtension(
    after parentCheckpoint: LocalWritingExposureLedgerCheckpoint
  ) throws -> LocalWritingExposureLedgerExtension {
    try withExclusiveLock { ledgerIdentity in
      let bytes = try Self.readAuthorityFile(
        name: ledgerName,
        expectedIdentity: ledgerIdentity,
        in: directoryDescriptor
      )
      let verification = try Self.verifyData(bytes, expectedCorpusID: corpusID)
      guard parentCheckpoint.corpusID == corpusID,
        parentCheckpoint.eventCount < verification.checkpoint.eventCount,
        verification.checkpoint(at: parentCheckpoint.eventCount) == parentCheckpoint
      else { throw LocalWritingExposureLedgerError.invalidOrder }
      return try Self.makeExtension(
        parent: parentCheckpoint,
        child: verification.checkpoint,
        events: Array(verification.events.dropFirst(Int(parentCheckpoint.eventCount)))
      )
    }
  }

  public func fastForward(
    _ ledgerExtension: LocalWritingExposureLedgerExtension
  ) throws -> LocalWritingExposureLedgerCheckpoint {
    try withExclusiveLock { ledgerIdentity in
      let verifiedExtension = try Self.verifyExtensionData(
        ledgerExtension.canonicalData
      )
      guard verifiedExtension == ledgerExtension,
        verifiedExtension.corpusID == corpusID
      else { throw LocalWritingExposureLedgerError.identityMismatch }
      let currentBytes = try Self.readAuthorityFile(
        name: ledgerName,
        expectedIdentity: ledgerIdentity,
        in: directoryDescriptor
      )
      let current = try Self.verifyData(currentBytes, expectedCorpusID: corpusID)
      guard current.checkpoint == verifiedExtension.parentCheckpoint else {
        throw LocalWritingExposureLedgerError.conflict
      }
      let wire: ExtensionWire = try Self.decodeCanonical(
        ExtensionWire.self,
        from: verifiedExtension.canonicalData
      )
      var stagedBytes = currentBytes
      for encoded in wire.events {
        guard let event = Data(base64Encoded: encoded) else {
          throw LocalWritingExposureLedgerError.corruption
        }
        stagedBytes.append(event)
        stagedBytes.append(0x0A)
      }
      guard stagedBytes.count <= Self.maximumLedgerBytes else {
        throw LocalWritingExposureLedgerError.corruption
      }
      let resulting = try Self.verifyData(stagedBytes, expectedCorpusID: corpusID)
      guard resulting.checkpoint == verifiedExtension.childCheckpoint else {
        throw LocalWritingExposureLedgerError.invalidOrder
      }
      return try commit(
        stagedBytes,
        verifiedCheckpoint: resulting.checkpoint,
        replacing: ledgerIdentity
      )
    }
  }

  public func appendExposure(
    _ exposure: LocalWritingCandidateExposure,
    expectedHead: String
  ) throws -> LocalWritingExposureLedgerCheckpoint {
    try append(.candidateExposure(exposure), expectedHead: expectedHead)
  }

  public func appendInvalidation(
    _ invalidation: LocalWritingMaterialLineageInvalidation,
    expectedHead: String
  ) throws -> LocalWritingExposureLedgerCheckpoint {
    try append(.materialLineageInvalidation(invalidation), expectedHead: expectedHead)
  }

  func appendExposureThenAccess(
    _ exposure: LocalWritingCandidateExposure,
    expectedHead: String,
    candidateAccess: () throws -> Void
  ) throws -> LocalWritingExposureLedgerCheckpoint {
    let checkpoint = try appendExposure(exposure, expectedHead: expectedHead)
    let reopened = try verify(expectedCorpusID: corpusID)
    guard reopened.checkpoint == checkpoint else {
      throw LocalWritingExposureLedgerError.conflict
    }
    try candidateAccess()
    return checkpoint
  }

  func appendInvalidationThenMutation(
    _ invalidation: LocalWritingMaterialLineageInvalidation,
    expectedHead: String,
    mutation: () throws -> Void
  ) throws -> LocalWritingExposureLedgerCheckpoint {
    let checkpoint = try appendInvalidation(invalidation, expectedHead: expectedHead)
    let reopened = try verify(expectedCorpusID: corpusID)
    guard reopened.checkpoint == checkpoint else {
      throw LocalWritingExposureLedgerError.conflict
    }
    try mutation()
    return checkpoint
  }

  private func append(
    _ payload: LocalWritingExposureEventPayload,
    expectedHead: String
  ) throws -> LocalWritingExposureLedgerCheckpoint {
    try withExclusiveLock { ledgerIdentity in
      let currentBytes = try Self.readAuthorityFile(
        name: ledgerName,
        expectedIdentity: ledgerIdentity,
        in: directoryDescriptor
      )
      let current = try Self.verifyData(currentBytes, expectedCorpusID: corpusID)
      guard current.checkpoint.currentHeadSHA256 == expectedHead else {
        throw LocalWritingExposureLedgerError.conflict
      }
      try validate(payload, against: current)

      let (sequence, overflow) = current.checkpoint.eventCount.addingReportingOverflow(1)
      guard !overflow else { throw LocalWritingExposureLedgerError.invalidOrder }
      let eventData = try Self.canonicalEventData(
        payload: payload,
        sequence: sequence,
        previousEventSHA256: expectedHead
      )
      var stagedBytes = currentBytes
      stagedBytes.append(eventData)
      stagedBytes.append(0x0A)
      guard stagedBytes.count <= Self.maximumLedgerBytes else {
        throw LocalWritingExposureLedgerError.corruption
      }

      let verified = try Self.verifyData(stagedBytes, expectedCorpusID: corpusID)
      return try commit(
        stagedBytes,
        verifiedCheckpoint: verified.checkpoint,
        replacing: ledgerIdentity
      )
    }
  }

  private func commit(
    _ stagedBytes: Data,
    verifiedCheckpoint: LocalWritingExposureLedgerCheckpoint,
    replacing ledgerIdentity: AuthorityIdentity
  ) throws -> LocalWritingExposureLedgerCheckpoint {
    let stageName = ".\(ledgerName).stage-\(UUID().uuidString)"
    let writeDescriptor = Darwin.openat(
      directoryDescriptor,
      stageName,
      O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
      mode_t(0o600)
    )
    guard writeDescriptor >= 0 else { throw Self.mappedSystemError() }
    var writeDescriptorOpen = true
    var readDescriptor: Int32 = -1
    var readDescriptorOpen = false
    var stageExists = true
    var pinnedStageIdentity: AuthorityIdentity?
    defer {
      if readDescriptorOpen { Darwin.close(readDescriptor) }
      if writeDescriptorOpen { Darwin.close(writeDescriptor) }
      if stageExists,
        let pinnedStageIdentity,
        let pathIdentity = try? Self.authorityIdentity(
          name: stageName,
          in: directoryDescriptor
        ),
        pathIdentity == pinnedStageIdentity
      {
        Darwin.unlinkat(directoryDescriptor, stageName, 0)
      }
    }
    guard fchmod(writeDescriptor, 0o600) == 0 else {
      throw LocalWritingExposureLedgerError.ioFailure
    }
    let stageIdentity = try Self.validateAuthorityDescriptor(writeDescriptor)
    pinnedStageIdentity = stageIdentity
    try Self.requireNamedIdentity(
      stageIdentity,
      name: stageName,
      in: directoryDescriptor
    )
    try Self.writeAll(stagedBytes, to: writeDescriptor)
    guard fsync(writeDescriptor) == 0 else {
      throw LocalWritingExposureLedgerError.ioFailure
    }
    try Self.requireNamedIdentity(
      stageIdentity,
      name: stageName,
      in: directoryDescriptor
    )
    try faultHook?(.afterStageSync)
    try validateHeldAuthority(ledgerIdentity: ledgerIdentity)
    try Self.requireNamedIdentity(
      stageIdentity,
      name: stageName,
      in: directoryDescriptor
    )
    let writeCloseResult = Darwin.close(writeDescriptor)
    writeDescriptorOpen = false
    guard writeCloseResult == 0 else {
      throw LocalWritingExposureLedgerError.ioFailure
    }
    try faultHook?(.afterStageWriteCloseBeforeReadOpen)
    try validateHeldAuthority(ledgerIdentity: ledgerIdentity)

    readDescriptor = try Self.openAuthorityDescriptor(
      name: stageName,
      expectedIdentity: stageIdentity,
      flags: O_RDONLY,
      in: directoryDescriptor
    )
    readDescriptorOpen = true
    let reread = try Self.readAuthorityDescriptor(readDescriptor)
    guard reread == stagedBytes else {
      throw LocalWritingExposureLedgerError.corruption
    }
    let verified = try Self.verifyData(reread, expectedCorpusID: corpusID)
    guard verified.checkpoint == verifiedCheckpoint else {
      throw LocalWritingExposureLedgerError.corruption
    }
    try Self.requireNamedIdentity(
      stageIdentity,
      name: stageName,
      in: directoryDescriptor
    )
    let readCloseResult = Darwin.close(readDescriptor)
    readDescriptorOpen = false
    guard readCloseResult == 0 else {
      throw LocalWritingExposureLedgerError.ioFailure
    }
    try faultHook?(.beforeRename)
    try validateHeldAuthority(ledgerIdentity: ledgerIdentity)
    try Self.requireNamedIdentity(
      stageIdentity,
      name: stageName,
      in: directoryDescriptor
    )
    guard Darwin.renameat(
      directoryDescriptor,
      stageName,
      directoryDescriptor,
      ledgerName
    ) == 0 else { throw Self.mappedSystemError() }
    stageExists = false
    try Self.requireNamedIdentity(
      stageIdentity,
      name: ledgerName,
      in: directoryDescriptor
    )
    try faultHook?(.afterRenameBeforeDirectorySync)
    try validateRootAndLock()
    try Self.requireNamedIdentity(
      stageIdentity,
      name: ledgerName,
      in: directoryDescriptor
    )
    try Self.syncDirectory(directoryDescriptor)
    directorySyncObserver?()
    return verifiedCheckpoint
  }

  private func validate(
    _ payload: LocalWritingExposureEventPayload,
    against verification: LocalWritingExposureLedgerVerification
  ) throws {
    switch payload {
    case .candidateExposure(let exposure):
      guard exposure.corpusID == corpusID else {
        throw LocalWritingExposureLedgerError.identityMismatch
      }
      let duplicate = verification.events.contains { event in
        guard case .candidateExposure(let existing) = event.payload else {
          return false
        }
        return existing.caseID == exposure.caseID
          && existing.materialLineageID == exposure.materialLineageID
          && existing.candidateIdentitySHA256 == exposure.candidateIdentitySHA256
          && existing.configurationIdentitySHA256 == exposure.configurationIdentitySHA256
          && existing.roleProfileIdentitySHA256 == exposure.roleProfileIdentitySHA256
          && existing.executionIdentitySHA256 == exposure.executionIdentitySHA256
          && existing.executionStratum == exposure.executionStratum
      }
      guard !duplicate else { throw LocalWritingExposureLedgerError.conflict }

    case .materialLineageInvalidation(let invalidation):
      guard invalidation.corpusID == corpusID else {
        throw LocalWritingExposureLedgerError.identityMismatch
      }
      var matchingExposure = false
      var duplicate = false
      for event in verification.events {
        switch event.payload {
        case .candidateExposure(let exposure):
          if exposure.materialLineageID == invalidation.materialLineageID {
            guard exposure.caseID == invalidation.caseID else {
              throw LocalWritingExposureLedgerError.invalidOrder
            }
            matchingExposure = true
          }
        case .materialLineageInvalidation(let existing):
          if existing.materialLineageID == invalidation.materialLineageID,
            existing.reason == invalidation.reason
          {
            duplicate = true
          }
        }
      }
      guard matchingExposure else { throw LocalWritingExposureLedgerError.invalidOrder }
      guard !duplicate else { throw LocalWritingExposureLedgerError.conflict }
    }
  }

  private func withExclusiveLock<T>(
    _ body: (AuthorityIdentity) throws -> T
  ) throws -> T {
    try validateRootAndLock()
    let descriptor = try Self.openAuthorityDescriptor(
      name: lockName,
      expectedIdentity: lockIdentity,
      flags: O_RDWR,
      in: directoryDescriptor
    )
    defer { Darwin.close(descriptor) }
    while flock(descriptor, LOCK_EX) != 0 {
      guard errno == EINTR else { throw Self.mappedSystemError() }
    }
    defer { flock(descriptor, LOCK_UN) }
    try validateRootAndLock()
    let ledgerIdentity = try Self.authorityIdentity(
      name: ledgerName,
      in: directoryDescriptor
    )
    try faultHook?(.afterLockAcquired)
    try validateHeldAuthority(ledgerIdentity: ledgerIdentity)
    return try body(ledgerIdentity)
  }

  private func validateRootAndLock() throws {
    try Self.requireDirectoryIdentity(
      directoryIdentity,
      descriptor: directoryDescriptor,
      url: directoryURL
    )
    try Self.requireNamedIdentity(
      lockIdentity,
      name: lockName,
      in: directoryDescriptor
    )
  }

  private func validateHeldAuthority(ledgerIdentity: AuthorityIdentity) throws {
    try validateRootAndLock()
    try Self.requireNamedIdentity(
      ledgerIdentity,
      name: ledgerName,
      in: directoryDescriptor
    )
  }
}

extension LocalWritingExposureLedger {
  private static func canonicalHeader(corpusID: UUID) throws -> Data {
    let corpus = canonicalExposureUUID(corpusID)
    let genesis = sha256(try encode(GenesisWire(schemaVersion: 1, corpusID: corpus)))
    var data = try encode(HeaderWire(
      schemaVersion: 1,
      corpusID: corpus,
      genesisSHA256: genesis
    ))
    data.append(0x0A)
    return data
  }

  private static func canonicalEventData(
    payload: LocalWritingExposureEventPayload,
    sequence: UInt64,
    previousEventSHA256: String
  ) throws -> Data {
    guard isExposureDigest(previousEventSHA256), sequence > 0 else {
      throw LocalWritingExposureLedgerError.invalidOrder
    }
    switch payload {
    case .candidateExposure(let exposure):
      let digestWire = ExposureDigestWire(
        schemaVersion: 1,
        kind: LocalWritingExposureEventKind.candidateExposure.rawValue,
        sequence: sequence,
        previousEventSHA256: previousEventSHA256,
        corpusID: canonicalExposureUUID(exposure.corpusID),
        caseID: canonicalExposureUUID(exposure.caseID),
        materialLineageID: canonicalExposureUUID(exposure.materialLineageID),
        candidateIdentitySHA256: exposure.candidateIdentitySHA256,
        configurationIdentitySHA256: exposure.configurationIdentitySHA256,
        roleProfileIdentitySHA256: exposure.roleProfileIdentitySHA256,
        executionIdentitySHA256: exposure.executionIdentitySHA256,
        executionStratum: exposure.executionStratum.rawValue
      )
      let digest = sha256(try encode(digestWire))
      return try encode(ExposureEventWire(digest: digestWire, eventSHA256: digest))

    case .materialLineageInvalidation(let invalidation):
      let digestWire = InvalidationDigestWire(
        schemaVersion: 1,
        kind: LocalWritingExposureEventKind.materialLineageInvalidation.rawValue,
        sequence: sequence,
        previousEventSHA256: previousEventSHA256,
        corpusID: canonicalExposureUUID(invalidation.corpusID),
        caseID: canonicalExposureUUID(invalidation.caseID),
        materialLineageID: canonicalExposureUUID(invalidation.materialLineageID),
        reason: invalidation.reason.rawValue
      )
      let digest = sha256(try encode(digestWire))
      return try encode(InvalidationEventWire(digest: digestWire, eventSHA256: digest))
    }
  }

  private static func makeExtension(
    parent: LocalWritingExposureLedgerCheckpoint,
    child: LocalWritingExposureLedgerCheckpoint,
    events: [LocalWritingExposureEventEnvelope]
  ) throws -> LocalWritingExposureLedgerExtension {
    let encodedEvents = try events.map { event in
      try canonicalEventData(
        payload: event.payload,
        sequence: event.sequence,
        previousEventSHA256: event.previousEventSHA256
      ).base64EncodedString()
    }
    let data = try encode(ExtensionWire(
      schemaVersion: 1,
      corpusID: canonicalExposureUUID(parent.corpusID),
      parentCheckpoint: CheckpointWire(parent),
      childCheckpoint: CheckpointWire(child),
      events: encodedEvents
    ))
    return try verifyExtensionData(data)
  }

  private static func verifyExtensionData(
    _ data: Data
  ) throws -> LocalWritingExposureLedgerExtension {
    guard !data.isEmpty, data.count <= maximumLedgerBytes * 2 else {
      throw LocalWritingExposureLedgerError.corruption
    }
    let wire: ExtensionWire = try decodeCanonical(ExtensionWire.self, from: data)
    guard wire.schemaVersion == 1,
      let corpusID = canonicalUUID(wire.corpusID)
    else { throw LocalWritingExposureLedgerError.corruption }
    let parent = try wire.parentCheckpoint.checkpoint(expectedCorpusID: corpusID)
    let child = try wire.childCheckpoint.checkpoint(expectedCorpusID: corpusID)
    guard parent.eventCount < child.eventCount,
      child.eventCount - parent.eventCount == UInt64(wire.events.count),
      !wire.events.isEmpty
    else { throw LocalWritingExposureLedgerError.invalidOrder }

    var previous = parent.currentHeadSHA256
    var sequence = parent.eventCount
    var exposures = Set<ExposureIdentity>()
    var invalidations = Set<InvalidationIdentity>()
    for encoded in wire.events {
      guard let eventData = Data(base64Encoded: encoded),
        eventData.base64EncodedString() == encoded,
        !eventData.isEmpty,
        eventData.count <= maximumLineBytes
      else { throw LocalWritingExposureLedgerError.corruption }
      let (event, eventCorpusID) = try decodeEvent(eventData)
      let (next, overflow) = sequence.addingReportingOverflow(1)
      guard !overflow,
        eventCorpusID == corpusID,
        event.sequence == next,
        event.previousEventSHA256 == previous
      else { throw LocalWritingExposureLedgerError.invalidOrder }
      switch event.payload {
      case .candidateExposure(let exposure):
        guard exposures.insert(ExposureIdentity(exposure)).inserted else {
          throw LocalWritingExposureLedgerError.invalidOrder
        }
      case .materialLineageInvalidation(let invalidation):
        guard invalidations.insert(InvalidationIdentity(invalidation)).inserted else {
          throw LocalWritingExposureLedgerError.invalidOrder
        }
      }
      sequence = next
      previous = event.eventSHA256
    }
    guard sequence == child.eventCount,
      previous == child.currentHeadSHA256
    else { throw LocalWritingExposureLedgerError.invalidOrder }
    return LocalWritingExposureLedgerExtension(
      corpusID: corpusID,
      parentCheckpoint: parent,
      childCheckpoint: child,
      canonicalData: data
    )
  }

  private static func verifyData(
    _ data: Data,
    expectedCorpusID: UUID?
  ) throws -> LocalWritingExposureLedgerVerification {
    guard data.count <= maximumLedgerBytes, !data.isEmpty else {
      throw LocalWritingExposureLedgerError.corruption
    }
    guard data.last == 0x0A else { throw LocalWritingExposureLedgerError.corruption }
    let split = data.split(separator: 0x0A, omittingEmptySubsequences: false)
    guard split.count >= 2, split.last?.isEmpty == true else {
      throw LocalWritingExposureLedgerError.corruption
    }
    let lines = split[..<(split.count - 1)].map { Data($0) }
    guard !lines.isEmpty,
      lines.allSatisfy({ !$0.isEmpty && $0.count <= maximumLineBytes })
    else { throw LocalWritingExposureLedgerError.corruption }

    let header: HeaderWire = try decodeCanonical(HeaderWire.self, from: lines[0])
    guard header.schemaVersion == 1,
      let corpusID = canonicalUUID(header.corpusID),
      isExposureDigest(header.genesisSHA256)
    else { throw LocalWritingExposureLedgerError.corruption }
    if let expectedCorpusID, corpusID != expectedCorpusID {
      throw LocalWritingExposureLedgerError.identityMismatch
    }
    let expectedGenesis = sha256(try encode(GenesisWire(
      schemaVersion: 1,
      corpusID: header.corpusID
    )))
    guard header.genesisSHA256 == expectedGenesis else {
      throw LocalWritingExposureLedgerError.corruption
    }

    var events: [LocalWritingExposureEventEnvelope] = []
    var previous = header.genesisSHA256
    var sequence: UInt64 = 0
    var exposures = Set<ExposureIdentity>()
    var invalidations = Set<InvalidationIdentity>()
    var lineageCases: [UUID: UUID] = [:]

    for line in lines.dropFirst() {
      let (event, eventCorpusID) = try decodeEvent(line)
      switch event.payload {
      case .candidateExposure(let exposure):
        let identity = ExposureIdentity(exposure)
        guard exposures.insert(identity).inserted else {
          throw LocalWritingExposureLedgerError.invalidOrder
        }
        if let existing = lineageCases[exposure.materialLineageID],
          existing != exposure.caseID
        {
          throw LocalWritingExposureLedgerError.invalidOrder
        }
        lineageCases[exposure.materialLineageID] = exposure.caseID

      case .materialLineageInvalidation(let invalidation):
        guard lineageCases[invalidation.materialLineageID] == invalidation.caseID else {
          throw LocalWritingExposureLedgerError.invalidOrder
        }
        guard invalidations.insert(InvalidationIdentity(invalidation)).inserted else {
          throw LocalWritingExposureLedgerError.invalidOrder
        }
      }

      let (next, overflow) = sequence.addingReportingOverflow(1)
      guard !overflow,
        event.schemaVersion == 1,
        event.sequence == next,
        event.previousEventSHA256 == previous,
        eventCorpusID == corpusID,
        isExposureDigest(event.eventSHA256)
      else { throw LocalWritingExposureLedgerError.invalidOrder }
      sequence = next
      previous = event.eventSHA256
      events.append(event)
    }

    return LocalWritingExposureLedgerVerification(
      checkpoint: LocalWritingExposureLedgerCheckpoint(
        corpusID: corpusID,
        eventCount: sequence,
        currentHeadSHA256: previous
      ),
      events: events,
      genesisSHA256: header.genesisSHA256
    )
  }

  private static func decodeEvent(
    _ data: Data
  ) throws -> (LocalWritingExposureEventEnvelope, UUID) {
    switch try eventKind(in: data) {
    case .candidateExposure:
      let wire: ExposureEventWire = try decodeCanonical(ExposureEventWire.self, from: data)
      let exposure = try wire.exposure()
      guard wire.eventSHA256 == sha256(try encode(wire.digest)) else {
        throw LocalWritingExposureLedgerError.corruption
      }
      return (
        LocalWritingExposureEventEnvelope(
          sequence: wire.sequence,
          previousEventSHA256: wire.previousEventSHA256,
          eventSHA256: wire.eventSHA256,
          payload: .candidateExposure(exposure)
        ),
        exposure.corpusID
      )

    case .materialLineageInvalidation:
      let wire: InvalidationEventWire = try decodeCanonical(
        InvalidationEventWire.self,
        from: data
      )
      let invalidation = try wire.invalidation()
      guard wire.eventSHA256 == sha256(try encode(wire.digest)) else {
        throw LocalWritingExposureLedgerError.corruption
      }
      return (
        LocalWritingExposureEventEnvelope(
          sequence: wire.sequence,
          previousEventSHA256: wire.previousEventSHA256,
          eventSHA256: wire.eventSHA256,
          payload: .materialLineageInvalidation(invalidation)
        ),
        invalidation.corpusID
      )
    }
  }

  private static func eventKind(in data: Data) throws -> LocalWritingExposureEventKind {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let rawKind = object["kind"] as? String,
      let kind = LocalWritingExposureEventKind(rawValue: rawKind)
    else { throw LocalWritingExposureLedgerError.corruption }
    return kind
  }

  private static func encode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    do {
      return try encoder.encode(value)
    } catch {
      throw LocalWritingExposureLedgerError.corruption
    }
  }

  private static func decodeCanonical<T: Codable>(
    _ type: T.Type,
    from data: Data
  ) throws -> T {
    guard String(data: data, encoding: .utf8) != nil else {
      throw LocalWritingExposureLedgerError.corruption
    }
    let value: T
    do {
      value = try JSONDecoder().decode(type, from: data)
    } catch {
      throw LocalWritingExposureLedgerError.corruption
    }
    guard try encode(value) == data else {
      throw LocalWritingExposureLedgerError.nonCanonicalData
    }
    return value
  }

  private static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

extension LocalWritingExposureLedger {
  private static func openDirectoryAuthority(
    for ledgerURL: URL
  ) throws -> (descriptor: Int32, identity: AuthorityIdentity) {
    guard ledgerURL.isFileURL,
      ledgerURL.path.hasPrefix("/"),
      ledgerURL.path == ledgerURL.standardizedFileURL.path,
      !ledgerURL.lastPathComponent.isEmpty,
      ledgerURL.lastPathComponent != ".",
      ledgerURL.lastPathComponent != "..",
      !ledgerURL.lastPathComponent.contains("/"),
      !ledgerURL.appendingPathExtension("lock").lastPathComponent.contains("/")
    else { throw LocalWritingExposureLedgerError.permissions }
    let directoryURL = ledgerURL.deletingLastPathComponent()
    let descriptor = Darwin.open(
      directoryURL.path,
      O_RDONLY | O_DIRECTORY | O_NOFOLLOW
    )
    guard descriptor >= 0 else { throw mappedSystemError() }
    var keepDescriptor = false
    defer {
      if !keepDescriptor { Darwin.close(descriptor) }
    }
    let identity = try validateDirectoryDescriptor(descriptor)
    try requireDirectoryIdentity(
      identity,
      descriptor: descriptor,
      url: directoryURL
    )
    keepDescriptor = true
    return (descriptor, identity)
  }

  private static func requireAbsent(name: String, in directoryDescriptor: Int32) throws {
    var status = stat()
    guard fstatat(
      directoryDescriptor,
      name,
      &status,
      AT_SYMLINK_NOFOLLOW
    ) != 0 else {
      throw LocalWritingExposureLedgerError.conflict
    }
    guard errno == ENOENT else { throw mappedSystemError() }
  }

  private static func authorityIdentity(
    name: String,
    in directoryDescriptor: Int32
  ) throws -> AuthorityIdentity {
    var status = stat()
    guard fstatat(
      directoryDescriptor,
      name,
      &status,
      AT_SYMLINK_NOFOLLOW
    ) == 0,
      status.st_mode & S_IFMT == S_IFREG,
      status.st_uid == geteuid(),
      status.st_mode & 0o7777 == 0o600
    else { throw LocalWritingExposureLedgerError.permissions }
    return AuthorityIdentity(status)
  }

  private static func validateAuthorityDescriptor(
    _ descriptor: Int32
  ) throws -> AuthorityIdentity {
    var status = stat()
    guard fstat(descriptor, &status) == 0,
      status.st_mode & S_IFMT == S_IFREG,
      status.st_uid == geteuid(),
      status.st_mode & 0o7777 == 0o600
    else { throw LocalWritingExposureLedgerError.permissions }
    return AuthorityIdentity(status)
  }

  private static func validateDirectoryDescriptor(
    _ descriptor: Int32
  ) throws -> AuthorityIdentity {
    var status = stat()
    guard fstat(descriptor, &status) == 0,
      status.st_mode & S_IFMT == S_IFDIR,
      status.st_uid == geteuid(),
      status.st_mode & 0o7777 == 0o700
    else { throw LocalWritingExposureLedgerError.permissions }
    return AuthorityIdentity(status)
  }

  private static func requireNamedIdentity(
    _ expectedIdentity: AuthorityIdentity,
    name: String,
    in directoryDescriptor: Int32
  ) throws {
    guard try authorityIdentity(name: name, in: directoryDescriptor) == expectedIdentity else {
      throw LocalWritingExposureLedgerError.permissions
    }
  }

  private static func requireDirectoryIdentity(
    _ expectedIdentity: AuthorityIdentity,
    descriptor: Int32,
    url: URL
  ) throws {
    guard try validateDirectoryDescriptor(descriptor) == expectedIdentity else {
      throw LocalWritingExposureLedgerError.permissions
    }
    var status = stat()
    guard lstat(url.path, &status) == 0,
      status.st_mode & S_IFMT == S_IFDIR,
      status.st_uid == geteuid(),
      status.st_mode & 0o7777 == 0o700,
      AuthorityIdentity(status) == expectedIdentity
    else { throw LocalWritingExposureLedgerError.permissions }
  }

  private static func openAuthorityDescriptor(
    name: String,
    expectedIdentity: AuthorityIdentity,
    flags: Int32,
    in directoryDescriptor: Int32
  ) throws -> Int32 {
    try requireNamedIdentity(
      expectedIdentity,
      name: name,
      in: directoryDescriptor
    )
    let descriptor = Darwin.openat(
      directoryDescriptor,
      name,
      flags | O_NOFOLLOW
    )
    guard descriptor >= 0 else { throw mappedSystemError() }
    var keepDescriptor = false
    defer {
      if !keepDescriptor { Darwin.close(descriptor) }
    }
    guard try validateAuthorityDescriptor(descriptor) == expectedIdentity else {
      throw LocalWritingExposureLedgerError.permissions
    }
    try requireNamedIdentity(
      expectedIdentity,
      name: name,
      in: directoryDescriptor
    )
    keepDescriptor = true
    return descriptor
  }

  private static func readAuthorityFile(
    name: String,
    expectedIdentity: AuthorityIdentity,
    in directoryDescriptor: Int32
  ) throws -> Data {
    let descriptor = try openAuthorityDescriptor(
      name: name,
      expectedIdentity: expectedIdentity,
      flags: O_RDONLY,
      in: directoryDescriptor
    )
    defer { Darwin.close(descriptor) }
    let result = try readAuthorityDescriptor(descriptor)
    try requireNamedIdentity(
      expectedIdentity,
      name: name,
      in: directoryDescriptor
    )
    return result
  }

  private static func readAuthorityDescriptor(_ descriptor: Int32) throws -> Data {
    guard lseek(descriptor, 0, SEEK_SET) == 0 else {
      throw LocalWritingExposureLedgerError.ioFailure
    }
    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 8_192)
    while true {
      let count = Darwin.read(descriptor, &buffer, buffer.count)
      if count == 0 { break }
      if count < 0 {
        if errno == EINTR { continue }
        throw mappedSystemError()
      }
      guard result.count <= maximumLedgerBytes - count else {
        throw LocalWritingExposureLedgerError.corruption
      }
      result.append(buffer, count: count)
    }
    return result
  }

  private static func writeAll(_ data: Data, to descriptor: Int32) throws {
    try data.withUnsafeBytes { rawBuffer in
      guard let base = rawBuffer.baseAddress else { return }
      var offset = 0
      while offset < rawBuffer.count {
        let count = Darwin.write(
          descriptor,
          base.advanced(by: offset),
          rawBuffer.count - offset
        )
        if count < 0 {
          if errno == EINTR { continue }
          throw mappedSystemError()
        }
        guard count > 0 else { throw LocalWritingExposureLedgerError.ioFailure }
        offset += count
      }
    }
  }

  private static func syncDirectory(_ descriptor: Int32) throws {
    _ = try validateDirectoryDescriptor(descriptor)
    guard fsync(descriptor) == 0 else {
      throw LocalWritingExposureLedgerError.ioFailure
    }
  }

  private static func mappedSystemError() -> LocalWritingExposureLedgerError {
    switch errno {
    case EACCES, EPERM, ELOOP, EISDIR, ENOTDIR, ENOENT:
      .permissions
    case EEXIST:
      .conflict
    default:
      .ioFailure
    }
  }
}

private struct AuthorityIdentity: Equatable {
  let device: UInt64
  let inode: UInt64

  init(_ status: stat) {
    device = UInt64(status.st_dev)
    inode = UInt64(status.st_ino)
  }
}

private struct CheckpointWire: Codable {
  let schemaVersion: Int
  let corpusID: String
  let eventCount: UInt64
  let currentHeadSHA256: String

  init(_ checkpoint: LocalWritingExposureLedgerCheckpoint) {
    schemaVersion = checkpoint.schemaVersion
    corpusID = canonicalExposureUUID(checkpoint.corpusID)
    eventCount = checkpoint.eventCount
    currentHeadSHA256 = checkpoint.currentHeadSHA256
  }

  func checkpoint(
    expectedCorpusID: UUID
  ) throws -> LocalWritingExposureLedgerCheckpoint {
    let checkpoint = try checkpoint()
    guard checkpoint.corpusID == expectedCorpusID else {
      throw LocalWritingExposureLedgerError.identityMismatch
    }
    return checkpoint
  }

  func checkpoint() throws -> LocalWritingExposureLedgerCheckpoint {
    guard schemaVersion == 1,
      let verifiedCorpusID = canonicalUUID(corpusID),
      isExposureDigest(currentHeadSHA256)
    else { throw LocalWritingExposureLedgerError.identityMismatch }
    return LocalWritingExposureLedgerCheckpoint(
      corpusID: verifiedCorpusID,
      eventCount: eventCount,
      currentHeadSHA256: currentHeadSHA256
    )
  }
}

private struct ExtensionWire: Codable {
  let schemaVersion: Int
  let corpusID: String
  let parentCheckpoint: CheckpointWire
  let childCheckpoint: CheckpointWire
  let events: [String]
}

private struct GenesisWire: Codable {
  let schemaVersion: Int
  let corpusID: String
}

private struct HeaderWire: Codable {
  let schemaVersion: Int
  let corpusID: String
  let genesisSHA256: String
}

private struct ExposureDigestWire: Codable {
  let schemaVersion: Int
  let kind: String
  let sequence: UInt64
  let previousEventSHA256: String
  let corpusID: String
  let caseID: String
  let materialLineageID: String
  let candidateIdentitySHA256: String
  let configurationIdentitySHA256: String
  let roleProfileIdentitySHA256: String
  let executionIdentitySHA256: String
  let executionStratum: String
}

private struct ExposureEventWire: Codable {
  let schemaVersion: Int
  let kind: String
  let sequence: UInt64
  let previousEventSHA256: String
  let corpusID: String
  let caseID: String
  let materialLineageID: String
  let candidateIdentitySHA256: String
  let configurationIdentitySHA256: String
  let roleProfileIdentitySHA256: String
  let executionIdentitySHA256: String
  let executionStratum: String
  let eventSHA256: String

  init(digest: ExposureDigestWire, eventSHA256: String) {
    schemaVersion = digest.schemaVersion
    kind = digest.kind
    sequence = digest.sequence
    previousEventSHA256 = digest.previousEventSHA256
    corpusID = digest.corpusID
    caseID = digest.caseID
    materialLineageID = digest.materialLineageID
    candidateIdentitySHA256 = digest.candidateIdentitySHA256
    configurationIdentitySHA256 = digest.configurationIdentitySHA256
    roleProfileIdentitySHA256 = digest.roleProfileIdentitySHA256
    executionIdentitySHA256 = digest.executionIdentitySHA256
    executionStratum = digest.executionStratum
    self.eventSHA256 = eventSHA256
  }

  var digest: ExposureDigestWire {
    ExposureDigestWire(
      schemaVersion: schemaVersion,
      kind: kind,
      sequence: sequence,
      previousEventSHA256: previousEventSHA256,
      corpusID: corpusID,
      caseID: caseID,
      materialLineageID: materialLineageID,
      candidateIdentitySHA256: candidateIdentitySHA256,
      configurationIdentitySHA256: configurationIdentitySHA256,
      roleProfileIdentitySHA256: roleProfileIdentitySHA256,
      executionIdentitySHA256: executionIdentitySHA256,
      executionStratum: executionStratum
    )
  }

  func exposure() throws -> LocalWritingCandidateExposure {
    guard schemaVersion == 1,
      kind == LocalWritingExposureEventKind.candidateExposure.rawValue,
      let corpusID = canonicalUUID(corpusID),
      let caseID = canonicalUUID(caseID),
      let materialLineageID = canonicalUUID(materialLineageID),
      let stratum = LocalWritingExposureExecutionStratum(rawValue: executionStratum),
      isExposureDigest(previousEventSHA256),
      isExposureDigest(eventSHA256)
    else { throw LocalWritingExposureLedgerError.corruption }
    return try LocalWritingCandidateExposure(
      corpusID: corpusID,
      caseID: caseID,
      materialLineageID: materialLineageID,
      candidateIdentitySHA256: candidateIdentitySHA256,
      configurationIdentitySHA256: configurationIdentitySHA256,
      roleProfileIdentitySHA256: roleProfileIdentitySHA256,
      executionIdentitySHA256: executionIdentitySHA256,
      executionStratum: stratum
    )
  }
}

private struct InvalidationDigestWire: Codable {
  let schemaVersion: Int
  let kind: String
  let sequence: UInt64
  let previousEventSHA256: String
  let corpusID: String
  let caseID: String
  let materialLineageID: String
  let reason: String
}

private struct InvalidationEventWire: Codable {
  let schemaVersion: Int
  let kind: String
  let sequence: UInt64
  let previousEventSHA256: String
  let corpusID: String
  let caseID: String
  let materialLineageID: String
  let reason: String
  let eventSHA256: String

  init(digest: InvalidationDigestWire, eventSHA256: String) {
    schemaVersion = digest.schemaVersion
    kind = digest.kind
    sequence = digest.sequence
    previousEventSHA256 = digest.previousEventSHA256
    corpusID = digest.corpusID
    caseID = digest.caseID
    materialLineageID = digest.materialLineageID
    reason = digest.reason
    self.eventSHA256 = eventSHA256
  }

  var digest: InvalidationDigestWire {
    InvalidationDigestWire(
      schemaVersion: schemaVersion,
      kind: kind,
      sequence: sequence,
      previousEventSHA256: previousEventSHA256,
      corpusID: corpusID,
      caseID: caseID,
      materialLineageID: materialLineageID,
      reason: reason
    )
  }

  func invalidation() throws -> LocalWritingMaterialLineageInvalidation {
    guard schemaVersion == 1,
      kind == LocalWritingExposureEventKind.materialLineageInvalidation.rawValue,
      let corpusID = canonicalUUID(corpusID),
      let caseID = canonicalUUID(caseID),
      let materialLineageID = canonicalUUID(materialLineageID),
      let reason = LocalWritingMaterialLineageInvalidationReason(rawValue: reason),
      isExposureDigest(previousEventSHA256),
      isExposureDigest(eventSHA256)
    else { throw LocalWritingExposureLedgerError.corruption }
    return try LocalWritingMaterialLineageInvalidation(
      corpusID: corpusID,
      caseID: caseID,
      materialLineageID: materialLineageID,
      reason: reason
    )
  }
}

private struct ExposureIdentity: Hashable {
  let caseID: UUID
  let materialLineageID: UUID
  let candidateIdentitySHA256: String
  let configurationIdentitySHA256: String
  let roleProfileIdentitySHA256: String
  let executionIdentitySHA256: String
  let executionStratum: String

  init(_ exposure: LocalWritingCandidateExposure) {
    caseID = exposure.caseID
    materialLineageID = exposure.materialLineageID
    candidateIdentitySHA256 = exposure.candidateIdentitySHA256
    configurationIdentitySHA256 = exposure.configurationIdentitySHA256
    roleProfileIdentitySHA256 = exposure.roleProfileIdentitySHA256
    executionIdentitySHA256 = exposure.executionIdentitySHA256
    executionStratum = exposure.executionStratum.rawValue
  }
}

private struct InvalidationIdentity: Hashable {
  let materialLineageID: UUID
  let reason: String

  init(_ invalidation: LocalWritingMaterialLineageInvalidation) {
    materialLineageID = invalidation.materialLineageID
    reason = invalidation.reason.rawValue
  }
}

private func canonicalExposureUUID(_ value: UUID) -> String {
  value.uuidString.lowercased()
}

private func canonicalUUID(_ value: String) -> UUID? {
  guard value == value.lowercased(),
    let uuid = UUID(uuidString: value),
    canonicalExposureUUID(uuid) == value
  else { return nil }
  return uuid
}

private func isExposureDigest(_ value: String) -> Bool {
  value.count == 64
    && value != String(repeating: "0", count: 64)
    && value.utf8.allSatisfy {
      ($0 >= Character("0").asciiValue! && $0 <= Character("9").asciiValue!)
        || ($0 >= Character("a").asciiValue! && $0 <= Character("f").asciiValue!)
    }
}
