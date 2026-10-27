import CryptoKit
import Foundation
import Testing

@testable import FleckApp

@Suite(.serialized)
struct AgentEventWebhookSignerTests {
  @Test func matchesSyntheticStandardWebhooksVectorAndPreservesExactBody() throws {
    let key = Data((0..<32).map(UInt8.init))
    let body = Data(#"{"type":"test","n":1}"#.utf8)
    let originalBody = body

    let signature = try AgentEventWebhookSigner.sign(
      id: "evt_123",
      timestamp: Date(timeIntervalSince1970: 1_729_000_000),
      body: body,
      secret: key
    )

    #expect(signature.webhookID == "evt_123")
    #expect(signature.webhookTimestamp == "1729000000")
    #expect(
      signature.webhookSignature
        == "v1,tuzAFw83CjtlM+5kFpPgaq9Opt5rlvgP31QR60nEYmc="
    )
    #expect(body == originalBody)
  }

  @Test func eachAttemptUsesItsOwnTimestampAndSignsEmbeddedNULBytes() throws {
    let key = Data(repeating: 0x5a, count: 32)
    let body = Data([0x7b, 0x00, 0xff, 0x7d])
    let first = try AgentEventWebhookSigner.sign(
      id: "evt_retry-1",
      timestamp: Date(timeIntervalSince1970: 1_729_000_000),
      body: body,
      secret: key
    )
    let second = try AgentEventWebhookSigner.sign(
      id: "evt_retry-1",
      timestamp: Date(timeIntervalSince1970: 1_729_000_001),
      body: body,
      secret: key
    )

    #expect(first.webhookID == second.webhookID)
    #expect(first.webhookTimestamp == "1729000000")
    #expect(second.webhookTimestamp == "1729000001")
    #expect(first.webhookSignature != second.webhookSignature)
  }

  @Test func overlapSignatureUsesOneTimestampAndFramesCurrentBeforePrevious() throws {
    let currentSecret = Data(repeating: 0x31, count: 32)
    let previousSecret = Data(repeating: 0x42, count: 32)
    let timestamp = Date(timeIntervalSince1970: 1_729_000_000.9)
    let body = Data([0x7b, 0x00, 0xff, 0x7d])

    let signature = try AgentEventWebhookSigner.sign(
      id: "evt_overlap",
      timestamp: timestamp,
      body: body,
      currentSecret: currentSecret,
      previousSecret: previousSecret
    )
    var message = Data("evt_overlap.1729000000.".utf8)
    message.append(body)
    let currentCode = HMAC<SHA256>.authenticationCode(
      for: message,
      using: SymmetricKey(data: currentSecret)
    )
    let previousCode = HMAC<SHA256>.authenticationCode(
      for: message,
      using: SymmetricKey(data: previousSecret)
    )

    #expect(signature.webhookID == "evt_overlap")
    #expect(signature.webhookTimestamp == "1729000000")
    #expect(
      signature.webhookSignature
        == "v1,\(Data(currentCode).base64EncodedString()) v1,\(Data(previousCode).base64EncodedString())"
    )
    #expect(body == Data([0x7b, 0x00, 0xff, 0x7d]))
  }

  @Test func rejectsInvalidIdentifiersTimestampsKeysAndOversizedBodies() {
    let key = Data(repeating: 0x31, count: 32)
    let timestamp = Date(timeIntervalSince1970: 1_729_000_000)

    for id in [
      "", ".", "evt.with.dot", "evt\r\ninjected", "evt\u{00}nul",
      String(repeating: "x", count: 129),
    ] {
      #expect(throws: AgentEventWebhookSigningError.invalidInput) {
        try AgentEventWebhookSigner.sign(id: id, timestamp: timestamp, body: Data(), secret: key)
      }
    }

    for invalidTimestamp in [
      Date(timeIntervalSince1970: -1),
      Date(timeIntervalSince1970: .nan),
      Date(timeIntervalSince1970: .infinity),
    ] {
      #expect(throws: AgentEventWebhookSigningError.invalidInput) {
        try AgentEventWebhookSigner.sign(
          id: "evt_123", timestamp: invalidTimestamp, body: Data(), secret: key)
      }
    }

    for invalidKey in [Data(repeating: 0x31, count: 23), Data(repeating: 0x31, count: 65)] {
      #expect(throws: AgentEventWebhookSigningError.invalidInput) {
        try AgentEventWebhookSigner.sign(
          id: "evt_123", timestamp: timestamp, body: Data(), secret: invalidKey)
      }
    }

    #expect(throws: AgentEventWebhookSigningError.invalidInput) {
      try AgentEventWebhookSigner.sign(
        id: "evt_123",
        timestamp: timestamp,
        body: Data(repeating: 0x7b, count: 1_025),
        secret: key
      )
    }
  }
}
