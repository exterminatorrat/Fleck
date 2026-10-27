import CryptoKit
import FleckCore
import Foundation

struct AgentEventSubscriptionReceipt: Equatable, Sendable {
  let subscriptionID: String
  let status: AgentEventPendingStatus
  let expiresAt: Date
  let revision: UInt64
  let grantRevision: UInt64
}

typealias AgentEventWorkspaceProvider = @Sendable () async throws -> Workspace

actor AgentEventSubscriptionLifecycleGate {
  private var isOccupied = false
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private var queueObservers: [CheckedContinuation<Void, Never>] = []

  func withExclusiveAccess<Value: Sendable>(
    _ operation: @Sendable () async throws -> Value
  ) async throws -> Value {
    await acquire()
    defer { release() }
    return try await operation()
  }

  private func acquire() async {
    guard isOccupied else {
      isOccupied = true
      return
    }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
      let observers = queueObservers
      queueObservers.removeAll()
      for observer in observers {
        observer.resume()
      }
    }
  }

  func waitForQueuedOperation() async {
    guard waiters.isEmpty else { return }
    await withCheckedContinuation { continuation in
      queueObservers.append(continuation)
    }
  }

  private func release() {
    guard !waiters.isEmpty else {
      isOccupied = false
      return
    }
    waiters.removeFirst().resume()
  }
}

struct AgentEventSubscriptionService: Sendable {
  private static let lifecycleGate = AgentEventSubscriptionLifecycleGate()
  private let authority: AgentCapabilityAuthority
  private let store: AgentEventSubscriptionStore
  private let signingKeyStore: AgentEventSigningKeyStore
  private let clock: @Sendable () -> Date

  init(
    authority: AgentCapabilityAuthority,
    store: AgentEventSubscriptionStore = AgentEventSubscriptionStore(),
    signingKeyStore: AgentEventSigningKeyStore = AgentEventSigningKeyStore(),
    clock: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.authority = authority
    self.store = store
    self.signingKeyStore = signingKeyStore
    self.clock = clock
  }

  static func waitForQueuedLifecycleOperation() async {
    await lifecycleGate.waitForQueuedOperation()
  }

  func maintainSigningKeyLifecycle(now: Date) async throws {
    try await Self.lifecycleGate.withExclusiveAccess { [self] in
      let clockMovedBackwards = try await store.observeTrustedClock(now: now)
      if clockMovedBackwards {
        try await cleanupRetiredSigningKeys()
        throw AgentEventSubscriptionError.invalidConfiguration
      }
      try await cleanupRetiredSigningKeys()
    }
  }

  func pruneExpiredSubscriptions(now: Date) async throws {
    try await Self.lifecycleGate.withExclusiveAccess { [self] in
      let clockMovedBackwards = try await store.observeTrustedClock(now: now)
      if clockMovedBackwards {
        try await cleanupRetiredSigningKeys()
        throw AgentEventSubscriptionError.invalidConfiguration
      }
      _ = try await store.pruneExpired(now: now)
      try await cleanupRetiredSigningKeys()
    }
  }

  func retirePreviousSigningKey(subscriptionID: String, now: Date) async throws {
    try await Self.lifecycleGate.withExclusiveAccess { [self] in
      let clockMovedBackwards = try await store.observeTrustedClock(now: now)
      if clockMovedBackwards {
        try await cleanupRetiredSigningKeys()
        throw AgentEventSubscriptionError.invalidConfiguration
      }
      guard let current = try await store.currentSubscription(id: subscriptionID) else {
        try await cleanupRetiredSigningKeys()
        return
      }
      if current.previousSigningKey != nil {
        _ = try await store.retirePreviousSigningKey(
          subscriptionID: subscriptionID,
          expected: current
        )
      }
      try await cleanupRetiredSigningKeys()
    }
  }

  func listEvents(profileID: UUID, workspace: Workspace) async throws -> [AgentEventDescriptor] {
    let state = try await authority.store.currentState()
    guard let profile = state.profiles[profileID],
      profile.allowsEventObservation,
      profile.allowedCapabilities.contains(.readNotes)
    else {
      throw AgentWorkspaceError(code: .capabilityDenied)
    }

    let snapshot = try await authority.snapshot(profileID: profileID, workspace: workspace)
    let noteScopeAvailable = workspace.notes.contains {
      snapshot.readableNoteIDs.contains($0.id)
    }
    let folderScopeAvailable = workspace.folders.contains { folder in
      let hasReadableFutureFolderGrant = profile.grants.contains { grant in
        guard case .folderIncludingFutureNotes(let grantedFolderID) = grant.scope else {
          return false
        }
        return grantedFolderID == folder.id && grant.authority.allows(.read)
      }
      guard hasReadableFutureFolderGrant else { return false }
      return workspace.notes.filter { $0.folderID == folder.id }.allSatisfy {
        snapshot.readableNoteIDs.contains($0.id)
      }
    }
    return AgentEventCatalog.events(
      noteScopeAvailable: noteScopeAvailable,
      folderScopeAvailable: folderScopeAvailable
    )
  }

  func createPending(
    profileID: UUID,
    event: AgentEventName,
    scope: AgentEventScope,
    callbackURL: String,
    signingSecret: String,
    requestedTTLSeconds: TimeInterval? = nil,
    workspaceProvider: @escaping AgentEventWorkspaceProvider,
    now: Date? = nil
  ) async throws -> AgentEventSubscriptionReceipt {
    try await Self.lifecycleGate.withExclusiveAccess { [self] in
      try await createPendingExclusively(
        profileID: profileID,
        event: event,
        scope: scope,
        callbackURL: callbackURL,
        signingSecret: signingSecret,
        requestedTTLSeconds: requestedTTLSeconds,
        workspaceProvider: workspaceProvider,
        now: now
      )
    }
  }

  private func createPendingExclusively(
    profileID: UUID,
    event: AgentEventName,
    scope: AgentEventScope,
    callbackURL: String,
    signingSecret: String,
    requestedTTLSeconds: TimeInterval?,
    workspaceProvider: @escaping AgentEventWorkspaceProvider,
    now: Date?
  ) async throws -> AgentEventSubscriptionReceipt {
    let canonicalURL = try AgentEventSubscriptionIdentity.canonicalCallbackURL(callbackURL)
    let ttl = try AgentEventSubscriptionIdentity.grantedTTL(requestedTTLSeconds)
    let workspace = try await currentWorkspace(from: workspaceProvider)
    let grantRevision = try await authority.authorizeEventObservation(
      profileID: profileID,
      scope: scope,
      workspace: workspace
    )
    let operationTime = now ?? clock()
    guard Self.isValidClockDate(operationTime) else {
      throw AgentEventSubscriptionError.invalidConfiguration
    }
    let clockMovedBackwards = try await store.observeTrustedClock(now: operationTime)
    if clockMovedBackwards {
      try await cleanupRetiredSigningKeys()
      throw AgentEventSubscriptionError.invalidConfiguration
    }
    try await cleanupRetiredSigningKeys()
    _ = try await store.pruneExpired(now: operationTime)
    try await cleanupRetiredSigningKeys()

    let subscriptionID = AgentEventSubscriptionIdentity.subscriptionID(
      profileID: profileID,
      event: event,
      scope: scope,
      callbackURL: canonicalURL
    )
    let secretData = try signingKeyStore.validatedSecretData(from: signingSecret)
    let previous = try await store.currentSubscription(id: subscriptionID)
    let canPreserveKey = previous.map {
      $0.expiresAt > operationTime && $0.grantRevision == grantRevision
    } ?? false
    let preserveCurrentKey: Bool
    if canPreserveKey, let previous {
      let currentSecret = try signingKeyStore.validatedSecretData(
        reference: previous.signingKeyReference
      )
      preserveCurrentKey = AgentCredentialSecurity.constantTimeEqual(secretData, currentSecret)
      if let overlap = previous.previousSigningKey, overlap.expiresAt > operationTime,
        !preserveCurrentKey
      {
        let remaining = overlap.expiresAt.timeIntervalSince(operationTime)
        let retryAfterMs = max(
          1,
          Int((min(remaining, AgentEventPreviousSigningKey.maximumLifetime) * 1_000).rounded(.up))
        )
        throw AgentWorkspaceError.signingKeyRotationInProgress(retryAfterMs: retryAfterMs)
      }
    } else {
      preserveCurrentKey = false
    }
    let keyReference: String
    if preserveCurrentKey {
      guard let previous else {
        throw AgentEventSubscriptionError.storageFailure
      }
      keyReference = previous.signingKeyReference
    } else {
      keyReference = AgentEventSigningKeyStore.newReference()
    }
    if !preserveCurrentKey {
      try await store.reserveSigningKeyReference(keyReference)
      do {
        try signingKeyStore.store(secretData: secretData, reference: keyReference)
      } catch {
        await discardStagedSigningKey(keyReference)
        throw error
      }
    }
    do {
      let currentWorkspace = try await currentWorkspace(from: workspaceProvider)
      try await authority.assertEventObservationCurrent(
        profileID: profileID,
        grantRevision: grantRevision,
        scope: scope,
        workspace: currentWorkspace
      )
    } catch {
      await discardStagedSigningKey(keyReference)
      throw error
    }

    let commitTime = now ?? clock()
    guard Self.isValidClockDate(commitTime) else {
      if !preserveCurrentKey { await discardStagedSigningKey(keyReference) }
      throw AgentEventSubscriptionError.invalidConfiguration
    }
    let commitClockMovedBackwards: Bool
    do {
      commitClockMovedBackwards = try await store.observeTrustedClock(now: commitTime)
    } catch {
      if !preserveCurrentKey { await discardStagedSigningKey(keyReference) }
      throw error
    }
    if commitClockMovedBackwards {
      if !preserveCurrentKey { await discardStagedSigningKey(keyReference) }
      try await cleanupRetiredSigningKeys()
      throw AgentEventSubscriptionError.invalidConfiguration
    }
    guard
      commitTime >= operationTime,
      commitTime.addingTimeInterval(ttl).timeIntervalSince1970.isFinite
    else {
      if !preserveCurrentKey { await discardStagedSigningKey(keyReference) }
      throw AgentEventSubscriptionError.invalidConfiguration
    }
    do {
      try await cleanupRetiredSigningKeys(includeStaged: false)
    } catch {
      if !preserveCurrentKey { await discardStagedSigningKey(keyReference) }
      throw error
    }
    let latestPrevious: AgentEventPendingSubscription?
    do {
      latestPrevious = try await store.currentSubscription(id: subscriptionID)
    } catch {
      if !preserveCurrentKey { await discardStagedSigningKey(keyReference) }
      throw error
    }
    guard
      latestPrevious?.replacingPreviousSigningKey(previous?.previousSigningKey) == previous
    else {
      if !preserveCurrentKey { await discardStagedSigningKey(keyReference) }
      throw AgentWorkspaceError(code: .capabilityDenied)
    }
    let candidate = AgentEventPendingSubscription(
      subscriptionID: subscriptionID,
      profileID: profileID,
      event: event,
      scope: scope,
      callbackURL: canonicalURL,
      signingKeyReference: keyReference,
      grantRevision: grantRevision,
      createdAt: latestPrevious?.createdAt ?? commitTime,
      updatedAt: commitTime,
      expiresAt: commitTime.addingTimeInterval(ttl),
      revision: (previous?.revision ?? 0) + 1
    )
    let mutation: AgentEventSubscriptionMutation
    let clock = self.clock
    let acceptanceClock: @Sendable () -> Date = { now ?? clock() }
    do {
      mutation = try await store.createOrRefresh(
        candidate,
        expectedPrevious: latestPrevious,
        keyDisposition: preserveCurrentKey ? .preserveCurrent : .rotateToStagedKey,
        now: commitTime,
        acceptedTTL: ttl,
        acceptanceClock: acceptanceClock
      )
    } catch {
      if !preserveCurrentKey { await discardStagedSigningKey(keyReference) }
      try? await cleanupRetiredSigningKeys()
      throw error
    }

    do {
      let currentWorkspace = try await currentWorkspace(from: workspaceProvider)
      try await authority.assertEventObservationCurrent(
        profileID: profileID,
        grantRevision: grantRevision,
        scope: scope,
        workspace: currentWorkspace
      )
    } catch {
      if (try? await store.rollback(mutation)) != true {
        try? await store.retainSigningKeyForDeletion(reference: keyReference)
      }
      try? await cleanupRetiredSigningKeys()
      throw error
    }

    guard
      let current = try await store.currentSubscription(id: subscriptionID),
      current == mutation.stored
    else {
      try? await store.retainSigningKeyForDeletion(reference: keyReference)
      try? await cleanupRetiredSigningKeys()
      throw AgentWorkspaceError(code: .capabilityDenied)
    }
    try? await cleanupRetiredSigningKeys()
    return AgentEventSubscriptionReceipt(
      subscriptionID: current.subscriptionID,
      status: current.status,
      expiresAt: current.expiresAt,
      revision: current.revision,
      grantRevision: current.grantRevision
    )
  }

  func remove(profileID: UUID, subscriptionID: String) async throws {
    try await Self.lifecycleGate.withExclusiveAccess { [self] in
      guard Self.isValidSubscriptionID(subscriptionID) else {
        throw AgentEventSubscriptionError.invalidConfiguration
      }
      guard
        try await store.remove(subscriptionID: subscriptionID, profileID: profileID) != nil
      else {
        return
      }
      try? await cleanupRetiredSigningKeys()
    }
  }

  private func currentWorkspace(
    from provider: AgentEventWorkspaceProvider
  ) async throws -> Workspace {
    do {
      return try await provider()
    } catch {
      throw AgentWorkspaceError(code: .capabilityDenied)
    }
  }

  private func discardStagedSigningKey(_ reference: String) async {
    do {
      guard try await store.isSigningKeyReferenced(reference) == false else { return }
      try signingKeyStore.delete(reference: reference)
      try await store.acknowledgeSigningKeyDeletion(reference: reference)
    } catch {
      return
    }
  }

  private func cleanupRetiredSigningKeys(includeStaged: Bool = true) async throws {
    let references: [String]
    if includeStaged {
      references = try await store.pendingSigningKeyCleanupReferences()
    } else {
      references = try await store.pendingSigningKeyDeletions()
    }
    var failed = false
    for reference in references {
      do {
        guard try await store.isSigningKeyReferenced(reference) == false else { continue }
        try signingKeyStore.delete(reference: reference)
        try await store.acknowledgeSigningKeyDeletion(reference: reference)
      } catch {
        failed = true
      }
    }
    if failed {
      throw AgentEventSubscriptionError.storageFailure
    }
  }

  private static func isValidClockDate(_ date: Date) -> Bool {
    date.timeIntervalSince1970.isFinite && date.timeIntervalSince1970 >= 0
  }

  private static func isValidSubscriptionID(_ value: String) -> Bool {
    value.hasPrefix("evt_")
      && value.count == 68
      && value.utf8.dropFirst(4).allSatisfy {
        (48...57).contains($0) || (97...102).contains($0)
      }
  }
}

enum AgentEventSubscriptionIdentity {
  static func subscriptionID(
    profileID: UUID,
    event: AgentEventName,
    scope: AgentEventScope,
    callbackURL: String
  ) -> String {
    let input = [
      profileID.uuidString.lowercased(),
      event.rawValue,
      canonicalScopeValue(scope),
      callbackURL,
    ].joined(separator: "\u{0}")
    let digest = SHA256.hash(data: Data(input.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
    return "evt_\(digest)"
  }

  static func grantedTTL(_ requested: TimeInterval?) throws -> TimeInterval {
    guard let requested else { return 86_400 }
    if requested == .infinity { return 604_800 }
    guard requested.isFinite, (60.0...604_800.0).contains(requested) else {
      throw AgentEventSubscriptionError.invalidConfiguration
    }
    return requested
  }

  static func canonicalCallbackURL(_ value: String) throws -> String {
    guard
      value.utf8.count <= 2_048,
      value.unicodeScalars.allSatisfy({
        !CharacterSet.controlCharacters.contains($0)
          && !CharacterSet.whitespacesAndNewlines.contains($0)
      }),
      hasValidPercentEscapes(value),
      let components = URLComponents(string: value),
      components.scheme?.lowercased() == "https",
      let host = components.host,
      !host.isEmpty,
      components.user == nil,
      components.password == nil,
      components.fragment == nil,
      components.port.map({ (1...65_535).contains($0) }) ?? true,
      host.unicodeScalars.allSatisfy({
        !CharacterSet.controlCharacters.contains($0)
          && !CharacterSet.whitespacesAndNewlines.contains($0)
      }),
      hasValidPercentEscapes(components.percentEncodedPath),
      components.percentEncodedQuery.map(hasValidPercentEscapes) ?? true
    else {
      throw AgentEventSubscriptionError.invalidConfiguration
    }
    var canonical = components
    canonical.scheme = "https"
    canonical.host = host.lowercased()
    if canonical.port == 443 {
      canonical.port = nil
    }
    if canonical.percentEncodedPath.isEmpty {
      canonical.percentEncodedPath = "/"
    }
    guard
      let normalized = canonical.url?.absoluteString,
      normalized.utf8.count <= 2_048
    else {
      throw AgentEventSubscriptionError.invalidConfiguration
    }
    return normalized
  }

  private static func canonicalScopeValue(_ scope: AgentEventScope) -> String {
    switch scope {
    case .note(let noteID):
      "note:\(noteID.uuidString.lowercased())"
    case .folder(let folderID):
      "folder:\(folderID.uuidString.lowercased())"
    }
  }

  private static func hasValidPercentEscapes(_ value: String) -> Bool {
    let bytes = Array(value.utf8)
    var index = 0
    while index < bytes.count {
      guard bytes[index] == 0x25 else {
        index += 1
        continue
      }
      guard
        index + 2 < bytes.count,
        isHexDigit(bytes[index + 1]),
        isHexDigit(bytes[index + 2])
      else {
        return false
      }
      index += 3
    }
    return true
  }

  private static func isHexDigit(_ byte: UInt8) -> Bool {
    (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
  }
}
