import Foundation
import Testing

@testable import MenuBarNotesCore

@Test func exportsPortableTextAndMarkdown() throws {
  let note = Note(title: "Ideas/Maybe", body: "# Hello\n- item")
  let text = NoteExport(note: note, format: .plainText)
  let markdown = NoteExport(note: note, format: .markdown)

  #expect(text.suggestedFilename == "Ideas-Maybe.txt")
  #expect(String(decoding: text.data, as: UTF8.self) == note.body)
  #expect(markdown.contentType == "text/markdown")
  #expect(String(decoding: markdown.data, as: UTF8.self) == note.body)
}

@Test func rtfExportEscapesControlCharactersAndUnicode() {
  let export = NoteExport(note: Note(body: "{café}\\\nnext"), format: .richText)
  let value = String(decoding: export.data, as: UTF8.self)
  #expect(value.hasPrefix("{\\rtf1"))
  #expect(value.contains("\\{"))
  #expect(value.contains("\\u233?"))
  #expect(value.contains("\\par"))
}

@Test func rtfExportPreservesExistingFormattedSidecar() {
  let rtf = Data("{\\rtf1\\b bold}".utf8)
  let export = NoteExport(note: Note(body: "bold", richTextRTF: rtf), format: .richText)
  #expect(export.data == rtf)
}

@Test func importsUTF8UsingFilenameAsTitle() throws {
  let date = Date(timeIntervalSince1970: 10)
  let note = try NoteImport.note(from: Data("body".utf8), filename: "Daily.md", date: date)
  #expect(note.title == "Daily")
  #expect(note.body == "body")
  #expect(note.createdAt == date)
  #expect(throws: NoteImport.ImportError.invalidUTF8) {
    try NoteImport.note(from: Data([0xff]), filename: "bad.txt")
  }
}
