import Foundation

public struct NoteLink: Equatable, Sendable {
  public let targetNoteID: UUID
  public let label: String
  public let range: NSRange
  public let destinationRange: NSRange

  public init(
    targetNoteID: UUID,
    label: String,
    range: NSRange,
    destinationRange: NSRange
  ) {
    self.targetNoteID = targetNoteID
    self.label = label
    self.range = range
    self.destinationRange = destinationRange
  }
}

public enum NoteLinkFormatter {
  public static func escapeLabel(_ label: String) -> String {
    label
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "]", with: "\\]")
  }

  public static func markdown(label: String, targetNoteID: UUID) -> String {
    "[\(escapeLabel(label))](fleck://note/\(targetNoteID.uuidString))"
  }
}

public enum NoteLinkParser {
  private static let destinationPrefix = "fleck://note/"

  public static func links(in body: String) -> [NoteLink] {
    let source = body as NSString
    var links: [NoteLink] = []
    var cursor = 0

    while cursor < source.length {
      let openingRange = source.range(
        of: "[",
        options: [],
        range: NSRange(location: cursor, length: source.length - cursor)
      )
      guard openingRange.location != NSNotFound else { break }
      let opening = openingRange.location

      guard let closingLabel = nextUnescaped("]", in: source, after: opening + 1),
        closingLabel + 1 < source.length,
        source.character(at: closingLabel + 1) == 40,
        let closingDestination = nextUnescaped(")", in: source, after: closingLabel + 2)
      else {
        cursor = opening + 1
        continue
      }

      let destinationStart = closingLabel + 2
      let destinationRange = NSRange(
        location: destinationStart,
        length: closingDestination - destinationStart
      )
      let destination = source.substring(with: destinationRange)
      guard let targetNoteID = targetID(from: destination) else {
        cursor = opening + 1
        continue
      }

      let labelRange = NSRange(
        location: opening + 1,
        length: closingLabel - opening - 1
      )
      let link = NoteLink(
        targetNoteID: targetNoteID,
        label: decodeLabel(source.substring(with: labelRange)),
        range: NSRange(
          location: opening,
          length: closingDestination - opening + 1
        ),
        destinationRange: destinationRange
      )
      links.append(link)
      cursor = closingDestination + 1
    }

    return links
  }

  public static func link(atUTF16Location location: Int, in body: String) -> NoteLink? {
    guard location >= 0 else { return nil }
    return links(in: body).first { link in
      location >= link.range.location && location < NSMaxRange(link.range)
    }
  }

  public static func excerpt(around range: NSRange, in body: String, limit: Int) -> String {
    guard limit > 0, !body.isEmpty else { return "" }
    let source = body as NSString
    let bodyLength = source.length
    guard range.location != NSNotFound else { return "" }

    let start = min(max(0, range.location), bodyLength)
    let end = min(max(start, NSMaxRange(range)), bodyLength)
    let requested = NSRange(location: start, length: end - start)
    let composedRange = source.rangeOfComposedCharacterSequences(for: requested)
    let normalized = normalizedCharacters(in: body)
    guard !normalized.characters.isEmpty else { return "" }

    let matchingIndices = normalized.sourceOffsets.indices.filter { index in
      let offset = normalized.sourceOffsets[index]
      return offset >= composedRange.location && offset < NSMaxRange(composedRange)
    }
    let targetStart = matchingIndices.first ?? nearestIndex(
      to: composedRange.location,
      in: normalized.sourceOffsets
    )
    let link = links(in: body).first { NSIntersectionRange($0.range, composedRange).length > 0 }
    let labelOffset = link.map { min(max(0, $0.label.count / 2 + 1), max(0, normalized.characters.count - targetStart - 1)) } ?? 0
    let center = min(normalized.characters.count - 1, targetStart + labelOffset)

    var lower = max(0, center - limit / 2)
    var upper = min(normalized.characters.count, lower + limit)
    if upper - lower < limit {
      lower = max(0, upper - limit)
    }
    upper = min(normalized.characters.count, lower + limit)

    let prefix = lower > 0 ? "…" : ""
    let suffix = upper < normalized.characters.count ? "…" : ""
    return prefix + String(normalized.characters[lower..<upper]) + suffix
  }

  private static func targetID(from destination: String) -> UUID? {
    guard destination.hasPrefix(destinationPrefix) else { return nil }
    let uuidString = String(destination.dropFirst(destinationPrefix.count))
    guard uuidString.utf16.count == 36,
      uuidString.count == 36,
      !uuidString.contains(where: { $0.isWhitespace || "/%?#@:".contains($0) })
    else {
      return nil
    }
    return UUID(uuidString: uuidString)
  }

  private static func nextUnescaped(
    _ character: Character,
    in source: NSString,
    after start: Int
  ) -> Int? {
    let scalar = character == "]" ? 93 : 41
    guard start < source.length else { return nil }
    for index in start..<source.length where source.character(at: index) == scalar {
      var backslashCount = 0
      var previous = index - 1
      while previous >= 0, source.character(at: previous) == 92 {
        backslashCount += 1
        previous -= 1
      }
      if backslashCount.isMultiple(of: 2) { return index }
    }
    return nil
  }

  private static func decodeLabel(_ label: String) -> String {
    var decoded = ""
    var iterator = label.makeIterator()
    while let character = iterator.next() {
      guard character == "\\" else {
        decoded.append(character)
        continue
      }
      guard let escaped = iterator.next() else {
        decoded.append(character)
        continue
      }
      switch escaped {
      case "]", "\\": decoded.append(escaped)
      default:
        decoded.append(character)
        decoded.append(escaped)
      }
    }
    return decoded
  }

  private struct NormalizedCharacters {
    let characters: [Character]
    let sourceOffsets: [Int]
  }

  private static func normalizedCharacters(in body: String) -> NormalizedCharacters {
    var characters: [Character] = []
    var sourceOffsets: [Int] = []
    var sourceOffset = 0
    var hasWhitespace = false

    for character in body {
      let currentOffset = sourceOffset
      sourceOffset += character.utf16.count
      if character.isWhitespace {
        hasWhitespace = !characters.isEmpty
        continue
      }
      if hasWhitespace {
        characters.append(" ")
        sourceOffsets.append(currentOffset)
        hasWhitespace = false
      }
      characters.append(character)
      sourceOffsets.append(currentOffset)
    }
    return NormalizedCharacters(characters: characters, sourceOffsets: sourceOffsets)
  }

  private static func nearestIndex(to offset: Int, in offsets: [Int]) -> Int {
    offsets.firstIndex(where: { $0 >= offset }) ?? max(0, offsets.count - 1)
  }
}
