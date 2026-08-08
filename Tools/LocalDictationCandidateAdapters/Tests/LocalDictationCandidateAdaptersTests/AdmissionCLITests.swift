import Foundation
import Testing
@testable import LocalDictationCandidateCLI

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

@Suite("AdmissionCLITests")
struct AdmissionCLITests {

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
