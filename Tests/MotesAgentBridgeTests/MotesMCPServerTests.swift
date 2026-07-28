import Foundation
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
}
