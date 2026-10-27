import AppKit
import Testing

@testable import FleckApp

@Test @MainActor func completedChecklistTextInsertionStrikesOnlyFirstParagraph() throws {
  let frame = NSRect(x: 0, y: 0, width: 320, height: 160)
  let textView = ListAwareTextView(frame: frame)
  let window = NSWindow(
    contentRect: frame,
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = textView
  defer { window.contentView = nil }
  textView.allowsUndo = true
  textView.reduceMotion = true
  textView.string = "○ Task"
  #expect(window.makeFirstResponder(textView))
  textView.setSelectedRange(NSRange(location: 2, length: 0))
  #expect(textView.toggleSelectedChecklist())

  let insertionLocation = textView.string.utf16.count
  textView.setSelectedRange(NSRange(location: insertionLocation, length: 0))
  let storage = try #require(textView.textStorage)
  textView.typingAttributes = storage.attributes(
    at: insertionLocation - 1,
    effectiveRange: nil
  )
  #expect(
    textView.typingAttributes[.strikethroughStyle] as? Int
      == NSUnderlineStyle.single.rawValue
  )

  textView.insertText(
    " done\nplain",
    replacementRange: NSRange(location: insertionLocation, length: 0)
  )

  #expect(textView.string == "● Task done\nplain")
  #expect(
    storage.attribute(.strikethroughStyle, at: insertionLocation, effectiveRange: nil) as? Int
      == NSUnderlineStyle.single.rawValue
  )
  let plainContinuationLocation = ("● Task done\n" as NSString).length
  #expect(
    storage.attribute(.strikethroughStyle, at: plainContinuationLocation, effectiveRange: nil) == nil
  )
}

@Test @MainActor func richChecklistPastePreservesContinuationStrikeAndUndoGrouping() throws {
  let frame = NSRect(x: 0, y: 0, width: 320, height: 160)
  let textView = ListAwareTextView(frame: frame)
  let window = NSWindow(
    contentRect: frame,
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = textView
  defer { window.contentView = nil }
  textView.allowsUndo = true
  textView.reduceMotion = true
  let destinationFont = NSFont.systemFont(ofSize: 18)
  textView.textStorage?.setAttributedString(
    NSAttributedString(string: "○ Task", attributes: [.font: destinationFont])
  )
  #expect(window.makeFirstResponder(textView))
  textView.setSelectedRange(NSRange(location: 2, length: 0))
  #expect(textView.toggleSelectedChecklist())
  let originalCompletedText = textView.attributedString()
  let originalGroupsByEvent = try #require(textView.undoManager).groupsByEvent
  let undoManager = try #require(textView.undoManager)
  undoManager.groupsByEvent = false
  defer { undoManager.groupsByEvent = originalGroupsByEvent }
  undoManager.removeAllActions()

  let pasteString = " pasted\ncontinued"
  let sourceFont = NSFont.systemFont(ofSize: 13)
  let pastedText = NSMutableAttributedString(
    string: pasteString,
    attributes: [.font: sourceFont]
  )
  let continuationRange = (pasteString as NSString).range(of: "continued")
  pastedText.addAttribute(
    .strikethroughStyle,
    value: NSUnderlineStyle.single.rawValue,
    range: continuationRange
  )
  let insertionLocation = textView.string.utf16.count
  textView.setSelectedRange(NSRange(location: insertionLocation, length: 0))
  let storage = try #require(textView.textStorage)
  textView.typingAttributes = storage.attributes(
    at: insertionLocation - 1,
    effectiveRange: nil
  )

  textView.insertPastedTextForTesting(
    pastedText,
    plainText: pasteString,
    hasRichFormatting: true
  )

  #expect(textView.string == "● Task pasted\ncontinued")
  #expect(textView.hasPasteOptions)
  #expect(textView.pasteOptionEnabledStates == [true, true, true])
  #expect(
    storage.attribute(.strikethroughStyle, at: insertionLocation, effectiveRange: nil) as? Int
      == NSUnderlineStyle.single.rawValue
  )
  let pastedContinuationLocation = ("● Task pasted\n" as NSString).length
  #expect(
    storage.attribute(.strikethroughStyle, at: pastedContinuationLocation, effectiveRange: nil)
      as? Int == NSUnderlineStyle.single.rawValue
  )
  #expect(
    (storage.attribute(.font, at: insertionLocation, effectiveRange: nil) as? NSFont)?.pointSize
      == sourceFont.pointSize
  )
  let pastedBeforeOption = textView.attributedString()

  textView.applyPasteOption(.mergeFormatting)

  #expect(!textView.hasPasteOptions)
  #expect(textView.string == "● Task pasted\ncontinued")
  #expect(
    storage.attribute(.strikethroughStyle, at: pastedContinuationLocation, effectiveRange: nil)
      as? Int == NSUnderlineStyle.single.rawValue
  )
  #expect(
    (storage.attribute(.font, at: insertionLocation, effectiveRange: nil) as? NSFont)?.pointSize
      == destinationFont.pointSize
  )
  undoManager.undo()
  #expect(textView.attributedString().isEqual(to: pastedBeforeOption))
  #expect(textView.string == "● Task pasted\ncontinued")
  undoManager.undo()
  #expect(textView.attributedString().isEqual(to: originalCompletedText))
  #expect(!undoManager.canUndo)
}

@Test @MainActor func pasteTextOnlyClearsChecklistContinuationAndUndoRestoresRichStrike() throws {
  let frame = NSRect(x: 0, y: 0, width: 320, height: 160)
  let textView = ListAwareTextView(frame: frame)
  let window = NSWindow(
    contentRect: frame,
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = textView
  defer { window.contentView = nil }
  textView.allowsUndo = true
  textView.reduceMotion = true
  let destinationFont = NSFont.systemFont(ofSize: 18)
  textView.textStorage?.setAttributedString(
    NSAttributedString(string: "○ Task", attributes: [.font: destinationFont])
  )
  #expect(window.makeFirstResponder(textView))
  textView.setSelectedRange(NSRange(location: 2, length: 0))
  #expect(textView.toggleSelectedChecklist())
  let originalCompletedText = textView.attributedString()
  let undoManager = try #require(textView.undoManager)
  let originalGroupsByEvent = undoManager.groupsByEvent
  undoManager.groupsByEvent = false
  defer { undoManager.groupsByEvent = originalGroupsByEvent }
  undoManager.removeAllActions()

  let pasteString = " pasted\ncontinued"
  let sourceFont = NSFont.systemFont(ofSize: 13)
  let pastedText = NSMutableAttributedString(
    string: pasteString,
    attributes: [.font: sourceFont]
  )
  let continuationRange = (pasteString as NSString).range(of: "continued")
  pastedText.addAttribute(
    .strikethroughStyle,
    value: NSUnderlineStyle.single.rawValue,
    range: continuationRange
  )
  let insertionLocation = textView.string.utf16.count
  textView.setSelectedRange(NSRange(location: insertionLocation, length: 0))
  let storage = try #require(textView.textStorage)
  textView.typingAttributes = storage.attributes(
    at: insertionLocation - 1,
    effectiveRange: nil
  )

  textView.insertPastedTextForTesting(
    pastedText,
    plainText: pasteString,
    hasRichFormatting: true
  )

  #expect(textView.string == "● Task pasted\ncontinued")
  #expect(textView.pasteOptionEnabledStates == [true, true, true])
  let pastedContinuationLocation = ("● Task pasted\n" as NSString).length
  #expect(
    storage.attribute(.strikethroughStyle, at: insertionLocation, effectiveRange: nil) as? Int
      == NSUnderlineStyle.single.rawValue
  )
  #expect(
    storage.attribute(.strikethroughStyle, at: pastedContinuationLocation, effectiveRange: nil)
      as? Int == NSUnderlineStyle.single.rawValue
  )
  let pastedBeforeOption = textView.attributedString()

  textView.applyPasteOption(.pasteTextOnly)

  #expect(!textView.hasPasteOptions)
  #expect(textView.string == "● Task pasted\ncontinued")
  #expect(
    storage.attribute(.strikethroughStyle, at: insertionLocation, effectiveRange: nil) as? Int
      == NSUnderlineStyle.single.rawValue
  )
  #expect(
    storage.attribute(.strikethroughStyle, at: pastedContinuationLocation, effectiveRange: nil) == nil
  )
  undoManager.undo()
  #expect(textView.attributedString().isEqual(to: pastedBeforeOption))
  #expect(
    storage.attribute(.strikethroughStyle, at: pastedContinuationLocation, effectiveRange: nil)
      as? Int == NSUnderlineStyle.single.rawValue
  )
  undoManager.undo()
  #expect(textView.attributedString().isEqual(to: originalCompletedText))
  #expect(!undoManager.canUndo)
}

@MainActor
private func narrowChecklistEditor(
  _ text: NSAttributedString,
  width: CGFloat
) -> (ListAwareTextView, NSWindow) {
  let frame = NSRect(x: 0, y: 0, width: width, height: 240)
  let textView = ListAwareTextView(frame: frame)
  let window = NSWindow(
    contentRect: frame,
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = textView
  textView.allowsUndo = true
  textView.textContainerInset = .zero
  textView.textContainer?.lineFragmentPadding = 0
  textView.textStorage?.setAttributedString(text)
  return (textView, window)
}

@MainActor
private func checklistGlyphOrigin(
  at characterIndex: Int,
  layoutManager: NSLayoutManager
) -> (x: CGFloat, line: NSRect) {
  let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)
  let line = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
  return (line.minX + layoutManager.location(forGlyphAt: glyphIndex).x, line)
}

@Test @MainActor func checklistWrapAlignsContinuationWithMeasuredContentOrigin() throws {
  let baseFont = NSFont.systemFont(ofSize: 14)
  let content = "LongSyntheticTokenWithoutBreaks followed by enough words to wrap again"
  let cases: [(name: String, indent: String, marker: String, contentFont: NSFont)] = [
    (
      "top-level mixed-font",
      "",
      "○",
      .monospacedSystemFont(ofSize: 16, weight: .regular)
    ),
    (
      "nested checked",
      "    ",
      "●",
      .systemFont(ofSize: 16)
    ),
  ]

  for item in cases {
    let text = item.indent + item.marker + " " + content
    let markerLocation = (item.indent as NSString).length
    let contentLocation = (item.indent + item.marker + " " as NSString).length
    let contentRange = NSRange(location: contentLocation, length: (content as NSString).length)
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.firstLineHeadIndent = 4
    paragraphStyle.headIndent = 12
    paragraphStyle.tailIndent = -8
    paragraphStyle.lineSpacing = 3
    paragraphStyle.paragraphSpacing = 6
    let attributed = NSMutableAttributedString(
      string: text,
      attributes: [.font: baseFont, .paragraphStyle: paragraphStyle]
    )
    attributed.addAttribute(.font, value: item.contentFont, range: contentRange)
    if item.marker == "●" {
      attributed.addAttribute(
        .strikethroughStyle,
        value: NSUnderlineStyle.single.rawValue,
        range: contentRange
      )
    }

    let structuralIndentWidth = (item.indent as NSString).size(withAttributes: [.font: baseFont]).width
    let continuationWord = "followed"
    let continuationWordWidth = (continuationWord as NSString)
      .size(withAttributes: [.font: item.contentFont]).width
    let width = paragraphStyle.firstLineHeadIndent + structuralIndentWidth + 20
      + continuationWordWidth - paragraphStyle.tailIndent + 1
    let (textView, _) = narrowChecklistEditor(attributed, width: width)
    let layoutManager = try #require(textView.layoutManager)
    let textContainer = try #require(textView.textContainer)
    layoutManager.ensureLayout(for: textContainer)
    let liveParagraphStyle = try #require(
      textView.textStorage?.attribute(.paragraphStyle, at: contentLocation, effectiveRange: nil)
        as? NSParagraphStyle
    )
    #expect(liveParagraphStyle.firstLineHeadIndent == paragraphStyle.firstLineHeadIndent, Testing.Comment(rawValue: item.name))
    #expect(liveParagraphStyle.headIndent == paragraphStyle.headIndent, Testing.Comment(rawValue: item.name))
    #expect(liveParagraphStyle.tailIndent == paragraphStyle.tailIndent, Testing.Comment(rawValue: item.name))
    #expect(liveParagraphStyle.lineSpacing == paragraphStyle.lineSpacing, Testing.Comment(rawValue: item.name))
    #expect(liveParagraphStyle.paragraphSpacing == paragraphStyle.paragraphSpacing, Testing.Comment(rawValue: item.name))

    let marker = checklistGlyphOrigin(at: markerLocation, layoutManager: layoutManager)
    let firstContent = checklistGlyphOrigin(at: contentLocation, layoutManager: layoutManager)
    #expect(abs(marker.line.minY - firstContent.line.minY) < 0.5, Testing.Comment(rawValue: item.name))

    let firstContinuationLocation = try #require(
      (contentLocation + 1..<NSMaxRange(contentRange)).first { location in
        let line = checklistGlyphOrigin(at: location, layoutManager: layoutManager).line
        return abs(line.minY - firstContent.line.minY) > 0.5
      }
    )
    let continuation = checklistGlyphOrigin(
      at: firstContinuationLocation,
      layoutManager: layoutManager
    )
    let nativeReferenceTextView = NSTextView(
      frame: NSRect(x: 0, y: 0, width: width, height: 240)
    )
    nativeReferenceTextView.textContainerInset = .zero
    nativeReferenceTextView.textContainer?.lineFragmentPadding = 0
    nativeReferenceTextView.textStorage?.setAttributedString(attributed)
    let nativeReferenceLayoutManager = try #require(nativeReferenceTextView.layoutManager)
    let nativeReferenceTextContainer = try #require(nativeReferenceTextView.textContainer)
    nativeReferenceLayoutManager.ensureLayout(for: nativeReferenceTextContainer)
    let nativeReferenceGlyph = nativeReferenceLayoutManager.glyphIndexForCharacter(
      at: firstContinuationLocation
    )
    let nativeReferenceLine = nativeReferenceLayoutManager.lineFragmentRect(
      forGlyphAt: nativeReferenceGlyph,
      effectiveRange: nil
    )
    let nativeReferenceTailIndent = (
      nativeReferenceTextView.textStorage?.attribute(
        .paragraphStyle,
        at: firstContinuationLocation,
        effectiveRange: nil
      ) as? NSParagraphStyle
    )?.tailIndent ?? 0
    print(
      "CHECKLIST_NATIVE_REFERENCE case=\(item.name) containerMaxX=\(nativeReferenceTextContainer.size.width) "
        + "padding=\(nativeReferenceTextContainer.lineFragmentPadding) "
        + "tailIndent=\(nativeReferenceTailIndent) lineMaxX=\(nativeReferenceLine.maxX) "
        + "usableRightEdge=\(nativeReferenceTextContainer.size.width + nativeReferenceTailIndent)"
    )
    #expect(abs(firstContent.x - continuation.x) < 0.5, Testing.Comment(rawValue: item.name))

    let firstContentGlyph = layoutManager.glyphIndexForCharacter(at: contentLocation)
    var firstContentLineGlyphRange = NSRange(location: 0, length: 0)
    _ = layoutManager.lineFragmentRect(
      forGlyphAt: firstContentGlyph,
      effectiveRange: &firstContentLineGlyphRange
    )
    let contentGlyphRange = layoutManager.glyphRange(
      forCharacterRange: contentRange,
      actualCharacterRange: nil
    )
    let expectedRightEdge = textContainer.size.width + liveParagraphStyle.tailIndent
    var continuationLineLocations = Set<Int>()
    for glyphIndex in contentGlyphRange.location..<NSMaxRange(contentGlyphRange) {
      var lineGlyphRange = NSRange(location: 0, length: 0)
      let lineRect = layoutManager.lineFragmentRect(
        forGlyphAt: glyphIndex,
        effectiveRange: &lineGlyphRange
      )
      guard lineGlyphRange.location != firstContentLineGlyphRange.location,
        continuationLineLocations.insert(lineGlyphRange.location).inserted
      else {
        continue
      }

      let usedRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
      let continuationGlyphRange = NSIntersectionRange(lineGlyphRange, contentGlyphRange)
      let glyphExtent = layoutManager.boundingRect(
        forGlyphRange: continuationGlyphRange,
        in: textContainer
      )
      if continuationLineLocations.count == 1 {
        print(
          "CHECKLIST_FRAGMENT_EDGE case=\(item.name) containerWidth=\(textContainer.size.width) "
            + "padding=\(textContainer.lineFragmentPadding) tailIndent=\(liveParagraphStyle.tailIndent) "
            + "firstContentX=\(firstContent.x) continuationX=\(continuation.x) "
            + "continuationDelta=\(continuation.x - firstContent.x) "
            + "lineMaxX=\(lineRect.maxX) usedMaxX=\(usedRect.maxX) glyphMaxX=\(glyphExtent.maxX) "
            + "expectedRightEdge=\(expectedRightEdge)"
        )
      }
      #expect(abs(lineRect.maxX - textContainer.size.width) < 0.5, Testing.Comment(rawValue: item.name))
      #expect(usedRect.maxX <= expectedRightEdge + 0.5, Testing.Comment(rawValue: item.name))
      #expect(glyphExtent.maxX <= expectedRightEdge + 0.5, Testing.Comment(rawValue: item.name))
    }
    #expect(continuationLineLocations.count > 0, Testing.Comment(rawValue: item.name))

    let continuationWordRange = (content as NSString).range(of: continuationWord)
    let firstContinuationWordLine = checklistGlyphOrigin(
      at: contentLocation + continuationWordRange.location,
      layoutManager: layoutManager
    ).line
    for offset in 1..<continuationWordRange.length {
      let glyph = checklistGlyphOrigin(
        at: contentLocation + continuationWordRange.location + offset,
        layoutManager: layoutManager
      )
      #expect(abs(firstContinuationWordLine.minY - glyph.line.minY) < 0.5, Testing.Comment(rawValue: item.name))
    }
    #expect(textView.string == text, Testing.Comment(rawValue: item.name))
  }
}

@Test @MainActor func checklistDisplayLayoutPreservesComposedCharactersRTFAndUndo() throws {
  let font = NSFont.systemFont(ofSize: 14)
  let content = "e\u{301}LongSyntheticTokenWithoutBreaks followed by words"
  let text = "    ● " + content
  let contentLocation = ("    ● " as NSString).length
  let contentRange = NSRange(location: contentLocation, length: (content as NSString).length)
  let paragraphStyle = NSMutableParagraphStyle()
  paragraphStyle.firstLineHeadIndent = 4
  paragraphStyle.headIndent = 12
  paragraphStyle.tailIndent = -8
  paragraphStyle.lineSpacing = 2
  paragraphStyle.paragraphSpacing = 5
  let attributed = NSMutableAttributedString(
    string: text,
    attributes: [.font: font, .paragraphStyle: paragraphStyle]
  )
  attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)

  let indentWidth = ("    " as NSString).size(withAttributes: [.font: font]).width
  let firstSequence = (content as NSString).rangeOfComposedCharacterSequence(at: 0)
  let firstSequenceText = (content as NSString).substring(with: firstSequence)
  let firstSequenceWidth = (firstSequenceText as NSString).size(withAttributes: [.font: font]).width
  let width = paragraphStyle.firstLineHeadIndent + indentWidth + 20 + firstSequenceWidth
    - paragraphStyle.tailIndent + 1
  let (textView, _) = narrowChecklistEditor(attributed, width: width)
  let layoutManager = try #require(textView.layoutManager)
  let textContainer = try #require(textView.textContainer)
  let beforeLayout = textView.attributedString()
  layoutManager.ensureLayout(for: textContainer)

  let storage = try #require(textView.textStorage)
  #expect(textView.string == text)
  #expect(textView.attributedString().isEqual(to: beforeLayout))
  let composedRange = NSRange(
    location: contentLocation + firstSequence.location,
    length: firstSequence.length
  )
  let composedGlyphs = layoutManager.glyphRange(
    forCharacterRange: composedRange,
    actualCharacterRange: nil
  )
  #expect(composedGlyphs.length > 0)
  let firstComposedLine = layoutManager.lineFragmentRect(
    forGlyphAt: composedGlyphs.location,
    effectiveRange: nil
  )
  let marker = checklistGlyphOrigin(at: 4, layoutManager: layoutManager)
  #expect(abs(marker.line.minY - firstComposedLine.minY) < 0.5)
  for glyphIndex in composedGlyphs.location..<NSMaxRange(composedGlyphs) {
    let line = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
    #expect(abs(line.minY - firstComposedLine.minY) < 0.5)
  }

  let paragraphBeforeSave = try #require(
    storage.attribute(.paragraphStyle, at: contentLocation, effectiveRange: nil) as? NSParagraphStyle
  )
  let originalParagraph = try #require(
    attributed.attribute(.paragraphStyle, at: contentLocation, effectiveRange: nil) as? NSParagraphStyle
  )
  let effectiveRightEdge: (CGFloat, CGFloat, CGFloat, CGFloat) -> CGFloat = {
    tailIndent, paperWidth, leftMargin, rightMargin in
    tailIndent > 0
      ? leftMargin + tailIndent
      : paperWidth - rightMargin + tailIndent
  }
  let rtf = try beforeLayout.data(
    from: NSRange(location: 0, length: beforeLayout.length),
    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
  )
  var actualDocumentAttributes: NSDictionary?
  let restored = try NSAttributedString(
    data: rtf,
    options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: &actualDocumentAttributes
  )
  try #require(restored.string == text)
  let paragraphAfterSave = try #require(
    restored.attribute(.paragraphStyle, at: contentLocation, effectiveRange: nil) as? NSParagraphStyle
  )
  #expect(paragraphAfterSave.firstLineHeadIndent == paragraphBeforeSave.firstLineHeadIndent)
  #expect(paragraphAfterSave.headIndent == paragraphBeforeSave.headIndent)
  #expect(paragraphAfterSave.lineSpacing == paragraphBeforeSave.lineSpacing)
  #expect(paragraphAfterSave.paragraphSpacing == paragraphBeforeSave.paragraphSpacing)
  let actualRestoredFont = try #require(
    restored.attribute(.font, at: contentLocation, effectiveRange: nil) as? NSFont
  )
  #expect(actualRestoredFont.pointSize == font.pointSize)
  #expect(
    restored.attribute(.strikethroughStyle, at: contentLocation, effectiveRange: nil) as? Int
      == NSUnderlineStyle.single.rawValue
  )

  let defaultReferenceRTF = try attributed.data(
    from: NSRange(location: 0, length: attributed.length),
    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
  )
  var defaultReferenceDocumentAttributes: NSDictionary?
  let defaultReferenceRestored = try NSAttributedString(
    data: defaultReferenceRTF,
    options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: &defaultReferenceDocumentAttributes
  )
  try #require(defaultReferenceRestored.string == text)
  let defaultReferenceParagraph = try #require(
    defaultReferenceRestored.attribute(.paragraphStyle, at: contentLocation, effectiveRange: nil)
      as? NSParagraphStyle
  )
  #expect(defaultReferenceParagraph.firstLineHeadIndent == originalParagraph.firstLineHeadIndent)
  #expect(defaultReferenceParagraph.headIndent == originalParagraph.headIndent)
  #expect(defaultReferenceParagraph.lineSpacing == originalParagraph.lineSpacing)
  #expect(defaultReferenceParagraph.paragraphSpacing == originalParagraph.paragraphSpacing)
  let defaultReferenceFont = try #require(
    defaultReferenceRestored.attribute(.font, at: contentLocation, effectiveRange: nil) as? NSFont
  )
  #expect(defaultReferenceFont.pointSize == font.pointSize)
  #expect(
    defaultReferenceRestored.attribute(.strikethroughStyle, at: contentLocation, effectiveRange: nil)
      as? Int == NSUnderlineStyle.single.rawValue
  )

  let actualDecodedAttributes = try #require(
    actualDocumentAttributes as? [NSAttributedString.DocumentAttributeKey: Any]
  )
  let defaultReferenceDecodedAttributes = try #require(
    defaultReferenceDocumentAttributes as? [NSAttributedString.DocumentAttributeKey: Any]
  )
  let actualPaperSize = try #require(
    (actualDecodedAttributes[.paperSize] as? NSValue)?.sizeValue
  )
  let actualLeftMargin = CGFloat(
    try #require((actualDecodedAttributes[.leftMargin] as? NSNumber)?.doubleValue)
  )
  let actualRightMargin = CGFloat(
    try #require((actualDecodedAttributes[.rightMargin] as? NSNumber)?.doubleValue)
  )
  let defaultReferencePaperSize = try #require(
    (defaultReferenceDecodedAttributes[.paperSize] as? NSValue)?.sizeValue
  )
  let defaultReferenceLeftMargin = CGFloat(
    try #require((defaultReferenceDecodedAttributes[.leftMargin] as? NSNumber)?.doubleValue)
  )
  let defaultReferenceRightMargin = CGFloat(
    try #require((defaultReferenceDecodedAttributes[.rightMargin] as? NSNumber)?.doubleValue)
  )
  #expect(actualPaperSize == defaultReferencePaperSize)
  #expect(actualLeftMargin == defaultReferenceLeftMargin)
  #expect(actualRightMargin == defaultReferenceRightMargin)
  #expect(paragraphAfterSave.tailIndent == defaultReferenceParagraph.tailIndent)
  #expect(
    effectiveRightEdge(
      paragraphAfterSave.tailIndent,
      actualPaperSize.width,
      actualLeftMargin,
      actualRightMargin
    )
      == effectiveRightEdge(
        defaultReferenceParagraph.tailIndent,
        defaultReferencePaperSize.width,
        defaultReferenceLeftMargin,
        defaultReferenceRightMargin
      )
  )

  let referenceWidths: [CGFloat] = [432, 612]
  let referenceLeftMargin: CGFloat = 24
  let referenceRightMargin: CGFloat = 32
  let twipsPerPoint: CGFloat = 20
  let expectedRightIndentTwips = Int((abs(originalParagraph.tailIndent) * twipsPerPoint).rounded())
  let indentationControlExpression = try NSRegularExpression(
    pattern: #"\\(?:li|ri|fi|paperw|paperh|margl|margr)-?\d+"#
  )
  for (index, paperWidth) in referenceWidths.enumerated() {
    let referencePaperSize = NSSize(width: paperWidth, height: 792)
    let referenceRTF = try attributed.data(
      from: NSRange(location: 0, length: attributed.length),
      documentAttributes: [
        .documentType: NSAttributedString.DocumentType.rtf,
        .paperSize: NSValue(size: referencePaperSize),
        .leftMargin: NSNumber(value: Double(referenceLeftMargin)),
        .rightMargin: NSNumber(value: Double(referenceRightMargin)),
      ]
    )
    var decodedDocumentAttributes: NSDictionary?
    let referenceRestored = try NSAttributedString(
      data: referenceRTF,
      options: [.documentType: NSAttributedString.DocumentType.rtf],
      documentAttributes: &decodedDocumentAttributes
    )
    try #require(referenceRestored.string == text)
    let decodedAttributes = try #require(
      decodedDocumentAttributes as? [NSAttributedString.DocumentAttributeKey: Any]
    )
    let decodedPaperSize = try #require(
      (decodedAttributes[.paperSize] as? NSValue)?.sizeValue
    )
    let decodedLeftMargin = CGFloat(
      try #require((decodedAttributes[.leftMargin] as? NSNumber)?.doubleValue)
    )
    let decodedRightMargin = CGFloat(
      try #require((decodedAttributes[.rightMargin] as? NSNumber)?.doubleValue)
    )
    #expect(decodedPaperSize == referencePaperSize)
    #expect(decodedLeftMargin == referenceLeftMargin)
    #expect(decodedRightMargin == referenceRightMargin)
    let referenceParagraph = try #require(
      referenceRestored.attribute(.paragraphStyle, at: contentLocation, effectiveRange: nil)
        as? NSParagraphStyle
    )
    #expect(referenceParagraph.firstLineHeadIndent == originalParagraph.firstLineHeadIndent)
    #expect(referenceParagraph.headIndent == originalParagraph.headIndent)
    #expect(referenceParagraph.lineSpacing == originalParagraph.lineSpacing)
    #expect(referenceParagraph.paragraphSpacing == originalParagraph.paragraphSpacing)
    let referenceFont = try #require(
      referenceRestored.attribute(.font, at: contentLocation, effectiveRange: nil) as? NSFont
    )
    #expect(referenceFont.pointSize == font.pointSize)
    #expect(
      referenceRestored.attribute(.strikethroughStyle, at: contentLocation, effectiveRange: nil)
        as? Int == NSUnderlineStyle.single.rawValue
    )

    let rtfString = String(decoding: referenceRTF, as: UTF8.self)
    let rtfNSString = rtfString as NSString
    let indentationControls = indentationControlExpression.matches(
      in: rtfString,
      range: NSRange(location: 0, length: rtfNSString.length)
    ).map { rtfNSString.substring(with: $0.range) }
    let expectedPaperWidthControl = "\\paperw\(Int((paperWidth * twipsPerPoint).rounded()))"
    let expectedPaperHeightControl = "\\paperh\(Int((referencePaperSize.height * twipsPerPoint).rounded()))"
    let expectedLeftMarginControl = "\\margl\(Int((referenceLeftMargin * twipsPerPoint).rounded()))"
    let expectedRightMarginControl = "\\margr\(Int((referenceRightMargin * twipsPerPoint).rounded()))"
    let paperWidthControls = indentationControls.filter { $0.hasPrefix("\\paperw") }
    let paperHeightControls = indentationControls.filter { $0.hasPrefix("\\paperh") }
    let leftMarginControls = indentationControls.filter { $0.hasPrefix("\\margl") }
    let rightMarginControls = indentationControls.filter { $0.hasPrefix("\\margr") }
    #expect(
      paperWidthControls.isEmpty || paperWidthControls.allSatisfy { $0 == expectedPaperWidthControl }
    )
    #expect(
      paperHeightControls.isEmpty || paperHeightControls.allSatisfy { $0 == expectedPaperHeightControl }
    )
    #expect(!leftMarginControls.isEmpty)
    #expect(leftMarginControls.allSatisfy { $0 == expectedLeftMarginControl })
    #expect(!rightMarginControls.isEmpty)
    #expect(rightMarginControls.allSatisfy { $0 == expectedRightMarginControl })
    #expect(
      indentationControls.filter { $0.hasPrefix("\\ri") }
        == ["\\ri\(expectedRightIndentTwips)"]
    )

    let matchedOriginalEdge = effectiveRightEdge(
      originalParagraph.tailIndent,
      decodedPaperSize.width,
      decodedLeftMargin,
      decodedRightMargin
    )
    let matchedDecodedEdge = effectiveRightEdge(
      referenceParagraph.tailIndent,
      decodedPaperSize.width,
      decodedLeftMargin,
      decodedRightMargin
    )
    #expect(matchedOriginalEdge == matchedDecodedEdge)
    let changedPaperWidth = referenceWidths[1 - index]
    let calculatedChangedOriginalEdge = effectiveRightEdge(
      originalParagraph.tailIndent,
      changedPaperWidth,
      decodedLeftMargin,
      decodedRightMargin
    )
    let calculatedChangedDecodedEdge = effectiveRightEdge(
      referenceParagraph.tailIndent,
      changedPaperWidth,
      decodedLeftMargin,
      decodedRightMargin
    )
    print(
      "CHECKLIST_RTF_REFERENCE matchedPaper=\(decodedPaperSize) margins=\(decodedLeftMargin),\(decodedRightMargin) "
        + "controls=\(indentationControls) originalTail=\(originalParagraph.tailIndent) "
        + "decodedTail=\(referenceParagraph.tailIndent) matchedOriginalEdge=\(matchedOriginalEdge) "
        + "matchedDecodedEdge=\(matchedDecodedEdge) "
        + "crossFrame=CALCULATED_ONLY_NOT_OBSERVED_RESIZE_REFLOW_OR_PORTABILITY "
        + "changedPaperWidth=\(changedPaperWidth) "
        + "calculatedOriginalEdge=\(calculatedChangedOriginalEdge) "
        + "calculatedDecodedEdge=\(calculatedChangedDecodedEdge)"
    )
  }

  for selection in [
    NSRange(location: contentLocation, length: 0),
    NSRange(location: contentLocation + firstSequence.length, length: 0),
  ] {
    let (undoTextView, _) = narrowChecklistEditor(attributed, width: width)
    let undoStorage = try #require(undoTextView.textStorage)
    undoTextView.undoManager?.removeAllActions()
    undoTextView.setSelectedRange(selection)
    #expect(undoTextView.toggleSelectedChecklist())
    #expect(undoTextView.string == "    ○ " + content)
    #expect(undoTextView.selectedRange() == selection)
    #expect(undoStorage.attribute(.strikethroughStyle, at: contentLocation, effectiveRange: nil) == nil)
    let undoManager = try #require(undoTextView.undoManager)
    undoManager.undo()
    #expect(undoTextView.string == text)
    #expect(undoTextView.selectedRange() == selection)
    #expect(
      undoStorage.attribute(.strikethroughStyle, at: contentLocation, effectiveRange: nil) as? Int
        == NSUnderlineStyle.single.rawValue
    )
    #expect(undoManager.canRedo)
    undoManager.redo()
    #expect(undoTextView.string == "    ○ " + content)
    #expect(undoTextView.selectedRange() == selection)
    #expect(undoStorage.attribute(.strikethroughStyle, at: contentLocation, effectiveRange: nil) == nil)
  }
}
