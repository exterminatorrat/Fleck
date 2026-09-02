import Foundation
import Testing

@testable import FleckCore

@Test func AgentAuthorityIsCumulative() {
  #expect(AgentAuthority.read.allows(.read))
  #expect(!AgentAuthority.read.allows(.propose))
  #expect(!AgentAuthority.read.allows(.write))
  #expect(AgentAuthority.propose.allows(.read))
  #expect(AgentAuthority.propose.allows(.propose))
  #expect(!AgentAuthority.propose.allows(.write))
  #expect(AgentAuthority.write.allows(.read))
  #expect(AgentAuthority.write.allows(.propose))
  #expect(AgentAuthority.write.allows(.write))
}

@Test func AgentCapabilityRawValuesAreStable() {
  #expect(AgentCapability.listNotes.rawValue == "notes.list")
  #expect(AgentCapability.readNotes.rawValue == "notes.read")
  #expect(AgentCapability.writeNotes.rawValue == "notes.write")
  #expect(AgentCapability.undoChanges.rawValue == "changes.undo")
  #expect(AgentAuthority.read.rawValue == "read")
  #expect(AgentAuthority.propose.rawValue == "propose")
  #expect(AgentAuthority.write.rawValue == "write")
}

@Test func CapabilityModelsRoundTripThroughCodable() throws {
  let noteID = testUUID("00000000-0000-0000-0000-000000000001")
  let folderID = testUUID("00000000-0000-0000-0000-000000000002")
  let profileID = testUUID("00000000-0000-0000-0000-000000000003")
  let grants = [
    AgentResourceGrant(
      id: testUUID("00000000-0000-0000-0000-000000000004"),
      scope: .note(noteID: noteID),
      authority: .read
    ),
    AgentResourceGrant(
      id: testUUID("00000000-0000-0000-0000-000000000005"),
      scope: .folderIncludingFutureNotes(folderID: folderID),
      authority: .write
    ),
  ]
  let profile = AgentProfileCapabilities(
    profileID: profileID,
    grantRevision: 7,
    allowedCapabilities: Set(AgentCapability.allCases),
    grants: grants
  )
  let summary = AgentCapabilitySummary(
    grantRevision: 7,
    availableCapabilities: [.listNotes, .readNotes]
  )
  let encoder = JSONEncoder()
  let decoder = JSONDecoder()

  #expect(
    try decoder.decode(
      AgentCapability.self,
      from: encoder.encode(AgentCapability.writeNotes)
    ) == .writeNotes
  )
  #expect(
    try decoder.decode(
      AgentAuthority.self,
      from: encoder.encode(AgentAuthority.propose)
    ) == .propose
  )
  #expect(try decoder.decode(AgentGrantScope.self, from: encoder.encode(AgentGrantScope.note(noteID: noteID))) == .note(noteID: noteID))
  #expect(try decoder.decode(AgentResourceGrant.self, from: encoder.encode(grants[1])) == grants[1])
  #expect(try decoder.decode(AgentProfileCapabilities.self, from: encoder.encode(profile)) == profile)
  #expect(try decoder.decode(AgentCapabilitySummary.self, from: encoder.encode(summary)) == summary)
}

@Test func CapabilitySetsAndGrantsEncodeDeterministically() throws {
  let profileID = testUUID("00000000-0000-0000-0000-000000000010")
  let firstGrant = AgentResourceGrant(
    id: testUUID("00000000-0000-0000-0000-000000000011"),
    scope: .folderIncludingFutureNotes(
      folderID: testUUID("00000000-0000-0000-0000-000000000013")
    ),
    authority: .write
  )
  let secondGrant = AgentResourceGrant(
    id: testUUID("00000000-0000-0000-0000-000000000012"),
    scope: .note(
      noteID: testUUID("00000000-0000-0000-0000-000000000014")
    ),
    authority: .read
  )
  let first = AgentProfileCapabilities(
    profileID: profileID,
    grantRevision: 1,
    allowedCapabilities: [.writeNotes, .listNotes, .undoChanges, .readNotes],
    grants: [firstGrant, secondGrant]
  )
  let second = AgentProfileCapabilities(
    profileID: profileID,
    grantRevision: 1,
    allowedCapabilities: [.readNotes, .undoChanges, .listNotes, .writeNotes],
    grants: [secondGrant, firstGrant]
  )
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys]

  #expect(try encoder.encode(first) == encoder.encode(second))
  #expect(first == second)

  let decoder = JSONDecoder()
  #expect(
    try decoder.decode(
      AgentProfileCapabilities.self,
      from: encoder.encode(first)
    ) == first
  )
}

@Test func DirectNoteGrantSurvivesFolderMoves() throws {
  let firstFolder = try Folder(
    id: testUUID("00000000-0000-0000-0000-000000000020"),
    name: "First"
  )
  let secondFolder = try Folder(
    id: testUUID("00000000-0000-0000-0000-000000000021"),
    name: "Second"
  )
  let note = Note(
    id: testUUID("00000000-0000-0000-0000-000000000022"),
    folderID: firstFolder.id
  )
  let profile = makeProfile(
    grants: [
      AgentResourceGrant(
        scope: .note(noteID: note.id),
        authority: .write
      ),
    ]
  )
  var workspace = Workspace(notes: [note], folders: [firstFolder, secondFolder])

  let beforeMove = AgentCapabilityPolicy.authorizationSnapshot(
    for: profile,
    workspace: workspace
  )
  try workspace.moveNote(id: note.id, toFolderID: secondFolder.id)
  let afterMove = AgentCapabilityPolicy.authorizationSnapshot(
    for: profile,
    workspace: workspace
  )

  #expect(beforeMove.readableNoteIDs == [note.id])
  #expect(beforeMove.writableNoteIDs == [note.id])
  #expect(afterMove.readableNoteIDs == [note.id])
  #expect(afterMove.writableNoteIDs == [note.id])
}

@Test func DynamicFolderGrantTracksMembership() throws {
  let folder = try Folder(
    id: testUUID("00000000-0000-0000-0000-000000000030"),
    name: "Projects"
  )
  let inside = Note(
    id: testUUID("00000000-0000-0000-0000-000000000031"),
    folderID: folder.id
  )
  let outside = Note(id: testUUID("00000000-0000-0000-0000-000000000032"))
  let profile = makeProfile(
    grants: [
      AgentResourceGrant(
        scope: .folderIncludingFutureNotes(folderID: folder.id),
        authority: .write
      ),
    ]
  )
  var workspace = Workspace(notes: [inside, outside], folders: [folder])

  let initial = AgentCapabilityPolicy.authorizationSnapshot(
    for: profile,
    workspace: workspace
  )
  try workspace.moveNote(id: outside.id, toFolderID: folder.id)
  let afterEntering = AgentCapabilityPolicy.authorizationSnapshot(
    for: profile,
    workspace: workspace
  )
  try workspace.moveNote(id: inside.id, toFolderID: nil)
  let afterLeaving = AgentCapabilityPolicy.authorizationSnapshot(
    for: profile,
    workspace: workspace
  )

  #expect(initial.readableNoteIDs == [inside.id])
  #expect(initial.writableNoteIDs == [inside.id])
  #expect(afterEntering.readableNoteIDs == Set([inside.id, outside.id]))
  #expect(afterEntering.writableNoteIDs == Set([inside.id, outside.id]))
  #expect(afterLeaving.readableNoteIDs == [outside.id])
  #expect(afterLeaving.writableNoteIDs == [outside.id])
}

@Test func DynamicFolderGrantIsRevokedWhenFolderIsDeleted() throws {
  let folder = try Folder(
    id: testUUID("00000000-0000-0000-0000-000000000040"),
    name: "Projects"
  )
  let note = Note(
    id: testUUID("00000000-0000-0000-0000-000000000041"),
    folderID: folder.id
  )
  let profile = makeProfile(
    grants: [
      AgentResourceGrant(
        scope: .folderIncludingFutureNotes(folderID: folder.id),
        authority: .read
      ),
    ]
  )
  var workspace = Workspace(notes: [note], folders: [folder])

  #expect(
    AgentCapabilityPolicy.authorizationSnapshot(for: profile, workspace: workspace)
      .readableNoteIDs == [note.id]
  )
  try workspace.deleteFolder(id: folder.id)
  let result = AgentCapabilityPolicy.authorizationSnapshot(
    for: profile,
    workspace: workspace
  )

  #expect(result.readableNoteIDs.isEmpty)
  #expect(result.proposableNoteIDs.isEmpty)
  #expect(result.writableNoteIDs.isEmpty)
  #expect(result.availableCapabilities.isEmpty)
}

@Test func OverlappingGrantsUnionAuthorities() throws {
  let folder = try Folder(
    id: testUUID("00000000-0000-0000-0000-000000000050"),
    name: "Projects"
  )
  let overlapping = Note(
    id: testUUID("00000000-0000-0000-0000-000000000051"),
    folderID: folder.id
  )
  let proposable = Note(id: testUUID("00000000-0000-0000-0000-000000000052"))
  let readable = Note(id: testUUID("00000000-0000-0000-0000-000000000053"))
  let profile = makeProfile(
    grants: [
      AgentResourceGrant(
        scope: .note(noteID: overlapping.id),
        authority: .read
      ),
      AgentResourceGrant(
        scope: .folderIncludingFutureNotes(folderID: folder.id),
        authority: .write
      ),
      AgentResourceGrant(
        scope: .note(noteID: proposable.id),
        authority: .propose
      ),
      AgentResourceGrant(
        scope: .note(noteID: readable.id),
        authority: .read
      ),
    ]
  )

  let result = AgentCapabilityPolicy.authorizationSnapshot(
    for: profile,
    workspace: Workspace(notes: [overlapping, proposable, readable], folders: [folder])
  )

  #expect(result.readableNoteIDs == Set([overlapping.id, proposable.id, readable.id]))
  #expect(result.proposableNoteIDs == Set([overlapping.id, proposable.id]))
  #expect(result.writableNoteIDs == [overlapping.id])
  #expect(result.availableCapabilities == Set(AgentCapability.allCases))

  let reversedProfile = makeProfile(grants: Array(profile.grants.reversed()))
  let reversedResult = AgentCapabilityPolicy.authorizationSnapshot(
    for: reversedProfile,
    workspace: Workspace(notes: [overlapping, proposable, readable], folders: [folder])
  )
  #expect(result == reversedResult)
}

@Test func CapabilitiesRequireAllowedCapabilityAndEffectiveAuthority() {
  let note = Note(id: testUUID("00000000-0000-0000-0000-000000000060"))
  let profile = AgentProfileCapabilities(
    profileID: testUUID("00000000-0000-0000-0000-000000000061"),
    grantRevision: 2,
    allowedCapabilities: [.writeNotes],
    grants: [
      AgentResourceGrant(scope: .note(noteID: note.id), authority: .read),
    ]
  )

  let result = AgentCapabilityPolicy.authorizationSnapshot(
    for: profile,
    workspace: Workspace(notes: [note])
  )

  #expect(result.readableNoteIDs == [note.id])
  #expect(result.writableNoteIDs.isEmpty)
  #expect(result.availableCapabilities.isEmpty)
}

@Test func ProposeOnlyNoteGrantExposesReadCapabilitiesWithoutWriteCapabilities() {
  let note = Note(id: testUUID("00000000-0000-0000-0000-000000000062"))
  let profile = AgentProfileCapabilities(
    profileID: testUUID("00000000-0000-0000-0000-000000000063"),
    grantRevision: 3,
    allowedCapabilities: Set(AgentCapability.allCases),
    grants: [
      AgentResourceGrant(scope: .note(noteID: note.id), authority: .propose),
    ]
  )

  let result = AgentCapabilityPolicy.authorizationSnapshot(
    for: profile,
    workspace: Workspace(notes: [note])
  )

  #expect(result.readableNoteIDs == [note.id])
  #expect(result.proposableNoteIDs == [note.id])
  #expect(result.writableNoteIDs.isEmpty)
  #expect(result.availableCapabilities == Set([.listNotes, .readNotes]))
  #expect(!result.availableCapabilities.contains(.writeNotes))
  #expect(!result.availableCapabilities.contains(.undoChanges))
}

@Test func EmptyOrUnknownScopesProduceNoAccess() {
  let note = Note(
    id: testUUID("00000000-0000-0000-0000-000000000070"),
    agentAccess: true,
    folderID: testUUID("00000000-0000-0000-0000-000000000071")
  )
  let profile = AgentProfileCapabilities(
    profileID: testUUID("00000000-0000-0000-0000-000000000072"),
    grantRevision: 1,
    allowedCapabilities: Set(AgentCapability.allCases),
    grants: [
      AgentResourceGrant(
        scope: .folderIncludingFutureNotes(folderID: note.folderID!),
        authority: .write
      ),
    ]
  )

  let result = AgentCapabilityPolicy.authorizationSnapshot(
    for: profile,
    workspace: Workspace(notes: [note])
  )

  #expect(result.readableNoteIDs.isEmpty)
  #expect(result.proposableNoteIDs.isEmpty)
  #expect(result.writableNoteIDs.isEmpty)
  #expect(result.availableCapabilities.isEmpty)
}

@Test func EmptyGrantScopeProducesNoAccess() {
  let note = Note(id: testUUID("00000000-0000-0000-0000-000000000073"))
  let profile = makeProfile(grants: [])

  let result = AgentCapabilityPolicy.authorizationSnapshot(
    for: profile,
    workspace: Workspace(notes: [note])
  )

  #expect(result.readableNoteIDs.isEmpty)
  #expect(result.proposableNoteIDs.isEmpty)
  #expect(result.writableNoteIDs.isEmpty)
  #expect(result.availableCapabilities.isEmpty)
}

@Test func AuthorizationSnapshotPreservesProfileRevisionAndIdentity() {
  let profileID = testUUID("00000000-0000-0000-0000-000000000080")
  let profile = AgentProfileCapabilities(
    profileID: profileID,
    grantRevision: 19,
    allowedCapabilities: [],
    grants: []
  )

  let result = AgentCapabilityPolicy.authorizationSnapshot(
    for: profile,
    workspace: Workspace()
  )

  #expect(result.profileID == profileID)
  #expect(result.grantRevision == 19)
}

@Test func AuthorizationPolicyIsDeterministicAndDoesNotMutateInputs() throws {
  let folder = try Folder(
    id: testUUID("00000000-0000-0000-0000-000000000090"),
    name: "Projects"
  )
  let first = Note(
    id: testUUID("00000000-0000-0000-0000-000000000091"),
    folderID: folder.id
  )
  let second = Note(id: testUUID("00000000-0000-0000-0000-000000000092"))
  let profile = makeProfile(
    grants: [
      AgentResourceGrant(scope: .note(noteID: second.id), authority: .propose),
      AgentResourceGrant(
        scope: .folderIncludingFutureNotes(folderID: folder.id),
        authority: .write
      ),
    ]
  )
  let workspace = Workspace(notes: [first, second], folders: [folder])

  let firstResult = AgentCapabilityPolicy.authorizationSnapshot(
    for: profile,
    workspace: workspace
  )
  let secondResult = AgentCapabilityPolicy.authorizationSnapshot(
    for: profile,
    workspace: workspace
  )

  #expect(firstResult == secondResult)
  #expect(workspace == Workspace(notes: [first, second], folders: [folder]))
  #expect(profile == makeProfile(
    profileID: profile.profileID,
    grantRevision: profile.grantRevision,
    allowedCapabilities: profile.allowedCapabilities,
    grants: profile.grants
  ))
}

private func makeProfile(
  profileID: UUID = testUUID("00000000-0000-0000-0000-0000000000A0"),
  grantRevision: UInt64 = 1,
  allowedCapabilities: Set<AgentCapability> = Set(AgentCapability.allCases),
  grants: [AgentResourceGrant]
) -> AgentProfileCapabilities {
  AgentProfileCapabilities(
    profileID: profileID,
    grantRevision: grantRevision,
    allowedCapabilities: allowedCapabilities,
    grants: grants
  )
}

private func testUUID(_ rawValue: String) -> UUID {
  UUID(uuidString: rawValue)!
}
