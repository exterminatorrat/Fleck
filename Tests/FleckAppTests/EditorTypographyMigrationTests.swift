import AppKit
import Testing

@testable import FleckApp

private let migrationBodySize: CGFloat = 17

private enum LegacyEmphasis: Sendable {
  case none
  case bold
  case italic
}

private struct LegacyPreset: Sendable {
  let scale: CGFloat
  let before: CGFloat
  let after: CGFloat
  var emphasis: LegacyEmphasis = .none
  var code = false
}

private let legacyBody = LegacyPreset(scale: 1, before: 0, after: 0)
private let legacyHeading1 = LegacyPreset(
  scale: 1.75,
  before: 12,
  after: 8,
  emphasis: .bold
)
private let legacyHeading2 = LegacyPreset(
  scale: 1.5,
  before: 10,
  after: 6,
  emphasis: .bold
)
private let legacyHeading3 = LegacyPreset(
  scale: 1.25,
  before: 8,
  after: 4,
  emphasis: .bold
)
private let legacyQuote = LegacyPreset(scale: 1, before: 6, after: 6, emphasis: .italic)
private let legacyCode = LegacyPreset(scale: 1, before: 4, after: 4, code: true)

private func legacyAttributes(
  _ preset: LegacyPreset,
  family: String = EditorTypography.systemFamily
) -> [NSAttributedString.Key: Any] {
  let size = migrationBodySize * preset.scale
  let font: NSFont
  if preset.code {
    font = .monospacedSystemFont(ofSize: size, weight: .regular)
  } else {
    let manager = NSFontManager.shared
    var base = manager.convert(
      EditorTypography.bodyFont(family: family, size: size),
      toNotHaveTrait: [.boldFontMask, .italicFontMask]
    )
    switch preset.emphasis {
    case .none:
      break
    case .bold:
      base = manager.convert(base, toHaveTrait: .boldFontMask)
    case .italic:
      base = manager.convert(base, toHaveTrait: .italicFontMask)
    }
    font = base
  }
  let paragraph = NSMutableParagraphStyle()
  let lineHeight = EditorTypography.defaultLineHeight * preset.scale
  paragraph.minimumLineHeight = lineHeight
  paragraph.maximumLineHeight = lineHeight
  paragraph.lineHeightMultiple = 0
  paragraph.paragraphSpacingBefore = preset.before
  paragraph.paragraphSpacing = preset.after
  paragraph.defaultTabInterval = 36
  return [.font: font, .paragraphStyle: paragraph]
}

private func migrationStorage(_ body: String, preset: LegacyPreset) -> NSTextStorage {
  let storage = NSTextStorage()
  storage.setAttributedString(NSAttributedString(string: body, attributes: legacyAttributes(preset)))
  return storage
}

private func paragraphStyle(_ storage: NSTextStorage, at location: Int = 0) throws
  -> NSParagraphStyle
{
  try #require(
    storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
  )
}

private func migrate(_ storage: NSTextStorage) -> Int {
  EditorTypographyMigration.migrate(
    storage,
    family: EditorTypography.systemFamily,
    size: migrationBodySize,
    isListParagraph: { _ in false }
  )
}

@Test @MainActor func legacyBodyParagraphAdoptsTheBodyGrid() throws {
  let storage = migrationStorage("Body copy\n", preset: legacyBody)

  #expect(migrate(storage) == 1)

  #expect(storage.string == "Body copy\n")
  let paragraph = try paragraphStyle(storage)
  #expect(abs(paragraph.paragraphSpacingBefore) < 0.01)
  #expect(abs(paragraph.paragraphSpacing - EditorTypography.bodyParagraphSpacing) < 0.01)
  #expect(abs(paragraph.minimumLineHeight - EditorTypography.defaultLineHeight) < 0.01)
  #expect(
    abs(
      paragraph.defaultTabInterval
        - EditorTypography.indentWidth(
          font: EditorTypography.bodyFont(
            family: EditorTypography.systemFamily,
            size: migrationBodySize
          )
        )
    ) < 0.01
  )
}

@Test @MainActor func legacyQuoteAndCodeAdoptTheCurrentSpacing() throws {
  let bodyTabInterval = EditorTypography.indentWidth(
    font: EditorTypography.bodyFont(
      family: EditorTypography.systemFamily,
      size: migrationBodySize
    )
  )
  let quote = migrationStorage("Quoted line\n", preset: legacyQuote)
  let code = migrationStorage("let value = 1\n", preset: legacyCode)

  #expect(migrate(quote) == 1)
  #expect(migrate(code) == 1)

  let quoteParagraph = try paragraphStyle(quote)
  #expect(abs(quoteParagraph.paragraphSpacingBefore - 8) < 0.01)
  #expect(abs(quoteParagraph.paragraphSpacing - 8) < 0.01)
  let quoteFont = try #require(quote.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
  #expect(NSFontManager.shared.traits(of: quoteFont).contains(.italicFontMask))

  let codeParagraph = try paragraphStyle(code)
  #expect(abs(codeParagraph.paragraphSpacingBefore - 4) < 0.01)
  #expect(abs(codeParagraph.paragraphSpacing - 4) < 0.01)
  #expect(abs(codeParagraph.defaultTabInterval - bodyTabInterval) < 0.01)
}

@Test @MainActor func legacyHeadingLevelsAdoptTheCurrentHierarchy() throws {
  let cases: [(preset: LegacyPreset, scale: CGFloat, before: CGFloat, after: CGFloat)] = [
    (legacyHeading1, 1.6, 16, 8),
    (legacyHeading2, 1.35, 12, 6),
    (legacyHeading3, 1.15, 8, 4),
  ]
  for expected in cases {
    let storage = migrationStorage("Heading line\n", preset: expected.preset)

    #expect(migrate(storage) == 1)

    let paragraph = try paragraphStyle(storage)
    #expect(abs(paragraph.paragraphSpacingBefore - expected.before) < 0.01)
    #expect(abs(paragraph.paragraphSpacing - expected.after) < 0.01)
    #expect(
      abs(
        paragraph.minimumLineHeight
          - EditorTypography.defaultLineHeight * expected.scale
      ) < 0.01
    )
    let font = try #require(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
    #expect(abs(font.pointSize - migrationBodySize * expected.scale) < 0.01)
    #expect(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
  }
}

@Test @MainActor func currentPresetParagraphIsLeftByteForByte() throws {
  let body = "Heading line\nBody copy\n"
  let storage = NSTextStorage()
  storage.setAttributedString(NSAttributedString(string: body))
  let headingRange = NSRange(location: 0, length: ("Heading line\n" as NSString).length)
  let bodyRange = NSRange(location: NSMaxRange(headingRange), length: ("Body copy\n" as NSString).length)
  storage.addAttributes(
    [
      .font: EditorTypography.presetFont(
        for: .heading1,
        family: EditorTypography.systemFamily,
        size: migrationBodySize
      ),
      .paragraphStyle: EditorTypography.presetParagraphStyle(
        for: .heading1,
        family: EditorTypography.systemFamily,
        size: migrationBodySize
      ),
    ],
    range: headingRange
  )
  storage.addAttributes(
    EditorTypography.defaultAttributes(family: EditorTypography.systemFamily, size: migrationBodySize),
    range: bodyRange
  )
  let headingBefore = try paragraphStyle(storage, at: 0)
  let bodyBefore = try paragraphStyle(storage, at: headingRange.length)

  #expect(migrate(storage) == 0)

  let headingAfter = try paragraphStyle(storage, at: 0)
  let bodyAfter = try paragraphStyle(storage, at: headingRange.length)
  #expect(abs(headingAfter.minimumLineHeight - headingBefore.minimumLineHeight) < 0.01)
  #expect(abs(headingAfter.paragraphSpacingBefore - headingBefore.paragraphSpacingBefore) < 0.01)
  #expect(abs(headingAfter.paragraphSpacing - headingBefore.paragraphSpacing) < 0.01)
  #expect(abs(headingAfter.defaultTabInterval - headingBefore.defaultTabInterval) < 0.01)
  #expect(abs(bodyAfter.paragraphSpacing - bodyBefore.paragraphSpacing) < 0.01)
  #expect(abs(bodyAfter.defaultTabInterval - bodyBefore.defaultTabInterval) < 0.01)
}

@Test @MainActor func handTunedParagraphStaysExactlyAsPersisted() throws {
  let customSpacing = migrationStorage("Hand tuned copy\n", preset: legacyBody)
  customSpacing.addAttribute(
    .paragraphStyle,
    value: {
      let paragraph = NSMutableParagraphStyle()
      paragraph.minimumLineHeight = 24
      paragraph.maximumLineHeight = 24
      paragraph.paragraphSpacing = 14
      paragraph.defaultTabInterval = 36
      return paragraph
    }(),
    range: NSRange(location: 0, length: customSpacing.length)
  )

  let indented = migrationStorage("Indented copy\n", preset: legacyBody)
  indented.addAttribute(
    .paragraphStyle,
    value: {
      let paragraph = NSMutableParagraphStyle()
      paragraph.minimumLineHeight = EditorTypography.defaultLineHeight
      paragraph.maximumLineHeight = EditorTypography.defaultLineHeight
      paragraph.headIndent = 20
      paragraph.firstLineHeadIndent = 20
      paragraph.defaultTabInterval = 36
      return paragraph
    }(),
    range: NSRange(location: 0, length: indented.length)
  )

  #expect(migrate(customSpacing) == 0)
  #expect(abs(try paragraphStyle(customSpacing).paragraphSpacing - 14) < 0.01)
  #expect(migrate(indented) == 0)
  #expect(abs(try paragraphStyle(indented).headIndent - 20) < 0.01)
}

@Test @MainActor func mismatchedFontAndSpacingIsLeftAlone() throws {
  let storage = migrationStorage("Ambiguous line\n", preset: legacyBody)
  let manager = NSFontManager.shared
  storage.addAttribute(
    .font,
    value: manager.convert(
      EditorTypography.bodyFont(
        family: EditorTypography.systemFamily,
        size: migrationBodySize * 1.75
      ),
      toHaveTrait: .boldFontMask
    ),
    range: NSRange(location: 0, length: storage.length)
  )

  #expect(migrate(storage) == 0)
  #expect(abs(try paragraphStyle(storage).paragraphSpacing) < 0.01)
}

@Test @MainActor func loadingTwiceDoesNotRestyleAgain() throws {
  let storage = migrationStorage("Body copy\nHeading line\n", preset: legacyBody)
  storage.addAttributes(
    legacyAttributes(legacyHeading2),
    range: NSRange(
      location: ("Body copy\n" as NSString).length,
      length: ("Heading line\n" as NSString).length
    )
  )

  #expect(migrate(storage) == 2)

  let bodyAfterFirst = try paragraphStyle(storage, at: 0)
  let headingLocation = ("Body copy\n" as NSString).length
  let headingAfterFirst = try paragraphStyle(storage, at: headingLocation)

  #expect(migrate(storage) == 0)

  let bodyAfterSecond = try paragraphStyle(storage, at: 0)
  let headingAfterSecond = try paragraphStyle(storage, at: headingLocation)
  #expect(abs(bodyAfterSecond.paragraphSpacing - bodyAfterFirst.paragraphSpacing) < 0.01)
  #expect(
    abs(bodyAfterSecond.minimumLineHeight - bodyAfterFirst.minimumLineHeight) < 0.01
  )
  #expect(
    abs(headingAfterSecond.paragraphSpacingBefore - headingAfterFirst.paragraphSpacingBefore)
      < 0.01
  )
  #expect(
    abs(headingAfterSecond.minimumLineHeight - headingAfterFirst.minimumLineHeight) < 0.01
  )
}

@Test @MainActor func legacyHeadingsSurviveTheRichTextCodecAndStillMigrate() throws {
  let cases: [(preset: LegacyPreset, style: EditorTextStyle)] = [
    (legacyHeading1, .heading1),
    (legacyHeading2, .heading2),
    (legacyHeading3, .heading3),
  ]
  for item in cases {
    let source = NSAttributedString(
      string: "Heading line\n",
      attributes: legacyAttributes(item.preset)
    )
    let decoded = try NoteRichTextCodec.decode(NoteRichTextCodec.encode(source))
    let decodedFont = try #require(
      decoded.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    )
    #expect(abs(decodedFont.pointSize - migrationBodySize * item.preset.scale) < 0.05)
    let storage = NSTextStorage()
    storage.setAttributedString(decoded)

    #expect(migrate(storage) == 1)

    let paragraph = try paragraphStyle(storage)
    let font = try #require(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
    let expectedScale = EditorTypography.presetScale(for: item.style)
    #expect(abs(font.pointSize - migrationBodySize * expectedScale) < 0.05)
    #expect(
      abs(paragraph.minimumLineHeight - EditorTypography.defaultLineHeight * expectedScale)
        < 0.05
    )
  }
}

@Test @MainActor func legacyPresetsInANamedEditorFamilyStillMigrate() throws {
  let family = "Avenir Next"
  let storage = NSTextStorage()
  storage.setAttributedString(
    NSAttributedString(
      string: "Heading line\n",
      attributes: legacyAttributes(legacyHeading2, family: family)
    )
  )
  storage.append(
    NSAttributedString(
      string: "Body copy\n",
      attributes: legacyAttributes(legacyBody, family: family)
    )
  )

  let migrated = EditorTypographyMigration.migrate(
    storage,
    family: family,
    size: migrationBodySize,
    isListParagraph: { _ in false }
  )

  #expect(migrated == 2)
  let headingFont = try #require(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
  #expect(headingFont.familyName == family)
  #expect(abs(headingFont.pointSize - migrationBodySize * 1.35) < 0.05)
  let bodyParagraph = try paragraphStyle(storage, at: ("Heading line\n" as NSString).length)
  #expect(abs(bodyParagraph.paragraphSpacing - EditorTypography.bodyParagraphSpacing) < 0.01)
  let bodyFont = try #require(
    storage.attribute(.font, at: ("Heading line\n" as NSString).length, effectiveRange: nil)
      as? NSFont
  )
  #expect(bodyFont.familyName == family)
}

@Test @MainActor func listParagraphsKeepTheirSpacingOnFirstOpen() throws {
  let frame = NSRect(x: 0, y: 0, width: 480, height: 240)
  let window = NSWindow(
    contentRect: frame,
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  let textView = ListAwareTextView(frame: frame)
  window.contentView = textView
  defer { withExtendedLifetime(window) {} }

  let body = "1. First step\nBody copy\n"
  let listLength = ("1. First step\n" as NSString).length
  let storage = NSTextStorage()
  storage.setAttributedString(NSAttributedString(string: body))
  storage.addAttributes(legacyAttributes(legacyBody), range: NSRange(location: 0, length: storage.length))
  textView.textStorage?.setAttributedString(NSAttributedString(attributedString: storage))

  let migrated = textView.migrateLegacyTypography(
    family: EditorTypography.systemFamily,
    size: migrationBodySize
  )

  #expect(migrated == 1)
  let liveStorage = try #require(textView.textStorage)
  let listParagraph = try paragraphStyle(liveStorage, at: 0)
  #expect(abs(listParagraph.paragraphSpacing) < 0.01)
  #expect(abs(listParagraph.defaultTabInterval - 36) < 0.01)
  let bodyParagraph = try paragraphStyle(liveStorage, at: listLength)
  #expect(abs(bodyParagraph.paragraphSpacing - EditorTypography.bodyParagraphSpacing) < 0.01)
}

@Test @MainActor func migratingMixedPresetsPreservesUnownedAttributesAndIsIdempotent() throws {
  let cases: [(LegacyPreset, CGFloat, CGFloat, CGFloat)] = [
    (legacyHeading3, 1.15, 8, 4),
    (legacyBody, 1, 0, 8),
    (legacyCode, 1, 4, 4),
    (legacyHeading1, 1.6, 16, 8),
    (legacyQuote, 1, 8, 8),
    (legacyHeading2, 1.35, 12, 6),
  ]
  let storage = NSTextStorage()
  var paragraphs: [(range: NSRange, size: CGFloat, before: CGFloat, after: CGFloat)] = []
  for (index, item) in cases.enumerated() {
    var attributes = legacyAttributes(item.0)
    let paragraph = try #require(
      (attributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy()
        as? NSMutableParagraphStyle
    )
    paragraph.lineSpacing = 3
    paragraph.baseWritingDirection = .rightToLeft
    attributes[.paragraphStyle] = paragraph
    attributes[.foregroundColor] = NSColor.systemPurple
    attributes[.kern] = 1.25
    let text = "Paragraph \(index)\n"
    let range = NSRange(location: storage.length, length: (text as NSString).length)
    paragraphs.append((range, migrationBodySize * item.1, item.2, item.3))
    storage.append(NSAttributedString(string: text, attributes: attributes))
  }
  let originalText = storage.string

  #expect(migrate(storage) == cases.count)

  #expect(storage.string == originalText)
  for expected in paragraphs {
    let attributes = storage.attributes(at: expected.range.location, effectiveRange: nil)
    let font = try #require(attributes[.font] as? NSFont)
    let paragraph = try #require(attributes[.paragraphStyle] as? NSParagraphStyle)
    #expect(abs(font.pointSize - expected.size) < 0.01)
    #expect(paragraph.paragraphSpacingBefore == expected.before)
    #expect(paragraph.paragraphSpacing == expected.after)
    #expect(paragraph.lineSpacing == 3)
    #expect(paragraph.baseWritingDirection == .rightToLeft)
    #expect((attributes[.foregroundColor] as? NSColor)?.isEqual(NSColor.systemPurple) == true)
    #expect(attributes[.kern] as? Double == 1.25)
  }
  let migrated = NSAttributedString(attributedString: storage)

  #expect(migrate(storage) == 0)
  #expect(storage.isEqual(to: migrated))
}
