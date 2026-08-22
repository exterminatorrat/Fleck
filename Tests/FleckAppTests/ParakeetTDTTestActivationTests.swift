#if os(macOS) && CLEAN_DICTATION_ENHANCED_CANDIDATE
import Foundation
import Testing

@testable import FleckApp

private enum ActivationTestError: Error {
  case configuration
  case load
  case decode
}

private actor ActivationMutationProbe {
  private(set) var invocationCount = 0

  func record() {
    invocationCount += 1
  }
}

@MainActor
private final class ActivationInferenceProbe: EnhancedSpeechInferring {
  var loadedRepositories: [URL] = []
  var transcribedSamples: [[Float]] = []
  var releaseCount = 0
  var cancelCount = 0
  var loadError: Error?
  var transcribeError: Error?

  func load(from repositoryURL: URL) async throws {
    if let loadError { throw loadError }
    loadedRepositories.append(repositoryURL)
  }

  func transcribe(_ samples: [Float]) async throws -> String {
    if let transcribeError { throw transcribeError }
    transcribedSamples.append(samples)
    return ""
  }

  func cancel() async {
    cancelCount += 1
  }

  func releaseResources() async {
    releaseCount += 1
  }
}

@Test @MainActor
func activationSharesOneManagerWithInstallerAndBindsExactRecommendation() throws {
  let root = TestPaths.temporaryDirectory()
  defer { TestPaths.remove(root) }

  let activation = ParakeetTDTTestActivation.make(
    applicationSupportURL: root
  )
  let installer = try #require(
    activation.installer as? EnhancedModelManagerInstaller
  )

  #expect(installer.manager === activation.manager)
  #expect(installer.descriptor.modelID == "FluidInference/parakeet-tdt-0.6b-v2-coreml")
  #expect(installer.descriptor.revision == "ee09c569f73759e6d44c9bd16766f477b2b36d39")
  #expect(installer.descriptor.runtimeABI == ParakeetTDTTestConfiguration.runtimeABI)
  #expect(installer.snapshot.phase == .notInstalled)
}

@Test @MainActor
func activationPropagatesModelMutationHookThroughDefaultConfiguration() async throws {
  let root = TestPaths.temporaryDirectory()
  defer { TestPaths.remove(root) }
  let probe = ActivationMutationProbe()

  let activation = ParakeetTDTTestActivation.make(
    applicationSupportURL: root,
    modelMutationWillBegin: { await probe.record() }
  )

  try await activation.manager.deleteModel()

  #expect(await probe.invocationCount == 1)
}

@Test @MainActor
func activationConstructionFailureReturnsSafeAppleSpeechFallback() {
  let root = TestPaths.temporaryDirectory()
  defer { TestPaths.remove(root) }

  let activation = ParakeetTDTTestActivation.make(
    applicationSupportURL: root,
    configurationFactory: { _, _ in
      throw ActivationTestError.configuration
    }
  )

  #expect(activation.manager.verifiedLoadState == .unavailable)
  #expect(
    activation.installer.snapshot.recommendation
      == AdmittedModelRecommendation.builtIn
  )
  guard case .failed(let message) = activation.installer.snapshot.phase else {
    Issue.record("Expected a non-operating failed fallback")
    return
  }
  #expect(message.contains("Apple Speech"))
  #expect(!message.contains(root.path))
}

@Test @MainActor
func activationRefreshLoadsAndCalibratesThenReleasesInferenceResources() async throws {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let fixture = try TestManagers.manager(
    descriptor: descriptor,
    artifactIdentity: TestArtifacts.identity(matching: descriptor),
    manifest: TestManifests.tiny,
    transport: ModelDownloadingProbe(bytes: TestFixtures.tinyBytes),
    refreshFixture: .ready
  )
  defer { fixture.cleanup() }
  let probe = ActivationInferenceProbe()
  let activation = ParakeetTDTTestActivation.make(
    applicationSupportURL: fixture.root,
    configurationFactory: { _, hooks in
      AdmittedModelSignedConfiguration(
        rawDescriptor: TestDescriptors.raw(descriptor),
        hardware: .init(
          architecture: "arm64",
          requestedLanguages: Set(descriptor.languages),
          availableBytes: .max
        ),
        manager: fixture.manager,
        startup: hooks.startup,
        calibrate: hooks.calibrate
      )
    },
    makeInference: { probe }
  )

  await activation.installer.refresh()

  #expect(
    activation.installer.snapshot.phase == AdmittedModelInstallPhase.installed
  )
  #expect(probe.loadedRepositories.count == 2)
  #expect(probe.transcribedSamples.count == 1)
  #expect(probe.transcribedSamples[0].count == 4_800)
  #expect(probe.releaseCount == 2)
}

@Test @MainActor
func activationStartupFailureRepairsExactRepositoryAndReleasesResources() async throws {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let fixture = try TestManagers.manager(
    descriptor: descriptor,
    artifactIdentity: TestArtifacts.identity(matching: descriptor),
    manifest: TestManifests.tiny,
    transport: ModelDownloadingProbe(bytes: TestFixtures.tinyBytes),
    refreshFixture: .ready
  )
  defer { fixture.cleanup() }
  let probe = ActivationInferenceProbe()
  probe.loadError = ActivationTestError.load
  let activation = ParakeetTDTTestActivation.make(
    applicationSupportURL: fixture.root,
    configurationFactory: { _, hooks in
      AdmittedModelSignedConfiguration(
        rawDescriptor: TestDescriptors.raw(descriptor),
        hardware: .init(
          architecture: "arm64",
          requestedLanguages: Set(descriptor.languages),
          availableBytes: .max
        ),
        manager: fixture.manager,
        startup: hooks.startup,
        calibrate: hooks.calibrate
      )
    },
    makeInference: { probe }
  )

  await activation.installer.refresh()

  #expect(
    activation.installer.snapshot.phase != AdmittedModelInstallPhase.installed
  )
  #expect(probe.releaseCount == 1)
  guard case .repairRequired = fixture.manager.state else {
    Issue.record("Expected the exact repository to be repaired after startup failure")
    return
  }
}

@Test @MainActor
func activationCalibrationFailureRepairsExactRepositoryAndReleasesResources() async throws {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let fixture = try TestManagers.manager(
    descriptor: descriptor,
    artifactIdentity: TestArtifacts.identity(matching: descriptor),
    manifest: TestManifests.tiny,
    transport: ModelDownloadingProbe(bytes: TestFixtures.tinyBytes),
    refreshFixture: .ready
  )
  defer { fixture.cleanup() }
  let probe = ActivationInferenceProbe()
  probe.transcribeError = ActivationTestError.decode
  let activation = ParakeetTDTTestActivation.make(
    applicationSupportURL: fixture.root,
    configurationFactory: { _, hooks in
      AdmittedModelSignedConfiguration(
        rawDescriptor: TestDescriptors.raw(descriptor),
        hardware: .init(
          architecture: "arm64",
          requestedLanguages: Set(descriptor.languages),
          availableBytes: .max
        ),
        manager: fixture.manager,
        startup: hooks.startup,
        calibrate: hooks.calibrate
      )
    },
    makeInference: { probe }
  )

  await activation.installer.refresh()

  #expect(
    activation.installer.snapshot.phase != AdmittedModelInstallPhase.installed
  )
  #expect(probe.releaseCount == 2)
  guard case .repairRequired = fixture.manager.state else {
    Issue.record("Expected the exact repository to be repaired after calibration failure")
    return
  }
}
#endif
