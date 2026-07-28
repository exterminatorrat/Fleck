#if os(macOS)
  import Darwin
  import Foundation
  import MenuBarNotesAgentProtocol
  import MenuBarNotesCore

  @main
  enum MotesAgentBridge {
    static func main() {
      let stdin = StdinReader()
      let arguments = Array(CommandLine.arguments.dropFirst())
      do {
        let command = try BridgeCommand.parse(arguments: arguments) {
          try stdin.read()
        }
        Task {
          Darwin.exit(await run(command, stdin: stdin))
        }
        dispatchMain()
      } catch let error as BridgeParseError {
        write("\(error.description)\n", to: .standardError)
        Darwin.exit(error.exitCode)
      } catch {
        write("motes-agent failed.\n", to: .standardError)
        Darwin.exit(1)
      }
    }

    private static func run(
      _ command: BridgeCommand,
      stdin: StdinReader,
      credentialStore: BridgeCredentialStore = BridgeCredentialStore(),
      client: AgentIPCClient = AgentIPCClient()
    ) async -> Int32 {
      switch command {
      case .help:
        write(BridgeOutput.help + "\n", to: .standardOutput)
        return 0
      case .configure(let profileID):
        do {
          try credentialStore.store(
            profileID: profileID,
            canonicalBase64: try stdin.read()
          )
          write("Configured profile \(profileID.uuidString).\n", to: .standardOutput)
          return 0
        } catch {
          write("Could not configure the profile.\n", to: .standardError)
          return 1
        }
      case .disconnect(let profileID):
        do {
          try credentialStore.delete(profileID: profileID)
          write("Disconnected profile \(profileID.uuidString).\n", to: .standardOutput)
          return 0
        } catch {
          write("Could not disconnect the profile.\n", to: .standardError)
          return 1
        }
      case .mcp(let profileID):
        do {
          try await MotesMCPServer.run(profileID: profileID)
          return 0
        } catch {
          write("MCP server failed.\n", to: .standardError)
          return 1
        }
      case .workspace(let profileID, let workspaceCommand, let json):
        do {
          let credential = try credentialStore.load(profileID: profileID)
          let request = AgentWireRequest(
            requestID: UUID(),
            profileID: profileID,
            credentialBase64: credential,
            command: workspaceCommand
          )
          let response = try client.send(request)
          write(
            try BridgeOutput.response(response, json: json) + "\n",
            to: .standardOutput
          )
          return 0
        } catch let error as AgentWorkspaceError {
          writeWorkspaceError(error, json: json)
          return 1
        } catch AgentIPCClientError.writeTimedOut {
          if let operationID = command.operationID {
            write(
              BridgeOutput.writeTimedOut(operationID: operationID) + "\n",
              to: .standardError
            )
          } else {
            write("The request write timed out.\n", to: .standardError)
          }
          return 1
        } catch AgentIPCClientError.responseTimedOut {
          write(
            BridgeOutput.responseTimedOut(operationID: command.operationID)
              + "\n",
            to: .standardError
          )
          return 1
        } catch BridgeCredentialStoreError.credentialNotFound {
          writeWorkspaceError(
            AgentWorkspaceError(
              code: .permissionRevoked,
              recoveryAction: "Reconnect this profile in Motes."
            ),
            json: json
          )
          return 1
        } catch {
          writeWorkspaceError(
            AgentWorkspaceError(
              code: .motesUnavailable,
              recoveryAction: "Open Motes and try again."
            ),
            json: json
          )
          return 1
        }
      }
    }

    private static func writeWorkspaceError(
      _ error: AgentWorkspaceError,
      json: Bool
    ) {
      let output =
        (try? BridgeOutput.workspaceError(error, json: json))
        ?? error.code.rawValue
      write(output + "\n", to: .standardError)
    }

    private static func write(_ text: String, to handle: FileHandle) {
      handle.write(Data(text.utf8))
    }
  }

  private final class StdinReader: @unchecked Sendable {
    private let lock = NSLock()
    private var cached: String?

    func read() throws -> String {
      lock.lock()
      defer { lock.unlock() }
      if let cached { return cached }
      let result =
        String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
      cached = result
      return result
    }
  }
#endif
