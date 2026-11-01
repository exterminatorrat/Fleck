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

@MainActor
private func attributedString(from rtf: Data) throws -> NSAttributedString {
  try NSAttributedString(
    data: rtf,
    options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: nil
  )
}
