import Foundation

public actor LocalStore {
  public enum StoreError: Error, Equatable {
    case invalidFilename
    case invalidTrashEntry(UUID)
    case missingTrashEntry(UUID)
  }

  private struct Manifest: Codable {
    var formatVersion: Int?
    var noteOrder: [UUID]
    var selectedNoteID: UUID?
    var metadata: [UUID: Metadata]
  }

  private struct Metadata: Codable {
    var title: String
    var createdAt: Date
    var modifiedAt: Date
    var isPinned: Bool
  }

  private struct TrashMetadata: Codable {
    var id: UUID
    var title: String
    var createdAt: Date
    var modifiedAt: Date
    var isPinned: Bool
    var deletedAt: Date
  }

  private let rootURL: URL
  private let fileManager: FileManager
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder
  private let now: @Sendable () -> Date
  private static let currentFormatVersion = 1
  private static let trashLifetime: TimeInterval = 30 * 24 * 60 * 60

  public init(
    rootURL: URL,
    fileManager: FileManager = .default,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.rootURL = rootURL
    self.fileManager = fileManager
    self.now = now
    encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
  }

  public func loadWorkspace() throws -> Workspace {
    try createDirectoryIfNeeded()
    try purgeExpiredTrash()
    guard let (manifest, sourceDirectory) = loadManifest() else {
      var workspace = Workspace()
      workspace.ensureNoteExists()
      return workspace
    }

    let notes = manifest.noteOrder.compactMap { id -> Note? in
      guard let metadata = manifest.metadata[id] else { return nil }
      let bodyDirectories = sourceDirectory == recoveryURL ? [recoveryURL] : [rootURL, recoveryURL]
      guard
        let body = bodyDirectories.lazy.compactMap({ directory in
          try? String(contentsOf: self.noteURL(for: id, in: directory), encoding: .utf8)
        }).first
      else { return nil }
      let richTextRTF = bodyDirectories.lazy.compactMap { directory in
        try? Data(contentsOf: self.richTextURL(for: id, in: directory))
      }.first
      return Note(
        id: id,
        title: metadata.title,
        body: body,
        richTextRTF: richTextRTF,
        createdAt: metadata.createdAt,
        modifiedAt: metadata.modifiedAt,
        isPinned: metadata.isPinned
      )
    }

    var workspace = Workspace(notes: notes, selectedNoteID: manifest.selectedNoteID)
    workspace.ensureNoteExists()
    return workspace
  }

  public func save(
    workspace: Workspace,
    preferences: AppPreferences,
    trashedNotes: [Note] = []
  ) throws {
    try createDirectoryIfNeeded()
    for note in trashedNotes {
      try archiveInTrash(note)
    }
    try purgeExpiredTrash()
    try saveActive(workspace: workspace, preferences: preferences)
  }

  public func loadTrash() throws -> [TrashedNote] {
    try createDirectoryIfNeeded()
    try purgeExpiredTrash()
    guard fileManager.fileExists(atPath: trashURL.path) else { return [] }

    return try fileManager
      .contentsOfDirectory(at: trashURL, includingPropertiesForKeys: nil)
      .compactMap(loadTrashedNote)
      .sorted { $0.deletedAt > $1.deletedAt }
  }

  public func restore(
    _ trashedNote: TrashedNote,
    into workspace: Workspace,
    preferences: AppPreferences
  ) throws -> Workspace {
    try createDirectoryIfNeeded()
    let entryURL = trashEntryURL(for: trashedNote.id)
    guard loadTrashedNote(at: entryURL) != nil else {
      throw StoreError.missingTrashEntry(trashedNote.id)
    }

    var restoredWorkspace = workspace
    restoredWorkspace.addNote(trashedNote.note)
    try saveActive(workspace: restoredWorkspace, preferences: preferences)
    try fileManager.removeItem(at: entryURL)
    return restoredWorkspace
  }

  private func saveActive(workspace: Workspace, preferences: AppPreferences) throws {
    try createRecoverySnapshot()

    let manifest = Manifest(
      formatVersion: Self.currentFormatVersion,
      noteOrder: workspace.notes.map(\.id),
      selectedNoteID: workspace.selectedNoteID,
      metadata: Dictionary(
        uniqueKeysWithValues: workspace.notes.map { note in
          (
            note.id,
            Metadata(
              title: note.title,
              createdAt: note.createdAt,
              modifiedAt: note.modifiedAt,
              isPinned: note.isPinned
            )
          )
        })
    )

    for note in workspace.notes {
      try note.body.write(to: noteURL(for: note.id), atomically: true, encoding: .utf8)
      let richTextURL = richTextURL(for: note.id, in: rootURL)
      if let richTextRTF = note.richTextRTF {
        try richTextRTF.write(to: richTextURL, options: .atomic)
      } else if fileManager.fileExists(atPath: richTextURL.path) {
        try fileManager.removeItem(at: richTextURL)
      }
    }
    try encoder.encode(manifest).write(
      to: rootURL.appendingPathComponent("workspace.json"),
      options: .atomic
    )
    try encoder.encode(preferences).write(
      to: rootURL.appendingPathComponent("preferences.json"),
      options: .atomic
    )

    let liveFilenames = Set(
      workspace.notes.flatMap {
        ["\($0.id.uuidString.lowercased()).md", "\($0.id.uuidString.lowercased()).rtf"]
      })
    for fileURL in try fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)
    where ["md", "rtf"].contains(fileURL.pathExtension)
      && !liveFilenames.contains(fileURL.lastPathComponent)
    {
      try fileManager.removeItem(at: fileURL)
    }
  }

  public func loadPreferences() throws -> AppPreferences {
    try createDirectoryIfNeeded()
    let url = rootURL.appendingPathComponent("preferences.json")
    if let preferences = decode(AppPreferences.self, at: url) { return preferences }
    return decode(AppPreferences.self, at: recoveryURL.appendingPathComponent("preferences.json"))
      ?? AppPreferences()
  }

  private func createDirectoryIfNeeded() throws {
    try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
  }

  private func noteURL(for id: UUID) -> URL {
    noteURL(for: id, in: rootURL)
  }

  private var recoveryURL: URL { rootURL.appendingPathComponent("Recovery", isDirectory: true) }

  private var trashURL: URL { rootURL.appendingPathComponent("Trash", isDirectory: true) }

  private func noteURL(for id: UUID, in directory: URL) -> URL {
    directory.appendingPathComponent("\(id.uuidString.lowercased()).md")
  }

  private func richTextURL(for id: UUID, in directory: URL) -> URL {
    directory.appendingPathComponent("\(id.uuidString.lowercased()).rtf")
  }

  private func decode<Value: Decodable>(_ type: Value.Type, at url: URL) -> Value? {
    guard fileManager.fileExists(atPath: url.path),
      let data = try? Data(contentsOf: url)
    else { return nil }
    return try? decoder.decode(type, from: data)
  }

  private func loadManifest() -> (Manifest, URL)? {
    let candidates = [rootURL, recoveryURL]
    for directory in candidates {
      let url = directory.appendingPathComponent("workspace.json")
      guard let manifest = decode(Manifest.self, at: url) else { continue }
      guard manifest.formatVersion == nil || manifest.formatVersion == Self.currentFormatVersion
      else {
        continue
      }
      return (manifest, directory)
    }
    return nil
  }

  private func archiveInTrash(_ note: Note) throws {
    try fileManager.createDirectory(at: trashURL, withIntermediateDirectories: true)
    let entryURL = trashEntryURL(for: note.id)
    if fileManager.fileExists(atPath: entryURL.path) {
      guard loadTrashedNote(at: entryURL) != nil else {
        throw StoreError.invalidTrashEntry(note.id)
      }
      return
    }

    let stagingURL = trashURL.appendingPathComponent(
      "\(note.id.uuidString.lowercased()).staging",
      isDirectory: true
    )
    try? fileManager.removeItem(at: stagingURL)
    do {
      try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
      let metadata = TrashMetadata(
        id: note.id,
        title: note.title,
        createdAt: note.createdAt,
        modifiedAt: note.modifiedAt,
        isPinned: note.isPinned,
        deletedAt: now()
      )
      try encoder.encode(metadata).write(
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

  private func loadTrashedNote(at entryURL: URL) -> TrashedNote? {
    guard
      let directoryID = UUID(uuidString: entryURL.lastPathComponent),
      let metadata = decode(
        TrashMetadata.self,
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
        createdAt: metadata.createdAt,
        modifiedAt: metadata.modifiedAt,
        isPinned: metadata.isPinned
      ),
      deletedAt: metadata.deletedAt
    )
  }

  private func trashEntryURL(for id: UUID) -> URL {
    trashURL.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
  }

  private func purgeExpiredTrash() throws {
    guard fileManager.fileExists(atPath: trashURL.path) else { return }
    let cutoff = now().addingTimeInterval(-Self.trashLifetime)
    for entryURL in try fileManager.contentsOfDirectory(
      at: trashURL,
      includingPropertiesForKeys: nil
    ) {
      guard let trashedNote = loadTrashedNote(at: entryURL),
        trashedNote.deletedAt <= cutoff
      else { continue }
      try fileManager.removeItem(at: entryURL)
    }
  }

  /// Keeps one complete previous generation so an interrupted or malformed save is recoverable.
  private func createRecoverySnapshot() throws {
    let manifestURL = rootURL.appendingPathComponent("workspace.json")
    guard fileManager.fileExists(atPath: manifestURL.path) else { return }

    let stagingURL = rootURL.appendingPathComponent("Recovery.staging", isDirectory: true)
    try? fileManager.removeItem(at: stagingURL)
    try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)

    let filenames = try fileManager.contentsOfDirectory(atPath: rootURL.path).filter {
      $0 == "workspace.json" || $0 == "preferences.json"
        || $0.hasSuffix(".md") || $0.hasSuffix(".rtf")
    }
    for filename in filenames {
      try fileManager.copyItem(
        at: rootURL.appendingPathComponent(filename),
        to: stagingURL.appendingPathComponent(filename)
      )
    }
    try? fileManager.removeItem(at: recoveryURL)
    try fileManager.moveItem(at: stagingURL, to: recoveryURL)
  }
}
