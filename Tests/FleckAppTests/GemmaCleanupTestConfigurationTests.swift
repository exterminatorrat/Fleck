#if os(macOS) && CLEAN_DICTATION_ENHANCED_CANDIDATE
import Foundation
import Testing

@testable import FleckApp

@MainActor
private func makeGemmaConfiguration(
  architectureSupported: Bool = true
) throws -> (AdmittedModelSignedConfiguration, URL) {
  let root = TestPaths.temporaryDirectory()
  let configuration = try GemmaCleanupTestConfiguration.make(
    admittedBaseRoot: root,
    capacityProvider: { .max },
    architectureProvider: { architectureSupported },
    startup: {},
    calibrate: {}
  )
  return (configuration, root)
}

@Test @MainActor
func gemmaCleanupConfigurationBindsExactArtifactRuntimeAndCleanupNamespace() throws {
  let (configuration, root) = try makeGemmaConfiguration()
  defer { TestPaths.remove(root) }

  let raw = configuration.rawDescriptor
  let descriptor = try AdmittedModelDescriptor(validating: raw)
  let identity = configuration.manager.admittedArtifactIdentity

  #expect(raw.role == .cleanup)
  #expect(raw.modelID == "mlx-community/gemma-3-1b-it-qat-4bit")
  #expect(raw.revision == "15fed4eafb456c6fcb2a1165f19ac609670ed14b")
  #expect(raw.source.absoluteString == "https://huggingface.co/mlx-community/gemma-3-1b-it-qat-4bit")
  #expect(GemmaCleanupTestConfiguration.localRepositoryName == "gemma-3-1b-it-qat-4bit")
  #expect(GemmaCleanupTestConfiguration.mlxSwiftLMRevision == "bd4b7434e6bdb588c7ef55706ff8904cb7fd4c57")
  #expect(GemmaCleanupTestConfiguration.mlxSwiftVersion == "0.31.6")
  #expect(GemmaCleanupTestConfiguration.swiftTransformersVersion == "1.3.0")
  #expect(raw.runtimeABI == GemmaCleanupTestConfiguration.runtimeABI)
  #expect(raw.conversion == "MLX")
  #expect(raw.quantization == "QAT 4-bit")
  #expect(raw.license == "Gemma Terms of Use")
  #expect(raw.languages == ["en"])
  #expect(raw.architectures == ["arm64"])
  #expect(raw.files.count == 10)
  #expect(raw.downloadBytes == 771_863_021)
  #expect(raw.installedBytes == raw.downloadBytes)
  #expect(raw.notices.contains("Gemma Cleanup Model Terms"))
  #expect(raw.notices.contains("https://ai.google.dev/gemma/terms"))
  #expect(configuration.hardware == .init(
    architecture: "arm64",
    requestedLanguages: ["en"],
    availableBytes: .max
  ))
  #expect(identity.role == .cleanup)
  #expect(identity.immutableIdentity == descriptor.immutableIdentity)
  #expect(identity.files == raw.files)
  #expect(configuration.manager.admittedManifest.totalByteCount == 771_863_021)
  #expect(configuration.manager.admittedStorageBaseRootURL
    == root.standardizedFileURL.resolvingSymlinksInPath())
  #expect(configuration.manager.admittedStorageNamespaceRootURL
    == configuration.manager.modelRootURL)
  #expect(configuration.manager.modelRootURL
    != configuration.manager.admittedStorageBaseRootURL)
  try AdmittedModelArtifactBinding.validate(
    descriptor: descriptor,
    artifact: identity,
    manifest: configuration.manager.admittedManifest
  )
}

@Test @MainActor
func gemmaCleanupConfigurationRejectsUnsupportedArchitectureBeforeOperation() throws {
  let (configuration, root) = try makeGemmaConfiguration(
    architectureSupported: false
  )
  defer { TestPaths.remove(root) }

  let installer = makeAdmittedModelInstaller(
    signedConfiguration: configuration,
    expectedRole: .cleanup
  )

  #expect(configuration.hardware.architecture == "x86_64")
  #expect(installer.snapshot.recommendation == .builtIn)
  #expect(installer.snapshot.lastError != nil)
}

@Test @MainActor
func gemmaCleanupConfigurationPassesMutationBarrierToManager() async throws {
  let gate = AsyncModelMutationGate()
  let root = TestPaths.temporaryDirectory()
  defer { TestPaths.remove(root) }
  let configuration = try GemmaCleanupTestConfiguration.make(
    admittedBaseRoot: root,
    capacityProvider: { .max },
    architectureProvider: { true },
    modelMutationWillBegin: { await gate.wait() },
    startup: {},
    calibrate: {}
  )

  let deletion = Task { @MainActor in
    try await configuration.manager.deleteModel()
  }
  await gate.waitUntilEntered()

  #expect(await gate.invocationCount == 1)
  #expect(configuration.manager.state == .removing)

  await gate.release()
  try await deletion.value
  #expect(configuration.manager.state == .notInstalled)
}

@Test @MainActor
func gemmaCleanupConfigurationRejectsChangedFileIdentityWithSameAggregate() throws {
  let (valid, validRoot) = try makeGemmaConfiguration()
  defer { TestPaths.remove(validRoot) }
  let root = TestPaths.temporaryDirectory()
  defer { TestPaths.remove(root) }
  let bundle = root.appendingPathComponent(
    "Fleck_FleckApp.bundle",
    isDirectory: true
  )
  try FileManager.default.createDirectory(
    at: bundle,
    withIntermediateDirectories: true
  )
  var files = valid.manager.admittedManifest.files
  files[0] = EnhancedModelFile(
    path: files[0].path,
    byteCount: files[0].byteCount,
    sha256: String(repeating: "0", count: 64)
  )
  let changedManifest = EnhancedModelManifest(
    schemaVersion: valid.manager.admittedManifest.schemaVersion,
    modelID: valid.manager.admittedManifest.modelID,
    revision: valid.manager.admittedManifest.revision,
    totalByteCount: valid.manager.admittedManifest.totalByteCount,
    files: files
  )
  try JSONEncoder().encode(changedManifest).write(
    to: bundle.appendingPathComponent("GemmaCleanupModelManifest.json")
  )
  try Data("Gemma terms".utf8).write(
    to: bundle.appendingPathComponent("GemmaCleanupNotice.md")
  )

  #expect(throws: GemmaCleanupTestConfigurationError.unexpectedManifestIdentity) {
    _ = try GemmaCleanupTestConfiguration.make(
      admittedBaseRoot: root.appendingPathComponent("CleanupModels"),
      capacityProvider: { .max },
      architectureProvider: { true },
      startup: {},
      calibrate: {},
      applicationResourceRoot: root,
      moduleBundle: nil
    )
  }
}
#endif
