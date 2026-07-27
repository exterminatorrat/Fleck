#if os(macOS)
  @preconcurrency import AVFAudio
  import FluidAudio
  import Foundation
  import MenuBarNotesCore

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
    func load(from repositoryURL: URL) async throws
    func transcribe(_ samples: [Float]) async throws -> String
    func cancel() async
    func releaseResources() async
  }

  @MainActor
  protocol EnhancedAudioCapturing: AnyObject {
    func start(level: @escaping @MainActor (Float) -> Void) throws
    func stopAndTakeSamples() throws -> [Float]
    func cancel()
    func releaseResources()
  }

  @MainActor
  final class EnhancedSpeechCapture: SpeechEngine {
    let kind: DictationSpeechEngine = .enhancedLocal

    static var isFluidAudioOffline: Bool {
      ModelHub.offlineMode
    }

    private final class Resources {
      let inference: any EnhancedSpeechInferring
      let audio: any EnhancedAudioCapturing
      var transcriptionTask: Task<String, Error>?
      var released = false

      init(
        inference: any EnhancedSpeechInferring,
        audio: any EnhancedAudioCapturing
      ) {
        self.inference = inference
        self.audio = audio
      }
    }

    private let verifiedLoadState: @MainActor () -> EnhancedModelVerifiedLoadState
    private let makeInference: @MainActor () -> any EnhancedSpeechInferring
    private let makeAudio: @MainActor (
      EnhancedAudioConfiguration
    ) throws -> any EnhancedAudioCapturing
    private let markRepairRequired: @MainActor (String) -> Void
    private let recommendStandard: @MainActor () -> Void

    private var loadingInference: (any EnhancedSpeechInferring)?
    private var resources: Resources?
    private var lifecycleID: UUID?

    var hasActiveResources: Bool {
      loadingInference != nil || resources != nil
    }

    init(
      verifiedLoadState: @escaping @MainActor () -> EnhancedModelVerifiedLoadState,
      makeInference: @escaping @MainActor () -> any EnhancedSpeechInferring = {
        FluidEnhancedSpeechInference()
      },
      makeAudio: @escaping @MainActor (
        EnhancedAudioConfiguration
      ) throws -> any EnhancedAudioCapturing = {
        try EnhancedSystemAudioCapture(configuration: $0)
      },
      markRepairRequired: @escaping @MainActor (String) -> Void = { _ in },
      recommendStandard: @escaping @MainActor () -> Void = {}
    ) {
      ModelHub.offlineMode = true
      self.verifiedLoadState = verifiedLoadState
      self.makeInference = makeInference
      self.makeAudio = makeAudio
      self.markRepairRequired = markRepairRequired
      self.recommendStandard = recommendStandard
    }

    convenience init(
      modelManager: EnhancedModelManager,
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
        makeInference: makeInference,
        makeAudio: makeAudio,
        markRepairRequired: { [weak modelManager] message in
          modelManager?.markInferenceLoadFailure(message: message)
        },
        recommendStandard: recommendStandard
      )
    }

    func start(
      provisional _: @escaping @MainActor (String) -> Void,
      level: @escaping @MainActor (Float) -> Void
    ) async throws {
      guard !hasActiveResources else {
        throw DictationFailure.unavailable
      }

      ModelHub.offlineMode = true
      let lifecycleID = UUID()
      self.lifecycleID = lifecycleID
      let inference = makeInference()
      loadingInference = inference

      guard case .ready(let repositoryURL) = verifiedLoadState() else {
        loadingInference = nil
        self.lifecycleID = nil
        await inference.releaseResources()
        throw DictationFailure.unavailable
      }

      do {
        ModelHub.offlineMode = true
        try await inference.load(from: repositoryURL)
      } catch {
        let wasCancelled = self.lifecycleID != lifecycleID
        if loadingInference === inference {
          loadingInference = nil
        }
        if self.lifecycleID == lifecycleID {
          self.lifecycleID = nil
        }
        await inference.releaseResources()
        if wasCancelled {
          throw CancellationError()
        }
        markRepairRequired(error.localizedDescription)
        recommendStandard()
        throw error
      }

      guard self.lifecycleID == lifecycleID else {
        if loadingInference === inference {
          loadingInference = nil
        }
        await inference.releaseResources()
        throw CancellationError()
      }
      loadingInference = nil

      guard
        case .ready(let currentRepositoryURL) = verifiedLoadState(),
        currentRepositoryURL == repositoryURL
      else {
        self.lifecycleID = nil
        await inference.releaseResources()
        throw DictationFailure.unavailable
      }

      do {
        let audio = try makeAudio(.inference)
        let resources = Resources(inference: inference, audio: audio)
        self.resources = resources
        try audio.start(level: level)
      } catch {
        let resources = self.resources
        self.resources = nil
        self.lifecycleID = nil
        resources?.audio.cancel()
        resources?.audio.releaseResources()
        await inference.releaseResources()
        throw error
      }
    }

    func finish() async throws -> String? {
      guard let resources else {
        throw DictationFailure.unavailable
      }

      let samples: [Float]
      do {
        samples = try resources.audio.stopAndTakeSamples()
      } catch {
        await release(resources, cancelling: true)
        throw error
      }
      guard !samples.isEmpty else {
        await release(resources, cancelling: false)
        return nil
      }

      let task = Task {
        try await resources.inference.transcribe(samples)
      }
      resources.transcriptionTask = task
      do {
        let text = try await task.value
        await release(resources, cancelling: false)
        return text
          .trimmingCharacters(in: .whitespacesAndNewlines)
          .nilIfEmpty
      } catch {
        await release(resources, cancelling: true)
        throw error
      }
    }

    func cancel() async {
      lifecycleID = nil
      if let loadingInference {
        self.loadingInference = nil
        await loadingInference.cancel()
        await loadingInference.releaseResources()
      }
      if let resources {
        await release(resources, cancelling: true)
      }
    }

    func releaseResources() async {
      await cancel()
    }

    private func release(
      _ candidate: Resources,
      cancelling: Bool
    ) async {
      guard !candidate.released else { return }
      candidate.released = true
      lifecycleID = nil
      if cancelling {
        candidate.audio.cancel()
        candidate.transcriptionTask?.cancel()
        await candidate.inference.cancel()
      }
      _ = await candidate.transcriptionTask?.result
      candidate.audio.releaseResources()
      await candidate.inference.releaseResources()
      candidate.transcriptionTask = nil
      if resources === candidate {
        resources = nil
      }
    }
  }

  @MainActor
  private final class FluidEnhancedSpeechInference: EnhancedSpeechInferring {
    private var models: AsrModels?
    private var manager: AsrManager?
    private var loadTask: Task<AsrModels, Error>?

    func load(from repositoryURL: URL) async throws {
      ModelHub.offlineMode = true
      let task = Task {
        try await AsrModels.load(
          from: repositoryURL,
          configuration: AsrModels.defaultConfiguration(),
          version: .v2
        )
      }
      loadTask = task
      let models = try await task.value
      loadTask = nil
      try Task.checkCancellation()

      let manager = AsrManager(config: .default)
      do {
        try await manager.loadModels(models)
      } catch {
        await manager.cleanup()
        throw error
      }
      self.models = models
      self.manager = manager
    }

    func transcribe(_ samples: [Float]) async throws -> String {
      guard let manager else {
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

    func cancel() async {
      loadTask?.cancel()
    }

    func releaseResources() async {
      loadTask?.cancel()
      _ = await loadTask?.result
      loadTask = nil
      await manager?.cleanup()
      manager = nil
      models = nil
    }
  }

  private final class EnhancedSampleAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var error: Error?
    private var level: (@MainActor (Float) -> Void)?

    init(level: @escaping @MainActor (Float) -> Void) {
      self.level = level
    }

    func append(_ buffer: AVAudioPCMBuffer) {
      guard
        buffer.format.commonFormat == .pcmFormatFloat32,
        buffer.format.channelCount == 1,
        let channel = buffer.floatChannelData?[0]
      else {
        fail(DictationFailure.transcriptionFailed)
        return
      }
      let values = Array(
        UnsafeBufferPointer(
          start: channel,
          count: Int(buffer.frameLength)
        )
      )
      lock.withLock {
        guard error == nil else { return }
        samples.append(contentsOf: values)
      }
      let rms = AudioBufferTools.normalizedRMS(buffer)
      Task { @MainActor [weak self] in
        self?.emit(rms)
      }
    }

    func fail(_ error: Error) {
      lock.withLock {
        if self.error == nil {
          self.error = error
        }
      }
    }

    func take() throws -> [Float] {
      try lock.withLock {
        defer {
          samples.removeAll(keepingCapacity: false)
          error = nil
          level = nil
        }
        if let error { throw error }
        return samples
      }
    }

    func clear() {
      lock.withLock {
        samples.removeAll(keepingCapacity: false)
        error = nil
        level = nil
      }
    }

    @MainActor
    private func emit(_ value: Float) {
      level?(value)
    }
  }

  @MainActor
  private final class EnhancedSystemAudioCapture: EnhancedAudioCapturing {
    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var accumulator: EnhancedSampleAccumulator?
    private var tapInstalled = false

    init(configuration: EnhancedAudioConfiguration) throws {
      guard configuration == .inference else {
        throw DictationFailure.unavailable
      }
      engine = AVAudioEngine()
    }

    func start(level: @escaping @MainActor (Float) -> Void) throws {
      guard let engine else {
        throw DictationFailure.unavailable
      }
      let inputNode = engine.inputNode
      let inputFormat = inputNode.inputFormat(forBus: 0)
      guard
        let outputFormat = AVAudioFormat(
          commonFormat: .pcmFormatFloat32,
          sampleRate: EnhancedAudioConfiguration.inference.sampleRate,
          channels: AVAudioChannelCount(EnhancedAudioConfiguration.inference.channelCount),
          interleaved: false
        ),
        let converter = AVAudioConverter(
          from: inputFormat,
          to: outputFormat
        )
      else {
        throw DictationFailure.unavailable
      }

      let accumulator = EnhancedSampleAccumulator(level: level)
      self.converter = converter
      self.accumulator = accumulator
      inputNode.installTap(
        onBus: 0,
        bufferSize: 1_024,
        format: inputFormat
      ) { buffer, _ in
        do {
          accumulator.append(
            try AudioBufferTools.convert(
              buffer,
              using: converter,
              to: outputFormat
            )
          )
        } catch {
          accumulator.fail(error)
        }
      }
      tapInstalled = true
      engine.prepare()
      do {
        try engine.start()
      } catch {
        stopAudio()
        accumulator.clear()
        self.accumulator = nil
        self.converter = nil
        throw error
      }
    }

    func stopAndTakeSamples() throws -> [Float] {
      stopAudio()
      return try accumulator?.take() ?? []
    }

    func cancel() {
      stopAudio()
      accumulator?.clear()
    }

    func releaseResources() {
      stopAudio()
      accumulator?.clear()
      accumulator = nil
      converter = nil
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
