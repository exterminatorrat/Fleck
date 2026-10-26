import Foundation
import Testing

@testable import FleckApp

@Suite("AgentClientSetup")
struct AgentClientSetupTests {
  private let profileID = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!

  @Test func newClientSetupUsesFleckNamesAndPath() {
    let setup = AgentClientSetup(
      installedHelperURL: URL(fileURLWithPath: "/absolute/path/to/fleck"),
      profileID: profileID
    )

    #expect(
      setup.codexCommand
        == "codex mcp add fleck -- /absolute/path/to/fleck mcp --profile \(profileID.uuidString)"
    )
    #expect(
      setup.claudeCodeCommand
        == "claude mcp add --scope user fleck -- /absolute/path/to/fleck mcp --profile \(profileID.uuidString)"
    )
    #expect(
      setup.kimiConfiguration
        == """
        {
          "mcpServers": {
            "fleck": {
              "command": "/absolute/path/to/fleck",
              "args": ["mcp", "--profile", "\(profileID.uuidString)"]
            }
          }
        }
        """
    )
    #expect(
      setup.genericConfiguration
        == """
        {
          "command": "/absolute/path/to/fleck",
          "args": ["mcp", "--profile", "\(profileID.uuidString)"]
        }
        """
    )
  }

  @Test func escapesShellAndJSONSpecialCharactersWithoutCredentials() {
    let helperPath = "/Users/Test User/Fleck's \"Bridge\"/fleck"
    let setup = AgentClientSetup(
      installedHelperURL: URL(fileURLWithPath: helperPath),
      profileID: profileID
    )

    #expect(
      setup.codexCommand
        == "codex mcp add fleck -- '/Users/Test User/Fleck'\\''s \"Bridge\"/fleck' mcp --profile \(profileID.uuidString)"
    )
    #expect(
      setup.claudeCodeCommand
        == "claude mcp add --scope user fleck -- '/Users/Test User/Fleck'\\''s \"Bridge\"/fleck' mcp --profile \(profileID.uuidString)"
    )
    #expect(
      setup.kimiConfiguration.contains(#""command": "/Users/Test User/Fleck's \"Bridge\"/fleck""#))
    #expect(
      setup.genericConfiguration.contains(#""command": "/Users/Test User/Fleck's \"Bridge\"/fleck""#)
    )
    for snippet in [
      setup.codexCommand,
      setup.claudeCodeCommand,
      setup.kimiConfiguration,
      setup.genericConfiguration,
    ] {
      #expect(!snippet.contains("token"))
      #expect(!snippet.contains("credential"))
    }
  }

  @Test func cursorInstallLinkUsesDocumentedLocalStdioContract() throws {
    let helper = URL(fileURLWithPath: "/Applications/Fleck Local/fleck")
    let setup = AgentClientSetup(installedHelperURL: helper, profileID: profileID)
    let installURL = try #require(setup.cursorInstallURL)
    let components = try #require(
      URLComponents(url: installURL, resolvingAgainstBaseURL: false)
    )

    #expect(components.scheme == "cursor")
    #expect(components.host == "anysphere.cursor-deeplink")
    #expect(components.path == "/mcp/install")

    let queryItems = try #require(components.queryItems)
    let query = Dictionary(
      uniqueKeysWithValues: queryItems.compactMap { item in
        item.value.map { (item.name, $0) }
      }
    )
    #expect(Set(query.keys) == ["name", "config"])
    #expect(query["name"] == "fleck-\(profileID.uuidString.lowercased())")
    #expect(setup.cursorInstallURL == AgentClientSetup(
      installedHelperURL: helper,
      profileID: profileID
    ).cursorInstallURL)

    let encodedConfiguration = try #require(query["config"])
    let configurationData = try #require(Data(base64Encoded: encodedConfiguration))
    let configuration = try #require(
      JSONSerialization.jsonObject(with: configurationData) as? [String: Any]
    )
    #expect(Set(configuration.keys) == ["args", "command", "type"])
    #expect(configuration["type"] as? String == "stdio")
    #expect(configuration["command"] as? String == helper.path)
    #expect(configuration["args"] as? [String] == ["mcp", "--profile", profileID.uuidString])
  }

  @Test func cursorInstallConfigPreservesUnicodeAndPunctuationPaths() throws {
    let helper = URL(fileURLWithPath: "/tmp/测试 folder/quote'\"?/tilde~/fleck")
    let installURL = try #require(
      AgentClientSetup(installedHelperURL: helper, profileID: profileID).cursorInstallURL
    )
    let components = try #require(
      URLComponents(url: installURL, resolvingAgainstBaseURL: false)
    )
    let queryItems = try #require(components.queryItems)
    let query = Dictionary(
      uniqueKeysWithValues: queryItems.compactMap { item in
        item.value.map { (item.name, $0) }
      }
    )
    let encodedConfiguration = try #require(query["config"])
    let configurationData = try #require(Data(base64Encoded: encodedConfiguration))
    let configuration = try #require(
      JSONSerialization.jsonObject(with: configurationData) as? [String: Any]
    )

    #expect(configuration["command"] as? String == helper.path)
    #expect(configuration["env"] == nil)
    #expect(configuration["headers"] == nil)
    #expect(configuration["token"] == nil)
    #expect(configuration["credential"] == nil)
  }

  @Test func cursorInstallLinkPercentEncodesBase64ReservedCharacters() throws {
    let repeatedQuestionMarks = String(repeating: "?", count: 12)
    let repeatedTildes = String(repeating: "~", count: 12)
    let rawQueries = (0..<3).compactMap { padding in
      let suffix = String(repeating: "x", count: padding)
      let helper = URL(
        fileURLWithPath: "/tmp/\(repeatedQuestionMarks)\(repeatedTildes)\(suffix)/fleck"
      )
      guard
        let installURL = AgentClientSetup(
          installedHelperURL: helper,
          profileID: profileID
        ).cursorInstallURL
      else { return nil }
      return URLComponents(url: installURL, resolvingAgainstBaseURL: false)?.percentEncodedQuery
    }

    #expect(
      rawQueries.contains {
        $0.contains("%2B") && $0.contains("%2F") && $0.contains("%3D")
      }
    )
  }

  @Test func cursorManualConfigurationIsMergeableWhitelistedJSON() throws {
    let helper = URL(fileURLWithPath: "/tmp/测试 folder/quote'\"?/fleck")
    let setup = AgentClientSetup(installedHelperURL: helper, profileID: profileID)
    let configurationText = try #require(setup.cursorManualConfiguration)
    let configuration = try #require(
      JSONSerialization.jsonObject(with: Data(configurationText.utf8)) as? [String: Any]
    )
    let servers = try #require(configuration["mcpServers"] as? [String: Any])
    let serverName = "fleck-\(profileID.uuidString.lowercased())"
    let server = try #require(servers[serverName] as? [String: Any])

    #expect(Set(configuration.keys) == ["mcpServers"])
    #expect(Set(servers.keys) == [serverName])
    #expect(Set(server.keys) == ["args", "command", "type"])
    #expect(server["type"] as? String == "stdio")
    #expect(server["command"] as? String == helper.path)
    #expect(server["args"] as? [String] == ["mcp", "--profile", profileID.uuidString])
    #expect(!configurationText.lowercased().contains("token"))
    #expect(!configurationText.lowercased().contains("credential"))
    #expect(!configurationText.contains("\"env\""))
    #expect(!configurationText.contains("\"headers\""))
    #expect(
      setup.cursorManualConfiguration
        == AgentClientSetup(installedHelperURL: helper, profileID: profileID)
          .cursorManualConfiguration
    )
  }

  @Test func cursorInstallLinkRejectsNonlocalOrUnsafeHelperURLs() {
    for helperURL in [
      URL(string: "https://example.test/fleck")!,
      URL(string: "file://example.test/tmp/fleck")!,
      URL(string: "file://user:placeholder@localhost/tmp/fleck")!,
      URL(string: "file:///tmp/fleck?mode=unsafe")!,
      URL(string: "file:///tmp/fleck#fragment")!,
      URL(string: "file:relative/fleck")!,
    ] {
      #expect(AgentClientSetup(installedHelperURL: helperURL, profileID: profileID).cursorInstallURL == nil)
    }
  }
}
