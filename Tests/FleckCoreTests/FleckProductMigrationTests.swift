import Foundation
import Testing

@testable import FleckCore

@Test func migratesCompleteLegacyWorkspaceAndWritesReceipt() throws {
  let parent = migrationTestDirectory()
  defer { try? FileManager.default.removeItem(at: parent) }
  let legacy = legacyMigrationURL(in: parent)
  let canonical = canonicalMigrationURL(in: parent)
  let migratedAt = Date(timeIntervalSince1970: 1_800_000_000)

  try createLegacyMigrationFixture(at: legacy)
  let expectedFiles = try migrationFileContents(at: legacy)

  let outcome = FleckProductMigration(
    applicationSupportParent: parent,
    now: { migratedAt }
  ).prepare()

  #expect(outcome == .migrated(canonical))
  #expect(!FileManager.default.fileExists(atPath: legacy.path))
  for (relativePath, expectedData) in expectedFiles {
    #expect(
      try Data(contentsOf: canonical.appendingPathComponent(relativePath))
        == expectedData
    )
  }
  let receipt = try JSONDecoder.fleckMigration.decode(
    FleckMigrationReceipt.self,
    from: Data(
      contentsOf: canonical.appendingPathComponent(
        FleckProductPaths.migrationReceiptName
      )
    )
  )
  #expect(receipt.schemaVersion == 1)
  #expect(receipt.migratedAt == migratedAt)
  #expect(receipt.legacyPath == legacy.path)
  #expect(receipt.canonicalPath == canonical.path)
}

@Test func repeatedMigrationUsesCanonicalRootWithoutRewritingIt() throws {
  let parent = migrationTestDirectory()
  defer { try? FileManager.default.removeItem(at: parent) }
  let canonical = canonicalMigrationURL(in: parent)
  try createLegacyMigrationFixture(at: legacyMigrationURL(in: parent))
  let migration = FleckProductMigration(
    applicationSupportParent: parent,
    now: { Date(timeIntervalSince1970: 1_800_000_000) }
  )
  #expect(migration.prepare() == .migrated(canonical))
  let expectedFiles = try migrationFileContents(at: canonical)

  #expect(migration.prepare() == .alreadyMigrated(canonical))
  #expect(try migrationFileContents(at: canonical) == expectedFiles)
}

@Test func canonicalOnlyWorkspaceRunsWithoutInventingAMigrationReceipt() throws {
  let parent = migrationTestDirectory()
  defer { try? FileManager.default.removeItem(at: parent) }
  let canonical = canonicalMigrationURL(in: parent)
  try createLegacyMigrationFixture(at: canonical)

  #expect(
    FleckProductMigration(applicationSupportParent: parent).prepare()
      == .alreadyMigrated(canonical)
  )
  #expect(
    !FileManager.default.fileExists(
      atPath: canonical.appendingPathComponent(
        FleckProductPaths.migrationReceiptName
      ).path
    )
  )
}

@Test func compatibilityOnlyLegacyRootIsNotAWorkspaceConflict() throws {
  let parent = migrationTestDirectory()
  defer { try? FileManager.default.removeItem(at: parent) }
  let legacy = legacyMigrationURL(in: parent)
  let canonical = canonicalMigrationURL(in: parent)
  try createLegacyMigrationFixture(at: canonical)
  let bridge = legacy.appendingPathComponent("AgentBridge", isDirectory: true)
  try FileManager.default.createDirectory(
    at: bridge.appendingPathComponent("bin", isDirectory: true),
    withIntermediateDirectories: true
  )
  try Data("{}".utf8).write(
    to: bridge.appendingPathComponent("fleck-compatibility-v1.json")
  )
  try Data("#!/bin/sh".utf8).write(
    to: bridge.appendingPathComponent("bin/motes")
  )

  #expect(
    FleckProductMigration(applicationSupportParent: parent).prepare()
      == .alreadyMigrated(canonical)
  )
  #expect(FileManager.default.fileExists(atPath: legacy.path))
}

@Test func twoWorkspaceRootsFailClosedAndPreserveBoth() throws {
  let parent = migrationTestDirectory()
  defer { try? FileManager.default.removeItem(at: parent) }
  let legacy = legacyMigrationURL(in: parent)
  let canonical = canonicalMigrationURL(in: parent)
  try createLegacyMigrationFixture(at: legacy)
  try createLegacyMigrationFixture(at: canonical)

  let outcome = FleckProductMigration(applicationSupportParent: parent).prepare()

  #expect(
    outcome
      == .failed(
        canonical,
        .conflictingWorkspaces(
          legacyPath: legacy.path,
          canonicalPath: canonical.path
        )
      )
  )
  #expect(FileManager.default.fileExists(atPath: legacy.path))
  #expect(FileManager.default.fileExists(atPath: canonical.path))
}

@Test func symlinkedLegacyRootFailsClosed() throws {
  let parent = migrationTestDirectory()
  defer { try? FileManager.default.removeItem(at: parent) }
  let actual = parent.appendingPathComponent("Actual", isDirectory: true)
  let legacy = legacyMigrationURL(in: parent)
  let canonical = canonicalMigrationURL(in: parent)
  try createLegacyMigrationFixture(at: actual)
  try FileManager.default.createSymbolicLink(at: legacy, withDestinationURL: actual)

  #expect(
    FleckProductMigration(applicationSupportParent: parent).prepare()
      == .failed(canonical, .unsafeLegacyRoot)
  )
  #expect(FileManager.default.fileExists(atPath: legacy.path))
  #expect(FileManager.default.fileExists(atPath: actual.path))
}

@Test func invalidMovedWorkspaceRollsBackToLegacyPath() throws {
  let parent = migrationTestDirectory()
  defer { try? FileManager.default.removeItem(at: parent) }
  let legacy = legacyMigrationURL(in: parent)
  let canonical = canonicalMigrationURL(in: parent)
  try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
  try Data("invalid".utf8).write(
    to: legacy.appendingPathComponent("workspace.json")
  )

  #expect(
    FleckProductMigration(applicationSupportParent: parent).prepare()
      == .failed(canonical, .invalidMigratedWorkspace)
  )
  #expect(FileManager.default.fileExists(atPath: legacy.path))
  #expect(!FileManager.default.fileExists(atPath: canonical.path))
}

@Test func failedRollbackReportsBothPreservedPaths() throws {
  let parent = migrationTestDirectory()
  defer { try? FileManager.default.removeItem(at: parent) }
  let legacy = legacyMigrationURL(in: parent)
  let canonical = canonicalMigrationURL(in: parent)
  try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
  try Data("invalid".utf8).write(
    to: legacy.appendingPathComponent("workspace.json")
  )
  let fileManager = RollbackFailingFileManager(
    rollbackSource: canonical,
    rollbackDestination: legacy
  )

  #expect(
    FleckProductMigration(
      applicationSupportParent: parent,
      fileManager: fileManager
    ).prepare()
      == .failed(
        canonical,
        .rollbackFailed(
          legacyPath: legacy.path,
          canonicalPath: canonical.path
        )
      )
  )
  #expect(!FileManager.default.fileExists(atPath: legacy.path))
  #expect(FileManager.default.fileExists(atPath: canonical.path))
}

private final class RollbackFailingFileManager: FileManager, @unchecked Sendable {
  private let rollbackSource: URL
  private let rollbackDestination: URL

  init(rollbackSource: URL, rollbackDestination: URL) {
    self.rollbackSource = rollbackSource
    self.rollbackDestination = rollbackDestination
    super.init()
  }

  override func moveItem(at srcURL: URL, to dstURL: URL) throws {
    if srcURL == rollbackSource && dstURL == rollbackDestination {
      throw CocoaError(.fileWriteUnknown)
    }
    try super.moveItem(at: srcURL, to: dstURL)
  }
}

private func migrationTestDirectory() -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent(
    "FleckProductMigrationTests-\(UUID())",
    isDirectory: true
  )
}

private func legacyMigrationURL(in parent: URL) -> URL {
  parent.appendingPathComponent(
    FleckProductPaths.legacyDirectoryName,
    isDirectory: true
  )
}

private func canonicalMigrationURL(in parent: URL) -> URL {
  parent.appendingPathComponent(
    FleckProductPaths.canonicalDirectoryName,
    isDirectory: true
  )
}

private func createLegacyMigrationFixture(at root: URL) throws {
  let note = Note(
    title: "Migrated note",
    body: "Keep every byte",
    richTextRTF: Data("{\\rtf1 Keep every byte}".utf8),
    agentAccess: true,
    revision: 3
  )
  _ = try LocalStoreSnapshotWriter(rootURL: root).save(
    workspace: Workspace(notes: [note], selectedNoteID: note.id),
    preferences: AppPreferences(accentHex: "#123456"),
    generation: 7
  )
  let representativeFiles: [String: Data] = [
    "Trash/example/body.md": Data("trashed".utf8),
    "DictationHistory/history.json": Data("dictation".utf8),
    "Models/model.bin": Data([0, 1, 2, 3]),
    "AgentIntegrations/profiles.json": Data("profiles".utf8),
    "AgentActivity/activity.json": Data("activity".utf8),
  ]
  for (relativePath, data) in representativeFiles {
    let destination = root.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(
      at: destination.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try data.write(to: destination)
  }
}

private func migrationFileContents(at root: URL) throws -> [String: Data] {
  let keys: Set<URLResourceKey> = [.isRegularFileKey]
  let rootComponents = root.resolvingSymlinksInPath().pathComponents
  guard
    let enumerator = FileManager.default.enumerator(
      at: root,
      includingPropertiesForKeys: Array(keys)
    )
  else { return [:] }
  var contents: [String: Data] = [:]
  for case let fileURL as URL in enumerator {
    guard try fileURL.resourceValues(forKeys: keys).isRegularFile == true else {
      continue
    }
    let relativePath = fileURL.resolvingSymlinksInPath().pathComponents
      .dropFirst(rootComponents.count)
      .joined(separator: "/")
    contents[relativePath] = try Data(contentsOf: fileURL)
  }
  return contents
}

private extension JSONDecoder {
  static var fleckMigration: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
