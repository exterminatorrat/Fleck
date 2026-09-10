import Foundation
import Logging
import MCP
import FleckCore
import Testing

@testable import FleckAgentBridge

@Suite("FleckMCP server")
struct FleckMCPServerTests {
  @Test func advertisesOnlyToolCapabilitiesAtVersionOne() async {
    let server = await FleckMCPServer.makeServer(
      listTools: { FleckMCPToolRegistry.tools },
      callTool: { _ in
        try FleckMCPToolRegistry.result(
          for: AgentWorkspaceError(code: .invalidOperation)
        )
      }
    )

    #expect(server.name == "fleck")
    #expect(server.version == "1.0.0")
    let capabilities = await server.capabilities
    #expect(capabilities.tools?.listChanged == false)
    #expect(capabilities.prompts == nil)
    #expect(capabilities.resources == nil)
    #expect(capabilities.logging == nil)
    #expect(capabilities.completions == nil)
  }

  @Test func registeredHandlersServeToolsOverInMemoryTransport() async throws {
    let server = await FleckMCPServer.makeServer(
      listTools: { FleckMCPToolRegistry.tools },
      callTool: { parameters in
        #expect(parameters.name == "list_shared_notes")
        return try FleckMCPToolRegistry.result(
          for: AgentWorkspaceResponse.sharedNotes(notes: [])
        )
      }
    )
    let transports = await InMemoryTransport.createConnectedPair()
    let client = Client(name: "test", version: "1")

    try await server.start(transport: transports.server)
    _ = try await client.connect(transport: transports.client)
    let listed = try await client.listTools()
    let iconIgnoringTools = try JSONDecoder().decode(
      [IconIgnoringTool].self,
      from: JSONEncoder().encode(listed.tools)
    )
    let called = try await client.callTool(
      name: try #require(iconIgnoringTools.first).name,
      arguments: [:]
    )
    await client.disconnect()
    await server.stop()

    #expect(listed.tools.map(\.name) == FleckMCPToolRegistry.tools.map(\.name))
    #expect(iconIgnoringTools.map(\.name) == listed.tools.map(\.name))
    #expect(
      listed.tools.allSatisfy {
        $0.icons == FleckMCPToolRegistry.tools.first?.icons
          && $0.icons?.count == 1
      }
    )
    #expect(called.isError == false)
  }

  @Test func listToolsRecomputesCurrentCapabilitiesForEveryRequest() async throws {
    let summaries = SummarySequence([
      AgentCapabilitySummary(
        grantRevision: 1,
        availableCapabilities: [.listNotes, .readNotes]
      ),
      AgentCapabilitySummary(
        grantRevision: 2,
        availableCapabilities: Set(AgentCapability.allCases)
      ),
    ])
    let server = await FleckMCPServer.makeServer(
      listTools: {
        FleckMCPToolRegistry.tools(for: await summaries.next())
      },
      callTool: { _ in
        try FleckMCPToolRegistry.result(
          for: AgentWorkspaceError(code: .invalidOperation)
        )
      }
    )
    let transports = await InMemoryTransport.createConnectedPair()
    let client = Client(name: "test", version: "1")

    try await server.start(transport: transports.server)
    _ = try await client.connect(transport: transports.client)
    let first = try await client.listTools()
    let second = try await client.listTools()
    await client.disconnect()
    await server.stop()

    #expect(
      first.tools.map(\.name) == [
        "list_shared_notes",
        "read_note",
        "list_tasks",
        "list_agent_activity",
      ]
    )
    #expect(second.tools.map(\.name) == FleckMCPToolRegistry.tools.map(\.name))
  }

  @Test func canceledSingleAndBatchRequestsDoNotBlockEOFDrain() async {
    let transport = FleckStdioTransport(transport: FailingSendTransport())
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
    let transport = FleckStdioTransport(transport: FailingSendTransport())
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
    let transport = FleckStdioTransport(transport: FailingSendTransport())
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

private struct IconIgnoringTool: Decodable {
  let name: String
}

private enum TestTransportError: Error {
  case sendFailed
}

private actor SummarySequence {
  private var summaries: [AgentCapabilitySummary]

  init(_ summaries: [AgentCapabilitySummary]) {
    self.summaries = summaries
  }

  func next() -> AgentCapabilitySummary {
    summaries.removeFirst()
  }
}

private actor FailingSendTransport: Transport {
  nonisolated let logger = Logger(label: "fleck.mcp.test")

  func connect() {}

  func disconnect() {}

  func send(_ data: Data) throws {
    throw TestTransportError.sendFailed
  }

  func receive() -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { $0.finish() }
  }
}
