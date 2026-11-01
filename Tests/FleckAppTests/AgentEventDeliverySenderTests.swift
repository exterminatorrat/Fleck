import CryptoKit
import FleckCore
import FleckMCPFixtureSupport
import Foundation
import Testing

@testable import FleckApp

@Suite(.serialized)
struct AgentEventDeliverySenderTests {
  @Test func sendsExactStagedBodyWithFreshSignatureAndLeavesOutboxUntouched() async throws {
    let fixture = try await SenderFixture.make(ownerEnabled: true)
    defer { fixture.remove() }
    let probe = SenderExchangeProbe(
      responses: [AgentEventHTTPResponse(statusCode: 204, body: Data("remote-private-body".utf8))]
    )
    let sender = fixture.sender(exchange: probe.exchange)

    let result = await sender.send(
      fixture.reservation,
      workspaceProvider: { fixture.workspace }
    )

    #expect(result == .settled(.receipt))
    let request = try #require(await probe.firstRequest())
    #expect(await probe.requestCount() == 1)
    #expect(request.url == fixture.callbackURL)
    #expect(request.body == fixture.body)
    try AgentEventHTTPTransport.validateHeaders(request.headers)
    let headers = Dictionary(uniqueKeysWithValues: request.headers.map { ($0.name, $0.value) })
    #expect(
      Set(headers.keys)
        == Set([
          "content-type", "webhook-id", "webhook-timestamp", "webhook-signature",
          "x-mcp-subscription-id",
        ]))
    #expect(headers["webhook-id"] == fixture.eventID)
    #expect(headers["x-mcp-subscription-id"] == fixture.subscriptionID)
    #expect(headers["content-type"] == "application/json")
    let signatureIsValid = try independentlyValidSignature(request, secret: fixture.secret)
    #expect(signatureIsValid)

    let record = try fixture.ledgerRecord()
    #expect(record.status == .receipt)
    #expect(record.httpStatus == 204)
    let outbox = try fixture.outboxStore.load()
    #expect(outbox == fixture.initialOutbox)
    #expect(fixture.secretStore.readCount() == 1)
    try fixture.assertNoPersistence(of: Data("remote-private-body".utf8))
    try fixture.assertNoPersistence(of: fixture.secret)
  }

  @Test func liveOverlapSignsExactAttemptWithCurrentAndPreviousKeys() async throws {
    let fixture = try await SenderFixture.make(ownerEnabled: true)
    defer { fixture.remove() }
    let previousReference = try fixture.installPreviousSigningKey(
      expiresAt: SenderFixture.baseDate.addingTimeInterval(60)
    )
    let probe = SenderExchangeProbe(
      responses: [AgentEventHTTPResponse(statusCode: 204, body: Data())]
    )

    #expect(
      await fixture.sender(exchange: probe.exchange).send(
        fixture.reservation,
        workspaceProvider: { fixture.workspace }
      ) == .settled(.receipt)
    )

    let request = try #require(await probe.firstRequest())
    let signature = try #require(
      request.headers.first { $0.name == "webhook-signature" }?.value
    )
    #expect(signature.split(separator: " ").count == 2)
    try AgentEventHTTPTransport.validateHeaders(request.headers)
    #expect(try independentlyValidSignature(request, secret: fixture.secret))
    #expect(
      try independentlyValidSignature(
        request,
        secret: Data(repeating: 0x24, count: 32)
      )
    )
    #expect(request.body == fixture.body)
    #expect(fixture.secretStore.readCount() == 2)
    #expect(
      try await fixture.subscriptionStore.currentSubscription(id: fixture.subscriptionID)?
        .previousSigningKey?.reference == previousReference
    )
  }

  @Test func overlapExpiringDuringFinalAuthorizationSendsCurrentOnly() async throws {
    let fixture = try await SenderFixture.make(ownerEnabled: true)
    defer { fixture.remove() }
    let previousSecret = Data(repeating: 0x24, count: 32)
    let previousReference = try fixture.installPreviousSigningKey(
      expiresAt: SenderFixture.baseDate.addingTimeInterval(1)
    )
    let gate = SenderWorkspaceGate(workspace: fixture.workspace, pauseOnCall: 3)
    let probe = SenderExchangeProbe(
      responses: [AgentEventHTTPResponse(statusCode: 204, body: Data())]
    )
    let task = Task {
      await fixture.sender(exchange: probe.exchange).send(
        fixture.reservation,
        workspaceProvider: { try await gate.provide() }
      )
    }
    await gate.waitUntilPaused()
    fixture.clock.set(SenderFixture.baseDate.addingTimeInterval(2))
    await gate.release()

    #expect(await task.value == .settled(.receipt))
    let request = try #require(await probe.firstRequest())
    let signature = try #require(
      request.headers.first { $0.name == "webhook-signature" }?.value
    )
    #expect(signature.split(separator: " ").count == 1)
    #expect(try independentlyValidSignature(request, secret: fixture.secret))
    let previousSignatureIsValid = try independentlyValidSignature(
      request,
      secret: previousSecret
    )
    #expect(!previousSignatureIsValid)
    #expect(request.body == fixture.body)
    #expect(
      request.headers.first { $0.name == "webhook-timestamp" }?.value == "1800000000"
    )
    #expect(fixture.secretStore.readCount() == 2)
    #expect(
      try await fixture.subscriptionStore.currentSubscription(id: fixture.subscriptionID)?
        .previousSigningKey?.reference == previousReference
    )
  }

  @Test func missingLiveOverlapKeyFailsClosedBeforeExchange() async throws {
    let fixture = try await SenderFixture.make(ownerEnabled: true)
    defer { fixture.remove() }
    let previousReference = try fixture.installPreviousSigningKey(
      expiresAt: SenderFixture.baseDate.addingTimeInterval(60)
    )
    try fixture.signingKeyStore.delete(reference: previousReference)
    fixture.secretStore.resetCounts()
    let probe = SenderExchangeProbe(responses: [])

    #expect(
      await fixture.sender(exchange: probe.exchange).send(
        fixture.reservation,
        workspaceProvider: { fixture.workspace }
      ) == .denied
    )
    #expect(fixture.secretStore.readCount() == 2)
    #expect(await probe.requestCount() == 0)
  }

  @Test func initialEligibilityDenialsDoNotReadKeysOrInvokeExchange() async throws {
    enum Denial: CaseIterable {
      case ownerOff
      case missingProof
      case revokedProfile
      case permissionChanged
      case expiredLease
      case unavailableWorkspace
    }

    for denial in Denial.allCases {
      let fixture = try await SenderFixture.make(
        includeProof: denial != .missingProof,
        ownerEnabled: denial != .ownerOff
      )
      defer { fixture.remove() }
      switch denial {
      case .ownerOff, .missingProof, .unavailableWorkspace:
        break
      case .revokedProfile:
        try fixture.revokeProfile()
      case .permissionChanged:
        try await fixture.disableObservationPermission()
      case .expiredLease:
        fixture.clock.set(SenderFixture.baseDate.addingTimeInterval(31))
      }
      let probe = SenderExchangeProbe(
        responses: [AgentEventHTTPResponse(statusCode: 204, body: Data())]
      )
      let workspaceProvider: AgentEventWorkspaceProvider = {
        if denial == .unavailableWorkspace { throw SenderWorkspaceUnavailable() }
        return fixture.workspace
      }
      let result = await fixture.sender(exchange: probe.exchange).send(
        fixture.reservation,
        workspaceProvider: workspaceProvider
      )

      #expect(result == .denied)
      #expect(fixture.secretStore.readCount() == 0)
      #expect(await probe.requestCount() == 0)
      let record = try fixture.ledgerRecord()
      #expect(record.status == .reserved || denial == .expiredLease)
    }
  }

  @Test func preCancelledCallSettlesCancellationBeforeReadingKeyOrExchanging() async throws {
    let fixture = try await SenderFixture.make(ownerEnabled: true)
    defer { fixture.remove() }
    let probe = SenderExchangeProbe(responses: [])
    let sender = fixture.sender(exchange: probe.exchange)
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return await sender.send(
        fixture.reservation,
        workspaceProvider: { fixture.workspace }
      )
    }

    #expect(await task.value == .settled(.retryWaiting))
    #expect(fixture.secretStore.readCount() == 0)
    #expect(await probe.requestCount() == 0)
    let record = try fixture.ledgerRecord()
    #expect(record.status == .retryWaiting)
    #expect(record.failureCategory == .cancelled)
    #expect(record.httpStatus == nil)
    #expect(try fixture.outboxStore.load() == fixture.initialOutbox)
  }

  @Test func invalidReservationBodyKeyAndSigningTimeNeverReachExchange() async throws {
    let staleFixture = try await SenderFixture.make(ownerEnabled: true)
    defer { staleFixture.remove() }
    let staleProbe = SenderExchangeProbe(responses: [])
    let stale = replacingReservationID(staleFixture.reservation)
    #expect(
      await staleFixture.sender(exchange: staleProbe.exchange).send(
        stale,
        workspaceProvider: { staleFixture.workspace }
      ) == .denied
    )
    #expect(staleFixture.secretStore.readCount() == 0)
    #expect(await staleProbe.requestCount() == 0)

    let bodyFixture = try await SenderFixture.make(ownerEnabled: true)
    defer { bodyFixture.remove() }
    var outboxDocument = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: bodyFixture.outboxURL)) as? [String: Any]
    )
    var entries = try #require(outboxDocument["entries"] as? [[String: Any]])
    entries[0]["body"] = Data("not an event envelope".utf8).base64EncodedString()
    outboxDocument["entries"] = entries
    let malformedOutbox = try JSONSerialization.data(
      withJSONObject: outboxDocument,
      options: [.sortedKeys]
    )
    try malformedOutbox.write(to: bodyFixture.outboxURL, options: .atomic)
    let bodyProbe = SenderExchangeProbe(responses: [])
    #expect(
      await bodyFixture.sender(exchange: bodyProbe.exchange).send(
        bodyFixture.reservation,
        workspaceProvider: { bodyFixture.workspace }
      ) == .denied
    )
    #expect(bodyFixture.secretStore.readCount() == 0)
    #expect(await bodyProbe.requestCount() == 0)

    let missingKeyFixture = try await SenderFixture.make(ownerEnabled: true)
    defer { missingKeyFixture.remove() }
    try missingKeyFixture.signingKeyStore.delete(reference: missingKeyFixture.signingKeyReference)
    missingKeyFixture.secretStore.resetCounts()
    let missingKeyProbe = SenderExchangeProbe(responses: [])
    #expect(
      await missingKeyFixture.sender(exchange: missingKeyProbe.exchange).send(
        missingKeyFixture.reservation,
        workspaceProvider: { missingKeyFixture.workspace }
      ) == .denied
    )
    #expect(missingKeyFixture.secretStore.readCount() == 1)
    #expect(await missingKeyProbe.requestCount() == 0)

    let timeFixture = try await SenderFixture.make(ownerEnabled: true)
    defer { timeFixture.remove() }
    let timeProbe = SenderExchangeProbe(responses: [])
    let invalidTimeSender = timeFixture.sender(
      now: { Date(timeIntervalSince1970: .infinity) },
      exchange: timeProbe.exchange
    )
    #expect(
      await invalidTimeSender.send(
        timeFixture.reservation,
        workspaceProvider: { timeFixture.workspace }
      ) == .denied
    )
    #expect(timeFixture.secretStore.readCount() == 0)
    #expect(await timeProbe.requestCount() == 0)
  }

  @Test func aSourceChangeDuringLedgerObservationStopsBeforeKeyRead() async throws {
    let fixture = try await SenderFixture.make(ownerEnabled: true)
    defer { fixture.remove() }
    let gate = SenderSubscriptionReadGate(pauseAt: 2)
    let service = fixture.ledgerService(subscriptionRead: { id in
      try await gate.read(store: fixture.subscriptionStore, id: id)
    })
    let probe = SenderExchangeProbe(responses: [])
    let task = Task {
      await fixture.sender(ledgerService: service, exchange: probe.exchange).send(
        fixture.reservation,
        workspaceProvider: { fixture.workspace }
      )
    }
    await gate.waitUntilPaused()
    _ = try await fixture.subscriptionStore.remove(
      subscriptionID: fixture.subscriptionID,
      profileID: fixture.profileID
    )
    await gate.release()

    #expect(await task.value == .denied)
    #expect(fixture.secretStore.readCount() == 0)
    #expect(await probe.requestCount() == 0)
  }

  @Test func profileRevocationDuringSigningKeyReadStopsBeforeExchange() async throws {
    let fixture = try await SenderFixture.make(ownerEnabled: true)
    defer { fixture.remove() }
    let profileURL = fixture.profileURL
    let revokedProfile = AgentIntegrationProfile(
      id: fixture.profileID,
      displayName: "Synthetic sender profile",
      createdAt: SenderFixture.baseDate,
      lastConnectedAt: nil,
      revokedAt: SenderFixture.baseDate.addingTimeInterval(1)
    )
    let profileData = try JSONEncoder().encode([revokedProfile])
    fixture.secretStore.runBeforeNextRead {
      try profileData.write(to: profileURL, options: .atomic)
    }
    let probe = SenderExchangeProbe(responses: [])

    #expect(
      await fixture.sender(exchange: probe.exchange).send(
        fixture.reservation,
        workspaceProvider: { fixture.workspace }
      ) == .denied
    )
    #expect(fixture.secretStore.readCount() == 1)
    #expect(await probe.requestCount() == 0)
    let persistedProfiles = try JSONDecoder().decode(
      [AgentIntegrationProfile].self,
      from: Data(contentsOf: profileURL)
    )
    #expect(persistedProfiles.first?.revokedAt == revokedProfile.revokedAt)
    let record = try fixture.ledgerRecord()
    #expect(record.status != .receipt)
  }

  @Test func ownerMutationAtTheFinalAuthorizationCheckpointPreventsExchange() async throws {
    let fixture = try await SenderFixture.make(ownerEnabled: true)
    defer { fixture.remove() }
    let gate = SenderWorkspaceGate(workspace: fixture.workspace, pauseOnCall: 3)
    let probe = SenderExchangeProbe(responses: [])
    let task = Task {
      await fixture.sender(exchange: probe.exchange).send(
        fixture.reservation,
        workspaceProvider: { try await gate.provide() }
      )
    }
    await gate.waitUntilPaused()
    let currentControl = try #require(
      try await fixture.subscriptionStore.currentSubscription(id: fixture.subscriptionID)?
        .deliveryControl
    )
    _ = try await fixture.subscriptionStore.setOwnerDeliveryEligibility(
      binding: fixture.binding,
      expectedGenerationID: currentControl.generationID,
      eligible: false
    )
    await gate.release()

    #expect(await task.value == .denied)
    #expect(fixture.secretStore.readCount() == 1)
    #expect(await probe.requestCount() == 0)
  }

  @Test
  func temporaryExclusionABADuringLedgerObservationStopsBeforeKeyReadAndExchange() async throws {
    let fixture = try await SenderFixture.make(ownerEnabled: true)
    defer { fixture.remove() }
    let gate = SenderSubscriptionReadGate(pauseAt: 2)
    let service = fixture.ledgerService(subscriptionRead: { id in
      try await gate.read(store: fixture.subscriptionStore, id: id)
    })
    let probe = SenderExchangeProbe(responses: [])
    let task = Task {
      await fixture.sender(ledgerService: service, exchange: probe.exchange).send(
        fixture.reservation,
        workspaceProvider: { fixture.workspace }
      )
    }

    await gate.waitUntilPaused()
    fixture.authority.exclude(noteID: fixture.noteID)
    fixture.authority.include(noteID: fixture.noteID)
    await gate.release()

    #expect(await task.value == .denied)
    #expect(fixture.secretStore.readCount() == 0)
    #expect(await probe.requestCount() == 0)
  }

  @Test func temporaryExclusionABADuringFinalEligibilityRecheckPreventsExchange() async throws {
    let fixture = try await SenderFixture.make(ownerEnabled: true)
    defer { fixture.remove() }
    let gate = SenderWorkspaceGate(workspace: fixture.workspace, pauseOnCall: 3)
    let probe = SenderExchangeProbe(responses: [])
    let task = Task {
      await fixture.sender(exchange: probe.exchange).send(
        fixture.reservation,
        workspaceProvider: { try await gate.provide() }
      )
    }

    await gate.waitUntilPaused()
    fixture.authority.exclude(noteID: fixture.noteID)
    fixture.authority.include(noteID: fixture.noteID)
    await gate.release()

    #expect(await task.value == .denied)
    #expect(fixture.secretStore.readCount() == 1)
    #expect(await probe.requestCount() == 0)
  }

  @Test func cancellationDuringInitialAndFinalAuthorizationProviderSuspensionsSettles() async throws
  {
    let scenarios: [(Int, Bool, Int)] = [
      (1, false, 0), (1, true, 0), (3, false, 1), (3, true, 1),
    ]
    for (pauseOnCall, throwsAfterRelease, expectedKeyReads) in scenarios {
      let fixture = try await SenderFixture.make(ownerEnabled: true)
      defer { fixture.remove() }
      let gate = SenderWorkspaceGate(
        workspace: fixture.workspace,
        pauseOnCall: pauseOnCall,
        throwsAfterPause: throwsAfterRelease
      )
      let probe = SenderExchangeProbe(responses: [])
      let task = Task {
        await fixture.sender(exchange: probe.exchange).send(
          fixture.reservation,
          workspaceProvider: { try await gate.provide() }
        )
      }
      await gate.waitUntilPaused()
      task.cancel()
      await gate.release()

      #expect(await task.value == .settled(.retryWaiting))
      #expect(fixture.secretStore.readCount() == expectedKeyReads)
      #expect(await probe.requestCount() == 0)
      let record = try fixture.ledgerRecord()
      #expect(record.status == .retryWaiting)
      #expect(record.failureCategory == .cancelled)
      #expect(record.httpStatus == nil)
    }
  }

  @Test func retriesPreserveEventIDAndBodyButRefreshTimestampAndSignature() async throws {
    let fixture = try await SenderFixture.make(ownerEnabled: true)
    defer { fixture.remove() }
    let probe = SenderExchangeProbe(
      responses: [
        AgentEventHTTPResponse(statusCode: 503, body: Data("remote-private-error".utf8)),
        AgentEventHTTPResponse(statusCode: 202, body: Data("remote-private-body".utf8)),
      ]
    )
    let sender = fixture.sender(exchange: probe.exchange)
    let firstResult = await sender.send(
      fixture.reservation,
      workspaceProvider: { fixture.workspace }
    )
    fixture.clock.set(SenderFixture.baseDate.addingTimeInterval(5))
    let nextReservation = try #require(
      try await fixture.ledgerService.reserveNext(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID
      )
    )
    let secondResult = await sender.send(
      nextReservation,
      workspaceProvider: { fixture.workspace }
    )

    #expect(firstResult == .settled(.retryWaiting))
    #expect(secondResult == .settled(.receipt))
    let requests = await probe.requests()
    #expect(requests.count == 2)
    #expect(requests[0].body == fixture.body)
    #expect(requests[1].body == fixture.body)
    #expect(requests[0].body == requests[1].body)
    #expect(requests[0].headers.first { $0.name == "webhook-id" }?.value == fixture.eventID)
    #expect(requests[1].headers.first { $0.name == "webhook-id" }?.value == fixture.eventID)
    #expect(
      requests[0].headers.first { $0.name == "webhook-timestamp" }?.value
        != requests[1].headers.first { $0.name == "webhook-timestamp" }?.value
    )
    #expect(
      requests[0].headers.first { $0.name == "webhook-signature" }?.value
        != requests[1].headers.first { $0.name == "webhook-signature" }?.value
    )
    let firstSignatureIsValid = try independentlyValidSignature(requests[0], secret: fixture.secret)
    let secondSignatureIsValid = try independentlyValidSignature(
      requests[1], secret: fixture.secret)
    #expect(firstSignatureIsValid)
    #expect(secondSignatureIsValid)
    let record = try fixture.ledgerRecord()
    #expect(record.status == .receipt)
    let outbox = try fixture.outboxStore.load()
    #expect(outbox == fixture.initialOutbox)
    try fixture.assertNoPersistence(of: Data("remote-private-error".utf8))
    try fixture.assertNoPersistence(of: Data("remote-private-body".utf8))
  }

  @Test func reportedStatusesAndTransportFailureUseOnlyLedgerSettlementCategories()
    async throws
  {
    let cases: [(Int, AgentEventDeliveryLedgerRecordStatus)] = [
      (200, .receipt), (429, .retryWaiting), (503, .retryWaiting), (410, .terminal),
      (413, .terminal), (401, .paused), (403, .paused),
    ]
    for (status, expectedStatus) in cases {
      let fixture = try await SenderFixture.make(ownerEnabled: true)
      defer { fixture.remove() }
      let probe = SenderExchangeProbe(
        responses: [
          AgentEventHTTPResponse(
            statusCode: status,
            body: Data("unpersisted-remote-body".utf8),
            retryAfterSeconds: status == 429 ? .greatestFiniteMagnitude : nil
          )
        ]
      )
      let result = await fixture.sender(exchange: probe.exchange).send(
        fixture.reservation,
        workspaceProvider: { fixture.workspace }
      )
      #expect(result == .settled(expectedStatus))
      let record = try fixture.ledgerRecord()
      #expect(record.status == expectedStatus)
      #expect(record.httpStatus == status)
      #expect(await probe.requestCount() == 1)
      try fixture.assertNoPersistence(of: Data("unpersisted-remote-".utf8))
    }

    let fixture = try await SenderFixture.make(ownerEnabled: true)
    defer { fixture.remove() }
    let probe = SenderExchangeProbe(responses: [], fail: true)
    #expect(
      await fixture.sender(exchange: probe.exchange).send(
        fixture.reservation,
        workspaceProvider: { fixture.workspace }
      ) == .settled(.retryWaiting)
    )
    let failedRecord = try fixture.ledgerRecord()
    #expect(failedRecord.failureCategory == .transportFailure)
    #expect(failedRecord.httpStatus == nil)
    try fixture.assertNoPersistence(of: Data("remote-private-error".utf8))
  }

  @Test func concurrentCallsReturnBusyAndTaskCancellationSettlesCancelledOutcome() async throws {
    let fixture = try await SenderFixture.make(ownerEnabled: true)
    defer { fixture.remove() }
    let probe = SenderExchangeProbe(responses: [], suspend: true)
    let sender = fixture.sender(exchange: probe.exchange)
    let first = Task {
      await sender.send(fixture.reservation, workspaceProvider: { fixture.workspace })
    }
    _ = await probe.waitForFirstRequest()
    let unrelatedReservation = replacingReservationID(fixture.reservation)
    #expect(
      await sender.send(
        unrelatedReservation,
        workspaceProvider: { fixture.workspace }
      ) == .busy
    )
    #expect(await probe.requestCount() == 1)
    #expect(fixture.secretStore.readCount() == 1)
    first.cancel()

    #expect(await first.value == .settled(.retryWaiting))
    let record = try fixture.ledgerRecord()
    #expect(record.failureCategory == .cancelled)
    #expect(record.status == .retryWaiting)
  }

  @Test func cancelledGenericExchangeFailureSettlesAsCancellation() async throws {
    let fixture = try await SenderFixture.make(ownerEnabled: true)
    defer { fixture.remove() }
    let probe = SenderExchangeProbe(responses: [])
    let task = Task {
      await fixture.sender(exchange: probe.exchangeWithoutCancellationHandler).send(
        fixture.reservation,
        workspaceProvider: { fixture.workspace }
      )
    }
    _ = await probe.waitForFirstRequest()
    task.cancel()
    await probe.failSuspendedRequest()

    #expect(await task.value == .settled(.retryWaiting))
    #expect(await probe.requestCount() == 1)
    let record = try fixture.ledgerRecord()
    #expect(record.status == .retryWaiting)
    #expect(record.failureCategory == .cancelled)
    #expect(record.httpStatus == nil)
    try fixture.assertNoPersistence(of: Data("remote-private-error".utf8))
  }

  @Test func lateLeaseOrRemovedBindingCannotCreateAReceipt() async throws {
    let expiredFixture = try await SenderFixture.make(ownerEnabled: true)
    defer { expiredFixture.remove() }
    let expiredProbe = SenderExchangeProbe(responses: [], suspend: true)
    let expiredTask = Task {
      await expiredFixture.sender(exchange: expiredProbe.exchange).send(
        expiredFixture.reservation,
        workspaceProvider: { expiredFixture.workspace }
      )
    }
    _ = await expiredProbe.waitForFirstRequest()
    expiredFixture.clock.set(SenderFixture.baseDate.addingTimeInterval(31))
    await expiredProbe.resume(with: AgentEventHTTPResponse(statusCode: 200, body: Data()))
    #expect(await expiredTask.value == .settlementFailed)
    let expiredRecord = try expiredFixture.ledgerRecord()
    #expect(expiredRecord.status != .receipt)

    let removedFixture = try await SenderFixture.make(ownerEnabled: true)
    defer { removedFixture.remove() }
    let removedProbe = SenderExchangeProbe(responses: [], suspend: true)
    let removedTask = Task {
      await removedFixture.sender(exchange: removedProbe.exchange).send(
        removedFixture.reservation,
        workspaceProvider: { removedFixture.workspace }
      )
    }
    _ = await removedProbe.waitForFirstRequest()
    _ = try await removedFixture.subscriptionStore.remove(
      subscriptionID: removedFixture.subscriptionID,
      profileID: removedFixture.profileID
    )
    await removedProbe.resume(with: AgentEventHTTPResponse(statusCode: 200, body: Data()))
    #expect(await removedTask.value == .settlementFailed)
    let removedRecord = try removedFixture.ledgerRecord()
    #expect(removedRecord.status != .receipt)
  }

  @Test func settlementUsesPersistedBytesToRecognizeActualCommit() async throws {
    for failure in [SenderTestFileWriter.Failure.beforeWrite, .afterWrite] {
      let fixture = try await SenderFixture.make(ownerEnabled: true)
      defer { fixture.remove() }
      let probe = SenderExchangeProbe(
        responses: [AgentEventHTTPResponse(statusCode: 200, body: Data("remote-private-body".utf8))]
      )
      let sender = fixture.sender(exchange: { url, headers, body in
        fixture.fileWriter.failNext(failure)
        return try await probe.exchange(url: url, headers: headers, body: body)
      })

      let result = await sender.send(
        fixture.reservation,
        workspaceProvider: { fixture.workspace }
      )

      #expect(
        result == (failure == .beforeWrite ? .settlementFailed : .settled(.receipt))
      )
      #expect(await probe.requestCount() == 1)
      let record = try fixture.ledgerRecord()
      #expect(record.status == (failure == .beforeWrite ? .reserved : .receipt))
      let outbox = try fixture.outboxStore.load()
      #expect(outbox == fixture.initialOutbox)
      try fixture.assertNoPersistence(of: Data("remote-private-body".utf8))
    }
  }
}

private struct SenderFixture {
  static let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
  static let signingSecret = Data(repeating: 0x53, count: 32)

  let rootURL: URL
  let ownedRoot: OwnedMCPFixtureRoot
  let profileURL: URL
  let subscriptionURL: URL
  let verificationURL: URL
  let outboxURL: URL
  let ledgerURL: URL
  let profileID: UUID
  let noteID: UUID
  let subscriptionID: String
  let signingKeyReference: String
  let callbackURL: String
  let eventID: String
  let body: Data
  var secret: Data { Self.signingSecret }
  let workspace: Workspace
  let binding: AgentEventCallbackVerificationBinding
  let reservation: AgentEventDeliveryLedgerReservation
  let initialOutbox: AgentEventOutboxState
  let clock: SenderTestClock
  let secretStore: SenderTestSecretStore
  let signingKeyStore: AgentEventSigningKeyStore
  let authority: AgentCapabilityAuthority
  let capabilities: AgentCapabilityStore
  let profileStore: AgentProfileStore
  let subscriptionStore: AgentEventSubscriptionStore
  let verificationStore: AgentEventCallbackVerificationStore
  let outboxStore: AgentEventOutboxStore
  let ledgerStore: AgentEventDeliveryLedgerStore
  let ledgerService: AgentEventDeliveryLedgerService
  let fileWriter: SenderTestFileWriter

  static func make(
    includeProof: Bool = true,
    ownerEnabled: Bool = false
  ) async throws -> SenderFixture {
    let ownedRoot = try OwnedMCPFixtureRoot.create(kind: .eventDeliverySender)
    var ownershipTransferred = false
    defer {
      if !ownershipTransferred {
        do {
          try ownedRoot.cleanup()
        } catch {
          Issue.record("Sender fixture construction cleanup failed: \(error)")
        }
      }
    }
    let rootURL = ownedRoot.url
    let profileID = UUID()
    let noteID = UUID()
    let workspace = Workspace(notes: [Note(id: noteID)])
    let callbackURL = "https://delivery-sender.invalid/events"
    let subscriptionID = AgentEventSubscriptionIdentity.subscriptionID(
      profileID: profileID,
      event: .noteUpdated,
      scope: .note(noteID: noteID),
      callbackURL: callbackURL
    )
    let signingKeyReference = UUID().uuidString.lowercased()
    let clock = SenderTestClock(date: baseDate)
    let secretStore = SenderTestSecretStore()
    let signingKeyStore = AgentEventSigningKeyStore(secretStore: secretStore)

    let profileURL = rootURL.appendingPathComponent("profiles.json")
    let profile = AgentIntegrationProfile(
      id: profileID,
      displayName: "Synthetic sender profile",
      createdAt: baseDate,
      lastConnectedAt: nil,
      revokedAt: nil
    )
    try JSONEncoder().encode([profile]).write(to: profileURL, options: .atomic)
    let profileStore = AgentProfileStore(
      profilesURL: profileURL,
      secretStore: secretStore,
      now: { clock.now() }
    )

    let capabilityDirectory = rootURL.appendingPathComponent("capabilities", isDirectory: true)
    let capabilities = AgentCapabilityStore(
      capabilitiesURL: capabilityDirectory.appendingPathComponent("capabilities.json"),
      previousCapabilitiesURL: capabilityDirectory.appendingPathComponent(
        "capabilities.previous.json"
      )
    )
    var capabilityState = try await capabilities.loadOrMigrate(
      activeProfileIDs: [profileID],
      workspace: workspace
    )
    if capabilityState.profiles[profileID] == nil {
      capabilityState = try await capabilities.registerEmptyProfile(profileID)
    }
    let priorCapabilities = try #require(capabilityState.profiles[profileID])
    let capabilitiesProfile = AgentProfileCapabilities(
      profileID: profileID,
      grantRevision: priorCapabilities.grantRevision + 1,
      allowedCapabilities: [.readNotes],
      grants: [AgentResourceGrant(scope: .note(noteID: noteID), authority: .read)],
      allowsEventObservation: true
    )
    _ = try await capabilities.replaceProfile(
      capabilitiesProfile,
      expectedGrantRevision: priorCapabilities.grantRevision
    )
    let authority = AgentCapabilityAuthority(store: capabilities)

    let subscriptionURL = rootURL.appendingPathComponent("event-subscriptions.json")
    let subscriptionStore = AgentEventSubscriptionStore(fileURL: subscriptionURL)
    try await subscriptionStore.reserveSigningKeyReference(signingKeyReference)
    _ = try await subscriptionStore.createOrRefresh(
      AgentEventPendingSubscription(
        subscriptionID: subscriptionID,
        profileID: profileID,
        event: .noteUpdated,
        scope: .note(noteID: noteID),
        callbackURL: callbackURL,
        signingKeyReference: signingKeyReference,
        grantRevision: capabilitiesProfile.grantRevision,
        createdAt: baseDate,
        updatedAt: baseDate,
        expiresAt: baseDate.addingTimeInterval(86_400),
        revision: 1
      ),
      now: baseDate
    )
    let binding = AgentEventCallbackVerificationBinding(
      profileID: profileID,
      subscriptionID: subscriptionID,
      subscriptionRevision: 1,
      grantRevision: capabilitiesProfile.grantRevision,
      signingKeyReference: signingKeyReference
    )
    let verificationURL = rootURL.appendingPathComponent("event-verification.json")
    let verificationStore = AgentEventCallbackVerificationStore(
      fileURL: verificationURL,
      now: { clock.now() }
    )
    if includeProof {
      let intent = AgentEventCallbackVerificationIntent(
        id: UUID(),
        binding: binding,
        nonceDigest: Data(repeating: 0x2a, count: 32),
        createdAt: baseDate,
        expiresAt: baseDate.addingTimeInterval(60)
      )
      try verificationStore.begin(intent)
      _ = try verificationStore.complete(
        intent,
        subscriptionExpiresAt: baseDate.addingTimeInterval(86_400)
      )
    }

    let eventID = UUID().uuidString.lowercased()
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let envelope = try AgentEventEnvelope(
      eventID: eventID,
      name: .noteUpdated,
      timestamp: formatter.string(from: baseDate),
      data: .noteUpdated(
        noteID: noteID,
        revision: 1,
        changedFields: [.body],
        origin: .local
      ),
      cursor: nil
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let body = try encoder.encode(envelope)
    let position = AgentEventOutboxPosition(epoch: UUID(), sequence: 1)
    let outboxURL = rootURL.appendingPathComponent("event-outbox.json")
    let outboxStore = AgentEventOutboxStore(fileURL: outboxURL)
    try outboxStore.update { state in
      state.progress = [
        AgentEventOutboxProgress(
          profileID: profileID,
          subscriptionID: subscriptionID,
          subscriptionRevision: 1,
          grantRevision: capabilitiesProfile.grantRevision,
          anchor: AgentEventOutboxPosition(epoch: position.epoch, sequence: 0),
          capturedThrough: position,
          status: .pending,
          nonDeliveryDisposition: nil
        )
      ]
      state.entries = [
        AgentEventOutboxEntry(
          profileID: profileID,
          subscriptionID: subscriptionID,
          eventID: eventID,
          sourcePosition: position,
          body: body,
          status: .awaitingVerification,
          nonDeliveryDisposition: nil
        )
      ]
    }
    let initialOutbox = try outboxStore.load()
    let ledgerURL = rootURL.appendingPathComponent("event-delivery-ledger.json")
    let fileWriter = SenderTestFileWriter()
    let ledgerStore = AgentEventDeliveryLedgerStore(
      fileURL: ledgerURL,
      now: { clock.now() },
      jitterBasisPoints: { 0 },
      fileWriter: { data, url in try fileWriter.write(data, to: url) }
    )
    let ledgerService = AgentEventDeliveryLedgerService(
      outboxStore: outboxStore,
      subscriptionStore: subscriptionStore,
      ledgerStore: ledgerStore
    )
    guard
      let reservation = try await ledgerService.reserveNext(
        profileID: profileID,
        subscriptionID: subscriptionID
      )
    else {
      throw SenderTestError.missingReservation
    }
    _ = try await ledgerService.observe(reservation)
    if ownerEnabled {
      let ownerControl = try #require(
        try await subscriptionStore.currentSubscription(id: subscriptionID)?.deliveryControl
      )
      _ = try await subscriptionStore.setOwnerDeliveryEligibility(
        binding: binding,
        expectedGenerationID: ownerControl.generationID,
        eligible: true
      )
    }
    try signingKeyStore.store(secretData: signingSecret, reference: signingKeyReference)
    secretStore.resetCounts()

    let fixture = SenderFixture(
      rootURL: rootURL,
      ownedRoot: ownedRoot,
      profileURL: profileURL,
      subscriptionURL: subscriptionURL,
      verificationURL: verificationURL,
      outboxURL: outboxURL,
      ledgerURL: ledgerURL,
      profileID: profileID,
      noteID: noteID,
      subscriptionID: subscriptionID,
      signingKeyReference: signingKeyReference,
      callbackURL: callbackURL,
      eventID: eventID,
      body: body,
      workspace: workspace,
      binding: binding,
      reservation: reservation,
      initialOutbox: initialOutbox,
      clock: clock,
      secretStore: secretStore,
      signingKeyStore: signingKeyStore,
      authority: authority,
      capabilities: capabilities,
      profileStore: profileStore,
      subscriptionStore: subscriptionStore,
      verificationStore: verificationStore,
      outboxStore: outboxStore,
      ledgerStore: ledgerStore,
      ledgerService: ledgerService,
      fileWriter: fileWriter
    )
    ownershipTransferred = true
    return fixture
  }

  func sender(
    now: (@Sendable () -> Date)? = nil,
    ledgerService: AgentEventDeliveryLedgerService? = nil,
    exchange: @escaping AgentEventDeliveryExchange
  ) -> AgentEventDeliverySender {
    AgentEventDeliverySender(
      ledgerService: ledgerService ?? self.ledgerService,
      authorizationService: authorizationService(),
      subscriptionStore: subscriptionStore,
      signingKeyStore: signingKeyStore,
      now: now ?? { clock.now() },
      exchange: exchange
    )
  }

  func installPreviousSigningKey(expiresAt: Date) throws -> String {
    let reference = UUID().uuidString.lowercased()
    var document = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: subscriptionURL)) as? [String: Any]
    )
    var subscriptions = try #require(document["subscriptions"] as? [[String: Any]])
    subscriptions[0]["previousSigningKey"] = [
      "reference": reference,
      "startedAt": Self.baseDate.timeIntervalSinceReferenceDate,
      "expiresAt": expiresAt.timeIntervalSinceReferenceDate,
    ]
    document["subscriptions"] = subscriptions
    try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
      .write(to: subscriptionURL, options: .atomic)
    try signingKeyStore.store(secretData: Data(repeating: 0x24, count: 32), reference: reference)
    return reference
  }

  func authorizationService() -> AgentEventDeliveryAuthorizationService {
    AgentEventDeliveryAuthorizationService(
      authority: authority,
      profileStore: profileStore,
      subscriptionStore: subscriptionStore,
      verificationStore: verificationStore,
      outboxStore: outboxStore,
      ledgerStore: ledgerStore,
      now: { clock.now() }
    )
  }

  func ledgerService(
    subscriptionRead: (@Sendable (String) async throws -> AgentEventPendingSubscription?)?
  ) -> AgentEventDeliveryLedgerService {
    AgentEventDeliveryLedgerService(
      outboxStore: outboxStore,
      subscriptionStore: subscriptionStore,
      ledgerStore: ledgerStore,
      subscriptionRead: subscriptionRead
    )
  }

  func ledgerRecord() throws -> AgentEventDeliveryLedgerRecord {
    let document = try JSONDecoder().decode(
      AgentEventDeliveryLedgerDocument.self,
      from: Data(contentsOf: ledgerURL)
    )
    return try #require(document.records.first { $0.eventID == eventID })
  }

  func revokeProfile() throws {
    let profile = AgentIntegrationProfile(
      id: profileID,
      displayName: "Synthetic sender profile",
      createdAt: Self.baseDate,
      lastConnectedAt: nil,
      revokedAt: clock.now()
    )
    try JSONEncoder().encode([profile]).write(to: profileURL, options: .atomic)
  }

  func disableObservationPermission() async throws {
    let state = try await capabilities.currentState()
    let current = try #require(state.profiles[profileID])
    let replacement = AgentProfileCapabilities(
      profileID: profileID,
      grantRevision: current.grantRevision + 1,
      allowedCapabilities: current.allowedCapabilities,
      grants: current.grants,
      allowsEventObservation: false
    )
    _ = try await capabilities.replaceProfile(
      replacement,
      expectedGrantRevision: current.grantRevision
    )
  }

  func assertNoPersistence(of bytes: Data) throws {
    for url in [profileURL, subscriptionURL, verificationURL, outboxURL, ledgerURL] {
      guard FileManager.default.fileExists(atPath: url.path) else { continue }
      let persisted = try Data(contentsOf: url)
      #expect(persisted.range(of: bytes) == nil)
    }
  }

  func remove() {
    do {
      try ownedRoot.cleanup()
    } catch {
      Issue.record("Sender fixture cleanup failed: \(error)")
    }
  }
}

private struct SenderExchangeRequest: Equatable, Sendable {
  let url: String
  let headers: [AgentEventHTTPHeader]
  let body: Data
}

private actor SenderExchangeProbe {
  private let responses: [AgentEventHTTPResponse]
  private let shouldFail: Bool
  private let shouldSuspend: Bool
  private var capturedRequests: [SenderExchangeRequest] = []
  private var responseIndex = 0
  private var requestWaiter: CheckedContinuation<SenderExchangeRequest, Never>?
  private var responseContinuation: CheckedContinuation<AgentEventHTTPResponse, any Error>?

  init(
    responses: [AgentEventHTTPResponse],
    fail: Bool = false,
    suspend: Bool = false
  ) {
    self.responses = responses
    shouldFail = fail
    shouldSuspend = suspend
  }

  func exchange(
    url: String,
    headers: [AgentEventHTTPHeader],
    body: Data
  ) async throws -> AgentEventHTTPResponse {
    let request = SenderExchangeRequest(url: url, headers: headers, body: body)
    capturedRequests.append(request)
    requestWaiter?.resume(returning: request)
    requestWaiter = nil
    if shouldSuspend {
      return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
          responseContinuation = continuation
        }
      } onCancel: {
        Task { await self.cancelResponse() }
      }
    }
    if shouldFail { throw SenderRemoteError() }
    guard responseIndex < responses.count else { throw SenderRemoteError() }
    let response = responses[responseIndex]
    responseIndex += 1
    return response
  }

  func exchangeWithoutCancellationHandler(
    url: String,
    headers: [AgentEventHTTPHeader],
    body: Data
  ) async throws -> AgentEventHTTPResponse {
    let request = SenderExchangeRequest(url: url, headers: headers, body: body)
    capturedRequests.append(request)
    requestWaiter?.resume(returning: request)
    requestWaiter = nil
    return try await withCheckedThrowingContinuation { continuation in
      responseContinuation = continuation
    }
  }

  func requestCount() -> Int {
    capturedRequests.count
  }

  func requests() -> [SenderExchangeRequest] {
    capturedRequests
  }

  func firstRequest() async -> SenderExchangeRequest? {
    if let request = capturedRequests.first { return request }
    return await withCheckedContinuation { continuation in
      requestWaiter = continuation
    }
  }

  func waitForFirstRequest() async -> SenderExchangeRequest {
    if let request = capturedRequests.first { return request }
    return await withCheckedContinuation { continuation in
      requestWaiter = continuation
    }
  }

  func resume(with response: AgentEventHTTPResponse) {
    let continuation = responseContinuation
    responseContinuation = nil
    continuation?.resume(returning: response)
  }

  func failSuspendedRequest() {
    let continuation = responseContinuation
    responseContinuation = nil
    continuation?.resume(throwing: SenderRemoteError())
  }

  private func cancelResponse() {
    let continuation = responseContinuation
    responseContinuation = nil
    continuation?.resume(throwing: CancellationError())
  }
}

private actor SenderSubscriptionReadGate {
  private let pauseAt: Int
  private var readCount = 0
  private var paused = false
  private var releaseRequested = false
  private var pauseWaiter: CheckedContinuation<Void, Never>?
  private var releaseContinuation: CheckedContinuation<Void, Never>?

  init(pauseAt: Int) {
    self.pauseAt = pauseAt
  }

  func read(
    store: AgentEventSubscriptionStore,
    id: String
  ) async throws -> AgentEventPendingSubscription? {
    readCount += 1
    if readCount == pauseAt {
      paused = true
      pauseWaiter?.resume()
      pauseWaiter = nil
      await withCheckedContinuation { continuation in
        if releaseRequested {
          continuation.resume()
        } else {
          releaseContinuation = continuation
        }
      }
    }
    return try await store.currentSubscription(id: id)
  }

  func waitUntilPaused() async {
    guard !paused else { return }
    await withCheckedContinuation { continuation in
      pauseWaiter = continuation
    }
  }

  func release() {
    releaseRequested = true
    let continuation = releaseContinuation
    releaseContinuation = nil
    continuation?.resume()
  }
}

private actor SenderWorkspaceGate {
  private let workspace: Workspace
  private let pauseOnCall: Int
  private let throwsAfterPause: Bool
  private var callCount = 0
  private var paused = false
  private var releaseRequested = false
  private var pauseWaiter: CheckedContinuation<Void, Never>?
  private var releaseContinuation: CheckedContinuation<Void, Never>?

  init(workspace: Workspace, pauseOnCall: Int, throwsAfterPause: Bool = false) {
    self.workspace = workspace
    self.pauseOnCall = pauseOnCall
    self.throwsAfterPause = throwsAfterPause
  }

  func provide() async throws -> Workspace {
    callCount += 1
    if callCount == pauseOnCall {
      paused = true
      pauseWaiter?.resume()
      pauseWaiter = nil
      await withCheckedContinuation { continuation in
        if releaseRequested {
          continuation.resume()
        } else {
          releaseContinuation = continuation
        }
      }
      if throwsAfterPause { throw CancellationError() }
    }
    return workspace
  }

  func waitUntilPaused() async {
    guard !paused else { return }
    await withCheckedContinuation { continuation in
      pauseWaiter = continuation
    }
  }

  func release() {
    releaseRequested = true
    let continuation = releaseContinuation
    releaseContinuation = nil
    continuation?.resume()
  }
}

private final class SenderTestClock: @unchecked Sendable {
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

private final class SenderTestSecretStore: AgentSecretStoring, @unchecked Sendable {
  private static let signingKeyService = "com.harryjin.fleck.agent-event-signing-keys"
  private let lock = NSLock()
  private var values: [String: Data] = [:]
  private var reads = 0
  private var beforeNextRead: (() throws -> Void)?

  func read(service: String, account: String) throws -> Data? {
    let (value, action) = lock.withLock {
      reads += 1
      let action = beforeNextRead
      beforeNextRead = nil
      return (values[key(service: service, account: account)], action)
    }
    try action?()
    return value
  }

  func runBeforeNextRead(_ action: @escaping () throws -> Void) {
    lock.withLock { beforeNextRead = action }
  }

  func write(_ data: Data, service: String, account: String) throws {
    lock.withLock { values[key(service: service, account: account)] = data }
  }

  func delete(service: String, account: String) throws {
    _ = lock.withLock { values.removeValue(forKey: key(service: service, account: account)) }
  }

  func readCount() -> Int {
    lock.withLock { reads }
  }

  func resetCounts() {
    lock.withLock { reads = 0 }
  }

  func removeSigningKey(reference: String) {
    try? delete(service: Self.signingKeyService, account: reference)
  }

  private func key(service: String, account: String) -> String {
    "\(service)\u{0}\(account)"
  }
}

private final class SenderTestFileWriter: @unchecked Sendable {
  enum Failure: Equatable {
    case beforeWrite
    case afterWrite
  }

  private let lock = NSLock()
  private var nextFailure: Failure?

  func failNext(_ failure: Failure) {
    lock.withLock { nextFailure = failure }
  }

  func write(_ data: Data, to url: URL) throws {
    let failure = lock.withLock {
      let failure = nextFailure
      nextFailure = nil
      return failure
    }
    if failure == .beforeWrite { throw SenderTestFileWriteError.injected }
    try data.write(to: url, options: .atomic)
    if failure == .afterWrite { throw SenderTestFileWriteError.injected }
  }
}

private enum SenderTestFileWriteError: Error {
  case injected
}

private struct SenderRemoteError: LocalizedError {
  var errorDescription: String? { "remote-private-error" }
}

private struct SenderWorkspaceUnavailable: Error {}

private enum SenderTestError: Error {
  case missingReservation
}

private func independentlyValidSignature(
  _ request: SenderExchangeRequest,
  secret: Data
) throws -> Bool {
  let headers = Dictionary(uniqueKeysWithValues: request.headers.map { ($0.name, $0.value) })
  guard
    let eventID = headers["webhook-id"],
    let timestamp = headers["webhook-timestamp"],
    let signature = headers["webhook-signature"]
  else {
    return false
  }
  var message = Data("\(eventID).\(timestamp).".utf8)
  message.append(request.body)
  let code = HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: secret))
  return signature.split(separator: " ").contains("v1,\(Data(code).base64EncodedString())")
}

private func replacingReservationID(
  _ reservation: AgentEventDeliveryLedgerReservation
) -> AgentEventDeliveryLedgerReservation {
  AgentEventDeliveryLedgerReservation(
    id: UUID(),
    binding: reservation.binding,
    bindingGenerationID: reservation.bindingGenerationID,
    eventID: reservation.eventID,
    sourcePosition: reservation.sourcePosition,
    expiresAt: reservation.expiresAt,
    attemptCount: reservation.attemptCount,
    leaseDeadline: reservation.leaseDeadline
  )
}
