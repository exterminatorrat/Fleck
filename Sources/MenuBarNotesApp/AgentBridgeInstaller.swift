#if os(macOS)
  import CryptoKit
  import Darwin
  import Foundation
  import MenuBarNotesCore

  enum AgentBridgeInstallerError: Error, Equatable {
    case bundledHelperMissing
    case destinationNotOwned
    case verificationFailed
    case processFailed(Int32)
    case processTimedOut
  }

  struct AgentBridgeInstallationReceipt: Codable, Equatable {
    let destination: String
    let sha256: String
    let installedVersion: String
    let bundleIdentifier: String
  }

  protocol AgentBridgeInstallerFileSystem: Sendable {
    func data(at url: URL) throws -> Data
    func fileExists(at url: URL) -> Bool
    func createDirectory(at url: URL) throws
    func write(_ data: Data, to url: URL) throws
    func replaceItem(at destination: URL, with staging: URL) throws
    func removeItem(at url: URL) throws
    func makeExecutable(at url: URL) throws
  }

  protocol AgentBridgeProcessRunning: Sendable {
    func run(executable: URL, arguments: [String], stdin: Data?) throws
  }

  struct AgentBridgeInstaller: Sendable {
    static let ownerBundleIdentifier = "com.harryjin.motes"
    private static let transactionLock = NSRecursiveLock()

    let bundledHelperURL: URL
    let applicationSupportURL: URL
    private let fileSystem: any AgentBridgeInstallerFileSystem
    private let processRunner: any AgentBridgeProcessRunning
    private let installedVersion: String
    private let transactionAttemptObserver: @Sendable () -> Void

    init(
      bundledHelperURL: URL,
      applicationSupportURL: URL,
      fileSystem: any AgentBridgeInstallerFileSystem = LocalAgentBridgeInstallerFileSystem(),
      processRunner: any AgentBridgeProcessRunning = LocalAgentBridgeProcessRunner(),
      installedVersion: String = Bundle.main.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
      ) as? String ?? "development",
      transactionAttemptObserver: @escaping @Sendable () -> Void = {}
    ) {
      self.bundledHelperURL = bundledHelperURL
      self.applicationSupportURL = applicationSupportURL
      self.fileSystem = fileSystem
      self.processRunner = processRunner
      self.installedVersion = installedVersion
      self.transactionAttemptObserver = transactionAttemptObserver
    }

    static func live() throws -> Self {
      guard let sharedSupportURL = Bundle.main.sharedSupportURL else {
        throw AgentBridgeInstallerError.bundledHelperMissing
      }
      let applicationSupportURL = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      )[0].appendingPathComponent(
        FleckProductPaths.canonicalDirectoryName,
        isDirectory: true
      )
      return Self(
        bundledHelperURL: sharedSupportURL.appendingPathComponent("motes-agent"),
        applicationSupportURL: applicationSupportURL
      )
    }

    var installedHelperURL: URL {
      applicationSupportURL
        .appendingPathComponent("AgentBridge", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("motes")
        .standardizedFileURL
    }

    var installationReceiptURL: URL {
      applicationSupportURL
        .appendingPathComponent("AgentBridge", isDirectory: true)
        .appendingPathComponent("install-receipt.json")
    }

    @discardableResult
    func install() throws -> URL {
      transactionAttemptObserver()
      return try Self.transactionLock.withLock {
        guard fileSystem.fileExists(at: bundledHelperURL) else {
          throw AgentBridgeInstallerError.bundledHelperMissing
        }
        let bundledData = try fileSystem.data(at: bundledHelperURL)
        let previous = try previousInstall()

        let directory = installedHelperURL.deletingLastPathComponent()
        try fileSystem.createDirectory(at: directory)
        let staging = directory.appendingPathComponent(".motes-\(UUID().uuidString).staging")
        try fileSystem.write(bundledData, to: staging)
        try fileSystem.makeExecutable(at: staging)
        defer { try? fileSystem.removeItem(at: staging) }
        var didSwap = false
        do {
          try fileSystem.replaceItem(at: installedHelperURL, with: staging)
          didSwap = true
          let installedHash = sha256(try fileSystem.data(at: installedHelperURL))
          guard installedHash == sha256(bundledData) else {
            throw AgentBridgeInstallerError.verificationFailed
          }
          let receipt = AgentBridgeInstallationReceipt(
            destination: installedHelperURL.path,
            sha256: installedHash,
            installedVersion: installedVersion,
            bundleIdentifier: Self.ownerBundleIdentifier
          )
          try fileSystem.write(
            try JSONEncoder().encode(receipt),
            to: installationReceiptURL
          )
          guard verifiedInstalledHelperURL() == installedHelperURL else {
            throw AgentBridgeInstallerError.verificationFailed
          }
          return installedHelperURL
        } catch {
          if didSwap {
            try restore(previous)
          }
          throw error
        }
      }
    }

    func installAsync() async throws -> URL {
      try await Task.detached(priority: .userInitiated) {
        try install()
      }.value
    }

    func receipt() throws -> AgentBridgeInstallationReceipt {
      try JSONDecoder().decode(
        AgentBridgeInstallationReceipt.self,
        from: fileSystem.data(at: installationReceiptURL)
      )
    }

    func verifiedInstalledHelperURL() -> URL? {
      guard
        fileSystem.fileExists(at: installedHelperURL),
        let receipt = try? receipt(),
        receipt.destination == installedHelperURL.path,
        receipt.bundleIdentifier == Self.ownerBundleIdentifier,
        receipt.installedVersion == installedVersion,
        let installedData = try? fileSystem.data(at: installedHelperURL),
        receipt.sha256 == sha256(installedData)
      else { return nil }
      return installedHelperURL
    }

    func provision(profileID: UUID, token: Data) throws {
      transactionAttemptObserver()
      try Self.transactionLock.withLock {
        let helper = try install()
        try processRunner.run(
          executable: helper,
          arguments: [
            "configure", "--profile", profileID.uuidString, "--token-stdin",
          ],
          stdin: Data(token.base64EncodedString().utf8)
        )
      }
    }

    func provisionAsync(profileID: UUID, token: Data) async throws {
      try await Task.detached(priority: .userInitiated) {
        try provision(profileID: profileID, token: token)
      }.value
    }

    func disconnect(profileID: UUID) throws {
      transactionAttemptObserver()
      try Self.transactionLock.withLock {
        guard let helper = verifiedInstalledHelperURL() else {
          throw AgentBridgeInstallerError.verificationFailed
        }
        try processRunner.run(
          executable: helper,
          arguments: ["disconnect", "--profile", profileID.uuidString],
          stdin: nil
        )
      }
    }

    func disconnectAsync(profileID: UUID) async throws {
      try await Task.detached(priority: .userInitiated) {
        try disconnect(profileID: profileID)
      }.value
    }

    func removeInstalledHelper() throws {
      transactionAttemptObserver()
      try Self.transactionLock.withLock {
        guard
          fileSystem.fileExists(at: installedHelperURL),
          let prior = try? receipt(),
          prior.destination == installedHelperURL.path,
          prior.bundleIdentifier == Self.ownerBundleIdentifier,
          prior.sha256 == sha256(try fileSystem.data(at: installedHelperURL))
        else {
          if fileSystem.fileExists(at: installedHelperURL) {
            throw AgentBridgeInstallerError.destinationNotOwned
          }
          return
        }
        try fileSystem.removeItem(at: installedHelperURL)
        try fileSystem.removeItem(at: installationReceiptURL)
      }
    }

    func setupSnippet(profileID: UUID) -> String {
      "\(installedHelperURL.path) mcp --profile \(profileID.uuidString)"
    }

    private func sha256(_ data: Data) -> String {
      SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private struct PreviousInstall {
      let helper: Data?
      let receipt: Data?
    }

    private func previousInstall() throws -> PreviousInstall {
      let receiptData =
        fileSystem.fileExists(at: installationReceiptURL)
        ? try fileSystem.data(at: installationReceiptURL)
        : nil
      guard fileSystem.fileExists(at: installedHelperURL) else {
        return PreviousInstall(helper: nil, receipt: receiptData)
      }
      let helper = try fileSystem.data(at: installedHelperURL)
      guard
        let receiptData,
        let receipt = try? JSONDecoder().decode(
          AgentBridgeInstallationReceipt.self,
          from: receiptData
        ),
        receipt.destination == installedHelperURL.path,
        receipt.bundleIdentifier == Self.ownerBundleIdentifier,
        receipt.sha256 == sha256(helper)
      else {
        throw AgentBridgeInstallerError.destinationNotOwned
      }
      return PreviousInstall(helper: helper, receipt: receiptData)
    }

    private func restore(_ previous: PreviousInstall) throws {
      if let helper = previous.helper {
        let staging = installedHelperURL.deletingLastPathComponent()
          .appendingPathComponent(".motes-\(UUID().uuidString).rollback")
        try fileSystem.write(helper, to: staging)
        try fileSystem.makeExecutable(at: staging)
        defer { try? fileSystem.removeItem(at: staging) }
        try fileSystem.replaceItem(at: installedHelperURL, with: staging)
      } else {
        try fileSystem.removeItem(at: installedHelperURL)
      }
      if let receipt = previous.receipt {
        try fileSystem.write(receipt, to: installationReceiptURL)
      } else {
        try fileSystem.removeItem(at: installationReceiptURL)
      }
    }
  }

  struct LocalAgentBridgeInstallerFileSystem: AgentBridgeInstallerFileSystem {
    func data(at url: URL) throws -> Data {
      try Data(contentsOf: url)
    }

    func fileExists(at url: URL) -> Bool {
      FileManager.default.fileExists(atPath: url.path)
    }

    func createDirectory(at url: URL) throws {
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func write(_ data: Data, to url: URL) throws {
      try data.write(to: url, options: .atomic)
    }

    func replaceItem(at destination: URL, with staging: URL) throws {
      if FileManager.default.fileExists(atPath: destination.path) {
        _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
      } else {
        try FileManager.default.moveItem(at: staging, to: destination)
      }
    }

    func removeItem(at url: URL) throws {
      guard FileManager.default.fileExists(atPath: url.path) else { return }
      try FileManager.default.removeItem(at: url)
    }

    func makeExecutable(at url: URL) throws {
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: url.path
      )
    }
  }

  struct LocalAgentBridgeProcessRunner: AgentBridgeProcessRunning {
    let timeout: TimeInterval

    init(timeout: TimeInterval = 10) {
      self.timeout = timeout
    }

    func run(executable: URL, arguments: [String], stdin: Data?) throws {
      let process = Process()
      let completion = DispatchSemaphore(value: 0)
      process.executableURL = executable
      process.arguments = arguments
      process.terminationHandler = { _ in completion.signal() }
      if let stdin {
        let pipe = Pipe()
        process.standardInput = pipe
        try process.run()
        pipe.fileHandleForWriting.write(stdin)
        try pipe.fileHandleForWriting.close()
      } else {
        try process.run()
      }
      guard completion.wait(timeout: .now() + timeout) == .success else {
        process.terminate()
        if completion.wait(timeout: .now() + 1) == .timedOut {
          Darwin.kill(process.processIdentifier, SIGKILL)
          _ = completion.wait(timeout: .now() + 1)
        }
        throw AgentBridgeInstallerError.processTimedOut
      }
      guard process.terminationStatus == 0 else {
        throw AgentBridgeInstallerError.processFailed(process.terminationStatus)
      }
    }
  }
#endif
