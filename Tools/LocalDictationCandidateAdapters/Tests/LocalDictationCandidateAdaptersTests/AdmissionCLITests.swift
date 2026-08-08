import Darwin
import Foundation
import Testing
@testable import LocalDictationCandidateProtocol
@testable import LocalDictationCandidateCLI
@testable import LocalDictationCandidateRunner

private func admissionFixture(_ name: String) throws -> Data {
  try Data(contentsOf: admissionFixtureURL(name))
}

private func admissionFixtureURL(_ name: String) -> URL {
  var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
  while url.path != "/" {
    let candidate = url.appendingPathComponent("Tests/Fixtures/\(name)")
    if FileManager.default.fileExists(atPath: candidate.path) {
      return candidate
    }
    url.deleteLastPathComponent()
  }
  return url.appendingPathComponent(name)
}

private func fixtureAdapterURL() -> URL {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/local-dictation-fixture-adapter.sh")
}

private func temporaryDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("fleck-admission-tests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
  return url
}

private func writeManifest(_ object: [String: Any], in directory: URL) throws -> URL {
  let url = directory.appendingPathComponent("manifest.json")
  try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: url)
  return url
}

private actor CLIResultBox {
  private var result: Int32?

  func store(_ result: Int32) {
    self.result = result
  }

  func value() -> Int32? {
    result
  }
}

private func shellLiteral(_ value: String) -> String {
  "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

private func waitForPIDFile(_ pidFile: URL, timeout: Duration) async throws -> Int32 {
  let deadline = ContinuousClock.now + timeout
  while ContinuousClock.now < deadline {
    if let pid = try? Int32(String(contentsOf: pidFile).trimmingCharacters(in: .whitespacesAndNewlines)) {
      return pid
    }
    try await Task.sleep(for: .milliseconds(20))
  }
  throw NSError(domain: "AdmissionCLITests", code: 1)
}

private func launchCLI(
  mode: String,
  eventTimeout: Duration,
  in directory: URL
) async throws -> (Task<Void, Never>, CLIResultBox, Int32) {
  let pidFile = directory.appendingPathComponent("adapter.pid")
  let wrapper = directory.appendingPathComponent("adapter-wrapper.sh")
  let output = directory.appendingPathComponent("report.json")
  let modelRoot = directory.appendingPathComponent("model-root")
  let fixture = fixtureAdapterURL()
  try FileManager.default.createDirectory(at: modelRoot, withIntermediateDirectories: false)
  let wrapperBody = """
  #!/bin/sh
  set -eu
  printf '%s\\n' "$$" > \(shellLiteral(pidFile.path))
  exec /bin/sh \(shellLiteral(fixture.path)) \(shellLiteral(mode))
  """
  try Data(wrapperBody.utf8).write(to: wrapper)
  try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)

  let arguments = [
    "run",
    "--manifest", admissionFixtureURL("local-dictation-admission-v1.json").path,
    "--adapter", wrapper.path,
    "--model-root", modelRoot.path,
    "--output", output.path,
  ]
  let box = CLIResultBox()
  let task = Task.detached(priority: .userInitiated) {
    let result = await LocalDictationCandidateCLI.run(arguments, eventTimeout: eventTimeout)
    await box.store(result)
  }
  do {
    let pid = try await waitForPIDFile(pidFile, timeout: .seconds(10))
    return (task, box, pid)
  } catch {
    _ = await task.value
    throw error
  }
}

private func waitForCLI(
  _ task: Task<Void, Never>,
  box: CLIResultBox,
  pid: Int32,
  timeout: Duration
) async throws -> Bool {
  let deadline = ContinuousClock.now + timeout
  while ContinuousClock.now < deadline {
    if await box.value() != nil {
      _ = await task.value
      return true
    }
    try await Task.sleep(for: .milliseconds(20))
  }
  if kill(pid, 0) == 0 {
    kill(pid, SIGKILL)
  }
  _ = await task.value
  return false
}

@Suite("AdmissionCLITests")
struct AdmissionCLITests {

  @Test func targetFailureEventStopsAdmissionWait() async throws {
    let process = AdapterProcess()
    let stream = await process.events()
    try await process.start(
      executableURL: fixtureAdapterURL(),
      arguments: ["failure"],
      environment: ["PATH": "/usr/bin:/bin"]
    )
    try await process.send(
      CandidateAdapterRequest(
        schemaVersion: 1,
        requestID: "load-1",
        operation: .load,
        audioPath: nil,
        sampleRate: nil,
        localeIdentifier: nil,
        contextPhrases: [],
        transcript: nil,
        protectedForms: [],
        cleanupMode: nil
      )
    )
    let ready = try await nextEvent(
      stream,
      requestID: "load-1",
      timeout: .seconds(2),
      matching: { $0.kind == .ready }
    )
    #expect(ready.event.kind == .ready)
    try await process.send(
      CandidateAdapterRequest(
        schemaVersion: 1,
        requestID: "transcribe-1",
        operation: .transcribe,
        audioPath: "/fixtures/mixed.wav",
        sampleRate: 16_000,
        localeIdentifier: "auto",
        contextPhrases: [],
        transcript: nil,
        protectedForms: [],
        cleanupMode: nil
      )
    )
    var reason: CLIError?
    do {
      _ = try await nextEvent(
        stream,
        requestID: "transcribe-1",
        timeout: .seconds(2),
        matching: { $0.kind == .final }
      )
    } catch let error as CLIError {
      reason = error
    }
    #expect(reason == .lifecycle("adapter-failure"))
    await process.terminate()
    #expect(!(await process.diagnostics()).childIsRunning)
  }

  @Test func silentEventWaitHasBoundedDeadline() async throws {
    let process = AdapterProcess()
    let stream = await process.events()
    try await process.start(
      executableURL: fixtureAdapterURL(),
      arguments: ["silent"],
      environment: ["PATH": "/usr/bin:/bin"]
    )
    try await process.send(
      CandidateAdapterRequest(
        schemaVersion: 1,
        requestID: "load-1",
        operation: .load,
        audioPath: nil,
        sampleRate: nil,
        localeIdentifier: nil,
        contextPhrases: [],
        transcript: nil,
        protectedForms: [],
        cleanupMode: nil
      )
    )
    _ = try await nextEvent(
      stream,
      requestID: "load-1",
      timeout: .seconds(2),
      matching: { $0.kind == .ready }
    )
    try await process.send(
      CandidateAdapterRequest(
        schemaVersion: 1,
        requestID: "transcribe-1",
        operation: .transcribe,
        audioPath: "/fixtures/mixed.wav",
        sampleRate: 16_000,
        localeIdentifier: "auto",
        contextPhrases: [],
        transcript: nil,
        protectedForms: [],
        cleanupMode: nil
      )
    )
    var reason: CLIError?
    do {
      _ = try await nextEvent(
        stream,
        requestID: "transcribe-1",
        timeout: .seconds(1),
        matching: { $0.kind == .final }
      )
    } catch let error as CLIError {
      reason = error
    }
    #expect(reason == .lifecycle("event-timeout"))
    await process.terminate()
    #expect(!(await process.diagnostics()).childIsRunning)
  }

  @Test func runnerTimeoutCleansUpExactChild() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let (task, box, pid) = try await launchCLI(
      mode: "silent",
      eventTimeout: .seconds(5),
      in: directory
    )
    let completed = try await waitForCLI(task, box: box, pid: pid, timeout: .seconds(7))
    #expect(completed)
    #expect(await box.value() == 2)
    #expect(kill(pid, 0) != 0)
  }

  @Test func acceptsExactlyTenImmutableAdmissionCases() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let result = await LocalDictationCandidateCLI.run([
      "validate-admission",
      "--manifest", admissionFixtureURL("local-dictation-admission-v1.json").path,
      "--schema", admissionFixtureURL("local-dictation-admission-v1.schema.json").path,
    ])
    #expect(result == 0)
  }

  @Test func missingSchemaAndUnsupportedVersionFailClosed() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let manifest = try #require(
      JSONSerialization.jsonObject(with: admissionFixture("local-dictation-admission-v1.json")) as? [String: Any]
    )
    let changed = manifest.merging(["schemaVersion": 2]) { _, new in new }
    let changedURL = try writeManifest(changed, in: directory)
    #expect(await LocalDictationCandidateCLI.run([
      "validate-admission", "--manifest", changedURL.path,
      "--schema", admissionFixtureURL("local-dictation-admission-v1.schema.json").path,
    ]) == 2)
    #expect(await LocalDictationCandidateCLI.run([
      "validate-admission", "--manifest", admissionFixtureURL("local-dictation-admission-v1.json").path,
      "--schema", directory.appendingPathComponent("missing.schema.json").path,
    ]) == 2)
  }

  @Test func duplicateCaseIDAndWrongAudioHashFailClosed() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    var manifest = try #require(
      JSONSerialization.jsonObject(with: admissionFixture("local-dictation-admission-v1.json")) as? [String: Any]
    )
    var cases = try #require(manifest["cases"] as? [[String: Any]])
    cases[1]["id"] = cases[0]["id"]
    manifest["cases"] = cases
    let duplicateURL = try writeManifest(manifest, in: directory)
    #expect(await LocalDictationCandidateCLI.run([
      "validate-admission", "--manifest", duplicateURL.path,
      "--schema", admissionFixtureURL("local-dictation-admission-v1.schema.json").path,
    ]) == 2)

    manifest = try #require(
      JSONSerialization.jsonObject(with: admissionFixture("local-dictation-admission-v1.json")) as? [String: Any]
    )
    cases = try #require(manifest["cases"] as? [[String: Any]])
    let audioURL = directory.appendingPathComponent("case.wav")
    try Data("admitted-audio".utf8).write(to: audioURL)
    cases[0]["audioPath"] = audioURL.path
    cases[0]["audioSHA256"] = String(repeating: "0", count: 64)
    manifest["cases"] = cases
    let wrongHashURL = try writeManifest(manifest, in: directory)
    #expect(await LocalDictationCandidateCLI.run([
      "validate-admission", "--manifest", wrongHashURL.path,
      "--schema", admissionFixtureURL("local-dictation-admission-v1.schema.json").path,
    ]) == 2)
  }

  @Test func runRejectsRelativeAdapterSymlinkEscapeAndExistingOutput() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let manifest = admissionFixtureURL("local-dictation-admission-v1.json").path
    let schema = admissionFixtureURL("local-dictation-admission-v1.schema.json").path
    let modelRoot = directory.appendingPathComponent("model-root")
    let outside = directory.appendingPathComponent("outside")
    try FileManager.default.createDirectory(at: modelRoot, withIntermediateDirectories: false)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
    try FileManager.default.createSymbolicLink(
      at: modelRoot.appendingPathComponent("escape"),
      withDestinationURL: outside
    )
    let output = directory.appendingPathComponent("existing.json")
    try Data("existing".utf8).write(to: output)
    #expect(await LocalDictationCandidateCLI.run([
      "run", "--manifest", manifest, "--adapter", "relative-adapter",
      "--model-root", modelRoot.path, "--output", directory.appendingPathComponent("new.json").path,
    ]) == 2)
    #expect(await LocalDictationCandidateCLI.run([
      "run", "--manifest", manifest, "--adapter", "/bin/sh",
      "--model-root", modelRoot.path, "--output", directory.appendingPathComponent("new.json").path,
    ]) == 2)
    try FileManager.default.removeItem(at: modelRoot.appendingPathComponent("escape"))
    #expect(await LocalDictationCandidateCLI.run([
      "run", "--manifest", manifest, "--adapter", "/bin/sh",
      "--model-root", modelRoot.path, "--output", output.path,
    ]) == 2)
    _ = schema
  }
}
