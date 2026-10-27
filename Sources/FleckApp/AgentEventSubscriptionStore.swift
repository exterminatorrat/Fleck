import FleckCore
import Foundation

enum AgentEventSubscriptionError: Error, Equatable, Sendable {
  case invalidConfiguration
  case capacityExceeded
  case storageFailure
}

enum AgentEventSigningKeyDisposition: Equatable, Sendable {
  case preserveCurrent
  case rotateToStagedKey
}

enum AgentEventPendingStatus: String, Codable, Equatable, Sendable {
  case pending
}

struct AgentEventPreviousSigningKey: Codable, Equatable, Sendable {
  static let maximumLifetime: TimeInterval = 60

  let reference: String
  let startedAt: Date
  let expiresAt: Date

  init(reference: String, startedAt: Date, expiresAt: Date) {
    self.reference = reference
    self.startedAt = startedAt
    self.expiresAt = expiresAt
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: EventStoreCodingKey.self)
    let keys = Set(container.allKeys.map(\.stringValue))
    guard keys == ["reference", "startedAt", "expiresAt"] else {
      throw AgentEventSubscriptionError.storageFailure
    }
    reference = try container.decode(String.self, forKey: EventStoreCodingKey("reference"))
    startedAt = try container.decode(Date.self, forKey: EventStoreCodingKey("startedAt"))
    expiresAt = try container.decode(Date.self, forKey: EventStoreCodingKey("expiresAt"))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: EventStoreCodingKey.self)
    try container.encode(reference, forKey: EventStoreCodingKey("reference"))
    try container.encode(startedAt, forKey: EventStoreCodingKey("startedAt"))
    try container.encode(expiresAt, forKey: EventStoreCodingKey("expiresAt"))
  }
}

struct AgentEventDeliveryControl: Codable, Equatable, Sendable {
  let generationID: UUID
  let binding: AgentEventCallbackVerificationBinding
  let enabled: Bool
  let allowsAutomaticRenewal: Bool

  init(
    generationID: UUID,
    binding: AgentEventCallbackVerificationBinding,
    enabled: Bool,
    allowsAutomaticRenewal: Bool = false
  ) {
    self.generationID = generationID
    self.binding = binding
    self.enabled = enabled
    self.allowsAutomaticRenewal = allowsAutomaticRenewal
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: EventStoreCodingKey.self)
    let keys = Set(container.allKeys.map(\.stringValue))
    let baseKeys: Set<String> = ["generationID", "binding", "enabled"]
    guard keys == baseKeys || keys == baseKeys.union(["allowsAutomaticRenewal"])
    else {
      throw AgentEventSubscriptionError.storageFailure
    }
    let generation = try container.decode(
      String.self,
      forKey: EventStoreCodingKey("generationID")
    )
    guard
      let generationID = UUID(uuidString: generation),
      generationID.uuidString.lowercased() == generation
    else {
      throw AgentEventSubscriptionError.storageFailure
    }
    self.generationID = generationID
    binding = try container.decode(
      AgentEventCallbackVerificationBinding.self,
      forKey: EventStoreCodingKey("binding")
    )
    enabled = try container.decode(Bool.self, forKey: EventStoreCodingKey("enabled"))
    allowsAutomaticRenewal =
      try container.decodeIfPresent(
        Bool.self,
        forKey: EventStoreCodingKey("allowsAutomaticRenewal")
      ) ?? false
    guard !allowsAutomaticRenewal || enabled else {
      throw AgentEventSubscriptionError.storageFailure
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: EventStoreCodingKey.self)
    try container.encode(
      generationID.uuidString.lowercased(),
      forKey: EventStoreCodingKey("generationID")
    )
    try container.encode(binding, forKey: EventStoreCodingKey("binding"))
    try container.encode(enabled, forKey: EventStoreCodingKey("enabled"))
    try container.encode(
      allowsAutomaticRenewal,
      forKey: EventStoreCodingKey("allowsAutomaticRenewal")
    )
  }
}

struct AgentEventPendingSubscription: Codable, Equatable, Sendable {
  let subscriptionID: String
  let profileID: UUID
  let event: AgentEventName
  let scope: AgentEventScope
  let callbackURL: String
  let signingKeyReference: String
  let grantRevision: UInt64
  let createdAt: Date
  let updatedAt: Date
  let expiresAt: Date
  let revision: UInt64
  let status: AgentEventPendingStatus
  let deliveryControl: AgentEventDeliveryControl?
  let previousSigningKey: AgentEventPreviousSigningKey?

  private enum CodingKeys: String, CodingKey {
    case subscriptionID
    case profileID
    case event
    case scope
    case callbackURL
    case signingKeyReference
    case grantRevision
    case createdAt
    case updatedAt
    case expiresAt
    case revision
    case status
    case deliveryControl
    case previousSigningKey
  }

  init(
    subscriptionID: String,
    profileID: UUID,
    event: AgentEventName,
    scope: AgentEventScope,
    callbackURL: String,
    signingKeyReference: String,
    grantRevision: UInt64,
    createdAt: Date,
    updatedAt: Date,
    expiresAt: Date,
    revision: UInt64,
    status: AgentEventPendingStatus = .pending,
    deliveryControl: AgentEventDeliveryControl? = nil,
    previousSigningKey: AgentEventPreviousSigningKey? = nil
  ) {
    self.subscriptionID = subscriptionID
    self.profileID = profileID
    self.event = event
    self.scope = scope
    self.callbackURL = callbackURL
    self.signingKeyReference = signingKeyReference
    self.grantRevision = grantRevision
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.expiresAt = expiresAt
    self.revision = revision
    self.status = status
    self.deliveryControl = deliveryControl
    self.previousSigningKey = previousSigningKey
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: EventStoreCodingKey.self)
    let expectedKeys: Set<String> = [
      "subscriptionID",
      "profileID",
      "event",
      "scope",
      "callbackURL",
      "signingKeyReference",
      "grantRevision",
      "createdAt",
      "updatedAt",
      "expiresAt",
      "revision",
      "status",
    ]
    let actualKeys = Set(container.allKeys.map(\.stringValue))
    let supportedKeys: Set<Set<String>> = [
      expectedKeys,
      expectedKeys.union(["deliveryControl"]),
      expectedKeys.union(["previousSigningKey"]),
      expectedKeys.union(["deliveryControl", "previousSigningKey"]),
    ]
    guard supportedKeys.contains(actualKeys) else {
      throw AgentEventSubscriptionError.storageFailure
    }
    subscriptionID = try container.decode(
      String.self, forKey: EventStoreCodingKey("subscriptionID"))
    profileID = try container.decode(UUID.self, forKey: EventStoreCodingKey("profileID"))
    event = try container.decode(AgentEventName.self, forKey: EventStoreCodingKey("event"))
    scope = try container.decode(AgentEventScope.self, forKey: EventStoreCodingKey("scope"))
    callbackURL = try container.decode(String.self, forKey: EventStoreCodingKey("callbackURL"))
    signingKeyReference = try container.decode(
      String.self,
      forKey: EventStoreCodingKey("signingKeyReference")
    )
    grantRevision = try container.decode(UInt64.self, forKey: EventStoreCodingKey("grantRevision"))
    createdAt = try container.decode(Date.self, forKey: EventStoreCodingKey("createdAt"))
    updatedAt = try container.decode(Date.self, forKey: EventStoreCodingKey("updatedAt"))
    expiresAt = try container.decode(Date.self, forKey: EventStoreCodingKey("expiresAt"))
    revision = try container.decode(UInt64.self, forKey: EventStoreCodingKey("revision"))
    status = try container.decode(
      AgentEventPendingStatus.self,
      forKey: EventStoreCodingKey("status")
    )
    deliveryControl = try container.decodeIfPresent(
      AgentEventDeliveryControl.self,
      forKey: EventStoreCodingKey("deliveryControl")
    )
    previousSigningKey = try container.decodeIfPresent(
      AgentEventPreviousSigningKey.self,
      forKey: EventStoreCodingKey("previousSigningKey")
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(subscriptionID, forKey: .subscriptionID)
    try container.encode(profileID, forKey: .profileID)
    try container.encode(event, forKey: .event)
    try container.encode(scope, forKey: .scope)
    try container.encode(callbackURL, forKey: .callbackURL)
    try container.encode(signingKeyReference, forKey: .signingKeyReference)
    try container.encode(grantRevision, forKey: .grantRevision)
    try container.encode(createdAt, forKey: .createdAt)
    try container.encode(updatedAt, forKey: .updatedAt)
    try container.encode(expiresAt, forKey: .expiresAt)
    try container.encode(revision, forKey: .revision)
    try container.encode(status, forKey: .status)
    try container.encodeIfPresent(deliveryControl, forKey: .deliveryControl)
    try container.encodeIfPresent(previousSigningKey, forKey: .previousSigningKey)
  }

  func replacingDeliveryControl(_ deliveryControl: AgentEventDeliveryControl?)
    -> AgentEventPendingSubscription
  {
    AgentEventPendingSubscription(
      subscriptionID: subscriptionID,
      profileID: profileID,
      event: event,
      scope: scope,
      callbackURL: callbackURL,
      signingKeyReference: signingKeyReference,
      grantRevision: grantRevision,
      createdAt: createdAt,
      updatedAt: updatedAt,
      expiresAt: expiresAt,
      revision: revision,
      status: status,
      deliveryControl: deliveryControl,
      previousSigningKey: previousSigningKey
    )
  }

  func replacingPreviousSigningKey(_ previousSigningKey: AgentEventPreviousSigningKey?)
    -> AgentEventPendingSubscription
  {
    AgentEventPendingSubscription(
      subscriptionID: subscriptionID,
      profileID: profileID,
      event: event,
      scope: scope,
      callbackURL: callbackURL,
      signingKeyReference: signingKeyReference,
      grantRevision: grantRevision,
      createdAt: createdAt,
      updatedAt: updatedAt,
      expiresAt: expiresAt,
      revision: revision,
      status: status,
      deliveryControl: deliveryControl,
      previousSigningKey: previousSigningKey
    )
  }
}

struct AgentEventSubscriptionMutation: Sendable {
  let stored: AgentEventPendingSubscription
  let previous: AgentEventPendingSubscription?
}

actor AgentEventSubscriptionStore {
  private struct State: Sendable {
    var subscriptions: [String: AgentEventPendingSubscription]
    var pendingSigningKeyDeletions: Set<String>
    var stagedSigningKeyReferences: Set<String>
    var lastObservedAt: Date
  }

  private struct Document: Codable {
    let schemaVersion: Int
    let subscriptions: [AgentEventPendingSubscription]
    let pendingSigningKeyDeletions: [String]
    let stagedSigningKeyReferences: [String]
    let lastObservedAt: Date

    init(state: State) {
      schemaVersion = 5
      subscriptions = state.subscriptions.values.sorted {
        $0.subscriptionID < $1.subscriptionID
      }
      pendingSigningKeyDeletions = state.pendingSigningKeyDeletions.sorted()
      stagedSigningKeyReferences = state.stagedSigningKeyReferences.sorted()
      lastObservedAt = state.lastObservedAt
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: EventStoreCodingKey.self)
      schemaVersion = try container.decode(Int.self, forKey: EventStoreCodingKey("schemaVersion"))
      let decodedSubscriptions = try container.decode(
        [VersionedSubscription].self,
        forKey: EventStoreCodingKey("subscriptions")
      )
      subscriptions = decodedSubscriptions.map(\.subscription)
      let keys = Set(container.allKeys.map(\.stringValue))
      switch schemaVersion {
      case 1 where keys == ["schemaVersion", "subscriptions"]:
        guard decodedSubscriptions.allSatisfy({
          !$0.hasDeliveryControl && !$0.hasPreviousSigningKey
        }) else {
          throw AgentEventSubscriptionError.storageFailure
        }
        pendingSigningKeyDeletions = []
        stagedSigningKeyReferences = []
        lastObservedAt = Self.migrationWatermark(decodedSubscriptions)
      case 2 where keys == ["schemaVersion", "subscriptions", "pendingSigningKeyDeletions"]:
        guard decodedSubscriptions.allSatisfy({
          !$0.hasDeliveryControl && !$0.hasPreviousSigningKey
        }) else {
          throw AgentEventSubscriptionError.storageFailure
        }
        pendingSigningKeyDeletions = try container.decode(
          [String].self,
          forKey: EventStoreCodingKey("pendingSigningKeyDeletions")
        )
        stagedSigningKeyReferences = []
        lastObservedAt = Self.migrationWatermark(decodedSubscriptions)
      case 3
      where keys == [
        "schemaVersion",
        "subscriptions",
        "pendingSigningKeyDeletions",
        "stagedSigningKeyReferences",
      ]:
        guard decodedSubscriptions.allSatisfy({
          !$0.hasDeliveryControl && !$0.hasPreviousSigningKey
        }) else {
          throw AgentEventSubscriptionError.storageFailure
        }
        pendingSigningKeyDeletions = try container.decode(
          [String].self,
          forKey: EventStoreCodingKey("pendingSigningKeyDeletions")
        )
        stagedSigningKeyReferences = try container.decode(
          [String].self,
          forKey: EventStoreCodingKey("stagedSigningKeyReferences")
        )
        lastObservedAt = Self.migrationWatermark(decodedSubscriptions)
      case 4
      where keys == [
        "schemaVersion",
        "subscriptions",
        "pendingSigningKeyDeletions",
        "stagedSigningKeyReferences",
      ]:
        guard decodedSubscriptions.allSatisfy({
          !$0.hasNullDeliveryControl && !$0.hasPreviousSigningKey
        }) else {
          throw AgentEventSubscriptionError.storageFailure
        }
        pendingSigningKeyDeletions = try container.decode(
          [String].self,
          forKey: EventStoreCodingKey("pendingSigningKeyDeletions")
        )
        stagedSigningKeyReferences = try container.decode(
          [String].self,
          forKey: EventStoreCodingKey("stagedSigningKeyReferences")
        )
        lastObservedAt = Self.migrationWatermark(decodedSubscriptions)
      case 5
      where keys == [
        "schemaVersion",
        "subscriptions",
        "pendingSigningKeyDeletions",
        "stagedSigningKeyReferences",
        "lastObservedAt",
      ]:
        guard decodedSubscriptions.allSatisfy({
          !$0.hasNullDeliveryControl && !$0.hasNullPreviousSigningKey
        }) else {
          throw AgentEventSubscriptionError.storageFailure
        }
        pendingSigningKeyDeletions = try container.decode(
          [String].self,
          forKey: EventStoreCodingKey("pendingSigningKeyDeletions")
        )
        stagedSigningKeyReferences = try container.decode(
          [String].self,
          forKey: EventStoreCodingKey("stagedSigningKeyReferences")
        )
        lastObservedAt = try container.decode(Date.self, forKey: EventStoreCodingKey("lastObservedAt"))
      default:
        throw AgentEventSubscriptionError.storageFailure
      }
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: EventStoreCodingKey.self)
      try container.encode(schemaVersion, forKey: EventStoreCodingKey("schemaVersion"))
      try container.encode(subscriptions, forKey: EventStoreCodingKey("subscriptions"))
      try container.encode(
        pendingSigningKeyDeletions,
        forKey: EventStoreCodingKey("pendingSigningKeyDeletions")
      )
      try container.encode(
        stagedSigningKeyReferences,
        forKey: EventStoreCodingKey("stagedSigningKeyReferences")
      )
      try container.encode(lastObservedAt, forKey: EventStoreCodingKey("lastObservedAt"))
    }

    private static func migrationWatermark(_ subscriptions: [VersionedSubscription]) -> Date {
      subscriptions.map(\.subscription.updatedAt).max() ?? Date(timeIntervalSince1970: 0)
    }

    private struct VersionedSubscription: Decodable {
      let subscription: AgentEventPendingSubscription
      let hasDeliveryControl: Bool
      let hasNullDeliveryControl: Bool
      let hasPreviousSigningKey: Bool
      let hasNullPreviousSigningKey: Bool

      init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: EventStoreCodingKey.self)
        let deliveryControlKey = EventStoreCodingKey("deliveryControl")
        hasDeliveryControl = container.contains(deliveryControlKey)
        if hasDeliveryControl {
          hasNullDeliveryControl = try container.decodeNil(forKey: deliveryControlKey)
        } else {
          hasNullDeliveryControl = false
        }
        let previousSigningKeyKey = EventStoreCodingKey("previousSigningKey")
        hasPreviousSigningKey = container.contains(previousSigningKeyKey)
        if hasPreviousSigningKey {
          hasNullPreviousSigningKey = try container.decodeNil(forKey: previousSigningKeyKey)
        } else {
          hasNullPreviousSigningKey = false
        }
        subscription = try AgentEventPendingSubscription(from: decoder)
      }
    }
  }

  private static let maximumFileSize = 1_048_576
  private static let maximumPerProfile = 32
  private static let maximumTotal = 128
  private static let maximumSigningKeyCleanupReferences = 512
  private static let stateLock = NSLock()

  nonisolated private let fileURL: URL
  private let fileWriter: @Sendable (Data, URL) throws -> Void

  init(
    fileURL: URL? = nil,
    fileWriter: @escaping @Sendable (Data, URL) throws -> Void = {
      try $0.write(to: $1, options: .atomic)
    }
  ) {
    self.fileURL = fileURL ?? Self.defaultFileURL()
    self.fileWriter = fileWriter
  }

  func pendingSubscriptions(
    profileID: UUID? = nil,
    now: Date = Date()
  ) throws -> [AgentEventPendingSubscription] {
    try Self.stateLock.withLock {
      let state = try loadState()
      guard Self.isValidClockDate(now), now >= state.lastObservedAt else {
        throw AgentEventSubscriptionError.invalidConfiguration
      }
      return state.subscriptions.values
        .filter { subscription in
          subscription.expiresAt > now
            && (profileID == nil || profileID == subscription.profileID)
        }
        .sorted { $0.subscriptionID < $1.subscriptionID }
    }
  }

  func allSubscriptions(profileID: UUID? = nil) throws -> [AgentEventPendingSubscription] {
    try Self.stateLock.withLock {
      try loadState().subscriptions.values
        .filter { profileID == nil || $0.profileID == profileID }
        .sorted { $0.subscriptionID < $1.subscriptionID }
    }
  }

  func observeTrustedClock(now: Date) throws -> Bool {
    try Self.stateLock.withLock {
      var state = try loadState()
      guard Self.isValidClockDate(now) else {
        throw AgentEventSubscriptionError.invalidConfiguration
      }
      if now < state.lastObservedAt {
        if Self.retireAllPreviousSigningKeys(in: &state) { try saveState(state) }
        return true
      }
      var changed = state.lastObservedAt != now
      state.lastObservedAt = now
      for (id, subscription) in state.subscriptions {
        guard let overlap = subscription.previousSigningKey, overlap.expiresAt <= now else {
          continue
        }
        state.pendingSigningKeyDeletions.insert(overlap.reference)
        state.subscriptions[id] = subscription.replacingPreviousSigningKey(nil)
        changed = true
      }
      if changed { try saveState(state) }
      return false
    }
  }

  func retirePreviousSigningKey(
    subscriptionID: String,
    expected: AgentEventPendingSubscription
  ) throws -> Bool {
    try Self.stateLock.withLock {
      var state = try loadState()
      guard
        state.subscriptions[subscriptionID] == expected,
        let previous = expected.previousSigningKey
      else {
        return false
      }
      state.pendingSigningKeyDeletions.insert(previous.reference)
      state.subscriptions[subscriptionID] = expected.replacingPreviousSigningKey(nil)
      try saveState(state)
      return true
    }
  }

  func pruneExpired(now: Date = Date()) throws -> [AgentEventPendingSubscription] {
    try Self.stateLock.withLock {
      var state = try loadState()
      guard Self.isValidClockDate(now) else {
        throw AgentEventSubscriptionError.invalidConfiguration
      }
      guard now >= state.lastObservedAt else {
        if Self.retireAllPreviousSigningKeys(in: &state) { try saveState(state) }
        throw AgentEventSubscriptionError.invalidConfiguration
      }
      var changed = state.lastObservedAt != now
      state.lastObservedAt = now
      for (id, subscription) in state.subscriptions {
        guard let overlap = subscription.previousSigningKey, overlap.expiresAt <= now else {
          continue
        }
        state.pendingSigningKeyDeletions.insert(overlap.reference)
        state.subscriptions[id] = subscription.replacingPreviousSigningKey(nil)
        changed = true
      }
      let expired = state.subscriptions.values.filter { $0.expiresAt <= now }
      guard !expired.isEmpty else {
        if changed { try saveState(state) }
        return []
      }
      let referencesToDelete = Set(expired.flatMap(Self.signingKeyReferences))
      let pendingReferences = state.pendingSigningKeyDeletions.union(referencesToDelete)
      guard
        pendingReferences.count + state.stagedSigningKeyReferences.count
          <= Self.maximumSigningKeyCleanupReferences
      else {
        throw AgentEventSubscriptionError.capacityExceeded
      }
      for subscription in expired {
        state.subscriptions.removeValue(forKey: subscription.subscriptionID)
      }
      state.pendingSigningKeyDeletions = pendingReferences
      try saveState(state)
      return expired.sorted { $0.subscriptionID < $1.subscriptionID }
    }
  }

  func createOrRefresh(
    _ candidate: AgentEventPendingSubscription,
    now: Date
  ) throws -> AgentEventSubscriptionMutation {
    let previous = try currentSubscription(id: candidate.subscriptionID)
    let disposition: AgentEventSigningKeyDisposition =
      previous?.signingKeyReference == candidate.signingKeyReference
      ? .preserveCurrent
      : .rotateToStagedKey
    let nextPreviousKey: AgentEventPreviousSigningKey?
    if let previous, disposition == .rotateToStagedKey,
      previous.grantRevision == candidate.grantRevision,
      previous.expiresAt > now
    {
      if let overlap = previous.previousSigningKey, overlap.expiresAt > now {
        throw Self.rotationInProgressError(overlap: overlap, now: now)
      }
      nextPreviousKey = AgentEventPreviousSigningKey(
        reference: previous.signingKeyReference,
        startedAt: now,
        expiresAt: min(
          now.addingTimeInterval(AgentEventPreviousSigningKey.maximumLifetime),
          candidate.expiresAt
        )
      )
    } else {
      nextPreviousKey = nil
    }
    return try createOrRefresh(
      candidate.replacingPreviousSigningKey(nextPreviousKey),
      expectedPrevious: previous,
      keyDisposition: disposition,
      now: now
    )
  }

  func createOrRefresh(
    _ candidate: AgentEventPendingSubscription,
    expectedPrevious: AgentEventPendingSubscription?,
    keyDisposition: AgentEventSigningKeyDisposition,
    now: Date
  ) throws -> AgentEventSubscriptionMutation {
    try createOrRefresh(
      candidate,
      expectedPrevious: expectedPrevious,
      keyDisposition: keyDisposition,
      now: now,
      acceptanceTTL: nil,
      acceptanceClock: { now }
    )
  }

  func createOrRefresh(
    _ candidate: AgentEventPendingSubscription,
    expectedPrevious: AgentEventPendingSubscription?,
    keyDisposition: AgentEventSigningKeyDisposition,
    now: Date,
    acceptedTTL: TimeInterval,
    acceptanceClock: @escaping @Sendable () -> Date
  ) throws -> AgentEventSubscriptionMutation {
    try createOrRefresh(
      candidate,
      expectedPrevious: expectedPrevious,
      keyDisposition: keyDisposition,
      now: now,
      acceptanceTTL: acceptedTTL,
      acceptanceClock: acceptanceClock
    )
  }

  private func createOrRefresh(
    _ candidate: AgentEventPendingSubscription,
    expectedPrevious: AgentEventPendingSubscription?,
    keyDisposition: AgentEventSigningKeyDisposition,
    now: Date,
    acceptanceTTL: TimeInterval?,
    acceptanceClock: @escaping @Sendable () -> Date
  ) throws -> AgentEventSubscriptionMutation {
    try Self.stateLock.withLock {
      var state = try loadState()
      let storedPrevious = state.subscriptions[candidate.subscriptionID]
      guard storedPrevious == expectedPrevious else {
        throw AgentWorkspaceError(code: .capabilityDenied)
      }

      let mutationTime: Date
      let previous: AgentEventPendingSubscription?
      let mutationCandidate: AgentEventPendingSubscription
      let expiredPreviousKeyReference: String?
      if let acceptanceTTL {
        let acceptedAt = acceptanceClock()
        guard Self.isValidClockDate(acceptedAt) else {
          throw AgentEventSubscriptionError.invalidConfiguration
        }
        if acceptedAt < state.lastObservedAt || acceptedAt < now {
          if Self.retireAllPreviousSigningKeys(in: &state) { try saveState(state) }
          throw AgentEventSubscriptionError.invalidConfiguration
        }
        guard
          (60.0...604_800.0).contains(acceptanceTTL),
          acceptedAt >= candidate.updatedAt
        else {
          throw AgentEventSubscriptionError.invalidConfiguration
        }
        let acceptedExpiresAt = acceptedAt.addingTimeInterval(acceptanceTTL)
        guard acceptedExpiresAt.timeIntervalSince1970.isFinite else {
          throw AgentEventSubscriptionError.invalidConfiguration
        }

        if let overlap = storedPrevious?.previousSigningKey,
          overlap.expiresAt <= acceptedAt
        {
          previous = storedPrevious?.replacingPreviousSigningKey(nil)
          expiredPreviousKeyReference = overlap.reference
        } else {
          previous = storedPrevious
          expiredPreviousKeyReference = nil
        }
        mutationTime = acceptedAt

        let nextPreviousKey: AgentEventPreviousSigningKey?
        switch keyDisposition {
        case .preserveCurrent:
          nextPreviousKey = previous?.previousSigningKey
        case .rotateToStagedKey:
          if let previous, previous.grantRevision == candidate.grantRevision,
            previous.expiresAt > acceptedAt
          {
            if let overlap = previous.previousSigningKey, overlap.expiresAt > acceptedAt {
              throw Self.rotationInProgressError(overlap: overlap, now: acceptedAt)
            }
            nextPreviousKey = AgentEventPreviousSigningKey(
              reference: previous.signingKeyReference,
              startedAt: acceptedAt,
              expiresAt: min(
                acceptedAt.addingTimeInterval(AgentEventPreviousSigningKey.maximumLifetime),
                acceptedExpiresAt
              )
            )
          } else {
            nextPreviousKey = nil
          }
        }
        mutationCandidate = AgentEventPendingSubscription(
          subscriptionID: candidate.subscriptionID,
          profileID: candidate.profileID,
          event: candidate.event,
          scope: candidate.scope,
          callbackURL: candidate.callbackURL,
          signingKeyReference: candidate.signingKeyReference,
          grantRevision: candidate.grantRevision,
          createdAt: candidate.createdAt,
          updatedAt: acceptedAt,
          expiresAt: acceptedExpiresAt,
          revision: candidate.revision,
          status: candidate.status,
          deliveryControl: candidate.deliveryControl,
          previousSigningKey: nextPreviousKey
        )
      } else {
        guard Self.isValidClockDate(now), now >= state.lastObservedAt else {
          throw AgentEventSubscriptionError.invalidConfiguration
        }
        mutationTime = now
        previous = storedPrevious
        mutationCandidate = candidate
        expiredPreviousKeyReference = nil
      }

      if let previous, previous.profileID != mutationCandidate.profileID {
        throw AgentWorkspaceError(code: .capabilityDenied)
      }
      if let previous,
        previous.event != mutationCandidate.event || previous.scope != mutationCandidate.scope
          || previous.callbackURL != mutationCandidate.callbackURL
      {
        throw AgentWorkspaceError(code: .capabilityDenied)
      }
      guard previous.map({ mutationCandidate.updatedAt >= $0.updatedAt }) ?? true else {
        throw AgentEventSubscriptionError.invalidConfiguration
      }
      guard Self.isValid(mutationCandidate, requireIdentity: true) else {
        throw AgentEventSubscriptionError.invalidConfiguration
      }
      guard
        !state.pendingSigningKeyDeletions.contains(mutationCandidate.signingKeyReference),
        Self.isValidSigningKeyReference(mutationCandidate.signingKeyReference),
        state.subscriptions.values.filter({ $0.subscriptionID != mutationCandidate.subscriptionID })
          .flatMap(Self.signingKeyReferences).allSatisfy({
            $0 != mutationCandidate.signingKeyReference
              && $0 != mutationCandidate.previousSigningKey?.reference
          })
      else {
        throw AgentEventSubscriptionError.invalidConfiguration
      }
      switch keyDisposition {
      case .preserveCurrent:
        guard
          let previous,
          previous.signingKeyReference == mutationCandidate.signingKeyReference,
          !state.stagedSigningKeyReferences.contains(mutationCandidate.signingKeyReference),
          mutationCandidate.previousSigningKey == previous.previousSigningKey
        else {
          throw AgentEventSubscriptionError.invalidConfiguration
        }
      case .rotateToStagedKey:
        guard
          state.stagedSigningKeyReferences.contains(mutationCandidate.signingKeyReference),
          previous?.signingKeyReference != mutationCandidate.signingKeyReference
        else {
          throw AgentEventSubscriptionError.invalidConfiguration
        }
        if let previous, previous.grantRevision == mutationCandidate.grantRevision,
          previous.expiresAt > mutationTime
        {
          guard previous.previousSigningKey.map({ $0.expiresAt <= mutationTime }) ?? true,
            let overlap = mutationCandidate.previousSigningKey,
            overlap.reference == previous.signingKeyReference,
            overlap.startedAt == mutationTime,
            overlap.expiresAt == min(
              mutationTime.addingTimeInterval(AgentEventPreviousSigningKey.maximumLifetime),
              mutationCandidate.expiresAt
            )
          else {
            throw AgentEventSubscriptionError.invalidConfiguration
          }
        } else {
          guard mutationCandidate.previousSigningKey == nil else {
            throw AgentEventSubscriptionError.invalidConfiguration
          }
        }
      }
      let totalCount = state.subscriptions.count - (storedPrevious == nil ? 0 : 1)
      let profileCount = state.subscriptions.values.filter {
        $0.profileID == mutationCandidate.profileID
          && $0.subscriptionID != mutationCandidate.subscriptionID
      }.count
      guard
        totalCount < Self.maximumTotal,
        profileCount < Self.maximumPerProfile
      else {
        throw AgentEventSubscriptionError.capacityExceeded
      }
      guard previous?.revision != UInt64.max else {
        throw AgentEventSubscriptionError.storageFailure
      }
      let stored = AgentEventPendingSubscription(
        subscriptionID: mutationCandidate.subscriptionID,
        profileID: mutationCandidate.profileID,
        event: mutationCandidate.event,
        scope: mutationCandidate.scope,
        callbackURL: mutationCandidate.callbackURL,
        signingKeyReference: mutationCandidate.signingKeyReference,
        grantRevision: mutationCandidate.grantRevision,
        createdAt: previous?.createdAt ?? mutationTime,
        updatedAt: mutationCandidate.updatedAt,
        expiresAt: mutationCandidate.expiresAt,
        revision: (previous?.revision ?? 0) + 1,
        deliveryControl: Self.controlForRefresh(
          previous: previous,
          candidate: mutationCandidate,
          subscriptionRevision: (previous?.revision ?? 0) + 1,
          now: mutationTime
        ),
        previousSigningKey: mutationCandidate.previousSigningKey
      )
      guard Self.isValid(stored, requireIdentity: true) else {
        throw AgentEventSubscriptionError.invalidConfiguration
      }
      if let previous {
        let removedReferences = Set(Self.signingKeyReferences(previous))
          .subtracting(Self.signingKeyReferences(stored))
        state.pendingSigningKeyDeletions.formUnion(removedReferences)
      }
      if let expiredPreviousKeyReference {
        state.pendingSigningKeyDeletions.insert(expiredPreviousKeyReference)
      }
      state.stagedSigningKeyReferences.remove(mutationCandidate.signingKeyReference)
      state.subscriptions[stored.subscriptionID] = stored
      state.lastObservedAt = max(state.lastObservedAt, mutationTime)
      try saveState(state)
      return AgentEventSubscriptionMutation(stored: stored, previous: previous)
    }
  }

  func rollback(_ mutation: AgentEventSubscriptionMutation) throws -> Bool {
    try Self.stateLock.withLock {
      var state = try loadState()
      guard let current = state.subscriptions[mutation.stored.subscriptionID],
        current == mutation.stored
      else {
        return false
      }
      let currentReferences = Set(Self.signingKeyReferences(current))
      if let previous = mutation.previous {
        let restored = previous.replacingDeliveryControl(Self.offControl(for: previous))
        let restoredReferences = Set(Self.signingKeyReferences(restored))
        state.pendingSigningKeyDeletions.subtract(restoredReferences)
        state.pendingSigningKeyDeletions.formUnion(currentReferences.subtracting(restoredReferences))
        state.subscriptions[restored.subscriptionID] = restored
      } else {
        state.pendingSigningKeyDeletions.formUnion(currentReferences)
        state.subscriptions.removeValue(forKey: current.subscriptionID)
      }
      try saveState(state)
      return true
    }
  }

  func currentSubscription(
    id: String
  ) throws -> AgentEventPendingSubscription? {
    try Self.stateLock.withLock {
      try loadState().subscriptions[id]
    }
  }

  nonisolated func isCurrentSubscription(
    expected: AgentEventPendingSubscription
  ) -> Bool {
    do {
      return try Self.stateLock.withLock {
        try loadState().subscriptions[expected.subscriptionID] == expected
      }
    } catch {
      return false
    }
  }

  nonisolated func isCurrentOwnerDeliveryControl(
    binding: AgentEventCallbackVerificationBinding,
    generationID: UUID
  ) -> Bool {
    do {
      return try Self.stateLock.withLock {
        guard
          let subscription = try loadState().subscriptions[binding.subscriptionID],
          Self.binding(for: subscription) == binding,
          let control = subscription.deliveryControl
        else {
          return false
        }
        return control.binding == binding
          && control.generationID == generationID
          && control.enabled
      }
    } catch {
      return false
    }
  }

  nonisolated func isCurrentOwnerDeliveryControl(
    binding: AgentEventCallbackVerificationBinding,
    control: AgentEventDeliveryControl
  ) -> Bool {
    do {
      return try Self.stateLock.withLock {
        guard
          let subscription = try loadState().subscriptions[binding.subscriptionID],
          Self.binding(for: subscription) == binding
        else {
          return false
        }
        return control.binding == binding && subscription.deliveryControl == control
      }
    } catch {
      return false
    }
  }

  func setOwnerDeliveryEligibility(
    binding: AgentEventCallbackVerificationBinding,
    expectedGenerationID: UUID?,
    eligible: Bool,
    allowsAutomaticRenewal: Bool = false,
    prospectiveGenerationID: UUID? = nil
  ) throws -> AgentEventDeliveryControl? {
    try Self.stateLock.withLock {
      var state = try loadState()
      guard
        let current = state.subscriptions[binding.subscriptionID],
        Self.binding(for: current) == binding,
        current.deliveryControl?.generationID == expectedGenerationID,
        current.deliveryControl.map({ $0.binding == binding }) ?? true
      else {
        return nil
      }
      let generationID = prospectiveGenerationID ?? UUID()
      guard expectedGenerationID != generationID else { return nil }
      if prospectiveGenerationID != nil,
        state.subscriptions.values.contains(where: {
          $0.deliveryControl?.generationID == generationID
        })
      {
        return nil
      }
      let control = AgentEventDeliveryControl(
        generationID: generationID,
        binding: binding,
        enabled: eligible,
        allowsAutomaticRenewal: eligible && allowsAutomaticRenewal
      )
      state.subscriptions[current.subscriptionID] = current.replacingDeliveryControl(control)
      try saveState(state)
      guard
        let persisted = try loadState().subscriptions[current.subscriptionID],
        Self.binding(for: persisted) == binding,
        persisted.deliveryControl == control
      else {
        throw AgentEventSubscriptionError.storageFailure
      }
      return control
    }
  }

  func isSigningKeyReferenced(_ reference: String) throws -> Bool {
    try Self.stateLock.withLock {
      try loadState().subscriptions.values.contains {
        Self.signingKeyReferences($0).contains(reference)
      }
    }
  }

  func pendingSigningKeyDeletions() throws -> [String] {
    try Self.stateLock.withLock {
      try loadState().pendingSigningKeyDeletions.sorted()
    }
  }

  func pendingSigningKeyCleanupReferences() throws -> [String] {
    try Self.stateLock.withLock {
      let state = try loadState()
      return state.pendingSigningKeyDeletions
        .union(state.stagedSigningKeyReferences)
        .sorted()
    }
  }

  func stagedSigningKeyReferences() throws -> [String] {
    try Self.stateLock.withLock {
      try loadState().stagedSigningKeyReferences.sorted()
    }
  }

  func reserveSigningKeyReference(_ reference: String) throws {
    try Self.stateLock.withLock {
      var state = try loadState()
      guard Self.isValidSigningKeyReference(reference) else {
        throw AgentEventSubscriptionError.storageFailure
      }
      guard
        !state.pendingSigningKeyDeletions.contains(reference),
        !state.stagedSigningKeyReferences.contains(reference),
        !state.subscriptions.values.contains(where: {
          Self.signingKeyReferences($0).contains(reference)
        }),
        Self.referenceCount(in: state) < Self.maximumSigningKeyCleanupReferences
      else {
        if Self.referenceCount(in: state) >= Self.maximumSigningKeyCleanupReferences
        {
          throw AgentEventSubscriptionError.capacityExceeded
        }
        throw AgentEventSubscriptionError.invalidConfiguration
      }
      state.stagedSigningKeyReferences.insert(reference)
      try saveState(state)
    }
  }

  func retainSigningKeyForDeletion(reference: String) throws {
    try Self.stateLock.withLock {
      var state = try loadState()
      guard Self.isValidSigningKeyReference(reference) else {
        throw AgentEventSubscriptionError.storageFailure
      }
      guard
        !state.subscriptions.values.contains(where: {
          Self.signingKeyReferences($0).contains(reference)
        })
      else {
        throw AgentEventSubscriptionError.storageFailure
      }
      if state.stagedSigningKeyReferences.remove(reference) != nil {
        state.pendingSigningKeyDeletions.insert(reference)
        try saveState(state)
        return
      }
      guard !state.pendingSigningKeyDeletions.contains(reference) else { return }
      guard
        Self.referenceCount(in: state) < Self.maximumSigningKeyCleanupReferences
      else {
        throw AgentEventSubscriptionError.capacityExceeded
      }
      state.pendingSigningKeyDeletions.insert(reference)
      try saveState(state)
    }
  }

  func acknowledgeSigningKeyDeletion(reference: String) throws {
    try Self.stateLock.withLock {
      var state = try loadState()
      guard Self.isValidSigningKeyReference(reference) else {
        throw AgentEventSubscriptionError.storageFailure
      }
      guard !state.subscriptions.values.contains(where: {
        Self.signingKeyReferences($0).contains(reference)
      })
      else {
        throw AgentEventSubscriptionError.storageFailure
      }
      guard
        state.pendingSigningKeyDeletions.remove(reference) != nil
          || state.stagedSigningKeyReferences.remove(reference) != nil
      else {
        return
      }
      try saveState(state)
    }
  }

  func remove(
    subscriptionID: String,
    profileID: UUID
  ) throws -> AgentEventPendingSubscription? {
    try Self.stateLock.withLock {
      var state = try loadState()
      guard let subscription = state.subscriptions[subscriptionID] else { return nil }
      guard subscription.profileID == profileID else { return nil }
      guard
        Self.referenceCount(in: state) <= Self.maximumSigningKeyCleanupReferences
      else {
        throw AgentEventSubscriptionError.capacityExceeded
      }
      state.subscriptions.removeValue(forKey: subscriptionID)
      state.pendingSigningKeyDeletions.formUnion(Self.signingKeyReferences(subscription))
      try saveState(state)
      return subscription
    }
  }

  nonisolated private func loadState() throws -> State {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return State(
        subscriptions: [:],
        pendingSigningKeyDeletions: [],
        stagedSigningKeyReferences: [],
        lastObservedAt: Date(timeIntervalSince1970: 0)
      )
    }
    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
      guard
        let fileSize = attributes[.size] as? NSNumber,
        fileSize.intValue <= Self.maximumFileSize
      else {
        throw AgentEventSubscriptionError.storageFailure
      }
      let data = try Data(contentsOf: fileURL)
      guard data.count <= Self.maximumFileSize else {
        throw AgentEventSubscriptionError.storageFailure
      }
      let document = try JSONDecoder().decode(Document.self, from: data)
      let ids = document.subscriptions.map(\.subscriptionID)
      let pendingReferences = document.pendingSigningKeyDeletions
      let stagedReferences = document.stagedSigningKeyReferences
      let subscriptionReferences = document.subscriptions.flatMap(Self.signingKeyReferences)
      guard
        Set(ids).count == ids.count,
        ids.count <= Self.maximumTotal,
        Set(pendingReferences).count == pendingReferences.count,
        Set(stagedReferences).count == stagedReferences.count,
        pendingReferences.count + stagedReferences.count + subscriptionReferences.count
          <= Self.maximumSigningKeyCleanupReferences
      else {
        throw AgentEventSubscriptionError.storageFailure
      }
      let state = State(
        subscriptions: Dictionary(
          uniqueKeysWithValues: document.subscriptions.map { ($0.subscriptionID, $0) }
        ),
        pendingSigningKeyDeletions: Set(pendingReferences),
        stagedSigningKeyReferences: Set(stagedReferences),
        lastObservedAt: document.lastObservedAt
      )
      guard
        Self.isValidState(state)
      else {
        throw AgentEventSubscriptionError.storageFailure
      }
      return state
    } catch let error as AgentEventSubscriptionError {
      throw error
    } catch {
      throw AgentEventSubscriptionError.storageFailure
    }
  }

  private func saveState(_ state: State) throws {
    do {
      guard Self.isValidState(state) else {
        throw AgentEventSubscriptionError.storageFailure
      }
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      let data = try encoder.encode(Document(state: state))
      guard data.count <= Self.maximumFileSize else {
        throw AgentEventSubscriptionError.storageFailure
      }
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o700],
        ofItemAtPath: fileURL.deletingLastPathComponent().path
      )
      do {
        try fileWriter(data, fileURL)
      } catch {
        let persistedData: Data?
        if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
          let fileSize = attributes[.size] as? NSNumber,
          fileSize.intValue <= Self.maximumFileSize
        {
          persistedData = try? Data(contentsOf: fileURL)
        } else {
          persistedData = nil
        }
        guard persistedData == data else {
          throw AgentEventSubscriptionError.storageFailure
        }
      }
    } catch let error as AgentEventSubscriptionError {
      throw error
    } catch {
      throw AgentEventSubscriptionError.storageFailure
    }
  }

  private static func isValid(
    _ subscription: AgentEventPendingSubscription,
    requireIdentity: Bool
  ) -> Bool {
    guard
      subscription.status == .pending,
      subscription.revision > 0,
      subscription.signingKeyReference == subscription.signingKeyReference.lowercased(),
      UUID(uuidString: subscription.signingKeyReference) != nil,
      subscription.createdAt.timeIntervalSince1970.isFinite,
      subscription.updatedAt.timeIntervalSince1970.isFinite,
      subscription.updatedAt >= subscription.createdAt,
      subscription.expiresAt.timeIntervalSince1970.isFinite,
      (60.0...604_800.0).contains(
        subscription.expiresAt.timeIntervalSince(subscription.updatedAt)
      ),
      let canonicalURL = try? AgentEventSubscriptionIdentity.canonicalCallbackURL(
        subscription.callbackURL
      ),
      canonicalURL == subscription.callbackURL
    else {
      return false
    }
    if let previousSigningKey = subscription.previousSigningKey {
      guard
        previousSigningKey.reference != subscription.signingKeyReference,
        isValidSigningKeyReference(previousSigningKey.reference),
        previousSigningKey.startedAt.timeIntervalSince1970.isFinite,
        previousSigningKey.expiresAt.timeIntervalSince1970.isFinite,
        subscription.createdAt <= previousSigningKey.startedAt,
        previousSigningKey.startedAt <= subscription.updatedAt,
        subscription.updatedAt < previousSigningKey.expiresAt,
        previousSigningKey.startedAt < previousSigningKey.expiresAt,
        previousSigningKey.expiresAt <= subscription.expiresAt,
        previousSigningKey.expiresAt.timeIntervalSince(previousSigningKey.startedAt)
          <= AgentEventPreviousSigningKey.maximumLifetime
      else {
        return false
      }
    }
    guard
      subscription.deliveryControl.map({ $0.binding == binding(for: subscription) }) ?? true
    else {
      return false
    }
    if requireIdentity {
      return subscription.subscriptionID
        == AgentEventSubscriptionIdentity.subscriptionID(
          profileID: subscription.profileID,
          event: subscription.event,
          scope: subscription.scope,
          callbackURL: subscription.callbackURL
        )
    }
    return true
  }

  private static func isValidState(_ state: State) -> Bool {
    let subscriptions = Array(state.subscriptions.values)
    let liveReferences = subscriptions.flatMap(Self.signingKeyReferences)
    let allReferences = liveReferences
      + Array(state.pendingSigningKeyDeletions)
      + Array(state.stagedSigningKeyReferences)
    return subscriptions.count <= Self.maximumTotal
      && Dictionary(grouping: subscriptions, by: \.profileID).values.allSatisfy({
        $0.count <= Self.maximumPerProfile
      })
      && subscriptions.allSatisfy({ Self.isValid($0, requireIdentity: true) })
      && isValidClockDate(state.lastObservedAt)
      && Set(allReferences).count == allReferences.count
      && allReferences.count <= Self.maximumSigningKeyCleanupReferences
      && state.pendingSigningKeyDeletions.allSatisfy(Self.isValidSigningKeyReference)
      && state.stagedSigningKeyReferences.allSatisfy(Self.isValidSigningKeyReference)
  }

  private static func signingKeyReferences(
    _ subscription: AgentEventPendingSubscription
  ) -> [String] {
    [subscription.signingKeyReference] + (subscription.previousSigningKey.map { [$0.reference] } ?? [])
  }

  private static func referenceCount(in state: State) -> Int {
    state.subscriptions.values.flatMap(Self.signingKeyReferences).count
      + state.pendingSigningKeyDeletions.count
      + state.stagedSigningKeyReferences.count
  }

  private static func isValidClockDate(_ date: Date) -> Bool {
    date.timeIntervalSince1970.isFinite && date.timeIntervalSince1970 >= 0
  }

  private static func rotationInProgressError(
    overlap: AgentEventPreviousSigningKey,
    now: Date
  ) -> AgentWorkspaceError {
    let remaining = overlap.expiresAt.timeIntervalSince(now)
    let retryAfterMs = max(
      1,
      Int((min(remaining, AgentEventPreviousSigningKey.maximumLifetime) * 1_000).rounded(.up))
    )
    return AgentWorkspaceError.signingKeyRotationInProgress(retryAfterMs: retryAfterMs)
  }

  private static func retireAllPreviousSigningKeys(in state: inout State) -> Bool {
    var changed = false
    for (id, subscription) in state.subscriptions {
      guard let overlap = subscription.previousSigningKey else { continue }
      state.pendingSigningKeyDeletions.insert(overlap.reference)
      state.subscriptions[id] = subscription.replacingPreviousSigningKey(nil)
      changed = true
    }
    return changed
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

  private static func binding(
    profileID: UUID,
    subscriptionID: String,
    subscriptionRevision: UInt64,
    grantRevision: UInt64,
    signingKeyReference: String
  ) -> AgentEventCallbackVerificationBinding {
    AgentEventCallbackVerificationBinding(
      profileID: profileID,
      subscriptionID: subscriptionID,
      subscriptionRevision: subscriptionRevision,
      grantRevision: grantRevision,
      signingKeyReference: signingKeyReference
    )
  }

  private static func offControl(
    for subscription: AgentEventPendingSubscription
  ) -> AgentEventDeliveryControl {
    AgentEventDeliveryControl(
      generationID: UUID(),
      binding: binding(for: subscription),
      enabled: false
    )
  }

  private static func offControl(
    profileID: UUID,
    subscriptionID: String,
    subscriptionRevision: UInt64,
    grantRevision: UInt64,
    signingKeyReference: String
  ) -> AgentEventDeliveryControl {
    AgentEventDeliveryControl(
      generationID: UUID(),
      binding: binding(
        profileID: profileID,
        subscriptionID: subscriptionID,
        subscriptionRevision: subscriptionRevision,
        grantRevision: grantRevision,
        signingKeyReference: signingKeyReference
      ),
      enabled: false
    )
  }

  private static func controlForRefresh(
    previous: AgentEventPendingSubscription?,
    candidate: AgentEventPendingSubscription,
    subscriptionRevision: UInt64,
    now: Date
  ) -> AgentEventDeliveryControl {
    let binding = binding(
      profileID: candidate.profileID,
      subscriptionID: candidate.subscriptionID,
      subscriptionRevision: subscriptionRevision,
      grantRevision: candidate.grantRevision,
      signingKeyReference: candidate.signingKeyReference
    )
    let carriesRenewal =
      previous.map { previous in
        previous.expiresAt > now
          && previous.grantRevision == candidate.grantRevision
          && previous.deliveryControl?.binding == Self.binding(for: previous)
          && previous.deliveryControl?.enabled == true
          && previous.deliveryControl?.allowsAutomaticRenewal == true
      } ?? false
    return AgentEventDeliveryControl(
      generationID: UUID(),
      binding: binding,
      enabled: carriesRenewal,
      allowsAutomaticRenewal: carriesRenewal
    )
  }

  private static func isValidSigningKeyReference(_ reference: String) -> Bool {
    guard let uuid = UUID(uuidString: reference) else { return false }
    return uuid.uuidString.lowercased() == reference
  }

  private static func defaultFileURL() -> URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent(FleckProductPaths.canonicalDirectoryName, isDirectory: true)
      .appendingPathComponent("AgentIntegrations", isDirectory: true)
      .appendingPathComponent("AgentEvents", isDirectory: true)
      .appendingPathComponent("event-subscriptions.json")
  }
}

private struct EventStoreCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int? = nil

  init(_ value: String) {
    stringValue = value
  }

  init?(stringValue: String) {
    self.init(stringValue)
  }

  init?(intValue: Int) {
    return nil
  }
}
