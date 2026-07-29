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
}
