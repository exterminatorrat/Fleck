import FleckCore
import Foundation

protocol AgentCapabilityAuthorizing: Sendable {
  var temporaryExclusionGeneration: UUID? { get }
  func snapshot(
    profileID: UUID,
    workspace: Workspace
  ) async throws -> AgentAuthorizationSnapshot
  func assertCurrent(
    profileID: UUID,
    grantRevision: UInt64
  ) async throws
  func assertCurrent(
    profileID: UUID,
    grantRevision: UInt64,
    expectedTemporaryExclusionGeneration: UUID?
  ) async throws
}

extension AgentCapabilityAuthorizing {
  var temporaryExclusionGeneration: UUID? { nil }

  func assertCurrent(
    profileID: UUID,
    grantRevision: UInt64,
    expectedTemporaryExclusionGeneration: UUID?
  ) async throws {
    guard temporaryExclusionGeneration == expectedTemporaryExclusionGeneration else {
      throw AgentWorkspaceError(code: .capabilityDenied)
    }
    try await assertCurrent(
      profileID: profileID,
      grantRevision: grantRevision
    )
    guard temporaryExclusionGeneration == expectedTemporaryExclusionGeneration else {
      throw AgentWorkspaceError(code: .capabilityDenied)
    }
  }
}

protocol AgentCapabilityExclusionManaging: Sendable {
  func exclude(noteID: UUID)
  func include(noteID: UUID)
}

private final class AgentCapabilityExclusions: @unchecked Sendable {
  private let lock = NSLock()
  private var noteIDs: Set<UUID> = []
  private var currentGeneration = UUID()

  var generation: UUID {
    lock.withLock { currentGeneration }
  }

  func exclude(noteID: UUID) {
    lock.withLock {
      guard noteIDs.insert(noteID).inserted else { return }
      advanceGeneration()
    }
  }

  func include(noteID: UUID) {
    lock.withLock {
      guard noteIDs.remove(noteID) != nil else { return }
      advanceGeneration()
    }
  }

  func contains(noteID: UUID) -> Bool {
    lock.withLock { noteIDs.contains(noteID) }
  }

  private func advanceGeneration() {
    var next = UUID()
    while next == currentGeneration {
      next = UUID()
    }
    currentGeneration = next
  }
}

struct AgentCapabilityAuthority:
  AgentCapabilityAuthorizing,
  AgentCapabilityExclusionManaging,
  Sendable
{
  let store: AgentCapabilityStore
  private let exclusions: AgentCapabilityExclusions

  var temporaryExclusionGeneration: UUID? { exclusions.generation }

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
    let (profile, privacyPolicy) = try await profileAndPolicy(profileID: profileID)
    let snapshot = AgentCapabilityPolicy.authorizationSnapshot(
      for: profile,
      workspace: workspace
    )
    let excludedNoteIDs = Set(
      workspace.notes
        .filter { note in
          privacyPolicy?.deniedNoteIDs.contains(note.id) == true
            || note.folderID.map { privacyPolicy?.deniedFolderIDs.contains($0) == true } == true
            || exclusions.contains(noteID: note.id)
        }
        .map(\.id)
    )
    let readableNoteIDs = snapshot.readableNoteIDs.subtracting(excludedNoteIDs)
    let writableNoteIDs = snapshot.writableNoteIDs.subtracting(excludedNoteIDs)
    let availableCapabilities = Set(
      snapshot.availableCapabilities.filter { capability in
        switch capability {
        case .listNotes, .readNotes:
          return !readableNoteIDs.isEmpty
        case .writeNotes, .undoChanges:
          return !writableNoteIDs.isEmpty
        }
      }
    )
    return AgentAuthorizationSnapshot(
      profileID: snapshot.profileID,
      grantRevision: snapshot.grantRevision,
      availableCapabilities: availableCapabilities,
      readableNoteIDs: readableNoteIDs,
      proposableNoteIDs: snapshot.proposableNoteIDs.subtracting(excludedNoteIDs),
      writableNoteIDs: writableNoteIDs
    )
  }

  func assertCurrent(profileID: UUID, grantRevision: UInt64) async throws {
    let (profile, _) = try await profileAndPolicy(profileID: profileID)
    guard profile.grantRevision == grantRevision else {
      throw capabilityDenied()
    }
  }

  func assertCurrent(
    profileID: UUID,
    grantRevision: UInt64,
    expectedTemporaryExclusionGeneration: UUID?
  ) async throws {
    guard temporaryExclusionGeneration == expectedTemporaryExclusionGeneration else {
      throw capabilityDenied()
    }
    try await assertCurrent(
      profileID: profileID,
      grantRevision: grantRevision
    )
    guard temporaryExclusionGeneration == expectedTemporaryExclusionGeneration else {
      throw capabilityDenied()
    }
  }

  func authorizeEventObservation(
    profileID: UUID,
    scope: AgentEventScope,
    workspace: Workspace
  ) async throws -> UInt64 {
    let (profile, privacyPolicy) = try await profileAndPolicy(profileID: profileID)
    guard
      profile.allowsEventObservation,
      profile.allowedCapabilities.contains(.readNotes)
    else {
      throw capabilityDenied()
    }

    let snapshot = AgentCapabilityPolicy.authorizationSnapshot(
      for: profile,
      workspace: workspace
    )
    switch scope {
    case .note(let noteID):
      let noteFolderID = workspace.notes.first(where: { $0.id == noteID })?.folderID
      let folderDenied =
        noteFolderID.map {
          privacyPolicy?.deniedFolderIDs.contains($0) == true
        } ?? false
      guard
        snapshot.readableNoteIDs.contains(noteID),
        privacyPolicy?.deniedNoteIDs.contains(noteID) != true,
        !folderDenied,
        !exclusions.contains(noteID: noteID)
      else {
        throw capabilityDenied()
      }
    case .folder(let folderID):
      guard privacyPolicy?.deniedFolderIDs.contains(folderID) != true else {
        throw capabilityDenied()
      }
      let folderNotesAreReadable = workspace.notes
        .filter { $0.folderID == folderID }
        .allSatisfy { note in
          snapshot.readableNoteIDs.contains(note.id)
            && privacyPolicy?.deniedNoteIDs.contains(note.id) != true
            && !exclusions.contains(noteID: note.id)
        }
      guard
        workspace.folders.contains(where: { $0.id == folderID }),
        profile.grants.contains(where: { grant in
          guard case .folderIncludingFutureNotes(let grantedFolderID) = grant.scope
          else { return false }
          return grantedFolderID == folderID && grant.authority.allows(.read)
        }),
        folderNotesAreReadable
      else {
        throw capabilityDenied()
      }
    }
    return profile.grantRevision
  }

  func assertEventObservationCurrent(
    profileID: UUID,
    grantRevision: UInt64,
    scope: AgentEventScope,
    workspace: Workspace
  ) async throws {
    let currentRevision = try await authorizeEventObservation(
      profileID: profileID,
      scope: scope,
      workspace: workspace
    )
    guard currentRevision == grantRevision else {
      throw capabilityDenied()
    }
  }

  private func profileAndPolicy(
    profileID: UUID
  ) async throws -> (AgentProfileCapabilities, AgentCapabilityPrivacyPolicy?) {
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
    return (profile, state.privacyPolicy)
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
    case .getCapabilities, .listEvents, .prepareEventSubscription, .removeEventSubscription:
      return .authenticated
    }
  }
}
