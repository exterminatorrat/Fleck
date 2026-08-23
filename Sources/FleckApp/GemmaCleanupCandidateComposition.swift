#if os(macOS) && CLEAN_DICTATION_ENHANCED_CANDIDATE
import Combine
import Foundation

@MainActor
final class GemmaCleanupCandidateComposition {
  private enum LifecycleState: Equatable {
    case operational
    case mutationSuppressed
    case shutDown
  }

  typealias ActivationFactory = @MainActor (
    URL,
    @escaping @Sendable () async -> Void
  ) -> GemmaCleanupTestActivation.Result

  let modelManager: EnhancedModelManager
  let installer: any AdmittedModelInstalling
  let settingsViewModel: AdmittedModelSettingsViewModel
  let cleanupGenerator: DynamicCleanupGenerator

  private let gate: GemmaCleanupLeaseGate
  private let verifiedLoadState: @MainActor () -> EnhancedModelVerifiedLoadState
  private let makeGemmaGenerator: @MainActor (URL) -> GemmaCleanupGenerator
  private var lifecycleState = LifecycleState.operational
  private var presentationSubscription: AnyCancellable?

  convenience init(
    applicationSupportURL: URL,
    foundationIsAvailable: @escaping @Sendable () -> Bool,
    foundationGenerator: any BoundedCleanupGenerating,
    prepareForGeneration: @escaping @Sendable () async throws -> Void,
    verifiedLoadState: (@MainActor () -> EnhancedModelVerifiedLoadState)? = nil,
    makeActivation: ActivationFactory = { applicationSupportURL, mutation in
      GemmaCleanupTestActivation.make(
        applicationSupportURL: applicationSupportURL,
        modelMutationWillBegin: mutation
      )
    }
  ) {
    let gate = GemmaCleanupLeaseGate()
    let mutationRelay = GemmaCleanupMutationRelay()
    let activation = makeActivation(applicationSupportURL) {
      await mutationRelay.beginMutation()
    }
    self.init(
      activation: activation,
      foundationIsAvailable: foundationIsAvailable,
      foundationGenerator: foundationGenerator,
      prepareForGeneration: prepareForGeneration,
      gate: gate,
      verifiedLoadState: verifiedLoadState
    )
    mutationRelay.composition = self
  }

  init(
    activation: GemmaCleanupTestActivation.Result,
    foundationIsAvailable: @escaping @Sendable () -> Bool,
    foundationGenerator: any BoundedCleanupGenerating,
    prepareForGeneration: @escaping @Sendable () async throws -> Void,
    gate: GemmaCleanupLeaseGate = GemmaCleanupLeaseGate(),
    verifiedLoadState: (@MainActor () -> EnhancedModelVerifiedLoadState)? = nil
  ) {
    let settingsViewModel = AdmittedModelSettingsViewModel(
      installer: activation.installer,
      context: .cleanup(fallbackLabel: "Faithful Local Fallback")
    )
    let makeTransport = activation.makeTransport
    self.modelManager = activation.manager
    self.installer = activation.installer
    self.settingsViewModel = settingsViewModel
    self.gate = gate
    self.verifiedLoadState = verifiedLoadState ?? { [weak manager = activation.manager] in
      manager?.verifiedLoadState ?? .unavailable
    }
    self.makeGemmaGenerator = { repositoryURL in
      GemmaCleanupGenerator(
        transportFactory: { makeTransport(repositoryURL) },
        prepareForGeneration: prepareForGeneration
      )
    }
    cleanupGenerator = DynamicCleanupGenerator(
      foundationIsAvailable: foundationIsAvailable,
      foundationGenerator: foundationGenerator,
      gemmaGate: gate
    )
    presentationSubscription = settingsViewModel.$presentation.sink { [weak self] presentation in
      self?.reconcileGate(presentation)
    }
    reconcileGate()
  }

  var isGemmaReady: Bool {
    isGemmaReady(for: settingsViewModel.presentation)
  }

  func isGemmaReady(for presentation: AdmittedModelSettingsPresentation) -> Bool {
    guard lifecycleState == .operational else { return false }
    guard presentation.phase == .installed else { return false }
    guard case .ready = verifiedLoadState() else { return false }
    return true
  }

  func reconcileGate() {
    reconcileGate(settingsViewModel.presentation)
  }

  private func reconcileGate(_ presentation: AdmittedModelSettingsPresentation) {
    switch lifecycleState {
    case .shutDown:
      gate.disable()
      return
    case .mutationSuppressed:
      guard presentation.phase != .installed else {
        gate.disable()
        return
      }
      lifecycleState = .operational
      gate.disable()
      return
    case .operational:
      break
    }
    guard presentation.phase == .installed,
          case .ready(let repositoryURL) = verifiedLoadState() else {
      gate.disable()
      return
    }
    gate.enable(makeGemmaGenerator(repositoryURL))
  }

  func refresh() async {
    await settingsViewModel.refresh()
    reconcileGate()
  }

  func disable() {
    enterShutdown()
  }

  func shutdown() async {
    enterShutdown()
    installer.cancel()
    await gate.disableAndWait()
  }

  fileprivate func beginMutation() async {
    if lifecycleState != .shutDown {
      lifecycleState = .mutationSuppressed
    }
    await gate.disableAndWait()
  }

  private func enterShutdown() {
    lifecycleState = .shutDown
    presentationSubscription?.cancel()
    presentationSubscription = nil
    gate.disable()
  }

  isolated deinit {
    gate.disable()
  }
}

@MainActor
private final class GemmaCleanupMutationRelay {
  weak var composition: GemmaCleanupCandidateComposition?

  func beginMutation() async {
    await composition?.beginMutation()
  }
}
#endif
