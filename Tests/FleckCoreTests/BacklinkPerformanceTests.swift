import Foundation
import Testing

@testable import FleckCore

@Test
func BacklinkPerformanceBuildsDenseDeterministicFixtures() async {
  for count in [10, 100, 1_000] {
    let fixture = BacklinkScaleFixture.notes(count: count, linksPerNote: 4)
    let start = ContinuousClock.now
    let index = await BacklinkIndexer().build(liveNotes: fixture)
    let milliseconds = backlinkPerformanceMilliseconds(since: start)

    #expect(fixture.count == count)
    #expect(index.incoming(to: BacklinkScaleFixture.noteID(at: 0)).count == 4)
    #expect(milliseconds.isFinite)
    print(
      "BacklinkPerformance note_count=" + String(count)
        + " duration_ms=" + String(format: "%.3f", milliseconds)
    )
  }
}

@Test
func BacklinkPerformanceIncrementalBodyEditInvalidatesOnlyDerivedContent() async {
  let fixture = BacklinkScaleFixture.notes(count: 100, linksPerNote: 4)
  let indexer = BacklinkIndexer()
  let first = await indexer.build(liveNotes: fixture)
  let targetID = BacklinkScaleFixture.noteID(at: 99)
  let sourceID = fixture[0].id
  var changed = fixture
  changed[0].body += " " + NoteLinkFormatter.markdown(label: "N99", targetNoteID: targetID)

  let second = await indexer.build(liveNotes: changed)
  let firstSource = first.incoming(to: targetID).first { $0.sourceNoteID == sourceID }
  let secondSource = second.incoming(to: targetID).first { $0.sourceNoteID == sourceID }

  #expect(first != second)
  #expect(firstSource == nil)
  #expect(secondSource?.referenceCount == 1)
}

private enum BacklinkScaleFixture {
  static func noteID(at index: Int) -> UUID {
    let suffix = String(repeating: "0", count: max(0, 12 - String(index).count)) + String(index)
    return UUID(uuidString: "00000000-0000-0000-0000-" + suffix)!
  }

  static func notes(count: Int, linksPerNote: Int) -> [Note] {
    precondition(count > linksPerNote)
    return (0..<count).map { index in
      let links = (1...linksPerNote).map { offset in
        let targetIndex = (index + offset) % count
        return NoteLinkFormatter.markdown(
          label: "N" + String(targetIndex),
          targetNoteID: noteID(at: targetIndex)
        )
      }.joined(separator: " ")
      return Note(
        id: noteID(at: index),
        title: "Synthetic backlink note " + String(index),
        body: links,
        modifiedAt: Date(timeIntervalSince1970: TimeInterval(index))
      )
    }
  }
}

private func backlinkPerformanceMilliseconds(since start: ContinuousClock.Instant) -> Double {
  let components = start.duration(to: .now).components
  return Double(components.seconds) * 1_000
    + Double(components.attoseconds) / 1_000_000_000_000_000
}
