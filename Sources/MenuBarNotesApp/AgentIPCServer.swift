#if os(macOS)
  import Darwin
  import AppKit
  import Foundation
  import MenuBarNotesAgentProtocol
  import MenuBarNotesCore

  enum AgentIPCServerError: Error, Equatable {
    case unsafeEndpoint
    case socketPathTooLong
    case systemCall
  }

  final class AgentIPCServer: @unchecked Sendable {
    typealias Execute =
      @MainActor @Sendable (
        UUID,
        Data,
        AgentWorkspaceCommand
      ) async throws -> AgentWorkspaceResponse
    typealias PeerUIDLookup = @Sendable (Int32) throws -> uid_t
    typealias ResponseWriter = @Sendable (Data, Int32) -> Void

    private struct BoundSocket: Equatable {
      let device: dev_t
      let inode: ino_t
    }

    private final class Client: @unchecked Sendable {
      let descriptor: Int32
      let source: DispatchSourceRead
      var buffer = Data()
      var timeout: DispatchWorkItem?

      init(descriptor: Int32, source: DispatchSourceRead) {
        self.descriptor = descriptor
        self.source = source
      }
    }

    let maximumActiveClients: Int
    let idleReadTimeout: TimeInterval

    private let endpointURL: URL
    private let effectiveUID: uid_t
    private let peerUID: PeerUIDLookup
    private let responseWriter: ResponseWriter
    private let execute: Execute
    private let queue = DispatchQueue(label: "Motes.AgentIPCServer")
    private let lock = NSLock()
    private var listenerDescriptor: Int32 = -1
    private var listenerSource: DispatchSourceRead?
    private var clients: [Int32: Client] = [:]
    private var boundSocket: BoundSocket?

    init(
      endpointURL: URL = AgentBridgeEndpoint.socketURL(),
      maximumActiveClients: Int = 8,
      idleReadTimeout: TimeInterval = 10,
      effectiveUID: uid_t = geteuid(),
      peerUID: @escaping PeerUIDLookup = AgentIPCServer.lookupPeerUID,
      responseWriter: @escaping ResponseWriter = AgentIPCServer.writeAll,
      execute: @escaping Execute
    ) {
      self.endpointURL = endpointURL
      self.maximumActiveClients = maximumActiveClients
      self.idleReadTimeout = idleReadTimeout
      self.effectiveUID = effectiveUID
      self.peerUID = peerUID
      self.responseWriter = responseWriter
      self.execute = execute
    }

    deinit {
      stop()
    }

    func start() throws {
      try lock.withLock {
        guard listenerDescriptor == -1 else { return }
        guard maximumActiveClients > 0, idleReadTimeout > 0 else {
          throw AgentIPCServerError.unsafeEndpoint
        }
        try prepareEndpoint()

        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw AgentIPCServerError.systemCall }
        var shouldClose = true
        defer {
          if shouldClose {
            Darwin.close(descriptor)
          }
        }
        guard fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0 else {
          throw AgentIPCServerError.systemCall
        }

        var address = try socketAddress()
        let addressLength = socklen_t(
          MemoryLayout<sa_family_t>.size
            + endpointURL.path.utf8.count + 1
        )
        let bindResult = withUnsafePointer(to: &address) { pointer in
          pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.bind(descriptor, $0, addressLength)
          }
        }
        guard bindResult == 0 else { throw AgentIPCServerError.systemCall }
        guard chmod(endpointURL.path, 0o600) == 0 else {
          Darwin.unlink(endpointURL.path)
          throw AgentIPCServerError.systemCall
        }
        guard Darwin.listen(descriptor, Int32(maximumActiveClients)) == 0 else {
          Darwin.unlink(endpointURL.path)
          throw AgentIPCServerError.systemCall
        }
        let identity = try socketIdentity(at: endpointURL.path)

        let source = DispatchSource.makeReadSource(
          fileDescriptor: descriptor,
          queue: queue
        )
        source.setEventHandler { [weak self] in
          self?.acceptClients()
        }
        listenerDescriptor = descriptor
        listenerSource = source
        boundSocket = identity
        shouldClose = false
        source.resume()
      }
    }

    func stop() {
      let identity = lock.withLock {
        let identity = boundSocket
        listenerSource?.cancel()
        if listenerDescriptor >= 0 {
          Darwin.shutdown(listenerDescriptor, SHUT_RDWR)
          Darwin.close(listenerDescriptor)
        }
        for client in clients.values {
          client.timeout?.cancel()
          client.source.cancel()
          Darwin.shutdown(client.descriptor, SHUT_RDWR)
          Darwin.close(client.descriptor)
        }
        listenerSource = nil
        listenerDescriptor = -1
        clients.removeAll()
        boundSocket = nil
        return identity
      }

      if let identity {
        unlinkOwnedSocket(ifMatching: identity)
      }
    }

    func response(to request: AgentWireRequest) async -> AgentWireResponse {
      guard request.protocolVersion == AgentWireRequest.currentProtocolVersion else {
        return .failure(
          requestID: request.requestID,
          error: AgentWorkspaceError(
            code: .invalidPayload,
            recoveryAction: "Please update Motes and the helper, then try again."
          )
        )
      }
      guard
        let credential = Data(
          base64Encoded: request.credentialBase64,
          options: []
        ),
        credential.count == 32,
        credential.base64EncodedString() == request.credentialBase64
      else {
        return .failure(
          requestID: request.requestID,
          error: AgentWorkspaceError(code: .invalidPayload)
        )
      }

      let response: AgentWireResponse
      do {
        response = .success(
          requestID: request.requestID,
          result: try await execute(
            request.profileID,
            credential,
            request.command
          )
        )
      } catch let error as AgentWorkspaceError {
        response = .failure(requestID: request.requestID, error: error)
      } catch {
        response = .failure(
          requestID: request.requestID,
          error: AgentWorkspaceError(code: .internalSaveFailure)
        )
      }
      guard (try? AgentWireFraming.encode(response)) != nil else {
        return .failure(
          requestID: request.requestID,
          error: AgentWorkspaceError(code: .responseTooLarge)
        )
      }
      return response
    }

    func peerIsAllowed(_ descriptor: Int32) -> Bool {
      (try? peerUID(descriptor)) == effectiveUID
    }

    private func prepareEndpoint() throws {
      let parent = endpointURL.deletingLastPathComponent()
      var status = stat()
      if lstat(parent.path, &status) != 0 {
        guard errno == ENOENT else { throw AgentIPCServerError.unsafeEndpoint }
        do {
          try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
          )
        } catch {
          throw AgentIPCServerError.unsafeEndpoint
        }
        guard lstat(parent.path, &status) == 0 else {
          throw AgentIPCServerError.unsafeEndpoint
        }
      }
      guard
        status.st_mode & S_IFMT == S_IFDIR,
        status.st_uid == effectiveUID,
        chmod(parent.path, 0o700) == 0
      else {
        throw AgentIPCServerError.unsafeEndpoint
      }

      var leaf = stat()
      if lstat(endpointURL.path, &leaf) == 0 {
        guard
          leaf.st_mode & S_IFMT == S_IFSOCK,
          leaf.st_uid == effectiveUID,
          Darwin.unlink(endpointURL.path) == 0
        else {
          throw AgentIPCServerError.unsafeEndpoint
        }
      } else if errno != ENOENT {
        throw AgentIPCServerError.unsafeEndpoint
      }
      guard endpointURL.path.utf8.count + 1 <= 104 else {
        throw AgentIPCServerError.socketPathTooLong
      }
    }

    private func socketAddress() throws -> sockaddr_un {
      let bytes = Array(endpointURL.path.utf8) + [0]
      guard bytes.count <= 104 else {
        throw AgentIPCServerError.socketPathTooLong
      }
      var address = sockaddr_un()
      address.sun_family = sa_family_t(AF_UNIX)
      withUnsafeMutablePointer(to: &address.sun_path) { pointer in
        pointer.withMemoryRebound(to: UInt8.self, capacity: 104) {
          for (index, byte) in bytes.enumerated() {
            $0[index] = byte
          }
        }
      }
      return address
    }

    private func socketIdentity(at path: String) throws -> BoundSocket {
      var status = stat()
      guard
        lstat(path, &status) == 0,
        status.st_mode & S_IFMT == S_IFSOCK,
        status.st_uid == effectiveUID
      else {
        throw AgentIPCServerError.systemCall
      }
      return BoundSocket(device: status.st_dev, inode: status.st_ino)
    }

    private func unlinkOwnedSocket(ifMatching identity: BoundSocket) {
      var status = stat()
      guard
        lstat(endpointURL.path, &status) == 0,
        status.st_mode & S_IFMT == S_IFSOCK,
        status.st_uid == effectiveUID,
        status.st_dev == identity.device,
        status.st_ino == identity.inode
      else { return }
      Darwin.unlink(endpointURL.path)
    }

    private func acceptClients() {
      while true {
        let descriptor = Darwin.accept(listener(), nil, nil)
        if descriptor < 0 {
          if errno == EINTR { continue }
          return
        }
        acceptClient(descriptor)
      }
    }

    private func listener() -> Int32 {
      lock.withLock { listenerDescriptor }
    }

    private func acceptClient(_ descriptor: Int32) {
      guard
        setNoSigPipe(descriptor),
        peerIsAllowed(descriptor)
      else {
        Darwin.close(descriptor)
        return
      }

      let source = DispatchSource.makeReadSource(
        fileDescriptor: descriptor,
        queue: queue
      )
      let client = Client(descriptor: descriptor, source: source)
      let inserted = lock.withLock {
        guard
          listenerDescriptor >= 0,
          clients.count < maximumActiveClients
        else { return false }
        clients[descriptor] = client
        return true
      }
      guard inserted else {
        source.cancel()
        source.resume()
        Darwin.close(descriptor)
        return
      }
      source.setEventHandler { [weak self] in
        self?.read(client)
      }
      source.resume()
      resetTimeout(client)
    }

    private func read(_ client: Client) {
      var bytes = [UInt8](repeating: 0, count: 8_192)
      let count = Darwin.read(client.descriptor, &bytes, bytes.count)
      guard count > 0 else {
        finish(client)
        return
      }
      guard
        count <= AgentWireFraming.maximumFrameBytes + 4 - client.buffer.count
      else {
        finish(client)
        return
      }
      client.buffer.append(bytes, count: count)
      if client.buffer.count >= 4 {
        let length = client.buffer.prefix(4).reduce(UInt32.zero) {
          ($0 << 8) | UInt32($1)
        }
        guard
          length > 0,
          length <= AgentWireFraming.maximumFrameBytes
        else {
          finish(client)
          return
        }
        guard client.buffer.count <= Int(length) + 4 else {
          finish(client)
          return
        }
      }

      do {
        guard
          let request = try AgentWireFraming.decodeFrame(
            AgentWireRequest.self,
            from: &client.buffer
          )
        else {
          resetTimeout(client)
          return
        }
        client.timeout?.cancel()
        client.source.cancel()
        Task { [weak self] in
          guard let self else { return }
          let frame = try? AgentWireFraming.encode(
            await self.response(to: request)
          )
          self.queue.async {
            if let frame {
              self.writeIfActive(frame, to: client)
            }
            self.finish(client)
          }
        }
      } catch {
        finish(client)
      }
    }

    private func resetTimeout(_ client: Client) {
      client.timeout?.cancel()
      let timeout = DispatchWorkItem { [weak self, weak client] in
        guard let client else { return }
        self?.finish(client, cancelTimeout: false)
      }
      client.timeout = timeout
      queue.asyncAfter(
        deadline: .now() + idleReadTimeout,
        execute: timeout
      )
    }

    private func writeIfActive(_ data: Data, to client: Client) {
      lock.withLock {
        guard clients[client.descriptor] === client else { return }
        responseWriter(data, client.descriptor)
      }
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) {
      data.withUnsafeBytes { rawBuffer in
        guard var base = rawBuffer.baseAddress else { return }
        var remaining = rawBuffer.count
        while remaining > 0 {
          let count = Darwin.write(descriptor, base, remaining)
          if count > 0 {
            remaining -= count
            base = base.advanced(by: count)
          } else if count < 0, errno == EINTR {
            continue
          } else {
            return
          }
        }
      }
    }

    private func finish(_ client: Client, cancelTimeout: Bool = true) {
      lock.withLock {
        guard clients[client.descriptor] === client else { return }
        clients.removeValue(forKey: client.descriptor)
        if cancelTimeout {
          client.timeout?.cancel()
        }
        client.timeout = nil
        client.source.cancel()
        Darwin.shutdown(client.descriptor, SHUT_RDWR)
        Darwin.close(client.descriptor)
      }
    }

    private static func lookupPeerUID(_ descriptor: Int32) throws -> uid_t {
      var uid: uid_t = 0
      var gid: gid_t = 0
      guard getpeereid(descriptor, &uid, &gid) == 0 else {
        throw AgentIPCServerError.systemCall
      }
      return uid
    }

    private func setNoSigPipe(_ descriptor: Int32) -> Bool {
      var enabled: Int32 = 1
      return setsockopt(
        descriptor,
        SOL_SOCKET,
        SO_NOSIGPIPE,
        &enabled,
        socklen_t(MemoryLayout<Int32>.size)
      ) == 0
    }
  }

  @MainActor
  final class AgentIPCRuntime {
    private final class ObserverToken: @unchecked Sendable {
      let value: NSObjectProtocol

      init(_ value: NSObjectProtocol) {
        self.value = value
      }
    }

    private let server: AgentIPCServer
    private var startupTask: Task<Void, Never>?
    private var terminationObserver: ObserverToken?

    convenience init(appState: AppState, server: AgentIPCServer) {
      self.init(
        server: server,
        waitUntilReady: { [weak appState] in
          await appState?.waitUntilInitialLoad()
        }
      )
    }

    init(
      server: AgentIPCServer,
      waitUntilReady: @escaping @MainActor @Sendable () async -> Void
    ) {
      self.server = server
      startupTask = Task { [weak server] in
        await waitUntilReady()
        guard !Task.isCancelled else { return }
        try? server?.start()
      }
      terminationObserver = ObserverToken(
        NotificationCenter.default.addObserver(
          forName: NSApplication.willTerminateNotification,
          object: nil,
          queue: .main
        ) { [weak server] _ in
          server?.stop()
        }
      )
    }

    deinit {
      startupTask?.cancel()
      if let terminationObserver {
        NotificationCenter.default.removeObserver(terminationObserver.value)
      }
      server.stop()
    }
  }
#endif
