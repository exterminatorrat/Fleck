import CryptoKit
import FleckCore
import Foundation
import FleckMCPFixtureSupport
import Testing

@testable import FleckApp
@testable import FleckCore

@Suite(.serialized)
struct AgentEventOutboxTests {
  @Test func registrationAnchorsAtHeadAndCapturePreservesOneExactBody() async throws {
    let fixture = try await AgentEventOutboxFixture.make()
    defer { fixture.remove() }

    try await fixture.service.registerPending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      now: fixture.date
    )
    let initial = try fixture.outboxStore.load()
    let initialProgress = try #require(initial.progress.first)
    #expect(initialProgress.anchor?.sequence == 1)
    #expect(initialProgress.capturedThrough == initialProgress.anchor)
    #expect(initial.entries.isEmpty)

    var changed = fixture.note
    changed.title = "PRIVATE_TITLE_CANARY_UPDATED"
    changed.body = "PRIVATE_BODY_CANARY_UPDATED"
    changed.revision = 1
    changed.modifiedAt = fixture.date.addingTimeInterval(1)
    try fixture.save(Workspace(notes: [changed], selectedNoteID: changed.id), generation: 1)
    try await fixture.service.capturePending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      now: fixture.date
    )

    let captured = try fixture.outboxStore.load()
    let entry = try #require(captured.entries.first)
    let body = try #require(entry.body)
    let envelope = try JSONDecoder().decode(AgentEventEnvelope.self, from: body)
    #expect(entry.status == .awaitingVerification)
    #expect(entry.eventID == envelope.eventID)
    #expect(envelope.name == .noteUpdated)
    #expect(envelope.cursor == nil)
    #expect(body.count < 1_024)
    #expect(try #require(captured.progress.first?.capturedThrough).sequence == 2)

    let reopenedStore = AgentEventOutboxStore(fileURL: fixture.outboxURL)
    let beforeRefresh = try reopenedStore.load()
    try await fixture.service(using: reopenedStore).capturePending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      now: fixture.date
    )
    let afterRefresh = try reopenedStore.load()
    #expect(afterRefresh.entries.count == 1)
    #expect(afterRefresh.entries.first?.body == body)
    #expect(afterRefresh.progress == beforeRefresh.progress)

    let persisted = String(decoding: try Data(contentsOf: fixture.outboxURL), as: UTF8.self)
    #expect(!persisted.contains("https://example.com/"))
    #expect(!persisted.contains(fixture.signingKeyReference))
    #expect(!persisted.contains("PRIVATE_PROFILE_DISPLAY_CANARY"))
    #expect(!persisted.contains("PRIVATE_TITLE_CANARY"))
    #expect(!persisted.contains("PRIVATE_BODY_CANARY"))
    #expect(fixture.secretStore.accessCount == 0)
  }

  @Test func enabledCaptureCoalescesSameNoteUpdatesWithinWindowAndUnionsFields() async throws {
    let fixture = try await AgentEventOutboxFixture.make()
    defer { fixture.remove() }
    let service = fixture.service(coalescesNoteUpdateBursts: true)
    try await service.registerPending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      now: fixture.date
    )
    let anchor = try #require(try fixture.outboxStore.load().progress.first?.anchor?.sequence)

    var first = fixture.note
    first.title = "First burst update"
    first.revision = 1
    first.modifiedAt = fixture.date.addingTimeInterval(1)
    fixture.clock.set(first.modifiedAt)
    try fixture.save(fixture.workspace(with: first), generation: 1)

    var latest = first
    latest.body = "Second burst update"
    latest.revision = 2
    latest.modifiedAt = fixture.date.addingTimeInterval(2)
    fixture.clock.set(latest.modifiedAt)
    try fixture.save(fixture.workspace(with: latest), generation: 2)
    try await service.capturePending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      now: fixture.date
    )

    let state = try fixture.outboxStore.load()
    let entry = try #require(state.entries.first)
    let body = try #require(entry.body)
    let envelope = try JSONDecoder().decode(AgentEventEnvelope.self, from: body)
    let journal = try #require(try await fixture.localStore.loadSnapshot().agentEventJournal)
    let newestRecord = try #require(journal.records.last)
    #expect(state.entries.count == 1)
    #expect(entry.sourcePosition.sequence == anchor + 2)
    #expect(entry.eventID == newestRecord.eventID.uuidString.lowercased())
    #expect(envelope.eventID == entry.eventID)
    #expect(envelope.name == .noteUpdated)
    if case .noteUpdated(let noteID, let revision, let changedFields, _) = envelope.data {
      #expect(noteID == fixture.note.id)
      #expect(revision == latest.revision)
      #expect(changedFields == [.body, .title])
    } else {
      Issue.record("A coalesced update must remain a note.updated event.")
    }
    #expect(state.progress.first?.capturedThrough?.sequence == newestRecord.sequence)

    let reopenedStore = AgentEventOutboxStore(fileURL: fixture.outboxURL)
    try await fixture.service(
      using: reopenedStore,
      coalescesNoteUpdateBursts: true
    ).capturePending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      now: fixture.date
    )
    #expect(try reopenedStore.load().entries.first?.body == body)
    #expect(try reopenedStore.load().entries.first?.eventID == entry.eventID)
  }

  @Test func enabledCaptureCoalescesInterleavedNotesIndependently() async throws {
    let fixture = try await AgentEventOutboxFixture.make(folderScope: true)
    defer { fixture.remove() }
    let secondNote = Note(
      id: UUID(),
      title: "Second note",
      body: "Synthetic second body",
      createdAt: fixture.date,
      modifiedAt: fixture.date,
      agentAccess: true,
      folderID: fixture.folder.id
    )
    var workspace = Workspace(
      notes: [fixture.note, secondNote],
      selectedNoteID: fixture.note.id,
      folders: fixture.folders
    )
    try fixture.save(workspace, generation: 1)
    let service = fixture.service(coalescesNoteUpdateBursts: true)
    try await service.registerPending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      now: fixture.date
    )
    let anchor = try #require(try fixture.outboxStore.load().progress.first?.anchor?.sequence)

    var first = fixture.note
    first.title = "First interleaved note"
    first.revision = 1
    first.modifiedAt = fixture.date.addingTimeInterval(1)
    fixture.clock.set(first.modifiedAt)
    workspace.notes[0] = first
    try fixture.save(workspace, generation: 2)

    var second = secondNote
    second.body = "Interleaved second-note update"
    second.revision = 1
    second.modifiedAt = fixture.date.addingTimeInterval(1.5)
    fixture.clock.set(second.modifiedAt)
    workspace.notes[1] = second
    try fixture.save(workspace, generation: 3)

    first.body = "Later first-note update"
    first.revision = 2
    first.modifiedAt = fixture.date.addingTimeInterval(2)
    fixture.clock.set(first.modifiedAt)
    workspace.notes[0] = first
    try fixture.save(workspace, generation: 4)
    try await service.capturePending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      now: fixture.date
    )

    let entries = try fixture.outboxStore.load().entries.sorted {
      $0.sourcePosition.sequence < $1.sourcePosition.sequence
    }
    let updates = try entries.map { entry -> (UUID, UInt64, [AgentEventChangedField], String) in
      let body = try #require(entry.body)
      let envelope = try JSONDecoder().decode(AgentEventEnvelope.self, from: body)
      if case .noteUpdated(let noteID, let revision, let changedFields, _) = envelope.data {
        return (noteID, revision, changedFields, entry.eventID)
      }
      throw AgentEventOutboxError.storageFailure
    }
    let journal = try #require(try await fixture.localStore.loadSnapshot().agentEventJournal)
    let latestRecord = try #require(journal.records.last)
    let secondNoteUpdate = try #require(updates.first)
    let coalescedUpdate = try #require(updates.last)
    #expect(entries.count == 2)
    #expect(entries.map(\.sourcePosition.sequence) == [anchor + 2, anchor + 3])
    #expect(updates.map { $0.0 } == [secondNote.id, fixture.note.id])
    #expect(secondNoteUpdate.1 == second.revision)
    #expect(secondNoteUpdate.2 == [.body])
    #expect(coalescedUpdate.1 == first.revision)
    #expect(coalescedUpdate.2 == [.body, .title])
    #expect(coalescedUpdate.3 == latestRecord.eventID.uuidString.lowercased())
  }

  @Test func enabledCaptureDoesNotCoalesceAcrossChecklistTransition() async throws {
    let fixture = try await AgentEventOutboxFixture.make()
    defer { fixture.remove() }
    var baseline = fixture.note
    baseline.body = "○ Task"
    baseline.revision = 1
    baseline.modifiedAt = fixture.date.addingTimeInterval(0.5)
    fixture.clock.set(baseline.modifiedAt)
    try fixture.save(fixture.workspace(with: baseline), generation: 1)
    let service = fixture.service(coalescesNoteUpdateBursts: true)
    try await service.registerPending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      now: fixture.date
    )
    let anchor = try #require(try fixture.outboxStore.load().progress.first?.anchor?.sequence)

    var first = baseline
    first.title = "Before checklist transition"
    first.revision = 2
    first.modifiedAt = fixture.date.addingTimeInterval(1)
    fixture.clock.set(first.modifiedAt)
    try fixture.save(fixture.workspace(with: first), generation: 2)

    var completed = first
    completed.body = "● Task"
    completed.revision = 3
    completed.modifiedAt = fixture.date.addingTimeInterval(1.5)
    fixture.clock.set(completed.modifiedAt)
    try fixture.save(fixture.workspace(with: completed), generation: 3)

    var last = completed
    last.title = "After checklist transition"
    last.revision = 4
    last.modifiedAt = fixture.date.addingTimeInterval(2)
    fixture.clock.set(last.modifiedAt)
    try fixture.save(fixture.workspace(with: last), generation: 4)
    try await service.capturePending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      now: fixture.date
    )

    let state = try fixture.outboxStore.load()
    #expect(state.entries.count == 2)
    let entriesByPosition = state.entries.sorted {
      $0.sourcePosition.sequence < $1.sourcePosition.sequence
    }
    #expect(entriesByPosition.map(\.sourcePosition.sequence) == [anchor + 1, anchor + 3])
    #expect(state.progress.first?.capturedThrough?.sequence == anchor + 3)
  }

  @Test func enabledCaptureHonorsTwoSecondWindowAndThirtyTwoRecordLimit() async throws {
    let window = try await AgentEventOutboxFixture.make()
    defer { window.remove() }
    let windowService = window.service(coalescesNoteUpdateBursts: true)
    try await windowService.registerPending(
      profileID: window.profileID,
      subscriptionID: window.subscriptionID,
      now: window.date
    )
    var note = window.note
    note.title = "Window first"
    note.revision = 1
    note.modifiedAt = window.date.addingTimeInterval(1)
    window.clock.set(note.modifiedAt)
    try window.save(window.workspace(with: note), generation: 1)
    note.title = "Window second"
    note.revision = 2
    note.modifiedAt = window.date.addingTimeInterval(4)
    window.clock.set(note.modifiedAt)
    try window.save(window.workspace(with: note), generation: 2)
    let persistedWindowUpdates = try #require(
      try await window.localStore.loadSnapshot().agentEventJournal?.records.filter {
        $0.noteID == window.note.id && $0.eventName == .noteUpdated
      }
    )
    let firstPersistedWindowUpdate = try #require(persistedWindowUpdates.first)
    let lastPersistedWindowUpdate = try #require(persistedWindowUpdates.last)
    #expect(persistedWindowUpdates.count == 2)
    #expect(
      lastPersistedWindowUpdate.occurredAt.timeIntervalSince(
        firstPersistedWindowUpdate.occurredAt
      ) == 3
    )
    try await windowService.capturePending(
      profileID: window.profileID,
      subscriptionID: window.subscriptionID,
      now: window.date
    )
    #expect(try window.outboxStore.load().entries.count == 2)

    let bounded = try await AgentEventOutboxFixture.make()
    defer { bounded.remove() }
    let boundedService = bounded.service(coalescesNoteUpdateBursts: true)
    try await boundedService.registerPending(
      profileID: bounded.profileID,
      subscriptionID: bounded.subscriptionID,
      now: bounded.date
    )
    let anchor = try #require(try bounded.outboxStore.load().progress.first?.anchor?.sequence)
    var boundedNote = bounded.note
    for revision in UInt64(1)...33 {
      bounded.clock.set(bounded.date.addingTimeInterval(Double(revision) * 0.05))
      boundedNote.title = "Bounded update \(revision)"
      boundedNote.revision = revision
      boundedNote.modifiedAt = bounded.clock.now()
      try bounded.save(
        bounded.workspace(with: boundedNote),
        generation: revision
      )
    }
    try await boundedService.capturePending(
      profileID: bounded.profileID,
      subscriptionID: bounded.subscriptionID,
      now: bounded.date
    )
    let boundedEntries = try bounded.outboxStore.load().entries.sorted {
      $0.sourcePosition.sequence < $1.sourcePosition.sequence
    }
    #expect(boundedEntries.count == 2)
    #expect(
      boundedEntries.map(\.sourcePosition.sequence) == [anchor + 32, anchor + 33]
    )
  }

  @Test func enabledCaptureKeepsRetryingStagedBodyAndEventIdentity() async throws {
    let fixture = try await AgentEventOutboxFixture.make()
    defer { fixture.remove() }
    try await fixture.service.registerPending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      now: fixture.date
    )
    var stagedNote = fixture.note
    stagedNote.title = "Retrying staged update"
    stagedNote.revision = 1
    stagedNote.modifiedAt = fixture.date.addingTimeInterval(1)
    fixture.clock.set(stagedNote.modifiedAt)
    try fixture.save(fixture.workspace(with: stagedNote), generation: 1)
    try await fixture.service.capturePending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      now: fixture.date
    )
    let stagedEntry = try #require(try fixture.outboxStore.load().entries.first)
    let stagedBody = try #require(stagedEntry.body)
    let subscription = try #require(
      try await fixture.subscriptionStore.currentSubscription(id: fixture.subscriptionID)
    )
    let ledgerStore = AgentEventDeliveryLedgerStore(
      fileURL: fixture.rootURL.appendingPathComponent("delivery-ledger.json"),
      now: { fixture.clock.now() },
      jitterBasisPoints: { 0 }
    )
    let ledgerService = AgentEventDeliveryLedgerService(
      outboxStore: fixture.outboxStore,
      subscriptionStore: fixture.subscriptionStore,
      ledgerStore: ledgerStore
    )
    let reservation = try #require(
      try await ledgerService.reserveNext(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID
      )
    )
    let binding = AgentEventCallbackVerificationBinding(
      profileID: subscription.profileID,
      subscriptionID: subscription.subscriptionID,
      subscriptionRevision: subscription.revision,
      grantRevision: subscription.grantRevision,
      signingKeyReference: subscription.signingKeyReference
    )
    #expect(try await ledgerService.observe(reservation).body == stagedBody)
    _ = try await ledgerService.settle(
      reservation,
      outcome: .httpStatus(503, retryAfter: nil)
    )
    #expect(try ledgerStore.records(for: binding).first?.status == .retryWaiting)

    var latestNote = stagedNote
    latestNote.body = "Retrying staged update plus second edit"
    latestNote.revision = 2
    latestNote.modifiedAt = fixture.date.addingTimeInterval(2)
    fixture.clock.set(latestNote.modifiedAt)
    try fixture.save(fixture.workspace(with: latestNote), generation: 2)
    latestNote.title = "Retrying staged update plus third edit"
    latestNote.revision = 3
    latestNote.modifiedAt = fixture.date.addingTimeInterval(3)
    fixture.clock.set(latestNote.modifiedAt)
    try fixture.save(fixture.workspace(with: latestNote), generation: 3)

    try await fixture.service(coalescesNoteUpdateBursts: true).capturePending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      now: fixture.date
    )
    let entries = try fixture.outboxStore.load().entries
    let stillStaged = try #require(entries.first(where: { $0.eventID == stagedEntry.eventID }))
    #expect(entries.count == 2)
    #expect(stillStaged.body == stagedBody)
    #expect(stillStaged.sourcePosition == stagedEntry.sourcePosition)
    #expect(try ledgerStore.records(for: reservation.binding).first?.status == .retryWaiting)
  }

  @Test func temporaryExclusionChangesAtSnapshotAwaitPreventRegistrationAndCapture() async throws {
    let registration = try await AgentEventOutboxFixture.make()
    defer { registration.remove() }
    let registrationGate = AgentEventOutboxSnapshotReadGate(localStore: registration.localStore)
    let registrationService = registration.service(snapshotReader: {
      try await registrationGate.load()
    })
    let registrationProfileID = registration.profileID
    let registrationSubscriptionID = registration.subscriptionID
    let registrationDate = registration.date
    let registrationTask = Task {
      try await registrationService.registerPending(
        profileID: registrationProfileID,
        subscriptionID: registrationSubscriptionID,
        now: registrationDate
      )
    }

    await registrationGate.waitUntilPaused()
    registration.authority.exclude(noteID: registration.note.id)
    registration.authority.include(noteID: registration.note.id)
    await registrationGate.release()

    await #expect(throws: AgentEventOutboxError.sourceChanged) {
      try await registrationTask.value
    }
    #expect(try registration.outboxStore.load().progress.isEmpty)

    let capture = try await AgentEventOutboxFixture.make()
    defer { capture.remove() }
    try await capture.stageOneEvent()
    let beforeCapture = try capture.outboxStore.load()
    let beforeBytes = try Data(contentsOf: capture.outboxURL)
    let captureGate = AgentEventOutboxSnapshotReadGate(localStore: capture.localStore)
    let captureService = capture.service(snapshotReader: {
      try await captureGate.load()
    })
    let captureProfileID = capture.profileID
    let captureSubscriptionID = capture.subscriptionID
    let captureDate = capture.date
    let captureTask = Task {
      try await captureService.capturePending(
        profileID: captureProfileID,
        subscriptionID: captureSubscriptionID,
        now: captureDate
      )
    }

    await captureGate.waitUntilPaused()
    capture.authority.exclude(noteID: capture.note.id)
    await captureGate.release()

    await #expect(throws: AgentEventOutboxError.sourceChanged) {
      try await captureTask.value
    }
    #expect(try capture.outboxStore.load() == beforeCapture)
    #expect(try Data(contentsOf: capture.outboxURL) == beforeBytes)
  }

  @Test func delayedRegistrationCannotRegressRefreshedSubscriptionProgress() async throws {
    let fixture = try await AgentEventOutboxFixture.make()
    defer { fixture.remove() }
    try await fixture.stageOneEvent()
    let before = try fixture.outboxStore.load()
    let previousProgress = try #require(before.progress.first)
    let previousSubscription = try #require(
      await fixture.subscriptionStore.currentSubscription(id: fixture.subscriptionID)
    )
    let previousControl = try #require(previousSubscription.deliveryControl)
    let previousBinding = eventOutboxVerificationBinding(for: previousSubscription)
    let ownerControl = try #require(
      try await fixture.subscriptionStore.setOwnerDeliveryEligibility(
        binding: previousBinding,
        expectedGenerationID: previousControl.generationID,
        eligible: true
      )
    )
    let gate = AgentEventOutboxSnapshotReadGate(
      localStore: fixture.localStore,
      pauseOnRead: 2
    )
    let staleRegistrationService = fixture.service(snapshotReader: {
      try await gate.load()
    })
    let profileID = fixture.profileID
    let subscriptionID = fixture.subscriptionID
    let date = fixture.date
    let staleRegistration = Task {
      try await staleRegistrationService.registerPending(
        profileID: profileID,
        subscriptionID: subscriptionID,
        now: date,
        ownerDeliveryControl: ownerControl
      )
    }
    defer { Task { await gate.release() } }
    await gate.waitUntilPaused()

    let refreshedKeyReference = UUID().uuidString.lowercased()
    try await fixture.subscriptionStore.reserveSigningKeyReference(refreshedKeyReference)
    _ = try await fixture.subscriptionStore.createOrRefresh(
      AgentEventPendingSubscription(
        subscriptionID: previousSubscription.subscriptionID,
        profileID: previousSubscription.profileID,
        event: previousSubscription.event,
        scope: previousSubscription.scope,
        callbackURL: previousSubscription.callbackURL,
        signingKeyReference: refreshedKeyReference,
        grantRevision: previousSubscription.grantRevision,
        createdAt: previousSubscription.createdAt,
        updatedAt: date.addingTimeInterval(1),
        expiresAt: previousSubscription.expiresAt,
        revision: previousSubscription.revision + 1
      ),
      now: date
    )
    let refreshedSubscription = try #require(
      await fixture.subscriptionStore.currentSubscription(id: subscriptionID)
    )
    #expect(refreshedSubscription.revision == previousSubscription.revision + 1)
    #expect(refreshedSubscription.signingKeyReference != previousSubscription.signingKeyReference)
    let refreshedControl = try #require(refreshedSubscription.deliveryControl)
    let refreshedBinding = eventOutboxVerificationBinding(for: refreshedSubscription)
    let currentOwnerControl = try #require(
      try await fixture.subscriptionStore.setOwnerDeliveryEligibility(
        binding: refreshedBinding,
        expectedGenerationID: refreshedControl.generationID,
        eligible: true
      )
    )
    #expect(currentOwnerControl.generationID != ownerControl.generationID)
    try await fixture.service.registerPending(
      profileID: profileID,
      subscriptionID: subscriptionID,
      now: date,
      ownerDeliveryControl: currentOwnerControl
    )

    let afterRefresh = try fixture.outboxStore.load()
    let refreshedProgress = try #require(afterRefresh.progress.first)
    #expect(refreshedProgress.subscriptionRevision == refreshedSubscription.revision)
    #expect(refreshedProgress.anchor == previousProgress.anchor)
    #expect(refreshedProgress.capturedThrough == previousProgress.capturedThrough)
    #expect(refreshedProgress.status == previousProgress.status)
    #expect(refreshedProgress.nonDeliveryDisposition == previousProgress.nonDeliveryDisposition)
    #expect(afterRefresh.entries == before.entries)
    let refreshedBytes = try Data(contentsOf: fixture.outboxURL)

    await gate.release()
    await #expect(throws: AgentEventOutboxError.sourceChanged) {
      try await staleRegistration.value
    }
    #expect(try fixture.outboxStore.load() == afterRefresh)
    #expect(try Data(contentsOf: fixture.outboxURL) == refreshedBytes)
  }

  @Test func ownerOffOnDuringPendingRegistrationRejectsOriginalControl() async throws {
    let fixture = try await AgentEventOutboxFixture.make()
    defer { fixture.remove() }
    try await fixture.stageOneEvent()
    let before = try fixture.outboxStore.load()
    let beforeBytes = try Data(contentsOf: fixture.outboxURL)
    let subscription = try #require(
      await fixture.subscriptionStore.currentSubscription(id: fixture.subscriptionID)
    )
    let initialControl = try #require(subscription.deliveryControl)
    let binding = eventOutboxVerificationBinding(for: subscription)
    let originalControl = try #require(
      try await fixture.subscriptionStore.setOwnerDeliveryEligibility(
        binding: binding,
        expectedGenerationID: initialControl.generationID,
        eligible: true
      )
    )
    let gate = AgentEventOutboxSnapshotReadGate(
      localStore: fixture.localStore,
      pauseOnRead: 2
    )
    let service = fixture.service(snapshotReader: {
      try await gate.load()
    })
    let profileID = fixture.profileID
    let subscriptionID = fixture.subscriptionID
    let date = fixture.date
    let registration = Task {
      try await service.registerPending(
        profileID: profileID,
        subscriptionID: subscriptionID,
        now: date,
        ownerDeliveryControl: originalControl
      )
    }
    defer { Task { await gate.release() } }
    await gate.waitUntilPaused()

    let disabledControl = try #require(
      try await fixture.subscriptionStore.setOwnerDeliveryEligibility(
        binding: binding,
        expectedGenerationID: originalControl.generationID,
        eligible: false
      )
    )
    let replacementControl = try #require(
      try await fixture.subscriptionStore.setOwnerDeliveryEligibility(
        binding: binding,
        expectedGenerationID: disabledControl.generationID,
        eligible: true
      )
    )
    #expect(replacementControl.enabled)
    #expect(replacementControl.binding == originalControl.binding)
    #expect(replacementControl.generationID != originalControl.generationID)

    await gate.release()
    await #expect(throws: AgentEventOutboxError.sourceChanged) {
      try await registration.value
    }
    #expect(try fixture.outboxStore.load() == before)
    #expect(try Data(contentsOf: fixture.outboxURL) == beforeBytes)
  }

  @Test func integrationAndUncertainJournalRecordsAdvanceWithoutStaging() async throws {
    let fixture = try await AgentEventOutboxFixture.make()
    defer { fixture.remove() }
    try await fixture.service.registerPending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      now: fixture.date
    )

    var integrationEdit = fixture.note
    integrationEdit.body = "PRIVATE_INTEGRATION_CANARY"
    integrationEdit.revision = 1
    integrationEdit.modifiedAt = fixture.date.addingTimeInterval(1)
    let integration = AgentActivityActor.integration(
      profileID: fixture.profileID,
      displayName: "PRIVATE_ACTOR_CANARY"
    )
    let integrationProof = AgentWorkspaceCommitProof(
      changeID: UUID(),
      noteID: fixture.note.id,
      resultingRevision: integrationEdit.revision,
      bodySHA256: eventOutboxSHA256(Data(integrationEdit.body.utf8)),
      actor: .localUser,
      originatingActor: integration,
      operationID: UUID(),
      expiresAt: fixture.date.addingTimeInterval(60)
    )
    try fixture.save(
      Workspace(notes: [integrationEdit], selectedNoteID: fixture.note.id),
      generation: 1,
      proof: integrationProof
    )
    try await fixture.service.capturePending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      now: fixture.date
    )

    var uncertainEdit = integrationEdit
    uncertainEdit.body = "PRIVATE_UNCERTAIN_CANARY"
    uncertainEdit.revision = 2
    uncertainEdit.modifiedAt = fixture.date.addingTimeInterval(2)
    let uncertainProof = AgentWorkspaceCommitProof(
      changeID: UUID(),
      noteID: fixture.note.id,
      resultingRevision: uncertainEdit.revision,
      bodySHA256: String(repeating: "0", count: 64),
      actor: .localUser,
      operationID: UUID(),
      expiresAt: fixture.date.addingTimeInterval(60)
    )
    try fixture.save(
      Workspace(notes: [uncertainEdit], selectedNoteID: fixture.note.id),
      generation: 2,
      proof: uncertainProof
    )
    try await fixture.service.capturePending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      now: fixture.date
    )

    let state = try fixture.outboxStore.load()
    #expect(state.entries.isEmpty)
    #expect(try #require(state.progress.first?.capturedThrough).sequence == 3)
    let persisted = String(decoding: try Data(contentsOf: fixture.outboxURL), as: UTF8.self)
    #expect(!persisted.contains("PRIVATE_INTEGRATION_CANARY"))
    #expect(!persisted.contains("PRIVATE_UNCERTAIN_CANARY"))
    #expect(!persisted.contains("PRIVATE_ACTOR_CANARY"))
  }

  @Test func movingAStagedFolderNotePurgesItWithNonDeliveryDisposition() async throws {
    let fixture = try await AgentEventOutboxFixture.make(folderScope: true)
    defer { fixture.remove() }
    try await fixture.service.registerPending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      now: fixture.date
    )

    var changed = fixture.note
    changed.body = "PRIVATE_FOLDER_EVENT_CANARY"
    changed.revision = 1
    changed.modifiedAt = fixture.date.addingTimeInterval(1)
    try fixture.save(fixture.workspace(with: changed), generation: 1)
    try await fixture.service.capturePending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      now: fixture.date
    )
    #expect(try fixture.outboxStore.load().entries.contains { $0.status == .awaitingVerification })

    changed.folderID = nil
    changed.body = "PRIVATE_MOVED_OUT_CANARY"
    changed.revision = 2
    changed.modifiedAt = fixture.date.addingTimeInterval(2)
    try fixture.save(fixture.workspace(with: changed), generation: 2)
    try await fixture.service.capturePending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      now: fixture.date
    )

    let state = try fixture.outboxStore.load()
    #expect(!state.entries.contains { $0.status == .awaitingVerification })
    #expect(
      state.entries.contains {
        $0.status == .notDelivered
          && $0.nonDeliveryDisposition == .scopeMembershipChanged
          && $0.body == nil
      })
    #expect(try #require(state.progress.first?.capturedThrough).sequence == 3)
  }

  @Test func revocationRemovalAndExpiryPurgePendingBodiesExplicitly() async throws {
    let revoked = try await AgentEventOutboxFixture.make()
    defer { revoked.remove() }
    try await revoked.stageOneEvent()
    try await revoked.replaceAuthorization(allowed: [], grants: [], observation: false)
    try await revoked.service.capturePending(
      profileID: revoked.profileID,
      subscriptionID: revoked.subscriptionID,
      now: revoked.date
    )
    let revokedState = try revoked.outboxStore.load()
    #expect(revokedState.progress.first?.status == .discarded)
    #expect(revokedState.progress.first?.nonDeliveryDisposition == .permissionChanged)
    #expect(!revokedState.entries.contains { $0.status == .awaitingVerification })
    #expect(revokedState.entries.first?.body == nil)

    let removed = try await AgentEventOutboxFixture.make()
    defer { removed.remove() }
    try await removed.stageOneEvent()
    _ = try await removed.subscriptionStore.remove(
      subscriptionID: removed.subscriptionID,
      profileID: removed.profileID
    )
    try await removed.service.capturePending(
      profileID: removed.profileID,
      subscriptionID: removed.subscriptionID,
      now: removed.date
    )
    let removedState = try removed.outboxStore.load()
    #expect(removedState.progress.first?.nonDeliveryDisposition == .subscriptionRemoved)
    #expect(!removedState.entries.contains { $0.status == .awaitingVerification })
    #expect(removedState.entries.first?.body == nil)

    let expired = try await AgentEventOutboxFixture.make(expiresIn: 600)
    defer { expired.remove() }
    try await expired.stageOneEvent()
    let expiry = try #require(
      try await expired.subscriptionStore.currentSubscription(
        id: expired.subscriptionID
      )?.expiresAt)
    try await expired.service.capturePending(
      profileID: expired.profileID,
      subscriptionID: expired.subscriptionID,
      now: expiry
    )
    let expiredState = try expired.outboxStore.load()
    #expect(expiredState.progress.first?.nonDeliveryDisposition == .expired)
    #expect(!expiredState.entries.contains { $0.status == .awaitingVerification })
    #expect(expiredState.entries.first?.body == nil)
  }

  @Test func pausedQueuesRevalidateTargetAndOwnerAuthorizationWithoutResumingCapture() async throws
  {
    let pausedStatuses: [AgentEventOutboxProgressStatus] = [
      .pausedCapacity, .pausedHistory, .pausedUnavailable,
    ]
    for pausedStatus in pausedStatuses {
      for invalidation in AgentEventOutboxTargetInvalidation.allCases {
        let fixture = try await AgentEventOutboxFixture.make()
        defer { fixture.remove() }
        try await fixture.preparePausedQueue(pausedStatus)
        let before = try #require(try fixture.outboxStore.load().progress.first)
        try await fixture.appendAuthorizedEvent()

        let disposition: AgentEventOutboxNonDeliveryDisposition
        var now = fixture.date
        switch invalidation {
        case .profileRevoked:
          try await fixture.profileStore.revoke(profileID: fixture.profileID)
          disposition = .profileRevoked
        case .subscriptionRemoved:
          _ = try await fixture.subscriptionStore.remove(
            subscriptionID: fixture.subscriptionID,
            profileID: fixture.profileID
          )
          disposition = .subscriptionRemoved
        case .expired:
          now = try #require(
            try await fixture.subscriptionStore.currentSubscription(
              id: fixture.subscriptionID
            )?.expiresAt
          )
          disposition = .expired
        case .observationRevoked:
          let current = try #require(
            try await fixture.capabilityStore.currentState().profiles[fixture.profileID]
          )
          try await fixture.replaceAuthorization(
            allowed: current.allowedCapabilities,
            grants: current.grants,
            observation: false
          )
          disposition = .permissionChanged
        case .grantRevoked:
          try await fixture.replaceAuthorization(
            allowed: [.readNotes],
            grants: [],
            observation: true
          )
          disposition = .permissionChanged
        }

        try await fixture.service.capturePending(
          profileID: fixture.profileID,
          subscriptionID: fixture.subscriptionID,
          now: now
        )

        let state = try fixture.outboxStore.load()
        let progress = try #require(state.progress.first)
        let entry = try #require(state.entries.first)
        #expect(progress.status == .discarded)
        #expect(progress.anchor == before.anchor)
        #expect(progress.capturedThrough == before.capturedThrough)
        #expect(progress.nonDeliveryDisposition == disposition)
        #expect(state.entries.count == 1)
        #expect(entry.status == .notDelivered)
        #expect(entry.body == nil)
        #expect(entry.nonDeliveryDisposition == disposition)
      }
    }
  }

  @Test func pausedQueuesPurgeMovedOrExcludedBodiesWithoutChangingPauseOrScanPosition()
    async throws
  {
    let pausedStatuses: [AgentEventOutboxProgressStatus] = [
      .pausedCapacity, .pausedHistory, .pausedUnavailable,
    ]
    for pausedStatus in pausedStatuses {
      for mutation in AgentEventOutboxNoteMutation.allCases {
        let fixture = try await AgentEventOutboxFixture.make(folderScope: true)
        defer { fixture.remove() }
        try await fixture.preparePausedQueue(pausedStatus)
        let before = try #require(try fixture.outboxStore.load().progress.first)
        try await fixture.appendAuthorizedEvent()
        let disposition: AgentEventOutboxNonDeliveryDisposition
        switch mutation {
        case .moveOutOfFolder:
          let snapshot = try await fixture.localStore.loadSnapshot()
          var note = try #require(snapshot.workspace.notes.first)
          note.folderID = nil
          note.revision += 1
          note.modifiedAt = fixture.clock.now().addingTimeInterval(1)
          try fixture.save(
            fixture.workspace(with: note),
            generation: snapshot.generation + 1
          )
          disposition = .scopeMembershipChanged
        case .excludeFromAgentAccess:
          fixture.authority.exclude(noteID: fixture.note.id)
          disposition = .noteNoLongerAuthorized
        }

        try await fixture.service.capturePending(
          profileID: fixture.profileID,
          subscriptionID: fixture.subscriptionID,
          now: fixture.date
        )

        let state = try fixture.outboxStore.load()
        let progress = try #require(state.progress.first)
        let entry = try #require(state.entries.first)
        #expect(progress.status == pausedStatus)
        #expect(progress.anchor == before.anchor)
        #expect(progress.capturedThrough == before.capturedThrough)
        #expect(state.entries.count == 1)
        #expect(entry.status == .notDelivered)
        #expect(entry.body == nil)
        #expect(entry.nonDeliveryDisposition == disposition)
      }
    }
  }

  @Test func discardedQueuesStayTerminalAfterPermissionsAndPendingTargetReturn() async throws {
    let fixture = try await AgentEventOutboxFixture.make()
    defer { fixture.remove() }
    try await fixture.stageOneEvent()
    let before = try #require(try fixture.outboxStore.load().progress.first)
    try await fixture.replaceAuthorization(allowed: [], grants: [], observation: false)
    try await fixture.service.capturePending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      now: fixture.date
    )
    let discardedState = try fixture.outboxStore.load()
    #expect(discardedState.progress.first?.status == .discarded)
    #expect(discardedState.progress.first?.capturedThrough == before.capturedThrough)
    #expect(discardedState.entries.first?.status == .notDelivered)
    #expect(discardedState.entries.first?.body == nil)

    try await fixture.replaceAuthorization(
      allowed: [.readNotes],
      grants: [
        AgentResourceGrant(scope: .note(noteID: fixture.note.id), authority: .read)
      ],
      observation: true
    )
    let capabilities = try #require(
      try await fixture.capabilityStore.currentState().profiles[fixture.profileID]
    )
    let current = try #require(
      try await fixture.subscriptionStore.currentSubscription(id: fixture.subscriptionID)
    )
    let signingKeyReference = UUID().uuidString.lowercased()
    try await fixture.subscriptionStore.reserveSigningKeyReference(signingKeyReference)
    _ = try await fixture.subscriptionStore.createOrRefresh(
      AgentEventPendingSubscription(
        subscriptionID: current.subscriptionID,
        profileID: current.profileID,
        event: current.event,
        scope: current.scope,
        callbackURL: current.callbackURL,
        signingKeyReference: signingKeyReference,
        grantRevision: capabilities.grantRevision,
        createdAt: current.createdAt,
        updatedAt: fixture.date.addingTimeInterval(1),
        expiresAt: current.expiresAt,
        revision: current.revision + 1
      ),
      now: fixture.date
    )
    try await fixture.service.registerPending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      now: fixture.date
    )
    try await fixture.service.capturePending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      now: fixture.date
    )

    let finalState = try fixture.outboxStore.load()
    #expect(finalState == discardedState)
  }

  @Test func ownerApprovalResumesDiscardedQueueAtCurrentHead() async throws {
    let fixture = try await AgentEventOutboxFixture.make()
    defer { fixture.remove() }
    try await fixture.stageOneEvent()
    try await fixture.replaceAuthorization(allowed: [], grants: [], observation: false)
    try await fixture.service.capturePending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      now: fixture.date
    )
    let discardedState = try fixture.outboxStore.load()
    #expect(discardedState.progress.first?.status == .discarded)
    #expect(discardedState.entries.first?.body == nil)

    try await fixture.replaceAuthorization(
      allowed: [.readNotes],
      grants: [
        AgentResourceGrant(scope: .note(noteID: fixture.note.id), authority: .read)
      ],
      observation: true
    )
    let capabilities = try #require(
      try await fixture.capabilityStore.currentState().profiles[fixture.profileID]
    )
    let current = try #require(
      try await fixture.subscriptionStore.currentSubscription(id: fixture.subscriptionID)
    )
    let signingKeyReference = UUID().uuidString.lowercased()
    try await fixture.subscriptionStore.reserveSigningKeyReference(signingKeyReference)
    _ = try await fixture.subscriptionStore.createOrRefresh(
      AgentEventPendingSubscription(
        subscriptionID: current.subscriptionID,
        profileID: current.profileID,
        event: current.event,
        scope: current.scope,
        callbackURL: current.callbackURL,
        signingKeyReference: signingKeyReference,
        grantRevision: capabilities.grantRevision,
        createdAt: current.createdAt,
        updatedAt: fixture.date.addingTimeInterval(1),
        expiresAt: current.expiresAt,
        revision: current.revision + 1
      ),
      now: fixture.date
    )
    let refreshed = try #require(
      try await fixture.subscriptionStore.currentSubscription(id: fixture.subscriptionID)
    )
    let staleControl = try #require(refreshed.deliveryControl)
    #expect(!staleControl.enabled)
    let binding = AgentEventCallbackVerificationBinding(
      profileID: refreshed.profileID,
      subscriptionID: refreshed.subscriptionID,
      subscriptionRevision: refreshed.revision,
      grantRevision: refreshed.grantRevision,
      signingKeyReference: refreshed.signingKeyReference
    )
    let ownerControl = try #require(
      try await fixture.subscriptionStore.setOwnerDeliveryEligibility(
        binding: binding,
        expectedGenerationID: staleControl.generationID,
        eligible: true
      )
    )

    var staleControlRejected = false
    do {
      try await fixture.service.registerPending(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID,
        now: fixture.date,
        ownerDeliveryControl: staleControl
      )
    } catch AgentEventOutboxError.sourceChanged {
      staleControlRejected = true
    }
    #expect(staleControlRejected)
    #expect(try fixture.outboxStore.load() == discardedState)

    try await fixture.service.registerPending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      now: fixture.date,
      ownerDeliveryControl: ownerControl
    )
    let resumedState = try fixture.outboxStore.load()
    let resumedProgress = try #require(resumedState.progress.first)
    #expect(resumedProgress.status == .pending)
    #expect(resumedProgress.subscriptionRevision == refreshed.revision)
    #expect(resumedProgress.grantRevision == capabilities.grantRevision)
    #expect(resumedProgress.anchor?.sequence == 2)
    #expect(resumedProgress.capturedThrough == resumedProgress.anchor)
    #expect(resumedProgress.nonDeliveryDisposition == nil)
    #expect(resumedState.entries.isEmpty)

    try await fixture.appendAuthorizedEvent()
    try await fixture.service.capturePending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      now: fixture.date
    )
    let capturedState = try fixture.outboxStore.load()
    let capturedEntry = try #require(capturedState.entries.first)
    #expect(capturedState.entries.count == 1)
    #expect(capturedEntry.sourcePosition.sequence == 3)
    #expect(capturedEntry.eventID != discardedState.entries.first?.eventID)
    #expect(capturedEntry.body != nil)
  }

  @Test func pausedReadFailuresLeaveOutboxBytesAndScanPositionUntouched() async throws {
    for failure in AgentEventOutboxReadFailure.allCases {
      let fixture = try await AgentEventOutboxFixture.make()
      defer { fixture.remove() }
      try await fixture.preparePausedQueue(.pausedCapacity)
      let before = try fixture.outboxStore.load()
      let beforeBytes = try Data(contentsOf: fixture.outboxURL)
      switch failure {
      case .snapshot:
        try fixture.corruptSnapshotStore()
      case .profile:
        try fixture.corruptProfileStore()
      case .capabilities:
        try fixture.corruptCapabilityStore()
      }

      var failedAsExpected = false
      do {
        try await fixture.service.capturePending(
          profileID: fixture.profileID,
          subscriptionID: fixture.subscriptionID,
          now: fixture.date
        )
      } catch {
        if failure == .snapshot {
          failedAsExpected = (error as? LocalStore.StoreError) == .invalidSnapshot
        } else {
          failedAsExpected = (error as? AgentWorkspaceError)?.code == .internalSaveFailure
        }
      }

      #expect(failedAsExpected)
      #expect(try fixture.outboxStore.load() == before)
      #expect(try Data(contentsOf: fixture.outboxURL) == beforeBytes)
    }
  }

  @Test func recoveryMissingJournalAndRetentionGapPauseWithoutAdvancing() async throws {
    let recovery = try await AgentEventOutboxFixture.make()
    defer { recovery.remove() }
    var changed = recovery.note
    changed.body = "Recovery generation"
    changed.revision = 1
    try recovery.save(recovery.workspace(with: changed), generation: 1)
    try Data("corrupt root body".utf8).write(
      to: recovery.workspaceURL.appendingPathComponent(
        "\(recovery.note.id.uuidString.lowercased()).md"
      ),
      options: .atomic
    )
    try await recovery.service.registerPending(
      profileID: recovery.profileID,
      subscriptionID: recovery.subscriptionID,
      now: recovery.date
    )
    let recoveryProgress = try #require(try recovery.outboxStore.load().progress.first)
    #expect(recoveryProgress.status == .pausedHistory)
    #expect(recoveryProgress.anchor == nil)
    #expect(try await recovery.localStore.loadSnapshot().source == .recovery)

    let missing = try await AgentEventOutboxFixture.make()
    defer { missing.remove() }
    try missing.removeJournalFromRoot()
    try await missing.service.registerPending(
      profileID: missing.profileID,
      subscriptionID: missing.subscriptionID,
      now: missing.date
    )
    let missingProgress = try #require(try missing.outboxStore.load().progress.first)
    #expect(missingProgress.status == .pausedUnavailable)
    #expect(missingProgress.anchor == nil)

    let gap = try await AgentEventOutboxFixture.make()
    defer { gap.remove() }
    try await gap.service.registerPending(
      profileID: gap.profileID,
      subscriptionID: gap.subscriptionID,
      now: gap.date
    )
    var firstChange = gap.note
    firstChange.body = "Before retention"
    firstChange.revision = 1
    firstChange.modifiedAt = gap.date.addingTimeInterval(1)
    try gap.save(gap.workspace(with: firstChange), generation: 1)
    gap.clock.set(gap.date.addingTimeInterval(8 * 24 * 60 * 60))
    var retainedChange = firstChange
    retainedChange.body = "After retention"
    retainedChange.revision = 2
    retainedChange.modifiedAt = gap.clock.now()
    try gap.save(gap.workspace(with: retainedChange), generation: 2)
    try await gap.service.capturePending(
      profileID: gap.profileID,
      subscriptionID: gap.subscriptionID,
      now: gap.date
    )
    let gapProgress = try #require(try gap.outboxStore.load().progress.first)
    #expect(gapProgress.status == .pausedHistory)
    #expect(gapProgress.capturedThrough?.sequence == gapProgress.anchor?.sequence)
    #expect(try #require(await gap.localStore.loadSnapshot().agentEventJournal).historyFloor == 3)
    #expect(try gap.outboxStore.load().entries.isEmpty)
  }

  @Test func capacityPausesAtTheFirstUnqueuedEligibleRecord() async throws {
    let fixture = try await AgentEventOutboxFixture.make(event: .noteCreated)
    defer { fixture.remove() }
    try await fixture.service.registerPending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      now: fixture.date
    )
    try installEventJournal(recordCount: 258, noteID: fixture.note.id, at: fixture.workspaceURL)

    try await fixture.service.capturePending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      now: fixture.date
    )
    let state = try fixture.outboxStore.load()
    let progress = try #require(state.progress.first)
    #expect(state.entries.count == 256)
    #expect(state.entries.allSatisfy { $0.status == .awaitingVerification })
    #expect(progress.status == .pausedCapacity)
    #expect(progress.capturedThrough?.sequence == 257)
    #expect(!state.entries.contains { $0.sourcePosition.sequence == 258 })
  }

  @Test func enabledCaptureKeepsInterleavedBurstContiguousAcrossCapacityPause() async throws {
    let fixture = try await AgentEventOutboxFixture.make(folderScope: true)
    defer { fixture.remove() }
    let secondNote = Note(
      id: UUID(),
      title: "Second note",
      body: "Synthetic second body",
      createdAt: fixture.date,
      modifiedAt: fixture.date,
      agentAccess: true,
      folderID: fixture.folder.id
    )
    let privateNote = Note(
      id: UUID(),
      title: "Restricted note",
      body: "Synthetic restricted body",
      createdAt: fixture.date,
      modifiedAt: fixture.date,
      agentAccess: true,
      folderID: nil
    )
    var workspace = Workspace(
      notes: [fixture.note, secondNote, privateNote],
      selectedNoteID: fixture.note.id,
      folders: fixture.folders
    )
    try fixture.save(workspace, generation: 1)
    let service = fixture.service(coalescesNoteUpdateBursts: true)
    try await service.registerPending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      now: fixture.date
    )
    let progress = try #require(
      try fixture.outboxStore.load().progress.first(where: {
        $0.subscriptionID == fixture.subscriptionID
      })
    )
    let anchor = try #require(progress.anchor)
    let checkpoint = anchor.sequence + 256
    let privatePosition = anchor.sequence + 50
    var sourceNoteIDs = Array(repeating: fixture.note.id, count: Int(checkpoint))
    sourceNoteIDs[Int(privatePosition - 1)] = privateNote.id
    try installNoteUpdatedJournal(
      recordCount: Int(checkpoint),
      noteIDs: sourceNoteIDs,
      at: fixture.workspaceURL
    )
    try fixture.outboxStore.update { state in
      guard
        let index = state.progress.firstIndex(where: {
          $0.subscriptionID == fixture.subscriptionID
        })
      else {
        throw AgentEventOutboxError.registrationRequired
      }
      state.progress[index].capturedThrough = AgentEventOutboxPosition(
        epoch: anchor.epoch,
        sequence: checkpoint
      )
      for sequence in (anchor.sequence + 1)...checkpoint {
        let noteID = sourceNoteIDs[Int(sequence - 1)]
        let eventID = UUID().uuidString.lowercased()
        state.entries.append(
          AgentEventOutboxEntry(
            profileID: fixture.profileID,
            subscriptionID: fixture.subscriptionID,
            eventID: eventID,
            sourcePosition: AgentEventOutboxPosition(epoch: anchor.epoch, sequence: sequence),
            body: try outboxTestBody(eventID: eventID, noteID: noteID, revision: sequence),
            status: .awaitingVerification,
            nonDeliveryDisposition: nil
          )
        )
      }
    }
    let ledgerStore = AgentEventDeliveryLedgerStore(
      fileURL: fixture.rootURL.appendingPathComponent("delivery-ledger.json"),
      now: { fixture.clock.now() },
      jitterBasisPoints: { 0 }
    )
    let ledgerService = AgentEventDeliveryLedgerService(
      outboxStore: fixture.outboxStore,
      subscriptionStore: fixture.subscriptionStore,
      ledgerStore: ledgerStore
    )
    var stagedBodiesBeforeCapture: [String: Data] = [:]
    for entry in try fixture.outboxStore.load().entries where entry.status == .awaitingVerification
    {
      guard let body = entry.body else { throw AgentEventOutboxError.storageFailure }
      stagedBodiesBeforeCapture[entry.eventID] = body
    }
    let inFlightReservation = try #require(
      try await ledgerService.reserveNext(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID
      )
    )

    var first = fixture.note
    first.title = "First interleaved note"
    first.revision = 1
    first.modifiedAt = fixture.date.addingTimeInterval(1)
    fixture.clock.set(first.modifiedAt)
    workspace.notes[0] = first
    try fixture.save(workspace, generation: 2)
    var second = secondNote
    second.body = "Interleaved second-note update"
    second.revision = 1
    second.modifiedAt = fixture.date.addingTimeInterval(2)
    fixture.clock.set(second.modifiedAt)
    workspace.notes[1] = second
    try fixture.save(workspace, generation: 3)
    first.body = "Later first-note update"
    first.revision = 2
    first.modifiedAt = fixture.date.addingTimeInterval(3)
    fixture.clock.set(first.modifiedAt)
    workspace.notes[0] = first
    try fixture.save(workspace, generation: 4)

    try await service.capturePending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      now: fixture.clock.now()
    )
    let pausedState = try fixture.outboxStore.load()
    let pausedProgress = try #require(
      pausedState.progress.first(where: { $0.subscriptionID == fixture.subscriptionID })
    )
    #expect(pausedProgress.status == .pausedCapacity)
    #expect(pausedProgress.capturedThrough?.sequence == checkpoint)
    #expect(
      pausedState.entries.filter { $0.status == .awaitingVerification }.count == 255
    )
    let purgedEntry = try #require(
      pausedState.entries.first(where: { $0.sourcePosition.sequence == privatePosition })
    )
    #expect(purgedEntry.status == .notDelivered)
    #expect(purgedEntry.body == nil)
    #expect(purgedEntry.nonDeliveryDisposition == .scopeMembershipChanged)
    for entry in pausedState.entries where entry.eventID != purgedEntry.eventID {
      #expect(entry.body == stagedBodiesBeforeCapture[entry.eventID])
    }

    let reopenedStore = AgentEventOutboxStore(fileURL: fixture.outboxURL)
    let reopenedState = try reopenedStore.load()
    #expect(reopenedState == pausedState)
    let reopenedService = fixture.service(
      using: reopenedStore,
      coalescesNoteUpdateBursts: true
    )
    let reopenedLedgerService = AgentEventDeliveryLedgerService(
      outboxStore: reopenedStore,
      subscriptionStore: fixture.subscriptionStore,
      ledgerStore: ledgerStore
    )
    let receipt = try await reopenedLedgerService.settle(
      inFlightReservation,
      outcome: .httpStatus(204, retryAfter: nil)
    )
    #expect(receipt.status == .receipt)
    try await reopenedService.releaseCompletedRecords([receipt])

    try await reopenedService.capturePending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      now: fixture.clock.now()
    )
    let finalState = try reopenedStore.load()
    let finalProgress = try #require(
      finalState.progress.first(where: { $0.subscriptionID == fixture.subscriptionID })
    )
    let finalJournal = try #require(
      try await fixture.localStore.loadSnapshot().agentEventJournal
    )
    let sourceRecords = finalJournal.records.filter { $0.sequence > checkpoint }
    let finalEntries = finalState.entries.sorted {
      $0.sourcePosition.sequence < $1.sourcePosition.sequence
    }
    let capturedEntries = finalEntries.filter { $0.sourcePosition.sequence > checkpoint }
    let capturedBodies = try capturedEntries.map { entry -> (UUID, [AgentEventChangedField]) in
      let body = try #require(entry.body)
      let envelope = try JSONDecoder().decode(AgentEventEnvelope.self, from: body)
      guard case .noteUpdated(let noteID, _, let changedFields, _) = envelope.data else {
        throw AgentEventOutboxError.storageFailure
      }
      return (noteID, changedFields)
    }
    let firstUpdate = try #require(capturedBodies.first(where: { $0.0 == fixture.note.id }))
    let secondUpdate = try #require(capturedBodies.first(where: { $0.0 == secondNote.id }))
    #expect(finalProgress.status == .pending)
    #expect(finalProgress.capturedThrough?.sequence == finalJournal.lastSequence)
    #expect(capturedEntries.count == 2)
    #expect(firstUpdate.1 == [.body, .title])
    #expect(secondUpdate.1 == [.body])
    #expect(
      capturedEntries.map(\.eventID)
        == sourceRecords.suffix(2).map {
          $0.eventID.uuidString.lowercased()
        })
    #expect(Set(finalState.entries.map(\.eventID)).count == finalState.entries.count)
    #expect(
      finalState.entries.first(where: { $0.sourcePosition.sequence == privatePosition })
        == purgedEntry
    )
  }

  @Test func enabledCaptureKeepsAggregateCapacityAdmissionTransactional() async throws {
    let fixture = try await AgentEventOutboxFixture.make(folderScope: true)
    defer { fixture.remove() }
    let secondNote = Note(
      id: UUID(),
      title: "Second note",
      body: "Synthetic second body",
      createdAt: fixture.date,
      modifiedAt: fixture.date,
      agentAccess: true,
      folderID: fixture.folder.id
    )
    let workspace = Workspace(
      notes: [fixture.note, secondNote],
      selectedNoteID: fixture.note.id,
      folders: fixture.folders
    )
    try fixture.save(workspace, generation: 1)
    let service = fixture.service(coalescesNoteUpdateBursts: true)
    try await service.registerPending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      now: fixture.date
    )
    let firstSubscription = try #require(
      await fixture.subscriptionStore.currentSubscription(id: fixture.subscriptionID)
    )
    let secondCallbackURL = "https://example.com/events/aggregate-capacity"
    let secondSubscriptionID = AgentEventSubscriptionIdentity.subscriptionID(
      profileID: fixture.profileID,
      event: .noteUpdated,
      scope: firstSubscription.scope,
      callbackURL: secondCallbackURL
    )
    let secondKeyReference = UUID().uuidString.lowercased()
    try await fixture.subscriptionStore.reserveSigningKeyReference(secondKeyReference)
    _ = try await fixture.subscriptionStore.createOrRefresh(
      AgentEventPendingSubscription(
        subscriptionID: secondSubscriptionID,
        profileID: fixture.profileID,
        event: .noteUpdated,
        scope: firstSubscription.scope,
        callbackURL: secondCallbackURL,
        signingKeyReference: secondKeyReference,
        grantRevision: firstSubscription.grantRevision,
        createdAt: fixture.date,
        updatedAt: fixture.date,
        expiresAt: fixture.date.addingTimeInterval(604_800),
        revision: 1
      ),
      now: fixture.date
    )
    try await service.registerPending(
      profileID: fixture.profileID,
      subscriptionID: secondSubscriptionID,
      now: fixture.date
    )
    let thirdCallbackURL = "https://example.com/events/profile-capacity-target"
    let thirdSubscriptionID = AgentEventSubscriptionIdentity.subscriptionID(
      profileID: fixture.profileID,
      event: .noteUpdated,
      scope: firstSubscription.scope,
      callbackURL: thirdCallbackURL
    )
    let thirdKeyReference = UUID().uuidString.lowercased()
    try await fixture.subscriptionStore.reserveSigningKeyReference(thirdKeyReference)
    _ = try await fixture.subscriptionStore.createOrRefresh(
      AgentEventPendingSubscription(
        subscriptionID: thirdSubscriptionID,
        profileID: fixture.profileID,
        event: .noteUpdated,
        scope: firstSubscription.scope,
        callbackURL: thirdCallbackURL,
        signingKeyReference: thirdKeyReference,
        grantRevision: firstSubscription.grantRevision,
        createdAt: fixture.date,
        updatedAt: fixture.date,
        expiresAt: fixture.date.addingTimeInterval(604_800),
        revision: 1
      ),
      now: fixture.date
    )
    try await service.registerPending(
      profileID: fixture.profileID,
      subscriptionID: thirdSubscriptionID,
      now: fixture.date
    )
    let stateBeforeSeed = try fixture.outboxStore.load()
    let firstProgress = try #require(
      stateBeforeSeed.progress.first(where: { $0.subscriptionID == fixture.subscriptionID })
    )
    let secondProgress = try #require(
      stateBeforeSeed.progress.first(where: { $0.subscriptionID == secondSubscriptionID })
    )
    let thirdProgress = try #require(
      stateBeforeSeed.progress.first(where: { $0.subscriptionID == thirdSubscriptionID })
    )
    let anchor = try #require(firstProgress.anchor)
    #expect(secondProgress.anchor == anchor)
    #expect(thirdProgress.anchor == anchor)
    let checkpoint = anchor.sequence + 256
    try installNoteUpdatedJournal(
      recordCount: Int(checkpoint),
      noteIDs: Array(repeating: fixture.note.id, count: Int(checkpoint)),
      at: fixture.workspaceURL
    )
    try fixture.outboxStore.update { state in
      guard
        let firstIndex = state.progress.firstIndex(where: {
          $0.subscriptionID == fixture.subscriptionID
        }),
        let secondIndex = state.progress.firstIndex(where: {
          $0.subscriptionID == secondSubscriptionID
        }),
        let thirdIndex = state.progress.firstIndex(where: {
          $0.subscriptionID == thirdSubscriptionID
        })
      else {
        throw AgentEventOutboxError.registrationRequired
      }
      let capturedThrough = AgentEventOutboxPosition(epoch: anchor.epoch, sequence: checkpoint)
      state.progress[firstIndex].capturedThrough = capturedThrough
      state.progress[secondIndex].capturedThrough = capturedThrough
      state.progress[thirdIndex].capturedThrough = capturedThrough
      for offset in 1...256 {
        let position = AgentEventOutboxPosition(
          epoch: anchor.epoch,
          sequence: anchor.sequence + UInt64(offset)
        )
        let eventID = UUID().uuidString.lowercased()
        state.entries.append(
          AgentEventOutboxEntry(
            profileID: fixture.profileID,
            subscriptionID: fixture.subscriptionID,
            eventID: eventID,
            sourcePosition: position,
            body: try outboxTestBody(
              eventID: eventID,
              noteID: fixture.note.id,
              revision: UInt64(offset)
            ),
            status: .awaitingVerification,
            nonDeliveryDisposition: nil
          )
        )
      }
      for offset in 1...255 {
        let position = AgentEventOutboxPosition(
          epoch: anchor.epoch,
          sequence: anchor.sequence + UInt64(offset)
        )
        let eventID = UUID().uuidString.lowercased()
        state.entries.append(
          AgentEventOutboxEntry(
            profileID: fixture.profileID,
            subscriptionID: secondSubscriptionID,
            eventID: eventID,
            sourcePosition: position,
            body: try outboxTestBody(
              eventID: eventID,
              noteID: fixture.note.id,
              revision: UInt64(offset)
            ),
            status: .awaitingVerification,
            nonDeliveryDisposition: nil
          )
        )
      }
    }
    let current = try fixture.outboxStore.load()
    #expect(
      current.entries.filter { $0.status == .awaitingVerification }.count == 511
    )

    var changedWorkspace = workspace
    var first = fixture.note
    first.title = "Aggregate first note title"
    first.revision = 1
    first.modifiedAt = fixture.date.addingTimeInterval(1)
    fixture.clock.set(first.modifiedAt)
    changedWorkspace.notes[0] = first
    try fixture.save(changedWorkspace, generation: 2)
    var second = secondNote
    second.body = "Aggregate second note body"
    second.revision = 1
    second.modifiedAt = fixture.date.addingTimeInterval(2)
    fixture.clock.set(second.modifiedAt)
    changedWorkspace.notes[1] = second
    try fixture.save(changedWorkspace, generation: 3)
    first.body = "Aggregate final first note body"
    first.revision = 2
    first.modifiedAt = fixture.date.addingTimeInterval(3)
    fixture.clock.set(first.modifiedAt)
    changedWorkspace.notes[0] = first
    try fixture.save(changedWorkspace, generation: 4)
    let journal = try #require(
      try await fixture.localStore.loadSnapshot().agentEventJournal
    )
    let newEventIDs = Set(
      journal.records.filter { $0.sequence > checkpoint }.map {
        $0.eventID.uuidString.lowercased()
      })

    try await service.capturePending(
      profileID: fixture.profileID,
      subscriptionID: thirdSubscriptionID,
      now: fixture.clock.now()
    )
    let after = try fixture.outboxStore.load()
    let progress = try #require(
      after.progress.first(where: { $0.subscriptionID == thirdSubscriptionID })
    )
    #expect(progress.status == .pausedCapacity)
    #expect(progress.capturedThrough?.sequence == checkpoint)
    #expect(after.entries.count == current.entries.count)
    #expect(after.entries.filter { $0.status == .awaitingVerification }.count == 511)
    #expect(after.entries == current.entries)
    #expect(Set(after.entries.map(\.eventID)).isDisjoint(with: newEventIDs))
  }

  @Test func corruptOversizedAndUnknownOutboxStatesFailWithoutReset() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("AgentEventOutboxStoreTests-\(UUID())", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let fileURL = root.appendingPathComponent("outbox.json")
    let store = AgentEventOutboxStore(fileURL: fileURL)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    for invalid in [
      Data(#"{"schemaVersion":1,"progress":[],"entries":[],"unknown":true}"#.utf8),
      Data(repeating: 0x20, count: 8 * 1_048_576 + 1),
    ] {
      try invalid.write(to: fileURL, options: .atomic)
      #expect(throws: AgentEventOutboxError.storageFailure) { _ = try store.load() }
      #expect(try Data(contentsOf: fileURL) == invalid)
    }
  }

  @Test func atomicWriteFailuresReopenToTheActualPersistedState() async throws {
    let fixture = try await AgentEventOutboxFixture.make()
    defer { fixture.remove() }
    try await fixture.service.registerPending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      now: fixture.date
    )
    let original = try Data(contentsOf: fixture.outboxURL)
    let beforeCommitStore = AgentEventOutboxStore(
      fileURL: fixture.outboxURL,
      fileWriter: { _, _ in throw AgentEventOutboxTestFailure.injectedWriteFailure }
    )
    #expect(throws: AgentEventOutboxError.storageFailure) {
      try beforeCommitStore.update { state in
        state.progress[0].status = .pausedHistory
      }
    }
    #expect(try Data(contentsOf: fixture.outboxURL) == original)

    let afterCommitStore = AgentEventOutboxStore(
      fileURL: fixture.outboxURL,
      fileWriter: { data, url in
        try data.write(to: url, options: .atomic)
        throw AgentEventOutboxTestFailure.injectedWriteFailure
      }
    )
    try afterCommitStore.update { state in
      state.progress[0].status = .pausedHistory
    }
    let reopened = try AgentEventOutboxStore(fileURL: fixture.outboxURL).load()
    #expect(reopened.progress.first?.status == .pausedHistory)
  }

  @Test func subscriptionProgressCapacityFailsClosedAt128() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("AgentEventOutboxStoreTests-\(UUID())", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = AgentEventOutboxStore(fileURL: root.appendingPathComponent("outbox.json"))
    let epoch = UUID()
    try store.update { state in
      state.progress = (0..<128).map { index in
        let profileID = UUID()
        let subscriptionID = AgentEventSubscriptionIdentity.subscriptionID(
          profileID: profileID,
          event: .noteCreated,
          scope: .note(noteID: UUID()),
          callbackURL: "https://example.com/outbox-\(index)"
        )
        let position = AgentEventOutboxPosition(epoch: epoch, sequence: 0)
        return AgentEventOutboxProgress(
          profileID: profileID,
          subscriptionID: subscriptionID,
          subscriptionRevision: 1,
          grantRevision: 1,
          anchor: position,
          capturedThrough: position,
          status: .pending,
          nonDeliveryDisposition: nil
        )
      }
    }
    let original = try Data(contentsOf: store.fileURL)
    #expect(throws: AgentEventOutboxError.capacityExceeded) {
      try store.update { state in
        let profileID = UUID()
        let subscriptionID = AgentEventSubscriptionIdentity.subscriptionID(
          profileID: profileID,
          event: .noteCreated,
          scope: .note(noteID: UUID()),
          callbackURL: "https://example.com/overflow"
        )
        let position = AgentEventOutboxPosition(epoch: epoch, sequence: 0)
        state.progress.append(
          AgentEventOutboxProgress(
            profileID: profileID,
            subscriptionID: subscriptionID,
            subscriptionRevision: 1,
            grantRevision: 1,
            anchor: position,
            capturedThrough: position,
            status: .pending,
            nonDeliveryDisposition: nil
          )
        )
      }
    }
    #expect(try Data(contentsOf: store.fileURL) == original)
  }
}

private struct AgentEventOutboxFixture {
  let ownedRoot: OwnedMCPFixtureRoot
  let rootURL: URL
  let workspaceURL: URL
  let outboxURL: URL
  let profileID: UUID
  let note: Note
  let folder: Folder
  let folders: [Folder]
  let event: AgentEventName
  let subscriptionID: String
  let signingKeyReference: String
  let date: Date
  let clock: AgentEventOutboxTestClock
  let localStore: LocalStore
  let profileStore: AgentProfileStore
  let capabilityStore: AgentCapabilityStore
  let subscriptionStore: AgentEventSubscriptionStore
  let outboxStore: AgentEventOutboxStore
  let authority: AgentCapabilityAuthority
  let secretStore: AgentEventOutboxTestSecretStore
  let service: AgentEventOutboxService

  static func make(
    folderScope: Bool = false,
    event: AgentEventName = .noteUpdated,
    expiresIn: TimeInterval = 604_800
  ) async throws -> AgentEventOutboxFixture {
    let ownedRoot = try OwnedMCPFixtureRoot.create(kind: .eventOutbox)
    let rootURL = ownedRoot.url
    var rootOwnershipTransferred = false
    defer {
      if !rootOwnershipTransferred {
        do {
          try ownedRoot.cleanup()
        } catch {
          Issue.record("Owned MCP fixture cleanup failed: \(error)")
        }
      }
    }
    let workspaceURL = rootURL.appendingPathComponent("workspace", isDirectory: true)
    let integrationsURL = rootURL.appendingPathComponent("AgentIntegrations", isDirectory: true)
    let eventURL = integrationsURL.appendingPathComponent("AgentEvents", isDirectory: true)
    let outboxURL = eventURL.appendingPathComponent("event-outbox.json")
    let profilesURL = integrationsURL.appendingPathComponent("profiles.json")
    let capabilitiesURL = integrationsURL.appendingPathComponent("capabilities.json")
    let previousCapabilitiesURL = integrationsURL.appendingPathComponent(
      "capabilities.previous.json"
    )
    try FileManager.default.createDirectory(at: integrationsURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: eventURL, withIntermediateDirectories: true)

    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let clock = AgentEventOutboxTestClock(date: date)
    let profileID = UUID()
    let noteID = UUID()
    let folder = try Folder(id: UUID(), name: "Synthetic Outbox Folder")
    let folders = folderScope ? [folder] : []
    let note = Note(
      id: noteID,
      title: "PRIVATE_TITLE_CANARY",
      body: "PRIVATE_BODY_CANARY",
      createdAt: date,
      modifiedAt: date,
      agentAccess: true,
      folderID: folderScope ? folder.id : nil
    )
    let workspace = Workspace(notes: [note], selectedNoteID: note.id, folders: folders)
    let localStore = LocalStore(rootURL: workspaceURL, now: { clock.now() })
    _ = try localStore.snapshotWriter.save(
      workspace: workspace,
      preferences: .init(),
      generation: 0
    )

    let secretStore = AgentEventOutboxTestSecretStore()
    let profileStore = AgentProfileStore(
      profilesURL: profilesURL,
      secretStore: secretStore,
      randomBytes: AgentEventOutboxTestRandomBytes(),
      now: { clock.now() }
    )
    let profile = AgentIntegrationProfile(
      id: profileID,
      displayName: "PRIVATE_PROFILE_DISPLAY_CANARY",
      createdAt: date,
      lastConnectedAt: nil,
      revokedAt: nil
    )
    try JSONEncoder().encode([profile]).write(to: profilesURL, options: .atomic)

    let capabilityStore = AgentCapabilityStore(
      capabilitiesURL: capabilitiesURL,
      previousCapabilitiesURL: previousCapabilitiesURL
    )
    let initial = try await capabilityStore.loadOrMigrate(
      activeProfileIDs: [profileID],
      workspace: workspace
    )
    let initialRevision = try #require(initial.profiles[profileID]?.grantRevision)
    let grantScope: AgentGrantScope =
      folderScope
      ? .folderIncludingFutureNotes(folderID: folder.id)
      : .note(noteID: note.id)
    let capabilities = AgentProfileCapabilities(
      profileID: profileID,
      grantRevision: initialRevision + 1,
      allowedCapabilities: [.readNotes],
      grants: [AgentResourceGrant(scope: grantScope, authority: .read)],
      allowsEventObservation: true
    )
    _ = try await capabilityStore.replaceProfile(
      capabilities,
      expectedGrantRevision: initialRevision
    )
    let authority = AgentCapabilityAuthority(store: capabilityStore)
    let scope: AgentEventScope =
      folderScope
      ? .folder(folderID: folder.id)
      : .note(noteID: note.id)
    let callbackURL = "https://example.com/events/\(UUID().uuidString.lowercased())"
    let subscriptionID = AgentEventSubscriptionIdentity.subscriptionID(
      profileID: profileID,
      event: event,
      scope: scope,
      callbackURL: callbackURL
    )
    let signingKeyReference = UUID().uuidString.lowercased()
    let subscriptionStore = AgentEventSubscriptionStore(
      fileURL: eventURL.appendingPathComponent("event-subscriptions.json")
    )
    try await subscriptionStore.reserveSigningKeyReference(signingKeyReference)
    _ = try await subscriptionStore.createOrRefresh(
      AgentEventPendingSubscription(
        subscriptionID: subscriptionID,
        profileID: profileID,
        event: event,
        scope: scope,
        callbackURL: callbackURL,
        signingKeyReference: signingKeyReference,
        grantRevision: capabilities.grantRevision,
        createdAt: date,
        updatedAt: date,
        expiresAt: date.addingTimeInterval(expiresIn),
        revision: 1
      ),
      now: date
    )
    let outboxStore = AgentEventOutboxStore(fileURL: outboxURL)
    let service = AgentEventOutboxService(
      store: outboxStore,
      localStore: localStore,
      profileStore: profileStore,
      subscriptionStore: subscriptionStore,
      authority: authority
    )
    let fixture = AgentEventOutboxFixture(
      ownedRoot: ownedRoot,
      rootURL: rootURL,
      workspaceURL: workspaceURL,
      outboxURL: outboxURL,
      profileID: profileID,
      note: note,
      folder: folder,
      folders: folders,
      event: event,
      subscriptionID: subscriptionID,
      signingKeyReference: signingKeyReference,
      date: date,
      clock: clock,
      localStore: localStore,
      profileStore: profileStore,
      capabilityStore: capabilityStore,
      subscriptionStore: subscriptionStore,
      outboxStore: outboxStore,
      authority: authority,
      secretStore: secretStore,
      service: service
    )
    rootOwnershipTransferred = true
    return fixture
  }

  func service(
    using store: AgentEventOutboxStore,
    coalescesNoteUpdateBursts: Bool = false
  ) -> AgentEventOutboxService {
    AgentEventOutboxService(
      store: store,
      localStore: localStore,
      profileStore: profileStore,
      subscriptionStore: subscriptionStore,
      authority: authority,
      coalescesNoteUpdateBursts: coalescesNoteUpdateBursts
    )
  }

  func service(coalescesNoteUpdateBursts: Bool) -> AgentEventOutboxService {
    AgentEventOutboxService(
      store: outboxStore,
      localStore: localStore,
      profileStore: profileStore,
      subscriptionStore: subscriptionStore,
      authority: authority,
      coalescesNoteUpdateBursts: coalescesNoteUpdateBursts
    )
  }

  func service(
    snapshotReader: @escaping @Sendable () async throws -> LocalStoreSnapshot
  ) -> AgentEventOutboxService {
    AgentEventOutboxService(
      store: outboxStore,
      localStore: localStore,
      profileStore: profileStore,
      subscriptionStore: subscriptionStore,
      authority: authority,
      snapshotReader: snapshotReader
    )
  }

  func workspace(with note: Note) -> Workspace {
    Workspace(notes: [note], selectedNoteID: note.id, folders: folders)
  }

  func save(
    _ workspace: Workspace,
    generation: UInt64,
    proof: AgentWorkspaceCommitProof? = nil
  ) throws {
    _ = try localStore.snapshotWriter.save(
      workspace: workspace,
      preferences: .init(),
      generation: generation,
      commitProof: proof
    )
  }

  func stageOneEvent() async throws {
    try await service.registerPending(
      profileID: profileID,
      subscriptionID: subscriptionID,
      now: date
    )
    var changed = note
    changed.body = "PRIVATE_BODY_CANARY_UPDATED"
    changed.revision = 1
    changed.modifiedAt = date.addingTimeInterval(1)
    try save(workspace(with: changed), generation: 1)
    try await service.capturePending(
      profileID: profileID,
      subscriptionID: subscriptionID,
      now: date
    )
  }

  func preparePausedQueue(_ status: AgentEventOutboxProgressStatus) async throws {
    try await stageOneEvent()
    switch status {
    case .pausedUnavailable:
      try removeJournalFromRoot()
      try await service.capturePending(
        profileID: profileID,
        subscriptionID: subscriptionID,
        now: date
      )
    case .pausedHistory:
      clock.set(date.addingTimeInterval(8 * 24 * 60 * 60))
      try await appendAuthorizedEvent()
      clock.set(date.addingTimeInterval(16 * 24 * 60 * 60))
      try await appendAuthorizedEvent()
      try await service.capturePending(
        profileID: profileID,
        subscriptionID: subscriptionID,
        now: date
      )
    case .pausedCapacity:
      try outboxStore.update { state in
        guard
          let index = state.progress.firstIndex(where: {
            $0.profileID == profileID && $0.subscriptionID == subscriptionID
          })
        else {
          throw AgentEventOutboxError.registrationRequired
        }
        state.progress[index].status = .pausedCapacity
      }
    case .pending, .discarded:
      throw AgentEventOutboxError.storageFailure
    }
    guard try outboxStore.load().progress.first?.status == status else {
      throw AgentEventOutboxError.sourceChanged
    }
  }

  func appendAuthorizedEvent() async throws {
    let snapshot = try await localStore.loadSnapshot()
    var note = try #require(snapshot.workspace.notes.first)
    note.body = "PRIVATE_NEW_BODY_CANARY"
    note.revision += 1
    note.modifiedAt = clock.now().addingTimeInterval(1)
    try save(workspace(with: note), generation: snapshot.generation + 1)
  }

  func replaceAuthorization(
    allowed: Set<AgentCapability>,
    grants: [AgentResourceGrant],
    observation: Bool
  ) async throws {
    let current = try #require(try await capabilityStore.currentState().profiles[profileID])
    _ = try await capabilityStore.replaceProfile(
      AgentProfileCapabilities(
        profileID: profileID,
        grantRevision: current.grantRevision + 1,
        allowedCapabilities: allowed,
        grants: grants,
        allowsEventObservation: observation
      ),
      expectedGrantRevision: current.grantRevision
    )
  }

  func removeJournalFromRoot() throws {
    let manifestURL = workspaceURL.appendingPathComponent("workspace.json")
    var manifest = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
    )
    manifest.removeValue(forKey: "agentEventJournal")
    manifest.removeValue(forKey: "agentEventJournalSHA256")
    try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
      .write(to: manifestURL, options: .atomic)
  }

  func corruptSnapshotStore() throws {
    let invalidManifest = Data("unreadable snapshot".utf8)
    for directory in [
      workspaceURL,
      workspaceURL.appendingPathComponent("Recovery", isDirectory: true),
    ] {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try invalidManifest.write(
        to: directory.appendingPathComponent("workspace.json"),
        options: .atomic
      )
    }
  }

  func corruptProfileStore() throws {
    let profilesURL =
      rootURL
      .appendingPathComponent("AgentIntegrations", isDirectory: true)
      .appendingPathComponent("profiles.json")
    try Data("unreadable profiles".utf8).write(to: profilesURL, options: .atomic)
  }

  func corruptCapabilityStore() throws {
    let integrationsURL = rootURL.appendingPathComponent("AgentIntegrations", isDirectory: true)
    for fileName in ["capabilities.json", "capabilities.previous.json"] {
      try Data("unreadable capabilities".utf8).write(
        to: integrationsURL.appendingPathComponent(fileName),
        options: .atomic
      )
    }
  }

  func remove() {
    do {
      try ownedRoot.cleanup()
    } catch {
      Issue.record("Owned MCP fixture cleanup failed: \(error)")
    }
  }
}

private func eventOutboxVerificationBinding(
  for subscription: AgentEventPendingSubscription
) -> AgentEventCallbackVerificationBinding {
  AgentEventCallbackVerificationBinding(
    profileID: subscription.profileID,
    subscriptionID: subscription.subscriptionID,
    subscriptionRevision: subscription.revision,
    grantRevision: subscription.grantRevision,
    signingKeyReference: subscription.signingKeyReference
  )
}

private enum AgentEventOutboxReadFailure: CaseIterable, Equatable {
  case snapshot
  case profile
  case capabilities
}

private final class AgentEventOutboxTestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Date

  init(date: Date) {
    value = date
  }

  func now() -> Date {
    lock.withLock { value }
  }

  func set(_ date: Date) {
    lock.withLock { value = date }
  }
}

private actor AgentEventOutboxSnapshotReadGate {
  private let localStore: LocalStore
  private let pauseOnRead: Int
  private var readCount = 0
  private var hasEntered = false
  private var releaseRequested = false
  private var enteredContinuation: CheckedContinuation<Void, Never>?
  private var releaseContinuation: CheckedContinuation<Void, Never>?

  init(localStore: LocalStore, pauseOnRead: Int = 1) {
    self.localStore = localStore
    self.pauseOnRead = pauseOnRead
  }

  func load() async throws -> LocalStoreSnapshot {
    readCount += 1
    if readCount == pauseOnRead {
      hasEntered = true
      enteredContinuation?.resume()
      enteredContinuation = nil
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        if releaseRequested {
          continuation.resume()
        } else {
          releaseContinuation = continuation
        }
      }
    }
    return try await localStore.loadSnapshot()
  }

  func waitUntilPaused() async {
    guard !hasEntered else { return }
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      enteredContinuation = continuation
    }
  }

  func release() {
    releaseRequested = true
    releaseContinuation?.resume()
    releaseContinuation = nil
  }
}

private struct AgentEventOutboxTestSecretStore: AgentSecretStoring {
  var accessCount: Int { 0 }

  func read(service: String, account: String) throws -> Data? { nil }
  func write(_ data: Data, service: String, account: String) throws {}
  func delete(service: String, account: String) throws {}
}

private struct AgentEventOutboxTestRandomBytes: AgentRandomBytesProviding {
  func randomBytes(count: Int) throws -> Data {
    Data(repeating: 0xA5, count: count)
  }
}

private enum AgentEventOutboxTestFailure: Error {
  case injectedWriteFailure
}

private enum AgentEventOutboxTargetInvalidation: CaseIterable {
  case profileRevoked
  case subscriptionRemoved
  case expired
  case observationRevoked
  case grantRevoked
}

private enum AgentEventOutboxNoteMutation: CaseIterable {
  case moveOutOfFolder
  case excludeFromAgentAccess
}

private func eventOutboxSHA256(_ data: Data) -> String {
  SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func outboxTestBody(
  eventID: String,
  noteID: UUID,
  revision: UInt64
) throws -> Data {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime]
  let envelope = try AgentEventEnvelope(
    eventID: eventID,
    name: .noteUpdated,
    timestamp: formatter.string(from: Date(timeIntervalSince1970: 1_800_000_000)),
    data: .noteUpdated(
      noteID: noteID,
      revision: revision,
      changedFields: [.body],
      origin: .local
    ),
    cursor: nil
  )
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
  return try encoder.encode(envelope)
}

private func installNoteUpdatedJournal(
  recordCount: Int,
  noteIDs: [UUID],
  at root: URL
) throws {
  let manifestURL = root.appendingPathComponent("workspace.json")
  var manifest = try #require(
    JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
  )
  var journal = try #require(manifest["agentEventJournal"] as? [String: Any])
  let originalRecords = try #require(journal["records"] as? [[String: Any]])
  let template = try #require(originalRecords.first)
  guard recordCount > 0, noteIDs.count == recordCount else {
    throw AgentEventOutboxError.storageFailure
  }
  let records = (0..<recordCount).map { index -> [String: Any] in
    var record = template
    record["eventID"] = UUID().uuidString.lowercased()
    record["noteID"] = noteIDs[index].uuidString.lowercased()
    record["revision"] = index + 1
    record["sequence"] = index + 1
    record["eventName"] = AgentEventName.noteUpdated.rawValue
    record["changedFields"] = [AgentEventChangedField.body.rawValue]
    record.removeValue(forKey: "completionTransition")
    record["provenance"] = AgentEventProvenance.local.rawValue
    return record
  }
  journal["historyIncomplete"] = false
  journal["historyFloor"] = 1
  journal["lastSequence"] = recordCount
  journal["records"] = records
  manifest["agentEventJournal"] = journal
  let journalData = try JSONSerialization.data(withJSONObject: journal, options: [.sortedKeys])
  let decoder = JSONDecoder()
  decoder.dateDecodingStrategy = .iso8601
  let decodedJournal = try decoder.decode(AgentEventJournal.self, from: journalData)
  manifest["agentEventJournalSHA256"] = eventOutboxSHA256(try decodedJournal.canonicalData())
  try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
    .write(to: manifestURL, options: .atomic)
}

private func installEventJournal(recordCount: Int, noteID: UUID, at root: URL) throws {
  let manifestURL = root.appendingPathComponent("workspace.json")
  var manifest = try #require(
    JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
  )
  var journal = try #require(manifest["agentEventJournal"] as? [String: Any])
  let originalRecords = try #require(journal["records"] as? [[String: Any]])
  let template = try #require(originalRecords.first)
  let records = (0..<recordCount).map { index -> [String: Any] in
    var record = template
    record["eventID"] = UUID().uuidString.lowercased()
    record["noteID"] = noteID.uuidString.lowercased()
    record["revision"] = index + 1
    record["sequence"] = index + 1
    record["provenance"] = AgentEventProvenance.local.rawValue
    return record
  }
  journal["historyIncomplete"] = false
  journal["historyFloor"] = 1
  journal["lastSequence"] = recordCount
  journal["records"] = records
  manifest["agentEventJournal"] = journal
  let journalData = try JSONSerialization.data(withJSONObject: journal, options: [.sortedKeys])
  let decoder = JSONDecoder()
  decoder.dateDecodingStrategy = .iso8601
  let decodedJournal = try decoder.decode(AgentEventJournal.self, from: journalData)
  manifest["agentEventJournalSHA256"] = eventOutboxSHA256(try decodedJournal.canonicalData())
  try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
    .write(to: manifestURL, options: .atomic)
}
