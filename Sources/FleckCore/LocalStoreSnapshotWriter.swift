import CryptoKit
import Foundation

public enum LocalStoreFolderMigrationWarning: Equatable, Sendable {
  case malformedFolderCollection
  case invalidFolderRecord
  case duplicateFolderID(UUID)
  case reservedFolderName(String)
  case duplicateFolderName(String)
  case malformedNoteFolderID(UUID)
  case orphanNoteFolderID(noteID: UUID, folderID: UUID)
}

struct LocalStoreTrashMetadata: Codable {
  var id: UUID
  var title: String
  var tabColorHex: String?
  var createdAt: Date
  var modifiedAt: Date
  var isPinned: Bool
  var deletedAt: Date
  var agentAccess: Bool?
  var revision: UInt64?
  var folderID: UUID?
}

public enum LocalStoreSnapshotSource: Equatable, Sendable {
  case root
  case recovery
  case fresh
}

public struct LocalStoreSnapshot: Equatable, Sendable {
  public let workspace: Workspace
  public let preferences: AppPreferences
  public let commitProofs: [AgentWorkspaceCommitProof]
  public let source: LocalStoreSnapshotSource
  public let generation: UInt64
  public let folderMigrationWarnings: [LocalStoreFolderMigrationWarning]

  public init(
    workspace: Workspace,
    preferences: AppPreferences,
    commitProofs: [AgentWorkspaceCommitProof],
    source: LocalStoreSnapshotSource,
    generation: UInt64 = 0,
    folderMigrationWarnings: [LocalStoreFolderMigrationWarning] = []
  ) {
    self.workspace = workspace
    self.preferences = preferences
    self.commitProofs = commitProofs
    self.source = source
    self.generation = generation
    self.folderMigrationWarnings = folderMigrationWarnings
  }
}

public enum LocalStoreSnapshotWriteResult: Equatable, Sendable {
  case committed
  case superseded
}

public final class LocalStoreSnapshotWriter: @unchecked Sendable {
  struct Hooks: Sendable {
    var beforeManifestCommit: @Sendable (UInt64) throws -> Void
    var afterManifestCommit: @Sendable (UInt64) throws -> Void

    init(
      beforeManifestCommit: @escaping @Sendable (UInt64) throws -> Void = { _ in },
      afterManifestCommit: @escaping @Sendable (UInt64) throws -> Void = { _ in }
    ) {
      self.beforeManifestCommit = beforeManifestCommit
      self.afterManifestCommit = afterManifestCommit
    }
  }

  private struct Manifest: Codable {
    var formatVersion: Int?
    var noteOrder: [UUID]
    var selectedNoteID: UUID?
    var metadata: [UUID: Metadata]
    var folders: FolderCollection?
    var snapshotGeneration: UInt64?
    var snapshotIntegrityVersion: Int?
    var markdownSHA256: [String: String]?
    var rtfSHA256: [String: String]?
    var preferencesSHA256: String?
    var agentCommitProofs: [AgentWorkspaceCommitProof]?

    init(
      formatVersion: Int?,
      noteOrder: [UUID],
      selectedNoteID: UUID?,
      metadata: [UUID: Metadata],
      folders: FolderCollection?,
      snapshotGeneration: UInt64?,
      snapshotIntegrityVersion: Int?,
      markdownSHA256: [String: String]?,
      rtfSHA256: [String: String]?,
      preferencesSHA256: String?,
      agentCommitProofs: [AgentWorkspaceCommitProof]?
    ) {
      self.formatVersion = formatVersion
      self.noteOrder = noteOrder
      self.selectedNoteID = selectedNoteID
      self.metadata = metadata
      self.folders = folders
      self.snapshotGeneration = snapshotGeneration
      self.snapshotIntegrityVersion = snapshotIntegrityVersion
      self.markdownSHA256 = markdownSHA256
      self.rtfSHA256 = rtfSHA256
      self.preferencesSHA256 = preferencesSHA256
      self.agentCommitProofs = agentCommitProofs
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      formatVersion = try container.decodeIfPresent(Int.self, forKey: .formatVersion)
      noteOrder = try container.decode([UUID].self, forKey: .noteOrder)
      selectedNoteID = try container.decodeIfPresent(UUID.self, forKey: .selectedNoteID)
      metadata = try container.decode([UUID: Metadata].self, forKey: .metadata)
      if container.contains(.folders) {
        folders = try container.decodeNil(forKey: .folders)
          ? FolderCollection(malformed: true)
          : container.decode(FolderCollection.self, forKey: .folders)
      } else {
        folders = nil
      }
      snapshotGeneration = try container.decodeIfPresent(UInt64.self, forKey: .snapshotGeneration)
      snapshotIntegrityVersion = try container.decodeIfPresent(
        Int.self,
        forKey: .snapshotIntegrityVersion
      )
      markdownSHA256 = try container.decodeIfPresent(
        [String: String].self,
        forKey: .markdownSHA256
      )
      rtfSHA256 = try container.decodeIfPresent([String: String].self, forKey: .rtfSHA256)
      preferencesSHA256 = try container.decodeIfPresent(String.self, forKey: .preferencesSHA256)
      agentCommitProofs = try container.decodeIfPresent(
        [AgentWorkspaceCommitProof].self,
        forKey: .agentCommitProofs
      )
    }

    private enum CodingKeys: String, CodingKey {
      case formatVersion
      case noteOrder
      case selectedNoteID
      case metadata
      case folders
      case snapshotGeneration
      case snapshotIntegrityVersion
      case markdownSHA256
      case rtfSHA256
      case preferencesSHA256
      case agentCommitProofs
    }
  }

  private struct FolderRecord: Codable {
    let id: UUID?
    let name: String?

    init(id: UUID, name: String) {
      self.id = id
      self.name = name
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      id = try? container.decode(UUID.self, forKey: .id)
      name = try? container.decode(String.self, forKey: .name)
    }

    private enum CodingKeys: String, CodingKey {
      case id
      case name
    }
  }

  private struct FolderCollection: Codable {
    let elements: [FolderRecord?]
    let isMalformed: Bool

    init(records: [FolderRecord]) {
      elements = records.map(Optional.some)
      isMalformed = false
    }

    init(malformed: Bool) {
      elements = []
      isMalformed = malformed
    }

    init(from decoder: Decoder) throws {
      do {
        var container = try decoder.unkeyedContainer()
        var elements: [FolderRecord?] = []
        while !container.isAtEnd {
          let element = try container.superDecoder()
          if let record = try? FolderRecord(from: element) {
            elements.append(record)
          } else {
            elements.append(nil)
          }
        }
        self.elements = elements
        isMalformed = false
      } catch {
        elements = []
        isMalformed = true
      }
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.unkeyedContainer()
      for element in elements {
        if let record = element {
          try container.encode(record)
        }
      }
    }
  }

  private struct Metadata: Codable {
    var title: String
    var tabColorHex: String?
    var createdAt: Date
    var modifiedAt: Date
    var isPinned: Bool
    var agentAccess: Bool?
    var revision: UInt64?
    var folderID: UUID?
    var folderIDWasMalformed = false

    init(
      title: String,
      tabColorHex: String?,
      createdAt: Date,
      modifiedAt: Date,
      isPinned: Bool,
      agentAccess: Bool?,
      revision: UInt64?,
      folderID: UUID?
    ) {
      self.title = title
      self.tabColorHex = tabColorHex
      self.createdAt = createdAt
      self.modifiedAt = modifiedAt
      self.isPinned = isPinned
      self.agentAccess = agentAccess
      self.revision = revision
      self.folderID = folderID
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      title = try container.decode(String.self, forKey: .title)
      tabColorHex = try container.decodeIfPresent(String.self, forKey: .tabColorHex)
      createdAt = try container.decode(Date.self, forKey: .createdAt)
      modifiedAt = try container.decode(Date.self, forKey: .modifiedAt)
      isPinned = try container.decode(Bool.self, forKey: .isPinned)
      agentAccess = try container.decodeIfPresent(Bool.self, forKey: .agentAccess)
      revision = try container.decodeIfPresent(UInt64.self, forKey: .revision)
      if container.contains(.folderID) {
        if try container.decodeNil(forKey: .folderID) {
          folderID = nil
        } else if let decoded = try? container.decode(UUID.self, forKey: .folderID) {
          folderID = decoded
        } else {
          folderID = nil
          folderIDWasMalformed = true
        }
      } else {
        folderID = nil
      }
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(title, forKey: .title)
      try container.encodeIfPresent(tabColorHex, forKey: .tabColorHex)
      try container.encode(createdAt, forKey: .createdAt)
      try container.encode(modifiedAt, forKey: .modifiedAt)
      try container.encode(isPinned, forKey: .isPinned)
      try container.encodeIfPresent(agentAccess, forKey: .agentAccess)
      try container.encodeIfPresent(revision, forKey: .revision)
      try container.encodeIfPresent(folderID, forKey: .folderID)
    }

    private enum CodingKeys: String, CodingKey {
      case title
      case tabColorHex
      case createdAt
      case modifiedAt
      case isPinned
      case agentAccess
      case revision
      case folderID
    }
  }

  private struct LoadedCandidate {
    let snapshot: LocalStoreSnapshot
    let manifest: Manifest
    let directory: URL
  }

  private static let formatVersion = 2
  private static let integrityVersion = 1
  private static let maximumCommitProofs = 256
  private static let trashLifetime: TimeInterval = 30 * 24 * 60 * 60

  private let rootURL: URL
  private let recoveryURL: URL
  private let fileManager: FileManager
  private let now: @Sendable () -> Date
  private let hooks: Hooks
  private let lock = NSLock()
  private var highestCommittedGeneration: UInt64?
  private var highestAdmittedGeneration: UInt64?

  public convenience init(
    rootURL: URL,
    fileManager: FileManager = .default,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.init(
      rootURL: rootURL,
      fileManager: fileManager,
      now: now,
      hooks: Hooks()
    )
  }

  init(
    rootURL: URL,
    fileManager: FileManager = .default,
    now: @escaping @Sendable () -> Date = Date.init,
    hooks: Hooks
  ) {
    self.rootURL = rootURL
    recoveryURL = rootURL.appendingPathComponent("Recovery", isDirectory: true)
    self.fileManager = fileManager
    self.now = now
    self.hooks = hooks
  }

  @discardableResult
  public func save(
    workspace: Workspace,
    preferences: AppPreferences,
    generation: UInt64,
    commitProof: AgentWorkspaceCommitProof? = nil,
    trashedNotes: [Note] = []
  ) throws -> LocalStoreSnapshotWriteResult {
    try lock.withLock {
      initializeWatermarkIfNeeded()
      if let highestAdmittedGeneration,
        generation < highestAdmittedGeneration
      {
        return .superseded
      }
      highestAdmittedGeneration = max(
        highestAdmittedGeneration ?? 0,
        generation
      )
      try fileManager.createDirectory(
        at: rootURL,
        withIntermediateDirectories: true
      )
      if !trashedNotes.isEmpty {
        for note in trashedNotes {
          try archiveInTrash(note)
        }
        try purgeExpiredTrashLocked()
      }

      let validRoot = loadCandidate(in: rootURL, source: .root)
      if let validRoot {
        try createRecovery(from: validRoot)
      }

      let preferencesData = try encoder().encode(preferences)
      let preferencesHash = sha256(preferencesData)
      let canReusePreferences = canReuse(
        hash: preferencesHash,
        expectedHash: validRoot?.manifest.preferencesSHA256,
        root: validRoot
      )
      if !canReusePreferences {
        try preferencesData.write(
          to: rootURL.appendingPathComponent("preferences.json"),
          options: .atomic
        )
      }

      var markdownHashes: [String: String] = [:]
      var rtfHashes: [String: String] = [:]
      for note in workspace.notes {
        let key = note.id.uuidString.lowercased()
        let bodyData = Data(note.body.utf8)
        let bodyHash = sha256(bodyData)
        let canReuseBody = canReuse(
          hash: bodyHash,
          expectedHash: validRoot?.manifest.markdownSHA256?[key],
          root: validRoot
        )
        if !canReuseBody {
          try bodyData.write(to: noteURL(note.id, in: rootURL), options: .atomic)
        }
        if canReuseBody, let expectedHash = validRoot?.manifest.markdownSHA256?[key] {
          markdownHashes[key] = expectedHash
        } else {
          markdownHashes[key] = bodyHash
        }
        let richTextURL = rtfURL(note.id, in: rootURL)
        if let richTextRTF = note.richTextRTF {
          let richTextHash = sha256(richTextRTF)
          let canReuseRichText = canReuse(
            hash: richTextHash,
            expectedHash: validRoot?.manifest.rtfSHA256?[key],
            root: validRoot
          )
          if !canReuseRichText {
            try richTextRTF.write(to: richTextURL, options: .atomic)
          }
          if canReuseRichText, let expectedHash = validRoot?.manifest.rtfSHA256?[key] {
            rtfHashes[key] = expectedHash
          } else {
            rtfHashes[key] = richTextHash
          }
        }
      }

      var proofs =
        (validRoot?.manifest.agentCommitProofs
        ?? loadCandidate(in: recoveryURL, source: .recovery)?
        .manifest.agentCommitProofs
        ?? [])
        .filter { $0.expiresAt > now() }
      if let commitProof {
        proofs.removeAll { $0.changeID == commitProof.changeID }
        proofs.append(commitProof)
      }
      proofs = Array(
        proofs
          .sorted {
            if $0.expiresAt != $1.expiresAt {
              return $0.expiresAt > $1.expiresAt
            }
            return $0.changeID.uuidString < $1.changeID.uuidString
          }
          .prefix(Self.maximumCommitProofs)
      )

      let manifestPreferencesHash = canReusePreferences
        ? validRoot?.manifest.preferencesSHA256 ?? preferencesHash
        : preferencesHash
      let manifest = Manifest(
        formatVersion: Self.formatVersion,
        noteOrder: workspace.notes.map(\.id),
        selectedNoteID: workspace.selectedNoteID,
        metadata: Dictionary(
          uniqueKeysWithValues: workspace.notes.map { note in
            (
              note.id,
              Metadata(
                title: note.title,
                tabColorHex: note.tabColorHex,
                createdAt: note.createdAt,
                modifiedAt: note.modifiedAt,
                isPinned: note.isPinned,
                agentAccess: note.agentAccess,
                revision: note.revision,
                folderID: note.folderID
              )
            )
          }
        ),
        folders: FolderCollection(
          records: workspace.folders.map { FolderRecord(id: $0.id, name: $0.name) }
        ),
        snapshotGeneration: generation,
        snapshotIntegrityVersion: Self.integrityVersion,
        markdownSHA256: markdownHashes,
        rtfSHA256: rtfHashes,
        preferencesSHA256: manifestPreferencesHash,
        agentCommitProofs: proofs
      )
      try hooks.beforeManifestCommit(generation)
      try encoder().encode(manifest).write(
        to: rootURL.appendingPathComponent("workspace.json"),
        options: .atomic
      )
      highestCommittedGeneration = generation

      try? hooks.afterManifestCommit(generation)
      cleanupOrphans(workspace: workspace)
      return .committed
    }
  }

  public func loadSnapshot() throws -> LocalStoreSnapshot {
    try lock.withLock {
      try fileManager.createDirectory(
        at: rootURL,
        withIntermediateDirectories: true
      )
      if let root = loadCandidate(in: rootURL, source: .root) {
        highestCommittedGeneration = max(
          highestCommittedGeneration ?? 0,
          root.manifest.snapshotGeneration ?? 0
        )
        highestAdmittedGeneration = max(
          highestAdmittedGeneration ?? 0,
          root.manifest.snapshotGeneration ?? 0
        )
        return root.snapshot
      }
      if let recovery = loadCandidate(in: recoveryURL, source: .recovery) {
        highestCommittedGeneration = max(
          highestCommittedGeneration ?? 0,
          recovery.manifest.snapshotGeneration ?? 0
        )
        highestAdmittedGeneration = max(
          highestAdmittedGeneration ?? 0,
          recovery.manifest.snapshotGeneration ?? 0
        )
        return recovery.snapshot
      }

      let rootManifest = rootURL.appendingPathComponent("workspace.json")
      let recoveryManifest = recoveryURL.appendingPathComponent("workspace.json")
      if fileManager.fileExists(atPath: rootManifest.path)
        || fileManager.fileExists(atPath: recoveryManifest.path)
      {
        throw LocalStore.StoreError.invalidSnapshot
      }
      var workspace = Workspace()
      workspace.ensureNoteExists()
      return LocalStoreSnapshot(
        workspace: workspace,
        preferences: AppPreferences(),
        commitProofs: [],
        source: .fresh,
        generation: 0
      )
    }
  }

  func purgeExpiredTrash() throws {
    try lock.withLock {
      try purgeExpiredTrashLocked()
    }
  }

  private func initializeWatermarkIfNeeded() {
    guard highestCommittedGeneration == nil else { return }
    let root = loadCandidate(in: rootURL, source: .root)
    let recovery = loadCandidate(in: recoveryURL, source: .recovery)
    highestCommittedGeneration = max(
      root?.manifest.snapshotGeneration ?? 0,
      recovery?.manifest.snapshotGeneration ?? 0
    )
    highestAdmittedGeneration = highestCommittedGeneration
  }

  private func repairFolders(
    _ collection: FolderCollection?
  ) -> (
    folders: [Folder],
    warnings: [LocalStoreFolderMigrationWarning]
  ) {
    guard let collection else { return ([], []) }

    var warnings: [LocalStoreFolderMigrationWarning] = []
    if collection.isMalformed {
      warnings.append(.malformedFolderCollection)
    }

    var folders: [Folder] = []
    var folderIDs = Set<UUID>()
    var folderNameKeys = Set<String>()
    for element in collection.elements {
      guard let record = element else {
        warnings.append(.invalidFolderRecord)
        continue
      }
      guard let id = record.id, let rawName = record.name else {
        warnings.append(.invalidFolderRecord)
        continue
      }
      guard !folderIDs.contains(id) else {
        warnings.append(.duplicateFolderID(id))
        continue
      }

      let normalizedName: String
      do {
        normalizedName = try Folder.normalizedName(rawName)
      } catch let error as FolderError where error == .reservedName {
        warnings.append(.reservedFolderName(rawName))
        continue
      } catch {
        warnings.append(.invalidFolderRecord)
        continue
      }

      var repairedName = normalizedName
      if folderNameKeys.contains(Folder.nameKey(repairedName)) {
        let baseName = folders.first {
          Folder.nameKey($0.name) == Folder.nameKey(repairedName)
        }?.name ?? repairedName
        var suffixNumber = 2
        repeat {
          let suffix = " (\(suffixNumber))"
          let prefixLimit = max(1, 80 - suffix.count)
          repairedName = String(baseName.prefix(prefixLimit)) + suffix
          suffixNumber += 1
        } while folderNameKeys.contains(Folder.nameKey(repairedName))
        warnings.append(.duplicateFolderName(normalizedName))
      }

      guard let folder = try? Folder(id: id, name: repairedName) else {
        warnings.append(.invalidFolderRecord)
        continue
      }
      folders.append(folder)
      folderIDs.insert(id)
      folderNameKeys.insert(Folder.nameKey(folder.name))
    }
    return (folders, warnings)
  }

  private func loadCandidate(
    in directory: URL,
    source: LocalStoreSnapshotSource
  ) -> LoadedCandidate? {
    guard
      let manifestData = try? Data(
        contentsOf: directory.appendingPathComponent("workspace.json")
      ),
      let manifest = try? decoder().decode(Manifest.self, from: manifestData),
      manifest.formatVersion == nil
        || manifest.formatVersion == 1
        || manifest.formatVersion == Self.formatVersion
    else {
      return nil
    }
    if manifest.formatVersion == Self.formatVersion,
      manifest.snapshotIntegrityVersion != Self.integrityVersion
    {
      return nil
    }

    let preferencesURL = directory.appendingPathComponent("preferences.json")
    let preferencesData = try? Data(contentsOf: preferencesURL)
    let preferences: AppPreferences
    if let preferencesData,
      let decoded = try? decoder().decode(AppPreferences.self, from: preferencesData)
    {
      preferences = decoded
    } else if manifest.snapshotIntegrityVersion == nil {
      preferences = AppPreferences()
    } else {
      return nil
    }

    if manifest.snapshotIntegrityVersion == Self.integrityVersion {
      guard
        let preferencesData,
        let preferencesSHA256 = manifest.preferencesSHA256,
        sha256(preferencesData) == preferencesSHA256,
        let markdownSHA256 = manifest.markdownSHA256,
        let rtfSHA256 = manifest.rtfSHA256
      else {
        return nil
      }
      for id in manifest.noteOrder {
        let key = id.uuidString.lowercased()
        guard
          let expected = markdownSHA256[key],
          let bodyData = try? Data(contentsOf: noteURL(id, in: directory)),
          sha256(bodyData) == expected
        else {
          return nil
        }
        if let expectedRTF = rtfSHA256[key] {
          guard
            let richTextData = try? Data(contentsOf: rtfURL(id, in: directory)),
            sha256(richTextData) == expectedRTF
          else {
            return nil
          }
        }
      }
    } else if manifest.snapshotIntegrityVersion != nil {
      return nil
    }

    let folderRepair = repairFolders(manifest.folders)
    var folderMigrationWarnings = folderRepair.warnings
    let validFolderIDs = Set(folderRepair.folders.map(\.id))
    let notes = manifest.noteOrder.compactMap { id -> Note? in
      guard
        let metadata = manifest.metadata[id],
        let body = try? String(
          contentsOf: noteURL(id, in: directory),
          encoding: .utf8
        )
      else {
        return nil
      }
      let key = id.uuidString.lowercased()
      let shouldLoadRTF =
        manifest.snapshotIntegrityVersion == nil
        || manifest.rtfSHA256?[key] != nil
      let richTextRTF =
        shouldLoadRTF
        ? try? Data(contentsOf: rtfURL(id, in: directory))
        : nil
      let folderID: UUID?
      if metadata.folderIDWasMalformed {
        folderID = nil
        folderMigrationWarnings.append(.malformedNoteFolderID(id))
      } else if let metadataFolderID = metadata.folderID {
        if validFolderIDs.contains(metadataFolderID) {
          folderID = metadataFolderID
        } else {
          folderID = nil
          folderMigrationWarnings.append(
            .orphanNoteFolderID(noteID: id, folderID: metadataFolderID)
          )
        }
      } else {
        folderID = nil
      }
      return Note(
        id: id,
        title: metadata.title,
        body: body,
        richTextRTF: richTextRTF,
        tabColorHex: metadata.tabColorHex,
        createdAt: metadata.createdAt,
        modifiedAt: metadata.modifiedAt,
        isPinned: metadata.isPinned,
        agentAccess: metadata.agentAccess ?? false,
        revision: metadata.revision ?? 0,
        folderID: folderID
      )
    }
    if manifest.snapshotIntegrityVersion != nil,
      notes.count != manifest.noteOrder.count
    {
      return nil
    }
    var workspace = Workspace(
      notes: notes,
      selectedNoteID: manifest.selectedNoteID,
      folders: folderRepair.folders
    )
    workspace.ensureNoteExists()
    return LoadedCandidate(
      snapshot: LocalStoreSnapshot(
        workspace: workspace,
        preferences: preferences,
        commitProofs: (manifest.agentCommitProofs ?? [])
          .filter { $0.expiresAt > now() },
        source: source,
        generation: manifest.snapshotGeneration ?? 0,
        folderMigrationWarnings: folderMigrationWarnings
      ),
      manifest: manifest,
      directory: directory
    )
  }

  private func createRecovery(from root: LoadedCandidate) throws {
    let staging = rootURL.appendingPathComponent(
      "Recovery.staging",
      isDirectory: true
    )
    try? fileManager.removeItem(at: staging)
    try fileManager.createDirectory(
      at: staging,
      withIntermediateDirectories: true
    )
    do {
      var filenames: [String] = []
      let preferencesSource = root.directory.appendingPathComponent(
        "preferences.json"
      )
      if fileManager.fileExists(atPath: preferencesSource.path) {
        filenames.append("preferences.json")
      } else {
        try encoder().encode(root.snapshot.preferences).write(
          to: staging.appendingPathComponent("preferences.json"),
          options: .atomic
        )
      }
      for id in root.manifest.noteOrder {
        filenames.append(noteURL(id, in: root.directory).lastPathComponent)
        if root.manifest.rtfSHA256?[id.uuidString.lowercased()] != nil
          || fileManager.fileExists(
            atPath: rtfURL(id, in: root.directory).path
          )
        {
          filenames.append(rtfURL(id, in: root.directory).lastPathComponent)
        }
      }
      for filename in filenames {
        let source = root.directory.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: source.path) else { continue }
        try fileManager.copyItem(
          at: source,
          to: staging.appendingPathComponent(filename)
        )
      }
      try fileManager.copyItem(
        at: root.directory.appendingPathComponent("workspace.json"),
        to: staging.appendingPathComponent("workspace.json")
      )
      try? fileManager.removeItem(at: recoveryURL)
      try fileManager.moveItem(at: staging, to: recoveryURL)
    } catch {
      try? fileManager.removeItem(at: staging)
      throw error
    }
  }

  private func cleanupOrphans(workspace: Workspace) {
    let live = Set(
      workspace.notes.flatMap {
        [noteURL($0.id, in: rootURL).lastPathComponent]
          + ($0.richTextRTF == nil
            ? []
            : [rtfURL($0.id, in: rootURL).lastPathComponent])
      }
    )
    guard
      let contents = try? fileManager.contentsOfDirectory(
        at: rootURL,
        includingPropertiesForKeys: nil
      )
    else { return }
    for url in contents
    where ["md", "rtf"].contains(url.pathExtension)
      && !live.contains(url.lastPathComponent)
    {
      try? fileManager.removeItem(at: url)
    }
  }

  private var trashURL: URL {
    rootURL.appendingPathComponent("Trash", isDirectory: true)
  }

  private func archiveInTrash(_ note: Note) throws {
    try fileManager.createDirectory(
      at: trashURL,
      withIntermediateDirectories: true
    )
    let entryURL = trashEntryURL(for: note.id)
    if fileManager.fileExists(atPath: entryURL.path) {
      guard validTrashMetadata(at: entryURL) != nil else {
        throw LocalStore.StoreError.invalidTrashEntry(note.id)
      }
      return
    }

    let stagingURL = trashURL.appendingPathComponent(
      "\(note.id.uuidString.lowercased()).staging",
      isDirectory: true
    )
    try? fileManager.removeItem(at: stagingURL)
    do {
      try fileManager.createDirectory(
        at: stagingURL,
        withIntermediateDirectories: true
      )
      let metadata = LocalStoreTrashMetadata(
        id: note.id,
        title: note.title,
        tabColorHex: note.tabColorHex,
        createdAt: note.createdAt,
        modifiedAt: note.modifiedAt,
        isPinned: note.isPinned,
        deletedAt: now(),
        agentAccess: note.agentAccess,
        revision: note.revision,
        folderID: note.folderID
      )
      try encoder().encode(metadata).write(
        to: stagingURL.appendingPathComponent("metadata.json"),
        options: .atomic
      )
      try note.body.write(
        to: stagingURL.appendingPathComponent("body.md"),
        atomically: true,
        encoding: .utf8
      )
      if let richTextRTF = note.richTextRTF {
        try richTextRTF.write(
          to: stagingURL.appendingPathComponent("rich-text.rtf"),
          options: .atomic
        )
      }
      try fileManager.moveItem(at: stagingURL, to: entryURL)
    } catch {
      try? fileManager.removeItem(at: stagingURL)
      throw error
    }
  }

  private func validTrashMetadata(
    at entryURL: URL
  ) -> LocalStoreTrashMetadata? {
    guard
      let directoryID = UUID(uuidString: entryURL.lastPathComponent),
      let data = try? Data(
        contentsOf: entryURL.appendingPathComponent("metadata.json")
      ),
      let metadata = try? decoder().decode(
        LocalStoreTrashMetadata.self,
        from: data
      ),
      metadata.id == directoryID,
      (try? Data(contentsOf: entryURL.appendingPathComponent("body.md"))) != nil
    else {
      return nil
    }
    return metadata
  }

  private func trashEntryURL(for id: UUID) -> URL {
    trashURL.appendingPathComponent(
      id.uuidString.lowercased(),
      isDirectory: true
    )
  }

  private func purgeExpiredTrashLocked() throws {
    guard fileManager.fileExists(atPath: trashURL.path) else { return }
    let cutoff = now().addingTimeInterval(-Self.trashLifetime)
    for entryURL in try fileManager.contentsOfDirectory(
      at: trashURL,
      includingPropertiesForKeys: nil
    ) {
      guard
        let metadata = validTrashMetadata(at: entryURL),
        metadata.deletedAt <= cutoff
      else {
        continue
      }
      try fileManager.removeItem(at: entryURL)
    }
  }

  private func noteURL(_ id: UUID, in directory: URL) -> URL {
    directory.appendingPathComponent("\(id.uuidString.lowercased()).md")
  }

  private func rtfURL(_ id: UUID, in directory: URL) -> URL {
    directory.appendingPathComponent("\(id.uuidString.lowercased()).rtf")
  }

  private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data)
      .map { String(format: "%02x", $0) }
      .joined()
  }

  private func canReuse(
    hash: String,
    expectedHash: String?,
    root: LoadedCandidate?
  ) -> Bool {
    // loadCandidate has already validated the root bytes against expectedHash.
    root?.manifest.snapshotIntegrityVersion == Self.integrityVersion
      && expectedHash == hash
  }

  private func encoder() -> JSONEncoder {
    let value = JSONEncoder()
    value.outputFormatting = [.prettyPrinted, .sortedKeys]
    value.dateEncodingStrategy = .iso8601
    return value
  }

  private func decoder() -> JSONDecoder {
    let value = JSONDecoder()
    value.dateDecodingStrategy = .iso8601
    return value
  }
}
