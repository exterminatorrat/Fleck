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
