#if os(macOS)
  import Darwin
  import Foundation
  import Logging
  import MCP

  actor FleckMCPBoundedStdioTransport: Transport {
    nonisolated let logger = Logger(label: "mcp.transport.fleck.stdio")

    private let messageStream: AsyncThrowingStream<Data, Error>
    private let messageContinuation: AsyncThrowingStream<Data, Error>.Continuation
    private let inputDescriptor: Int32
    private let outputDescriptor: Int32
    private var isConnected = false
    private var readTask: Task<Void, Never>?
    private var outputIsBusy = false
    private var outputWaiters: [OutputWaiter] = []

    private static let outputWriteTimeout = Duration.seconds(2)

    var pendingOutputSendCount: Int { outputWaiters.count + (outputIsBusy ? 1 : 0) }

    init(
      inputDescriptor: Int32 = STDIN_FILENO,
      outputDescriptor: Int32 = STDOUT_FILENO
    ) {
      self.inputDescriptor = inputDescriptor
      self.outputDescriptor = outputDescriptor
      var continuation: AsyncThrowingStream<Data, Error>.Continuation!
      messageStream = AsyncThrowingStream(
        bufferingPolicy: .bufferingOldest(
          FleckMCPModernDispatcher.maximumConcurrentRequests
        )
      ) { continuation = $0 }
      messageContinuation = continuation
    }

    func connect() throws {
      guard !isConnected else { return }
      guard fcntl(outputDescriptor, F_SETNOSIGPIPE, 1) == 0 else {
        throw FleckMCPBoundedStdioError.systemCall(errno)
      }
      try Self.setNonBlocking(inputDescriptor)
      try Self.setNonBlocking(outputDescriptor)
      isConnected = true
      readTask = Task { [weak self] in
        guard let self else { return }
        await self.readLoop()
      }
    }

    func disconnect() {
      guard isConnected else { return }
      isConnected = false
      readTask?.cancel()
      let waiting = outputWaiters.map(\.continuation)
      outputWaiters.removeAll()
      outputIsBusy = false
      for waiter in waiting {
        waiter.resume(throwing: FleckMCPBoundedStdioError.notConnected)
      }
      messageContinuation.finish()
    }

    func send(_ data: Data) async throws {
      guard isConnected,
        data.count <= FleckMCPModernDispatcher.maximumBatchResponseBytes,
        !data.contains(UInt8(ascii: "\n"))
      else {
        throw FleckMCPBoundedStdioError.invalidMessage
      }
      try await acquireOutput()
      defer { releaseOutput() }
      guard !Task.isCancelled else { throw CancellationError() }

      var message = data
      message.append(UInt8(ascii: "\n"))
      var offset = 0
      let deadline = ContinuousClock.now + Self.outputWriteTimeout
      while offset < message.count {
        guard isConnected else { throw FleckMCPBoundedStdioError.notConnected }
        if ContinuousClock.now >= deadline {
          disconnect()
          throw FleckMCPBoundedStdioError.outputWriteTimedOut
        }
        if offset == 0, Task.isCancelled { throw CancellationError() }
        let written = message.withUnsafeBytes { buffer in
          Darwin.write(
            outputDescriptor,
            buffer.baseAddress?.advanced(by: offset),
            buffer.count - offset
          )
        }
        if written > 0 {
          offset += written
          continue
        }
        if written < 0, errno == EAGAIN || errno == EWOULDBLOCK {
          await Self.waitForRetry()
          continue
        }
        if written < 0, errno == EINTR { continue }
        throw FleckMCPBoundedStdioError.systemCall(written < 0 ? errno : EIO)
      }
    }

    func receive() -> AsyncThrowingStream<Data, Error> { messageStream }

    private func readLoop() async {
      let maximumBytes = FleckMCPModernDispatcher.maximumMessageBytes
      var buffer = [UInt8](repeating: 0, count: 4096)
      var pending = Data()
      var discardingOversizedMessage = false

      while !Task.isCancelled {
        let bytesRead = buffer.withUnsafeMutableBytes { buffer in
          Darwin.read(inputDescriptor, buffer.baseAddress, buffer.count)
        }
        if bytesRead == 0 {
          if !pending.isEmpty || discardingOversizedMessage {
            messageContinuation.finish(throwing: FleckMCPBoundedStdioError.truncatedMessage)
            return
          }
          messageContinuation.finish()
          return
        }
        if bytesRead < 0 {
          if errno == EAGAIN || errno == EWOULDBLOCK {
            try? await Task.sleep(for: .milliseconds(10))
            continue
          }
          if errno == EINTR { continue }
          messageContinuation.finish(throwing: FleckMCPBoundedStdioError.systemCall(errno))
          return
        }

        for byte in buffer.prefix(bytesRead) {
          if byte == UInt8(ascii: "\n") {
            if discardingOversizedMessage {
              guard await yield(Data([UInt8.max])) else { return }
              discardingOversizedMessage = false
            } else {
              guard await yield(pending) else { return }
            }
            pending.removeAll(keepingCapacity: true)
          } else if !discardingOversizedMessage {
            if pending.count == maximumBytes {
              pending.removeAll(keepingCapacity: true)
              discardingOversizedMessage = true
            } else {
              pending.append(byte)
            }
          }
        }
      }
      messageContinuation.finish()
    }

    private func yield(_ message: Data) async -> Bool {
      while isConnected, !Task.isCancelled {
        switch messageContinuation.yield(message) {
        case .enqueued:
          return true
        case .dropped:
          await Self.waitForRetry()
        case .terminated:
          return false
        @unknown default:
          return false
        }
      }
      return false
    }

    private func acquireOutput() async throws {
      guard isConnected else { throw FleckMCPBoundedStdioError.notConnected }
      guard outputIsBusy else {
        outputIsBusy = true
        return
      }
      guard outputWaiters.count < FleckMCPModernDispatcher.maximumConcurrentRequests - 1
      else {
        throw FleckMCPBoundedStdioError.outputQueueFull
      }
      let waiterID = UUID()
      try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation {
          (continuation: CheckedContinuation<Void, Error>) in
          guard isConnected else {
            continuation.resume(throwing: FleckMCPBoundedStdioError.notConnected)
            return
          }
          guard !Task.isCancelled else {
            continuation.resume(throwing: CancellationError())
            return
          }
          outputWaiters.append(OutputWaiter(id: waiterID, continuation: continuation))
        }
      } onCancel: {
        Task { await self.cancelOutputWaiter(waiterID) }
      }
      guard isConnected else { throw FleckMCPBoundedStdioError.notConnected }
    }

    private func releaseOutput() {
      guard !outputWaiters.isEmpty else {
        outputIsBusy = false
        return
      }
      outputWaiters.removeFirst().continuation.resume()
    }

    private func cancelOutputWaiter(_ id: UUID) {
      guard let index = outputWaiters.firstIndex(where: { $0.id == id }) else { return }
      outputWaiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    private static func waitForRetry() async {
      await Task.detached { try? await Task.sleep(for: .milliseconds(10)) }.value
    }

    private static func setNonBlocking(_ descriptor: Int32) throws {
      let flags = fcntl(descriptor, F_GETFL)
      guard flags >= 0,
        fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) >= 0
      else {
        throw FleckMCPBoundedStdioError.systemCall(errno)
      }
    }

    private struct OutputWaiter {
      let id: UUID
      let continuation: CheckedContinuation<Void, Error>
    }
  }

  private enum FleckMCPBoundedStdioError: Error {
    case invalidMessage
    case notConnected
    case truncatedMessage
    case outputQueueFull
    case outputWriteTimedOut
    case systemCall(Int32)
  }
#endif
