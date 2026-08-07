import Foundation
import FleckCore
import Testing

@testable import FleckApp

@Test @MainActor
func WorkspaceSearchPresentationRejectsWhitespaceAndKeepsSelectionOutOfRecomputation() async {
  let first = workspaceSearchTestNote("00000000-0000-0000-0000-000000000001", title: "First")
  let second = workspaceSearchTestNote("00000000-0000-0000-0000-000000000002", title: "Second")
  var activated: [UUID] = []
  let controller = WorkspaceSearchController(searchOperation: { _, notes, _ in
    notes.map(workspaceSearchTestResult)
  })

  controller.present()
  controller.setQuery(" \n\t", in: [first, second])
  await settleWorkspaceSearch()

  #expect(controller.results.isEmpty)
  #expect(controller.highlightedNoteID == nil)
  #expect(
    !controller.activateHighlighted(currentNoteIDs: Set([first.id, second.id])) {
      activated.append($0)
    }
  )
  #expect(activated.isEmpty)
}

@Test @MainActor
func WorkspaceSearchPresentationNavigatesBoundariesByStableUUID() async {
  let notes = [
    workspaceSearchTestNote("00000000-0000-0000-0000-000000000001", title: "One"),
    workspaceSearchTestNote("00000000-0000-0000-0000-000000000002", title: "Two"),
    workspaceSearchTestNote("00000000-0000-0000-0000-000000000003", title: "Three"),
  ]
  let controller = WorkspaceSearchController(searchOperation: { _, notes, _ in
    notes.map(workspaceSearchTestResult)
  })

  controller.present()
  controller.setQuery("anything", in: notes)
  await settleWorkspaceSearch()

  #expect(controller.highlightedNoteID == notes[0].id)
  controller.moveHighlight(.down)
  #expect(controller.highlightedNoteID == notes[1].id)
  controller.moveHighlight(.down)
  #expect(controller.highlightedNoteID == notes[2].id)
  controller.moveHighlight(.down)
  #expect(controller.highlightedNoteID == notes[2].id)
  controller.moveHighlight(.up)
  #expect(controller.highlightedNoteID == notes[1].id)
  controller.moveHighlight(.up)
  #expect(controller.highlightedNoteID == notes[0].id)
  controller.moveHighlight(.up)
  #expect(controller.highlightedNoteID == notes[0].id)
}

@Test @MainActor
func WorkspaceSearchPresentationGuardsRacesAndPreservesUUIDAcrossReordering() async throws {
  let first = workspaceSearchTestNote("00000000-0000-0000-0000-000000000001", title: "First")
  let second = workspaceSearchTestNote("00000000-0000-0000-0000-000000000002", title: "Second")
  let third = workspaceSearchTestNote("00000000-0000-0000-0000-000000000003", title: "Third")
  let operation: WorkspaceSearchController.SearchOperation = { query, notes, _ in
    if query == "old" {
      try? await Task.sleep(for: .milliseconds(40))
      return [workspaceSearchTestResult(first)]
    }
    return notes.map(workspaceSearchTestResult)
  }
  let controller = WorkspaceSearchController(searchOperation: operation)

  controller.present()
  controller.setQuery("old", in: [first, second, third])
  controller.setQuery("new", in: [first, second, third])
  try await Task.sleep(for: .milliseconds(80))
  await settleWorkspaceSearch()

  #expect(controller.results.map(\.noteID) == [first.id, second.id, third.id])
  controller.moveHighlight(.down)
  #expect(controller.highlightedNoteID == second.id)

  controller.refresh(in: [third, second, first])
  await settleWorkspaceSearch()
  #expect(controller.highlightedNoteID == second.id)

  controller.refresh(in: [third, first])
  await settleWorkspaceSearch()
  #expect(controller.highlightedNoteID == third.id)
}

@Test @MainActor
func WorkspaceSearchPresentationInvalidatesResultsDuringRefresh() async throws {
  let first = workspaceSearchTestNote("00000000-0000-0000-0000-000000000001", title: "First")
  let second = workspaceSearchTestNote("00000000-0000-0000-0000-000000000002", title: "Second")
  let notes = [first, second]
  let operation: WorkspaceSearchController.SearchOperation = { query, _, _ in
    if query == "new" {
      try? await Task.sleep(for: .milliseconds(80))
      return [workspaceSearchTestResult(second)]
    }
    return [workspaceSearchTestResult(first)]
  }
  let controller = WorkspaceSearchController(searchOperation: operation)

  controller.present()
  controller.setQuery("old", in: notes)
  await settleWorkspaceSearch()
  #expect(controller.results.map(\.noteID) == [first.id])

  controller.setQuery("new", in: notes)
  #expect(!controller.resultsAreCurrent)
  var activated: [UUID] = []
  #expect(
    !controller.activateResult(
      first.id,
      currentNoteIDs: Set(notes.map(\.id)),
      activate: { activated.append($0) }
    )
  )
  #expect(activated.isEmpty)
  #expect(controller.isPresented)

  try await Task.sleep(for: .milliseconds(100))
  await settleWorkspaceSearch()
  #expect(controller.resultsAreCurrent)
  #expect(controller.results.map(\.noteID) == [second.id])
}

@Test @MainActor
func WorkspaceSearchPresentationActivatesOnceAndRejectsDeletedResults() async {
  let first = workspaceSearchTestNote("00000000-0000-0000-0000-000000000001", title: "First")
  let second = workspaceSearchTestNote("00000000-0000-0000-0000-000000000002", title: "Second")
  let third = workspaceSearchTestNote("00000000-0000-0000-0000-000000000003", title: "Third")
  let notes = [first, second, third]
  let controller = WorkspaceSearchController(searchOperation: { _, notes, _ in
    notes.map(workspaceSearchTestResult)
  })

  controller.present()
  controller.setQuery("anything", in: notes)
  await settleWorkspaceSearch()
  controller.moveHighlight(.down)

  var activated: [UUID] = []
  #expect(
    controller.activateHighlighted(currentNoteIDs: Set(notes.map(\.id))) {
      activated.append($0)
    }
  )
  #expect(
    !controller.activateHighlighted(currentNoteIDs: Set(notes.map(\.id))) {
      activated.append($0)
    }
  )
  #expect(activated == [second.id])
  #expect(!controller.isPresented)

  controller.present()
  controller.setQuery("anything", in: notes)
  await settleWorkspaceSearch()
  controller.moveHighlight(.down)
  #expect(
    !controller.activateHighlighted(currentNoteIDs: Set([first.id, third.id])) {
      activated.append($0)
    }
  )
  #expect(activated == [second.id])
  #expect(controller.isPresented)
}

@Test @MainActor
func WorkspaceSearchPresentationActivatesChosenResultExactlyOnceAndRejectsDeletedIDs() async {
  let first = workspaceSearchTestNote("00000000-0000-0000-0000-000000000001", title: "First")
  let second = workspaceSearchTestNote("00000000-0000-0000-0000-000000000002", title: "Second")
  let third = workspaceSearchTestNote("00000000-0000-0000-0000-000000000003", title: "Third")
  let notes = [first, second, third]
  let controller = WorkspaceSearchController(searchOperation: { _, notes, _ in
    notes.map(workspaceSearchTestResult)
  })

  controller.present()
  controller.setQuery("anything", in: notes)
  await settleWorkspaceSearch()

  var activated: [UUID] = []
  #expect(
    controller.activateResult(
      second.id,
      currentNoteIDs: Set(notes.map(\.id)),
      activate: { activated.append($0) }
    )
  )
  #expect(activated == [second.id])
  #expect(!controller.isPresented)
  #expect(
    !controller.activateResult(
      second.id,
      currentNoteIDs: Set(notes.map(\.id)),
      activate: { activated.append($0) }
    )
  )
  #expect(activated == [second.id])

  controller.present()
  controller.setQuery("anything", in: notes)
  await settleWorkspaceSearch()
  #expect(
    !controller.activateResult(
      second.id,
      currentNoteIDs: Set([first.id, third.id]),
      activate: { activated.append($0) }
    )
  )
  #expect(activated == [second.id])
  #expect(controller.isPresented)
}

private func workspaceSearchTestNote(_ id: String, title: String, body: String = "body") -> Note {
  Note(id: UUID(uuidString: id)!, title: title, body: body)
}

private func workspaceSearchTestResult(_ note: Note) -> WorkspaceSearchResult {
  WorkspaceSearchResult(
    noteID: note.id,
    displayTitle: note.displayTitle,
    snippet: note.body,
    match: WorkspaceSearchMatch(field: .title, location: 0, length: 1),
    score: 1
  )
}

@MainActor
private func settleWorkspaceSearch() async {
  for _ in 0..<20 {
    await Task.yield()
  }
}
