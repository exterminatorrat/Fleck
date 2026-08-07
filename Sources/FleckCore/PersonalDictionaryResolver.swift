import Foundation

public enum PersonalDictionaryResolverError: Error, Equatable, Sendable {
  case invalidEntries
}

public struct PersonalDictionaryResolution: Equatable, Sendable {
  public let baseline: String
  public let protectedForms: [String]
  public let replacements: Int

  public init(baseline: String, protectedForms: [String], replacements: Int) {
    self.baseline = baseline
    self.protectedForms = protectedForms
    self.replacements = replacements
  }
}

public enum PersonalDictionaryResolver {
  public static func resolve(
    _ rawTranscript: String,
    entries: [PersonalDictionaryEntry]
  ) throws -> PersonalDictionaryResolution {
    guard !rawTranscript.isEmpty else {
      return PersonalDictionaryResolution(
        baseline: rawTranscript,
        protectedForms: [],
        replacements: 0
      )
    }

    var claims: [String: [AliasCandidate]] = [:]
    for entry in entries where entry.isEnabled {
      guard entry.validationIssues.isEmpty else {
        throw PersonalDictionaryResolverError.invalidEntries
      }
      for alias in entry.aliases {
        claims[PersonalDictionaryText.normalized(alias), default: []].append(
          AliasCandidate(
            alias: alias,
            normalized: PersonalDictionaryText.normalized(alias),
            preferredForm: entry.preferredForm,
            entryID: entry.id
          )
        )
      }
    }

    let candidates = claims.values
      .filter { $0.count == 1 }
      .compactMap(\.first)
      .sorted { lhs, rhs in
        let leftLength = lhs.alias.unicodeScalars.count
        let rightLength = rhs.alias.unicodeScalars.count
        if leftLength != rightLength { return leftLength > rightLength }
        if lhs.normalized != rhs.normalized {
          return PersonalDictionaryText.stableStringLess(lhs.normalized, rhs.normalized)
        }
        if lhs.alias != rhs.alias {
          return PersonalDictionaryText.stableStringLess(lhs.alias, rhs.alias)
        }
        return lhs.entryID.uuidString < rhs.entryID.uuidString
      }

    guard !candidates.isEmpty else {
      return PersonalDictionaryResolution(
        baseline: rawTranscript,
        protectedForms: [],
        replacements: 0
      )
    }

    var baseline = String()
    baseline.reserveCapacity(rawTranscript.utf8.count)
    var protectedForms: [String] = []
    var protectedSet = Set<String>()
    var replacements = 0
    var index = rawTranscript.startIndex
    var copiedThrough = rawTranscript.startIndex

    while index < rawTranscript.endIndex {
      guard let match = match(
        in: rawTranscript,
        at: index,
        candidates: candidates
      ) else {
        index = rawTranscript.index(after: index)
        continue
      }

      baseline += rawTranscript[copiedThrough..<match.range.lowerBound]
      baseline += match.candidate.preferredForm
      copiedThrough = match.range.upperBound
      index = match.range.upperBound
      replacements += 1
      if protectedSet.insert(match.candidate.preferredForm).inserted {
        protectedForms.append(match.candidate.preferredForm)
      }
    }

    baseline += rawTranscript[copiedThrough..<rawTranscript.endIndex]
    if replacements == 0 {
      baseline = rawTranscript
    }
    return PersonalDictionaryResolution(
      baseline: baseline,
      protectedForms: protectedForms,
      replacements: replacements
    )
  }

  public static func cleanupPreserves(
    _ protectedForms: [String],
    in candidate: String
  ) -> Bool {
    protectedForms.allSatisfy { form in
      guard !form.isEmpty else { return true }
      var start = candidate.startIndex
      while start < candidate.endIndex,
        let range = candidate.range(
          of: form,
          options: [],
          range: start..<candidate.endIndex,
          locale: nil
        )
      {
        if hasSafeBoundaries(in: candidate, range: range) { return true }
        guard range.upperBound < candidate.endIndex else { break }
        start = candidate.index(after: range.lowerBound)
      }
      return false
    }
  }

  public static func contextualStrings(
    entries: [PersonalDictionaryEntry],
    locale: Locale,
    limit: Int = 100
  ) -> [String] {
    guard limit > 0 else { return [] }
    let languageCode = Locale.Components(identifier: locale.identifier)
      .languageComponents
      .languageCode
    guard let languageCode else { return [] }

    let rankedEntries = entries
      .filter { entry in
        guard entry.isEnabled,
          !entry.preferredForm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }
        return Locale.Components(identifier: entry.localeIdentifier)
          .languageComponents
          .languageCode == languageCode
      }
      .sorted(by: rank)

    var result: [String] = []
    var seen = Set<String>()
    for entry in rankedEntries {
      let terms = [entry.preferredForm] + entry.aliases
      for term in terms where !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        guard seen.insert(term).inserted else { continue }
        result.append(term)
        if result.count == limit { return result }
      }
    }
    return result
  }

  private static func rank(
    _ lhs: PersonalDictionaryEntry,
    _ rhs: PersonalDictionaryEntry
  ) -> Bool {
    if lhs.isPriority != rhs.isPriority { return lhs.isPriority }
    if lhs.usage.useCount != rhs.usage.useCount {
      return lhs.usage.useCount > rhs.usage.useCount
    }
    switch (lhs.usage.lastUsedAt, rhs.usage.lastUsedAt) {
    case let (left?, right?) where left != right:
      return left > right
    case (nil, .some):
      return false
    case (.some, nil):
      return true
    default:
      break
    }
    if lhs.preferredForm != rhs.preferredForm {
      return PersonalDictionaryText.stableStringLess(lhs.preferredForm, rhs.preferredForm)
    }
    return lhs.id.uuidString < rhs.id.uuidString
  }

  private static func match(
    in text: String,
    at index: String.Index,
    candidates: [AliasCandidate]
  ) -> AliasMatch? {
    for candidate in candidates {
      guard let range = text.range(
        of: candidate.alias,
        options: [.caseInsensitive],
        range: index..<text.endIndex,
        locale: PersonalDictionaryText.normalizationLocale
      ), range.lowerBound == index,
        hasSafeBoundaries(in: text, range: range)
      else { continue }
      return AliasMatch(candidate: candidate, range: range)
    }
    return nil
  }

  private static func hasSafeBoundaries(
    in text: String,
    range: Range<String.Index>
  ) -> Bool {
    let first = text[range].first
    let last = text[range].last
    let before = range.lowerBound > text.startIndex
      ? text[text.index(before: range.lowerBound)]
      : nil
    let after = range.upperBound < text.endIndex
      ? text[range.upperBound...].first
      : nil
    if let before, let first, before.isWordCharacter && first.isWordCharacter {
      return false
    }
    if let after, let last, after.isWordCharacter && last.isWordCharacter {
      return false
    }
    return true
  }

  private struct AliasCandidate {
    let alias: String
    let normalized: String
    let preferredForm: String
    let entryID: UUID
  }

  private struct AliasMatch {
    let candidate: AliasCandidate
    let range: Range<String.Index>
  }
}

private extension Character {
  var isWordCharacter: Bool { isLetter || isNumber || self == "_" }
}
