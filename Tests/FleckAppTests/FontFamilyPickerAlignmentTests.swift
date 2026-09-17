import AppKit
import Testing
@testable import FleckApp

private let fontPickerAlignmentFamilies = [
  "Academy Engraved LET",
  "Al Bayan",
  "Al Nile",
  "Al Tarikh",
  "American Typewriter",
  "Webdings",
  "Wingdings 2",
  "Wingdings 3",
  "Zapfino",
]

@Test @MainActor func fontPickerAlignmentKeepsNamesAndPreviewsOnSharedBaselines() throws {
  let (_, picker) = fontPickerAlignmentHost(width: 280)
  var nameBaselines: [CGFloat] = []

  for family in fontPickerAlignmentFamilies {
    let metrics = try fontPickerAlignmentMetrics(for: family, picker: picker)
    #expect(abs(metrics.nameBaseline - metrics.sampleBaseline) < 0.5)
    nameBaselines.append(metrics.nameBaseline)
  }

  let first = try #require(nameBaselines.first)
  #expect(nameBaselines.allSatisfy { abs($0 - first) < 0.5 })
}

@Test @MainActor func fontPickerAlignmentReservesStablePreviewColumnAtNarrowWidths() throws {
  for width in [CGFloat(220), 280] {
    let (_, picker) = fontPickerAlignmentHost(width: width)
    var sampleFrames: [NSRect] = []

    for family in fontPickerAlignmentFamilies {
      let metrics = try fontPickerAlignmentMetrics(for: family, picker: picker)
      sampleFrames.append(metrics.sampleFrame)
      #expect(metrics.nameFrame.maxX <= metrics.sampleFrame.minX + 0.5)
      #expect(metrics.sampleFrame.width + 0.5 >= metrics.sampleIntrinsicWidth)
      #expect(metrics.cellWidth - metrics.sampleFrame.maxX >= 20)
      #expect(metrics.sampleFrame.maxX <= metrics.cellWidth)
    }

    let first = try #require(sampleFrames.first)
    #expect(sampleFrames.allSatisfy { abs($0.minX - first.minX) < 0.5 })
    #expect(sampleFrames.allSatisfy { abs($0.width - first.width) < 0.5 })
  }
}

@Test @MainActor func fontPickerAlignmentPreservesZapfinoRenderedInk() throws {
  let (_, picker) = fontPickerAlignmentHost(width: 220)
  picker.searchField.stringValue = "Zapfino"
  picker.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
  picker.view.layoutSubtreeIfNeeded()
  let table = try #require(fontPickerAlignmentDescendant(in: picker.view, as: NSTableView.self))
  let cell = try #require(fontPickerAlignmentCell(named: "Zapfino", in: table))
  cell.layoutSubtreeIfNeeded()
  let sample = try #require(
    fontPickerAlignmentDescendants(in: cell, as: NSTextField.self)
      .first(where: { $0.stringValue == "Aa" })
  )
  let width = try #require(sample.constraints.first(where: {
    $0.firstAttribute == .width && $0.secondItem == nil
  }))
  let trailing = try #require(cell.constraints.first(where: {
    ($0.firstItem as? NSView) === sample && $0.firstAttribute == .trailing
  }))
  let originalWidth = width.constant
  let originalTrailing = trailing.constant
  let originalFrame = cell.convert(sample.bounds, from: sample)
  let originalBaseline = fontPickerAlignmentBaseline(of: sample, in: cell)
  let actual = try fontPickerAlignmentBitmap(of: sample)

  width.constant = 80
  trailing.constant += 80 - originalWidth
  cell.layoutSubtreeIfNeeded()
  defer {
    width.constant = originalWidth
    trailing.constant = originalTrailing
    cell.layoutSubtreeIfNeeded()
  }
  let referenceFrame = cell.convert(sample.bounds, from: sample)
  let referenceBaseline = fontPickerAlignmentBaseline(of: sample, in: cell)
  let reference = try fontPickerAlignmentBitmap(of: sample)

  #expect(abs(referenceFrame.minX - originalFrame.minX) < 0.5)
  #expect(abs(referenceBaseline - originalBaseline) < 0.5)
  #expect(fontPickerAlignmentInkPixelCount(actual) > 0)
  #expect(fontPickerAlignmentInkPixelCount(actual) == fontPickerAlignmentInkPixelCount(reference))

  let evidence = try fontPickerAlignmentEvidenceDirectory()
  try fontPickerAlignmentZoomedPNG(actual).write(
    to: evidence.appendingPathComponent("font-picker-alignment-Zapfino-closeup.png")
  )
}

@Test @MainActor func fontPickerAlignmentHostedVisualEvidence() throws {
  let evidence = try fontPickerAlignmentEvidenceDirectory()
  for appearance in [NSAppearance.Name.aqua, .darkAqua] {
    for width in [CGFloat(220), 280] {
      let (window, picker) = fontPickerAlignmentHost(width: width, appearance: appearance)
      let table = try #require(fontPickerAlignmentDescendant(in: picker.view, as: NSTableView.self))
      let scroll = try #require(table.enclosingScrollView)
      scroll.contentView.scroll(to: .zero)
      scroll.reflectScrolledClipView(scroll.contentView)
      table.layoutSubtreeIfNeeded()
      for family in fontPickerAlignmentFamilies {
        #expect(fontPickerAlignmentCell(named: family, in: table) != nil)
      }
      let data = try fontPickerAlignmentPNG(of: picker.view, appearance: window.appearance)
      try data.write(to: evidence.appendingPathComponent(
        "font-picker-alignment-\(appearance.rawValue)-\(Int(width)).png"
      ))
    }
  }
}

private struct FontPickerAlignmentMetrics {
  let nameBaseline: CGFloat
  let sampleBaseline: CGFloat
  let nameFrame: NSRect
  let sampleFrame: NSRect
  let sampleIntrinsicWidth: CGFloat
  let cellWidth: CGFloat
}

@MainActor
private func fontPickerAlignmentMetrics(
  for family: String,
  picker: FontFamilyPickerController
) throws -> FontPickerAlignmentMetrics {
  picker.searchField.stringValue = family
  picker.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
  picker.view.layoutSubtreeIfNeeded()
  let table = try #require(fontPickerAlignmentDescendant(in: picker.view, as: NSTableView.self))
  table.layoutSubtreeIfNeeded()
  let cell = try #require(fontPickerAlignmentCell(named: family, in: table))
  cell.layoutSubtreeIfNeeded()
  let fields = fontPickerAlignmentDescendants(in: cell, as: NSTextField.self)
  let name = try #require(fields.first(where: { $0.stringValue == family }))
  let sample = try #require(fields.first(where: { $0.stringValue == "Aa" }))
  return FontPickerAlignmentMetrics(
    nameBaseline: fontPickerAlignmentBaseline(of: name, in: cell),
    sampleBaseline: fontPickerAlignmentBaseline(of: sample, in: cell),
    nameFrame: cell.convert(name.bounds, from: name),
    sampleFrame: cell.convert(sample.bounds, from: sample),
    sampleIntrinsicWidth: sample.intrinsicContentSize.width,
    cellWidth: cell.bounds.width
  )
}

@MainActor
private func fontPickerAlignmentCell(named family: String, in table: NSTableView) -> NSView? {
  for row in 0..<table.numberOfRows {
    guard let cell = table.view(atColumn: 0, row: row, makeIfNecessary: true) else { continue }
    if fontPickerAlignmentDescendants(in: cell, as: NSTextField.self).contains(where: { $0.stringValue == family }) {
      return cell
    }
  }
  return nil
}

@MainActor
private func fontPickerAlignmentBaseline(of field: NSTextField, in cell: NSView) -> CGFloat {
  let localY = field.isFlipped
    ? field.bounds.minY + field.firstBaselineOffsetFromTop
    : field.bounds.maxY - field.firstBaselineOffsetFromTop
  return cell.convert(NSPoint(x: field.bounds.minX, y: localY), from: field).y
}

@MainActor
private func fontPickerAlignmentHost(
  width: CGFloat,
  appearance: NSAppearance.Name = .aqua
) -> (NSWindow, FontFamilyPickerController) {
  let picker = FontFamilyPickerController(
    currentFamily: ".AppleSystemUIFont",
    isMixed: false,
    targetLabel: "Selected text",
    onCommit: { _ in },
    onCancel: {}
  )
  picker.loadViewIfNeeded()
  picker.preferredContentSize = NSSize(width: width, height: 320)
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: width, height: 320),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
  )
  window.appearance = NSAppearance(named: appearance)
  let host = NSView(frame: window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: width, height: 320))
  window.contentView = host
  window.setContentSize(NSSize(width: width, height: 320))
  picker.view.translatesAutoresizingMaskIntoConstraints = false
  host.addSubview(picker.view)
  NSLayoutConstraint.activate([
    picker.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
    picker.view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
    picker.view.topAnchor.constraint(equalTo: host.topAnchor),
    picker.view.bottomAnchor.constraint(equalTo: host.bottomAnchor),
  ])
  host.layoutSubtreeIfNeeded()
  return (window, picker)
}

@MainActor
private func fontPickerAlignmentDescendant<T: NSView>(in view: NSView, as type: T.Type) -> T? {
  if let match = view as? T { return match }
  for child in view.subviews {
    if let match = fontPickerAlignmentDescendant(in: child, as: type) { return match }
  }
  return nil
}

@MainActor
private func fontPickerAlignmentDescendants<T: NSView>(in view: NSView, as type: T.Type) -> [T] {
  (view as? T).map { [$0] }
    ?? view.subviews.flatMap { fontPickerAlignmentDescendants(in: $0, as: type) }
}

@MainActor
private func fontPickerAlignmentPNG(of view: NSView, appearance: NSAppearance?) throws -> Data {
  view.layoutSubtreeIfNeeded()
  let foreground = try #require(NSImage(data: view.dataWithPDF(inside: view.bounds)))
  let image = NSImage(size: view.bounds.size)
  image.lockFocus()
  appearance?.performAsCurrentDrawingAppearance {
    NSColor.windowBackgroundColor.setFill()
    view.bounds.fill()
  }
  foreground.draw(in: view.bounds, from: .zero, operation: .sourceOver, fraction: 1)
  image.unlockFocus()
  let tiff = try #require(image.tiffRepresentation)
  let bitmap = try #require(NSBitmapImageRep(data: tiff))
  return try #require(bitmap.representation(using: .png, properties: [:]))
}

@MainActor
private func fontPickerAlignmentBitmap(of view: NSView) throws -> NSBitmapImageRep {
  view.layoutSubtreeIfNeeded()
  let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
  view.cacheDisplay(in: view.bounds, to: bitmap)
  return bitmap
}

private func fontPickerAlignmentInkPixelCount(_ bitmap: NSBitmapImageRep) -> Int {
  var count = 0
  for y in 0..<bitmap.pixelsHigh {
    for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
      count += 1
    }
  }
  return count
}

@MainActor
private func fontPickerAlignmentZoomedPNG(_ bitmap: NSBitmapImageRep) throws -> Data {
  let source = NSImage(size: NSSize(width: bitmap.size.width, height: bitmap.size.height))
  source.addRepresentation(bitmap)
  let size = NSSize(width: source.size.width * 4, height: source.size.height * 4)
  let image = NSImage(size: size)
  image.lockFocus()
  NSColor.white.setFill()
  NSRect(origin: .zero, size: size).fill()
  NSGraphicsContext.current?.imageInterpolation = .none
  source.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1)
  image.unlockFocus()
  let tiff = try #require(image.tiffRepresentation)
  let zoomed = try #require(NSBitmapImageRep(data: tiff))
  return try #require(zoomed.representation(using: .png, properties: [:]))
}

private func fontPickerAlignmentEvidenceDirectory() throws -> URL {
  let directory = ProcessInfo.processInfo.environment["FLECK_FONT_PICKER_ALIGNMENT_EVIDENCE_DIRECTORY"].map {
    URL(fileURLWithPath: $0, isDirectory: true)
  } ?? FileManager.default.temporaryDirectory.appendingPathComponent(
    "FleckFontPickerAlignment-\(ProcessInfo.processInfo.processIdentifier)",
    isDirectory: true
  )
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory
}
