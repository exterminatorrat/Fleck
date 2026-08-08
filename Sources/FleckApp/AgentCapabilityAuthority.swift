import FleckCore
import Foundation

protocol AgentCapabilityAuthorizing: Sendable {
  func snapshot(
    profileID: UUID,
    workspace: Workspace
  ) async throws -> AgentAuthorizationSnapshot
  func assertCurrent(
    profileID: UUID,
    grantRevision: UInt64
  ) async throws
}

struct AgentCapabilityAuthority: AgentCapabilityAuthorizing, Sendable {
  let store: AgentCapabilityStore

  init(store: AgentCapabilityStore = AgentCapabilityStore()) {
    self.store = store
  }

  func snapshot(
    profileID: UUID,
    workspace: Workspace
  ) async throws -> AgentAuthorizationSnapshot {
    let profile = try await profile(profileID: profileID)
    return AgentCapabilityPolicy.authorizationSnapshot(
      for: profile,
      workspace: workspace
    )
  }

  func assertCurrent(profileID: UUID, grantRevision: UInt64) async throws {
    let profile = try await profile(profileID: profileID)
    guard profile.grantRevision == grantRevision else {
      throw capabilityDenied()
    }
  }

  private func profile(profileID: UUID) async throws -> AgentProfileCapabilities {
    let state: AgentCapabilityState
    do {
      state = try await store.currentState()
    } catch let error as AgentWorkspaceError {
      throw error
    } catch {
      throw AgentWorkspaceError(code: .internalSaveFailure)
    }
    guard let profile = state.profiles[profileID] else {
      throw capabilityDenied()
    }
    return profile
  }

  private func capabilityDenied() -> AgentWorkspaceError {
    AgentWorkspaceError(code: .capabilityDenied)
  }
}

enum AgentCapabilityCommandRequirement: Sendable {
  case authenticated
  case capability(AgentCapability, AgentAuthority)
}

extension AgentWorkspaceCommand {
  var capabilityRequirement: AgentCapabilityCommandRequirement {
    switch self {
    case .listSharedNotes:
      return .capability(.listNotes, .read)
    case .readNote, .listTasks, .listActivity:
      return .capability(.readNotes, .read)
    case .appendText,
      .insertText,
      .replaceLines,
      .addTask,
      .renameTask,
      .setTaskState,
      .removeTask:
      return .capability(.writeNotes, .write)
    case .undoChange:
      return .capability(.undoChanges, .write)
    case .getCapabilities:
      return .authenticated
    }
  }
}
