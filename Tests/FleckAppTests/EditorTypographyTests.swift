import AppKit
import Testing

@testable import FleckApp

@Test @MainActor func editorTypographyUsesAvenirAndOpenBodyRhythm() throws {
  let font = EditorTypography.bodyFont(family: "Avenir Next", size: 17)
  let paragraph = EditorTypography.defaultParagraphStyle(fontSize: 17)

  #expect(font.familyName == "Avenir Next")
  #expect(font.pointSize == 17)
  #expect(paragraph.minimumLineHeight == 27)
  #expect(paragraph.maximumLineHeight == 27)
}

@Test @MainActor func editorTypographyFallsBackWhenFamilyIsUnavailable() {
  let font = EditorTypography.bodyFont(
    family: "Missing Fleck Font",
    size: 17,
    fontProvider: { _, _ in nil }
  )

  #expect(font.familyName == NSFont.systemFont(ofSize: 17).familyName)
  #expect(font.pointSize == 17)
}

@Test @MainActor func editorTypographyDefaultAttributesStayConsistent() throws {
  let attributes = EditorTypography.defaultAttributes(
    family: "Avenir Next",
    size: 17
  )
  let font = try #require(attributes[.font] as? NSFont)
  let paragraph = try #require(attributes[.paragraphStyle] as? NSParagraphStyle)

  #expect(font.familyName == "Avenir Next")
  #expect(font.pointSize == 17)
  #expect(paragraph.minimumLineHeight == 27)
  #expect(paragraph.maximumLineHeight == 27)
}
