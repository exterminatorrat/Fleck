import Foundation
import Testing

@testable import FleckCore

@Test func NoteLinkFormatterEscapesLabelAndUsesCanonicalUUID() {
  let id = UUID(uuidString: "550E8400-E29B-41D4-A716-446655440000")!

  #expect(
    NoteLinkFormatter.markdown(label: "Plan ] \\ launch", targetNoteID: id)
      == #"[Plan \] \\ launch](fleck://note/550E8400-E29B-41D4-A716-446655440000)"#
  )
}

@Test func NoteLinkParserReturnsExactUTF16RangesForUnicode() throws {
  let id = UUID(uuidString: "550E8400-E29B-41D4-A716-446655440000")!
  let body = "🧠 before [Café](fleck://note/\(id.uuidString)) after"
  let links = NoteLinkParser.links(in: body)
  let link = try #require(links.first)

  #expect(links.count == 1)
  #expect(link.targetNoteID == id)
  #expect((body as NSString).substring(with: link.range).hasPrefix("[Café]"))
  #expect(
    (body as NSString).substring(with: link.destinationRange)
      == "fleck://note/\(id.uuidString)"
  )
}

@Test func NoteLinkParserRejectsBroadenedOrMalformedDestinations() {
  let id = "550E8400-E29B-41D4-A716-446655440000"
  let invalid = [
    "[A](https://example.com)",
    "[A](fleck://other/\(id))",
    "[A](fleck://note/not-a-uuid)",
    "[A](fleck://note/\(id)?x=1)",
    "[A](fleck://note/\(id)#x)",
    "[A](fleck://user@note/\(id))",
    "[A](fleck://note/\(id)/extra)",
    "[A](fleck://note/%\(id))",
    "[A](fleck://note/\(id) )",
  ]

  for body in invalid {
    #expect(NoteLinkParser.links(in: body).isEmpty)
  }
}

@Test func NoteLinkParserFindsMultipleEscapedAndEmptyLabels() throws {
  let firstID = UUID()
  let secondID = UUID()
  let first = NoteLinkFormatter.markdown(label: #"One ] \\ two"#, targetNoteID: firstID)
  let second = NoteLinkFormatter.markdown(label: "", targetNoteID: secondID)
  let body = "before \(first) middle [ordinary [text] after \(second)"
  let links = NoteLinkParser.links(in: body)

  #expect(links.count == 2)
  #expect(links.map(\.targetNoteID) == [firstID, secondID])
  #expect(links[0].label == #"One ] \\ two"#)
  #expect(links[1].label.isEmpty)
}

@Test func NoteLinkParserRejectsIncompleteSyntaxAndHonorsEscapedClosers() {
  let id = UUID()
  let body = "[not closed](fleck://note/\(id.uuidString) [still missing] [escaped \\] text]"

  #expect(NoteLinkParser.links(in: body).isEmpty)
}

@Test func NoteLinkParserLookupUsesInclusiveStartAndExclusiveEnd() throws {
  let id = UUID()
  let body = "x \(NoteLinkFormatter.markdown(label: "Target", targetNoteID: id)) y"
  let link = try #require(NoteLinkParser.links(in: body).first)

  #expect(NoteLinkParser.link(atUTF16Location: link.range.location, in: body) == link)
  #expect(
    NoteLinkParser.link(atUTF16Location: NSMaxRange(link.range) - 1, in: body) == link
  )
  #expect(NoteLinkParser.link(atUTF16Location: NSMaxRange(link.range), in: body) == nil)
}

@Test func NoteLinkParserExcerptNormalizesWhitespaceAndPreservesComposedCharacters() throws {
  let id = UUID()
  let token = NoteLinkFormatter.markdown(label: "Café", targetNoteID: id)
  let body = "before\n👩‍💻 \(token)\n after"
  let link = try #require(NoteLinkParser.links(in: body).first)
  let excerpt = NoteLinkParser.excerpt(around: link.range, in: body, limit: 24)

  #expect(excerpt.contains("Café"))
  #expect(!excerpt.contains("\n"))
  #expect(excerpt.count <= 26)
}
