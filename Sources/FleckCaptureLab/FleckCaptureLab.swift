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
    guard arguments.count == 3 else { throw WebsiteDemoError.invalidArguments }
    let path = arguments[2]
    guard NSString(string: path).isAbsolutePath else {
      throw WebsiteDemoError.sessionRootMustBeAbsolute
    }

    switch (arguments[0], arguments[1]) {
    case ("prepare", "--session-root"):
      let manifest = try await WebsiteDemoSession.prepare(
        at: URL(fileURLWithPath: path, isDirectory: true),
        now: now
      )
      return """
      Session: \(manifest.sessionRoot.path)
      Manifest: \(manifest.manifestURL.path)
      Fleck app: \(manifest.fleckApp.path)
      Fake repository: \(manifest.fakeRepository.path)

      """
    case ("verify", "--manifest"):
      let state = try await WebsiteDemoSession.verify(
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
      "Use prepare --session-root <absolute-path> or verify --manifest <absolute-path>."
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
  static func prepare(at root: URL, now: Date = Date()) async throws -> WebsiteDemoManifest {
    let fileManager = FileManager.default
    let sessionRoot = try safeSessionRoot(root)
    try fileManager.createDirectory(at: sessionRoot, withIntermediateDirectories: true)

    let fleckRoot = sessionRoot
      .appendingPathComponent("Library/Application Support/Fleck", isDirectory: true)
    let fakeRepository = sessionRoot.appendingPathComponent("NorthstarDemo", isDirectory: true)
    let manifest = WebsiteDemoManifest(
      sessionRoot: sessionRoot,
      fleckRoot: fleckRoot,
      fakeRepository: fakeRepository,
      fleckApp: packageRoot.appendingPathComponent(".build/Fleck.app", isDirectory: true),
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
        theme: .light,
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
    let expectedFleckRoot = sessionRoot
      .appendingPathComponent("Library/Application Support/Fleck", isDirectory: true)
    let expectedRepository = sessionRoot.appendingPathComponent("NorthstarDemo", isDirectory: true)
    let expectedFleckApp = packageRoot
      .appendingPathComponent(".build/Fleck.app", isDirectory: true)
    guard manifestURL == manifest.manifestURL.standardizedFileURL.resolvingSymlinksInPath(),
      manifest.fleckRoot.standardizedFileURL == expectedFleckRoot.standardizedFileURL,
      manifest.fakeRepository.standardizedFileURL == expectedRepository.standardizedFileURL,
      manifest.fleckApp.standardizedFileURL == expectedFleckApp.standardizedFileURL,
      manifest.projectNames == WebsiteDemoFixture.projectNames,
      manifest.captureCommands == WebsiteDemoFixture.captureCommands,
      !containsForbiddenMaterial(data)
    else {
      throw WebsiteDemoError.invalidManifest
    }

    let snapshot: LocalStoreSnapshot
    do {
      snapshot = try await LocalStore(rootURL: expectedFleckRoot).loadSnapshot()
    } catch {
      throw WebsiteDemoError.verificationFailed
    }
    let notes = snapshot.workspace.notes
    guard notes.map(\.id) == [
      WebsiteDemoFixture.northstarNoteID,
      WebsiteDemoFixture.relayNoteID,
      WebsiteDemoFixture.canvasNoteID,
      WebsiteDemoFixture.inboxNoteID,
    ],
      notes.map(\.title) == ["Northstar Demo", "Relay Demo", "Canvas Demo", "Inbox"],
      snapshot.workspace.selectedNoteID == WebsiteDemoFixture.northstarNoteID,
      notes[0].isPinned,
      notes.filter(\.agentAccess).map(\.id) == [WebsiteDemoFixture.northstarNoteID],
      snapshot.preferences.theme == .light,
      snapshot.preferences.onboardingProgress?.status == .completed,
      requiredRepositoryFiles.allSatisfy({ relativePath in
        FileManager.default.fileExists(
          atPath: expectedRepository.appendingPathComponent(relativePath).path
        )
      })
    else {
      throw WebsiteDemoError.verificationFailed
    }

    let tasks = AgentNoteMutationEngine.tasks(in: notes[0].body)
    guard tasks.count == 1,
      tasks[0].text == "Update onboarding permission order and add regression coverage."
    else {
      throw WebsiteDemoError.verificationFailed
    }
    return tasks[0].completed ? .completed : .open
  }

  private static let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

  private static let requiredRepositoryFiles = [
    "Package.swift",
    "README.md",
    "Sources/NorthstarDemo/OnboardingFlow.swift",
    "Tests/NorthstarDemoTests/OnboardingFlowTests.swift",
  ]

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

  private static func write(_ manifest: WebsiteDemoManifest) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(manifest).write(to: manifest.manifestURL, options: .atomic)
  }

  private static func containsForbiddenMaterial(_ data: Data) -> Bool {
    let text = String(decoding: data, as: UTF8.self).lowercased()
    return ["token", "credential", "verifier", "api_key", "footprint"]
      .contains(where: text.contains)
  }

  private static func createSyntheticRepository(at root: URL, now: Date) throws {
    let files = [
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
    process.environment = environment
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw WebsiteDemoError.gitCommandFailed
    }
  }
}
