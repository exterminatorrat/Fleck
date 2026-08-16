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

    let correction = Self.explicitCorrection(
      baselineLexemes,
      candidateValues,
      baselineValues
    )

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
    let filler = Self.isolatedFillerRemoval(
      baselineLexemes, candidateLexemes, baselineValues, candidateValues, baselineSpans
    )
    let duplicate = Self.immediateDuplicateRemoval(
      baselineLexemes, candidateValues, baselineValues, baselineSpans
    )
    let candidateToBaselineLexicalOrdinals = Self.candidateToBaselineLexicalOrdinals(
      baselineValues: baselineValues,
      candidateValues: candidateValues,
      baselineLexemes: baselineLexemes,
      candidateLexemes: candidateLexemes,
      ordinalMarkerPairs: ordinalMarkerPairs,
      correction: correction,
      allowSingleDeletion: filler != nil || duplicate != nil
    )
    guard let comparableCandidateSpans = Self.reconcileCaseOnlyNameSpans(
      baseline: baselineSpans,
      candidate: candidateSpans,
      baselineLexemes: baselineLexemes,
      candidateLexemes: candidateLexemes,
      ordinalMarkerPairs: ordinalMarkerPairs,
      candidateToBaselineLexicalOrdinals: candidateToBaselineLexicalOrdinals
    ) else { return .rejected(.protectedContentChanged) }
    guard Self.protectedSpansMatch(
      baselineSpans,
      comparableCandidateSpans,
      baselineLexemes: baselineLexemes,
      candidateLexemes: candidateLexemes,
      candidateToBaselineLexicalOrdinals: candidateToBaselineLexicalOrdinals,
      ordinalMarkerPairs: ordinalMarkerPairs,
      correction: correction
    ) else { return .rejected(.protectedContentChanged) }

    if baselineValues == candidateValues {
      return .accepted(
        text: candidate,
        operations: Self.equalLexicalOperations(baselineLexemes, candidateLexemes)
      )
    }
    if let filler {
      return .accepted(text: candidate, operations: [.deleteFiller(filler)])
    }
    if let duplicate {
      return .accepted(text: candidate, operations: [.deleteImmediateDuplicate(duplicate)])
    }
    if let correction {
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

  private struct ExplicitCorrection: Equatable {
    let removed: [String]
    let kept: [String]
    let markerCanonical: String
    let markerRawRange: Range<Int>
  }

  private struct FormattingLexeme: Equatable {
    let kind: CleanupLexemeKind
    let lexicalAnchor: Int
    let ordinalAtAnchor: Int
    let value: String
  }

  private struct FormattingCoordinate: Equatable {
    let lexicalAnchor: Int
    let ordinalAtAnchor: Int
    let value: String
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
            && hasCompleteDigitOrdinalToken(after: range, in: lexemes)
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
          let range = index..<(index + 2)
          signatures.append(.init(
            rawRange: range,
            classification: hasNumericPunctuationBridge(
              after: range.upperBound,
              in: lexemes
            ) ? .ambiguous : .quantity(value + suffix),
            rawContext: rawContext
          ))
          consumedIndices.formUnion(range)
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

      if let range = degreeUnitRange(at: index, in: lexemes) {
        let suffix = "°" + lexemes[range.upperBound - 1].canonical.lowercased()
        signatures.append(.init(
          rawRange: range,
          classification: hasNumericPunctuationBridge(
            after: range.upperBound,
            in: lexemes
          ) ? .ambiguous : .quantity(value + suffix),
          rawContext: rawContext
        ))
        consumedIndices.formUnion(range)
        index = range.upperBound
        continue
      }

      if index + 2 < lexemes.count,
         lexemes[index + 1].kind == .whitespace,
         lexemes[index + 2].kind == .word {
        let suffix = lexemes[index + 2].canonical.lowercased()
        if unitWords.contains(suffix) {
          let range = index..<(index + 3)
          signatures.append(.init(
            rawRange: range,
            classification: hasNumericPunctuationBridge(
              after: range.upperBound,
              in: lexemes
            ) ? .ambiguous : .quantity(value + suffix),
            rawContext: rawContext
          ))
          consumedIndices.formUnion(range)
          index += 3
          continue
        }
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
    return lexeme.original.contains {
      ["(", ")", "=", "_", "`"].contains(String($0))
    }
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

  private static func hasCompleteDigitOrdinalToken(
    after range: Range<Int>,
    in lexemes: [CleanupLexeme]
  ) -> Bool {
    guard lexemes.indices.contains(range.upperBound) else { return true }
    let next = lexemes[range.upperBound]
    guard next.kind != .whitespace else { return true }
    guard next.kind == .punctuation else { return false }
    guard sentenceTerminalPunctuation.contains(next.original)
      || [",", ";"].contains(next.original) else {
      return false
    }
    guard lexemes.indices.contains(range.upperBound + 1) else { return true }
    return lexemes[range.upperBound + 1].kind == .whitespace
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

    if index > 0, lexemes[index - 1].isLexical {
      return nil
    }
    if index > 0,
       lexemes[index - 1].kind != .whitespace,
       isNumericCodeBoundaryPunctuation(lexemes[index - 1]) {
      return nil
    }
    if index + 1 < lexemes.count,
       lexemes[index + 1].kind != .whitespace,
       isNumericCodeBoundaryPunctuation(lexemes[index + 1]) {
      return nil
    }
    if degreeUnitRange(at: index, in: lexemes) == nil,
       hasNumericPunctuationBridge(at: index, in: lexemes) {
      return nil
    }
    if hasUnsupportedNumericAffixRun(at: index, in: lexemes) {
      return nil
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

  private static func isNumericCodeBoundaryPunctuation(_ lexeme: CleanupLexeme) -> Bool {
    guard lexeme.kind == .punctuation, lexeme.original.count == 1 else { return false }
    return ["(", ")", "/", ":", "%", "=", "_", "`", "@", "#", "\\"].contains(lexeme.original)
  }

  private static func degreeUnitRange(
    at index: Int,
    in lexemes: [CleanupLexeme]
  ) -> Range<Int>? {
    let degreeIndex: Int
    if index + 1 < lexemes.count,
       lexemes[index + 1].kind == .punctuation,
       lexemes[index + 1].original == "°" {
      degreeIndex = index + 1
    } else if index + 2 < lexemes.count,
              lexemes[index + 1].kind == .whitespace,
              lexemes[index + 2].kind == .punctuation,
              lexemes[index + 2].original == "°" {
      degreeIndex = index + 2
    } else {
      return nil
    }
    guard lexemes.indices.contains(degreeIndex + 1),
          lexemes[degreeIndex + 1].kind == .word,
          unitWords.contains("°" + lexemes[degreeIndex + 1].canonical.lowercased()) else {
      return nil
    }
    return index..<(degreeIndex + 2)
  }

  private static func hasNumericPunctuationBridge(
    at index: Int,
    in lexemes: [CleanupLexeme]
  ) -> Bool {
    for step in [-1, 1] {
      var cursor = index + step
      var punctuationCount = 0
      while lexemes.indices.contains(cursor), lexemes[cursor].kind == .punctuation {
        punctuationCount += 1
        cursor += step
      }
      guard punctuationCount > 0,
            lexemes.indices.contains(cursor),
            lexemes[cursor].isLexical else { continue }
      return true
    }
    return false
  }

  private static func hasUnsupportedNumericAffixRun(
    at index: Int,
    in lexemes: [CleanupLexeme]
  ) -> Bool {
    for step in [-1, 1] {
      var cursor = index + step
      while lexemes.indices.contains(cursor), lexemes[cursor].kind == .whitespace {
        cursor += step
      }
      guard lexemes.indices.contains(cursor),
            lexemes[cursor].kind == .punctuation else { continue }
      if isNumericAffixPunctuation(lexemes[cursor]) { continue }

      var run: [CleanupLexeme] = []
      while lexemes.indices.contains(cursor),
            [.punctuation, .whitespace].contains(lexemes[cursor].kind) {
        if lexemes[cursor].kind == .punctuation {
          run.append(lexemes[cursor])
        }
        cursor += step
      }
      guard run.contains(where: isNumericAffixPunctuation) else { continue }
      if run.contains(where: { !isNumericContextPunctuation($0) }) {
        return true
      }
    }
    return false
  }

  private static func hasNumericPunctuationBridge(
    after index: Int,
    in lexemes: [CleanupLexeme]
  ) -> Bool {
    var cursor = index
    var punctuationCount = 0
    while lexemes.indices.contains(cursor), lexemes[cursor].kind == .punctuation {
      punctuationCount += 1
      cursor += 1
    }
    return punctuationCount > 0
      && lexemes.indices.contains(cursor)
      && lexemes[cursor].isLexical
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
    let baselineItems = listItemPayloads(baselineMarkers, in: baselineLexemes)
    let candidateItems = listItemPayloads(candidateMarkers, in: candidateLexemes)
    guard baselineItems.count == candidateItems.count,
          baselineItems.allSatisfy({ !$0.isEmpty }),
          candidateItems.allSatisfy({ !$0.isEmpty }),
          baselineItems == candidateItems else {
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

  private static func listItemPayloads(
    _ markerRanges: [Range<Int>],
    in lexemes: [CleanupLexeme]
  ) -> [[String]] {
    markerRanges.enumerated().map { offset, range in
      let end = offset + 1 < markerRanges.count
        ? markerRanges[offset + 1].lowerBound
        : lexemes.count
      return lexemes[range.upperBound..<end]
        .filter(\.isLexical)
        .map(\.canonical)
    }
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
    in lexemes: [CleanupLexeme],
    ignoring ignoredRawRanges: [Range<Int>] = []
  ) -> NameOccurrence? {
    guard span.category == .name,
          span.lexemeRange.count == 1,
          let index = span.lexemeRange.first,
          lexemes.indices.contains(index),
          lexemes[index].isLexical else { return nil }
    let lexicalOrdinal = lexemes[..<index].enumerated().reduce(into: 0) { count, pair in
      let (rawIndex, lexeme) = pair
      if lexeme.isLexical && !ignoredRawRanges.contains(where: { $0.contains(rawIndex) }) {
        count += 1
      }
    }
    return .init(
      lexicalOrdinal: lexicalOrdinal,
      canonical: lexemes[index].canonical
    )
  }

  private static func lexicalIndex(
    atOrdinal ordinal: Int,
    in lexemes: [CleanupLexeme],
    ignoring ignoredRawRanges: [Range<Int>] = []
  ) -> Int? {
    guard ordinal >= 0 else { return nil }
    var currentOrdinal = 0
    for index in lexemes.indices
      where lexemes[index].isLexical
        && !ignoredRawRanges.contains(where: { $0.contains(index) }) {
      if currentOrdinal == ordinal { return index }
      currentOrdinal += 1
    }
    return nil
  }

  private static func candidateToBaselineLexicalOrdinals(
    baselineValues: [String],
    candidateValues: [String],
    baselineLexemes: [CleanupLexeme],
    candidateLexemes: [CleanupLexeme],
    ordinalMarkerPairs: PairedOrdinalMarkerIndices?,
    correction: ExplicitCorrection?,
    allowSingleDeletion: Bool
  ) -> [Int]? {
    if let ordinalMarkerPairs {
      let normalizedBaselineValues = removingRawRanges(
        ordinalMarkerPairs.baselineRawRanges,
        from: baselineLexemes
      ).filter(\.isLexical).map(\.canonical)
      let normalizedCandidateValues = removingRawRanges(
        ordinalMarkerPairs.candidateRawRanges,
        from: candidateLexemes
      ).filter(\.isLexical).map(\.canonical)
      guard normalizedBaselineValues == normalizedCandidateValues else { return nil }
      return Array(normalizedCandidateValues.indices)
    }
    if baselineValues == candidateValues {
      return Array(candidateValues.indices)
    }
    if let correction {
      let prefixCount = baselineValues.count
        - correction.removed.count
        - correction.kept.count
        - 1
      guard prefixCount >= 0,
            prefixCount <= baselineValues.count,
            candidateValues == Array(baselineValues[..<prefixCount]) + correction.kept else {
        return nil
      }
      let tailStart = prefixCount + correction.removed.count + 1
      guard tailStart <= baselineValues.count,
            Array(baselineValues[tailStart..<baselineValues.count]) == correction.kept else {
        return nil
      }
      return candidateValues.indices.map { ordinal in
        ordinal < prefixCount ? ordinal : ordinal + correction.removed.count + 1
      }
    }
    guard allowSingleDeletion,
          candidateValues.count + 1 == baselineValues.count,
          let removedOrdinal = baselineValues.indices.first(where: { ordinal in
            var expected = baselineValues
            expected.remove(at: ordinal)
            return expected == candidateValues
          }) else {
      return nil
    }
    return candidateValues.indices.map { ordinal in
      ordinal < removedOrdinal ? ordinal : ordinal + 1
    }
  }

  private static func reconcileCaseOnlyNameSpans(
    baseline: [CleanupProtectedSpan],
    candidate: [CleanupProtectedSpan],
    baselineLexemes: [CleanupLexeme],
    candidateLexemes: [CleanupLexeme],
    ordinalMarkerPairs: PairedOrdinalMarkerIndices?,
    candidateToBaselineLexicalOrdinals: [Int]?
  ) -> [CleanupProtectedSpan]? {
    guard let candidateToBaselineLexicalOrdinals else { return candidate }
    let ignoredBaselineRawRanges = ordinalMarkerPairs?.baselineRawRanges ?? []
    let ignoredCandidateRawRanges = ordinalMarkerPairs?.candidateRawRanges ?? []
    let normalizedBaselineValues = removingRawRanges(
      ignoredBaselineRawRanges,
      from: baselineLexemes
    ).filter(\.isLexical).map(\.canonical)
    let normalizedCandidateValues = removingRawRanges(
      ignoredCandidateRawRanges,
      from: candidateLexemes
    ).filter(\.isLexical).map(\.canonical)

    let baselineNames = Set(
      baseline.compactMap {
        singleNameOccurrence(
          $0,
          in: baselineLexemes,
          ignoring: ignoredBaselineRawRanges
        )
      }
    )
    let candidateNames = Set(
      candidate.compactMap { span -> NameOccurrence? in
        guard let occurrence = singleNameOccurrence(
          span,
          in: candidateLexemes,
          ignoring: ignoredCandidateRawRanges
        ),
        candidateToBaselineLexicalOrdinals.indices.contains(occurrence.lexicalOrdinal) else {
          return nil
        }
        return .init(
          lexicalOrdinal: candidateToBaselineLexicalOrdinals[occurrence.lexicalOrdinal],
          canonical: occurrence.canonical
        )
      }
    )
    guard baselineNames.isSubset(of: candidateNames) else { return nil }

    return candidate.filter { span in
      guard let occurrence = singleNameOccurrence(
        span,
        in: candidateLexemes,
        ignoring: ignoredCandidateRawRanges
      ) else {
        return true
      }
      guard candidateToBaselineLexicalOrdinals.indices.contains(occurrence.lexicalOrdinal) else {
        return true
      }
      let baselineOrdinal = candidateToBaselineLexicalOrdinals[occurrence.lexicalOrdinal]
      guard !baselineNames.contains(.init(
        lexicalOrdinal: baselineOrdinal,
        canonical: occurrence.canonical
      )) else { return true }
      guard normalizedBaselineValues.indices.contains(baselineOrdinal),
            normalizedCandidateValues.indices.contains(occurrence.lexicalOrdinal),
            normalizedBaselineValues[baselineOrdinal]
              == normalizedCandidateValues[occurrence.lexicalOrdinal],
            normalizedCandidateValues[occurrence.lexicalOrdinal] == occurrence.canonical else {
        return true
      }
      guard let baselineIndex = lexicalIndex(
              atOrdinal: baselineOrdinal,
              in: baselineLexemes,
              ignoring: ignoredBaselineRawRanges
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
    baselineLexemes: [CleanupLexeme],
    candidateLexemes: [CleanupLexeme],
    candidateToBaselineLexicalOrdinals: [Int]?,
    ordinalMarkerPairs: PairedOrdinalMarkerIndices?,
    correction: ExplicitCorrection?
  ) -> Bool {
    let comparableBaseline = baseline.filter { span in
      guard let correction,
            correction.markerCanonical == "no" else { return true }
      return !(span.category == .negation && span.lexemeRange == correction.markerRawRange)
    }
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
    let orderedBaseline = comparableBaseline.sorted(by: stableOrder)
    let orderedCandidate = comparableCandidate.sorted(by: stableOrder)
    guard orderedBaseline.count == orderedCandidate.count else { return false }
    guard !orderedBaseline.isEmpty else { return true }
    guard let candidateToBaselineLexicalOrdinals else { return false }
    return zip(orderedBaseline, orderedCandidate).allSatisfy { baselineSpan, candidateSpan in
      guard baselineSpan.category == candidateSpan.category,
            protectedSpanLexemesMatch(baselineSpan, candidateSpan),
            let baselineOrdinal = protectedSpanLexicalOrdinal(
              baselineSpan,
              in: baselineLexemes,
              ignoring: ordinalMarkerPairs?.baselineRawRanges ?? []
            ),
            let candidateOrdinal = protectedSpanLexicalOrdinal(
              candidateSpan,
              in: candidateLexemes,
              ignoring: ordinalMarkerPairs?.candidateRawRanges ?? []
            ),
            candidateToBaselineLexicalOrdinals.indices.contains(candidateOrdinal) else {
        return false
      }
      return candidateToBaselineLexicalOrdinals[candidateOrdinal] == baselineOrdinal
    }
  }

  private static func protectedSpanLexicalOrdinal(
    _ span: CleanupProtectedSpan,
    in lexemes: [CleanupLexeme],
    ignoring ignoredRawRanges: [Range<Int>]
  ) -> Int? {
    guard let firstLexicalIndex = span.lexemeRange.first(where: { index in
      lexemes.indices.contains(index)
        && lexemes[index].isLexical
        && !ignoredRawRanges.contains(where: { $0.contains(index) })
    }) else { return nil }
    return lexemes[..<firstLexicalIndex].enumerated().reduce(into: 0) { count, pair in
      let (rawIndex, lexeme) = pair
      if lexeme.isLexical && !ignoredRawRanges.contains(where: { $0.contains(rawIndex) }) {
        count += 1
      }
    }
  }

  private static func protectedSpanLexemesMatch(
    _ baseline: CleanupProtectedSpan,
    _ candidate: CleanupProtectedSpan
  ) -> Bool {
    guard baseline.category == .command else {
      return baseline.canonicalLexemes == candidate.canonicalLexemes
    }
    if baseline.canonicalLexemes == candidate.canonicalLexemes { return true }
    guard let baselineLast = baseline.canonicalLexemes.last,
          !sentenceTerminalPunctuation.contains(baselineLast),
          candidate.canonicalLexemes.count == baseline.canonicalLexemes.count + 1,
          Array(candidate.canonicalLexemes.dropLast()) == baseline.canonicalLexemes,
          let candidateLast = candidate.canonicalLexemes.last,
          sentenceTerminalPunctuation.contains(candidateLast) else {
      return false
    }
    return true
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
    let baselineFormatting = formattingLexemes(baseline)
    let candidateFormatting = formattingLexemes(candidate)
    func formattingCounts(_ lexemes: [FormattingLexeme]) -> [Int: Int] {
      lexemes.reduce(into: [:]) { counts, lexeme in
        counts[lexeme.lexicalAnchor, default: 0] += 1
      }
    }
    let baselineCounts = formattingCounts(baselineFormatting)
    let candidateCounts = formattingCounts(candidateFormatting)
    let ordinalAnchors = Set(
      (Array(baselineCounts.keys) + Array(candidateCounts.keys)).filter { anchor in
        baselineCounts[anchor, default: 0] == candidateCounts[anchor, default: 0]
      }
    )
    let baselinePunctuation = formattingCoordinates(
      baselineFormatting,
      kind: .punctuation,
      ordinalAnchors: ordinalAnchors
    )
    let candidatePunctuation = formattingCoordinates(
      candidateFormatting,
      kind: .punctuation,
      ordinalAnchors: ordinalAnchors
    )
    let baselineWhitespace = formattingCoordinates(
      baselineFormatting,
      kind: .whitespace,
      ordinalAnchors: ordinalAnchors
    )
    let candidateWhitespace = formattingCoordinates(
      candidateFormatting,
      kind: .whitespace,
      ordinalAnchors: ordinalAnchors
    )
    if baselinePunctuation != candidatePunctuation {
      operations.append(.punctuation)
    }
    if baselineWhitespace != candidateWhitespace {
      operations.append(.whitespace)
    }
    return operations
  }

  private static func formattingLexemes(
    _ lexemes: [CleanupLexeme]
  ) -> [FormattingLexeme] {
    var lexicalAnchor = 0
    var ordinalByAnchor: [Int: Int] = [:]
    var result: [FormattingLexeme] = []
    for lexeme in lexemes {
      if lexeme.kind == .punctuation || lexeme.kind == .whitespace {
        let ordinalAtAnchor = ordinalByAnchor[lexicalAnchor, default: 0]
        result.append(.init(
          kind: lexeme.kind,
          lexicalAnchor: lexicalAnchor,
          ordinalAtAnchor: ordinalAtAnchor,
          value: lexeme.original
        ))
        ordinalByAnchor[lexicalAnchor] = ordinalAtAnchor + 1
      }
      if lexeme.isLexical { lexicalAnchor += 1 }
    }
    return result
  }

  private static func formattingCoordinates(
    _ lexemes: [FormattingLexeme],
    kind: CleanupLexemeKind,
    ordinalAnchors: Set<Int>
  ) -> [FormattingCoordinate] {
    lexemes.filter { $0.kind == kind }.map {
      .init(
        lexicalAnchor: $0.lexicalAnchor,
        ordinalAtAnchor: ordinalAnchors.contains($0.lexicalAnchor)
          ? $0.ordinalAtAnchor
          : 0,
        value: $0.value
      )
    }
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
  ) -> ExplicitCorrection? {
    let lexicalIndices = baseline.indices.filter { baseline[$0].isLexical }
    let correctionDelimiters: Set<String> = [",", ";", ":", "-", "–", "—"]

    func nearestNonWhitespace(_ index: Int, step: Int) -> Int? {
      var cursor = index + step
      while baseline.indices.contains(cursor) {
        if baseline[cursor].kind != .whitespace { return cursor }
        cursor += step
      }
      return nil
    }

    var matches: [ExplicitCorrection] = []
    for markerIndex in baselineValues.indices where correctionMarkers.contains(baselineValues[markerIndex]) {
      guard lexicalIndices.indices.contains(markerIndex),
            markerIndex + 1 < baselineValues.count else { continue }
      let markerRawIndex = lexicalIndices[markerIndex]
      guard let previous = nearestNonWhitespace(markerRawIndex, step: -1),
            let next = nearestNonWhitespace(markerRawIndex, step: 1),
            baseline[previous].kind == .punctuation,
            baseline[next].kind == .punctuation,
            correctionDelimiters.contains(baseline[previous].original),
            correctionDelimiters.contains(baseline[next].original) else {
        continue
      }
      let kept = Array(baselineValues[(markerIndex + 1)...])
      guard !kept.isEmpty,
            kept.allSatisfy({ !correctionMarkers.contains($0) }) else { continue }
      for splitIndex in 0..<markerIndex {
        let prefix = Array(baselineValues[..<splitIndex])
        let removed = Array(baselineValues[splitIndex..<markerIndex])
        guard !removed.isEmpty,
              removed.allSatisfy({ !correctionMarkers.contains($0) }),
              candidateValues == prefix + kept else { continue }
        matches.append(.init(
          removed: removed,
          kept: kept,
          markerCanonical: baselineValues[markerIndex],
          markerRawRange: markerRawIndex..<(markerRawIndex + 1)
        ))
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
    guard baseline.count == candidate.count,
          (2...5).contains(baseline.count),
          let firstBaseline = baseline.first,
          let firstCandidate = candidate.first,
          startsShortList(at: firstBaseline, in: baselineLexemes),
          startsShortList(at: firstCandidate.0, in: candidateLexemes),
          markersHaveItems(baseline, in: baselineLexemes),
          markersHaveItems(candidate.map(\.0), in: candidateLexemes),
          candidate.dropFirst().allSatisfy({ marker in
            isPrecededByLineBreak(marker.0, in: candidateLexemes)
          }) else {
      return nil
    }
    return (
      baselineRawRanges: baseline,
      candidateRawRanges: candidate.map(\.0),
      candidateNumberRawRanges: candidate.map(\.1)
    )
  }

  private static func startsShortList(
    at range: Range<Int>,
    in lexemes: [CleanupLexeme]
  ) -> Bool {
    lexemes[..<range.lowerBound].allSatisfy { $0.kind == .whitespace }
  }

  private static func isPrecededByLineBreak(
    _ range: Range<Int>,
    in lexemes: [CleanupLexeme]
  ) -> Bool {
    var index = range.lowerBound - 1
    while index >= 0, lexemes[index].kind == .whitespace {
      if lexemes[index].original.contains("\n")
        || lexemes[index].original.contains("\r") {
        return true
      }
      index -= 1
    }
    return false
  }

  private static func markersHaveItems(
    _ ranges: [Range<Int>],
    in lexemes: [CleanupLexeme]
  ) -> Bool {
    ranges.enumerated().allSatisfy { offset, range in
      let end = offset + 1 < ranges.count
        ? ranges[offset + 1].lowerBound
        : lexemes.count
      return lexemes[range.upperBound..<end].contains(where: \.isLexical)
    }
  }
}
