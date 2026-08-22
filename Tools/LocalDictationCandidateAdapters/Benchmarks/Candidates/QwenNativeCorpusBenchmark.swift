import CryptoKit
import Darwin
import Foundation

private let maximumJSONLineBytes = 1_048_576
private let maximumCapturedOutputBytes = 16 * 1_024 * 1_024
private let helperRequestTimeout: TimeInterval = 180
private let cancellationDeadline: TimeInterval = 5
private let cooperativeFinishDeadline: TimeInterval = 5

private struct BenchmarkFailure: Error, CustomStringConvertible {
  let message: String

  var description: String { message }
}

private struct ArchiveMetadata: Decodable, Equatable {
  let id: String
  let fileName: String
  let revision: String
  let sha256: String
  let sizeBytes: Int64
}

private struct ModelMetadata: Decodable {
  let id: String
  let ownerRevision: String
  let convertedRevision: String
  let license: String
  let ownerModelFile: String
  let ownerModelFileSHA256: String
  let archive: ArchiveMetadata
}

private struct RuntimeMetadata: Decodable {
  let id: String
  let revision: String
  let sourceCommit: String
  let license: String
  let architecture: String
  let provider: String
  let threadCount: Int
  let cAPI: String
  let archive: ArchiveMetadata
}

private struct HelperBuildReceipt: Decodable {
  let id: String
  let executableFileName: String
  let sha256: String
  let sizeBytes: Int64
  let modelID: String
  let modelRevision: String
  let runtimeID: String
  let runtimeRevision: String
  let status: String
}

private struct InventoryMetadata: Decodable {
  let path: String
  let sha256: String
  let sizeBytes: Int64
  let candidate: String
  let status: String
  let releaseAdmitted: Bool
}

private struct CapabilityMetadata: Decodable {
  let resultSemantics: String
  let supportsTrueStreaming: Bool
  let emitsRollingWindowPartials: Bool
  let supportsCancellation: Bool
  let supportsCooperativeDecodeCancellation: Bool
  let supportsContext: Bool
  let supportsHotwords: Bool
}

private struct TruthFlagMetadata: Decodable {
  let automatedCandidatePass: Bool
  let productionIntegrated: Bool
  let packagedAppVerified: Bool
  let releaseAdmitted: Bool
}

private struct CandidateMetadata: Decodable {
  let schemaVersion: Int
  let candidateID: String
  let model: ModelMetadata
  let runtime: RuntimeMetadata
  let helperBuild: HelperBuildReceipt
  let inventory: InventoryMetadata
  let capabilities: CapabilityMetadata
  let truthFlags: TruthFlagMetadata
}

private let pinnedModelOwnerRevision = "5eb144179a02acc5e5ba31e748d22b0cf3e303b0"
private let pinnedModelOwnerFileSHA256 = "79d6cbd4c98c7bbffe9db2edac07f56cd6637d0d5944b27f6c2b8353840323ea"
private let pinnedModelRevision = "sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25"
private let pinnedRuntimeRevision = "v1.13.4"
private let pinnedRuntimeSourceCommit = "142807252687d81b40d6315f23470a1512a00de3"
private let pinnedModelArchiveSHA256 = "393f8a14e2f5fb96746aaab342997a40641001fbd5bf9592a080a8329178ee96"
private let pinnedModelArchiveSizeBytes: Int64 = 878_702_423
private let pinnedRuntimeArchiveSHA256 = "ef7daa86a1e5f5dcb0ccf53e4e475c3ae24414652c9ae9c3912a82140c86fb1a"
private let pinnedRuntimeArchiveSizeBytes: Int64 = 17_716_081
private let pinnedHelperBuildSHA256 = "3ce3332a265e72acee78e6bd3975f96262b7f3c54bce3dacccd2418659db2eab"
private let pinnedHelperBuildSizeBytes: Int64 = 333_920
private let pinnedInventorySHA256 = "27fa7f977fbfaeedc02c3a4dadef42411883349af6750f417700b9967a37a5d1"
private let pinnedInventorySizeBytes: Int64 = 7_680

private struct InventoryArchive: Decodable, Equatable, Hashable {
  let fileName: String
  let sha256: String
  let sizeBytes: Int64
}

private struct InventoryFile: Decodable {
  let path: String
  let sha256: String
  let sizeBytes: Int64
}

private struct InventorySymlink: Decodable {
  let path: String
  let target: String
}

private struct InstalledArtifactInventory: Decodable {
  let archives: [InventoryArchive]
  let candidate: String
  let installedFiles: [InventoryFile]
  let installedSymlinks: [InventorySymlink]
  let releaseAdmitted: Bool
  let schemaVersion: Int
  let status: String
  let totalInstalledBytes: Int64
}

private struct SourceFileMetadata: Decodable {
  let path: String
  let url: String
  let sha256: String
  let byteCount: Int64
}

private struct CorpusSource: Decodable {
  let dataset: String
  let repository: String
  let revision: String
  let license: String
  let licenseURL: String
  let licenseMetadataURL: String
  let files: [String: SourceFileMetadata]
}

private struct ProtectedExpectation: Codable, Equatable {
  let kind: String
  let text: String
  let comparison: String
}

private struct CodeSwitchSpan: Decodable {
  let language: String
  let sourceCaseID: String
  let startSample: Int64
  let endSample: Int64
  let reference: String
}

private struct CorpusCase: Decodable {
  let id: String
  let sourceFile: String
  let language: String
  let sourceClass: String
  let audioSHA256: String
  let audioDurationMilliseconds: Int
  let audioBytes: Int64
  let reference: String
  let protectedExpectations: [ProtectedExpectation]
  let naturalCodeSwitch: Bool
  let codeSwitchSpans: [CodeSwitchSpan]?
}

private struct CorpusManifest: Decodable {
  let schemaVersion: Int
  let manifestID: String
  let immutable: Bool
  let source: CorpusSource
  let cases: [CorpusCase]
}

private struct AudioShape {
  let sampleRate: Int
  let channels: Int
  let sampleCount: Int64
}

private struct BenchmarkCase {
  let id: String
  let sourceFile: String
  let language: String
  let sourceClass: String
  let audioURL: URL
  let audioSHA256: String
  let audioDurationMilliseconds: Int
  let audioBytes: Int64
  let reference: String
  let protectedExpectations: [ProtectedExpectation]
  let codeSwitchSpans: [CodeSwitchSpan]
}

private struct ManifestReceipt {
  let path: String
  let sha256: String
  let byteCount: Int64
  let manifest: CorpusManifest
}

private struct PreparedReceipt {
  let inventoryPath: String
  let inventoryRelativePath: String
  let inventorySHA256: String
  let inventoryByteCount: Int64
  let inventory: InstalledArtifactInventory
  let verifiedInventory: ArtifactInventory
}

private struct BenchmarkOptions {
  let preparedRoot: String
  let helper: String
  let publicManifest: String
  let publicRoot: String
  let compositeManifest: String
  let compositeRoot: String
  let outputRoot: String
  let metadata: String
  let repoRoot: String
  let contractTest: Bool
  let selfTest: Bool

  init(arguments: [String]) throws {
    var values: [String: String] = [:]
    var selfTest = false
    var contractTest = false
    var index = 1
    let valueFlags: Set<String> = [
      "--prepared-root", "--helper", "--public-human-manifest", "--public-human-root",
      "--composite-manifest", "--composite-root", "--output-root", "--metadata", "--repo-root",
    ]

    while index < arguments.count {
      let flag = arguments[index]
      if flag == "--self-test" {
        guard !selfTest else { throw BenchmarkFailure(message: "duplicate-argument:--self-test") }
        selfTest = true
        index += 1
        continue
      }
      if flag == "--contract-test" {
        guard !contractTest else { throw BenchmarkFailure(message: "duplicate-argument:--contract-test") }
        contractTest = true
        index += 1
        continue
      }
      guard valueFlags.contains(flag), index + 1 < arguments.count else {
        throw BenchmarkFailure(message: "unsupported-or-missing-argument:\(flag)")
      }
      guard values[flag] == nil, !arguments[index + 1].isEmpty else {
        throw BenchmarkFailure(message: "duplicate-or-empty-argument:\(flag)")
      }
      values[flag] = arguments[index + 1]
      index += 2
    }

    if selfTest {
      guard values.isEmpty && !contractTest else {
        throw BenchmarkFailure(message: "self-test-does-not-accept-inputs")
      }
      preparedRoot = ""
      helper = ""
      publicManifest = ""
      publicRoot = ""
      compositeManifest = ""
      compositeRoot = ""
      outputRoot = ""
      metadata = ""
      repoRoot = ""
      self.contractTest = false
      self.selfTest = true
      return
    }

    func required(_ flag: String) throws -> String {
      guard let value = values[flag] else {
        throw BenchmarkFailure(message: "missing-argument:\(flag)")
      }
      return value
    }

    preparedRoot = try required("--prepared-root")
    helper = try required("--helper")
    publicManifest = try required("--public-human-manifest")
    publicRoot = try required("--public-human-root")
    compositeManifest = try required("--composite-manifest")
    compositeRoot = try required("--composite-root")
    outputRoot = try required("--output-root")
    metadata = try required("--metadata")
    repoRoot = values["--repo-root"] ?? FileManager.default.currentDirectoryPath
    self.contractTest = contractTest
    self.selfTest = false
  }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
  guard condition() else { throw BenchmarkFailure(message: message) }
}

private func isCanonicalHash(_ value: String) -> Bool {
  value.utf8.count == 64 && value.utf8.allSatisfy { byte in
    (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)
  }
}

private func isSafeRelativePath(_ path: String) -> Bool {
  guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("://") else { return false }
  let components = path.split(separator: "/", omittingEmptySubsequences: false)
  return !components.contains { $0.isEmpty || $0 == "." || $0 == ".." }
}

private func isSafeSymlinkTarget(_ target: String) -> Bool {
  guard !target.isEmpty,
    !target.hasPrefix("/"),
    !target.contains("://"),
    !target.contains("\0"),
    !target.contains("\n"),
    !target.contains("\r")
  else { return false }
  let components = target.split(separator: "/", omittingEmptySubsequences: false)
  return !components.contains { $0.isEmpty }
}

private func isSymbolicLink(_ path: String) -> Bool {
  var info = stat()
  guard lstat(path, &info) == 0 else { return false }
  return (info.st_mode & S_IFMT) == S_IFLNK
}

private func requireCanonicalPath(
  _ rawPath: String,
  field: String,
  allowMissing: Bool
) throws -> URL {
  guard rawPath.first == "/",
    !rawPath.contains("://"),
    !rawPath.contains("\0"),
    !rawPath.contains("\n"),
    !rawPath.contains("\r")
  else {
    throw BenchmarkFailure(message: "\(field)-must-be-absolute-local-path")
  }

  let lexical = URL(fileURLWithPath: rawPath).standardizedFileURL
  guard lexical.path == rawPath else {
    throw BenchmarkFailure(message: "\(field)-must-be-canonical:\(rawPath)->\(lexical.path)")
  }

  var componentPath = "/"
  for component in rawPath.split(separator: "/") {
    componentPath = componentPath == "/"
      ? "/\(component)"
      : componentPath + "/\(component)"
    if isSymbolicLink(componentPath) {
      throw BenchmarkFailure(message: "\(field)-contains-symlink")
    }
  }

  var info = stat()
  let exists = lstat(rawPath, &info) == 0
  if !exists {
    guard allowMissing else {
      throw BenchmarkFailure(message: "\(field)-missing")
    }
    let parent = lexical.deletingLastPathComponent()
    var parentInfo = stat()
    guard lstat(parent.path, &parentInfo) == 0,
      (parentInfo.st_mode & S_IFMT) == S_IFDIR,
      !isSymbolicLink(parent.path)
    else {
      throw BenchmarkFailure(message: "\(field)-parent-must-be-existing-directory")
    }
  } else if (info.st_mode & S_IFMT) == S_IFLNK {
    throw BenchmarkFailure(message: "\(field)-must-not-be-symlink")
  }
  return lexical
}

private func requireDirectory(_ url: URL, field: String) throws {
  var info = stat()
  guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else {
    throw BenchmarkFailure(message: "\(field)-must-be-directory")
  }
}

private func requireRegularFile(_ url: URL, field: String, executable: Bool = false) throws {
  var info = stat()
  guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
    throw BenchmarkFailure(message: "\(field)-must-be-regular-file")
  }
  if executable {
    guard access(url.path, X_OK) == 0 else {
      throw BenchmarkFailure(message: "\(field)-must-be-executable")
    }
  }
}

private func isWithin(_ child: String, root: String) -> Bool {
  child == root || child.hasPrefix(root.hasSuffix("/") ? root : root + "/")
}

private func requireContainedAudio(_ relativePath: String, root: URL, id: String) throws -> URL {
  guard isSafeRelativePath(relativePath) else {
    throw BenchmarkFailure(message: "case-\(id)-unsafe-audio-path")
  }
  let lexical = root.appendingPathComponent(relativePath).standardizedFileURL
  guard isWithin(lexical.path, root: root.path) else {
    throw BenchmarkFailure(message: "case-\(id)-audio-outside-root")
  }
  guard lexical.resolvingSymlinksInPath().standardizedFileURL.path == lexical.path else {
    throw BenchmarkFailure(message: "case-\(id)-audio-symlink")
  }
  try requireRegularFile(lexical, field: "case-(id)-audio")
  return lexical
}

private func sha256File(_ url: URL) throws -> (sha256: String, byteCount: Int64) {
  let handle = try FileHandle(forReadingFrom: url)
  defer { try? handle.close() }
  var hasher = SHA256()
  var byteCount: Int64 = 0
  while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
    let (next, overflow) = byteCount.addingReportingOverflow(Int64(chunk.count))
  guard !overflow else { throw BenchmarkFailure(message: "file-size-overflow:\(url.path)") }
    byteCount = next
    hasher.update(data: chunk)
  }
  let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
  return (digest, byteCount)
}

private func sha256Data(_ data: Data) -> String {
  SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func readJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
  let data = try Data(contentsOf: url, options: .mappedIfSafe)
  do {
    return try JSONDecoder().decode(type, from: data)
  } catch {
    throw BenchmarkFailure(message: "malformed-json:\(url.lastPathComponent)")
  }
}

private func validateMetadata(_ metadata: CandidateMetadata, allowContractFixture: Bool) throws {
  try require(metadata.schemaVersion == 1, "metadata-schema-version")
  try require(metadata.candidateID == "qwen3-asr-0.6b-int8", "metadata-candidate-id")
  try require(metadata.model.id == "Qwen/Qwen3-ASR-0.6B" && !metadata.model.convertedRevision.isEmpty,
              "metadata-model-identity")
  try require(!metadata.model.ownerRevision.isEmpty && isCanonicalHash(metadata.model.ownerModelFileSHA256), "metadata-owner-identity")
  try require(metadata.runtime.id == "sherpa-onnx" && !metadata.runtime.revision.isEmpty,
              "metadata-runtime-identity")
  try require(metadata.runtime.architecture == "arm64", "metadata-architecture")
  try require(metadata.runtime.provider == "cpu" && metadata.runtime.threadCount > 0, "metadata-runtime-settings")
  try require(!metadata.helperBuild.id.isEmpty && !metadata.helperBuild.executableFileName.isEmpty,
              "metadata-helper-build-identity")
  try require(isCanonicalHash(metadata.helperBuild.sha256) && metadata.helperBuild.sizeBytes > 0,
              "metadata-helper-build-digest")
  try require(metadata.helperBuild.modelID == metadata.model.id &&
                metadata.helperBuild.modelRevision == metadata.model.convertedRevision &&
                metadata.helperBuild.runtimeID == metadata.runtime.id &&
                metadata.helperBuild.runtimeRevision == metadata.runtime.revision,
              "metadata-helper-build-pinned-identities")
  try require(!metadata.helperBuild.status.isEmpty, "metadata-helper-build-status")
  try require(metadata.inventory.path == "installed-artifact-inventory.json", "metadata-inventory-path")
  try require(isCanonicalHash(metadata.inventory.sha256) && metadata.inventory.sizeBytes > 0, "metadata-inventory-identity")
  try require(metadata.inventory.candidate == metadata.candidateID, "metadata-inventory-candidate")
  try require(!metadata.inventory.status.isEmpty && !metadata.inventory.releaseAdmitted, "metadata-inventory-status")
  for archive in [metadata.model.archive, metadata.runtime.archive] {
    try require(!archive.id.isEmpty && !archive.fileName.isEmpty && !archive.revision.isEmpty, "metadata-archive-identity")
    try require(isCanonicalHash(archive.sha256) && archive.sizeBytes > 0, "metadata-archive-digest")
  }
  if !allowContractFixture {
    try require(metadata.model.ownerRevision == pinnedModelOwnerRevision, "metadata-owner-revision-pin")
    try require(metadata.model.ownerModelFileSHA256 == pinnedModelOwnerFileSHA256,
                "metadata-owner-file-pin")
    try require(metadata.model.convertedRevision == pinnedModelRevision, "metadata-model-revision-pin")
    try require(metadata.runtime.revision == pinnedRuntimeRevision, "metadata-runtime-revision-pin")
    try require(metadata.runtime.sourceCommit == pinnedRuntimeSourceCommit,
                "metadata-runtime-source-pin")
    try require(metadata.model.archive.sha256 == pinnedModelArchiveSHA256 &&
                  metadata.model.archive.sizeBytes == pinnedModelArchiveSizeBytes,
                "metadata-model-archive-pin")
    try require(metadata.runtime.archive.sha256 == pinnedRuntimeArchiveSHA256 &&
                  metadata.runtime.archive.sizeBytes == pinnedRuntimeArchiveSizeBytes,
                "metadata-runtime-archive-pin")
    try require(metadata.helperBuild.sha256 == pinnedHelperBuildSHA256 &&
                  metadata.helperBuild.sizeBytes == pinnedHelperBuildSizeBytes,
                "metadata-helper-build-pin")
    try require(metadata.inventory.sha256 == pinnedInventorySHA256 &&
                  metadata.inventory.sizeBytes == pinnedInventorySizeBytes,
                "metadata-inventory-pin")
  }
  try require(metadata.capabilities.resultSemantics == "batch-final-only", "metadata-result-semantics")
  try require(!metadata.capabilities.supportsTrueStreaming,
              "metadata-true-streaming-must-remain-false")
  try require(!metadata.capabilities.emitsRollingWindowPartials,
              "metadata-partials-must-remain-false")
  try require(!metadata.capabilities.supportsCancellation,
              "metadata-cancellation-must-remain-false")
  try require(!metadata.capabilities.supportsCooperativeDecodeCancellation,
              "metadata-cooperative-cancellation-must-remain-false")
  try require(!metadata.truthFlags.automatedCandidatePass,
              "metadata-automated-pass-must-remain-false")
  try require(!metadata.truthFlags.productionIntegrated,
              "metadata-production-integration-must-remain-false")
  try require(!metadata.truthFlags.packagedAppVerified,
              "metadata-packaged-app-verification-must-remain-false")
  try require(!metadata.truthFlags.releaseAdmitted,
              "metadata-release-admission-must-remain-false")
}

private func verifyPreparedInventory(
  root: URL,
  metadata: CandidateMetadata
) throws -> PreparedReceipt {
  try requireDirectory(root, field: "prepared-root")
  let inventoryURL = root.appendingPathComponent(metadata.inventory.path)
  try requireRegularFile(inventoryURL, field: "prepared-inventory")
  let identity = try sha256File(inventoryURL)
  try require(identity.byteCount == metadata.inventory.sizeBytes,
              "prepared-inventory-size-mismatch")
  try require(identity.sha256 == metadata.inventory.sha256,
              "prepared-inventory-sha256-mismatch")

  let inventory: InstalledArtifactInventory = try readJSON(InstalledArtifactInventory.self, from: inventoryURL)
  try require(inventory.schemaVersion == 1, "prepared-inventory-schema-version")
  try require(inventory.candidate == metadata.inventory.candidate, "prepared-inventory-candidate")
  try require(inventory.status == metadata.inventory.status, "prepared-inventory-status")
  try require(inventory.releaseAdmitted == metadata.inventory.releaseAdmitted,
              "prepared-inventory-release-flag")
  try require(inventory.archives.count == 2, "prepared-inventory-archive-count")
  let expectedArchives = Set([
    InventoryArchive(fileName: metadata.runtime.archive.fileName, sha256: metadata.runtime.archive.sha256, sizeBytes: metadata.runtime.archive.sizeBytes),
    InventoryArchive(fileName: metadata.model.archive.fileName, sha256: metadata.model.archive.sha256, sizeBytes: metadata.model.archive.sizeBytes),
  ])
  try require(Set(inventory.archives) == expectedArchives, "prepared-inventory-archive-identity")
  try require(!inventory.installedFiles.isEmpty, "prepared-inventory-installed-files-empty")
  try require(inventory.totalInstalledBytes >= 0, "prepared-inventory-total-bytes")

  var seen = Set<String>()
  for file in inventory.installedFiles {
    try require(isSafeRelativePath(file.path) && (file.path.hasPrefix("runtime/") || file.path.hasPrefix("model/")),
                "prepared-inventory-unsafe-file-path")
    try require(isCanonicalHash(file.sha256) && file.sizeBytes > 0,
                "prepared-inventory-file-identity")
    try require(seen.insert(file.path).inserted, "prepared-inventory-duplicate-file")
  }
  for link in inventory.installedSymlinks {
    try require(isSafeRelativePath(link.path) && (link.path.hasPrefix("runtime/") || link.path.hasPrefix("model/")),
                "prepared-inventory-unsafe-symlink-path")
    try require(isSafeSymlinkTarget(link.target), "prepared-inventory-unsafe-symlink-target")
    try require(seen.insert(link.path).inserted, "prepared-inventory-duplicate-path")
  }
  let topLevel = Set((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [])
  try require(topLevel == [metadata.inventory.path, "runtime", "model"],
              "prepared-inventory-top-level-mismatch")
  try requireDirectory(root.appendingPathComponent("runtime"), field: "prepared-runtime-root")
  try requireDirectory(root.appendingPathComponent("model"), field: "prepared-model-root")
  try require(!isSymbolicLink(root.appendingPathComponent("runtime").path),
              "prepared-runtime-root-symlink")
  try require(!isSymbolicLink(root.appendingPathComponent("model").path),
              "prepared-model-root-symlink")

  let verifiedInventory: ArtifactInventory
  do {
    verifiedInventory = try ArtifactInventory.collect(from: root)
  } catch let error as ArtifactInventoryError {
    throw BenchmarkFailure(message: "prepared-runtime-inventory-" + error.description)
  } catch {
    throw BenchmarkFailure(message: "prepared-runtime-inventory-failed")
  }

  let expectedEntries = inventory.installedFiles.map { file in
    ArtifactInventory.Entry(
      relativePath: file.path,
      sha256: file.sha256,
      byteCount: file.sizeBytes
    )
  } + inventory.installedSymlinks.map { link in
    ArtifactInventory.Entry(
      relativePath: link.path,
      sha256: sha256Data(Data(link.target.utf8)),
      byteCount: Int64(link.target.utf8.count),
      kind: .symbolicLink,
      symlinkTarget: link.target
    )
  }
  let manifestEntry = verifiedInventory.files.first {
    $0.relativePath == metadata.inventory.path
  }
  try require(manifestEntry?.kind == .regularFile,
              "prepared-inventory-manifest-entry-missing")
  let actualEntries = verifiedInventory.files.filter {
    $0.relativePath != metadata.inventory.path
  }
  let sortedExpected = expectedEntries.sorted { $0.relativePath < $1.relativePath }
  let sortedActual = actualEntries.sorted { $0.relativePath < $1.relativePath }
  try require(sortedActual == sortedExpected,
              "prepared-runtime-inventory-content-mismatch")
  var actualRegularBytes: Int64 = 0
  for entry in actualEntries where entry.kind == .regularFile {
    let (next, overflow) = actualRegularBytes.addingReportingOverflow(entry.byteCount)
    try require(!overflow, "prepared-runtime-inventory-regular-bytes-overflow")
    actualRegularBytes = next
  }
  try require(actualRegularBytes == inventory.totalInstalledBytes,
              "prepared-runtime-inventory-total-bytes-mismatch")
  var declaredRegularBytes: Int64 = 0
  for entry in inventory.installedFiles {
    let (next, overflow) = declaredRegularBytes.addingReportingOverflow(entry.sizeBytes)
    try require(!overflow, "prepared-inventory-declared-total-bytes-overflow")
    declaredRegularBytes = next
  }
  try require(declaredRegularBytes == inventory.totalInstalledBytes,
              "prepared-inventory-declared-total-bytes-mismatch")

  return PreparedReceipt(
    inventoryPath: inventoryURL.path,
    inventoryRelativePath: metadata.inventory.path,
    inventorySHA256: identity.sha256,
    inventoryByteCount: identity.byteCount,
    inventory: inventory,
    verifiedInventory: verifiedInventory
  )
}

private func validateSource(_ source: CorpusSource) throws {
  try require(source.dataset == "google/fleurs", "corpus-dataset-mismatch")
  try require(source.repository == "https://huggingface.co/datasets/google/fleurs",
              "corpus-repository-mismatch")
  try require(source.revision == "a3c817cbf7c08863e0c472861c7c39e27ce7f38e",
              "corpus-revision-mismatch")
  try require(source.license == "CC-BY-4.0", "corpus-license-mismatch")
  try require(source.licenseURL == "https://creativecommons.org/licenses/by/4.0/",
              "corpus-license-url-mismatch")
  try require(source.files["englishValidation"]?.sha256 == "7c3eebdff31e1c510b78e51319e5b9779429b87c9895f2e5f3005bfe68854c65",
              "corpus-english-source-pin-mismatch")
  try require(source.files["mandarinValidation"]?.sha256 == "18698f80879a221f68318a4ccb8752b74c2f5bf521af0e0011b07e4670ea62ad",
              "corpus-mandarin-source-pin-mismatch")
}

private func readManifest(_ url: URL) throws -> ManifestReceipt {
  try requireRegularFile(url, field: "corpus-manifest")
  let identity = try sha256File(url)
  let manifest: CorpusManifest = try readJSON(CorpusManifest.self, from: url)
  try require(manifest.schemaVersion == 1 && manifest.immutable, "corpus-manifest-immutability")
  try validateSource(manifest.source)
  return ManifestReceipt(path: url.path, sha256: identity.sha256, byteCount: identity.byteCount, manifest: manifest)
}

private func selectedManifestCases(_ manifest: CorpusManifest, sourceClass: String) -> [CorpusCase] {
  manifest.cases.filter { $0.sourceClass == sourceClass }.sorted { $0.id < $1.id }
}

private func requireExactCheckedInCaseIdentity(
  supplied: ManifestReceipt,
  checkedIn: ManifestReceipt,
  sourceClass: String
) throws {
  let actual = selectedManifestCases(supplied.manifest, sourceClass: sourceClass)
  let expected = selectedManifestCases(checkedIn.manifest, sourceClass: sourceClass)
  try require(actual.count == expected.count, "corpus-(sourceClass)-checked-in-case-count")
  for (actualCase, expectedCase) in zip(actual, expected) {
    try require(actualCase.id == expectedCase.id &&
                  actualCase.reference == expectedCase.reference &&
                  actualCase.audioSHA256 == expectedCase.audioSHA256,
                "corpus-(sourceClass)-checked-in-case-identity:(actualCase.id)")
  }
}

private func validateCheckedInManifestIdentity(
  publicReceipt: ManifestReceipt,
  compositeReceipt: ManifestReceipt,
  checkedInReceipt: ManifestReceipt
) throws {
  try require(publicReceipt.manifest.manifestID == checkedInReceipt.manifest.manifestID &&
                compositeReceipt.manifest.manifestID == checkedInReceipt.manifest.manifestID,
              "corpus-checked-in-manifest-id")
  try require(publicReceipt.manifest.source.revision == checkedInReceipt.manifest.source.revision &&
                compositeReceipt.manifest.source.revision == checkedInReceipt.manifest.source.revision,
              "corpus-checked-in-manifest-revision")
  try requireExactCheckedInCaseIdentity(
    supplied: publicReceipt,
    checkedIn: checkedInReceipt,
    sourceClass: "publicHuman"
  )
  try requireExactCheckedInCaseIdentity(
    supplied: compositeReceipt,
    checkedIn: checkedInReceipt,
    sourceClass: "publicHumanComposite"
  )
}

private func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
  UInt32(data[offset]) |
    (UInt32(data[offset + 1]) << 8) |
    (UInt32(data[offset + 2]) << 16) |
    (UInt32(data[offset + 3]) << 24)
}

private func readUInt16LE(_ data: Data, at offset: Int) -> UInt16 {
  UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
}

private func readWAVShape(_ url: URL) throws -> AudioShape {
  let data = try Data(contentsOf: url, options: .mappedIfSafe)
  try require(data.count >= 12 && data[0..<4].elementsEqual(Data("RIFF".utf8)) && data[8..<12].elementsEqual(Data("WAVE".utf8)),
              "audio-not-wav")
  var offset = 12
  var sampleRate: Int?
  var channels: Int?
  var blockAlign: Int?
  var dataBytes = 0
  while offset + 8 <= data.count {
    let chunkSize = Int(readUInt32LE(data, at: offset + 4))
    let payloadStart = offset + 8
    try require(chunkSize >= 0 && payloadStart <= data.count && chunkSize <= data.count - payloadStart,
                "audio-invalid-chunk")
    let chunkID = data[offset..<offset + 4]
    if chunkID.elementsEqual(Data("fmt ".utf8)) {
      try require(chunkSize >= 16, "audio-invalid-format-chunk")
      let audioFormat = readUInt16LE(data, at: payloadStart)
      try require(audioFormat == 1 || audioFormat == 3, "audio-format-not-pcm")
      channels = Int(readUInt16LE(data, at: payloadStart + 2))
      sampleRate = Int(readUInt32LE(data, at: payloadStart + 4))
      blockAlign = Int(readUInt16LE(data, at: payloadStart + 12))
    } else if chunkID.elementsEqual(Data("data".utf8)) && dataBytes == 0 {
      dataBytes = chunkSize
    }
    let paddedEnd = payloadStart + chunkSize + (chunkSize & 1)
    try require(paddedEnd <= data.count, "audio-chunk-overrun")
    offset = paddedEnd
  }
  guard let sampleRate, let channels, let blockAlign else {
    throw BenchmarkFailure(message: "audio-format-metadata-missing")
  }
  try require(sampleRate == 16_000, "audio-sample-rate-must-be-16000")
  try require(channels == 1, "audio-must-be-mono")
  try require(blockAlign > 0 && dataBytes > 0 && dataBytes % blockAlign == 0,
              "audio-data-shape-invalid")
  return AudioShape(sampleRate: sampleRate, channels: channels, sampleCount: Int64(dataBytes / blockAlign))
}

private func validateCaseAudio(_ item: CorpusCase, root: URL) throws -> BenchmarkCase {
  try require(isCanonicalHash(item.audioSHA256), "case-(item.id)-audio-hash")
  try require(item.audioDurationMilliseconds > 0 && item.audioBytes > 0,
              "case-(item.id)-audio-metadata")
  let audioURL = try requireContainedAudio(item.sourceFile, root: root, id: item.id)
  let identity = try sha256File(audioURL)
  try require(identity.sha256 == item.audioSHA256, "case-(item.id)-audio-sha256-mismatch")
  try require(identity.byteCount == item.audioBytes, "case-(item.id)-audio-size-mismatch")
  let shape = try readWAVShape(audioURL)
  let durationMilliseconds = Int((Double(shape.sampleCount) * 1_000 / Double(shape.sampleRate)).rounded())
  try require(durationMilliseconds == item.audioDurationMilliseconds,
              "case-(item.id)-audio-duration-mismatch")
  try require(!item.naturalCodeSwitch, "case-(item.id)-natural-code-switch-claim")
  return BenchmarkCase(
    id: item.id,
    sourceFile: item.sourceFile,
    language: item.language,
    sourceClass: item.sourceClass,
    audioURL: audioURL,
    audioSHA256: item.audioSHA256,
    audioDurationMilliseconds: item.audioDurationMilliseconds,
    audioBytes: item.audioBytes,
    reference: item.reference,
    protectedExpectations: item.protectedExpectations,
    codeSwitchSpans: item.codeSwitchSpans ?? []
  )
}

private func selectCases(
  publicReceipt: ManifestReceipt,
  publicRoot: URL,
  compositeReceipt: ManifestReceipt,
  compositeRoot: URL
) throws -> [BenchmarkCase] {
  try require(publicReceipt.manifest.source.revision == compositeReceipt.manifest.source.revision,
              "corpus-manifest-revision-disagreement")
  try require(publicReceipt.manifest.manifestID == compositeReceipt.manifest.manifestID,
              "corpus-manifest-id-disagreement")

  let publicItems = publicReceipt.manifest.cases.filter { $0.sourceClass == "publicHuman" }
  let englishItems = publicItems.filter { $0.language == "english" }.sorted { $0.id < $1.id }
  let mandarinItems = publicItems.filter { $0.language == "mandarin" }.sorted { $0.id < $1.id }
  try require(englishItems.count == 12 && mandarinItems.count == 12,
              "corpus-public-human-counts-mismatch")
  try require(Set(publicItems.map(\.id)).count == publicItems.count,
              "corpus-public-human-duplicate-case")
  try require(publicItems.allSatisfy { !$0.naturalCodeSwitch && $0.codeSwitchSpans == nil },
              "corpus-public-human-composite-truth-mismatch")

  let compositeItems = compositeReceipt.manifest.cases
    .filter { $0.sourceClass == "publicHumanComposite" }
    .sorted { $0.id < $1.id }
  try require(compositeItems.count == 12, "corpus-composite-count-mismatch")
  try require(Set(compositeItems.map(\.id)).count == compositeItems.count,
              "corpus-composite-duplicate-case")
  let publicByID = Dictionary(uniqueKeysWithValues: (englishItems + mandarinItems).map { ($0.id, $0) })

  var result: [BenchmarkCase] = []
  for item in englishItems + mandarinItems {
    result.append(try validateCaseAudio(item, root: publicRoot))
  }
  for item in compositeItems {
    try require(item.language == "mixed" && !item.naturalCodeSwitch,
                "case-(item.id)-composite-language-truth")
    guard let spans = item.codeSwitchSpans, spans.count == 2 else {
      throw BenchmarkFailure(message: "case-\(item.id)-composite-spans-missing")
    }
    var languages = Set<String>()
    var previousEnd: Int64 = -1
    for span in spans {
      try require(span.startSample >= 0 && span.startSample < span.endSample,
                  "case-(item.id)-composite-span-order")
      try require(span.startSample >= previousEnd, "case-(item.id)-composite-span-overlap")
      try require(span.language == "en_us" || span.language == "cmn_hans_cn",
                  "case-(item.id)-composite-span-language")
      guard let sourceCase = publicByID[span.sourceCaseID] else {
        throw BenchmarkFailure(message: "case-\(item.id)-composite-source-case-missing")
      }
      try require(sourceCase.reference == span.reference,
                  "case-(item.id)-composite-reference-mismatch")
      languages.insert(span.language)
      previousEnd = span.endSample
    }
    try require(languages == ["en_us", "cmn_hans_cn"],
                "case-(item.id)-composite-language-pair")
    let validated = try validateCaseAudio(item, root: compositeRoot)
    let totalSamples = Int64(item.audioDurationMilliseconds) * 16
    try require(spans.allSatisfy { $0.endSample <= totalSamples },
                "case-(item.id)-composite-span-containment")
    result.append(validated)
  }
  try require(result.count == 36, "corpus-total-case-count-mismatch")
  try require(result.map(\.id) == (englishItems + mandarinItems + compositeItems).map(\.id),
              "corpus-stable-order-mismatch")
  return result
}

private struct JSONKeyScanner {
  private let bytes: [UInt8]
  private var index = 0

  init(_ data: Data) {
    bytes = Array(data)
  }

  static func topLevelKeys(_ data: Data) throws -> [String] {
    var scanner = JSONKeyScanner(data)
    return try scanner.readObjectKeys()
  }

  private mutating func readObjectKeys() throws -> [String] {
    skipWhitespace()
    guard consume(0x7B) else { throw BenchmarkFailure(message: "malformed-helper-json") }
    var keys: [String] = []
    skipWhitespace()
    if consume(0x7D) {
      skipWhitespace()
      guard index == bytes.count else { throw BenchmarkFailure(message: "malformed-helper-json") }
      return keys
    }
    while true {
      skipWhitespace()
      keys.append(try readString())
      skipWhitespace()
      guard consume(0x3A) else { throw BenchmarkFailure(message: "malformed-helper-json") }
      try skipValue()
      skipWhitespace()
      if consume(0x7D) { break }
      guard consume(0x2C) else { throw BenchmarkFailure(message: "malformed-helper-json") }
    }
    skipWhitespace()
    guard index == bytes.count else { throw BenchmarkFailure(message: "malformed-helper-json") }
    return keys
  }

  private mutating func skipValue() throws {
    skipWhitespace()
    guard index < bytes.count else { throw BenchmarkFailure(message: "malformed-helper-json") }
    switch bytes[index] {
    case 0x22:
      _ = try readString()
    case 0x7B:
      index += 1
      skipWhitespace()
      if consume(0x7D) { return }
      while true {
        skipWhitespace()
        _ = try readString()
        skipWhitespace()
        guard consume(0x3A) else { throw BenchmarkFailure(message: "malformed-helper-json") }
        try skipValue()
        skipWhitespace()
        if consume(0x7D) { return }
        guard consume(0x2C) else { throw BenchmarkFailure(message: "malformed-helper-json") }
      }
    case 0x5B:
      index += 1
      skipWhitespace()
      if consume(0x5D) { return }
      while true {
        try skipValue()
        skipWhitespace()
        if consume(0x5D) { return }
        guard consume(0x2C) else { throw BenchmarkFailure(message: "malformed-helper-json") }
      }
    default:
      let start = index
      while index < bytes.count,
        ![0x20, 0x09, 0x0A, 0x0D, 0x2C, 0x5D, 0x7D].contains(bytes[index]) {
        index += 1
      }
      guard index > start else { throw BenchmarkFailure(message: "malformed-helper-json") }
    }
  }

  private mutating func readString() throws -> String {
    guard consume(0x22) else { throw BenchmarkFailure(message: "malformed-helper-json") }
    var data = Data()
    while index < bytes.count {
      let byte = bytes[index]
      index += 1
      switch byte {
      case 0x22:
        guard let value = String(data: data, encoding: .utf8) else {
          throw BenchmarkFailure(message: "malformed-helper-json")
        }
        return value
      case 0x5C:
        guard index < bytes.count else { throw BenchmarkFailure(message: "malformed-helper-json") }
        let escape = bytes[index]
        index += 1
        switch escape {
        case 0x22, 0x5C, 0x2F:
          data.append(escape)
        case 0x62: data.append(0x08)
        case 0x66: data.append(0x0C)
        case 0x6E: data.append(0x0A)
        case 0x72: data.append(0x0D)
        case 0x74: data.append(0x09)
        case 0x75:
          guard index + 4 <= bytes.count else { throw BenchmarkFailure(message: "malformed-helper-json") }
          var scalarValue: UInt32 = 0
          for _ in 0..<4 {
            guard let digit = Self.hexValue(bytes[index]) else {
              throw BenchmarkFailure(message: "malformed-helper-json")
            }
            scalarValue = (scalarValue << 4) | digit
            index += 1
          }
          guard let scalar = UnicodeScalar(scalarValue), scalarValue < 0xD800 || scalarValue > 0xDFFF else {
            throw BenchmarkFailure(message: "malformed-helper-json")
          }
          data.append(contentsOf: String(scalar).utf8)
        default:
          throw BenchmarkFailure(message: "malformed-helper-json")
        }
      case 0x00...0x1F:
        throw BenchmarkFailure(message: "malformed-helper-json")
      default:
        data.append(byte)
      }
    }
    throw BenchmarkFailure(message: "malformed-helper-json")
  }

  private mutating func consume(_ byte: UInt8) -> Bool {
    guard index < bytes.count, bytes[index] == byte else { return false }
    index += 1
    return true
  }

  private mutating func skipWhitespace() {
    while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) {
      index += 1
    }
  }

  private static func hexValue(_ byte: UInt8) -> UInt32? {
    switch byte {
    case 0x30...0x39: return UInt32(byte - 0x30)
    case 0x41...0x46: return UInt32(byte - 0x41 + 10)
    case 0x61...0x66: return UInt32(byte - 0x61 + 10)
    default: return nil
    }
  }
}

private struct HelperEvent {
  let event: String
  let requestID: String
  let transcript: String?
  let runtimeVersion: String?
  let modelRevision: String?
  let code: String?
}

private func parseHelperEvent(_ data: Data) throws -> HelperEvent {
  guard data.count <= maximumJSONLineBytes, !data.isEmpty else {
    throw BenchmarkFailure(message: "helper-output-line-too-large")
  }
  let keys = try JSONKeyScanner.topLevelKeys(data)
  guard Set(keys).count == keys.count else {
    throw BenchmarkFailure(message: "duplicate-helper-output-key")
  }
  let object: [String: Any]
  do {
    guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw BenchmarkFailure(message: "helper-output-not-object")
    }
    object = value
  } catch let error as BenchmarkFailure {
    throw error
  } catch {
    throw BenchmarkFailure(message: "malformed-helper-json")
  }

  let globalKeys: Set<String> = [
    "schemaVersion", "event", "requestID", "runtimeVersion", "modelRevision",
    "transcript", "code", "message", "sequence",
  ]
  try require(Set(keys).isSubset(of: globalKeys), "unknown-helper-output-key")
  guard let schemaVersion = (object["schemaVersion"] as? NSNumber)?.intValue, schemaVersion == 1,
    let event = object["event"] as? String,
    let requestID = object["requestID"] as? String,
    !requestID.isEmpty
  else {
    throw BenchmarkFailure(message: "invalid-helper-output-envelope")
  }

  let allowed: Set<String>
  switch event {
  case "ready":
    allowed = ["schemaVersion", "event", "requestID", "runtimeVersion", "modelRevision"]
  case "final":
    allowed = ["schemaVersion", "event", "requestID", "transcript"]
  case "unloaded":
    allowed = ["schemaVersion", "event", "requestID"]
  case "failure":
    allowed = ["schemaVersion", "event", "requestID", "code", "message"]
  case "partial":
    throw BenchmarkFailure(message: "partial-helper-output")
  default:
    throw BenchmarkFailure(message: "unknown-helper-event:\(event)")
  }
  try require(Set(keys) == allowed, "helper-output-schema-mismatch:(event)")

  return HelperEvent(
    event: event,
    requestID: requestID,
    transcript: object["transcript"] as? String,
    runtimeVersion: object["runtimeVersion"] as? String,
    modelRevision: object["modelRevision"] as? String,
    code: object["code"] as? String
  )
}

private struct SessionDiagnostics {
  private(set) var processIdentifier: Int32 = 0
  let exitStatus: Int32
  let stdout: Data
  let stderr: String
  let stdoutByteCount: Int
  let stderrByteCount: Int
  let stderrReceivedByteCount: Int
  let stderrTruncated: Bool
  let events: [HelperEvent]
  let forcedTermination: Bool
}

private final class HelperSession: @unchecked Sendable {
  private let process: Process
  private let input: Pipe
  private let output: Pipe
  private let error: Pipe
  private let lock = NSLock()
  private let eventSignal = DispatchSemaphore(value: 0)
  private var stdoutLineBuffer = Data()
  private var stdoutData = Data()
  private var stdoutByteCount = 0
  private var stdoutProtocolError: String?
  private var events: [HelperEvent] = []
  private var stderrData = Data()
  private var stderrByteCount = 0
  private var stderrReceivedByteCount = 0
  private var stderrTruncated = false
  private var didExit = false
  private var exitStatus: Int32?
  private var readersStopped = false
  private let redactedRoots: [String]

  private(set) var processIdentifier: Int32 = 0

  init(
    executable: URL,
    arguments: [String],
    redactedRoots: [URL],
    expectedIdentity: (sha256: String, byteCount: Int64)? = nil
  ) throws {
    process = Process()
    input = Pipe()
    output = Pipe()
    error = Pipe()
    self.redactedRoots = redactedRoots.map { $0.path }.filter { !$0.isEmpty }
    process.executableURL = executable
    process.arguments = arguments
    process.environment = ["PATH": "/usr/bin:/bin", "LC_ALL": "C"]
    process.standardInput = input
    process.standardOutput = output
    process.standardError = error
    process.terminationHandler = { [weak self] child in
      guard let self else { return }
      self.lock.lock()
      self.didExit = true
      self.exitStatus = child.terminationStatus
      self.lock.unlock()
      self.eventSignal.signal()
    }
    if let expectedIdentity {
      let launchIdentity = try sha256File(executable)
      guard launchIdentity.sha256 == expectedIdentity.sha256,
        launchIdentity.byteCount == expectedIdentity.byteCount
      else {
        throw BenchmarkFailure(message: "helper-build-changed-before-launch")
      }
    }
    try process.run()
    processIdentifier = process.processIdentifier
    guard processIdentifier > 0 else { throw BenchmarkFailure(message: "helper-process-id-unavailable") }
    installReaders()
  }

  func send(_ object: [String: Any], expectedEvent: String, timeout: TimeInterval = helperRequestTimeout) throws -> HelperEvent {
    let requestID = try requestID(from: object)
    try write(object)
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      lock.lock()
      if let error = stdoutProtocolError {
        lock.unlock()
        throw BenchmarkFailure(message: error)
      }
      if let index = events.firstIndex(where: { $0.requestID == requestID }) {
        let event = events.remove(at: index)
        lock.unlock()
        try require(event.event == expectedEvent,
                    "helper-request-\(requestID)-expected-\(expectedEvent)-received-\(event.event)")
        if event.event == "failure" {
          throw BenchmarkFailure(message: "helper-failure:\(event.code ?? "unknown")")
        }
        return event
      }
      if let foreign = events.first(where: { $0.requestID != requestID }) {
        lock.unlock()
        throw BenchmarkFailure(message: "helper-output-request-order:\(foreign.requestID)")
      }
      let exited = didExit
      lock.unlock()
      if exited {
        throw BenchmarkFailure(message: "helper-exited-before-\(requestID)")
      }
      _ = eventSignal.wait(timeout: .now() + 0.05)
    }
    throw BenchmarkFailure(message: "helper-request-timeout:\(requestID)")
  }

  func write(_ object: [String: Any]) throws {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
      data.count < maximumJSONLineBytes,
      !data.contains(0x0A),
      !data.contains(0x0D)
    else {
      throw BenchmarkFailure(message: "invalid-helper-request")
    }
    var line = data
    line.append(0x0A)
    try input.fileHandleForWriting.write(contentsOf: line)
  }

  func waitForStderrMarker(_ marker: String, timeout: TimeInterval) throws {
    let needle = Data(marker.utf8)
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      lock.lock()
      let found = stderrData.range(of: needle) != nil
      let error = stdoutProtocolError
      let exited = didExit
      lock.unlock()
      if let error { throw BenchmarkFailure(message: error) }
      if found { return }
      if exited { throw BenchmarkFailure(message: "helper-exited-before-marker:\(marker)") }
      _ = eventSignal.wait(timeout: .now() + 0.05)
    }
    throw BenchmarkFailure(message: "helper-marker-timeout:\(marker)")
  }

  func finishCooperatively() throws -> SessionDiagnostics {
    try? input.fileHandleForWriting.close()
    let deadline = Date().addingTimeInterval(cooperativeFinishDeadline)
    while process.isRunning && Date() < deadline {
      RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
    guard !process.isRunning else {
      let pid = processIdentifier
      process.terminate()
      let terminateDeadline = Date().addingTimeInterval(1)
      while process.isRunning && Date() < terminateDeadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
      }
      if process.isRunning {
        guard kill(pid, SIGKILL) == 0 else {
          throw BenchmarkFailure(message: "cooperative-shutdown-kill-failed:\(pid)")
        }
      }
      process.waitUntilExit()
      stopReadersAndDrain()
      throw BenchmarkFailure(message: "helper-shutdown-timeout-forced-termination:\(pid)")
    }
    stopReadersAndDrain()
    lock.lock()
    let error = stdoutProtocolError
    let status = exitStatus ?? process.terminationStatus
    let diagnostics = makeDiagnostics(status: status, forced: false)
    lock.unlock()
    if let error { throw BenchmarkFailure(message: error) }
    try require(status == 0, "helper-exit-status-(status)")
    return diagnostics
  }

  func terminateExactly(within timeout: TimeInterval) throws -> SessionDiagnostics {
    let pid = processIdentifier
    process.terminate()
    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning && Date() < deadline {
      RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
    if process.isRunning {
      guard kill(pid, SIGKILL) == 0 else {
        throw BenchmarkFailure(message: "forced-termination-kill-failed:\(pid)")
      }
      process.waitUntilExit()
    }
    stopReadersAndDrain()
    lock.lock()
    let error = stdoutProtocolError
    let status = exitStatus ?? process.terminationStatus
    let diagnostics = makeDiagnostics(status: status, forced: true)
    lock.unlock()
    if let error, !error.hasPrefix("helper-output-line-too-large") {
      throw BenchmarkFailure(message: error)
    }
    return diagnostics
  }

  private func requestID(from object: [String: Any]) throws -> String {
    guard let requestID = object["requestID"] as? String, !requestID.isEmpty else {
      throw BenchmarkFailure(message: "request-id-missing")
    }
    return requestID
  }

  private func installReaders() {
    output.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      guard !data.isEmpty else { return }
      self?.appendStdout(data)
    }
    error.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      guard !data.isEmpty else { return }
      self?.appendStderr(data)
    }
  }

  private func appendStdout(_ data: Data) {
    lock.lock()
    stdoutByteCount += data.count
    stdoutData.append(data)
    if stdoutData.count > maximumCapturedOutputBytes {
      stdoutData = Data(stdoutData.suffix(maximumCapturedOutputBytes))
    }
    stdoutLineBuffer.append(data)
    if stdoutLineBuffer.count > maximumJSONLineBytes {
      stdoutProtocolError = "helper-output-flood"
    } else {
      while let newline = stdoutLineBuffer.firstIndex(of: 0x0A) {
        let line = Data(stdoutLineBuffer[..<newline])
        stdoutLineBuffer.removeSubrange(...newline)
        do {
          events.append(try parseHelperEvent(line))
        } catch let failure as BenchmarkFailure {
          stdoutProtocolError = failure.message
          break
        } catch {
          stdoutProtocolError = "malformed-helper-json"
          break
        }
      }
    }
    lock.unlock()
    eventSignal.signal()
  }

  private func appendStderr(_ data: Data) {
    let value = String(decoding: data, as: UTF8.self)
    var redacted = value
    for root in redactedRoots where !root.isEmpty {
      redacted = redacted.replacingOccurrences(of: root, with: "<redacted-path>")
    }
    let redactedData = Data(redacted.utf8)
    lock.lock()
    stderrReceivedByteCount += data.count
    stderrByteCount += redactedData.count
    stderrData.append(redactedData)
    if stderrData.count > maximumCapturedOutputBytes {
      stderrData = Data(stderrData.suffix(maximumCapturedOutputBytes))
      stderrTruncated = true
    }
    lock.unlock()
    eventSignal.signal()
  }

  private func stopReadersAndDrain() {
    lock.lock()
    guard !readersStopped else {
      lock.unlock()
      return
    }
    readersStopped = true
    lock.unlock()
    output.fileHandleForReading.readabilityHandler = nil
    error.fileHandleForReading.readabilityHandler = nil
    let remainingStdout = output.fileHandleForReading.readDataToEndOfFile()
    if !remainingStdout.isEmpty { appendStdout(remainingStdout) }
    let remainingStderr = error.fileHandleForReading.readDataToEndOfFile()
    if !remainingStderr.isEmpty { appendStderr(remainingStderr) }
    lock.lock()
    if !stdoutLineBuffer.isEmpty, stdoutProtocolError == nil {
      stdoutProtocolError = "helper-output-missing-newline"
    }
    lock.unlock()
  }

  private func makeDiagnostics(status: Int32, forced: Bool) -> SessionDiagnostics {
    SessionDiagnostics(
      processIdentifier: processIdentifier,
      exitStatus: status,
      stdout: stdoutData,
      stderr: String(decoding: stderrData, as: UTF8.self),
      stdoutByteCount: stdoutByteCount,
      stderrByteCount: stderrByteCount,
      stderrReceivedByteCount: stderrReceivedByteCount,
      stderrTruncated: stderrTruncated,
      events: events,
      forcedTermination: forced
    )
  }
}

private struct ResourcePeak {
  var residentBytes: Int64
  var physicalFootprintBytes: Int64
}

private final class ExactProcessResourceSampler: @unchecked Sendable {
  private let processIdentifier: Int32
  private let lock = NSLock()
  private var peak: ResourcePeak?
  private var timer: DispatchSourceTimer?

  init(processIdentifier: Int32) {
    self.processIdentifier = processIdentifier
  }

  func start() throws {
    try recordSample()
    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
    timer.schedule(deadline: .now(), repeating: .milliseconds(50))
    timer.setEventHandler { [weak self] in
      try? self?.recordSample()
    }
    timer.resume()
    self.timer = timer
  }

  func stop() throws -> ResourcePeak {
    timer?.cancel()
    timer = nil
    lock.lock()
    defer { lock.unlock() }
    guard let peak else { throw BenchmarkFailure(message: "resource-sample-missing") }
    return peak
  }

  private func recordSample() throws {
    var usage = rusage_info_v4()
    let result = withUnsafeMutablePointer(to: &usage) { pointer in
      pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
        proc_pid_rusage(processIdentifier, RUSAGE_INFO_V4, $0)
      }
    }
    guard result == 0,
      let resident = Int64(exactly: usage.ri_resident_size),
      let physical = Int64(exactly: usage.ri_phys_footprint),
      resident >= 0,
      physical >= 0
    else {
      throw BenchmarkFailure(message: "resource-sample-unavailable:\(processIdentifier)")
    }
    lock.lock()
    if let peak {
      self.peak = ResourcePeak(
        residentBytes: max(peak.residentBytes, resident),
        physicalFootprintBytes: max(peak.physicalFootprintBytes, physical)
      )
    } else {
      peak = ResourcePeak(residentBytes: resident, physicalFootprintBytes: physical)
    }
    lock.unlock()
  }
}

private struct WarmCaseResult {
  let benchmarkCase: BenchmarkCase
  let hypothesis: String
  let wallRequestToFinalMilliseconds: Double
  let helperNativeDecodeMilliseconds: Double?
  let peak: ResourcePeak
}

private struct WarmRun {
  let cases: [WarmCaseResult]
  let loadReadyMilliseconds: Double
  let unloadMilliseconds: Double
  let shutdownMilliseconds: Double
  let processIdentifier: Int32
  let peak: ResourcePeak
  let diagnostics: SessionDiagnostics
}

private struct ColdRun {
  let benchmarkCase: BenchmarkCase
  let hypothesis: String
  let launchToFinalMilliseconds: Double
  let loadReadyMilliseconds: Double
  let wallRequestToFinalMilliseconds: Double
  let helperNativeDecodeMilliseconds: Double?
  let peak: ResourcePeak
  let diagnostics: SessionDiagnostics
}

private struct CancellationRun {
  let benchmarkCase: BenchmarkCase
  let processIdentifier: Int32
  let peak: ResourcePeak
  let diagnostics: SessionDiagnostics
  let markerObserved: Bool
  let noLateFinal: Bool
}

private func monotonicMilliseconds() -> Double {
  Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000
}

private func locale(for language: String) throws -> String {
  switch language {
  case "english": return "en-US"
  case "mandarin": return "zh-CN"
  case "mixed": return "auto"
  default: throw BenchmarkFailure(message: "unsupported-case-language:\(language)")
  }
}

private func helperRequest(
  id: String,
  operation: String,
  benchmarkCase: BenchmarkCase? = nil
) throws -> [String: Any] {
  var object: [String: Any] = [
    "schemaVersion": 1,
    "requestID": id,
    "operation": operation,
    "contextPhrases": [],
    "protectedForms": [],
  ]
  if let benchmarkCase {
    object["audioPath"] = benchmarkCase.audioURL.path
    object["sampleRate"] = 16_000
    object["localeIdentifier"] = try locale(for: benchmarkCase.language)
  }
  return object
}

private func terminateQuietly(_ session: HelperSession) {
  _ = try? session.terminateExactly(within: 1)
}

private func nativeMeasurements(_ stderr: String) -> [String: Double] {
  var result: [String: Double] = [:]
  for line in stderr.split(whereSeparator: \.isNewline) where line.hasPrefix("measurement ") {
    var requestID: String?
    var milliseconds: Double?
    for component in line.split(separator: " ") {
      let pair = component.split(separator: "=", maxSplits: 1).map(String.init)
      guard pair.count == 2 else { continue }
      if pair[0] == "requestID" { requestID = pair[1] }
      if pair[0] == "elapsedMs" { milliseconds = Double(pair[1]) }
    }
    if let requestID, let milliseconds, milliseconds.isFinite, milliseconds >= 0 {
      result[requestID] = milliseconds
    }
  }
  return result
}

private func runWarm(
  preparedRoot: URL,
  helper: URL,
  helperIdentity: (sha256: String, byteCount: Int64),
  cases: [BenchmarkCase],
  metadata: CandidateMetadata,
  redactedRoots: [URL]
) throws -> WarmRun {
  let session = try HelperSession(
    executable: helper,
    arguments: ["--prepared-root", preparedRoot.path],
    redactedRoots: redactedRoots,
    expectedIdentity: helperIdentity
  )
  do {
    let sampler = ExactProcessResourceSampler(processIdentifier: session.processIdentifier)
    try sampler.start()
    let loadStarted = monotonicMilliseconds()
    let ready = try session.send(try helperRequest(id: "warm-load", operation: "load"), expectedEvent: "ready")
    let loadReadyMilliseconds = monotonicMilliseconds() - loadStarted
    try require(ready.runtimeVersion == metadata.runtime.revision,
                "warm-runtime-identity-mismatch")
    try require(ready.modelRevision == metadata.model.convertedRevision,
                "warm-model-identity-mismatch")

    var results: [WarmCaseResult] = []
    for benchmarkCase in cases {
      let requestID = "warm-\(benchmarkCase.id)"
      let started = monotonicMilliseconds()
      let event = try session.send(
        try helperRequest(id: requestID, operation: "transcribe", benchmarkCase: benchmarkCase),
        expectedEvent: "final"
      )
      let elapsed = monotonicMilliseconds() - started
      guard let hypothesis = event.transcript else {
        throw BenchmarkFailure(message: "helper-final-transcript-missing:\(benchmarkCase.id)")
      }
      results.append(
        WarmCaseResult(
          benchmarkCase: benchmarkCase,
          hypothesis: hypothesis,
          wallRequestToFinalMilliseconds: elapsed,
          helperNativeDecodeMilliseconds: nil,
          peak: ResourcePeak(residentBytes: 0, physicalFootprintBytes: 0)
        )
      )
    }

    let inferPeak = try sampler.stop()
    let unloadStarted = monotonicMilliseconds()
    _ = try session.send(try helperRequest(id: "warm-unload", operation: "unload"), expectedEvent: "unloaded")
    let unloadMilliseconds = monotonicMilliseconds() - unloadStarted
    let shutdownStarted = monotonicMilliseconds()
    _ = try session.send(try helperRequest(id: "warm-shutdown", operation: "shutdown"), expectedEvent: "unloaded")
    let shutdownMilliseconds = monotonicMilliseconds() - shutdownStarted
    let diagnostics = try session.finishCooperatively()
    let measurements = nativeMeasurements(diagnostics.stderr)
    let completed = results.map { result in
      WarmCaseResult(
        benchmarkCase: result.benchmarkCase,
        hypothesis: result.hypothesis,
        wallRequestToFinalMilliseconds: result.wallRequestToFinalMilliseconds,
        helperNativeDecodeMilliseconds: measurements["warm-\(result.benchmarkCase.id)"],
        peak: inferPeak
      )
    }
    return WarmRun(
      cases: completed,
      loadReadyMilliseconds: loadReadyMilliseconds,
      unloadMilliseconds: unloadMilliseconds,
      shutdownMilliseconds: shutdownMilliseconds,
      processIdentifier: session.processIdentifier,
      peak: inferPeak,
      diagnostics: diagnostics
    )
  } catch {
    terminateQuietly(session)
    throw error
  }
}

private func runCold(
  preparedRoot: URL,
  helper: URL,
  helperIdentity: (sha256: String, byteCount: Int64),
  benchmarkCase: BenchmarkCase,
  metadata: CandidateMetadata,
  index: Int,
  redactedRoots: [URL]
) throws -> ColdRun {
  let processStarted = monotonicMilliseconds()
  let session = try HelperSession(
    executable: helper,
    arguments: ["--prepared-root", preparedRoot.path],
    redactedRoots: redactedRoots,
    expectedIdentity: helperIdentity
  )
  do {
    let sampler = ExactProcessResourceSampler(processIdentifier: session.processIdentifier)
    try sampler.start()
    let loadStarted = monotonicMilliseconds()
    let ready = try session.send(try helperRequest(id: "cold-\(index)-load", operation: "load"), expectedEvent: "ready")
    let loadReadyMilliseconds = monotonicMilliseconds() - loadStarted
    try require(ready.runtimeVersion == metadata.runtime.revision,
                "cold-runtime-identity-mismatch:\(index)")
    try require(ready.modelRevision == metadata.model.convertedRevision,
                "cold-model-identity-mismatch:\(index)")
    let requestID = "cold-\(index)-\(benchmarkCase.id)"
    let started = monotonicMilliseconds()
    let event = try session.send(
      try helperRequest(id: requestID, operation: "transcribe", benchmarkCase: benchmarkCase),
      expectedEvent: "final"
    )
    let wallMilliseconds = monotonicMilliseconds() - started
    let launchToFinalMilliseconds = monotonicMilliseconds() - processStarted
    guard let hypothesis = event.transcript else {
      throw BenchmarkFailure(message: "helper-final-transcript-missing:\(benchmarkCase.id)")
    }
    _ = try session.send(try helperRequest(id: "cold-\(index)-unload", operation: "unload"), expectedEvent: "unloaded")
    let peak = try sampler.stop()
    _ = try session.send(try helperRequest(id: "cold-\(index)-shutdown", operation: "shutdown"), expectedEvent: "unloaded")
    let diagnostics = try session.finishCooperatively()
    let helperNativeDecodeMilliseconds = nativeMeasurements(diagnostics.stderr)[requestID]
    return ColdRun(
      benchmarkCase: benchmarkCase,
      hypothesis: hypothesis,
      launchToFinalMilliseconds: launchToFinalMilliseconds,
      loadReadyMilliseconds: loadReadyMilliseconds,
      wallRequestToFinalMilliseconds: wallMilliseconds,
      helperNativeDecodeMilliseconds: helperNativeDecodeMilliseconds,
      peak: peak,
      diagnostics: diagnostics
    )
  } catch {
    terminateQuietly(session)
    throw error
  }
}

private func runCancellation(
  preparedRoot: URL,
  helper: URL,
  helperIdentity: (sha256: String, byteCount: Int64),
  benchmarkCase: BenchmarkCase,
  metadata: CandidateMetadata,
  redactedRoots: [URL]
) throws -> CancellationRun {
  let session = try HelperSession(
    executable: helper,
    arguments: ["--prepared-root", preparedRoot.path, "--probe-blocked-decode"],
    redactedRoots: redactedRoots,
    expectedIdentity: helperIdentity
  )
  do {
    let sampler = ExactProcessResourceSampler(processIdentifier: session.processIdentifier)
    try sampler.start()
    let ready = try session.send(try helperRequest(id: "cancel-load", operation: "load"), expectedEvent: "ready")
    try require(ready.runtimeVersion == metadata.runtime.revision, "cancel-runtime-identity-mismatch")
    try require(ready.modelRevision == metadata.model.convertedRevision, "cancel-model-identity-mismatch")
    let requestID = "cancel-\(benchmarkCase.id)"
    try session.write(try helperRequest(id: requestID, operation: "transcribe", benchmarkCase: benchmarkCase))
    try session.waitForStderrMarker("native-decode-blocked", timeout: helperRequestTimeout)
    let diagnostics = try session.terminateExactly(within: cancellationDeadline)
    let peak = try sampler.stop()
    let noLateFinal = !diagnostics.events.contains { $0.requestID == requestID && $0.event == "final" }
    try require(noLateFinal, "late-final-after-forced-termination")
    return CancellationRun(
      benchmarkCase: benchmarkCase,
      processIdentifier: session.processIdentifier,
      peak: peak,
      diagnostics: diagnostics,
      markerObserved: true,
      noLateFinal: noLateFinal
    )
  } catch {
    terminateQuietly(session)
    throw error
  }
}

private func commandOutput(_ executable: String, arguments: [String]) -> String? {
  let process = Process()
  let pipe = Pipe()
  process.executableURL = URL(fileURLWithPath: executable)
  process.arguments = arguments
  process.environment = ["PATH": "/usr/bin:/bin", "LC_ALL": "C"]
  process.standardOutput = pipe
  process.standardError = FileHandle.nullDevice
  do {
    try process.run()
    process.waitUntilExit()
  } catch {
    return nil
  }
  guard process.terminationStatus == 0 else { return nil }
  let value = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    .trimmingCharacters(in: .whitespacesAndNewlines)
  return value.isEmpty ? nil : value
}

private struct OfflineObservation {
  let enforced: Bool
  let claimsVerifiedOffline: Bool
  let unexpectedConnectionCount: Int
  let probeAttempted: Bool
  let deniedError: String?
}

private func runOfflineNetworkProbe(contractTest: Bool) throws -> OfflineObservation {
  if contractTest {
    return OfflineObservation(
      enforced: false,
      claimsVerifiedOffline: false,
      unexpectedConnectionCount: 0,
      probeAttempted: false,
      deniedError: nil
    )
  }

  let descriptor = socket(AF_INET, SOCK_STREAM, 0)
  if descriptor < 0 {
    guard errno == EPERM || errno == EACCES else {
      throw BenchmarkFailure(message: "offline-network-probe-not-denied")
    }
    return OfflineObservation(
      enforced: true,
      claimsVerifiedOffline: true,
      unexpectedConnectionCount: 0,
      probeAttempted: true,
      deniedError: errno == EPERM ? "EPERM" : "EACCES"
    )
  }
  defer { close(descriptor) }

  var address = sockaddr_in()
  address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
  address.sin_family = sa_family_t(AF_INET)
  address.sin_port = in_port_t(9).bigEndian
  address.sin_addr.s_addr = inet_addr("127.0.0.1")
  let result = withUnsafePointer(to: &address) { pointer in
    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
    }
  }
  guard result < 0, errno == EPERM || errno == EACCES else {
    throw BenchmarkFailure(message: "offline-network-probe-not-denied")
  }
  return OfflineObservation(
    enforced: true,
    claimsVerifiedOffline: true,
    unexpectedConnectionCount: 0,
    probeAttempted: true,
    deniedError: errno == EPERM ? "EPERM" : "EACCES"
  )
}

private struct HardwareReceipt {
  let hwModel: String
  let chip: String
  let architecture: String
  let memoryBytes: Int64
  let osBuild: String
}

private func hardwareReceipt() throws -> HardwareReceipt {
  let hwModel = try requireHardwareValue(commandOutput("/usr/sbin/sysctl", arguments: ["-n", "hw.model"]), "hw.model")
  let chip = commandOutput("/usr/sbin/sysctl", arguments: ["-n", "machdep.cpu.brand_string"]) ?? "Apple Silicon"
  let architecture = try requireHardwareValue(commandOutput("/usr/bin/uname", arguments: ["-m"]), "architecture")
  let memoryText = try requireHardwareValue(commandOutput("/usr/sbin/sysctl", arguments: ["-n", "hw.memsize"]), "memory")
  guard let memoryBytes = Int64(memoryText), memoryBytes > 0 else {
    throw BenchmarkFailure(message: "hardware-memory-invalid")
  }
  let osBuild = try requireHardwareValue(commandOutput("/usr/sbin/sysctl", arguments: ["-n", "kern.osversion"]), "os-build")
  return HardwareReceipt(hwModel: hwModel, chip: chip, architecture: architecture, memoryBytes: memoryBytes, osBuild: osBuild)
}

private func requireHardwareValue(_ value: String?, _ field: String) throws -> String {
  guard let value, !value.isEmpty else { throw BenchmarkFailure(message: "hardware-\(field)-unavailable") }
  return value
}

private func lowercasedPOSIX(_ text: String) -> String {
  (text as NSString).lowercased(with: Locale(identifier: "en_US_POSIX"))
}

private func isLetterOrDigit(_ character: Character) -> Bool {
  character.unicodeScalars.contains {
    CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
  }
}

private func isHan(_ character: Character) -> Bool {
  character.unicodeScalars.contains { $0.properties.isIdeographic || $0.properties.isUnifiedIdeograph }
}

private func isWhitespace(_ character: Character) -> Bool {
  character.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
}

private func isPunctuation(_ character: Character) -> Bool {
  character.unicodeScalars.contains { CharacterSet.punctuationCharacters.contains($0) }
}

private func isApostrophe(_ character: Character) -> Bool {
  character.unicodeScalars.count == 1
    && [0x27, 0x2019, 0x02BC, 0xFF07].contains(character.unicodeScalars.first!.value)
}

private func wordTokens(_ text: String) -> [String] {
  var result: [String] = []
  var word = ""
  let characters = Array(text)
  var index = 0

  func flush() {
    guard !word.isEmpty else { return }
    result.append(word)
    word.removeAll(keepingCapacity: true)
  }

  while index < characters.count {
    let character = characters[index]
    guard isLetterOrDigit(character) else {
      index += 1
      continue
    }
    word.append(character)
    index += 1
    while index < characters.count {
      let next = characters[index]
      if isLetterOrDigit(next) {
        word.append(next)
        index += 1
      } else if isApostrophe(next), index + 1 < characters.count,
                isLetterOrDigit(characters[index + 1]) {
        word.append(next)
        index += 1
      } else {
        break
      }
    }
    flush()
  }
  flush()
  return result
}

private func mixedTokens(_ text: String) -> [String] {
  var result: [String] = []
  var word = ""
  let characters = Array(text)
  var index = 0

  func flush() {
    guard !word.isEmpty else { return }
    result.append(word)
    word.removeAll(keepingCapacity: true)
  }

  while index < characters.count {
    let character = characters[index]
    if isHan(character) {
      flush()
      result.append(String(character))
      index += 1
      continue
    }
    guard isLetterOrDigit(character) else {
      flush()
      index += 1
      continue
    }
    word.append(character)
    index += 1
    while index < characters.count {
      let next = characters[index]
      if isLetterOrDigit(next), !isHan(next) {
        word.append(next)
        index += 1
      } else if isApostrophe(next), index + 1 < characters.count,
                isLetterOrDigit(characters[index + 1]), !isHan(characters[index + 1]) {
        word.append(next)
        index += 1
      } else {
        break
      }
    }
    flush()
  }
  flush()
  return result
}

private func evaluationTokens(_ text: String, language: String) -> [String] {
  switch language {
  case "english": return wordTokens(lowercasedPOSIX(text))
  case "mandarin": return text.filter { !isWhitespace($0) && !isPunctuation($0) }.map(String.init)
  case "mixed": return mixedTokens(lowercasedPOSIX(text))
  default: return []
  }
}

private func levenshtein(_ reference: [String], _ hypothesis: [String]) -> Int {
  var previous = Array(0...hypothesis.count)
  for (referenceIndex, referenceToken) in reference.enumerated() {
    var current = [referenceIndex + 1]
    current.reserveCapacity(hypothesis.count + 1)
    for (hypothesisIndex, hypothesisToken) in hypothesis.enumerated() {
      let substitution = previous[hypothesisIndex] + (referenceToken == hypothesisToken ? 0 : 1)
      let insertion = current[hypothesisIndex] + 1
      let deletion = previous[hypothesisIndex + 1] + 1
      current.append(min(substitution, insertion, deletion))
    }
    previous = current
  }
  return previous[hypothesis.count]
}

private func collapseWhitespace(_ text: String) -> String {
  text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

private func protectedExpectationMatches(_ expectation: ProtectedExpectation, hypothesis: String) -> Bool {
  switch expectation.comparison {
  case "exact": return hypothesis.contains(expectation.text)
  case "caseAndWhitespaceInsensitive":
    return collapseWhitespace(lowercasedPOSIX(hypothesis)).contains(
      collapseWhitespace(lowercasedPOSIX(expectation.text))
    )
  default: return false
  }
}

private func spanMatches(_ span: CodeSwitchSpan, hypothesis: String) -> Bool {
  hypothesis.contains(span.reference) || collapseWhitespace(lowercasedPOSIX(hypothesis)).contains(
    collapseWhitespace(lowercasedPOSIX(span.reference))
  )
}

private func nearestRank(_ values: [Double], percentile: Double) -> Double? {
  guard !values.isEmpty else { return nil }
  let sorted = values.sorted()
  let rank = max(1, Int(ceil(percentile * Double(sorted.count))))
  return sorted[min(rank - 1, sorted.count - 1)]
}

private struct AccuracySummary {
  let englishWER: Double?
  let mandarinCER: Double?
  let mixedMER: Double?
  let codeSwitchSpanAccuracy: Double?
  let protectedViolationCount: Int
}

private func accuracySummary(_ results: [WarmCaseResult]) -> AccuracySummary {
  var edits: [String: Int] = [:]
  var referenceUnits: [String: Int] = [:]
  var protectedViolations = 0
  var matchedSpans = 0
  var totalSpans = 0
  for result in results {
    let referenceTokens = evaluationTokens(result.benchmarkCase.reference, language: result.benchmarkCase.language)
    let hypothesisTokens = evaluationTokens(result.hypothesis, language: result.benchmarkCase.language)
    edits[result.benchmarkCase.language, default: 0] += levenshtein(referenceTokens, hypothesisTokens)
    referenceUnits[result.benchmarkCase.language, default: 0] += referenceTokens.count
    protectedViolations += result.benchmarkCase.protectedExpectations.filter {
      !protectedExpectationMatches($0, hypothesis: result.hypothesis)
    }.count
    for span in result.benchmarkCase.codeSwitchSpans {
      totalSpans += 1
      if spanMatches(span, hypothesis: result.hypothesis) { matchedSpans += 1 }
    }
  }
  func rate(_ language: String) -> Double? {
    guard let units = referenceUnits[language], units > 0 else { return nil }
    return Double(edits[language, default: 0]) / Double(units)
  }
  return AccuracySummary(
    englishWER: rate("english"),
    mandarinCER: rate("mandarin"),
    mixedMER: rate("mixed"),
    codeSwitchSpanAccuracy: totalSpans == 0 ? nil : Double(matchedSpans) / Double(totalSpans),
    protectedViolationCount: protectedViolations
  )
}

private func jsonArchive(_ archive: ArchiveMetadata) -> [String: Any] {
  return [
    "id": archive.id,
    "revision": archive.revision,
    "sha256": archive.sha256,
    "byteCount": archive.sizeBytes,
  ]
}

private func jsonExpectation(_ expectation: ProtectedExpectation) -> [String: Any] {
  ["kind": expectation.kind, "text": expectation.text, "comparison": expectation.comparison]
}

private func jsonSpan(_ span: CodeSwitchSpan, hypothesis: String) -> [String: Any] {
  [
    "startMilliseconds": Double(span.startSample) * 1_000 / 16_000,
    "endMilliseconds": Double(span.endSample) * 1_000 / 16_000,
    "language": span.language == "en_us" ? "english" : "mandarin",
    "matched": spanMatches(span, hypothesis: hypothesis),
  ]
}

private func jsonCase(_ result: WarmCaseResult) -> [String: Any] {
  let item = result.benchmarkCase
  return [
    "id": item.id,
    "language": item.language,
    "sourceClass": item.sourceClass,
    "audioSHA256": item.audioSHA256,
    "audioDurationMilliseconds": Double(item.audioDurationMilliseconds),
    "reference": item.reference,
    "hypothesis": result.hypothesis,
    "protectedExpectations": item.protectedExpectations.map(jsonExpectation),
    "claimsNaturalCodeSwitch": false,
    "codeSwitchSpans": item.codeSwitchSpans.map { jsonSpan($0, hypothesis: result.hypothesis) },
    "captureTemperature": 0.0,
    "timing": [
      "fileDecodeMilliseconds": result.wallRequestToFinalMilliseconds,
      "stopToFinalMilliseconds": result.wallRequestToFinalMilliseconds,
      "firstPartialMilliseconds": NSNull(),
      "isCold": false,
    ],
    "peakResidentBytes": result.peak.residentBytes,
    "peakPhysicalFootprintBytes": result.peak.physicalFootprintBytes,
    "outcome": "transcribed",
    "cancellation": ["outcome": "notCancelled", "noLateOutput": false],
  ]
}

private func jsonEvaluationCase(_ result: WarmCaseResult) -> [String: Any] {
  let item = result.benchmarkCase
  return [
    "id": item.id,
    "language": item.language,
    "reference": item.reference,
    "hypothesis": result.hypothesis,
    "protectedExpectations": item.protectedExpectations.map(jsonExpectation),
    "timing": [
      "isCold": false,
      "firstPartialMilliseconds": NSNull(),
      "stopToFinalMilliseconds": result.wallRequestToFinalMilliseconds,
      "stopToInsertionMilliseconds": NSNull(),
    ],
    "peakResidentBytes": result.peak.residentBytes,
  ]
}

private func jsonLifecyclePhase(
  outcome: String,
  durationMilliseconds: Double,
  peak: ResourcePeak
) -> [String: Any] {
  [
    "outcome": outcome,
    "durationMilliseconds": durationMilliseconds,
    "peakResidentBytes": peak.residentBytes,
    "peakPhysicalFootprintBytes": peak.physicalFootprintBytes,
  ]
}

private func jsonData(_ object: [String: Any]) throws -> Data {
  guard JSONSerialization.isValidJSONObject(object) else {
    throw BenchmarkFailure(message: "output-json-object-invalid")
  }
  return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
}

private func validateCandidateBenchmarkEvidence(_ data: Data) throws {
  do {
    let evidence = try JSONDecoder().decode(CandidateBenchmarkEvidence.self, from: data)
    _ = try evidence.validated()
    try require(evidence.schemaVersion == 2, "candidate-evidence-v2-schema-version")
    try require(evidence.cases.count == 36, "candidate-evidence-v2-case-count")
    try require(evidence.cases.allSatisfy { !$0.timing.isCold },
                "candidate-evidence-v2-cold-canonical-case")
    try require(evidence.aggregate.latency.coldP50Milliseconds == nil &&
                  evidence.aggregate.latency.coldP95Milliseconds == nil,
                "candidate-evidence-v2-cold-latency-must-be-noncanonical")
    try require(!evidence.aggregate.lifecycleSummary.reloadSucceeded &&
                  !evidence.aggregate.lifecycleSummary.allSucceeded,
                "candidate-evidence-v2-reload-summary-must-not-claim-success")
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let privacy = object?["privacy"] as? [String: Any]
    try require(privacy?["unexpectedNetworkConnectionCount"] == nil,
                "candidate-evidence-v2-old-privacy-key")
    try require(privacy?["unexpectedConnectionCount"] != nil,
                "candidate-evidence-v2-privacy-key")
    let aggregate = object?["aggregate"] as? [String: Any]
    let summary = aggregate?["lifecycleSummary"] as? [String: Any]
    try require(summary?["reloadOutcome"] == nil && summary?["allMeasuredSucceeded"] == nil,
                "candidate-evidence-v2-old-lifecycle-keys")
    let diagnostics = object?["nonCanonicalDiagnostics"] as? [String: Any]
    try require(diagnostics?["reloadOutcome"] as? String == "notMeasured",
                "candidate-evidence-v2-reload-diagnostics")
    let inputs = object?["inputs"] as? [String: Any]
    try require((inputs?["preparedRoot"] as? String)?.hasSuffix("/installed-artifact-inventory.json") == false,
                "candidate-evidence-v2-prepared-root-trace")
  } catch let failure as BenchmarkFailure {
    throw failure
  } catch let error as CandidateBenchmarkEvidenceError {
    throw BenchmarkFailure(message: "candidate-evidence-v2-invalid:\(error)")
  } catch {
    throw BenchmarkFailure(message: "candidate-evidence-v2-decode-failed")
  }
}

private func publishDirectoryExclusively(stage: URL, destination: URL) throws {
  let result = stage.path.withCString { source in
    destination.path.withCString { target in
      renameatx_np(AT_FDCWD, source, AT_FDCWD, target, UInt32(RENAME_EXCL))
    }
  }
  guard result == 0 else {
    throw BenchmarkFailure(message: "output-publication-race-or-existing-destination")
  }
}

private func writeStageFile(_ data: Data, stage: URL, name: String) throws {
  let target = stage.appendingPathComponent(name)
  try data.write(to: target, options: .atomic)
  try requireRegularFile(target, field: "staged-(name)")
}

private func runSelfTest() throws {
  let duplicate = Data(#"{"schemaVersion":1,"event":"final","requestID":"x","requestID":"y","transcript":"ok"}"#.utf8)
  do {
    _ = try parseHelperEvent(duplicate)
    throw BenchmarkFailure(message: "self-test-duplicate-key-accepted")
  } catch let failure as BenchmarkFailure where failure.message == "self-test-duplicate-key-accepted" {
    throw failure
  } catch {
    print("contract=duplicate-output-keys:pass")
  }

  let unknown = Data(#"{"schemaVersion":1,"event":"final","requestID":"x","transcript":"ok","flood":"x"}"#.utf8)
  do {
    _ = try parseHelperEvent(unknown)
    throw BenchmarkFailure(message: "self-test-unknown-key-accepted")
  } catch let failure as BenchmarkFailure where failure.message == "self-test-unknown-key-accepted" {
    throw failure
  } catch {
    print("contract=unknown-output-keys:pass")
  }

  let partial = Data(#"{"schemaVersion":1,"event":"partial","requestID":"x","transcript":"x"}"#.utf8)
  do {
    _ = try parseHelperEvent(partial)
    throw BenchmarkFailure(message: "self-test-partial-output-accepted")
  } catch let failure as BenchmarkFailure where failure.message == "self-test-partial-output-accepted" {
    throw failure
  } catch {
    print("contract=partial-output-rejected:pass")
  }

  let flood = Data(repeating: 0x20, count: maximumJSONLineBytes + 1)
  do {
    _ = try parseHelperEvent(flood)
    throw BenchmarkFailure(message: "self-test-helper-output-flood-accepted")
  } catch let failure as BenchmarkFailure where failure.message == "self-test-helper-output-flood-accepted" {
    throw failure
  } catch {
    print("contract=helper-output-flood-rejected:pass")
  }

  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("fleck-qwen-contract-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
  defer { try? FileManager.default.removeItem(at: root) }

  let orderingHelper = root.appendingPathComponent("ordering-helper.sh")
  let orderingScript = """
  #!/bin/sh
  while IFS= read line; do
    printf '%s\\n' '{"schemaVersion":1,"event":"ready","requestID":"foreign","runtimeVersion":"runtime","modelRevision":"model"}'
  done
  """
  try Data(orderingScript.utf8).write(to: orderingHelper)
  try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: orderingHelper.path)
  do {
    let session = try HelperSession(executable: orderingHelper, arguments: [], redactedRoots: [])
    do {
      _ = try session.send(try helperRequest(id: "expected", operation: "load"), expectedEvent: "ready", timeout: 1)
      terminateQuietly(session)
      throw BenchmarkFailure(message: "self-test-request-order-accepted")
    } catch let failure as BenchmarkFailure where failure.message.hasPrefix("helper-output-request-order:") {
      terminateQuietly(session)
      print("contract=request-order-rejected:pass")
    } catch {
      terminateQuietly(session)
      throw error
    }
  }

  let stage = root.appendingPathComponent("stage", isDirectory: true)
  try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
  try Data("candidate".utf8).write(to: stage.appendingPathComponent("evidence.json"))
  for (name, kind) in [("file", "file"), ("directory", "directory"), ("symlink", "symlink")] {
    let destination = root.appendingPathComponent(name)
    switch kind {
    case "file": try Data("existing".utf8).write(to: destination)
    case "directory": try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
    default:
      let target = root.appendingPathComponent("symlink-target", isDirectory: true)
      try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
      try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: target)
    }
    do {
      try publishDirectoryExclusively(stage: stage, destination: destination)
      throw BenchmarkFailure(message: "self-test-publication-overwrite:\(kind)")
    } catch let failure as BenchmarkFailure where failure.message == "self-test-publication-overwrite:\(kind)" {
      throw failure
    } catch {
      print("contract=output-race-\(kind)-rejected:pass")
    }
    try? FileManager.default.removeItem(at: stage)
    try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
    try Data("candidate".utf8).write(to: stage.appendingPathComponent("evidence.json"))
  }
}

private func jsonDiagnostics(_ diagnostics: SessionDiagnostics) -> [String: Any] {
  [
    "processIdentifier": diagnostics.processIdentifier,
    "exitStatus": diagnostics.exitStatus,
    "forcedTermination": diagnostics.forcedTermination,
    "stdoutByteCount": diagnostics.stdoutByteCount,
    "stdoutSHA256": sha256Data(diagnostics.stdout),
    "stderrByteCount": diagnostics.stderrByteCount,
    "stderrReceivedByteCount": diagnostics.stderrReceivedByteCount,
    "stderrTruncated": diagnostics.stderrTruncated,
    "stderr": diagnostics.stderr,
  ]
}

private func jsonResourcePeak(_ peak: ResourcePeak) -> [String: Any] {
  [
    "residentBytes": peak.residentBytes,
    "physicalFootprintBytes": peak.physicalFootprintBytes,
  ]
}

private func jsonColdRun(_ run: ColdRun, index: Int) -> [String: Any] {
  let helperNativeDecodeMilliseconds: Any = run.helperNativeDecodeMilliseconds.map { $0 } ?? NSNull()
  return [
    "index": index,
    "caseID": run.benchmarkCase.id,
    "language": run.benchmarkCase.language,
    "sourceClass": run.benchmarkCase.sourceClass,
    "audioSHA256": run.benchmarkCase.audioSHA256,
    "reference": run.benchmarkCase.reference,
    "hypothesis": run.hypothesis,
    "launchToFinalMilliseconds": run.launchToFinalMilliseconds,
    "loadReadyMilliseconds": run.loadReadyMilliseconds,
    "requestToFinalMilliseconds": run.wallRequestToFinalMilliseconds,
    "helperNativeDecodeMilliseconds": helperNativeDecodeMilliseconds,
    "wallRequestToFinalRTF": run.wallRequestToFinalMilliseconds / Double(run.benchmarkCase.audioDurationMilliseconds),
    "peak": jsonResourcePeak(run.peak),
    "diagnostics": jsonDiagnostics(run.diagnostics),
    "lifecycle": ["load": "succeeded", "infer": "succeeded", "unload": "succeeded", "shutdown": "succeeded"],
  ]
}

private func jsonWarmRun(_ run: WarmRun) -> [String: Any] {
  [
    "processIdentifier": run.processIdentifier,
    "loadReadyMilliseconds": run.loadReadyMilliseconds,
    "unloadMilliseconds": run.unloadMilliseconds,
    "shutdownMilliseconds": run.shutdownMilliseconds,
    "peak": jsonResourcePeak(run.peak),
    "caseOrder": run.cases.map { $0.benchmarkCase.id },
    "cases": run.cases.map { result in
      [
        "id": result.benchmarkCase.id,
        "audioSHA256": result.benchmarkCase.audioSHA256,
        "reference": result.benchmarkCase.reference,
        "hypothesis": result.hypothesis,
        "fileDecodeMilliseconds": result.wallRequestToFinalMilliseconds,
        "stopToFinalMilliseconds": result.wallRequestToFinalMilliseconds,
        "fileDecodeRTF": result.wallRequestToFinalMilliseconds / Double(result.benchmarkCase.audioDurationMilliseconds),
        "peak": jsonResourcePeak(result.peak),
        "partials": [],
        "outcome": "final",
      ]
    },
    "diagnostics": jsonDiagnostics(run.diagnostics),
  ]
}

private func jsonTimingSummary(_ values: [Double]) -> [String: Any] {
  [
    "sampleCount": values.count,
    "p50Milliseconds": nearestRank(values, percentile: 0.50) as Any,
    "p95Milliseconds": nearestRank(values, percentile: 0.95) as Any,
  ]
}

private func jsonNonCanonicalDiagnostics(
  warm: WarmRun,
  cold: [ColdRun]
) -> [String: Any] {
  [
    "canonical": false,
    "reason": "supplemental cold-process and helper-native measurements; excluded from CandidateBenchmarkEvidence v2 aggregate",
    "reloadOutcome": "notMeasured",
    "reloadReason": "not-run-by-corpus-benchmark",
    "warmHelperNativeDecodeMilliseconds": warm.cases.compactMap { result in
      result.helperNativeDecodeMilliseconds.map {
        ["caseID": result.benchmarkCase.id, "milliseconds": $0]
      }
    },
    "coldCaseOrder": cold.map { $0.benchmarkCase.id },
    "coldRuns": cold.enumerated().map { jsonColdRun($0.element, index: $0.offset) },
    "freshProcessLaunchToFinalTiming": jsonTimingSummary(cold.map { $0.launchToFinalMilliseconds }),
    "wallRequestToFinalTiming": jsonTimingSummary(cold.map { $0.wallRequestToFinalMilliseconds }),
    "helperNativeDecodeTiming": jsonTimingSummary(cold.compactMap { $0.helperNativeDecodeMilliseconds }),
  ]
}

private func jsonCancellation(_ run: CancellationRun) -> [String: Any] {
  [
    "caseID": run.benchmarkCase.id,
    "language": run.benchmarkCase.language,
    "sourceClass": run.benchmarkCase.sourceClass,
    "audioSHA256": run.benchmarkCase.audioSHA256,
    "markerObserved": run.markerObserved,
    "noLateFinal": run.noLateFinal,
    "outcome": "forced",
    "classification": "process-level-forced-termination-not-cooperative",
    "processIdentifier": run.processIdentifier,
    "deadlineMilliseconds": cancellationDeadline * 1_000,
    "unsupportedProtocolCancellation": [
      "advertisedUnsupported": true,
      "requestWritten": false,
      "processTerminationRequestedAfterPositiveStart": run.markerObserved,
      "status": "not-sent-advertised-unsupported",
      "supportsCancellation": false,
      "supportsCooperativeDecodeCancellation": false,
      "responseEvent": NSNull(),
    ],
    "diagnostics": jsonDiagnostics(run.diagnostics),
  ]
}

private func jsonManifestReceipt(_ receipt: ManifestReceipt) -> [String: Any] {
  [
    "path": receipt.path,
    "sha256": receipt.sha256,
    "byteCount": receipt.byteCount,
    "manifestID": receipt.manifest.manifestID,
    "revision": receipt.manifest.source.revision,
    "license": receipt.manifest.source.license,
    "caseCount": receipt.manifest.cases.count,
  ]
}

private func jsonPreparedReceipt(_ receipt: PreparedReceipt) -> [String: Any] {
  let artifactEntries = receipt.verifiedInventory.files.filter {
    $0.relativePath != receipt.inventoryRelativePath
  }
  return [
    "inventoryPath": receipt.inventoryPath,
    "inventorySHA256": receipt.inventorySHA256,
    "inventoryByteCount": receipt.inventoryByteCount,
    "candidate": receipt.inventory.candidate,
    "status": receipt.inventory.status,
    "releaseAdmitted": receipt.inventory.releaseAdmitted,
    "verifiedEntries": artifactEntries.map {
      [
        "path": $0.relativePath,
        "kind": $0.kind.rawValue,
        "sha256": $0.sha256,
        "byteCount": $0.byteCount,
        "symlinkTarget": ($0.symlinkTarget != nil ? $0.symlinkTarget! : NSNull()) as Any,
      ]
    },
    "declaredRegularFileBytes": receipt.inventory.totalInstalledBytes,
    "verifiedRegularFileBytes": artifactEntries
      .filter { $0.kind == .regularFile }
      .reduce(0) { $0 + $1.byteCount },
    "verifiedInventoryScanBytesIncludingSymlinkTargets": receipt.verifiedInventory.totalInstalledBytes,
  ]
}

private func jsonAudioCase(_ result: WarmCaseResult) -> [String: Any] {
  var object = jsonCase(result)
  object["sourceFile"] = result.benchmarkCase.sourceFile
  object["audioBytes"] = result.benchmarkCase.audioBytes
  object["audioPath"] = result.benchmarkCase.audioURL.path
  return object
}

private func makeModelEvaluationInput(
  metadata: CandidateMetadata,
  hardware: HardwareReceipt,
  results: [WarmCaseResult],
  offline: OfflineObservation
) -> [String: Any] {
  [
    "schemaVersion": 1,
    "modelID": metadata.model.id,
    "revision": metadata.model.convertedRevision,
    "runtime": "\(metadata.runtime.id) \(metadata.runtime.revision)",
    "quantization": "int8",
    "hardware": "\(hardware.hwModel); \(hardware.chip); \(hardware.architecture); \(hardware.osBuild)",
    "unexpectedNetworkConnectionCount": offline.unexpectedConnectionCount,
    "cases": results.map(jsonEvaluationCase),
  ]
}

private func makeRawEvidence(
  runID: String,
  options: BenchmarkOptions,
  metadata: CandidateMetadata,
  prepared: PreparedReceipt,
  helperIdentity: (sha256: String, byteCount: Int64),
  publicReceipt: ManifestReceipt,
  compositeReceipt: ManifestReceipt,
  checkedInReceipt: ManifestReceipt,
  hardware: HardwareReceipt,
  warm: WarmRun,
  cold: [ColdRun],
  cancellation: CancellationRun,
  offline: OfflineObservation
) throws -> [String: Any] {
  let results = warm.cases
  let accuracy = accuracySummary(results)
  let totalAudioMilliseconds = results.reduce(0.0) {
    $0 + Double($1.benchmarkCase.audioDurationMilliseconds)
  }
  let totalWallRequestToFinalMilliseconds = results.reduce(0.0) {
    $0 + $1.wallRequestToFinalMilliseconds
  }
  let warmDecodeRTF = totalAudioMilliseconds > 0
    ? totalWallRequestToFinalMilliseconds / totalAudioMilliseconds
    : 0
  let standardCases = results.map(jsonCase)
  let lifecycle = [
    "load": jsonLifecyclePhase(
      outcome: "succeeded",
      durationMilliseconds: warm.loadReadyMilliseconds,
      peak: warm.peak
    ),
    "infer": jsonLifecyclePhase(
      outcome: "succeeded",
      durationMilliseconds: totalWallRequestToFinalMilliseconds,
      peak: warm.peak
    ),
    "unload": jsonLifecyclePhase(
      outcome: "succeeded",
      durationMilliseconds: warm.unloadMilliseconds,
      peak: warm.peak
    ),
    // The shared v2 contract has no not-measured lifecycle outcome. Keep the
    // canonical phase in a supported state and publish the not-measured truth
    // only in nonCanonicalDiagnostics below.
    "reload": jsonLifecyclePhase(
      outcome: "cancelled",
      durationMilliseconds: 0,
      peak: ResourcePeak(residentBytes: 0, physicalFootprintBytes: 0)
    ),
  ]
  let evidence: [String: Any] = [
    "schemaVersion": 2,
    "runID": runID,
    "claimScope": "candidateBenchmark",
    "evidenceClasses": ["publicHuman", "publicHumanComposite"],
    "candidate": [
      "modelID": metadata.model.id,
      "modelRevision": metadata.model.convertedRevision,
      "runtimeID": metadata.runtime.id,
      "runtimeRevision": metadata.runtime.revision,
      "quantization": "int8",
      "license": metadata.model.license,
    ],
    "artifacts": [
      "archiveReceipt": jsonArchive(metadata.model.archive),
      "artifactReceipt": jsonArchive(metadata.runtime.archive),
      "installedFiles": prepared.inventory.installedFiles.map {
        ["path": $0.path, "sha256": $0.sha256, "byteCount": $0.sizeBytes]
      },
      "totalInstalledBytes": prepared.inventory.totalInstalledBytes,
    ],
    "hardware": [
      "hwModel": hardware.hwModel,
      "chip": hardware.chip,
      "architecture": hardware.architecture,
      "memoryBytes": hardware.memoryBytes,
      "osBuild": hardware.osBuild,
    ],
    "corpus": [
      "manifestID": publicReceipt.manifest.manifestID,
      "revision": publicReceipt.manifest.source.revision,
      "license": publicReceipt.manifest.source.license,
      "checkedInManifest": jsonManifestReceipt(checkedInReceipt),
      "caseBindings": results.map {
        ["caseID": $0.benchmarkCase.id, "audioSHA256": $0.benchmarkCase.audioSHA256]
      },
    ],
    "privacy": [
      "policy": "public-human corpus benchmark is local-only and not retained outside the explicit evidence root",
      "mechanism": "sandbox-exec deny network*; in-process denied socket-connect probe; empty proxy environment; fixed PATH and LC_ALL",
      "enforced": offline.enforced,
      "claimsVerifiedOffline": offline.claimsVerifiedOffline,
      "unexpectedConnectionCount": offline.unexpectedConnectionCount,
      "probe": [
        "performedInBenchmarkProcess": offline.probeAttempted,
        "result": (offline.deniedError != nil ? offline.deniedError! : NSNull()) as Any,
      ],
    ],
    "aggregate": [
      "accuracy": [
        "englishWER": accuracy.englishWER as Any,
        "mandarinCER": accuracy.mandarinCER as Any,
        "mixedMER": accuracy.mixedMER as Any,
        "codeSwitchSpanAccuracy": accuracy.codeSwitchSpanAccuracy as Any,
        "protectedViolationCount": accuracy.protectedViolationCount,
      ],
      "latency": [
        "warmP50Milliseconds": nearestRank(results.map { $0.wallRequestToFinalMilliseconds }, percentile: 0.50) as Any,
        "warmP95Milliseconds": nearestRank(results.map { $0.wallRequestToFinalMilliseconds }, percentile: 0.95) as Any,
      ],
      "fileDecodeRTF": warmDecodeRTF,
      "peakResidentBytes": warm.peak.residentBytes,
      "peakPhysicalFootprintBytes": warm.peak.physicalFootprintBytes,
      "totalStorageBytes": prepared.inventory.totalInstalledBytes,
      "lifecycleSummary": [
        "loadSucceeded": true,
        "inferSucceeded": true,
        "unloadSucceeded": true,
        "reloadSucceeded": false,
        "allSucceeded": false,
      ],
    ],
    "gate": [
      "automatedCandidatePass": false,
      "failureReasons": [
        "candidate benchmark evidence is not an admission decision",
        "native helper exposes batch-final-only output without cooperative cancellation",
        "forced cancellation is process-level termination",
      ],
      "releaseAdmitted": false,
    ],
    "cases": standardCases,
    "lifecycle": lifecycle,
    "truthFlags": [
      "automatedCandidatePass": false,
      "productionIntegrated": false,
      "packagedAppVerified": false,
      "releaseAdmitted": false,
    ],
    "productionIntegrated": false,
    "packagedAppVerified": false,
    "releaseAdmitted": false,
    "inputs": [
      "preparedRoot": options.preparedRoot,
      "helper": options.helper,
      "publicHumanManifest": publicReceipt.path,
      "publicHumanRoot": options.publicRoot,
      "compositeManifest": compositeReceipt.path,
      "compositeRoot": options.compositeRoot,
      "outputRoot": options.outputRoot,
      "preparedRootIsSuppliedDirectory": true,
    ],
    "preparedInventory": jsonPreparedReceipt(prepared),
    "helperIdentity": [
      "path": options.helper,
      "sha256": helperIdentity.sha256,
      "byteCount": helperIdentity.byteCount,
      "buildReceipt": [
        "id": metadata.helperBuild.id,
        "executableFileName": metadata.helperBuild.executableFileName,
        "sha256": metadata.helperBuild.sha256,
        "byteCount": metadata.helperBuild.sizeBytes,
        "modelID": metadata.helperBuild.modelID,
        "modelRevision": metadata.helperBuild.modelRevision,
        "runtimeID": metadata.helperBuild.runtimeID,
        "runtimeRevision": metadata.helperBuild.runtimeRevision,
        "status": metadata.helperBuild.status,
      ],
    ],
    "runtimeCapabilities": [
      "resultSemantics": metadata.capabilities.resultSemantics,
      "supportsTrueStreaming": false,
      "emitsRollingWindowPartials": false,
      "supportsCancellation": false,
      "supportsCooperativeDecodeCancellation": false,
      "supportsContext": false,
      "supportsHotwords": false,
      "finalTranscriptOnly": true,
    ],
    "sourceManifests": [jsonManifestReceipt(publicReceipt), jsonManifestReceipt(compositeReceipt)],
    "caseOrder": results.map { $0.benchmarkCase.id },
    "warmRun": jsonWarmRun(warm),
    "nonCanonicalDiagnostics": jsonNonCanonicalDiagnostics(warm: warm, cold: cold),
    "cancellation": jsonCancellation(cancellation),
    "failureReasons": [
      "unsupported cooperative cancellation protocol",
      "process-level-forced-termination-not-cooperative",
      "productionIntegrated=false",
      "packagedAppVerified=false",
      "releaseAdmitted=false",
    ],
    "modelEvaluationInputFile": "model-evaluation-run-input-v1.json",
  ]
  try require(JSONSerialization.isValidJSONObject(evidence), "raw-evidence-json-invalid")
  return evidence
}

private func makeTranscriptLines(_ results: [WarmCaseResult]) throws -> Data {
  var data = Data()
  for result in results {
    let object: [String: Any] = [
      "id": result.benchmarkCase.id,
      "sourceClass": result.benchmarkCase.sourceClass,
      "language": result.benchmarkCase.language,
      "audioSHA256": result.benchmarkCase.audioSHA256,
      "audioBytes": result.benchmarkCase.audioBytes,
      "audioDurationMilliseconds": result.benchmarkCase.audioDurationMilliseconds,
      "reference": result.benchmarkCase.reference,
      "hypothesis": result.hypothesis,
      "fileDecodeMilliseconds": result.wallRequestToFinalMilliseconds,
      "stopToFinalMilliseconds": result.wallRequestToFinalMilliseconds,
      "fileDecodeRTF": result.wallRequestToFinalMilliseconds / Double(result.benchmarkCase.audioDurationMilliseconds),
      "isCold": false,
      "partials": [],
    ]
    guard JSONSerialization.isValidJSONObject(object) else {
      throw BenchmarkFailure(message: "transcript-json-invalid")
    }
    let line = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    data.append(line)
    data.append(0x0A)
  }
  return data
}

private func jsonDiagnosticsBundle(
  warm: WarmRun,
  cold: [ColdRun],
  cancellation: CancellationRun
) throws -> Data {
  try jsonData([
    "warm": jsonWarmRun(warm),
    "nonCanonicalDiagnostics": jsonNonCanonicalDiagnostics(warm: warm, cold: cold),
    "cancellation": jsonCancellation(cancellation),
  ])
}

private func requireExternalOutputRoot(_ output: URL, repoRoot: URL) throws {
  try require(!isWithin(output.path, root: repoRoot.path), "output-root-must-be-external-to-repository")
  let forbiddenComponent = output.path.split(separator: "/").contains { component in
    component.hasSuffix(".app") || component == ".build" || component == "DerivedData"
  }
  try require(!forbiddenComponent, "output-root-must-not-be-app-or-build-output")
}

private func runBenchmark(_ options: BenchmarkOptions) throws {
  let repoRoot = try requireCanonicalPath(options.repoRoot, field: "repo-root", allowMissing: false)
  try requireDirectory(repoRoot, field: "repo-root")
  let preparedRoot = try requireCanonicalPath(options.preparedRoot, field: "prepared-root", allowMissing: false)
  let helper = try requireCanonicalPath(options.helper, field: "helper", allowMissing: false)
  try requireRegularFile(helper, field: "helper", executable: true)
  let publicManifest = try requireCanonicalPath(options.publicManifest, field: "public-human-manifest", allowMissing: false)
  let publicRoot = try requireCanonicalPath(options.publicRoot, field: "public-human-root", allowMissing: false)
  try requireDirectory(publicRoot, field: "public-human-root")
  let compositeManifest = try requireCanonicalPath(options.compositeManifest, field: "composite-manifest", allowMissing: false)
  let compositeRoot = try requireCanonicalPath(options.compositeRoot, field: "composite-root", allowMissing: false)
  try requireDirectory(compositeRoot, field: "composite-root")
  let metadataURL = try requireCanonicalPath(options.metadata, field: "metadata", allowMissing: false)
  try requireRegularFile(metadataURL, field: "metadata")
  let output = try requireCanonicalPath(options.outputRoot, field: "output-root", allowMissing: true)
  try requireExternalOutputRoot(output, repoRoot: repoRoot)
  try require(!FileManager.default.fileExists(atPath: output.path), "output-root-must-be-new")
  let outputParent = output.deletingLastPathComponent()
  try requireDirectory(outputParent, field: "output-root-parent")

  let metadata: CandidateMetadata = try readJSON(CandidateMetadata.self, from: metadataURL)
  try validateMetadata(metadata, allowContractFixture: options.contractTest)
  let prepared = try verifyPreparedInventory(root: preparedRoot, metadata: metadata)
  let helperIdentity = try sha256File(helper)
  try require(helper.lastPathComponent == metadata.helperBuild.executableFileName,
              "helper-build-executable-name-mismatch")
  try require(helperIdentity.byteCount == metadata.helperBuild.sizeBytes &&
                helperIdentity.sha256 == metadata.helperBuild.sha256,
              "helper-build-receipt-mismatch")
  let offline = try runOfflineNetworkProbe(contractTest: options.contractTest)
  let publicReceipt = try readManifest(publicManifest)
  let compositeReceipt = try readManifest(compositeManifest)
  let checkedInReceipt: ManifestReceipt
  if options.contractTest {
    checkedInReceipt = publicReceipt
  } else {
    let checkedInURL = repoRoot.appendingPathComponent(
      "Tools/LocalDictationCandidateAdapters/Benchmarks/Corpus/manifest-v1.json"
    )
    checkedInReceipt = try readManifest(checkedInURL)
    try validateCheckedInManifestIdentity(
      publicReceipt: publicReceipt,
      compositeReceipt: compositeReceipt,
      checkedInReceipt: checkedInReceipt
    )
  }
  let cases = try selectCases(
    publicReceipt: publicReceipt,
    publicRoot: publicRoot,
    compositeReceipt: compositeReceipt,
    compositeRoot: compositeRoot
  )
  try require(cases.count == 36, "benchmark-case-count")
  let hardware = try hardwareReceipt()
  let warm = try runWarm(
    preparedRoot: preparedRoot,
    helper: helper,
    helperIdentity: helperIdentity,
    cases: cases,
    metadata: metadata,
    redactedRoots: [preparedRoot, publicRoot, compositeRoot, repoRoot]
  )
  try require(warm.cases.map { $0.benchmarkCase.id } == cases.map(\.id), "warm-case-order")

  let coldCases = [cases[0], cases[1], cases[12], cases[13], cases[24]]
  let cold = try coldCases.enumerated().map { index, benchmarkCase in
    try runCold(
      preparedRoot: preparedRoot,
      helper: helper,
      helperIdentity: helperIdentity,
      benchmarkCase: benchmarkCase,
      metadata: metadata,
      index: index,
      redactedRoots: [preparedRoot, publicRoot, compositeRoot, repoRoot]
    )
  }
  let cancellation = try runCancellation(
    preparedRoot: preparedRoot,
    helper: helper,
    helperIdentity: helperIdentity,
    benchmarkCase: cases[24],
    metadata: metadata,
    redactedRoots: [preparedRoot, publicRoot, compositeRoot, repoRoot]
  )
  let runID = UUID().uuidString
  let evidence = try makeRawEvidence(
    runID: runID,
    options: options,
    metadata: metadata,
    prepared: prepared,
    helperIdentity: helperIdentity,
    publicReceipt: publicReceipt,
    compositeReceipt: compositeReceipt,
    checkedInReceipt: checkedInReceipt,
    hardware: hardware,
    warm: warm,
    cold: cold,
    cancellation: cancellation,
    offline: offline
  )
  let evaluationInput = makeModelEvaluationInput(
    metadata: metadata,
    hardware: hardware,
    results: warm.cases,
    offline: offline
  )
  let diagnostics = try jsonDiagnosticsBundle(warm: warm, cold: cold, cancellation: cancellation)
  let evidenceData = try jsonData(evidence)
  try validateCandidateBenchmarkEvidence(evidenceData)
  let stage = outputParent.appendingPathComponent(".qwen-native-corpus-\(runID)", isDirectory: true)
  try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
  var published = false
  defer {
    if !published { try? FileManager.default.removeItem(at: stage) }
  }
  try writeStageFile(evidenceData, stage: stage, name: "candidate-benchmark-evidence-v2.json")
  try writeStageFile(try jsonData(evaluationInput), stage: stage, name: "model-evaluation-run-input-v1.json")
  try writeStageFile(try makeTranscriptLines(warm.cases), stage: stage, name: "transcripts.jsonl")
  try writeStageFile(diagnostics, stage: stage, name: "helper-diagnostics.json")
  try publishDirectoryExclusively(stage: stage, destination: output)
  published = true
  print("outputRoot=\(output.path)")
  print("cases=36 warm=1 cold=5 cancellation=forced")
  print("offlineEnforced=\(offline.enforced) unexpectedConnectionCount=\(offline.unexpectedConnectionCount)")
  print("automatedCandidatePass=false productionIntegrated=false packagedAppVerified=false releaseAdmitted=false")
}

@main
private struct QwenNativeCorpusBenchmarkMain {
  static func main() {
    do {
      if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--validate-evidence" {
        let evidenceURL = try requireCanonicalPath(
          CommandLine.arguments[2],
          field: "candidate-evidence",
          allowMissing: false
        )
        try requireRegularFile(evidenceURL, field: "candidate-evidence")
        try validateCandidateBenchmarkEvidence(try Data(contentsOf: evidenceURL, options: .mappedIfSafe))
        print("candidate-benchmark-evidence-v2:valid")
        return
      }
      let options = try BenchmarkOptions(arguments: CommandLine.arguments)
      if options.selfTest {
        try runSelfTest()
      } else {
        try runBenchmark(options)
      }
    } catch let failure as BenchmarkFailure {
      FileHandle.standardError.write(Data("qwen-native-corpus-benchmark:fail:\(failure.message)\n".utf8))
      Darwin.exit(2)
    } catch {
      FileHandle.standardError.write(Data("qwen-native-corpus-benchmark:fail:unexpected-error\n".utf8))
      Darwin.exit(2)
    }
  }
}
