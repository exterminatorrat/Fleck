import Foundation
import Testing
@testable import LocalDictationCandidateProtocol

private func fixture(_ name: String) throws -> Data {
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

@Suite("CandidateAdapterProtocolTests")
struct CandidateAdapterProtocolTests {

  @Test func requestRoundTripsWithBoundedContext() throws {
    let request = CandidateAdapterRequest(
      schemaVersion: 1,
      requestID: "request-1",
      operation: .transcribe,
      audioPath: "/fixtures/mixed.wav",
      sampleRate: 16_000,
      localeIdentifier: "auto",
      contextPhrases: ["Fleck", "SwiftUI"],
      transcript: nil,
      protectedForms: [],
      cleanupMode: nil
    )

    #expect(
      try JSONLinesCodec.decodeRequest(JSONLinesCodec.encode(request)) == request
    )
  }

  @Test func requestRejectsUnknownKeyAndMoreThanOneHundredContextPhrases() throws {
    let unknownKey = Data(
      #"{"schemaVersion":1,"requestID":"request-1","operation":"load","unexpected":true}"#.utf8
    )
    #expect(throws: CandidateAdapterProtocolError.self) {
      try JSONLinesCodec.decodeRequest(unknownKey)
    }

    let request = CandidateAdapterRequest(
      schemaVersion: 1,
      requestID: "request-1",
      operation: .transcribe,
      audioPath: "/fixtures/mixed.wav",
      sampleRate: 16_000,
      localeIdentifier: "auto",
      contextPhrases: (0..<101).map { "phrase-\($0)" },
      transcript: nil,
      protectedForms: [],
      cleanupMode: nil
    )
    #expect(throws: CandidateAdapterProtocolError.self) {
      try JSONLinesCodec.encode(request)
    }
  }

  @Test func requestRejectsNewlineRelativePathEmptyIDUnsupportedVersionAndDuplicateContext() throws {
    let newline = CandidateAdapterRequest(
      schemaVersion: 1,
      requestID: "request-1",
      operation: .transcribe,
      audioPath: "/fixtures/mixed.wav",
      sampleRate: 16_000,
      localeIdentifier: "auto\nprivate",
      contextPhrases: [],
      transcript: nil,
      protectedForms: [],
      cleanupMode: nil
    )
    #expect(throws: CandidateAdapterProtocolError.self) {
      try JSONLinesCodec.encode(newline)
    }

    let relative = CandidateAdapterRequest(
      schemaVersion: 1,
      requestID: "request-1",
      operation: .transcribe,
      audioPath: "relative.wav",
      sampleRate: 16_000,
      localeIdentifier: "auto",
      contextPhrases: [],
      transcript: nil,
      protectedForms: [],
      cleanupMode: nil
    )
    #expect(throws: CandidateAdapterProtocolError.self) {
      try JSONLinesCodec.encode(relative)
    }

    let emptyID = CandidateAdapterRequest(
      schemaVersion: 1,
      requestID: "",
      operation: .load,
      audioPath: nil,
      sampleRate: nil,
      localeIdentifier: nil,
      contextPhrases: [],
      transcript: nil,
      protectedForms: [],
      cleanupMode: nil
    )
    #expect(throws: CandidateAdapterProtocolError.self) {
      try JSONLinesCodec.encode(emptyID)
    }

    let unsupportedVersion = Data(
      #"{"schemaVersion":2,"requestID":"request-1","operation":"load"}"#.utf8
    )
    #expect(throws: CandidateAdapterProtocolError.self) {
      try JSONLinesCodec.decodeRequest(unsupportedVersion)
    }

    let duplicate = CandidateAdapterRequest(
      schemaVersion: 1,
      requestID: "request-1",
      operation: .transcribe,
      audioPath: "/fixtures/mixed.wav",
      sampleRate: 16_000,
      localeIdentifier: "auto",
      contextPhrases: ["Fleck", "Fleck"],
      transcript: nil,
      protectedForms: [],
      cleanupMode: nil
    )
    #expect(throws: CandidateAdapterProtocolError.self) {
      try JSONLinesCodec.encode(duplicate)
    }
  }

  @Test func requestRejectsFieldsThatDoNotBelongToOperation() throws {
    let invalid = Data(
      #"{"audioPath":"/fixtures/mixed.wav","operation":"load","requestID":"request-1","schemaVersion":1}"#.utf8
    )
    #expect(throws: CandidateAdapterProtocolError.self) {
      try JSONLinesCodec.decodeRequest(invalid)
    }
  }

  @Test func encodingIsOneSortedJSONObjectPerLine() throws {
    let request = CandidateAdapterRequest(
      schemaVersion: 1,
      requestID: "request-1",
      operation: .load,
      audioPath: nil,
      sampleRate: nil,
      localeIdentifier: nil,
      contextPhrases: [],
      transcript: nil,
      protectedForms: [],
      cleanupMode: nil
    )
    let encoded = try JSONLinesCodec.encode(request)
    #expect(encoded.last == 0x0A)
    #expect(encoded.dropLast().first == Character("{").asciiValue)
    #expect(encoded.dropLast().last == Character("}").asciiValue)
    #expect(encoded.filter { $0 == 0x0A }.count == 1)
  }

  @Test func requestAndEventsRoundTripCheckedInFixtures() throws {
    let requestData = try fixture("local-dictation-adapter-request-v1.json")
    let request = try JSONLinesCodec.decodeRequest(requestData)
    #expect(try JSONLinesCodec.decodeRequest(JSONLinesCodec.encode(request)) == request)

    let eventLines = try fixture("local-dictation-adapter-event-v1.jsonl")
      .split(separator: 0x0A, omittingEmptySubsequences: true)
    #expect(eventLines.count == 7)
    for line in eventLines {
      let event = try JSONLinesCodec.decodeEvent(Data(line) + Data([0x0A]))
      #expect(
        try JSONLinesCodec.decodeEvent(JSONLinesCodec.encode(event)) == event
      )
    }
  }
}
