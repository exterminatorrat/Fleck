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

@MainActor
private func attributedString(from rtf: Data) throws -> NSAttributedString {
  try NSAttributedString(
    data: rtf,
    options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: nil
  )
}
