import CryptoKit
import Darwin
import FleckCore
import Foundation

enum LocalWritingCorpusStoreError: String, Error, Equatable, Sendable,
  CustomStringConvertible
{
  case invalidLocation
  case alreadyExists
  case missingAuthority
  case permissions
  case nonCanonicalData
  case identityMismatch
  case rollbackOrFork
  case ioFailure

  var description: String { rawValue }
}

struct LocalWritingCorpusWorkspace: Equatable, Sendable {
  let corpusID: UUID
  let workspaceURL: URL
  let manifest: LocalWritingCorpusManifestEnvelope
  let checkpoint: LocalWritingExposureLedgerCheckpoint
}

enum LocalWritingCorpusStoreFaultPoint: Equatable, Sendable {
  case afterConsentSyncBeforeReadback
  case afterConsentPublish
  case afterManifestPublish
  case afterLedgerCreate
  case afterCheckpointStageSync
  case afterCheckpointStageCloseBeforeReadback
  case beforeCheckpointRename
  case afterCheckpointRenameBeforeDirectorySync
  case afterAuthorityRead
  case afterInitialSelectedLeafSnapshot
  case afterFinalSelectedLeafSnapshot
  case beforeCorpusRename
  case afterCorpusRenameBeforeManagedSync
  case afterOpenManagedParentSync
  case beforeCorpusDirectorySync
  case beforeLiveLedgerVerification
  case beforeFinalAuthorityRecheck
}

actor LocalWritingCorpusStore {
  typealias Clock = @Sendable () -> Int64
  typealias ForbiddenRootsProvider = @Sendable () -> [URL]
  typealias FaultHook = @Sendable (LocalWritingCorpusStoreFaultPoint) throws -> Void

  private static let managedContainerName = "Fleck Local Writing Corpus"
  private static let consentName = "consent.json"
  private static let manifestName = "manifest.json"
  private static let checkpointName = "checkpoint.json"
  private static let exposureName = "exposure"
  private static let ledgerName = "ledger.jsonl"
  private static let maximumConsentBytes = 4 * 1_024
  private static let maximumManifestBytes = 64 * 1_024
  private static let maximumCheckpointBytes = 2 * 1_024
  private static let maximumLedgerBytes = 4 * 1_024 * 1_024

  private let fileManager: FileManager
  private let clock: Clock
  private let additionalForbiddenRoots: ForbiddenRootsProvider
  private let faultHook: FaultHook?

  init(
    fileManager: FileManager = .default,
    clock: @escaping Clock = {
      Int64(Date().timeIntervalSince1970 * 1_000)
    },
    additionalForbiddenRoots: @escaping ForbiddenRootsProvider = { [] },
    faultHook: FaultHook? = nil
  ) {
    self.fileManager = fileManager
    self.clock = clock
    self.additionalForbiddenRoots = additionalForbiddenRoots
    self.faultHook = faultHook
  }

  func create(
    in selectedContainerURL: URL,
    corpusID: UUID = UUID()
  ) throws -> LocalWritingCorpusWorkspace {
    try validateSelectedContainer(selectedContainerURL)
    let timestamp = clock()
    guard timestamp >= 0 else { throw LocalWritingCorpusStoreError.nonCanonicalData }

    let selectedPath = try Self.openSelectedPath(
      selectedContainerURL,
      afterLeafSnapshot: { try self.faultHook?(.afterInitialSelectedLeafSnapshot) }
    )
    let selected = selectedPath.selected
    defer { Darwin.close(selected.descriptor) }
    let managed = try Self.createOrOpenDirectory(
      named: Self.managedContainerName,
      in: selected.descriptor
    )
    defer { Darwin.close(managed.descriptor) }

    let corpusName = corpusID.uuidString.lowercased()
    guard Self.isAbsent(named: corpusName, in: managed.descriptor) else {
      throw LocalWritingCorpusStoreError.alreadyExists
    }
    let stageName = ".corpus-stage-\(UUID().uuidString.lowercased())"
    let corpus = try Self.createDirectory(
      named: stageName,
      in: managed.descriptor,
      beforeParentSync: { try self.faultHook?(.beforeCorpusDirectorySync) }
    )
    var exposure: DirectoryAuthority?
    var createdFiles: [String: AuthorityIdentity] = [:]
    defer {
      if let exposure { Darwin.close(exposure.descriptor) }
      Darwin.close(corpus.descriptor)
    }

    let consent = ConsentReceipt(corpusID: corpusID, createdAt: timestamp)
    let consentData = consent.canonicalData
    let consentDigest = Self.sha256(consentData)
    let payload = try LocalWritingCorpusPayload(
      language: "en-US",
      claimScope: .ownerPrivateBeta,
      consentReceiptSHA256: consentDigest,
      createdAtUnixMilliseconds: timestamp,
      controlledWorkspaces: [],
      cases: []
    )
    let manifest = try LocalWritingCorpusCodec.makeManifest(
      corpusID: corpusID,
      payload: payload
    )
    let manifestData = try LocalWritingCorpusCodec.canonicalData(for: manifest)

    createdFiles[Self.consentName] = try Self.publishExclusive(
      consentData,
      named: Self.consentName,
      in: corpus.descriptor,
      beforeReadback: { try self.faultHook?(.afterConsentSyncBeforeReadback) }
    )
    try faultHook?(.afterConsentPublish)
    createdFiles[Self.manifestName] = try Self.publishExclusive(
      manifestData,
      named: Self.manifestName,
      in: corpus.descriptor
    )
    try faultHook?(.afterManifestPublish)

    let createdExposure = try Self.createDirectory(
      named: Self.exposureName,
      in: corpus.descriptor
    )
    exposure = createdExposure
    let workspaceURL = selectedContainerURL
      .appendingPathComponent(Self.managedContainerName, isDirectory: true)
      .appendingPathComponent(corpusName, isDirectory: true)
    let ledgerURL = workspaceURL
      .appendingPathComponent(Self.exposureName, isDirectory: true)
      .appendingPathComponent(Self.ledgerName)
    let ledger: LocalWritingExposureLedger
    do {
      ledger = try LocalWritingExposureLedger.create(
        at: ledgerURL,
        pinnedDirectoryDescriptor: createdExposure.descriptor,
        corpusID: corpusID
      )
    } catch {
      throw Self.mapLedgerError(error)
    }
    createdFiles["\(Self.exposureName)/\(Self.ledgerName)"] = try Self.fileIdentity(
      named: Self.ledgerName,
      in: createdExposure.descriptor
    )
    createdFiles["\(Self.exposureName)/\(Self.ledgerName).lock"] = try Self.fileIdentity(
      named: "\(Self.ledgerName).lock",
      in: createdExposure.descriptor
    )
    try faultHook?(.afterLedgerCreate)
    let checkpoint: LocalWritingExposureLedgerCheckpoint
    do {
      checkpoint = try ledger.checkpoint()
    } catch {
      throw Self.mapLedgerError(error)
    }
    let ledgerBytes = try Self.readAuthorityFile(
      named: Self.ledgerName,
      maximumBytes: Self.maximumLedgerBytes,
      in: createdExposure.descriptor
    )
    let lockBytes = try Self.readAuthorityFile(
      named: "\(Self.ledgerName).lock",
      maximumBytes: 0,
      in: createdExposure.descriptor
    )
    createdFiles[Self.checkpointName] = try publishCheckpoint(
      checkpoint,
      replacing: nil,
      in: corpus
    )
    try Self.requireDirectoryIdentity(corpus)
    try Self.requireDirectoryIdentity(createdExposure)
    try Self.syncDirectory(managed.descriptor)
    try Self.syncDirectory(selected.descriptor, exactMode: nil)
    try Self.requireSelectedPathAuthority(
      selectedPath,
      at: selectedContainerURL
    )
    try Self.requireDirectoryIdentity(managed)
    try Self.requireDirectoryIdentity(corpus)
    try Self.requireDirectoryIdentity(createdExposure)
    try Self.requireAuthorityFile(
      named: Self.consentName,
      maximumBytes: Self.maximumConsentBytes,
      expectedIdentity: createdFiles[Self.consentName],
      expectedData: consentData,
      in: corpus.descriptor
    )
    try Self.requireAuthorityFile(
      named: Self.manifestName,
      maximumBytes: Self.maximumManifestBytes,
      expectedIdentity: createdFiles[Self.manifestName],
      expectedData: manifestData,
      in: corpus.descriptor
    )
    try Self.requireAuthorityFile(
      named: Self.ledgerName,
      maximumBytes: Self.maximumLedgerBytes,
      expectedIdentity: createdFiles["\(Self.exposureName)/\(Self.ledgerName)"],
      expectedData: ledgerBytes.data,
      in: createdExposure.descriptor
    )
    try Self.requireAuthorityFile(
      named: "\(Self.ledgerName).lock",
      maximumBytes: 0,
      expectedIdentity: createdFiles["\(Self.exposureName)/\(Self.ledgerName).lock"],
      expectedData: lockBytes.data,
      in: createdExposure.descriptor
    )
    try Self.requireAuthorityFile(
      named: Self.checkpointName,
      maximumBytes: Self.maximumCheckpointBytes,
      expectedIdentity: createdFiles[Self.checkpointName],
      expectedData: checkpoint.canonicalData,
      in: corpus.descriptor
    )
    try faultHook?(.beforeCorpusRename)
    try Self.requireDirectoryIdentity(corpus)
    guard Self.isAbsent(named: corpusName, in: managed.descriptor) else {
      throw LocalWritingCorpusStoreError.alreadyExists
    }
    guard renameatx_np(
      managed.descriptor,
      stageName,
      managed.descriptor,
      corpusName,
      UInt32(RENAME_EXCL)
    ) == 0 else { throw Self.mapSystemError() }
    let finalCorpus = DirectoryAuthority(
      descriptor: corpus.descriptor,
      identity: corpus.identity,
      name: corpusName,
      parentDescriptor: managed.descriptor
    )
    try Self.requireDirectoryIdentity(finalCorpus)
    do {
      try faultHook?(.afterCorpusRenameBeforeManagedSync)
      try Self.syncDirectory(managed.descriptor)
    } catch {
      throw LocalWritingCorpusStoreError.ioFailure
    }

    let reboundCorpus = try Self.openDirectory(named: corpusName, in: managed.descriptor)
    defer { Darwin.close(reboundCorpus.descriptor) }
    guard reboundCorpus.identity == corpus.identity else {
      throw LocalWritingCorpusStoreError.identityMismatch
    }
    let reboundExposure = try Self.openDirectory(
      named: Self.exposureName,
      in: reboundCorpus.descriptor
    )
    defer { Darwin.close(reboundExposure.descriptor) }
    guard reboundExposure.identity == createdExposure.identity else {
      throw LocalWritingCorpusStoreError.identityMismatch
    }
    let reboundLedger: LocalWritingExposureLedger
    do {
      reboundLedger = try LocalWritingExposureLedger.open(
        at: ledgerURL,
        pinnedDirectoryDescriptor: reboundExposure.descriptor
      )
      guard try reboundLedger.verify(expectedCorpusID: corpusID).checkpoint == checkpoint else {
        throw LocalWritingCorpusStoreError.identityMismatch
      }
    } catch let error as LocalWritingCorpusStoreError {
      throw error
    } catch {
      throw Self.mapLedgerError(error)
    }
    try faultHook?(.beforeFinalAuthorityRecheck)
    try Self.requireSelectedPathAuthority(
      selectedPath,
      at: selectedContainerURL,
      afterLeafSnapshot: { try self.faultHook?(.afterFinalSelectedLeafSnapshot) }
    )
    try Self.requireDirectoryIdentity(managed)
    try Self.requireDirectoryIdentity(reboundCorpus)
    try Self.requireDirectoryIdentity(reboundExposure)
    try Self.requireAuthorityFile(
      named: Self.consentName,
      maximumBytes: Self.maximumConsentBytes,
      expectedIdentity: createdFiles[Self.consentName],
      expectedData: consentData,
      in: reboundCorpus.descriptor
    )
    try Self.requireAuthorityFile(
      named: Self.manifestName,
      maximumBytes: Self.maximumManifestBytes,
      expectedIdentity: createdFiles[Self.manifestName],
      expectedData: manifestData,
      in: reboundCorpus.descriptor
    )
    try Self.requireAuthorityFile(
      named: Self.ledgerName,
      maximumBytes: Self.maximumLedgerBytes,
      expectedIdentity: createdFiles["\(Self.exposureName)/\(Self.ledgerName)"],
      expectedData: ledgerBytes.data,
      in: reboundExposure.descriptor
    )
    try Self.requireAuthorityFile(
      named: "\(Self.ledgerName).lock",
      maximumBytes: 0,
      expectedIdentity: createdFiles["\(Self.exposureName)/\(Self.ledgerName).lock"],
      expectedData: lockBytes.data,
      in: reboundExposure.descriptor
    )
    try Self.requireAuthorityFile(
      named: Self.checkpointName,
      maximumBytes: Self.maximumCheckpointBytes,
      expectedIdentity: createdFiles[Self.checkpointName],
      expectedData: checkpoint.canonicalData,
      in: reboundCorpus.descriptor
    )
    return LocalWritingCorpusWorkspace(
      corpusID: corpusID,
      workspaceURL: workspaceURL,
      manifest: manifest,
      checkpoint: checkpoint
    )
  }

  func open(at workspaceURL: URL) throws -> LocalWritingCorpusWorkspace {
    let location = try validateWorkspaceLocation(workspaceURL)
    try validateSelectedContainer(location.selectedContainer)
    let selectedPath = try Self.openSelectedPath(
      location.selectedContainer,
      afterLeafSnapshot: { try self.faultHook?(.afterInitialSelectedLeafSnapshot) }
    )
    let selected = selectedPath.selected
    defer { Darwin.close(selected.descriptor) }
    let managed = try Self.openDirectory(
      named: Self.managedContainerName,
      in: selected.descriptor
    )
    defer { Darwin.close(managed.descriptor) }
    let corpus = try Self.openDirectory(named: location.corpusName, in: managed.descriptor)
    defer { Darwin.close(corpus.descriptor) }
    do {
      try Self.syncDirectory(managed.descriptor)
    } catch {
      throw LocalWritingCorpusStoreError.ioFailure
    }
    try faultHook?(.afterOpenManagedParentSync)
    let exposure = try Self.openDirectory(named: Self.exposureName, in: corpus.descriptor)
    defer { Darwin.close(exposure.descriptor) }

    let consentBytes = try Self.readAuthorityFile(
      named: Self.consentName,
      maximumBytes: Self.maximumConsentBytes,
      in: corpus.descriptor
    )
    let consent = try ConsentReceipt.decodeCanonical(consentBytes.data)
    let manifestBytes = try Self.readAuthorityFile(
      named: Self.manifestName,
      maximumBytes: Self.maximumManifestBytes,
      in: corpus.descriptor
    )
    let ledgerBytes = try Self.readAuthorityFile(
      named: Self.ledgerName,
      maximumBytes: Self.maximumLedgerBytes,
      in: exposure.descriptor
    )
    let lockBytes = try Self.readAuthorityFile(
      named: "\(Self.ledgerName).lock",
      maximumBytes: 0,
      in: exposure.descriptor
    )
    let cachedBytes = try Self.readAuthorityFileIfPresent(
      named: Self.checkpointName,
      maximumBytes: Self.maximumCheckpointBytes,
      in: corpus.descriptor
    )
    try faultHook?(.afterAuthorityRead)
    let checkpointUnchanged: Bool
    if let cachedBytes {
      checkpointUnchanged = (try? Self.fileIdentity(
        named: Self.checkpointName,
        in: corpus.descriptor
      )) == cachedBytes.identity
    } else {
      checkpointUnchanged = Self.isAbsent(
        named: Self.checkpointName,
        in: corpus.descriptor
      )
    }
    guard try Self.fileIdentity(named: Self.consentName, in: corpus.descriptor)
      == consentBytes.identity,
      try Self.fileIdentity(named: Self.manifestName, in: corpus.descriptor)
        == manifestBytes.identity,
      checkpointUnchanged
    else { throw LocalWritingCorpusStoreError.identityMismatch }
    try Self.requireAuthorityFile(
      named: Self.ledgerName,
      maximumBytes: Self.maximumLedgerBytes,
      expectedIdentity: ledgerBytes.identity,
      expectedData: ledgerBytes.data,
      in: exposure.descriptor
    )
    try Self.requireAuthorityFile(
      named: "\(Self.ledgerName).lock",
      maximumBytes: 0,
      expectedIdentity: lockBytes.identity,
      expectedData: lockBytes.data,
      in: exposure.descriptor
    )
    let manifest: LocalWritingCorpusManifestEnvelope
    do {
      manifest = try LocalWritingCorpusCodec.decodeCanonical(manifestBytes.data)
      guard try LocalWritingCorpusCodec.canonicalData(for: manifest) == manifestBytes.data else {
        throw LocalWritingCorpusStoreError.nonCanonicalData
      }
    } catch let error as LocalWritingCorpusStoreError {
      throw error
    } catch {
      throw LocalWritingCorpusStoreError.nonCanonicalData
    }
    guard consent.corpusID == location.corpusID,
      consent.consentID == location.corpusID,
      manifest.corpusID == location.corpusID,
      manifest.payload.createdAtUnixMilliseconds == consent.createdAt,
      manifest.payload.consentReceiptSHA256 == Self.sha256(consentBytes.data),
      manifest.payload.language == "en-US",
      manifest.payload.claimScope == .ownerPrivateBeta,
      manifest.payload.controlledWorkspaces.isEmpty,
      manifest.payload.cases.isEmpty
    else { throw LocalWritingCorpusStoreError.identityMismatch }

    let ledgerURL = workspaceURL
      .appendingPathComponent(Self.exposureName, isDirectory: true)
      .appendingPathComponent(Self.ledgerName)
    let ledger: LocalWritingExposureLedger
    let live: LocalWritingExposureLedgerCheckpoint
    do {
      try faultHook?(.beforeLiveLedgerVerification)
      ledger = try LocalWritingExposureLedger.open(
        at: ledgerURL,
        pinnedDirectoryDescriptor: exposure.descriptor
      )
      live = try ledger.verify(expectedCorpusID: location.corpusID).checkpoint
    } catch {
      throw Self.mapLedgerError(error)
    }

    let checkpointIdentity: AuthorityIdentity
    if let cachedBytes {
      let cached: LocalWritingExposureLedgerCheckpoint
      do {
        cached = try LocalWritingExposureLedger.verifyCheckpoint(
          canonicalData: cachedBytes.data
        )
      } catch {
        throw LocalWritingCorpusStoreError.nonCanonicalData
      }
      guard cached.corpusID == location.corpusID else {
        throw LocalWritingCorpusStoreError.identityMismatch
      }
      if cached.eventCount > live.eventCount {
        throw LocalWritingCorpusStoreError.rollbackOrFork
      }
      if cached.eventCount == live.eventCount {
        guard cached == live else { throw LocalWritingCorpusStoreError.rollbackOrFork }
        checkpointIdentity = cachedBytes.identity
      } else {
        do {
          let ledgerExtension = try ledger.exportExtension(after: cached)
          guard ledgerExtension.childCheckpoint == live else {
            throw LocalWritingCorpusStoreError.rollbackOrFork
          }
        } catch let error as LocalWritingCorpusStoreError {
          throw error
        } catch {
          throw LocalWritingCorpusStoreError.rollbackOrFork
        }
        checkpointIdentity = try publishCheckpoint(
          live,
          replacing: cachedBytes.identity,
          in: corpus
        )
      }
    } else {
      checkpointIdentity = try publishCheckpoint(live, replacing: nil, in: corpus)
    }
    try faultHook?(.beforeFinalAuthorityRecheck)
    try Self.requireSelectedPathAuthority(
      selectedPath,
      at: location.selectedContainer,
      afterLeafSnapshot: { try self.faultHook?(.afterFinalSelectedLeafSnapshot) }
    )
    try Self.requireDirectoryIdentity(managed)
    try Self.requireDirectoryIdentity(corpus)
    try Self.requireDirectoryIdentity(exposure)
    try Self.requireAuthorityFile(
      named: Self.consentName,
      maximumBytes: Self.maximumConsentBytes,
      expectedIdentity: consentBytes.identity,
      expectedData: consentBytes.data,
      in: corpus.descriptor
    )
    try Self.requireAuthorityFile(
      named: Self.manifestName,
      maximumBytes: Self.maximumManifestBytes,
      expectedIdentity: manifestBytes.identity,
      expectedData: manifestBytes.data,
      in: corpus.descriptor
    )
    try Self.requireAuthorityFile(
      named: Self.ledgerName,
      maximumBytes: Self.maximumLedgerBytes,
      expectedIdentity: ledgerBytes.identity,
      expectedData: ledgerBytes.data,
      in: exposure.descriptor
    )
    try Self.requireAuthorityFile(
      named: "\(Self.ledgerName).lock",
      maximumBytes: 0,
      expectedIdentity: lockBytes.identity,
      expectedData: lockBytes.data,
      in: exposure.descriptor
    )
    try Self.requireAuthorityFile(
      named: Self.checkpointName,
      maximumBytes: Self.maximumCheckpointBytes,
      expectedIdentity: checkpointIdentity,
      expectedData: live.canonicalData,
      in: corpus.descriptor
    )
    let finalLedgerCheckpoint: LocalWritingExposureLedgerCheckpoint
    do {
      finalLedgerCheckpoint = try LocalWritingExposureLedger.open(
        at: ledgerURL,
        pinnedDirectoryDescriptor: exposure.descriptor
      ).verify(expectedCorpusID: location.corpusID).checkpoint
    } catch {
      throw Self.mapLedgerError(error)
    }
    guard finalLedgerCheckpoint == live else {
      throw LocalWritingCorpusStoreError.rollbackOrFork
    }
    return LocalWritingCorpusWorkspace(
      corpusID: location.corpusID,
      workspaceURL: workspaceURL,
      manifest: manifest,
      checkpoint: live
    )
  }

  private func validateSelectedContainer(_ url: URL) throws {
    guard Self.isCanonicalAbsoluteFileURL(url) else {
      throw LocalWritingCorpusStoreError.invalidLocation
    }
    let path = url.path
    guard path != "/",
      path != fileManager.homeDirectoryForCurrentUser.standardizedFileURL.path
    else { throw LocalWritingCorpusStoreError.invalidLocation }
    let forbidden = additionalForbiddenRoots().map { $0.standardizedFileURL.path }
    guard !forbidden.contains(where: { Self.isEqualOrDescendant(path, of: $0) }) else {
      throw LocalWritingCorpusStoreError.invalidLocation
    }
    guard !url.pathComponents.contains(where: {
      $0.lowercased().hasSuffix(".app")
    }) else { throw LocalWritingCorpusStoreError.invalidLocation }
  }

  private func validateWorkspaceLocation(
    _ workspaceURL: URL
  ) throws -> (selectedContainer: URL, corpusName: String, corpusID: UUID) {
    guard Self.isCanonicalAbsoluteFileURL(workspaceURL) else {
      throw LocalWritingCorpusStoreError.invalidLocation
    }
    let corpusName = workspaceURL.lastPathComponent
    guard corpusName == corpusName.lowercased(),
      let corpusID = UUID(uuidString: corpusName),
      corpusID.uuidString.lowercased() == corpusName,
      workspaceURL.deletingLastPathComponent().lastPathComponent
        == Self.managedContainerName
    else { throw LocalWritingCorpusStoreError.invalidLocation }
    return (
      workspaceURL.deletingLastPathComponent().deletingLastPathComponent(),
      corpusName,
      corpusID
    )
  }

  private func publishCheckpoint(
    _ checkpoint: LocalWritingExposureLedgerCheckpoint,
    replacing oldIdentity: AuthorityIdentity?,
    in directory: DirectoryAuthority
  ) throws -> AuthorityIdentity {
    let stageName = ".checkpoint-\(UUID().uuidString.lowercased()).stage"
    var stageDescriptor = Darwin.openat(
      directory.descriptor,
      stageName,
      O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW,
      mode_t(0o600)
    )
    guard stageDescriptor >= 0 else { throw Self.mapSystemError() }
    var publicationComplete = false
    defer {
      if stageDescriptor >= 0 { Darwin.close(stageDescriptor) }
      if !publicationComplete { _ = fsync(directory.descriptor) }
    }
    guard fchmod(stageDescriptor, 0o600) == 0 else {
      throw LocalWritingCorpusStoreError.ioFailure
    }
    let validatedStageIdentity = try Self.validateFileDescriptor(stageDescriptor)
    try Self.writeAll(checkpoint.canonicalData, to: stageDescriptor)
    try Self.fullSync(stageDescriptor)
    try faultHook?(.afterCheckpointStageSync)
    guard Darwin.close(stageDescriptor) == 0 else {
      throw LocalWritingCorpusStoreError.ioFailure
    }
    stageDescriptor = -1
    try faultHook?(.afterCheckpointStageCloseBeforeReadback)
    let readback = try Self.readAuthorityFile(
      named: stageName,
      maximumBytes: Self.maximumCheckpointBytes,
      in: directory.descriptor
    )
    guard readback.identity == validatedStageIdentity,
      readback.data == checkpoint.canonicalData,
      (try? LocalWritingExposureLedger.verifyCheckpoint(
        canonicalData: readback.data
      )) == checkpoint
    else { throw LocalWritingCorpusStoreError.identityMismatch }
    try faultHook?(.beforeCheckpointRename)
    if let oldIdentity {
      guard try Self.fileIdentity(
        named: Self.checkpointName,
        in: directory.descriptor
      ) == oldIdentity else { throw LocalWritingCorpusStoreError.identityMismatch }
      guard renameatx_np(
        directory.descriptor,
        stageName,
        directory.descriptor,
        Self.checkpointName,
        UInt32(RENAME_SWAP)
      ) == 0 else { throw Self.mapSystemError() }
      guard try Self.fileIdentity(
        named: Self.checkpointName,
        in: directory.descriptor
      ) == validatedStageIdentity,
        try Self.fileIdentity(named: stageName, in: directory.descriptor) == oldIdentity
      else { throw LocalWritingCorpusStoreError.identityMismatch }
    } else {
      guard Self.isAbsent(named: Self.checkpointName, in: directory.descriptor) else {
        throw LocalWritingCorpusStoreError.identityMismatch
      }
      guard renameatx_np(
        directory.descriptor,
        stageName,
        directory.descriptor,
        Self.checkpointName,
        UInt32(RENAME_EXCL)
      ) == 0 else { throw Self.mapSystemError() }
      guard try Self.fileIdentity(
        named: Self.checkpointName,
        in: directory.descriptor
      ) == validatedStageIdentity else { throw LocalWritingCorpusStoreError.identityMismatch }
    }
    try faultHook?(.afterCheckpointRenameBeforeDirectorySync)
    try Self.syncDirectory(directory.descriptor)
    try Self.requireDirectoryIdentity(directory)
    publicationComplete = true
    return validatedStageIdentity
  }
}

private extension LocalWritingCorpusStore {
  struct AuthorityIdentity: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64

    init(_ status: stat) {
      device = UInt64(status.st_dev)
      inode = UInt64(status.st_ino)
    }
  }

  struct DirectoryAuthority: Sendable {
    let descriptor: Int32
    let identity: AuthorityIdentity
    let name: String?
    let parentDescriptor: Int32?
  }

  struct SelectedPathAuthority: Sendable {
    let selected: DirectoryAuthority
    let componentIdentities: [AuthorityIdentity]
  }

  struct AuthorityBytes: Sendable {
    let identity: AuthorityIdentity
    let data: Data
  }

  struct ConsentReceipt: Equatable, Sendable {
    let consentID: UUID
    let corpusID: UUID
    let createdAt: Int64

    init(corpusID: UUID, createdAt: Int64) {
      consentID = corpusID
      self.corpusID = corpusID
      self.createdAt = createdAt
    }

    var canonicalData: Data {
      Data(
        "{\"allowsAudioCapture\":false,\"allowsTranscriptReference\":false,\"consentID\":\"\(consentID.uuidString.lowercased())\",\"corpusID\":\"\(corpusID.uuidString.lowercased())\",\"createdAtUnixMilliseconds\":\(createdAt),\"purpose\":\"localWritingQuality\",\"schemaVersion\":1}".utf8
      )
    }

    static func decodeCanonical(_ data: Data) throws -> ConsentReceipt {
      guard !data.isEmpty,
        data.count <= maximumConsentBytes,
        let text = String(data: data, encoding: .utf8),
        text == text.precomposedStringWithCanonicalMapping
      else { throw LocalWritingCorpusStoreError.nonCanonicalData }
      var remainder = text[...]
      func consume(_ literal: String) throws {
        guard remainder.hasPrefix(literal) else {
          throw LocalWritingCorpusStoreError.nonCanonicalData
        }
        remainder.removeFirst(literal.count)
      }
      func consumeUUID(ending suffix: String) throws -> UUID {
        guard let end = remainder.range(of: suffix) else {
          throw LocalWritingCorpusStoreError.nonCanonicalData
        }
        let value = String(remainder[..<end.lowerBound])
        remainder = remainder[end.upperBound...]
        guard value == value.lowercased(),
          let uuid = UUID(uuidString: value),
          uuid.uuidString.lowercased() == value
        else { throw LocalWritingCorpusStoreError.nonCanonicalData }
        return uuid
      }
      try consume(
        "{\"allowsAudioCapture\":false,\"allowsTranscriptReference\":false,\"consentID\":\""
      )
      let consentID = try consumeUUID(ending: "\",\"corpusID\":\"")
      let corpusID = try consumeUUID(ending: "\",\"createdAtUnixMilliseconds\":")
      guard let end = remainder.firstIndex(of: ",") else {
        throw LocalWritingCorpusStoreError.nonCanonicalData
      }
      let number = String(remainder[..<end])
      remainder = remainder[remainder.index(after: end)...]
      guard !number.isEmpty,
        number == "0" || (number.first != "0" && number.allSatisfy(\.isNumber)),
        let createdAt = Int64(number),
        createdAt >= 0
      else { throw LocalWritingCorpusStoreError.nonCanonicalData }
      try consume("\"purpose\":\"localWritingQuality\",\"schemaVersion\":1}")
      let receipt = ConsentReceipt(
        consentID: consentID,
        corpusID: corpusID,
        createdAt: createdAt
      )
      guard remainder.isEmpty, receipt.canonicalData == data else {
        throw LocalWritingCorpusStoreError.nonCanonicalData
      }
      return receipt
    }

    private init(consentID: UUID, corpusID: UUID, createdAt: Int64) {
      self.consentID = consentID
      self.corpusID = corpusID
      self.createdAt = createdAt
    }
  }

  static func isCanonicalAbsoluteFileURL(_ url: URL) -> Bool {
    url.isFileURL
      && url.path.hasPrefix("/")
      && url.path == url.standardizedFileURL.path
      && !url.pathComponents.contains("..")
      && !url.pathComponents.contains(".")
  }

  static func isEqualOrDescendant(_ path: String, of root: String) -> Bool {
    path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
  }

  static func openSelectedPath(
    _ url: URL,
    afterLeafSnapshot: (() throws -> Void)? = nil
  ) throws -> SelectedPathAuthority {
    let components = url.pathComponents
    guard components.first == "/", components.count > 1 else {
      throw LocalWritingCorpusStoreError.invalidLocation
    }
    var descriptor = Darwin.open(
      "/",
      O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
    )
    guard descriptor >= 0 else { throw mapSystemError(missingIsLocation: true) }
    var keepDescriptor = false
    defer { if !keepDescriptor { Darwin.close(descriptor) } }
    var identities = [try validateDirectoryDescriptor(descriptor, exactMode: nil)]
    try rejectGitMarker(in: descriptor)

    for (index, component) in components.dropFirst().enumerated() {
      var status = stat()
      guard fstatat(descriptor, component, &status, AT_SYMLINK_NOFOLLOW) == 0 else {
        throw mapSystemError(missingIsLocation: true)
      }
      guard status.st_mode & S_IFMT == S_IFDIR else {
        throw LocalWritingCorpusStoreError.invalidLocation
      }
      let snapshot = AuthorityIdentity(status)
      if index == components.count - 2 { try afterLeafSnapshot?() }
      let next = Darwin.openat(
        descriptor,
        component,
        O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
      )
      guard next >= 0 else { throw mapSystemError(missingIsLocation: true) }
      var keepNext = false
      defer { if !keepNext { Darwin.close(next) } }
      guard try validateDirectoryDescriptor(next, exactMode: nil) == snapshot else {
        throw LocalWritingCorpusStoreError.identityMismatch
      }
      try rejectGitMarker(in: next)
      Darwin.close(descriptor)
      descriptor = next
      keepNext = true
      identities.append(snapshot)
    }

    keepDescriptor = true
    return SelectedPathAuthority(
      selected: DirectoryAuthority(
        descriptor: descriptor,
        identity: identities[identities.count - 1],
        name: nil,
        parentDescriptor: nil
      ),
      componentIdentities: identities
    )
  }

  static func rejectGitMarker(in directoryDescriptor: Int32) throws {
    var status = stat()
    if fstatat(directoryDescriptor, ".git", &status, AT_SYMLINK_NOFOLLOW) == 0 {
      if status.st_mode & S_IFMT == S_IFDIR || status.st_mode & S_IFMT == S_IFREG {
        throw LocalWritingCorpusStoreError.invalidLocation
      }
      return
    }
    guard errno == ENOENT else { throw mapSystemError(missingIsLocation: true) }
  }

  static func createOrOpenDirectory(
    named name: String,
    in parentDescriptor: Int32
  ) throws -> DirectoryAuthority {
    if mkdirat(parentDescriptor, name, mode_t(0o700)) == 0 {
      return try openDirectory(named: name, in: parentDescriptor)
    }
    guard errno == EEXIST else { throw mapSystemError() }
    return try openDirectory(named: name, in: parentDescriptor)
  }

  static func createDirectory(
    named name: String,
    in parentDescriptor: Int32,
    beforeParentSync: (() throws -> Void)? = nil
  ) throws -> DirectoryAuthority {
    guard mkdirat(parentDescriptor, name, mode_t(0o700)) == 0 else {
      if errno == EEXIST { throw LocalWritingCorpusStoreError.alreadyExists }
      throw mapSystemError()
    }
    let createdIdentity = try directoryIdentity(named: name, in: parentDescriptor)
    var openedAuthority: DirectoryAuthority?
    do {
      let authority = try openDirectory(named: name, in: parentDescriptor)
      openedAuthority = authority
      guard authority.identity == createdIdentity else {
        throw LocalWritingCorpusStoreError.identityMismatch
      }
      try beforeParentSync?()
      try syncDirectory(parentDescriptor, exactMode: nil)
      return authority
    } catch {
      if let openedAuthority { Darwin.close(openedAuthority.descriptor) }
      throw error
    }
  }

  static func openDirectory(
    named name: String,
    in parentDescriptor: Int32
  ) throws -> DirectoryAuthority {
    let descriptor = Darwin.openat(
      parentDescriptor,
      name,
      O_RDONLY | O_DIRECTORY | O_NOFOLLOW
    )
    guard descriptor >= 0 else { throw mapSystemError(missingIsLocation: false) }
    var keep = false
    defer { if !keep { Darwin.close(descriptor) } }
    let identity = try validateDirectoryDescriptor(descriptor, exactMode: 0o700)
    guard try directoryIdentity(named: name, in: parentDescriptor) == identity else {
      throw LocalWritingCorpusStoreError.identityMismatch
    }
    keep = true
    return DirectoryAuthority(
      descriptor: descriptor,
      identity: identity,
      name: name,
      parentDescriptor: parentDescriptor
    )
  }

  static func publishExclusive(
    _ data: Data,
    named name: String,
    in directoryDescriptor: Int32,
    beforeReadback: (() throws -> Void)? = nil
  ) throws -> AuthorityIdentity {
    let descriptor = Darwin.openat(
      directoryDescriptor,
      name,
      O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW,
      mode_t(0o600)
    )
    guard descriptor >= 0 else {
      if errno == EEXIST { throw LocalWritingCorpusStoreError.alreadyExists }
      throw mapSystemError()
    }
    defer { Darwin.close(descriptor) }
    guard fchmod(descriptor, 0o600) == 0 else {
      throw LocalWritingCorpusStoreError.ioFailure
    }
    let createdIdentity = try validateFileDescriptor(descriptor)
    try writeAll(data, to: descriptor)
    try fullSync(descriptor)
    try beforeReadback?()
    let readback = try readAuthorityFile(
      named: name,
      maximumBytes: max(data.count, 1),
      in: directoryDescriptor
    )
    guard readback.identity == createdIdentity, readback.data == data else {
      throw LocalWritingCorpusStoreError.identityMismatch
    }
    try syncDirectory(directoryDescriptor)
    return createdIdentity
  }

  static func readAuthorityFileIfPresent(
    named name: String,
    maximumBytes: Int,
    in directoryDescriptor: Int32
  ) throws -> AuthorityBytes? {
    var status = stat()
    guard fstatat(directoryDescriptor, name, &status, AT_SYMLINK_NOFOLLOW) == 0 else {
      if errno == ENOENT { return nil }
      throw mapSystemError()
    }
    return try readAuthorityFile(
      named: name,
      maximumBytes: maximumBytes,
      in: directoryDescriptor
    )
  }

  static func readAuthorityFile(
    named name: String,
    maximumBytes: Int,
    in directoryDescriptor: Int32
  ) throws -> AuthorityBytes {
    let expected = try fileIdentity(named: name, in: directoryDescriptor)
    let descriptor = Darwin.openat(directoryDescriptor, name, O_RDONLY | O_NOFOLLOW)
    guard descriptor >= 0 else { throw mapSystemError(missingIsLocation: false) }
    defer { Darwin.close(descriptor) }
    guard try validateFileDescriptor(descriptor) == expected else {
      throw LocalWritingCorpusStoreError.identityMismatch
    }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: min(8_192, maximumBytes + 1))
    while true {
      let count = Darwin.read(descriptor, &buffer, buffer.count)
      if count == 0 { break }
      if count < 0 {
        if errno == EINTR { continue }
        throw mapSystemError()
      }
      guard data.count <= maximumBytes - count else {
        throw LocalWritingCorpusStoreError.nonCanonicalData
      }
      data.append(buffer, count: count)
    }
    guard try fileIdentity(named: name, in: directoryDescriptor) == expected else {
      throw LocalWritingCorpusStoreError.identityMismatch
    }
    return AuthorityBytes(identity: expected, data: data)
  }

  static func fileIdentity(
    named name: String,
    in directoryDescriptor: Int32
  ) throws -> AuthorityIdentity {
    var status = stat()
    guard fstatat(directoryDescriptor, name, &status, AT_SYMLINK_NOFOLLOW) == 0 else {
      throw mapSystemError(missingIsLocation: false)
    }
    guard status.st_mode & S_IFMT == S_IFREG,
      status.st_uid == geteuid(),
      status.st_mode & 0o7777 == 0o600
    else { throw LocalWritingCorpusStoreError.permissions }
    return AuthorityIdentity(status)
  }

  static func directoryIdentity(
    named name: String,
    in parentDescriptor: Int32
  ) throws -> AuthorityIdentity {
    var status = stat()
    guard fstatat(parentDescriptor, name, &status, AT_SYMLINK_NOFOLLOW) == 0 else {
      throw mapSystemError(missingIsLocation: false)
    }
    guard status.st_mode & S_IFMT == S_IFDIR,
      status.st_uid == geteuid(),
      status.st_mode & 0o7777 == 0o700
    else { throw LocalWritingCorpusStoreError.permissions }
    return AuthorityIdentity(status)
  }

  static func validateDirectoryDescriptor(
    _ descriptor: Int32,
    exactMode: mode_t?
  ) throws -> AuthorityIdentity {
    var status = stat()
    guard fstat(descriptor, &status) == 0,
      status.st_mode & S_IFMT == S_IFDIR,
      exactMode == nil || status.st_mode & 0o7777 == exactMode
    else { throw LocalWritingCorpusStoreError.permissions }
    if exactMode != nil, status.st_uid != geteuid() {
      throw LocalWritingCorpusStoreError.permissions
    }
    return AuthorityIdentity(status)
  }

  static func validateFileDescriptor(_ descriptor: Int32) throws -> AuthorityIdentity {
    var status = stat()
    guard fstat(descriptor, &status) == 0,
      status.st_mode & S_IFMT == S_IFREG,
      status.st_uid == geteuid(),
      status.st_mode & 0o7777 == 0o600
    else { throw LocalWritingCorpusStoreError.permissions }
    return AuthorityIdentity(status)
  }

  static func requireDirectoryIdentity(_ authority: DirectoryAuthority) throws {
    guard try validateDirectoryDescriptor(authority.descriptor, exactMode: 0o700)
      == authority.identity
    else { throw LocalWritingCorpusStoreError.identityMismatch }
    if let name = authority.name, let parent = authority.parentDescriptor {
      guard try directoryIdentity(named: name, in: parent) == authority.identity else {
        throw LocalWritingCorpusStoreError.identityMismatch
      }
    }
  }

  static func requireSelectedPathAuthority(
    _ authority: SelectedPathAuthority,
    at url: URL,
    afterLeafSnapshot: (() throws -> Void)? = nil
  ) throws {
    guard try validateDirectoryDescriptor(authority.selected.descriptor, exactMode: nil)
      == authority.selected.identity
    else { throw LocalWritingCorpusStoreError.identityMismatch }
    let repeated: SelectedPathAuthority
    do {
      repeated = try openSelectedPath(url, afterLeafSnapshot: afterLeafSnapshot)
    } catch {
      throw LocalWritingCorpusStoreError.identityMismatch
    }
    defer { Darwin.close(repeated.selected.descriptor) }
    guard repeated.componentIdentities == authority.componentIdentities,
      repeated.selected.identity == authority.selected.identity
    else { throw LocalWritingCorpusStoreError.identityMismatch }
  }

  static func requireAuthorityFile(
    named name: String,
    maximumBytes: Int,
    expectedIdentity: AuthorityIdentity?,
    expectedData: Data,
    in directoryDescriptor: Int32
  ) throws {
    guard let expectedIdentity else {
      throw LocalWritingCorpusStoreError.ioFailure
    }
    let current = try readAuthorityFile(
      named: name,
      maximumBytes: maximumBytes,
      in: directoryDescriptor
    )
    guard current.identity == expectedIdentity, current.data == expectedData else {
      throw LocalWritingCorpusStoreError.identityMismatch
    }
  }

  static func writeAll(_ data: Data, to descriptor: Int32) throws {
    try data.withUnsafeBytes { bytes in
      guard let base = bytes.baseAddress else { return }
      var offset = 0
      while offset < bytes.count {
        let count = Darwin.write(
          descriptor,
          base.advanced(by: offset),
          bytes.count - offset
        )
        if count < 0 {
          if errno == EINTR { continue }
          throw mapSystemError()
        }
        guard count > 0 else { throw LocalWritingCorpusStoreError.ioFailure }
        offset += count
      }
    }
  }

  static func fullSync(_ descriptor: Int32) throws {
    guard fcntl(descriptor, F_FULLFSYNC) == 0 else {
      throw LocalWritingCorpusStoreError.ioFailure
    }
  }

  static func syncDirectory(_ descriptor: Int32, exactMode: mode_t? = 0o700) throws {
    _ = try validateDirectoryDescriptor(descriptor, exactMode: exactMode)
    guard fsync(descriptor) == 0 else { throw LocalWritingCorpusStoreError.ioFailure }
  }

  static func isAbsent(named name: String, in directoryDescriptor: Int32) -> Bool {
    var status = stat()
    return fstatat(directoryDescriptor, name, &status, AT_SYMLINK_NOFOLLOW) != 0
      && errno == ENOENT
  }

  static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  static func mapLedgerError(_ error: Error) -> LocalWritingCorpusStoreError {
    guard let ledgerError = error as? LocalWritingExposureLedgerError else {
      return .ioFailure
    }
    switch ledgerError {
    case .conflict, .invalidOrder:
      return .rollbackOrFork
    case .corruption, .nonCanonicalData:
      return .nonCanonicalData
    case .identityMismatch:
      return .identityMismatch
    case .permissions:
      return .permissions
    case .invalidation, .ioFailure:
      return .ioFailure
    }
  }

  static func mapSystemError(
    missingIsLocation: Bool = false
  ) -> LocalWritingCorpusStoreError {
    switch errno {
    case ENOENT:
      return missingIsLocation ? .invalidLocation : .missingAuthority
    case EEXIST:
      return .alreadyExists
    case EACCES, EPERM, ELOOP, EISDIR, ENOTDIR:
      return .permissions
    default:
      return .ioFailure
    }
  }
}
