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

@Test func generatesOnlyTheSyntheticRepositoryFiles() async throws {
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
