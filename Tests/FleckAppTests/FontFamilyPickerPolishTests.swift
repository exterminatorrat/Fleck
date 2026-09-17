import AppKit
import Testing
@testable import FleckApp

@Test @MainActor func fontPickerPolishRemovesVisibleTargetContext() throws {
  let (_, picker) = fontPickerPolishHost(width: 280, currentFamily: "Avenir Next")
  let labels = fontPickerPolishDescendants(in: picker.view, as: NSTextField.self)
    .map(\.stringValue)

  #expect(!labels.contains(where: { $0.hasPrefix("Applying to ") }))
  #expect(picker.searchField.accessibilityHelp() == "Choose a font for Selected text")
}

@Test @MainActor func fontPickerPolishDrawsNeutralPaddedSelectionAndHover() throws {
  for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
    let (window, picker) = fontPickerPolishHost(
      width: 280,
      currentFamily: "Avenir Next",
      appearance: appearanceName
    )
    let table = try #require(fontPickerPolishDescendant(in: picker.view, as: NSTableView.self))
    let scroll = try #require(table.enclosingScrollView)
    scroll.contentView.scroll(to: .zero)
    scroll.reflectScrolledClipView(scroll.contentView)
    #expect(table.selectionHighlightStyle == .none)
    table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    table.layoutSubtreeIfNeeded()
    let selectedRow = try #require(table.rowView(atRow: 0, makeIfNecessary: true))
    selectedRow.isEmphasized = true
    selectedRow.needsDisplay = true
    let selected = try fontPickerPolishBitmap(of: selectedRow, appearance: window.appearance)
    let selectedColor = try #require(fontPickerPolishColor(in: selected, view: selectedRow, point: NSPoint(x: 8, y: 5)))
    #expect(fontPickerPolishSaturation(selectedColor) < 0.06)

    let hoveredRow = try #require(table.rowView(atRow: 1, makeIfNecessary: true))
    let trailingHitPoint = table.convert(
      NSPoint(x: hoveredRow.bounds.maxX - 8, y: hoveredRow.bounds.midY),
      from: hoveredRow
    )
    #expect(table.row(at: trailingHitPoint) == 1)
    let beforeHover = try fontPickerPolishBitmap(of: hoveredRow, appearance: window.appearance)
    fontPickerPolishPlacePointer(over: hoveredRow, in: table, window: window)
    hoveredRow.mouseEntered(with: try #require(fontPickerPolishEnterExitEvent(type: .mouseEntered, window: window)))
    hoveredRow.displayIfNeeded()
    let hovered = try fontPickerPolishBitmap(of: hoveredRow, appearance: window.appearance)

    #expect(fontPickerPolishImageDifference(beforeHover, hovered) > 0.002)
    for x in [CGFloat(8), hoveredRow.bounds.width - 8] {
      let before = try #require(fontPickerPolishColor(in: beforeHover, view: hoveredRow, point: NSPoint(x: x, y: 5)))
      let after = try #require(fontPickerPolishColor(in: hovered, view: hoveredRow, point: NSPoint(x: x, y: 5)))
      #expect(fontPickerPolishColorDifference(before, after) > 0.01)
      #expect(fontPickerPolishSaturation(after) < 0.06)
    }
    let hoverColor = try #require(fontPickerPolishColor(in: hovered, view: hoveredRow, point: NSPoint(x: 8, y: 5)))
    #expect(fontPickerPolishColorDifference(selectedColor, hoverColor) > 0.01)
  }
}

@Test @MainActor func fontPickerPolishHoverExitAndReloadClearFeedback() throws {
  let (window, picker) = fontPickerPolishHost(width: 280, currentFamily: nil)
  let table = try #require(fontPickerPolishDescendant(in: picker.view, as: NSTableView.self))
  let row = try #require(table.rowView(atRow: 1, makeIfNecessary: true))
  let idle = try fontPickerPolishBitmap(of: row, appearance: window.appearance)
  fontPickerPolishPlacePointer(over: row, in: table, window: window)
  row.mouseEntered(with: try #require(fontPickerPolishEnterExitEvent(type: .mouseEntered, window: window)))
  let hovered = try fontPickerPolishBitmap(of: row, appearance: window.appearance)
  #expect(fontPickerPolishImageDifference(idle, hovered) > 0.002)

  window.setFrameOrigin(NSPoint(x: window.frame.minX + 1_000, y: window.frame.minY + 1_000))
  row.mouseExited(with: try #require(fontPickerPolishEnterExitEvent(type: .mouseExited, window: window)))
  let exited = try fontPickerPolishBitmap(of: row, appearance: window.appearance)
  #expect(fontPickerPolishImageDifference(idle, exited) < 0.002)

  picker.searchField.stringValue = "Menlo"
  picker.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
  picker.searchField.stringValue = ""
  picker.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
  table.scrollRowToVisible(max(0, table.numberOfRows - 1))
  table.scrollRowToVisible(0)
  table.layoutSubtreeIfNeeded()
  let reloaded = try #require(table.rowView(atRow: 1, makeIfNecessary: true))
  let reloadedImage = try fontPickerPolishBitmap(of: reloaded, appearance: window.appearance)
  #expect(fontPickerPolishImageDifference(idle, reloadedImage) < 0.002)
}

@Test @MainActor func fontPickerPolishStationaryScrollMovesHoverWithoutMouseExit() throws {
  let (window, picker) = fontPickerPolishHost(width: 280, currentFamily: nil)
  let scroll = try #require(fontPickerPolishDescendant(in: picker.view, as: NSScrollView.self))
  let table = try #require(fontPickerPolishDescendant(in: picker.view, as: NSTableView.self))
  scroll.contentView.scroll(to: .zero)
  scroll.reflectScrolledClipView(scroll.contentView)
  table.layoutSubtreeIfNeeded()

  let oldRow = try #require(table.rowView(atRow: 1, makeIfNecessary: true))
  let point = NSPoint(x: oldRow.bounds.midX, y: oldRow.bounds.midY)
  let pointInWindow = table.convert(table.convert(point, from: oldRow), to: nil)
  let pointer = NSEvent.mouseLocation
  window.setFrameOrigin(NSPoint(x: pointer.x - pointInWindow.x, y: pointer.y - pointInWindow.y))

  oldRow.mouseEntered(with: try #require(fontPickerPolishEnterExitEvent(type: .mouseEntered, window: window)))
  let oldHovered = try fontPickerPolishBitmap(of: oldRow, appearance: window.appearance)
  let oldHoveredColor = try #require(fontPickerPolishColor(in: oldHovered, view: oldRow, point: NSPoint(x: 8, y: 5)))
  #expect(oldHoveredColor.alphaComponent > 0.08)

  scroll.contentView.scroll(to: NSPoint(x: 0, y: scroll.contentView.bounds.minY + 31))
  scroll.reflectScrolledClipView(scroll.contentView)
  table.layoutSubtreeIfNeeded()
  let stationaryPoint = table.convert(window.mouseLocationOutsideOfEventStream, from: nil)
  let currentRowIndex = table.row(at: stationaryPoint)
  #expect(currentRowIndex > 1)
  let currentRow = try #require(table.rowView(atRow: currentRowIndex, makeIfNecessary: true))
  oldRow.updateTrackingAreas()
  currentRow.updateTrackingAreas()

  let oldAfterScroll = try fontPickerPolishBitmap(of: oldRow, appearance: window.appearance)
  let oldAfterColor = try #require(fontPickerPolishColor(in: oldAfterScroll, view: oldRow, point: NSPoint(x: 8, y: 5)))
  let currentAfterScroll = try fontPickerPolishBitmap(of: currentRow, appearance: window.appearance)
  let currentAfterColor = try #require(fontPickerPolishColor(in: currentAfterScroll, view: currentRow, point: NSPoint(x: 8, y: 5)))
  #expect(oldAfterColor.alphaComponent < 0.01)
  #expect(currentAfterColor.alphaComponent > 0.08)

  oldRow.mouseEntered(with: try #require(fontPickerPolishEnterExitEvent(type: .mouseEntered, window: window)))
  let oldAfterStrayEnter = try fontPickerPolishBitmap(of: oldRow, appearance: window.appearance)
  let oldAfterStrayColor = try #require(fontPickerPolishColor(in: oldAfterStrayEnter, view: oldRow, point: NSPoint(x: 8, y: 5)))
  #expect(oldAfterStrayColor.alphaComponent < 0.01)
}

@Test @MainActor func fontPickerPolishUsesTracklessNativeScrollerAtRightEdge() throws {
  for style in [NSScroller.Style.overlay, .legacy] {
    let (_, picker) = fontPickerPolishHost(width: 280, currentFamily: "Avenir Next")
    let scroll = try #require(fontPickerPolishDescendant(in: picker.view, as: NSScrollView.self))
    scroll.scrollerStyle = style
    scroll.tile()
    scroll.layoutSubtreeIfNeeded()
    let scroller = try #require(scroll.verticalScroller)

    #expect(scroll.scrollerStyle == style)
    #expect(scroller.scrollerStyle == style)
    let scrollFrame = picker.view.convert(scroll.bounds, from: scroll)
    #expect(abs(scrollFrame.maxX - picker.view.bounds.maxX) < 1)
    #expect(abs(scroller.frame.maxX - scroll.bounds.maxX) < 1)
    #expect(type(of: scroller) != NSScroller.self)
    #expect(try fontPickerPolishOpaquePixelCount(size: scroller.bounds.size) {
      scroller.drawKnobSlot(in: scroller.bounds, highlight: false)
    } == 0)
    #expect(try fontPickerPolishOpaquePixelCount(size: scroller.bounds.size) {
      scroller.drawKnob()
    } > 0)
  }
}

@Test @MainActor func fontPickerPolishFitsSearchRowsAndEmptyStateAtNarrowWidths() throws {
  for width in [CGFloat(220), 280] {
    let (_, picker) = fontPickerPolishHost(width: width, currentFamily: "Avenir Next")
    let scroll = try #require(fontPickerPolishDescendant(in: picker.view, as: NSScrollView.self))
    let table = try #require(fontPickerPolishDescendant(in: picker.view, as: NSTableView.self))
    let row = try #require(table.rowView(atRow: 0, makeIfNecessary: true))
    let cell = try #require(table.view(atColumn: 0, row: 0, makeIfNecessary: true))

    let searchFrame = picker.view.convert(picker.searchField.bounds, from: picker.searchField)
    let scrollFrame = picker.view.convert(scroll.bounds, from: scroll)
    #expect(abs(searchFrame.minX - 12) < 1)
    #expect(abs(searchFrame.maxX - (width - 12)) < 1)
    #expect(abs(scrollFrame.maxX - width) < 1)
    #expect(table.frame.width <= scroll.contentSize.width + 1)
    #expect(cell.frame.maxX <= row.bounds.maxX + 1)
    #expect(scroll.horizontalScroller == nil || scroll.hasHorizontalScroller == false)

    picker.searchField.stringValue = "nonesuchfont-123"
    picker.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    let visibleLabels = fontPickerPolishDescendants(in: picker.view, as: NSTextField.self)
      .filter { !$0.isHidden }
      .map(\.stringValue)
    #expect(visibleLabels.contains("No matching fonts"))
  }
}

@Test @MainActor func fontPickerPolishHostedVisualEvidence() throws {
  let evidence = try fontPickerPolishEvidenceDirectory()
  for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
    let (selectedWindow, selectedPicker) = fontPickerPolishHost(
      width: 280,
      currentFamily: ".AppleSystemUIFont",
      appearance: appearanceName
    )
    let selectedScroll = try #require(fontPickerPolishDescendant(in: selectedPicker.view, as: NSScrollView.self))
    selectedScroll.contentView.scroll(to: .zero)
    selectedScroll.reflectScrolledClipView(selectedScroll.contentView)
    selectedWindow.orderBack(nil)
    try fontPickerPolishPNG(of: selectedPicker.view, appearance: selectedWindow.appearance).write(
      to: evidence.appendingPathComponent("font-picker-\(appearanceName.rawValue)-selected.png")
    )
    selectedWindow.orderOut(nil)

    let (hoveredWindow, hoveredPicker) = fontPickerPolishHost(
      width: 280,
      currentFamily: "Avenir Next",
      appearance: appearanceName
    )
    let hoveredScroll = try #require(fontPickerPolishDescendant(in: hoveredPicker.view, as: NSScrollView.self))
    hoveredScroll.contentView.scroll(to: .zero)
    hoveredScroll.reflectScrolledClipView(hoveredScroll.contentView)
    let table = try #require(fontPickerPolishDescendant(in: hoveredPicker.view, as: NSTableView.self))
    table.deselectAll(nil)
    let hoveredRow = try #require(table.rowView(atRow: 1, makeIfNecessary: true))
    fontPickerPolishPlacePointer(over: hoveredRow, in: table, window: hoveredWindow)
    hoveredRow.mouseEntered(with: try #require(fontPickerPolishEnterExitEvent(type: .mouseEntered, window: hoveredWindow)))
    try fontPickerPolishPNG(of: hoveredPicker.view, appearance: hoveredWindow.appearance).write(
      to: evidence.appendingPathComponent("font-picker-\(appearanceName.rawValue)-hovered.png")
    )
    hoveredWindow.orderOut(nil)
  }

  let (fullWindow, fullPicker) = fontPickerPolishHost(width: 280, currentFamily: "Avenir Next")
  fullWindow.orderBack(nil)
  let fullScroll = try #require(fontPickerPolishDescendant(in: fullPicker.view, as: NSScrollView.self))
  fullScroll.flashScrollers()
  RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
  try fontPickerPolishPNG(of: fullPicker.view, appearance: fullWindow.appearance).write(
    to: evidence.appendingPathComponent("font-picker-full-scrollbar.png")
  )
  fullWindow.orderOut(nil)

  let (narrowWindow, narrowPicker) = fontPickerPolishHost(width: 220, currentFamily: "Avenir Next")
  narrowWindow.orderBack(nil)
  try fontPickerPolishPNG(of: narrowPicker.view, appearance: narrowWindow.appearance).write(
    to: evidence.appendingPathComponent("font-picker-220-narrow.png")
  )
  narrowWindow.orderOut(nil)
}

@MainActor
private func fontPickerPolishHost(
  width: CGFloat,
  currentFamily: String?,
  appearance: NSAppearance.Name = .aqua
) -> (NSWindow, FontFamilyPickerController) {
  let picker = FontFamilyPickerController(
    currentFamily: currentFamily,
    isMixed: currentFamily == nil,
    targetLabel: "Selected text",
    onCommit: { _ in },
    onCancel: {}
  )
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: width, height: 320),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
  )
  window.appearance = NSAppearance(named: appearance)
  picker.loadViewIfNeeded()
  picker.preferredContentSize = NSSize(width: width, height: 320)
  let host = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 320))
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
private func fontPickerPolishDescendant<T: NSView>(in view: NSView, as type: T.Type) -> T? {
  if let match = view as? T { return match }
  for child in view.subviews {
    if let match = fontPickerPolishDescendant(in: child, as: type) { return match }
  }
  return nil
}

@MainActor
private func fontPickerPolishDescendants<T: NSView>(in view: NSView, as type: T.Type) -> [T] {
  (view as? T).map { [$0] } ?? view.subviews.flatMap { fontPickerPolishDescendants(in: $0, as: type) }
}

@MainActor
private func fontPickerPolishEnterExitEvent(type: NSEvent.EventType, window: NSWindow) -> NSEvent? {
  NSEvent.enterExitEvent(
    with: type,
    location: window.mouseLocationOutsideOfEventStream,
    modifierFlags: [],
    timestamp: 0,
    windowNumber: window.windowNumber,
    context: nil,
    eventNumber: 1,
    trackingNumber: 1,
    userData: nil
  )
}

@MainActor
private func fontPickerPolishPlacePointer(over row: NSTableRowView, in table: NSTableView, window: NSWindow) {
  let point = NSPoint(x: row.bounds.midX, y: row.bounds.midY)
  let pointInWindow = table.convert(table.convert(point, from: row), to: nil)
  let pointer = NSEvent.mouseLocation
  window.setFrameOrigin(NSPoint(x: pointer.x - pointInWindow.x, y: pointer.y - pointInWindow.y))
}

@MainActor
private func fontPickerPolishBitmap(of view: NSView, appearance: NSAppearance?) throws -> NSBitmapImageRep {
  view.layoutSubtreeIfNeeded()
  view.display()
  let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
  appearance?.performAsCurrentDrawingAppearance {
    view.cacheDisplay(in: view.bounds, to: bitmap)
  }
  return bitmap
}

@MainActor
private func fontPickerPolishColor(in bitmap: NSBitmapImageRep, view: NSView, point: NSPoint) -> NSColor? {
  let x = Int(point.x * CGFloat(bitmap.pixelsWide) / view.bounds.width)
  let y = Int(point.y * CGFloat(bitmap.pixelsHigh) / view.bounds.height)
  return bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
}

private func fontPickerPolishSaturation(_ color: NSColor) -> CGFloat {
  max(color.redComponent, color.greenComponent, color.blueComponent)
    - min(color.redComponent, color.greenComponent, color.blueComponent)
}

private func fontPickerPolishColorDifference(_ lhs: NSColor, _ rhs: NSColor) -> CGFloat {
  abs(lhs.redComponent - rhs.redComponent)
    + abs(lhs.greenComponent - rhs.greenComponent)
    + abs(lhs.blueComponent - rhs.blueComponent)
    + abs(lhs.alphaComponent - rhs.alphaComponent)
}

private func fontPickerPolishImageDifference(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep) -> CGFloat {
  guard lhs.pixelsWide == rhs.pixelsWide, lhs.pixelsHigh == rhs.pixelsHigh else { return 1 }
  var total: CGFloat = 0
  var count = 0
  for y in stride(from: 1, to: lhs.pixelsHigh, by: 2) {
    for x in stride(from: 1, to: lhs.pixelsWide, by: 2) {
      guard
        let left = lhs.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
        let right = rhs.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
      else { continue }
      total += fontPickerPolishColorDifference(left, right)
      count += 1
    }
  }
  return count == 0 ? 0 : total / CGFloat(count)
}

@MainActor
private func fontPickerPolishOpaquePixelCount(size: NSSize, drawing: () -> Void) throws -> Int {
  let bitmap = try #require(NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: max(1, Int(size.width)),
    pixelsHigh: max(1, Int(size.height)),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  ))
  let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context
  NSColor.clear.setFill()
  NSRect(origin: .zero, size: size).fill()
  drawing()
  context.flushGraphics()
  NSGraphicsContext.restoreGraphicsState()
  var count = 0
  for y in 0..<bitmap.pixelsHigh {
    for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.01 {
      count += 1
    }
  }
  return count
}

@MainActor
private func fontPickerPolishPNG(
  of view: NSView,
  appearance: NSAppearance?
) throws -> Data {
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
  let composited = try #require(NSBitmapImageRep(data: tiff))
  return try #require(composited.representation(using: .png, properties: [:]))
}

private func fontPickerPolishEvidenceDirectory() throws -> URL {
  let directory = ProcessInfo.processInfo.environment["FLECK_FONT_PICKER_EVIDENCE_DIRECTORY"].map {
    URL(fileURLWithPath: $0, isDirectory: true)
  } ?? FileManager.default.temporaryDirectory.appendingPathComponent(
    "FleckFontPickerPolish-\(ProcessInfo.processInfo.processIdentifier)",
    isDirectory: true
  )
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory
}
