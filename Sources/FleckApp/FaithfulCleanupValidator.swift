import Foundation
import FleckCore

enum CleanupEditOperation: Equatable, Sendable {
  case caseChange
  case punctuation
  case whitespace
  case deleteFiller(String)
  case deleteImmediateDuplicate([String])
  case selectExplicitCorrection(removed: [String], kept: [String])
  case formatList
}

enum CleanupValidationFailure: Error, Equatable, Sendable {
  case emptyCandidate
  case protectedContentChanged
  case lexicalInsertion
  case lexicalDeletion
  case lexicalSubstitution
  case reorderedContent
  case ambiguousCorrection
  case numberMeaningChanged
}

enum CleanupValidationDecision: Equatable, Sendable {
  case accepted(text: String, operations: [CleanupEditOperation])
  case rejected(CleanupValidationFailure)
}

struct FaithfulCleanupValidator: Sendable {
  init() {}

  func validate(
    candidate: String,
    against resolution: PersonalDictionaryResolution
  ) -> CleanupValidationDecision {
    guard !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return .rejected(.emptyCandidate)
    }

    let baselineLexemes = CleanupLexeme.scan(resolution.baseline)
    let candidateLexemes = CleanupLexeme.scan(candidate)
    let baselineValues = baselineLexemes.filter(\.isLexical).map(\.canonical)
    let candidateValues = candidateLexemes.filter(\.isLexical).map(\.canonical)
    let ordinalMarkerPairs = Self.pairedOrdinalMarkersAreOnlyDifference(
      baselineLexemes: baselineLexemes,
      candidateLexemes: candidateLexemes
    )

    guard Self.numberMeaningIsPreserved(
      baselineLexemes: baselineLexemes,
      candidateLexemes: candidateLexemes
    )
      || ordinalMarkerPairs != nil else {
      return .rejected(.numberMeaningChanged)
    }

    guard PersonalDictionaryResolver.cleanupPreserves(
      resolution.protectedForms,
      in: candidate
    ) else { return .rejected(.protectedContentChanged) }

    let baselineSpans = CleanupProtectedSpan.extract(
      from: resolution.baseline,
      protectedForms: resolution.protectedForms
    )
    let candidateSpans = CleanupProtectedSpan.extract(
      from: candidate,
      protectedForms: resolution.protectedForms
    )
    guard let comparableCandidateSpans = Self.reconcileCaseOnlyNameSpans(
      baseline: baselineSpans,
      candidate: candidateSpans,
      baselineLexemes: baselineLexemes,
      candidateLexemes: candidateLexemes,
      baselineValues: baselineValues,
      candidateValues: candidateValues
    ) else { return .rejected(.protectedContentChanged) }
    guard Self.protectedSpansMatch(
      baselineSpans,
      comparableCandidateSpans,
      ordinalMarkerPairs: ordinalMarkerPairs
    ) else { return .rejected(.protectedContentChanged) }

    if baselineValues == candidateValues {
      return .accepted(
        text: candidate,
        operations: Self.equalLexicalOperations(baselineLexemes, candidateLexemes)
      )
    }
    if let filler = Self.isolatedFillerRemoval(
      baselineLexemes, candidateLexemes, baselineValues, candidateValues, baselineSpans
    ) {
      return .accepted(text: candidate, operations: [.deleteFiller(filler)])
    }
    if let duplicate = Self.immediateDuplicateRemoval(
      baselineLexemes, candidateValues, baselineValues, baselineSpans
    ) {
      return .accepted(text: candidate, operations: [.deleteImmediateDuplicate(duplicate)])
    }
    if let correction = Self.explicitCorrection(
      baselineLexemes, candidateValues, baselineValues
    ) {
      return .accepted(
        text: candidate,
        operations: [.selectExplicitCorrection(
          removed: correction.removed,
          kept: correction.kept
        )]
      )
    }
    if Self.hasCorrectionMarker(baselineValues) {
      return .rejected(.ambiguousCorrection)
    }
    if let ordinalMarkerPairs,
       Self.isShortListFormatting(
         baselineLexemes,
         candidateLexemes,
         ordinalMarkerPairs: ordinalMarkerPairs
       ) {
      return .accepted(text: candidate, operations: [.formatList])
    }
    if candidateValues.count > baselineValues.count {
      return .rejected(.lexicalInsertion)
    }
    if candidateValues.count < baselineValues.count {
      return .rejected(.lexicalDeletion)
    }
    if candidateValues.sorted() == baselineValues.sorted() {
      return .rejected(.reorderedContent)
    }
    return .rejected(.lexicalSubstitution)
  }

  private static let fillerWords: Set<String> = ["um", "uh", "erm", "呃", "嗯"]
  private static let numberWords: Set<String> = [
    "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
    "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
    "seventeen", "eighteen", "nineteen", "twenty", "thirty", "forty", "fifty",
    "sixty", "seventy", "eighty", "ninety", "hundred", "thousand", "million", "billion",
    "trillion", "first", "second", "third", "fourth", "fifth", "sixth", "seventh",
    "eighth", "ninth", "tenth", "eleventh", "twelfth", "thirteenth", "fourteenth",
    "fifteenth", "sixteenth", "seventeenth", "eighteenth", "nineteenth", "twentieth",
    "thirtieth", "fortieth", "fiftieth", "sixtieth", "seventieth", "eightieth",
    "ninetieth", "hundredth", "thousandth", "millionth", "billionth", "trillionth"
  ]
  private static let quantityWords: Set<String> = [
    "half", "halves", "quarter", "quarters", "thirds", "fourths", "fifths",
    "eighths", "tenths", "fraction", "fractions", "decimal", "decimals",
    "percent", "percentage", "percentages", "currency", "currencies", "cent",
    "cents", "dollar", "dollars", "euro", "euros",
    "yen", "pound", "pounds", "yuan", "dozen", "dozens", "pair", "pairs",
    "gram", "grams", "kilogram", "kilograms", "meter", "meters", "metre",
    "metres", "kilometer", "kilometers", "kilometre", "kilometres", "mile",
    "miles", "inch", "inches", "foot", "feet", "yard", "yards", "liter",
    "liters", "litre", "litres", "hour", "hours", "minute", "minutes",
    "second", "seconds", "day", "days", "week", "weeks", "month", "months",
    "year", "years"
  ]
  private static let numericLookingRoots: Set<String> = [
    "hundred", "thousand", "million", "billion", "trillion", "percent",
    "fraction", "decimal", "half", "quarter", "cent", "dollar", "euro",
    "currency", "yen", "pound", "yuan", "dozen", "gram", "kilo", "meter", "metre",
    "liter", "litre", "mile", "inch", "foot", "yard"
  ]
  private static let numericLookingSuffixes: [String] = ["ish", "like"]
  private static let correctionMarkers: Set<String> = ["actually", "sorry", "no"]
  private static let sentenceTerminalPunctuation: Set<String> = [
    ".", "!", "?", "。", "！", "？"
  ]

  private enum NumberClassification: Equatable {
    case none
    case digit(String)
    case digitOrdinal(String)
    case word(String)
    case quantity(String)
    case ambiguous
  }

  private struct PairedOrdinalMarkerIndices: Equatable {
    let baselineRawRanges: [Range<Int>]
    let candidateRawRanges: [Range<Int>]
    let candidateNumberRawRanges: [Range<Int>]
  }

  private struct NumericRawContext: Equatable {
    let detachedLeadingContext: [String]
    let detachedTrailingContext: [String]

    static let none = Self(
      detachedLeadingContext: [],
      detachedTrailingContext: []
    )
  }

  private struct NumberSemanticSignature: Equatable {
    let classification: NumberClassification
    let rawContext: NumericRawContext
  }

  private struct NumberSignature: Equatable {
    let rawRange: Range<Int>
    let classification: NumberClassification
    let rawContext: NumericRawContext

    init(
      rawRange: Range<Int>,
      classification: NumberClassification,
      rawContext: NumericRawContext = .none
    ) {
      self.rawRange = rawRange
      self.classification = classification
      self.rawContext = rawContext
    }

    var semantic: NumberSemanticSignature {
      .init(classification: classification, rawContext: rawContext)
    }
  }

  private static let ordinalMarkerNumbers: [String: Int] = [
    "first": 1,
    "second": 2,
    "third": 3,
    "fourth": 4,
    "fifth": 5
  ]

  private static func numberMeaningIsPreserved(
    baselineLexemes: [CleanupLexeme],
    candidateLexemes: [CleanupLexeme]
  ) -> Bool {
    let baseline = numberSignatures(from: baselineLexemes)
    let candidate = numberSignatures(from: candidateLexemes)
    guard !baseline.contains(where: { $0.classification == .ambiguous }),
          !candidate.contains(where: { $0.classification == .ambiguous }) else {
      return false
    }
    return baseline
      .filter { $0.classification != .none }
      .map(\.semantic)
      == candidate
      .filter { $0.classification != .none }
      .map(\.semantic)
  }

  private static func numberSignatures(from lexemes: [CleanupLexeme]) -> [NumberSignature] {
    var signatures: [NumberSignature] = []
    var consumedIndices = Set<Int>()
    var index = 0
    while index < lexemes.count {
      guard lexemes[index].kind == .number else {
        index += 1
        continue
      }

      let value = lexemes[index].canonical.lowercased()
      guard let rawContext = numericRawContext(at: index, in: lexemes) else {
        signatures.append(.init(
          rawRange: index..<(index + 1),
          classification: .ambiguous
        ))
        consumedIndices.insert(index)
        index += 1
        continue
      }
      if index + 1 < lexemes.count, lexemes[index + 1].kind == .word {
        let suffix = lexemes[index + 1].canonical.lowercased()
        if ["st", "nd", "rd", "th"].contains(suffix) {
          let range = index..<(index + 2)
          let classification: NumberClassification = validOrdinalSuffix(for: value, suffix: suffix)
            ? .digitOrdinal(value + suffix)
            : .ambiguous
          signatures.append(.init(
            rawRange: range,
            classification: classification,
            rawContext: rawContext
          ))
          consumedIndices.formUnion(range)
          index += 2
          continue
        }
        if unitWords.contains(suffix) {
          signatures.append(.init(
            rawRange: index..<(index + 2),
            classification: .quantity(value + suffix),
            rawContext: rawContext
          ))
          consumedIndices.formUnion(index..<(index + 2))
          index += 2
          continue
        }
        if suffix.hasPrefix("st") || suffix.hasPrefix("nd")
            || suffix.hasPrefix("rd") || suffix.hasPrefix("th") {
          signatures.append(.init(
            rawRange: index..<(index + 2),
            classification: .ambiguous,
            rawContext: rawContext
          ))
          consumedIndices.formUnion(index..<(index + 2))
          index += 2
          continue
        }
        signatures.append(.init(
          rawRange: index..<(index + 2),
          classification: .ambiguous,
          rawContext: rawContext
        ))
        consumedIndices.formUnion(index..<(index + 2))
        index += 2
        continue
      }

      if index + 2 < lexemes.count,
         lexemes[index + 1].kind == .whitespace,
         lexemes[index + 2].kind == .word,
         ["am", "pm"].contains(lexemes[index + 2].canonical.lowercased()),
         value.contains(":") {
        let time = value + lexemes[index + 2].canonical.lowercased()
        signatures.append(.init(
          rawRange: index..<(index + 3),
          classification: classifyNumber(time),
          rawContext: rawContext
        ))
        consumedIndices.formUnion(index..<(index + 3))
        index += 3
        continue
      }

      signatures.append(.init(
        rawRange: index..<(index + 1),
        classification: classifyNumber(value),
        rawContext: rawContext
      ))
      consumedIndices.insert(index)
      index += 1
    }

    for index in lexemes.indices where isAmbiguousNumericSpecialRun(lexemes[index]) {
      signatures.append(.init(
        rawRange: index..<(index + 1),
        classification: .ambiguous
      ))
    }

    for index in lexemes.indices where lexemes[index].kind == .word && !consumedIndices.contains(index) {
      let classification = classifyNumber(lexemes[index].canonical)
      if classification != .none {
        signatures.append(.init(
          rawRange: index..<(index + 1),
          classification: classification
        ))
      }
    }
    return signatures.sorted { $0.rawRange.lowerBound < $1.rawRange.lowerBound }
  }

  private static func isAmbiguousNumericSpecialRun(_ lexeme: CleanupLexeme) -> Bool {
    guard lexeme.kind == .code,
          lexeme.original.unicodeScalars.contains(where: CharacterSet.decimalDigits.contains)
    else { return false }
    return lexeme.original.contains("(") || lexeme.original.contains(")")
  }

  private static let unitWords: Set<String> = [
    "ms", "s", "sec", "secs", "min", "mins", "hour", "hours", "mm", "cm",
    "m", "km", "g", "kg", "mg", "oz", "lb", "lbs", "ml", "l", "gb", "mb",
    "tb", "c", "°c"
  ]

  private static func validOrdinalSuffix(for digits: String, suffix: String) -> Bool {
    guard let integer = Int(digits), ["st", "nd", "rd", "th"].contains(suffix) else {
      return false
    }
    let expected: String
    let lastTwo = integer % 100
    if (11...13).contains(lastTwo) {
      expected = "th"
    } else {
      switch integer % 10 {
      case 1: expected = "st"
      case 2: expected = "nd"
      case 3: expected = "rd"
      default: expected = "th"
      }
    }
    return suffix == expected
  }

  private static func numericRawContext(
    at index: Int,
    in lexemes: [CleanupLexeme]
  ) -> NumericRawContext? {
    let original = lexemes[index].original
    let openCount = original.filter { $0 == "(" }.count
    let closeCount = original.filter { $0 == ")" }.count
    guard openCount == closeCount else { return nil }
    if openCount > 0 {
      guard original.first == "(", original.last == ")" else { return nil }
    }

    func adjacentNonWhitespace(_ step: Int) -> CleanupLexeme? {
      var cursor = index + step
      while lexemes.indices.contains(cursor) {
        if lexemes[cursor].kind != .whitespace { return lexemes[cursor] }
        cursor += step
      }
      return nil
    }

    func rawContextRun(_ step: Int) -> [String] {
      var cursor = index + step
      var context: [String] = []
      while lexemes.indices.contains(cursor) {
        if lexemes[cursor].kind == .whitespace {
          cursor += step
          continue
        }
        guard isNumericContextPunctuation(lexemes[cursor]) else { break }
        context.append(lexemes[cursor].original)
        cursor += step
      }
      return step < 0 ? Array(context.reversed()) : context
    }

    let previous = adjacentNonWhitespace(-1)
    let next = adjacentNonWhitespace(1)
    if let previous,
       ["(", ")"].contains(previous.original),
       !(openCount > 0 && closeCount > 0) {
      return nil
    }
    if let next {
      if ["(", ")"].contains(next.original),
         !(openCount > 0 && closeCount > 0) {
        return nil
      }
      if ["/", ":", "%"].contains(next.original) { return nil }
      if original.hasSuffix("%") && next.original == "%" { return nil }
    }
    let detachedLeadingContext = rawContextRun(-1)
    let detachedTrailingContext = rawContextRun(1)
    guard detachedTrailingContext.isEmpty else {
      return nil
    }
    let hasAffix = detachedLeadingContext.contains { value in
      guard value.count == 1, let character = value.first else { return false }
      return isNumericSign(character) || isCurrencySymbol(character)
    }
    let hasSeparator = detachedLeadingContext.contains {
      [":", "/", "%"].contains($0)
    }
    guard !(hasAffix && hasSeparator) else { return nil }
    return .init(
      detachedLeadingContext: detachedLeadingContext,
      detachedTrailingContext: detachedTrailingContext
    )
  }

  private static func isNumericContextPunctuation(_ lexeme: CleanupLexeme) -> Bool {
    isNumericAffixPunctuation(lexeme)
      || (lexeme.kind == .punctuation
        && [":", "/", "%"].contains(lexeme.original))
  }

  private static func isNumericAffixPunctuation(_ lexeme: CleanupLexeme) -> Bool {
    guard lexeme.kind == .punctuation,
          lexeme.original.count == 1,
          let character = lexeme.original.first else {
      return false
    }
    return isNumericSign(character) || isCurrencySymbol(character)
  }

  private static func isNumericSign(_ character: Character) -> Bool {
    character == "+" || character == "-" || character == "−"
  }

  private static func isCurrencySymbol(_ character: Character) -> Bool {
    character.unicodeScalars.contains {
      $0.properties.generalCategory == .currencySymbol
    }
  }

  private static func parseScannerNumericForm(
    _ canonical: String
  ) -> NumberClassification? {
    let characters = Array(canonical)
    guard !characters.isEmpty else { return nil }
    var index = 0
    let parenthesized = characters[index] == "("
    if parenthesized { index += 1 }
    if characters.indices.contains(index), isNumericSign(characters[index]) {
      index += 1
    }
    if characters.indices.contains(index), isCurrencySymbol(characters[index]) {
      index += 1
    }
    if characters.indices.contains(index), isNumericSign(characters[index]) {
      index += 1
    }

    let coreStart = index
    guard characters.indices.contains(index), characters[index].isNumber else {
      return nil
    }
    while index < characters.count {
      if characters[index].isNumber {
        index += 1
        continue
      }
      let separator = characters[index]
      guard [".", "-", "/", ":"].contains(separator),
            index + 1 < characters.count,
            characters[index + 1].isNumber else {
        break
      }
      index += 1
    }
    let core = String(characters[coreStart..<index])
    if index < characters.count,
       characters[index] == "%" || isCurrencySymbol(characters[index]) {
      index += 1
    }

    var meridiem: String?
    if parenthesized {
      guard index < characters.count, characters[index] == ")" else {
        return nil
      }
      index += 1
    } else if index + 1 < characters.count,
              (characters[index] == "a" || characters[index] == "p"),
              characters[index + 1] == "m" {
      meridiem = String(characters[index...(index + 1)]).lowercased()
      index += 2
    }

    guard index == characters.count,
          isSupportedNumericCore(core, meridiem: meridiem) else {
      return nil
    }
    return .digit(canonical)
  }

  private static func isSupportedNumericCore(
    _ core: String,
    meridiem: String?
  ) -> Bool {
    if core.range(of: #"^\d+/\d+$"#, options: .regularExpression) != nil {
      let parts = core.split(separator: "/")
      guard meridiem == nil,
            parts.count == 2,
            let denominator = Int(parts[1]),
            denominator > 0 else {
        return false
      }
      return true
    }

    if core.range(of: #"^\d+(?:\.\d+)?$"#, options: .regularExpression) != nil {
      guard meridiem != nil else { return true }
      guard let hour = Int(core) else { return false }
      return (1...12).contains(hour)
        && core.range(of: #"^\d{1,2}$"#, options: .regularExpression) != nil
    }

    guard core.range(of: #"^\d{1,2}:\d{2}$"#, options: .regularExpression) != nil else {
      return false
    }
    let parts = core.split(separator: ":")
    guard parts.count == 2,
          let hour = Int(parts[0]),
          let minute = Int(parts[1]),
          (meridiem == nil ? (0...23).contains(hour) : (1...12).contains(hour)),
          (0...59).contains(minute) else {
      return false
    }
    return true
  }

  private static func classifyNumber(_ value: String) -> NumberClassification {
    let canonical = value.lowercased()
    if numberWords.contains(canonical) {
      return .word(canonical)
    }
    if quantityWords.contains(canonical) {
      return .quantity(canonical)
    }
    if canonical.contains("-") {
      let parts = canonical.split(separator: "-").map(String.init)
      if parts.allSatisfy({ numberWords.contains($0) || quantityWords.contains($0) }) {
        return .word(canonical)
      }
      if parts.contains(where: { numberWords.contains($0) || quantityWords.contains($0) }) {
        return .ambiguous
      }
    }
    if canonical.range(of: #"^[0-9]+(?:st|nd|rd|th)$"#, options: .regularExpression) != nil {
      let suffix = String(canonical.suffix(2))
      let digits = String(canonical.dropLast(2))
      return validOrdinalSuffix(for: digits, suffix: suffix)
        ? .digitOrdinal(canonical)
        : .ambiguous
    }
    if let numeric = parseScannerNumericForm(canonical) {
      return numeric
    }
    if canonical.unicodeScalars.contains(where: CharacterSet.decimalDigits.contains) {
      return .ambiguous
    }
    if isBoundedNumericLookingForm(canonical) {
      return .ambiguous
    }
    return .none
  }

  private static func isBoundedNumericLookingForm(_ canonical: String) -> Bool {
    guard canonical.allSatisfy({ $0.isLetter }) else { return false }
    return numericLookingSuffixes.contains { suffix in
      guard canonical.hasSuffix(suffix) else { return false }
      let root = String(canonical.dropLast(suffix.count))
      return numericLookingRoots.contains(root)
    }
  }

  private static func pairedOrdinalMarkersAreOnlyDifference(
    baselineLexemes: [CleanupLexeme],
    candidateLexemes: [CleanupLexeme]
  ) -> PairedOrdinalMarkerIndices? {
    guard let markerRanges = validatedShortListMarkerRanges(
      baselineLexemes: baselineLexemes,
      candidateLexemes: candidateLexemes
    ) else {
      return nil
    }
    let baselineMarkers = markerRanges.baselineRawRanges
    let candidateMarkers = markerRanges.candidateRawRanges
    guard baselineMarkers.count >= 2,
          baselineMarkers.count == candidateMarkers.count else {
      return nil
    }
    guard zip(baselineMarkers, candidateMarkers).enumerated().allSatisfy({ offset, pair in
      guard let baselineNumber = ordinalMarkerNumbers[
              baselineLexemes[pair.0.lowerBound].canonical
            ],
            let candidateNumber = isNumericListMarker(
              candidateLexemes[pair.1.lowerBound].canonical
            ) else {
        return false
      }
      return baselineNumber == offset + 1 && candidateNumber == offset + 1
    }) else {
      return nil
    }
    let baselineRemainder = removingRawRanges(baselineMarkers, from: baselineLexemes)
    let candidateRemainder = removingRawRanges(candidateMarkers, from: candidateLexemes)
    guard numberMeaningIsPreserved(
      baselineLexemes: baselineRemainder,
      candidateLexemes: candidateRemainder
    ) else {
      return nil
    }
    return .init(
      baselineRawRanges: baselineMarkers,
      candidateRawRanges: candidateMarkers,
      candidateNumberRawRanges: markerRanges.candidateNumberRawRanges
    )
  }

  private static func removingRawRanges(
    _ ranges: [Range<Int>],
    from lexemes: [CleanupLexeme]
  ) -> [CleanupLexeme] {
    lexemes.enumerated()
      .filter { index, _ in !ranges.contains { $0.contains(index) } }
      .map(\.element)
  }

  private static func isNumericListMarker(_ value: String) -> Int? {
    guard let number = Int(value) else { return nil }
    return (1...5).contains(number) ? number : nil
  }

  private struct NameOccurrence: Hashable {
    let lexicalOrdinal: Int
    let canonical: String
  }

  private static func singleNameOccurrence(
    _ span: CleanupProtectedSpan,
    in lexemes: [CleanupLexeme]
  ) -> NameOccurrence? {
    guard span.category == .name,
          span.lexemeRange.count == 1,
          let index = span.lexemeRange.first,
          lexemes.indices.contains(index),
          lexemes[index].isLexical else { return nil }
    let lexicalOrdinal = lexemes[..<index].reduce(into: 0) { count, lexeme in
      if lexeme.isLexical { count += 1 }
    }
    return .init(
      lexicalOrdinal: lexicalOrdinal,
      canonical: lexemes[index].canonical
    )
  }

  private static func lexicalIndex(
    atOrdinal ordinal: Int,
    in lexemes: [CleanupLexeme]
  ) -> Int? {
    guard ordinal >= 0 else { return nil }
    var currentOrdinal = 0
    for index in lexemes.indices where lexemes[index].isLexical {
      if currentOrdinal == ordinal { return index }
      currentOrdinal += 1
    }
    return nil
  }

  private static func reconcileCaseOnlyNameSpans(
    baseline: [CleanupProtectedSpan],
    candidate: [CleanupProtectedSpan],
    baselineLexemes: [CleanupLexeme],
    candidateLexemes: [CleanupLexeme],
    baselineValues: [String],
    candidateValues: [String]
  ) -> [CleanupProtectedSpan]? {
    guard baselineValues == candidateValues else { return candidate }

    let baselineNames = Set(
      baseline.compactMap { singleNameOccurrence($0, in: baselineLexemes) }
    )
    let candidateNames = Set(
      candidate.compactMap { singleNameOccurrence($0, in: candidateLexemes) }
    )
    guard baselineNames.isSubset(of: candidateNames) else { return nil }

    return candidate.filter { span in
      guard let occurrence = singleNameOccurrence(span, in: candidateLexemes) else {
        return true
      }
      guard !baselineNames.contains(occurrence) else { return true }
      guard baselineValues.indices.contains(occurrence.lexicalOrdinal),
            candidateValues.indices.contains(occurrence.lexicalOrdinal),
            baselineValues[occurrence.lexicalOrdinal]
              == candidateValues[occurrence.lexicalOrdinal],
            candidateValues[occurrence.lexicalOrdinal] == occurrence.canonical else {
        return true
      }
      guard let baselineIndex = lexicalIndex(
              atOrdinal: occurrence.lexicalOrdinal,
              in: baselineLexemes
            ),
            let candidateIndex = span.lexemeRange.first,
            candidateLexemes.indices.contains(candidateIndex),
            baselineLexemes[baselineIndex].canonical == occurrence.canonical,
            baselineLexemes[baselineIndex].original
              != candidateLexemes[candidateIndex].original,
            baselineLexemes[baselineIndex].original.lowercased()
              == candidateLexemes[candidateIndex].original.lowercased() else {
        return true
      }
      return false
    }
  }

  private static func protectedSpansMatch(
    _ baseline: [CleanupProtectedSpan],
    _ candidate: [CleanupProtectedSpan],
    ordinalMarkerPairs: PairedOrdinalMarkerIndices?
  ) -> Bool {
    let exemptCandidateNumbers = ordinalMarkerPairs?.candidateNumberRawRanges ?? []
    let comparableCandidate = candidate.filter { span in
      guard span.category == .number else { return true }
      return !exemptCandidateNumbers.contains(span.lexemeRange)
    }
    let stableOrder: (CleanupProtectedSpan, CleanupProtectedSpan) -> Bool = { left, right in
      if left.category.rawValue != right.category.rawValue {
        return left.category.rawValue < right.category.rawValue
      }
      if left.lexemeRange.lowerBound != right.lexemeRange.lowerBound {
        return left.lexemeRange.lowerBound < right.lexemeRange.lowerBound
      }
      return left.lexemeRange.upperBound < right.lexemeRange.upperBound
    }
    let orderedBaseline = baseline.sorted(by: stableOrder)
    let orderedCandidate = comparableCandidate.sorted(by: stableOrder)
    guard orderedBaseline.count == orderedCandidate.count else { return false }
    return zip(orderedBaseline, orderedCandidate).allSatisfy { baselineSpan, candidateSpan in
      baselineSpan.category == candidateSpan.category
        && comparableProtectedLexemes(baselineSpan.canonicalLexemes)
          == comparableProtectedLexemes(candidateSpan.canonicalLexemes)
    }
  }

  private static func comparableProtectedLexemes(_ values: [String]) -> [String] {
    var comparable = values
    while let last = comparable.last, sentenceTerminalPunctuation.contains(last) {
      comparable.removeLast()
    }
    return comparable
  }

  private static func equalLexicalOperations(
    _ baseline: [CleanupLexeme],
    _ candidate: [CleanupLexeme]
  ) -> [CleanupEditOperation] {
    var operations: [CleanupEditOperation] = []
    let baselineLexical = baseline.filter(\.isLexical)
    let candidateLexical = candidate.filter(\.isLexical)
    if zip(baselineLexical, candidateLexical).contains(where: { left, right in
      left.kind == .word
        && left.canonical == right.canonical
        && left.original != right.original
        && left.original.lowercased() == right.original.lowercased()
    }) {
      operations.append(.caseChange)
    }
    if baseline.filter({ $0.kind == .punctuation }).map(\.original)
      != candidate.filter({ $0.kind == .punctuation }).map(\.original) {
      operations.append(.punctuation)
    }
    if baseline.filter({ $0.kind == .whitespace }).map(\.original)
      != candidate.filter({ $0.kind == .whitespace }).map(\.original) {
      operations.append(.whitespace)
    }
    return operations
  }

  private static func isolatedFillerRemoval(
    _ baseline: [CleanupLexeme],
    _ candidate: [CleanupLexeme],
    _ baselineValues: [String],
    _ candidateValues: [String],
    _ spans: [CleanupProtectedSpan]
  ) -> String? {
    guard candidateValues.count + 1 == baselineValues.count else { return nil }
    let lexicalIndices = baseline.indices.filter { baseline[$0].isLexical }
    var matches: [(ordinal: Int, value: String)] = []
    for ordinal in baselineValues.indices {
      guard fillerWords.contains(baselineValues[ordinal]) else { continue }
      var expected = baselineValues
      expected.remove(at: ordinal)
      guard expected == candidateValues,
            lexicalIndices.indices.contains(ordinal) else { continue }
      let rawIndex = lexicalIndices[ordinal]
      guard !spans.contains(where: { $0.lexemeRange.contains(rawIndex) }) else { continue }

      func isBoundaryOrPunctuation(_ step: Int) -> Bool {
        var cursor = rawIndex + step
        while baseline.indices.contains(cursor) {
          if baseline[cursor].kind == .whitespace {
            cursor += step
            continue
          }
          return baseline[cursor].kind == .punctuation
        }
        return true
      }

      guard isBoundaryOrPunctuation(-1), isBoundaryOrPunctuation(1) else { continue }
      matches.append((ordinal, baselineValues[ordinal]))
    }
    guard matches.count == 1 else { return nil }
    return matches[0].value
  }

  private static func immediateDuplicateRemoval(
    _ baseline: [CleanupLexeme],
    _ candidateValues: [String],
    _ baselineValues: [String],
    _ spans: [CleanupProtectedSpan]
  ) -> [String]? {
    guard candidateValues.count + 1 == baselineValues.count else { return nil }
    let lexicalIndices = baseline.indices.filter { baseline[$0].isLexical }
    for ordinal in baselineValues.indices {
      guard ordinal + 1 < baselineValues.count,
            baselineValues[ordinal] == baselineValues[ordinal + 1],
            lexicalIndices.indices.contains(ordinal),
            lexicalIndices.indices.contains(ordinal + 1) else { continue }
      let firstIndex = lexicalIndices[ordinal]
      let secondIndex = lexicalIndices[ordinal + 1]
      guard baseline[firstIndex].kind != .number,
            baseline[secondIndex].kind != .number,
            !spans.contains(where: { $0.lexemeRange.contains(firstIndex) }),
            !spans.contains(where: { $0.lexemeRange.contains(secondIndex) }) else { continue }
      guard baseline[(firstIndex + 1)..<secondIndex].allSatisfy({ $0.kind == .whitespace }) else {
        continue
      }
      var expected = baselineValues
      expected.remove(at: ordinal)
      if expected == candidateValues {
        return [baselineValues[ordinal]]
      }
    }
    return nil
  }

  private static func explicitCorrection(
    _ baseline: [CleanupLexeme],
    _ candidateValues: [String],
    _ baselineValues: [String]
  ) -> (removed: [String], kept: [String])? {
    _ = baseline
    var matches: [(removed: [String], kept: [String])] = []
    for markerIndex in baselineValues.indices where correctionMarkers.contains(baselineValues[markerIndex]) {
      guard markerIndex + 1 < baselineValues.count else { continue }
      let kept = Array(baselineValues[(markerIndex + 1)...])
      guard !kept.isEmpty else { continue }
      for splitIndex in 0..<markerIndex {
        let prefix = Array(baselineValues[..<splitIndex])
        let removed = Array(baselineValues[splitIndex..<markerIndex])
        guard !removed.isEmpty,
              candidateValues == prefix + kept else { continue }
        matches.append((removed, kept))
      }
    }
    guard matches.count == 1 else { return nil }
    return matches[0]
  }

  private static func hasCorrectionMarker(_ values: [String]) -> Bool {
    values.contains { correctionMarkers.contains($0) }
  }

  private static func isShortListFormatting(
    _ baseline: [CleanupLexeme],
    _ candidate: [CleanupLexeme],
    ordinalMarkerPairs: PairedOrdinalMarkerIndices
  ) -> Bool {
    func startsItem(
      _ range: Range<Int>,
      in lexemes: [CleanupLexeme]
    ) -> Bool {
      var index = range.lowerBound - 1
      var hasLineBreak = false
      while index >= 0 {
        if lexemes[index].kind == .whitespace {
          hasLineBreak = hasLineBreak
            || lexemes[index].original.contains("\n")
            || lexemes[index].original.contains("\r")
          index -= 1
          continue
        }
        return hasLineBreak || lexemes[index].kind == .punctuation
      }
      return true
    }

    guard ordinalMarkerPairs.candidateRawRanges.allSatisfy({
      startsItem($0, in: candidate)
    }) else {
      return false
    }

    let baselineRemainder = removingRawRanges(
      ordinalMarkerPairs.baselineRawRanges,
      from: baseline
    )
    let candidateRemainder = removingRawRanges(
      ordinalMarkerPairs.candidateRawRanges,
      from: candidate
    )
    return baselineRemainder.filter(\.isLexical).map(\.canonical)
      == candidateRemainder.filter(\.isLexical).map(\.canonical)
  }

  private static func validatedShortListMarkerRanges(
    baselineLexemes: [CleanupLexeme],
    candidateLexemes: [CleanupLexeme]
  ) -> (
    baselineRawRanges: [Range<Int>],
    candidateRawRanges: [Range<Int>],
    candidateNumberRawRanges: [Range<Int>]
  )? {
    let baseline = baselineLexemes.indices.compactMap { index -> Range<Int>? in
      guard baselineLexemes[index].kind == .word,
            ordinalMarkerNumbers[baselineLexemes[index].canonical] != nil else {
        return nil
      }
      return index..<(index + 1)
    }
    let candidate = candidateLexemes.indices.compactMap { index -> (Range<Int>, Range<Int>)? in
      guard candidateLexemes[index].kind == .number,
            isNumericListMarker(candidateLexemes[index].canonical) != nil,
            index + 1 < candidateLexemes.count,
            candidateLexemes[index + 1].original == "." else {
        return nil
      }
      return (index..<(index + 2), index..<(index + 1))
    }
    guard baseline.count == candidate.count, baseline.count >= 2 else { return nil }
    return (
      baselineRawRanges: baseline,
      candidateRawRanges: candidate.map(\.0),
      candidateNumberRawRanges: candidate.map(\.1)
    )
  }
}
