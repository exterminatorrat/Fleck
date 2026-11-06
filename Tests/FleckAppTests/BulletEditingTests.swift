import AppKit
import Testing

@testable import FleckApp

@MainActor
private func bulletEditor(_ text: String) -> (ListAwareTextView, NSWindow) {
  let frame = NSRect(x: 0, y: 0, width: 360, height: 180)
  let textView = ListAwareTextView(frame: frame)
  let window = NSWindow(
    contentRect: frame,
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = textView
  textView.allowsUndo = true
  textView.string = text
  return (textView, window)
}

private func threeSpaceTabInterval(for font: NSFont) -> CGFloat {
  3 * (" " as NSString).size(withAttributes: [.font: font]).width
}

@Test @MainActor func nestedBulletFirstTabRetainsItsThreeSpaceGrid() throws {
  let font = NSFont.systemFont(ofSize: 17)
  let paragraph = EditorTypography.defaultParagraphStyle(fontSize: font.pointSize)
  let (view, window) = bulletEditor("    ◦ item")
  defer { window.contentView = nil }
  view.textStorage?.setAttributedString(NSAttributedString(
    string: view.string, attributes: [.font: font, .paragraphStyle: paragraph]
  ))
  view.setSelectedRange(NSRange(location: 6, length: 0))
  view.insertTab(nil)
  #expect(view.string == "    ◦ \titem")
  let style = try #require(
    view.textStorage?.attribute(.paragraphStyle, at: 6, effectiveRange: nil) as? NSParagraphStyle
  )
  #expect(abs(style.defaultTabInterval - threeSpaceTabInterval(for: font)) < 0.01)
  #expect(style.tabStops.isEmpty)
  #expect(style.minimumLineHeight == paragraph.minimumLineHeight)
  #expect(style.maximumLineHeight == paragraph.maximumLineHeight)
}

@Test(arguments: [false, true], [false, true])
@MainActor func bulletTabDoesNotMigratePersistedThreeSpaceOrCustomGrid(
  _ explicitStop: Bool, _ existingTab: Bool
) throws {
  let font = NSFont.systemFont(ofSize: 17)
  let paragraph = NSMutableParagraphStyle()
  paragraph.defaultTabInterval = threeSpaceTabInterval(for: font)
  paragraph.tabStops = explicitStop
    ? [NSTextTab(textAlignment: .right, location: 72, options: [:])] : []
  paragraph.firstLineHeadIndent = 4
  paragraph.headIndent = 12
  paragraph.tailIndent = -8
  paragraph.lineSpacing = 3
  let source = NSAttributedString(string: existingTab ? "• \titem" : "• item", attributes: [
    .font: font, .paragraphStyle: paragraph, .underlineStyle: 1,
  ])
  let restored = try NoteRichTextCodec.decode(NoteRichTextCodec.encode(source))
  let (view, window) = bulletEditor(restored.string)
  defer { window.contentView = nil }
  view.textStorage?.setAttributedString(restored)
  let location = existingTab ? 3 : 2
  let expected = existingTab ? "• \t\titem" : "• \titem"
  view.setSelectedRange(NSRange(location: location, length: 0))
  let originalStyle = try #require(restored.attribute(.paragraphStyle, at: 0, effectiveRange: nil))
  view.undoManager?.removeAllActions()
  view.insertTab(nil)
  #expect(view.string == expected)
  #expect(view.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
    == originalStyle as? NSParagraphStyle)
  let saved = try NoteRichTextCodec.decode(NoteRichTextCodec.encode(try #require(view.textStorage)))
  #expect(saved.string == view.string)
  #expect(saved.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
    == originalStyle as? NSParagraphStyle)
  let undo = try #require(view.undoManager)
  undo.undo()
  #expect(view.string == restored.string)
  #expect(view.selectedRange() == NSRange(location: location, length: 0))
  undo.redo()
  #expect(view.string == expected)
  #expect(view.selectedRange() == NSRange(location: location + 1, length: 0))
}

@Test(arguments: [false, true])
@MainActor func explicitBulletTabChoosesAppDefaultForUnspecifiedSettingsIncludingRTF(
  _ throughRTF: Bool
) throws {
  let paragraph = EditorTypography.defaultParagraphStyle(fontSize: 17)
  let source = NSAttributedString(string: "• item", attributes: [
    .font: NSFont.systemFont(ofSize: 17), .paragraphStyle: paragraph, .underlineStyle: 1,
  ])
  let content = throughRTF ? try NoteRichTextCodec.decode(NoteRichTextCodec.encode(source)) : source
  let previous = try #require(content.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
  try #require(previous.defaultTabInterval == paragraph.defaultTabInterval)
  try #require(previous.tabStops == paragraph.tabStops)
  let (view, window) = bulletEditor(content.string)
  defer { window.contentView = nil }
  view.textStorage?.setAttributedString(content)
  view.setSelectedRange(NSRange(location: 2, length: 0))
  view.insertTab(nil)
  #expect(view.string == "• \titem")
  #expect(view.selectedRange() == NSRange(location: 3, length: 0))
  let storage = try #require(view.textStorage)
  let style = try #require(storage.attribute(.paragraphStyle, at: 2, effectiveRange: nil) as? NSParagraphStyle)
  #expect(style.defaultTabInterval == 36)
  #expect(style.tabStops.isEmpty)
  #expect(style.firstLineHeadIndent == previous.firstLineHeadIndent)
  #expect(style.headIndent == previous.headIndent)
  #expect(style.tailIndent == previous.tailIndent)
  #expect(style.minimumLineHeight == previous.minimumLineHeight)
  #expect(style.maximumLineHeight == previous.maximumLineHeight)
  #expect(storage.attribute(.underlineStyle, at: 3, effectiveRange: nil) as? Int == 1)
  let reopened = try NoteRichTextCodec.decode(NoteRichTextCodec.encode(storage))
  #expect(reopened.string == storage.string)
  #expect((reopened.attribute(.paragraphStyle, at: 2, effectiveRange: nil) as? NSParagraphStyle)?.defaultTabInterval == 36)
}

@Test @MainActor func bulletTabPreservesAnExistingTabUsingAppKitDefaultStops() throws {
  let paragraph = EditorTypography.defaultParagraphStyle(fontSize: 17)
  let (view, window) = bulletEditor("• \titem")
  defer { window.contentView = nil }
  view.textStorage?.addAttribute(.paragraphStyle, value: paragraph,
    range: NSRange(location: 0, length: view.string.utf16.count))
  view.setSelectedRange(NSRange(location: 3, length: 0))
  view.insertTab(nil)
  #expect(view.string == "• \t\titem")
  #expect(view.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
    == paragraph)
}

@Test @MainActor func markedTextTabUsesNativeCommandWithoutRewritingBulletParagraph() throws {
  let (view, window) = bulletEditor("• item")
  defer { window.contentView = nil }
  let reference = NSTextView(frame: NSRect(x: 0, y: 0, width: 360, height: 180))
  reference.string = "item"
  view.setSelectedRange(NSRange(location: 4, length: 0))
  reference.setSelectedRange(NSRange(location: 2, length: 0))
  for editor: NSTextView in [view, reference] {
    editor.setMarkedText("拼", selectedRange: NSRange(location: 1, length: 0),
      replacementRange: NSRange(location: NSNotFound, length: 0))
    #expect(editor.hasMarkedText())
    editor.insertTab(nil)
  }
  #expect(view.string == "• " + reference.string)
  #expect(view.hasMarkedText() == reference.hasMarkedText())
  #expect(view.selectedRange().location == reference.selectedRange().location + 2)
  #expect(view.selectedRange().length == reference.selectedRange().length)
}

@MainActor
private func expectSamePublicFont(_ actual: NSFont, as expected: NSFont) {
  #expect(actual.pointSize == expected.pointSize)
  #expect(actual.familyName == expected.familyName)
  #expect(NSFontManager.shared.traits(of: actual) == NSFontManager.shared.traits(of: expected))
}

private func rtfDefaultTabIntervalTwips(in data: Data) throws -> Int {
  let rtf = String(decoding: data, as: UTF8.self)
  let commandRange = try #require(
    rtf.range(of: #"\\deftab(\d+)"#, options: .regularExpression)
  )
  let command = String(rtf[commandRange])
  return try #require(Int(command.dropFirst(#"\deftab"#.count)))
}

@Test @MainActor func backspaceRemovesAnEmptyTopLevelBulletInOneUndoableAction() throws {
  let original = "Before\n• \nAfter"
  let (textView, _) = bulletEditor(original)
  let itemStart = ("Before\n" as NSString).length
  textView.textStorage?.addAttribute(
    .foregroundColor,
    value: NSColor.systemRed,
    range: NSRange(location: itemStart, length: 2)
  )
  textView.setSelectedRange(NSRange(location: itemStart + 2, length: 0))

  textView.deleteBackward(nil)

  #expect(textView.string == "Before\n\nAfter")
  #expect(textView.selectedRange() == NSRange(location: itemStart, length: 0))
  let undoManager = try #require(textView.undoManager)
  #expect(undoManager.canUndo)
  undoManager.undo()
  #expect(textView.string == original)
  #expect(
    textView.textStorage?.attribute(.foregroundColor, at: itemStart, effectiveRange: nil) as? NSColor
      == NSColor.systemRed
  )
  #expect(undoManager.canRedo)
  undoManager.redo()
  #expect(textView.string == "Before\n\nAfter")
}

@Test @MainActor func backspaceRemovesNestedBulletIndentAndLeavesCaretAtLeftMargin() {
  let (textView, _) = bulletEditor("• Parent\n    ◦ \n• Sibling")
  let itemStart = ("• Parent\n" as NSString).length
  textView.setSelectedRange(NSRange(location: itemStart + 6, length: 0))

  textView.deleteBackward(nil)

  #expect(textView.string == "• Parent\n\n• Sibling")
  #expect(textView.selectedRange() == NSRange(location: itemStart, length: 0))
}

@Test @MainActor func togglingMultilineEmptyBulletsPreservesReplacementSelection() {
  let (textView, _) = bulletEditor("• \n• ")
  textView.setSelectedRange(NSRange(location: 0, length: textView.string.utf16.count))

  textView.toggleList(.bullet(.disc))

  #expect(textView.string == "\n")
  #expect(textView.selectedRange() == NSRange(location: 0, length: 1))
}

@Test @MainActor func selectAllIncludesBulletPrefixesForCopyAndDelete() throws {
  let original = "• note"
  let (textView, window) = bulletEditor(original)
  #expect(window.makeFirstResponder(textView))

  textView.selectAll(nil)

  #expect(textView.selectedRange() == NSRange(location: 0, length: original.utf16.count))
  let pasteboard = NSPasteboard.withUniqueName()
  defer { pasteboard.releaseGlobally() }
  #expect(textView.writeSelection(to: pasteboard, types: textView.writablePasteboardTypes))
  #expect(pasteboard.string(forType: .string) == original)

  textView.deleteBackward(nil)

  #expect(textView.string.isEmpty)
}

@Test @MainActor func leftArrowAtBulletStartMovesToPreviousParagraphEnd() {
  let cases: [(text: String, bulletPrefix: String, previousParagraphEnd: Int)] = [
    ("Before\n• item", "Before\n• ", ("Before" as NSString).length),
    ("Before\n    ◦ item", "Before\n    ◦ ", ("Before" as NSString).length),
    ("• parent\n    ◦ nested", "• parent\n    ◦ ", ("• parent" as NSString).length),
  ]

  for item in cases {
    let (textView, _) = bulletEditor(item.text)
    let contentStart = (item.bulletPrefix as NSString).length
    textView.setSelectedRange(NSRange(location: contentStart, length: 0))

    textView.moveLeft(nil)

    #expect(
      textView.selectedRange()
        == NSRange(location: item.previousParagraphEnd, length: 0)
    )
  }
}

@Test @MainActor func collapsedTabInsertsANativeTabInsideBulletsAtStartMiddleAndEnd() {
  let cases: [(text: String, location: Int, expected: String)] = [
    ("• bullet", 2, "• \tbullet"),
    ("• bullet", 5, "• bul\tlet"),
    ("• bullet", 8, "• bullet\t"),
    ("    ◦ nested", 6, "    ◦ \tnested"),
  ]

  for item in cases {
    let (textView, _) = bulletEditor(item.text)
    textView.setSelectedRange(NSRange(location: item.location, length: 0))

    textView.insertTab(nil)

    #expect(textView.string == item.expected)
    #expect(textView.selectedRange() == NSRange(location: item.location + 1, length: 0))
  }
}

@Test @MainActor func oneBulletTabIsOneBackspaceAndArrowNavigationUnit() {
  let original = "• bullet"
  let (textView, _) = bulletEditor(original)
  textView.setSelectedRange(NSRange(location: 2, length: 0))

  textView.insertTab(nil)

  #expect(textView.string == "• \tbullet")
  #expect(textView.selectedRange() == NSRange(location: 3, length: 0))
  textView.moveLeft(nil)
  #expect(textView.selectedRange() == NSRange(location: 2, length: 0))
  textView.moveRight(nil)
  #expect(textView.selectedRange() == NSRange(location: 3, length: 0))

  textView.deleteBackward(nil)

  #expect(textView.string == original)
  #expect(textView.selectedRange() == NSRange(location: 2, length: 0))
}

@Test @MainActor func consecutiveBulletTabsAreSeparateBackspaceUnits() {
  let (textView, _) = bulletEditor("• item")
  textView.setSelectedRange(NSRange(location: 2, length: 0))

  textView.insertTab(nil)
  textView.insertTab(nil)

  #expect(textView.string == "• \t\titem")
  #expect(textView.selectedRange() == NSRange(location: 4, length: 0))
  textView.deleteBackward(nil)
  #expect(textView.string == "• \titem")
  #expect(textView.selectedRange() == NSRange(location: 3, length: 0))
  textView.deleteBackward(nil)
  #expect(textView.string == "• item")
  #expect(textView.selectedRange() == NSRange(location: 2, length: 0))
}

@Test @MainActor func manualSpacesRemainIndividuallyEditableBesideBulletTab() {
  let (textView, _) = bulletEditor("•   item")
  textView.setSelectedRange(NSRange(location: 4, length: 0))

  textView.insertTab(nil)

  #expect(textView.string == "•   \titem")
  #expect(textView.selectedRange() == NSRange(location: 5, length: 0))
  textView.deleteBackward(nil)
  #expect(textView.string == "•   item")
  #expect(textView.selectedRange() == NSRange(location: 4, length: 0))
  textView.deleteBackward(nil)
  #expect(textView.string == "•  item")
  #expect(textView.selectedRange() == NSRange(location: 3, length: 0))
}

@Test @MainActor func forwardDeleteRemovesOneInsertedBulletTab() {
  let (textView, _) = bulletEditor("• item")
  textView.setSelectedRange(NSRange(location: 2, length: 0))
  textView.insertTab(nil)
  #expect(textView.string == "• \titem")

  textView.setSelectedRange(NSRange(location: 2, length: 0))
  textView.deleteForward(nil)

  #expect(textView.string == "• item")
  #expect(textView.selectedRange() == NSRange(location: 2, length: 0))
}

@Test("Depth-zero bullet Tab chooses the 36-point app default for default tab settings")
@MainActor func bulletTabUsesThreeSpaceIntervalAndAlignsToNextStop() throws {
  let font = NSFont.systemFont(ofSize: 14)
  let defaultParagraph = EditorTypography.defaultParagraphStyle(fontSize: font.pointSize)
  let (textView, _) = bulletEditor("• X\n• Y")
  let original = NSAttributedString(
    string: textView.string,
    attributes: [.font: font, .paragraphStyle: defaultParagraph]
  )
  textView.textStorage?.setAttributedString(original)
  textView.setSelectedRange(NSRange(location: 2, length: 0))

  textView.insertTab(nil)

  #expect(textView.string == "• \tX\n• Y")
  #expect(textView.selectedRange() == NSRange(location: 3, length: 0))
  let storage = try #require(textView.textStorage)
  let insertedStyle = try #require(
    storage.attribute(.paragraphStyle, at: 2, effectiveRange: nil) as? NSParagraphStyle
  )
  let untouchedStyle = try #require(
    storage.attribute(.paragraphStyle, at: 5, effectiveRange: nil) as? NSParagraphStyle
  )
  let expectedInterval: CGFloat = 36
  #expect(abs(insertedStyle.defaultTabInterval - expectedInterval) < 0.01)
  #expect(insertedStyle.tabStops.isEmpty)
  #expect(insertedStyle.minimumLineHeight == defaultParagraph.minimumLineHeight)
  #expect(insertedStyle.maximumLineHeight == defaultParagraph.maximumLineHeight)
  #expect(untouchedStyle.defaultTabInterval == defaultParagraph.defaultTabInterval)

  let layoutManager = try #require(textView.layoutManager)
  let textContainer = try #require(textView.textContainer)
  layoutManager.ensureLayout(for: textContainer)
  let bulletGlyphs = layoutManager.glyphRange(
    forCharacterRange: NSRange(location: 0, length: 1),
    actualCharacterRange: nil
  )
  let followingTextGlyphs = layoutManager.glyphRange(
    forCharacterRange: NSRange(location: 3, length: 1),
    actualCharacterRange: nil
  )
  let bulletOrigin = layoutManager.location(forGlyphAt: bulletGlyphs.location).x
  let followingTextOrigin = layoutManager.location(forGlyphAt: followingTextGlyphs.location).x
  let tabAdvance = followingTextOrigin - bulletOrigin
  let prefixWidth = ("• " as NSString).size(withAttributes: [.font: font]).width
  let nextStopIndex = (prefixWidth / expectedInterval).rounded(.down) + 1
  let expectedNextStop = nextStopIndex * expectedInterval
  #expect(abs(tabAdvance - expectedNextStop) < 0.5)
}

@Test @MainActor func bulletTabAlignsNarrowAndWideGlyphsToTheNextStopAcrossPositions() throws {
  let fonts: [(name: String, font: NSFont)] = [
    ("system-12", .systemFont(ofSize: 12)),
    ("system-20", .systemFont(ofSize: 20)),
    ("monospaced-14", .monospacedSystemFont(ofSize: 14, weight: .regular)),
    ("monospaced-20", .monospacedSystemFont(ofSize: 20, weight: .regular)),
  ]
  let (textView, _) = bulletEditor("• \n")
  let layoutManager = try #require(textView.layoutManager)
  let textContainer = try #require(textView.textContainer)

  for fontCase in fonts {
    for content in ["i", "W", "iW", "Wi"] {
      for offset in 0...content.count {
        let original = "• \(content)\n"
        let paragraphStyle = EditorTypography.defaultParagraphStyle(fontSize: fontCase.font.pointSize)
        textView.undoManager?.removeAllActions()
        textView.textStorage?.setAttributedString(
          NSAttributedString(
            string: original,
            attributes: [.font: fontCase.font, .paragraphStyle: paragraphStyle]
          )
        )
        let caretLocation = 2 + offset
        textView.setSelectedRange(NSRange(location: caretLocation, length: 0))

        layoutManager.ensureLayout(for: textContainer)
        let bulletGlyphs = layoutManager.glyphRange(
          forCharacterRange: NSRange(location: 0, length: 1),
          actualCharacterRange: nil
        )
        let insertionGlyph = layoutManager.glyphIndexForCharacter(at: caretLocation)
        let paragraphLineX = layoutManager.lineFragmentRect(
          forGlyphAt: bulletGlyphs.location,
          effectiveRange: nil
        ).minX
        let paragraphOriginX = layoutManager.location(forGlyphAt: bulletGlyphs.location).x
        let caretBeforeTabX = layoutManager.location(forGlyphAt: insertionGlyph).x
        let caretBeforeTabContainerX = paragraphLineX + caretBeforeTabX
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: fontCase.font]).width
        let interval: CGFloat = 36
        let nextStopIndex = ((caretBeforeTabX - paragraphOriginX) / interval).rounded(.down) + 1
        let expectedCaretAfterTabX = paragraphOriginX + nextStopIndex * interval

        textView.insertTab(nil)

        let prefix = String(content.prefix(offset))
        let suffix = String(content.dropFirst(offset))
        let description = "\(fontCase.name), \(content), offset \(offset)"
        #expect(textView.string == "• \(prefix)\t\(suffix)\n", Testing.Comment(rawValue: description))
        #expect(textView.selectedRange() == NSRange(location: caretLocation + 1, length: 0))
        layoutManager.ensureLayout(for: textContainer)
        let followingGlyphs = layoutManager.glyphRange(
          forCharacterRange: NSRange(location: caretLocation + 1, length: 1),
          actualCharacterRange: nil
        )
        let caretAfterTabX = layoutManager.location(forGlyphAt: followingGlyphs.location).x
        let caretAfterTabContainerX = layoutManager.lineFragmentRect(
          forGlyphAt: followingGlyphs.location,
          effectiveRange: nil
        ).minX + caretAfterTabX
        print(
          "TAB_GEOMETRY font=\(fontCase.name) size=\(fontCase.font.pointSize) "
            + "content=\(content) offset=\(offset) beforeX=\(caretBeforeTabContainerX) "
            + "afterX=\(caretAfterTabContainerX) space=\(spaceWidth) interval=\(interval) "
            + "nextStopIndex=\(nextStopIndex) nextStopX=\(paragraphLineX + expectedCaretAfterTabX)"
        )
        #expect(caretAfterTabX > caretBeforeTabX, Testing.Comment(rawValue: description))
        #expect(abs(caretAfterTabX - expectedCaretAfterTabX) < 0.5, Testing.Comment(rawValue: description))
        let insertedStyle = try #require(
          textView.textStorage?.attribute(.paragraphStyle, at: caretLocation, effectiveRange: nil)
            as? NSParagraphStyle
        )
        #expect(abs(insertedStyle.defaultTabInterval - interval) < 0.01, Testing.Comment(rawValue: description))
        #expect(insertedStyle.tabStops.isEmpty, Testing.Comment(rawValue: description))
      }
    }
  }
}

@Test @MainActor func customBulletTabStopsAndParagraphMetricsArePreserved() throws {
  let font = NSFont.systemFont(ofSize: 14)
  let paragraph = NSMutableParagraphStyle()
  paragraph.defaultTabInterval = 51
  paragraph.tabStops = [NSTextTab(textAlignment: .right, location: 72, options: [:])]
  paragraph.firstLineHeadIndent = 4
  paragraph.headIndent = 12
  paragraph.tailIndent = -10
  paragraph.lineSpacing = 3
  paragraph.paragraphSpacing = 6
  paragraph.minimumLineHeight = 22
  paragraph.maximumLineHeight = 22
  let (textView, _) = bulletEditor("• item")
  textView.textStorage?.setAttributedString(
    NSAttributedString(string: textView.string, attributes: [.font: font, .paragraphStyle: paragraph])
  )
  textView.setSelectedRange(NSRange(location: 2, length: 0))

  textView.insertTab(nil)

  #expect(textView.string == "• \titem")
  let storage = try #require(textView.textStorage)
  let insertedStyle = try #require(
    storage.attribute(.paragraphStyle, at: 2, effectiveRange: nil) as? NSParagraphStyle
  )
  #expect(insertedStyle.defaultTabInterval == paragraph.defaultTabInterval)
  #expect(insertedStyle.tabStops.map(\.location) == [72])
  #expect(insertedStyle.tabStops.map(\.alignment) == [.right])
  #expect(insertedStyle.firstLineHeadIndent == paragraph.firstLineHeadIndent)
  #expect(insertedStyle.headIndent == paragraph.headIndent)
  #expect(insertedStyle.tailIndent == paragraph.tailIndent)
  #expect(insertedStyle.lineSpacing == paragraph.lineSpacing)
  #expect(insertedStyle.paragraphSpacing == paragraph.paragraphSpacing)
  #expect(insertedStyle.minimumLineHeight == paragraph.minimumLineHeight)
  #expect(insertedStyle.maximumLineHeight == paragraph.maximumLineHeight)
  #expect(storage.attribute(.font, at: 3, effectiveRange: nil) as? NSFont == font)
}

@Test @MainActor func bulletTabInsertionAndDeletionUndoRedoRestoreCharacterAndParagraphStyle() throws {
  let font = NSFont.systemFont(ofSize: 14)
  let paragraph = EditorTypography.defaultParagraphStyle(fontSize: font.pointSize)
  let (textView, _) = bulletEditor("• item")
  textView.textStorage?.setAttributedString(
    NSAttributedString(string: textView.string, attributes: [.font: font, .paragraphStyle: paragraph])
  )
  textView.setSelectedRange(NSRange(location: 2, length: 0))

  textView.insertTab(nil)

  #expect(textView.string == "• \titem")
  #expect(textView.selectedRange() == NSRange(location: 3, length: 0))
  let undoManager = try #require(textView.undoManager)
  let insertedStyle = try #require(
    textView.textStorage?.attribute(.paragraphStyle, at: 2, effectiveRange: nil) as? NSParagraphStyle
  )
  let interval = insertedStyle.defaultTabInterval
  #expect(undoManager.canUndo)
  undoManager.undo()
  #expect(textView.string == "• item")
  #expect(textView.selectedRange() == NSRange(location: 2, length: 0))
  #expect(
    textView.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
      == paragraph
  )
  #expect(undoManager.canRedo)
  undoManager.redo()
  #expect(textView.string == "• \titem")
  #expect(textView.selectedRange() == NSRange(location: 3, length: 0))
  let redoneStyle = try #require(
    textView.textStorage?.attribute(.paragraphStyle, at: 2, effectiveRange: nil) as? NSParagraphStyle
  )
  #expect(redoneStyle.defaultTabInterval == interval)

  undoManager.removeAllActions()
  textView.setSelectedRange(NSRange(location: 3, length: 0))
  textView.deleteBackward(nil)
  #expect(textView.string == "• item")
  #expect(textView.selectedRange() == NSRange(location: 2, length: 0))
  undoManager.undo()
  #expect(textView.string == "• \titem")
  #expect(textView.selectedRange() == NSRange(location: 3, length: 0))
  let restoredStyle = try #require(
    textView.textStorage?.attribute(.paragraphStyle, at: 2, effectiveRange: nil) as? NSParagraphStyle
  )
  #expect(restoredStyle.defaultTabInterval == interval)
  undoManager.redo()
  #expect(textView.string == "• item")
  #expect(textView.selectedRange() == NSRange(location: 2, length: 0))
}

@Test @MainActor func bulletTabSurvivesPlainAndRichClipboardRoundTrips() throws {
  let font = NSFont.systemFont(ofSize: 14)
  let paragraph = EditorTypography.defaultParagraphStyle(fontSize: font.pointSize)
  let (source, sourceWindow) = bulletEditor("• item")
  source.textStorage?.setAttributedString(
    NSAttributedString(string: source.string, attributes: [.font: font, .paragraphStyle: paragraph])
  )
  #expect(sourceWindow.makeFirstResponder(source))
  source.setSelectedRange(NSRange(location: 2, length: 0))
  source.insertTab(nil)
  #expect(source.string == "• \titem")
  let sourceStyle = try #require(
    source.textStorage?.attribute(.paragraphStyle, at: 2, effectiveRange: nil) as? NSParagraphStyle
  )

  source.setSelectedRange(NSRange(location: 2, length: 1))
  let plainPasteboard = NSPasteboard.withUniqueName()
  defer { plainPasteboard.releaseGlobally() }
  #expect(source.writeSelection(to: plainPasteboard, types: source.writablePasteboardTypes))
  #expect(source.selectedRange() == NSRange(location: 2, length: 1))
  let plainText = try #require(plainPasteboard.string(forType: .string))
  #expect(plainText == "\t")
  let plainPaste = bulletEditor("• ").0
  plainPaste.setSelectedRange(NSRange(location: 2, length: 0))
  plainPaste.insertPastedTextForTesting(
    NSAttributedString(string: plainText),
    plainText: plainText,
    hasRichFormatting: false
  )
  #expect(plainPaste.string == "• \t")
  plainPaste.deleteBackward(nil)
  #expect(plainPaste.string == "• ")

  let richPasteboard = NSPasteboard.withUniqueName()
  defer { richPasteboard.releaseGlobally() }
  #expect(source.writeSelection(to: richPasteboard, types: source.writablePasteboardTypes))
  let richData = try #require(richPasteboard.data(forType: .rtf))
  let richText = try NSAttributedString(
    data: richData,
    options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: nil
  )
  #expect(richText.string == "\t")
  let richStyle = try #require(
    richText.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
  )
  let encodedTwips = CGFloat(try rtfDefaultTabIntervalTwips(in: richData))
  #expect(abs(sourceStyle.defaultTabInterval * 20 - encodedTwips) <= 1)
  #expect(richStyle.defaultTabInterval == encodedTwips / 20)
  let richPaste = bulletEditor("• ").0
  richPaste.setSelectedRange(NSRange(location: 2, length: 0))
  richPaste.insertPastedTextForTesting(richText, plainText: richText.string)
  #expect(richPaste.string == "• \t")
  #expect(richPaste.textStorage?.attribute(.paragraphStyle, at: 2, effectiveRange: nil) == nil)
  richPaste.deleteBackward(nil)
  #expect(richPaste.string == "• ")
}

@Test @MainActor func wholeParagraphRichPastePreservesNativeTabFormatting() throws {
  let font = try #require(NSFont(name: "Helvetica", size: 14))
  #expect(font.pointSize == 14)
  let paragraph = EditorTypography.defaultParagraphStyle(fontSize: font.pointSize)
  let (source, sourceWindow) = bulletEditor("• item")
  source.textStorage?.setAttributedString(
    NSAttributedString(string: source.string, attributes: [.font: font, .paragraphStyle: paragraph])
  )
  #expect(sourceWindow.makeFirstResponder(source))
  source.setSelectedRange(NSRange(location: 2, length: 0))
  source.typingAttributes = try #require(
    source.textStorage?.attributes(at: 2, effectiveRange: nil)
  )
  source.insertTab(nil)
  #expect(source.string == "• \titem")
  let sourceTabFont = try #require(
    source.textStorage?.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
  )
  let sourceBodyFont = try #require(
    source.textStorage?.attribute(.font, at: 3, effectiveRange: nil) as? NSFont
  )
  expectSamePublicFont(sourceTabFont, as: font)
  expectSamePublicFont(sourceBodyFont, as: font)

  source.setSelectedRange(NSRange(location: 0, length: source.string.utf16.count))
  let pasteboard = NSPasteboard.withUniqueName()
  defer { pasteboard.releaseGlobally() }
  #expect(source.writeSelection(to: pasteboard, types: source.writablePasteboardTypes))
  let richData = try #require(pasteboard.data(forType: .rtf))
  let richText = try NSAttributedString(
    data: richData,
    options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: nil
  )
  #expect(richText.string == source.string)
  let richStyle = try #require(
    richText.attribute(.paragraphStyle, at: 2, effectiveRange: nil) as? NSParagraphStyle
  )
  let decodedTabFont = try #require(
    richText.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
  )
  let decodedBodyFont = try #require(
    richText.attribute(.font, at: 3, effectiveRange: nil) as? NSFont
  )
  expectSamePublicFont(decodedTabFont, as: sourceTabFont)
  expectSamePublicFont(decodedBodyFont, as: sourceBodyFont)
  let encodedTwips = CGFloat(try rtfDefaultTabIntervalTwips(in: richData))
  #expect(abs(36 * 20 - encodedTwips) <= 1)
  #expect(richStyle.defaultTabInterval == encodedTwips / 20)

  let richPaste = bulletEditor("").0
  richPaste.insertPastedTextForTesting(richText, plainText: richText.string)
  #expect(richPaste.string == source.string)
  let pastedStyle = try #require(
    richPaste.textStorage?.attribute(.paragraphStyle, at: 2, effectiveRange: nil) as? NSParagraphStyle
  )
  #expect(pastedStyle.defaultTabInterval == richStyle.defaultTabInterval)
  let pastedTabFont = try #require(
    richPaste.textStorage?.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
  )
  let pastedBodyFont = try #require(
    richPaste.textStorage?.attribute(.font, at: 3, effectiveRange: nil) as? NSFont
  )
  expectSamePublicFont(pastedTabFont, as: decodedTabFont)
  expectSamePublicFont(pastedBodyFont, as: decodedBodyFont)
  richPaste.setSelectedRange(NSRange(location: 3, length: 0))
  richPaste.deleteBackward(nil)
  #expect(richPaste.string == "• item")
}

@Test @MainActor func bulletTabSurvivesNoteRTFRoundTrip() throws {
  let font = NSFont.systemFont(ofSize: 14)
  let paragraph = EditorTypography.defaultParagraphStyle(fontSize: font.pointSize)
  let (textView, _) = bulletEditor("• item")
  textView.textStorage?.setAttributedString(
    NSAttributedString(string: textView.string, attributes: [.font: font, .paragraphStyle: paragraph])
  )
  textView.setSelectedRange(NSRange(location: 2, length: 0))
  textView.insertTab(nil)
  #expect(textView.string == "• \titem")

  let snapshot = textView.attributedString()
  let rtf = try snapshot.data(
    from: NSRange(location: 0, length: snapshot.length),
    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
  )
  let restored = try NSAttributedString(
    data: rtf,
    options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: nil
  )

  #expect(restored.string == "• \titem")
  let restoredStyle = try #require(
    restored.attribute(.paragraphStyle, at: 2, effectiveRange: nil) as? NSParagraphStyle
  )
  let encodedTwips = CGFloat(try rtfDefaultTabIntervalTwips(in: rtf))
  #expect(abs(36 * 20 - encodedTwips) <= 1)
  #expect(restoredStyle.defaultTabInterval == encodedTwips / 20)
  let reopened = bulletEditor(restored.string).0
  reopened.textStorage?.setAttributedString(restored)
  reopened.setSelectedRange(NSRange(location: 3, length: 0))
  reopened.deleteBackward(nil)
  #expect(reopened.string == "• item")
}

@Test @MainActor func collapsedTabOnAnEmptyBulletCreatesASubBullet() {
  let (textView, _) = bulletEditor("• ")
  textView.setSelectedRange(NSRange(location: 2, length: 0))

  textView.insertTab(nil)

  #expect(textView.string == "    ◦ ")
}

@Test @MainActor func collapsedCaretProposalsCannotEnterBulletPrefixes() {
  let cases: [(text: String, prefixLength: Int)] = [
    ("• item", 2),
    ("    ◦ nested", 6),
    ("▪ square", 2),
  ]

  for item in cases {
    let (textView, _) = bulletEditor(item.text)
    for location in 0..<item.prefixLength {
      let range = textView.selectionRange(
        forProposedRange: NSRange(location: location, length: 0),
        granularity: .selectByCharacter
      )
      #expect(range == NSRange(location: item.prefixLength, length: 0))
      textView.setSelectedRange(NSRange(location: location, length: 0))
      #expect(textView.selectedRange() == NSRange(location: item.prefixLength, length: 0))
    }
    let selectedPrefix = textView.selectionRange(
      forProposedRange: NSRange(location: 0, length: item.prefixLength),
      granularity: .selectByCharacter
    )
    #expect(selectedPrefix == NSRange(location: 0, length: item.prefixLength))
    textView.setSelectedRange(NSRange(location: 0, length: item.prefixLength))
    #expect(textView.selectedRange() == NSRange(location: 0, length: item.prefixLength))
    let selectedLine = textView.selectionRange(
      forProposedRange: NSRange(location: 0, length: item.text.utf16.count),
      granularity: .selectByCharacter
    )
    #expect(selectedLine == NSRange(location: 0, length: item.text.utf16.count))
    textView.setSelectedRange(NSRange(location: 0, length: item.text.utf16.count))
    #expect(textView.selectedRange() == NSRange(location: 0, length: item.text.utf16.count))
  }
}

@Test @MainActor func keyboardNavigationCannotMoveCaretIntoBulletPrefixes() {
  for (text, contentStart) in [("• item", 2), ("    ◦ nested", 6)] {
    let (textView, _) = bulletEditor(text)
    textView.setSelectedRange(NSRange(location: contentStart, length: 0))

    textView.moveLeft(nil)
    #expect(textView.selectedRange() == NSRange(location: contentStart, length: 0))

    textView.moveRight(nil)
    #expect(textView.selectedRange() == NSRange(location: contentStart + 1, length: 0))
  }
}

@MainActor
private final class BulletIntegrationChangeObserver: NSObject {
  private(set) var selectionChanges = 0
  private(set) var textChanges = 0

  @objc func selectionDidChange(_ notification: Notification) {
    selectionChanges += 1
  }

  @objc func textDidChange(_ notification: Notification) {
    textChanges += 1
  }
}

@MainActor
private final class ManagedBulletImageFixture {
  let root: URL
  let store: InlineNoteImageStore

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("FleckBulletImage-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    store = InlineNoteImageStore(
      rootURL: root.appendingPathComponent("managed", isDirectory: true)
    )
  }

  func remove() {
    try? FileManager.default.removeItem(at: root)
  }

  func makeReference() throws -> String {
    let bitmap = try #require(NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: 2,
      pixelsHigh: 2,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ))
    bitmap.setColor(.systemRed, atX: 0, y: 0)
    let imageURL = root.appendingPathComponent("synthetic.png")
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: imageURL)
    return try store.importImage(at: imageURL).reference
  }
}

@Test @MainActor func f63PortCollapsedTabInsertsNativeTabsInsideBulletContent() {
  let cases: [(text: String, location: Int, expected: String)] = [
    ("• bullet", 2, "• \tbullet"),
    ("• bullet", 5, "• bul\tlet"),
    ("• bullet", 8, "• bullet\t"),
    ("    ◦ nested", 6, "    ◦ \tnested"),
  ]

  for item in cases {
    let (textView, _) = bulletEditor(item.text)
    textView.setSelectedRange(NSRange(location: item.location, length: 0))
    textView.insertTab(nil)
    #expect(textView.string == item.expected)
    #expect(textView.selectedRange() == NSRange(location: item.location + 1, length: 0))
  }
}

@Test @MainActor func f63PortOneBulletTabIsOneBackspaceAndUndoUnit() throws {
  let original = "• bullet"
  let (textView, _) = bulletEditor(original)
  textView.setSelectedRange(NSRange(location: 2, length: 0))
  textView.insertTab(nil)

  #expect(textView.string == "• \tbullet")
  #expect(textView.selectedRange() == NSRange(location: 3, length: 0))
  textView.moveLeft(nil)
  #expect(textView.selectedRange() == NSRange(location: 2, length: 0))
  textView.moveRight(nil)
  #expect(textView.selectedRange() == NSRange(location: 3, length: 0))

  let undoManager = try #require(textView.undoManager)
  undoManager.undo()
  #expect(textView.string == original)
  undoManager.redo()
  #expect(textView.string == "• \tbullet")
  textView.deleteBackward(nil)
  #expect(textView.string == original)
}

@Test("Depth-zero default-tab policy preserves paragraph metrics and explicit custom stops")
@MainActor func f63PortBulletTabPreservesMetricsAndUsesThreeSpaceDefault() throws {
  let font = NSFont.systemFont(ofSize: 14)
  let defaultParagraph = EditorTypography.defaultParagraphStyle(fontSize: font.pointSize)
  let (textView, _) = bulletEditor("• X\n• Y")
  textView.textStorage?.setAttributedString(
    NSAttributedString(string: textView.string, attributes: [.font: font, .paragraphStyle: defaultParagraph])
  )
  textView.setSelectedRange(NSRange(location: 2, length: 0))
  textView.insertTab(nil)

  #expect(textView.string == "• \tX\n• Y")
  let storage = try #require(textView.textStorage)
  let insertedStyle = try #require(
    storage.attribute(.paragraphStyle, at: 2, effectiveRange: nil) as? NSParagraphStyle
  )
  let untouchedStyle = try #require(
    storage.attribute(.paragraphStyle, at: 5, effectiveRange: nil) as? NSParagraphStyle
  )
  #expect(insertedStyle.defaultTabInterval == 36)
  #expect(insertedStyle.tabStops.isEmpty)
  #expect(insertedStyle.minimumLineHeight == defaultParagraph.minimumLineHeight)
  #expect(insertedStyle.maximumLineHeight == defaultParagraph.maximumLineHeight)
  #expect(untouchedStyle.defaultTabInterval == defaultParagraph.defaultTabInterval)

  let customParagraph = NSMutableParagraphStyle()
  customParagraph.defaultTabInterval = 51
  customParagraph.tabStops = [NSTextTab(textAlignment: .right, location: 72, options: [:])]
  customParagraph.headIndent = 12
  let (custom, _) = bulletEditor("• item")
  custom.textStorage?.setAttributedString(
    NSAttributedString(string: custom.string, attributes: [.font: font, .paragraphStyle: customParagraph])
  )
  custom.setSelectedRange(NSRange(location: 2, length: 0))
  custom.insertTab(nil)

  let preserved = try #require(
    custom.textStorage?.attribute(.paragraphStyle, at: 2, effectiveRange: nil) as? NSParagraphStyle
  )
  #expect(preserved.defaultTabInterval == customParagraph.defaultTabInterval)
  #expect(preserved.tabStops.map(\.location) == [72])
  #expect(preserved.tabStops.map(\.alignment) == [.right])
  #expect(preserved.headIndent == customParagraph.headIndent)
  #expect(custom.textStorage?.attribute(.font, at: 3, effectiveRange: nil) as? NSFont == font)
}

@Test @MainActor func f63PortBulletTabRTFRoundTripPreservesParagraphStyle() throws {
  let font = NSFont.systemFont(ofSize: 14)
  let paragraph = EditorTypography.defaultParagraphStyle(fontSize: font.pointSize)
  let (source, _) = bulletEditor("• item")
  source.textStorage?.setAttributedString(
    NSAttributedString(string: source.string, attributes: [.font: font, .paragraphStyle: paragraph])
  )
  source.setSelectedRange(NSRange(location: 2, length: 0))
  source.insertTab(nil)
  source.setSelectedRange(NSRange(location: 0, length: source.string.utf16.count))
  let pasteboard = NSPasteboard.withUniqueName()
  defer { pasteboard.releaseGlobally() }

  #expect(source.writeSelection(to: pasteboard, types: source.writablePasteboardTypes))
  let richData = try #require(pasteboard.data(forType: .rtf))
  let richText = try NSAttributedString(
    data: richData,
    options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: nil
  )
  #expect(richText.string == "• \titem")
  let sourceStyle = try #require(
    source.textStorage?.attribute(.paragraphStyle, at: 2, effectiveRange: nil) as? NSParagraphStyle
  )
  let richStyle = try #require(
    richText.attribute(.paragraphStyle, at: 2, effectiveRange: nil) as? NSParagraphStyle
  )
  let encodedTwips = CGFloat(try rtfDefaultTabIntervalTwips(in: richData))
  #expect(abs(sourceStyle.defaultTabInterval * 20 - encodedTwips) <= 1)
  #expect(richStyle.defaultTabInterval == encodedTwips / 20)

  let pasted = bulletEditor("").0
  pasted.insertPastedTextForTesting(richText, plainText: richText.string)
  #expect(pasted.string == source.string)
  let pastedStyle = try #require(
    pasted.textStorage?.attribute(.paragraphStyle, at: 2, effectiveRange: nil) as? NSParagraphStyle
  )
  #expect(pastedStyle.defaultTabInterval == richStyle.defaultTabInterval)
}

@Test @MainActor func f63PortWholeItemClipboardPreservesMarkersAndSubstringDoesNot() throws {
  let (source, sourceWindow) = bulletEditor("• note")
  #expect(sourceWindow.makeFirstResponder(source))
  source.setSelectedRange(NSRange(location: 2, length: 4))
  let pasteboard = NSPasteboard.withUniqueName()
  defer { pasteboard.releaseGlobally() }

  #expect(source.writeSelection(to: pasteboard, types: source.writablePasteboardTypes))
  #expect(source.selectedRange() == NSRange(location: 2, length: 4))
  #expect(pasteboard.string(forType: .string) == "• note")

  source.setSelectedRange(NSRange(location: 3, length: 2))
  let substringPasteboard = NSPasteboard.withUniqueName()
  defer { substringPasteboard.releaseGlobally() }
  #expect(source.writeSelection(to: substringPasteboard, types: source.writablePasteboardTypes))
  #expect(substringPasteboard.string(forType: .string) == "ot")
}

@Test @MainActor func f63PortMultiSelectionClipboardPreservesWholeItemsAndSourceSelection() throws {
  let (source, sourceWindow) = bulletEditor("• first\n• second\n• third")
  #expect(sourceWindow.makeFirstResponder(source))
  let selections = [NSRange(location: 2, length: 5), NSRange(location: 10, length: 6)]
  source.textStorage?.addAttribute(
    .foregroundColor,
    value: NSColor.systemRed,
    range: NSRange(location: 0, length: 2)
  )
  source.textStorage?.addAttribute(.font, value: NSFont.systemFont(ofSize: 25), range: selections[0])
  source.textStorage?.addAttribute(
    .foregroundColor,
    value: NSColor.systemGreen,
    range: NSRange(location: 8, length: 2)
  )
  source.textStorage?.addAttribute(.font, value: NSFont.systemFont(ofSize: 17), range: selections[1])
  source.setSelectedRanges(
    selections.map { NSValue(range: $0) },
    affinity: .downstream,
    stillSelecting: false
  )
  let initialStorage = NSAttributedString(attributedString: try #require(source.textStorage))
  let selectionAffinity = source.selectionAffinity
  let observer = BulletIntegrationChangeObserver()
  NotificationCenter.default.addObserver(
    observer,
    selector: #selector(BulletIntegrationChangeObserver.selectionDidChange(_:)),
    name: NSTextView.didChangeSelectionNotification,
    object: source
  )
  NotificationCenter.default.addObserver(
    observer,
    selector: #selector(BulletIntegrationChangeObserver.textDidChange(_:)),
    name: NSText.didChangeNotification,
    object: source
  )
  defer { NotificationCenter.default.removeObserver(observer) }
  let pasteboard = NSPasteboard.withUniqueName()
  defer { pasteboard.releaseGlobally() }

  #expect(source.writeSelection(to: pasteboard, types: source.writablePasteboardTypes))
  let copiedText = try #require(pasteboard.string(forType: .string))
  #expect(copiedText.contains("• first"))
  #expect(copiedText.contains("• second"))
  #expect(!copiedText.contains("third"))
  #expect(source.selectedRanges.map(\.rangeValue) == selections)
  #expect(source.selectionAffinity == selectionAffinity)
  #expect(source.textStorage?.isEqual(to: initialStorage) == true)
  #expect(observer.selectionChanges == 0)
  #expect(observer.textChanges == 0)

  let richText = try NSAttributedString(
    data: #require(pasteboard.data(forType: .rtf)),
    options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: nil
  )
  let firstBody = (richText.string as NSString).range(of: "first").location
  let secondBody = (richText.string as NSString).range(of: "second").location
  let secondMarker = (richText.string as NSString).range(of: "• second").location
  #expect(firstBody != NSNotFound)
  #expect(secondBody != NSNotFound)
  #expect(secondMarker != NSNotFound)
  if firstBody != NSNotFound {
    #expect(
      richText.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .systemRed
    )
    #expect(
      (richText.attribute(.font, at: firstBody, effectiveRange: nil) as? NSFont)?.pointSize == 25
    )
  }
  if secondBody != NSNotFound, secondMarker != NSNotFound {
    #expect(
      richText.attribute(.foregroundColor, at: secondMarker, effectiveRange: nil) as? NSColor
        == .systemGreen
    )
    #expect(
      (richText.attribute(.font, at: secondBody, effectiveRange: nil) as? NSFont)?.pointSize == 17
    )
  }
}

@Test @MainActor func f63PortTabAfterManagedImageClearsAttachmentAttributes() throws {
  let fixture = try ManagedBulletImageFixture()
  defer { fixture.remove() }
  let reference = try fixture.makeReference()
  let display = fixture.store.projectedContent(
    from: NSAttributedString(string: "• \(reference) tail")
  )
  let (textView, _) = bulletEditor(display.string)
  textView.inlineImageStore = fixture.store
  textView.textStorage?.setAttributedString(display)
  let imageLocation = (display.string as NSString).range(of: "\u{fffc}").location
  let attachment = try #require(
    textView.textStorage?.attribute(.attachment, at: imageLocation, effectiveRange: nil)
      as? InlineNoteImageAttachment
  )
  let font = try #require(
    textView.textStorage?.attribute(.font, at: imageLocation, effectiveRange: nil) as? NSFont
  )
  textView.setSelectedRange(NSRange(location: imageLocation + 1, length: 0))
  textView.typingAttributes = [.attachment: attachment, .font: font]

  textView.insertTab(nil)

  #expect(textView.string == "• \u{fffc}\t tail")
  #expect(
    textView.textStorage?.attribute(.attachment, at: imageLocation, effectiveRange: nil)
      is InlineNoteImageAttachment
  )
  #expect(
    textView.textStorage?.attribute(.attachment, at: imageLocation + 1, effectiveRange: nil) == nil
  )
  #expect(
    InlineNoteImageProjection.expanded(try #require(textView.textStorage)).string
      == "• \(reference)\t tail"
  )
}
