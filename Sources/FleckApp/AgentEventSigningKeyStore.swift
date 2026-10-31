import Foundation

struct AgentEventSigningKeyStore: Sendable {
  private static let service = "com.harryjin.fleck.agent-event-signing-keys"
  private let secretStore: any AgentSecretStoring

  init(secretStore: any AgentSecretStoring = AgentKeychainSecretStore()) {
    self.secretStore = secretStore
  }

  static func newReference() -> String {
    UUID().uuidString.lowercased()
  }

  func validatedSecretData(from signingSecret: String) throws -> Data {
    guard
      signingSecret.hasPrefix("whsec_"),
      let data = Data(base64Encoded: String(signingSecret.dropFirst("whsec_".count))),
      data.base64EncodedString() == signingSecret.dropFirst("whsec_".count),
      (24...64).contains(data.count)
    else {
      throw AgentEventSubscriptionError.invalidConfiguration
    }
    return data
  }

  func store(secretData: Data, reference: String) throws {
    guard
      Self.isValidReference(reference),
      (24...64).contains(secretData.count)
    else {
      throw AgentEventSubscriptionError.invalidConfiguration
    }
    do {
      try secretStore.write(secretData, service: Self.service, account: reference)
    } catch {
      throw AgentEventSubscriptionError.storageFailure
    }
  }

  func delete(reference: String) throws {
    guard Self.isValidReference(reference) else {
      throw AgentEventSubscriptionError.storageFailure
    }
    do {
      try secretStore.delete(service: Self.service, account: reference)
    } catch {
      throw AgentEventSubscriptionError.storageFailure
    }
  }

  func validatedSecretData(reference: String) throws -> Data {
    guard Self.isValidReference(reference) else {
      throw AgentEventSubscriptionError.storageFailure
    }
    do {
      guard let secretData = try secretStore.read(service: Self.service, account: reference),
        (24...64).contains(secretData.count)
      else {
        throw AgentEventSubscriptionError.storageFailure
      }
      return secretData
    } catch let error as AgentEventSubscriptionError {
      throw error
    } catch {
      throw AgentEventSubscriptionError.storageFailure
    }
  }

  private static func isValidReference(_ reference: String) -> Bool {
    guard let uuid = UUID(uuidString: reference) else { return false }
    return uuid.uuidString.lowercased() == reference
  }
}
