import Foundation
import Testing

@testable import FleckApp

@Suite("AgentConnectionPrompt")
struct AgentConnectionPromptTests {
  private let profileID = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!
  private let helperPath = "/Applications/Fleck/fleck"

  private func clientSetup(helperPath: String) -> AgentClientSetup {
    AgentClientSetup(
      installedHelperURL: URL(fileURLWithPath: helperPath),
      profileID: profileID
    )
  }

  private func embeddedDocument(in prompt: String) throws -> [String: Any] {
    let start = try #require(prompt.range(of: "```json\n"))
    let end = try #require(
      prompt.range(of: "\n```", options: [], range: start.upperBound..<prompt.endIndex)
    )
    let json = String(prompt[start.upperBound..<end.lowerBound])
    return try #require(
      JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
    )
  }

  @Test func serverNameIsTheLowercasedProfileIdentifier() {
    #expect(
      clientSetup(helperPath: helperPath).connectionServerName
        == "fleck-01234567-89ab-cdef-0123-456789abcdef"
    )
  }

  @Test func everyIntegrationProducesADistinctPrompt() throws {
    let clientSetup = self.clientSetup(helperPath: helperPath)
    var prompts: [String] = []
    for integration in AgentIntegrationKind.allCases {
      let prompt = try #require(clientSetup.connectionPrompt(for: integration))
      prompts.append(prompt)
      #expect(prompt.contains(clientSetup.connectionServerName))
      #expect(prompt.contains("mcp --profile \(profileID.uuidString)"))
      #expect(prompt.contains(helperPath))
    }
    #expect(Set(prompts).count == AgentIntegrationKind.allCases.count)
  }

  @Test func everyPromptEmbedsTheExactStdioConfiguration() throws {
    let clientSetup = self.clientSetup(helperPath: helperPath)
    for integration in AgentIntegrationKind.allCases {
      let prompt = try #require(clientSetup.connectionPrompt(for: integration))
      let document = try embeddedDocument(in: prompt)
      #expect(Set(document.keys) == ["mcpServers"])
      let servers = try #require(document["mcpServers"] as? [String: Any])
      #expect(Set(servers.keys) == [clientSetup.connectionServerName])
      let server = try #require(servers[clientSetup.connectionServerName] as? [String: Any])
      #expect(Set(server.keys) == ["args", "command"])
      #expect(server["command"] as? String == helperPath)
      #expect(
        server["args"] as? [String] == ["mcp", "--profile", profileID.uuidString]
      )
      #expect(server["env"] == nil)
      #expect(server["headers"] == nil)
    }
  }

  @Test func codexAndClaudeCodePromptsUseKnownCommandsWithTheUniqueName() throws {
    let clientSetup = self.clientSetup(helperPath: helperPath)
    let serverName = clientSetup.connectionServerName
    let codexPrompt = try #require(clientSetup.connectionPrompt(for: .codex))
    let claudePrompt = try #require(clientSetup.connectionPrompt(for: .claudeCode))
    let arguments = "mcp --profile \(profileID.uuidString)"

    #expect(
      codexPrompt.contains("codex mcp add \(serverName) -- \(helperPath) \(arguments)")
    )
    #expect(!codexPrompt.contains("claude mcp add"))
    #expect(
      claudePrompt.contains(
        "claude mcp add --scope user \(serverName) -- \(helperPath) \(arguments)"
      )
    )
    #expect(!claudePrompt.contains("codex mcp add"))
  }

  @Test func kimiPromptUsesAMcpServersEntryWithoutShellCommands() throws {
    let clientSetup = self.clientSetup(helperPath: helperPath)
    let prompt = try #require(clientSetup.connectionPrompt(for: .kimi))

    #expect(prompt.contains("Kimi"))
    #expect(prompt.contains("\"mcpServers\""))
    #expect(!prompt.contains("codex mcp add"))
    #expect(!prompt.contains("claude mcp add"))
  }

  @Test func genericPromptCoversCapyLocalStdioSetupWithoutInventingCommands() throws {
    let clientSetup = self.clientSetup(helperPath: helperPath)
    let prompt = try #require(clientSetup.connectionPrompt(for: .genericCLI))
    let lowered = prompt.lowercased()

    #expect(prompt.contains("Capy"))
    #expect(lowered.contains("local stdio"))
    #expect(lowered.contains("import"))
    #expect(lowered.contains("approve"))
    #expect(!lowered.contains("capy mcp"))
    #expect(!lowered.contains("capy cli"))
    #expect(!prompt.contains("codex mcp add"))
    #expect(!prompt.contains("claude mcp add"))
  }

  @Test func promptsStateScopeApprovalAndVerificationLimits() throws {
    let clientSetup = self.clientSetup(helperPath: helperPath)
    let requiredSnippets = [
      "same macOS user account",
      "cannot start or reach it",
      "Preserve unrelated settings and existing MCP servers",
      "reuse that entry and do not add a duplicate",
      "ask before replacing it",
      "Ask the user for approval",
      "Do not install software",
      "a new profile can read no notes",
      "grant only the notes and capabilities",
      "Restart the agent",
      "Do not open or read note contents",
      "saved configuration alone",
      "only after the server responds",
    ]

    for integration in AgentIntegrationKind.allCases {
      let prompt = try #require(clientSetup.connectionPrompt(for: integration))
      for snippet in requiredSnippets {
        #expect(prompt.contains(snippet))
      }
    }
  }

  @Test func promptsCarryNoCredentialPayloadOrNetworkFallback() throws {
    let clientSetup = self.clientSetup(helperPath: helperPath)
    let forbidden = [
      "authorization",
      "bearer",
      "api key",
      "api_key",
      "apikey",
      "password",
      "secret",
      "\"env\"",
      "\"headers\"",
      "http://",
      "https://",
      "://",
      "tunnel",
      "ngrok",
      "cloudflared",
    ]

    for integration in AgentIntegrationKind.allCases {
      let prompt = try #require(clientSetup.connectionPrompt(for: integration))
      let lowered = prompt.lowercased()
      for marker in forbidden {
        #expect(!lowered.contains(marker))
      }
    }
  }

  @Test func promptsEscapeQuotesSpacesUnicodeAndNewlinesInTheHelperPath() throws {
    let trickyPath = "/tmp/测试 folder/line\nbreak/quote'\"$`/fleck"
    let clientSetup = self.clientSetup(helperPath: trickyPath)

    for integration in AgentIntegrationKind.allCases {
      let prompt = try #require(clientSetup.connectionPrompt(for: integration))
      let document = try embeddedDocument(in: prompt)
      let servers = try #require(document["mcpServers"] as? [String: Any])
      let server = try #require(servers[clientSetup.connectionServerName] as? [String: Any])
      #expect(server["command"] as? String == trickyPath)
    }

    let codexPrompt = try #require(clientSetup.connectionPrompt(for: .codex))
    #expect(codexPrompt.contains("'/tmp/测试 folder/line\nbreak/quote'\\''\"$`/fleck'"))
  }

  @Test func promptsRejectInvalidOrNonlocalHelperURLs() {
    let helperURLs = [
      URL(string: "https://example.test/fleck")!,
      URL(string: "file://example.test/tmp/fleck")!,
      URL(string: "file://user:placeholder@localhost/tmp/fleck")!,
      URL(string: "file:///tmp/fleck?mode=unsafe")!,
      URL(string: "file:///tmp/fleck#fragment")!,
      URL(string: "file:relative/fleck")!,
    ]

    for helperURL in helperURLs {
      let setup = AgentClientSetup(
        installedHelperURL: helperURL,
        profileID: profileID
      )
      for integration in AgentIntegrationKind.allCases {
        #expect(setup.connectionPrompt(for: integration) == nil)
      }
    }
  }
}
