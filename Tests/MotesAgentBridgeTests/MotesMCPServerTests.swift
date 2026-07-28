import Foundation
import Logging
import MCP
import MenuBarNotesCore
import Testing

@testable import MotesAgentBridge

@Suite("MotesMCP server")
struct MotesMCPServerTests {
  @Test func advertisesOnlyToolCapabilitiesAtVersionOne() async {
    let server = await MotesMCPServer.makeServer(
      callTool: { _ in
        try MotesMCPToolRegistry.result(
          for: AgentWorkspaceError(code: .invalidOperation)
        )
      }
    )

    #expect(server.name == "motes")
    #expect(server.version == "1.0.0")
    let capabilities = await server.capabilities
    #expect(capabilities.tools?.listChanged == false)
    #expect(capabilities.prompts == nil)
    #expect(capabilities.resources == nil)
    #expect(capabilities.logging == nil)
    #expect(capabilities.completions == nil)
  }

  @Test func registeredHandlersServeToolsOverInMemoryTransport() async throws {
    let server = await MotesMCPServer.makeServer { parameters in
      #expect(parameters.name == "list_shared_notes")
      return try MotesMCPToolRegistry.result(
        for: AgentWorkspaceResponse.sharedNotes(notes: [])
      )
    }
    let transports = await InMemoryTransport.createConnectedPair()
    let client = Client(name: "test", version: "1")

    try await server.start(transport: transports.server)
    _ = try await client.connect(transport: transports.client)
    let listed = try await client.listTools()
    let called = try await client.callTool(
      name: "list_shared_notes",
      arguments: [:]
    )
    await client.disconnect()
    await server.stop()

    #expect(listed.tools.map(\.name) == MotesMCPToolRegistry.tools.map(\.name))
    #expect(called.isError == false)
  }

  @Test func canceledSingleAndBatchRequestsDoNotBlockEOFDrain() async {
    let transport = MotesStdioTransport(transport: FailingSendTransport())
    let messages = [
      (
        #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"slow"}}"#,
        #"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":7}}"#
      ),
      (
        #"[{"jsonrpc":"2.0","id":"batch","method":"tools/call","params":{"name":"slow"}}]"#,
        #"[{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":"batch"}}]"#
      ),
    ]

    for (request, cancellation) in messages {
      await transport.recordRequests(in: Data(request.utf8))
      #expect(await transport.pendingRequestCount == 1)
      await transport.recordRequests(in: Data(cancellation.utf8))
      #expect(await transport.pendingRequestCount == 0)
      await transport.waitUntilDrained()
    }
  }

  @Test func arrayParametersStillTrackSingleAndBatchRequestIDs() async {
    let transport = MotesStdioTransport(transport: FailingSendTransport())
    let messages = [
      (
        #"{"jsonrpc":"2.0","id":11,"method":"custom/request","params":[1,2,3]}"#,
        #"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":11}}"#
      ),
      (
        #"[{"jsonrpc":"2.0","id":"array-batch","method":"custom/request","params":["value"]}]"#,
        #"[{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":"array-batch"}}]"#
      ),
    ]

    for (request, cancellation) in messages {
      await transport.recordRequests(in: Data(request.utf8))
      #expect(await transport.pendingRequestCount == 1)
      await transport.recordRequests(in: Data(cancellation.utf8))
      #expect(await transport.pendingRequestCount == 0)
      await transport.waitUntilDrained()
    }
  }

  @Test func failedResponseSendStillResolvesPendingRequest() async {
    let transport = MotesStdioTransport(transport: FailingSendTransport())
    await transport.recordRequests(
      in: Data(
        #"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"slow"}}"#
          .utf8
      )
    )

    await #expect(throws: TestTransportError.self) {
      try await transport.send(
        Data(#"{"jsonrpc":"2.0","id":9,"result":{}}"#.utf8)
      )
    }
    #expect(await transport.pendingRequestCount == 0)
    await transport.waitUntilDrained()
  }
}

private enum TestTransportError: Error {
  case sendFailed
}

private actor FailingSendTransport: Transport {
  nonisolated let logger = Logger(label: "motes.mcp.test")

  func connect() {}

  func disconnect() {}

  func send(_ data: Data) throws {
    throw TestTransportError.sendFailed
  }

  func receive() -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { $0.finish() }
  }
}
