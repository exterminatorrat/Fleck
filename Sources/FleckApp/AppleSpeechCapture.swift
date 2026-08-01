@preconcurrency import AVFAudio
import CoreAudio
import Foundation
import FleckCore
@preconcurrency import Speech

enum DictationFailure: Error, Equatable {
  case unavailable
  case permissionDenied
  case noSpeech
  case transcriptionFailed
  case saveFailed
  case interrupted
}

extension DictationFailure: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .unavailable:
      "On-device speech recognition is unavailable."
    case .permissionDenied:
      "Microphone or Speech Recognition access is denied."
    case .noSpeech:
      "No speech was detected."
    case .transcriptionFailed:
      "Speech recognition could not transcribe the recording."
    case .saveFailed:
      "The dictation could not be saved."
    case .interrupted:
      "Dictation was interrupted."
    }
  }
}

enum MicrophoneSelection: Equatable, Sendable {
  case automatic
  case selected(uid: String)
  case fallbackToAutomatic(settingsCopy: String)
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

enum AppleSpeechAudioPump {
  static func drain(
    _ ingress: BoundedAudioIngress,
    consume: @escaping @Sendable (sending AVAudioPCMBuffer) async -> Void
  ) async throws {
    for try await buffer in ingress.buffers {
      await consume(buffer)
    }
  }
}

final class CoalescingLevelRelay: @unchecked Sendable {
  private let sink: @MainActor (Float) async -> Void
  private let lock = NSLock()
  private var latest: Float?
  private var deliveryPending = false

  init(sink: @escaping @MainActor (Float) async -> Void) {
    self.sink = sink
  }

  func submit(_ level: Float) {
    lock.lock()
    latest = level
    let shouldSchedule = !deliveryPending
    deliveryPending = true
    lock.unlock()

    guard shouldSchedule else { return }
    Task { @MainActor in
      await deliverLatest()
    }
  }

  @MainActor
  private func deliverLatest() async {
    let level = lock.withLock {
      defer { latest = nil }
      return latest
    }

    if let level {
      await sink(level)
    }

    let shouldSchedule = lock.withLock {
      let shouldSchedule = latest != nil
      if !shouldSchedule {
        deliveryPending = false
      }
      return shouldSchedule
    }

    guard shouldSchedule else { return }
    Task { @MainActor in
      await deliverLatest()
    }
  }
}

enum AudioTapIngress {
  static func makeHandler(for ingress: BoundedAudioIngress) -> AVAudioNodeTapBlock {
    { buffer, _ in
      do {
        _ = ingress.yield(try AudioBufferTools.copy(buffer))
      } catch {
        ingress.fail(DictationFailure.transcriptionFailed)
      }
    }
  }
}

protocol AppleSpeechSession: AnyObject, Sendable {
  var supportsOnDeviceRecognition: Bool { get async }

  func start(
    provisional: @escaping @MainActor @Sendable (String) -> Void,
    level: @escaping @MainActor @Sendable (Float) -> Void
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
    provisional: @escaping @MainActor @Sendable (String) -> Void,
    level: @escaping @MainActor @Sendable (Float) -> Void
  ) async throws {
    guard session == nil else { throw DictationFailure.unavailable }
    guard case .granted = await requestPermission() else {
      throw DictationFailure.permissionDenied
    }
    let session = try await makeSession()
    guard await session.supportsOnDeviceRecognition else {
      await session.releaseResources()
      throw DictationFailure.unavailable
    }
    self.session = session
    terminalFailure = nil
    terminalCommandIssued = false
    do {
      try await session.start(provisional: provisional, level: level)
      guard self.session === session, !terminalCommandIssued else {
        throw CancellationError()
      }
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

enum CoreAudioMicrophone {
  static func select(savedUID: String?) -> MicrophoneSelection {
    select(
      savedUID: savedUID,
      deviceIDForUID: { uid in
        guard let deviceID = deviceID(for: uid), hasInputChannels(deviceID) else { return nil }
        return deviceID
      },
      defaultInputDeviceID: defaultInputDeviceID
    )
  }

  static func select(
    savedUID: String?,
    deviceIDForUID: (String) -> AudioDeviceID?,
    defaultInputDeviceID: () -> AudioDeviceID?
  ) -> MicrophoneSelection {
    guard let savedUID else { return .automatic }
    if let savedDeviceID = deviceIDForUID(savedUID),
       savedDeviceID != kAudioObjectUnknown,
       let defaultDeviceID = defaultInputDeviceID(),
       defaultDeviceID != kAudioObjectUnknown,
       savedDeviceID == defaultDeviceID
    {
      return .selected(uid: savedUID)
    }
    return .fallbackToAutomatic(
      settingsCopy: "The saved microphone is unavailable. Using Automatic."
    )
  }

  private static func deviceID(for uid: String) -> AudioDeviceID? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var deviceUID = uid as CFString
    var deviceID = AudioDeviceID(kAudioObjectUnknown)
    var byteCount = UInt32(MemoryLayout<AudioDeviceID>.size)
    let status = withUnsafePointer(to: &deviceUID) { deviceUIDPointer in
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        UInt32(MemoryLayout<CFString>.size),
        deviceUIDPointer,
        &byteCount,
        &deviceID
      )
    }
    guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
    return deviceID
  }

  private static func defaultInputDeviceID() -> AudioDeviceID? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultInputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var deviceID = AudioDeviceID(kAudioObjectUnknown)
    var byteCount = UInt32(MemoryLayout<AudioDeviceID>.size)
    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &byteCount,
      &deviceID
    )
    guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
    return deviceID
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
}

actor LegacyAppleSpeechSession: AppleSpeechSession {
  private let makeAudioEngine: @Sendable () -> AVAudioEngine
  private let makeRecognizer: @Sendable () -> SFSpeechRecognizer?
  private let microphoneUID: String?
  private let microphoneSelectionChanged: @MainActor (MicrophoneSelection) -> Void
  private var recognizer: SFSpeechRecognizer?
  private var audioEngine: AVAudioEngine?
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private var ingress: BoundedAudioIngress?
  private var ingressWorker: Task<Void, Never>?
  private var provisional: (@MainActor @Sendable (String) -> Void)?
  private var levelRelay: CoalescingLevelRelay?
  private var terminal: Result<String?, Error>?
  private var finishContinuation: CheckedContinuation<String?, Error>?
  private var tapInstalled = false
  private var didEndAudio = false
  private var didCancelRecognition = false
  private var terminationRequested = false

  var supportsOnDeviceRecognition: Bool {
    prepareFrameworkObjects()
    return recognizer?.supportsOnDeviceRecognition == true
  }

  init(
    microphoneUID: String?,
    microphoneSelectionChanged: @escaping @MainActor (MicrophoneSelection) -> Void,
    makeAudioEngine: @escaping @Sendable () -> AVAudioEngine = { AVAudioEngine() },
    makeRecognizer: @escaping @Sendable () -> SFSpeechRecognizer? = {
      SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }
  ) {
    self.makeAudioEngine = makeAudioEngine
    self.makeRecognizer = makeRecognizer
    self.microphoneUID = microphoneUID
    self.microphoneSelectionChanged = microphoneSelectionChanged
  }

  func start(
    provisional: @escaping @MainActor @Sendable (String) -> Void,
    level: @escaping @MainActor @Sendable (Float) -> Void
  ) async throws {
    guard !terminationRequested else { throw CancellationError() }
    prepareFrameworkObjects()
    guard let audioEngine, let recognizer, recognizer.supportsOnDeviceRecognition else {
      throw DictationFailure.unavailable
    }
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.requiresOnDeviceRecognition = true
    request.shouldReportPartialResults = true
    request.taskHint = .dictation
    self.request = request
    self.provisional = provisional
    let levelRelay = CoalescingLevelRelay(sink: level)
    self.levelRelay = levelRelay
    terminal = nil
    didEndAudio = false
    didCancelRecognition = false

    let inputNode = audioEngine.inputNode
    await microphoneSelectionChanged(CoreAudioMicrophone.select(savedUID: microphoneUID))
    guard !terminationRequested else { throw CancellationError() }
    let inputFormat = inputNode.inputFormat(forBus: 0)
    let ingress = BoundedAudioIngress(capacity: 8)
    self.ingress = ingress
    ingressWorker = Task { [weak self] in
      do {
        try await AppleSpeechAudioPump.drain(ingress) { [weak self] buffer in
          await self?.consume(buffer, levelRelay: levelRelay)
        }
      } catch {
        await self?.resolve(.failure(error))
      }
    }
    inputNode.installTap(
      onBus: 0,
      bufferSize: 1_024,
      format: inputFormat,
      block: AudioTapIngress.makeHandler(for: ingress)
    )
    tapInstalled = true
    recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
      let text = result?.bestTranscription.formattedString
      let isFinal = result?.isFinal == true
      let errorCode = (error as NSError?)?.code
      Task { [weak self] in
        await self?.receive(text: text, isFinal: isFinal, errorCode: errorCode)
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
    terminationRequested = true
    stopAudio()
    ingress?.finish()
    await ingressWorker?.value
    cancelRecognitionOnce()
    resolve(.success(nil))
  }

  func releaseResources() async {
    terminationRequested = true
    stopAudio()
    ingress?.finish()
    await ingressWorker?.value
    if terminal == nil {
      cancelRecognitionOnce()
      resolve(.success(nil))
    }
    recognitionTask = nil
    request = nil
    recognizer = nil
    audioEngine = nil
    ingress = nil
    ingressWorker = nil
    provisional = nil
    levelRelay = nil
  }

  private func receive(text: String?, isFinal: Bool, errorCode: Int?) async {
    if let text {
      if isFinal {
        resolve(.success(text))
      } else {
        await provisional?(text)
      }
    }
    if let errorCode {
      if errorCode == 1_110 {
        resolve(.success(nil))
      } else {
        resolve(.failure(DictationFailure.transcriptionFailed))
      }
    }
  }

  private func consume(
    _ buffer: sending AVAudioPCMBuffer,
    levelRelay: CoalescingLevelRelay
  ) {
    request?.append(buffer)
    levelRelay.submit(AudioBufferTools.normalizedRMS(buffer))
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
    guard let audioEngine else { return }
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

  private func prepareFrameworkObjects() {
    guard !terminationRequested, audioEngine == nil else { return }
    audioEngine = makeAudioEngine()
    recognizer = makeRecognizer()
  }
}

@available(macOS 26.0, *)
private struct ModernAnalyzerInputSequence: AsyncSequence, @unchecked Sendable {
  typealias Element = AnalyzerInput

  struct AsyncIterator: AsyncIteratorProtocol {
    var buffers: AsyncThrowingStream<AVAudioPCMBuffer, Error>.Iterator
    let convert: @Sendable (AVAudioPCMBuffer) async throws -> AnalyzerInput

    mutating func next() async throws -> AnalyzerInput? {
      guard let buffer = try await buffers.next() else { return nil }
      return try await convert(buffer)
    }
  }

  let buffers: AsyncThrowingStream<AVAudioPCMBuffer, Error>
  let convert: @Sendable (AVAudioPCMBuffer) async throws -> AnalyzerInput

  func makeAsyncIterator() -> AsyncIterator {
    .init(buffers: buffers.makeAsyncIterator(), convert: convert)
  }
}

@available(macOS 26.0, *)
private actor ModernAppleSpeechSession: AppleSpeechSession {
  private let locale = Locale(identifier: "en-US")
  private let microphoneUID: String?
  private let microphoneSelectionChanged: @MainActor (MicrophoneSelection) -> Void
  private var audioEngine: AVAudioEngine?
  private var analyzer: SpeechAnalyzer?
  private var converter: AVAudioConverter?
  private var analyzerFormat: AVAudioFormat?
  private var ingress: BoundedAudioIngress?
  private var analysisTask: Task<Void, Never>?
  private var resultsTask: Task<Void, Never>?
  private var provisional: (@MainActor @Sendable (String) -> Void)?
  private var levelRelay: CoalescingLevelRelay?
  private var transcript = AppleSpeechTranscriptAssembler()
  private var terminalError: Error?
  private var tapInstalled = false
  private var didFinalize = false
  private var didCancelAnalyzer = false
  private var terminationRequested = false

  var supportsOnDeviceRecognition: Bool { true }

  init(
    microphoneUID: String?,
    microphoneSelectionChanged: @escaping @MainActor (MicrophoneSelection) -> Void
  ) {
    self.microphoneUID = microphoneUID
    self.microphoneSelectionChanged = microphoneSelectionChanged
  }

  func start(
    provisional: @escaping @MainActor @Sendable (String) -> Void,
    level: @escaping @MainActor @Sendable (Float) -> Void
  ) async throws {
    guard !terminationRequested else { throw CancellationError() }
    let audioEngine = AVAudioEngine()
    self.audioEngine = audioEngine
    let installedLocales = await DictationTranscriber.installedLocales
    guard !terminationRequested else { throw CancellationError() }
    guard AppleSpeechLocale.containsEquivalent(locale, in: installedLocales) else {
      throw DictationFailure.unavailable
    }

    let inputNode = audioEngine.inputNode
    await microphoneSelectionChanged(CoreAudioMicrophone.select(savedUID: microphoneUID))
    guard !terminationRequested else { throw CancellationError() }
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
    guard !terminationRequested else { throw CancellationError() }
    let analyzer = SpeechAnalyzer(
      modules: modules,
      options: .init(priority: .userInitiated, modelRetention: .whileInUse)
    )
    self.analyzer = analyzer
    try await analyzer.prepareToAnalyze(in: format)
    guard !terminationRequested else { throw CancellationError() }

    guard let converter = AVAudioConverter(from: naturalFormat, to: format) else {
      throw DictationFailure.unavailable
    }
    let ingress = BoundedAudioIngress(capacity: 8)
    let levelRelay = CoalescingLevelRelay(sink: level)
    self.converter = converter
    analyzerFormat = format
    self.ingress = ingress
    self.provisional = provisional
    self.levelRelay = levelRelay
    transcript = AppleSpeechTranscriptAssembler()
    terminalError = nil
    didFinalize = false
    didCancelAnalyzer = false
    let inputs = ModernAnalyzerInputSequence(
      buffers: ingress.buffers,
      convert: { [weak self] buffer in
        guard let self else { throw CancellationError() }
        return try await self.analyzerInput(for: buffer)
      }
    )

    analysisTask = Task { [weak self] in
      do {
        try await analyzer.start(inputSequence: inputs)
      } catch {
        await self?.fail(error)
      }
    }
    resultsTask = Task { [weak self] in
      do {
        for try await result in transcriber.results {
          let text = String(result.text.characters)
          await self?.receive(text: text, isFinal: result.isFinal)
        }
      } catch {
        await self?.fail(error)
      }
    }

    inputNode.installTap(
      onBus: 0,
      bufferSize: 1_024,
      format: naturalFormat,
      block: AudioTapIngress.makeHandler(for: ingress)
    )
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
    return transcript.displayText().nilIfEmpty
  }

  func cancel() async {
    terminationRequested = true
    stopAudio()
    ingress?.finish()
    await cancelAnalyzerOnce()
    analysisTask?.cancel()
    resultsTask?.cancel()
    await analysisTask?.value
    await resultsTask?.value
  }

  func releaseResources() async {
    terminationRequested = true
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
    audioEngine = nil
    converter = nil
    analyzerFormat = nil
    provisional = nil
    levelRelay = nil
    transcript = AppleSpeechTranscriptAssembler()
    terminalError = nil
  }

  private func analyzerInput(for buffer: AVAudioPCMBuffer) throws -> AnalyzerInput {
    guard let converter, let analyzerFormat, let levelRelay else {
      throw CancellationError()
    }
    let converted = try AudioBufferTools.convert(
      buffer,
      using: converter,
      to: analyzerFormat
    )
    levelRelay.submit(AudioBufferTools.normalizedRMS(buffer))
    return AnalyzerInput(buffer: converted)
  }

  private func receive(text: String, isFinal: Bool) async {
    if isFinal {
      transcript.appendFinal(text)
      await provisional?(transcript.displayText())
    } else {
      await provisional?(transcript.displayText(provisional: text))
    }
  }

  private func fail(_ error: Error) {
    terminalError = error
    stopAudio()
  }

  private func stopAudio() {
    guard let audioEngine else { return }
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

struct AppleSpeechTranscriptAssembler {
  private var finalizedWords: [String] = []

  mutating func appendFinal(_ text: String) {
    finalizedWords = Self.merge(finalizedWords, with: Self.words(in: text))
  }

  func displayText(provisional: String = "") -> String {
    Self.merge(finalizedWords, with: Self.words(in: provisional))
      .joined(separator: " ")
  }

  private static func words(in text: String) -> [String] {
    text.split(whereSeparator: \.isWhitespace).map(String.init)
  }

  private static func merge(_ first: [String], with second: [String]) -> [String] {
    guard !first.isEmpty else { return second }
    guard !second.isEmpty else { return first }
    let maximumOverlap = min(8, first.count, second.count)
    if maximumOverlap >= 2 {
      for count in stride(from: maximumOverlap, through: 2, by: -1) {
        let suffix = first.suffix(count)
        let prefix = second.prefix(count)
        guard zip(suffix, prefix).allSatisfy({
          $0.0.caseInsensitiveCompare($0.1) == .orderedSame
        }) else { continue }
        return first + second.dropFirst(count)
      }
    }
    return first + second
  }
}
