#if os(macOS)
  import Darwin
  import Dispatch
  import Foundation
  import Logging
  import MCP

  enum MotesMCPServer {
    typealias ToolHandler =
      @Sendable (CallTool.Parameters) async throws -> CallTool.Result

    static func makeServer(
      callTool: @escaping ToolHandler
    ) async -> Server {
      let server = Server(
        name: "motes",
        version: "1.0.0",
        capabilities: .init(tools: .init(listChanged: false))
      )
      await server.withMethodHandler(ListTools.self) { _ in
        ListTools.Result(tools: MotesMCPToolRegistry.tools)
      }
      await server.withMethodHandler(CallTool.self, handler: callTool)
      return server
    }

    static func run(profileID: UUID) async throws {
      let server = await makeServer { parameters in
        MotesMCPToolRegistry.call(parameters, profileID: profileID)
      }
      let transport = MotesStdioTransport()

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
      transport: MotesStdioTransport
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

  private actor MotesStdioTransport: Transport {
    nonisolated let logger: Logger

    private let transport: StdioTransport
    private var pendingRequestIDs: Set<ID> = []
    private var drainContinuation: CheckedContinuation<Void, Never>?
    private var drainWasAborted = false

    init() {
      let transport = StdioTransport()
      self.transport = transport
      self.logger = transport.logger
    }

    func connect() async throws {
      try await transport.connect()
    }

    func disconnect() async {
      await transport.disconnect()
    }

    func send(_ data: Data) async throws {
      try await transport.send(data)
      for id in Self.messageIDs(in: data, requiringMethod: false) {
        pendingRequestIDs.remove(id)
      }
      resumeDrainIfReady()
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

    private func recordRequests(in data: Data) {
      pendingRequestIDs.formUnion(
        Self.messageIDs(in: data, requiringMethod: true)
      )
    }

    private func resumeDrainIfReady() {
      guard pendingRequestIDs.isEmpty || drainWasAborted else { return }
      drainContinuation?.resume()
      drainContinuation = nil
    }

    private nonisolated static func messageIDs(
      in data: Data,
      requiringMethod: Bool
    ) -> [ID] {
      let decoder = JSONDecoder()
      let messages =
        (try? decoder.decode([WireMessage].self, from: data))
        ?? (try? decoder.decode(WireMessage.self, from: data)).map { [$0] }
        ?? []
      return messages.compactMap { message in
        guard !requiringMethod || message.method != nil else { return nil }
        return message.id
      }
    }
  }

  private struct WireMessage: Decodable {
    let id: ID?
    let method: String?
  }
#endif
