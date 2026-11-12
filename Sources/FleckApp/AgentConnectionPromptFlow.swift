#if os(macOS)
  import Foundation

  enum AgentConnectionPromptStatus: Equatable {
    case idle
    case preparing
    case ready
    case selectProfile
    case unavailable
    case scopeChanged
    case cancelled
    case failure

    var message: String? {
      switch self {
      case .idle, .ready: nil
      case .preparing: "Preparing your local connector and setup prompt…"
      case .selectProfile:
        "A profile already exists. Review its access below, then copy its setup prompt."
      case .unavailable:
        "This profile is no longer available. Review the profiles below and try again."
      case .scopeChanged:
        "This profile’s access changed. Review its current access and try again."
      case .cancelled:
        "Setup was cancelled. Any profile already created is still available below."
      case .failure:
        "Could not prepare the setup prompt. Check the local connector and try again."
      }
    }

    var isError: Bool {
      self == .unavailable || self == .scopeChanged || self == .failure
    }
  }

  @MainActor
  final class AgentConnectionPromptFlow {
    private let prepareConnector: @MainActor () async throws -> URL
    private let loadProfiles: @MainActor () async throws -> [AgentIntegrationProfile]
    private let createProfile: @MainActor (AgentIntegrationKind) async throws -> AgentIntegrationProfile
    private let statusChanged: @MainActor (AgentConnectionPromptStatus) -> Void

    private(set) var status = AgentConnectionPromptStatus.idle
    private(set) var isInFlight = false

    init(
      prepareConnector: @escaping @MainActor () async throws -> URL,
      loadProfiles: @escaping @MainActor () async throws -> [AgentIntegrationProfile],
      createProfile: @escaping @MainActor (AgentIntegrationKind) async throws -> AgentIntegrationProfile,
      statusChanged: @escaping @MainActor (AgentConnectionPromptStatus) -> Void = { _ in }
    ) {
      self.prepareConnector = prepareConnector
      self.loadProfiles = loadProfiles
      self.createProfile = createProfile
      self.statusChanged = statusChanged
    }

    func prepare(
      for integration: AgentIntegrationKind,
      profileID: UUID? = nil,
      validateProfile: @MainActor (AgentIntegrationProfile, Bool) -> Bool
    ) async -> String? {
      guard !isInFlight else { return nil }
      isInFlight = true
      defer { isInFlight = false }
      setStatus(.preparing)
      do {
        try Task.checkCancellation()
        let profiles = try await loadProfiles()
        try Task.checkCancellation()
        let selectedProfile: AgentIntegrationProfile?
        if let profileID {
          guard let profile = profiles.first(where: {
            $0.id == profileID && $0.displayName == integration.displayName && !$0.isRevoked
          }) else {
            setStatus(.unavailable)
            return nil
          }
          selectedProfile = profile
        } else {
          guard !profiles.contains(where: {
            $0.displayName == integration.displayName && !$0.isRevoked
          }) else {
            setStatus(.selectProfile)
            return nil
          }
          selectedProfile = nil
        }
        let helperURL = try await prepareConnector()
        try Task.checkCancellation()
        let profile: AgentIntegrationProfile
        if let selectedProfile {
          profile = selectedProfile
        } else {
          let currentProfiles = try await loadProfiles()
          try Task.checkCancellation()
          guard !currentProfiles.contains(where: {
            $0.displayName == integration.displayName && !$0.isRevoked
          }) else {
            setStatus(.selectProfile)
            return nil
          }
          profile = try await createProfile(integration)
        }
        try Task.checkCancellation()
        guard profile.displayName == integration.displayName, !profile.isRevoked else {
          setStatus(.unavailable)
          return nil
        }
        guard validateProfile(profile, selectedProfile == nil) else {
          setStatus(.scopeChanged)
          return nil
        }
        try Task.checkCancellation()
        guard let prompt = AgentClientSetup(
          installedHelperURL: helperURL,
          profileID: profile.id
        ).connectionPrompt(for: integration) else {
          setStatus(.failure)
          return nil
        }
        setStatus(.ready)
        return prompt
      } catch is CancellationError {
        setStatus(.cancelled)
        return nil
      } catch {
        setStatus(.failure)
        return nil
      }
    }

    private func setStatus(_ status: AgentConnectionPromptStatus) {
      self.status = status
      statusChanged(status)
    }
  }
#endif
