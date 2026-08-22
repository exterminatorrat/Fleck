import Foundation
import FleckCore

enum CleanupProtectedCategory: String, CaseIterable, Hashable, Sendable {
  case dictionary
  case name
  case number
  case dateOrTime
  case price
  case unit
  case quantity
  case recipient
  case destination
  case path
  case url
  case email
  case code
  case command
  case negation
  case modality
  case commitment
  case quoted
  case mixedLanguage
}

struct CleanupProtectedSpan: Equatable, Sendable {
  let category: CleanupProtectedCategory
  let text: String
  // Lexical values plus non-whitespace punctuation and symbols; whitespace is omitted.
  let canonicalLexemes: [String]
  let lexemeRange: Range<Int>

  static func extract(from text: String, protectedForms: [String]) -> [Self] {
    let lexemes = CleanupLexeme.scan(text)
    var spans: [Self] = []
    func append(_ category: CleanupProtectedCategory, _ range: Range<Int>) {
      guard !range.isEmpty else { return }
      spans.append(makeSpan(category: category, lexemes: lexemes, range: range))
    }

    let records = protectedForms.compactMap { form -> (values: [String], key: String)? in
      let values = CleanupLexeme.scan(form)
        .filter { $0.kind != .whitespace }
        .map(\.canonical)
      guard !values.isEmpty else { return nil }
      return (values, values.joined(separator: "\u{1F}"))
    }.sorted { left, right in
      if left.values.count != right.values.count { return left.values.count > right.values.count }
      return left.key < right.key
    }
    var remaining: [String: Int] = [:]
    for record in records { remaining[record.key, default: 0] += 1 }
    var occupied = Set<Int>()
    for start in lexemes.indices where lexemes[start].kind != .whitespace {
      for record in records {
        guard (remaining[record.key] ?? 0) > 0,
              let end = matchingEnd(of: record.values, in: lexemes, from: start) else { continue }
        let range = start..<end
        guard range.first(where: { occupied.contains($0) }) == nil else { continue }
        append(.dictionary, range)
        remaining[record.key, default: 0] -= 1
        for index in range { occupied.insert(index) }
        break
      }
    }

    let dictionaryNameIndices = Set(spans.compactMap { span -> Int? in
      guard span.category == .dictionary, span.lexemeRange.count == 1 else { return nil }
      let index = span.lexemeRange.lowerBound
      guard lexemes[index].kind == .word,
            lexemes[index].original.first?.isUppercase == true else { return nil }
      return index
    })

    for index in lexemes.indices {
      let lexeme = lexemes[index]
      switch lexeme.kind {
      case .url: append(.url, index..<(index + 1))
      case .email: append(.email, index..<(index + 1))
      case .path: append(.path, index..<(index + 1))
      case .code: append(.code, index..<(index + 1))
      case .number:
        let lower = lexeme.original.lowercased()
        if containsCurrency(lexeme.original) {
          append(.price, index..<(index + 1))
        } else if lower.contains("-") || lower.contains("/") || lower.contains(":")
                    || lower.hasSuffix("am") || lower.hasSuffix("pm") {
          append(.dateOrTime, index..<(index + 1))
        } else {
          append(.number, index..<(index + 1))
        }
        if let unit = nextLexicalIndex(in: lexemes, after: index),
           lexemes[unit].kind == .word,
           unitValues.contains(lexemes[unit].canonical) {
          append(.unit, unit..<(unit + 1))
          append(.quantity, index..<(unit + 1))
        }
      case .word, .han, .punctuation, .whitespace:
        break
      }
    }

    for index in lexemes.indices where isCurrencyPunctuation(lexemes[index]) {
      guard let numberIndex = nextLexicalIndex(in: lexemes, after: index),
            lexemes[numberIndex].kind == .number else { continue }
      append(.price, index..<(numberIndex + 1))
    }

    let dateWords = monthWords.union(weekdayWords)
    let commandWords: Set<String> = ["run", "execute", "open", "type", "use", "git", "npm", "swift", "curl", "rm", "chmod", "xcodebuild"]
    let negations: Set<String> = ["no", "not", "never", "without", "cannot", "can't", "don't", "doesn't", "isn't", "won't", "不", "没", "没有", "不要", "不能", "未", "無", "无"]
    let modalities: Set<String> = ["may", "might", "could", "can", "should", "would", "perhaps", "可能", "可以", "应该"]
    let commitments: Set<String> = ["will", "must", "shall", "promise", "committed", "一定", "必须", "承诺"]
    for index in lexemes.indices where lexemes[index].isLexical {
      let word = lexemes[index].canonical
      let atSentenceBoundary = previousSentenceBoundary(in: lexemes, before: index)
      if dateWords.contains(word) { append(.dateOrTime, index..<(index + 1)) }
      if negations.contains(word)
          || (lexemes[index].kind == .han && containsMandarinTerm(word, in: negations)) {
        append(.negation, index..<(index + 1))
      }
      if modalities.contains(word)
          || (lexemes[index].kind == .han && containsMandarinTerm(word, in: modalities)) {
        append(.modality, index..<(index + 1))
      }
      if commitments.contains(word)
          || (lexemes[index].kind == .han && containsMandarinTerm(word, in: commitments)) {
        append(.commitment, index..<(index + 1))
      }
      if commandWords.contains(word) {
        append(.command, commandRange(in: lexemes, from: index))
      }
      if let range = followingRange(in: lexemes, after: index), ["to", "email", "call", "tell"].contains(word) {
        append(.recipient, range)
      }
      if let range = followingRange(in: lexemes, after: index), ["at", "into", "toward", "destination"].contains(word) {
        append(.destination, range)
      }
      if (lexemes[index].kind == .word || lexemes[index].kind == .han),
         !commandWords.contains(word), !dateWords.contains(word),
         lexemes[index].canonical != "i",
         lexemes[index].original.first?.isUppercase == true,
         !followsListMarker(in: lexemes, before: index),
         (atSentenceBoundary == false
          || (dictionaryNameIndices.contains(index) && atSentenceBoundary)) {
        append(.name, index..<(index + 1))
      }
    }

    var quoteStart: Int?
    var quoteCloser: String?
    for index in lexemes.indices {
      let value = lexemes[index].original
      if quoteStart == nil, value == "\"" {
        quoteStart = index
        quoteCloser = "\""
      } else if quoteStart == nil, value == "“" {
        quoteStart = index
        quoteCloser = "”"
      } else if quoteStart == nil, value == "'" {
        quoteStart = index
        quoteCloser = "'"
      } else if quoteStart == nil, value == "‘" {
        quoteStart = index
        quoteCloser = "’"
      } else if let start = quoteStart, value == quoteCloser {
        append(.quoted, start..<(index + 1))
        quoteStart = nil
        quoteCloser = nil
      }
    }

    let languageIndices = lexemes.indices.filter { lexemes[$0].isLexical }
    let hasWord = languageIndices.contains { lexemes[$0].kind == .word }
    let hasHan = languageIndices.contains { lexemes[$0].kind == .han }
    if hasWord, hasHan, let first = languageIndices.first, let last = languageIndices.last {
      append(.mixedLanguage, first..<(last + 1))
    }
    return spans.sorted { left, right in
      if left.lexemeRange.lowerBound != right.lexemeRange.lowerBound {
        return left.lexemeRange.lowerBound < right.lexemeRange.lowerBound
      }
      let leftLength = left.lexemeRange.count
      let rightLength = right.lexemeRange.count
      if leftLength != rightLength { return leftLength > rightLength }
      return left.category.rawValue < right.category.rawValue
    }
  }

  private static let unitValues: Set<String> = ["ms", "s", "sec", "secs", "min", "mins", "hour", "hours", "mm", "cm", "m", "km", "g", "kg", "mg", "oz", "lb", "lbs", "ml", "l", "gb", "mb", "tb", "%", "°c"]
  private static let monthWords: Set<String> = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
  private static let weekdayWords: Set<String> = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
  private static func containsMandarinTerm(_ word: String, in terms: Set<String>) -> Bool {
    terms.contains { word.contains($0) }
  }

  private static func containsCurrency(_ value: String) -> Bool {
    value.unicodeScalars.contains { $0.properties.generalCategory == .currencySymbol }
  }

  private static func isCurrencyPunctuation(_ lexeme: CleanupLexeme) -> Bool {
    lexeme.kind == .punctuation && containsCurrency(lexeme.original)
  }

  private static func makeSpan(category: CleanupProtectedCategory, lexemes: [CleanupLexeme], range: Range<Int>) -> Self {
    let slice = lexemes[range]
    return Self(
      category: category,
      text: slice.map(\.original).joined(),
      canonicalLexemes: slice.filter { $0.kind != .whitespace }.map(\.canonical),
      lexemeRange: range
    )
  }

  private static func matchingEnd(of values: [String], in lexemes: [CleanupLexeme], from start: Int) -> Int? {
    var found: [String] = []
    var index = start
    var end = start
    while index < lexemes.count && found.count < values.count {
      if lexemes[index].kind != .whitespace {
        found.append(lexemes[index].canonical)
        end = index + 1
      }
      index += 1
    }
    return found == values ? end : nil
  }

  private static func nextLexicalIndex(in lexemes: [CleanupLexeme], after index: Int) -> Int? {
    var next = index + 1
    while next < lexemes.count {
      if lexemes[next].isLexical { return next }
      if lexemes[next].kind != .whitespace { return nil }
      next += 1
    }
    return nil
  }

  private static func followingRange(in lexemes: [CleanupLexeme], after index: Int) -> Range<Int>? {
    guard let next = nextLexicalIndex(in: lexemes, after: index) else { return nil }
    return next..<(next + 1)
  }

  private static func commandRange(in lexemes: [CleanupLexeme], from start: Int) -> Range<Int> {
    return start..<lexemes.count
  }

  private static func previousSentenceBoundary(in lexemes: [CleanupLexeme], before index: Int) -> Bool {
    var current = index - 1
    while current >= 0 {
      if lexemes[current].isLexical { return false }
      if [".", "!", "?"].contains(lexemes[current].original) { return true }
      current -= 1
    }
    return true
  }

  private static func followsListMarker(in lexemes: [CleanupLexeme], before index: Int) -> Bool {
    guard let punctuation = nearestNonWhitespace(in: lexemes, before: index),
          lexemes[punctuation].original == ".",
          let number = nearestNonWhitespace(in: lexemes, before: punctuation) else { return false }
    return lexemes[number].kind == .number && ["1", "2", "3", "4", "5"].contains(lexemes[number].canonical)
  }

  private static func nearestNonWhitespace(in lexemes: [CleanupLexeme], before index: Int) -> Int? {
    var current = index - 1
    while current >= 0 {
      if lexemes[current].kind != .whitespace { return current }
      current -= 1
    }
    return nil
  }
}
