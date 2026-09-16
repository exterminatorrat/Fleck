import AppKit
import SwiftUI
import Testing

@testable import FleckApp

@Test @MainActor func productionHostDragReservesTheFullImageLine() throws {
  let fixture = try ProductionImageLayoutFixture()
  defer { fixture.remove() }
  let image = try fixture.makeImage(name: "production-drag.png", width: 640, height: 480)
  let intro = "Production typography keeps this line clear."
  let following = "Following text is unobscured."
  let initial = "\(intro)\n\n\(following)"
  let harness = ProductionEditorHarness(
    text: initial,
    store: fixture.store,
    width: 650,
    height: 650
  )
  defer { harness.close() }
  harness.settle()
  let editor = try harness.editor()
  let initialCaret = initial.utf16.count
  editor.setSelectedRange(NSRange(location: initialCaret, length: 0))
  editor.undoManager?.removeAllActions()

  let result = performProductionDrag(
    urls: [image],
    on: editor,
    in: harness.window,
    sourceLocation: intro.utf16.count + 1
  )
  #expect(result)
  harness.settle()

  let source = InlineNoteImageProjection.expanded(try #require(editor.textStorage))
  let reference = try #require(managedLayoutReferences(in: source.string).first)
  #expect(source.string == "\(intro)\n\(reference)\n\(following)")
  #expect(harness.model.text.utf16.elementsEqual(source.string.utf16))
  let decoded = try NSAttributedString(
    data: #require(harness.model.rtf),
    options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: nil
  )
  #expect(decoded.string.utf16.elementsEqual(source.string.utf16))

  let geometry = try attachmentGeometry(in: editor)
  #expect(geometry.line.insetBy(dx: -0.5, dy: -0.5).contains(geometry.bounds))
  let introBounds = try glyphBounds(of: intro, in: editor)
  let followingBounds = try glyphBounds(of: following, in: editor)
  #expect(NSIntersectionRect(geometry.bounds, introBounds).isEmpty)
  #expect(NSIntersectionRect(geometry.bounds, followingBounds).isEmpty)
  #expect(geometry.bounds.width == 426)
  #expect(geometry.bounds.height == 320)
  #expect(geometry.line.height == 320)
  #expect(textLineHeight(at: 0, in: editor) == 27)
  #expect(editor.layoutManager?.usedRect(for: geometry.container).contains(geometry.bounds) == true)
  let editorBounds = geometry.bounds.offsetBy(
    dx: editor.textContainerOrigin.x,
    dy: editor.textContainerOrigin.y
  )
  #expect(editor.bounds.insetBy(dx: -0.5, dy: -0.5).contains(editorBounds))

  let referenceRange = (source.string as NSString).range(of: reference)
  let paragraph = try #require(
    source.attribute(.paragraphStyle, at: referenceRange.location, effectiveRange: nil)
      as? NSParagraphStyle
  )
  #expect(paragraph.minimumLineHeight == 27)
  #expect(paragraph.maximumLineHeight == 27)
}

@Test @MainActor func productionHostLayoutTracksContentWithoutMutatingCanonicalSource() throws {
  let fixture = try ProductionImageLayoutFixture()
  defer { fixture.remove() }
  let inline = try fixture.store.importImage(
    at: fixture.makeImage(name: "inline.png", width: 80, height: 40)
  ).reference
  let firstSmall = try fixture.store.importImage(
    at: fixture.makeImage(name: "small-first.png", width: 60, height: 40)
  ).reference
  let secondSmall = try fixture.store.importImage(
    at: fixture.makeImage(name: "small-second.png", width: 50, height: 30)
  ).reference
  let landscape = try fixture.store.importImage(
    at: fixture.makeImage(name: "landscape.png", width: 640, height: 480)
  ).reference
  let portrait = try fixture.store.importImage(
    at: fixture.makeImage(name: "portrait.png", width: 120, height: 240)
  ).reference
  let following = "Final following text remains below every image."
  let body = """
    Plain production line.
    Inline prefix \(inline) trailing text.
    \(firstSmall)\(secondSmall)
    \(landscape)
    \(portrait)
    \(following)
    """
  let harness = ProductionEditorHarness(
    text: body,
    store: fixture.store,
    width: 650,
    height: 1_000
  )
  defer { harness.close() }
  harness.settle()
  let editor = try harness.editor()
  let originalSource = InlineNoteImageProjection.expanded(try #require(editor.textStorage))
  var geometries = try attachmentGeometries(in: editor)

  #expect(geometries.count == 5)
  assertAttachmentGeometryIsContained(geometries)
  #expect(geometries[0].attachmentBounds.size == NSSize(width: 80, height: 40))
  #expect(geometries[1].line.minY == geometries[2].line.minY)
  #expect(geometries[3].attachmentBounds.size == NSSize(width: 426, height: 320))
  #expect(geometries[4].attachmentBounds.size == NSSize(width: 120, height: 240))
  #expect(geometries[3].line.minY != geometries[4].line.minY)
  #expect(textLineHeight(at: 0, in: editor) == 27)
  #expect(geometries[0].bounds.minX > 0)
  #expect(
    try glyphLocation(of: " trailing text.", in: editor).x
      >= geometries[0].attachmentBounds.width + geometries[0].bounds.minX - 0.5
  )
  #expect(NSIntersectionRect(
    geometries[4].bounds,
    try glyphBounds(of: following, in: editor)
  ).isEmpty)
  #expect(
    originalSource.isEqual(
      to: InlineNoteImageProjection.expanded(try #require(editor.textStorage))
    )
  )

  harness.resize(width: 360, height: 1_000)
  geometries = try attachmentGeometries(in: editor)
  assertAttachmentGeometryIsContained(geometries)
  #expect(geometries[3].attachmentBounds.size == NSSize(width: 328, height: 245))
  #expect(geometries[4].attachmentBounds.size == NSSize(width: 120, height: 240))
  #expect(
    abs(
      geometries[3].attachmentBounds.width / geometries[3].attachmentBounds.height
        - 640 / 480
    ) < 0.01
  )
  #expect(
    originalSource.isEqual(
      to: InlineNoteImageProjection.expanded(try #require(editor.textStorage))
    )
  )
  harness.resize(width: 650, height: 1_000)

  geometries = try attachmentGeometries(in: editor)
  editor.setSelectedRange(geometries[4].characterRange)
  editor.undoManager?.removeAllActions()
  #expect(harness.model.commands.applyFontSize(23))
  harness.model.commands.applyList(.bullet(.disc))
  harness.settle()
  let formatted = InlineNoteImageProjection.expanded(try #require(editor.textStorage))
  let portraitRange = (formatted.string as NSString).range(of: portrait)
  let formattedFont = try #require(
    formatted.attribute(.font, at: portraitRange.location, effectiveRange: nil) as? NSFont
  )
  let formattedParagraph = try #require(
    formatted.attribute(.paragraphStyle, at: portraitRange.location, effectiveRange: nil)
      as? NSParagraphStyle
  )
  #expect(formattedFont.pointSize == 23)
  #expect(formattedParagraph.minimumLineHeight == 27)
  #expect(formattedParagraph.maximumLineHeight == 27)
  #expect(formatted.string.contains("• "))
  assertAttachmentGeometryIsContained(try attachmentGeometries(in: editor))
  editor.undoManager?.undo()
  harness.settle()
  editor.undoManager?.undo()
  harness.settle()
  #expect(
    originalSource.isEqual(
      to: InlineNoteImageProjection.expanded(try #require(editor.textStorage))
    )
  )

  geometries = try attachmentGeometries(in: editor)
  let removedLandscapeRange = geometries[3].characterRange
  editor.setSelectedRange(removedLandscapeRange)
  editor.deleteBackward(nil)
  harness.settle()
  #expect(try attachmentGeometries(in: editor).count == 4)
  #expect(textLineHeight(at: removedLandscapeRange.location, in: editor) == 27)
  editor.undoManager?.undo()
  harness.settle()
  #expect(try attachmentGeometries(in: editor).count == 5)
  editor.undoManager?.redo()
  harness.settle()
  #expect(textLineHeight(at: removedLandscapeRange.location, in: editor) == 27)
  editor.undoManager?.undo()
  harness.settle()

  geometries = try attachmentGeometries(in: editor)
  let pasteboard = NSPasteboard.withUniqueName()
  defer { pasteboard.releaseGlobally() }
  editor.setSelectedRange(geometries[0].characterRange)
  #expect(editor.writeSelection(to: pasteboard, types: editor.writablePasteboardTypes))
  editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
  #expect(editor.readSelection(from: pasteboard, type: .rtf))
  harness.settle()
  let pastedSource = InlineNoteImageProjection.expanded(try #require(editor.textStorage))
  #expect(try attachmentGeometries(in: editor).count == 6)
  #expect(try managedLayoutReferences(in: pastedSource.string).filter { $0 == inline }.count == 2)
  editor.undoManager?.undo()
  harness.settle()
  #expect(try attachmentGeometries(in: editor).count == 5)
  editor.undoManager?.redo()
  harness.settle()
  geometries = try attachmentGeometries(in: editor)
  editor.setSelectedRange(try #require(geometries.last).characterRange)
  editor.deleteBackward(nil)
  harness.settle()
  #expect(try attachmentGeometries(in: editor).count == 5)
  editor.undoManager?.undo()
  harness.settle()
  #expect(try attachmentGeometries(in: editor).count == 6)
  editor.undoManager?.redo()
  harness.settle()
  #expect(try attachmentGeometries(in: editor).count == 5)
  editor.undoManager?.undo()
  harness.settle()
  editor.undoManager?.undo()
  harness.settle()
  let restoredSource = InlineNoteImageProjection.expanded(try #require(editor.textStorage))
  #expect(originalSource.isEqual(to: restoredSource))

  let savedText = harness.model.text
  let savedRTF = try #require(harness.model.rtf)
  harness.close()
  let reopened = ProductionEditorHarness(
    text: savedText,
    rtf: savedRTF,
    store: fixture.store,
    width: 650,
    height: 1_000
  )
  defer { reopened.close() }
  reopened.settle()
  let reopenedEditor = try reopened.editor()
  let reopenedSource = InlineNoteImageProjection.expanded(
    try #require(reopenedEditor.textStorage)
  )
  #expect(reopenedSource.string.utf16.elementsEqual(savedText.utf16))
  for reference in [inline, firstSmall, secondSmall, landscape, portrait] {
    let range = (reopenedSource.string as NSString).range(of: reference)
    let font = try #require(
      reopenedSource.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
    )
    let paragraph = try #require(
      reopenedSource.attribute(.paragraphStyle, at: range.location, effectiveRange: nil)
        as? NSParagraphStyle
    )
    #expect(font.familyName == "Avenir Next")
    #expect(font.pointSize == 17)
    #expect(paragraph.minimumLineHeight == 27)
    #expect(paragraph.maximumLineHeight == 27)
  }
  assertAttachmentGeometryIsContained(try attachmentGeometries(in: reopenedEditor))
}

@Test @MainActor func productionLayoutDelegateFollowsRepresentableLifecycle() throws {
  let fixture = try ProductionImageLayoutFixture()
  defer { fixture.remove() }
  let harness = ProductionEditorHarness(
    text: "Lifecycle",
    store: fixture.store,
    width: 480,
    height: 320
  )
  harness.settle()
  let editor = try harness.editor()
  let layout = try #require(editor.layoutManager)
  #expect(layout.delegate === editor)
  harness.close()
  #expect(layout.delegate == nil)

  let replacementHarness = ProductionEditorHarness(
    text: "Replacement delegate",
    store: fixture.store,
    width: 480,
    height: 320
  )
  replacementHarness.settle()
  let replacementEditor = try replacementHarness.editor()
  let replacementLayout = try #require(replacementEditor.layoutManager)
  let replacementDelegate = ReplacementLayoutDelegate()
  replacementLayout.delegate = replacementDelegate
  replacementHarness.close()
  #expect(replacementLayout.delegate === replacementDelegate)
}

@Test @MainActor func productionHostPreservesChecklistGlyphsAlongsideInlineImages() throws {
  let fixture = try ProductionImageLayoutFixture()
  defer { fixture.remove() }
  let image = try fixture.makeImage(name: "checklist-image.png", width: 640, height: 480)
  let reference = try fixture.store.importImage(at: image).reference
  let body = """
    ○ Open checklist
    \(reference)
    Following adjacent image.
    ● \(reference) Same-paragraph image.
    Following checklist image.
    """
  let canonical = NSAttributedString(
    string: body,
    attributes: EditorTypography.defaultAttributes(family: "Avenir Next", size: 17)
  )
  let rtf = try canonical.data(
    from: NSRange(location: 0, length: canonical.length),
    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
  )
  let harness = ProductionEditorHarness(
    text: body,
    rtf: rtf,
    store: fixture.store,
    width: 650,
    height: 1_000
  )
  defer { harness.close() }
  harness.settle()
  let editor = try harness.editor()
  let storage = try #require(editor.textStorage)
  let sourceBeforeLayout = InlineNoteImageProjection.expanded(storage)
  #expect(sourceBeforeLayout.string.utf16.elementsEqual(body.utf16))
  #expect(harness.model.text.utf16.elementsEqual(body.utf16))
  #expect(harness.model.rtf == rtf)

  let layout = try #require(editor.layoutManager)
  let container = try #require(editor.textContainer)
  layout.ensureLayout(for: container)
  let displayed = editor.string as NSString
  let markers = [
    ("○", displayed.range(of: "○").location),
    ("●", displayed.range(of: "●").location),
  ]
  var markerLines: [NSRect] = []
  for (marker, location) in markers {
    #expect(displayed.substring(with: NSRange(location: location, length: 1)) == marker)
    for characterIndex in location...(location + 1) {
      let glyph = layout.glyphIndexForCharacter(at: characterIndex)
      #expect(layout.propertyForGlyph(at: glyph).contains(.controlCharacter))
    }
    let prefixGlyphs = layout.glyphRange(
      forCharacterRange: NSRange(location: location, length: 2),
      actualCharacterRange: nil
    )
    let slot = layout.boundingRect(forGlyphRange: prefixGlyphs, in: container)
      .offsetBy(dx: editor.textContainerOrigin.x, dy: editor.textContainerOrigin.y)
    #expect(abs(slot.width - 20) < 0.01)
    let markerRect = try #require(
      editor.checklistMarkerRect(for: NSRange(location: location, length: 1))
    )
    #expect(abs(markerRect.minX - slot.minX) < 0.01)
    let hitRect = try #require(
      editor.checklistHitRect(for: NSRange(location: location, length: 1))
    )
    #expect(hitRect.contains(markerRect))
    let markerGlyph = layout.glyphIndexForCharacter(at: location)
    markerLines.append(layout.lineFragmentRect(forGlyphAt: markerGlyph, effectiveRange: nil))
  }

  let geometries = try attachmentGeometries(in: editor)
  #expect(geometries.count == 2)
  for geometry in geometries {
    #expect(geometry.attachmentBounds.size == NSSize(width: 426, height: 320))
    #expect(geometry.line.insetBy(dx: -0.5, dy: -0.5).contains(geometry.bounds))
  }
  #expect(geometries[0].line.height == 320)
  let neighboringCharacters = displayed.range(of: "Same-paragraph image.")
  let neighboringGlyphs = layout.glyphRange(
    forCharacterRange: neighboringCharacters,
    actualCharacterRange: nil
  )
  var textFragments: [(line: NSRect, glyphs: NSRange)] = []
  layout.enumerateLineFragments(forGlyphRange: neighboringGlyphs) {
    line, _, _, lineGlyphs, _ in
    let intersection = NSIntersectionRange(lineGlyphs, neighboringGlyphs)
    if intersection.length > 0 {
      textFragments.append((line, intersection))
    }
  }
  #expect(!textFragments.isEmpty)
  var coveredGlyphLocation = neighboringGlyphs.location
  for fragment in textFragments {
    #expect(fragment.glyphs.location == coveredGlyphLocation)
    coveredGlyphLocation = NSMaxRange(fragment.glyphs)
  }
  #expect(coveredGlyphLocation == NSMaxRange(neighboringGlyphs))

  let sharedFragments = textFragments.filter {
    $0.line.minY == geometries[1].line.minY
  }
  let wrappedFragments = textFragments.filter {
    $0.line.minY >= geometries[1].line.maxY
  }
  let sharedFragment = try #require(sharedFragments.first)
  #expect(sharedFragment.glyphs.length > 0)
  #expect(sharedFragment.glyphs.location == neighboringGlyphs.location)
  #expect(!wrappedFragments.isEmpty)
  #expect(sharedFragments.count + wrappedFragments.count == textFragments.count)

  let firstSharedGlyph = sharedFragment.glyphs.location
  let firstSharedLocation = layout.location(forGlyphAt: firstSharedGlyph)
  let firstSharedOrigin = NSPoint(
    x: sharedFragment.line.minX + firstSharedLocation.x,
    y: sharedFragment.line.minY + firstSharedLocation.y
  )
  #expect(firstSharedOrigin.x > geometries[1].bounds.maxX)
  let imageGlyph = layout.glyphRange(
    forCharacterRange: geometries[1].characterRange,
    actualCharacterRange: nil
  ).location
  let imageBaseline = geometries[1].line.minY + layout.location(forGlyphAt: imageGlyph).y
  #expect(abs(firstSharedOrigin.y - imageBaseline) < 0.01)

  let controlCharacter = displayed.range(of: "Open checklist").location
  let controlGlyph = layout.glyphIndexForCharacter(at: controlCharacter)
  let controlLine = layout.lineFragmentRect(forGlyphAt: controlGlyph, effectiveRange: nil)
  let nativeBelowBaseline = controlLine.height - layout.location(forGlyphAt: controlGlyph).y
  let mixedBelowBaseline = sharedFragment.line.height - firstSharedLocation.y
  #expect(mixedBelowBaseline >= nativeBelowBaseline)

  var precedingLine = geometries[1].line
  for fragment in wrappedFragments {
    #expect(fragment.line.minY >= precedingLine.maxY)
    #expect(fragment.line.height == controlLine.height)
    precedingLine = fragment.line
  }
  let followingCharacter = displayed.range(of: "Following checklist image.").location
  let followingGlyph = layout.glyphIndexForCharacter(at: followingCharacter)
  let followingLine = layout.lineFragmentRect(forGlyphAt: followingGlyph, effectiveRange: nil)
  #expect(followingLine.minY >= precedingLine.maxY)
  #expect(markerLines[0].maxY <= geometries[0].line.minY)
  #expect(markerLines[1].minY == geometries[1].line.minY)
  #expect(NSIntersectionRect(
    geometries[0].bounds,
    try glyphBounds(of: "Following adjacent image.", in: editor)
  ).isEmpty)
  #expect(NSIntersectionRect(
    geometries[1].bounds,
    try glyphBounds(of: "Following checklist image.", in: editor)
  ).isEmpty)

  let sourceAfterLayout = InlineNoteImageProjection.expanded(storage)
  #expect(sourceAfterLayout.isEqual(to: sourceBeforeLayout))
  let serialized = try sourceAfterLayout.data(
    from: NSRange(location: 0, length: sourceAfterLayout.length),
    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
  )
  let decoded = try NSAttributedString(
    data: serialized,
    options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: nil
  )
  #expect(decoded.string.utf16.elementsEqual(body.utf16))
  let reprojected = fixture.store.projectedContent(from: decoded)
  #expect(
    InlineNoteImageProjection.expanded(reprojected).string.utf16.elementsEqual(body.utf16)
  )
}

@Test @MainActor func productionLayoutReservesShiftedImagesButNotShiftedText() throws {
  let fixture = try ProductionImageLayoutFixture()
  defer { fixture.remove() }
  let image = try fixture.makeImage(name: "baseline.png", width: 640, height: 480)
  let reference = try fixture.store.importImage(at: image).reference

  for shift: CGFloat in [-80, 80] {
    let body = "Before\n\(reference)\nAfter"
    let attributed = NSMutableAttributedString(
      string: body,
      attributes: EditorTypography.defaultAttributes(family: "Avenir Next", size: 17)
    )
    attributed.addAttribute(
      .baselineOffset,
      value: shift,
      range: (body as NSString).range(of: reference)
    )
    let rtf = try attributed.data(
      from: NSRange(location: 0, length: attributed.length),
      documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
    )
    let harness = ProductionEditorHarness(
      text: body,
      rtf: rtf,
      store: fixture.store,
      width: 650,
      height: 650
    )
    defer { harness.close() }
    harness.settle()
    let editor = try harness.editor()
    let sourceBeforeLayout = InlineNoteImageProjection.expanded(
      try #require(editor.textStorage)
    )
    let geometry = try attachmentGeometry(in: editor)

    #expect(geometry.line.insetBy(dx: -0.5, dy: -0.5).contains(geometry.bounds))
    #expect(geometry.line.height == 400)
    #expect(NSIntersectionRect(
      geometry.bounds,
      try glyphBounds(of: "Before", in: editor)
    ).isEmpty)
    #expect(NSIntersectionRect(
      geometry.bounds,
      try glyphBounds(of: "After", in: editor)
    ).isEmpty)
    let sourceAfterLayout = InlineNoteImageProjection.expanded(
      try #require(editor.textStorage)
    )
    #expect(sourceBeforeLayout.isEqual(to: sourceAfterLayout))
    let referenceRange = (sourceAfterLayout.string as NSString).range(of: reference)
    #expect(
      (sourceAfterLayout.attribute(
        .baselineOffset,
        at: referenceRange.location,
        effectiveRange: nil
      ) as? NSNumber)?.doubleValue == Double(shift)
    )
  }

  let text = "Text-only shifted baseline"
  let attributedText = NSMutableAttributedString(
    string: text,
    attributes: EditorTypography.defaultAttributes(family: "Avenir Next", size: 17)
  )
  attributedText.addAttribute(
    .baselineOffset,
    value: -80,
    range: NSRange(location: 0, length: attributedText.length)
  )
  let textRTF = try attributedText.data(
    from: NSRange(location: 0, length: attributedText.length),
    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
  )
  let textHarness = ProductionEditorHarness(
    text: text,
    rtf: textRTF,
    store: fixture.store,
    width: 650,
    height: 320
  )
  defer { textHarness.close() }
  textHarness.settle()
  let textEditor = try textHarness.editor()
  let textSource = InlineNoteImageProjection.expanded(try #require(textEditor.textStorage))
  #expect(textLineHeight(at: 0, in: textEditor) == 27)
  #expect(
    (textSource.attribute(.baselineOffset, at: 0, effectiveRange: nil) as? NSNumber)?
      .doubleValue == -80
  )
}

@Test @MainActor func productionHostRendersRealisticImageEvidence() throws {
  guard let evidencePath = ProcessInfo.processInfo.environment["FLECK_LAYOUT_EVIDENCE_DIR"]
  else { return }
  let evidenceDirectory = URL(fileURLWithPath: evidencePath, isDirectory: true)
  try FileManager.default.createDirectory(
    at: evidenceDirectory,
    withIntermediateDirectories: true
  )
  let fixture = try ProductionImageLayoutFixture()
  defer { fixture.remove() }
  let image = try fixture.makeImage(name: "evidence-landscape.png", width: 640, height: 480)
  let reference = try fixture.store.importImage(at: image).reference
  let intro = "A complete generated landscape follows."
  let following = "Following text remains fully visible."
  let body = "\(intro)\n\(reference)\n\(following)"
  let appearances: [(String, NSAppearance.Name)] = [
    ("light", .aqua),
    ("dark", .darkAqua),
    ("high-contrast", .accessibilityHighContrastAqua),
  ]
  let widths: [(String, CGFloat)] = [("narrow", 360), ("normal", 650)]

  for (appearanceName, appearance) in appearances {
    for (widthName, width) in widths {
      let harness = ProductionEditorHarness(
        text: body,
        store: fixture.store,
        width: width,
        height: 520,
        appearance: appearance
      )
      harness.settle()
      let editor = try harness.editor()
      let sourceBeforeCapture = InlineNoteImageProjection.expanded(
        try #require(editor.textStorage)
      )
      let geometry = try attachmentGeometry(in: editor)
      #expect(geometry.line.insetBy(dx: -0.5, dy: -0.5).contains(geometry.bounds))
      #expect(NSIntersectionRect(
        geometry.bounds,
        try glyphBounds(of: intro, in: editor)
      ).isEmpty)
      #expect(NSIntersectionRect(
        geometry.bounds,
        try glyphBounds(of: following, in: editor)
      ).isEmpty)
      #expect(textLineHeight(at: 0, in: editor) == 27)
      #expect(geometry.attachmentBounds.width <= width - 32)
      #expect(geometry.attachmentBounds.height <= 320)
      let sourceAfterLayout = InlineNoteImageProjection.expanded(
        try #require(editor.textStorage)
      )
      #expect(sourceBeforeCapture.isEqual(to: sourceAfterLayout))

      let bitmap = try #require(
        harness.host.bitmapImageRepForCachingDisplay(in: harness.host.bounds)
      )
      harness.host.cacheDisplay(in: harness.host.bounds, to: bitmap)
      var bluePixels = 0
      var yellowPixels = 0
      var greenPixels = 0
      for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
          guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
            color.alphaComponent > 0.9
          else { continue }
          if color.blueComponent > 0.65
            && color.blueComponent > color.redComponent + 0.2
          {
            bluePixels += 1
          }
          if color.redComponent > 0.8
            && color.greenComponent > 0.5
            && color.blueComponent < 0.35
          {
            yellowPixels += 1
          }
          if color.greenComponent > color.redComponent + 0.15
            && color.greenComponent > color.blueComponent
          {
            greenPixels += 1
          }
        }
      }
      #expect(bluePixels > 1_000)
      #expect(yellowPixels > 50)
      #expect(greenPixels > 500)
      try #require(bitmap.representation(using: .png, properties: [:])).write(
        to: evidenceDirectory.appendingPathComponent(
          "production-layout-\(appearanceName)-\(widthName).png"
        )
      )
      harness.close()
    }
  }

  let inline = try fixture.store.importImage(
    at: fixture.makeImage(name: "evidence-inline.png", width: 80, height: 40)
  ).reference
  let second = try fixture.store.importImage(
    at: fixture.makeImage(name: "evidence-second.png", width: 100, height: 60)
  ).reference
  let multiHarness = ProductionEditorHarness(
    text: "Inline prefix \(inline) trailing text.\n\(inline)\(second)\n\(reference)\nFollowing text.",
    store: fixture.store,
    width: 650,
    height: 650
  )
  multiHarness.settle()
  assertAttachmentGeometryIsContained(
    try attachmentGeometries(in: multiHarness.editor())
  )
  let multiBitmap = try #require(
    multiHarness.host.bitmapImageRepForCachingDisplay(in: multiHarness.host.bounds)
  )
  multiHarness.host.cacheDisplay(in: multiHarness.host.bounds, to: multiBitmap)
  try #require(multiBitmap.representation(using: .png, properties: [:])).write(
    to: evidenceDirectory.appendingPathComponent("production-layout-inline-multiple.png")
  )
  multiHarness.close()
}

@MainActor
private final class ProductionEditorModel: ObservableObject {
  @Published var text: String
  @Published var rtf: Data?
  @Published var fontFamily: String
  @Published var fontSize: Double
  let commands = EditorCommands()
  let store: InlineNoteImageStore

  init(
    text: String,
    rtf: Data? = nil,
    fontFamily: String = "Avenir Next",
    fontSize: Double = 17,
    store: InlineNoteImageStore
  ) {
    self.text = text
    self.rtf = rtf
    self.fontFamily = fontFamily
    self.fontSize = fontSize
    self.store = store
  }
}

@MainActor
private struct ProductionEditorView: View {
  @ObservedObject var model: ProductionEditorModel

  var body: some View {
    NativeRichTextEditor(
      text: model.text,
      richTextRTF: model.rtf,
      title: "Production typography",
      onChange: { text, rtf in
        model.text = text
        model.rtf = rtf
      },
      fontFamily: model.fontFamily,
      fontSize: model.fontSize,
      textColorHex: nil,
      backgroundColorHex: nil,
      accentColorHex: "#007AFF",
      reduceMotion: true,
      automaticLists: true,
      commands: model.commands,
      inlineImageStore: model.store
    )
    .background(Color(nsColor: .textBackgroundColor))
  }
}

@MainActor
private final class ProductionEditorHarness {
  let model: ProductionEditorModel
  let host: NSHostingView<AnyView>
  let window: NSWindow

  init(
    text: String,
    rtf: Data? = nil,
    store: InlineNoteImageStore,
    width: CGFloat,
    height: CGFloat,
    appearance: NSAppearance.Name = .aqua
  ) {
    model = ProductionEditorModel(text: text, rtf: rtf, store: store)
    host = NSHostingView(rootView: AnyView(ProductionEditorView(model: model)))
    host.frame = NSRect(x: 0, y: 0, width: width, height: height)
    window = NSWindow(
      contentRect: host.frame,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    window.isReleasedWhenClosed = false
    let resolvedAppearance = NSAppearance(named: appearance)
    window.appearance = resolvedAppearance
    host.appearance = resolvedAppearance
    window.contentView = host
  }

  func settle() {
    host.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.08))
    host.layoutSubtreeIfNeeded()
  }

  func editor() throws -> ListAwareTextView {
    try #require(model.commands.textView as? ListAwareTextView)
  }

  func resize(width: CGFloat, height: CGFloat) {
    window.setContentSize(NSSize(width: width, height: height))
    host.frame = NSRect(x: 0, y: 0, width: width, height: height)
    settle()
  }

  func close() {
    host.rootView = AnyView(EmptyView())
    settle()
    window.close()
  }
}

private struct AttachmentGeometry {
  let characterRange: NSRange
  let bounds: NSRect
  let attachmentBounds: NSRect
  let line: NSRect
  let container: NSTextContainer
}

@MainActor
private func assertAttachmentGeometryIsContained(_ geometries: [AttachmentGeometry]) {
  for geometry in geometries {
    #expect(geometry.line.insetBy(dx: -0.5, dy: -0.5).contains(geometry.bounds))
    #expect(
      geometry.container.layoutManager?.usedRect(for: geometry.container)
        .insetBy(dx: -0.5, dy: -0.5).contains(geometry.bounds) == true
    )
  }
}

@MainActor
private func attachmentGeometry(in editor: NSTextView) throws -> AttachmentGeometry {
  try #require(attachmentGeometries(in: editor).first)
}

@MainActor
private func attachmentGeometries(in editor: NSTextView) throws -> [AttachmentGeometry] {
  let storage = try #require(editor.textStorage)
  let layout = try #require(editor.layoutManager)
  let container = try #require(editor.textContainer)
  layout.ensureLayout(for: container)
  var attachmentRuns: [(NSRange, InlineNoteImageAttachment)] = []
  storage.enumerateAttribute(
    .attachment,
    in: NSRange(location: 0, length: storage.length)
  ) { value, range, _ in
    guard let attachment = value as? InlineNoteImageAttachment else { return }
    attachmentRuns.append((range, attachment))
  }
  return attachmentRuns.map { range, attachment in
    let glyphRange = layout.glyphRange(
      forCharacterRange: range,
      actualCharacterRange: nil
    )
    let line = layout.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
    return AttachmentGeometry(
      characterRange: range,
      bounds: layout.boundingRect(forGlyphRange: glyphRange, in: container),
      attachmentBounds: attachment.attachmentBounds(
        for: container,
        proposedLineFragment: line,
        glyphPosition: .zero,
        characterIndex: range.location
      ),
      line: line,
      container: container
    )
  }
}

@MainActor
private func glyphBounds(of text: String, in editor: NSTextView) throws -> NSRect {
  let layout = try #require(editor.layoutManager)
  let container = try #require(editor.textContainer)
  let characterRange = (editor.string as NSString).range(of: text)
  let glyphRange = layout.glyphRange(
    forCharacterRange: characterRange,
    actualCharacterRange: nil
  )
  return layout.boundingRect(forGlyphRange: glyphRange, in: container)
}

@MainActor
private func glyphLocation(of text: String, in editor: NSTextView) throws -> NSPoint {
  let layout = try #require(editor.layoutManager)
  let characterRange = (editor.string as NSString).range(of: text)
  let glyph = layout.glyphIndexForCharacter(at: characterRange.location)
  return layout.location(forGlyphAt: glyph)
}

@MainActor
private func textLineHeight(at characterIndex: Int, in editor: NSTextView) -> CGFloat {
  guard let layout = editor.layoutManager else { return 0 }
  let glyph = layout.glyphIndexForCharacter(at: characterIndex)
  return layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).height
}

@MainActor
private func performProductionDrag(
  urls: [URL],
  on editor: NSTextView,
  in window: NSWindow,
  sourceLocation: Int
) -> Bool {
  guard let layout = editor.layoutManager, let container = editor.textContainer else {
    return false
  }
  layout.ensureLayout(for: container)
  let glyph = layout.glyphIndexForCharacter(at: sourceLocation)
  let line = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
  let point = NSPoint(
    x: editor.textContainerOrigin.x + line.minX + 4,
    y: editor.textContainerOrigin.y + line.midY
  )
  let pasteboard = NSPasteboard.withUniqueName()
  defer { pasteboard.releaseGlobally() }
  pasteboard.writeObjects(urls.map { $0 as NSURL })
  let info = ProductionDraggingInfo(
    window: window,
    location: editor.convert(point, to: nil),
    pasteboard: pasteboard,
    itemCount: urls.count
  )
  guard editor.draggingEntered(info) == .copy,
    editor.draggingUpdated(info) == .copy,
    editor.prepareForDragOperation(info)
  else { return false }
  let performed = editor.performDragOperation(info)
  editor.concludeDragOperation(info)
  return performed
}

@MainActor
private final class ProductionDraggingInfo: NSObject, NSDraggingInfo {
  let draggingDestinationWindow: NSWindow?
  let draggingSourceOperationMask: NSDragOperation = .copy
  var draggingLocation: NSPoint
  let draggedImageLocation: NSPoint = .zero
  let draggedImage: NSImage? = nil
  let draggingPasteboard: NSPasteboard
  let draggingSource: Any? = nil
  let draggingSequenceNumber = 1
  var draggingFormation: NSDraggingFormation = .none
  var animatesToDestination = false
  var numberOfValidItemsForDrop: Int
  let springLoadingHighlight: NSSpringLoadingHighlight = .none

  init(
    window: NSWindow,
    location: NSPoint,
    pasteboard: NSPasteboard,
    itemCount: Int
  ) {
    draggingDestinationWindow = window
    draggingLocation = location
    draggingPasteboard = pasteboard
    numberOfValidItemsForDrop = itemCount
  }

  func slideDraggedImage(to screenPoint: NSPoint) {}

  override func namesOfPromisedFilesDropped(
    atDestination dropDestination: URL
  ) -> [String]? { nil }

  func enumerateDraggingItems(
    options enumOpts: NSDraggingItemEnumerationOptions,
    for view: NSView?,
    classes classArray: [AnyClass],
    searchOptions: [NSPasteboard.ReadingOptionKey: Any],
    using block: @escaping (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
  ) {}

  func resetSpringLoading() {}
}

@MainActor
private final class ReplacementLayoutDelegate: NSObject, NSLayoutManagerDelegate {}

@MainActor
private struct ProductionImageLayoutFixture {
  let root: URL
  let store: InlineNoteImageStore

  init() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "FleckInlineImageLayout-\(UUID().uuidString)",
      isDirectory: true
    )
    store = InlineNoteImageStore(
      rootURL: root.appendingPathComponent("managed", isDirectory: true)
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  func remove() {
    try? FileManager.default.removeItem(at: root)
  }

  func makeImage(name: String, width: Int, height: Int) throws -> URL {
    let bitmap = try #require(NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: width,
      pixelsHigh: height,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ))
    for y in 0..<height {
      for x in 0..<width {
        let horizontal = CGFloat(x) / CGFloat(max(1, width - 1))
        let vertical = CGFloat(y) / CGFloat(max(1, height - 1))
        let ground = vertical > 0.72
        let sun = pow(horizontal - 0.78, 2) + pow(vertical - 0.2, 2) < 0.008
        let mountain = vertical >= 0.28 + abs(horizontal - 0.56) * 0.9
          && vertical < 0.72
        let tree = pow((horizontal - 0.18) / 0.09, 2)
          + pow((vertical - 0.56) / 0.16, 2) < 1
        let color: NSColor
        if ground {
          color = NSColor(calibratedRed: 0.12, green: 0.55, blue: 0.18, alpha: 1)
        } else if tree {
          color = NSColor(calibratedRed: 0.04, green: 0.38, blue: 0.12, alpha: 1)
        } else if mountain {
          color = horizontal < 0.56
            ? NSColor(calibratedRed: 0.28, green: 0.32, blue: 0.42, alpha: 1)
            : NSColor(calibratedRed: 0.45, green: 0.39, blue: 0.34, alpha: 1)
        } else if sun {
          color = NSColor(calibratedRed: 1, green: 0.72, blue: 0.08, alpha: 1)
        } else {
          color = NSColor(
            calibratedRed: 0.12 + vertical * 0.15,
            green: 0.42 + vertical * 0.2,
            blue: 0.9,
            alpha: 1
          )
        }
        bitmap.setColor(color, atX: x, y: y)
      }
    }
    let url = root.appendingPathComponent(name)
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
    return url
  }
}

private func managedLayoutReferences(in source: String) throws -> [String] {
  let expression = try NSRegularExpression(pattern: #"!\[[^\]]*\]\((file://[^)]+)\)"#)
  return expression.matches(
    in: source,
    range: NSRange(location: 0, length: (source as NSString).length)
  ).map { match in
    (source as NSString).substring(with: match.range)
  }
}
