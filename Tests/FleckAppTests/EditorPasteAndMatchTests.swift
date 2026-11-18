import AppKit
import FleckCore
import Testing

@testable import FleckApp

@MainActor
private func pasteEditor(_ text: String) -> (ListAwareTextView, NSWindow) {
  let frame = NSRect(x: 0, y: 0, width: 420, height: 200)
  let view = ListAwareTextView(frame: frame)
  let window = NSWindow(
    contentRect: frame,
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = view
  view.allowsUndo = true
  view.textStorage?.setAttributedString(
    NSAttributedString(string: text, attributes: [
      .font: NSFont(name: "Helvetica", size: 15)!,
      .paragraphStyle: EditorTypography.defaultParagraphStyle(fontSize: 15),
    ])
  )
  window.makeKeyAndOrderFront(nil)
  window.makeFirstResponder(view)
  return (view, window)
}

private func imageOnlyPasteboard() -> NSPasteboard {
  let pasteboard = NSPasteboard.withUniqueName()
  pasteboard.clearContents()
  let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: 4,
    pixelsHigh: 4,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  )!
  let image = NSImage(size: NSSize(width: 4, height: 4))
  image.addRepresentation(rep)
  pasteboard.writeObjects([image])
  return pasteboard
}

@Test @MainActor func matchedStyleMergeKeepsEmphasisOnTheDestinationStyle() throws {
  let link = URL(string: "fleck-note://\(UUID())")!
  let source = NSAttributedString(
    string: "Bold link",
    attributes: [
      .font: try #require(NSFont(name: "Helvetica-Bold", size: 42)),
      .underlineStyle: NSUnderlineStyle.single.rawValue,
      .strikethroughStyle: NSUnderlineStyle.single.rawValue,
      .link: link,
    ]
  )
  let destinationFont = try #require(NSFont(name: "Helvetica", size: 15))
  let destinationParagraph = EditorTypography.defaultParagraphStyle(fontSize: 15)

  let merged = ListAwareTextView.mergePaste(
    source,
    destinationAttributes: [.font: destinationFont, .paragraphStyle: destinationParagraph]
  )

  #expect(merged.string == "Bold link")
  let font = try #require(merged.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
  #expect(font.familyName == destinationFont.familyName)
  #expect(font.pointSize == 15)
  #expect(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
  #expect(
    merged.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int
      == NSUnderlineStyle.single.rawValue
  )
  #expect(
    merged.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int
      == NSUnderlineStyle.single.rawValue
  )
  #expect(merged.attribute(.link, at: 0, effectiveRange: nil) as? URL == link)
  #expect(
    merged.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
      == destinationParagraph
  )
}

@Test @MainActor func matchedStylePasteboardReadsRichTextAndPlainText() throws {
  let rich = NSPasteboard.withUniqueName()
  defer { rich.releaseGlobally() }
  rich.clearContents()
  rich.writeObjects([
    NSAttributedString(
      string: "Rich",
      attributes: [.font: try #require(NSFont(name: "Helvetica-Bold", size: 24))]
    )
  ])
  let richContent = try #require(
    ListAwareTextView.matchedStylePasteboardContent(from: rich)
  )
  #expect(richContent.string == "Rich")
  let richFont = try #require(richContent.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
  #expect(NSFontManager.shared.traits(of: richFont).contains(.boldFontMask))

  let plain = NSPasteboard.withUniqueName()
  defer { plain.releaseGlobally() }
  plain.clearContents()
  plain.setString("Plain", forType: .string)
  let plainContent = try #require(
    ListAwareTextView.matchedStylePasteboardContent(from: plain)
  )
  #expect(plainContent.string == "Plain")
  #expect(plainContent.attribute(.font, at: 0, effectiveRange: nil) == nil)
}

@Test @MainActor func matchedStylePasteboardRefusesAnImageOnlyCopy() throws {
  let pasteboard = imageOnlyPasteboard()
  defer { pasteboard.releaseGlobally() }

  try #require(pasteboard.data(forType: .tiff) != nil)
  #expect(pasteboard.string(forType: .string) == nil)
  #expect(ListAwareTextView.matchedStylePasteboardContent(from: pasteboard) == nil)
}

@Test @MainActor func pasteAndMatchStyleInsertsOnTheDestinationStyle() throws {
  let (view, window) = pasteEditor("Body ")
  defer { window.contentView = nil }
  let destinationParagraph = EditorTypography.defaultParagraphStyle(fontSize: 15)
  view.setSelectedRange(NSRange(location: 5, length: 0))
  view.typingAttributes = [
    .font: try #require(NSFont(name: "Helvetica", size: 15)),
    .paragraphStyle: destinationParagraph,
  ]

  let pasteboard = NSPasteboard.withUniqueName()
  defer { pasteboard.releaseGlobally() }
  pasteboard.clearContents()
  pasteboard.writeObjects([
    NSAttributedString(
      string: "Bold",
      attributes: [
        .font: try #require(NSFont(name: "Helvetica-Bold", size: 42)),
        .underlineStyle: NSUnderlineStyle.single.rawValue,
      ]
    )
  ])

  view.pasteMatchedStyle(from: pasteboard)

  #expect(view.string == "Body Bold")
  let font = try #require(view.textStorage?.attribute(.font, at: 6, effectiveRange: nil) as? NSFont)
  #expect(font.familyName == "Helvetica")
  #expect(font.pointSize == 15)
  #expect(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
  #expect(
    view.textStorage?.attribute(.underlineStyle, at: 6, effectiveRange: nil) as? Int
      == NSUnderlineStyle.single.rawValue
  )
  #expect(
    view.textStorage?.attribute(.paragraphStyle, at: 6, effectiveRange: nil) as? NSParagraphStyle
      == destinationParagraph
  )
  #expect(view.selectedRange() == NSRange(location: 9, length: 0))

  view.undoManager?.undo()
  #expect(view.string == "Body ")
}

@Test @MainActor func pasteAndMatchStyleIgnoresAnImageOnlyCopy() {
  let (view, window) = pasteEditor("Body ")
  defer { window.contentView = nil }
  view.setSelectedRange(NSRange(location: 5, length: 0))
  let pasteboard = imageOnlyPasteboard()
  defer { pasteboard.releaseGlobally() }

  view.pasteMatchedStyle(from: pasteboard)

  #expect(view.string == "Body ")
  #expect(view.selectedRange() == NSRange(location: 5, length: 0))
}

@Test @MainActor func pasteAndMatchStyleActionRoutesThroughTheStandardSelector() throws {
  let (view, window) = pasteEditor("Body ")
  defer { window.contentView = nil }
  view.setSelectedRange(NSRange(location: 5, length: 0))
  view.typingAttributes = [.font: try #require(NSFont(name: "Helvetica", size: 15))]

  let pasteboard = NSPasteboard.general
  pasteboard.clearContents()
  pasteboard.writeObjects([
    NSAttributedString(
      string: "Bold",
      attributes: [.font: try #require(NSFont(name: "Helvetica-Bold", size: 42))]
    )
  ])

  view.pasteAsPlainText(nil)

  #expect(view.string == "Body Bold")
  let font = try #require(view.textStorage?.attribute(.font, at: 6, effectiveRange: nil) as? NSFont)
  #expect(font.pointSize == 15)
  #expect(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
}

@Test @MainActor func pasteAndMatchStyleKeepsANoteLinkParsable() throws {
  let (view, window) = pasteEditor("")
  defer { window.contentView = nil }
  let target = UUID()
  let markdown = NoteLinkFormatter.markdown(label: "Target", targetNoteID: target)
  view.setSelectedRange(NSRange(location: 0, length: 0))

  let pasteboard = NSPasteboard.withUniqueName()
  defer { pasteboard.releaseGlobally() }
  pasteboard.clearContents()
  pasteboard.setString("Body \(markdown)", forType: .string)

  view.pasteMatchedStyle(from: pasteboard)

  #expect(view.string == "Body \(markdown)")
  #expect(NoteLinkParser.links(in: view.string).count == 1)
}
