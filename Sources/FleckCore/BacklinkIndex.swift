import Foundation

public struct BacklinkSource: Equatable, Identifiable, Sendable {
  public let sourceNoteID: UUID
  public let sourceDisplayTitle: String
  public let sourceFolderID: UUID?
  public let targetNoteID: UUID
  public let excerpt: String
  public let referenceCount: Int
  public let sourceModifiedAt: Date

  public var id: UUID { sourceNoteID }

  public init(
    sourceNoteID: UUID,
    sourceDisplayTitle: String,
    sourceFolderID: UUID?,
    targetNoteID: UUID,
    excerpt: String,
    referenceCount: Int,
    sourceModifiedAt: Date
  ) {
    self.sourceNoteID = sourceNoteID
    self.sourceDisplayTitle = sourceDisplayTitle
    self.sourceFolderID = sourceFolderID
    self.targetNoteID = targetNoteID
    self.excerpt = excerpt
    self.referenceCount = referenceCount
    self.sourceModifiedAt = sourceModifiedAt
  }
}

public struct BacklinkIndex: Equatable, Sendable {
  private let incomingByTarget: [UUID: [BacklinkSource]]

  public init(incomingByTarget: [UUID: [BacklinkSource]] = [:]) {
    self.incomingByTarget = incomingByTarget
  }

  public func incoming(to targetNoteID: UUID) -> [BacklinkSource] {
    incomingByTarget[targetNoteID] ?? []
  }
}

public actor BacklinkIndexer {
  private struct CachedSource {
    let revision: UInt64
    let body: String
    let links: [NoteLink]
  }

  private struct SourceMetadata {
    let displayTitle: String
    let folderID: UUID?
    let modifiedAt: Date
  }

  private struct Group {
    let firstLink: NoteLink
    var referenceCount: Int
  }

  private var cache: [UUID: CachedSource] = [:]
  private var lastCompletedIndex = BacklinkIndex()

  public init() {}

  public func build(liveNotes: [Note]) async -> BacklinkIndex {
    guard !Task.isCancelled else { return lastCompletedIndex }

    let liveIDs = Set(liveNotes.map(\.id))
    cache = cache.filter { liveIDs.contains($0.key) }
    let sortedNotes = liveNotes.sorted {
      $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased()
    }
    var metadataBySourceID: [UUID: SourceMetadata] = [:]
    var bodyBySourceID: [UUID: String] = [:]
    var groupsByTarget: [UUID: [UUID: Group]] = [:]

    for (index, note) in sortedNotes.enumerated() {
      if index.isMultiple(of: 64) {
        guard !Task.isCancelled else { return lastCompletedIndex }
        await Task.yield()
        guard !Task.isCancelled else { return lastCompletedIndex }
      }

      metadataBySourceID[note.id] = SourceMetadata(
        displayTitle: note.displayTitle,
        folderID: note.folderID,
        modifiedAt: note.modifiedAt
      )
      bodyBySourceID[note.id] = note.body
      let links: [NoteLink]
      if let cached = cache[note.id], cached.revision == note.revision, cached.body == note.body {
        links = cached.links
      } else {
        links = NoteLinkParser.links(in: note.body)
        cache[note.id] = CachedSource(revision: note.revision, body: note.body, links: links)
      }

      for link in links where link.targetNoteID != note.id {
        if var sourceGroups = groupsByTarget[link.targetNoteID],
          var group = sourceGroups[note.id]
        {
          group.referenceCount += 1
          sourceGroups[note.id] = group
          groupsByTarget[link.targetNoteID] = sourceGroups
        } else {
          var sourceGroups = groupsByTarget[link.targetNoteID] ?? [:]
          sourceGroups[note.id] = Group(firstLink: link, referenceCount: 1)
          groupsByTarget[link.targetNoteID] = sourceGroups
        }
      }
    }

    guard !Task.isCancelled else { return lastCompletedIndex }

    var incomingByTarget: [UUID: [BacklinkSource]] = [:]
    for (targetID, sourceGroups) in groupsByTarget {
      guard !Task.isCancelled else { return lastCompletedIndex }
      let sources = sourceGroups.compactMap { sourceID, group -> BacklinkSource? in
        guard let metadata = metadataBySourceID[sourceID] else { return nil }
        return BacklinkSource(
          sourceNoteID: sourceID,
          sourceDisplayTitle: metadata.displayTitle,
          sourceFolderID: metadata.folderID,
          targetNoteID: targetID,
          excerpt: NoteLinkParser.excerpt(
            around: group.firstLink.range,
            in: bodyBySourceID[sourceID] ?? "",
            limit: 160
          ),
          referenceCount: group.referenceCount,
          sourceModifiedAt: metadata.modifiedAt
        )
      }.sorted { lhs, rhs in
        if lhs.sourceModifiedAt != rhs.sourceModifiedAt {
          return lhs.sourceModifiedAt > rhs.sourceModifiedAt
        }
        return lhs.sourceNoteID.uuidString.lowercased() < rhs.sourceNoteID.uuidString.lowercased()
      }
      incomingByTarget[targetID] = sources
    }

    guard !Task.isCancelled else { return lastCompletedIndex }
    let completed = BacklinkIndex(incomingByTarget: incomingByTarget)
    lastCompletedIndex = completed
    return completed
  }
}
