import Foundation
import Testing

@testable import FleckApp

@Test func stablePrefixOnlyGrows() throws {
  var state = StreamingTranscriptState()
  _ = try state.accept(generation: 1, fullText: "First. Second")
  let update = try state.accept(
    generation: 2,
    fullText: "First. Second. Third"
  )
  #expect(update.stableText == "First. ")
  #expect(update.provisionalTail == "Second. Third")
}

@Test func zeroTerminatorsKeepTheWholeTranscriptMutable() throws {
  var state = StreamingTranscriptState()
  let update = try state.accept(generation: 1, fullText: "No terminator")
  #expect(update.stableText == "")
  #expect(update.provisionalTail == "No terminator")
}

@Test func oneTerminatorStabilizesThatClause() throws {
  var state = StreamingTranscriptState()
  let update = try state.accept(generation: 1, fullText: "First. Second")
  #expect(update.stableText == "First. ")
  #expect(update.provisionalTail == "Second")
}

@Test func twoTerminatorsKeepTheNewestTwoClausesMutable() throws {
  var state = StreamingTranscriptState()
  let update = try state.accept(
    generation: 1,
    fullText: "First. Second. Third"
  )
  #expect(update.stableText == "First. ")
  #expect(update.provisionalTail == "Second. Third")
}

@Test func threeTerminatorsKeepTheNewestTwoClausesMutable() throws {
  var state = StreamingTranscriptState()
  let update = try state.accept(
    generation: 1,
    fullText: "First. Second. Third. Fourth"
  )
  #expect(update.stableText == "First. Second. ")
  #expect(update.provisionalTail == "Third. Fourth")
}

@Test func staleGenerationAndStableRegressionAreRejected() throws {
  var state = StreamingTranscriptState()
  _ = try state.accept(generation: 2, fullText: "Alpha. Beta")
  #expect(throws: StreamingTranscriptStateError.staleGeneration) {
    try state.accept(generation: 2, fullText: "Alpha. Gamma")
  }
  #expect(throws: StreamingTranscriptStateError.stablePrefixChanged) {
    try state.accept(generation: 3, fullText: "Changed. Beta")
  }
}

@Test func mutableTailNeverExceedsEightyCleanupLexemes() throws {
  var state = StreamingTranscriptState()
  let lexicalUnits = String(repeating: "字，", count: 81) + "尾"
  let update = try state.accept(generation: 1, fullText: lexicalUnits)
  #expect(CleanupLexeme.tokenCount(update.provisionalTail) <= 80)
}

@Test func noSpaceMandarinKeepsOnlyNewestTwoClausesMutable() throws {
  var state = StreamingTranscriptState()
  let update = try state.accept(
    generation: 1,
    fullText: "第一句。第二句！第三句？第四句"
  )
  #expect(update.stableText == "第一句。第二句！")
  #expect(update.provisionalTail == "第三句？第四句")
}

@Test func whitespaceAfterTerminatorBelongsToStablePrefix() throws {
  var state = StreamingTranscriptState()
  let update = try state.accept(generation: 1, fullText: "First. Second")
  #expect(update.stableText == "First. ")
  #expect(update.provisionalTail == "Second")
}

@Test func mixedLanguageTerminatorsDoNotRequireWhitespace() throws {
  var state = StreamingTranscriptState()
  let update = try state.accept(
    generation: 1,
    fullText: "你好。send report!下一句"
  )
  #expect(update.stableText == "你好。")
  #expect(update.provisionalTail == "send report!下一句")
}
