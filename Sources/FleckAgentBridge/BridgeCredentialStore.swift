#if os(macOS)
  import Foundation
  import FleckCore
  import Security

  enum BridgeCredentialStoreError: Error, Equatable {
    case invalidCredential
    case credentialNotFound
    case keychainFailure
  }

  protocol BridgeKeychainDataStoring:
    KeychainDataStoring,
    Sendable
  {
    func delete(service: String, account: String) throws
  }

  struct BridgeCredentialStore {
    static let service = "com.harryjin.fleck.agent-profile"
    static let legacyService = "com.harryjin.motes.agent-profile"

    private let keychainStore: any BridgeKeychainDataStoring

    init(
      keychainStore: any BridgeKeychainDataStoring =
        BridgeSystemKeychainDataStore()
    ) {
      self.keychainStore = keychainStore
    }

    func store(profileID: UUID, canonicalBase64: String) throws {
      guard
        let credential = Data(base64Encoded: canonicalBase64, options: []),
        credential.count == 32,
        credential.base64EncodedString() == canonicalBase64
      else {
        throw BridgeCredentialStoreError.invalidCredential
      }
      do {
        try migratingStore.write(
          credential,
          account: profileID.uuidString
        )
      } catch {
        throw BridgeCredentialStoreError.keychainFailure
      }
    }

    func load(profileID: UUID) throws -> String {
      let data: Data
      do {
        guard
          let loaded = try migratingStore.readOrMigrate(
            account: profileID.uuidString
          )
        else {
          throw BridgeCredentialStoreError.credentialNotFound
        }
        data = loaded
      } catch let error as BridgeCredentialStoreError {
        throw error
      } catch {
        throw BridgeCredentialStoreError.keychainFailure
      }
      guard data.count == 32 else {
        throw BridgeCredentialStoreError.invalidCredential
      }
      return data.base64EncodedString()
    }

    func delete(profileID: UUID) throws {
      do {
        try keychainStore.delete(
          service: Self.service,
          account: profileID.uuidString
        )
      } catch {
        throw BridgeCredentialStoreError.keychainFailure
      }
    }

    private var migratingStore: MigratingKeychainDataStore {
      MigratingKeychainDataStore(
        store: keychainStore,
        canonicalService: Self.service,
        legacyServices: [Self.legacyService]
      )
    }
  }

  private final class BridgeSystemKeychainDataStore:
    BridgeKeychainDataStoring,
    @unchecked Sendable
  {
    func read(service: String, account: String) throws -> Data? {
      var query = keychainQuery(service: service, account: account)
      query[kSecReturnData] = true
      query[kSecMatchLimit] = kSecMatchLimitOne
      var result: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &result)
      if status == errSecItemNotFound {
        return nil
      }
      guard status == errSecSuccess, let data = result as? Data else {
        throw BridgeCredentialStoreError.keychainFailure
      }
      return data
    }

    func write(_ data: Data, service: String, account: String) throws {
      let query = keychainQuery(service: service, account: account)
      let updateStatus = SecItemUpdate(
        query as CFDictionary,
        [kSecValueData: data] as CFDictionary
      )
      if updateStatus == errSecSuccess { return }
      guard updateStatus == errSecItemNotFound else {
        throw BridgeCredentialStoreError.keychainFailure
      }
      var item = query
      item[kSecValueData] = data
      item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
        throw BridgeCredentialStoreError.keychainFailure
      }
    }

    func delete(service: String, account: String) throws {
      let status = SecItemDelete(
        keychainQuery(service: service, account: account) as CFDictionary
      )
      guard status == errSecSuccess || status == errSecItemNotFound else {
        throw BridgeCredentialStoreError.keychainFailure
      }
    }

    private func keychainQuery(
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
#endif
