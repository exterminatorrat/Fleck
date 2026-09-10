#if os(macOS) && CLEAN_DICTATION_ENHANCED_CANDIDATE
import Combine
import Foundation
import FleckCore
import Testing

@testable import FleckApp

@Suite(.serialized)
struct GemmaCleanupAppCompositionTests {
  @Test @MainActor
  func installedVerifiedGemmaCompositionRoutesSemantically() async {
    let fixture = CompositionFixture(phase: .installed, verified: true)
    let inbox = compositionCandidate(title: "Inbox")
    let project = compositionCandidate(title: "Project Delta", context: "Launch plans and deadlines")
    fixture.transport.responseText = "high:c1"
    let composition = fixture.makeComposition()

    #expect(await composition.destinationRouter.route(
      transcript: "Prepare the launch checklist",
      candidates: [inbox, project],
      inboxID: inbox.destination.noteID
    ) == .resolved(project.destination.noteID))
    #expect(fixture.transport.startCount == 1)
  }

  @Test @MainActor
  func compositionExactTitleMatchStartsNoSemanticHelper() async {
    let fixture = CompositionFixture(phase: .installed, verified: true)
    let inbox = compositionCandidate(title: "Inbox")
    let chemistry = compositionCandidate(title: "Chemistry", context: "Lab reports")
    let foundation = CompositionDestinationRouterProbe(result: .resolved(inbox.destination.noteID))
    let composition = fixture.makeComposition(foundationRouter: foundation)

    #expect(await composition.destinationRouter.route(
      transcript: "Save this chemistry note.",
      candidates: [inbox, chemistry],
      inboxID: inbox.destination.noteID
    ) == .resolved(chemistry.destination.noteID))
    #expect(await foundation.callCount == 0)
    #expect(fixture.transport.startCount == 0)
  }

  @Test @MainActor
  func compositionPrefersAvailableFoundationRouterWithoutStartingLocalHelper() async {
    let fixture = CompositionFixture(phase: .installed, verified: true)
    let availability = BoolProbe(true)
    let inbox = compositionCandidate(title: "Inbox")
    let project = compositionCandidate(title: "Project Delta", context: "Launch plans and deadlines")
    let foundation = CompositionDestinationRouterProbe(result: .resolved(project.destination.noteID))
    let composition = fixture.makeComposition(
      foundationIsAvailable: { availability.value },
      foundationRouter: foundation
    )

    #expect(await composition.destinationRouter.route(
      transcript: "Prepare the launch checklist",
      candidates: [inbox, project],
      inboxID: inbox.destination.noteID
    ) == .resolved(project.destination.noteID))
    #expect(await foundation.callCount == 1)
    #expect(fixture.transport.startCount == 0)
  }

  @Test @MainActor
  func unavailableGemmaCompositionRoutesToInboxWithoutStartingHelper() async {
    let fixture = CompositionFixture(phase: .notInstalled, verified: false)
    let inbox = compositionCandidate(title: "Inbox")
    let project = compositionCandidate(title: "Project Delta", context: "Launch plans and deadlines")
    let composition = fixture.makeComposition()

    #expect(await composition.destinationRouter.route(
      transcript: "Prepare the launch checklist",
      candidates: [inbox, project],
      inboxID: inbox.destination.noteID
    ) == .inbox)
    #expect(fixture.transport.startCount == 0)
  }

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
    guard await fixture.waitForPresentation(composition, .installed) else { return }
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
  func shutdownDisablesImmediatelyAndDrainsAcknowledgedRouteLease() async throws {
    let fixture = CompositionFixture(
      phase: .installed,
      verified: true,
      blocksAcknowledgement: true
    )
    let composition = fixture.makeComposition()
    let inbox = compositionCandidate(title: "Inbox")
    let project = compositionCandidate(title: "Project Delta", context: "Launch plans")
    fixture.transport.responseText = "high:c1"
    let result = Task {
      await composition.destinationRouter.route(
        transcript: "Prepare the launch checklist",
        candidates: [inbox, project],
        inboxID: inbox.destination.noteID
      )
    }
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
    #expect(await result.value == .resolved(project.destination.noteID))
    await shutdown.value
    #expect(drained.isFinished)
    #expect(fixture.installer.cancelCount == 1)
  }

  @Test @MainActor
  func modelMutationCallbackDisablesImmediatelyAndDrainsAcknowledgedRouteLease() async throws {
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
      foundationRouter: InboxRouter(),
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
    let inbox = compositionCandidate(title: "Inbox")
    let project = compositionCandidate(title: "Project Delta", context: "Launch plans")
    fixture.transport.responseText = "high:c1"
    let result = Task {
      await composition.destinationRouter.route(
        transcript: "Prepare the launch checklist",
        candidates: [inbox, project],
        inboxID: inbox.destination.noteID
      )
    }
    await fixture.transport.waitUntilAcknowledgement()

    let drained = CompletionProbe()
    let modelMutation = Task {
      await mutation.run()
      drained.finish()
    }
    for _ in 0..<1_000 where composition.isGemmaReady {
      await Task.yield()
    }

    #expect(!composition.isGemmaReady)
    #expect(!drained.isFinished)
    do {
      let unexpectedSession = try composition.cleanupGenerator.start(
        cleanupRequest(),
        maximumOutputTokens: 24
      )
      unexpectedSession.forceTerminate()
      Issue.record("Expected Gemma to be unavailable during model mutation")
    } catch {
      #expect(error as? DynamicCleanupGeneratorError == .gemmaUnavailable)
    }

    fixture.transport.releaseAcknowledgement()
    #expect(await result.value == .resolved(project.destination.noteID))
    await modelMutation.value
    #expect(drained.isFinished)
  }

  @Test @MainActor
  func mutationSuppressionRequiresNonInstalledBeforeFreshInstalledReopens() async throws {
    let fixture = CompositionFixture(
      phase: .installed,
      verified: true,
      publicationDelay: .milliseconds(20)
    )
    let mutation = MutationCallbackProbe()
    let composition = fixture.makeActivatedComposition(mutation: mutation)

    await mutation.run()
    fixture.installer.publish(phase: .installed)
    guard await fixture.drainPresentationUpdates() else { return }
    #expect(throws: DynamicCleanupGeneratorError.gemmaUnavailable) {
      _ = try composition.cleanupGenerator.start(cleanupRequest(), maximumOutputTokens: 24)
    }

    fixture.installer.publish(phase: .removing)
    #expect(composition.settingsViewModel.presentation.phase == .installed)
    guard await fixture.waitForPresentation(composition, .removing) else { return }
    #expect(throws: DynamicCleanupGeneratorError.gemmaUnavailable) {
      _ = try composition.cleanupGenerator.start(cleanupRequest(), maximumOutputTokens: 24)
    }

    fixture.installer.publish(phase: .installed)
    guard await fixture.waitForPresentation(composition, .installed) else { return }
    let session = try composition.cleanupGenerator.start(
      cleanupRequest(),
      maximumOutputTokens: 24
    )
    #expect(try await session.result().cleaned == "gemma")
  }

  @Test @MainActor
  func disableAndShutdownKeepLateInstalledPublicationsClosed() async {
    let disabledFixture = CompositionFixture(phase: .installed, verified: true)
    let disabledComposition = disabledFixture.makeComposition()

    disabledComposition.disable()
    disabledFixture.installer.publish(phase: .removing)
    guard await disabledFixture.waitForPresentation(disabledComposition, .removing) else { return }
    disabledFixture.installer.publish(phase: .installed)
    guard await disabledFixture.waitForPresentation(disabledComposition, .installed) else { return }
    #expect(throws: DynamicCleanupGeneratorError.gemmaUnavailable) {
      _ = try disabledComposition.cleanupGenerator.start(
        cleanupRequest(),
        maximumOutputTokens: 24
      )
    }

    let shutdownFixture = CompositionFixture(phase: .installed, verified: true)
    let shutdownComposition = shutdownFixture.makeComposition()
    await shutdownComposition.shutdown()
    shutdownFixture.installer.publish(phase: .removing)
    guard await shutdownFixture.waitForPresentation(shutdownComposition, .removing) else { return }
    shutdownFixture.installer.publish(phase: .installed)
    guard await shutdownFixture.waitForPresentation(shutdownComposition, .installed) else { return }
    #expect(throws: DynamicCleanupGeneratorError.gemmaUnavailable) {
      _ = try shutdownComposition.cleanupGenerator.start(
        cleanupRequest(),
        maximumOutputTokens: 24
      )
    }
  }

  @Test @MainActor
  func cleanupUsesStableTruthfulFallbackLabel() {
    let fixture = CompositionFixture(phase: .builtIn, verified: false)
    let composition = fixture.makeComposition(foundationIsAvailable: { true })

    #expect(composition.settingsViewModel.presentation.modelLabel == "Faithful Local Fallback")
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

  @Test @MainActor
  func cleanupPresentationTransitionsRefreshRuntimeAvailability() async throws {
    let fixture = try await CleanupAvailabilityRuntimeFixture()
    defer { fixture.removeTemporaryFiles() }

    #expect(!fixture.runtime.availability.cleanupAvailable)
    #expect(fixture.runtime.availability.routing == .exactTitle)

    fixture.cleanupReady.value = true
    fixture.installer.publish(phase: .installed)
    await fixture.drainPresentationUpdates()
    #expect(fixture.runtime.availability.cleanupAvailable)
    #expect(fixture.runtime.availability.routing == .exactTitle)

    fixture.cleanupReady.value = false
    fixture.installer.publish(phase: .repairRequired(message: "Verification failed"))
    await fixture.drainPresentationUpdates()
    #expect(!fixture.runtime.availability.cleanupAvailable)
    #expect(fixture.runtime.availability.routing == .exactTitle)

    await fixture.runtime.shutdown()
  }

  @Test
  func exactTitleSmartCaptureRemainsAvailableWithVerifiedLocalCleanup() {
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
    #expect(availability.routing == .exactTitle)
    #expect(compatibility.cleanup.detail == "Available")
    #expect(compatibility.cleanup.available)
    #expect(compatibility.smartCapture.available)
  }

  @Test @MainActor
  func localRoutingAvailabilityRequiresOperationalComposition() {
    let fixture = CompositionFixture(phase: .installed, verified: true)
    let composition = fixture.makeComposition()
    let input: (Bool) -> DictationAvailability.Input = { localRoutingReady in
      .init(
        osMajorVersion: 14,
        architecture: .appleSilicon,
        microphonePermission: .authorized,
        speechPermission: .authorized,
        appleOnDeviceRecognitionSupported: true,
        enhancedModelReady: false,
        foundationModelAvailability: .unsupportedOS,
        cleanupModelReady: composition.isGemmaReady,
        localRoutingModelReady: localRoutingReady
      )
    }

    #expect(DictationAvailability.evaluate(input(composition.isLocalRoutingReady)).routing == .localModel)
    composition.disable()
    #expect(!composition.isLocalRoutingReady)
    #expect(DictationAvailability.evaluate(input(composition.isLocalRoutingReady)).routing == .exactTitle)
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
  private var presentationDelivery: CompositionPresentationDelivery?
  private var initialPresentationPhase: AdmittedModelInstallPhase?
  private var acknowledgedInitialPresentation = false

  init(
    phase: AdmittedModelInstallPhase,
    verified: Bool,
    blocksAcknowledgement: Bool = false,
    publicationDelay: Duration? = nil
  ) {
    installer = CompositionInstaller(phase: phase, publicationDelay: publicationDelay)
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
    foundationRouter: any DestinationRouting = InboxRouter(),
    prepareForGeneration: @escaping @Sendable () async throws -> Void = {}
  ) -> GemmaCleanupCandidateComposition {
    let composition = GemmaCleanupCandidateComposition(
      activation: activation,
      foundationIsAvailable: foundationIsAvailable,
      foundationGenerator: foundationGenerator,
      foundationRouter: foundationRouter,
      prepareForGeneration: prepareForGeneration,
      verifiedLoadState: { [weak self] in
        self?.verifiedRepositoryURL.map(EnhancedModelVerifiedLoadState.ready) ?? .unavailable
      }
    )
    observePresentationDelivery(from: composition)
    return composition
  }

  func makeActivatedComposition(
    mutation: MutationCallbackProbe
  ) -> GemmaCleanupCandidateComposition {
    let activation = activation
    let composition = GemmaCleanupCandidateComposition(
      applicationSupportURL: URL(fileURLWithPath: "/tmp/fleck-app-support"),
      foundationIsAvailable: { false },
      foundationGenerator: CleanupGeneratorProbe(text: "foundation"),
      foundationRouter: InboxRouter(),
      prepareForGeneration: {},
      verifiedLoadState: { [weak self] in
        self?.verifiedRepositoryURL.map(EnhancedModelVerifiedLoadState.ready)
          ?? .unavailable
      },
      makeActivation: { _, callback in
        mutation.install(callback)
        return activation
      }
    )
    observePresentationDelivery(from: composition)
    return composition
  }

  var activation: GemmaCleanupTestActivation.Result {
    GemmaCleanupTestActivation.Result(
      manager: manager,
      installer: installer,
      helperExecutableURL: URL(fileURLWithPath: "/tmp/gemma-cleanup-helper"),
      makeTransport: { [transport] _ in transport }
    )
  }

  @discardableResult
  func waitForPresentation(
    _ composition: GemmaCleanupCandidateComposition,
    _ phase: AdmittedModelInstallPhase
  ) async -> Bool {
    guard let deliveredPhase = await nextPresentationPublication() else {
      return false
    }
    guard deliveredPhase == phase else {
      Issue.record("Expected next presentation phase \(phase), received \(deliveredPhase)")
      return false
    }
    guard composition.settingsViewModel.presentation.phase == phase else {
      Issue.record("Presentation publication arrived before the phase was observable")
      return false
    }
    return true
  }

  @discardableResult
  func drainPresentationUpdates() async -> Bool {
    guard let composition else {
      Issue.record("Composition presentation observer is not installed")
      return false
    }
    return await waitForPresentation(composition, installer.snapshot.phase)
  }

  private weak var composition: GemmaCleanupCandidateComposition?

  private func observePresentationDelivery(from composition: GemmaCleanupCandidateComposition) {
    self.composition = composition
    initialPresentationPhase = composition.settingsViewModel.presentation.phase
    presentationDelivery = CompositionPresentationDelivery(composition.settingsViewModel)
  }

  private func nextPresentationPublication() async -> AdmittedModelInstallPhase? {
    guard let presentationDelivery else { return nil }
    if !acknowledgedInitialPresentation {
      guard let deliveredInitial = await presentationDelivery.next() else {
        Issue.record("Timed out waiting for the initial presentation delivery")
        return nil
      }
      guard deliveredInitial == initialPresentationPhase else {
        Issue.record(
          "Expected initial presentation phase \(String(describing: initialPresentationPhase)), received \(deliveredInitial)"
        )
        return nil
      }
      acknowledgedInitialPresentation = true
    }
    guard let publication = await presentationDelivery.next() else {
      Issue.record("Timed out waiting for the next presentation publication")
      return nil
    }
    return publication
  }
}

@MainActor
private final class CompositionPresentationDelivery {
  private var buffered: [AdmittedModelInstallPhase] = []
  private var waiter: CheckedContinuation<AdmittedModelInstallPhase?, Never>?
  private var timeoutTask: Task<Void, Never>?
  private var cancellable: AnyCancellable?

  init(_ viewModel: AdmittedModelSettingsViewModel) {
    cancellable = viewModel.$presentation.dropFirst().sink { [weak self] presentation in
      self?.receive(presentation.phase)
    }
  }

  func next() async -> AdmittedModelInstallPhase? {
    if !buffered.isEmpty { return buffered.removeFirst() }
    return await withCheckedContinuation { continuation in
      waiter = continuation
      timeoutTask = Task { @MainActor [weak self] in
        do {
          try await Task.sleep(for: .seconds(1))
        } catch {
          return
        }
        guard !Task.isCancelled else { return }
        self?.timeOut()
      }
    }
  }

  private func receive(_ phase: AdmittedModelInstallPhase) {
    guard let waiter else {
      buffered.append(phase)
      return
    }
    self.waiter = nil
    timeoutTask?.cancel()
    timeoutTask = nil
    waiter.resume(returning: phase)
  }

  private func timeOut() {
    guard let waiter else { return }
    self.waiter = nil
    timeoutTask = nil
    waiter.resume(returning: nil)
  }
}

@MainActor
private final class CleanupAvailabilityRuntimeFixture {
  let root: URL
  let installer = CompositionInstaller(phase: .notInstalled)
  let cleanupReady = BoolProbe(false)
  let runtime: DictationRuntime

  init() async throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("cleanup-availability-runtime-" + UUID().uuidString)
    let appState = AppState(
      store: LocalStore(rootURL: root),
      saveOperation: { _, _, _ in }
    )
    await appState.waitUntilInitialLoad()
    let provider = UnavailableEngineProvider()
    let history = DictationHistoryController(
      load: { [] },
      save: { _ in },
      delete: { _ in },
      clear: {}
    )
    let admittedSettings = AdmittedModelSettingsViewModel(
      installer: BuiltInAdmittedModelInstaller()
    )
    let cleanupSettings = AdmittedModelSettingsViewModel(
      installer: installer,
      context: .cleanup(fallbackLabel: "Faithful Local Fallback")
    )
    let coordinator = DictationCoordinator(
      engineProvider: provider,
      preferredEngine: { .standard },
      cleaner: IdentityCleaner(),
      router: InboxRouter(),
      saver: appState,
      historyController: history,
      historyEnabled: { true }
    )
    let shortcut = GlobalHoldShortcut(
      handler: coordinator,
      monitor: InertModifierMonitor(),
      escapeRegistrar: InertEscapeRegistrar()
    )
    let ready = cleanupReady
    runtime = DictationRuntime(
      appState: appState,
      modelManager: DictationModelCapability(
        modelRootURL: root.appendingPathComponent("model", isDirectory: true),
        candidateEnabled: true,
        architectureProvider: { true }
      ),
      engineProvider: provider,
      coordinator: coordinator,
      shortcutController: shortcut,
      capsuleController: DictationCapsuleController(),
      historyController: history,
      permissionController: DictationPermissionController(),
      editorRegistry: DictationEditorRegistry(),
      startupAssessment: {},
      admittedModelSettingsViewModel: admittedSettings,
      cleanupAdmittedModelSettingsViewModel: cleanupSettings,
      availabilityProvider: {
        DictationAvailability.evaluate(.init(
          osMajorVersion: 14,
          architecture: .appleSilicon,
          microphonePermission: .authorized,
          speechPermission: .authorized,
          appleOnDeviceRecognitionSupported: true,
          enhancedModelReady: false,
          foundationModelAvailability: .unsupportedOS,
          cleanupModelReady: ready.value
        ))
      },
      cleanupModelReady: { _ in ready.value }
    )
    await runtime.awaitStartupAssessment()
  }

  func drainPresentationUpdates() async {
    for _ in 0..<100 {
      await Task.yield()
    }
  }

  func removeTemporaryFiles() {
    try? FileManager.default.removeItem(at: root)
  }
}

@MainActor
private final class CompositionInstaller: AdmittedModelInstalling {
  private(set) var snapshot: AdmittedModelInstallationSnapshot
  let updates: AsyncStream<AdmittedModelInstallationSnapshot>
  private let continuation: AsyncStream<AdmittedModelInstallationSnapshot>.Continuation
  private let publicationDelay: Duration?
  private(set) var cancelCount = 0

  init(phase: AdmittedModelInstallPhase, publicationDelay: Duration? = nil) {
    let pair = AsyncStream<AdmittedModelInstallationSnapshot>.makeStream()
    updates = pair.stream
    continuation = pair.continuation
    self.publicationDelay = publicationDelay
    snapshot = .init(
      recommendation: phase == .builtIn
        ? .builtIn
        : .recommended(TestDescriptors.tinyAdmittedASR),
      phase: phase,
      lastError: nil
    )
    deliver(snapshot)
  }

  func publish(phase: AdmittedModelInstallPhase) {
    snapshot = .init(
      recommendation: snapshot.recommendation,
      phase: phase,
      lastError: nil
    )
    deliver(snapshot)
  }

  private func deliver(_ snapshot: AdmittedModelInstallationSnapshot) {
    guard let publicationDelay else {
      continuation.yield(snapshot)
      return
    }
    Task { [continuation] in
      try? await Task.sleep(for: publicationDelay)
      continuation.yield(snapshot)
    }
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

private actor CompositionDestinationRouterProbe: DestinationRouting {
  let result: DictationRoutingDecision
  private(set) var callCount = 0

  init(result: DictationRoutingDecision) {
    self.result = result
  }

  func route(
    transcript _: String,
    candidates _: [DictationRoutingCandidate],
    inboxID _: UUID?
  ) async -> DictationRoutingDecision {
    callCount += 1
    return result
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

@MainActor
private final class UnavailableEngineProvider: SpeechEngineProviding {
  func engineForCapture(preferred _: DictationSpeechEngine) async throws -> any SpeechEngine {
    throw DictationFailure.unavailable
  }
}

private struct IdentityCleaner: TranscriptCleaning {
  func clean(_ rawTranscript: String) async throws -> String { rawTranscript }
}

private struct InboxRouter: DestinationRouting {
  func route(
    transcript _: String,
    candidates _: [DictationRoutingCandidate],
    inboxID _: UUID?
  ) async -> DictationRoutingDecision {
    .inbox
  }
}

@MainActor
private final class InertModifierMonitor: ModifierKeyMonitoring {
  var transitionHandler: ((ModifierKeyTransition) -> Void)?
  var stateHandler: ((ModifierMonitorState) -> Void)?
  let accessGranted = true

  func start() { stateHandler?(.running) }
  func stop() { stateHandler?(.stopped) }
  func requestAccess() -> Bool { true }
}

@MainActor
private final class InertEscapeRegistrar: EscapeHotKeyRegistering {
  var eventHandler: (() -> Void)?
  func register() {}
  func unregister() {}
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
  var responseText = "gemma"

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
    session.complete(text: responseText)
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

  func complete(text: String) {
    let requestID = terminationExpectation.cleanupRequestID
    let rawText = String(decoding: try! JSONEncoder().encode(["text": text]), as: UTF8.self)
    let quotedRawText = String(decoding: try! JSONEncoder().encode(rawText), as: UTF8.self)
    continuation.yield(Data(#"{"schemaVersion":1,"kind":"started","requestID":"\#(requestID)"}"#.utf8))
    continuation.yield(Data(#"{"schemaVersion":1,"kind":"completed","requestID":"\#(requestID)","rawText":\#(quotedRawText)}"#.utf8))
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

private func compositionCandidate(
  title: String,
  context: String = ""
) -> DictationRoutingCandidate {
  .init(
    destination: .init(noteID: UUID(), title: title),
    semanticContext: context
  )
}
#endif
