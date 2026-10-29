import Foundation
import FleckCore

struct DictationFilingPlan: Equatable, Sendable {
  private struct Chunk: Equatable, Sendable {
    let text: String
    let location: Int
    let length: Int
  }

  struct Fragment: Equatable, Sendable {
    let text: String
    let destinationID: UUID
  }

  struct Output: Equatable, Sendable {
    let destinationID: UUID
    let contentRevision: UInt64
    let bodyDigest: String
    let heading: DictationRoutingHeading?
    let text: String
  }

  private struct OutputKey: Hashable {
    let destinationID: UUID
    let headingID: String?
  }

  private struct Coverage: Equatable, Sendable {
    let chunkIndex: Int
    let outputIndex: Int
    let destinationID: UUID
    let headingID: String?
  }

  private struct CandidateSnapshot: Equatable, Sendable {
    let destinationID: UUID
    let contentRevision: UInt64
    let bodyDigest: String
    let headings: [DictationRoutingHeading]
  }

  private static let maximumInputBytes = 16 * 1024
  private static let maximumChunkCount = 8
  private static let newlineScalars = CharacterSet.newlines
  private static let sentenceTerminals = CharacterSet(charactersIn: ".!?。！？؟")
  private static let lowInformationWords: Set<String> = [
    "a", "an", "and", "are", "as", "at", "be", "by", "for", "from", "in", "into",
    "is", "it", "of", "on", "or", "the", "to", "with",
  ]

  let text: String
  let outputs: [Output]
  private let coverage: [Coverage]
  private let candidates: [CandidateSnapshot]
  private let inboxID: UUID?

  init?(
    text: String,
    fragments: [Fragment],
    candidates: [DictationRoutingCandidate],
    inboxID: UUID? = nil
  ) {
    guard let chunks = Self.hostChunkRecords(in: text),
      chunks.count == fragments.count,
      Set(candidates.map { $0.destination.noteID }).count == candidates.count
    else { return nil }

    let candidatesByID = Dictionary(
      uniqueKeysWithValues: candidates.map { ($0.destination.noteID, $0) }
    )
    let destinationIDs = Set(fragments.map(\.destinationID))
    guard !destinationIDs.isEmpty,
      inboxID.map({ !destinationIDs.contains($0) }) ?? true
    else { return nil }

    var outputs: [Output] = []
    var outputIndexes: [OutputKey: Int] = [:]
    var coverage: [Coverage] = []
    var usedDestinationIDs: [UUID] = []

    for (index, pair) in zip(chunks, fragments).enumerated() {
      let (chunk, fragment) = pair
      guard Self.exactlyEqual(chunk.text, fragment.text),
        let candidate = candidatesByID[fragment.destinationID],
        candidate.destination.noteID != inboxID,
        Self.headingsAreValid(candidate.headings, body: candidate.semanticContext)
      else { return nil }

      let heading = Self.uniqueHeading(for: chunk.text, in: candidate.headings)

      let key = OutputKey(
        destinationID: fragment.destinationID,
        headingID: heading?.id
      )
      let outputIndex: Int
      if let existingIndex = outputIndexes[key] {
        let existing = outputs[existingIndex]
        outputs[existingIndex] = Output(
          destinationID: existing.destinationID,
          contentRevision: existing.contentRevision,
          bodyDigest: existing.bodyDigest,
          heading: existing.heading,
          text: existing.text + chunk.text
        )
        outputIndex = existingIndex
      } else {
        outputIndex = outputs.count
        outputIndexes[key] = outputIndex
        outputs.append(Output(
          destinationID: candidate.destination.noteID,
          contentRevision: candidate.contentRevision,
          bodyDigest: Self.digest(candidate.semanticContext),
          heading: heading,
          text: chunk.text
        ))
      }
      coverage.append(Coverage(
        chunkIndex: index,
        outputIndex: outputIndex,
        destinationID: fragment.destinationID,
        headingID: heading?.id
      ))
      if !usedDestinationIDs.contains(candidate.destination.noteID) {
        usedDestinationIDs.append(candidate.destination.noteID)
      }
    }

    if destinationIDs.count == 1, !coverage.contains(where: { $0.headingID != nil }) {
      return nil
    }

    self.text = text
    self.outputs = outputs
    self.coverage = coverage
    self.candidates = usedDestinationIDs.compactMap { destinationID in
      guard let candidate = candidatesByID[destinationID] else { return nil }
      return CandidateSnapshot(
        destinationID: destinationID,
        contentRevision: candidate.contentRevision,
        bodyDigest: Self.digest(candidate.semanticContext),
        headings: candidate.headings
      )
    }
    self.inboxID = inboxID
    guard isValid(against: candidates) else { return nil }
  }

  static func make(
    text: String,
    fragments: [Fragment],
    candidates: [DictationRoutingCandidate],
    inboxID: UUID? = nil
  ) -> Self? {
    Self(text: text, fragments: fragments, candidates: candidates, inboxID: inboxID)
  }

  func isValid(against candidates: [DictationRoutingCandidate]) -> Bool {
    guard let chunks = Self.hostChunkRecords(in: text),
      chunks.count == coverage.count,
      !outputs.isEmpty,
      Set(candidates.map { $0.destination.noteID }).count == candidates.count
    else { return false }

    let candidatesByID = Dictionary(
      uniqueKeysWithValues: candidates.map { ($0.destination.noteID, $0) }
    )
    var rebuiltOutputs = Array(repeating: "", count: outputs.count)
    var expectedLocation = 0
    for (index, pair) in zip(chunks, coverage).enumerated() {
      let (chunk, assignment) = pair
      guard assignment.chunkIndex == index,
        assignment.outputIndex >= 0,
        assignment.outputIndex < outputs.count,
        chunk.location == expectedLocation,
        chunk.length == chunk.text.utf16.count,
        outputs[assignment.outputIndex].destinationID == assignment.destinationID,
        outputs[assignment.outputIndex].heading?.id == assignment.headingID,
        Self.exactlyEqual(
          (text as NSString).substring(
            with: NSRange(location: chunk.location, length: chunk.length)
          ),
          chunk.text
        )
      else { return false }
      expectedLocation += chunk.length
      rebuiltOutputs[assignment.outputIndex] += chunk.text
    }
    guard expectedLocation == text.utf16.count,
      rebuiltOutputs.count == outputs.count,
      zip(rebuiltOutputs, outputs).allSatisfy({ Self.exactlyEqual($0.0, $0.1.text) })
    else { return false }

    for snapshot in self.candidates {
      guard let candidate = candidatesByID[snapshot.destinationID],
        candidate.destination.noteID != inboxID,
        candidate.contentRevision == snapshot.contentRevision,
        Self.digest(candidate.semanticContext) == snapshot.bodyDigest,
        Self.headingsExactlyEqual(candidate.headings, snapshot.headings),
        Self.headingsAreValid(candidate.headings, body: candidate.semanticContext)
      else { return false }
    }

    for output in outputs {
      guard output.destinationID != inboxID,
        let candidate = candidatesByID[output.destinationID],
        let snapshot = self.candidates.first(where: {
          $0.destinationID == output.destinationID
        }),
        output.contentRevision == candidate.contentRevision,
        output.contentRevision == snapshot.contentRevision,
        output.bodyDigest == Self.digest(candidate.semanticContext),
        output.bodyDigest == snapshot.bodyDigest,
        output.heading.map({ heading in
          candidate.headings.filter { Self.headingExactlyEqual($0, heading) }.count == 1
        }) ?? true
      else { return false }
    }
    return true
  }

  static func digest(_ text: String) -> String {
    DictationFilingLedger.digest(text)
  }

  static func headingID(location: Int, title: String, level: Int) -> String {
    "\(location):\(level):\(title)"
  }

  private static func exactlyEqual(_ lhs: String, _ rhs: String) -> Bool {
    lhs.utf8.elementsEqual(rhs.utf8)
  }

  private static func headingExactlyEqual(
    _ lhs: DictationRoutingHeading,
    _ rhs: DictationRoutingHeading
  ) -> Bool {
    exactlyEqual(lhs.id, rhs.id)
      && exactlyEqual(lhs.title, rhs.title)
      && lhs.level == rhs.level
      && lhs.insertionUTF16Offset == rhs.insertionUTF16Offset
  }

  private static func headingsExactlyEqual(
    _ lhs: [DictationRoutingHeading],
    _ rhs: [DictationRoutingHeading]
  ) -> Bool {
    lhs.count == rhs.count
      && zip(lhs, rhs).allSatisfy { headingExactlyEqual($0.0, $0.1) }
  }

  static func hostChunks(in text: String) -> [String]? {
    hostChunkRecords(in: text)?.map(\.text)
  }

  private static func hostChunkRecords(in text: String) -> [Chunk]? {
    guard !text.isEmpty, text.utf8.count <= maximumInputBytes else { return nil }

    var naturalBoundaries = [0]
    var index = text.startIndex
    while index < text.endIndex {
      let character = text[index]
      let next = text.index(after: index)
      if character.unicodeScalars.allSatisfy({ newlineScalars.contains($0) }) {
        naturalBoundaries.append(next.utf16Offset(in: text))
        index = next
        continue
      }
      if character.unicodeScalars.contains(where: { sentenceTerminals.contains($0) }),
        next < text.endIndex, text[next].isWhitespace
      {
        var boundary = next
        while boundary < text.endIndex, text[boundary].isWhitespace {
          boundary = text.index(after: boundary)
        }
        naturalBoundaries.append(boundary.utf16Offset(in: text))
        index = boundary
        continue
      }
      index = next
    }

    let totalLength = text.utf16.count
    if naturalBoundaries.last != totalLength { naturalBoundaries.append(totalLength) }
    var uniqueBoundaries = [naturalBoundaries[0]]
    for boundary in naturalBoundaries.dropFirst() {
      if let lastBoundary = uniqueBoundaries.last, boundary > lastBoundary {
        uniqueBoundaries.append(boundary)
      }
    }
    let source = text as NSString
    var segments: [Chunk] = []
    for index in 0..<(uniqueBoundaries.count - 1) {
      let location = uniqueBoundaries[index]
      let end = uniqueBoundaries[index + 1]
      let range = NSRange(location: location, length: end - location)
      segments.append(Chunk(
        text: source.substring(with: range),
        location: location,
        length: range.length
      ))
    }

    var mergedSegments: [Chunk] = []
    var leadingWhitespace: Chunk?
    for segment in segments {
      if segment.text.allSatisfy(\.isWhitespace) {
        if let previous = mergedSegments.popLast() {
          mergedSegments.append(Chunk(
            text: previous.text + segment.text,
            location: previous.location,
            length: previous.length + segment.length
          ))
        } else if let pending = leadingWhitespace {
          leadingWhitespace = Chunk(
            text: pending.text + segment.text,
            location: pending.location,
            length: pending.length + segment.length
          )
        } else {
          leadingWhitespace = segment
        }
      } else if let pending = leadingWhitespace {
        mergedSegments.append(Chunk(
          text: pending.text + segment.text,
          location: pending.location,
          length: pending.length + segment.length
        ))
        leadingWhitespace = nil
      } else {
        mergedSegments.append(segment)
      }
    }
    if let pending = leadingWhitespace {
      guard let previous = mergedSegments.popLast() else { return nil }
      mergedSegments.append(Chunk(
        text: previous.text + pending.text,
        location: previous.location,
        length: previous.length + pending.length
      ))
    }
    let segmentCount = mergedSegments.count
    guard segmentCount > 0 else { return nil }

    let chunkCount = min(maximumChunkCount, segmentCount)
    return (0..<chunkCount).map { chunkIndex in
      let firstSegment = chunkIndex * segmentCount / chunkCount
      let afterLastSegment = (chunkIndex + 1) * segmentCount / chunkCount
      let first = mergedSegments[firstSegment]
      let last = mergedSegments[afterLastSegment - 1]
      let range = NSRange(
        location: first.location,
        length: last.location + last.length - first.location
      )
      return Chunk(
        text: source.substring(with: range),
        location: first.location,
        length: range.length
      )
    }
  }

  private static func headingsAreValid(
    _ headings: [DictationRoutingHeading],
    body: String
  ) -> Bool {
    let ids = headings.map(\.id)
    guard Set(ids).count == ids.count else { return false }
    return headings.allSatisfy { heading in
      let location = headingLocation(from: heading.id)
      return !heading.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && (1...6).contains(heading.level)
        && location >= 0
        && location < body.utf16.count
        && isParagraphBoundary(location, in: body)
        && heading.insertionUTF16Offset >= 0
        && heading.insertionUTF16Offset >= location
        && heading.insertionUTF16Offset <= body.utf16.count
        && exactlyEqual(
          heading.id,
          headingID(location: location, title: heading.title, level: heading.level)
        )
        && headingMatches(heading, at: location, in: body)
        && isParagraphBoundary(heading.insertionUTF16Offset, in: body)
    }
  }

  private static func headingLocation(from id: String) -> Int {
    guard let separator = id.firstIndex(of: ":"),
      let location = Int(id[..<separator])
    else { return -1 }
    return location
  }

  private static func headingMatches(
    _ heading: DictationRoutingHeading,
    at location: Int,
    in body: String
  ) -> Bool {
    let source = body as NSString
    var lineStart = 0
    var lineEnd = 0
    var contentsEnd = 0
    source.getLineStart(
      &lineStart,
      end: &lineEnd,
      contentsEnd: &contentsEnd,
      for: NSRange(location: location, length: 0)
    )
    guard lineStart == location, lineEnd > lineStart else { return false }
    let line = source.substring(
      with: NSRange(location: lineStart, length: contentsEnd - lineStart)
    ).trimmingCharacters(in: .whitespaces)
    if exactlyEqual(line, heading.title) { return true }

    let characters = Array(line)
    var position = 0
    while position < characters.count, characters[position] == "#" { position += 1 }
    guard position == heading.level,
      position == characters.count || characters[position].isWhitespace
    else { return false }
    var title = String(characters[position...]).trimmingCharacters(in: .whitespaces)
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
    return exactlyEqual(title, heading.title)
  }

  private static func isParagraphBoundary(_ offset: Int, in text: String) -> Bool {
    guard offset >= 0, offset <= text.utf16.count else { return false }
    var index = text.startIndex
    while true {
      guard index.utf16Offset(in: text) != offset else {
        if index == text.startIndex || index == text.endIndex { return true }
        let previous = text[text.index(before: index)]
        return previous.unicodeScalars.allSatisfy({ newlineScalars.contains($0) })
          || text[index].unicodeScalars.allSatisfy({ newlineScalars.contains($0) })
      }
      guard index < text.endIndex else { return false }
      index = text.index(after: index)
    }
  }

  private static func uniqueHeading(
    for text: String,
    in headings: [DictationRoutingHeading]
  ) -> DictationRoutingHeading? {
    let textWords = lexemes(in: text)
    guard !textWords.isEmpty, !headings.isEmpty else { return nil }
    let exactMatches = headings.filter { heading in
      let titleWords = lexemes(in: heading.title)
      return !titleWords.isEmpty && contains(titleWords, in: textWords)
    }
    if exactMatches.count == 1 { return exactMatches[0] }
    if exactMatches.count > 1 { return nil }

    let textTerms = Set(textWords.filter { !lowInformationWords.contains($0) })
    let scored = headings.compactMap { heading -> (DictationRoutingHeading, Double)? in
      let titleTerms = Set(lexemes(in: heading.title).filter { !lowInformationWords.contains($0) })
      let sharedTerms = textTerms.intersection(titleTerms).count
      guard sharedTerms >= 2,
        sharedTerms * 2 >= titleTerms.count
      else { return nil }
      return (heading, Double(sharedTerms) / Double(titleTerms.count))
    }
    guard let bestScore = scored.map(\.1).max() else { return nil }
    let best = scored.filter { abs($0.1 - bestScore) < 0.000_001 }
    return best.count == 1 ? best[0].0 : nil
  }

  private static func lexemes(in text: String) -> [String] {
    text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
  }

  private static func contains(_ phrase: [String], in words: [String]) -> Bool {
    guard phrase.count <= words.count else { return false }
    return (0...(words.count - phrase.count)).contains { start in
      words[start..<(start + phrase.count)].elementsEqual(phrase)
    }
  }
}
