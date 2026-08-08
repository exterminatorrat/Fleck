import Foundation
import Testing
@testable import LocalDictationEvaluation

private func strictSchemaFixture(_ name: String) throws -> Data {
  var url = URL(fileURLWithPath: #filePath)
  for _ in 0..<8 {
    let candidate = url
      .deletingLastPathComponent()
      .appendingPathComponent("Tests/Fixtures/\(name)")
    if FileManager.default.fileExists(atPath: candidate.path) {
      return try Data(contentsOf: candidate)
    }
    url.deleteLastPathComponent()
  }
  Issue.record("Missing fixture \(name)")
  return Data()
}

private func strictSchemaObjectFixture(_ name: String) throws -> [String: Any] {
  try #require(
    JSONSerialization.jsonObject(with: strictSchemaFixture(name)) as? [String: Any]
  )
}

@Suite("StrictJSONSchemaTests")
struct StrictJSONSchemaTests {

  @Test func rejectsUnknownTopLevelCorpusKey() throws {
    var changed = try strictSchemaObjectFixture("local-dictation-evaluation-v1.json")
    changed["unexpected"] = true
    let issues = try StrictJSONSchema.unknownKeyIssues(
      instanceData: JSONSerialization.data(withJSONObject: changed),
      schemaData: strictSchemaFixture("local-dictation-evaluation-v1.schema.json")
    )
    #expect(issues == [StrictJSONIssue(path: "/unexpected", key: "unexpected")])
  }

  @Test func rejectsUnknownNestedRunKeyThroughRefAndArray() throws {
    var run = try strictSchemaObjectFixture("local-dictation-run-sample-v1.json")
    var results = try #require(run["results"] as? [[String: Any]])
    var first = results[0]
    var latency = try #require(first["latency"] as? [String: Any])
    latency["mysteryMilliseconds"] = 1
    first["latency"] = latency
    results[0] = first
    run["results"] = results
    let issues = try StrictJSONSchema.unknownKeyIssues(
      instanceData: JSONSerialization.data(withJSONObject: run),
      schemaData: strictSchemaFixture("local-dictation-run-v1.schema.json")
    )
    #expect(issues == [
      StrictJSONIssue(
        path: "/results/0/latency/mysteryMilliseconds",
        key: "mysteryMilliseconds"
      )
    ])
  }

  @Test func escapesUnknownKeysAsJSONPointerSegmentsAndSortsIssues() throws {
    var changed = try strictSchemaObjectFixture("local-dictation-evaluation-v1.json")
    changed["z/key~"] = true
    changed["a/key~"] = true
    let issues = try StrictJSONSchema.unknownKeyIssues(
      instanceData: JSONSerialization.data(withJSONObject: changed),
      schemaData: strictSchemaFixture("local-dictation-evaluation-v1.schema.json")
    )
    #expect(issues == [
      StrictJSONIssue(path: "/a~1key~0", key: "a/key~"),
      StrictJSONIssue(path: "/z~1key~0", key: "z/key~")
    ])
  }

  @Test func rejectsMalformedOrUnsupportedSchemaInsteadOfAcceptingInput() throws {
    let instance = try strictSchemaFixture("local-dictation-evaluation-v1.json")
    let malformedSchema = Data(#"{"type":"object","properties":[]}"#.utf8)
    do {
      _ = try StrictJSONSchema.unknownKeyIssues(
        instanceData: instance,
        schemaData: malformedSchema
      )
      Issue.record("Malformed schema unexpectedly passed")
    } catch let error as StrictJSONSchemaError {
      #expect(error == .invalidSchema)
    }

    let unsupportedReference = Data(
      #"{"type":"object","additionalProperties":false,"properties":{"value":{"$ref":"other.json"}}}"#.utf8
    )
    do {
      _ = try StrictJSONSchema.unknownKeyIssues(
        instanceData: Data(#"{"value":{}}"#.utf8),
        schemaData: unsupportedReference
      )
      Issue.record("Unsupported reference unexpectedly passed")
    } catch let error as StrictJSONSchemaError {
      #expect(error == .invalidSchema)
    }
  }
}
