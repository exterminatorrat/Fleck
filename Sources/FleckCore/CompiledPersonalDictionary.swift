import CryptoKit
import Foundation

public struct CompiledPersonalDictionary: Equatable, Sendable {
  public struct RoutingLexiconRecord: Equatable, Sendable {
    public let exactForm: String
    public let canonicalClaim: String
    public let entryID: UUID

    public init(exactForm: String, canonicalClaim: String, entryID: UUID) {
      self.exactForm = exactForm
      self.canonicalClaim = canonicalClaim
      self.entryID = entryID
    }
  }

  public enum DiagnosticCode: String, Equatable, Sendable {
    case disabledEntry
    case unsupportedLocaleEntry
    case duplicatePreferredOwner
    case aliasPreferredCollision
    case ambiguousAlias
    case recognitionTruncated
  }

  public struct Diagnostic: Equatable, Sendable {
    public let code: DiagnosticCode
    public let count: Int

    public init(code: DiagnosticCode, count: Int) {
      self.code = code
      self.count = count
    }
  }

  public let revision: UInt64
  public let contentDigest: String
  public let localeIdentifier: String
  public let compilerPolicyRevision: Int
  public let recognitionStrings: [String]
  public let protectedLexicon: [String]
  public let routingLexicon: [RoutingLexiconRecord]
  public let diagnostics: [Diagnostic]

  let resolverRules: [ResolverRule]

  public static func compile(
    _ snapshot: PersonalDictionarySnapshotV2
  ) throws -> CompiledPersonalDictionary {
    guard snapshot.validationIssues.isEmpty else {
      throw PersonalDictionaryResolverError.invalidEntries
    }

    let disabledCount = snapshot.entries.count { !$0.isEnabled }
    let unsupportedLocaleCount = snapshot.entries.count { $0.localeIdentifier != locale }
    let effectiveEntries = snapshot.entries
      .filter { $0.isEnabled && $0.localeIdentifier == locale }
      .map(CompilerEntry.init)

    let preferredOwners = Dictionary(grouping: effectiveEntries, by: \.preferred.canonical)
    let duplicatePreferredKeys = Set(
      preferredOwners.compactMap { key, entries in entries.count > 1 ? key : nil }
    )
    let excludedEntryIDs = Set(
      effectiveEntries
        .filter { duplicatePreferredKeys.contains($0.preferred.canonical) }
        .map(\.id)
    )
    let remainingEntries = effectiveEntries.filter { !excludedEntryIDs.contains($0.id) }
    let uniquePreferredOwners = Dictionary(
      uniqueKeysWithValues: remainingEntries.map { ($0.preferred.canonical, $0.id) }
    )

    var aliasPreferredCollisionKeys = Set<String>()
    var aliasesAfterPreferredCollisions: [Claim] = []
    for entry in remainingEntries {
      for alias in entry.aliases {
        if let preferredOwner = uniquePreferredOwners[alias.canonical] {
          if preferredOwner != entry.id {
            aliasPreferredCollisionKeys.insert(alias.canonical)
          }
          continue
        }
        aliasesAfterPreferredCollisions.append(alias)
      }
    }

    let aliasOwners = Dictionary(grouping: aliasesAfterPreferredCollisions, by: \.canonical)
    let ambiguousAliasKeys = Set(
      aliasOwners.compactMap { key, claims in
        Set(claims.map(\.entryID)).count > 1 ? key : nil
      }
    )

    var safeClaimsByEntry: [UUID: [Claim]] = [:]
    for entry in remainingEntries {
      var claims = [entry.preferred]
      var seenClaims = Set([entry.preferred.canonical])
      claims += entry.aliases.sorted(by: claimLess).filter { alias in
        !aliasPreferredCollisionKeys.contains(alias.canonical)
          && !ambiguousAliasKeys.contains(alias.canonical)
          && seenClaims.insert(alias.canonical).inserted
      }
      safeClaimsByEntry[entry.id] = claims
    }

    let routingLexicon = safeClaimsByEntry.values
      .flatMap { $0 }
      .map {
        RoutingLexiconRecord(
          exactForm: $0.exact,
          canonicalClaim: $0.canonical,
          entryID: $0.entryID
        )
      }
      .sorted(by: routingLess)

    let protectedLexicon = remainingEntries
      .map(\.preferred)
      .sorted(by: claimLess)
      .map(\.exact)

    let rankedEntries = remainingEntries.sorted(by: entryRank)
    var allRecognitionStrings: [String] = []
    var seenRecognitionClaims = Set<String>()
    for entry in rankedEntries {
      let safeClaims = safeClaimsByEntry[entry.id] ?? []
      guard let preferred = safeClaims.first else { continue }
      let aliases = safeClaims.dropFirst().sorted(by: claimLess)
      for claim in [preferred] + aliases where seenRecognitionClaims.insert(claim.canonical).inserted {
        allRecognitionStrings.append(claim.exact)
      }
    }
    let recognitionStrings = Array(allRecognitionStrings.prefix(recognitionLimit))

    let blockerClaims = effectiveEntries
      .filter { excludedEntryIDs.contains($0.id) }
      .flatMap(\.aliases)
      + aliasesAfterPreferredCollisions.filter { ambiguousAliasKeys.contains($0.canonical) }
    let resolverRules = (
      safeClaimsByEntry.values.flatMap { claims in
        claims.map {
          ResolverRule(
            exactForm: $0.exact,
            canonicalClaim: $0.canonical,
            preferredForm: $0.preferredForm,
            entryID: $0.entryID,
            isBlocker: false
          )
        }
      }
      + deduplicatedBlockers(blockerClaims).map {
        ResolverRule(
          exactForm: $0.exact,
          canonicalClaim: $0.canonical,
          preferredForm: "",
          entryID: $0.entryID,
          isBlocker: true
        )
      }
    ).sorted(by: resolverRuleLess)

    var diagnosticCounts: [DiagnosticCode: Int] = [:]
    diagnosticCounts[.disabledEntry] = disabledCount
    diagnosticCounts[.unsupportedLocaleEntry] = unsupportedLocaleCount
    diagnosticCounts[.duplicatePreferredOwner] = duplicatePreferredKeys.count
    diagnosticCounts[.aliasPreferredCollision] = aliasPreferredCollisionKeys.count
    diagnosticCounts[.ambiguousAlias] = ambiguousAliasKeys.count
    diagnosticCounts[.recognitionTruncated] = allRecognitionStrings.count - recognitionStrings.count
    let diagnostics = diagnosticCounts
      .filter { $0.value > 0 }
      .map(Diagnostic.init)
      .sorted { stableLess($0.code.rawValue, $1.code.rawValue) }

    return CompiledPersonalDictionary(
      revision: snapshot.revision,
      contentDigest: digest(
        recognitionStrings: recognitionStrings,
        resolverRules: resolverRules.filter { !$0.isBlocker },
        protectedLexicon: protectedLexicon,
        routingLexicon: routingLexicon
      ),
      localeIdentifier: locale,
      compilerPolicyRevision: policyRevision,
      recognitionStrings: recognitionStrings,
      protectedLexicon: protectedLexicon,
      routingLexicon: routingLexicon,
      diagnostics: diagnostics,
      resolverRules: resolverRules
    )
  }

  private static let locale = "en-US"
  private static let policyRevision = 1
  private static let recognitionLimit = 100

  private static func deduplicatedBlockers(_ claims: [Claim]) -> [Claim] {
    var seen = Set<String>()
    return claims.sorted(by: claimLess).filter {
      seen.insert("\($0.canonical.utf8.count):\($0.canonical)\($0.exact.utf8.count):\($0.exact)").inserted
    }
  }

  private static func entryRank(_ lhs: CompilerEntry, _ rhs: CompilerEntry) -> Bool {
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
    if lhs.preferred.exact != rhs.preferred.exact {
      return stableLess(lhs.preferred.exact, rhs.preferred.exact)
    }
    return lhs.id.uuidString.lowercased() < rhs.id.uuidString.lowercased()
  }

  private static func claimLess(_ lhs: Claim, _ rhs: Claim) -> Bool {
    if lhs.canonical != rhs.canonical { return stableLess(lhs.canonical, rhs.canonical) }
    if lhs.exact != rhs.exact { return stableLess(lhs.exact, rhs.exact) }
    return lhs.entryID.uuidString.lowercased() < rhs.entryID.uuidString.lowercased()
  }

  private static func routingLess(
    _ lhs: RoutingLexiconRecord,
    _ rhs: RoutingLexiconRecord
  ) -> Bool {
    if lhs.canonicalClaim != rhs.canonicalClaim {
      return stableLess(lhs.canonicalClaim, rhs.canonicalClaim)
    }
    if lhs.exactForm != rhs.exactForm { return stableLess(lhs.exactForm, rhs.exactForm) }
    return lhs.entryID.uuidString.lowercased() < rhs.entryID.uuidString.lowercased()
  }

  private static func resolverRuleLess(_ lhs: ResolverRule, _ rhs: ResolverRule) -> Bool {
    let leftLength = lhs.exactForm.unicodeScalars.count
    let rightLength = rhs.exactForm.unicodeScalars.count
    if leftLength != rightLength { return leftLength > rightLength }
    if lhs.canonicalClaim != rhs.canonicalClaim {
      return stableLess(lhs.canonicalClaim, rhs.canonicalClaim)
    }
    if lhs.exactForm != rhs.exactForm { return stableLess(lhs.exactForm, rhs.exactForm) }
    return lhs.entryID.uuidString.lowercased() < rhs.entryID.uuidString.lowercased()
  }

  private static func stableLess(_ lhs: String, _ rhs: String) -> Bool {
    PersonalDictionaryText.stableStringLess(lhs, rhs)
  }

  private static func digest(
    recognitionStrings: [String],
    resolverRules: [ResolverRule],
    protectedLexicon: [String],
    routingLexicon: [RoutingLexiconRecord]
  ) -> String {
    var preimage = ""
    append("compilerPolicyRevision", String(policyRevision), to: &preimage)
    append("localeIdentifier", locale, to: &preimage)
    append("recognitionCount", String(recognitionStrings.count), to: &preimage)
    for value in recognitionStrings { append("recognition", value, to: &preimage) }
    append("resolverCount", String(resolverRules.count), to: &preimage)
    for rule in resolverRules {
      append("resolverExact", rule.exactForm, to: &preimage)
      append("resolverCanonical", rule.canonicalClaim, to: &preimage)
      append("resolverPreferred", rule.preferredForm, to: &preimage)
      append("resolverEntryID", rule.entryID.uuidString.lowercased(), to: &preimage)
      append("resolverBlocker", rule.isBlocker ? "1" : "0", to: &preimage)
    }
    append("protectedCount", String(protectedLexicon.count), to: &preimage)
    for value in protectedLexicon { append("protected", value, to: &preimage) }
    append("routingCount", String(routingLexicon.count), to: &preimage)
    for record in routingLexicon {
      append("routingExact", record.exactForm, to: &preimage)
      append("routingCanonical", record.canonicalClaim, to: &preimage)
      append("routingEntryID", record.entryID.uuidString.lowercased(), to: &preimage)
    }
    return SHA256.hash(data: Data(preimage.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
  }

  private static func append(_ label: String, _ value: String, to preimage: inout String) {
    preimage += "\(label.utf8.count):\(label)\(value.utf8.count):\(value)"
  }
}

extension CompiledPersonalDictionary {
  struct ResolverRule: Equatable, Sendable {
    let exactForm: String
    let canonicalClaim: String
    let preferredForm: String
    let entryID: UUID
    let isBlocker: Bool
  }

  private struct Claim {
    let exact: String
    let canonical: String
    let preferredForm: String
    let entryID: UUID
  }

  private struct CompilerEntry {
    let id: UUID
    let preferred: Claim
    let aliases: [Claim]
    let isPriority: Bool
    let usage: PersonalDictionaryUsage

    init(_ entry: PersonalDictionaryEntry) {
      let preferredForm = Self.exact(entry.preferredForm)
      id = entry.id
      preferred = Claim(
        exact: preferredForm,
        canonical: Self.canonical(preferredForm),
        preferredForm: preferredForm,
        entryID: entry.id
      )
      aliases = entry.aliases.map { alias in
        let exact = Self.exact(alias)
        return Claim(
          exact: exact,
          canonical: Self.canonical(exact),
          preferredForm: preferredForm,
          entryID: entry.id
        )
      }
      isPriority = entry.isPriority
      usage = entry.usage
    }

    private static func exact(_ value: String) -> String {
      value.precomposedStringWithCanonicalMapping
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func canonical(_ value: String) -> String {
      value.folding(
        options: [.caseInsensitive],
        locale: PersonalDictionaryText.normalizationLocale
      )
    }
  }
}
