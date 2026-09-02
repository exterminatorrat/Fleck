import Foundation

public enum AgentCapabilityPolicy {
  public static func authorizationSnapshot(
    for profile: AgentProfileCapabilities,
    workspace: Workspace
  ) -> AgentAuthorizationSnapshot {
    let liveNoteIDs = Set(workspace.notes.map(\.id))
    let liveFolderIDs = Set(workspace.folders.map(\.id))
    var authorityByNoteID: [UUID: AgentAuthority] = [:]

    for grant in profile.grants {
      let noteIDs: [UUID]
      switch grant.scope {
      case let .note(noteID):
        guard liveNoteIDs.contains(noteID) else { continue }
        noteIDs = [noteID]
      case let .folderIncludingFutureNotes(folderID):
        guard liveFolderIDs.contains(folderID) else { continue }
        noteIDs = workspace.notes
          .filter { $0.folderID == folderID }
          .map(\.id)
      }

      for noteID in noteIDs {
        guard authorityByNoteID[noteID]?.allows(grant.authority) != true else {
          continue
        }
        authorityByNoteID[noteID] = grant.authority
      }
    }

    let readableNoteIDs = Set(
      authorityByNoteID.compactMap { noteID, authority in
        authority.allows(.read) ? noteID : nil
      }
    )
    let proposableNoteIDs = Set(
      authorityByNoteID.compactMap { noteID, authority in
        authority.allows(.propose) ? noteID : nil
      }
    )
    let writableNoteIDs = Set(
      authorityByNoteID.compactMap { noteID, authority in
        authority.allows(.write) ? noteID : nil
      }
    )

    let availableCapabilities = Set(
      profile.allowedCapabilities.filter { capability in
        switch capability {
        case .listNotes, .readNotes:
          return !readableNoteIDs.isEmpty
        case .writeNotes, .undoChanges:
          return !writableNoteIDs.isEmpty
        }
      }
    )

    return AgentAuthorizationSnapshot(
      profileID: profile.profileID,
      grantRevision: profile.grantRevision,
      availableCapabilities: availableCapabilities,
      readableNoteIDs: readableNoteIDs,
      proposableNoteIDs: proposableNoteIDs,
      writableNoteIDs: writableNoteIDs
    )
  }
}
