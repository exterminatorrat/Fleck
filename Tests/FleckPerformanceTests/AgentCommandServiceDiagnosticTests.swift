import AppKit
import CryptoKit
import Darwin
import FleckCore
import Testing

@testable import FleckApp

private let performanceOptIn = ProcessInfo.processInfo.environment["FLECK_PERF_RUN"] == "1"
private let measurementCount = 9
private let warmupCount = 1

#if DEBUG
private let compiledConfiguration = "debug"
#else
private let compiledConfiguration = "release"
#endif

private enum PerformanceHarnessError: Error {
  case invalidRunEnvironment
  case processCPUUnavailable
  case invalidMeasurement
}

private struct RunMetadata {
  let configuration: String
  let buildSystem: String
  let swiftVersion: String
  let macOSVersion: String
  let architecture: String
}

private struct MeasuredAction {
  let perform: @MainActor () async throws -> Void
  let verify: @MainActor () async throws -> Void
  let counters: @MainActor () -> [String: Int]
  let quiesce: @MainActor () async -> Void
  let cleanup: @MainActor () async -> Void
}

@MainActor
private func runMetadata() throws -> RunMetadata {
  let environment = ProcessInfo.processInfo.environment
  guard environment["FLECK_PERF_RUN"] == "1",
    environment["FLECK_PERF_CONFIGURATION"] == compiledConfiguration,
    let buildSystem = environment["FLECK_PERF_BUILD_SYSTEM"],
    ["default", "native", "swiftbuild", "xcode"].contains(buildSystem),
    let swiftVersion = environment["FLECK_PERF_SWIFT_VERSION"],
    !swiftVersion.isEmpty,
    swiftVersion.unicodeScalars.allSatisfy({
      CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .()+_-")
        .contains($0)
    })
  else {
    throw PerformanceHarnessError.invalidRunEnvironment
  }

  let version = ProcessInfo.processInfo.operatingSystemVersion
  #if arch(arm64)
  let architecture = "arm64"
  #elseif arch(x86_64)
  let architecture = "x86_64"
  #else
  let architecture = "other"
  #endif

  return RunMetadata(
    configuration: compiledConfiguration,
    buildSystem: buildSystem,
    swiftVersion: swiftVersion,
    macOSVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
    architecture: architecture
  )
}

@MainActor
private func encodedRTF(_ body: String, underlinePrefix: Bool = true) throws -> Data {
  let attributed = NSMutableAttributedString(
    string: body,
    attributes: [.font: NSFont.systemFont(ofSize: 13)]
  )
  if attributed.length > 0, underlinePrefix {
    attributed.addAttribute(
      .underlineStyle,
      value: NSUnderlineStyle.single.rawValue,
      range: NSRange(location: 0, length: min(12, attributed.length))
    )
  }
  return try NoteRichTextCodec.encode(attributed)
}

private func syntheticBody(byteCount: Int, marker: String) -> String {
  let paragraph = "Fleck perf \(marker) — λ Ω 🧪\ncontrolled synthetic paragraph.\n"
  var body = ""
  while body.utf8.count < byteCount {
    body += paragraph
  }
  return body
}

private func temporaryStoreRoot() throws -> URL {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "fleck-foreground-perf-\(UUID().uuidString)",
    isDirectory: true
  )
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  return root
}

private func sha256(_ string: String) -> String {
  SHA256.hash(data: Data(string.utf8))
    .map { String(format: "%02x", $0) }
    .joined()
}

private func processCPUMicroseconds() throws -> Int64 {
  var usage = rusage()
  guard getrusage(RUSAGE_SELF, &usage) == 0 else {
    throw PerformanceHarnessError.processCPUUnavailable
  }
  let user = try timevalMicroseconds(usage.ru_utime)
  let system = try timevalMicroseconds(usage.ru_stime)
  let (total, overflow) = user.addingReportingOverflow(system)
  guard !overflow else { throw PerformanceHarnessError.processCPUUnavailable }
  return total
}

@MainActor
private func measureFreshActions(
  caseID: String,
  scope: String,
  prepare: @MainActor () async throws -> MeasuredAction
) async throws -> RawMeasurement {
  var samples: [Int64] = []
  var cpuSamples: [Int64] = []
  var counters: [String: Int] = [:]

  for iteration in 0..<(warmupCount + measurementCount) {
    let action = try await prepare()
    try await withActionCleanup(action) {
      if iteration < warmupCount {
        try await action.perform()
        try await action.verify()
        await action.quiesce()
        return
      }

      let cpuBefore = try processCPUMicroseconds()
      let clock = ContinuousClock()
      let start = clock.now
      try await action.perform()
      let elapsed = start.duration(to: clock.now)
      let cpuAfter = try processCPUMicroseconds()
      guard cpuAfter >= cpuBefore else { throw PerformanceHarnessError.invalidMeasurement }
      samples.append(try nanoseconds(elapsed))
      cpuSamples.append(cpuAfter - cpuBefore)
      try await action.verify()
      for (name, value) in action.counters() {
        counters[name, default: 0] += value
      }
      await action.quiesce()
    }
  }

  return try rawMeasurement(
    caseID: caseID,
    scope: scope,
    samples: samples,
    cpuSamples: cpuSamples,
    counters: counters
  )
}

@MainActor
private func withActionCleanup<Value>(
  _ action: MeasuredAction,
  operation: @MainActor () async throws -> Value
) async throws -> Value {
  do {
    let result = try await operation()
    await action.cleanup()
    return result
  } catch {
    await action.cleanup()
    throw error
  }
}

private func rawMeasurement(
  caseID: String,
  scope: String,
  samples: [Int64],
  cpuSamples: [Int64],
  counters: [String: Int]
) throws -> RawMeasurement {
  let sorted = samples.sorted()
  guard !sorted.isEmpty,
    sorted.allSatisfy({ $0 >= 0 }),
    cpuSamples.count == sorted.count,
    cpuSamples.allSatisfy({ $0 >= 0 })
  else { throw PerformanceHarnessError.invalidMeasurement }
  let middle = sorted.count / 2
  guard !sorted.count.isMultiple(of: 2) else {
    throw PerformanceHarnessError.invalidMeasurement
  }
  var totalCPUMicroseconds: Int64 = 0
  for sample in cpuSamples {
    let (total, overflow) = totalCPUMicroseconds.addingReportingOverflow(sample)
    guard !overflow else { throw PerformanceHarnessError.invalidMeasurement }
    totalCPUMicroseconds = total
  }
  let p95Rank = max(1, Int(ceil(Double(sorted.count) * 0.95)))
  return RawMeasurement(
    caseID: caseID,
    scope: scope,
    repetitions: sorted.count,
    warmups: warmupCount,
    medianNanoseconds: sorted[middle],
    p95Nanoseconds: sorted[p95Rank - 1],
    minimumNanoseconds: sorted[0],
    maximumNanoseconds: sorted[sorted.count - 1],
    processCPUMicroseconds: totalCPUMicroseconds,
    counters: counters
  )
}

private func timevalMicroseconds(_ value: timeval) throws -> Int64 {
  let seconds = Int64(value.tv_sec)
  let microseconds = Int64(value.tv_usec)
  guard seconds >= 0, microseconds >= 0, microseconds < 1_000_000 else {
    throw PerformanceHarnessError.processCPUUnavailable
  }
  let (wholeSeconds, secondsOverflow) = seconds.multipliedReportingOverflow(by: 1_000_000)
  let (total, microsecondsOverflow) = wholeSeconds.addingReportingOverflow(microseconds)
  guard !secondsOverflow, !microsecondsOverflow else {
    throw PerformanceHarnessError.processCPUUnavailable
  }
  return total
}

private func nanoseconds(_ duration: Duration) throws -> Int64 {
  let components = duration.components
  guard
    components.seconds >= 0,
    components.attoseconds >= 0,
    components.attoseconds < 1_000_000_000_000_000_000
  else { throw PerformanceHarnessError.invalidMeasurement }
  let (wholeSeconds, secondsOverflow) = components.seconds.multipliedReportingOverflow(
    by: 1_000_000_000
  )
  let wholeNanoseconds = components.attoseconds / 1_000_000_000
  let roundedSubNanosecond: Int64 =
    components.attoseconds % 1_000_000_000 == 0 ? 0 : 1
  let (subsecondNanoseconds, fractionOverflow) = wholeNanoseconds.addingReportingOverflow(
    roundedSubNanosecond
  )
  let (total, totalOverflow) = wholeSeconds.addingReportingOverflow(subsecondNanoseconds)
  guard !secondsOverflow, !fractionOverflow, !totalOverflow else {
    throw PerformanceHarnessError.invalidMeasurement
  }
  return total
}

private struct ServiceDiagnosticRecord: Encodable {
  let schemaVersion: Int
  let diagnosticID: String
  let scope: String
  let requestSurface: String
  let profileAuthorization: String
  let capabilityAuthorization: String
  let optIn: Bool
  let performanceGating: Bool
  let acceptanceLimits: String
  let wireOrEndToEndMCP: Bool
  let shippingMeasurement: Bool
  let configuration: String
  let buildSystem: String
  let testabilityEnabled: Bool
  let swiftVersion: String
  let macOSVersion: String
  let architecture: String
  let repetitions: Int
  let warmups: Int
  let unexpectedOperationErrors: Int
  let outcome: String
  let medianMilliseconds: Double
  let p95Milliseconds: Double
  let rangeMilliseconds: [Double]
  let processCPUSeconds: Double
  let processCPUSecondsPerOperation: Double
  let counters: [String: Int]
  let baselineStatus: String
}

private enum AgentCommandDiagnosticScenario: String, CaseIterable {
  case clean = "clean_after_explicit_save"
  case pendingHumanEdit = "pending_human_edit_after_explicit_save"
}

private final class DiagnosticSaveOperationCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var operationCount = 0

  var count: Int { lock.withLock { operationCount } }

  func record() {
    lock.withLock { operationCount += 1 }
  }
}

private final class DiagnosticAgentSecretStore: AgentSecretStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [String: Data] = [:]

  func read(service: String, account: String) throws -> Data? {
    lock.withLock { storage[key(service: service, account: account)] }
  }

  func write(_ data: Data, service: String, account: String) throws {
    lock.withLock { storage[key(service: service, account: account)] = data }
  }

  func delete(service: String, account: String) throws {
    _ = lock.withLock { storage.removeValue(forKey: key(service: service, account: account)) }
  }

  private func key(service: String, account: String) -> String {
    "\(service)\u{0}\(account)"
  }
}

private struct DiagnosticRandomBytesProvider: AgentRandomBytesProviding {
  func randomBytes(count: Int) throws -> Data {
    Data(repeating: 0xA7, count: count)
  }
}

@Suite(.serialized)
struct AgentCommandServiceDiagnosticTests {
  @Test(.enabled(if: performanceOptIn))
  @MainActor
  func agentCommandServiceAuthorizedWritesReportServiceLevelDiagnostics()
    async throws
  {
    let metadata = try runMetadata()
    for noteCount in [10, 100, 1_000] {
      for scenario in AgentCommandDiagnosticScenario.allCases {
        let measurement = try await measureFreshActions(
          caseID: "diagnostic.agent_command_service.\(scenario.rawValue).notes.\(noteCount).1KiB",
          scope: "service_level.not_wire_or_end_to_end_mcp",
          prepare: {
            try await makeAgentCommandServiceAction(
              noteCount: noteCount,
              scenario: scenario
            )
          }
        )
        recordServiceDiagnostic(measurement, metadata: metadata)
      }
    }
  }
}

@MainActor
private func makeAgentCommandServiceAction(
  noteCount: Int,
  scenario: AgentCommandDiagnosticScenario
) async throws -> MeasuredAction {
  let initialBody = syntheticBody(byteCount: 1_024, marker: "A")
  let initialRTF = try encodedRTF(initialBody)
  let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
  let notes = (0..<noteCount).map { index in
    Note(
      title: "Synthetic \(index)",
      body: initialBody,
      richTextRTF: initialRTF,
      createdAt: referenceDate,
      modifiedAt: referenceDate,
      revision: 1
    )
  }
  let initialTarget = try #require(notes.first)
  let workspace = Workspace(notes: notes, selectedNoteID: initialTarget.id)
  let root = try temporaryStoreRoot()

  do {
    let store = LocalStore(rootURL: root)
    let seedResult = try await store.save(
      workspace: workspace,
      preferences: AppPreferences(),
      generation: 1
    )
    try #require(seedResult == .committed)

    let integrationRoot = root.appendingPathComponent(
      "AgentIntegrations",
      isDirectory: true
    )
    let profileStore = AgentProfileStore(
      profilesURL: integrationRoot.appendingPathComponent("profiles.json"),
      secretStore: DiagnosticAgentSecretStore(),
      randomBytes: DiagnosticRandomBytesProvider()
    )
    let provisioning = try await profileStore.create(
      name: "Synthetic performance diagnostic"
    )
    let profile = provisioning.profile
    let capabilityStore = AgentCapabilityStore(
      capabilitiesURL: integrationRoot.appendingPathComponent(
        "capabilities.json"
      ),
      previousCapabilitiesURL: integrationRoot.appendingPathComponent(
        "capabilities.previous.json"
      )
    )
    let initialCapabilities = try await capabilityStore.loadOrMigrate(
      activeProfileIDs: [profile.id],
      workspace: workspace
    )
    let initialProfile = try #require(initialCapabilities.profiles[profile.id])
    let writeProfile = AgentProfileCapabilities(
      profileID: profile.id,
      grantRevision: initialProfile.grantRevision + 1,
      allowedCapabilities: [.writeNotes],
      grants: [
        AgentResourceGrant(
          scope: .note(noteID: initialTarget.id),
          authority: .write
        )
      ]
    )
    _ = try await capabilityStore.replaceProfile(
      writeProfile,
      expectedGrantRevision: initialProfile.grantRevision
    )

    let capabilityAuthority = AgentCapabilityAuthority(store: capabilityStore)
    let activityStore = AgentActivityStore(rootURL: root)
    let saveOperationCounter = DiagnosticSaveOperationCounter()
    let state = AppState(
      store: store,
      saveOperation: { workspace, preferences, trashedNotes, generation in
        saveOperationCounter.record()
        return try await store.save(
          workspace: workspace,
          preferences: preferences,
          trashedNotes: trashedNotes,
          generation: generation
        )
      },
      agentProfileStore: profileStore,
      agentActivityStore: activityStore,
      agentCapabilityStore: capabilityStore,
      agentCapabilityAuthority: capabilityAuthority
    )
    await state.waitUntilInitialLoad()
    try #require(state.isAgentWorkspaceAvailable)
    try #require(state.workspace == workspace)
    try await state.saveNow(transactionOwned: true).value
    await state.quiescePersistenceForTesting()
    let settledSaveOperationCount = saveOperationCounter.count
    try #require(settledSaveOperationCount > 0)
    let initialGeneration = state.persistenceGeneration

    let authorization = try await capabilityAuthority.snapshot(
      profileID: profile.id,
      workspace: state.workspace
    )
    try #require(authorization.availableCapabilities.contains(.writeNotes))
    try #require(authorization.writableNoteIDs == Set([initialTarget.id]))

    let expectedHumanBody: String?
    let expectedHumanRevision: UInt64?
    if scenario == .pendingHumanEdit {
      let humanBody = syntheticBody(byteCount: 1_024, marker: "H")
      let humanRTF = try encodedRTF(humanBody)
      state.updateSelected(body: humanBody, richTextRTF: humanRTF)
      expectedHumanBody = humanBody
      expectedHumanRevision = initialTarget.revision + 1
    } else {
      expectedHumanBody = nil
      expectedHumanRevision = nil
    }

    let target = try #require(
      state.workspace.notes.first(where: { $0.id == initialTarget.id })
    )
    let generationBeforeWrite = state.persistenceGeneration
    try #require(
      generationBeforeWrite == initialGeneration
        + (expectedHumanRevision == nil ? 0 : 1)
    )
    try #require(
      target.revision == initialTarget.revision
        + (expectedHumanRevision == nil ? 0 : 1)
    )
    let generationAfterWrite = generationBeforeWrite + 1
    let expectedBody = target.body + "\n\nAgent diagnostic write"
    let operationID = UUID()
    let command = AgentWorkspaceCommand.appendText(
      request: .init(
        context: .init(
          noteID: target.id,
          expectedRevision: target.revision,
          operationID: operationID
        ),
        text: "Agent diagnostic write"
      )
    )
    let actor = AgentActivityActor.integration(
      profileID: profile.id,
      displayName: profile.displayName
    )
    let credential = provisioning.credential
    let service = AgentCommandService(
      state: state,
      profileStore: profileStore,
      activityStore: activityStore,
      capabilityAuthority: capabilityAuthority,
      taskHandleCodec: AgentTaskHandleCodec(
        signingKeyProvider: AgentKeychainSigningKeyProvider(
          secretStore: DiagnosticAgentSecretStore(),
          randomBytes: DiagnosticRandomBytesProvider()
        )
      ),
      now: {
        Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
      }
    )
    var response: AgentWorkspaceResponse?
    var saveOperationsBeforeWrite = 0
    var saveOperationsDuringWrite = 0
    var saveOperationsDuringReplay = 0
    var durableProofCount = 0
    var durableReceiptCount = 0

    try #require(saveOperationCounter.count == settledSaveOperationCount)

    return MeasuredAction(
      perform: {
        try #require(saveOperationCounter.count == settledSaveOperationCount)
        saveOperationsBeforeWrite = saveOperationCounter.count
        response = try await service.execute(
          profileID: profile.id,
          credential: credential,
          command: command
        )
      },
      verify: {
        await state.quiescePersistenceForTesting()
        saveOperationsDuringWrite =
          saveOperationCounter.count - saveOperationsBeforeWrite
        let firstResponse = try #require(response)
        guard case .write(let receipt) = firstResponse else {
          throw PerformanceHarnessError.invalidMeasurement
        }
        try #require(receipt.noteID == target.id)
        try #require(receipt.previousRevision == target.revision)
        try #require(receipt.resultingRevision == target.revision + 1)

        let reopenedSnapshot = try await LocalStore(rootURL: root).loadSnapshot()
        let savedTarget = try #require(
          reopenedSnapshot.workspace.notes.first(where: { $0.id == target.id })
        )
        let committedTarget = try #require(
          state.workspace.notes.first(where: { $0.id == target.id })
        )
        try #require(savedTarget.body == expectedBody)
        try #require(savedTarget.revision == receipt.resultingRevision)
        try #require(savedTarget.richTextRTF == committedTarget.richTextRTF)
        let savedRTF = try #require(savedTarget.richTextRTF)
        let decodedRTF = try NoteRichTextCodec.decode(savedRTF)
        try #require(decodedRTF.string == expectedBody)
        try #require(
          (decodedRTF.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? NSNumber)?
            .intValue == NSUnderlineStyle.single.rawValue
        )
        var expectedPersistedWorkspace = state.workspace
        let targetIndex = try #require(
          expectedPersistedWorkspace.notes.firstIndex(where: { $0.id == target.id })
        )
        expectedPersistedWorkspace.notes[targetIndex].modifiedAt = Date(
          timeIntervalSince1970: floor(committedTarget.modifiedAt.timeIntervalSince1970)
        )
        try #require(expectedPersistedWorkspace == reopenedSnapshot.workspace)
        try #require(reopenedSnapshot.generation == generationAfterWrite)
        try #require(state.persistenceGeneration == generationAfterWrite)

        if let expectedHumanBody, let expectedHumanRevision {
          try #require(target.body == expectedHumanBody)
          try #require(target.revision == expectedHumanRevision)
        } else {
          try #require(target.body == initialTarget.body)
          try #require(target.revision == initialTarget.revision)
        }
        try #require(
          reopenedSnapshot.workspace.notes.filter { $0.id != target.id }
            == workspace.notes.filter { $0.id != target.id }
        )

        let stateProof = try #require(
          state.agentCommitProofs.first(where: { $0.operationID == operationID })
        )
        try #require(state.agentCommitProofs.count == 1)
        try #require(stateProof.changeID == receipt.changeID)
        try #require(stateProof.noteID == receipt.noteID)
        try #require(stateProof.resultingRevision == receipt.resultingRevision)
        try #require(stateProof.bodySHA256 == sha256(expectedBody))
        try #require(reopenedSnapshot.commitProofs == [stateProof])
        durableProofCount = reopenedSnapshot.commitProofs.count

        let reopenedActivityStore = AgentActivityStore(rootURL: root)
        let activityReceipt = try #require(
          reopenedActivityStore.priorReceipt(
            actor: actor,
            operationID: operationID
          )
        )
        try #require(activityReceipt == receipt)
        let activityRecords = reopenedActivityStore.list(
          profileID: profile.id,
          visibleNoteIDs: Set(notes.map(\.id))
        )
        try #require(activityRecords.count == 1)
        try #require(activityRecords[0].changeID == receipt.changeID)
        try #require(activityRecords[0].operationID == operationID)
        try #require(activityRecords[0].receipt == receipt)
        try #require(activityRecords[0].resultingRevision == receipt.resultingRevision)
        durableReceiptCount = activityRecords.count

        let saveOperationsBeforeReplay = saveOperationCounter.count
        let replayedResponse = try await service.execute(
          profileID: profile.id,
          credential: credential,
          command: command
        )
        try #require(replayedResponse == firstResponse)
        try #require(state.persistenceGeneration == generationAfterWrite)
        try #require(state.agentCommitProofs == [stateProof])
        let currentTarget = try #require(
          state.workspace.notes.first(where: { $0.id == target.id })
        )
        try #require(currentTarget.revision == receipt.resultingRevision)
        let replayedSnapshot = try await LocalStore(rootURL: root).loadSnapshot()
        try #require(replayedSnapshot == reopenedSnapshot)
        saveOperationsDuringReplay =
          saveOperationCounter.count - saveOperationsBeforeReplay
        try #require(saveOperationsDuringReplay == 0)
      },
      counters: {
        [
          "timedAuthorizedWriteExecutions": 1,
          "verificationOnlyIdempotentReplays": 1,
          "authorizedTargetRevisionAdvances": 1,
          "pendingHumanEditRevisionAdvances": expectedHumanRevision == nil ? 0 : 1,
          "persistenceGenerationAdvances": Int(
            generationAfterWrite - initialGeneration
          ),
          "appStateSaveOperationsBeforeWrite": saveOperationsBeforeWrite,
          "appStateSaveOperationsDuringWrite": saveOperationsDuringWrite,
          "appStateSaveOperationsDuringReplay": saveOperationsDuringReplay,
          "appStateCommitProofs": state.agentCommitProofs.count,
          "durableCommitProofs": durableProofCount,
          "durableActivityReceipts": durableReceiptCount,
          "unexpectedOperationErrors": 0,
        ]
      },
      quiesce: { await state.quiescePersistenceForTesting() },
      cleanup: {
        await state.quiescePersistenceForTesting()
        try? FileManager.default.removeItem(at: root)
      }
    )
  } catch {
    try? FileManager.default.removeItem(at: root)
    throw error
  }
}

@MainActor
private func recordServiceDiagnostic(
  _ measurement: RawMeasurement,
  metadata: RunMetadata
) {
  let record = ServiceDiagnosticRecord(
    schemaVersion: 1,
    diagnosticID: measurement.caseID,
    scope: measurement.scope,
    requestSurface: "AgentCommandService.execute",
    profileAuthorization: "real_agent_profile_store_with_in_memory_secret_backend",
    capabilityAuthorization: "temporary_persisted_agent_capability_store",
    optIn: ProcessInfo.processInfo.environment["FLECK_PERF_RUN"] == "1",
    performanceGating: false,
    acceptanceLimits: "none",
    wireOrEndToEndMCP: false,
    shippingMeasurement: false,
    configuration: metadata.configuration,
    buildSystem: metadata.buildSystem,
    testabilityEnabled: true,
    swiftVersion: metadata.swiftVersion,
    macOSVersion: metadata.macOSVersion,
    architecture: metadata.architecture,
    repetitions: measurement.repetitions,
    warmups: measurement.warmups,
    unexpectedOperationErrors: measurement.counters["unexpectedOperationErrors"] ?? 0,
    outcome: "authorized_write_and_idempotent_replay_verified",
    medianMilliseconds: measurement.medianMilliseconds,
    p95Milliseconds: measurement.p95Milliseconds,
    rangeMilliseconds: [measurement.minimumMilliseconds, measurement.maximumMilliseconds],
    processCPUSeconds: measurement.processCPUSeconds,
    processCPUSecondsPerOperation: measurement.processCPUSeconds / Double(measurement.repetitions),
    counters: measurement.counters,
    baselineStatus: "not_applicable"
  )
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys]
  guard let data = try? encoder.encode(record), let line = String(data: data, encoding: .utf8) else {
    Issue.record("Could not encode sanitized service diagnostic result")
    return
  }
  print("FLECK_PERF_DIAGNOSTIC \(line)")
}
