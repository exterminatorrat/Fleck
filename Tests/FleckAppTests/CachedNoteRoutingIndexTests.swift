import Foundation
import FleckCore
import Testing

@testable import FleckApp

@Test func cachedRoutingFindsEvidenceFromTheMiddleOfACompleteLongNote() async {
  let target = cachedRoutingCandidate(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
    title: "Optics",
    body: (Array(repeating: "ordinary", count: 120)
      + ["laser", "interference", "holography", "experiment"]
      + Array(repeating: "trailing", count: 120)).joined(separator: " "),
    revision: 4
  )
  let index = CachedNoteRoutingIndex()

  let matches = await index.retrieve(
    transcript: "Record the laser holography experiment",
    candidates: [target]
  )

  #expect(matches.first?.candidate.destination.noteID == target.destination.noteID)
  #expect(matches.first?.excerpt.contains("laser interference holography experiment") == true)
  #expect(matches.first?.excerpt.split(whereSeparator: \Character.isWhitespace).count ?? 0 <= 96)
}

@Test func cachedRoutingSupportsArbitraryVocabularyWithoutProjectMappings() async {
  let target = cachedRoutingCandidate(
    title: "Asterism",
    body: "Quartz noctilucent vespertilion lucidarium"
  )
  let index = CachedNoteRoutingIndex()

  let matches = await index.retrieve(
    transcript: "Remember the noctilucent lucidarium",
    candidates: [target]
  )

  #expect(matches.map { $0.candidate.destination.noteID } == [target.destination.noteID])
  #expect(matches.first?.exactTermMatches == 2)
}

@Test func cachedRoutingUsesGenericTrigramsForOrdinaryInflections() async {
  let target = cachedRoutingCandidate(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
    title: "Displays",
    body: "The laboratory has a hologram display"
  )
  let unrelated = cachedRoutingCandidate(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
    title: "Archive",
    body: "The laboratory stores old records"
  )
  let index = CachedNoteRoutingIndex()

  let matches = await index.retrieve(
    transcript: "Review the holograms",
    candidates: [unrelated, target]
  )

  #expect(matches.first?.candidate.destination.noteID == target.destination.noteID)
  #expect(matches.first?.exactTermMatches == 0)
  #expect(matches.first?.score ?? 0 > 0)
}

@Test func cachedRoutingOrdersTiesByNormalizedTitleThenUUID() async {
  let alpha = cachedRoutingCandidate(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000022")!,
    title: " alpha\n",
    body: "common phrase"
  )
  let sharedFirst = cachedRoutingCandidate(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000020")!,
    title: "Shared",
    body: "common phrase"
  )
  let sharedSecond = cachedRoutingCandidate(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!,
    title: "shared",
    body: "common phrase"
  )
  let index = CachedNoteRoutingIndex()

  let forward = await index.retrieve(
    transcript: "common phrase",
    candidates: [sharedSecond, alpha, sharedFirst]
  )
  let reversed = await index.retrieve(
    transcript: "common phrase",
    candidates: [sharedFirst, alpha, sharedSecond]
  )

  let expected = [alpha, sharedFirst, sharedSecond].map(\.destination.noteID)
  #expect(forward.map { $0.candidate.destination.noteID } == expected)
  #expect(reversed == forward)
}

@Test func cachedRoutingScoresExactMatchesAboveTrigramOnlyMatches() async {
  let exact = cachedRoutingCandidate(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000024")!,
    title: "Zulu",
    body: "holograms"
  )
  let fuzzy = cachedRoutingCandidate(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000023")!,
    title: "Alpha",
    body: "hologram"
  )
  let index = CachedNoteRoutingIndex()

  let matches = await index.retrieve(transcript: "holograms", candidates: [fuzzy, exact])

  #expect(matches.first?.candidate.destination.noteID == exact.destination.noteID)
  #expect(matches.first?.exactTermMatches == 1)
}

@Test func cachedRoutingBoostsExactTitleEvidenceAboveBodyEvidence() async {
  let titleMatch = cachedRoutingCandidate(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000031")!,
    title: "Aurora Signal",
    body: "Unrelated meeting notes"
  )
  let bodyMatch = cachedRoutingCandidate(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000032")!,
    title: "Archive",
    body: "Aurora signal observations"
  )
  let index = CachedNoteRoutingIndex()

  let matches = await index.retrieve(
    transcript: "Discuss the aurora signal",
    candidates: [bodyMatch, titleMatch]
  )

  #expect(matches.first?.candidate.destination.noteID == titleMatch.destination.noteID)
  #expect((matches.first?.score ?? 0) > (matches.dropFirst().first?.score ?? 0))
}

@Test func cachedRoutingReturnsEmptyForDuplicateCandidateIDs() async {
  let id = UUID(uuidString: "00000000-0000-0000-0000-000000000041")!
  let first = cachedRoutingCandidate(id: id, title: "First", body: "distinct evidence")
  let second = cachedRoutingCandidate(id: id, title: "Second", body: "different evidence")
  let index = CachedNoteRoutingIndex()

  #expect(await index.retrieve(
    transcript: "distinct evidence",
    candidates: [first, second]
  ).isEmpty)
}

@Test func cachedRoutingReindexesChangedContentRevision() async {
  let id = UUID(uuidString: "00000000-0000-0000-0000-000000000051")!
  let original = cachedRoutingCandidate(
    id: id,
    title: "Research",
    body: "obsoletequartz findings",
    revision: 1
  )
  let changed = cachedRoutingCandidate(
    id: id,
    title: "Research",
    body: "currentnebula findings",
    revision: 2
  )
  let index = CachedNoteRoutingIndex()

  #expect(await index.retrieve(
    transcript: "obsoletequartz",
    candidates: [original]
  ).first?.candidate.destination.noteID == id)
  #expect(await index.retrieve(
    transcript: "obsoletequartz",
    candidates: [changed]
  ).isEmpty)
  #expect(await index.retrieve(
    transcript: "currentnebula",
    candidates: [changed]
  ).first?.candidate.destination.noteID == id)
}

@Test func cachedRoutingTreatsRevisionAsTheAuthoritativeBodyIdentity() async {
  let id = UUID(uuidString: "00000000-0000-0000-0000-000000000061")!
  let original = cachedRoutingCandidate(
    id: id,
    title: "Research",
    body: "amberquartz findings",
    revision: 7
  )
  let changed = cachedRoutingCandidate(
    id: id,
    title: "Research",
    body: "violetnebula findings",
    revision: 7
  )
  let index = CachedNoteRoutingIndex()

  _ = await index.retrieve(transcript: "amberquartz", candidates: [original])
  let reused = await index.retrieve(transcript: "amberquartz", candidates: [changed])

  #expect(reused.first?.candidate == changed)
  #expect(reused.first?.excerpt.contains("amberquartz") == true)
  #expect(await index.retrieve(transcript: "violetnebula", candidates: [changed]).isEmpty)
}

@Test func cachedRoutingReindexesAChangedTitleWithoutARevisionChange() async {
  let id = UUID(uuidString: "00000000-0000-0000-0000-000000000062")!
  let original = cachedRoutingCandidate(
    id: id,
    title: "Amberquartz",
    body: "stable findings",
    revision: 7
  )
  let renamed = cachedRoutingCandidate(
    id: id,
    title: "Violetnebula",
    body: "stable findings",
    revision: 7
  )
  let index = CachedNoteRoutingIndex()

  _ = await index.retrieve(transcript: "amberquartz", candidates: [original])

  #expect(await index.retrieve(transcript: "amberquartz", candidates: [renamed]).isEmpty)
  #expect(await index.retrieve(
    transcript: "violetnebula",
    candidates: [renamed]
  ).first?.candidate == renamed)
}

@Test func cachedRoutingReusesAnUnchangedRevisionDeterministically() async {
  let candidate = cachedRoutingCandidate(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000071")!,
    title: "Reuse",
    body: "stable passage evidence",
    revision: 9
  )
  let index = CachedNoteRoutingIndex()

  let first = await index.retrieve(transcript: "stable evidence", candidates: [candidate])
  let second = await index.retrieve(transcript: "stable evidence", candidates: [candidate])

  #expect(second == first)
}

@Test func cachedRoutingRemovesNotesAbsentFromTheLatestCandidateSet() async {
  let retained = cachedRoutingCandidate(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000081")!,
    title: "Retained",
    body: "persistent archive"
  )
  let deleted = cachedRoutingCandidate(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000082")!,
    title: "Deleted",
    body: "vanished relic"
  )
  let index = CachedNoteRoutingIndex()

  _ = await index.retrieve(transcript: "vanished relic", candidates: [retained, deleted])
  #expect(await index.retrieve(transcript: "vanished relic", candidates: [retained]).isEmpty)
}

@Test func cachedRoutingHonorsResultLimitAndReturnsUniqueNotes() async {
  let candidates = (1...3).map { number in
    cachedRoutingCandidate(
      id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!,
      title: "Note \(number)",
      body: "shared bounded evidence"
    )
  }
  let index = CachedNoteRoutingIndex()

  let matches = await index.retrieve(
    transcript: "shared bounded evidence",
    candidates: candidates,
    limit: 2
  )

  #expect(matches.count == 2)
  #expect(Set(matches.map { $0.candidate.destination.noteID }).count == 2)
}

@Test func cachedRoutingReturnsEmptyForBlankGenericNoEvidenceAndNonpositiveLimit() async {
  let candidate = cachedRoutingCandidate(title: "Useful", body: "specific evidence")
  let index = CachedNoteRoutingIndex()

  #expect(await index.retrieve(transcript: "   \n\t", candidates: [candidate]).isEmpty)
  #expect(await index.retrieve(
    transcript: "the and of with please",
    candidates: [candidate]
  ).isEmpty)
  #expect(await index.retrieve(transcript: "unmatched", candidates: [candidate]).isEmpty)
  #expect(await index.retrieve(
    transcript: "specific",
    candidates: [candidate],
    limit: 0
  ).isEmpty)
}

@Test func cachedRoutingPreCancellationReturnsEmptyAndPreservesCachedResults() async {
  let candidate = cachedRoutingCandidate(title: "Cancel", body: "cancelled evidence")
  let index = CachedNoteRoutingIndex()
  let cached = await index.retrieve(transcript: "cancelled evidence", candidates: [candidate])
  let task = Task {
    while !Task.isCancelled { await Task.yield() }
    return await index.retrieve(transcript: "cancelled evidence", candidates: [candidate])
  }

  task.cancel()

  #expect(await task.value.isEmpty)
  #expect(await index.retrieve(
    transcript: "cancelled evidence",
    candidates: [candidate]
  ) == cached)
}

private func cachedRoutingCandidate(
  id: UUID = UUID(),
  title: String,
  body: String,
  revision: UInt64 = 0
) -> DictationRoutingCandidate {
  DictationRoutingCandidate(
    destination: DictationDestination(noteID: id, title: title),
    semanticContext: body,
    contentRevision: revision
  )
}
