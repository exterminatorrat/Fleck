import Darwin
import Foundation
import Testing
@testable import LocalDictationCandidateCLI

@Suite("BenchmarkRunTests", .serialized)
struct BenchmarkRunTests {
  @Test func completedCasesRetainTranscriptPartialsAndTimings() async throws {
    let fixture = try BenchmarkFixture(mode: "success")
    defer { fixture.remove() }

    let status = await LocalDictationCandidateCLI.run(
      fixture.arguments,
      eventTimeout: .seconds(2)
    )
    #expect(status == 0)

    let report = try fixture.reportObject()
    let cases = try #require(report["cases"] as? [[String: Any]])
    let completed = try #require(cases.first { $0["caseID"] as? String == "english-technical-prose" })
    #expect(completed["finalTranscript"] as? String == "final")
    let partials = try #require(completed["partialObservations"] as? [[String: Any]])
    #expect(partials.count == 2)
    #expect(partials[0]["sequence"] as? Int == 0)
    #expect(partials[0]["transcript"] as? String == "first")
    #expect(partials[1]["sequence"] as? Int == 1)
    #expect(partials[1]["transcript"] as? String == "second")
    #expect(completed["captureTemperature"] as? String == "cold")
    #expect((completed["requestToFirstPartialMilliseconds"] as? NSNumber)?.doubleValue ?? 0 > 0)
    #expect((completed["fileDecodeMilliseconds"] as? NSNumber)?.doubleValue ?? 0 > 0)
    #expect((completed["audioDurationMilliseconds"] as? NSNumber)?.doubleValue == 1_000)
    #expect((completed["realTimeFactor"] as? NSNumber)?.doubleValue ?? 0 > 0)

    let cancelled = try #require(cases.first { $0["caseID"] as? String == "cancellation-active-decode" })
    #expect(cancelled["finalTranscript"] == nil)
    #expect(cancelled["realTimeFactor"] == nil)
  }

  @Test func duplicateAudioDurationMeasurementsFailClosed() async throws {
    let fixture = try BenchmarkFixture(mode: "duplicate-audio-duration")
    defer { fixture.remove() }

    let status = await LocalDictationCandidateCLI.run(
      fixture.arguments,
      eventTimeout: .seconds(2)
    )
    #expect(status == 2)
    #expect(!FileManager.default.fileExists(atPath: fixture.output.path))
  }

  @Test func missingCancellationAcknowledgementUsesCooperativeShutdownBoundary() async throws {
    let fixture = try BenchmarkFixture(mode: "missing-cancel-ack-cooperative")
    defer { fixture.remove() }

    let invocation = await runWithCapturedStderr(
      fixture.arguments,
      eventTimeout: .milliseconds(500)
    )
    #expect(invocation.status == 2)
    #expect(invocation.stderr == "admission error: lifecycle: cancellation-not-cooperative\n")
    #expect(!FileManager.default.fileExists(atPath: fixture.output.path))
    #expect(try fixture.eventRecords() == ["cancel", "shutdown"])
    try await Task.sleep(for: .milliseconds(100))
    #expect(try fixture.eventRecords() == ["cancel", "shutdown"])
  }

  @Test func missingCancellationAcknowledgementUsesForcedTerminationBoundary() async throws {
    let fixture = try BenchmarkFixture(mode: "missing-cancel-ack-forced")
    defer { fixture.remove() }

    let invocation = await runWithCapturedStderr(
      fixture.arguments,
      eventTimeout: .milliseconds(500)
    )
    #expect(invocation.status == 2)
    #expect(invocation.stderr == "admission error: lifecycle: cancellation-not-cooperative\n")
    #expect(!FileManager.default.fileExists(atPath: fixture.output.path))
    #expect(try fixture.eventRecords() == ["cancel", "shutdown"])
    try await Task.sleep(for: .milliseconds(100))
    #expect(try fixture.eventRecords() == ["cancel", "shutdown"])
  }

  @Test func partialObservationsStayOrderedAndRejectNonIncreasingSequences() throws {
    var run = BenchmarkRun()
    let receivedAt = ContinuousClock.now
    try run.observe(
      .partial(requestID: "case", sequence: 2, transcript: "first"),
      receivedAt: receivedAt
    )
    try run.observe(
      .partial(requestID: "case", sequence: 4, transcript: "second"),
      receivedAt: receivedAt
    )
    #expect(run.partialObservations == [
      PartialTranscriptObservation(sequence: 2, transcript: "first"),
      PartialTranscriptObservation(sequence: 4, transcript: "second"),
    ])
    #expect(throws: BenchmarkRunError.partialSequenceNotIncreasing) {
      try run.observe(
        .partial(requestID: "case", sequence: 4, transcript: "duplicate"),
        receivedAt: receivedAt
      )
    }
  }

  @Test func audioDurationRequiresExplicitPositiveMillisecondsMeasurement() throws {
    var run = BenchmarkRun()
    try run.observe(
      .measurement(requestID: "case", name: "duration", value: 1_000, unit: "ms"),
      receivedAt: ContinuousClock.now
    )
    try run.observe(
      .measurement(requestID: "case", name: "audioDuration", value: 1, unit: "seconds"),
      receivedAt: ContinuousClock.now
    )
    let start = ContinuousClock.now
    let metrics = run.metrics(
      requestStartedAt: start,
      terminalAt: start.advanced(by: .milliseconds(10)),
      cancelled: false
    )
    #expect(metrics.audioDurationMilliseconds == nil)
    #expect(metrics.realTimeFactor == nil)
  }
}

private struct CLIInvocation {
  let status: Int32
  let stderr: String
}

private func runWithCapturedStderr(
  _ arguments: [String],
  eventTimeout: Duration
) async -> CLIInvocation {
  let pipe = Pipe()
  let savedStderr = dup(STDERR_FILENO)
  precondition(savedStderr >= 0)
  fflush(stderr)
  precondition(dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO) >= 0)

  let status = await LocalDictationCandidateCLI.run(
    arguments,
    eventTimeout: eventTimeout
  )

  fflush(stderr)
  precondition(dup2(savedStderr, STDERR_FILENO) >= 0)
  close(savedStderr)
  pipe.fileHandleForWriting.closeFile()
  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  return CLIInvocation(
    status: status,
    stderr: String(decoding: data, as: UTF8.self)
  )
}

private struct BenchmarkFixture {
  let root: URL
  let adapter: URL
  let manifest: URL
  let output: URL
  let marker: URL

  init(mode: String) throws {
    root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("local-dictation-benchmark-\(UUID().uuidString)", isDirectory: true)
    adapter = root.appendingPathComponent("adapter.sh")
    manifest = root.appendingPathComponent("manifest.json")
    output = root.appendingPathComponent("report.json")
    marker = root.appendingPathComponent("adapter-events")
    let runtimeRoot = root.appendingPathComponent("runtime", isDirectory: true)
    let modelRoot = root.appendingPathComponent("model", isDirectory: true)
    try FileManager.default.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: modelRoot, withIntermediateDirectories: true)
    try Data(Self.adapterScript(mode: mode, markerPath: marker.path).utf8).write(to: adapter)
    guard chmod(adapter.path, 0o755) == 0 else {
      throw NSError(domain: "BenchmarkFixture", code: 1)
    }
    let roles = [
      "english-technical-prose",
      "english-developer-command",
      "mandarin-prose-numbers-units",
      "mandarin-technical-terms",
      "english-mandarin-switch",
      "mandarin-english-switch",
      "personal-dictionary-aliases",
      "silence-noise-hallucination",
      "cancellation-active-decode",
      "repeated-load-inference-unload-reload",
    ]
    let cases = roles.enumerated().map { index, role in
      [
        "id": role,
        "role": role,
        "expectedLanguage": "en-US",
        "expectedCategory": "technical",
        "audioPath": "/missing/\(role).wav",
        "audioSHA256": String(repeating: "0", count: 64),
        "evaluationOnlyContextPhrases": [],
        "cancellationPoint": role == "cancellation-active-decode" ? "during-active-decode" : "not-applicable",
        "captureTemperature": index == 0 ? "cold" : "warm",
        "claimsPartials": true,
      ] as [String: Any]
    }
    let manifestObject: [String: Any] = [
      "schemaVersion": 1,
      "manifestID": "benchmark-test",
      "revision": "test-revision",
      "immutable": true,
      "audioAdmission": [
        "status": "synthetic-only",
        "provenance": "test-fixture",
        "consentRecord": "not-applicable",
      ],
      "cases": cases,
    ]
    try JSONSerialization.data(withJSONObject: manifestObject, options: [.sortedKeys]).write(to: manifest)
  }

  var arguments: [String] {
    [
      "run",
      "--manifest", manifest.path,
      "--adapter", adapter.path,
      "--runtime-root", root.appendingPathComponent("runtime").path,
      "--model-root", root.appendingPathComponent("model").path,
      "--output", output.path,
    ]
  }

  func reportObject() throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: Data(contentsOf: output)) as! [String: Any]
  }

  func eventRecords() throws -> [String] {
    guard FileManager.default.fileExists(atPath: marker.path) else { return [] }
    return try String(contentsOf: marker, encoding: .utf8)
      .split(whereSeparator: \.isNewline)
      .map(String.init)
  }

  func remove() {
    try? FileManager.default.removeItem(at: root)
  }

  private static func adapterScript(mode: String, markerPath: String) -> String {
    """
    #!/bin/sh
    set -eu
    mode='\(mode)'
    marker='\(markerPath)'
    record_event() {
      printf '%s\\n' "$1" >> "$marker"
    }
    while IFS= read -r line; do
      request_id=$(printf '%s' "$line" | sed -n 's/.*"requestID":"\\([^"]*\\)".*/\\1/p')
      operation=$(printf '%s' "$line" | sed -n 's/.*"operation":"\\([^"]*\\)".*/\\1/p')
      case "$operation" in
        load)
          printf '%s\\n' "{\\\"event\\\":\\\"ready\\\",\\\"modelRevision\\\":\\\"fixture-model\\\",\\\"requestID\\\":\\\"$request_id\\\",\\\"runtimeVersion\\\":\\\"fixture-runtime\\\",\\\"schemaVersion\\\":1}"
          ;;
        transcribe)
          if [ "$request_id" = "case-cancellation-active-decode" ]; then
            printf '%s\\n' "{\\\"event\\\":\\\"partial\\\",\\\"requestID\\\":\\\"$request_id\\\",\\\"schemaVersion\\\":1,\\\"sequence\\\":0,\\\"transcript\\\":\\\"cancelling\\\"}"
            printf '%s\\n' "{\\\"event\\\":\\\"measurement\\\",\\\"name\\\":\\\"audioDurationMilliseconds\\\",\\\"requestID\\\":\\\"$request_id\\\",\\\"schemaVersion\\\":1,\\\"unit\\\":\\\"ms\\\",\\\"value\\\":1000}"
          else
            printf '%s\\n' "{\\\"event\\\":\\\"partial\\\",\\\"requestID\\\":\\\"$request_id\\\",\\\"schemaVersion\\\":1,\\\"sequence\\\":0,\\\"transcript\\\":\\\"first\\\"}"
            printf '%s\\n' "{\\\"event\\\":\\\"partial\\\",\\\"requestID\\\":\\\"$request_id\\\",\\\"schemaVersion\\\":1,\\\"sequence\\\":1,\\\"transcript\\\":\\\"second\\\"}"
            printf '%s\\n' "{\\\"event\\\":\\\"measurement\\\",\\\"name\\\":\\\"audioDuration\\\",\\\"requestID\\\":\\\"$request_id\\\",\\\"schemaVersion\\\":1,\\\"unit\\\":\\\"milliseconds\\\",\\\"value\\\":1000}"
            if [ "$mode" = "duplicate-audio-duration" ] && [ "$request_id" = "case-english-technical-prose" ]; then
              printf '%s\\n' "{\\\"event\\\":\\\"measurement\\\",\\\"name\\\":\\\"audioDuration\\\",\\\"requestID\\\":\\\"$request_id\\\",\\\"schemaVersion\\\":1,\\\"unit\\\":\\\"milliseconds\\\",\\\"value\\\":1000}"
            fi
            sleep 0.02
            printf '%s\\n' "{\\\"event\\\":\\\"final\\\",\\\"requestID\\\":\\\"$request_id\\\",\\\"schemaVersion\\\":1,\\\"transcript\\\":\\\"final\\\"}"
          fi
          ;;
        cancel)
          if [ "$mode" = "missing-cancel-ack-cooperative" ] || [ "$mode" = "missing-cancel-ack-forced" ]; then
            record_event cancel
          else
            printf '%s\\n' "{\\\"event\\\":\\\"cancelled\\\",\\\"requestID\\\":\\\"$request_id\\\",\\\"schemaVersion\\\":1}"
          fi
          ;;
        shutdown)
          if [ "$mode" = "missing-cancel-ack-cooperative" ]; then
            record_event shutdown
            printf '%s\\n' "{\\\"event\\\":\\\"unloaded\\\",\\\"requestID\\\":\\\"$request_id\\\",\\\"schemaVersion\\\":1}"
            exit 0
          elif [ "$mode" = "missing-cancel-ack-forced" ]; then
            record_event shutdown
            sleep 5
          else
            printf '%s\\n' "{\\\"event\\\":\\\"unloaded\\\",\\\"requestID\\\":\\\"$request_id\\\",\\\"schemaVersion\\\":1}"
            exit 0
          fi
          ;;
        unload|shutdown)
          printf '%s\\n' "{\\\"event\\\":\\\"unloaded\\\",\\\"requestID\\\":\\\"$request_id\\\",\\\"schemaVersion\\\":1}"
          if [ "$operation" = "shutdown" ]; then exit 0; fi
          ;;
      esac
    done
    """
  }
}
