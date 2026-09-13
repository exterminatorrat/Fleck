#if os(macOS)
  import CryptoKit
  import Darwin
  import Foundation
  import FleckCore

  enum AgentBridgeInstallerError: Error, Equatable {
    case bundledHelperMissing
    case destinationNotOwned
    case verificationFailed
    case processFailed(Int32)
    case processTimedOut
  }

  extension AgentBridgeInstallerError: LocalizedError {
    var errorDescription: String? {
      switch self {
      case .bundledHelperMissing:
        "The Agent Connector is available only in the packaged Fleck app."
      case .destinationNotOwned:
        "Fleck cannot replace an Agent Connector it did not install."
      case .verificationFailed:
        "Fleck could not verify the Agent Connector."
      case .processFailed:
        "The Agent Connector stopped unexpectedly."
      case .processTimedOut:
        "The Agent Connector did not respond in time."
      }
    }

    var recoverySuggestion: String? {
      guard self == .bundledHelperMissing else { return nil }
      return """
        Build and open the packaged app:
        mkdir -p .build &&
        RESULT_DIR="$(mktemp -d "$PWD/.build/development-result.XXXXXX")" &&
        RESULT_FILE="$RESULT_DIR/build-result.json" &&
        Scripts/build-fleck-app.sh --result-file "$RESULT_FILE" &&
        FLECK_APP="$(Scripts/fleck-build-identity.py read-result --repo "$PWD" --result-file "$RESULT_FILE" --flavor development)" &&
        /usr/bin/open -n "$FLECK_APP"
        """
    }
  }

  struct AgentBridgeInstallationReceipt: Codable, Equatable {
    let destination: String
    let sha256: String
    let installedVersion: String
    let bundleIdentifier: String
  }

  struct AgentBridgeCompatibilityReceipt: Codable, Equatable {
    let schemaVersion: Int
    let canonicalDestination: String
    let canonicalSHA256: String
    let launcherDestination: String
    let launcherSHA256: String
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
    static let ownerBundleIdentifier = "com.harryjin.fleck"
    static let legacyOwnerBundleIdentifier = "com.harryjin.motes"
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
        bundledHelperURL: sharedSupportURL.appendingPathComponent("fleck-agent"),
        applicationSupportURL: applicationSupportURL
      )
    }

    var installedHelperURL: URL {
      applicationSupportURL
        .appendingPathComponent("AgentBridge", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("fleck")
        .standardizedFileURL
    }

    var legacyLauncherURL: URL {
      applicationSupportURL.deletingLastPathComponent()
        .appendingPathComponent(
          FleckProductPaths.legacyDirectoryName,
          isDirectory: true
        )
        .appendingPathComponent("AgentBridge", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("motes") // Legacy launcher for one release.
        .standardizedFileURL
    }

    var migratedLegacyHelperURL: URL {
      applicationSupportURL
        .appendingPathComponent("AgentBridge", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("motes") // Legacy migrated helper name.
        .standardizedFileURL
    }

    var installationReceiptURL: URL {
      applicationSupportURL
        .appendingPathComponent("AgentBridge", isDirectory: true)
        .appendingPathComponent("install-receipt.json")
    }

    var compatibilityReceiptURL: URL {
      legacyLauncherURL.deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("fleck-compatibility-v1.json")
    }

    private var migrationReceiptURL: URL {
      applicationSupportURL.appendingPathComponent(
        FleckProductPaths.migrationReceiptName
      )
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

        let canonicalDirectory = installedHelperURL.deletingLastPathComponent()
        let legacyDirectory = legacyLauncherURL.deletingLastPathComponent()
        try fileSystem.createDirectory(at: canonicalDirectory)
        try fileSystem.createDirectory(at: legacyDirectory)
        let canonicalStaging = canonicalDirectory.appendingPathComponent(
          ".fleck-\(UUID().uuidString).staging"
        )
        let launcherStaging = legacyDirectory.appendingPathComponent(
          ".motes-\(UUID().uuidString).staging" // Compatibility launcher.
        )
        let launcherData = compatibilityLauncherData()
        try fileSystem.write(bundledData, to: canonicalStaging)
        try fileSystem.makeExecutable(at: canonicalStaging)
        try fileSystem.write(launcherData, to: launcherStaging)
        try fileSystem.makeExecutable(at: launcherStaging)
        defer {
          try? fileSystem.removeItem(at: canonicalStaging)
          try? fileSystem.removeItem(at: launcherStaging)
        }
        var didMutate = false
        do {
          try fileSystem.replaceItem(
            at: installedHelperURL,
            with: canonicalStaging
          )
          didMutate = true
          try fileSystem.replaceItem(
            at: legacyLauncherURL,
            with: launcherStaging
          )
          let installedHash = sha256(try fileSystem.data(at: installedHelperURL))
          let launcherHash = sha256(try fileSystem.data(at: legacyLauncherURL))
          guard
            installedHash == sha256(bundledData),
            launcherHash == sha256(launcherData)
          else {
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
          let compatibility = AgentBridgeCompatibilityReceipt(
            schemaVersion: 1,
            canonicalDestination: installedHelperURL.path,
            canonicalSHA256: installedHash,
            launcherDestination: legacyLauncherURL.path,
            launcherSHA256: launcherHash,
            installedVersion: installedVersion,
            bundleIdentifier: Self.ownerBundleIdentifier
          )
          let compatibilityEncoder = JSONEncoder()
          compatibilityEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
          try fileSystem.write(
            try compatibilityEncoder.encode(compatibility),
            to: compatibilityReceiptURL
          )
          try fileSystem.removeItem(at: migratedLegacyHelperURL)
          guard
            verifiedInstalledHelperURL() == installedHelperURL,
            verifiedLegacyLauncherURL() == legacyLauncherURL
          else {
            throw AgentBridgeInstallerError.verificationFailed
          }
          return installedHelperURL
        } catch {
          if didMutate {
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

    func verifiedLegacyLauncherURL() -> URL? {
      guard
        fileSystem.fileExists(at: legacyLauncherURL),
        fileSystem.fileExists(at: installedHelperURL),
        let markerData = try? fileSystem.data(at: compatibilityReceiptURL),
        let marker = try? JSONDecoder().decode(
          AgentBridgeCompatibilityReceipt.self,
          from: markerData
        ),
        marker.schemaVersion == 1,
        marker.canonicalDestination == installedHelperURL.path,
        marker.launcherDestination == legacyLauncherURL.path,
        marker.installedVersion == installedVersion,
        marker.bundleIdentifier == Self.ownerBundleIdentifier,
        let canonicalData = try? fileSystem.data(at: installedHelperURL),
        let launcherData = try? fileSystem.data(at: legacyLauncherURL),
        marker.canonicalSHA256 == sha256(canonicalData),
        marker.launcherSHA256 == sha256(launcherData)
      else { return nil }
      return legacyLauncherURL
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
        let hasLegacyLauncher = fileSystem.fileExists(at: legacyLauncherURL)
        if hasLegacyLauncher {
          guard verifiedLegacyLauncherURL() == legacyLauncherURL else {
            throw AgentBridgeInstallerError.destinationNotOwned
          }
        }
        try fileSystem.removeItem(at: installedHelperURL)
        try fileSystem.removeItem(at: installationReceiptURL)
        if hasLegacyLauncher {
          try fileSystem.removeItem(at: legacyLauncherURL)
          try fileSystem.removeItem(at: compatibilityReceiptURL)
        }
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
      let migratedLegacyHelper: Data?
      let legacyLauncher: Data?
      let compatibilityReceipt: Data?
    }

    private func previousInstall() throws -> PreviousInstall {
      let receiptData =
        fileSystem.fileExists(at: installationReceiptURL)
        ? try fileSystem.data(at: installationReceiptURL)
        : nil
      let helper =
        fileSystem.fileExists(at: installedHelperURL)
        ? try fileSystem.data(at: installedHelperURL)
        : nil
      let migratedLegacyHelper =
        fileSystem.fileExists(at: migratedLegacyHelperURL)
        ? try fileSystem.data(at: migratedLegacyHelperURL)
        : nil
      let legacyLauncher =
        fileSystem.fileExists(at: legacyLauncherURL)
        ? try fileSystem.data(at: legacyLauncherURL)
        : nil
      let compatibilityReceipt =
        fileSystem.fileExists(at: compatibilityReceiptURL)
        ? try fileSystem.data(at: compatibilityReceiptURL)
        : nil
      if helper != nil, !ownsInstalledHelper(receiptData: receiptData) {
        throw AgentBridgeInstallerError.destinationNotOwned
      }
      if migratedLegacyHelper != nil,
        !ownsMigratedLegacyHelper(receiptData: receiptData)
      {
        throw AgentBridgeInstallerError.destinationNotOwned
      }
      if legacyLauncher != nil,
        !ownsLegacyLauncher(markerData: compatibilityReceipt)
      {
        throw AgentBridgeInstallerError.destinationNotOwned
      }
      if receiptData != nil, helper == nil, migratedLegacyHelper == nil {
        throw AgentBridgeInstallerError.destinationNotOwned
      }
      if compatibilityReceipt != nil, legacyLauncher == nil {
        throw AgentBridgeInstallerError.destinationNotOwned
      }
      return PreviousInstall(
        helper: helper,
        receipt: receiptData,
        migratedLegacyHelper: migratedLegacyHelper,
        legacyLauncher: legacyLauncher,
        compatibilityReceipt: compatibilityReceipt
      )
    }

    private func restore(_ previous: PreviousInstall) throws {
      try restore(previous.helper, at: installedHelperURL, executable: true)
      try restore(previous.receipt, at: installationReceiptURL)
      try restore(
        previous.migratedLegacyHelper,
        at: migratedLegacyHelperURL,
        executable: true
      )
      try restore(
        previous.legacyLauncher,
        at: legacyLauncherURL,
        executable: true
      )
      try restore(
        previous.compatibilityReceipt,
        at: compatibilityReceiptURL
      )
    }

    private func restore(
      _ data: Data?,
      at destination: URL,
      executable: Bool = false
    ) throws {
      guard let data else {
        try fileSystem.removeItem(at: destination)
        return
      }
      let staging = destination.deletingLastPathComponent()
        .appendingPathComponent(".fleck-\(UUID().uuidString).rollback")
      try fileSystem.write(data, to: staging)
      if executable {
        try fileSystem.makeExecutable(at: staging)
      }
      defer { try? fileSystem.removeItem(at: staging) }
      try fileSystem.replaceItem(at: destination, with: staging)
    }

    private func compatibilityLauncherData() -> Data {
      Data(
        (
          "#!/bin/sh\nexec "
            + ShellArgument.encode(installedHelperURL.path)
            + " \"$@\"\n"
        ).utf8
      )
    }

    private func ownsInstalledHelper(receiptData: Data?) -> Bool {
      guard
        let receiptData,
        let receipt = try? JSONDecoder().decode(
          AgentBridgeInstallationReceipt.self,
          from: receiptData
        ),
        receipt.destination == installedHelperURL.path,
        receipt.bundleIdentifier == Self.ownerBundleIdentifier,
        let helper = try? fileSystem.data(at: installedHelperURL),
        receipt.sha256 == sha256(helper)
      else { return false }
      return true
    }

    private func ownsMigratedLegacyHelper(receiptData: Data?) -> Bool {
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      guard
        let receiptData,
        let receipt = try? JSONDecoder().decode(
          AgentBridgeInstallationReceipt.self,
          from: receiptData
        ),
        receipt.destination == legacyLauncherURL.path,
        receipt.bundleIdentifier == Self.legacyOwnerBundleIdentifier,
        let helper = try? fileSystem.data(at: migratedLegacyHelperURL),
        receipt.sha256 == sha256(helper),
        let migrationData = try? fileSystem.data(at: migrationReceiptURL),
        let migration = try? decoder.decode(
          FleckMigrationReceipt.self,
          from: migrationData
        ),
        migration.schemaVersion == 1,
        migration.legacyPath
          == legacyLauncherURL
          .deletingLastPathComponent()
          .deletingLastPathComponent()
          .deletingLastPathComponent()
          .path,
        migration.canonicalPath == applicationSupportURL.path
      else { return false }
      return true
    }

    private func ownsLegacyLauncher(markerData: Data?) -> Bool {
      guard
        let markerData,
        let marker = try? JSONDecoder().decode(
          AgentBridgeCompatibilityReceipt.self,
          from: markerData
        ),
        marker.schemaVersion == 1,
        marker.canonicalDestination == installedHelperURL.path,
        marker.launcherDestination == legacyLauncherURL.path,
        marker.bundleIdentifier == Self.ownerBundleIdentifier,
        let canonicalData = try? fileSystem.data(at: installedHelperURL),
        let launcherData = try? fileSystem.data(at: legacyLauncherURL),
        marker.canonicalSHA256 == sha256(canonicalData),
        marker.launcherSHA256 == sha256(launcherData)
      else { return false }
      return true
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
