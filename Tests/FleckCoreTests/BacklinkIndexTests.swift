import Foundation
import Testing

@testable import FleckCore

@Test func BacklinkIndexerGroupsSourcesAndOrdersThemDeterministically() async throws {
  let target = Note(id: UUID(), title: "Target")
  let older = Note(
    id: UUID(),
    title: "Older",
    body: NoteLinkFormatter.markdown(label: "Target", targetNoteID: target.id),
    modifiedAt: Date(timeIntervalSince1970: 10)
  )
  let newer = Note(
    id: UUID(),
    title: "Newer",
    body: [
      NoteLinkFormatter.markdown(label: "Target", targetNoteID: target.id),
      NoteLinkFormatter.markdown(label: "Again", targetNoteID: target.id),
    ].joined(separator: " and "),
    modifiedAt: Date(timeIntervalSince1970: 20)
  )

  let index = await BacklinkIndexer().build(liveNotes: [target, older, newer])
  let incoming = index.incoming(to: target.id)

  #expect(incoming.map(\.sourceNoteID) == [newer.id, older.id])
  #expect(incoming.first?.referenceCount == 2)
  #expect(incoming.first?.excerpt.contains("Target") == true)
}

@Test func BacklinkIndexerDoesNotPublishSelfLinksOrMissingSources() async {
  let targetID = UUID()
  let sourceID = UUID()
  let target = Note(
    id: targetID,
    title: "Target",
    body: NoteLinkFormatter.markdown(label: "Self", targetNoteID: targetID)
  )
  let source = Note(
    id: sourceID,
    title: "Source",
    body: NoteLinkFormatter.markdown(label: "Target", targetNoteID: targetID)
  )
  let indexer = BacklinkIndexer()

  let first = await indexer.build(liveNotes: [target, source])
  #expect(first.incoming(to: targetID).map(\.sourceNoteID) == [sourceID])
  #expect(first.incoming(to: sourceID).isEmpty)

  let second = await indexer.build(liveNotes: [target])
  #expect(second.incoming(to: targetID).isEmpty)
}

@Test func BacklinkIndexerUsesCurrentMetadataWhenBodyIsUnchanged() async {
  let targetID = UUID()
  let sourceID = UUID()
  let folderID = UUID()
  let body = NoteLinkFormatter.markdown(label: "Target", targetNoteID: targetID)
  let target = Note(id: targetID, title: "Target")
  let firstSource = Note(
    id: sourceID,
    title: "Before rename",
    body: body,
    modifiedAt: Date(timeIntervalSince1970: 10)
  )
  let indexer = BacklinkIndexer()

  _ = await indexer.build(liveNotes: [target, firstSource])

  let renamedSource = Note(
    id: sourceID,
    title: "After rename",
    body: body,
    modifiedAt: Date(timeIntervalSince1970: 20),
    folderID: folderID
  )
  let index = await indexer.build(liveNotes: [target, renamedSource])
  let source = index.incoming(to: targetID).first

  #expect(source?.sourceDisplayTitle == "After rename")
  #expect(source?.sourceFolderID == folderID)
  #expect(source?.sourceModifiedAt == Date(timeIntervalSince1970: 20))
}

@Test func BacklinkIndexerInvalidatesCachedLinksWhenBodyChangesWithoutRevisionChange() async {
  let firstTargetID = UUID()
  let secondTargetID = UUID()
  let sourceID = UUID()
  let target = Note(id: firstTargetID, title: "First")
  let secondTarget = Note(id: secondTargetID, title: "Second")
  let firstBody = NoteLinkFormatter.markdown(label: "First", targetNoteID: firstTargetID)
  let secondBody = NoteLinkFormatter.markdown(label: "Second", targetNoteID: secondTargetID)
  let indexer = BacklinkIndexer()

  _ = await indexer.build(
    liveNotes: [target, secondTarget, Note(id: sourceID, body: firstBody, revision: 4)]
  )

  let changed = Note(id: sourceID, body: secondBody, revision: 4)
  let index = await indexer.build(liveNotes: [target, secondTarget, changed])

  #expect(index.incoming(to: firstTargetID).isEmpty)
  #expect(index.incoming(to: secondTargetID).map(\.sourceNoteID) == [sourceID])
}

@Test func BacklinkIndexerRestoresIncomingLinksByStableTargetUUID() async {
  let targetID = UUID()
  let source = Note(
    title: "Source",
    body: NoteLinkFormatter.markdown(label: "Target", targetNoteID: targetID)
  )
  let indexer = BacklinkIndexer()

  let withoutTarget = await indexer.build(liveNotes: [source])
  #expect(withoutTarget.incoming(to: targetID).map(\.sourceNoteID) == [source.id])

  let restoredTarget = Note(id: targetID, title: "Restored")
  let withTarget = await indexer.build(liveNotes: [restoredTarget, source])
  #expect(withTarget.incoming(to: targetID).map(\.sourceNoteID) == [source.id])
}

@Test func BacklinkIndexerOrdersEqualDatesByLowercaseUUID() async {
  let targetID = UUID()
  let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
  let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  let date = Date(timeIntervalSince1970: 10)
  let target = Note(id: targetID, title: "Target")
  let first = Note(
    id: firstID,
    body: NoteLinkFormatter.markdown(label: "Target", targetNoteID: targetID),
    modifiedAt: date
  )
  let second = Note(
    id: secondID,
    body: NoteLinkFormatter.markdown(label: "Target", targetNoteID: targetID),
    modifiedAt: date
  )

  let index = await BacklinkIndexer().build(liveNotes: [target, first, second])

  #expect(index.incoming(to: targetID).map(\.sourceNoteID) == [secondID, firstID])
}

@Test func BacklinkIndexerCancellationReturnsLastCompleteIndex() async {
  let targetID = UUID()
  let source = Note(
    title: "Source",
    body: NoteLinkFormatter.markdown(label: "Target", targetNoteID: targetID)
  )
  let indexer = BacklinkIndexer()
  let completed = await indexer.build(liveNotes: [source])
  let largeSnapshot = (0..<5_000).map { index in
    Note(
      title: "Note \(index)",
      body: NoteLinkFormatter.markdown(label: "Target", targetNoteID: targetID)
    )
  }

  let task = Task { await indexer.build(liveNotes: largeSnapshot) }
  task.cancel()
  let cancelled = await task.value

  #expect(cancelled == completed)
}
