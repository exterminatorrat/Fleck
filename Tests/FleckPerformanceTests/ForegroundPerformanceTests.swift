import AppKit
import Combine
import CryptoKit
import Darwin
import FleckCore
import SwiftUI
import Testing

@testable import FleckApp

private let performanceOptIn = ProcessInfo.processInfo.environment["FLECK_PERF_RUN"] == "1"
private let measurementCount = 9
private let warmupCount = 1

#if DEBUG
private let compiledConfiguration = "debug"
#else
private let compiledConfiguration = "release"
#endif

private let benchmarkCaseIDs: Set<String> = [
  "editor.typing.1KiB",
  "editor.typing.64KiB",
  "editor.selection.1KiB",
  "editor.selection.64KiB",
  "state.noop.notes.10",
  "state.noop.notes.100",
  "state.noop.notes.1000",
  "state.body_rtf.notes.10",
  "state.body_rtf.notes.100",
  "state.body_rtf.notes.1000",
  "state.body_only.notes.10",
  "state.body_only.notes.100",
  "state.body_only.notes.1000",
  "state.rtf_only.notes.10",
  "state.rtf_only.notes.100",
  "state.rtf_only.notes.1000",
  "state.title_only.notes.10",
  "state.title_only.notes.100",
  "state.title_only.notes.1000",
  "state.body_rtf_64KiB.notes.10",
  "state.body_rtf_64KiB.notes.100",
  "state.body_rtf_64KiB.notes.1000",
  "switch.identity.first_mount",
  "switch.identity.warm",
  "store.one_note_save.notes.10",
  "store.one_note_save.notes.100",
  "store.one_note_save.notes.1000",
  "store.unchanged_snapshot.notes.10",
  "store.unchanged_snapshot.notes.100",
  "store.unchanged_snapshot.notes.1000",
  "store.metadata_only.notes.10",
  "store.metadata_only.notes.100",
  "store.metadata_only.notes.1000",
  "commit.app_state_only.notes.10",
  "commit.app_state_only.notes.100",
  "commit.app_state_only.notes.1000"
]

private enum PerformanceHarnessError: Error {
  case invalidRunEnvironment
  case missingEditor
  case missingFormattingState
  case processCPUUnavailable
  case invalidMeasurement
}

private enum SelectedContentWorkload: String, CaseIterable {
  case noOp = "noop"
  case bodyAndRTF = "body_rtf"
  case bodyOnly = "body_only"
  case richTextOnly = "rtf_only"
  case titleOnly = "title_only"
  case largeBodyAndRTF = "body_rtf_64KiB"
}

private struct RunMetadata {
  let configuration: String
  let buildSystem: String
  let swiftVersion: String
  let macOSVersion: String
  let architecture: String
}

private struct BaselineReceipt: Decodable {
  let schemaVersion: Int
  let baselineSourceCommit: String
  let configuration: String
  let buildSystem: String
  let testabilityEnabled: Bool
  let cases: [BaselineCase]
}

struct BaselineCase: Decodable {
  let caseID: String
  let baselineMedianMilliseconds: Decimal
  let medianNoiseMarginMilliseconds: Decimal
  let baselineP95Milliseconds: Decimal
  let p95NoiseMarginMilliseconds: Decimal
  let baselineProcessCPUSeconds: Decimal
  let cpuNoiseMarginSeconds: Decimal
}

private struct MeasuredAction {
  let perform: @MainActor () async throws -> Void
  let verify: @MainActor () async throws -> Void
  let counters: @MainActor () -> [String: Int]
  let quiesce: @MainActor () async -> Void
  let cleanup: @MainActor () async -> Void
}

struct RawMeasurement {
  let caseID: String
  let scope: String
  let repetitions: Int
  let warmups: Int
  let medianNanoseconds: Int64
  let p95Nanoseconds: Int64
  let minimumNanoseconds: Int64
  let maximumNanoseconds: Int64
  let processCPUMicroseconds: Int64
  let counters: [String: Int]

  var medianMilliseconds: Double { Double(medianNanoseconds) / 1_000_000 }
  var p95Milliseconds: Double { Double(p95Nanoseconds) / 1_000_000 }
  var minimumMilliseconds: Double { Double(minimumNanoseconds) / 1_000_000 }
  var maximumMilliseconds: Double { Double(maximumNanoseconds) / 1_000_000 }
  var processCPUSeconds: Double { Double(processCPUMicroseconds) / 1_000_000 }
}

private struct PerformanceRecord: Encodable {
  let schemaVersion: Int
  let caseID: String
  let scope: String
  let optIn: Bool
  let configuration: String
  let buildSystem: String
  let testabilityEnabled: Bool
  let swiftVersion: String
  let macOSVersion: String
  let architecture: String
  let repetitions: Int
  let warmups: Int
  let errors: Int
  let correctness: String
  let medianMilliseconds: Double
  let p95Milliseconds: Double
  let rangeMilliseconds: [Double]
  let processCPUSeconds: Double
  let processCPUSecondsPerOperation: Double
  let counters: [String: Int]
  let baselineStatus: String
}

@MainActor
private final class PublicationProbe {
  private var cancellable: AnyCancellable?
  private(set) var count = 0

  init(state: AppState) {
    cancellable = state.objectWillChange.sink { [weak self] in
      self?.count += 1
    }
  }
}

@MainActor
private struct HostedPanelFixture {
  let root: URL
  let state: AppState
  let commands: EditorCommands
  let window: NSWindow
  let host: NSHostingView<AnyView>
  let textView: ListAwareTextView

  func quiesce() async {
    await state.quiescePersistenceForTesting()
  }

  func cleanup() async {
    closeHostedEditor(window)
    await quiesce()
    try? FileManager.default.removeItem(at: root)
  }
}

@MainActor
private struct PerformanceThemeRoot<Content: View>: View {
  @ObservedObject private var state: AppState
  private let content: Content

  init(state: AppState, @ViewBuilder content: () -> Content) {
    _state = ObservedObject(wrappedValue: state)
    self.content = content()
  }

  var body: some View {
    content.environmentObject(state).fleckTheme(state)
  }
}

@Suite(.serialized)
struct ForegroundPerformanceTests {
  @Test(.enabled(if: performanceOptIn))
  @MainActor
  func editorTypingMeasuresSmallAndLargeSyntheticNotes() async throws {
    let metadata = try runMetadata()
    for (caseID, size) in [("editor.typing.1KiB", 1_024), ("editor.typing.64KiB", 65_536)] {
      let measurement = try await measureFreshActions(
        caseID: caseID,
        scope: "editor.insert_callback_and_layout",
        prepare: { try await makeEditorTypingAction(byteCount: size) }
      )
      recordAndCheck(measurement, metadata: metadata)
    }
  }

  @Test(.enabled(if: performanceOptIn))
  @MainActor
  func editorSelectionMeasuresCollapsedCaretFormattingWithoutContentChanges() async throws {
    let metadata = try runMetadata()
    for (caseID, size) in [
      ("editor.selection.1KiB", 1_024),
      ("editor.selection.64KiB", 65_536)
    ] {
      let measurement = try await measureFreshActions(
        caseID: caseID,
        scope: "editor.collapsed_caret_formatting",
        prepare: { try await makeEditorSelectionAction(byteCount: size) }
      )
      recordAndCheck(measurement, metadata: metadata)
    }
  }

  @Test(.enabled(if: performanceOptIn))
  @MainActor
  func selectedContentMeasuresMutationsAtThreeWorkspaceSizes() async throws {
    let metadata = try runMetadata()
    for workload in SelectedContentWorkload.allCases {
      for noteCount in [10, 100, 1_000] {
        let measurement = try await measureFreshActions(
          caseID: "state.\(workload.rawValue).notes.\(noteCount)",
          scope: workload == .largeBodyAndRTF
            ? "app_state.selected_content.64KiB"
            : "app_state.selected_content",
          prepare: {
            try await makeSelectedContentAction(
              noteCount: noteCount,
              workload: workload
            )
          }
        )
        recordAndCheck(measurement, metadata: metadata)
      }
    }
  }

  @Test(.enabled(if: performanceOptIn))
  @MainActor
  func identityBoundedHostedSwitchMeasuresFirstMountAndWarmAlternation() async throws {
    let metadata = try runMetadata()
    let notes = try switchNotes()
    let firstMount = try await measureFreshActions(
      caseID: "switch.identity.first_mount",
      scope: "hosted_editor_identity_switch",
      prepare: { try await makeFirstMountSwitchAction(notes: notes) }
    )
    recordAndCheck(firstMount, metadata: metadata)

    let warmSwitch = try await measureReusableAction(
      caseID: "switch.identity.warm",
      scope: "hosted_editor_identity_switch",
      prepare: { try await makeWarmSwitchAction(notes: notes) }
    )
    recordAndCheck(warmSwitch, metadata: metadata)
  }

  @Test(.enabled(if: performanceOptIn))
  @MainActor
  func oneNoteLocalStoreSavesReloadAtThreeWorkspaceSizes() async throws {
    let metadata = try runMetadata()
    for noteCount in [10, 100, 1_000] {
      let changed = try await measureLocalStoreSaves(noteCount: noteCount)
      recordAndCheck(changed, metadata: metadata)
      let unchanged = try await measureSnapshotSaves(noteCount: noteCount, metadataOnly: false)
      recordAndCheck(unchanged, metadata: metadata)
      let metadataOnly = try await measureSnapshotSaves(noteCount: noteCount, metadataOnly: true)
      recordAndCheck(metadataOnly, metadata: metadata)
    }
  }

  @Test(.enabled(if: performanceOptIn))
  @MainActor
  func appStateCommitOnlyMeasuresDurableCommitNotMCPRequestEndToEnd() async throws {
    let metadata = try runMetadata()
    for noteCount in [10, 100, 1_000] {
      let measurement = try await measureAppStateCommits(noteCount: noteCount)
      recordAndCheck(measurement, metadata: metadata)
    }
  }
}

@MainActor
private func runMetadata() throws -> RunMetadata {
  let environment = ProcessInfo.processInfo.environment
  guard environment["FLECK_PERF_RUN"] == "1",
    environment["FLECK_PERF_CONFIGURATION"] == compiledConfiguration,
    let buildSystem = environment["FLECK_PERF_BUILD_SYSTEM"],
    ["default", "native", "swiftbuild", "xcode"].contains(buildSystem),
    let swiftVersion = environment["FLECK_PERF_SWIFT_VERSION"],
    !swiftVersion.isEmpty,
    swiftVersion.unicodeScalars.allSatisfy({
      CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .()+_-")
        .contains($0)
    })
  else {
    throw PerformanceHarnessError.invalidRunEnvironment
  }

  let version = ProcessInfo.processInfo.operatingSystemVersion
  #if arch(arm64)
  let architecture = "arm64"
  #elseif arch(x86_64)
  let architecture = "x86_64"
  #else
  let architecture = "other"
  #endif

  return RunMetadata(
    configuration: compiledConfiguration,
    buildSystem: buildSystem,
    swiftVersion: swiftVersion,
    macOSVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
    architecture: architecture
  )
}

@MainActor
private func measureFreshActions(
  caseID: String,
  scope: String,
  prepare: @MainActor () async throws -> MeasuredAction
) async throws -> RawMeasurement {
  var samples: [Int64] = []
  var cpuSamples: [Int64] = []
  var counters: [String: Int] = [:]

  for iteration in 0..<(warmupCount + measurementCount) {
    let action = try await prepare()
    try await withActionCleanup(action) {
      if iteration < warmupCount {
        try await action.perform()
        try await action.verify()
        await action.quiesce()
        return
      }

      let cpuBefore = try processCPUMicroseconds()
      let clock = ContinuousClock()
      let start = clock.now
      try await action.perform()
      let elapsed = start.duration(to: clock.now)
      let cpuAfter = try processCPUMicroseconds()
      guard cpuAfter >= cpuBefore else { throw PerformanceHarnessError.invalidMeasurement }
      samples.append(try nanoseconds(elapsed))
      cpuSamples.append(cpuAfter - cpuBefore)
      try await action.verify()
      for (name, value) in action.counters() {
        counters[name, default: 0] += value
      }
      await action.quiesce()
    }
  }

  return try rawMeasurement(
    caseID: caseID,
    scope: scope,
    samples: samples,
    cpuSamples: cpuSamples,
    counters: counters
  )
}

@MainActor
private func measureReusableAction(
  caseID: String,
  scope: String,
  prepare: @MainActor () async throws -> MeasuredAction
) async throws -> RawMeasurement {
  let action = try await prepare()
  return try await withActionCleanup(action) {
    for _ in 0..<warmupCount {
      try await action.perform()
      try await action.verify()
      await action.quiesce()
    }

    var samples: [Int64] = []
    var cpuSamples: [Int64] = []
    var counters: [String: Int] = [:]
    for _ in 0..<measurementCount {
      let cpuBefore = try processCPUMicroseconds()
      let clock = ContinuousClock()
      let start = clock.now
      try await action.perform()
      let elapsed = start.duration(to: clock.now)
      let cpuAfter = try processCPUMicroseconds()
      guard cpuAfter >= cpuBefore else { throw PerformanceHarnessError.invalidMeasurement }
      samples.append(try nanoseconds(elapsed))
      cpuSamples.append(cpuAfter - cpuBefore)
      try await action.verify()
      for (name, value) in action.counters() {
        counters[name, default: 0] += value
      }
      await action.quiesce()
    }

    return try rawMeasurement(
      caseID: caseID,
      scope: scope,
      samples: samples,
      cpuSamples: cpuSamples,
      counters: counters
    )
  }
}

@MainActor
private func withActionCleanup<Value>(
  _ action: MeasuredAction,
  operation: @MainActor () async throws -> Value
) async throws -> Value {
  do {
    let result = try await operation()
    await action.cleanup()
    return result
  } catch {
    await action.cleanup()
    throw error
  }
}

private func rawMeasurement(
  caseID: String,
  scope: String,
  samples: [Int64],
  cpuSamples: [Int64],
  counters: [String: Int]
) throws -> RawMeasurement {
  let sorted = samples.sorted()
  guard !sorted.isEmpty,
    sorted.allSatisfy({ $0 >= 0 }),
    cpuSamples.count == sorted.count,
    cpuSamples.allSatisfy({ $0 >= 0 })
  else { throw PerformanceHarnessError.invalidMeasurement }
  let middle = sorted.count / 2
  guard !sorted.count.isMultiple(of: 2) else {
    throw PerformanceHarnessError.invalidMeasurement
  }
  var totalCPUMicroseconds: Int64 = 0
  for sample in cpuSamples {
    let (total, overflow) = totalCPUMicroseconds.addingReportingOverflow(sample)
    guard !overflow else { throw PerformanceHarnessError.invalidMeasurement }
    totalCPUMicroseconds = total
  }
  let p95Rank = max(1, Int(ceil(Double(sorted.count) * 0.95)))
  return RawMeasurement(
    caseID: caseID,
    scope: scope,
    repetitions: sorted.count,
    warmups: warmupCount,
    medianNanoseconds: sorted[middle],
    p95Nanoseconds: sorted[p95Rank - 1],
    minimumNanoseconds: sorted[0],
    maximumNanoseconds: sorted[sorted.count - 1],
    processCPUMicroseconds: totalCPUMicroseconds,
    counters: counters
  )
}

@MainActor
private func makeEditorTypingAction(byteCount: Int) async throws -> MeasuredAction {
  let initialBody = syntheticBody(byteCount: byteCount, marker: "A")
  let initialRTF = try encodedRTF(initialBody)
  let note = Note(
    title: "Synthetic editor benchmark",
    body: initialBody,
    richTextRTF: initialRTF,
    revision: 1
  )
  let fixture = try await makeHostedPanelFixture(
    workspace: Workspace(notes: [note], selectedNoteID: note.id)
  )
  let textView = fixture.textView
  guard fixture.window.makeFirstResponder(textView) else {
    await fixture.cleanup()
    throw PerformanceHarnessError.missingEditor
  }
  let publications = PublicationProbe(state: fixture.state)
  let insertedText = " Ω🧪\n"
  let expectedBody = initialBody + insertedText

  return MeasuredAction(
    perform: {
      textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
      for character in insertedText {
        textView.insertText(
          String(character),
          replacementRange: textView.selectedRange()
        )
      }
      guard flushEditorLayout(in: fixture.host) != nil else {
        throw PerformanceHarnessError.missingEditor
      }
    },
    verify: {
      try #require(textView.string == expectedBody)
      let selected = try #require(
        fixture.state.workspace.notes.first(where: { $0.id == note.id })
      )
      try #require(selected.body == expectedBody)
      try #require(selected.revision == note.revision + UInt64(insertedText.count))
      let richTextRTF = try #require(selected.richTextRTF)
      let decoded = try NoteRichTextCodec.decode(richTextRTF)
      try #require(decoded.string == expectedBody)
    },
    counters: { ["workspacePublications": publications.count] },
    quiesce: { await fixture.quiesce() },
    cleanup: { await fixture.cleanup() }
  )
}

@MainActor
private func makeEditorSelectionAction(byteCount: Int) async throws -> MeasuredAction {
  let body = syntheticBody(byteCount: byteCount, marker: "S")
  let richTextRTF = try encodedRTF(body)
  let note = Note(title: "Synthetic editor selection", body: body, richTextRTF: richTextRTF, revision: 1)
  let fixture = try await makeHostedPanelFixture(
    workspace: Workspace(notes: [note], selectedNoteID: note.id)
  )
  let textView = fixture.textView
  guard fixture.window.makeFirstResponder(textView) else {
    await fixture.cleanup()
    throw PerformanceHarnessError.missingEditor
  }
  fixture.commands.refreshFormattingState()
  let generation = fixture.state.persistenceGeneration
  var formattingBefore: Bool?
  var formattingAfter: Bool?

  return MeasuredAction(
    perform: {
      textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
      formattingBefore = fixture.commands.isBold
      fixture.commands.toggleBold()
      formattingAfter = fixture.commands.isBold
      guard flushEditorLayout(in: fixture.host) != nil else {
        throw PerformanceHarnessError.missingEditor
      }
    },
    verify: {
      guard let before = formattingBefore, let after = formattingAfter else {
        throw PerformanceHarnessError.missingFormattingState
      }
      try #require(before != after)
      try #require(textView.selectedRange().length == 0)
      try #require(textView.string == body)
      let selected = try #require(
        fixture.state.workspace.notes.first(where: { $0.id == note.id })
      )
      try #require(selected.body == body)
      try #require(selected.richTextRTF == richTextRTF)
      try #require(selected.revision == note.revision)
      try #require(fixture.state.persistenceGeneration == generation)
    },
    counters: { ["collapsedCaretFormattingUpdates": 1] },
    quiesce: { await fixture.quiesce() },
    cleanup: { await fixture.cleanup() }
  )
}

@MainActor
private func makeSelectedContentAction(
  noteCount: Int,
  workload: SelectedContentWorkload
) async throws -> MeasuredAction {
  let isLarge = workload == .largeBodyAndRTF
  let initialBody = syntheticBody(byteCount: isLarge ? 65_536 : 1_024, marker: "A")
  let replacementBody: String
  if isLarge {
    let finalPeriod = try #require(initialBody.lastIndex(of: "."))
    try #require(initialBody.distance(from: finalPeriod, to: initialBody.endIndex) == 2)
    var changedBody = initialBody
    changedBody.replaceSubrange(finalPeriod...finalPeriod, with: "!")
    try #require(changedBody.utf8.count == initialBody.utf8.count)
    replacementBody = changedBody
  } else {
    replacementBody = syntheticBody(byteCount: 1_024, marker: "B")
  }
  let smallBody = syntheticBody(byteCount: 1_024, marker: "S")
  let smallRTF = try encodedRTF(smallBody)
  let initialRTF = workload == .bodyOnly ? nil : try encodedRTF(initialBody)
  var expectedBody = initialBody
  var expectedRTF = initialRTF
  var expectedTitle = "Synthetic 0"
  switch workload {
  case .noOp:
    break
  case .bodyAndRTF:
    expectedBody = replacementBody
    expectedRTF = try encodedRTF(replacementBody)
  case .bodyOnly:
    expectedBody = replacementBody
    expectedRTF = nil
  case .richTextOnly:
    let existingRTF = try #require(initialRTF)
    let formattingOnlyRTF = try encodedRTF(initialBody, underlinePrefix: false)
    try #require(formattingOnlyRTF != existingRTF)
    expectedRTF = formattingOnlyRTF
  case .titleOnly:
    expectedTitle = "Synthetic title-only"
  case .largeBodyAndRTF:
    expectedBody = replacementBody
    expectedRTF = try encodedRTF(replacementBody)
  }
  let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
  let notes = (0..<noteCount).map { index in
    let otherNoteInLargeWorkload = isLarge && index > 0
    return Note(
      title: "Synthetic \(index)",
      body: otherNoteInLargeWorkload ? smallBody : initialBody,
      richTextRTF: otherNoteInLargeWorkload ? smallRTF : initialRTF,
      createdAt: referenceDate,
      modifiedAt: referenceDate,
      revision: 1
    )
  }
  let initialNote = try #require(notes.first)
  let workspace = Workspace(notes: notes, selectedNoteID: initialNote.id)
  let root = try temporaryStoreRoot()
  let state = AppState(
    store: LocalStore(rootURL: root),
    saveOperation: { _, _, _, _ in .committed }
  )
  await state.waitUntilInitialLoad()
  state.workspace = workspace
  let noteID = initialNote.id
  let generation = state.persistenceGeneration
  let expectedGeneration = generation + (workload == .noOp ? 0 : 1)
  let expectedRevision = initialNote.revision + (workload == .noOp ? 0 : 1)
  let dateBeforeMutation = Date()
  let publications = PublicationProbe(state: state)

  return MeasuredAction(
    perform: {
      if workload == .titleOnly {
        state.updateSelected(title: expectedTitle)
      } else {
        state.updateSelected(body: expectedBody, richTextRTF: expectedRTF)
      }
    },
    verify: {
      let selected = try #require(state.workspace.notes.first(where: { $0.id == noteID }))
      try #require(state.workspace.selectedNoteID == noteID)
      try #require(selected.title == expectedTitle)
      try #require(selected.body == expectedBody)
      try #require(selected.richTextRTF == expectedRTF)
      try #require(selected.revision == expectedRevision)
      try #require(selected.createdAt == initialNote.createdAt)
      if workload == .noOp {
        try #require(selected.modifiedAt == initialNote.modifiedAt)
      } else {
        try #require(selected.modifiedAt > initialNote.modifiedAt)
        try #require(selected.modifiedAt >= dateBeforeMutation)
        try #require(selected.modifiedAt <= Date())
      }
      try #require(state.persistenceGeneration == expectedGeneration)
      let untouchedNotes = state.workspace.notes.filter { $0.id != noteID }
      try #require(untouchedNotes == workspace.notes.filter { $0.id != noteID })
      if let expectedRTF {
        let decoded = try NoteRichTextCodec.decode(expectedRTF)
        try #require(decoded.string == expectedBody)
      } else {
        try #require(selected.richTextRTF == nil)
      }
    },
    counters: { ["workspacePublications": publications.count] },
    quiesce: { await state.quiescePersistenceForTesting() },
    cleanup: {
      await state.quiescePersistenceForTesting()
      try? FileManager.default.removeItem(at: root)
    }
  )
}

@MainActor
private func makeFirstMountSwitchAction(notes: (Note, Note)) async throws -> MeasuredAction {
  let fixture = try await makeHostedPanelFixture(
    workspace: Workspace(notes: [notes.0, notes.1], selectedNoteID: notes.0.id)
  )
  let priorTextView = fixture.textView
  var switchedTextView: ListAwareTextView?

  return MeasuredAction(
    perform: {
      fixture.state.select(notes.1.id)
      switchedTextView = try await waitForEditor(in: fixture.host, differentFrom: priorTextView)
    },
    verify: {
      let switchedTextView = try #require(switchedTextView)
      try #require(switchedTextView !== priorTextView)
      try #require(fixture.state.workspace.selectedNoteID == notes.1.id)
      let selected = try #require(
        fixture.state.workspace.notes.first(where: { $0.id == notes.1.id })
      )
      try #require(switchedTextView.string == selected.body)
      let richTextRTF = try #require(selected.richTextRTF)
      let decoded = try NoteRichTextCodec.decode(richTextRTF)
      try #require(decoded.string == selected.body)
    },
    counters: { ["identityBoundedSwitches": 1] },
    quiesce: { await fixture.quiesce() },
    cleanup: { await fixture.cleanup() }
  )
}

@MainActor
private func makeWarmSwitchAction(notes: (Note, Note)) async throws -> MeasuredAction {
  let fixture = try await makeHostedPanelFixture(
    workspace: Workspace(notes: [notes.0, notes.1], selectedNoteID: notes.0.id)
  )
  var activeIndex = 0
  var priorTextView = fixture.textView
  var switchedFromTextView: ListAwareTextView?
  var switchedTextView: ListAwareTextView?

  return MeasuredAction(
    perform: {
      let nextIndex = 1 - activeIndex
      let prior = priorTextView
      let nextNote = nextIndex == 0 ? notes.0 : notes.1
      fixture.state.select(nextNote.id)
      let next = try await waitForEditor(in: fixture.host, differentFrom: prior)
      switchedFromTextView = prior
      switchedTextView = next
      priorTextView = next
      activeIndex = nextIndex
    },
    verify: {
      let activeNote = activeIndex == 0 ? notes.0 : notes.1
      let switchedTextView = try #require(switchedTextView)
      try #require(switchedTextView !== switchedFromTextView)
      try #require(fixture.state.workspace.selectedNoteID == activeNote.id)
      let selected = try #require(
        fixture.state.workspace.notes.first(where: { $0.id == activeNote.id })
      )
      try #require(switchedTextView.string == selected.body)
      let richTextRTF = try #require(selected.richTextRTF)
      let decoded = try NoteRichTextCodec.decode(richTextRTF)
      try #require(decoded.string == selected.body)
    },
    counters: { ["identityBoundedSwitches": 1] },
    quiesce: { await fixture.quiesce() },
    cleanup: { await fixture.cleanup() }
  )
}

@MainActor
private func measureLocalStoreSaves(noteCount: Int) async throws -> RawMeasurement {
  let root = try temporaryStoreRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = LocalStore(rootURL: root)
  let initialBody = syntheticBody(byteCount: 1_024, marker: "A")
  let firstReplacement = syntheticBody(byteCount: 1_024, marker: "B")
  let secondReplacement = syntheticBody(byteCount: 1_024, marker: "C")
  let initialRTF = try encodedRTF(initialBody)
  let replacementRTF = try encodedRTF(firstReplacement)
  let alternateRTF = try encodedRTF(secondReplacement)
  var workspace = makeWorkspace(
    noteCount: noteCount,
    body: initialBody,
    richTextRTF: initialRTF
  )
  let preferences = AppPreferences()
  let noteID = try #require(workspace.selectedNoteID)
  let seed = try await store.save(
    workspace: workspace,
    preferences: preferences,
    generation: 1
  )
  try #require(seed == .committed)
  var generation: UInt64 = 1
  var nextMarker = 0

  return try await measureFreshActions(
    caseID: "store.one_note_save.notes.\(noteCount)",
    scope: "local_store_durable_save",
    prepare: {
      let body = nextMarker.isMultiple(of: 2) ? firstReplacement : secondReplacement
      let richTextRTF = nextMarker.isMultiple(of: 2) ? replacementRTF : alternateRTF
      nextMarker += 1
      let expectedGeneration = generation + 1
      var candidate = workspace
      candidate.updateContent(
        id: noteID,
        body: body,
        rtf: richTextRTF,
        now: Date(timeIntervalSince1970: 1_700_000_000 + Double(expectedGeneration))
      )
      var result: LocalStoreSnapshotWriteResult?

      return MeasuredAction(
        perform: {
          result = try await store.save(
            workspace: candidate,
            preferences: preferences,
            generation: expectedGeneration
          )
        },
        verify: {
          try #require(result == .committed)
          let snapshot = try await store.loadSnapshot()
          try #require(snapshot.workspace == candidate)
          try #require(snapshot.preferences == preferences)
          try #require(snapshot.generation == expectedGeneration)
          try #require(snapshot.workspace.notes.count == noteCount)
          let saved = try #require(snapshot.workspace.notes.first(where: { $0.id == noteID }))
          try #require(saved.body == body)
          try #require(saved.richTextRTF == richTextRTF)
          let savedRTF = try #require(saved.richTextRTF)
          let decoded = try NoteRichTextCodec.decode(savedRTF)
          try #require(decoded.string == body)
          workspace = candidate
          generation = expectedGeneration
        },
        counters: { ["durableSaves": result == .committed ? 1 : 0] },
        quiesce: {},
        cleanup: {}
      )
    }
  )
}

@MainActor
private func measureSnapshotSaves(noteCount: Int, metadataOnly: Bool) async throws -> RawMeasurement {
  let root = try temporaryStoreRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = LocalStore(rootURL: root)
  let body = syntheticBody(byteCount: 1_024, marker: "A")
  let richTextRTF = try encodedRTF(body)
  var workspace = makeWorkspace(noteCount: noteCount, body: body, richTextRTF: richTextRTF)
  var preferences = AppPreferences()
  let seed = try await store.save(workspace: workspace, preferences: preferences, generation: 1)
  try #require(seed == .committed)
  let noteID = try #require(workspace.selectedNoteID)
  let noteURL = root.appendingPathComponent("\(noteID.uuidString.lowercased()).md")
  let initialLiveNoteFileIdentity = try liveNoteFileIdentity(at: noteURL)
  var generation: UInt64 = 1

  return try await measureFreshActions(
    caseID: metadataOnly
      ? "store.metadata_only.notes.\(noteCount)"
      : "store.unchanged_snapshot.notes.\(noteCount)",
    scope: metadataOnly ? "local_store_metadata_only_save" : "local_store_unchanged_snapshot",
    prepare: {
      let candidateWorkspace = workspace
      var candidatePreferences = preferences
      if metadataOnly { candidatePreferences.showFormattingBar.toggle() }
      let expectedGeneration = generation + 1
      try #require(!metadataOnly || candidatePreferences != preferences)
      var result: LocalStoreSnapshotWriteResult?

      return MeasuredAction(
        perform: {
          result = try await store.save(
            workspace: candidateWorkspace,
            preferences: candidatePreferences,
            generation: expectedGeneration
          )
        },
        verify: {
          try #require(result == .committed)
          let snapshot = try await store.loadSnapshot()
          try #require(snapshot.workspace == candidateWorkspace)
          try #require(snapshot.preferences == candidatePreferences)
          try #require(snapshot.generation == expectedGeneration)
          let currentLiveNoteFileIdentity = try liveNoteFileIdentity(at: noteURL)
          try #require(currentLiveNoteFileIdentity == initialLiveNoteFileIdentity)
          if !metadataOnly {
            try #require(snapshot.workspace == workspace)
            try #require(snapshot.preferences == preferences)
          }
          workspace = candidateWorkspace
          preferences = candidatePreferences
          generation = expectedGeneration
        },
        counters: { ["durableSaves": result == .committed ? 1 : 0] },
        quiesce: {},
        cleanup: {}
      )
    }
  )
}

@MainActor
private func measureAppStateCommits(noteCount: Int) async throws -> RawMeasurement {
  let root = try temporaryStoreRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = LocalStore(rootURL: root)
  let initialBody = syntheticBody(byteCount: 1_024, marker: "A")
  let replacementBody = syntheticBody(byteCount: 1_024, marker: "B")
  let alternateBody = syntheticBody(byteCount: 1_024, marker: "C")
  let initialRTF = try encodedRTF(initialBody)
  let replacementRTF = try encodedRTF(replacementBody)
  let alternateRTF = try encodedRTF(alternateBody)
  let initialWorkspace = makeWorkspace(
    noteCount: noteCount,
    body: initialBody,
    richTextRTF: initialRTF
  )
  let seed = try await store.save(
    workspace: initialWorkspace,
    preferences: AppPreferences(),
    generation: 1
  )
  try #require(seed == .committed)
  let state = AppState(store: store)
  await state.waitUntilInitialLoad()
  try #require(state.isAgentWorkspaceAvailable)
  let noteID = try #require(state.workspace.selectedNoteID)
  var targetIndex = 0

  return try await measureFreshActions(
    caseID: "commit.app_state_only.notes.\(noteCount)",
    scope: "commit_only_not_end_to_end_mcp",
    prepare: {
      let body = targetIndex.isMultiple(of: 2) ? replacementBody : alternateBody
      let richTextRTF = targetIndex.isMultiple(of: 2) ? replacementRTF : alternateRTF
      targetIndex += 1
      var candidate = state.workspace
      candidate.updateContent(id: noteID, body: body, rtf: richTextRTF)
      let expectedGeneration = state.persistenceGeneration
      let changedNote = try #require(candidate.notes.first(where: { $0.id == noteID }))
      let proof = AgentWorkspaceCommitProof(
        changeID: UUID(),
        noteID: noteID,
        resultingRevision: changedNote.revision,
        bodySHA256: sha256(body),
        actor: .integration(profileID: UUID(), displayName: "Synthetic benchmark"),
        operationID: UUID(),
        expiresAt: Date(timeIntervalSince1970: 4_000_000_000)
      )
      var committed = false

      return MeasuredAction(
        perform: {
          try state.commitAgentWorkspace(
            candidate,
            expectedGeneration: expectedGeneration,
            commitProof: proof
          )
          committed = true
        },
        verify: {
          try #require(committed)
          try #require(state.persistenceGeneration == expectedGeneration + 1)
          try #require(state.agentCommitProofs.contains(proof))
          let restored = try await store.loadSnapshot().workspace
          try #require(restored.notes.count == noteCount)
          let saved = try #require(restored.notes.first(where: { $0.id == noteID }))
          try #require(saved.body == body)
          try #require(saved.richTextRTF == richTextRTF)
          let savedRTF = try #require(saved.richTextRTF)
          let decoded = try NoteRichTextCodec.decode(savedRTF)
          try #require(decoded.string == body)
        },
        counters: { ["durableCommits": committed ? 1 : 0] },
        quiesce: { await state.quiescePersistenceForTesting() },
        cleanup: { await state.quiescePersistenceForTesting() }
      )
    }
  )
}

@MainActor
private func makeWorkspace(noteCount: Int, body: String, richTextRTF: Data) -> Workspace {
  let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
  let notes = (0..<noteCount).map { index in
    Note(
      title: "Synthetic \(index)",
      body: body,
      richTextRTF: richTextRTF,
      createdAt: referenceDate,
      modifiedAt: referenceDate,
      revision: 1
    )
  }
  return Workspace(notes: notes, selectedNoteID: notes.first?.id)
}

@MainActor
private func switchNotes() throws -> (Note, Note) {
  let firstBody = syntheticBody(byteCount: 1_024, marker: "A")
  let secondBody = syntheticBody(byteCount: 1_024, marker: "B")
  return (
    Note(title: "Synthetic A", body: firstBody, richTextRTF: try encodedRTF(firstBody), revision: 1),
    Note(title: "Synthetic B", body: secondBody, richTextRTF: try encodedRTF(secondBody), revision: 1)
  )
}

@MainActor
private func makeHostedPanelFixture(workspace: Workspace) async throws -> HostedPanelFixture {
  let root = try temporaryStoreRoot()
  let state = AppState(
    store: LocalStore(rootURL: root),
    saveOperation: { _, _, _, _ in .committed }
  )
  await state.waitUntilInitialLoad()
  state.preferences.fontFamily = NSFont.systemFont(ofSize: 14).familyName ?? "Helvetica"
  state.preferences.fontSize = 14
  state.workspace = workspace
  let commands = EditorCommands()
  let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
  let panel = NotesPanel(
    dictationRuntime: runtime,
    isPinned: false,
    sizing: .container,
    editorCommands: commands
  )
  let host = NSHostingView(
    rootView: AnyView(PerformanceThemeRoot(state: state) { panel })
  )
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 640, height: 430),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.isReleasedWhenClosed = false
  window.contentView = host
  window.makeKeyAndOrderFront(nil)
  do {
    let textView = try await waitForEditor(in: host)
    let selectedID = try #require(state.workspace.selectedNoteID)
    let selected = try #require(state.workspace.notes.first(where: { $0.id == selectedID }))
    try #require(textView.string == selected.body)
    return HostedPanelFixture(
      root: root,
      state: state,
      commands: commands,
      window: window,
      host: host,
      textView: textView
    )
  } catch {
    closeHostedEditor(window)
    await state.quiescePersistenceForTesting()
    try? FileManager.default.removeItem(at: root)
    throw error
  }
}

@MainActor
private func findEditor(in view: NSView) -> ListAwareTextView? {
  if let textView = view as? ListAwareTextView { return textView }
  for subview in view.subviews {
    if let textView = findEditor(in: subview) { return textView }
  }
  return nil
}

@MainActor
private func flushEditorLayout(in host: NSHostingView<AnyView>) -> ListAwareTextView? {
  host.layoutSubtreeIfNeeded()
  guard let textView = findEditor(in: host) else { return nil }
  flushTextKitLayout(in: textView)
  return textView
}

@MainActor
private func flushTextKitLayout(in textView: ListAwareTextView) {
  textView.layoutSubtreeIfNeeded()
  if let layoutManager = textView.layoutManager, let textContainer = textView.textContainer {
    layoutManager.ensureLayout(for: textContainer)
    _ = layoutManager.usedRect(for: textContainer)
  }
}

@MainActor
private func waitForEditor(
  in host: NSHostingView<AnyView>,
  differentFrom previous: ListAwareTextView? = nil
) async throws -> ListAwareTextView {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: .seconds(1))
  while clock.now < deadline {
    host.layoutSubtreeIfNeeded()
    if let textView = findEditor(in: host),
      previous.map({ textView !== $0 }) ?? true
    {
      flushTextKitLayout(in: textView)
      return textView
    }
    await Task.yield()
  }
  throw PerformanceHarnessError.missingEditor
}

@MainActor
private func closeHostedEditor(_ window: NSWindow) {
  window.orderOut(nil)
  window.contentView = nil
  window.close()
}

@MainActor
private func encodedRTF(_ body: String, underlinePrefix: Bool = true) throws -> Data {
  let attributed = NSMutableAttributedString(
    string: body,
    attributes: [.font: NSFont.systemFont(ofSize: 13)]
  )
  if attributed.length > 0, underlinePrefix {
    attributed.addAttribute(
      .underlineStyle,
      value: NSUnderlineStyle.single.rawValue,
      range: NSRange(location: 0, length: min(12, attributed.length))
    )
  }
  return try NoteRichTextCodec.encode(attributed)
}

private func syntheticBody(byteCount: Int, marker: String) -> String {
  let paragraph = "Fleck perf \(marker) — λ Ω 🧪\ncontrolled synthetic paragraph.\n"
  var body = ""
  while body.utf8.count < byteCount {
    body += paragraph
  }
  return body
}

private func temporaryStoreRoot() throws -> URL {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "fleck-foreground-perf-\(UUID().uuidString)",
    isDirectory: true
  )
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  return root
}

private func liveNoteFileIdentity(at url: URL) throws -> UInt64 {
  let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
  return try #require((attributes[.systemFileNumber] as? NSNumber)?.uint64Value)
}

private func sha256(_ string: String) -> String {
  SHA256.hash(data: Data(string.utf8))
    .map { String(format: "%02x", $0) }
    .joined()
}

private func processCPUMicroseconds() throws -> Int64 {
  var usage = rusage()
  guard getrusage(RUSAGE_SELF, &usage) == 0 else {
    throw PerformanceHarnessError.processCPUUnavailable
  }
  let user = try timevalMicroseconds(usage.ru_utime)
  let system = try timevalMicroseconds(usage.ru_stime)
  let (total, overflow) = user.addingReportingOverflow(system)
  guard !overflow else { throw PerformanceHarnessError.processCPUUnavailable }
  return total
}

private func timevalMicroseconds(_ value: timeval) throws -> Int64 {
  let seconds = Int64(value.tv_sec)
  let microseconds = Int64(value.tv_usec)
  guard seconds >= 0, microseconds >= 0, microseconds < 1_000_000 else {
    throw PerformanceHarnessError.processCPUUnavailable
  }
  let (wholeSeconds, secondsOverflow) = seconds.multipliedReportingOverflow(by: 1_000_000)
  let (total, microsecondsOverflow) = wholeSeconds.addingReportingOverflow(microseconds)
  guard !secondsOverflow, !microsecondsOverflow else {
    throw PerformanceHarnessError.processCPUUnavailable
  }
  return total
}

private func nanoseconds(_ duration: Duration) throws -> Int64 {
  let components = duration.components
  guard
    components.seconds >= 0,
    components.attoseconds >= 0,
    components.attoseconds < 1_000_000_000_000_000_000
  else { throw PerformanceHarnessError.invalidMeasurement }
  let (wholeSeconds, secondsOverflow) = components.seconds.multipliedReportingOverflow(
    by: 1_000_000_000
  )
  let wholeNanoseconds = components.attoseconds / 1_000_000_000
  let roundedSubNanosecond: Int64 =
    components.attoseconds % 1_000_000_000 == 0 ? 0 : 1
  let (subsecondNanoseconds, fractionOverflow) = wholeNanoseconds.addingReportingOverflow(
    roundedSubNanosecond
  )
  let (total, totalOverflow) = wholeSeconds.addingReportingOverflow(subsecondNanoseconds)
  guard !secondsOverflow, !fractionOverflow, !totalOverflow else {
    throw PerformanceHarnessError.invalidMeasurement
  }
  return total
}

@MainActor
private func recordAndCheck(_ measurement: RawMeasurement, metadata: RunMetadata) {
  let comparison = baselineComparison(for: measurement, metadata: metadata)
  let record = PerformanceRecord(
    schemaVersion: 1,
    caseID: measurement.caseID,
    scope: measurement.scope,
    optIn: ProcessInfo.processInfo.environment["FLECK_PERF_RUN"] == "1",
    configuration: metadata.configuration,
    buildSystem: metadata.buildSystem,
    testabilityEnabled: true,
    swiftVersion: metadata.swiftVersion,
    macOSVersion: metadata.macOSVersion,
    architecture: metadata.architecture,
    repetitions: measurement.repetitions,
    warmups: measurement.warmups,
    errors: 0,
    correctness: "passed",
    medianMilliseconds: measurement.medianMilliseconds,
    p95Milliseconds: measurement.p95Milliseconds,
    rangeMilliseconds: [measurement.minimumMilliseconds, measurement.maximumMilliseconds],
    processCPUSeconds: measurement.processCPUSeconds,
    processCPUSecondsPerOperation: measurement.processCPUSeconds / Double(measurement.repetitions),
    counters: measurement.counters,
    baselineStatus: comparison.status
  )
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys]
  guard let data = try? encoder.encode(record), let line = String(data: data, encoding: .utf8) else {
    Issue.record("Could not encode sanitized performance result")
    return
  }
  print("FLECK_PERF_RESULT \(line)")
  if let failure = comparison.failure {
    Issue.record(Testing.Comment(rawValue: failure))
  }
}

@MainActor
private func baselineComparison(
  for measurement: RawMeasurement,
  metadata: RunMetadata
) -> (status: String, failure: String?) {
  guard let path = ProcessInfo.processInfo.environment["FLECK_PERF_BASELINE_RECEIPT"] else {
    return ("not_configured", nil)
  }
  guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
    let receipt = try? JSONDecoder().decode(BaselineReceipt.self, from: data),
    receipt.schemaVersion == 1,
    receipt.baselineSourceCommit.count == 40,
    receipt.baselineSourceCommit.allSatisfy({ $0.isHexDigit }),
    receipt.configuration == metadata.configuration,
    receipt.buildSystem == metadata.buildSystem,
    receipt.testabilityEnabled,
    Set(receipt.cases.map(\.caseID)) == benchmarkCaseIDs,
    receipt.cases.count == benchmarkCaseIDs.count,
    receipt.cases.allSatisfy(validBaselineCase)
  else {
    return ("invalid", "Performance baseline receipt is invalid or does not match this configuration")
  }
  guard let baseline = receipt.cases.first(where: { $0.caseID == measurement.caseID }) else {
    return ("invalid", "Performance baseline receipt is missing this benchmark case")
  }

  guard let passes = PerformanceBaselineComparator.passes(measurement, against: baseline) else {
    return ("invalid", "Performance measurement or baseline limit is outside the supported range")
  }
  return passes
    ? ("pass", nil)
    : ("fail", "Performance measurement exceeded the frozen baseline envelope")
}

private func validBaselineCase(_ value: BaselineCase) -> Bool {
  PerformanceBaselineComparator.isValid(value)
}

enum PerformanceBaselineComparator {
  static func nanoseconds(forMilliseconds value: Decimal) -> Int64? {
    fixedPointUnits(value, unitsPerValue: 1_000_000)
  }

  static func microseconds(forSeconds value: Decimal) -> Int64? {
    fixedPointUnits(value, unitsPerValue: 1_000_000)
  }

  static func isValid(_ baseline: BaselineCase) -> Bool {
    let values = [
      baseline.baselineMedianMilliseconds,
      baseline.medianNoiseMarginMilliseconds,
      baseline.baselineP95Milliseconds,
      baseline.p95NoiseMarginMilliseconds,
      baseline.baselineProcessCPUSeconds,
      baseline.cpuNoiseMarginSeconds
    ]
    guard values.allSatisfy({ !$0.isNaN && $0 >= 0 }) else { return false }
    return limit(
      baseline.baselineMedianMilliseconds,
      margin: baseline.medianNoiseMarginMilliseconds,
      unitsPerValue: 1_000_000
    ) != nil
      && limit(
        baseline.baselineP95Milliseconds,
        margin: baseline.p95NoiseMarginMilliseconds,
        unitsPerValue: 1_000_000
      ) != nil
      && limit(
        baseline.baselineProcessCPUSeconds,
        margin: baseline.cpuNoiseMarginSeconds,
        unitsPerValue: 1_000_000
      ) != nil
  }

  static func passes(_ measurement: RawMeasurement, against baseline: BaselineCase) -> Bool? {
    guard
      measurement.caseID == baseline.caseID,
      measurement.repetitions == measurementCount,
      measurement.warmups == warmupCount,
      measurement.minimumNanoseconds >= 0,
      measurement.minimumNanoseconds <= measurement.medianNanoseconds,
      measurement.medianNanoseconds <= measurement.p95Nanoseconds,
      measurement.p95Nanoseconds <= measurement.maximumNanoseconds,
      measurement.processCPUMicroseconds >= 0,
      isValid(baseline),
      let medianLimit = limit(
        baseline.baselineMedianMilliseconds,
        margin: baseline.medianNoiseMarginMilliseconds,
        unitsPerValue: 1_000_000
      ),
      let p95Limit = limit(
        baseline.baselineP95Milliseconds,
        margin: baseline.p95NoiseMarginMilliseconds,
        unitsPerValue: 1_000_000
      ),
      let cpuLimit = limit(
        baseline.baselineProcessCPUSeconds,
        margin: baseline.cpuNoiseMarginSeconds,
        unitsPerValue: 1_000_000
      )
    else { return nil }

    return measurement.medianNanoseconds <= medianLimit
      && measurement.p95Nanoseconds <= p95Limit
      && measurement.processCPUMicroseconds <= cpuLimit
  }

  private static func limit(
    _ baseline: Decimal,
    margin: Decimal,
    unitsPerValue: Int64
  ) -> Int64? {
    guard !baseline.isNaN, !margin.isNaN, baseline >= 0, margin >= 0 else { return nil }
    var baseline = baseline
    var margin = margin
    var exactLimit = Decimal()
    guard NSDecimalAdd(&exactLimit, &baseline, &margin, .plain) == .noError else { return nil }
    return fixedPointUnits(exactLimit, unitsPerValue: unitsPerValue)
  }

  private static func fixedPointUnits(_ value: Decimal, unitsPerValue: Int64) -> Int64? {
    guard !value.isNaN, value >= 0 else { return nil }
    var value = value
    var scale = Decimal(unitsPerValue)
    var scaled = Decimal()
    guard NSDecimalMultiply(&scaled, &value, &scale, .plain) == .noError else { return nil }
    guard !scaled.isNaN, scaled >= 0 else { return nil }
    var rounded = Decimal()
    NSDecimalRound(&rounded, &scaled, 0, .plain)
    guard !rounded.isNaN, rounded <= Decimal(Int64.max) else { return nil }
    let integer = NSDecimalNumber(decimal: rounded).int64Value
    guard Decimal(integer) == rounded else { return nil }
    return integer
  }
}
