#if os(macOS)
  import AppKit
  import FleckCore
  import Testing

  @testable import FleckApp

  @Test @MainActor func compactRenderingCollapsesTheLinkDestinationAndKeepsTheBody() throws {
    let target = UUID()
    let token = NoteLinkFormatter.markdown(label: "Launch checklist", targetNoteID: target)
    let text = "Ship it. \(token) covers signing."
    let textView = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 200))
    textView.string = text
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    textView.refreshNoteLinks(accentColorHex: "#FFD600", liveNoteIDs: [target])

    let layoutManager = try #require(textView.layoutManager)
    let container = try #require(textView.textContainer)
    layoutManager.ensureLayout(for: container)
    let link = try #require(NoteLinkParser.links(in: text).first)
    let collapsedWidth = layoutManager.usedRect(for: container).width

    let collapsedNulls = nullGlyphCount(layoutManager)

    #expect(link.nonLabelRanges.count == 2)
    #expect(textView.string == text)

    textView.setSelectedRange(NSRange(location: link.labelRange.location, length: 0))
    layoutManager.ensureLayout(for: container)
    let revealedWidth = layoutManager.usedRect(for: container).width

    let destinationLength = link.range.length - link.labelRange.length
    let toggled = collapsedNulls - nullGlyphCount(layoutManager)
    #expect(toggled <= destinationLength)
    #expect(toggled >= destinationLength - 2)
    #expect(revealedWidth > collapsedWidth)
    #expect(textView.string == text)
  }

  @Test @MainActor func compactRenderingRevealsTheSourceWhenTheCaretEntersTheLink() throws {
    let target = UUID()
    let token = NoteLinkFormatter.markdown(label: "Launch checklist", targetNoteID: target)
    let text = "Ship it. \(token) covers signing."
    let textView = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 200))
    textView.string = text
    textView.setSelectedRange(NSRange(location: 0, length: 0))
    textView.refreshNoteLinks(accentColorHex: "#FFD600", liveNoteIDs: [target])

    let layoutManager = try #require(textView.layoutManager)
    let container = try #require(textView.textContainer)
    let link = try #require(NoteLinkParser.links(in: text).first)
    layoutManager.ensureLayout(for: container)
    let collapsedNulls = nullGlyphCount(layoutManager)

    textView.setSelectedRange(NSRange(location: link.labelRange.location, length: 0))
    layoutManager.ensureLayout(for: container)
    let revealedNulls = nullGlyphCount(layoutManager)
    let destinationLength = link.range.length - link.labelRange.length
    #expect(collapsedNulls - revealedNulls <= destinationLength)
    #expect(collapsedNulls - revealedNulls >= destinationLength - 2)

    textView.setSelectedRange(NSRange(location: 0, length: 0))
    layoutManager.ensureLayout(for: container)
    #expect(nullGlyphCount(layoutManager) == collapsedNulls)
    #expect(textView.string == text)
  }

  @Test @MainActor func compactRenderingSelectingTheLinkRevealsItsSource() throws {
    let target = UUID()
    let token = NoteLinkFormatter.markdown(label: "Launch checklist", targetNoteID: target)
    let text = "Ship it. \(token) covers signing."
    let textView = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 200))
    textView.string = text
    textView.setSelectedRange(NSRange(location: 0, length: 0))
    textView.refreshNoteLinks(accentColorHex: "#FFD600", liveNoteIDs: [target])

    let layoutManager = try #require(textView.layoutManager)
    let container = try #require(textView.textContainer)
    let link = try #require(NoteLinkParser.links(in: text).first)
    layoutManager.ensureLayout(for: container)
    let collapsedNulls = nullGlyphCount(layoutManager)

    textView.setSelectedRange(NSRange(location: link.labelRange.location, length: 3))
    layoutManager.ensureLayout(for: container)
    let destinationLength = link.range.length - link.labelRange.length
    let toggled = collapsedNulls - nullGlyphCount(layoutManager)
    #expect(toggled <= destinationLength)
    #expect(toggled >= destinationLength - 2)
  }

  @Test @MainActor func compactRenderingLeavesLinkInkAndUnderlineOnTheCollapsedLabel() throws {
    let target = UUID()
    let token = NoteLinkFormatter.markdown(label: "Launch checklist", targetNoteID: target)
    let text = "Ship it. \(token) covers signing."
    let textView = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 200))
    textView.string = text
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    textView.refreshNoteLinks(accentColorHex: "#FFD600", liveNoteIDs: [target])

    let layoutManager = try #require(textView.layoutManager)
    let link = try #require(NoteLinkParser.links(in: text).first)
    let canvas = EditorCanvasInk.canvasColor(for: textView)
    let yellow = try #require(NSColor(hex: "#FFD600"))
    let expected = FleckColorContrast.accessibleForeground(yellow, against: canvas)
    let labelInk = try #require(
      layoutManager.temporaryAttribute(
        .foregroundColor,
        atCharacterIndex: link.labelRange.location,
        effectiveRange: nil
      ) as? NSColor
    )

    #expect(sRGB(labelInk) == sRGB(expected))
    #expect(
      layoutManager.temporaryAttribute(
        .underlineStyle,
        atCharacterIndex: link.labelRange.location,
        effectiveRange: nil
      ) as? Int == NSUnderlineStyle.single.rawValue
    )
    #expect(textView.textStorage?.attribute(.link, at: link.range.location, effectiveRange: nil) == nil)
  }

  @Test @MainActor func compactRenderingMarksAMissingTargetWithoutColorAlone() throws {
    let missing = UUID()
    let token = NoteLinkFormatter.markdown(label: "Launch checklist", targetNoteID: missing)
    let text = "Ship it. \(token) covers signing."
    let textView = ListAwareTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 200))
    textView.string = text
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    textView.refreshNoteLinks(accentColorHex: "#FFD600", liveNoteIDs: [])

    let layoutManager = try #require(textView.layoutManager)
    let link = try #require(NoteLinkParser.links(in: text).first)
    #expect(nullGlyphCount(layoutManager) > 0)
    #expect(
      layoutManager.temporaryAttribute(
        .underlineStyle,
        atCharacterIndex: link.labelRange.location,
        effectiveRange: nil
      ) as? Int == NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue
    )
  }

  @MainActor
  private func nullGlyphCount(_ layoutManager: NSLayoutManager) -> Int {
    (0..<layoutManager.numberOfGlyphs).reduce(into: 0) { count, glyphIndex in
      if layoutManager.propertyForGlyph(at: glyphIndex) == .null {
        count += 1
      }
    }
  }

  private func sRGB(_ color: NSColor) -> [Int] {
    let converted = color.usingColorSpace(.sRGB) ?? color
    return [
      Int((converted.redComponent * 255).rounded()),
      Int((converted.greenComponent * 255).rounded()),
      Int((converted.blueComponent * 255).rounded()),
      Int((converted.alphaComponent * 255).rounded()),
    ]
  }
#endif
