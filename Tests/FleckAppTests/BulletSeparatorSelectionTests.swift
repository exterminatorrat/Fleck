import AppKit
import Testing

@testable import FleckApp

@MainActor
private func separatorEditor(
  _ text: String,
  allowsUndo: Bool = false
) -> (ListAwareTextView, NSWindow) {
  let frame = NSRect(x: 0, y: 0, width: 360, height: 180)
  let textView = ListAwareTextView(frame: frame)
  let window = NSWindow(
    contentRect: frame,
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = textView
  textView.allowsUndo = allowsUndo
  textView.string = text
  return (textView, window)
}

private func partiallyCovers(_ range: NSRange, prefix: NSRange) -> Bool {
  let overlap = NSIntersectionRange(range, prefix).length
  return overlap > 0 && overlap < prefix.length
}

private func pixelColor(
  at point: NSPoint,
  bitmap: NSBitmapImageRep,
  scale: CGFloat
) -> NSColor? {
  bitmap.colorAt(x: Int(point.x * scale), y: Int(point.y * scale))?.usingColorSpace(.sRGB)
}

private func pixelColorsDiffer(_ first: NSColor, _ second: NSColor) -> Bool {
  abs(first.redComponent - second.redComponent) > 0.05
    || abs(first.greenComponent - second.greenComponent) > 0.05
    || abs(first.blueComponent - second.blueComponent) > 0.05
}

private func pixelColorsMatch(_ first: NSColor, _ second: NSColor) -> Bool {
  abs(first.redComponent - second.redComponent) <= 0.05
    && abs(first.greenComponent - second.greenComponent) <= 0.05
    && abs(first.blueComponent - second.blueComponent) <= 0.05
    && abs(first.alphaComponent - second.alphaComponent) <= 0.05
}

private func structuralPrefixIntact(_ text: String) -> Bool {
  let firstLine =
    text.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? ""
  return firstLine.hasPrefix("• ")
    && EditorListEngine.parse(firstLine)?.style == .bullet(.disc)
}

@Suite("BulletSeparatorSelectionTests")
@MainActor
struct BulletSeparatorSelectionTests {
  @Test func separatorSelectionExpandsToTheWholeStructuralPrefix() {
    let (textView, window) = separatorEditor("• text")
    defer { window.contentView = nil }

    textView.setSelectedRange(NSRange(location: 1, length: 1))

    #expect(textView.selectedRange() == NSRange(location: 0, length: 2))
  }

  @Test func nestedSeparatorSelectionKeepsIndentationOutsideTheStructuralPrefix() {
    let (textView, window) = separatorEditor("    ◦ text")
    defer { window.contentView = nil }

    textView.setSelectedRange(NSRange(location: 5, length: 1))

    #expect(textView.selectedRange() == NSRange(location: 4, length: 2))
  }

  @Test func caretInsideTheStructuralPrefixStillCollapsesToContentStart() {
    let (textView, window) = separatorEditor("• text")
    defer { window.contentView = nil }

    textView.setSelectedRange(NSRange(location: 1, length: 0))
    #expect(textView.selectedRange() == NSRange(location: 2, length: 0))

    textView.setSelectedRange(NSRange(location: 0, length: 0))
    #expect(textView.selectedRange() == NSRange(location: 2, length: 0))
  }

  @Test func characterGranularitySelectionSnapsToTheStructuralPrefix() {
    let (textView, window) = separatorEditor("• text")
    defer { window.contentView = nil }

    let range = textView.selectionRange(
      forProposedRange: NSRange(location: 1, length: 1),
      granularity: .selectByCharacter
    )

    #expect(range == NSRange(location: 0, length: 2))
  }

  @Test func wordAndParagraphGranularityProposalsNeverExposeAPartialPrefix() {
    let (textView, window) = separatorEditor("• text")
    defer { window.contentView = nil }

    let prefix = NSRange(location: 0, length: 2)
    for granularity in [
      NSSelectionGranularity.selectByCharacter,
      .selectByWord,
      .selectByParagraph,
    ] {
      for proposal in [NSRange(location: 1, length: 1), NSRange(location: 0, length: 1)] {
        let range = textView.selectionRange(
          forProposedRange: proposal,
          granularity: granularity
        )
        #expect(!partiallyCovers(range, prefix: prefix))
      }
    }
  }

  @Test func shiftLeftFromContentStartNeverLeavesAPartialPrefixSelected() {
    let (textView, window) = separatorEditor("• text")
    defer { window.contentView = nil }
    #expect(window.makeFirstResponder(textView))

    textView.setSelectedRange(NSRange(location: 2, length: 0))
    textView.moveLeftAndModifySelection(nil)

    #expect(textView.selectedRange() == NSRange(location: 0, length: 2))
  }

  @Test func multiSelectionSnapsEachTouchedStructuralPrefix() {
    let (textView, window) = separatorEditor("• one\n• two")
    defer { window.contentView = nil }

    textView.setSelectedRanges(
      [
        NSValue(range: NSRange(location: 1, length: 1)),
        NSValue(range: NSRange(location: 7, length: 1)),
      ],
      affinity: .downstream,
      stillSelecting: false
    )

    #expect(
      textView.selectedRanges.map(\.rangeValue) == [
        NSRange(location: 0, length: 2),
        NSRange(location: 6, length: 2),
      ]
    )
  }

  @Test func multilineSelectionIsUnchangedAndStillCoversWholeItems() {
    let text = "• one\n• two"
    let (textView, window) = separatorEditor(text)
    defer { window.contentView = nil }

    textView.setSelectedRange(NSRange(location: 0, length: text.utf16.count))
    #expect(textView.selectedRange() == NSRange(location: 0, length: text.utf16.count))

    textView.deleteBackward(nil)

    #expect(textView.string.isEmpty)
  }

  @Test func bodySelectionAfterTheSeparatorIsUnchanged() {
    let (textView, window) = separatorEditor("• text")
    defer { window.contentView = nil }

    textView.setSelectedRange(NSRange(location: 2, length: 4))

    #expect(textView.selectedRange() == NSRange(location: 2, length: 4))
  }

  @Test func interveningBulletSelectionStateNeverExposesAPartialPrefix() {
    let text = "• first\n• second"
    let (textView, window) = separatorEditor(text)
    defer { window.contentView = nil }

    textView.setSelectedRange(NSRange(location: 2, length: text.utf16.count - 2))
    #expect(textView.selectedRange() == NSRange(location: 2, length: text.utf16.count - 2))

    textView.setSelectedRange(NSRange(location: 9, length: 1))
    #expect(textView.selectedRange() == NSRange(location: 8, length: 2))
  }

  @Test func backspaceAtContentStartRemovesTheWholeMarkerOnce() throws {
    let (textView, window) = separatorEditor("• text", allowsUndo: true)
    defer { window.contentView = nil }

    textView.setSelectedRange(NSRange(location: 2, length: 0))
    textView.deleteBackward(nil)

    #expect(textView.string == "text")
    #expect(textView.selectedRange() == NSRange(location: 0, length: 0))

    let undoManager = try #require(textView.undoManager)
    #expect(undoManager.canUndo)
    undoManager.undo()
    #expect(textView.string == "• text")
  }

  @Test func backspaceInsideTheBodyDeletesOneCharacter() {
    let (textView, window) = separatorEditor("• text")
    defer { window.contentView = nil }

    textView.setSelectedRange(NSRange(location: 4, length: 0))
    textView.deleteBackward(nil)

    #expect(textView.string == "• txt")
    #expect(textView.selectedRange() == NSRange(location: 3, length: 0))
  }

  @Test func backspaceKeepsLeadingBodySpacesIndividuallyEditable() {
    let (textView, window) = separatorEditor("•  item")
    defer { window.contentView = nil }

    textView.setSelectedRange(NSRange(location: 3, length: 0))
    textView.deleteBackward(nil)

    #expect(textView.string == "• item")
    #expect(textView.selectedRange() == NSRange(location: 2, length: 0))
  }

  @Test func forwardDeleteAtContentStartDeletesBodyOnly() {
    let (textView, window) = separatorEditor("• text")
    defer { window.contentView = nil }

    textView.setSelectedRange(NSRange(location: 2, length: 0))
    textView.deleteForward(nil)

    #expect(textView.string == "• ext")
    #expect(textView.selectedRange() == NSRange(location: 2, length: 0))
  }

  @Test func forwardDeleteOnWholeMarkerSelectionRemovesTheWholePrefix() {
    let (textView, window) = separatorEditor("• text")
    defer { window.contentView = nil }

    textView.setSelectedRange(NSRange(location: 0, length: 2))
    textView.deleteForward(nil)

    #expect(textView.string == "text")
  }

  @Test func optionDeleteAtContentStartRemovesTheWholeMarkerOnce() throws {
    let (textView, window) = separatorEditor("• text", allowsUndo: true)
    defer { window.contentView = nil }

    textView.setSelectedRange(NSRange(location: 2, length: 0))
    textView.deleteWordBackward(nil)

    #expect(textView.string == "text")
    #expect(textView.selectedRange() == NSRange(location: 0, length: 0))

    let undoManager = try #require(textView.undoManager)
    #expect(undoManager.canUndo)
    undoManager.undo()
    #expect(textView.string == "• text")
  }

  @Test func optionDeleteInsideTheBodyKeepsTheStructuralPrefixIntact() {
    let original = "• alphabet"
    let (textView, window) = separatorEditor(original)
    defer { window.contentView = nil }

    textView.setSelectedRange(NSRange(location: 4, length: 0))
    textView.deleteWordBackward(nil)

    #expect(textView.string.hasPrefix("• "))
    #expect(textView.string.utf16.count < original.utf16.count)
  }

  @Test func lineAndParagraphDeletionAtContentStartRemoveTheWholePrefix() {
    let cases = [(text: "• text", contentStart: 2), (text: "    ◦ text", contentStart: 6)]
    for item in cases {
      let (lineView, lineWindow) = separatorEditor(item.text)
      defer { lineWindow.contentView = nil }
      lineView.setSelectedRange(NSRange(location: item.contentStart, length: 0))
      lineView.deleteToBeginningOfLine(nil)
      #expect(lineView.string == "text")

      let (paragraphView, paragraphWindow) = separatorEditor(item.text)
      defer { paragraphWindow.contentView = nil }
      paragraphView.setSelectedRange(NSRange(location: item.contentStart, length: 0))
      paragraphView.deleteToBeginningOfParagraph(nil)
      #expect(paragraphView.string == "text")
    }
  }

  @Test func typingAtContentStartInsertsIntoTheBody() {
    let (textView, window) = separatorEditor("• text")
    defer { window.contentView = nil }

    textView.setSelectedRange(NSRange(location: 2, length: 0))
    textView.insertText("X", replacementRange: textView.selectedRange())

    #expect(textView.string == "• Xtext")
  }

  @Test func typingOnWholeMarkerSelectionReplacesTheWholePrefix() {
    let (textView, window) = separatorEditor("• text")
    defer { window.contentView = nil }

    textView.setSelectedRange(NSRange(location: 0, length: 2))
    textView.insertText("X", replacementRange: textView.selectedRange())

    #expect(textView.string == "Xtext")
  }

  @Test func explicitSeparatorReplacementRangeCannotSplitThePrefix() {
    let (textView, window) = separatorEditor("• text")
    defer { window.contentView = nil }

    textView.insertText("X", replacementRange: NSRange(location: 1, length: 1))

    #expect(textView.string == "Xtext")
  }

  @Test(arguments: [true, false])
  func optionDeleteFromBodyPositionsKeepsTheStructuralPrefix(smartInsertDeleteEnabled: Bool) {
    let cases: [(text: String, carets: [Int])] = [
      ("• alpha", [4, 7]),
      ("• alpha beta", [4, 7, 8, 12]),
    ]
    for item in cases {
      for caret in item.carets {
        let (textView, window) = separatorEditor(item.text)
        defer { window.contentView = nil }
        textView.smartInsertDeleteEnabled = smartInsertDeleteEnabled
        textView.setSelectedRange(NSRange(location: caret, length: 0))
        textView.deleteWordBackward(nil)
        #expect(structuralPrefixIntact(textView.string))
        #expect(textView.string.utf16.count < item.text.utf16.count)
      }
    }
  }

  @Test(arguments: [true, false])
  func selectionDeletionOfTheBodyKeepsTheStructuralPrefix(smartInsertDeleteEnabled: Bool) {
    let text = "• alpha"
    for forward in [false, true] {
      let (textView, window) = separatorEditor(text)
      defer { window.contentView = nil }
      textView.smartInsertDeleteEnabled = smartInsertDeleteEnabled
      textView.setSelectedRange(NSRange(location: 2, length: 5))
      if forward {
        textView.deleteForward(nil)
      } else {
        textView.deleteBackward(nil)
      }
      #expect(structuralPrefixIntact(textView.string))
      #expect(textView.string.utf16.count < text.utf16.count)
    }
  }

  @Test func smartDeleteRangeOfABodyRangeDoesNotConsumeTheSeparator() {
    let (textView, window) = separatorEditor("• alpha")
    defer { window.contentView = nil }

    for smartInsertDeleteEnabled in [true, false] {
      textView.smartInsertDeleteEnabled = smartInsertDeleteEnabled
      let expanded = textView.smartDeleteRange(forProposedRange: NSRange(location: 2, length: 5))
      #expect(expanded.location != NSNotFound)
      #expect(expanded.length == 0 || expanded.location >= 2)
    }
  }

  @Test(arguments: [true, false])
  func smartDeleteRangeClampsBodyOnlyProposalsToTheContentStart(
    smartInsertDeleteEnabled: Bool
  ) {
    let cases: [(text: String, prefix: NSRange, proposal: NSRange)] = [
      ("• alpha", NSRange(location: 0, length: 2), NSRange(location: 2, length: 5)),
      ("    ◦ alpha", NSRange(location: 4, length: 2), NSRange(location: 6, length: 5)),
      ("• alpha beta", NSRange(location: 0, length: 2), NSRange(location: 8, length: 4)),
    ]
    for item in cases {
      let (textView, window) = separatorEditor(item.text)
      defer { window.contentView = nil }
      textView.smartInsertDeleteEnabled = smartInsertDeleteEnabled

      let expanded = textView.smartDeleteRange(forProposedRange: item.proposal)

      #expect(expanded.location != NSNotFound)
      #expect(NSIntersectionRange(expanded, item.prefix).length == 0)
      #expect(expanded.location <= item.proposal.location)
      #expect(NSMaxRange(expanded) >= NSMaxRange(item.proposal))
    }
  }

  @Test(arguments: [true, false])
  func smartDeleteRangeKeepsADeliberatelySelectedPrefix(smartInsertDeleteEnabled: Bool) {
    let (textView, window) = separatorEditor("• alpha")
    defer { window.contentView = nil }
    textView.smartInsertDeleteEnabled = smartInsertDeleteEnabled

    let expanded = textView.smartDeleteRange(forProposedRange: NSRange(location: 0, length: 7))

    #expect(expanded.location == 0)
    #expect(NSMaxRange(expanded) == 7)
  }

  @Test func smartDeleteRangeDoesNotReachAPrefixOnTheFollowingLine() {
    let (textView, window) = separatorEditor("text\n• alpha")
    defer { window.contentView = nil }
    textView.smartInsertDeleteEnabled = true

    let expanded = textView.smartDeleteRange(forProposedRange: NSRange(location: 0, length: 4))

    #expect(NSIntersectionRange(expanded, NSRange(location: 5, length: 2)).length == 0)
  }

  @Test func smartDeleteRangeKeepsBodyWhitespaceExpansion() {
    let (textView, window) = separatorEditor("• alpha beta")
    defer { window.contentView = nil }
    textView.smartInsertDeleteEnabled = true

    let expanded = textView.smartDeleteRange(forProposedRange: NSRange(location: 8, length: 4))

    #expect(NSIntersectionRange(expanded, NSRange(location: 0, length: 2)).length == 0)
    #expect(expanded.location <= 8)
    #expect(NSMaxRange(expanded) >= 12)
  }

  @Test func nestedBackspaceUndoRestoresStringAndAttributes() throws {
    let original = "• Parent\n    ◦ item text"
    let (textView, window) = separatorEditor(original, allowsUndo: true)
    defer { window.contentView = nil }
    let nestedStart = ("• Parent\n" as NSString).length
    let contentStart = nestedStart + 6
    textView.textStorage?.addAttribute(
      .foregroundColor,
      value: NSColor.systemRed,
      range: NSRange(location: nestedStart, length: original.utf16.count - nestedStart)
    )
    textView.textStorage?.addAttribute(
      .foregroundColor,
      value: NSColor.systemBlue,
      range: NSRange(location: contentStart, length: 9)
    )
    textView.setSelectedRange(NSRange(location: contentStart, length: 0))

    textView.deleteBackward(nil)

    #expect(textView.string == "• Parent\nitem text")
    #expect(textView.selectedRange() == NSRange(location: nestedStart, length: 0))

    let undoManager = try #require(textView.undoManager)
    undoManager.undo()

    #expect(textView.string == original)
    #expect(
      textView.textStorage?.attribute(.foregroundColor, at: nestedStart + 4, effectiveRange: nil)
        as? NSColor == NSColor.systemRed
    )
    #expect(
      textView.textStorage?.attribute(.foregroundColor, at: contentStart, effectiveRange: nil)
        as? NSColor == NSColor.systemBlue
    )

    undoManager.redo()
    #expect(textView.string == "• Parent\nitem text")
  }

  @Test(arguments: [false, true], [false, true])
  func separatorGapStaysUnhighlightedInSyntheticRender(
    isDark: Bool,
    drawsBackground: Bool
  ) throws {
    let text = "• first\n    ◦ second\nplain"
    let (textView, window) = separatorEditor(text)
    defer { window.contentView = nil }
    let host = NSView(frame: textView.bounds)
    host.wantsLayer = true
    host.layer?.backgroundColor = (isDark ? NSColor.black : NSColor.white).cgColor
    textView.removeFromSuperview()
    textView.frame = host.bounds
    textView.autoresizingMask = [.width, .height]
    host.addSubview(textView)
    window.contentView = host
    textView.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
    textView.drawsBackground = drawsBackground
    textView.textColor = isDark ? .white : .black
    textView.textStorage?.addAttribute(
      .font,
      value: NSFont.systemFont(ofSize: 24),
      range: NSRange(location: 0, length: textView.string.utf16.count)
    )
    #expect(window.makeFirstResponder(textView))
    let referenceBitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: referenceBitmap)
    let referenceScale = CGFloat(referenceBitmap.pixelsWide) / host.bounds.width
    let referenceBackground = try #require(
      pixelColor(
        at: NSPoint(x: host.bounds.maxX - 10, y: host.bounds.maxY - 10),
        bitmap: referenceBitmap,
        scale: referenceScale
      )
    )
    textView.setSelectedRange(NSRange(location: 0, length: text.utf16.count))
    textView.displayIfNeeded()
    window.displayIfNeeded()

    let layoutManager = try #require(textView.layoutManager)
    let textContainer = try #require(textView.textContainer)
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width

    func backgroundSample(at range: NSRange) -> NSColor? {
      let glyphRange = layoutManager.glyphRange(
        forCharacterRange: range,
        actualCharacterRange: nil
      )
      let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        .offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
      return pixelColor(
        at: NSPoint(x: rect.midX, y: rect.maxY - 2),
        bitmap: bitmap,
        scale: scale
      )
    }

    let separatorBackground = try #require(backgroundSample(at: NSRange(location: 13, length: 1)))
    let bodyBackground = try #require(backgroundSample(at: NSRange(location: 14, length: 6)))
    #expect(pixelColorsDiffer(bodyBackground, referenceBackground))
    #expect(pixelColorsMatch(separatorBackground, referenceBackground))

    if let evidenceDirectory = ProcessInfo.processInfo.environment["FLECK_EDITOR_EVIDENCE_DIR"] {
      let png = try #require(bitmap.representation(using: .png, properties: [:]))
      let name = "bullet-separator-gap-\(isDark ? "dark" : "light")-"
        + "\(drawsBackground ? "opaque" : "transparent").png"
      try png.write(
        to: URL(fileURLWithPath: evidenceDirectory).appendingPathComponent(name)
      )
    }
  }
}
