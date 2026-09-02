import Foundation

#if os(macOS)
import Darwin
#endif

struct GemmaCleanupProcessTransport: GemmaCleanupTransport, Sendable {
  struct Timing: Sendable {
    let gracefulTimeoutNanoseconds: UInt64
    let escalationGraceNanoseconds: UInt64
    let forcedDrainTimeoutNanoseconds: UInt64
    let pollIntervalNanoseconds: UInt64

    init(
      gracefulTimeoutNanoseconds: UInt64 = 5_000_000_000,
      escalationGraceNanoseconds: UInt64 = 250_000_000,
      forcedDrainTimeoutNanoseconds: UInt64 = 5_000_000_000,
      pollIntervalNanoseconds: UInt64 = 5_000_000
    ) {
      self.gracefulTimeoutNanoseconds = gracefulTimeoutNanoseconds
      self.escalationGraceNanoseconds = escalationGraceNanoseconds
      self.forcedDrainTimeoutNanoseconds = forcedDrainTimeoutNanoseconds
      self.pollIntervalNanoseconds = pollIntervalNanoseconds
    }

    static let live = Self()

    static let short = Self(
      gracefulTimeoutNanoseconds: 150_000_000,
      escalationGraceNanoseconds: 20_000_000,
      forcedDrainTimeoutNanoseconds: 1_000_000_000,
      pollIntervalNanoseconds: 2_000_000
    )
  }

  static let defaultSandboxExecutableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
  static let defaultSandboxProfile = "(version 1)(allow default)(deny network*)"

  private let helperExecutableURL: URL
  private let modelDirectoryURL: URL
  private let sandboxExecutableURL: URL?
  private let sandboxProfile: String
  private let timing: Timing
  private let beforeInitialWrite: @Sendable () -> Void
  private let afterInitialWrite: @Sendable () -> Void
  private let afterInputClose: @Sendable () -> Void
  private let prepareInputBeforeLaunch: @Sendable (FileHandle) throws -> Void
  private let configureNoSIGPIPE: @Sendable (Int32) -> Int32

  init(
    helperExecutableURL: URL,
    modelDirectoryURL: URL,
    sandboxExecutableURL: URL? = Self.defaultSandboxExecutableURL,
    sandboxProfile: String = Self.defaultSandboxProfile,
    timing: Timing = .live,
    beforeInitialWrite: @escaping @Sendable () -> Void = {},
    afterInitialWrite: @escaping @Sendable () -> Void = {},
    afterInputClose: @escaping @Sendable () -> Void = {},
    prepareInputBeforeLaunch: @escaping @Sendable (FileHandle) throws -> Void = { _ in },
    configureNoSIGPIPE: @escaping @Sendable (Int32) -> Int32 = { descriptor in
#if os(macOS)
      fcntl(descriptor, F_SETNOSIGPIPE, 1)
#else
      -1
#endif
    }
  ) {
    self.helperExecutableURL = helperExecutableURL
    self.modelDirectoryURL = modelDirectoryURL
    self.sandboxExecutableURL = sandboxExecutableURL
    self.sandboxProfile = sandboxProfile
    self.timing = timing
    self.beforeInitialWrite = beforeInitialWrite
    self.afterInitialWrite = afterInitialWrite
    self.afterInputClose = afterInputClose
    self.prepareInputBeforeLaunch = prepareInputBeforeLaunch
    self.configureNoSIGPIPE = configureNoSIGPIPE
  }

  func start(_ request: GemmaCleanupHelperRequest) throws -> any GemmaCleanupTransportSession {
    guard isCanonicalExecutableFile(helperExecutableURL),
          isCanonicalDirectory(modelDirectoryURL),
          sandboxExecutableURL.map(isCanonicalExecutableFile) ?? true
    else {
      throw GemmaCleanupProcessTransportError.invalidLaunchURL
    }

    var requestData = try JSONEncoder().encode(request)
    guard requestData.count <= GemmaCleanupProcessTransportSession.maxLineBytes else {
      throw GemmaCleanupProcessTransportError.inputTooLarge
    }
    requestData.append(0x0A)

    let process = Process()
    let input = Pipe()
    let output = Pipe()
    let standardError = Pipe()
    process.standardInput = input
    process.standardOutput = output
    process.standardError = standardError

    if let sandboxExecutableURL {
      process.executableURL = sandboxExecutableURL
      process.arguments = [
        "-p",
        sandboxProfile,
        helperExecutableURL.path,
        "--model-directory",
        modelDirectoryURL.path,
      ]
    } else {
      process.executableURL = helperExecutableURL
      process.arguments = ["--model-directory", modelDirectoryURL.path]
    }

    let session: GemmaCleanupProcessTransportSession
    do {
      session = try GemmaCleanupProcessTransportSession(
        process: process,
        input: input.fileHandleForWriting,
        output: output.fileHandleForReading,
        error: standardError.fileHandleForReading,
        request: request,
        timing: timing,
        afterInputClose: afterInputClose,
        configureNoSIGPIPE: configureNoSIGPIPE
      )
    } catch {
      try? input.fileHandleForWriting.close()
      try? output.fileHandleForReading.close()
      try? standardError.fileHandleForReading.close()
      throw error
    }
    process.terminationHandler = { [weak session] process in
      session?.processDidExit(process)
    }

    do {
      try prepareInputBeforeLaunch(input.fileHandleForWriting)
    } catch {
      try? input.fileHandleForWriting.close()
      try? output.fileHandleForReading.close()
      try? standardError.fileHandleForReading.close()
      throw error
    }

    do {
      try process.run()
    } catch {
      try? input.fileHandleForWriting.close()
      try? output.fileHandleForReading.close()
      try? standardError.fileHandleForReading.close()
      throw error
    }

    session.startReaders()
    session.enqueueInitial(
      requestData,
      beforeWrite: beforeInitialWrite,
      afterWrite: afterInitialWrite
    )
    return session
  }

  private func isCanonicalExecutableFile(_ url: URL) -> Bool {
    guard isCanonicalAbsoluteFileURL(url),
          fileType(at: url.path) == S_IFREG,
          FileManager.default.isExecutableFile(atPath: url.path)
    else { return false }
    return true
  }

  private func isCanonicalDirectory(_ url: URL) -> Bool {
    isCanonicalAbsoluteFileURL(url) && fileType(at: url.path) == S_IFDIR
  }

  private func isCanonicalAbsoluteFileURL(_ url: URL) -> Bool {
    guard url.isFileURL,
          url.path.hasPrefix("/"),
          url.path == url.standardizedFileURL.path
    else { return false }
    return url.resolvingSymlinksInPath().standardizedFileURL.path == url.path
  }

  private func fileType(at path: String) -> mode_t? {
    var info = stat()
    guard lstat(path, &info) == 0 else { return nil }
    return info.st_mode & S_IFMT
  }
}

private enum GemmaCleanupProcessTransportError: Error {
  case invalidLaunchURL
  case inputTooLarge
  case protocolViolation
  case earlyEOF
  case processExited
  case brokenPipe
  case forced
  case cannotConfigureNoSIGPIPE
}

private final class GemmaCleanupProcessTransportSession:
  GemmaCleanupTransportSession,
  @unchecked Sendable
{
  static let maxLineBytes = 64 * 1024
  private static let maxStderrBytes = 64 * 1024
  private static let maxRawTextBytes = 16 * 1024

  var events: AsyncThrowingStream<Data, Error> { eventStream }

  let terminationExpectation: GemmaCleanupTerminationExpectation

  private let process: Process
  private let input: FileHandle
  private let output: FileHandle
  private let error: FileHandle
  private let timing: GemmaCleanupProcessTransport.Timing
  private let afterInputClose: @Sendable () -> Void
  private let eventStream: AsyncThrowingStream<Data, Error>
  private let eventContinuation: AsyncThrowingStream<Data, Error>.Continuation
  private let lock = NSLock()
  private let writeLock = NSLock()
  private let writeQueue = DispatchQueue(label: "com.fleck.gemma-cleanup.write")

  private var escalationTask: Task<Void, Never>?
  private var forcedTask: Task<GemmaCleanupTransportTerminationDisposition, Never>?
  private var gracefulTasks: [Bool: Task<GemmaCleanupTransportTerminationDisposition, Never>] = [:]

  private var readySeen = false
  private var startedSeen = false
  private var terminalSeen = false
  private var publicFinished = false
  private var cancellationSent = false
  private var cancellationWritten = false
  private var cancellationAcknowledged = false
  private var shutdownSent = false
  private var shutdownWritten = false
  private var shutdownAcknowledged = false
  private var protocolFailed = false
  private var forceRequested = false
  private var stdinClosed = false
  private var stdoutEOF = false
  private var stderrEOF = false
  private var processExited = false
  private var terminationStatus: Int32?
  private var terminationReason: Process.TerminationReason?
  private var sigtermSent = false
  private var sigkillSent = false

  private func withStateLock<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  init(
    process: Process,
    input: FileHandle,
    output: FileHandle,
    error: FileHandle,
    request: GemmaCleanupHelperRequest,
    timing: GemmaCleanupProcessTransport.Timing,
    afterInputClose: @escaping @Sendable () -> Void,
    configureNoSIGPIPE: @Sendable (Int32) -> Int32
  ) throws {
    self.process = process
    self.input = input
    self.output = output
    self.error = error
    self.timing = timing
    self.afterInputClose = afterInputClose
    guard configureNoSIGPIPE(input.fileDescriptor) == 0 else {
      throw GemmaCleanupProcessTransportError.cannotConfigureNoSIGPIPE
    }
    let pair = AsyncThrowingStream<Data, Error>.makeStream()
    self.eventStream = pair.stream
    self.eventContinuation = pair.continuation
    self.terminationExpectation = GemmaCleanupTerminationExpectation(
      cleanupRequestID: request.requestID,
      cancellationCommandID: "cancel-\(request.requestID)",
      shutdownCommandID: "shutdown-\(request.requestID)"
    )
  }

  func startReaders() {
    let output = self.output
    let error = self.error
    DispatchQueue.global(qos: .utility).async { [weak self, output] in
      self?.readStdout(from: output)
    }
    DispatchQueue.global(qos: .utility).async { [weak self, error] in
      self?.readStderr(from: error)
    }
  }

  func enqueueInitial(
    _ data: Data,
    beforeWrite: @escaping @Sendable () -> Void,
    afterWrite: @escaping @Sendable () -> Void
  ) {
    writeQueue.async { [self] in
      do {
        beforeWrite()
        try write(data)
        afterWrite()
      } catch {
        initialWriteFailed()
      }
    }
  }

  private func initialWriteFailed() {
    fail(.brokenPipe)
  }

  func requestCancellation() {
    let commandID = terminationExpectation.cancellationCommandID
    let shouldSend: Bool
    lock.lock()
    shouldSend = !cancellationSent
    if shouldSend {
      cancellationSent = true
    }
    lock.unlock()
    guard shouldSend, let commandID else { return }

    let command = GemmaCleanupControlRequest.cancel(
      requestID: commandID,
      targetRequestID: terminationExpectation.cleanupRequestID
    )
    enqueueControl(command)
  }

  func forceTerminate() {
    let shouldFinishPublic: Bool
    let shouldCloseInput: Bool
    let processID: Int32?
    let shouldSendSIGTERM: Bool

    lock.lock()
    if forceRequested {
      shouldFinishPublic = false
      shouldCloseInput = false
      processID = nil
      shouldSendSIGTERM = false
    } else {
      forceRequested = true
      shouldFinishPublic = !publicFinished
      shouldCloseInput = !stdinClosed
      stdinClosed = true
      let running = process.isRunning
      shouldSendSIGTERM = !sigtermSent
      sigtermSent = true
      processID = running ? process.processIdentifier : nil
    }
    lock.unlock()

    if shouldFinishPublic {
      finishPublic(throwing: GemmaCleanupProcessTransportError.forced)
    }
    if shouldSendSIGTERM, let processID {
      sendSignal(SIGTERM, to: processID)
    }
    scheduleEscalation()
    if shouldCloseInput {
      enqueueInputClose()
    }
    _ = makeForcedTask()
  }

  func terminationAcknowledgement(
    for phase: GemmaCleanupTerminationPhase
  ) async -> GemmaCleanupTransportTerminationDisposition {
    switch phase {
    case .forced:
      forceTerminate()
      return await makeForcedTask().value
    case .graceful(let requireCancellationAcknowledgement):
      if let task = withStateLock({ gracefulTasks[requireCancellationAcknowledgement] }) {
        return await task.value
      }
      let task: Task<GemmaCleanupTransportTerminationDisposition, Never> = Task { [weak self] in
        guard let self else {
          return GemmaCleanupTransportTerminationDisposition.failed(.unverifiable)
        }
        return await self.runGraceful(
          requireCancellationAcknowledgement: requireCancellationAcknowledgement
        )
      }
      let selectedTask = withStateLock {
        if let existing = gracefulTasks[requireCancellationAcknowledgement] {
          return existing
        }
        gracefulTasks[requireCancellationAcknowledgement] = task
        return task
      }
      return await selectedTask.value
    }
  }

  func processDidExit(_ process: Process) {
    let shouldFailPublic: Bool
    lock.lock()
    processExited = true
    terminationStatus = process.terminationStatus
    terminationReason = process.terminationReason
    shouldFailPublic = !publicFinished && !terminalSeen
    if process.terminationStatus != 0 || (!terminalSeen && !forceRequested) {
      protocolFailed = true
    }
    lock.unlock()

    if shouldFailPublic {
      finishPublic(throwing: GemmaCleanupProcessTransportError.processExited)
    }
    if process.terminationStatus != 0 || shouldFailPublic {
      forceTerminate()
    }
    cancelEscalationIfDrained()
  }

  private func readStdout(from handle: FileHandle) {
    var line = Data()
    var lineTooLarge = false

    while true {
      let chunk = handle.availableData
      guard !chunk.isEmpty else { break }
      for byte in chunk {
        if byte == 0x0A {
          if lineTooLarge {
            fail(.protocolViolation)
          } else {
            handleStdoutLine(line)
          }
          line.removeAll(keepingCapacity: true)
          lineTooLarge = false
        } else if !lineTooLarge {
          if line.count >= Self.maxLineBytes {
            lineTooLarge = true
            fail(.protocolViolation)
          } else {
            line.append(byte)
          }
        }
      }
    }

    if lineTooLarge || !line.isEmpty {
      fail(.earlyEOF)
    }
    let (missingTerminal, missingShutdown) = withStateLock {
      stdoutEOF = true
      return (!terminalSeen, terminalSeen && !shutdownAcknowledged)
    }
    cancelEscalationIfDrained()
    if missingTerminal || missingShutdown {
      fail(.earlyEOF)
    }
  }

  private func readStderr(from handle: FileHandle) {
    var lineBytes = 0
    var totalBytes = 0
    var overflow = false

    while true {
      let chunk = handle.availableData
      guard !chunk.isEmpty else { break }
      for byte in chunk {
        totalBytes += 1
        lineBytes = byte == 0x0A ? 0 : lineBytes + 1
        if !overflow && (lineBytes > Self.maxLineBytes || totalBytes > Self.maxStderrBytes) {
          overflow = true
          fail(.protocolViolation)
        }
      }
    }
    withStateLock {
      stderrEOF = true
    }
    cancelEscalationIfDrained()
  }

  private func handleStdoutLine(_ data: Data) {
    guard let event = GemmaCleanupProcessWire.decodeEvent(
      data,
      requestID: terminationExpectation.cleanupRequestID,
      cancellationCommandID: terminationExpectation.cancellationCommandID,
      shutdownCommandID: terminationExpectation.shutdownCommandID
    ) else {
      fail(.protocolViolation)
      return
    }

    let validatesControlWrite: Bool
    switch event {
    case .cancelAcknowledged, .shutdownAcknowledged:
      validatesControlWrite = true
    default:
      validatesControlWrite = false
    }
    if validatesControlWrite {
      writeLock.lock()
    }

    var publicData: Data?
    var finishAfterYield = false
    var invalid = false

    lock.lock()
    if forceRequested {
      lock.unlock()
      if validatesControlWrite {
        writeLock.unlock()
      }
      fail(.forced)
      return
    }
    switch event {
    case .ready:
      guard !readySeen, !startedSeen, !terminalSeen else {
        invalid = true
        break
      }
      readySeen = true
      publicData = data
    case .started:
      guard readySeen, !startedSeen, !terminalSeen else {
        invalid = true
        break
      }
      startedSeen = true
      publicData = data
    case .completed, .failed, .cancelled:
      guard readySeen, startedSeen, !terminalSeen else {
        invalid = true
        break
      }
      terminalSeen = true
      publicData = data
      finishAfterYield = true
    case .cancelAcknowledged:
      guard terminalSeen, cancellationWritten, !cancellationAcknowledged else {
        invalid = true
        break
      }
      cancellationAcknowledged = true
    case .shutdownAcknowledged:
      guard terminalSeen, shutdownWritten, !shutdownAcknowledged else {
        invalid = true
        break
      }
      shutdownAcknowledged = true
    }
    lock.unlock()
    if validatesControlWrite {
      writeLock.unlock()
    }

    guard !invalid else {
      fail(.protocolViolation)
      return
    }
    if let publicData {
      lock.lock()
      let suppress = forceRequested
      lock.unlock()
      guard !suppress else {
        fail(.forced)
        return
      }
      eventContinuation.yield(publicData)
      if finishAfterYield {
        finishPublic()
      }
    }
  }

  private func runGraceful(
    requireCancellationAcknowledgement: Bool
  ) async -> GemmaCleanupTransportTerminationDisposition {
    let invalidInitialState = withStateLock {
      !terminalSeen || forceRequested || protocolFailed
        || (requireCancellationAcknowledgement && !cancellationSent)
        || (!requireCancellationAcknowledgement && cancellationSent)
    }
    guard !invalidInitialState else {
      return await failGracefullyUnverifiable()
    }

    let commandID = terminationExpectation.shutdownCommandID
    let shouldSendShutdown = withStateLock {
      let shouldSend = !shutdownSent
      if shouldSend { shutdownSent = true }
      return shouldSend
    }

    if shouldSendShutdown {
      enqueueControl(.shutdown(requestID: commandID))
    }

    let completed = await waitUntil(timeout: timing.gracefulTimeoutNanoseconds) {
      self.gracefulProof(
        requireCancellationAcknowledgement: requireCancellationAcknowledgement
      ) != nil
      || self.shouldStopGracefulWait()
    }
    if let proof = gracefulProof(
      requireCancellationAcknowledgement: requireCancellationAcknowledgement
    ), completed {
      return .verified(proof)
    }

    return await failGracefullyUnverifiable()
  }

  private func failGracefullyUnverifiable()
    async -> GemmaCleanupTransportTerminationDisposition
  {
    let fullyExitedAndDrained = withStateLock {
      processExited && stdoutEOF && stderrEOF
    }
    guard !fullyExitedAndDrained else { return .failed(.unverifiable) }

    forceTerminate()
    _ = await makeForcedTask().value
    return .failed(.unverifiable)
  }

  private func gracefulProof(
    requireCancellationAcknowledgement: Bool
  ) -> GemmaCleanupTerminationProof? {
    lock.lock()
    defer { lock.unlock() }
    guard readySeen, startedSeen, terminalSeen,
          shutdownAcknowledged,
          shutdownWritten,
          processExited,
          terminationStatus == 0,
          terminationReason == .exit,
          stdoutEOF,
          stderrEOF,
          !protocolFailed,
          !forceRequested
    else { return nil }
    if requireCancellationAcknowledgement {
      guard cancellationSent, cancellationWritten, cancellationAcknowledged else {
        return nil
      }
    } else {
      guard !cancellationSent, !cancellationAcknowledged else { return nil }
    }
    return GemmaCleanupTerminationProof(
      phase: .graceful(
        requireCancellationAcknowledgement: requireCancellationAcknowledgement
      ),
      cleanupRequestID: terminationExpectation.cleanupRequestID,
      cancellationCommandID: cancellationAcknowledged
        ? terminationExpectation.cancellationCommandID
        : nil,
      cancellationTargetRequestID: cancellationAcknowledged
        ? terminationExpectation.cleanupRequestID
        : nil,
      shutdownCommandID: terminationExpectation.shutdownCommandID,
      cooperative: true,
      processTerminationMayBeRequired: false,
      processExited: true,
      outputDrained: true
    )
  }

  private func shouldStopGracefulWait() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return forceRequested || protocolFailed || (processExited && stdoutEOF && stderrEOF)
  }

  private func makeForcedTask() -> Task<GemmaCleanupTransportTerminationDisposition, Never> {
    lock.lock()
    if let forcedTask {
      lock.unlock()
      return forcedTask
    }
    let task: Task<GemmaCleanupTransportTerminationDisposition, Never> = Task.detached { [self] in
      return await self.waitForForcedDisposition()
    }
    forcedTask = task
    lock.unlock()
    return task
  }

  private func waitForForcedDisposition() async -> GemmaCleanupTransportTerminationDisposition {
    defer {
      withStateLock {
        forcedTask = nil
      }
    }
    let completed = await waitUntil(timeout: timing.forcedDrainTimeoutNanoseconds) {
      self.forcedDrainComplete()
    }
    guard completed else { return .failed(.unverifiable) }
    let (invalidNonzeroExit, requestID) = withStateLock {
      (
        terminationReason == .exit && terminationStatus != 0,
        terminationExpectation.cleanupRequestID
      )
    }
    guard !invalidNonzeroExit else { return .failed(.unverifiable) }
    return .verified(
      GemmaCleanupTerminationProof(
        phase: .forced,
        cleanupRequestID: requestID,
        cancellationCommandID: nil,
        cancellationTargetRequestID: nil,
        shutdownCommandID: nil,
        cooperative: false,
        processTerminationMayBeRequired: true,
        processExited: true,
        outputDrained: true
      )
    )
  }

  private func forcedDrainComplete() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return processExited && stdoutEOF && stderrEOF
  }

  private func waitUntil(
    timeout: UInt64,
    condition: () -> Bool
  ) async -> Bool {
    let start = DispatchTime.now().uptimeNanoseconds
    while true {
      if condition() { return true }
      let elapsed = DispatchTime.now().uptimeNanoseconds - start
      if elapsed >= timeout { return false }
      let remaining = timeout - elapsed
      let sleepFor = min(remaining, timing.pollIntervalNanoseconds)
      do {
        try await Task.sleep(nanoseconds: sleepFor)
      } catch {
        return false
      }
    }
  }

  private func scheduleEscalation() {
    lock.lock()
    guard escalationTask == nil else {
      lock.unlock()
      return
    }
    let task = Task.detached { [weak self] in
      guard let self else { return }
      do {
        try await Task.sleep(nanoseconds: self.timing.escalationGraceNanoseconds)
      } catch {
        return
      }
      self.sendSIGKILLIfRunning()
    }
    escalationTask = task
    lock.unlock()
  }

  private func sendSIGKILLIfRunning() {
    let processID: Int32?
    lock.lock()
    guard forceRequested, !sigkillSent, process.isRunning else {
      lock.unlock()
      return
    }
    sigkillSent = true
    processID = process.processIdentifier
    lock.unlock()
    if let processID {
      sendSignal(SIGKILL, to: processID)
    }
  }

  private func cancelEscalationIfDrained() {
    let task: Task<Void, Never>?
    lock.lock()
    if processExited && stdoutEOF && stderrEOF {
      task = escalationTask
      escalationTask = nil
    } else {
      task = nil
    }
    lock.unlock()
    task?.cancel()
  }

  private func sendControl(_ command: GemmaCleanupControlRequest) throws {
    var data = try JSONEncoder().encode(command)
    guard data.count <= Self.maxLineBytes - 1 else {
      throw GemmaCleanupProcessTransportError.inputTooLarge
    }
    data.append(0x0A)
    try write(data) {
      self.withStateLock {
        switch command.operation {
        case "cancel":
          self.cancellationWritten = true
        case "shutdown":
          self.shutdownWritten = true
        default:
          break
        }
      }
    }
  }

  private func enqueueControl(_ command: GemmaCleanupControlRequest) {
    writeQueue.async { [weak self] in
      guard let self else { return }
      do {
        try self.sendControl(command)
      } catch {
        self.fail(.brokenPipe)
      }
    }
  }

  private func enqueueInputClose() {
    writeQueue.async { [weak self] in
      guard let self else { return }
      try? self.input.close()
      self.afterInputClose()
    }
  }

  private func write(_ data: Data, afterWrite: (() -> Void)? = nil) throws {
    writeLock.lock()
    defer { writeLock.unlock() }
    lock.lock()
    let closed = stdinClosed
    lock.unlock()
    guard !closed else { throw GemmaCleanupProcessTransportError.brokenPipe }
    try input.write(contentsOf: data)
    afterWrite?()
  }

  private func fail(_ error: GemmaCleanupProcessTransportError) {
    lock.lock()
    protocolFailed = true
    lock.unlock()
    finishPublic(throwing: error)
    forceTerminate()
  }

  private func finishPublic(throwing error: Error? = nil) {
    lock.lock()
    guard !publicFinished else {
      lock.unlock()
      return
    }
    publicFinished = true
    lock.unlock()
    if let error {
      eventContinuation.finish(throwing: error)
    } else {
      eventContinuation.finish()
    }
  }

  private func sendSignal(_ signal: Int32, to processID: Int32) {
    #if os(macOS)
    _ = Darwin.kill(processID, signal)
    #endif
  }
}

private struct GemmaCleanupControlRequest: Encodable {
  let schemaVersion = 1
  let operation: String
  let requestID: String
  let targetRequestID: String?

  static func cancel(requestID: String, targetRequestID: String) -> Self {
    Self(
      operation: "cancel",
      requestID: requestID,
      targetRequestID: targetRequestID
    )
  }

  static func shutdown(requestID: String) -> Self {
    Self(operation: "shutdown", requestID: requestID, targetRequestID: nil)
  }

  enum CodingKeys: String, CodingKey {
    case schemaVersion
    case operation
    case requestID
    case targetRequestID
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(schemaVersion, forKey: .schemaVersion)
    try container.encode(operation, forKey: .operation)
    try container.encode(requestID, forKey: .requestID)
    if let targetRequestID {
      try container.encode(targetRequestID, forKey: .targetRequestID)
    }
  }
}

private enum GemmaCleanupProcessWire {
  enum Event {
    case ready
    case started
    case completed
    case failed
    case cancelled
    case cancelAcknowledged
    case shutdownAcknowledged
  }

  static func decodeEvent(
    _ data: Data,
    requestID: String,
    cancellationCommandID: String?,
    shutdownCommandID: String
  ) -> Event? {
    guard data.count <= GemmaCleanupProcessTransportSession.maxLineBytes else { return nil }
    var scanner = JSONDuplicateKeyScanner(data: data)
    guard scanner.validate(),
          let object = try? JSONSerialization.jsonObject(with: data),
          let dictionary = object as? [String: Any],
          isSchemaVersionOne(dictionary["schemaVersion"]),
          let kind = dictionary["kind"] as? String
    else { return nil }

    let keys = Set(dictionary.keys)
    switch kind {
    case "ready":
      return keys == ["schemaVersion", "kind"] ? .ready : nil
    case "started":
      guard keys == ["schemaVersion", "kind", "requestID"],
            dictionary["requestID"] as? String == requestID else { return nil }
      return .started
    case "completed":
      guard keys == ["schemaVersion", "kind", "requestID", "rawText"],
            dictionary["requestID"] as? String == requestID,
            let rawText = dictionary["rawText"] as? String,
            Data(rawText.utf8).count <= 16 * 1024 else { return nil }
      return .completed
    case "failed":
      guard keys == ["schemaVersion", "kind", "requestID", "errorCode"],
            dictionary["requestID"] as? String == requestID,
            let errorCode = dictionary["errorCode"] as? String,
            ["deadline-exceeded", "generation-failed", "output-too-large"].contains(errorCode)
      else { return nil }
      return .failed
    case "cancelled":
      guard keys == [
        "schemaVersion", "kind", "requestID", "errorCode", "cooperative",
        "processTerminationMayBeRequired",
      ],
        dictionary["requestID"] as? String == requestID,
        dictionary["errorCode"] as? String == "cancelled",
        isBoolean(dictionary["cooperative"]),
        isBoolean(dictionary["processTerminationMayBeRequired"]),
        (dictionary["cooperative"] as? NSNumber)?.boolValue == true,
        (dictionary["processTerminationMayBeRequired"] as? NSNumber)?.boolValue == false
      else { return nil }
      return .cancelled
    case "cancel-acknowledged":
      guard keys == [
        "schemaVersion", "kind", "requestID", "targetRequestID", "cooperative",
        "processTerminationMayBeRequired",
      ],
        let cancellationCommandID,
        dictionary["requestID"] as? String == cancellationCommandID,
        dictionary["targetRequestID"] as? String == requestID,
        isBoolean(dictionary["cooperative"]),
        isBoolean(dictionary["processTerminationMayBeRequired"]),
        (dictionary["cooperative"] as? NSNumber)?.boolValue == true,
        (dictionary["processTerminationMayBeRequired"] as? NSNumber)?.boolValue == false
      else { return nil }
      return .cancelAcknowledged
    case "shutdown-acknowledged":
      guard keys == [
        "schemaVersion", "kind", "requestID", "cooperative",
        "processTerminationMayBeRequired",
      ],
        dictionary["requestID"] as? String == shutdownCommandID,
        isBoolean(dictionary["cooperative"]),
        isBoolean(dictionary["processTerminationMayBeRequired"]),
        (dictionary["cooperative"] as? NSNumber)?.boolValue == true,
        (dictionary["processTerminationMayBeRequired"] as? NSNumber)?.boolValue == false
      else { return nil }
      return .shutdownAcknowledged
    default:
      return nil
    }
  }

  private static func isSchemaVersionOne(_ value: Any?) -> Bool {
    guard let number = value as? NSNumber else { return false }
    let type = String(cString: number.objCType)
    return type != "c" && type != "d" && type != "f" && number.intValue == 1
  }

  private static func isBoolean(_ value: Any?) -> Bool {
    guard let number = value as? NSNumber else { return false }
    return String(cString: number.objCType) == "c"
  }
}

private struct JSONDuplicateKeyScanner {
  private let bytes: [UInt8]
  private var index = 0

  init(data: Data) {
    self.bytes = Array(data)
  }

  mutating func validate() -> Bool {
    skipWhitespace()
    guard readValue() else { return false }
    skipWhitespace()
    return index == bytes.count
  }

  private mutating func readValue() -> Bool {
    guard let byte = current else { return false }
    switch byte {
    case 0x7B: return readObject()
    case 0x5B: return readArray()
    case 0x22: return readString() != nil
    case 0x74: return readLiteral(Array("true".utf8))
    case 0x66: return readLiteral(Array("false".utf8))
    case 0x6E: return readLiteral(Array("null".utf8))
    case 0x2D, 0x30...0x39:
      readNumber()
      return true
    default: return false
    }
  }

  private mutating func readObject() -> Bool {
    guard consume(0x7B) else { return false }
    skipWhitespace()
    var keys = Set<String>()
    if consume(0x7D) { return true }
    while true {
      skipWhitespace()
      guard let key = readString(), keys.insert(key).inserted else { return false }
      skipWhitespace()
      guard consume(0x3A) else { return false }
      skipWhitespace()
      guard readValue() else { return false }
      skipWhitespace()
      if consume(0x7D) { return true }
      guard consume(0x2C) else { return false }
    }
  }

  private mutating func readArray() -> Bool {
    guard consume(0x5B) else { return false }
    skipWhitespace()
    if consume(0x5D) { return true }
    while true {
      skipWhitespace()
      guard readValue() else { return false }
      skipWhitespace()
      if consume(0x5D) { return true }
      guard consume(0x2C) else { return false }
    }
  }

  private mutating func readString() -> String? {
    let start = index
    guard consume(0x22) else { return nil }
    while let byte = current {
      switch byte {
      case 0x22:
        index += 1
        let raw = Data(bytes[start..<index])
        return try? JSONSerialization.jsonObject(
          with: raw,
          options: [.fragmentsAllowed]
        ) as? String
      case 0x5C:
        index += 1
        guard current != nil else { return nil }
        index += 1
      case 0x00...0x1F:
        return nil
      default:
        index += 1
      }
    }
    return nil
  }

  private mutating func readNumber() {
    while let byte = current,
          (0x30...0x39).contains(byte) || byte == 0x2D || byte == 0x2B
            || byte == 0x2E || byte == 0x45 || byte == 0x65 {
      index += 1
    }
  }

  private mutating func readLiteral(_ literal: [UInt8]) -> Bool {
    guard index + literal.count <= bytes.count,
          Array(bytes[index..<(index + literal.count)]) == literal else { return false }
    index += literal.count
    return true
  }

  private mutating func consume(_ byte: UInt8) -> Bool {
    guard current == byte else { return false }
    index += 1
    return true
  }

  private mutating func skipWhitespace() {
    while let byte = current, [0x20, 0x09, 0x0A, 0x0D].contains(byte) {
      index += 1
    }
  }

  private var current: UInt8? {
    guard index < bytes.count else { return nil }
    return bytes[index]
  }
}
