import CryptoKit
import Combine
import Foundation
import Testing

@testable import MenuBarNotesApp

@Suite(.serialized)
struct EnhancedModelManagerTests {
  @Test @MainActor func missingInstallIsNotInstalled() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }

    await fixture.manager.refreshState()

    #expect(fixture.manager.state == .notInstalled)
  }

  @Test @MainActor func exactAllowlistIsReady() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.install()

    await fixture.manager.refreshState()

    #expect(fixture.manager.state == .ready)
    #expect(fixture.manager.verifiedRepositoryURL == fixture.repositoryURL)
  }

  @Test(arguments: Corruption.allCases)
  @MainActor
  func invalidInstallNeedsRepair(corruption: Corruption) async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.install(corruption: corruption)

    await fixture.manager.refreshState()

    guard case .repairRequired = fixture.manager.state else {
      Issue.record("Expected repairRequired, got \(fixture.manager.state)")
      return
    }
  }

  @Test @MainActor func intelDoesNotTouchStorageCapacityOrTransport() async throws {
    let root = temporaryRoot()
    let transport = TestTransport()
    let capacity = LockedCounter()
    let manager = EnhancedModelManager(
      modelRootURL: root,
      manifest: testManifest,
      capacityProvider: {
        capacity.increment()
        return Int64.max
      },
      architectureProvider: { false },
      clock: { Date.distantPast },
      transport: transport
    )
    defer { try? FileManager.default.removeItem(at: root) }

    await manager.refreshState()
    do {
      try await manager.download()
      Issue.record("Expected unsupported architecture")
    } catch {
      #expect(error as? EnhancedModelManagerError == .unsupportedArchitecture)
    }

    #expect(manager.isArchitectureSupported == false)
    #expect(manager.state == .notInstalled)
    #expect(!FileManager.default.fileExists(atPath: root.path))
    #expect(capacity.value == 0)
    #expect(transport.callCount == 0)
  }

  @Test @MainActor func insufficientCapacityReportsRequiredBytes() async throws {
    let fixture = try Fixture(capacity: EnhancedModelManager.requiredAvailableCapacity - 1)
    defer { fixture.remove() }

    do {
      try await fixture.manager.download()
      Issue.record("Expected insufficient space")
    } catch {
      #expect(
        error as? EnhancedModelManagerError
          == .insufficientSpace(
            required: EnhancedModelManager.requiredAvailableCapacity,
            available: EnhancedModelManager.requiredAvailableCapacity - 1
          )
      )
    }
    #expect(fixture.transport.callCount == 0)
    #expect(fixture.manager.state == .notInstalled)
  }

  @Test @MainActor func progressIsByteWeightedAndMonotonic() async throws {
    let manifest = EnhancedModelManifest(
      schemaVersion: 1,
      modelID: "owner/model",
      revision: "revision",
      totalByteCount: 10,
      files: [
        .init(path: "a.bin", byteCount: 2, sha256: sha256(Data("aa".utf8))),
        .init(path: "b.bin", byteCount: 8, sha256: sha256(Data("bbbbbbbb".utf8))),
      ]
    )
    let fixture = try Fixture(manifest: manifest)
    defer { fixture.remove() }
    fixture.transport.handler = { url, _, progress in
      let name = url.deletingPathExtension().lastPathComponent
      let data = name == "a" ? Data("aa".utf8) : Data("bbbbbbbb".utf8)
      if name == "a" {
        progress(2, 2)
      } else {
        progress(6, 8)
        progress(4, 8)
        progress(8, 8)
      }
      return ModelDownloadResult(
        temporaryURL: try writeTemporary(data),
        resumeData: nil
      )
    }

    let recorder = StateRecorder()
    let cancellable = fixture.manager.$state.sink { recorder.append($0) }
    try await fixture.manager.download()

    let progress = recorder.states.compactMap {
      if case .downloading(let value) = $0 { value } else { nil }
    }
    #expect(progress.contains(0.2))
    #expect(progress.contains(0.8))
    #expect(zip(progress, progress.dropFirst()).allSatisfy(<=))
    #expect(fixture.manager.state == .ready)
    _ = cancellable
  }

  @Test @MainActor func cancellationPersistsOnlyTransportIssuedResumeData() async throws {
    for issued in [true, false] {
      let fixture = try Fixture()
      defer { fixture.remove() }
      let data = validResumeData()
      let remoteURL = try EnhancedModelManager.remoteURL(
        for: testManifest.files[0],
        manifest: testManifest
      )
      if issued {
        fixture.transport.markResumeDataIssued(data, for: remoteURL)
      }
      fixture.transport.handler = { receivedURL, _, _ in
        #expect(receivedURL == remoteURL)
        throw ModelDownloadError.cancelled(resumeData: data)
      }

      await #expect(throws: ModelDownloadError.self) {
        try await fixture.manager.download()
      }

      let resumeFiles = filesBelow(fixture.resumeURL)
      #expect(resumeFiles.count == (issued ? 1 : 0))
      if issued {
        fixture.transport.handler = { receivedURL, resumeData, _ in
          #expect(receivedURL == remoteURL)
          #expect(resumeData == data)
          return ModelDownloadResult(
            temporaryURL: try writeTemporary(testContents),
            resumeData: nil
          )
        }
        try await fixture.manager.download()
        #expect(fixture.manager.state == .ready)
      }
    }
  }

  @Test @MainActor func fabricatedResumePlistCannotBypassPinnedDownloadURL() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let resumeFile = fixture.resumeFileURL
    try FileManager.default.createDirectory(
      at: resumeFile.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try validResumeData().write(to: resumeFile)
    let expectedURL = try EnhancedModelManager.remoteURL(
      for: testManifest.files[0],
      manifest: testManifest
    )
    fixture.transport.handler = { receivedURL, resumeData, _ in
      #expect(receivedURL == expectedURL)
      #expect(resumeData == nil)
      return ModelDownloadResult(
        temporaryURL: try writeTemporary(testContents),
        resumeData: nil
      )
    }

    try await fixture.manager.download()

    #expect(fixture.manager.state == .ready)
  }

  @Test func productionResumeValidatorRejectsEverySyntheticPlist() throws {
    let downloader = URLSessionModelDownloader()
    let pinnedURL = try EnhancedModelManager.remoteURL(
      for: testManifest.files[0],
      manifest: testManifest
    )
    #expect(
      downloader.sessionProducedResumeToken(
        for: validResumeData(),
        remoteURL: pinnedURL
      ) == nil
    )
    #expect(
      downloader.sessionProducedResumeToken(
        for: strictResumeData(
          originalURL: URL(string: "https://evil.example/model")!,
          currentURL: URL(string: "https://evil.example/model")!
        ),
        remoteURL: pinnedURL
      ) == nil
    )
    #expect(
      downloader.sessionProducedResumeToken(
        for: strictResumeData(
          originalURL: pinnedURL,
          currentURL: pinnedURL,
          downloadURL: URL(string: "https://evil.example/model")!
        ),
        remoteURL: pinnedURL
      ) == nil
    )
    #expect(
      downloader.sessionProducedResumeToken(
        for: strictResumeData(originalURL: pinnedURL, currentURL: pinnedURL),
        remoteURL: pinnedURL
      ) == nil
    )
  }

  @Test @MainActor func authenticatedResumeDataSurvivesANewTransport() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let data = validResumeData()
    let remoteURL = try EnhancedModelManager.remoteURL(
      for: testManifest.files[0],
      manifest: testManifest
    )
    fixture.transport.markResumeDataIssued(data, for: remoteURL)
    fixture.transport.handler = { _, _, _ in
      throw ModelDownloadError.cancelled(resumeData: data)
    }
    await #expect(throws: ModelDownloadError.self) {
      try await fixture.manager.download()
    }

    let restartedTransport = TestTransport()
    restartedTransport.handler = { receivedURL, resumeData, _ in
      #expect(receivedURL == remoteURL)
      #expect(resumeData == data)
      return ModelDownloadResult(
        temporaryURL: try writeTemporary(testContents),
        resumeData: nil
      )
    }
    let restartedManager = EnhancedModelManager(
      modelRootURL: fixture.root,
      manifest: testManifest,
      capacityProvider: { .max },
      architectureProvider: { true },
      transport: restartedTransport,
      resumeAuthenticationKeyProvider: { testResumeAuthenticationKey }
    )

    try await restartedManager.download()

    #expect(restartedManager.state == .ready)
  }

  @Test @MainActor func tamperedAuthenticatedResumeDataFailsClosed() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let data = validResumeData()
    let remoteURL = try EnhancedModelManager.remoteURL(
      for: testManifest.files[0],
      manifest: testManifest
    )
    fixture.transport.markResumeDataIssued(data, for: remoteURL)
    fixture.transport.handler = { _, _, _ in
      throw ModelDownloadError.cancelled(resumeData: data)
    }
    await #expect(throws: ModelDownloadError.self) {
      try await fixture.manager.download()
    }
    var envelope = try #require(
      JSONSerialization.jsonObject(
        with: Data(contentsOf: fixture.resumeFileURL)
      ) as? [String: Any]
    )
    envelope["authenticationTag"] = Data(repeating: 0, count: 32).base64EncodedString()
    try JSONSerialization.data(withJSONObject: envelope).write(
      to: fixture.resumeFileURL,
      options: .atomic
    )

    let restartedTransport = TestTransport()
    restartedTransport.handler = { receivedURL, resumeData, _ in
      #expect(receivedURL == remoteURL)
      #expect(resumeData == nil)
      return ModelDownloadResult(
        temporaryURL: try writeTemporary(testContents),
        resumeData: nil
      )
    }
    let restartedManager = EnhancedModelManager(
      modelRootURL: fixture.root,
      manifest: testManifest,
      capacityProvider: { .max },
      architectureProvider: { true },
      transport: restartedTransport,
      resumeAuthenticationKeyProvider: { testResumeAuthenticationKey }
    )

    try await restartedManager.download()

    #expect(restartedManager.state == .ready)
  }

  @Test func cancellationBeforeTaskRegistrationPreventsTheTaskFromStarting() {
    let handshake = DownloadStartHandshake()
    let session = URLSession(configuration: .ephemeral)
    let task = session.downloadTask(
      with: URL(string: "https://huggingface.co/never-started")!
    )
    defer { session.invalidateAndCancel() }

    #expect(handshake.requestCancellation() == nil)
    #expect(handshake.installAndResume(task) == false)
    #expect(task.state == .suspended)
  }

  @Test @MainActor func checksumFailureClearsStagingAndResume() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try FileManager.default.createDirectory(
      at: fixture.resumeURL,
      withIntermediateDirectories: true
    )
    try validResumeData().write(to: fixture.resumeURL.appendingPathComponent("old"))
    fixture.transport.handler = { _, _, _ in
      ModelDownloadResult(
        temporaryURL: try writeTemporary(Data("wrong".utf8)),
        resumeData: nil
      )
    }

    await #expect(throws: EnhancedModelManagerError.self) {
      try await fixture.manager.download()
    }

    #expect(filesBelow(fixture.stagingURL).isEmpty)
    #expect(filesBelow(fixture.resumeURL).isEmpty)
    guard case .repairRequired = fixture.manager.state else {
      Issue.record("Expected repairRequired")
      return
    }
  }

  @Test @MainActor func verifiedStagingIsRenamedIntoInstalledRevision() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    fixture.transport.handler = { _, _, _ in
      ModelDownloadResult(
        temporaryURL: try writeTemporary(testContents),
        resumeData: nil
      )
    }

    try await fixture.manager.download()

    let installedFile = try #require(fixture.manager.verifiedRepositoryURL)
      .appendingPathComponent(testManifest.files[0].path)
    #expect(fixture.manager.verifiedRepositoryURL == fixture.repositoryURL)
    #expect(FileManager.default.fileExists(atPath: installedFile.path))
    #expect(filesBelow(fixture.stagingURL).isEmpty)
    #expect(fixture.manager.state == .ready)
  }

  @Test @MainActor func deleteRemovesOnlyOwnedModelTrees() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    for url in [
      fixture.installedURL, fixture.stagingURL, fixture.resumeURL, fixture.derivedURL,
    ] {
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
      try Data().write(to: url.appendingPathComponent("owned"))
    }
    let sibling = fixture.root.deletingLastPathComponent().appendingPathComponent("notes.json")
    try Data("keep".utf8).write(to: sibling)

    try await fixture.manager.deleteModel()

    #expect(fixture.manager.state == .notInstalled)
    #expect([fixture.installedURL, fixture.stagingURL, fixture.resumeURL, fixture.derivedURL]
      .allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    #expect(FileManager.default.fileExists(atPath: sibling.path))
  }

  @Test @MainActor func lifecycleOperationsCannotOverlap() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let control = DownloadControl()
    fixture.transport.handler = { _, _, _ in
      try await control.download()
    }
    let download = Task { @MainActor in
      try await fixture.manager.download()
    }
    await control.waitUntilStarted()

    await #expect(throws: EnhancedModelManagerError.operationInProgress) {
      try await fixture.manager.deleteModel()
    }

    control.succeed(with: testContents)
    try await download.value
    #expect(fixture.manager.state == .ready)
  }

  @Test @MainActor func staleRefreshCannotOverwriteANewerDelete() async throws {
    let assessment = AssessmentControl()
    let fixture = try Fixture(assessmentDidComplete: {
      assessment.didComplete()
    })
    defer { fixture.remove() }
    try fixture.install()
    let refresh = Task { @MainActor in
      await fixture.manager.refreshState()
    }
    await assessment.waitUntilComplete()

    try await fixture.manager.deleteModel()
    assessment.release()
    await refresh.value

    #expect(fixture.manager.state == .notInstalled)
    #expect(fixture.manager.verifiedRepositoryURL == nil)
  }

  @Test @MainActor func modelRootIsExcludedFromBackup() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }

    await fixture.manager.refreshState()

    let values = try fixture.root.resourceValues(forKeys: [.isExcludedFromBackupKey])
    #expect(values.isExcludedFromBackup == true)
  }

  @Test @MainActor func validOlderInstallIsUpdateAvailableWithoutMovingBytes() async throws {
    let current = EnhancedModelManifest(
      schemaVersion: 1,
      modelID: testManifest.modelID,
      revision: "new-revision",
      totalByteCount: testManifest.totalByteCount,
      files: testManifest.files
    )
    let fixture = try Fixture(
      manifest: current,
      trustedManifests: [testManifest, current]
    )
    defer { fixture.remove() }
    try fixture.install(manifest: testManifest)
    let oldData = try Data(contentsOf: fixture.fileURL(for: testManifest))

    await fixture.manager.refreshState()

    #expect(fixture.manager.state == .updateAvailable)
    #expect(fixture.manager.verifiedRepositoryURL == fixture.repositoryURL(for: testManifest))
    #expect(
      fixture.manager.verifiedLoadState
        == .ready(repositoryURL: fixture.repositoryURL(for: testManifest))
    )
    #expect(try Data(contentsOf: fixture.fileURL(for: testManifest)) == oldData)
    #expect(!FileManager.default.fileExists(atPath: fixture.stagingURL.path))
    #expect(fixture.transport.callCount == 0)
  }

  @Test @MainActor func failedUpdateKeepsPriorVerifiedRevisionReadyForUse() async throws {
    let current = EnhancedModelManifest(
      schemaVersion: 1,
      modelID: testManifest.modelID,
      revision: "new-revision",
      totalByteCount: testManifest.totalByteCount,
      files: testManifest.files
    )
    let fixture = try Fixture(
      manifest: current,
      trustedManifests: [testManifest, current]
    )
    defer { fixture.remove() }
    try fixture.install(manifest: testManifest)
    await fixture.manager.refreshState()
    let oldRepository = fixture.repositoryURL(for: testManifest)
    let control = DownloadControl()
    fixture.transport.handler = { _, _, _ in
      try await control.download()
    }
    let update = Task { @MainActor in
      try await fixture.manager.update()
    }
    await control.waitUntilStarted()

    #expect(fixture.manager.verifiedRepositoryURL == oldRepository)
    control.fail(with: TestError.downloadFailed)
    await #expect(throws: TestError.downloadFailed) {
      try await update.value
    }

    #expect(fixture.manager.state == .updateAvailable)
    #expect(fixture.manager.verifiedRepositoryURL == oldRepository)
    #expect(try Data(contentsOf: fixture.fileURL(for: testManifest)) == testContents)
  }

  @Test @MainActor func cleanupFailureAfterMoveAdoptsTheNewVerifiedRevision() async throws {
    let current = EnhancedModelManifest(
      schemaVersion: 1,
      modelID: testManifest.modelID,
      revision: "new-revision",
      totalByteCount: testManifest.totalByteCount,
      files: testManifest.files
    )
    let fixture = try Fixture(
      manifest: current,
      trustedManifests: [testManifest, current]
    )
    defer { fixture.remove() }
    try fixture.install(manifest: testManifest)
    let outside = canonicalTemporaryDirectory()
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    let blockedCleanup = fixture.installedURL.appendingPathComponent("zzzz-blocked")
    try FileManager.default.createSymbolicLink(
      at: blockedCleanup,
      withDestinationURL: outside
    )
    defer { try? FileManager.default.removeItem(at: outside) }
    await fixture.manager.refreshState()
    fixture.transport.handler = { _, _, _ in
      ModelDownloadResult(
        temporaryURL: try writeTemporary(testContents),
        resumeData: nil
      )
    }

    do {
      try await fixture.manager.update()
      Issue.record("Expected cleanup failure")
    } catch {
      // The committed model remains usable even though old-revision cleanup failed.
    }

    let newRepository = fixture.repositoryURL(for: current)
    #expect(fixture.manager.state == .ready)
    #expect(fixture.manager.verifiedRepositoryURL == newRepository)
    #expect(
      fixture.manager.verifiedLoadState == .ready(repositoryURL: newRepository)
    )
    #expect(try Data(contentsOf: fixture.fileURL(for: current)) == testContents)
    #expect(
      !FileManager.default.fileExists(
        atPath: fixture.installedURL
          .appendingPathComponent(testManifest.revision)
          .path
      )
    )
  }

  @Test @MainActor func installedManifestCannotAuthorizeAnUnshippedRevision() async throws {
    let current = EnhancedModelManifest(
      schemaVersion: 1,
      modelID: testManifest.modelID,
      revision: "new-revision",
      totalByteCount: testManifest.totalByteCount,
      files: testManifest.files
    )
    let fixture = try Fixture(manifest: current, trustedManifests: [current])
    defer { fixture.remove() }
    try fixture.install(manifest: testManifest)

    await fixture.manager.refreshState()

    #expect(fixture.manager.state == .notInstalled)
    #expect(fixture.manager.verifiedRepositoryURL == nil)
  }

  @Test @MainActor func symlinkedModelRootsAndDestructiveTargetsAreRejected() async throws {
    let base = canonicalTemporaryDirectory()
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let outside = base.appendingPathComponent("outside", isDirectory: true)
    let linkedGrandparent = base.appendingPathComponent("linked", isDirectory: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      at: linkedGrandparent,
      withDestinationURL: outside
    )
    let manager = EnhancedModelManager(
      modelRootURL: linkedGrandparent
        .appendingPathComponent("nested", isDirectory: true)
        .appendingPathComponent("DictationModels", isDirectory: true),
      manifest: testManifest,
      capacityProvider: { .max },
      architectureProvider: { true },
      transport: TestTransport()
    )
    defer { try? FileManager.default.removeItem(at: base) }

    await manager.refreshState()

    guard case .repairRequired = manager.state else {
      Issue.record("Expected a symlinked ancestor to be rejected")
      return
    }
    #expect(!FileManager.default.fileExists(
      atPath: outside
        .appendingPathComponent("nested")
        .appendingPathComponent("DictationModels").path
    ))

    let fixture = try Fixture()
    defer { fixture.remove() }
    let sentinel = outside.appendingPathComponent("sentinel")
    try testContents.write(to: sentinel)
    try FileManager.default.createDirectory(
      at: fixture.root,
      withIntermediateDirectories: true
    )
    try FileManager.default.createSymbolicLink(
      at: fixture.installedURL,
      withDestinationURL: outside
    )

    await #expect(throws: EnhancedModelManagerError.self) {
      try await fixture.manager.deleteModel()
    }
    #expect(try Data(contentsOf: sentinel) == testContents)
  }

  @Test func artifactURLUsesEncodedAllowlistedPathAndPinnedRevision() throws {
    let file = EnhancedModelFile(
      path: "folder/a file#1.bin",
      byteCount: 0,
      sha256: sha256(Data())
    )
    let manifest = EnhancedModelManifest(
      schemaVersion: 1,
      modelID: testManifest.modelID,
      revision: "immutable-revision",
      totalByteCount: 0,
      files: [file]
    )

    let url = try EnhancedModelManager.remoteURL(for: file, manifest: manifest)

    #expect(url.host == "huggingface.co")
    #expect(url.path.contains("/resolve/immutable-revision/folder/a file#1.bin"))
    #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
      == [URLQueryItem(name: "download", value: "true")])
  }

  @Test(arguments: ["../escape", "/absolute", "safe/../../escape", "", "safe//file"])
  func unsafeManifestPathIsRejected(path: String) {
    let file = EnhancedModelFile(path: path, byteCount: 0, sha256: sha256(Data()))

    #expect(throws: EnhancedModelManagerError.self) {
      try EnhancedModelManager.remoteURL(for: file, manifest: testManifest)
    }
  }

  @Test @MainActor func unsafeRevisionCannotReachOutsideModelRoot() async throws {
    let manifest = EnhancedModelManifest(
      schemaVersion: 1,
      modelID: "owner/model",
      revision: "../../outside",
      totalByteCount: Int64(testContents.count),
      files: [
        .init(
          path: "Encoder.mlmodelc/model.bin",
          byteCount: Int64(testContents.count),
          sha256: sha256(testContents)
        )
      ]
    )
    let fixture = try Fixture(manifest: manifest)
    defer { fixture.remove() }
    let outside = fixture.root.deletingLastPathComponent()
      .appendingPathComponent("outside/model/Encoder.mlmodelc", isDirectory: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    let sentinel = outside.appendingPathComponent("model.bin")
    try testContents.write(to: sentinel)

    await #expect(throws: EnhancedModelManagerError.invalidManifest) {
      try await fixture.manager.download()
    }

    #expect(try Data(contentsOf: sentinel) == testContents)
    #expect(fixture.transport.callCount == 0)
  }

  @Test(arguments: [
    ("huggingface.co", true),
    ("cdn.huggingface.co", true),
    ("transfer.xethub.hf.co", true),
    ("evil-huggingface.co", false),
    ("huggingface.co.evil.example", false),
    ("xethub.hf.co.evil.example", false),
  ])
  func redirectHostAllowlistUsesDNSLabels(host: String, allowed: Bool) {
    #expect(URLSessionModelDownloader.isAllowedRedirectHost(host) == allowed)
  }

  @Test(arguments: [
    ("https://huggingface.co/file", true),
    ("https://cdn.huggingface.co/file", true),
    ("https://transfer.xethub.hf.co/file", true),
    ("http://huggingface.co/file", false),
    ("https://evil-huggingface.co/file", false),
  ])
  func redirectsRequireHTTPSAndAnAllowedHost(value: String, allowed: Bool) {
    #expect(
      URLSessionModelDownloader.isAllowedRedirectURL(URL(string: value)!) == allowed
    )
  }
}

enum Corruption: CaseIterable {
  case missing
  case extra
  case extraDirectory
  case wrongSize
  case wrongHash
}

private let testContents = Data("model".utf8)
private let testResumeAuthenticationKey = SymmetricKey(
  data: Data(repeating: 0xA5, count: 32)
)
private let testManifest = EnhancedModelManifest(
  schemaVersion: 1,
  modelID: "owner/parakeet-tdt-0.6b-v2-coreml",
  revision: "revision",
  totalByteCount: Int64(testContents.count),
  files: [
    EnhancedModelFile(
      path: "Encoder.mlmodelc/model.bin",
      byteCount: Int64(testContents.count),
      sha256: sha256(testContents)
    )
  ]
)

@MainActor
private final class Fixture {
  let root: URL
  let manifest: EnhancedModelManifest
  let transport: TestTransport
  let manager: EnhancedModelManager

  init(
    manifest: EnhancedModelManifest = testManifest,
    capacity: Int64 = .max,
    trustedManifests: [EnhancedModelManifest]? = nil,
    assessmentDidComplete: @escaping @Sendable () -> Void = {},
    resumeAuthenticationKey: SymmetricKey = testResumeAuthenticationKey
  ) throws {
    root = temporaryRoot()
    self.manifest = manifest
    transport = TestTransport()
    manager = EnhancedModelManager(
      modelRootURL: root,
      manifest: manifest,
      trustedManifests: trustedManifests,
      capacityProvider: { capacity },
      architectureProvider: { true },
      clock: { Date() },
      transport: transport,
      assessmentDidComplete: assessmentDidComplete,
      resumeAuthenticationKeyProvider: { resumeAuthenticationKey }
    )
  }

  var installedURL: URL {
    root.appendingPathComponent("installed", isDirectory: true)
  }

  var stagingURL: URL {
    root.appendingPathComponent("staging", isDirectory: true)
  }

  var resumeURL: URL {
    root.appendingPathComponent("resume", isDirectory: true)
  }

  var derivedURL: URL {
    root.appendingPathComponent("derived", isDirectory: true)
  }

  var resumeFileURL: URL {
    resumeURL
      .appendingPathComponent(manifest.revision, isDirectory: true)
      .appendingPathComponent(manifest.modelID.split(separator: "/").last.map(String.init)!)
      .appendingPathComponent(manifest.files[0].path + ".resumeData")
  }

  var repositoryURL: URL {
    self.repositoryURL(for: manifest)
  }

  var fileURL: URL {
    self.fileURL(for: manifest)
  }

  func repositoryURL(for manifest: EnhancedModelManifest) -> URL {
    installedURL
      .appendingPathComponent(manifest.revision, isDirectory: true)
      .appendingPathComponent(manifest.modelID.split(separator: "/").last.map(String.init)!)
  }

  func fileURL(for manifest: EnhancedModelManifest) -> URL {
    self.repositoryURL(for: manifest)
      .appendingPathComponent(manifest.files[0].path)
  }

  func install(
    manifest: EnhancedModelManifest? = nil,
    corruption: Corruption? = nil
  ) throws {
    let manifest = manifest ?? self.manifest
    let repository = self.repositoryURL(for: manifest)
    try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
    if corruption != .missing {
      let data: Data
      switch corruption {
      case .wrongSize:
        data = Data("too long".utf8)
      case .wrongHash:
        data = Data("other".utf8)
      default:
        data = testContents
      }
      let file = self.fileURL(for: manifest)
      try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try data.write(to: file)
    }
    if corruption == .extra {
      try Data().write(to: repository.appendingPathComponent(".extra.bin"))
    }
    if corruption == .extraDirectory {
      try FileManager.default.createDirectory(
        at: repository.appendingPathComponent("unexpected", isDirectory: true),
        withIntermediateDirectories: true
      )
    }
    let encoded = try JSONEncoder().encode(manifest)
    try encoded.write(
      to: repository.deletingLastPathComponent()
        .appendingPathComponent("manifest.json")
    )
  }

  func remove() {
    try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
  }
}

private final class TestTransport: ModelDownloading, @unchecked Sendable {
  typealias Handler = @Sendable (
    URL,
    Data?,
    @escaping @Sendable (Int64, Int64) -> Void
  ) async throws -> ModelDownloadResult

  private let lock = NSLock()
  private var calls = 0
  private var issuedResumeData: [Data: URL] = [:]
  var handler: Handler = { _, _, _ in
    throw TestError.noHandler
  }

  var callCount: Int {
    lock.withLock { calls }
  }

  func markResumeDataIssued(_ data: Data, for remoteURL: URL) {
    lock.withLock { issuedResumeData[data] = remoteURL }
  }

  func sessionProducedResumeToken(
    for data: Data,
    remoteURL: URL
  ) -> ModelResumeToken? {
    lock.withLock {
      issuedResumeData[data] == remoteURL
        ? ModelResumeToken(issuedData: data)
        : nil
    }
  }

  func download(
    from remoteURL: URL,
    resumeToken: ModelResumeToken?,
    progress: @escaping @Sendable (Int64, Int64) -> Void
  ) async throws -> ModelDownloadResult {
    lock.withLock { calls += 1 }
    return try await handler(remoteURL, resumeToken?.data, progress)
  }
}

private enum TestError: Error {
  case noHandler
  case downloadFailed
}

private final class DownloadControl: @unchecked Sendable {
  private let lock = NSLock()
  private var startWaiters: [CheckedContinuation<Void, Never>] = []
  private var started = false
  private var completion: CheckedContinuation<ModelDownloadResult, Error>?

  func download() async throws -> ModelDownloadResult {
    try await withCheckedThrowingContinuation { continuation in
      let waiters = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
        completion = continuation
        started = true
        defer { startWaiters.removeAll() }
        return startWaiters
      }
      waiters.forEach { $0.resume() }
    }
  }

  func waitUntilStarted() async {
    await withCheckedContinuation { continuation in
      let resumeNow = lock.withLock {
        if started { return true }
        startWaiters.append(continuation)
        return false
      }
      if resumeNow { continuation.resume() }
    }
  }

  func succeed(with data: Data) {
    finish(.success(ModelDownloadResult(
      temporaryURL: try! writeTemporary(data),
      resumeData: nil
    )))
  }

  func fail(with error: Error) {
    finish(.failure(error))
  }

  private func finish(_ result: Result<ModelDownloadResult, Error>) {
    let continuation = lock.withLock {
      defer { completion = nil }
      return completion
    }
    continuation?.resume(with: result)
  }
}

private final class AssessmentControl: @unchecked Sendable {
  private let lock = NSLock()
  private let proceed = DispatchSemaphore(value: 0)
  private var isComplete = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func didComplete() {
    let pending = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
      isComplete = true
      defer { waiters.removeAll() }
      return waiters
    }
    pending.forEach { $0.resume() }
    proceed.wait()
  }

  func waitUntilComplete() async {
    await withCheckedContinuation { continuation in
      let resumeNow = lock.withLock {
        if isComplete { return true }
        waiters.append(continuation)
        return false
      }
      if resumeNow { continuation.resume() }
    }
  }

  func release() {
    proceed.signal()
  }
}

private final class LockedCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0

  var value: Int {
    lock.withLock { count }
  }

  func increment() {
    lock.withLock { count += 1 }
  }
}

private final class StateRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var recorded: [EnhancedModelState] = []

  var states: [EnhancedModelState] {
    lock.withLock { recorded }
  }

  func append(_ state: EnhancedModelState) {
    lock.withLock { recorded.append(state) }
  }
}

private func temporaryRoot() -> URL {
  canonicalTemporaryDirectory()
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
    .appendingPathComponent("DictationModels", isDirectory: true)
}

private func writeTemporary(_ data: Data) throws -> URL {
  let url = canonicalTemporaryDirectory()
    .appendingPathComponent(UUID().uuidString)
  try data.write(to: url)
  return url
}

private func canonicalTemporaryDirectory() -> URL {
  let temporary = FileManager.default.temporaryDirectory.standardizedFileURL
  guard temporary.path == "/var" || temporary.path.hasPrefix("/var/") else {
    return temporary
  }
  return URL(fileURLWithPath: "/private" + temporary.path, isDirectory: true)
}

private func filesBelow(_ root: URL) -> [URL] {
  guard
    let enumerator = FileManager.default.enumerator(
      at: root,
      includingPropertiesForKeys: [.isRegularFileKey]
    )
  else { return [] }
  return enumerator.compactMap {
    guard
      let url = $0 as? URL,
      (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    else { return nil }
    return url
  }
}

private func validResumeData() -> Data {
  try! PropertyListSerialization.data(
    fromPropertyList: ["NSURLSessionDownloadURL": "https://huggingface.co/file"],
    format: .binary,
    options: 0
  )
}

private func strictResumeData(
  originalURL: URL,
  currentURL: URL,
  downloadURL: URL? = nil
) -> Data {
  let original = try! NSKeyedArchiver.archivedData(
    withRootObject: NSURLRequest(url: originalURL),
    requiringSecureCoding: true
  )
  let current = try! NSKeyedArchiver.archivedData(
    withRootObject: NSURLRequest(url: currentURL),
    requiringSecureCoding: true
  )
  var propertyList: [String: Any] = [
    "NSURLSessionResumeInfoVersion": 2,
    "NSURLSessionResumeBytesReceived": 1,
    "NSURLSessionResumeInfoTempFileName": "CFNetworkDownload_test.tmp",
    "NSURLSessionResumeOriginalRequest": original,
    "NSURLSessionResumeCurrentRequest": current,
  ]
  propertyList["NSURLSessionDownloadURL"] = downloadURL?.absoluteString
  return try! PropertyListSerialization.data(
    fromPropertyList: propertyList,
    format: .binary,
    options: 0
  )
}

private func sha256(_ data: Data) -> String {
  SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
