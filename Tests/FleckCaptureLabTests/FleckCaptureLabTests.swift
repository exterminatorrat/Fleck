import Darwin
import Foundation
import FleckCore
import Testing

@testable import FleckCaptureLab

private struct TemporaryDirectory {
  let url: URL

  init() throws {
    let base = FileManager.default.temporaryDirectory
      .appendingPathComponent("fleck-capture-lab-tests", isDirectory: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    let path = try FileManager.default.url(
      for: .itemReplacementDirectory,
      in: .userDomainMask,
      appropriateFor: base,
      create: true
    )
    url = path
  }
}

private enum TestCommandError: Error {
  case failed(Int32, String)
}

@discardableResult
private func replaceAmbientGitEnvironment(
  with replacement: [String: String]
) -> [String: String] {
  let current = ProcessInfo.processInfo.environment
  let previous = current.filter { $0.key.uppercased().hasPrefix("GIT_") }
  for key in current.keys where key.uppercased().hasPrefix("GIT_") {
    unsetenv(key)
  }
  for (key, value) in replacement {
    setenv(key, value, 1)
  }
  return previous
}

private func gitOutput(_ arguments: [String], repository: URL) throws -> String {
  let process = Process()
  let output = Pipe()
  let errors = Pipe()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
  process.arguments = arguments
  process.currentDirectoryURL = repository
  process.standardOutput = output
  process.standardError = errors
  var environment = ProcessInfo.processInfo.environment
  for key in Array(environment.keys) where key.uppercased().hasPrefix("GIT_") {
    environment.removeValue(forKey: key)
  }
  environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
  environment["GIT_CONFIG_NOSYSTEM"] = "1"
  process.environment = environment
  try process.run()
  process.waitUntilExit()
  let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
  guard process.terminationStatus == 0 else {
    let error = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    throw TestCommandError.failed(process.terminationStatus, error)
  }
  return text.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func regularFilePaths(in root: URL) throws -> [String] {
  let rootPath = root.resolvingSymlinksInPath().path
  guard let enumerator = FileManager.default.enumerator(
    at: root,
    includingPropertiesForKeys: [.isRegularFileKey],
    options: [.skipsHiddenFiles]
  ) else {
    return []
  }
  var files: [String] = []
  for case let fileURL as URL in enumerator {
    let filePath = fileURL.resolvingSymlinksInPath().path
    guard filePath.hasPrefix(rootPath + "/") else { continue }
    let relativePath = String(filePath.dropFirst(rootPath.count + 1))
    guard !relativePath.hasPrefix(".git/") else { continue }
    guard try fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
      continue
    }
    files.append(relativePath)
  }
  return files.sorted()
}

@Test func preparesOnlySyntheticCaptureData() async throws {
  let session = try TemporaryDirectory()
  let now = Date(timeIntervalSince1970: 1_725_000_000)

  let manifest = try await WebsiteDemoSession.prepare(at: session.url, now: now)
  let snapshot = try await LocalStore(rootURL: manifest.fleckRoot).loadSnapshot()

  #expect(snapshot.workspace.notes.map(\.title) == [
    "Northstar Demo", "Relay Demo", "Canvas Demo", "Inbox",
  ])
  #expect(snapshot.workspace.selectedNoteID == WebsiteDemoFixture.northstarNoteID)
  #expect(snapshot.workspace.notes.filter(\.agentAccess).map(\.title) == ["Northstar Demo"])
  let tasks = AgentNoteMutationEngine.tasks(in: snapshot.workspace.notes[0].body)
  #expect(tasks.count == 1)
  #expect(tasks.first?.text == "Update onboarding permission order and add regression coverage.")
  #expect(tasks.first?.completed == false)
  #expect(snapshot.preferences.onboardingProgress?.status == .completed)
}

@Test func refusesAnExistingFleckWorkspace() async throws {
  let session = try TemporaryDirectory()
  let fleckRoot = session.url
    .appendingPathComponent("Library/Application Support/Fleck", isDirectory: true)
  try FileManager.default.createDirectory(at: fleckRoot, withIntermediateDirectories: true)

  await #expect(throws: WebsiteDemoError.sessionAlreadyPrepared) {
    try await WebsiteDemoSession.prepare(at: session.url, now: Date(timeIntervalSince1970: 1))
  }
}

@Test func refusesAnExistingCaptureManifest() async throws {
  let session = try TemporaryDirectory()
  let manifestURL = session.url.appendingPathComponent("fleck-capture-manifest.json")
  try Data("{}".utf8).write(to: manifestURL)

  await #expect(throws: WebsiteDemoError.sessionAlreadyPrepared) {
    try await WebsiteDemoSession.prepare(at: session.url, now: Date(timeIntervalSince1970: 1))
  }
}

@Test func requiresAnAbsoluteSessionRoot() async {
  await #expect(throws: WebsiteDemoError.sessionRootMustBeAbsolute) {
    try await WebsiteDemoSession.prepare(
      at: URL(string: "relative-session")!,
      now: Date(timeIntervalSince1970: 1)
    )
  }
}

@Test func manifestContainsNoCredentialOrRealWorkspaceMaterial() async throws {
  let session = try TemporaryDirectory()
  let manifest = try await WebsiteDemoSession.prepare(
    at: session.url,
    now: Date(timeIntervalSince1970: 1_725_000_000)
  )
  let encoded = try Data(contentsOf: manifest.manifestURL)
  let text = String(decoding: encoded, as: UTF8.self).lowercased()

  for forbidden in ["token", "credential", "verifier", "api_key", "footprint"] {
    #expect(!text.contains(forbidden))
  }
}

@Test func manifestEncodesShellConsumableAbsolutePaths() async throws {
  let session = try TemporaryDirectory()
  let manifest = try await WebsiteDemoSession.prepare(
    at: session.url,
    now: Date(timeIntervalSince1970: 1_725_000_000)
  )
  let object = try #require(
    JSONSerialization.jsonObject(with: Data(contentsOf: manifest.manifestURL))
      as? [String: Any]
  )

  #expect(object["sessionRoot"] as? String == manifest.sessionRoot.path)
  #expect(object["fleckRoot"] as? String == manifest.fleckRoot.path)
  #expect(object["fakeRepository"] as? String == manifest.fakeRepository.path)
  #expect(object["fleckApp"] as? String == manifest.fleckApp.path)
}

@Test func verifierRejectsUnsafeSessionRootsBeforeWorkspaceAccess() async throws {
  let session = try TemporaryDirectory()
  let validManifest = try await WebsiteDemoSession.prepare(
    at: session.url,
    now: Date(timeIntervalSince1970: 1_725_000_000)
  )
  let unsafeRoots = [
    URL(fileURLWithPath: "/", isDirectory: true),
    FileManager.default.homeDirectoryForCurrentUser,
  ]

  for (index, unsafeRoot) in unsafeRoots.enumerated() {
    let craftedManifest = WebsiteDemoManifest(
      sessionRoot: unsafeRoot,
      fleckRoot: unsafeRoot
        .appendingPathComponent("Library/Application Support/Fleck", isDirectory: true),
      fakeRepository: unsafeRoot.appendingPathComponent("NorthstarDemo", isDirectory: true),
      fleckApp: validManifest.fleckApp,
      projectNames: validManifest.projectNames,
      captureCommands: validManifest.captureCommands
    )
    let craftedURL = session.url.appendingPathComponent("unsafe-manifest-\(index).json")
    try JSONEncoder().encode(craftedManifest).write(to: craftedURL)

    await #expect(throws: WebsiteDemoError.unsafeSessionRoot) {
      try await WebsiteDemoSession.verify(manifestAt: craftedURL)
    }
  }
}

@Test func ignoresPoisonedAmbientGitRedirectors() async throws {
  let session = try TemporaryDirectory()
  let poison = try TemporaryDirectory()
  let poisonWorkTree = poison.url.appendingPathComponent("worktree", isDirectory: true)
  try FileManager.default.createDirectory(at: poisonWorkTree, withIntermediateDirectories: true)
  let poisonGitDirectory = poison.url.appendingPathComponent("external.git", isDirectory: true)
  let poisonIndex = poison.url.appendingPathComponent("external.index")
  let poisonObjects = poison.url.appendingPathComponent("objects", isDirectory: true)
  let previousEnvironment = replaceAmbientGitEnvironment(with: [
    "GIT_DIR": poisonGitDirectory.path,
    "GIT_WORK_TREE": poisonWorkTree.path,
    "GIT_INDEX_FILE": poisonIndex.path,
    "GIT_OBJECT_DIRECTORY": poisonObjects.path,
  ])
  defer { replaceAmbientGitEnvironment(with: previousEnvironment) }

  let manifest = try await WebsiteDemoSession.prepare(
    at: session.url,
    now: Date(timeIntervalSince1970: 1_725_000_000)
  )

  #expect(try gitOutput(["branch", "--show-current"], repository: manifest.fakeRepository) == "main")
  #expect(!FileManager.default.fileExists(atPath: poisonGitDirectory.path))
  #expect(!FileManager.default.fileExists(atPath: poisonIndex.path))
  #expect(!FileManager.default.fileExists(atPath: poisonObjects.path))
  #expect(try FileManager.default.contentsOfDirectory(atPath: poisonWorkTree.path).isEmpty)
}

@Test func generatesExactSyntheticRepositoryContract() async throws {
  let session = try TemporaryDirectory()
  let manifest = try await WebsiteDemoSession.prepare(
    at: session.url,
    now: Date(timeIntervalSince1970: 1_725_000_000)
  )
  let files = try regularFilePaths(in: manifest.fakeRepository)
  #expect(files == [
    "Package.swift",
    "README.md",
    "Sources/NorthstarDemo/OnboardingFlow.swift",
    "Tests/NorthstarDemoTests/OnboardingFlowTests.swift",
  ])
  let gitHead = manifest.fakeRepository.appendingPathComponent(".git/HEAD")
  #expect(FileManager.default.fileExists(atPath: gitHead.path))

  #expect(try gitOutput(["branch", "--show-current"], repository: manifest.fakeRepository) == "main")
  #expect(try gitOutput(["rev-list", "--count", "HEAD"], repository: manifest.fakeRepository) == "1")
  #expect(
    try gitOutput(["log", "-1", "--format=%s"], repository: manifest.fakeRepository)
      == "chore: seed synthetic Northstar demo"
  )
  #expect(
    try gitOutput(["config", "--local", "--get", "user.name"], repository: manifest.fakeRepository)
      == "Fleck Demo"
  )
  #expect(
    try gitOutput(["config", "--local", "--get", "user.email"], repository: manifest.fakeRepository)
      == "demo@invalid.example"
  )
  #expect(
    try gitOutput(["log", "-1", "--format=%an <%ae>"], repository: manifest.fakeRepository)
      == "Fleck Demo <demo@invalid.example>"
  )
  #expect(try gitOutput(["remote"], repository: manifest.fakeRepository).isEmpty)

  #expect(
    try String(
      contentsOf: manifest.fakeRepository.appendingPathComponent("Package.swift"),
      encoding: .utf8
    )
      == """
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
      """
  )
  #expect(
    try String(
      contentsOf: manifest.fakeRepository.appendingPathComponent("README.md"),
      encoding: .utf8
    )
      == """
      # Northstar Demo

      This repository contains only synthetic website-demo data for Fleck captures.
      """
  )
  #expect(
    try String(
      contentsOf: manifest.fakeRepository
        .appendingPathComponent("Sources/NorthstarDemo/OnboardingFlow.swift"),
      encoding: .utf8
    )
      == """
      public enum PermissionRequestPoint: Equatable, Sendable {
        case firstLaunch
        case afterWelcome
      }

      public struct OnboardingFlow: Sendable {
        public init() {}
        public var permissionRequestPoint: PermissionRequestPoint { .firstLaunch }
        public var welcomeStepCount: Int { 3 }
      }
      """
  )
  #expect(
    try String(
      contentsOf: manifest.fakeRepository
        .appendingPathComponent("Tests/NorthstarDemoTests/OnboardingFlowTests.swift"),
      encoding: .utf8
    )
      == """
      import NorthstarDemo
      import Testing

      @Test func welcomeFlowHasThreeSteps() {
        #expect(OnboardingFlow().welcomeStepCount == 3)
      }
      """
  )
}

@Test func verifiesOpenAndCompletedCanonicalTaskStates() async throws {
  let session = try TemporaryDirectory()
  let manifest = try await WebsiteDemoSession.prepare(
    at: session.url,
    now: Date(timeIntervalSince1970: 1_725_000_000)
  )

  let initialState = try await WebsiteDemoSession.verify(manifestAt: manifest.manifestURL)
  #expect(initialState == .open)

  let store = LocalStore(rootURL: manifest.fleckRoot)
  let snapshot = try await store.loadSnapshot()
  var workspace = snapshot.workspace
  let task = try #require(AgentNoteMutationEngine.tasks(in: workspace.notes[0].body).first)
  let mutation = try AgentNoteMutationEngine.setTaskState(
    task,
    completed: true,
    in: workspace.notes[0].body
  )
  workspace.updateNote(
    id: WebsiteDemoFixture.northstarNoteID,
    body: mutation.body,
    now: Date(timeIntervalSince1970: 1_725_000_001)
  )
  try await store.save(
    workspace: workspace,
    preferences: snapshot.preferences,
    generation: snapshot.generation + 1
  )

  let completedState = try await WebsiteDemoSession.verify(manifestAt: manifest.manifestURL)
  #expect(completedState == .completed)
}

@Test func commandLineRejectsRelativeSessionRoots() async {
  await #expect(throws: WebsiteDemoError.sessionRootMustBeAbsolute) {
    try await FleckCaptureLab.run(
      arguments: ["prepare", "--session-root", "relative-session"],
      now: Date(timeIntervalSince1970: 1)
    )
  }
}
