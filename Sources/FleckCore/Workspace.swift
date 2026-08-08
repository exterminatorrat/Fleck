import Foundation

public enum FolderError: Error, Equatable, Sendable {
  case emptyName
  case controlCharacter
  case pathSeparator
  case nameTooLong
  case reservedName
  case duplicateName
  case invalidTarget
}

public struct Folder: Codable, Equatable, Sendable {
  public let id: UUID
  public var name: String

  public init(id: UUID = UUID(), name: String) throws {
    self.id = id
    self.name = try Self.normalizedName(name)
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      id: container.decode(UUID.self, forKey: .id),
      name: container.decode(String.self, forKey: .name)
    )
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case name
  }

  static func normalizedName(_ value: String) throws -> String {
    let canonical = value.precomposedStringWithCanonicalMapping
    for scalar in canonical.unicodeScalars {
      let isLineBreak = scalar == "\n" || scalar == "\r"
        || scalar == "\u{2028}" || scalar == "\u{2029}"
      if isLineBreak || CharacterSet.controlCharacters.contains(scalar)
      {
        throw FolderError.controlCharacter
      }
      if scalar == "/" || scalar == "\\" {
        throw FolderError.pathSeparator
      }
    }

    var normalized = ""
    var pendingSpace = false
    for character in canonical {
      if character.isWhitespace {
        pendingSpace = true
        continue
      }
      if pendingSpace && !normalized.isEmpty {
        normalized.append(" ")
      }
      normalized.append(character)
      pendingSpace = false
    }
    guard !normalized.isEmpty else { throw FolderError.emptyName }
    guard normalized.count <= 80 else { throw FolderError.nameTooLong }
    let key = Self.nameKey(normalized)
    guard key != "inbox", key != "trash" else {
      throw FolderError.reservedName
    }
    return normalized
  }

  static func nameKey(_ value: String) -> String {
    value
      .precomposedStringWithCanonicalMapping
      .folding(
        options: [.caseInsensitive],
        locale: Locale(identifier: "en_US_POSIX")
      )
      .precomposedStringWithCanonicalMapping
  }
}

public struct Workspace: Codable, Equatable, Sendable {
  public var notes: [Note]
  public var selectedNoteID: UUID?
  public var folders: [Folder]

  public init(
    notes: [Note] = [],
    selectedNoteID: UUID? = nil,
    folders: [Folder] = []
  ) {
    self.notes = notes
    self.selectedNoteID = selectedNoteID
    self.folders = folders
  }

  private enum CodingKeys: String, CodingKey {
    case notes
    case selectedNoteID
    case folders
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    notes = try container.decode([Note].self, forKey: .notes)
    selectedNoteID = try container.decodeIfPresent(UUID.self, forKey: .selectedNoteID)
    folders = try container.decodeIfPresent([Folder].self, forKey: .folders) ?? []
  }

  @discardableResult
  public mutating func createFolder(name: String) throws -> Folder {
    let folder = try Folder(name: name)
    guard !folders.contains(where: { Folder.nameKey($0.name) == Folder.nameKey(folder.name) })
    else { throw FolderError.duplicateName }
    folders.append(folder)
    return folder
  }

  public mutating func renameFolder(id: UUID, name: String) throws {
    guard let index = folders.firstIndex(where: { $0.id == id }) else {
      throw FolderError.invalidTarget
    }
    let normalized = try Folder.normalizedName(name)
    guard !folders.enumerated().contains(where: {
      $0.offset != index && Folder.nameKey($0.element.name) == Folder.nameKey(normalized)
    }) else { throw FolderError.duplicateName }
    folders[index].name = normalized
  }

  public mutating func reorderFolder(id: UUID, to destination: Int) throws {
    guard let source = folders.firstIndex(where: { $0.id == id }) else { return }
    var reordered = folders
    let folder = reordered.remove(at: source)
    guard (0...reordered.count).contains(destination) else { return }
    reordered.insert(folder, at: destination)
    folders = reordered
  }

  public mutating func deleteFolder(id: UUID) throws {
    guard let index = folders.firstIndex(where: { $0.id == id }) else {
      throw FolderError.invalidTarget
    }
    folders.remove(at: index)
    for index in notes.indices where notes[index].folderID == id {
      notes[index].folderID = nil
    }
  }

  public mutating func moveNote(id: UUID, toFolderID folderID: UUID?) throws {
    guard let index = notes.firstIndex(where: { $0.id == id }) else {
      throw FolderError.invalidTarget
    }
    if let folderID, !folders.contains(where: { $0.id == folderID }) {
      throw FolderError.invalidTarget
    }
    notes[index].folderID = folderID
  }

  public func notes(inFolderID folderID: UUID?) -> [Note] {
    notes.filter { $0.folderID == folderID }
  }

  public mutating func reorderNote(
    id: UUID,
    inFolderID folderID: UUID?,
    toVisibleIndex destination: Int
  ) throws {
    guard let moving = notes.first(where: { $0.id == id }), moving.folderID == folderID else {
      throw FolderError.invalidTarget
    }
    guard folderID == nil || folders.contains(where: { $0.id == folderID }) else {
      throw FolderError.invalidTarget
    }

    let isPinned = moving.isPinned
    var partition = notes.filter { $0.isPinned == isPinned && $0.id != id }
    let visible = partition.filter { $0.folderID == folderID }
    guard (0...visible.count).contains(destination) else { return }

    let insertion: Int
    if destination == visible.count {
      insertion = partition.lastIndex(where: { $0.folderID == folderID }).map { $0 + 1 }
        ?? partition.count
    } else {
      insertion = partition.firstIndex(where: { $0.id == visible[destination].id }) ?? partition.count
    }
    partition.insert(moving, at: insertion)

    let pinned = isPinned ? partition : notes.filter(\.isPinned)
    let unpinned = isPinned ? notes.filter { !$0.isPinned } : partition
    notes = pinned + unpinned
  }

  public mutating func addRestoredNote(_ note: Note) {
    guard !notes.contains(where: { $0.id == note.id }) else {
      selectedNoteID = note.id
      return
    }
    var restored = note
    if let folderID = restored.folderID,
      !folders.contains(where: { $0.id == folderID })
    {
      restored.folderID = nil
    }
    let insertion = restored.isPinned
      ? (notes.lastIndex(where: \.isPinned).map { $0 + 1 } ?? 0)
      : notes.count
    notes.insert(restored, at: insertion)
    selectedNoteID = restored.id
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
    var changed = false
    var incrementsRevision = false
    if let title, title != notes[index].title {
      notes[index].title = title
      changed = true
      incrementsRevision = true
    }
    if let body, body != notes[index].body {
      notes[index].body = body
      changed = true
      incrementsRevision = true
    }
    if let isPinned, isPinned != notes[index].isPinned {
      notes[index].isPinned = isPinned
      changed = true
    }
    guard changed else { return }
    if incrementsRevision {
      notes[index].revision += 1
    }
    notes[index].modifiedAt = now
  }

  public mutating func updateContent(
    id: UUID,
    body: String,
    rtf: Data?,
    now: Date = Date()
  ) {
    guard let index = notes.firstIndex(where: { $0.id == id }),
      notes[index].body != body || notes[index].richTextRTF != rtf
    else { return }
    notes[index].body = body
    notes[index].richTextRTF = rtf
    notes[index].revision += 1
    notes[index].modifiedAt = now
  }

  public mutating func setAgentAccess(
    id: UUID,
    enabled: Bool,
    now: Date = Date()
  ) {
    guard let index = notes.firstIndex(where: { $0.id == id }),
      notes[index].agentAccess != enabled
    else { return }
    notes[index].agentAccess = enabled
    notes[index].revision += 1
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
    let pinnedCount = notes.filter(\.isPinned).count
    let lowerBound = note.isPinned ? 0 : pinnedCount
    let upperBound = note.isPinned ? pinnedCount : notes.count
    notes.insert(note, at: min(max(lowerBound, destination), upperBound))
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

  public mutating func setTabColor(id: UUID, hex: String?, now: Date = Date()) {
    guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
    notes[index].tabColorHex = hex
    notes[index].modifiedAt = now
  }
}
