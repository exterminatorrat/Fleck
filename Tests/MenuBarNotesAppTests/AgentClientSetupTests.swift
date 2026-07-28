import Foundation
import Testing

@testable import MenuBarNotesApp

@Suite("AgentClientSetup")
struct AgentClientSetupTests {
  private let profileID = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!

  @Test func generatesCurrentClientSetupFormats() {
    let setup = AgentClientSetup(
      installedHelperURL: URL(fileURLWithPath: "/absolute/path/to/motes"),
      profileID: profileID
    )

    #expect(
      setup.codexCommand
        == "codex mcp add motes -- /absolute/path/to/motes mcp --profile \(profileID.uuidString)"
    )
    #expect(
      setup.claudeCodeCommand
        == "claude mcp add --scope user motes -- /absolute/path/to/motes mcp --profile \(profileID.uuidString)"
    )
    #expect(
      setup.kimiConfiguration
        == """
        {
          "mcpServers": {
            "motes": {
              "command": "/absolute/path/to/motes",
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
          "command": "/absolute/path/to/motes",
          "args": ["mcp", "--profile", "\(profileID.uuidString)"]
        }
        """
    )
  }

  @Test func escapesShellAndJSONSpecialCharactersWithoutCredentials() {
    let helperPath = "/Users/Test User/Mote's \"Bridge\"/motes"
    let setup = AgentClientSetup(
      installedHelperURL: URL(fileURLWithPath: helperPath),
      profileID: profileID
    )

    #expect(
      setup.codexCommand
        == "codex mcp add motes -- '/Users/Test User/Mote'\\''s \"Bridge\"/motes' mcp --profile \(profileID.uuidString)"
    )
    #expect(
      setup.claudeCodeCommand
        == "claude mcp add --scope user motes -- '/Users/Test User/Mote'\\''s \"Bridge\"/motes' mcp --profile \(profileID.uuidString)"
    )
    #expect(
      setup.kimiConfiguration.contains(#""command": "/Users/Test User/Mote's \"Bridge\"/motes""#))
    #expect(
      setup.genericConfiguration.contains(#""command": "/Users/Test User/Mote's \"Bridge\"/motes""#)
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
