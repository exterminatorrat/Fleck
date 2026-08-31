import Foundation
import Testing
import CryptoKit

@testable import FleckApp
import FleckCore

@Suite(.serialized)
struct LocalWritingCorpusStoreTests {
  @Test
  func createsDeterministicEmptyPrivateWorkspace() async throws {
    let fixture = try CorpusStoreFixture()
    defer { fixture.cleanup() }
    let corpusID = UUID(uuidString: "00000000-0000-0000-0000-0000000000a1")!
    let store = LocalWritingCorpusStore(
      clock: { 1_725_000_000_123 },
      additionalForbiddenRoots: { [] }
    )

    #expect(fixture.selectedContainer.isFileURL)
    #expect(fixture.selectedContainer.path.hasPrefix("/"))
    #expect(fixture.selectedContainer.path == fixture.selectedContainer.standardizedFileURL.path)
    #expect(!fixture.selectedContainer.pathComponents.contains(".."))
    #expect(!fixture.selectedContainer.pathComponents.contains("."))

    let workspace = try await store.create(
      in: fixture.selectedContainer,
      corpusID: corpusID
    )

    #expect(workspace.corpusID == corpusID)
    #expect(workspace.workspaceURL == fixture.selectedContainer
      .appendingPathComponent("Fleck Local Writing Corpus", isDirectory: true)
      .appendingPathComponent(corpusID.uuidString.lowercased(), isDirectory: true))
    #expect(workspace.manifest.corpusID == corpusID)
    #expect(workspace.manifest.payload.language == "en-US")
    #expect(workspace.manifest.payload.claimScope == .ownerPrivateBeta)
    #expect(workspace.manifest.payload.createdAtUnixMilliseconds == 1_725_000_000_123)
    #expect(workspace.manifest.payload.controlledWorkspaces.isEmpty)
    #expect(workspace.manifest.payload.cases.isEmpty)
    #expect(workspace.checkpoint.corpusID == corpusID)
    #expect(workspace.checkpoint.eventCount == 0)

    let consentURL = workspace.workspaceURL.appendingPathComponent("consent.json")
    let manifestURL = workspace.workspaceURL.appendingPathComponent("manifest.json")
    let checkpointURL = workspace.workspaceURL.appendingPathComponent("checkpoint.json")
    let exposureURL = workspace.workspaceURL.appendingPathComponent("exposure", isDirectory: true)
    let ledgerURL = exposureURL.appendingPathComponent("ledger.jsonl")
    let lockURL = exposureURL.appendingPathComponent("ledger.jsonl.lock")
    let consent = Data(#"{"allowsAudioCapture":false,"allowsTranscriptReference":false,"consentID":"00000000-0000-0000-0000-0000000000a1","corpusID":"00000000-0000-0000-0000-0000000000a1","createdAtUnixMilliseconds":1725000000123,"purpose":"localWritingQuality","schemaVersion":1}"#.utf8)
    let consentDigest = SHA256.hash(data: consent).map { String(format: "%02x", $0) }.joined()

    #expect(try Data(contentsOf: consentURL) == consent)
    #expect(workspace.manifest.payload.consentReceiptSHA256 == consentDigest)
    #expect(try Data(contentsOf: manifestURL)
      == LocalWritingCorpusCodec.canonicalData(for: workspace.manifest))
    #expect(try Data(contentsOf: checkpointURL) == workspace.checkpoint.canonicalData)
    #expect(FileManager.default.fileExists(atPath: ledgerURL.path))
    #expect(FileManager.default.fileExists(atPath: lockURL.path))
    for directory in [workspace.workspaceURL.deletingLastPathComponent(), workspace.workspaceURL, exposureURL] {
      #expect(try permissions(at: directory) == 0o700)
    }
    for file in [consentURL, manifestURL, checkpointURL, ledgerURL, lockURL] {
      #expect(try permissions(at: file) == 0o600)
    }
  }

  @Test
  func checkpointDirectorySyncFailureRemovesOnlyThePartialCorpusChild() async throws {
    let fixture = try CorpusStoreFixture()
    defer { fixture.cleanup() }
    let corpusID = UUID(uuidString: "00000000-0000-0000-0000-0000000000a2")!
    let workspaceURL = fixture.workspaceURL(corpusID: corpusID)
    let store = LocalWritingCorpusStore(
      clock: { 1_725_000_000_124 },
      additionalForbiddenRoots: { [] },
      faultHook: { point in
        if point == .afterCheckpointRenameBeforeDirectorySync {
          throw CorpusStoreTestFailure.injected
        }
      }
    )

    await #expect(throws: CorpusStoreTestFailure.injected) {
      try await store.create(in: fixture.selectedContainer, corpusID: corpusID)
    }

    #expect(!FileManager.default.fileExists(atPath: workspaceURL.path))
    let opener = LocalWritingCorpusStore(
      clock: { 1_725_000_000_124 },
      additionalForbiddenRoots: { [] }
    )
    await #expect(throws: LocalWritingCorpusStoreError.missingAuthority) {
      try await opener.open(at: workspaceURL)
    }
  }

  @Test
  func reopensTheExactEmptyWorkspaceAndRejectsAnExistingDestination() async throws {
    let fixture = try CorpusStoreFixture()
    defer { fixture.cleanup() }
    let corpusID = testUUID(0xa3)
    let store = fixture.store(timestamp: 1_725_000_000_125)
    let created = try await store.create(in: fixture.selectedContainer, corpusID: corpusID)

    let reopened = try await fixture.store().open(at: created.workspaceURL)

    #expect(reopened == created)
    await #expect(throws: LocalWritingCorpusStoreError.alreadyExists) {
      try await store.create(in: fixture.selectedContainer, corpusID: corpusID)
    }
  }

  @Test
  func rejectsUnsafeSelectedContainersWithoutMutatingThem() async throws {
    let fixture = try CorpusStoreFixture()
    defer { fixture.cleanup() }
    let corpusID = testUUID(0xa4)
    let store = fixture.store()
    let fileManager = FileManager.default

    for invalid in [
      URL(fileURLWithPath: "/", isDirectory: true),
      fileManager.homeDirectoryForCurrentUser,
      fixture.selectedContainer.appendingPathComponent("..", isDirectory: true),
      URL(string: "file:relative-corpus")!,
    ] {
      await #expect(throws: LocalWritingCorpusStoreError.invalidLocation) {
        try await store.create(in: invalid, corpusID: corpusID)
      }
    }

    let forbidden = fixture.root.appendingPathComponent("Forbidden", isDirectory: true)
    try fileManager.createDirectory(at: forbidden, withIntermediateDirectories: true)
    let forbiddenStore = LocalWritingCorpusStore(
      clock: { 1 },
      additionalForbiddenRoots: { [forbidden] }
    )
    await #expect(throws: LocalWritingCorpusStoreError.invalidLocation) {
      try await forbiddenStore.create(in: forbidden, corpusID: corpusID)
    }

    for markerIsDirectory in [true, false] {
      let repository = fixture.root.appendingPathComponent(
        markerIsDirectory ? "Repository" : "Worktree",
        isDirectory: true
      )
      let selected = repository.appendingPathComponent("Selected", isDirectory: true)
      try fileManager.createDirectory(at: selected, withIntermediateDirectories: true)
      let marker = repository.appendingPathComponent(".git", isDirectory: markerIsDirectory)
      if markerIsDirectory {
        try fileManager.createDirectory(at: marker, withIntermediateDirectories: false)
      } else {
        try Data("gitdir: elsewhere".utf8).write(to: marker)
      }
      await #expect(throws: LocalWritingCorpusStoreError.invalidLocation) {
        try await store.create(in: selected, corpusID: corpusID)
      }
    }

    let appSelected = fixture.root
      .appendingPathComponent("Example.app", isDirectory: true)
      .appendingPathComponent("Selected", isDirectory: true)
    try fileManager.createDirectory(at: appSelected, withIntermediateDirectories: true)
    await #expect(throws: LocalWritingCorpusStoreError.invalidLocation) {
      try await store.create(in: appSelected, corpusID: corpusID)
    }
    #expect(!fileManager.fileExists(
      atPath: fixture.selectedContainer.appendingPathComponent("Fleck Local Writing Corpus").path
    ))
  }

  @Test
  func rejectsSelectedAndManagedSymlinksAndIncorrectAuthorityModes() async throws {
    let fileManager = FileManager.default
    let selectedSymlinkFixture = try CorpusStoreFixture()
    defer { selectedSymlinkFixture.cleanup() }
    let selectedSymlink = selectedSymlinkFixture.root
      .appendingPathComponent("SelectedSymlink", isDirectory: true)
    try fileManager.createSymbolicLink(
      at: selectedSymlink,
      withDestinationURL: selectedSymlinkFixture.selectedContainer
    )
    await #expect(throws: LocalWritingCorpusStoreError.invalidLocation) {
      try await selectedSymlinkFixture.store().create(
        in: selectedSymlink,
        corpusID: testUUID(0xa5)
      )
    }
    let realParent = selectedSymlinkFixture.root
      .appendingPathComponent("RealParent", isDirectory: true)
    let selectedBelowRealParent = realParent
      .appendingPathComponent("Selected", isDirectory: true)
    try fileManager.createDirectory(
      at: selectedBelowRealParent,
      withIntermediateDirectories: true
    )
    let parentSymlink = selectedSymlinkFixture.root
      .appendingPathComponent("ParentSymlink", isDirectory: true)
    try fileManager.createSymbolicLink(at: parentSymlink, withDestinationURL: realParent)
    await #expect(throws: LocalWritingCorpusStoreError.invalidLocation) {
      try await selectedSymlinkFixture.store().create(
        in: parentSymlink.appendingPathComponent("Selected", isDirectory: true),
        corpusID: testUUID(0xa5)
      )
    }

    let managedSymlinkFixture = try CorpusStoreFixture()
    defer { managedSymlinkFixture.cleanup() }
    let target = managedSymlinkFixture.root.appendingPathComponent("Target", isDirectory: true)
    try fileManager.createDirectory(at: target, withIntermediateDirectories: false)
    try fileManager.createSymbolicLink(
      at: managedSymlinkFixture.selectedContainer
        .appendingPathComponent("Fleck Local Writing Corpus", isDirectory: true),
      withDestinationURL: target
    )
    await #expect(throws: LocalWritingCorpusStoreError.permissions) {
      try await managedSymlinkFixture.store().create(
        in: managedSymlinkFixture.selectedContainer,
        corpusID: testUUID(0xa6)
      )
    }

    let modeFixture = try CorpusStoreFixture()
    defer { modeFixture.cleanup() }
    let created = try await modeFixture.store().create(
      in: modeFixture.selectedContainer,
      corpusID: testUUID(0xa7)
    )
    let paths = CorpusStorePaths(workspace: created.workspaceURL)
    try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: paths.manifest.path)
    await #expect(throws: LocalWritingCorpusStoreError.permissions) {
      try await modeFixture.store().open(at: created.workspaceURL)
    }
    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.manifest.path)
    try fileManager.removeItem(at: paths.manifest)
    try fileManager.createSymbolicLink(at: paths.manifest, withDestinationURL: paths.consent)
    await #expect(throws: LocalWritingCorpusStoreError.permissions) {
      try await modeFixture.store().open(at: created.workspaceURL)
    }
  }

  @Test
  func rejectsNoncanonicalOrMismatchedConsentReceipts() async throws {
    let fixture = try CorpusStoreFixture()
    defer { fixture.cleanup() }
    let created = try await fixture.store(timestamp: 100).create(
      in: fixture.selectedContainer,
      corpusID: testUUID(0xa8)
    )
    let paths = CorpusStorePaths(workspace: created.workspaceURL)
    let canonical = try Data(contentsOf: paths.consent)
    let text = try #require(String(data: canonical, encoding: .utf8))
    let noncanonical: [Data] = [
      Data((" " + text).utf8),
      Data(text.replacingOccurrences(
        of: #""schemaVersion":1"#,
        with: #""unknown":0,"schemaVersion":1"#
      ).utf8),
      Data(text.replacingOccurrences(
        of: #""schemaVersion":1"#,
        with: #""schemaVersion":1,"schemaVersion":1"#
      ).utf8),
      Data(text.replacingOccurrences(of: "false", with: "true").utf8),
      Data(text.replacingOccurrences(of: #""schemaVersion":1"#, with: #""schemaVersion":2"#).utf8),
      Data(text.replacingOccurrences(of: ":100,", with: ":100.0,").utf8),
      Data(text.replacingOccurrences(of: ":100,", with: ":9223372036854775808,").utf8),
      Data([0xff]),
      Data(repeating: 0x20, count: 4_097),
    ]
    for bytes in noncanonical {
      try replaceFile(at: paths.consent, with: bytes)
      await #expect(throws: LocalWritingCorpusStoreError.nonCanonicalData) {
        try await fixture.store().open(at: created.workspaceURL)
      }
    }

    let wrongID = text.replacingOccurrences(
      of: testUUID(0xa8).uuidString.lowercased(),
      with: testUUID(0xff).uuidString.lowercased()
    )
    try replaceFile(at: paths.consent, with: Data(wrongID.utf8))
    await #expect(throws: LocalWritingCorpusStoreError.identityMismatch) {
      try await fixture.store().open(at: created.workspaceURL)
    }
    let wrongTime = text.replacingOccurrences(of: ":100,", with: ":101,")
    try replaceFile(at: paths.consent, with: Data(wrongTime.utf8))
    await #expect(throws: LocalWritingCorpusStoreError.identityMismatch) {
      try await fixture.store().open(at: created.workspaceURL)
    }
  }

  @Test
  func rejectsManifestLedgerAndCheckpointCorruption() async throws {
    let manifestFixture = try CorpusStoreFixture()
    defer { manifestFixture.cleanup() }
    let manifestWorkspace = try await manifestFixture.store().create(
      in: manifestFixture.selectedContainer,
      corpusID: testUUID(0xa9)
    )
    let manifestPaths = CorpusStorePaths(workspace: manifestWorkspace.workspaceURL)
    let manifest = try Data(contentsOf: manifestPaths.manifest)
    try replaceFile(at: manifestPaths.manifest, with: Data([0x20]) + manifest)
    await #expect(throws: LocalWritingCorpusStoreError.nonCanonicalData) {
      try await manifestFixture.store().open(at: manifestWorkspace.workspaceURL)
    }

    let ledgerFixture = try CorpusStoreFixture()
    defer { ledgerFixture.cleanup() }
    let ledgerWorkspace = try await ledgerFixture.store().create(
      in: ledgerFixture.selectedContainer,
      corpusID: testUUID(0xaa)
    )
    let ledgerPaths = CorpusStorePaths(workspace: ledgerWorkspace.workspaceURL)
    try replaceFile(at: ledgerPaths.ledger, with: Data("corrupt\n".utf8))
    await #expect(throws: LocalWritingCorpusStoreError.nonCanonicalData) {
      try await ledgerFixture.store().open(at: ledgerWorkspace.workspaceURL)
    }

    let checkpointFixture = try CorpusStoreFixture()
    defer { checkpointFixture.cleanup() }
    let checkpointWorkspace = try await checkpointFixture.store().create(
      in: checkpointFixture.selectedContainer,
      corpusID: testUUID(0xab)
    )
    let checkpointPaths = CorpusStorePaths(workspace: checkpointWorkspace.workspaceURL)
    try replaceFile(at: checkpointPaths.checkpoint, with: Data("{}".utf8))
    await #expect(throws: LocalWritingCorpusStoreError.nonCanonicalData) {
      try await checkpointFixture.store().open(at: checkpointWorkspace.workspaceURL)
    }
  }

  @Test
  func rejectsCanonicalManifestBindingMismatchesAndWrongSchema() async throws {
    let fixture = try CorpusStoreFixture()
    defer { fixture.cleanup() }
    let corpusID = testUUID(0xbd)
    let workspace = try await fixture.store(timestamp: 200).create(
      in: fixture.selectedContainer,
      corpusID: corpusID
    )
    let paths = CorpusStorePaths(workspace: workspace.workspaceURL)
    let canonical = try Data(contentsOf: paths.manifest)
    let payloads = [
      try LocalWritingCorpusPayload(
        language: "en-US",
        claimScope: .ownerPrivateBeta,
        consentReceiptSHA256: workspace.manifest.payload.consentReceiptSHA256,
        createdAtUnixMilliseconds: 201,
        controlledWorkspaces: [],
        cases: []
      ),
      try LocalWritingCorpusPayload(
        language: "en-US",
        claimScope: .ownerPrivateBeta,
        consentReceiptSHA256: String(repeating: "1", count: 64),
        createdAtUnixMilliseconds: 200,
        controlledWorkspaces: [],
        cases: []
      ),
    ]
    for payload in payloads {
      let manifest = try LocalWritingCorpusCodec.makeManifest(
        corpusID: corpusID,
        payload: payload
      )
      try replaceFile(
        at: paths.manifest,
        with: try LocalWritingCorpusCodec.canonicalData(for: manifest)
      )
      await #expect(throws: LocalWritingCorpusStoreError.identityMismatch) {
        try await fixture.store().open(at: workspace.workspaceURL)
      }
    }
    let wrongCorpusManifest = try LocalWritingCorpusCodec.makeManifest(
      corpusID: testUUID(0xbe),
      payload: workspace.manifest.payload
    )
    try replaceFile(
      at: paths.manifest,
      with: try LocalWritingCorpusCodec.canonicalData(for: wrongCorpusManifest)
    )
    await #expect(throws: LocalWritingCorpusStoreError.identityMismatch) {
      try await fixture.store().open(at: workspace.workspaceURL)
    }

    let text = try #require(String(data: canonical, encoding: .utf8))
    try replaceFile(
      at: paths.manifest,
      with: Data(text.replacingOccurrences(
        of: #""schemaVersion":1"#,
        with: #""schemaVersion":2"#
      ).utf8)
    )
    await #expect(throws: LocalWritingCorpusStoreError.nonCanonicalData) {
      try await fixture.store().open(at: workspace.workspaceURL)
    }
  }

  @Test
  func repairsMissingAndExactStaleAncestorCheckpointsFromTheLedger() async throws {
    let missingFixture = try CorpusStoreFixture()
    defer { missingFixture.cleanup() }
    let missingWorkspace = try await missingFixture.store().create(
      in: missingFixture.selectedContainer,
      corpusID: testUUID(0xac)
    )
    let missingPaths = CorpusStorePaths(workspace: missingWorkspace.workspaceURL)
    try FileManager.default.removeItem(at: missingPaths.checkpoint)
    let reopenedMissing = try await missingFixture.store().open(at: missingWorkspace.workspaceURL)
    #expect(try Data(contentsOf: missingPaths.checkpoint) == reopenedMissing.checkpoint.canonicalData)
    #expect(try permissions(at: missingPaths.checkpoint) == 0o600)

    let staleFixture = try CorpusStoreFixture()
    defer { staleFixture.cleanup() }
    let staleWorkspace = try await staleFixture.store().create(
      in: staleFixture.selectedContainer,
      corpusID: testUUID(0xad)
    )
    let stalePaths = CorpusStorePaths(workspace: staleWorkspace.workspaceURL)
    let live = try appendExposure(
      to: stalePaths.ledger,
      corpusID: staleWorkspace.corpusID,
      parent: staleWorkspace.checkpoint,
      discriminator: 1
    )
    let reopenedStale = try await staleFixture.store().open(at: staleWorkspace.workspaceURL)
    #expect(reopenedStale.checkpoint == live)
    #expect(try Data(contentsOf: stalePaths.checkpoint) == live.canonicalData)
  }

  @Test
  func rejectsAheadForkedAndWrongCorpusCheckpoints() async throws {
    let ahead = try await makeCheckpointPair(firstID: 0xae, secondID: 0xae)
    defer { ahead.cleanup() }
    let aheadLive = try appendExposure(
      to: ahead.secondPaths.ledger,
      corpusID: ahead.firstWorkspace.corpusID,
      parent: ahead.secondWorkspace.checkpoint,
      discriminator: 2
    )
    try replaceFile(at: ahead.firstPaths.checkpoint, with: aheadLive.canonicalData)
    await #expect(throws: LocalWritingCorpusStoreError.rollbackOrFork) {
      try await ahead.firstFixture.store().open(at: ahead.firstWorkspace.workspaceURL)
    }

    let fork = try await makeCheckpointPair(firstID: 0xaf, secondID: 0xaf)
    defer { fork.cleanup() }
    let firstHead = try appendExposure(
      to: fork.firstPaths.ledger,
      corpusID: fork.firstWorkspace.corpusID,
      parent: fork.firstWorkspace.checkpoint,
      discriminator: 3
    )
    _ = try await fork.firstFixture.store().open(at: fork.firstWorkspace.workspaceURL)
    let forkHead = try appendExposure(
      to: fork.secondPaths.ledger,
      corpusID: fork.secondWorkspace.corpusID,
      parent: fork.secondWorkspace.checkpoint,
      discriminator: 4
    )
    #expect(firstHead.eventCount == forkHead.eventCount)
    #expect(firstHead.currentHeadSHA256 != forkHead.currentHeadSHA256)
    try replaceFile(at: fork.firstPaths.checkpoint, with: forkHead.canonicalData)
    await #expect(throws: LocalWritingCorpusStoreError.rollbackOrFork) {
      try await fork.firstFixture.store().open(at: fork.firstWorkspace.workspaceURL)
    }

    let wrong = try await makeCheckpointPair(firstID: 0xb0, secondID: 0xb1)
    defer { wrong.cleanup() }
    try replaceFile(
      at: wrong.firstPaths.checkpoint,
      with: wrong.secondWorkspace.checkpoint.canonicalData
    )
    await #expect(throws: LocalWritingCorpusStoreError.identityMismatch) {
      try await wrong.firstFixture.store().open(at: wrong.firstWorkspace.workspaceURL)
    }
  }

  @Test
  func everyCreationFaultLeavesNoOpenablePartialChild() async throws {
    let points: [LocalWritingCorpusStoreFaultPoint] = [
      .afterConsentPublish,
      .afterManifestPublish,
      .afterLedgerCreate,
      .afterCheckpointStageSync,
      .afterCheckpointStageCloseBeforeReadback,
      .beforeCheckpointRename,
    ]
    for (index, point) in points.enumerated() {
      let fixture = try CorpusStoreFixture()
      defer { fixture.cleanup() }
      let corpusID = testUUID(UInt8(0xb2 + index))
      let workspaceURL = fixture.workspaceURL(corpusID: corpusID)
      let store = fixture.store(faultHook: { observed in
        if observed == point { throw CorpusStoreTestFailure.injected }
      })
      await #expect(throws: CorpusStoreTestFailure.injected) {
        try await store.create(in: fixture.selectedContainer, corpusID: corpusID)
      }
      #expect(!FileManager.default.fileExists(atPath: workspaceURL.path))
      await #expect(throws: LocalWritingCorpusStoreError.missingAuthority) {
        try await fixture.store().open(at: workspaceURL)
      }
    }
  }

  @Test
  func cleanupPreservesAnIdentitySwappedReplacement() async throws {
    let fixture = try CorpusStoreFixture()
    defer { fixture.cleanup() }
    let corpusID = testUUID(0xb8)
    let workspace = fixture.workspaceURL(corpusID: corpusID)
    let displaced = fixture.root.appendingPathComponent("Displaced", isDirectory: true)
    let store = fixture.store(faultHook: { point in
      guard point == .afterConsentPublish else { return }
      try FileManager.default.moveItem(at: workspace, to: displaced)
      try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false)
      try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: workspace.path)
      throw CorpusStoreTestFailure.injected
    })

    await #expect(throws: CorpusStoreTestFailure.injected) {
      try await store.create(in: fixture.selectedContainer, corpusID: corpusID)
    }

    #expect(FileManager.default.fileExists(atPath: workspace.path))
    #expect(FileManager.default.fileExists(atPath: displaced.path))
    #expect((try FileManager.default.contentsOfDirectory(atPath: workspace.path)).isEmpty)
  }

  @Test
  func openRejectsAByteForByteLeafReplacementDuringValidation() async throws {
    let fixture = try CorpusStoreFixture()
    defer { fixture.cleanup() }
    let workspace = try await fixture.store().create(
      in: fixture.selectedContainer,
      corpusID: testUUID(0xba)
    )
    let paths = CorpusStorePaths(workspace: workspace.workspaceURL)
    let manifest = try Data(contentsOf: paths.manifest)
    let opener = fixture.store(faultHook: { point in
      guard point == .afterAuthorityRead else { return }
      try FileManager.default.removeItem(at: paths.manifest)
      #expect(FileManager.default.createFile(atPath: paths.manifest.path, contents: manifest))
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: paths.manifest.path
      )
    })

    await #expect(throws: LocalWritingCorpusStoreError.identityMismatch) {
      try await opener.open(at: workspace.workspaceURL)
    }
  }

  @Test
  func checkpointReadbackAndRenameFailuresPreserveOnlyForeignAuthorities() async throws {
    let readbackFixture = try CorpusStoreFixture()
    defer { readbackFixture.cleanup() }
    let readbackID = testUUID(0xbb)
    let readbackWorkspace = readbackFixture.workspaceURL(corpusID: readbackID)
    let readbackStore = readbackFixture.store(faultHook: { point in
      guard point == .afterCheckpointStageCloseBeforeReadback else { return }
      let names = try FileManager.default.contentsOfDirectory(atPath: readbackWorkspace.path)
      let stage = try #require(names.first { $0.hasPrefix(".checkpoint-") })
      try replaceFile(
        at: readbackWorkspace.appendingPathComponent(stage),
        with: Data("{}".utf8)
      )
    })
    await #expect(throws: LocalWritingCorpusStoreError.identityMismatch) {
      try await readbackStore.create(
        in: readbackFixture.selectedContainer,
        corpusID: readbackID
      )
    }
    #expect(!FileManager.default.fileExists(atPath: readbackWorkspace.path))

    let renameFixture = try CorpusStoreFixture()
    defer { renameFixture.cleanup() }
    let renameID = testUUID(0xbc)
    let renameWorkspace = renameFixture.workspaceURL(corpusID: renameID)
    let checkpoint = renameWorkspace.appendingPathComponent("checkpoint.json")
    let foreign = Data("foreign-authority".utf8)
    let renameStore = renameFixture.store(faultHook: { point in
      guard point == .beforeCheckpointRename else { return }
      #expect(FileManager.default.createFile(atPath: checkpoint.path, contents: foreign))
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: checkpoint.path
      )
    })
    await #expect(throws: LocalWritingCorpusStoreError.identityMismatch) {
      try await renameStore.create(in: renameFixture.selectedContainer, corpusID: renameID)
    }
    #expect(try Data(contentsOf: checkpoint) == foreign)
    await #expect(throws: LocalWritingCorpusStoreError.missingAuthority) {
      try await renameFixture.store().open(at: renameWorkspace)
    }
  }

  @Test
  func canonicalAuthoritiesAndErrorsContainNoPrivateMaterial() async throws {
    let fixture = try CorpusStoreFixture()
    defer { fixture.cleanup() }
    let workspace = try await fixture.store().create(
      in: fixture.selectedContainer,
      corpusID: testUUID(0xb9)
    )
    let paths = CorpusStorePaths(workspace: workspace.workspaceURL)
    var authorityBytes = Data()
    for url in [paths.consent, paths.manifest, paths.checkpoint, paths.ledger] {
      authorityBytes.append(try Data(contentsOf: url))
    }
    let text = String(decoding: authorityBytes, as: UTF8.self)
    for privateValue in [
      fixture.root.path,
      FileManager.default.homeDirectoryForCurrentUser.path,
      "private transcript material",
      "recorded audio bytes",
    ] {
      #expect(!text.contains(privateValue))
    }
    for error in [
      LocalWritingCorpusStoreError.invalidLocation,
      .alreadyExists,
      .missingAuthority,
      .permissions,
      .nonCanonicalData,
      .identityMismatch,
      .rollbackOrFork,
      .ioFailure,
    ] {
      #expect(!error.description.contains("/"))
      #expect(!error.description.contains(FileManager.default.homeDirectoryForCurrentUser.lastPathComponent))
    }
  }
}

private enum CorpusStoreTestFailure: Error {
  case injected
}

private func permissions(at url: URL) throws -> Int {
  let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
  return try #require(attributes[.posixPermissions] as? Int) & 0o7777
}

private func testUUID(_ finalByte: UInt8) -> UUID {
  UUID(uuidString: String(format: "00000000-0000-0000-0000-0000000000%02x", finalByte))!
}

private func replaceFile(at url: URL, with data: Data) throws {
  let handle = try FileHandle(forWritingTo: url)
  defer { try? handle.close() }
  try handle.truncate(atOffset: 0)
  try handle.write(contentsOf: data)
  try handle.synchronize()
}

private func appendExposure(
  to ledgerURL: URL,
  corpusID: UUID,
  parent: LocalWritingExposureLedgerCheckpoint,
  discriminator: UInt8
) throws -> LocalWritingExposureLedgerCheckpoint {
  let ledger = try LocalWritingExposureLedger.open(at: ledgerURL)
  let digestCharacter = String(format: "%x", Int(discriminator % 15) + 1)
  let exposure = try LocalWritingCandidateExposure(
    corpusID: corpusID,
    caseID: testUUID(discriminator),
    materialLineageID: testUUID(discriminator &+ 0x20),
    candidateIdentitySHA256: String(repeating: digestCharacter, count: 64),
    configurationIdentitySHA256: String(repeating: "2", count: 64),
    roleProfileIdentitySHA256: String(repeating: "3", count: 64),
    executionIdentitySHA256: String(repeating: "4", count: 64),
    executionStratum: .e1
  )
  return try ledger.appendExposure(exposure, expectedHead: parent.currentHeadSHA256)
}

private struct CorpusStorePaths {
  let consent: URL
  let manifest: URL
  let checkpoint: URL
  let exposure: URL
  let ledger: URL
  let lock: URL

  init(workspace: URL) {
    consent = workspace.appendingPathComponent("consent.json")
    manifest = workspace.appendingPathComponent("manifest.json")
    checkpoint = workspace.appendingPathComponent("checkpoint.json")
    exposure = workspace.appendingPathComponent("exposure", isDirectory: true)
    ledger = exposure.appendingPathComponent("ledger.jsonl")
    lock = exposure.appendingPathComponent("ledger.jsonl.lock")
  }
}

private struct CorpusCheckpointPair {
  let firstFixture: CorpusStoreFixture
  let secondFixture: CorpusStoreFixture
  let firstWorkspace: LocalWritingCorpusWorkspace
  let secondWorkspace: LocalWritingCorpusWorkspace

  var firstPaths: CorpusStorePaths { CorpusStorePaths(workspace: firstWorkspace.workspaceURL) }
  var secondPaths: CorpusStorePaths { CorpusStorePaths(workspace: secondWorkspace.workspaceURL) }

  func cleanup() {
    firstFixture.cleanup()
    secondFixture.cleanup()
  }
}

private func makeCheckpointPair(
  firstID: UInt8,
  secondID: UInt8
) async throws -> CorpusCheckpointPair {
  let first = try CorpusStoreFixture()
  do {
    let second = try CorpusStoreFixture()
    do {
      let firstWorkspace = try await first.store().create(
        in: first.selectedContainer,
        corpusID: testUUID(firstID)
      )
      let secondWorkspace = try await second.store().create(
        in: second.selectedContainer,
        corpusID: testUUID(secondID)
      )
      return CorpusCheckpointPair(
        firstFixture: first,
        secondFixture: second,
        firstWorkspace: firstWorkspace,
        secondWorkspace: secondWorkspace
      )
    } catch {
      second.cleanup()
      throw error
    }
  } catch {
    first.cleanup()
    throw error
  }
}

private struct CorpusStoreFixture {
  let root: URL
  let selectedContainer: URL

  init() throws {
    root = URL(fileURLWithPath: "/Users/Shared", isDirectory: true)
      .appendingPathComponent(
      "FleckLocalWritingCorpusStoreTests-\(UUID().uuidString)",
      isDirectory: true
    )
    selectedContainer = root.appendingPathComponent("Selected", isDirectory: true)
    try FileManager.default.createDirectory(
      at: selectedContainer,
      withIntermediateDirectories: true
    )
  }

  func cleanup() {
    try? FileManager.default.removeItem(at: root)
  }

  func workspaceURL(corpusID: UUID) -> URL {
    selectedContainer
      .appendingPathComponent("Fleck Local Writing Corpus", isDirectory: true)
      .appendingPathComponent(corpusID.uuidString.lowercased(), isDirectory: true)
  }

  func store(
    timestamp: Int64 = 1_725_000_000_123,
    faultHook: LocalWritingCorpusStore.FaultHook? = nil
  ) -> LocalWritingCorpusStore {
    LocalWritingCorpusStore(
      clock: { timestamp },
      additionalForbiddenRoots: { [] },
      faultHook: faultHook
    )
  }
}
