import FleckCore
import Foundation
import Testing

@testable import FleckApp

@Suite("AgentCapabilityPresentation")
struct AgentCapabilityPresentationTests {
  @Test func FutureFolderAccessRequiresExplicitConfirmation() {
    #expect(
      AgentCapabilityPresentation.requiresBroadGrantConfirmation(
        scope: .folderIncludingFutureNotes(folderID: UUID())
      )
    )
    #expect(
      !AgentCapabilityPresentation.requiresBroadGrantConfirmation(
        scope: .note(noteID: UUID())
      )
    )
  }

  @Test func LegacyFlagAloneDoesNotProduceASharedBadge() {
    let note = Note(agentAccess: true)

    #expect(
      !AgentCapabilityPresentation.isShared(
        noteID: note.id,
        activeProfiles: [],
        workspace: Workspace(notes: [note])
      )
    )
  }

  @Test func ProfileSummariesDistinguishReadWriteAndNoScope() throws {
    let note = Note(id: testUUID("00000000-0000-0000-0000-000000000301"))
    let workspace = Workspace(notes: [note])
    let read = AgentProfileCapabilities(
      profileID: UUID(),
      grantRevision: 1,
      allowedCapabilities: [.readNotes],
      grants: [
        AgentResourceGrant(
          scope: .note(noteID: note.id),
          authority: .read
        )
      ]
    )
    let write = AgentProfileCapabilities(
      profileID: UUID(),
      grantRevision: 1,
      allowedCapabilities: [.writeNotes],
      grants: [
        AgentResourceGrant(
          scope: .note(noteID: note.id),
          authority: .write
        )
      ]
    )
    let empty = AgentProfileCapabilities(
      profileID: UUID(),
      grantRevision: 0,
      allowedCapabilities: [],
      grants: []
    )

    #expect(
      AgentCapabilityPresentation.profileSummary(
        for: read,
        isActive: true,
        workspace: workspace
      ).scopeSummary == "Read"
    )
    #expect(
      AgentCapabilityPresentation.profileSummary(
        for: read,
        isActive: true,
        workspace: workspace
      ).toolsSummary == "1 tool"
    )
    let manyTools = AgentProfileCapabilities(
      profileID: UUID(),
      grantRevision: 1,
      allowedCapabilities: [.listNotes, .readNotes],
      grants: read.grants
    )
    #expect(
      AgentCapabilityPresentation.profileSummary(
        for: manyTools,
        isActive: true,
        workspace: workspace
      ).toolsSummary == "2 tools"
    )
    #expect(
      AgentCapabilityPresentation.profileSummary(
        for: write,
        isActive: true,
        workspace: workspace
      ).scopeSummary == "Read + Write"
    )
    #expect(
      AgentCapabilityPresentation.profileSummary(
        for: empty,
        isActive: true,
        workspace: workspace
      ).summary == "No tools or notes granted"
    )
  }

  @Test func RevokedProfilesAndDeletedFoldersHaveNoEffectiveScope() throws {
    let folder = try Folder(
      id: testUUID("00000000-0000-0000-0000-000000000302"),
      name: "Projects"
    )
    let note = Note(
      id: testUUID("00000000-0000-0000-0000-000000000303"),
      folderID: folder.id
    )
    let capabilities = AgentProfileCapabilities(
      profileID: UUID(),
      grantRevision: 1,
      allowedCapabilities: [.readNotes],
      grants: [
        AgentResourceGrant(
          scope: .folderIncludingFutureNotes(folderID: folder.id),
          authority: .read
        )
      ]
    )

    let deletedFolderSummary = AgentCapabilityPresentation.profileSummary(
      for: capabilities,
      isActive: true,
      workspace: Workspace(notes: [note])
    )
    #expect(deletedFolderSummary.summary == "No tools or notes granted")

    let revokedSummary = AgentCapabilityPresentation.profileSummary(
      for: capabilities,
      isActive: false,
      workspace: Workspace(notes: [note], folders: [folder])
    )
    #expect(revokedSummary.summary == "No tools or notes granted")
  }

  @Test func FutureFolderCopyAndUnassignedShareLabelAreExact() throws {
    let folder = try Folder(name: "Projects")
    #expect(
      AgentCapabilityPresentation.futureFolderSummary(folderName: folder.name)
        == "Includes future notes in “Projects”"
    )
    #expect(
      AgentCapabilityPresentation.futureFolderConfirmationMessage
        == "This profile will automatically gain access to notes moved into this folder."
    )
    #expect(
      AgentCapabilityPresentation.unassignedLegacySharesLabel
        == "Unassigned legacy shares"
    )
    let empty = AgentProfileCapabilities(
      profileID: UUID(),
      grantRevision: 0,
      allowedCapabilities: [],
      grants: []
    )
    let summary = AgentCapabilityPresentation.profileSummary(
      for: empty,
      isActive: true,
      workspace: Workspace(),
      unassignedLegacyNoteIDs: [UUID()]
    )
    #expect(summary.accessibilityLabel.contains("Unassigned legacy shares"))
    #expect(!summary.accessibilityLabel.contains("00000000-0000"))
  }

  @Test func VoiceOverLabelsAreDeterministicAndContentSafe() {
    #expect(
      AgentCapabilityPresentation.manageAgentAccessAccessibilityLabel
        == "Manage Agent Access…"
    )
    #expect(
      AgentCapabilityPresentation.noteAccessAccessibilityLabel(.read)
        == "Agent access: Read"
    )
    #expect(
      !AgentCapabilityPresentation.noteAccessAccessibilityLabel(.write)
        .contains("http")
    )
  }

  @Test func DirectNotesDoNotIncludeFolderDerivedAccess() throws {
    let folder = try Folder(
      id: testUUID("00000000-0000-0000-0000-000000000304"),
      name: "Projects"
    )
    let note = Note(
      id: testUUID("00000000-0000-0000-0000-000000000305"),
      folderID: folder.id
    )
    let profile = AgentProfileCapabilities(
      profileID: UUID(),
      grantRevision: 4,
      allowedCapabilities: [.writeNotes],
      grants: [
        AgentResourceGrant(
          scope: .folderIncludingFutureNotes(folderID: folder.id),
          authority: .write
        )
      ]
    )
    let workspace = Workspace(notes: [note], folders: [folder])

    #expect(
      AgentCapabilityPresentation.explicitNoteAccess(
        for: note.id,
        profile: profile
      ) == .off
    )
    #expect(
      AgentCapabilityPresentation.folderAccess(
        for: folder.id,
        profile: profile,
        workspace: workspace
    ) == .includingFutureNotes
    )
  }

  @Test func InheritedFolderAccessDisablesNoteEditsWithoutReplacement() throws {
    let folder = try Folder(
      id: testUUID("00000000-0000-0000-0000-00000000030D"),
      name: "Projects"
    )
    let note = Note(
      id: testUUID("00000000-0000-0000-0000-00000000030E"),
      folderID: folder.id
    )
    let profile = AgentProfileCapabilities(
      profileID: UUID(),
      grantRevision: 5,
      allowedCapabilities: [.readNotes, .writeNotes],
      grants: [
        AgentResourceGrant(
          scope: .folderIncludingFutureNotes(folderID: folder.id),
          authority: .write
        )
      ]
    )
    let workspace = Workspace(notes: [note], folders: [folder])
    let liveProfile = AgentProfileCapabilities(
      profileID: profile.profileID,
      grantRevision: profile.grantRevision + 1,
      allowedCapabilities: [.writeNotes],
      grants: [
        AgentResourceGrant(
          scope: .note(noteID: note.id),
          authority: .write
        )
      ]
    )

    #expect(
      AgentCapabilityPresentation.isNoteAccessInherited(
        for: note.id,
        profile: profile,
        workspace: workspace
      )
    )
    #expect(
      !AgentCapabilityPresentation.canEditNoteAccess(
        for: note.id,
        profile: profile,
        workspace: workspace
      )
    )
    #expect(
      AgentCapabilityPresentation.noteAccessReplacementIfEditable(
        noteID: note.id,
        level: .off,
        baseline: profile,
        workspace: workspace
      ) == nil
    )
    #expect(
      !AgentCapabilityPresentation.canEditNoteAccess(
        for: note.id,
        profileID: profile.profileID,
        baselineCapabilities: [profile.profileID: profile],
        workspace: workspace
      )
    )
    #expect(
      AgentCapabilityPresentation.canEditNoteAccess(
        for: note.id,
        profileID: profile.profileID,
        baselineCapabilities: [profile.profileID: liveProfile],
        workspace: workspace
      )
    )
    #expect(
      AgentCapabilityPresentation.noteAccessReplacementIfEditable(
        noteID: note.id,
        level: .off,
        baseline: liveProfile,
        workspace: workspace
      ) != nil
    )
    #expect(
      AgentCapabilityPresentation.inheritedAccessMessage
        == "Access is inherited from a folder. Edit the profile to change it."
    )
  }

  @Test func DirectOnlyNoteAccessRemainsEditable() throws {
    let note = Note(id: testUUID("00000000-0000-0000-0000-00000000030F"))
    let profile = AgentProfileCapabilities(
      profileID: UUID(),
      grantRevision: 2,
      allowedCapabilities: [.writeNotes],
      grants: [
        AgentResourceGrant(
          scope: .note(noteID: note.id),
          authority: .write
        )
      ]
    )
    let workspace = Workspace(notes: [note])

    #expect(
      !AgentCapabilityPresentation.isNoteAccessInherited(
        for: note.id,
        profile: profile,
        workspace: workspace
      )
    )
    #expect(
      AgentCapabilityPresentation.canEditNoteAccess(
        for: note.id,
        profile: profile,
        workspace: workspace
      )
    )
    let replacement = try #require(
      AgentCapabilityPresentation.noteAccessReplacementIfEditable(
        noteID: note.id,
        level: .off,
        baseline: profile,
        workspace: workspace
      )
    )
    #expect(
      AgentCapabilityPresentation.explicitNoteAccess(
        for: note.id,
        profile: replacement
      ) == .off
    )
  }

  @Test func CapabilityDraftPreservesDirectAndFolderGrantIdentityOnNoOp() throws {
    let folder = try Folder(
      id: testUUID("00000000-0000-0000-0000-000000000310"),
      name: "Projects"
    )
    let note = Note(
      id: testUUID("00000000-0000-0000-0000-000000000311"),
      folderID: folder.id
    )
    let authorities: [AgentAuthority] = [.read, .propose, .write]

    for (index, authority) in authorities.enumerated() {
      let directGrant = AgentResourceGrant(
        id: testUUID(
          "00000000-0000-0000-0000-00000000031\(index + 1)"
        ),
        scope: .note(noteID: note.id),
        authority: authority
      )
      let futureGrant = AgentResourceGrant(
        id: testUUID(
          "00000000-0000-0000-0000-00000000032\(index + 1)"
        ),
        scope: .folderIncludingFutureNotes(folderID: folder.id),
        authority: authority
      )
      let profile = AgentProfileCapabilities(
        profileID: UUID(),
        grantRevision: 7,
        allowedCapabilities: [.readNotes, .writeNotes],
        grants: [directGrant, futureGrant]
      )
      let directLevel: AgentNoteAccessLevel = authority.allows(.write)
        ? .write
        : .read
      let replacement = AgentCapabilityPresentation.capabilityReplacement(
        baseline: profile,
        allowedCapabilities: profile.allowedCapabilities,
        expectedGrantRevision: profile.grantRevision,
        directAccess: [note.id: directLevel],
        folderAccess: [folder.id: .includingFutureNotes]
      )

      #expect(replacement.grants == profile.grants)
      #expect(
        AgentCapabilityPresentation.capabilityReplacementIfChanged(
          baseline: profile,
          allowedCapabilities: profile.allowedCapabilities,
          expectedGrantRevision: profile.grantRevision,
          directAccess: [note.id: directLevel],
          folderAccess: [folder.id: .includingFutureNotes]
        ) == nil
      )
    }
  }

  @Test func ConfirmedFutureFolderTransitionCreatesOneWriteGrant() throws {
    let folder = try Folder(
      id: testUUID("00000000-0000-0000-0000-000000000313"),
      name: "Projects"
    )
    let profile = AgentProfileCapabilities(
      profileID: UUID(),
      grantRevision: 0,
      allowedCapabilities: [.writeNotes],
      grants: []
    )

    let replacement = try #require(
      AgentCapabilityPresentation.capabilityReplacementIfChanged(
        baseline: profile,
        allowedCapabilities: profile.allowedCapabilities,
        expectedGrantRevision: profile.grantRevision,
        directAccess: [:],
        folderAccess: [folder.id: .includingFutureNotes]
      )
    )
    #expect(replacement.grants.count == 1)
    #expect(
      replacement.grants.first?.scope
        == .folderIncludingFutureNotes(folderID: folder.id)
    )
    #expect(replacement.grants.first?.authority == .write)
  }

  @Test func NoteAccessRowsDistinguishEditableInheritedAndUnavailableStates() throws {
    let folder = try Folder(
      id: testUUID("00000000-0000-0000-0000-000000000314"),
      name: "Projects"
    )
    let note = Note(
      id: testUUID("00000000-0000-0000-0000-000000000315"),
      folderID: folder.id
    )
    let inherited = AgentProfileCapabilities(
      profileID: UUID(),
      grantRevision: 1,
      allowedCapabilities: [.readNotes],
      grants: [
        AgentResourceGrant(
          scope: .folderIncludingFutureNotes(folderID: folder.id),
          authority: .read
        )
      ]
    )
    let direct = AgentProfileCapabilities(
      profileID: inherited.profileID,
      grantRevision: 2,
      allowedCapabilities: [.readNotes],
      grants: [
        AgentResourceGrant(
          scope: .note(noteID: note.id),
          authority: .read
        )
      ]
    )
    let workspace = Workspace(notes: [note], folders: [folder])

    #expect(
      AgentCapabilityPresentation.noteAccessRowState(
        for: note.id,
        profileID: inherited.profileID,
        baselineCapabilities: [inherited.profileID: inherited],
        workspace: workspace
      ) == .inheritedFolder
    )
    #expect(
      AgentCapabilityPresentation.noteAccessRowState(
        for: note.id,
        profileID: inherited.profileID,
        baselineCapabilities: [inherited.profileID: direct],
        workspace: workspace
      ) == .editable
    )
    #expect(
      AgentCapabilityPresentation.noteAccessRowState(
        for: note.id,
        profileID: UUID(),
        baselineCapabilities: [:],
        workspace: workspace
      ) == .unavailable
    )
    #expect(
      AgentCapabilityPresentation.unavailableAccessMessage
        == "Capability profile unavailable. Close and reopen this sheet."
    )
    let displayed = AgentCapabilityPresentation.snapshotActiveProfiles([
      AgentIntegrationProfile(
        id: inherited.profileID,
        displayName: "Codex",
        createdAt: Date(timeIntervalSince1970: 1),
        lastConnectedAt: nil,
        revokedAt: nil
      )
    ])
    let liveAdded = displayed + [
      AgentIntegrationProfile(
        id: UUID(),
        displayName: "Claude",
        createdAt: Date(timeIntervalSince1970: 2),
        lastConnectedAt: nil,
        revokedAt: nil
      )
    ]
    #expect(displayed.count == 1)
    #expect(liveAdded.count == 2)
  }

  @Test func DirectAndFutureFolderDraftsRoundTripWithoutDuplicateScopes() throws {
    let folder = try Folder(
      id: testUUID("00000000-0000-0000-0000-000000000306"),
      name: "Projects"
    )
    let note = Note(
      id: testUUID("00000000-0000-0000-0000-000000000307"),
      folderID: folder.id
    )
    let profile = AgentProfileCapabilities(
      profileID: UUID(),
      grantRevision: 2,
      allowedCapabilities: [.readNotes, .writeNotes],
      grants: [
        AgentResourceGrant(
          scope: .note(noteID: note.id),
          authority: .write
        ),
        AgentResourceGrant(
          scope: .folderIncludingFutureNotes(folderID: folder.id),
          authority: .write
        )
      ]
    )
    let replacement = AgentCapabilityPresentation.capabilityReplacement(
      baseline: profile,
      allowedCapabilities: profile.allowedCapabilities,
      expectedGrantRevision: profile.grantRevision,
      directAccess: [note.id: .write],
      folderAccess: [folder.id: .includingFutureNotes]
    )

    #expect(
      replacement.grants.filter {
        if case .note(note.id) = $0.scope { return true }
        return false
      }.count == 1
    )
    #expect(
      replacement.grants.filter {
        if case .folderIncludingFutureNotes(folder.id) = $0.scope { return true }
        return false
      }.count == 1
    )

    let futureOnly = AgentProfileCapabilities(
      profileID: profile.profileID,
      grantRevision: profile.grantRevision,
      allowedCapabilities: profile.allowedCapabilities,
      grants: [
        AgentResourceGrant(
          scope: .folderIncludingFutureNotes(folderID: folder.id),
          authority: .write
        )
      ]
    )
    let futureReplacement = AgentCapabilityPresentation.capabilityReplacement(
      baseline: futureOnly,
      allowedCapabilities: futureOnly.allowedCapabilities,
      expectedGrantRevision: futureOnly.grantRevision,
      directAccess: [:],
      folderAccess: [folder.id: .includingFutureNotes]
    )
    #expect(
      futureReplacement.grants.allSatisfy { grant in
        if case .note = grant.scope { return false }
        return true
      }
    )
  }

  @Test func CurrentFolderSelectionMaterializesDirectWriteGrantsOnce() throws {
    let folder = try Folder(
      id: testUUID("00000000-0000-0000-0000-000000000308"),
      name: "Projects"
    )
    let first = Note(
      id: testUUID("00000000-0000-0000-0000-000000000309"),
      folderID: folder.id
    )
    let second = Note(
      id: testUUID("00000000-0000-0000-0000-00000000030A"),
      folderID: folder.id
    )
    let profile = AgentProfileCapabilities(
      profileID: UUID(),
      grantRevision: 0,
      allowedCapabilities: [.writeNotes],
      grants: []
    )
    let workspace = Workspace(notes: [first, second], folders: [folder])
    let materialized = AgentCapabilityPresentation.materializeCurrentFolderNotes(
      folderID: folder.id,
      workspace: workspace,
      directAccess: [:],
      materializedAccess: [:]
    )
    let replacement = AgentCapabilityPresentation.capabilityReplacement(
      baseline: profile,
      allowedCapabilities: profile.allowedCapabilities,
      expectedGrantRevision: profile.grantRevision,
      directAccess: materialized.directAccess,
      folderAccess: [folder.id: .currentNotes]
    )

    #expect(materialized.directAccess == [first.id: .write, second.id: .write])
    #expect(
      replacement.grants.filter { grant in
        if case .note = grant.scope { return true }
        return false
      }.count == 2
    )
    #expect(
      replacement.grants.allSatisfy { grant in
        if case .folderIncludingFutureNotes = grant.scope { return false }
        return true
      }
    )
  }

  @Test func NoteAccessDraftUsesDisplayedRevisionAfterProfileChanges() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("AgentNoteAccessRevisionTests-(UUID())", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let directory = root.appendingPathComponent("AgentIntegrations", isDirectory: true)
    let capabilitiesURL = directory.appendingPathComponent("capabilities.json")
    let previousURL = directory.appendingPathComponent("capabilities.previous.json")
    let store = AgentCapabilityStore(
      capabilitiesURL: capabilitiesURL,
      previousCapabilitiesURL: previousURL
    )
    let profileID = testUUID("00000000-0000-0000-0000-00000000030B")
    let noteID = testUUID("00000000-0000-0000-0000-00000000030C")
    let initial = try await store.loadOrMigrate(
      activeProfileIDs: [profileID],
      workspace: Workspace(notes: [Note(id: noteID)])
    )
    let displayed = try #require(initial.profiles[profileID])
    let draft = AgentCapabilityPresentation.noteAccessReplacement(
      noteID: noteID,
      level: .write,
      baseline: displayed
    )
    let changed = AgentProfileCapabilities(
      profileID: profileID,
      grantRevision: displayed.grantRevision + 1,
      allowedCapabilities: [.readNotes],
      grants: []
    )
    _ = try await store.replaceProfile(
      changed,
      expectedGrantRevision: displayed.grantRevision
    )
    let beforeRetry = try await store.currentState()

    await #expect(throws: AgentWorkspaceError(code: .revisionConflict)) {
      _ = try await store.replaceProfiles([
        (
          profile: draft,
          expectedGrantRevision: displayed.grantRevision
        )
      ])
    }
    #expect(try await store.currentState() == beforeRetry)
  }

  private func testUUID(_ value: String) -> UUID {
    UUID(uuidString: value)!
  }
}

@MainActor
extension AppState {
  // The pre-capability command-service fixtures still exercise legacy note
  // migration input. Keep that fixture-only bridge out of the product target.
  func setSelectedAgentAccess(_ enabled: Bool) {
    guard let id = workspace.selectedNoteID else { return }
    let originalWorkspace = workspace
    workspace.setAgentAccess(id: id, enabled: enabled)
    guard workspace != originalWorkspace else { return }
    saveNow()
    refreshAgentActivity()
  }
}
