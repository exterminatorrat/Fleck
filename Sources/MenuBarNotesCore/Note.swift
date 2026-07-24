import Foundation

public struct Note: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public var title: String
  public var body: String
  /// Versioned RTF data used only when formatting cannot be represented by Markdown.
  public var richTextRTF: Data?
  public var createdAt: Date
  public var modifiedAt: Date
  public var isPinned: Bool

  public init(
    id: UUID = UUID(),
    title: String = "Untitled",
    body: String = "",
    richTextRTF: Data? = nil,
    createdAt: Date = Date(),
    modifiedAt: Date = Date(),
    isPinned: Bool = false
  ) {
    self.id = id
    self.title = title
    self.body = body
    self.richTextRTF = richTextRTF
    self.createdAt = createdAt
    self.modifiedAt = modifiedAt
    self.isPinned = isPinned
  }

  public var displayTitle: String {
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedTitle.isEmpty { return trimmedTitle }

    let firstLine =
      body
      .split(whereSeparator: \Character.isNewline)
      .first?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return firstLine.flatMap { $0.isEmpty ? nil : String($0.prefix(40)) } ?? "Untitled"
  }
}
