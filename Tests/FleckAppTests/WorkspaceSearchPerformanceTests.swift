import Foundation
import FleckCore
import Testing

@testable import FleckApp

@Test @MainActor
func WorkspaceSearchPerformanceReportsWarmQueriesAndPaletteObservations() async throws {
  for count in WorkspaceSearchPerformanceFixtures.supportedCounts {
    let notes = WorkspaceSearchPerformanceFixtures.notes(count: count)
    let originalNotes = notes
    let engine = WorkspaceSearchEngine()
    _ = await engine.search(query: "Synthetic fixture", in: notes, limit: 50)

    var warmQuerySamples: [Double] = []
    for _ in 0..<25 {
      let start = ContinuousClock.now
      let results = await engine.search(query: "Synthetic fixture", in: notes, limit: 50)
      warmQuerySamples.append(workspaceSearchMilliseconds(since: start))
      #expect(!results.isEmpty)
      #expect(results.count <= 50)
      #expect(
        results.allSatisfy { result in
          notes.contains(where: { note in note.id == result.noteID })
        }
      )
    }

    let controller = WorkspaceSearchController()
    let presentStart = ContinuousClock.now
    controller.present()
    let palettePresentationMilliseconds = workspaceSearchMilliseconds(since: presentStart)

    let resultStart = ContinuousClock.now
    controller.setQuery("Synthetic fixture", in: notes)
    for _ in 0..<2_000 where controller.results.isEmpty {
      try? await Task.sleep(for: .milliseconds(1))
    }
    let paletteFirstResultMilliseconds = workspaceSearchMilliseconds(since: resultStart)

    #expect(controller.results.count <= 50)
    #expect(!controller.results.isEmpty)
    #expect(
      controller.results.allSatisfy { result in
        notes.contains(where: { note in note.id == result.noteID })
      }
    )
    #expect(controller.highlightedNoteID == controller.results.first?.noteID)
    #expect(notes == originalNotes)
    let paletteResultCount = controller.results.count
    controller.dismiss()

    let p50 = workspaceSearchPercentile(warmQuerySamples, percentile: 0.50)
    let p95 = workspaceSearchPercentile(warmQuerySamples, percentile: 0.95)
    #expect(p50 >= 0)
    #expect(p95 >= p50)
    #expect(presentationTimingIsFinite(palettePresentationMilliseconds))
    #expect(presentationTimingIsFinite(paletteFirstResultMilliseconds))
    print(
      "WorkspaceSearchPerformance count=" + String(count)
        + " warmQueryP50Ms=" + String(format: "%.3f", p50)
        + " warmQueryP95Ms=" + String(format: "%.3f", p95)
        + " palettePresentMs=" + String(format: "%.3f", palettePresentationMilliseconds)
        + " paletteFirstResultMs=" + String(format: "%.3f", paletteFirstResultMilliseconds)
        + " resultCount=" + String(paletteResultCount)
    )
  }
}

private func workspaceSearchMilliseconds(since start: ContinuousClock.Instant) -> Double {
  let components = start.duration(to: .now).components
  return Double(components.seconds) * 1_000
    + Double(components.attoseconds) / 1_000_000_000_000_000
}

private func workspaceSearchPercentile(_ samples: [Double], percentile: Double) -> Double {
  let sorted = samples.sorted()
  let rank = max(0, min(sorted.count - 1, Int(ceil(Double(sorted.count) * percentile)) - 1))
  return sorted[rank]
}

private func presentationTimingIsFinite(_ milliseconds: Double) -> Bool {
  milliseconds.isFinite && milliseconds >= 0
}

// FleckAppTests cannot depend on FleckCoreTests, so this preserves the accepted
// scale fixture data locally rather than changing test-target dependencies.
private enum WorkspaceSearchPerformanceFixtures {
  static let supportedCounts = [10, 100, 1_000]

  static func notes(count: Int) -> [Note] {
    precondition(supportedCounts.contains(count))

    return (0..<count).map { index in
      let variant = index % 10
      let title: String
      let body: String
      let richTextRTF: Data?

      switch variant {
      case 0:
        title = "Café Fixture " + String(index)
        body = "Synthetic fixture café résumé line " + String(index)
          + "\nSecond line • punctuation!"
        richTextRTF = nil
      case 1:
        title = "NAÏVE Fixture " + String(index)
        body = "Synthetic fixture naïve façade — data " + String(index)
        richTextRTF = nil
      case 2:
        title = "Punctuation / Fixture #" + String(index) + "!"
        body = "Synthetic fixture [brackets] {braces} (parentheses); line "
          + String(index) + "."
        richTextRTF = nil
      case 3:
        title = ""
        body = "Untitled Fixture Header " + String(index)
          + "\nSynthetic fixture body line " + String(index) + "\nThird line."
        richTextRTF = nil
      case 4, 5:
        title = "Duplicate Fixture"
        body = "Synthetic fixture duplicate body " + String(index)
        richTextRTF = nil
      case 6:
        title = "RTF Fixture " + String(index)
        body = "Synthetic fixture formatted body " + String(index)
        richTextRTF = Data(
          ("{\\rtf1\\ansi\\b Synthetic fixture " + String(index) + "}").utf8
        )
      case 7:
        title = "Unicode 東京 Fixture " + String(index)
        body = "Synthetic fixture emoji 👩‍💻 " + String(index)
        richTextRTF = nil
      case 8:
        title = "Case Fixture " + String(index)
        body = "Synthetic fixture CASE token " + String(index)
        richTextRTF = nil
      default:
        title = "Multiline Fixture " + String(index)
        body = "Synthetic fixture first line " + String(index)
          + "\r\nsecond line\tvalue"
        richTextRTF = nil
      }

      return Note(
        id: id(for: index),
        title: title,
        body: body,
        richTextRTF: richTextRTF,
        createdAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(index)),
        modifiedAt: Date(timeIntervalSince1970: 1_800_100_000 + Double(index))
      )
    }
  }

  private static func id(for index: Int) -> UUID {
    let value = UInt64(index)
    return UUID(
      uuid: (
        0xF1,
        0xEC,
        0x6B,
        0x00,
        0xA1,
        0x00,
        0x40,
        0x00,
        0x80,
        0x00,
        0x00,
        0x00,
        UInt8((value >> 16) & 0xFF),
        UInt8((value >> 8) & 0xFF),
        UInt8(value & 0xFF),
        0x00
      )
    )
  }
}
