import Foundation

public actor LocalStore {
  public enum RestoreOutcome: Equatable, Sendable {
    public enum TrashCleanup: Equatable, Sendable {
      case succeeded
      case failed
    }

    case committed(workspace: Workspace, trashCleanup: TrashCleanup)

    public var workspace: Workspace {
      switch self {
      case let .committed(workspace, _): workspace
      }
    }

    public var trashCleanup: TrashCleanup {
      switch self {
      case let .committed(_, trashCleanup): trashCleanup
      }
    }
  }

  public enum StoreError: Error, Equatable {
    case invalidFilename
    case invalidTrashEntry(UUID)
    case missingTrashEntry(UUID)
    case invalidSnapshot
    case restoreConflict
  }

  public nonisolated let rootURL: URL
  private let fileManager: FileManager
  private let decoder: JSONDecoder
  public nonisolated let snapshotWriter: LocalStoreSnapshotWriter

  public init(
    rootURL: URL,
    fileManager: FileManager = .default,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.rootURL = rootURL
    self.fileManager = fileManager
    snapshotWriter = LocalStoreSnapshotWriter(
      rootURL: rootURL,
      fileManager: fileManager,
      now: now
    )
    decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
  }

  public func loadWorkspace() throws -> Workspace {
    try createDirectoryIfNeeded()
    try snapshotWriter.purgeExpiredTrash()
    do {
      return try snapshotWriter.loadSnapshot().workspace
    } catch StoreError.invalidSnapshot {
      var workspace = Workspace()
      workspace.ensureNoteExists()
      return workspace
    }
  }

  public func loadSnapshot() throws -> LocalStoreSnapshot {
    try createDirectoryIfNeeded()
    try snapshotWriter.purgeExpiredTrash()
    return try snapshotWriter.loadSnapshot()
  }

  @discardableResult
  public func save(
    workspace: Workspace,
    preferences: AppPreferences,
    trashedNotes: [Note] = [],
    generation: UInt64 = 0,
    commitProof: AgentWorkspaceCommitProof? = nil
  ) throws -> LocalStoreSnapshotWriteResult {
    return try snapshotWriter.save(
      workspace: workspace,
      preferences: preferences,
      generation: generation,
      commitProof: commitProof,
      trashedNotes: trashedNotes
    )
  }

  public func loadTrash() throws -> [TrashedNote] {
    try createDirectoryIfNeeded()
    try snapshotWriter.purgeExpiredTrash()
    guard fileManager.fileExists(atPath: trashURL.path) else { return [] }

    return
      try fileManager
      .contentsOfDirectory(at: trashURL, includingPropertiesForKeys: nil)
      .compactMap(loadTrashedNote)
      .sorted { $0.deletedAt > $1.deletedAt }
  }

  public func restore(
    _ trashedNote: TrashedNote,
    into workspace: Workspace,
    preferences: AppPreferences,
    generation: UInt64 = 0
  ) throws -> RestoreOutcome {
    try createDirectoryIfNeeded()
    let entryURL = trashEntryURL(for: trashedNote.id)
    guard loadTrashedNote(at: entryURL) != nil else {
      throw StoreError.missingTrashEntry(trashedNote.id)
    }

    var restoredWorkspace = workspace
    restoredWorkspace.addRestoredNote(trashedNote.note)
    let result = try snapshotWriter.save(
      workspace: restoredWorkspace,
      preferences: preferences,
      generation: generation
    )
    guard result == .committed else {
      throw StoreError.restoreConflict
    }
    let trashCleanup: RestoreOutcome.TrashCleanup
    do {
      try fileManager.removeItem(at: entryURL)
      trashCleanup = .succeeded
    } catch {
      trashCleanup = .failed
    }
    return .committed(
      workspace: restoredWorkspace,
      trashCleanup: trashCleanup
    )
  }

  public func loadPreferences() throws -> AppPreferences {
    try createDirectoryIfNeeded()
    return try snapshotWriter.loadSnapshot().preferences
  }

  private func createDirectoryIfNeeded() throws {
    try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
  }

  private var trashURL: URL { rootURL.appendingPathComponent("Trash", isDirectory: true) }

  private func decode<Value: Decodable>(_ type: Value.Type, at url: URL) -> Value? {
    guard fileManager.fileExists(atPath: url.path),
      let data = try? Data(contentsOf: url)
    else { return nil }
    return try? decoder.decode(type, from: data)
  }

  private func loadTrashedNote(at entryURL: URL) -> TrashedNote? {
    guard
      let directoryID = UUID(uuidString: entryURL.lastPathComponent),
      let metadata = decode(
        LocalStoreTrashMetadata.self,
        at: entryURL.appendingPathComponent("metadata.json")
      ),
      metadata.id == directoryID,
      let body = try? String(
        contentsOf: entryURL.appendingPathComponent("body.md"),
        encoding: .utf8
      )
    else { return nil }

    let richTextURL = entryURL.appendingPathComponent("rich-text.rtf")
    let richTextRTF =
      fileManager.fileExists(atPath: richTextURL.path)
      ? try? Data(contentsOf: richTextURL)
      : nil
    return TrashedNote(
      note: Note(
        id: metadata.id,
        title: metadata.title,
        body: body,
        richTextRTF: richTextRTF,
        tabColorHex: metadata.tabColorHex,
        createdAt: metadata.createdAt,
        modifiedAt: metadata.modifiedAt,
        isPinned: metadata.isPinned,
        agentAccess: metadata.agentAccess ?? false,
        revision: metadata.revision ?? 0,
        folderID: metadata.folderID
      ),
      deletedAt: metadata.deletedAt
    )
  }

  private func trashEntryURL(for id: UUID) -> URL {
    trashURL.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
  }

}
