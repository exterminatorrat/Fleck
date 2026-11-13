#if os(macOS)
  import Foundation

  enum AgentIntegrationKind: String, CaseIterable, Identifiable {
    case codex = "Codex"
    case claudeCode = "Claude Code"
    case kimi = "Kimi"
    case genericCLI = "Generic CLI"

    var id: Self { self }

    var displayName: String { rawValue }

    var description: String {
      switch self {
      case .codex:
        "Connect Codex to explicitly shared notes."
      case .claudeCode:
        "Connect Claude Code to explicitly shared notes."
      case .kimi:
        "Connect Kimi to explicitly shared notes."
      case .genericCLI:
        "Connect another local CLI to explicitly shared notes."
      }
    }

    var addButtonTitle: String { "Add \(displayName)" }
  }

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

    var connectionServerName: String {
      "fleck-\(profileID.uuidString.lowercased())"
    }

    func connectionPrompt(for integration: AgentIntegrationKind) -> String? {
      guard
        let helperPath = localAbsoluteHelperPath,
        let configuration = mcpServersConfiguration(helperPath: helperPath)
      else { return nil }

      return """
        This is a setup request for the Fleck MCP server on the user's Mac. Work only on this Mac, under the same macOS user account as Fleck: the server is a local stdio process started from a local file path, so an agent running in the cloud or on another machine cannot start or reach it.

        Fleck must be running for the server to answer. Fleck manages authentication locally. Do not add private authentication data to client configuration, environment variables, headers, or files.

        Server name: \(connectionServerName)
        Command: \(ShellArgument.encode(helperPath))
        Arguments: \(arguments.joined(separator: " "))

        Use this connection data in the agent's supported MCP configuration format and keep every other entry. The JSON below is import data, not a file to paste over an existing configuration; translate it if the agent uses a different format:

        ```json
        \(configuration)
        ```

        \(connectionInstructions(for: integration, helperPath: helperPath))

        Rules:
        - Preserve unrelated settings and existing MCP servers; change only what this Fleck server needs.
        - If \(connectionServerName) already exists with exactly this command and these arguments, reuse that entry and do not add a duplicate.
        - If that name exists with a different command, profile, or transport, describe the conflict without displaying authentication values and ask before replacing it.
        - Ask the user for approval before editing their configuration or running setup commands, and report exactly what changed.
        - Do not install software, and do not make this server reachable from another machine or the network.

        After setup:
        - Note access is granted only in Fleck: a new profile can read no notes until the user grants capabilities for it in Fleck's agent settings. Ask the user to grant only the notes and capabilities they want.
        - Restart the agent, or reload its MCP configuration, if the Fleck tools do not appear.
        - Verify by listing the Fleck tools or by running the agent's own connection check. Do not open or read note contents to verify, and do not report success from saved configuration alone: say the connection works only after the server responds.
        """
    }

    var cursorManualConfiguration: String? {
      guard
        let configurationData = cursorConfigurationData,
        let configuration = try? JSONSerialization.jsonObject(with: configurationData),
        let data = try? JSONSerialization.data(
          withJSONObject: ["mcpServers": [cursorConfigurationName: configuration]],
          options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
      else { return nil }
      return String(decoding: data, as: UTF8.self)
    }

    var cursorInstallURL: URL? {
      guard let data = cursorConfigurationData else { return nil }
      let base64Configuration = data.base64EncodedString()
      let queryValueCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
      )
      guard
        let encodedName = cursorConfigurationName.addingPercentEncoding(
          withAllowedCharacters: queryValueCharacters
        ),
        let encodedConfiguration = base64Configuration.addingPercentEncoding(
          withAllowedCharacters: queryValueCharacters
        )
      else { return nil }

      return URL(
        string:
          "cursor://anysphere.cursor-deeplink/mcp/install?name=\(encodedName)&config=\(encodedConfiguration)"
      )
    }

    private var cursorConfigurationData: Data? {
      guard let helperPath = localAbsoluteHelperPath else { return nil }
      return try? JSONSerialization.data(
        withJSONObject: [
          "type": "stdio",
          "command": helperPath,
          "args": arguments,
        ],
        options: [.sortedKeys, .withoutEscapingSlashes]
      )
    }

    private var cursorConfigurationName: String {
      connectionServerName
    }

    private func connectionInstructions(
      for integration: AgentIntegrationKind,
      helperPath: String
    ) -> String {
      let shellCommand =
        "\(ShellArgument.encode(helperPath)) \(arguments.joined(separator: " "))"
      switch integration {
      case .codex:
        return """
          Configure Codex from a shell on this Mac:

          codex mcp add \(connectionServerName) -- \(shellCommand)

          If the installed Codex has no such command, use its supported MCP settings or map command and args into an [mcp_servers.\(connectionServerName)] table in its TOML configuration. Do not paste the JSON wrapper into a TOML file. Restart Codex if needed.
          """
      case .claudeCode:
        return """
          Configure Claude Code from a shell on this Mac:

          claude mcp add --scope user \(connectionServerName) -- \(shellCommand)

          If the installed Claude Code has no such command, add the entry above to its user-scope MCP configuration and restart Claude Code.
          """
      case .kimi:
        return """
          Add the entry above to Kimi's MCP configuration, merging it into any existing "mcpServers" object, then reload or restart Kimi so its tools appear.
          """
      case .genericCLI:
        return """
          Configure the user's local agent through its own MCP server settings, using the stdio entry above and its approval step. For Capy, use Capy's supported local stdio setup: add or import that JSON in Capy's MCP server settings, then approve the server when Capy asks. Do not invent command-line setup for Capy or for any other agent without a local stdio option; tell the user instead.
          """
      }
    }

    private func mcpServersConfiguration(helperPath: String) -> String? {
      let server: [String: Any] = ["command": helperPath, "args": arguments]
      guard
        let data = try? JSONSerialization.data(
          withJSONObject: ["mcpServers": [connectionServerName: server]],
          options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
      else { return nil }
      return String(decoding: data, as: UTF8.self)
    }

    private var localAbsoluteHelperPath: String? {
      guard
        installedHelperURL.isFileURL,
        let components = URLComponents(
          url: installedHelperURL,
          resolvingAgainstBaseURL: false
        ),
        components.scheme?.lowercased() == "file",
        components.user == nil,
        components.password == nil,
        components.query == nil,
        components.fragment == nil,
        components.port == nil,
        components.host == nil
          || components.host?.isEmpty == true
          || components.host?.lowercased() == "localhost",
        installedHelperURL.path.hasPrefix("/")
      else { return nil }
      return installedHelperURL.path
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

  enum CursorSetupStatus: Equatable {
    case idle
    case preparing
    case profileReady
    case requestSent
    case manualFallback
    case cancelled
    case failure
    case profileSelectionRequired
    case profileUnavailable
    case profileScopeChanged

    var isInProgress: Bool {
      self == .preparing || self == .profileReady
    }

    var isError: Bool {
      switch self {
      case .manualFallback, .failure, .profileUnavailable, .profileScopeChanged:
        true
      case .idle, .preparing, .profileReady, .requestSent, .cancelled,
        .profileSelectionRequired:
        false
      }
    }

    var message: String? {
      switch self {
      case .idle:
        nil
      case .preparing:
        "Preparing the local connector and Cursor profile…"
      case .profileReady:
        "The Cursor profile is ready. Cursor will show an installation confirmation."
      case .requestSent:
        "Cursor's install prompt was requested. Confirm it in Cursor; Fleck cannot verify acceptance or connection. If you dismissed it, choose this profile's “Open in Cursor…” action to try again."
      case .manualFallback:
        "Cursor could not open its install prompt. Use the manual setup below."
      case .cancelled:
        "Cursor setup was cancelled. Any profile already created is still available."
      case .failure:
        "Cursor setup could not be completed. No Cursor install request was sent; retry when the local setup is ready."
      case .profileSelectionRequired:
        "A Cursor profile already exists. Review its current scope below, then choose “Open in Cursor…” on that profile; no profile was selected automatically."
      case .profileUnavailable:
        "The selected profile is not an active Cursor profile. Review active profiles below or use the manual setup."
      case .profileScopeChanged:
        "The profile or its access changed before Cursor was opened. Review its current scope and try again."
      }
    }
  }

  enum CursorSetupFlowError: Error {
    case unavailable
  }

  @MainActor
  final class CursorSetupFlow {
    typealias ProfileValidator = @MainActor (AgentIntegrationProfile, Bool) -> Bool

    private let prepareConnector: @MainActor () async throws -> URL
    private let loadActiveProfiles: @MainActor () async throws -> [AgentIntegrationProfile]
    private let createProfile: @MainActor () async throws -> AgentIntegrationProfile
    private let openURL: @MainActor (URL) -> Bool
    private let statusChanged: @MainActor (CursorSetupStatus) -> Void

    private(set) var status = CursorSetupStatus.idle
    private(set) var isInFlight = false

    init(
      prepareConnector: @escaping @MainActor () async throws -> URL,
      loadActiveProfiles: @escaping @MainActor () async throws -> [AgentIntegrationProfile],
      createProfile: @escaping @MainActor () async throws -> AgentIntegrationProfile,
      openURL: @escaping @MainActor (URL) -> Bool,
      statusChanged: @escaping @MainActor (CursorSetupStatus) -> Void = { _ in }
    ) {
      self.prepareConnector = prepareConnector
      self.loadActiveProfiles = loadActiveProfiles
      self.createProfile = createProfile
      self.openURL = openURL
      self.statusChanged = statusChanged
    }

    func setUp(
      profileID: UUID? = nil,
      validateProfile: ProfileValidator
    ) async {
      guard !isInFlight else { return }
      isInFlight = true
      defer { isInFlight = false }
      setStatus(.preparing)
      guard !Task.isCancelled else {
        setStatus(.cancelled)
        return
      }

      do {
        let profiles = try await loadActiveProfiles()
        guard !Task.isCancelled else {
          setStatus(.cancelled)
          return
        }

        let selectedProfile: AgentIntegrationProfile?
        if let profileID {
          guard
            let profile = profiles.first(where: {
              $0.id == profileID && $0.displayName == "Cursor" && !$0.isRevoked
            })
          else {
            setStatus(.profileUnavailable)
            return
          }
          selectedProfile = profile
        } else {
          guard !profiles.contains(where: { $0.displayName == "Cursor" && !$0.isRevoked }) else {
            setStatus(.profileSelectionRequired)
            return
          }
          selectedProfile = nil
        }

        guard !Task.isCancelled else {
          setStatus(.cancelled)
          return
        }
        let helperURL = try await prepareConnector()
        guard !Task.isCancelled else {
          setStatus(.cancelled)
          return
        }

        let profile: AgentIntegrationProfile
        let isNewProfile: Bool
        if let selectedProfile {
          profile = selectedProfile
          isNewProfile = false
        } else {
          guard !Task.isCancelled else {
            setStatus(.cancelled)
            return
          }
          profile = try await createProfile()
          isNewProfile = true
          guard !Task.isCancelled else {
            setStatus(.cancelled)
            return
          }
          guard profile.displayName == "Cursor", !profile.isRevoked else {
            setStatus(.failure)
            return
          }
        }

        guard
          let installURL = AgentClientSetup(
            installedHelperURL: helperURL,
            profileID: profile.id
          ).cursorInstallURL
        else {
          setStatus(.failure)
          return
        }

        setStatus(.profileReady)
        guard !Task.isCancelled else {
          setStatus(.cancelled)
          return
        }
        guard validateProfile(profile, isNewProfile) else {
          setStatus(.profileScopeChanged)
          return
        }
        guard !Task.isCancelled else {
          setStatus(.cancelled)
          return
        }
        setStatus(openURL(installURL) ? .requestSent : .manualFallback)
      } catch {
        setStatus(Task.isCancelled ? .cancelled : .failure)
      }
    }

    private func setStatus(_ status: CursorSetupStatus) {
      self.status = status
      statusChanged(status)
    }
  }
#endif
