#if os(macOS)
  import FleckCore
  import Foundation
  import Testing

  @testable import FleckApp

  @Suite("AgentActivityLineDiff")
  struct AgentActivityLineDiffTests {
    @Test func unchangedTextKeepsContextWithoutRemovalOrAddition() throws {
      let lines = try #require(
        AgentActivityLineDiff.lines(before: "alpha\nbeta", after: "alpha\nbeta")
      )

      #expect(lines == [
        AgentActivityDiffLine(kind: .unchanged, text: "alpha"),
        AgentActivityDiffLine(kind: .unchanged, text: "beta"),
      ])
      #expect(lines.map(\.marker) == [" ", " "])
    }

    @Test func insertionMarksOnlyTheAddedLine() throws {
      let lines = try #require(
        AgentActivityLineDiff.lines(
          before: "alpha\ngamma",
          after: "alpha\nbeta\ngamma"
        )
      )

      #expect(lines.map(\.kind) == [.unchanged, .added, .unchanged])
      #expect(lines.map(\.text) == ["alpha", "beta", "gamma"])
      #expect(lines.map(\.marker) == [" ", "+", " "])
    }

    @Test func appendMarksTheNewTextAsAdded() throws {
      let lines = try #require(
        AgentActivityLineDiff.lines(before: "", after: "appended")
      )

      #expect(lines == [AgentActivityDiffLine(kind: .added, text: "appended")])
    }

    @Test func deletionMarksOnlyTheRemovedLine() throws {
      let lines = try #require(
        AgentActivityLineDiff.lines(
          before: "alpha\nbeta\ngamma",
          after: "alpha\ngamma"
        )
      )

      #expect(lines.map(\.kind) == [.unchanged, .removed, .unchanged])
      #expect(lines.map(\.text) == ["alpha", "beta", "gamma"])
      #expect(lines.map(\.marker) == [" ", "-", " "])
    }

    @Test func removalOfAllTextMarksEveryLineAsRemoved() throws {
      let lines = try #require(
        AgentActivityLineDiff.lines(before: "alpha\nbeta", after: "")
      )

      #expect(lines.map(\.kind) == [.removed, .removed])
      #expect(lines.map(\.text) == ["alpha", "beta"])
    }

    @Test func replacementMarksRemovedAndAddedLinesAroundUnchangedContext() throws {
      let lines = try #require(
        AgentActivityLineDiff.lines(
          before: "alpha\nold\ngamma",
          after: "alpha\nnew\ngamma"
        )
      )

      #expect(lines.map(\.kind) == [.unchanged, .removed, .added, .unchanged])
      #expect(lines.map(\.text) == ["alpha", "old", "new", "gamma"])
      #expect(lines.map(\.marker) == [" ", "-", "+", " "])
    }

    @Test func addingATrailingNewlineMarksAnAddedEmptyLine() throws {
      let lines = try #require(
        AgentActivityLineDiff.lines(before: "alpha", after: "alpha\n")
      )

      #expect(lines.map(\.kind) == [.unchanged, .added])
      #expect(lines.map(\.text) == ["alpha", ""])
      #expect(lines.map(\.marker) == [" ", "+"])
    }

    @Test func removingATrailingNewlineMarksARemovedEmptyLine() throws {
      let lines = try #require(
        AgentActivityLineDiff.lines(before: "alpha\n", after: "alpha")
      )

      #expect(lines.map(\.kind) == [.unchanged, .removed])
      #expect(lines.map(\.text) == ["alpha", ""])
      #expect(lines.map(\.marker) == [" ", "-"])
    }

    @Test func matchingTrailingNewlinesRemainUnchanged() throws {
      let lines = try #require(
        AgentActivityLineDiff.lines(before: "alpha\n", after: "alpha\n")
      )

      #expect(lines.map(\.kind) == [.unchanged, .unchanged])
      #expect(lines.map(\.text) == ["alpha", ""])
    }

    @Test func blankLinesStayVisibleAsContextOrChanges() throws {
      let lines = try #require(
        AgentActivityLineDiff.lines(
          before: "alpha\n\nbeta",
          after: "alpha\nbeta"
        )
      )

      #expect(lines.map(\.kind) == [.unchanged, .removed, .unchanged])
      #expect(lines.map(\.text) == ["alpha", "", "beta"])
      #expect(lines.map(\.marker) == [" ", "-", " "])
    }

    @Test func emptyBeforeAndAfterProduceNoDiffLines() throws {
      let lines = try #require(AgentActivityLineDiff.lines(before: "", after: ""))

      #expect(lines.isEmpty)
    }

    @Test func lineEndingsAreNormalizedBeforeDiffing() throws {
      let lines = try #require(
        AgentActivityLineDiff.lines(before: "alpha\r\nbeta", after: "alpha\nbeta")
      )

      #expect(lines.map(\.kind) == [.unchanged, .unchanged])
      #expect(lines.map(\.text) == ["alpha", "beta"])
    }

    @Test func oversizedPatchesSkipDiffingInsteadOfGrowingUnbounded() throws {
      let oversized = Array(repeating: "line", count: 201).joined(separator: "\n")
      #expect(AgentActivityLineDiff.lines(before: oversized, after: oversized) == nil)

      let atLimit = Array(repeating: "line", count: 200).joined(separator: "\n")
      #expect(
        AgentActivityLineDiff.lines(before: atLimit, after: atLimit)?.count == 200
      )
    }

    @Test func oversizedUTF8PayloadsSkipDiffingEvenUnderTheLineCap() throws {
      let hugeSingleLine = String(repeating: "x", count: 2 * 1024 * 1024)

      #expect(AgentActivityLineDiff.lines(before: "", after: hugeSingleLine) == nil)
      #expect(AgentActivityLineDiff.lines(before: hugeSingleLine, after: "x") == nil)
    }

    @Test func markersAndLabelsIdentifyLineKindWithoutColor() {
      #expect(AgentActivityDiffLine(kind: .unchanged, text: "alpha").marker == " ")
      #expect(AgentActivityDiffLine(kind: .removed, text: "old").marker == "-")
      #expect(AgentActivityDiffLine(kind: .added, text: "new").marker == "+")
      #expect(
        AgentActivityDiffLine(kind: .unchanged, text: "alpha").accessibilityLabel
          == "Unchanged: alpha"
      )
      #expect(
        AgentActivityDiffLine(kind: .removed, text: "old").accessibilityLabel
          == "Removed: old"
      )
      #expect(
        AgentActivityDiffLine(kind: .added, text: "new").accessibilityLabel
          == "Added: new"
      )
      #expect(
        AgentActivityDiffLine(kind: .removed, text: "").accessibilityLabel
          == "Removed empty line"
      )
    }

    @Test func activityRowAttachesDiffAndPreservesRecordedText() throws {
      let note = Note(title: "Launch", body: "alpha\nnew")
      let record = makeRecord(
        note: note,
        before: "alpha\nold",
        after: "alpha\nnew"
      )

      let row = AgentActivityRowPresentation(
        record: record,
        activeNote: note,
        activeProfileIDs: []
      )

      #expect(row.beforeText == "alpha\nold")
      #expect(row.afterText == "alpha\nnew")
      let diffLines = try #require(row.diffLines)
      #expect(diffLines.map(\.kind) == [.unchanged, .removed, .added])
      #expect(row.canUndo)
    }

    @Test func activityDiffUsesMarkersAndLabelsRatherThanColorAlone() throws {
      let sourceRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/FleckApp")
      let activity = try String(
        contentsOf: sourceRoot.appendingPathComponent("AgentActivityView.swift"),
        encoding: .utf8
      )

      #expect(activity.contains("Text(line.marker)"))
      #expect(activity.contains(".accessibilityLabel(line.accessibilityLabel)"))
      #expect(activity.contains("theme.color(.error)"))
      #expect(activity.contains("theme.color(.success)"))
      #expect(activity.contains("too large to display as a line diff"))
    }

    private func makeRecord(
      note: Note,
      before: String,
      after: String
    ) -> AgentActivityRecord {
      let changeID = UUID()
      let transaction = PreparedAgentTransaction(
        changeID: changeID,
        noteID: note.id,
        noteTitle: note.title,
        actor: .localUser,
        operationID: UUID(),
        createdAt: Date(),
        operation: .replaceLines,
        patch: AgentTextPatch(
          beforeText: before,
          afterText: after,
          range: NSRange(location: 0, length: (before as NSString).length),
          prefixContext: "",
          suffixContext: ""
        ),
        previousRevision: 0,
        resultingRevision: 1,
        resultingBodySHA256: ""
      )
      return AgentActivityRecord(
        transaction: transaction,
        receipt: AgentWriteReceipt(
          changeID: changeID,
          noteID: note.id,
          previousRevision: 0,
          resultingRevision: 1
        )
      )
    }
  }
#endif
