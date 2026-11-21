import Foundation
import Testing

@testable import FleckCore

@Test func WorkspaceSearchRanksExactTitleBeforePrefixSubstringAndBody() async {
  let notes = [
    searchNote(
      "00000000-0000-0000-0000-000000000001",
      title: "  CAFÉ  ",
      body: "unrelated body",
      modifiedAt: 400
    ),
    searchNote(
      "00000000-0000-0000-0000-000000000002",
      title: "Café notes",
      body: "unrelated body",
      modifiedAt: 300
    ),
    searchNote(
      "00000000-0000-0000-0000-000000000003",
      title: "Daily Café notes",
      body: "unrelated body",
      modifiedAt: 200
    ),
    searchNote(
      "00000000-0000-0000-0000-000000000004",
      title: "Other title",
      body: "A café appears in the body.",
      modifiedAt: 500
    ),
  ]

  let results = await WorkspaceSearchEngine().search(query: "cafe", in: notes)

  #expect(results.map(\.noteID) == notes.map(\.id))
  #expect(results.map(\.score) == [4, 3, 2, 1])
  #expect(results.map { $0.match.field } == [.title, .title, .title, .body])
}

@Test func WorkspaceSearchFoldsCaseAndDiacriticsButReportsOriginalUTF16Range() async {
  let note = searchNote(
    "00000000-0000-0000-0000-000000000010",
    title: "Crème brûlée",
    body: "α 👩‍💻 naïve and NAIVE",
    modifiedAt: 100
  )

  let titleResult = await WorkspaceSearchEngine().search(query: "CREME", in: [note])
  let bodyResult = await WorkspaceSearchEngine().search(query: "NAIVE", in: [note])

  #expect(titleResult.first?.match.field == .title)
  #expect(titleResult.first?.match.location == 0)
  #expect(titleResult.first?.match.length == "Crème".utf16.count)
  #expect(bodyResult.first?.match.field == .body)
  #expect(bodyResult.first?.match.location == "α 👩‍💻 ".utf16.count)
  #expect(bodyResult.first?.match.length == "naïve".utf16.count)
  #expect(bodyResult.first?.snippet.contains("naïve") == true)
}

@Test func WorkspaceSearchOrdersSameCategoryByRecencyThenUUIDString() async {
  let sameDate = Date(timeIntervalSince1970: 200)
  let notes = [
    searchNote(
      "00000000-0000-0000-0000-000000000002",
      title: "Duplicate",
      body: "body",
      modifiedAt: sameDate
    ),
    searchNote(
      "00000000-0000-0000-0000-000000000003",
      title: "Duplicate",
      body: "body",
      modifiedAt: 300
    ),
    searchNote(
      "00000000-0000-0000-0000-000000000001",
      title: "Duplicate",
      body: "body",
      modifiedAt: sameDate
    ),
  ]

  let results = await WorkspaceSearchEngine().search(query: "duplicate", in: notes)

  #expect(results.map(\.noteID).map(\.uuidString) == [
    "00000000-0000-0000-0000-000000000003",
    "00000000-0000-0000-0000-000000000001",
    "00000000-0000-0000-0000-000000000002",
  ])
}

@Test func WorkspaceSearchHonorsResultLimitAndRejectsEmptyQueries() async {
  let notes = WorkspaceScaleFixtures.notes(count: 10)
  let engine = WorkspaceSearchEngine()

  let limited = await engine.search(query: "synthetic", in: notes, limit: 2)
  let empty = await engine.search(query: " \n\t", in: notes)
  let zero = await engine.search(query: "synthetic", in: notes, limit: 0)
  let negative = await engine.search(query: "synthetic", in: notes, limit: -1)

  #expect(limited.count == 2)
  #expect(empty.isEmpty)
  #expect(zero.isEmpty)
  #expect(negative.isEmpty)
}

@Test func WorkspaceSearchCreatesSingleLineUnicodeSafeBoundedSnippets() async {
  let before = String(repeating: "👩‍💻", count: 65)
  let after = String(repeating: "🧑🏽‍🚀", count: 65)
  let body = before + "\nCafé\n" + after
  let note = searchNote(
    "00000000-0000-0000-0000-000000000020",
    title: "Snippet fixture",
    body: body,
    modifiedAt: 100
  )

  let result = await WorkspaceSearchEngine().search(query: "CAFE", in: [note]).first

  #expect(result?.snippet.hasPrefix("…") == true)
  #expect(result?.snippet.hasSuffix("…") == true)
  #expect(result?.snippet.contains("Café") == true)
  #expect(result?.snippet.contains("\n") == false)
  #expect(result?.snippet.contains("\r") == false)
  #expect(result?.snippet.count ?? .max <= 120)
  #expect(result?.match.location == before.utf16.count + 1)
  #expect(result?.match.length == "Café".utf16.count)
}

@Test func WorkspaceSearchCancellationReturnsNoStalePartialResults() async {
  let notes = WorkspaceScaleFixtures.notes(count: 1_000)
  let task = Task {
    await Task.yield()
    return await WorkspaceSearchEngine().search(query: "synthetic", in: notes, limit: notes.count)
  }

  task.cancel()
  let results = await task.value

  #expect(results.isEmpty)
}

@Test func WorkspaceSearchIsRepeatableAndDoesNotMutateItsSnapshot() async {
  let notes = WorkspaceScaleFixtures.notes(count: 100)
  let original = notes
  let engine = WorkspaceSearchEngine()

  let first = await engine.search(query: "fixture", in: notes, limit: notes.count)
  let second = await engine.search(query: "fixture", in: notes, limit: notes.count)

  #expect(first == second)
  #expect(notes == original)
}

@Test func WorkspaceScaleFixturesContainExactDeterministicSizesAndRequiredCoverage() {
  for count in WorkspaceScaleFixtures.supportedCounts {
    let first = WorkspaceScaleFixtures.notes(count: count)
    let second = WorkspaceScaleFixtures.notes(count: count)

    #expect(first.count == count)
    #expect(first == second)
    #expect(Set(first.map(\.id)).count == count)
    #expect(first.contains { $0.title.contains("Café") })
    #expect(first.contains { $0.title.contains("NAÏVE") })
    #expect(first.contains { $0.title.contains("/") || $0.body.contains("[brackets]") })
    #expect(first.contains { $0.title.isEmpty })
    #expect(first.contains { $0.title == "Duplicate Fixture" })
    #expect(first.contains { $0.body.contains("\n") || $0.body.contains("\r") })
    #expect(first.contains { $0.richTextRTF != nil })
    #expect(first.allSatisfy { $0.body.contains("Synthetic fixture") })
  }
}

@Test func WorkspaceScaleSearchFindsEverySyntheticRecordDeterministically() async {
  let engine = WorkspaceSearchEngine()

  for count in WorkspaceScaleFixtures.supportedCounts {
    let notes = WorkspaceScaleFixtures.notes(count: count)
    let expectedIDs = notes
      .sorted {
        if $0.modifiedAt != $1.modifiedAt { return $0.modifiedAt > $1.modifiedAt }
        return $0.id.uuidString < $1.id.uuidString
      }
      .map(\.id)

    let first = await engine.search(query: "synthetic", in: notes, limit: count)
    let second = await engine.search(query: "synthetic", in: notes, limit: count)

    #expect(first.count == count)
    #expect(first.map(\.noteID) == expectedIDs)
    #expect(first.allSatisfy { $0.match.field == .body && $0.score == 1 })
    #expect(first == second)
  }
}

private func searchNote(
  _ id: String,
  title: String,
  body: String,
  modifiedAt: TimeInterval
) -> Note {
  searchNote(
    id,
    title: title,
    body: body,
    modifiedAt: Date(timeIntervalSince1970: modifiedAt)
  )
}

private func searchNote(
  _ id: String,
  title: String,
  body: String,
  modifiedAt: Date
) -> Note {
  Note(
    id: UUID(uuidString: id)!,
    title: title,
    body: body,
    createdAt: modifiedAt,
    modifiedAt: modifiedAt
  )
}

@Test func WorkspaceSearchBodyMatchRangeLocatesTheFoldedMatchInTheNoteBody() async {
  let body = "α 👩‍💻 first line\r\nsecond CAFÉ line"
  let note = searchNote(
    "00000000-0000-0000-0000-000000000030",
    title: "Unrelated title",
    body: body,
    modifiedAt: 100
  )

  let results = await WorkspaceSearchEngine().search(query: "  cafe \n", in: [note])
  let result = results.first

  #expect(results.count == 1)
  #expect(result?.match.field == .body)
  #expect(
    result?.bodyMatchRange(in: body, query: "  cafe \n")
      == NSRange(
        location: "α 👩‍💻 first line\r\nsecond ".utf16.count,
        length: "CAFÉ".utf16.count
      )
  )
}

@Test func WorkspaceSearchBodyMatchRangeRejectsTitleStaleAndUnaddressableMatches() {
  let titleResult = WorkspaceSearchResult(
    noteID: UUID(),
    displayTitle: "Café",
    snippet: "Café",
    match: WorkspaceSearchMatch(field: .title, location: 0, length: "Café".utf16.count),
    score: 4
  )
  #expect(titleResult.bodyMatchRange(in: "Café", query: "cafe") == nil)

  let bodyResult = WorkspaceSearchResult(
    noteID: UUID(),
    displayTitle: "Note",
    snippet: "cafe",
    match: WorkspaceSearchMatch(field: .body, location: 4, length: 4),
    score: 1
  )
  #expect(
    bodyResult.bodyMatchRange(in: "The cafe here", query: " cafe ")
      == NSRange(location: 4, length: 4)
  )
  #expect(bodyResult.bodyMatchRange(in: "The tea here", query: "cafe") == nil)
  #expect(bodyResult.bodyMatchRange(in: "caf", query: "cafe") == nil)
  #expect(bodyResult.bodyMatchRange(in: "The cafe here", query: " \n\t ") == nil)

  let clusterResult = WorkspaceSearchResult(
    noteID: UUID(),
    displayTitle: "Note",
    snippet: "cafe",
    match: WorkspaceSearchMatch(field: .body, location: 1, length: 4),
    score: 1
  )
  #expect(clusterResult.bodyMatchRange(in: "👨‍👩‍👧cafe", query: "cafe") == nil)
}

@Test func WorkspaceSearchBodyMatchRangeKeepsFoldedExpansionSpansAndRejectsStaleSpans() async {
  let body = "A ß line"
  let note = searchNote(
    "00000000-0000-0000-0000-000000000040",
    title: "Unrelated title",
    body: body,
    modifiedAt: 100
  )

  let results = await WorkspaceSearchEngine().search(query: "s", in: [note])
  let result = results.first

  #expect(results.count == 1)
  #expect(result?.match.field == .body)
  #expect(result?.match.location == 2)
  #expect(result?.match.length == "ß".utf16.count)
  #expect(
    result?.bodyMatchRange(in: body, query: "s") == NSRange(location: 2, length: 1)
  )
  #expect(result?.bodyMatchRange(in: "s A ß", query: "s") == nil)
  #expect(result?.bodyMatchRange(in: "A ☕ line", query: "s") == nil)

  let laterSpan = WorkspaceSearchResult(
    noteID: note.id,
    displayTitle: note.displayTitle,
    snippet: "",
    match: WorkspaceSearchMatch(field: .body, location: 5, length: 1),
    score: 1
  )
  #expect(laterSpan.bodyMatchRange(in: body, query: "s") == nil)
}

@Test func WorkspaceSearchASCIIBodyFindsFirstCaseFoldedHitAcrossLineBreaks() async {
  let engine = WorkspaceSearchEngine()
  let body = "Alpha beta\nGamma needle alpha"
  let note = searchNote(
    "00000000-0000-0000-0000-000000000050",
    title: "Unrelated title",
    body: body,
    modifiedAt: 100
  )

  let start = await engine.search(query: "ALPHA", in: [note])
  #expect(start.count == 1)
  #expect(start.first?.match.field == .body)
  #expect(start.first?.match.location == 0)
  #expect(start.first?.match.length == "Alpha".utf16.count)
  #expect(start.first?.score == 1)
  #expect(start.first?.snippet == "Alpha beta Gamma needle alpha")

  let acrossLines = await engine.search(query: "beta\nGAMMA", in: [note])
  #expect(acrossLines.first?.match.location == "Alpha ".utf16.count)
  #expect(acrossLines.first?.match.length == "beta\nGamma".utf16.count)
  #expect(acrossLines.first?.snippet == "Alpha beta Gamma needle alpha")

  let end = await engine.search(query: "needle", in: [note])
  #expect(end.first?.match.location == "Alpha beta\nGamma ".utf16.count)
  #expect(end.first?.match.length == "needle".utf16.count)
  #expect(
    end.first?.bodyMatchRange(in: body, query: "needle")
      == NSRange(location: "Alpha beta\nGamma ".utf16.count, length: "needle".utf16.count)
  )

  let miss = await engine.search(query: "absent", in: [note])
  #expect(miss.isEmpty)
}

@Test func WorkspaceSearchASCIIBodyPreflightRejectsNonmatchingAndEmptyBodies() async {
  let engine = WorkspaceSearchEngine()
  let empty = searchNote(
    "00000000-0000-0000-0000-000000000051",
    title: "Empty body",
    body: "",
    modifiedAt: 100
  )
  let noHit = searchNote(
    "00000000-0000-0000-0000-000000000052",
    title: "No hit",
    body: "alpha beta gamma",
    modifiedAt: 200
  )
  let endHit = searchNote(
    "00000000-0000-0000-0000-000000000053",
    title: "End hit",
    body: "alpha beta gamma ZETA",
    modifiedAt: 300
  )
  let largeMiss = searchNote(
    "00000000-0000-0000-0000-000000000054",
    title: "Large ASCII",
    body: String(repeating: "alpha beta gamma delta\n", count: 500),
    modifiedAt: 400
  )
  let notes = [empty, noHit, endHit]

  let miss = await engine.search(query: "delta", in: notes)
  let largeMissResult = await engine.search(query: "needle", in: [largeMiss])
  #expect(miss.isEmpty)
  #expect(largeMissResult.isEmpty)

  let hits = await engine.search(query: "zeta", in: notes)
  #expect(hits.map(\.noteID) == [endHit.id])
  #expect(hits.first?.match.location == "alpha beta gamma ".utf16.count)
  #expect(hits.first?.match.length == "ZETA".utf16.count)
}

@Test func WorkspaceSearchASCIIBodyMatchesFoldedNonASCIIQuery() async {
  let engine = WorkspaceSearchEngine()
  let body = "ASCII cafe line"
  let note = searchNote(
    "00000000-0000-0000-0000-000000000055",
    title: "Unrelated title",
    body: body,
    modifiedAt: 100
  )
  let missNote = searchNote(
    "00000000-0000-0000-0000-000000000056",
    title: "Unrelated title",
    body: "ASCII tea line",
    modifiedAt: 100
  )

  let accent = await engine.search(query: "CAFÉ", in: [note])
  #expect(accent.count == 1)
  #expect(accent.first?.match.field == .body)
  #expect(accent.first?.match.location == "ASCII ".utf16.count)
  #expect(accent.first?.match.length == "cafe".utf16.count)
  #expect(accent.first?.snippet == body)
  #expect(
    accent.first?.bodyMatchRange(in: body, query: "CAFÉ")
      == NSRange(location: "ASCII ".utf16.count, length: "cafe".utf16.count)
  )

  let miss = await engine.search(query: "CAFÉ", in: [missNote])
  #expect(miss.isEmpty)
}

@Test func WorkspaceSearchUnicodeBodyKeepsPerGraphemeSpansForExpansionsAndClusters() async {
  let engine = WorkspaceSearchEngine()

  let sharpS = searchNote(
    "00000000-0000-0000-0000-000000000060",
    title: "Unrelated title",
    body: "A Straße end",
    modifiedAt: 100
  )
  let expansion = await engine.search(query: "ss", in: [sharpS])
  #expect(expansion.first?.match.field == .body)
  #expect(expansion.first?.match.location == "A Stra".utf16.count)
  #expect(expansion.first?.match.length == "ß".utf16.count)

  let decomposedBody = "x cafe\u{301} needle"
  let decomposed = searchNote(
    "00000000-0000-0000-0000-000000000061",
    title: "Unrelated title",
    body: decomposedBody,
    modifiedAt: 100
  )
  let accent = await engine.search(query: "CAFÉ", in: [decomposed])
  #expect(accent.first?.match.location == 2)
  #expect(accent.first?.match.length == "cafe\u{301}".utf16.count)
  #expect(accent.first?.snippet == decomposedBody)

  let clusterBody = "👩‍💻 🧑🏽‍🚀 needlé tail"
  let cluster = searchNote(
    "00000000-0000-0000-0000-000000000062",
    title: "Unrelated title",
    body: clusterBody,
    modifiedAt: 100
  )
  let clusterHit = await engine.search(query: "needle", in: [cluster])
  #expect(clusterHit.first?.match.location == "👩‍💻 🧑🏽‍🚀 ".utf16.count)
  #expect(clusterHit.first?.match.length == "needlé".utf16.count)
  #expect(
    clusterHit.first?.bodyMatchRange(in: clusterBody, query: "needle")
      == NSRange(
        location: "👩‍💻 🧑🏽‍🚀 ".utf16.count,
        length: "needlé".utf16.count
      )
  )

  let longUnicode = searchNote(
    "00000000-0000-0000-0000-000000000063",
    title: "Long Unicode",
    body: String(repeating: "αβγ δεζ\n", count: 600),
    modifiedAt: 100
  )
  let longUnicodeMiss = await engine.search(query: "needle", in: [longUnicode])
  #expect(longUnicodeMiss.isEmpty)
}

@Test func WorkspaceSearchReadsCurrentContentForReusedUUIDAndTimestamp() async {
  let engine = WorkspaceSearchEngine()
  let id = "00000000-0000-0000-0000-000000000070"
  let timestamp = Date(timeIntervalSince1970: 1_000)

  let initial = searchNote(
    id,
    title: "First title",
    body: "prefix needle suffix",
    modifiedAt: timestamp
  )
  let found = await engine.search(query: "needle", in: [initial])
  #expect(found.map(\.noteID) == [initial.id])
  #expect(found.first?.match.field == .body)
  #expect(found.first?.match.location == "prefix ".utf16.count)

  let moved = searchNote(
    id,
    title: "First title",
    body: "moved later needle",
    modifiedAt: timestamp
  )
  let movedResult = await engine.search(query: "needle", in: [moved])
  #expect(movedResult.map(\.noteID) == [initial.id])
  #expect(movedResult.first?.match.location == "moved later ".utf16.count)

  let removed = searchNote(
    id,
    title: "First title",
    body: "prefix suffix",
    modifiedAt: timestamp
  )
  let removedResult = await engine.search(query: "needle", in: [removed])
  #expect(removedResult.isEmpty)

  let titleChanged = searchNote(
    id,
    title: "Needle now",
    body: "needle in body",
    modifiedAt: timestamp
  )
  let titleResult = await engine.search(query: "NEEDLE", in: [titleChanged])
  #expect(titleResult.first?.match.field == .title)
  #expect(titleResult.first?.match.location == 0)
  #expect(titleResult.first?.match.length == "Needle".utf16.count)
  #expect(titleResult.first?.score == 3)

  let exactTitle = searchNote(
    id,
    title: "needle",
    body: "body has needle",
    modifiedAt: timestamp
  )
  let exactResult = await engine.search(query: "needle", in: [exactTitle])
  #expect(exactResult.first?.match.field == .title)
  #expect(exactResult.first?.match.location == 0)
  #expect(exactResult.first?.score == 4)
}
