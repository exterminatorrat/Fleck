import FleckCore
import Foundation

enum AgentEventCallbackVerificationStoreError: Error, Equatable, Sendable {
  case invalidBinding
  case capacityExceeded
  case verificationInProgress
  case staleIntent
  case storageFailure
}

struct AgentEventCallbackVerificationBinding: Codable, Equatable, Hashable, Sendable {
  let profileID: UUID
  let subscriptionID: String
  let subscriptionRevision: UInt64
  let grantRevision: UInt64
  let signingKeyReference: String

  init(
    profileID: UUID,
    subscriptionID: String,
    subscriptionRevision: UInt64,
    grantRevision: UInt64,
    signingKeyReference: String
  ) {
    self.profileID = profileID
    self.subscriptionID = subscriptionID
    self.subscriptionRevision = subscriptionRevision
    self.grantRevision = grantRevision
    self.signingKeyReference = signingKeyReference
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(
      keyedBy: AgentEventCallbackVerificationCodingKey.self
    )
    try requireExactKeys(
      container,
      [
        "profileID", "subscriptionID", "subscriptionRevision", "grantRevision",
        "signingKeyReference",
      ])
    profileID = try container.decode(
      UUID.self,
      forKey: AgentEventCallbackVerificationCodingKey("profileID")
    )
    subscriptionID = try container.decode(
      String.self,
      forKey: AgentEventCallbackVerificationCodingKey("subscriptionID")
    )
    subscriptionRevision = try container.decode(
      UInt64.self,
      forKey: AgentEventCallbackVerificationCodingKey("subscriptionRevision")
    )
    grantRevision = try container.decode(
      UInt64.self,
      forKey: AgentEventCallbackVerificationCodingKey("grantRevision")
    )
    signingKeyReference = try container.decode(
      String.self,
      forKey: AgentEventCallbackVerificationCodingKey("signingKeyReference")
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: AgentEventCallbackVerificationCodingKey.self)
    try container.encode(profileID, forKey: AgentEventCallbackVerificationCodingKey("profileID"))
    try container.encode(
      subscriptionID,
      forKey: AgentEventCallbackVerificationCodingKey("subscriptionID")
    )
    try container.encode(
      subscriptionRevision,
      forKey: AgentEventCallbackVerificationCodingKey("subscriptionRevision")
    )
    try container.encode(
      grantRevision,
      forKey: AgentEventCallbackVerificationCodingKey("grantRevision")
    )
    try container.encode(
      signingKeyReference,
      forKey: AgentEventCallbackVerificationCodingKey("signingKeyReference")
    )
  }
}

struct AgentEventCallbackVerificationIntent: Codable, Equatable, Sendable {
  let id: UUID
  let binding: AgentEventCallbackVerificationBinding
  let nonceDigest: Data
  let createdAt: Date
  let expiresAt: Date

  init(
    id: UUID,
    binding: AgentEventCallbackVerificationBinding,
    nonceDigest: Data,
    createdAt: Date,
    expiresAt: Date
  ) {
    self.id = id
    self.binding = binding
    self.nonceDigest = nonceDigest
    self.createdAt = createdAt
    self.expiresAt = expiresAt
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(
      keyedBy: AgentEventCallbackVerificationCodingKey.self
    )
    try requireExactKeys(container, ["id", "binding", "nonceDigest", "createdAt", "expiresAt"])
    id = try container.decode(UUID.self, forKey: AgentEventCallbackVerificationCodingKey("id"))
    binding = try container.decode(
      AgentEventCallbackVerificationBinding.self,
      forKey: AgentEventCallbackVerificationCodingKey("binding")
    )
    nonceDigest = try container.decode(
      Data.self,
      forKey: AgentEventCallbackVerificationCodingKey("nonceDigest")
    )
    createdAt = try container.decode(
      Date.self,
      forKey: AgentEventCallbackVerificationCodingKey("createdAt")
    )
    expiresAt = try container.decode(
      Date.self,
      forKey: AgentEventCallbackVerificationCodingKey("expiresAt")
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: AgentEventCallbackVerificationCodingKey.self)
    try container.encode(id, forKey: AgentEventCallbackVerificationCodingKey("id"))
    try container.encode(binding, forKey: AgentEventCallbackVerificationCodingKey("binding"))
    try container.encode(
      nonceDigest, forKey: AgentEventCallbackVerificationCodingKey("nonceDigest"))
    try container.encode(createdAt, forKey: AgentEventCallbackVerificationCodingKey("createdAt"))
    try container.encode(expiresAt, forKey: AgentEventCallbackVerificationCodingKey("expiresAt"))
  }
}

struct AgentEventCallbackVerificationProof: Codable, Equatable, Sendable {
  let binding: AgentEventCallbackVerificationBinding
  let originIntentID: UUID
  let verifiedAt: Date
  let expiresAt: Date

  init(
    binding: AgentEventCallbackVerificationBinding,
    originIntentID: UUID,
    verifiedAt: Date,
    expiresAt: Date
  ) {
    self.binding = binding
    self.originIntentID = originIntentID
    self.verifiedAt = verifiedAt
    self.expiresAt = expiresAt
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(
      keyedBy: AgentEventCallbackVerificationCodingKey.self
    )
    try requireExactKeys(container, ["binding", "originIntentID", "verifiedAt", "expiresAt"])
    binding = try container.decode(
      AgentEventCallbackVerificationBinding.self,
      forKey: AgentEventCallbackVerificationCodingKey("binding")
    )
    originIntentID = try container.decode(
      UUID.self,
      forKey: AgentEventCallbackVerificationCodingKey("originIntentID")
    )
    verifiedAt = try container.decode(
      Date.self,
      forKey: AgentEventCallbackVerificationCodingKey("verifiedAt")
    )
    expiresAt = try container.decode(
      Date.self,
      forKey: AgentEventCallbackVerificationCodingKey("expiresAt")
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: AgentEventCallbackVerificationCodingKey.self)
    try container.encode(binding, forKey: AgentEventCallbackVerificationCodingKey("binding"))
    try container.encode(
      originIntentID,
      forKey: AgentEventCallbackVerificationCodingKey("originIntentID")
    )
    try container.encode(verifiedAt, forKey: AgentEventCallbackVerificationCodingKey("verifiedAt"))
    try container.encode(expiresAt, forKey: AgentEventCallbackVerificationCodingKey("expiresAt"))
  }
}

struct AgentEventEndpointVerificationCacheEntry: Codable, Equatable, Sendable {
  let id: UUID
  let profileID: UUID
  let canonicalCallbackURLDigest: String
  let grantRevision: UInt64
  let signingKeyReference: String
  let verifiedAt: Date
  let expiresAt: Date

  init(
    id: UUID,
    profileID: UUID,
    canonicalCallbackURLDigest: String,
    grantRevision: UInt64,
    signingKeyReference: String,
    verifiedAt: Date,
    expiresAt: Date
  ) {
    self.id = id
    self.profileID = profileID
    self.canonicalCallbackURLDigest = canonicalCallbackURLDigest
    self.grantRevision = grantRevision
    self.signingKeyReference = signingKeyReference
    self.verifiedAt = verifiedAt
    self.expiresAt = expiresAt
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: AgentEventCallbackVerificationCodingKey.self)
    try requireExactKeys(
      container,
      [
        "id", "profileID", "canonicalCallbackURLDigest", "grantRevision",
        "signingKeyReference", "verifiedAt", "expiresAt",
      ]
    )
    id = try container.decode(UUID.self, forKey: AgentEventCallbackVerificationCodingKey("id"))
    profileID = try container.decode(
      UUID.self,
      forKey: AgentEventCallbackVerificationCodingKey("profileID")
    )
    canonicalCallbackURLDigest = try container.decode(
      String.self,
      forKey: AgentEventCallbackVerificationCodingKey("canonicalCallbackURLDigest")
    )
    grantRevision = try container.decode(
      UInt64.self,
      forKey: AgentEventCallbackVerificationCodingKey("grantRevision")
    )
    signingKeyReference = try container.decode(
      String.self,
      forKey: AgentEventCallbackVerificationCodingKey("signingKeyReference")
    )
    verifiedAt = try container.decode(
      Date.self,
      forKey: AgentEventCallbackVerificationCodingKey("verifiedAt")
    )
    expiresAt = try container.decode(
      Date.self,
      forKey: AgentEventCallbackVerificationCodingKey("expiresAt")
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: AgentEventCallbackVerificationCodingKey.self)
    try container.encode(id, forKey: AgentEventCallbackVerificationCodingKey("id"))
    try container.encode(profileID, forKey: AgentEventCallbackVerificationCodingKey("profileID"))
    try container.encode(
      canonicalCallbackURLDigest,
      forKey: AgentEventCallbackVerificationCodingKey("canonicalCallbackURLDigest")
    )
    try container.encode(
      grantRevision,
      forKey: AgentEventCallbackVerificationCodingKey("grantRevision")
    )
    try container.encode(
      signingKeyReference,
      forKey: AgentEventCallbackVerificationCodingKey("signingKeyReference")
    )
    try container.encode(verifiedAt, forKey: AgentEventCallbackVerificationCodingKey("verifiedAt"))
    try container.encode(expiresAt, forKey: AgentEventCallbackVerificationCodingKey("expiresAt"))
  }
}

final class AgentEventCallbackVerificationStore: @unchecked Sendable {
  private struct State {
    var intents: [AgentEventCallbackVerificationIntent]
    var proofs: [AgentEventCallbackVerificationProof]
    var endpointCache: [AgentEventEndpointVerificationCacheEntry]
    var lastObservedAt: Date
  }

  private struct Document: Codable {
    let schemaVersion: Int
    let intents: [AgentEventCallbackVerificationIntent]
    let proofs: [AgentEventCallbackVerificationProof]
    let endpointCache: [AgentEventEndpointVerificationCacheEntry]
    let lastObservedAt: Date

    init(_ state: State) {
      schemaVersion = 3
      intents = state.intents.sorted { $0.id.uuidString < $1.id.uuidString }
      proofs = state.proofs.sorted { Self.bindingOrder($0.binding) < Self.bindingOrder($1.binding) }
      endpointCache = state.endpointCache.sorted {
        Self.endpointCacheOrder($0) < Self.endpointCacheOrder($1)
      }
      lastObservedAt = state.lastObservedAt
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(
        keyedBy: AgentEventCallbackVerificationCodingKey.self
      )
      schemaVersion = try container.decode(
        Int.self,
        forKey: AgentEventCallbackVerificationCodingKey("schemaVersion")
      )
      let keys = Set(container.allKeys.map(\.stringValue))
      switch schemaVersion {
      case 2 where keys == ["schemaVersion", "intents", "proofs", "lastObservedAt"]:
        endpointCache = []
      case 3 where keys == [
        "schemaVersion", "intents", "proofs", "endpointCache", "lastObservedAt",
      ]:
        endpointCache = try container.decode(
          [AgentEventEndpointVerificationCacheEntry].self,
          forKey: AgentEventCallbackVerificationCodingKey("endpointCache")
        )
      default:
        throw AgentEventCallbackVerificationStoreError.storageFailure
      }
      intents = try container.decode(
        [AgentEventCallbackVerificationIntent].self,
        forKey: AgentEventCallbackVerificationCodingKey("intents")
      )
      proofs = try container.decode(
        [AgentEventCallbackVerificationProof].self,
        forKey: AgentEventCallbackVerificationCodingKey("proofs")
      )
      lastObservedAt = try container.decode(
        Date.self,
        forKey: AgentEventCallbackVerificationCodingKey("lastObservedAt")
      )
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: AgentEventCallbackVerificationCodingKey.self)
      try container.encode(
        schemaVersion, forKey: AgentEventCallbackVerificationCodingKey("schemaVersion"))
      try container.encode(intents, forKey: AgentEventCallbackVerificationCodingKey("intents"))
      try container.encode(proofs, forKey: AgentEventCallbackVerificationCodingKey("proofs"))
      try container.encode(
        endpointCache,
        forKey: AgentEventCallbackVerificationCodingKey("endpointCache")
      )
      try container.encode(
        lastObservedAt, forKey: AgentEventCallbackVerificationCodingKey("lastObservedAt"))
    }

    private static func bindingOrder(_ binding: AgentEventCallbackVerificationBinding) -> String {
      [
        binding.profileID.uuidString.lowercased(),
        binding.subscriptionID,
        String(binding.subscriptionRevision),
        String(binding.grantRevision),
        binding.signingKeyReference,
      ].joined(separator: "\u{0}")
    }

    private static func endpointCacheOrder(_ entry: AgentEventEndpointVerificationCacheEntry)
      -> String
    {
      [
        entry.profileID.uuidString.lowercased(),
        entry.canonicalCallbackURLDigest,
      ].joined(separator: "\u{0}")
    }
  }

  private static let maximumFileSize = 1_048_576
  private static let maximumIntents = 128
  private static let maximumProofs = 128
  private static let maximumEndpointCacheEntries = 128
  static let maximumIntentLifetime: TimeInterval = 60
  private static let maximumProofLifetime: TimeInterval = 600
  private static let stateLock = NSLock()

  private let fileURL: URL
  private let clock: @Sendable () -> Date
  private let fileWriter: @Sendable (Data, URL) throws -> Void

  init(
    fileURL: URL? = nil,
    now: @escaping @Sendable () -> Date = { Date() },
    fileWriter: @escaping @Sendable (Data, URL) throws -> Void = {
      try $0.write(to: $1, options: .atomic)
    }
  ) {
    self.fileURL = fileURL ?? Self.defaultFileURL()
    clock = now
    self.fileWriter = fileWriter
  }

  func currentProof(for binding: AgentEventCallbackVerificationBinding) throws
    -> AgentEventCallbackVerificationProof?
  {
    try Self.stateLock.withLock {
      guard Self.isValid(binding) else {
        throw AgentEventCallbackVerificationStoreError.invalidBinding
      }
      let now = clock()
      guard Self.isValidDate(now) else {
        throw AgentEventCallbackVerificationStoreError.invalidBinding
      }
      var state = try loadState()
      if !FileManager.default.fileExists(atPath: fileURL.path),
        state.intents.isEmpty, state.proofs.isEmpty
      {
        return nil
      }
      let (changed, clockMovedBackwards) = Self.normalize(&state, now: now)
      if changed { try saveState(state) }
      if clockMovedBackwards { return nil }
      return state.proofs.first { $0.binding == binding }
    }
  }

  func endpointCacheEntry(
    profileID: UUID,
    canonicalCallbackURL: String,
    grantRevision: UInt64,
    signingKeyReference: String
  ) throws -> AgentEventEndpointVerificationCacheEntry? {
    try Self.stateLock.withLock {
      guard let canonicalCallbackURLDigest = Self.canonicalURLSHA256Digest(canonicalCallbackURL),
        Self.isValidEndpointCacheKey(
          profileID: profileID,
          canonicalCallbackURL: canonicalCallbackURL,
          grantRevision: grantRevision,
          signingKeyReference: signingKeyReference
        )
      else {
        throw AgentEventCallbackVerificationStoreError.invalidBinding
      }
      let now = clock()
      guard Self.isValidDate(now) else {
        throw AgentEventCallbackVerificationStoreError.invalidBinding
      }
      var state = try loadState()
      if !FileManager.default.fileExists(atPath: fileURL.path),
        state.intents.isEmpty, state.proofs.isEmpty, state.endpointCache.isEmpty
      {
        return nil
      }
      let (changed, clockMovedBackwards) = Self.normalize(&state, now: now)
      if changed { try saveState(state) }
      guard !clockMovedBackwards else { return nil }
      return state.endpointCache.first {
        $0.profileID == profileID
          && $0.canonicalCallbackURLDigest == canonicalCallbackURLDigest
          && $0.grantRevision == grantRevision
          && $0.signingKeyReference == signingKeyReference
          && now >= $0.verifiedAt
          && now < $0.expiresAt
      }
    }
  }

  func begin(_ intent: AgentEventCallbackVerificationIntent) throws {
    try Self.stateLock.withLock {
      guard Self.isValid(intent) else {
        throw AgentEventCallbackVerificationStoreError.invalidBinding
      }
      let now = clock()
      guard Self.isValidDate(now) else {
        throw AgentEventCallbackVerificationStoreError.invalidBinding
      }
      var state = try loadState()
      let (changed, clockMovedBackwards) = Self.normalize(&state, now: now)
      guard !clockMovedBackwards else {
        if changed { try saveState(state) }
        throw AgentEventCallbackVerificationStoreError.staleIntent
      }
      if state.intents.contains(where: { $0.binding == intent.binding }) {
        if changed { try saveState(state) }
        throw AgentEventCallbackVerificationStoreError.verificationInProgress
      }
      guard
        !state.intents.contains(where: { $0.id == intent.id }),
        !state.proofs.contains(where: { $0.originIntentID == intent.id }),
        !state.intents.contains(where: { $0.nonceDigest == intent.nonceDigest }),
        now >= intent.createdAt,
        now < intent.expiresAt
      else {
        if changed { try saveState(state) }
        throw AgentEventCallbackVerificationStoreError.staleIntent
      }
      guard state.intents.count < Self.maximumIntents else {
        if changed { try saveState(state) }
        throw AgentEventCallbackVerificationStoreError.capacityExceeded
      }
      let reservedProofBindings = Set(state.proofs.map(\.binding)).union(
        state.intents.map(\.binding)
      )
      guard
        reservedProofBindings.contains(intent.binding)
          || reservedProofBindings.count < Self.maximumProofs
      else {
        if changed { try saveState(state) }
        throw AgentEventCallbackVerificationStoreError.capacityExceeded
      }
      state.lastObservedAt = now
      state.intents.append(intent)
      try saveState(state)
    }
  }

  func cancel(_ intent: AgentEventCallbackVerificationIntent) throws {
    try Self.stateLock.withLock {
      var state = try loadState()
      guard let index = state.intents.firstIndex(of: intent) else { return }
      state.intents.remove(at: index)
      try saveState(state)
    }
  }

  func observe(_ intent: AgentEventCallbackVerificationIntent) throws {
    try Self.stateLock.withLock {
      guard Self.isValid(intent) else {
        throw AgentEventCallbackVerificationStoreError.invalidBinding
      }
      let now = clock()
      guard Self.isValidDate(now) else {
        throw AgentEventCallbackVerificationStoreError.invalidBinding
      }
      var state = try loadState()
      let (changed, clockMovedBackwards) = Self.normalize(&state, now: now)
      guard !clockMovedBackwards,
        state.intents.contains(intent),
        now >= intent.createdAt,
        now < intent.expiresAt
      else {
        if changed { try saveState(state) }
        throw AgentEventCallbackVerificationStoreError.staleIntent
      }
      state.lastObservedAt = now
      try saveState(state)
    }
  }

  func complete(
    _ intent: AgentEventCallbackVerificationIntent,
    subscriptionExpiresAt: Date,
    canonicalCallbackURL: String? = nil
  ) throws -> AgentEventCallbackVerificationProof {
    try Self.stateLock.withLock {
      guard
        Self.isValid(intent), Self.isValidDate(subscriptionExpiresAt),
        canonicalCallbackURL.map(Self.isCanonicalCallbackURL) ?? true
      else {
        throw AgentEventCallbackVerificationStoreError.invalidBinding
      }
      let now = clock()
      guard Self.isValidDate(now) else {
        throw AgentEventCallbackVerificationStoreError.invalidBinding
      }
      var state = try loadState()
      let (changed, clockMovedBackwards) = Self.normalize(&state, now: now)
      guard !clockMovedBackwards,
        let index = state.intents.firstIndex(of: intent),
        !state.proofs.contains(where: {
          $0.binding.profileID == intent.binding.profileID
            && $0.binding.subscriptionID == intent.binding.subscriptionID
            && $0.binding.subscriptionRevision > intent.binding.subscriptionRevision
        }),
        now >= intent.createdAt,
        now < intent.expiresAt,
        now < subscriptionExpiresAt
      else {
        if changed { try saveState(state) }
        throw AgentEventCallbackVerificationStoreError.staleIntent
      }

      let proof = AgentEventCallbackVerificationProof(
        binding: intent.binding,
        originIntentID: intent.id,
        verifiedAt: now,
        expiresAt: min(now.addingTimeInterval(Self.maximumProofLifetime), subscriptionExpiresAt)
      )
      guard Self.isValid(proof) else {
        if changed { try saveState(state) }
        throw AgentEventCallbackVerificationStoreError.staleIntent
      }
      let replacing = state.proofs.firstIndex { $0.binding == intent.binding }
      if replacing == nil {
        state.proofs.removeAll {
          $0.binding.profileID == intent.binding.profileID
            && $0.binding.subscriptionID == intent.binding.subscriptionID
            && $0.binding.subscriptionRevision < intent.binding.subscriptionRevision
        }
      }
      guard replacing != nil || state.proofs.count < Self.maximumProofs else {
        if changed { try saveState(state) }
        throw AgentEventCallbackVerificationStoreError.capacityExceeded
      }
      state.intents.remove(at: index)
      if let replacing {
        state.proofs[replacing] = proof
      } else {
        state.proofs.append(proof)
      }
      if let canonicalCallbackURL {
        guard let canonicalCallbackURLDigest = Self.canonicalURLSHA256Digest(canonicalCallbackURL)
        else {
          throw AgentEventCallbackVerificationStoreError.invalidBinding
        }
        let cacheEntry = AgentEventEndpointVerificationCacheEntry(
          id: UUID(),
          profileID: intent.binding.profileID,
          canonicalCallbackURLDigest: canonicalCallbackURLDigest,
          grantRevision: intent.binding.grantRevision,
          signingKeyReference: intent.binding.signingKeyReference,
          verifiedAt: proof.verifiedAt,
          expiresAt: proof.expiresAt
        )
        if let cachedIndex = state.endpointCache.firstIndex(where: {
          $0.profileID == cacheEntry.profileID
            && $0.canonicalCallbackURLDigest == cacheEntry.canonicalCallbackURLDigest
        }) {
          state.endpointCache[cachedIndex] = cacheEntry
        } else {
          if state.endpointCache.count >= Self.maximumEndpointCacheEntries {
            let oldestIndex = state.endpointCache.indices.min {
              let lhs = state.endpointCache[$0]
              let rhs = state.endpointCache[$1]
              if lhs.verifiedAt != rhs.verifiedAt { return lhs.verifiedAt < rhs.verifiedAt }
              return Self.endpointCacheOrder(lhs) < Self.endpointCacheOrder(rhs)
            }
            if let oldestIndex { state.endpointCache.remove(at: oldestIndex) }
          }
          state.endpointCache.append(cacheEntry)
        }
      }
      state.lastObservedAt = now
      try saveState(state)
      return proof
    }
  }

  func materializeProof(
    cachedEntry: AgentEventEndpointVerificationCacheEntry,
    targetBinding: AgentEventCallbackVerificationBinding,
    subscriptionExpiresAt: Date,
    originID: UUID
  ) throws -> AgentEventCallbackVerificationProof {
    try Self.stateLock.withLock {
      guard
        Self.isValid(cachedEntry),
        Self.isValid(targetBinding),
        Self.isValidDate(subscriptionExpiresAt),
        cachedEntry.profileID == targetBinding.profileID,
        cachedEntry.grantRevision == targetBinding.grantRevision,
        cachedEntry.signingKeyReference == targetBinding.signingKeyReference
      else {
        throw AgentEventCallbackVerificationStoreError.invalidBinding
      }
      let now = clock()
      guard Self.isValidDate(now) else {
        throw AgentEventCallbackVerificationStoreError.invalidBinding
      }
      var state = try loadState()
      let (changed, clockMovedBackwards) = Self.normalize(&state, now: now)
      guard !clockMovedBackwards,
        state.endpointCache.contains(cachedEntry),
        now >= cachedEntry.verifiedAt,
        now < cachedEntry.expiresAt,
        now < subscriptionExpiresAt
      else {
        if changed { try saveState(state) }
        throw AgentEventCallbackVerificationStoreError.staleIntent
      }
      if let existing = state.proofs.first(where: { $0.binding == targetBinding }) {
        guard existing.expiresAt <= subscriptionExpiresAt else {
          if changed { try saveState(state) }
          throw AgentEventCallbackVerificationStoreError.storageFailure
        }
        if changed { try saveState(state) }
        return existing
      }
      guard
        !state.proofs.contains(where: {
          $0.binding.profileID == targetBinding.profileID
            && $0.binding.subscriptionID == targetBinding.subscriptionID
            && $0.binding.subscriptionRevision > targetBinding.subscriptionRevision
        }),
        !state.intents.contains(where: {
          $0.binding.profileID == targetBinding.profileID
            && $0.binding.subscriptionID == targetBinding.subscriptionID
            && $0.binding.subscriptionRevision > targetBinding.subscriptionRevision
        }),
        !state.intents.contains(where: { $0.id == originID }),
        !state.proofs.contains(where: { $0.originIntentID == originID })
      else {
        if changed { try saveState(state) }
        throw AgentEventCallbackVerificationStoreError.staleIntent
      }
      state.proofs.removeAll {
        $0.binding.profileID == targetBinding.profileID
          && $0.binding.subscriptionID == targetBinding.subscriptionID
          && $0.binding.subscriptionRevision < targetBinding.subscriptionRevision
      }
      let reservedProofBindings = Set(state.proofs.map(\.binding)).union(
        state.intents.map(\.binding)
      )
      guard reservedProofBindings.contains(targetBinding)
        || reservedProofBindings.count < Self.maximumProofs
      else {
        if changed { try saveState(state) }
        throw AgentEventCallbackVerificationStoreError.capacityExceeded
      }
      let proof = AgentEventCallbackVerificationProof(
        binding: targetBinding,
        originIntentID: originID,
        verifiedAt: cachedEntry.verifiedAt,
        expiresAt: min(cachedEntry.expiresAt, subscriptionExpiresAt)
      )
      guard Self.isValid(proof) else {
        if changed { try saveState(state) }
        throw AgentEventCallbackVerificationStoreError.staleIntent
      }
      state.proofs.append(proof)
      state.lastObservedAt = now
      try saveState(state)
      return proof
    }
  }

  func removeProof(
    for binding: AgentEventCallbackVerificationBinding,
    generatedBy intentID: UUID
  ) throws {
    try Self.stateLock.withLock {
      guard Self.isValid(binding) else {
        throw AgentEventCallbackVerificationStoreError.invalidBinding
      }
      var state = try loadState()
      guard
        let index = state.proofs.firstIndex(where: {
          $0.binding == binding && $0.originIntentID == intentID
        })
      else { return }
      state.proofs.remove(at: index)
      try saveState(state)
    }
  }

  private func loadState() throws -> State {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return State(
        intents: [],
        proofs: [],
        endpointCache: [],
        lastObservedAt: Date(timeIntervalSince1970: 0)
      )
    }
    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
      guard
        attributes[.type] as? FileAttributeType == .typeRegular,
        let fileSize = attributes[.size] as? NSNumber,
        fileSize.intValue <= Self.maximumFileSize
      else {
        throw AgentEventCallbackVerificationStoreError.storageFailure
      }
      let data = try Data(contentsOf: fileURL)
      guard data.count <= Self.maximumFileSize else {
        throw AgentEventCallbackVerificationStoreError.storageFailure
      }
      let document = try JSONDecoder().decode(Document.self, from: data)
      let state = State(
        intents: document.intents,
        proofs: document.proofs,
        endpointCache: document.endpointCache,
        lastObservedAt: document.lastObservedAt
      )
      guard Self.isValid(state) else {
        throw AgentEventCallbackVerificationStoreError.storageFailure
      }
      return state
    } catch let error as AgentEventCallbackVerificationStoreError {
      throw error
    } catch {
      throw AgentEventCallbackVerificationStoreError.storageFailure
    }
  }

  private func saveState(_ state: State) throws {
    do {
      guard Self.isValid(state) else {
        throw AgentEventCallbackVerificationStoreError.storageFailure
      }
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      let data = try encoder.encode(Document(state))
      guard data.count <= Self.maximumFileSize else {
        throw AgentEventCallbackVerificationStoreError.storageFailure
      }
      let directoryURL = fileURL.deletingLastPathComponent()
      try FileManager.default.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o700],
        ofItemAtPath: directoryURL.path
      )
      do {
        try fileWriter(data, fileURL)
      } catch {
        let persistedData: Data?
        if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
          attributes[.type] as? FileAttributeType == .typeRegular,
          let fileSize = attributes[.size] as? NSNumber,
          fileSize.intValue <= Self.maximumFileSize
        {
          persistedData = try? Data(contentsOf: fileURL)
        } else {
          persistedData = nil
        }
        guard persistedData == data else {
          throw AgentEventCallbackVerificationStoreError.storageFailure
        }
      }
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: fileURL.path
      )
    } catch let error as AgentEventCallbackVerificationStoreError {
      throw error
    } catch {
      throw AgentEventCallbackVerificationStoreError.storageFailure
    }
  }

  private static func normalize(_ state: inout State, now: Date) -> (Bool, Bool) {
    var changed = false
    if now < state.lastObservedAt {
      if !state.intents.isEmpty || !state.proofs.isEmpty || !state.endpointCache.isEmpty {
        changed = true
      }
      state.intents.removeAll()
      state.proofs.removeAll()
      state.endpointCache.removeAll()
      return (changed, true)
    }

    let activeIntents = state.intents.filter {
      now >= $0.createdAt && now < $0.expiresAt
    }
    let activeProofs = state.proofs.filter {
      now >= $0.verifiedAt && now < $0.expiresAt
    }
    if activeIntents != state.intents {
      state.intents = activeIntents
      changed = true
    }
    if activeProofs != state.proofs {
      state.proofs = activeProofs
      changed = true
    }
    let activeEndpointCache = state.endpointCache.filter {
      now >= $0.verifiedAt && now < $0.expiresAt
    }
    if activeEndpointCache != state.endpointCache {
      state.endpointCache = activeEndpointCache
      changed = true
    }
    if now > state.lastObservedAt {
      state.lastObservedAt = now
      changed = true
    }
    return (changed, false)
  }

  private static func isValid(_ binding: AgentEventCallbackVerificationBinding) -> Bool {
    let subscriptionBytes = Array(binding.subscriptionID.utf8)
    guard
      binding.subscriptionRevision > 0,
      binding.grantRevision > 0,
      subscriptionBytes.count == 68,
      binding.subscriptionID.hasPrefix("evt_"),
      subscriptionBytes.dropFirst(4).allSatisfy({
        (48...57).contains($0) || (97...102).contains($0)
      }),
      let reference = UUID(uuidString: binding.signingKeyReference),
      reference.uuidString.lowercased() == binding.signingKeyReference
    else {
      return false
    }
    return true
  }

  private static func isValid(_ intent: AgentEventCallbackVerificationIntent) -> Bool {
    isValid(intent.binding)
      && intent.nonceDigest.count == 32
      && isValidDate(intent.createdAt)
      && isValidDate(intent.expiresAt)
      && intent.expiresAt > intent.createdAt
      && intent.expiresAt.timeIntervalSince(intent.createdAt) <= maximumIntentLifetime
  }

  private static func isValid(_ proof: AgentEventCallbackVerificationProof) -> Bool {
    isValid(proof.binding)
      && isValidDate(proof.verifiedAt)
      && isValidDate(proof.expiresAt)
      && proof.expiresAt > proof.verifiedAt
      && proof.expiresAt.timeIntervalSince(proof.verifiedAt) <= maximumProofLifetime
  }

  private static func isValid(_ entry: AgentEventEndpointVerificationCacheEntry) -> Bool {
    guard
      isValidDate(entry.verifiedAt),
      isValidDate(entry.expiresAt),
      entry.grantRevision > 0,
      isCanonicalCallbackURLDigest(entry.canonicalCallbackURLDigest),
      let keyReference = UUID(uuidString: entry.signingKeyReference),
      keyReference.uuidString.lowercased() == entry.signingKeyReference,
      entry.expiresAt > entry.verifiedAt,
      entry.expiresAt.timeIntervalSince(entry.verifiedAt) <= maximumProofLifetime
    else {
      return false
    }
    return true
  }

  private static func isValidEndpointCacheKey(
    profileID: UUID,
    canonicalCallbackURL: String,
    grantRevision: UInt64,
    signingKeyReference: String
  ) -> Bool {
    guard grantRevision > 0, isCanonicalCallbackURL(canonicalCallbackURL),
      let reference = UUID(uuidString: signingKeyReference)
    else {
      return false
    }
    return reference.uuidString.lowercased() == signingKeyReference
  }

  private static func isCanonicalCallbackURL(_ value: String) -> Bool {
    (try? AgentEventSubscriptionIdentity.canonicalCallbackURL(value)) == value
  }

  static func canonicalURLSHA256Digest(_ canonicalCallbackURL: String) -> String? {
    guard isCanonicalCallbackURL(canonicalCallbackURL) else { return nil }
    return AgentCredentialSecurity.sha256(Data(canonicalCallbackURL.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
  }

  private static func isCanonicalCallbackURLDigest(_ value: String) -> Bool {
    let bytes = Array(value.utf8)
    return bytes.count == 64 && bytes.allSatisfy {
      (48...57).contains($0) || (97...102).contains($0)
    }
  }

  private static func endpointCacheOrder(_ entry: AgentEventEndpointVerificationCacheEntry)
    -> String
  {
    [entry.profileID.uuidString.lowercased(), entry.canonicalCallbackURLDigest]
      .joined(separator: "\u{0}")
  }

  private static func isValid(_ state: State) -> Bool {
    guard
      state.intents.count <= maximumIntents,
      state.proofs.count <= maximumProofs,
      state.endpointCache.count <= maximumEndpointCacheEntries,
      isValidDate(state.lastObservedAt),
      state.intents.allSatisfy(isValid),
      state.proofs.allSatisfy(isValid),
      state.endpointCache.allSatisfy(isValid)
    else {
      return false
    }
    let intentIDs = state.intents.map(\.id)
    let nonceDigests = state.intents.map(\.nonceDigest)
    let proofBindings = state.proofs.map(\.binding)
    let proofGenerationIDs = state.proofs.map(\.originIntentID)
    let endpointIDs = state.endpointCache.map(\.id)
    let endpointKeys = state.endpointCache.map {
      "\($0.profileID.uuidString.lowercased())\u{0}\($0.canonicalCallbackURLDigest)"
    }
    let reservedProofBindings = Set(state.proofs.map(\.binding)).union(
      state.intents.map(\.binding)
    )
    return Set(intentIDs).count == intentIDs.count
      && Set(nonceDigests).count == nonceDigests.count
      && Set(proofBindings).count == proofBindings.count
      && Set(proofGenerationIDs).count == proofGenerationIDs.count
      && Set(endpointIDs).count == endpointIDs.count
      && Set(endpointKeys).count == endpointKeys.count
      && Set(intentIDs).isDisjoint(with: proofGenerationIDs)
      && Set(state.intents.map(\.binding)).count == state.intents.count
      && reservedProofBindings.count <= maximumProofs
      && state.intents.allSatisfy({ $0.createdAt <= state.lastObservedAt })
      && state.proofs.allSatisfy({ $0.verifiedAt <= state.lastObservedAt })
      && state.endpointCache.allSatisfy({ $0.verifiedAt <= state.lastObservedAt })
  }

  private static func isValidDate(_ date: Date) -> Bool {
    let seconds = date.timeIntervalSince1970
    return seconds.isFinite && seconds >= 0
  }

  private static func defaultFileURL() -> URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent(FleckProductPaths.canonicalDirectoryName, isDirectory: true)
      .appendingPathComponent("AgentIntegrations", isDirectory: true)
      .appendingPathComponent("AgentEvents", isDirectory: true)
      .appendingPathComponent("callback-verification.json", isDirectory: false)
  }
}

private struct AgentEventCallbackVerificationCodingKey: CodingKey {
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
    throw AgentEventCallbackVerificationStoreError.storageFailure
  }
}
