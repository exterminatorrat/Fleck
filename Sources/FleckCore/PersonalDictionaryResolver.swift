import Foundation

public enum PersonalDictionaryResolverError: Error, Equatable, Sendable {
  case invalidEntries
}

public struct PersonalDictionaryResolution: Equatable, Sendable {
  public let baseline: String
  public let protectedForms: [String]
  public let replacements: Int
  public let dictionaryRevision: UInt64?
  public let dictionaryContentDigest: String?
  public let appliedEntryIDs: [UUID]

  public init(
    baseline: String,
    protectedForms: [String],
    replacements: Int,
    dictionaryRevision: UInt64? = nil,
    dictionaryContentDigest: String? = nil,
    appliedEntryIDs: [UUID] = []
  ) {
    self.baseline = baseline
    self.protectedForms = protectedForms
    self.replacements = replacements
    self.dictionaryRevision = dictionaryRevision
    self.dictionaryContentDigest = dictionaryContentDigest
    self.appliedEntryIDs = appliedEntryIDs
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
    var preferredForms = Set<String>()
    for entry in entries where entry.isEnabled {
      guard entry.validationIssues.isEmpty else {
        throw PersonalDictionaryResolverError.invalidEntries
      }
      preferredForms.insert(entry.preferredForm)
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
      .flatMap { claim in
        claim.map { candidate in
          var candidate = candidate
          candidate.isAmbiguous = claim.count > 1
          return candidate
        }
      }
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

    return resolve(
      rawTranscript,
      candidates: candidates,
      preferredForms: preferredForms,
      dictionaryRevision: nil,
      dictionaryContentDigest: nil
    )
  }

  public static func resolve(
    _ rawTranscript: String,
    compiled: CompiledPersonalDictionary
  ) -> PersonalDictionaryResolution {
    let candidates = compiled.resolverRules.map { rule in
      AliasCandidate(
        alias: rule.exactForm,
        normalized: rule.canonicalClaim,
        preferredForm: rule.preferredForm,
        entryID: rule.entryID,
        isAmbiguous: rule.isBlocker
      )
    }
    return resolve(
      rawTranscript,
      candidates: candidates,
      preferredForms: Set(compiled.protectedLexicon),
      dictionaryRevision: compiled.revision,
      dictionaryContentDigest: compiled.contentDigest
    )
  }

  private static func resolve(
    _ rawTranscript: String,
    candidates: [AliasCandidate],
    preferredForms: Set<String>,
    dictionaryRevision: UInt64?,
    dictionaryContentDigest: String?
  ) -> PersonalDictionaryResolution {
    guard !rawTranscript.isEmpty else {
      return PersonalDictionaryResolution(
        baseline: rawTranscript,
        protectedForms: [],
        replacements: 0,
        dictionaryRevision: dictionaryRevision,
        dictionaryContentDigest: dictionaryContentDigest
      )
    }

    var baseline = String()
    baseline.reserveCapacity(rawTranscript.utf8.count)
    var replacements = 0
    var appliedEntryIDs: [UUID] = []
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

      if match.candidate.isAmbiguous {
        index = match.range.upperBound
        continue
      }

      baseline += rawTranscript[copiedThrough..<match.range.lowerBound]
      baseline += match.candidate.preferredForm
      copiedThrough = match.range.upperBound
      index = match.range.upperBound
      replacements += 1
      appliedEntryIDs.append(match.candidate.entryID)
    }

    baseline += rawTranscript[copiedThrough..<rawTranscript.endIndex]
    if replacements == 0 {
      baseline = rawTranscript
    }
    let protectedForms = protectedOccurrences(
      in: baseline,
      preferredForms: preferredForms
    )
    return PersonalDictionaryResolution(
      baseline: baseline,
      protectedForms: protectedForms,
      replacements: replacements,
      dictionaryRevision: dictionaryRevision,
      dictionaryContentDigest: dictionaryContentDigest,
      appliedEntryIDs: appliedEntryIDs
    )
  }

  public static func cleanupPreserves(
    _ protectedForms: [String],
    in candidate: String
  ) -> Bool {
    var requiredCounts: [String: Int] = [:]
    for form in protectedForms where !form.isEmpty {
      requiredCounts[form, default: 0] += 1
    }
    for (form, count) in requiredCounts {
      guard safeOccurrenceCount(of: form, in: candidate) >= count else {
        return false
      }
    }
    return true
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

  private static func protectedOccurrences(
    in text: String,
    preferredForms: Set<String>
  ) -> [String] {
    let forms = preferredForms
      .filter { !$0.isEmpty }
      .sorted { lhs, rhs in
        if lhs.unicodeScalars.count != rhs.unicodeScalars.count {
          return lhs.unicodeScalars.count > rhs.unicodeScalars.count
        }
        return PersonalDictionaryText.stableStringLess(lhs, rhs)
      }
    var result: [String] = []
    var index = text.startIndex
    while index < text.endIndex {
      for form in forms {
        guard let range = text.range(
          of: form,
          options: [],
          range: index..<text.endIndex,
          locale: nil
        ), range.lowerBound == index,
          hasSafeBoundaries(in: text, range: range)
        else { continue }
        result.append(form)
      }
      index = text.index(after: index)
    }
    return result
  }

  private static func safeOccurrenceCount(of form: String, in text: String) -> Int {
    guard !form.isEmpty else { return 0 }
    var count = 0
    var start = text.startIndex
    while start < text.endIndex,
      let range = text.range(
        of: form,
        options: [],
        range: start..<text.endIndex,
        locale: nil
      )
    {
      if hasSafeBoundaries(in: text, range: range) {
        count += 1
      }
      guard range.upperBound < text.endIndex else { break }
      start = text.index(after: range.lowerBound)
    }
    return count
  }

  private struct AliasCandidate {
    let alias: String
    let normalized: String
    let preferredForm: String
    let entryID: UUID
    var isAmbiguous = false
  }

  private struct AliasMatch {
    let candidate: AliasCandidate
    let range: Range<String.Index>
  }
}

private extension Character {
  var isWordCharacter: Bool { isLetter || isNumber || self == "_" }
}
