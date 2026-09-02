import CryptoKit
import Foundation
import FleckCore

protocol TranscriptCleaning: Sendable {
  func clean(_ rawTranscript: String) async throws -> String
}

protocol DestinationRouting: Sendable {
  func route(
    transcript: String,
    candidates: [DictationDestination],
    inboxID: UUID?
  ) async -> UUID?
}

@main
struct ScoreQwenCleanupQualification {
  private enum ScoreError: Error, CustomStringConvertible {
    case usage
    case invalid(String)
    case controlUnavailable

    var description: String {
      switch self {
      case .usage:
        return "usage: score_qwen_cleanup_qualification --corpus PATH --warm PATH --cold-manifest PATH --cancellation PATH"
      case .invalid(let message): return message
      case .controlUnavailable: return "deterministic cleanup control unavailable"
      }
    }
  }

  private enum ControlError: Error {
    case unavailable
  }

  private struct ProtectedExpectation {
    let kind: String
    let text: String
    let comparison: String
  }

  private struct CaseSpec {
    let id: String
    let language: String
    let sourceClass: String
    let rawBaseline: String
    let protectedForms: [String]
    let protectedExpectations: [ProtectedExpectation]
    let sourceEvidence: [String: Any]
    let expectedChange: Bool
    let engine: String
  }

  private struct EvidenceRecord {
    let object: [String: Any]
    let caseID: String
    let caseAccepted: Bool
    let envelopeAccepted: Bool
    let validatorDecision: String
    let validatorReason: String
    let candidateText: String?
    let generation: [String: Any]
    let provenance: [String: Any]
    let maxRSSBytes: Int

    func provenanceEqual(_ other: [String: Any]) -> Bool {
      guard let lhs = try? JSONSerialization.data(withJSONObject: provenance, options: [.sortedKeys]),
            let rhs = try? JSONSerialization.data(withJSONObject: other, options: [.sortedKeys]) else {
        return false
      }
      return lhs == rhs
    }
  }

  private struct ColdRun {
    let object: [String: Any]
    let caseID: String
    let status: String
    let processToResultMilliseconds: Double?
    let evidencePath: String?
    let evidenceSHA256: String?
  }

  private struct GroupStats {
    var total = 0
    var accepted = 0
    var protectedViolations = 0
    var rejectionReasons: [String: Int] = [:]

    mutating func add(reason: String, isAccepted: Bool, protectedViolation: Bool) {
      total += 1
      if isAccepted { accepted += 1 }
      if protectedViolation { protectedViolations += 1 }
      if !isAccepted {
        rejectionReasons[reason, default: 0] += 1
      }
    }
  }

  private static func main() async {
    do {
      let paths = try parseArguments(Array(CommandLine.arguments.dropFirst()))
      let corpus = try readCorpus(at: paths.corpus)
      let warm = try readEvidence(at: paths.warm)
      let cold = try readColdManifest(at: paths.coldManifest)
      let cancellation = try readJSONObject(at: paths.cancellation)
      let report = try await score(
        corpus: corpus,
        warm: warm,
        cold: cold,
        cancellation: cancellation,
        warmPath: paths.warm
      )
      let data = try JSONSerialization.data(
        withJSONObject: report,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      )
      guard let text = String(data: data, encoding: .utf8) else {
        throw ScoreError.invalid("score report is not UTF-8")
      }
      print(text)
    } catch {
      fputs("qwen-cleanup-qualification-score-error: \(error)\n", stderr)
      Foundation.exit(2)
    }
  }

  private struct Paths {
    let corpus: String
    let warm: String
    let coldManifest: String
    let cancellation: String
  }

  private static func parseArguments(_ arguments: [String]) throws -> Paths {
    var values: [String: String] = [:]
    var index = 0
    while index < arguments.count {
      guard index + 1 < arguments.count else { throw ScoreError.usage }
      let key = arguments[index]
      guard key == "--corpus" || key == "--warm" || key == "--cold-manifest" || key == "--cancellation" else {
        throw ScoreError.usage
      }
      values[key] = arguments[index + 1]
      index += 2
    }
    guard let corpus = values["--corpus"],
          let warm = values["--warm"],
          let coldManifest = values["--cold-manifest"],
          let cancellation = values["--cancellation"] else {
      throw ScoreError.usage
    }
    return Paths(corpus: corpus, warm: warm, coldManifest: coldManifest, cancellation: cancellation)
  }

  private static func score(
    corpus: [CaseSpec],
    warm: [EvidenceRecord],
    cold: [ColdRun],
    cancellation: [String: Any],
    warmPath: String
  ) async throws -> [String: Any] {
    let casesByID = Dictionary(uniqueKeysWithValues: corpus.map { ($0.id, $0) })
    guard warm.count == corpus.count else {
      throw ScoreError.invalid("warm evidence count does not match corpus")
    }
    guard Set(warm.map(\.caseID)) == Set(corpus.map(\.id)) else {
      throw ScoreError.invalid("warm evidence case identities do not match corpus")
    }

    let deterministic = FoundationModelDictation(
      osMajorVersion: { 25 },
      cleanupGenerator: { _, _ in throw ControlError.unavailable },
      routingGenerator: { _, _ in .inbox }
    )
    let validator = FaithfulCleanupValidator()
    var caseResults: [[String: Any]] = []
    var groups: [String: GroupStats] = [:]
    var warmGenerationMilliseconds: [Double] = []
    var warmRSSValues: [Int] = []
    var protectedViolationCount = 0
    var unexpectedLexicalChangeCount = 0
    var qwenAcceptedCount = 0
    var qwenRejectionReasons: [String: Int] = [:]
    var deterministicAcceptedCount = 0
    var deterministicChangedCount = 0
    var deterministicExpectationMismatches: [[String: Any]] = []
    var deterministicProtectedViolations: [[String: Any]] = []
    var deterministicRejectionReasons: [String: Int] = [:]

    for record in warm {
      guard let specification = casesByID[record.caseID] else {
        throw ScoreError.invalid("warm evidence has unknown case \(record.caseID)")
      }
      guard let generationMilliseconds = number(record.generation["generationElapsedMs"]) else {
        throw ScoreError.invalid("warm evidence is missing generation timing for \(record.caseID)")
      }
      warmGenerationMilliseconds.append(generationMilliseconds)
      warmRSSValues.append(record.maxRSSBytes)

      let qwenViolations = protectedViolations(
        specification: specification,
        candidate: record.candidateText
      )
      let qwenAccepted = record.caseAccepted && qwenViolations.isEmpty
      if qwenAccepted { qwenAcceptedCount += 1 }
      protectedViolationCount += qwenViolations.count
      if !qwenAccepted {
        let reason = qwenViolations.isEmpty
          ? record.validatorReason
          : "protectedViolation"
        qwenRejectionReasons[reason, default: 0] += 1
      }
      if !record.caseAccepted,
         [
           "lexicalInsertion",
           "lexicalDeletion",
           "lexicalSubstitution",
           "reorderedContent",
           "ambiguousCorrection",
           "numberMeaningChanged",
         ].contains(record.validatorReason) {
        unexpectedLexicalChangeCount += 1
      }

      let controlResult = await deterministic.cleanupResult(specification.rawBaseline)
      let controlText = controlResult.text
      let controlChanged = controlText != specification.rawBaseline
      if controlChanged { deterministicChangedCount += 1 }
      let controlDecision = validator.validate(
        candidate: controlText,
        against: .init(
          baseline: specification.rawBaseline,
          protectedForms: specification.protectedForms,
          replacements: 0
        )
      )
      let controlAccepted: Bool
      let controlReason: String
      switch controlDecision {
      case .accepted:
        controlAccepted = true
        controlReason = "accepted"
        deterministicAcceptedCount += 1
      case .rejected(let failure):
        controlAccepted = false
        controlReason = failureName(failure)
        deterministicRejectionReasons[controlReason, default: 0] += 1
      }
      let controlViolations = protectedViolations(
        specification: specification,
        candidate: controlText
      )
      if !controlViolations.isEmpty {
        deterministicProtectedViolations.append([
          "caseID": specification.id,
          "violations": controlViolations,
        ])
      }
      if controlChanged != specification.expectedChange {
        deterministicExpectationMismatches.append([
          "caseID": specification.id,
          "expectedChange": specification.expectedChange,
          "actualChange": controlChanged,
          "text": controlText,
        ])
      }

      let engine = specification.engine
      let groupKey = "\(specification.language)/\(engine)/\(specification.sourceClass)"
      groups[groupKey, default: GroupStats()].add(
        reason: qwenViolations.isEmpty ? record.validatorReason : "protectedViolation",
        isAccepted: qwenAccepted,
        protectedViolation: !qwenViolations.isEmpty
      )

      var result: [String: Any] = [
        "caseID": specification.id,
        "language": specification.language,
        "sourceClass": specification.sourceClass,
        "engine": engine,
        "rawBaseline": specification.rawBaseline,
        "qwen": [
          "caseAccepted": record.caseAccepted,
          "envelopeAccepted": record.envelopeAccepted,
          "validatorDecision": record.validatorDecision,
          "validatorReason": record.validatorReason,
          "candidateText": record.candidateText ?? NSNull(),
          "acceptedAfterProtectedChecks": qwenAccepted,
          "protectedViolations": qwenViolations,
        ],
        "deterministicControl": [
          "text": controlText,
          "changed": controlChanged,
          "expectedChange": specification.expectedChange,
          "accepted": controlAccepted,
          "validatorReason": controlReason,
          "protectedViolations": controlViolations,
        ],
      ]
      if result["qwen"] == nil { result["qwen"] = NSNull() }
      caseResults.append(result)
    }

    let coldSuccesses = cold.filter { $0.status == "success" }
    let coldTimings = coldSuccesses.compactMap(\.processToResultMilliseconds)
    let coldRSSValues = try coldSuccesses.compactMap { run -> Int? in
      guard let path = run.evidencePath else { return nil }
      let records = try readEvidence(at: path)
      guard records.count == 1 else {
        throw ScoreError.invalid("cold evidence is not a single-case file: \(path)")
      }
      return records[0].maxRSSBytes
    }
    let evidencePaths = [warmPath] + cold.compactMap(\.evidencePath)
    let evidenceFiles = try evidencePaths.map(fileIdentity)
    let provenance = warm.first?.provenance ?? [:]
    let provenanceConsistent = warm.dropFirst().allSatisfy { $0.provenanceEqual(provenance) }

    let automatedCandidatePass = qwenAcceptedCount == corpus.count
      && protectedViolationCount == 0
      && unexpectedLexicalChangeCount == 0
      && bool(cancellation["noLatePublication"]) == true
    let deterministicPass = deterministicExpectationMismatches.isEmpty
      && deterministicProtectedViolations.isEmpty
      && deterministicAcceptedCount == corpus.count

    let report: [String: Any] = [
      "schemaVersion": 1,
      "claimScope": "developer-only-external-qwen-cleanup-qualification",
      "qualification": [
        "corpusID": "fleck-qwen-cleanup-qualification-corpus-v1",
        "corpusCaseCount": corpus.count,
        "asrCaseCount": corpus.filter { $0.sourceClass != "protectedStress" }.count,
        "protectedStressCaseCount": corpus.filter { $0.sourceClass == "protectedStress" }.count,
        "sourceEvidencePinned": true,
        "noMicrophoneAudioCopied": true,
      ],
      "candidate": [
        "acceptedCaseCount": qwenAcceptedCount,
        "rejectedCaseCount": corpus.count - qwenAcceptedCount,
        "protectedViolationCount": protectedViolationCount,
        "unexpectedLexicalChangeCount": unexpectedLexicalChangeCount,
        "rejectionReasons": qwenRejectionReasons,
        "automatedCandidatePass": automatedCandidatePass,
      ],
      "deterministicControl": [
        "acceptedCaseCount": deterministicAcceptedCount,
        "changedCaseCount": deterministicChangedCount,
        "expectedChangeMismatchCount": deterministicExpectationMismatches.count,
        "expectationMismatches": deterministicExpectationMismatches,
        "protectedViolationCount": deterministicProtectedViolations.count,
        "protectedViolations": deterministicProtectedViolations,
        "rejectionReasons": deterministicRejectionReasons,
        "pass": deterministicPass,
        "implementation": "compiled checked-in FoundationModelDictation.localCleanup with osMajorVersion=25",
      ],
      "acceptanceByLanguageAndSource": groupsJSON(groups),
      "timing": [
        "warmGenerationMilliseconds": timingJSON(warmGenerationMilliseconds),
        "coldProcessToResultMilliseconds": timingJSON(coldTimings),
        "warmCaseCount": warmGenerationMilliseconds.count,
        "coldRunCount": cold.count,
        "coldSuccessfulRunCount": coldSuccesses.count,
        "maxRssBytes": (warmRSSValues + coldRSSValues).max() ?? 0,
      ],
      "cancellation": cancellation,
      "evidenceFiles": evidenceFiles,
      "provenance": provenance,
      "provenanceConsistent": provenanceConsistent,
      "modelRuntime": [
        "artifact": warm.first?.object["artifact"] ?? NSNull(),
        "runtime": warm.first?.object["runtime"] ?? NSNull(),
        "offline": warm.first?.object["offline"] ?? NSNull(),
      ],
      "truthFlags": [
        "productionIntegrated": false,
        "packagedAppVerified": false,
        "releaseAdmitted": false,
      ],
      "caseResults": caseResults,
    ]
    return report
  }

  private static func readCorpus(at path: String) throws -> [CaseSpec] {
    let object = try readJSONObject(at: path)
    guard int(object["schemaVersion"]) == 1 else {
      throw ScoreError.invalid("unsupported corpus schema")
    }
    guard let values = object["cases"] as? [[String: Any]], !values.isEmpty else {
      throw ScoreError.invalid("corpus cases are missing")
    }
    return try values.map { value in
      guard let id = value["id"] as? String,
            let language = value["language"] as? String,
            let sourceClass = value["sourceClass"] as? String,
            let rawBaseline = value["rawBaseline"] as? String,
            let protectedForms = value["protectedForms"] as? [String],
            let rawExpectations = value["protectedExpectations"] as? [[String: Any]],
            let sourceEvidence = value["sourceEvidence"] as? [String: Any],
            let expectedChange = value["deterministicCleanupExpectedToChange"] as? Bool else {
        throw ScoreError.invalid("malformed corpus case")
      }
      let expectations = try rawExpectations.map { expectation -> ProtectedExpectation in
        guard let kind = expectation["kind"] as? String,
              let text = expectation["text"] as? String,
              let comparison = expectation["comparison"] as? String else {
          throw ScoreError.invalid("malformed protected expectation for \(id)")
        }
        return ProtectedExpectation(kind: kind, text: text, comparison: comparison)
      }
      let engine = sourceEvidence["engine"] as? String ?? "none"
      return CaseSpec(
        id: id,
        language: language,
        sourceClass: sourceClass,
        rawBaseline: rawBaseline,
        protectedForms: protectedForms,
        protectedExpectations: expectations,
        sourceEvidence: sourceEvidence,
        expectedChange: expectedChange,
        engine: engine
      )
    }
  }

  private static func readEvidence(at path: String) throws -> [EvidenceRecord] {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    var records: [EvidenceRecord] = []
    for line in data.split(whereSeparator: { $0 == 0x0A || $0 == 0x0D }) where !line.isEmpty {
      guard let object = try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
            let caseID = object["caseID"] as? String,
            let caseAccepted = object["caseAccepted"] as? Bool,
            let envelopeAccepted = object["envelopeAccepted"] as? Bool,
            let validatorDecision = object["validatorDecision"] as? String,
            let validatorReason = object["validatorReason"] as? String,
            let generation = object["generation"] as? [String: Any],
            let provenance = object["provenance"] as? [String: Any],
            let maxRSSBytes = int(object["generation"].flatMap { ($0 as? [String: Any])?["maxRssBytes"] }) else {
        throw ScoreError.invalid("malformed accepted-harness evidence record")
      }
      records.append(EvidenceRecord(
        object: object,
        caseID: caseID,
        caseAccepted: caseAccepted,
        envelopeAccepted: envelopeAccepted,
        validatorDecision: validatorDecision,
        validatorReason: validatorReason,
        candidateText: object["candidateText"] as? String,
        generation: generation,
        provenance: provenance,
        maxRSSBytes: maxRSSBytes
      ))
    }
    return records
  }

  private static func readColdManifest(at path: String) throws -> [ColdRun] {
    let object = try JSONSerialization.jsonObject(
      with: Data(contentsOf: URL(fileURLWithPath: path))
    )
    guard let values = object as? [[String: Any]] else {
      throw ScoreError.invalid("cold manifest must be an array")
    }
    return try values.map { value in
      guard let caseID = value["caseID"] as? String,
            let status = value["status"] as? String else {
        throw ScoreError.invalid("malformed cold manifest record")
      }
      return ColdRun(
        object: value,
        caseID: caseID,
        status: status,
        processToResultMilliseconds: number(value["processToResultMilliseconds"]),
        evidencePath: value["evidencePath"] as? String,
        evidenceSHA256: value["evidenceSHA256"] as? String
      )
    }
  }

  private static func readJSONObject(at path: String) throws -> [String: Any] {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw ScoreError.invalid("expected JSON object at \(path)")
    }
    return object
  }

  private static func protectedViolations(
    specification: CaseSpec,
    candidate: String?
  ) -> [[String: Any]] {
    guard let candidate else { return [] }
    var violations: [[String: Any]] = []
    for form in specification.protectedForms where !candidate.contains(form) {
      violations.append(["kind": "protectedForm", "text": form])
    }
    for expectation in specification.protectedExpectations {
      let preserved: Bool
      switch expectation.comparison {
      case "exactSubstring": preserved = candidate.contains(expectation.text)
      default: preserved = false
      }
      if !preserved {
        violations.append([
          "comparison": expectation.comparison,
          "kind": expectation.kind,
          "text": expectation.text,
        ])
      }
    }
    return violations
  }

  private static func groupsJSON(_ groups: [String: GroupStats]) -> [String: Any] {
    var result: [String: Any] = [:]
    for key in groups.keys.sorted() {
      guard let value = groups[key] else { continue }
      result[key] = [
        "total": value.total,
        "accepted": value.accepted,
        "rejected": value.total - value.accepted,
        "acceptanceRate": value.total == 0 ? 0 : Double(value.accepted) / Double(value.total),
        "protectedViolations": value.protectedViolations,
        "rejectionReasons": value.rejectionReasons,
      ]
    }
    return result
  }

  private static func timingJSON(_ values: [Double]) -> [String: Any] {
    guard !values.isEmpty else {
      return ["count": 0, "p50Milliseconds": NSNull(), "p95Milliseconds": NSNull(), "maxMilliseconds": NSNull()]
    }
    let sorted = values.sorted()
    return [
      "count": values.count,
      "p50Milliseconds": percentile(sorted, fraction: 0.50),
      "p95Milliseconds": percentile(sorted, fraction: 0.95),
      "maxMilliseconds": sorted.last as Any,
    ]
  }

  private static func percentile(_ sorted: [Double], fraction: Double) -> Double {
    let index = max(0, min(sorted.count - 1, Int(ceil(Double(sorted.count) * fraction)) - 1))
    return sorted[index]
  }

  private static func fileIdentity(_ path: String) throws -> [String: Any] {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    return ["path": path, "bytes": data.count, "sha256": digest]
  }

  private static func failureName(_ failure: CleanupValidationFailure) -> String {
    switch failure {
    case .emptyCandidate: return "emptyCandidate"
    case .protectedContentChanged: return "protectedContentChanged"
    case .lexicalInsertion: return "lexicalInsertion"
    case .lexicalDeletion: return "lexicalDeletion"
    case .lexicalSubstitution: return "lexicalSubstitution"
    case .reorderedContent: return "reorderedContent"
    case .ambiguousCorrection: return "ambiguousCorrection"
    case .numberMeaningChanged: return "numberMeaningChanged"
    }
  }

  private static func int(_ value: Any?) -> Int? {
    guard let number = value as? NSNumber, !number.isBoolean else { return nil }
    return number.intValue
  }

  private static func number(_ value: Any?) -> Double? {
    guard let number = value as? NSNumber, !number.isBoolean else { return nil }
    return number.doubleValue
  }

  private static func bool(_ value: Any?) -> Bool? {
    value as? Bool
  }
}

private extension NSNumber {
  var isBoolean: Bool { String(cString: objCType) == "c" }
}
