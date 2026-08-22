import Foundation

public struct BoundedOutput: Sendable {
  public static let defaultLimit = 1_048_576

  private let limit: Int
  private let redactedRoots: [String]
  private var storage = Data()
  private var totalByteCount = 0
  private var truncated = false

  public init(
    limit: Int = BoundedOutput.defaultLimit,
    redactedRoots: [URL] = []
  ) {
    self.limit = max(1, limit)
    self.redactedRoots = redactedRoots.map { $0.standardizedFileURL.path }
  }

  public mutating func append(_ data: Data) {
    totalByteCount += data.count
    storage.append(data)
    if storage.count > limit {
      storage = Data(storage.suffix(limit))
      truncated = true
    }
  }

  public var byteCount: Int { storage.count }
  public var receivedByteCount: Int { totalByteCount }
  public var didTruncate: Bool { truncated }

  public var string: String {
    var value = String(decoding: storage, as: UTF8.self)
    for root in redactedRoots where !root.isEmpty {
      value = value.replacingOccurrences(of: root, with: "<redacted-path>")
    }
    return value
  }
}
