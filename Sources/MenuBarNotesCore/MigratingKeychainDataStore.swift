import Foundation

public protocol KeychainDataStoring: Sendable {
  func read(service: String, account: String) throws -> Data?
  func write(_ data: Data, service: String, account: String) throws
}

public enum KeychainMigrationError: Error, Equatable, Sendable {
  case verificationFailed
}

public struct MigratingKeychainDataStore: Sendable {
  private let store: any KeychainDataStoring
  private let canonicalService: String
  private let legacyServices: [String]

  public init(
    store: any KeychainDataStoring,
    canonicalService: String,
    legacyServices: [String]
  ) {
    self.store = store
    self.canonicalService = canonicalService
    self.legacyServices = legacyServices
  }

  public func readOrMigrate(account: String) throws -> Data? {
    if let canonical = try store.read(
      service: canonicalService,
      account: account
    ) {
      return canonical
    }
    for legacyService in legacyServices {
      guard
        let legacy = try store.read(
          service: legacyService,
          account: account
        )
      else { continue }
      try store.write(
        legacy,
        service: canonicalService,
        account: account
      )
      guard
        try store.read(
          service: canonicalService,
          account: account
        ) == legacy
      else {
        throw KeychainMigrationError.verificationFailed
      }
      return legacy
    }
    return nil
  }

  public func write(_ data: Data, account: String) throws {
    try store.write(
      data,
      service: canonicalService,
      account: account
    )
  }
}
