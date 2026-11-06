import FleckCore
import Foundation

enum AgentEventDeliveryLedgerError: Error, Equatable, Sendable {
  case invalidInput
  case capacityExceeded
  case staleReservation
  case clockRollback
  case sourceChanged
  case storageFailure
}

enum AgentEventDeliveryLedgerRecordStatus: String, Codable, Equatable, Sendable {
  case reserved
  case retryWaiting
  case receipt
  case terminal
  case paused
  case expired
  case exhausted
  case superseded
}

enum AgentEventDeliveryLedgerFailureCategory: String, Codable, Equatable, Sendable {
  case transportFailure
  case cancelled
  case retryableHTTP
  case terminalHTTP
  case pausedHTTP
  case leaseExpired
  case retentionExpired
  case attemptsExhausted
  case bindingRefreshed
}

struct AgentEventDeliveryLedgerBindingGeneration: Codable, Equatable, Sendable {
  let binding: AgentEventCallbackVerificationBinding
  let generationID: String
  let pendingReservationGenerationID: String?

  init(
    binding: AgentEventCallbackVerificationBinding,
    generationID: String,
    pendingReservationGenerationID: String? = nil
  ) {
    self.binding = binding
    self.generationID = generationID
    self.pendingReservationGenerationID = pendingReservationGenerationID
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: AgentEventDeliveryLedgerCodingKey.self)
    try requireLedgerKeys(container, ["binding", "generationID", "pendingReservationGenerationID"])
    binding = try container.decode(
      AgentEventCallbackVerificationBinding.self,
      forKey: AgentEventDeliveryLedgerCodingKey("binding")
    )
    generationID = try container.decode(
      String.self,
      forKey: AgentEventDeliveryLedgerCodingKey("generationID")
    )
    pendingReservationGenerationID = try container.decodeIfPresent(
      String.self,
      forKey: AgentEventDeliveryLedgerCodingKey("pendingReservationGenerationID")
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: AgentEventDeliveryLedgerCodingKey.self)
    try container.encode(binding, forKey: AgentEventDeliveryLedgerCodingKey("binding"))
    try container.encode(generationID, forKey: AgentEventDeliveryLedgerCodingKey("generationID"))
    try container.encode(
      pendingReservationGenerationID,
      forKey: AgentEventDeliveryLedgerCodingKey("pendingReservationGenerationID")
    )
  }
}

struct AgentEventDeliveryLedgerRecord: Codable, Equatable, Sendable {
  let binding: AgentEventCallbackVerificationBinding
  let bindingGenerationID: String
  let eventID: String
  let sourcePosition: AgentEventOutboxPosition
  let expiresAt: Date
  var attemptCount: UInt64
  var status: AgentEventDeliveryLedgerRecordStatus
  var reservationID: String?
  var leaseDeadline: Date?
  var nextEligibleAt: Date?
  var httpStatus: Int?
  var failureCategory: AgentEventDeliveryLedgerFailureCategory?
  var receiptAt: Date?

  init(
    binding: AgentEventCallbackVerificationBinding,
    bindingGenerationID: String,
    eventID: String,
    sourcePosition: AgentEventOutboxPosition,
    expiresAt: Date,
    attemptCount: UInt64,
    status: AgentEventDeliveryLedgerRecordStatus,
    reservationID: String?,
    leaseDeadline: Date?,
    nextEligibleAt: Date?,
    httpStatus: Int?,
    failureCategory: AgentEventDeliveryLedgerFailureCategory?,
    receiptAt: Date? = nil
  ) {
    self.binding = binding
    self.bindingGenerationID = bindingGenerationID
    self.eventID = eventID
    self.sourcePosition = sourcePosition
    self.expiresAt = expiresAt
    self.attemptCount = attemptCount
    self.status = status
    self.reservationID = reservationID
    self.leaseDeadline = leaseDeadline
    self.nextEligibleAt = nextEligibleAt
    self.httpStatus = httpStatus
    self.failureCategory = failureCategory
    self.receiptAt = receiptAt
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: AgentEventDeliveryLedgerCodingKey.self)
    try requireLedgerKeys(
      container,
      [
        "binding", "bindingGenerationID", "eventID", "sourcePosition", "expiresAt", "attemptCount",
        "status",
        "reservationID", "leaseDeadline", "nextEligibleAt", "httpStatus", "failureCategory",
      ],
      optional: ["receiptAt"]
    )
    binding = try container.decode(
      AgentEventCallbackVerificationBinding.self,
      forKey: AgentEventDeliveryLedgerCodingKey("binding")
    )
    bindingGenerationID = try container.decode(
      String.self,
      forKey: AgentEventDeliveryLedgerCodingKey("bindingGenerationID")
    )
    eventID = try container.decode(
      String.self, forKey: AgentEventDeliveryLedgerCodingKey("eventID"))
    sourcePosition = try container.decode(
      AgentEventOutboxPosition.self,
      forKey: AgentEventDeliveryLedgerCodingKey("sourcePosition")
    )
    expiresAt = try container.decode(
      Date.self, forKey: AgentEventDeliveryLedgerCodingKey("expiresAt"))
    attemptCount = try container.decode(
      UInt64.self,
      forKey: AgentEventDeliveryLedgerCodingKey("attemptCount")
    )
    status = try container.decode(
      AgentEventDeliveryLedgerRecordStatus.self,
      forKey: AgentEventDeliveryLedgerCodingKey("status")
    )
    reservationID = try container.decodeIfPresent(
      String.self,
      forKey: AgentEventDeliveryLedgerCodingKey("reservationID")
    )
    leaseDeadline = try container.decodeIfPresent(
      Date.self,
      forKey: AgentEventDeliveryLedgerCodingKey("leaseDeadline")
    )
    nextEligibleAt = try container.decodeIfPresent(
      Date.self,
      forKey: AgentEventDeliveryLedgerCodingKey("nextEligibleAt")
    )
    httpStatus = try container.decodeIfPresent(
      Int.self,
      forKey: AgentEventDeliveryLedgerCodingKey("httpStatus")
    )
    failureCategory = try container.decodeIfPresent(
      AgentEventDeliveryLedgerFailureCategory.self,
      forKey: AgentEventDeliveryLedgerCodingKey("failureCategory")
    )
    receiptAt = try container.decodeIfPresent(
      Date.self,
      forKey: AgentEventDeliveryLedgerCodingKey("receiptAt")
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: AgentEventDeliveryLedgerCodingKey.self)
    try container.encode(binding, forKey: AgentEventDeliveryLedgerCodingKey("binding"))
    try container.encode(
      bindingGenerationID,
      forKey: AgentEventDeliveryLedgerCodingKey("bindingGenerationID")
    )
    try container.encode(eventID, forKey: AgentEventDeliveryLedgerCodingKey("eventID"))
    try container.encode(
      sourcePosition, forKey: AgentEventDeliveryLedgerCodingKey("sourcePosition"))
    try container.encode(expiresAt, forKey: AgentEventDeliveryLedgerCodingKey("expiresAt"))
    try container.encode(attemptCount, forKey: AgentEventDeliveryLedgerCodingKey("attemptCount"))
    try container.encode(status, forKey: AgentEventDeliveryLedgerCodingKey("status"))
    try container.encode(reservationID, forKey: AgentEventDeliveryLedgerCodingKey("reservationID"))
    try container.encode(leaseDeadline, forKey: AgentEventDeliveryLedgerCodingKey("leaseDeadline"))
    try container.encode(
      nextEligibleAt, forKey: AgentEventDeliveryLedgerCodingKey("nextEligibleAt"))
    try container.encode(httpStatus, forKey: AgentEventDeliveryLedgerCodingKey("httpStatus"))
    try container.encode(
      failureCategory,
      forKey: AgentEventDeliveryLedgerCodingKey("failureCategory")
    )
    try container.encodeIfPresent(
      receiptAt,
      forKey: AgentEventDeliveryLedgerCodingKey("receiptAt")
    )
  }
}

struct AgentEventDeliveryLedgerDocument: Codable, Equatable, Sendable {
  let schemaVersion: Int
  var records: [AgentEventDeliveryLedgerRecord]
  var bindingGenerations: [AgentEventDeliveryLedgerBindingGeneration]
  var lastObservedAt: Date

  init(
    schemaVersion: Int = 2,
    records: [AgentEventDeliveryLedgerRecord],
    bindingGenerations: [AgentEventDeliveryLedgerBindingGeneration],
    lastObservedAt: Date
  ) {
    self.schemaVersion = schemaVersion
    self.records = records.sorted(by: Self.recordOrder)
    self.bindingGenerations = bindingGenerations.sorted(by: Self.bindingGenerationOrder)
    self.lastObservedAt = lastObservedAt
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: AgentEventDeliveryLedgerCodingKey.self)
    try requireLedgerKeys(
      container, ["schemaVersion", "records", "bindingGenerations", "lastObservedAt"])
    schemaVersion = try container.decode(
      Int.self,
      forKey: AgentEventDeliveryLedgerCodingKey("schemaVersion")
    )
    records = try container.decode(
      [AgentEventDeliveryLedgerRecord].self,
      forKey: AgentEventDeliveryLedgerCodingKey("records")
    )
    bindingGenerations = try container.decode(
      [AgentEventDeliveryLedgerBindingGeneration].self,
      forKey: AgentEventDeliveryLedgerCodingKey("bindingGenerations")
    )
    lastObservedAt = try container.decode(
      Date.self,
      forKey: AgentEventDeliveryLedgerCodingKey("lastObservedAt")
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: AgentEventDeliveryLedgerCodingKey.self)
    try container.encode(schemaVersion, forKey: AgentEventDeliveryLedgerCodingKey("schemaVersion"))
    try container.encode(records, forKey: AgentEventDeliveryLedgerCodingKey("records"))
    try container.encode(
      bindingGenerations,
      forKey: AgentEventDeliveryLedgerCodingKey("bindingGenerations")
    )
    try container.encode(
      lastObservedAt, forKey: AgentEventDeliveryLedgerCodingKey("lastObservedAt"))
  }

  static func recordOrder(
    _ left: AgentEventDeliveryLedgerRecord,
    _ right: AgentEventDeliveryLedgerRecord
  ) -> Bool {
    let leftBinding = left.binding
    let rightBinding = right.binding
    if leftBinding.profileID != rightBinding.profileID {
      return leftBinding.profileID.uuidString.lowercased()
        < rightBinding.profileID.uuidString.lowercased()
    }
    if leftBinding.subscriptionID != rightBinding.subscriptionID {
      return leftBinding.subscriptionID < rightBinding.subscriptionID
    }
    if leftBinding.subscriptionRevision != rightBinding.subscriptionRevision {
      return leftBinding.subscriptionRevision < rightBinding.subscriptionRevision
    }
    if leftBinding.grantRevision != rightBinding.grantRevision {
      return leftBinding.grantRevision < rightBinding.grantRevision
    }
    if leftBinding.signingKeyReference != rightBinding.signingKeyReference {
      return leftBinding.signingKeyReference < rightBinding.signingKeyReference
    }
    if left.bindingGenerationID != right.bindingGenerationID {
      return left.bindingGenerationID < right.bindingGenerationID
    }
    if left.sourcePosition.epoch != right.sourcePosition.epoch {
      return left.sourcePosition.epoch.uuidString.lowercased()
        < right.sourcePosition.epoch.uuidString.lowercased()
    }
    if left.sourcePosition.sequence != right.sourcePosition.sequence {
      return left.sourcePosition.sequence < right.sourcePosition.sequence
    }
    return left.eventID < right.eventID
  }

  static func bindingGenerationOrder(
    _ left: AgentEventDeliveryLedgerBindingGeneration,
    _ right: AgentEventDeliveryLedgerBindingGeneration
  ) -> Bool {
    let leftBinding = left.binding
    let rightBinding = right.binding
    if leftBinding.profileID != rightBinding.profileID {
      return leftBinding.profileID.uuidString.lowercased()
        < rightBinding.profileID.uuidString.lowercased()
    }
    return leftBinding.subscriptionID < rightBinding.subscriptionID
  }
}

struct AgentEventDeliveryLedgerCandidate: Equatable, Sendable {
  let binding: AgentEventCallbackVerificationBinding
  let eventID: String
  let sourcePosition: AgentEventOutboxPosition
  let eventTimestamp: Date
  let subscriptionExpiresAt: Date

  init(
    binding: AgentEventCallbackVerificationBinding,
    eventID: String,
    sourcePosition: AgentEventOutboxPosition,
    eventTimestamp: Date,
    subscriptionExpiresAt: Date
  ) {
    self.binding = binding
    self.eventID = eventID
    self.sourcePosition = sourcePosition
    self.eventTimestamp = eventTimestamp
    self.subscriptionExpiresAt = subscriptionExpiresAt
  }

  var expiresAt: Date? {
    guard
      AgentEventDeliveryLedgerStore.isValidDate(eventTimestamp),
      AgentEventDeliveryLedgerStore.isValidDate(subscriptionExpiresAt)
    else {
      return nil
    }
    let eventExpiry = eventTimestamp.addingTimeInterval(
      AgentEventDeliveryLedgerStore.maximumRetention
    )
    guard
      AgentEventDeliveryLedgerStore.isValidDate(eventExpiry),
      eventExpiry > eventTimestamp
    else {
      return nil
    }
    return min(eventExpiry, subscriptionExpiresAt)
  }
}

struct AgentEventDeliveryLedgerReservation: Equatable, Sendable {
  let id: UUID
  let binding: AgentEventCallbackVerificationBinding
  let bindingGenerationID: String
  let eventID: String
  let sourcePosition: AgentEventOutboxPosition
  let expiresAt: Date
  let attemptCount: UInt64
  let leaseDeadline: Date
}

struct AgentEventDeliveryAttempt: Equatable, Sendable {
  let reservation: AgentEventDeliveryLedgerReservation
  let body: Data
}

enum AgentEventDeliveryLedgerOutcome: Equatable, Sendable {
  case transportFailure
  case cancelled
  case httpStatus(Int, retryAfter: TimeInterval?)
}

enum AgentEventDeliveryLedgerReservationDecision: Equatable, Sendable {
  case reserved(AgentEventDeliveryLedgerReservation)
  case skipped
  case blocked
}

final class AgentEventDeliveryLedgerStore: @unchecked Sendable {
  private struct State: Equatable {
    var records: [AgentEventDeliveryLedgerRecord]
    var bindingGenerations: [AgentEventDeliveryLedgerBindingGeneration]
    var lastObservedAt: Date
  }

  private enum Settlement {
    case retry(AgentEventDeliveryLedgerFailureCategory, httpStatus: Int?, retryAfter: TimeInterval?)
    case receipt(Int)
    case terminal(Int)
    case pause(Int)
  }

  private static let stateLock = NSLock()
  private static let maximumFileSize = 8 * 1_048_576
  private static let maximumBindings = 128
  private static let maximumRecordsPerSubscription = 256
  private static let maximumRecordsPerProfile = 512
  private static let maximumRecordsTotal = 4_096
  private static let maximumAttempts: UInt64 = 12
  private static let maximumLease: TimeInterval = 30
  private static let maximumRetryDelay: TimeInterval = 900
  private static let maximumRetryAfter: TimeInterval = 900
  private static let initialRetryDelay: TimeInterval = 5
  static let maximumRetention: TimeInterval = 7 * 24 * 60 * 60

  let fileURL: URL
  private let clock: @Sendable () -> Date
  private let jitterBasisPoints: @Sendable () -> UInt64
  private let fileWriter: @Sendable (Data, URL) throws -> Void

  init(
    fileURL: URL? = nil,
    now: @escaping @Sendable () -> Date = { Date() },
    jitterBasisPoints: @escaping @Sendable () -> UInt64 = {
      UInt64.random(in: 0...2_000)
    },
    fileWriter: @escaping @Sendable (Data, URL) throws -> Void = {
      try $0.write(to: $1, options: .atomic)
    }
  ) {
    self.fileURL = fileURL ?? Self.defaultFileURL()
    clock = now
    self.jitterBasisPoints = jitterBasisPoints
    self.fileWriter = fileWriter
  }

  func currentBindingGeneration(
    profileID: UUID,
    subscriptionID: String
  ) throws -> AgentEventDeliveryLedgerBindingGeneration? {
    try Self.stateLock.withLock {
      generation(
        profileID: profileID,
        subscriptionID: subscriptionID,
        state: try loadState()
      )
    }
  }

  func records(
    for binding: AgentEventCallbackVerificationBinding
  ) throws -> [AgentEventDeliveryLedgerRecord] {
    try Self.stateLock.withLock {
      try loadState().records.filter { $0.binding == binding }
    }
  }

  func lastReceiptAt(profileID: UUID, subscriptionID: String) throws -> Date? {
    try Self.stateLock.withLock {
      try loadState().records
        .filter {
          $0.binding.profileID == profileID
            && $0.binding.subscriptionID == subscriptionID
            && $0.status == .receipt
        }
        .compactMap(\.receiptAt)
        .max()
    }
  }

  func reconcileAndReserve(
    candidates: [AgentEventDeliveryLedgerCandidate],
    validatedBinding: AgentEventCallbackVerificationBinding,
    expectedGeneration: AgentEventDeliveryLedgerBindingGeneration?
  ) throws -> AgentEventDeliveryLedgerReservationDecision {
    guard Self.isValid(validatedBinding),
      candidates.allSatisfy({ Self.isValid($0) && $0.binding == validatedBinding })
    else {
      throw AgentEventDeliveryLedgerError.invalidInput
    }
    return try Self.stateLock.withLock {
      let now = clock()
      guard Self.isValidDate(now) else {
        throw AgentEventDeliveryLedgerError.invalidInput
      }
      let original = try loadState()
      guard now >= original.lastObservedAt else {
        throw AgentEventDeliveryLedgerError.clockRollback
      }
      guard
        generation(
          profileID: validatedBinding.profileID,
          subscriptionID: validatedBinding.subscriptionID,
          state: original
        ) == expectedGeneration
      else {
        throw AgentEventDeliveryLedgerError.sourceChanged
      }

      var state = original
      state.lastObservedAt = now
      let currentGeneration: AgentEventDeliveryLedgerBindingGeneration
      if let expectedGeneration, expectedGeneration.binding == validatedBinding {
        currentGeneration = expectedGeneration
        try recoverCurrentGeneration(currentGeneration, now: now, state: &state)
      } else {
        let pendingGenerationID =
          expectedGeneration.map {
            retirePriorGeneration($0, now: now, state: &state)
          } ?? nil
        let nextGeneration = AgentEventDeliveryLedgerBindingGeneration(
          binding: validatedBinding,
          generationID: UUID().uuidString.lowercased(),
          pendingReservationGenerationID: pendingGenerationID
        )
        if expectedGeneration == nil,
          state.bindingGenerations.count >= Self.maximumBindings
        {
          throw AgentEventDeliveryLedgerError.capacityExceeded
        }
        replaceGeneration(nextGeneration, profileID: validatedBinding.profileID, state: &state)
        guard
          Set(
            state.records.map(Self.recordBindingKey)
              + state.bindingGenerations.map { Self.bindingKey($0.binding) }
          ).count
            <= Self.maximumBindings
        else {
          throw AgentEventDeliveryLedgerError.capacityExceeded
        }
        currentGeneration = nextGeneration
      }

      let decision = try reserve(
        candidates,
        generation: currentGeneration,
        now: now,
        state: &state
      )
      if decision == .skipped || decision == .blocked,
        state.records == original.records,
        state.bindingGenerations == original.bindingGenerations
      {
        state.lastObservedAt = original.lastObservedAt
      }
      try saveIfChanged(state, from: original)
      return decision
    }
  }

  func observe(
    _ reservation: AgentEventDeliveryLedgerReservation,
    expectedGeneration: AgentEventDeliveryLedgerBindingGeneration
  ) throws {
    try Self.stateLock.withLock {
      let now = clock()
      guard Self.isValidDate(now) else {
        throw AgentEventDeliveryLedgerError.invalidInput
      }
      let original = try loadState()
      guard now >= original.lastObservedAt else {
        throw AgentEventDeliveryLedgerError.clockRollback
      }
      guard
        generation(
          profileID: reservation.binding.profileID,
          subscriptionID: reservation.binding.subscriptionID,
          state: original
        ) == expectedGeneration,
        expectedGeneration.generationID == reservation.bindingGenerationID,
        expectedGeneration.binding == reservation.binding
      else {
        throw AgentEventDeliveryLedgerError.staleReservation
      }
      var state = original
      state.lastObservedAt = now
      guard let index = matchingReservation(reservation, state: state) else {
        throw AgentEventDeliveryLedgerError.staleReservation
      }
      guard
        let deadline = state.records[index].leaseDeadline,
        now < deadline,
        now < state.records[index].expiresAt
      else {
        try recoverExpiredReservation(at: index, now: now, state: &state)
        try saveIfChanged(state, from: original)
        throw AgentEventDeliveryLedgerError.staleReservation
      }
      try saveIfChanged(state, from: original)
    }
  }

  func settle(
    _ reservation: AgentEventDeliveryLedgerReservation,
    outcome: AgentEventDeliveryLedgerOutcome,
    expectedGeneration: AgentEventDeliveryLedgerBindingGeneration
  ) throws -> AgentEventDeliveryLedgerRecord {
    let settlement = try Self.classify(outcome)
    return try Self.stateLock.withLock {
      let now = clock()
      guard Self.isValidDate(now) else {
        throw AgentEventDeliveryLedgerError.invalidInput
      }
      let original = try loadState()
      guard now >= original.lastObservedAt else {
        throw AgentEventDeliveryLedgerError.clockRollback
      }
      guard
        generation(
          profileID: reservation.binding.profileID,
          subscriptionID: reservation.binding.subscriptionID,
          state: original
        ) == expectedGeneration,
        expectedGeneration.generationID == reservation.bindingGenerationID,
        expectedGeneration.binding == reservation.binding
      else {
        throw AgentEventDeliveryLedgerError.staleReservation
      }
      var state = original
      state.lastObservedAt = now
      guard let index = matchingReservation(reservation, state: state) else {
        throw AgentEventDeliveryLedgerError.staleReservation
      }
      guard
        let deadline = state.records[index].leaseDeadline,
        now < deadline,
        now < state.records[index].expiresAt
      else {
        try recoverExpiredReservation(at: index, now: now, state: &state)
        try saveIfChanged(state, from: original)
        throw AgentEventDeliveryLedgerError.staleReservation
      }
      try apply(settlement, at: index, now: now, state: &state)
      try saveIfChanged(state, from: original)
      return state.records[index]
    }
  }

  func cancel(
    _ reservation: AgentEventDeliveryLedgerReservation,
    expectedGeneration: AgentEventDeliveryLedgerBindingGeneration
  ) throws -> AgentEventDeliveryLedgerRecord {
    try settle(
      reservation,
      outcome: .cancelled,
      expectedGeneration: expectedGeneration
    )
  }

  private func generation(
    profileID: UUID,
    subscriptionID: String,
    state: State
  ) -> AgentEventDeliveryLedgerBindingGeneration? {
    state.bindingGenerations.first {
      Self.sameSubscription(
        $0.binding,
        profileID: profileID,
        subscriptionID: subscriptionID
      )
    }
  }

  private func replaceGeneration(
    _ generation: AgentEventDeliveryLedgerBindingGeneration,
    profileID: UUID,
    state: inout State
  ) {
    state.bindingGenerations.removeAll {
      Self.sameSubscription(
        $0.binding,
        profileID: profileID,
        subscriptionID: generation.binding.subscriptionID
      )
    }
    state.bindingGenerations.append(generation)
    state.bindingGenerations.sort(by: AgentEventDeliveryLedgerDocument.bindingGenerationOrder)
  }

  private func reserve(
    _ candidates: [AgentEventDeliveryLedgerCandidate],
    generation: AgentEventDeliveryLedgerBindingGeneration,
    now: Date,
    state: inout State
  ) throws -> AgentEventDeliveryLedgerReservationDecision {
    for candidate in candidates {
      let decision = try reserve(candidate, generation: generation, now: now, state: &state)
      if decision != .skipped { return decision }
    }
    return .skipped
  }

  private func reserve(
    _ candidate: AgentEventDeliveryLedgerCandidate,
    generation: AgentEventDeliveryLedgerBindingGeneration,
    now: Date,
    state: inout State
  ) throws -> AgentEventDeliveryLedgerReservationDecision {
    guard generation.binding == candidate.binding,
      let candidateExpiresAt = candidate.expiresAt
    else {
      throw AgentEventDeliveryLedgerError.invalidInput
    }
    let binding = candidate.binding
    if state.records.contains(where: {
      Self.sameSubscription(
        $0.binding,
        profileID: binding.profileID,
        subscriptionID: binding.subscriptionID
      ) && $0.status == .reserved && ($0.leaseDeadline ?? .distantPast) > now
    }) {
      return .blocked
    }
    let activeReservations = state.records.filter {
      $0.status == .reserved && ($0.leaseDeadline ?? .distantPast) > now
    }.count
    guard activeReservations < 4 else { return .blocked }

    if let index = state.records.firstIndex(where: {
      Self.sameIdentity(
        $0,
        candidate: candidate,
        generationID: generation.generationID,
        expiresAt: candidateExpiresAt
      )
    }) {
      var record = state.records[index]
      switch record.status {
      case .receipt, .terminal, .expired, .exhausted, .superseded:
        return .skipped
      case .paused:
        return .blocked
      case .reserved:
        if let deadline = record.leaseDeadline, deadline > now { return .blocked }
        try recoverExpiredReservation(at: index, now: now, state: &state)
        return .blocked
      case .retryWaiting:
        guard let nextEligibleAt = record.nextEligibleAt else {
          throw AgentEventDeliveryLedgerError.storageFailure
        }
        if now >= record.expiresAt {
          expire(at: index, state: &state)
          return .skipped
        }
        guard now >= nextEligibleAt else { return .blocked }
        guard record.attemptCount < Self.maximumAttempts else {
          exhaust(at: index, state: &state, httpStatus: record.httpStatus)
          return .skipped
        }
        let (nextAttempt, overflow) = record.attemptCount.addingReportingOverflow(1)
        guard !overflow, nextAttempt <= Self.maximumAttempts else {
          throw AgentEventDeliveryLedgerError.storageFailure
        }
        let deadline = try Self.leaseDeadline(now: now, expiresAt: record.expiresAt)
        record.attemptCount = nextAttempt
        record.status = .reserved
        record.reservationID = UUID().uuidString.lowercased()
        record.leaseDeadline = deadline
        record.nextEligibleAt = nil
        record.httpStatus = nil
        record.failureCategory = nil
        state.records[index] = record
        return .reserved(try reservation(record))
      }
    }

    guard now < candidateExpiresAt else { return .skipped }
    guard
      !state.records.contains(where: {
        Self.sameBindingEvent(
          $0,
          candidate: candidate,
          generationID: generation.generationID
        )
          || Self.sameBindingPosition(
            $0,
            candidate: candidate,
            generationID: generation.generationID
          )
      })
    else {
      throw AgentEventDeliveryLedgerError.sourceChanged
    }
    try Self.checkCapacity(
      for: candidate,
      generations: state.bindingGenerations,
      records: state.records
    )
    let deadline = try Self.leaseDeadline(now: now, expiresAt: candidateExpiresAt)
    let record = AgentEventDeliveryLedgerRecord(
      binding: candidate.binding,
      bindingGenerationID: generation.generationID,
      eventID: candidate.eventID,
      sourcePosition: candidate.sourcePosition,
      expiresAt: candidateExpiresAt,
      attemptCount: 1,
      status: .reserved,
      reservationID: UUID().uuidString.lowercased(),
      leaseDeadline: deadline,
      nextEligibleAt: nil,
      httpStatus: nil,
      failureCategory: nil
    )
    state.records.append(record)
    state.records.sort(by: AgentEventDeliveryLedgerDocument.recordOrder)
    return .reserved(try reservation(record))
  }

  private func apply(
    _ settlement: Settlement,
    at index: Int,
    now: Date,
    state: inout State
  ) throws {
    var record = state.records[index]
    switch settlement {
    case .receipt(let status):
      record.status = .receipt
      record.reservationID = nil
      record.leaseDeadline = nil
      record.nextEligibleAt = nil
      record.httpStatus = status
      record.failureCategory = nil
      record.receiptAt = now
    case .terminal(let status):
      record.status = .terminal
      record.reservationID = nil
      record.leaseDeadline = nil
      record.nextEligibleAt = nil
      record.httpStatus = status
      record.failureCategory = .terminalHTTP
    case .pause(let status):
      record.status = .paused
      record.reservationID = nil
      record.leaseDeadline = nil
      record.nextEligibleAt = nil
      record.httpStatus = status
      record.failureCategory = .pausedHTTP
    case .retry(let category, let httpStatus, let retryAfter):
      try scheduleRetry(
        &record,
        at: now,
        category: category,
        httpStatus: httpStatus,
        retryAfter: retryAfter
      )
    }
    state.records[index] = record
  }

  private func recoverCurrentGeneration(
    _ generation: AgentEventDeliveryLedgerBindingGeneration,
    now: Date,
    state: inout State
  ) throws {
    let pendingGenerationID = cleanupPendingGeneration(generation, now: now, state: &state)
    if pendingGenerationID != generation.pendingReservationGenerationID {
      replaceGeneration(
        AgentEventDeliveryLedgerBindingGeneration(
          binding: generation.binding,
          generationID: generation.generationID,
          pendingReservationGenerationID: pendingGenerationID
        ),
        profileID: generation.binding.profileID,
        state: &state
      )
    }
    for index in state.records.indices
    where state.records[index].bindingGenerationID == generation.generationID {
      if state.records[index].status == .reserved,
        (state.records[index].leaseDeadline ?? .distantPast) <= now
      {
        try recoverExpiredReservation(at: index, now: now, state: &state)
      } else if state.records[index].status == .retryWaiting,
        now >= state.records[index].expiresAt
      {
        expire(at: index, state: &state)
      }
    }
  }

  private func retirePriorGeneration(
    _ generation: AgentEventDeliveryLedgerBindingGeneration,
    now: Date,
    state: inout State
  ) -> String? {
    var pendingGenerationID = cleanupPendingGeneration(generation, now: now, state: &state)
    var hasLiveReservation = false
    for index in state.records.indices
    where state.records[index].bindingGenerationID == generation.generationID {
      switch state.records[index].status {
      case .reserved:
        if let deadline = state.records[index].leaseDeadline, deadline > now {
          hasLiveReservation = true
        } else {
          supersede(at: index, state: &state)
        }
      case .retryWaiting, .paused:
        supersede(at: index, state: &state)
      case .receipt, .terminal, .expired, .exhausted, .superseded:
        break
      }
    }
    if hasLiveReservation {
      pendingGenerationID = generation.generationID
    }
    return pendingGenerationID
  }

  private func cleanupPendingGeneration(
    _ generation: AgentEventDeliveryLedgerBindingGeneration,
    now: Date,
    state: inout State
  ) -> String? {
    guard let pendingGenerationID = generation.pendingReservationGenerationID else { return nil }
    var hasLiveReservation = false
    for index in state.records.indices
    where state.records[index].bindingGenerationID == pendingGenerationID
      && Self.sameSubscription(
        state.records[index].binding,
        profileID: generation.binding.profileID,
        subscriptionID: generation.binding.subscriptionID
      )
    {
      guard state.records[index].status == .reserved else { continue }
      if (state.records[index].leaseDeadline ?? .distantPast) > now {
        hasLiveReservation = true
      } else {
        supersede(at: index, state: &state)
      }
    }
    return hasLiveReservation ? pendingGenerationID : nil
  }

  private func recoverExpiredReservation(
    at index: Int,
    now: Date,
    state: inout State
  ) throws {
    var record = state.records[index]
    guard record.status == .reserved, (record.leaseDeadline ?? .distantPast) <= now else {
      return
    }
    guard now < record.expiresAt else {
      expire(at: index, state: &state)
      return
    }
    guard record.attemptCount < Self.maximumAttempts else {
      exhaust(at: index, state: &state, httpStatus: nil)
      return
    }
    try scheduleRetry(
      &record,
      at: now,
      category: .leaseExpired,
      httpStatus: nil,
      retryAfter: nil
    )
    state.records[index] = record
  }

  private func scheduleRetry(
    _ record: inout AgentEventDeliveryLedgerRecord,
    at now: Date,
    category: AgentEventDeliveryLedgerFailureCategory,
    httpStatus: Int?,
    retryAfter: TimeInterval?
  ) throws {
    guard record.attemptCount < Self.maximumAttempts else {
      record.status = .exhausted
      record.reservationID = nil
      record.leaseDeadline = nil
      record.nextEligibleAt = nil
      record.httpStatus = httpStatus
      record.failureCategory = .attemptsExhausted
      return
    }
    let jitter = jitterBasisPoints()
    guard jitter <= 2_000 else { throw AgentEventDeliveryLedgerError.invalidInput }
    let retryDelay = Self.retryDelay(
      attempt: record.attemptCount,
      jitterBasisPoints: jitter,
      retryAfter: retryAfter
    )
    let nextEligibleAt = now.addingTimeInterval(retryDelay.delay)
    guard Self.isValidDate(nextEligibleAt), nextEligibleAt > now else {
      throw AgentEventDeliveryLedgerError.invalidInput
    }
    if nextEligibleAt >= record.expiresAt {
      record.status = .expired
      record.reservationID = nil
      record.leaseDeadline = nil
      record.nextEligibleAt = nil
      record.httpStatus = nil
      record.failureCategory = .retentionExpired
      return
    }
    let actualDelay = nextEligibleAt.timeIntervalSince(now)
    guard
      actualDelay.isFinite,
      actualDelay >= retryDelay.minimum,
      actualDelay <= Self.maximumRetryDelay
    else {
      throw AgentEventDeliveryLedgerError.invalidInput
    }
    record.reservationID = nil
    record.leaseDeadline = nil
    record.status = .retryWaiting
    record.nextEligibleAt = nextEligibleAt
    record.httpStatus = httpStatus
    record.failureCategory = category
  }

  private func supersede(at index: Int, state: inout State) {
    var record = state.records[index]
    record.status = .superseded
    record.reservationID = nil
    record.leaseDeadline = nil
    record.nextEligibleAt = nil
    record.httpStatus = nil
    record.failureCategory = .bindingRefreshed
    state.records[index] = record
  }

  private func expire(at index: Int, state: inout State) {
    var record = state.records[index]
    record.status = .expired
    record.reservationID = nil
    record.leaseDeadline = nil
    record.nextEligibleAt = nil
    record.httpStatus = nil
    record.failureCategory = .retentionExpired
    state.records[index] = record
  }

  private func exhaust(
    at index: Int,
    state: inout State,
    httpStatus: Int?
  ) {
    var record = state.records[index]
    record.status = .exhausted
    record.reservationID = nil
    record.leaseDeadline = nil
    record.nextEligibleAt = nil
    record.httpStatus = httpStatus
    record.failureCategory = .attemptsExhausted
    state.records[index] = record
  }

  private func matchingReservation(
    _ reservation: AgentEventDeliveryLedgerReservation,
    state: State
  ) -> Int? {
    state.records.firstIndex { record in
      record.binding == reservation.binding
        && record.bindingGenerationID == reservation.bindingGenerationID
        && record.eventID == reservation.eventID
        && record.sourcePosition == reservation.sourcePosition
        && record.expiresAt == reservation.expiresAt
        && record.attemptCount == reservation.attemptCount
        && record.reservationID == reservation.id.uuidString.lowercased()
        && record.status == .reserved
    }
  }

  private func reservation(
    _ record: AgentEventDeliveryLedgerRecord
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

  private func saveIfChanged(_ state: State, from previous: State) throws {
    guard state != previous else { return }
    try saveState(state)
  }

  private func saveState(_ state: State) throws {
    let ordered = state.records.sorted(by: AgentEventDeliveryLedgerDocument.recordOrder)
    let document = AgentEventDeliveryLedgerDocument(
      records: ordered,
      bindingGenerations: state.bindingGenerations,
      lastObservedAt: state.lastObservedAt
    )
    try Self.validate(document)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data: Data
    do {
      data = try encoder.encode(document)
    } catch {
      throw AgentEventDeliveryLedgerError.storageFailure
    }
    guard data.count <= Self.maximumFileSize else {
      throw AgentEventDeliveryLedgerError.capacityExceeded
    }
    do {
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
        let persistedData = Self.readPersistedData(
          at: fileURL,
          maximumFileSize: Self.maximumFileSize
        )
        guard persistedData == data else {
          throw AgentEventDeliveryLedgerError.storageFailure
        }
      }
    } catch let error as AgentEventDeliveryLedgerError {
      throw error
    } catch {
      throw AgentEventDeliveryLedgerError.storageFailure
    }
  }

  private func loadState() throws -> State {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return State(records: [], bindingGenerations: [], lastObservedAt: .distantPast)
    }
    guard let data = Self.readPersistedData(at: fileURL, maximumFileSize: Self.maximumFileSize)
    else {
      throw AgentEventDeliveryLedgerError.storageFailure
    }
    do {
      let document = try JSONDecoder().decode(AgentEventDeliveryLedgerDocument.self, from: data)
      try Self.validate(document)
      guard
        document.records
          == document.records.sorted(by: AgentEventDeliveryLedgerDocument.recordOrder)
          && document.bindingGenerations
            == document.bindingGenerations.sorted(
              by: AgentEventDeliveryLedgerDocument.bindingGenerationOrder)
      else {
        throw AgentEventDeliveryLedgerError.storageFailure
      }
      return State(
        records: document.records,
        bindingGenerations: document.bindingGenerations,
        lastObservedAt: document.lastObservedAt
      )
    } catch let error as AgentEventDeliveryLedgerError {
      throw error
    } catch {
      throw AgentEventDeliveryLedgerError.storageFailure
    }
  }

  private static func validate(_ document: AgentEventDeliveryLedgerDocument) throws {
    guard
      document.schemaVersion == 2,
      isValidDate(document.lastObservedAt),
      document.records.count <= maximumRecordsTotal,
      document.records == document.records.sorted(by: AgentEventDeliveryLedgerDocument.recordOrder),
      document.bindingGenerations.count <= maximumBindings,
      document.bindingGenerations
        == document.bindingGenerations.sorted(
          by: AgentEventDeliveryLedgerDocument.bindingGenerationOrder)
    else {
      throw AgentEventDeliveryLedgerError.storageFailure
    }
    let records = document.records
    let generations = document.bindingGenerations
    let reservationIDs = records.compactMap(\.reservationID)
    let generationIDs = generations.map(\.generationID)
    var generationOwners: [(id: String, subscriptionKey: String)] = []
    for generation in generations {
      let subscriptionKey = generationSubscriptionKey(generation)
      generationOwners.append((generation.generationID, subscriptionKey))
      if let pendingID = generation.pendingReservationGenerationID {
        generationOwners.append((pendingID, subscriptionKey))
      }
    }
    generationOwners.append(
      contentsOf: records.map {
        ($0.bindingGenerationID, recordSubscriptionKey($0))
      })
    let generationOwnersAreUnique = Dictionary(
      grouping: generationOwners,
      by: { $0.id }
    ).values.allSatisfy { owners in
      guard let subscriptionKey = owners.first?.subscriptionKey else { return false }
      return owners.allSatisfy { $0.subscriptionKey == subscriptionKey }
    }
    let generationBindingsAreConsistent = Dictionary(
      grouping: generations.map { ($0.generationID, $0.binding) }
        + records.map { ($0.bindingGenerationID, $0.binding) },
      by: { $0.0 }
    ).values.allSatisfy { bindings in
      guard let binding = bindings.first?.1 else { return false }
      return bindings.allSatisfy { $0.1 == binding }
    }
    let currentGenerationBySubscription = Dictionary(
      generations.map { (generationSubscriptionKey($0), $0) },
      uniquingKeysWith: { first, _ in first }
    )
    let activeRecordOwnershipIsValid = records.allSatisfy { record in
      switch record.status {
      case .reserved:
        guard let deadline = record.leaseDeadline,
          deadline > document.lastObservedAt
        else {
          return true
        }
        guard let generation = currentGenerationBySubscription[recordSubscriptionKey(record)]
        else {
          return false
        }
        return
          (generation.generationID == record.bindingGenerationID
          && generation.binding == record.binding)
          || generation.pendingReservationGenerationID == record.bindingGenerationID
      case .retryWaiting, .paused:
        guard let generation = currentGenerationBySubscription[recordSubscriptionKey(record)]
        else {
          return false
        }
        return generation.generationID == record.bindingGenerationID
          && generation.binding == record.binding
      case .receipt, .terminal, .expired, .exhausted, .superseded:
        return true
      }
    }
    let leaseLimit = document.lastObservedAt.addingTimeInterval(maximumLease)
    let leaseLimitInterval = leaseLimit.timeIntervalSince(document.lastObservedAt)
    guard
      isValidDate(leaseLimit),
      leaseLimit > document.lastObservedAt,
      leaseLimitInterval.isFinite,
      leaseLimitInterval <= maximumLease,
      Set(records.map(recordEventKey)).count == records.count,
      Set(records.map(recordPositionKey)).count == records.count,
      Set(reservationIDs).count == reservationIDs.count,
      Set(generationIDs).count == generations.count,
      Set(generations.map(generationSubscriptionKey)).count == generations.count,
      generationOwnersAreUnique,
      generationBindingsAreConsistent,
      activeRecordOwnershipIsValid,
      generations.allSatisfy(validBindingGeneration),
      generations.allSatisfy({ generation in
        guard let pendingID = generation.pendingReservationGenerationID else { return true }
        return records.contains {
          $0.bindingGenerationID == pendingID
            && $0.status == .reserved
            && sameSubscription(
              $0.binding,
              profileID: generation.binding.profileID,
              subscriptionID: generation.binding.subscriptionID
            )
        }
      }),
      Set(records.map(recordBindingKey) + generations.map { bindingKey($0.binding) }).count
        <= maximumBindings,
      Dictionary(grouping: records, by: recordSubscriptionKey).values.allSatisfy({
        $0.count <= maximumRecordsPerSubscription
      }),
      Dictionary(grouping: records, by: { $0.binding.profileID }).values.allSatisfy({
        $0.count <= maximumRecordsPerProfile
      }),
      records.allSatisfy({ record in
        validRecord(record)
          && (record.receiptAt.map { $0 <= document.lastObservedAt } ?? true)
          && validRetryHorizon(record, lastObservedAt: document.lastObservedAt)
          && (record.leaseDeadline.map { deadline in
            let interval = deadline.timeIntervalSince(document.lastObservedAt)
            return deadline <= leaseLimit && interval.isFinite && interval <= maximumLease
          } ?? true)
      })
    else {
      throw AgentEventDeliveryLedgerError.storageFailure
    }
    let liveReservations = records.filter {
      $0.status == .reserved && ($0.leaseDeadline ?? .distantPast) > document.lastObservedAt
    }
    guard
      liveReservations.count <= 4,
      Dictionary(grouping: liveReservations, by: recordSubscriptionKey).values.allSatisfy({
        $0.count <= 1
      })
    else {
      throw AgentEventDeliveryLedgerError.storageFailure
    }
  }

  private static func validBindingGeneration(
    _ generation: AgentEventDeliveryLedgerBindingGeneration
  ) -> Bool {
    isValid(generation.binding)
      && isCanonicalUUID(generation.generationID)
      && (generation.pendingReservationGenerationID.map {
        isCanonicalUUID($0) && $0 != generation.generationID
      } ?? true)
  }

  private static func validRecord(_ record: AgentEventDeliveryLedgerRecord) -> Bool {
    guard
      isValid(record.binding),
      isCanonicalUUID(record.bindingGenerationID),
      isCanonicalUUID(record.eventID),
      record.sourcePosition.sequence < UInt64.max,
      isValidDate(record.expiresAt),
      record.receiptAt.map(isValidDate) ?? true,
      record.receiptAt == nil || record.status == .receipt,
      (1...maximumAttempts).contains(record.attemptCount),
      record.httpStatus.map({ (100...599).contains($0) }) ?? true
    else {
      return false
    }
    let hasLease = record.reservationID != nil || record.leaseDeadline != nil
    switch record.status {
    case .reserved:
      guard
        let reservationID = record.reservationID,
        isCanonicalUUID(reservationID),
        let deadline = record.leaseDeadline,
        isValidDate(deadline),
        deadline <= record.expiresAt,
        record.nextEligibleAt == nil,
        record.httpStatus == nil,
        record.failureCategory == nil
      else {
        return false
      }
      return true
    case .retryWaiting:
      guard
        !hasLease,
        let next = record.nextEligibleAt,
        isValidDate(next),
        next < record.expiresAt,
        record.attemptCount < maximumAttempts,
        let failure = record.failureCategory,
        [.transportFailure, .cancelled, .retryableHTTP, .leaseExpired].contains(failure)
      else {
        return false
      }
      switch failure {
      case .retryableHTTP:
        guard record.httpStatus.map(Self.isRetryableHTTPStatus) == true else { return false }
      case .transportFailure, .cancelled, .leaseExpired:
        guard record.httpStatus == nil else { return false }
      case .terminalHTTP, .pausedHTTP, .retentionExpired, .attemptsExhausted, .bindingRefreshed:
        return false
      }
      return true
    case .receipt:
      return !hasLease
        && record.nextEligibleAt == nil
        && record.httpStatus.map { (200...299).contains($0) } == true
        && record.failureCategory == nil
    case .terminal:
      return !hasLease
        && record.nextEligibleAt == nil
        && [410, 413].contains(record.httpStatus ?? 0)
        && record.failureCategory == .terminalHTTP
    case .paused:
      guard
        !hasLease,
        record.nextEligibleAt == nil,
        let status = record.httpStatus,
        (100...599).contains(status),
        !(200...299).contains(status),
        ![408, 410, 413, 429].contains(status),
        !(500...599).contains(status),
        record.failureCategory == .pausedHTTP
      else {
        return false
      }
      return true
    case .expired:
      return !hasLease
        && record.nextEligibleAt == nil
        && record.httpStatus == nil
        && record.failureCategory == .retentionExpired
    case .exhausted:
      return !hasLease
        && record.nextEligibleAt == nil
        && record.attemptCount == maximumAttempts
        && (record.httpStatus.map(Self.isRetryableHTTPStatus) ?? true)
        && record.failureCategory == .attemptsExhausted
    case .superseded:
      return !hasLease
        && record.nextEligibleAt == nil
        && record.httpStatus == nil
        && record.failureCategory == .bindingRefreshed
    }
  }

  private static func validRetryHorizon(
    _ record: AgentEventDeliveryLedgerRecord,
    lastObservedAt: Date
  ) -> Bool {
    guard
      record.status == .retryWaiting,
      let nextEligibleAt = record.nextEligibleAt,
      nextEligibleAt > lastObservedAt
    else {
      return true
    }
    let interval = nextEligibleAt.timeIntervalSince(lastObservedAt)
    return interval.isFinite && interval <= maximumRetryDelay
  }

  private static func checkCapacity(
    for candidate: AgentEventDeliveryLedgerCandidate,
    generations: [AgentEventDeliveryLedgerBindingGeneration],
    records: [AgentEventDeliveryLedgerRecord]
  ) throws {
    guard records.count < maximumRecordsTotal else {
      throw AgentEventDeliveryLedgerError.capacityExceeded
    }
    guard
      records.filter({ recordSubscriptionKey($0) == candidateSubscriptionKey(candidate) }).count
        < maximumRecordsPerSubscription
    else {
      throw AgentEventDeliveryLedgerError.capacityExceeded
    }
    guard
      records.filter({ $0.binding.profileID == candidate.binding.profileID }).count
        < maximumRecordsPerProfile
    else {
      throw AgentEventDeliveryLedgerError.capacityExceeded
    }
    let bindingKeys = Set(
      records.map(recordBindingKey) + generations.map { bindingKey($0.binding) })
    guard
      bindingKeys.contains(candidateBindingKey(candidate))
        || bindingKeys.count < maximumBindings
    else {
      throw AgentEventDeliveryLedgerError.capacityExceeded
    }
  }

  private static func isValid(
    _ candidate: AgentEventDeliveryLedgerCandidate
  ) -> Bool {
    guard
      isValid(candidate.binding),
      isCanonicalUUID(candidate.eventID),
      candidate.sourcePosition.sequence < UInt64.max,
      isValidDate(candidate.eventTimestamp),
      isValidDate(candidate.subscriptionExpiresAt),
      let expiresAt = candidate.expiresAt,
      isValidDate(expiresAt)
    else {
      return false
    }
    return true
  }

  private static func isValid(_ binding: AgentEventCallbackVerificationBinding) -> Bool {
    binding.subscriptionID.hasPrefix("evt_")
      && binding.subscriptionID.utf8.count == 68
      && binding.subscriptionID.utf8.dropFirst(4).allSatisfy {
        (48...57).contains($0) || (97...102).contains($0)
      }
      && binding.subscriptionRevision > 0
      && binding.grantRevision > 0
      && isCanonicalUUID(binding.signingKeyReference)
  }

  static func isValidDate(_ date: Date) -> Bool {
    date.timeIntervalSince1970.isFinite
  }

  private static func isCanonicalUUID(_ value: String) -> Bool {
    guard let uuid = UUID(uuidString: value) else { return false }
    return uuid.uuidString.lowercased() == value
  }

  private static func classify(_ outcome: AgentEventDeliveryLedgerOutcome) throws -> Settlement {
    switch outcome {
    case .transportFailure:
      return .retry(.transportFailure, httpStatus: nil, retryAfter: nil)
    case .cancelled:
      return .retry(.cancelled, httpStatus: nil, retryAfter: nil)
    case .httpStatus(let status, let retryAfter):
      guard (100...599).contains(status) else {
        throw AgentEventDeliveryLedgerError.invalidInput
      }
      let validRetryAfter = retryAfter.flatMap { value in
        value.isFinite && (0...maximumRetryAfter).contains(value) ? value : nil
      }
      if (200...299).contains(status) { return .receipt(status) }
      if [410, 413].contains(status) { return .terminal(status) }
      if status == 408 || status == 429 || (500...599).contains(status) {
        return .retry(.retryableHTTP, httpStatus: status, retryAfter: validRetryAfter)
      }
      return .pause(status)
    }
  }

  private static func retryDelay(
    attempt: UInt64,
    jitterBasisPoints: UInt64,
    retryAfter: TimeInterval?
  ) -> (delay: TimeInterval, minimum: TimeInterval) {
    var base = initialRetryDelay
    if attempt > 1 {
      for _ in 1..<attempt {
        base = min(maximumRetryDelay, base * 2)
      }
    }
    let jittered = min(
      maximumRetryDelay,
      base + base * Double(jitterBasisPoints) / 10_000
    )
    let retryAfterMinimum = retryAfter ?? 0
    return (max(jittered, retryAfterMinimum), max(base, retryAfterMinimum))
  }

  private static func leaseDeadline(now: Date, expiresAt: Date) throws -> Date {
    let requestedDeadline = now.addingTimeInterval(maximumLease)
    guard isValidDate(requestedDeadline), requestedDeadline > now else {
      throw AgentEventDeliveryLedgerError.invalidInput
    }
    let deadline = min(requestedDeadline, expiresAt)
    guard deadline > now else { throw AgentEventDeliveryLedgerError.staleReservation }
    let interval = deadline.timeIntervalSince(now)
    guard interval.isFinite, interval <= maximumLease else {
      throw AgentEventDeliveryLedgerError.invalidInput
    }
    return deadline
  }

  private static func sameIdentity(
    _ record: AgentEventDeliveryLedgerRecord,
    candidate: AgentEventDeliveryLedgerCandidate,
    generationID: String,
    expiresAt: Date
  ) -> Bool {
    record.binding == candidate.binding
      && record.bindingGenerationID == generationID
      && record.eventID == candidate.eventID
      && record.sourcePosition == candidate.sourcePosition
      && record.expiresAt == expiresAt
  }

  private static func sameBindingEvent(
    _ record: AgentEventDeliveryLedgerRecord,
    candidate: AgentEventDeliveryLedgerCandidate,
    generationID: String
  ) -> Bool {
    record.binding == candidate.binding
      && record.bindingGenerationID == generationID
      && record.eventID == candidate.eventID
  }

  private static func sameBindingPosition(
    _ record: AgentEventDeliveryLedgerRecord,
    candidate: AgentEventDeliveryLedgerCandidate,
    generationID: String
  ) -> Bool {
    record.binding == candidate.binding
      && record.bindingGenerationID == generationID
      && record.sourcePosition == candidate.sourcePosition
  }

  private static func sameSubscription(
    _ binding: AgentEventCallbackVerificationBinding,
    profileID: UUID,
    subscriptionID: String
  ) -> Bool {
    binding.profileID == profileID && binding.subscriptionID == subscriptionID
  }

  private static func recordEventKey(_ record: AgentEventDeliveryLedgerRecord) -> String {
    "\(recordGenerationKey(record))\u{0}\(record.eventID)"
  }

  private static func recordPositionKey(_ record: AgentEventDeliveryLedgerRecord) -> String {
    "\(recordGenerationKey(record))\u{0}\(record.sourcePosition.epoch.uuidString.lowercased())\u{0}\(record.sourcePosition.sequence)"
  }

  private static func recordBindingKey(_ record: AgentEventDeliveryLedgerRecord) -> String {
    bindingKey(record.binding)
  }

  private static func recordGenerationKey(_ record: AgentEventDeliveryLedgerRecord) -> String {
    "\(bindingKey(record.binding))\u{0}\(record.bindingGenerationID)"
  }

  private static func candidateBindingKey(
    _ candidate: AgentEventDeliveryLedgerCandidate
  ) -> String {
    bindingKey(candidate.binding)
  }

  private static func bindingKey(_ binding: AgentEventCallbackVerificationBinding) -> String {
    [
      binding.profileID.uuidString.lowercased(), binding.subscriptionID,
      String(binding.subscriptionRevision), String(binding.grantRevision),
      binding.signingKeyReference,
    ].joined(separator: "\u{0}")
  }

  private static func generationSubscriptionKey(
    _ generation: AgentEventDeliveryLedgerBindingGeneration
  ) -> String {
    "\(generation.binding.profileID.uuidString.lowercased())\u{0}\(generation.binding.subscriptionID)"
  }

  private static func recordSubscriptionKey(_ record: AgentEventDeliveryLedgerRecord) -> String {
    "\(record.binding.profileID.uuidString.lowercased())\u{0}\(record.binding.subscriptionID)"
  }

  private static func candidateSubscriptionKey(
    _ candidate: AgentEventDeliveryLedgerCandidate
  ) -> String {
    "\(candidate.binding.profileID.uuidString.lowercased())\u{0}\(candidate.binding.subscriptionID)"
  }

  private static func isRetryableHTTPStatus(_ status: Int) -> Bool {
    status == 408 || status == 429 || (500...599).contains(status)
  }

  private static func readPersistedData(at url: URL, maximumFileSize: Int) -> Data? {
    guard
      let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
      attributes[.type] as? FileAttributeType == .typeRegular,
      let size = attributes[.size] as? NSNumber,
      size.int64Value >= 0,
      size.int64Value <= Int64(maximumFileSize),
      let data = try? Data(contentsOf: url),
      data.count <= maximumFileSize
    else {
      return nil
    }
    return data
  }

  private static func defaultFileURL() -> URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent(FleckProductPaths.canonicalDirectoryName, isDirectory: true)
      .appendingPathComponent("AgentIntegrations", isDirectory: true)
      .appendingPathComponent("AgentEvents", isDirectory: true)
      .appendingPathComponent("event-delivery-ledger.json")
  }
}

private struct AgentEventDeliveryLedgerCodingKey: CodingKey {
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

private func requireLedgerKeys<Key: CodingKey>(
  _ container: KeyedDecodingContainer<Key>,
  _ expected: Set<String>,
  optional: Set<String> = []
) throws {
  let actual = Set(container.allKeys.map(\.stringValue))
  guard
    expected.isSubset(of: actual),
    actual.subtracting(expected).isSubset(of: optional)
  else {
    throw AgentEventDeliveryLedgerError.storageFailure
  }
}
