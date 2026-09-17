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
  func scrollerDrawsFourPointCapsuleAndNoTrackAcrossAppearancesAndScales() throws {
    var appearanceColors: [NSAppearance.Name: NSColor] = [:]

    for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
      let customScrollView = makeAgentActivityScrollerComparison(
        scroller: AgentActivityScroller(),
        appearanceName: appearanceName
      )
      let stockScrollView = makeAgentActivityScrollerComparison(
        scroller: NSScroller(),
        appearanceName: appearanceName
      )
      let custom = try #require(customScrollView.verticalScroller as? AgentActivityScroller)
      let stock = try #require(stockScrollView.verticalScroller)

      #expect(custom.frame == stock.frame)
      #expect(custom.rect(for: .knob) == stock.rect(for: .knob))
      #expect(
        custom.convert(custom.rect(for: .knob), to: customScrollView)
          == stock.convert(stock.rect(for: .knob), to: stockScrollView)
      )

      for scale in [1, 2] {
        let knob = try renderAgentActivityScrollerPart(custom, part: .knob, scale: scale)
        let silhouetteBounds = try #require(nonTransparentPixelBounds(in: knob))
        let cornerAlpha = alpha(
          in: knob,
          x: Int(silhouetteBounds.minX),
          y: Int(silhouetteBounds.minY)
        )
        let endCenterAlpha = alpha(
          in: knob,
          x: Int(silhouetteBounds.midX),
          y: Int(silhouetteBounds.minY)
        )
        let topCenterAlpha = alpha(
          in: knob,
          x: Int(silhouetteBounds.midX),
          y: Int(silhouetteBounds.maxY) - 1
        )
        let leftCenterAlpha = alpha(
          in: knob,
          x: Int(silhouetteBounds.minX),
          y: Int(silhouetteBounds.midY)
        )
        let rightCenterAlpha = alpha(
          in: knob,
          x: Int(silhouetteBounds.maxX) - 1,
          y: Int(silhouetteBounds.midY)
        )

        #expect(silhouetteBounds.width == AgentActivityScroller.visualKnobWidth * CGFloat(scale))
        #expect(silhouetteBounds.minX > 0)
        #expect(silhouetteBounds.maxX < CGFloat(knob.pixelsWide))
        #expect(silhouetteBounds.minY > 0)
        #expect(silhouetteBounds.maxY < CGFloat(knob.pixelsHigh))
        #expect(endCenterAlpha > 0)
        #expect(topCenterAlpha > 0)
        #expect(leftCenterAlpha > 0)
        #expect(rightCenterAlpha > 0)
        #expect(cornerAlpha < endCenterAlpha * 0.4)
        #expect(
          alpha(
            in: knob,
            x: Int(silhouetteBounds.minX) - 1,
            y: Int(silhouetteBounds.midY)
          ) == 0
        )
        #expect(
          alpha(
            in: knob,
            x: Int(silhouetteBounds.midX),
            y: Int(silhouetteBounds.minY) - 1
          ) == 0
        )
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
      let paintedBounds = try #require(nonTransparentPixelBounds(in: knob))
      appearanceColors[appearanceName] = knob.colorAt(
        x: Int(paintedBounds.midX),
        y: Int(paintedBounds.midY)
      )
      #expect((appearanceColors[appearanceName]?.alphaComponent ?? 0) >= 0.4)
      #expect((appearanceColors[appearanceName]?.alphaComponent ?? 1) <= 0.75)
      try captureAgentActivityScrollerParts(
        appearanceName: appearanceName,
        knob: knob,
        stockKnob: stockKnob,
        slot: slot,
        stockSlot: stockSlot
      )
    }

    #expect(appearanceColors[.aqua] != appearanceColors[.darkAqua])
  }

  @Test @MainActor
  func visualKnobUsesStableProportionalGeometryAtBothEndpoints() throws {
    let scrollView = makeAgentActivityScrollerComparison(
      scroller: AgentActivityScroller(),
      appearanceName: .aqua
    )
    let scroller = try #require(scrollView.verticalScroller as? AgentActivityScroller)

    for proportion in [CGFloat(0.0001), 0.125, 0.25, 0.5] {
      scroller.knobProportion = proportion
      var visualSize: NSSize?

      for position in [CGFloat(0), 0.5, 1] {
        scroller.doubleValue = Double(position)
        let visual = scroller.visualKnobRect
        let native = scroller.rect(for: .knob)
        let track = scroller.bounds.insetBy(
          dx: 0,
          dy: AgentActivityScroller.visualTrackInset
        )
        let travel = track.height - visual.height
        let expectedY = floor(scroller.isFlipped
          ? track.minY + travel * position
          : track.maxY - visual.height - travel * position)

        #expect(visualSize == nil || visual.size == visualSize)
        #expect(native.contains(visual))
        #expect(visual.width == AgentActivityScroller.visualKnobWidth)
        #expect(abs(visual.minY - expectedY) < 0.001)
        #expect(
          abs(visual.maxX - scroller.bounds.maxX + AgentActivityScroller.visualTrailingInset)
            < 0.001
        )
        visualSize = visual.size
      }

      if proportion == 0.0001 {
        #expect(visualSize?.height == AgentActivityScroller.visualMinimumKnobLength)
      } else {
        #expect((visualSize?.height ?? 0) > AgentActivityScroller.visualMinimumKnobLength)
      }
    }
  }

  @Test @MainActor
  func publicHoverEventsDoNotMorphVisualKnob() throws {
    let scrollView = makeAgentActivityScrollerComparison(
      scroller: AgentActivityScroller(),
      appearanceName: .aqua
    )
    let scroller = try #require(scrollView.verticalScroller as? AgentActivityScroller)
    let idleRect = scroller.visualKnobRect
    let idle = try renderAgentActivityScrollerPart(scroller, part: .knob)
    let location = NSPoint(x: idleRect.midX, y: idleRect.midY)

    scroller.mouseEntered(
      with: try #require(makeAgentActivityEnterExitEvent(type: .mouseEntered, at: location))
    )
    let hoveredRect = scroller.visualKnobRect
    let hovered = try renderAgentActivityScrollerPart(scroller, part: .knob)
    scroller.mouseExited(
      with: try #require(makeAgentActivityEnterExitEvent(type: .mouseExited, at: location))
    )

    #expect(hoveredRect == idleRect)
    #expect(opacityMask(in: hovered) == opacityMask(in: idle))
  }

  @Test @MainActor
  func nativeKnobHitAreaContainsPaintAndDraggingMovesDocument() async throws {
    let componentFixture = try await makeAgentActivityScrollFixture(
      recordCount: 20,
      size: NSSize(width: 420, height: 320)
    )
    defer { componentFixture.close() }
    componentFixture.window.makeKeyAndOrderFront(nil)
    let componentScrollView = try #require(agentActivityScrollView(in: componentFixture.host))
    let componentScroller = try #require(
      componentScrollView.verticalScroller as? AgentActivityScroller
    )
    componentScroller.isHidden = false
    componentScroller.alphaValue = 1
    let paintedKnob = componentScroller.visualKnobRect
    let paintedCenterInWindow = componentScroller.convert(
      NSPoint(x: paintedKnob.midX, y: paintedKnob.midY),
      to: nil
    )

    #expect(componentScroller.rect(for: .knob).contains(paintedKnob))
    #expect(componentScroller.testPart(paintedCenterInWindow) == .knob)

    let componentTrace = try exerciseAgentActivityNativeDrag(
      scroller: componentScroller,
      scrollView: componentScrollView,
      window: componentFixture.window,
      startRect: paintedKnob
    )
    await settleAgentActivityScrollHost(componentFixture.host)

    #expect(componentTrace.targetWasScrollView)
    #expect(componentTrace.actionName != nil)
    #expect(componentTrace.initialHitPart == .knob)
    #expect(!componentTrace.duringValues.isEmpty)
    #expect(!componentTrace.duringHitParts.isEmpty)
    #expect(componentTrace.duringHitParts.contains(.knob))
    #expect(componentTrace.duringHitParts.allSatisfy { $0 == .knob || $0 == .knobSlot })
    #expect(componentTrace.duringValues.contains { $0 != componentTrace.initialValue })
    #expect(componentTrace.finalValue != componentTrace.initialValue)
    #expect(componentTrace.forwardedActions.allSatisfy { $0 })
    #expect(!componentTrace.duringDocumentOrigins.isEmpty)
    #expect(componentTrace.finalDocumentOrigin != componentTrace.initialDocumentOrigin)
    #expect(componentTrace.documentHeight > componentTrace.clipBounds.height)
    #expect(componentScroller.visualKnobRect != componentTrace.initialVisualRect)
    try captureAgentActivityNativeDragTrace(componentTrace)
  }

  @Test @MainActor
  func heldNativeDragFreezesVisualLengthUntilMouseUp() async throws {
    let fixture = try await makeAgentActivityScrollFixture(
      recordCount: 10,
      size: NSSize(width: 420, height: 320)
    )
    defer { fixture.close() }
    fixture.window.makeKeyAndOrderFront(nil)
    let scrollView = try #require(agentActivityScrollView(in: fixture.host))
    let scroller = try #require(scrollView.verticalScroller as? AgentActivityScroller)
    let originalTarget = try #require(scroller.target as AnyObject?)
    let originalAction = try #require(scroller.action)
    let initialRect = scroller.visualKnobRect
    try #require(initialRect.height > AgentActivityScroller.visualMinimumKnobLength)
    let initialValue = scroller.doubleValue
    let initialDocumentOrigin = scrollView.contentView.bounds.origin
    let probe = AgentActivityHeldDragProbe(
      scroller: scroller,
      nextProportion: 0.05,
      target: originalTarget,
      action: originalAction
    )
    scroller.target = probe
    scroller.action = #selector(AgentActivityHeldDragProbe.scrollerDidTrack(_:))
    defer {
      scroller.target = originalTarget
      scroller.action = originalAction
    }

    let startInWindow = scroller.convert(
      NSPoint(x: initialRect.midX, y: initialRect.midY),
      to: nil
    )
    let destinationInWindow = scroller.convert(
      agentActivityDragDestination(from: initialRect, in: scroller, distance: 60),
      to: nil
    )
    let mouseDown = try #require(
      makeAgentActivityMouseEvent(type: .leftMouseDown, at: startInWindow, in: fixture.window)
    )
    let mouseDragged = try #require(
      makeAgentActivityMouseEvent(
        type: .leftMouseDragged,
        at: destinationInWindow,
        in: fixture.window
      )
    )
    let mouseUp = try #require(
      makeAgentActivityMouseEvent(type: .leftMouseUp, at: destinationInWindow, in: fixture.window)
    )
    NSApp.postEvent(mouseDragged, atStart: false)
    NSApp.postEvent(mouseUp, atStart: false)
    scroller.mouseDown(with: mouseDown)
    await settleAgentActivityScrollHost(fixture.host)

    let heldBefore = try #require(probe.rectBeforeProportionChange)
    let heldAfter = try #require(probe.rectAfterProportionChange)
    #expect(heldBefore == heldAfter)
    #expect(heldBefore.size == initialRect.size)
    #expect(probe.maskBeforeProportionChange == probe.maskAfterProportionChange)
    #expect(probe.forwardedAction == true)
    #expect(scroller.doubleValue != initialValue)
    #expect(scrollView.contentView.bounds.origin != initialDocumentOrigin)

    let track = scroller.bounds.insetBy(dx: 0, dy: AgentActivityScroller.visualTrackInset)
    let releasedProportion: CGFloat = 0.5
    let expectedReleasedHeight = floor(
      max(AgentActivityScroller.visualMinimumKnobLength, track.height * releasedProportion)
    )
    try #require(expectedReleasedHeight != heldBefore.height)
    scroller.knobProportion = releasedProportion
    let releasedRect = scroller.visualKnobRect
    let position = min(max(CGFloat(scroller.doubleValue), 0), 1)
    let travel = track.height - releasedRect.height
    let expectedReleasedY = floor(scroller.isFlipped
      ? track.minY + travel * position
      : track.maxY - releasedRect.height - travel * position)

    #expect(releasedRect.height == expectedReleasedHeight)
    #expect(releasedRect.height != heldBefore.height)
    #expect(abs(releasedRect.minY - expectedReleasedY) < 0.001)
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
  let initialVisualKnob = scroller.visualKnobRect
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
  let initialKnobFrame = scroller.convert(initialVisualKnob, to: fixture.host)
  #expect(abs(initialScrollFrame.maxX - fixture.host.bounds.maxX) < 0.75)
  #expect(abs(fixture.host.bounds.maxY - initialScrollFrame.maxY - 18) < 0.75)
  #expect(abs(fixture.host.bounds.maxX - initialScrollerFrame.maxX - 2) < 0.75)
  #expect(abs(initialScrollerFrame.maxX - initialKnobFrame.maxX - 3) < 0.75)
  #expect(abs(fixture.host.bounds.maxX - initialKnobFrame.maxX - 5) < 0.75)

  fixture.window.setContentSize(NSSize(width: 680, height: 480))
  await settleAgentActivityScrollHost(fixture.host)
  let resizedScrollFrame = scrollView.convert(scrollView.bounds, to: fixture.host)
  let resizedScrollerFrame = scroller.convert(scroller.bounds, to: fixture.host)
  let resizedKnobFrame = scroller.convert(scroller.visualKnobRect, to: fixture.host)
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

private struct AgentActivityNativeDragTrace {
  let initialValue: Double
  let duringValues: [Double]
  let finalValue: Double
  let initialHitPart: NSScroller.Part
  let duringHitParts: [NSScroller.Part]
  let targetWasScrollView: Bool
  let actionName: String?
  let forwardedActions: [Bool]
  let initialDocumentOrigin: NSPoint
  let duringDocumentOrigins: [NSPoint]
  let finalDocumentOrigin: NSPoint
  let documentHeight: CGFloat
  let clipBounds: NSRect
  let initialVisualRect: NSRect
}

@MainActor
private final class AgentActivityScrollerActionRecorder: NSObject {
  let target: AnyObject
  let action: Selector
  let scrollView: NSScrollView
  var values: [Double] = []
  var hitParts: [NSScroller.Part] = []
  var documentOrigins: [NSPoint] = []
  var forwardedActions: [Bool] = []

  init(target: AnyObject, action: Selector, scrollView: NSScrollView) {
    self.target = target
    self.action = action
    self.scrollView = scrollView
  }

  @objc func forward(_ sender: NSScroller) {
    values.append(sender.doubleValue)
    hitParts.append(sender.hitPart)
    forwardedActions.append(NSApp.sendAction(action, to: target, from: sender))
    documentOrigins.append(scrollView.contentView.bounds.origin)
  }
}

@MainActor
private func exerciseAgentActivityNativeDrag(
  scroller: NSScroller,
  scrollView: NSScrollView,
  window: NSWindow,
  startRect: NSRect
) throws -> AgentActivityNativeDragTrace {
  let originalTarget = try #require(scroller.target as AnyObject?)
  let originalAction = try #require(scroller.action)
  let recorder = AgentActivityScrollerActionRecorder(
    target: originalTarget,
    action: originalAction,
    scrollView: scrollView
  )
  let initialValue = scroller.doubleValue
  let initialOrigin = scrollView.contentView.bounds.origin
  let startInWindow = scroller.convert(
    NSPoint(x: startRect.midX, y: startRect.midY),
    to: nil
  )
  let initialHitPart = scroller.testPart(startInWindow)
  let destinationInWindow = scroller.convert(
    agentActivityDragDestination(from: startRect, in: scroller, distance: 80),
    to: nil
  )
  let mouseDown = try #require(
    makeAgentActivityMouseEvent(type: .leftMouseDown, at: startInWindow, in: window)
  )
  let mouseDragged = try #require(
    makeAgentActivityMouseEvent(type: .leftMouseDragged, at: destinationInWindow, in: window)
  )
  let mouseUp = try #require(
    makeAgentActivityMouseEvent(type: .leftMouseUp, at: destinationInWindow, in: window)
  )

  scroller.target = recorder
  scroller.action = #selector(AgentActivityScrollerActionRecorder.forward(_:))
  defer {
    scroller.target = originalTarget
    scroller.action = originalAction
  }
  NSApp.postEvent(mouseDragged, atStart: false)
  NSApp.postEvent(mouseUp, atStart: false)
  scroller.mouseDown(with: mouseDown)

  return AgentActivityNativeDragTrace(
    initialValue: initialValue,
    duringValues: recorder.values,
    finalValue: scroller.doubleValue,
    initialHitPart: initialHitPart,
    duringHitParts: recorder.hitParts,
    targetWasScrollView: originalTarget === scrollView,
    actionName: NSStringFromSelector(originalAction),
    forwardedActions: recorder.forwardedActions,
    initialDocumentOrigin: initialOrigin,
    duringDocumentOrigins: recorder.documentOrigins,
    finalDocumentOrigin: scrollView.contentView.bounds.origin,
    documentHeight: scrollView.documentView?.bounds.height ?? 0,
    clipBounds: scrollView.contentView.bounds,
    initialVisualRect: startRect
  )
}

private func agentActivityScrollerPartName(_ part: NSScroller.Part) -> String {
  switch part {
  case .noPart: "noPart"
  case .decrementPage: "decrementPage"
  case .knob: "knob"
  case .incrementPage: "incrementPage"
  case .decrementLine: "decrementLine"
  case .incrementLine: "incrementLine"
  case .knobSlot: "knobSlot"
  @unknown default: "unknown"
  }
}

private func captureAgentActivityNativeDragTrace(
  _ trace: AgentActivityNativeDragTrace
) throws {
  guard let directory = ProcessInfo.processInfo.environment["AGENT_ACTIVITY_CAPTURE_DIR"] else {
    return
  }
  let duringParts = trace.duringHitParts.map {
    "\(agentActivityScrollerPartName($0))(raw=\($0.rawValue))"
  }.joined(separator: ",")
  let duringValues = trace.duringValues.map { "\($0)" }.joined(separator: ",")
  let duringOrigins = trace.duringDocumentOrigins.map {
    "(\($0.x),\($0.y))"
  }.joined(separator: ",")
  let text = """
  eventSequence=leftMouseDown,leftMouseDragged,leftMouseUp
  initialHitPart=\(agentActivityScrollerPartName(trace.initialHitPart))(raw=\(trace.initialHitPart.rawValue))
  duringHitParts=\(duringParts)
  targetWasScrollView=\(trace.targetWasScrollView)
  action=\(trace.actionName ?? "nil")
  initialValue=\(trace.initialValue)
  duringValues=\(duringValues)
  finalValue=\(trace.finalValue)
  initialDocumentOrigin=(\(trace.initialDocumentOrigin.x),\(trace.initialDocumentOrigin.y))
  duringDocumentOrigins=\(duringOrigins)
  finalDocumentOrigin=(\(trace.finalDocumentOrigin.x),\(trace.finalDocumentOrigin.y))
  documentHeight=\(trace.documentHeight)
  clipBounds=\(trace.clipBounds)
  """
  try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
  try text.write(
    to: URL(fileURLWithPath: directory)
      .appendingPathComponent("agent-activity-native-drag-trace.txt"),
    atomically: true,
    encoding: String.Encoding.utf8
  )
}

@MainActor
private final class AgentActivityHeldDragProbe: NSObject {
  let scroller: AgentActivityScroller
  let nextProportion: CGFloat
  let target: AnyObject
  let action: Selector
  var rectBeforeProportionChange: NSRect?
  var rectAfterProportionChange: NSRect?
  var maskBeforeProportionChange: [Bool]?
  var maskAfterProportionChange: [Bool]?
  var forwardedAction: Bool?

  init(
    scroller: AgentActivityScroller,
    nextProportion: CGFloat,
    target: AnyObject,
    action: Selector
  ) {
    self.scroller = scroller
    self.nextProportion = nextProportion
    self.target = target
    self.action = action
  }

  @objc func scrollerDidTrack(_ sender: NSScroller) {
    guard rectBeforeProportionChange == nil else {
      forwardedAction = (forwardedAction ?? true)
        && NSApp.sendAction(action, to: target, from: sender)
      return
    }
    rectBeforeProportionChange = scroller.visualKnobRect
    maskBeforeProportionChange = try? opacityMask(
      in: renderAgentActivityScrollerPart(scroller, part: .knob)
    )
    forwardedAction = (forwardedAction ?? true)
      && NSApp.sendAction(action, to: target, from: sender)
    scroller.knobProportion = nextProportion
    rectAfterProportionChange = scroller.visualKnobRect
    maskAfterProportionChange = try? opacityMask(
      in: renderAgentActivityScrollerPart(scroller, part: .knob)
    )
  }
}

@MainActor
private func makeAgentActivityMouseEvent(
  type: NSEvent.EventType,
  at location: NSPoint,
  in window: NSWindow
) -> NSEvent? {
  NSEvent.mouseEvent(
    with: type,
    location: location,
    modifierFlags: [],
    timestamp: ProcessInfo.processInfo.systemUptime,
    windowNumber: window.windowNumber,
    context: nil,
    eventNumber: 0,
    clickCount: 1,
    pressure: 1
  )
}

private func makeAgentActivityEnterExitEvent(
  type: NSEvent.EventType,
  at location: NSPoint
) -> NSEvent? {
  NSEvent.enterExitEvent(
    with: type,
    location: location,
    modifierFlags: [],
    timestamp: ProcessInfo.processInfo.systemUptime,
    windowNumber: 0,
    context: nil,
    eventNumber: 0,
    trackingNumber: 0,
    userData: nil
  )
}

@MainActor
private func agentActivityDragDestination(
  from knob: NSRect,
  in scroller: NSScroller,
  distance: CGFloat
) -> NSPoint {
  let valueDirection: CGFloat = scroller.doubleValue <= 0.5 ? 1 : -1
  let coordinateDirection = scroller.isFlipped ? valueDirection : -valueDirection
  let y = knob.midY + coordinateDirection * distance
  return NSPoint(
    x: knob.midX,
    y: min(max(y, scroller.bounds.minY + 4), scroller.bounds.maxY - 4)
  )
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

private func alpha(in bitmap: NSBitmapImageRep, x: Int, y: Int) -> CGFloat {
  bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
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
