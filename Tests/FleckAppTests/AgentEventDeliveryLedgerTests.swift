import FleckCore
import FleckMCPFixtureSupport
import Foundation
import Testing

@testable import FleckApp
@testable import FleckCore

@Suite(.serialized)
struct AgentEventDeliveryLedgerTests {
  @Test func reservationPersistsBeforeReturningAndObservationReturnsOnlyTheOutboxBody()
    async throws
  {
    let fixture = try await LedgerFixture.make()
    defer { fixture.remove() }

    let initialOutbox = try fixture.outboxStore.load()
    let reservation = try #require(
      try await fixture.service().reserveNext(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID
      )
    )
    #expect(reservation.attemptCount == 1)
    #expect(reservation.sourcePosition == fixture.positions[0])

    let persisted = try fixture.readLedger()
    let reservedRecord = try #require(persisted.records.first)
    #expect(reservedRecord.status == .reserved)
    #expect(reservedRecord.reservationID == reservation.id.uuidString.lowercased())
    #expect(reservedRecord.leaseDeadline == reservation.leaseDeadline)
    #expect(persisted.lastObservedAt == fixture.clock.now())

    let attempt = try await fixture.service().observe(reservation)
    #expect(attempt.reservation == reservation)
    #expect(attempt.body == fixture.bodies[0])
    #expect(try fixture.outboxStore.load() == initialOutbox)
    #expect(
      try await fixture.service().settle(
        reservation,
        outcome: .httpStatus(204, retryAfter: nil)
      ).status == .receipt
    )
    #expect(try fixture.outboxStore.load() == initialOutbox)

    let bytes = try Data(contentsOf: fixture.ledgerURL)
    let serialized = String(decoding: bytes, as: UTF8.self)
    #expect(!serialized.contains(String(decoding: fixture.bodies[0], as: UTF8.self)))
    #expect(!serialized.contains(fixture.bodies[0].base64EncodedString()))
    #expect(!serialized.contains(fixture.callbackURL))
    #expect(!serialized.contains("PRIVATE_CALLBACK_URL_CANARY"))
    #expect(!serialized.contains("whsec_"))
  }

  @Test func reservationAndReceiptWritesRecognizeOnlyActualAfterWriteCommits() async throws {
    let beforeFixture = try await LedgerFixture.make()
    defer { beforeFixture.remove() }
    let beforeWriter = LedgerTestFileWriter(failBeforeWriteNumbers: [1])
    let beforeService = beforeFixture.service(writer: beforeWriter)
    let beforeError: AgentEventDeliveryLedgerError? = await ledgerError {
      _ = try await beforeService.reserveNext(
        profileID: beforeFixture.profileID,
        subscriptionID: beforeFixture.subscriptionID
      )
    }
    #expect(beforeError == .storageFailure)
    #expect(!FileManager.default.fileExists(atPath: beforeFixture.ledgerURL.path))

    let afterFixture = try await LedgerFixture.make(entryCount: 2)
    defer { afterFixture.remove() }
    let afterWriter = LedgerTestFileWriter(failAfterWriteNumbers: [1])
    let afterService = afterFixture.service(writer: afterWriter)
    let beforeReceiptOutbox = try afterFixture.outboxStore.load()
    let reservation = try #require(
      try await afterService.reserveNext(
        profileID: afterFixture.profileID,
        subscriptionID: afterFixture.subscriptionID
      )
    )
    #expect(reservation.attemptCount == 1)

    afterWriter.setFailures(before: [], after: [2])
    let receipt = try await afterService.settle(
      reservation,
      outcome: .httpStatus(204, retryAfter: nil)
    )
    #expect(receipt.status == .receipt)
    #expect(receipt.httpStatus == 204)
    #expect(try afterFixture.readLedger().records.first?.status == .receipt)
    #expect(try afterFixture.outboxStore.load() == beforeReceiptOutbox)

    let nextReservation = try #require(
      try await afterService.reserveNext(
        profileID: afterFixture.profileID,
        subscriptionID: afterFixture.subscriptionID
      )
    )
    #expect(nextReservation.eventID == afterFixture.eventIDs[1])
    #expect(nextReservation.attemptCount == 1)
  }

  @Test func receiptWriteFailureAfterReportedSuccessCanRetryTheSameEventAndBody()
    async throws
  {
    let fixture = try await LedgerFixture.make()
    defer { fixture.remove() }
    let writer = LedgerTestFileWriter()
    let service = fixture.service(writer: writer)
    let reservation = try #require(
      try await service.reserveNext(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID
      )
    )
    writer.setFailures(before: [2], after: [])

    let receiptError: AgentEventDeliveryLedgerError? = await ledgerError {
      _ = try await service.settle(reservation, outcome: .httpStatus(200, retryAfter: nil))
    }
    #expect(receiptError == .storageFailure)
    #expect(try fixture.readLedger().records.first?.status == .reserved)

    let reopened = fixture.service()
    fixture.clock.set(fixture.baseDate.addingTimeInterval(31))
    #expect(
      try await reopened.reserveNext(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID
      ) == nil
    )
    fixture.clock.set(fixture.baseDate.addingTimeInterval(36))
    let retry = try #require(
      try await reopened.reserveNext(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID
      )
    )
    #expect(retry.eventID == reservation.eventID)
    #expect(retry.sourcePosition == reservation.sourcePosition)
    #expect(retry.attemptCount == 2)
    #expect(try await reopened.observe(retry).body == fixture.bodies[0])
    #expect(try fixture.readLedger().records.first?.status == .reserved)
  }

  @Test func twoInstancesRecoverExpiredLeasesAndOldGenerationsCannotReleaseSuccessors()
    async throws
  {
    let fixture = try await LedgerFixture.make()
    defer { fixture.remove() }
    let serviceA = fixture.service()
    let serviceB = fixture.service()
    let reservationA = try #require(
      try await serviceA.reserveNext(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID
      )
    )
    #expect(
      try await serviceB.reserveNext(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID
      ) == nil
    )

    fixture.clock.set(fixture.baseDate.addingTimeInterval(31))
    #expect(
      try await serviceB.reserveNext(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID
      ) == nil
    )
    fixture.clock.set(fixture.baseDate.addingTimeInterval(36))
    let reservationB = try #require(
      try await serviceB.reserveNext(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID
      )
    )
    #expect(reservationB.attemptCount == 2)
    #expect(reservationB.id != reservationA.id)

    let staleObservation: AgentEventDeliveryLedgerError? = await ledgerError {
      _ = try await serviceA.observe(reservationA)
    }
    #expect(staleObservation == .staleReservation)
    let staleCancellation: AgentEventDeliveryLedgerError? = await ledgerError {
      _ = try await serviceA.cancel(reservationA)
    }
    #expect(staleCancellation == .staleReservation)
    let staleReceipt: AgentEventDeliveryLedgerError? = await ledgerError {
      _ = try await serviceA.settle(
        reservationA,
        outcome: .httpStatus(204, retryAfter: nil)
      )
    }
    #expect(staleReceipt == .staleReservation)
    #expect(try await serviceB.observe(reservationB).body == fixture.bodies[0])
    #expect(
      try fixture.readLedger().records.first?.reservationID
        == reservationB.id.uuidString.lowercased())

    let cancelled = try await serviceB.cancel(reservationB)
    #expect(cancelled.status == .retryWaiting)
    #expect(cancelled.failureCategory == .cancelled)
  }

  @Test func globalAndPerSubscriptionSlotsBlockAndReleaseReservations() throws {
    let rootFixture = try LedgerFixture.makeRoot()
    let root = rootFixture.url
    defer { cleanupLedgerFixtureRoot(rootFixture) }
    let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
    let store = AgentEventDeliveryLedgerStore(
      fileURL: root.appendingPathComponent("event-delivery-ledger.json"),
      now: { baseDate },
      jitterBasisPoints: { 0 }
    )
    let candidates = (1...5).map { value in
      directCandidate(profile: stableUUID(value), subscription: value, event: value)
    }
    let reservations = try candidates.prefix(4).map {
      candidate -> AgentEventDeliveryLedgerReservation in
      guard case .reserved(let reservation) = try reserve(candidate, in: store) else {
        Issue.record("The first four independent reservations should be admitted.")
        throw AgentEventDeliveryLedgerError.storageFailure
      }
      return reservation
    }
    #expect(try reserve(candidates[4], in: store) == .blocked)

    let cancellation = try cancel(reservations[0], in: store)
    #expect(cancellation.status == .retryWaiting)
    guard case .reserved(let fifth) = try reserve(candidates[4], in: store) else {
      Issue.record("Cancellation should release a global slot.")
      return
    }

    let nextCandidate = directCandidate(
      profile: stableUUID(5),
      subscription: 5,
      event: 6,
    )
    #expect(try reserve(nextCandidate, in: store) == .blocked)
    #expect(
      try settle(fifth, outcome: .httpStatus(204, retryAfter: nil), in: store).status == .receipt)
    guard case .reserved(let next) = try reserve(nextCandidate, in: store) else {
      Issue.record("A receipt should release the per-subscription slot.")
      return
    }
    #expect(
      try settle(next, outcome: .httpStatus(204, retryAfter: nil), in: store).status == .receipt)
    let refreshedCandidate = directCandidate(
      profile: stableUUID(5),
      subscription: 5,
      event: 6,
      revision: 2
    )
    guard case .reserved(let refreshed) = try reserve(refreshedCandidate, in: store) else {
      Issue.record("A validated binding refresh should start a separate attempt.")
      return
    }
    #expect(refreshed.attemptCount == 1)
    #expect(refreshed.binding.subscriptionRevision == 2)
  }

  @Test func aLateReceiptBindingCannotSupersedeSuccessorRetryOrPause() async throws {
    let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
    for successorStatus in [AgentEventDeliveryLedgerRecordStatus.retryWaiting, .paused] {
      let rootFixture = try LedgerFixture.makeRoot()
      let root = rootFixture.url
      defer { cleanupLedgerFixtureRoot(rootFixture) }
      let fileURL = root.appendingPathComponent("event-delivery-ledger.json")
      let oldCandidate = directCandidate(
        profile: stableUUID(80),
        subscription: 80,
        event: 81,
        revision: 1
      )
      let successorCandidate = directCandidate(
        profile: stableUUID(80),
        subscription: 80,
        event: 81,
        revision: 2
      )
      let oldGeneration = AgentEventDeliveryLedgerBindingGeneration(
        binding: oldCandidate.binding,
        generationID: stableUUID(90_080).uuidString.lowercased()
      )
      let successorGeneration = AgentEventDeliveryLedgerBindingGeneration(
        binding: successorCandidate.binding,
        generationID: stableUUID(90_081).uuidString.lowercased()
      )
      let receipt = AgentEventDeliveryLedgerRecord(
        binding: oldCandidate.binding,
        bindingGenerationID: oldGeneration.generationID,
        eventID: oldCandidate.eventID,
        sourcePosition: oldCandidate.sourcePosition,
        expiresAt: try #require(oldCandidate.expiresAt),
        attemptCount: 1,
        status: .receipt,
        reservationID: nil,
        leaseDeadline: nil,
        nextEligibleAt: nil,
        httpStatus: 204,
        failureCategory: nil
      )
      let successor = AgentEventDeliveryLedgerRecord(
        binding: successorCandidate.binding,
        bindingGenerationID: successorGeneration.generationID,
        eventID: successorCandidate.eventID,
        sourcePosition: successorCandidate.sourcePosition,
        expiresAt: try #require(successorCandidate.expiresAt),
        attemptCount: 1,
        status: successorStatus,
        reservationID: nil,
        leaseDeadline: nil,
        nextEligibleAt: successorStatus == .retryWaiting ? baseDate.addingTimeInterval(5) : nil,
        httpStatus: successorStatus == .retryWaiting ? 503 : 400,
        failureCategory: successorStatus == .retryWaiting ? .retryableHTTP : .pausedHTTP
      )
      try write(
        ledgerDocument(
          records: [receipt, successor],
          bindingGenerations: [successorGeneration],
          lastObservedAt: baseDate
        ),
        to: fileURL
      )
      let store = AgentEventDeliveryLedgerStore(
        fileURL: fileURL,
        now: { baseDate.addingTimeInterval(10) },
        jitterBasisPoints: { 0 }
      )
      let before = try Data(contentsOf: fileURL)
      let staleAdmission: AgentEventDeliveryLedgerError? = await ledgerError {
        try store.reconcileAndReserve(
          candidates: [oldCandidate],
          validatedBinding: oldCandidate.binding,
          expectedGeneration: oldGeneration
        )
      }
      #expect(staleAdmission == .sourceChanged)
      let rows = try JSONDecoder().decode(
        AgentEventDeliveryLedgerDocument.self,
        from: Data(contentsOf: fileURL)
      ).records
      #expect(
        rows.first(where: { $0.binding == successorCandidate.binding })?.status
          == successorStatus
      )
      #expect(try Data(contentsOf: fileURL) == before)
    }
  }

  @Test func bindingGenerationFollowsValidatedSourceRollbackNotRevisionRank() throws {
    let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
    let clock = LedgerTestClock(date: baseDate)
    let oldCandidate = directCandidate(profile: stableUUID(82), subscription: 82, event: 83)
    let newerCandidate = directCandidate(
      profile: stableUUID(82),
      subscription: 82,
      event: 83,
      revision: 2
    )
    let rootFixture = try LedgerFixture.makeRoot()
    let root = rootFixture.url
    defer { cleanupLedgerFixtureRoot(rootFixture) }
    let store = AgentEventDeliveryLedgerStore(
      fileURL: root.appendingPathComponent("event-delivery-ledger.json"),
      now: { clock.now() },
      jitterBasisPoints: { 0 }
    )

    #expect(
      try store.reconcileAndReserve(
        candidates: [],
        validatedBinding: oldCandidate.binding,
        expectedGeneration: nil
      ) == .skipped
    )
    let originalGeneration = try #require(
      try store.currentBindingGeneration(
        profileID: oldCandidate.binding.profileID,
        subscriptionID: oldCandidate.binding.subscriptionID
      )
    )
    guard case .reserved(let newerReservation) = try reserve(newerCandidate, in: store) else {
      Issue.record("A validated higher revision should create its own generation.")
      return
    }
    let newerGeneration = try #require(
      try store.currentBindingGeneration(
        profileID: newerCandidate.binding.profileID,
        subscriptionID: newerCandidate.binding.subscriptionID
      )
    )

    #expect(
      try store.reconcileAndReserve(
        candidates: [oldCandidate],
        validatedBinding: oldCandidate.binding,
        expectedGeneration: newerGeneration
      ) == .blocked
    )
    let rollbackGeneration = try #require(
      try store.currentBindingGeneration(
        profileID: oldCandidate.binding.profileID,
        subscriptionID: oldCandidate.binding.subscriptionID
      )
    )
    #expect(rollbackGeneration.binding == oldCandidate.binding)
    #expect(rollbackGeneration.generationID != originalGeneration.generationID)
    #expect(
      rollbackGeneration.pendingReservationGenerationID == newerReservation.bindingGenerationID)

    clock.set(baseDate.addingTimeInterval(31))
    guard case .reserved(let rollbackReservation) = try reserve(oldCandidate, in: store) else {
      Issue.record(
        "A validated source rollback should reserve after the predecessor lease expires.")
      return
    }
    #expect(rollbackReservation.binding.subscriptionRevision == 1)
    #expect(rollbackReservation.attemptCount == 1)
    #expect(
      try store.currentBindingGeneration(
        profileID: oldCandidate.binding.profileID,
        subscriptionID: oldCandidate.binding.subscriptionID
      )?.generationID == rollbackGeneration.generationID
    )
    let document = try JSONDecoder().decode(
      AgentEventDeliveryLedgerDocument.self,
      from: Data(contentsOf: store.fileURL)
    )
    #expect(
      document.records.contains(where: {
        $0.bindingGenerationID == newerReservation.bindingGenerationID
          && $0.status == .superseded
      })
    )
  }

  @Test func generationOwnershipRejectsUnlinkedLiveRowsAndAmbiguousPredecessors()
    async throws
  {
    let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
    let profileID = stableUUID(83)
    let previous = directCandidate(profile: profileID, subscription: 83, event: 83)
    let current = directCandidate(
      profile: profileID,
      subscription: 83,
      event: 83,
      revision: 2
    )
    let previousGenerationID = stableUUID(91_000).uuidString.lowercased()
    let currentGeneration = AgentEventDeliveryLedgerBindingGeneration(
      binding: current.binding,
      generationID: stableUUID(91_001).uuidString.lowercased()
    )
    let liveDeadline = baseDate.addingTimeInterval(30)

    func document(
      records: [AgentEventDeliveryLedgerRecord],
      generations: [AgentEventDeliveryLedgerBindingGeneration]
    ) -> AgentEventDeliveryLedgerDocument {
      ledgerDocument(
        records: records.sorted(by: AgentEventDeliveryLedgerDocument.recordOrder),
        bindingGenerations: generations.sorted(
          by: AgentEventDeliveryLedgerDocument.bindingGenerationOrder),
        lastObservedAt: baseDate
      )
    }

    func reservedRecord(
      _ candidate: AgentEventDeliveryLedgerCandidate,
      generationID: String,
      reservationNumber: Int
    ) throws -> AgentEventDeliveryLedgerRecord {
      AgentEventDeliveryLedgerRecord(
        binding: candidate.binding,
        bindingGenerationID: generationID,
        eventID: candidate.eventID,
        sourcePosition: candidate.sourcePosition,
        expiresAt: try #require(candidate.expiresAt),
        attemptCount: 1,
        status: .reserved,
        reservationID: stableUUID(reservationNumber).uuidString.lowercased(),
        leaseDeadline: liveDeadline,
        nextEligibleAt: nil,
        httpStatus: nil,
        failureCategory: nil
      )
    }

    func retryRecord(
      _ candidate: AgentEventDeliveryLedgerCandidate,
      generationID: String
    ) throws -> AgentEventDeliveryLedgerRecord {
      AgentEventDeliveryLedgerRecord(
        binding: candidate.binding,
        bindingGenerationID: generationID,
        eventID: candidate.eventID,
        sourcePosition: candidate.sourcePosition,
        expiresAt: try #require(candidate.expiresAt),
        attemptCount: 1,
        status: .retryWaiting,
        reservationID: nil,
        leaseDeadline: nil,
        nextEligibleAt: baseDate.addingTimeInterval(5),
        httpStatus: nil,
        failureCategory: .transportFailure
      )
    }

    func pausedRecord(
      _ candidate: AgentEventDeliveryLedgerCandidate,
      generationID: String
    ) throws -> AgentEventDeliveryLedgerRecord {
      AgentEventDeliveryLedgerRecord(
        binding: candidate.binding,
        bindingGenerationID: generationID,
        eventID: candidate.eventID,
        sourcePosition: candidate.sourcePosition,
        expiresAt: try #require(candidate.expiresAt),
        attemptCount: 1,
        status: .paused,
        reservationID: nil,
        leaseDeadline: nil,
        nextEligibleAt: nil,
        httpStatus: 400,
        failureCategory: .pausedHTTP
      )
    }

    func reservation(
      for record: AgentEventDeliveryLedgerRecord
    ) throws -> AgentEventDeliveryLedgerReservation {
      guard
        let reservationID = record.reservationID,
        let id = UUID(uuidString: reservationID),
        let leaseDeadline = record.leaseDeadline
      else {
        throw AgentEventDeliveryLedgerError.storageFailure
      }
      return AgentEventDeliveryLedgerReservation(
        id: id,
        binding: record.binding,
        bindingGenerationID: record.bindingGenerationID,
        eventID: record.eventID,
        sourcePosition: record.sourcePosition,
        expiresAt: record.expiresAt,
        attemptCount: record.attemptCount,
        leaseDeadline: leaseDeadline
      )
    }

    let orphan = try reservedRecord(
      previous,
      generationID: previousGenerationID,
      reservationNumber: 91_010
    )
    let orphaned = document(records: [orphan], generations: [currentGeneration])

    let otherProfileID = stableUUID(84)
    let otherPrevious = directCandidate(
      profile: otherProfileID,
      subscription: 84,
      event: 84
    )
    let otherCurrent = directCandidate(
      profile: otherProfileID,
      subscription: 84,
      event: 84,
      revision: 2
    )
    let sharedPendingID = stableUUID(91_020).uuidString.lowercased()
    let otherCurrentGeneration = AgentEventDeliveryLedgerBindingGeneration(
      binding: otherCurrent.binding,
      generationID: stableUUID(91_021).uuidString.lowercased(),
      pendingReservationGenerationID: sharedPendingID
    )
    let currentWithPending = AgentEventDeliveryLedgerBindingGeneration(
      binding: current.binding,
      generationID: currentGeneration.generationID,
      pendingReservationGenerationID: sharedPendingID
    )
    let firstPredecessor = try reservedRecord(
      previous,
      generationID: sharedPendingID,
      reservationNumber: 91_022
    )
    let secondPredecessor = try reservedRecord(
      otherPrevious,
      generationID: sharedPendingID,
      reservationNumber: 91_023
    )
    let predecessorIDReusedAcrossSubscriptions = document(
      records: [firstPredecessor, secondPredecessor],
      generations: [currentWithPending, otherCurrentGeneration]
    )

    let retryingOldGeneration = document(
      records: [try retryRecord(previous, generationID: previousGenerationID)],
      generations: [currentGeneration]
    )
    let pausedOldGeneration = document(
      records: [try pausedRecord(previous, generationID: previousGenerationID)],
      generations: [currentGeneration]
    )
    let missingPredecessor = document(
      records: [],
      generations: [
        AgentEventDeliveryLedgerBindingGeneration(
          binding: current.binding,
          generationID: currentGeneration.generationID,
          pendingReservationGenerationID: previousGenerationID
        )
      ]
    )
    let foreignSIDPrevious = directCandidate(
      profile: profileID,
      subscription: 85,
      event: 85
    )
    let foreignSIDRecord = try reservedRecord(
      foreignSIDPrevious,
      generationID: previousGenerationID,
      reservationNumber: 91_024
    )
    let foreignSIDPredecessor = document(
      records: [foreignSIDRecord],
      generations: [
        AgentEventDeliveryLedgerBindingGeneration(
          binding: current.binding,
          generationID: currentGeneration.generationID,
          pendingReservationGenerationID: previousGenerationID
        )
      ]
    )

    let scenarios:
      [(
        String,
        AgentEventDeliveryLedgerDocument,
        AgentEventDeliveryLedgerBindingGeneration,
        AgentEventDeliveryLedgerCandidate,
        AgentEventDeliveryLedgerReservation
      )] = [
        (
          "live predecessor after refresh with missing pending link",
          orphaned,
          currentGeneration,
          current,
          try reservation(for: orphan)
        ),
        (
          "one predecessor UUID linked across subscriptions",
          predecessorIDReusedAcrossSubscriptions,
          currentWithPending,
          current,
          try reservation(for: firstPredecessor)
        ),
        (
          "retry-waiting row owned by a superseded generation",
          retryingOldGeneration,
          currentGeneration,
          current,
          try reservation(for: orphan)
        ),
        (
          "paused row owned by a superseded generation",
          pausedOldGeneration,
          currentGeneration,
          current,
          try reservation(for: orphan)
        ),
        (
          "missing pending predecessor row",
          missingPredecessor,
          AgentEventDeliveryLedgerBindingGeneration(
            binding: current.binding,
            generationID: currentGeneration.generationID,
            pendingReservationGenerationID: previousGenerationID
          ),
          current,
          try reservation(for: orphan)
        ),
        (
          "pending predecessor with a foreign subscription ID",
          foreignSIDPredecessor,
          AgentEventDeliveryLedgerBindingGeneration(
            binding: current.binding,
            generationID: currentGeneration.generationID,
            pendingReservationGenerationID: previousGenerationID
          ),
          current,
          try reservation(for: foreignSIDRecord)
        ),
      ]

    let rootFixture = try LedgerFixture.makeRoot()
    let root = rootFixture.url
    defer { cleanupLedgerFixtureRoot(rootFixture) }
    let fileURL = root.appendingPathComponent("event-delivery-ledger.json")
    for (label, rawDocument, expectedGeneration, candidate, observedReservation) in scenarios {
      for operation in ["currentBindingGeneration", "admission", "observe"] {
        try write(rawDocument, to: fileURL)
        let before = try Data(contentsOf: fileURL)
        let store = AgentEventDeliveryLedgerStore(
          fileURL: fileURL,
          now: { baseDate },
          jitterBasisPoints: { 0 }
        )

        if operation == "currentBindingGeneration" {
          var foundGeneration: AgentEventDeliveryLedgerBindingGeneration?
          let error: AgentEventDeliveryLedgerError? = await ledgerError {
            foundGeneration = try store.currentBindingGeneration(
              profileID: candidate.binding.profileID,
              subscriptionID: candidate.binding.subscriptionID
            )
          }
          #expect(error == .storageFailure, "corrupt \(label) read error")
          #expect(foundGeneration == nil, "corrupt \(label) returned a generation")
        } else if operation == "admission" {
          var decision: AgentEventDeliveryLedgerReservationDecision?
          let error: AgentEventDeliveryLedgerError? = await ledgerError {
            decision = try store.reconcileAndReserve(
              candidates: [candidate],
              validatedBinding: candidate.binding,
              expectedGeneration: expectedGeneration
            )
          }
          #expect(error == .storageFailure, "corrupt \(label) admission error")
          #expect(decision == nil, "corrupt \(label) returned \(String(describing: decision))")
        } else {
          let error: AgentEventDeliveryLedgerError? = await ledgerError {
            try store.observe(observedReservation, expectedGeneration: expectedGeneration)
          }
          #expect(error == .storageFailure, "corrupt \(label) observe error")
        }

        #expect(try Data(contentsOf: fileURL) == before, "preserved \(label) after \(operation)")
      }
    }
  }

  @Test func generationOwnershipPreservesCurrentRowsAndUnknownHistory() throws {
    let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
    let profileID = stableUUID(86)
    let previous = directCandidate(profile: profileID, subscription: 86, event: 86)
    let current = directCandidate(
      profile: profileID,
      subscription: 86,
      event: 86,
      revision: 2
    )
    let pausedCandidate = directCandidate(
      profile: profileID,
      subscription: 86,
      event: 93,
      revision: 2
    )
    let currentGeneration = AgentEventDeliveryLedgerBindingGeneration(
      binding: current.binding,
      generationID: stableUUID(91_100).uuidString.lowercased()
    )
    let previousGenerationID = stableUUID(91_101).uuidString.lowercased()

    func record(
      _ candidate: AgentEventDeliveryLedgerCandidate,
      generationID: String,
      status: AgentEventDeliveryLedgerRecordStatus,
      attemptCount: UInt64 = 1,
      reservationID: String? = nil,
      leaseDeadline: Date? = nil,
      nextEligibleAt: Date? = nil,
      httpStatus: Int? = nil,
      failureCategory: AgentEventDeliveryLedgerFailureCategory? = nil
    ) throws -> AgentEventDeliveryLedgerRecord {
      AgentEventDeliveryLedgerRecord(
        binding: candidate.binding,
        bindingGenerationID: generationID,
        eventID: candidate.eventID,
        sourcePosition: candidate.sourcePosition,
        expiresAt: try #require(candidate.expiresAt),
        attemptCount: attemptCount,
        status: status,
        reservationID: reservationID,
        leaseDeadline: leaseDeadline,
        nextEligibleAt: nextEligibleAt,
        httpStatus: httpStatus,
        failureCategory: failureCategory
      )
    }

    let records = try [
      record(
        current,
        generationID: currentGeneration.generationID,
        status: .retryWaiting,
        nextEligibleAt: baseDate.addingTimeInterval(5),
        failureCategory: .transportFailure
      ),
      record(
        pausedCandidate,
        generationID: currentGeneration.generationID,
        status: .paused,
        httpStatus: 400,
        failureCategory: .pausedHTTP
      ),
      record(
        directCandidate(profile: profileID, subscription: 86, event: 87),
        generationID: previousGenerationID,
        status: .receipt,
        httpStatus: 204
      ),
      record(
        directCandidate(profile: profileID, subscription: 86, event: 88),
        generationID: previousGenerationID,
        status: .terminal,
        httpStatus: 410,
        failureCategory: .terminalHTTP
      ),
      record(
        directCandidate(profile: profileID, subscription: 86, event: 89),
        generationID: previousGenerationID,
        status: .expired,
        failureCategory: .retentionExpired
      ),
      record(
        directCandidate(profile: profileID, subscription: 86, event: 90),
        generationID: previousGenerationID,
        status: .exhausted,
        attemptCount: 12,
        httpStatus: 503,
        failureCategory: .attemptsExhausted
      ),
      record(
        directCandidate(profile: profileID, subscription: 86, event: 91),
        generationID: previousGenerationID,
        status: .superseded,
        failureCategory: .bindingRefreshed
      ),
      record(
        directCandidate(profile: profileID, subscription: 86, event: 92),
        generationID: previousGenerationID,
        status: .reserved,
        reservationID: stableUUID(91_102).uuidString.lowercased(),
        leaseDeadline: baseDate.addingTimeInterval(-1)
      ),
    ].sorted(by: AgentEventDeliveryLedgerDocument.recordOrder)
    let rawDocument = ledgerDocument(
      records: records,
      bindingGenerations: [currentGeneration],
      lastObservedAt: baseDate
    )
    let rootFixture = try LedgerFixture.makeRoot()
    let root = rootFixture.url
    defer { cleanupLedgerFixtureRoot(rootFixture) }
    let fileURL = root.appendingPathComponent("event-delivery-ledger.json")
    try write(rawDocument, to: fileURL)
    let before = try Data(contentsOf: fileURL)
    let store = AgentEventDeliveryLedgerStore(fileURL: fileURL, now: { baseDate })

    #expect(
      try store.currentBindingGeneration(
        profileID: current.binding.profileID,
        subscriptionID: current.binding.subscriptionID
      ) == currentGeneration
    )
    #expect(try Data(contentsOf: fileURL) == before)
    let decoded = try JSONDecoder().decode(
      AgentEventDeliveryLedgerDocument.self,
      from: Data(contentsOf: fileURL)
    )
    #expect(decoded == rawDocument)
    #expect(decoded.records.count == 8)
    #expect(decoded.records.contains { $0.status == .retryWaiting })
    #expect(decoded.records.contains { $0.status == .paused })
    #expect(decoded.records.contains { $0.status == .receipt })
    #expect(decoded.records.contains { $0.status == .terminal })
    #expect(decoded.records.contains { $0.status == .expired })
    #expect(decoded.records.contains { $0.status == .exhausted })
    #expect(decoded.records.contains { $0.status == .superseded })
    #expect(
      decoded.records.contains {
        $0.status == .reserved && $0.leaseDeadline == baseDate.addingTimeInterval(-1)
      }
    )

    let expiredHighWater = baseDate.addingTimeInterval(31)
    let expiredDocument = ledgerDocument(
      records: [
        try record(
          previous,
          generationID: previousGenerationID,
          status: .reserved,
          reservationID: stableUUID(91_103).uuidString.lowercased(),
          leaseDeadline: baseDate.addingTimeInterval(30)
        )
      ],
      bindingGenerations: [currentGeneration],
      lastObservedAt: expiredHighWater
    )
    try write(expiredDocument, to: fileURL)
    let expiredBytes = try Data(contentsOf: fileURL)
    let expiredStore = AgentEventDeliveryLedgerStore(fileURL: fileURL, now: { expiredHighWater })
    #expect(
      try expiredStore.currentBindingGeneration(
        profileID: current.binding.profileID,
        subscriptionID: current.binding.subscriptionID
      ) == currentGeneration
    )
    #expect(try Data(contentsOf: fileURL) == expiredBytes)
    let preservedExpired = try JSONDecoder().decode(
      AgentEventDeliveryLedgerDocument.self,
      from: Data(contentsOf: fileURL)
    )
    #expect(preservedExpired == expiredDocument)
    #expect(preservedExpired.records.first?.status == .reserved)
    #expect(preservedExpired.records.first?.bindingGenerationID == previousGenerationID)
  }

  @Test func repeatedRefreshRetainsOriginalLivePredecessorUntilLeaseExpiry() throws {
    let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
    let clock = LedgerTestClock(date: baseDate)
    let profileID = stableUUID(87)
    let original = directCandidate(profile: profileID, subscription: 87, event: 87)
    let refreshed = directCandidate(
      profile: profileID,
      subscription: 87,
      event: 87,
      revision: 2
    )
    let refreshedAgain = directCandidate(
      profile: profileID,
      subscription: 87,
      event: 87,
      revision: 3
    )
    let rootFixture = try LedgerFixture.makeRoot()
    let root = rootFixture.url
    defer { cleanupLedgerFixtureRoot(rootFixture) }
    let fileURL = root.appendingPathComponent("event-delivery-ledger.json")
    let store = AgentEventDeliveryLedgerStore(
      fileURL: fileURL,
      now: { clock.now() },
      jitterBasisPoints: { 0 }
    )
    #expect(
      try store.reconcileAndReserve(
        candidates: [],
        validatedBinding: original.binding,
        expectedGeneration: nil
      ) == .skipped
    )
    let originalGeneration = try #require(
      try store.currentBindingGeneration(
        profileID: original.binding.profileID,
        subscriptionID: original.binding.subscriptionID
      )
    )
    guard case .reserved(let predecessor) = try reserve(original, in: store) else {
      Issue.record("The original binding should own the initial live lease.")
      return
    }

    #expect(
      try store.reconcileAndReserve(
        candidates: [refreshed],
        validatedBinding: refreshed.binding,
        expectedGeneration: originalGeneration
      ) == .blocked
    )
    let refreshedGeneration = try #require(
      try store.currentBindingGeneration(
        profileID: refreshed.binding.profileID,
        subscriptionID: refreshed.binding.subscriptionID
      )
    )
    #expect(refreshedGeneration.binding == refreshed.binding)
    #expect(refreshedGeneration.pendingReservationGenerationID == predecessor.bindingGenerationID)

    #expect(
      try store.reconcileAndReserve(
        candidates: [refreshedAgain],
        validatedBinding: refreshedAgain.binding,
        expectedGeneration: refreshedGeneration
      ) == .blocked
    )
    let latestGeneration = try #require(
      try store.currentBindingGeneration(
        profileID: refreshedAgain.binding.profileID,
        subscriptionID: refreshedAgain.binding.subscriptionID
      )
    )
    #expect(latestGeneration.binding == refreshedAgain.binding)
    #expect(latestGeneration.generationID != refreshedGeneration.generationID)
    #expect(latestGeneration.pendingReservationGenerationID == predecessor.bindingGenerationID)
    let beforeExpiry = try JSONDecoder().decode(
      AgentEventDeliveryLedgerDocument.self,
      from: Data(contentsOf: fileURL)
    )
    #expect(beforeExpiry.records.count == 1)
    #expect(beforeExpiry.records.first?.bindingGenerationID == predecessor.bindingGenerationID)
    #expect(beforeExpiry.records.first?.status == .reserved)
    #expect(beforeExpiry.records.first?.reservationID == predecessor.id.uuidString.lowercased())
    #expect(beforeExpiry.records.first?.leaseDeadline == predecessor.leaseDeadline)

    clock.set(baseDate.addingTimeInterval(31))
    guard case .reserved(let successor) = try reserve(refreshedAgain, in: store) else {
      Issue.record("The latest validated binding should reserve after the predecessor expires.")
      return
    }
    #expect(successor.bindingGenerationID == latestGeneration.generationID)
    #expect(successor.attemptCount == 1)
    let recovered = try JSONDecoder().decode(
      AgentEventDeliveryLedgerDocument.self,
      from: Data(contentsOf: fileURL)
    )
    #expect(recovered.lastObservedAt == clock.now())
    #expect(
      recovered.bindingGenerations.first(where: { $0.binding == refreshedAgain.binding })?
        .pendingReservationGenerationID == nil
    )
    let recoveredPredecessor = try #require(
      recovered.records.first(where: { $0.bindingGenerationID == predecessor.bindingGenerationID })
    )
    #expect(recoveredPredecessor.status == .superseded)
    #expect(recoveredPredecessor.reservationID == nil)
    #expect(recoveredPredecessor.leaseDeadline == nil)
    #expect(recoveredPredecessor.failureCategory == .bindingRefreshed)
    let recoveredSuccessor = try #require(
      recovered.records.first(where: { $0.bindingGenerationID == successor.bindingGenerationID })
    )
    #expect(recoveredSuccessor.status == .reserved)
    #expect(recoveredSuccessor.binding == refreshedAgain.binding)
    #expect(recoveredSuccessor.reservationID == successor.id.uuidString.lowercased())
    #expect(recoveredSuccessor.leaseDeadline == successor.leaseDeadline)
  }

  @Test func persistedDocumentRejectsForgedLiveSlotCountsAndLeaseHorizons() async throws {
    let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
    func reservedRecord(
      _ candidate: AgentEventDeliveryLedgerCandidate,
      reservationNumber: Int,
      deadline: Date
    ) throws -> AgentEventDeliveryLedgerRecord {
      AgentEventDeliveryLedgerRecord(
        binding: candidate.binding,
        bindingGenerationID: stableUUID(90_100 + reservationNumber).uuidString.lowercased(),
        eventID: candidate.eventID,
        sourcePosition: candidate.sourcePosition,
        expiresAt: try #require(candidate.expiresAt),
        attemptCount: 1,
        status: .reserved,
        reservationID: stableUUID(reservationNumber).uuidString.lowercased(),
        leaseDeadline: deadline,
        nextEligibleAt: nil,
        httpStatus: nil,
        failureCategory: nil
      )
    }
    let liveDeadline = baseDate.addingTimeInterval(30)
    let fiveLiveReservations = try (1...5).map { value in
      try reservedRecord(
        directCandidate(profile: stableUUID(value), subscription: value, event: value),
        reservationNumber: 90_100 + value,
        deadline: liveDeadline
      )
    }
    let sameSubscriptionA = directCandidate(
      profile: stableUUID(91),
      subscription: 91,
      event: 92,
      revision: 1
    )
    let sameSubscriptionB = directCandidate(
      profile: stableUUID(91),
      subscription: 91,
      event: 93,
      revision: 2
    )
    var corruptions:
      [(String, AgentEventDeliveryLedgerDocument, AgentEventDeliveryLedgerCandidate)] = [
        (
          "five live slots",
          ledgerDocument(
            records: fiveLiveReservations,
            lastObservedAt: baseDate
          ),
          directCandidate(profile: stableUUID(6), subscription: 6, event: 6)
        ),
        (
          "two live generations for one subscription",
          ledgerDocument(
            records: [
              try reservedRecord(
                sameSubscriptionA, reservationNumber: 90_201, deadline: liveDeadline),
              try reservedRecord(
                sameSubscriptionB, reservationNumber: 90_202, deadline: liveDeadline),
            ],
            lastObservedAt: baseDate
          ),
          directCandidate(profile: stableUUID(91), subscription: 91, event: 94, revision: 3)
        ),
      ]
    for (index, excess) in [31.0, 100.0].enumerated() {
      let candidate = directCandidate(profile: stableUUID(92), subscription: 92, event: index + 1)
      corruptions.append(
        (
          "lease horizon +\(Int(excess)) seconds",
          ledgerDocument(
            records: [
              try reservedRecord(
                candidate,
                reservationNumber: 90_300 + index,
                deadline: baseDate.addingTimeInterval(excess)
              )
            ],
            lastObservedAt: baseDate
          ),
          directCandidate(profile: stableUUID(93), subscription: 93, event: index + 1)
        )
      )
    }
    let hugeHighWater = Date(timeIntervalSince1970: 1e308)
    let hugeDeadline = Date(timeIntervalSince1970: 1.0000000000000002e308)
    let hugeExpiry = Date(timeIntervalSince1970: 1.0000000000000004e308)
    let hugeCandidate = directCandidate(
      profile: stableUUID(94),
      subscription: 94,
      event: 95,
      eventTimestamp: hugeHighWater,
      subscriptionExpiresAt: hugeExpiry
    )
    let hugeRow = AgentEventDeliveryLedgerRecord(
      binding: hugeCandidate.binding,
      bindingGenerationID: stableUUID(90_400).uuidString.lowercased(),
      eventID: hugeCandidate.eventID,
      sourcePosition: hugeCandidate.sourcePosition,
      expiresAt: hugeExpiry,
      attemptCount: 1,
      status: .reserved,
      reservationID: stableUUID(90_400).uuidString.lowercased(),
      leaseDeadline: hugeDeadline,
      nextEligibleAt: nil,
      httpStatus: nil,
      failureCategory: nil
    )
    corruptions.append(
      (
        "nonrepresentable lease horizon near Double bounds",
        ledgerDocument(records: [hugeRow], lastObservedAt: hugeHighWater),
        directCandidate(profile: stableUUID(95), subscription: 95, event: 96)
      )
    )

    let roundedHighWater = Date(timeIntervalSince1970: 1e17)
    let roundedCandidate = directCandidate(
      profile: stableUUID(95),
      subscription: 95,
      event: 97,
      eventTimestamp: roundedHighWater,
      subscriptionExpiresAt: roundedHighWater.addingTimeInterval(604_800)
    )
    let roundedRow = AgentEventDeliveryLedgerRecord(
      binding: roundedCandidate.binding,
      bindingGenerationID: stableUUID(90_401).uuidString.lowercased(),
      eventID: roundedCandidate.eventID,
      sourcePosition: roundedCandidate.sourcePosition,
      expiresAt: try #require(roundedCandidate.expiresAt),
      attemptCount: 1,
      status: .reserved,
      reservationID: stableUUID(90_402).uuidString.lowercased(),
      leaseDeadline: roundedHighWater.addingTimeInterval(32),
      nextEligibleAt: nil,
      httpStatus: nil,
      failureCategory: nil
    )
    corruptions.append(
      (
        "rounded lease horizon exceeds 30 seconds",
        ledgerDocument(records: [roundedRow], lastObservedAt: roundedHighWater),
        directCandidate(profile: stableUUID(96), subscription: 96, event: 98)
      )
    )

    for (label, document, candidate) in corruptions {
      let rootFixture = try LedgerFixture.makeRoot()
      let root = rootFixture.url
      defer { cleanupLedgerFixtureRoot(rootFixture) }
      let fileURL = root.appendingPathComponent("event-delivery-ledger.json")
      try write(document, to: fileURL)
      let before = try Data(contentsOf: fileURL)
      let store = AgentEventDeliveryLedgerStore(
        fileURL: fileURL,
        now: { document.lastObservedAt },
        jitterBasisPoints: { 0 }
      )
      let error: AgentEventDeliveryLedgerError? = await ledgerError {
        try reserve(candidate, in: store)
      }
      #expect(error == .storageFailure, "corrupt \(label)")
      #expect(try Data(contentsOf: fileURL) == before, "preserved \(label)")
    }

    let unrepresentableRootFixture = try LedgerFixture.makeRoot()
    let unrepresentableRoot = unrepresentableRootFixture.url
    defer { cleanupLedgerFixtureRoot(unrepresentableRootFixture) }
    let unrepresentableURL = unrepresentableRoot.appendingPathComponent(
      "event-delivery-ledger.json")
    let unrepresentableCandidate = directCandidate(
      profile: stableUUID(97),
      subscription: 97,
      event: 99,
      eventTimestamp: roundedHighWater,
      subscriptionExpiresAt: roundedHighWater.addingTimeInterval(604_800)
    )
    let unrepresentableStore = AgentEventDeliveryLedgerStore(
      fileURL: unrepresentableURL,
      now: { roundedHighWater },
      jitterBasisPoints: { 0 }
    )
    let unrepresentableError: AgentEventDeliveryLedgerError? = await ledgerError {
      try reserve(unrepresentableCandidate, in: unrepresentableStore)
    }
    #expect(unrepresentableError == .invalidInput)
    #expect(!FileManager.default.fileExists(atPath: unrepresentableURL.path))

    let expiredRootFixture = try LedgerFixture.makeRoot()
    let expiredRoot = expiredRootFixture.url
    defer { cleanupLedgerFixtureRoot(expiredRootFixture) }
    let expiredURL = expiredRoot.appendingPathComponent("event-delivery-ledger.json")
    let expiredA = directCandidate(profile: stableUUID(96), subscription: 96, event: 97)
    let expiredB = directCandidate(
      profile: stableUUID(96),
      subscription: 96,
      event: 98,
      revision: 2
    )
    try write(
      ledgerDocument(
        records: [
          try reservedRecord(
            expiredA,
            reservationNumber: 90_500,
            deadline: baseDate.addingTimeInterval(-1)
          ),
          try reservedRecord(
            expiredB,
            reservationNumber: 90_501,
            deadline: baseDate.addingTimeInterval(-1)
          ),
        ],
        lastObservedAt: baseDate
      ),
      to: expiredURL
    )
    let expiredStore = AgentEventDeliveryLedgerStore(
      fileURL: expiredURL,
      now: { baseDate },
      jitterBasisPoints: { 0 }
    )
    guard
      case .reserved = try reserve(
        directCandidate(profile: stableUUID(97), subscription: 97, event: 97),
        in: expiredStore
      )
    else {
      Issue.record("Expired reservations should not consume persisted live slots.")
      return
    }
    #expect(
      try JSONDecoder().decode(
        AgentEventDeliveryLedgerDocument.self,
        from: Data(contentsOf: expiredURL)
      ).records.filter { $0.status == .reserved && $0.leaseDeadline! <= baseDate }.count == 2
    )
  }

  @Test func persistedRetryHorizonsRejectUnboundedFutureAndAllowDueRows() async throws {
    let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
    let candidate = directCandidate(
      profile: stableUUID(98),
      subscription: 98,
      event: 98,
      subscriptionExpiresAt: baseDate.addingTimeInterval(10_000)
    )
    let generationID = stableUUID(90_600).uuidString.lowercased()
    func retryRow(
      nextEligibleAt: Date,
      expiresAt: Date
    ) -> AgentEventDeliveryLedgerRecord {
      AgentEventDeliveryLedgerRecord(
        binding: candidate.binding,
        bindingGenerationID: generationID,
        eventID: candidate.eventID,
        sourcePosition: candidate.sourcePosition,
        expiresAt: expiresAt,
        attemptCount: 1,
        status: .retryWaiting,
        reservationID: nil,
        leaseDeadline: nil,
        nextEligibleAt: nextEligibleAt,
        httpStatus: 503,
        failureCategory: .retryableHTTP
      )
    }
    let invalidHorizons: [(String, Date, Date, Date)] = [
      (
        "retry deadline +901 seconds",
        baseDate,
        baseDate.addingTimeInterval(901),
        baseDate.addingTimeInterval(10_000)
      ),
      (
        "retry deadline +3600 seconds before expiry",
        baseDate,
        baseDate.addingTimeInterval(3_600),
        baseDate.addingTimeInterval(10_000)
      ),
      (
        "large finite retry interval at positive high-water precision edge",
        Date(timeIntervalSince1970: 1e16),
        Date(timeIntervalSince1970: 1e308),
        Date(timeIntervalSince1970: 1.0000000000000002e308)
      ),
      (
        "large finite retry interval at negative high-water precision edge",
        Date(timeIntervalSince1970: -1e16),
        Date(timeIntervalSince1970: 1e308),
        Date(timeIntervalSince1970: 1.0000000000000002e308)
      ),
    ]

    for (label, highWater, deadline, expiry) in invalidHorizons {
      let rootFixture = try LedgerFixture.makeRoot()
      let root = rootFixture.url
      defer { cleanupLedgerFixtureRoot(rootFixture) }
      let fileURL = root.appendingPathComponent("event-delivery-ledger.json")
      try write(
        ledgerDocument(
          records: [retryRow(nextEligibleAt: deadline, expiresAt: expiry)],
          lastObservedAt: highWater
        ),
        to: fileURL
      )
      let before = try Data(contentsOf: fileURL)
      let store = AgentEventDeliveryLedgerStore(
        fileURL: fileURL,
        now: { highWater },
        jitterBasisPoints: { 0 }
      )
      let error: AgentEventDeliveryLedgerError? = await ledgerError {
        _ = try store.currentBindingGeneration(
          profileID: candidate.binding.profileID,
          subscriptionID: candidate.binding.subscriptionID
        )
      }
      #expect(error == .storageFailure, "corrupt \(label)")
      #expect(try Data(contentsOf: fileURL) == before, "preserved \(label)")
      let preserved = try JSONDecoder().decode(
        AgentEventDeliveryLedgerDocument.self,
        from: Data(contentsOf: fileURL)
      )
      let row = try #require(preserved.records.first)
      #expect(preserved.lastObservedAt == highWater)
      #expect(row.status == .retryWaiting)
      #expect(row.nextEligibleAt == deadline)
      #expect(row.reservationID == nil)
      #expect(row.leaseDeadline == nil)
      #expect(row.httpStatus == 503)
      #expect(row.failureCategory == .retryableHTTP)
    }

    let dueHighWater = baseDate.addingTimeInterval(1_200)
    let dueDeadline = baseDate.addingTimeInterval(900)
    let dueRootFixture = try LedgerFixture.makeRoot()
    let dueRoot = dueRootFixture.url
    defer { cleanupLedgerFixtureRoot(dueRootFixture) }
    let dueURL = dueRoot.appendingPathComponent("event-delivery-ledger.json")
    try write(
      ledgerDocument(
        records: [
          retryRow(
            nextEligibleAt: dueDeadline,
            expiresAt: try #require(candidate.expiresAt)
          )
        ],
        lastObservedAt: dueHighWater
      ),
      to: dueURL
    )
    let dueStore = AgentEventDeliveryLedgerStore(
      fileURL: dueURL,
      now: { dueHighWater },
      jitterBasisPoints: { 0 }
    )
    guard case .reserved(let recovered) = try reserve(candidate, in: dueStore) else {
      Issue.record("A retry deadline already below the persisted high-water should be due.")
      return
    }
    #expect(recovered.attemptCount == 2)
    #expect(recovered.leaseDeadline.timeIntervalSince(dueHighWater) == 30)
    let recoveredDocument = try JSONDecoder().decode(
      AgentEventDeliveryLedgerDocument.self,
      from: Data(contentsOf: dueURL)
    )
    #expect(recoveredDocument.lastObservedAt == dueHighWater)
    #expect(recoveredDocument.records.first?.status == .reserved)
  }

  @Test func roundedRetryDeadlineRejectsUnderFloorWithoutChangingReservation() async throws {
    let now = Date(timeIntervalSince1970: 1e16)
    let candidate = directCandidate(
      profile: stableUUID(99),
      subscription: 99,
      event: 99,
      eventTimestamp: now,
      subscriptionExpiresAt: now.addingTimeInterval(604_800)
    )
    let rootFixture = try LedgerFixture.makeRoot()
    let root = rootFixture.url
    defer { cleanupLedgerFixtureRoot(rootFixture) }
    let fileURL = root.appendingPathComponent("event-delivery-ledger.json")
    let store = AgentEventDeliveryLedgerStore(
      fileURL: fileURL,
      now: { now },
      jitterBasisPoints: { 0 }
    )
    guard case .reserved(let reservation) = try reserve(candidate, in: store) else {
      Issue.record("The high-clock candidate should admit its representable 30-second lease.")
      return
    }
    #expect(reservation.leaseDeadline.timeIntervalSince(now) == 30)
    #expect(now.addingTimeInterval(5).timeIntervalSince(now) == 4)
    let before = try Data(contentsOf: fileURL)
    let documentBefore = try JSONDecoder().decode(
      AgentEventDeliveryLedgerDocument.self, from: before)
    #expect(documentBefore.lastObservedAt == now)
    let rowBefore = try #require(documentBefore.records.first)
    #expect(rowBefore.status == .reserved)
    #expect(rowBefore.reservationID == reservation.id.uuidString.lowercased())
    #expect(rowBefore.leaseDeadline == reservation.leaseDeadline)
    let generationBefore = documentBefore.bindingGenerations

    let error: AgentEventDeliveryLedgerError? = await ledgerError {
      _ = try settle(reservation, outcome: .transportFailure, in: store)
    }
    #expect(error == .invalidInput)
    #expect(try Data(contentsOf: fileURL) == before)
    let documentAfter = try JSONDecoder().decode(
      AgentEventDeliveryLedgerDocument.self,
      from: Data(contentsOf: fileURL)
    )
    #expect(documentAfter == documentBefore)
    #expect(documentAfter.bindingGenerations == generationBefore)
    #expect(documentAfter.records.first?.status == .reserved)
    #expect(documentAfter.records.first?.reservationID == reservation.id.uuidString.lowercased())
    #expect(documentAfter.records.first?.leaseDeadline == reservation.leaseDeadline)
    #expect(documentAfter.records.first?.nextEligibleAt == nil)
    #expect(documentAfter.records.first?.failureCategory == nil)
  }

  @Test func roundedLeaseRecoveryRetryRejectsUnderFloorWithoutWriting() async throws {
    let now = Date(timeIntervalSince1970: 1e16)
    let candidate = directCandidate(
      profile: stableUUID(101),
      subscription: 101,
      event: 101,
      eventTimestamp: now,
      subscriptionExpiresAt: now.addingTimeInterval(604_800)
    )
    let previousHighWater = now.addingTimeInterval(-60)
    let record = AgentEventDeliveryLedgerRecord(
      binding: candidate.binding,
      bindingGenerationID: stableUUID(90_801).uuidString.lowercased(),
      eventID: candidate.eventID,
      sourcePosition: candidate.sourcePosition,
      expiresAt: try #require(candidate.expiresAt),
      attemptCount: 1,
      status: .reserved,
      reservationID: stableUUID(90_802).uuidString.lowercased(),
      leaseDeadline: now.addingTimeInterval(-30),
      nextEligibleAt: nil,
      httpStatus: nil,
      failureCategory: nil
    )
    let document = ledgerDocument(records: [record], lastObservedAt: previousHighWater)
    let rootFixture = try LedgerFixture.makeRoot()
    let root = rootFixture.url
    defer { cleanupLedgerFixtureRoot(rootFixture) }
    let fileURL = root.appendingPathComponent("event-delivery-ledger.json")
    try write(document, to: fileURL)
    let before = try Data(contentsOf: fileURL)
    let store = AgentEventDeliveryLedgerStore(
      fileURL: fileURL,
      now: { now },
      jitterBasisPoints: { 0 }
    )

    let error: AgentEventDeliveryLedgerError? = await ledgerError {
      _ = try reserve(candidate, in: store)
    }
    #expect(error == .invalidInput)
    #expect(try Data(contentsOf: fileURL) == before)
    let documentAfter = try JSONDecoder().decode(
      AgentEventDeliveryLedgerDocument.self,
      from: Data(contentsOf: fileURL)
    )
    #expect(documentAfter == document)
    #expect(documentAfter.records.first?.status == .reserved)
    #expect(documentAfter.records.first?.leaseDeadline == record.leaseDeadline)
    #expect(documentAfter.records.first?.nextEligibleAt == nil)
    #expect(documentAfter.records.first?.failureCategory == nil)
  }

  @Test func fractionalClockJitterAndRetryAfterRespectRetryFloors() async throws {
    let start = Date(timeIntervalSince1970: 1_800_000_000.123456)
    let candidate = directCandidate(
      profile: stableUUID(100),
      subscription: 100,
      event: 100,
      eventTimestamp: start,
      subscriptionExpiresAt: start.addingTimeInterval(100_000)
    )
    let rootFixture = try LedgerFixture.makeRoot()
    let root = rootFixture.url
    defer { cleanupLedgerFixtureRoot(rootFixture) }
    let fileURL = root.appendingPathComponent("event-delivery-ledger.json")
    let clock = LedgerTestClock(date: start)
    let store = AgentEventDeliveryLedgerStore(
      fileURL: fileURL,
      now: { clock.now() },
      jitterBasisPoints: { 1 }
    )
    guard case .reserved(let first) = try reserve(candidate, in: store) else {
      Issue.record("The fractional-clock candidate should reserve.")
      return
    }
    let jittered = try settle(first, outcome: .transportFailure, in: store)
    let jitteredDeadline = try #require(jittered.nextEligibleAt)
    let jitteredInterval = jitteredDeadline.timeIntervalSince(start)
    #expect(jitteredInterval >= 5)
    #expect(jitteredInterval < 6)
    clock.set(jitteredDeadline)

    guard case .reserved(let second) = try reserve(candidate, in: store) else {
      Issue.record("The fractional jitter deadline should become eligible.")
      return
    }
    let retryAfterStart = clock.now()
    let retryAfter = try settle(
      second,
      outcome: .httpStatus(503, retryAfter: 20.25),
      in: store
    )
    let retryAfterDeadline = try #require(retryAfter.nextEligibleAt)
    let retryAfterInterval = retryAfterDeadline.timeIntervalSince(retryAfterStart)
    #expect(retryAfter.status == .retryWaiting)
    #expect(retryAfter.attemptCount == 2)
    #expect(retryAfter.failureCategory == .retryableHTTP)
    #expect(retryAfter.httpStatus == 503)
    #expect(retryAfterInterval >= 20.25)
    #expect(retryAfterInterval <= 900)
  }

  @Test func failedAdmissionDoesNotPersistHighWaterOrCleanup() async throws {
    let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
    let cleanupStatuses: [AgentEventDeliveryLedgerRecordStatus] = [
      .retryWaiting, .paused, .reserved,
    ]
    for status in cleanupStatuses {
      let rootFixture = try LedgerFixture.makeRoot()
      let root = rootFixture.url
      defer { cleanupLedgerFixtureRoot(rootFixture) }
      let fileURL = root.appendingPathComponent("event-delivery-ledger.json")
      var rows = capacityDocument(totalRecords: 4_096).records
      var cleanupRow = try #require(rows.first)
      cleanupRow.status = status
      cleanupRow.reservationID =
        status == .reserved
        ? stableUUID(90_500).uuidString.lowercased()
        : nil
      cleanupRow.leaseDeadline = status == .reserved ? baseDate.addingTimeInterval(30) : nil
      cleanupRow.nextEligibleAt =
        status == .retryWaiting
        ? baseDate.addingTimeInterval(5)
        : nil
      cleanupRow.httpStatus = status == .retryWaiting ? 503 : status == .paused ? 400 : nil
      cleanupRow.failureCategory =
        switch status {
        case .retryWaiting: .retryableHTTP
        case .paused: .pausedHTTP
        case .reserved: nil
        case .receipt, .terminal, .expired, .exhausted, .superseded: nil
        }
      rows[0] = cleanupRow
      let fullDocument = ledgerDocument(
        records: rows,
        lastObservedAt: baseDate
      )
      try write(fullDocument, to: fileURL)
      let before = try Data(contentsOf: fileURL)
      let candidate = directCandidate(
        profile: cleanupRow.binding.profileID,
        subscription: 1,
        event: 99_999,
        revision: 2,
        eventTimestamp: baseDate,
        subscriptionExpiresAt: baseDate.addingTimeInterval(604_800)
      )
      let store = AgentEventDeliveryLedgerStore(
        fileURL: fileURL,
        now: { baseDate.addingTimeInterval(50) },
        jitterBasisPoints: { 0 }
      )
      let error: AgentEventDeliveryLedgerError? = await ledgerError {
        try reserve(candidate, in: store)
      }
      #expect(error == .capacityExceeded, "cleanup status \(status)")
      #expect(try Data(contentsOf: fileURL) == before, "unchanged after \(status) admission")
    }

    let clockRootFixture = try LedgerFixture.makeRoot()
    let clockRoot = clockRootFixture.url
    defer { cleanupLedgerFixtureRoot(clockRootFixture) }
    let clockURL = clockRoot.appendingPathComponent("event-delivery-ledger.json")
    let fullDocument = capacityDocument(totalRecords: 4_096)
    try write(fullDocument, to: clockURL)
    let beforeClockFailure = try Data(contentsOf: clockURL)
    let clockStore = AgentEventDeliveryLedgerStore(
      fileURL: clockURL,
      now: { baseDate.addingTimeInterval(1) },
      jitterBasisPoints: { 0 }
    )
    let clockCapacityError: AgentEventDeliveryLedgerError? = await ledgerError {
      try reserve(
        directCandidate(profile: stableUUID(50_000), subscription: 9, event: 9),
        in: clockStore
      )
    }
    #expect(clockCapacityError == .capacityExceeded)
    #expect(try Data(contentsOf: clockURL) == beforeClockFailure)

    let sourceRootFixture = try LedgerFixture.makeRoot()
    let sourceRoot = sourceRootFixture.url
    defer { cleanupLedgerFixtureRoot(sourceRootFixture) }
    let sourceURL = sourceRoot.appendingPathComponent("event-delivery-ledger.json")
    let existingCandidate = directCandidate(
      profile: stableUUID(50_001), subscription: 10, event: 10)
    let existingRecord = AgentEventDeliveryLedgerRecord(
      binding: existingCandidate.binding,
      bindingGenerationID: stableUUID(90_501).uuidString.lowercased(),
      eventID: existingCandidate.eventID,
      sourcePosition: existingCandidate.sourcePosition,
      expiresAt: try #require(existingCandidate.expiresAt),
      attemptCount: 1,
      status: .receipt,
      reservationID: nil,
      leaseDeadline: nil,
      nextEligibleAt: nil,
      httpStatus: 204,
      failureCategory: nil
    )
    let sourceDocument = ledgerDocument(
      records: [existingRecord],
      lastObservedAt: baseDate
    )
    try write(sourceDocument, to: sourceURL)
    let beforeSourceFailure = try Data(contentsOf: sourceURL)
    let wrongPosition = AgentEventDeliveryLedgerCandidate(
      binding: existingCandidate.binding,
      eventID: existingCandidate.eventID,
      sourcePosition: AgentEventOutboxPosition(
        epoch: existingCandidate.sourcePosition.epoch,
        sequence: existingCandidate.sourcePosition.sequence + 1
      ),
      eventTimestamp: existingCandidate.eventTimestamp,
      subscriptionExpiresAt: existingCandidate.subscriptionExpiresAt
    )
    let sourceStore = AgentEventDeliveryLedgerStore(
      fileURL: sourceURL,
      now: { baseDate.addingTimeInterval(1) },
      jitterBasisPoints: { 0 }
    )
    let sourceError: AgentEventDeliveryLedgerError? = await ledgerError {
      try reserve(wrongPosition, in: sourceStore)
    }
    #expect(sourceError == .sourceChanged)
    #expect(try Data(contentsOf: sourceURL) == beforeSourceFailure)

    let jitterRootFixture = try LedgerFixture.makeRoot()
    let jitterRoot = jitterRootFixture.url
    defer { cleanupLedgerFixtureRoot(jitterRootFixture) }
    let jitterURL = jitterRoot.appendingPathComponent("event-delivery-ledger.json")
    let jitterCandidate = directCandidate(
      profile: stableUUID(50_002), subscription: 11, event: 11)
    let jitterGenerationID = stableUUID(90_502).uuidString.lowercased()
    let expiredLease = AgentEventDeliveryLedgerRecord(
      binding: jitterCandidate.binding,
      bindingGenerationID: jitterGenerationID,
      eventID: jitterCandidate.eventID,
      sourcePosition: jitterCandidate.sourcePosition,
      expiresAt: try #require(jitterCandidate.expiresAt),
      attemptCount: 1,
      status: .reserved,
      reservationID: stableUUID(90_503).uuidString.lowercased(),
      leaseDeadline: baseDate.addingTimeInterval(30),
      nextEligibleAt: nil,
      httpStatus: nil,
      failureCategory: nil
    )
    try write(
      ledgerDocument(records: [expiredLease], lastObservedAt: baseDate),
      to: jitterURL
    )
    let beforeJitterFailure = try Data(contentsOf: jitterURL)
    let jitterStore = AgentEventDeliveryLedgerStore(
      fileURL: jitterURL,
      now: { baseDate.addingTimeInterval(31) },
      jitterBasisPoints: { 2_001 }
    )
    let jitterError: AgentEventDeliveryLedgerError? = await ledgerError {
      try reserve(jitterCandidate, in: jitterStore)
    }
    #expect(jitterError == .invalidInput)
    #expect(try Data(contentsOf: jitterURL) == beforeJitterFailure)
  }

  @Test func refreshedBindingDoesNotInheritReceiptOrKeepAStaleLiveSlot() async throws {
    let fixture = try await LedgerFixture.make()
    defer { fixture.remove() }
    let oldService = fixture.service()
    let oldReservation = try #require(
      try await oldService.reserveNext(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID
      )
    )
    let refreshed = try await fixture.refreshSubscription()
    let newService = fixture.service()
    #expect(
      try await newService.reserveNext(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID
      ) == nil
    )

    fixture.clock.set(fixture.baseDate.addingTimeInterval(31))
    let newReservation = try #require(
      try await newService.reserveNext(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID
      )
    )
    #expect(newReservation.attemptCount == 1)
    #expect(newReservation.id != oldReservation.id)
    #expect(newReservation.binding.subscriptionRevision == refreshed.revision)

    let oldOutcome: AgentEventDeliveryLedgerError? = await ledgerError {
      _ = try await oldService.settle(
        oldReservation,
        outcome: .httpStatus(204, retryAfter: nil)
      )
    }
    #expect(oldOutcome == .staleReservation)
    let document = try fixture.readLedger()
    #expect(document.records.count == 2)
    #expect(
      document.records.contains(where: {
        $0.binding.subscriptionRevision == 1 && $0.status == .superseded
      }))
    #expect(
      document.records.contains(where: {
        $0.binding.subscriptionRevision == refreshed.revision && $0.status == .reserved
      }))
  }

  @Test func refreshedBindingWithoutMatchingPendingProgressCannotReserve() async throws {
    let fixture = try await LedgerFixture.make()
    defer { fixture.remove() }

    let refreshed = try await fixture.refreshSubscription(updateProgress: false)
    #expect(refreshed.revision == 2)
    #expect(
      try await fixture.service().reserveNext(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID
      ) == nil
    )
    #expect(!FileManager.default.fileExists(atPath: fixture.ledgerURL.path))
  }

  @Test func noncanonicalStagedOutboxBodyCannotCreateAnAttempt() async throws {
    let fixture = try await LedgerFixture.make()
    defer { fixture.remove() }

    var document = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: fixture.outboxURL)) as? [String: Any]
    )
    var entries = try #require(document["entries"] as? [[String: Any]])
    var noncanonicalBody = fixture.bodies[0]
    noncanonicalBody.append(0x20)
    entries[0]["body"] = noncanonicalBody.base64EncodedString()
    document["entries"] = entries
    let invalidOutbox = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
    try invalidOutbox.write(to: fixture.outboxURL, options: .atomic)

    var caughtError: Error?
    do {
      _ = try await fixture.service().reserveNext(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID
      )
    } catch let error {
      caughtError = error
    }
    #expect(caughtError as? AgentEventOutboxError == .storageFailure)
    #expect(!FileManager.default.fileExists(atPath: fixture.ledgerURL.path))
  }

  @Test func outboxMutationDuringFinalSubscriptionAwaitRejectsReserveObserveAndSettle()
    async throws
  {
    let reserveFixture = try await LedgerFixture.make()
    defer { reserveFixture.remove() }
    let reserveGate = LedgerSubscriptionReadGate()
    let reserveSubscriptionStore = reserveFixture.subscriptionStore
    let reserveService = reserveFixture.service(subscriptionRead: { id in
      try await reserveGate.read(subscriptionStore: reserveSubscriptionStore, id: id)
    })
    let reserveTask = Task {
      try await reserveService.reserveNext(
        profileID: reserveFixture.profileID,
        subscriptionID: reserveFixture.subscriptionID
      )
    }
    await reserveGate.waitForFinalRead()
    try markStagedEntryNotDelivered(in: reserveFixture)
    await reserveGate.releaseFinalRead()
    let reserveError: AgentEventDeliveryLedgerError? = await ledgerError {
      try await reserveTask.value
    }
    #expect(reserveError == .sourceChanged)
    #expect(!FileManager.default.fileExists(atPath: reserveFixture.ledgerURL.path))

    let observeFixture = try await LedgerFixture.make()
    defer { observeFixture.remove() }
    let reservation = try #require(
      try await observeFixture.service().reserveNext(
        profileID: observeFixture.profileID,
        subscriptionID: observeFixture.subscriptionID
      )
    )
    let observeGate = LedgerSubscriptionReadGate()
    let observeSubscriptionStore = observeFixture.subscriptionStore
    let observeService = observeFixture.service(subscriptionRead: { id in
      try await observeGate.read(subscriptionStore: observeSubscriptionStore, id: id)
    })
    let observeTask = Task { try await observeService.observe(reservation) }
    await observeGate.waitForFinalRead()
    try markStagedEntryNotDelivered(in: observeFixture)
    await observeGate.releaseFinalRead()
    let observeError: AgentEventDeliveryLedgerError? = await ledgerError {
      try await observeTask.value
    }
    #expect(observeError == .sourceChanged)
    #expect(try observeFixture.readLedger().records.first?.status == .reserved)

    let settleFixture = try await LedgerFixture.make()
    defer { settleFixture.remove() }
    let settleReservation = try #require(
      try await settleFixture.service().reserveNext(
        profileID: settleFixture.profileID,
        subscriptionID: settleFixture.subscriptionID
      )
    )
    let settleGate = LedgerSubscriptionReadGate()
    let settleSubscriptionStore = settleFixture.subscriptionStore
    let settleService = settleFixture.service(subscriptionRead: { id in
      try await settleGate.read(subscriptionStore: settleSubscriptionStore, id: id)
    })
    let settleTask = Task {
      try await settleService.settle(
        settleReservation,
        outcome: .httpStatus(204, retryAfter: nil)
      )
    }
    await settleGate.waitForFinalRead()
    try markStagedEntryNotDelivered(in: settleFixture)
    await settleGate.releaseFinalRead()
    let settleError: AgentEventDeliveryLedgerError? = await ledgerError {
      try await settleTask.value
    }
    #expect(settleError == .sourceChanged)
    #expect(try settleFixture.readLedger().records.first?.status == .reserved)
  }

  @Test func aReceiptIsScopedToItsBindingAndRefreshStartsASeparateAttempt() async throws {
    let fixture = try await LedgerFixture.make()
    defer { fixture.remove() }
    let originalService = fixture.service()
    let original = try #require(
      try await originalService.reserveNext(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID
      )
    )
    _ = try await originalService.settle(original, outcome: .httpStatus(201, retryAfter: nil))
    let refreshed = try await fixture.refreshSubscription()

    let fresh = try #require(
      try await fixture.service().reserveNext(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID
      )
    )
    #expect(fresh.eventID == original.eventID)
    #expect(fresh.sourcePosition == original.sourcePosition)
    #expect(fresh.attemptCount == 1)
    #expect(fresh.binding.subscriptionRevision == refreshed.revision)
    let records = try fixture.readLedger().records
    #expect(records.count == 2)
    #expect(records.filter { $0.status == .receipt }.count == 1)
    #expect(records.filter { $0.status == .reserved }.count == 1)
  }

  @Test func reportedOutcomesUseBoundedRetryTerminalReceiptAndPauseStates() async throws {
    let cases: [(AgentEventDeliveryLedgerOutcome, AgentEventDeliveryLedgerRecordStatus)] = [
      (.transportFailure, .retryWaiting),
      (.cancelled, .retryWaiting),
      (.httpStatus(408, retryAfter: nil), .retryWaiting),
      (.httpStatus(429, retryAfter: nil), .retryWaiting),
      (.httpStatus(500, retryAfter: nil), .retryWaiting),
      (.httpStatus(599, retryAfter: nil), .retryWaiting),
      (.httpStatus(200, retryAfter: nil), .receipt),
      (.httpStatus(299, retryAfter: nil), .receipt),
      (.httpStatus(410, retryAfter: nil), .terminal),
      (.httpStatus(413, retryAfter: nil), .terminal),
      (.httpStatus(302, retryAfter: nil), .paused),
      (.httpStatus(400, retryAfter: nil), .paused),
    ]

    for (index, outcome) in cases.enumerated() {
      let fixture = try await LedgerFixture.make()
      defer { fixture.remove() }
      let service = fixture.service()
      let reservation = try #require(
        try await service.reserveNext(
          profileID: fixture.profileID,
          subscriptionID: fixture.subscriptionID
        )
      )
      let settled = try await service.settle(reservation, outcome: outcome.0)
      #expect(settled.status == outcome.1, "outcome case \(index)")
      if case .httpStatus(let status, _) = outcome.0 {
        #expect(settled.httpStatus == status)
      }
      if outcome.1 == .receipt {
        #expect(settled.failureCategory == nil)
      }
    }

    let invalidFixture = try await LedgerFixture.make()
    defer { invalidFixture.remove() }
    let invalidService = invalidFixture.service()
    let reservation = try #require(
      try await invalidService.reserveNext(
        profileID: invalidFixture.profileID,
        subscriptionID: invalidFixture.subscriptionID
      )
    )
    let invalidStatus: AgentEventDeliveryLedgerError? = await ledgerError {
      _ = try await invalidService.settle(
        reservation,
        outcome: .httpStatus(600, retryAfter: nil)
      )
    }
    #expect(invalidStatus == .invalidInput)
    #expect(try invalidFixture.readLedger().records.first?.status == .reserved)
  }

  @Test func retryAfterAndJitterRespectFloorsCapsExpiryAndAttemptExhaustion() async throws {
    let fixture = try await LedgerFixture.make(entryCount: 2)
    defer { fixture.remove() }
    let service = fixture.service(jitterBasisPoints: 2_000)
    let first = try #require(
      try await service.reserveNext(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID
      )
    )
    let firstFailure = try await service.settle(first, outcome: .transportFailure)
    #expect(firstFailure.nextEligibleAt?.timeIntervalSince(fixture.baseDate) == 6)
    fixture.clock.set(fixture.baseDate.addingTimeInterval(5.9))
    #expect(
      try await service.reserveNext(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID
      ) == nil
    )
    fixture.clock.set(fixture.baseDate.addingTimeInterval(6))
    let second = try #require(
      try await service.reserveNext(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID
      )
    )
    #expect(second.attemptCount == 2)
    let retryAfterStart = fixture.clock.now()
    let secondFailure = try await service.settle(
      second,
      outcome: .httpStatus(429, retryAfter: 20)
    )
    #expect(secondFailure.nextEligibleAt?.timeIntervalSince(retryAfterStart) == 20)

    let invalidRetryAfterValues: [TimeInterval] = [-1, 901, .infinity, .nan]
    let eventIDContainingRetryAfterDigits = "90100000-0000-4000-8000-000000000001"
    let allowedDocumentKeys: Set<String> = [
      "schemaVersion", "records", "bindingGenerations", "lastObservedAt",
    ]
    let allowedRecordKeys: Set<String> = [
      "binding", "bindingGenerationID", "eventID", "sourcePosition", "expiresAt",
      "attemptCount", "status", "reservationID", "leaseDeadline", "nextEligibleAt",
      "httpStatus", "failureCategory",
    ]
    for (index, retryAfter) in invalidRetryAfterValues.enumerated() {
      let badFixture = try await LedgerFixture.make(
        eventIDs: [eventIDContainingRetryAfterDigits])
      defer { badFixture.remove() }
      let badService = badFixture.service(jitterBasisPoints: 0)
      let reservation = try #require(
        try await badService.reserveNext(
          profileID: badFixture.profileID,
          subscriptionID: badFixture.subscriptionID
        )
      )
      let settled = try await badService.settle(
        reservation,
        outcome: .httpStatus(429, retryAfter: retryAfter)
      )
      #expect(
        settled.nextEligibleAt?.timeIntervalSince(badFixture.baseDate) == 5,
        "retry-after case \(index)")
      let persistedData = try Data(contentsOf: badFixture.ledgerURL)
      let persistedJSON = try #require(
        JSONSerialization.jsonObject(with: persistedData) as? [String: Any])
      #expect(Set(persistedJSON.keys) == allowedDocumentKeys)
      let persistedRows = try #require(persistedJSON["records"] as? [[String: Any]])
      #expect(persistedRows.count == 1)
      let persistedRow = try #require(persistedRows.first)
      #expect(Set(persistedRow.keys) == allowedRecordKeys)
      #expect(!persistedRow.keys.contains("retryAfter"))

      let document = try badFixture.readLedger()
      #expect(document.schemaVersion == 2)
      #expect(document.records.count == 1)
      let record = try #require(document.records.first)
      #expect(record.eventID == eventIDContainingRetryAfterDigits)
      #expect(record.eventID.contains("901"))
      #expect(record.attemptCount == 1)
      #expect(record.status == .retryWaiting)
      #expect(record.failureCategory == .retryableHTTP)
      #expect(record.httpStatus == 429)
      #expect(record.reservationID == nil)
      #expect(record.leaseDeadline == nil)
      #expect(record.nextEligibleAt?.timeIntervalSince(badFixture.baseDate) == 5)
    }

    let invalidJitterFixture = try await LedgerFixture.make()
    defer { invalidJitterFixture.remove() }
    let invalidJitterService = invalidJitterFixture.service(jitterBasisPoints: 2_001)
    let invalidJitterReservation = try #require(
      try await invalidJitterService.reserveNext(
        profileID: invalidJitterFixture.profileID,
        subscriptionID: invalidJitterFixture.subscriptionID
      )
    )
    let invalidJitterError: AgentEventDeliveryLedgerError? = await ledgerError {
      _ = try await invalidJitterService.settle(
        invalidJitterReservation,
        outcome: .transportFailure
      )
    }
    #expect(invalidJitterError == .invalidInput)
    #expect(try invalidJitterFixture.readLedger().records.first?.status == .reserved)

    let expiryFixture = try await LedgerFixture.make(subscriptionLifetime: 60)
    defer { expiryFixture.remove() }
    let expiryService = expiryFixture.service(jitterBasisPoints: 0)
    let expiryReservation = try #require(
      try await expiryService.reserveNext(
        profileID: expiryFixture.profileID,
        subscriptionID: expiryFixture.subscriptionID
      )
    )
    let expiryRetry = try await expiryService.settle(
      expiryReservation,
      outcome: .httpStatus(429, retryAfter: 900)
    )
    #expect(expiryRetry.status == .expired)
    #expect(expiryRetry.nextEligibleAt == nil)
    #expect(expiryRetry.failureCategory == .retentionExpired)

    let cappedFixture = try await LedgerFixture.make()
    defer { cappedFixture.remove() }
    let cappedService = cappedFixture.service(jitterBasisPoints: 0)
    var active = try #require(
      try await cappedService.reserveNext(
        profileID: cappedFixture.profileID,
        subscriptionID: cappedFixture.subscriptionID
      )
    )
    for attempt in 1...9 {
      let start = cappedFixture.clock.now()
      let failed = try await cappedService.settle(active, outcome: .transportFailure)
      #expect(failed.attemptCount == UInt64(attempt))
      let expectedDelay = min(900.0, 5.0 * pow(2.0, Double(attempt - 1)))
      #expect(failed.nextEligibleAt?.timeIntervalSince(start) == expectedDelay)
      cappedFixture.clock.set(try #require(failed.nextEligibleAt))
      if attempt < 9 {
        active = try #require(
          try await cappedService.reserveNext(
            profileID: cappedFixture.profileID,
            subscriptionID: cappedFixture.subscriptionID
          )
        )
      }
    }

    let exhaustionFixture = try await LedgerFixture.make()
    defer { exhaustionFixture.remove() }
    let exhaustionService = exhaustionFixture.service(jitterBasisPoints: 0)
    var reservation = try #require(
      try await exhaustionService.reserveNext(
        profileID: exhaustionFixture.profileID,
        subscriptionID: exhaustionFixture.subscriptionID
      )
    )
    for attempt in 1...12 {
      let record = try await exhaustionService.settle(
        reservation,
        outcome: .httpStatus(503, retryAfter: 900)
      )
      #expect(record.attemptCount == UInt64(attempt))
      if attempt < 12 {
        let nextEligibleAt = try #require(record.nextEligibleAt)
        exhaustionFixture.clock.set(nextEligibleAt)
        reservation = try #require(
          try await exhaustionService.reserveNext(
            profileID: exhaustionFixture.profileID,
            subscriptionID: exhaustionFixture.subscriptionID
          )
        )
      } else {
        #expect(record.status == .exhausted)
        #expect(record.nextEligibleAt == nil)
      }
    }
    #expect(
      try await exhaustionService.reserveNext(
        profileID: exhaustionFixture.profileID,
        subscriptionID: exhaustionFixture.subscriptionID
      ) == nil
    )
  }

  @Test func genuineClockRollbackPreservesHighWaterButOlderEventTimeDoesNotRollback()
    async throws
  {
    let fixture = try await LedgerFixture.make(eventAges: [0, 60])
    defer { fixture.remove() }
    let service = fixture.service()
    let first = try #require(
      try await service.reserveNext(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID
      )
    )
    fixture.clock.set(fixture.baseDate.addingTimeInterval(10))
    _ = try await service.settle(first, outcome: .httpStatus(204, retryAfter: nil))
    let highWaterBytes = try Data(contentsOf: fixture.ledgerURL)

    fixture.clock.set(fixture.baseDate.addingTimeInterval(5))
    let rollback: AgentEventDeliveryLedgerError? = await ledgerError {
      _ = try await service.reserveNext(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID
      )
    }
    #expect(rollback == .clockRollback)
    #expect(try Data(contentsOf: fixture.ledgerURL) == highWaterBytes)

    fixture.clock.set(fixture.baseDate.addingTimeInterval(10))
    let second = try #require(
      try await service.reserveNext(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID
      )
    )
    #expect(second.eventID == fixture.eventIDs[1])
    #expect(second.sourcePosition == fixture.positions[1])
  }

  @Test func injectedClockIsSampledInsideTheSharedTransactionLock() async throws {
    let rootFixture = try LedgerFixture.makeRoot()
    let root = rootFixture.url
    defer { cleanupLedgerFixtureRoot(rootFixture) }
    let fileURL = root.appendingPathComponent("event-delivery-ledger.json")
    let gate = LedgerGateClock(base: Date(timeIntervalSince1970: 1_800_000_000))
    let storeA = AgentEventDeliveryLedgerStore(fileURL: fileURL, now: { gate.now() })
    let storeB = AgentEventDeliveryLedgerStore(fileURL: fileURL, now: { gate.now() })
    let candidateA = directCandidate(profile: stableUUID(1), subscription: 1, event: 1)
    let candidateB = directCandidate(profile: stableUUID(2), subscription: 2, event: 2)

    let taskA = Task.detached { try reserve(candidateA, in: storeA) }
    #expect(gate.waitForFirstCall())
    let taskB = Task.detached { try reserve(candidateB, in: storeB) }
    #expect(!gate.secondCallArrived(timeout: .now() + 0.05))
    gate.releaseFirstCall()
    let decisionA = try await taskA.value
    let decisionB = try await taskB.value
    guard case .reserved = decisionA, case .reserved = decisionB else {
      Issue.record("Both independent candidates should reserve after lock-ordered clock reads.")
      return
    }
    #expect(gate.callCount == 2)
  }

  @Test func eventRetentionAndSubscriptionExpiryBoundEveryReservation() async throws {
    let expiredEvent = try await LedgerFixture.make(eventAges: [604_801])
    defer { expiredEvent.remove() }
    #expect(
      try await expiredEvent.service().reserveNext(
        profileID: expiredEvent.profileID,
        subscriptionID: expiredEvent.subscriptionID
      ) == nil
    )

    let shortSubscription = try await LedgerFixture.make(subscriptionLifetime: 60)
    defer { shortSubscription.remove() }
    let service = shortSubscription.service()
    let reservation = try #require(
      try await service.reserveNext(
        profileID: shortSubscription.profileID,
        subscriptionID: shortSubscription.subscriptionID
      )
    )
    #expect(reservation.expiresAt == shortSubscription.baseDate.addingTimeInterval(60))
    #expect(reservation.leaseDeadline <= reservation.expiresAt)
    shortSubscription.clock.set(shortSubscription.baseDate.addingTimeInterval(60))
    #expect(
      try await service.reserveNext(
        profileID: shortSubscription.profileID,
        subscriptionID: shortSubscription.subscriptionID
      ) == nil
    )
    #expect(try shortSubscription.readLedger().records.first?.status == .expired)

    let arithmeticFixture = try await LedgerFixture.make()
    defer { arithmeticFixture.remove() }
    let huge = Date(timeIntervalSince1970: 1e300)
    let arithmeticError: AgentEventDeliveryLedgerError? = await ledgerError {
      _ = try reserve(
        AgentEventDeliveryLedgerCandidate(
          binding: arithmeticFixture.binding,
          eventID: arithmeticFixture.eventIDs[0],
          sourcePosition: arithmeticFixture.positions[0],
          eventTimestamp: huge,
          subscriptionExpiresAt: huge
        ),
        in: arithmeticFixture.store()
      )
    }
    #expect(arithmeticError == .invalidInput)

    let maximumSequenceCandidate = AgentEventDeliveryLedgerCandidate(
      binding: arithmeticFixture.binding,
      eventID: arithmeticFixture.eventIDs[0],
      sourcePosition: AgentEventOutboxPosition(
        epoch: arithmeticFixture.positions[0].epoch,
        sequence: UInt64.max
      ),
      eventTimestamp: arithmeticFixture.baseDate,
      subscriptionExpiresAt: arithmeticFixture.baseDate.addingTimeInterval(60_000)
    )
    let sequenceError: AgentEventDeliveryLedgerError? = await ledgerError {
      try reserve(maximumSequenceCandidate, in: arithmeticFixture.store())
    }
    #expect(sequenceError == .invalidInput)
    #expect(!FileManager.default.fileExists(atPath: arithmeticFixture.ledgerURL.path))
  }

  @Test func persistedCapacityBoundsRejectWithoutEvictionAndCorruptionFailsClosed()
    async throws
  {
    let scenarios: [(String, AgentEventDeliveryLedgerDocument, AgentEventDeliveryLedgerCandidate)] =
      [
        (
          "subscription", capacityDocument(recordsPerSubscription: 256),
          directCandidate(profile: stableUUID(10_000), subscription: 1, event: 257)
        ),
        (
          "profile", capacityDocument(recordsPerProfile: 512),
          directCandidate(profile: stableUUID(10_000), subscription: 3, event: 900)
        ),
        (
          "bindings", capacityDocument(bindingCount: 128),
          directCandidate(profile: stableUUID(999), subscription: 999, event: 900)
        ),
        (
          "total", capacityDocument(totalRecords: 4_096),
          directCandidate(profile: stableUUID(1), subscription: 1, event: 9_000)
        ),
      ]

    for (label, document, candidate) in scenarios {
      let rootFixture = try LedgerFixture.makeRoot()
      let root = rootFixture.url
      defer { cleanupLedgerFixtureRoot(rootFixture) }
      let fileURL = root.appendingPathComponent("event-delivery-ledger.json")
      try write(document, to: fileURL)
      let before = try Data(contentsOf: fileURL)
      let store = AgentEventDeliveryLedgerStore(
        fileURL: fileURL,
        now: { document.lastObservedAt }
      )
      let error: AgentEventDeliveryLedgerError? = await ledgerError {
        _ = try reserve(candidate, in: store)
      }
      #expect(error == .capacityExceeded, "capacity \(label)")
      #expect(try Data(contentsOf: fileURL) == before, "capacity \(label) did not evict or rewrite")
    }

    let corruptFixture = try await LedgerFixture.make()
    defer { corruptFixture.remove() }
    let validReservation = try #require(
      try await corruptFixture.service().reserveNext(
        profileID: corruptFixture.profileID,
        subscriptionID: corruptFixture.subscriptionID
      )
    )
    let validBytes = try Data(contentsOf: corruptFixture.ledgerURL)
    let validDocument = try JSONDecoder().decode(
      AgentEventDeliveryLedgerDocument.self,
      from: validBytes
    )
    let record = try #require(validDocument.records.first)
    let otherIdentity = directCandidate(
      profile: stableUUID(90_004), subscription: 90_004, event: 90_005)
    func reservedRecord(
      binding: AgentEventCallbackVerificationBinding? = nil,
      eventID: String? = nil,
      sourcePosition: AgentEventOutboxPosition? = nil,
      attemptCount: UInt64? = nil,
      reservationID: String? = nil,
      leaseDeadline: Date? = nil,
      bindingGenerationID: String? = nil
    ) -> AgentEventDeliveryLedgerRecord {
      let selectedBinding = binding ?? record.binding
      return AgentEventDeliveryLedgerRecord(
        binding: selectedBinding,
        bindingGenerationID: bindingGenerationID ?? record.bindingGenerationID,
        eventID: eventID ?? record.eventID,
        sourcePosition: sourcePosition ?? record.sourcePosition,
        expiresAt: record.expiresAt,
        attemptCount: attemptCount ?? record.attemptCount,
        status: .reserved,
        reservationID: reservationID ?? record.reservationID,
        leaseDeadline: leaseDeadline ?? record.leaseDeadline,
        nextEligibleAt: nil,
        httpStatus: nil,
        failureCategory: nil
      )
    }
    let nextReservationID = stableUUID(90_001).uuidString.lowercased()
    let nextPosition = AgentEventOutboxPosition(
      epoch: record.sourcePosition.epoch,
      sequence: record.sourcePosition.sequence + 1
    )
    let corruptDocuments: [(String, AgentEventDeliveryLedgerDocument)] = [
      (
        "schema version",
        ledgerDocument(
          schemaVersion: 1,
          records: [record],
          lastObservedAt: validDocument.lastObservedAt
        )
      ),
      (
        "attempt count",
        ledgerDocument(
          records: [reservedRecord(attemptCount: 13)],
          lastObservedAt: validDocument.lastObservedAt
        )
      ),
      (
        "lease deadline",
        ledgerDocument(
          records: [reservedRecord(leaseDeadline: Date(timeIntervalSince1970: 1e300))],
          lastObservedAt: validDocument.lastObservedAt
        )
      ),
      (
        "duplicate event",
        ledgerDocument(
          records: [
            record,
            reservedRecord(
              sourcePosition: nextPosition,
              reservationID: nextReservationID,
              bindingGenerationID: record.bindingGenerationID
            ),
          ],
          lastObservedAt: validDocument.lastObservedAt
        )
      ),
      (
        "duplicate position",
        ledgerDocument(
          records: [
            record,
            reservedRecord(
              eventID: stableUUID(90_002).uuidString.lowercased(),
              reservationID: stableUUID(90_003).uuidString.lowercased(),
              bindingGenerationID: record.bindingGenerationID
            ),
          ],
          lastObservedAt: validDocument.lastObservedAt
        )
      ),
      (
        "duplicate reservation id",
        ledgerDocument(
          records: [
            record,
            reservedRecord(
              binding: otherIdentity.binding,
              eventID: otherIdentity.eventID,
              sourcePosition: otherIdentity.sourcePosition,
              bindingGenerationID: stableUUID(90_006).uuidString.lowercased()
            ),
          ],
          lastObservedAt: validDocument.lastObservedAt
        )
      ),
    ]
    for (label, document) in corruptDocuments {
      try write(document, to: corruptFixture.ledgerURL)
      let bytes = try Data(contentsOf: corruptFixture.ledgerURL)
      let malformed: AgentEventDeliveryLedgerError? = await ledgerError {
        try observe(validReservation, in: corruptFixture.store())
      }
      #expect(malformed == .storageFailure, "corrupt \(label)")
      #expect(try Data(contentsOf: corruptFixture.ledgerURL) == bytes, "preserved \(label)")
    }

    var unknownKey = try #require(
      JSONSerialization.jsonObject(with: validBytes) as? [String: Any]
    )
    unknownKey["unexpected"] = true
    let unknownKeyBytes = try JSONSerialization.data(
      withJSONObject: unknownKey, options: [.sortedKeys])
    try unknownKeyBytes.write(to: corruptFixture.ledgerURL, options: .atomic)
    let unknownKeyError: AgentEventDeliveryLedgerError? = await ledgerError {
      try observe(validReservation, in: corruptFixture.store())
    }
    #expect(unknownKeyError == .storageFailure)
    #expect(try Data(contentsOf: corruptFixture.ledgerURL) == unknownKeyBytes)

    var unknownRecordKey = try #require(
      JSONSerialization.jsonObject(with: validBytes) as? [String: Any]
    )
    var records = try #require(unknownRecordKey["records"] as? [[String: Any]])
    records[0]["unexpected"] = true
    unknownRecordKey["records"] = records
    let unknownRecordKeyBytes = try JSONSerialization.data(
      withJSONObject: unknownRecordKey,
      options: [.sortedKeys]
    )
    try unknownRecordKeyBytes.write(to: corruptFixture.ledgerURL, options: .atomic)
    let unknownRecordKeyError: AgentEventDeliveryLedgerError? = await ledgerError {
      try observe(validReservation, in: corruptFixture.store())
    }
    #expect(unknownRecordKeyError == .storageFailure)
    #expect(try Data(contentsOf: corruptFixture.ledgerURL) == unknownRecordKeyBytes)

    let overflow = String(decoding: validBytes, as: UTF8.self)
      .replacingOccurrences(
        of: "\"attemptCount\":1",
        with: "\"attemptCount\":18446744073709551616"
      )
    let overflowBytes = Data(overflow.utf8)
    try overflowBytes.write(to: corruptFixture.ledgerURL, options: .atomic)
    let overflowError: AgentEventDeliveryLedgerError? = await ledgerError {
      try observe(validReservation, in: corruptFixture.store())
    }
    #expect(overflowError == .storageFailure)
    #expect(try Data(contentsOf: corruptFixture.ledgerURL) == overflowBytes)

    let oversizedRootFixture = try LedgerFixture.makeRoot()
    let oversizedRoot = oversizedRootFixture.url
    defer { cleanupLedgerFixtureRoot(oversizedRootFixture) }
    let oversizedURL = oversizedRoot.appendingPathComponent("event-delivery-ledger.json")
    let oversized = Data(repeating: 0x20, count: 8 * 1_048_576 + 1)
    try oversized.write(to: oversizedURL, options: .atomic)
    let oversizedStore = AgentEventDeliveryLedgerStore(
      fileURL: oversizedURL,
      now: { Date(timeIntervalSince1970: 1_800_000_000) }
    )
    let oversizedError: AgentEventDeliveryLedgerError? = await ledgerError {
      _ = try reserve(
        directCandidate(profile: stableUUID(1), subscription: 1, event: 1),
        in: oversizedStore
      )
    }
    #expect(oversizedError == .storageFailure)
    #expect(try Data(contentsOf: oversizedURL) == oversized)
  }
}

private func cleanupLedgerFixtureRoot(_ root: OwnedMCPFixtureRoot) {
  do {
    try root.cleanup()
  } catch {
    Issue.record("Ledger fixture cleanup failed: \(error)")
  }
}

private struct LedgerFixture {
  let rootURL: URL
  let ownedRoot: OwnedMCPFixtureRoot
  let outboxURL: URL
  let subscriptionURL: URL
  let ledgerURL: URL
  let profileID: UUID
  let noteID: UUID
  let subscriptionID: String
  let callbackURL: String
  let signingKeyReference: String
  let baseDate: Date
  let eventIDs: [String]
  let positions: [AgentEventOutboxPosition]
  let bodies: [Data]
  let clock: LedgerTestClock
  let outboxStore: AgentEventOutboxStore
  let subscriptionStore: AgentEventSubscriptionStore
  let binding: AgentEventCallbackVerificationBinding

  static func makeRoot() throws -> OwnedMCPFixtureRoot {
    try OwnedMCPFixtureRoot.create(kind: .eventDeliveryLedger)
  }

  static func make(
    entryCount: Int = 1,
    eventAges: [TimeInterval]? = nil,
    subscriptionLifetime: TimeInterval = 604_800,
    eventIDs explicitEventIDs: [String]? = nil
  ) async throws -> LedgerFixture {
    let ownedRoot = try OwnedMCPFixtureRoot.create(kind: .eventDeliveryLedger)
    var ownershipTransferred = false
    defer {
      if !ownershipTransferred {
        cleanupLedgerFixtureRoot(ownedRoot)
      }
    }
    let rootURL = ownedRoot.url
    let entryCount = eventAges?.count ?? entryCount
    let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
    let profileID = UUID()
    let noteID = UUID()
    let callbackURL = "https://ledger-canary.invalid/events/PRIVATE_CALLBACK_URL_CANARY"
    let scope = AgentEventScope.note(noteID: noteID)
    let event = AgentEventName.noteUpdated
    let subscriptionID = AgentEventSubscriptionIdentity.subscriptionID(
      profileID: profileID,
      event: event,
      scope: scope,
      callbackURL: callbackURL
    )
    let signingKeyReference = UUID().uuidString.lowercased()
    let outboxURL = rootURL.appendingPathComponent("event-outbox.json")
    let subscriptionURL = rootURL.appendingPathComponent("event-subscriptions.json")
    let ledgerURL = rootURL.appendingPathComponent("event-delivery-ledger.json")
    let clock = LedgerTestClock(date: baseDate)
    let subscriptionStore = AgentEventSubscriptionStore(fileURL: subscriptionURL)
    try await subscriptionStore.reserveSigningKeyReference(signingKeyReference)
    _ = try await subscriptionStore.createOrRefresh(
      AgentEventPendingSubscription(
        subscriptionID: subscriptionID,
        profileID: profileID,
        event: event,
        scope: scope,
        callbackURL: callbackURL,
        signingKeyReference: signingKeyReference,
        grantRevision: 1,
        createdAt: baseDate,
        updatedAt: baseDate,
        expiresAt: baseDate.addingTimeInterval(subscriptionLifetime),
        revision: 1
      ),
      now: baseDate
    )

    let ages = eventAges ?? Array(repeating: 0, count: entryCount)
    let epoch = UUID()
    let eventIDs = explicitEventIDs ?? (0..<entryCount).map { _ in UUID().uuidString.lowercased() }
    let positions = (0..<entryCount).map { index in
      AgentEventOutboxPosition(epoch: epoch, sequence: UInt64(index + 1))
    }
    let bodies = try (0..<entryCount).map { index in
      let timestamp = isoTimestamp(baseDate.addingTimeInterval(-ages[index]))
      let envelope = try AgentEventEnvelope(
        eventID: eventIDs[index],
        name: event,
        timestamp: timestamp,
        data: .noteUpdated(
          noteID: noteID,
          revision: UInt64(index + 1),
          changedFields: [.body],
          origin: .local
        ),
        cursor: nil
      )
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
      return try encoder.encode(envelope)
    }
    let outboxStore = AgentEventOutboxStore(fileURL: outboxURL)
    try outboxStore.update { state in
      let anchor = AgentEventOutboxPosition(epoch: epoch, sequence: 0)
      state.progress = [
        AgentEventOutboxProgress(
          profileID: profileID,
          subscriptionID: subscriptionID,
          subscriptionRevision: 1,
          grantRevision: 1,
          anchor: anchor,
          capturedThrough: AgentEventOutboxPosition(
            epoch: epoch,
            sequence: UInt64(entryCount)
          ),
          status: .pending,
          nonDeliveryDisposition: nil
        )
      ]
      state.entries = (0..<entryCount).map { index in
        AgentEventOutboxEntry(
          profileID: profileID,
          subscriptionID: subscriptionID,
          eventID: eventIDs[index],
          sourcePosition: positions[index],
          body: bodies[index],
          status: .awaitingVerification,
          nonDeliveryDisposition: nil
        )
      }
    }
    let fixture = LedgerFixture(
      rootURL: rootURL,
      ownedRoot: ownedRoot,
      outboxURL: outboxURL,
      subscriptionURL: subscriptionURL,
      ledgerURL: ledgerURL,
      profileID: profileID,
      noteID: noteID,
      subscriptionID: subscriptionID,
      callbackURL: callbackURL,
      signingKeyReference: signingKeyReference,
      baseDate: baseDate,
      eventIDs: eventIDs,
      positions: positions,
      bodies: bodies,
      clock: clock,
      outboxStore: outboxStore,
      subscriptionStore: subscriptionStore,
      binding: AgentEventCallbackVerificationBinding(
        profileID: profileID,
        subscriptionID: subscriptionID,
        subscriptionRevision: 1,
        grantRevision: 1,
        signingKeyReference: signingKeyReference
      )
    )
    ownershipTransferred = true
    return fixture
  }

  func service(
    writer: LedgerTestFileWriter? = nil,
    jitterBasisPoints: UInt64 = 0,
    subscriptionRead: (@Sendable (String) async throws -> AgentEventPendingSubscription?)? = nil
  ) -> AgentEventDeliveryLedgerService {
    AgentEventDeliveryLedgerService(
      outboxStore: AgentEventOutboxStore(fileURL: outboxURL),
      subscriptionStore: subscriptionStore,
      ledgerStore: store(writer: writer, jitterBasisPoints: jitterBasisPoints),
      subscriptionRead: subscriptionRead
    )
  }

  func store(
    writer: LedgerTestFileWriter? = nil,
    jitterBasisPoints: UInt64 = 0
  ) -> AgentEventDeliveryLedgerStore {
    AgentEventDeliveryLedgerStore(
      fileURL: ledgerURL,
      now: { clock.now() },
      jitterBasisPoints: { jitterBasisPoints },
      fileWriter: { data, url in
        if let writer {
          try writer.write(data, to: url)
        } else {
          try data.write(to: url, options: .atomic)
        }
      }
    )
  }

  func readLedger() throws -> AgentEventDeliveryLedgerDocument {
    try JSONDecoder().decode(
      AgentEventDeliveryLedgerDocument.self, from: Data(contentsOf: ledgerURL))
  }

  func refreshSubscription(updateProgress: Bool = true) async throws
    -> AgentEventPendingSubscription
  {
    let previous = try #require(
      try await subscriptionStore.currentSubscription(id: subscriptionID)
    )
    let nextKeyReference = UUID().uuidString.lowercased()
    try await subscriptionStore.reserveSigningKeyReference(nextKeyReference)
    let mutation = try await subscriptionStore.createOrRefresh(
      AgentEventPendingSubscription(
        subscriptionID: previous.subscriptionID,
        profileID: previous.profileID,
        event: previous.event,
        scope: previous.scope,
        callbackURL: previous.callbackURL,
        signingKeyReference: nextKeyReference,
        grantRevision: previous.grantRevision,
        createdAt: previous.createdAt,
        updatedAt: clock.now(),
        expiresAt: previous.expiresAt,
        revision: previous.revision
      ),
      now: clock.now()
    )
    if updateProgress {
      try outboxStore.update { state in
        guard
          let index = state.progress.firstIndex(where: {
            $0.profileID == profileID && $0.subscriptionID == subscriptionID
          })
        else { throw AgentEventOutboxError.registrationRequired }
        state.progress[index].subscriptionRevision = mutation.stored.revision
      }
    }
    return mutation.stored
  }

  func remove() {
    cleanupLedgerFixtureRoot(ownedRoot)
  }
}

private final class LedgerTestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var date: Date

  init(date: Date) {
    self.date = date
  }

  func now() -> Date {
    lock.withLock { date }
  }

  func set(_ date: Date) {
    lock.withLock { self.date = date }
  }
}

private actor LedgerSubscriptionReadGate {
  private var readCount = 0
  private var blockedRead: CheckedContinuation<Void, Never>?
  private var finalReadWaiter: CheckedContinuation<Void, Never>?

  func read(
    subscriptionStore: AgentEventSubscriptionStore,
    id: String
  ) async throws -> AgentEventPendingSubscription? {
    let subscription = try await subscriptionStore.currentSubscription(id: id)
    readCount += 1
    guard readCount == 2 else { return subscription }
    await withCheckedContinuation { continuation in
      blockedRead = continuation
      finalReadWaiter?.resume()
      finalReadWaiter = nil
    }
    return subscription
  }

  func waitForFinalRead() async {
    guard blockedRead == nil else { return }
    await withCheckedContinuation { continuation in
      finalReadWaiter = continuation
    }
  }

  func releaseFinalRead() {
    let continuation = blockedRead
    blockedRead = nil
    continuation?.resume()
  }
}

private final class LedgerTestFileWriter: @unchecked Sendable {
  private let lock = NSLock()
  private var before: Set<Int>
  private var after: Set<Int>
  private var writeCount = 0

  init(failBeforeWriteNumbers: Set<Int> = [], failAfterWriteNumbers: Set<Int> = []) {
    before = failBeforeWriteNumbers
    after = failAfterWriteNumbers
  }

  func setFailures(before: Set<Int>, after: Set<Int>) {
    lock.withLock {
      self.before = before
      self.after = after
    }
  }

  func write(_ data: Data, to url: URL) throws {
    let (shouldFailBefore, shouldFailAfter) = lock.withLock {
      writeCount += 1
      return (before.contains(writeCount), after.contains(writeCount))
    }
    if shouldFailBefore { throw AgentEventDeliveryLedgerError.storageFailure }
    try data.write(to: url, options: .atomic)
    if shouldFailAfter { throw AgentEventDeliveryLedgerError.storageFailure }
  }
}

private final class LedgerGateClock: @unchecked Sendable {
  private let lock = NSLock()
  private let firstCall = DispatchSemaphore(value: 0)
  private let releaseFirst = DispatchSemaphore(value: 0)
  private let secondCall = DispatchSemaphore(value: 0)
  private let base: Date
  private var calls = 0

  init(base: Date) {
    self.base = base
  }

  var callCount: Int {
    lock.withLock { calls }
  }

  func now() -> Date {
    let index = lock.withLock {
      calls += 1
      return calls
    }
    if index == 1 {
      firstCall.signal()
      _ = releaseFirst.wait(timeout: .now() + 5)
    } else {
      secondCall.signal()
    }
    return base.addingTimeInterval(TimeInterval(index))
  }

  func waitForFirstCall() -> Bool {
    firstCall.wait(timeout: .now() + 5) == .success
  }

  func secondCallArrived(timeout: DispatchTime) -> Bool {
    secondCall.wait(timeout: timeout) == .success
  }

  func releaseFirstCall() {
    releaseFirst.signal()
  }
}

private func ledgerError<Value>(
  _ operation: () async throws -> Value
) async -> AgentEventDeliveryLedgerError? {
  do {
    _ = try await operation()
    return nil
  } catch {
    return error as? AgentEventDeliveryLedgerError
  }
}

private func isoTimestamp(_ date: Date) -> String {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  return formatter.string(from: date)
}

private func markStagedEntryNotDelivered(in fixture: LedgerFixture) throws {
  try fixture.outboxStore.update { state in
    guard
      let progressIndex = state.progress.firstIndex(where: {
        $0.profileID == fixture.profileID && $0.subscriptionID == fixture.subscriptionID
      }),
      let entryIndex = state.entries.firstIndex(where: {
        $0.profileID == fixture.profileID && $0.subscriptionID == fixture.subscriptionID
      })
    else {
      throw AgentEventOutboxError.registrationRequired
    }
    state.progress[progressIndex].status = .pausedHistory
    state.entries[entryIndex].status = .notDelivered
    state.entries[entryIndex].body = nil
    state.entries[entryIndex].nonDeliveryDisposition = .expired
  }
}

private func directCandidate(
  profile: UUID,
  subscription: Int,
  event: Int,
  revision: UInt64 = 1,
  eventTimestamp: Date = Date(timeIntervalSince1970: 1_800_000_000),
  subscriptionExpiresAt: Date = Date(timeIntervalSince1970: 1_800_100_000)
) -> AgentEventDeliveryLedgerCandidate {
  let subscriptionID =
    "evt_\(String(repeating: "0", count: 64 - String(subscription, radix: 16).count))\(String(subscription, radix: 16))"
  return AgentEventDeliveryLedgerCandidate(
    binding: AgentEventCallbackVerificationBinding(
      profileID: profile,
      subscriptionID: subscriptionID,
      subscriptionRevision: revision,
      grantRevision: 1,
      signingKeyReference: stableUUID(1_000_000 + subscription).uuidString.lowercased()
    ),
    eventID: stableUUID(2_000_000 + event).uuidString.lowercased(),
    sourcePosition: AgentEventOutboxPosition(
      epoch: stableUUID(3_000_000 + subscription),
      sequence: UInt64(event)
    ),
    eventTimestamp: eventTimestamp,
    subscriptionExpiresAt: subscriptionExpiresAt
  )
}

private func ledgerDocument(
  schemaVersion: Int = 2,
  records: [AgentEventDeliveryLedgerRecord],
  bindingGenerations explicitGenerations: [AgentEventDeliveryLedgerBindingGeneration]? = nil,
  lastObservedAt: Date
) -> AgentEventDeliveryLedgerDocument {
  var generationsBySubscription: [String: AgentEventDeliveryLedgerBindingGeneration] = [:]
  for record in records {
    let key =
      "\(record.binding.profileID.uuidString.lowercased())\u{0}\(record.binding.subscriptionID)"
    if generationsBySubscription[key] == nil {
      generationsBySubscription[key] = AgentEventDeliveryLedgerBindingGeneration(
        binding: record.binding,
        generationID: record.bindingGenerationID
      )
    }
  }
  return AgentEventDeliveryLedgerDocument(
    schemaVersion: schemaVersion,
    records: records,
    bindingGenerations: explicitGenerations ?? Array(generationsBySubscription.values),
    lastObservedAt: lastObservedAt
  )
}

private func reserve(
  _ candidate: AgentEventDeliveryLedgerCandidate,
  in store: AgentEventDeliveryLedgerStore,
  expectedGeneration: AgentEventDeliveryLedgerBindingGeneration? = nil
) throws -> AgentEventDeliveryLedgerReservationDecision {
  let currentGeneration = try store.currentBindingGeneration(
    profileID: candidate.binding.profileID,
    subscriptionID: candidate.binding.subscriptionID
  )
  return try store.reconcileAndReserve(
    candidates: [candidate],
    validatedBinding: candidate.binding,
    expectedGeneration: expectedGeneration ?? currentGeneration
  )
}

private func observe(
  _ reservation: AgentEventDeliveryLedgerReservation,
  in store: AgentEventDeliveryLedgerStore
) throws {
  guard
    let generation = try store.currentBindingGeneration(
      profileID: reservation.binding.profileID,
      subscriptionID: reservation.binding.subscriptionID
    )
  else {
    throw AgentEventDeliveryLedgerError.staleReservation
  }
  try store.observe(reservation, expectedGeneration: generation)
}

private func settle(
  _ reservation: AgentEventDeliveryLedgerReservation,
  outcome: AgentEventDeliveryLedgerOutcome,
  in store: AgentEventDeliveryLedgerStore
) throws -> AgentEventDeliveryLedgerRecord {
  guard
    let generation = try store.currentBindingGeneration(
      profileID: reservation.binding.profileID,
      subscriptionID: reservation.binding.subscriptionID
    )
  else {
    throw AgentEventDeliveryLedgerError.staleReservation
  }
  return try store.settle(reservation, outcome: outcome, expectedGeneration: generation)
}

private func cancel(
  _ reservation: AgentEventDeliveryLedgerReservation,
  in store: AgentEventDeliveryLedgerStore
) throws -> AgentEventDeliveryLedgerRecord {
  guard
    let generation = try store.currentBindingGeneration(
      profileID: reservation.binding.profileID,
      subscriptionID: reservation.binding.subscriptionID
    )
  else {
    throw AgentEventDeliveryLedgerError.staleReservation
  }
  return try store.cancel(reservation, expectedGeneration: generation)
}

private func capacityDocument(
  recordsPerSubscription: Int = 0,
  recordsPerProfile: Int = 0,
  bindingCount: Int = 0,
  totalRecords: Int = 0
) -> AgentEventDeliveryLedgerDocument {
  let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
  var records: [AgentEventDeliveryLedgerRecord] = []
  let profileCount: Int
  let subscriptionsPerProfile: Int
  let perSubscription: Int
  if recordsPerSubscription > 0 {
    profileCount = 1
    subscriptionsPerProfile = 1
    perSubscription = recordsPerSubscription
  } else if recordsPerProfile > 0 {
    profileCount = 1
    subscriptionsPerProfile = 2
    perSubscription = recordsPerProfile / 2
  } else if bindingCount > 0 {
    profileCount = bindingCount
    subscriptionsPerProfile = 1
    perSubscription = 1
  } else {
    profileCount = 8
    subscriptionsPerProfile = 16
    perSubscription = totalRecords / (profileCount * subscriptionsPerProfile)
  }

  for profileIndex in 0..<profileCount {
    for subscriptionIndex in 0..<subscriptionsPerProfile {
      let bindingIndex = profileIndex * subscriptionsPerProfile + subscriptionIndex + 1
      let profile = stableUUID(10_000 + profileIndex)
      let binding = AgentEventCallbackVerificationBinding(
        profileID: profile,
        subscriptionID:
          "evt_\(String(repeating: "0", count: 64 - String(bindingIndex, radix: 16).count))\(String(bindingIndex, radix: 16))",
        subscriptionRevision: 1,
        grantRevision: 1,
        signingKeyReference: stableUUID(20_000 + bindingIndex).uuidString.lowercased()
      )
      let generationID = stableUUID(40_000 + bindingIndex).uuidString.lowercased()
      for sequence in 1...perSubscription {
        let eventNumber = bindingIndex * 10_000 + sequence
        records.append(
          AgentEventDeliveryLedgerRecord(
            binding: binding,
            bindingGenerationID: generationID,
            eventID: stableUUID(eventNumber).uuidString.lowercased(),
            sourcePosition: AgentEventOutboxPosition(
              epoch: stableUUID(30_000 + bindingIndex),
              sequence: UInt64(sequence)
            ),
            expiresAt: baseDate.addingTimeInterval(604_800),
            attemptCount: 1,
            status: .receipt,
            reservationID: nil,
            leaseDeadline: nil,
            nextEligibleAt: nil,
            httpStatus: 204,
            failureCategory: nil
          )
        )
      }
    }
  }
  return ledgerDocument(records: records, lastObservedAt: baseDate)
}

private func write(_ document: AgentEventDeliveryLedgerDocument, to url: URL) throws {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
  try encoder.encode(document).write(to: url, options: .atomic)
}

private func stableUUID(_ value: Int) -> UUID {
  let suffix = String(value, radix: 16)
  let padded = String(repeating: "0", count: 12 - suffix.count) + suffix
  return UUID(uuidString: "00000000-0000-4000-8000-\(padded)")!
}
