import AppKit
import MenuBarNotesCore
import Testing

@testable import MenuBarNotesApp

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

    #expect(suffixFont.pointSize == 21)
    #expect(suffixFont.familyName == "Menlo")
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

@MainActor
private func attributedString(from rtf: Data) throws -> NSAttributedString {
  try NSAttributedString(
    data: rtf,
    options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: nil
  )
}
