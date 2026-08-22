import Darwin
import Foundation
import LocalDictationCandidateProtocol

public protocol AdapterProcessClock: Sendable {
  func sleep(for duration: Duration) async throws
}

public struct ContinuousAdapterClock: AdapterProcessClock {
  public init() {}

  public func sleep(for duration: Duration) async throws {
    try await Task.sleep(for: duration)
  }
}

public enum AdapterProcessError: Error, Equatable, Sendable, CustomStringConvertible {
  case alreadyStarted
  case notStarted
  case invalidExecutable(String)
  case invalidEnvironmentKey(String)
  case invalidEnvironmentValue(String)
  case invalidArgument
  case duplicateRequestID(String)
  case unknownCancellationRequest(String)
  case cancelTargetNotPending(String)
  case unexpectedRequestID(String)
  case invalidEventOrdering(String)
  case stdoutProtocol(CandidateAdapterProtocolError)
  case stdoutFlood
  case stdoutReadFailed
  case unexpectedEOF
  case unexpectedAcknowledgement(
    expected: CandidateAdapterEventKind,
    received: CandidateAdapterEventKind
  )
  case shutdownAcknowledgementMissing
  case childExitFailure(Int32)
  case childExitNotProven
  case timeout(String)

  public var description: String {
    switch self {
    case .alreadyStarted: return "adapter already started"
    case .notStarted: return "adapter not started"
    case .invalidExecutable(let path): return "invalid executable: \(path)"
    case .invalidEnvironmentKey(let key): return "invalid environment key: \(key)"
    case .invalidEnvironmentValue(let key): return "invalid environment value: \(key)"
    case .invalidArgument: return "invalid process argument"
    case .duplicateRequestID(let requestID): return "duplicate request ID: \(requestID)"
    case .unknownCancellationRequest(let requestID):
      return "unknown cancellation request: \(requestID)"
    case .cancelTargetNotPending(let requestID):
      return "cancel target not pending: \(requestID)"
    case .unexpectedRequestID(let requestID): return "unexpected request ID: \(requestID)"
    case .invalidEventOrdering(let detail): return "invalid event ordering: \(detail)"
    case .stdoutProtocol(let error): return "stdout protocol error: \(error)"
    case .stdoutFlood: return "stdout flood"
    case .stdoutReadFailed: return "stdout read failed"
    case .unexpectedEOF: return "unexpected adapter EOF"
    case .unexpectedAcknowledgement: return "unexpected acknowledgement"
    case .shutdownAcknowledgementMissing: return "shutdown acknowledgement missing"
    case .childExitFailure(let status): return "child exited with status: \(status)"
    case .childExitNotProven: return "child exit could not be proven"
    case .timeout(let operation): return "timeout: \(operation)"
    }
  }
}

public enum AdapterProcessTerminationPath: String, Equatable, Sendable {
  case cooperativeCancellation
  case cooperativeShutdown
  case forcedTermination
}

public struct AdapterProcessDiagnostics: Equatable, Sendable {
  public let stderr: String
  public let stderrByteCount: Int
  public let stderrReceivedByteCount: Int
  public let stderrTruncated: Bool
  public let stdoutByteCount: Int
  public let forcedTermination: Bool
  public let cancelAcknowledged: Bool
  public let shutdownAcknowledged: Bool
  public let childIsRunning: Bool
  public let childExitStatus: Int32?

  fileprivate init(
    stderr: String,
    stderrByteCount: Int,
    stderrReceivedByteCount: Int,
    stderrTruncated: Bool,
    stdoutByteCount: Int,
    forcedTermination: Bool,
    cancelAcknowledged: Bool,
    shutdownAcknowledged: Bool,
    childIsRunning: Bool,
    childExitStatus: Int32?
  ) {
    self.stderr = stderr
    self.stderrByteCount = stderrByteCount
    self.stderrReceivedByteCount = stderrReceivedByteCount
    self.stderrTruncated = stderrTruncated
    self.stdoutByteCount = stdoutByteCount
    self.forcedTermination = forcedTermination
    self.cancelAcknowledged = cancelAcknowledged
    self.shutdownAcknowledged = shutdownAcknowledged
    self.childIsRunning = childIsRunning
    self.childExitStatus = childExitStatus
  }
}

public actor AdapterProcess {
  private struct RequestState {
    let operation: CandidateAdapterOperation
    let targetRequestID: String?
    var ready = false
    var terminal = false
    var lastPartialSequence = -1
  }

  private static let allowedEnvironmentKeys: Set<String> = [
    "PATH",
    "TMPDIR",
    "LANG",
    "LC_ALL",
    "LC_CTYPE",
    "METAL_CAPTURE_ENABLED",
    "METAL_DEBUG_ERROR_MODE",
    "METAL_DEVICE_WRAPPER_TYPE",
  ]
  private static let maximumStdoutBytes = JSONLinesCodec.maximumLineBytes

  private let clock: any AdapterProcessClock
  private let terminationSignal: @Sendable (Int32) -> Void
  private var stderrOutput: BoundedOutput
  private var process: Process?
  private var stdin: FileHandle?
  private var stdoutHandle: FileHandle?
  private var stderrHandle: FileHandle?
  private var stdoutSource: DispatchSourceRead?
  private var stderrSource: DispatchSourceRead?
  private var eventStream: AsyncThrowingStream<CandidateAdapterEvent, Error>?
  private var eventContinuation: AsyncThrowingStream<CandidateAdapterEvent, Error>.Continuation?
  private var pendingEvents: [CandidateAdapterEvent] = []
  private var stdoutLineBuffer = Data()
  private var stdoutEOFSeen = false
  private var stdoutByteCount = 0
  private var requestStates: [String: RequestState] = [:]
  private var terminalRequestIDs = Set<String>()
  private var terminalEventKinds: [String: CandidateAdapterEventKind] = [:]
  private var waiters: [String: [CheckedContinuation<Void, Error>]] = [:]
  private var terminalError: AdapterProcessError?
  private var childExitStatus: Int32?
  private var forcedTermination = false
  private var cancelAcknowledged = false
  private var shutdownAcknowledged = false
  private var shuttingDown = false
  private var shutdownCompletion: Task<AdapterProcessTerminationPath, Error>?

  public init(
    clock: any AdapterProcessClock = ContinuousAdapterClock(),
    redactedRoots: [URL] = []
  ) {
    self.clock = clock
    self.terminationSignal = { processIdentifier in
      _ = Darwin.kill(processIdentifier, SIGKILL)
    }
    stderrOutput = BoundedOutput(redactedRoots: redactedRoots)
  }

  init(
    clock: any AdapterProcessClock = ContinuousAdapterClock(),
    redactedRoots: [URL] = [],
    terminationSignal: @escaping @Sendable (Int32) -> Void
  ) {
    self.clock = clock
    self.terminationSignal = terminationSignal
    stderrOutput = BoundedOutput(redactedRoots: redactedRoots)
  }

  public func events() -> AsyncThrowingStream<CandidateAdapterEvent, Error> {
    if let eventStream {
      return eventStream
    }
    let pair = AsyncThrowingStream<CandidateAdapterEvent, Error>.makeStream(
      bufferingPolicy: .bufferingOldest(256)
    )
    eventStream = pair.stream
    eventContinuation = pair.continuation
    if let terminalError {
      pair.continuation.finish(throwing: terminalError)
    } else {
      for event in pendingEvents {
        _ = pair.continuation.yield(event)
      }
    }
    pendingEvents.removeAll(keepingCapacity: false)
    return pair.stream
  }

  public func start(
    executableURL: URL,
    arguments: [String] = [],
    environment: [String: String] = [:]
  ) async throws {
    guard process == nil else {
      throw AdapterProcessError.alreadyStarted
    }
    let executable = try Self.resolveExecutable(executableURL)
    let environment = try Self.resolveEnvironment(environment)
    guard arguments.allSatisfy({ argument in
      !argument.unicodeScalars.contains { $0 == "\0" || $0 == "\n" || $0 == "\r" }
    }) else {
      throw AdapterProcessError.invalidArgument
    }

    let process = Process()
    let input = Pipe()
    let output = Pipe()
    let error = Pipe()
    process.executableURL = executable
    process.arguments = arguments
    process.environment = environment
    process.standardInput = input
    process.standardOutput = output
    process.standardError = error
    process.terminationHandler = { [weak self] process in
      let status = process.terminationStatus
      Task { await self?.handleTermination(status: status) }
    }
    do {
      try process.run()
    } catch {
      throw AdapterProcessError.invalidExecutable(executable.path)
    }
    self.process = process
    stdin = input.fileHandleForWriting
    stdoutHandle = output.fileHandleForReading
    stderrHandle = error.fileHandleForReading
    installReaders(output: output.fileHandleForReading, error: error.fileHandleForReading)
  }

  public func send(_ request: CandidateAdapterRequest) async throws {
    guard let process, process.isRunning, stdin != nil else {
      throw AdapterProcessError.notStarted
    }
    try request.validate()
    guard requestStates[request.requestID] == nil else {
      throw AdapterProcessError.duplicateRequestID(request.requestID)
    }
    let data: Data
    do {
      data = try JSONLinesCodec.encode(request)
    } catch let error as CandidateAdapterProtocolError {
      throw AdapterProcessError.stdoutProtocol(error)
    }
    guard let stdin else {
      throw AdapterProcessError.notStarted
    }
    requestStates[request.requestID] = RequestState(
      operation: request.operation,
      targetRequestID: request.targetRequestID
    )
    do {
      try stdin.write(contentsOf: data)
    } catch {
      requestStates.removeValue(forKey: request.requestID)
      throw AdapterProcessError.notStarted
    }
  }

  @discardableResult
  public func cancel(
    requestID: String,
    timeout: Duration
  ) async throws -> AdapterProcessTerminationPath {
    guard let targetState = requestStates[requestID] else {
      throw AdapterProcessError.unknownCancellationRequest(requestID)
    }
    guard !targetState.terminal else {
      if targetState.operation == .load {
        throw AdapterProcessError.cancelTargetNotPending(requestID)
      }
      throw AdapterProcessError.unknownCancellationRequest(requestID)
    }
    let cancelRequestID = "cancel-\(UUID().uuidString)"
    try await send(
      CandidateAdapterRequest(
        schemaVersion: 1,
        requestID: cancelRequestID,
        operation: .cancel,
        audioPath: nil,
        sampleRate: nil,
        localeIdentifier: nil,
        contextPhrases: [],
        transcript: nil,
        protectedForms: [],
        cleanupMode: nil,
        targetRequestID: requestID
      )
    )
    do {
      try await waitForTerminal(
        cancelRequestID,
        expectedKind: .cancelled,
        timeout: timeout
      )
      cancelAcknowledged = true
      return .cooperativeCancellation
    } catch let error as AdapterProcessError {
      guard case .timeout = error else { throw error }
      do {
        return try await shutdown(timeout: timeout)
      } catch let shutdownError as AdapterProcessError {
        guard case .shutdownAcknowledgementMissing = shutdownError else {
          throw shutdownError
        }
        forceTerminate()
        try await requireChildExit(timeout: .seconds(1))
        return .forcedTermination
      } catch {
        throw error
      }
    }
  }

  @discardableResult
  public func shutdown(timeout: Duration) async throws -> AdapterProcessTerminationPath {
    guard process != nil else {
      throw AdapterProcessError.notStarted
    }
    if let shutdownCompletion {
      return try await shutdownCompletion.value
    }
    let completion = Task { [weak self] () throws -> AdapterProcessTerminationPath in
      guard let self else { throw AdapterProcessError.notStarted }
      return try await self.performShutdown(timeout: timeout)
    }
    shutdownCompletion = completion
    return try await completion.value
  }

  private func performShutdown(timeout: Duration) async throws -> AdapterProcessTerminationPath {
    guard process != nil else {
      throw AdapterProcessError.notStarted
    }
    shuttingDown = true
    let shutdownRequestID = "shutdown-\(UUID().uuidString)"
    try await send(
      CandidateAdapterRequest(
        schemaVersion: 1,
        requestID: shutdownRequestID,
        operation: .shutdown,
        audioPath: nil,
        sampleRate: nil,
        localeIdentifier: nil,
        contextPhrases: [],
        transcript: nil,
        protectedForms: [],
        cleanupMode: nil
      )
    )
    do {
      try await waitForTerminal(
        shutdownRequestID,
        expectedKind: .unloaded,
        timeout: timeout
      )
    } catch let error as AdapterProcessError {
      if case .timeout = error {
        terminalError = .shutdownAcknowledgementMissing
        forceTerminate()
        try await requireChildExit(timeout: .seconds(1))
        throw AdapterProcessError.shutdownAcknowledgementMissing
      }
      throw error
    }

    shutdownAcknowledged = true
    do {
      try await waitForCleanShutdown(timeout: timeout)
      return .cooperativeShutdown
    } catch let error as AdapterProcessError {
      if case .timeout = error {
        forceTerminate()
        shutdownAcknowledged = false
        try await requireChildExit(timeout: .seconds(1))
        return .forcedTermination
      }
      throw error
    }
  }

  public func diagnostics() -> AdapterProcessDiagnostics {
    AdapterProcessDiagnostics(
      stderr: stderrOutput.string,
      stderrByteCount: stderrOutput.byteCount,
      stderrReceivedByteCount: stderrOutput.receivedByteCount,
      stderrTruncated: stderrOutput.didTruncate,
      stdoutByteCount: stdoutByteCount,
      forcedTermination: forcedTermination,
      cancelAcknowledged: cancelAcknowledged,
      shutdownAcknowledged: shutdownAcknowledged,
      childIsRunning: process?.isRunning ?? false,
      childExitStatus: childExitStatus
    )
  }

  func terminateForTesting() {
    forceTerminate()
  }

  public func terminate() async {
    forceTerminate()
    _ = await waitForExit(timeout: .seconds(1))
  }

  private func consumeStdout(_ data: Data) {
    guard terminalError == nil else { return }
    guard stdoutByteCount <= Self.maximumStdoutBytes,
      data.count <= Self.maximumStdoutBytes - stdoutByteCount
    else {
      fail(.stdoutFlood)
      return
    }
    stdoutByteCount += data.count
    stdoutLineBuffer.append(data)
    guard stdoutLineBuffer.count <= JSONLinesCodec.maximumLineBytes else {
      fail(.stdoutFlood)
      return
    }
    while let newline = stdoutLineBuffer.firstIndex(of: 0x0A) {
      let line = Data(stdoutLineBuffer[..<newline]) + Data([0x0A])
      stdoutLineBuffer.removeSubrange(...newline)
      do {
        let event = try JSONLinesCodec.decodeEvent(line)
        try accept(event)
        if let eventContinuation {
          switch eventContinuation.yield(event) {
          case .enqueued:
            break
          case .dropped, .terminated:
            fail(.stdoutFlood)
          @unknown default:
            fail(.stdoutFlood)
          }
        } else {
          if pendingEvents.count >= 256 {
            fail(.stdoutFlood)
            return
          }
          pendingEvents.append(event)
        }
      } catch let error as CandidateAdapterProtocolError {
        fail(.stdoutProtocol(error))
        return
      } catch let error as AdapterProcessError {
        fail(error)
        return
      } catch {
        fail(.stdoutProtocol(.malformedJSON))
        return
      }
    }
  }

  private func consumeStderr(_ data: Data) {
    stderrOutput.append(data)
  }

  private func installReaders(output: FileHandle, error: FileHandle) {
    let stdoutQueue = DispatchQueue(
      label: "LocalDictationCandidateRunner.AdapterProcess.stdout",
      qos: .utility
    )
    let stdoutSource = DispatchSource.makeReadSource(
      fileDescriptor: output.fileDescriptor,
      queue: stdoutQueue
    )
    stdoutSource.setEventHandler { [weak self] in
      let data = output.availableData
      let completion = DispatchSemaphore(value: 0)
      Task { [weak self] in
        defer { completion.signal() }
        guard let self else { return }
        if data.isEmpty {
          stdoutSource.cancel()
          await self.handleStdoutEOF()
        } else {
          await self.consumeStdout(data)
        }
      }
      // Backpressure the dedicated source queue so data and EOF stay ordered.
      // Only this queue waits; the Swift cooperative executor remains unblocked.
      completion.wait()
    }
    stdoutSource.setCancelHandler {
      output.closeFile()
    }
    stdoutSource.resume()
    self.stdoutSource = stdoutSource

    let stderrSource = DispatchSource.makeReadSource(
      fileDescriptor: error.fileDescriptor,
      queue: DispatchQueue.global(qos: .utility)
    )
    stderrSource.setEventHandler { [weak self] in
      let data = error.availableData
      if data.isEmpty {
        stderrSource.cancel()
      } else {
        Task { await self?.consumeStderr(data) }
      }
    }
    stderrSource.setCancelHandler {
      error.closeFile()
    }
    stderrSource.resume()
    self.stderrSource = stderrSource
  }

  private func handleStdoutEOF() {
    guard terminalError == nil else { return }
    stdoutEOFSeen = true
    if !stdoutLineBuffer.isEmpty {
      fail(.stdoutProtocol(.malformedJSON))
    } else {
      Task { [weak self] in
        await Task.yield()
        await self?.checkEOFAfterOutputDrain()
      }
    }
  }

  private func checkEOFAfterOutputDrain() {
    guard stdoutEOFSeen, terminalError == nil, !shutdownAcknowledged else { return }
    if shuttingDown {
      fail(.shutdownAcknowledgementMissing)
    } else {
      fail(.unexpectedEOF)
    }
  }

  private func accept(_ event: CandidateAdapterEvent) throws {
    guard let initialState = requestStates[event.requestID] else {
      throw AdapterProcessError.unexpectedRequestID(event.requestID)
    }
    var state = initialState
    if let expectedKind = Self.expectedAcknowledgementKind(for: state.operation),
      Self.isTerminalEvent(event.kind), event.kind != .failure, event.kind != expectedKind
    {
      throw AdapterProcessError.unexpectedAcknowledgement(
        expected: expectedKind,
        received: event.kind
      )
    }
    switch event {
    case .ready:
      guard state.operation == .load, !state.ready, !state.terminal else {
        throw AdapterProcessError.invalidEventOrdering("ready")
      }
      state.ready = true
      state.terminal = true
    case .partial(_, let sequence, _):
      guard state.operation == .transcribe, !state.terminal,
        sequence > state.lastPartialSequence
      else {
        throw AdapterProcessError.invalidEventOrdering("partial")
      }
      state.lastPartialSequence = sequence
    case .final:
      guard (state.operation == .transcribe || state.operation == .clean),
        !state.terminal
      else {
        throw AdapterProcessError.invalidEventOrdering("final")
      }
      state.terminal = true
    case .cancelled:
      guard state.operation == .cancel, !state.terminal else {
        throw AdapterProcessError.invalidEventOrdering("cancelled")
      }
      guard let targetRequestID = state.targetRequestID,
        var targetState = requestStates[targetRequestID],
        !targetState.terminal
      else {
        throw AdapterProcessError.cancelTargetNotPending(state.targetRequestID ?? "<missing>")
      }
      targetState.terminal = true
      requestStates[targetRequestID] = targetState
      terminalRequestIDs.insert(targetRequestID)
      terminalEventKinds[targetRequestID] = .cancelled
      let targetContinuations = waiters.removeValue(forKey: targetRequestID) ?? []
      for continuation in targetContinuations {
        continuation.resume()
      }
      state.terminal = true
    case .unloaded:
      guard (state.operation == .unload || state.operation == .shutdown),
        !state.terminal
      else {
        throw AdapterProcessError.invalidEventOrdering("unloaded")
      }
      state.terminal = true
      if state.operation == .shutdown {
        shutdownAcknowledged = true
      }
    case .measurement:
      guard !state.terminal else {
        throw AdapterProcessError.invalidEventOrdering("measurement")
      }
    case .failure:
      guard !state.terminal else {
        throw AdapterProcessError.invalidEventOrdering("failure")
      }
      state.terminal = true
    }
    requestStates[event.requestID] = state
    if state.terminal {
      terminalRequestIDs.insert(event.requestID)
      terminalEventKinds[event.requestID] = event.kind
      let continuations = waiters.removeValue(forKey: event.requestID) ?? []
      for continuation in continuations {
        continuation.resume()
      }
    }
  }

  private func waitForTerminal(
    _ requestID: String,
    expectedKind: CandidateAdapterEventKind,
    timeout: Duration
  ) async throws {
    if let terminalError {
      throw terminalError
    }
    if terminalRequestIDs.contains(requestID) {
      try validateTerminal(requestID, expectedKind: expectedKind)
      return
    }
    try await withCheckedThrowingContinuation { continuation in
      waiters[requestID, default: []].append(continuation)
      let clock = self.clock
      Task {
        do {
          try await clock.sleep(for: timeout)
          self.timeoutWaiter(requestID)
        } catch {
          // The timer has no externally visible cancellation path.
        }
      }
    }
    try validateTerminal(requestID, expectedKind: expectedKind)
  }

  private func waitForCleanShutdown(timeout: Duration) async throws {
    let deadline = ContinuousClock.now + timeout
    while true {
      if let terminalError {
        throw terminalError
      }
      if let childExitStatus, childExitStatus != 0 {
        let error = AdapterProcessError.childExitFailure(childExitStatus)
        fail(error)
        throw error
      }
      if stdoutEOFSeen, childExitStatus == 0 {
        return
      }
      guard ContinuousClock.now < deadline else {
        throw AdapterProcessError.timeout("shutdown-completion")
      }
      do {
        try await clock.sleep(for: .milliseconds(5))
      } catch {
        throw AdapterProcessError.timeout("shutdown-completion")
      }
    }
  }

  private func validateTerminal(
    _ requestID: String,
    expectedKind: CandidateAdapterEventKind
  ) throws {
    if let terminalError {
      throw terminalError
    }
    guard let receivedKind = terminalEventKinds[requestID], receivedKind != expectedKind else {
      return
    }
    let error = AdapterProcessError.unexpectedAcknowledgement(
      expected: expectedKind,
      received: receivedKind
    )
    fail(error)
    throw error
  }

  private func timeoutWaiter(_ requestID: String) {
    guard let continuations = waiters.removeValue(forKey: requestID), !continuations.isEmpty else {
      return
    }
    for continuation in continuations {
      continuation.resume(throwing: AdapterProcessError.timeout(requestID))
    }
  }

  private static func expectedAcknowledgementKind(
    for operation: CandidateAdapterOperation
  ) -> CandidateAdapterEventKind? {
    switch operation {
    case .cancel:
      return .cancelled
    case .unload, .shutdown:
      return .unloaded
    case .load, .transcribe, .clean:
      return nil
    }
  }

  private static func isTerminalEvent(_ kind: CandidateAdapterEventKind) -> Bool {
    switch kind {
    case .final, .cancelled, .unloaded, .failure:
      return true
    case .ready, .partial, .measurement:
      return false
    }
  }

  private func handleTermination(status: Int32) {
    childExitStatus = status
    if stdoutEOFSeen {
      checkEOFAfterOutputDrain()
    }
  }

  private func fail(_ error: AdapterProcessError) {
    guard terminalError == nil else { return }
    terminalError = error
    cancelAcknowledged = false
    shutdownAcknowledged = false
    eventContinuation?.finish(throwing: error)
    let continuations = waiters.values.flatMap { $0 }
    waiters.removeAll()
    for continuation in continuations {
      continuation.resume(throwing: error)
    }
    forceTerminate()
  }

  private func forceTerminate() {
    stdoutSource?.cancel()
    stderrSource?.cancel()
    stdin?.closeFile()
    guard let process, process.isRunning else { return }
    forcedTermination = true
    terminationSignal(process.processIdentifier)
  }

  private func requireChildExit(timeout: Duration) async throws {
    guard await waitForExit(timeout: timeout) else {
      throw AdapterProcessError.childExitNotProven
    }
  }

  private func waitForExit(timeout: Duration) async -> Bool {
    let components = timeout.components
    let milliseconds = max(
      1,
      Int(min(
        Int64.max,
        components.seconds.multipliedReportingOverflow(by: 1_000).partialValue
          + components.attoseconds / 1_000_000_000_000_000
      ))
    )
    let iterations = max(1, milliseconds / 5)
    for _ in 0..<iterations {
      guard let process, process.isRunning else {
        if let process {
          childExitStatus = process.terminationStatus
        }
        return true
      }
      await sleepIgnoringCancellation(for: .milliseconds(5))
    }
    if let process, !process.isRunning {
      childExitStatus = process.terminationStatus
      return true
    }
    return false
  }

  private func sleepIgnoringCancellation(for duration: Duration) async {
    let clock = self.clock
    let sleeper = Task.detached { () -> Void in
      do {
        try await clock.sleep(for: duration)
      } catch {
        // An injected clock may refuse the delay; the bounded loop remains fail-closed.
      }
    }
    await sleeper.value
  }

  private static func resolveExecutable(_ url: URL) throws -> URL {
    guard url.isFileURL, url.path.first == "/" else {
      throw AdapterProcessError.invalidExecutable(url.path)
    }
    let resolved = url.resolvingSymlinksInPath()
    let attributes = try? FileManager.default.attributesOfItem(atPath: resolved.path)
    guard attributes?[.type] as? FileAttributeType == .typeRegular,
      FileManager.default.isExecutableFile(atPath: resolved.path)
    else {
      throw AdapterProcessError.invalidExecutable(url.path)
    }
    return resolved
  }

  private static func resolveEnvironment(_ environment: [String: String]) throws -> [String: String] {
    guard environment.keys.allSatisfy({ allowedEnvironmentKeys.contains($0) }) else {
      let key = environment.keys.first(where: { !allowedEnvironmentKeys.contains($0) })!
      throw AdapterProcessError.invalidEnvironmentKey(key)
    }
    var resolved = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
    for (key, value) in environment {
      guard !value.unicodeScalars.contains(where: { $0 == "\0" || $0 == "\n" || $0 == "\r" }) else {
        throw AdapterProcessError.invalidEnvironmentValue(key)
      }
      resolved[key] = value
    }
    return resolved
  }
}
