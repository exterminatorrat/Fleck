#if os(macOS)
  import Foundation

  struct AgentClientSetup {
    let installedHelperURL: URL
    let profileID: UUID

    var codexCommand: String {
      "codex mcp add fleck -- \(ShellArgument.encode(installedHelperURL.path)) \(arguments.joined(separator: " "))"
    }

    var claudeCodeCommand: String {
      "claude mcp add --scope user fleck -- \(ShellArgument.encode(installedHelperURL.path)) \(arguments.joined(separator: " "))"
    }

    var kimiConfiguration: String {
      """
      {
        "mcpServers": {
          "fleck": {
            "command": \(jsonString(installedHelperURL.path)),
            "args": [\(arguments.map(jsonString).joined(separator: ", "))]
          }
        }
      }
      """
    }

    var genericConfiguration: String {
      """
      {
        "command": \(jsonString(installedHelperURL.path)),
        "args": [\(arguments.map(jsonString).joined(separator: ", "))]
      }
      """
    }

    private var arguments: [String] {
      ["mcp", "--profile", profileID.uuidString]
    }

    private func jsonString(_ value: String) -> String {
      let encoder = JSONEncoder()
      encoder.outputFormatting = .withoutEscapingSlashes
      return String(decoding: try! encoder.encode(value), as: UTF8.self)
    }
  }
#endif
