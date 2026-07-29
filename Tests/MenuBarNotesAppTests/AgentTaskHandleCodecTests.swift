import CryptoKit
import Foundation
import MenuBarNotesCore
import Testing

@testable import MenuBarNotesApp

struct AgentTaskHandleCodecTests {
  private let noteID = UUID(
    uuidString: "00000000-0000-0000-0000-000000000001"
  )!
  private let key = Data((0..<32).map(UInt8.init))

  @Test func handleRoundTripsCompleteUnicodeChecklistLine() throws {
    let codec = AgentTaskHandleCodec(
      signingKeyProvider: FixedSigningKeyProvider(key: key)
    )
    let line = "\t○ Review café 👩🏽‍💻 e\u{301}"
    let reference = AgentTaskReference(
      noteID: noteID,
      revision: 17,
      line: 4,
      checklistLine: line
    )

    let handle = try codec.encode(reference)
    let decoded = try codec.decode(
      handle,
      noteID: noteID,
      revision: 17,
      checklistLine: line
    )

    #expect(decoded == reference)
    #expect(!handle.contains(line))
    #expect(!handle.contains("+"))
    #expect(!handle.contains("/"))
    #expect(!handle.contains("="))
  }

  @Test func handleBindsOneBasedLineNumberAndCompleteLineHash() throws {
    let codec = AgentTaskHandleCodec(
      signingKeyProvider: FixedSigningKeyProvider(key: key)
    )
    let line = "  ● Ship Motes"
    let first = try codec.encode(
      .init(noteID: noteID, revision: 2, line: 1, checklistLine: line)
    )
    let second = try codec.encode(
      .init(noteID: noteID, revision: 2, line: 2, checklistLine: line)
    )
    let changedIndent = try codec.encode(
      .init(noteID: noteID, revision: 2, line: 1, checklistLine: " ● Ship Motes")
    )

    #expect(first != second)
    #expect(first != changedIndent)
    #expect(throws: AgentWorkspaceError.self) {
      try codec.encode(
        .init(noteID: noteID, revision: 2, line: 0, checklistLine: line)
      )
    }
  }

  @Test func changedBytesWrongNoteAndWrongRevisionAreExpired() throws {
    let codec = AgentTaskHandleCodec(
      signingKeyProvider: FixedSigningKeyProvider(key: key)
    )
    let line = "○ Task"
    let handle = try codec.encode(
      .init(noteID: noteID, revision: 8, line: 3, checklistLine: line)
    )
    var tampered = Array(handle.utf8)
    tampered[tampered.count / 2] =
      tampered[tampered.count / 2] == 65 ? 66 : 65
    let tamperedHandle = String(decoding: tampered, as: UTF8.self)

    try expectExpired {
      _ = try codec.decode(
        tamperedHandle,
        noteID: noteID,
        revision: 8,
        checklistLine: line
      )
    }
    try expectExpired {
      _ = try codec.decode(
        handle,
        noteID: UUID(),
        revision: 8,
        checklistLine: line
      )
    }
    try expectExpired {
      _ = try codec.decode(
        handle,
        noteID: noteID,
        revision: 9,
        checklistLine: line
      )
    }
  }

  @Test func visuallySimilarButByteDifferentUnicodeLineIsRejected() throws {
    let codec = AgentTaskHandleCodec(
      signingKeyProvider: FixedSigningKeyProvider(key: key)
    )
    let composed = "○ café"
    let decomposed = "○ cafe\u{301}"
    let handle = try codec.encode(
      .init(noteID: noteID, revision: 3, line: 1, checklistLine: composed)
    )

    try expectExpired {
      _ = try codec.decode(
        handle,
        noteID: noteID,
        revision: 3,
        checklistLine: decomposed
      )
    }
  }

  @Test func malformedPayloadUnknownVersionAndWrongKeyAreRejected() throws {
    let codec = AgentTaskHandleCodec(
      signingKeyProvider: FixedSigningKeyProvider(key: key)
    )
    let line = "○ Task"
    let handle = try codec.encode(
      .init(noteID: noteID, revision: 1, line: 1, checklistLine: line)
    )
    let wrongKeyCodec = AgentTaskHandleCodec(
      signingKeyProvider: FixedSigningKeyProvider(
        key: Data(repeating: 0xFF, count: 32)
      )
    )

    for invalid in ["", ".", "not-a-handle", "%%%.\u{0}"] {
      try expectExpired {
        _ = try codec.decode(
          invalid,
          noteID: noteID,
          revision: 1,
          checklistLine: line
        )
      }
    }
    try expectExpired {
      _ = try wrongKeyCodec.decode(
        handle,
        noteID: noteID,
        revision: 1,
        checklistLine: line
      )
    }

    let malformed = signedHandle(
      payload: Data("not-json".utf8),
      key: key
    )
    try expectExpired {
      _ = try codec.decode(
        malformed,
        noteID: noteID,
        revision: 1,
        checklistLine: line
      )
    }

    let versionBytes = try JSONSerialization.data(
      withJSONObject: [
        "version": 2,
        "noteID": noteID.uuidString,
        "revision": 1,
        "line": 1,
        "checklistLineSHA256":
          "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      ],
      options: [.sortedKeys]
    )
    let forged = signedHandle(payload: versionBytes, key: key)
    try expectExpired {
      _ = try codec.decode(
        forged,
        noteID: noteID,
        revision: 1,
        checklistLine: line
      )
    }
  }

  @Test func nonCanonicalBase64TamperingIsRejected() throws {
    let codec = AgentTaskHandleCodec(
      signingKeyProvider: FixedSigningKeyProvider(key: key)
    )
    let line = "○ Task"
    let handle = try codec.encode(
      .init(noteID: noteID, revision: 1, line: 1, checklistLine: line)
    )
    var parts = handle.split(separator: ".").map(String.init)
    let alphabet = Array(
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
    )
    let canonicalLast = try #require(parts[1].last)
    let index = try #require(alphabet.firstIndex(of: canonicalLast))
    #expect(index % 4 == 0)
    parts[1].removeLast()
    parts[1].append(alphabet[index + 1])

    try expectExpired {
      _ = try codec.decode(
        parts.joined(separator: "."),
        noteID: noteID,
        revision: 1,
        checklistLine: line
      )
    }
  }

  @Test func productionSigningKeyProviderCreatesAndReusesExactlyThirtyTwoBytes() throws {
    let secrets = FakeTaskHandleSecretStore()
    let random = CountingRandomBytes(value: Data(repeating: 0x67, count: 32))
    let provider = AgentKeychainSigningKeyProvider(
      secretStore: secrets,
      randomBytes: random
    )

    #expect(try provider.signingKey() == Data(repeating: 0x67, count: 32))
    #expect(try provider.signingKey() == Data(repeating: 0x67, count: 32))
    #expect(random.callCount == 1)
    #expect(
      secrets.value(
        service: AgentCredentialSecurity.taskHandleSigningService,
        account: AgentCredentialSecurity.taskHandleSigningAccount
      ) == Data(repeating: 0x67, count: 32)
    )
  }

  @Test func signingProviderRejectsMalformedStoredAndGeneratedKeys() throws {
    let malformedSecrets = FakeTaskHandleSecretStore()
    try malformedSecrets.write(
      Data(repeating: 0x01, count: 31),
      service: AgentCredentialSecurity.taskHandleSigningService,
      account: AgentCredentialSecurity.taskHandleSigningAccount
    )
    let malformedStored = AgentKeychainSigningKeyProvider(
      secretStore: malformedSecrets,
      randomBytes: CountingRandomBytes(value: Data(repeating: 0x02, count: 32))
    )
    #expect(throws: AgentWorkspaceError.self) {
      try malformedStored.signingKey()
    }

    let malformedGenerated = AgentKeychainSigningKeyProvider(
      secretStore: FakeTaskHandleSecretStore(),
      randomBytes: CountingRandomBytes(value: Data(repeating: 0x03, count: 33))
    )
    #expect(throws: AgentWorkspaceError.self) {
      try malformedGenerated.signingKey()
    }
  }

  @Test func legacyTaskSigningKeyMigratesWithoutRegeneration() throws {
    let secrets = FakeTaskHandleSecretStore()
    let key = Data(repeating: 0x42, count: 32)
    try secrets.write(
      key,
      service: AgentCredentialSecurity.legacyTaskHandleSigningService,
      account: AgentCredentialSecurity.taskHandleSigningAccount
    )
    let random = CountingRandomBytes(value: Data(repeating: 0x99, count: 32))
    let provider = AgentKeychainSigningKeyProvider(
      secretStore: secrets,
      randomBytes: random
    )

    #expect(try provider.signingKey() == key)
    #expect(random.callCount == 0)
    #expect(
      secrets.value(
        service: AgentCredentialSecurity.taskHandleSigningService,
        account: AgentCredentialSecurity.taskHandleSigningAccount
      ) == key
    )
    #expect(
      secrets.value(
        service: AgentCredentialSecurity.legacyTaskHandleSigningService,
        account: AgentCredentialSecurity.taskHandleSigningAccount
      ) == key
    )
  }
}

private func expectExpired(_ operation: () throws -> Void) throws {
  do {
    try operation()
    Issue.record("Expected task_handle_expired")
  } catch let error as AgentWorkspaceError {
    #expect(error.code == .taskHandleExpired)
    #expect(error.recoveryAction == "List tasks again to obtain current handles.")
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

private func signedHandle(payload: Data, key: Data) -> String {
  let tag = Data(
    HMAC<SHA256>.authenticationCode(
      for: payload,
      using: SymmetricKey(data: key)
    )
  )
  return payload.base64URLEncoded() + "." + tag.base64URLEncoded()
}

private struct FixedSigningKeyProvider: AgentSigningKeyProviding {
  let key: Data

  func signingKey() throws -> Data {
    key
  }
}

private final class FakeTaskHandleSecretStore:
  AgentSecretStoring, @unchecked Sendable
{
  private let lock = NSLock()
  private var storage: [String: Data] = [:]

  func value(service: String, account: String) -> Data? {
    lock.withLock { storage["\(service)\u{0}\(account)"] }
  }

  func read(service: String, account: String) throws -> Data? {
    value(service: service, account: account)
  }

  func write(_ data: Data, service: String, account: String) throws {
    lock.withLock {
      storage["\(service)\u{0}\(account)"] = data
    }
  }

  func delete(service: String, account: String) throws {
    _ = lock.withLock {
      storage.removeValue(forKey: "\(service)\u{0}\(account)")
    }
  }
}

private final class CountingRandomBytes:
  AgentRandomBytesProviding, @unchecked Sendable
{
  private let lock = NSLock()
  private let value: Data
  private var calls = 0

  init(value: Data) {
    self.value = value
  }

  var callCount: Int {
    lock.withLock { calls }
  }

  func randomBytes(count: Int) throws -> Data {
    lock.withLock {
      calls += 1
      return value
    }
  }
}

extension Data {
  fileprivate func base64URLEncoded() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
