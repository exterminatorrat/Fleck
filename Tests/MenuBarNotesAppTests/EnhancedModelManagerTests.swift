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

  @Test @MainActor func cancellationPersistsOnlyURLSessionResumeData() async throws {
    for data in [validResumeData(), Data("not resume data".utf8)] {
      let fixture = try Fixture()
      defer { fixture.remove() }
      fixture.transport.handler = { _, _, _ in
        throw ModelDownloadError.cancelled(resumeData: data)
      }

      await #expect(throws: ModelDownloadError.self) {
        try await fixture.manager.download()
      }

      let resumeFiles = filesBelow(fixture.resumeURL)
      #expect(resumeFiles.count == (data == validResumeData() ? 1 : 0))
    }
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
    let fixture = try Fixture(manifest: current)
    defer { fixture.remove() }
    try fixture.install(manifest: testManifest)
    let oldData = try Data(contentsOf: fixture.fileURL(for: testManifest))

    await fixture.manager.refreshState()

    #expect(fixture.manager.state == .updateAvailable)
    #expect(try Data(contentsOf: fixture.fileURL(for: testManifest)) == oldData)
    #expect(!FileManager.default.fileExists(atPath: fixture.stagingURL.path))
    #expect(fixture.transport.callCount == 0)
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
}

enum Corruption: CaseIterable {
  case missing
  case extra
  case wrongSize
  case wrongHash
}

private let testContents = Data("model".utf8)
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
    capacity: Int64 = .max
  ) throws {
    root = temporaryRoot()
    self.manifest = manifest
    transport = TestTransport()
    manager = EnhancedModelManager(
      modelRootURL: root,
      manifest: manifest,
      capacityProvider: { capacity },
      architectureProvider: { true },
      clock: { Date() },
      transport: transport
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
  var handler: Handler = { _, _, _ in
    throw TestError.noHandler
  }

  var callCount: Int {
    lock.withLock { calls }
  }

  func download(
    from remoteURL: URL,
    resumeData: Data?,
    progress: @escaping @Sendable (Int64, Int64) -> Void
  ) async throws -> ModelDownloadResult {
    lock.withLock { calls += 1 }
    return try await handler(remoteURL, resumeData, progress)
  }
}

private enum TestError: Error {
  case noHandler
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
  FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
    .appendingPathComponent("DictationModels", isDirectory: true)
}

private func writeTemporary(_ data: Data) throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString)
  try data.write(to: url)
  return url
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

private func sha256(_ data: Data) -> String {
  SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
