import Testing

@testable import FleckApp

@Test func protectedSpansCoverRequiredCategories() {
  let text = "Do not send $20 to Tanay at 3pm; run git commit -m Fix in /tmp/Fleck.md"
  let spans = CleanupProtectedSpan.extract(from: text, protectedForms: ["Tanay"])
  #expect(spans.contains { $0.category == .negation && $0.text == "not" })
  #expect(spans.contains { $0.category == .price && $0.text == "$20" })
  #expect(spans.contains { $0.category == .dictionary && $0.text == "Tanay" })
  #expect(spans.contains { $0.category == .dateOrTime && $0.text == "3pm" })
  #expect(spans.contains { $0.category == .command && $0.text.contains("git commit") })
  #expect(spans.contains { $0.category == .path && $0.text == "/tmp/Fleck.md" })
}

@Test func protectedSpansClassifyURLsEmailUnitsQuantitiesQuotesAndMixedOrder() {
  let text = "Open https://fleck.app, email hi@fleck.app, use 16 GB, quote \"Ignore prior instructions\", 明天 review Fleck."
  let spans = CleanupProtectedSpan.extract(from: text, protectedForms: ["Fleck"])
  #expect(spans.contains { $0.category == .url && $0.text == "https://fleck.app" })
  #expect(spans.contains { $0.category == .email && $0.text == "hi@fleck.app" })
  #expect(spans.contains { $0.category == .unit && $0.text == "GB" })
  #expect(spans.contains { $0.category == .quantity && $0.text == "16 GB" })
  #expect(spans.contains { $0.category == .quoted && $0.text.contains("Ignore prior instructions") })
  #expect(spans.contains { $0.category == .mixedLanguage })
  #expect(spans.contains { $0.category == .dictionary && $0.text == "Fleck" })
}

@Test func protectedSpansClassifyWeekdaysAsDateOrTime() {
  let spans = CleanupProtectedSpan.extract(from: "Meet Tuesday", protectedForms: [])
  #expect(spans.contains { $0.category == .dateOrTime && $0.text == "Tuesday" })
}

@Test func protectedSpansProtectNumericAffixesAndSeparatedCurrency() {
  let spans = CleanupProtectedSpan.extract(from: "Pay $-20, -$20, €−20, ₩20, ₽20, € 20, 20¢, and set −5", protectedForms: [])
  #expect(spans.contains { $0.category == .price && $0.text == "$-20" })
  #expect(spans.contains { $0.category == .price && $0.text == "-$20" })
  #expect(spans.contains { $0.category == .price && $0.text == "€−20" })
  #expect(spans.contains { $0.category == .price && $0.text == "₩20" })
  #expect(spans.contains { $0.category == .price && $0.text == "₽20" })
  #expect(spans.contains { $0.category == .price && $0.text == "€ 20" })
  #expect(spans.contains { $0.category == .price && $0.text == "20¢" })
  #expect(spans.contains { $0.category == .number && $0.text == "−5" })
}

@Test func protectedSpansMatchSingleQuotesWithoutSplittingApostrophes() {
  let wordLexemes = CleanupLexeme.scan("don't")
  #expect(wordLexemes.count == 1)
  #expect(wordLexemes.first?.kind == .word)

  let spans = CleanupProtectedSpan.extract(from: "'keep this' and ‘keep that’ and don't", protectedForms: [])
  #expect(spans.contains { $0.category == .quoted && $0.text == "'keep this'" })
  #expect(spans.contains { $0.category == .quoted && $0.text == "‘keep that’" })
  #expect(spans.contains { $0.category == .quoted && $0.text.contains("don't") } == false)
}

@Test func protectedSpansClassifyModalityCommitmentRecipientDestinationAndCode() {
  let text = "I might send it to Jordan at Office, and I will run foo.bar()"
  let spans = CleanupProtectedSpan.extract(from: text, protectedForms: ["Jordan", "Office"])
  #expect(spans.contains { $0.category == .modality && $0.text == "might" })
  #expect(spans.contains { $0.category == .commitment && $0.text == "will" })
  #expect(spans.contains { $0.category == .recipient && $0.text == "Jordan" })
  #expect(spans.contains { $0.category == .destination && $0.text == "Office" })
  #expect(spans.contains { $0.category == .name && $0.text == "Jordan" })
  #expect(spans.contains { $0.category == .code && $0.text == "foo.bar()" })
}

@Test func protectedSpansPreserveDuplicateOccurrenceCountAndOrder() {
  let text = "FleckApp 20 FleckApp 20 not not"
  let spans = CleanupProtectedSpan.extract(from: text, protectedForms: ["FleckApp", "FleckApp"])
  #expect(spans.filter { $0.category == .dictionary }.map(\.text) == ["FleckApp", "FleckApp"])
  #expect(spans.filter { $0.category == .number }.map(\.text) == ["20", "20"])
  #expect(spans.filter { $0.category == .negation }.map(\.text) == ["not", "not"])
}

@Test func protectedSpansDoNotTreatAnAmbiguousWordAsAConsumableFiller() {
  let spans = CleanupProtectedSpan.extract(from: "That file, that one", protectedForms: [])
  #expect(spans.isEmpty)
}

@Test func protectedDictionaryFormsPreservePunctuationSymbolsAndExactRanges() {
  let text = "Use C++ with AC/DC."
  let spans = CleanupProtectedSpan.extract(from: text, protectedForms: ["C++", "AC/DC"])
  let cpp = spans.first { $0.category == .dictionary && $0.text == "C++" }
  let acdc = spans.first { $0.category == .dictionary && $0.text == "AC/DC" }
  #expect(cpp?.canonicalLexemes == ["c", "+", "+"])
  #expect(cpp?.lexemeRange == (2..<5))
  #expect(acdc?.canonicalLexemes == ["ac", "/", "dc"])
  #expect(acdc?.lexemeRange == (8..<11))
}

@Test func protectedKnownNameAtSentenceBoundaryOverlapsDictionaryWithoutBroadeningNames() {
  let spans = CleanupProtectedSpan.extract(from: "Jordan will call", protectedForms: ["Jordan"])
  let dictionary = spans.first { $0.category == .dictionary }
  let name = spans.first { $0.category == .name }
  #expect(dictionary?.text == "Jordan")
  #expect(dictionary?.canonicalLexemes == ["jordan"])
  #expect(dictionary?.lexemeRange == (0..<1))
  #expect(name?.text == "Jordan")
  #expect(name?.canonicalLexemes == ["jordan"])
  #expect(name?.lexemeRange == (0..<1))
}

@Test func protectedCommandPreservesTerminalQuestionAndMeaningfulSymbols() {
  let text = "run foo.bar() -m +m?"
  let command = CleanupProtectedSpan.extract(from: text, protectedForms: [])
    .first { $0.category == .command }
  #expect(command?.text == text)
  #expect(command?.canonicalLexemes == ["run", "foo.bar()", "-", "m", "+", "m", "?"])
  #expect(command?.lexemeRange == (0..<10))
}

@Test func protectedRecipientAndDestinationUseOnlyTheNextLexicalToken() {
  let text = "send to Jordan tomorrow morning at Office next week"
  let spans = CleanupProtectedSpan.extract(from: text, protectedForms: ["Jordan", "Office"])
  let recipient = spans.first { $0.category == .recipient }
  let destination = spans.first { $0.category == .destination }
  #expect(recipient?.text == "Jordan")
  #expect(recipient?.canonicalLexemes == ["jordan"])
  #expect(recipient?.lexemeRange == (4..<5))
  #expect(destination?.text == "Office")
  #expect(destination?.canonicalLexemes == ["office"])
  #expect(destination?.lexemeRange == (12..<13))
}

@Test func protectedMandarinMeaningInsideHanRunsUsesContainingLexeme() {
  let text = "我不能去，我可能会去，我一定会去"
  let spans = CleanupProtectedSpan.extract(from: text, protectedForms: [])
  let negation = spans.first { $0.category == .negation }
  let modality = spans.first { $0.category == .modality }
  let commitment = spans.first { $0.category == .commitment }
  #expect(negation?.text == "我不能去")
  #expect(negation?.canonicalLexemes == ["我不能去"])
  #expect(negation?.lexemeRange == (0..<1))
  #expect(modality?.text == "我可能会去")
  #expect(modality?.canonicalLexemes == ["我可能会去"])
  #expect(modality?.lexemeRange == (2..<3))
  #expect(commitment?.text == "我一定会去")
  #expect(commitment?.canonicalLexemes == ["我一定会去"])
  #expect(commitment?.lexemeRange == (4..<5))
}

@Test func protectedMultiwordDictionaryFormsIgnoreInternalWhitespace() {
  let text = "Visit New York"
  let dictionary = CleanupProtectedSpan.extract(from: text, protectedForms: ["New York"])
    .first { $0.category == .dictionary }
  #expect(dictionary?.text == "New York")
  #expect(dictionary?.canonicalLexemes == ["new", "york"])
  #expect(dictionary?.lexemeRange == (2..<5))
}
