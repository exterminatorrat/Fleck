import Foundation
import Testing
@testable import LocalDictationCandidateProtocol
@testable import LocalDictationCandidateRunner

private func fixtureAdapterScript() -> URL {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/local-dictation-fixture-adapter.sh")
}

private func request(
  _ requestID: String,
  operation: CandidateAdapterOperation,
  targetRequestID: String? = nil
) -> CandidateAdapterRequest {
  CandidateAdapterRequest(
    schemaVersion: 1,
    requestID: requestID,
    operation: operation,
    audioPath: operation == .transcribe ? "/fixtures/mixed.wav" : nil,
    sampleRate: operation == .transcribe ? 16_000 : nil,
    localeIdentifier: operation == .transcribe ? "auto" : nil,
    contextPhrases: [],
    transcript: operation == .clean ? "baseline" : nil,
    protectedForms: [],
    cleanupMode: operation == .clean ? .conservative : nil,
    targetRequestID: targetRequestID
  )
}

private func startProcess(_ mode: String) async throws -> AdapterProcess {
  let process = AdapterProcess(
    redactedRoots: [URL(fileURLWithPath: "/private/model-root")]
  )
  _ = await process.events()
  try await process.start(
    executableURL: URL(fileURLWithPath: "/bin/sh"),
    arguments: [fixtureAdapterScript().path, mode],
    environment: ["PATH": "/usr/bin:/bin"]
  )
  return process
}

@Suite("AdapterProcessTests")
struct AdapterProcessTests {

  @Test func cooperativeLifecyclePreservesPartialFinalOrdering() async throws {
    let process = try await startProcess("cooperative")
    let stream = await process.events()
    let collected = Task {
      var events: [CandidateAdapterEvent] = []
      for try await event in stream {
        events.append(event)
        if case .final = event { break }
      }
      return events
    }

    try await process.send(request("load-1", operation: .load))
    try await process.send(request("transcribe-1", operation: .transcribe))
    let events = try await collected.value
    #expect(events.count == 3)
    if events.count == 3 {
      #expect(events[0].kind == .ready)
      #expect(events[1].kind == .partial)
      #expect(events[2].kind == .final)
      #expect(events.allSatisfy { $0.requestID == "transcribe-1" || $0.requestID == "load-1" })
    }
    _ = try await process.shutdown(timeout: .seconds(1))
  }

  @Test func rejectsUnexpectedRequestIDAndMalformedJSON() async throws {
    for mode in ["wrong-id", "malformed"] {
      let process = try await startProcess(mode)
      let stream = await process.events()
      let failure = Task {
        do {
          for try await _ in stream { }
          return false
        } catch {
          return true
        }
      }
      try await process.send(request("load-1", operation: .load))
      #expect(await failure.value)
      await process.terminate()
    }
  }

  @Test func rejectsInvalidEventOrdering() async throws {
    let process = try await startProcess("invalid-order")
    let stream = await process.events()
    let failure = Task {
      do {
        for try await _ in stream { }
        return false
      } catch {
        return true
      }
    }
    try await process.send(request("transcribe-1", operation: .transcribe))
    #expect(await failure.value)
    await process.terminate()
  }

  @Test func boundsStdoutAndStderrAndRedactsConfiguredRoots() async throws {
    let process = try await startProcess("flood-both")
    let stream = await process.events()
    let failure = Task {
      do {
        for try await _ in stream { }
        return false
      } catch {
        return true
      }
    }
    try await process.send(request("load-1", operation: .load))
    #expect(await failure.value)
    let diagnostics = await process.diagnostics()
    #expect(diagnostics.stderrByteCount <= 1_048_576)
    #expect(diagnostics.stderr.contains("<redacted-path>"))
    #expect(!diagnostics.stderr.contains("/private/model-root"))
    await process.terminate()
  }

  @Test func boundedEventBufferOverflowFailsClosed() async throws {
    let process = AdapterProcess()
    let stream = await process.events()
    try await process.start(
      executableURL: URL(fileURLWithPath: "/bin/sh"),
      arguments: [fixtureAdapterScript().path, "flood-events"],
      environment: ["PATH": "/usr/bin:/bin"]
    )
    try await process.send(request("load-1", operation: .load))
    try await Task.sleep(for: .milliseconds(100))
    let failure = Task {
      do {
        for try await _ in stream { }
        return nil as AdapterProcessError?
      } catch let error as AdapterProcessError {
        return error
      } catch {
        return nil
      }
    }
    let result = await failure.value
    #expect(result == .stdoutFlood, "received \(String(describing: result))")
    #expect(!(await process.diagnostics()).childIsRunning)
    await process.terminate()
  }

  @Test func timeoutCancelsThenForciblyTerminatesExactChild() async throws {
    let process = try await startProcess("stuck")
    try await process.send(request("load-1", operation: .load))
    try await process.send(request("transcribe-1", operation: .transcribe))
    let path = try await process.cancel(requestID: "transcribe-1", timeout: .milliseconds(50))
    #expect(path == .forcedTermination)
    let diagnostics = await process.diagnostics()
    #expect(diagnostics.forcedTermination)
    #expect(!diagnostics.childIsRunning)
  }

  @Test func cooperativeCancellationAndShutdownRecordAcknowledgements() async throws {
    let process = try await startProcess("cooperative")
    try await process.send(request("load-1", operation: .load))
    try await process.send(request("transcribe-1", operation: .transcribe))
    let path = try await process.cancel(requestID: "transcribe-1", timeout: .seconds(1))
    #expect(path == .cooperativeCancellation)
    let shutdownPath = try await process.shutdown(timeout: .seconds(1))
    #expect(shutdownPath == .cooperativeShutdown)
    let diagnostics = await process.diagnostics()
    #expect(diagnostics.cancelAcknowledged)
    #expect(diagnostics.shutdownAcknowledged)
    #expect(!diagnostics.childIsRunning)
    #expect(diagnostics.childExitStatus == 0)
  }

  @Test func eofBeforeShutdownAcknowledgementFailsClosed() async throws {
    let process = try await startProcess("eof-before-shutdown")
    try await process.send(request("load-1", operation: .load))
    var didThrow = false
    do {
      _ = try await process.shutdown(timeout: .milliseconds(100))
    } catch is AdapterProcessError {
      didThrow = true
    }
    #expect(didThrow)
    let diagnostics = await process.diagnostics()
    #expect(!diagnostics.shutdownAcknowledged)
  }
}
