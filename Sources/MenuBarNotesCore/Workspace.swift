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

  public mutating func addNote(_ note: Note) {
    guard !notes.contains(where: { $0.id == note.id }) else {
      selectedNoteID = note.id
      return
    }
    notes.append(note)
    selectedNoteID = note.id
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

  public mutating func selectAdjacent(forward: Bool) {
    guard !notes.isEmpty else { return }
    let index = notes.firstIndex(where: { $0.id == selectedNoteID }) ?? 0
    selectedNoteID = notes[(index + (forward ? 1 : notes.count - 1)) % notes.count].id
  }

  public mutating func moveNote(id: UUID, to destination: Int) {
    guard let source = notes.firstIndex(where: { $0.id == id }) else { return }
    let note = notes.remove(at: source)
    notes.insert(note, at: min(max(0, destination), notes.count))
  }

  public mutating func togglePinned(id: UUID, now: Date = Date()) {
    guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
    notes[index].isPinned.toggle()
    notes[index].modifiedAt = now
    let note = notes.remove(at: index)
    let destination =
      note.isPinned
      ? (notes.lastIndex(where: \.isPinned).map { $0 + 1 } ?? 0)
      : (notes.lastIndex(where: \.isPinned).map { $0 + 1 } ?? 0)
    notes.insert(note, at: destination)
  }
}
