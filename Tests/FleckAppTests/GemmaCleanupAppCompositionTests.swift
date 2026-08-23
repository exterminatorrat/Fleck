#if os(macOS) && CLEAN_DICTATION_ENHANCED_CANDIDATE
import Foundation
import FleckCore
import Testing

@testable import FleckApp

@Suite(.serialized)
struct GemmaCleanupAppCompositionTests {
  @Test @MainActor
  func readyGemmaCompositionUsesCleanupContextAndFoundationPerRequest() async throws {
    let fixture = CompositionFixture(phase: .installed, verified: true)
    let foundation = CleanupGeneratorProbe(text: "foundation")
    let foundationAvailability = BoolProbe(false)
    let composition = fixture.makeComposition(
      foundationIsAvailable: { foundationAvailability.value },
      foundationGenerator: foundation
    )

    #expect(composition.settingsViewModel.presentation.accessibilityLabel == "Cleanup model")
    #expect(composition.settingsViewModel.presentation.modelLabel == "Gemma 3 1B")
    #expect(composition.isGemmaReady)

    foundationAvailability.value = true
    let foundationSession = try composition.cleanupGenerator.start(
      cleanupRequest(),
      maximumOutputTokens: 24
    )
    #expect(try await foundationSession.result().cleaned == "foundation")
    #expect(fixture.transport.startCount == 0)

    foundationAvailability.value = false
    let gemmaSession = try composition.cleanupGenerator.start(
      cleanupRequest(),
      maximumOutputTokens: 24
    )
    #expect(try await gemmaSession.result().cleaned == "gemma")
    #expect(fixture.transport.startCount == 1)
  }

  @Test @MainActor
  func gateRequiresInstalledPresentationAndVerifiedRepository() async throws {
    let fixture = CompositionFixture(phase: .installed, verified: false)
    let composition = fixture.makeComposition()

    #expect(!composition.isGemmaReady)
    #expect(throws: DynamicCleanupGeneratorError.gemmaUnavailable) {
      _ = try composition.cleanupGenerator.start(cleanupRequest(), maximumOutputTokens: 24)
    }

    fixture.verifiedRepositoryURL = fixture.repositoryURL
    fixture.installer.publish(phase: .installed)
    await fixture.waitForPresentation(.installed)
    composition.reconcileGate()
    #expect(composition.isGemmaReady)
    _ = try composition.cleanupGenerator.start(cleanupRequest(), maximumOutputTokens: 24)

    fixture.installer.publish(phase: .removing)
    while composition.settingsViewModel.presentation.phase != .removing {
      await Task.yield()
    }
    #expect(throws: DynamicCleanupGeneratorError.gemmaUnavailable) {
      _ = try composition.cleanupGenerator.start(cleanupRequest(), maximumOutputTokens: 24)
    }
  }

  @Test @MainActor
  func gemmaAwaitsParakeetColdHandoffBeforeTransportStart() async throws {
    let fixture = CompositionFixture(phase: .installed, verified: true)
    let composition = fixture.makeComposition(prepareForGeneration: {
      fixture.events.append("parakeet-cold")
    })
    let session = try composition.cleanupGenerator.start(
      cleanupRequest(),
      maximumOutputTokens: 24
    )

    let result = try await session.result()

    #expect(result.cleaned == "gemma")
    #expect(fixture.events.values.prefix(2) == ["parakeet-cold", "transport-start"])
  }

  @Test @MainActor
  func mutationAndShutdownDisableImmediatelyAndDrainAcknowledgedLease() async throws {
    let fixture = CompositionFixture(
      phase: .installed,
      verified: true,
      blocksAcknowledgement: true
    )
    let composition = fixture.makeComposition()
    let session = try composition.cleanupGenerator.start(
      cleanupRequest(),
      maximumOutputTokens: 24
    )
    let result = Task { try await session.result() }
    await fixture.transport.waitUntilAcknowledgement()

    let drained = CompletionProbe()
    let shutdown = Task {
      await composition.shutdown()
      drained.finish()
    }
    await Task.yield()

    #expect(!drained.isFinished)
    #expect(throws: DynamicCleanupGeneratorError.gemmaUnavailable) {
      _ = try composition.cleanupGenerator.start(cleanupRequest(), maximumOutputTokens: 24)
    }

    fixture.transport.releaseAcknowledgement()
    #expect(try await result.value.cleaned == "gemma")
    await shutdown.value
    #expect(drained.isFinished)
    #expect(fixture.installer.cancelCount == 1)
  }

  @Test @MainActor
  func modelMutationCallbackDisablesImmediatelyAndDrainsAcknowledgedLease() async throws {
    let fixture = CompositionFixture(
      phase: .installed,
      verified: true,
      blocksAcknowledgement: true
    )
    let mutation = MutationCallbackProbe()
    let composition = GemmaCleanupCandidateComposition(
      applicationSupportURL: URL(fileURLWithPath: "/tmp/fleck-app-support"),
      foundationIsAvailable: { false },
      foundationGenerator: CleanupGeneratorProbe(text: "foundation"),
      prepareForGeneration: {},
      verifiedLoadState: { [weak fixture] in
        fixture?.verifiedRepositoryURL.map(EnhancedModelVerifiedLoadState.ready)
          ?? .unavailable
      },
      makeActivation: { applicationSupportURL, callback in
        #expect(applicationSupportURL.path == "/tmp/fleck-app-support")
        mutation.install(callback)
        return fixture.activation
      }
    )
    let session = try composition.cleanupGenerator.start(
      cleanupRequest(),
      maximumOutputTokens: 24
    )
    let result = Task { try await session.result() }
    await fixture.transport.waitUntilAcknowledgement()

    let drained = CompletionProbe()
    let modelMutation = Task {
      await mutation.run()
      drained.finish()
    }
    await Task.yield()

    #expect(!drained.isFinished)
    #expect(throws: DynamicCleanupGeneratorError.gemmaUnavailable) {
      _ = try composition.cleanupGenerator.start(cleanupRequest(), maximumOutputTokens: 24)
    }

    fixture.transport.releaseAcknowledgement()
    #expect(try await result.value.cleaned == "gemma")
    await modelMutation.value
    #expect(drained.isFinished)
  }

  @Test @MainActor
  func foundationAvailabilitySelectsTruthfulCleanupFallbackLabel() {
    let fixture = CompositionFixture(phase: .builtIn, verified: false)
    let composition = fixture.makeComposition(foundationIsAvailable: { true })

    #expect(composition.settingsViewModel.presentation.modelLabel == "Apple On-Device")
  }

  @Test @MainActor
  func runtimeExposesDistinctDictationAndCleanupSettingsModels() async {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("gemma-cleanup-runtime-" + UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let state = AppState(
      store: LocalStore(rootURL: root),
      saveOperation: { _, _, _ in }
    )
    await state.waitUntilInitialLoad()
    let runtime = DictationRuntime(appState: state, applicationSupportURL: root)

    await runtime.awaitStartupAssessment()

    #expect(runtime.admittedModelSettingsViewModel !== runtime.cleanupAdmittedModelSettingsViewModel)
    #expect(runtime.admittedModelSettingsViewModel.presentation.accessibilityLabel == "Dictation model")
    #expect(runtime.cleanupAdmittedModelSettingsViewModel.presentation.accessibilityLabel == "Cleanup model")
    await runtime.shutdown()
  }

  @Test
  func verifiedLocalCleanupDoesNotEnableSmartCaptureRouting() {
    let availability = DictationAvailability.evaluate(.init(
      osMajorVersion: 14,
      architecture: .appleSilicon,
      microphonePermission: .authorized,
      speechPermission: .authorized,
      appleOnDeviceRecognitionSupported: true,
      enhancedModelReady: false,
      foundationModelAvailability: .unsupportedOS,
      cleanupModelReady: true
    ))
    let compatibility = DictationCompatibilityPresentation(availability: availability)

    #expect(availability.cleanupAvailable)
    #expect(availability.routing == .inbox)
    #expect(compatibility.cleanup.detail == "Available")
    #expect(compatibility.cleanup.available)
    #expect(!compatibility.smartCapture.available)
  }
}

@MainActor
private final class CompositionFixture {
  let repositoryURL = URL(fileURLWithPath: "/tmp/fleck-gemma-ready", isDirectory: true)
  let installer: CompositionInstaller
  let manager: EnhancedModelManager
  let transport: CompositionTransport
  let events = EventProbe()
  var verifiedRepositoryURL: URL?

  init(
    phase: AdmittedModelInstallPhase,
    verified: Bool,
    blocksAcknowledgement: Bool = false
  ) {
    installer = CompositionInstaller(phase: phase)
    manager = EnhancedModelManager(
      modelRootURL: URL(fileURLWithPath: "/tmp/fleck-gemma-manager", isDirectory: true),
      candidateEnabled: true,
      architectureProvider: { true }
    )
    transport = CompositionTransport(
      events: events,
      blocksAcknowledgement: blocksAcknowledgement
    )
    verifiedRepositoryURL = verified ? repositoryURL : nil
  }

  func makeComposition(
    foundationIsAvailable: @escaping @Sendable () -> Bool = { false },
    foundationGenerator: any BoundedCleanupGenerating = CleanupGeneratorProbe(text: "foundation"),
    prepareForGeneration: @escaping @Sendable () async throws -> Void = {}
  ) -> GemmaCleanupCandidateComposition {
    GemmaCleanupCandidateComposition(
      activation: activation,
      foundationIsAvailable: foundationIsAvailable,
      foundationGenerator: foundationGenerator,
      prepareForGeneration: prepareForGeneration,
      verifiedLoadState: { [weak self] in
        self?.verifiedRepositoryURL.map(EnhancedModelVerifiedLoadState.ready) ?? .unavailable
      }
    )
  }

  var activation: GemmaCleanupTestActivation.Result {
    GemmaCleanupTestActivation.Result(
      manager: manager,
      installer: installer,
      helperExecutableURL: URL(fileURLWithPath: "/tmp/gemma-cleanup-helper"),
      makeTransport: { [transport] _ in transport }
    )
  }

  func waitForPresentation(_ phase: AdmittedModelInstallPhase) async {
    while installer.snapshot.phase != phase { await Task.yield() }
    for _ in 0..<100 {
      await Task.yield()
    }
  }
}

@MainActor
private final class CompositionInstaller: AdmittedModelInstalling {
  private(set) var snapshot: AdmittedModelInstallationSnapshot
  let updates: AsyncStream<AdmittedModelInstallationSnapshot>
  private let continuation: AsyncStream<AdmittedModelInstallationSnapshot>.Continuation
  private(set) var cancelCount = 0

  init(phase: AdmittedModelInstallPhase) {
    let pair = AsyncStream<AdmittedModelInstallationSnapshot>.makeStream()
    updates = pair.stream
    continuation = pair.continuation
    snapshot = .init(
      recommendation: phase == .builtIn
        ? .builtIn
        : .recommended(TestDescriptors.tinyAdmittedASR),
      phase: phase,
      lastError: nil
    )
    continuation.yield(snapshot)
  }

  func publish(phase: AdmittedModelInstallPhase) {
    snapshot = .init(
      recommendation: snapshot.recommendation,
      phase: phase,
      lastError: nil
    )
    continuation.yield(snapshot)
  }

  func refresh() async {}
  func install() async {}
  func cancel() { cancelCount += 1 }
  func repair() async {}
  func update() async {}
  func remove() async {}
}

private final class EventProbe: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [String] = []

  var values: [String] { lock.withLock { storage } }
  func append(_ value: String) { lock.withLock { storage.append(value) } }
}

private final class BoolProbe: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: Bool

  init(_ value: Bool) { storage = value }

  var value: Bool {
    get { lock.withLock { storage } }
    set { lock.withLock { storage = newValue } }
  }
}

private final class CompletionProbe: @unchecked Sendable {
  private let lock = NSLock()
  private var storage = false
  var isFinished: Bool { lock.withLock { storage } }
  func finish() { lock.withLock { storage = true } }
}

private final class MutationCallbackProbe: @unchecked Sendable {
  private let lock = NSLock()
  private var callback: (@Sendable () async -> Void)?

  func install(_ callback: @escaping @Sendable () async -> Void) {
    lock.withLock { self.callback = callback }
  }

  func run() async {
    let callback = lock.withLock { self.callback }
    await callback?()
  }
}

private struct CleanupGeneratorProbe: BoundedCleanupGenerating {
  let text: String

  func start(
    _: IncrementalCleanupRequest,
    maximumOutputTokens _: Int
  ) throws -> any CleanupGenerationSession {
    CleanupSessionProbe(text: text)
  }
}

private final class CleanupSessionProbe: CleanupGenerationSession, @unchecked Sendable {
  let text: String
  init(text: String) { self.text = text }
  func result() async throws -> GeneratedCleanupCandidate { .init(cleaned: text) }
  func acknowledgement() async {}
  func requestCancellation() {}
  func forceTerminate() {}
}

private final class CompositionTransport: GemmaCleanupTransport, @unchecked Sendable {
  private let lock = NSLock()
  private let eventsProbe: EventProbe
  private let blocksAcknowledgement: Bool
  private var sessions: [CompositionTransportSession] = []
  private var starts = 0

  init(events: EventProbe, blocksAcknowledgement: Bool) {
    eventsProbe = events
    self.blocksAcknowledgement = blocksAcknowledgement
  }

  var startCount: Int { lock.withLock { starts } }

  func start(_ request: GemmaCleanupHelperRequest) throws -> any GemmaCleanupTransportSession {
    eventsProbe.append("transport-start")
    let session = CompositionTransportSession(
      request: request,
      blocksAcknowledgement: blocksAcknowledgement
    )
    lock.withLock {
      starts += 1
      sessions.append(session)
    }
    session.complete()
    return session
  }

  func waitUntilAcknowledgement() async {
    while !lock.withLock({ sessions.first?.acknowledgementStarted == true }) {
      await Task.yield()
    }
  }

  func releaseAcknowledgement() {
    lock.withLock { sessions }.forEach { $0.releaseAcknowledgement() }
  }
}

private final class CompositionTransportSession: GemmaCleanupTransportSession, @unchecked Sendable {
  let events: AsyncThrowingStream<Data, Error>
  let terminationExpectation: GemmaCleanupTerminationExpectation
  private let continuation: AsyncThrowingStream<Data, Error>.Continuation
  private let lock = NSLock()
  private let blocksAcknowledgement: Bool
  private var acknowledgementContinuation:
    CheckedContinuation<GemmaCleanupTransportTerminationDisposition, Never>?
  private var acknowledgementStartedStorage = false

  init(request: GemmaCleanupHelperRequest, blocksAcknowledgement: Bool) {
    let pair = AsyncThrowingStream<Data, Error>.makeStream()
    events = pair.stream
    continuation = pair.continuation
    terminationExpectation = .init(
      cleanupRequestID: request.requestID,
      cancellationCommandID: "cancel-\(request.requestID)",
      shutdownCommandID: "shutdown-\(request.requestID)"
    )
    self.blocksAcknowledgement = blocksAcknowledgement
  }

  var acknowledgementStarted: Bool { lock.withLock { acknowledgementStartedStorage } }

  func complete() {
    let requestID = terminationExpectation.cleanupRequestID
    continuation.yield(Data(#"{"schemaVersion":1,"kind":"started","requestID":"\#(requestID)"}"#.utf8))
    continuation.yield(Data(#"{"schemaVersion":1,"kind":"completed","requestID":"\#(requestID)","rawText":"{\"text\":\"gemma\"}"}"#.utf8))
    continuation.finish()
  }

  func requestCancellation() {}
  func forceTerminate() { continuation.finish() }

  func terminationAcknowledgement(
    for phase: GemmaCleanupTerminationPhase
  ) async -> GemmaCleanupTransportTerminationDisposition {
    let disposition = verifiedDisposition(phase: phase)
    guard blocksAcknowledgement else { return disposition }
    return await withCheckedContinuation { continuation in
      lock.withLock {
        acknowledgementStartedStorage = true
        acknowledgementContinuation = continuation
      }
    }
  }

  func releaseAcknowledgement() {
    let continuation = lock.withLock { () -> CheckedContinuation<GemmaCleanupTransportTerminationDisposition, Never>? in
      defer { acknowledgementContinuation = nil }
      return acknowledgementContinuation
    }
    continuation?.resume(returning: verifiedDisposition(phase: .graceful(requireCancellationAcknowledgement: false)))
  }

  private func verifiedDisposition(
    phase: GemmaCleanupTerminationPhase
  ) -> GemmaCleanupTransportTerminationDisposition {
    .verified(.init(
      phase: phase,
      cleanupRequestID: terminationExpectation.cleanupRequestID,
      cancellationCommandID: nil,
      cancellationTargetRequestID: nil,
      shutdownCommandID: terminationExpectation.shutdownCommandID,
      cooperative: true,
      processTerminationMayBeRequired: false,
      processExited: true,
      outputDrained: true
    ))
  }
}

private func cleanupRequest() -> IncrementalCleanupRequest {
  .init(
    baseline: "hello world",
    protectedForms: [],
    replacements: 0,
    deadline: ContinuousClock.now.advanced(by: .seconds(5))
  )
}
#endif
