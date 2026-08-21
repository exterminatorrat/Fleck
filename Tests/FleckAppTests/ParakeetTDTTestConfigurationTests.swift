#if os(macOS) && CLEAN_DICTATION_ENHANCED_CANDIDATE
import Foundation
import Testing

@testable import FleckApp

private enum ConfigurationTestError: Error {
  case capacityUnavailable
}

private final class ArchitectureProbe: @unchecked Sendable {
  var invocationCount = 0

  func sample() -> Bool {
    invocationCount += 1
    return invocationCount == 1
  }
}

@MainActor
private func makeTestConfiguration(
  capacity: Int64 = .max,
  architectureSupported: Bool = true
) throws -> (value: AdmittedModelSignedConfiguration, baseRoot: URL) {
  let baseRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent("fleck-parakeet-configuration-\(UUID().uuidString)")
  let value = try ParakeetTDTTestConfiguration.make(
    admittedBaseRoot: baseRoot,
    capacityProvider: { capacity },
    architectureProvider: { architectureSupported },
    startup: {},
    calibrate: {}
  )
  return (value, baseRoot)
}

private func removeTestRoot(_ url: URL) {
  try? FileManager.default.removeItem(at: url)
}

@Test @MainActor
func parakeetConfigurationBindsExactManifestIdentityAndNamespace() throws {
  let test = try makeTestConfiguration()
  defer { removeTestRoot(test.baseRoot) }

  let raw = test.value.rawDescriptor
  let descriptor = try AdmittedModelDescriptor(validating: raw)
  let identity = test.value.manager.admittedArtifactIdentity

  #expect(raw.role == .asr)
  #expect(raw.modelID == "FluidInference/parakeet-tdt-0.6b-v2-coreml")
  #expect(raw.revision == "ee09c569f73759e6d44c9bd16766f477b2b36d39")
  #expect(raw.source.absoluteString == "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml")
  #expect(raw.runtimeABI == "FluidAudio/v0.15.5@19600a485baa4998812e4654b70d2bab8f2c9949")
  #expect(raw.conversion == "CoreML")
  #expect(raw.quantization == "FP16")
  #expect(raw.license == "CC-BY-4.0")
  #expect(raw.languages == ["en"])
  #expect(raw.architectures == ["arm64"])
  #expect(raw.files.count == 21)
  #expect(raw.downloadBytes == 464_413_247)
  #expect(raw.installedBytes == raw.downloadBytes)
  #expect(raw.notices.contains("Third-Party Notices"))
  #expect(test.value.hardware == .init(
    architecture: "arm64",
    requestedLanguages: ["en"],
    availableBytes: .max
  ))
  #expect(identity.immutableIdentity == descriptor.immutableIdentity)
  #expect(identity.files == raw.files)
  #expect(identity.downloadBytes == raw.downloadBytes)
  #expect(test.value.manager.admittedManifest.files.map {
    AdmittedModelFile(path: $0.path, byteCount: $0.byteCount, sha256: $0.sha256)
  } == raw.files)
  try AdmittedModelArtifactBinding.validate(
    descriptor: descriptor,
    artifact: identity,
    manifest: test.value.manager.admittedManifest
  )
  #expect(test.value.manager.admittedStorageBaseRootURL
    == test.baseRoot.standardizedFileURL.resolvingSymlinksInPath())
  #expect(test.value.manager.admittedStorageNamespaceRootURL
    == test.value.manager.modelRootURL)
  #expect(test.value.manager.modelRootURL != test.value.manager.admittedStorageBaseRootURL)
}

@Test @MainActor
func architectureProviderIsSampledOnceAndManagerMatchesHardwareProfile() throws {
  let probe = ArchitectureProbe()
  let baseRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent("fleck-parakeet-architecture-probe-\(UUID().uuidString)")
  let configuration = try ParakeetTDTTestConfiguration.make(
    admittedBaseRoot: baseRoot,
    capacityProvider: { Int64.max },
    architectureProvider: { probe.sample() },
    startup: {},
    calibrate: {}
  )
  defer { removeTestRoot(baseRoot) }

  #expect(probe.invocationCount == 1)
  #expect(configuration.hardware.architecture == "arm64")
  #expect(configuration.manager.isArchitectureSupported)
  #expect(configuration.manager.isArchitectureSupported
    == (configuration.hardware.architecture == "arm64"))
}

@Test @MainActor
func unsupportedArchitectureFallsBackBeforeInstallerOperation() throws {
  let test = try makeTestConfiguration(architectureSupported: false)
  defer { removeTestRoot(test.baseRoot) }

  let installer = makeAdmittedModelInstaller(signedConfiguration: test.value)

  #expect(test.value.hardware.architecture == "x86_64")
  #expect(installer.snapshot.recommendation == .builtIn)
  #expect(installer.snapshot.lastError != nil)
}

@Test @MainActor
func unsupportedLanguageFallsBackBeforeInstallerOperation() throws {
  let test = try makeTestConfiguration()
  defer { removeTestRoot(test.baseRoot) }

  let languageMismatch = AdmittedModelSignedConfiguration(
    rawDescriptor: test.value.rawDescriptor,
    hardware: .init(
      architecture: "arm64",
      requestedLanguages: ["zh"],
      availableBytes: .max
    ),
    manager: test.value.manager,
    startup: test.value.startup,
    calibrate: test.value.calibrate
  )
  let installer = makeAdmittedModelInstaller(
    signedConfiguration: languageMismatch
  )

  #expect(installer.snapshot.recommendation == .builtIn)
  #expect(installer.snapshot.lastError != nil)
}

@Test @MainActor
func insufficientCapacityFallsBackBeforeInstallerOperation() throws {
  let valid = try makeTestConfiguration()
  let descriptor = try AdmittedModelDescriptor(
    validating: valid.value.rawDescriptor
  )
  removeTestRoot(valid.baseRoot)
  let test = try makeTestConfiguration(
    capacity: descriptor.requiredCapacityBytes - 1
  )
  defer { removeTestRoot(test.baseRoot) }

  let installer = makeAdmittedModelInstaller(signedConfiguration: test.value)

  #expect(test.value.hardware.availableBytes < descriptor.requiredCapacityBytes)
  #expect(installer.snapshot.recommendation == .builtIn)
  #expect(installer.snapshot.lastError != nil)
}

@Test @MainActor
func signedConfigurationRemainsOptInAndDefaultInstallerStaysBuiltIn() {
  let installer = makeAdmittedModelInstaller()
  let explicitNil = makeAdmittedModelInstaller(signedConfiguration: nil)

  #expect(installer.snapshot.recommendation == .builtIn)
  #expect(installer.snapshot.phase == .builtIn)
  #expect(explicitNil.snapshot.recommendation == .builtIn)
  #expect(explicitNil.snapshot.phase == .builtIn)
}

@Test @MainActor
func invalidNamespaceFailsWithoutFatalConstruction() {
  #expect(throws: AdmittedModelStorageNamespace.Error.invalidBaseRoot) {
    _ = try ParakeetTDTTestConfiguration.make(
      admittedBaseRoot: URL(fileURLWithPath: "/"),
      capacityProvider: { Int64.max },
      architectureProvider: { true },
      startup: {},
      calibrate: {}
    )
  }
}

@Test @MainActor
func capacityProviderFailureIsPropagatedWithoutConstruction() {
  #expect(throws: ConfigurationTestError.capacityUnavailable) {
    _ = try ParakeetTDTTestConfiguration.make(
      admittedBaseRoot: FileManager.default.temporaryDirectory,
      capacityProvider: { throw ConfigurationTestError.capacityUnavailable },
      architectureProvider: { true },
      startup: {},
      calibrate: {}
    )
  }
}
#endif
