import FleckModelEvaluation
import Foundation
import Testing

@Test func syntheticFixtureRoundTripsAsStrictVersionTwoEvidence() throws {
  let evidence = try decodeFixture()

  #expect(evidence.schemaVersion == 2)
  #expect(evidence.runID == "synthetic-fixture-run")
  #expect(evidence.claimScope == .candidateBenchmark)
  #expect(evidence.evidenceClasses == [.publicHuman, .publicHumanComposite, .synthetic])
  #expect(evidence.cases.count == 5)
  #expect(evidence.artifacts.totalInstalledBytes == 48)
  #expect(evidence.privacy.claimsVerifiedOffline)
  #expect(evidence.aggregate.accuracy.englishWER == 0.0)
  #expect(evidence.aggregate.accuracy.mandarinCER == 0.0)
  #expect(evidence.aggregate.accuracy.mixedMER == 0.0)
  #expect(evidence.aggregate.accuracy.codeSwitchSpanAccuracy == 1.0)
  #expect(evidence.aggregate.accuracy.protectedViolationCount == 0)
  #expect(evidence.aggregate.latency.coldP50Milliseconds == 1.0)
  #expect(evidence.aggregate.latency.coldP95Milliseconds == 2.0)
  #expect(evidence.aggregate.latency.warmP50Milliseconds == 1.5)
  #expect(evidence.aggregate.latency.warmP95Milliseconds == 1.75)
  #expect(evidence.aggregate.fileDecodeRTF == 0.0025)
  #expect(evidence.aggregate.peakResidentBytes == 10240)
  #expect(evidence.aggregate.peakPhysicalFootprintBytes == 11264)
  #expect(evidence.aggregate.totalStorageBytes == 48)
  #expect(evidence.aggregate.lifecycleSummary.allSucceeded)
  #expect(!evidence.gate.automatedCandidatePass)
  #expect(evidence.gate.failureReasons == [
    "synthetic test-only fixture has no real candidate result"
  ])
  #expect(!evidence.gate.releaseAdmitted)
  #expect(evidence.cases.first(where: { $0.id == "composite-mixed" })?.codeSwitchSpans.allSatisfy(\.matched) == true)
  #expect(evidence.lifecycle.load.outcome == .succeeded)
  #expect(evidence.lifecycle.infer.outcome == .succeeded)
  #expect(evidence.lifecycle.unload.outcome == .succeeded)
  #expect(evidence.lifecycle.reload.outcome == .succeeded)

  let roundTripped = try JSONDecoder().decode(
    CandidateBenchmarkEvidence.self,
    from: JSONEncoder().encode(evidence)
  )
  #expect(roundTripped == evidence)
}

@Test func preservesEmptyHypothesesForSilenceAndCancellation() throws {
  let evidence = try decodeFixture()
  let cases = Dictionary(uniqueKeysWithValues: evidence.cases.map { ($0.id, $0) })

  #expect(cases["none-silence"]?.hypothesis == "")
  #expect(cases["none-silence"]?.reference == "")
  #expect(cases["english-cancel"]?.hypothesis == "")
  #expect(cases["english-cancel"]?.cancellation.outcome == .cooperative)
}

@Test func rejectsUnsupportedSchemaAndBlankIdentity() throws {
  try expectEvidenceFailure(mutatedFixture { $0["schemaVersion"] = 1 })
  try expectEvidenceFailure(mutatedFixture { root in
    var candidate = root["candidate"] as! [String: Any]
    candidate["modelID"] = "  "
    root["candidate"] = candidate
  })
  try expectEvidenceFailure(mutatedFixture { root in
    var hardware = root["hardware"] as! [String: Any]
    hardware["chip"] = ""
    root["hardware"] = hardware
  })
}

@Test func rejectsUnsortedDuplicateOrMismatchedEvidenceClasses() throws {
  try expectEvidenceFailure(mutatedFixture { root in
    root["evidenceClasses"] = ["synthetic", "publicHuman", "publicHumanComposite"]
  })
  try expectEvidenceFailure(mutatedFixture { root in
    root["evidenceClasses"] = ["publicHuman", "publicHuman", "synthetic"]
  })
  try expectEvidenceFailure(mutatedFixture { root in
    root["evidenceClasses"] = ["publicHuman", "publicHumanComposite", "operatorLiveHuman", "synthetic"]
  })
}

@Test func rejectsNonCanonicalHashesAndBrokenCorpusBinding() throws {
  try expectEvidenceFailure(mutatedFixture { root in
    mutateCase(&root, id: "public-human") { $0["audioSHA256"] = String(repeating: "A", count: 64) }
  })
  try expectEvidenceFailure(mutatedFixture { root in
    mutateCase(&root, id: "public-human") { $0["audioSHA256"] = String(repeating: "9", count: 64) }
  })
}

@Test func rejectsNegativeOverflowingAndMismatchedSizes() throws {
  try expectEvidenceFailure(mutatedFixture { root in
    mutateCase(&root, id: "public-human") { $0["peakResidentBytes"] = -1 }
  })
  try expectEvidenceFailure(mutatedFixture { root in
    var artifacts = root["artifacts"] as! [String: Any]
    artifacts["totalInstalledBytes"] = 49
    root["artifacts"] = artifacts
  })
  try expectEvidenceFailure(mutatedFixture { root in
    var artifacts = root["artifacts"] as! [String: Any]
    var installedFiles = artifacts["installedFiles"] as! [[String: Any]]
    installedFiles[0]["byteCount"] = Int64.max
    artifacts["installedFiles"] = installedFiles
    root["artifacts"] = artifacts
  })
  try expectEvidenceFailure(mutatedFixture { root in
    var hardware = root["hardware"] as! [String: Any]
    hardware["memoryBytes"] = 9223372036854775808.0
    root["hardware"] = hardware
  })
  try expectEvidenceFailure(mutatedFixture { root in
    mutateCase(&root, id: "public-human") { $0["captureTemperature"] = "NaN" }
  })
}

@Test func requiresOrderedCompositeSpansAndRejectsSpansOnOtherSources() throws {
  try expectEvidenceFailure(mutatedFixture { root in
    mutateCase(&root, id: "composite-mixed") { caseObject in
      var spans = caseObject["codeSwitchSpans"] as! [[String: Any]]
      spans[1]["startMilliseconds"] = 200.0
      caseObject["codeSwitchSpans"] = spans
    }
  })
  try expectEvidenceFailure(mutatedFixture { root in
    mutateCase(&root, id: "composite-mixed") { caseObject in
      caseObject["codeSwitchSpans"] = []
    }
  })
  try expectEvidenceFailure(mutatedFixture { root in
    mutateCase(&root, id: "composite-mixed") { caseObject in
      var spans = caseObject["codeSwitchSpans"] as! [[String: Any]]
      spans[0].removeValue(forKey: "matched")
      caseObject["codeSwitchSpans"] = spans
    }
  })
  try expectEvidenceFailure(mutatedFixture { root in
    mutateCase(&root, id: "composite-mixed") { caseObject in
      caseObject["sourceClass"] = "publicHuman"
    }
    root["evidenceClasses"] = ["publicHuman", "synthetic"]
  })
}

@Test func rejectsNaturalCodeSwitchClaimsForCompositeCases() throws {
  try expectEvidenceFailure(mutatedFixture { root in
    mutateCase(&root, id: "composite-mixed") { $0["claimsNaturalCodeSwitch"] = true }
  })
}

@Test func rejectsOfflineClaimsWithoutEnforcementAndCooperativeLateOutput() throws {
  try expectEvidenceFailure(mutatedFixture { root in
    var privacy = root["privacy"] as! [String: Any]
    privacy["enforced"] = false
    root["privacy"] = privacy
  })
  try expectEvidenceFailure(mutatedFixture { root in
    mutateCase(&root, id: "english-cancel") { caseObject in
      var cancellation = caseObject["cancellation"] as! [String: Any]
      cancellation["noLateOutput"] = false
      caseObject["cancellation"] = cancellation
    }
  })
}

@Test func rejectsMissingBlankOrIncompleteAggregateIdentity() throws {
  try expectEvidenceFailure(mutatedFixture { root in
    root.removeValue(forKey: "runID")
  })
  try expectEvidenceFailure(mutatedFixture { root in
    root["runID"] = "  "
  })
  try expectEvidenceFailure(mutatedFixture { root in
    root.removeValue(forKey: "aggregate")
  })
  try expectEvidenceFailure(mutatedFixture { root in
    root.removeValue(forKey: "gate")
  })
}

@Test func rejectsMalformedAggregateValues() throws {
  try expectEvidenceFailure(mutatedFixture { root in
    var aggregate = root["aggregate"] as! [String: Any]
    var accuracy = aggregate["accuracy"] as! [String: Any]
    accuracy["englishWER"] = -0.1
    aggregate["accuracy"] = accuracy
    root["aggregate"] = aggregate
  })
  try expectEvidenceFailure(mutatedFixture { root in
    var aggregate = root["aggregate"] as! [String: Any]
    var latency = aggregate["latency"] as! [String: Any]
    latency["coldP50Milliseconds"] = -1.0
    aggregate["latency"] = latency
    root["aggregate"] = aggregate
  })
  try expectEvidenceFailure(mutatedFixture { root in
    var aggregate = root["aggregate"] as! [String: Any]
    aggregate["fileDecodeRTF"] = "NaN"
    root["aggregate"] = aggregate
  })
  try expectEvidenceFailure(try fixtureReplacing(
    "\"fileDecodeRTF\": 0.0025",
    with: "\"fileDecodeRTF\": 1e999"
  ))
  try expectEvidenceFailure(mutatedFixture { root in
    var aggregate = root["aggregate"] as! [String: Any]
    aggregate["peakResidentBytes"] = -1
    root["aggregate"] = aggregate
  })
  try expectEvidenceFailure(mutatedFixture { root in
    var aggregate = root["aggregate"] as! [String: Any]
    aggregate["totalStorageBytes"] = 49
    root["aggregate"] = aggregate
  })
  try expectEvidenceFailure(mutatedFixture { root in
    var aggregate = root["aggregate"] as! [String: Any]
    var latency = aggregate["latency"] as! [String: Any]
    latency["coldP95Milliseconds"] = 90.0
    aggregate["latency"] = latency
    root["aggregate"] = aggregate
  })
}

@Test func rejectsDerivedLatencyMemoryAndStorageMismatches() throws {
  try expectEvidenceFailure(mutatedFixture { root in
    var aggregate = root["aggregate"] as! [String: Any]
    var latency = aggregate["latency"] as! [String: Any]
    latency["coldP50Milliseconds"] = 1.5
    aggregate["latency"] = latency
    root["aggregate"] = aggregate
  })
  try expectEvidenceFailure(mutatedFixture { root in
    var aggregate = root["aggregate"] as! [String: Any]
    aggregate["fileDecodeRTF"] = 0.1
    root["aggregate"] = aggregate
  })
  try expectEvidenceFailure(mutatedFixture { root in
    var aggregate = root["aggregate"] as! [String: Any]
    aggregate["peakResidentBytes"] = 8192
    root["aggregate"] = aggregate
  })
  try expectEvidenceFailure(mutatedFixture { root in
    var aggregate = root["aggregate"] as! [String: Any]
    aggregate["peakPhysicalFootprintBytes"] = 9216
    root["aggregate"] = aggregate
  })
  try expectEvidenceFailure(mutatedFixture { root in
    var aggregate = root["aggregate"] as! [String: Any]
    aggregate["totalStorageBytes"] = 47
    root["aggregate"] = aggregate
  })
}

@Test func rejectsAggregatesThatDisagreeWithDetailedCases() throws {
  try expectEvidenceFailure(mutatedFixture { root in
    var aggregate = root["aggregate"] as! [String: Any]
    var accuracy = aggregate["accuracy"] as! [String: Any]
    accuracy["englishWER"] = 0.5
    aggregate["accuracy"] = accuracy
    root["aggregate"] = aggregate
  })
  try expectEvidenceFailure(mutatedFixture { root in
    var aggregate = root["aggregate"] as! [String: Any]
    var accuracy = aggregate["accuracy"] as! [String: Any]
    accuracy["mandarinCER"] = 0.5
    aggregate["accuracy"] = accuracy
    root["aggregate"] = aggregate
  })
  try expectEvidenceFailure(mutatedFixture { root in
    var aggregate = root["aggregate"] as! [String: Any]
    var accuracy = aggregate["accuracy"] as! [String: Any]
    accuracy["mixedMER"] = 0.5
    aggregate["accuracy"] = accuracy
    root["aggregate"] = aggregate
  })
  try expectEvidenceFailure(mutatedFixture { root in
    var aggregate = root["aggregate"] as! [String: Any]
    var accuracy = aggregate["accuracy"] as! [String: Any]
    accuracy["protectedViolationCount"] = 1
    aggregate["accuracy"] = accuracy
    root["aggregate"] = aggregate
  })
  try expectEvidenceFailure(mutatedFixture { root in
    var aggregate = root["aggregate"] as! [String: Any]
    var accuracy = aggregate["accuracy"] as! [String: Any]
    accuracy["codeSwitchSpanAccuracy"] = 0.5
    aggregate["accuracy"] = accuracy
    root["aggregate"] = aggregate
  })
}

@Test func acceptsErrorRatesAboveOneWhenDerived() throws {
  let data = try mutatedFixture { root in
    mutateCase(&root, id: "english-transcribed") {
      $0["hypothesis"] = "one two three four five"
    }
    var aggregate = root["aggregate"] as! [String: Any]
    var accuracy = aggregate["accuracy"] as! [String: Any]
    accuracy["englishWER"] = 2.5
    aggregate["accuracy"] = accuracy
    root["aggregate"] = aggregate
  }
  let evidence = try JSONDecoder().decode(CandidateBenchmarkEvidence.self, from: data)
  #expect(evidence.aggregate.accuracy.englishWER == 2.5)
}

@Test func ignoresSyntheticSpeechFromAccuracyAndProtectedAggregates() throws {
  let data = try mutatedFixture { root in
    mutateCase(&root, id: "english-cancel") { caseObject in
      caseObject["hypothesis"] = "wrong"
      caseObject["outcome"] = "transcribed"
      caseObject["cancellation"] = [
        "outcome": "notCancelled",
        "noLateOutput": false,
      ]
      caseObject["protectedExpectations"] = [[
        "kind": "synthetic-only",
        "text": "must not count",
        "comparison": "exact",
      ]]
    }
    root["aggregate"] = (root["aggregate"] as! [String: Any]).merging([
      "fileDecodeRTF": 0.0022058823529411764,
    ]) { _, replacement in replacement }
  }
  let evidence = try JSONDecoder().decode(CandidateBenchmarkEvidence.self, from: data)
  #expect(evidence.aggregate.accuracy.englishWER == 0.0)
  #expect(evidence.aggregate.accuracy.protectedViolationCount == 0)
}

@Test func rejectsSpeechSilenceMissHiddenByMissingAggregateMetric() throws {
  try expectEvidenceFailure(mutatedFixture { root in
    mutateCase(&root, id: "english-transcribed") { caseObject in
      caseObject["outcome"] = "silence"
      caseObject["hypothesis"] = ""
    }
    var aggregate = root["aggregate"] as! [String: Any]
    var accuracy = aggregate["accuracy"] as! [String: Any]
    accuracy["englishWER"] = NSNull()
    aggregate["accuracy"] = accuracy
    root["aggregate"] = aggregate
  })
}

@Test func rejectsPublicHumanMixedSilenceMissFromUnchangedAggregate() throws {
  try expectEvidenceFailure(mutatedFixture { root in
    mutateCase(&root, id: "english-transcribed") { caseObject in
      caseObject["language"] = "mixed"
      caseObject["outcome"] = "silence"
      caseObject["hypothesis"] = ""
    }
    var aggregate = root["aggregate"] as! [String: Any]
    var accuracy = aggregate["accuracy"] as! [String: Any]
    accuracy["englishWER"] = NSNull()
    aggregate["accuracy"] = accuracy
    root["aggregate"] = aggregate
  })
}

@Test func acceptsCompletedPublicHumanMixedSpeech() throws {
  let data = try mutatedFixture { root in
    mutateCase(&root, id: "english-transcribed") { caseObject in
      caseObject["language"] = "mixed"
    }
    var aggregate = root["aggregate"] as! [String: Any]
    var accuracy = aggregate["accuracy"] as! [String: Any]
    accuracy["englishWER"] = NSNull()
    aggregate["accuracy"] = accuracy
    root["aggregate"] = aggregate
  }
  let evidence = try JSONDecoder().decode(CandidateBenchmarkEvidence.self, from: data)
  #expect(evidence.aggregate.accuracy.englishWER == nil)
  #expect(evidence.aggregate.accuracy.mixedMER == 0.0)
}

@Test func acceptsApplicableOperatorLiveHumanSpeech() throws {
  let data = try mutatedFixture { root in
    mutateCase(&root, id: "public-human") { $0["sourceClass"] = "operatorLiveHuman" }
    root["evidenceClasses"] = [
      "operatorLiveHuman",
      "publicHuman",
      "publicHumanComposite",
      "synthetic",
    ]
  }
  let evidence = try JSONDecoder().decode(CandidateBenchmarkEvidence.self, from: data)
  #expect(evidence.aggregate.accuracy.mandarinCER == 0.0)
}

@Test func acceptsOperatorLiveHumanMixedWithoutCompositeSpans() throws {
  let data = try mutatedFixture { root in
    mutateCase(&root, id: "composite-mixed") { caseObject in
      caseObject["sourceClass"] = "operatorLiveHuman"
      caseObject["codeSwitchSpans"] = []
    }
    root["evidenceClasses"] = ["operatorLiveHuman", "publicHuman", "synthetic"]
    var aggregate = root["aggregate"] as! [String: Any]
    var accuracy = aggregate["accuracy"] as! [String: Any]
    accuracy["codeSwitchSpanAccuracy"] = NSNull()
    aggregate["accuracy"] = accuracy
    root["aggregate"] = aggregate
  }
  let evidence = try JSONDecoder().decode(CandidateBenchmarkEvidence.self, from: data)
  #expect(evidence.aggregate.accuracy.mixedMER == 0.0)
  #expect(evidence.aggregate.accuracy.codeSwitchSpanAccuracy == nil)
}

@Test func rejectsOperatorLiveHumanProtectedViolationFromUnchangedAggregates() throws {
  try expectEvidenceFailure(mutatedFixture { root in
    mutateCase(&root, id: "english-cancel") { caseObject in
      caseObject["sourceClass"] = "operatorLiveHuman"
      caseObject["outcome"] = "transcribed"
      caseObject["hypothesis"] = "cancel this"
      caseObject["cancellation"] = [
        "outcome": "notCancelled",
        "noLateOutput": false,
      ]
      caseObject["protectedExpectations"] = [[
        "kind": "operator-live",
        "text": "must not count",
        "comparison": "exact",
      ]]
    }
    root["evidenceClasses"] = [
      "operatorLiveHuman",
      "publicHuman",
      "publicHumanComposite",
      "synthetic",
    ]
    var aggregate = root["aggregate"] as! [String: Any]
    aggregate["fileDecodeRTF"] = 0.0022058823529411764
    root["aggregate"] = aggregate
  })
}

@Test func excludesCancelledTimingFromCompletedDecodeAggregates() throws {
  let data = try mutatedFixture { root in
    mutateCase(&root, id: "english-cancel") { caseObject in
      var timing = caseObject["timing"] as! [String: Any]
      timing["fileDecodeMilliseconds"] = 999.0
      caseObject["timing"] = timing
    }
  }
  let evidence = try JSONDecoder().decode(CandidateBenchmarkEvidence.self, from: data)
  #expect(evidence.aggregate.latency.warmP50Milliseconds == 1.5)
  #expect(evidence.aggregate.latency.warmP95Milliseconds == 1.75)
  #expect(evidence.aggregate.fileDecodeRTF == 0.0025)
}

@Test func rejectsCompletedTimingChangesWithoutAggregateUpdate() throws {
  try expectEvidenceFailure(mutatedFixture { root in
    mutateCase(&root, id: "english-transcribed") { caseObject in
      var timing = caseObject["timing"] as! [String: Any]
      timing["fileDecodeMilliseconds"] = 999.0
      caseObject["timing"] = timing
    }
  })
}

@Test func acceptsFileDecodeLatencyWithoutPartialTimings() throws {
  let data = try mutatedFixture { root in
    for id in ["none-silence", "public-human", "composite-mixed", "english-transcribed", "english-cancel"] {
      mutateCase(&root, id: id) { caseObject in
        var timing = caseObject["timing"] as! [String: Any]
        timing["firstPartialMilliseconds"] = NSNull()
        caseObject["timing"] = timing
      }
    }
  }
  _ = try JSONDecoder().decode(CandidateBenchmarkEvidence.self, from: data)
}

@Test func rejectsContradictoryLifecycleAndGateClaims() throws {
  try expectEvidenceFailure(mutatedFixture { root in
    var lifecycle = root["lifecycle"] as! [String: Any]
    var load = lifecycle["load"] as! [String: Any]
    load["outcome"] = "failed"
    lifecycle["load"] = load
    root["lifecycle"] = lifecycle
  })
  try expectEvidenceFailure(mutatedFixture { root in
    var lifecycle = root["lifecycle"] as! [String: Any]
    var load = lifecycle["load"] as! [String: Any]
    load["outcome"] = "cancelled"
    lifecycle["load"] = load
    root["lifecycle"] = lifecycle
  })
  try expectEvidenceFailure(mutatedFixture { root in
    var lifecycle = root["lifecycle"] as! [String: Any]
    var unload = lifecycle["unload"] as! [String: Any]
    unload["outcome"] = "failed"
    lifecycle["unload"] = unload
    root["lifecycle"] = lifecycle
  })
  try expectEvidenceFailure(mutatedFixture { root in
    var lifecycle = root["lifecycle"] as! [String: Any]
    var load = lifecycle["load"] as! [String: Any]
    var infer = lifecycle["infer"] as! [String: Any]
    load["outcome"] = "failed"
    infer["outcome"] = "failed"
    lifecycle["load"] = load
    lifecycle["infer"] = infer
    root["lifecycle"] = lifecycle
  })
  try expectEvidenceFailure(mutatedFixture { root in
    var gate = root["gate"] as! [String: Any]
    gate["automatedCandidatePass"] = false
    gate["failureReasons"] = []
    root["gate"] = gate
  })
  try expectEvidenceFailure(mutatedFixture { root in
    var gate = root["gate"] as! [String: Any]
    gate["automatedCandidatePass"] = true
    root["gate"] = gate
  })
  try expectEvidenceFailure(mutatedFixture { root in
    var gate = root["gate"] as! [String: Any]
    gate["releaseAdmitted"] = true
    root["gate"] = gate
  })
  try expectEvidenceFailure(mutatedFixture { root in
    var aggregate = root["aggregate"] as! [String: Any]
    var summary = aggregate["lifecycleSummary"] as! [String: Any]
    summary["allSucceeded"] = false
    aggregate["lifecycleSummary"] = summary
    root["aggregate"] = aggregate
  })
}

@Test func rejectsUnsupportedCompositeLanguagePair() throws {
  try expectEvidenceFailure(mutatedFixture { root in
    mutateCase(&root, id: "composite-mixed") { $0["language"] = "english" }
  })
}

@Test func rejectsAutomatedCandidatePassEvenWithCompleteSafetyAndCoverage() throws {
  try expectEvidenceFailure(mutatedFixture { root in
    var gate = root["gate"] as! [String: Any]
    gate["automatedCandidatePass"] = true
    gate["failureReasons"] = []
    root["gate"] = gate
  })
}

@Test func rejectsPassingGateWithoutRequiredSafetyEvidence() throws {
  try expectEvidenceFailure(mutatedFixture { root in
    var aggregate = root["aggregate"] as! [String: Any]
    var accuracy = aggregate["accuracy"] as! [String: Any]
    accuracy["protectedViolationCount"] = 1
    aggregate["accuracy"] = accuracy
    root["aggregate"] = aggregate
    var gate = root["gate"] as! [String: Any]
    gate["automatedCandidatePass"] = true
    gate["failureReasons"] = []
    root["gate"] = gate
  })
  try expectEvidenceFailure(mutatedFixture { root in
    var privacy = root["privacy"] as! [String: Any]
    privacy["enforced"] = false
    privacy["claimsVerifiedOffline"] = false
    root["privacy"] = privacy
    var gate = root["gate"] as! [String: Any]
    gate["automatedCandidatePass"] = true
    gate["failureReasons"] = []
    root["gate"] = gate
  })
}

@Test func rejectsPassingGateWithoutRequiredCoverage() throws {
  try expectEvidenceFailure(mutatedFixture { root in
    mutateCase(&root, id: "english-transcribed") { $0["sourceClass"] = "synthetic" }
    var gate = root["gate"] as! [String: Any]
    gate["automatedCandidatePass"] = true
    gate["failureReasons"] = []
    root["gate"] = gate
  })
  try expectEvidenceFailure(mutatedFixture { root in
    mutateCase(&root, id: "english-cancel") { caseObject in
      caseObject["outcome"] = "transcribed"
      caseObject["hypothesis"] = "cancel this"
      var cancellation = caseObject["cancellation"] as! [String: Any]
      cancellation["outcome"] = "notCancelled"
      caseObject["cancellation"] = cancellation
    }
    var gate = root["gate"] as! [String: Any]
    gate["automatedCandidatePass"] = true
    gate["failureReasons"] = []
    root["gate"] = gate
  })
}

private func decodeFixture() throws -> CandidateBenchmarkEvidence {
  try JSONDecoder().decode(
    CandidateBenchmarkEvidence.self,
    from: fixtureData()
  )
}

private func fixtureData() throws -> Data {
  let url = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/local-dictation-candidate-benchmark-v2.json")
  return try Data(contentsOf: url)
}

private func fixtureReplacing(_ old: String, with new: String) throws -> Data {
  let fixture = String(data: try fixtureData(), encoding: .utf8)!
  return Data(fixture.replacingOccurrences(of: old, with: new).utf8)
}

private func mutatedFixture(
  _ mutate: (inout [String: Any]) -> Void
) throws -> Data {
  var object = try JSONSerialization.jsonObject(with: fixtureData()) as! [String: Any]
  mutate(&object)
  return try JSONSerialization.data(withJSONObject: object)
}

private func mutateCase(
  _ root: inout [String: Any],
  id: String,
  mutate: (inout [String: Any]) -> Void
) {
  var cases = root["cases"] as! [[String: Any]]
  guard let index = cases.firstIndex(where: { $0["id"] as? String == id }) else {
    fatalError("Missing fixture case: \(id)")
  }
  mutate(&cases[index])
  root["cases"] = cases
}

private func expectEvidenceFailure(_ data: Data) throws {
  do {
    _ = try JSONDecoder().decode(CandidateBenchmarkEvidence.self, from: data)
    Issue.record("Expected malformed candidate benchmark evidence to fail closed.")
  } catch {
    // Any decoding or validation error is a closed failure for malformed evidence.
  }
}
