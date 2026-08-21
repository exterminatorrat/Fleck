import Foundation
import CryptoKit
import Testing

@testable import FleckApp

enum TestFixtures {
  static let tinyBytes = Data("fixture!".utf8) // exactly 8 bytes
  static let tinySHA256 = SHA256.hash(data: tinyBytes)
    .map { String(format: "%02x", $0) }
    .joined()
}

@Test @MainActor
func defaultBuildUsesBuiltInInstallerWithoutManagerReference() async {
  let installer = BuiltInAdmittedModelInstaller()
  await installer.install()
  #expect(installer.snapshot.phase == .builtIn)
}

#if CLEAN_DICTATION_ENHANCED_CANDIDATE
enum TestDescriptors {
  static let tinyAdmittedASR = makeValidated(
    modelID: "example/tiny",
    languages: ["en-US"]
  )

  static let neutralAdmitted = makeValidated(
    modelID: "example/neutral",
    languages: ["en-US", "zh-CN"]
  )

  private static func makeValidated(
    modelID: String,
    languages: [String]
  ) -> AdmittedModelDescriptor {
    try! AdmittedModelDescriptor(validating: RawAdmittedModelDescriptor(
      role: .asr,
      modelID: modelID,
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
      languages: languages,
      architectures: ["arm64"]
    ))
  }

  static func raw(
    _ descriptor: AdmittedModelDescriptor
  ) -> RawAdmittedModelDescriptor {
    make(descriptor, modelID: descriptor.modelID)
  }

  static func make(
    _ descriptor: AdmittedModelDescriptor,
    modelID: String
  ) -> RawAdmittedModelDescriptor {
    RawAdmittedModelDescriptor(
      role: descriptor.role,
      modelID: modelID,
      revision: descriptor.revision,
      runtimeABI: descriptor.runtimeABI,
      conversion: descriptor.conversion,
      quantization: descriptor.quantization,
      license: descriptor.license,
      notices: descriptor.notices,
      source: descriptor.source,
      files: descriptor.files,
      downloadBytes: descriptor.downloadBytes,
      installedBytes: descriptor.installedBytes,
      languages: descriptor.languages,
      architectures: descriptor.architectures
    )
  }
}

enum TestManifests {
  static let tiny = EnhancedModelManifest(
    schemaVersion: 1,
    modelID: TestDescriptors.tinyAdmittedASR.modelID,
    revision: TestDescriptors.tinyAdmittedASR.revision,
    totalByteCount: Int64(TestFixtures.tinyBytes.count),
    files: [
      .init(
        path: TestFixtures.tinyAdmittedPath,
        byteCount: Int64(TestFixtures.tinyBytes.count),
        sha256: TestFixtures.tinySHA256
      )
    ]
  )

  static func make(
    _ manifest: EnhancedModelManifest,
    schemaVersion: Int? = nil,
    modelID: String? = nil,
    revision: String? = nil,
    files: [EnhancedModelFile]? = nil,
    totalByteCount: Int64? = nil
  ) -> EnhancedModelManifest {
    EnhancedModelManifest(
      schemaVersion: schemaVersion ?? manifest.schemaVersion,
      modelID: modelID ?? manifest.modelID,
      revision: revision ?? manifest.revision,
      totalByteCount: totalByteCount ?? manifest.totalByteCount,
      files: files ?? manifest.files
    )
  }
}

extension TestFixtures {
  static let tinyAdmittedPath = "model.bin"
}

enum TestArtifacts {
  static func identity(
    matching descriptor: AdmittedModelDescriptor
  ) -> EnhancedModelArtifactIdentity {
    EnhancedModelArtifactIdentity(
      sourceRepository: descriptor.source,
      modelID: descriptor.modelID,
      revision: descriptor.revision,
      license: descriptor.license,
      runtimeABI: descriptor.runtimeABI,
      conversion: descriptor.conversion,
      quantization: descriptor.quantization,
      files: descriptor.files,
      downloadBytes: descriptor.downloadBytes,
      installedBytes: descriptor.installedBytes,
      requiredCapacityBytes: descriptor.requiredCapacityBytes
    )
  }

  static func identityWith(
    sourceRepository: URL? = nil,
    modelID: String? = nil,
    revision: String? = nil,
    license: String? = nil,
    runtimeABI: String? = nil,
    conversion: String? = nil,
    quantization: String? = nil,
    files: [AdmittedModelFile]? = nil,
    downloadBytes: Int64? = nil,
    installedBytes: Int64? = nil,
    requiredCapacityBytes: Int64? = nil
  ) -> EnhancedModelArtifactIdentity {
    identity(
      identity(
        matching: TestDescriptors.tinyAdmittedASR
      ),
      sourceRepository: sourceRepository,
      modelID: modelID,
      revision: revision,
      license: license,
      runtimeABI: runtimeABI,
      conversion: conversion,
      quantization: quantization,
      files: files,
      downloadBytes: downloadBytes,
      installedBytes: installedBytes,
      requiredCapacityBytes: requiredCapacityBytes
    )
  }

  static func identity(
    _ base: EnhancedModelArtifactIdentity,
    sourceRepository: URL? = nil,
    modelID: String? = nil,
    revision: String? = nil,
    license: String? = nil,
    runtimeABI: String? = nil,
    conversion: String? = nil,
    quantization: String? = nil,
    files: [AdmittedModelFile]? = nil,
    downloadBytes: Int64? = nil,
    installedBytes: Int64? = nil,
    requiredCapacityBytes: Int64? = nil
  ) -> EnhancedModelArtifactIdentity {
    EnhancedModelArtifactIdentity(
      sourceRepository: sourceRepository ?? base.sourceRepository,
      modelID: modelID ?? base.modelID,
      revision: revision ?? base.revision,
      license: license ?? base.license,
      runtimeABI: runtimeABI ?? base.runtimeABI,
      conversion: conversion ?? base.conversion,
      quantization: quantization ?? base.quantization,
      files: files ?? base.files,
      downloadBytes: downloadBytes ?? base.downloadBytes,
      installedBytes: installedBytes ?? base.installedBytes,
      requiredCapacityBytes: requiredCapacityBytes
        ?? base.requiredCapacityBytes
    )
  }
}

final class SynchronousCapacityProbe: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Int64

  init(_ value: Int64) { self.value = value }

  func read() -> Int64 {
    lock.lock()
    defer { lock.unlock() }
    return value
  }

  func set(_ value: Int64) {
    lock.lock()
    self.value = value
    lock.unlock()
  }
}

final class ModelDownloadingProbe: ModelDownloading, @unchecked Sendable {
  private let lock = NSLock()
  private let bytes: Data
  private let progressSequence: [Int64]
  private let pausesUntilCancelled: Bool
  private let pausesAfterFirstProgress: Bool
  private var calls = 0
  private var started = false
  private var firstProgressPublished = false
  private var releaseRequested = false
  private var cancellationRequested = false
  private var cancellationContinuation:
    CheckedContinuation<ModelDownloadResult, Error>?
  private var releaseContinuation: CheckedContinuation<Void, Never>?
  private var startWaiters: [CheckedContinuation<Void, Never>] = []
  private var firstProgressWaiters: [CheckedContinuation<Void, Never>] = []

  init(
    bytes: Data,
    progressSequence: [Int64] = [4, 8, 8],
    pausesUntilCancelled: Bool = false,
    pausesAfterFirstProgress: Bool = false
  ) {
    self.bytes = bytes
    self.progressSequence = progressSequence
    self.pausesUntilCancelled = pausesUntilCancelled
    self.pausesAfterFirstProgress = pausesAfterFirstProgress
  }

  var downloadCalls: Int {
    lock.withLock { calls }
  }

  var cancelObserved: Bool {
    lock.withLock { cancellationRequested }
  }

  func sessionProducedResumeToken(
    for data: Data,
    remoteURL: URL
  ) -> ModelResumeToken? {
    nil
  }

  func download(
    from remoteURL: URL,
    resumeToken: ModelResumeToken?,
    progress: @escaping @Sendable (Int64, Int64) -> Void
  ) async throws -> ModelDownloadResult {
    let startWaiters = lock.withLock {
      calls += 1
      started = true
      defer { self.startWaiters.removeAll() }
      return self.startWaiters
    }
    startWaiters.forEach { $0.resume() }

    if pausesUntilCancelled {
      return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
          let cancelNow = lock.withLock {
            if cancellationRequested {
              return true
            }
            cancellationContinuation = continuation
            return false
          }
          if cancelNow {
            continuation.resume(
              throwing: ModelDownloadError.cancelled(resumeData: nil)
            )
          }
        }
      } onCancel: {
        self.requestCancellation()
      }
    }

    for (index, receivedBytes) in progressSequence.enumerated() {
      let firstProgressWaiters = lock.withLock {
        if index == 0 {
          firstProgressPublished = true
          defer { self.firstProgressWaiters.removeAll() }
          return self.firstProgressWaiters
        }
        return []
      }
      firstProgressWaiters.forEach { $0.resume() }
      progress(receivedBytes, Int64(bytes.count))
      if pausesAfterFirstProgress && index == 0 {
        await waitForProgressRelease()
      }
    }

    return ModelDownloadResult(
      temporaryURL: try writeTemporary(bytes),
      resumeData: nil
    )
  }

  func waitUntilStarted() async {
    await withCheckedContinuation { continuation in
      let resumeNow = lock.withLock {
        if started {
          return true
        }
        startWaiters.append(continuation)
        return false
      }
      if resumeNow {
        continuation.resume()
      }
    }
  }

  func waitUntilFirstProgress() async {
    await withCheckedContinuation { continuation in
      let resumeNow = lock.withLock {
        if firstProgressPublished {
          return true
        }
        firstProgressWaiters.append(continuation)
        return false
      }
      if resumeNow {
        continuation.resume()
      }
    }
  }

  func releaseProgress() {
    let continuation = lock.withLock {
      releaseRequested = true
      defer { releaseContinuation = nil }
      return releaseContinuation
    }
    continuation?.resume()
  }

  private func waitForProgressRelease() async {
    await withCheckedContinuation { continuation in
      let resumeNow = lock.withLock {
        if releaseRequested {
          return true
        }
        releaseContinuation = continuation
        return false
      }
      if resumeNow {
        continuation.resume()
      }
    }
  }

  private func requestCancellation() {
    let continuation = lock.withLock {
      cancellationRequested = true
      defer { cancellationContinuation = nil }
      return cancellationContinuation
    }
    continuation?.resume(
      throwing: ModelDownloadError.cancelled(resumeData: nil)
    )
  }
}

actor PhaseRecorder {
  private(set) var values: [String] = []

  func append(_ value: String) {
    values.append(value)
  }
}

struct ObservedProgress: Equatable, Sendable {
  let receivedBytes: Int64
  let totalBytes: Int64
}

actor ProgressSnapshotRecorder {
  private(set) var values: [ObservedProgress] = []
  private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

  func append(_ value: ObservedProgress) {
    values.append(value)
    let ready = waiters.filter { $0.0 <= values.count }
    waiters.removeAll { $0.0 <= values.count }
    ready.forEach { $0.1.resume() }
  }

  func waitUntilCount(_ count: Int) async {
    guard values.count < count else { return }
    await withCheckedContinuation { continuation in
      if values.count >= count {
        continuation.resume()
      } else {
        waiters.append((count, continuation))
      }
    }
  }
}

enum TestPaths {
  static func temporaryDirectory() -> URL {
    let candidate = URL(fileURLWithPath: "/Users/Shared", isDirectory: true)
      .appendingPathComponent("FleckTests-\(UUID().uuidString)", isDirectory: true)
      .standardizedFileURL
    do {
      try FileManager.default.createDirectory(
        at: candidate,
        withIntermediateDirectories: false
      )
      return candidate.resolvingSymlinksInPath().standardizedFileURL
    } catch {
      preconditionFailure("Unable to create isolated test directory: \(error)")
    }
  }

  static func remove(_ directory: URL) {
    try? FileManager.default.removeItem(at: directory)
  }
}

@MainActor
final class TestManagerFixture {
  let root: URL
  let manager: EnhancedModelManager

  init(
    descriptor: AdmittedModelDescriptor,
    artifactIdentity: EnhancedModelArtifactIdentity,
    manifest: EnhancedModelManifest,
    transport: any ModelDownloading,
    refreshFixture: TestRefreshFixture? = nil,
    capacityProvider: @escaping @Sendable () throws -> Int64 = { Int64.max },
    architectureProvider: @escaping @Sendable () -> Bool = { true }
  ) throws {
    root = TestPaths.temporaryDirectory()
    do {
      let namespace = try AdmittedModelStorageNamespace(
        baseRootURL: root,
        descriptor: descriptor
      )
      let trustedManifests = try refreshFixture?.seed(
        root: namespace.rootURL,
        current: manifest
      ) ?? [manifest]
      manager = try EnhancedModelManager(
        admittedBaseRoot: root,
        descriptor: descriptor,
        manifest: manifest,
        artifactIdentity: artifactIdentity,
        trustedManifests: trustedManifests,
        candidateEnabled: true,
        capacityProvider: capacityProvider,
        architectureProvider: architectureProvider,
        transport: transport
      )
    } catch {
      TestPaths.remove(root)
      throw error
    }
  }

  func cleanup() {
    TestPaths.remove(root)
  }
}

enum TestManagers {
  @MainActor
  static func manager(
    descriptor: AdmittedModelDescriptor,
    artifactIdentity: EnhancedModelArtifactIdentity,
    manifest: EnhancedModelManifest,
    transport: any ModelDownloading,
    refreshFixture: TestRefreshFixture? = nil,
    capacityProvider: @escaping @Sendable () throws -> Int64 = {
      Int64.max
    },
    architectureProvider: @escaping @Sendable () -> Bool = { true }
  ) throws -> TestManagerFixture {
    try TestManagerFixture(
      descriptor: descriptor,
      artifactIdentity: artifactIdentity,
      manifest: manifest,
      transport: transport,
      refreshFixture: refreshFixture,
      capacityProvider: capacityProvider,
      architectureProvider: architectureProvider
    )
  }

  @MainActor
  static func managerAtRoot(
    descriptor: AdmittedModelDescriptor,
    artifactIdentity: EnhancedModelArtifactIdentity,
    manifest: EnhancedModelManifest,
    transport: any ModelDownloading,
    modelRootURL: URL,
    admittedStorageNamespace: AdmittedModelStorageNamespace
  ) -> EnhancedModelManager {
    EnhancedModelManager(
      modelRootURL: modelRootURL,
      manifest: manifest,
      artifactIdentity: artifactIdentity,
      candidateEnabled: true,
      capacityProvider: { Int64.max },
      architectureProvider: { true },
      transport: transport,
      admittedStorageNamespace: admittedStorageNamespace
    )
  }
}

enum TestRefreshFixture: Equatable {
  case ready
  case updateAvailable
  case repairRequired

  func seed(
    root: URL,
    current: EnhancedModelManifest
  ) throws -> [EnhancedModelManifest] {
    let fileManager = FileManager.default
    let modelName = try #require(current.modelID.split(separator: "/").last)

    func seedInstall(
      _ manifest: EnhancedModelManifest,
      bytes: Data
    ) throws {
      let repository = root
        .appendingPathComponent("installed", isDirectory: true)
        .appendingPathComponent(manifest.revision, isDirectory: true)
        .appendingPathComponent(String(modelName), isDirectory: true)
      try fileManager.createDirectory(
        at: repository,
        withIntermediateDirectories: true
      )
      let file = repository.appendingPathComponent(manifest.files[0].path)
      try fileManager.createDirectory(
        at: file.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try bytes.write(to: file, options: .atomic)
      try JSONEncoder().encode(manifest).write(
        to: repository.deletingLastPathComponent()
          .appendingPathComponent("manifest.json"),
        options: .atomic
      )
    }

    switch self {
    case .ready:
      try seedInstall(current, bytes: TestFixtures.tinyBytes)
      return [current]
    case .updateAvailable:
      let previous = TestManifests.make(
        current,
        revision: "previous-revision"
      )
      try seedInstall(previous, bytes: TestFixtures.tinyBytes)
      return [current, previous]
    case .repairRequired:
      try seedInstall(current, bytes: Data("bad".utf8))
      return [current]
    }
  }
}

private func writeTemporary(_ data: Data) throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString)
  try data.write(to: url)
  return url
}

@Test @MainActor
func existingDictationModelCapabilityCallShapesRemainSourceCompatible() {
  let defaultRoot = TestPaths.temporaryDirectory()
  let testRoot = TestPaths.temporaryDirectory()
  defer {
    TestPaths.remove(defaultRoot)
    TestPaths.remove(testRoot)
  }
  // This call uses the production capacity and arm64 defaults.
  let defaultCapability = DictationModelCapability(
    modelRootURL: defaultRoot
  )
  // This is the existing test shape; only its architecture probe is injected.
  let testCapability = DictationModelCapability(
    modelRootURL: testRoot,
    candidateEnabled: true,
    architectureProvider: { true }
  )
  #expect(defaultCapability.state == .notInstalled)
  #expect(testCapability.state == .notInstalled)
}

@Test @MainActor
func fakeInstallReportsBytesThenVerificationStartupAndCalibration() async {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let transport = ModelDownloadingProbe(bytes: TestFixtures.tinyBytes)
  #expect(TestFixtures.tinyBytes.count == 8)
  #expect(descriptor.downloadBytes == 8)
  #expect(TestManifests.tiny.totalByteCount == 8)
  #expect(TestManifests.tiny.files[0].byteCount == 8)
  #expect(TestManifests.tiny.files[0].sha256 == TestFixtures.tinySHA256)
  #expect(TestArtifacts.identity(matching: descriptor).downloadBytes == 8)
  #expect(TestArtifacts.identity(matching: descriptor).files[0].byteCount == 8)
  #expect(TestArtifacts.identity(matching: descriptor).files[0].sha256 == TestFixtures.tinySHA256)
  let lifecycle = PhaseRecorder()
  let fixture = try! TestManagers.manager(
    descriptor: descriptor,
    artifactIdentity: TestArtifacts.identity(matching: descriptor),
    manifest: TestManifests.tiny,
    transport: transport
  )
  defer { fixture.cleanup() }
  let manager = fixture.manager
  let installer = try! EnhancedModelManagerInstaller(
    manager: manager,
    descriptor: descriptor,
    startup: { await lifecycle.append("startup") },
    calibrate: { await lifecycle.append("calibration") }
  )

  await installer.install()

  #expect(installer.phaseHistory.suffix(9) == [
    .downloading(receivedBytes: 0, totalBytes: descriptor.downloadBytes),
    .downloading(receivedBytes: 4, totalBytes: descriptor.downloadBytes),
    .downloading(receivedBytes: 8, totalBytes: descriptor.downloadBytes),
    .verifying,
    .installing,
    .ready,
    .starting,
    .calibrating,
    .installed
  ])
  #expect(await lifecycle.values == ["startup", "calibration"])
  #expect(installer.snapshot.phase == .installed)
}

@Test @MainActor
func checksumFailureBecomesActionableRepairState() async {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let fixture = try! TestManagers.manager(
    descriptor: descriptor,
    artifactIdentity: TestArtifacts.identity(matching: descriptor),
    manifest: TestManifests.tiny,
    transport: ModelDownloadingProbe(bytes: Data("corrupt!".utf8))
  )
  defer { fixture.cleanup() }
  let manager = fixture.manager
  let installer = try! EnhancedModelManagerInstaller(
    manager: manager,
    descriptor: descriptor,
    startup: { },
    calibrate: { }
  )
  await installer.install()
  guard case .repairRequired(let message) = installer.snapshot.phase else {
    Issue.record("Expected repair state")
    return
  }
  #expect(message.contains("checksum"))
}

@Test @MainActor
func refreshMapsStaleStateWithoutStartingOperation() async throws {
  let cases: [TestRefreshFixture] = [
    .ready,
    .updateAvailable,
    .repairRequired
  ]

  for refreshFixture in cases {
    let descriptor = TestDescriptors.tinyAdmittedASR
    let transport = ModelDownloadingProbe(bytes: TestFixtures.tinyBytes)
    let fixture = try TestManagers.manager(
      descriptor: descriptor,
      artifactIdentity: TestArtifacts.identity(matching: descriptor),
      manifest: TestManifests.tiny,
      transport: transport,
      refreshFixture: refreshFixture
    )
    defer { fixture.cleanup() }
    let manager = fixture.manager
    let installer = try EnhancedModelManagerInstaller(
      manager: manager,
      descriptor: descriptor,
      startup: { Issue.record("refresh must not start startup") },
      calibrate: { Issue.record("refresh must not start calibration") }
    )

    #expect(installer.snapshot.phase == .notInstalled)
    await installer.refresh()

    switch refreshFixture {
    case .ready:
      #expect(installer.snapshot.phase == .ready)
    case .updateAvailable:
      #expect(installer.snapshot.phase == .updateAvailable)
    case .repairRequired:
      guard case .repairRequired = installer.snapshot.phase else {
        Issue.record("Expected the manager's filesystem repairRequired state")
        continue
      }
    }
    #expect(transport.downloadCalls == 0)
    #expect(!installer.phaseHistory.contains {
      if case .downloading = $0 { return true }
      return false
    })
  }
}

@Test @MainActor
func liveCapacityGateRejectsInstallRepairAndUpdateBeforeTransport() async {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let initialAvailableBytes = descriptor.requiredCapacityBytes + 1
  let insufficientAvailableBytes = descriptor.downloadBytes + 1
  #expect(insufficientAvailableBytes > descriptor.downloadBytes)
  #expect(insufficientAvailableBytes < descriptor.requiredCapacityBytes)
  let catalog = AdmittedModelCatalog(
    signedDescriptor: descriptor,
    hardware: .init(
      architecture: descriptor.architectures[0],
      requestedLanguages: [descriptor.languages[0]],
      availableBytes: initialAvailableBytes
    )
  )
  #expect(catalog.recommendation() == .recommended(descriptor))
  let operations: [(String, TestRefreshFixture?)] = [
    ("install", nil),
    ("repair", .repairRequired),
    ("update", .updateAvailable)
  ]

  for (operation, refreshFixture) in operations {
    let capacity = SynchronousCapacityProbe(initialAvailableBytes)
    let transport = ModelDownloadingProbe(bytes: TestFixtures.tinyBytes)
    let fixture = try! TestManagers.manager(
      descriptor: descriptor,
      artifactIdentity: TestArtifacts.identity(matching: descriptor),
      manifest: TestManifests.tiny,
      transport: transport,
      refreshFixture: refreshFixture,
      capacityProvider: { capacity.read() }
    )
    defer { fixture.cleanup() }
    let manager = fixture.manager
    let installer = try! EnhancedModelManagerInstaller(
      manager: manager,
      descriptor: descriptor,
      startup: { },
      calibrate: { }
    )
    if refreshFixture != nil { await installer.refresh() }
    capacity.set(insufficientAvailableBytes)
    switch operation {
    case "install": await installer.install()
    case "repair": await installer.repair()
    case "update": await installer.update()
    default: Issue.record("Unexpected fixture operation")
    }
    #expect(transport.downloadCalls == 0)
    #expect(!installer.phaseHistory.contains {
      if case .downloading = $0 { return true }
      return false
    })
    #expect(installer.snapshot.lastError != nil)
  }
}

@Test @MainActor
func removeDeletesOnlyTheSelectedAdmittedNamespace() async throws {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let baseRoot = TestPaths.temporaryDirectory()
  defer { TestPaths.remove(baseRoot) }
  let namespace = try AdmittedModelStorageNamespace(
    baseRootURL: baseRoot,
    descriptor: descriptor
  )
  let fileManager = FileManager.default
  for layer in ["installed", "staging", "resume", "derived"] {
    let selected = namespace.rootURL.appendingPathComponent(layer, isDirectory: true)
    try fileManager.createDirectory(at: selected, withIntermediateDirectories: true)
    try Data("selected".utf8).write(
      to: selected.appendingPathComponent("sentinel"),
      options: .atomic
    )
  }
  let sibling = baseRoot
    .appendingPathComponent("sibling-model", isDirectory: true)
    .appendingPathComponent("installed", isDirectory: true)
  try fileManager.createDirectory(at: sibling, withIntermediateDirectories: true)
  let siblingFile = sibling.appendingPathComponent("sentinel")
  try Data("sibling".utf8).write(to: siblingFile)

  let manager = TestManagers.managerAtRoot(
    descriptor: descriptor,
    artifactIdentity: TestArtifacts.identity(matching: descriptor),
    manifest: TestManifests.tiny,
    transport: ModelDownloadingProbe(bytes: TestFixtures.tinyBytes),
    modelRootURL: namespace.rootURL,
    admittedStorageNamespace: namespace
  )
  let installer = try EnhancedModelManagerInstaller(
    manager: manager,
    descriptor: descriptor,
    startup: { },
    calibrate: { }
  )

  await installer.remove()

  for layer in ["installed", "staging", "resume", "derived"] {
    #expect(!fileManager.fileExists(
      atPath: namespace.rootURL.appendingPathComponent(layer).path
    ))
  }
  #expect(fileManager.fileExists(atPath: namespace.rootURL.path))
  #expect(fileManager.fileExists(atPath: siblingFile.path))
  #expect(fileManager.fileExists(atPath: baseRoot.path))
}

@Test @MainActor
func admittedInstallerRejectsSharedOrWrongNamespaceBeforeOperation() throws {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let baseRoot = TestPaths.temporaryDirectory()
  defer { TestPaths.remove(baseRoot) }
  let selected = try AdmittedModelStorageNamespace(
    baseRootURL: baseRoot,
    descriptor: descriptor
  )

  let sharedTransport = ModelDownloadingProbe(bytes: TestFixtures.tinyBytes)
  let sharedManager = TestManagers.managerAtRoot(
    descriptor: descriptor,
    artifactIdentity: TestArtifacts.identity(matching: descriptor),
    manifest: TestManifests.tiny,
    transport: sharedTransport,
    modelRootURL: baseRoot,
    admittedStorageNamespace: selected
  )
  #expect(throws: AdmittedModelStorageNamespace.Error.managerRootMismatch) {
    _ = try EnhancedModelManagerInstaller(
      manager: sharedManager,
      descriptor: descriptor,
      startup: { },
      calibrate: { }
    )
  }

  let wrong = try AdmittedModelStorageNamespace(
    baseRootURL: baseRoot,
    descriptor: TestDescriptors.neutralAdmitted
  )
  let wrongTransport = ModelDownloadingProbe(bytes: TestFixtures.tinyBytes)
  let wrongManager = TestManagers.managerAtRoot(
    descriptor: descriptor,
    artifactIdentity: TestArtifacts.identity(matching: descriptor),
    manifest: TestManifests.tiny,
    transport: wrongTransport,
    modelRootURL: wrong.rootURL,
    admittedStorageNamespace: wrong
  )
  #expect(throws: AdmittedModelStorageNamespace.Error.managerRootMismatch) {
    _ = try EnhancedModelManagerInstaller(
      manager: wrongManager,
      descriptor: descriptor,
      startup: { },
      calibrate: { }
    )
  }
  #expect(sharedTransport.downloadCalls == 0)
  #expect(wrongTransport.downloadCalls == 0)
}

@Test @MainActor
func cancellationPublishesCancelledAndCannotPublishInstalledLater() async {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let transport = ModelDownloadingProbe(
    bytes: TestFixtures.tinyBytes,
    pausesUntilCancelled: true
  )
  let fixture = try! TestManagers.manager(
    descriptor: descriptor,
    artifactIdentity: TestArtifacts.identity(matching: descriptor),
    manifest: TestManifests.tiny,
    transport: transport
  )
  defer { fixture.cleanup() }
  let manager = fixture.manager
  let installer = try! EnhancedModelManagerInstaller(
    manager: manager,
    descriptor: descriptor,
    startup: { },
    calibrate: { }
  )

  let install = Task { await installer.install() }
  await transport.waitUntilStarted()
  installer.cancel()
  await install.value

  #expect(installer.snapshot.phase == .cancelled)
  #expect(installer.snapshot.lastError == "Model operation cancelled.")
  #expect(installer.phaseHistory.last != .installed)
  #expect(!installer.phaseHistory.contains(.installed))
  #expect(transport.cancelObserved)
}

@Test @MainActor
func descriptorArtifactMismatchFailsBeforeTransport() async {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let transport = ModelDownloadingProbe(bytes: TestFixtures.tinyBytes)
  let fixture = try! TestManagers.manager(
    descriptor: descriptor,
    artifactIdentity: TestArtifacts.identityWith(
      revision: "different-revision"
    ),
    manifest: TestManifests.tiny,
    transport: transport
  )
  defer { fixture.cleanup() }
  let manager = fixture.manager
  #expect(throws: AdmittedModelArtifactMismatch.descriptorArtifactMismatch) {
    _ = try EnhancedModelManagerInstaller(
      manager: manager,
      descriptor: descriptor,
      startup: { },
      calibrate: { }
    )
  }
  #expect(transport.downloadCalls == 0)
}

@Test @MainActor
func immutableArtifactMismatchesAreRejectedBeforeTransport() throws {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let valid = TestArtifacts.identity(matching: descriptor)
  let mismatches = [
    TestArtifacts.identity(valid, sourceRepository: URL(string: "https://example.invalid/other")!),
    TestArtifacts.identity(valid, modelID: "different-model"),
    TestArtifacts.identity(valid, revision: "different-revision"),
    TestArtifacts.identity(valid, license: "different-license"),
    TestArtifacts.identity(valid, runtimeABI: "different-runtime"),
    TestArtifacts.identity(valid, conversion: "different-conversion"),
    TestArtifacts.identity(valid, quantization: "different-quantization"),
    TestArtifacts.identity(valid, files: [ .init(path: "other.bin", byteCount: 4, sha256: String(repeating: "a", count: 64)) ]),
    TestArtifacts.identity(valid, files: [ .init(path: valid.files[0].path, byteCount: valid.files[0].byteCount, sha256: String(repeating: "b", count: 64)) ]),
    TestArtifacts.identity(valid, files: [ .init(path: valid.files[0].path, byteCount: valid.files[0].byteCount + 1, sha256: valid.files[0].sha256) ]),
    TestArtifacts.identity(valid, downloadBytes: valid.downloadBytes + 1),
    TestArtifacts.identity(valid, installedBytes: valid.installedBytes + 1),
    TestArtifacts.identity(
      valid,
      requiredCapacityBytes: valid.requiredCapacityBytes + 1
    )
  ]
  for artifact in mismatches {
    #expect(throws: AdmittedModelArtifactMismatch.descriptorArtifactMismatch) {
      try AdmittedModelArtifactBinding.validate(
        descriptor: descriptor,
        artifact: artifact,
        manifest: TestManifests.tiny
      )
    }
  }
}

@Test @MainActor
func artifactManifestMismatchesAreRejectedBeforeTransport() throws {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let artifact = TestArtifacts.identity(matching: descriptor)
  let mismatchedManifests = [
    TestManifests.make(TestManifests.tiny, schemaVersion: 2),
    TestManifests.make(TestManifests.tiny, modelID: "other/model"),
    TestManifests.make(TestManifests.tiny, revision: "other-revision"),
    TestManifests.make(
      TestManifests.tiny,
      files: [ .init(
        path: artifact.files[0].path,
        byteCount: artifact.files[0].byteCount,
        sha256: String(repeating: "b", count: 64)
      ) ]
    ),
    TestManifests.make(
      TestManifests.tiny,
      files: [ .init(
        path: artifact.files[0].path,
        byteCount: artifact.files[0].byteCount + 1,
        sha256: artifact.files[0].sha256
      ) ]
    ),
    TestManifests.make(TestManifests.tiny, totalByteCount: 999)
  ]
  for manifest in mismatchedManifests {
    #expect(throws: AdmittedModelArtifactMismatch.artifactManifestMismatch) {
      try AdmittedModelArtifactBinding.validate(
        descriptor: descriptor,
        artifact: artifact,
        manifest: manifest
      )
    }
  }
}

@Test @MainActor
func artifactManifestMismatchFailsBeforeTransport() {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let transport = ModelDownloadingProbe(bytes: TestFixtures.tinyBytes)
  let fixture = try! TestManagers.manager(
    descriptor: descriptor,
    artifactIdentity: TestArtifacts.identity(matching: descriptor),
    manifest: TestManifests.make(TestManifests.tiny, revision: "wrong"),
    transport: transport
  )
  defer { fixture.cleanup() }
  let manager = fixture.manager
  #expect(throws: AdmittedModelArtifactMismatch.artifactManifestMismatch) {
    _ = try EnhancedModelManagerInstaller(
      manager: manager,
      descriptor: descriptor,
      startup: { },
      calibrate: { }
    )
  }
  #expect(transport.downloadCalls == 0)
}

@Test
func artifactRemoteURLUsesExplicitSourceAndRevisionAndKeepsDownloadQuery() throws {
  let sourceRepository = URL(string: "https://example.invalid/custom-repository")!
  let revision = "custom-revision-123"
  let url = try EnhancedModelManager.remoteURL(
    for: .init(path: "folder/model.bin", byteCount: 4, sha256: String(repeating: "a", count: 64)),
    sourceRepository: sourceRepository,
    revision: revision
  )
  #expect(url.path == "/custom-repository/resolve/custom-revision-123/folder/model.bin")
  #expect(url.absoluteString == "https://example.invalid/custom-repository/resolve/custom-revision-123/folder/model.bin?download=true")
  #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems == [
    URLQueryItem(name: "download", value: "true")
  ])
}

@Test @MainActor
func managerRejectsDescriptorUnsafePathTableBeforeURLResolution() {
  let unsafePaths = [
    "", "/absolute.bin", "%2fabsolute.bin", ".", "..", "a//b",
    "a/./b", "a/../b", "a\\b", "a\\..\\b", "a/%2e%2e/b",
    "a/%252e%252e/b", "%6dodel.bin"
  ]
  for path in unsafePaths {
    do {
      _ = try EnhancedModelManager.remoteURL(
        for: .init(path: path, byteCount: 8, sha256: String(repeating: "a", count: 64)),
        sourceRepository: URL(string: "https://example.invalid/repository")!,
        revision: "revision"
      )
      Issue.record("Unsafe manager path unexpectedly reached URL construction: \(path)")
    } catch let error as EnhancedModelManagerError {
      #expect(error == .invalidManifestPath(path))
    } catch {
      Issue.record("Unexpected manager path error for \(path): \(error)")
    }
  }
}

@Test @MainActor
func managerRejectsDuplicateNormalizedManifestPathsBeforeTransport() async {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let duplicateManifest = TestManifests.make(
    TestManifests.tiny,
    files: [
      .init(path: "model.bin", byteCount: 8, sha256: TestFixtures.tinySHA256),
      .init(path: "model.bin", byteCount: 8, sha256: TestFixtures.tinySHA256)
    ],
    totalByteCount: 16
  )
  let transport = ModelDownloadingProbe(bytes: TestFixtures.tinyBytes)
  let fixture = try! TestManagers.manager(
    descriptor: descriptor,
    artifactIdentity: TestArtifacts.identity(matching: descriptor),
    manifest: duplicateManifest,
    transport: transport,
    capacityProvider: { Int64.max }
  )
  defer { fixture.cleanup() }
  let manager = fixture.manager
  do {
    try await manager.download()
    Issue.record("Duplicate normalized manifest paths unexpectedly downloaded")
  } catch let error as EnhancedModelManagerError {
    #expect(error == .invalidManifest)
  } catch {
    Issue.record("Unexpected duplicate-path manager error: \(error)")
  }
  #expect(transport.downloadCalls == 0)
}

@Test @MainActor
func installerUpdatesExposeBytesBeforeCompletion() async {
  let descriptor = TestDescriptors.tinyAdmittedASR
  let transport = ModelDownloadingProbe(
    bytes: TestFixtures.tinyBytes,
    progressSequence: [4, 8, 8],
    pausesAfterFirstProgress: true
  )
  let fixture = try! TestManagers.manager(
    descriptor: descriptor,
    artifactIdentity: TestArtifacts.identity(matching: descriptor),
    manifest: TestManifests.tiny,
    transport: transport
  )
  defer { fixture.cleanup() }
  let manager = fixture.manager
  let installer = try! EnhancedModelManagerInstaller(
    manager: manager,
    descriptor: descriptor,
    startup: { },
    calibrate: { }
  )
  let recorder = ProgressSnapshotRecorder()
  let updates = Task {
    for await snapshot in installer.updates {
      if case .downloading(let receivedBytes, let totalBytes) = snapshot.phase,
         receivedBytes > 0 {
        await recorder.append(ObservedProgress(
          receivedBytes: receivedBytes,
          totalBytes: totalBytes
        ))
      }
    }
  }
  let install = Task { await installer.install() }
  await transport.waitUntilFirstProgress()
  await recorder.waitUntilCount(1)
  let firstSnapshots = await recorder.values
  #expect(firstSnapshots.map(\.receivedBytes) == [4])
  #expect(firstSnapshots.map(\.totalBytes) == [descriptor.downloadBytes])
  await transport.releaseProgress()
  await install.value
  await recorder.waitUntilCount(2)
  let snapshots = await recorder.values
  #expect(snapshots.map(\.receivedBytes) == [4, 8])
  #expect(snapshots.map(\.totalBytes) == [
    descriptor.downloadBytes,
    descriptor.downloadBytes
  ])
  #expect(snapshots.map(\.receivedBytes) ==
    snapshots.map(\.receivedBytes).sorted())
  let publishedDownloads = installer.phaseHistory.compactMap { phase -> Int64? in
    guard case .downloading(let receivedBytes, let totalBytes) = phase else {
      return nil
    }
    #expect(totalBytes == descriptor.downloadBytes)
    return receivedBytes
  }
  #expect(publishedDownloads == [0, 4, 8])
  updates.cancel()
}
#endif
