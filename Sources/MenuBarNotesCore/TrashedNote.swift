import Foundation

public struct TrashedNote: Identifiable, Equatable, Sendable {
  public var note: Note
  public var deletedAt: Date

  public var id: UUID { note.id }

  public init(note: Note, deletedAt: Date) {
    self.note = note
    self.deletedAt = deletedAt
  }
}
