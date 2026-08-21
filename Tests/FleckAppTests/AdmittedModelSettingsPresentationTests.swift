import Foundation
import Testing

@testable import FleckApp

private enum AdmittedModelSettingsTestDescriptors {
  static let tinyAdmittedASR: AdmittedModelDescriptor = {
    #if CLEAN_DICTATION_ENHANCED_CANDIDATE
      return TestDescriptors.tinyAdmittedASR
    #else
      return try! AdmittedModelDescriptor(validating: RawAdmittedModelDescriptor(
        role: .asr,
        modelID: "example/tiny",
        revision: "tiny-revision",
        runtimeABI: "runtime",
        conversion: "conversion",
        quantization: "quantized",
        license: "license",
        notices: "notices",
        source: URL(string: "https://example.invalid/repository")!,
        files: [
          .init(
            path: "model.bin",
            byteCount: Int64(TestFixtures.tinyBytes.count),
            sha256: TestFixtures.tinySHA256
          )
        ],
        downloadBytes: Int64(TestFixtures.tinyBytes.count),
        installedBytes: 16,
        languages: ["en-US"],
        architectures: ["arm64"]
      ))
    #endif
  }()
}

@Test func builtInStateHasNoInstallActionOrPicker() {
  let presentation = AdmittedModelSettingsPresentation(
    snapshot: .init(
      recommendation: .builtIn,
      phase: .builtIn,
      lastError: nil
    )
  )
  #expect(presentation.primaryAction == nil)
  #expect(presentation.primaryActionLabel == nil)
  #expect(presentation.detail.contains("No custom model is installed"))
  #expect(presentation.detail.contains("On-device recognition"))
  #expect(presentation.detail.contains("Apple Speech"))
  #expect(presentation.accessibilityLabel == "Dictation model")
  #expect(presentation.accessibilityValue == "Apple Speech, Built in")
}

@Test func builtInFailureRemainsFailClosedWithoutRetryAction() {
  let presentation = AdmittedModelSettingsPresentation(
    snapshot: .init(
      recommendation: .builtIn,
      phase: .failed(message: "invalid signed configuration"),
      lastError: "invalid signed configuration"
    )
  )

  #expect(presentation.primaryAction == nil)
  #expect(presentation.primaryActionLabel == nil)
}

@Test func modelLabelNamesCandidateAndBuiltInFallback() {
  let recommended = AdmittedModelSettingsPresentation(
    snapshot: .init(
      recommendation: .recommended(AdmittedModelSettingsTestDescriptors.tinyAdmittedASR),
      phase: .notInstalled,
      lastError: nil
    )
  )
  let builtIn = AdmittedModelSettingsPresentation(
    snapshot: .init(
      recommendation: .builtIn,
      phase: .builtIn,
      lastError: nil
    )
  )

  #expect(recommended.modelLabel == "Parakeet TDT 0.6B v2")
  #expect(builtIn.modelLabel == "Apple Speech")
}

@Test func ordinaryStatesStayCompactWithOnlyRelevantActions() {
  let descriptor = AdmittedModelSettingsTestDescriptors.tinyAdmittedASR
  let presentations: [(AdmittedModelSettingsPresentation, AdmittedModelSettingsAction?)] = [
    (
      AdmittedModelSettingsPresentation(
        snapshot: .init(recommendation: .builtIn, phase: .builtIn, lastError: nil)
      ),
      nil
    ),
    (
      AdmittedModelSettingsPresentation(
        snapshot: .init(recommendation: .recommended(descriptor), phase: .notInstalled, lastError: nil)
      ),
      .install
    ),
    (
      AdmittedModelSettingsPresentation(
        snapshot: .init(recommendation: .recommended(descriptor), phase: .installed, lastError: nil)
      ),
      .remove
    ),
  ]

  for (presentation, action) in presentations {
    #expect(!presentation.showsStatus)
    #expect(!presentation.showsDetail)
    #expect(presentation.primaryAction == action)
  }
}

@Test func onlyActionableExceptionalStatesExposeDetailedCopy() {
  let descriptor = AdmittedModelSettingsTestDescriptors.tinyAdmittedASR
  let expectations: [(AdmittedModelInstallPhase, Bool, Bool)] = [
    (.builtIn, false, false),
    (.notInstalled, false, false),
    (.downloading(receivedBytes: 1, totalBytes: 2), true, false),
    (.verifying, true, false),
    (.installing, true, false),
    (.ready, true, false),
    (.starting, true, false),
    (.calibrating, true, false),
    (.installed, false, false),
    (.updateAvailable, true, false),
    (.repairRequired(message: "repair required"), true, true),
    (.removing, true, false),
    (.cancelled, true, true),
    (.failed(message: "failed"), true, true),
  ]

  for (phase, showsStatus, showsDetail) in expectations {
    let recommendation: AdmittedModelRecommendation = phase == .builtIn
      ? .builtIn
      : .recommended(descriptor)
    let presentation = AdmittedModelSettingsPresentation(
      snapshot: .init(recommendation: recommendation, phase: phase, lastError: nil)
    )
    #expect(presentation.showsStatus == showsStatus)
    #expect(presentation.showsDetail == showsDetail)
  }
}

@Test func recommendationHasExplicitInstallWithoutTechnicalMetadata() {
  let descriptor = AdmittedModelSettingsTestDescriptors.tinyAdmittedASR
  let presentation = AdmittedModelSettingsPresentation(
    snapshot: .init(
      recommendation: .recommended(descriptor),
      phase: .notInstalled,
      lastError: nil
    )
  )
  #expect(presentation.primaryAction == .install)
  #expect(presentation.primaryActionLabel == "Install")
  #expect(presentation.identity == descriptor.modelID)
  #expect(!presentation.detail.contains(descriptor.revision))
  #expect(!presentation.detail.contains(descriptor.license))
  #expect(!presentation.detail.contains(String(descriptor.downloadBytes)))
  #expect(!presentation.detail.contains(String(descriptor.installedBytes)))
  #expect(!presentation.accessibilityValue.contains(descriptor.revision))
  #expect(!presentation.accessibilityValue.contains(descriptor.architectures.joined(separator: ", ")))
  #expect(!presentation.accessibilityValue.contains(descriptor.languages.joined(separator: ", ")))
}

@Test func recommendationCardHasConciseVoiceOverCopyAndKeyboardFocus() {
  let descriptor = AdmittedModelSettingsTestDescriptors.tinyAdmittedASR
  let presentation = AdmittedModelSettingsPresentation(
    snapshot: .init(
      recommendation: .recommended(descriptor),
      phase: .notInstalled,
      lastError: nil
    )
  )
  #expect(presentation.accessibilityLabel == "Dictation model")
  #expect(presentation.accessibilityValue == "Parakeet TDT 0.6B v2, Available to install")
  #expect(!presentation.detail.contains("Supported architectures"))
  #expect(!presentation.detail.contains("Supported languages"))
  #expect(!presentation.detail.contains("Checksums"))
  #expect(presentation.isKeyboardFocusable)
}

@Test func recommendedPhaseCopyUsesNeutralExperimentalCandidateLanguage() {
  let descriptor = AdmittedModelSettingsTestDescriptors.tinyAdmittedASR
  let expectations: [
    (phase: AdmittedModelInstallPhase, detail: String)
  ] = [
    (
      .notInstalled,
      "The experimental enhanced local model candidate is available to install."
    ),
    (
      .downloading(receivedBytes: 4, totalBytes: 8),
      "Downloading the experimental enhanced local model candidate."
    ),
    (
      .verifying,
      "Verifying the downloaded experimental enhanced local model candidate."
    ),
    (
      .installing,
      "Installing the verified experimental enhanced local model candidate."
    ),
    (
      .ready,
      "The experimental enhanced local model candidate is prepared to start."
    ),
    (
      .starting,
      "Starting the experimental enhanced local model candidate."
    ),
    (
      .calibrating,
      "Calibrating the experimental enhanced local model candidate."
    ),
    (
      .installed,
      "The experimental enhanced local model candidate is installed and available."
    ),
    (
      .updateAvailable,
      "An update is available for the experimental enhanced local model candidate."
    ),
    (
      .repairRequired(message: "repair required"),
      "The experimental enhanced local model candidate needs repair: repair required"
    ),
    (
      .removing,
      "Removing the experimental enhanced local model candidate and returning to Apple Speech."
    ),
    (
      .cancelled,
      "Experimental enhanced local model candidate installation was cancelled."
    ),
    (
      .failed(message: "failed"),
      "Enhanced local dictation failed: failed"
    ),
  ]

  for expectation in expectations {
    let presentation = AdmittedModelSettingsPresentation(
      snapshot: .init(
        recommendation: .recommended(descriptor),
        phase: expectation.phase,
        lastError: nil
      )
    )

    #expect(presentation.detail.hasPrefix(expectation.detail))
    #expect(presentation.accessibilityLabel == "Dictation model")
    #expect(!presentation.detail.localizedCaseInsensitiveContains("admitted model"))
    #expect(!presentation.accessibilityLabel.localizedCaseInsensitiveContains("admitted model"))
    #expect(!presentation.accessibilityValue.localizedCaseInsensitiveContains("admitted model"))
  }
}

@Test func noRecommendationStatesRemainWithoutModelIdentity() {
  for phase in [AdmittedModelInstallPhase.builtIn,
                .failed(message: "invalid signed configuration")] {
    let presentation = AdmittedModelSettingsPresentation(
      snapshot: .init(recommendation: .builtIn, phase: phase, lastError: nil)
    )
    #expect(presentation.identity == nil)
  }
}

@Test func recommendedFailureRetainsFallbackAndExposesRetry() {
  let descriptor = AdmittedModelSettingsTestDescriptors.tinyAdmittedASR
  let presentation = AdmittedModelSettingsPresentation(
    snapshot: .init(
      recommendation: .recommended(descriptor),
      phase: .failed(message: "startup failed"),
      lastError: "startup failed"
    )
  )
  #expect(presentation.identity == descriptor.modelID)
  #expect(presentation.primaryAction == .repair)
  #expect(presentation.primaryActionLabel == "Retry")
  #expect(presentation.detail.contains("Fleck continues with Apple Speech"))
  #expect(presentation.detail.contains("startup failed"))
  #expect(!presentation.detail.contains("restart Fleck"))
}

@Test func repairRequiredKeepsRepairLabelWhileFailedUsesRetry() {
  let descriptor = AdmittedModelSettingsTestDescriptors.tinyAdmittedASR
  let repairRequired = AdmittedModelSettingsPresentation(
    snapshot: .init(
      recommendation: .recommended(descriptor),
      phase: .repairRequired(message: "repair required"),
      lastError: nil
    )
  )
  let failed = AdmittedModelSettingsPresentation(
    snapshot: .init(
      recommendation: .recommended(descriptor),
      phase: .failed(message: "startup failed"),
      lastError: nil
    )
  )

  #expect(repairRequired.primaryAction == .repair)
  #expect(repairRequired.primaryActionLabel == "Repair")
  #expect(failed.primaryAction == .repair)
  #expect(failed.primaryActionLabel == "Retry")
}

@Test func readyKeepsCancellationAvailableUntilInstalled() {
  let descriptor = AdmittedModelSettingsTestDescriptors.tinyAdmittedASR
  let ready = AdmittedModelSettingsPresentation(
    snapshot: .init(
      recommendation: .recommended(descriptor),
      phase: .ready,
      lastError: nil
    )
  )
  let installed = AdmittedModelSettingsPresentation(
    snapshot: .init(
      recommendation: .recommended(descriptor),
      phase: .installed,
      lastError: nil
    )
  )

  #expect(ready.primaryAction == .cancel)
  #expect(ready.primaryActionLabel == "Cancel")
  #expect(installed.primaryAction == .remove)
  #expect(installed.primaryActionLabel == "Remove")
}

@Test func downloadingUsesTruthfulProgressAndVoiceOverValue() {
  let presentation = AdmittedModelSettingsPresentation(
    snapshot: .init(
      recommendation: .recommended(AdmittedModelSettingsTestDescriptors.tinyAdmittedASR),
      phase: .downloading(receivedBytes: 25, totalBytes: 100),
      lastError: nil
    )
  )
  #expect(presentation.progress == 0.25)
  #expect(presentation.progressAccessibilityValue == "25%")
  #expect(presentation.primaryAction == .cancel)
}

@Test func everySettingsPhaseHasFiniteActionableCopy() {
  let descriptor = AdmittedModelSettingsTestDescriptors.tinyAdmittedASR
  let phases: [AdmittedModelInstallPhase] = [
    .notInstalled,
    .downloading(receivedBytes: 4, totalBytes: 8),
    .verifying,
    .installing,
    .ready,
    .starting,
    .calibrating,
    .installed,
    .updateAvailable,
    .repairRequired(message: "repair required"),
    .removing,
    .cancelled,
    .failed(message: "failed")
  ]

  for phase in phases {
    let presentation = AdmittedModelSettingsPresentation(
      snapshot: .init(
        recommendation: .recommended(descriptor),
        phase: phase,
        lastError: nil
      )
    )
    #expect(!presentation.detail.isEmpty)
    #expect(!presentation.detail.contains("Loading"))
    #expect(!presentation.accessibilityValue.contains("Loading"))
  }
}

@Test func inProgressCardHasFinitePhaseAndProgressAccessibilityText() {
  let presentation = AdmittedModelSettingsPresentation(
    snapshot: .init(
      recommendation: .recommended(AdmittedModelSettingsTestDescriptors.tinyAdmittedASR),
      phase: .downloading(receivedBytes: 4, totalBytes: 8),
      lastError: nil
    )
  )
  #expect(presentation.accessibilityLabel == "Dictation model")
  #expect(presentation.accessibilityValue == "Parakeet TDT 0.6B v2, Downloading, 50%")
  #expect(presentation.progressAccessibilityValue == "50%")
  #expect(!presentation.accessibilityValue.contains("Loading"))
}

@Test func readyAndCancelledHaveFiniteSettingsCopy() {
  for phase in [AdmittedModelInstallPhase.ready, .cancelled] {
    let presentation = AdmittedModelSettingsPresentation(
      snapshot: .init(
        recommendation: .recommended(AdmittedModelSettingsTestDescriptors.tinyAdmittedASR),
        phase: phase,
        lastError: nil
      )
    )
    #expect(!presentation.detail.isEmpty)
    #expect(!presentation.detail.contains("Loading"))
  }
}

@MainActor
private final class InstallerActionProbe: AdmittedModelInstalling {
  private let holdsOperations: Bool
  private let continuation: AsyncStream<AdmittedModelInstallationSnapshot>.Continuation
  private var counts: [AdmittedModelSettingsAction: Int] = [:]
  private var startedActions = Set<AdmittedModelSettingsAction>()
  private var startWaiters: [(AdmittedModelSettingsAction, CheckedContinuation<Void, Never>)] = []
  private var phaseWaiters: [(AdmittedModelInstallPhase, CheckedContinuation<Void, Never>)] = []
  private var operationFinishedWaiters: [CheckedContinuation<Void, Never>] = []
  private var cancellationContinuation: CheckedContinuation<Void, Never>?

  private(set) var snapshot: AdmittedModelInstallationSnapshot
  private(set) var operationFinished = false
  let updates: AsyncStream<AdmittedModelInstallationSnapshot>

  private let refreshPhase: AdmittedModelInstallPhase?

  init(
    holdsOperations: Bool = false,
    refreshPhase: AdmittedModelInstallPhase? = nil
  ) {
    self.holdsOperations = holdsOperations
    self.refreshPhase = refreshPhase
    var continuation: AsyncStream<AdmittedModelInstallationSnapshot>.Continuation!
    updates = AsyncStream { continuation = $0 }
    self.continuation = continuation
    snapshot = .init(
      recommendation: .recommended(AdmittedModelSettingsTestDescriptors.tinyAdmittedASR),
      phase: .notInstalled,
      lastError: nil
    )
    continuation.yield(snapshot)
  }

  func count(_ action: AdmittedModelSettingsAction) -> Int {
    counts[action, default: 0]
  }

  func waitUntilStarted(_ action: AdmittedModelSettingsAction) async {
    guard !startedActions.contains(action) else { return }
    await withCheckedContinuation { continuation in
      if startedActions.contains(action) {
        continuation.resume()
      } else {
        startWaiters.append((action, continuation))
      }
    }
  }

  func waitUntilPhase(_ phase: AdmittedModelInstallPhase) async {
    guard snapshot.phase != phase else { return }
    await withCheckedContinuation { continuation in
      if snapshot.phase == phase {
        continuation.resume()
      } else {
        phaseWaiters.append((phase, continuation))
      }
    }
  }

  func waitUntilOperationFinished() async {
    guard !operationFinished else { return }
    await withCheckedContinuation { continuation in
      if operationFinished {
        continuation.resume()
      } else {
        operationFinishedWaiters.append(continuation)
      }
    }
  }

  func refresh() async {
    if let refreshPhase {
      publish(refreshPhase)
    }
  }

  func publishSequence(_ phases: [AdmittedModelInstallPhase]) {
    phases.forEach(publish)
  }

  func install() async {
    record(.install)
    started(.install)
    if holdsOperations {
      publish(.downloading(receivedBytes: 0, totalBytes: 100))
      await withCheckedContinuation { cancellationContinuation = $0 }
    } else {
      publish(.ready)
    }
    operationFinished = true
    let waiters = operationFinishedWaiters
    operationFinishedWaiters.removeAll()
    waiters.forEach { $0.resume() }
  }

  func cancel() {
    record(.cancel)
    guard holdsOperations else { return }
    publish(.cancelled)
    cancellationContinuation?.resume()
    cancellationContinuation = nil
  }

  func repair() async {
    record(.repair)
    started(.repair)
    publish(.repairRequired(message: "repair"))
  }

  func update() async {
    record(.update)
    started(.update)
    publish(.updateAvailable)
  }

  func remove() async {
    record(.remove)
    started(.remove)
    publish(.removing)
  }

  private func record(_ action: AdmittedModelSettingsAction) {
    counts[action, default: 0] += 1
  }

  private func started(_ action: AdmittedModelSettingsAction) {
    startedActions.insert(action)
    let waiters = startWaiters.filter { $0.0 == action }
    startWaiters.removeAll { $0.0 == action }
    waiters.forEach { $0.1.resume() }
  }

  private func publish(_ phase: AdmittedModelInstallPhase) {
    let lastError: String?
    switch phase {
    case .repairRequired(let message), .failed(let message):
      lastError = message
    default:
      lastError = nil
    }
    snapshot = .init(
      recommendation: .recommended(AdmittedModelSettingsTestDescriptors.tinyAdmittedASR),
      phase: phase,
      lastError: lastError
    )
    continuation.yield(snapshot)
    let waiters = phaseWaiters.filter { $0.0 == phase }
    phaseWaiters.removeAll { $0.0 == phase }
    waiters.forEach { $0.1.resume() }
  }
}

@MainActor
private func waitForPresentation(
  _ viewModel: AdmittedModelSettingsViewModel,
  phase: AdmittedModelInstallPhase
) async {
  for _ in 0..<100 {
    if viewModel.presentation.phase == phase { return }
    await Task.yield()
  }
}

@Test @MainActor
func failedRecommendedSnapshotExposesRetryAndDispatchesRepairExactlyOnce() async {
  let probe = InstallerActionProbe(
    refreshPhase: .failed(message: "startup failed")
  )
  let viewModel = AdmittedModelSettingsViewModel(installer: probe)

  await viewModel.refresh()
  await waitForPresentation(viewModel, phase: .failed(message: "startup failed"))

  #expect(viewModel.presentation.primaryAction == .repair)
  #expect(viewModel.presentation.primaryActionLabel == "Retry")

  viewModel.perform(.repair)
  viewModel.perform(.repair)
  await probe.waitUntilPhase(.repairRequired(message: "repair"))
  await waitForPresentation(viewModel, phase: .repairRequired(message: "repair"))

  #expect(probe.count(.repair) == 1)
}

@Test @MainActor
func settingsActionsDispatchExactlyOnceAndUpdatePresentation() async {
  let rows: [(AdmittedModelSettingsAction, AdmittedModelInstallPhase)] = [
    (.install, .ready),
    (.repair, .repairRequired(message: "repair")),
    (.update, .updateAvailable),
    (.remove, .removing)
  ]
  for (action, expectedPhase) in rows {
    let probe = InstallerActionProbe()
    let viewModel = AdmittedModelSettingsViewModel(installer: probe)
    viewModel.perform(action)
    await probe.waitUntilPhase(expectedPhase)
    await waitForPresentation(viewModel, phase: expectedPhase)
    #expect(probe.count(action) == 1)
    #expect(viewModel.presentation.phase == expectedPhase)
  }

  let cancellingProbe = InstallerActionProbe(holdsOperations: true)
  let cancellingViewModel = AdmittedModelSettingsViewModel(installer: cancellingProbe)
  cancellingViewModel.perform(.install)
  await cancellingProbe.waitUntilStarted(.install)
  cancellingViewModel.perform(.repair)
  cancellingViewModel.perform(.update)
  cancellingViewModel.perform(.remove)
  cancellingViewModel.perform(.cancel)
  cancellingViewModel.perform(.cancel)
  await cancellingProbe.waitUntilPhase(.cancelled)
  await waitForPresentation(cancellingViewModel, phase: .cancelled)
  #expect(cancellingProbe.count(.install) == 1)
  #expect(cancellingProbe.count(.repair) == 0)
  #expect(cancellingProbe.count(.update) == 0)
  #expect(cancellingProbe.count(.remove) == 0)
  #expect(cancellingProbe.count(.cancel) == 1)
  #expect(cancellingViewModel.presentation.phase == .cancelled)
}

@Test @MainActor
func releasingViewModelCancelsHeldInstallWithoutLateOwnerUpdate() async {
  let probe = InstallerActionProbe(holdsOperations: true)
  var viewModel: AdmittedModelSettingsViewModel? =
    AdmittedModelSettingsViewModel(installer: probe)
  weak var weakViewModel: AdmittedModelSettingsViewModel? = viewModel

  viewModel?.perform(.install)
  await probe.waitUntilStarted(.install)
  await probe.waitUntilPhase(.downloading(receivedBytes: 0, totalBytes: 100))
  viewModel = nil

  #expect(weakViewModel == nil)
  await probe.waitUntilPhase(.cancelled)
  await probe.waitUntilOperationFinished()
  #expect(probe.count(.cancel) == 1)
  #expect(probe.operationFinished)

  for _ in 0..<10 {
    await Task.yield()
  }
  #expect(weakViewModel == nil)
}

@Test @MainActor
func refreshPublishesPersistedSettingsState() async {
  let probe = InstallerActionProbe(refreshPhase: .updateAvailable)
  let viewModel = AdmittedModelSettingsViewModel(installer: probe)

  await viewModel.refresh()
  await waitForPresentation(viewModel, phase: .updateAvailable)

  #expect(viewModel.presentation.phase == .updateAvailable)
}

@Test @MainActor
func orderedInstallerUpdatesLeaveFinalPresentationAtInstalled() async {
  let probe = InstallerActionProbe()
  let viewModel = AdmittedModelSettingsViewModel(installer: probe)

  probe.publishSequence([
    .downloading(receivedBytes: 4, totalBytes: 8),
    .verifying,
    .installing,
    .installed
  ])
  await waitForPresentation(viewModel, phase: .installed)

  #expect(viewModel.presentation.phase == .installed)
}

@Test @MainActor
func currentAppConstructionDefaultsToBuiltInInstaller() {
  let installer = makeAdmittedModelInstaller()
  #expect(installer.snapshot.recommendation == .builtIn)
  #expect(installer.snapshot.phase == .builtIn)
}

#if CLEAN_DICTATION_ENHANCED_CANDIDATE
func supportedHardware(
  for descriptor: AdmittedModelDescriptor,
  availableBytes: Int64? = nil
) -> AdmittedModelHardwareProfile {
  .init(
    architecture: descriptor.architectures[0],
    requestedLanguages: [descriptor.languages[0]],
    availableBytes: availableBytes ?? descriptor.requiredCapacityBytes
  )
}

struct SignedTestConfiguration {
  let value: AdmittedModelSignedConfiguration
  let fixture: TestManagerFixture
}

@MainActor
func signedConfiguration(
  descriptor: AdmittedModelDescriptor,
  hardware: AdmittedModelHardwareProfile,
  transport: ModelDownloadingProbe
) -> SignedTestConfiguration {
  let fixture = try! TestManagers.manager(
    descriptor: descriptor,
    artifactIdentity: TestArtifacts.identity(matching: descriptor),
    manifest: TestManifests.tiny,
    transport: transport
  )
  return SignedTestConfiguration(
    value: AdmittedModelSignedConfiguration(
      rawDescriptor: TestDescriptors.raw(descriptor),
      hardware: hardware,
      manager: fixture.manager,
      startup: { },
      calibrate: { }
    ),
    fixture: fixture
  )
}

@Test @MainActor
func nilSignedConfigurationUsesBuiltInInstaller() {
  let installer = makeAdmittedModelInstaller(signedConfiguration: nil)
  #expect(installer.snapshot.recommendation == .builtIn)
  #expect(installer.snapshot.phase == .builtIn)
}

@Test @MainActor
func architectureMismatchReturnsBuiltInFailureWithoutTransport() {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let transport = ModelDownloadingProbe(bytes: TestFixtures.tinyBytes)
  let test = signedConfiguration(
    descriptor: descriptor,
    hardware: .init(
      architecture: "x86_64",
      requestedLanguages: [descriptor.languages[0]],
      availableBytes: descriptor.requiredCapacityBytes
    ),
    transport: transport
  )
  defer { test.fixture.cleanup() }
  let installer = makeAdmittedModelInstaller(signedConfiguration: test.value)
  #expect(installer.snapshot.recommendation == .builtIn)
  #expect(installer.snapshot.lastError != nil)
  #expect(transport.downloadCalls == 0)
}

@Test @MainActor
func languageMismatchReturnsBuiltInFailureWithoutTransport() {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let transport = ModelDownloadingProbe(bytes: TestFixtures.tinyBytes)
  let test = signedConfiguration(
    descriptor: descriptor,
    hardware: .init(
      architecture: descriptor.architectures[0],
      requestedLanguages: ["zh-CN"],
      availableBytes: descriptor.requiredCapacityBytes
    ),
    transport: transport
  )
  defer { test.fixture.cleanup() }
  let installer = makeAdmittedModelInstaller(signedConfiguration: test.value)
  #expect(installer.snapshot.recommendation == .builtIn)
  #expect(installer.snapshot.lastError != nil)
  #expect(transport.downloadCalls == 0)
}

@Test @MainActor
func mixedRequestedLanguagesReturnBuiltInFailureWithoutTransport() {
  let descriptor = TestDescriptors.tinyAdmittedASR
  #expect(descriptor.languages == ["en-US"])
  let transport = ModelDownloadingProbe(bytes: TestFixtures.tinyBytes)
  let test = signedConfiguration(
    descriptor: descriptor,
    hardware: .init(
      architecture: descriptor.architectures[0],
      requestedLanguages: ["en-US", "zh-CN"],
      availableBytes: descriptor.requiredCapacityBytes
    ),
    transport: transport
  )
  defer { test.fixture.cleanup() }
  let installer = makeAdmittedModelInstaller(signedConfiguration: test.value)
  #expect(installer.snapshot.recommendation == .builtIn)
  #expect(installer.snapshot.lastError != nil)
  #expect(transport.downloadCalls == 0)
}

@Test @MainActor
func insufficientStagingCapacityReturnsBuiltInFailureWithoutTransport() {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let availableBytes = descriptor.downloadBytes + 1
  #expect(availableBytes > descriptor.downloadBytes)
  #expect(availableBytes < descriptor.requiredCapacityBytes)
  let transport = ModelDownloadingProbe(bytes: TestFixtures.tinyBytes)
  let test = signedConfiguration(
    descriptor: descriptor,
    hardware: supportedHardware(for: descriptor, availableBytes: availableBytes),
    transport: transport
  )
  defer { test.fixture.cleanup() }
  let installer = makeAdmittedModelInstaller(signedConfiguration: test.value)
  #expect(installer.snapshot.recommendation == .builtIn)
  #expect(installer.snapshot.lastError != nil)
  #expect(transport.downloadCalls == 0)
}

@Test @MainActor
func supportedHardwareProfileReachesRecommendedInstallerWithoutStartingTransport() {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let transport = ModelDownloadingProbe(bytes: TestFixtures.tinyBytes)
  let test = signedConfiguration(
    descriptor: descriptor,
    hardware: supportedHardware(for: descriptor),
    transport: transport
  )
  defer { test.fixture.cleanup() }
  let installer = makeAdmittedModelInstaller(signedConfiguration: test.value)
  #expect(installer.snapshot.recommendation == .recommended(descriptor))
  #expect(installer.snapshot.phase == .notInstalled)
  #expect(transport.downloadCalls == 0)
}

@Test @MainActor
func invalidSignedDescriptorIsCaughtAsNonOperatingBuiltInFailure() {
  let raw = TestDescriptors.make(TestDescriptors.neutralAdmitted, modelID: "")
  let transport = ModelDownloadingProbe(bytes: TestFixtures.tinyBytes)
  let fixture = try! TestManagers.manager(
    descriptor: TestDescriptors.tinyAdmittedASR,
    artifactIdentity: TestArtifacts.identity(matching: TestDescriptors.tinyAdmittedASR),
    manifest: TestManifests.tiny,
    transport: transport
  )
  defer { fixture.cleanup() }
  let configuration = AdmittedModelSignedConfiguration(
    rawDescriptor: raw,
    hardware: supportedHardware(for: TestDescriptors.tinyAdmittedASR),
    manager: fixture.manager,
    startup: { },
    calibrate: { }
  )
  let installer = makeAdmittedModelInstaller(signedConfiguration: configuration)
  #expect(installer.snapshot.recommendation == .builtIn)
  guard case .failed(let message) = installer.snapshot.phase else {
    Issue.record("Expected a failed non-operating Settings snapshot")
    return
  }
  #expect(!message.isEmpty)
  let presentation = AdmittedModelSettingsPresentation(snapshot: installer.snapshot)
  #expect(presentation.detail.contains(message))
  #expect(presentation.identity == nil)
  #expect(presentation.primaryAction == nil)
  #expect(transport.downloadCalls == 0)
}

@Test @MainActor
func artifactBindingFailureReturnsBuiltInWithoutRetryOrTransport() {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let transport = ModelDownloadingProbe(bytes: TestFixtures.tinyBytes)
  let fixture = try! TestManagers.manager(
    descriptor: descriptor,
    artifactIdentity: TestArtifacts.identityWith(revision: "wrong"),
    manifest: TestManifests.tiny,
    transport: transport
  )
  defer { fixture.cleanup() }
  let configuration = AdmittedModelSignedConfiguration(
    rawDescriptor: TestDescriptors.raw(descriptor),
    hardware: supportedHardware(for: descriptor),
    manager: fixture.manager,
    startup: { },
    calibrate: { }
  )
  let installer = makeAdmittedModelInstaller(signedConfiguration: configuration)
  #expect(installer.snapshot.recommendation == .builtIn)
  #expect(transport.downloadCalls == 0)
  #expect(installer.snapshot.lastError != nil)
  let presentation = AdmittedModelSettingsPresentation(snapshot: installer.snapshot)
  #expect(presentation.identity == nil)
  #expect(presentation.primaryAction == nil)
  #expect(presentation.primaryActionLabel == nil)
  #expect(presentation.detail.contains("Fleck continues with Apple Speech"))
  #expect(!presentation.detail.contains("restart Fleck"))

  let availability = DictationAvailability.evaluate(.init(
    osMajorVersion: 26,
    architecture: .appleSilicon,
    microphonePermission: .authorized,
    speechPermission: .authorized,
    appleOnDeviceRecognitionSupported: true,
    enhancedModelReady: false,
    foundationModelAvailable: true
  ))
  #expect(availability.standardAvailable)
}

@Test @MainActor
func storageNamespaceMismatchReturnsBuiltInWithoutRetryOrTransport() throws {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let transport = ModelDownloadingProbe(bytes: TestFixtures.tinyBytes)
  let baseRoot = TestPaths.temporaryDirectory()
  defer { TestPaths.remove(baseRoot) }
  let selected = try AdmittedModelStorageNamespace(
    baseRootURL: baseRoot,
    descriptor: descriptor
  )
  let manager = EnhancedModelManager(
    modelRootURL: baseRoot,
    manifest: TestManifests.tiny,
    artifactIdentity: TestArtifacts.identity(matching: descriptor),
    candidateEnabled: true,
    capacityProvider: { Int64.max },
    architectureProvider: { true },
    transport: transport,
    admittedStorageNamespace: selected
  )
  let configuration = AdmittedModelSignedConfiguration(
    rawDescriptor: TestDescriptors.raw(descriptor),
    hardware: supportedHardware(for: descriptor),
    manager: manager,
    startup: { },
    calibrate: { }
  )

  let installer = makeAdmittedModelInstaller(signedConfiguration: configuration)
  #expect(installer.snapshot.recommendation == .builtIn)
  #expect(installer.snapshot.lastError != nil)
  #expect(transport.downloadCalls == 0)
  let presentation = AdmittedModelSettingsPresentation(snapshot: installer.snapshot)
  #expect(presentation.primaryAction == nil)
  #expect(presentation.primaryActionLabel == nil)
}
#endif
