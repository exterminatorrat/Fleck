#if os(macOS)
import AppKit
import Foundation
import FleckCore

@MainActor
enum DictationSectionInsertion {
  struct Result: Equatable {
    let body: String
    let richTextRTF: Data
    let location: Int
    let length: Int
    let digest: String
  }

  struct RemovalResult: Equatable {
    let body: String
    let richTextRTF: Data
  }

  private struct HeadingRecord: Hashable {
    let location: Int
    let title: String
    let level: Int
  }

  private struct Fence {
    let marker: Character
    let length: Int
  }

  private enum Failure: Swift.Error {
    case invalidBody
    case invalidInsertionOffset
    case invalidRemovalRange
    case digestMismatch
    case codecMismatch
    case emptyInsertion
  }

  static func headings(
    in note: Note,
    defaults: NoteTextAppendDefaults
  ) -> [DictationRoutingHeading] {
    let attributed: NSAttributedString
    if let rtf = note.richTextRTF {
      guard let decoded = try? NoteRichTextCodec.decode(rtf),
        decoded.string.utf8.elementsEqual(note.body.utf8)
      else {
        return []
      }
      attributed = decoded
    } else {
      attributed = NSAttributedString(string: note.body, attributes: defaults.attributes)
    }

    var records = markdownHeadings(in: note.body)
    let markdownLocations = Set(records.map(\.location))
    records.append(contentsOf: styledHeadings(
      in: attributed,
      defaults: defaults,
      excluding: markdownLocations
    ))
    let headings = Array(Set(records)).sorted {
      if $0.location != $1.location { return $0.location < $1.location }
      if $0.level != $1.level { return $0.level < $1.level }
      return $0.title < $1.title
    }

    return headings.enumerated().map { index, heading in
      let insertionOffset = headings.dropFirst(index + 1)
        .first(where: { $0.level <= heading.level })?.location
        ?? note.body.utf16.count
      return DictationRoutingHeading(
        id: DictationFilingPlan.headingID(
          location: heading.location,
          title: heading.title,
          level: heading.level
        ),
        title: heading.title,
        level: heading.level,
        insertionUTF16Offset: insertionOffset
      )
    }
  }

  static func inserting(
    _ text: String,
    into note: Note,
    atUTF16Offset offset: Int,
    defaults: NoteTextAppendDefaults
  ) throws -> Result {
    guard !text.isEmpty else { throw Failure.emptyInsertion }
    let attributed = try attributedText(for: note, defaults: defaults)
    guard isParagraphBoundary(offset, in: note.body) else {
      throw Failure.invalidInsertionOffset
    }

    let source = note.body as NSString
    let left = source.substring(to: offset)
    let right = source.substring(from: offset)
    let prefix = separatorBefore(text, after: left)
    let suffix = separatorAfter(text, before: right)
    let insertion = prefix + text + suffix
    let updated = NSMutableAttributedString(attributedString: attributed)
    updated.insert(
      NSAttributedString(string: insertion, attributes: defaults.attributes),
      at: offset
    )
    let body = updated.string
    let insertionRange = NSRange(location: offset, length: insertion.utf16.count)
    let insertedText = (body as NSString).substring(with: insertionRange)
    let rtf = try NoteRichTextCodec.encode(updated)
    guard try NoteRichTextCodec.decode(rtf).string.utf8.elementsEqual(body.utf8) else {
      throw Failure.codecMismatch
    }
    return Result(
      body: body,
      richTextRTF: rtf,
      location: insertionRange.location,
      length: insertionRange.length,
      digest: DictationFilingPlan.digest(insertedText)
    )
  }

  static func removing(
    range: NSRange,
    digest: String,
    from note: Note,
    defaults: NoteTextAppendDefaults
  ) throws -> RemovalResult {
    let attributed = try attributedText(for: note, defaults: defaults)
    guard range.location >= 0,
      range.length > 0,
      range.location <= attributed.length,
      range.length <= attributed.length - range.location,
      isCharacterBoundary(range.location, in: note.body),
      isCharacterBoundary(NSMaxRange(range), in: note.body)
    else { throw Failure.invalidRemovalRange }

    let removedText = (note.body as NSString).substring(with: range)
    guard DictationFilingPlan.digest(removedText) == digest else {
      throw Failure.digestMismatch
    }
    let updated = NSMutableAttributedString(attributedString: attributed)
    updated.deleteCharacters(in: range)
    let body = updated.string
    let rtf = try NoteRichTextCodec.encode(updated)
    guard try NoteRichTextCodec.decode(rtf).string.utf8.elementsEqual(body.utf8) else {
      throw Failure.codecMismatch
    }
    return RemovalResult(body: body, richTextRTF: rtf)
  }

  private static func attributedText(
    for note: Note,
    defaults: NoteTextAppendDefaults
  ) throws -> NSAttributedString {
    guard let rtf = note.richTextRTF else {
      return NSAttributedString(string: note.body, attributes: defaults.attributes)
    }
    let attributed = try NoteRichTextCodec.decode(rtf)
    guard attributed.string.utf8.elementsEqual(note.body.utf8) else {
      throw Failure.invalidBody
    }
    return attributed
  }

  private static func markdownHeadings(in body: String) -> [HeadingRecord] {
    let source = body as NSString
    var records: [HeadingRecord] = []
    var fence: Fence?
    var previousLine: (location: Int, text: String)?
    var location = 0
    while location < source.length {
      var lineStart = 0
      var lineEnd = 0
      var contentsEnd = 0
      source.getLineStart(
        &lineStart,
        end: &lineEnd,
        contentsEnd: &contentsEnd,
        for: NSRange(location: location, length: 0)
      )
      guard lineEnd > location else { break }
      let line = source.substring(
        with: NSRange(location: lineStart, length: contentsEnd - lineStart)
      )
      if let activeFence = fence {
        if let currentFence = fenceRun(in: line),
          currentFence.marker == activeFence.marker,
          currentFence.length >= activeFence.length,
          fenceRemainderIsWhitespace(
            in: line,
            marker: activeFence.marker,
            run: currentFence.length
          )
        {
          fence = nil
          previousLine = nil
        }
      } else if let openingFence = openingFence(in: line) {
        fence = openingFence
        previousLine = nil
      } else if let heading = markdownHeading(in: line) {
        records.append(HeadingRecord(
          location: lineStart,
          title: heading.title,
          level: heading.level
        ))
        previousLine = (lineStart, line)
      } else if let level = setextHeadingLevel(in: line) {
        if let previousLine,
          let title = nonemptyTrimmed(previousLine.text),
          markdownHeading(in: previousLine.text) == nil
        {
          records.append(HeadingRecord(
            location: previousLine.location,
            title: title,
            level: level
          ))
        }
        previousLine = nil
      } else {
        previousLine = (lineStart, line)
      }
      location = lineEnd
    }
    return records
  }

  private static func markdownHeading(in line: String) -> (title: String, level: Int)? {
    let characters = Array(line)
    var position = 0
    while position < characters.count, position < 3, characters[position] == " " {
      position += 1
    }
    var level = 0
    while position < characters.count, characters[position] == "#" {
      level += 1
      position += 1
    }
    guard (1...6).contains(level),
      position == characters.count || characters[position].isWhitespace
    else { return nil }

    var title = String(characters[position...]).trimmingCharacters(in: .whitespaces)
    guard !title.isEmpty else { return nil }
    var closingMarkers = title.endIndex
    while closingMarkers > title.startIndex, title[title.index(before: closingMarkers)] == "#" {
      closingMarkers = title.index(before: closingMarkers)
    }
    if closingMarkers < title.endIndex,
      closingMarkers > title.startIndex,
      title[title.index(before: closingMarkers)].isWhitespace
    {
      title = String(title[..<title.index(before: closingMarkers)])
        .trimmingCharacters(in: .whitespaces)
    }
    guard !title.isEmpty else { return nil }
    return (title, level)
  }

  private static func setextHeadingLevel(in line: String) -> Int? {
    let characters = Array(line)
    var position = 0
    while position < characters.count, position < 3, characters[position] == " " {
      position += 1
    }
    guard position < characters.count else { return nil }
    let marker = characters[position]
    let content = String(characters[position...]).trimmingCharacters(in: .whitespaces)
    let markers = Array(content)
    guard (marker == "=" || marker == "-"),
      markers.count >= 3,
      markers.allSatisfy({ $0 == marker })
    else { return nil }
    return marker == "=" ? 1 : 2
  }

  private static func nonemptyTrimmed(_ text: String) -> String? {
    let result = text.trimmingCharacters(in: .whitespaces)
    return result.isEmpty ? nil : result
  }

  private static func fenceRun(in line: String) -> Fence? {
    let characters = Array(line)
    var position = 0
    while position < characters.count, position < 3, characters[position] == " " {
      position += 1
    }
    guard position < characters.count,
      characters[position] == "`" || characters[position] == "~"
    else { return nil }
    let marker = characters[position]
    let start = position
    while position < characters.count, characters[position] == marker { position += 1 }
    let length = position - start
    guard length >= 3 else { return nil }
    return Fence(marker: marker, length: length)
  }

  private static func openingFence(in line: String) -> Fence? {
    guard let fence = fenceRun(in: line) else { return nil }
    guard fence.marker == "`" else { return fence }
    let characters = Array(line)
    var position = 0
    while position < characters.count, position < 3, characters[position] == " " {
      position += 1
    }
    position += fence.length
    guard !characters[position...].contains("`") else { return nil }
    return fence
  }

  private static func fenceRemainderIsWhitespace(
    in line: String,
    marker: Character,
    run: Int
  ) -> Bool {
    let characters = Array(line)
    var position = 0
    while position < characters.count, position < 3, characters[position] == " " {
      position += 1
    }
    while position < characters.count, characters[position] == marker {
      position += 1
    }
    guard position >= run else { return false }
    return characters[position...].allSatisfy(\.isWhitespace)
  }

  private static func styledHeadings(
    in attributed: NSAttributedString,
    defaults: NoteTextAppendDefaults,
    excluding excludedLocations: Set<Int>
  ) -> [HeadingRecord] {
    let source = attributed.string as NSString
    var records: [HeadingRecord] = []
    var location = 0
    while location < source.length {
      var paragraphStart = 0
      var paragraphEnd = 0
      var contentsEnd = 0
      source.getParagraphStart(
        &paragraphStart,
        end: &paragraphEnd,
        contentsEnd: &contentsEnd,
        for: NSRange(location: location, length: 0)
      )
      guard paragraphEnd > location else { break }
      let title = source.substring(
        with: NSRange(location: paragraphStart, length: contentsEnd - paragraphStart)
      ).trimmingCharacters(in: .whitespacesAndNewlines)
      if !title.isEmpty, !excludedLocations.contains(paragraphStart),
        let font = attributed.attribute(.font, at: paragraphStart, effectiveRange: nil) as? NSFont,
        let paragraph = attributed.attribute(
          .paragraphStyle,
          at: paragraphStart,
          effectiveRange: nil
        ) as? NSParagraphStyle
      {
        let traits = NSFontManager.shared.traits(of: font)
        let titleRange = NSRange(location: paragraphStart, length: contentsEnd - paragraphStart)
        let styles: [(level: Int, scale: CGFloat, before: CGFloat, after: CGFloat)] = [
          (1, 1.75, 12, 8),
          (2, 1.5, 10, 6),
          (3, 1.25, 8, 4),
        ]
        if let style = styles.first(where: { style in
          abs(font.pointSize - defaults.font.pointSize * style.scale) < 0.01
            && traits.contains(.boldFontMask)
            && abs(paragraph.paragraphSpacingBefore - style.before) < 0.01
            && abs(paragraph.paragraphSpacing - style.after) < 0.01
            && paragraphFontsMatch(
              attributed,
              in: titleRange,
              pointSize: defaults.font.pointSize * style.scale
            )
        }) {
          records.append(HeadingRecord(
            location: paragraphStart,
            title: title,
            level: style.level
          ))
        }
      }
      location = paragraphEnd
    }
    return records
  }

  private static func separatorBefore(_ text: String, after left: String) -> String {
    guard !left.isEmpty else { return "" }
    let existing = trailingLineBreakCount(in: left) + leadingLineBreakCount(in: text)
    return String(repeating: "\n", count: max(0, 2 - existing))
  }

  private static func separatorAfter(_ text: String, before right: String) -> String {
    guard !right.isEmpty else { return "" }
    let existing = trailingLineBreakCount(in: text) + leadingLineBreakCount(in: right)
    return String(repeating: "\n", count: max(0, 2 - existing))
  }

  private static func trailingLineBreakCount(in text: String) -> Int {
    text.reversed().prefix(while: isLineBreak).count
  }

  private static func leadingLineBreakCount(in text: String) -> Int {
    text.prefix(while: isLineBreak).count
  }

  private static func isLineBreak(_ character: Character) -> Bool {
    character.unicodeScalars.allSatisfy(CharacterSet.newlines.contains)
  }

  private static func paragraphFontsMatch(
    _ attributed: NSAttributedString,
    in range: NSRange,
    pointSize: CGFloat
  ) -> Bool {
    var foundFont = false
    var matches = true
    attributed.enumerateAttribute(.font, in: range) { value, _, stop in
      guard let font = value as? NSFont,
        abs(font.pointSize - pointSize) < 0.01,
        NSFontManager.shared.traits(of: font).contains(.boldFontMask)
      else {
        matches = false
        stop.pointee = true
        return
      }
      foundFont = true
    }
    return foundFont && matches
  }

  private static func isParagraphBoundary(_ offset: Int, in text: String) -> Bool {
    guard isCharacterBoundary(offset, in: text) else { return false }
    var index = text.startIndex
    while index.utf16Offset(in: text) < offset { index = text.index(after: index) }
    if index == text.startIndex || index == text.endIndex { return true }
    return isLineBreak(text[text.index(before: index)])
      || isLineBreak(text[index])
  }

  private static func isCharacterBoundary(_ offset: Int, in text: String) -> Bool {
    guard offset >= 0, offset <= text.utf16.count else { return false }
    return text.indices.contains { $0.utf16Offset(in: text) == offset }
      || text.endIndex.utf16Offset(in: text) == offset
  }
}
#endif
