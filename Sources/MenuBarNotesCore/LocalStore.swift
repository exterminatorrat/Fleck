import Foundation

public actor LocalStore {
    public enum StoreError: Error, Equatable {
        case invalidFilename
    }

    private struct Manifest: Codable {
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
        let manifestURL = rootURL.appendingPathComponent("workspace.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            var workspace = Workspace()
            workspace.ensureNoteExists()
            return workspace
        }

        let manifest = try decoder.decode(Manifest.self, from: Data(contentsOf: manifestURL))
        let notes = try manifest.noteOrder.compactMap { id -> Note? in
            guard let metadata = manifest.metadata[id] else { return nil }
            let bodyURL = noteURL(for: id)
            guard fileManager.fileExists(atPath: bodyURL.path) else { return nil }
            return Note(
                id: id,
                title: metadata.title,
                body: try String(contentsOf: bodyURL, encoding: .utf8),
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

        let manifest = Manifest(
            noteOrder: workspace.notes.map(\.id),
            selectedNoteID: workspace.selectedNoteID,
            metadata: Dictionary(uniqueKeysWithValues: workspace.notes.map { note in
                (note.id, Metadata(
                    title: note.title,
                    createdAt: note.createdAt,
                    modifiedAt: note.modifiedAt,
                    isPinned: note.isPinned
                ))
            })
        )

        for note in workspace.notes {
            try note.body.write(to: noteURL(for: note.id), atomically: true, encoding: .utf8)
        }
        try encoder.encode(manifest).write(
            to: rootURL.appendingPathComponent("workspace.json"),
            options: .atomic
        )
        try encoder.encode(preferences).write(
            to: rootURL.appendingPathComponent("preferences.json"),
            options: .atomic
        )

        let liveFilenames = Set(workspace.notes.map { "\($0.id.uuidString.lowercased()).md" })
        for fileURL in try fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)
        where fileURL.pathExtension == "md" && !liveFilenames.contains(fileURL.lastPathComponent) {
            try fileManager.removeItem(at: fileURL)
        }
    }

    public func loadPreferences() throws -> AppPreferences {
        try createDirectoryIfNeeded()
        let url = rootURL.appendingPathComponent("preferences.json")
        guard fileManager.fileExists(atPath: url.path) else { return AppPreferences() }
        return try decoder.decode(AppPreferences.self, from: Data(contentsOf: url))
    }

    private func createDirectoryIfNeeded() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    private func noteURL(for id: UUID) -> URL {
        rootURL.appendingPathComponent("\(id.uuidString.lowercased()).md")
    }
}
