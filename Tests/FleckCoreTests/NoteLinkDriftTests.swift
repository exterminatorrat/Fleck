import Foundation
import Testing

@testable import FleckCore

private let driftTargetID = UUID(uuidString: "550E8400-E29B-41D4-A716-446655440000")!

@Test func NoteLinkDriftReportsOnlyLiveLinksWhoseLabelDisagrees() {
  let body = """
    Current [Launch checklist](fleck://note/\(driftTargetID)) and \
    Stale [Launch checklist](fleck://note/\(driftTargetID)) and \
    Gone [Launch checklist](fleck://note/\(UUID().uuidString))
    """
  let titles = NoteLinkTargetTitles(titlesByID: [driftTargetID: "Launch checklist"])

  let states = NoteLinkInspector.driftStates(in: body, titles: titles)

  #expect(states.count == 3)
  #expect(states[0].isLive)
  #expect(!states[0].isStale)
  #expect(states[1].isLive)
  #expect(!states[1].isStale)
  #expect(!states[2].isLive)
  #expect(!states[2].isStale)
}

@Test func NoteLinkDriftIgnoresSurroundingWhitespaceWhenComparingLabels() {
  let body = "[ Launch checklist ](fleck://note/\(driftTargetID))"
  let titles = NoteLinkTargetTitles(titlesByID: [driftTargetID: "Launch checklist"])

  let state = NoteLinkInspector.driftStates(in: body, titles: titles)[0]

  #expect(!state.isStale)
}

@Test func NoteLinkDriftDetectsARenamedTarget() {
  let body = "Ship it. [Launch checklist](fleck://note/\(driftTargetID)) covers signing."
  let titles = NoteLinkTargetTitles(titlesByID: [driftTargetID: "Launch Plan v3"])

  let state = NoteLinkInspector.driftStates(in: body, titles: titles)[0]

  #expect(state.isStale)
  #expect(state.currentTitle == "Launch Plan v3")
  #expect(state.link.label == "Launch checklist")
}

@Test func NoteLinkInspectorRelabelsOnlyStaleLabelsAndKeepsEverythingElse() {
  let otherID = UUID()
  let body = """
    Keep [Launch checklist](fleck://note/\(driftTargetID)) and \
    Fix [Old name](fleck://note/\(otherID)) and plain prose
    """
  let titles = NoteLinkTargetTitles(titlesByID: [
    driftTargetID: "Launch checklist",
    otherID: "New name",
  ])

  let result = NoteLinkInspector.relabeledBody(body, titles: titles)

  #expect(result.changedLinkCount == 1)
  #expect(
    result.body
      == """
      Keep [Launch checklist](fleck://note/\(driftTargetID)) and \
      Fix [New name](fleck://note/\(otherID)) and plain prose
      """
  )
  #expect(NoteLinkParser.links(in: result.body).map(\.targetNoteID) == [driftTargetID, otherID])
}

@Test func NoteLinkInspectorEscapesBracketsInRewrittenLabels() {
  let body = "[Old](fleck://note/\(driftTargetID))"
  let titles = NoteLinkTargetTitles(titlesByID: [driftTargetID: "Plan ] launch"])

  let result = NoteLinkInspector.relabeledBody(body, titles: titles)

  #expect(result.changedLinkCount == 1)
  #expect(
    result.body == NoteLinkFormatter.markdown(label: "Plan ] launch", targetNoteID: driftTargetID)
  )
  #expect(NoteLinkParser.links(in: result.body).first?.label == "Plan ] launch")
}

@Test func NoteLinkInspectorRelabelingIsIdempotent() {
  let body = "[Old](fleck://note/\(driftTargetID))"
  let titles = NoteLinkTargetTitles(titlesByID: [driftTargetID: "New"])

  let first = NoteLinkInspector.relabeledBody(body, titles: titles)
  let second = NoteLinkInspector.relabeledBody(first.body, titles: titles)

  #expect(first.changedLinkCount == 1)
  #expect(second.changedLinkCount == 0)
  #expect(second.body == first.body)
}

@Test func NoteLinkTargetTitlesResolveDisplayTitlesForUntitledNotes() {
  let note = Note(title: "   ", body: "First line of an untitled note")

  let titles = NoteLinkTargetTitles(notes: [note])

  #expect(titles.title(for: note.id) == note.displayTitle)
  #expect(titles.liveNoteIDs == [note.id])
}
