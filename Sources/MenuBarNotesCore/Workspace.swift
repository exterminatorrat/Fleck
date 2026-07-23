import Foundation

public struct Workspace: Codable, Equatable, Sendable {
    public var notes: [Note]
    public var selectedNoteID: UUID?

    public init(notes: [Note] = [], selectedNoteID: UUID? = nil) {
        self.notes = notes
        self.selectedNoteID = selectedNoteID
    }

    public mutating func ensureNoteExists(now: Date = Date()) {
        guard notes.isEmpty else {
            if selectedNoteID == nil || !notes.contains(where: { $0.id == selectedNoteID }) {
                selectedNoteID = notes[0].id
            }
            return
        }

        let note = Note(createdAt: now, modifiedAt: now)
        notes = [note]
        selectedNoteID = note.id
    }

    @discardableResult
    public mutating func addNote(now: Date = Date()) -> UUID {
        let note = Note(createdAt: now, modifiedAt: now)
        notes.append(note)
        selectedNoteID = note.id
        return note.id
    }

    public mutating func deleteNote(id: UUID, now: Date = Date()) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes.remove(at: index)

        if selectedNoteID == id {
            selectedNoteID = notes.indices.contains(index) ? notes[index].id : notes.last?.id
        }
        ensureNoteExists(now: now)
    }

    public mutating func updateNote(
        id: UUID,
        title: String? = nil,
        body: String? = nil,
        isPinned: Bool? = nil,
        now: Date = Date()
    ) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        if let title { notes[index].title = title }
        if let body { notes[index].body = body }
        if let isPinned { notes[index].isPinned = isPinned }
        notes[index].modifiedAt = now
    }
}
