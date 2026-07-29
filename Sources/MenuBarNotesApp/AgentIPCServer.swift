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
    typealias ResponseWriter = @Sendable (Data, Int, Int32) -> Int
    typealias DescriptorCloser = @Sendable (Int32) -> Void

    private struct BoundSocket: Equatable {
      let device: dev_t
      let inode: ino_t
    }

    private final class DescriptorLifecycle: @unchecked Sendable {
      let descriptor: Int32

      private let closer: DescriptorCloser
      private let lock = NSLock()
      private let closed = DispatchGroup()
      private var sourceCount = 0
      private var closeRequested = false
      private var didClose = false

      init(descriptor: Int32, closer: @escaping DescriptorCloser) {
        self.descriptor = descriptor
        self.closer = closer
        closed.enter()
      }

      func registerSource() -> Bool {
        lock.withLock {
          guard !closeRequested else { return false }
          sourceCount += 1
          return true
        }
      }

      func sourceCancellationDidComplete() {
        closeIfNeeded {
          precondition(sourceCount > 0)
          sourceCount -= 1
        }
      }

      func requestClose() {
        closeIfNeeded {
          closeRequested = true
        }
      }

      func waitUntilClosed() {
        closed.wait()
      }

      private func closeIfNeeded(_ update: () -> Void) {
        let shouldClose = lock.withLock {
          update()
          guard closeRequested, sourceCount == 0, !didClose else {
            return false
          }
          didClose = true
          return true
        }
        guard shouldClose else { return }
        closer(descriptor)
        closed.leave()
      }
    }

    private final class Client: @unchecked Sendable {
      let lifecycle: DescriptorLifecycle
      let source: DispatchSourceRead
      var buffer = Data()
      var timeout: DispatchWorkItem?
      var response: Data?
      var responseOffset = 0
      var writeSource: DispatchSourceWrite?

      var descriptor: Int32 { lifecycle.descriptor }

      init(lifecycle: DescriptorLifecycle, source: DispatchSourceRead) {
        self.lifecycle = lifecycle
        self.source = source
      }
    }

    private struct StopResult {
      let identity: BoundSocket?
      let lifecycles: [DescriptorLifecycle]
    }

    let maximumActiveClients: Int
    let idleReadTimeout: TimeInterval

    private let endpointURL: URL
    private let effectiveUID: uid_t
    private let peerUID: PeerUIDLookup
    private let responseWriter: ResponseWriter
    private let responseWriteWillBegin: @Sendable () -> Void
    private let descriptorCloser: DescriptorCloser
    private let stopWillCancelSources: @Sendable () -> Void
    private let sourceCancellationDidComplete: @Sendable (Int32) -> Void
    private let execute: Execute
    private let queue = DispatchQueue(label: "Motes.AgentIPCServer")
    private let queueKey = DispatchSpecificKey<Void>()
    private let lock = NSLock()
    private var listenerDescriptor: Int32 = -1
    private var listenerSource: DispatchSourceRead?
    private var listenerLifecycle: DescriptorLifecycle?
    private var clients: [Int32: Client] = [:]
    private var boundSocket: BoundSocket?

    init(
      endpointURL: URL = AgentBridgeEndpoint.socketURL(),
      maximumActiveClients: Int = 8,
      idleReadTimeout: TimeInterval = 10,
      effectiveUID: uid_t = geteuid(),
      peerUID: @escaping PeerUIDLookup = AgentIPCServer.lookupPeerUID,
      responseWriter: @escaping ResponseWriter = AgentIPCServer.writeAll,
      responseWriteWillBegin: @escaping @Sendable () -> Void = {},
      descriptorCloser: @escaping DescriptorCloser = AgentIPCServer.closeDescriptor,
      stopWillCancelSources: @escaping @Sendable () -> Void = {},
      sourceCancellationDidComplete: @escaping @Sendable (Int32) -> Void = { _ in },
      execute: @escaping Execute
    ) {
      self.endpointURL = endpointURL
      self.maximumActiveClients = maximumActiveClients
      self.idleReadTimeout = idleReadTimeout
      self.effectiveUID = effectiveUID
      self.peerUID = peerUID
      self.responseWriter = responseWriter
      self.responseWriteWillBegin = responseWriteWillBegin
      self.descriptorCloser = descriptorCloser
      self.stopWillCancelSources = stopWillCancelSources
      self.sourceCancellationDidComplete = sourceCancellationDidComplete
      self.execute = execute
      queue.setSpecific(key: queueKey, value: ())
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

        let lifecycle = DescriptorLifecycle(
          descriptor: descriptor,
          closer: descriptorCloser
        )
        precondition(lifecycle.registerSource())
        let source = DispatchSource.makeReadSource(
          fileDescriptor: descriptor,
          queue: queue
        )
        source.setEventHandler { [weak self] in
          self?.acceptClients()
        }
        source.setCancelHandler { [weak self, lifecycle] in
          self?.sourceCancellationDidComplete(descriptor)
          lifecycle.sourceCancellationDidComplete()
        }
        listenerDescriptor = descriptor
        listenerSource = source
        listenerLifecycle = lifecycle
        boundSocket = identity
        shouldClose = false
        source.resume()
      }
    }

    func stop() {
      let result: StopResult
      if DispatchQueue.getSpecific(key: queueKey) != nil {
        result = stopOnQueue()
      } else {
        result = queue.sync { stopOnQueue() }
        for lifecycle in result.lifecycles {
          lifecycle.waitUntilClosed()
        }
      }

      if let identity = result.identity {
        unlinkOwnedSocket(ifMatching: identity)
      }
    }

    private func stopOnQueue() -> StopResult {
      let state = lock.withLock {
        let identity = boundSocket
        let listener = listenerSource
        let listenerLifecycle = listenerLifecycle
        let clients = Array(clients.values)
        listenerSource = nil
        self.listenerLifecycle = nil
        listenerDescriptor = -1
        self.clients.removeAll()
        boundSocket = nil
        return (identity, listener, listenerLifecycle, clients)
      }

      stopWillCancelSources()
      state.1?.cancel()
      state.2?.requestClose()
      for client in state.3 {
        client.timeout?.cancel()
        client.source.cancel()
        client.writeSource?.cancel()
        client.lifecycle.requestClose()
      }
      return StopResult(
        identity: state.0,
        lifecycles: [state.2].compactMap { $0 } + state.3.map(\.lifecycle)
      )
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
        peerIsAllowed(descriptor),
        setNonBlocking(descriptor)
      else {
        Darwin.close(descriptor)
        return
      }

      let source = DispatchSource.makeReadSource(
        fileDescriptor: descriptor,
        queue: queue
      )
      let lifecycle = DescriptorLifecycle(
        descriptor: descriptor,
        closer: descriptorCloser
      )
      precondition(lifecycle.registerSource())
      source.setCancelHandler { [weak self, lifecycle] in
        self?.sourceCancellationDidComplete(descriptor)
        lifecycle.sourceCancellationDidComplete()
      }
      let client = Client(lifecycle: lifecycle, source: source)
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
        lifecycle.requestClose()
        return
      }
      source.setEventHandler { [weak self] in
        self?.read(client)
      }
      source.resume()
      resetTimeout(client)
    }

    private func read(_ client: Client) {
      guard
        lock.withLock({ clients[client.descriptor] === client })
      else { return }

      var bytes = [UInt8](repeating: 0, count: 8_192)
      let count = Darwin.read(client.descriptor, &bytes, bytes.count)
      if count < 0, errno == EAGAIN || errno == EWOULDBLOCK {
        resetTimeout(client)
        return
      }
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
              self.beginWrite(frame, to: client)
            } else {
              self.finish(client)
            }
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

    private func beginWrite(_ data: Data, to client: Client) {
      let active = lock.withLock {
        guard clients[client.descriptor] === client else { return false }
        client.response = data
        client.responseOffset = 0
        return true
      }
      guard active else { return }
      guard client.lifecycle.registerSource() else {
        finish(client)
        return
      }
      let source = DispatchSource.makeWriteSource(
        fileDescriptor: client.descriptor,
        queue: queue
      )
      client.writeSource = source
      source.setEventHandler { [weak self] in
        self?.continueWrite(client)
      }
      source.setCancelHandler { [weak self, lifecycle = client.lifecycle] in
        self?.sourceCancellationDidComplete(client.descriptor)
        lifecycle.sourceCancellationDidComplete()
      }
      source.resume()
      responseWriteWillBegin()
      resetTimeout(client)
      continueWrite(client)
    }

    private func continueWrite(_ client: Client) {
      guard
        lock.withLock({ clients[client.descriptor] === client }),
        let response = client.response
      else { return }

      while client.responseOffset < response.count {
        let count = responseWriter(
          response,
          client.responseOffset,
          client.descriptor
        )
        if count > 0 {
          client.responseOffset += count
        } else if count < 0, errno == EINTR {
          continue
        } else if count < 0, errno == EAGAIN || errno == EWOULDBLOCK {
          return
        } else {
          finish(client)
          return
        }
      }
      finish(client)
    }

    private static func writeAll(
      _ data: Data,
      from offset: Int,
      to descriptor: Int32
    ) -> Int {
      data.withUnsafeBytes { rawBuffer in
        guard let base = rawBuffer.baseAddress else { return 0 }
        return Darwin.write(
          descriptor,
          base.advanced(by: offset),
          rawBuffer.count - offset
        )
      }
    }

    private func finish(_ client: Client, cancelTimeout: Bool = true) {
      let active = lock.withLock { () -> Bool in
        guard clients[client.descriptor] === client else { return false }
        clients.removeValue(forKey: client.descriptor)
        return true
      }
      guard active else { return }
      if cancelTimeout {
        client.timeout?.cancel()
      }
      client.timeout = nil
      client.source.cancel()
      client.writeSource?.cancel()
      client.lifecycle.requestClose()
    }

    private static func closeDescriptor(_ descriptor: Int32) {
      Darwin.shutdown(descriptor, SHUT_RDWR)
      Darwin.close(descriptor)
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

    private func setNonBlocking(_ descriptor: Int32) -> Bool {
      let flags = fcntl(descriptor, F_GETFL)
      return flags >= 0
        && fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0
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
    private let notificationCenter: NotificationCenter
    private var startupTask: Task<Void, Never>?
    private var terminationObserver: ObserverToken?
    private var terminated = false

    convenience init(appState: AppState, server: AgentIPCServer) {
      self.init(
        server: server,
        waitUntilReady: { [weak appState] in
          await appState?.waitUntilInitialLoad()
        },
        canStart: { [weak appState] in
          appState?.isAgentWorkspaceAvailable == true
        }
      )
    }

    init(
      server: AgentIPCServer,
      waitUntilReady: @escaping @MainActor @Sendable () async -> Void,
      canStart: @escaping @MainActor @Sendable () -> Bool = { true },
      notificationCenter: NotificationCenter = .default
    ) {
      self.server = server
      self.notificationCenter = notificationCenter
      startupTask = Task { [weak self, weak server] in
        await waitUntilReady()
        guard
          let self,
          !Task.isCancelled,
          !terminated,
          canStart()
        else { return }
        try? server?.start()
      }
      terminationObserver = ObserverToken(
        notificationCenter.addObserver(
          forName: NSApplication.willTerminateNotification,
          object: nil,
          queue: .main
        ) { [weak self] _ in
          MainActor.assumeIsolated {
            self?.terminate()
          }
        }
      )
    }

    private func terminate() {
      terminated = true
      startupTask?.cancel()
      startupTask = nil
      server.stop()
    }

    deinit {
      startupTask?.cancel()
      if let terminationObserver {
        notificationCenter.removeObserver(terminationObserver.value)
      }
      server.stop()
    }
  }
#endif
