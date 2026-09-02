import CryptoKit
import Darwin
import Foundation

struct ArtifactInventoryHooks: Sendable {
  let afterInitialMetadata: (@Sendable (URL) -> Void)?
  let afterTargetComponentValidation: (@Sendable (URL) -> Void)?

  init(
    afterInitialMetadata: (@Sendable (URL) -> Void)? = nil,
    afterTargetComponentValidation: (@Sendable (URL) -> Void)? = nil
  ) {
    self.afterInitialMetadata = afterInitialMetadata
    self.afterTargetComponentValidation = afterTargetComponentValidation
  }
}

public struct ArtifactInventory: Equatable, Sendable {
  public enum EntryKind: String, Codable, Equatable, Sendable {
    case regularFile
    case symbolicLink
  }

  public struct Entry: Equatable, Sendable {
    public let relativePath: String
    public let kind: EntryKind
    public let symlinkTarget: String?
    public let sha256: String
    public let byteCount: Int64

    public init(
      relativePath: String,
      sha256: String,
      byteCount: Int64,
      kind: EntryKind = .regularFile,
      symlinkTarget: String? = nil
    ) {
      self.relativePath = relativePath
      self.kind = kind
      self.symlinkTarget = symlinkTarget
      self.sha256 = sha256
      self.byteCount = byteCount
    }
  }

  public let files: [Entry]
  public let totalInstalledBytes: Int64

  public static func collect(from root: URL) throws -> ArtifactInventory {
    try collect(from: root, hooks: ArtifactInventoryHooks())
  }

  static func collect(
    from root: URL,
    hooks: ArtifactInventoryHooks
  ) throws -> ArtifactInventory {
    let validatedRoot = try validateRoot(root)
    var state = ScanState()
    defer {
      for observation in state.targetObservations {
        Darwin.close(observation.parentDescriptor)
      }
    }
    try scanDirectory(
      validatedRoot.url,
      initialMetadata: validatedRoot.metadata,
      openDescriptor: {
        let descriptor = Darwin.open(
          validatedRoot.url.path,
          O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
          throw ArtifactInventoryError.fileChangedDuringHashing(".")
        }
        return descriptor
      },
      rootDescriptor: nil,
      rootURL: validatedRoot.url,
      directoryAncestry: [
        try identity(from: validatedRoot.metadata, relativePath: ".")
      ],
      relativePrefix: "",
      state: &state,
      hooks: hooks
    )
    try validateTargetObservations(state.targetObservations)
    state.entries.sort { unicodeScalarOrder($0.relativePath, $1.relativePath) }
    return ArtifactInventory(files: state.entries, totalInstalledBytes: state.totalInstalledBytes)
  }

  private init(files: [Entry], totalInstalledBytes: Int64) {
    self.files = files
    self.totalInstalledBytes = totalInstalledBytes
  }

  private struct ScanState {
    var entries: [Entry] = []
    var totalInstalledBytes: Int64 = 0
    var canonicalPaths = Set<String>()
    var caseInsensitivePaths = Set<String>()
    var targetObservations: [TargetObservation] = []
  }

  private struct FileIdentity: Equatable, Hashable {
    let device: UInt64
    let inode: UInt64
    let mode: UInt32
    let type: UInt32
    let size: Int64
    let modificationSeconds: Int64
    let modificationNanoseconds: Int64
    let changeSeconds: Int64
    let changeNanoseconds: Int64
  }

  private struct TargetObservation {
    let parentDescriptor: Int32
    let name: String
    let identity: FileIdentity
    let relativePath: String
  }

  private struct TargetDirectoryFrame {
    let descriptor: Int32
    let relativeComponents: [String]
    let identity: FileIdentity
  }

  private enum TargetKind {
    case regularFile
    case directory
  }

  private static func validateRoot(
    _ root: URL
  ) throws -> (url: URL, metadata: stat) {
    guard root.isFileURL, root.path.first == "/" else {
      throw ArtifactInventoryError.rootNotAbsolute(root.path)
    }

    let root = root.standardizedFileURL
    let initialMetadata = try metadata(at: root)
    let type = initialMetadata.st_mode & S_IFMT
    guard type != S_IFLNK else {
      throw ArtifactInventoryError.symbolicLink(root.path)
    }
    guard type == S_IFDIR else {
      throw ArtifactInventoryError.rootNotDirectory(root.path)
    }
    return (root, initialMetadata)
  }

  private static func scanDirectory(
    _ directory: URL,
    initialMetadata: stat,
    openDescriptor: () throws -> Int32,
    rootDescriptor: Int32?,
    rootURL: URL,
    directoryAncestry: [FileIdentity],
    relativePrefix: String,
    state: inout ScanState,
    hooks: ArtifactInventoryHooks
  ) throws {
    let directoryIdentity = try identity(
      from: initialMetadata,
      relativePath: relativePrefix.isEmpty ? "." : relativePrefix
    )
    hooks.afterInitialMetadata?(directory)
    let directoryDescriptor = try openDescriptor()
    defer { Darwin.close(directoryDescriptor) }
    let effectiveRootDescriptor = rootDescriptor ?? directoryDescriptor
    let rootIdentity = directoryAncestry[0]
    try requireIdentity(
      at: directoryDescriptor,
      expected: directoryIdentity,
      relativePath: relativePrefix.isEmpty ? "." : relativePrefix
    )
    try requireIdentity(
      at: directory,
      expected: directoryIdentity,
      relativePath: relativePrefix.isEmpty ? "." : relativePrefix
    )

    let children = try directoryEntries(
      from: directoryDescriptor,
      path: directory.path
    )
    try requireIdentity(
      at: directoryDescriptor,
      expected: directoryIdentity,
      relativePath: relativePrefix.isEmpty ? "." : relativePrefix
    )
    try requireIdentity(
      at: directory,
      expected: directoryIdentity,
      relativePath: relativePrefix.isEmpty ? "." : relativePrefix
    )

    for childName in children {
      try requireIdentity(
        at: directoryDescriptor,
        expected: directoryIdentity,
        relativePath: relativePrefix.isEmpty ? "." : relativePrefix
      )

      let relativePath = relativePrefix.isEmpty
        ? childName
        : relativePrefix + "/" + childName
      try validateRelativePath(relativePath)
      try register(relativePath, state: &state)

      var childMetadata = stat()
      guard Darwin.fstatat(
        directoryDescriptor,
        childName,
        &childMetadata,
        AT_SYMLINK_NOFOLLOW
      ) == 0 else {
        throw ArtifactInventoryError.fileChangedDuringHashing(relativePath)
      }
      let childIdentity = try identity(from: childMetadata, relativePath: relativePath)
      let type = childMetadata.st_mode & S_IFMT
      let child = directory.appendingPathComponent(childName, isDirectory: type == S_IFDIR)
      if type == S_IFDIR {
        try scanDirectory(
          child,
          initialMetadata: childMetadata,
          openDescriptor: {
            let descriptor = Darwin.openat(
              directoryDescriptor,
              childName,
              O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            guard descriptor >= 0 else {
              throw ArtifactInventoryError.fileChangedDuringHashing(relativePath)
            }
            return descriptor
          },
          rootDescriptor: effectiveRootDescriptor,
          rootURL: rootURL,
          directoryAncestry: directoryAncestry + [childIdentity],
          relativePrefix: relativePath,
          state: &state,
          hooks: hooks
        )
        continue
      }

      hooks.afterInitialMetadata?(child)
      try requireIdentity(
        at: directoryDescriptor,
        name: childName,
        expected: childIdentity,
        relativePath: relativePath
      )
      if type == S_IFLNK {
        let entry = try inventorySymlink(
          parentDescriptor: directoryDescriptor,
          childName: childName,
          initialIdentity: childIdentity,
          parentIdentity: directoryIdentity,
          rootDescriptor: effectiveRootDescriptor,
          rootIdentity: rootIdentity,
          rootURL: rootURL,
          ancestorIdentities: directoryAncestry,
          hooks: hooks,
          state: &state,
          relativePath: relativePath
        )
        state.entries.append(entry)
        try addBytes(entry.byteCount, to: &state.totalInstalledBytes)
        continue
      }
      guard type == S_IFREG else {
        throw ArtifactInventoryError.specialFile(relativePath)
      }

      let entry = try hashFile(
        parentDescriptor: directoryDescriptor,
        childName: childName,
        initialIdentity: childIdentity,
        parentIdentity: directoryIdentity,
        relativePath: relativePath
      )
      state.entries.append(entry)
      try addBytes(entry.byteCount, to: &state.totalInstalledBytes)
    }

    try requireIdentity(
      at: directoryDescriptor,
      expected: directoryIdentity,
      relativePath: relativePrefix.isEmpty ? "." : relativePrefix
    )
    try requireIdentity(
      at: directory,
      expected: directoryIdentity,
      relativePath: relativePrefix.isEmpty ? "." : relativePrefix
    )
  }

  private static func directoryEntries(
    from descriptor: Int32,
    path: String
  ) throws -> [String] {
    let duplicate = Darwin.dup(descriptor)
    guard duplicate >= 0 else {
      throw ArtifactInventoryError.directoryEnumerationFailed(path)
    }
    guard let stream = Darwin.fdopendir(duplicate) else {
      Darwin.close(duplicate)
      throw ArtifactInventoryError.directoryEnumerationFailed(path)
    }
    defer { Darwin.closedir(stream) }

    var names: [String] = []
    errno = 0
    while let entry = Darwin.readdir(stream) {
      let name = withUnsafePointer(to: &entry.pointee.d_name) {
        $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen)) {
          String(cString: $0)
        }
      }
      guard name != ".", name != ".." else { continue }
      names.append(name)
    }
    guard errno == 0 else {
      throw ArtifactInventoryError.directoryEnumerationFailed(path)
    }
    names.sort(by: unicodeScalarOrder)
    return names
  }

  private static func register(_ relativePath: String, state: inout ScanState) throws {
    let normalizedComponents = relativePath
      .split(separator: "/", omittingEmptySubsequences: false)
      .map { String($0).precomposedStringWithCanonicalMapping }
    let canonicalPath = normalizedComponents.joined(separator: "/")
    guard state.canonicalPaths.insert(canonicalPath).inserted else {
      throw ArtifactInventoryError.duplicateRelativePath(relativePath)
    }

    let caseInsensitivePath = normalizedComponents
      .map { $0.lowercased() }
      .joined(separator: "/")
    guard state.caseInsensitivePaths.insert(caseInsensitivePath).inserted else {
      throw ArtifactInventoryError.caseCollidingRelativePath(relativePath)
    }
  }

  private static func validateRelativePath(_ path: String) throws {
    let components = path.split(separator: "/", omittingEmptySubsequences: false)
    guard !path.isEmpty,
      !path.hasPrefix("/"),
      !path.hasSuffix("/"),
      !components.isEmpty,
      components.allSatisfy({ $0 != "." && $0 != ".." }),
      !path.unicodeScalars.contains(where: { scalar in
        scalar == "\0" || scalar == "\n" || scalar == "\r"
      })
    else {
      throw ArtifactInventoryError.unsafeRelativePath(path)
    }
  }

  private static func preservedSymlinkTarget(
    _ target: String,
    relativePath: String
  ) throws -> String {
    guard !target.isEmpty,
      !target.hasPrefix("/"),
      !target.unicodeScalars.contains(where: { scalar in
        scalar == "\0" || scalar == "\n" || scalar == "\r"
      })
    else {
      throw ArtifactInventoryError.invalidSymlink(relativePath)
    }

    var components = relativePath
      .split(separator: "/", omittingEmptySubsequences: true)
      .dropLast()
      .map(String.init)
    for component in target.split(separator: "/", omittingEmptySubsequences: false) {
      guard !component.isEmpty else {
        throw ArtifactInventoryError.invalidSymlink(relativePath)
      }
      components.append(String(component))
    }
    return components.joined(separator: "/")
  }

  private static func inventorySymlink(
    parentDescriptor: Int32,
    childName: String,
    initialIdentity: FileIdentity,
    parentIdentity: FileIdentity,
    rootDescriptor: Int32,
    rootIdentity: FileIdentity,
    rootURL: URL,
    ancestorIdentities: [FileIdentity],
    hooks: ArtifactInventoryHooks,
    state: inout ScanState,
    relativePath: String
  ) throws -> Entry {
    try requireIdentity(
      at: parentDescriptor,
      expected: parentIdentity,
      relativePath: parentPath(relativePath)
    )
    let target = try readSymlinkTarget(
      from: parentDescriptor,
      childName: childName,
      relativePath: relativePath
    )
    try retainTargetObservation(
      parentDescriptor: parentDescriptor,
      name: childName,
      identity: initialIdentity,
      relativePath: relativePath,
      state: &state
    )
    let targetPath = try preservedSymlinkTarget(target, relativePath: relativePath)
    let resolvedTarget = try resolveTarget(
      targetPath: targetPath,
      rootDescriptor: rootDescriptor,
      rootIdentity: rootIdentity,
      rootURL: rootURL,
      relativePath: relativePath,
      hooks: hooks,
      state: &state
    )
    if resolvedTarget.kind == .directory,
      ancestorIdentities.contains(resolvedTarget.identity) {
      throw ArtifactInventoryError.invalidSymlink(relativePath)
    }
    try validateTargetObservations(state.targetObservations)
    try requireIdentity(at: rootDescriptor, expected: rootIdentity, relativePath: relativePath)
    try requireIdentity(
      at: parentDescriptor,
      name: childName,
      expected: initialIdentity,
      relativePath: relativePath
    )
    try requireIdentity(
      at: parentDescriptor,
      expected: parentIdentity,
      relativePath: parentPath(relativePath)
    )

    let data = Data(target.utf8)
    return Entry(
      relativePath: relativePath,
      sha256: digest(data),
      byteCount: Int64(data.count),
      kind: .symbolicLink,
      symlinkTarget: target
    )
  }

  private static func resolveTarget(
    targetPath: String,
    rootDescriptor: Int32,
    rootIdentity: FileIdentity,
    rootURL: URL,
    relativePath: String,
    hooks: ArtifactInventoryHooks,
    state: inout ScanState
  ) throws -> (kind: TargetKind, identity: FileIdentity) {
    let rootCopy = Darwin.dup(rootDescriptor)
    guard rootCopy >= 0 else {
      throw ArtifactInventoryError.fileChangedDuringHashing(relativePath)
    }
    var frames = [
      TargetDirectoryFrame(
        descriptor: rootCopy,
        relativeComponents: [],
        identity: rootIdentity
      )
    ]
    defer {
      for frame in frames {
        Darwin.close(frame.descriptor)
      }
    }

    var pending = targetPath.isEmpty
      ? []
      : targetPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    var followedSymlinks = Set<FileIdentity>()

    while !pending.isEmpty {
      let component = pending.removeFirst()
      guard !component.isEmpty else {
        throw ArtifactInventoryError.invalidSymlink(relativePath)
      }
      if component == "." {
        continue
      }
      if component == ".." {
        guard frames.count > 1 else {
          throw ArtifactInventoryError.invalidSymlink(relativePath)
        }
        let frame = frames.removeLast()
        Darwin.close(frame.descriptor)
        continue
      }

      let frame = frames[frames.count - 1]
      try requireIdentity(at: frame.descriptor, expected: frame.identity, relativePath: relativePath)
      var componentMetadata = stat()
      guard Darwin.fstatat(
        frame.descriptor,
        component,
        &componentMetadata,
        AT_SYMLINK_NOFOLLOW
      ) == 0,
        let componentIdentity = fileIdentity(from: componentMetadata)
      else {
        throw ArtifactInventoryError.invalidSymlink(relativePath)
      }

      let componentPath = frame.relativeComponents + [component]
      let componentRelativePath = componentPath.joined(separator: "/")
      let componentURL = rootURL.appendingPathComponent(componentRelativePath)
      let componentType = componentMetadata.st_mode & S_IFMT
      if componentType == S_IFLNK {
        guard followedSymlinks.insert(componentIdentity).inserted else {
          throw ArtifactInventoryError.invalidSymlink(relativePath)
        }
        let target = try readSymlinkTarget(
          from: frame.descriptor,
          childName: component,
          relativePath: relativePath
        )
        let targetComponents = try symlinkTargetComponents(
          target,
          relativePath: relativePath
        )
        try retainTargetObservation(
          parentDescriptor: frame.descriptor,
          name: component,
          identity: componentIdentity,
          relativePath: relativePath,
          state: &state
        )
        hooks.afterTargetComponentValidation?(componentURL)
        try validateTargetObservations(state.targetObservations)
        try requireIdentity(
          at: frame.descriptor,
          name: component,
          expected: componentIdentity,
          relativePath: relativePath
        )
        pending = targetComponents + pending
        continue
      }

      guard componentType == S_IFREG || componentType == S_IFDIR else {
        throw ArtifactInventoryError.invalidSymlink(relativePath)
      }
      let isFinal = pending.isEmpty
      if !isFinal {
        guard componentType == S_IFDIR else {
          throw ArtifactInventoryError.invalidSymlink(relativePath)
        }
        let childDescriptor = try openTargetDescriptor(
          parentDescriptor: frame.descriptor,
          name: component,
          identity: componentIdentity,
          type: UInt32(S_IFDIR),
          relativePath: relativePath
        )
        frames.append(
          TargetDirectoryFrame(
            descriptor: childDescriptor,
            relativeComponents: componentPath,
            identity: componentIdentity
          )
        )
        try retainTargetObservation(
          parentDescriptor: frame.descriptor,
          name: component,
          identity: componentIdentity,
          relativePath: relativePath,
          state: &state
        )
        hooks.afterTargetComponentValidation?(componentURL)
        try validateTargetObservations(state.targetObservations)
        try requireIdentity(
          at: frame.descriptor,
          name: component,
          expected: componentIdentity,
          relativePath: relativePath
        )
        try requireIdentity(
          at: childDescriptor,
          expected: componentIdentity,
          relativePath: relativePath
        )
        continue
      }

      let targetDescriptor = try openTargetDescriptor(
        parentDescriptor: frame.descriptor,
        name: component,
        identity: componentIdentity,
        type: UInt32(componentType),
        relativePath: relativePath
      )
      do {
        defer { Darwin.close(targetDescriptor) }
        try retainTargetObservation(
          parentDescriptor: frame.descriptor,
          name: component,
          identity: componentIdentity,
          relativePath: relativePath,
          state: &state
        )
        hooks.afterTargetComponentValidation?(componentURL)
        try validateTargetObservations(state.targetObservations)
        try requireIdentity(
          at: frame.descriptor,
          name: component,
          expected: componentIdentity,
          relativePath: relativePath
        )
        try requireIdentity(
          at: targetDescriptor,
          expected: componentIdentity,
          relativePath: relativePath
        )
      }
      return (
        kind: componentType == S_IFDIR ? .directory : .regularFile,
        identity: componentIdentity
      )
    }

    try requireIdentity(at: rootDescriptor, expected: rootIdentity, relativePath: relativePath)
    return (kind: .directory, identity: frames[frames.count - 1].identity)
  }

  private static func symlinkTargetComponents(
    _ target: String,
    relativePath: String
  ) throws -> [String] {
    guard !target.isEmpty,
      !target.hasPrefix("/"),
      !target.unicodeScalars.contains(where: { scalar in
        scalar == "\0" || scalar == "\n" || scalar == "\r"
      })
    else {
      throw ArtifactInventoryError.invalidSymlink(relativePath)
    }
    let components = target
      .split(separator: "/", omittingEmptySubsequences: false)
      .map(String.init)
    guard components.allSatisfy({ !$0.isEmpty }) else {
      throw ArtifactInventoryError.invalidSymlink(relativePath)
    }
    return components
  }

  private static func retainTargetObservation(
    parentDescriptor: Int32,
    name: String,
    identity: FileIdentity,
    relativePath: String,
    state: inout ScanState
  ) throws {
    let retainedDescriptor = Darwin.dup(parentDescriptor)
    guard retainedDescriptor >= 0 else {
      throw ArtifactInventoryError.fileChangedDuringHashing(relativePath)
    }
    state.targetObservations.append(
      TargetObservation(
        parentDescriptor: retainedDescriptor,
        name: name,
        identity: identity,
        relativePath: relativePath
      )
    )
  }

  private static func validateTargetObservations(
    _ observations: [TargetObservation]
  ) throws {
    for observation in observations {
      try requireIdentity(
        at: observation.parentDescriptor,
        name: observation.name,
        expected: observation.identity,
        relativePath: observation.relativePath
      )
    }
  }

  private static func openTargetDescriptor(
    parentDescriptor: Int32,
    name: String,
    identity: FileIdentity,
    type: UInt32,
    relativePath: String
  ) throws -> Int32 {
    let flags = type == S_IFDIR
      ? O_RDONLY | O_DIRECTORY | O_NOFOLLOW
      : O_RDONLY | O_NOFOLLOW
    let descriptor = Darwin.openat(parentDescriptor, name, flags)
    guard descriptor >= 0 else {
      if let currentIdentity = currentIdentity(at: parentDescriptor, name: name),
        currentIdentity != identity {
        throw ArtifactInventoryError.fileChangedDuringHashing(relativePath)
      }
      throw ArtifactInventoryError.invalidSymlink(relativePath)
    }

    var openedMetadata = stat()
    guard Darwin.fstat(descriptor, &openedMetadata) == 0,
      let openedIdentity = fileIdentity(from: openedMetadata),
      openedIdentity == identity,
      openedIdentity.type == type
    else {
      Darwin.close(descriptor)
      throw ArtifactInventoryError.fileChangedDuringHashing(relativePath)
    }
    return descriptor
  }

  private static func readSymlinkTarget(
    from parentDescriptor: Int32,
    childName: String,
    relativePath: String
  ) throws -> String {
    var bytes = [UInt8](repeating: 0, count: Int(PATH_MAX))
    let length = bytes.withUnsafeMutableBytes { rawBuffer in
      Darwin.readlinkat(
        parentDescriptor,
        childName,
        rawBuffer.bindMemory(to: CChar.self).baseAddress,
        rawBuffer.count
      )
    }
    guard length > 0, length < bytes.count else {
      throw ArtifactInventoryError.invalidSymlink(relativePath)
    }
    let targetData = Data(bytes[0..<Int(length)])
    guard let target = String(data: targetData, encoding: .utf8) else {
      throw ArtifactInventoryError.invalidSymlink(relativePath)
    }
    return target
  }

  private static func hashFile(
    parentDescriptor: Int32,
    childName: String,
    initialIdentity: FileIdentity,
    parentIdentity: FileIdentity,
    relativePath: String
  ) throws -> Entry {
    try requireIdentity(
      at: parentDescriptor,
      expected: parentIdentity,
      relativePath: parentPath(relativePath)
    )
    let descriptor = Darwin.openat(
      parentDescriptor,
      childName,
      O_RDONLY | O_NOFOLLOW
    )
    guard descriptor >= 0 else {
      if let currentIdentity = currentIdentity(
        at: parentDescriptor,
        name: childName
      ),
        currentIdentity != initialIdentity {
        throw ArtifactInventoryError.fileChangedDuringHashing(relativePath)
      }
      throw ArtifactInventoryError.unreadableFile(relativePath)
    }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    defer { try? handle.close() }

    var openedMetadata = stat()
    guard Darwin.fstat(descriptor, &openedMetadata) == 0,
      let openedIdentity = fileIdentity(from: openedMetadata),
      openedIdentity == initialIdentity,
      openedIdentity.type == UInt32(S_IFREG)
    else {
      throw ArtifactInventoryError.fileChangedDuringHashing(relativePath)
    }

    var hasher = SHA256()
    var readByteCount: Int64 = 0
    do {
      while true {
        guard let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty else {
          break
        }
        let (nextByteCount, overflow) = readByteCount.addingReportingOverflow(Int64(chunk.count))
        guard !overflow else {
          throw ArtifactInventoryError.fileChangedDuringHashing(relativePath)
        }
        readByteCount = nextByteCount
        hasher.update(data: chunk)
        try ensureIdentity(descriptor, expected: initialIdentity, relativePath: relativePath)
      }
    } catch let error as ArtifactInventoryError {
      throw error
    } catch {
      throw ArtifactInventoryError.unreadableFile(relativePath)
    }

    var finalMetadata = stat()
    guard Darwin.fstat(descriptor, &finalMetadata) == 0,
      let finalIdentity = fileIdentity(from: finalMetadata),
      finalIdentity == initialIdentity,
      readByteCount == initialIdentity.size
    else {
      throw ArtifactInventoryError.fileChangedDuringHashing(relativePath)
    }
    try requireIdentity(
      at: parentDescriptor,
      name: childName,
      expected: initialIdentity,
      relativePath: relativePath
    )
    try requireIdentity(
      at: parentDescriptor,
      expected: parentIdentity,
      relativePath: parentPath(relativePath)
    )

    return Entry(
      relativePath: relativePath,
      sha256: hasher.finalize().map { String(format: "%02x", $0) }.joined(),
      byteCount: initialIdentity.size
    )
  }

  private static func addBytes(_ byteCount: Int64, to total: inout Int64) throws {
    let (nextTotal, overflow) = total.addingReportingOverflow(byteCount)
    guard !overflow else {
      throw ArtifactInventoryError.totalInstalledBytesOverflow
    }
    total = nextTotal
  }

  private static func ensureIdentity(
    _ descriptor: Int32,
    expected: FileIdentity,
    relativePath: String
  ) throws {
    var currentMetadata = stat()
    guard Darwin.fstat(descriptor, &currentMetadata) == 0,
      let currentIdentity = fileIdentity(from: currentMetadata),
      currentIdentity == expected
    else {
      throw ArtifactInventoryError.fileChangedDuringHashing(relativePath)
    }
  }

  private static func requireIdentity(
    at url: URL,
    expected: FileIdentity,
    relativePath: String
  ) throws {
    guard let currentMetadata = try? metadata(at: url),
      let currentIdentity = fileIdentity(from: currentMetadata),
      currentIdentity == expected
    else {
      throw ArtifactInventoryError.fileChangedDuringHashing(relativePath)
    }
  }

  private static func requireIdentity(
    at descriptor: Int32,
    expected: FileIdentity,
    relativePath: String
  ) throws {
    var currentMetadata = stat()
    guard Darwin.fstat(descriptor, &currentMetadata) == 0,
      let currentIdentity = fileIdentity(from: currentMetadata),
      currentIdentity == expected
    else {
      throw ArtifactInventoryError.fileChangedDuringHashing(relativePath)
    }
  }

  private static func requireIdentity(
    at descriptor: Int32,
    name: String,
    expected: FileIdentity,
    relativePath: String
  ) throws {
    guard let value = currentIdentity(at: descriptor, name: name), value == expected else {
      throw ArtifactInventoryError.fileChangedDuringHashing(relativePath)
    }
  }

  private static func currentIdentity(
    at descriptor: Int32,
    name: String
  ) -> FileIdentity? {
    var currentMetadata = stat()
    guard Darwin.fstatat(
      descriptor,
      name,
      &currentMetadata,
      AT_SYMLINK_NOFOLLOW
    ) == 0 else {
      return nil
    }
    return fileIdentity(from: currentMetadata)
  }

  private static func metadata(at url: URL) throws -> stat {
    var result = stat()
    guard Darwin.lstat(url.path, &result) == 0 else {
      throw ArtifactInventoryError.unreadableFile(url.path)
    }
    return result
  }

  private static func identity(
    from metadata: stat,
    relativePath: String
  ) throws -> FileIdentity {
    guard let value = fileIdentity(from: metadata) else {
      throw ArtifactInventoryError.fileChangedDuringHashing(relativePath)
    }
    return value
  }

  private static func fileIdentity(from metadata: stat) -> FileIdentity? {
    guard let size = Int64(exactly: metadata.st_size), size >= 0 else {
      return nil
    }
    return FileIdentity(
      device: UInt64(metadata.st_dev),
      inode: UInt64(metadata.st_ino),
      mode: UInt32(metadata.st_mode),
      type: UInt32(metadata.st_mode & S_IFMT),
      size: size,
      modificationSeconds: Int64(metadata.st_mtimespec.tv_sec),
      modificationNanoseconds: Int64(metadata.st_mtimespec.tv_nsec),
      changeSeconds: Int64(metadata.st_ctimespec.tv_sec),
      changeNanoseconds: Int64(metadata.st_ctimespec.tv_nsec)
    )
  }

  private static func parentPath(_ relativePath: String) -> String {
    let parent = relativePath.split(separator: "/").dropLast().joined(separator: "/")
    return parent.isEmpty ? "." : parent
  }

  private static func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func unicodeScalarOrder(_ lhs: String, _ rhs: String) -> Bool {
    let lhsScalars = lhs.unicodeScalars.map(\.value)
    let rhsScalars = rhs.unicodeScalars.map(\.value)
    for (left, right) in zip(lhsScalars, rhsScalars) where left != right {
      return left < right
    }
    return lhsScalars.count < rhsScalars.count
  }
}

public enum ArtifactInventoryError: Error, Equatable, Sendable, CustomStringConvertible {
  case rootNotAbsolute(String)
  case rootNotDirectory(String)
  case symbolicLink(String)
  case specialFile(String)
  case unsafeRelativePath(String)
  case duplicateRelativePath(String)
  case caseCollidingRelativePath(String)
  case invalidSymlink(String)
  case unreadableFile(String)
  case fileChangedDuringHashing(String)
  case totalInstalledBytesOverflow
  case directoryEnumerationFailed(String)

  public var description: String {
    switch self {
    case .rootNotAbsolute(let path): return "artifact root is not absolute: \(path)"
    case .rootNotDirectory(let path): return "artifact root is not a directory: \(path)"
    case .symbolicLink(let path): return "symbolic link is not allowed: \(path)"
    case .specialFile(let path): return "special file is not allowed: \(path)"
    case .unsafeRelativePath(let path): return "unsafe relative artifact path: \(path)"
    case .duplicateRelativePath(let path): return "duplicate artifact path: \(path)"
    case .caseCollidingRelativePath(let path):
      return "case-colliding artifact path: \(path)"
    case .invalidSymlink(let path): return "invalid symbolic link: \(path)"
    case .unreadableFile(let path): return "artifact file is unreadable: \(path)"
    case .fileChangedDuringHashing(let path):
      return "artifact path changed during inventory: \(path)"
    case .totalInstalledBytesOverflow: return "artifact byte total overflow"
    case .directoryEnumerationFailed(let path):
      return "artifact directory could not be enumerated: \(path)"
    }
  }
}
