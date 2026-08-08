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

@Test func FleckProductMigrationFolderBearingSnapshotRoundTrip() throws {
  let parent = migrationTestDirectory()
  defer { try? FileManager.default.removeItem(at: parent) }
  let legacy = legacyMigrationURL(in: parent)
  let canonical = canonicalMigrationURL(in: parent)
  let folder = try Folder(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000301")!,
    name: "Migrated"
  )
  let date = Date(timeIntervalSince1970: 1_700_000_000)
  let note = Note(
    title: "Foldered",
    body: "Keep folder metadata",
    createdAt: date,
    modifiedAt: date,
    agentAccess: true,
    revision: 4,
    folderID: folder.id
  )
  let workspace = Workspace(
    notes: [note],
    selectedNoteID: note.id,
    folders: [folder]
  )
  _ = try LocalStoreSnapshotWriter(rootURL: legacy).save(
    workspace: workspace,
    preferences: AppPreferences(accentHex: "#123456"),
    generation: 7
  )

  #expect(
    FleckProductMigration(applicationSupportParent: parent).prepare()
      == .migrated(canonical)
  )
  let migrated = try LocalStoreSnapshotWriter(rootURL: canonical).loadSnapshot()
  #expect(migrated.workspace == workspace)
  #expect(migrated.workspace.folders == [folder])
  #expect(migrated.workspace.notes.first?.folderID == folder.id)
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
    to: bridge.appendingPathComponent("bin/motes") // Legacy launcher fixture.
  )

  #expect(
    FleckProductMigration(applicationSupportParent: parent).prepare()
      == .alreadyMigrated(canonical)
  )
  #expect(FileManager.default.fileExists(atPath: legacy.path))
}

@Test func emptyCanonicalAgentScaffoldingDoesNotBlockLegacyMigration() throws {
  let parent = migrationTestDirectory()
  defer { try? FileManager.default.removeItem(at: parent) }
  let legacy = legacyMigrationURL(in: parent)
  let canonical = canonicalMigrationURL(in: parent)
  try createLegacyMigrationFixture(at: legacy)
  for directory in ["Prepared", "Records", "Tombstones"] {
    try FileManager.default.createDirectory(
      at: canonical.appendingPathComponent("AgentActivity/\(directory)"),
      withIntermediateDirectories: true
    )
  }

  #expect(
    FleckProductMigration(applicationSupportParent: parent).prepare()
      == .migrated(canonical)
  )
  #expect(!FileManager.default.fileExists(atPath: legacy.path))
  #expect(
    FileManager.default.fileExists(
      atPath: canonical.appendingPathComponent("workspace.json").path
    )
  )
}

@Test func unknownCanonicalScaffoldingIsNeverRemoved() throws {
  let parent = migrationTestDirectory()
  defer { try? FileManager.default.removeItem(at: parent) }
  let legacy = legacyMigrationURL(in: parent)
  let canonical = canonicalMigrationURL(in: parent)
  try createLegacyMigrationFixture(at: legacy)
  try FileManager.default.createDirectory(
    at: canonical.appendingPathComponent("Unknown"),
    withIntermediateDirectories: true
  )

  #expect(
    FleckProductMigration(applicationSupportParent: parent).prepare()
      == .failed(canonical, .filesystemFailure)
  )
  #expect(FileManager.default.fileExists(atPath: legacy.path))
  #expect(
    FileManager.default.fileExists(
      atPath: canonical.appendingPathComponent("Unknown").path
    )
  )
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

@Test func receiptBackedRecreatedEmptyLegacyWorkspaceUsesCanonicalRoot() throws {
  let parent = migrationTestDirectory()
  defer { try? FileManager.default.removeItem(at: parent) }
  let legacy = legacyMigrationURL(in: parent)
  let canonical = canonicalMigrationURL(in: parent)
  try createLegacyMigrationFixture(at: canonical)
  try writeMigrationReceipt(legacy: legacy, canonical: canonical)
  try createEmptyLegacyMigrationFixture(at: legacy)
  let expectedLegacy = try migrationFileContents(at: legacy)
  let expectedCanonical = try migrationFileContents(at: canonical)

  #expect(
    FleckProductMigration(applicationSupportParent: parent).prepare()
      == .alreadyMigrated(canonical)
  )
  #expect(try migrationFileContents(at: legacy) == expectedLegacy)
  #expect(try migrationFileContents(at: canonical) == expectedCanonical)
}

@Test func recreatedEmptyLegacyWorkspaceIgnoresAgentAccessBookkeeping() throws {
  let parent = migrationTestDirectory()
  defer { try? FileManager.default.removeItem(at: parent) }
  let legacy = legacyMigrationURL(in: parent)
  let canonical = canonicalMigrationURL(in: parent)
  try createLegacyMigrationFixture(at: canonical)
  try writeMigrationReceipt(legacy: legacy, canonical: canonical)
  let note = Note(agentAccess: true, revision: 1)
  _ = try LocalStoreSnapshotWriter(rootURL: legacy).save(
    workspace: Workspace(notes: [note], selectedNoteID: note.id),
    preferences: .init(),
    generation: 3
  )
  try createEmptyLegacyCompatibilityDirectories(at: legacy)
  let expectedLegacy = try migrationFileContents(at: legacy)
  let expectedCanonical = try migrationFileContents(at: canonical)

  #expect(
    FleckProductMigration(applicationSupportParent: parent).prepare()
      == .alreadyMigrated(canonical)
  )
  #expect(try migrationFileContents(at: legacy) == expectedLegacy)
  #expect(try migrationFileContents(at: canonical) == expectedCanonical)
}

@Test func unreadableGeneratedLegacyDirectoryFailsClosed() throws {
  let parent = migrationTestDirectory()
  defer { try? FileManager.default.removeItem(at: parent) }
  let legacy = legacyMigrationURL(in: parent)
  let canonical = canonicalMigrationURL(in: parent)
  try createLegacyMigrationFixture(at: canonical)
  try writeMigrationReceipt(legacy: legacy, canonical: canonical)
  try createEmptyLegacyMigrationFixture(at: legacy)
  let expectedLegacy = try migrationFileContents(at: legacy)
  let expectedCanonical = try migrationFileContents(at: canonical)
  let fileManager = DirectoryReadFailingFileManager(
    blockedDirectory: legacy.appendingPathComponent(
      "AgentBridge",
      isDirectory: true
    )
  )

  #expect(
    FleckProductMigration(
      applicationSupportParent: parent,
      fileManager: fileManager
    ).prepare()
      == .failed(
        canonical,
        .conflictingWorkspaces(
          legacyPath: legacy.path,
          canonicalPath: canonical.path
        )
      )
  )
  #expect(try migrationFileContents(at: legacy) == expectedLegacy)
  #expect(try migrationFileContents(at: canonical) == expectedCanonical)
}

@Test func recreatedEmptyLegacyWorkspaceWithoutReceiptFailsClosed() throws {
  try expectRecreatedLegacyConflict(.missingReceipt)
}

@Test(arguments: InvalidRecreatedLegacyWorkspace.allCases)
func recreatedLegacyWorkspaceFailsClosedWhenItIsNotExactlyDisposable(
  _ invalid: InvalidRecreatedLegacyWorkspace
) throws {
  try expectRecreatedLegacyConflict(invalid)
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

@Test func folderBearingMigrationValidationFailurePreservesLegacySnapshot() throws {
  let parent = migrationTestDirectory()
  defer { try? FileManager.default.removeItem(at: parent) }
  let legacy = legacyMigrationURL(in: parent)
  let canonical = canonicalMigrationURL(in: parent)
  let folder = try Folder(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000321")!,
    name: "Legacy Folder"
  )
  let note = Note(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000322")!,
    title: "Foldered",
    body: "Original",
    folderID: folder.id
  )
  _ = try LocalStoreSnapshotWriter(rootURL: legacy).save(
    workspace: Workspace(
      notes: [note],
      selectedNoteID: note.id,
      folders: [folder]
    ),
    preferences: AppPreferences(fontFamily: "Menlo"),
    generation: 1
  )
  try Data("corrupt body".utf8).write(
    to: legacy.appendingPathComponent("\(note.id.uuidString.lowercased()).md")
  )
  let expectedLegacy = try migrationFileContents(at: legacy)

  #expect(
    FleckProductMigration(applicationSupportParent: parent).prepare()
      == .failed(canonical, .invalidMigratedWorkspace)
  )
  #expect(try migrationFileContents(at: legacy) == expectedLegacy)
  #expect(!FileManager.default.fileExists(atPath: canonical.path))
  let manifest = try #require(
    try JSONSerialization.jsonObject(
      with: Data(contentsOf: legacy.appendingPathComponent("workspace.json"))
    ) as? [String: Any]
  )
  #expect((manifest["folders"] as? [[String: Any]])?.count == 1)
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

enum InvalidRecreatedLegacyWorkspace: CaseIterable, Sendable {
  case missingReceipt
  case wrongReceiptLegacyPath
  case wrongReceiptCanonicalPath
  case wrongReceiptSchema
  case nonemptyBody
  case richText
  case bomOnlyBody
  case malformedPreferences
  case malformedManifest
  case wrongSelectedNote
  case renamedNote
  case pinnedNote
  case coloredNote
  case secondNote
  case trashDirectory
  case recoveryDirectory
  case agentActivityFile
  case agentBridgeFile
  case unknownFile
  case nestedDirectory
  case nestedSymlink

  static var allCases: [Self] {
    [
      .wrongReceiptLegacyPath,
      .wrongReceiptCanonicalPath,
      .wrongReceiptSchema,
      .nonemptyBody,
      .richText,
      .bomOnlyBody,
      .malformedPreferences,
      .malformedManifest,
      .wrongSelectedNote,
      .renamedNote,
      .pinnedNote,
      .coloredNote,
      .secondNote,
      .trashDirectory,
      .recoveryDirectory,
      .agentActivityFile,
      .agentBridgeFile,
      .unknownFile,
      .nestedDirectory,
      .nestedSymlink,
    ]
  }
}

private func expectRecreatedLegacyConflict(
  _ invalid: InvalidRecreatedLegacyWorkspace
) throws {
  let parent = migrationTestDirectory()
  defer { try? FileManager.default.removeItem(at: parent) }
  let legacy = legacyMigrationURL(in: parent)
  let canonical = canonicalMigrationURL(in: parent)
  try createLegacyMigrationFixture(at: canonical)
  if invalid != .missingReceipt {
    try writeMigrationReceipt(
      legacy: legacy,
      canonical: canonical,
      schemaVersion: invalid == .wrongReceiptSchema ? 2 : 1,
      legacyPath:
        invalid == .wrongReceiptLegacyPath
        ? parent.appendingPathComponent("WrongLegacy").path
        : legacy.path,
      canonicalPath:
        invalid == .wrongReceiptCanonicalPath
        ? parent.appendingPathComponent("WrongCanonical").path
        : canonical.path
    )
  }

  var note = Note()
  switch invalid {
  case .nonemptyBody:
    note.body = "Meaningful"
  case .richText:
    note.richTextRTF = Data("{\\rtf1 Meaningful}".utf8)
  case .renamedNote:
    note.title = "Named"
  case .pinnedNote:
    note.isPinned = true
  case .coloredNote:
    note.tabColorHex = "#7257F5"
  default:
    break
  }
  let notes = invalid == .secondNote ? [note, Note()] : [note]
  _ = try LocalStoreSnapshotWriter(rootURL: legacy).save(
    workspace: Workspace(notes: notes, selectedNoteID: note.id),
    preferences: .init(),
    generation: 1
  )
  try createEmptyLegacyCompatibilityDirectories(at: legacy)

  switch invalid {
  case .bomOnlyBody:
    try removeSnapshotIntegrity(at: legacy)
    try Data([0xEF, 0xBB, 0xBF]).write(
      to: legacy.appendingPathComponent(
        "\(note.id.uuidString.lowercased()).md"
      )
    )
  case .malformedPreferences:
    try removeSnapshotIntegrity(at: legacy)
    try Data("not-json".utf8).write(
      to: legacy.appendingPathComponent("preferences.json")
    )
  case .malformedManifest:
    try Data("not-json".utf8).write(
      to: legacy.appendingPathComponent("workspace.json")
    )
  case .wrongSelectedNote:
    try updateManifest(at: legacy) {
      $0["selectedNoteID"] = UUID().uuidString
    }
  case .trashDirectory:
    try FileManager.default.createDirectory(
      at: legacy.appendingPathComponent("Trash"),
      withIntermediateDirectories: false
    )
  case .recoveryDirectory:
    try FileManager.default.createDirectory(
      at: legacy.appendingPathComponent("Recovery"),
      withIntermediateDirectories: false
    )
  case .agentActivityFile:
    try Data("agent activity".utf8).write(
      to: legacy.appendingPathComponent("AgentActivity/Records/change.json")
    )
  case .agentBridgeFile:
    try Data("helper".utf8).write(
      to: legacy.appendingPathComponent("AgentBridge/fleck")
    )
  case .unknownFile:
    try Data("unknown".utf8).write(
      to: legacy.appendingPathComponent(".unknown")
    )
  case .nestedDirectory:
    try FileManager.default.createDirectory(
      at: legacy.appendingPathComponent("Unknown/Nested"),
      withIntermediateDirectories: true
    )
  case .nestedSymlink:
    try FileManager.default.createSymbolicLink(
      at: legacy.appendingPathComponent("linked"),
      withDestinationURL: canonical
    )
  default:
    break
  }

  let expectedLegacy = try migrationFileContents(at: legacy)
  let expectedCanonical = try migrationFileContents(at: canonical)
  #expect(
    FleckProductMigration(applicationSupportParent: parent).prepare()
      == .failed(
        canonical,
        .conflictingWorkspaces(
          legacyPath: legacy.path,
          canonicalPath: canonical.path
        )
      )
  )
  #expect(try migrationFileContents(at: legacy) == expectedLegacy)
  #expect(try migrationFileContents(at: canonical) == expectedCanonical)
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

private final class DirectoryReadFailingFileManager:
  FileManager,
  @unchecked Sendable
{
  private let blockedDirectory: URL

  init(blockedDirectory: URL) {
    self.blockedDirectory = blockedDirectory.standardizedFileURL
    super.init()
  }

  override func contentsOfDirectory(
    at url: URL,
    includingPropertiesForKeys keys: [URLResourceKey]?,
    options mask: DirectoryEnumerationOptions = []
  ) throws -> [URL] {
    if url.standardizedFileURL == blockedDirectory {
      throw CocoaError(.fileReadNoPermission)
    }
    return try super.contentsOfDirectory(
      at: url,
      includingPropertiesForKeys: keys,
      options: mask
    )
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

private func createEmptyLegacyMigrationFixture(at root: URL) throws {
  let note = Note()
  _ = try LocalStoreSnapshotWriter(rootURL: root).save(
    workspace: Workspace(notes: [note], selectedNoteID: note.id),
    preferences: .init(),
    generation: 1
  )
  try createEmptyLegacyCompatibilityDirectories(at: root)
}

private func createEmptyLegacyCompatibilityDirectories(at root: URL) throws {
  for relativePath in [
    "AgentActivity/Prepared",
    "AgentActivity/Records",
    "AgentActivity/Tombstones",
    "AgentBridge",
  ] {
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent(relativePath),
      withIntermediateDirectories: true
    )
  }
}

private func writeMigrationReceipt(
  legacy: URL,
  canonical: URL,
  schemaVersion: Int = 1,
  legacyPath: String? = nil,
  canonicalPath: String? = nil
) throws {
  let receipt = FleckMigrationReceipt(
    schemaVersion: schemaVersion,
    migratedAt: Date(timeIntervalSince1970: 1_800_000_000),
    legacyPath: legacyPath ?? legacy.path,
    canonicalPath: canonicalPath ?? canonical.path
  )
  let encoder = JSONEncoder()
  encoder.dateEncodingStrategy = .iso8601
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  try encoder.encode(receipt).write(
    to: canonical.appendingPathComponent(
      FleckProductPaths.migrationReceiptName
    ),
    options: .atomic
  )
}

private func removeSnapshotIntegrity(at root: URL) throws {
  try updateManifest(at: root) { object in
    for key in [
      "snapshotIntegrityVersion",
      "markdownSHA256",
      "rtfSHA256",
      "preferencesSHA256",
    ] {
      object.removeValue(forKey: key)
    }
  }
}

private func updateManifest(
  at root: URL,
  mutate: (inout [String: Any]) -> Void
) throws {
  let manifestURL = root.appendingPathComponent("workspace.json")
  let data = try Data(contentsOf: manifestURL)
  var object = try #require(
    JSONSerialization.jsonObject(with: data) as? [String: Any]
  )
  mutate(&object)
  try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    .write(to: manifestURL, options: .atomic)
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

extension JSONDecoder {
  fileprivate static var fleckMigration: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
