import Foundation
import Testing

@testable import FleckCore

@Suite(.serialized)
struct MigratingKeychainDataStoreTests {
  private let canonical = "com.harryjin.fleck.test"
  private let legacy = "com.harryjin.motes.test"
  private let account = "profile"

  @Test func canonicalSecretWinsWithoutReadingLegacy() throws {
    let store = MemoryKeychainDataStore()
    store.seed(Data("new".utf8), service: canonical, account: account)
    store.seed(Data("old".utf8), service: legacy, account: account)
    let migrating = migration(store)

    #expect(try migrating.readOrMigrate(account: account) == Data("new".utf8))
    #expect(
      store.reads
        == [.init(service: canonical, account: account)]
    )
  }

  @Test func legacySecretCopiesToCanonicalAndVerifiesBeforeReturn() throws {
    let store = MemoryKeychainDataStore()
    let value = Data([1, 2, 3, 4])
    store.seed(value, service: legacy, account: account)

    #expect(try migration(store).readOrMigrate(account: account) == value)
    #expect(store.value(service: canonical, account: account) == value)
    #expect(store.value(service: legacy, account: account) == value)
    #expect(
      store.reads
        == [
          .init(service: canonical, account: account),
          .init(service: legacy, account: account),
          .init(service: canonical, account: account),
        ]
    )
  }

  @Test func failedCanonicalWriteLeavesLegacySecretUntouched() throws {
    let store = MemoryKeychainDataStore()
    let value = Data([5, 6, 7])
    store.seed(value, service: legacy, account: account)
    store.failWrites = true

    #expect(throws: (any Error).self) {
      _ = try migration(store).readOrMigrate(account: account)
    }
    #expect(store.value(service: canonical, account: account) == nil)
    #expect(store.value(service: legacy, account: account) == value)
  }

  @Test func failedReadbackRejectsTheMigratedSecret() throws {
    let store = MemoryKeychainDataStore()
    store.seed(Data("legacy".utf8), service: legacy, account: account)
    store.canonicalReadbackOverride = Data("wrong".utf8)

    #expect(throws: KeychainMigrationError.verificationFailed) {
      _ = try migration(store).readOrMigrate(account: account)
    }
    #expect(
      store.value(service: legacy, account: account)
        == Data("legacy".utf8)
    )
  }

  @Test func missingCanonicalAndLegacyReturnsNil() throws {
    let store = MemoryKeychainDataStore()

    #expect(try migration(store).readOrMigrate(account: account) == nil)
  }

  @Test func enhancedResumeKeyMigratesWithoutChangingItsBytes() throws {
    let store = MemoryKeychainDataStore()
    let value = Data((0..<32).map(UInt8.init))
    store.seed(
      value,
      service: "com.motes.enhanced-model-resume",
      account: "default"
    )
    let migrating = MigratingKeychainDataStore(
      store: store,
      canonicalService: "com.harryjin.fleck.enhanced-model-resume",
      legacyServices: ["com.motes.enhanced-model-resume"]
    )

    #expect(try migrating.readOrMigrate(account: "default") == value)
    #expect(
      store.value(
        service: "com.harryjin.fleck.enhanced-model-resume",
        account: "default"
      ) == value
    )
  }

  private func migration(
    _ store: MemoryKeychainDataStore
  ) -> MigratingKeychainDataStore {
    MigratingKeychainDataStore(
      store: store,
      canonicalService: canonical,
      legacyServices: [legacy]
    )
  }
}

private final class MemoryKeychainDataStore:
  KeychainDataStoring,
  @unchecked Sendable
{
  struct Read: Equatable {
    let service: String
    let account: String
  }

  private let lock = NSLock()
  private var values: [String: Data] = [:]
  private var recordedReads: [Read] = []
  private var didWriteCanonical = false
  var failWrites = false
  var canonicalReadbackOverride: Data?

  var reads: [Read] {
    lock.withLock { recordedReads }
  }

  func seed(_ value: Data, service: String, account: String) {
    lock.withLock {
      values[key(service, account)] = value
    }
  }

  func value(service: String, account: String) -> Data? {
    lock.withLock { values[key(service, account)] }
  }

  func read(service: String, account: String) throws -> Data? {
    lock.withLock {
      recordedReads.append(.init(service: service, account: account))
      if didWriteCanonical, let canonicalReadbackOverride,
        service.contains(".fleck.")
      {
        return canonicalReadbackOverride
      }
      return values[key(service, account)]
    }
  }

  func write(_ data: Data, service: String, account: String) throws {
    try lock.withLock {
      if failWrites {
        throw MemoryKeychainError.writeFailed
      }
      values[key(service, account)] = data
      didWriteCanonical = service.contains(".fleck.")
    }
  }

  private func key(_ service: String, _ account: String) -> String {
    "\(service)\u{0}\(account)"
  }
}

private enum MemoryKeychainError: Error {
  case writeFailed
}
