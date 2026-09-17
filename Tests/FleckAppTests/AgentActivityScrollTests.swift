import AppKit
import FleckCore
import SwiftUI
import Testing

@testable import FleckApp

@Suite("AgentActivityScroll")
struct AgentActivityScrollTests {
  @Test @MainActor
  func scrollerStaysFivePointsInsidePanelAcrossResizeAndAppearances() async throws {
    for appearanceName in [
      NSAppearance.Name.aqua, .darkAqua, .aqua, .darkAqua,
    ] {
      try await verifyAgentActivityScrollOpening(appearanceName: appearanceName)
    }
  }

  @Test @MainActor
  func scrollerDrawsVisibleKnobAndNoTrackWithStockPositiveControl() throws {
    for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
      let customScrollView = makeAgentActivityScrollerComparison(
        scroller: AgentActivityScroller(),
        appearanceName: appearanceName
      )
      let stockScrollView = makeAgentActivityScrollerComparison(
        scroller: NSScroller(),
        appearanceName: appearanceName
      )
      let custom = try #require(customScrollView.verticalScroller)
      let stock = try #require(stockScrollView.verticalScroller)

      #expect(custom.frame == stock.frame)
      #expect(custom.rect(for: .knob) == stock.rect(for: .knob))
      #expect(
        custom.convert(custom.rect(for: .knob), to: customScrollView)
          == stock.convert(stock.rect(for: .knob), to: stockScrollView)
      )

      for scale in [1, 2] {
        let knob = try renderAgentActivityScrollerPart(custom, part: .knob, scale: scale)
        let stockKnob = try renderAgentActivityScrollerPart(stock, part: .knob, scale: scale)
        let customSilhouette = opacityMask(in: knob)
        let stockSilhouette = opacityMask(in: stockKnob)
        let silhouetteBounds = try #require(nonTransparentPixelBounds(in: knob))

        #expect(customSilhouette == stockSilhouette)
        #expect(silhouetteBounds == nonTransparentPixelBounds(in: stockKnob))
        #expect(silhouetteBounds.minX > 0)
        #expect(silhouetteBounds.maxX < CGFloat(knob.pixelsWide))
        #expect(silhouetteBounds.minY > 0)
        #expect(silhouetteBounds.maxY < CGFloat(knob.pixelsHigh))
      }

      let knob = try renderAgentActivityScrollerPart(custom, part: .knob)
      let stockKnob = try renderAgentActivityScrollerPart(stock, part: .knob)
      let slot = try renderAgentActivityScrollerPart(custom, part: .slot(highlighted: false))
      let highlightedSlot = try renderAgentActivityScrollerPart(
        custom,
        part: .slot(highlighted: true)
      )
      let stockSlot = try renderAgentActivityScrollerPart(stock, part: .slot(highlighted: false))
      let stockHighlightedSlot = try renderAgentActivityScrollerPart(
        stock,
        part: .slot(highlighted: true)
      )

      #expect(nonTransparentPixelCount(in: knob) > 0)
      #expect(nonTransparentPixelCount(in: slot) == 0)
      #expect(nonTransparentPixelCount(in: highlightedSlot) == 0)
      #expect(nonTransparentPixelCount(in: stockSlot) > 0)
      #expect(nonTransparentPixelCount(in: stockHighlightedSlot) > 0)
      try captureAgentActivityScrollerParts(
        appearanceName: appearanceName,
        knob: knob,
        stockKnob: stockKnob,
        slot: slot,
        stockSlot: stockSlot
      )
    }
  }

  @Test @MainActor
  func scrollViewHandlesLongAndShortContent() async throws {
    let longFixture = try await makeAgentActivityScrollFixture(
      recordCount: 20,
      size: NSSize(width: 420, height: 320)
    )
    defer { longFixture.close() }
    let longScrollView = try #require(agentActivityScrollView(in: longFixture.host))
    let longDocument = try #require(longScrollView.documentView)
    let maximumOffset = longDocument.bounds.height - longScrollView.contentView.bounds.height
    #expect(maximumOffset > 100)

    longScrollView.contentView.scroll(to: NSPoint(x: 0, y: maximumOffset))
    longScrollView.reflectScrolledClipView(longScrollView.contentView)
    #expect(longScrollView.contentView.bounds.origin.y > 100)

    let shortFixture = try await makeAgentActivityScrollFixture(
      recordCount: 1,
      size: NSSize(width: 680, height: 800)
    )
    defer { shortFixture.close() }
    let shortScrollView = try #require(agentActivityScrollView(in: shortFixture.host))
    let shortDocument = try #require(shortScrollView.documentView)
    #expect(shortDocument.bounds.height <= shortScrollView.contentView.bounds.height + 1)

    let initialOrigin = shortScrollView.contentView.bounds.origin
    let constrainedBounds = shortScrollView.contentView.constrainBoundsRect(
      NSRect(
        origin: NSPoint(x: 0, y: 100),
        size: shortScrollView.contentView.bounds.size
      )
    )
    shortScrollView.contentView.scroll(to: constrainedBounds.origin)
    shortScrollView.reflectScrolledClipView(shortScrollView.contentView)
    #expect(abs(shortScrollView.contentView.bounds.origin.y - initialOrigin.y) < 0.75)
  }
}

@MainActor
private func verifyAgentActivityScrollOpening(
  appearanceName: NSAppearance.Name
) async throws {
  let fixture = try await makeAgentActivityScrollFixture(
    recordCount: 20,
    size: NSSize(width: 420, height: 320),
    appearanceName: appearanceName
  )
  defer { fixture.close() }

  let scrollView = try #require(agentActivityScrollView(in: fixture.host))
  let document = try #require(scrollView.documentView)
  let scroller = try #require(scrollView.verticalScroller as? AgentActivityScroller)
  let expectedProportion = scrollView.contentView.bounds.height / document.bounds.height
  let initialKnob = scroller.rect(for: .knob)
  let knobCenterInWindow = scroller.convert(
    NSPoint(x: initialKnob.midX, y: initialKnob.midY),
    to: nil
  )

  #expect(scroller.isEnabled)
  #expect(expectedProportion > 0 && expectedProportion < 1)
  #expect(abs(scroller.knobProportion - expectedProportion) < 0.0001)
  #expect(scroller.testPart(knobCenterInWindow) == .knob)
  #expect(scrollView.scrollerStyle == .overlay)
  #expect(scrollView.autohidesScrollers)
  #expect(!scrollView.drawsBackground)
  #expect(scroller.accessibilityRole() == .scrollBar)
  #expect(scroller.target === scrollView)
  #expect(scroller.action != nil)
  #expect(scrollView.scrollerInsets.right == 2)

  let initialScrollFrame = scrollView.convert(scrollView.bounds, to: fixture.host)
  let initialScrollerFrame = scroller.convert(scroller.bounds, to: fixture.host)
  let initialKnobFrame = scroller.convert(initialKnob, to: fixture.host)
  #expect(abs(initialScrollFrame.maxX - fixture.host.bounds.maxX) < 0.75)
  #expect(abs(fixture.host.bounds.maxY - initialScrollFrame.maxY - 18) < 0.75)
  #expect(abs(fixture.host.bounds.maxX - initialScrollerFrame.maxX - 2) < 0.75)
  #expect(abs(initialScrollerFrame.maxX - initialKnobFrame.maxX - 3) < 0.75)
  #expect(abs(fixture.host.bounds.maxX - initialKnobFrame.maxX - 5) < 0.75)

  fixture.window.setContentSize(NSSize(width: 680, height: 480))
  await settleAgentActivityScrollHost(fixture.host)
  let resizedScrollFrame = scrollView.convert(scrollView.bounds, to: fixture.host)
  let resizedScrollerFrame = scroller.convert(scroller.bounds, to: fixture.host)
  let resizedKnobFrame = scroller.convert(scroller.rect(for: .knob), to: fixture.host)
  #expect(abs(resizedScrollFrame.maxX - fixture.host.bounds.maxX) < 0.75)
  #expect(abs(fixture.host.bounds.maxY - resizedScrollFrame.maxY - 18) < 0.75)
  #expect(abs(fixture.host.bounds.maxX - resizedScrollerFrame.maxX - 2) < 0.75)
  #expect(abs(resizedScrollerFrame.maxX - resizedKnobFrame.maxX - 3) < 0.75)
  #expect(abs(fixture.host.bounds.maxX - resizedKnobFrame.maxX - 5) < 0.75)
  try captureAgentActivityScrollFixture(fixture, appearanceName: appearanceName)
}

private enum AgentActivityScrollerPart {
  case knob
  case slot(highlighted: Bool)
}

@MainActor
private func makeAgentActivityScrollerComparison(
  scroller: NSScroller,
  appearanceName: NSAppearance.Name
) -> NSScrollView {
  let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 320))
  scrollView.hasVerticalScroller = true
  scrollView.scrollerStyle = .overlay
  scrollView.verticalScroller = scroller
  scrollView.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 2)
  scrollView.appearance = NSAppearance(named: appearanceName)
  scrollView.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 3_000))
  scrollView.reflectScrolledClipView(scrollView.contentView)
  scrollView.tile()
  scrollView.layoutSubtreeIfNeeded()
  return scrollView
}

@MainActor
private func renderAgentActivityScrollerPart(
  _ scroller: NSScroller,
  part: AgentActivityScrollerPart,
  scale: Int = 1
) throws -> NSBitmapImageRep {
  let bitmap = try #require(
    NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: Int(scroller.bounds.width) * scale,
      pixelsHigh: Int(scroller.bounds.height) * scale,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    )
  )
  bitmap.size = scroller.bounds.size
  let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context
  scroller.effectiveAppearance.performAsCurrentDrawingAppearance {
    switch part {
    case .knob:
      scroller.drawKnob()
    case .slot(let highlighted):
      scroller.drawKnobSlot(in: scroller.rect(for: .knobSlot), highlight: highlighted)
    }
  }
  context.flushGraphics()
  NSGraphicsContext.restoreGraphicsState()
  return bitmap
}

private func opacityMask(in bitmap: NSBitmapImageRep) -> [Bool] {
  var mask: [Bool] = []
  mask.reserveCapacity(bitmap.pixelsWide * bitmap.pixelsHigh)
  for y in 0..<bitmap.pixelsHigh {
    for x in 0..<bitmap.pixelsWide {
      mask.append((bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0)
    }
  }
  return mask
}

private func nonTransparentPixelBounds(in bitmap: NSBitmapImageRep) -> NSRect? {
  var minX = bitmap.pixelsWide
  var minY = bitmap.pixelsHigh
  var maxX = -1
  var maxY = -1
  for y in 0..<bitmap.pixelsHigh {
    for x in 0..<bitmap.pixelsWide
    where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0 {
      minX = min(minX, x)
      minY = min(minY, y)
      maxX = max(maxX, x)
      maxY = max(maxY, y)
    }
  }
  guard maxX >= minX, maxY >= minY else { return nil }
  return NSRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

private func nonTransparentPixelCount(in bitmap: NSBitmapImageRep) -> Int {
  var count = 0
  for y in 0..<bitmap.pixelsHigh {
    for x in 0..<bitmap.pixelsWide
    where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0 {
      count += 1
    }
  }
  return count
}

private func captureAgentActivityScrollerParts(
  appearanceName: NSAppearance.Name,
  knob: NSBitmapImageRep,
  stockKnob: NSBitmapImageRep,
  slot: NSBitmapImageRep,
  stockSlot: NSBitmapImageRep
) throws {
  guard let directory = ProcessInfo.processInfo.environment["AGENT_ACTIVITY_CAPTURE_DIR"] else {
    return
  }
  try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
  for (name, bitmap) in [
    ("knob", knob),
    ("stock-knob", stockKnob),
    ("trackless-slot", slot),
    ("stock-slot", stockSlot),
  ] {
    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    try data.write(
      to: URL(fileURLWithPath: directory)
        .appendingPathComponent("agent-activity-\(appearanceName.rawValue)-\(name).png")
    )
  }
}

@MainActor
private struct AgentActivityScrollFixture {
  let root: URL
  let window: NSWindow
  let host: NSHostingView<AnyView>

  func close() {
    window.contentView = nil
    window.orderOut(nil)
    try? FileManager.default.removeItem(at: root)
  }
}

@MainActor
private func makeAgentActivityScrollFixture(
  recordCount: Int,
  size: NSSize,
  appearanceName: NSAppearance.Name? = nil
) async throws -> AgentActivityScrollFixture {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("AgentActivityScroll-\(UUID().uuidString)", isDirectory: true)
  let note = Note(title: "Activity fixture", body: "After", revision: UInt64(recordCount + 1))
  let store = LocalStore(rootURL: root)
  try await store.save(
    workspace: Workspace(notes: [note], selectedNoteID: note.id),
    preferences: .init(),
    trashedNotes: []
  )
  let activityStore = AgentActivityStore(rootURL: root)
  for index in 0..<recordCount {
    let transaction = PreparedAgentTransaction(
      changeID: UUID(),
      noteID: note.id,
      noteTitle: note.title,
      actor: .integration(profileID: UUID(), displayName: "Codex"),
      operationID: UUID(),
      createdAt: Date().addingTimeInterval(TimeInterval(-index)),
      operation: .appendText,
      patch: AgentTextPatch(
        beforeText: "Before \(index)",
        afterText: "After \(index)",
        range: NSRange(location: 0, length: 0),
        prefixContext: "",
        suffixContext: ""
      ),
      previousRevision: UInt64(index),
      resultingRevision: UInt64(index + 1),
      resultingBodySHA256: ""
    )
    try activityStore.prepare(transaction)
    try activityStore.commit(
      changeID: transaction.changeID,
      receipt: AgentWriteReceipt(
        changeID: transaction.changeID,
        noteID: transaction.noteID,
        previousRevision: transaction.previousRevision,
        resultingRevision: transaction.resultingRevision
      )
    )
  }
  let state = AppState(store: store, agentActivityStore: activityStore)
  await state.waitUntilInitialLoad()
  let host = NSHostingView(
    rootView: AnyView(
      ZStack {
        Color(nsColor: .windowBackgroundColor)
        AgentActivityView(onOpenNote: { _ in }, onDismiss: {})
          .environmentObject(state)
      }
    )
  )
  let window = NSWindow(
    contentRect: NSRect(origin: .zero, size: size),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
  )
  if let appearanceName {
    window.appearance = NSAppearance(named: appearanceName)
  }
  window.contentView = host
  await settleAgentActivityScrollHost(host)
  return AgentActivityScrollFixture(root: root, window: window, host: host)
}

@MainActor
private func settleAgentActivityScrollHost(_ host: NSView) async {
  for _ in 0..<20 {
    host.layoutSubtreeIfNeeded()
    await Task.yield()
  }
}

@MainActor
private func agentActivityScrollView(in view: NSView) -> NSScrollView? {
  if let scrollView = view as? NSScrollView,
    scrollView.verticalScroller is AgentActivityScroller
  {
    return scrollView
  }
  for subview in view.subviews {
    if let scrollView = agentActivityScrollView(in: subview) { return scrollView }
  }
  return nil
}

@MainActor
private func captureAgentActivityScrollFixture(
  _ fixture: AgentActivityScrollFixture,
  appearanceName: NSAppearance.Name
) throws {
  guard let directory = ProcessInfo.processInfo.environment["AGENT_ACTIVITY_CAPTURE_DIR"] else {
    return
  }
  try FileManager.default.createDirectory(
    atPath: directory,
    withIntermediateDirectories: true
  )
  let scrollView = try #require(agentActivityScrollView(in: fixture.host))
  scrollView.flashScrollers()
  scrollView.verticalScroller?.isHidden = false
  scrollView.verticalScroller?.alphaValue = 1
  fixture.host.needsDisplay = true
  fixture.host.displayIfNeeded()
  let bitmap = try #require(fixture.host.bitmapImageRepForCachingDisplay(in: fixture.host.bounds))
  fixture.host.cacheDisplay(in: fixture.host.bounds, to: bitmap)
  let data = try #require(bitmap.representation(using: .png, properties: [:]))
  try data.write(
    to: URL(fileURLWithPath: directory)
      .appendingPathComponent("agent-activity-\(appearanceName.rawValue).png")
  )
}
