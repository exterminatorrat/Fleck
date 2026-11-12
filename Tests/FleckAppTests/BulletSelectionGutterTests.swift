import AppKit
import Testing

@testable import FleckApp

private struct GutterCase: Sendable {
  let name: String
  let text: String
  let location: Int
  let length: Int
  let markers: [Int]
  let isDark: Bool
  let drawsBackground: Bool
}

extension GutterCase: CustomTestStringConvertible {
  var testDescription: String { name }
}

private let nestedText = "• parent\n    ◦ child\n    ◦ sibling"
private let bulletColumn = "• first\n• second\n• third"

private let gutterCases: [GutterCase] = [
  GutterCase(
    name: "first-light-opaque", text: bulletColumn, location: 0, length: 8, markers: [0],
    isDark: false, drawsBackground: true
  ),
  GutterCase(
    name: "first-dark-transparent", text: bulletColumn, location: 0, length: 8, markers: [0],
    isDark: true, drawsBackground: false
  ),
  GutterCase(
    name: "middle-light-opaque", text: bulletColumn, location: 8, length: 9, markers: [8],
    isDark: false, drawsBackground: true
  ),
  GutterCase(
    name: "nested-multiline-light-opaque", text: nestedText, location: 0,
    length: nestedText.utf16.count, markers: [0, 13, 25], isDark: false, drawsBackground: true
  ),
  GutterCase(
    name: "nested-multiline-dark-transparent", text: nestedText, location: 0,
    length: nestedText.utf16.count, markers: [0, 13, 25], isDark: true, drawsBackground: false
  ),
]

@MainActor
private struct GutterFixture {
  let textView: ListAwareTextView
  let host: NSView
  let window: NSWindow
}

@MainActor
private struct GutterRender {
  let reference: NSBitmapImageRep
  let selected: NSBitmapImageRep
  let scale: CGFloat
}

@MainActor
private func gutterFixture(
  _ text: String,
  isDark: Bool,
  drawsBackground: Bool
) -> GutterFixture {
  let frame = NSRect(x: 0, y: 0, width: 420, height: 240)
  let textView = ListAwareTextView(frame: frame)
  textView.reduceMotion = true
  textView.textContainerInset = NSSize(width: 16, height: 10)
  textView.textContainer?.lineFragmentPadding = 0
  var attributes = EditorTypography.defaultAttributes(family: ".AppleSystemUIFont", size: 17)
  let paragraphStyle = (attributes[.paragraphStyle] as? NSParagraphStyle ?? .default)
    .mutableCopy() as! NSMutableParagraphStyle
  paragraphStyle.paragraphSpacingBefore = 12
  paragraphStyle.paragraphSpacing = 8
  attributes[.paragraphStyle] = paragraphStyle
  attributes[.foregroundColor] = isDark ? NSColor.white : NSColor.black
  textView.textStorage?.setAttributedString(
    NSAttributedString(string: text, attributes: attributes)
  )
  textView.typingAttributes = attributes
  textView.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
  textView.drawsBackground = drawsBackground
  textView.backgroundColor = isDark ? .black : .white
  textView.textColor = isDark ? .white : .black

  let host = NSView(frame: frame)
  host.wantsLayer = true
  host.layer?.backgroundColor = (isDark ? NSColor.black : NSColor.white).cgColor
  textView.removeFromSuperview()
  textView.frame = host.bounds
  textView.autoresizingMask = [.width, .height]
  host.addSubview(textView)

  let window = NSWindow(
    contentRect: frame,
    styleMask: [.titled],
    backing: .buffered,
    defer: false
  )
  window.contentView = host
  _ = window.makeFirstResponder(textView)
  if let container = textView.textContainer {
    textView.layoutManager?.ensureLayout(for: container)
  }
  return GutterFixture(textView: textView, host: host, window: window)
}

@MainActor
private func renderSelection(
  _ fixture: GutterFixture,
  selection: NSRange
) throws -> GutterRender {
  let reference = try #require(
    fixture.host.bitmapImageRepForCachingDisplay(in: fixture.host.bounds)
  )
  fixture.host.cacheDisplay(in: fixture.host.bounds, to: reference)
  fixture.textView.setSelectedRange(selection)
  fixture.textView.displayIfNeeded()
  fixture.window.displayIfNeeded()
  let selected = try #require(
    fixture.host.bitmapImageRepForCachingDisplay(in: fixture.host.bounds)
  )
  fixture.host.cacheDisplay(in: fixture.host.bounds, to: selected)
  return GutterRender(
    reference: reference,
    selected: selected,
    scale: CGFloat(reference.pixelsWide) / fixture.host.bounds.width
  )
}

@MainActor
private func bitmapPixel(
  _ bitmap: NSBitmapImageRep,
  textViewPoint point: NSPoint,
  fixture: GutterFixture,
  scale: CGFloat
) -> NSColor? {
  let hostPoint = fixture.host.convert(point, from: fixture.textView)
  let distanceFromTop = fixture.host.isFlipped ? hostPoint.y : fixture.host.bounds.maxY - hostPoint.y
  let column = Int((hostPoint.x * scale).rounded(.down))
  let row = Int((distanceFromTop * scale).rounded(.down))
  guard column >= 0, column < bitmap.pixelsWide, row >= 0, row < bitmap.pixelsHigh else {
    return nil
  }
  return bitmap.colorAt(x: column, y: row)?.usingColorSpace(.sRGB)
}

private func sameColor(_ first: NSColor, _ second: NSColor) -> Bool {
  abs(first.redComponent - second.redComponent) <= 0.02
    && abs(first.greenComponent - second.greenComponent) <= 0.02
    && abs(first.blueComponent - second.blueComponent) <= 0.02
    && abs(first.alphaComponent - second.alphaComponent) <= 0.02
}

@MainActor
private func changedPixelCount(
  in region: NSRect,
  fixture: GutterFixture,
  render: GutterRender
) -> Int {
  var count = 0
  for x in stride(from: region.minX, through: region.maxX, by: 0.5) {
    for y in stride(from: region.minY, through: region.maxY, by: 0.5) {
      let point = NSPoint(x: x, y: y)
      guard
        let before = bitmapPixel(render.reference, textViewPoint: point, fixture: fixture, scale: render.scale),
        let after = bitmapPixel(render.selected, textViewPoint: point, fixture: fixture, scale: render.scale)
      else { continue }
      if !sameColor(before, after) { count += 1 }
    }
  }
  return count
}

@MainActor
private func bulletGutterGeometry(
  _ fixture: GutterFixture,
  marker: Int
) throws -> (prefix: NSRect, line: NSRect) {
  let layoutManager = try #require(fixture.textView.layoutManager)
  let container = try #require(fixture.textView.textContainer)
  layoutManager.ensureLayout(for: container)
  let glyphs = layoutManager.glyphRange(
    forCharacterRange: NSRange(location: marker, length: 2),
    actualCharacterRange: nil
  )
  let origin = fixture.textView.textContainerOrigin
  return (
    layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
      .offsetBy(dx: origin.x, dy: origin.y),
    layoutManager.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
      .offsetBy(dx: origin.x, dy: origin.y)
  )
}

@MainActor
private func expectCleanGutter(
  _ fixture: GutterFixture,
  marker: Int,
  render: GutterRender
) throws {
  let geometry = try bulletGutterGeometry(fixture, marker: marker)
  #expect(geometry.prefix.width > 8)
  let bands = [
    NSRect(
      x: geometry.prefix.minX + 0.5,
      y: geometry.line.minY + 1,
      width: geometry.prefix.width - 1.5,
      height: max(0, geometry.prefix.minY - geometry.line.minY - 2)
    ),
    NSRect(
      x: geometry.prefix.minX + 0.5,
      y: geometry.prefix.maxY + 1,
      width: geometry.prefix.width - 1.5,
      height: max(0, geometry.line.maxY - geometry.prefix.maxY - 2)
    ),
  ]
  #expect(bands[0].height + bands[1].height > 3)
  for band in bands where band.height > 0 {
    #expect(changedPixelCount(in: band, fixture: fixture, render: render) == 0)
  }
}

@MainActor
private func expectSelectedBody(
  _ fixture: GutterFixture,
  marker: Int,
  render: GutterRender
) throws {
  let geometry = try bulletGutterGeometry(fixture, marker: marker)
  let body = NSRect(
    x: geometry.prefix.maxX + 4,
    y: geometry.prefix.minY + 2,
    width: geometry.line.maxX - geometry.prefix.maxX - 12,
    height: geometry.prefix.height - 4
  )
  #expect(changedPixelCount(in: body, fixture: fixture, render: render) > 20)
}

@MainActor
private func writeGutterEvidence(_ render: GutterRender, name: String) throws {
  guard let directory = ProcessInfo.processInfo.environment["FLECK_EDITOR_EVIDENCE_DIR"] else {
    return
  }
  try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
  let png = try #require(render.selected.representation(using: .png, properties: [:]))
  try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
}

@Suite("BulletSelectionGutterTests")
@MainActor
struct BulletSelectionGutterTests {
  @Test(arguments: gutterCases)
  fileprivate func selectedGutterStaysUnhighlightedAtEveryMarker(_ item: GutterCase) throws {
    let fixture = gutterFixture(
      item.text,
      isDark: item.isDark,
      drawsBackground: item.drawsBackground
    )
    defer { fixture.window.contentView = nil }

    let render = try renderSelection(
      fixture,
      selection: NSRange(location: item.location, length: item.length)
    )
    try writeGutterEvidence(render, name: "bullet-gutter-\(item.name)")

    for marker in item.markers {
      try expectCleanGutter(fixture, marker: marker, render: render)
    }
    try expectSelectedBody(fixture, marker: item.markers[0], render: render)
  }
}
