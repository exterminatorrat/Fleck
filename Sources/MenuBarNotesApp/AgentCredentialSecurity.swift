import CryptoKit
import Foundation
import MenuBarNotesCore
import Security

protocol AgentSecretStoring: KeychainDataStoring {
  func delete(service: String, account: String) throws
}

protocol AgentRandomBytesProviding: Sendable {
  func randomBytes(count: Int) throws -> Data
}

enum AgentCredentialSecurity {
  static let profileVerifierService =
    "com.harryjin.fleck.agent-profile-verifier"
  static let legacyProfileVerifierService =
    "com.harryjin.motes.agent-profile-verifier"
  static let taskHandleSigningService =
    "com.harryjin.fleck.agent-task-handles"
  static let legacyTaskHandleSigningService =
    "com.harryjin.motes.agent-task-handles"
  static let taskHandleSigningAccount = "default"
  static let secretByteCount = 32

  static func sha256(_ value: Data) -> Data {
    Data(SHA256.hash(data: value))
  }

  static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
    let maximumCount = max(lhs.count, rhs.count)
    var difference = UInt64(lhs.count ^ rhs.count)

    for index in 0..<maximumCount {
      let left = index < lhs.count ? lhs[index] : 0
      let right = index < rhs.count ? rhs[index] : 0
      difference |= UInt64(left ^ right)
    }
    return difference == 0
  }

  static var permissionRevokedError: AgentWorkspaceError {
    AgentWorkspaceError(
      code: .permissionRevoked,
      recoveryAction: "Reconnect this integration in Motes Settings."
    )
  }

  static var internalFailure: AgentWorkspaceError {
    AgentWorkspaceError(code: .internalSaveFailure)
  }
}

struct AgentSystemRandomBytesProvider: AgentRandomBytesProviding {
  func randomBytes(count: Int) throws -> Data {
    guard count > 0 else {
      throw AgentCredentialSecurity.internalFailure
    }
    var bytes = Data(count: count)
    let status = bytes.withUnsafeMutableBytes {
      SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!)
    }
    guard status == errSecSuccess else {
      throw AgentCredentialSecurity.internalFailure
    }
    return bytes
  }
}

final class AgentKeychainSecretStore: AgentSecretStoring, @unchecked Sendable {
  func read(service: String, account: String) throws -> Data? {
    var query = Self.baseQuery(service: service, account: account)
    query[kSecReturnData] = true
    query[kSecMatchLimit] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    if status == errSecItemNotFound {
      return nil
    }
    guard status == errSecSuccess, let data = result as? Data else {
      throw AgentCredentialSecurity.internalFailure
    }
    return data
  }

  func write(_ data: Data, service: String, account: String) throws {
    let query = Self.baseQuery(service: service, account: account)
    let updateStatus = SecItemUpdate(
      query as CFDictionary,
      [kSecValueData: data] as CFDictionary
    )
    if updateStatus == errSecSuccess {
      return
    }
    guard updateStatus == errSecItemNotFound else {
      throw AgentCredentialSecurity.internalFailure
    }

    var addition = query
    addition[kSecValueData] = data
    addition[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    guard SecItemAdd(addition as CFDictionary, nil) == errSecSuccess else {
      throw AgentCredentialSecurity.internalFailure
    }
  }

  func delete(service: String, account: String) throws {
    let status = SecItemDelete(
      Self.baseQuery(service: service, account: account) as CFDictionary
    )
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw AgentCredentialSecurity.internalFailure
    }
  }

  static func baseQuery(
    service: String,
    account: String
  ) -> [CFString: Any] {
    [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account,
      kSecUseDataProtectionKeychain: true,
    ]
  }
}
