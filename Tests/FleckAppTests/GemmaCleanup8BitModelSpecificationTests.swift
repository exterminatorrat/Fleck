#if os(macOS) && CLEAN_DICTATION_ENHANCED_CANDIDATE
import Foundation
import FleckCore
import Testing

@testable import FleckApp

private func syntheticGemma8BitQualification(
  identity: AdmittedModelImmutableIdentity? = nil,
  family: String = GemmaCleanup8BitModelSpecification.family,
  applicability: LocalModelResourceApplicability = .measured,
  minimumRAMBytes: Int64 = 1,
  workingRAMBytes: Int64 = 1,
  storageBytes: Int64? = nil,
  license: LocalModelLicenseState = .gemmaTermsReviewed,
  cleanupEvidence: LocalModelEvidenceTier = .fleckQualified,
  smartFilingEvidence: LocalModelEvidenceTier? = .fleckQualified,
  admission: LocalModelAdmissionState = .notAdmitted
) throws -> GemmaCleanupModelQualification {
  let descriptor = try AdmittedModelDescriptor(
    validating: GemmaCleanup8BitModelSpecification.rawDescriptor
  )
  return GemmaCleanupModelQualification(
    family: family,
    identity: identity ?? descriptor.immutableIdentity,
    resources: LocalModelResourceEnvelope(
      applicability: applicability,
      minimumRAMBytes: minimumRAMBytes,
      workingRAMBytes: workingRAMBytes,
      storageBytes: storageBytes ?? descriptor.installedBytes
    ),
    license: license,
    cleanupEvidence: cleanupEvidence,
    smartFilingEvidence: smartFilingEvidence,
    admission: admission
  )
}

private func resolveGemma8Bit(
  _ qualification: GemmaCleanupModelQualification?,
  modelID: String? = GemmaCleanup8BitModelSpecification.modelID,
  role: AdmittedModelRole = .cleanup,
  architectureSupported: Bool = true,
  physicalMemoryBytes: UInt64 = .max,
  availableDiskBytes: Int64
) -> AdmittedModelDescriptor? {
  GemmaCleanupModelSelection.resolveQualifiedAlternative(
    pendingModelID: modelID,
    role: role,
    qualification: qualification,
    architectureSupported: architectureSupported,
    physicalMemoryBytes: physicalMemoryBytes,
    availableDiskBytes: availableDiskBytes
  )
}

@MainActor
private final class GemmaSelectionInstallProbe: AdmittedModelInstalling {
  let snapshot: AdmittedModelInstallationSnapshot
  let updates: AsyncStream<AdmittedModelInstallationSnapshot>
  private(set) var installCount = 0
  private var installWaiter: CheckedContinuation<Void, Never>?

  init(descriptor: AdmittedModelDescriptor) {
    let initial = AdmittedModelInstallationSnapshot(
      recommendation: .recommended(descriptor),
      phase: .notInstalled,
      lastError: nil
    )
    snapshot = initial
    updates = AsyncStream { continuation in
      continuation.yield(initial)
      continuation.finish()
    }
  }

  func waitUntilInstalled() async {
    guard installCount == 0 else { return }
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      if installCount == 0 {
        installWaiter = continuation
      } else {
        continuation.resume()
      }
    }
  }

  func refresh() async {}

  func install() async {
    installCount += 1
    installWaiter?.resume()
    installWaiter = nil
  }

  func cancel() {}
  func repair() async {}
  func update() async {}
  func remove() async {}
}

@Test
func gemma8BitSpecificationBindsExactManifestRuntimeAndTerms() throws {
  let specification = GemmaCleanup8BitModelSpecification.self
  let raw = specification.rawDescriptor
  let descriptor = try AdmittedModelDescriptor(validating: raw)

  #expect(specification.family == "Gemma3Text")
  #expect(raw.role == .cleanup)
  #expect(raw.modelID == "mlx-community/gemma-3-1b-it-8bit")
  #expect(raw.revision == "7b963136f21d05ca8b367c93a9c47a7944ad281a")
  #expect(raw.runtimeABI == GemmaCleanupTestConfiguration.runtimeABI)
  #expect(raw.conversion == "MLX")
  #expect(raw.quantization == "standard8bit/group64")
  #expect(raw.license == "Gemma Terms of Use")
  #expect(raw.notices.contains("custom-licensed third-party model"))
  #expect(raw.notices.contains("not covered by Fleck's MPL-2.0 license"))
  #expect(raw.notices.contains("Review the Google Gemma Terms of Use"))
  #expect(raw.notices.contains("Text cleanup and Smart Capture filing"))
  #expect(raw.notices.contains("same selected model through the existing Gemma cleanup gate"))
  #expect(specification.manifest.totalByteCount == 1_422_735_116)
  #expect(specification.manifest.files == [
    .init(
      path: ".gitattributes",
      byteCount: 1_570,
      sha256: "34448b82c17d60fec9b65b1f093c115ddbaadc04beb1b0140b6bfed2e012a930"
    ),
    .init(
      path: "README.md",
      byteCount: 1_168,
      sha256: "e2d846a168ab74055ec08627f0f2c7c55a85f926dfa9774d869c50bf2a9895d8"
    ),
    .init(
      path: "added_tokens.json",
      byteCount: 35,
      sha256: "50b2f405ba56a26d4913fd772089992252d7f942123cc0a034d96424221ba946"
    ),
    .init(
      path: "config.json",
      byteCount: 1_098,
      sha256: "11609c5a184ab6c9dfc05cbff358e91b14116f150676997cbe5e0642a5102296"
    ),
    .init(
      path: "model.safetensors",
      byteCount: 1_383_448_829,
      sha256: "c0795eea60413fc455178c1d81f78bcf382af17ca530da4ddcf3838bc63746e8"
    ),
    .init(
      path: "model.safetensors.index.json",
      byteCount: 50_543,
      sha256: "b29b2ad4ed2d6e49e18c27d16f4762de972fc6ae7ebc54c720368db7e3cd6c58"
    ),
    .init(
      path: "preprocessor_config.json",
      byteCount: 570,
      sha256: "f688d6bb20c5017601c4011de7ca656da8485b540b05013efdaf986c0fcc918d"
    ),
    .init(
      path: "special_tokens_map.json",
      byteCount: 662,
      sha256: "2f7b0adf4fb469770bb1490e3e35df87b1dc578246c5e7e6fc76ecf33213a397"
    ),
    .init(
      path: "tokenizer.json",
      byteCount: 33_384_568,
      sha256: "4667f2089529e8e7657cfb6d1c19910ae71ff5f28aa7ab2ff2763330affad795"
    ),
    .init(
      path: "tokenizer.model",
      byteCount: 4_689_074,
      sha256: "1299c11d7cf632ef3b4e11937501358ada021bbdf7c47638d13c0ee982f2e79c"
    ),
    .init(
      path: "tokenizer_config.json",
      byteCount: 1_156_999,
      sha256: "bfe25c2735e395407beb78456ea9a6984a1f00d8c16fa04a8b75f2a614cf53e1"
    ),
  ])
  #expect(raw.files.count == 11)
  #expect(raw.downloadBytes == specification.manifest.totalByteCount)
  #expect(raw.installedBytes == raw.downloadBytes)
  #expect(descriptor.immutableIdentity.modelID == specification.modelID)
}

@Test
func settingsLabelsAreBoundToRecognizedModelIDs() throws {
  let fixture = TestDescriptors.tinyAdmittedASR
  let parakeet = try AdmittedModelDescriptor(validating: TestDescriptors.make(
    fixture,
    modelID: "FluidInference/parakeet-tdt-0.6b-v2-coreml",
    role: .asr
  ))
  let gemma4Bit = try AdmittedModelDescriptor(validating: TestDescriptors.make(
    fixture,
    modelID: "mlx-community/gemma-3-1b-it-qat-4bit",
    role: .cleanup
  ))
  let gemma8Bit = try AdmittedModelDescriptor(
    validating: GemmaCleanup8BitModelSpecification.rawDescriptor
  )

  func modelLabel(
    _ descriptor: AdmittedModelDescriptor,
    context: AdmittedModelSettingsContext
  ) -> String {
    AdmittedModelSettingsPresentation(
      snapshot: .init(
        recommendation: .recommended(descriptor),
        phase: .notInstalled,
        lastError: nil
      ),
      context: context
    ).modelLabel
  }

  #expect(modelLabel(parakeet, context: .dictation) == "Parakeet TDT 0.6B v2")
  #expect(modelLabel(gemma4Bit, context: .cleanup(fallbackLabel: "Fallback")) == "Gemma 3 1B")
  #expect(modelLabel(gemma8Bit, context: .cleanup(fallbackLabel: "Fallback")) == "Gemma 3 1B (8-bit)")
  #expect(
    modelLabel(fixture, context: .dictation) == "example/tiny"
  )
  #expect(
    modelLabel(fixture, context: .cleanup(fallbackLabel: "Fallback")) == "example/tiny"
  )
}

@Test
func gemma8BitSelectionRequiresExactMeasuredQualifiedIdentityAndCapacity() throws {
  let descriptor = try AdmittedModelDescriptor(
    validating: GemmaCleanup8BitModelSpecification.rawDescriptor
  )
  let diskRequirement = descriptor.requiredCapacityBytes
  let qualification = try syntheticGemma8BitQualification()

  #expect(
    resolveGemma8Bit(qualification, availableDiskBytes: diskRequirement) == .some(descriptor)
  )
  #expect(resolveGemma8Bit(nil, availableDiskBytes: diskRequirement) == nil)
  #expect(
    resolveGemma8Bit(qualification, modelID: "unknown/model", availableDiskBytes: diskRequirement) == nil
  )
  #expect(resolveGemma8Bit(qualification, modelID: nil, availableDiskBytes: diskRequirement) == nil)
  #expect(
    resolveGemma8Bit(qualification, role: .asr, availableDiskBytes: diskRequirement) == nil
  )
  #expect(
    resolveGemma8Bit(
      qualification,
      architectureSupported: false,
      availableDiskBytes: diskRequirement
    ) == nil
  )
  #expect(
    resolveGemma8Bit(qualification, physicalMemoryBytes: 0, availableDiskBytes: diskRequirement) == nil
  )
  #expect(resolveGemma8Bit(qualification, availableDiskBytes: diskRequirement - 1) == nil)

  let identity = descriptor.immutableIdentity
  func alteredIdentity(
    revision: String? = nil,
    runtimeABI: String? = nil,
    files: [AdmittedModelFile]? = nil
  ) -> AdmittedModelImmutableIdentity {
    AdmittedModelImmutableIdentity(
      role: identity.role,
      sourceRepository: identity.sourceRepository,
      modelID: identity.modelID,
      revision: revision ?? identity.revision,
      license: identity.license,
      runtimeABI: runtimeABI ?? identity.runtimeABI,
      conversion: identity.conversion,
      quantization: identity.quantization,
      files: files ?? identity.files,
      downloadBytes: identity.downloadBytes,
      installedBytes: identity.installedBytes,
      requiredCapacityBytes: identity.requiredCapacityBytes
    )
  }
  let configFileIndex = try #require(identity.files.firstIndex { $0.path == "config.json" })
  var filesWithChangedConfigHash = identity.files
  let configFile = filesWithChangedConfigHash[configFileIndex]
  filesWithChangedConfigHash[configFileIndex] = AdmittedModelFile(
    path: configFile.path,
    byteCount: configFile.byteCount,
    sha256: String(repeating: "0", count: 64)
  )
  let invalidQualifications = [
    try syntheticGemma8BitQualification(
      identity: alteredIdentity(revision: String(repeating: "0", count: 40))
    ),
    try syntheticGemma8BitQualification(
      identity: alteredIdentity(runtimeABI: identity.runtimeABI + "-mismatch")
    ),
    try syntheticGemma8BitQualification(
      identity: alteredIdentity(files: filesWithChangedConfigHash)
    ),
    try syntheticGemma8BitQualification(applicability: .notApplicable),
    try syntheticGemma8BitQualification(minimumRAMBytes: 0),
    try syntheticGemma8BitQualification(minimumRAMBytes: 2, workingRAMBytes: 1),
    try syntheticGemma8BitQualification(storageBytes: descriptor.installedBytes - 1),
    try syntheticGemma8BitQualification(license: .ccBy40Reviewed),
    try syntheticGemma8BitQualification(cleanupEvidence: .identityVerified),
    try syntheticGemma8BitQualification(smartFilingEvidence: nil),
    try syntheticGemma8BitQualification(smartFilingEvidence: .identityVerified),
    try syntheticGemma8BitQualification(admission: .twoDeviceAccepted),
    try syntheticGemma8BitQualification(family: "another-family"),
  ]
  for invalid in invalidQualifications {
    #expect(resolveGemma8Bit(invalid, availableDiskBytes: diskRequirement) == nil)
  }
}

@Test @MainActor
func pendingGemmaRequestUsesLegacyDefaultUnlessSyntheticQualificationIsComplete() async throws {
  let descriptor = try AdmittedModelDescriptor(
    validating: GemmaCleanup8BitModelSpecification.rawDescriptor
  )
  let qualification = try syntheticGemma8BitQualification()
  var preferences = AppPreferences(
    pendingCleanupModelID: GemmaCleanup8BitModelSpecification.modelID
  )
  let pendingAtStartup = preferences.pendingCleanupModelID
  let root = TestPaths.temporaryDirectory()
  defer { TestPaths.remove(root) }
  func makeConfiguration(
    pendingModelID: String?,
    qualification: GemmaCleanupModelQualification? = nil
  ) throws -> AdmittedModelSignedConfiguration {
    try GemmaCleanupTestConfiguration.make(
      admittedBaseRoot: root,
      capacityProvider: { .max },
      architectureProvider: { true },
      startup: {},
      calibrate: {},
      pendingCleanupModelID: pendingModelID,
      qualification: qualification
    )
  }

  let unqualified = try makeConfiguration(pendingModelID: pendingAtStartup)
  let noPendingSelection = try makeConfiguration(
    pendingModelID: nil,
    qualification: qualification
  )
  let unknownPendingSelection = try makeConfiguration(
    pendingModelID: "unknown/model",
    qualification: qualification
  )
  #expect(unqualified.rawDescriptor.modelID == "mlx-community/gemma-3-1b-it-qat-4bit")
  #expect(noPendingSelection.rawDescriptor.modelID == unqualified.rawDescriptor.modelID)
  #expect(unknownPendingSelection.rawDescriptor.modelID == unqualified.rawDescriptor.modelID)
  let unqualifiedInstaller = makeAdmittedModelInstaller(
    signedConfiguration: unqualified,
    expectedRole: .cleanup
  )
  let unqualifiedViewModel = AdmittedModelSettingsViewModel(
    installer: unqualifiedInstaller,
    context: .cleanup(fallbackLabel: "Faithful Local Fallback")
  )
  #expect(
    unqualifiedViewModel.presentation.identity == .some("mlx-community/gemma-3-1b-it-qat-4bit")
  )
  #expect(unqualifiedViewModel.presentation.primaryAction == .some(.install))
  #expect(preferences.pendingCleanupModelID == pendingAtStartup)

  let selected = try makeConfiguration(
    pendingModelID: pendingAtStartup,
    qualification: qualification
  )
  let startupIdentity = selected.manager.admittedArtifactIdentity.immutableIdentity
  let startupModelID = selected.rawDescriptor.modelID
  preferences.pendingCleanupModelID = "mlx-community/gemma-3-1b-it-qat-4bit"

  #expect(selected.rawDescriptor.modelID == GemmaCleanup8BitModelSpecification.modelID)
  #expect(
    selected.manager.admittedArtifactIdentity.immutableIdentity == descriptor.immutableIdentity
  )
  #expect(selected.manager.modelRootURL != unqualified.manager.modelRootURL)
  try AdmittedModelStorageNamespace.validate(
    managerRootURL: selected.manager.modelRootURL,
    selected: selected.manager.selectedAdmittedStorageNamespace,
    descriptor: descriptor
  )

  let installProbe = GemmaSelectionInstallProbe(descriptor: descriptor)
  let cleanupViewModel = AdmittedModelSettingsViewModel(
    installer: installProbe,
    context: .cleanup(fallbackLabel: "Faithful Local Fallback")
  )
  cleanupViewModel.perform(.install)
  await installProbe.waitUntilInstalled()
  #expect(installProbe.installCount == 1)
  #expect(preferences.pendingCleanupModelID == "mlx-community/gemma-3-1b-it-qat-4bit")
  #expect(selected.manager.admittedArtifactIdentity.immutableIdentity == startupIdentity)
  #expect(selected.rawDescriptor.modelID == startupModelID)

  let speechViewModel = AdmittedModelSettingsViewModel(
    installer: BuiltInAdmittedModelInstaller()
  )
  #expect(ModelLibraryCatalog.entries(
    speechViewModel: speechViewModel,
    cleanupViewModel: cleanupViewModel
  ).isEmpty)
  #expect(preferences.pendingCleanupModelID == "mlx-community/gemma-3-1b-it-qat-4bit")
}
#endif
