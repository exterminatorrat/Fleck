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

  @Test func NoteAccessContextDriftFailsClosedWithoutAReplacement() throws {
    let folder = try Folder(
      id: testUUID("00000000-0000-0000-0000-000000000350"),
      name: "Projects"
    )
    let otherFolder = try Folder(
      id: testUUID("00000000-0000-0000-0000-000000000351"),
      name: "Archive"
    )
    let note = Note(
      id: testUUID("00000000-0000-0000-0000-000000000352"),
      title: "Original",
      folderID: folder.id
    )
    let baselineWorkspace = Workspace(
      notes: [note],
      folders: [folder, otherFolder]
    )
    let captured = AgentCapabilityPresentation.noteAccessContext(
      for: note.id,
      in: baselineWorkspace
    )
    let profile = AgentProfileCapabilities(
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

    let movedOut = Workspace(
      notes: [Note(id: note.id, title: note.title, folderID: nil)],
      folders: baselineWorkspace.folders
    )
    let movedIn = Workspace(
      notes: [Note(id: note.id, title: note.title, folderID: otherFolder.id)],
      folders: baselineWorkspace.folders
    )
    let deletedFolder = Workspace(
      notes: [note],
      folders: [otherFolder]
    )
    let deletedNote = Workspace(folders: baselineWorkspace.folders)
    let unchangedContext = Workspace(
      notes: [
        Note(
          id: note.id,
          title: "Renamed",
          body: "Body changed",
          revision: 9,
          folderID: folder.id
        )
      ],
      folders: baselineWorkspace.folders
    )

    #expect(
      !AgentCapabilityPresentation.noteAccessContextIsUnchanged(
        noteID: note.id,
        captured: captured,
        workspace: movedOut
      )
    )
    #expect(
      !AgentCapabilityPresentation.noteAccessContextIsUnchanged(
        noteID: note.id,
        captured: captured,
        workspace: movedIn
      )
    )
    #expect(
      !AgentCapabilityPresentation.noteAccessContextIsUnchanged(
        noteID: note.id,
        captured: captured,
        workspace: deletedFolder
      )
    )
    #expect(
      !AgentCapabilityPresentation.noteAccessContextIsUnchanged(
        noteID: note.id,
        captured: captured,
        workspace: deletedNote
      )
    )
    #expect(
      AgentCapabilityPresentation.noteAccessContextIsUnchanged(
        noteID: note.id,
        captured: captured,
        workspace: unchangedContext
      )
    )
    #expect(
      AgentCapabilityPresentation.noteAccessContextChangedMessage
        == "This note’s folder changed. Close and reopen this sheet."
    )

    #expect(
      AgentCapabilityPresentation.noteAccessReplacementIfContextUnchanged(
        noteID: note.id,
        level: .off,
        baseline: profile,
        baselineWorkspace: baselineWorkspace,
        capturedContext: captured,
        currentWorkspace: movedOut
      ) == nil
    )
    #expect(
      AgentCapabilityPresentation.noteAccessReplacementIfContextUnchanged(
        noteID: note.id,
        level: .off,
        baseline: profile,
        baselineWorkspace: baselineWorkspace,
        capturedContext: captured,
        currentWorkspace: unchangedContext
      ) != nil
    )
  }

  @Test func LegacyAssignmentRebasesMaterializedFolderMarkers() throws {
    let folder = try Folder(
      id: testUUID("00000000-0000-0000-0000-000000000353"),
      name: "Projects"
    )
    let assignedNote = Note(
      id: testUUID("00000000-0000-0000-0000-000000000354"),
      folderID: folder.id
    )
    let unassignedNote = Note(
      id: testUUID("00000000-0000-0000-0000-000000000355"),
      folderID: folder.id
    )
    let workspace = Workspace(
      notes: [assignedNote, unassignedNote],
      folders: [folder]
    )
    let materialized = AgentCapabilityPresentation.materializeCurrentFolderNotes(
      folderID: folder.id,
      workspace: workspace,
      directAccess: [:],
      materializedAccess: [:]
    )
    let rebasedMarkers = AgentCapabilityPresentation.rebaseMaterializedAccess(
      assignedNoteIDs: [assignedNote.id],
      materializedAccess: materialized.materializedAccess
    )
    let restored = AgentCapabilityPresentation.restoreMaterializedCurrentFolderNotes(
      folderID: folder.id,
      workspace: workspace,
      directAccess: materialized.directAccess,
      materializedAccess: rebasedMarkers
    )
    let refreshedBaseline = AgentProfileCapabilities(
      profileID: UUID(),
      grantRevision: 2,
      allowedCapabilities: [.writeNotes],
      grants: [
        AgentResourceGrant(
          scope: .note(noteID: assignedNote.id),
          authority: .write
        )
      ]
    )

    #expect(
      restored.directAccess
        == [assignedNote.id: AgentNoteAccessLevel.write]
    )
    #expect(restored.materializedAccess.isEmpty)
    #expect(
      AgentCapabilityPresentation.capabilityReplacementIfChanged(
        baseline: refreshedBaseline,
        allowedCapabilities: refreshedBaseline.allowedCapabilities,
        expectedGrantRevision: refreshedBaseline.grantRevision,
        directAccess: restored.directAccess,
        folderAccess: [folder.id: .off]
      ) == nil
    )
  }

  @Test @MainActor
  func FailedRestoreRollsBackOnlyRestoredNoteAfterUnrelatedEdit() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "RestoreRollback-\\(UUID().uuidString)",
        isDirectory: true
      )
    defer { try? FileManager.default.removeItem(at: root) }
    let existing = Note(
      id: testUUID("00000000-0000-0000-0000-000000000370"),
      title: "Existing"
    )
    let restored = Note(
      id: testUUID("00000000-0000-0000-0000-000000000371"),
      title: "Restored"
    )
    let store = LocalStore(rootURL: root)
    let restoredTrash = TrashedNote(note: restored, deletedAt: Date())
    try await store.save(
      workspace: Workspace(
        notes: [existing],
        selectedNoteID: existing.id
      ),
      preferences: .init(),
      trashedNotes: [restored]
    )

    let restoreGate = PausableAgentCapabilitySaveGate()
    let restoreOperation: AppState.RestoreOperation = {
      _, optimisticWorkspace, _, _ in
      let entry = await restoreGate.markEntered()
      let failing = await restoreGate.waitForRelease(entry: entry)
      if failing {
        throw RestoreTestError.restoreFailed
      }
      return optimisticWorkspace
    }
    let state = AppState(
      store: store,
      saveOperation: { _, _, _, _ in .committed },
      loadTrashOperation: { [restoredTrash] },
      restoreOperation: restoreOperation
    )
    await state.waitUntilInitialLoad()

    let task = try #require(state.restore(restoredTrash))
    let entry = await restoreGate.waitUntilEntered(after: 0)
    state.select(existing.id)
    state.updateSelected(title: "Edited while restore is pending")

    await restoreGate.release(entry: entry, failing: true)
    await task.value

    #expect(!state.workspace.notes.contains(where: { $0.id == restored.id }))
    #expect(
      state.workspace.notes.first(where: { $0.id == existing.id })?.title
        == "Edited while restore is pending"
    )

    let retry = try #require(state.restore(restoredTrash))
    let retryEntry = await restoreGate.waitUntilEntered(after: entry)
    await restoreGate.release(entry: retryEntry, failing: false)
    await retry.value
    #expect(state.workspace.notes.contains(where: { $0.id == restored.id }))
  }

  @Test @MainActor
  func FailedRestoreReinsertsOriginalTrashRowWhenCompensatingRefreshFails()
    async throws
  {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "RestoreTrashFallback-\(UUID().uuidString)",
        isDirectory: true
      )
    defer { try? FileManager.default.removeItem(at: root) }
    let existing = Note(
      id: testUUID("00000000-0000-0000-0000-000000000376"),
      title: "Existing"
    )
    let restored = Note(
      id: testUUID("00000000-0000-0000-0000-000000000377"),
      title: "Restored"
    )
    let other = Note(
      id: testUUID("00000000-0000-0000-0000-000000000378"),
      title: "Other trash"
    )
    let store = LocalStore(rootURL: root)
    let restoredTrash = TrashedNote(note: restored, deletedAt: Date())
    let otherTrash = TrashedNote(note: other, deletedAt: Date().addingTimeInterval(-1))
    try await store.save(
      workspace: Workspace(notes: [existing], selectedNoteID: existing.id),
      preferences: .init(),
      trashedNotes: [restored, other]
    )

    let restoreGate = PausableAgentCapabilitySaveGate()
    let trashRefresh = TrashRefreshSequence(successfulRows: [otherTrash])
    let restoreOperation: AppState.RestoreOperation = {
      _, optimisticWorkspace, _, _ in
      let entry = await restoreGate.markEntered()
      let failing = await restoreGate.waitForRelease(entry: entry)
      if failing {
        throw RestoreTestError.restoreFailed
      }
      return optimisticWorkspace
    }
    let state = AppState(
      store: store,
      saveOperation: { _, _, _, _ in .committed },
      loadTrashOperation: { try await trashRefresh.next() },
      restoreOperation: restoreOperation
    )
    await state.waitUntilInitialLoad()

    let task = try #require(state.restore(restoredTrash))
    let entry = await restoreGate.waitUntilEntered(after: 0)
    state.select(existing.id)
    state.updateSelected(title: "Edited while restore is pending")
    #expect(!state.trashedNotes.contains(where: { $0.id == restored.id }))
    #expect(state.trashedNotes.filter { $0.id == other.id }.count == 1)

    await restoreGate.release(entry: entry, failing: true)
    await task.value

    #expect(!state.workspace.notes.contains(where: { $0.id == restored.id }))
    #expect(
      state.workspace.notes.first(where: { $0.id == existing.id })?.title
        == "Edited while restore is pending"
    )
    #expect(state.trashedNotes.filter { $0.id == restored.id }.count == 1)
    #expect(state.trashedNotes.filter { $0.id == other.id }.count == 1)
    #expect(state.saveError == "restore failed")

    let retryRow = try #require(
      state.trashedNotes.first(where: { $0.id == restored.id })
    )
    let retry = try #require(state.restore(retryRow))
    let retryEntry = await restoreGate.waitUntilEntered(after: entry)
    await restoreGate.release(entry: retryEntry, failing: false)
    await retry.value

    #expect(state.workspace.notes.contains(where: { $0.id == restored.id }))
    #expect(!state.trashedNotes.contains(where: { $0.id == restored.id }))
    #expect(state.trashedNotes.filter { $0.id == other.id }.count == 1)
    #expect(state.saveError == nil)
  }

  @Test @MainActor
  func SuccessfulRestoreKeepsCommittedWorkspaceWhenTrashRefreshFails()
    async throws
  {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "RestoreRefreshFailure-\\(UUID().uuidString)",
        isDirectory: true
      )
    defer { try? FileManager.default.removeItem(at: root) }
    let existing = Note(title: "Existing")
    let restored = Note(title: "Restored")
    let store = LocalStore(rootURL: root)
    let restoredTrash = TrashedNote(note: restored, deletedAt: Date())
    try await store.save(
      workspace: Workspace(notes: [existing], selectedNoteID: existing.id),
      preferences: .init(),
      trashedNotes: [restored]
    )

    let restoreOperation: AppState.RestoreOperation = {
      trashedNote, workspace, preferences, generation in
      try await store.restore(
        trashedNote,
        into: workspace,
        preferences: preferences,
        generation: generation
      )
    }
    let state = AppState(
      store: store,
      saveOperation: { _, _, _, _ in .committed },
      loadTrashOperation: {
        throw RestoreTestError.trashRefreshFailed
      },
      restoreOperation: restoreOperation
    )
    await state.waitUntilInitialLoad()

    let task = try #require(state.restore(restoredTrash))
    await task.value

    #expect(state.workspace.notes.contains(where: { $0.id == restored.id }))
    #expect(!state.trashedNotes.contains(where: { $0.id == restored.id }))
    #expect(state.saveError == "trash refresh failed")
    let snapshot = try await store.loadSnapshot()
    #expect(snapshot.workspace.notes.contains(where: { $0.id == restored.id }))
    #expect(try await store.loadTrash().isEmpty)
  }

  @Test @MainActor
  func PendingRestoreRejectsNoteCapabilityRoutesButAllowsUnrelatedNotes()
    async throws
  {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "PendingRestoreCapabilities-\\(UUID().uuidString)",
        isDirectory: true
      )
    defer { try? FileManager.default.removeItem(at: root) }
    let restored = Note(
      id: testUUID("00000000-0000-0000-0000-000000000372"),
      title: "Restored",
      agentAccess: true
    )
    let unrelated = Note(
      id: testUUID("00000000-0000-0000-0000-000000000373"),
      title: "Unrelated",
      agentAccess: true
    )
    let secondUnrelated = Note(
      id: testUUID("00000000-0000-0000-0000-000000000374"),
      title: "Second unrelated",
      agentAccess: true
    )
    let profileID = testUUID("00000000-0000-0000-0000-000000000375")
    let profile = AgentIntegrationProfile(
      id: profileID,
      displayName: "Codex",
      createdAt: Date(timeIntervalSince1970: 1),
      lastConnectedAt: nil,
      revokedAt: nil
    )
    let localStore = LocalStore(rootURL: root)
    let restoredTrash = TrashedNote(note: restored, deletedAt: Date())
    try await localStore.save(
      workspace: Workspace(
        notes: [unrelated, secondUnrelated],
        selectedNoteID: unrelated.id
      ),
      preferences: .init(),
      trashedNotes: [restored]
    )
    let profilesURL = root
      .appendingPathComponent("AgentIntegrations", isDirectory: true)
      .appendingPathComponent("profiles.json")
    try FileManager.default.createDirectory(
      at: profilesURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try JSONEncoder().encode([profile]).write(to: profilesURL)
    let capabilityStore = AgentCapabilityStore(
      capabilitiesURL: profilesURL.deletingLastPathComponent()
        .appendingPathComponent("capabilities.json"),
      previousCapabilitiesURL: profilesURL.deletingLastPathComponent()
        .appendingPathComponent("capabilities.previous.json")
    )
    _ = try await capabilityStore.loadOrMigrate(
      activeProfileIDs: [],
      workspace: Workspace(notes: [restored, unrelated, secondUnrelated])
    )
    _ = try await capabilityStore.registerEmptyProfile(profileID)
    let replacementGate = PausableAgentCapabilitySaveGate()
    let replacementOperation: AppState.AgentCapabilityBatchReplaceOperation = {
      replacements,
      expectedGrantRevisions in
      _ = await replacementGate.markEntered()
      return try await capabilityStore.replaceProfiles(
        replacements,
        expectedGrantRevisions: expectedGrantRevisions
      )
    }
    let restoreGate = PausableAgentCapabilitySaveGate()
    let restoreOperation: AppState.RestoreOperation = {
      _, optimisticWorkspace, _, _ in
      let entry = await restoreGate.markEntered()
      let failing = await restoreGate.waitForRelease(entry: entry)
      if failing {
        throw RestoreTestError.restoreFailed
      }
      return optimisticWorkspace
    }
    let state = AppState(
      store: localStore,
      saveOperation: { _, _, _, _ in .committed },
      loadTrashOperation: { [restoredTrash] },
      restoreOperation: restoreOperation,
      agentProfileStore: AgentProfileStore(profilesURL: profilesURL),
      agentCapabilityStore: capabilityStore,
      replaceAgentCapabilities: replacementOperation
    )
    await state.waitUntilInitialLoad()

    let restoreTask = try #require(state.restore(restoredTrash))
    let restoreEntry = await restoreGate.waitUntilEntered(after: 0)
    let initialState = try await capabilityStore.currentState()
    let initialProfile = try #require(initialState.profiles[profileID])

    let pendingReplacement = AgentCapabilityPresentation.noteAccessReplacement(
      noteID: restored.id,
      level: .write,
      baseline: initialProfile
    )
    #expect(
      await state.updateAgentCapabilities(
        pendingReplacement,
        expectedGrantRevision: initialProfile.grantRevision
      ) == .revisionConflict
    )
    #expect(try await capabilityStore.currentState() == initialState)

    let batchState = try await capabilityStore.currentState()
    let batchProfile = try #require(batchState.profiles[profileID])
    let batchReplacement = AgentCapabilityPresentation.noteAccessReplacement(
      noteID: restored.id,
      level: .read,
      baseline: batchProfile
    )
    #expect(
      await state.updateAgentCapabilities([
        (
          profile: batchReplacement,
          expectedGrantRevision: batchProfile.grantRevision
        )
      ]) == .revisionConflict
    )
    #expect(try await capabilityStore.currentState() == batchState)

    let assignmentState = try await capabilityStore.currentState()
    let assignmentProfile = try #require(assignmentState.profiles[profileID])
    #expect(
      await state.assignUnassignedLegacyNotes(
        [restored.id],
        to: profileID,
        expectedGrantRevision: assignmentProfile.grantRevision
      ) == .revisionConflict
    )
    #expect(try await capabilityStore.currentState() == assignmentState)

    let singleState = try await capabilityStore.currentState()
    let singleProfile = try #require(singleState.profiles[profileID])
    let unrelatedReplacement = AgentCapabilityPresentation.noteAccessReplacement(
      noteID: unrelated.id,
      level: .write,
      baseline: singleProfile
    )
    #expect(
      await state.updateAgentCapabilities(
        unrelatedReplacement,
        expectedGrantRevision: singleProfile.grantRevision
      ) == .succeeded
    )
    #expect(await replacementGate.count == 1)

    let batchUnrelatedState = try await capabilityStore.currentState()
    let batchUnrelatedProfile = try #require(
      batchUnrelatedState.profiles[profileID]
    )
    let secondReplacement = AgentCapabilityPresentation.noteAccessReplacement(
      noteID: secondUnrelated.id,
      level: .read,
      baseline: batchUnrelatedProfile
    )
    #expect(
      await state.updateAgentCapabilities([
        (
          profile: secondReplacement,
          expectedGrantRevision: batchUnrelatedProfile.grantRevision
        )
      ]) == .succeeded
    )
    #expect(await replacementGate.count == 2)

    let assignmentUnrelatedState = try await capabilityStore.currentState()
    let assignmentUnrelatedProfile = try #require(
      assignmentUnrelatedState.profiles[profileID]
    )
    #expect(
      await state.assignUnassignedLegacyNotes(
        [secondUnrelated.id],
        to: profileID,
        expectedGrantRevision: assignmentUnrelatedProfile.grantRevision
      ) == .succeeded
    )

    let stateBeforeFailure = try await capabilityStore.currentState()
    let restoredGrants = stateBeforeFailure.profiles[profileID]!.grants.filter {
      if case let .note(noteID) = $0.scope {
        return noteID == restored.id
      }
      return false
    }
    #expect(restoredGrants.isEmpty)
    #expect(stateBeforeFailure.unassignedLegacyNoteIDs.contains(restored.id))

    await restoreGate.release(entry: restoreEntry, failing: true)
    await restoreTask.value
    #expect(!state.workspace.notes.contains(where: { $0.id == restored.id }))

    let retry = try #require(state.restore(restoredTrash))
    let retryEntry = await restoreGate.waitUntilEntered(after: restoreEntry)
    await restoreGate.release(entry: retryEntry, failing: false)
    await retry.value
    let stateAfterRetry = try await capabilityStore.currentState()
    let retryGrants = stateAfterRetry.profiles[profileID]!.grants.filter {
      if case let .note(noteID) = $0.scope {
        return noteID == restored.id
      }
      return false
    }
    #expect(retryGrants.isEmpty)
    #expect(stateAfterRetry.unassignedLegacyNoteIDs.contains(restored.id))
  }

  @Test @MainActor
  func GenericFutureFolderSaveLocksPendingRestoreContextThroughPublication()
    async throws
  {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "GenericPendingRestoreCapabilities-\(UUID().uuidString)",
        isDirectory: true
      )
    defer { try? FileManager.default.removeItem(at: root) }
    let folderA = try Folder(
      id: testUUID("00000000-0000-0000-0000-000000000380"),
      name: "Current"
    )
    let folderB = try Folder(
      id: testUUID("00000000-0000-0000-0000-000000000381"),
      name: "Granted"
    )
    let folderC = try Folder(
      id: testUUID("00000000-0000-0000-0000-000000000382"),
      name: "Next"
    )
    let restoredNote = Note(
      id: testUUID("00000000-0000-0000-0000-000000000383"),
      title: "Restored",
      folderID: folderA.id
    )
    let unrelatedNote = Note(
      id: testUUID("00000000-0000-0000-0000-000000000384"),
      title: "Unrelated",
      folderID: folderA.id
    )
    let profileID = testUUID("00000000-0000-0000-0000-000000000385")
    let profile = AgentIntegrationProfile(
      id: profileID,
      displayName: "Codex",
      createdAt: Date(timeIntervalSince1970: 1),
      lastConnectedAt: nil,
      revokedAt: nil
    )
    let localStore = LocalStore(rootURL: root)
    let restoredTrash = TrashedNote(note: restoredNote, deletedAt: Date())
    try await localStore.save(
      workspace: Workspace(
        notes: [unrelatedNote],
        selectedNoteID: unrelatedNote.id,
        folders: [folderA, folderB, folderC]
      ),
      preferences: .init(),
      trashedNotes: [restoredNote]
    )
    let profilesURL = root
      .appendingPathComponent("AgentIntegrations", isDirectory: true)
      .appendingPathComponent("profiles.json")
    try FileManager.default.createDirectory(
      at: profilesURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try JSONEncoder().encode([profile]).write(to: profilesURL)
    let capabilityStore = AgentCapabilityStore(
      capabilitiesURL: profilesURL.deletingLastPathComponent()
        .appendingPathComponent("capabilities.json"),
      previousCapabilitiesURL: profilesURL.deletingLastPathComponent()
        .appendingPathComponent("capabilities.previous.json")
    )
    _ = try await capabilityStore.loadOrMigrate(
      activeProfileIDs: [],
      workspace: Workspace(
        notes: [restoredNote, unrelatedNote],
        folders: [folderA, folderB, folderC]
      )
    )
    _ = try await capabilityStore.registerEmptyProfile(profileID)

    let capabilityGate = PausableAgentCapabilitySaveGate()
    let restoreGate = PausableAgentCapabilitySaveGate()
    let replacementOperation: AppState.AgentCapabilityBatchReplaceOperation = {
      replacements,
      expectedGrantRevisions in
      let entry = await capabilityGate.markEntered()
      let failing = await capabilityGate.waitForRelease(entry: entry)
      if failing {
        throw AgentWorkspaceError(code: .revisionConflict)
      }
      return try await capabilityStore.replaceProfiles(
        replacements,
        expectedGrantRevisions: expectedGrantRevisions
      )
    }
    let restoreOperation: AppState.RestoreOperation = {
      _, optimisticWorkspace, _, _ in
      let entry = await restoreGate.markEntered()
      let failing = await restoreGate.waitForRelease(entry: entry)
      if failing {
        throw RestoreTestError.restoreFailed
      }
      return optimisticWorkspace
    }
    let state = AppState(
      store: localStore,
      saveOperation: { _, _, _, _ in .committed },
      loadTrashOperation: { [] },
      restoreOperation: restoreOperation,
      agentProfileStore: AgentProfileStore(profilesURL: profilesURL),
      agentCapabilityStore: capabilityStore,
      replaceAgentCapabilities: replacementOperation
    )
    await state.waitUntilInitialLoad()

    let restoreTask = try #require(state.restore(restoredTrash))
    let restoreEntry = await restoreGate.waitUntilEntered(after: 0)
    let initialProfile = try #require(state.capabilityProfile(profileID))
    let firstReplacement = AgentProfileCapabilities(
      profileID: profileID,
      grantRevision: initialProfile.grantRevision + 1,
      allowedCapabilities: [.readNotes, .writeNotes],
      grants: [
        AgentResourceGrant(
          scope: .folderIncludingFutureNotes(folderID: folderB.id),
          authority: .write
        )
      ]
    )
    let firstTask = Task { @MainActor in
      await state.updateAgentCapabilities(
        firstReplacement,
        expectedGrantRevision: initialProfile.grantRevision
      )
    }
    let firstEntry = await capabilityGate.waitUntilEntered(after: 0)
    let workspaceBeforeRejectedMoves = state.workspace
    #expect(!state.moveNote(restoredNote.id, toFolderID: folderB.id))
    #expect(state.workspace == workspaceBeforeRejectedMoves)
    #expect(state.moveNote(unrelatedNote.id, toFolderID: folderB.id))
    state.updateSelected(title: "Edited while saving", body: "Body is allowed")
    #expect(state.selectedNote?.body == "Body is allowed")
    let foldersBeforeRejectedDelete = state.workspace.folders
    try state.deleteFolder(id: folderA.id)
    let folderDeleteWasRejected = state.workspace.folders == foldersBeforeRejectedDelete
    #expect(folderDeleteWasRejected)
    guard folderDeleteWasRejected else { return }

    await capabilityGate.release(entry: firstEntry, failing: false)
    #expect(await firstTask.value == .succeeded)
    #expect(state.moveNote(restoredNote.id, toFolderID: folderB.id))
    #expect(state.moveNote(restoredNote.id, toFolderID: folderA.id))

    let currentProfile = try #require(state.capabilityProfile(profileID))
    let secondReplacement = AgentProfileCapabilities(
      profileID: profileID,
      grantRevision: currentProfile.grantRevision + 1,
      allowedCapabilities: currentProfile.allowedCapabilities,
      grants: [
        AgentResourceGrant(
          scope: .folderIncludingFutureNotes(folderID: folderC.id),
          authority: .write
        )
      ]
    )
    let secondTask = Task { @MainActor in
      await state.updateAgentCapabilities(
        secondReplacement,
        expectedGrantRevision: currentProfile.grantRevision
      )
    }
    let secondEntry = await capabilityGate.waitUntilEntered(after: firstEntry)
    #expect(!state.moveNote(restoredNote.id, toFolderID: folderC.id))
    await capabilityGate.release(entry: secondEntry, failing: true)
    #expect(await secondTask.value == .revisionConflict)
    #expect(state.moveNote(restoredNote.id, toFolderID: folderC.id))

    await restoreGate.release(entry: restoreEntry, failing: false)
    await restoreTask.value
    #expect(
      state.workspace.notes.first(where: { $0.id == restoredNote.id })?.folderID
        == folderC.id
    )
  }

  @Test @MainActor
  func NoteAccessSaveLocksRelevantWorkspaceMutationsUntilPersistenceCompletes()
    async throws
  {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "AgentNoteAccessTransaction-\(UUID().uuidString)",
        isDirectory: true
      )
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = try Folder(
      id: testUUID("00000000-0000-0000-0000-000000000360"),
      name: "Projects"
    )
    let unrelatedFolder = try Folder(
      id: testUUID("00000000-0000-0000-0000-000000000361"),
      name: "Archive"
    )
    let note = Note(
      id: testUUID("00000000-0000-0000-0000-000000000362"),
      title: "Locked",
      folderID: folder.id
    )
    let restoredNote = Note(
      id: testUUID("00000000-0000-0000-0000-000000000365"),
      title: "Restored",
      folderID: folder.id
    )
    let unrelatedNote = Note(
      id: testUUID("00000000-0000-0000-0000-000000000363"),
      title: "Unrelated",
      folderID: unrelatedFolder.id
    )
    let initialWorkspace = Workspace(
      notes: [note, unrelatedNote],
      selectedNoteID: note.id,
      folders: [folder, unrelatedFolder]
    )
    let localStore = LocalStore(rootURL: root)
    _ = try await localStore.save(
      workspace: initialWorkspace,
      preferences: .init()
    )

    let profileID = testUUID("00000000-0000-0000-0000-000000000364")
    let profilesURL = root
      .appendingPathComponent("AgentIntegrations", isDirectory: true)
      .appendingPathComponent("profiles.json")
    try FileManager.default.createDirectory(
      at: profilesURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let profile = AgentIntegrationProfile(
      id: profileID,
      displayName: "Codex",
      createdAt: Date(timeIntervalSince1970: 1),
      lastConnectedAt: nil,
      revokedAt: nil
    )
    try JSONEncoder().encode([profile]).write(to: profilesURL)

    let capabilityStore = AgentCapabilityStore(
      capabilitiesURL: profilesURL.deletingLastPathComponent()
        .appendingPathComponent("capabilities.json"),
      previousCapabilitiesURL: profilesURL.deletingLastPathComponent()
        .appendingPathComponent("capabilities.previous.json")
    )
    let gate = PausableAgentCapabilitySaveGate()
    let restoreGate = PausableAgentCapabilitySaveGate()
    let replacementOperation: AppState.AgentCapabilityBatchReplaceOperation = {
      replacements,
      expectedGrantRevisions in
      let entry = await gate.markEntered()
      let failing = await gate.waitForRelease(entry: entry)
      if failing { throw CancellationError() }
      return try await capabilityStore.replaceProfiles(
        replacements,
        expectedGrantRevisions: expectedGrantRevisions
      )
    }
    let restoreOperation: AppState.RestoreOperation = {
      _, optimisticWorkspace, _, _ in
      let entry = await restoreGate.markEntered()
      let failing = await restoreGate.waitForRelease(entry: entry)
      if failing { throw AgentWorkspaceError(code: .internalSaveFailure) }
      return optimisticWorkspace
    }
    let state = AppState(
      store: localStore,
      saveOperation: { _, _, _, _ in .committed },
      loadTrashOperation: { [] },
      restoreOperation: restoreOperation,
      agentProfileStore: AgentProfileStore(profilesURL: profilesURL),
      agentCapabilityStore: capabilityStore,
      replaceAgentCapabilities: replacementOperation
    )
    await state.waitUntilInitialLoad()

    let restoredTrash = TrashedNote(note: restoredNote, deletedAt: Date())
    let restoreTask = try #require(state.restore(restoredTrash))
    let restoreEntry = await restoreGate.waitUntilEntered(after: 0)
    #expect(
      state.workspace.notes.contains(where: { $0.id == restoredNote.id })
    )
    #expect(state.restore(restoredTrash) == nil)
    let initialDisplayed = try #require(state.capabilityProfile(profileID))
    let restoredContext = AgentCapabilityPresentation.noteAccessContext(
      for: restoredNote.id,
      in: state.workspace
    )
    let restoredReplacement = AgentCapabilityPresentation.noteAccessReplacement(
      noteID: restoredNote.id,
      level: .write,
      baseline: initialDisplayed
    )
    let restoredExpectedRevision = [profileID: initialDisplayed.grantRevision]
    #expect(
      await state.updateAgentCapabilitiesForNote(
        noteID: restoredNote.id,
        capturedContext: restoredContext,
        replacements: [
          (
            profile: restoredReplacement,
            expectedGrantRevision: initialDisplayed.grantRevision
          )
        ],
        expectedGrantRevisions: restoredExpectedRevision
      ) == .contextChanged
    )
    #expect(await gate.count == 0)

    let unrelatedContext = AgentCapabilityPresentation.noteAccessContext(
      for: note.id,
      in: state.workspace
    )
    let unrelatedReplacement = AgentCapabilityPresentation.noteAccessReplacement(
      noteID: note.id,
      level: .write,
      baseline: initialDisplayed
    )
    let unrelatedTask = Task { @MainActor in
      await state.updateAgentCapabilitiesForNote(
        noteID: note.id,
        capturedContext: unrelatedContext,
        replacements: [
          (
            profile: unrelatedReplacement,
            expectedGrantRevision: initialDisplayed.grantRevision
          )
        ],
        expectedGrantRevisions: [profileID: initialDisplayed.grantRevision]
      )
    }
    let unrelatedEntry = await gate.waitUntilEntered(after: 0)
    await gate.release(entry: unrelatedEntry, failing: false)
    #expect(await unrelatedTask.value == .succeeded)

    await restoreGate.release(entry: restoreEntry, failing: true)
    await restoreTask.value
    #expect(
      !state.workspace.notes.contains(where: { $0.id == restoredNote.id })
    )
    #expect(
      await state.updateAgentCapabilitiesForNote(
        noteID: restoredNote.id,
        capturedContext: restoredContext,
        replacements: [
          (
            profile: restoredReplacement,
            expectedGrantRevision: initialDisplayed.grantRevision
          )
        ],
        expectedGrantRevisions: restoredExpectedRevision
      ) == .contextChanged
    )

    let retryRestoreTask = try #require(state.restore(restoredTrash))
    let retryRestoreEntry = await restoreGate.waitUntilEntered(after: restoreEntry)
    let retryDisplayed = try #require(state.capabilityProfile(profileID))
    let retryReplacement = AgentCapabilityPresentation.noteAccessReplacement(
      noteID: restoredNote.id,
      level: .write,
      baseline: retryDisplayed
    )
    #expect(
      await state.updateAgentCapabilitiesForNote(
        noteID: restoredNote.id,
        capturedContext: restoredContext,
        replacements: [
          (
            profile: retryReplacement,
            expectedGrantRevision: retryDisplayed.grantRevision
          )
        ],
        expectedGrantRevisions: [profileID: retryDisplayed.grantRevision]
      ) == .contextChanged
    )
    #expect(await gate.count == unrelatedEntry)
    await restoreGate.release(entry: retryRestoreEntry, failing: false)
    await retryRestoreTask.value
    #expect(
      state.workspace.notes.contains(where: { $0.id == restoredNote.id })
    )

    let freshDisplayed = try #require(state.capabilityProfile(profileID))
    let freshRestoredContext = AgentCapabilityPresentation.noteAccessContext(
      for: restoredNote.id,
      in: state.workspace
    )
    let freshRestoredReplacement = AgentCapabilityPresentation.noteAccessReplacement(
      noteID: restoredNote.id,
      level: .write,
      baseline: freshDisplayed
    )
    let freshCapabilityTask = Task { @MainActor in
      await state.updateAgentCapabilitiesForNote(
        noteID: restoredNote.id,
        capturedContext: freshRestoredContext,
        replacements: [
          (
            profile: freshRestoredReplacement,
            expectedGrantRevision: freshDisplayed.grantRevision
          )
        ],
        expectedGrantRevisions: [profileID: freshDisplayed.grantRevision]
      )
    }
    let freshCapabilityEntry = await gate.waitUntilEntered(after: unrelatedEntry)
    await gate.release(entry: freshCapabilityEntry, failing: false)
    #expect(await freshCapabilityTask.value == .succeeded)

    let displayed = try #require(state.capabilityProfile(profileID))
    let capturedContext = AgentCapabilityPresentation.noteAccessContext(
      for: note.id,
      in: state.workspace
    )
    let replacement = AgentCapabilityPresentation.noteAccessReplacement(
      noteID: note.id,
      level: .write,
      baseline: displayed
    )
    let expectedGrantRevisions = [profileID: displayed.grantRevision]
    #expect(state.moveNote(note.id, toFolderID: nil))
    #expect(
      await state.updateAgentCapabilitiesForNote(
        noteID: note.id,
        capturedContext: capturedContext,
        replacements: [
          (
            profile: replacement,
            expectedGrantRevision: displayed.grantRevision
          )
        ],
        expectedGrantRevisions: expectedGrantRevisions
      ) == .contextChanged
    )
    #expect(await gate.count == freshCapabilityEntry)
    #expect(state.moveNote(note.id, toFolderID: folder.id))

    let saveTask = Task { @MainActor in
      await state.updateAgentCapabilitiesForNote(
        noteID: note.id,
        capturedContext: capturedContext,
        replacements: [
          (
            profile: replacement,
            expectedGrantRevision: displayed.grantRevision
          )
        ],
        expectedGrantRevisions: expectedGrantRevisions
      )
    }
    let firstEntry = await gate.waitUntilEntered(after: freshCapabilityEntry)

    state.updateSelected(title: "Edited while saving", body: "Body is allowed")
    #expect(state.selectedNote?.body == "Body is allowed")
    #expect(!state.moveNote(note.id, toFolderID: unrelatedFolder.id))
    state.moveToTrash(note.id)
    #expect(
      AgentCapabilityPresentation.noteAccessContext(
        for: note.id,
        in: state.workspace
      ) == capturedContext
    )
    try state.deleteFolder(id: folder.id)
    state.restore(TrashedNote(note: note, deletedAt: Date()))
    #expect(
      AgentCapabilityPresentation.noteAccessContext(
        for: note.id,
        in: state.workspace
      ) == capturedContext
    )
    #expect(state.moveNote(unrelatedNote.id, toFolderID: nil))
    try state.deleteFolder(id: unrelatedFolder.id)

    await gate.release(entry: firstEntry, failing: false)
    #expect(await saveTask.value == .succeeded)
    #expect(
      try await capabilityStore.currentState().profiles[profileID]
        == state.capabilityProfile(profileID)
    )

    let afterSaveFolder = try state.createFolder(named: "After save")
    #expect(state.moveNote(note.id, toFolderID: afterSaveFolder.id))

    let current = try #require(state.capabilityProfile(profileID))
    let secondContext = AgentCapabilityPresentation.noteAccessContext(
      for: note.id,
      in: state.workspace
    )
    let secondReplacement = AgentCapabilityPresentation.noteAccessReplacement(
      noteID: note.id,
      level: .read,
      baseline: current
    )
    let secondTask = Task { @MainActor in
      await state.updateAgentCapabilitiesForNote(
        noteID: note.id,
        capturedContext: secondContext,
        replacements: [
          (
            profile: secondReplacement,
            expectedGrantRevision: current.grantRevision
          )
        ],
        expectedGrantRevisions: [profileID: current.grantRevision]
      )
    }
    let secondEntry = await gate.waitUntilEntered(after: firstEntry)
    await gate.release(entry: secondEntry, failing: true)
    #expect(await secondTask.value == .failed)
    #expect(state.moveNote(note.id, toFolderID: nil))
  }

  private func testUUID(_ value: String) -> UUID {
    UUID(uuidString: value)!
  }
}

private enum RestoreTestError: Error, LocalizedError, Sendable {
  case restoreFailed
  case trashRefreshFailed
  case compensatingRefreshFailed

  var errorDescription: String? {
    switch self {
    case .restoreFailed: "restore failed"
    case .trashRefreshFailed: "trash refresh failed"
    case .compensatingRefreshFailed: "compensating refresh failed"
    }
  }
}

private actor TrashRefreshSequence {
  private let successfulRows: [TrashedNote]
  private var hasFailedCompensatingRefresh = false

  init(successfulRows: [TrashedNote]) {
    self.successfulRows = successfulRows
  }

  func next() throws -> [TrashedNote] {
    if !hasFailedCompensatingRefresh {
      hasFailedCompensatingRefresh = true
      throw RestoreTestError.compensatingRefreshFailed
    }
    return successfulRows
  }
}

private actor PausableAgentCapabilitySaveGate {
  private var entryCount = 0
  private var enteredWaiters: [CheckedContinuation<Int, Never>] = []
  private var pendingReleases: [Int: Bool] = [:]
  private var releaseWaiters: [Int: CheckedContinuation<Bool, Never>] = [:]

  func markEntered() -> Int {
    entryCount += 1
    let waiters = enteredWaiters
    enteredWaiters.removeAll()
    for waiter in waiters {
      waiter.resume(returning: entryCount)
    }
    return entryCount
  }

  var count: Int { entryCount }

  func waitUntilEntered(after count: Int) async -> Int {
    guard entryCount <= count else { return entryCount }
    return await withCheckedContinuation { continuation in
      enteredWaiters.append(continuation)
    }
  }

  func waitForRelease(entry: Int) async -> Bool {
    if let release = pendingReleases.removeValue(forKey: entry) {
      return release
    }
    return await withCheckedContinuation { continuation in
      releaseWaiters[entry] = continuation
    }
  }

  func release(entry: Int, failing: Bool) {
    if let waiter = releaseWaiters.removeValue(forKey: entry) {
      waiter.resume(returning: failing)
    } else {
      pendingReleases[entry] = failing
    }
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
