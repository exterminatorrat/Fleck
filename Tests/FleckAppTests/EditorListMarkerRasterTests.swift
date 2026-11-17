#if os(macOS)
  import AppKit
  import Testing

  @testable import FleckApp

  /// What a reader sees, not what the layout manager says: the editor is drawn
  /// into a bitmap on paper-white background in light appearance and the marker
  /// column is counted for ink. Build 208 passed every geometry and
  /// attributed-string assertion while painting no marker at all, so these tests
  /// rasterise.
  @MainActor
  private func rasterEditor(
    _ text: String,
    dark: Bool = false,
    family: String = ".AppleSystemUIFont"
  ) -> (ListAwareTextView, NSWindow) {
    let frame = NSRect(x: 0, y: 0, width: 480, height: 220)
    let view = ListAwareTextView(frame: frame)
    let window = NSWindow(
      contentRect: frame,
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )
    window.contentView = view
    view.configuredBodyFontFamily = family
    view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    view.drawsBackground = true
    view.backgroundColor = dark ? .black : .white
    view.textStorage?.setAttributedString(
      NSAttributedString(string: text, attributes: [
        .font: EditorTypography.bodyFont(family: family, size: 17),
        .paragraphStyle: EditorTypography.defaultParagraphStyle(fontSize: 17),
        .foregroundColor: dark ? NSColor.white : NSColor.black,
      ])
    )
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(view)
    return (view, window)
  }

  /// Rasterised ink in a view-space rect: pixels dark enough to be a glyph on
  /// white paper. Background-relative on purpose, so the count cannot be faked by
  /// a uniformly dark bitmap.
  @MainActor
  private func inkPixels(in view: ListAwareTextView, rect: NSRect, dark: Bool = false) -> Int {
    view.layoutSubtreeIfNeeded()
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return -1 }
    view.cacheDisplay(in: view.bounds, to: rep)
    let scale = CGFloat(rep.pixelsWide) / max(view.bounds.width, 1)
    let x0 = max(0, Int((rect.minX * scale).rounded(.down)))
    let x1 = min(rep.pixelsWide, Int((rect.maxX * scale).rounded(.up)))
    let y0 = max(0, Int((rect.minY * scale).rounded(.down)))
    let y1 = min(rep.pixelsHigh, Int((rect.maxY * scale).rounded(.up)))
    guard x0 < x1, y0 < y1 else { return -1 }
    var count = 0
    for y in y0..<y1 {
      for x in x0..<x1 {
        guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.genericRGB) else { continue }
        let luminance =
          0.299 * color.redComponent + 0.587 * color.greenComponent
          + 0.114 * color.blueComponent
        let isInk = dark ? luminance > 0.2 : luminance < 0.85
        if color.alphaComponent > 0.5 && isInk { count += 1 }
      }
    }
    return count
  }

  /// Marker ink for the paragraph that starts at `location`: the glyph rect of the
  /// marker character — the first non-space character, so an indented nested item
  /// measures its bullet and not the indentation.
  @MainActor
  private func markerInk(
    of view: ListAwareTextView,
    paragraphAt location: Int,
    dark: Bool = false
  ) -> Int {
    guard let layoutManager = view.layoutManager, let container = view.textContainer else {
      return -1
    }
    layoutManager.ensureLayout(for: container)
    let ns = view.string as NSString
    var marker = location
    while marker < ns.length, ns.character(at: marker) == 0x20 { marker += 1 }
    let glyphs = layoutManager.glyphRange(
      forCharacterRange: NSRange(location: marker, length: 1),
      actualCharacterRange: nil
    )
    guard glyphs.length > 0 else { return -1 }
    let column = layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
      .offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)
    return inkPixels(in: view, rect: column, dark: dark)
  }

  /// Blank paper to the right of the used text, as a control that the measurement
  /// reports no ink where there is none.
  @MainActor
  private func blankInk(of view: ListAwareTextView) -> Int {
    guard let layoutManager = view.layoutManager, let container = view.textContainer else {
      return -1
    }
    let used = layoutManager.usedRect(for: container)
    return inkPixels(
      in: view,
      rect: NSRect(
        x: view.textContainerOrigin.x + used.maxX + 40,
        y: view.textContainerOrigin.y,
        width: 40,
        height: min(24, container.size.height)
      )
    )
  }

  private func paragraphStarts(in text: String) -> [Int] {
    let ns = text as NSString
    var starts = [0]
    for index in 0..<ns.length where ns.character(at: index) == 0x0A {
      starts.append(index + 1)
    }
    return starts
  }

  /// A plain note with two list items paints both markers. Build 208 drew no
  /// marker ink here at all, which is what Harry saw in every note.
  @Test @MainActor func plainListItemsPaintTheirMarkers() throws {
    let text = "• first item\n• second item"
    let (view, window) = rasterEditor(text)
    defer { window.contentView = nil }
    view.refreshChecklistPresentation()

    for start in paragraphStarts(in: text) {
      #expect(markerInk(of: view, paragraphAt: start) > 4, "paragraph at \(start)")
    }
    #expect(blankInk(of: view) == 0)
  }

  /// Every state a marker can be in still paints: nested, ideographic, empty, and
  /// with the caret or a selection in the paragraph.
  @Test @MainActor func everyListMarkerStatePaintsInk() throws {
    let text = """
      • top level
          • nested level
      • has the caret
      • inside a selection
      • \u{4F60}\u{597D}
      •
      """
    let (view, window) = rasterEditor(text)
    defer { window.contentView = nil }
    let ns = text as NSString
    view.refreshChecklistPresentation()
    view.setSelectedRange(
      NSRange(location: ns.range(of: "inside a selection").location, length: 4)
    )
    view.refreshChecklistPresentation()

    for start in paragraphStarts(in: text) {
      #expect(markerInk(of: view, paragraphAt: start) > 4, "paragraph at \(start)")
    }
  }

  /// The caret sitting in a list paragraph does not remove that paragraph's marker.
  @Test @MainActor func theCaretParagraphKeepsItsMarker() throws {
    let text = "• first item\n• second item"
    let (view, window) = rasterEditor(text)
    defer { window.contentView = nil }
    let second = paragraphStarts(in: text)[1]
    view.setSelectedRange(NSRange(location: 0, length: 0))
    view.refreshChecklistPresentation()
    let awayFromIt = markerInk(of: view, paragraphAt: second)
    view.setSelectedRange(NSRange(location: second + 2, length: 0))
    view.refreshChecklistPresentation()
    let withTheCaret = markerInk(of: view, paragraphAt: second)
    #expect(awayFromIt > 4)
    #expect(withTheCaret > 4)
  }

  /// A list paragraph's first line sits at the same place inside its line box as a
  /// plain paragraph's, so no marker font can lift it the way Build 207 did.
  @Test @MainActor func listParagraphKeepsAPlainParagraphBaseline() throws {
    let text = "plain paragraph\n• list paragraph"
    let (view, window) = rasterEditor(text)
    defer { window.contentView = nil }
    let storage = try #require(view.textStorage)
    let layoutManager = try #require(view.layoutManager)
    let container = try #require(view.textContainer)
    let ns = text as NSString
    let plain = ns.range(of: "plain paragraph")
    let list = ns.range(of: "list paragraph")

    func glyphOffset(at location: Int) -> CGFloat {
      layoutManager.ensureLayout(for: container)
      return layoutManager.location(
        forGlyphAt: layoutManager.glyphIndexForCharacter(at: location)
      ).y
    }
    func fragmentHeight(at location: Int) -> CGFloat {
      layoutManager.ensureLayout(for: container)
      return layoutManager.lineFragmentRect(
        forGlyphAt: layoutManager.glyphIndexForCharacter(at: location),
        effectiveRange: nil,
        withoutAdditionalLayout: true
      ).height
    }

    view.normalizeListMarkerFonts()
    view.refreshChecklistPresentation()

    #expect(abs(glyphOffset(at: plain.location) - glyphOffset(at: list.location)) < 0.01)
    #expect(abs(fragmentHeight(at: plain.location) - fragmentHeight(at: list.location)) < 0.01)

    let bodyFont = EditorTypography.bodyFont(
      family: ".AppleSystemUIFont",
      size: 17
    )
    let markerFont = try #require(
      storage.attribute(.font, at: list.location - 2, effectiveRange: nil) as? NSFont
    )
    #expect(abs(markerFont.pointSize - bodyFont.pointSize) < 0.01)
  }
  /// The drawn marker resolves its ink from storage, not from the temporary colour
  /// that hides the native glyph, and that holds in the dark appearance the note is
  /// read in as well.
  @Test @MainActor func scaledMarkerPaintsInDarkAppearance() throws {
    let text = "• \u{4F60}\u{597D} world"
    let (view, window) = rasterEditor(text, dark: true)
    defer { window.contentView = nil }
    view.refreshChecklistPresentation()
    view.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
    view.refreshChecklistPresentation()
    #expect(markerInk(of: view, paragraphAt: 0, dark: true) > 4)
  }
  /// A byte-exact signature of one paragraph's marker: the rasterised pixels of the
  /// marker column, row by row. Two ink counts can agree while a glyph has moved, so
  /// the comparisons below use the pixels themselves.
  @MainActor
  private func markerSignature(of view: ListAwareTextView, paragraphAt location: Int)
    -> String
  {
    guard let layoutManager = view.layoutManager, let container = view.textContainer,
      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
    else { return "" }
    layoutManager.ensureLayout(for: container)
    let ns = view.string as NSString
    var marker = location
    while marker < ns.length, ns.character(at: marker) == 0x20 { marker += 1 }
    guard marker < ns.length else { return "" }
    let glyphs = layoutManager.glyphRange(
      forCharacterRange: NSRange(location: marker, length: 1),
      actualCharacterRange: nil
    )
    guard glyphs.length > 0 else { return "" }
    let column = layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
      .offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)
      .insetBy(dx: -3, dy: -6)
    view.cacheDisplay(in: view.bounds, to: rep)
    let scale = CGFloat(rep.pixelsWide) / max(view.bounds.width, 1)
    let x0 = max(0, Int((column.minX * scale).rounded(.down)))
    let x1 = min(rep.pixelsWide, Int((column.maxX * scale).rounded(.up)))
    let y0 = max(0, Int((column.minY * scale).rounded(.down)))
    let y1 = min(rep.pixelsHigh, Int((column.maxY * scale).rounded(.up)))
    guard x0 < x1, y0 < y1 else { return "" }
    var ink = 0
    var bits = ""
    bits.reserveCapacity((x1 - x0) * (y1 - y0))
    for y in y0..<y1 {
      for x in x0..<x1 {
        guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.genericRGB) else {
          bits.append("0")
          continue
        }
        let luminance =
          0.299 * color.redComponent + 0.587 * color.greenComponent
          + 0.114 * color.blueComponent
        let isInk = color.alphaComponent > 0.5 && luminance < 0.85
        if isInk { ink += 1 }
        bits.append(isInk ? "1" : "0")
      }
    }
    return "\(x1 - x0)x\(y1 - y0)@\(x0),\(y0) ink=\(ink) \(bits)"
  }

  @MainActor
  private func setRunFont(
    _ font: NSFont,
    paragraphAt location: Int,
    in view: ListAwareTextView
  ) {
    guard let storage = view.textStorage else { return }
    let ns = view.string as NSString
    storage.addAttribute(
      .font,
      value: font,
      range: ns.paragraphRange(for: NSRange(location: location, length: 0))
    )
  }

  /// Every text list marker is drawn by the view, so the text system has none left to
  /// paint at a size of its own. A marker it did paint would be the fallback that made
  /// a bullet change size under Harry's caret.
  @Test @MainActor func everyListMarkerIsDrawnByTheView() throws {
    let text = "• top level\n    • nested level\n1. numbered\n• \u{4F60}\u{597D}\n• "
    let (view, window) = rasterEditor(text)
    defer { window.contentView = nil }
    let ns = text as NSString
    view.refreshChecklistPresentation()

    var expected: [NSRange] = []
    for start in paragraphStarts(in: text) {
      let paragraph = ns.paragraphRange(for: NSRange(location: start, length: 0))
      var marker = start
      while marker < NSMaxRange(paragraph), ns.character(at: marker) == 0x20 { marker += 1 }
      guard marker < NSMaxRange(paragraph) else { continue }
      var end = marker
      while end < NSMaxRange(paragraph), ns.character(at: end) != 0x20 { end += 1 }
      expected.append(NSRange(location: marker, length: end - marker))
    }
    #expect(expected.count == 5)
    #expect(view.drawnListMarkerPresentations.map(\.range) == expected)
  }

  /// Moving the insertion point through a note with mixed run fonts and an empty item
  /// re-registers every marker. None of them may change a single pixel while it does,
  /// and every filled line keeps the one marker the note wears: a line whose marker
  /// differed from its neighbour's would alternate on the way past it.
  @Test @MainActor func movingTheCaretNeverChangesAMarker() throws {
    let text = "• hello world\n• \u{4F60}\u{597D}\u{4E16}\u{754C}\n• \n• \u{518D}\u{89C1}"
    let (view, window) = rasterEditor(text, family: "Avenir Next")
    defer { window.contentView = nil }
    let avenir = try #require(NSFont(name: "AvenirNext-Regular", size: 17))
    let pingfang = try #require(NSFont(name: "PingFangSC-Regular", size: 17))
    let starts = paragraphStarts(in: text)
    for (index, start) in starts.enumerated() {
      setRunFont(index.isMultiple(of: 2) ? avenir : pingfang, paragraphAt: start, in: view)
    }
    view.normalizeListMarkerFonts()
    view.refreshChecklistPresentation()

    let end = (text as NSString).length
    var baseline: [Int: String] = [:]
    for _ in 0..<2 {
      for start in starts {
        view.setSelectedRange(NSRange(location: start, length: 0))
        view.refreshChecklistPresentation()
        view.setSelectedRange(NSRange(location: end, length: 0))
        view.refreshChecklistPresentation()
        for paragraph in starts {
          let signature = markerSignature(of: view, paragraphAt: paragraph)
          if let recorded = baseline[paragraph] {
            #expect(signature == recorded, "paragraph at \(paragraph)")
          } else {
            #expect(!signature.isEmpty)
            baseline[paragraph] = signature
          }
        }
      }
    }
    #expect(baseline.count == starts.count)

    let ns = text as NSString
    let filled = starts.filter { start in
      let paragraph = ns.paragraphRange(for: NSRange(location: start, length: 0))
      return ns.substring(with: paragraph).trimmingCharacters(in: .whitespacesAndNewlines) != "•"
    }
    #expect(filled.count == 3)
    let inks = filled.map { markerInk(of: view, paragraphAt: $0) }
    #expect(inks.allSatisfy { $0 > 4 })
    #expect(Set(inks).count == 1, "marker ink per line \(inks)")
  }

  /// The run font cannot reach the marker: the same text in Avenir Next and in
  /// PingFang SC draws the same pixels in the marker column.
  @Test @MainActor func swappingTheRunFamilyLeavesTheMarkerAlone() throws {
    let text = "• \u{4F60}\u{597D}\u{4E16}\u{754C}"
    let avenir = try #require(NSFont(name: "AvenirNext-Regular", size: 17))
    let pingfang = try #require(NSFont(name: "PingFangSC-Regular", size: 17))
    var signatures: [String] = []
    for font in [avenir, pingfang] {
      let (view, window) = rasterEditor(text, family: "Avenir Next")
      defer { window.contentView = nil }
      setRunFont(font, paragraphAt: 0, in: view)
      view.normalizeListMarkerFonts()
      view.setSelectedRange(
        NSRange(location: (text as NSString).length, length: 0)
      )
      view.refreshChecklistPresentation()
      let markerFont = try #require(view.drawnListMarkerPresentations.first?.font)
      #expect(markerFont.familyName == "Avenir Next")
      signatures.append(markerSignature(of: view, paragraphAt: 0))
    }
    #expect(!signatures[0].isEmpty)
    #expect(signatures[0] == signatures[1])
  }

  /// Typing a character refreshes the paragraph. The marker's pixels are not allowed
  /// to move or change weight because of it, not even when the character typed is one
  /// that would make the line read as ideographic.
  @Test @MainActor func appendingACharacterLeavesTheMarkerAlone() throws {
    let text = "• hello"
    let (view, window) = rasterEditor(text, family: "Avenir Next")
    defer { window.contentView = nil }
    let storage = try #require(view.textStorage)
    view.refreshChecklistPresentation()
    let before = markerSignature(of: view, paragraphAt: 0)

    let end = storage.length
    view.setSelectedRange(NSRange(location: end, length: 0))
    view.insertText("\u{5B57}", replacementRange: NSRange(location: end, length: 0))
    view.refreshChecklistPresentation()
    view.setSelectedRange(NSRange(location: storage.length, length: 0))
    view.refreshChecklistPresentation()

    #expect(!before.isEmpty)
    #expect(markerSignature(of: view, paragraphAt: 0) == before)
  }
#endif
