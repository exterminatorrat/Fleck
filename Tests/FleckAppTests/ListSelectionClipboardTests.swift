import AppKit
import Testing

@testable import FleckApp

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

@MainActor
private final class SelectionChangeObserver: NSObject {
  private(set) var count = 0

  @objc func selectionDidChange(_ notification: Notification) {
    count += 1
  }
}

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

@Test @MainActor func multilineSelectionDoesNotHighlightAnInterveningBulletGlyph() throws {
  let (textView, window) = bulletEditor("• first\n• second")
  let host = NSView(frame: textView.bounds)
  host.wantsLayer = true
  host.layer?.backgroundColor = NSColor.white.cgColor
  textView.removeFromSuperview()
  textView.frame = host.bounds
  textView.autoresizingMask = [.width, .height]
  host.addSubview(textView)
  window.contentView = host
  textView.appearance = NSAppearance(named: .aqua)
  textView.drawsBackground = false
  textView.textColor = .black
  #expect(window.makeFirstResponder(textView))
  let selection = NSRange(location: 2, length: textView.string.utf16.count - 2)
  textView.setSelectedRange(selection)
  textView.displayIfNeeded()
  window.displayIfNeeded()

  let layoutManager = try #require(textView.layoutManager)
  let textContainer = try #require(textView.textContainer)
  let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
  host.cacheDisplay(in: host.bounds, to: bitmap)
  let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
  let firstMarkerGlyphs = layoutManager.glyphRange(
    forCharacterRange: NSRange(location: 0, length: 1),
    actualCharacterRange: nil
  )
  let interveningMarkerGlyphs = layoutManager.glyphRange(
    forCharacterRange: NSRange(location: 8, length: 1),
    actualCharacterRange: nil
  )
  let contentGlyphs = layoutManager.glyphRange(
    forCharacterRange: NSRange(location: 10, length: 6),
    actualCharacterRange: nil
  )
  let firstMarkerRect = layoutManager.boundingRect(
    forGlyphRange: firstMarkerGlyphs,
    in: textContainer
  )
    .offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
  let interveningMarkerRect = layoutManager.boundingRect(
    forGlyphRange: interveningMarkerGlyphs,
    in: textContainer
  )
    .offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
  let contentRect = layoutManager.boundingRect(forGlyphRange: contentGlyphs, in: textContainer)
    .offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
  let firstMarkerBackground = try #require(
    pixelColor(
      at: NSPoint(x: firstMarkerRect.midX, y: firstMarkerRect.maxY - 2),
      bitmap: bitmap,
      scale: scale
    )
  )
  let interveningMarkerBackground = try #require(
    pixelColor(
      at: NSPoint(x: interveningMarkerRect.midX, y: interveningMarkerRect.maxY - 2),
      bitmap: bitmap,
      scale: scale
    )
  )
  let contentBackground = try #require(
    pixelColor(
      at: NSPoint(x: contentRect.midX, y: contentRect.maxY - 2),
      bitmap: bitmap,
      scale: scale
    )
  )
  let hostBackground = try #require(
    pixelColor(
      at: NSPoint(x: host.bounds.maxX - 10, y: host.bounds.maxY - 10),
      bitmap: bitmap,
      scale: scale
    )
  )
  #expect(pixelColorsDiffer(contentBackground, hostBackground))
  #expect(pixelColorsMatch(firstMarkerBackground, hostBackground))
  #expect(pixelColorsMatch(interveningMarkerBackground, hostBackground))
  if let evidenceDirectory = ProcessInfo.processInfo.environment["FLECK_EDITOR_EVIDENCE_DIR"] {
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    try png.write(
      to: URL(fileURLWithPath: evidenceDirectory).appendingPathComponent("bullet-selection.png")
    )
  }
}

@Test @MainActor func selectedBulletMarkerKeepsConfiguredTextViewBackground() throws {
  let (textView, window) = bulletEditor("• first\n• second")
  textView.drawsBackground = true
  textView.backgroundColor = NSColor(calibratedRed: 0.82, green: 0.91, blue: 0.76, alpha: 1)
  textView.setSelectedRange(NSRange(location: 2, length: textView.string.utf16.count - 2))
  #expect(window.makeFirstResponder(textView))
  textView.displayIfNeeded()
  window.displayIfNeeded()

  let layoutManager = try #require(textView.layoutManager)
  let textContainer = try #require(textView.textContainer)
  let bitmap = try #require(textView.bitmapImageRepForCachingDisplay(in: textView.bounds))
  textView.cacheDisplay(in: textView.bounds, to: bitmap)
  let markerGlyphs = layoutManager.glyphRange(
    forCharacterRange: NSRange(location: 8, length: 1),
    actualCharacterRange: nil
  )
  let markerRect = layoutManager.boundingRect(
    forGlyphRange: markerGlyphs,
    in: textContainer
  ).offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
  let scale = CGFloat(bitmap.pixelsWide) / textView.bounds.width
  let markerBackground = try #require(
    pixelColor(
      at: NSPoint(x: markerRect.midX, y: markerRect.maxY - 2),
      bitmap: bitmap,
      scale: scale
    )
  )
  let expectedBackground = try #require(textView.backgroundColor.usingColorSpace(.sRGB))

  #expect(pixelColorsMatch(markerBackground, expectedBackground))
}

@Test @MainActor func wholeItemClipboardPreservesMarkersAndSubstringClipboardDoesNot() throws {
  let (source, sourceWindow) = bulletEditor("• note")
  #expect(sourceWindow.makeFirstResponder(source))
  source.setSelectedRange(NSRange(location: 2, length: 4))

  let plainPasteboard = NSPasteboard.withUniqueName()
  defer { plainPasteboard.releaseGlobally() }
  #expect(source.writeSelection(to: plainPasteboard, types: source.writablePasteboardTypes))
  #expect(source.selectedRange() == NSRange(location: 2, length: 4))
  let plainText = try #require(plainPasteboard.string(forType: .string))
  #expect(plainText == "• note")

  let plainPaste = bulletEditor("").0
  plainPaste.insertPastedTextForTesting(
    NSAttributedString(string: plainText),
    plainText: plainText,
    hasRichFormatting: false
  )
  #expect(plainPaste.string == "• note")

  let richPasteboard = NSPasteboard.withUniqueName()
  defer { richPasteboard.releaseGlobally() }
  #expect(source.writeSelection(to: richPasteboard, types: source.writablePasteboardTypes))
  #expect(source.selectedRange() == NSRange(location: 2, length: 4))
  let richData = try #require(richPasteboard.data(forType: .rtf))
  let richText = try NSAttributedString(
    data: richData,
    options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: nil
  )
  #expect(richText.string == "• note")

  let explicitTypesPasteboard = NSPasteboard.withUniqueName()
  defer { explicitTypesPasteboard.releaseGlobally() }
  #expect(source.writeSelection(to: explicitTypesPasteboard, types: [.rtf, .string]))
  #expect(explicitTypesPasteboard.string(forType: .string) == "• note")
  #expect(explicitTypesPasteboard.data(forType: .rtf) != nil)
  #expect(source.selectedRange() == NSRange(location: 2, length: 4))

  for type in [NSPasteboard.PasteboardType.string, .rtf] {
    let directPasteboard = NSPasteboard.withUniqueName()
    defer { directPasteboard.releaseGlobally() }
    #expect(source.writeSelection(to: directPasteboard, type: type))
    if type == .string {
      #expect(directPasteboard.string(forType: .string) == "• note")
    } else {
      let directRichText = try NSAttributedString(
        data: #require(directPasteboard.data(forType: .rtf)),
        options: [.documentType: NSAttributedString.DocumentType.rtf],
        documentAttributes: nil
      )
      #expect(directRichText.string == "• note")
    }
    #expect(source.selectedRange() == NSRange(location: 2, length: 4))
  }

  let richPaste = bulletEditor("").0
  richPaste.insertPastedTextForTesting(richText, plainText: richText.string)
  #expect(richPaste.string == "• note")

  source.setSelectedRange(NSRange(location: 3, length: 2))
  let substringPasteboard = NSPasteboard.withUniqueName()
  defer { substringPasteboard.releaseGlobally() }
  #expect(source.writeSelection(to: substringPasteboard, types: source.writablePasteboardTypes))
  #expect(substringPasteboard.string(forType: .string) == "ot")
  let directSubstringPasteboard = NSPasteboard.withUniqueName()
  defer { directSubstringPasteboard.releaseGlobally() }
  #expect(source.writeSelection(to: directSubstringPasteboard, type: .string))
  #expect(directSubstringPasteboard.string(forType: .string) == "ot")
  let directRichSubstringPasteboard = NSPasteboard.withUniqueName()
  defer { directRichSubstringPasteboard.releaseGlobally() }
  #expect(source.writeSelection(to: directRichSubstringPasteboard, type: .rtf))
  let directRichSubstring = try NSAttributedString(
    data: #require(directRichSubstringPasteboard.data(forType: .rtf)),
    options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: nil
  )
  #expect(directRichSubstring.string == "ot")
  #expect(source.selectedRange() == NSRange(location: 3, length: 2))

  source.setSelectedRange(NSRange(location: 3, length: 0))
  let emptySelectionPasteboard = NSPasteboard.withUniqueName()
  defer { emptySelectionPasteboard.releaseGlobally() }
  #expect(!source.writeSelection(to: emptySelectionPasteboard, type: .string))
  #expect(emptySelectionPasteboard.string(forType: .string) == nil)
  #expect(source.selectedRange() == NSRange(location: 3, length: 0))
}

@Test @MainActor func multiSelectionClipboardPreservesWholeItemsWithoutChangingSelections() throws {
  let sourceText = "• first\n• second\n• third"
  let (source, sourceWindow) = bulletEditor(sourceText)
  #expect(sourceWindow.makeFirstResponder(source))
  let selections = [NSRange(location: 2, length: 5), NSRange(location: 10, length: 6)]
  source.textStorage?.addAttribute(
    .foregroundColor,
    value: NSColor.systemRed,
    range: NSRange(location: 0, length: 2)
  )
  source.textStorage?.addAttribute(
    .font,
    value: NSFont.systemFont(ofSize: 25),
    range: NSRange(location: 2, length: 5)
  )
  source.textStorage?.addAttribute(
    .foregroundColor,
    value: NSColor.systemGreen,
    range: NSRange(location: 8, length: 2)
  )
  source.textStorage?.addAttribute(
    .font,
    value: NSFont.systemFont(ofSize: 17),
    range: NSRange(location: 10, length: 6)
  )
  source.setSelectedRanges(
    selections.map { NSValue(range: $0) },
    affinity: .downstream,
    stillSelecting: false
  )
  let notificationObserver = SelectionChangeObserver()
  NotificationCenter.default.addObserver(
    notificationObserver,
    selector: #selector(SelectionChangeObserver.selectionDidChange(_:)),
    name: NSTextView.didChangeSelectionNotification,
    object: source
  )
  defer { NotificationCenter.default.removeObserver(notificationObserver) }
  let selectionAffinity = source.selectionAffinity
  let pasteboard = NSPasteboard.withUniqueName()
  defer { pasteboard.releaseGlobally() }

  #expect(source.writeSelection(to: pasteboard, types: source.writablePasteboardTypes))

  let copiedText = try #require(pasteboard.string(forType: .string))
  #expect(copiedText.contains("• first"))
  #expect(copiedText.contains("• second"))
  #expect(!copiedText.contains("third"))
  #expect(source.selectedRanges.map(\.rangeValue) == selections)
  #expect(source.selectionAffinity == selectionAffinity)
  #expect(notificationObserver.count == 0)

  let richData = try #require(pasteboard.data(forType: .rtf))
  let richText = try NSAttributedString(
    data: richData,
    options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: nil
  )
  let firstBodyLocation = (richText.string as NSString).range(of: "first").location
  let secondBodyLocation = (richText.string as NSString).range(of: "second").location
  #expect(firstBodyLocation != NSNotFound)
  #expect(secondBodyLocation != NSNotFound)
  if firstBodyLocation != NSNotFound {
    #expect(
      richText.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        == NSColor.systemRed
    )
    #expect(
      (richText.attribute(.font, at: firstBodyLocation, effectiveRange: nil) as? NSFont)?.pointSize
        == 25
    )
  }
  let secondMarkerLocation = (richText.string as NSString).range(of: "• second").location
  if secondMarkerLocation != NSNotFound, secondBodyLocation != NSNotFound {
    #expect(
      richText.attribute(.foregroundColor, at: secondMarkerLocation, effectiveRange: nil) as? NSColor
        == NSColor.systemGreen
    )
    #expect(
      (richText.attribute(.font, at: secondBodyLocation, effectiveRange: nil) as? NSFont)?.pointSize
        == 17
    )
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

@Test @MainActor func f63PortManagedImageInLaterSelectionCopiesReferenceOnly() throws {
  let fixture = try ManagedBulletImageFixture()
  defer { fixture.remove() }
  let reference = try fixture.makeReference()
  let canonical = "• first\n• \(reference)\n• omitted"
  let display = fixture.store.projectedContent(from: NSAttributedString(string: canonical))
  let firstSelection = (display.string as NSString).range(of: "first")
  let imageSelection = (display.string as NSString).range(of: "\u{fffc}")
  let sourceImageRange = (canonical as NSString).range(of: reference)
  #expect(
    InlineNoteImageProjection.sourceRange(forDisplayRange: imageSelection, in: display)
      == sourceImageRange
  )

  let (source, sourceWindow) = bulletEditor(display.string)
  source.inlineImageStore = fixture.store
  source.textStorage?.setAttributedString(display)
  let firstFont = NSFont.systemFont(ofSize: 25)
  let imageFont = NSFont.systemFont(ofSize: 17)
  source.textStorage?.addAttribute(.font, value: firstFont, range: firstSelection)
  source.textStorage?.addAttribute(.font, value: imageFont, range: imageSelection)
  source.textStorage?.addAttribute(
    .link,
    value: fixture.root.appendingPathComponent("metadata-only").absoluteString,
    range: imageSelection
  )
  #expect(sourceWindow.makeFirstResponder(source))
  let selections = [firstSelection, imageSelection]
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

  #expect(source.writablePasteboardTypes == [.rtf, .string])
  #expect(source.writeSelection(to: pasteboard, types: source.writablePasteboardTypes))
  let copiedText = try #require(pasteboard.string(forType: .string))
  #expect(copiedText.contains("• first"))
  #expect(copiedText.contains("• \(reference)"))
  #expect(!copiedText.contains("omitted"))
  #expect(source.string == display.string)
  #expect(source.textStorage?.isEqual(to: initialStorage) == true)
  #expect(source.selectedRanges.map(\.rangeValue) == selections)
  #expect(source.selectionAffinity == selectionAffinity)
  #expect(observer.selectionChanges == 0)
  #expect(observer.textChanges == 0)
  #expect(pasteboard.data(forType: .tiff) == nil)
  #expect(pasteboard.data(forType: .rtfd) == nil)

  let directTextPasteboard = NSPasteboard.withUniqueName()
  defer { directTextPasteboard.releaseGlobally() }
  #expect(source.writeSelection(to: directTextPasteboard, type: .string))
  #expect(directTextPasteboard.string(forType: .string) == copiedText)

  let directRTFPasteboard = NSPasteboard.withUniqueName()
  defer { directRTFPasteboard.releaseGlobally() }
  #expect(source.writeSelection(to: directRTFPasteboard, type: .rtf))
  let directRTFData = try #require(directRTFPasteboard.data(forType: .rtf))
  let directRTF = try NSAttributedString(
    data: directRTFData,
    options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: nil
  )
  let directFirst = (directRTF.string as NSString).range(of: "first").location
  let directReference = (directRTF.string as NSString).range(of: reference).location
  #expect(directRTF.string.contains("• first"))
  #expect(directRTF.string.contains("• \(reference)"))
  #expect(!directRTF.string.contains("omitted"))
  #expect(!directRTF.string.contains("\u{fffc}"))
  #expect(directFirst != NSNotFound)
  #expect(directReference != NSNotFound)
  if directFirst != NSNotFound {
    #expect(
      (directRTF.attribute(.font, at: directFirst, effectiveRange: nil) as? NSFont)?.pointSize
        == firstFont.pointSize
    )
  }
  if directReference != NSNotFound {
    #expect(
      (directRTF.attribute(.font, at: directReference, effectiveRange: nil) as? NSFont)?.pointSize
        == imageFont.pointSize
    )
  }
  var directContainsAttachment = false
  directRTF.enumerateAttribute(
    .attachment,
    in: NSRange(location: 0, length: directRTF.length)
  ) { value, _, stop in
    guard value != nil else { return }
    directContainsAttachment = true
    stop.pointee = true
  }
  #expect(!directContainsAttachment)
  directRTF.enumerateAttribute(
    .link,
    in: NSRange(location: 0, length: directRTF.length)
  ) { value, _, _ in
    #expect(value == nil)
  }
  #expect(directRTFPasteboard.data(forType: .tiff) == nil)
  #expect(directRTFPasteboard.data(forType: .rtfd) == nil)

  let blockedImagePasteboard = NSPasteboard.withUniqueName()
  defer { blockedImagePasteboard.releaseGlobally() }
  #expect(!source.writeSelection(to: blockedImagePasteboard, type: .tiff))
  #expect(blockedImagePasteboard.data(forType: .tiff) == nil)
  let blockedRTFDPasteboard = NSPasteboard.withUniqueName()
  defer { blockedRTFDPasteboard.releaseGlobally() }
  #expect(!source.writeSelection(to: blockedRTFDPasteboard, type: .rtfd))
  #expect(blockedRTFDPasteboard.data(forType: .rtfd) == nil)

  let richText = try NSAttributedString(
    data: #require(pasteboard.data(forType: .rtf)),
    options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: nil
  )
  #expect(richText.string.contains("• first"))
  #expect(richText.string.contains("• \(reference)"))
  #expect(!richText.string.contains("omitted"))
  var containsAttachment = false
  richText.enumerateAttribute(
    .attachment,
    in: NSRange(location: 0, length: richText.length)
  ) { value, _, stop in
    guard value != nil else { return }
    containsAttachment = true
    stop.pointee = true
  }
  #expect(!containsAttachment)
  richText.enumerateAttribute(
    .link,
    in: NSRange(location: 0, length: richText.length)
  ) { value, _, _ in
    #expect(value == nil)
  }
  #expect(source.textStorage?.isEqual(to: initialStorage) == true)
  #expect(source.selectedRanges.map(\.rangeValue) == selections)
  #expect(source.selectionAffinity == selectionAffinity)
  #expect(observer.selectionChanges == 0)
  #expect(observer.textChanges == 0)
}

@Test @MainActor func f63PortTextOnlyWholeBulletAfterUnselectedImageMapsClipboardOffsets() throws {
  let fixture = try ManagedBulletImageFixture()
  defer { fixture.remove() }
  let reference = try fixture.makeReference()
  let canonical = "• \(reference)\n• selected\n• omitted"
  let display = fixture.store.projectedContent(from: NSAttributedString(string: canonical))
  let unselectedImageRange = (display.string as NSString).range(of: "\u{fffc}")
  let selectedText = (display.string as NSString).range(of: "selected")
  let selectedBullet = (display.string as NSString).range(of: "• selected")
  let canonicalSelectedText = (canonical as NSString).range(of: "selected")
  let canonicalSelectedBullet = (canonical as NSString).range(of: "• selected")
  #expect(
    display.attribute(.attachment, at: unselectedImageRange.location, effectiveRange: nil)
      is InlineNoteImageAttachment
  )
  #expect(unselectedImageRange.location < selectedText.location)
  #expect(NSIntersectionRange(unselectedImageRange, selectedBullet).length == 0)
  #expect(selectedText.location != canonicalSelectedText.location)
  #expect(
    InlineNoteImageProjection.sourceRange(forDisplayRange: selectedBullet, in: display)
      == canonicalSelectedBullet
  )

  let (source, sourceWindow) = bulletEditor(display.string)
  source.inlineImageStore = fixture.store
  source.textStorage?.setAttributedString(display)
  let font = NSFont.systemFont(ofSize: 19)
  source.textStorage?.addAttributes(
    [.font: font, .foregroundColor: NSColor.systemBlue],
    range: selectedText
  )
  #expect(sourceWindow.makeFirstResponder(source))
  source.setSelectedRange(selectedText)
  let initialStorage = NSAttributedString(attributedString: try #require(source.textStorage))
  let initialText = source.string
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

  #expect(source.writeSelection(to: pasteboard, types: [.rtf, .string]))
  #expect(pasteboard.string(forType: .string) == "• selected")
  #expect(pasteboard.data(forType: .tiff) == nil)
  #expect(pasteboard.data(forType: .rtfd) == nil)
  let richText = try NSAttributedString(
    data: #require(pasteboard.data(forType: .rtf)),
    options: [.documentType: NSAttributedString.DocumentType.rtf],
    documentAttributes: nil
  )
  #expect(richText.string == "• selected")
  #expect(!richText.string.contains(reference))
  #expect(!richText.string.contains("\u{fffc}"))
  var containsAttachment = false
  richText.enumerateAttribute(
    .attachment,
    in: NSRange(location: 0, length: richText.length)
  ) { value, _, stop in
    guard value != nil else { return }
    containsAttachment = true
    stop.pointee = true
  }
  #expect(!containsAttachment)
  let copiedTextLocation = (richText.string as NSString).range(of: "selected").location
  #expect(copiedTextLocation != NSNotFound)
  if copiedTextLocation != NSNotFound {
    #expect(
      (richText.attribute(.font, at: copiedTextLocation, effectiveRange: nil) as? NSFont)?.pointSize
        == font.pointSize
    )
  }
  #expect(source.string == initialText)
  #expect(source.textStorage?.isEqual(to: initialStorage) == true)
  #expect(source.selectedRanges.map(\.rangeValue) == [selectedText])
  #expect(source.selectionAffinity == selectionAffinity)
  #expect(observer.selectionChanges == 0)
  #expect(observer.textChanges == 0)
}
