#if os(macOS) && CLEAN_DICTATION_ENHANCED_CANDIDATE
import Combine
import Foundation

@MainActor
final class GemmaCleanupCandidateComposition {
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
    let activation = makeActivation(applicationSupportURL) {
      await gate.disableAndWait()
    }
    self.init(
      activation: activation,
      foundationIsAvailable: foundationIsAvailable,
      foundationGenerator: foundationGenerator,
      prepareForGeneration: prepareForGeneration,
      gate: gate,
      verifiedLoadState: verifiedLoadState
    )
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
      context: .cleanup(
        fallbackLabel: foundationIsAvailable()
          ? "Apple On-Device"
          : "Deterministic Fallback"
      )
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
    guard settingsViewModel.presentation.phase == .installed else { return false }
    guard case .ready = verifiedLoadState() else { return false }
    return true
  }

  func reconcileGate() {
    reconcileGate(settingsViewModel.presentation)
  }

  private func reconcileGate(_ presentation: AdmittedModelSettingsPresentation) {
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
    gate.disable()
  }

  func shutdown() async {
    installer.cancel()
    await gate.disableAndWait()
  }

  isolated deinit {
    gate.disable()
  }
}
#endif
