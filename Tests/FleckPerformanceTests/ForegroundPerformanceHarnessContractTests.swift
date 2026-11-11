import Foundation
import FleckCore
import Testing

@testable import FleckApp

@MainActor
private final class WeakAppStateReference {
  weak var value: AppState?

  init(_ value: AppState) {
    self.value = value
  }
}

private actor SaveCallbackCounter {
  private var count = 0
  private var cleanupFinished = false
  private var callbacksAfterCleanup = 0

  func increment() {
    count += 1
    if cleanupFinished {
      callbacksAfterCleanup += 1
    }
  }

  func markCleanupFinished() {
    cleanupFinished = true
  }

  func value() -> Int {
    count
  }

  func callbacksAfterCleanupValue() -> Int {
    callbacksAfterCleanup
  }
}

private actor SaveOperationGate {
  private var started = false
  private var startWaiters: [CheckedContinuation<Void, Never>] = []
  private var finishWaiters: [CheckedContinuation<Void, Never>] = []
  private var cancellationObserved: Bool?

  func perform() async -> LocalStoreSnapshotWriteResult {
    started = true
    let waiters = startWaiters
    startWaiters.removeAll()
    for waiter in waiters {
      waiter.resume()
    }

    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      finishWaiters.append(continuation)
    }
    cancellationObserved = Task.isCancelled
    return .committed
  }

  func waitForStart() async {
    guard !started else { return }
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      startWaiters.append(continuation)
    }
  }

  func release() {
    let waiters = finishWaiters
    finishWaiters.removeAll()
    for waiter in waiters {
      waiter.resume()
    }
  }

  func wasCancelled() -> Bool? {
    cancellationObserved
  }
}

@Suite(.serialized)
struct ForegroundPerformanceHarnessContractTests {
  @Test
  func originalReceiptMediansMapToNanoseconds() {
    let values: [(String, Int64)] = [
      ("0.021375", 21_375),
      ("0.022917", 22_917),
      ("0.022875", 22_875),
      ("0.021958", 21_958),
      ("0.023", 23_000)
    ]

    for (value, expectedNanoseconds) in values {
      #expect(
        PerformanceBaselineComparator.nanoseconds(forMilliseconds: decimal(value))
          == expectedNanoseconds
      )
    }
  }

  @Test
  func originalReceiptCPUValuesMapToMicroseconds() {
    let values: [(String, Int64)] = [
      ("0.00005899999998604244", 59),
      ("0.000046000000024490426", 46),
      ("0.00004800000001381477", 48),
      ("0.00004899999998494173", 49)
    ]

    for (value, expectedMicroseconds) in values {
      #expect(
        PerformanceBaselineComparator.microseconds(forSeconds: decimal(value))
          == expectedMicroseconds
      )
    }
  }

  @Test
  func wallBoundariesPassExactlyAndRejectTheNextNanosecond() throws {
    let receipt = try JSONDecoder().decode(
      BaselineCase.self,
      from: Data(
        #"{"caseID":"state.noop.notes.10","baselineMedianMilliseconds":0.021375,"medianNoiseMarginMilliseconds":0.003249999999999997,"baselineP95Milliseconds":0.021375,"p95NoiseMarginMilliseconds":0.003249999999999997,"baselineProcessCPUSeconds":0.000021,"cpuNoiseMarginSeconds":0.000004}"#.utf8
      )
    )
    let exactBoundary = measurement(median: 24_625, p95: 24_625, cpu: 25)
    #expect(PerformanceBaselineComparator.passes(exactBoundary, against: receipt) == true)

    let nextMedianNanosecond = measurement(median: 24_626, p95: 24_626, cpu: 25)
    #expect(
      PerformanceBaselineComparator.passes(
        nextMedianNanosecond,
        against: baseline(p95: "0.03", p95Margin: "0")
      ) == false
    )

    let nextP95Nanosecond = measurement(median: 24_625, p95: 24_626, cpu: 25)
    #expect(
      PerformanceBaselineComparator.passes(
        nextP95Nanosecond,
        against: baseline(median: "0.03", medianMargin: "0")
      ) == false
    )

    let titleOnlyReceipt = baseline(
      caseID: "state.title_only.notes.1000",
      median: "0.022875",
      medianMargin: "0.001749999999999998",
      p95: "0.023708",
      p95Margin: "0.0027500000000000024",
      cpu: "0.00021299999998802832",
      cpuMargin: "0.00003900000001374202"
    )
    let titleOnlyBoundary = measurement(
      caseID: "state.title_only.notes.1000",
      median: 24_625,
      p95: 26_458,
      cpu: 252
    )
    #expect(
      PerformanceBaselineComparator.passes(titleOnlyBoundary, against: titleOnlyReceipt)
        == true
    )

    let titleOnlyNextMedianNanosecond = measurement(
      caseID: "state.title_only.notes.1000",
      median: 24_626,
      p95: 26_458,
      cpu: 252
    )
    #expect(
      PerformanceBaselineComparator.passes(
        titleOnlyNextMedianNanosecond,
        against: titleOnlyReceipt
      ) == false
    )

    let titleOnlyNextP95Nanosecond = measurement(
      caseID: "state.title_only.notes.1000",
      median: 24_625,
      p95: 26_459,
      cpu: 252
    )
    #expect(
      PerformanceBaselineComparator.passes(
        titleOnlyNextP95Nanosecond,
        against: titleOnlyReceipt
      ) == false
    )
  }

  @Test
  func cpuBoundaryPassesExactlyAndRejectsTheNextMicrosecond() {
    let exactBoundary = measurement(median: 0, p95: 0, cpu: 25)
    #expect(PerformanceBaselineComparator.passes(exactBoundary, against: baseline()) == true)

    let nextMicrosecond = measurement(median: 0, p95: 0, cpu: 26)
    #expect(PerformanceBaselineComparator.passes(nextMicrosecond, against: baseline()) == false)
  }

  @Test
  func invalidAndOutOfRangeBaselineValuesAreRejected() {
    #expect(
      PerformanceBaselineComparator.nanoseconds(
        forMilliseconds: decimal("-0.001")
      ) == nil
    )
    #expect(
      PerformanceBaselineComparator.nanoseconds(
        forMilliseconds: decimal("9223372036854.775808")
      ) == nil
    )
    #expect(
      PerformanceBaselineComparator.passes(
        measurement(median: 0, p95: 0, cpu: 0),
        against: baseline(median: "9223372036854.775808", medianMargin: "0")
      ) == nil
    )
  }

  @Test
  @MainActor
  func fixtureCleanupReleasesStateWithPendingSave() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "fleck-perf-lifetime-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let callbacks = SaveCallbackCounter()
    var state: AppState? = AppState(
      store: LocalStore(rootURL: root),
      saveOperation: { _, _, _, _ in
        await callbacks.increment()
        return .committed
      }
    )
    await state!.waitUntilInitialLoad()
    let note = Note(title: "Synthetic", body: "Synthetic fixture body")
    state!.workspace = Workspace(notes: [note], selectedNoteID: note.id)
    let weakState = WeakAppStateReference(state!)

    state!.updateSelected(title: "Synthetic changed")
    await state!.quiescePersistenceForTesting()
    try FileManager.default.removeItem(at: root)
    state = nil

    #expect(weakState.value == nil)
    #expect(await callbacks.value() == 0)
  }

  @Test
  @MainActor
  func quiescenceWaitsForAnInFlightSaveAndItsStatusTask() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "fleck-perf-in-flight-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let gate = SaveOperationGate()
    var state: AppState? = AppState(
      store: LocalStore(rootURL: root),
      saveOperation: { _, _, _, _ in await gate.perform() }
    )
    await state!.waitUntilInitialLoad()
    let note = Note(title: "Synthetic", body: "Synthetic fixture body")
    state!.workspace = Workspace(notes: [note], selectedNoteID: note.id)
    let weakState = WeakAppStateReference(state!)
    state!.updateSelected(title: "Synthetic changed")

    await gate.waitForStart()
    let releaseSave = Task {
      await Task.yield()
      await gate.release()
    }
    await state!.quiescePersistenceForTesting()
    await releaseSave.value
    state = nil

    #expect(await gate.wasCancelled() == false)
    #expect(weakState.value == nil)
  }

  @Test
  @MainActor
  func quiescenceDrainsReplacedSavesAroundAnInFlightSave() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "fleck-perf-replaced-saves-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let callbacks = SaveCallbackCounter()
    let gate = SaveOperationGate()
    var state: AppState? = AppState(
      store: LocalStore(rootURL: root),
      saveOperation: { _, _, _, _ in
        await callbacks.increment()
        return await gate.perform()
      }
    )
    await state!.waitUntilInitialLoad()
    let note = Note(title: "Synthetic", body: "Synthetic fixture body")
    state!.workspace = Workspace(notes: [note], selectedNoteID: note.id)
    let weakState = WeakAppStateReference(state!)

    state!.updateSelected(title: "First replacement")
    state!.updateSelected(title: "Second replacement")
    state!.updateSelected(title: "Final replacement")
    await gate.waitForStart()

    let releaseSave = Task {
      await Task.yield()
      await gate.release()
    }
    await state!.quiescePersistenceForTesting()
    await releaseSave.value
    try FileManager.default.removeItem(at: root)
    await callbacks.markCleanupFinished()
    state = nil

    #expect(await callbacks.value() == 1)
    #expect(await callbacks.callbacksAfterCleanupValue() == 0)
    #expect(await gate.wasCancelled() == false)
    #expect(weakState.value == nil)
  }
}

private func decimal(_ value: String) -> Decimal {
  Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
}

private func baseline(
  caseID: String = "state.noop.notes.10",
  median: String = "0.021375",
  medianMargin: String = "0.003249999999999997",
  p95: String = "0.021375",
  p95Margin: String = "0.003249999999999997",
  cpu: String = "0.000021",
  cpuMargin: String = "0.000004"
) -> BaselineCase {
  BaselineCase(
    caseID: caseID,
    baselineMedianMilliseconds: decimal(median),
    medianNoiseMarginMilliseconds: decimal(medianMargin),
    baselineP95Milliseconds: decimal(p95),
    p95NoiseMarginMilliseconds: decimal(p95Margin),
    baselineProcessCPUSeconds: decimal(cpu),
    cpuNoiseMarginSeconds: decimal(cpuMargin)
  )
}

private func measurement(
  caseID: String = "state.noop.notes.10",
  median: Int64,
  p95: Int64,
  cpu: Int64
) -> RawMeasurement {
  RawMeasurement(
    caseID: caseID,
    scope: "contract-test",
    repetitions: 9,
    warmups: 1,
    medianNanoseconds: median,
    p95Nanoseconds: p95,
    minimumNanoseconds: min(median, p95),
    maximumNanoseconds: max(median, p95),
    processCPUMicroseconds: cpu,
    counters: [:]
  )
}
