import Foundation

protocol LocalDictationRuntimeAdapter: AnyObject, Sendable {
  var role: LocalDictationRuntimeRole { get }
  func load() async throws
  func cancel() async
  func unload() async
}

enum LocalDictationRuntimeRole: Equatable, Sendable {
  case asr
  case cleanup
}

enum LocalDictationRuntimeAdapterHealth: Equatable, Sendable {
  case available
  case unavailable
}

struct LocalDictationRuntimeSnapshot: Equatable, Sendable {
  let residency: DictationRuntimeResidency
  let asrHealth: LocalDictationRuntimeAdapterHealth
  let cleanupHealth: LocalDictationRuntimeAdapterHealth
  let hasActiveLease: Bool
}

enum LocalDictationRuntimeError: Error, Equatable, Sendable {
  case captureLeaseAlreadyActive
  case modelMutationInProgress
  case adapterUnavailable(LocalDictationRuntimeRole)
  case adapterLoadFailed(LocalDictationRuntimeRole)
}

actor LocalDictationRuntime {
  private let asrAdapter: any LocalDictationRuntimeAdapter
  private let cleanupAdapter: any LocalDictationRuntimeAdapter
  private let policy: DictationRuntimePolicy
  private let scheduler: DictationInferenceScheduler
  private let sleeper: @Sendable (Duration) async -> Void

  private var asrLoaded = false
  private var cleanupLoaded = false
  private var asrHealth: LocalDictationRuntimeAdapterHealth = .available
  private var cleanupHealth: LocalDictationRuntimeAdapterHealth = .available
  private var asrLoadFailures = 0
  private var cleanupLoadFailures = 0

  private var activeLease: UUID?
  private var leaseAcquisitionInProgress = false
  private var cancellationInProgress: UUID?
  private var preparationInProgress = false
  private var preparationIntent: DictationPreparationIntent?
  private var preparationWaiters: [CheckedContinuation<Void, Never>] = []
  private var modelMutationPending = false
  private var mutationWaiters: [CheckedContinuation<Void, Never>] = []

  private var idleTransitionInProgress = false
  private var idleTransitionWaiters: [CheckedContinuation<Void, Never>] = []
  private var transitionTask: Task<Void, Never>?
  private var transitionGeneration: UInt64 = 0

  init(
    asrAdapter: any LocalDictationRuntimeAdapter,
    cleanupAdapter: any LocalDictationRuntimeAdapter,
    policy: DictationRuntimePolicy,
    scheduler: DictationInferenceScheduler = DictationInferenceScheduler(),
    sleeper: @escaping @Sendable (Duration) async -> Void
  ) {
    self.asrAdapter = asrAdapter
    self.cleanupAdapter = cleanupAdapter
    self.policy = policy
    self.scheduler = scheduler
    self.sleeper = sleeper
  }

  func prepare(for intent: DictationPreparationIntent) async {
    guard activeLease == nil,
          !modelMutationPending,
          !leaseAcquisitionInProgress,
          !cancellationInProgressIsActive
    else { return }

    if preparationInProgress {
      let inFlightIntent = preparationIntent
      await waitForPreparation()
      if intent == .immediateCapture, inFlightIntent == .likelyCapture {
        await prepare(for: intent)
      }
      return
    }
    if idleTransitionInProgress {
      await waitForIdleTransition()
      await prepare(for: intent)
      return
    }

    let previousResidency = currentResidency
    preparationInProgress = true
    preparationIntent = intent
    do {
      try await loadASR()
    } catch {
      // Preparation is advisory. Acquisition remains authoritative.
    }

    if intent == .immediateCapture, asrLoaded {
      await loadCleanupIfPossible()
    }

    await finishPreparation(from: previousResidency)
  }

  func acquireCaptureLease() async throws -> UUID {
    while true {
      if modelMutationPending {
        throw LocalDictationRuntimeError.modelMutationInProgress
      }
      if preparationInProgress {
        await waitForPreparation()
        continue
      }
      if idleTransitionInProgress {
        await waitForIdleTransition()
        continue
      }
      break
    }
    if activeLease != nil || leaseAcquisitionInProgress {
      throw LocalDictationRuntimeError.captureLeaseAlreadyActive
    }

    leaseAcquisitionInProgress = true
    defer { leaseAcquisitionInProgress = false }
    cancelTransition()

    do {
      try await loadASR()
    } catch {
      if modelMutationPending {
        await forceCold()
      }
      throw error
    }
    await loadCleanupIfPossible()

    if modelMutationPending {
      await forceCold()
      throw LocalDictationRuntimeError.modelMutationInProgress
    }

    let lease = UUID()
    activeLease = lease
    cancelTransition()
    return lease
  }

  func releaseCaptureLease(_ id: UUID) async {
    guard activeLease == id, cancellationInProgress == nil else { return }

    activeLease = nil
    if modelMutationPending {
      await forceCold()
    } else {
      recordResidencyEntry(from: .active)
    }
  }

  func cancelCaptureLease(_ id: UUID) async {
    guard activeLease == id, cancellationInProgress == nil else { return }

    cancellationInProgress = id
    let shouldCancelCleanup = cleanupLoaded
    await asrAdapter.cancel()
    if shouldCancelCleanup {
      await cleanupAdapter.cancel()
    }
    cancellationInProgress = nil
    guard activeLease == id else { return }

    activeLease = nil
    if modelMutationPending {
      await forceCold()
    } else {
      recordResidencyEntry(from: .active)
    }
  }

  func handle(_ signal: DictationRuntimeSignal) async {
    while true {
      guard activeLease == nil,
            !leaseAcquisitionInProgress,
            cancellationInProgress == nil,
            !modelMutationPending
      else { return }

      if preparationInProgress {
        await waitForPreparation()
        continue
      }
      if idleTransitionInProgress {
        await waitForIdleTransition()
        continue
      }
      guard activeLease == nil,
            !leaseAcquisitionInProgress,
            cancellationInProgress == nil,
            !modelMutationPending,
            !preparationInProgress,
            !idleTransitionInProgress
      else { continue }
      break
    }

    let target = policy.targetState(after: signal, activeLease: false)
    let previousResidency = currentResidency
    switch target {
    case .standby:
      await moveToStandby(from: previousResidency)
    case .cold:
      await forceCold()
    case .active, .warm:
      break
    }
  }

  func waitUntilColdForModelMutation() async {
    if modelMutationPending {
      await withCheckedContinuation { mutationWaiters.append($0) }
      return
    }

    modelMutationPending = true
    if activeLease != nil || cancellationInProgress != nil || leaseAcquisitionInProgress
      || preparationInProgress || idleTransitionInProgress {
      await withCheckedContinuation { mutationWaiters.append($0) }
      return
    }

    await forceCold()
  }

  func snapshot() async -> LocalDictationRuntimeSnapshot {
    LocalDictationRuntimeSnapshot(
      residency: currentResidency,
      asrHealth: asrHealth,
      cleanupHealth: cleanupHealth,
      hasActiveLease: activeLease != nil
    )
  }

  private var cancellationInProgressIsActive: Bool {
    cancellationInProgress != nil
  }

  private func waitForPreparation() async {
    guard preparationInProgress else { return }
    await withCheckedContinuation { preparationWaiters.append($0) }
  }

  private func waitForIdleTransition() async {
    guard idleTransitionInProgress else { return }
    await withCheckedContinuation { idleTransitionWaiters.append($0) }
  }

  private func finishPreparation(from previousResidency: DictationRuntimeResidency) async {
    let mutationWasPending = modelMutationPending
    if mutationWasPending {
      await forceCold()
    }

    preparationInProgress = false
    preparationIntent = nil
    if !mutationWasPending, activeLease == nil {
      recordResidencyEntry(from: previousResidency)
    }

    let waiters = preparationWaiters
    preparationWaiters = []
    waiters.forEach { $0.resume() }
  }

  private var currentResidency: DictationRuntimeResidency {
    if activeLease != nil { return .active }
    if asrLoaded, cleanupLoaded { return .warm }
    if asrLoaded { return .standby }
    return .cold
  }

  private func loadASR() async throws {
    guard !asrLoaded else { return }
    guard asrHealth == .available else {
      throw LocalDictationRuntimeError.adapterUnavailable(.asr)
    }

    do {
      try await asrAdapter.load()
    } catch {
      recordLoadFailure(for: .asr)
      throw LocalDictationRuntimeError.adapterLoadFailed(.asr)
    }
    asrLoaded = true
    asrLoadFailures = 0
    asrHealth = .available
  }

  private func loadCleanupIfPossible() async {
    guard asrLoaded, !cleanupLoaded, cleanupHealth == .available else { return }

    do {
      try await cleanupAdapter.load()
    } catch {
      recordLoadFailure(for: .cleanup)
      return
    }
    cleanupLoaded = true
    cleanupLoadFailures = 0
    cleanupHealth = .available
  }

  private func recordLoadFailure(for role: LocalDictationRuntimeRole) {
    switch role {
    case .asr:
      asrLoadFailures += 1
      if asrLoadFailures >= 2 { asrHealth = .unavailable }
    case .cleanup:
      cleanupLoadFailures += 1
      if cleanupLoadFailures >= 2 { cleanupHealth = .unavailable }
    }
  }

  private func recordResidencyEntry(from previousResidency: DictationRuntimeResidency) {
    guard activeLease == nil else {
      cancelTransition()
      return
    }

    let residency = currentResidency
    guard residency != previousResidency else { return }
    switch residency {
    case .warm:
      scheduleTransition(for: .warm)
    case .standby:
      scheduleTransition(for: .standby)
    case .cold, .active:
      cancelTransition()
    }
  }

  private func moveToStandby(from previousResidency: DictationRuntimeResidency) async {
    guard activeLease == nil, !idleTransitionInProgress else { return }

    idleTransitionInProgress = true
    await unloadCleanupIfLoaded()

    let mutationWasPending = modelMutationPending
    if mutationWasPending {
      await forceCold()
    }
    finishIdleTransition()

    guard !mutationWasPending, activeLease == nil else { return }
    recordResidencyEntry(from: previousResidency)
  }

  private func forceCold() async {
    cancelTransition()
    guard activeLease == nil else { return }

    let ownsIdleTransition = !idleTransitionInProgress
    if ownsIdleTransition {
      idleTransitionInProgress = true
    }
    await unloadCleanupIfLoaded()
    await unloadASRIfLoaded()
    if ownsIdleTransition {
      finishIdleTransition()
    }
  }

  private func finishIdleTransition() {
    idleTransitionInProgress = false
    if modelMutationPending {
      completeModelMutation()
    }
    let waiters = idleTransitionWaiters
    idleTransitionWaiters = []
    waiters.forEach { $0.resume() }
  }

  private func unloadCleanupIfLoaded() async {
    guard cleanupLoaded else { return }
    await cleanupAdapter.unload()
    cleanupLoaded = false
  }

  private func unloadASRIfLoaded() async {
    guard asrLoaded else { return }
    await asrAdapter.unload()
    asrLoaded = false
  }

  private func scheduleTransition(for residency: DictationRuntimeResidency) {
    transitionTask?.cancel()
    transitionGeneration += 1
    let generation = transitionGeneration
    let duration = residency == .warm ? policy.warmDuration : policy.standbyDuration
    let sleeper = self.sleeper
    transitionTask = Task { [weak self] in
      await sleeper(duration)
      await self?.expireTransition(for: residency, generation: generation)
    }
  }

  private func cancelTransition() {
    transitionGeneration += 1
    transitionTask?.cancel()
    transitionTask = nil
  }

  private func expireTransition(
    for residency: DictationRuntimeResidency,
    generation: UInt64
  ) async {
    guard generation == transitionGeneration,
          activeLease == nil,
          !modelMutationPending,
          currentResidency == residency
    else { return }

    if preparationInProgress {
      await waitForPreparation()
      await expireTransition(for: residency, generation: generation)
      return
    }
    if idleTransitionInProgress {
      await waitForIdleTransition()
      await expireTransition(for: residency, generation: generation)
      return
    }

    transitionTask = nil
    idleTransitionInProgress = true
    switch residency {
    case .warm:
      await unloadCleanupIfLoaded()
    case .standby:
      await unloadASRIfLoaded()
    case .cold, .active:
      finishIdleTransition()
      return
    }

    let mutationWasPending = modelMutationPending
    if mutationWasPending {
      await forceCold()
    }
    finishIdleTransition()

    guard generation == transitionGeneration,
          activeLease == nil,
          !mutationWasPending
    else { return }
    recordResidencyEntry(from: residency)
  }

  private func completeModelMutation() {
    guard modelMutationPending else { return }
    modelMutationPending = false
    let waiters = mutationWaiters
    mutationWaiters = []
    waiters.forEach { $0.resume() }
  }
}
