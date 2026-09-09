#if os(macOS)
  import Combine
  import Foundation
  import SwiftUI

  enum AgentRequestOutcome: Equatable, Sendable {
    case succeeded
    case failed
    case cancelled
  }

  enum AgentRequestEvent: Equatable, Sendable {
    case began(requestID: UUID, profileID: UUID)
    case finished(requestID: UUID, profileID: UUID, outcome: AgentRequestOutcome)
  }

  enum AgentActivityIndicatorState: Equatable {
    case idle
    case working
    case recentlyUsed
    case failed
    case cancelled

    var accessibilityLabel: String {
      switch self {
      case .idle: "Agent Activity"
      case .working: "Agent using Fleck"
      case .recentlyUsed: "Agent used Fleck just now"
      case .failed: "Agent request failed"
      case .cancelled: "Agent request cancelled"
      }
    }

    var statusSymbol: String? {
      switch self {
      case .idle: nil
      case .working: "circle.fill"
      case .recentlyUsed: "checkmark.circle.fill"
      case .failed: "exclamationmark.circle.fill"
      case .cancelled: "xmark.circle.fill"
      }
    }

    fileprivate var statusColor: Color {
      switch self {
      case .idle, .cancelled: .secondary
      case .working: .accentColor
      case .recentlyUsed: .green
      case .failed: .orange
      }
    }
  }

  @MainActor
  final class AgentActivityIndicatorPresentation: ObservableObject {
    typealias ClearScheduler = (Duration, @escaping @MainActor () -> Void) -> Void

    @Published private(set) var state: AgentActivityIndicatorState = .idle
    private let scheduleClear: ClearScheduler
    private var activeRequests: [UUID: UUID] = [:]
    private var generation: UInt64 = 0
    private var terminalProfileID: UUID?

    init(
      scheduleClear: @escaping ClearScheduler = { delay, action in
        Task { @MainActor in
          try? await Task.sleep(for: delay)
          action()
        }
      }
    ) {
      self.scheduleClear = scheduleClear
    }

    func receive(_ event: AgentRequestEvent) {
      switch event {
      case .began(let requestID, let profileID):
        activeRequests[requestID] = profileID
        generation &+= 1
        terminalProfileID = nil
        state = .working
      case .finished(let requestID, let profileID, let outcome):
        guard activeRequests[requestID] == profileID else { return }
        activeRequests[requestID] = nil
        generation &+= 1
        guard activeRequests.isEmpty else {
          terminalProfileID = nil
          state = .working
          return
        }
        terminalProfileID = profileID
        switch outcome {
        case .succeeded: state = .recentlyUsed
        case .failed: state = .failed
        case .cancelled: state = .cancelled
        }
        let terminalGeneration = generation
        scheduleClear(.seconds(3)) { [weak self] in
          guard let self,
            self.generation == terminalGeneration,
            self.activeRequests.isEmpty
          else { return }
          self.state = .idle
          self.terminalProfileID = nil
        }
      }
    }

    func revoke(profileID: UUID) {
      let requestIDs = activeRequests.compactMap { requestID, activeProfileID in
        activeProfileID == profileID ? requestID : nil
      }
      let clearsTerminal = terminalProfileID == profileID
      guard !requestIDs.isEmpty || clearsTerminal else { return }
      requestIDs.forEach { activeRequests[$0] = nil }
      generation &+= 1
      if clearsTerminal {
        terminalProfileID = nil
      }
      state = activeRequests.isEmpty ? .idle : .working
    }

    func retainProfiles(_ profileIDs: Set<UUID>) {
      let knownProfileIDs = Set(activeRequests.values).union(
        terminalProfileID.map { [$0] } ?? []
      )
      for profileID in knownProfileIDs.subtracting(profileIDs) {
        revoke(profileID: profileID)
      }
    }

    func reset() {
      activeRequests.removeAll()
      terminalProfileID = nil
      generation &+= 1
      state = .idle
    }
  }

  struct AgentActivityIndicator: View {
    @ObservedObject var presentation: AgentActivityIndicatorPresentation
    let action: () -> Void

    var body: some View {
      Button(action: action) {
        HStack(spacing: 4) {
          switch FleckMark.load(template: true) {
          case .image(let mark):
            Image(nsImage: mark)
              .resizable()
              .frame(width: 18, height: 18)
          case .missingPackagedResource:
            Text("!")
              .foregroundStyle(.red)
          }
          Text("MCP")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: true, vertical: false)
          Image(systemName: presentation.state.statusSymbol ?? "circle.fill")
            .font(.system(size: 7, weight: .semibold))
            .foregroundStyle(presentation.state.statusColor)
            .opacity(presentation.state.statusSymbol == nil ? 0 : 1)
            .frame(width: 9, height: 9)
        }
        .frame(width: 64, height: 22, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("agent-activity-indicator")
      .accessibilityLabel(presentation.state.accessibilityLabel)
      .accessibilityHint("Open Agent Activity")
      .help(presentation.state.accessibilityLabel)
    }
  }
#endif
