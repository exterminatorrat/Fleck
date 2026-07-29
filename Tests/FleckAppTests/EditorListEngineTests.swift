import Testing

@testable import FleckApp

@Test func automaticStylesFollowDepth() {
  #expect(EditorListEngine.automaticBullet(depth: 0) == .disc)
  #expect(EditorListEngine.automaticBullet(depth: 1) == .circle)
  #expect(EditorListEngine.automaticBullet(depth: 2) == .square)
  #expect(EditorListEngine.automaticBullet(depth: 3) == .disc)
  #expect(EditorListEngine.automaticNumber(depth: 0) == .decimal)
  #expect(EditorListEngine.automaticNumber(depth: 1) == .alphabetic)
  #expect(EditorListEngine.automaticNumber(depth: 2) == .roman)
}

@Test func parserRecognizesSupportedMarkers() {
  #expect(EditorListEngine.parse("• Item")?.style == .bullet(.disc))
  #expect(EditorListEngine.parse("    ◦ Child")?.depth == 1)
  #expect(EditorListEngine.parse("▪ Item")?.style == .bullet(.square))
  #expect(EditorListEngine.parse("– Item")?.style == .bullet(.dash))
  #expect(EditorListEngine.parse("2. Item")?.style == .number(.decimal))
  #expect(EditorListEngine.parse("    b. Child")?.style == .number(.alphabetic))
  #expect(EditorListEngine.parse("    i. Ninth")?.style == .number(.alphabetic))
  #expect(EditorListEngine.parse("        i. First")?.style == .number(.roman))
  #expect(EditorListEngine.parse("        ii. Child")?.style == .number(.roman))
  #expect(EditorListEngine.parse("○ Task")?.style == .checklist)
  #expect(EditorListEngine.parse("● Done")?.isChecklistComplete == true)
  #expect(EditorListEngine.parse("not. a list") == nil)
}

@Test func parserAcceptsLegacyMarkers() {
  #expect(EditorListEngine.parse("- Legacy")?.style == .bullet(.disc))
  #expect(EditorListEngine.parse("* Legacy")?.style == .bullet(.disc))
  #expect(EditorListEngine.parse("+ Legacy")?.style == .bullet(.disc))
  #expect(EditorListEngine.parse("1) Legacy")?.style == .number(.decimal))
}

@Test func togglingListsReplacesOrRemovesMarkers() {
  #expect(
    EditorListEngine.toggle(style: .bullet(.square), in: "One\nTwo")
      == "▪ One\n▪ Two"
  )
  #expect(
    EditorListEngine.toggle(style: .bullet(.square), in: "▪ One\n▪ Two")
      == "One\nTwo"
  )
  #expect(
    EditorListEngine.toggle(style: .number(.alphabetic), in: "• One\n• Two")
      == "a. One\nb. Two"
  )
  #expect(
    EditorListEngine.toggle(style: .checklist, in: "One\n\nTwo")
      == "○ One\n\n○ Two"
  )
}

@Test func automaticListsUseEachParagraphDepth() {
  let plain = "Parent\n    Child\n        Grandchild"
  let bullets = "• Parent\n    ◦ Child\n        ▪ Grandchild"
  let numbers = "1. Parent\n    a. Child\n        i. Grandchild"

  #expect(EditorListEngine.toggleAutomatic(family: .bullets, in: plain) == bullets)
  #expect(EditorListEngine.toggleAutomatic(family: .bullets, in: bullets) == plain)
  #expect(EditorListEngine.toggleAutomatic(family: .numbers, in: plain) == numbers)
}

@Test func returnAndIndentUseListHierarchy() {
  #expect(EditorListEngine.continuation(after: "1. Parent") == "2. ")
  #expect(EditorListEngine.continuation(after: "    i. Ninth") == "    j. ")
  #expect(EditorListEngine.continuation(after: "        i. First") == "        ii. ")
  #expect(
    EditorListEngine.continuation(
      after: "    i. First",
      preferredNumberStyle: .roman
    ) == "    ii. "
  )
  #expect(EditorListEngine.continuation(after: "● Done") == "○ ")
  #expect(EditorListEngine.continuation(after: "○ ") == nil)
  #expect(EditorListEngine.indent("• Child", removing: false) == "    ◦ Child")
  #expect(EditorListEngine.indent("    a. Child", removing: true) == "1. Child")
  #expect(
    EditorListEngine.indent("1. First\n2. Second", removing: false)
      == "    a. First\n    b. Second"
  )
  #expect(EditorListEngine.indent("Plain", removing: false) == "    Plain")
  #expect(EditorListEngine.indent("Plain", removing: true) == "Plain")
  #expect(EditorListEngine.indent("5. Unchanged", removing: true) == "5. Unchanged")
}

@Test func numberingRecomputesContiguousSiblingBlocks() {
  #expect(
    EditorListEngine.renumber(
      "1. Parent\n    a. Child\n1. Sibling\nPlain\n8. Separate"
    )
      == "1. Parent\n    a. Child\n2. Sibling\nPlain\n1. Separate"
  )
}

@Test func typedPrefixesAndChecklistsNormalize() {
  #expect(EditorListEngine.normalizeTypedPrefix("- ") == "• ")
  #expect(EditorListEngine.normalizeTypedPrefix("* ") == "• ")
  #expect(EditorListEngine.normalizeTypedPrefix("+ ") == "• ")
  #expect(EditorListEngine.normalizeTypedPrefix("1) ") == "1. ")
  #expect(EditorListEngine.normalizeTypedPrefix("[] ") == "○ ")
  #expect(EditorListEngine.normalizeTypedPrefix("[ ] ") == "○ ")
  #expect(EditorListEngine.normalizeTypedPrefix("word ") == nil)
  #expect(EditorListEngine.toggleChecklist("○ Task") == "● Task")
  #expect(EditorListEngine.toggleChecklist("● Task") == "○ Task")
  #expect(EditorListEngine.toggleChecklist("• Not a task") == "• Not a task")
}
