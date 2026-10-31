import Darwin
import Foundation
import Testing

@testable import FleckMCPFixtureSupport

private enum FixtureAdmissionTestError: Error, Equatable {
  case setupFailure
  case injectedFailure
}

private struct GuardedFixtureRoots {
  let run: URL
  let homePath: String
  let temporary: URL
  let runPath: String
  let temporaryPath: String
  let environment: [String: String]
}

private func directoryPath(_ url: URL) -> String {
  let path = url.path
  return path.hasSuffix("/") ? String(path.dropLast()) : path
}

private func makeSandbox() throws -> OwnedMCPFixtureRoot {
  try OwnedMCPFixtureRoot.create(kind: .eventJournal)
}

private func recordCleanup(_ root: OwnedMCPFixtureRoot) {
  do {
    try root.cleanup()
  } catch {
    Issue.record("Owned MCP fixture cleanup failed: \(error)")
  }
}

private func makeDirectory(_ url: URL, mode: mode_t = 0o700) throws {
  let path = directoryPath(url)
  let parentPath = directoryPath(url.deletingLastPathComponent())
  let name = url.lastPathComponent
  guard url.isFileURL, !name.isEmpty, name != ".", name != "..", !name.contains("/"),
    path == parentPath + "/" + name
  else {
    throw FixtureAdmissionTestError.setupFailure
  }

  func isOwnedDirectory(_ status: stat, expectedMode: mode_t? = nil) -> Bool {
    guard (status.st_mode & S_IFMT) == S_IFDIR, status.st_uid == geteuid() else { return false }
    if let expectedMode, (status.st_mode & 0o7777) != expectedMode { return false }
    return true
  }
  func hasSameIdentity(_ left: stat, _ right: stat) -> Bool {
    left.st_dev == right.st_dev && left.st_ino == right.st_ino
  }

  let parentFD = parentPath.withCString {
    Darwin.open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
  }
  guard parentFD >= 0 else { throw FixtureAdmissionTestError.setupFailure }
  defer { Darwin.close(parentFD) }

  guard name.withCString({ Darwin.mkdirat(parentFD, $0, mode) }) == 0 else {
    throw FixtureAdmissionTestError.setupFailure
  }
  var createdPathStatus = stat()
  var createdEntryStatus = stat()
  guard
    path.withCString({ lstat($0, &createdPathStatus) }) == 0,
    name.withCString({ fstatat(parentFD, $0, &createdEntryStatus, AT_SYMLINK_NOFOLLOW) }) == 0,
    isOwnedDirectory(createdPathStatus),
    isOwnedDirectory(createdEntryStatus),
    hasSameIdentity(createdPathStatus, createdEntryStatus)
  else {
    throw FixtureAdmissionTestError.setupFailure
  }

  let childFD = name.withCString {
    Darwin.openat(parentFD, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
  }
  guard childFD >= 0 else { throw FixtureAdmissionTestError.setupFailure }
  defer { Darwin.close(childFD) }

  var openedStatus = stat()
  var openedPathStatus = stat()
  var openedEntryStatus = stat()
  guard
    fstat(childFD, &openedStatus) == 0,
    path.withCString({ lstat($0, &openedPathStatus) }) == 0,
    name.withCString({ fstatat(parentFD, $0, &openedEntryStatus, AT_SYMLINK_NOFOLLOW) }) == 0,
    isOwnedDirectory(openedStatus),
    isOwnedDirectory(openedPathStatus),
    isOwnedDirectory(openedEntryStatus),
    hasSameIdentity(openedStatus, createdPathStatus),
    hasSameIdentity(openedPathStatus, createdPathStatus),
    hasSameIdentity(openedEntryStatus, createdPathStatus)
  else {
    throw FixtureAdmissionTestError.setupFailure
  }

  guard Darwin.fchmod(childFD, mode) == 0 else {
    throw FixtureAdmissionTestError.setupFailure
  }

  var finalDescriptorStatus = stat()
  var finalPathStatus = stat()
  var finalEntryStatus = stat()
  guard
    fstat(childFD, &finalDescriptorStatus) == 0,
    path.withCString({ lstat($0, &finalPathStatus) }) == 0,
    name.withCString({ fstatat(parentFD, $0, &finalEntryStatus, AT_SYMLINK_NOFOLLOW) }) == 0,
    isOwnedDirectory(finalDescriptorStatus, expectedMode: mode),
    isOwnedDirectory(finalPathStatus, expectedMode: mode),
    isOwnedDirectory(finalEntryStatus, expectedMode: mode),
    hasSameIdentity(finalDescriptorStatus, createdPathStatus),
    hasSameIdentity(finalPathStatus, createdPathStatus),
    hasSameIdentity(finalEntryStatus, createdPathStatus)
  else {
    throw FixtureAdmissionTestError.setupFailure
  }
}

private func makeGuardedRoots(
  in sandbox: OwnedMCPFixtureRoot,
  name: String = "run",
  runMode: mode_t = 0o700
) throws -> GuardedFixtureRoots {
  let run = sandbox.url.appendingPathComponent(name, isDirectory: true)
  let home = run.appendingPathComponent("home", isDirectory: true)
  let temporary = run.appendingPathComponent("tmp", isDirectory: true)
  let runPath = directoryPath(run)
  let homePath = directoryPath(home)
  let temporaryPath = directoryPath(temporary)
  try makeDirectory(run, mode: runMode)
  try makeDirectory(home)
  try makeDirectory(temporary)
  let binding = try OwnedMCPFixtureRoot.bindingTextForTesting(
    runRoot: run,
    temporaryRoot: temporary
  )
  return GuardedFixtureRoots(
    run: run,
    homePath: homePath,
    temporary: temporary,
    runPath: runPath,
    temporaryPath: temporaryPath,
    environment: [
      "HOME": homePath,
      "TMPDIR": temporaryPath,
      OwnedMCPFixtureRoot.bindingEnvironmentKey: binding,
    ]
  )
}

private func bindingText(_ roots: GuardedFixtureRoots) -> String {
  roots.environment[OwnedMCPFixtureRoot.bindingEnvironmentKey]!
}

private func replacingField(_ rawValue: String, key: String, value: String) -> String {
  let prefix = key + "="
  return rawValue
    .split(separator: "\n", omittingEmptySubsequences: false)
    .map { $0.hasPrefix(prefix) ? prefix + value : String($0) }
    .joined(separator: "\n")
}

private func environment(_ roots: GuardedFixtureRoots, binding: String? = nil) -> [String: String] {
  var environment = roots.environment
  if let binding { environment[OwnedMCPFixtureRoot.bindingEnvironmentKey] = binding }
  return environment
}

private func createForTesting(
  _ roots: GuardedFixtureRoots,
  kind: OwnedMCPFixtureKind = .eventOutbox,
  environment: [String: String]? = nil,
  foundationTemporaryDirectory: URL? = nil,
  guardedBuild: Bool = true,
  id: UUID = UUID(),
  afterChildCreated: (() throws -> Void)? = nil
) throws -> OwnedMCPFixtureRoot {
  try OwnedMCPFixtureRoot.createForTesting(
    kind: kind,
    environment: environment ?? roots.environment,
    foundationTemporaryDirectory: foundationTemporaryDirectory ?? roots.temporary,
    guardedBuild: guardedBuild,
    id: id,
    afterChildCreated: afterChildCreated
  )
}

private func contents(of url: URL) throws -> [URL] {
  try FileManager.default.contentsOfDirectory(
    at: url,
    includingPropertiesForKeys: nil
  )
}

private func string(at url: URL) throws -> String {
  String(decoding: try Data(contentsOf: url), as: UTF8.self)
}

private func identity(at url: URL) throws -> stat {
  let path = directoryPath(url)
  var status = stat()
  guard path.withCString({ lstat($0, &status) }) == 0 else {
    throw FixtureAdmissionTestError.setupFailure
  }
  return status
}

@Test func guardedBuildRequiresBindingWhenAllRuntimeMetadataIsMissing() throws {
  let sandbox = try makeSandbox()
  defer { recordCleanup(sandbox) }

  #expect(throws: OwnedMCPFixtureRootError.missingBinding) {
    _ = try OwnedMCPFixtureRoot.createForTesting(
      kind: .eventOutbox,
      environment: [:],
      foundationTemporaryDirectory: sandbox.url,
      guardedBuild: true
    )
  }
  #expect(try contents(of: sandbox.url).isEmpty)
}

@Test func bindingParserRejectsMalformedRecordsBeforeCreatingAChild() throws {
  let sandbox = try makeSandbox()
  defer { recordCleanup(sandbox) }
  let roots = try makeGuardedRoots(in: sandbox)
  let valid = bindingText(roots)
  let malformed = [
    "version=1",
    replacingField(valid, key: "version", value: "2"),
    replacingField(valid, key: "run_inode", value: "true"),
    replacingField(valid, key: "run_path", value: "relative/path"),
    replacingField(valid, key: "run_path", value: roots.runPath + "/."),
    replacingField(valid, key: "run_path", value: roots.runPath + "/\u{0085}name"),
    replacingField(valid, key: "tmp_mode", value: "0448"),
    valid + "\nversion=1",
    valid + "\nunknown=1",
    valid.replacingOccurrences(of: "tmp_mode=", with: ""),
    valid + "\n",
    String(repeating: "x", count: 4097),
  ]

  for rawValue in malformed {
    #expect(throws: OwnedMCPFixtureRootError.malformedBinding) {
      _ = try createForTesting(roots, environment: environment(roots, binding: rawValue))
    }
  }
  #expect(try contents(of: roots.temporary).isEmpty)
}

@Test func foundationHomeAndTmpdirMustMatchTheBoundRoot() throws {
  let sandbox = try makeSandbox()
  defer { recordCleanup(sandbox) }
  let roots = try makeGuardedRoots(in: sandbox)

  #expect(throws: OwnedMCPFixtureRootError.bindingMismatch) {
    _ = try createForTesting(roots, foundationTemporaryDirectory: roots.run)
  }
  var wrongTemporaryEnvironment = roots.environment
  wrongTemporaryEnvironment["TMPDIR"] = roots.runPath
  #expect(throws: OwnedMCPFixtureRootError.bindingMismatch) {
    _ = try createForTesting(roots, environment: wrongTemporaryEnvironment)
  }
  var wrongHomeEnvironment = roots.environment
  wrongHomeEnvironment["HOME"] = roots.runPath
  #expect(throws: OwnedMCPFixtureRootError.bindingMismatch) {
    _ = try createForTesting(roots, environment: wrongHomeEnvironment)
  }
  wrongHomeEnvironment["HOME"] = roots.homePath + "/"
  #expect(throws: OwnedMCPFixtureRootError.bindingMismatch) {
    _ = try createForTesting(roots, environment: wrongHomeEnvironment)
  }
  #expect(try contents(of: roots.temporary).isEmpty)
}

@Test func ancestorAndTemporaryLeafSymlinkAliasesAreRejected() throws {
  let sandbox = try makeSandbox()
  defer { recordCleanup(sandbox) }
  let roots = try makeGuardedRoots(in: sandbox)
  let alias = sandbox.url.appendingPathComponent("run-alias", isDirectory: true)
  let aliasPath = directoryPath(alias)
  guard roots.runPath.withCString({ target in aliasPath.withCString { symlink(target, $0) } }) == 0 else {
    throw FixtureAdmissionTestError.setupFailure
  }
  let aliasTemporaryPath = directoryPath(alias.appendingPathComponent("tmp", isDirectory: true))
  var aliasEnvironment = environment(
    roots,
    binding: replacingField(
      replacingField(bindingText(roots), key: "run_path", value: aliasPath),
      key: "tmp_path",
      value: aliasTemporaryPath
    )
  )
  aliasEnvironment["HOME"] = aliasPath + "/home"
  aliasEnvironment["TMPDIR"] = aliasTemporaryPath
  #expect(throws: OwnedMCPFixtureRootError.unsafeDirectory) {
    _ = try createForTesting(
      roots,
      environment: aliasEnvironment,
      foundationTemporaryDirectory: URL(fileURLWithPath: aliasTemporaryPath, isDirectory: true)
    )
  }

  let movedTemporary = roots.run.appendingPathComponent("tmp-real", isDirectory: true)
  try FileManager.default.moveItem(at: roots.temporary, to: movedTemporary)
  guard
    directoryPath(movedTemporary).withCString({ target in
      roots.temporaryPath.withCString { symlink(target, $0) }
    }) == 0
  else {
    throw FixtureAdmissionTestError.setupFailure
  }
  #expect(throws: OwnedMCPFixtureRootError.unsafeDirectory) {
    _ = try createForTesting(roots)
  }
}

@Test func ordinaryFoundationFallbackResolvesPhysicalAliasesBeforeAdmission() throws {
  let sandbox = try makeSandbox()
  defer { recordCleanup(sandbox) }
  let parent = sandbox.url.appendingPathComponent("physical-parent", isDirectory: true)
  try makeDirectory(parent)
  let alias = sandbox.url.appendingPathComponent("temporary-alias", isDirectory: true)
  guard directoryPath(parent).withCString({ target in
    directoryPath(alias).withCString { symlink(target, $0) }
  }) == 0 else {
    throw FixtureAdmissionTestError.setupFailure
  }
  let child = try OwnedMCPFixtureRoot.createForTesting(
    kind: .eventJournal,
    environment: [:],
    foundationTemporaryDirectory: alias,
    guardedBuild: false
  )
  #expect(directoryPath(child.url.deletingLastPathComponent()) == directoryPath(parent))
  #expect(try contents(of: parent).map(\.lastPathComponent) == [child.url.lastPathComponent])
  try child.cleanup()
  #expect(try contents(of: parent).isEmpty)
  #expect(try alias.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
}

@Test func staleIdentityAndIncorrectExpectedUidOrModeFailClosed() throws {
  let sandbox = try makeSandbox()
  defer { recordCleanup(sandbox) }
  let roots = try makeGuardedRoots(in: sandbox)
  let original = bindingText(roots)
  let currentUID = UInt32(geteuid())
  let wrongUID = currentUID == 0 ? 1 : 0

  for invalid in [
    replacingField(original, key: "tmp_uid", value: String(wrongUID)),
    replacingField(original, key: "tmp_mode", value: "447"),
  ] {
    #expect(throws: OwnedMCPFixtureRootError.identityMismatch) {
      _ = try createForTesting(roots, environment: environment(roots, binding: invalid))
    }
  }

  let moved = roots.run.appendingPathComponent("tmp-old", isDirectory: true)
  try FileManager.default.moveItem(at: roots.temporary, to: moved)
  try makeDirectory(roots.temporary)
  #expect(throws: OwnedMCPFixtureRootError.identityMismatch) {
    _ = try createForTesting(roots)
  }
  #expect(try contents(of: roots.temporary).isEmpty)
}

@Test func nonDirectoryTemporaryRootIsRejectedBeforeChildCreation() throws {
  let sandbox = try makeSandbox()
  defer { recordCleanup(sandbox) }
  let roots = try makeGuardedRoots(in: sandbox)
  let movedTemporary = roots.run.appendingPathComponent("tmp-directory", isDirectory: true)
  try FileManager.default.moveItem(at: roots.temporary, to: movedTemporary)
  let temporaryFile = URL(fileURLWithPath: roots.temporaryPath)
  try Data("not-a-directory".utf8).write(to: temporaryFile)

  #expect(throws: OwnedMCPFixtureRootError.unsafeDirectory) {
    _ = try createForTesting(roots)
  }
  #expect(try string(at: temporaryFile) == "not-a-directory")
  #expect(try contents(of: movedTemporary).isEmpty)
}

@Test func nonprivateBoundRunRootIsRejectedWithoutPermissionRepair() throws {
  let sandbox = try makeSandbox()
  defer { recordCleanup(sandbox) }
  let roots = try makeGuardedRoots(in: sandbox, runMode: 0o755)

  #expect(throws: OwnedMCPFixtureRootError.rootNotPrivate) {
    _ = try createForTesting(roots)
  }
  #expect(try contents(of: roots.temporary).isEmpty)
}

@Test func ordinaryBuildUsesAPrivateChildButRejectsBrokenBinding() throws {
  let sandbox = try makeSandbox()
  defer { recordCleanup(sandbox) }
  let sentinel = sandbox.url.appendingPathComponent("sibling-sentinel")
  try Data("preserve".utf8).write(to: sentinel)
  let ordinary = try OwnedMCPFixtureRoot.createForTesting(
    kind: .eventJournal,
    environment: [:],
    foundationTemporaryDirectory: sandbox.url,
    guardedBuild: false
  )
  let status = try identity(at: ordinary.url)
  #expect((status.st_mode & S_IFMT) == S_IFDIR)
  #expect(status.st_uid == geteuid())
  #expect((status.st_mode & 0o7777) == 0o700)
  try ordinary.cleanup()
  #expect(!FileManager.default.fileExists(atPath: ordinary.url.path))
  #expect(try string(at: sentinel) == "preserve")

  #expect(throws: OwnedMCPFixtureRootError.malformedBinding) {
    _ = try OwnedMCPFixtureRoot.createForTesting(
      kind: .eventJournal,
      environment: [OwnedMCPFixtureRoot.bindingEnvironmentKey: "version=1"],
      foundationTemporaryDirectory: sandbox.url,
      guardedBuild: false
    )
  }
}

@Test func existingDirectoryAndSymlinkCollisionsAreNeverAdopted() throws {
  let sandbox = try makeSandbox()
  defer { recordCleanup(sandbox) }
  let roots = try makeGuardedRoots(in: sandbox)
  let directoryID = UUID()
  let existingDirectory = roots.temporary.appendingPathComponent(
    OwnedMCPFixtureKind.eventOutbox.basename(for: directoryID),
    isDirectory: true
  )
  try makeDirectory(existingDirectory)
  let directorySentinel = existingDirectory.appendingPathComponent("sentinel")
  try Data("keep-directory".utf8).write(to: directorySentinel)
  #expect(throws: OwnedMCPFixtureRootError.childCollision) {
    _ = try createForTesting(roots, id: directoryID)
  }
  #expect(try string(at: directorySentinel) == "keep-directory")

  let symlinkID = UUID()
  let siblingSentinel = roots.temporary.appendingPathComponent("sibling-sentinel")
  try Data("keep-sibling".utf8).write(to: siblingSentinel)
  let existingSymlink = roots.temporary.appendingPathComponent(
    OwnedMCPFixtureKind.eventOutbox.basename(for: symlinkID),
    isDirectory: true
  )
  guard siblingSentinel.path.withCString({ target in directoryPath(existingSymlink).withCString { symlink(target, $0) } }) == 0 else {
    throw FixtureAdmissionTestError.setupFailure
  }
  #expect(throws: OwnedMCPFixtureRootError.childCollision) {
    _ = try createForTesting(roots, id: symlinkID)
  }
  #expect((try identity(at: existingSymlink).st_mode & S_IFMT) == S_IFLNK)
  #expect(try string(at: siblingSentinel) == "keep-sibling")
}

@Test func validBoundChildCleanupPreservesSiblingAndDoesNotFollowSymlinks() throws {
  let sandbox = try makeSandbox()
  defer { recordCleanup(sandbox) }
  let roots = try makeGuardedRoots(in: sandbox)
  let sentinel = roots.temporary.appendingPathComponent("sibling-sentinel")
  try Data("preserve".utf8).write(to: sentinel)
  let owned = try createForTesting(roots, kind: .eventJournal)
  let status = try identity(at: owned.url)
  #expect((status.st_mode & 0o7777) == 0o700)
  #expect(status.st_uid == geteuid())
  let content = owned.url.appendingPathComponent("synthetic.txt")
  try Data("synthetic fixture".utf8).write(to: content)
  let link = owned.url.appendingPathComponent("sibling-link")
  guard sentinel.path.withCString({ target in link.path.withCString { symlink(target, $0) } }) == 0 else {
    throw FixtureAdmissionTestError.setupFailure
  }

  try owned.cleanup()
  #expect(!FileManager.default.fileExists(atPath: owned.url.path))
  #expect(try string(at: sentinel) == "preserve")
}

@Test func cleanupRejectsMissingOrForeignReplacementWithoutDeletingSentinels() throws {
  let sandbox = try makeSandbox()
  defer { recordCleanup(sandbox) }
  let missingRoots = try makeGuardedRoots(in: sandbox, name: "missing-run")
  let missingSentinel = missingRoots.temporary.appendingPathComponent("sibling-sentinel")
  try Data("preserve-missing".utf8).write(to: missingSentinel)
  let missingChild = try createForTesting(missingRoots)
  try FileManager.default.removeItem(at: missingChild.url)
  #expect(throws: OwnedMCPFixtureRootError.identityMismatch) {
    try missingChild.cleanup()
  }
  #expect(try string(at: missingSentinel) == "preserve-missing")

  let replacementRoots = try makeGuardedRoots(in: sandbox, name: "replacement-run")
  let replacement = try createForTesting(replacementRoots)
  let movedChild = replacementRoots.temporary.appendingPathComponent("moved-owned-child", isDirectory: true)
  try FileManager.default.moveItem(at: replacement.url, to: movedChild)
  try makeDirectory(replacement.url)
  let foreignSentinel = replacement.url.appendingPathComponent("foreign-sentinel")
  try Data("preserve-foreign".utf8).write(to: foreignSentinel)
  #expect(throws: OwnedMCPFixtureRootError.identityMismatch) {
    try replacement.cleanup()
  }
  #expect(FileManager.default.fileExists(atPath: movedChild.path))
  #expect(try string(at: foreignSentinel) == "preserve-foreign")
}

@Test func cleanupRejectsAReboundTemporaryParent() throws {
  let sandbox = try makeSandbox()
  defer { recordCleanup(sandbox) }
  let roots = try makeGuardedRoots(in: sandbox)
  let owned = try createForTesting(roots)
  let movedTemporary = roots.run.appendingPathComponent("tmp-old", isDirectory: true)
  try FileManager.default.moveItem(at: roots.temporary, to: movedTemporary)
  try makeDirectory(roots.temporary)
  let sentinel = roots.temporary.appendingPathComponent("foreign-parent-sentinel")
  try Data("preserve-parent".utf8).write(to: sentinel)

  #expect(throws: OwnedMCPFixtureRootError.identityMismatch) {
    try owned.cleanup()
  }
  #expect(try string(at: sentinel) == "preserve-parent")
}

@Test func constructorFailureCleansOnlyTheStillMatchingCreatedChild() throws {
  let sandbox = try makeSandbox()
  defer { recordCleanup(sandbox) }
  let roots = try makeGuardedRoots(in: sandbox)
  let sibling = roots.temporary.appendingPathComponent("sibling-sentinel")
  try Data("preserve".utf8).write(to: sibling)
  let id = UUID()
  let childURL = roots.temporary.appendingPathComponent(
    OwnedMCPFixtureKind.eventOutbox.basename(for: id),
    isDirectory: true
  )

  #expect(throws: FixtureAdmissionTestError.injectedFailure) {
    _ = try createForTesting(
      roots,
      id: id,
      afterChildCreated: { throw FixtureAdmissionTestError.injectedFailure }
    )
  }
  #expect(!FileManager.default.fileExists(atPath: childURL.path))
  #expect(try string(at: sibling) == "preserve")
}

@Test func constructorFailureLeavesAReplacementChildUntouched() throws {
  let sandbox = try makeSandbox()
  defer { recordCleanup(sandbox) }
  let roots = try makeGuardedRoots(in: sandbox)
  let id = UUID()
  let childURL = roots.temporary.appendingPathComponent(
    OwnedMCPFixtureKind.eventOutbox.basename(for: id),
    isDirectory: true
  )
  let movedChild = roots.temporary.appendingPathComponent("moved-owned-child", isDirectory: true)

  #expect(throws: OwnedMCPFixtureRootError.creationCleanupFailed) {
    _ = try createForTesting(
      roots,
      id: id,
      afterChildCreated: {
        try FileManager.default.moveItem(at: childURL, to: movedChild)
        try makeDirectory(childURL)
        try Data("preserve-replacement".utf8).write(
          to: childURL.appendingPathComponent("sentinel")
        )
      }
    )
  }
  #expect(try string(at: childURL.appendingPathComponent("sentinel")) == "preserve-replacement")
  #expect(FileManager.default.fileExists(atPath: movedChild.path))
}
