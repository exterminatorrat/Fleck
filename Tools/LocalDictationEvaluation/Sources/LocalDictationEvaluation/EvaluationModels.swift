import Foundation

public enum EvaluationLanguageMode: String, Codable, CaseIterable, Hashable, Equatable, Sendable {
  case english
  case mandarin
  case mixed
}

public enum TranscriptArtifactKind: String, Codable, CaseIterable, Hashable, Equatable, Sendable {
  case asrRaw
  case dictionaryBaseline
  case cleanedResult
}

public struct EditCounts: Codable, Equatable, Sendable {
  public let substitutions: Int
  public let deletions: Int
  public let insertions: Int
  public let referenceUnits: Int

  public init(
    substitutions: Int,
    deletions: Int,
    insertions: Int,
    referenceUnits: Int
  ) {
    self.substitutions = substitutions
    self.deletions = deletions
    self.insertions = insertions
    self.referenceUnits = referenceUnits
  }

  public var errorRate: Double {
    guard referenceUnits > 0 else {
      return substitutions == 0 && deletions == 0 && insertions == 0 ? 0 : 1
    }
    return Double(substitutions + deletions + insertions)
      / Double(referenceUnits)
  }

  public func adding(_ other: EditCounts) -> EditCounts {
    EditCounts(
      substitutions: substitutions + other.substitutions,
      deletions: deletions + other.deletions,
      insertions: insertions + other.insertions,
      referenceUnits: referenceUnits + other.referenceUnits
    )
  }
}
