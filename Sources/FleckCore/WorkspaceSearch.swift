import Foundation

public enum WorkspaceSearchMatchField: String, Equatable, Sendable {
  case title
  case body
}

public struct WorkspaceSearchMatch: Equatable, Sendable {
  public let field: WorkspaceSearchMatchField
  public let location: Int
  public let length: Int

  public init(field: WorkspaceSearchMatchField, location: Int, length: Int) {
    self.field = field
    self.location = location
    self.length = length
  }
}

public struct WorkspaceSearchResult: Equatable, Identifiable, Sendable {
  public let noteID: UUID
  public let displayTitle: String
  public let snippet: String
  public let match: WorkspaceSearchMatch
  public let score: Int

  public var id: UUID { noteID }

  public init(
    noteID: UUID,
    displayTitle: String,
    snippet: String,
    match: WorkspaceSearchMatch,
    score: Int
  ) {
    self.noteID = noteID
    self.displayTitle = displayTitle
    self.snippet = snippet
    self.match = match
    self.score = score
  }
}

public struct WorkspaceSearchEngine: Sendable {
  public init() {}

  public func search(
    query: String,
    in notes: [Note],
    limit: Int = 50
  ) async -> [WorkspaceSearchResult] {
    guard limit > 0, !Task.isCancelled else { return [] }

    let foldedQuery = Self.fold(
      query.trimmingCharacters(in: .whitespacesAndNewlines)
    )
    guard !foldedQuery.isEmpty, !Task.isCancelled else { return [] }

    var matches: [RankedSearchResult] = []
    matches.reserveCapacity(min(limit, notes.count))

    for (index, note) in notes.enumerated() {
      if index.isMultiple(of: 64) {
        guard !Task.isCancelled else { return [] }
        await Task.yield()
        guard !Task.isCancelled else { return [] }
      }

      guard let match = Self.match(for: note, query: foldedQuery) else { continue }
      matches.append(
        RankedSearchResult(
          result: match,
          modifiedAt: note.modifiedAt,
          uuidString: note.id.uuidString,
          inputIndex: index
        )
      )
    }

    guard !Task.isCancelled else { return [] }
    matches.sort { lhs, rhs in
      if lhs.result.score != rhs.result.score {
        return lhs.result.score > rhs.result.score
      }
      if lhs.modifiedAt != rhs.modifiedAt {
        return lhs.modifiedAt > rhs.modifiedAt
      }
      if lhs.uuidString != rhs.uuidString {
        return lhs.uuidString < rhs.uuidString
      }
      return lhs.inputIndex < rhs.inputIndex
    }

    guard !Task.isCancelled else { return [] }
    return matches.prefix(limit).map(\.result)
  }

  private struct RankedSearchResult {
    let result: WorkspaceSearchResult
    let modifiedAt: Date
    let uuidString: String
    let inputIndex: Int
  }

  private struct OriginalMatch {
    let location: Int
    let length: Int
    let characterRange: Range<Int>
  }

  private struct FoldedText {
    let characters: [Character]
    let utf16Offsets: [Int]
    let folded: String
    let foldedStartOffsets: [Int]
    let foldedEndOffsets: [Int]

    init(_ original: String) {
      characters = Array(original)

      var originalOffsets = [0]
      originalOffsets.reserveCapacity(characters.count + 1)
      for character in characters {
        originalOffsets.append(
          originalOffsets[originalOffsets.count - 1] + String(character).utf16.count
        )
      }
      utf16Offsets = originalOffsets

      var foldedValue = ""
      var foldedStarts = [0]
      var foldedEnds = [0]
      foldedValue.reserveCapacity(original.utf16.count)

      for index in characters.indices {
        let originalStart = originalOffsets[index]
        let originalEnd = originalOffsets[index + 1]
        let piece = WorkspaceSearchEngine.fold(String(characters[index]))
        let pieceLength = piece.utf16.count
        guard pieceLength > 0 else { continue }

        foldedStarts[foldedStarts.count - 1] = originalStart
        foldedEnds[foldedEnds.count - 1] = originalStart
        foldedValue.append(contentsOf: piece)

        for boundary in 1...pieceLength {
          if boundary == pieceLength {
            foldedStarts.append(originalEnd)
            foldedEnds.append(originalEnd)
          } else {
            foldedStarts.append(originalStart)
            foldedEnds.append(originalEnd)
          }
        }
      }

      folded = foldedValue
      foldedStartOffsets = foldedStarts
      foldedEndOffsets = foldedEnds
    }

    func firstMatch(of foldedQuery: String) -> OriginalMatch? {
      guard let range = folded.range(of: foldedQuery) else { return nil }
      let foldedStart = range.lowerBound.utf16Offset(in: folded)
      let foldedEnd = range.upperBound.utf16Offset(in: folded)
      guard foldedStart < foldedEnd,
        foldedEnd < foldedStartOffsets.count,
        foldedEnd < foldedEndOffsets.count
      else { return nil }

      let originalStart = foldedStartOffsets[foldedStart]
      let originalEnd = foldedEndOffsets[foldedEnd]
      guard originalEnd > originalStart,
        let characterStart = utf16Offsets.firstIndex(of: originalStart),
        let characterEnd = utf16Offsets.firstIndex(of: originalEnd),
        characterStart < characterEnd
      else { return nil }

      return OriginalMatch(
        location: originalStart,
        length: originalEnd - originalStart,
        characterRange: characterStart..<characterEnd
      )
    }

    func snippet(for match: OriginalMatch) -> String {
      let maximumLength = 120
      guard characters.count > maximumLength else {
        return characters.map(Self.singleLine).joined()
      }

      let windowLength = maximumLength - 2
      var start = max(0, match.characterRange.lowerBound - windowLength / 2)
      start = min(start, characters.count - windowLength)
      var end = start + windowLength

      if match.characterRange.lowerBound < start {
        start = match.characterRange.lowerBound
        end = min(characters.count, start + windowLength)
      }
      if match.characterRange.upperBound > end {
        end = min(characters.count, match.characterRange.upperBound)
        start = max(0, end - windowLength)
      }

      let content = characters[start..<end].map(Self.singleLine).joined()
      let leading = start > 0 ? "…" : ""
      let trailing = end < characters.count ? "…" : ""
      return leading + content + trailing
    }

    private static func singleLine(_ character: Character) -> String {
      character.isNewline ? " " : String(character)
    }
  }

  private static func match(
    for note: Note,
    query foldedQuery: String
  ) -> WorkspaceSearchResult? {
    let displayTitle = note.displayTitle
    let title = FoldedText(displayTitle)

    if let titleMatch = title.firstMatch(of: foldedQuery) {
      let score: Int
      if title.folded == foldedQuery {
        score = 4
      } else if title.folded.hasPrefix(foldedQuery) {
        score = 3
      } else {
        score = 2
      }

      let metadata = WorkspaceSearchMatch(
        field: .title,
        location: titleMatch.location,
        length: titleMatch.length
      )
      return WorkspaceSearchResult(
        noteID: note.id,
        displayTitle: displayTitle,
        snippet: title.snippet(for: titleMatch),
        match: metadata,
        score: score
      )
    }

    let body = FoldedText(note.body)
    guard let bodyMatch = body.firstMatch(of: foldedQuery) else { return nil }
    let metadata = WorkspaceSearchMatch(
      field: .body,
      location: bodyMatch.location,
      length: bodyMatch.length
    )
    return WorkspaceSearchResult(
      noteID: note.id,
      displayTitle: displayTitle,
      snippet: body.snippet(for: bodyMatch),
      match: metadata,
      score: 1
    )
  }

  private static func fold(_ value: String) -> String {
    value.folding(
      options: [.caseInsensitive, .diacriticInsensitive],
      locale: Locale(identifier: "en_US_POSIX")
    )
  }
}
