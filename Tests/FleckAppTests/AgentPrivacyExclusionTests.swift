import FleckCore
import Foundation
import FleckMCPFixtureSupport
import Testing

@testable import FleckApp

@Suite(.serialized)
struct AgentPrivacyExclusionTests {
  @Test func legacySchemaDefaultsToNoPolicyAndPolicyPersistsOnReopen() async throws {
    let fixture = try PrivacyExclusionFixture()
    defer { fixture.remove() }
    let profileID = privacyTestUUID("00000000-0000-4000-8000-000000000101")
    let initial = try await fixture.store.loadOrMigrate(
      activeProfileIDs: [profileID],
      workspace: Workspace()
    )
    #expect(initial.privacyPolicy == nil)
    let legacy = try fixture.readDocument()
    #expect(legacy["schemaVersion"] as? Int == 2)
    #expect(legacy["privacyPolicy"] == nil)

    let noteID = privacyTestUUID("00000000-0000-4000-8000-000000000102")
    let folderID = privacyTestUUID("00000000-0000-4000-8000-000000000103")
    let updated = try await fixture.store.replacePrivacyPolicy(
      deniedNoteIDs: [noteID],
      deniedFolderIDs: [folderID],
      expectedGeneration: nil
    )
    let policy = try #require(updated.privacyPolicy)
    #expect(policy.deniedNoteIDs == [noteID])
    #expect(policy.deniedFolderIDs == [folderID])

    let persisted = try fixture.readDocument()
    #expect(persisted["schemaVersion"] as? Int == 3)
    #expect(try fixture.readPolicy(persisted) == policy)
    let reloaded = try await fixture.reloadedStore().currentState()
    #expect(reloaded == updated)
  }

  @Test func durableDenialsOverrideLegacyDirectAndFolderGrantsForEveryProfile()
    async throws
  {
    let fixture = try PrivacyExclusionFixture()
    defer { fixture.remove() }
    let firstProfileID = privacyTestUUID("00000000-0000-4000-8000-000000000111")
    let secondProfileID = privacyTestUUID("00000000-0000-4000-8000-000000000112")
    let folderID = privacyTestUUID("00000000-0000-4000-8000-000000000113")
    let otherFolderID = privacyTestUUID("00000000-0000-4000-8000-000000000114")
    let legacyNote = Note(
      id: privacyTestUUID("00000000-0000-4000-8000-000000000115"),
      title: "Synthetic shared note",
      agentAccess: true,
      folderID: folderID
    )
    let directNote = Note(
      id: privacyTestUUID("00000000-0000-4000-8000-000000000116"),
      title: "Synthetic direct note",
      folderID: otherFolderID
    )
    let inheritedNote = Note(
      id: privacyTestUUID("00000000-0000-4000-8000-000000000117"),
      title: "Synthetic inherited note",
      folderID: folderID
    )
    let workspace = Workspace(
      notes: [legacyNote, directNote, inheritedNote],
      folders: [
        try Folder(id: folderID, name: "Synthetic denied folder"),
        try Folder(id: otherFolderID, name: "Synthetic other folder"),
      ]
    )
    let migrated = try await fixture.store.loadOrMigrate(
      activeProfileIDs: [firstProfileID, secondProfileID],
      workspace: workspace
    )
    let first = try #require(migrated.profiles[firstProfileID])
    let second = try #require(migrated.profiles[secondProfileID])
    #expect(second.grants.count == 1)
    #expect(second.grants[0].scope == .note(noteID: legacyNote.id))
    #expect(second.grants[0].authority == .write)
    _ = try await fixture.store.replaceProfile(
      AgentProfileCapabilities(
        profileID: firstProfileID,
        grantRevision: first.grantRevision + 1,
        allowedCapabilities: [.listNotes, .readNotes, .writeNotes],
        grants: [
          AgentResourceGrant(
            scope: .note(noteID: directNote.id),
            authority: .write
          ),
          AgentResourceGrant(
            scope: .folderIncludingFutureNotes(folderID: folderID),
            authority: .write
          ),
        ],
        allowsEventObservation: true
      ),
      expectedGrantRevision: first.grantRevision
    )
    let latest = try await fixture.store.currentState()
    let latestSecond = try #require(latest.profiles[secondProfileID])
    _ = try await fixture.store.replaceProfile(
      AgentProfileCapabilities(
        profileID: secondProfileID,
        grantRevision: latestSecond.grantRevision + 1,
        allowedCapabilities: [.listNotes, .readNotes, .writeNotes],
        grants: latestSecond.grants + [
          AgentResourceGrant(
            scope: .folderIncludingFutureNotes(folderID: folderID),
            authority: .write
          )
        ],
        allowsEventObservation: true
      ),
      expectedGrantRevision: latestSecond.grantRevision
    )
    let beforePolicy = try await fixture.store.currentState()
    let previousBytes = try Data(contentsOf: fixture.previousCapabilitiesURL)
    let firstBefore = try #require(beforePolicy.profiles[firstProfileID])
    let secondBefore = try #require(beforePolicy.profiles[secondProfileID])
    let updated = try await fixture.store.replacePrivacyPolicy(
      deniedNoteIDs: [legacyNote.id, directNote.id],
      deniedFolderIDs: [folderID],
      expectedGeneration: nil
    )

    let policy = try #require(updated.privacyPolicy)
    #expect(policy.deniedNoteIDs == [legacyNote.id, directNote.id])
    #expect(policy.deniedFolderIDs == [folderID])
    let firstAfter = try #require(updated.profiles[firstProfileID])
    let secondAfter = try #require(updated.profiles[secondProfileID])
    #expect(firstAfter.grantRevision == firstBefore.grantRevision + 1)
    #expect(secondAfter.grantRevision == secondBefore.grantRevision + 1)
    #expect(firstAfter.grants == firstBefore.grants)
    #expect(secondAfter.grants == secondBefore.grants)
    #expect(firstAfter.allowsEventObservation)
    #expect(secondAfter.allowsEventObservation)
    #expect(try Data(contentsOf: fixture.previousCapabilitiesURL) != previousBytes)
    let backup = try fixture.readDocument(at: fixture.previousCapabilitiesURL)
    let backupPolicy = try fixture.readPolicy(backup)
    #expect(backupPolicy.deniedNoteIDs == [legacyNote.id, directNote.id])
    #expect(backupPolicy.deniedFolderIDs == [folderID])

    let futureNote = Note(
      id: privacyTestUUID("00000000-0000-4000-8000-000000000118"),
      title: "Synthetic future note",
      folderID: folderID
    )
    let movedNote = Note(
      id: privacyTestUUID("00000000-0000-4000-8000-000000000119"),
      title: "Synthetic moved note",
      folderID: folderID
    )
    let currentWorkspace = Workspace(
      notes: [legacyNote, directNote, inheritedNote, futureNote, movedNote],
      folders: workspace.folders
    )
    let authority = AgentCapabilityAuthority(store: fixture.reloadedStore())
    for profileID in [firstProfileID, secondProfileID] {
      let snapshot = try await authority.snapshot(
        profileID: profileID,
        workspace: currentWorkspace
      )
      #expect(!snapshot.readableNoteIDs.contains(legacyNote.id))
      #expect(!snapshot.writableNoteIDs.contains(legacyNote.id))
      #expect(!snapshot.readableNoteIDs.contains(directNote.id))
      #expect(!snapshot.writableNoteIDs.contains(directNote.id))
      #expect(!snapshot.readableNoteIDs.contains(inheritedNote.id))
      #expect(!snapshot.readableNoteIDs.contains(futureNote.id))
      #expect(!snapshot.readableNoteIDs.contains(movedNote.id))
      #expect(snapshot.availableCapabilities.isEmpty)
    }
    await #expect(throws: AgentWorkspaceError(code: .capabilityDenied)) {
      _ = try await authority.authorizeEventObservation(
        profileID: firstProfileID,
        scope: .folder(folderID: folderID),
        workspace: currentWorkspace
      )
    }
    await #expect(throws: AgentWorkspaceError(code: .capabilityDenied)) {
      _ = try await authority.authorizeEventObservation(
        profileID: firstProfileID,
        scope: .note(noteID: directNote.id),
        workspace: currentWorkspace
      )
    }
  }

  @Test func emptyDeniedFolderIsRejectedForObservationWithoutDisclosingItsID()
    async throws
  {
    let fixture = try PrivacyExclusionFixture()
    defer { fixture.remove() }
    let profileID = privacyTestUUID("00000000-0000-4000-8000-000000000121")
    let folderID = privacyTestUUID("00000000-0000-4000-8000-000000000122")
    let workspace = Workspace(
      folders: [try Folder(id: folderID, name: "Synthetic empty folder")]
    )
    let initial = try await fixture.store.loadOrMigrate(
      activeProfileIDs: [profileID],
      workspace: workspace
    )
    let current = try #require(initial.profiles[profileID])
    _ = try await fixture.store.replaceProfile(
      AgentProfileCapabilities(
        profileID: profileID,
        grantRevision: current.grantRevision + 1,
        allowedCapabilities: [.readNotes],
        grants: [
          AgentResourceGrant(
            scope: .folderIncludingFutureNotes(folderID: folderID),
            authority: .read
          )
        ],
        allowsEventObservation: true
      ),
      expectedGrantRevision: current.grantRevision
    )
    _ = try await fixture.store.replacePrivacyPolicy(
      deniedNoteIDs: [],
      deniedFolderIDs: [folderID],
      expectedGeneration: nil
    )
    let authority = AgentCapabilityAuthority(store: fixture.reloadedStore())

    do {
      _ = try await authority.authorizeEventObservation(
        profileID: profileID,
        scope: .folder(folderID: folderID),
        workspace: workspace
      )
      Issue.record("Expected denied-folder observation to fail")
    } catch let error as AgentWorkspaceError {
      #expect(error == AgentWorkspaceError(code: .capabilityDenied))
      #expect(!String(describing: error).contains(folderID.uuidString))
    }
  }

  @Test func noteDenialRejectsWholeGrantedFolderObservation() async throws {
    let fixture = try PrivacyExclusionFixture()
    defer { fixture.remove() }
    let profileID = privacyTestUUID("00000000-0000-4000-8000-000000000123")
    let folderID = privacyTestUUID("00000000-0000-4000-8000-000000000124")
    let deniedNote = Note(
      id: privacyTestUUID("00000000-0000-4000-8000-000000000125"),
      folderID: folderID
    )
    let otherNote = Note(
      id: privacyTestUUID("00000000-0000-4000-8000-000000000126"),
      folderID: folderID
    )
    let workspace = Workspace(
      notes: [deniedNote, otherNote],
      folders: [try Folder(id: folderID, name: "Synthetic mixed folder")]
    )
    let initial = try await fixture.store.loadOrMigrate(
      activeProfileIDs: [profileID],
      workspace: workspace
    )
    let profile = try #require(initial.profiles[profileID])
    _ = try await fixture.store.replaceProfile(
      AgentProfileCapabilities(
        profileID: profileID,
        grantRevision: profile.grantRevision + 1,
        allowedCapabilities: [.listNotes, .readNotes],
        grants: [
          AgentResourceGrant(
            scope: .folderIncludingFutureNotes(folderID: folderID),
            authority: .read
          )
        ],
        allowsEventObservation: true
      ),
      expectedGrantRevision: profile.grantRevision
    )
    _ = try await fixture.store.replacePrivacyPolicy(
      deniedNoteIDs: [deniedNote.id],
      deniedFolderIDs: [],
      expectedGeneration: nil
    )
    let authority = AgentCapabilityAuthority(store: fixture.reloadedStore())

    await #expect(throws: AgentWorkspaceError(code: .capabilityDenied)) {
      _ = try await authority.authorizeEventObservation(
        profileID: profileID,
        scope: .folder(folderID: folderID),
        workspace: workspace
      )
    }
    let snapshot = try await authority.snapshot(
      profileID: profileID,
      workspace: workspace
    )
    #expect(snapshot.readableNoteIDs == [otherNote.id])
    #expect(snapshot.availableCapabilities.contains(.readNotes))
  }

  @Test func policyGenerationCasNoOpsClearReapplyAndFencesStaleDrafts() async throws {
    let fixture = try PrivacyExclusionFixture()
    defer { fixture.remove() }
    let profileID = privacyTestUUID("00000000-0000-4000-8000-000000000131")
    let noteID = privacyTestUUID("00000000-0000-4000-8000-000000000132")
    let initial = try await fixture.store.loadOrMigrate(
      activeProfileIDs: [profileID],
      workspace: Workspace()
    )
    let displayed = try #require(initial.profiles[profileID])
    let authority = AgentCapabilityAuthority(store: fixture.store)
    try await authority.assertCurrent(
      profileID: profileID,
      grantRevision: displayed.grantRevision
    )
    let first = try await fixture.store.replacePrivacyPolicy(
      deniedNoteIDs: [noteID],
      deniedFolderIDs: [],
      expectedGeneration: nil
    )
    let generation = try #require(first.privacyPolicy).generation
    let revised = try #require(first.profiles[profileID])
    #expect(revised.grantRevision == displayed.grantRevision + 1)
    await #expect(throws: AgentWorkspaceError(code: .capabilityDenied)) {
      try await authority.assertCurrent(
        profileID: profileID,
        grantRevision: displayed.grantRevision
      )
    }
    await #expect(throws: AgentWorkspaceError(code: .revisionConflict)) {
      _ = try await fixture.store.replaceProfile(
        AgentProfileCapabilities(
          profileID: profileID,
          grantRevision: displayed.grantRevision + 1,
          allowedCapabilities: [.readNotes],
          grants: []
        ),
        expectedGrantRevision: displayed.grantRevision
      )
    }

    let currentBytes = try Data(contentsOf: fixture.capabilitiesURL)
    let noOp = try await fixture.store.replacePrivacyPolicy(
      deniedNoteIDs: [noteID],
      deniedFolderIDs: [],
      expectedGeneration: generation
    )
    #expect(noOp == first)
    #expect(try Data(contentsOf: fixture.capabilitiesURL) == currentBytes)
    await #expect(throws: AgentWorkspaceError(code: .revisionConflict)) {
      _ = try await fixture.store.replacePrivacyPolicy(
        deniedNoteIDs: [],
        deniedFolderIDs: [],
        expectedGeneration: nil
      )
    }

    let cleared = try await fixture.store.replacePrivacyPolicy(
      deniedNoteIDs: [],
      deniedFolderIDs: [],
      expectedGeneration: generation
    )
    let clearedPolicy = try #require(cleared.privacyPolicy)
    #expect(clearedPolicy.generation != generation)
    #expect(clearedPolicy.deniedNoteIDs.isEmpty)
    #expect(clearedPolicy.deniedFolderIDs.isEmpty)
    #expect(try fixture.readDocument()["schemaVersion"] as? Int == 3)
    let clearingBackup = try fixture.readDocument(at: fixture.previousCapabilitiesURL)
    #expect(try fixture.readPolicy(clearingBackup).deniedNoteIDs == [noteID])
    let reapplied = try await fixture.store.replacePrivacyPolicy(
      deniedNoteIDs: [noteID],
      deniedFolderIDs: [],
      expectedGeneration: clearedPolicy.generation
    )
    #expect(try #require(reapplied.privacyPolicy).generation != clearedPolicy.generation)

    let emptyFixture = try PrivacyExclusionFixture()
    defer { emptyFixture.remove() }
    let legacyEmpty = try await emptyFixture.store.loadOrMigrate(
      activeProfileIDs: [],
      workspace: Workspace()
    )
    let emptyUpdate = try await emptyFixture.store.replacePrivacyPolicy(
      deniedNoteIDs: [],
      deniedFolderIDs: [],
      expectedGeneration: nil
    )
    #expect(emptyUpdate == legacyEmpty)
    #expect(emptyUpdate.privacyPolicy == nil)
  }

  @Test func newProfilesKeepThePersistedGlobalDenial() async throws {
    let fixture = try PrivacyExclusionFixture()
    defer { fixture.remove() }
    let firstID = privacyTestUUID("00000000-0000-4000-8000-000000000141")
    let secondID = privacyTestUUID("00000000-0000-4000-8000-000000000142")
    let noteID = privacyTestUUID("00000000-0000-4000-8000-000000000143")
    let note = Note(id: noteID, agentAccess: true)
    _ = try await fixture.store.loadOrMigrate(
      activeProfileIDs: [firstID],
      workspace: Workspace(notes: [note])
    )
    let policyState = try await fixture.store.replacePrivacyPolicy(
      deniedNoteIDs: [noteID],
      deniedFolderIDs: [],
      expectedGeneration: nil
    )
    let registered = try await fixture.store.registerEmptyProfile(secondID)
    #expect(registered.privacyPolicy == policyState.privacyPolicy)
    #expect(registered.profiles[secondID]?.grantRevision == 0)
    #expect(registered.profiles[secondID]?.grants.isEmpty == true)
    let snapshot = try await AgentCapabilityAuthority(store: fixture.reloadedStore()).snapshot(
      profileID: secondID,
      workspace: Workspace(notes: [note])
    )
    #expect(!snapshot.readableNoteIDs.contains(noteID))
    #expect(!snapshot.writableNoteIDs.contains(noteID))
  }

  @Test func fullBudgetDisjointReplacementUsesBoundedBackupAndFailsClosed()
    async throws
  {
    let fixture = try PrivacyExclusionFixture()
    defer { fixture.remove() }
    let firstProfileID = privacyTestUUID("00000000-0000-4000-8000-000000000151")
    let secondProfileID = privacyTestUUID("00000000-0000-4000-8000-000000000152")
    let initial = try await fixture.store.loadOrMigrate(
      activeProfileIDs: [firstProfileID, secondProfileID],
      workspace: Workspace()
    )
    let noteIDs = Set(
      (0..<65_536).map { index in
        privacyTestUUID(String(format: "00000000-0000-4000-8000-%012x", index))
      })
    let folderIDs = Set(
      (65_536..<131_072).map { index in
        privacyTestUUID(String(format: "00000000-0000-4000-8000-%012x", index))
      })
    #expect(noteIDs.count == 65_536)
    #expect(folderIDs.count == 65_536)

    let first = try await fixture.store.replacePrivacyPolicy(
      deniedNoteIDs: noteIDs,
      deniedFolderIDs: [],
      expectedGeneration: nil
    )
    let firstPolicy = try #require(first.privacyPolicy)
    for profileID in [firstProfileID, secondProfileID] {
      let initialProfile = try #require(initial.profiles[profileID])
      #expect(first.profiles[profileID]?.grantRevision == initialProfile.grantRevision + 1)
    }

    let second = try await fixture.store.replacePrivacyPolicy(
      deniedNoteIDs: [],
      deniedFolderIDs: folderIDs,
      expectedGeneration: firstPolicy.generation
    )
    let secondPolicy = try #require(second.privacyPolicy)
    #expect(secondPolicy.generation != firstPolicy.generation)
    #expect(secondPolicy.deniedNoteIDs.isEmpty)
    #expect(secondPolicy.deniedFolderIDs == folderIDs)
    for profileID in [firstProfileID, secondProfileID] {
      let initialProfile = try #require(initial.profiles[profileID])
      #expect(second.profiles[profileID]?.grantRevision == initialProfile.grantRevision + 2)
    }
    await #expect(throws: AgentWorkspaceError(code: .revisionConflict)) {
      _ = try await fixture.store.replacePrivacyPolicy(
        deniedNoteIDs: noteIDs,
        deniedFolderIDs: [],
        expectedGeneration: firstPolicy.generation
      )
    }

    let current = try fixture.readDocument()
    #expect(current["schemaVersion"] as? Int == 3)
    #expect(try fixture.readPolicy(current) == secondPolicy)
    let backup = try fixture.readDocument(at: fixture.previousCapabilitiesURL)
    let backupPolicy = try fixture.readPolicy(backup)
    #expect(backup["schemaVersion"] as? Int == 3)
    #expect(backupPolicy == secondPolicy)
    #expect(
      backupPolicy.deniedNoteIDs.count + backupPolicy.deniedFolderIDs.count
        <= 65_536
    )

    let backupBeforeCorruption = try Data(contentsOf: fixture.previousCapabilitiesURL)
    let corruptCurrent = Data("corrupt-current-after-policy-ack".utf8)
    try corruptCurrent.write(to: fixture.capabilitiesURL)
    await #expect(throws: AgentWorkspaceError(code: .internalSaveFailure)) {
      _ = try await fixture.reloadedStore().currentState()
    }
    #expect(try Data(contentsOf: fixture.capabilitiesURL) == corruptCurrent)
    #expect(try Data(contentsOf: fixture.previousCapabilitiesURL) == backupBeforeCorruption)
  }

  @Test func legacyAssignmentAndProfileReplacementPreservePolicy() async throws {
    let fixture = try PrivacyExclusionFixture()
    defer { fixture.remove() }
    let profileID = privacyTestUUID("00000000-0000-4000-8000-000000000144")
    let note = Note(
      id: privacyTestUUID("00000000-0000-4000-8000-000000000145"),
      agentAccess: true
    )
    let migrated = try await fixture.store.loadOrMigrate(
      activeProfileIDs: [],
      workspace: Workspace(notes: [note])
    )
    let policyState = try await fixture.store.replacePrivacyPolicy(
      deniedNoteIDs: [note.id],
      deniedFolderIDs: [],
      expectedGeneration: nil
    )
    #expect(policyState.unassignedLegacyNoteIDs == [note.id])
    let registered = try await fixture.store.registerEmptyProfile(profileID)
    #expect(registered.privacyPolicy == policyState.privacyPolicy)
    let assigned = try await fixture.store.assignUnassignedLegacyNotes(
      [note.id],
      to: profileID,
      expectedGrantRevision: 0
    )
    #expect(assigned.privacyPolicy == policyState.privacyPolicy)
    #expect(assigned.unassignedLegacyNoteIDs.isEmpty)
    let assignedProfile = try #require(assigned.profiles[profileID])
    #expect(assignedProfile.grants.contains { $0.scope == .note(noteID: note.id) })

    let replacement = AgentProfileCapabilities(
      profileID: profileID,
      grantRevision: assignedProfile.grantRevision + 1,
      allowedCapabilities: [.listNotes, .readNotes, .writeNotes],
      grants: assignedProfile.grants,
      allowsEventObservation: true
    )
    let replaced = try await fixture.store.replaceProfile(
      replacement,
      expectedGrantRevision: assignedProfile.grantRevision
    )
    #expect(replaced.privacyPolicy == policyState.privacyPolicy)
    let snapshot = try await AgentCapabilityAuthority(store: fixture.reloadedStore()).snapshot(
      profileID: profileID,
      workspace: Workspace(notes: [note])
    )
    #expect(snapshot.readableNoteIDs.isEmpty)
    #expect(snapshot.writableNoteIDs.isEmpty)
    #expect(migrated.unassignedLegacyNoteIDs == [note.id])
  }

  @Test func twoStoreInstancesSerializePolicyCompareAndSwap() async throws {
    let fixture = try PrivacyExclusionFixture()
    defer { fixture.remove() }
    let profileID = privacyTestUUID("00000000-0000-4000-8000-000000000151")
    let firstNoteID = privacyTestUUID("00000000-0000-4000-8000-000000000152")
    let secondNoteID = privacyTestUUID("00000000-0000-4000-8000-000000000153")
    _ = try await fixture.store.loadOrMigrate(
      activeProfileIDs: [profileID],
      workspace: Workspace()
    )
    let secondStore = fixture.reloadedStore()

    async let firstResult = attemptPolicyUpdate(
      with: fixture.store,
      deniedNoteID: firstNoteID
    )
    async let secondResult = attemptPolicyUpdate(
      with: secondStore,
      deniedNoteID: secondNoteID
    )
    let results = await [firstResult, secondResult]
    #expect(
      results.filter {
        if case .success = $0 { return true }
        return false
      }.count == 1)
    #expect(
      results.filter {
        if case .failure(let error as AgentWorkspaceError) = $0 {
          return error == AgentWorkspaceError(code: .revisionConflict)
        }
        return false
      }.count == 1
    )
    let final = try await fixture.reloadedStore().currentState()
    #expect(final.profiles[profileID]?.grantRevision == 2)
    #expect(final.privacyPolicy?.deniedNoteIDs.count == 1)
  }

  @Test func malformedAndOversizedPoliciesFailClosed() async throws {
    let fixture = try PrivacyExclusionFixture()
    defer { fixture.remove() }
    let profileID = privacyTestUUID("00000000-0000-4000-8000-000000000161")
    _ = try await fixture.store.loadOrMigrate(
      activeProfileIDs: [profileID],
      workspace: Workspace()
    )
    let expectedPolicy: [String: Any] = [
      "generation": "00000000-0000-4000-8000-000000000162",
      "deniedNoteIDs": [],
      "deniedFolderIDs": [],
    ]
    let malformedPolicies: [[String: Any]] = [
      ["generation": NSNull(), "deniedNoteIDs": [], "deniedFolderIDs": []],
      ["generation": "not-a-uuid", "deniedNoteIDs": [], "deniedFolderIDs": []],
      [
        "generation": expectedPolicy["generation"]!, "deniedNoteIDs": NSNull(),
        "deniedFolderIDs": [],
      ],
      [
        "generation": expectedPolicy["generation"]!, "deniedNoteIDs": [], "deniedFolderIDs": [],
        "unknown": true,
      ],
      [
        "generation": expectedPolicy["generation"]!,
        "deniedNoteIDs": [
          "00000000-0000-4000-8000-000000000163", "00000000-0000-4000-8000-000000000163",
        ],
        "deniedFolderIDs": [],
      ],
      [
        "generation": expectedPolicy["generation"]!,
        "deniedNoteIDs": [],
        "deniedFolderIDs": [
          "00000000-0000-4000-8000-000000000165", "00000000-0000-4000-8000-000000000165",
        ],
      ],
    ]
    for malformed in malformedPolicies {
      var document = try fixture.readDocument()
      document["schemaVersion"] = 3
      document["privacyPolicy"] = malformed
      try fixture.writeDocument(document)
      await #expect(throws: AgentWorkspaceError(code: .internalSaveFailure)) {
        _ = try await fixture.reloadedStore().currentState()
      }
    }
    var missingPolicy = try fixture.readDocument()
    missingPolicy["schemaVersion"] = 3
    missingPolicy.removeValue(forKey: "privacyPolicy")
    try fixture.writeDocument(missingPolicy)
    await #expect(throws: AgentWorkspaceError(code: .internalSaveFailure)) {
      _ = try await fixture.reloadedStore().currentState()
    }
    var nullPolicy = try fixture.readDocument()
    nullPolicy["schemaVersion"] = 3
    nullPolicy["privacyPolicy"] = NSNull()
    try fixture.writeDocument(nullPolicy)
    await #expect(throws: AgentWorkspaceError(code: .internalSaveFailure)) {
      _ = try await fixture.reloadedStore().currentState()
    }
    var legacyWithPolicy = try fixture.readDocument()
    legacyWithPolicy["schemaVersion"] = 2
    legacyWithPolicy["privacyPolicy"] = expectedPolicy
    try fixture.writeDocument(legacyWithPolicy)
    await #expect(throws: AgentWorkspaceError(code: .internalSaveFailure)) {
      _ = try await fixture.reloadedStore().currentState()
    }
    var unknownSchema = try fixture.readDocument()
    unknownSchema["schemaVersion"] = 99
    try fixture.writeDocument(unknownSchema)
    await #expect(throws: AgentWorkspaceError(code: .internalSaveFailure)) {
      _ = try await fixture.reloadedStore().currentState()
    }

    var oversizedPolicy = expectedPolicy
    oversizedPolicy["deniedNoteIDs"] = (0...65_536).map { index in
      String(format: "00000000-0000-4000-8000-%012X", index)
    }
    var oversizedDocument = try fixture.readDocument()
    oversizedDocument["schemaVersion"] = 3
    oversizedDocument["privacyPolicy"] = oversizedPolicy
    try fixture.writeDocument(oversizedDocument)
    await #expect(throws: AgentWorkspaceError(code: .internalSaveFailure)) {
      _ = try await fixture.reloadedStore().currentState()
    }

    var validPolicy = expectedPolicy
    validPolicy["generation"] = "00000000-0000-4000-8000-000000000164"
    var validDocument = try fixture.readDocument()
    validDocument["schemaVersion"] = 3
    validDocument["privacyPolicy"] = validPolicy
    let oversizedBytes = try JSONSerialization.data(withJSONObject: validDocument)
    try oversizedBytes.write(to: fixture.capabilitiesURL)
    let oversizedHandle = try FileHandle(forWritingTo: fixture.capabilitiesURL)
    try oversizedHandle.seek(toOffset: 64 * 1_024 * 1_024)
    try oversizedHandle.write(contentsOf: Data([0x20]))
    try oversizedHandle.close()
    await #expect(throws: AgentWorkspaceError(code: .internalSaveFailure)) {
      _ = try await fixture.reloadedStore().currentState()
    }
  }

  @Test func policyRevisionOverflowRejectsWithoutChangingEitherGeneration()
    async throws
  {
    let fixture = try PrivacyExclusionFixture()
    defer { fixture.remove() }
    let profileID = privacyTestUUID("00000000-0000-4000-8000-000000000171")
    _ = try await fixture.store.loadOrMigrate(
      activeProfileIDs: [profileID],
      workspace: Workspace()
    )
    var document = try fixture.readDocument()
    var profiles = try #require(document["profiles"] as? [[String: Any]])
    profiles[0]["grantRevision"] = NSNumber(value: UInt64.max)
    document["profiles"] = profiles
    try fixture.writeDocument(document)
    let currentBefore = try Data(contentsOf: fixture.capabilitiesURL)
    let backupBefore = try? Data(contentsOf: fixture.previousCapabilitiesURL)

    await #expect(throws: AgentWorkspaceError(code: .invalidPayload)) {
      _ = try await fixture.reloadedStore().replacePrivacyPolicy(
        deniedNoteIDs: [privacyTestUUID("00000000-0000-4000-8000-000000000172")],
        deniedFolderIDs: [],
        expectedGeneration: nil
      )
    }
    #expect(try Data(contentsOf: fixture.capabilitiesURL) == currentBefore)
    #expect((try? Data(contentsOf: fixture.previousCapabilitiesURL)) == backupBefore)
  }

  @Test func policyCurrentLossOrCorruptionNeverPromotesPrivateBackup() async throws {
    for damage in ["corrupt", "missing"] {
      let fixture = try PrivacyExclusionFixture()
      defer { fixture.remove() }
      let profileID = privacyTestUUID("00000000-0000-4000-8000-000000000181")
      let noteID = privacyTestUUID("00000000-0000-4000-8000-000000000182")
      _ = try await fixture.store.loadOrMigrate(
        activeProfileIDs: [profileID],
        workspace: Workspace(notes: [Note(id: noteID, agentAccess: true)])
      )
      let policyState = try await fixture.store.replacePrivacyPolicy(
        deniedNoteIDs: [noteID],
        deniedFolderIDs: [],
        expectedGeneration: nil
      )
      let currentBefore = try Data(contentsOf: fixture.capabilitiesURL)
      let backupBefore = try Data(contentsOf: fixture.previousCapabilitiesURL)
      if damage == "corrupt" {
        try Data("corrupt-current-with-policy".utf8).write(to: fixture.capabilitiesURL)
      } else {
        try FileManager.default.removeItem(at: fixture.capabilitiesURL)
      }
      let damagedCurrent = try? Data(contentsOf: fixture.capabilitiesURL)
      await #expect(throws: AgentWorkspaceError(code: .internalSaveFailure)) {
        _ = try await fixture.reloadedStore().currentState()
      }
      #expect((try? Data(contentsOf: fixture.capabilitiesURL)) == damagedCurrent)
      #expect(try Data(contentsOf: fixture.previousCapabilitiesURL) == backupBefore)
      #expect(policyState.privacyPolicy != nil)
      if damage == "corrupt" {
        #expect(damagedCurrent != currentBefore)
      } else {
        #expect(damagedCurrent == nil)
      }
    }
  }

  @Test func unknownCurrentSchemaCannotFallBackToLegacyBackup() async throws {
    let fixture = try PrivacyExclusionFixture()
    defer { fixture.remove() }
    _ = try await fixture.store.loadOrMigrate(
      activeProfileIDs: [],
      workspace: Workspace()
    )
    let legacyBytes = try Data(contentsOf: fixture.capabilitiesURL)
    try legacyBytes.write(to: fixture.previousCapabilitiesURL)
    var unknown = try fixture.readDocument()
    unknown["schemaVersion"] = 99
    try fixture.writeDocument(unknown)
    let currentBefore = try Data(contentsOf: fixture.capabilitiesURL)
    let backupBefore = try Data(contentsOf: fixture.previousCapabilitiesURL)

    await #expect(throws: AgentWorkspaceError(code: .internalSaveFailure)) {
      _ = try await fixture.reloadedStore().currentState()
    }
    #expect(try Data(contentsOf: fixture.capabilitiesURL) == currentBefore)
    #expect(try Data(contentsOf: fixture.previousCapabilitiesURL) == backupBefore)
  }

  @Test func policyWritesRecognizeCompletedAfterWriteThrowsAndFailClosedBeforeCurrent()
    async throws
  {
    for fault in [
      PrivacyWriteFault.beforeBackup,
      PrivacyWriteFault.afterBackup,
      PrivacyWriteFault.beforeCurrent,
      PrivacyWriteFault.afterCurrent,
    ] {
      let controller = PrivacyWriteFaultController()
      let fixture = try PrivacyExclusionFixture(writeData: { data, url in
        try controller.write(data, to: url)
      })
      defer { fixture.remove() }
      let profileID = privacyTestUUID("00000000-0000-4000-8000-000000000191")
      let noteID = privacyTestUUID("00000000-0000-4000-8000-000000000192")
      let initial = try await fixture.store.loadOrMigrate(
        activeProfileIDs: [profileID],
        workspace: Workspace()
      )
      let currentBefore = try Data(contentsOf: fixture.capabilitiesURL)
      let backupBefore = try? Data(contentsOf: fixture.previousCapabilitiesURL)
      controller.arm(fault)

      if fault == .afterBackup || fault == .afterCurrent {
        let updated = try await fixture.store.replacePrivacyPolicy(
          deniedNoteIDs: [noteID],
          deniedFolderIDs: [],
          expectedGeneration: nil
        )
        #expect(updated.privacyPolicy?.deniedNoteIDs == [noteID])
        let initialRevision = try #require(initial.profiles[profileID]).grantRevision
        #expect(updated.profiles[profileID]?.grantRevision == initialRevision + 1)
        #expect(try fixture.readDocument()["schemaVersion"] as? Int == 3)
      } else {
        await #expect(throws: AgentWorkspaceError(code: .internalSaveFailure)) {
          _ = try await fixture.store.replacePrivacyPolicy(
            deniedNoteIDs: [noteID],
            deniedFolderIDs: [],
            expectedGeneration: nil
          )
        }
        #expect(try Data(contentsOf: fixture.capabilitiesURL) == currentBefore)
        if fault == .beforeBackup {
          #expect((try? Data(contentsOf: fixture.previousCapabilitiesURL)) == backupBefore)
        } else {
          let failedCurrent = try Data(contentsOf: fixture.capabilitiesURL)
          let failedBackup = try Data(contentsOf: fixture.previousCapabilitiesURL)
          #expect(failedCurrent == currentBefore)
          #expect(try fixture.readPolicy(from: failedBackup).deniedNoteIDs == [noteID])
          await #expect(throws: AgentWorkspaceError(code: .internalSaveFailure)) {
            _ = try await fixture.reloadedStore().currentState()
          }
          #expect(try Data(contentsOf: fixture.capabilitiesURL) == failedCurrent)
          #expect(try Data(contentsOf: fixture.previousCapabilitiesURL) == failedBackup)
        }
      }
    }
  }
}

private struct PrivacyExclusionFixture {
  let ownedRoot: OwnedMCPFixtureRoot
  let rootURL: URL
  let capabilitiesURL: URL
  let previousCapabilitiesURL: URL
  let store: AgentCapabilityStore

  init(
    writeData: (@Sendable (Data, URL) throws -> Void)? = nil
  ) throws {
    let ownedRoot = try OwnedMCPFixtureRoot.create(kind: .privacyExclusion)
    self.ownedRoot = ownedRoot
    rootURL = ownedRoot.url
    capabilitiesURL =
      rootURL
      .appendingPathComponent("AgentIntegrations", isDirectory: true)
      .appendingPathComponent("capabilities.json")
    previousCapabilitiesURL =
      rootURL
      .appendingPathComponent("AgentIntegrations", isDirectory: true)
      .appendingPathComponent("capabilities.previous.json")
    store = AgentCapabilityStore(
      capabilitiesURL: capabilitiesURL,
      previousCapabilitiesURL: previousCapabilitiesURL,
      writeData: writeData
    )
  }

  func remove() {
    do {
      try ownedRoot.cleanup()
    } catch {
      Issue.record("Owned MCP fixture cleanup failed: \(error)")
    }
  }

  func reloadedStore() -> AgentCapabilityStore {
    AgentCapabilityStore(
      capabilitiesURL: capabilitiesURL,
      previousCapabilitiesURL: previousCapabilitiesURL
    )
  }

  func readDocument(at url: URL? = nil) throws -> [String: Any] {
    guard
      let document = try JSONSerialization.jsonObject(
        with: Data(contentsOf: url ?? capabilitiesURL)
      ) as? [String: Any]
    else {
      throw PrivacyExclusionTestError.invalidDocument
    }
    return document
  }

  func readPolicy(_ document: [String: Any]) throws -> AgentCapabilityPrivacyPolicy {
    guard let raw = document["privacyPolicy"] as? [String: Any],
      let generationString = raw["generation"] as? String,
      let generation = UUID(uuidString: generationString),
      let noteStrings = raw["deniedNoteIDs"] as? [String],
      let folderStrings = raw["deniedFolderIDs"] as? [String],
      let noteIDs = Optional(noteStrings.compactMap { UUID(uuidString: $0) }),
      let folderIDs = Optional(folderStrings.compactMap { UUID(uuidString: $0) }),
      noteIDs.count == noteStrings.count,
      folderIDs.count == folderStrings.count
    else {
      throw PrivacyExclusionTestError.invalidDocument
    }
    return AgentCapabilityPrivacyPolicy(
      generation: generation,
      deniedNoteIDs: Set(noteIDs),
      deniedFolderIDs: Set(folderIDs)
    )
  }

  func readPolicy(from data: Data) throws -> AgentCapabilityPrivacyPolicy {
    guard let document = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { throw PrivacyExclusionTestError.invalidDocument }
    return try readPolicy(document)
  }

  func writeDocument(_ document: [String: Any]) throws {
    let data = try JSONSerialization.data(
      withJSONObject: document,
      options: [.prettyPrinted, .sortedKeys]
    )
    try data.write(to: capabilitiesURL)
  }
}

private enum PrivacyWriteFault: Equatable {
  case beforeBackup
  case afterBackup
  case beforeCurrent
  case afterCurrent
}

private final class PrivacyWriteFaultController: @unchecked Sendable {
  private let lock = NSLock()
  private var fault: PrivacyWriteFault?

  func arm(_ fault: PrivacyWriteFault) {
    lock.withLock { self.fault = fault }
  }

  func write(_ data: Data, to url: URL) throws {
    let selected = lock.withLock { fault }
    let isBackup = url.lastPathComponent == "capabilities.previous.json"
    let shouldFail =
      switch selected {
      case .beforeBackup: isBackup
      case .afterBackup: isBackup
      case .beforeCurrent: !isBackup
      case .afterCurrent: !isBackup
      case nil: false
      }
    guard shouldFail else {
      try data.write(to: url, options: .atomic)
      return
    }
    switch selected {
    case .afterBackup, .afterCurrent:
      try data.write(to: url, options: .atomic)
      throw PrivacyExclusionTestError.injectedWriteFailure
    default:
      throw PrivacyExclusionTestError.injectedWriteFailure
    }
  }
}

private func attemptPolicyUpdate(
  with store: AgentCapabilityStore,
  deniedNoteID: UUID
) async -> Result<AgentCapabilityState, Error> {
  do {
    return .success(
      try await store.replacePrivacyPolicy(
        deniedNoteIDs: [deniedNoteID],
        deniedFolderIDs: [],
        expectedGeneration: nil
      )
    )
  } catch {
    return .failure(error)
  }
}

private func privacyTestUUID(_ value: String) -> UUID {
  UUID(uuidString: value)!
}

private enum PrivacyExclusionTestError: Error {
  case invalidDocument
  case injectedWriteFailure
}
