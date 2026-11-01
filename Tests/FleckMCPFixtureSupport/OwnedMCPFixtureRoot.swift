import Darwin
import Foundation

public enum OwnedMCPFixtureKind: String {
  case capabilityAuthority
  case privacyExclusion
  case eventSubscription
  case eventOutbox
  case deliveryAuthorization
  case eventJournal
  case eventMonitoringRuntime
  case eventMonitoringFlow
  case eventCallbackVerification
  case eventCommandService
  case eventIPCSocket
  case eventDeliverySender
  case eventDeliveryLedger
  case inlineImage
  case eventHTTPTransport
  case nativeVisualEvidence

  func basename(for id: UUID) -> String {
    if self == .eventIPCSocket { return "fe-\(id.uuidString.lowercased())" }
    return "fleck-mcp-\(rawValue)-\(id.uuidString.lowercased())"
  }
}

enum OwnedMCPFixtureRootError: String, Error, Equatable {
  case missingBinding = "missing-binding"
  case malformedBinding = "malformed-binding"
  case bindingMismatch = "binding-mismatch"
  case unsafeDirectory = "unsafe-directory"
  case filesystemFailure = "filesystem-failure"
  case identityMismatch = "identity-mismatch"
  case rootNotPrivate = "root-not-private"
  case childCollision = "child-collision"
  case childNotPrivate = "child-not-private"
  case cleanupFailed = "cleanup-failed"
  case cleanupLimitExceeded = "cleanup-limit-exceeded"
  case creationCleanupFailed = "creation-cleanup-failed"
  case alreadyClosed = "already-closed"
}

private struct DirectoryIdentity: Equatable {
  let device: UInt64
  let inode: UInt64
  let uid: UInt32
  let mode: UInt16

  init(device: UInt64, inode: UInt64, uid: UInt32, mode: UInt16) {
    self.device = device
    self.inode = inode
    self.uid = uid
    self.mode = mode
  }

  init(_ status: stat) throws {
    guard let device = UInt64(exactly: status.st_dev), let inode = UInt64(exactly: status.st_ino),
      let uid = UInt32(exactly: status.st_uid)
    else {
      throw OwnedMCPFixtureRootError.identityMismatch
    }
    self.init(device: device, inode: inode, uid: uid, mode: UInt16(status.st_mode & 0o7777))
  }

  func matches(_ status: stat) -> Bool {
    guard (status.st_mode & S_IFMT) == S_IFDIR,
      let other = try? DirectoryIdentity(status)
    else {
      return false
    }
    return other == self
  }
}

private struct FixtureBinding {
  let runPath: String
  let runIdentity: DirectoryIdentity
  let temporaryPath: String
  let temporaryIdentity: DirectoryIdentity

  static func parse(_ raw: String) throws -> FixtureBinding {
    guard raw.utf8.count <= 4096 else { throw OwnedMCPFixtureRootError.malformedBinding }
    var fields: [String: String] = [:]
    for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
      guard let separator = line.firstIndex(of: "=") else {
        throw OwnedMCPFixtureRootError.malformedBinding
      }
      let key = String(line[..<separator])
      let value = String(line[line.index(after: separator)...])
      guard !key.isEmpty, !value.isEmpty, fields.updateValue(value, forKey: key) == nil else {
        throw OwnedMCPFixtureRootError.malformedBinding
      }
    }
    let keys: Set<String> = [
      "version", "run_path", "run_dev", "run_inode", "run_uid", "run_mode",
      "tmp_path", "tmp_dev", "tmp_inode", "tmp_uid", "tmp_mode",
    ]
    guard Set(fields.keys) == keys, fields["version"] == "1",
      let runPath = fields["run_path"], let temporaryPath = fields["tmp_path"],
      isCanonicalDirectoryPath(runPath), isCanonicalDirectoryPath(temporaryPath),
      temporaryPath == runPath + "/tmp"
    else {
      throw OwnedMCPFixtureRootError.malformedBinding
    }
    return FixtureBinding(
      runPath: runPath,
      runIdentity: DirectoryIdentity(
        device: try number(fields, "run_dev"),
        inode: try number(fields, "run_inode"),
        uid: try number(fields, "run_uid"),
        mode: try number(fields, "run_mode")
      ),
      temporaryPath: temporaryPath,
      temporaryIdentity: DirectoryIdentity(
        device: try number(fields, "tmp_dev"),
        inode: try number(fields, "tmp_inode"),
        uid: try number(fields, "tmp_uid"),
        mode: try number(fields, "tmp_mode")
      )
    )
  }

  func serialized() -> String {
    [
      "version=1", "run_path=\(runPath)", "run_dev=\(runIdentity.device)",
      "run_inode=\(runIdentity.inode)", "run_uid=\(runIdentity.uid)",
      "run_mode=\(runIdentity.mode)", "tmp_path=\(temporaryPath)",
      "tmp_dev=\(temporaryIdentity.device)", "tmp_inode=\(temporaryIdentity.inode)",
      "tmp_uid=\(temporaryIdentity.uid)", "tmp_mode=\(temporaryIdentity.mode)",
    ].joined(separator: "\n")
  }
}

// Bound public creation uses the validated process binding; Foundation matching remains for injected tests.
private enum FixtureRootSelection {
  case configuredBinding
  case foundation(URL)
}

public final class OwnedMCPFixtureRoot: @unchecked Sendable {
  static let bindingEnvironmentKey = "FLECK_MCP_FIXTURE_ROOT_BINDING"
  private static let outputLock = NSLock()
  public let url: URL

  private let lock = NSLock()
  private let kind: OwnedMCPFixtureKind
  private let basename: String
  private let childIdentity: DirectoryIdentity
  private var childFD: Int32
  private var root: OpenedRoot
  private var closed = false

  private init(kind: OwnedMCPFixtureKind, basename: String, child: OpenedDirectory, root: OpenedRoot) {
    self.kind = kind
    self.basename = basename
    childIdentity = child.identity
    childFD = child.fd
    self.root = root
    url = URL(fileURLWithPath: root.parentPath, isDirectory: true)
      .appendingPathComponent(basename, isDirectory: true)
  }

  public static func create(kind: OwnedMCPFixtureKind) throws -> OwnedMCPFixtureRoot {
    let environment = ProcessInfo.processInfo.environment
    let rootSelection: FixtureRootSelection
    if environment[Self.bindingEnvironmentKey] == nil {
      rootSelection = .foundation(FileManager.default.temporaryDirectory)
    } else {
      rootSelection = .configuredBinding
    }
    return try createInternal(
      kind: kind,
      environment: environment,
      rootSelection: rootSelection,
      guardedBuild: Self.compiledForGuardedFixtures,
      id: UUID(),
      afterChildCreated: nil
    )
  }

  public static func createSocketRoot() throws -> OwnedMCPFixtureRoot {
    try createSocketRoot(
      environment: ProcessInfo.processInfo.environment,
      guardedBuild: Self.compiledForGuardedFixtures
    )
  }

  static func createSocketRoot(
    environment: [String: String],
    guardedBuild: Bool,
    ordinaryTemporaryDirectory: URL = URL(fileURLWithPath: "/private/tmp", isDirectory: true),
    id: UUID = UUID()
  ) throws -> OwnedMCPFixtureRoot {
    guard environment["FLECK_IPC_PACKET_MODE"] == nil,
      environment["FLECK_IPC_PACKET_TMPDIR"] == nil
    else {
      throw OwnedMCPFixtureRootError.bindingMismatch
    }
    let rootSelection: FixtureRootSelection = environment[Self.bindingEnvironmentKey] == nil
      ? .foundation(ordinaryTemporaryDirectory) : .configuredBinding
    return try createInternal(
      kind: .eventIPCSocket,
      environment: environment,
      rootSelection: rootSelection,
      guardedBuild: guardedBuild,
      id: id,
      afterChildCreated: nil
    )
  }

  static func createForTesting(
    kind: OwnedMCPFixtureKind,
    environment: [String: String],
    foundationTemporaryDirectory: URL,
    guardedBuild: Bool,
    id: UUID = UUID(),
    afterChildCreated: (() throws -> Void)? = nil
  ) throws -> OwnedMCPFixtureRoot {
    try createInternal(
      kind: kind,
      environment: environment,
      rootSelection: .foundation(foundationTemporaryDirectory),
      guardedBuild: guardedBuild,
      id: id,
      afterChildCreated: afterChildCreated
    )
  }

  static func bindingTextForTesting(runRoot: URL, temporaryRoot: URL) throws -> String {
    let runPath = withoutDirectorySeparator(runRoot.path)
    let temporaryPath = withoutDirectorySeparator(temporaryRoot.path)
    guard runRoot.isFileURL, temporaryRoot.isFileURL,
      temporaryPath == runPath + "/tmp"
    else {
      throw OwnedMCPFixtureRootError.bindingMismatch
    }
    let run = try openDirectoryPath(runPath)
    defer { Darwin.close(run.fd) }
    let temporary = try openDirectoryChild(run.fd, "tmp")
    defer { Darwin.close(temporary.fd) }
    let pathTemporary = try openDirectoryPath(temporaryPath)
    defer { Darwin.close(pathTemporary.fd) }
    guard temporary.identity == pathTemporary.identity else {
      throw OwnedMCPFixtureRootError.identityMismatch
    }
    return FixtureBinding(
      runPath: runPath,
      runIdentity: run.identity,
      temporaryPath: temporaryPath,
      temporaryIdentity: temporary.identity
    ).serialized()
  }

  public func cleanup() throws {
    try lock.withLock {
      guard !closed else { throw OwnedMCPFixtureRootError.alreadyClosed }
      closed = true
      defer { closeDescriptors() }
      do {
        try Self.removeOwnedChild(
          root: root,
          childFD: childFD,
          name: basename,
          identity: childIdentity,
          emptyOnly: kind == .eventIPCSocket
        )
        if root.logsRecords {
          Self.emit("cleanup", "ok", kind: kind, basename: basename, child: childIdentity)
        }
      } catch {
        if root.logsRecords {
          Self.emit("cleanup", "failed", kind: kind, basename: basename, reason: Self.reason(error))
        }
        throw error
      }
    }
  }

  deinit { lock.withLock { closeDescriptors() } }

  private static func createInternal(
    kind: OwnedMCPFixtureKind,
    environment: [String: String],
    rootSelection: FixtureRootSelection,
    guardedBuild: Bool,
    id: UUID,
    afterChildCreated: (() throws -> Void)?
  ) throws -> OwnedMCPFixtureRoot {
    let raw = environment[Self.bindingEnvironmentKey]
    let logs = guardedBuild || raw != nil
    let basename = kind.basename(for: id)
    let binding: FixtureBinding?
    do {
      binding = try resolveBinding(raw, environment, rootSelection, guardedBuild)
    } catch {
      if logs { emit("admit", "failed", kind: kind, reason: reason(error)) }
      throw error
    }
    var root: OpenedRoot
    do {
      root = try openFixtureRoot(binding, rootSelection, logs)
    } catch {
      if logs { emit("admit", "failed", kind: kind, reason: reason(error)) }
      throw error
    }
    var childFD: Int32 = -1
    var childIdentity: DirectoryIdentity?
    var transferred = false
    defer {
      if !transferred {
        if childFD >= 0 { Darwin.close(childFD) }
        closeDescriptors(&root)
      }
    }
    if logs { emit("admit", "ok", kind: kind, run: root.runIdentity ?? root.parentIdentity, tmp: root.parentIdentity) }

    let result = basename.withCString { mkdirat(root.parentFD, $0, 0o700) }
    guard result == 0 else {
      let error: OwnedMCPFixtureRootError = errno == EEXIST ? .childCollision : .filesystemFailure
      if logs { emit("create", "failed", kind: kind, basename: basename, reason: error.rawValue) }
      throw error
    }
    do {
      let child = try openDirectoryChild(root.parentFD, basename)
      childFD = child.fd
      childIdentity = child.identity
      guard child.identity.uid == UInt32(geteuid()), child.identity.mode == 0o700 else {
        throw OwnedMCPFixtureRootError.childNotPrivate
      }
      try afterChildCreated?()
      try verifyOwnedPaths(root, childFD, basename, child.identity, requireChild: true)
      let handle = OwnedMCPFixtureRoot(kind: kind, basename: basename, child: child, root: root)
      transferred = true
      if logs { emit("create", "ok", kind: kind, basename: basename, child: child.identity) }
      return handle
    } catch {
      if childFD >= 0, let childIdentity {
        do {
          try removeOwnedChild(
            root: root, childFD: childFD, name: basename, identity: childIdentity,
            emptyOnly: kind == .eventIPCSocket
          )
          if logs {
            emit(
              "cleanup", "ok", kind: kind, basename: basename, reason: "constructor-failure",
              child: childIdentity
            )
          }
        } catch {
          if logs {
            emit("cleanup", "failed", kind: kind, basename: basename, reason: "creation-cleanup-failed")
            emit("create", "failed", kind: kind, basename: basename, reason: "creation-cleanup-failed")
          }
          throw OwnedMCPFixtureRootError.creationCleanupFailed
        }
      }
      if logs { emit("create", "failed", kind: kind, basename: basename, reason: reason(error)) }
      throw error
    }
  }

  private static func resolveBinding(
    _ raw: String?,
    _ environment: [String: String],
    _ rootSelection: FixtureRootSelection,
    _ guardedBuild: Bool
  ) throws -> FixtureBinding? {
    guard let raw else {
      if guardedBuild { throw OwnedMCPFixtureRootError.missingBinding }
      return nil
    }
    let binding = try FixtureBinding.parse(raw)
    guard let home = environment["HOME"], home == binding.runPath + "/home",
      let tmp = environment["TMPDIR"], pathMatches(tmp, binding.temporaryPath)
    else {
      throw OwnedMCPFixtureRootError.bindingMismatch
    }
    if case .foundation(let foundationTemporaryDirectory) = rootSelection {
      guard foundationTemporaryDirectory.isFileURL,
        pathMatches(foundationTemporaryDirectory.path, binding.temporaryPath)
      else {
        throw OwnedMCPFixtureRootError.bindingMismatch
      }
    }
    return binding
  }

  private static func openFixtureRoot(
    _ binding: FixtureBinding?,
    _ rootSelection: FixtureRootSelection,
    _ logs: Bool
  ) throws -> OpenedRoot {
    guard let binding else {
      guard case .foundation(let foundationTemporaryDirectory) = rootSelection,
        foundationTemporaryDirectory.isFileURL
      else {
        throw OwnedMCPFixtureRootError.unsafeDirectory
      }
      guard let resolvedPath = foundationTemporaryDirectory.path.withCString({ realpath($0, nil) })
      else {
        throw OwnedMCPFixtureRootError.unsafeDirectory
      }
      defer { free(resolvedPath) }
      let path = String(cString: resolvedPath)
      let parent = try openDirectoryPath(path)
      return OpenedRoot(
        runFD: -1, runPath: nil, runIdentity: nil, parentFD: parent.fd, parentPath: path,
        parentIdentity: parent.identity, logsRecords: logs
      )
    }
    let run = try openDirectoryPath(binding.runPath)
    var temporaryFD: Int32 = -1
    var parentFD: Int32 = -1
    var transferred = false
    defer { if temporaryFD >= 0 { Darwin.close(temporaryFD) } }
    defer {
      if !transferred {
        if parentFD >= 0 { Darwin.close(parentFD) }
        Darwin.close(run.fd)
      }
    }
    guard run.identity == binding.runIdentity else { throw OwnedMCPFixtureRootError.identityMismatch }
    guard run.identity.uid == UInt32(geteuid()), run.identity.mode == 0o700 else {
      throw OwnedMCPFixtureRootError.rootNotPrivate
    }
    let temporary = try openDirectoryChild(run.fd, "tmp")
    temporaryFD = temporary.fd
    guard temporary.identity == binding.temporaryIdentity else {
      throw OwnedMCPFixtureRootError.identityMismatch
    }
    guard temporary.identity.uid == UInt32(geteuid()), temporary.identity.mode == 0o700 else {
      throw OwnedMCPFixtureRootError.rootNotPrivate
    }
    let pathTemporary = try openDirectoryPath(binding.temporaryPath)
    defer { Darwin.close(pathTemporary.fd) }
    guard pathTemporary.identity == temporary.identity else {
      throw OwnedMCPFixtureRootError.identityMismatch
    }
    parentFD = fcntl(temporaryFD, F_DUPFD_CLOEXEC, 0)
    guard parentFD >= 0 else { throw OwnedMCPFixtureRootError.filesystemFailure }
    transferred = true
    return OpenedRoot(
      runFD: run.fd, runPath: binding.runPath, runIdentity: binding.runIdentity,
      parentFD: parentFD, parentPath: binding.temporaryPath,
      parentIdentity: binding.temporaryIdentity, logsRecords: logs
    )
  }

  private static func openDirectoryPath(_ path: String) throws -> OpenedDirectory {
    guard isCanonicalDirectoryPath(path) else { throw OwnedMCPFixtureRootError.unsafeDirectory }
    let flags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
    var fd = Darwin.open("/", flags)
    guard fd >= 0 else { throw OwnedMCPFixtureRootError.filesystemFailure }
    for component in path.dropFirst().split(separator: "/", omittingEmptySubsequences: false) {
      let name = String(component)
      let next = name.withCString { Darwin.openat(fd, $0, flags) }
      guard next >= 0 else { Darwin.close(fd); throw OwnedMCPFixtureRootError.unsafeDirectory }
      do {
        let openedIdentity = try directoryIdentity(of: next)
        var entry = stat()
        guard name.withCString({ fstatat(fd, $0, &entry, AT_SYMLINK_NOFOLLOW) }) == 0,
          openedIdentity.matches(entry)
        else {
          throw OwnedMCPFixtureRootError.identityMismatch
        }
      } catch {
        Darwin.close(next)
        Darwin.close(fd)
        throw error
      }
      Darwin.close(fd)
      fd = next
    }
    do {
      return OpenedDirectory(fd: fd, identity: try directoryIdentity(of: fd))
    } catch {
      Darwin.close(fd)
      throw error
    }
  }

  private static func openDirectoryChild(_ parentFD: Int32, _ name: String) throws
    -> OpenedDirectory
  {
    guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else {
      throw OwnedMCPFixtureRootError.unsafeDirectory
    }
    let flags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
    let fd = name.withCString { Darwin.openat(parentFD, $0, flags) }
    guard fd >= 0 else { throw OwnedMCPFixtureRootError.unsafeDirectory }
    do {
      let identity = try directoryIdentity(of: fd)
      var entry = stat()
      guard name.withCString({ fstatat(parentFD, $0, &entry, AT_SYMLINK_NOFOLLOW) }) == 0,
        identity.matches(entry)
      else {
        throw OwnedMCPFixtureRootError.identityMismatch
      }
      return OpenedDirectory(fd: fd, identity: identity)
    } catch {
      Darwin.close(fd)
      throw error
    }
  }

  private static func directoryIdentity(of fd: Int32) throws -> DirectoryIdentity {
    var status = stat()
    guard fstat(fd, &status) == 0 else { throw OwnedMCPFixtureRootError.filesystemFailure }
    return try DirectoryIdentity(status)
  }

  private static func verifyOwnedPaths(
    _ root: OpenedRoot,
    _ childFD: Int32,
    _ name: String,
    _ child: DirectoryIdentity,
    requireChild: Bool
  ) throws {
    guard try directoryIdentity(of: root.parentFD) == root.parentIdentity else {
      throw OwnedMCPFixtureRootError.identityMismatch
    }
    let pathParent = try openDirectoryPath(root.parentPath)
    defer { Darwin.close(pathParent.fd) }
    guard pathParent.identity == root.parentIdentity else { throw OwnedMCPFixtureRootError.identityMismatch }
    if let runPath = root.runPath, let runIdentity = root.runIdentity {
      guard try directoryIdentity(of: root.runFD) == runIdentity else {
        throw OwnedMCPFixtureRootError.identityMismatch
      }
      let pathRun = try openDirectoryPath(runPath)
      defer { Darwin.close(pathRun.fd) }
      guard pathRun.identity == runIdentity else { throw OwnedMCPFixtureRootError.identityMismatch }
      let currentTemporary = try openDirectoryChild(root.runFD, "tmp")
      defer { Darwin.close(currentTemporary.fd) }
      guard currentTemporary.identity == root.parentIdentity else {
        throw OwnedMCPFixtureRootError.identityMismatch
      }
    }
    guard try directoryIdentity(of: childFD) == child else { throw OwnedMCPFixtureRootError.identityMismatch }
    var entry = stat()
    let result = name.withCString { fstatat(root.parentFD, $0, &entry, AT_SYMLINK_NOFOLLOW) }
    if requireChild {
      guard result == 0, child.matches(entry) else { throw OwnedMCPFixtureRootError.identityMismatch }
    } else {
      guard result != 0, errno == ENOENT else { throw OwnedMCPFixtureRootError.identityMismatch }
    }
  }

  private static func removeOwnedChild(
    root: OpenedRoot,
    childFD: Int32,
    name: String,
    identity: DirectoryIdentity,
    emptyOnly: Bool = false
  ) throws {
    try verifyOwnedPaths(root, childFD, name, identity, requireChild: true)
    if !emptyOnly {
      var entries = 0
      try removeContents(of: childFD, depth: 0, entries: &entries)
    }
    try verifyOwnedPaths(root, childFD, name, identity, requireChild: true)
    guard name.withCString({ unlinkat(root.parentFD, $0, AT_REMOVEDIR) }) == 0 else {
      throw OwnedMCPFixtureRootError.cleanupFailed
    }
    try verifyOwnedPaths(root, childFD, name, identity, requireChild: false)
  }

  private static func removeContents(of fd: Int32, depth: Int, entries: inout Int) throws {
    guard depth <= 16 else { throw OwnedMCPFixtureRootError.cleanupLimitExceeded }
    let duplicate = fcntl(fd, F_DUPFD_CLOEXEC, 0)
    guard duplicate >= 0 else { throw OwnedMCPFixtureRootError.filesystemFailure }
    guard let directory = fdopendir(duplicate) else {
      Darwin.close(duplicate)
      throw OwnedMCPFixtureRootError.filesystemFailure
    }
    defer { closedir(directory) }
    while true {
      errno = 0
      guard let item = readdir(directory) else {
        guard errno == 0 else { throw OwnedMCPFixtureRootError.filesystemFailure }
        return
      }
      let nameCapacity = MemoryLayout.size(ofValue: item.pointee.d_name)
      let name = withUnsafePointer(to: &item.pointee.d_name) { namePointer in
        namePointer.withMemoryRebound(to: CChar.self, capacity: nameCapacity) {
          String(cString: $0)
        }
      }
      if name == "." || name == ".." { continue }
      entries += 1
      guard entries <= 4096 else { throw OwnedMCPFixtureRootError.cleanupLimitExceeded }
      let before = try entryStatus(name, fd)
      let type = before.st_mode & S_IFMT
      if type == S_IFDIR {
        let child = try openDirectoryChild(fd, name)
        guard child.identity.matches(before) else {
          Darwin.close(child.fd)
          throw OwnedMCPFixtureRootError.identityMismatch
        }
        do {
          try removeContents(of: child.fd, depth: depth + 1, entries: &entries)
          let after = try entryStatus(name, fd)
          guard sameEntry(before, after), name.withCString({ unlinkat(fd, $0, AT_REMOVEDIR) }) == 0 else {
            throw OwnedMCPFixtureRootError.cleanupFailed
          }
        } catch {
          Darwin.close(child.fd)
          throw error
        }
        Darwin.close(child.fd)
      } else if type == S_IFREG || type == S_IFLNK {
        let after = try entryStatus(name, fd)
        guard sameEntry(before, after), name.withCString({ unlinkat(fd, $0, 0) }) == 0 else {
          throw OwnedMCPFixtureRootError.cleanupFailed
        }
      } else {
        throw OwnedMCPFixtureRootError.cleanupFailed
      }
    }
  }

  private static func entryStatus(_ name: String, _ fd: Int32) throws -> stat {
    var status = stat()
    guard name.withCString({ fstatat(fd, $0, &status, AT_SYMLINK_NOFOLLOW) }) == 0 else {
      throw OwnedMCPFixtureRootError.cleanupFailed
    }
    return status
  }

  private static func closeDescriptors(_ root: inout OpenedRoot) {
    if root.parentFD >= 0 { Darwin.close(root.parentFD); root.parentFD = -1 }
    if root.runFD >= 0 { Darwin.close(root.runFD); root.runFD = -1 }
  }

  private func closeDescriptors() {
    if childFD >= 0 { Darwin.close(childFD); childFD = -1 }
    Self.closeDescriptors(&root)
  }

  private static func emit(
    _ event: String,
    _ result: String,
    kind: OwnedMCPFixtureKind,
    basename: String? = nil,
    reason: String? = nil,
    run: DirectoryIdentity? = nil,
    tmp: DirectoryIdentity? = nil,
    child: DirectoryIdentity? = nil
  ) {
    var fields = ["event=\(event)", "result=\(result)", "pid=\(getpid())", "kind=\(kind.rawValue)"]
    if let basename { fields.append("basename=\(basename)") }
    if let reason { fields.append("reason=\(reason)") }
    for (name, identity) in [("run", run), ("tmp", tmp), ("child", child)] {
      guard let identity else { continue }
      fields += [
        "\(name)_dev=\(identity.device)", "\(name)_inode=\(identity.inode)",
        "\(name)_uid=\(identity.uid)", "\(name)_mode=\(identity.mode)",
      ]
    }
    let line = "FLECK_MCP_FIXTURE " + fields.joined(separator: " ") + "\n"
    let output = line.utf8.count <= 512 ? line : "FLECK_MCP_FIXTURE event=record result=failed reason=record-limit\n"
    outputLock.withLock { FileHandle.standardOutput.write(Data(output.utf8)) }
  }

  private static func reason(_ error: Error) -> String {
    (error as? OwnedMCPFixtureRootError)?.rawValue ?? "constructor-failure"
  }

#if FLECK_GUARDED_MCP_FIXTURES
  private static let compiledForGuardedFixtures = true
#else
  private static let compiledForGuardedFixtures = false
#endif
}

private struct OpenedDirectory {
  let fd: Int32
  let identity: DirectoryIdentity
}

private struct OpenedRoot {
  var runFD: Int32
  let runPath: String?
  let runIdentity: DirectoryIdentity?
  var parentFD: Int32
  let parentPath: String
  let parentIdentity: DirectoryIdentity
  let logsRecords: Bool
}

private func number<T: FixedWidthInteger & LosslessStringConvertible>(
  _ fields: [String: String],
  _ key: String
) throws -> T {
  guard let raw = fields[key], raw == "0" || !raw.hasPrefix("0"),
    raw.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }), let value = T(raw)
  else {
    throw OwnedMCPFixtureRootError.malformedBinding
  }
  return value
}

private func isCanonicalDirectoryPath(_ path: String) -> Bool {
  guard path.utf8.count <= 1024, path.hasPrefix("/"), path != "/", !path.hasSuffix("/"),
    path.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
  else {
    return false
  }
  return path.dropFirst().split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
    !$0.isEmpty && $0 != "." && $0 != ".."
  }
}

private func pathMatches(_ candidate: String, _ expected: String) -> Bool {
  candidate == expected || candidate == expected + "/"
}

private func withoutDirectorySeparator(_ path: String) -> String {
  path.hasSuffix("/") ? String(path.dropLast()) : path
}

private func sameEntry(_ lhs: stat, _ rhs: stat) -> Bool {
  lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino && lhs.st_uid == rhs.st_uid
    && (lhs.st_mode & 0o7777) == (rhs.st_mode & 0o7777)
    && (lhs.st_mode & S_IFMT) == (rhs.st_mode & S_IFMT)
}
