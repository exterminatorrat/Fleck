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
    #expect(installer.verifiedInstalledHelperURL() == expected)
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
    #expect(
      fileSystem.files[installer.installedHelperURL.path]
        == Data("someone else".utf8)
    )
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

  @Test func failedPostSwapHashVerificationRemovesANewUnownedDestination() throws {
    let fileSystem = FakeInstallerFileSystem()
    let bundle = URL(fileURLWithPath: "/bundle/motes-agent")
    let support = URL(fileURLWithPath: "/support")
    fileSystem.files[bundle.path] = Data("helper".utf8)
    fileSystem.corruptNextReplacement = true
    let installer = AgentBridgeInstaller(
      bundledHelperURL: bundle,
      applicationSupportURL: support,
      fileSystem: fileSystem,
      processRunner: RecordingAgentProcessRunner()
    )

    #expect(throws: AgentBridgeInstallerError.verificationFailed) {
      try installer.install()
    }
    #expect(fileSystem.files[installer.installedHelperURL.path] == nil)
    #expect(installer.verifiedInstalledHelperURL() == nil)
  }

  @Test func failedReceiptWriteAtomicallyRestoresPriorVerifiedInstall() throws {
    let fileSystem = FakeInstallerFileSystem()
    let bundle = URL(fileURLWithPath: "/bundle/motes-agent")
    let support = URL(fileURLWithPath: "/support")
    let installer = AgentBridgeInstaller(
      bundledHelperURL: bundle,
      applicationSupportURL: support,
      fileSystem: fileSystem,
      processRunner: RecordingAgentProcessRunner()
    )
    let original = Data("original".utf8)
    fileSystem.files[bundle.path] = original
    _ = try installer.install()
    let originalReceipt = try fileSystem.data(at: installer.installationReceiptURL)
    fileSystem.files[bundle.path] = Data("replacement".utf8)
    fileSystem.failNextWritePath = installer.installationReceiptURL.path

    #expect(throws: (any Error).self) {
      try installer.install()
    }
    #expect(fileSystem.files[installer.installedHelperURL.path] == original)
    #expect(fileSystem.files[installer.installationReceiptURL.path] == originalReceipt)
    #expect(installer.verifiedInstalledHelperURL() == installer.installedHelperURL)
  }

  @Test func installedStatusRejectsMissingAndTamperedHelpers() throws {
    let fixture = try InstalledHelperFixture()
    fixture.fileSystem.files.removeValue(forKey: fixture.installer.installedHelperURL.path)
    #expect(fixture.installer.verifiedInstalledHelperURL() == nil)

    let tampered = try InstalledHelperFixture()
    tampered.fileSystem.files[tampered.installer.installedHelperURL.path] = Data("tampered".utf8)
    #expect(tampered.installer.verifiedInstalledHelperURL() == nil)
  }

  @Test func installedStatusRejectsWrongOwnerAndVersionReceipts() throws {
    let wrongOwner = try InstalledHelperFixture()
    var receipt = try wrongOwner.installer.receipt()
    receipt = AgentBridgeInstallationReceipt(
      destination: receipt.destination,
      sha256: receipt.sha256,
      installedVersion: receipt.installedVersion,
      bundleIdentifier: "example.not-motes"
    )
    wrongOwner.fileSystem.files[wrongOwner.installer.installationReceiptURL.path] =
      try JSONEncoder().encode(receipt)
    #expect(wrongOwner.installer.verifiedInstalledHelperURL() == nil)

    let wrongVersion = try InstalledHelperFixture()
    let current = try wrongVersion.installer.receipt()
    wrongVersion.fileSystem.files[wrongVersion.installer.installationReceiptURL.path] =
      try JSONEncoder().encode(
        AgentBridgeInstallationReceipt(
          destination: current.destination,
          sha256: current.sha256,
          installedVersion: "0.0.0",
          bundleIdentifier: current.bundleIdentifier
        ))
    #expect(wrongVersion.installer.verifiedInstalledHelperURL() == nil)
  }
}

private final class FakeInstallerFileSystem: AgentBridgeInstallerFileSystem, @unchecked Sendable {
  var files: [String: Data] = [:]
  var corruptNextReplacement = false
  var failNextWritePath: String?

  func data(at url: URL) throws -> Data {
    guard let data = files[url.path] else { throw CocoaError(.fileNoSuchFile) }
    return data
  }

  func fileExists(at url: URL) -> Bool {
    files[url.path] != nil
  }

  func createDirectory(at url: URL) throws {}

  func write(_ data: Data, to url: URL) throws {
    if failNextWritePath == url.path {
      failNextWritePath = nil
      throw CocoaError(.fileWriteUnknown)
    }
    files[url.path] = data
  }

  func replaceItem(at destination: URL, with staging: URL) throws {
    files[destination.path] = files.removeValue(forKey: staging.path)
    if corruptNextReplacement {
      corruptNextReplacement = false
      files[destination.path] = Data("corrupt".utf8)
    }
  }

  func removeItem(at url: URL) throws {
    files.removeValue(forKey: url.path)
  }

  func makeExecutable(at url: URL) throws {}
}

private struct InstalledHelperFixture {
  let fileSystem = FakeInstallerFileSystem()
  let installer: AgentBridgeInstaller

  init() throws {
    let bundle = URL(fileURLWithPath: "/bundle/\(UUID().uuidString)/motes-agent")
    let support = URL(fileURLWithPath: "/support/\(UUID().uuidString)")
    installer = AgentBridgeInstaller(
      bundledHelperURL: bundle,
      applicationSupportURL: support,
      fileSystem: fileSystem,
      processRunner: RecordingAgentProcessRunner(),
      installedVersion: "1.2.3"
    )
    fileSystem.files[bundle.path] = Data("helper".utf8)
    _ = try installer.install()
  }
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
