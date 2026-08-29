import Darwin
import CryptoKit
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

enum RepositoryContamination: CaseIterable {
  case modifiedTrackedFile
  case extraUntrackedFile
  case remote
}

enum PostflightContamination: CaseIterable, Equatable {
  case missingProof
  case wrongActor
  case wrongProfileID
  case wrongRevision
  case extraPath
  case malformedPatch
  case remote
  case wrongBehavior
}

private let approvedAgentInstructions = """
  When asked to pick up where the user left off, inspect the available Fleck tools for the open Northstar Demo handoff. Make the requested change in this synthetic repository, run its tests, and only after they pass update the originating Fleck task to reflect the completed work. Do not use network access or add a git remote.
  """

private let completedOnboardingSource = """
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

private let completedOnboardingTests = """
  import NorthstarDemo
  import Testing

  @Test func welcomeFlowHasThreeSteps() {
    #expect(OnboardingFlow().welcomeStepCount == 3)
  }

  @Test func requestsLocationAfterWelcome() {
    #expect(OnboardingFlow().permissionRequestPoint == .afterWelcome)
  }
  """

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

private func bodySHA256(_ body: String) -> String {
  SHA256.hash(data: Data(body.utf8))
    .map { String(format: "%02x", $0) }
    .joined()
}

private func completeWorkflow(
  in manifest: WebsiteDemoManifest,
  contamination: PostflightContamination? = nil
) async throws {
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
  let northstar = try #require(
    workspace.notes.first(where: { $0.id == WebsiteDemoFixture.northstarNoteID })
  )
  let activeProfileID = UUID(uuidString: "99999999-9999-4999-8999-999999999999")!
  let profilesURL = manifest.fleckRoot
    .appendingPathComponent("AgentIntegrations/profiles.json")
  try FileManager.default.createDirectory(
    at: profilesURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )
  let profilesData = try JSONSerialization.data(
    withJSONObject: [[
      "createdAt": 0,
      "displayName": "Codex",
      "id": activeProfileID.uuidString,
    ]],
    options: [.prettyPrinted, .sortedKeys]
  )
  try profilesData.write(to: profilesURL, options: .atomic)
  let actor: AgentActivityActor =
    contamination == .wrongActor
    ? .integration(
      profileID: activeProfileID,
      displayName: "Codex Demo"
    )
    : .integration(
      profileID: contamination == .wrongProfileID
        ? UUID(uuidString: "66666666-6666-4666-8666-666666666666")!
        : activeProfileID,
      displayName: "Codex"
    )
  let proof = AgentWorkspaceCommitProof(
    changeID: UUID(uuidString: "77777777-7777-4777-8777-777777777777")!,
    noteID: WebsiteDemoFixture.northstarNoteID,
    resultingRevision: contamination == .wrongRevision
      ? northstar.revision + 1
      : northstar.revision,
    bodySHA256: bodySHA256(northstar.body),
    actor: actor,
    operationID: UUID(uuidString: "88888888-8888-4888-8888-888888888888")!,
    expiresAt: Date(timeIntervalSince1970: 4_000_000_000)
  )
  try await store.save(
    workspace: workspace,
    preferences: snapshot.preferences,
    generation: 1,
    commitProof: contamination == .missingProof ? nil : proof
  )

  let sourceURL = manifest.fakeRepository
    .appendingPathComponent("Sources/NorthstarDemo/OnboardingFlow.swift")
  let testURL = manifest.fakeRepository
    .appendingPathComponent("Tests/NorthstarDemoTests/OnboardingFlowTests.swift")
  let source: String
  switch contamination {
  case .malformedPatch:
    source = completedOnboardingSource.replacingOccurrences(
      of: "{ .afterWelcome }",
      with: "{ .afterWelcome }  "
    )
  case .wrongBehavior:
    source = completedOnboardingSource.replacingOccurrences(
      of: "{ .afterWelcome }",
      with: "{ .firstLaunch }\n"
    )
  default:
    source = completedOnboardingSource
  }
  try Data(source.utf8).write(to: sourceURL, options: .atomic)
  try Data(completedOnboardingTests.utf8).write(to: testURL, options: .atomic)

  if contamination == .extraPath {
    try Data("unexpected tracked change\n".utf8).write(
      to: manifest.fakeRepository.appendingPathComponent("README.md"),
      options: .atomic
    )
  }
  if contamination == .remote {
    _ = try gitOutput(
      ["remote", "add", "origin", "https://invalid.example/northstar.git"],
      repository: manifest.fakeRepository
    )
  }
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
  #expect(snapshot.preferences.theme == .dark)
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

@Test func verifierRejectsUnknownManifestFields() async throws {
  let session = try TemporaryDirectory()
  let manifest = try await WebsiteDemoSession.prepare(
    at: session.url,
    now: Date(timeIntervalSince1970: 1_725_000_000)
  )
  var object = try #require(
    JSONSerialization.jsonObject(with: Data(contentsOf: manifest.manifestURL))
      as? [String: Any]
  )
  object["unexpectedField"] = true
  let contaminated = try JSONSerialization.data(
    withJSONObject: object,
    options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
  )
  try contaminated.write(to: manifest.manifestURL, options: .atomic)

  await #expect(throws: WebsiteDemoError.invalidManifest) {
    try await WebsiteDemoSession.verify(manifestAt: manifest.manifestURL)
  }
}

@Test func manifestUsesEnhancedAppAndRejectsLightweightApp() async throws {
  let session = try TemporaryDirectory()
  let manifest = try await WebsiteDemoSession.prepare(
    at: session.url,
    now: Date(timeIntervalSince1970: 1_725_000_000)
  )
  let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let enhancedApp = packageRoot
    .appendingPathComponent(".build/parakeet-test/Fleck.app", isDirectory: true)
  let lightweightApp = packageRoot
    .appendingPathComponent(".build/Fleck.app", isDirectory: true)

  #expect(manifest.fleckApp.standardizedFileURL == enhancedApp.standardizedFileURL)
  #expect(manifest.fleckApp.standardizedFileURL != lightweightApp.standardizedFileURL)

  let lightweightManifest = WebsiteDemoManifest(
    sessionRoot: manifest.sessionRoot,
    fleckRoot: manifest.fleckRoot,
    fakeRepository: manifest.fakeRepository,
    fleckApp: lightweightApp,
    projectNames: manifest.projectNames,
    captureCommands: manifest.captureCommands
  )
  try JSONEncoder().encode(lightweightManifest).write(to: manifest.manifestURL, options: .atomic)

  await #expect(throws: WebsiteDemoError.invalidManifest) {
    try await WebsiteDemoSession.verify(manifestAt: manifest.manifestURL)
  }
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
    "AGENTS.md",
    "Package.swift",
    "README.md",
    "Sources/NorthstarDemo/OnboardingFlow.swift",
    "Tests/NorthstarDemoTests/OnboardingFlowTests.swift",
  ])
  let gitHead = manifest.fakeRepository.appendingPathComponent(".git/HEAD")
  #expect(FileManager.default.fileExists(atPath: gitHead.path))

  #expect(
    try String(
      contentsOf: manifest.fakeRepository.appendingPathComponent("AGENTS.md"),
      encoding: .utf8
    ) == approvedAgentInstructions
  )

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

@Test func verifierRejectsContaminatedNoteBody() async throws {
  let session = try TemporaryDirectory()
  let manifest = try await WebsiteDemoSession.prepare(
    at: session.url,
    now: Date(timeIntervalSince1970: 1_725_000_000)
  )
  let store = LocalStore(rootURL: manifest.fleckRoot)
  let snapshot = try await store.loadSnapshot()
  var workspace = snapshot.workspace
  workspace.updateNote(
    id: WebsiteDemoFixture.northstarNoteID,
    body: workspace.notes[0].body + "\n\nInjected capture data.",
    now: Date(timeIntervalSince1970: 1_725_000_001)
  )
  try await store.save(
    workspace: workspace,
    preferences: snapshot.preferences,
    generation: snapshot.generation + 1
  )

  await #expect(throws: WebsiteDemoError.verificationFailed) {
    try await WebsiteDemoSession.verify(manifestAt: manifest.manifestURL)
  }
}

@Test(arguments: RepositoryContamination.allCases)
func verifierRejectsRepositoryContamination(_ contamination: RepositoryContamination) async throws {
  let session = try TemporaryDirectory()
  let manifest = try await WebsiteDemoSession.prepare(
    at: session.url,
    now: Date(timeIntervalSince1970: 1_725_000_000)
  )

  switch contamination {
  case .modifiedTrackedFile:
    try Data("modified synthetic readme\n".utf8).write(
      to: manifest.fakeRepository.appendingPathComponent("README.md"),
      options: .atomic
    )
  case .extraUntrackedFile:
    try Data("unexpected file\n".utf8).write(
      to: manifest.fakeRepository.appendingPathComponent("EXTRA.md"),
      options: .atomic
    )
  case .remote:
    _ = try gitOutput(
      ["remote", "add", "origin", "https://invalid.example/northstar.git"],
      repository: manifest.fakeRepository
    )
  }

  await #expect(throws: WebsiteDemoError.verificationFailed) {
    try await WebsiteDemoSession.verify(manifestAt: manifest.manifestURL)
  }
}

@Test func verifierToleratesModelRuntimeDirectories() async throws {
  let session = try TemporaryDirectory()
  let manifest = try await WebsiteDemoSession.prepare(
    at: session.url,
    now: Date(timeIntervalSince1970: 1_725_000_000)
  )
  for directory in ["DictationModels", "CleanupModels"] {
    let root = manifest.fleckRoot.appendingPathComponent(directory, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("synthetic runtime marker\n".utf8).write(
      to: root.appendingPathComponent("runtime-marker.txt"),
      options: .atomic
    )
  }

  let state = try await WebsiteDemoSession.verify(manifestAt: manifest.manifestURL)
  #expect(state == .open)
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

@Test func seedVerifierRejectsCompletedSupportedAgentWorkflow() async throws {
  let session = try TemporaryDirectory()
  let manifest = try await WebsiteDemoSession.prepare(
    at: session.url,
    now: Date(timeIntervalSince1970: 1_725_000_000)
  )
  try await completeWorkflow(in: manifest)
  for path in [
    "Sources/NorthstarDemo/OnboardingFlow.swift",
    "Tests/NorthstarDemoTests/OnboardingFlowTests.swift",
  ] {
    let seed = try gitOutput(["show", "HEAD:\(path)"], repository: manifest.fakeRepository)
    try Data(seed.utf8).write(
      to: manifest.fakeRepository.appendingPathComponent(path),
      options: .atomic
    )
  }
  #expect(
    try gitOutput(
      ["status", "--porcelain=v1", "--untracked-files=all"],
      repository: manifest.fakeRepository
    ).isEmpty
  )

  await #expect(throws: WebsiteDemoError.verificationFailed) {
    try await WebsiteDemoSession.verify(manifestAt: manifest.manifestURL)
  }
}

@Test func postflightAcceptsExactCompletedSupportedAgentWorkflow() async throws {
  let session = try TemporaryDirectory()
  let manifest = try await WebsiteDemoSession.prepare(
    at: session.url,
    now: Date(timeIntervalSince1970: 1_725_000_000)
  )
  try await completeWorkflow(in: manifest)

  let state = try await WebsiteDemoSession.postflight(manifestAt: manifest.manifestURL)
  #expect(state == .completed)
}

@Test(arguments: PostflightContamination.allCases)
func postflightRejectsIncompleteOrIncoherentWorkflow(
  _ contamination: PostflightContamination
) async throws {
  let session = try TemporaryDirectory()
  let manifest = try await WebsiteDemoSession.prepare(
    at: session.url,
    now: Date(timeIntervalSince1970: 1_725_000_000)
  )
  try await completeWorkflow(in: manifest, contamination: contamination)

  await #expect(throws: WebsiteDemoError.verificationFailed) {
    try await WebsiteDemoSession.postflight(manifestAt: manifest.manifestURL)
  }
}

@Test func commandLineRejectsRelativeSessionRoots() async {
  await #expect(throws: WebsiteDemoError.sessionRootMustBeAbsolute) {
    try await FleckCaptureLab.run(
      arguments: ["prepare", "--session-root", "relative-session"],
      now: Date(timeIntervalSince1970: 1)
    )
  }
}
