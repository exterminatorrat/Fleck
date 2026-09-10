#if os(macOS) && CLEAN_DICTATION_ENHANCED_CANDIDATE
import Foundation

@MainActor
final class AdaptiveEnhancedSpeechInference: EnhancedSpeechInferring {
  private enum Phase {
    case idle
    case loading
    case active
    case transcribing
    case releasing
  }

  private let inference: any EnhancedSpeechInferring
  private let profile: DictationResourceProfile
  private let policy: DictationRuntimePolicy
  private let snapshot: @MainActor () -> DictationResourceSnapshot
  private let sleeper: @MainActor (Duration) async throws -> Void

  private var phase: Phase = .idle
  private var isLoaded = false
  private var loadedRepositoryURL: URL?
  private var pendingForceCold = false
  private var retentionTask: Task<Void, Never>?
  private var generation: UInt64 = 0
  private var coldRequestGeneration: UInt64 = 0
  private var coldWaiters: [CheckedContinuation<Void, Never>] = []

  init(
    inference: any EnhancedSpeechInferring,
    profile: DictationResourceProfile,
    policy: DictationRuntimePolicy,
    snapshot: @escaping @MainActor () -> DictationResourceSnapshot,
    sleeper: @escaping @MainActor (Duration) async throws -> Void = { duration in
      try await Task.sleep(for: duration)
    }
  ) {
    self.inference = inference
    self.profile = profile
    self.policy = policy
    self.snapshot = snapshot
    self.sleeper = sleeper
  }

  func loadDisposition(for repositoryURL: URL) -> DictationRuntimeMeasurements.LoadDisposition? {
    guard phase == .idle else { return nil }
    if isLoaded, loadedRepositoryURL == repositoryURL { return .warm }
    return .cold
  }

  func load(from repositoryURL: URL) async throws {
    guard phase == .idle else {
      throw DictationFailure.unavailable
    }

    if isLoaded {
      guard loadedRepositoryURL != repositoryURL else {
        invalidateRetention()
        phase = .active
        return
      }
      let substitutionRequestGeneration = coldRequestGeneration
      await beginColdRelease(cancelUnderlying: false)
      guard coldRequestGeneration == substitutionRequestGeneration else {
        throw CancellationError()
      }
    }

    phase = .loading
    generation &+= 1
    let loadGeneration = generation
    do {
      try await inference.load(from: repositoryURL)
      guard phase == .loading, generation == loadGeneration else {
        throw CancellationError()
      }
      isLoaded = true
      loadedRepositoryURL = repositoryURL
      phase = .active
    } catch {
      if phase == .loading, generation == loadGeneration {
        await beginColdRelease(cancelUnderlying: false)
      }
      throw error
    }
  }

  func transcribe(_ samples: [Float]) async throws -> String {
    guard phase == .active, isLoaded else {
      throw DictationFailure.unavailable
    }

    phase = .transcribing
    let transcriptionGeneration = generation
    do {
      let text = try await inference.transcribe(samples)
      guard
        phase == .transcribing,
        isLoaded,
        generation == transcriptionGeneration
      else {
        throw CancellationError()
      }
      phase = .active
      return text
    } catch {
      if phase == .transcribing, generation == transcriptionGeneration {
        await beginColdRelease(cancelUnderlying: false)
      }
      throw error
    }
  }

  func cancel() async {
    guard phase != .idle || isLoaded else { return }
    coldRequestGeneration &+= 1
    switch phase {
    case .loading, .active, .transcribing:
      await beginColdRelease(cancelUnderlying: true)
    case .idle where isLoaded:
      await beginColdRelease(cancelUnderlying: true)
    case .releasing:
      await waitForCold()
    case .idle:
      break
    }
  }

  func releaseResources() async {
    switch phase {
    case .active:
      phase = .idle
      let retention = policy.parakeetRetention(
        profile: profile,
        snapshot: snapshot()
      )
      if pendingForceCold || retention == .zero {
        await beginColdRelease(cancelUnderlying: false)
      } else {
        generation &+= 1
        scheduleRetention(retention, generation: generation)
      }
    case .releasing:
      await waitForCold()
    case .idle, .loading, .transcribing:
      return
    }
  }

  func forceCold() async {
    switch phase {
    case .idle where isLoaded:
      coldRequestGeneration &+= 1
      invalidateRetention()
      await beginColdRelease(cancelUnderlying: false)
    case .loading, .active, .transcribing:
      coldRequestGeneration &+= 1
      pendingForceCold = true
      await waitForCold()
    case .releasing:
      coldRequestGeneration &+= 1
      await waitForCold()
    case .idle:
      return
    }
  }

  private func scheduleRetention(_ duration: Duration, generation: UInt64) {
    let sleeper = sleeper
    retentionTask = Task { @MainActor [weak self] in
      do {
        try await sleeper(duration)
      } catch {
        return
      }
      guard !Task.isCancelled, let self else { return }
      guard
        self.phase == .idle,
        self.isLoaded,
        self.generation == generation
      else {
        return
      }
      await self.beginColdRelease(cancelUnderlying: false)
    }
  }

  private func invalidateRetention() {
    generation &+= 1
    retentionTask?.cancel()
    retentionTask = nil
  }

  private func beginColdRelease(cancelUnderlying: Bool) async {
    guard phase != .releasing else {
      await waitForCold()
      return
    }
    guard isLoaded || phase == .loading else {
      pendingForceCold = false
      resumeColdWaiters()
      return
    }

    invalidateRetention()
    phase = .releasing
    isLoaded = false
    loadedRepositoryURL = nil
    if cancelUnderlying {
      await inference.cancel()
    }
    await inference.releaseResources()
    phase = .idle
    pendingForceCold = false
    resumeColdWaiters()
  }

  private func waitForCold() async {
    guard phase != .idle || isLoaded else { return }
    await withCheckedContinuation { continuation in
      coldWaiters.append(continuation)
    }
  }

  private func resumeColdWaiters() {
    let waiters = coldWaiters
    coldWaiters.removeAll()
    for waiter in waiters {
      waiter.resume()
    }
  }
}
#endif
