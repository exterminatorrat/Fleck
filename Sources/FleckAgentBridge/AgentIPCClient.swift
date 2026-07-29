#if os(macOS)
  import AppKit
  import Darwin
  import Foundation
  import FleckAgentProtocol
  import FleckCore

  enum AgentIPCClientError: Error, Equatable {
    case connectionFailed
    case fleckUnavailable
    case writeTimedOut
    case responseTimedOut
    case connectionClosed
    case invalidFrame
    case responseMismatch
    case protocolMismatch
  }

  final class AgentIPCClient {
    typealias Connector = (URL) throws -> Int32
    typealias Launcher = () throws -> Void
    typealias Sleeper = (TimeInterval) -> Void
    typealias Clock = () -> TimeInterval
    typealias Writer = (Data, Int32) throws -> Void
    typealias Reader = (Int32, TimeInterval) throws -> Data
    typealias Closer = (Int32) -> Void

    private let endpointURL: URL
    private let readinessTimeout: TimeInterval
    private let responseTimeout: TimeInterval
    private let pollInterval: TimeInterval
    private let connect: Connector
    private let launch: Launcher
    private let sleep: Sleeper
    private let now: Clock
    private let write: Writer
    private let read: Reader
    private let close: Closer

    init(
      endpointURL: URL = AgentBridgeEndpoint.socketURL(),
      readinessTimeout: TimeInterval = 10,
      responseTimeout: TimeInterval = 60,
      pollInterval: TimeInterval = 0.05,
      connect: @escaping Connector = AgentIPCClient.connectSocket,
      launch: @escaping Launcher = AgentIPCClient.launchMotes,
      sleep: @escaping Sleeper = Thread.sleep(forTimeInterval:),
      now: @escaping Clock = { ProcessInfo.processInfo.systemUptime },
      write: @escaping Writer = AgentIPCClient.writeFrame,
      read: @escaping Reader = AgentIPCClient.readChunk,
      close: @escaping Closer = { Darwin.close($0) }
    ) {
      self.endpointURL = endpointURL
      self.readinessTimeout = readinessTimeout
      self.responseTimeout = responseTimeout
      self.pollInterval = pollInterval
      self.connect = connect
      self.launch = launch
      self.sleep = sleep
      self.now = now
      self.write = write
      self.read = read
      self.close = close
    }

    func send(_ request: AgentWireRequest) throws -> AgentWorkspaceResponse {
      let descriptor = try connectOrLaunch()
      defer { close(descriptor) }

      do {
        try write(try AgentWireFraming.encode(request), descriptor)
      } catch AgentIPCClientError.writeTimedOut {
        throw AgentIPCClientError.writeTimedOut
      } catch {
        throw AgentIPCClientError.connectionClosed
      }

      let responseDeadline = now() + responseTimeout
      var buffer = Data()
      while true {
        guard now() < responseDeadline else {
          throw AgentIPCClientError.responseTimedOut
        }
        do {
          if let response = try AgentWireFraming.decodeFrame(
            AgentWireResponse.self,
            from: &buffer
          ) {
            guard response.requestID == request.requestID else {
              throw AgentIPCClientError.responseMismatch
            }
            guard
              response.protocolVersion
                == AgentWireRequest.currentProtocolVersion
            else {
              throw AgentIPCClientError.protocolMismatch
            }
            if let error = response.error {
              throw error
            }
            guard let result = response.result else {
              throw AgentIPCClientError.invalidFrame
            }
            return result
          }
        } catch let error as AgentIPCClientError {
          throw error
        } catch let error as AgentWorkspaceError {
          throw error
        } catch {
          throw AgentIPCClientError.invalidFrame
        }

        let chunk = try read(
          descriptor,
          max(0, responseDeadline - now())
        )
        guard now() < responseDeadline else {
          throw AgentIPCClientError.responseTimedOut
        }
        guard !chunk.isEmpty else {
          throw AgentIPCClientError.connectionClosed
        }
        buffer.append(chunk)
        guard buffer.count <= AgentWireFraming.maximumFrameBytes + 4 else {
          throw AgentIPCClientError.invalidFrame
        }
      }
    }

    private func connectOrLaunch() throws -> Int32 {
      do {
        return try connect(endpointURL)
      } catch {
        try launch()
      }

      let deadline = now() + readinessTimeout
      while now() < deadline {
        do {
          return try connect(endpointURL)
        } catch {
          sleep(min(pollInterval, max(0, deadline - now())))
        }
      }
      throw AgentIPCClientError.fleckUnavailable
    }

    private static func launchMotes() throws {
      guard
        let applicationURL = NSWorkspace.shared.urlForApplication(
          withBundleIdentifier: "com.harryjin.fleck"
        )
      else {
        throw AgentIPCClientError.fleckUnavailable
      }
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.activates = false
      configuration.addsToRecentItems = false
      NSWorkspace.shared.openApplication(
        at: applicationURL,
        configuration: configuration
      ) { _, _ in }
    }

    private static func connectSocket(to endpointURL: URL) throws -> Int32 {
      let pathBytes = Array(endpointURL.path.utf8)
      guard
        !pathBytes.isEmpty,
        pathBytes.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path)
      else {
        throw AgentIPCClientError.connectionFailed
      }

      let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
      guard descriptor >= 0 else {
        throw AgentIPCClientError.connectionFailed
      }
      var shouldClose = true
      defer {
        if shouldClose {
          Darwin.close(descriptor)
        }
      }

      var noSignal: Int32 = 1
      guard
        setsockopt(
          descriptor,
          SOL_SOCKET,
          SO_NOSIGPIPE,
          &noSignal,
          socklen_t(MemoryLayout<Int32>.size)
        ) == 0
      else {
        throw AgentIPCClientError.connectionFailed
      }

      var address = sockaddr_un()
      address.sun_family = sa_family_t(AF_UNIX)
      withUnsafeMutableBytes(of: &address.sun_path) { destination in
        destination.copyBytes(from: pathBytes)
        destination[pathBytes.count] = 0
      }
      let addressLength = socklen_t(
        MemoryLayout<sa_family_t>.size + pathBytes.count + 1
      )
      let result = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          Darwin.connect(descriptor, $0, addressLength)
        }
      }
      guard result == 0 else {
        throw AgentIPCClientError.connectionFailed
      }
      guard fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0 else {
        throw AgentIPCClientError.connectionFailed
      }
      shouldClose = false
      return descriptor
    }

    private static func writeFrame(_ data: Data, to descriptor: Int32) throws {
      var offset = 0
      let deadline = ProcessInfo.processInfo.systemUptime + 10
      while offset < data.count {
        let written = data.withUnsafeBytes { bytes in
          Darwin.write(
            descriptor,
            bytes.baseAddress!.advanced(by: offset),
            data.count - offset
          )
        }
        if written > 0 {
          offset += written
          continue
        }
        if written < 0, errno == EINTR {
          continue
        }
        if written < 0, errno == EAGAIN || errno == EWOULDBLOCK {
          let remaining = deadline - ProcessInfo.processInfo.systemUptime
          guard remaining > 0 else {
            throw AgentIPCClientError.writeTimedOut
          }
          var descriptorPoll = pollfd(
            fd: descriptor,
            events: Int16(POLLOUT),
            revents: 0
          )
          let milliseconds = Int32(
            min(remaining * 1_000, Double(Int32.max))
          )
          let result = Darwin.poll(&descriptorPoll, 1, milliseconds)
          if result > 0 { continue }
          if result < 0, errno == EINTR { continue }
          if result == 0 { throw AgentIPCClientError.writeTimedOut }
        }
        throw AgentIPCClientError.connectionClosed
      }
    }

    private static func readChunk(
      from descriptor: Int32,
      timeout: TimeInterval
    ) throws -> Data {
      guard timeout > 0 else {
        throw AgentIPCClientError.responseTimedOut
      }
      let deadline = ProcessInfo.processInfo.systemUptime + timeout
      while true {
        var descriptorPoll = pollfd(
          fd: descriptor,
          events: Int16(POLLIN),
          revents: 0
        )
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        guard remaining > 0 else {
          throw AgentIPCClientError.responseTimedOut
        }
        let milliseconds = Int32(
          min(ceil(remaining * 1_000), Double(Int32.max))
        )
        let pollResult = Darwin.poll(&descriptorPoll, 1, milliseconds)
        if pollResult < 0, errno == EINTR { continue }
        if pollResult == 0 {
          throw AgentIPCClientError.responseTimedOut
        }
        guard pollResult > 0 else {
          throw AgentIPCClientError.connectionClosed
        }

        var bytes = [UInt8](repeating: 0, count: 16_384)
        let count = Darwin.read(descriptor, &bytes, bytes.count)
        if count > 0 {
          return Data(bytes.prefix(count))
        }
        if count < 0, errno == EINTR || errno == EAGAIN {
          continue
        }
        throw AgentIPCClientError.connectionClosed
      }
    }
  }
#endif
