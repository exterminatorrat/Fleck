#if os(macOS)
  import Darwin
  import Dispatch
  import Foundation
  import Logging
  import MCP

  enum FleckMCPServer {
    typealias ToolListHandler = @Sendable () async throws -> [Tool]
    typealias ToolHandler =
      @Sendable (CallTool.Parameters) async throws -> CallTool.Result

    static func makeServer(
      listTools: @escaping ToolListHandler,
      callTool: @escaping ToolHandler
    ) async -> Server {
      let server = Server(
        name: "fleck",
        version: "1.0.0",
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
      let server = await makeServer(
        listTools: {
          FleckMCPToolRegistry.tools(for: try client.capabilities())
        },
        callTool: { parameters in
          FleckMCPToolRegistry.call(parameters, client: client)
        }
      )
      let transport = FleckStdioTransport()

      try await server.start(transport: transport)
      let signals = terminationSignals(for: server, transport: transport)
      await server.waitUntilCompleted()
      await transport.waitUntilDrained()
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
    private var pendingRequestIDs: Set<ID> = []
    private var drainContinuation: CheckedContinuation<Void, Never>?
    private var drainWasAborted = false

    init() {
      let transport = StdioTransport()
      self.transport = transport
      self.logger = transport.logger
    }

    init(transport: any Transport) {
      self.transport = transport
      self.logger = Logger(label: "mcp.transport.fleck")
    }

    var pendingRequestCount: Int { pendingRequestIDs.count }

    func connect() async throws {
      try await transport.connect()
    }

    func disconnect() async {
      await transport.disconnect()
    }

    func send(_ data: Data) async throws {
      let responseIDs = Self.messages(in: data).compactMap(\.id)
      defer {
        pendingRequestIDs.subtract(responseIDs)
        resumeDrainIfReady()
      }
      try await transport.send(data)
    }

    func receive() -> AsyncThrowingStream<Data, Error> {
      AsyncThrowingStream { continuation in
        Task {
          do {
            let messages = await transport.receive()
            for try await data in messages {
              self.recordRequests(in: data)
              continuation.yield(data)
            }
            continuation.finish()
          } catch {
            continuation.finish(throwing: error)
          }
        }
      }
    }

    func waitUntilDrained() async {
      guard !pendingRequestIDs.isEmpty, !drainWasAborted else { return }
      await withCheckedContinuation { continuation in
        drainContinuation = continuation
      }
    }

    func abortDrain() {
      drainWasAborted = true
      resumeDrainIfReady()
    }

    func recordRequests(in data: Data) {
      for message in Self.messages(in: data) {
        if message.method == CancelledNotification.name,
          let requestID = Self.id(
            from: message.params?.objectValue?["requestId"]
          )
        {
          pendingRequestIDs.remove(requestID)
        } else if message.method != nil, let requestID = message.id {
          pendingRequestIDs.insert(requestID)
        }
      }
      resumeDrainIfReady()
    }

    private func resumeDrainIfReady() {
      guard pendingRequestIDs.isEmpty || drainWasAborted else { return }
      drainContinuation?.resume()
      drainContinuation = nil
    }

    private nonisolated static func messages(in data: Data) -> [WireMessage] {
      let decoder = JSONDecoder()
      return
        (try? decoder.decode([WireMessage].self, from: data))
        ?? (try? decoder.decode(WireMessage.self, from: data)).map { [$0] }
        ?? []
    }

    private nonisolated static func id(from value: Value?) -> ID? {
      if let string = value?.stringValue { return .string(string) }
      if let number = value?.intValue { return .number(number) }
      return nil
    }
  }

  private struct WireMessage: Decodable {
    let id: ID?
    let method: String?
    let params: Value?
  }
#endif
