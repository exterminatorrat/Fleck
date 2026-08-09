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

protocol AgentCapabilityExclusionManaging: Sendable {
  func exclude(noteID: UUID)
  func include(noteID: UUID)
}

private final class AgentCapabilityExclusions: @unchecked Sendable {
  private let lock = NSLock()
  private var noteIDs: Set<UUID> = []

  func exclude(noteID: UUID) {
    lock.withLock { _ = noteIDs.insert(noteID) }
  }

  func include(noteID: UUID) {
    lock.withLock { _ = noteIDs.remove(noteID) }
  }

  func contains(noteID: UUID) -> Bool {
    lock.withLock { noteIDs.contains(noteID) }
  }
}

struct AgentCapabilityAuthority:
  AgentCapabilityAuthorizing,
  AgentCapabilityExclusionManaging,
  Sendable
{
  let store: AgentCapabilityStore
  private let exclusions: AgentCapabilityExclusions

  init(store: AgentCapabilityStore = AgentCapabilityStore()) {
    self.store = store
    exclusions = AgentCapabilityExclusions()
  }

  func exclude(noteID: UUID) {
    exclusions.exclude(noteID: noteID)
  }

  func include(noteID: UUID) {
    exclusions.include(noteID: noteID)
  }

  func snapshot(
    profileID: UUID,
    workspace: Workspace
  ) async throws -> AgentAuthorizationSnapshot {
    let profile = try await profile(profileID: profileID)
    let snapshot = AgentCapabilityPolicy.authorizationSnapshot(
      for: profile,
      workspace: workspace
    )
    let excludedNoteIDs = Set(
      workspace.notes.map(\.id).filter { exclusions.contains(noteID: $0) }
    )
    return AgentAuthorizationSnapshot(
      profileID: snapshot.profileID,
      grantRevision: snapshot.grantRevision,
      availableCapabilities: snapshot.availableCapabilities,
      readableNoteIDs: snapshot.readableNoteIDs.subtracting(excludedNoteIDs),
      proposableNoteIDs: snapshot.proposableNoteIDs.subtracting(excludedNoteIDs),
      writableNoteIDs: snapshot.writableNoteIDs.subtracting(excludedNoteIDs)
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
