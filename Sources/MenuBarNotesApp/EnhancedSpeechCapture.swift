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

    private final class LoadingResources {
      let inference: any EnhancedSpeechInferring
      var released = false

      init(inference: any EnhancedSpeechInferring) {
        self.inference = inference
      }
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
    private let markRepairRequired: @MainActor (String, URL) -> Void
    private let recommendStandard: @MainActor () -> Void

    private var loadingResources: LoadingResources?
    private var resources: Resources?
    private var lifecycleID: UUID?

    var hasActiveResources: Bool {
      loadingResources != nil || resources != nil
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
      markRepairRequired: @escaping @MainActor (String, URL) -> Void = { _, _ in },
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
      let loadingResources = LoadingResources(inference: inference)
      self.loadingResources = loadingResources

      guard case .ready(let repositoryURL) = verifiedLoadState() else {
        self.lifecycleID = nil
        await release(loadingResources, cancelling: false)
        recommendStandard()
        throw DictationFailure.unavailable
      }

      do {
        ModelHub.offlineMode = true
        try await inference.load(from: repositoryURL)
      } catch {
        let wasCancelled = self.lifecycleID != lifecycleID
        if self.lifecycleID == lifecycleID {
          self.lifecycleID = nil
        }
        await release(loadingResources, cancelling: wasCancelled)
        if wasCancelled {
          throw CancellationError()
        }
        markRepairRequired(error.localizedDescription, repositoryURL)
        recommendStandard()
        throw error
      }

      guard self.lifecycleID == lifecycleID else {
        await release(loadingResources, cancelling: true)
        throw CancellationError()
      }

      guard
        case .ready(let currentRepositoryURL) = verifiedLoadState(),
        currentRepositoryURL == repositoryURL
      else {
        self.lifecycleID = nil
        await release(loadingResources, cancelling: false)
        recommendStandard()
        throw DictationFailure.unavailable
      }

      do {
        let audio = try makeAudio(.inference)
        let resources = Resources(inference: inference, audio: audio)
        self.resources = resources
        try audio.start(level: level)
        self.loadingResources = nil
      } catch {
        let resources = self.resources
        self.resources = nil
        self.lifecycleID = nil
        resources?.audio.cancel()
        resources?.audio.releaseResources()
        await release(loadingResources, cancelling: true)
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
        guard !resources.released else {
          throw CancellationError()
        }
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
      if let loadingResources {
        await release(loadingResources, cancelling: true)
      }
      if let resources {
        await release(resources, cancelling: true)
      }
    }

    func releaseResources() async {
      await cancel()
    }

    private func release(
      _ candidate: LoadingResources,
      cancelling: Bool
    ) async {
      guard !candidate.released else { return }
      candidate.released = true
      if cancelling {
        await candidate.inference.cancel()
      }
      await candidate.inference.releaseResources()
      if loadingResources === candidate {
        loadingResources = nil
      }
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

  final class EnhancedAudioStreamConverter: @unchecked Sendable {
    private final class InputSupply: @unchecked Sendable {
      var wasSupplied = false
    }

    private let lock = NSLock()
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private var samples: [Float] = []
    private var error: Error?
    private var level: (@MainActor (Float) -> Void)?
    private var finished = false

    init(
      inputFormat: AVAudioFormat,
      outputFormat: AVAudioFormat,
      level: @escaping @MainActor (Float) -> Void
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
    }

    func append(_ buffer: AVAudioPCMBuffer) throws {
      let levels = try lock.withLock {
        guard !finished else { throw CancellationError() }
        if let error { throw error }
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
          self.error = error
          throw error
        }
      }
      for value in levels {
        Task { @MainActor [weak self] in
          self?.emit(value)
        }
      }
    }

    func finishAndTakeSamples() throws -> [Float] {
      try lock.withLock {
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
            return samples
          case .error:
            throw AudioBufferTools.BufferError.conversionFailed
          @unknown default:
            throw AudioBufferTools.BufferError.conversionFailed
          }
        }
      }
    }

    func cancel() {
      lock.withLock {
        finished = true
        converter.reset()
        samples.removeAll(keepingCapacity: false)
        error = nil
        level = nil
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
      samples.append(
        contentsOf: UnsafeBufferPointer(
          start: channel,
          count: Int(buffer.frameLength)
        )
      )
    }

    @MainActor
    private func emit(_ value: Float) {
      let callback = lock.withLock { level }
      callback?(value)
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
        )
      else {
        throw DictationFailure.unavailable
      }

      let streamConverter = try EnhancedAudioStreamConverter(
        inputFormat: inputFormat,
        outputFormat: outputFormat,
        level: level
      )
      self.streamConverter = streamConverter
      inputNode.installTap(
        onBus: 0,
        bufferSize: 1_024,
        format: inputFormat
      ) { buffer, _ in
        try? streamConverter.append(buffer)
      }
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
