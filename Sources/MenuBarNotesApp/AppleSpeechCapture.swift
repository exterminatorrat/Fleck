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
        inputStatus.pointee = .endOfStream
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
final class AppleSpeechCapture: SpeechEngine {
  let kind: DictationSpeechEngine = .standard

  private let requestPermission: () async -> DictationPermissionResult
  private let makeSession: () async throws -> any AppleSpeechSession
  private var session: (any AppleSpeechSession)?

  init(
    requestPermission: @escaping () async -> DictationPermissionResult,
    makeSession: @escaping () async throws -> any AppleSpeechSession
  ) {
    self.requestPermission = requestPermission
    self.makeSession = makeSession
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
      }
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
    do {
      try await session.start(provisional: provisional, level: level)
    } catch {
      await releaseResources()
      throw error
    }
  }

  func finish() async throws -> String? {
    guard let session else { throw DictationFailure.unavailable }
    do {
      let text = try await session.finish()
      await releaseResources()
      return text?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    } catch {
      await releaseResources()
      throw error
    }
  }

  func cancel() async {
    await session?.cancel()
    await releaseResources()
  }

  func releaseResources() async {
    guard let session else { return }
    self.session = nil
    await session.releaseResources()
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
  private var provisional: (@MainActor (String) -> Void)?
  private var level: (@MainActor (Float) -> Void)?
  private var terminal: Result<String?, Error>?
  private var finishContinuation: CheckedContinuation<String?, Error>?
  private var tapInstalled = false

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

    let inputNode = audioEngine.inputNode
    microphoneSelectionChanged(CoreAudioMicrophone.select(savedUID: microphoneUID, for: inputNode))
    let inputFormat = inputNode.inputFormat(forBus: 0)
    inputNode.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) {
      [weak self] buffer, _ in
      guard let copied = try? AudioBufferTools.copy(buffer) else { return }
      let rms = AudioBufferTools.normalizedRMS(copied)
      Task { @MainActor [weak self] in
        self?.request?.append(copied)
        self?.level?(rms)
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
      recognitionTask?.cancel()
      recognitionTask = nil
      self.request = nil
      throw error
    }
  }

  func finish() async throws -> String? {
    stopAudio()
    request?.endAudio()
    if let terminal {
      return try terminal.get()
    }
    return try await withCheckedThrowingContinuation { continuation in
      finishContinuation = continuation
    }
  }

  func cancel() async {
    stopAudio()
    request?.endAudio()
    recognitionTask?.cancel()
    resolve(.success(nil))
  }

  func releaseResources() async {
    stopAudio()
    request?.endAudio()
    recognitionTask?.cancel()
    recognitionTask = nil
    request = nil
    provisional = nil
    level = nil
    resolve(.success(nil))
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
}

@available(macOS 26.0, *)
@MainActor
private final class ModernAppleSpeechSession: AppleSpeechSession {
  private let locale = Locale(identifier: "en-US")
  private let audioEngine = AVAudioEngine()
  private let microphoneUID: String?
  private let microphoneSelectionChanged: @MainActor (MicrophoneSelection) -> Void
  private var analyzer: SpeechAnalyzer?
  private var streamContinuation: AsyncStream<AnalyzerInput>.Continuation?
  private var analysisTask: Task<Void, Never>?
  private var resultsTask: Task<Void, Never>?
  private var converter: AVAudioConverter?
  private var outputFormat: AVAudioFormat?
  private var provisional: (@MainActor (String) -> Void)?
  private var level: (@MainActor (Float) -> Void)?
  private var finalSegments: [String] = []
  private var terminalError: Error?
  private var tapInstalled = false

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
    guard installedLocales.contains(where: {
      $0.identifier.lowercased() == locale.identifier.lowercased()
    }) else {
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

    var continuation: AsyncStream<AnalyzerInput>.Continuation?
    let stream = AsyncStream<AnalyzerInput>(bufferingPolicy: .bufferingNewest(8)) {
      continuation = $0
    }
    guard let continuation,
          let converter = AVAudioConverter(from: naturalFormat, to: format)
    else {
      throw DictationFailure.unavailable
    }
    self.analyzer = analyzer
    streamContinuation = continuation
    self.converter = converter
    outputFormat = format
    self.provisional = provisional
    self.level = level
    finalSegments = []
    terminalError = nil

    analysisTask = Task { [weak self] in
      do {
        try await analyzer.start(inputSequence: stream)
      } catch {
        self?.terminalError = error
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

    inputNode.installTap(onBus: 0, bufferSize: 1_024, format: naturalFormat) {
      [weak self] buffer, _ in
      guard let copied = try? AudioBufferTools.copy(buffer) else { return }
      let rms = AudioBufferTools.normalizedRMS(copied)
      Task { @MainActor [weak self] in
        guard let self, let converter = self.converter, let outputFormat = self.outputFormat else {
          return
        }
        do {
          let converted = try AudioBufferTools.convert(
            copied,
            using: converter,
            to: outputFormat
          )
          self.streamContinuation?.yield(AnalyzerInput(buffer: converted))
          self.level?(rms)
        } catch {
          self.terminalError = error
        }
      }
    }
    tapInstalled = true
    audioEngine.prepare()
    do {
      try audioEngine.start()
    } catch {
      stopAudio()
      continuation.finish()
      await analyzer.cancelAndFinishNow()
      throw error
    }
  }

  func finish() async throws -> String? {
    stopAudio()
    streamContinuation?.finish()
    if let analyzer {
      try await analyzer.finalizeAndFinishThroughEndOfInput()
    }
    await analysisTask?.value
    await resultsTask?.value
    if let terminalError { throw terminalError }
    let text = finalSegments.joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return text.nilIfEmpty
  }

  func cancel() async {
    stopAudio()
    streamContinuation?.finish()
    await analyzer?.cancelAndFinishNow()
    analysisTask?.cancel()
    resultsTask?.cancel()
  }

  func releaseResources() async {
    stopAudio()
    streamContinuation?.finish()
    await analyzer?.cancelAndFinishNow()
    analysisTask?.cancel()
    resultsTask?.cancel()
    analysisTask = nil
    resultsTask = nil
    streamContinuation = nil
    analyzer = nil
    converter = nil
    outputFormat = nil
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
}
