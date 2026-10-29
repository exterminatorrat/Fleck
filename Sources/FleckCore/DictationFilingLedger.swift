import CryptoKit
import Foundation

public struct DictationFilingInsertion: Codable, Equatable, Sendable {
  public let noteID: UUID
  public let noteRevision: UInt64
  public let location: Int
  public let length: Int
  public let digest: String

  public init(noteID: UUID, noteRevision: UInt64, location: Int, length: Int, digest: String) {
    self.noteID = noteID
    self.noteRevision = noteRevision
    self.location = location
    self.length = length
    self.digest = digest
  }
}

public struct DictationFilingCommit: Codable, Equatable, Sendable {
  public enum State: String, Codable, Sendable {
    case committed
    case undone
  }

  public let captureID: UUID
  public var state: State
  public let inputDigest: String
  public let insertions: [DictationFilingInsertion]

  public init(
    captureID: UUID,
    state: State = .committed,
    inputDigest: String,
    insertions: [DictationFilingInsertion]
  ) {
    self.captureID = captureID
    self.state = state
    self.inputDigest = inputDigest
    self.insertions = insertions
  }
}

public struct DictationFilingLedger: Codable, Equatable, Sendable {
  public let version: Int
  public var commits: [DictationFilingCommit]

  public init(commits: [DictationFilingCommit] = []) {
    version = 1
    self.commits = commits
  }

  public var isValid: Bool {
    guard version == 1, Set(commits.map(\.captureID)).count == commits.count else {
      return false
    }
    return commits.allSatisfy { commit in
      guard Self.isDigest(commit.inputDigest), (1...8).contains(commit.insertions.count) else {
        return false
      }
      let grouped = Dictionary(grouping: commit.insertions, by: \.noteID)
      return grouped.values.allSatisfy { insertions in
        let ordered = insertions.sorted { $0.location < $1.location }
        var end = 0
        return ordered.allSatisfy { insertion in
          guard insertion.location >= end, insertion.length > 0,
            insertion.location <= Int.max - insertion.length,
            insertion.noteRevision == ordered.first?.noteRevision,
            Self.isDigest(insertion.digest)
          else { return false }
          end = insertion.location + insertion.length
          return true
        }
      }
    }
  }

  public static func digest(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  public func preserves(_ previous: DictationFilingLedger) -> Bool {
    guard isValid, previous.isValid else { return false }
    let current = Dictionary(uniqueKeysWithValues: commits.map { ($0.captureID, $0) })
    return previous.commits.allSatisfy { prior in
      guard let next = current[prior.captureID],
        next.inputDigest == prior.inputDigest, next.insertions == prior.insertions
      else { return false }
      return prior.state == .committed || next.state == .undone
    }
  }

  public func canonicalData() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(self)
  }

  private static func isDigest(_ value: String) -> Bool {
    value.utf8.count == 64 && value.utf8.allSatisfy {
      (48...57).contains($0) || (97...102).contains($0)
    }
  }
}
