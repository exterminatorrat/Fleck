#if os(macOS)
import AppKit
import Testing

@testable import FleckApp

@Suite("InlineImageTransformPersistence", .serialized)
@MainActor
struct InlineImageTransformPersistenceTests {
  @Test func plainReferenceRoundTripsExactBytes() throws {
    let source = "![Grüße — 日本語](file:///tmp/0B5F6A2E-1F0B-4A3C-9D16-6E2B7C8D9E0F.png)"
    let reference = try #require(InlineNoteImageReference.parse(source))

    #expect(reference.text.utf8.elementsEqual(source.utf8))
    #expect(reference.transform == nil)
    #expect(reference.titleText == nil)
    #expect(reference.altText == "Grüße — 日本語")
    #expect(reference.urlText == "file:///tmp/0B5F6A2E-1F0B-4A3C-9D16-6E2B7C8D9E0F.png")
  }

  @Test func exactSourceBytesSurviveParsingOfAnExistingTitle() throws {
    let sources = [
      "![Image](file:///tmp/x.png \"fleck:200x150@30\")",
      "![Bild ✓](file:///tmp/x.png \"fleck:200.50x150@030\")",
      "![Image](file:///tmp/x.png \"fleck:12.25x7.5@359.99\")",
    ]
    for source in sources {
      let reference = try #require(InlineNoteImageReference.parse(source))
      #expect(reference.text.utf8.elementsEqual(source.utf8))
      let title = try #require(reference.titleText)
      let titleIsASCII = title.unicodeScalars.allSatisfy { $0.isASCII }
      #expect(titleIsASCII)
    }
  }

  @Test func transformTitleSerializesDeterministicASCIINumbers() throws {
    let reference = try #require(
      InlineNoteImageReference.parse("![Photo](file:///tmp/x.png)")
    )

    let whole = try #require(
      reference.replacingTransform(
        InlineImageTransform(size: CGSize(width: 200, height: 150), rotationDegrees: 30)
      )
    )
    #expect(whole.text == "![Photo](file:///tmp/x.png \"fleck:200x150@30\")")
    #expect(
      whole.transform
        == InlineImageTransform(size: CGSize(width: 200, height: 150), rotationDegrees: 30)
    )

    let fractional = try #require(
      reference.replacingTransform(
        InlineImageTransform(size: CGSize(width: 200, height: 150.5), rotationDegrees: 30.25)
      )
    )
    #expect(fractional.text == "![Photo](file:///tmp/x.png \"fleck:200x150.5@30.25\")")
    #expect(
      fractional.transform
        == InlineImageTransform(size: CGSize(width: 200, height: 150.5), rotationDegrees: 30.25)
    )

    let wrapped = try #require(
      reference.replacingTransform(
        InlineImageTransform(size: CGSize(width: 44, height: 24), rotationDegrees: 390)
      )
    )
    #expect(wrapped.text == "![Photo](file:///tmp/x.png \"fleck:44x24@30\")")

    let restored = try #require(InlineNoteImageReference.parse(fractional.text))
    #expect(restored.text.utf8.elementsEqual(fractional.text.utf8))
    #expect(restored.titleText == "fleck:200x150.5@30.25")
  }

  @Test func transformSurvivesRTFAndReprojectsWithUnicodeAttributes() throws {
    let fixture = try PersistenceImageFixture()
    defer { fixture.remove() }
    let reference = try fixture.reference(width: 640, height: 480)
    let plain = try #require(InlineNoteImageReference.parse(reference))
    let titled = try #require(
      plain.replacingTransform(
        InlineImageTransform(size: CGSize(width: 260, height: 130), rotationDegrees: 45.5)
      )
    )
    let source = "Body ✓\n\(titled.text)\nAfter — 日本語"
    let attributed = NSAttributedString(
      string: source,
      attributes: [
        .font: NSFont.systemFont(ofSize: 15),
        .foregroundColor: NSColor(calibratedRed: 0.9, green: 0.1, blue: 0.1, alpha: 1),
      ]
    )
    let rtf = try attributed.data(
      from: NSRange(location: 0, length: attributed.length),
      documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
    )
    let decoded = try NSAttributedString(
      data: rtf,
      options: [.documentType: NSAttributedString.DocumentType.rtf],
      documentAttributes: nil
    )
    #expect(decoded.string.utf8.elementsEqual(source.utf8))

    let projected = fixture.store.projectedContent(from: decoded)
    #expect(projected.string == "Body ✓\n\u{fffc}\nAfter — 日本語")
    let attachment = try #require(
      projected.attribute(.attachment, at: 7, effectiveRange: nil) as? InlineNoteImageAttachment
    )
    let expected = InlineImageTransform(
      size: CGSize(width: 260, height: 130),
      rotationDegrees: 45.5
    )
    #expect(attachment.displayTransform == expected)
    #expect(attachment.sourceReference.utf8.elementsEqual(titled.text.utf8))
    #expect(attachment.originalPixelSize == NSSize(width: 640, height: 480))

    let font = try #require(
      projected.attribute(.font, at: 7, effectiveRange: nil) as? NSFont
    )
    #expect(font.pointSize == 15)
    let expectedColor = NSColor(
      calibratedRed: 0.9,
      green: 0.1,
      blue: 0.1,
      alpha: 1
    ).usingColorSpace(.sRGB)
    let color = try #require(
      projected.attribute(.foregroundColor, at: 7, effectiveRange: nil) as? NSColor
    ).usingColorSpace(.sRGB)
    #expect(abs((color?.redComponent ?? 0) - (expectedColor?.redComponent ?? 1)) < 0.05)
    #expect(abs((color?.greenComponent ?? 1) - (expectedColor?.greenComponent ?? 0)) < 0.05)

    let expanded = InlineNoteImageProjection.expanded(projected)
    #expect(expanded.string.utf8.elementsEqual(source.utf8))
  }

  @Test func plainReferenceKeepsLegacyAutoFitSizing() throws {
    let fixture = try PersistenceImageFixture()
    defer { fixture.remove() }
    let attachment = try fixture.attachment(width: 640, height: 480)

    #expect(attachment.displayTransform == nil)
    #expect(attachment.image === attachment.originalImage)
    #expect(bounds(of: attachment, availableWidth: 1_000) == NSSize(width: 426, height: 320))
    #expect(bounds(of: attachment, availableWidth: 200) == NSSize(width: 200, height: 150))
    #expect(bounds(of: attachment, availableWidth: 10_000) == NSSize(width: 426, height: 320))

    let effective = attachment.effectiveTransform(
      fitting: NSRect(x: 0, y: 0, width: 426, height: 320)
    )
    #expect(effective == InlineImageTransform(size: CGSize(width: 426, height: 320)))
  }

  @Test func explicitTransformStretchesSidesAndClampsToRotatedViewport() throws {
    let fixture = try PersistenceImageFixture()
    defer { fixture.remove() }
    let plain = try fixture.attachment(width: 640, height: 480)
    let stretched = try #require(
      plain.replacingTransform(
        InlineImageTransform(size: CGSize(width: 400, height: 100), rotationDegrees: 0)
      )
    )
    #expect(bounds(of: stretched, availableWidth: 1_000) == NSSize(width: 400, height: 100))

    let rotated = try #require(
      plain.replacingTransform(
        InlineImageTransform(size: CGSize(width: 400, height: 100), rotationDegrees: 90)
      )
    )
    let envelope = InlineImageTransform(
      size: CGSize(width: 400, height: 100),
      rotationDegrees: 90
    ).rotatedSize
    #expect(envelope == CGSize(width: 100, height: 400))

    let wide = bounds(of: rotated, availableWidth: 1_000)
    #expect(close(wide, NSSize(width: 100, height: 400)))
    #expect(wide.width <= 1_000)

    let narrow = bounds(of: rotated, availableWidth: 60)
    #expect(close(narrow, NSSize(width: 60, height: 240)))
    #expect(narrow.width <= 60)

    let effective = rotated.effectiveTransform(
      fitting: NSRect(x: 0, y: 0, width: narrow.width, height: narrow.height)
    )
    #expect(effective.rotationDegrees == 90)
    #expect(close(effective.rotatedSize, narrow))
    #expect(effective.rotatedSize.height <= narrow.height + 0.01)
  }

  @Test func invalidOrForeignTitlesStayTextWithoutAllocation() throws {
    let fixture = try PersistenceImageFixture()
    defer { fixture.remove() }
    let url = try fixture.imageURLString(width: 40, height: 30)
    let titles = [
      "fleck:0x150@30",
      "fleck:200x0@30",
      "fleck:200x150@",
      "fleck:200x150@abc",
      "fleck:200x150@-30",
      "fleck:200x150@360",
      "fleck:200000x150@0",
      "fleck:200000x200000@0",
      "fleck:1e3x150@0",
      "fleck:200 x150@0",
      "fleck:200x150@30x",
      "fleck:200x150",
      "caption",
      "",
    ]
    for title in titles {
      let source = "![Image](\(url) \"\(title)\")"
      #expect(InlineNoteImageReference.parse(source) == nil)
      #expect(InlineNoteImageStore.referenceRanges(in: source).isEmpty)
      let projected = fixture.store.projectedContent(from: NSAttributedString(string: source))
      #expect(projected.string.utf8.elementsEqual(source.utf8))
    }

    let malformedPlain = [
      "![Image](fleck:200x150@30)",
      "![Image](file:///tmp/\(UUID().uuidString).png \"fleck:200x150@30\")",
    ]
    for source in malformedPlain {
      let projected = fixture.store.projectedContent(from: NSAttributedString(string: source))
      #expect(projected.string.utf8.elementsEqual(source.utf8))
    }

    let bounded = try fixture.attachment(
      width: 40,
      height: 30,
      transform: InlineImageTransform(size: CGSize(width: 20_000, height: 20_000))
    )
    #expect(close(bounds(of: bounded, availableWidth: 100), NSSize(width: 100, height: 100)))
    let effective = bounded.effectiveTransform(
      fitting: NSRect(x: 0, y: 0, width: 100, height: 100)
    )
    #expect(effective.rotatedSize.width <= 100.01)
    #expect(effective.rotatedSize.height <= 100.01)
  }

  @Test func replacingTransformSharesTheOriginalImageWithoutMutation() throws {
    let fixture = try PersistenceImageFixture()
    defer { fixture.remove() }
    let plainReference = try fixture.reference(width: 80, height: 60)
    let first = try fixture.attachment(reference: plainReference)
    let shared = first.originalImage
    let second = InlineNoteImageAttachment(
      sourceReference: first.sourceReference,
      image: shared,
      originalPixelSize: first.originalPixelSize,
      accessibilityLabel: "Image file shared.png"
    )
    let originalBytes = plainReference

    let replaced = try #require(
      first.replacingTransform(
        InlineImageTransform(size: CGSize(width: 120, height: 80), rotationDegrees: 15)
      )
    )

    #expect(first.sourceReference.utf8.elementsEqual(originalBytes.utf8))
    #expect(first.displayTransform == nil)
    #expect(first.image === shared)
    #expect(first.image?.size == NSSize(width: 80, height: 60))

    #expect(second.sourceReference.utf8.elementsEqual(originalBytes.utf8))
    #expect(second.displayTransform == nil)
    #expect(second.image === shared)
    #expect(second.originalImage === shared)

    #expect(replaced !== first)
    #expect(replaced !== second)
    #expect(replaced.originalImage === shared)
    #expect(replaced.image !== shared)
    let replacedEnvelope = InlineImageTransform(
      size: CGSize(width: 120, height: 80),
      rotationDegrees: 15
    ).rotatedSize
    #expect(replaced.image?.size == replacedEnvelope)
    #expect(replaced.originalPixelSize == first.originalPixelSize)
    #expect(
      replaced.displayTransform
        == InlineImageTransform(size: CGSize(width: 120, height: 80), rotationDegrees: 15)
    )
    let plainURL = try fixture.urlString(from: plainReference)
    #expect(replaced.sourceReference.hasSuffix("\"fleck:120x80@15\")"))
    #expect(replaced.sourceReference.hasPrefix("![Image](\(plainURL)"))

    let restored = try #require(replaced.replacingTransform(nil))
    #expect(restored.sourceReference.utf8.elementsEqual(originalBytes.utf8))
    #expect(restored.displayTransform == nil)
    #expect(restored.image === shared)
  }

  @Test func clockwiseRotationPutsTheOriginalLeftHalfAboveTheRightHalf() throws {
    let fixture = try PersistenceImageFixture()
    defer { fixture.remove() }
    let plain = try fixture.attachment(width: 80, height: 40)
    let rotated = try #require(plain.replacingTransform(
      InlineImageTransform(size: CGSize(width: 80, height: 40), rotationDegrees: 90)
    ))
    let data = try #require(rotated.image?.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: data))
    let top = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 4))
      .usingColorSpace(.sRGB)
    let bottom = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh * 3 / 4))
      .usingColorSpace(.sRGB)
    let topColor = try #require(top)
    let bottomColor = try #require(bottom)
    #expect(topColor.redComponent > topColor.blueComponent)
    #expect(bottomColor.blueComponent > bottomColor.redComponent)
  }

  @Test func transformedAttachmentKeepsOriginalAndReservesRotatedSpace() throws {
    let fixture = try PersistenceImageFixture()
    defer { fixture.remove() }
    let plain = try fixture.attachment(width: 640, height: 480)
    let original = plain.originalImage
    let rotation = InlineImageTransform(
      size: CGSize(width: 400, height: 100),
      rotationDegrees: 90
    )
    let rotated = try #require(plain.replacingTransform(rotation))

    #expect(rotated.originalImage === original)
    #expect(original.size == NSSize(width: 640, height: 480))
    #expect(rotated.image !== original)
    #expect(rotated.image?.size == CGSize(width: 100, height: 400))
    #expect(rotated.displayTransform == rotation)

    let layoutView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    let container = try #require(layoutView.textContainer)
    let layoutManager = try #require(layoutView.layoutManager)
    container.lineFragmentPadding = 0
    container.containerSize = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
    container.widthTracksTextView = false
    let storage = NSMutableAttributedString(string: "Before\n")
    storage.append(
      NSAttributedString(
        string: "\u{fffc}",
        attributes: [.attachment: rotated, .font: NSFont.systemFont(ofSize: 15)]
      )
    )
    storage.append(NSAttributedString(string: "\nAfter"))
    layoutView.textStorage?.setAttributedString(storage)
    layoutManager.ensureLayout(for: container)

    let attachmentGlyph = layoutManager.glyphIndexForCharacter(at: 7)
    let attachmentLine = layoutManager.lineFragmentRect(
      forGlyphAt: attachmentGlyph,
      effectiveRange: nil
    )
    let attachmentRect = layoutManager.boundingRect(
      forGlyphRange: NSRange(location: attachmentGlyph, length: 1),
      in: container
    )
    let followingLine = layoutManager.lineFragmentRect(
      forGlyphAt: layoutManager.glyphIndexForCharacter(at: 9),
      effectiveRange: nil
    )
    #expect(abs(attachmentLine.height - 400) < 1)
    #expect(abs(attachmentRect.width - 100) < 1)
    #expect(attachmentRect.height <= attachmentLine.height + 0.5)
    #expect(followingLine.minY >= attachmentLine.maxY - 0.5)

    let rendered = InlineNoteImageAttachment.renderedImage(
      original: original,
      transform: rotation
    )
    #expect(rendered !== original)
    #expect(rendered.size == CGSize(width: 100, height: 400))
    #expect(original.size == NSSize(width: 640, height: 480))
    #expect(
      InlineNoteImageAttachment.renderedImage(original: original, transform: nil) === original
    )

    let capped = InlineNoteImageAttachment.renderedImage(
      original: original,
      transform: InlineImageTransform(size: CGSize(width: 6_000, height: 4_000))
    )
    let cappedData = try #require(capped.tiffRepresentation)
    let cappedBitmap = try #require(NSBitmapImageRep(data: cappedData))
    let longEdge = CGFloat(max(cappedBitmap.pixelsWide, cappedBitmap.pixelsHigh))
    #expect(longEdge <= InlineNoteImageAttachment.maximumRenderedEdge)
    #expect(longEdge > 2_000)
    #expect(original.size == NSSize(width: 640, height: 480))
  }

  @Test func transformedRasterKeepsRetinaPixelsSeparateFromLogicalSize() throws {
    let fixture = try PersistenceImageFixture()
    defer { fixture.remove() }
    let plain = try fixture.attachment(width: 800, height: 400)
    let rendered = InlineNoteImageAttachment.renderedImage(
      original: plain.originalImage,
      transform: InlineImageTransform(size: CGSize(width: 400, height: 200))
    )
    #expect(rendered.size == CGSize(width: 400, height: 200))
    let data = try #require(rendered.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: data))
    #expect(bitmap.pixelsWide == 800)
    #expect(bitmap.pixelsHigh == 400)
  }

  @Test func replacementRejectsUnpersistableTransformsAndKeepsRoundedValues() throws {
    let fixture = try PersistenceImageFixture()
    defer { fixture.remove() }
    let plain = try fixture.attachment(width: 120, height: 90)

    #expect(plain.replacingTransform(InlineImageTransform(size: .zero)) == nil)
    #expect(
      plain.replacingTransform(InlineImageTransform(size: CGSize(width: 30_000, height: 100)))
        == nil
    )
    #expect(
      plain.replacingTransform(
        InlineImageTransform(size: CGSize(width: CGFloat.infinity, height: 100))
      ) == nil
    )
    #expect(plain.replacingTransform(nil) != nil)

    let rounded = try #require(
      plain.replacingTransform(
        InlineImageTransform(
          size: CGSize(width: 120.6789, height: 80.1234),
          rotationDegrees: 15.9876
        )
      )
    )
    let title = try #require(
      InlineNoteImageReference.parse(rounded.sourceReference)?.titleText
    )
    #expect(title == "fleck:120.68x80.12@15.99")
    #expect(rounded.displayTransform == InlineNoteImageReference.transform(fromTitle: title))
    #expect(rounded.sourceReference.hasSuffix("\"\(title)\")"))
    #expect(rounded.originalImage === plain.originalImage)
  }
}

@MainActor
private struct PersistenceImageFixture {
  let root: URL
  let store: InlineNoteImageStore

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("FleckImagePersist-\(UUID().uuidString)", isDirectory: true)
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
        let color = x < width / 2
          ? NSColor(calibratedRed: 0.85, green: 0.15, blue: 0.10, alpha: 1)
          : NSColor(calibratedRed: 0.12, green: 0.30, blue: 0.85, alpha: 1)
        bitmap.setColor(color, atX: x, y: y)
      }
    }
    let url = root.appendingPathComponent(name)
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
    return url
  }

  func reference(width: Int, height: Int) throws -> String {
    try store.importImage(
      at: makeImage(
        name: "fixture-\(width)x\(height)-\(UUID().uuidString).png",
        width: width,
        height: height
      )
    ).reference
  }

  func imageURLString(width: Int, height: Int) throws -> String {
    let reference = try reference(width: width, height: height)
    return try urlString(from: reference)
  }

  func urlString(from reference: String) throws -> String {
    try #require(InlineNoteImageReference.parse(reference)).urlText
  }

  func attachment(reference: String) throws -> InlineNoteImageAttachment {
    let projected = store.projectedContent(from: NSAttributedString(string: reference))
    return try #require(
      projected.attribute(.attachment, at: 0, effectiveRange: nil)
        as? InlineNoteImageAttachment
    )
  }

  func attachment(width: Int, height: Int) throws -> InlineNoteImageAttachment {
    try attachment(reference: reference(width: width, height: height))
  }

  func attachment(
    width: Int,
    height: Int,
    transform: InlineImageTransform?
  ) throws -> InlineNoteImageAttachment {
    let plain = try attachment(width: width, height: height)
    return try #require(plain.replacingTransform(transform))
  }
}

@MainActor
private func bounds(of attachment: InlineNoteImageAttachment, availableWidth: CGFloat) -> NSSize {
  attachment.attachmentBounds(
    for: nil,
    proposedLineFragment: NSRect(x: 0, y: 0, width: availableWidth, height: 20),
    glyphPosition: .zero,
    characterIndex: 0
  ).size
}

private func close(_ size: CGSize, _ expected: CGSize, tolerance: CGFloat = 0.01) -> Bool {
  abs(size.width - expected.width) <= tolerance && abs(size.height - expected.height) <= tolerance
}

#endif
