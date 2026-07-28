#if os(macOS)
  import Foundation
  import Security

  enum BridgeCredentialStoreError: Error, Equatable {
    case invalidCredential
    case credentialNotFound
    case keychainFailure
  }

  struct BridgeCredentialStore {
    static let service = "com.harryjin.motes.agent-profile"

    func store(profileID: UUID, canonicalBase64: String) throws {
      guard
        let credential = Data(base64Encoded: canonicalBase64, options: []),
        credential.count == 32,
        credential.base64EncodedString() == canonicalBase64
      else {
        throw BridgeCredentialStoreError.invalidCredential
      }

      let query = keychainQuery(profileID: profileID)
      let update = [kSecValueData: credential] as CFDictionary
      let updateStatus = SecItemUpdate(query as CFDictionary, update)
      if updateStatus == errSecSuccess { return }
      guard updateStatus == errSecItemNotFound else {
        throw BridgeCredentialStoreError.keychainFailure
      }

      var item = query
      item[kSecValueData] = credential
      item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
        throw BridgeCredentialStoreError.keychainFailure
      }
    }

    func load(profileID: UUID) throws -> String {
      var query = keychainQuery(profileID: profileID)
      query[kSecReturnData] = true
      query[kSecMatchLimit] = kSecMatchLimitOne
      var result: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &result)
      guard status != errSecItemNotFound else {
        throw BridgeCredentialStoreError.credentialNotFound
      }
      guard status == errSecSuccess, let data = result as? Data else {
        throw BridgeCredentialStoreError.keychainFailure
      }
      guard data.count == 32 else {
        throw BridgeCredentialStoreError.invalidCredential
      }
      return data.base64EncodedString()
    }

    func delete(profileID: UUID) throws {
      let status = SecItemDelete(keychainQuery(profileID: profileID) as CFDictionary)
      guard status == errSecSuccess || status == errSecItemNotFound else {
        throw BridgeCredentialStoreError.keychainFailure
      }
    }

    private func keychainQuery(profileID: UUID) -> [CFString: Any] {
      [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: Self.service,
        kSecAttrAccount: profileID.uuidString,
      ]
    }
  }
#endif
