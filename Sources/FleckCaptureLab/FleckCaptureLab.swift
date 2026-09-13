import CryptoKit
import Darwin
import Foundation
import FleckCore

@main
enum FleckCaptureLab {
  static func main() async {
    do {
      let output = try await run(arguments: Array(CommandLine.arguments.dropFirst()))
      FileHandle.standardOutput.write(Data(output.utf8))
    } catch {
      FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
      Darwin.exit(1)
    }
  }

  static func run(arguments: [String], now: Date = Date()) async throws -> String {
    guard arguments.count >= 3 else { throw WebsiteDemoError.invalidArguments }
    let path = arguments[2]
    guard NSString(string: path).isAbsolutePath else {
      throw WebsiteDemoError.sessionRootMustBeAbsolute
    }

    switch (arguments[0], arguments[1]) {
    case ("prepare", "--session-root") where arguments.count == 5 && arguments[3] == "--fleck-app":
      let fleckAppPath = arguments[4]
      guard NSString(string: fleckAppPath).isAbsolutePath else {
        throw WebsiteDemoError.invalidManifest
      }
      let manifest = try await WebsiteDemoSession.prepare(
        at: URL(fileURLWithPath: path, isDirectory: true),
        fleckApp: URL(fileURLWithPath: fleckAppPath, isDirectory: true),
        now: now
      )
      return """
      Session: \(manifest.sessionRoot.path)
      Manifest: \(manifest.manifestURL.path)
      Fleck app: \(manifest.fleckApp.path)
      Fake repository: \(manifest.fakeRepository.path)

      """
    case ("verify", "--manifest") where arguments.count == 3:
      let state = try await WebsiteDemoSession.verify(
        manifestAt: URL(fileURLWithPath: path)
      )
      return "Task state: \(state.rawValue)\n"
    case ("postflight", "--manifest") where arguments.count == 3:
      let state = try await WebsiteDemoSession.postflight(
        manifestAt: URL(fileURLWithPath: path)
      )
      return "Task state: \(state.rawValue)\n"
    default:
      throw WebsiteDemoError.invalidArguments
    }
  }
}

enum WebsiteDemoError: Error, Equatable {
  case invalidArguments
  case sessionRootMustBeAbsolute
  case unsafeSessionRoot
  case sessionAlreadyPrepared
  case invalidManifest
  case verificationFailed
  case gitCommandFailed
}

extension WebsiteDemoError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .invalidArguments:
      "Use prepare --session-root <absolute-path> --fleck-app <absolute-versioned-app>, verify --manifest <absolute-path>, or postflight --manifest <absolute-path>."
    case .sessionRootMustBeAbsolute:
      "The capture-lab path must be absolute."
    case .unsafeSessionRoot:
      "The capture-lab path cannot be the filesystem root or user home."
    case .sessionAlreadyPrepared:
      "The capture session already contains prepared data."
    case .invalidManifest:
      "The capture manifest is invalid."
    case .verificationFailed:
      "The capture session does not match the synthetic fixture."
    case .gitCommandFailed:
      "The synthetic repository could not be initialized."
    }
  }
}

enum WebsiteDemoTaskState: String, Equatable, Sendable {
  case open
  case completed
}

struct WebsiteDemoCaptureCommands: Codable, Equatable, Sendable {
  let dictation: String
  let agentPrompt: String
  let approval: String
}

struct WebsiteDemoManifest: Codable, Equatable, Sendable {
  let sessionRoot: URL
  let fleckRoot: URL
  let fakeRepository: URL
  let fleckApp: URL
  let projectNames: [String]
  let captureCommands: WebsiteDemoCaptureCommands

  var manifestURL: URL {
    sessionRoot.appendingPathComponent("fleck-capture-manifest.json")
  }

  private enum CodingKeys: String, CodingKey {
    case sessionRoot
    case fleckRoot
    case fakeRepository
    case fleckApp
    case projectNames
    case captureCommands
  }

  init(
    sessionRoot: URL,
    fleckRoot: URL,
    fakeRepository: URL,
    fleckApp: URL,
    projectNames: [String],
    captureCommands: WebsiteDemoCaptureCommands
  ) {
    self.sessionRoot = sessionRoot
    self.fleckRoot = fleckRoot
    self.fakeRepository = fakeRepository
    self.fleckApp = fleckApp
    self.projectNames = projectNames
    self.captureCommands = captureCommands
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let sessionRoot = try container.decode(String.self, forKey: .sessionRoot)
    let fleckRoot = try container.decode(String.self, forKey: .fleckRoot)
    let fakeRepository = try container.decode(String.self, forKey: .fakeRepository)
    let fleckApp = try container.decode(String.self, forKey: .fleckApp)
    guard [sessionRoot, fleckRoot, fakeRepository, fleckApp]
      .allSatisfy({ NSString(string: $0).isAbsolutePath })
    else {
      throw DecodingError.dataCorruptedError(
        forKey: .sessionRoot,
        in: container,
        debugDescription: "Manifest paths must be absolute."
      )
    }
    self.sessionRoot = URL(fileURLWithPath: sessionRoot, isDirectory: true)
    self.fleckRoot = URL(fileURLWithPath: fleckRoot, isDirectory: true)
    self.fakeRepository = URL(fileURLWithPath: fakeRepository, isDirectory: true)
    self.fleckApp = URL(fileURLWithPath: fleckApp, isDirectory: true)
    projectNames = try container.decode([String].self, forKey: .projectNames)
    captureCommands = try container.decode(
      WebsiteDemoCaptureCommands.self,
      forKey: .captureCommands
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(sessionRoot.path, forKey: .sessionRoot)
    try container.encode(fleckRoot.path, forKey: .fleckRoot)
    try container.encode(fakeRepository.path, forKey: .fakeRepository)
    try container.encode(fleckApp.path, forKey: .fleckApp)
    try container.encode(projectNames, forKey: .projectNames)
    try container.encode(captureCommands, forKey: .captureCommands)
  }
}

enum WebsiteDemoFixture {
  static let projectNames = ["Northstar Demo", "Relay Demo", "Canvas Demo"]
  static let captureCommands = WebsiteDemoCaptureCommands(
    dictation: "Northstar Demo: move the location permission request until after onboarding.",
    agentPrompt: "Pick up where I left off.",
    approval: "Do it."
  )
  static let northstarNoteID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
  static let relayNoteID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
  static let canvasNoteID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
  static let inboxNoteID = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
  static let projectsFolderID = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!

  static func workspace(now: Date) throws -> Workspace {
    let projects = try Folder(id: projectsFolderID, name: "Projects")
    let northstar = Note(
      id: northstarNoteID,
      title: "Northstar Demo",
      body: """
      # Onboarding handoff

      Decision: Ask for location only after the welcome walkthrough, when the user understands why it is needed.

      ○ Update onboarding permission order and add regression coverage.
      """,
      tabColorHex: "#6D5DF6",
      createdAt: now,
      modifiedAt: now,
      isPinned: true,
      agentAccess: true,
      folderID: projects.id
    )
    let relay = Note(
      id: relayNoteID,
      title: "Relay Demo",
      body: "# Release notes\n\nDocument the offline retry behavior before beta.",
      createdAt: now,
      modifiedAt: now,
      folderID: projects.id
    )
    let canvas = Note(
      id: canvasNoteID,
      title: "Canvas Demo",
      body: "# Editor polish\n\nKeep the formatting toolbar quiet until text is selected.",
      createdAt: now,
      modifiedAt: now,
      folderID: projects.id
    )
    let inbox = Note(
      id: inboxNoteID,
      title: "Inbox",
      body: "",
      createdAt: now,
      modifiedAt: now
    )
    return Workspace(
      notes: [northstar, relay, canvas, inbox],
      selectedNoteID: northstar.id,
      folders: [projects]
    )
  }
}

enum WebsiteDemoSession {
  static func prepare(
    at root: URL,
    fleckApp: URL,
    now: Date = Date()
  ) async throws -> WebsiteDemoManifest {
    let fileManager = FileManager.default
    let sessionRoot = try safeSessionRoot(root)
    try fileManager.createDirectory(at: sessionRoot, withIntermediateDirectories: true)

    let fleckRoot = sessionRoot
      .appendingPathComponent("Library/Application Support/Fleck", isDirectory: true)
    let fakeRepository = sessionRoot.appendingPathComponent("NorthstarDemo", isDirectory: true)
    guard isSupportedFleckApp(fleckApp, allowLegacy: false) else {
      throw WebsiteDemoError.invalidManifest
    }
    let manifest = WebsiteDemoManifest(
      sessionRoot: sessionRoot,
      fleckRoot: fleckRoot,
      fakeRepository: fakeRepository,
      fleckApp: fleckApp,
      projectNames: WebsiteDemoFixture.projectNames,
      captureCommands: WebsiteDemoFixture.captureCommands
    )
    guard !fileManager.fileExists(atPath: fleckRoot.path),
      !fileManager.fileExists(atPath: fakeRepository.path),
      !fileManager.fileExists(atPath: manifest.manifestURL.path)
    else {
      throw WebsiteDemoError.sessionAlreadyPrepared
    }

    let store = LocalStore(rootURL: fleckRoot)
    guard try await store.save(
      workspace: WebsiteDemoFixture.workspace(now: now),
      preferences: AppPreferences(
        theme: .dark,
        onboardingProgress: OnboardingProgress(status: .completed)
      )
    ) == .committed else {
      throw WebsiteDemoError.verificationFailed
    }
    try createSyntheticRepository(at: fakeRepository, now: now)
    try write(manifest)
    return manifest
  }

  static func verify(manifestAt url: URL) async throws -> WebsiteDemoTaskState {
    try await verify(manifestAt: url, kind: .seed)
  }

  static func postflight(manifestAt url: URL) async throws -> WebsiteDemoTaskState {
    try await verify(manifestAt: url, kind: .postflight)
  }

  private enum VerificationKind {
    case seed
    case postflight
  }

  private static func verify(
    manifestAt url: URL,
    kind: VerificationKind
  ) async throws -> WebsiteDemoTaskState {
    guard url.isFileURL, url.path.hasPrefix("/") else {
      throw WebsiteDemoError.sessionRootMustBeAbsolute
    }
    let manifestURL = url.standardizedFileURL.resolvingSymlinksInPath()
    let data: Data
    let manifest: WebsiteDemoManifest
    do {
      data = try Data(contentsOf: manifestURL)
      manifest = try JSONDecoder().decode(WebsiteDemoManifest.self, from: data)
    } catch {
      throw WebsiteDemoError.invalidManifest
    }

    let sessionRoot = try safeSessionRoot(manifest.sessionRoot)
    let canonicalManifestData: Data
    do {
      canonicalManifestData = try encodedManifest(manifest)
    } catch {
      throw WebsiteDemoError.invalidManifest
    }
    let expectedFleckRoot = sessionRoot
      .appendingPathComponent("Library/Application Support/Fleck", isDirectory: true)
    let expectedRepository = sessionRoot.appendingPathComponent("NorthstarDemo", isDirectory: true)
    guard data == canonicalManifestData,
      manifestURL == manifest.manifestURL.standardizedFileURL.resolvingSymlinksInPath(),
      manifest.fleckRoot.standardizedFileURL == expectedFleckRoot.standardizedFileURL,
      manifest.fakeRepository.standardizedFileURL == expectedRepository.standardizedFileURL,
      isSupportedFleckApp(manifest.fleckApp, allowLegacy: true),
      manifest.projectNames == WebsiteDemoFixture.projectNames,
      manifest.captureCommands == WebsiteDemoFixture.captureCommands
    else {
      throw WebsiteDemoError.invalidManifest
    }

    let snapshot: LocalStoreSnapshot
    do {
      snapshot = try await LocalStore(rootURL: expectedFleckRoot).loadSnapshot()
    } catch {
      throw WebsiteDemoError.verificationFailed
    }
    let state: WebsiteDemoTaskState
    do {
      let codexProfileID: UUID?
      switch kind {
      case .seed:
        codexProfileID = nil
      case .postflight:
        codexProfileID = try verifiedCodexProfileID(at: expectedFleckRoot)
      }
      state = try verifiedTaskState(
        in: snapshot,
        kind: kind,
        codexProfileID: codexProfileID
      )
      switch kind {
      case .seed:
        try verifySyntheticRepository(at: expectedRepository)
      case .postflight:
        try verifyCompletedSyntheticRepository(at: expectedRepository)
      }
    } catch {
      throw WebsiteDemoError.verificationFailed
    }
    return state
  }

  private static let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

  private static let legacyFleckApp = packageRoot
    .appendingPathComponent(".build/parakeet-test/Fleck.app", isDirectory: true)

  private static func isSupportedFleckApp(_ app: URL, allowLegacy: Bool) -> Bool {
    guard app.isFileURL, app.path.hasPrefix("/"), app.standardizedFileURL == app else {
      return false
    }
    if allowLegacy, app == legacyFleckApp {
      return true
    }
    let parent = packageRoot.appendingPathComponent(".build/parakeet-test", isDirectory: true)
    guard app.deletingLastPathComponent() == parent else {
      return false
    }
    return app.lastPathComponent.range(
      of: #"^Fleck [0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)? Build [1-9][0-9]*\.app$"#,
      options: .regularExpression
    ) != nil
  }

  private static let requiredRepositoryFiles = [
    "AGENTS.md",
    "Package.swift",
    "README.md",
    "Sources/NorthstarDemo/OnboardingFlow.swift",
    "Tests/NorthstarDemoTests/OnboardingFlowTests.swift",
  ]

  private static let syntheticRepositoryTreeID = "a44703c57fe485f3491d0826f21bce8146d3ae4e"

  private static let completedRepositoryFiles = [
    "Sources/NorthstarDemo/OnboardingFlow.swift",
    "Tests/NorthstarDemoTests/OnboardingFlowTests.swift",
  ]

  private static let completedOnboardingSource = """
    public enum PermissionRequestPoint: Equatable, Sendable {
      case firstLaunch
      case afterWelcome
    }

    public struct OnboardingFlow: Sendable {
      public init() {}
      public var permissionRequestPoint: PermissionRequestPoint { .afterWelcome }
      public var welcomeStepCount: Int { 3 }
    }
    """

  private static let completedOnboardingTests = """
    import NorthstarDemo
    import Testing

    @Test func welcomeFlowHasThreeSteps() {
      #expect(OnboardingFlow().welcomeStepCount == 3)
    }

    @Test func requestsLocationAfterWelcome() {
      #expect(OnboardingFlow().permissionRequestPoint == .afterWelcome)
    }
    """

  private static func safeSessionRoot(_ root: URL) throws -> URL {
    guard root.isFileURL, root.path.hasPrefix("/") else {
      throw WebsiteDemoError.sessionRootMustBeAbsolute
    }
    let sessionRoot = root.standardizedFileURL.resolvingSymlinksInPath()
    let userHome = FileManager.default.homeDirectoryForCurrentUser
      .standardizedFileURL.resolvingSymlinksInPath()
    guard sessionRoot.path != "/", sessionRoot != userHome else {
      throw WebsiteDemoError.unsafeSessionRoot
    }
    return sessionRoot
  }

  private static func encodedManifest(_ manifest: WebsiteDemoManifest) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(manifest)
  }

  private static func write(_ manifest: WebsiteDemoManifest) throws {
    try encodedManifest(manifest).write(to: manifest.manifestURL, options: .atomic)
  }

  private static func verifiedTaskState(
    in snapshot: LocalStoreSnapshot,
    kind: VerificationKind,
    codexProfileID: UUID?
  ) throws -> WebsiteDemoTaskState {
    let expectedPreferences = AppPreferences(
      theme: .dark,
      onboardingProgress: OnboardingProgress(status: .completed)
    )
    guard snapshot.preferences == expectedPreferences,
      snapshot.source == .root,
      snapshot.folderMigrationWarnings.isEmpty,
      let fixtureDate = snapshot.workspace.notes.first?.createdAt
    else {
      throw WebsiteDemoError.verificationFailed
    }

    let openWorkspace = try WebsiteDemoFixture.workspace(now: fixtureDate)
    let state: WebsiteDemoTaskState
    if snapshot.workspace == openWorkspace, snapshot.generation == 0 {
      state = .open
    } else {
      guard let actualNorthstar = snapshot.workspace.notes.first,
        actualNorthstar.modifiedAt >= actualNorthstar.createdAt,
        let task = AgentNoteMutationEngine.tasks(in: openWorkspace.notes[0].body).first
      else {
        throw WebsiteDemoError.verificationFailed
      }
      let mutation = try AgentNoteMutationEngine.setTaskState(
        task,
        completed: true,
        in: openWorkspace.notes[0].body
      )
      var completedWorkspace = openWorkspace
      completedWorkspace.updateNote(
        id: WebsiteDemoFixture.northstarNoteID,
        body: mutation.body,
        now: actualNorthstar.modifiedAt
      )
      guard snapshot.workspace == completedWorkspace, snapshot.generation == 1 else {
        throw WebsiteDemoError.verificationFailed
      }
      state = .completed
    }

    switch kind {
    case .seed:
      guard snapshot.commitProofs.isEmpty else {
        throw WebsiteDemoError.verificationFailed
      }
    case .postflight:
      guard state == .completed,
        let northstar = snapshot.workspace.notes.first,
        let codexProfileID,
        verifiesPostflightProof(
          snapshot.commitProofs,
          northstar: northstar,
          codexProfileID: codexProfileID
        )
      else {
        throw WebsiteDemoError.verificationFailed
      }
    }
    return state
  }

  private static func verifySyntheticRepository(at root: URL) throws {
    try verifyRepositoryIdentity(at: root)
    guard try gitOutput(
      ["status", "--porcelain=v1", "--untracked-files=all"],
      at: root
    ).isEmpty,
      try gitOutput(["ls-files", "--others", "--ignored", "--exclude-standard"], at: root)
        .isEmpty
    else {
      throw WebsiteDemoError.verificationFailed
    }
  }

  private static func verifyCompletedSyntheticRepository(at root: URL) throws {
    try verifyRepositoryIdentity(at: root)
    let source = try String(
      contentsOf: root.appendingPathComponent(completedRepositoryFiles[0]),
      encoding: .utf8
    )
    let tests = try String(
      contentsOf: root.appendingPathComponent(completedRepositoryFiles[1]),
      encoding: .utf8
    )
    guard try gitOutput(["diff", "--name-only", "--"], at: root)
      == completedRepositoryFiles.joined(separator: "\n"),
      try gitOutput(["diff", "--cached", "--name-only", "--"], at: root).isEmpty,
      try gitOutput(["ls-files", "--others", "--exclude-standard"], at: root).isEmpty,
      try gitOutput(["ls-files", "--others", "--ignored", "--exclude-standard"], at: root)
        .isEmpty,
      try gitOutput(["diff", "--check", "--"], at: root).isEmpty,
      source == completedOnboardingSource,
      tests == completedOnboardingTests
    else {
      throw WebsiteDemoError.verificationFailed
    }
  }

  private static func verifyRepositoryIdentity(at root: URL) throws {
    let gitDirectory = root.appendingPathComponent(".git", isDirectory: true)
    let gitValues = try gitDirectory.resourceValues(
      forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
    )
    guard gitValues.isDirectory == true,
      gitValues.isSymbolicLink != true
    else {
      throw WebsiteDemoError.verificationFailed
    }

    guard try gitOutput(["remote"], at: root).isEmpty,
      try gitOutput(["rev-parse", "HEAD^{tree}"], at: root) == syntheticRepositoryTreeID,
      try gitOutput(["branch", "--show-current"], at: root) == "main",
      try gitOutput(["rev-list", "--count", "HEAD"], at: root) == "1",
      try gitOutput(["for-each-ref", "--format=%(refname)"], at: root) == "refs/heads/main",
      try gitOutput(["log", "-1", "--format=%s"], at: root)
        == "chore: seed synthetic Northstar demo",
      try gitOutput(["log", "-1", "--format=%an <%ae>"], at: root)
        == "Fleck Demo <demo@invalid.example>",
      try gitOutput(["config", "--local", "--get", "user.name"], at: root) == "Fleck Demo",
      try gitOutput(["config", "--local", "--get", "user.email"], at: root)
        == "demo@invalid.example"
    else {
      throw WebsiteDemoError.verificationFailed
    }
  }

  private static func verifiesPostflightProof(
    _ proofs: [AgentWorkspaceCommitProof],
    northstar: Note,
    codexProfileID: UUID
  ) -> Bool {
    guard proofs.count == 1, let proof = proofs.first,
      northstar.id == WebsiteDemoFixture.northstarNoteID,
      northstar.revision == 1,
      proof.noteID == northstar.id,
      proof.resultingRevision == northstar.revision,
      proof.bodySHA256 == bodySHA256(northstar.body),
      proof.expiresAt > northstar.modifiedAt,
      case .integration(let proofProfileID, let displayName) = proof.actor,
      proofProfileID == codexProfileID,
      displayName == "Codex"
    else {
      return false
    }
    return true
  }

  private static func verifiedCodexProfileID(at fleckRoot: URL) throws -> UUID {
    let profilesURL = fleckRoot.appendingPathComponent("AgentIntegrations/profiles.json")
    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: profilesURL))
    guard let profiles = object as? [[String: Any]] else {
      throw WebsiteDemoError.verificationFailed
    }
    var profileIDs: [UUID] = []
    for profile in profiles
    where profile["displayName"] as? String == "Codex" && profile["revokedAt"] == nil {
      guard let id = profile["id"] as? String, let profileID = UUID(uuidString: id) else {
        throw WebsiteDemoError.verificationFailed
      }
      profileIDs.append(profileID)
    }
    guard profileIDs.count == 1, let profileID = profileIDs.first else {
      throw WebsiteDemoError.verificationFailed
    }
    return profileID
  }

  private static func bodySHA256(_ body: String) -> String {
    SHA256.hash(data: Data(body.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
  }

  private static func createSyntheticRepository(at root: URL, now: Date) throws {
    let files = [
      "AGENTS.md": """
      When asked to pick up where the user left off, inspect the available Fleck tools for the open Northstar Demo handoff. Make the requested change in this synthetic repository, run its tests, and only after they pass update the originating Fleck task to reflect the completed work. Do not use network access or add a git remote.
      """,
      "Package.swift": """
      // swift-tools-version: 6.0

      import PackageDescription

      let package = Package(
        name: "NorthstarDemo",
        platforms: [.macOS(.v14)],
        products: [
          .library(name: "NorthstarDemo", targets: ["NorthstarDemo"]),
        ],
        targets: [
          .target(name: "NorthstarDemo"),
          .testTarget(name: "NorthstarDemoTests", dependencies: ["NorthstarDemo"]),
        ]
      )
      """,
      "README.md": """
      # Northstar Demo

      This repository contains only synthetic website-demo data for Fleck captures.
      """,
      "Sources/NorthstarDemo/OnboardingFlow.swift": """
      public enum PermissionRequestPoint: Equatable, Sendable {
        case firstLaunch
        case afterWelcome
      }

      public struct OnboardingFlow: Sendable {
        public init() {}
        public var permissionRequestPoint: PermissionRequestPoint { .firstLaunch }
        public var welcomeStepCount: Int { 3 }
      }
      """,
      "Tests/NorthstarDemoTests/OnboardingFlowTests.swift": """
      import NorthstarDemo
      import Testing

      @Test func welcomeFlowHasThreeSteps() {
        #expect(OnboardingFlow().welcomeStepCount == 3)
      }
      """,
    ]
    for path in files.keys.sorted() {
      let url = root.appendingPathComponent(path)
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try Data(files[path]!.utf8).write(to: url, options: .atomic)
    }

    try runGit(["init", "--quiet", "--initial-branch=main"], at: root)
    try runGit(["config", "--local", "user.name", "Fleck Demo"], at: root)
    try runGit(["config", "--local", "user.email", "demo@invalid.example"], at: root)
    try runGit(["add", "--"] + requiredRepositoryFiles, at: root)
    try runGit(
      ["commit", "--quiet", "-m", "chore: seed synthetic Northstar demo"],
      at: root,
      now: now
    )
  }

  private static func runGit(_ arguments: [String], at root: URL, now: Date? = nil) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments
    process.currentDirectoryURL = root
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    process.environment = gitEnvironment(now: now)
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw WebsiteDemoError.gitCommandFailed
    }
  }

  private static func gitOutput(_ arguments: [String], at root: URL) throws -> String {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments
    process.currentDirectoryURL = root
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    process.environment = gitEnvironment(now: nil)
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw WebsiteDemoError.gitCommandFailed
    }
    return String(decoding: data, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func gitEnvironment(now: Date?) -> [String: String] {
    var environment = ProcessInfo.processInfo.environment
    for key in Array(environment.keys) where key.uppercased().hasPrefix("GIT_") {
      environment.removeValue(forKey: key)
    }
    environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
    environment["GIT_CONFIG_NOSYSTEM"] = "1"
    environment["GIT_AUTHOR_NAME"] = "Fleck Demo"
    environment["GIT_AUTHOR_EMAIL"] = "demo@invalid.example"
    environment["GIT_COMMITTER_NAME"] = "Fleck Demo"
    environment["GIT_COMMITTER_EMAIL"] = "demo@invalid.example"
    if let now {
      let date = "@\(Int(now.timeIntervalSince1970)) +0000"
      environment["GIT_AUTHOR_DATE"] = date
      environment["GIT_COMMITTER_DATE"] = date
    }
    return environment
  }
}
