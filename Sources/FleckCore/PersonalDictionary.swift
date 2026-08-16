import Foundation

public enum PersonalDictionaryOrigin: String, Codable, Sendable {
  case manual
  case suggested
}

public struct PersonalDictionaryUsage: Codable, Equatable, Sendable {
  public static let maximumUseCount = 1_000_000

  public var useCount: Int
  public var lastUsedAt: Date?

  public init(useCount: Int = 0, lastUsedAt: Date? = nil) {
    self.useCount = useCount
    self.lastUsedAt = lastUsedAt
  }
}

public enum PersonalDictionaryValidationCode: String, Codable, Equatable, Sendable {
  case blankPreferredForm = "preferredForm.blank"
  case blankAlias = "aliases.blank"
  case duplicateAlias = "aliases.duplicate"
  case blankLocaleIdentifier = "localeIdentifier.blank"
  case negativeUseCount = "usage.useCount.negative"
  case useCountExceedsMaximum = "usage.useCount.exceedsMaximum"
  case blankSuggestionPreferredForm = "suggestion.preferredForm.blank"
  case blankObservedForm = "suggestion.observedForms.blank"
  case duplicateObservedForm = "suggestion.observedForms.duplicate"
  case negativeObservationCount = "suggestion.observationCount.negative"
  case observationCountExceedsMaximum = "suggestion.observationCount.exceedsMaximum"
  case unsupportedSchemaVersion = "schemaVersion.unsupported"
  case duplicateEntryID = "entries.id.duplicate"
  case duplicateSuggestionID = "suggestions.id.duplicate"
}

public struct PersonalDictionaryValidationIssue: Equatable, Sendable, CustomStringConvertible {
  public let code: PersonalDictionaryValidationCode
  public let field: String

  public init(code: PersonalDictionaryValidationCode, field: String) {
    self.code = code
    self.field = field
  }

  public var description: String { code.rawValue }
}

public enum PersonalDictionaryValidationError: Error, Equatable, Sendable, CustomStringConvertible {
  case invalidEntry([PersonalDictionaryValidationCode])
  case invalidSuggestion([PersonalDictionaryValidationCode])
  case invalidSnapshot([PersonalDictionaryValidationCode])

  public var codes: [PersonalDictionaryValidationCode] {
    switch self {
    case .invalidEntry(let codes), .invalidSuggestion(let codes), .invalidSnapshot(let codes):
      return codes
    }
  }

  public var description: String {
    codes.map(\.rawValue).joined(separator: ",")
  }
}

public struct PersonalDictionaryEntry: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public var preferredForm: String
  public var aliases: [String]
  public var localeIdentifier: String
  public var isPriority: Bool
  public var isEnabled: Bool
  public var origin: PersonalDictionaryOrigin
  public var usage: PersonalDictionaryUsage

  public init(
    id: UUID = UUID(),
    preferredForm: String,
    aliases: [String] = [],
    localeIdentifier: String = "en-US",
    isPriority: Bool = false,
    isEnabled: Bool = true,
    origin: PersonalDictionaryOrigin = .manual,
    usage: PersonalDictionaryUsage = .init()
  ) {
    self.id = id
    self.preferredForm = preferredForm
    self.aliases = aliases
    self.localeIdentifier = localeIdentifier
    self.isPriority = isPriority
    self.isEnabled = isEnabled
    self.origin = origin
    self.usage = usage
  }

  public var validationIssues: [PersonalDictionaryValidationIssue] {
    var issues: [PersonalDictionaryValidationIssue] = []
    if preferredForm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      issues.append(.init(code: .blankPreferredForm, field: "preferredForm"))
    }
    var normalizedAliases = Set<String>()
    for alias in aliases {
      guard !alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        issues.append(.init(code: .blankAlias, field: "aliases"))
        continue
      }
      let normalized = PersonalDictionaryText.normalized(alias)
      if !normalizedAliases.insert(normalized).inserted {
        issues.append(.init(code: .duplicateAlias, field: "aliases"))
      }
    }
    if localeIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      issues.append(.init(code: .blankLocaleIdentifier, field: "localeIdentifier"))
    }
    if usage.useCount < 0 {
      issues.append(.init(code: .negativeUseCount, field: "usage.useCount"))
    } else if usage.useCount > PersonalDictionaryUsage.maximumUseCount {
      issues.append(.init(code: .useCountExceedsMaximum, field: "usage.useCount"))
    }
    return issues
  }

  public func validate() throws {
    let codes = validationIssues.map(\.code)
    guard codes.isEmpty else { throw PersonalDictionaryValidationError.invalidEntry(codes) }
  }
}

public struct PersonalDictionarySuggestion: Identifiable, Codable, Equatable, Sendable {
  public static let maximumObservationCount = PersonalDictionaryUsage.maximumUseCount

  public let id: UUID
  public var preferredForm: String
  public var observedForms: [String]
  public var localeIdentifier: String
  public var observationCount: Int
  public var lastObservedAt: Date

  public init(
    id: UUID = UUID(),
    preferredForm: String,
    observedForms: [String] = [],
    localeIdentifier: String = "en-US",
    observationCount: Int = 0,
    lastObservedAt: Date = Date()
  ) {
    self.id = id
    self.preferredForm = preferredForm
    self.observedForms = observedForms
    self.localeIdentifier = localeIdentifier
    self.observationCount = observationCount
    self.lastObservedAt = lastObservedAt
  }

  public var validationIssues: [PersonalDictionaryValidationIssue] {
    var issues: [PersonalDictionaryValidationIssue] = []
    if preferredForm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      issues.append(.init(code: .blankSuggestionPreferredForm, field: "preferredForm"))
    }
    var observedForms = Set<String>()
    for form in self.observedForms {
      guard !form.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        issues.append(.init(code: .blankObservedForm, field: "observedForms"))
        continue
      }
      if !observedForms.insert(PersonalDictionaryText.normalized(form)).inserted {
        issues.append(.init(code: .duplicateObservedForm, field: "observedForms"))
      }
    }
    if localeIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      issues.append(.init(code: .blankLocaleIdentifier, field: "localeIdentifier"))
    }
    if observationCount < 0 {
      issues.append(.init(code: .negativeObservationCount, field: "observationCount"))
    } else if observationCount > Self.maximumObservationCount {
      issues.append(.init(code: .observationCountExceedsMaximum, field: "observationCount"))
    }
    return issues
  }

  public func validate() throws {
    let codes = validationIssues.map(\.code)
    guard codes.isEmpty else {
      throw PersonalDictionaryValidationError.invalidSuggestion(codes)
    }
  }
}

public struct PersonalDictionarySnapshot: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public var schemaVersion: Int
  public var entries: [PersonalDictionaryEntry]
  public var suggestions: [PersonalDictionarySuggestion]

  public init(
    schemaVersion: Int = Self.currentSchemaVersion,
    entries: [PersonalDictionaryEntry] = [],
    suggestions: [PersonalDictionarySuggestion] = []
  ) {
    self.schemaVersion = schemaVersion
    self.entries = entries
    self.suggestions = suggestions
  }

  public var validationIssues: [PersonalDictionaryValidationIssue] {
    var issues: [PersonalDictionaryValidationIssue] = []
    if schemaVersion != Self.currentSchemaVersion {
      issues.append(.init(code: .unsupportedSchemaVersion, field: "schemaVersion"))
    }
    issues += entries.flatMap { entry in
      entry.validationIssues.map { .init(code: $0.code, field: "entries") }
    }
    var entryIDs = Set<UUID>()
    for entry in entries where !entryIDs.insert(entry.id).inserted {
      issues.append(.init(code: .duplicateEntryID, field: "entries.id"))
    }
    issues += suggestions.flatMap { suggestion in
      suggestion.validationIssues.map { .init(code: $0.code, field: "suggestions") }
    }
    var suggestionIDs = Set<UUID>()
    for suggestion in suggestions where !suggestionIDs.insert(suggestion.id).inserted {
      issues.append(.init(code: .duplicateSuggestionID, field: "suggestions.id"))
    }
    return issues
  }

  public func validate() throws {
    let codes = validationIssues.map(\.code)
    guard codes.isEmpty else { throw PersonalDictionaryValidationError.invalidSnapshot(codes) }
  }
}

enum PersonalDictionaryText {
  static let normalizationLocale = Locale(identifier: "en_US_POSIX")

  static func normalized(_ value: String) -> String {
    value.folding(options: [.caseInsensitive], locale: normalizationLocale)
  }

  static func stableStringLess(_ lhs: String, _ rhs: String) -> Bool {
    let left = Array(lhs.unicodeScalars)
    let right = Array(rhs.unicodeScalars)
    return left.lexicographicallyPrecedes(right) { $0.value < $1.value }
  }
}
