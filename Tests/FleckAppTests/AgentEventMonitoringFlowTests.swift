import CryptoKit
import FleckCore
import FleckMCPFixtureSupport
import Foundation
import Testing

@testable import FleckApp

@Suite(.serialized)
struct AgentEventMonitoringFlowTests {
  @Test func anchorsBeforeChallengeAndSendsOneCapturedEventPerCall() async throws {
    let fixture = try await AgentEventMonitoringFlowFixture.make()
    defer { fixture.remove() }

    let localStore = fixture.runtime.localStore
    let updatedWorkspace = fixture.updatedWorkspace
    await fixture.callbackExchange.setAfterRequest {
      _ = try await localStore.save(
        workspace: updatedWorkspace,
        preferences: .init(),
        generation: 2
      )
    }

    let proof = try await fixture.runtime.monitoringService.anchorAndVerifyPendingSubscription(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      workspaceProvider: fixture.workspaceProvider,
      now: fixture.clock.now()
    )
    try await fixture.enableOwnerDelivery(for: proof.binding)
    try await fixture.saveSecondLocalNote()

    let snapshot = try await fixture.runtime.localStore.loadSnapshot()
    let lastRecord = try #require(snapshot.agentEventJournal?.records.last)
    let progress = try #require(fixture.runtime.outboxStore.load().progress.first)
    let anchor = try #require(progress.anchor)
    #expect(anchor.sequence == 1)
    #expect(anchor.sequence < lastRecord.sequence)
    #expect(lastRecord.provenance == .local)
    #expect(await fixture.callbackExchange.requestCount() == 1)

    let result = try await fixture.runtime.monitoringService.captureReserveAndSendAtMostOne(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      workspaceProvider: fixture.workspaceProvider,
      now: fixture.clock.now()
    )
    #expect(result == .some(.settled(.receipt)))

    let outbox = try fixture.runtime.outboxStore.load()
    let entries = outbox.entries.sorted {
      $0.sourcePosition.sequence < $1.sourcePosition.sequence
    }
    #expect(entries.count == 2)
    let entry = try #require(entries.first)
    let body = try #require(entry.body)
    let envelope = try JSONDecoder().decode(AgentEventEnvelope.self, from: body)
    let metadataOnly: Bool
    if case .noteUpdated(let noteID, let revision, let fields, .local) = envelope.data {
      metadataOnly =
        noteID == fixture.initialNote.id
        && revision == fixture.updatedNote.revision
        && Set(fields) == Set([.title, .body])
    } else {
      metadataOnly = false
    }
    #expect(metadataOnly)
    #expect(envelope.eventID == entry.eventID)
    #expect(envelope.cursor == nil)

    let noteContents = [
      fixture.initialNote.title,
      fixture.initialNote.body,
      fixture.updatedNote.title,
      fixture.updatedNote.body,
      fixture.secondUpdatedNote.title,
      fixture.secondUpdatedNote.body,
      fixture.integrationBody,
    ]
    let bodyText = String(data: body, encoding: .utf8) ?? ""
    #expect(!noteContents.contains(where: { bodyText.contains($0) }))

    let delivered = try #require(await fixture.applicationExchange.requests().first)
    #expect(delivered.eventID == entry.eventID)
    #expect(delivered.body == body)
    #expect(await fixture.applicationExchange.requestCount() == 1)
    let ledger = try fixture.ledgerDocument()
    #expect(ledger.records.first?.status == .receipt)

    let secondResult = try await fixture.runtime.monitoringService
      .captureReserveAndSendAtMostOne(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID,
        workspaceProvider: fixture.workspaceProvider,
        now: fixture.clock.now()
      )
    #expect(secondResult == .some(.settled(.receipt)))
    let deliveredRequests = await fixture.applicationExchange.requests()
    #expect(deliveredRequests.count == 2)
    let secondDelivery = try #require(deliveredRequests.last)
    #expect(secondDelivery.eventID != delivered.eventID)
    let secondBodyText = String(data: secondDelivery.body, encoding: .utf8) ?? ""
    #expect(!noteContents.contains(where: { secondBodyText.contains($0) }))

    let secondEnvelope = try JSONDecoder().decode(
      AgentEventEnvelope.self,
      from: secondDelivery.body
    )
    let secondMetadataOnly: Bool
    if case .noteUpdated(let noteID, let revision, let fields, .local) = secondEnvelope.data {
      secondMetadataOnly =
        noteID == fixture.secondUpdatedNote.id
        && revision == fixture.secondUpdatedNote.revision
        && Set(fields) == Set([.title, .body])
    } else {
      secondMetadataOnly = false
    }
    #expect(secondMetadataOnly)
    #expect(await fixture.applicationExchange.requestCount() == 2)

    let repeated = try await fixture.runtime.monitoringService.captureReserveAndSendAtMostOne(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      workspaceProvider: fixture.workspaceProvider,
      now: fixture.clock.now()
    )
    #expect(repeated == nil)
    #expect(await fixture.applicationExchange.requestCount() == 2)

    var integrationNote = fixture.secondUpdatedNote
    integrationNote.body = fixture.integrationBody
    integrationNote.revision += 1
    integrationNote.modifiedAt = fixture.clock.now().addingTimeInterval(1)
    let integrationProof = fixture.integrationProof(for: integrationNote)
    _ = try await fixture.runtime.localStore.save(
      workspace: Workspace(notes: [integrationNote], selectedNoteID: integrationNote.id),
      preferences: .init(),
      generation: 4,
      commitProof: integrationProof
    )
    let integrationSnapshot = try await fixture.runtime.localStore.loadSnapshot()
    #expect(integrationSnapshot.agentEventJournal?.records.last?.provenance == .integration)

    let integrationResult = try await fixture.runtime.monitoringService
      .captureReserveAndSendAtMostOne(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID,
        workspaceProvider: fixture.workspaceProvider,
        now: fixture.clock.now()
      )
    #expect(integrationResult == nil)
    #expect((try fixture.runtime.outboxStore.load()).entries.count == 2)
    #expect(await fixture.applicationExchange.requestCount() == 2)
  }

  @Test func reopeningRetriesTheSameEventBodyWithANewSigningTime() async throws {
    let fixture = try await AgentEventMonitoringFlowFixture.make(applicationStatuses: [503, 204])
    defer { fixture.remove() }

    let proof = try await fixture.runtime.monitoringService.anchorAndVerifyPendingSubscription(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      workspaceProvider: fixture.workspaceProvider,
      now: fixture.clock.now()
    )
    try await fixture.enableOwnerDelivery(for: proof.binding)
    try await fixture.saveUpdatedNote()

    let first = try await fixture.runtime.monitoringService.captureReserveAndSendAtMostOne(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      workspaceProvider: fixture.workspaceProvider,
      now: fixture.clock.now()
    )
    #expect(first == .some(.settled(.retryWaiting)))
    let firstRequest = try #require(await fixture.applicationExchange.requests().first)
    let originalEntry = try #require(fixture.runtime.outboxStore.load().entries.first)
    let originalBody = try #require(originalEntry.body)
    #expect(firstRequest.eventID == originalEntry.eventID)
    #expect(firstRequest.body == originalBody)
    #expect(try fixture.ledgerDocument().records.first?.status == .retryWaiting)

    fixture.clock.advance(by: 5)
    let reopenedRuntime = fixture.makeReopenedRuntime()
    let second = try await reopenedRuntime.monitoringService.captureReserveAndSendAtMostOne(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      workspaceProvider: fixture.workspaceProvider(from: reopenedRuntime),
      now: fixture.clock.now()
    )
    #expect(second == .some(.settled(.receipt)))

    let requests = await fixture.applicationExchange.requests()
    #expect(requests.count == 2)
    let secondRequest = try #require(requests.last)
    #expect(secondRequest.eventID == firstRequest.eventID)
    #expect(secondRequest.body == originalBody)
    let firstTime = try #require(Int64(firstRequest.webhookTimestamp))
    let secondTime = try #require(Int64(secondRequest.webhookTimestamp))
    #expect(secondTime > firstTime)

    let reopenedEntry = try #require(reopenedRuntime.outboxStore.load().entries.first)
    #expect(reopenedEntry.eventID == originalEntry.eventID)
    #expect(reopenedEntry.body == originalEntry.body)
    #expect(try fixture.ledgerDocument().records.first?.status == .receipt)

    let repeated = try await reopenedRuntime.monitoringService.captureReserveAndSendAtMostOne(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      workspaceProvider: fixture.workspaceProvider(from: reopenedRuntime),
      now: fixture.clock.now()
    )
    #expect(repeated == nil)
    #expect(await fixture.applicationExchange.requestCount() == 2)
  }

  @Test func defaultOffFailedVerificationRevocationPrivacyAndUnavailableWorkspaceFailClosed()
    async throws
  {
    for scenario in MonitoringFlowFailureScenario.allCases {
      let fixture = try await AgentEventMonitoringFlowFixture.make()
      defer { fixture.remove() }

      if scenario == .failedVerification {
        await fixture.callbackExchange.setExactEcho(false)
      }

      var verificationSucceeded = false
      do {
        let proof = try await fixture.runtime.monitoringService
          .anchorAndVerifyPendingSubscription(
            profileID: fixture.profileID,
            subscriptionID: fixture.subscriptionID,
            workspaceProvider: fixture.workspaceProvider,
            now: fixture.clock.now()
          )
        verificationSucceeded = true
        if scenario != .defaultOff {
          try await fixture.enableOwnerDelivery(for: proof.binding)
        }
      } catch {
        #expect(scenario == .failedVerification)
      }
      #expect(verificationSucceeded == (scenario != .failedVerification))

      if scenario == .defaultOff {
        let subscription = try #require(
          await fixture.runtime.subscriptionStore.currentSubscription(
            id: fixture.subscriptionID
          )
        )
        #expect(subscription.deliveryControl?.enabled != true)
      }

      if scenario == .failedVerification {
        let binding = try await fixture.pendingBinding()
        let proof = try await fixture.runtime.verificationStore.currentProof(for: binding)
        #expect(proof == nil)
        try await fixture.enableOwnerDelivery(for: binding)
      }
      try await fixture.saveUpdatedNote()

      switch scenario {
      case .defaultOff, .failedVerification, .unavailableWorkspace:
        break
      case .revokedProfile:
        try await fixture.runtime.profileStore.revoke(profileID: fixture.profileID)
      case .privateNote:
        fixture.runtime.authority.exclude(noteID: fixture.initialNote.id)
      }

      let provider: AgentEventWorkspaceProvider
      if scenario == .unavailableWorkspace {
        provider = {
          throw AgentEventMonitoringFlowTestError.unavailable
        }
      } else {
        provider = fixture.workspaceProvider
      }
      let result = try await fixture.runtime.monitoringService
        .captureReserveAndSendAtMostOne(
          profileID: fixture.profileID,
          subscriptionID: fixture.subscriptionID,
          workspaceProvider: provider,
          now: fixture.clock.now()
        )

      #expect(await fixture.callbackExchange.requestCount() == 1)
      #expect(await fixture.applicationExchange.requestCount() == 0)
      if scenario == .revokedProfile || scenario == .privateNote {
        #expect(result == nil)
      } else {
        #expect(result == .some(.denied))
      }
    }
  }
}

private enum MonitoringFlowFailureScenario: CaseIterable, Equatable {
  case defaultOff
  case failedVerification
  case revokedProfile
  case privateNote
  case unavailableWorkspace
}

private enum AgentEventMonitoringFlowTestError: Error, Sendable {
  case invalidExchange
  case unavailable
  case ownerConsentNotSaved
}

private struct MonitoringFlowVerificationRequest: Decodable {
  let type: String
  let challenge: String
}

private struct MonitoringFlowVerificationResponse: Encodable {
  let challenge: String
}

private struct MonitoringFlowRequest: Sendable {
  let eventID: String
  let webhookTimestamp: String
  let body: Data
}

private actor MonitoringFlowCallbackExchange {
  private let callbackURL: String
  private let secret: Data
  private var exactEcho = true
  private var totalRequests = 0
  private var afterRequest: (@Sendable () async throws -> Void)?

  init(callbackURL: String, secret: Data) {
    self.callbackURL = callbackURL
    self.secret = secret
  }

  func setExactEcho(_ exact: Bool) {
    exactEcho = exact
  }

  func setAfterRequest(_ action: @escaping @Sendable () async throws -> Void) {
    afterRequest = action
  }

  func requestCount() -> Int {
    totalRequests
  }

  func exchange(
    _ callbackURL: String,
    _ headers: [AgentEventHTTPHeader],
    _ body: Data
  ) async throws -> AgentEventHTTPResponse {
    guard
      callbackURL == self.callbackURL,
      hasValidWebhookSignature(headers: headers, body: body, secret: secret),
      let request = try? JSONDecoder().decode(MonitoringFlowVerificationRequest.self, from: body),
      request.type == "verification",
      !request.challenge.isEmpty
    else {
      throw AgentEventMonitoringFlowTestError.invalidExchange
    }
    totalRequests += 1
    let action = afterRequest
    afterRequest = nil
    try await action?()

    let challenge = exactEcho ? request.challenge : request.challenge + "x"
    let responseBody = try JSONEncoder().encode(
      MonitoringFlowVerificationResponse(challenge: challenge))
    return AgentEventHTTPResponse(statusCode: 200, body: responseBody)
  }
}

private actor MonitoringFlowApplicationExchange {
  private let callbackURL: String
  private let subscriptionID: String
  private let secret: Data
  private var statuses: [Int]
  private var received: [MonitoringFlowRequest] = []

  init(callbackURL: String, subscriptionID: String, secret: Data, statuses: [Int]) {
    self.callbackURL = callbackURL
    self.subscriptionID = subscriptionID
    self.secret = secret
    self.statuses = statuses
  }

  func requests() -> [MonitoringFlowRequest] {
    received
  }

  func requestCount() -> Int {
    received.count
  }

  func exchange(
    _ callbackURL: String,
    _ headers: [AgentEventHTTPHeader],
    _ body: Data
  ) async throws -> AgentEventHTTPResponse {
    guard
      callbackURL == self.callbackURL,
      header("x-mcp-subscription-id", in: headers) == subscriptionID,
      header("content-type", in: headers) == "application/json",
      hasValidWebhookSignature(headers: headers, body: body, secret: secret),
      let envelope = try? JSONDecoder().decode(AgentEventEnvelope.self, from: body),
      envelope.eventID == header("webhook-id", in: headers),
      envelope.cursor == nil
    else {
      throw AgentEventMonitoringFlowTestError.invalidExchange
    }
    guard let timestamp = header("webhook-timestamp", in: headers) else {
      throw AgentEventMonitoringFlowTestError.invalidExchange
    }
    received.append(
      MonitoringFlowRequest(eventID: envelope.eventID, webhookTimestamp: timestamp, body: body)
    )
    let statusCode = statuses.isEmpty ? 204 : statuses.removeFirst()
    return AgentEventHTTPResponse(statusCode: statusCode, body: Data())
  }
}

private func header(_ name: String, in headers: [AgentEventHTTPHeader]) -> String? {
  headers.first(where: { $0.name == name })?.value
}

private func hasValidWebhookSignature(
  headers: [AgentEventHTTPHeader],
  body: Data,
  secret: Data
) -> Bool {
  guard
    let id = header("webhook-id", in: headers),
    let timestamp = header("webhook-timestamp", in: headers),
    Int64(timestamp) != nil,
    let receivedSignature = header("webhook-signature", in: headers)
  else {
    return false
  }
  var message = Data("\(id).\(timestamp).".utf8)
  message.append(body)
  let code = HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: secret))
  let expectedSignature = "v1,\(Data(code).base64EncodedString())"
  return AgentCredentialSecurity.constantTimeEqual(
    Data(expectedSignature.utf8),
    Data(receivedSignature.utf8)
  )
}

private final class MonitoringFlowTestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var value = Date(timeIntervalSince1970: 1_800_000_000)

  func now() -> Date {
    lock.lock()
    defer { lock.unlock() }
    return value
  }

  func advance(by interval: TimeInterval) {
    lock.lock()
    defer { lock.unlock() }
    value = value.addingTimeInterval(interval)
  }
}

private final class MonitoringFlowTestSecretStore: AgentSecretStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var values: [String: Data] = [:]

  func read(service: String, account: String) throws -> Data? {
    lock.lock()
    defer { lock.unlock() }
    return values["\(service)\u{0}\(account)"]
  }

  func write(_ data: Data, service: String, account: String) throws {
    lock.lock()
    defer { lock.unlock() }
    values["\(service)\u{0}\(account)"] = data
  }

  func delete(service: String, account: String) throws {
    lock.lock()
    defer { lock.unlock() }
    values.removeValue(forKey: "\(service)\u{0}\(account)")
  }
}

private final class MonitoringFlowTestRandomBytes: AgentRandomBytesProviding, @unchecked Sendable {
  private let lock = NSLock()
  private var nextByte: UInt8 = 0

  func randomBytes(count: Int) throws -> Data {
    lock.lock()
    defer { lock.unlock() }
    nextByte &+= 1
    return Data(repeating: nextByte, count: count)
  }
}

private struct AgentEventMonitoringRuntime {
  let localStore: LocalStore
  let profileStore: AgentProfileStore
  let authority: AgentCapabilityAuthority
  let subscriptionStore: AgentEventSubscriptionStore
  let verificationStore: AgentEventCallbackVerificationStore
  let outboxStore: AgentEventOutboxStore
  let ledgerStore: AgentEventDeliveryLedgerStore
  let monitoringService: AgentEventMonitoringService

  init(
    localStore: LocalStore,
    profileStore: AgentProfileStore,
    authority: AgentCapabilityAuthority,
    subscriptionStore: AgentEventSubscriptionStore,
    verificationStore: AgentEventCallbackVerificationStore,
    outboxStore: AgentEventOutboxStore,
    ledgerStore: AgentEventDeliveryLedgerStore,
    signingKeyStore: AgentEventSigningKeyStore,
    clock: MonitoringFlowTestClock,
    callbackExchange: MonitoringFlowCallbackExchange,
    applicationExchange: MonitoringFlowApplicationExchange,
    randomBytes: AgentRandomBytesProviding
  ) {
    self.localStore = localStore
    self.profileStore = profileStore
    self.authority = authority
    self.subscriptionStore = subscriptionStore
    self.verificationStore = verificationStore
    self.outboxStore = outboxStore
    self.ledgerStore = ledgerStore

    let outboxService = AgentEventOutboxService(
      store: outboxStore,
      localStore: localStore,
      profileStore: profileStore,
      subscriptionStore: subscriptionStore,
      authority: authority
    )
    let callbackVerificationService = AgentEventCallbackVerificationService(
      authority: authority,
      profileStore: profileStore,
      subscriptionStore: subscriptionStore,
      signingKeyStore: signingKeyStore,
      verificationStore: verificationStore,
      randomBytes: randomBytes,
      now: { clock.now() },
      exchange: { url, headers, body in
        try await callbackExchange.exchange(url, headers, body)
      }
    )
    let deliveryLedgerService = AgentEventDeliveryLedgerService(
      outboxStore: outboxStore,
      subscriptionStore: subscriptionStore,
      ledgerStore: ledgerStore
    )
    let authorizationService = AgentEventDeliveryAuthorizationService(
      authority: authority,
      profileStore: profileStore,
      subscriptionStore: subscriptionStore,
      verificationStore: verificationStore,
      outboxStore: outboxStore,
      ledgerStore: ledgerStore,
      now: { clock.now() }
    )
    let deliverySender = AgentEventDeliverySender(
      ledgerService: deliveryLedgerService,
      authorizationService: authorizationService,
      subscriptionStore: subscriptionStore,
      signingKeyStore: signingKeyStore,
      now: { clock.now() },
      exchange: { url, headers, body in
        try await applicationExchange.exchange(url, headers, body)
      }
    )
    monitoringService = AgentEventMonitoringService(
      authority: authority,
      outboxService: outboxService,
      callbackVerificationService: callbackVerificationService,
      deliveryLedgerService: deliveryLedgerService,
      deliverySender: deliverySender
    )
  }
}

private struct AgentEventMonitoringFlowFixture {
  let rootURL: URL
  let ownedRoot: OwnedMCPFixtureRoot
  let workspaceURL: URL
  let profilesURL: URL
  let capabilitiesURL: URL
  let previousCapabilitiesURL: URL
  let subscriptionURL: URL
  let verificationURL: URL
  let outboxURL: URL
  let ledgerURL: URL
  let profileID: UUID
  let subscriptionID: String
  let initialNote: Note
  let updatedNote: Note
  let secondUpdatedNote: Note
  let integrationBody: String
  let clock: MonitoringFlowTestClock
  let secretStore: MonitoringFlowTestSecretStore
  let randomBytes: MonitoringFlowTestRandomBytes
  let callbackExchange: MonitoringFlowCallbackExchange
  let applicationExchange: MonitoringFlowApplicationExchange
  let runtime: AgentEventMonitoringRuntime

  var updatedWorkspace: Workspace {
    Workspace(notes: [updatedNote], selectedNoteID: updatedNote.id)
  }

  var workspaceProvider: AgentEventWorkspaceProvider {
    workspaceProvider(from: runtime)
  }

  static func make(applicationStatuses: [Int] = [204]) async throws
    -> AgentEventMonitoringFlowFixture
  {
    let ownedRoot = try OwnedMCPFixtureRoot.create(kind: .eventMonitoringFlow)
    var ownershipTransferred = false
    defer {
      if !ownershipTransferred {
        do {
          try ownedRoot.cleanup()
        } catch {
          Issue.record("Monitoring flow fixture construction cleanup failed: \(error)")
        }
      }
    }
    let rootURL = ownedRoot.url
    let workspaceURL = rootURL.appendingPathComponent("workspace", isDirectory: true)
    let integrationsURL = rootURL.appendingPathComponent("integrations", isDirectory: true)
    let eventURL = integrationsURL.appendingPathComponent("events", isDirectory: true)
    try FileManager.default.createDirectory(at: integrationsURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: eventURL, withIntermediateDirectories: true)

    let clock = MonitoringFlowTestClock()
    let secretStore = MonitoringFlowTestSecretStore()
    let randomBytes = MonitoringFlowTestRandomBytes()
    let signingSecretData = Data(repeating: 0x5a, count: 32)
    let signingSecret = "whsec_\(signingSecretData.base64EncodedString())"
    let now = clock.now()
    let noteID = UUID()
    let initialNote = Note(
      id: noteID,
      title: "\(UUID().uuidString)-title",
      body: "\(UUID().uuidString)-body",
      createdAt: now,
      modifiedAt: now,
      agentAccess: true,
      revision: 1
    )
    let updatedNote = Note(
      id: noteID,
      title: "\(UUID().uuidString)-title",
      body: "\(UUID().uuidString)-body",
      createdAt: now,
      modifiedAt: now.addingTimeInterval(1),
      agentAccess: true,
      revision: 2
    )
    let secondUpdatedNote = Note(
      id: noteID,
      title: updatedNote.title + " continued",
      body: updatedNote.body + "\nSecond local edit",
      createdAt: now,
      modifiedAt: now.addingTimeInterval(2),
      agentAccess: true,
      revision: 3
    )
    let initialWorkspace = Workspace(notes: [initialNote], selectedNoteID: noteID)
    let localStore = LocalStore(rootURL: workspaceURL, now: { clock.now() })
    _ = try await localStore.save(
      workspace: initialWorkspace,
      preferences: .init(),
      generation: 1
    )

    let profilesURL = integrationsURL.appendingPathComponent("profiles.json")
    let profileStore = AgentProfileStore(
      profilesURL: profilesURL,
      secretStore: secretStore,
      randomBytes: randomBytes,
      now: { clock.now() }
    )
    let profile = try await profileStore.create(name: "Monitoring flow test")
    let profileID = profile.profile.id

    let capabilitiesURL = integrationsURL.appendingPathComponent("capabilities.json")
    let previousCapabilitiesURL = integrationsURL.appendingPathComponent(
      "capabilities.previous.json"
    )
    let capabilityStore = AgentCapabilityStore(
      capabilitiesURL: capabilitiesURL,
      previousCapabilitiesURL: previousCapabilitiesURL
    )
    let initialCapabilities = try await capabilityStore.loadOrMigrate(
      activeProfileIDs: [profileID],
      workspace: initialWorkspace
    )
    guard let initialProfile = initialCapabilities.profiles[profileID] else {
      throw AgentEventMonitoringFlowTestError.invalidExchange
    }
    let grantedProfile = AgentProfileCapabilities(
      profileID: profileID,
      grantRevision: initialProfile.grantRevision + 1,
      allowedCapabilities: [.readNotes],
      grants: [AgentResourceGrant(scope: .note(noteID: noteID), authority: .read)],
      allowsEventObservation: true
    )
    _ = try await capabilityStore.replaceProfile(
      grantedProfile,
      expectedGrantRevision: initialProfile.grantRevision
    )
    let authority = AgentCapabilityAuthority(store: capabilityStore)

    let callbackURL = "https://example.com/events"
    let subscriptionID = AgentEventSubscriptionIdentity.subscriptionID(
      profileID: profileID,
      event: .noteUpdated,
      scope: .note(noteID: noteID),
      callbackURL: callbackURL
    )
    let subscriptionURL = eventURL.appendingPathComponent("subscriptions.json")
    let verificationURL = eventURL.appendingPathComponent("verification.json")
    let outboxURL = eventURL.appendingPathComponent("outbox.json")
    let ledgerURL = eventURL.appendingPathComponent("ledger.json")
    let subscriptionStore = AgentEventSubscriptionStore(fileURL: subscriptionURL)
    let signingKeyStore = AgentEventSigningKeyStore(secretStore: secretStore)
    let subscriptionService = AgentEventSubscriptionService(
      authority: authority,
      store: subscriptionStore,
      signingKeyStore: signingKeyStore,
      clock: { clock.now() }
    )
    let workspaceProvider: AgentEventWorkspaceProvider = {
      let snapshot = try await localStore.loadSnapshot()
      return snapshot.workspace
    }
    _ = try await subscriptionService.createPending(
      profileID: profileID,
      event: .noteUpdated,
      scope: .note(noteID: noteID),
      callbackURL: callbackURL,
      signingSecret: signingSecret,
      workspaceProvider: workspaceProvider,
      now: now
    )

    let callbackExchange = MonitoringFlowCallbackExchange(
      callbackURL: callbackURL,
      secret: signingSecretData
    )
    let applicationExchange = MonitoringFlowApplicationExchange(
      callbackURL: callbackURL,
      subscriptionID: subscriptionID,
      secret: signingSecretData,
      statuses: applicationStatuses
    )
    let verificationStore = AgentEventCallbackVerificationStore(
      fileURL: verificationURL,
      now: { clock.now() }
    )
    let outboxStore = AgentEventOutboxStore(fileURL: outboxURL)
    let ledgerStore = AgentEventDeliveryLedgerStore(
      fileURL: ledgerURL,
      now: { clock.now() },
      jitterBasisPoints: { 0 }
    )
    let runtime = AgentEventMonitoringRuntime(
      localStore: localStore,
      profileStore: profileStore,
      authority: authority,
      subscriptionStore: subscriptionStore,
      verificationStore: verificationStore,
      outboxStore: outboxStore,
      ledgerStore: ledgerStore,
      signingKeyStore: signingKeyStore,
      clock: clock,
      callbackExchange: callbackExchange,
      applicationExchange: applicationExchange,
      randomBytes: randomBytes
    )
    let fixture = AgentEventMonitoringFlowFixture(
      rootURL: rootURL,
      ownedRoot: ownedRoot,
      workspaceURL: workspaceURL,
      profilesURL: profilesURL,
      capabilitiesURL: capabilitiesURL,
      previousCapabilitiesURL: previousCapabilitiesURL,
      subscriptionURL: subscriptionURL,
      verificationURL: verificationURL,
      outboxURL: outboxURL,
      ledgerURL: ledgerURL,
      profileID: profileID,
      subscriptionID: subscriptionID,
      initialNote: initialNote,
      updatedNote: updatedNote,
      secondUpdatedNote: secondUpdatedNote,
      integrationBody: "\(UUID().uuidString)-integration-body",
      clock: clock,
      secretStore: secretStore,
      randomBytes: randomBytes,
      callbackExchange: callbackExchange,
      applicationExchange: applicationExchange,
      runtime: runtime
    )
    ownershipTransferred = true
    return fixture
  }

  func workspaceProvider(from runtime: AgentEventMonitoringRuntime) -> AgentEventWorkspaceProvider {
    let localStore = runtime.localStore
    return {
      let snapshot = try await localStore.loadSnapshot()
      return snapshot.workspace
    }
  }

  func enableOwnerDelivery(for binding: AgentEventCallbackVerificationBinding) async throws {
    guard
      let subscription = try await runtime.subscriptionStore.currentSubscription(
        id: subscriptionID
      )
    else {
      throw AgentEventMonitoringFlowTestError.ownerConsentNotSaved
    }
    let control = try await runtime.subscriptionStore.setOwnerDeliveryEligibility(
      binding: binding,
      expectedGenerationID: subscription.deliveryControl?.generationID,
      eligible: true
    )
    guard control?.enabled == true else {
      throw AgentEventMonitoringFlowTestError.ownerConsentNotSaved
    }
  }

  func pendingBinding() async throws -> AgentEventCallbackVerificationBinding {
    guard
      let subscription = try await runtime.subscriptionStore.currentSubscription(
        id: subscriptionID
      )
    else {
      throw AgentEventMonitoringFlowTestError.ownerConsentNotSaved
    }
    return AgentEventCallbackVerificationBinding(
      profileID: subscription.profileID,
      subscriptionID: subscription.subscriptionID,
      subscriptionRevision: subscription.revision,
      grantRevision: subscription.grantRevision,
      signingKeyReference: subscription.signingKeyReference
    )
  }

  func saveUpdatedNote() async throws {
    _ = try await runtime.localStore.save(
      workspace: updatedWorkspace,
      preferences: .init(),
      generation: 2
    )
  }

  func saveSecondLocalNote() async throws {
    _ = try await runtime.localStore.save(
      workspace: Workspace(
        notes: [secondUpdatedNote],
        selectedNoteID: secondUpdatedNote.id
      ),
      preferences: .init(),
      generation: 3
    )
  }

  func integrationProof(for note: Note) -> AgentWorkspaceCommitProof {
    let digest = SHA256.hash(data: Data(note.body.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
    return AgentWorkspaceCommitProof(
      changeID: UUID(),
      noteID: note.id,
      resultingRevision: note.revision,
      bodySHA256: digest,
      actor: .integration(profileID: profileID, displayName: "Synthetic integration"),
      operationID: UUID(),
      expiresAt: clock.now().addingTimeInterval(600)
    )
  }

  func makeReopenedRuntime() -> AgentEventMonitoringRuntime {
    let localStore = LocalStore(rootURL: workspaceURL, now: { clock.now() })
    let profileStore = AgentProfileStore(
      profilesURL: profilesURL,
      secretStore: secretStore,
      randomBytes: randomBytes,
      now: { clock.now() }
    )
    let capabilityStore = AgentCapabilityStore(
      capabilitiesURL: capabilitiesURL,
      previousCapabilitiesURL: previousCapabilitiesURL
    )
    let authority = AgentCapabilityAuthority(store: capabilityStore)
    let subscriptionStore = AgentEventSubscriptionStore(fileURL: subscriptionURL)
    let verificationStore = AgentEventCallbackVerificationStore(
      fileURL: verificationURL,
      now: { clock.now() }
    )
    let outboxStore = AgentEventOutboxStore(fileURL: outboxURL)
    let ledgerStore = AgentEventDeliveryLedgerStore(
      fileURL: ledgerURL,
      now: { clock.now() },
      jitterBasisPoints: { 0 }
    )
    let signingKeyStore = AgentEventSigningKeyStore(secretStore: secretStore)
    return AgentEventMonitoringRuntime(
      localStore: localStore,
      profileStore: profileStore,
      authority: authority,
      subscriptionStore: subscriptionStore,
      verificationStore: verificationStore,
      outboxStore: outboxStore,
      ledgerStore: ledgerStore,
      signingKeyStore: signingKeyStore,
      clock: clock,
      callbackExchange: callbackExchange,
      applicationExchange: applicationExchange,
      randomBytes: randomBytes
    )
  }

  func ledgerDocument() throws -> AgentEventDeliveryLedgerDocument {
    try JSONDecoder().decode(
      AgentEventDeliveryLedgerDocument.self,
      from: Data(contentsOf: ledgerURL)
    )
  }

  func remove() {
    do {
      try ownedRoot.cleanup()
    } catch {
      Issue.record("Monitoring flow fixture cleanup failed: \(error)")
    }
  }
}
