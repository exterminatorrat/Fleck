#if os(macOS)
  import Darwin
  import Dispatch
  import Foundation
  import Logging
  import MCP

  enum FleckMCPServer {
    static let name = "fleck"
    static let version = "1.0.0"

    typealias ToolListHandler = @Sendable () async throws -> [Tool]
    typealias ToolHandler =
      @Sendable (CallTool.Parameters) async throws -> CallTool.Result

    static func makeServer(
      listTools: @escaping ToolListHandler,
      callTool: @escaping ToolHandler
    ) async -> Server {
      let server = Server(
        name: name,
        version: version,
        capabilities: .init(tools: .init(listChanged: false))
      )
      await server.withMethodHandler(ListTools.self) { _ in
        ListTools.Result(tools: try await listTools())
      }
      await server.withMethodHandler(CallTool.self, handler: callTool)
      return server
    }

    static func run(profileID: UUID) async throws {
      let client = AgentWorkspaceClient(profileID: profileID)
      let listTools: ToolListHandler = {
        FleckMCPToolRegistry.tools(for: try client.capabilities())
      }
      let callTool: ToolHandler = { parameters in
        FleckMCPToolRegistry.call(parameters, client: client)
      }
      let server = await makeServer(listTools: listTools, callTool: callTool)
      let dispatcher = FleckMCPModernDispatcher(
        listTools: listTools,
        callTool: callTool,
        eventCommand: { command in try client.execute(command) },
        eventAvailability: {
          guard let response = try? client.execute(.listEvents),
            case .events(let events) = response
          else {
            return false
          }
          return !events.isEmpty
        }
      )
      let transport = FleckStdioTransport(
        transport: FleckMCPBoundedStdioTransport(),
        modernDispatcher: dispatcher
      )

      try await server.start(transport: transport)
      let signals = terminationSignals(for: server, transport: transport)
      await transport.waitUntilInputEnded()
      await transport.waitUntilDrained()
      do {
        try await transport.throwOutputFailureIfAny()
      } catch {
        for signalSource in signals {
          signalSource.cancel()
        }
        await server.stop()
        throw error
      }
      for signalSource in signals {
        signalSource.cancel()
      }
      await server.stop()
    }

    private static func terminationSignals(
      for server: Server,
      transport: FleckStdioTransport
    ) -> [DispatchSourceSignal] {
      [SIGINT, SIGTERM].map { signalNumber in
        Darwin.signal(signalNumber, SIG_IGN)
        let source = DispatchSource.makeSignalSource(
          signal: signalNumber,
          queue: .global()
        )
        source.setEventHandler {
          Task {
            await transport.abortDrain()
            await server.stop()
          }
        }
        source.resume()
        return source
      }
    }
  }

  actor FleckStdioTransport: Transport {
    nonisolated let logger: Logger

    private let transport: any Transport
    private let modernDispatcher: FleckMCPModernDispatcher?
    private var receiveStream: AsyncThrowingStream<Data, Error>?
    private var receiveContinuation: AsyncThrowingStream<Data, Error>.Continuation?
    private var receiveTask: Task<Void, Never>?
    private var receiveStreamEnded = false
    private var inputError: Error?
    private var pendingRequestIDs: Set<FleckMCPWireID> = []
    private var activeRequestIDs: Set<FleckMCPWireID> = []
    private var requestOwners: [FleckMCPWireID: RequestOwner] = [:]
    private var queuedFrames: [ScheduledFrame] = []
    private var modernTasks: [FleckMCPWireID: ModernRequest] = [:]
    private var outputOperations: [UUID: OutputOperation] = [:]
    private var outputOperationForID: [FleckMCPWireID: UUID] = [:]
    private var deferredCancellationIDs: Set<FleckMCPWireID> = []
    private var rejectionTasks: [UUID: Task<Void, Never>] = [:]
    private var rejectionBytes = 0
    private var outputBytesInFlight = 0
    private var legacyInitialized = false
    private var inputEnded = false
    private var drainContinuation: CheckedContinuation<Bool, Never>?
    private var drainToken: UUID?
    private var eofDrainDeadline: ContinuousClock.Instant?
    private var drainTimeoutTask: Task<Void, Never>?
    private var eofHandlerTask: Task<Void, Never>?
    private var inputEndWaiters: [CheckedContinuation<Void, Never>] = []
    private var drainWasAborted = false
    private var outputFailure: String?

    private static let maximumActiveRequestIDs =
      FleckMCPModernDispatcher.maximumConcurrentRequests
    private static let maximumQueuedFrames = 32
    private static let maximumRequestOwners = maximumActiveRequestIDs * (maximumQueuedFrames + 1)
    private static let maximumRejectionFrames = 16
    private static let maximumRejectionBytes = 65_536
    private static let maximumResidentOutputBytes =
      FleckMCPModernDispatcher.maximumBatchResponseBytes
    private static let eofHandlerGrace = Duration.milliseconds(250)
    private static let drainTimeout = Duration.seconds(3)

    init() {
      let transport = FleckMCPBoundedStdioTransport()
      self.transport = transport
      self.logger = transport.logger
      self.modernDispatcher = nil
    }

    init(transport: any Transport) {
      self.transport = transport
      self.logger = Logger(label: "mcp.transport.fleck")
      self.modernDispatcher = nil
    }

    init(
      transport: any Transport,
      modernDispatcher: FleckMCPModernDispatcher
    ) {
      self.transport = transport
      self.logger = Logger(label: "mcp.transport.fleck")
      self.modernDispatcher = modernDispatcher
    }

    var pendingRequestCount: Int { pendingRequestIDs.count }
    var activeRequestIDCount: Int { activeRequestIDs.count }
    var activeModernRequestCount: Int { modernTasks.count }
    var queuedFrameCount: Int { queuedFrames.count }
    var queuedRequestIDCount: Int { queuedFrames.reduce(0) { $0 + $1.requestIDs.count } }
    var pendingOutputByteCount: Int { outputBytesInFlight }
    var outputOperationCount: Int { outputOperations.count }
    var rejectionOutputCount: Int { rejectionTasks.count }
    var requestOwnerCount: Int { requestOwners.count }
    var receiveStreamIsEnded: Bool { receiveStreamEnded }

    func connect() async throws {
      try await transport.connect()
    }

    func disconnect() async {
      await abortDrain()
    }

    func send(_ data: Data) async throws {
      try await send(data, expectedTokens: nil)
    }

    func receive() -> AsyncThrowingStream<Data, Error> {
      if let receiveStream { return receiveStream }
      var continuation: AsyncThrowingStream<Data, Error>.Continuation!
      let stream = AsyncThrowingStream<Data, Error>(
        bufferingPolicy: .bufferingOldest(Self.maximumQueuedFrames)
      ) { continuation = $0 }
      receiveStream = stream
      receiveContinuation = continuation
      let inputTransport = transport
      receiveTask = Task { [weak self] in
        do {
          for try await data in await inputTransport.receive() {
            await self?.route(data)
          }
          await self?.finishInput()
        } catch {
          await self?.finishInput(error)
        }
      }
      return stream
    }

    func waitUntilInputEnded() async {
      guard !inputEnded else { return }
      await withCheckedContinuation { inputEndWaiters.append($0) }
    }

    func waitUntilDrained() async {
      guard !isDrained, !drainWasAborted else { return }
      let timedOut = await withCheckedContinuation { continuation in
        drainContinuation = continuation
        scheduleDrainTimeoutIfNeeded()
      }
      if timedOut, outputFailure == nil {
        outputFailure = String(describing: FleckMCPTransportError.drainTimedOut)
      }
    }

    func throwOutputFailureIfAny() throws {
      if let outputFailure {
        throw FleckMCPTransportError.outputFailed(outputFailure)
      }
    }

    func abortDrain() async {
      guard !drainWasAborted else { return }
      drainWasAborted = true
      inputEnded = true
      receiveTask?.cancel()
      eofHandlerTask?.cancel()
      eofHandlerTask = nil
      drainTimeoutTask?.cancel()
      drainTimeoutTask = nil
      drainToken = nil
      eofDrainDeadline = nil
      receiveStreamEnded = true
      receiveContinuation?.finish()
      resumeInputEndWaiters()
      queuedFrames.removeAll()
      for request in modernTasks.values { request.task.cancel() }
      modernTasks.removeAll()
      for operation in outputOperations.values { operation.task.cancel() }
      outputOperations.removeAll()
      outputOperationForID.removeAll()
      outputBytesInFlight = 0
      for task in rejectionTasks.values { task.cancel() }
      rejectionTasks.removeAll()
      rejectionBytes = 0
      requestOwners.removeAll()
      pendingRequestIDs.removeAll()
      activeRequestIDs.removeAll()
      deferredCancellationIDs.removeAll()
      resumeDrainIfReady()
      await transport.disconnect()
    }

    func recordRequests(in data: Data) async {
      for message in Self.messages(in: data) {
        guard let method = message["method"] as? String else { continue }
        if method == "notifications/cancelled",
          let params = message["params"] as? [String: Any],
          let requestID = FleckMCPWireID.parse(params["requestId"])
        {
          await cancelRequest(requestID)
        } else if let requestID = FleckMCPWireID.parse(message["id"]) {
          guard requestOwners[requestID] == nil,
            requestOwners.count < Self.maximumRequestOwners
          else {
            continue
          }
          registerPendingResponse(requestID, route: .legacy, frameToken: UUID())
        }
      }
    }

    private var isDrained: Bool {
      pendingRequestIDs.isEmpty
        && queuedFrames.isEmpty
        && outputOperations.isEmpty
        && rejectionTasks.isEmpty
    }

    private func route(_ data: Data) async {
      guard !inputEnded, !drainWasAborted else { return }
      guard let modernDispatcher else {
        let ids = Self.requestIDs(in: data)
        await acceptFrame(data, requestIDs: ids, route: .legacy)
        return
      }

      switch FleckMCPModernDispatcher.route(
        data,
        legacyInitialized: legacyInitialized
      ) {
      case .legacy(let requestIDs, let startsLegacySession):
        for message in Self.messages(in: data) {
          guard message["jsonrpc"] as? String == "2.0",
            !message.keys.contains("id"),
            message["method"] as? String == "notifications/cancelled",
            let params = message["params"] as? [String: Any],
            let requestID = FleckMCPWireID.parse(params["requestId"])
          else { continue }
          await cancelRequest(requestID)
        }
        await acceptFrame(
          data,
          requestIDs: requestIDs,
          route: .legacy,
          startsLegacySession: startsLegacySession
        )

      case .notification(let forwardToLegacy, let cancellationID):
        if let cancellationID { await cancelRequest(cancellationID) }
        if forwardToLegacy {
          await acceptFrame(data, requestIDs: [], route: .legacy)
        } else if cancellationID == nil {
          await startReadyFrames()
          resumeDrainIfReady()
        }

      case .modern:
        guard let requestID = Self.requestID(in: data) else {
          if let response = await modernDispatcher.response(for: data) {
            await enqueueRejection(response)
          }
          return
        }
        await acceptFrame(data, requestIDs: [requestID], route: .modern)
      }
    }

    private func acceptFrame(
      _ data: Data,
      requestIDs: [FleckMCPWireID],
      route: ScheduledRoute,
      startsLegacySession: Bool = false
    ) async {
      let isBatch = Self.isBatch(data)
      let uniqueIDs = Self.unique(requestIDs)
      guard requestIDs.count <= Self.maximumActiveRequestIDs,
        uniqueIDs.count == requestIDs.count
      else {
        await enqueueRejection(
          Self.errorResponseFrame(
            for: uniqueIDs,
            isBatch: isBatch,
            code: -32600,
            message: "Invalid Request"
          )
        )
        return
      }
      guard uniqueIDs.allSatisfy({ requestOwners[$0] == nil }) else {
        await enqueueRejection(
          Self.errorResponseFrame(
            for: uniqueIDs,
            isBatch: isBatch,
            code: -32600,
            message: "Invalid Request"
          )
        )
        return
      }
      guard requestOwners.count + uniqueIDs.count <= Self.maximumRequestOwners else {
        await enqueueRejection(
          Self.errorResponseFrame(
            for: uniqueIDs,
            isBatch: isBatch,
            code: -32000,
            message: "Server is busy"
          )
        )
        return
      }
      guard queuedFrames.count < Self.maximumQueuedFrames else {
        if uniqueIDs.isEmpty {
          await failConnection(FleckMCPTransportError.overloaded("request queue is full"))
        } else {
          await enqueueRejection(
            Self.errorResponseFrame(
              for: uniqueIDs,
              isBatch: isBatch,
              code: -32000,
              message: "Server is busy"
            )
          )
        }
        return
      }

      let frameToken = UUID()
      var requestTokens: [FleckMCPWireID: UUID] = [:]
      for id in uniqueIDs {
        let token = UUID()
        requestTokens[id] = token
        requestOwners[id] = RequestOwner(
          token: token,
          frameToken: frameToken,
          route: route
        )
      }
      if startsLegacySession { legacyInitialized = true }
      queuedFrames.append(
        ScheduledFrame(
          token: frameToken,
          data: data,
          requestIDs: uniqueIDs,
          requestTokens: requestTokens,
          route: route,
          isBatch: isBatch
        )
      )
      await startReadyFrames()
    }

    private func startReadyFrames() async {
      guard let receiveContinuation, !drainWasAborted else { return }
      while let first = queuedFrames.first {
        let requestIDs = first.requestIDs.filter {
          requestOwners[$0]?.frameToken == first.token
        }
        guard activeRequestIDs.count + requestIDs.count <= Self.maximumActiveRequestIDs
        else { return }
        queuedFrames.removeFirst()
        for id in requestIDs {
          guard var owner = requestOwners[id], owner.frameToken == first.token else { continue }
          owner.cancelled = false
          requestOwners[id] = owner
          activeRequestIDs.insert(id)
          pendingRequestIDs.insert(id)
        }

        switch first.route {
        case .modern:
          guard requestIDs.count == 1,
            let requestID = requestIDs.first,
            let token = first.requestTokens[requestID],
            let modernDispatcher
          else {
            await failConnection(FleckMCPTransportError.overloaded("invalid scheduled request"))
            return
          }
          startModernRequest(first.data, id: requestID, token: token, dispatcher: modernDispatcher)

        case .legacy:
          switch receiveContinuation.yield(first.data) {
          case .enqueued:
            continue
          case .dropped:
            await failConnection(
              FleckMCPTransportError.overloaded("legacy dispatch buffer is full"))
            return
          case .terminated:
            if !inputEnded {
              await failConnection(FleckMCPTransportError.overloaded("legacy dispatch ended"))
            }
            return
          @unknown default:
            await failConnection(FleckMCPTransportError.overloaded("legacy dispatch failed"))
            return
          }
        }
      }
      finishReceiveStreamIfReady()
    }

    private func startModernRequest(
      _ data: Data,
      id: FleckMCPWireID,
      token: UUID,
      dispatcher: FleckMCPModernDispatcher
    ) {
      let task = Task.detached { [weak self, dispatcher] in
        let response = await dispatcher.response(for: data)
        await self?.finishModernRequest(id, token: token, response: response)
      }
      modernTasks[id] = ModernRequest(
        token: token,
        task: task,
        cancelled: false,
        responseDeliveryPending: false
      )
    }

    private func finishModernRequest(
      _ id: FleckMCPWireID,
      token: UUID,
      response: Data?
    ) async {
      guard let active = modernTasks[id], active.token == token else { return }
      guard let owner = requestOwners[id], owner.token == token,
        !owner.cancelled,
        !Task.isCancelled,
        let response
      else {
        if requestOwners[id]?.cancelled == true, !inputEnded {
          modernTasks.removeValue(forKey: id)
          requestOwners.removeValue(forKey: id)
          pendingRequestIDs.remove(id)
          activeRequestIDs.remove(id)
          await startReadyFrames()
          return
        }
        modernTasks.removeValue(forKey: id)
        await completePendingResponses([id], tokens: [id: token])
        return
      }
      modernTasks[id] = ModernRequest(
        token: token,
        task: active.task,
        cancelled: false,
        responseDeliveryPending: true
      )
      do {
        try await send(response, expectedTokens: [id: token])
      } catch {}
      if modernTasks[id]?.token == token {
        if modernTasks[id]?.cancelled == true, outputBytesInFlight > 0 {
          deferredCancellationIDs.insert(id)
        } else {
          modernTasks.removeValue(forKey: id)
        }
      }
      await startReadyFrames()
    }

    private func cancelRequest(_ id: FleckMCPWireID) async {
      guard let owner = requestOwners[id] else { return }
      if let index = queuedFrames.firstIndex(where: { $0.token == owner.frameToken }) {
        removeQueuedRequest(id, fromFrameAt: index)
        requestOwners.removeValue(forKey: id)
        pendingRequestIDs.remove(id)
        await startReadyFrames()
        resumeDrainIfReady()
        return
      }

      var updatedOwner = owner
      updatedOwner.cancelled = true
      requestOwners[id] = updatedOwner
      if let active = modernTasks[id], active.token == owner.token {
        modernTasks[id] = ModernRequest(
          token: active.token,
          task: active.task,
          cancelled: true,
          responseDeliveryPending: active.responseDeliveryPending
        )
        active.task.cancel()
        if !active.responseDeliveryPending {
          activeRequestIDs.remove(id)
          pendingRequestIDs.remove(id)
        }
      } else {
        pendingRequestIDs.remove(id)
      }
      cancelOutputOperation(for: id)
      await startReadyFrames()
      resumeDrainIfReady()
    }

    private func removeQueuedRequest(_ id: FleckMCPWireID, fromFrameAt index: Int) {
      var frame = queuedFrames[index]
      frame.requestIDs.removeAll { $0 == id }
      frame.requestTokens.removeValue(forKey: id)
      if !frame.isBatch {
        queuedFrames.remove(at: index)
        return
      }
      guard let items = try? JSONSerialization.jsonObject(with: frame.data) as? [Any] else {
        queuedFrames.remove(at: index)
        return
      }
      let remaining = items.filter { item in
        guard let message = item as? [String: Any] else { return true }
        return FleckMCPWireID.parse(message["id"]) != id
      }
      if remaining.isEmpty {
        queuedFrames.remove(at: index)
      } else if let data = try? JSONSerialization.data(
        withJSONObject: remaining,
        options: [.sortedKeys]
      ) {
        frame.data = data
        queuedFrames[index] = frame
      } else {
        queuedFrames.remove(at: index)
      }
    }

    private func send(_ data: Data, expectedTokens: [FleckMCPWireID: UUID]?) async throws {
      let originalData = data
      var prepared = try prepareResponse(data, expectedTokens: expectedTokens)
      guard prepared.data != nil, !prepared.outputIDs.isEmpty else {
        await completePendingResponses(prepared.completionIDs, tokens: prepared.completionTokens)
        return
      }

      while let outputData = prepared.data {
        guard prepared.outputIDs.allSatisfy({ outputOperationForID[$0] == nil }) else {
          outputFailure = String(
            describing: FleckMCPTransportError.overloaded("duplicate response output"))
          await completePendingResponses(prepared.completionIDs, tokens: prepared.completionTokens)
          await abortDrain()
          throw FleckMCPTransportError.outputFailed(outputFailure ?? "duplicate response output")
        }
        guard
          outputBytesInFlight + rejectionBytes + outputData.count
            <= Self.maximumResidentOutputBytes + Self.maximumRejectionBytes
        else {
          outputFailure = String(
            describing: FleckMCPTransportError.overloaded("response output budget exceeded"))
          await completePendingResponses(prepared.completionIDs, tokens: prepared.completionTokens)
          await abortDrain()
          throw FleckMCPTransportError.outputFailed(
            outputFailure ?? "response output budget exceeded")
        }

        let operationID = UUID()
        let writeTask = Task { try await transport.send(outputData) }
        outputBytesInFlight += outputData.count
        outputOperations[operationID] = OutputOperation(
          ids: Set(prepared.outputIDs),
          byteCount: outputData.count,
          task: writeTask
        )
        for id in prepared.outputIDs { outputOperationForID[id] = operationID }

        do {
          try await withTaskCancellationHandler {
            try await writeTask.value
          } onCancel: {
            writeTask.cancel()
          }
          finishOutputOperation(operationID)
          await completePendingResponses(prepared.completionIDs, tokens: prepared.completionTokens)
          return
        } catch is CancellationError {
          finishOutputOperation(operationID)
          let refreshed = try prepareResponse(
            originalData, expectedTokens: prepared.completionTokens)
          guard refreshed.data != nil, !refreshed.outputIDs.isEmpty else {
            await completePendingResponses(
              refreshed.completionIDs, tokens: refreshed.completionTokens)
            return
          }
          guard refreshed.data != outputData || !Task.isCancelled else {
            throw CancellationError()
          }
          prepared = refreshed
        } catch {
          finishOutputOperation(operationID)
          outputFailure = String(describing: error)
          await completePendingResponses(prepared.completionIDs, tokens: prepared.completionTokens)
          await abortDrain()
          throw error
        }
      }
    }

    private func prepareResponse(
      _ data: Data,
      expectedTokens: [FleckMCPWireID: UUID]?
    ) throws -> PreparedResponse {
      let value = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
      let isBatch: Bool
      let messages: [[String: Any]]
      if let batch = value as? [Any] {
        isBatch = true
        guard batch.allSatisfy({ $0 is [String: Any] }) else {
          throw FleckMCPTransportError.invalidResponse
        }
        messages = batch.compactMap { $0 as? [String: Any] }
      } else if let message = value as? [String: Any] {
        isBatch = false
        messages = [message]
      } else {
        throw FleckMCPTransportError.invalidResponse
      }

      if messages.count == 1, let notification = messages.first,
        notification["method"] as? String == "notifications/progress",
        let params = notification["params"] as? [String: Any],
        let id = FleckMCPWireID.parse(params["progressToken"]),
        activeRequestIDs.contains(id),
        let owner = requestOwners[id],
        case .legacy = owner.route,
        !owner.cancelled,
        !drainWasAborted,
        expectedTokens == nil || expectedTokens?[id] == owner.token
      {
        let notificationData = try JSONSerialization.data(
          withJSONObject: notification,
          options: [.sortedKeys]
        )
        guard notificationData.count <= FleckMCPModernDispatcher.maximumResponseBytes else {
          return PreparedResponse(
            data: nil,
            completionIDs: [],
            completionTokens: [id: owner.token],
            outputIDs: []
          )
        }
        return PreparedResponse(
          data: notificationData,
          completionIDs: [],
          completionTokens: [id: owner.token],
          outputIDs: [id]
        )
      }

      var completionTokens: [FleckMCPWireID: UUID] = [:]
      var responseMessages: [(FleckMCPWireID, [String: Any])] = []
      for message in messages {
        guard message["method"] == nil,
          let id = FleckMCPWireID.parse(message["id"]),
          activeRequestIDs.contains(id),
          let owner = requestOwners[id],
          expectedTokens == nil || expectedTokens?[id] == owner.token
        else {
          continue
        }
        completionTokens[id] = owner.token
        if !owner.cancelled, !drainWasAborted { responseMessages.append((id, message)) }
      }
      let completionIDs = Array(completionTokens.keys)
      guard !responseMessages.isEmpty else {
        return PreparedResponse(
          data: nil,
          completionIDs: completionIDs,
          completionTokens: completionTokens,
          outputIDs: []
        )
      }

      let responseIDs = responseMessages.map(\.0)
      let messageObjects = responseMessages.map(\.1)
      let encodedItemByteCounts = try messageObjects.map {
        try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]).count
      }
      var responseData = try Self.encodeResponses(messageObjects, isBatch: isBatch)
      let maximumBytes =
        isBatch || responseMessages.count > 1
        ? FleckMCPModernDispatcher.maximumResponseBytes * responseMessages.count + 16_384
        : FleckMCPModernDispatcher.maximumResponseBytes
      if encodedItemByteCounts.contains(where: {
        $0 > FleckMCPModernDispatcher.maximumResponseBytes
      })
        || responseData.count > maximumBytes
      {
        responseData = try Self.errorResponseData(for: responseIDs, isBatch: isBatch)
      }
      if responseData.count > Self.maximumResidentOutputBytes {
        responseData = try Self.errorResponseData(for: responseIDs, isBatch: isBatch)
      }
      return PreparedResponse(
        data: responseData,
        completionIDs: completionIDs,
        completionTokens: completionTokens,
        outputIDs: responseIDs
      )
    }

    private func enqueueRejection(_ data: Data) async {
      guard !drainWasAborted else { return }
      guard data.count <= FleckMCPModernDispatcher.maximumBatchResponseBytes,
        rejectionTasks.count < Self.maximumRejectionFrames,
        rejectionBytes + data.count <= Self.maximumRejectionBytes
      else {
        await failConnection(FleckMCPTransportError.overloaded("rejection output queue is full"))
        return
      }
      let token = UUID()
      rejectionBytes += data.count
      let task = Task { [weak self] in
        guard let self else { return }
        await self.sendRejection(data, token: token)
      }
      rejectionTasks[token] = task
    }

    private func sendRejection(_ data: Data, token: UUID) async {
      do {
        try await transport.send(data)
        finishRejection(token, byteCount: data.count)
      } catch {
        finishRejection(token, byteCount: data.count)
        guard !(error is CancellationError), !drainWasAborted else { return }
        await failConnection(error)
      }
    }

    private func finishRejection(_ token: UUID, byteCount: Int) {
      rejectionTasks.removeValue(forKey: token)
      rejectionBytes = max(0, rejectionBytes - byteCount)
      resumeDrainIfReady()
    }

    private func finishOutputOperation(_ id: UUID) {
      guard let operation = outputOperations.removeValue(forKey: id) else { return }
      outputBytesInFlight = max(0, outputBytesInFlight - operation.byteCount)
      for requestID in operation.ids where outputOperationForID[requestID] == id {
        outputOperationForID.removeValue(forKey: requestID)
      }
      if outputBytesInFlight == 0 {
        for requestID in deferredCancellationIDs {
          requestOwners.removeValue(forKey: requestID)
          pendingRequestIDs.remove(requestID)
          activeRequestIDs.remove(requestID)
          modernTasks.removeValue(forKey: requestID)
        }
        deferredCancellationIDs.removeAll()
      }
      resumeDrainIfReady()
    }

    private func cancelOutputOperation(for id: FleckMCPWireID) {
      guard let operationID = outputOperationForID[id] else { return }
      outputOperations[operationID]?.task.cancel()
    }

    private func completePendingResponses(
      _ requestIDs: [FleckMCPWireID],
      tokens: [FleckMCPWireID: UUID]? = nil
    ) async {
      for id in requestIDs {
        guard let owner = requestOwners[id],
          tokens == nil || tokens?[id] == owner.token
        else {
          continue
        }
        if owner.cancelled,
          modernTasks[id]?.cancelled == true,
          modernTasks[id]?.responseDeliveryPending == true,
          outputBytesInFlight > 0
        {
          deferredCancellationIDs.insert(id)
          continue
        }
        requestOwners.removeValue(forKey: id)
        pendingRequestIDs.remove(id)
        activeRequestIDs.remove(id)
      }
      await startReadyFrames()
      resumeDrainIfReady()
    }

    private func registerPendingResponse(
      _ id: FleckMCPWireID,
      route: ScheduledRoute,
      frameToken: UUID
    ) {
      let token = UUID()
      requestOwners[id] = RequestOwner(
        token: token,
        frameToken: frameToken,
        route: route
      )
      activeRequestIDs.insert(id)
      pendingRequestIDs.insert(id)
    }

    private func finishInput(_ error: Error? = nil) async {
      guard !inputEnded else { return }
      inputEnded = true
      inputError = error
      let deadline = ContinuousClock.now + Self.drainTimeout
      let token = UUID()
      eofDrainDeadline = deadline
      drainToken = token
      scheduleDrainTimeoutIfNeeded()
      let cancelledIDsWithoutOutput = requestOwners.compactMap { id, owner in
        owner.cancelled && outputOperationForID[id] == nil ? id : nil
      }
      for id in cancelledIDsWithoutOutput {
        requestOwners.removeValue(forKey: id)
        pendingRequestIDs.remove(id)
        activeRequestIDs.remove(id)
        modernTasks.removeValue(forKey: id)
        deferredCancellationIDs.remove(id)
      }
      resumeInputEndWaiters()
      await startReadyFrames()
      scheduleEOFHandlerCleanup()
      resumeDrainIfReady()
    }

    private func scheduleDrainTimeoutIfNeeded() {
      guard let deadline = eofDrainDeadline,
        let token = drainToken,
        drainTimeoutTask == nil
      else {
        return
      }
      drainTimeoutTask = Task.detached { [weak self] in
        let remaining = ContinuousClock.now.duration(to: deadline)
        try? await Task.sleep(for: max(.zero, remaining))
        guard !Task.isCancelled else { return }
        await self?.drainTimedOut(token)
      }
    }

    private func scheduleEOFHandlerCleanup() {
      guard inputEnded, !drainWasAborted, eofHandlerTask == nil else { return }
      eofHandlerTask = Task.detached { [weak self] in
        try? await Task.sleep(for: Self.eofHandlerGrace)
        guard !Task.isCancelled else { return }
        await self?.cancelUnresponsiveModernHandlersAfterEOF()
      }
    }

    private func cancelUnresponsiveModernHandlersAfterEOF() async {
      eofHandlerTask = nil
      guard inputEnded, !drainWasAborted else { return }
      let unfinishedModernIDs = modernTasks.compactMap { id, request in
        request.responseDeliveryPending ? nil : id
      }
      for id in unfinishedModernIDs {
        modernTasks[id]?.task.cancel()
        modernTasks.removeValue(forKey: id)
        requestOwners.removeValue(forKey: id)
        pendingRequestIDs.remove(id)
        activeRequestIDs.remove(id)
      }
      await startReadyFrames()
      resumeDrainIfReady()
      if modernTasks.values.contains(where: { !$0.responseDeliveryPending })
        || queuedFrames.contains(where: { frame in
          if case .modern = frame.route { return true }
          return false
        })
      {
        scheduleEOFHandlerCleanup()
      }
    }

    private func finishReceiveStreamIfReady() {
      guard inputEnded, queuedFrames.isEmpty, !receiveStreamEnded else { return }
      receiveStreamEnded = true
      if let inputError {
        receiveContinuation?.finish(throwing: inputError)
      } else {
        receiveContinuation?.finish()
      }
    }

    private func failConnection(_ error: Error) async {
      if outputFailure == nil { outputFailure = String(describing: error) }
      await abortDrain()
    }

    private func resumeInputEndWaiters() {
      let waiters = inputEndWaiters
      inputEndWaiters.removeAll()
      for waiter in waiters { waiter.resume() }
    }

    private func resumeDrainIfReady() {
      guard isDrained || drainWasAborted else { return }
      eofHandlerTask?.cancel()
      eofHandlerTask = nil
      drainTimeoutTask?.cancel()
      drainTimeoutTask = nil
      drainToken = nil
      eofDrainDeadline = nil
      drainContinuation?.resume(returning: false)
      drainContinuation = nil
    }

    private func drainTimedOut(_ token: UUID) async {
      guard drainToken == token else { return }
      outputFailure = String(describing: FleckMCPTransportError.drainTimedOut)
      drainWasAborted = true
      eofHandlerTask?.cancel()
      eofHandlerTask = nil
      queuedFrames.removeAll()
      for request in modernTasks.values { request.task.cancel() }
      modernTasks.removeAll()
      for operation in outputOperations.values { operation.task.cancel() }
      outputOperations.removeAll()
      outputOperationForID.removeAll()
      outputBytesInFlight = 0
      for task in rejectionTasks.values { task.cancel() }
      rejectionTasks.removeAll()
      rejectionBytes = 0
      requestOwners.removeAll()
      pendingRequestIDs.removeAll()
      activeRequestIDs.removeAll()
      deferredCancellationIDs.removeAll()
      drainTimeoutTask = nil
      drainToken = nil
      eofDrainDeadline = nil
      drainContinuation?.resume(returning: true)
      drainContinuation = nil
      inputEnded = true
      receiveStreamEnded = true
      receiveContinuation?.finish()
      resumeInputEndWaiters()
      await transport.disconnect()
    }

    private nonisolated static func messages(in data: Data) -> [[String: Any]] {
      guard
        let value = try? JSONSerialization.jsonObject(
          with: data,
          options: [.fragmentsAllowed]
        )
      else {
        return []
      }
      if let messages = value as? [[String: Any]] { return messages }
      return (value as? [String: Any]).map { [$0] } ?? []
    }

    private nonisolated static func requestID(in data: Data) -> FleckMCPWireID? {
      guard
        let message = try? JSONSerialization.jsonObject(
          with: data,
          options: [.fragmentsAllowed]
        ) as? [String: Any],
        message["jsonrpc"] as? String == "2.0",
        message["method"] is String,
        message.keys.contains("id")
      else {
        return nil
      }
      return FleckMCPWireID.parse(message["id"])
    }

    private nonisolated static func requestIDs(in data: Data) -> [FleckMCPWireID] {
      messages(in: data).compactMap { message in
        guard message["jsonrpc"] as? String == "2.0",
          message["method"] is String,
          message.keys.contains("id")
        else {
          return nil
        }
        return FleckMCPWireID.parse(message["id"])
      }
    }

    private nonisolated static func isBatch(_ data: Data) -> Bool {
      (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) is [Any]
    }

    private nonisolated static func unique(_ ids: [FleckMCPWireID]) -> [FleckMCPWireID] {
      var seen: Set<FleckMCPWireID> = []
      return ids.filter { seen.insert($0).inserted }
    }

    private nonisolated static func errorResponseFrame(
      for requestIDs: [FleckMCPWireID],
      isBatch: Bool,
      code: Int,
      message: String
    ) -> Data {
      let errors = unique(requestIDs).compactMap { id -> [String: Any]? in
        try? JSONSerialization.jsonObject(
          with: FleckMCPModernDispatcher.errorResponse(id: id, code: code, message: message),
          options: [.fragmentsAllowed]
        ) as? [String: Any]
      }
      guard isBatch || errors.count > 1 else {
        return errors.first.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
          ?? FleckMCPModernDispatcher.errorResponse(
            id: nil,
            code: code,
            message: message
          )
      }
      return (try? JSONSerialization.data(withJSONObject: errors, options: [.sortedKeys]))
        ?? FleckMCPModernDispatcher.errorResponse(id: nil, code: code, message: message)
    }

    private nonisolated static func encodeResponses(
      _ messages: [[String: Any]],
      isBatch: Bool
    ) throws -> Data {
      if isBatch || messages.count > 1 {
        return try JSONSerialization.data(withJSONObject: messages, options: [.sortedKeys])
      }
      guard let message = messages.first else {
        throw FleckMCPTransportError.invalidResponse
      }
      return try JSONSerialization.data(withJSONObject: message, options: [.sortedKeys])
    }

    private nonisolated static func errorResponseData(
      for requestIDs: [FleckMCPWireID],
      isBatch: Bool
    ) throws -> Data {
      let errors = requestIDs.compactMap { id -> [String: Any]? in
        try? JSONSerialization.jsonObject(
          with: FleckMCPModernDispatcher.errorResponse(
            id: id,
            code: -32603,
            message: "Internal error"
          ),
          options: [.fragmentsAllowed]
        ) as? [String: Any]
      }
      if isBatch || errors.count > 1 {
        return try JSONSerialization.data(withJSONObject: errors, options: [.sortedKeys])
      }
      guard let error = errors.first else {
        throw FleckMCPTransportError.invalidResponse
      }
      return try JSONSerialization.data(withJSONObject: error, options: [.sortedKeys])
    }

    private struct RequestOwner {
      let token: UUID
      let frameToken: UUID
      let route: ScheduledRoute
      var cancelled = false
    }

    private struct ScheduledFrame {
      let token: UUID
      var data: Data
      var requestIDs: [FleckMCPWireID]
      var requestTokens: [FleckMCPWireID: UUID]
      let route: ScheduledRoute
      let isBatch: Bool
    }

    private enum ScheduledRoute {
      case modern
      case legacy
    }

    private struct ModernRequest {
      let token: UUID
      let task: Task<Void, Never>
      let cancelled: Bool
      let responseDeliveryPending: Bool
    }

    private struct OutputOperation {
      let ids: Set<FleckMCPWireID>
      let byteCount: Int
      let task: Task<Void, Error>
    }

    private struct PreparedResponse {
      let data: Data?
      let completionIDs: [FleckMCPWireID]
      let completionTokens: [FleckMCPWireID: UUID]
      let outputIDs: [FleckMCPWireID]
    }
  }

  private enum FleckMCPTransportError: Error {
    case drainTimedOut
    case invalidResponse
    case overloaded(String)
    case outputFailed(String)
  }
#endif
