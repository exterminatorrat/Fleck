import CryptoKit
import Foundation
import FleckCore
import Testing

@testable import FleckApp

@Suite("AgentBridgeInstaller")
struct AgentBridgeInstallerTests {
  @Test func installWritesVerifiedFleckHelperAndMotesCompatibilityLauncher() throws {
    let fileSystem = FakeInstallerFileSystem()
    let bundle = URL(fileURLWithPath: "/Fleck.app/Contents/SharedSupport/fleck-agent")
    let support = URL(fileURLWithPath: "/Users/test/Library/Application Support/Fleck")
    let helper = Data("verified helper".utf8)
    fileSystem.files[bundle.path] = helper
    let installer = AgentBridgeInstaller(
      bundledHelperURL: bundle,
      applicationSupportURL: support,
      fileSystem: fileSystem,
      processRunner: RecordingAgentProcessRunner()
    )

    let installed = try installer.install()
    let expected = support.appendingPathComponent("AgentBridge/bin/fleck")
    let legacyLauncherName = "motes"
    let legacyLauncher = URL(fileURLWithPath: "/Users/test/Library/Application Support")
      .appendingPathComponent(FleckProductPaths.legacyDirectoryName)
      .appendingPathComponent("AgentBridge/bin/\(legacyLauncherName)")

    #expect(installed == expected)
    #expect(installed.path.hasPrefix("/"))
    #expect(fileSystem.files[expected.path] == helper)
    #expect(try installer.receipt().sha256 == SHA256.hash(data: helper).hexString)
    #expect(installer.verifiedInstalledHelperURL() == expected)
    #expect(
      fileSystem.files[legacyLauncher.path]
        == Data("#!/bin/sh\nexec '\(expected.path)' \"$@\"\n".utf8)
    )
    #expect(installer.verifiedLegacyLauncherURL() == legacyLauncher)
  }

  @Test func existingFleckReceiptMustVerifyBeforeReplacement() throws {
    let fileSystem = FakeInstallerFileSystem()
    let bundle = URL(fileURLWithPath: "/bundle/fleck-agent")
    let support = URL(fileURLWithPath: "/support")
    fileSystem.files[bundle.path] = Data("new".utf8)
    fileSystem.files[support.appendingPathComponent("AgentBridge/bin/fleck").path] =
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

  @Test func movedLegacyHelperVerifiesAgainstItsPreMigrationReceipt() throws {
    let fileSystem = FakeInstallerFileSystem()
    let bundle = URL(fileURLWithPath: "/bundle/fleck-agent")
    let parent = URL(fileURLWithPath: "/Users/test/Library/Application Support")
    let support = parent.appendingPathComponent("Fleck", isDirectory: true)
    let legacy = parent.appendingPathComponent(
      FleckProductPaths.legacyDirectoryName,
      isDirectory: true
    )
    let installer = AgentBridgeInstaller(
      bundledHelperURL: bundle,
      applicationSupportURL: support,
      fileSystem: fileSystem,
      processRunner: RecordingAgentProcessRunner()
    )
    let oldHelper = Data("old motes helper".utf8) // Legacy helper fixture.
    fileSystem.files[bundle.path] = Data("new fleck helper".utf8)
    fileSystem.files[installer.migratedLegacyHelperURL.path] = oldHelper
    fileSystem.files[installer.installationReceiptURL.path] =
      try JSONEncoder().encode(
        AgentBridgeInstallationReceipt(
          destination: legacy.appendingPathComponent("AgentBridge/bin/motes").path, // Legacy receipt.
          sha256: SHA256.hash(data: oldHelper).hexString,
          installedVersion: "development",
          bundleIdentifier: "com.harryjin.motes" // Legacy bundle identifier.
        )
      )
    let migration = FleckMigrationReceipt(
      schemaVersion: 1,
      migratedAt: Date(timeIntervalSince1970: 100),
      legacyPath: legacy.path,
      canonicalPath: support.path
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    fileSystem.files[
      support.appendingPathComponent(
        FleckProductPaths.migrationReceiptName
      ).path
    ] = try encoder.encode(migration)

    #expect(try installer.install() == installer.installedHelperURL)
    #expect(fileSystem.files[installer.migratedLegacyHelperURL.path] == nil)
    #expect(installer.verifiedLegacyLauncherURL() == installer.legacyLauncherURL)
  }

  @Test func repeatedInstallIsIdempotent() throws {
    let fixture = try InstalledHelperFixture()
    let firstHelper = fixture.fileSystem.files[
      fixture.installer.installedHelperURL.path
    ]
    let firstLauncher = fixture.fileSystem.files[
      fixture.installer.legacyLauncherURL.path
    ]

    _ = try fixture.installer.install()

    #expect(
      fixture.fileSystem.files[fixture.installer.installedHelperURL.path]
        == firstHelper
    )
    #expect(
      fixture.fileSystem.files[fixture.installer.legacyLauncherURL.path]
        == firstLauncher
    )
    #expect(
      fixture.installer.verifiedLegacyLauncherURL()
        == fixture.installer.legacyLauncherURL
    )
  }

  @Test func provisioningSendsTokenOnlyThroughStdin() throws {
    let fileSystem = FakeInstallerFileSystem()
    let runner = RecordingAgentProcessRunner()
    let bundle = URL(fileURLWithPath: "/bundle/fleck-agent")
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
    let bundle = URL(fileURLWithPath: "/bundle/fleck-agent")
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
    let bundle = URL(fileURLWithPath: "/bundle/fleck-agent")
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
    let bundle = URL(fileURLWithPath: "/bundle/fleck-agent")
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

  @Test func failedCompatibilitySwapRollsBackCanonicalAndLegacyFiles() throws {
    let fixture = try InstalledHelperFixture()
    let originalHelper = try fixture.fileSystem.data(
      at: fixture.installer.installedHelperURL
    )
    let originalLauncher = try fixture.fileSystem.data(
      at: fixture.installer.legacyLauncherURL
    )
    let originalReceipt = try fixture.fileSystem.data(
      at: fixture.installer.installationReceiptURL
    )
    let originalMarker = try fixture.fileSystem.data(
      at: fixture.installer.compatibilityReceiptURL
    )
    fixture.fileSystem.files[fixture.installer.bundledHelperURL.path] =
      Data("new helper".utf8)
    fixture.fileSystem.failNextWritePath =
      fixture.installer.compatibilityReceiptURL.path

    #expect(throws: (any Error).self) {
      try fixture.installer.install()
    }

    #expect(
      fixture.fileSystem.files[fixture.installer.installedHelperURL.path]
        == originalHelper
    )
    #expect(
      fixture.fileSystem.files[fixture.installer.legacyLauncherURL.path]
        == originalLauncher
    )
    #expect(
      fixture.fileSystem.files[fixture.installer.installationReceiptURL.path]
        == originalReceipt
    )
    #expect(
      fixture.fileSystem.files[fixture.installer.compatibilityReceiptURL.path]
        == originalMarker
    )
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
      bundleIdentifier: "example.not-fleck"
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

  @Test func disconnectFailsClosedWhenInstalledHelperIsMissing() throws {
    let runner = RecordingAgentProcessRunner()
    let installer = AgentBridgeInstaller(
      bundledHelperURL: URL(fileURLWithPath: "/bundle/fleck-agent"),
      applicationSupportURL: URL(fileURLWithPath: "/support"),
      fileSystem: FakeInstallerFileSystem(),
      processRunner: runner
    )

    #expect(throws: AgentBridgeInstallerError.verificationFailed) {
      try installer.disconnect(profileID: UUID())
    }
    #expect(runner.invocations.isEmpty)
  }

  @Test func disconnectFailsClosedWhenInstalledHelperWasTampered() throws {
    let fixture = try InstalledHelperFixture()
    fixture.fileSystem.files[fixture.installer.installedHelperURL.path] = Data("tampered".utf8)

    #expect(throws: AgentBridgeInstallerError.verificationFailed) {
      try fixture.installer.disconnect(profileID: UUID())
    }
    #expect(fixture.runner.invocations.isEmpty)
  }

  @Test func disconnectExecutesOnlyVerifiedCanonicalFleckHelper() throws {
    let fixture = try InstalledHelperFixture()
    let profileID = UUID()

    try fixture.installer.disconnect(profileID: profileID)

    let invocation = try #require(fixture.runner.invocations.first)
    #expect(invocation.executable == fixture.installer.installedHelperURL)
    #expect(
      invocation.arguments
        == ["disconnect", "--profile", profileID.uuidString]
    )
  }

  @Test func asynchronousInstallerOperationsStayOffMainThread() async throws {
    let fileSystem = FakeInstallerFileSystem()
    let runner = RecordingAgentProcessRunner()
    let bundle = URL(fileURLWithPath: "/bundle/fleck-agent")
    fileSystem.files[bundle.path] = Data("helper".utf8)
    let installer = AgentBridgeInstaller(
      bundledHelperURL: bundle,
      applicationSupportURL: URL(fileURLWithPath: "/support"),
      fileSystem: fileSystem,
      processRunner: runner
    )
    fileSystem.observedMainThread.removeAll()
    let profileID = UUID()

    _ = try await installer.installAsync()
    try await installer.provisionAsync(profileID: profileID, token: Data(repeating: 1, count: 32))
    try await installer.disconnectAsync(profileID: profileID)

    #expect(!fileSystem.observedMainThread.isEmpty)
    #expect(fileSystem.observedMainThread.allSatisfy { !$0 })
    #expect(runner.invocations.count == 2)
    #expect(runner.invocations.allSatisfy { !$0.ranOnMainThread })
  }

  @Test func localProcessRunnerTimesOutInsteadOfWaitingForever() {
    let runner = LocalAgentBridgeProcessRunner(timeout: 0.01)

    #expect(throws: AgentBridgeInstallerError.processTimedOut) {
      try runner.run(
        executable: URL(fileURLWithPath: "/bin/sleep"),
        arguments: ["5"],
        stdin: nil
      )
    }
  }

  @Test func legacyAbsoluteMotesPathRunsFleckWithoutProtocolNoise() throws {
    let parent = FileManager.default.temporaryDirectory.appendingPathComponent(
      "FleckBridgeCompatibility-\(UUID())",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: parent) }
    let support = parent.appendingPathComponent("Fleck", isDirectory: true)
    let bundled = parent.appendingPathComponent("fleck-agent")
    try FileManager.default.createDirectory(
      at: parent,
      withIntermediateDirectories: true
    )
    try Data(
      "#!/bin/sh\nprintf 'fleck:%s\\n' \"$1\"\n".utf8
    ).write(to: bundled)
    let installer = AgentBridgeInstaller(
      bundledHelperURL: bundled,
      applicationSupportURL: support
    )
    _ = try installer.install()

    let canonical = try runForOutput(
      installer.installedHelperURL,
      arguments: ["--help"]
    )
    let legacy = try runForOutput(
      installer.legacyLauncherURL,
      arguments: ["--help"]
    )

    #expect(canonical.status == 0)
    #expect(legacy.status == canonical.status)
    #expect(legacy.stdout == canonical.stdout)
    #expect(legacy.stdout == "fleck:--help\n")
    #expect(legacy.stderr.isEmpty)
  }

  @Test func concurrentProvisionAndInstallSerializeTheSharedHelperTransaction() async throws {
    let fileSystem = FakeInstallerFileSystem()
    let blockingRunner = BlockingAgentProcessRunner()
    let secondAttempt = BlockingTransactionAttempt()
    let bundle = URL(fileURLWithPath: "/bundle/fleck-agent")
    let support = URL(fileURLWithPath: "/support")
    fileSystem.files[bundle.path] = Data("helper".utf8)
    let provisioningInstaller = AgentBridgeInstaller(
      bundledHelperURL: bundle,
      applicationSupportURL: support,
      fileSystem: fileSystem,
      processRunner: blockingRunner
    )
    let installingInstaller = AgentBridgeInstaller(
      bundledHelperURL: bundle,
      applicationSupportURL: support,
      fileSystem: fileSystem,
      processRunner: RecordingAgentProcessRunner(),
      transactionAttemptObserver: { secondAttempt.signal() }
    )

    let provision = Task {
      try await provisioningInstaller.provisionAsync(
        profileID: UUID(),
        token: Data(repeating: 1, count: 32)
      )
    }
    #expect(blockingRunner.waitUntilEntered())
    let operationCount = fileSystem.operationCount
    let install = Task {
      try await installingInstaller.installAsync()
    }

    #expect(secondAttempt.waitUntilAttempted())
    #expect(fileSystem.operationCount == operationCount)

    blockingRunner.release()
    try await provision.value
    _ = try await install.value
    #expect(installingInstaller.verifiedInstalledHelperURL() == installingInstaller.installedHelperURL)
  }
}

private func runForOutput(
  _ executable: URL,
  arguments: [String]
) throws -> (status: Int32, stdout: String, stderr: String) {
  let process = Process()
  let stdout = Pipe()
  let stderr = Pipe()
  process.executableURL = executable
  process.arguments = arguments
  process.standardOutput = stdout
  process.standardError = stderr
  try process.run()
  process.waitUntilExit()
  return (
    process.terminationStatus,
    String(
      decoding: stdout.fileHandleForReading.readDataToEndOfFile(),
      as: UTF8.self
    ),
    String(
      decoding: stderr.fileHandleForReading.readDataToEndOfFile(),
      as: UTF8.self
    )
  )
}

private final class FakeInstallerFileSystem: AgentBridgeInstallerFileSystem, @unchecked Sendable {
  var files: [String: Data] = [:]
  var corruptNextReplacement = false
  var failNextWritePath: String?
  var observedMainThread: [Bool] = []
  private let observationLock = NSLock()
  private var observedOperationCount = 0

  var operationCount: Int {
    observationLock.withLock { observedOperationCount }
  }

  private func observeThread() {
    observationLock.withLock {
      observedMainThread.append(Thread.isMainThread)
      observedOperationCount += 1
    }
  }

  func data(at url: URL) throws -> Data {
    observeThread()
    guard let data = files[url.path] else { throw CocoaError(.fileNoSuchFile) }
    return data
  }

  func fileExists(at url: URL) -> Bool {
    observeThread()
    return files[url.path] != nil
  }

  func createDirectory(at url: URL) throws {
    observeThread()
  }

  func write(_ data: Data, to url: URL) throws {
    observeThread()
    if failNextWritePath == url.path {
      failNextWritePath = nil
      throw CocoaError(.fileWriteUnknown)
    }
    files[url.path] = data
  }

  func replaceItem(at destination: URL, with staging: URL) throws {
    observeThread()
    files[destination.path] = files.removeValue(forKey: staging.path)
    if corruptNextReplacement {
      corruptNextReplacement = false
      files[destination.path] = Data("corrupt".utf8)
    }
  }

  func removeItem(at url: URL) throws {
    observeThread()
    files.removeValue(forKey: url.path)
  }

  func makeExecutable(at url: URL) throws {
    observeThread()
  }
}

private struct InstalledHelperFixture {
  let fileSystem = FakeInstallerFileSystem()
  let runner = RecordingAgentProcessRunner()
  let installer: AgentBridgeInstaller

  init() throws {
    let bundle = URL(fileURLWithPath: "/bundle/\(UUID().uuidString)/fleck-agent")
    let support = URL(fileURLWithPath: "/support/\(UUID().uuidString)")
    installer = AgentBridgeInstaller(
      bundledHelperURL: bundle,
      applicationSupportURL: support,
      fileSystem: fileSystem,
      processRunner: runner,
      installedVersion: "1.2.3"
    )
    fileSystem.files[bundle.path] = Data("helper".utf8)
    _ = try installer.install()
  }
}

private final class BlockingTransactionAttempt: @unchecked Sendable {
  private let attempted = DispatchSemaphore(value: 0)

  func signal() {
    attempted.signal()
  }

  func waitUntilAttempted() -> Bool {
    attempted.wait(timeout: .now() + 2) == .success
  }
}

private final class BlockingAgentProcessRunner: AgentBridgeProcessRunning, @unchecked Sendable {
  private let entered = DispatchSemaphore(value: 0)
  private let released = DispatchSemaphore(value: 0)

  func run(executable: URL, arguments: [String], stdin: Data?) throws {
    entered.signal()
    released.wait()
  }

  func waitUntilEntered() -> Bool {
    entered.wait(timeout: .now() + 2) == .success
  }

  func release() {
    released.signal()
  }
}

private final class RecordingAgentProcessRunner: AgentBridgeProcessRunning, @unchecked Sendable {
  struct Invocation {
    let executable: URL
    let arguments: [String]
    let stdin: Data?
    let ranOnMainThread: Bool
  }

  var invocations: [Invocation] = []

  func run(executable: URL, arguments: [String], stdin: Data?) throws {
    invocations.append(
      Invocation(
        executable: executable,
        arguments: arguments,
        stdin: stdin,
        ranOnMainThread: Thread.isMainThread
      )
    )
  }
}

extension SHA256.Digest {
  fileprivate var hexString: String {
    map { String(format: "%02x", $0) }.joined()
  }
}
