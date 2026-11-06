import FleckCore
import Foundation

enum AgentEventCallbackVerificationError: Error, Equatable, Sendable {
  case notAuthorized
  case verificationInProgress
  case capacityExceeded
  case keyUnavailable
  case randomUnavailable
  case verificationFailed
  case timedOut
  case cancelled
  case busy
  case transportFailure
  case storageFailure
}

typealias AgentEventCallbackVerificationHTTPExchange =
  @Sendable (
    _ callbackURL: String,
    _ headers: [AgentEventHTTPHeader],
    _ body: Data
  ) async throws -> AgentEventHTTPResponse

struct AgentEventCallbackVerificationService: Sendable {
  private struct VerificationRequest: Encodable {
    let type: String
    let challenge: String
  }

  private struct VerificationResponse: Decodable {
    let challenge: String

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: VerificationCodingKey.self)
      try requireExactKeys(container, ["challenge"])
      challenge = try container.decode(String.self, forKey: VerificationCodingKey("challenge"))
    }
  }

  private static let challengeByteCount = 32
  private static let maximumResponseBodyBytes = 1_024

  private let authority: AgentCapabilityAuthority
  private let profileStore: AgentProfileStore
  private let subscriptionStore: AgentEventSubscriptionStore
  private let signingKeyStore: AgentEventSigningKeyStore
  private let verificationStore: AgentEventCallbackVerificationStore
  private let randomBytes: any AgentRandomBytesProviding
  private let now: @Sendable () -> Date
  private let exchange: AgentEventCallbackVerificationHTTPExchange

  init(
    authority: AgentCapabilityAuthority,
    profileStore: AgentProfileStore = AgentProfileStore(),
    subscriptionStore: AgentEventSubscriptionStore = AgentEventSubscriptionStore(),
    signingKeyStore: AgentEventSigningKeyStore = AgentEventSigningKeyStore(),
    verificationStore: AgentEventCallbackVerificationStore = AgentEventCallbackVerificationStore(),
    randomBytes: any AgentRandomBytesProviding = AgentSystemRandomBytesProvider(),
    now: @escaping @Sendable () -> Date = { Date() },
    exchange: @escaping AgentEventCallbackVerificationHTTPExchange = { callbackURL, headers, body in
      try await AgentEventHTTPTransport().post(
        callbackURL: callbackURL,
        headers: headers,
        body: body
      )
    }
  ) {
    self.authority = authority
    self.profileStore = profileStore
    self.subscriptionStore = subscriptionStore
    self.signingKeyStore = signingKeyStore
    self.verificationStore = verificationStore
    self.randomBytes = randomBytes
    self.now = now
    self.exchange = exchange
  }

  func verifyPending(
    profileID: UUID,
    subscriptionID: String,
    workspaceProvider: @escaping AgentEventWorkspaceProvider,
    ownerDeliveryControl: AgentEventDeliveryControl? = nil,
    requestOriginID: UUID? = nil
  ) async throws -> AgentEventCallbackVerificationProof {
    let expectedTemporaryExclusionGeneration = authority.temporaryExclusionGeneration
    let subscription = try await currentPendingSubscription(
      profileID: profileID,
      subscriptionID: subscriptionID,
      workspaceProvider: workspaceProvider,
      expectedTemporaryExclusionGeneration: expectedTemporaryExclusionGeneration,
      ownerDeliveryControl: ownerDeliveryControl
    )
    try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
    let binding = Self.binding(for: subscription)

    do {
      if let proof = try verificationStore.currentProof(for: binding) {
        do {
          let current = try await requireCurrent(
            binding,
            profileID: profileID,
            subscriptionID: subscriptionID,
            workspaceProvider: workspaceProvider,
            expectedTemporaryExclusionGeneration: expectedTemporaryExclusionGeneration,
            ownerDeliveryControl: ownerDeliveryControl
          )
          guard proof.expiresAt <= current.expiresAt else {
            try? verificationStore.removeProof(for: binding, generatedBy: proof.originIntentID)
            throw AgentEventCallbackVerificationError.storageFailure
          }
          if let currentProof = try verificationStore.currentProof(for: binding) {
            guard currentProof.expiresAt <= current.expiresAt else {
              try? verificationStore.removeProof(
                for: binding,
                generatedBy: currentProof.originIntentID
              )
              throw AgentEventCallbackVerificationError.storageFailure
            }
            try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
            return currentProof
          }
        } catch {
          do {
            try verificationStore.removeProof(for: binding, generatedBy: proof.originIntentID)
          } catch let storeError as AgentEventCallbackVerificationStoreError {
            throw Self.mapStoreError(storeError)
          }
          throw error
        }
      }
    } catch let error as AgentEventCallbackVerificationStoreError {
      throw Self.mapStoreError(error)
    }

    let endpointCacheEntry: AgentEventEndpointVerificationCacheEntry?
    do {
      endpointCacheEntry = try verificationStore.endpointCacheEntry(
        profileID: subscription.profileID,
        canonicalCallbackURL: subscription.callbackURL,
        grantRevision: subscription.grantRevision,
        signingKeyReference: subscription.signingKeyReference
      )
    } catch let error as AgentEventCallbackVerificationStoreError {
      throw Self.mapStoreError(error)
    }
    if let endpointCacheEntry {
      return try await materializeCachedProof(
        endpointCacheEntry,
        binding: binding,
        profileID: profileID,
        subscriptionID: subscriptionID,
        workspaceProvider: workspaceProvider,
        expectedTemporaryExclusionGeneration: expectedTemporaryExclusionGeneration,
        ownerDeliveryControl: ownerDeliveryControl,
        requestOriginID: requestOriginID
      )
    }

    let challengeData: Data
    do {
      challengeData = try randomBytes.randomBytes(count: Self.challengeByteCount)
    } catch {
      throw AgentEventCallbackVerificationError.randomUnavailable
    }
    guard challengeData.count == Self.challengeByteCount else {
      throw AgentEventCallbackVerificationError.randomUnavailable
    }
    let challenge = challengeData.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
    let nonceDigest = AgentCredentialSecurity.sha256(Data(challenge.utf8))
    let intentTime = now()
    guard Self.isValidDate(intentTime), intentTime < subscription.expiresAt else {
      throw AgentEventCallbackVerificationError.notAuthorized
    }
    let intentExpiry = min(
      intentTime.addingTimeInterval(AgentEventCallbackVerificationStore.maximumIntentLifetime),
      subscription.expiresAt
    )
    let intent = AgentEventCallbackVerificationIntent(
      id: requestOriginID ?? UUID(),
      binding: binding,
      nonceDigest: nonceDigest,
      createdAt: intentTime,
      expiresAt: intentExpiry
    )

    do {
      let current = try await requireCurrent(
        binding,
        profileID: profileID,
        subscriptionID: subscriptionID,
        workspaceProvider: workspaceProvider,
        expectedTemporaryExclusionGeneration: expectedTemporaryExclusionGeneration,
        ownerDeliveryControl: ownerDeliveryControl
      )
      let beginTime = now()
      guard Self.isValidDate(beginTime), beginTime < current.expiresAt else {
        throw AgentEventCallbackVerificationError.notAuthorized
      }
      guard beginTime >= intent.createdAt, beginTime < intent.expiresAt else {
        throw AgentEventCallbackVerificationError.verificationFailed
      }
      try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
      try verificationStore.begin(intent)
    } catch let error as AgentEventCallbackVerificationStoreError {
      throw Self.mapStoreError(error)
    }

    do {
      return try await performVerification(
        intent,
        challenge: challenge,
        profileID: profileID,
        subscriptionID: subscriptionID,
        workspaceProvider: workspaceProvider,
        expectedTemporaryExclusionGeneration: expectedTemporaryExclusionGeneration,
        ownerDeliveryControl: ownerDeliveryControl
      )
    } catch {
      try? verificationStore.cancel(intent)
      do {
        try verificationStore.removeProof(for: binding, generatedBy: intent.id)
      } catch let storeError as AgentEventCallbackVerificationStoreError {
        throw Self.mapStoreError(storeError)
      }
      throw error
    }
  }

  private func performVerification(
    _ intent: AgentEventCallbackVerificationIntent,
    challenge: String,
    profileID: UUID,
    subscriptionID: String,
    workspaceProvider: AgentEventWorkspaceProvider,
    expectedTemporaryExclusionGeneration: UUID?,
    ownerDeliveryControl: AgentEventDeliveryControl?
  ) async throws -> AgentEventCallbackVerificationProof {
    let subscription = try await requireCurrent(
      intent.binding,
      profileID: profileID,
      subscriptionID: subscriptionID,
      workspaceProvider: workspaceProvider,
      expectedTemporaryExclusionGeneration: expectedTemporaryExclusionGeneration,
      ownerDeliveryControl: ownerDeliveryControl
    )
    try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
    let keyReadTime = now()
    guard
      Self.isValidDate(keyReadTime),
      keyReadTime >= intent.createdAt,
      keyReadTime < intent.expiresAt,
      keyReadTime < subscription.expiresAt
    else {
      throw AgentEventCallbackVerificationError.verificationFailed
    }
    do {
      try verificationStore.observe(intent)
    } catch let error as AgentEventCallbackVerificationStoreError {
      throw Self.mapStoreError(error)
    }
    try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
    let secret: Data
    do {
      secret = try signingKeyStore.validatedSecretData(
        reference: intent.binding.signingKeyReference
      )
    } catch {
      throw AgentEventCallbackVerificationError.keyUnavailable
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let body: Data
    do {
      body = try encoder.encode(VerificationRequest(type: "verification", challenge: challenge))
    } catch {
      throw AgentEventCallbackVerificationError.verificationFailed
    }
    let webhookID = "msg_verification_\(intent.id.uuidString.lowercased())"
    let requestSubscription = try await requireCurrent(
      intent.binding,
      profileID: profileID,
      subscriptionID: subscriptionID,
      workspaceProvider: workspaceProvider,
      expectedTemporaryExclusionGeneration: expectedTemporaryExclusionGeneration,
      ownerDeliveryControl: ownerDeliveryControl
    )
    try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
    let requestTime = now()
    guard
      Self.isValidDate(requestTime),
      requestTime >= intent.createdAt,
      requestTime < intent.expiresAt,
      requestTime < requestSubscription.expiresAt
    else {
      throw AgentEventCallbackVerificationError.verificationFailed
    }
    let signature: AgentEventWebhookSignature
    do {
      signature = try AgentEventWebhookSigner.sign(
        id: webhookID,
        timestamp: requestTime,
        body: body,
        secret: secret
      )
    } catch {
      throw AgentEventCallbackVerificationError.verificationFailed
    }
    let headers = [
      AgentEventHTTPHeader(name: "content-type", value: "application/json"),
      AgentEventHTTPHeader(name: "webhook-id", value: signature.webhookID),
      AgentEventHTTPHeader(name: "webhook-timestamp", value: signature.webhookTimestamp),
      AgentEventHTTPHeader(name: "webhook-signature", value: signature.webhookSignature),
      AgentEventHTTPHeader(
        name: "x-mcp-subscription-id",
        value: intent.binding.subscriptionID
      ),
    ]
    let finalRequestTime = now()
    guard
      Self.isValidDate(finalRequestTime),
      finalRequestTime >= intent.createdAt,
      finalRequestTime < intent.expiresAt,
      finalRequestTime < requestSubscription.expiresAt
    else {
      throw AgentEventCallbackVerificationError.verificationFailed
    }
    do {
      try verificationStore.observe(intent)
    } catch let error as AgentEventCallbackVerificationStoreError {
      throw Self.mapStoreError(error)
    }
    try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
    _ = try await requireCurrent(
      intent.binding,
      profileID: profileID,
      subscriptionID: subscriptionID,
      workspaceProvider: workspaceProvider,
      expectedTemporaryExclusionGeneration: expectedTemporaryExclusionGeneration,
      ownerDeliveryControl: ownerDeliveryControl
    )
    try Task.checkCancellation()
    let response: AgentEventHTTPResponse
    do {
      response = try await exchange(requestSubscription.callbackURL, headers, body)
    } catch let error as AgentEventHTTPTransportError {
      switch error {
      case .timedOut:
        throw AgentEventCallbackVerificationError.timedOut
      case .cancelled:
        throw AgentEventCallbackVerificationError.cancelled
      case .busy:
        throw AgentEventCallbackVerificationError.busy
      case .invalidRequest, .transportFailure:
        throw AgentEventCallbackVerificationError.transportFailure
      }
    } catch is CancellationError {
      throw AgentEventCallbackVerificationError.cancelled
    } catch {
      throw AgentEventCallbackVerificationError.transportFailure
    }

    try Task.checkCancellation()
    let responseSubscription = try await requireCurrent(
      intent.binding,
      profileID: profileID,
      subscriptionID: subscriptionID,
      workspaceProvider: workspaceProvider,
      expectedTemporaryExclusionGeneration: expectedTemporaryExclusionGeneration,
      ownerDeliveryControl: ownerDeliveryControl
    )
    let responseTime = now()
    guard
      Self.isValidDate(responseTime),
      responseTime >= intent.createdAt,
      responseTime < intent.expiresAt,
      responseTime < responseSubscription.expiresAt,
      (200...299).contains(response.statusCode),
      response.body.count <= Self.maximumResponseBodyBytes
    else {
      throw AgentEventCallbackVerificationError.verificationFailed
    }

    let echo: VerificationResponse
    do {
      echo = try JSONDecoder().decode(VerificationResponse.self, from: response.body)
    } catch {
      throw AgentEventCallbackVerificationError.verificationFailed
    }
    let expectedDigest = AgentCredentialSecurity.sha256(Data(challenge.utf8))
    let responseDigest = AgentCredentialSecurity.sha256(Data(echo.challenge.utf8))
    guard
      AgentCredentialSecurity.constantTimeEqual(intent.nonceDigest, expectedDigest),
      AgentCredentialSecurity.constantTimeEqual(expectedDigest, responseDigest)
    else {
      throw AgentEventCallbackVerificationError.verificationFailed
    }

    let commitSubscription = try await requireCurrent(
      intent.binding,
      profileID: profileID,
      subscriptionID: subscriptionID,
      workspaceProvider: workspaceProvider,
      expectedTemporaryExclusionGeneration: expectedTemporaryExclusionGeneration,
      ownerDeliveryControl: ownerDeliveryControl
    )
    try Task.checkCancellation()
    let commitCheckpointTime = now()
    guard
      Self.isValidDate(commitCheckpointTime),
      commitCheckpointTime >= intent.createdAt,
      commitCheckpointTime < intent.expiresAt,
      commitCheckpointTime < commitSubscription.expiresAt
    else {
      throw AgentEventCallbackVerificationError.verificationFailed
    }
    let proof: AgentEventCallbackVerificationProof
    do {
      try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
      proof = try verificationStore.complete(
        intent,
        subscriptionExpiresAt: commitSubscription.expiresAt,
        canonicalCallbackURL: commitSubscription.callbackURL
      )
      try Task.checkCancellation()
      try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
    } catch let error as AgentEventCallbackVerificationStoreError {
      throw Self.mapStoreError(error)
    }
    let postCommitSubscription = try await requireCurrent(
      intent.binding,
      profileID: profileID,
      subscriptionID: subscriptionID,
      workspaceProvider: workspaceProvider,
      expectedTemporaryExclusionGeneration: expectedTemporaryExclusionGeneration,
      ownerDeliveryControl: ownerDeliveryControl
    )
    try Task.checkCancellation()

    let cached: AgentEventCallbackVerificationProof
    do {
      guard let stored = try verificationStore.currentProof(for: intent.binding)
      else {
        throw AgentEventCallbackVerificationError.verificationFailed
      }
      cached = stored
    } catch let error as AgentEventCallbackVerificationStoreError {
      throw Self.mapStoreError(error)
    }
    guard cached == proof else {
      throw AgentEventCallbackVerificationError.verificationFailed
    }
    guard cached.expiresAt <= postCommitSubscription.expiresAt else {
      throw AgentEventCallbackVerificationError.storageFailure
    }
    let returnSubscription = try await requireCurrent(
      intent.binding,
      profileID: profileID,
      subscriptionID: subscriptionID,
      workspaceProvider: workspaceProvider,
      expectedTemporaryExclusionGeneration: expectedTemporaryExclusionGeneration,
      ownerDeliveryControl: ownerDeliveryControl
    )
    try Task.checkCancellation()
    let current: AgentEventCallbackVerificationProof?
    do {
      current = try verificationStore.currentProof(for: intent.binding)
    } catch let error as AgentEventCallbackVerificationStoreError {
      throw Self.mapStoreError(error)
    }
    guard let current, current == proof, current.expiresAt <= returnSubscription.expiresAt else {
      throw AgentEventCallbackVerificationError.verificationFailed
    }
    try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
    return current
  }

  private func materializeCachedProof(
    _ entry: AgentEventEndpointVerificationCacheEntry,
    binding: AgentEventCallbackVerificationBinding,
    profileID: UUID,
    subscriptionID: String,
    workspaceProvider: AgentEventWorkspaceProvider,
    expectedTemporaryExclusionGeneration: UUID?,
    ownerDeliveryControl: AgentEventDeliveryControl?,
    requestOriginID: UUID?
  ) async throws -> AgentEventCallbackVerificationProof {
    let originID = requestOriginID ?? UUID()
    do {
      let currentSubscription = try await requireCurrent(
        binding,
        profileID: profileID,
        subscriptionID: subscriptionID,
        workspaceProvider: workspaceProvider,
        expectedTemporaryExclusionGeneration: expectedTemporaryExclusionGeneration,
        ownerDeliveryControl: ownerDeliveryControl
      )
      guard
        AgentEventCallbackVerificationStore.canonicalURLSHA256Digest(
          currentSubscription.callbackURL
        ) == entry.canonicalCallbackURLDigest
      else {
        throw AgentEventCallbackVerificationError.notAuthorized
      }
      try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
      do {
        _ = try signingKeyStore.validatedSecretData(reference: binding.signingKeyReference)
      } catch {
        throw AgentEventCallbackVerificationError.keyUnavailable
      }
      try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
      try Task.checkCancellation()
      let proof: AgentEventCallbackVerificationProof
      do {
        proof = try verificationStore.materializeProof(
          cachedEntry: entry,
          targetBinding: binding,
          subscriptionExpiresAt: currentSubscription.expiresAt,
          originID: originID
        )
      } catch let error as AgentEventCallbackVerificationStoreError {
        throw Self.mapStoreError(error)
      }
      try Task.checkCancellation()
      let postCommitSubscription = try await requireCurrent(
        binding,
        profileID: profileID,
        subscriptionID: subscriptionID,
        workspaceProvider: workspaceProvider,
        expectedTemporaryExclusionGeneration: expectedTemporaryExclusionGeneration,
        ownerDeliveryControl: ownerDeliveryControl
      )
      try Task.checkCancellation()
      let stored: AgentEventCallbackVerificationProof?
      do {
        stored = try verificationStore.currentProof(for: binding)
      } catch let error as AgentEventCallbackVerificationStoreError {
        throw Self.mapStoreError(error)
      }
      guard
        proof.binding == binding,
        proof.verifiedAt == entry.verifiedAt,
        proof.expiresAt <= entry.expiresAt,
        proof.expiresAt <= postCommitSubscription.expiresAt,
        proof.expiresAt > now(),
        stored == proof
      else {
        throw AgentEventCallbackVerificationError.verificationFailed
      }
      let returnSubscription = try await requireCurrent(
        binding,
        profileID: profileID,
        subscriptionID: subscriptionID,
        workspaceProvider: workspaceProvider,
        expectedTemporaryExclusionGeneration: expectedTemporaryExclusionGeneration,
        ownerDeliveryControl: ownerDeliveryControl
      )
      try Task.checkCancellation()
      let current: AgentEventCallbackVerificationProof?
      do {
        current = try verificationStore.currentProof(for: binding)
      } catch let error as AgentEventCallbackVerificationStoreError {
        throw Self.mapStoreError(error)
      }
      guard
        let current,
        current == proof,
        current.expiresAt > now(),
        current.expiresAt <= returnSubscription.expiresAt
      else {
        throw AgentEventCallbackVerificationError.verificationFailed
      }
      try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
      return current
    } catch {
      do {
        try verificationStore.removeProof(for: binding, generatedBy: originID)
      } catch let storeError as AgentEventCallbackVerificationStoreError {
        throw Self.mapStoreError(storeError)
      }
      throw error
    }
  }

  private func requireCurrent(
    _ binding: AgentEventCallbackVerificationBinding,
    profileID: UUID,
    subscriptionID: String,
    workspaceProvider: AgentEventWorkspaceProvider,
    expectedTemporaryExclusionGeneration: UUID?,
    ownerDeliveryControl: AgentEventDeliveryControl?
  ) async throws -> AgentEventPendingSubscription {
    let subscription = try await currentPendingSubscription(
      profileID: profileID,
      subscriptionID: subscriptionID,
      workspaceProvider: workspaceProvider,
      expectedTemporaryExclusionGeneration: expectedTemporaryExclusionGeneration,
      ownerDeliveryControl: ownerDeliveryControl
    )
    try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
    guard Self.binding(for: subscription) == binding else {
      throw AgentEventCallbackVerificationError.notAuthorized
    }
    return subscription
  }

  private func currentPendingSubscription(
    profileID: UUID,
    subscriptionID: String,
    workspaceProvider: AgentEventWorkspaceProvider,
    expectedTemporaryExclusionGeneration: UUID?,
    ownerDeliveryControl: AgentEventDeliveryControl? = nil
  ) async throws -> AgentEventPendingSubscription {
    guard Self.isValidSubscriptionID(subscriptionID) else {
      throw AgentEventCallbackVerificationError.notAuthorized
    }
    let profiles: [AgentIntegrationProfile]
    do {
      profiles = try await profileStore.activeProfiles()
      try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
    } catch {
      if error is AgentEventCallbackVerificationError { throw error }
      throw AgentEventCallbackVerificationError.notAuthorized
    }
    guard profiles.contains(where: { $0.id == profileID && !$0.isRevoked }) else {
      throw AgentEventCallbackVerificationError.notAuthorized
    }

    let subscription: AgentEventPendingSubscription?
    do {
      subscription = try await subscriptionStore.currentSubscription(id: subscriptionID)
      try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
    } catch {
      if error is AgentEventCallbackVerificationError { throw error }
      throw AgentEventCallbackVerificationError.storageFailure
    }
    guard let subscription,
      subscription.subscriptionID == subscriptionID,
      subscription.profileID == profileID,
      subscription.status == .pending,
      subscription.revision > 0,
      Self.isValidSigningKeyReference(subscription.signingKeyReference)
    else {
      throw AgentEventCallbackVerificationError.notAuthorized
    }
    let subscriptionTime = now()
    guard Self.isValidDate(subscriptionTime) else {
      throw AgentEventCallbackVerificationError.storageFailure
    }
    guard subscription.expiresAt > subscriptionTime else {
      throw AgentEventCallbackVerificationError.notAuthorized
    }

    let workspace: Workspace
    do {
      workspace = try await workspaceProvider()
      try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
    } catch {
      if error is AgentEventCallbackVerificationError { throw error }
      throw AgentEventCallbackVerificationError.notAuthorized
    }
    do {
      try await authority.assertEventObservationCurrent(
        profileID: profileID,
        grantRevision: subscription.grantRevision,
        scope: subscription.scope,
        workspace: workspace
      )
      try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
    } catch {
      throw AgentEventCallbackVerificationError.notAuthorized
    }

    let currentProfiles: [AgentIntegrationProfile]
    do {
      currentProfiles = try await profileStore.activeProfiles()
      try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
    } catch {
      if error is AgentEventCallbackVerificationError { throw error }
      throw AgentEventCallbackVerificationError.notAuthorized
    }
    guard currentProfiles.contains(where: { $0.id == profileID && !$0.isRevoked }) else {
      throw AgentEventCallbackVerificationError.notAuthorized
    }

    let currentSubscription: AgentEventPendingSubscription?
    do {
      currentSubscription = try await subscriptionStore.currentSubscription(id: subscriptionID)
      try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
    } catch {
      if error is AgentEventCallbackVerificationError { throw error }
      throw AgentEventCallbackVerificationError.storageFailure
    }
    guard currentSubscription == subscription else {
      throw AgentEventCallbackVerificationError.notAuthorized
    }
    if let ownerDeliveryControl {
      let binding = Self.binding(for: subscription)
      guard
        ownerDeliveryControl.enabled,
        ownerDeliveryControl.binding == binding,
        subscription.deliveryControl == ownerDeliveryControl,
        subscriptionStore.isCurrentOwnerDeliveryControl(
          binding: binding,
          control: ownerDeliveryControl
        )
      else {
        throw AgentEventCallbackVerificationError.notAuthorized
      }
    }
    let authorizationTime = now()
    guard Self.isValidDate(authorizationTime) else {
      throw AgentEventCallbackVerificationError.storageFailure
    }
    guard subscription.expiresAt > authorizationTime else {
      throw AgentEventCallbackVerificationError.notAuthorized
    }
    try requireTemporaryExclusionGeneration(expectedTemporaryExclusionGeneration)
    return subscription
  }

  private func requireTemporaryExclusionGeneration(_ expected: UUID?) throws {
    guard authority.temporaryExclusionGeneration == expected else {
      throw AgentEventCallbackVerificationError.notAuthorized
    }
  }

  private static func binding(
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

  private static func isValidSubscriptionID(_ value: String) -> Bool {
    let bytes = Array(value.utf8)
    return bytes.count == 68
      && value.hasPrefix("evt_")
      && bytes.dropFirst(4).allSatisfy {
        (48...57).contains($0) || (97...102).contains($0)
      }
  }

  private static func isValidSigningKeyReference(_ value: String) -> Bool {
    guard let reference = UUID(uuidString: value) else { return false }
    return reference.uuidString.lowercased() == value
  }

  private static func isValidDate(_ value: Date) -> Bool {
    let seconds = value.timeIntervalSince1970
    return seconds.isFinite && seconds >= 0
  }

  private static func mapStoreError(
    _ error: AgentEventCallbackVerificationStoreError
  ) -> AgentEventCallbackVerificationError {
    switch error {
    case .invalidBinding, .staleIntent, .storageFailure:
      return .storageFailure
    case .capacityExceeded:
      return .capacityExceeded
    case .verificationInProgress:
      return .verificationInProgress
    }
  }
}

private struct VerificationCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int? = nil

  init(_ string: String) {
    stringValue = string
  }

  init?(stringValue: String) {
    self.init(stringValue)
  }

  init?(intValue: Int) {
    return nil
  }
}

private func requireExactKeys<Key: CodingKey>(
  _ container: KeyedDecodingContainer<Key>,
  _ allowed: Set<String>
) throws {
  let actual = Set(container.allKeys.map(\.stringValue))
  guard container.allKeys.count == actual.count, actual == allowed else {
    throw AgentEventCallbackVerificationError.verificationFailed
  }
}
