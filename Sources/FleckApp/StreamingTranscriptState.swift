import Foundation

enum StreamingTranscriptStateError: Error, Equatable {
  case staleGeneration
  case stablePrefixChanged
  case mutableTailTooLarge
}

struct StreamingTranscriptState {
  private(set) var update = DictationTextUpdate(
    generation: 0, stableText: "", provisionalTail: ""
  )
  let maximumMutableLexicalUnits = 80
  let maximumMutableClauses = 2

  mutating func accept(
    generation: UInt64,
    fullText: String
  ) throws -> DictationTextUpdate {
    guard generation > update.generation else {
      throw StreamingTranscriptStateError.staleGeneration
    }
    let split = Self.splitStablePrefix(
      fullText,
      maximumMutableLexicalUnits: maximumMutableLexicalUnits,
      maximumMutableClauses: maximumMutableClauses
    )
    guard split.stable.hasPrefix(update.stableText) else {
      throw StreamingTranscriptStateError.stablePrefixChanged
    }
    guard CleanupLexeme.tokenCount(split.tail)
      <= maximumMutableLexicalUnits else {
      throw StreamingTranscriptStateError.mutableTailTooLarge
    }
    update = DictationTextUpdate(
      generation: generation,
      stableText: split.stable,
      provisionalTail: split.tail
    )
    return update
  }

  private static let clauseTerminators: Set<Character> = [
    ".", "?", "!", "。", "！", "？"
  ]

  private static func splitStablePrefix(
    _ fullText: String,
    maximumMutableLexicalUnits: Int,
    maximumMutableClauses: Int
  ) -> (stable: String, tail: String) {
    let lexemes = CleanupLexeme.scan(fullText)
    var offset = 0
    var terminatorEnds = [Int]()
    var lexicalSpans = [(start: Int, end: Int)]()

    for lexeme in lexemes {
      let start = offset
      offset += Array(lexeme.original).count
      if lexeme.kind == .punctuation,
         lexeme.original.count == 1,
         clauseTerminators.contains(Character(lexeme.original)) {
        terminatorEnds.append(offset)
      }
      if lexeme.isLexical {
        lexicalSpans.append((start: start, end: offset))
      }
    }

    var clauseStart = 0
    if !terminatorEnds.isEmpty {
      let boundaryIndex = max(
        0,
        terminatorEnds.count - maximumMutableClauses
      )
      clauseStart = terminatorEnds[boundaryIndex]
    }

    let characters = Array(fullText)
    let trailingLexemes = CleanupLexeme.scan(String(characters[clauseStart...]))
    for lexeme in trailingLexemes {
      guard lexeme.kind == .whitespace else { break }
      clauseStart += Array(lexeme.original).count
    }

    let mutableSpans = lexicalSpans.filter { $0.start >= clauseStart }
    let boundedStart = mutableSpans.count > maximumMutableLexicalUnits
      ? mutableSpans[mutableSpans.count - maximumMutableLexicalUnits].start
      : clauseStart
    return (
      String(characters[..<boundedStart]),
      String(characters[boundedStart...])
    )
  }
}
