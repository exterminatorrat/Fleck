import CryptoKit
import Darwin
import Foundation
import Testing
@testable import LocalDictationCandidateRunner

private final class TemporaryDirectory {
  let url: URL

  init() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("local-dictation-artifact-inventory-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    url = directory
  }

  deinit {
    try? FileManager.default.removeItem(at: url)
  }

  func write(_ relativePath: String, _ contents: String) throws {
    let fileURL = url.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data(contents.utf8).write(to: fileURL)
  }

  func symlink(_ relativePath: String, target: String) throws {
    let linkURL = url.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(
      at: linkURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try FileManager.default.createSymbolicLink(
      atPath: linkURL.path,
      withDestinationPath: target
    )
  }
}

private func sha256(_ value: String) -> String {
  SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
}

private final class OneShotMutation: @unchecked Sendable {
  private let lock = NSLock()
  private var hasRun = false

  func run(_ mutation: () -> Void) {
    lock.lock()
    guard !hasRun else {
      lock.unlock()
      return
    }
    hasRun = true
    lock.unlock()
    mutation()
  }
}

private func capturedInventoryError(
  _ operation: () throws -> Void
) -> ArtifactInventoryError? {
  do {
    try operation()
    return nil
  } catch let error as ArtifactInventoryError {
    return error
  } catch {
    Issue.record("unexpected error: \(error)")
    return nil
  }
}

@Suite("ArtifactInventoryTests")
struct ArtifactInventoryTests {

  @Test func inventoriesRegularFilesSortedAndHashedIncludingPackageContents() throws {
    let directory = try TemporaryDirectory()
    try directory.write("zeta.txt", "z")
    try directory.write("nested/alpha.txt", "alpha")
    try directory.write("ignored.bundle/inside.txt", "must not be inventoried")

    let inventory = try ArtifactInventory.collect(from: directory.url)

    #expect(
      inventory.files.map(\.relativePath) == [
        "ignored.bundle/inside.txt",
        "nested/alpha.txt",
        "zeta.txt",
      ]
    )
    #expect(inventory.files.map(\.byteCount) == [23, 5, 1])
    #expect(
      inventory.files.map(\.sha256) == [
        sha256("must not be inventoried"),
        sha256("alpha"),
        sha256("z"),
      ]
    )
    #expect(inventory.totalInstalledBytes == 29)
  }

  @Test func inventoriesInternalFrameworkSymlinksAsTargetBytes() throws {
    let directory = try TemporaryDirectory()
    try directory.write(
      "Runtime.xcframework/ios-arm64/Runtime.framework/Versions/A/Runtime",
      "binary"
    )
    try directory.symlink(
      "Runtime.xcframework/ios-arm64/Runtime.framework/Versions/Current",
      target: "A"
    )
    try directory.symlink(
      "Runtime.xcframework/ios-arm64/Runtime.framework/Runtime",
      target: "Versions/Current/Runtime"
    )

    let inventory = try ArtifactInventory.collect(from: directory.url)
    let entries = Dictionary(
      uniqueKeysWithValues: inventory.files.map { ($0.relativePath, $0) }
    )
    let currentPath =
      "Runtime.xcframework/ios-arm64/Runtime.framework/Versions/Current"
    let binaryLinkPath = "Runtime.xcframework/ios-arm64/Runtime.framework/Runtime"

    #expect(entries[currentPath]?.kind == .symbolicLink)
    #expect(entries[currentPath]?.symlinkTarget == "A")
    #expect(entries[currentPath]?.byteCount == 1)
    #expect(entries[currentPath]?.sha256 == sha256("A"))
    #expect(entries[binaryLinkPath]?.kind == .symbolicLink)
    #expect(entries[binaryLinkPath]?.symlinkTarget == "Versions/Current/Runtime")
    #expect(entries[binaryLinkPath]?.byteCount == 24)
    #expect(entries[binaryLinkPath]?.sha256 == sha256("Versions/Current/Runtime"))
    #expect(entries[
      "Runtime.xcframework/ios-arm64/Runtime.framework/Versions/A/Runtime"
    ]?.kind == .regularFile)
  }

  @Test func inventoriesValidSymlinkAndRejectsSpecialFiles() throws {
    let directory = try TemporaryDirectory()
    try directory.write("target.txt", "target")

    try directory.symlink("alias.txt", target: "target.txt")
    let inventory = try ArtifactInventory.collect(from: directory.url)
    let alias = inventory.files.first { $0.relativePath == "alias.txt" }
    #expect(alias?.kind == .symbolicLink)
    #expect(alias?.symlinkTarget == "target.txt")
    #expect(alias?.byteCount == 10)

    try FileManager.default.removeItem(at: directory.url.appendingPathComponent("alias.txt"))
    let fifo = directory.url.appendingPathComponent("named-pipe")
    #expect(Darwin.mkfifo(fifo.path, 0o600) == 0)
    defer { _ = Darwin.unlink(fifo.path) }
    #expect(throws: ArtifactInventoryError.self) {
      try ArtifactInventory.collect(from: directory.url)
    }
  }

  @Test func rejectsAbsoluteEscapingDanglingAndCyclicSymlinks() throws {
    for (name, target) in [
      ("absolute", "/outside"),
      ("escaping", "../../outside"),
      ("dangling", "missing"),
    ] {
      let directory = try TemporaryDirectory()
      try directory.symlink(name, target: target)
      #expect(throws: ArtifactInventoryError.self) {
        try ArtifactInventory.collect(from: directory.url)
      }
    }

    let cyclicDirectory = try TemporaryDirectory()
    try cyclicDirectory.symlink("a", target: "b")
    try cyclicDirectory.symlink("b", target: "a")
    #expect(throws: ArtifactInventoryError.self) {
      try ArtifactInventory.collect(from: cyclicDirectory.url)
    }

    let specialDirectory = try TemporaryDirectory()
    let fifo = specialDirectory.url.appendingPathComponent("z-named-pipe")
    #expect(Darwin.mkfifo(fifo.path, 0o600) == 0)
    defer { _ = Darwin.unlink(fifo.path) }
    try specialDirectory.symlink("a-special-link", target: "z-named-pipe")
    let error = capturedInventoryError {
      _ = try ArtifactInventory.collect(from: specialDirectory.url)
    }
    #expect(error == .invalidSymlink("a-special-link"))
  }

  @Test func rejectsSymlinkToAncestorDirectory() throws {
    let directory = try TemporaryDirectory()
    try directory.write("subdir/file.txt", "inside")
    try directory.symlink("subdir/loop", target: "..")

    let error = capturedInventoryError {
      _ = try ArtifactInventory.collect(from: directory.url)
    }

    #expect(error == .invalidSymlink("subdir/loop"))
  }

  @Test func rejectsSymlinkThenParentTargetThatIsDangling() throws {
    let directory = try TemporaryDirectory()
    try directory.write("dir/sub/inside.txt", "inside")
    try directory.write("safe", "safe")
    try directory.symlink("linkdir", target: "dir/sub")
    try directory.symlink("alias", target: "linkdir/../safe")

    let error = capturedInventoryError {
      _ = try ArtifactInventory.collect(from: directory.url)
    }

    #expect(error == .invalidSymlink("alias"))
  }

  @Test func rejectsTargetComponentReplacementAfterValidation() throws {
    let directory = try TemporaryDirectory()
    let outside = try TemporaryDirectory()
    try directory.write("target/nested.txt", "inside")
    try outside.write("nested.txt", "outside")

    let targetURL = directory.url.appendingPathComponent("target")
    let outsideURL = outside.url
    try directory.symlink("alias", target: "target/nested.txt")
    let mutation = OneShotMutation()
    let hooks = ArtifactInventoryHooks(afterTargetComponentValidation: { url in
      guard url == targetURL else { return }
      mutation.run {
        try? FileManager.default.removeItem(at: targetURL)
        try? FileManager.default.createSymbolicLink(
          at: targetURL,
          withDestinationURL: outsideURL
        )
      }
    })

    let error = capturedInventoryError {
      _ = try ArtifactInventory.collect(from: directory.url, hooks: hooks)
    }

    #expect(error == .fileChangedDuringHashing("alias"))
  }

  @Test func rejectsDirectoryReplacementWithOutsideSymlinkBeforeRecursion() throws {
    let directory = try TemporaryDirectory()
    let outside = try TemporaryDirectory()
    try outside.write("outside.txt", "outside bytes")
    try directory.write("checked/inside.txt", "inside bytes")
    let outsideURL = outside.url
    let mutation = OneShotMutation()
    let hooks = ArtifactInventoryHooks(afterInitialMetadata: { url in
      guard url.lastPathComponent == "checked" else { return }
      mutation.run {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.createSymbolicLink(at: url, withDestinationURL: outsideURL)
      }
    })

    let error = capturedInventoryError {
      _ = try ArtifactInventory.collect(from: directory.url, hooks: hooks)
    }

    #expect(error == .fileChangedDuringHashing("checked"))
  }

  @Test func rejectsSameSizeFileReplacementBeforeOpen() throws {
    let directory = try TemporaryDirectory()
    try directory.write("checked.txt", "content")
    let mutation = OneShotMutation()
    let hooks = ArtifactInventoryHooks(afterInitialMetadata: { url in
      guard url.lastPathComponent == "checked.txt" else { return }
      mutation.run {
        try? Data("changed".utf8).write(to: url, options: .atomic)
      }
    })

    let error = capturedInventoryError {
      _ = try ArtifactInventory.collect(from: directory.url, hooks: hooks)
    }

    #expect(error == .fileChangedDuringHashing("checked.txt"))
  }

  @Test func rejectsRelativeAndMissingRoots() throws {
    #expect(throws: ArtifactInventoryError.self) {
      try ArtifactInventory.collect(from: URL(fileURLWithPath: "relative-root"))
    }

    let missing = FileManager.default.temporaryDirectory
      .appendingPathComponent("missing-artifact-inventory-\(UUID().uuidString)")
    #expect(throws: ArtifactInventoryError.self) {
      try ArtifactInventory.collect(from: missing)
    }
  }
}
