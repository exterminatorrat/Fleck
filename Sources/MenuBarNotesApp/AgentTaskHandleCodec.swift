import CryptoKit
import Foundation
import MenuBarNotesCore

struct AgentTaskReference: Codable, Equatable, Sendable {
  let noteID: UUID
  let revision: UInt64
  let line: Int
  let checklistLineSHA256: String

  init(
    noteID: UUID,
    revision: UInt64,
    line: Int,
    checklistLine: String
  ) {
    self.noteID = noteID
    self.revision = revision
    self.line = line
    checklistLineSHA256 = AgentTaskHandleCodec.sha256Hex(checklistLine)
  }

  fileprivate init(
    noteID: UUID,
    revision: UInt64,
    line: Int,
    checklistLineSHA256: String
  ) {
    self.noteID = noteID
    self.revision = revision
    self.line = line
    self.checklistLineSHA256 = checklistLineSHA256
  }
}

protocol AgentSigningKeyProviding: Sendable {
  func signingKey() throws -> Data
}

final class AgentKeychainSigningKeyProvider:
  AgentSigningKeyProviding, @unchecked Sendable
{
  private static let lock = NSLock()
  private let secretStore: any AgentSecretStoring
  private let randomBytes: any AgentRandomBytesProviding

  init(
    secretStore: any AgentSecretStoring = AgentKeychainSecretStore(),
    randomBytes: any AgentRandomBytesProviding = AgentSystemRandomBytesProvider()
  ) {
    self.secretStore = secretStore
    self.randomBytes = randomBytes
  }

  func signingKey() throws -> Data {
    try Self.lock.withLock {
      if let stored = try secretStore.read(
        service: AgentCredentialSecurity.taskHandleSigningService,
        account: AgentCredentialSecurity.taskHandleSigningAccount
      ) {
        guard stored.count == AgentCredentialSecurity.secretByteCount else {
          throw AgentCredentialSecurity.internalFailure
        }
        return stored
      }

      let generated = try randomBytes.randomBytes(
        count: AgentCredentialSecurity.secretByteCount
      )
      guard generated.count == AgentCredentialSecurity.secretByteCount else {
        throw AgentCredentialSecurity.internalFailure
      }
      try secretStore.write(
        generated,
        service: AgentCredentialSecurity.taskHandleSigningService,
        account: AgentCredentialSecurity.taskHandleSigningAccount
      )
      return generated
    }
  }
}

struct AgentTaskHandleCodec: Sendable {
  private struct Payload: Codable {
    let version: Int
    let noteID: UUID
    let revision: UInt64
    let line: Int
    let checklistLineSHA256: String
  }

  private static let version = 1
  private let signingKeyProvider: any AgentSigningKeyProviding

  init(
    signingKeyProvider: any AgentSigningKeyProviding =
      AgentKeychainSigningKeyProvider()
  ) {
    self.signingKeyProvider = signingKeyProvider
  }

  func encode(_ reference: AgentTaskReference) throws -> String {
    guard
      reference.line > 0,
      isSHA256Hex(reference.checklistLineSHA256)
    else {
      throw AgentWorkspaceError(
        code: .invalidPayload,
        recoveryAction: "Use a valid one-based checklist line."
      )
    }
    let key = try signingKeyProvider.signingKey()
    guard key.count == AgentCredentialSecurity.secretByteCount else {
      throw AgentCredentialSecurity.internalFailure
    }
    let payload = Payload(
      version: Self.version,
      noteID: reference.noteID,
      revision: reference.revision,
      line: reference.line,
      checklistLineSHA256: reference.checklistLineSHA256
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let payloadData = try encoder.encode(payload)
    let tag = Data(
      HMAC<SHA256>.authenticationCode(
        for: payloadData,
        using: SymmetricKey(data: key)
      )
    )
    return payloadData.base64URLEncoded() + "." + tag.base64URLEncoded()
  }

  func decode(
    _ handle: String,
    noteID: UUID,
    revision: UInt64,
    checklistLine: String? = nil
  ) throws -> AgentTaskReference {
    let parts = handle.split(
      separator: ".",
      omittingEmptySubsequences: false
    )
    guard
      parts.count == 2,
      let payloadData = Data(base64URL: String(parts[0])),
      let suppliedTag = Data(base64URL: String(parts[1])),
      suppliedTag.count == SHA256.byteCount
    else {
      throw expiredError()
    }

    let key = try signingKeyProvider.signingKey()
    guard key.count == AgentCredentialSecurity.secretByteCount else {
      throw AgentCredentialSecurity.internalFailure
    }
    let expectedTag = Data(
      HMAC<SHA256>.authenticationCode(
        for: payloadData,
        using: SymmetricKey(data: key)
      )
    )
    guard AgentCredentialSecurity.constantTimeEqual(suppliedTag, expectedTag)
    else {
      throw expiredError()
    }
    guard
      let payload = try? JSONDecoder().decode(Payload.self, from: payloadData),
      payload.version == Self.version,
      payload.noteID == noteID,
      payload.revision == revision,
      payload.line > 0,
      isSHA256Hex(payload.checklistLineSHA256)
    else {
      throw expiredError()
    }
    if let checklistLine {
      guard
        AgentCredentialSecurity.constantTimeEqual(
          Data(payload.checklistLineSHA256.utf8),
          Data(Self.sha256Hex(checklistLine).utf8)
        )
      else {
        throw expiredError()
      }
    }
    return AgentTaskReference(
      noteID: payload.noteID,
      revision: payload.revision,
      line: payload.line,
      checklistLineSHA256: payload.checklistLineSHA256
    )
  }

  static func sha256Hex(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
  }

  private func isSHA256Hex(_ value: String) -> Bool {
    value.utf8.count == 64
      && value.utf8.allSatisfy {
        (48...57).contains($0) || (97...102).contains($0)
      }
  }

  private func expiredError() -> AgentWorkspaceError {
    AgentWorkspaceError(
      code: .taskHandleExpired,
      recoveryAction: "List tasks again to obtain current handles."
    )
  }
}

extension Data {
  fileprivate init?(base64URL value: String) {
    guard
      !value.isEmpty,
      value.utf8.allSatisfy({
        (48...57).contains($0)
          || (65...90).contains($0)
          || (97...122).contains($0)
          || $0 == 45
          || $0 == 95
      })
    else {
      return nil
    }
    let padding = String(repeating: "=", count: (4 - value.count % 4) % 4)
    let base64 =
      value
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
      + padding
    guard let decoded = Data(base64Encoded: base64) else {
      return nil
    }
    guard decoded.base64URLEncoded() == value else {
      return nil
    }
    self = decoded
  }

  fileprivate func base64URLEncoded() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
