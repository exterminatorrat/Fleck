import Foundation

public enum TranscriptMetrics {
  private static let englishLocale = Locale(identifier: "en_US_POSIX")

  public static func englishWordErrorRate(
    reference: String,
    hypothesis: String
  ) -> EditCounts {
    editCounts(
      reference: englishWords(reference),
      hypothesis: englishWords(hypothesis)
    )
  }

  public static func mandarinCharacterErrorRate(
    reference: String,
    hypothesis: String
  ) -> EditCounts {
    editCounts(
      reference: mandarinCharacters(reference),
      hypothesis: mandarinCharacters(hypothesis)
    )
  }

  public static func percentile(
    _ percentile: Double,
    values: [Double]
  ) -> Double? {
    guard percentile.isFinite, (0...100).contains(percentile), !values.isEmpty,
      values.allSatisfy(\.isFinite)
    else {
      return nil
    }
    let sorted = values.sorted()
    let nearestRank = max(
      1,
      Int(ceil(percentile / 100 * Double(sorted.count)))
    )
    return sorted[nearestRank - 1]
  }

  public static func englishWords(_ text: String) -> [String] {
    let normalized = text.precomposedStringWithCompatibilityMapping
    var separated = ""
    for scalar in normalized.unicodeScalars {
      if CharacterSet.letters.contains(scalar)
        || CharacterSet.decimalDigits.contains(scalar)
        || scalar.value == 0x27
      {
        separated.unicodeScalars.append(scalar)
      } else {
        separated.append(" ")
      }
    }
    return separated.split(whereSeparator: \.isWhitespace).map {
      String($0).lowercased(with: englishLocale)
    }
  }

  public static func mandarinCharacters(_ text: String) -> [Character] {
    let normalized = text.precomposedStringWithCompatibilityMapping
    return normalized.filter { character in
      !character.unicodeScalars.contains { scalar in
        CharacterSet.whitespacesAndNewlines.contains(scalar)
          || CharacterSet.punctuationCharacters.contains(scalar)
      }
    }.map { $0 }
  }

  public static func protectedDeveloperTerms(_ text: String) -> [String] {
    let candidates = text.split { character in
      !character.unicodeScalars.allSatisfy { scalar in
        CharacterSet.letters.contains(scalar)
          || CharacterSet.decimalDigits.contains(scalar)
          || scalar.value == 0x5F
      }
    }.map(String.init)

    return candidates.filter { candidate in
      let characters = Array(candidate)
      guard characters.count > 1 else { return false }
      let letterCount = characters.filter { $0.isLetter }.count
      let allUppercase = letterCount >= 2
        && characters.filter(\.isLetter).allSatisfy(\.isUppercase)
      let hasCaseTransition = zip(
        characters.dropLast(),
        characters.dropFirst()
      ).contains { previous, current in
        previous.isLowercase && current.isUppercase
      }
      return candidate.contains("_") || allUppercase || hasCaseTransition
    }
  }

  private static func editCounts<T: Equatable>(
    reference: [T],
    hypothesis: [T]
  ) -> EditCounts {
    var costs = Array(
      repeating: Array(repeating: 0, count: hypothesis.count + 1),
      count: reference.count + 1
    )
    for row in 0...reference.count { costs[row][0] = row }
    for column in 0...hypothesis.count { costs[0][column] = column }

    if !reference.isEmpty && !hypothesis.isEmpty {
      for row in 1...reference.count {
        for column in 1...hypothesis.count {
          let substitutionCost = reference[row - 1] == hypothesis[column - 1]
            ? 0
            : 1
          costs[row][column] = min(
            costs[row - 1][column - 1] + substitutionCost,
            costs[row - 1][column] + 1,
            costs[row][column - 1] + 1
          )
        }
      }
    }

    var row = reference.count
    var column = hypothesis.count
    var substitutions = 0
    var deletions = 0
    var insertions = 0

    while row > 0 || column > 0 {
      if row > 0, column > 0,
        reference[row - 1] == hypothesis[column - 1],
        costs[row][column] == costs[row - 1][column - 1]
      {
        row -= 1
        column -= 1
      } else if row > 0, column > 0,
        costs[row][column] == costs[row - 1][column - 1] + 1
      {
        substitutions += 1
        row -= 1
        column -= 1
      } else if row > 0,
        costs[row][column] == costs[row - 1][column] + 1
      {
        deletions += 1
        row -= 1
      } else {
        insertions += 1
        column -= 1
      }
    }

    return EditCounts(
      substitutions: substitutions,
      deletions: deletions,
      insertions: insertions,
      referenceUnits: reference.count
    )
  }
}

public enum TranscriptMetricsVersion {
  public static let schemaVersion = 1
}
