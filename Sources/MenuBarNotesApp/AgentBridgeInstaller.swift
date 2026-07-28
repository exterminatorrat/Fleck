#if os(macOS)
  import CryptoKit
  import Foundation

  enum AgentBridgeInstallerError: Error, Equatable {
    case bundledHelperMissing
    case destinationNotOwned
    case verificationFailed
    case processFailed(Int32)
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

  struct AgentBridgeInstaller {
    static let ownerBundleIdentifier = "com.harryjin.motes"

    let bundledHelperURL: URL
    let applicationSupportURL: URL
    private let fileSystem: any AgentBridgeInstallerFileSystem
    private let processRunner: any AgentBridgeProcessRunning
    private let installedVersion: String
    private let bundleIdentifier: String

    init(
      bundledHelperURL: URL,
      applicationSupportURL: URL,
      fileSystem: any AgentBridgeInstallerFileSystem = LocalAgentBridgeInstallerFileSystem(),
      processRunner: any AgentBridgeProcessRunning = LocalAgentBridgeProcessRunner(),
      installedVersion: String = Bundle.main.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
      ) as? String ?? "development",
      bundleIdentifier: String = Bundle.main.bundleIdentifier ?? ownerBundleIdentifier
    ) {
      self.bundledHelperURL = bundledHelperURL
      self.applicationSupportURL = applicationSupportURL
      self.fileSystem = fileSystem
      self.processRunner = processRunner
      self.installedVersion = installedVersion
      self.bundleIdentifier = bundleIdentifier
    }

    static func live() throws -> Self {
      guard let sharedSupportURL = Bundle.main.sharedSupportURL else {
        throw AgentBridgeInstallerError.bundledHelperMissing
      }
      let applicationSupportURL = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      )[0].appendingPathComponent("MenuBarNotes", isDirectory: true)
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

    private var receiptURL: URL {
      applicationSupportURL
        .appendingPathComponent("AgentBridge", isDirectory: true)
        .appendingPathComponent("install-receipt.json")
    }

    @discardableResult
    func install() throws -> URL {
      guard fileSystem.fileExists(at: bundledHelperURL) else {
        throw AgentBridgeInstallerError.bundledHelperMissing
      }
      let bundledData = try fileSystem.data(at: bundledHelperURL)
      if fileSystem.fileExists(at: installedHelperURL) {
        guard
          let prior = try? receipt(),
          prior.destination == installedHelperURL.path,
          prior.bundleIdentifier == bundleIdentifier,
          prior.sha256 == sha256(try fileSystem.data(at: installedHelperURL))
        else {
          throw AgentBridgeInstallerError.destinationNotOwned
        }
      }

      let directory = installedHelperURL.deletingLastPathComponent()
      try fileSystem.createDirectory(at: directory)
      let staging = directory.appendingPathComponent(".motes-\(UUID().uuidString).staging")
      try fileSystem.write(bundledData, to: staging)
      try fileSystem.makeExecutable(at: staging)
      defer { try? fileSystem.removeItem(at: staging) }
      try fileSystem.replaceItem(at: installedHelperURL, with: staging)
      let installedHash = sha256(try fileSystem.data(at: installedHelperURL))
      guard installedHash == sha256(bundledData) else {
        throw AgentBridgeInstallerError.verificationFailed
      }
      let receipt = AgentBridgeInstallationReceipt(
        destination: installedHelperURL.path,
        sha256: installedHash,
        installedVersion: installedVersion,
        bundleIdentifier: bundleIdentifier
      )
      try fileSystem.write(try JSONEncoder().encode(receipt), to: receiptURL)
      return installedHelperURL
    }

    func receipt() throws -> AgentBridgeInstallationReceipt {
      try JSONDecoder().decode(
        AgentBridgeInstallationReceipt.self,
        from: fileSystem.data(at: receiptURL)
      )
    }

    func provision(profileID: UUID, token: Data) throws {
      let helper = try install()
      try processRunner.run(
        executable: helper,
        arguments: [
          "configure", "--profile", profileID.uuidString, "--token-stdin",
        ],
        stdin: Data(token.base64EncodedString().utf8)
      )
    }

    func disconnect(profileID: UUID) throws {
      try processRunner.run(
        executable: installedHelperURL,
        arguments: ["disconnect", "--profile", profileID.uuidString],
        stdin: nil
      )
    }

    func removeInstalledHelper() throws {
      guard
        fileSystem.fileExists(at: installedHelperURL),
        let prior = try? receipt(),
        prior.destination == installedHelperURL.path,
        prior.bundleIdentifier == bundleIdentifier,
        prior.sha256 == sha256(try fileSystem.data(at: installedHelperURL))
      else {
        if fileSystem.fileExists(at: installedHelperURL) {
          throw AgentBridgeInstallerError.destinationNotOwned
        }
        return
      }
      try fileSystem.removeItem(at: installedHelperURL)
      try fileSystem.removeItem(at: receiptURL)
    }

    func setupSnippet(profileID: UUID) -> String {
      "\(installedHelperURL.path) mcp --profile \(profileID.uuidString)"
    }

    private func sha256(_ data: Data) -> String {
      SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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
    func run(executable: URL, arguments: [String], stdin: Data?) throws {
      let process = Process()
      process.executableURL = executable
      process.arguments = arguments
      if let stdin {
        let pipe = Pipe()
        process.standardInput = pipe
        try process.run()
        pipe.fileHandleForWriting.write(stdin)
        try pipe.fileHandleForWriting.close()
      } else {
        try process.run()
      }
      process.waitUntilExit()
      guard process.terminationStatus == 0 else {
        throw AgentBridgeInstallerError.processFailed(process.terminationStatus)
      }
    }
  }
#endif
