#if os(macOS)
  import Foundation

  struct AgentClientSetup {
    let installedHelperURL: URL
    let profileID: UUID

    var codexCommand: String {
      "codex mcp add motes -- \(shellArgument(installedHelperURL.path)) \(arguments.joined(separator: " "))"
    }

    var claudeCodeCommand: String {
      "claude mcp add --scope user motes -- \(shellArgument(installedHelperURL.path)) \(arguments.joined(separator: " "))"
    }

    var kimiConfiguration: String {
      """
      {
        "mcpServers": {
          "motes": {
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

    private func shellArgument(_ value: String) -> String {
      let safe = CharacterSet.alphanumerics.union(
        CharacterSet(charactersIn: "_@%+=:,./-")
      )
      if value.unicodeScalars.allSatisfy(safe.contains) {
        return value
      }
      return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func jsonString(_ value: String) -> String {
      let encoder = JSONEncoder()
      encoder.outputFormatting = .withoutEscapingSlashes
      return String(decoding: try! encoder.encode(value), as: UTF8.self)
    }
  }
#endif
