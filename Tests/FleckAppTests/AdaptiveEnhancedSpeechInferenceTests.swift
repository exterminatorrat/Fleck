#if os(macOS) && CLEAN_DICTATION_ENHANCED_CANDIDATE
import Foundation
import Testing

@testable import FleckApp

private enum AdaptiveInferenceTestError: Error, Equatable {
  case load
  case transcribe
}

private enum AdaptiveSubstitutionOutcome: Equatable {
  case succeeded
  case cancellation
  case unavailable
  case other
}

@MainActor
private final class AdaptiveInferenceProbe: EnhancedSpeechInferring {
  var loadError: AdaptiveInferenceTestError?
  var transcribeError: AdaptiveInferenceTestError?
  var loadGate: AdaptiveGate?
  var transcribeGate: AdaptiveGate?
  var releaseGate: AdaptiveGate?
  private(set) var events: [String] = []
  private(set) var loadedRepositories: [URL] = []
  private(set) var transcribedSamples: [[Float]] = []
  private(set) var cancelCount = 0
  private(set) var releaseCount = 0

  func load(from repositoryURL: URL) async throws {
    events.append("load:\(repositoryURL.lastPathComponent)")
    loadedRepositories.append(repositoryURL)
    if let loadGate {
      await loadGate.wait()
    }
    if let loadError {
      throw loadError
    }
  }

  func transcribe(_ samples: [Float]) async throws -> String {
    events.append("transcribe")
    transcribedSamples.append(samples)
    if let transcribeGate {
      await transcribeGate.wait()
    }
    if let transcribeError {
      throw transcribeError
    }
    return "transcript"
  }

  func cancel() async {
    events.append("cancel")
    cancelCount += 1
  }

  func releaseResources() async {
    events.append("release")
    releaseCount += 1
    if let releaseGate {
      await releaseGate.wait()
    }
  }
}

@MainActor
private final class AdaptiveGate {
  private var isOpen = false
  private var continuation: CheckedContinuation<Void, Never>?

  func wait() async {
    guard !isOpen else { return }
    await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  func open() {
    isOpen = true
    continuation?.resume()
    continuation = nil
  }
}

@MainActor
private final class AdaptiveCompletionProbe {
  private(set) var count = 0

  func record() {
    count += 1
  }
}

@MainActor
private final class AdaptiveManualSleeper {
  private var continuations: [CheckedContinuation<Void, Error>?] = []
  private(set) var requestedDurations: [Duration] = []

  var pendingCount: Int {
    continuations.compactMap { $0 }.count
  }

  func sleep(for duration: Duration) async throws {
    requestedDurations.append(duration)
    try await withCheckedThrowingContinuation { continuation in
      continuations.append(continuation)
    }
  }

  func resume(at index: Int) {
    guard continuations.indices.contains(index), let continuation = continuations[index] else {
      return
    }
    continuations[index] = nil
    continuation.resume()
  }

  func resumeAll() {
    for index in continuations.indices {
      resume(at: index)
    }
  }
}

@MainActor
private struct AdaptiveInferenceFixture {
  let inference: AdaptiveInferenceProbe
  let sleeper: AdaptiveManualSleeper
  let wrapper: AdaptiveEnhancedSpeechInference
}

@MainActor
private func makeFixture(
  installedMemoryGiB: UInt64 = 8,
  activeProcessorCount: Int = 8,
  reclaimableMemoryGiB: UInt64? = 6
) -> AdaptiveInferenceFixture {
  let inference = AdaptiveInferenceProbe()
  let sleeper = AdaptiveManualSleeper()
  let profile = DictationResourceProfile(
    installedMemoryBytes: installedMemoryGiB * gib,
    activeProcessorCount: activeProcessorCount
  )
  let snapshot = DictationResourceSnapshot(
    reclaimableMemoryBytes: reclaimableMemoryGiB.map { $0 * gib }
  )
  let wrapper = AdaptiveEnhancedSpeechInference(
    inference: inference,
    profile: profile,
    policy: .policy(memoryBytes: profile.installedMemoryBytes),
    snapshot: { snapshot },
    sleeper: { duration in
      try await sleeper.sleep(for: duration)
    }
  )
  return AdaptiveInferenceFixture(
    inference: inference,
    sleeper: sleeper,
    wrapper: wrapper
  )
}

@MainActor
private func drainAdaptiveTasks() async {
  for _ in 0..<8 {
    await Task.yield()
  }
}

private let gib: UInt64 = 1_024 * 1_024 * 1_024

private let adaptiveRepository = URL(fileURLWithPath: "/models/parakeet-a")
private let replacementRepository = URL(fileURLWithPath: "/models/parakeet-b")

@Test @MainActor
func healthyEightGiBReleaseSchedulesAtMostFifteenSecondsAndWarmLoadReusesRepository() async throws {
  let fixture = makeFixture()

  try await fixture.wrapper.load(from: adaptiveRepository)
  await fixture.wrapper.releaseResources()
  await drainAdaptiveTasks()

  #expect(fixture.sleeper.requestedDurations == [.seconds(15)])
  try await fixture.wrapper.load(from: adaptiveRepository)
  #expect(fixture.inference.loadedRepositories == [adaptiveRepository])

  await fixture.wrapper.releaseResources()
  await fixture.wrapper.forceCold()
  fixture.sleeper.resumeAll()
}

@Test @MainActor
func healthyTwentyFourGiBReleaseSchedulesOneHundredTwentySeconds() async throws {
  let fixture = makeFixture(
    installedMemoryGiB: 24,
    activeProcessorCount: 10,
    reclaimableMemoryGiB: 18
  )

  try await fixture.wrapper.load(from: adaptiveRepository)
  await fixture.wrapper.releaseResources()
  await drainAdaptiveTasks()

  #expect(fixture.sleeper.requestedDurations == [.seconds(120)])
  await fixture.wrapper.forceCold()
  fixture.sleeper.resumeAll()
}

@Test @MainActor
func lowReclaimableMemoryReleasesImmediatelyWithoutRetentionTimer() async throws {
  let fixture = makeFixture(reclaimableMemoryGiB: 1)

  try await fixture.wrapper.load(from: adaptiveRepository)
  await fixture.wrapper.releaseResources()

  #expect(fixture.inference.releaseCount == 1)
  #expect(fixture.sleeper.requestedDurations.isEmpty)
}

@Test @MainActor
func reacquisitionCancelsOldGenerationAndLateTimerCannotUnloadActiveUse() async throws {
  let fixture = makeFixture()

  try await fixture.wrapper.load(from: adaptiveRepository)
  await fixture.wrapper.releaseResources()
  await drainAdaptiveTasks()
  #expect(fixture.sleeper.pendingCount == 1)

  try await fixture.wrapper.load(from: adaptiveRepository)
  fixture.sleeper.resume(at: 0)
  await drainAdaptiveTasks()

  #expect(fixture.inference.loadedRepositories == [adaptiveRepository])
  #expect(fixture.inference.releaseCount == 0)

  await fixture.wrapper.releaseResources()
  await drainAdaptiveTasks()
  fixture.sleeper.resume(at: 1)
  await drainAdaptiveTasks()
  #expect(fixture.inference.releaseCount == 1)
}

@Test @MainActor
func retentionExpiryUnloadsExactlyOnce() async throws {
  let fixture = makeFixture()

  try await fixture.wrapper.load(from: adaptiveRepository)
  await fixture.wrapper.releaseResources()
  await drainAdaptiveTasks()
  fixture.sleeper.resume(at: 0)
  await drainAdaptiveTasks()

  await fixture.wrapper.releaseResources()
  #expect(fixture.inference.releaseCount == 1)
}

@Test @MainActor
func idleForceColdCancelsRetentionAndAwaitsColdRelease() async throws {
  let fixture = makeFixture()
  let releaseGate = AdaptiveGate()
  let completion = AdaptiveCompletionProbe()
  fixture.inference.releaseGate = releaseGate

  try await fixture.wrapper.load(from: adaptiveRepository)
  await fixture.wrapper.releaseResources()
  await drainAdaptiveTasks()
  #expect(fixture.inference.releaseCount == 0)

  let forceCold = Task { @MainActor in
    await fixture.wrapper.forceCold()
    completion.record()
  }
  await drainAdaptiveTasks()

  #expect(fixture.inference.releaseCount == 1)
  #expect(completion.count == 0)
  releaseGate.open()
  await forceCold.value

  #expect(completion.count == 1)
  fixture.sleeper.resumeAll()
}

@Test @MainActor
func activeForceColdWaitsForReleaseAndAllWaitersReturnCold() async throws {
  let fixture = makeFixture()
  let releaseGate = AdaptiveGate()
  let completion = AdaptiveCompletionProbe()
  fixture.inference.releaseGate = releaseGate

  try await fixture.wrapper.load(from: adaptiveRepository)
  let firstForceCold = Task { @MainActor in
    await fixture.wrapper.forceCold()
    completion.record()
  }
  let secondForceCold = Task { @MainActor in
    await fixture.wrapper.forceCold()
    completion.record()
  }
  await drainAdaptiveTasks()

  #expect(fixture.inference.releaseCount == 0)
  let release = Task { @MainActor in
    await fixture.wrapper.releaseResources()
  }
  await drainAdaptiveTasks()
  #expect(fixture.inference.releaseCount == 1)
  #expect(completion.count == 0)
  releaseGate.open()
  await release.value
  await firstForceCold.value
  await secondForceCold.value

  #expect(fixture.inference.releaseCount == 1)
  #expect(completion.count == 2)
}

@Test @MainActor
func forceColdDuringLoadWaitsForOuterReleaseBoundary() async throws {
  let fixture = makeFixture()
  let loadGate = AdaptiveGate()
  let completion = AdaptiveCompletionProbe()
  fixture.inference.loadGate = loadGate

  let loading = Task { @MainActor in
    try await fixture.wrapper.load(from: adaptiveRepository)
  }
  await drainAdaptiveTasks()
  let forceCold = Task { @MainActor in
    await fixture.wrapper.forceCold()
    completion.record()
  }
  await drainAdaptiveTasks()

  loadGate.open()
  try await loading.value

  #expect(fixture.inference.releaseCount == 0)
  #expect(completion.count == 0)
  await fixture.wrapper.releaseResources()
  await forceCold.value

  #expect(fixture.inference.releaseCount == 1)
  #expect(completion.count == 1)
}

@Test @MainActor
func forceColdDuringTranscriptionWaitsForOuterReleaseBoundary() async throws {
  let fixture = makeFixture()
  let transcribeGate = AdaptiveGate()
  let completion = AdaptiveCompletionProbe()
  fixture.inference.transcribeGate = transcribeGate

  try await fixture.wrapper.load(from: adaptiveRepository)
  let transcribing = Task { @MainActor in
    try await fixture.wrapper.transcribe([0.75])
  }
  await drainAdaptiveTasks()
  let forceCold = Task { @MainActor in
    await fixture.wrapper.forceCold()
    completion.record()
  }
  await drainAdaptiveTasks()

  transcribeGate.open()
  #expect(try await transcribing.value == "transcript")
  #expect(fixture.inference.releaseCount == 0)
  #expect(completion.count == 0)
  await fixture.wrapper.releaseResources()
  await forceCold.value

  #expect(fixture.inference.releaseCount == 1)
  #expect(completion.count == 1)
}

@Test @MainActor
func forceColdDuringRepositorySubstitutionAbortsRewarmBeforeReplacementLoad() async throws {
  let fixture = makeFixture()
  let releaseGate = AdaptiveGate()
  let completion = AdaptiveCompletionProbe()
  fixture.inference.releaseGate = releaseGate

  try await fixture.wrapper.load(from: adaptiveRepository)
  await fixture.wrapper.releaseResources()
  await drainAdaptiveTasks()

  let substitution = Task { @MainActor in
    do {
      try await fixture.wrapper.load(from: replacementRepository)
      return AdaptiveSubstitutionOutcome.succeeded
    } catch is CancellationError {
      return AdaptiveSubstitutionOutcome.cancellation
    } catch let error as DictationFailure where error == .unavailable {
      return AdaptiveSubstitutionOutcome.unavailable
    } catch {
      return AdaptiveSubstitutionOutcome.other
    }
  }
  await drainAdaptiveTasks()
  #expect(fixture.inference.events == ["load:parakeet-a", "release"])

  let forceCold = Task { @MainActor in
    await fixture.wrapper.forceCold()
    completion.record()
  }
  await drainAdaptiveTasks()
  releaseGate.open()

  let outcome = await substitution.value
  await forceCold.value
  #expect(outcome == .cancellation || outcome == .unavailable)
  #expect(fixture.inference.loadedRepositories == [adaptiveRepository])
  #expect(fixture.inference.releaseCount == 1)
  #expect(completion.count == 1)

  try await fixture.wrapper.load(from: replacementRepository)
  #expect(fixture.inference.loadedRepositories == [
    adaptiveRepository,
    replacementRepository,
  ])
  await fixture.wrapper.cancel()
  fixture.sleeper.resumeAll()
}

@Test @MainActor
func cancelDuringRepositorySubstitutionAbortsRewarmBeforeReplacementLoad() async throws {
  let fixture = makeFixture()
  let releaseGate = AdaptiveGate()
  let completion = AdaptiveCompletionProbe()
  fixture.inference.releaseGate = releaseGate

  try await fixture.wrapper.load(from: adaptiveRepository)
  await fixture.wrapper.releaseResources()
  await drainAdaptiveTasks()

  let substitution = Task { @MainActor in
    do {
      try await fixture.wrapper.load(from: replacementRepository)
      return AdaptiveSubstitutionOutcome.succeeded
    } catch is CancellationError {
      return AdaptiveSubstitutionOutcome.cancellation
    } catch let error as DictationFailure where error == .unavailable {
      return AdaptiveSubstitutionOutcome.unavailable
    } catch {
      return AdaptiveSubstitutionOutcome.other
    }
  }
  await drainAdaptiveTasks()
  #expect(fixture.inference.events == ["load:parakeet-a", "release"])

  let cancel = Task { @MainActor in
    await fixture.wrapper.cancel()
    completion.record()
  }
  await drainAdaptiveTasks()
  releaseGate.open()

  let outcome = await substitution.value
  await cancel.value
  #expect(outcome == .cancellation || outcome == .unavailable)
  #expect(fixture.inference.loadedRepositories == [adaptiveRepository])
  #expect(fixture.inference.cancelCount == 0)
  #expect(fixture.inference.releaseCount == 1)
  #expect(completion.count == 1)

  try await fixture.wrapper.load(from: replacementRepository)
  #expect(fixture.inference.loadedRepositories == [
    adaptiveRepository,
    replacementRepository,
  ])
  await fixture.wrapper.cancel()
  fixture.sleeper.resumeAll()
}

@Test @MainActor
func cancelPerformsOneCancelAndReleaseAndNextLoadStartsCold() async throws {
  let fixture = makeFixture()

  try await fixture.wrapper.load(from: adaptiveRepository)
  await fixture.wrapper.cancel()
  await fixture.wrapper.cancel()
  await fixture.wrapper.releaseResources()

  #expect(fixture.inference.cancelCount == 1)
  #expect(fixture.inference.releaseCount == 1)

  try await fixture.wrapper.load(from: adaptiveRepository)
  #expect(fixture.inference.loadedRepositories == [adaptiveRepository, adaptiveRepository])
  await fixture.wrapper.cancel()
}

@Test @MainActor
func loadFailureReleasesBeforeRethrowingExactError() async {
  let fixture = makeFixture()
  fixture.inference.loadError = .load

  await #expect(throws: AdaptiveInferenceTestError.load) {
    try await fixture.wrapper.load(from: adaptiveRepository)
  }

  #expect(fixture.inference.events == ["load:parakeet-a", "release"])
}

@Test @MainActor
func transcribeFailureReleasesBeforeRethrowingExactError() async throws {
  let fixture = makeFixture()
  fixture.inference.transcribeError = .transcribe
  try await fixture.wrapper.load(from: adaptiveRepository)

  await #expect(throws: AdaptiveInferenceTestError.transcribe) {
    try await fixture.wrapper.transcribe([0.25])
  }

  #expect(fixture.inference.events == ["load:parakeet-a", "transcribe", "release"])
}

@Test @MainActor
func repositorySubstitutionReleasesOldRepositoryBeforeLoadingNewOne() async throws {
  let fixture = makeFixture()

  try await fixture.wrapper.load(from: adaptiveRepository)
  await fixture.wrapper.releaseResources()
  await drainAdaptiveTasks()
  try await fixture.wrapper.load(from: replacementRepository)

  #expect(fixture.inference.events == [
    "load:parakeet-a",
    "release",
    "load:parakeet-b",
  ])
  await fixture.wrapper.cancel()
  fixture.sleeper.resumeAll()
}

@Test @MainActor
func repeatedReleaseDoesNotExtendTimerOrDoubleRelease() async throws {
  let fixture = makeFixture()

  try await fixture.wrapper.load(from: adaptiveRepository)
  await fixture.wrapper.releaseResources()
  await fixture.wrapper.releaseResources()
  await drainAdaptiveTasks()
  #expect(fixture.sleeper.requestedDurations == [.seconds(15)])
  #expect(fixture.inference.releaseCount == 0)

  fixture.sleeper.resume(at: 0)
  await drainAdaptiveTasks()
  await fixture.wrapper.releaseResources()

  #expect(fixture.inference.releaseCount == 1)
  #expect(fixture.sleeper.requestedDurations == [.seconds(15)])
}

@Test @MainActor
func overlappingLoadsFailClosedWithoutStartingSecondUnderlyingLoad() async throws {
  let fixture = makeFixture()
  let gate = AdaptiveGate()
  fixture.inference.loadGate = gate

  let firstLoad = Task { @MainActor in
    try await fixture.wrapper.load(from: adaptiveRepository)
  }
  await drainAdaptiveTasks()

  await #expect(throws: DictationFailure.unavailable) {
    try await fixture.wrapper.load(from: replacementRepository)
  }
  #expect(fixture.inference.loadedRepositories == [adaptiveRepository])

  gate.open()
  try await firstLoad.value
  await fixture.wrapper.cancel()
}

@Test @MainActor
func transcribeRequiresAnActiveLoadedUse() async {
  let fixture = makeFixture()

  await #expect(throws: DictationFailure.unavailable) {
    try await fixture.wrapper.transcribe([0.5])
  }

  #expect(fixture.inference.transcribedSamples.isEmpty)
}

@Test @MainActor
func dictationDiagnosticsAdaptiveLoadDispositionIsColdWarmOrUnavailableFromObservedState() async throws {
  let fixture = makeFixture()

  #expect(fixture.wrapper.loadDisposition(for: adaptiveRepository) == .cold)
  try await fixture.wrapper.load(from: adaptiveRepository)
  #expect(fixture.wrapper.loadDisposition(for: adaptiveRepository) == nil)
  await fixture.wrapper.releaseResources()
  #expect(fixture.wrapper.loadDisposition(for: adaptiveRepository) == .warm)
  #expect(fixture.wrapper.loadDisposition(for: replacementRepository) == .cold)

  await fixture.wrapper.forceCold()
  fixture.sleeper.resumeAll()
}
#endif
