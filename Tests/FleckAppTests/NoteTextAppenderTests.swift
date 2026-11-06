import AppKit
import FleckCore
import Testing

@testable import FleckApp

@Test @MainActor func noteTextAppenderUsesNoLeadingParagraphForAnEmptyNote() throws {
  let result = NoteTextAppender.appending("Dictated thought", to: Note(body: ""))

  #expect(result.body == "Dictated thought")
  #expect(result.insertedSuffix == "Dictated thought")
  #expect(try attributedString(from: result.richTextRTF).string == "Dictated thought")
}

@Test @MainActor func noteTextAppenderAddsExactlyOneParagraphSeparatorToExistingContent() {
  let result = NoteTextAppender.appending("Dictated thought", to: Note(body: "Existing"))

  #expect(result.body == "Existing\n\nDictated thought")
  #expect(result.insertedSuffix == "\n\nDictated thought")
}

@Test @MainActor func noteTextAppenderPreservesExistingAttributedRunsAndUsesDefaultSuffixAttributes()
  throws
{
  let source = NSMutableAttributedString(string: "Bold")
  source.addAttribute(
    .font,
    value: NSFont.boldSystemFont(ofSize: 18),
    range: NSRange(location: 0, length: source.length)
  )
  source.addAttribute(
    .underlineStyle,
    value: NSUnderlineStyle.single.rawValue,
    range: NSRange(location: 0, length: source.length)
  )
  let sourceRTF = try source.data(
    from: NSRange(location: 0, length: source.length),
    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
  )

  let result = NoteTextAppender.appending("Dictated", to: Note(body: "Bold", richTextRTF: sourceRTF))
  let appended = try attributedString(from: result.richTextRTF)

  #expect(appended.string == "Bold\n\nDictated")
  #expect(
    NSFontManager.shared.traits(of: try #require(
      appended.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    )).contains(.boldFontMask)
  )
  #expect(
    appended.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int
      == NSUnderlineStyle.single.rawValue
  )
  #expect((appended.attribute(.underlineStyle, at: 6, effectiveRange: nil) as? Int ?? 0) == 0)
}

@Test @MainActor func noteTextAppenderExposesTheExactSuffixForConditionalUndo() {
  let result = NoteTextAppender.appending("Dictated thought", to: Note(body: "Existing"))
  let suffixLength = result.insertedSuffix.utf16.count
  let bodyWithoutSuffix = String(result.body.dropLast(suffixLength))

  #expect(result.body.hasSuffix(result.insertedSuffix))
  #expect(bodyWithoutSuffix == "Existing")
}

@Test @MainActor func noteTextAppenderUsesExplicitEditorDefaultsForEmptyPlainAndFormattedNotes()
  throws
{
  let defaults = NoteTextAppendDefaults(fontFamily: "Menlo", fontSize: 21)
  let expectedLineHeight: CGFloat = 21.0 / 17.0 * 27.0
  let formatted = NSMutableAttributedString(string: "Bold")
  formatted.addAttribute(
    .font,
    value: NSFont.boldSystemFont(ofSize: 18),
    range: NSRange(location: 0, length: formatted.length)
  )
  let formattedRTF = try formatted.data(
    from: NSRange(location: 0, length: formatted.length),
    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
  )

  for note in [
    Note(body: ""),
    Note(body: "Plain"),
    Note(body: "Bold", richTextRTF: formattedRTF),
  ] {
    let result = NoteTextAppender.appending("Dictated", to: note, defaults: defaults)
    let appended = try attributedString(from: result.richTextRTF)
    let suffixLocation = appended.length - "Dictated".utf16.count
    let suffixFont = try #require(appended.attribute(.font, at: suffixLocation, effectiveRange: nil) as? NSFont)
    let suffixParagraph = try #require(
      appended.attribute(.paragraphStyle, at: suffixLocation, effectiveRange: nil)
        as? NSParagraphStyle
    )

    #expect(suffixFont.pointSize == 21)
    #expect(suffixFont.familyName == "Menlo")
    #expect(abs(suffixParagraph.minimumLineHeight - expectedLineHeight) < 0.01)
    #expect(abs(suffixParagraph.maximumLineHeight - expectedLineHeight) < 0.01)
  }
}

@Test @MainActor func noteTextAppenderAppliesDefaultsToTheEntirePlainNoteAfterRTFRoundTrip()
  throws
{
  let defaults = NoteTextAppendDefaults(fontFamily: "Menlo", fontSize: 21)
  let result = NoteTextAppender.appending("Dictated", to: Note(body: "Plain"), defaults: defaults)
  let appended = try attributedString(from: result.richTextRTF)

  for location in [0, appended.length - "Dictated".utf16.count] {
    let font = try #require(appended.attribute(.font, at: location, effectiveRange: nil) as? NSFont)
    #expect(font.familyName == "Menlo")
    #expect(font.pointSize == 21)
  }
}

@Test @MainActor func noteRichTextCodecPreservesRelativeTailIndentsAcrossRoundTrip() throws {
  let body = "First paragraph\nSecond paragraph\n"
  let style = NSMutableParagraphStyle()
  style.tailIndent = -24
  let source = NSAttributedString(
    string: body,
    attributes: [.font: NSFont.systemFont(ofSize: 17), .paragraphStyle: style]
  )

  let decoded = try NoteRichTextCodec.decode(NoteRichTextCodec.encode(source))
  #expect(decoded.string.utf8.elementsEqual(body.utf8))
  for location in [0, "First paragraph\n".utf16.count] {
    let decodedStyle = try #require(
      decoded.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
    )
    #expect(decodedStyle.tailIndent == -24)
  }
}

@Test @MainActor func noteRichTextCodecIgnoresOutOfBoundsRelativeTailMetadata() throws {
  let source = NSAttributedString(
    string: "A paragraph\n",
    attributes: [.paragraphStyle: NSParagraphStyle.default]
  )
  var rtf = try source.data(
    from: NSRange(location: 0, length: source.length),
    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
  )
  let baseline = try NoteRichTextCodec.decode(rtf)
  let prefix = Data("{\\rtf1".utf8)
  try #require(rtf.starts(with: prefix))
  let records: [[String: Any]] = [
    ["location": 0, "length": Int.max, "value": -24.0]
  ]
  let payload = try JSONSerialization.data(withJSONObject: records)
  let metadata = Data("{\\*\\fleckrelativetailsv1 \(payload.base64EncodedString())}".utf8)
  rtf.insert(contentsOf: metadata, at: prefix.count)

  let decoded = try NoteRichTextCodec.decode(rtf)
  #expect(decoded.string.utf8.elementsEqual(baseline.string.utf8))
  let style = try #require(
    decoded.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
  )
  let baselineStyle = try #require(
    baseline.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
  )
  #expect(style.tailIndent == baselineStyle.tailIndent)
}

@Test @MainActor func noteTextAppenderPreservesRelativeTailIndentsInExistingParagraphs() throws {
  let body = "First paragraph\nSecond paragraph"
  let style = NSMutableParagraphStyle()
  style.tailIndent = -24
  let source = NSAttributedString(
    string: body,
    attributes: [.font: NSFont.systemFont(ofSize: 17), .paragraphStyle: style]
  )
  let note = Note(body: body, richTextRTF: try NoteRichTextCodec.encode(source))

  let result = NoteTextAppender.appending("Dictated", to: note)
  let appended = try NoteRichTextCodec.decode(result.richTextRTF)

  #expect(
    result.body.utf16.elementsEqual(
      "First paragraph\nSecond paragraph\n\nDictated".utf16
    )
  )
  for location in [0, "First paragraph\n".utf16.count] {
    let paragraph = try #require(
      appended.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
    )
    #expect(paragraph.tailIndent == -24)
  }
}

@Test @MainActor func noteTextAppenderFallsBackToPlainBodyForMalformedRTF() throws {
  let result = NoteTextAppender.appending(
    "Added",
    to: Note(body: "Synthetic fallback", richTextRTF: Data("malformed RTF".utf8))
  )

  #expect(
    try attributedString(from: result.richTextRTF).string == "Synthetic fallback\n\nAdded"
  )
}

@MainActor
private func attributedString(from rtf: Data) throws -> NSAttributedString {
  try NSAttributedString(
    data: rtf,
    options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: nil
  )
}

@Test @MainActor func noteRTFSerializationPreservesRelativeAndAbsoluteTailIndents() throws {
  let attributed = NSMutableAttributedString(string: "relative\nzero\nabsolute")
  let ranges = [
    NSRange(location: 0, length: 9), NSRange(location: 9, length: 5),
    NSRange(location: 14, length: 8),
  ]
  let tails: [CGFloat] = [-8, 0, 120]
  for (range, tail) in zip(ranges, tails) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.firstLineHeadIndent = 4
    paragraph.headIndent = 12
    paragraph.tailIndent = tail
    attributed.addAttribute(.paragraphStyle, value: paragraph, range: range)
  }
  let legacyRTF = try attributed.data(
    from: NSRange(location: 0, length: attributed.length),
    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
  )
  let legacyNative = try NSAttributedString(
    data: legacyRTF, options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: nil
  )
  let legacyDecoded = try NoteRichTextCodec.decode(legacyRTF)
  let encoded = try NoteRichTextCodec.encode(attributed)
  let decoded = try NoteRichTextCodec.decode(encoded)
  let nativeDecoded = try NSAttributedString(
    data: encoded, options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: nil
  )
  #expect(decoded.string.utf16.elementsEqual(attributed.string.utf16))
  #expect(nativeDecoded.string.utf16.elementsEqual(attributed.string.utf16))
  for (range, tail) in zip(ranges, tails) {
    let paragraph = try #require(
      decoded.attribute(.paragraphStyle, at: range.location, effectiveRange: nil)
        as? NSParagraphStyle
    )
    #expect(paragraph.firstLineHeadIndent == 4)
    #expect(paragraph.headIndent == 12)
    #expect(paragraph.tailIndent == tail)
    let legacyStyle = try #require(
      legacyNative.attribute(.paragraphStyle, at: range.location, effectiveRange: nil)
        as? NSParagraphStyle
    )
    for unmodified in [legacyDecoded, nativeDecoded] {
      let style = try #require(
        unmodified.attribute(.paragraphStyle, at: range.location, effectiveRange: nil)
          as? NSParagraphStyle
      )
      #expect(style.isEqual(legacyStyle))
    }
  }

  let invalidRecords = [
    #"[{"location":1,"length":8,"value":-8}]"#,
    #"[{"location":0,"length":9,"value":8}]"#,
    #"[{"location":0,"length":9,"value":-8},{"location":0,"length":9,"value":-16}]"#,
    #"[{"location":0,"length":9,"value":-8},{"location":22,"length":1,"value":-16}]"#,
    "invalid JSON",
  ]
  for records in invalidRecords {
    var invalid = legacyRTF
    let payload = Data(records.utf8).base64EncodedString()
    invalid.insert(
      contentsOf: Data("{\\*\\fleckrelativetailsv1 \(payload)}".utf8), at: 6
    )
    let decodedInvalid = try NoteRichTextCodec.decode(invalid)
    #expect(decodedInvalid.isEqual(to: legacyNative))
  }

  let validRecord = #"[{"location":0,"length":9,"value":-8}]"#
  for extraBytes in [0, 3] {
    let json = validRecord + String(repeating: " ", count: 387 + extraBytes - validRecord.utf8.count)
    let payload = Data(json.utf8).base64EncodedString()
    #expect(payload.utf8.count == 516 + (extraBytes == 0 ? 0 : 4))
    var bounded = legacyRTF
    bounded.insert(contentsOf: Data("{\\*\\fleckrelativetailsv1 \(payload)}".utf8), at: 6)
    let decodedBounded = try NoteRichTextCodec.decode(bounded)
    if extraBytes == 0 {
      let paragraph = try #require(
        decodedBounded.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
      )
      #expect(paragraph.tailIndent == -8)
    } else {
      #expect(decodedBounded.isEqual(to: legacyNative))
    }
  }
}

@Test @MainActor func noteRTFRelativeTailsSurviveUnicodeAndLineEndingNormalization() throws {
  for ending in ["\n", "\r", "\r\n", "\u{2029}"] {
    let contents = ["zero e\u{301}", "relative e\u{301}", "relative \u{1100}\u{1161}", "absolute é"]
    let tails: [CGFloat] = [0, -8, -16, 120]
    let source = NSMutableAttributedString(string: contents.joined(separator: ending), attributes: [.font: NSFont.systemFont(ofSize: 14)])
    let sourceText = source.string as NSString
    var location = 0
    for tail in tails {
      let range = sourceText.paragraphRange(for: NSRange(location: location, length: 0))
      let style = NSMutableParagraphStyle()
      style.firstLineHeadIndent = 4; style.headIndent = 12; style.tailIndent = tail
      source.addAttribute(.paragraphStyle, value: style, range: range)
      location = NSMaxRange(range)
    }
    let decoded = try NoteRichTextCodec.decode(NoteRichTextCodec.encode(source))
    let decodedText = decoded.string as NSString
    location = 0
    for (content, tail) in zip(contents, tails) {
      let range = decodedText.paragraphRange(for: NSRange(location: location, length: 0))
      var contentEnd = 0
      decodedText.getParagraphStart(nil, end: nil, contentsEnd: &contentEnd, for: range)
      #expect(decodedText.substring(with: NSRange(location: location, length: contentEnd - location)) == content)
      let style = try #require(decoded.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle)
      #expect(style.firstLineHeadIndent == 4)
      #expect(style.headIndent == 12)
      #expect(style.tailIndent == tail)
      location = NSMaxRange(range)
    }
    #expect(location == decodedText.length)
  }
}

@Test @MainActor func noteRTFRelativeTailsPreserveInternalUnicodeLineSeparator() throws {
  let text = "e\u{301}\u{2028}line\u{2029}relative"
  let source = NSMutableAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 14)])
  let firstRange = (text as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
  let relativeRange = NSRange(location: NSMaxRange(firstRange), length: source.length - NSMaxRange(firstRange))
  let zero = NSMutableParagraphStyle()
  source.addAttribute(.paragraphStyle, value: zero, range: firstRange)
  let relative = NSMutableParagraphStyle(); relative.tailIndent = -8
  source.addAttribute(.paragraphStyle, value: relative, range: relativeRange)
  let decoded = try NoteRichTextCodec.decode(NoteRichTextCodec.encode(source))
  let decodedText = decoded.string as NSString
  let decodedFirst = decodedText.paragraphRange(for: NSRange(location: 0, length: 0))
  var contentEnd = 0
  decodedText.getParagraphStart(nil, end: nil, contentsEnd: &contentEnd, for: decodedFirst)
  #expect(decodedText.substring(to: contentEnd) == "e\u{301}\u{2028}line")
  #expect(decodedText.substring(from: NSMaxRange(decodedFirst)) == "relative")
  let firstStyle = try #require(decoded.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
  let relativeStyle = try #require(decoded.attribute(.paragraphStyle, at: NSMaxRange(decodedFirst), effectiveRange: nil) as? NSParagraphStyle)
  #expect(firstStyle.tailIndent == 0)
  #expect(relativeStyle.tailIndent == -8)
}
