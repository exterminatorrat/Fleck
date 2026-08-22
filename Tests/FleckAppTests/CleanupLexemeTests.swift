import Testing

@testable import FleckApp

@Test func lexemesIgnoreCaseAndPunctuationForWordComparison() {
  let values = CleanupLexeme.scan("Send, FLECKApp!")
  #expect(values.filter(\.isLexical).map(\.canonical) == ["send", "fleckapp"])
  #expect(values.map(\.original) == ["Send", ",", " ", "FLECKApp", "!"])
}

@Test func lexemesKeepHanCharactersInOrder() {
  let values = CleanupLexeme.scan("明天下午三点。")
  #expect(values.filter(\.isLexical).map(\.canonical).joined() == "明天下午三点")
  #expect(values.last?.kind == .punctuation)
}

@Test func lexemesKeepSpecialRunsWholeBeforePunctuation() {
  let values = CleanupLexeme.scan("Use /tmp/Fleck.md, https://fleck.app, and hi@fleck.app.")
  #expect(values.contains { $0.original == "/tmp/Fleck.md" && $0.kind == .path })
  #expect(values.contains { $0.original == "https://fleck.app" && $0.kind == .url })
  #expect(values.contains { $0.original == "hi@fleck.app" && $0.kind == .email })
  #expect(values.contains { $0.original == "." && $0.kind == .punctuation })
}

@Test func lexemesKeepNumericExpressionsAsSingleLexemes() {
  let values = CleanupLexeme.scan("3 3.5 $4.20 20% 16 GB 3pm 2026-08-10 $-20 -$20 €−20 ₩20 ₽20 −5 20¢")
  #expect(
    values.filter { $0.kind == .number }.map(\.original)
      == ["3", "3.5", "$4.20", "20%", "16", "3pm", "2026-08-10", "$-20", "-$20", "€−20", "₩20", "₽20", "−5", "20¢"]
  )
}

@Test func lexemesKeepSeparatedCurrencyAdjacentToNumbers() {
  let values = CleanupLexeme.scan("€ 20")
  #expect(values.map(\.original) == ["€", " ", "20"])
  #expect(values.first?.kind == .punctuation)
  #expect(values.last?.kind == .number)
}

@Test func lexemesUseCanonicalUnicodeCompositionWithoutTransliteration() {
  let composed = "José"
  let decomposed = "Jose\u{301}"
  let composedValue = CleanupLexeme.scan(composed).filter(\.isLexical).map(\.canonical)
  let decomposedValue = CleanupLexeme.scan(decomposed).filter(\.isLexical).map(\.canonical)
  #expect(composedValue == decomposedValue)
  #expect(CleanupLexeme.scan("Fleck 明天下午 3pm").filter(\.isLexical).map(\.canonical) == ["fleck", "明天下午", "3pm"])
}

@Test func lexemesClassifyCodeLikeRunsWithoutExecutingThem() {
  let values = CleanupLexeme.scan("git commit -m Fix foo.bar() --offline")
  #expect(values.contains { $0.original == "foo.bar()" && $0.kind == .code })
  #expect(values.contains { $0.original == "--offline" && $0.kind == .code })
  #expect(values.filter(\.isLexical).map(\.canonical).contains("git"))
}

@Test func lexemesScanLongPunctuationOnlyInputWithoutSpecialRunWork() {
  let input = String(repeating: "!?", count: 10_000)
  let values = CleanupLexeme.scan(input)
  #expect(values.count == input.count)
  #expect(values.allSatisfy { $0.kind == .punctuation })
}

@Test func tokenCountCountsOnlyLexicalRuns() {
  #expect(CleanupLexeme.tokenCount("Send, the report.") == 3)
  #expect(CleanupLexeme.tokenCount("明天下午三点。") == 1)
}

@Test func lexemesSeparateUnicodeSentencePunctuationFromURLs() {
  let values = CleanupLexeme.scan("Visit https://fleck.app。")
  #expect(values.contains { $0.original == "https://fleck.app" && $0.kind == .url })
  #expect(values.contains { $0.original == "。" && $0.kind == .punctuation })
}

@Test func lexemesKeepDigitLeadingEmailWhole() {
  let values = CleanupLexeme.scan("Email 3@fleck.app.")
  #expect(values.contains { $0.original == "3@fleck.app" && $0.kind == .email })
  #expect(values.contains { $0.original == "." && $0.kind == .punctuation })
}
