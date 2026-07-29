import Foundation

public actor DictationHistoryStore {
  private static let retentionInterval: TimeInterval = 30 * 24 * 60 * 60

  private let rootURL: URL
  private let fileManager: FileManager
  private let now: @Sendable () -> Date
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  public init(
    rootURL: URL,
    fileManager: FileManager = .default,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.rootURL = rootURL
    self.fileManager = fileManager
    self.now = now

    encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601

    decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
  }

  public func save(_ record: DictationHistoryRecord) throws {
    try createDirectoryIfNeeded()
    try encoder.encode(record).write(to: recordURL(for: record.id), options: .atomic)
    try purgeExpired()
  }

  public func list() throws -> [DictationHistoryRecord] {
    try purgeExpired()
    return try records()
  }

  public func delete(id: UUID) throws {
    let url = recordURL(for: id)
    guard fileManager.fileExists(atPath: url.path) else { return }
    try fileManager.removeItem(at: url)
  }

  public func clear() throws {
    guard fileManager.fileExists(atPath: historyURL.path) else { return }
    try fileManager.removeItem(at: historyURL)
  }

  public func purgeExpired() throws {
    try createDirectoryIfNeeded()
    let expirationDate = now().addingTimeInterval(-Self.retentionInterval)
    for url in try recordFiles() {
      guard let data = try? Data(contentsOf: url),
        let record = try? decoder.decode(DictationHistoryRecord.self, from: data),
        record.completedAt <= expirationDate
      else { continue }
      try fileManager.removeItem(at: url)
    }
  }

  private var historyURL: URL {
    rootURL.appendingPathComponent("DictationHistory", isDirectory: true)
  }

  private func recordURL(for id: UUID) -> URL {
    historyURL.appendingPathComponent("\(id.uuidString.lowercased()).json")
  }

  private func createDirectoryIfNeeded() throws {
    try fileManager.createDirectory(at: historyURL, withIntermediateDirectories: true)
  }

  private func recordFiles() throws -> [URL] {
    try fileManager.contentsOfDirectory(at: historyURL, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "json" }
  }

  private func records() throws -> [DictationHistoryRecord] {
    try recordFiles().compactMap { url in
      guard let data = try? Data(contentsOf: url) else { return nil }
      return try? decoder.decode(DictationHistoryRecord.self, from: data)
    }
    .sorted {
      $0.completedAt == $1.completedAt
        ? $0.id.uuidString < $1.id.uuidString
        : $0.completedAt > $1.completedAt
    }
  }
}
