import Foundation

struct CachedNoteRoutingMatch: Equatable, Sendable {
  let candidate: DictationRoutingCandidate
  let excerpt: String
  let score: Int
  let exactTermMatches: Int
}

struct CachedNoteRoutingResourceUsage: Equatable, Sendable {
  let noteCount: Int
  let passageCount: Int
  let excerptUTF8Count: Int
  let exactPostingCount: Int
  let trigramPostingCount: Int
  let completenessScanUTF8Count: Int
}

actor CachedNoteRoutingIndex {
  static let maximumNoteCount = 256
  static let maximumPassagesPerNote = 8
  static let maximumPassageCount = maximumNoteCount * maximumPassagesPerNote
  static let maximumExcerptUTF8Count = maximumPassageCount * maximumExcerptUTF8PerPassage
  static let maximumExactPostingCount =
    maximumNoteCount * maximumTitleTermCount
      + maximumPassageCount * maximumPassageTermCount
  static let maximumTrigramPostingCount =
    maximumNoteCount * maximumTitleTrigramCount
      + maximumPassageCount * maximumPassageTrigramCount
  static let maximumCompletenessScanUTF8PerCandidate = 32 * 1_024
  static let maximumCompletenessScanUTF8Count = 128 * 1_024

  private static let maximumExcerptUTF8PerPassage = 2_048
  private static let maximumTitleUTF8Count = 2_048
  private static let maximumTitleTermCount = 32
  private static let maximumPassageTermCount = 96
  private static let maximumTitleTrigramCount = 256
  private static let maximumPassageTrigramCount = 512

  private struct PassageID: Hashable {
    let noteID: UUID
    let ordinal: Int
  }

  private struct Passage {
    let excerpt: String
    let terms: Set<String>
    let trigrams: Set<String>
  }

  private struct Note {
    let noteID: UUID
    let destinationTitle: String
    let contentRevision: UInt64
    let titleTerms: Set<String>
    let titleTrigrams: Set<String>
    let passageIDs: [PassageID]
    let requiresCompletenessGuard: Bool
  }

  private struct ScoredPassage {
    let match: CachedNoteRoutingMatch
    let ordinal: Int
  }

  private struct BoundedFeatureSet {
    let values: Set<String>
    let wasTruncated: Bool
  }

  private enum CompletenessScanResult: Equatable {
    case noEvidence
    case evidence
    case exhausted
  }

  private var notes: [UUID: Note] = [:]
  private var passages: [PassageID: Passage] = [:]
  private var exactPostings: [String: Set<PassageID>] = [:]
  private var trigramPostings: [String: Set<PassageID>] = [:]
  private var lastCompletenessScanUTF8Count = 0

  func retrieve(
    transcript: String,
    candidates: [DictationRoutingCandidate],
    limit: Int = 6
  ) -> [CachedNoteRoutingMatch] {
    lastCompletenessScanUTF8Count = 0
    guard !Task.isCancelled, limit > 0 else { return [] }
    let queryTerms = Self.meaningfulTerms(in: transcript)
    guard !queryTerms.isEmpty else { return [] }

    let candidateIDs = candidates.map(\.destination.noteID)
    guard Set(candidateIDs).count == candidates.count else { return [] }
    let boundedCandidates = candidates
      .sorted { $0.destination.noteID.uuidString < $1.destination.noteID.uuidString }
      .prefix(Self.maximumNoteCount)
    let candidatesByID = Dictionary(uniqueKeysWithValues: boundedCandidates.map {
      ($0.destination.noteID, $0)
    })

    guard synchronize(Array(boundedCandidates)), !Task.isCancelled else { return [] }

    let queryTrigrams = Self.trigrams(for: queryTerms)
    var matchingPassages = Set<PassageID>()
    for term in queryTerms {
      matchingPassages.formUnion(exactPostings[term] ?? [])
    }
    for trigram in queryTrigrams {
      matchingPassages.formUnion(trigramPostings[trigram] ?? [])
    }
    guard !matchingPassages.isEmpty else { return [] }

    var bestByNote: [UUID: ScoredPassage] = [:]
    for passageID in matchingPassages {
      guard !Task.isCancelled else { return [] }
      guard let candidate = candidatesByID[passageID.noteID],
            let note = notes[passageID.noteID],
            let passage = passages[passageID] else {
        continue
      }
      let titleExact = queryTerms.intersection(note.titleTerms)
      let bodyExact = queryTerms.intersection(passage.terms).subtracting(titleExact)
      let exactMatches = titleExact.union(bodyExact).count
      var score = 0
      for term in titleExact {
        score += 120 * rarity(of: term, in: exactPostings)
      }
      for term in bodyExact {
        score += 80 * rarity(of: term, in: exactPostings)
      }
      for trigram in queryTrigrams.intersection(note.titleTrigrams.union(passage.trigrams)) {
        score += rarity(of: trigram, in: trigramPostings)
      }
      guard score > 0 else { continue }

      let scored = ScoredPassage(
        match: CachedNoteRoutingMatch(
          candidate: candidate,
          excerpt: passage.excerpt,
          score: score,
          exactTermMatches: exactMatches
        ),
        ordinal: passageID.ordinal
      )
      if let current = bestByNote[passageID.noteID] {
        if Self.precedes(scored, current) { bestByNote[passageID.noteID] = scored }
      } else {
        bestByNote[passageID.noteID] = scored
      }
    }

    guard !Task.isCancelled else { return [] }
    guard !bestByNote.isEmpty else { return [] }
    var remainingCompletenessScanUTF8Count = Self.maximumCompletenessScanUTF8Count
    for candidate in candidates {
      guard !Task.isCancelled else { return [] }
      if let note = notes[candidate.destination.noteID], !note.requiresCompletenessGuard {
        continue
      }
      let scanResult = scanForUnindexedQueryEvidence(
        in: candidate,
        queryTerms: queryTerms,
        queryTrigrams: queryTrigrams,
        remainingGlobalUTF8Count: &remainingCompletenessScanUTF8Count
      )
      if scanResult != .noEvidence {
        return []
      }
    }
    guard !Task.isCancelled else { return [] }
    return bestByNote.values
      .sorted { lhs, rhs in
        if lhs.match.score != rhs.match.score { return lhs.match.score > rhs.match.score }
        if lhs.match.exactTermMatches != rhs.match.exactTermMatches {
          return lhs.match.exactTermMatches > rhs.match.exactTermMatches
        }
        let lhsTitle = Self.normalizedWhitespace(lhs.match.candidate.destination.title).lowercased()
        let rhsTitle = Self.normalizedWhitespace(rhs.match.candidate.destination.title).lowercased()
        if lhsTitle != rhsTitle { return lhsTitle < rhsTitle }
        return lhs.match.candidate.destination.noteID.uuidString.lowercased()
          < rhs.match.candidate.destination.noteID.uuidString.lowercased()
      }
      .prefix(limit)
      .map(\.match)
  }

  func resourceUsage() -> CachedNoteRoutingResourceUsage {
    CachedNoteRoutingResourceUsage(
      noteCount: notes.count,
      passageCount: passages.count,
      excerptUTF8Count: passages.values.reduce(0) { $0 + $1.excerpt.utf8.count },
      exactPostingCount: exactPostings.values.reduce(0) { $0 + $1.count },
      trigramPostingCount: trigramPostings.values.reduce(0) { $0 + $1.count },
      completenessScanUTF8Count: lastCompletenessScanUTF8Count
    )
  }

  private func synchronize(_ candidates: [DictationRoutingCandidate]) -> Bool {
    let currentIDs = Set(candidates.map(\.destination.noteID))
    var replacements: [(note: Note, passages: [Passage])] = []
    for candidate in candidates {
      guard !Task.isCancelled else { return false }
      let cached = notes[candidate.destination.noteID]
      let boundedTitle = Self.boundedText(
        candidate.destination.title,
        maximumUTF8Count: Self.maximumTitleUTF8Count
      )
      guard cached?.contentRevision != candidate.contentRevision
              || cached?.destinationTitle != boundedTitle else {
        continue
      }
      guard let prepared = Self.prepare(candidate) else { return false }
      replacements.append(prepared)
    }
    guard !Task.isCancelled else { return false }

    let replacementIDs = Set(replacements.map(\.note.noteID))
    let removedIDs = Set(notes.keys).subtracting(currentIDs).union(replacementIDs)
    for noteID in removedIDs { remove(noteID) }
    for replacement in replacements { insert(replacement.note, passages: replacement.passages) }
    return !Task.isCancelled
  }

  private static func prepare(
    _ candidate: DictationRoutingCandidate
  ) -> (note: Note, passages: [Passage])? {
    guard !Task.isCancelled else { return nil }
    let noteID = candidate.destination.noteID
    let boundedTitle = Self.boundedText(
      candidate.destination.title,
      maximumUTF8Count: Self.maximumTitleUTF8Count
    )
    let normalizedTitle = Self.normalizedWhitespace(boundedTitle)
    let boundedTitleTerms = Self.boundedMeaningfulTerms(
      in: normalizedTitle,
      limit: Self.maximumTitleTermCount
    )
    let titleTerms = boundedTitleTerms.values
    let boundedTitleTrigrams = Self.boundedTrigrams(
      for: titleTerms,
      limit: Self.maximumTitleTrigramCount
    )
    let titleTrigrams = boundedTitleTrigrams.values
    guard let preparedBody = Self.bodyPassages(candidate.semanticContext) else { return nil }
    let bodyPassages = preparedBody.passages
    let passageIDs = bodyPassages.indices.map { PassageID(noteID: noteID, ordinal: $0) }
    let note = Note(
      noteID: noteID,
      destinationTitle: boundedTitle,
      contentRevision: candidate.contentRevision,
      titleTerms: titleTerms,
      titleTrigrams: titleTrigrams,
      passageIDs: passageIDs,
      requiresCompletenessGuard: boundedTitle != candidate.destination.title
        || boundedTitleTerms.wasTruncated
        || boundedTitleTrigrams.wasTruncated
        || preparedBody.requiresCompletenessGuard
    )
    return (note, bodyPassages)
  }

  private func insert(_ note: Note, passages bodyPassages: [Passage]) {
    let noteID = note.noteID
    notes[noteID] = note

    for (passageID, passage) in zip(note.passageIDs, bodyPassages) {
      passages[passageID] = passage
      let indexedTitleTerms = passageID.ordinal == 0 ? note.titleTerms : []
      let indexedTitleTrigrams = passageID.ordinal == 0 ? note.titleTrigrams : []
      for term in indexedTitleTerms.union(passage.terms) {
        exactPostings[term, default: []].insert(passageID)
      }
      for trigram in indexedTitleTrigrams.union(passage.trigrams) {
        trigramPostings[trigram, default: []].insert(passageID)
      }
    }
  }

  private func remove(_ noteID: UUID) {
    guard let note = notes.removeValue(forKey: noteID) else { return }
    for passageID in note.passageIDs {
      guard let passage = passages.removeValue(forKey: passageID) else { continue }
      let indexedTitleTerms = passageID.ordinal == 0 ? note.titleTerms : []
      let indexedTitleTrigrams = passageID.ordinal == 0 ? note.titleTrigrams : []
      for term in indexedTitleTerms.union(passage.terms) {
        exactPostings[term]?.remove(passageID)
        if exactPostings[term]?.isEmpty == true { exactPostings[term] = nil }
      }
      for trigram in indexedTitleTrigrams.union(passage.trigrams) {
        trigramPostings[trigram]?.remove(passageID)
        if trigramPostings[trigram]?.isEmpty == true { trigramPostings[trigram] = nil }
      }
    }
  }

  private func rarity(
    of feature: String,
    in postings: [String: Set<PassageID>]
  ) -> Int {
    let documentFrequency = Set(postings[feature, default: []].map(\.noteID)).count
    return max(1, notes.count - documentFrequency + 1)
  }

  private func scanForUnindexedQueryEvidence(
    in candidate: DictationRoutingCandidate,
    queryTerms: Set<String>,
    queryTrigrams: Set<String>,
    remainingGlobalUTF8Count: inout Int
  ) -> CompletenessScanResult {
    var unindexedTerms = queryTerms
    var unindexedTrigrams = queryTrigrams
    if let note = notes[candidate.destination.noteID] {
      unindexedTerms.subtract(note.titleTerms)
      unindexedTrigrams.subtract(note.titleTrigrams)
      for passageID in note.passageIDs {
        guard let passage = passages[passageID] else { continue }
        unindexedTerms.subtract(passage.terms)
        unindexedTrigrams.subtract(passage.trigrams)
      }
    }
    guard !unindexedTerms.isEmpty || !unindexedTrigrams.isEmpty else { return .noEvidence }

    var remainingCandidateUTF8Count = Self.maximumCompletenessScanUTF8PerCandidate
    let titleResult = scanQueryEvidence(
      in: candidate.destination.title,
      queryTerms: unindexedTerms,
      queryTrigrams: unindexedTrigrams,
      remainingCandidateUTF8Count: &remainingCandidateUTF8Count,
      remainingGlobalUTF8Count: &remainingGlobalUTF8Count
    )
    guard titleResult == .noEvidence else { return titleResult }
    return scanQueryEvidence(
      in: candidate.semanticContext,
      queryTerms: unindexedTerms,
      queryTrigrams: unindexedTrigrams,
      remainingCandidateUTF8Count: &remainingCandidateUTF8Count,
      remainingGlobalUTF8Count: &remainingGlobalUTF8Count
    )
  }

  private func scanQueryEvidence(
    in input: String,
    queryTerms: Set<String>,
    queryTrigrams: Set<String>,
    remainingCandidateUTF8Count: inout Int,
    remainingGlobalUTF8Count: inout Int
  ) -> CompletenessScanResult {
    guard !Task.isCancelled else { return .exhausted }
    let allowedUTF8Count = min(remainingCandidateUTF8Count, remainingGlobalUTF8Count)
    let bounded = Self.boundedScanText(input, maximumUTF8Count: allowedUTF8Count)
    remainingCandidateUTF8Count -= bounded.utf8Count
    remainingGlobalUTF8Count -= bounded.utf8Count
    lastCompletenessScanUTF8Count += bounded.utf8Count
    guard !bounded.wasTruncated, !Task.isCancelled else { return .exhausted }
    return Self.containsQueryEvidence(
      in: bounded.text,
      queryTerms: queryTerms,
      queryTrigrams: queryTrigrams
    ) ? .evidence : .noEvidence
  }

  private static func precedes(_ lhs: ScoredPassage, _ rhs: ScoredPassage) -> Bool {
    if lhs.match.score != rhs.match.score { return lhs.match.score > rhs.match.score }
    if lhs.match.exactTermMatches != rhs.match.exactTermMatches {
      return lhs.match.exactTermMatches > rhs.match.exactTermMatches
    }
    return lhs.ordinal < rhs.ordinal
  }

  private static func bodyPassages(
    _ body: String
  ) -> (passages: [Passage], requiresCompletenessGuard: Bool)? {
    guard !Task.isCancelled else { return nil }
    let words = body.split(whereSeparator: \Character.isWhitespace)
    guard !words.isEmpty else {
      return ([Passage(excerpt: "", terms: [], trigrams: [])], false)
    }

    let passageStarts: [Int]
    let naturalPassageCount = 1 + max(0, words.count - 96 + 71) / 72
    if naturalPassageCount <= maximumPassagesPerNote {
      passageStarts = (0..<naturalPassageCount).map { $0 * 72 }
    } else {
      let lastStart = words.count - 96
      passageStarts = (0..<maximumPassagesPerNote).map { ordinal in
        ordinal * lastStart / (maximumPassagesPerNote - 1)
      }
    }

    var result: [Passage] = []
    result.reserveCapacity(passageStarts.count)
    var requiresCompletenessGuard = naturalPassageCount > maximumPassagesPerNote
    for start in passageStarts {
      guard !Task.isCancelled else { return nil }
      let end = min(start + 96, words.count)
      let excerptResult = boundedExcerpt(words[start..<end])
      let excerpt = excerptResult.text
      let boundedTerms = boundedMeaningfulTerms(in: excerpt, limit: maximumPassageTermCount)
      let terms = boundedTerms.values
      let boundedPassageTrigrams = boundedTrigrams(
        for: terms,
        limit: maximumPassageTrigramCount
      )
      let passageTrigrams = boundedPassageTrigrams.values
      result.append(Passage(
        excerpt: excerpt,
        terms: terms,
        trigrams: passageTrigrams
      ))
      requiresCompletenessGuard = requiresCompletenessGuard
        || excerptResult.wasTruncated
        || boundedTerms.wasTruncated
        || boundedPassageTrigrams.wasTruncated
    }
    return (result, requiresCompletenessGuard)
  }

  private static func meaningfulTerms(in input: String) -> Set<String> {
    boundedMeaningfulTerms(in: input, limit: .max).values
  }

  private static func boundedMeaningfulTerms(
    in input: String,
    limit: Int
  ) -> BoundedFeatureSet {
    var result = Set<String>()
    for lexeme in CleanupLexeme.scan(input) {
      guard lexeme.kind == .word else { continue }
      let term = lexeme.canonical
      guard term.count > 1, !ignoredTerms.contains(term), !result.contains(term) else { continue }
      guard result.count < limit else { return BoundedFeatureSet(values: result, wasTruncated: true) }
      result.insert(term)
    }
    return BoundedFeatureSet(values: result, wasTruncated: false)
  }

  private static func trigrams(for terms: Set<String>) -> Set<String> {
    boundedTrigrams(for: terms, limit: .max).values
  }

  private static func boundedTrigrams(
    for terms: Set<String>,
    limit: Int
  ) -> BoundedFeatureSet {
    var result = Set<String>()
    for term in terms.sorted() {
      let bytes = Array(term.utf8)
      guard bytes.count >= 4, bytes.allSatisfy({ (97...122).contains($0) }) else { continue }
      for index in 0...(bytes.count - 3) {
        let trigram = String(decoding: bytes[index..<(index + 3)], as: UTF8.self)
        guard !result.contains(trigram) else { continue }
        guard result.count < limit else {
          return BoundedFeatureSet(values: result, wasTruncated: true)
        }
        result.insert(trigram)
      }
    }
    return BoundedFeatureSet(values: result, wasTruncated: false)
  }

  private static func containsQueryEvidence(
    in input: String,
    queryTerms: Set<String>,
    queryTrigrams: Set<String>
  ) -> Bool {
    guard !Task.isCancelled else { return false }
    for lexeme in CleanupLexeme.scan(input) {
      guard !Task.isCancelled else { return false }
      guard lexeme.kind == .word else { continue }
      let term = lexeme.canonical
      guard term.count > 1, !ignoredTerms.contains(term) else { continue }
      if queryTerms.contains(term) { return true }

      let bytes = Array(term.utf8)
      guard bytes.count >= 4, bytes.allSatisfy({ (97...122).contains($0) }) else {
        continue
      }
      for index in 0...(bytes.count - 3) {
        let trigram = String(decoding: bytes[index..<(index + 3)], as: UTF8.self)
        if queryTrigrams.contains(trigram) { return true }
      }
    }
    return false
  }

  private static func boundedScanText(
    _ input: String,
    maximumUTF8Count: Int
  ) -> (text: String, utf8Count: Int, wasTruncated: Bool) {
    var result = ""
    var byteCount = 0
    for character in input {
      guard !Task.isCancelled else { return (result, byteCount, true) }
      let characterByteCount = character.utf8.count
      guard byteCount + characterByteCount <= maximumUTF8Count else {
        return (result, byteCount, true)
      }
      result.append(character)
      byteCount += characterByteCount
    }
    return (result, byteCount, false)
  }

  private static func boundedExcerpt(
    _ words: ArraySlice<Substring>
  ) -> (text: String, wasTruncated: Bool) {
    var result = ""
    var byteCount = 0
    for word in words {
      if !result.isEmpty {
        guard byteCount < maximumExcerptUTF8PerPassage else { return (result, true) }
        result.append(" ")
        byteCount += 1
      }
      for character in word {
        let characterByteCount = character.utf8.count
        guard byteCount + characterByteCount <= maximumExcerptUTF8PerPassage else {
          return (result, true)
        }
        result.append(character)
        byteCount += characterByteCount
      }
    }
    return (result, false)
  }

  private static func boundedText(
    _ input: String,
    maximumUTF8Count: Int
  ) -> String {
    var result = ""
    var byteCount = 0
    for character in input {
      let characterByteCount = character.utf8.count
      guard byteCount + characterByteCount <= maximumUTF8Count else { break }
      result.append(character)
      byteCount += characterByteCount
    }
    return result
  }

  private static func normalizedWhitespace(_ input: String) -> String {
    input.split(whereSeparator: \Character.isWhitespace).joined(separator: " ")
  }

  private static let ignoredTerms: Set<String> = [
    "a", "an", "and", "are", "as", "at", "be", "but", "by", "can", "do", "for",
    "from", "had", "has", "have", "he", "her", "his", "i", "if", "in", "is", "it",
    "its", "like", "me", "my", "of", "on", "or", "our", "please", "she", "so", "that",
    "the", "their", "them", "they", "this", "to", "uh", "um", "we", "were", "what",
    "when", "where", "which", "who", "will", "with", "you", "your",
  ]
}
