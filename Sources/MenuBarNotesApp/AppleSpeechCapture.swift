@preconcurrency import AVFAudio
import AudioToolbox
import CoreAudio
import Foundation
import MenuBarNotesCore
@preconcurrency import Speech

enum DictationFailure: Error, Equatable {
  case unavailable
  case permissionDenied
  case noSpeech
  case transcriptionFailed
  case saveFailed
  case interrupted
}

enum MicrophoneSelection: Equatable, Sendable {
  case automatic
  case selected(uid: String)
  case missingUsingAutomatic(settingsCopy: String)

  static func resolve(savedUID: String?, availableUIDs: [String]) -> Self {
    guard let savedUID else { return .automatic }
    guard availableUIDs.contains(savedUID) else {
      return .missingUsingAutomatic(
        settingsCopy: "The saved microphone is unavailable. Using Automatic."
      )
    }
    return .selected(uid: savedUID)
  }
}

enum AudioBufferTools {
  private final class InputSupply: @unchecked Sendable {
    var wasSupplied = false
  }

  enum BufferError: Error {
    case allocationFailed
    case conversionFailed
  }

  static func copy(_ source: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
    guard let result = AVAudioPCMBuffer(
      pcmFormat: source.format,
      frameCapacity: source.frameLength
    ) else {
      throw BufferError.allocationFailed
    }
    result.frameLength = source.frameLength
    let sourceBuffers = UnsafeMutableAudioBufferListPointer(source.mutableAudioBufferList)
    let resultBuffers = UnsafeMutableAudioBufferListPointer(result.mutableAudioBufferList)
    for index in 0..<min(sourceBuffers.count, resultBuffers.count) {
      let byteCount = Int(sourceBuffers[index].mDataByteSize)
      guard let sourceData = sourceBuffers[index].mData,
            let resultData = resultBuffers[index].mData
      else { continue }
      resultData.copyMemory(from: sourceData, byteCount: byteCount)
      resultBuffers[index].mDataByteSize = sourceBuffers[index].mDataByteSize
    }
    return result
  }

  static func normalizedRMS(_ buffer: AVAudioPCMBuffer) -> Float {
    guard buffer.format.commonFormat == .pcmFormatFloat32,
          let channels = buffer.floatChannelData,
          buffer.frameLength > 0
    else { return 0 }
    let channelCount = Int(buffer.format.channelCount)
    let frameCount = Int(buffer.frameLength)
    var squareSum: Float = 0
    for channel in 0..<channelCount {
      for frame in 0..<frameCount {
        let sample = channels[channel][frame]
        squareSum += sample * sample
      }
    }
    let rms = sqrt(squareSum / Float(channelCount * frameCount))
    return min(max(rms, 0), 1)
  }

  static func convert(
    _ source: AVAudioPCMBuffer,
    using converter: AVAudioConverter,
    to outputFormat: AVAudioFormat
  ) throws -> AVAudioPCMBuffer {
    let ratio = outputFormat.sampleRate / source.format.sampleRate
    let capacity = AVAudioFrameCount(ceil(Double(source.frameLength) * ratio)) + 1
    guard let result = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
      throw BufferError.allocationFailed
    }
    let inputSupply = InputSupply()
    var conversionError: NSError?
    let status = converter.convert(to: result, error: &conversionError) { _, inputStatus in
      if inputSupply.wasSupplied {
        inputStatus.pointee = .noDataNow
        return nil
      }
      inputSupply.wasSupplied = true
      inputStatus.pointee = .haveData
      return source
    }
    guard conversionError == nil, status != .error else {
      throw conversionError ?? BufferError.conversionFailed
    }
    return result
  }
}

enum AppleSpeechLocale {
  static func containsEquivalent(_ target: Locale, in installed: [Locale]) -> Bool {
    let target = Locale.Components(identifier: target.identifier).languageComponents
    return installed.contains {
      let candidate = Locale.Components(identifier: $0.identifier).languageComponents
      return candidate.languageCode == target.languageCode
        && candidate.script == target.script
        && candidate.region == target.region
    }
  }
}

final class BoundedAudioIngress: @unchecked Sendable {
  let buffers: AsyncThrowingStream<AVAudioPCMBuffer, Error>
  private let continuation: AsyncThrowingStream<AVAudioPCMBuffer, Error>.Continuation
  private let lock = NSLock()
  private var terminated = false

  init(capacity: Int) {
    var continuation: AsyncThrowingStream<AVAudioPCMBuffer, Error>.Continuation?
    buffers = AsyncThrowingStream(bufferingPolicy: .bufferingNewest(capacity)) {
      continuation = $0
    }
    self.continuation = continuation!
  }

  @discardableResult
  func yield(_ buffer: AVAudioPCMBuffer) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard !terminated else { return false }
    switch continuation.yield(buffer) {
    case .enqueued:
      return true
    case .dropped:
      terminated = true
      continuation.finish(throwing: DictationFailure.transcriptionFailed)
      return false
    case .terminated:
      terminated = true
      return false
    @unknown default:
      terminated = true
      continuation.finish(throwing: DictationFailure.transcriptionFailed)
      return false
    }
  }

  func finish() {
    lock.lock()
    defer { lock.unlock() }
    guard !terminated else { return }
    terminated = true
    continuation.finish()
  }

  func fail(_ error: Error) {
    lock.lock()
    defer { lock.unlock() }
    guard !terminated else { return }
    terminated = true
    continuation.finish(throwing: error)
  }
}

@MainActor
protocol AppleSpeechSession: AnyObject {
  var supportsOnDeviceRecognition: Bool { get }

  func start(
    provisional: @escaping @MainActor (String) -> Void,
    level: @escaping @MainActor (Float) -> Void
  ) async throws
  func finish() async throws -> String?
  func cancel() async
  func releaseResources() async
}

@MainActor
protocol AppleSpeechInterruptionSource: AnyObject {
  func start(_ handler: @escaping @MainActor @Sendable () -> Void)
  func stop()
}

@MainActor
private final class SystemAppleSpeechInterruptionSource: AppleSpeechInterruptionSource {
  private var token: NSObjectProtocol?

  func start(_ handler: @escaping @MainActor @Sendable () -> Void) {
    stop()
    token = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange,
      object: nil,
      queue: nil
    ) { _ in
      Task { @MainActor in handler() }
    }
  }

  func stop() {
    guard let token else { return }
    NotificationCenter.default.removeObserver(token)
    self.token = nil
  }
}

@MainActor
final class AppleSpeechCapture: SpeechEngine {
  let kind: DictationSpeechEngine = .standard

  private let requestPermission: () async -> DictationPermissionResult
  private let makeSession: () async throws -> any AppleSpeechSession
  private let interruptions: any AppleSpeechInterruptionSource
  private var session: (any AppleSpeechSession)?
  private var terminalFailure: DictationFailure?
  private var terminalCommandIssued = false
  private var interruptionObservationActive = false

  init(
    requestPermission: @escaping () async -> DictationPermissionResult,
    makeSession: @escaping () async throws -> any AppleSpeechSession,
    interruptions: any AppleSpeechInterruptionSource = SystemAppleSpeechInterruptionSource()
  ) {
    self.requestPermission = requestPermission
    self.makeSession = makeSession
    self.interruptions = interruptions
  }

  convenience init(
    microphoneUID: String? = nil,
    permissions: DictationPermissionController = .init(),
    microphoneSelectionChanged: @escaping @MainActor (MicrophoneSelection) -> Void = { _ in }
  ) {
    self.init(
      requestPermission: {
        await permissions.requestAccess(after: .toolbarMicrophone)
      },
      makeSession: {
        if #available(macOS 26.0, *) {
          return ModernAppleSpeechSession(
            microphoneUID: microphoneUID,
            microphoneSelectionChanged: microphoneSelectionChanged
          )
        }
        return LegacyAppleSpeechSession(
          microphoneUID: microphoneUID,
          microphoneSelectionChanged: microphoneSelectionChanged
        )
      },
      interruptions: SystemAppleSpeechInterruptionSource()
    )
  }

  func start(
    provisional: @escaping @MainActor (String) -> Void,
    level: @escaping @MainActor (Float) -> Void
  ) async throws {
    guard case .granted = await requestPermission() else {
      throw DictationFailure.permissionDenied
    }
    let session = try await makeSession()
    guard session.supportsOnDeviceRecognition else {
      await session.releaseResources()
      throw DictationFailure.unavailable
    }
    self.session = session
    terminalFailure = nil
    terminalCommandIssued = false
    do {
      try await session.start(provisional: provisional, level: level)
      interruptionObservationActive = true
      interruptions.start { [weak self] in
        Task { @MainActor [weak self] in
          await self?.interrupt()
        }
      }
    } catch {
      await release(session)
      throw error
    }
  }

  func finish() async throws -> String? {
    if let terminalFailure { throw terminalFailure }
    guard let session else { throw DictationFailure.unavailable }
    terminalCommandIssued = true
    do {
      let text = try await session.finish()
      await release(session)
      if let terminalFailure { throw terminalFailure }
      return text?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    } catch {
      await release(session)
      throw terminalFailure ?? error
    }
  }

  func cancel() async {
    guard let session else { return }
    if !terminalCommandIssued {
      terminalCommandIssued = true
      await session.cancel()
    }
    await release(session)
  }

  func releaseResources() async {
    guard let session else { return }
    if !terminalCommandIssued {
      terminalCommandIssued = true
      await session.cancel()
    }
    await release(session)
  }

  private func interrupt() async {
    guard terminalFailure == nil, let session else { return }
    terminalFailure = .interrupted
    if !terminalCommandIssued {
      terminalCommandIssued = true
    }
    await session.cancel()
    await release(session)
  }

  private func release(_ candidate: any AppleSpeechSession) async {
    guard let session, session === candidate else { return }
    self.session = nil
    stopInterruptionObservation()
    await candidate.releaseResources()
  }

  private func stopInterruptionObservation() {
    guard interruptionObservationActive else { return }
    interruptionObservationActive = false
    interruptions.stop()
  }
}

private extension String {
  var nilIfEmpty: String? { isEmpty ? nil : self }
}

@MainActor
private enum CoreAudioMicrophone {
  static func select(
    savedUID: String?,
    for inputNode: AVAudioInputNode
  ) -> MicrophoneSelection {
    let devices = inputDevices()
    let selection = MicrophoneSelection.resolve(
      savedUID: savedUID,
      availableUIDs: devices.map(\.uid)
    )
    guard case .selected(let uid) = selection,
          let deviceID = devices.first(where: { $0.uid == uid })?.id,
          let audioUnit = inputNode.audioUnit
    else { return selection }
    var mutableDeviceID = deviceID
    let status = AudioUnitSetProperty(
      audioUnit,
      kAudioOutputUnitProperty_CurrentDevice,
      kAudioUnitScope_Global,
      0,
      &mutableDeviceID,
      UInt32(MemoryLayout<AudioDeviceID>.size)
    )
    return status == noErr
      ? selection
      : .missingUsingAutomatic(
        settingsCopy: "The saved microphone is unavailable. Using Automatic."
      )
  }

  private static func inputDevices() -> [(id: AudioDeviceID, uid: String)] {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var byteCount: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &byteCount
    ) == noErr else { return [] }
    let count = Int(byteCount) / MemoryLayout<AudioDeviceID>.size
    var ids = [AudioDeviceID](repeating: 0, count: count)
    guard AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &byteCount,
      &ids
    ) == noErr else { return [] }
    return ids.compactMap { id in
      guard hasInputChannels(id), let uid = uid(for: id) else { return nil }
      return (id, uid)
    }
  }

  private static func hasInputChannels(_ id: AudioDeviceID) -> Bool {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreamConfiguration,
      mScope: kAudioDevicePropertyScopeInput,
      mElement: kAudioObjectPropertyElementMain
    )
    var byteCount: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &byteCount) == noErr else {
      return false
    }
    let raw = UnsafeMutableRawPointer.allocate(
      byteCount: Int(byteCount),
      alignment: MemoryLayout<AudioBufferList>.alignment
    )
    defer { raw.deallocate() }
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &byteCount, raw) == noErr else {
      return false
    }
    let buffers = UnsafeMutableAudioBufferListPointer(
      raw.assumingMemoryBound(to: AudioBufferList.self)
    )
    return buffers.contains { $0.mNumberChannels > 0 }
  }

  private static func uid(for id: AudioDeviceID) -> String? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyDeviceUID,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var uid: Unmanaged<CFString>?
    var byteCount = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &byteCount, &uid) == noErr else {
      return nil
    }
    return uid?.takeUnretainedValue() as String?
  }
}

@MainActor
private final class LegacyAppleSpeechSession: AppleSpeechSession {
  private let recognizer: SFSpeechRecognizer?
  private let audioEngine = AVAudioEngine()
  private let microphoneUID: String?
  private let microphoneSelectionChanged: @MainActor (MicrophoneSelection) -> Void
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private var ingress: BoundedAudioIngress?
  private var ingressWorker: Task<Void, Never>?
  private var provisional: (@MainActor (String) -> Void)?
  private var level: (@MainActor (Float) -> Void)?
  private var terminal: Result<String?, Error>?
  private var finishContinuation: CheckedContinuation<String?, Error>?
  private var tapInstalled = false
  private var didEndAudio = false
  private var didCancelRecognition = false

  var supportsOnDeviceRecognition: Bool {
    recognizer?.supportsOnDeviceRecognition == true
  }

  init(
    microphoneUID: String?,
    microphoneSelectionChanged: @escaping @MainActor (MicrophoneSelection) -> Void
  ) {
    recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    self.microphoneUID = microphoneUID
    self.microphoneSelectionChanged = microphoneSelectionChanged
  }

  func start(
    provisional: @escaping @MainActor (String) -> Void,
    level: @escaping @MainActor (Float) -> Void
  ) async throws {
    guard let recognizer, recognizer.supportsOnDeviceRecognition else {
      throw DictationFailure.unavailable
    }
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.requiresOnDeviceRecognition = true
    request.shouldReportPartialResults = true
    request.taskHint = .dictation
    self.request = request
    self.provisional = provisional
    self.level = level
    terminal = nil
    didEndAudio = false
    didCancelRecognition = false

    let inputNode = audioEngine.inputNode
    microphoneSelectionChanged(CoreAudioMicrophone.select(savedUID: microphoneUID, for: inputNode))
    let inputFormat = inputNode.inputFormat(forBus: 0)
    let ingress = BoundedAudioIngress(capacity: 8)
    self.ingress = ingress
    ingressWorker = Task { @MainActor [weak self] in
      do {
        for try await buffer in ingress.buffers {
          guard let self else { return }
          self.request?.append(buffer)
          self.level?(AudioBufferTools.normalizedRMS(buffer))
        }
      } catch {
        self?.resolve(.failure(error))
      }
    }
    inputNode.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) { buffer, _ in
      do {
        _ = ingress.yield(try AudioBufferTools.copy(buffer))
      } catch {
        ingress.fail(DictationFailure.transcriptionFailed)
      }
    }
    tapInstalled = true
    recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
      Task { @MainActor [weak self] in
        self?.receive(result: result, error: error)
      }
    }
    audioEngine.prepare()
    do {
      try audioEngine.start()
    } catch {
      stopAudio()
      ingress.finish()
      await ingressWorker?.value
      cancelRecognitionOnce()
      recognitionTask = nil
      self.request = nil
      throw error
    }
  }

  func finish() async throws -> String? {
    stopAudio()
    ingress?.finish()
    await ingressWorker?.value
    endAudioOnce()
    if let terminal {
      return try terminal.get()
    }
    return try await withCheckedThrowingContinuation { continuation in
      finishContinuation = continuation
    }
  }

  func cancel() async {
    stopAudio()
    ingress?.finish()
    await ingressWorker?.value
    cancelRecognitionOnce()
    resolve(.success(nil))
  }

  func releaseResources() async {
    stopAudio()
    ingress?.finish()
    await ingressWorker?.value
    if terminal == nil {
      cancelRecognitionOnce()
      resolve(.success(nil))
    }
    recognitionTask = nil
    request = nil
    ingress = nil
    ingressWorker = nil
    provisional = nil
    level = nil
  }

  private func receive(result: SFSpeechRecognitionResult?, error: Error?) {
    if let result {
      let text = result.bestTranscription.formattedString
      if result.isFinal {
        resolve(.success(text))
      } else {
        provisional?(text)
      }
    }
    if let error {
      let nsError = error as NSError
      if nsError.code == 1_110 {
        resolve(.success(nil))
      } else {
        resolve(.failure(error))
      }
    }
  }

  private func resolve(_ result: Result<String?, Error>) {
    guard terminal == nil else { return }
    terminal = result
    stopAudio()
    if let finishContinuation {
      self.finishContinuation = nil
      finishContinuation.resume(with: result)
    }
  }

  private func stopAudio() {
    if tapInstalled {
      audioEngine.inputNode.removeTap(onBus: 0)
      tapInstalled = false
    }
    if audioEngine.isRunning {
      audioEngine.stop()
    }
  }

  private func endAudioOnce() {
    guard !didEndAudio else { return }
    didEndAudio = true
    request?.endAudio()
  }

  private func cancelRecognitionOnce() {
    guard !didCancelRecognition else { return }
    didCancelRecognition = true
    recognitionTask?.cancel()
  }
}

@available(macOS 26.0, *)
private final class ModernAudioConversion: @unchecked Sendable {
  private let converter: AVAudioConverter
  private let outputFormat: AVAudioFormat
  private let level: @MainActor (Float) -> Void

  init(
    converter: AVAudioConverter,
    outputFormat: AVAudioFormat,
    level: @escaping @MainActor (Float) -> Void
  ) {
    self.converter = converter
    self.outputFormat = outputFormat
    self.level = level
  }

  func analyzerInput(for buffer: AVAudioPCMBuffer) async throws -> AnalyzerInput {
    let converted = try AudioBufferTools.convert(
      buffer,
      using: converter,
      to: outputFormat
    )
    await level(AudioBufferTools.normalizedRMS(buffer))
    return AnalyzerInput(buffer: converted)
  }
}

@available(macOS 26.0, *)
private struct ModernAnalyzerInputSequence: AsyncSequence, @unchecked Sendable {
  typealias Element = AnalyzerInput

  struct AsyncIterator: AsyncIteratorProtocol {
    var buffers: AsyncThrowingStream<AVAudioPCMBuffer, Error>.Iterator
    let conversion: ModernAudioConversion

    mutating func next() async throws -> AnalyzerInput? {
      guard let buffer = try await buffers.next() else { return nil }
      return try await conversion.analyzerInput(for: buffer)
    }
  }

  let buffers: AsyncThrowingStream<AVAudioPCMBuffer, Error>
  let conversion: ModernAudioConversion

  func makeAsyncIterator() -> AsyncIterator {
    .init(buffers: buffers.makeAsyncIterator(), conversion: conversion)
  }
}

@available(macOS 26.0, *)
@MainActor
private final class ModernAppleSpeechSession: AppleSpeechSession {
  private let locale = Locale(identifier: "en-US")
  private let audioEngine = AVAudioEngine()
  private let microphoneUID: String?
  private let microphoneSelectionChanged: @MainActor (MicrophoneSelection) -> Void
  private var analyzer: SpeechAnalyzer?
  private var ingress: BoundedAudioIngress?
  private var analysisTask: Task<Void, Never>?
  private var resultsTask: Task<Void, Never>?
  private var provisional: (@MainActor (String) -> Void)?
  private var level: (@MainActor (Float) -> Void)?
  private var finalSegments: [String] = []
  private var terminalError: Error?
  private var tapInstalled = false
  private var didFinalize = false
  private var didCancelAnalyzer = false

  var supportsOnDeviceRecognition: Bool { true }

  init(
    microphoneUID: String?,
    microphoneSelectionChanged: @escaping @MainActor (MicrophoneSelection) -> Void
  ) {
    self.microphoneUID = microphoneUID
    self.microphoneSelectionChanged = microphoneSelectionChanged
  }

  func start(
    provisional: @escaping @MainActor (String) -> Void,
    level: @escaping @MainActor (Float) -> Void
  ) async throws {
    let installedLocales = await DictationTranscriber.installedLocales
    guard AppleSpeechLocale.containsEquivalent(locale, in: installedLocales) else {
      throw DictationFailure.unavailable
    }

    let inputNode = audioEngine.inputNode
    microphoneSelectionChanged(CoreAudioMicrophone.select(savedUID: microphoneUID, for: inputNode))
    let naturalFormat = inputNode.inputFormat(forBus: 0)
    let transcriber = DictationTranscriber(
      locale: locale,
      preset: .progressiveShortDictation
    )
    let modules: [any SpeechModule] = [transcriber]
    guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(
      compatibleWith: modules,
      considering: naturalFormat
    ) else {
      throw DictationFailure.unavailable
    }
    let analyzer = SpeechAnalyzer(
      modules: modules,
      options: .init(priority: .userInitiated, modelRetention: .whileInUse)
    )
    try await analyzer.prepareToAnalyze(in: format)

    guard let converter = AVAudioConverter(from: naturalFormat, to: format) else {
      throw DictationFailure.unavailable
    }
    let ingress = BoundedAudioIngress(capacity: 8)
    let inputs = ModernAnalyzerInputSequence(
      buffers: ingress.buffers,
      conversion: .init(converter: converter, outputFormat: format, level: level)
    )
    self.analyzer = analyzer
    self.ingress = ingress
    self.provisional = provisional
    self.level = level
    finalSegments = []
    terminalError = nil
    didFinalize = false
    didCancelAnalyzer = false

    analysisTask = Task { [weak self] in
      do {
        try await analyzer.start(inputSequence: inputs)
      } catch {
        self?.terminalError = error
        self?.stopAudio()
      }
    }
    resultsTask = Task { [weak self] in
      do {
        for try await result in transcriber.results {
          guard let self else { return }
          let text = String(result.text.characters)
          if result.isFinal {
            self.finalSegments.append(text)
          } else {
            self.provisional?(text)
          }
        }
      } catch {
        self?.terminalError = error
      }
    }

    inputNode.installTap(onBus: 0, bufferSize: 1_024, format: naturalFormat) { buffer, _ in
      do {
        _ = ingress.yield(try AudioBufferTools.copy(buffer))
      } catch {
        ingress.fail(DictationFailure.transcriptionFailed)
      }
    }
    tapInstalled = true
    audioEngine.prepare()
    do {
      try audioEngine.start()
    } catch {
      stopAudio()
      ingress.finish()
      await analysisTask?.value
      await cancelAnalyzerOnce()
      throw error
    }
  }

  func finish() async throws -> String? {
    stopAudio()
    ingress?.finish()
    await analysisTask?.value
    if let terminalError {
      await cancelAnalyzerOnce()
      resultsTask?.cancel()
      await resultsTask?.value
      throw terminalError
    }
    do {
      try await finalizeAnalyzerOnce()
    } catch {
      terminalError = error
      await cancelAnalyzerOnce()
      resultsTask?.cancel()
      await resultsTask?.value
      throw error
    }
    await resultsTask?.value
    if let terminalError { throw terminalError }
    let text = finalSegments.joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return text.nilIfEmpty
  }

  func cancel() async {
    stopAudio()
    ingress?.finish()
    await cancelAnalyzerOnce()
    analysisTask?.cancel()
    resultsTask?.cancel()
    await analysisTask?.value
    await resultsTask?.value
  }

  func releaseResources() async {
    stopAudio()
    ingress?.finish()
    await analysisTask?.value
    if !didFinalize && !didCancelAnalyzer {
      await cancelAnalyzerOnce()
    }
    if didCancelAnalyzer {
      analysisTask?.cancel()
      resultsTask?.cancel()
    }
    await analysisTask?.value
    await resultsTask?.value
    analysisTask = nil
    resultsTask = nil
    ingress = nil
    analyzer = nil
    provisional = nil
    level = nil
    finalSegments = []
    terminalError = nil
  }

  private func stopAudio() {
    if tapInstalled {
      audioEngine.inputNode.removeTap(onBus: 0)
      tapInstalled = false
    }
    if audioEngine.isRunning {
      audioEngine.stop()
    }
  }

  private func finalizeAnalyzerOnce() async throws {
    guard !didFinalize else { return }
    didFinalize = true
    try await analyzer?.finalizeAndFinishThroughEndOfInput()
  }

  private func cancelAnalyzerOnce() async {
    guard !didCancelAnalyzer else { return }
    didCancelAnalyzer = true
    await analyzer?.cancelAndFinishNow()
  }
}
