import Foundation

public enum ModelEvaluationLanguage: String, Codable, Equatable, Sendable {
  case english
  case mandarin
  case mixed
}

public enum ModelEvaluationProtectedComparison: String, Codable, Equatable, Sendable {
  case exact
  case caseAndWhitespaceInsensitive
}

public struct ModelEvaluationProtectedExpectation: Codable, Equatable, Sendable {
  public let kind: String
  public let text: String
  public let comparison: ModelEvaluationProtectedComparison

  public init(
    kind: String,
    text: String,
    comparison: ModelEvaluationProtectedComparison
  ) {
    self.kind = kind
    self.text = text
    self.comparison = comparison
  }
}

public struct ModelEvaluationTiming: Codable, Equatable, Sendable {
  public let isCold: Bool
  public let firstPartialMilliseconds: Double?
  public let stopToFinalMilliseconds: Double?
  public let stopToInsertionMilliseconds: Double?

  public init(
    isCold: Bool,
    firstPartialMilliseconds: Double? = nil,
    stopToFinalMilliseconds: Double? = nil,
    stopToInsertionMilliseconds: Double? = nil
  ) {
    self.isCold = isCold
    self.firstPartialMilliseconds = firstPartialMilliseconds
    self.stopToFinalMilliseconds = stopToFinalMilliseconds
    self.stopToInsertionMilliseconds = stopToInsertionMilliseconds
  }
}

public struct ModelEvaluationCaseInput: Codable, Equatable, Sendable {
  public let id: String
  public let language: ModelEvaluationLanguage
  public let reference: String
  public let hypothesis: String
  public let protectedExpectations: [ModelEvaluationProtectedExpectation]
  public let timing: ModelEvaluationTiming?
  public let peakResidentBytes: Int64?

  public init(
    id: String,
    language: ModelEvaluationLanguage,
    reference: String,
    hypothesis: String,
    protectedExpectations: [ModelEvaluationProtectedExpectation] = [],
    timing: ModelEvaluationTiming? = nil,
    peakResidentBytes: Int64? = nil
  ) {
    self.id = id
    self.language = language
    self.reference = reference
    self.hypothesis = hypothesis
    self.protectedExpectations = protectedExpectations
    self.timing = timing
    self.peakResidentBytes = peakResidentBytes
  }
}

public struct ModelEvaluationRunInput: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let modelID: String
  public let revision: String
  public let runtime: String
  public let quantization: String
  public let hardware: String
  public let unexpectedNetworkConnectionCount: Int
  public let cases: [ModelEvaluationCaseInput]

  public init(
    schemaVersion: Int,
    modelID: String,
    revision: String,
    runtime: String,
    quantization: String,
    hardware: String,
    unexpectedNetworkConnectionCount: Int,
    cases: [ModelEvaluationCaseInput]
  ) {
    self.schemaVersion = schemaVersion
    self.modelID = modelID
    self.revision = revision
    self.runtime = runtime
    self.quantization = quantization
    self.hardware = hardware
    self.unexpectedNetworkConnectionCount = unexpectedNetworkConnectionCount
    self.cases = cases
  }
}

public struct ModelEvaluationLanguageMetric: Codable, Equatable, Sendable {
  public let language: ModelEvaluationLanguage
  public let edits: Int
  public let referenceUnits: Int

  public var errorRate: Double {
    return Double(edits) / Double(referenceUnits)
  }

  public init(language: ModelEvaluationLanguage, edits: Int, referenceUnits: Int) {
    self.language = language
    self.edits = edits
    self.referenceUnits = referenceUnits
  }

  private enum CodingKeys: String, CodingKey {
    case language
    case edits
    case referenceUnits
    case errorRate
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    language = try container.decode(ModelEvaluationLanguage.self, forKey: .language)
    edits = try container.decode(Int.self, forKey: .edits)
    referenceUnits = try container.decode(Int.self, forKey: .referenceUnits)
    _ = try container.decodeIfPresent(Double.self, forKey: .errorRate)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(language, forKey: .language)
    try container.encode(edits, forKey: .edits)
    try container.encode(referenceUnits, forKey: .referenceUnits)
    try container.encode(errorRate, forKey: .errorRate)
  }
}

public struct ModelEvaluationCaseMetric: Codable, Equatable, Sendable {
  public let caseID: String
  public let language: ModelEvaluationLanguage
  public let edits: Int
  public let referenceUnits: Int

  public var errorRate: Double {
    return Double(edits) / Double(referenceUnits)
  }

  public init(
    caseID: String,
    language: ModelEvaluationLanguage,
    edits: Int,
    referenceUnits: Int
  ) {
    self.caseID = caseID
    self.language = language
    self.edits = edits
    self.referenceUnits = referenceUnits
  }

  private enum CodingKeys: String, CodingKey {
    case caseID
    case language
    case edits
    case referenceUnits
    case errorRate
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    caseID = try container.decode(String.self, forKey: .caseID)
    language = try container.decode(ModelEvaluationLanguage.self, forKey: .language)
    edits = try container.decode(Int.self, forKey: .edits)
    referenceUnits = try container.decode(Int.self, forKey: .referenceUnits)
    _ = try container.decodeIfPresent(Double.self, forKey: .errorRate)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(caseID, forKey: .caseID)
    try container.encode(language, forKey: .language)
    try container.encode(edits, forKey: .edits)
    try container.encode(referenceUnits, forKey: .referenceUnits)
    try container.encode(errorRate, forKey: .errorRate)
  }
}

public struct ModelEvaluationProtectedViolation: Codable, Equatable, Sendable {
  public let caseID: String
  public let kind: String
  public let expectedText: String
  public let observedHypothesis: String

  public init(
    caseID: String,
    kind: String,
    expectedText: String,
    observedHypothesis: String
  ) {
    self.caseID = caseID
    self.kind = kind
    self.expectedText = expectedText
    self.observedHypothesis = observedHypothesis
  }
}

public enum ModelEvaluationLatencyKind: String, Codable, Equatable, Sendable {
  case firstPartial
  case stopToFinal
  case stopToInsertion
}

public struct ModelEvaluationLatencySummary: Codable, Equatable, Sendable {
  public let isCold: Bool
  public let kind: ModelEvaluationLatencyKind
  public let sampleCount: Int
  public let p50Milliseconds: Double
  public let p95Milliseconds: Double

  public init(
    isCold: Bool,
    kind: ModelEvaluationLatencyKind,
    sampleCount: Int,
    p50Milliseconds: Double,
    p95Milliseconds: Double
  ) {
    self.isCold = isCold
    self.kind = kind
    self.sampleCount = sampleCount
    self.p50Milliseconds = p50Milliseconds
    self.p95Milliseconds = p95Milliseconds
  }
}

public struct ModelEvaluationReport: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let modelID: String
  public let revision: String
  public let runtime: String
  public let quantization: String
  public let hardware: String
  public let languageMetrics: [ModelEvaluationLanguageMetric]
  public let caseMetrics: [ModelEvaluationCaseMetric]
  public let protectedViolations: [ModelEvaluationProtectedViolation]
  public let latencySummaries: [ModelEvaluationLatencySummary]
  public let maximumObservedPeakResidentBytes: Int64?
  public let unexpectedNetworkConnectionCount: Int

  public init(
    schemaVersion: Int,
    modelID: String,
    revision: String,
    runtime: String,
    quantization: String,
    hardware: String,
    languageMetrics: [ModelEvaluationLanguageMetric],
    caseMetrics: [ModelEvaluationCaseMetric],
    protectedViolations: [ModelEvaluationProtectedViolation],
    latencySummaries: [ModelEvaluationLatencySummary],
    maximumObservedPeakResidentBytes: Int64?,
    unexpectedNetworkConnectionCount: Int
  ) {
    self.schemaVersion = schemaVersion
    self.modelID = modelID
    self.revision = revision
    self.runtime = runtime
    self.quantization = quantization
    self.hardware = hardware
    self.languageMetrics = languageMetrics
    self.caseMetrics = caseMetrics
    self.protectedViolations = protectedViolations
    self.latencySummaries = latencySummaries
    self.maximumObservedPeakResidentBytes = maximumObservedPeakResidentBytes
    self.unexpectedNetworkConnectionCount = unexpectedNetworkConnectionCount
  }
}

public enum ModelEvaluationError: Error, Equatable, Sendable, CustomStringConvertible {
  case unsupportedSchemaVersion(Int)
  case emptyModelID
  case emptyRevision
  case emptyRuntime
  case emptyQuantization
  case emptyHardware
  case emptyCases
  case emptyCaseID
  case duplicateCaseID(String)
  case duplicateProtectedExpectation(String)
  case emptyReference(String)
  case emptyReferenceUnits(String)
  case emptyProtectedKind(String)
  case emptyProtectedText(String)
  case negativeNetworkConnectionCount
  case negativeTiming(String)
  case nonFiniteTiming(String)
  case negativePeakResidentBytes(String)

  public var description: String {
    switch self {
    case .unsupportedSchemaVersion(let version):
      return "Unsupported schema version: \(version)."
    case .emptyModelID:
      return "Model identity is required."
    case .emptyRevision:
      return "Model revision is required."
    case .emptyRuntime:
      return "Runtime is required."
    case .emptyQuantization:
      return "Quantization is required."
    case .emptyHardware:
      return "Hardware is required."
    case .emptyCases:
      return "At least one evaluation case is required."
    case .emptyCaseID:
      return "Case identity is required."
    case .duplicateCaseID(let id):
      return "Duplicate case identity: \(id)."
    case .duplicateProtectedExpectation(let id):
      return "Duplicate protected expectation in case \(id)."
    case .emptyReference(let id):
      return "Reference is required for case \(id)."
    case .emptyReferenceUnits(let id):
      return "Reference has no scoring units for case \(id)."
    case .emptyProtectedKind(let id):
      return "Protected expectation kind is required for case \(id)."
    case .emptyProtectedText(let id):
      return "Protected expectation text is required for case \(id)."
    case .negativeNetworkConnectionCount:
      return "Unexpected network connection count cannot be negative."
    case .negativeTiming(let field):
      return "Timing cannot be negative: \(field)."
    case .nonFiniteTiming(let field):
      return "Timing must be finite: \(field)."
    case .negativePeakResidentBytes(let id):
      return "Peak resident bytes cannot be negative for case \(id)."
    }
  }
}

public enum ModelEvaluationScorer {
  private enum ProtectedValueShape {
    case word
    case numeric
    case path
    case url
  }

  public static func score(
    _ input: ModelEvaluationRunInput
  ) throws -> ModelEvaluationReport {
    try validate(input)

    let languages: [ModelEvaluationLanguage] = [.english, .mandarin, .mixed]
    var editsByLanguage = [Int](repeating: 0, count: languages.count)
    var referenceUnitsByLanguage = [Int](repeating: 0, count: languages.count)
    var presentLanguages = [Bool](repeating: false, count: languages.count)
    var caseMetrics: [ModelEvaluationCaseMetric] = []
    var protectedViolations: [ModelEvaluationProtectedViolation] = []
    var latencySamples = Array(
      repeating: Array(repeating: [Double](), count: 3),
      count: 2
    )
    var maximumObservedPeakResidentBytes: Int64?

    for evaluationCase in input.cases {
      let referenceTokens = tokens(
        for: evaluationCase.reference,
        language: evaluationCase.language
      )
      let hypothesisTokens = tokens(
        for: evaluationCase.hypothesis,
        language: evaluationCase.language
      )
      guard !referenceTokens.isEmpty else {
        throw ModelEvaluationError.emptyReferenceUnits(evaluationCase.id)
      }
      let languageIndex = languages.firstIndex(of: evaluationCase.language)!
      presentLanguages[languageIndex] = true
      let edits = levenshtein(
        referenceTokens,
        hypothesisTokens
      )
      editsByLanguage[languageIndex] += edits
      referenceUnitsByLanguage[languageIndex] += referenceTokens.count
      caseMetrics.append(
        ModelEvaluationCaseMetric(
          caseID: evaluationCase.id,
          language: evaluationCase.language,
          edits: edits,
          referenceUnits: referenceTokens.count
        )
      )

      for expectation in evaluationCase.protectedExpectations {
        guard
          contains(
            expectation.text,
            in: evaluationCase.hypothesis,
            comparison: expectation.comparison
          )
        else {
          protectedViolations.append(
            ModelEvaluationProtectedViolation(
              caseID: evaluationCase.id,
              kind: expectation.kind,
              expectedText: expectation.text,
              observedHypothesis: evaluationCase.hypothesis
            )
          )
          continue
        }
      }

      if let timing = evaluationCase.timing {
        let coldIndex = timing.isCold ? 1 : 0
        if let value = timing.firstPartialMilliseconds {
          latencySamples[coldIndex][0].append(value)
        }
        if let value = timing.stopToFinalMilliseconds {
          latencySamples[coldIndex][1].append(value)
        }
        if let value = timing.stopToInsertionMilliseconds {
          latencySamples[coldIndex][2].append(value)
        }
      }

      if let peakResidentBytes = evaluationCase.peakResidentBytes {
        maximumObservedPeakResidentBytes = max(
          maximumObservedPeakResidentBytes ?? peakResidentBytes,
          peakResidentBytes
        )
      }
    }

    var languageMetrics: [ModelEvaluationLanguageMetric] = []
    for (index, language) in languages.enumerated()
    where presentLanguages[index] {
      languageMetrics.append(
        ModelEvaluationLanguageMetric(
          language: language,
          edits: editsByLanguage[index],
          referenceUnits: referenceUnitsByLanguage[index]
        )
      )
    }

    let latencyKinds: [ModelEvaluationLatencyKind] = [
      .firstPartial,
      .stopToFinal,
      .stopToInsertion,
    ]
    var latencySummaries: [ModelEvaluationLatencySummary] = []
    for coldIndex in 0..<latencySamples.count {
      for kindIndex in 0..<latencyKinds.count {
        let samples = latencySamples[coldIndex][kindIndex]
        guard !samples.isEmpty else { continue }
        latencySummaries.append(
          ModelEvaluationLatencySummary(
            isCold: coldIndex == 1,
            kind: latencyKinds[kindIndex],
            sampleCount: samples.count,
            p50Milliseconds: nearestRank(samples, percentile: 0.50),
            p95Milliseconds: nearestRank(samples, percentile: 0.95)
          )
        )
      }
    }

    return ModelEvaluationReport(
      schemaVersion: input.schemaVersion,
      modelID: input.modelID,
      revision: input.revision,
      runtime: input.runtime,
      quantization: input.quantization,
      hardware: input.hardware,
      languageMetrics: languageMetrics,
      caseMetrics: caseMetrics,
      protectedViolations: protectedViolations,
      latencySummaries: latencySummaries,
      maximumObservedPeakResidentBytes: maximumObservedPeakResidentBytes,
      unexpectedNetworkConnectionCount: input.unexpectedNetworkConnectionCount
    )
  }

  private static func validate(_ input: ModelEvaluationRunInput) throws {
    guard input.schemaVersion == 1 else {
      throw ModelEvaluationError.unsupportedSchemaVersion(input.schemaVersion)
    }
    guard !input.modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ModelEvaluationError.emptyModelID
    }
    guard !input.revision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ModelEvaluationError.emptyRevision
    }
    guard !input.runtime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ModelEvaluationError.emptyRuntime
    }
    guard !input.quantization.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ModelEvaluationError.emptyQuantization
    }
    guard !input.hardware.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ModelEvaluationError.emptyHardware
    }
    guard !input.cases.isEmpty else {
      throw ModelEvaluationError.emptyCases
    }
    guard input.unexpectedNetworkConnectionCount >= 0 else {
      throw ModelEvaluationError.negativeNetworkConnectionCount
    }

    var seenCaseIDs = Set<String>()
    for evaluationCase in input.cases {
      let caseID = evaluationCase.id.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !caseID.isEmpty else {
        throw ModelEvaluationError.emptyCaseID
      }
      guard seenCaseIDs.insert(caseID).inserted else {
        throw ModelEvaluationError.duplicateCaseID(caseID)
      }
      guard
        !evaluationCase.reference
          .trimmingCharacters(in: .whitespacesAndNewlines)
          .isEmpty
      else {
        throw ModelEvaluationError.emptyReference(evaluationCase.id)
      }

      var seenProtectedExpectations: [ModelEvaluationProtectedExpectation] = []
      for expectation in evaluationCase.protectedExpectations {
        guard
          !expectation.kind
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        else {
          throw ModelEvaluationError.emptyProtectedKind(evaluationCase.id)
        }
        guard
          !expectation.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        else {
          throw ModelEvaluationError.emptyProtectedText(evaluationCase.id)
        }
        guard !seenProtectedExpectations.contains(expectation) else {
          throw ModelEvaluationError.duplicateProtectedExpectation(evaluationCase.id)
        }
        seenProtectedExpectations.append(expectation)
      }

      if let timing = evaluationCase.timing {
        let measurements: [(String, Double?)] = [
          ("firstPartialMilliseconds", timing.firstPartialMilliseconds),
          ("stopToFinalMilliseconds", timing.stopToFinalMilliseconds),
          ("stopToInsertionMilliseconds", timing.stopToInsertionMilliseconds),
        ]
        for (field, value) in measurements {
          guard let value else { continue }
          guard value.isFinite else {
            throw ModelEvaluationError.nonFiniteTiming(field)
          }
          guard value >= 0 else {
            throw ModelEvaluationError.negativeTiming(field)
          }
        }
      }

      if let peakResidentBytes = evaluationCase.peakResidentBytes,
        peakResidentBytes < 0
      {
        throw ModelEvaluationError.negativePeakResidentBytes(evaluationCase.id)
      }
    }
  }

  private static func tokens(
    for text: String,
    language: ModelEvaluationLanguage
  ) -> [String] {
    switch language {
    case .english:
      return englishTokens(text)
    case .mandarin:
      return mandarinTokens(text)
    case .mixed:
      return mixedTokens(lowercasedPOSIX(text))
    }
  }

  private static func englishTokens(_ text: String) -> [String] {
    let normalized = (text as NSString).lowercased(
      with: Locale(identifier: "en_US_POSIX")
    )
    return wordTokens(normalized)
  }

  private static func mandarinTokens(_ text: String) -> [String] {
    text.filter { character in
      !isWhitespace(character) && !isPunctuation(character)
    }.map(String.init)
  }

  private static func mixedTokens(_ text: String) -> [String] {
    var result: [String] = []
    var word = ""
    let characters = Array(text)
    var index = 0

    func flushWord() {
      guard !word.isEmpty else { return }
      result.append(word)
      word.removeAll(keepingCapacity: true)
    }

    while index < characters.count {
      let character = characters[index]
      if isHan(character) {
        flushWord()
        result.append(String(character))
        index += 1
        continue
      }

      guard isLetterOrDigit(character) else {
        flushWord()
        index += 1
        continue
      }

      word.append(character)
      index += 1
      while index < characters.count {
        let next = characters[index]
        if isLetterOrDigit(next), !isHan(next) {
          word.append(next)
          index += 1
        } else if isApostrophe(next),
          index + 1 < characters.count,
          isLetterOrDigit(characters[index + 1]),
          !isHan(characters[index + 1])
        {
          word.append(next)
          index += 1
        } else {
          break
        }
      }
      flushWord()
    }

    flushWord()
    return result
  }

  private static func wordTokens(_ text: String) -> [String] {
    var result: [String] = []
    var word = ""
    let characters = Array(text)
    var index = 0

    func flushWord() {
      guard !word.isEmpty else { return }
      result.append(word)
      word.removeAll(keepingCapacity: true)
    }

    while index < characters.count {
      let character = characters[index]
      guard isLetterOrDigit(character) else {
        index += 1
        continue
      }

      word.append(character)
      index += 1
      while index < characters.count {
        let next = characters[index]
        if isLetterOrDigit(next) {
          word.append(next)
          index += 1
        } else if isApostrophe(next),
          index + 1 < characters.count,
          isLetterOrDigit(characters[index + 1])
        {
          word.append(next)
          index += 1
        } else {
          break
        }
      }
      flushWord()
    }

    flushWord()
    return result
  }

  private static func isLetterOrDigit(_ character: Character) -> Bool {
    character.unicodeScalars.contains { scalar in
      CharacterSet.letters.contains(scalar)
        || CharacterSet.decimalDigits.contains(scalar)
    }
  }

  private static func isHan(_ character: Character) -> Bool {
    character.unicodeScalars.contains { scalar in
      scalar.properties.isIdeographic || scalar.properties.isUnifiedIdeograph
    }
  }

  private static func isWhitespace(_ character: Character) -> Bool {
    character.unicodeScalars.allSatisfy {
      CharacterSet.whitespacesAndNewlines.contains($0)
    }
  }

  private static func isPunctuation(_ character: Character) -> Bool {
    character.unicodeScalars.contains {
      CharacterSet.punctuationCharacters.contains($0)
    }
  }

  private static func isApostrophe(_ character: Character) -> Bool {
    character.unicodeScalars.count == 1
      && [0x27, 0x2019, 0x02BC, 0xFF07].contains(
        character.unicodeScalars.first!.value
      )
  }

  private static func contains(
    _ expected: String,
    in hypothesis: String,
    comparison: ModelEvaluationProtectedComparison
  ) -> Bool {
    let normalizedExpected: String
    let normalizedHypothesis: String
    switch comparison {
    case .exact:
      normalizedExpected = expected
      normalizedHypothesis = hypothesis
    case .caseAndWhitespaceInsensitive:
      normalizedExpected = collapseWhitespace(lowercasedPOSIX(expected))
      normalizedHypothesis = collapseWhitespace(lowercasedPOSIX(hypothesis))
    }
    return containsBoundedLiteral(normalizedExpected, in: normalizedHypothesis)
  }

  private static func containsBoundedLiteral(
    _ expected: String,
    in hypothesis: String
  ) -> Bool {
    guard !expected.isEmpty else { return false }

    let shape = protectedValueShape(expected)
    var searchStart = hypothesis.startIndex
    while searchStart < hypothesis.endIndex,
      let range = hypothesis.range(
        of: expected,
        range: searchStart..<hypothesis.endIndex
      )
    {
      let leftBoundaryIndex: String.Index? =
        range.lowerBound > hypothesis.startIndex
        ? hypothesis.index(before: range.lowerBound)
        : nil
      let rightBoundaryIndex: String.Index? =
        range.upperBound < hypothesis.endIndex
        ? range.upperBound
        : nil
      let leftBoundary = leftBoundaryIndex.map { hypothesis[$0] }
      let rightBoundary = rightBoundaryIndex.map { hypothesis[$0] }
      let leftContinuation: Character? = leftBoundaryIndex.flatMap { index in
        guard index > hypothesis.startIndex else { return nil }
        return hypothesis[hypothesis.index(before: index)]
      }
      let rightContinuation: Character? = rightBoundaryIndex.flatMap { index in
        let nextIndex = hypothesis.index(after: index)
        guard nextIndex < hypothesis.endIndex else { return nil }
        return hypothesis[nextIndex]
      }

      let leftContinuesValue = continuesProtectedValue(
        shape: shape,
        boundary: leftBoundary,
        continuation: leftContinuation,
        isLeft: true
      )
      let rightContinuesValue = continuesProtectedValue(
        shape: shape,
        boundary: rightBoundary,
        continuation: rightContinuation,
        isLeft: false
      )
      if !leftContinuesValue && !rightContinuesValue {
        return true
      }

      searchStart = hypothesis.index(after: range.lowerBound)
    }
    return false
  }

  private static func continuesProtectedValue(
    shape: ProtectedValueShape,
    boundary: Character?,
    continuation: Character?,
    isLeft: Bool
  ) -> Bool {
    guard let boundary else { return false }

    switch shape {
    case .word:
      return continuesWordValue(
        boundary: boundary,
        continuation: continuation
      )
    case .path:
      return continuesPathOrURLValue(
        boundary: boundary,
        continuation: continuation,
        isLeft: isLeft,
        isURL: false
      )
    case .url:
      return continuesPathOrURLValue(
        boundary: boundary,
        continuation: continuation,
        isLeft: isLeft,
        isURL: true
      )
    case .numeric:
      if isWordOrIdentifierContinuation(boundary) {
        return true
      }
      if isTypographicNumericRangeDash(boundary) {
        return true
      }
      if isCurrencySymbol(boundary) || isNumericSign(boundary) {
        return true
      }
      if !isLeft && isPercent(boundary) {
        return true
      }
      guard isNumericSeparator(boundary) else { return false }
      if isLeft || boundary != "." && boundary != "," {
        return true
      }
      return continuation.map(isDecimalDigit) == true
    }
  }

  private static func protectedValueShape(_ text: String) -> ProtectedValueShape {
    if isNumericShaped(text) {
      return .numeric
    }
    if isURLShaped(text) {
      return .url
    }
    if isPathShaped(text) {
      return .path
    }
    return .word
  }

  private static func isNumericShaped(_ text: String) -> Bool {
    var numericText = text
    if let first = numericText.first, isNumericSign(first) {
      numericText.removeFirst()
    }

    var hasDigit = false
    var requiresDigitAfterRangeHyphen = false
    var previousWasDigit = false
    for character in numericText {
      if isDecimalDigit(character) {
        hasDigit = true
        previousWasDigit = true
        requiresDigitAfterRangeHyphen = false
      } else if isNumericRangeDash(character) {
        guard previousWasDigit else { return false }
        previousWasDigit = false
        requiresDigitAfterRangeHyphen = true
      } else if !isNumericSeparator(character)
        && !isCurrencySymbol(character)
        && !isPercent(character)
      {
        return false
      } else {
        guard !requiresDigitAfterRangeHyphen else { return false }
        previousWasDigit = false
      }
    }
    return hasDigit && !requiresDigitAfterRangeHyphen
  }

  private static func isURLShaped(_ text: String) -> Bool {
    let scalars = text.unicodeScalars
    guard !text.contains(where: isWhitespace) else { return false }
    let hasForwardSlash = scalars.contains { $0.value == 0x2F }
    let hasBackslash = scalars.contains { $0.value == 0x5C }
    let hasPathSeparator = hasForwardSlash || hasBackslash
    let hasScheme = text.contains("://")
    let startsWithDoubleSlash = text.hasPrefix("//")
    let hasEmailMarker = !hasPathSeparator && scalars.contains { $0.value == 0x40 }
    let hasDomainLikeHostBeforeSlash =
      text.firstIndex(of: "/").map { index in
        let host = text[..<index]
        return host.contains(".")
          && host.unicodeScalars.contains { CharacterSet.letters.contains($0) }
      } == true
    if hasBackslash && !hasScheme {
      return false
    }
    if hasForwardSlash
      && !hasScheme
      && !startsWithDoubleSlash
      && !hasDomainLikeHostBeforeSlash
    {
      return false
    }

    let hasURLMarker = scalars.contains {
      [0x23, 0x25, 0x26, 0x3A, 0x3D, 0x40, 0x3F].contains($0.value)
    }
    let hasDomainPeriod =
      scalars.contains { $0.value == 0x2E }
      && scalars.contains { CharacterSet.letters.contains($0) }
    return hasScheme
      || startsWithDoubleSlash
      || hasEmailMarker
      || hasURLMarker
      || hasDomainPeriod
  }

  private static func isPathShaped(_ text: String) -> Bool {
    text.unicodeScalars.contains {
      $0.value == 0x2F || $0.value == 0x5C
    }
  }

  private static func isWordOrIdentifierContinuation(
    _ character: Character
  ) -> Bool {
    isLetterOrDigit(character) || character == "_"
  }

  private static func continuesWordValue(
    boundary: Character,
    continuation: Character?
  ) -> Bool {
    if isWordOrIdentifierContinuation(boundary) {
      return true
    }
    guard
      isApostrophe(boundary)
        || isNumericRangeDash(boundary)
        || boundary == "."
        || boundary == "@"
    else {
      return false
    }
    return continuation.map(isWordOrIdentifierContinuation) == true
  }

  private static func isPathURLContinuation(_ character: Character) -> Bool {
    character.unicodeScalars.contains { isPathURLScalar($0) }
  }

  private static func continuesPathOrURLValue(
    boundary: Character,
    continuation: Character?,
    isLeft: Bool,
    isURL: Bool
  ) -> Bool {
    if isWordOrIdentifierContinuation(boundary) {
      return true
    }
    if boundary == "/" || boundary == "\\" {
      return true
    }
    if !isURL && isPathAlwaysContinuation(boundary) {
      return true
    }
    if isURL && isURLAlwaysContinuation(boundary) {
      return true
    }
    guard isURL ? isURLContinuation(boundary) : isPathURLContinuation(boundary) else {
      return false
    }
    if isLeft {
      return true
    }
    guard let continuation, !isWhitespace(continuation) else { return false }
    return !isClosingSentenceDelimiter(continuation)
  }

  private static func isURLAlwaysContinuation(_ character: Character) -> Bool {
    character.unicodeScalars.contains {
      [0x23, 0x26, 0x25, 0x3D, 0x40, 0x3A, 0x2B, 0x3F, 0x7E].contains($0.value)
    }
  }

  private static func isURLContinuation(_ character: Character) -> Bool {
    isPathURLContinuation(character)
      || character.unicodeScalars.contains {
        [0x21, 0x24, 0x2C, 0x3B].contains($0.value)
      }
  }

  private static func isPathAlwaysContinuation(_ character: Character) -> Bool {
    isPathURLContinuation(character) && character != "." && character != "?"
  }

  private static func isClosingSentenceDelimiter(_ character: Character) -> Bool {
    character.unicodeScalars.contains {
      [0x22, 0x27, 0x2019, 0x201D, 0x29, 0x5D, 0x7D].contains($0.value)
    }
  }

  private static func isDecimalDigit(_ character: Character) -> Bool {
    character.unicodeScalars.contains {
      CharacterSet.decimalDigits.contains($0)
    }
  }

  private static func isCurrencySymbol(_ character: Character) -> Bool {
    character.unicodeScalars.contains {
      $0.properties.generalCategory == .currencySymbol
    }
  }

  private static func isPercent(_ character: Character) -> Bool {
    character.unicodeScalars.contains {
      [0x25, 0xFF05, 0x066A].contains($0.value)
    }
  }

  private static func isNumericSign(_ character: Character) -> Bool {
    character == "+" || character == "-" || character == "−"
  }

  private static func isNumericRangeDash(_ character: Character) -> Bool {
    character.unicodeScalars.contains {
      [0x2D, 0x2012, 0x2013, 0x2014, 0x2015].contains($0.value)
    }
  }

  private static func isTypographicNumericRangeDash(_ character: Character) -> Bool {
    character.unicodeScalars.contains {
      [0x2012, 0x2013, 0x2014, 0x2015].contains($0.value)
    }
  }

  private static func isNumericSeparator(_ character: Character) -> Bool {
    character.unicodeScalars.contains {
      [0x2C, 0x2E, 0x2F, 0x3A, 0x2044].contains($0.value)
    }
  }

  private static func isPathURLScalar(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x2F, 0x5C, 0x2E, 0x2D, 0x24, 0x3A, 0x3F, 0x26, 0x3D, 0x25, 0x23,
      0x40, 0x2B, 0x7E:
      return true
    default:
      return false
    }
  }

  private static func lowercasedPOSIX(_ text: String) -> String {
    (text as NSString).lowercased(with: Locale(identifier: "en_US_POSIX"))
  }

  private static func collapseWhitespace(_ text: String) -> String {
    var result = ""
    var previousWasWhitespace = false
    for character in text {
      if isWhitespace(character) {
        if !previousWasWhitespace {
          result.append(" ")
        }
        previousWasWhitespace = true
      } else {
        result.append(character)
        previousWasWhitespace = false
      }
    }
    return result
  }

  private static func nearestRank(_ values: [Double], percentile: Double) -> Double {
    let sorted = values.sorted()
    let oneBasedRank = Int(ceil(percentile * Double(sorted.count)))
    let index = min(max(oneBasedRank - 1, 0), sorted.count - 1)
    return sorted[index]
  }

  private static func levenshtein<T: Equatable>(
    _ reference: [T],
    _ hypothesis: [T]
  ) -> Int {
    if reference.isEmpty { return hypothesis.count }
    if hypothesis.isEmpty { return reference.count }

    var previous = Array(0...hypothesis.count)
    for (referenceIndex, referenceValue) in reference.enumerated() {
      var current = [Int](repeating: 0, count: hypothesis.count + 1)
      current[0] = referenceIndex + 1
      for (hypothesisIndex, hypothesisValue) in hypothesis.enumerated() {
        let substitution =
          previous[hypothesisIndex]
          + (referenceValue == hypothesisValue ? 0 : 1)
        let insertion = current[hypothesisIndex] + 1
        let deletion = previous[hypothesisIndex + 1] + 1
        current[hypothesisIndex + 1] = min(substitution, insertion, deletion)
      }
      previous = current
    }
    return previous[hypothesis.count]
  }
}
