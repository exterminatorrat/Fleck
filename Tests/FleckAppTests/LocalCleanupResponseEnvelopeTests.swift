import Foundation
import FleckCore
import Testing

@testable import FleckApp

@Test func envelopeExtractsOnlyTheSingleTextMember() {
  #expect(extract(#"{"text":"Send the report."}"#) == "Send the report.")
  #expect(
    extract(#" { "text" : "你好\u0021" } "#) == "你好!"
  )
}

@Test func envelopeRejectsObservedQwenWrapperFamilies() {
  for raw in [
    #"{"quote":"Send the report."}"#,
    #""Send the report.""#,
    "Thinking Process:\n" + #"{"text":"Send the report."}"#,
    "Here is the cleaned text: " + #"{"text":"Send the report."}"#,
    #"{"text":"Send the report."}"# + "\nHere is the answer.",
    #"{"text":"Send the report." trailing"#,
    #"{"text":"Send the report.}"#
  ] {
    #expect(extract(raw) == nil, "Unexpectedly accepted wrapper: \(raw)")
  }
}

@Test func envelopeRejectsNonStringNestedAndAdditionalValues() {
  for raw in [
    #"["Send the report."]"#,
    #"{"text":{"value":"Send the report."}}"#,
    #"{"text":["Send the report."]}"#,
    #"{"text":null}"#,
    #"{"text":42}"#,
    #"{"text":"Send the report.","quote":"extra"}"#,
    #"{"quote":"extra","text":"Send the report."}"#
  ] {
    #expect(extract(raw) == nil, "Unexpectedly accepted non-exact shape: \(raw)")
  }
}

@Test func envelopeRejectsDuplicateKeysIncludingEscapedEquivalentKeys() {
  for raw in [
    #"{"text":"one","text":"two"}"#,
    #"{"text":"one","\u0074ext":"two"}"#,
    #"{"\u0074ext":"one","text":"two"}"#
  ] {
    #expect(extract(raw) == nil, "Unexpectedly accepted duplicate key: \(raw)")
  }
}

@Test func envelopeRequiresFullJSONConsumptionAndJSONWhitespaceOnly() {
  #expect(
    extract("\n\t" + #"{"text":"Send the report."}"# + "\r\n")
      == "Send the report."
  )
  for raw in [
    "prefix " + #"{"text":"Send the report."}"#,
    #"{"text":"Send the report."}"# + " trailing",
    "\u{00A0}" + #"{"text":"Send the report."}"#,
    #"{"text":"Send the report."}"# + "\u{00A0}"
  ] {
    #expect(extract(raw) == nil, "Unexpectedly accepted non-JSON boundary bytes")
  }
}

@Test func envelopeRejectsMalformedAndInvalidUTF8Input() {
  #expect(extract(#"{"text":"unfinished"#) == nil)
  #expect(extract(#"{"text":"bad\q"}"#) == nil)

  let invalidUTF8 = Data([
    0x7B, 0x22, 0x74, 0x65, 0x78, 0x74, 0x22, 0x3A, 0x22,
    0xC3, 0x28,
    0x22, 0x7D
  ])
  #expect(extract(invalidUTF8) == nil)
}

@Test func envelopeRejectsEmptyAndWhitespaceOnlyCandidates() {
  for raw in [
    #"{"text":""}"#,
    #"{"text":" "}"#,
    #"{"text":"\n\t"}"#
  ] {
    #expect(extract(raw) == nil)
  }
}

@Test func envelopeEnforcesInjectedByteAndCharacterBounds() {
  let input = #"{"text":"Send"}"#
  let inputBytes = Data(input.utf8).count
  #expect(
    extract(input, maximumInputBytes: inputBytes) == "Send"
  )
  #expect(
    extract(input, maximumInputBytes: inputBytes - 1) == nil
  )

  let output = #"{"text":"你好"}"#
  #expect(
    extract(output, maximumOutputCharacters: 2) == "你好"
  )
  #expect(
    extract(output, maximumOutputCharacters: 1) == nil
  )
  #expect(
    extract(output, maximumOutputCharacters: 0) == nil
  )
}

@Test func extractedFaithfulPunctuationAndCaseCleanupIsAccepted() {
  let baseline = "um, send the report"
  guard let candidate = extract(#"{"text":"Send the report."}"#) else {
    Issue.record("Expected the exact text envelope to yield a candidate")
    return
  }

  let decision = FaithfulCleanupValidator().validate(
    candidate: candidate,
    against: .init(baseline: baseline, protectedForms: [], replacements: 0)
  )
  guard case .accepted(let text, _) = decision else {
    Issue.record("Expected faithful cleanup to accept the extracted candidate")
    return
  }
  #expect(text == candidate)
}

@Test func extractedProtectedSemanticChangesAreRejectedByFaithfulValidator() {
  let cases: [(String, String, String)] = [
    ("name", "Email Alice now", "Email Bob now"),
    ("number", "Send 20 files", "Send 21 files"),
    ("date", "Meet on 2026-08-20", "Meet on 2026-08-21"),
    ("URL", "Open https://example.com/docs", "Open https://example.com/help"),
    ("path", "Read /fixtures/fleck/README.md", "Read /fixtures/fleck/AGENTS.md"),
    ("command", "Run git status --short", "Run git log --short"),
    ("destination", "Save it to Inbox", "Save it to Archive"),
    ("commitment", "I will ship the patch", "I might ship the patch"),
    ("negation", "Do not send the email", "Do send the email")
  ]

  for (label, baseline, changed) in cases {
    guard let candidate = extract(#"{"text":"\#(changed)"}"#) else {
      Issue.record("Expected an envelope candidate for \(label)")
      continue
    }
    let decision = FaithfulCleanupValidator().validate(
      candidate: candidate,
      against: .init(baseline: baseline, protectedForms: [], replacements: 0)
    )
    guard case .rejected = decision else {
      Issue.record("Expected \(label) change to be rejected")
      continue
    }
  }
}

private let defaultMaximumInputBytes = 4_096
private let defaultMaximumOutputCharacters = 512

private func extract(
  _ raw: String,
  maximumInputBytes: Int = defaultMaximumInputBytes,
  maximumOutputCharacters: Int = defaultMaximumOutputCharacters
) -> String? {
  extract(
    Data(raw.utf8),
    maximumInputBytes: maximumInputBytes,
    maximumOutputCharacters: maximumOutputCharacters
  )
}

private func extract(
  _ data: Data,
  maximumInputBytes: Int = defaultMaximumInputBytes,
  maximumOutputCharacters: Int = defaultMaximumOutputCharacters
) -> String? {
  LocalCleanupResponseEnvelope.extract(
    from: data,
    maximumInputBytes: maximumInputBytes,
    maximumOutputCharacters: maximumOutputCharacters
  )
}
