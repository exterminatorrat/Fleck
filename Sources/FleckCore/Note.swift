import Foundation

public struct Note: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public var title: String
  public var body: String
  /// Versioned RTF data used only when formatting cannot be represented by Markdown.
  public var richTextRTF: Data?
  public var tabColorHex: String?
  public var createdAt: Date
  public var modifiedAt: Date
  public var isPinned: Bool
  public var agentAccess: Bool
  public var revision: UInt64
  public var folderID: UUID?

  public init(
    id: UUID = UUID(),
    title: String = "Untitled",
    body: String = "",
    richTextRTF: Data? = nil,
    tabColorHex: String? = nil,
    createdAt: Date = Date(),
    modifiedAt: Date = Date(),
    isPinned: Bool = false,
    agentAccess: Bool = false,
    revision: UInt64 = 0,
    folderID: UUID? = nil
  ) {
    self.id = id
    self.title = title
    self.body = body
    self.richTextRTF = richTextRTF
    self.tabColorHex = tabColorHex
    self.createdAt = createdAt
    self.modifiedAt = modifiedAt
    self.isPinned = isPinned
    self.agentAccess = agentAccess
    self.revision = revision
    self.folderID = folderID
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case title
    case body
    case richTextRTF
    case tabColorHex
    case createdAt
    case modifiedAt
    case isPinned
    case agentAccess
    case revision
    case folderID
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    body = try container.decode(String.self, forKey: .body)
    richTextRTF = try container.decodeIfPresent(Data.self, forKey: .richTextRTF)
    tabColorHex = try container.decodeIfPresent(String.self, forKey: .tabColorHex)
    createdAt = try container.decode(Date.self, forKey: .createdAt)
    modifiedAt = try container.decode(Date.self, forKey: .modifiedAt)
    isPinned = try container.decode(Bool.self, forKey: .isPinned)
    agentAccess = try container.decodeIfPresent(Bool.self, forKey: .agentAccess) ?? false
    revision = try container.decodeIfPresent(UInt64.self, forKey: .revision) ?? 0
    folderID = try container.decodeIfPresent(UUID.self, forKey: .folderID)
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
