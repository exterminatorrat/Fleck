#if os(macOS) && CLEAN_DICTATION_ENHANCED_CANDIDATE
import Foundation
import Testing

@testable import FleckApp

private enum GemmaActivationTestError: Error {
  case configuration
  case probe
}

private actor GemmaActivationProbe {
  private(set) var calls: [(helper: URL, repository: URL)] = []
  private var waiters: [CheckedContinuation<Void, Never>] = []
  var error: Error?
  var blocksUntilCancelled = false

  func run(helper: URL, repository: URL) async throws {
    calls.append((helper, repository))
    let pending = waiters
    waiters.removeAll()
    pending.forEach { $0.resume() }
    if blocksUntilCancelled {
      try await Task.sleep(for: .seconds(30))
    }
    if let error { throw error }
  }

  func waitUntilCalled() async {
    guard calls.isEmpty else { return }
    await withCheckedContinuation { continuation in
      if calls.isEmpty {
        waiters.append(continuation)
      } else {
        continuation.resume()
      }
    }
  }
}

@MainActor
private func makeCleanupFixture(
  ready: Bool
) throws -> (fixture: TestManagerFixture, descriptor: AdmittedModelDescriptor) {
  let descriptor = try AdmittedModelDescriptor(validating: TestDescriptors.make(
    TestDescriptors.tinyAdmittedASR,
    modelID: TestDescriptors.tinyAdmittedASR.modelID,
    role: .cleanup
  ))
  let fixture = try TestManagers.manager(
    descriptor: descriptor,
    artifactIdentity: TestArtifacts.identity(matching: descriptor),
    manifest: TestManifests.tiny,
    transport: ModelDownloadingProbe(bytes: TestFixtures.tinyBytes),
    refreshFixture: ready ? .ready : nil
  )
  return (fixture, descriptor)
}

@MainActor
private func makeActivation(
  fixture: TestManagerFixture,
  descriptor: AdmittedModelDescriptor,
  bundleURL: URL,
  probe: GemmaActivationProbe
) -> GemmaCleanupTestActivation.Result {
  GemmaCleanupTestActivation.make(
    applicationSupportURL: fixture.root,
    bundleURL: bundleURL,
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
    probe: { helper, repository in
      try await probe.run(helper: helper, repository: repository)
    }
  )
}

@Test @MainActor
func gemmaActivationUsesCleanupRootRoleAndCanonicalPackagedHelper() throws {
  let root = TestPaths.temporaryDirectory()
  defer { TestPaths.remove(root) }
  let bundle = root.appendingPathComponent("Fleck.app", isDirectory: true)

  let activation = GemmaCleanupTestActivation.make(
    applicationSupportURL: root,
    bundleURL: bundle
  )
  let installer = try #require(
    activation.installer as? EnhancedModelManagerInstaller
  )
  let expectedHelper = bundle
    .appendingPathComponent("Contents/SharedSupport/gemma-cleanup-helper")
    .standardizedFileURL

  #expect(installer.manager === activation.manager)
  #expect(installer.descriptor.role == .cleanup)
  #expect(activation.manager.admittedStorageBaseRootURL
    == root.appendingPathComponent("CleanupModels", isDirectory: true)
      .standardizedFileURL.resolvingSymlinksInPath())
  #expect(activation.helperExecutableURL == expectedHelper)
  #expect(activation.makeTransport(activation.manager.modelRootURL)
    is GemmaCleanupProcessTransport)
}

@Test @MainActor
func gemmaActivationProbesOnceThenCalibrationReusesUnchangedProof() async throws {
  let test = try makeCleanupFixture(ready: true)
  defer { test.fixture.cleanup() }
  let bundle = test.fixture.root.appendingPathComponent("Fleck.app")
  let probe = GemmaActivationProbe()
  let activation = makeActivation(
    fixture: test.fixture,
    descriptor: test.descriptor,
    bundleURL: bundle,
    probe: probe
  )

  await activation.installer.refresh()

  #expect(activation.installer.snapshot.phase == .installed)
  #expect(await probe.calls.count == 1)
  #expect(await probe.calls.first?.helper == activation.helperExecutableURL)
  #expect(await probe.calls.first?.repository == test.fixture.manager.verifiedRepositoryURL)
}

@Test @MainActor
func gemmaActivationProbeFailureMarksExactRepositoryForRepair() async throws {
  let test = try makeCleanupFixture(ready: true)
  defer { test.fixture.cleanup() }
  let probe = GemmaActivationProbe()
  await probe.setError(GemmaActivationTestError.probe)
  let activation = makeActivation(
    fixture: test.fixture,
    descriptor: test.descriptor,
    bundleURL: test.fixture.root.appendingPathComponent("Fleck.app"),
    probe: probe
  )

  await activation.installer.refresh()

  #expect(await probe.calls.count == 1)
  guard case .repairRequired(let message) = test.fixture.manager.state else {
    Issue.record("Expected Gemma runtime failure to require repair")
    return
  }
  #expect(message.contains("cleanup model"))
  #expect(!message.contains("Apple Speech"))
}

@Test @MainActor
func gemmaActivationCancellationDoesNotCorruptVerifiedRepository() async throws {
  let test = try makeCleanupFixture(ready: true)
  defer { test.fixture.cleanup() }
  let probe = GemmaActivationProbe()
  await probe.setBlocksUntilCancelled(true)
  let activation = makeActivation(
    fixture: test.fixture,
    descriptor: test.descriptor,
    bundleURL: test.fixture.root.appendingPathComponent("Fleck.app"),
    probe: probe
  )

  let refresh = Task { @MainActor in
    await activation.installer.refresh()
  }
  await probe.waitUntilCalled()
  activation.installer.cancel()
  await refresh.value

  #expect(activation.installer.snapshot.phase == .cancelled)
  #expect(test.fixture.manager.state == .ready)
  #expect(test.fixture.manager.verifiedLoadState != .unavailable)
}

@Test @MainActor
func gemmaActivationRepositoryChangeRejectsProofAndRequiresRepair() async throws {
  let test = try makeCleanupFixture(ready: true)
  defer { test.fixture.cleanup() }
  var hooks: GemmaCleanupTestActivation.ConfigurationHooks?
  let activation = GemmaCleanupTestActivation.make(
    applicationSupportURL: test.fixture.root,
    bundleURL: test.fixture.root.appendingPathComponent("Fleck.app"),
    configurationFactory: { _, suppliedHooks in
      hooks = suppliedHooks
      return AdmittedModelSignedConfiguration(
        rawDescriptor: TestDescriptors.raw(test.descriptor),
        hardware: .init(
          architecture: "arm64",
          requestedLanguages: Set(test.descriptor.languages),
          availableBytes: .max
        ),
        manager: test.fixture.manager,
        startup: suppliedHooks.startup,
        calibrate: suppliedHooks.calibrate
      )
    },
    probe: { _, repository in
      test.fixture.manager.markInferenceLoadFailure(
        message: "repository changed",
        failedRepositoryURL: repository
      )
    }
  )

  await activation.installer.refresh()

  #expect(hooks != nil)
  guard case .repairRequired = test.fixture.manager.state else {
    Issue.record("Expected changed repository proof to require repair")
    return
  }
  #expect(activation.installer.snapshot.phase != .installed)
}

@Test @MainActor
func gemmaActivationInvalidStateAndConstructionFailureNeverStartProbe() async throws {
  let test = try makeCleanupFixture(ready: false)
  defer { test.fixture.cleanup() }
  let probe = GemmaActivationProbe()
  let activation = makeActivation(
    fixture: test.fixture,
    descriptor: test.descriptor,
    bundleURL: test.fixture.root.appendingPathComponent("Fleck.app"),
    probe: probe
  )

  await activation.installer.refresh()
  #expect(await probe.calls.isEmpty)

  let failed = GemmaCleanupTestActivation.make(
    applicationSupportURL: test.fixture.root,
    configurationFactory: { _, _ in
      throw GemmaActivationTestError.configuration
    },
    probe: { helper, repository in
      try await probe.run(helper: helper, repository: repository)
    }
  )
  await failed.installer.refresh()

  guard case .failed(let message) = failed.installer.snapshot.phase else {
    Issue.record("Expected inert cleanup activation failure")
    return
  }
  #expect(await probe.calls.isEmpty)
  #expect(message.contains("cleanup"))
  #expect(!message.contains("Apple Speech"))
}

private extension GemmaActivationProbe {
  func setError(_ error: Error?) {
    self.error = error
  }

  func setBlocksUntilCancelled(_ value: Bool) {
    blocksUntilCancelled = value
  }
}
#endif
