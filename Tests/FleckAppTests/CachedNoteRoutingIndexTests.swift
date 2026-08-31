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

@Test func cachedRoutingUsesEnglishLemmasForOrdinaryInflections() async {
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
  #expect(matches.first?.exactTermMatches == 1)
  #expect(matches.first?.score ?? 0 > 0)
}

@Test func cachedRoutingLemmatizesIndependentEnglishPluralConcepts() async {
  let target = cachedRoutingCandidate(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000013")!,
    title: "Chi Han Technologies Website",
    body: "Filling in all the placeholder images"
  )
  let unrelated = cachedRoutingCandidate(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000014")!,
    title: "Website Demo",
    body: "Prepare the launch recording and product walkthrough"
  )
  let index = CachedNoteRoutingIndex()

  let matches = await index.retrieve(
    transcript: "We need to fix all the image placeholders",
    candidates: [unrelated, target]
  )

  #expect(matches.first?.candidate.destination.noteID == target.destination.noteID)
  #expect(matches.first?.exactTermMatches == 3)
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
    body: "holographic"
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

@Test func cachedRoutingReusesBoundedLongTitleIdentityWithoutReindexingTheBody() async {
  let id = UUID(uuidString: "00000000-0000-0000-0000-000000000063")!
  let longTitle = String(repeating: "Long title segment ", count: 200)
  let original = cachedRoutingCandidate(
    id: id,
    title: longTitle,
    body: "amberquartz findings",
    revision: 7
  )
  let changedBody = cachedRoutingCandidate(
    id: id,
    title: longTitle,
    body: "violetnebula findings",
    revision: 7
  )
  let index = CachedNoteRoutingIndex()

  _ = await index.retrieve(transcript: "amberquartz", candidates: [original])
  let reused = await index.retrieve(transcript: "amberquartz", candidates: [changedBody])

  #expect(reused.first?.candidate == changedBody)
  #expect(reused.first?.excerpt.contains("amberquartz") == true)
  #expect(await index.retrieve(
    transcript: "violetnebula",
    candidates: [changedBody]
  ).isEmpty)
}

@Test func cachedRoutingReindexesWhenATitleCrossesTheBoundedIdentityBoundary() async {
  let apparent = cachedRoutingCandidate(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000064")!,
    title: "Apparent",
    body: "zxqvbp indexed evidence",
    revision: 7
  )
  let boundaryID = UUID(uuidString: "00000000-0000-0000-0000-000000000065")!
  let boundaryTitle = String(repeating: " ", count: 2_041) + "Archive"
  let original = cachedRoutingCandidate(
    id: boundaryID,
    title: boundaryTitle,
    body: "ordinary archive material",
    revision: 7
  )
  let appended = cachedRoutingCandidate(
    id: boundaryID,
    title: boundaryTitle + " zxqvbp",
    body: "ordinary archive material",
    revision: 7
  )
  let index = CachedNoteRoutingIndex()

  #expect(boundaryTitle.utf8.count == 2_048)
  #expect(await index.retrieve(
    transcript: "zxqvbp",
    candidates: [apparent, original]
  ).first?.candidate == apparent)
  #expect(await index.retrieve(
    transcript: "zxqvbp",
    candidates: [appended, apparent]
  ).isEmpty)
  #expect(await index.retrieve(
    transcript: "zxqvbp",
    candidates: [apparent]
  ).first?.candidate == apparent)
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

@Test func cachedRoutingBoundsAggregateResourcesDeterministically() async {
  let candidateCount = CachedNoteRoutingIndex.maximumNoteCount + 64
  let oversizedBody = Array(repeating: "bounded evidence", count: 400)
    .joined(separator: " ")
  let candidates = (0..<candidateCount).map { index in
    cachedRoutingCandidate(
      id: UUID(uuidString: String(format: "00000000-0000-0000-%04x-%012x", index, index))!,
      title: "Bounded \(index)",
      body: index == 0
        ? oversizedBody + " rareterminalmarker"
        : (index < CachedNoteRoutingIndex.maximumNoteCount
          ? oversizedBody
          : "ordinary archive material")
    )
  }
  let forwardIndex = CachedNoteRoutingIndex()
  let reverseIndex = CachedNoteRoutingIndex()

  let forward = await forwardIndex.retrieve(
    transcript: "rareterminalmarker",
    candidates: candidates,
    limit: 1
  )
  let reverse = await reverseIndex.retrieve(
    transcript: "rareterminalmarker",
    candidates: Array(candidates.reversed()),
    limit: 1
  )
  let usage = await forwardIndex.resourceUsage()

  #expect(forward.isEmpty)
  #expect(reverse == forward)
  #expect(await forwardIndex.retrieve(
    transcript: "rareterminalmarker",
    candidates: candidates,
    limit: 1
  ) == forward)
  #expect(usage.noteCount == CachedNoteRoutingIndex.maximumNoteCount)
  #expect(usage.passageCount <= CachedNoteRoutingIndex.maximumPassageCount)
  #expect(usage.excerptUTF8Count <= CachedNoteRoutingIndex.maximumExcerptUTF8Count)
  #expect(usage.exactPostingCount <= CachedNoteRoutingIndex.maximumExactPostingCount)
  #expect(usage.trigramPostingCount <= CachedNoteRoutingIndex.maximumTrigramPostingCount)
  #expect(usage.completenessScanUTF8Count
    <= CachedNoteRoutingIndex.maximumCompletenessScanUTF8Count)
}

@Test func cachedRoutingFailsClosedWhenAnOmittedNoteHasRelevantEvidence() async {
  let apparent = cachedRoutingCandidate(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
    title: "Apparent",
    body: "boundarysignal indexed evidence"
  )
  let unrelated = (2...CachedNoteRoutingIndex.maximumNoteCount).map { index in
    cachedRoutingCandidate(
      id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", index))!,
      title: "Unrelated \(index)",
      body: "ordinary archive material"
    )
  }
  let omitted = cachedRoutingCandidate(
    id: UUID(uuidString: "ffffffff-ffff-ffff-ffff-ffffffffffff")!,
    title: "Omitted",
    body: "boundarysignal omitted evidence"
  )
  let candidates = [apparent] + unrelated + [omitted]
  let index = CachedNoteRoutingIndex()

  #expect(await index.retrieve(
    transcript: "boundarysignal",
    candidates: candidates
  ).isEmpty)
  #expect(await index.retrieve(
    transcript: "boundarysignal",
    candidates: Array(candidates.reversed())
  ).isEmpty)
}

@Test func cachedRoutingFailsClosedWhenAnUnsampledGapHasRelevantEvidence() async {
  let apparent = cachedRoutingCandidate(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
    title: "Apparent",
    body: "gapsignal indexed evidence"
  )
  var hiddenWords = Array(repeating: "ordinary", count: 1_000)
  hiddenWords[110] = "gapsignal"
  let hidden = cachedRoutingCandidate(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
    title: "Hidden",
    body: hiddenWords.joined(separator: " ")
  )
  let index = CachedNoteRoutingIndex()

  #expect(await index.retrieve(
    transcript: "gapsignal",
    candidates: [apparent, hidden]
  ).isEmpty)
}

@Test func cachedRoutingStillRoutesSampledEdgesWhenOmittedRegionsHaveNoEvidence() async {
  var words = Array(repeating: "ordinary", count: 1_000)
  words[0] = "beginningsignal"
  words[999] = "endingsignal"
  let candidate = cachedRoutingCandidate(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
    title: "Edges",
    body: words.joined(separator: " ")
  )
  let index = CachedNoteRoutingIndex()

  #expect(await index.retrieve(
    transcript: "beginningsignal",
    candidates: [candidate]
  ).first?.candidate.destination.noteID == candidate.destination.noteID)
  #expect(await index.retrieve(
    transcript: "endingsignal",
    candidates: [candidate]
  ).first?.candidate.destination.noteID == candidate.destination.noteID)
  #expect(await index.resourceUsage().completenessScanUTF8Count == 0)
}

@Test func cachedRoutingFailsClosedAtThePerCandidateCompletenessScanBudget() async {
  let apparent = cachedRoutingCandidate(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
    title: "Apparent",
    body: "zxqvbp indexed evidence"
  )
  let unrelated = (2...CachedNoteRoutingIndex.maximumNoteCount).map { index in
    cachedRoutingCandidate(
      id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", index))!,
      title: "Unrelated \(index)",
      body: "ordinary archive material"
    )
  }
  let omitted = cachedRoutingCandidate(
    id: UUID(uuidString: "ffffffff-ffff-ffff-ffff-ffffffffffff")!,
    title: "Omitted",
    body: String(
      repeating: "ordinary archive material ",
      count: CachedNoteRoutingIndex.maximumCompletenessScanUTF8PerCandidate / 8
    ) + " zxqvbp"
  )
  let index = CachedNoteRoutingIndex()

  #expect(await index.retrieve(
    transcript: "zxqvbp",
    candidates: [apparent] + unrelated + [omitted]
  ).isEmpty)
  let usage = await index.resourceUsage()
  #expect(usage.completenessScanUTF8Count
    == CachedNoteRoutingIndex.maximumCompletenessScanUTF8PerCandidate)
}

@Test func cachedRoutingFailsClosedAtTheGlobalCompletenessScanBudget() async {
  let apparent = cachedRoutingCandidate(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
    title: "Apparent",
    body: "zxqvbp indexed evidence"
  )
  let unrelated = (2...CachedNoteRoutingIndex.maximumNoteCount).map { index in
    cachedRoutingCandidate(
      id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", index))!,
      title: "Unrelated \(index)",
      body: "ordinary archive material"
    )
  }
  let omitted = (0..<20).map { index in
    cachedRoutingCandidate(
      id: UUID(uuidString: String(format: "ffffffff-ffff-ffff-ffff-%012x", index))!,
      title: "Omitted \(index)",
      body: String(repeating: "ordinary archive material ", count: 400)
    )
  }
  let index = CachedNoteRoutingIndex()

  #expect(await index.retrieve(
    transcript: "zxqvbp",
    candidates: [apparent] + unrelated + omitted
  ).isEmpty)
  let usage = await index.resourceUsage()
  #expect(usage.completenessScanUTF8Count
    == CachedNoteRoutingIndex.maximumCompletenessScanUTF8Count)
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
