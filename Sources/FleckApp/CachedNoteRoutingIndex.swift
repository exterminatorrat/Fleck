import Foundation

struct CachedNoteRoutingMatch: Equatable, Sendable {
  let candidate: DictationRoutingCandidate
  let excerpt: String
  let score: Int
  let exactTermMatches: Int
}

actor CachedNoteRoutingIndex {
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
  }

  private struct ScoredPassage {
    let match: CachedNoteRoutingMatch
    let ordinal: Int
  }

  private var notes: [UUID: Note] = [:]
  private var passages: [PassageID: Passage] = [:]
  private var exactPostings: [String: Set<PassageID>] = [:]
  private var trigramPostings: [String: Set<PassageID>] = [:]

  func retrieve(
    transcript: String,
    candidates: [DictationRoutingCandidate],
    limit: Int = 6
  ) -> [CachedNoteRoutingMatch] {
    guard !Task.isCancelled, limit > 0 else { return [] }
    let queryTerms = Self.meaningfulTerms(in: transcript)
    guard !queryTerms.isEmpty else { return [] }

    let candidateIDs = candidates.map(\.destination.noteID)
    guard Set(candidateIDs).count == candidates.count else { return [] }
    let candidatesByID = Dictionary(uniqueKeysWithValues: candidates.map {
      ($0.destination.noteID, $0)
    })

    guard synchronize(candidates), !Task.isCancelled else { return [] }

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

  private func synchronize(_ candidates: [DictationRoutingCandidate]) -> Bool {
    let currentIDs = Set(candidates.map(\.destination.noteID))
    var replacements: [(note: Note, passages: [Passage])] = []
    for candidate in candidates {
      guard !Task.isCancelled else { return false }
      let cached = notes[candidate.destination.noteID]
      guard cached?.contentRevision != candidate.contentRevision
              || cached?.destinationTitle != candidate.destination.title else {
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
    let normalizedTitle = Self.normalizedWhitespace(candidate.destination.title)
    let titleTerms = Self.meaningfulTerms(in: normalizedTitle)
    let titleTrigrams = Self.trigrams(for: titleTerms)
    guard let bodyPassages = Self.bodyPassages(candidate.semanticContext) else { return nil }
    let passageIDs = bodyPassages.indices.map { PassageID(noteID: noteID, ordinal: $0) }
    let note = Note(
      noteID: noteID,
      destinationTitle: candidate.destination.title,
      contentRevision: candidate.contentRevision,
      titleTerms: titleTerms,
      titleTrigrams: titleTrigrams,
      passageIDs: passageIDs
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

  private static func precedes(_ lhs: ScoredPassage, _ rhs: ScoredPassage) -> Bool {
    if lhs.match.score != rhs.match.score { return lhs.match.score > rhs.match.score }
    if lhs.match.exactTermMatches != rhs.match.exactTermMatches {
      return lhs.match.exactTermMatches > rhs.match.exactTermMatches
    }
    return lhs.ordinal < rhs.ordinal
  }

  private static func bodyPassages(_ body: String) -> [Passage]? {
    guard !Task.isCancelled else { return nil }
    let words = normalizedWhitespace(body).split(separator: " ").map(String.init)
    guard !words.isEmpty else {
      return [Passage(excerpt: "", terms: [], trigrams: [])]
    }

    var result: [Passage] = []
    var start = 0
    while start < words.count {
      guard !Task.isCancelled else { return nil }
      let end = min(start + 96, words.count)
      let excerpt = words[start..<end].joined(separator: " ")
      let terms = meaningfulTerms(in: excerpt)
      result.append(Passage(excerpt: excerpt, terms: terms, trigrams: trigrams(for: terms)))
      if end == words.count { break }
      start += 72
    }
    return result
  }

  private static func meaningfulTerms(in input: String) -> Set<String> {
    Set(CleanupLexeme.scan(input).compactMap { lexeme in
      guard lexeme.kind == .word else { return nil }
      let term = lexeme.canonical
      guard term.count > 1, !ignoredTerms.contains(term) else { return nil }
      return term
    })
  }

  private static func trigrams(for terms: Set<String>) -> Set<String> {
    Set(terms.flatMap { term -> [String] in
      let bytes = Array(term.utf8)
      guard bytes.count >= 4, bytes.allSatisfy({ (97...122).contains($0) }) else { return [] }
      return (0...(bytes.count - 3)).map { index in
        String(decoding: bytes[index..<(index + 3)], as: UTF8.self)
      }
    })
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
