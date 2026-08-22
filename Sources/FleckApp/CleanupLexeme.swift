import Foundation

enum CleanupLexemeKind: String, Equatable, Sendable {
  case word
  case han
  case number
  case punctuation
  case whitespace
  case url
  case email
  case path
  case code
}

struct CleanupLexeme: Equatable, Sendable {
  let original: String
  let canonical: String
  let kind: CleanupLexemeKind

  var isLexical: Bool {
    kind != .punctuation && kind != .whitespace
  }

  static func scan(_ input: String) -> [Self] {
    let characters = Array(input)
    var result: [Self] = []
    var index = 0

    while index < characters.count {
      let character = characters[index]
      if character.isWhitespace {
        let start = index
        repeat { index += 1 } while index < characters.count && characters[index].isWhitespace
        result.append(make(String(characters[start..<index]), kind: .whitespace))
        continue
      }

      if character.isNumber,
         (index == 0 || characters[index - 1].isWhitespace),
         let special = specialRun(in: characters, at: index),
         special.kind == .email {
        result.append(make(String(characters[index..<special.coreEnd]), kind: special.kind))
        index = special.coreEnd
        while index < special.end {
          result.append(make(String(characters[index]), kind: .punctuation))
          index += 1
        }
        continue
      }

      if let end = numberEnd(in: characters, at: index) {
        result.append(make(String(characters[index..<end]), kind: .number))
        index = end
        continue
      }

      if canStartSpecialRun(in: characters, at: index),
         let special = specialRun(in: characters, at: index) {
        result.append(make(String(characters[index..<special.coreEnd]), kind: special.kind))
        index = special.coreEnd
        while index < special.end {
          result.append(make(String(characters[index]), kind: .punctuation))
          index += 1
        }
        continue
      }

      if isHan(character) {
        let start = index
        repeat { index += 1 } while index < characters.count && isHan(characters[index])
        result.append(make(String(characters[start..<index]), kind: .han))
        continue
      }

      if character.isLetter {
        let start = index
        index += 1
        while index < characters.count {
          if characters[index].isLetter {
            index += 1
          } else if isApostrophe(characters[index]),
                    index + 1 < characters.count,
                    characters[index + 1].isLetter {
            index += 1
          } else {
            break
          }
        }
        result.append(make(String(characters[start..<index]), kind: .word))
        continue
      }

      result.append(make(String(character), kind: .punctuation))
      index += 1
    }
    return result
  }

  static func tokenCount(_ input: String) -> Int {
    scan(input).reduce(into: 0) { count, lexeme in
      if lexeme.isLexical { count += 1 }
    }
  }

  private static func make(_ value: String, kind: CleanupLexemeKind) -> Self {
    let composed = value.precomposedStringWithCanonicalMapping
    let canonical = kind == .word ? composed.lowercased() : composed
    return Self(original: value, canonical: canonical, kind: kind)
  }

  private static func isApostrophe(_ character: Character) -> Bool {
    character == "'" || character == "’"
  }

  private static func isHan(_ character: Character) -> Bool {
    character.unicodeScalars.contains { scalar in
      let value = scalar.value
      return isInRange(value, lower: 0x3400, upper: 0x4DBF)
        || isInRange(value, lower: 0x4E00, upper: 0x9FFF)
        || isInRange(value, lower: 0xF900, upper: 0xFAFF)
        || isInRange(value, lower: 0x20000, upper: 0x2FA1F)
    }
  }

  private static func isInRange(_ value: UInt32, lower: UInt32, upper: UInt32) -> Bool {
    value >= lower && value <= upper
  }

  private static func isCurrency(_ character: Character) -> Bool {
    character.unicodeScalars.contains { $0.properties.generalCategory == .currencySymbol }
  }

  private static func isSign(_ character: Character) -> Bool {
    character == "+" || character == "-" || character == "−"
  }

  private static func numberEnd(in characters: [Character], at start: Int) -> Int? {
    var index = start
    if index < characters.count && characters[index] == "(" {
      index += 1
    }
    if index < characters.count && isSign(characters[index]) {
      index += 1
    }
    if index < characters.count && isCurrency(characters[index]) { index += 1 }
    if index < characters.count && isSign(characters[index]) { index += 1 }
    guard index < characters.count && characters[index].isNumber else { return nil }

    var digitCount = 0
    while index < characters.count {
      if characters[index].isNumber {
        digitCount += 1
        index += 1
        continue
      }
      let separator = characters[index]
      let canContinue = separator == "." || separator == "-" || separator == "/" || separator == ":"
      guard canContinue, index + 1 < characters.count, characters[index + 1].isNumber else { break }
      index += 1
    }
    guard digitCount > 0 else { return nil }

    if index < characters.count && (characters[index] == "%" || isCurrency(characters[index])) {
      index += 1
    }
    if index < characters.count && characters[index] == ")" && characters[start] == "(" {
      index += 1
    } else if index + 1 < characters.count {
      let first = String(characters[index]).lowercased()
      let second = String(characters[index + 1]).lowercased()
      if (first == "a" || first == "p") && second == "m" {
        index += 2
      }
    }
    return index
  }

  private static func canStartSpecialRun(in characters: [Character], at index: Int) -> Bool {
    guard index == 0 || characters[index - 1].isWhitespace else { return false }
    let character = characters[index]
    if character.isLetter { return true }
    if character == "/" { return true }
    if character == "~" { return index + 1 < characters.count && characters[index + 1] == "/" }
    if character == "." {
      return (index + 1 < characters.count && characters[index + 1] == "/")
        || (index + 2 < characters.count
          && characters[index + 1] == "."
          && characters[index + 2] == "/")
    }
    if character == "-" { return index + 1 < characters.count && characters[index + 1] == "-" }
    if character == "@" { return index + 1 < characters.count && characters[index + 1].isLetter }
    return character == "_" || character == "=" || character == "`"
      || character == "(" || character == ")"
  }

  private static func specialRun(
    in characters: [Character],
    at start: Int
  ) -> (kind: CleanupLexemeKind, coreEnd: Int, end: Int)? {
    var end = start
    while end < characters.count && !characters[end].isWhitespace { end += 1 }
    var coreEnd = end
    while coreEnd > start,
          [".", ",", ";", ":", "!", "?", "。", "！", "？", "｡", "．", "，", "、", "；", "：", "…"]
            .contains(characters[coreEnd - 1]) {
      coreEnd -= 1
    }
    guard coreEnd > start else { return nil }
    let value = String(characters[start..<coreEnd])
    let kind: CleanupLexemeKind?
    if value.hasPrefix("http://") || value.hasPrefix("https://") || value.hasPrefix("www.") {
      kind = .url
    } else if value.filter({ $0 == "@" }).count == 1, value.contains(".") {
      kind = .email
    } else if value.hasPrefix("/") || value.hasPrefix("~/") || value.hasPrefix("./") || value.hasPrefix("../") {
      kind = .path
    } else {
      let hasMarker = value.contains("(") || value.contains(")") || value.contains("`")
        || value.contains("=") || value.contains("_") || value.contains("--")
      let hasIdentifierDot = value.enumerated().contains { offset, character in
        guard character == ".", offset > 0, offset + 1 < value.count else { return false }
        let left = value[value.index(value.startIndex, offsetBy: offset - 1)]
        let right = value[value.index(value.startIndex, offsetBy: offset + 1)]
        return (left.isLetter || left.isNumber) && (right.isLetter || right.isNumber)
          && (left.isLetter || right.isLetter)
      }
      kind = hasMarker || hasIdentifierDot ? .code : nil
    }
    guard let kind else { return nil }
    return (kind, coreEnd, end)
  }
}
