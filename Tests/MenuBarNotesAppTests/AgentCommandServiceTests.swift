import AppKit
import CryptoKit
import Foundation
import MenuBarNotesCore
import Testing

@testable import MenuBarNotesApp

@Test @MainActor func agentServiceRejectsEveryCommandWhenInitialLoadFailed() async throws {
  let fixture = AgentServiceFixture()
  fixture.state.isAgentWorkspaceAvailable = false

  await #expect(throws: AgentWorkspaceError.self) {
    try await fixture.service.execute(
      profileID: fixture.profile.id,
      credential: Data("credential".utf8),
      command: .listSharedNotes
    )
  }
  do {
    _ = try await fixture.service.execute(
      profileID: fixture.profile.id,
      credential: Data("credential".utf8),
      command: .listSharedNotes
    )
    Issue.record("Expected unavailable workspace")
  } catch let error as AgentWorkspaceError {
    #expect(error.code == .motesUnavailable)
    #expect(error.recoveryAction != nil)
  }
}

@Test @MainActor func unknownAndUnsharedNotesHaveIdenticalErrors() async throws {
  let fixture = AgentServiceFixture(shared: false)
  let unknown = UUID()
  let commands: [AgentWorkspaceCommand] = [
    .readNote(request: .init(noteID: unknown)),
    .readNote(request: .init(noteID: fixture.note.id)),
  ]
  var encoded: [Data] = []

  for command in commands {
    do {
      _ = try await fixture.execute(command)
      Issue.record("Expected note_not_found")
    } catch let error as AgentWorkspaceError {
      encoded.append(try JSONEncoder().encode(error))
    }
  }

  #expect(encoded.count == 2)
  #expect(encoded[0] == encoded[1])
}

@Test @MainActor func staleAgentWriteIsRejectedBeforeMutation() async throws {
  let fixture = AgentServiceFixture()
  let command = AgentWorkspaceCommand.appendText(
    request: .init(
      context: .init(
        noteID: fixture.note.id,
        expectedRevision: fixture.note.revision + 1,
        operationID: UUID()
      ),
      text: "Later"
    )
  )

  await #expect(throws: AgentWorkspaceError(code: .revisionConflict)) {
    try await fixture.execute(command)
  }
  #expect(fixture.state.workspace.notes[0].body == fixture.note.body)
  #expect(fixture.state.commitCount == 0)
}

@Test @MainActor func successfulAgentWriteCommitsOnceAndPublishesFeedback() async throws {
  let fixture = AgentServiceFixture()
  let operationID = UUID()

  let response = try await fixture.execute(
    .appendText(
      request: .init(
        context: .init(
          noteID: fixture.note.id,
          expectedRevision: fixture.note.revision,
          operationID: operationID
        ),
        text: "Agent text"
      )
    )
  )

  guard case .write(let receipt) = response else {
    Issue.record("Expected write receipt")
    return
  }
  #expect(receipt.previousRevision == fixture.note.revision)
  #expect(receipt.resultingRevision == fixture.note.revision + 1)
  #expect(fixture.state.workspace.notes[0].body == "Original\n\nAgent text")
  #expect(fixture.state.workspace.notes[0].revision == fixture.note.revision + 1)
  #expect(fixture.state.commitCount == 1)
  #expect(fixture.state.latestFeedback?.changeID == receipt.changeID)
  #expect(
    fixture.activityStore.list(
      profileID: fixture.profile.id,
      visibleNoteIDs: [fixture.note.id]
    ).count == 1
  )
}

@Test @MainActor func duplicateOperationReturnsReceiptWithoutSecondMutation() async throws {
  let fixture = AgentServiceFixture()
  let operationID = UUID()
  let command = AgentWorkspaceCommand.appendText(
    request: .init(
      context: .init(
        noteID: fixture.note.id,
        expectedRevision: fixture.note.revision,
        operationID: operationID
      ),
      text: "Once"
    )
  )

  let first = try await fixture.execute(command)
  let second = try await fixture.execute(command)

  #expect(first == second)
  #expect(fixture.state.commitCount == 1)
  #expect(fixture.state.workspace.notes[0].body == "Original\n\nOnce")
}

@Test @MainActor func commitFailureAbortsPreparationAndPublishesNothing() async throws {
  let fixture = AgentServiceFixture()
  fixture.state.commitError = AgentWorkspaceError(code: .internalSaveFailure)
  let operationID = UUID()

  await #expect(throws: AgentWorkspaceError(code: .internalSaveFailure)) {
    try await fixture.execute(
      .appendText(
        request: .init(
          context: .init(
            noteID: fixture.note.id,
            expectedRevision: fixture.note.revision,
            operationID: operationID
          ),
          text: "Never"
        )
      )
    )
  }

  #expect(fixture.state.workspace.notes[0] == fixture.note)
  #expect(fixture.state.latestFeedback == nil)
  #expect(
    fixture.activityStore.priorReceipt(
      actor: .integration(
        profileID: fixture.profile.id,
        displayName: fixture.profile.displayName
      ),
      operationID: operationID
    ) == nil
  )
}

@Test @MainActor func generationChangeDuringAuthorizationRejectsWithoutOverwritingHumanEdit()
  async throws
{
  let gate = AgentAuthorizationGate()
  let fixture = AgentServiceFixture(authorizer: gate)
  let command = AgentWorkspaceCommand.appendText(
    request: .init(
      context: .init(
        noteID: fixture.note.id,
        expectedRevision: fixture.note.revision,
        operationID: UUID()
      ),
      text: "Agent"
    )
  )

  let task = Task { @MainActor in try await fixture.execute(command) }
  await gate.waitUntilAuthorizationStarted()
  fixture.state.humanEdit(body: "Human")
  await gate.resume(with: fixture.profile)

  await #expect(throws: AgentWorkspaceError(code: .revisionConflict)) {
    try await task.value
  }
  #expect(fixture.state.workspace.notes[0].body == "Human")
  #expect(fixture.state.commitCount == 0)
}

@Test @MainActor func concurrentCommandsAuthorizeAndCommitInFIFOOrder() async throws {
  let gate = OrderedAgentAuthorizer()
  let fixture = AgentServiceFixture(authorizer: gate)
  let firstOperation = UUID()
  let first = Task { @MainActor in
    try await fixture.execute(
      .appendText(
        request: .init(
          context: .init(
            noteID: fixture.note.id,
            expectedRevision: fixture.note.revision,
            operationID: firstOperation
          ),
          text: "First"
        )
      )
    )
  }
  await gate.waitForCallCount(1)
  let second = Task { @MainActor in
    try await fixture.execute(.listSharedNotes)
  }
  try await Task.sleep(for: .milliseconds(30))
  #expect(await gate.callCount == 1)
  await gate.resumeNext(with: fixture.profile)
  _ = try await first.value
  await gate.waitForCallCount(2)
  await gate.resumeNext(with: fixture.profile)
  _ = try await second.value
  #expect(await gate.callCount == 2)
}

@Test @MainActor func localUndoSurvivesUnsharingAndRestoresExactAttributedChange() async throws {
  let fixture = AgentServiceFixture()
  let write = try await fixture.execute(
    .appendText(
      request: .init(
        context: .init(
          noteID: fixture.note.id,
          expectedRevision: fixture.note.revision,
          operationID: UUID()
        ),
        text: "Undo me"
      )
    )
  )
  guard case .write(let writeReceipt) = write else {
    Issue.record("Expected write")
    return
  }
  fixture.state.workspace.notes[0].agentAccess = false

  let response = try await fixture.service.executeLocalUndo(
    changeID: writeReceipt.changeID,
    expectedRevision: writeReceipt.resultingRevision,
    operationID: UUID()
  )

  guard case .undo(let receipt) = response else {
    Issue.record("Expected undo")
    return
  }
  #expect(receipt.resultingRevision == writeReceipt.resultingRevision + 1)
  #expect(fixture.state.workspace.notes[0].body == "Original")
  let undoRecord = try #require(fixture.activityStore.record(id: receipt.changeID))
  #expect(undoRecord.actor == .localUser)
  #expect(
    undoRecord.originatingActor
      == .integration(
        profileID: fixture.profile.id,
        displayName: fixture.profile.displayName
      )
  )
}

@Test @MainActor func authorizedUndoActivityReturnsOriginatingIntegration()
  async throws
{
  let fixture = AgentServiceFixture()
  let write = try await fixture.execute(
    .appendText(
      request: .init(
        context: .init(
          noteID: fixture.note.id,
          expectedRevision: fixture.note.revision,
          operationID: UUID()
        ),
        text: "Undo me"
      )
    )
  )
  guard case .write(let writeReceipt) = write else {
    Issue.record("Expected write")
    return
  }
  _ = try await fixture.execute(
    .undoChange(
      request: .init(
        changeID: writeReceipt.changeID,
        expectedRevision: writeReceipt.resultingRevision,
        operationID: UUID()
      )
    )
  )

  let response = try await fixture.execute(.listActivity)
  guard case .activity(let entries) = response,
    let undo = entries.first(where: { $0.operation == .undoChange })
  else {
    Issue.record("Expected Undo activity")
    return
  }
  #expect(
    undo.originatingActor
      == .integration(
        profileID: fixture.profile.id,
        displayName: fixture.profile.displayName
      )
  )
}

@Test @MainActor func undoingTaskCompletionUndoRestoresCompletedRichText()
  async throws
{
  let source = NSMutableAttributedString(string: "○ Ship release")
  source.addAttribute(
    .underlineStyle,
    value: NSUnderlineStyle.single.rawValue,
    range: NSRange(location: 2, length: "Ship release".utf16.count)
  )
  let note = Note(
    title: "Work",
    body: source.string,
    richTextRTF: try source.data(
      from: NSRange(location: 0, length: source.length),
      documentAttributes: [
        .documentType: NSAttributedString.DocumentType.rtf
      ]
    ),
    agentAccess: true,
    revision: 3
  )
  let fixture = AgentServiceFixture(note: note)
  guard
    case .tasks(let tasks) = try await fixture.execute(
      .listTasks(request: .init(noteID: note.id))
    ),
    let task = tasks.first
  else {
    Issue.record("Expected task")
    return
  }

  guard
    case .write(let completion) = try await fixture.execute(
      .setTaskState(
        request: .init(
          context: .init(
            noteID: note.id,
            expectedRevision: note.revision,
            operationID: UUID()
          ),
          taskHandle: task.taskHandle,
          completed: true
        )
      )
    )
  else {
    Issue.record("Expected completion")
    return
  }
  guard
    case .undo(let firstUndo) = try await fixture.execute(
      .undoChange(
        request: .init(
          changeID: completion.changeID,
          expectedRevision: completion.resultingRevision,
          operationID: UUID()
        )
      )
    )
  else {
    Issue.record("Expected first Undo")
    return
  }
  guard
    case .undo = try await fixture.execute(
      .undoChange(
        request: .init(
          changeID: firstUndo.changeID,
          expectedRevision: firstUndo.resultingRevision,
          operationID: UUID()
        )
      )
    )
  else {
    Issue.record("Expected second Undo")
    return
  }

  let restored = fixture.state.workspace.notes[0]
  #expect(restored.body == "● Ship release")
  let data = try #require(restored.richTextRTF)
  let attributed = try NSAttributedString(
    data: data,
    options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: nil
  )
  #expect(
    (attributed.attribute(
      .strikethroughStyle,
      at: 2,
      effectiveRange: nil
    ) as? Int) == NSUnderlineStyle.single.rawValue
  )
  #expect(
    (attributed.attribute(
      .underlineStyle,
      at: 2,
      effectiveRange: nil
    ) as? Int) == NSUnderlineStyle.single.rawValue
  )
}

@Test @MainActor func activityFailureAfterDurableCommitReconcilesOnRetry() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "AgentCommandServiceTests-\(UUID().uuidString)",
    isDirectory: true
  )
  defer { try? FileManager.default.removeItem(at: root) }
  let now = Date(timeIntervalSince1970: 500)
  let note = Note(
    title: "Shared",
    body: "Original",
    agentAccess: true,
    revision: 1
  )
  let profile = AgentIntegrationProfile(
    id: UUID(),
    displayName: "Codex",
    createdAt: now,
    lastConnectedAt: nil,
    revokedAt: nil
  )
  let state = FakeAgentWorkspaceState(
    workspace: Workspace(notes: [note], selectedNoteID: note.id)
  )
  let activity = FailOnceCommitActivityStore(
    base: AgentActivityStore(rootURL: root, now: { now })
  )
  let service = AgentCommandService(
    state: state,
    profileStore: FixedAgentAuthorizer(profile: profile),
    activityStore: activity,
    taskHandleCodec: AgentTaskHandleCodec(
      signingKeyProvider: FixedAgentSigningKeyProvider()
    ),
    now: { now }
  )
  let command = AgentWorkspaceCommand.appendText(
    request: .init(
      context: .init(
        noteID: note.id,
        expectedRevision: note.revision,
        operationID: UUID()
      ),
      text: "Once"
    )
  )

  await #expect(throws: AgentWorkspaceError(code: .internalSaveFailure)) {
    try await service.execute(
      profileID: profile.id,
      credential: Data(),
      command: command
    )
  }
  #expect(state.workspace.notes[0].body == "Original\n\nOnce")
  #expect(state.commitCount == 1)

  let retried = try await service.execute(
    profileID: profile.id,
    credential: Data(),
    command: command
  )
  guard case .write(let receipt) = retried else {
    Issue.record("Expected reconciled receipt")
    return
  }
  #expect(receipt.resultingRevision == 2)
  #expect(state.commitCount == 1)
}

@Test @MainActor func laterAmbiguousEditMakesLocalUndoUnsafe() async throws {
  let fixture = AgentServiceFixture()
  let write = try await fixture.execute(
    .appendText(
      request: .init(
        context: .init(
          noteID: fixture.note.id,
          expectedRevision: fixture.note.revision,
          operationID: UUID()
        ),
        text: "Repeated"
      )
    )
  )
  guard case .write(let receipt) = write else {
    Issue.record("Expected write")
    return
  }
  fixture.state.humanEdit(body: "X\nOriginal\n\nRepeated\n\nOriginal\n\nRepeated")

  await #expect(throws: AgentWorkspaceError(code: .revisionConflict)) {
    try await fixture.service.executeLocalUndo(
      changeID: receipt.changeID,
      expectedRevision: receipt.resultingRevision,
      operationID: UUID()
    )
  }
  let currentRevision = fixture.state.workspace.notes[0].revision
  await #expect(throws: AgentWorkspaceError(code: .unsafeUndo)) {
    try await fixture.service.executeLocalUndo(
      changeID: receipt.changeID,
      expectedRevision: currentRevision,
      operationID: UUID()
    )
  }
}

@Test @MainActor func unexpectedExecuteFailureIsContentFreeInternalSaveFailure()
  async throws
{
  let fixture = AgentServiceFixture(
    signingKeyProvider: ThrowingAgentSigningKeyProvider()
  )

  do {
    _ = try await fixture.execute(
      .addTask(
        request: .init(
          context: .init(
            noteID: fixture.note.id,
            expectedRevision: fixture.note.revision,
            operationID: UUID()
          ),
          text: "Task"
        )
      )
    )
    Issue.record("Expected internal save failure")
  } catch let error as AgentWorkspaceError {
    #expect(error == AgentWorkspaceError(code: .internalSaveFailure))
  }
}

@Test @MainActor func unexpectedLocalUndoFailureIsContentFreeInternalSaveFailure()
  async throws
{
  let fixture = AgentServiceFixture()
  fixture.state.flushError = UnexpectedAgentServiceTestError()

  do {
    _ = try await fixture.service.executeLocalUndo(
      changeID: UUID(),
      expectedRevision: fixture.note.revision,
      operationID: UUID()
    )
    Issue.record("Expected internal save failure")
  } catch let error as AgentWorkspaceError {
    #expect(error == AgentWorkspaceError(code: .internalSaveFailure))
  }
}

@Test @MainActor func activityUndoSafetyReflectsCurrentVisibleBody() async throws {
  let fixture = AgentServiceFixture()
  let write = try await fixture.execute(
    .appendText(
      request: .init(
        context: .init(
          noteID: fixture.note.id,
          expectedRevision: fixture.note.revision,
          operationID: UUID()
        ),
        text: "Unique"
      )
    )
  )
  guard case .write = write else {
    Issue.record("Expected write")
    return
  }

  let exact = try await fixture.execute(.listActivity)
  guard case .activity(let exactEntries) = exact else {
    Issue.record("Expected activity")
    return
  }
  #expect(exactEntries.map(\.canUndo) == [true])

  fixture.state.humanEdit(body: "Human\nOriginal\n\nUnique")
  let relocated = try await fixture.execute(.listActivity)
  guard case .activity(let relocatedEntries) = relocated else {
    Issue.record("Expected activity")
    return
  }
  #expect(relocatedEntries.map(\.canUndo) == [true])

  fixture.state.humanEdit(
    body: "X\nOriginal\n\nUnique\n\nOriginal\n\nUnique"
  )
  let ambiguous = try await fixture.execute(.listActivity)
  guard case .activity(let ambiguousEntries) = ambiguous else {
    Issue.record("Expected activity")
    return
  }
  #expect(ambiguousEntries.map(\.canUndo) == [false])
}

@Test @MainActor func recoveredLowerRevisionNeverAdvertisesCoincidentallyMatchingUndo()
  async throws
{
  let fixture = AgentServiceFixture()
  _ = try await fixture.execute(
    .appendText(
      request: .init(
        context: .init(
          noteID: fixture.note.id,
          expectedRevision: fixture.note.revision,
          operationID: UUID()
        ),
        text: "Coincidental"
      )
    )
  )
  fixture.state.workspace.notes[0].revision = fixture.note.revision - 1

  let response = try await fixture.execute(.listActivity)
  guard case .activity(let entries) = response else {
    Issue.record("Expected activity")
    return
  }
  #expect(entries.map(\.canUndo) == [false])
}

@Test @MainActor func recoveredLowerRevisionRejectsLocalUndoAsUnsafe()
  async throws
{
  let fixture = AgentServiceFixture()
  let write = try await fixture.execute(
    .appendText(
      request: .init(
        context: .init(
          noteID: fixture.note.id,
          expectedRevision: fixture.note.revision,
          operationID: UUID()
        ),
        text: "Coincidental"
      )
    )
  )
  guard case .write(let receipt) = write else {
    Issue.record("Expected write")
    return
  }
  fixture.state.workspace.notes[0].revision = fixture.note.revision - 1

  await #expect(throws: AgentWorkspaceError(code: .unsafeUndo)) {
    try await fixture.service.executeLocalUndo(
      changeID: receipt.changeID,
      expectedRevision: fixture.note.revision - 1,
      operationID: UUID()
    )
  }
}

@Test @MainActor func recoveredLowerRevisionRejectsAuthorizedUndoAsUnsafe()
  async throws
{
  let fixture = AgentServiceFixture()
  let write = try await fixture.execute(
    .appendText(
      request: .init(
        context: .init(
          noteID: fixture.note.id,
          expectedRevision: fixture.note.revision,
          operationID: UUID()
        ),
        text: "Coincidental"
      )
    )
  )
  guard case .write(let receipt) = write else {
    Issue.record("Expected write")
    return
  }
  fixture.state.workspace.notes[0].revision = fixture.note.revision - 1

  await #expect(throws: AgentWorkspaceError(code: .unsafeUndo)) {
    try await fixture.execute(
      .undoChange(
        request: .init(
          changeID: receipt.changeID,
          expectedRevision: fixture.note.revision - 1,
          operationID: UUID()
        )
      )
    )
  }
}

@Test @MainActor func appStateAgentCommitPersistsBodyRTFAndManifestProofBeforePublication()
  async throws
{
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "AgentCommandServiceTests-\(UUID().uuidString)",
    isDirectory: true
  )
  defer { try? FileManager.default.removeItem(at: root) }
  let store = LocalStore(rootURL: root)
  let state = AppState(store: store)
  await state.waitUntilInitialLoad()
  state.setSelectedAgentAccess(true)
  try await state.flushPendingPersistenceForAgent()
  let note = try #require(state.selectedNote)
  let profile = AgentIntegrationProfile(
    id: UUID(),
    displayName: "Codex",
    createdAt: Date(),
    lastConnectedAt: nil,
    revokedAt: nil
  )
  let activity = AgentActivityStore(rootURL: root)
  let service = AgentCommandService(
    state: state,
    profileStore: FixedAgentAuthorizer(profile: profile),
    activityStore: activity,
    taskHandleCodec: AgentTaskHandleCodec(
      signingKeyProvider: FixedAgentSigningKeyProvider()
    )
  )

  let response = try await service.execute(
    profileID: profile.id,
    credential: Data(),
    command: .appendText(
      request: .init(
        context: .init(
          noteID: note.id,
          expectedRevision: note.revision,
          operationID: UUID()
        ),
        text: "Durable"
      )
    )
  )
  guard case .write(let receipt) = response else {
    Issue.record("Expected write")
    return
  }
  let persisted = try await store.loadSnapshot()
  let persistedNote = try #require(
    persisted.workspace.notes.first(where: { $0.id == note.id })
  )

  #expect(persistedNote.body == state.selectedNote?.body)
  #expect(persistedNote.richTextRTF == state.selectedNote?.richTextRTF)
  #expect(persistedNote.revision == receipt.resultingRevision)
  #expect(
    persisted.commitProofs.contains {
      $0.changeID == receipt.changeID
        && $0.resultingRevision == receipt.resultingRevision
    }
  )
}

@Test @MainActor func appStateRollsBackUnchangedOptimisticRestoreAfterConflict()
  async throws
{
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "AgentCommandServiceTests-\(UUID().uuidString)",
    isDirectory: true
  )
  defer { try? FileManager.default.removeItem(at: root) }
  let store = LocalStore(rootURL: root)
  let remaining = Note(title: "Remaining")
  let deleted = Note(title: "Only copy", body: "Recover me")
  let active = Workspace(notes: [remaining], selectedNoteID: remaining.id)
  _ = try await store.save(
    workspace: active,
    preferences: .init(),
    trashedNotes: [deleted],
    generation: 2
  )
  let state = AppState(store: store)
  await state.waitUntilInitialLoad()
  let trashed = try #require(state.trashedNotes.first)
  _ = try await store.save(
    workspace: active,
    preferences: .init(),
    generation: state.persistenceGeneration + 2
  )

  state.restore(trashed)
  for _ in 0..<100 where state.saveError == nil {
    try await Task.sleep(for: .milliseconds(10))
  }

  #expect(!state.workspace.notes.contains { $0.id == deleted.id })
  #expect(state.trashedNotes.map(\.id) == [deleted.id])
  #expect(try await store.loadTrash().map(\.id) == [deleted.id])
}

@Test @MainActor func appStateDrainArchivesPendingTrashBeforeAgentCriticalSection()
  async throws
{
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "AgentCommandServiceTests-\(UUID().uuidString)",
    isDirectory: true
  )
  defer { try? FileManager.default.removeItem(at: root) }
  let store = LocalStore(rootURL: root)
  let state = AppState(store: store)
  await state.waitUntilInitialLoad()
  let deletedID = try #require(state.selectedNote?.id)
  state.addNote()
  state.setSelectedAgentAccess(true)
  state.moveToTrash(deletedID)

  try await state.flushPendingPersistenceForAgent()

  #expect(try await store.loadTrash().map(\.id) == [deletedID])
  #expect(state.workspace.notes.allSatisfy { $0.id != deletedID })
}

@Test @MainActor func appStateAgentDrainWaitsForAnOwnedDictationSave() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "AgentCommandServiceTests-\(UUID().uuidString)",
    isDirectory: true
  )
  defer { try? FileManager.default.removeItem(at: root) }
  let store = LocalStore(rootURL: root)
  let gate = AgentDrainSaveGate()
  let state = AppState(
    store: store,
    saveOperation: { workspace, preferences, trashedNotes, generation in
      try await gate.save(
        workspace: workspace,
        preferences: preferences,
        trashedNotes: trashedNotes,
        generation: generation
      )
    }
  )
  await state.waitUntilInitialLoad()
  let destinationID = try #require(state.selectedNote?.id)

  let dictationSave = Task { @MainActor in
    try await state.saveSmartCapture(
      text: "Dictated",
      captureID: UUID(),
      destinationID: destinationID
    )
  }
  await gate.waitUntilFirstSaveStarted()
  let agentDrain = Task { @MainActor in
    try await state.flushPendingPersistenceForAgent()
  }
  try await Task.sleep(for: .milliseconds(50))

  #expect(await gate.currentSaveCount() == 1)

  await gate.releaseFirstSave()
  _ = try await dictationSave.value
  try await agentDrain.value
  #expect(await gate.currentSaveCount() == 2)
}

@Test @MainActor func listActivityShowsOnlyCallerRecordsForCurrentlySharedNotes()
  async throws
{
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "AgentCommandServiceTests-\(UUID().uuidString)",
    isDirectory: true
  )
  defer { try? FileManager.default.removeItem(at: root) }
  let firstNote = Note(title: "First", agentAccess: true)
  let secondNote = Note(title: "Second", agentAccess: true)
  let state = FakeAgentWorkspaceState(
    workspace: Workspace(
      notes: [firstNote, secondNote],
      selectedNoteID: firstNote.id
    )
  )
  let firstProfile = AgentIntegrationProfile(
    id: UUID(),
    displayName: "Codex",
    createdAt: Date(),
    lastConnectedAt: nil,
    revokedAt: nil
  )
  let secondProfile = AgentIntegrationProfile(
    id: UUID(),
    displayName: "Claude",
    createdAt: Date(),
    lastConnectedAt: nil,
    revokedAt: nil
  )
  let activity = AgentActivityStore(rootURL: root)
  func service(_ profile: AgentIntegrationProfile) -> AgentCommandService {
    AgentCommandService(
      state: state,
      profileStore: FixedAgentAuthorizer(profile: profile),
      activityStore: activity,
      taskHandleCodec: AgentTaskHandleCodec(
        signingKeyProvider: FixedAgentSigningKeyProvider()
      )
    )
  }
  let firstService = service(firstProfile)
  let secondService = service(secondProfile)

  _ = try await firstService.execute(
    profileID: firstProfile.id,
    credential: Data(),
    command: .appendText(
      request: .init(
        context: .init(
          noteID: firstNote.id,
          expectedRevision: 0,
          operationID: UUID()
        ),
        text: "Codex"
      )
    )
  )
  _ = try await secondService.execute(
    profileID: secondProfile.id,
    credential: Data(),
    command: .appendText(
      request: .init(
        context: .init(
          noteID: firstNote.id,
          expectedRevision: 1,
          operationID: UUID()
        ),
        text: "Claude"
      )
    )
  )
  _ = try await firstService.execute(
    profileID: firstProfile.id,
    credential: Data(),
    command: .appendText(
      request: .init(
        context: .init(
          noteID: secondNote.id,
          expectedRevision: 0,
          operationID: UUID()
        ),
        text: "Hidden later"
      )
    )
  )
  state.workspace.notes[1].agentAccess = false

  let response = try await firstService.execute(
    profileID: firstProfile.id,
    credential: Data(),
    command: .listActivity
  )
  guard case .activity(let entries) = response else {
    Issue.record("Expected activity")
    return
  }
  #expect(entries.count == 1)
  #expect(entries[0].noteID == firstNote.id)
  #expect(
    entries[0].actor
      == .integration(
        profileID: firstProfile.id,
        displayName: firstProfile.displayName
      ))
}

@Test @MainActor func readNotePaginatesCRLFAndCROnOriginalLineBoundaries()
  async throws
{
  let note = Note(
    title: "Mixed",
    body: "One\r\nTwo\rThree",
    agentAccess: true
  )
  let profile = AgentIntegrationProfile(
    id: UUID(),
    displayName: "Codex",
    createdAt: Date(),
    lastConnectedAt: nil,
    revokedAt: nil
  )
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    UUID().uuidString,
    isDirectory: true
  )
  defer { try? FileManager.default.removeItem(at: root) }
  let service = AgentCommandService(
    state: FakeAgentWorkspaceState(
      workspace: Workspace(notes: [note], selectedNoteID: note.id)
    ),
    profileStore: FixedAgentAuthorizer(profile: profile),
    activityStore: AgentActivityStore(rootURL: root)
  )

  let firstPage = try await service.execute(
    profileID: profile.id,
    credential: Data(),
    command: .readNote(
      request: .init(noteID: note.id, startLine: 1, maxLines: 2)
    )
  )
  let secondPage = try await service.execute(
    profileID: profile.id,
    credential: Data(),
    command: .readNote(
      request: .init(noteID: note.id, startLine: 2, maxLines: 2)
    )
  )

  guard case .note(let first) = firstPage,
    case .note(let second) = secondPage
  else {
    Issue.record("Expected note pages")
    return
  }
  #expect(first.body == "One\r\nTwo")
  #expect(first.totalLineCount == 3)
  #expect(first.nextLine == 3)
  #expect(second.body == "Two\rThree")
  #expect(second.startLine == 2)
  #expect(second.endLine == 3)
  #expect(second.nextLine == nil)
}

@Test @MainActor func taskHandlesHashExactCRLFAndCRChecklistLinesBeforeWrite()
  async throws
{
  let note = Note(
    title: "Tasks",
    body: "○ A\r\n○ B\r○ C",
    agentAccess: true
  )
  let profile = AgentIntegrationProfile(
    id: UUID(),
    displayName: "Codex",
    createdAt: Date(),
    lastConnectedAt: nil,
    revokedAt: nil
  )
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    UUID().uuidString,
    isDirectory: true
  )
  defer { try? FileManager.default.removeItem(at: root) }
  let codec = AgentTaskHandleCodec(
    signingKeyProvider: FixedAgentSigningKeyProvider()
  )
  let service = AgentCommandService(
    state: FakeAgentWorkspaceState(
      workspace: Workspace(notes: [note], selectedNoteID: note.id)
    ),
    profileStore: FixedAgentAuthorizer(profile: profile),
    activityStore: AgentActivityStore(rootURL: root),
    taskHandleCodec: codec
  )
  let response = try await service.execute(
    profileID: profile.id,
    credential: Data(),
    command: .listTasks(request: .init(noteID: note.id))
  )
  guard case .tasks(let tasks) = response else {
    Issue.record("Expected tasks")
    return
  }
  #expect(tasks.map(\.text) == ["A", "B", "C"])
  let secondHandle = tasks[1].taskHandle
  #expect(
    try codec.decode(
      secondHandle,
      noteID: note.id,
      revision: note.revision,
      checklistLine: "○ B"
    ).line == 2
  )

  await #expect(throws: AgentWorkspaceError(code: .motesUnavailable)) {
    try await service.execute(
      profileID: profile.id,
      credential: Data(),
      command: .renameTask(
        request: .init(
          context: .init(
            noteID: note.id,
            expectedRevision: note.revision,
            operationID: UUID()
          ),
          taskHandle: secondHandle,
          text: "Renamed"
        )
      )
    )
  }
}

@MainActor
private final class AgentServiceFixture {
  let note: Note
  let profile: AgentIntegrationProfile
  let state: FakeAgentWorkspaceState
  let activityStore: AgentActivityStore
  let service: AgentCommandService
  private let root: URL

  init(
    shared: Bool = true,
    note providedNote: Note? = nil,
    authorizer: (any AgentProfileAuthorizing)? = nil,
    signingKeyProvider: any AgentSigningKeyProviding =
      FixedAgentSigningKeyProvider()
  ) {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "AgentCommandServiceTests-\(UUID().uuidString)",
      isDirectory: true
    )
    note =
      providedNote
      ?? Note(
        title: "Work",
        body: "Original",
        agentAccess: shared,
        revision: 3
      )
    profile = AgentIntegrationProfile(
      id: UUID(),
      displayName: "Codex",
      createdAt: Date(timeIntervalSince1970: 100),
      lastConnectedAt: nil,
      revokedAt: nil
    )
    state = FakeAgentWorkspaceState(
      workspace: Workspace(notes: [note], selectedNoteID: note.id)
    )
    activityStore = AgentActivityStore(
      rootURL: root,
      now: { Date(timeIntervalSince1970: 500) }
    )
    service = AgentCommandService(
      state: state,
      profileStore: authorizer ?? FixedAgentAuthorizer(profile: profile),
      activityStore: activityStore,
      taskHandleCodec: AgentTaskHandleCodec(
        signingKeyProvider: signingKeyProvider
      ),
      now: { Date(timeIntervalSince1970: 500) }
    )
  }

  deinit {
    try? FileManager.default.removeItem(at: root)
  }

  func execute(_ command: AgentWorkspaceCommand) async throws -> AgentWorkspaceResponse {
    try await service.execute(
      profileID: profile.id,
      credential: Data("credential".utf8),
      command: command
    )
  }
}

@MainActor
private final class FakeAgentWorkspaceState: AgentWorkspaceStateAccess {
  var workspace: Workspace
  var persistenceGeneration: UInt64 = 1
  var preferences = AppPreferences()
  var isAgentWorkspaceAvailable = true
  var agentCommitProofs: [AgentWorkspaceCommitProof] = []
  var latestFeedback: AgentChangeFeedback?
  var commitCount = 0
  var commitError: AgentWorkspaceError?
  var flushError: Error?

  init(workspace: Workspace) {
    self.workspace = workspace
  }

  func flushPendingPersistenceForAgent() async throws {
    if let flushError { throw flushError }
  }

  func commitAgentWorkspace(
    _ workspace: Workspace,
    expectedGeneration: UInt64,
    commitProof: AgentWorkspaceCommitProof
  ) throws {
    guard persistenceGeneration == expectedGeneration else {
      throw AgentWorkspaceError(code: .revisionConflict)
    }
    if let commitError { throw commitError }
    self.workspace = workspace
    persistenceGeneration += 1
    agentCommitProofs.append(commitProof)
    commitCount += 1
  }

  func publishAgentFeedback(_ feedback: AgentChangeFeedback) {
    latestFeedback = feedback
  }

  func humanEdit(body: String) {
    workspace.updateContent(
      id: workspace.notes[0].id,
      body: body,
      rtf: nil
    )
    persistenceGeneration += 1
  }
}

private actor FixedAgentAuthorizer: AgentProfileAuthorizing {
  let profile: AgentIntegrationProfile

  init(profile: AgentIntegrationProfile) {
    self.profile = profile
  }

  func authorize(
    profileID: UUID,
    credential: Data
  ) async throws -> AgentIntegrationProfile {
    profile
  }
}

private actor AgentAuthorizationGate: AgentProfileAuthorizing {
  private var continuation: CheckedContinuation<AgentIntegrationProfile, Never>?
  private var started = false

  func authorize(
    profileID: UUID,
    credential: Data
  ) async throws -> AgentIntegrationProfile {
    started = true
    return await withCheckedContinuation { continuation = $0 }
  }

  func waitUntilAuthorizationStarted() async {
    while !started {
      await Task.yield()
    }
  }

  func resume(with profile: AgentIntegrationProfile) {
    continuation?.resume(returning: profile)
    continuation = nil
  }
}

private actor OrderedAgentAuthorizer: AgentProfileAuthorizing {
  private(set) var callCount = 0
  private var continuations: [CheckedContinuation<AgentIntegrationProfile, Never>] = []

  func authorize(
    profileID: UUID,
    credential: Data
  ) async throws -> AgentIntegrationProfile {
    callCount += 1
    return await withCheckedContinuation { continuations.append($0) }
  }

  func waitForCallCount(_ count: Int) async {
    while callCount < count {
      await Task.yield()
    }
  }

  func resumeNext(with profile: AgentIntegrationProfile) {
    continuations.removeFirst().resume(returning: profile)
  }
}

private actor AgentDrainSaveGate {
  private var saveCount = 0
  private var firstSaveStarted = false
  private var firstSaveStartedContinuation: CheckedContinuation<Void, Never>?
  private var firstSaveContinuation: CheckedContinuation<Void, Never>?

  func save(
    workspace: Workspace,
    preferences: AppPreferences,
    trashedNotes: [Note],
    generation: UInt64
  ) async throws -> LocalStoreSnapshotWriteResult {
    saveCount += 1
    guard saveCount == 1 else { return .committed }
    firstSaveStarted = true
    firstSaveStartedContinuation?.resume()
    firstSaveStartedContinuation = nil
    await withCheckedContinuation { firstSaveContinuation = $0 }
    return .committed
  }

  func waitUntilFirstSaveStarted() async {
    guard !firstSaveStarted else { return }
    await withCheckedContinuation { firstSaveStartedContinuation = $0 }
  }

  func releaseFirstSave() {
    firstSaveContinuation?.resume()
    firstSaveContinuation = nil
  }

  func currentSaveCount() -> Int {
    saveCount
  }
}

private struct FixedAgentSigningKeyProvider: AgentSigningKeyProviding {
  func signingKey() throws -> Data {
    Data(repeating: 7, count: 32)
  }
}

private struct ThrowingAgentSigningKeyProvider: AgentSigningKeyProviding {
  func signingKey() throws -> Data {
    throw UnexpectedAgentServiceTestError()
  }
}

private struct UnexpectedAgentServiceTestError: Error {}

private final class FailOnceCommitActivityStore:
  AgentActivityPersisting, @unchecked Sendable
{
  private let base: AgentActivityStore
  private let lock = NSLock()
  private var shouldFail = true

  init(base: AgentActivityStore) {
    self.base = base
  }

  func prepare(_ transaction: PreparedAgentTransaction) throws {
    try base.prepare(transaction)
  }

  func commit(changeID: UUID, receipt: AgentWriteReceipt) throws {
    let fails = lock.withLock {
      defer { shouldFail = false }
      return shouldFail
    }
    if fails { throw AgentWorkspaceError(code: .invalidOperation) }
    try base.commit(changeID: changeID, receipt: receipt)
  }

  func abort(changeID: UUID) throws {
    try base.abort(changeID: changeID)
  }

  func priorReceipt(
    actor: AgentActivityActor,
    operationID: UUID
  ) -> AgentWriteReceipt? {
    base.priorReceipt(actor: actor, operationID: operationID)
  }

  func list(
    profileID: UUID?,
    visibleNoteIDs: Set<UUID>
  ) -> [AgentActivityRecord] {
    base.list(profileID: profileID, visibleNoteIDs: visibleNoteIDs)
  }

  func record(id: UUID) -> AgentActivityRecord? {
    base.record(id: id)
  }

  func reconcile(
    workspace: Workspace,
    commitProofs: [AgentWorkspaceCommitProof]
  ) throws {
    try base.reconcile(workspace: workspace, commitProofs: commitProofs)
  }
}
