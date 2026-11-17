#if os(macOS)
  import AppKit
  import CoreText
  import Testing

  @testable import FleckApp

  @MainActor
  private func markerEditor(_ text: String) -> (ListAwareTextView, NSWindow) {
    let frame = NSRect(x: 0, y: 0, width: 520, height: 240)
    let view = ListAwareTextView(frame: frame)
    let window = NSWindow(
      contentRect: frame,
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )
    window.contentView = view
    view.textStorage?.setAttributedString(
      NSAttributedString(string: text, attributes: [
        .font: EditorTypography.bodyFont(
          family: ".AppleSystemUIFont",
          size: 17
        ),
        .paragraphStyle: EditorTypography.defaultParagraphStyle(fontSize: 17),
      ])
    )
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(view)
    return (view, window)
  }

  /// Ink height the way a reader judges a glyph: the drawn outline, not the
  /// font's em box or line height.
  /// The line height the note's paragraph style pins for a size.
  private func markerLineHeight(fontSize: CGFloat) -> CGFloat {
    fontSize / 17 * EditorTypography.defaultLineHeight
  }

  private func inkHeight(of text: String, font: NSFont) -> CGFloat {
    let line = CTLineCreateWithAttributedString(
      NSAttributedString(string: text, attributes: [.font: font])
    )
    return CTLineGetBoundsWithOptions(line, .useGlyphPathBounds).height
  }

  /// Both lines carry the same marker, drawn at the size their own text occupies, so
  /// the ideographic line sits exactly where the Latin one does and neither line's
  /// bullet outweighs the other's.
  @Test @MainActor func cjkListMarkerMatchesTheLatinMarkerWithoutMovingTheLine() throws {
    let latinLine = "• hello world"
    let cjkLine = "• \u{4F60}\u{597D}\u{4E16}\u{754C}"
    let text = latinLine + "\n" + cjkLine
    let (view, window) = markerEditor(text)
    defer { window.contentView = nil }

    let layoutManager = try #require(view.layoutManager)
    let container = try #require(view.textContainer)
    let storage = try #require(view.textStorage)
    view.normalizeListMarkerFonts()
    view.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
    view.refreshChecklistPresentation()
    layoutManager.ensureLayout(for: container)

    let bodyFont = EditorTypography.bodyFont(
      family: ".AppleSystemUIFont",
      size: 17
    )
    let cjkMarkerIndex = latinLine.utf16.count + 1
    let storedMarker = try #require(
      storage.attribute(.font, at: cjkMarkerIndex, effectiveRange: nil) as? NSFont
    )
    #expect(abs(storedMarker.pointSize - bodyFont.pointSize) < 0.01)

    let drawn = view.drawnListMarkerPresentations
    #expect(drawn.count == 2)
    let latinMarker = try #require(drawn.first { $0.range.location == 0 }?.font)
    let cjkMarker = try #require(
      drawn.first { $0.range.location == cjkMarkerIndex }?.font
    )
    #expect(abs(cjkMarker.pointSize - latinMarker.pointSize) < 0.01)
    #expect(cjkMarker.familyName == latinMarker.familyName)
    #expect(
      abs(inkHeight(of: "\u{2022}", font: cjkMarker) - inkHeight(of: "\u{2022}", font: latinMarker))
        < 0.01
    )

    let latinFragment = layoutManager.lineFragmentRect(
      forGlyphAt: layoutManager.glyphIndexForCharacter(at: 0),
      effectiveRange: nil,
      withoutAdditionalLayout: true
    )
    let cjkFragment = layoutManager.lineFragmentRect(
      forGlyphAt: layoutManager.glyphIndexForCharacter(at: cjkMarkerIndex),
      effectiveRange: nil,
      withoutAdditionalLayout: true
    )
    let cjkGlyph = layoutManager.glyphIndexForCharacter(at: cjkMarkerIndex + 2)
    let cjkBaseline = cjkFragment.minY + layoutManager.location(forGlyphAt: cjkGlyph).y
    let latinBaseline = latinFragment.minY
      + layoutManager.location(forGlyphAt: layoutManager.glyphIndexForCharacter(at: 2)).y
    #expect(abs((cjkBaseline - cjkFragment.minY) - (latinBaseline - latinFragment.minY)) < 0.01)
    #expect(abs(cjkFragment.height - latinFragment.height) < 0.01)
  }

  /// The jump Harry reported: a marker-font change lifted the whole line by two
  /// points inside the paragraph's fixed line height. Normalising twice, focusing
  /// the line, and putting the caret in it must all leave its lines where they are.
  @Test @MainActor func normalizingAMarkerNeverMovesItsLine() throws {
    let cjk = "• \u{4F60}\u{597D}\u{4E16}\u{754C}"
    let text = cjk + "\nsecond line\nthird line"
    let (view, window) = markerEditor(text)
    defer { window.contentView = nil }
    let layoutManager = try #require(view.layoutManager)
    let container = try #require(view.textContainer)

    @MainActor func origin(of needle: String) throws -> CGFloat {
      layoutManager.ensureLayout(for: container)
      let ns = view.string as NSString
      let found = ns.range(of: needle)
      try #require(found.location != NSNotFound)
      let paragraph = ns.paragraphRange(for: NSRange(location: found.location, length: 0))
      let glyph = layoutManager.glyphIndexForCharacter(at: paragraph.location)
      let fragment = layoutManager.lineFragmentRect(
        forGlyphAt: glyph,
        effectiveRange: nil,
        withoutAdditionalLayout: true
      )
      return fragment.minY + layoutManager.location(forGlyphAt: glyph).y
    }

    view.normalizeListMarkerFonts()
    view.refreshChecklistPresentation()
    let lines = try ["second line", "third line"].map { try origin(of: $0) }
    let bullet = try origin(of: "\u{4F60}")

    view.window?.makeFirstResponder(view)
    view.setSelectedRange(NSRange(location: 2, length: 0))
    view.refreshChecklistPresentation()
    #expect(try ["second line", "third line"].map { try origin(of: $0) } == lines)
    #expect(try origin(of: "\u{4F60}") == bullet)

    view.normalizeListMarkerFonts()
    view.refreshChecklistPresentation()
    #expect(try ["second line", "third line"].map { try origin(of: $0) } == lines)
    #expect(try origin(of: "\u{4F60}") == bullet)

    let end = (cjk as NSString).length
    view.setSelectedRange(NSRange(location: end, length: 0))
    view.insertText("\u{5B57}", replacementRange: NSRange(location: end, length: 0))
    #expect(try ["second line", "third line"].map { try origin(of: $0) } == lines)
  }

  /// A marker left with a bigger font by an older note is repaired to its line's own
  /// font, which is what keeps the line measurable the same way every time.
  @Test @MainActor func staleMarkerFontIsRepairedToTheLineFont() throws {
    let text = "• \u{4F60}\u{597D}\u{4E16}\u{754C}"
    let (view, window) = markerEditor(text)
    defer { window.contentView = nil }
    let storage = try #require(view.textStorage)
    let layoutManager = try #require(view.layoutManager)
    let container = try #require(view.textContainer)
    let body = EditorTypography.bodyFont(family: ".AppleSystemUIFont", size: 17)
    let stale = try #require(NSFont(name: body.fontName, size: body.pointSize * 1.4))
    storage.addAttribute(.font, value: stale, range: NSRange(location: 0, length: 1))

    #expect(view.normalizeListMarkerFonts() >= 1)
    let repaired = try #require(
      storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    )
    #expect(abs(repaired.pointSize - body.pointSize) < 0.01)
    view.refreshChecklistPresentation()

    @MainActor func lineOrigin() -> CGFloat {
      layoutManager.ensureLayout(for: container)
      let glyph = layoutManager.glyphIndexForCharacter(at: 2)
      return layoutManager.lineFragmentRect(
        forGlyphAt: glyph,
        effectiveRange: nil,
        withoutAdditionalLayout: true
      ).minY + layoutManager.location(forGlyphAt: glyph).y
    }
    let repairedOrigin = lineOrigin()
    view.normalizeListMarkerFonts()
    #expect(lineOrigin() == repairedOrigin)
    let afterSecondPass =
      (storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize ?? 0
    #expect(abs(afterSecondPass - body.pointSize) < 0.01)

    let fragment = layoutManager.lineFragmentRect(
      forGlyphAt: layoutManager.glyphIndexForCharacter(at: 2),
      effectiveRange: nil,
      withoutAdditionalLayout: true
    )
    #expect(abs(fragment.height - markerLineHeight(fontSize: 17)) < 0.01)
    #expect(view.drawnListMarkerPresentations.count == 1)
  }

  @Test @MainActor func latinOnlyListKeepsTheBodyFontAndLineHeight() throws {
    let text = "• hello world\n1. hello again"
    let (view, window) = markerEditor(text)
    defer { window.contentView = nil }
    let layoutManager = try #require(view.layoutManager)
    let container = try #require(view.textContainer)
    layoutManager.ensureLayout(for: container)
    let lineHeight = layoutManager.lineFragmentRect(
      forGlyphAt: 0,
      effectiveRange: nil,
      withoutAdditionalLayout: true
    ).height

    let changes = view.normalizeListMarkerFonts()

    #expect(changes == 0)
    let storage = try #require(view.textStorage)
    let marker = try #require(
      storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    )
    #expect(abs(marker.pointSize - 17) < 0.01)
    view.refreshChecklistPresentation()
    #expect(view.drawnListMarkerPresentations.count == 2)
    layoutManager.ensureLayout(for: container)
    #expect(
      layoutManager.lineFragmentRect(
        forGlyphAt: 0,
        effectiveRange: nil,
        withoutAdditionalLayout: true
      ).height == lineHeight
    )
  }

  /// The paragraph style pins one line height, so the drawn marker has to fit inside
  /// it: the drawn font's ascent and descent still ride in the same band.
  @Test @MainActor func cjkMarkerStaysInsideTheParagraphLineHeight() throws {
    let (view, window) = markerEditor("• \u{4F60}\u{597D}\u{4E16}\u{754C}")
    defer { window.contentView = nil }
    let layoutManager = try #require(view.layoutManager)
    let container = try #require(view.textContainer)

    view.refreshChecklistPresentation()
    layoutManager.ensureLayout(for: container)

    let marker = try #require(view.drawnListMarkerPresentations.first?.font)
    let lineHeight = markerLineHeight(fontSize: 17)
    #expect(abs(marker.pointSize - 17) < 0.01)
    #expect(marker.ascender - marker.descender <= lineHeight)
    #expect(
      abs(
        layoutManager.lineFragmentRect(
          forGlyphAt: 0,
          effectiveRange: nil,
          withoutAdditionalLayout: true
        ).height - lineHeight
      ) < 0.01
    )
  }

  /// Typing into a paragraph must not re-size its marker. The marker's font is the
  /// paragraph's own, so committing another character cannot change what is drawn.
  @Test @MainActor func typingDoesNotResizeTheDrawnMarker() throws {
    let (view, window) = markerEditor("• \u{4F60}\u{597D}\u{4E16}\u{754C}")
    defer { window.contentView = nil }
    let storage = try #require(view.textStorage)
    view.refreshChecklistPresentation()
    let before = try #require(view.drawnListMarkerPresentations.first)

    view.setSelectedRange(NSRange(location: storage.length, length: 0))
    view.insertText("\u{5B57}", replacementRange: NSRange(location: storage.length, length: 0))

    view.refreshChecklistPresentation()
    let after = try #require(view.drawnListMarkerPresentations.first)
    #expect(after.range == before.range)
    #expect(after.font.fontName == before.font.fontName)
    #expect(abs(after.font.pointSize - before.font.pointSize) < 0.01)
  }

  /// A paste of several list lines never passes under the caret line by line, so every
  /// paragraph the edit wrote into has to carry its own drawn marker.
  @Test @MainActor func multiLineInsertionDrawsEveryPastedListMarker() throws {
    let (view, window) = markerEditor("• hello")
    defer { window.contentView = nil }
    let storage = try #require(view.textStorage)
    let insertion =
      "\n• \u{4F60}\u{597D}\n• \u{4E16}\u{754C}\n• \u{65E5}\u{672C}"
    let insertionPoint = storage.length

    view.setSelectedRange(NSRange(location: insertionPoint, length: 0))
    view.insertText(insertion, replacementRange: NSRange(location: insertionPoint, length: 0))

    view.refreshChecklistPresentation()
    let drawn = view.drawnListMarkerPresentations
    #expect(drawn.count == 4)
    let body = EditorTypography.bodyFont(family: ".AppleSystemUIFont", size: 17)
    for marker in drawn {
      #expect(abs(marker.font.pointSize - body.pointSize) < 0.01)
      let stored = try #require(
        storage.attribute(.font, at: marker.range.location, effectiveRange: nil) as? NSFont
      )
      #expect(abs(stored.pointSize - body.pointSize) < 0.01)
    }
  }

  /// The view draws every text list marker, so the text system's own ink is cleared
  /// for all of them: there is no marker left for it to paint at a size of its own.
  @Test @MainActor func drawnMarkerReplacesTheNativeInk() throws {
    let latin = "• hello world"
    let cjk = "• \u{4F60}\u{597D}\u{4E16}\u{754C}"
    let (view, window) = markerEditor(latin + "\n" + cjk)
    defer { window.contentView = nil }
    let layoutManager = try #require(view.layoutManager)
    let storage = try #require(view.textStorage)
    view.normalizeListMarkerFonts()
    view.refreshChecklistPresentation()

    let cjkMarkerIndex = latin.utf16.count + 1
    let cleared = layoutManager.temporaryAttribute(
      .foregroundColor,
      atCharacterIndex: cjkMarkerIndex,
      effectiveRange: nil
    ) as? NSColor
    #expect(cleared == .clear)
    let latinInk = layoutManager.temporaryAttribute(
      .foregroundColor,
      atCharacterIndex: 0,
      effectiveRange: nil
    ) as? NSColor
    #expect(latinInk == .clear)

    let drawn = view.drawnListMarkerPresentations
    #expect(drawn.count == 2)
    #expect(drawn.map(\.range.location) == [0, cjkMarkerIndex])
    let body = EditorTypography.bodyFont(family: ".AppleSystemUIFont", size: 17)
    let stored = try #require(
      storage.attribute(.font, at: cjkMarkerIndex, effectiveRange: nil) as? NSFont
    )
    #expect(abs(stored.pointSize - body.pointSize) < 0.01)
    #expect(drawn.allSatisfy { abs($0.font.pointSize - stored.pointSize) < 0.01 })
  }
#endif
