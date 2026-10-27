import CryptoKit
import Foundation

enum AgentEventWebhookSigningError: Error {
  case invalidInput
}

struct AgentEventWebhookSignature: Equatable, Sendable {
  let webhookID: String
  let webhookTimestamp: String
  let webhookSignature: String
}

enum AgentEventWebhookSigner {
  static func sign(
    id: String,
    timestamp: Date,
    body: Data,
    secret: Data
  ) throws -> AgentEventWebhookSignature {
    try sign(id: id, timestamp: timestamp, body: body, secret: secret, previousSecret: nil)
  }

  static func sign(
    id: String,
    timestamp: Date,
    body: Data,
    currentSecret: Data,
    previousSecret: Data?
  ) throws -> AgentEventWebhookSignature {
    try sign(
      id: id,
      timestamp: timestamp,
      body: body,
      secret: currentSecret,
      previousSecret: previousSecret
    )
  }

  static func sign(
    id: String,
    timestamp: Date,
    body: Data,
    secret: Data,
    previousSecret: Data?
  ) throws -> AgentEventWebhookSignature {
    guard
      isValidID(id),
      body.count <= 1_024,
      (24...64).contains(secret.count),
      previousSecret.map({ (24...64).contains($0.count) }) ?? true
    else {
      throw AgentEventWebhookSigningError.invalidInput
    }

    let seconds = timestamp.timeIntervalSince1970
    guard seconds.isFinite, seconds >= 0, seconds < Double(Int64.max) else {
      throw AgentEventWebhookSigningError.invalidInput
    }
    let unixSeconds = String(Int64(seconds.rounded(.down)))
    var message = Data("\(id).\(unixSeconds).".utf8)
    message.append(body)
    let code = HMAC<SHA256>.authenticationCode(
      for: message,
      using: SymmetricKey(data: secret)
    )
    let currentSignature = "v1,\(Data(code).base64EncodedString())"
    let signature: String
    if let previousSecret {
      let previousCode = HMAC<SHA256>.authenticationCode(
        for: message,
        using: SymmetricKey(data: previousSecret)
      )
      signature = "\(currentSignature) v1,\(Data(previousCode).base64EncodedString())"
    } else {
      signature = currentSignature
    }

    return AgentEventWebhookSignature(
      webhookID: id,
      webhookTimestamp: unixSeconds,
      webhookSignature: signature
    )
  }

  private static func isValidID(_ id: String) -> Bool {
    let bytes = Array(id.utf8)
    guard (1...128).contains(bytes.count) else { return false }
    return bytes.allSatisfy {
      (65...90).contains($0)
        || (97...122).contains($0)
        || (48...57).contains($0)
        || $0 == 95
        || $0 == 45
        || $0 == 58
    }
  }
}
