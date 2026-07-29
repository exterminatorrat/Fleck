import Foundation
import MenuBarNotesCore
import Testing

@testable import MotesAgentBridge

@Test func bridgeCredentialLoadsLegacyProfileAndThenUsesFleckService() throws {
  let store = BridgeMemoryKeychainStore()
  let profileID = UUID()
  let credential = Data(repeating: 0x35, count: 32)
  try store.write(
    credential,
    service: BridgeCredentialStore.legacyService,
    account: profileID.uuidString
  )
  let credentials = BridgeCredentialStore(keychainStore: store)

  #expect(
    try credentials.load(profileID: profileID)
      == credential.base64EncodedString()
  )
  #expect(
    try store.read(
      service: BridgeCredentialStore.service,
      account: profileID.uuidString
    ) == credential
  )
  #expect(
    try store.read(
      service: BridgeCredentialStore.legacyService,
      account: profileID.uuidString
    ) == credential
  )
}

private final class BridgeMemoryKeychainStore:
  BridgeKeychainDataStoring,
  @unchecked Sendable
{
  private let lock = NSLock()
  private var values: [String: Data] = [:]

  func read(service: String, account: String) throws -> Data? {
    lock.withLock { values[key(service, account)] }
  }

  func write(_ data: Data, service: String, account: String) throws {
    lock.withLock {
      values[key(service, account)] = data
    }
  }

  func delete(service: String, account: String) throws {
    _ = lock.withLock {
      values.removeValue(forKey: key(service, account))
    }
  }

  private func key(_ service: String, _ account: String) -> String {
    "\(service)\u{0}\(account)"
  }
}
