import FleckCore
import FleckMCPFixtureSupport
import Foundation
import Testing

@testable import FleckApp

@Suite(.serialized)
struct AgentEventCallbackVerificationTests {
  @Test func validEchoPersistsBoundProofAndUsesItOnlyAfterFreshAuthorization() async throws {
    let fixture = try await CallbackVerificationFixture.make()
    defer { fixture.remove() }
    let exchange = CallbackVerificationTestExchange { request in
      try makeEchoResponse(for: request)
    }
    let service = fixture.service(exchange: exchange)
    let intentObservation = CallbackVerificationIntentObservation()
    fixture.secretStore.observeSigningKeyRead {
      intentObservation.read(fixture.verificationURL)
    }

    let proof = try await service.verifyPending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      workspaceProvider: fixture.workspaceProvider
    )
    let request = try #require(await exchange.requests().first)
    let payload = try JSONDecoder().decode(CallbackVerificationRequest.self, from: request.body)
    let headers = Dictionary(uniqueKeysWithValues: request.headers.map { ($0.name, $0.value) })
    let signedTimestamp = try #require(Int64(headers["webhook-timestamp"] ?? ""))
    let expectedSignature = try AgentEventWebhookSigner.sign(
      id: try #require(headers["webhook-id"]),
      timestamp: Date(timeIntervalSince1970: TimeInterval(signedTimestamp)),
      body: request.body,
      secret: fixture.signingSecret
    )
    let serializedStore = String(
      decoding: try Data(contentsOf: fixture.verificationURL),
      as: UTF8.self
    )
    let subscription = try #require(
      await fixture.subscriptionStore.currentSubscription(id: fixture.subscriptionID)
    )

    #expect(intentObservation.value())
    #expect(request.callbackURL == fixture.callbackURL)
    #expect(
      request.headers.map(\.name) == [
        "content-type", "webhook-id", "webhook-timestamp", "webhook-signature",
        "x-mcp-subscription-id",
      ])
    #expect(headers["content-type"] == "application/json")
    #expect(headers["x-mcp-subscription-id"] == fixture.subscriptionID)
    #expect(headers["webhook-id"]?.hasPrefix("msg_verification_") == true)
    #expect(headers["webhook-signature"] == expectedSignature.webhookSignature)
    #expect(payload.type == "verification")
    #expect(payload.challenge.utf8.count == 43)
    #expect(
      payload.challenge.utf8.allSatisfy {
        (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
          || $0 == 45 || $0 == 95
      })
    #expect(proof.binding.profileID == fixture.profileID)
    #expect(proof.binding.subscriptionID == fixture.subscriptionID)
    #expect(proof.binding.subscriptionRevision == subscription.revision)
    #expect(proof.binding.grantRevision == subscription.grantRevision)
    #expect(proof.binding.signingKeyReference == subscription.signingKeyReference)
    #expect(proof.expiresAt <= proof.verifiedAt.addingTimeInterval(600))
    #expect(proof.expiresAt <= subscription.expiresAt)
    let verificationDocument = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: fixture.verificationURL))
        as? [String: Any]
    )
    #expect(verificationDocument["schemaVersion"] as? Int == 3)
    let endpointEntries = try #require(verificationDocument["endpointCache"] as? [[String: Any]])
    let endpointEntry = try #require(endpointEntries.first)
    #expect(endpointEntries.count == 1)
    #expect(
      endpointEntry["canonicalCallbackURLDigest"]
        as? String
        == AgentEventCallbackVerificationStore.canonicalURLSHA256Digest(fixture.callbackURL)
    )
    #expect(endpointEntry["canonicalCallbackURL"] == nil)
    let storedProof = try #require(
      (verificationDocument["proofs"] as? [[String: Any]])?.first
    )
    #expect(storedProof["originIntentID"] as? String == proof.originIntentID.uuidString)
    #expect(!serializedStore.contains(payload.challenge))
    #expect(!serializedStore.contains(fixture.callbackURL))
    #expect(
      !serializedStore.contains(
        fixture.callbackURL.replacingOccurrences(of: "/", with: "\\/")
      )
    )
    #expect(!serializedStore.contains(fixture.signingSecret.base64EncodedString()))
    #expect(fixture.secretStore.signingKeyReadCount() == 1)
    #expect(await exchange.requestCount() == 1)
    #expect(subscription.status == .pending)
    #expect(!FileManager.default.fileExists(atPath: fixture.outboxURL.path))

    let cached = try await service.verifyPending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      workspaceProvider: fixture.workspaceProvider
    )
    #expect(cached == proof)
    #expect(fixture.secretStore.signingKeyReadCount() == 1)
    #expect(await exchange.requestCount() == 1)
  }

  @Test func cancellationAfterProofCommitRemovesRequestOwnedIntentAndProof() async throws {
    let fixture = try await CallbackVerificationFixture.make()
    defer { fixture.remove() }
    let gate = CallbackVerificationAsyncGate()
    let workspaces = CallbackVerificationAsyncWorkspaceOverrideSequence(fixture.workspace) {
      if $0 == 8 { await gate.pause() }
      return nil
    }
    let exchange = CallbackVerificationTestExchange { request in
      try makeEchoResponse(for: request)
    }
    let requestOriginID = UUID()
    let task = Task {
      try await fixture.service(exchange: exchange).verifyPending(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID,
        workspaceProvider: { try await workspaces.next() },
        requestOriginID: requestOriginID
      )
    }
    defer {
      task.cancel()
      Task { await gate.release() }
    }
    await gate.waitUntilPaused()
    let committedProof = try? fixture.verificationStore.currentProof(for: fixture.binding)

    task.cancel()
    await gate.release()
    #expect(committedProof?.originIntentID == requestOriginID)
    do {
      _ = try await task.value
      Issue.record("Expected cancellation to remove the request-owned proof.")
    } catch is CancellationError {
    }

    let verificationDocument = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: fixture.verificationURL))
        as? [String: Any]
    )
    #expect((verificationDocument["intents"] as? [[String: Any]])?.isEmpty == true)
    #expect((verificationDocument["proofs"] as? [[String: Any]])?.isEmpty == true)
    #expect(try fixture.verificationStore.currentProof(for: fixture.binding) == nil)
    #expect(await exchange.requestCount() == 1)
  }

  @Test func sameSecretRefreshMaterializesFreshProofWithoutExtendingEndpointCache() async throws {
    let fixture = try await CallbackVerificationFixture.make()
    defer { fixture.remove() }
    let exchange = CallbackVerificationTestExchange { request in
      try makeEchoResponse(for: request)
    }
    let original = try await fixture.service(exchange: exchange).verifyPending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      workspaceProvider: fixture.workspaceProvider
    )
    let firstSubscription = try #require(
      await fixture.subscriptionStore.currentSubscription(id: fixture.subscriptionID)
    )
    let service = AgentEventSubscriptionService(
      authority: fixture.authority,
      store: fixture.subscriptionStore,
      signingKeyStore: fixture.signingKeyStore
    )
    fixture.clock.set(fixture.date.addingTimeInterval(100))
    _ = try await service.createPending(
      profileID: fixture.profileID,
      event: .noteUpdated,
      scope: firstSubscription.scope,
      callbackURL: fixture.callbackURL,
      signingSecret: "whsec_\(fixture.signingSecret.base64EncodedString())",
      requestedTTLSeconds: 3_600,
      workspaceProvider: fixture.workspaceProvider,
      now: fixture.clock.now()
    )

    let refreshed = try #require(
      await fixture.subscriptionStore.currentSubscription(id: fixture.subscriptionID)
    )
    let reused = try await fixture.service(exchange: exchange).verifyPending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      workspaceProvider: fixture.workspaceProvider
    )

    #expect(refreshed.revision == firstSubscription.revision + 1)
    #expect(refreshed.signingKeyReference == firstSubscription.signingKeyReference)
    #expect(reused.binding.subscriptionRevision == refreshed.revision)
    #expect(reused.binding.grantRevision == refreshed.grantRevision)
    #expect(reused.binding.signingKeyReference == refreshed.signingKeyReference)
    #expect(reused.originIntentID != original.originIntentID)
    #expect(reused.verifiedAt == original.verifiedAt)
    #expect(reused.expiresAt == original.expiresAt)
    #expect(fixture.secretStore.signingKeyReadCount() == 3)
    #expect(await exchange.requestCount() == 1)

    fixture.clock.set(original.expiresAt)
    let afterDeadline = try await fixture.service(exchange: exchange).verifyPending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      workspaceProvider: fixture.workspaceProvider
    )
    #expect(afterDeadline.verifiedAt == original.expiresAt)
    #expect(afterDeadline.originIntentID != reused.originIntentID)
    #expect(fixture.secretStore.signingKeyReadCount() == 4)
    #expect(await exchange.requestCount() == 2)
  }

  @Test func endpointCacheMissDoesNotPersistAnEmptyVerificationDocument() async throws {
    let fixture = try await CallbackVerificationFixture.make()
    defer { fixture.remove() }

    #expect(
      try fixture.verificationStore.endpointCacheEntry(
        profileID: fixture.profileID,
        canonicalCallbackURL: fixture.callbackURL,
        grantRevision: fixture.grantRevision,
        signingKeyReference: fixture.keyReference
      ) == nil
    )
    #expect(!FileManager.default.fileExists(atPath: fixture.verificationURL.path))
  }

  @Test func changedSigningKeyMissesEndpointCacheAndVerifiesWithReplacementKey() async throws {
    let fixture = try await CallbackVerificationFixture.make()
    defer { fixture.remove() }
    let exchange = CallbackVerificationTestExchange { request in
      try makeEchoResponse(for: request)
    }
    _ = try await fixture.service(exchange: exchange).verifyPending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      workspaceProvider: fixture.workspaceProvider
    )
    let initial = try #require(
      await fixture.subscriptionStore.currentSubscription(id: fixture.subscriptionID)
    )
    let replacementSecret = Data(repeating: 0x6b, count: 32)
    fixture.clock.set(fixture.date.addingTimeInterval(1))
    _ = try await AgentEventSubscriptionService(
      authority: fixture.authority,
      store: fixture.subscriptionStore,
      signingKeyStore: fixture.signingKeyStore
    ).createPending(
      profileID: fixture.profileID,
      event: .noteUpdated,
      scope: initial.scope,
      callbackURL: fixture.callbackURL,
      signingSecret: "whsec_\(replacementSecret.base64EncodedString())",
      requestedTTLSeconds: 3_600,
      workspaceProvider: fixture.workspaceProvider,
      now: fixture.date.addingTimeInterval(1)
    )

    let proof = try await fixture.service(exchange: exchange).verifyPending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      workspaceProvider: fixture.workspaceProvider
    )
    let current = try #require(
      await fixture.subscriptionStore.currentSubscription(id: fixture.subscriptionID)
    )
    let requests = await exchange.requests()
    let replacementRequest = try #require(requests.last)
    let headers = Dictionary(uniqueKeysWithValues: replacementRequest.headers.map { ($0.name, $0.value) })
    let timestamp = try #require(Int64(headers["webhook-timestamp"] ?? ""))
    let expectedSignature = try AgentEventWebhookSigner.sign(
      id: try #require(headers["webhook-id"]),
      timestamp: Date(timeIntervalSince1970: TimeInterval(timestamp)),
      body: replacementRequest.body,
      secret: replacementSecret
    )

    #expect(requests.count == 2)
    #expect(try decodeChallenge(from: requests[0].body) != decodeChallenge(from: requests[1].body))
    #expect(current.signingKeyReference != initial.signingKeyReference)
    #expect(proof.binding.signingKeyReference == current.signingKeyReference)
    #expect(headers["webhook-signature"] == expectedSignature.webhookSignature)
    #expect(fixture.secretStore.signingKeyReadCount() == 3)
  }

  @Test func schemaTwoProofsLoadWithoutInventingEndpointEvidence() async throws {
    let fixture = try await CallbackVerificationFixture.make()
    defer { fixture.remove() }
    let exchange = CallbackVerificationTestExchange { request in
      try makeEchoResponse(for: request)
    }
    let proof = try await fixture.service(exchange: exchange).verifyPending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      workspaceProvider: fixture.workspaceProvider
    )
    var document = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: fixture.verificationURL)) as? [String: Any]
    )
    document["schemaVersion"] = 2
    document.removeValue(forKey: "endpointCache")
    try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
      .write(to: fixture.verificationURL, options: .atomic)
    let legacyStore = AgentEventCallbackVerificationStore(
      fileURL: fixture.verificationURL,
      now: { fixture.clock.now() }
    )

    #expect(try legacyStore.currentProof(for: fixture.binding) == proof)
    #expect(
      try legacyStore.endpointCacheEntry(
        profileID: fixture.profileID,
        canonicalCallbackURL: fixture.callbackURL,
        grantRevision: fixture.grantRevision,
        signingKeyReference: fixture.keyReference
      ) == nil
    )
    #expect(await exchange.requestCount() == 1)
  }

  @Test func schemaThreeRejectsMalformedEndpointEvidenceWithoutRewriting() async throws {
    let fixture = try await CallbackVerificationFixture.make()
    defer { fixture.remove() }
    let exchange = CallbackVerificationTestExchange { request in
      try makeEchoResponse(for: request)
    }
    _ = try await fixture.service(exchange: exchange).verifyPending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      workspaceProvider: fixture.workspaceProvider
    )
    let original = try Data(contentsOf: fixture.verificationURL)
    let validDocument = try #require(
      JSONSerialization.jsonObject(with: original) as? [String: Any]
    )
    let validEntries = try #require(validDocument["endpointCache"] as? [[String: Any]])
    let validEntry = try #require(validEntries.first)
    var nullArray = validDocument
    nullArray["endpointCache"] = NSNull()
    var unknownField = validDocument
    var unknownEntries = validEntries
    unknownEntries[0]["unexpected"] = true
    unknownField["endpointCache"] = unknownEntries
    var invalidDigest = validDocument
    var invalidDigestEntries = validEntries
    invalidDigestEntries[0]["canonicalCallbackURLDigest"] = String(repeating: "g", count: 64)
    invalidDigest["endpointCache"] = invalidDigestEntries
    var duplicateKey = validDocument
    duplicateKey["endpointCache"] = [validEntry, validEntry]
    let invalidDocuments = [nullArray, unknownField, invalidDigest, duplicateKey]

    for document in invalidDocuments {
      let corrupted = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
      try corrupted.write(to: fixture.verificationURL, options: .atomic)

      #expect(
        throws: AgentEventCallbackVerificationStoreError.storageFailure
      ) {
        try fixture.verificationStore.endpointCacheEntry(
          profileID: fixture.profileID,
          canonicalCallbackURL: fixture.callbackURL,
          grantRevision: fixture.grantRevision,
          signingKeyReference: fixture.keyReference
        )
      }
      #expect(try Data(contentsOf: fixture.verificationURL) == corrupted)
    }
    #expect(await exchange.requestCount() == 1)
  }

  @Test func endpointCacheEvictsOldestEntryAtItsFixedLimit() async throws {
    let fixture = try await CallbackVerificationFixture.make()
    defer { fixture.remove() }
    let store = fixture.verificationStore
    var candidates: [(profileID: UUID, url: String, reference: String, key: String)] = []
    for index in 0..<129 {
      let profileID = UUID()
      let url = "https://example.com/cache/\(index)"
      let reference = UUID().uuidString.lowercased()
      let digest = try #require(
        AgentEventCallbackVerificationStore.canonicalURLSHA256Digest(url)
      )
      let key = "\(profileID.uuidString.lowercased())\u{0}\(digest)"
      let binding = fixture.binding(
        subscriptionID: "evt_\(String(format: "%064x", index + 1))",
        profileID: profileID,
        keyReference: reference
      )
      let intent = fixture.intent(
        id: UUID(),
        nonceByte: UInt8(truncatingIfNeeded: index + 1),
        binding: binding
      )
      try store.begin(intent)
      let proof = try store.complete(
        intent,
        subscriptionExpiresAt: fixture.date.addingTimeInterval(3_600),
        canonicalCallbackURL: url
      )
      try store.removeProof(for: binding, generatedBy: proof.originIntentID)
      candidates.append((profileID, url, reference, key))
    }
    let document = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: fixture.verificationURL)) as? [String: Any]
    )
    let entries = try #require(document["endpointCache"] as? [[String: Any]])
    let cacheKeys = Set(entries.compactMap { entry -> String? in
      guard let profile = entry["profileID"] as? String,
        let digest = entry["canonicalCallbackURLDigest"] as? String
      else {
        return nil
      }
      return "\(profile.lowercased())\u{0}\(digest)"
    })
    let oldest = try #require(candidates.min { $0.key < $1.key })
    let newest = try #require(candidates.last)

    #expect(entries.count == 128)
    #expect(!cacheKeys.contains(oldest.key))
    #expect(
      try store.endpointCacheEntry(
        profileID: oldest.profileID,
        canonicalCallbackURL: oldest.url,
        grantRevision: fixture.grantRevision,
        signingKeyReference: oldest.reference
      ) == nil
    )
    #expect(
      try store.endpointCacheEntry(
        profileID: newest.profileID,
        canonicalCallbackURL: newest.url,
        grantRevision: fixture.grantRevision,
        signingKeyReference: newest.reference
      ) != nil
    )
  }

  @Test func restartedServiceReturnsPersistedProofWithoutReadingKeyAgain() async throws {
    let fixture = try await CallbackVerificationFixture.make()
    defer { fixture.remove() }
    let firstExchange = CallbackVerificationTestExchange { request in
      try makeEchoResponse(for: request)
    }
    let proof = try await fixture.service(exchange: firstExchange).verifyPending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      workspaceProvider: fixture.workspaceProvider
    )
    let restartedExchange = CallbackVerificationTestExchange { _ in
      throw CallbackVerificationTestError.unexpectedRequest
    }
    let restartedStore = AgentEventCallbackVerificationStore(
      fileURL: fixture.verificationURL,
      now: { fixture.clock.now() }
    )
    let restarted = fixture.service(exchange: restartedExchange, verificationStore: restartedStore)

    let reloaded = try await restarted.verifyPending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      workspaceProvider: fixture.workspaceProvider
    )

    #expect(reloaded == proof)
    #expect(fixture.secretStore.signingKeyReadCount() == 1)
    #expect(await restartedExchange.requestCount() == 0)
  }

  @Test func cachedProofRequiresFreshAuthorizationBeforeReturn() async throws {
    let fixture = try await CallbackVerificationFixture.make()
    defer { fixture.remove() }
    let exchange = CallbackVerificationTestExchange { request in
      try makeEchoResponse(for: request)
    }
    let service = fixture.service(exchange: exchange)
    _ = try await service.verifyPending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      workspaceProvider: fixture.workspaceProvider
    )
    let sequence = CallbackVerificationWorkspaceSequence([
      fixture.workspace,
      Workspace(),
    ])

    await #expect(throws: AgentEventCallbackVerificationError.notAuthorized) {
      try await service.verifyPending(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID,
        workspaceProvider: { sequence.next() }
      )
    }

    #expect(fixture.secretStore.signingKeyReadCount() == 1)
    #expect(await exchange.requestCount() == 1)
    #expect(
      try fixture.verificationStore.currentProof(
        for: fixture.binding
      ) == nil)
  }

  @Test func wrongMalformedOversizedNonSuccessAndExpiredEchoesFailClosed() async throws {
    enum ResponseKind: CaseIterable {
      case wrongEcho
      case malformed
      case oversized
      case nonSuccess
      case expired
    }

    for kind in ResponseKind.allCases {
      let fixture = try await CallbackVerificationFixture.make()
      defer { fixture.remove() }
      let exchange = CallbackVerificationTestExchange { request in
        let challenge = try decodeChallenge(from: request.body)
        switch kind {
        case .wrongEcho:
          return try makeEchoResponse(challenge: "different")
        case .malformed:
          return AgentEventHTTPResponse(statusCode: 200, body: Data("not-json".utf8))
        case .oversized:
          return AgentEventHTTPResponse(
            statusCode: 200,
            body: Data(repeating: 0x20, count: 1_025)
          )
        case .nonSuccess:
          return try makeEchoResponse(challenge: challenge, statusCode: 302)
        case .expired:
          fixture.clock.set(fixture.date.addingTimeInterval(61))
          return try makeEchoResponse(challenge: challenge)
        }
      }

      await #expect(throws: AgentEventCallbackVerificationError.verificationFailed) {
        try await fixture.service(exchange: exchange).verifyPending(
          profileID: fixture.profileID,
          subscriptionID: fixture.subscriptionID,
          workspaceProvider: fixture.workspaceProvider
        )
      }
      #expect(fixture.secretStore.signingKeyReadCount() == 1)
      #expect(await exchange.requestCount() == 1)
      #expect(
        try fixture.verificationStore.currentProof(
          for: fixture.binding
        ) == nil)
    }
  }

  @Test func challengeExpiresAfterSixtySecondsAndAStaleReplyCannotReplaceNewIntent()
    async throws
  {
    let fixture = try await CallbackVerificationFixture.make()
    defer { fixture.remove() }
    let firstStore = fixture.verificationStore
    let firstIntent = fixture.intent(id: UUID(), nonceByte: 1)
    try firstStore.begin(firstIntent)
    try firstStore.cancel(firstIntent)
    let secondIntent = fixture.intent(id: UUID(), nonceByte: 2)
    let secondStore = AgentEventCallbackVerificationStore(
      fileURL: fixture.verificationURL,
      now: { fixture.clock.now() }
    )
    try secondStore.begin(secondIntent)
    #expect(throws: AgentEventCallbackVerificationStoreError.staleIntent) {
      try firstStore.complete(
        firstIntent,
        subscriptionExpiresAt: fixture.date.addingTimeInterval(3_600)
      )
    }
    let document = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: fixture.verificationURL))
        as? [String: Any]
    )
    let intents = try #require(document["intents"] as? [[String: Any]])
    let proofs = try #require(document["proofs"] as? [[String: Any]])
    #expect(intents.count == 1)
    #expect(proofs.isEmpty)
    #expect(intents.first?["id"] as? String == secondIntent.id.uuidString)
  }

  @Test func intentWriteFailureSendsNoHTTPAndActualAfterWriteCommitIsPreserved() async throws {
    let fixture = try await CallbackVerificationFixture.make()
    defer { fixture.remove() }
    let failedWriter = CallbackVerificationFileWriter(failBeforeWriteNumbers: [1])
    let failedStore = fixture.verificationStore(using: failedWriter)
    let failedExchange = CallbackVerificationTestExchange { request in
      try makeEchoResponse(for: request)
    }
    let failedService = fixture.service(
      exchange: failedExchange,
      verificationStore: failedStore
    )

    await #expect(throws: AgentEventCallbackVerificationError.storageFailure) {
      try await failedService.verifyPending(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID,
        workspaceProvider: fixture.workspaceProvider
      )
    }
    #expect(fixture.secretStore.signingKeyReadCount() == 0)
    #expect(await failedExchange.requestCount() == 0)
    #expect(failedWriter.writeCount() == 1)

    let afterWriteFixture = try await CallbackVerificationFixture.make()
    defer { afterWriteFixture.remove() }
    let afterWriteWriter = CallbackVerificationFileWriter(failAfterWriteNumbers: [1])
    let afterWriteStore = afterWriteFixture.verificationStore(using: afterWriteWriter)
    let exchange = CallbackVerificationTestExchange { request in
      try makeEchoResponse(for: request)
    }
    let proof = try await afterWriteFixture.service(
      exchange: exchange,
      verificationStore: afterWriteStore
    ).verifyPending(
      profileID: afterWriteFixture.profileID,
      subscriptionID: afterWriteFixture.subscriptionID,
      workspaceProvider: afterWriteFixture.workspaceProvider
    )

    #expect(proof.binding == afterWriteFixture.binding)
    #expect(afterWriteWriter.writeCount() >= 3)
    #expect(afterWriteFixture.secretStore.signingKeyReadCount() == 1)
    #expect(await exchange.requestCount() == 1)
    #expect(
      try afterWriteStore.currentProof(for: afterWriteFixture.binding)
        == proof)
  }

  @Test func proofWriteFailureCannotReturnSuccessButCommittedAfterWriteIsAccepted() async throws {
    let fixture = try await CallbackVerificationFixture.make()
    defer { fixture.remove() }
    let failedWriter = CallbackVerificationFileWriter(failBeforeWriteNumbers: [4])
    let failedStore = fixture.verificationStore(using: failedWriter)
    let failedExchange = CallbackVerificationTestExchange { request in
      try makeEchoResponse(for: request)
    }

    await #expect(throws: AgentEventCallbackVerificationError.storageFailure) {
      try await fixture.service(
        exchange: failedExchange,
        verificationStore: failedStore
      ).verifyPending(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID,
        workspaceProvider: fixture.workspaceProvider
      )
    }
    #expect(fixture.secretStore.signingKeyReadCount() == 1)
    #expect(await failedExchange.requestCount() == 1)
    try expectProofCommitWrite(failedWriter)
    #expect(try failedStore.currentProof(for: fixture.binding) == nil)

    let afterWriteFixture = try await CallbackVerificationFixture.make()
    defer { afterWriteFixture.remove() }
    let afterWriteWriter = CallbackVerificationFileWriter(failAfterWriteNumbers: [4])
    let afterWriteStore = afterWriteFixture.verificationStore(using: afterWriteWriter)
    let afterWriteExchange = CallbackVerificationTestExchange { request in
      try makeEchoResponse(for: request)
    }
    let committed = try await afterWriteFixture.service(
      exchange: afterWriteExchange,
      verificationStore: afterWriteStore
    ).verifyPending(
      profileID: afterWriteFixture.profileID,
      subscriptionID: afterWriteFixture.subscriptionID,
      workspaceProvider: afterWriteFixture.workspaceProvider
    )

    #expect(afterWriteWriter.writeCount() >= 4)
    #expect(afterWriteFixture.secretStore.signingKeyReadCount() == 1)
    #expect(await afterWriteExchange.requestCount() == 1)
    try expectProofCommitWrite(afterWriteWriter)
    #expect(
      try afterWriteStore.currentProof(
        for: afterWriteFixture.binding
      ) == committed)
  }

  @Test func missingKeyIsReadOnlyAfterDurableIntentAndNeverSendsHTTP() async throws {
    let fixture = try await CallbackVerificationFixture.make()
    defer { fixture.remove() }
    fixture.secretStore.removeSigningKey(reference: fixture.keyReference)
    let exchange = CallbackVerificationTestExchange { request in
      try makeEchoResponse(for: request)
    }
    let intentObservation = CallbackVerificationIntentObservation()
    fixture.secretStore.observeSigningKeyRead {
      intentObservation.read(fixture.verificationURL)
    }

    await #expect(throws: AgentEventCallbackVerificationError.keyUnavailable) {
      try await fixture.service(exchange: exchange).verifyPending(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID,
        workspaceProvider: fixture.workspaceProvider
      )
    }

    #expect(intentObservation.value())
    #expect(fixture.secretStore.signingKeyReadCount() == 1)
    #expect(await exchange.requestCount() == 0)
  }

  @Test func expiredIntentStopsBeforeSigningKeyRead() async throws {
    let fixture = try await CallbackVerificationFixture.make()
    defer { fixture.remove() }
    let sequence = CallbackVerificationWorkspaceSequence(
      Array(repeating: fixture.workspace, count: 3),
      onRequest: { request in
        if request == 3 {
          fixture.clock.set(fixture.date.addingTimeInterval(61))
        }
      }
    )
    let exchange = CallbackVerificationTestExchange { request in
      try makeEchoResponse(for: request)
    }

    await #expect(throws: AgentEventCallbackVerificationError.verificationFailed) {
      try await fixture.service(exchange: exchange).verifyPending(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID,
        workspaceProvider: { sequence.next() }
      )
    }

    #expect(fixture.secretStore.signingKeyReadCount() == 0)
    #expect(await exchange.requestCount() == 0)
    #expect(
      try fixture.verificationStore.currentProof(
        for: fixture.binding
      ) == nil)
  }

  @Test func intentClockRollbackAfterAuthorizationStopsBeforeSigningKeyRead() async throws {
    let fixture = try await CallbackVerificationFixture.make()
    defer { fixture.remove() }
    let gate = CallbackVerificationAsyncGate()
    let workspaces = CallbackVerificationAsyncWorkspaceOverrideSequence(fixture.workspace) {
      if $0 == 3 { await gate.pause() }
      return nil
    }
    let exchange = CallbackVerificationTestExchange { request in
      try makeEchoResponse(for: request)
    }
    let verification = Task {
      try await fixture.service(exchange: exchange).verifyPending(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID,
        workspaceProvider: { try await workspaces.next() }
      )
    }

    await gate.waitUntilPaused()
    #expect(fixture.secretStore.signingKeyReadCount() == 0)
    #expect(await exchange.requestCount() == 0)

    let rollback = try observeIntentClockRollback(in: fixture)
    try expectVerificationDocument(
      rollback.before,
      intentCount: 1,
      proofCount: 0,
      lastObservedAt: fixture.date
    )
    try expectVerificationDocument(
      rollback.after,
      intentCount: 0,
      proofCount: 0,
      lastObservedAt: rollback.highWater
    )
    #expect(fixture.secretStore.signingKeyReadCount() == 0)
    #expect(await exchange.requestCount() == 0)

    await gate.release()
    await #expect(throws: AgentEventCallbackVerificationError.storageFailure) {
      try await verification.value
    }
    #expect(fixture.secretStore.signingKeyReadCount() == 0)
    #expect(await exchange.requestCount() == 0)
    #expect(try Data(contentsOf: fixture.verificationURL) == rollback.after)
    try expectVerificationDocument(
      rollback.after,
      intentCount: 0,
      proofCount: 0,
      lastObservedAt: rollback.highWater
    )

    fixture.clock.set(rollback.highWater)
    let restartedStore = AgentEventCallbackVerificationStore(
      fileURL: fixture.verificationURL,
      now: { fixture.clock.now() }
    )
    #expect(try restartedStore.currentProof(for: fixture.binding) == nil)
    #expect(try Data(contentsOf: fixture.verificationURL) == rollback.after)
    try expectVerificationDocument(
      rollback.after,
      intentCount: 0,
      proofCount: 0,
      lastObservedAt: rollback.highWater
    )
  }

  @Test func intentClockRollbackAfterRequestAuthorizationPreventsHTTPExchange() async throws {
    let fixture = try await CallbackVerificationFixture.make()
    defer { fixture.remove() }
    let gate = CallbackVerificationAsyncGate()
    let workspaces = CallbackVerificationAsyncWorkspaceOverrideSequence(fixture.workspace) {
      if $0 == 4 { await gate.pause() }
      return nil
    }
    let exchange = CallbackVerificationTestExchange { request in
      try makeEchoResponse(for: request)
    }
    let verification = Task {
      try await fixture.service(exchange: exchange).verifyPending(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID,
        workspaceProvider: { try await workspaces.next() }
      )
    }

    await gate.waitUntilPaused()
    #expect(fixture.secretStore.signingKeyReadCount() == 1)
    #expect(await exchange.requestCount() == 0)

    let rollback = try observeIntentClockRollback(in: fixture)
    try expectVerificationDocument(
      rollback.before,
      intentCount: 1,
      proofCount: 0,
      lastObservedAt: fixture.date
    )
    try expectVerificationDocument(
      rollback.after,
      intentCount: 0,
      proofCount: 0,
      lastObservedAt: rollback.highWater
    )
    #expect(fixture.secretStore.signingKeyReadCount() == 1)
    #expect(await exchange.requestCount() == 0)

    await gate.release()
    await #expect(throws: AgentEventCallbackVerificationError.storageFailure) {
      try await verification.value
    }
    #expect(fixture.secretStore.signingKeyReadCount() == 1)
    #expect(await exchange.requestCount() == 0)
    #expect(try Data(contentsOf: fixture.verificationURL) == rollback.after)
    try expectVerificationDocument(
      rollback.after,
      intentCount: 0,
      proofCount: 0,
      lastObservedAt: rollback.highWater
    )

    fixture.clock.set(rollback.highWater)
    let restartedStore = AgentEventCallbackVerificationStore(
      fileURL: fixture.verificationURL,
      now: { fixture.clock.now() }
    )
    #expect(try restartedStore.currentProof(for: fixture.binding) == nil)
    #expect(try Data(contentsOf: fixture.verificationURL) == rollback.after)
    try expectVerificationDocument(
      rollback.after,
      intentCount: 0,
      proofCount: 0,
      lastObservedAt: rollback.highWater
    )
  }

  @Test func unauthorizedOwnerOrWorkspaceMakesNoKeyReadOrRequest() async throws {
    let fixture = try await CallbackVerificationFixture.make()
    defer { fixture.remove() }
    let exchange = CallbackVerificationTestExchange { request in
      try makeEchoResponse(for: request)
    }
    let service = fixture.service(exchange: exchange)

    await #expect(throws: AgentEventCallbackVerificationError.notAuthorized) {
      try await service.verifyPending(
        profileID: UUID(),
        subscriptionID: fixture.subscriptionID,
        workspaceProvider: fixture.workspaceProvider
      )
    }
    await #expect(throws: AgentEventCallbackVerificationError.notAuthorized) {
      try await service.verifyPending(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID,
        workspaceProvider: { Workspace() }
      )
    }

    #expect(fixture.secretStore.signingKeyReadCount() == 0)
    #expect(await exchange.requestCount() == 0)
  }

  @Test func scopeAuthorizationLossAtEveryCheckBoundaryPreventsOrInvalidatesProof() async throws {
    for invalidWorkspaceIndex in 1...9 {
      let fixture = try await CallbackVerificationFixture.make()
      defer { fixture.remove() }
      let sequence = CallbackVerificationWorkspaceSequence(
        Array(repeating: fixture.workspace, count: invalidWorkspaceIndex - 1) + [Workspace()]
      )
      let exchange = CallbackVerificationTestExchange { request in
        try makeEchoResponse(for: request)
      }
      let service = fixture.service(exchange: exchange)

      await #expect(throws: AgentEventCallbackVerificationError.notAuthorized) {
        try await service.verifyPending(
          profileID: fixture.profileID,
          subscriptionID: fixture.subscriptionID,
          workspaceProvider: { sequence.next() }
        )
      }

      #expect(fixture.secretStore.signingKeyReadCount() == (invalidWorkspaceIndex <= 3 ? 0 : 1))
      #expect(await exchange.requestCount() == (invalidWorkspaceIndex >= 6 ? 1 : 0))
      #expect(
        try fixture.verificationStore.currentProof(
          for: fixture.binding
        ) == nil)
    }
  }

  @Test func temporaryExclusionChangesDuringWorkspaceSuspensionPreventVerification() async throws {
    for reinclude in [false, true] {
      let fixture = try await CallbackVerificationFixture.make()
      defer { fixture.remove() }
      let gate = CallbackVerificationAsyncGate()
      let workspaces = CallbackVerificationAsyncWorkspaceOverrideSequence(fixture.workspace) {
        request in
        if request == 1 { await gate.pause() }
        return nil
      }
      let exchange = CallbackVerificationTestExchange { request in
        try makeEchoResponse(for: request)
      }
      let initialBytes = try? Data(contentsOf: fixture.verificationURL)
      let verification = Task {
        try await fixture.service(exchange: exchange).verifyPending(
          profileID: fixture.profileID,
          subscriptionID: fixture.subscriptionID,
          workspaceProvider: { try await workspaces.next() }
        )
      }

      await gate.waitUntilPaused()
      let noteID = try #require(fixture.workspace.notes.first?.id)
      fixture.authority.exclude(noteID: noteID)
      if reinclude {
        fixture.authority.include(noteID: noteID)
      }
      await gate.release()

      await #expect(throws: AgentEventCallbackVerificationError.notAuthorized) {
        try await verification.value
      }
      #expect(fixture.secretStore.signingKeyReadCount() == 0)
      #expect(await exchange.requestCount() == 0)
      #expect(try fixture.verificationStore.currentProof(for: fixture.binding) == nil)
      #expect((try? Data(contentsOf: fixture.verificationURL)) == initialBytes)
    }
  }

  @Test func temporaryExclusionABADuringExchangePreventsProofAcceptance() async throws {
    let fixture = try await CallbackVerificationFixture.make()
    defer { fixture.remove() }
    let barrier = CallbackVerificationExchangeBarrier()
    let exchange = CallbackVerificationTestExchange { request in
      try await barrier.hold(request)
    }
    let verification = Task {
      try await fixture.service(exchange: exchange).verifyPending(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID,
        workspaceProvider: fixture.workspaceProvider
      )
    }

    await barrier.waitForRequest()
    let noteID = try #require(fixture.workspace.notes.first?.id)
    fixture.authority.exclude(noteID: noteID)
    fixture.authority.include(noteID: noteID)
    await barrier.releaseEcho()

    await #expect(throws: AgentEventCallbackVerificationError.notAuthorized) {
      try await verification.value
    }
    #expect(fixture.secretStore.signingKeyReadCount() == 1)
    #expect(await exchange.requestCount() == 1)
    #expect(try fixture.verificationStore.currentProof(for: fixture.binding) == nil)
    try expectVerificationDocument(
      try Data(contentsOf: fixture.verificationURL),
      intentCount: 0,
      proofCount: 0,
      lastObservedAt: fixture.date
    )
  }

  @Test func refreshRemovalRevocationAndScopeChangeDuringExchangeInvalidateResponse()
    async throws
  {
    enum Mutation: CaseIterable {
      case refresh
      case remove
      case revokeProfile
      case loseObservationGrant
      case loseScopeAccess
    }

    for mutation in Mutation.allCases {
      let fixture = try await CallbackVerificationFixture.make()
      defer { fixture.remove() }
      let exchange = CallbackVerificationTestExchange { request in
        switch mutation {
        case .refresh:
          try await fixture.refreshSubscription()
        case .remove:
          try await fixture.removeSubscription()
        case .revokeProfile:
          try await fixture.profileStore.revoke(profileID: fixture.profileID)
        case .loseObservationGrant:
          try await fixture.setObservationPermission(false)
        case .loseScopeAccess:
          fixture.workspaceState.replace(Workspace())
        }
        return try makeEchoResponse(for: request)
      }

      await #expect(throws: AgentEventCallbackVerificationError.notAuthorized) {
        try await fixture.service(exchange: exchange).verifyPending(
          profileID: fixture.profileID,
          subscriptionID: fixture.subscriptionID,
          workspaceProvider: fixture.workspaceProvider
        )
      }
      #expect(await exchange.requestCount() == 1)
      #expect(
        try fixture.verificationStore.currentProof(
          for: fixture.binding
        ) == nil)
    }
  }

  @Test func cachedProofIsRevalidatedAfterAuthorizationTimeAdvancesOrRollsBack()
    async throws
  {
    enum ClockChange {
      case advanceToProofExpiry
      case rollBack
    }

    for clockChange in [ClockChange.advanceToProofExpiry, .rollBack] {
      let fixture = try await CallbackVerificationFixture.make()
      defer { fixture.remove() }
      let exchange = CallbackVerificationTestExchange { request in
        try makeEchoResponse(for: request)
      }
      let service = fixture.service(exchange: exchange)
      let original = try await service.verifyPending(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID,
        workspaceProvider: fixture.workspaceProvider
      )
      let cacheTime: Date
      let authorizationTime: Date
      switch clockChange {
      case .advanceToProofExpiry:
        cacheTime = original.verifiedAt.addingTimeInterval(100)
        authorizationTime = original.expiresAt
      case .rollBack:
        cacheTime = original.verifiedAt.addingTimeInterval(100)
        authorizationTime = original.verifiedAt.addingTimeInterval(50)
      }
      fixture.clock.set(cacheTime)
      let sequence = CallbackVerificationWorkspaceSequence(
        [fixture.workspace, fixture.workspace],
        onRequest: { request in
          if request == 2 { fixture.clock.set(authorizationTime) }
        }
      )

      switch clockChange {
      case .advanceToProofExpiry:
        let refreshed = try await service.verifyPending(
          profileID: fixture.profileID,
          subscriptionID: fixture.subscriptionID,
          workspaceProvider: { sequence.next() }
        )
        let requests = await exchange.requests()
        #expect(refreshed != original)
        #expect(refreshed.verifiedAt == authorizationTime)
        #expect(requests.count == 2)
        if requests.count == 2 {
          #expect(
            try decodeChallenge(from: requests[0].body)
              != decodeChallenge(from: requests[1].body)
          )
        }
        #expect(fixture.secretStore.signingKeyReadCount() == 2)
        #expect(try fixture.verificationStore.currentProof(for: fixture.binding) == refreshed)
      case .rollBack:
        await #expect(throws: AgentEventCallbackVerificationError.storageFailure) {
          try await service.verifyPending(
            profileID: fixture.profileID,
            subscriptionID: fixture.subscriptionID,
            workspaceProvider: { sequence.next() }
          )
        }
        let requests = await exchange.requests()
        #expect(requests.count == 1)
        #expect(fixture.secretStore.signingKeyReadCount() == 1)
        #expect(try fixture.verificationStore.currentProof(for: fixture.binding) == nil)
        let document = try #require(
          JSONSerialization.jsonObject(with: Data(contentsOf: fixture.verificationURL))
            as? [String: Any]
        )
        let lastObservedAt = try #require(document["lastObservedAt"] as? NSNumber)
        #expect(
          Date(timeIntervalSinceReferenceDate: lastObservedAt.doubleValue) == cacheTime)
      }
    }
  }

  @Test func elapsedIntentDeadlineDuringPrecommitAuthorizationDoesNotPersistProof() async throws {
    let fixture = try await CallbackVerificationFixture.make()
    defer { fixture.remove() }
    let sequence = CallbackVerificationWorkspaceSequence(
      Array(repeating: fixture.workspace, count: 8),
      onRequest: { request in
        if request == 6 { fixture.clock.set(fixture.date.addingTimeInterval(61)) }
      }
    )
    let exchange = CallbackVerificationTestExchange { request in
      try makeEchoResponse(for: request)
    }

    await #expect(throws: AgentEventCallbackVerificationError.verificationFailed) {
      try await fixture.service(exchange: exchange).verifyPending(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID,
        workspaceProvider: { sequence.next() }
      )
    }

    let request = try #require(await exchange.requests().first)
    let challenge = try decodeChallenge(from: request.body)
    let document = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: fixture.verificationURL))
        as? [String: Any]
    )
    #expect(fixture.secretStore.signingKeyReadCount() == 1)
    #expect(await exchange.requestCount() == 1)
    #expect((document["intents"] as? [[String: Any]])?.isEmpty == true)
    #expect((document["proofs"] as? [[String: Any]])?.isEmpty == true)
    #expect(
      !String(decoding: try Data(contentsOf: fixture.verificationURL), as: UTF8.self).contains(
        challenge))
  }

  @Test func finalReturnRechecksProofDeadlineAndSubscriptionTTL() async throws {
    enum Expiration {
      case proof
      case subscription
    }

    for expiration in [Expiration.proof, .subscription] {
      let fixture = try await CallbackVerificationFixture.make()
      defer { fixture.remove() }
      let subscription = try #require(
        await fixture.subscriptionStore.currentSubscription(id: fixture.subscriptionID)
      )
      let expirationTime =
        expiration == .proof
        ? fixture.date.addingTimeInterval(601)
        : subscription.expiresAt.addingTimeInterval(1)
      let sequence = CallbackVerificationWorkspaceSequence(
        Array(repeating: fixture.workspace, count: 8),
        onRequest: { request in
          if request == 8 { fixture.clock.set(expirationTime) }
        }
      )
      let exchange = CallbackVerificationTestExchange { request in
        try makeEchoResponse(for: request)
      }
      let expectedError: AgentEventCallbackVerificationError =
        expiration == .proof
        ? .verificationFailed
        : .notAuthorized

      await #expect(throws: expectedError) {
        try await fixture.service(exchange: exchange).verifyPending(
          profileID: fixture.profileID,
          subscriptionID: fixture.subscriptionID,
          workspaceProvider: { sequence.next() }
        )
      }

      #expect(fixture.secretStore.signingKeyReadCount() == 1)
      #expect(await exchange.requestCount() == 1)
      #expect(
        try fixture.verificationStore.currentProof(
          for: fixture.binding
        ) == nil)
      let document = try #require(
        JSONSerialization.jsonObject(with: Data(contentsOf: fixture.verificationURL))
          as? [String: Any]
      )
      #expect((document["intents"] as? [[String: Any]])?.isEmpty == true)
      #expect((document["proofs"] as? [[String: Any]])?.isEmpty == true)
    }
  }

  @Test func clockRollbackDuringFinalReturnAuthorizationDoesNotReturnCachedProof() async throws {
    let fixture = try await CallbackVerificationFixture.make()
    defer { fixture.remove() }
    let sequence = CallbackVerificationWorkspaceSequence(
      Array(repeating: fixture.workspace, count: 9),
      onRequest: { request in
        if request == 8 { fixture.clock.set(fixture.date.addingTimeInterval(100)) }
        if request == 9 { fixture.clock.set(fixture.date.addingTimeInterval(50)) }
      }
    )
    let exchange = CallbackVerificationTestExchange { request in
      try makeEchoResponse(for: request)
    }

    await #expect(throws: AgentEventCallbackVerificationError.verificationFailed) {
      try await fixture.service(exchange: exchange).verifyPending(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID,
        workspaceProvider: { sequence.next() }
      )
    }

    #expect(sequence.requestCountSnapshot() == 9)
    #expect(fixture.secretStore.signingKeyReadCount() == 1)
    #expect(await exchange.requestCount() == 1)
    #expect(
      try fixture.verificationStore.currentProof(
        for: fixture.binding
      ) == nil)
  }

  @Test func subscriptionAndProfileMetadataChangesAtAuthorizationBoundariesFailClosed()
    async throws
  {
    enum Checkpoint: CaseIterable {
      case beforeHTTP
      case cachedReturn
    }
    enum Mutation: CaseIterable {
      case refreshSubscription
      case removeSubscription
      case revokeProfile
    }

    for checkpoint in Checkpoint.allCases {
      for mutation in Mutation.allCases {
        let fixture = try await CallbackVerificationFixture.make()
        defer { fixture.remove() }
        let targetRequest = checkpoint == .beforeHTTP ? 4 : 11
        let sequence = CallbackVerificationAsyncWorkspaceSequence(
          fixture.workspace,
          onRequest: { request in
            guard request == targetRequest else { return }
            switch mutation {
            case .refreshSubscription:
              try await fixture.refreshSubscription()
            case .removeSubscription:
              try await fixture.removeSubscription()
            case .revokeProfile:
              try await fixture.profileStore.revoke(profileID: fixture.profileID)
            }
          }
        )
        let workspaceProvider: AgentEventWorkspaceProvider = { try await sequence.next() }
        let exchange = CallbackVerificationTestExchange { request in
          try makeEchoResponse(for: request)
        }
        let service = fixture.service(exchange: exchange)

        if checkpoint == .cachedReturn {
          _ = try await service.verifyPending(
            profileID: fixture.profileID,
            subscriptionID: fixture.subscriptionID,
            workspaceProvider: workspaceProvider
          )
        }

        await #expect(throws: AgentEventCallbackVerificationError.notAuthorized) {
          try await service.verifyPending(
            profileID: fixture.profileID,
            subscriptionID: fixture.subscriptionID,
            workspaceProvider: workspaceProvider
          )
        }

        #expect(fixture.secretStore.signingKeyReadCount() == 1)
        #expect(await exchange.requestCount() == (checkpoint == .beforeHTTP ? 0 : 1))
        #expect(
          try fixture.verificationStore.currentProof(
            for: fixture.binding
          ) == nil)
      }
    }
  }

  @Test func clockRollbackInvalidatesPreviouslyCachedProof() async throws {
    let fixture = try await CallbackVerificationFixture.make()
    defer { fixture.remove() }
    let exchange = CallbackVerificationTestExchange { request in
      try makeEchoResponse(for: request)
    }
    let proof = try await fixture.service(exchange: exchange).verifyPending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      workspaceProvider: fixture.workspaceProvider
    )
    fixture.clock.set(fixture.date.addingTimeInterval(100))
    #expect(
      try fixture.verificationStore.currentProof(
        for: fixture.binding
      ) == proof)
    fixture.clock.set(fixture.date.addingTimeInterval(50))

    #expect(
      try fixture.verificationStore.currentProof(
        for: fixture.binding
      ) == nil)
    let restarted = AgentEventCallbackVerificationStore(
      fileURL: fixture.verificationURL,
      now: { fixture.clock.now() }
    )
    #expect(try restarted.currentProof(for: fixture.binding) == nil)
    let document = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: fixture.verificationURL))
        as? [String: Any]
    )
    let lastObservedAt = try #require(document["lastObservedAt"] as? NSNumber)
    #expect(
      Date(timeIntervalSinceReferenceDate: lastObservedAt.doubleValue)
        == fixture.date.addingTimeInterval(100))
  }

  @Test func initialAuthorizationFailureCannotInvalidateAnotherServicesProof() async throws {
    let fixture = try await CallbackVerificationFixture.make()
    defer { fixture.remove() }
    let exchange = CallbackVerificationTestExchange { request in
      try makeEchoResponse(for: request)
    }
    let service = fixture.service(exchange: exchange)
    let snapshot = CallbackVerificationProofSnapshot()
    let unauthenticatedProvider: AgentEventWorkspaceProvider = {
      let proof = try await service.verifyPending(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID,
        workspaceProvider: fixture.workspaceProvider
      )
      await snapshot.record(proof, bytes: try Data(contentsOf: fixture.verificationURL))
      return Workspace()
    }

    do {
      _ = try await service.verifyPending(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID,
        workspaceProvider: unauthenticatedProvider
      )
      #expect(Bool(false), "an unauthorized caller unexpectedly received a proof")
    } catch {
      #expect(error as? AgentEventCallbackVerificationError == .notAuthorized)
    }

    let expected = try #require(await snapshot.value())
    #expect(try Data(contentsOf: fixture.verificationURL) == expected.bytes)
    #expect(
      try fixture.verificationStore.currentProof(
        for: fixture.binding
      ) == expected.proof)
    #expect(fixture.secretStore.signingKeyReadCount() == 1)
    #expect(await exchange.requestCount() == 1)
  }

  @Test func cachedAuthorizationFailureCannotInvalidateReplacementProof() async throws {
    let fixture = try await CallbackVerificationFixture.make()
    defer { fixture.remove() }
    let exchange = CallbackVerificationTestExchange { request in
      try makeEchoResponse(for: request)
    }
    let service = fixture.service(exchange: exchange)
    let original = try await service.verifyPending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      workspaceProvider: fixture.workspaceProvider
    )
    let snapshot = CallbackVerificationProofSnapshot()
    let workspaces = CallbackVerificationAsyncWorkspaceOverrideSequence(fixture.workspace) {
      request in
      guard request == 2 else { return nil }
      fixture.clock.set(original.expiresAt)
      let replacement = try await service.verifyPending(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID,
        workspaceProvider: fixture.workspaceProvider
      )
      await snapshot.record(replacement, bytes: try Data(contentsOf: fixture.verificationURL))
      return Workspace()
    }

    await #expect(throws: AgentEventCallbackVerificationError.notAuthorized) {
      try await service.verifyPending(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID,
        workspaceProvider: { try await workspaces.next() }
      )
    }

    let expected = try #require(await snapshot.value())
    #expect(expected.proof != original)
    #expect(try Data(contentsOf: fixture.verificationURL) == expected.bytes)
    #expect(
      try fixture.verificationStore.currentProof(
        for: fixture.binding
      ) == expected.proof)
    #expect(fixture.secretStore.signingKeyReadCount() == 2)
    #expect(await exchange.requestCount() == 2)
  }

  @Test func lateFailurePreservesSuccessorIntentOwnedByAnotherService() async throws {
    let fixture = try await CallbackVerificationFixture.make()
    defer { fixture.remove() }
    let firstBarrier = CallbackVerificationExchangeBarrier()
    let firstExchange = CallbackVerificationTestExchange { request in
      try await firstBarrier.hold(request)
    }
    let firstService = fixture.service(exchange: firstExchange)
    let first = Task {
      try await firstService.verifyPending(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID,
        workspaceProvider: fixture.workspaceProvider
      )
    }
    await firstBarrier.waitForRequest()
    fixture.clock.set(fixture.date.addingTimeInterval(61))

    let successorGate = CallbackVerificationAsyncGate()
    let successorWorkspaces = CallbackVerificationAsyncWorkspaceOverrideSequence(
      fixture.workspace
    ) { request in
      if request == 3 { await successorGate.pause() }
      return nil
    }
    let successorExchange = CallbackVerificationTestExchange { request in
      try makeEchoResponse(for: request)
    }
    let successorService = fixture.service(exchange: successorExchange)
    let successor = Task {
      try await successorService.verifyPending(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID,
        workspaceProvider: { try await successorWorkspaces.next() }
      )
    }
    await successorGate.waitUntilPaused()
    let beforeFailure = try Data(contentsOf: fixture.verificationURL)

    await firstBarrier.releaseEcho()
    switch await first.result {
    case .success:
      #expect(Bool(false), "the expired attempt unexpectedly succeeded")
    case .failure(let error):
      #expect(error as? AgentEventCallbackVerificationError == .verificationFailed)
    }
    #expect(try Data(contentsOf: fixture.verificationURL) == beforeFailure)

    await successorGate.release()
    let successorProof: AgentEventCallbackVerificationProof?
    do {
      successorProof = try await successor.value
    } catch {
      successorProof = nil
    }
    #expect(successorProof?.binding == fixture.binding)
    #expect(fixture.secretStore.signingKeyReadCount() == 2)
    #expect(await firstExchange.requestCount() == 1)
    #expect(await successorExchange.requestCount() == 1)
  }

  @Test func lateFailurePreservesProofCompletedByAnotherService() async throws {
    let fixture = try await CallbackVerificationFixture.make()
    defer { fixture.remove() }
    let firstBarrier = CallbackVerificationExchangeBarrier()
    let firstExchange = CallbackVerificationTestExchange { request in
      try await firstBarrier.hold(request)
    }
    let firstService = fixture.service(exchange: firstExchange)
    let first = Task {
      try await firstService.verifyPending(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID,
        workspaceProvider: fixture.workspaceProvider
      )
    }
    await firstBarrier.waitForRequest()
    fixture.clock.set(fixture.date.addingTimeInterval(61))

    let successorExchange = CallbackVerificationTestExchange { request in
      try makeEchoResponse(for: request)
    }
    let successorProof = try await fixture.service(exchange: successorExchange).verifyPending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      workspaceProvider: fixture.workspaceProvider
    )
    let successorBytes = try Data(contentsOf: fixture.verificationURL)

    await firstBarrier.releaseEcho()
    switch await first.result {
    case .success:
      #expect(Bool(false), "the expired attempt unexpectedly succeeded")
    case .failure(let error):
      #expect(error as? AgentEventCallbackVerificationError == .verificationFailed)
    }

    #expect(try Data(contentsOf: fixture.verificationURL) == successorBytes)
    #expect(
      try fixture.verificationStore.currentProof(
        for: fixture.binding
      ) == successorProof)
    #expect(await firstExchange.requestCount() == 1)
    #expect(await successorExchange.requestCount() == 1)
  }

  @Test func staleBindingLookupAfterRefreshRollbackPreservesNewIntentAndProof() async throws {
    let fixture = try await CallbackVerificationFixture.make()
    defer { fixture.remove() }
    let previous = try #require(
      await fixture.subscriptionStore.currentSubscription(id: fixture.subscriptionID)
    )
    let refreshedAt = fixture.date.addingTimeInterval(1)
    fixture.clock.set(refreshedAt)
    let nextReference = UUID().uuidString.lowercased()
    try await fixture.subscriptionStore.reserveSigningKeyReference(nextReference)
    try fixture.signingKeyStore.store(secretData: fixture.signingSecret, reference: nextReference)
    let mutation = try await fixture.subscriptionStore.createOrRefresh(
      AgentEventPendingSubscription(
        subscriptionID: previous.subscriptionID,
        profileID: previous.profileID,
        event: previous.event,
        scope: previous.scope,
        callbackURL: previous.callbackURL,
        signingKeyReference: nextReference,
        grantRevision: previous.grantRevision,
        createdAt: previous.createdAt,
        updatedAt: refreshedAt,
        expiresAt: refreshedAt.addingTimeInterval(3_600),
        revision: previous.revision + 1
      ),
      now: refreshedAt
    )
    let refreshedBinding = AgentEventCallbackVerificationBinding(
      profileID: previous.profileID,
      subscriptionID: previous.subscriptionID,
      subscriptionRevision: mutation.stored.revision,
      grantRevision: mutation.stored.grantRevision,
      signingKeyReference: mutation.stored.signingKeyReference
    )
    let store = fixture.verificationStore
    let proofIntent = fixture.intent(id: UUID(), nonceByte: 1, binding: refreshedBinding)
    try store.begin(proofIntent)
    let proof = try store.complete(
      proofIntent,
      subscriptionExpiresAt: refreshedAt.addingTimeInterval(3_600)
    )
    let pendingIntent = fixture.intent(id: UUID(), nonceByte: 2, binding: refreshedBinding)
    try store.begin(pendingIntent)
    let refreshedControl = try #require(mutation.stored.deliveryControl)
    #expect(try await fixture.subscriptionStore.rollback(mutation))
    let restored = try #require(
      await fixture.subscriptionStore.currentSubscription(id: fixture.subscriptionID)
    )
    #expect(restored.replacingDeliveryControl(nil) == previous.replacingDeliveryControl(nil))
    let restoredControl = try #require(restored.deliveryControl)
    let expectedBinding = AgentEventCallbackVerificationBinding(
      profileID: previous.profileID,
      subscriptionID: previous.subscriptionID,
      subscriptionRevision: previous.revision,
      grantRevision: previous.grantRevision,
      signingKeyReference: previous.signingKeyReference
    )
    #expect(!restoredControl.enabled)
    #expect(restoredControl.binding == expectedBinding)
    let previousControl = try #require(previous.deliveryControl)
    #expect(restoredControl.generationID != previousControl.generationID)
    #expect(restoredControl.generationID != refreshedControl.generationID)
    let beforeLookup = try Data(contentsOf: fixture.verificationURL)

    #expect(try store.currentProof(for: fixture.binding) == nil)

    #expect(try Data(contentsOf: fixture.verificationURL) == beforeLookup)
    #expect(try store.currentProof(for: refreshedBinding) == proof)
    let document = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: fixture.verificationURL))
        as? [String: Any]
    )
    #expect((document["intents"] as? [[String: Any]])?.count == 1)
    #expect((document["proofs"] as? [[String: Any]])?.count == 1)
  }

  @Test func outOfOrderStoreEntryDoesNotTreatStaleCallerStampAsClockRollback() async throws {
    let fixture = try await CallbackVerificationFixture.make()
    defer { fixture.remove() }
    let store = fixture.verificationStore
    let firstBinding = fixture.binding(
      subscriptionID: "evt_\(String(format: "%064x", 1))",
      profileID: UUID(),
      keyReference: UUID().uuidString.lowercased()
    )
    let secondBinding = fixture.binding(
      subscriptionID: "evt_\(String(format: "%064x", 2))",
      profileID: UUID(),
      keyReference: UUID().uuidString.lowercased()
    )
    let firstIntent = fixture.intent(id: UUID(), nonceByte: 1, binding: firstBinding)
    let secondIntent = fixture.intent(id: UUID(), nonceByte: 2, binding: secondBinding)
    try store.begin(firstIntent)
    try store.begin(secondIntent)
    let firstProof = try store.complete(
      firstIntent,
      subscriptionExpiresAt: fixture.date.addingTimeInterval(600)
    )
    let secondProof = try store.complete(
      secondIntent,
      subscriptionExpiresAt: fixture.date.addingTimeInterval(600)
    )

    let ready = DispatchSemaphore(value: 0)
    let resume = DispatchSemaphore(value: 0)
    let finished = DispatchSemaphore(value: 0)
    let staleStore = AgentEventCallbackVerificationStore(
      fileURL: fixture.verificationURL,
      now: { fixture.clock.now() }
    )
    let staleTimestamp = fixture.date.addingTimeInterval(1)
    let staleObservation = CallbackVerificationStoreLookupObservation()
    DispatchQueue.global().async {
      ready.signal()
      resume.wait()
      _ = staleTimestamp
      do {
        staleObservation.record(.success(try staleStore.currentProof(for: firstBinding)))
      } catch {
        staleObservation.record(.failure(.failed))
      }
      finished.signal()
    }
    #expect(callbackVerificationWait(ready))
    let newerTimestamp = fixture.date.addingTimeInterval(2)
    fixture.clock.set(newerTimestamp)
    _ = try AgentEventCallbackVerificationStore(
      fileURL: fixture.verificationURL,
      now: { fixture.clock.now() }
    ).currentProof(for: firstBinding)
    resume.signal()
    #expect(callbackVerificationWait(finished))
    #expect(staleObservation.value() == .success(firstProof))

    #expect(try store.currentProof(for: firstBinding) == firstProof)
    #expect(try store.currentProof(for: secondBinding) == secondProof)
  }

  @Test func legacyProofWithoutAttemptOwnerFailsClosedWithoutRewrite() async throws {
    let fixture = try await CallbackVerificationFixture.make()
    defer { fixture.remove() }
    let exchange = CallbackVerificationTestExchange { request in
      try makeEchoResponse(for: request)
    }
    _ = try await fixture.service(exchange: exchange).verifyPending(
      profileID: fixture.profileID,
      subscriptionID: fixture.subscriptionID,
      workspaceProvider: fixture.workspaceProvider
    )
    var document = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: fixture.verificationURL))
        as? [String: Any]
    )
    document["schemaVersion"] = 1
    var proofs = try #require(document["proofs"] as? [[String: Any]])
    proofs[0].removeValue(forKey: "originIntentID")
    document["proofs"] = proofs
    let legacy = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
    try legacy.write(to: fixture.verificationURL, options: .atomic)

    #expect(throws: AgentEventCallbackVerificationStoreError.storageFailure) {
      try fixture.verificationStore.currentProof(for: fixture.binding)
    }

    #expect(try Data(contentsOf: fixture.verificationURL) == legacy)
  }

  @Test func twoServiceAdmissionsReserveUnionOfProofAndIntentBindings() async throws {
    let fixture = try await CallbackVerificationFixture.make()
    defer { fixture.remove() }
    let store = fixture.verificationStore
    for index in 1...127 {
      let binding = fixture.binding(
        subscriptionID: "evt_\(String(format: "%064x", index))",
        profileID: UUID(),
        keyReference: UUID().uuidString.lowercased()
      )
      let intent = fixture.intent(
        id: UUID(),
        nonceByte: UInt8(truncatingIfNeeded: index),
        binding: binding
      )
      try store.begin(intent)
      _ = try store.complete(
        intent,
        subscriptionExpiresAt: fixture.date.addingTimeInterval(600)
      )
    }
    let secondSubscriptionID = try await fixture.addSubscription(
      callbackURL: "https://example.com/events/second-callback"
    )
    let firstBarrier = CallbackVerificationExchangeBarrier()
    let firstExchange = CallbackVerificationTestExchange { request in
      try await firstBarrier.hold(request)
    }
    let secondExchange = CallbackVerificationTestExchange { request in
      try makeEchoResponse(for: request)
    }
    let firstService = fixture.service(exchange: firstExchange, verificationStore: store)
    let secondService = fixture.service(exchange: secondExchange, verificationStore: store)
    let first = Task {
      try await firstService.verifyPending(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID,
        workspaceProvider: fixture.workspaceProvider
      )
    }
    await firstBarrier.waitForRequest()

    do {
      _ = try await secondService.verifyPending(
        profileID: fixture.profileID,
        subscriptionID: secondSubscriptionID,
        workspaceProvider: fixture.workspaceProvider
      )
      #expect(Bool(false), "the second binding exceeded proof capacity")
    } catch {
      #expect(error as? AgentEventCallbackVerificationError == .capacityExceeded)
    }

    #expect(fixture.secretStore.signingKeyReadCount() == 1)
    #expect(await secondExchange.requestCount() == 0)
    await firstBarrier.releaseEcho()
    let firstProof: AgentEventCallbackVerificationProof?
    do {
      firstProof = try await first.value
    } catch {
      firstProof = nil
    }
    #expect(firstProof?.binding == fixture.binding)
    #expect(fixture.secretStore.signingKeyReadCount() == 1)
    #expect(await firstExchange.requestCount() == 1)
    let document = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: fixture.verificationURL))
        as? [String: Any]
    )
    #expect((document["proofs"] as? [[String: Any]])?.count == 128)
    #expect((document["intents"] as? [[String: Any]])?.isEmpty == true)
  }

  @Test func corruptAndOversizedStoresFailClosedWithoutResetOrExternalEffects() async throws {
    for raw in [
      Data(#"{"schemaVersion":99}"#.utf8),
      Data(repeating: 0x20, count: 1_048_577),
    ] {
      let fixture = try await CallbackVerificationFixture.make()
      defer { fixture.remove() }
      try raw.write(to: fixture.verificationURL, options: .atomic)
      let exchange = CallbackVerificationTestExchange { request in
        try makeEchoResponse(for: request)
      }

      await #expect(throws: AgentEventCallbackVerificationError.storageFailure) {
        try await fixture.service(exchange: exchange).verifyPending(
          profileID: fixture.profileID,
          subscriptionID: fixture.subscriptionID,
          workspaceProvider: fixture.workspaceProvider
        )
      }

      #expect(try Data(contentsOf: fixture.verificationURL) == raw)
      #expect(fixture.secretStore.signingKeyReadCount() == 0)
      #expect(await exchange.requestCount() == 0)
    }
  }

  @Test func intentAndProofCapacityStopBeforeHTTP() async throws {
    for fillProofs in [false, true] {
      let fixture = try await CallbackVerificationFixture.make()
      defer { fixture.remove() }
      let store = fixture.verificationStore
      for index in 1...128 {
        let binding = fixture.binding(
          subscriptionID: "evt_\(String(format: "%064x", index))",
          profileID: UUID(),
          keyReference: UUID().uuidString.lowercased()
        )
        let intent = fixture.intent(
          id: UUID(),
          nonceByte: UInt8(truncatingIfNeeded: index),
          binding: binding
        )
        try store.begin(intent)
        if fillProofs {
          _ = try store.complete(
            intent,
            subscriptionExpiresAt: fixture.date.addingTimeInterval(600)
          )
        }
      }
      let exchange = CallbackVerificationTestExchange { request in
        try makeEchoResponse(for: request)
      }

      await #expect(throws: AgentEventCallbackVerificationError.capacityExceeded) {
        try await fixture.service(exchange: exchange, verificationStore: store).verifyPending(
          profileID: fixture.profileID,
          subscriptionID: fixture.subscriptionID,
          workspaceProvider: fixture.workspaceProvider
        )
      }
      #expect(fixture.secretStore.signingKeyReadCount() == 0)
      #expect(await exchange.requestCount() == 0)
    }
  }

  @Test func capacityReservationsReleaseOnCancelAndExpiryAndReplaceInPlace() async throws {
    let fixture = try await CallbackVerificationFixture.make()
    defer { fixture.remove() }
    let store = fixture.verificationStore
    var proofBindings: [AgentEventCallbackVerificationBinding] = []
    for index in 1...127 {
      let binding = fixture.binding(
        subscriptionID: "evt_\(String(format: "%064x", index))",
        profileID: UUID(),
        keyReference: UUID().uuidString.lowercased()
      )
      let intent = fixture.intent(
        id: UUID(),
        nonceByte: UInt8(truncatingIfNeeded: index),
        binding: binding
      )
      try store.begin(intent)
      _ = try store.complete(
        intent,
        subscriptionExpiresAt: fixture.date.addingTimeInterval(3_600)
      )
      proofBindings.append(binding)
    }

    let cancelledBinding = fixture.binding(
      subscriptionID: "evt_\(String(format: "%064x", 128))",
      profileID: UUID(),
      keyReference: UUID().uuidString.lowercased()
    )
    let cancelledIntent = fixture.intent(id: UUID(), nonceByte: 128, binding: cancelledBinding)
    try store.begin(cancelledIntent)
    try store.cancel(cancelledIntent)

    let expiredBinding = fixture.binding(
      subscriptionID: "evt_\(String(format: "%064x", 129))",
      profileID: UUID(),
      keyReference: UUID().uuidString.lowercased()
    )
    let expiredIntent = fixture.intent(id: UUID(), nonceByte: 129, binding: expiredBinding)
    try store.begin(expiredIntent)
    let nextTime = fixture.date.addingTimeInterval(61)
    fixture.clock.set(nextTime)
    let admittedBinding = fixture.binding(
      subscriptionID: "evt_\(String(format: "%064x", 130))",
      profileID: UUID(),
      keyReference: UUID().uuidString.lowercased()
    )
    let admittedIntent = AgentEventCallbackVerificationIntent(
      id: UUID(),
      binding: admittedBinding,
      nonceDigest: Data(repeating: 130, count: 32),
      createdAt: nextTime,
      expiresAt: nextTime.addingTimeInterval(60)
    )
    try store.begin(admittedIntent)
    let admittedProof = try store.complete(
      admittedIntent,
      subscriptionExpiresAt: nextTime.addingTimeInterval(3_600)
    )

    let replacementIntent = AgentEventCallbackVerificationIntent(
      id: UUID(),
      binding: proofBindings[0],
      nonceDigest: Data(repeating: 131, count: 32),
      createdAt: nextTime,
      expiresAt: nextTime.addingTimeInterval(60)
    )
    try store.begin(replacementIntent)
    let replacement = try store.complete(
      replacementIntent,
      subscriptionExpiresAt: nextTime.addingTimeInterval(3_600)
    )

    #expect(admittedProof.originIntentID == admittedIntent.id)
    #expect(replacement.originIntentID == replacementIntent.id)
    #expect(try store.currentProof(for: proofBindings[0]) == replacement)
    let document = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: fixture.verificationURL))
        as? [String: Any]
    )
    #expect((document["proofs"] as? [[String: Any]])?.count == 128)
    #expect((document["intents"] as? [[String: Any]])?.isEmpty == true)
  }

  @Test func concurrentServiceInstancesAllowOnlyOneChallengePerBinding() async throws {
    let fixture = try await CallbackVerificationFixture.make()
    defer { fixture.remove() }
    let barrier = CallbackVerificationExchangeBarrier()
    let exchange = CallbackVerificationTestExchange { request in
      try await barrier.hold(request)
    }
    let firstService = fixture.service(exchange: exchange)
    let secondService = fixture.service(
      exchange: exchange,
      verificationStore: AgentEventCallbackVerificationStore(
        fileURL: fixture.verificationURL,
        now: { fixture.clock.now() }
      )
    )
    let first = Task {
      try await firstService.verifyPending(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID,
        workspaceProvider: fixture.workspaceProvider
      )
    }
    await barrier.waitForRequest()

    await #expect(throws: AgentEventCallbackVerificationError.verificationInProgress) {
      try await secondService.verifyPending(
        profileID: fixture.profileID,
        subscriptionID: fixture.subscriptionID,
        workspaceProvider: fixture.workspaceProvider
      )
    }
    #expect(fixture.secretStore.signingKeyReadCount() == 1)
    #expect(await exchange.requestCount() == 1)
    await barrier.releaseEcho()
    let proof = try await first.value
    #expect(proof.binding == fixture.binding)
  }
}

private struct CallbackVerificationRequest: Decodable {
  let type: String
  let challenge: String
}

private struct CallbackVerificationResponse: Encodable {
  let challenge: String
}

private struct CallbackVerificationExchangeRequest: Sendable {
  let callbackURL: String
  let headers: [AgentEventHTTPHeader]
  let body: Data
}

private actor CallbackVerificationTestExchange {
  typealias Handler =
    @Sendable (CallbackVerificationExchangeRequest) async throws
    -> AgentEventHTTPResponse

  private let handler: Handler
  private var recordedRequests: [CallbackVerificationExchangeRequest] = []

  init(handler: @escaping Handler) {
    self.handler = handler
  }

  func post(
    callbackURL: String,
    headers: [AgentEventHTTPHeader],
    body: Data
  ) async throws -> AgentEventHTTPResponse {
    let request = CallbackVerificationExchangeRequest(
      callbackURL: callbackURL,
      headers: headers,
      body: body
    )
    recordedRequests.append(request)
    return try await handler(request)
  }

  func requests() -> [CallbackVerificationExchangeRequest] {
    recordedRequests
  }

  func requestCount() -> Int {
    recordedRequests.count
  }
}

private func makeEchoResponse(
  for request: CallbackVerificationExchangeRequest,
  statusCode: Int = 200
) throws -> AgentEventHTTPResponse {
  try makeEchoResponse(challenge: decodeChallenge(from: request.body), statusCode: statusCode)
}

private func makeEchoResponse(
  challenge: String,
  statusCode: Int = 200
) throws -> AgentEventHTTPResponse {
  AgentEventHTTPResponse(
    statusCode: statusCode,
    body: try JSONEncoder().encode(CallbackVerificationResponse(challenge: challenge))
  )
}

private func decodeChallenge(from body: Data) throws -> String {
  try JSONDecoder().decode(CallbackVerificationRequest.self, from: body).challenge
}

private func callbackVerificationWait(_ semaphore: DispatchSemaphore) -> Bool {
  semaphore.wait(timeout: .now() + 5) == .success
}

private struct CallbackVerificationRollbackSnapshot {
  let before: Data
  let after: Data
  let highWater: Date
}

private func observeIntentClockRollback(
  in fixture: CallbackVerificationFixture
) throws -> CallbackVerificationRollbackSnapshot {
  let before = try Data(contentsOf: fixture.verificationURL)
  let observerStore = AgentEventCallbackVerificationStore(
    fileURL: fixture.verificationURL,
    now: { fixture.clock.now() }
  )
  let highWater = fixture.date.addingTimeInterval(10)
  fixture.clock.set(highWater)
  _ = try observerStore.currentProof(for: fixture.binding)
  fixture.clock.set(fixture.date.addingTimeInterval(5))
  _ = try observerStore.currentProof(for: fixture.binding)
  return CallbackVerificationRollbackSnapshot(
    before: before,
    after: try Data(contentsOf: fixture.verificationURL),
    highWater: highWater
  )
}

private func expectVerificationDocument(
  _ data: Data,
  intentCount: Int,
  proofCount: Int,
  lastObservedAt expectedLastObservedAt: Date
) throws {
  let document = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  let intents = try #require(document["intents"] as? [[String: Any]])
  let proofs = try #require(document["proofs"] as? [[String: Any]])
  let lastObservedAt = try #require(document["lastObservedAt"] as? NSNumber)
  #expect(intents.count == intentCount)
  #expect(proofs.count == proofCount)
  #expect(
    Date(timeIntervalSinceReferenceDate: lastObservedAt.doubleValue) == expectedLastObservedAt
  )
}

private func expectProofCommitWrite(
  _ writer: CallbackVerificationFileWriter,
  intentWrite: Int = 1,
  proofWrite: Int = 4
) throws {
  let intentData = try #require(writer.writeAttempt(at: intentWrite))
  let intentDocument = try #require(
    JSONSerialization.jsonObject(with: intentData) as? [String: Any])
  let intentsBefore = try #require(intentDocument["intents"] as? [[String: Any]])
  let proofsBefore = try #require(intentDocument["proofs"] as? [[String: Any]])
  #expect(intentsBefore.count == 1)
  #expect(proofsBefore.isEmpty)
  let intentID = try #require(intentsBefore.first?["id"] as? String)

  let proofData = try #require(writer.writeAttempt(at: proofWrite))
  let proofDocument = try #require(JSONSerialization.jsonObject(with: proofData) as? [String: Any])
  let intentsAfter = try #require(proofDocument["intents"] as? [[String: Any]])
  let proofsAfter = try #require(proofDocument["proofs"] as? [[String: Any]])
  #expect(intentsAfter.isEmpty)
  #expect(proofsAfter.count == 1)
  let proof = try #require(proofsAfter.first)
  #expect(proof["originIntentID"] as? String == intentID)
}

private enum CallbackVerificationTestError: Error {
  case keyReadFailure
  case unexpectedRequest
  case fileWriteFailure
}

private enum CallbackVerificationStoreLookupFailure: Error, Equatable {
  case failed
}

private final class CallbackVerificationStoreLookupObservation: @unchecked Sendable {
  private let lock = NSLock()
  private var stored:
    Result<
      AgentEventCallbackVerificationProof?, CallbackVerificationStoreLookupFailure
    >?

  func record(
    _ result: Result<AgentEventCallbackVerificationProof?, CallbackVerificationStoreLookupFailure>
  ) {
    lock.withLock { stored = result }
  }

  func value()
    -> Result<AgentEventCallbackVerificationProof?, CallbackVerificationStoreLookupFailure>?
  {
    lock.withLock { stored }
  }
}

private final class CallbackVerificationTestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var currentDate: Date

  init(_ date: Date) {
    currentDate = date
  }

  func now() -> Date {
    lock.withLock { currentDate }
  }

  func set(_ date: Date) {
    lock.withLock { currentDate = date }
  }
}

private final class CallbackVerificationIntentObservation: @unchecked Sendable {
  private let lock = NSLock()
  private var intentExists = false

  func read(_ url: URL) {
    let document = try? JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    let observed =
      (document?["intents"] as? [[String: Any]])?.count == 1
      && (document?["proofs"] as? [[String: Any]])?.isEmpty == true
    lock.withLock { intentExists = observed }
  }

  func value() -> Bool {
    lock.withLock { intentExists }
  }
}

private final class CallbackVerificationTestRandomBytes: AgentRandomBytesProviding,
  @unchecked Sendable
{
  private let lock = NSLock()
  private var requestCount = 0

  func randomBytes(count: Int) throws -> Data {
    guard count > 0 else { throw CallbackVerificationTestError.keyReadFailure }
    return lock.withLock {
      requestCount += 1
      return Data((0..<count).map { UInt8(truncatingIfNeeded: requestCount &+ $0) })
    }
  }
}

private final class CallbackVerificationTestSecretStore: AgentSecretStoring, @unchecked Sendable {
  private let signingService = "com.harryjin.fleck.agent-event-signing-keys"
  private let lock = NSLock()
  private var values: [String: Data] = [:]
  private var signingKeyReads = 0
  private var shouldFailNextSigningKeyRead = false
  private var signingKeyReadObserver: (@Sendable () -> Void)?

  func read(service: String, account: String) throws -> Data? {
    let result: (Data?, Bool, (@Sendable () -> Void)?) = lock.withLock {
      guard service == signingService else {
        return (values[account], false, nil)
      }
      signingKeyReads += 1
      let observer = signingKeyReadObserver
      signingKeyReadObserver = nil
      let shouldFail = shouldFailNextSigningKeyRead
      shouldFailNextSigningKeyRead = false
      return (values[account], shouldFail, observer)
    }
    result.2?()
    if result.1 { throw CallbackVerificationTestError.keyReadFailure }
    return result.0
  }

  func write(_ data: Data, service: String, account: String) throws {
    lock.withLock { values[account] = data }
  }

  func delete(service: String, account: String) throws {
    lock.withLock { _ = values.removeValue(forKey: account) }
  }

  func signingKeyReadCount() -> Int {
    lock.withLock { signingKeyReads }
  }

  func observeSigningKeyRead(_ observer: @escaping @Sendable () -> Void) {
    lock.withLock { signingKeyReadObserver = observer }
  }

  func removeSigningKey(reference: String) {
    lock.withLock { _ = values.removeValue(forKey: reference) }
  }
}

private final class CallbackVerificationFileWriter: @unchecked Sendable {
  private let lock = NSLock()
  private let failBeforeWriteNumbers: Set<Int>
  private let failAfterWriteNumbers: Set<Int>
  private var writeCountValue = 0
  private var writeAttempts: [Data] = []

  init(
    failBeforeWriteNumbers: Set<Int> = [],
    failAfterWriteNumbers: Set<Int> = []
  ) {
    self.failBeforeWriteNumbers = failBeforeWriteNumbers
    self.failAfterWriteNumbers = failAfterWriteNumbers
  }

  func write(_ data: Data, to url: URL) throws {
    let writeNumber = lock.withLock {
      writeCountValue += 1
      writeAttempts.append(data)
      return writeCountValue
    }
    if failBeforeWriteNumbers.contains(writeNumber) {
      throw CallbackVerificationTestError.fileWriteFailure
    }
    try data.write(to: url, options: .atomic)
    if failAfterWriteNumbers.contains(writeNumber) {
      throw CallbackVerificationTestError.fileWriteFailure
    }
  }

  func writeCount() -> Int {
    lock.withLock { writeCountValue }
  }

  func writeAttempt(at number: Int) -> Data? {
    lock.withLock {
      guard number > 0, number <= writeAttempts.count else { return nil }
      return writeAttempts[number - 1]
    }
  }
}

private final class CallbackVerificationWorkspaceState: @unchecked Sendable {
  private let lock = NSLock()
  private var currentWorkspace: Workspace

  init(_ workspace: Workspace) {
    currentWorkspace = workspace
  }

  func current() -> Workspace {
    lock.withLock { currentWorkspace }
  }

  func replace(_ workspace: Workspace) {
    lock.withLock { currentWorkspace = workspace }
  }
}

private final class CallbackVerificationWorkspaceSequence: @unchecked Sendable {
  private let lock = NSLock()
  private let workspaces: [Workspace]
  private let onRequest: (@Sendable (Int) -> Void)?
  private var requestCount = 0

  init(_ workspaces: [Workspace], onRequest: (@Sendable (Int) -> Void)? = nil) {
    self.workspaces = workspaces
    self.onRequest = onRequest
  }

  func next() -> Workspace {
    let (workspace, request) = lock.withLock {
      let index = requestCount
      requestCount += 1
      return (workspaces[min(index, workspaces.count - 1)], index + 1)
    }
    onRequest?(request)
    return workspace
  }

  func requestCountSnapshot() -> Int {
    lock.withLock { requestCount }
  }
}

private final class CallbackVerificationAsyncWorkspaceSequence: @unchecked Sendable {
  private let lock = NSLock()
  private let workspace: Workspace
  private let onRequest: @Sendable (Int) async throws -> Void
  private var requestCount = 0

  init(
    _ workspace: Workspace,
    onRequest: @escaping @Sendable (Int) async throws -> Void = { _ in }
  ) {
    self.workspace = workspace
    self.onRequest = onRequest
  }

  func next() async throws -> Workspace {
    let request = lock.withLock {
      requestCount += 1
      return requestCount
    }
    try await onRequest(request)
    return workspace
  }
}

private final class CallbackVerificationAsyncWorkspaceOverrideSequence: @unchecked Sendable {
  private let lock = NSLock()
  private let workspace: Workspace
  private let onRequest: @Sendable (Int) async throws -> Workspace?
  private var requestCount = 0

  init(
    _ workspace: Workspace,
    onRequest: @escaping @Sendable (Int) async throws -> Workspace? = { _ in nil }
  ) {
    self.workspace = workspace
    self.onRequest = onRequest
  }

  func next() async throws -> Workspace {
    let request = lock.withLock {
      requestCount += 1
      return requestCount
    }
    return try await onRequest(request) ?? workspace
  }
}

private actor CallbackVerificationAsyncGate {
  private var hasPaused = false
  private var pausedContinuation: CheckedContinuation<Void, Never>?
  private var resumeContinuation: CheckedContinuation<Void, Never>?

  func pause() async {
    await withCheckedContinuation { continuation in
      resumeContinuation = continuation
      hasPaused = true
      pausedContinuation?.resume()
      pausedContinuation = nil
    }
  }

  func waitUntilPaused() async {
    guard !hasPaused else { return }
    await withCheckedContinuation { continuation in
      pausedContinuation = continuation
    }
  }

  func release() {
    resumeContinuation?.resume()
    resumeContinuation = nil
  }
}

private struct CallbackVerificationProofSnapshotValue: Sendable {
  let proof: AgentEventCallbackVerificationProof
  let bytes: Data
}

private actor CallbackVerificationProofSnapshot {
  private var stored: CallbackVerificationProofSnapshotValue?

  func record(_ proof: AgentEventCallbackVerificationProof, bytes: Data) {
    stored = CallbackVerificationProofSnapshotValue(proof: proof, bytes: bytes)
  }

  func value() -> CallbackVerificationProofSnapshotValue? {
    stored
  }
}

private actor CallbackVerificationExchangeBarrier {
  private var startedContinuation: CheckedContinuation<Void, Never>?
  private var responseContinuation: CheckedContinuation<AgentEventHTTPResponse, Error>?
  private var challenge: String?
  private var hasStarted = false

  func hold(
    _ request: CallbackVerificationExchangeRequest
  ) async throws -> AgentEventHTTPResponse {
    challenge = try decodeChallenge(from: request.body)
    hasStarted = true
    startedContinuation?.resume()
    startedContinuation = nil
    return try await withCheckedThrowingContinuation { continuation in
      responseContinuation = continuation
    }
  }

  func waitForRequest() async {
    guard !hasStarted else { return }
    await withCheckedContinuation { continuation in
      startedContinuation = continuation
    }
  }

  func releaseEcho() {
    guard let challenge, let responseContinuation else { return }
    self.responseContinuation = nil
    self.challenge = nil
    do {
      responseContinuation.resume(returning: try makeEchoResponse(challenge: challenge))
    } catch {
      responseContinuation.resume(throwing: error)
    }
  }
}

private final class CallbackVerificationFixture: @unchecked Sendable {
  let rootURL: URL
  let ownedRoot: OwnedMCPFixtureRoot
  let profileID: UUID
  let subscriptionID: String
  let grantRevision: UInt64
  let keyReference: String
  let callbackURL: String
  let date: Date
  let workspace: Workspace
  let signingSecret: Data
  let clock: CallbackVerificationTestClock
  let secretStore: CallbackVerificationTestSecretStore
  let profileStore: AgentProfileStore
  let capabilityStore: AgentCapabilityStore
  let subscriptionStore: AgentEventSubscriptionStore
  let verificationStore: AgentEventCallbackVerificationStore
  let authority: AgentCapabilityAuthority
  let signingKeyStore: AgentEventSigningKeyStore
  let randomBytes: CallbackVerificationTestRandomBytes
  let workspaceState: CallbackVerificationWorkspaceState
  let verificationURL: URL
  let outboxURL: URL

  private init(
    rootURL: URL,
    ownedRoot: OwnedMCPFixtureRoot,
    profileID: UUID,
    subscriptionID: String,
    grantRevision: UInt64,
    keyReference: String,
    callbackURL: String,
    date: Date,
    workspace: Workspace,
    signingSecret: Data,
    clock: CallbackVerificationTestClock,
    secretStore: CallbackVerificationTestSecretStore,
    profileStore: AgentProfileStore,
    capabilityStore: AgentCapabilityStore,
    subscriptionStore: AgentEventSubscriptionStore,
    verificationStore: AgentEventCallbackVerificationStore,
    authority: AgentCapabilityAuthority,
    signingKeyStore: AgentEventSigningKeyStore,
    randomBytes: CallbackVerificationTestRandomBytes,
    workspaceState: CallbackVerificationWorkspaceState,
    verificationURL: URL,
    outboxURL: URL
  ) {
    self.rootURL = rootURL
    self.ownedRoot = ownedRoot
    self.profileID = profileID
    self.subscriptionID = subscriptionID
    self.grantRevision = grantRevision
    self.keyReference = keyReference
    self.callbackURL = callbackURL
    self.date = date
    self.workspace = workspace
    self.signingSecret = signingSecret
    self.clock = clock
    self.secretStore = secretStore
    self.profileStore = profileStore
    self.capabilityStore = capabilityStore
    self.subscriptionStore = subscriptionStore
    self.verificationStore = verificationStore
    self.authority = authority
    self.signingKeyStore = signingKeyStore
    self.randomBytes = randomBytes
    self.workspaceState = workspaceState
    self.verificationURL = verificationURL
    self.outboxURL = outboxURL
  }

  static func make() async throws -> CallbackVerificationFixture {
    let ownedRoot = try OwnedMCPFixtureRoot.create(kind: .eventCallbackVerification)
    var ownershipTransferred = false
    defer {
      if !ownershipTransferred {
        do {
          try ownedRoot.cleanup()
        } catch {
          Issue.record("Callback verification fixture construction cleanup failed: \(error)")
        }
      }
    }
    let rootURL = ownedRoot.url
    let integrationsURL = rootURL.appendingPathComponent("AgentIntegrations", isDirectory: true)
    let eventURL = integrationsURL.appendingPathComponent("AgentEvents", isDirectory: true)
    try FileManager.default.createDirectory(at: eventURL, withIntermediateDirectories: true)
    let profilesURL = integrationsURL.appendingPathComponent("profiles.json")
    let capabilitiesURL = integrationsURL.appendingPathComponent("capabilities.json")
    let previousCapabilitiesURL = integrationsURL.appendingPathComponent(
      "capabilities.previous.json"
    )
    let subscriptionURL = eventURL.appendingPathComponent("event-subscriptions.json")
    let verificationURL = eventURL.appendingPathComponent("callback-verification.json")
    let outboxURL = eventURL.appendingPathComponent("event-outbox.json")
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let clock = CallbackVerificationTestClock(date)
    let profileID = UUID()
    let noteID = UUID()
    let callbackURL = "https://example.com/events/callback"
    let workspace = Workspace(
      notes: [
        Note(
          id: noteID,
          title: "Synthetic verification note",
          body: "Synthetic verification content",
          createdAt: date,
          modifiedAt: date,
          agentAccess: true
        )
      ],
      selectedNoteID: noteID
    )
    let secretStore = CallbackVerificationTestSecretStore()
    let randomBytes = CallbackVerificationTestRandomBytes()
    let profileStore = AgentProfileStore(
      profilesURL: profilesURL,
      secretStore: secretStore,
      randomBytes: randomBytes,
      now: { clock.now() }
    )
    let profile = AgentIntegrationProfile(
      id: profileID,
      displayName: "Synthetic verification profile",
      createdAt: date,
      lastConnectedAt: nil,
      revokedAt: nil
    )
    try JSONEncoder().encode([profile]).write(to: profilesURL, options: .atomic)
    let capabilityStore = AgentCapabilityStore(
      capabilitiesURL: capabilitiesURL,
      previousCapabilitiesURL: previousCapabilitiesURL
    )
    let initialState = try await capabilityStore.loadOrMigrate(
      activeProfileIDs: [profileID],
      workspace: workspace
    )
    guard let initialRevision = initialState.profiles[profileID]?.grantRevision else {
      throw CallbackVerificationTestError.unexpectedRequest
    }
    let capabilities = AgentProfileCapabilities(
      profileID: profileID,
      grantRevision: initialRevision + 1,
      allowedCapabilities: [.readNotes],
      grants: [
        AgentResourceGrant(scope: .note(noteID: noteID), authority: .read)
      ],
      allowsEventObservation: true
    )
    _ = try await capabilityStore.replaceProfile(
      capabilities,
      expectedGrantRevision: initialRevision
    )
    let authority = AgentCapabilityAuthority(store: capabilityStore)
    let keyReference = UUID().uuidString.lowercased()
    let signingSecret = Data(repeating: 0x5a, count: 32)
    let signingKeyStore = AgentEventSigningKeyStore(secretStore: secretStore)
    let subscriptionStore = AgentEventSubscriptionStore(fileURL: subscriptionURL)
    try await subscriptionStore.reserveSigningKeyReference(keyReference)
    try signingKeyStore.store(secretData: signingSecret, reference: keyReference)
    let subscriptionID = AgentEventSubscriptionIdentity.subscriptionID(
      profileID: profileID,
      event: .noteUpdated,
      scope: .note(noteID: noteID),
      callbackURL: callbackURL
    )
    _ = try await subscriptionStore.createOrRefresh(
      AgentEventPendingSubscription(
        subscriptionID: subscriptionID,
        profileID: profileID,
        event: .noteUpdated,
        scope: .note(noteID: noteID),
        callbackURL: callbackURL,
        signingKeyReference: keyReference,
        grantRevision: capabilities.grantRevision,
        createdAt: date,
        updatedAt: date,
        expiresAt: date.addingTimeInterval(3_600),
        revision: 1
      ),
      now: date
    )
    let verificationStore = AgentEventCallbackVerificationStore(
      fileURL: verificationURL,
      now: { clock.now() }
    )
    let fixture = CallbackVerificationFixture(
      rootURL: rootURL,
      ownedRoot: ownedRoot,
      profileID: profileID,
      subscriptionID: subscriptionID,
      grantRevision: capabilities.grantRevision,
      keyReference: keyReference,
      callbackURL: callbackURL,
      date: date,
      workspace: workspace,
      signingSecret: signingSecret,
      clock: clock,
      secretStore: secretStore,
      profileStore: profileStore,
      capabilityStore: capabilityStore,
      subscriptionStore: subscriptionStore,
      verificationStore: verificationStore,
      authority: authority,
      signingKeyStore: signingKeyStore,
      randomBytes: randomBytes,
      workspaceState: CallbackVerificationWorkspaceState(workspace),
      verificationURL: verificationURL,
      outboxURL: outboxURL
    )
    ownershipTransferred = true
    return fixture
  }

  var binding: AgentEventCallbackVerificationBinding {
    binding(subscriptionID: subscriptionID, profileID: profileID, keyReference: keyReference)
  }

  var workspaceProvider: AgentEventWorkspaceProvider {
    let workspaceState = workspaceState
    return { workspaceState.current() }
  }

  func binding(
    subscriptionID: String,
    profileID: UUID,
    keyReference: String
  ) -> AgentEventCallbackVerificationBinding {
    AgentEventCallbackVerificationBinding(
      profileID: profileID,
      subscriptionID: subscriptionID,
      subscriptionRevision: 1,
      grantRevision: grantRevision,
      signingKeyReference: keyReference
    )
  }

  func intent(
    id: UUID,
    nonceByte: UInt8,
    binding: AgentEventCallbackVerificationBinding? = nil
  ) -> AgentEventCallbackVerificationIntent {
    AgentEventCallbackVerificationIntent(
      id: id,
      binding: binding ?? self.binding,
      nonceDigest: Data(repeating: nonceByte, count: 32),
      createdAt: date,
      expiresAt: date.addingTimeInterval(60)
    )
  }

  func verificationStore(using writer: CallbackVerificationFileWriter)
    -> AgentEventCallbackVerificationStore
  {
    let clock = clock
    return AgentEventCallbackVerificationStore(
      fileURL: verificationURL,
      now: { clock.now() },
      fileWriter: { data, url in
        try writer.write(data, to: url)
      }
    )
  }

  func addSubscription(callbackURL: String) async throws -> String {
    guard let current = try await subscriptionStore.currentSubscription(id: subscriptionID) else {
      throw CallbackVerificationTestError.unexpectedRequest
    }
    let reference = UUID().uuidString.lowercased()
    try await subscriptionStore.reserveSigningKeyReference(reference)
    try signingKeyStore.store(secretData: signingSecret, reference: reference)
    let newID = AgentEventSubscriptionIdentity.subscriptionID(
      profileID: profileID,
      event: current.event,
      scope: current.scope,
      callbackURL: callbackURL
    )
    _ = try await subscriptionStore.createOrRefresh(
      AgentEventPendingSubscription(
        subscriptionID: newID,
        profileID: profileID,
        event: current.event,
        scope: current.scope,
        callbackURL: callbackURL,
        signingKeyReference: reference,
        grantRevision: current.grantRevision,
        createdAt: date,
        updatedAt: date,
        expiresAt: date.addingTimeInterval(3_600),
        revision: 1
      ),
      now: date
    )
    return newID
  }

  func service(
    exchange: CallbackVerificationTestExchange,
    verificationStore: AgentEventCallbackVerificationStore? = nil
  ) -> AgentEventCallbackVerificationService {
    let clock = clock
    return AgentEventCallbackVerificationService(
      authority: authority,
      profileStore: profileStore,
      subscriptionStore: subscriptionStore,
      signingKeyStore: signingKeyStore,
      verificationStore: verificationStore ?? self.verificationStore,
      randomBytes: randomBytes,
      now: { clock.now() },
      exchange: { callbackURL, headers, body in
        try await exchange.post(callbackURL: callbackURL, headers: headers, body: body)
      }
    )
  }

  func refreshSubscription() async throws {
    guard let current = try await subscriptionStore.currentSubscription(id: subscriptionID) else {
      throw CallbackVerificationTestError.unexpectedRequest
    }
    clock.set(date.addingTimeInterval(1))
    let nextReference = UUID().uuidString.lowercased()
    try await subscriptionStore.reserveSigningKeyReference(nextReference)
    try signingKeyStore.store(secretData: signingSecret, reference: nextReference)
    _ = try await subscriptionStore.createOrRefresh(
      AgentEventPendingSubscription(
        subscriptionID: current.subscriptionID,
        profileID: current.profileID,
        event: current.event,
        scope: current.scope,
        callbackURL: current.callbackURL,
        signingKeyReference: nextReference,
        grantRevision: current.grantRevision,
        createdAt: current.createdAt,
        updatedAt: clock.now(),
        expiresAt: clock.now().addingTimeInterval(3_600),
        revision: current.revision + 1
      ),
      now: clock.now()
    )
  }

  func removeSubscription() async throws {
    _ = try await subscriptionStore.remove(
      subscriptionID: subscriptionID,
      profileID: profileID
    )
  }

  func setObservationPermission(_ allowsObservation: Bool) async throws {
    let state = try await capabilityStore.currentState()
    guard let current = state.profiles[profileID] else {
      throw CallbackVerificationTestError.unexpectedRequest
    }
    _ = try await capabilityStore.replaceProfile(
      AgentProfileCapabilities(
        profileID: profileID,
        grantRevision: current.grantRevision + 1,
        allowedCapabilities: current.allowedCapabilities,
        grants: current.grants,
        allowsEventObservation: allowsObservation
      ),
      expectedGrantRevision: current.grantRevision
    )
  }

  func remove() {
    do {
      try ownedRoot.cleanup()
    } catch {
      Issue.record("Callback verification fixture cleanup failed: \(error)")
    }
  }
}
