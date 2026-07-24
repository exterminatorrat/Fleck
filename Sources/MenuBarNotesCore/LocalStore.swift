import Foundation

public actor LocalStore {
  public enum StoreError: Error, Equatable {
    case invalidFilename
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

  private let rootURL: URL
  private let fileManager: FileManager
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder
  private static let currentFormatVersion = 1

  public init(rootURL: URL, fileManager: FileManager = .default) {
    self.rootURL = rootURL
    self.fileManager = fileManager
    encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
  }

  public func loadWorkspace() throws -> Workspace {
    try createDirectoryIfNeeded()
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

  public func save(workspace: Workspace, preferences: AppPreferences) throws {
    try createDirectoryIfNeeded()
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
