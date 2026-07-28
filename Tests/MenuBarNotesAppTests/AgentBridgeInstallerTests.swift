import CryptoKit
import Foundation
import Testing

@testable import MenuBarNotesApp

@Suite("AgentBridgeInstaller")
struct AgentBridgeInstallerTests {
  @Test func installsVerifiedBundledHelperAtStableAbsolutePath() throws {
    let fileSystem = FakeInstallerFileSystem()
    let bundle = URL(fileURLWithPath: "/Motes.app/Contents/SharedSupport/motes-agent")
    let support = URL(fileURLWithPath: "/Users/test/Library/Application Support/MenuBarNotes")
    let helper = Data("verified helper".utf8)
    fileSystem.files[bundle.path] = helper
    let installer = AgentBridgeInstaller(
      bundledHelperURL: bundle,
      applicationSupportURL: support,
      fileSystem: fileSystem,
      processRunner: RecordingAgentProcessRunner()
    )

    let installed = try installer.install()
    let expected = support.appendingPathComponent("AgentBridge/bin/motes")

    #expect(installed == expected)
    #expect(installed.path.hasPrefix("/"))
    #expect(fileSystem.files[expected.path] == helper)
    #expect(try installer.receipt().sha256 == SHA256.hash(data: helper).hexString)
  }

  @Test func refusesToOverwriteAFileWithoutMatchingMotesReceipt() throws {
    let fileSystem = FakeInstallerFileSystem()
    let bundle = URL(fileURLWithPath: "/bundle/motes-agent")
    let support = URL(fileURLWithPath: "/support")
    fileSystem.files[bundle.path] = Data("new".utf8)
    fileSystem.files[support.appendingPathComponent("AgentBridge/bin/motes").path] =
      Data("someone else".utf8)
    let installer = AgentBridgeInstaller(
      bundledHelperURL: bundle,
      applicationSupportURL: support,
      fileSystem: fileSystem,
      processRunner: RecordingAgentProcessRunner()
    )

    #expect(throws: AgentBridgeInstallerError.destinationNotOwned) {
      try installer.install()
    }
  }

  @Test func provisioningSendsTokenOnlyThroughStdin() throws {
    let fileSystem = FakeInstallerFileSystem()
    let runner = RecordingAgentProcessRunner()
    let bundle = URL(fileURLWithPath: "/bundle/motes-agent")
    let support = URL(fileURLWithPath: "/support")
    fileSystem.files[bundle.path] = Data("helper".utf8)
    let installer = AgentBridgeInstaller(
      bundledHelperURL: bundle,
      applicationSupportURL: support,
      fileSystem: fileSystem,
      processRunner: runner
    )
    let profileID = UUID()
    let token = Data(repeating: 0xA5, count: 32)

    try installer.provision(profileID: profileID, token: token)

    let invocation = try #require(runner.invocations.first)
    #expect(
      invocation.arguments == ["configure", "--profile", profileID.uuidString, "--token-stdin"])
    #expect(invocation.stdin == Data(token.base64EncodedString().utf8))
    #expect(!invocation.arguments.joined().contains(token.base64EncodedString()))
  }

  @Test func cleanupRemovesOnlyReceiptOwnedHelperPaths() throws {
    let fileSystem = FakeInstallerFileSystem()
    let bundle = URL(fileURLWithPath: "/bundle/motes-agent")
    let support = URL(fileURLWithPath: "/support")
    fileSystem.files[bundle.path] = Data("helper".utf8)
    let unrelated = support.appendingPathComponent("unrelated.txt")
    fileSystem.files[unrelated.path] = Data("keep".utf8)
    let installer = AgentBridgeInstaller(
      bundledHelperURL: bundle,
      applicationSupportURL: support,
      fileSystem: fileSystem,
      processRunner: RecordingAgentProcessRunner()
    )
    let installed = try installer.install()

    try installer.removeInstalledHelper()

    #expect(fileSystem.files[installed.path] == nil)
    #expect(fileSystem.files[unrelated.path] != nil)
  }
}

private final class FakeInstallerFileSystem: AgentBridgeInstallerFileSystem, @unchecked Sendable {
  var files: [String: Data] = [:]

  func data(at url: URL) throws -> Data {
    guard let data = files[url.path] else { throw CocoaError(.fileNoSuchFile) }
    return data
  }

  func fileExists(at url: URL) -> Bool {
    files[url.path] != nil
  }

  func createDirectory(at url: URL) throws {}

  func write(_ data: Data, to url: URL) throws {
    files[url.path] = data
  }

  func replaceItem(at destination: URL, with staging: URL) throws {
    files[destination.path] = files.removeValue(forKey: staging.path)
  }

  func removeItem(at url: URL) throws {
    files.removeValue(forKey: url.path)
  }

  func makeExecutable(at url: URL) throws {}
}

private final class RecordingAgentProcessRunner: AgentBridgeProcessRunning, @unchecked Sendable {
  struct Invocation {
    let executable: URL
    let arguments: [String]
    let stdin: Data?
  }

  var invocations: [Invocation] = []

  func run(executable: URL, arguments: [String], stdin: Data?) throws {
    invocations.append(Invocation(executable: executable, arguments: arguments, stdin: stdin))
  }
}

extension SHA256.Digest {
  fileprivate var hexString: String {
    map { String(format: "%02x", $0) }.joined()
  }
}
