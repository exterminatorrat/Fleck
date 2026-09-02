import Foundation
import Testing

@testable import FleckApp

@Test func acquireWithoutPreparationLoadsASRAndEntersActive() async throws {
  let asr = FakeRuntimeAdapter(role: .asr)
  let cleanup = FakeRuntimeAdapter(role: .cleanup)
  let sleeper = ManualRuntimeSleeper()
  let runtime = makeRuntime(asr: asr, cleanup: cleanup, sleeper: sleeper)

  _ = try await runtime.acquireCaptureLease()

  #expect(await asr.loadCallCount == 1)
  #expect(await cleanup.loadCallCount == 1)
  #expect(await runtime.snapshot() == LocalDictationRuntimeSnapshot(
    residency: .active,
    asrHealth: .available,
    cleanupHealth: .available,
    hasActiveLease: true
  ))
}

@Test func overlappingCaptureLeaseIsRejected() async throws {
  let asr = FakeRuntimeAdapter(role: .asr)
  let cleanup = FakeRuntimeAdapter(role: .cleanup)
  let sleeper = ManualRuntimeSleeper()
  let runtime = makeRuntime(asr: asr, cleanup: cleanup, sleeper: sleeper)

  _ = try await runtime.acquireCaptureLease()

  await #expect(throws: LocalDictationRuntimeError.captureLeaseAlreadyActive) {
    try await runtime.acquireCaptureLease()
  }
}

@Test func releasingCaptureLeaseEntersWarmResidency() async throws {
  let asr = FakeRuntimeAdapter(role: .asr)
  let cleanup = FakeRuntimeAdapter(role: .cleanup)
  let sleeper = ManualRuntimeSleeper()
  let runtime = makeRuntime(asr: asr, cleanup: cleanup, sleeper: sleeper)
  let lease = try await runtime.acquireCaptureLease()

  await runtime.releaseCaptureLease(lease)
  await sleeper.waitUntilPendingCount(1)

  #expect(await runtime.snapshot().residency == .warm)
  #expect(await asr.unloadCallCount == 0)
  #expect(await cleanup.unloadCallCount == 0)

  await runtime.handle(.memoryCritical)
  await sleeper.resumeAll()
}

@Test func warmExpiryUnloadsCleanupAndEntersStandby() async throws {
  let asr = FakeRuntimeAdapter(role: .asr)
  let cleanup = FakeRuntimeAdapter(role: .cleanup)
  let sleeper = ManualRuntimeSleeper()
  let runtime = makeRuntime(asr: asr, cleanup: cleanup, sleeper: sleeper)
  let lease = try await runtime.acquireCaptureLease()
  await runtime.releaseCaptureLease(lease)
  await sleeper.waitUntilPendingCount(1)

  await sleeper.resumeNext()
  await cleanup.waitUntilUnloadCallCount(1)
  await sleeper.waitUntilPendingCount(1)

  #expect(await cleanup.unloadCallCount == 1)
  #expect(await asr.unloadCallCount == 0)
  #expect(await runtime.snapshot().residency == .standby)

  await runtime.handle(.memoryCritical)
  await sleeper.resumeAll()
}

@Test func standbyExpiryUnloadsASRAndEntersCold() async {
  let asr = FakeRuntimeAdapter(role: .asr)
  let cleanup = FakeRuntimeAdapter(role: .cleanup)
  let sleeper = ManualRuntimeSleeper()
  let runtime = makeRuntime(asr: asr, cleanup: cleanup, sleeper: sleeper)

  await runtime.prepare(for: .likelyCapture)
  await sleeper.waitUntilPendingCount(1)
  await sleeper.resumeNext()
  await asr.waitUntilUnloadCallCount(1)

  #expect(await asr.unloadCallCount == 1)
  #expect(await runtime.snapshot().residency == .cold)
  await sleeper.resumeAll()
}

@Test func likelyCapturePreparationLoadsASROnlyAndEntersStandby() async {
  let asr = FakeRuntimeAdapter(role: .asr)
  let cleanup = FakeRuntimeAdapter(role: .cleanup)
  let sleeper = ManualRuntimeSleeper()
  let runtime = makeRuntime(asr: asr, cleanup: cleanup, sleeper: sleeper)

  await runtime.prepare(for: .likelyCapture)
  await sleeper.waitUntilPendingCount(1)

  #expect(await asr.loadCallCount == 1)
  #expect(await cleanup.loadCallCount == 0)
  #expect(await runtime.snapshot().residency == .standby)

  await runtime.handle(.memoryCritical)
  await sleeper.resumeAll()
}

@Test func immediateCapturePreparationLoadsBothAdaptersAndEntersWarm() async {
  let asr = FakeRuntimeAdapter(role: .asr)
  let cleanup = FakeRuntimeAdapter(role: .cleanup)
  let sleeper = ManualRuntimeSleeper()
  let runtime = makeRuntime(asr: asr, cleanup: cleanup, sleeper: sleeper)

  await runtime.prepare(for: .immediateCapture)
  await sleeper.waitUntilPendingCount(1)

  #expect(await asr.loadCallCount == 1)
  #expect(await cleanup.loadCallCount == 1)
  #expect(await runtime.snapshot().residency == .warm)

  await runtime.handle(.memoryCritical)
  await sleeper.resumeAll()
}

@Test func preparationAndConcurrentAcquireReuseOneInFlightASRLoad() async throws {
  let asrLoadGate = AsyncRuntimeGate()
  let asr = FakeRuntimeAdapter(role: .asr, loadGate: asrLoadGate)
  let cleanup = FakeRuntimeAdapter(role: .cleanup)
  let sleeper = ManualRuntimeSleeper()
  let runtime = makeRuntime(asr: asr, cleanup: cleanup, sleeper: sleeper)

  let preparation = Task {
    await runtime.prepare(for: .immediateCapture)
  }
  await asrLoadGate.waitUntilWaiting()

  let concurrentPreparation = Task {
    await runtime.prepare(for: .likelyCapture)
  }
  let acquisition = Task {
    try await runtime.acquireCaptureLease()
  }
  await Task.yield()

  #expect(await asr.loadCallCount == 1)

  await asrLoadGate.openGate()
  await preparation.value
  await concurrentPreparation.value
  let lease = try await acquisition.value

  #expect(await asr.loadCallCount == 1)
  #expect(await cleanup.loadCallCount == 1)
  #expect(await runtime.snapshot().residency == .active)

  await runtime.releaseCaptureLease(lease)
  await runtime.handle(.memoryCritical)
  await sleeper.resumeAll()
}

@Test func acquisitionInvalidatesStandbyExpiryBeforeCleanupLoad() async throws {
  let cleanupLoadGate = AsyncRuntimeGate()
  let asr = FakeRuntimeAdapter(role: .asr)
  let cleanup = FakeRuntimeAdapter(
    role: .cleanup,
    loadGates: [cleanupLoadGate]
  )
  let sleeper = ManualRuntimeSleeper()
  let runtime = makeRuntime(asr: asr, cleanup: cleanup, sleeper: sleeper)

  await runtime.prepare(for: .likelyCapture)
  await sleeper.waitUntilPendingCount(1)

  let acquisition = Task {
    await captureLeaseResult(from: runtime)
  }
  await cleanupLoadGate.waitUntilWaiting()

  await sleeper.resumeNext()
  await Task.yield()
  #expect(await asr.unloadCallCount == 0)

  await cleanupLoadGate.openGate()
  let result = await acquisition.value
  guard case .success(let lease) = result else {
    #expect(Bool(false), "acquisition failed while an idle transition was in flight")
    await sleeper.resumeAll()
    return
  }

  #expect(await asr.loadCallCount == 1)
  #expect(await cleanup.loadCallCount == 1)
  #expect(await asr.unloadCallCount == 0)
  #expect(await asr.isLoaded)
  #expect(await runtime.snapshot().residency == .active)

  await runtime.releaseCaptureLease(lease)
  await runtime.handle(.memoryCritical)
  await sleeper.resumeAll()
}

@Test func idleWarningEntersStandbyAndIdleCriticalEntersCold() async throws {
  let asr = FakeRuntimeAdapter(role: .asr)
  let cleanup = FakeRuntimeAdapter(role: .cleanup)
  let sleeper = ManualRuntimeSleeper()
  let runtime = makeRuntime(asr: asr, cleanup: cleanup, sleeper: sleeper)
  let lease = try await runtime.acquireCaptureLease()
  await runtime.releaseCaptureLease(lease)
  await sleeper.waitUntilPendingCount(1)

  await runtime.handle(.memoryWarning)
  await cleanup.waitUntilUnloadCallCount(1)
  #expect(await runtime.snapshot().residency == .standby)

  await runtime.handle(.memoryCritical)
  await asr.waitUntilUnloadCallCount(1)
  #expect(await runtime.snapshot().residency == .cold)
  await sleeper.resumeAll()
}

@Test func failedAuthoritativeASRLoadCompletesPendingModelMutation() async throws {
  let asrLoadGate = AsyncRuntimeGate()
  let asr = FakeRuntimeAdapter(
    role: .asr,
    loadOutcomes: [
      .failure(.loadFailed),
      .success(()),
    ],
    loadGate: asrLoadGate
  )
  let cleanup = FakeRuntimeAdapter(role: .cleanup)
  let sleeper = ManualRuntimeSleeper()
  let runtime = makeRuntime(asr: asr, cleanup: cleanup, sleeper: sleeper)
  let completions = RuntimeCompletionProbe()

  let firstAcquisition = Task {
    await captureLeaseResult(from: runtime)
  }
  await asrLoadGate.waitUntilWaiting()

  let mutation = Task {
    await runtime.waitUntilColdForModelMutation()
    await completions.mark()
  }
  await Task.yield()
  #expect(await completions.count == 0)

  await asrLoadGate.openGate()
  let firstResult = await firstAcquisition.value
  guard case .failure(.adapterLoadFailed(.asr)) = firstResult else {
    #expect(Bool(false), "the first authoritative ASR load did not fail as configured")
    mutation.cancel()
    return
  }

  let secondResult = await captureLeaseResult(from: runtime)
  guard case .success(let lease) = secondResult else {
    #expect(Bool(false), "the failed load left model mutation pending")
    #expect(await completions.count == 1)
    mutation.cancel()
    return
  }

  await mutation.value
  #expect(await completions.count == 1)
  #expect(await runtime.snapshot().residency == .active)
  #expect(await asr.loadCallCount == 2)
  #expect(await cleanup.loadCallCount == 1)

  await runtime.releaseCaptureLease(lease)
  await runtime.handle(.memoryCritical)
  await sleeper.resumeAll()
}

@Test func failedImmediatePreparationDoesNotLoadCleanup() async {
  let asr = FakeRuntimeAdapter(
    role: .asr,
    loadOutcomes: [.failure(.loadFailed)]
  )
  let cleanup = FakeRuntimeAdapter(role: .cleanup)
  let sleeper = ManualRuntimeSleeper()
  let runtime = makeRuntime(asr: asr, cleanup: cleanup, sleeper: sleeper)

  await runtime.prepare(for: .immediateCapture)

  #expect(await asr.loadCallCount == 1)
  #expect(await cleanup.loadCallCount == 0)
  #expect(await cleanup.isLoaded == false)
  #expect(await sleeper.pendingCount == 0)
  #expect(await runtime.snapshot().residency == .cold)
}

@Test func immediatePreparationUpgradesLikelyPreparationWithoutDuplicateLoads() async {
  let asrLoadGate = AsyncRuntimeGate()
  let asr = FakeRuntimeAdapter(role: .asr, loadGate: asrLoadGate)
  let cleanup = FakeRuntimeAdapter(role: .cleanup)
  let sleeper = ManualRuntimeSleeper()
  let runtime = makeRuntime(asr: asr, cleanup: cleanup, sleeper: sleeper)

  let likelyPreparation = Task {
    await runtime.prepare(for: .likelyCapture)
  }
  await asrLoadGate.waitUntilWaiting()

  let immediatePreparation = Task {
    await runtime.prepare(for: .immediateCapture)
  }
  await asrLoadGate.openGate()
  await likelyPreparation.value
  await immediatePreparation.value
  await sleeper.waitUntilPendingCount(1)

  #expect(await asr.loadCallCount == 1)
  #expect(await cleanup.loadCallCount == 1)
  #expect(await runtime.snapshot().residency == .warm)
  #expect(await sleeper.pendingCount >= 1)

  await runtime.handle(.memoryCritical)
  await sleeper.resumeAll()
}

@Test func queuedAcquisitionWaitsForImmediatePreparationUpgrade() async throws {
  let asrLoadGate = AsyncRuntimeGate()
  let cleanupLoadGate = AsyncRuntimeGate()
  let asr = FakeRuntimeAdapter(role: .asr, loadGate: asrLoadGate)
  let cleanup = FakeRuntimeAdapter(
    role: .cleanup,
    loadGates: [cleanupLoadGate]
  )
  let sleeper = ManualRuntimeSleeper()
  let runtime = makeRuntime(asr: asr, cleanup: cleanup, sleeper: sleeper)
  let completions = RuntimeCompletionProbe()

  let likelyPreparation = Task {
    await runtime.prepare(for: .likelyCapture)
  }
  await asrLoadGate.waitUntilWaiting()

  let immediatePreparation = Task {
    await runtime.prepare(for: .immediateCapture)
  }
  await Task.yield()
  let acquisition = Task {
    let result = await captureLeaseResult(from: runtime)
    if case .success = result {
      await completions.mark()
    }
    return result
  }
  await Task.yield()

  await asrLoadGate.openGate()
  await cleanupLoadGate.waitUntilWaiting()
  for _ in 0..<3 {
    await Task.yield()
  }

  #expect(await cleanup.loadCallCount == 1)
  #expect(await completions.count == 0)

  await cleanupLoadGate.openGate()
  await likelyPreparation.value
  await immediatePreparation.value
  let result = await acquisition.value
  guard case .success(let lease) = result else {
    #expect(Bool(false), "acquisition did not wait for the immediate preparation")
    await sleeper.resumeAll()
    return
  }

  #expect(await cleanup.loadCallCount == 1)
  #expect(await completions.count == 1)
  await runtime.releaseCaptureLease(lease)
  await runtime.handle(.memoryCritical)
  await sleeper.resumeAll()
}

@Test func criticalSignalWaitsForPreparationUpgradeAndLeavesRuntimeCold() async {
  let asrLoadGate = AsyncRuntimeGate()
  let cleanupLoadGate = AsyncRuntimeGate()
  let asr = FakeRuntimeAdapter(role: .asr, loadGate: asrLoadGate)
  let cleanup = FakeRuntimeAdapter(
    role: .cleanup,
    loadGates: [cleanupLoadGate]
  )
  let sleeper = ManualRuntimeSleeper()
  let runtime = makeRuntime(asr: asr, cleanup: cleanup, sleeper: sleeper)
  let completions = RuntimeCompletionProbe()

  let likelyPreparation = Task {
    await runtime.prepare(for: .likelyCapture)
  }
  await asrLoadGate.waitUntilWaiting()
  let immediatePreparation = Task {
    await runtime.prepare(for: .immediateCapture)
  }
  await Task.yield()
  let criticalSignal = Task {
    await runtime.handle(.memoryCritical)
    await completions.mark()
  }
  await Task.yield()

  await asrLoadGate.openGate()
  await cleanupLoadGate.waitUntilWaiting()
  for _ in 0..<3 {
    await Task.yield()
  }

  #expect(await completions.count == 0)
  #expect(await asr.unloadCallCount == 0)
  #expect(await cleanup.unloadCallCount == 0)

  await cleanupLoadGate.openGate()
  await likelyPreparation.value
  await immediatePreparation.value
  await criticalSignal.value

  #expect(await completions.count == 1)
  #expect(await cleanup.loadCallCount == 1)
  #expect(await asr.unloadCallCount == 1)
  #expect(await cleanup.unloadCallCount == 1)
  #expect(await runtime.snapshot() == LocalDictationRuntimeSnapshot(
    residency: .cold,
    asrHealth: .available,
    cleanupHealth: .available,
    hasActiveLease: false
  ))
  await sleeper.resumeAll()
}

@Test func lifecycleWaiterCannotPreemptPendingImmediatePreparationUpgrade() async {
  let asrLoadGate = AsyncRuntimeGate()
  let asr = FakeRuntimeAdapter(role: .asr, loadGate: asrLoadGate)
  let cleanup = FakeRuntimeAdapter(role: .cleanup)
  let sleeper = ManualRuntimeSleeper()
  let runtime = makeRuntime(asr: asr, cleanup: cleanup, sleeper: sleeper)
  let completions = RuntimeCompletionProbe()

  let likelyPreparation = Task {
    await runtime.prepare(for: .likelyCapture)
  }
  await asrLoadGate.waitUntilWaiting()

  let criticalSignal = Task {
    await runtime.handle(.memoryCritical)
    await completions.mark()
  }
  await Task.yield()
  let immediatePreparation = Task {
    await runtime.prepare(for: .immediateCapture)
  }
  await Task.yield()

  await asrLoadGate.openGate()
  await likelyPreparation.value
  await criticalSignal.value
  await immediatePreparation.value

  #expect(await completions.count == 1)
  #expect(await asr.loadCallCount == 1)
  #expect(await cleanup.loadCallCount == 1)
  #expect(await asr.unloadCallCount == 1)
  #expect(await cleanup.unloadCallCount == 1)
  #expect(await runtime.snapshot() == LocalDictationRuntimeSnapshot(
    residency: .cold,
    asrHealth: .available,
    cleanupHealth: .available,
    hasActiveLease: false
  ))
  await sleeper.resumeAll()
}

@Test func multipleImmediatePreparationRequestsCoalesceBeforeWaitersResume() async {
  let asrLoadGate = AsyncRuntimeGate()
  let cleanupLoadGate = AsyncRuntimeGate()
  let asr = FakeRuntimeAdapter(role: .asr, loadGate: asrLoadGate)
  let cleanup = FakeRuntimeAdapter(
    role: .cleanup,
    loadGates: [cleanupLoadGate]
  )
  let sleeper = ManualRuntimeSleeper()
  let runtime = makeRuntime(asr: asr, cleanup: cleanup, sleeper: sleeper)
  let completions = RuntimeCompletionProbe()

  let likelyPreparation = Task {
    await runtime.prepare(for: .likelyCapture)
  }
  await asrLoadGate.waitUntilWaiting()
  let firstImmediatePreparation = Task {
    await runtime.prepare(for: .immediateCapture)
    await completions.mark()
  }
  await Task.yield()
  let secondImmediatePreparation = Task {
    await runtime.prepare(for: .immediateCapture)
    await completions.mark()
  }
  await Task.yield()

  await asrLoadGate.openGate()
  await cleanupLoadGate.waitUntilWaiting()
  for _ in 0..<3 {
    await Task.yield()
  }

  #expect(await cleanup.loadCallCount == 1)
  #expect(await completions.count == 0)

  await cleanupLoadGate.openGate()
  await likelyPreparation.value
  await firstImmediatePreparation.value
  await secondImmediatePreparation.value

  #expect(await cleanup.loadCallCount == 1)
  #expect(await completions.count == 2)
  #expect(await runtime.snapshot().residency == .warm)
  await runtime.handle(.memoryCritical)
  await sleeper.resumeAll()
}

@Test func preparationDuringActiveLeaseDoesNotStartAdapterWork() async throws {
  let asr = FakeRuntimeAdapter(role: .asr)
  let cleanup = FakeRuntimeAdapter(role: .cleanup)
  let sleeper = ManualRuntimeSleeper()
  let runtime = makeRuntime(asr: asr, cleanup: cleanup, sleeper: sleeper)
  let lease = try await runtime.acquireCaptureLease()
  let asrLoads = await asr.loadCallCount
  let cleanupLoads = await cleanup.loadCallCount

  await runtime.prepare(for: .immediateCapture)

  #expect(await asr.loadCallCount == asrLoads)
  #expect(await cleanup.loadCallCount == cleanupLoads)
  #expect(await runtime.snapshot().hasActiveLease)
  await runtime.releaseCaptureLease(lease)
  await runtime.handle(.memoryCritical)
  await sleeper.resumeAll()
}

@Test func captureWaitsForInFlightIdleUnloadBeforeAcquiring() async throws {
  let cleanupUnloadGate = AsyncRuntimeGate()
  let asr = FakeRuntimeAdapter(role: .asr)
  let cleanup = FakeRuntimeAdapter(role: .cleanup, unloadGate: cleanupUnloadGate)
  let sleeper = ManualRuntimeSleeper()
  let runtime = makeRuntime(asr: asr, cleanup: cleanup, sleeper: sleeper)

  await runtime.prepare(for: .immediateCapture)
  await sleeper.waitUntilPendingCount(1)
  await sleeper.resumeNext()
  await cleanup.waitUntilUnloadCallCount(1)
  await cleanupUnloadGate.waitUntilWaiting()

  let firstAcquisition = Task {
    await captureLeaseResult(from: runtime)
  }
  let secondAcquisition = Task {
    await captureLeaseResult(from: runtime)
  }
  await Task.yield()

  #expect(await cleanup.unloadCallCount == 1)
  await cleanupUnloadGate.openGate()

  let results = [await firstAcquisition.value, await secondAcquisition.value]
  let leases = results.compactMap { result -> UUID? in
    guard case .success(let lease) = result else { return nil }
    return lease
  }
  #expect(leases.count == 1)
  #expect(results.contains { result in
    guard case .failure(.captureLeaseAlreadyActive) = result else { return false }
    return true
  })
  #expect(await asr.loadCallCount == 1)
  #expect(await cleanup.loadCallCount == 2)
  #expect(await cleanup.unloadCallCount == 1)
  #expect(await runtime.snapshot().residency == .active)

  if let lease = leases.first {
    await runtime.releaseCaptureLease(lease)
  }
  await runtime.handle(.memoryCritical)
  await sleeper.resumeAll()
}

@Test func activeLifecycleSignalsNeverUnloadAdapters() async throws {
  let asr = FakeRuntimeAdapter(role: .asr)
  let cleanup = FakeRuntimeAdapter(role: .cleanup)
  let sleeper = ManualRuntimeSleeper()
  let runtime = makeRuntime(asr: asr, cleanup: cleanup, sleeper: sleeper)
  _ = try await runtime.acquireCaptureLease()

  let signals: [DictationRuntimeSignal] = [
    .memoryWarning,
    .memoryCritical,
    .thermalSerious,
    .thermalCritical,
    .lowPowerMode(true),
    .lowPowerMode(false),
    .willSleep,
    .didWake,
    .modelMutationWillBegin,
  ]
  for signal in signals {
    await runtime.handle(signal)
  }

  #expect(await runtime.snapshot().residency == .active)
  #expect(await asr.unloadCallCount == 0)
  #expect(await cleanup.unloadCallCount == 0)
}

@Test func cancellationKeepsLeaseReservedUntilEveryAdapterCancelCompletes() async throws {
  let asrCancelGate = AsyncRuntimeGate()
  let cleanupCancelGate = AsyncRuntimeGate()
  let asr = FakeRuntimeAdapter(role: .asr, cancelGate: asrCancelGate)
  let cleanup = FakeRuntimeAdapter(role: .cleanup, cancelGate: cleanupCancelGate)
  let sleeper = ManualRuntimeSleeper()
  let runtime = makeRuntime(asr: asr, cleanup: cleanup, sleeper: sleeper)
  let lease = try await runtime.acquireCaptureLease()

  let progress = RuntimeProgressRace()
  let cancellation = Task {
    await runtime.cancelCaptureLease(lease)
    await progress.signal(.finished)
  }
  let cleanupCancellation = Task {
    await cleanupCancelGate.waitUntilWaiting()
    await progress.signal(.cleanupCancellationStarted)
  }
  await asrCancelGate.waitUntilWaiting()

  await #expect(throws: LocalDictationRuntimeError.captureLeaseAlreadyActive) {
    try await runtime.acquireCaptureLease()
  }
  #expect(await runtime.snapshot().hasActiveLease)

  await asrCancelGate.openGate()
  let observed = await progress.wait()
  #expect(observed == .cleanupCancellationStarted)
  #expect(await asr.cancelCallCount == 1)
  #expect(await cleanup.cancelCallCount == 1)
  #expect(await runtime.snapshot().hasActiveLease)
  await #expect(throws: LocalDictationRuntimeError.captureLeaseAlreadyActive) {
    try await runtime.acquireCaptureLease()
  }

  await cleanupCancelGate.openGate()
  await cancellation.value
  await cleanupCancellation.value
  await sleeper.waitUntilPendingCount(1)
  #expect(await cleanup.cancelCallCount == 1)
  #expect(await runtime.snapshot().residency == .warm)

  await runtime.handle(.memoryCritical)
  await sleeper.resumeAll()
}

@Test func modelMutationWaitsForSuspendedPreparationBeforeForcingCold() async throws {
  let asrLoadGate = AsyncRuntimeGate()
  let asr = FakeRuntimeAdapter(role: .asr, loadGate: asrLoadGate)
  let cleanup = FakeRuntimeAdapter(role: .cleanup)
  let sleeper = ManualRuntimeSleeper()
  let runtime = makeRuntime(asr: asr, cleanup: cleanup, sleeper: sleeper)
  let completions = RuntimeCompletionProbe()

  let preparation = Task {
    await runtime.prepare(for: .immediateCapture)
  }
  await asrLoadGate.waitUntilWaiting()

  let mutation = Task {
    await runtime.waitUntilColdForModelMutation()
    await completions.mark()
  }
  await Task.yield()
  #expect(await completions.count == 0)
  #expect(await asr.unloadCallCount == 0)

  await asrLoadGate.openGate()
  await preparation.value
  await mutation.value

  #expect(await completions.count == 1)
  #expect(await asr.unloadCallCount == 1)
  #expect(await cleanup.unloadCallCount == 1)
  #expect(await runtime.snapshot().residency == .cold)
  await sleeper.resumeAll()
}

@Test func modelMutationDuringStandbyTransitionSerializesCleanupUnload() async throws {
  let cleanupUnloadGate = AsyncRuntimeGate()
  let asr = FakeRuntimeAdapter(role: .asr)
  let cleanup = FakeRuntimeAdapter(role: .cleanup, unloadGate: cleanupUnloadGate)
  let sleeper = ManualRuntimeSleeper()
  let runtime = makeRuntime(asr: asr, cleanup: cleanup, sleeper: sleeper)
  let lease = try await runtime.acquireCaptureLease()
  await runtime.releaseCaptureLease(lease)
  await sleeper.waitUntilPendingCount(1)

  await sleeper.resumeNext()
  await cleanup.waitUntilUnloadCallCount(1)
  await cleanupUnloadGate.waitUntilWaiting()

  let completions = RuntimeCompletionProbe()
  let mutation = Task {
    await runtime.waitUntilColdForModelMutation()
    await completions.mark()
  }
  await Task.yield()
  #expect(await completions.count == 0)
  #expect(await cleanup.unloadCallCount == 1)
  await #expect(throws: LocalDictationRuntimeError.modelMutationInProgress) {
    try await runtime.acquireCaptureLease()
  }

  await cleanupUnloadGate.openGate()
  await mutation.value

  #expect(await completions.count == 1)
  #expect(await cleanup.unloadCallCount == 1)
  #expect(await asr.unloadCallCount == 1)
  #expect(await runtime.snapshot().residency == .cold)
  await sleeper.resumeAll()
}

@Test func activeModelMutationWaitersBlockReacquireUntilReleaseMakesRuntimeCold() async throws {
  let asrUnloadGate = AsyncRuntimeGate()
  let asr = FakeRuntimeAdapter(role: .asr, unloadGate: asrUnloadGate)
  let cleanup = FakeRuntimeAdapter(role: .cleanup)
  let sleeper = ManualRuntimeSleeper()
  let runtime = makeRuntime(asr: asr, cleanup: cleanup, sleeper: sleeper)
  let lease = try await runtime.acquireCaptureLease()
  let completions = RuntimeCompletionProbe()

  let firstWaiter = Task {
    await runtime.waitUntilColdForModelMutation()
    await completions.mark()
  }
  await Task.yield()
  let secondWaiter = Task {
    await runtime.waitUntilColdForModelMutation()
    await completions.mark()
  }
  await Task.yield()

  await #expect(throws: LocalDictationRuntimeError.modelMutationInProgress) {
    try await runtime.acquireCaptureLease()
  }

  let release = Task {
    await runtime.releaseCaptureLease(lease)
  }
  await asrUnloadGate.waitUntilWaiting()
  #expect(await completions.count == 0)
  await #expect(throws: LocalDictationRuntimeError.modelMutationInProgress) {
    try await runtime.acquireCaptureLease()
  }

  await asrUnloadGate.openGate()
  await release.value
  await firstWaiter.value
  await secondWaiter.value

  #expect(await completions.count == 2)
  #expect(await runtime.snapshot() == LocalDictationRuntimeSnapshot(
    residency: .cold,
    asrHealth: .available,
    cleanupHealth: .available,
    hasActiveLease: false
  ))
}

@Test func idleModelMutationReturnsOnlyAfterForcingCold() async throws {
  let asr = FakeRuntimeAdapter(role: .asr)
  let cleanup = FakeRuntimeAdapter(role: .cleanup)
  let sleeper = ManualRuntimeSleeper()
  let runtime = makeRuntime(asr: asr, cleanup: cleanup, sleeper: sleeper)
  let lease = try await runtime.acquireCaptureLease()
  await runtime.releaseCaptureLease(lease)
  await sleeper.waitUntilPendingCount(1)

  await runtime.waitUntilColdForModelMutation()

  #expect(await asr.unloadCallCount == 1)
  #expect(await cleanup.unloadCallCount == 1)
  #expect(await runtime.snapshot().residency == .cold)
  await sleeper.resumeAll()
}

@Test func twoASRLoadFailuresMakeASRUnavailableWithoutAThirdLoad() async throws {
  let asr = FakeRuntimeAdapter(
    role: .asr,
    loadOutcomes: [
      .failure(.loadFailed),
      .failure(.loadFailed),
    ]
  )
  let cleanup = FakeRuntimeAdapter(role: .cleanup)
  let sleeper = ManualRuntimeSleeper()
  let runtime = makeRuntime(asr: asr, cleanup: cleanup, sleeper: sleeper)

  await runtime.prepare(for: .likelyCapture)
  #expect(await runtime.snapshot().asrHealth == .available)
  await #expect(throws: LocalDictationRuntimeError.adapterLoadFailed(.asr)) {
    try await runtime.acquireCaptureLease()
  }
  #expect(await runtime.snapshot().asrHealth == .unavailable)
  await #expect(throws: LocalDictationRuntimeError.adapterUnavailable(.asr)) {
    try await runtime.acquireCaptureLease()
  }
  #expect(await asr.loadCallCount == 2)
}

@Test func repeatedCleanupFailureLeavesASRCaptureAvailableAndMarksCleanupUnavailable() async throws {
  let asr = FakeRuntimeAdapter(role: .asr)
  let cleanup = FakeRuntimeAdapter(
    role: .cleanup,
    loadOutcomes: [
      .failure(.loadFailed),
      .failure(.loadFailed),
    ]
  )
  let sleeper = ManualRuntimeSleeper()
  let runtime = makeRuntime(asr: asr, cleanup: cleanup, sleeper: sleeper)

  let firstLease = try await runtime.acquireCaptureLease()
  await runtime.releaseCaptureLease(firstLease)
  await sleeper.waitUntilPendingCount(1)
  let secondLease = try await runtime.acquireCaptureLease()

  #expect(await asr.loadCallCount == 1)
  #expect(await cleanup.loadCallCount == 2)
  #expect(await runtime.snapshot() == LocalDictationRuntimeSnapshot(
    residency: .active,
    asrHealth: .available,
    cleanupHealth: .unavailable,
    hasActiveLease: true
  ))

  await runtime.releaseCaptureLease(secondLease)
  await runtime.handle(.memoryCritical)
  await sleeper.resumeAll()
}

@Test func successfulLoadResetsConsecutiveFailureCount() async throws {
  let asr = FakeRuntimeAdapter(
    role: .asr,
    loadOutcomes: [
      .failure(.loadFailed),
      .success(()),
      .failure(.loadFailed),
      .success(()),
    ]
  )
  let cleanup = FakeRuntimeAdapter(role: .cleanup)
  let sleeper = ManualRuntimeSleeper()
  let runtime = makeRuntime(asr: asr, cleanup: cleanup, sleeper: sleeper)

  await runtime.prepare(for: .likelyCapture)
  let firstLease = try await runtime.acquireCaptureLease()
  await runtime.releaseCaptureLease(firstLease)
  await runtime.handle(.memoryCritical)

  await #expect(throws: LocalDictationRuntimeError.adapterLoadFailed(.asr)) {
    try await runtime.acquireCaptureLease()
  }
  let secondLease = try await runtime.acquireCaptureLease()

  #expect(await asr.loadCallCount == 4)
  #expect(await runtime.snapshot().asrHealth == .available)
  #expect(await runtime.snapshot().hasActiveLease)

  await runtime.releaseCaptureLease(secondLease)
  await runtime.handle(.memoryCritical)
  await sleeper.resumeAll()
}

@Test func staleReleaseAndCancelIDsDoNothing() async throws {
  let asr = FakeRuntimeAdapter(role: .asr)
  let cleanup = FakeRuntimeAdapter(role: .cleanup)
  let sleeper = ManualRuntimeSleeper()
  let runtime = makeRuntime(asr: asr, cleanup: cleanup, sleeper: sleeper)
  let firstLease = try await runtime.acquireCaptureLease()
  let wrongID = UUID()

  await runtime.releaseCaptureLease(wrongID)
  await runtime.cancelCaptureLease(wrongID)
  #expect(await runtime.snapshot().hasActiveLease)
  #expect(await asr.cancelCallCount == 0)

  await runtime.releaseCaptureLease(firstLease)
  let secondLease = try await runtime.acquireCaptureLease()
  await runtime.releaseCaptureLease(firstLease)
  await runtime.cancelCaptureLease(firstLease)

  #expect(await runtime.snapshot().hasActiveLease)
  #expect(await asr.cancelCallCount == 0)

  await runtime.releaseCaptureLease(secondLease)
  await runtime.handle(.memoryCritical)
  await sleeper.resumeAll()
}

@Test func snapshotPrivacySurfaceContainsOnlyResidencyHealthAndLeaseState() {
  let snapshot = LocalDictationRuntimeSnapshot(
    residency: .cold,
    asrHealth: .available,
    cleanupHealth: .unavailable,
    hasActiveLease: false
  )
  let labels = Mirror(reflecting: snapshot).children.compactMap(\.label)

  #expect(labels == ["residency", "asrHealth", "cleanupHealth", "hasActiveLease"])
}

private func makeRuntime(
  asr: FakeRuntimeAdapter,
  cleanup: FakeRuntimeAdapter,
  sleeper: ManualRuntimeSleeper
) -> LocalDictationRuntime {
  LocalDictationRuntime(
    asrAdapter: asr,
    cleanupAdapter: cleanup,
    policy: DictationRuntimePolicy(
      warmDuration: .seconds(10),
      standbyDuration: .seconds(20)
    ),
    scheduler: DictationInferenceScheduler(),
    sleeper: { duration in await sleeper.sleep(for: duration) }
  )
}

private func captureLeaseResult(
  from runtime: LocalDictationRuntime
) async -> Result<UUID, LocalDictationRuntimeError> {
  do {
    return .success(try await runtime.acquireCaptureLease())
  } catch let error as LocalDictationRuntimeError {
    return .failure(error)
  } catch {
    fatalError("unexpected capture lease error: \(error)")
  }
}

private enum FakeRuntimeAdapterError: Error, Sendable {
  case loadFailed
}

private actor FakeRuntimeAdapter: LocalDictationRuntimeAdapter {
  nonisolated let role: LocalDictationRuntimeRole

  private var loadOutcomes: [Result<Void, FakeRuntimeAdapterError>]
  private let loadGate: AsyncRuntimeGate?
  private var loadGates: [AsyncRuntimeGate?]
  private let cancelGate: AsyncRuntimeGate?
  private let unloadGate: AsyncRuntimeGate?

  private(set) var loadCallCount = 0
  private(set) var cancelCallCount = 0
  private(set) var unloadCallCount = 0
  private(set) var isLoaded = false
  private var unloadWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

  init(
    role: LocalDictationRuntimeRole,
    loadOutcomes: [Result<Void, FakeRuntimeAdapterError>] = [],
    loadGate: AsyncRuntimeGate? = nil,
    loadGates: [AsyncRuntimeGate?] = [],
    cancelGate: AsyncRuntimeGate? = nil,
    unloadGate: AsyncRuntimeGate? = nil
  ) {
    self.role = role
    self.loadOutcomes = loadOutcomes
    self.loadGate = loadGate
    self.loadGates = loadGates
    self.cancelGate = cancelGate
    self.unloadGate = unloadGate
  }

  func load() async throws {
    loadCallCount += 1
    let gate: AsyncRuntimeGate?
    if loadGates.isEmpty {
      gate = loadGate
    } else {
      gate = loadGates.removeFirst()
    }
    if let gate { await gate.wait() }

    let outcome = loadOutcomes.isEmpty
      ? .success(())
      : loadOutcomes.removeFirst()
    switch outcome {
    case .success:
      isLoaded = true
    case .failure(let error):
      throw error
    }
  }

  func cancel() async {
    cancelCallCount += 1
    if let cancelGate { await cancelGate.wait() }
  }

  func unload() async {
    unloadCallCount += 1
    let ready = unloadWaiters.filter { $0.0 <= unloadCallCount }
    unloadWaiters.removeAll { $0.0 <= unloadCallCount }
    ready.forEach { $0.1.resume() }
    if let unloadGate { await unloadGate.wait() }
    isLoaded = false
  }

  func waitUntilUnloadCallCount(_ count: Int) async {
    guard unloadCallCount < count else { return }
    await withCheckedContinuation { continuation in
      unloadWaiters.append((count, continuation))
    }
  }
}

private actor AsyncRuntimeGate {
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private var waitingObservers: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    guard !isOpen else { return }
    let observers = waitingObservers
    waitingObservers = []
    observers.forEach { $0.resume() }
    await withCheckedContinuation { waiters.append($0) }
  }

  func waitUntilWaiting() async {
    guard !isOpen, waiters.isEmpty else { return }
    await withCheckedContinuation { waitingObservers.append($0) }
  }

  func openGate() {
    isOpen = true
    let observers = waitingObservers
    waitingObservers = []
    observers.forEach { $0.resume() }
    let pending = waiters
    waiters = []
    pending.forEach { $0.resume() }
  }
}

private actor ManualRuntimeSleeper {
  private var waiters: [(Duration, CheckedContinuation<Void, Never>)] = []
  private var pendingObservers: [(Int, CheckedContinuation<Void, Never>)] = []

  func sleep(for duration: Duration) async {
    await withCheckedContinuation { continuation in
      waiters.append((duration, continuation))
      let ready = pendingObservers.filter { $0.0 <= waiters.count }
      pendingObservers.removeAll { $0.0 <= waiters.count }
      ready.forEach { $0.1.resume() }
    }
  }

  func waitUntilPendingCount(_ count: Int) async {
    guard waiters.count < count else { return }
    await withCheckedContinuation { continuation in
      pendingObservers.append((count, continuation))
    }
  }

  var pendingCount: Int {
    waiters.count
  }

  func resumeNext() {
    guard !waiters.isEmpty else { return }
    waiters.removeFirst().1.resume()
  }

  func resumeAll() {
    let pending = waiters
    waiters = []
    pending.forEach { $0.1.resume() }
  }
}

private actor RuntimeCompletionProbe {
  private(set) var count = 0

  func mark() {
    count += 1
  }
}

private enum RuntimeProgress: Equatable, Sendable {
  case cleanupCancellationStarted
  case finished
}

private actor RuntimeProgressRace {
  private var result: RuntimeProgress?
  private var waiter: CheckedContinuation<RuntimeProgress, Never>?

  func signal(_ result: RuntimeProgress) {
    guard self.result == nil else { return }
    self.result = result
    waiter?.resume(returning: result)
    waiter = nil
  }

  func wait() async -> RuntimeProgress {
    if let result { return result }
    return await withCheckedContinuation { waiter = $0 }
  }
}
