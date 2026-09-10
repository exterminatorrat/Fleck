#if os(macOS) && CLEAN_DICTATION_ENHANCED_CANDIDATE
  @preconcurrency import AVFAudio
  import FleckEnhancedCandidateDependencies
  import Foundation
  import FleckCore

  struct EnhancedAudioConfiguration: Equatable {
    let sampleRate: Double
    let channelCount: Int
    let isFloat32: Bool

    static let inference = Self(
      sampleRate: 16_000,
      channelCount: 1,
      isFloat32: true
    )
  }

  @MainActor
  protocol EnhancedSpeechInferring: AnyObject {
    func loadDisposition(for repositoryURL: URL) -> DictationRuntimeMeasurements.LoadDisposition?
    func load(from repositoryURL: URL) async throws
    func transcribe(_ samples: [Float]) async throws -> String
    func cancel() async
    func releaseResources() async
  }

  @MainActor
  protocol EnhancedAudioCapturing: AnyObject {
    var firstInputBufferAt: ContinuousClock.Instant? { get }
    func selectMicrophone(savedUID: String?) -> MicrophoneSelection
    func start(level: @escaping @MainActor (Float) -> Void) throws
    func start(
      level: @escaping @MainActor (Float) -> Void,
      failure: @escaping @MainActor (Error) -> Void
    ) throws
    func stopAndTakeSamples() throws -> [Float]
    func cancel()
    func releaseResources()
  }

  extension EnhancedAudioCapturing {
    var firstInputBufferAt: ContinuousClock.Instant? { nil }

    func selectMicrophone(savedUID _: String?) -> MicrophoneSelection {
      .automatic
    }

    func start(
      level: @escaping @MainActor (Float) -> Void,
      failure _: @escaping @MainActor (Error) -> Void
    ) throws {
      try start(level: level)
    }
  }

  enum EnhancedSpeechCaptureError: Error, Equatable, LocalizedError {
    case missingInput
    case startupTimedOut
    case sampleLimitExceeded

    var errorDescription: String? {
      switch self {
      case .missingInput:
        "No usable microphone input is available."
      case .startupTimedOut:
        "Enhanced speech recognition did not become ready in time."
      case .sampleLimitExceeded:
        "Enhanced dictation exceeded the five-minute recording limit."
      }
    }
  }

  extension EnhancedSpeechInferring {
    func loadDisposition(for repositoryURL: URL) -> DictationRuntimeMeasurements.LoadDisposition? {
      _ = repositoryURL
      return nil
    }
  }

  @MainActor
  final class EnhancedSpeechCapture: SpeechEngine {
    let kind: DictationSpeechEngine = .enhancedLocal

    static var isFluidAudioOffline: Bool {
      ModelHub.offlineMode
    }

    private final class Resources {
      let inference: any EnhancedSpeechInferring
      let repositoryURL: URL
      var failureCallback: (@MainActor (Error) -> Void)?
      var permissionTask: Task<DictationPermissionResult, Never>?
      var audio: (any EnhancedAudioCapturing)?
      var loadTask: Task<Void, Never>?
      var watchdogTask: Task<Void, Never>?
      var transcriptionTask: Task<String, Error>?
      var releaseTask: Task<Void, Never>?
      var failure: Error?
      var startupDeadline: ContinuousClock.Instant?
      var frozenSamples: [Float]?
      var modelReady = false
      var audioStopped = false
      var cancelRequested = false
      var inferenceCancellationRequested = false
      var measurements = DictationRuntimeMeasurements.empty

      init(
        inference: any EnhancedSpeechInferring,
        repositoryURL: URL,
        failure: @escaping @MainActor (Error) -> Void
      ) {
        self.inference = inference
        self.repositoryURL = repositoryURL
        failureCallback = failure
      }
    }

    private let verifiedLoadState: @MainActor () -> EnhancedModelVerifiedLoadState
    private let requestPermission: @MainActor (
      DictationSpeechEngine
    ) async -> DictationPermissionResult
    private let microphoneUID: String?
    private let microphoneSelectionChanged: @MainActor (MicrophoneSelection) -> Void
    private let makeInference: @MainActor () -> any EnhancedSpeechInferring
    private let makeAudio: @MainActor (
      EnhancedAudioConfiguration
    ) throws -> any EnhancedAudioCapturing
    private let markRepairRequired: @MainActor (String, URL) -> Void
    private let recommendStandard: @MainActor () -> Void
    private let startupTimeout: Duration
    private let startupNow: @Sendable () -> ContinuousClock.Instant
    private let startupSleeper: @Sendable (Duration) async -> Void

    private var resources: Resources?
    private var latestMeasurements = DictationRuntimeMeasurements.empty

    var hasActiveResources: Bool {
      resources != nil
    }

    var runtimeMeasurements: DictationRuntimeMeasurements {
      guard let resources else { return latestMeasurements }
      return snapshot(resources)
    }

    init(
      verifiedLoadState: @escaping @MainActor () -> EnhancedModelVerifiedLoadState,
      requestPermission: @escaping @MainActor (
        DictationSpeechEngine
      ) async -> DictationPermissionResult = { _ in .granted },
      microphoneUID: String? = nil,
      microphoneSelectionChanged: @escaping @MainActor (MicrophoneSelection) -> Void = { _ in },
      makeInference: @escaping @MainActor () -> any EnhancedSpeechInferring = {
        FluidEnhancedSpeechInference()
      },
      makeAudio: @escaping @MainActor (
        EnhancedAudioConfiguration
      ) throws -> any EnhancedAudioCapturing = {
        try EnhancedSystemAudioCapture(configuration: $0)
      },
      markRepairRequired: @escaping @MainActor (String, URL) -> Void = { _, _ in },
      recommendStandard: @escaping @MainActor () -> Void = {},
      startupTimeout: Duration = .seconds(15),
      startupNow: @escaping @Sendable () -> ContinuousClock.Instant = {
        ContinuousClock().now
      },
      startupSleeper: @escaping @Sendable (Duration) async -> Void = { duration in
        try? await Task.sleep(for: duration)
      }
    ) {
      ModelHub.offlineMode = true
      self.verifiedLoadState = verifiedLoadState
      self.requestPermission = requestPermission
      self.microphoneUID = microphoneUID
      self.microphoneSelectionChanged = microphoneSelectionChanged
      self.makeInference = makeInference
      self.makeAudio = makeAudio
      self.markRepairRequired = markRepairRequired
      self.recommendStandard = recommendStandard
      self.startupTimeout = startupTimeout
      self.startupNow = startupNow
      self.startupSleeper = startupSleeper
    }

    convenience init(
      modelManager: EnhancedModelManager,
      permissions: DictationPermissionController = .init(),
      microphoneUID: String? = nil,
      microphoneSelectionChanged: @escaping @MainActor (MicrophoneSelection) -> Void = { _ in },
      makeInference: @escaping @MainActor () -> any EnhancedSpeechInferring = {
        FluidEnhancedSpeechInference()
      },
      makeAudio: @escaping @MainActor (
        EnhancedAudioConfiguration
      ) throws -> any EnhancedAudioCapturing = {
        try EnhancedSystemAudioCapture(configuration: $0)
      },
      recommendStandard: @escaping @MainActor () -> Void = {}
    ) {
      self.init(
        verifiedLoadState: { [weak modelManager] in
          modelManager?.verifiedLoadState ?? .unavailable
        },
        requestPermission: { engine in
          await permissions.requestAccess(for: engine, after: .toolbarMicrophone)
        },
        microphoneUID: microphoneUID,
        microphoneSelectionChanged: microphoneSelectionChanged,
        makeInference: makeInference,
        makeAudio: makeAudio,
        markRepairRequired: { [weak modelManager] message, repositoryURL in
          modelManager?.markInferenceLoadFailure(
            message: message,
            failedRepositoryURL: repositoryURL
          )
        },
        recommendStandard: recommendStandard
      )
    }

    func start(
      provisional: @escaping @MainActor (String) -> Void,
      level: @escaping @MainActor (Float) -> Void
    ) async throws {
      try await start(provisional: provisional, level: level, failure: { _ in })
    }

    func start(
      provisional _: @escaping @MainActor (String) -> Void,
      level: @escaping @MainActor (Float) -> Void,
      failure: @escaping @MainActor (Error) -> Void
    ) async throws {
      guard !hasActiveResources else {
        throw DictationFailure.unavailable
      }
      latestMeasurements = .empty
      ModelHub.offlineMode = true
      guard case .ready(let repositoryURL) = verifiedLoadState() else {
        latestMeasurements = latestMeasurements
          .recording(outcome: .failed)
          .recording(failure: .modelUnavailable)
        recommendStandard()
        throw DictationFailure.unavailable
      }

      let candidate = Resources(
        inference: makeInference(),
        repositoryURL: repositoryURL,
        failure: failure
      )
      resources = candidate
      let permissionTask = Task { @MainActor [requestPermission] in
        await requestPermission(.enhancedLocal)
      }
      candidate.permissionTask = permissionTask
      let permission = await permissionTask.value
      guard resources === candidate, !candidate.cancelRequested, !Task.isCancelled else {
        await release(candidate, cancelling: true)
        throw CancellationError()
      }
      guard case .granted = permission else {
        candidate.measurements = candidate.measurements
          .recording(outcome: .failed)
          .recording(failure: .permissionDenied)
        await release(candidate, cancelling: false)
        throw DictationFailure.permissionDenied
      }
      guard
        case .ready(let currentRepositoryURL) = verifiedLoadState(),
        currentRepositoryURL == repositoryURL
      else {
        candidate.measurements = candidate.measurements
          .recording(outcome: .failed)
          .recording(failure: .modelUnavailable)
        await release(candidate, cancelling: false)
        recommendStandard()
        throw DictationFailure.unavailable
      }

      do {
        let audio = try makeAudio(.inference)
        candidate.audio = audio
        microphoneSelectionChanged(audio.selectMicrophone(savedUID: microphoneUID))
        candidate.measurements = candidate.measurements.recording(
          .audioStartRequested,
          at: startupNow()
        )
        try audio.start(
          level: { [weak self, weak candidate] value in
            guard let self, let candidate,
              self.resources === candidate,
              !candidate.audioStopped,
              !candidate.cancelRequested,
              candidate.failure == nil
            else { return }
            level(value)
          },
          failure: { [weak self, weak candidate] error in
            guard let candidate else { return }
            self?.recordFailure(candidate, error: error, marksModelRepair: false)
          }
        )
      } catch {
        recordKnownFailure(candidate, error: error, defaultFailure: .sourceStartupFailure)
        let wasCancelled = error is CancellationError || Task.isCancelled
        stopAudio(candidate)
        await release(candidate, cancelling: true)
        if !wasCancelled {
          recommendStandard()
        }
        throw error
      }

      guard resources === candidate, !candidate.cancelRequested, !Task.isCancelled else {
        stopAudio(candidate)
        await release(candidate, cancelling: true)
        throw CancellationError()
      }
      let startupDeadline = startupNow().advanced(by: startupTimeout)
      candidate.startupDeadline = startupDeadline
      candidate.loadTask = Task { @MainActor [weak self, candidate] in
        guard let self,
          self.resources === candidate,
          !candidate.cancelRequested,
          candidate.failure == nil,
          !Task.isCancelled
        else { return }
        do {
          ModelHub.offlineMode = true
          if let disposition = candidate.inference.loadDisposition(for: repositoryURL) {
            candidate.measurements = candidate.measurements.recording(loadDisposition: disposition)
          }
          candidate.measurements = candidate.measurements.recording(
            .modelLoadRequested,
            at: self.startupNow()
          )
          try await candidate.inference.load(from: repositoryURL)
          self.completeLoad(candidate)
        } catch {
          guard !candidate.cancelRequested, candidate.failure == nil else { return }
          candidate.measurements = candidate.measurements
            .recording(outcome: .failed)
            .recording(failure: .modelLoadFailure)
          self.recordFailure(
            candidate,
            error: error,
            marksModelRepair: !(error is CancellationError)
          )
        }
      }
      candidate.watchdogTask = Task { @MainActor [weak self, candidate, startupNow, startupSleeper] in
        let remaining = startupNow().duration(to: startupDeadline)
        if remaining > .zero {
          await startupSleeper(remaining)
        }
        guard !Task.isCancelled else { return }
        self?.recordFailure(
          candidate,
          error: EnhancedSpeechCaptureError.startupTimedOut,
          marksModelRepair: false
        )
      }
    }

    func finish() async throws -> String? {
      guard let resources else {
        throw DictationFailure.unavailable
      }
      if let failure = resources.failure {
        await release(resources, cancelling: true)
        throw failure
      }
      guard !resources.cancelRequested else { throw CancellationError() }

      do {
        resources.audioStopped = true
        resources.frozenSamples = try resources.audio?.stopAndTakeSamples() ?? []
      } catch {
        let wasCancelled = error is CancellationError || Task.isCancelled
        if wasCancelled {
          resources.cancelRequested = true
          stopAudio(resources)
          await release(resources, cancelling: true)
          throw CancellationError()
        }
        recordKnownFailure(resources, error: error, defaultFailure: .sourceFailure)
        recordFailure(resources, error: error, marksModelRepair: false)
        await release(resources, cancelling: true)
        throw error
      }
      await resources.loadTask?.value
      if let failure = resources.failure {
        await release(resources, cancelling: true)
        throw failure
      }
      guard !resources.cancelRequested else {
        await release(resources, cancelling: true)
        throw CancellationError()
      }
      guard
        resources.modelReady,
        case .ready(let currentRepositoryURL) = verifiedLoadState(),
        currentRepositoryURL == resources.repositoryURL
      else {
        resources.measurements = resources.measurements
          .recording(outcome: .failed)
          .recording(failure: .modelUnavailable)
        recordFailure(resources, error: DictationFailure.unavailable, marksModelRepair: false)
        await release(resources, cancelling: true)
        throw DictationFailure.unavailable
      }
      let samples = resources.frozenSamples ?? []
      resources.frozenSamples = nil
      guard !samples.isEmpty else {
        await release(resources, cancelling: false)
        guard !resources.cancelRequested, resources.failure == nil else {
          throw CancellationError()
        }
        return nil
      }

      let task = Task {
        try await resources.inference.transcribe(samples)
      }
      resources.transcriptionTask = task
      do {
        let text = try await task.value
        guard self.resources === resources,
          !resources.cancelRequested,
          resources.failure == nil
        else {
          throw CancellationError()
        }
        await release(resources, cancelling: false)
        guard !resources.cancelRequested, resources.failure == nil else {
          throw CancellationError()
        }
        return text
          .trimmingCharacters(in: .whitespacesAndNewlines)
          .nilIfEmpty
      } catch {
        let wasCancelled = error is CancellationError || Task.isCancelled
        await release(resources, cancelling: true)
        if !wasCancelled {
          markRepairRequired(error.localizedDescription, resources.repositoryURL)
          recommendStandard()
        }
        throw error
      }
    }

    func cancel() async {
      guard let resources else { return }
      resources.cancelRequested = true
      stopAudio(resources)
      await release(resources, cancelling: true)
    }

    func releaseResources() async {
      await cancel()
    }

    private func completeLoad(_ candidate: Resources) {
      guard resources === candidate, !candidate.cancelRequested, candidate.failure == nil else { return }
      guard let startupDeadline = candidate.startupDeadline,
        startupNow() < startupDeadline
      else {
        recordFailure(
          candidate,
          error: EnhancedSpeechCaptureError.startupTimedOut,
          marksModelRepair: false
        )
        return
      }
      guard
        case .ready(let currentRepositoryURL) = verifiedLoadState(),
        currentRepositoryURL == candidate.repositoryURL
      else {
        candidate.measurements = candidate.measurements
          .recording(outcome: .failed)
          .recording(failure: .modelUnavailable)
        recordFailure(candidate, error: DictationFailure.unavailable, marksModelRepair: false)
        return
      }
      candidate.modelReady = true
      candidate.measurements = candidate.measurements.recording(.modelReady, at: startupNow())
      candidate.watchdogTask?.cancel()
    }

    private func recordFailure(
      _ candidate: Resources,
      error: Error,
      marksModelRepair: Bool
    ) {
      guard resources === candidate, !candidate.cancelRequested, candidate.failure == nil else { return }
      recordKnownFailure(candidate, error: error, defaultFailure: .sourceFailure)
      candidate.failure = error
      stopAudio(candidate)
      if marksModelRepair {
        markRepairRequired(error.localizedDescription, candidate.repositoryURL)
      }
      recommendStandard()
      candidate.failureCallback?(error)
      Task { @MainActor [weak self, candidate] in
        await self?.release(candidate, cancelling: true)
      }
    }

    private func stopAudio(_ candidate: Resources) {
      preserveSnapshot(candidate)
      candidate.frozenSamples = nil
      guard !candidate.audioStopped else { return }
      candidate.audioStopped = true
      candidate.audio?.cancel()
    }

    private func release(_ candidate: Resources, cancelling: Bool) async {
      preserveSnapshot(candidate)
      if let releaseTask = candidate.releaseTask {
        if cancelling {
          await requestInferenceCancellation(candidate)
        }
        await releaseTask.value
        return
      }
      let task = Task { @MainActor [weak self, candidate] in
        candidate.permissionTask?.cancel()
        candidate.loadTask?.cancel()
        candidate.watchdogTask?.cancel()
        candidate.transcriptionTask?.cancel()
        if cancelling {
          await self?.requestInferenceCancellation(candidate)
        }
        _ = await candidate.permissionTask?.result
        _ = await candidate.loadTask?.result
        _ = await candidate.transcriptionTask?.result
        candidate.audio?.releaseResources()
        await candidate.inference.releaseResources()
        candidate.failureCallback = nil
        candidate.permissionTask = nil
        candidate.loadTask = nil
        candidate.watchdogTask = nil
        candidate.transcriptionTask = nil
        candidate.frozenSamples = nil
        candidate.audio = nil
        if self?.resources === candidate {
          self?.resources = nil
        }
      }
      candidate.releaseTask = task
      await task.value
    }

    private func snapshot(_ candidate: Resources) -> DictationRuntimeMeasurements {
      guard let firstInputBufferAt = candidate.audio?.firstInputBufferAt else {
        return candidate.measurements
      }
      return candidate.measurements.recording(.firstInputBuffer, at: firstInputBufferAt)
    }

    private func preserveSnapshot(_ candidate: Resources) {
      candidate.measurements = snapshot(candidate)
      if resources === candidate {
        latestMeasurements = candidate.measurements
      }
    }

    private func recordKnownFailure(
      _ candidate: Resources,
      error: Error,
      defaultFailure: DictationRuntimeMeasurements.Failure
    ) {
      guard !(error is CancellationError) else { return }
      let failure: DictationRuntimeMeasurements.Failure
      if let enhancedError = error as? EnhancedSpeechCaptureError {
        switch enhancedError {
        case .missingInput: failure = .missingInput
        case .startupTimedOut: failure = .startupTimeout
        case .sampleLimitExceeded: failure = .bufferLimit
        }
      } else if let dictationError = error as? DictationFailure {
        switch dictationError {
        case .permissionDenied: failure = .permissionDenied
        default: failure = defaultFailure
        }
      } else {
        failure = defaultFailure
      }
      candidate.measurements = candidate.measurements
        .recording(outcome: .failed)
        .recording(failure: failure)
    }

    private func requestInferenceCancellation(_ candidate: Resources) async {
      guard !candidate.inferenceCancellationRequested else { return }
      candidate.inferenceCancellationRequested = true
      await candidate.inference.cancel()
    }
  }

  @MainActor
  protocol FluidEnhancedSpeechResources: AnyObject, Sendable {
    func prepare() async throws
    func transcribe(_ samples: [Float]) async throws -> String
    func cleanup() async
  }

  private final class FluidInferenceLifecycle: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var cancelled = false

    func begin() -> UInt64 {
      lock.withLock {
        generation &+= 1
        cancelled = false
        return generation
      }
    }

    func cancel() {
      lock.withLock {
        cancelled = true
        generation &+= 1
      }
    }

    func isCurrent(_ candidate: UInt64) -> Bool {
      lock.withLock {
        !cancelled && generation == candidate
      }
    }
  }

  @MainActor
  private final class FluidPinnedSpeechResources:
    FluidEnhancedSpeechResources,
    @unchecked Sendable
  {
    private var models: AsrModels?
    private var manager: AsrManager?
    private var cleaned = false

    init(models: AsrModels) {
      self.models = models
    }

    func prepare() async throws {
      guard let models, !cleaned else {
        throw CancellationError()
      }
      let manager = AsrManager(config: .default)
      do {
        try await manager.loadModels(models)
      } catch {
        await manager.cleanup()
        throw error
      }
      self.manager = manager
    }

    func transcribe(_ samples: [Float]) async throws -> String {
      guard let manager, !cleaned else {
        throw DictationFailure.unavailable
      }
      var decoderState = TdtDecoderState.make(
        decoderLayers: await manager.decoderLayerCount
      )
      return try await manager.transcribe(
        samples,
        decoderState: &decoderState
      ).text
    }

    func cleanup() async {
      guard !cleaned else { return }
      cleaned = true
      await manager?.cleanup()
      manager = nil
      models = nil
    }
  }

  @MainActor
  final class FluidEnhancedSpeechInference: EnhancedSpeechInferring {
    typealias ResourcesLoader = @MainActor @Sendable (
      URL
    ) async throws -> any FluidEnhancedSpeechResources

    private let lifecycle = FluidInferenceLifecycle()
    private let loadResources: ResourcesLoader
    private var resources: (any FluidEnhancedSpeechResources)?
    private var loadTask: Task<any FluidEnhancedSpeechResources, Error>?
    private var loadedGeneration: UInt64?

    var hasLoadedResources: Bool {
      resources != nil
    }

    func loadDisposition(for _: URL) -> DictationRuntimeMeasurements.LoadDisposition? {
      loadTask == nil && resources == nil ? .cold : nil
    }

    init(loadResources: @escaping ResourcesLoader = { repositoryURL in
      ModelHub.offlineMode = true
      let models = try await AsrModels.load(
        from: repositoryURL,
        configuration: AsrModels.defaultConfiguration(),
        version: .v2
      )
      return FluidPinnedSpeechResources(models: models)
    }) {
      self.loadResources = loadResources
    }

    func load(from repositoryURL: URL) async throws {
      guard loadTask == nil, resources == nil else {
        throw DictationFailure.unavailable
      }
      ModelHub.offlineMode = true
      let generation = lifecycle.begin()
      let lifecycle = lifecycle
      let loadResources = loadResources
      let task = Task { @MainActor in
        let candidate = try await loadResources(repositoryURL)
        guard lifecycle.isCurrent(generation) else {
          await candidate.cleanup()
          throw CancellationError()
        }
        do {
          try await candidate.prepare()
        } catch {
          await candidate.cleanup()
          throw error
        }
        guard lifecycle.isCurrent(generation) else {
          await candidate.cleanup()
          throw CancellationError()
        }
        return candidate
      }
      loadTask = task

      do {
        let candidate = try await task.value
        guard lifecycle.isCurrent(generation) else {
          await candidate.cleanup()
          throw CancellationError()
        }
        resources = candidate
        loadedGeneration = generation
        loadTask = nil
      } catch {
        loadTask = nil
        throw error
      }
    }

    func transcribe(_ samples: [Float]) async throws -> String {
      guard
        let resources,
        let loadedGeneration,
        lifecycle.isCurrent(loadedGeneration)
      else {
        throw DictationFailure.unavailable
      }
      let text = try await resources.transcribe(samples)
      guard lifecycle.isCurrent(loadedGeneration) else {
        throw CancellationError()
      }
      return text
    }

    func cancel() async {
      lifecycle.cancel()
      loadTask?.cancel()
    }

    func releaseResources() async {
      lifecycle.cancel()
      let task = loadTask
      task?.cancel()
      _ = await task?.result
      loadTask = nil
      guard let resources else { return }
      self.resources = nil
      loadedGeneration = nil
      await resources.cleanup()
    }
  }

  final class EnhancedAudioStreamConverter: @unchecked Sendable {
    static let maximumSampleCount = 4_800_000

    private final class InputSupply: @unchecked Sendable {
      var wasSupplied = false
    }

    private let lock = NSLock()
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private var samples: [Float] = []
    private var error: Error?
    private var level: (@MainActor (Float) -> Void)?
    private var failure: (@MainActor (Error) -> Void)?
    private var failureReported = false
    private var finished = false
    private var observedFirstInputBufferAt: ContinuousClock.Instant?
    private let now: @Sendable () -> ContinuousClock.Instant

    init(
      inputFormat: AVAudioFormat,
      outputFormat: AVAudioFormat,
      level: @escaping @MainActor (Float) -> Void,
      failure: @escaping @MainActor (Error) -> Void = { _ in },
      now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock().now }
    ) throws {
      guard let converter = AVAudioConverter(
        from: inputFormat,
        to: outputFormat
      ) else {
        throw DictationFailure.unavailable
      }
      self.converter = converter
      self.outputFormat = outputFormat
      self.level = level
      self.failure = failure
      self.now = now
    }

    var firstInputBufferAt: ContinuousClock.Instant? {
      lock.withLock { observedFirstInputBufferAt }
    }

    func append(_ buffer: AVAudioPCMBuffer) throws {
      let levels: [Float]
      do {
        levels = try lock.withLock {
          guard !finished else { throw CancellationError() }
          if let error { throw error }
          if buffer.frameLength > 0, observedFirstInputBufferAt == nil {
            observedFirstInputBufferAt = now()
          }
          do {
            let supply = InputSupply()
            var emittedLevels: [Float] = []
            while true {
              let output = try makeOutputBuffer(inputFrameCount: buffer.frameLength)
              var conversionError: NSError?
              let status = converter.convert(
                to: output,
                error: &conversionError
              ) { _, inputStatus in
                guard !supply.wasSupplied else {
                  inputStatus.pointee = .noDataNow
                  return nil
                }
                supply.wasSupplied = true
                inputStatus.pointee = .haveData
                return buffer
              }
              if let conversionError { throw conversionError }
              try appendOutput(output)
              if output.frameLength > 0 {
                emittedLevels.append(AudioBufferTools.normalizedRMS(output))
              }
              switch status {
              case .haveData:
                continue
              case .inputRanDry, .endOfStream:
                return emittedLevels
              case .error:
                throw AudioBufferTools.BufferError.conversionFailed
              @unknown default:
                throw AudioBufferTools.BufferError.conversionFailed
              }
            }
          } catch {
            self.error = self.error ?? error
            throw error
          }
        }
      } catch {
        reportFailure(error)
        throw error
      }
      for value in levels {
        Task { @MainActor [weak self] in
          self?.emit(value)
        }
      }
    }

    func finishAndTakeSamples() throws -> [Float] {
      do {
        let result: [Float] = try lock.withLock {
          defer {
            samples.removeAll(keepingCapacity: false)
            error = nil
            level = nil
            finished = true
          }
          if let error { throw error }
          guard !finished else { return [] }
          while true {
            let output = try makeOutputBuffer(inputFrameCount: 0)
            var conversionError: NSError?
            let status = converter.convert(
              to: output,
              error: &conversionError
            ) { _, inputStatus in
              inputStatus.pointee = .endOfStream
              return nil
            }
            if let conversionError { throw conversionError }
            try appendOutput(output)
            switch status {
            case .haveData, .inputRanDry:
              continue
            case .endOfStream:
              let result = samples
              failure = nil
              return result
            case .error:
              throw AudioBufferTools.BufferError.conversionFailed
            @unknown default:
              throw AudioBufferTools.BufferError.conversionFailed
            }
          }
        }
        return result
      } catch {
        reportFailure(error)
        throw error
      }
    }

    func cancel() {
      lock.withLock {
        finished = true
        converter.reset()
        samples.removeAll(keepingCapacity: false)
        error = nil
        level = nil
        failure = nil
      }
    }

    private func makeOutputBuffer(
      inputFrameCount: AVAudioFrameCount
    ) throws -> AVAudioPCMBuffer {
      let ratio = outputFormat.sampleRate / converter.inputFormat.sampleRate
      let convertedFrames = Int(ceil(Double(inputFrameCount) * ratio))
      let capacity = AVAudioFrameCount(max(convertedFrames + 64, 1_024))
      guard let output = AVAudioPCMBuffer(
        pcmFormat: outputFormat,
        frameCapacity: capacity
      ) else {
        throw AudioBufferTools.BufferError.allocationFailed
      }
      return output
    }

    private func appendOutput(_ buffer: AVAudioPCMBuffer) throws {
      guard
        buffer.format.commonFormat == .pcmFormatFloat32,
        buffer.format.channelCount == 1,
        let channel = buffer.floatChannelData?[0]
      else {
        throw DictationFailure.transcriptionFailed
      }
      let frameCount = Int(buffer.frameLength)
      guard frameCount <= Self.maximumSampleCount - samples.count else {
        throw EnhancedSpeechCaptureError.sampleLimitExceeded
      }
      samples.append(
        contentsOf: UnsafeBufferPointer(
          start: channel,
          count: frameCount
        )
      )
    }

    @MainActor
    private func emit(_ value: Float) {
      let callback = lock.withLock { level }
      callback?(value)
    }

    private func reportFailure(_ error: Error) {
      let callback: (@MainActor (Error) -> Void)? = lock.withLock {
        guard !failureReported else { return nil }
        failureReported = true
        let callback = failure
        failure = nil
        return callback
      }
      guard let callback else { return }
      Task { @MainActor in callback(error) }
    }
  }

  enum EnhancedSpeechAudioTapHandler {
    nonisolated static func makeHandler(
      for streamConverter: EnhancedAudioStreamConverter
    ) -> AVAudioNodeTapBlock {
      { buffer, _ in
        try? streamConverter.append(buffer)
      }
    }
  }

  @MainActor
  private final class EnhancedSystemAudioCapture: EnhancedAudioCapturing {
    private var engine: AVAudioEngine?
    private var streamConverter: EnhancedAudioStreamConverter?
    private var tapInstalled = false

    init(configuration: EnhancedAudioConfiguration) throws {
      guard configuration == .inference else {
        throw DictationFailure.unavailable
      }
      engine = AVAudioEngine()
    }

    func selectMicrophone(savedUID: String?) -> MicrophoneSelection {
      guard engine != nil else { return .automatic }
      return CoreAudioMicrophone.select(savedUID: savedUID)
    }

    func start(level: @escaping @MainActor (Float) -> Void) throws {
      try start(level: level, failure: { _ in })
    }

    func start(
      level: @escaping @MainActor (Float) -> Void,
      failure: @escaping @MainActor (Error) -> Void
    ) throws {
      guard let engine else {
        throw DictationFailure.unavailable
      }
      let inputNode = engine.inputNode
      let inputFormat = inputNode.inputFormat(forBus: 0)
      guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
        throw EnhancedSpeechCaptureError.missingInput
      }
      guard
        let outputFormat = AVAudioFormat(
          commonFormat: .pcmFormatFloat32,
          sampleRate: EnhancedAudioConfiguration.inference.sampleRate,
          channels: AVAudioChannelCount(EnhancedAudioConfiguration.inference.channelCount),
          interleaved: false
        )
      else {
        throw DictationFailure.unavailable
      }

      let streamConverter = try EnhancedAudioStreamConverter(
        inputFormat: inputFormat,
        outputFormat: outputFormat,
        level: level,
        failure: failure
      )
      self.streamConverter = streamConverter
      inputNode.installTap(
        onBus: 0,
        bufferSize: 1_024,
        format: inputFormat,
        block: EnhancedSpeechAudioTapHandler.makeHandler(for: streamConverter)
      )
      tapInstalled = true
      engine.prepare()
      do {
        try engine.start()
      } catch {
        stopAudio()
        streamConverter.cancel()
        self.streamConverter = nil
        throw error
      }
    }

    func stopAndTakeSamples() throws -> [Float] {
      stopAudio()
      return try streamConverter?.finishAndTakeSamples() ?? []
    }

    var firstInputBufferAt: ContinuousClock.Instant? {
      streamConverter?.firstInputBufferAt
    }

    func cancel() {
      stopAudio()
      streamConverter?.cancel()
    }

    func releaseResources() {
      stopAudio()
      streamConverter?.cancel()
      streamConverter = nil
      engine = nil
    }

    private func stopAudio() {
      guard let engine else { return }
      if tapInstalled {
        engine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
      }
      if engine.isRunning {
        engine.stop()
      }
    }
  }

  private extension String {
    var nilIfEmpty: String? {
      isEmpty ? nil : self
    }
  }
#endif
