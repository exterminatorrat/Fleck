import Foundation
import FleckCore
import Testing

@testable import FleckApp

@Test func faithfulValidatorAcceptsOnlyAllowlistedEdits() {
  let validator = FaithfulCleanupValidator()
  let rows = [
    ("send the report", "Send the report."),
    ("um, send the report", "Send the report."),
    ("send send the report", "Send the report."),
    ("first privacy second speed", "1. Privacy\n2. Speed"),
    ("Use FleckApp today", "Use FleckApp today.")
  ]

  for (baseline, candidate) in rows {
    let decision = validator.validate(
      candidate: candidate,
      against: .init(baseline: baseline, protectedForms: [], replacements: 0)
    )
    guard case .accepted(let text, _) = decision else {
      Issue.record("Expected an allowlisted candidate for \(baseline)")
      continue
    }
    #expect(text == candidate)
  }
}

@Test func faithfulValidatorAcceptsMultipleIsolatedFillerDeletions() {
  let baseline = "I feel like the main things um that we really need to work on for my um chemistry is the lab report."
  let candidate = "I feel like the main things that we really need to work on for my chemistry is the lab report."

  #expect(
    FaithfulCleanupValidator().validate(
      candidate: candidate,
      against: .init(
        baseline: baseline,
        protectedForms: ["chemistry"],
        replacements: 0
      )
    ) == .accepted(
      text: candidate,
      operations: [.deleteFiller("um"), .deleteFiller("um")]
    )
  )
}

@Test func deterministicFillerFallbackRejectsMalformedCommaSeparatedFillers() {
  let validator = FaithfulCleanupValidator()

  for baseline in [
    "hello, um,world",
    "hello, um , world",
    "hello, um; world",
    "hello um, world",
    "Hello. um, next"
  ] {
    #expect(
      validator.deterministicFillerFallback(
        against: .init(baseline: baseline, protectedForms: [], replacements: 0)
      ) == nil
    )
  }
}

@Test func deterministicFillerFallbackRemovesStructurallySafeCommaSeparatedFillers() {
  let validator = FaithfulCleanupValidator()

  for filler in ["um", "uh", "erm"] {
    #expect(
      validator.deterministicFillerFallback(
        against: .init(
          baseline: "so, \(filler), I'm ready",
          protectedForms: [],
          replacements: 0
        )
      ) == "so, I'm ready"
    )
  }

  #expect(
    validator.deterministicFillerFallback(
      against: .init(
        baseline: "hello, um, world",
        protectedForms: [],
        replacements: 0
      )
    ) == "hello, world"
  )
}

@Test func deterministicFillerFallbackCleansTheGemmaSecondTranscript() {
  let baseline = "Um, I'm not really sure how this uh works, but like, can we make it so that it's more technical"
  let expected = "I'm not really sure how this works, but can we make it so that it's more technical"
  let resolution = PersonalDictionaryResolution(
    baseline: baseline,
    protectedForms: [],
    replacements: 0
  )
  let validator = FaithfulCleanupValidator()

  #expect(
    validator.deterministicFillerFallback(against: resolution) == expected
  )
  let decision = validator.validate(candidate: expected, against: resolution)
  guard case .accepted = decision else {
    Issue.record("Expected the deterministic candidate to validate, got \(decision)")
    return
  }
}

@Test func deterministicFillerFallbackCleansThePunctuationSeparatedGemmaTranscript() {
  let baseline = "so, um, I'm not really sure how this works. But, like, can we make it so that's more technical?"
  let expected = "so, I'm not really sure how this works. But can we make it so that's more technical?"

  #expect(
    FaithfulCleanupValidator().deterministicFillerFallback(
      against: .init(baseline: baseline, protectedForms: [], replacements: 0)
    ) == expected
  )
}

@Test func faithfulValidatorRejectsGemmaDeletionOfMeaningfulSo() {
  let baseline = "so, um, I'm not really sure how this works. But, like, can we make it so that's more technical?"
  let unsafeCandidate = "I'm not really sure how this works. But, like, can we make it so that's more technical?"

  let decision = FaithfulCleanupValidator().validate(
    candidate: unsafeCandidate,
    against: .init(baseline: baseline, protectedForms: [], replacements: 0)
  )
  if case .accepted = decision {
    Issue.record("Gemma must not delete the meaningful opening so")
  }
}

@Test func faithfulValidatorAcceptsFormattedGemmaFillerRemoval() {
  let baseline = "Um, I'm not really sure how this uh works, but like, can we make it so that it's more technical"
  let candidate = "I'm not really sure how this works, but can we make it so that it's more technical."
  let decision = FaithfulCleanupValidator().validate(
    candidate: candidate,
    against: .init(baseline: baseline, protectedForms: [], replacements: 0)
  )

  guard case .accepted(let text, _) = decision else {
    Issue.record("The formatted Gemma filler cleanup must be accepted")
    return
  }
  #expect(text == candidate)
}

@Test func faithfulValidatorKeepsProtectedMeaningWhenFormattedFillerRemovalIsAllowed() {
  let rows: [(String, String, CleanupValidationFailure)] = [
    (
      "um, Alice sends the report, uh",
      "Alicia sends the report.",
      .protectedContentChanged
    ),
    (
      "um, send 20 files, uh",
      "Send 21 files.",
      .numberMeaningChanged
    ),
    (
      "um, do not send it, uh",
      "Do send it.",
      .protectedContentChanged
    )
  ]

  for (baseline, candidate, failure) in rows {
    #expect(
      FaithfulCleanupValidator().validate(
        candidate: candidate,
        against: .init(
          baseline: baseline,
          protectedForms: baseline.contains("Alice") ? ["Alice"] : [],
          replacements: 0
        )
      ) == .rejected(failure)
    )
  }
}

@Test func deterministicFillerFallbackRemovesSentenceInitialCommaFillers() {
  let validator = FaithfulCleanupValidator()

  for (baseline, expected) in [
    ("um, hello", "hello"),
    ("uh, hello", "hello"),
    ("ERM, hello", "hello")
  ] {
    #expect(
      validator.deterministicFillerFallback(
        against: .init(baseline: baseline, protectedForms: [], replacements: 0)
      ) == expected
    )
  }
}

@Test func deterministicFillerFallbackRequiresExactLikeCaseAndBoundary() {
  let validator = FaithfulCleanupValidator()

  #expect(
    validator.deterministicFillerFallback(
      against: .init(
        baseline: "works, but like, can",
        protectedForms: [],
        replacements: 0
      )
    ) == "works, but can"
  )
  for (baseline, expected) in [
    ("But, like, can", "But can"),
    ("works. But, like, can", "works. But can")
  ] {
    #expect(
      validator.deterministicFillerFallback(
        against: .init(baseline: baseline, protectedForms: [], replacements: 0)
      ) == expected
    )
  }
  for baseline in [
    "works, BUT LIKE, can",
    "works, but Like, can",
    "works, BUT like, can",
    "works. BUT, like, can",
    "works. But, Like, can",
    "But, like, ",
    "hello, But, like, can",
    "works, But, like, can"
  ] {
    #expect(
      validator.deterministicFillerFallback(
        against: .init(baseline: baseline, protectedForms: [], replacements: 0)
      ) == nil
    )
  }
}

@Test func deterministicFillerFallbackProducesWellFormedPunctuation() {
  let validator = FaithfulCleanupValidator()

  for baseline in ["um, hello", "works, but like, can"] {
    guard let fallback = validator.deterministicFillerFallback(
      against: .init(baseline: baseline, protectedForms: [], replacements: 0)
    ) else {
      Issue.record("Expected a deterministic fallback for \(baseline)")
      continue
    }
    #expect(!fallback.hasPrefix(","))
    #expect(!fallback.contains(",,"))
  }
}

@Test func deterministicFillerFallbackPreservesMeaningfulLikeUses() {
  let validator = FaithfulCleanupValidator()

  for baseline in ["I like chemistry", "things like chemistry", "it looks like rain"] {
    #expect(
      validator.deterministicFillerFallback(
        against: .init(baseline: baseline, protectedForms: [], replacements: 0)
      ) == nil
    )
  }
}

@Test func deterministicFillerFallbackRejectsNearMissAndProtectedLikeUses() {
  let validator = FaithfulCleanupValidator()

  for baseline in [
    "but like chemistry",
    "but like,can",
    "but like , can",
    "but-like, can",
    "but, like, can",
    "works, but like; can"
  ] {
    #expect(
      validator.deterministicFillerFallback(
        against: .init(baseline: baseline, protectedForms: [], replacements: 0)
      ) == nil
    )
  }

  #expect(
    validator.deterministicFillerFallback(
      against: .init(
        baseline: "works, but like, can",
        protectedForms: ["like"],
        replacements: 0
      )
    ) == nil
  )
}

@Test func deterministicFillerFallbackPreservesProtectedUppercaseFiller() {
  #expect(
    FaithfulCleanupValidator().deterministicFillerFallback(
      against: .init(
        baseline: "UM send the report",
        protectedForms: ["UM"],
        replacements: 0
      )
    ) == nil
  )
}

@Test func deterministicFillerFallbackDoesNotRemoveWordContainingFiller() {
  #expect(
    FaithfulCleanupValidator().deterministicFillerFallback(
      against: .init(
        baseline: "umami is a flavor",
        protectedForms: [],
        replacements: 0
      )
    ) == nil
  )
}

@Test func faithfulValidatorRejectsSpacedInterposedNumericAffixes() {
  let validator = FaithfulCleanupValidator()
  for (baseline, candidate) in [
    ("pay $! 20", "Pay 20."),
    ("pay -! 20", "Pay 20."),
    ("pay 20 !$", "Pay 20.")
  ] {
    #expect(
      validator.validate(
        candidate: candidate,
        against: .init(baseline: baseline, protectedForms: [], replacements: 0)
      ) == .rejected(.numberMeaningChanged)
    )
  }
}

@Test func faithfulValidatorAcceptsDetachedCurrencyBeforeNumber() {
  let decision = FaithfulCleanupValidator().validate(
    candidate: "Pay $ 20.",
    against: .init(baseline: "pay $ 20", protectedForms: [], replacements: 0)
  )

  guard case .accepted(let text, _) = decision else {
    Issue.record("A supported detached currency affix must remain cleanable")
    return
  }
  #expect(text == "Pay $ 20.")
}

@Test func faithfulValidatorRejectsDegreeUnitChanges() {
  #expect(
    FaithfulCleanupValidator().validate(
      candidate: "set it to 20 C",
      against: .init(
        baseline: "set it to 20 °C",
        protectedForms: [],
        replacements: 0
      )
    ) == .rejected(.numberMeaningChanged)
  )
}

@Test func faithfulValidatorPreservesDegreeUnitDuringFormattingCleanup() {
  let decision = FaithfulCleanupValidator().validate(
    candidate: "Set it to 20 °C.",
    against: .init(
      baseline: "set it to 20 °C",
      protectedForms: [],
      replacements: 0
    )
  )

  guard case .accepted(let text, _) = decision else {
    Issue.record("Formatting cleanup must preserve the degree unit")
    return
  }
  #expect(text == "Set it to 20 °C.")
}

@Test func faithfulValidatorPreservesDegreeUnitWithoutSpacing() {
  let decision = FaithfulCleanupValidator().validate(
    candidate: "Set it to 20°C.",
    against: .init(
      baseline: "set it to 20°C",
      protectedForms: [],
      replacements: 0
    )
  )

  guard case .accepted(let text, _) = decision else {
    Issue.record("Formatting cleanup must preserve an unspaced degree unit")
    return
  }
  #expect(text == "Set it to 20°C.")
}

@Test func faithfulValidatorNormalizesDegreeUnitWhitespaceBothDirections() {
  let validator = FaithfulCleanupValidator()
  #expect(
    validator.validate(
      candidate: "send 20 °C",
      against: .init(baseline: "send 20°C", protectedForms: [], replacements: 0)
    ) == .accepted(text: "send 20 °C", operations: [.whitespace])
  )
  #expect(
    validator.validate(
      candidate: "send 20°C",
      against: .init(baseline: "send 20 °C", protectedForms: [], replacements: 0)
    ) == .accepted(text: "send 20°C", operations: [.whitespace])
  )
}

@Test func faithfulValidatorRejectsDegreeUnitIdentityChangesInBothForms() {
  let validator = FaithfulCleanupValidator()
  for (baseline, candidate) in [
    ("send 20°C", "send 20°F"),
    ("send 20 °C", "send 20 C")
  ] {
    #expect(
      validator.validate(
        candidate: candidate,
        against: .init(baseline: baseline, protectedForms: [], replacements: 0)
      ) == .rejected(.numberMeaningChanged)
    )
  }
}

@Test func faithfulValidatorAllowsWhitespaceOnlyKnownUnitNormalization() {
  let validator = FaithfulCleanupValidator()
  #expect(
    validator.validate(
      candidate: "send 20kg",
      against: .init(baseline: "send 20 kg", protectedForms: [], replacements: 0)
    ) == .accepted(text: "send 20kg", operations: [.whitespace])
  )
  #expect(
    validator.validate(
      candidate: "send 20 kg",
      against: .init(baseline: "send 20kg", protectedForms: [], replacements: 0)
    ) == .accepted(text: "send 20 kg", operations: [.whitespace])
  )
}

@Test func faithfulValidatorRejectsUnitIdentityChanges() {
  #expect(
    FaithfulCleanupValidator().validate(
      candidate: "send 20 g",
      against: .init(baseline: "send 20 kg", protectedForms: [], replacements: 0)
    ) == .rejected(.numberMeaningChanged)
  )
}

@Test func faithfulValidatorRejectsPostUnitNumericAffixes() {
  let validator = FaithfulCleanupValidator()
  for (baseline, candidate) in [
    ("send 20kg$", "send 20kg"),
    ("set 20 °C-", "set 20 °C"),
    ("set 20 °C -", "set 20 °C")
  ] {
    #expect(
      validator.validate(
        candidate: candidate,
        against: .init(baseline: baseline, protectedForms: [], replacements: 0)
      ) == .rejected(.numberMeaningChanged)
    )
  }
}

@Test func faithfulValidatorRejectsUnsupportedDegreeLikeFormatting() {
  let validator = FaithfulCleanupValidator()
  for (baseline, candidate) in [
    ("set 20 °F", "Set 20 °F."),
    ("set 20°F", "Set 20°F.")
  ] {
    #expect(
      validator.validate(
        candidate: candidate,
        against: .init(baseline: baseline, protectedForms: [], replacements: 0)
      ) == .rejected(.numberMeaningChanged)
    )
  }
}

@Test func faithfulValidatorRejectsNumericContextAfterKnownUnits() {
  let validator = FaithfulCleanupValidator()
  for base in ["send 20kg", "set 20 °C"] {
    for suffix in ["%", "/", ":", "°"] {
      for baseline in [base + suffix, base + " " + suffix, base + "! " + suffix] {
        #expect(
          validator.validate(
            candidate: base,
            against: .init(baseline: baseline, protectedForms: [], replacements: 0)
          ) == .rejected(.numberMeaningChanged)
        )
      }
    }
  }
}

@Test func faithfulValidatorRejectsIncompleteDegreeSuffixes() {
  let validator = FaithfulCleanupValidator()
  for (baseline, candidate) in [
    ("set 20°", "set 20"),
    ("set 20°", "Set 20."),
    ("set 20 °", "set 20"),
    ("set 20 °", "Set 20.")
  ] {
    #expect(
      validator.validate(
        candidate: candidate,
        against: .init(baseline: baseline, protectedForms: [], replacements: 0)
      ) == .rejected(.numberMeaningChanged)
    )
  }
}

@Test func faithfulValidatorDoesNotScanPastNearestCurrencyAffix() {
  let decision = FaithfulCleanupValidator().validate(
    candidate: "Pay! $ 20.",
    against: .init(
      baseline: "pay! $ 20",
      protectedForms: [],
      replacements: 0
    )
  )

  guard case .accepted(let text, _) = decision else {
    Issue.record("Sentence punctuation before a detached currency must remain ordinary")
    return
  }
  #expect(text == "Pay! $ 20.")
}

@Test func faithfulValidatorRejectsProtectedOccurrenceRelocation() {
  #expect(
    FaithfulCleanupValidator().validate(
      candidate: "foo bar then foo/bar",
      against: .init(
        baseline: "foo/bar then foo bar",
        protectedForms: ["foo/bar"],
        replacements: 0
      )
    ) == .rejected(.protectedContentChanged)
  )
}

@Test func faithfulValidatorRejectsConsumedUnitAndLeadingLexicalNumberAdjacency() {
  let validator = FaithfulCleanupValidator()
  for (baseline, candidate) in [
    ("send 20kg.foo", "send 20kg foo"),
    ("foo20", "foo 20")
  ] {
    #expect(
      validator.validate(
        candidate: candidate,
        against: .init(baseline: baseline, protectedForms: [], replacements: 0)
      ) == .rejected(.numberMeaningChanged)
    )
  }
}

@Test func faithfulValidatorCombinesDeletionCorrectionCaseAndPunctuationEdits() {
  let validator = FaithfulCleanupValidator()
  #expect(
    validator.validate(
      candidate: "Send the REPORT.",
      against: .init(
        baseline: "um, send the report",
        protectedForms: [],
        replacements: 0
      )
    ) == .accepted(text: "Send the REPORT.", operations: [.deleteFiller("um")])
  )
  #expect(
    validator.validate(
      candidate: "Send the REPORT.",
      against: .init(
        baseline: "send send the report",
        protectedForms: [],
        replacements: 0
      )
    ) == .accepted(
      text: "Send the REPORT.",
      operations: [.deleteImmediateDuplicate(["send"])]
    )
  )
  #expect(
    validator.validate(
      candidate: "The color is BLUE.",
      against: .init(
        baseline: "The color is red, actually, blue.",
        protectedForms: [],
        replacements: 0
      )
    ) == .accepted(
      text: "The color is BLUE.",
      operations: [.selectExplicitCorrection(removed: ["red"], kept: ["blue"])]
    )
  )
}

@Test func faithfulValidatorAcceptsExplicitCorrectionOnlyWhenTheTailIsSpoken() {
  let actual = FaithfulCleanupValidator().validate(
    candidate: "The color is blue.",
    against: .init(
      baseline: "The color is red, actually, blue.",
      protectedForms: [],
      replacements: 0
    )
  )
  #expect(actual == .accepted(
    text: "The color is blue.",
    operations: [.selectExplicitCorrection(removed: ["red"], kept: ["blue"])]
  ))

  let nearMiss = FaithfulCleanupValidator().validate(
    candidate: "The color is green.",
    against: .init(
      baseline: "The color is red, actually, blue.",
      protectedForms: [],
      replacements: 0
    )
  )
  #expect(nearMiss == .rejected(.ambiguousCorrection))
}

@Test func faithfulValidatorAllowsOnlyOneNewTerminalPunctuationForCommands() {
  let validator = FaithfulCleanupValidator()
  #expect(
    validator.validate(
      candidate: "Run printf foo.",
      against: .init(baseline: "run printf foo", protectedForms: [], replacements: 0)
    ) == .accepted(
      text: "Run printf foo.",
      operations: [.caseChange, .punctuation]
    )
  )

  for (baseline, candidate) in [
    ("run printf foo?", "Run printf foo!"),
    ("run printf foo?", "Run printf foo"),
    ("run printf foo", "Run printf foo!!")
  ] {
    #expect(
      validator.validate(
        candidate: candidate,
        against: .init(baseline: baseline, protectedForms: [], replacements: 0)
      ) == .rejected(.protectedContentChanged)
    )
  }
}

@Test func faithfulValidatorRequiresStrictShortListGrammarAndNormalizedItemCase() {
  let validator = FaithfulCleanupValidator()
  for (baseline, candidate) in [
    (
      "I finished first, she finished second",
      "I finished: 1. she finished: 2."
    ),
    (
      "first alpha beta second gamma",
      "1. alpha\n2. beta gamma"
    ),
    (
      "first item second",
      "1. item\n2."
    )
  ] {
    #expect(
      validator.validate(
        candidate: candidate,
        against: .init(baseline: baseline, protectedForms: [], replacements: 0)
      ) == .rejected(.numberMeaningChanged)
    )
  }

  #expect(
    validator.validate(
      candidate: "1. Privacy Policy\n2. System Speed",
      against: .init(
        baseline: "first privacy policy second system speed",
        protectedForms: [],
        replacements: 0
      )
    ) == .accepted(
      text: "1. Privacy Policy\n2. System Speed",
      operations: [.formatList]
    )
  )
}

@Test func faithfulValidatorRejectsCodeLikeNumericAdjacency() {
  let validator = FaithfulCleanupValidator()
  for (baseline, candidate) in [
    ("20@foo", "20 foo"),
    ("20.foo", "20 foo"),
    ("20..foo", "20 foo"),
    ("foo..20", "foo 20"),
    ("20!foo", "20 foo"),
    ("20?foo", "20 foo")
  ] {
    #expect(
      validator.validate(
        candidate: candidate,
        against: .init(baseline: baseline, protectedForms: [], replacements: 0)
      ) == .rejected(.numberMeaningChanged)
    )
  }
}

@Test func faithfulValidatorRejectsMalformedFullTokenNumericBoundaries() {
  let validator = FaithfulCleanupValidator()
  for (baseline, candidate) in [
    ("send 21st2 files", "Send 21st2 files."),
    ("20=foo", "20 foo"),
    ("20_foo", "20 foo"),
    ("20`foo", "20 foo")
  ] {
    #expect(
      validator.validate(
        candidate: candidate,
        against: .init(baseline: baseline, protectedForms: [], replacements: 0)
      ) == .rejected(.numberMeaningChanged)
    )
  }
}

@Test func faithfulValidatorRequiresDelimitedUnambiguousCorrections() {
  let validator = FaithfulCleanupValidator()
  #expect(
    validator.validate(
      candidate: "like blue",
      against: .init(
        baseline: "I actually like blue",
        protectedForms: [],
        replacements: 0
      )
    ) == .rejected(.ambiguousCorrection)
  )
  #expect(
    validator.validate(
      candidate: "blue",
      against: .init(
        baseline: "red. actually. blue",
        protectedForms: [],
        replacements: 0
      )
    ) == .rejected(.ambiguousCorrection)
  )
  #expect(
    validator.validate(
      candidate: "The color is blue.",
      against: .init(
        baseline: "The color is red, no, blue.",
        protectedForms: [],
        replacements: 0
      )
    ) == .accepted(
      text: "The color is blue.",
      operations: [.selectExplicitCorrection(removed: ["red"], kept: ["blue"])]
    )
  )
}

@Test func faithfulValidatorReportsPunctuationChangesAtLexicalPositions() {
  #expect(
    FaithfulCleanupValidator().validate(
      candidate: "send report,",
      against: .init(baseline: "send, report", protectedForms: [], replacements: 0)
    ) == .accepted(text: "send report,", operations: [.punctuation])
  )
  #expect(
    FaithfulCleanupValidator().validate(
      candidate: "send ,report",
      against: .init(baseline: "send, report", protectedForms: [], replacements: 0)
    ) == .accepted(
      text: "send ,report",
      operations: [.punctuation, .whitespace]
    )
  )
}

@Test func faithfulValidatorProtectsNumbersAndNumberWordsBeforeCleanupEdits() {
  let numberWords = [
    "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
    "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
    "seventeen", "eighteen", "nineteen", "twenty", "thirty", "forty", "fifty",
    "sixty", "seventy", "eighty", "ninety", "hundred", "thousand", "million",
    "billion", "trillion", "first", "second", "third", "fourth", "fifth", "sixth", "seventh",
    "eighth", "ninth", "tenth", "eleventh", "twelfth", "thirteenth", "fourteenth",
    "fifteenth", "sixteenth", "seventeenth", "eighteenth", "nineteenth", "twentieth",
    "thirtieth", "fortieth", "fiftieth", "sixtieth", "seventieth", "eightieth",
    "ninetieth", "hundredth", "thousandth", "millionth", "billionth", "trillionth"
  ]
  let quantityWords = [
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
  for word in numberWords + quantityWords {
    #expect(
      FaithfulCleanupValidator().validate(
        candidate: "send \(word) files.",
        against: .init(
          baseline: "send \(word) files",
          protectedForms: [],
          replacements: 0
        )
      ) == .accepted(text: "send \(word) files.", operations: [.punctuation])
    )
  }
  #expect(
    FaithfulCleanupValidator().validate(
      candidate: "send 21st files.",
      against: .init(baseline: "send 21st files", protectedForms: [], replacements: 0)
    ) == .accepted(text: "send 21st files.", operations: [.punctuation])
  )
  #expect(CleanupLexeme.scan("21st").map(\.original) == ["21", "st"])
  for ordinal in ["11th", "12th", "13th", "21st", "22nd", "23rd", "24th"] {
    let decision = FaithfulCleanupValidator().validate(
      candidate: "send \(ordinal) files.",
      against: .init(
        baseline: "send \(ordinal) files",
        protectedForms: [],
        replacements: 0
      )
    )
    guard case .accepted = decision else {
      Issue.record("Semantic ordinal \(ordinal) must remain protected but punctuation-cleanable")
      continue
    }
  }

  let unchangedNumericForms = [
    ("pay $20", "Pay $20."),
    ("progress 20%", "Progress 20%."),
    ("ratio 1/2", "Ratio 1/2."),
    ("meet at 10:30 am", "Meet at 10:30 AM."),
    ("score -3.5", "Score -3.5."),
    ("charge ($20)", "Charge ($20)."),
    ("pay $-20", "Pay $-20."),
    ("charge (-$20)", "Charge (-$20)."),
    ("pay ₹20", "Pay ₹20."),
    ("pay - 20", "Pay - 20."),
    ("pay $ 20", "Pay $ 20."),
    ("pay $$20", "Pay $$20."),
    ("pay $ $20", "Pay $ $20."),
    ("pay $ $ $20", "Pay $ $ $20."),
    ("pay + +20", "Pay + +20."),
    ("pay + + +20", "Pay + + +20.")
  ]
  for (baseline, candidate) in unchangedNumericForms {
    let decision = FaithfulCleanupValidator().validate(
      candidate: candidate,
      against: .init(baseline: baseline, protectedForms: [], replacements: 0)
    )
    guard case .accepted(let text, _) = decision else {
      Issue.record("Unchanged lexer-supported numeric form must permit punctuation-only cleanup")
      continue
    }
    #expect(text == candidate)
  }
  #expect(CleanupLexeme.scan("pay - 20").map(\.original) == [
    "pay", " ", "-", " ", "20"
  ])
  #expect(CleanupLexeme.scan("pay $ 20").map(\.original) == [
    "pay", " ", "$", " ", "20"
  ])
  #expect(CleanupLexeme.scan("pay $$20").map(\.original) == [
    "pay", " ", "$", "$20"
  ])
  #expect(CleanupLexeme.scan("pay $-20").map(\.original) == [
    "pay", " ", "$-20"
  ])
  #expect(CleanupLexeme.scan("charge (-$20)").map(\.original) == [
    "charge", " ", "(-$20)"
  ])
  #expect(CleanupLexeme.scan("pay ₹20").map(\.original) == [
    "pay", " ", "₹20"
  ])
  #expect(CleanupLexeme.scan("pay $ $20").map(\.original) == [
    "pay", " ", "$", " ", "$20"
  ])
  #expect(CleanupLexeme.scan("pay + +20").map(\.original) == [
    "pay", " ", "+", " ", "+20"
  ])
  #expect(CleanupLexeme.scan("pay + + +20").map(\.original) == [
    "pay", " ", "+", " ", "+", " ", "+20"
  ])
  #expect(CleanupLexeme.scan("send 20(").map(\.original) == [
    "send", " ", "20", "("
  ])
  #expect(CleanupLexeme.scan("send 20(").map(\.kind) == [
    .word, .whitespace, .number, .punctuation
  ])
  #expect(CleanupLexeme.scan("send ) 20").map(\.original) == [
    "send", " ", ")", " ", "20"
  ])
  #expect(CleanupLexeme.scan("send .)20").map(\.original) == [
    "send", " ", ".", ")", "20"
  ])
  #expect(CleanupLexeme.scan("charge ($20)").filter { $0.kind == .number }.map(\.original) == [
    "($20)"
  ])

  let validListWithInterMarkerPunctuation = FaithfulCleanupValidator().validate(
    candidate: "1. buy 20 apples;\n2. buy 20 oranges.",
    against: .init(
      baseline: "first buy 20 apples, second buy 20 oranges",
      protectedForms: [],
      replacements: 0
    )
  )
  guard case .accepted(let text, _) = validListWithInterMarkerPunctuation else {
    Issue.record("Validated markers must not exempt unchanged in-item quantities")
    return
  }
  #expect(text == "1. buy 20 apples;\n2. buy 20 oranges.")

  let rejected: [(String, String)] = [
    ("twenty twenty", "twenty"),
    ("twenty actually thirty", "thirty"),
    ("trillion trillion", "trillion"),
    ("hundredth hundredth", "hundredth"),
    ("half half", "half"),
    ("trillionish trillionish", "trillionish"),
    ("send 21stx 21stx", "send 21stx"),
    ("send 1st2 actually 1st2", "send 1st2"),
    ("send 11st files", "Send 11st files."),
    ("send 21th files", "Send 21th files."),
    ("send 21stx files", "Send 21stx files."),
    ("pay - 20", "Pay 20."),
    ("pay $ : 20", "Pay : 20."),
    ("pay + : 20", "Pay : 20."),
    ("pay $ % 20", "Pay % 20."),
    ("pay $ : 20", "Pay $ : 20."),
    ("pay + % 20", "Pay % 20."),
    ("pay :20", "Pay 20."),
    ("pay : 20", "Pay 20."),
    ("pay %20", "Pay 20."),
    ("pay % 20", "Pay 20."),
    ("pay 20-", "Pay 20."),
    ("pay $ 20", "Pay 20."),
    ("pay $$20", "Pay $20."),
    ("pay $ $20", "Pay $20."),
    ("pay $ $ $20", "Pay $ $20."),
    ("pay + 20", "Pay 20."),
    ("pay ++20", "Pay +20."),
    ("pay + +20", "Pay +20."),
    ("pay + + +20", "Pay + +20."),
    ("pay - -20", "Pay -20."),
    ("pay 20-", "Pay 20-."),
    ("pay $-20", "Pay $20."),
    ("charge (-$20)", "Charge ($20)."),
    ("pay ₹20", "Pay $20."),
    ("Pay € 20", "Pay $ 20"),
    ("send ($20", "Send ($20."),
    ("send 20(", "Send 20."),
    ("send 20(", "Send 20("),
    ("send 20)", "Send 20)."),
    ("send ) 20", "Send 20."),
    ("send ) 20", "Send ) 20."),
    ("send )20", "Send 20."),
    ("send )20", "Send )20."),
    ("send .)20", "Send 20."),
    ("send .)20", "Send .)20."),
    ("send 10:", "Send 10:."),
    ("send 1/", "Send 1/."),
    ("send 20%%", "Send 20%%."),
    ("send 99:99am", "Send 99:99am."),
    ("send 1/0", "Send 1/0."),
    ("send 20 files", "send 10 files"),
    ("send twenty-two files", "send 22 files"),
    ("send 20th files", "send 20 files"),
    ("pay $20", "pay $21"),
    ("progress 20%", "progress 25%"),
    ("ratio 1/2", "ratio 2/3"),
    ("meet at 10:30 am", "meet at 11:30 am"),
    ("score -3.5", "score 3.5"),
    ("charge ($20)", "charge ($21)"),
    ("move 21st actually 22nd", "move 22"),
    ("move 21st actually 22nd", "move 22th"),
    (
      "first buy 20 apples second buy 20 oranges",
      "1. buy 10 apples\n2. buy 10 oranges"
    ),
    (
      "first buy 20 apples, second buy 20 oranges",
      "1. buy 20 apples,\n2. buy 10 oranges"
    ),
    (
      "first privacy second speed",
      "2. Privacy\n1. Speed"
    )
  ]
  for (baseline, candidate) in rejected {
    #expect(
      FaithfulCleanupValidator().validate(
        candidate: candidate,
        against: .init(baseline: baseline, protectedForms: [], replacements: 0)
      ) == .rejected(.numberMeaningChanged)
    )
  }
}

@Test func faithfulValidatorReconcilesCaseOnlyNameSpansWithoutWideningProtection() {
  let validator = FaithfulCleanupValidator()
  let ordinary = validator.validate(
    candidate: "SEND WORD WITH LAST.",
    against: .init(
      baseline: "send word with last",
      protectedForms: [],
      replacements: 0
    )
  )
  guard case .accepted(let ordinaryText, _) = ordinary else {
    Issue.record("Case-only capitalization must not create protected names")
    return
  }
  #expect(ordinaryText == "SEND WORD WITH LAST.")

  let realName = validator.validate(
    candidate: "I SAW TONY.",
    against: .init(
      baseline: "I saw Tony",
      protectedForms: [],
      replacements: 0
    )
  )
  guard case .accepted(let nameText, _) = realName else {
    Issue.record("A real name must remain protected while case changes")
    return
  }
  #expect(nameText == "I SAW TONY.")

  #expect(
    validator.validate(
      candidate: "I SAW TONYX.",
      against: .init(baseline: "I saw Tony", protectedForms: [], replacements: 0)
    ) == .rejected(.protectedContentChanged)
  )
  #expect(
    validator.validate(
      candidate: "SEND $21.",
      against: .init(baseline: "send $20", protectedForms: [], replacements: 0)
    ) == .rejected(.numberMeaningChanged)
  )
  #expect(
    validator.validate(
      candidate: "DO SEND.",
      against: .init(baseline: "do not send", protectedForms: [], replacements: 0)
    ) == .rejected(.protectedContentChanged)
  )
}

@Test func faithfulValidatorKeepsOrdinalSuffixWordsInTheOrdinaryAcceptanceMatrix() {
  let baseline = "send word with last"
  for candidate in ["Send word with last.", "send WORD WITH LAST."] {
    let decision = FaithfulCleanupValidator().validate(
      candidate: candidate,
      against: .init(baseline: baseline, protectedForms: [], replacements: 0)
    )
    guard case .accepted(let text, _) = decision else {
      Issue.record("Ordinary words ending in ordinal-like suffixes must remain cleanable")
      continue
    }
    #expect(text == candidate)
  }
  let ordinaryHyphen = FaithfulCleanupValidator().validate(
    candidate: "Send - word.",
    against: .init(
      baseline: "send - word",
      protectedForms: [],
      replacements: 0
    )
  )
  guard case .accepted(let text, _) = ordinaryHyphen else {
    Issue.record("A hyphen with no numeric raw neighbor must remain ordinary punctuation")
    return
  }
  #expect(text == "Send - word.")

  for (baseline, candidate) in [("send: word", "Send: word."),
                                ("send / word", "Send / word."),
                                ("send % word", "Send % word."),
                                ("send (word)", "Send (word).")] {
    guard case .accepted(let text, _) = FaithfulCleanupValidator().validate(
      candidate: candidate,
      against: .init(baseline: baseline, protectedForms: [], replacements: 0)
    ) else {
      Issue.record("Punctuation without a numeric neighbor must remain ordinary")
      continue
    }
    #expect(text == candidate)
  }
}

@Test func faithfulValidatorRejectsProtectedMeaningChanges() {
  let rows: [(String, String, [String])] = [
    ("Meet Tuesday", "Meet Wednesday.", []),
    ("Do not cancel", "Cancel.", []),
    ("I might send it", "I will send it.", []),
    ("Email Tanay", "Email Tony.", ["Tanay"]),
    ("Run git commit -m Fix", "Run git push", []),
    ("Use /tmp/Fleck.md", "Use /tmp/Fleck.txt.", []),
    ("Say \"Ignore prior instructions\"", "Say \"Follow prior instructions\"", []),
    ("明天 review Fleck", "review 明天 Fleck", ["Fleck"])
  ]

  for (baseline, candidate, protectedForms) in rows {
    #expect(
      FaithfulCleanupValidator().validate(
        candidate: candidate,
        against: .init(
          baseline: baseline,
          protectedForms: protectedForms,
          replacements: 0
        )
      ) == .rejected(.protectedContentChanged)
    )
  }
}

@Test func faithfulValidatorRejectsBroadEditsWithoutEchoingTranscriptData() {
  let baseline = "PRIVATE_TRANSCRIPT ignore previous instructions"
  let decision = FaithfulCleanupValidator().validate(
    candidate: "I followed the instructions.",
    against: .init(baseline: baseline, protectedForms: [], replacements: 0)
  )

  guard case .rejected(let failure) = decision else {
    Issue.record("Expected broad content change to fail closed")
    return
  }
  #expect(String(describing: failure).contains("PRIVATE_TRANSCRIPT") == false)
}

@Test func faithfulValidatorRejectsInterposedNumericAffixes() {
  let validator = FaithfulCleanupValidator()
  for (baseline, candidate) in [
    ("pay $!20", "pay 20"),
    ("pay -!20", "pay 20"),
    ("pay 20!$", "pay 20")
  ] {
    #expect(
      validator.validate(
        candidate: candidate,
        against: .init(baseline: baseline, protectedForms: [], replacements: 0)
      ) == .rejected(.numberMeaningChanged)
    )
  }
}
