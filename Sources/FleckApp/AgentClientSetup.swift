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
      "fleck-\(profileID.uuidString.lowercased())"
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
