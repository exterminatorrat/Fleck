import AppKit
import Testing

@testable import FleckApp

@Test @MainActor func menuPanelBandMovementStaysOwnedWhileInteriorAndControlMovementReachContent()
  async throws
{
  let screen = try #require(NSScreen.main)
  let fixture = await CursorRoutingFixture(screen: screen)
  defer { fixture.tearDown() }
  try await fixture.activateWindow()
  #expect(fixture.window.isKeyWindow, "cursor routing fixture window never became key")
  #expect(
    fixture.geometryStore.cachedStatusButton?.screenFrame.maxX == fixture.window.frame.maxX,
    "cursor routing fixture lost its anchored side"
  )
  let bounds = fixture.host.bounds

  for (name, point, cursor) in fixture.bandExpectations {
    #expect(
      fixture.host.usableHandle(at: point, in: fixture.window, fixedSide: fixture.fixedSide) != nil,
      "\(name) is not an eligible band point"
    )
    fixture.resetObservations()
    NSCursor.arrow.set()
    fixture.hover(atHostPoint: point)
    #expect(
      fixture.window.dispatchedTypes == [.mouseMoved],
      "\(name) movement did not pass through to the window"
    )
    #expect(
      fixture.content.mouseMovedCount == 1,
      "\(name) movement did not pass through exactly once to the content"
    )
    #expect(NSCursor.current === cursor, "\(name) movement did not set its resize cursor")
  }

  fixture.resetObservations()
  NSCursor.arrow.set()
  fixture.hover(atHostPoint: CGPoint(x: bounds.midX, y: bounds.midY))
  #expect(
    fixture.window.dispatchedTypes == [.mouseMoved],
    "interior movement was consumed or the fixture window was not key"
  )
  #expect(
    fixture.window.firstResponder === fixture.content,
    "fixture content is not first responder"
  )
  #expect(
    fixture.content.mouseMovedCount >= 1,
    "interior movement never reached the content or the fixture window was not key"
  )
  #expect(NSCursor.current === NSCursor.arrow)

  let sidePoint = fixture.bandExpectations[0].point
  let control = NSButton(
    frame: CGRect(
      x: fixture.fixedSide == .left ? bounds.maxX - 20 : bounds.minX,
      y: bounds.midY - 20,
      width: 20,
      height: 40
    )
  )
  control.isEnabled = true
  fixture.content.addSubview(control)
  defer { control.removeFromSuperview() }
  fixture.host.invalidateResizeCursorRegions()
  let advertisedAtControl = fixture.host.cursorRegistrations().contains {
    $0.rect.contains(sidePoint)
  }
  #expect(
    !advertisedAtControl,
    "the native margin map advertised an enabled control"
  )

  fixture.resetObservations()
  NSCursor.arrow.set()
  fixture.hover(atHostPoint: sidePoint)
  #expect(
    fixture.window.dispatchedTypes == [.mouseMoved],
    "movement over an enabled control was consumed by the resize band"
  )
  #expect(NSCursor.current === NSCursor.arrow)

  control.isEnabled = false
  fixture.host.invalidateResizeCursorRegions()
  let advertisedAtDisabledControl = fixture.host.cursorRegistrations().contains {
    $0.rect.contains(sidePoint)
  }
  let marginLayout = try #require(
    MenuPanelResizeGeometry.layout(in: fixture.host.bounds, fixedSide: fixture.fixedSide)
  )
  #expect(
    advertisedAtDisabledControl
      == MenuPanelResizeGeometry.cursorRegions(in: bounds, fixedSide: fixture.fixedSide)
        .contains(where: { $0.rect.contains(sidePoint) }),
    "the native cursor map disagreed with the admitted seven-point band"
  )
  #expect(marginLayout.bodyBounds.minY - marginLayout.outerBounds.minY == 3)
  #expect(marginLayout.handle(at: sidePoint) == nil)

  fixture.resetObservations()
  fixture.hover(atHostPoint: sidePoint)
  #expect(
    fixture.window.dispatchedTypes == [.mouseMoved],
    "disabled-control band movement did not pass through to the window"
  )
  #expect(fixture.content.mouseMovedCount == 1)
  #expect(NSCursor.current === NSCursor.resizeLeftRight)

  fixture.resetObservations()
  fixture.setSyntheticLivePointer(atHostPoint: sidePoint)
  fixture.exit(atHostPoint: sidePoint)
  #expect(fixture.window.dispatchedTypes == [.mouseExited], "band exit delivery changed")
  #expect(NSCursor.current === NSCursor.resizeLeftRight)
}

@Test @MainActor func queuedCursorRefreshSurvivesAnInstallationReplacedBeforeItRuns() async throws {
  let screen = try #require(NSScreen.main)
  let fixture = await CursorRoutingFixture(screen: screen)
  defer { fixture.tearDown() }
  try await fixture.activateWindow()
  let sidePoint = fixture.bandExpectations[0].point
  fixture.setSyntheticLivePointer(atHostPoint: sidePoint)
  let admission = await fixture.awaitInputHitAdmission(atHostPoint: sidePoint)
  try #require(admission.admitted, "band input was never admitted: \(admission.diagnostic)")
  let handle = try #require(
    fixture.host.usableHandle(
      at: fixture.host.convert(sidePoint, to: nil),
      in: fixture.window,
      fixedSide: fixture.fixedSide
    ),
    "the supersession premise needs an eligible band handle"
  )
  let expected = fixture.host.cursor(for: handle, fixedSide: fixture.fixedSide)

  fixture.hover(atHostPoint: sidePoint)
  try #require(NSCursor.current === expected, "the first movement never set the band cursor")
  fixture.host.uninstall()
  fixture.host.installIfNeeded()
  fixture.hover(atHostPoint: sidePoint)

  NSCursor.arrow.set()
  await fixture.drainMainQueue()
  #expect(
    NSCursor.current === expected,
    "the queued refresh of the replacement installation never applied the live-pointer cursor"
  )
}

@Test @MainActor func queuedCursorRefreshRetargetsHoverAfterHostGeometryCatchesUp() async throws {
  let screen = try #require(NSScreen.main)
  let fixture = await CursorRoutingFixture(screen: screen)
  defer { fixture.tearDown() }
  let fullWidth = fixture.host.bounds.width
  let fullHeight = fixture.host.bounds.height
  #expect(fullWidth > 400)
  #expect(fixture.fixedSide == .right, "layout-lag fixture lost its right-anchored side")
  try await fixture.activateWindow()
  let lagPointInWindow = CGPoint(x: fullWidth - 1, y: 1)
  #expect(
    MenuPanelResizeGeometry.handle(
      at: lagPointInWindow,
      in: CGRect(x: 0, y: 0, width: fullWidth, height: fullHeight),
      fixedSide: fixture.fixedSide
    ) == .nearBottomCorner
  )

  fixture.setSyntheticLivePointer(atHostPoint: lagPointInWindow)
  let admission = await fixture.awaitInputHitAdmission(atHostPoint: lagPointInWindow)
  try #require(admission.admitted, "band input was never admitted: \(admission.diagnostic)")

  fixture.host.frame = CGRect(x: 0, y: 0, width: fullWidth - 2, height: fullHeight)
  fixture.host.needsLayout = true
  fixture.host.layoutSubtreeIfNeeded()
  await fixture.drainMainQueue()
  #expect(
    fixture.host.usableHandle(
      at: lagPointInWindow,
      in: fixture.window,
      fixedSide: fixture.fixedSide
    ) == nil,
    "lagging host bounds did not hide the band at the new edge"
  )

  NSCursor.arrow.set()
  fixture.host.frame = CGRect(x: 0, y: 0, width: fullWidth, height: fullHeight)
  fixture.host.needsLayout = true
  fixture.host.layoutSubtreeIfNeeded()
  #expect(
    fixture.host.usableHandle(
      at: lagPointInWindow,
      in: fixture.window,
      fixedSide: fixture.fixedSide
    ) == .nearBottomCorner,
    "fresh hover resolution still misses the band after layout caught up"
  )

  await fixture.drainMainQueue()
  #expect(
    NSCursor.current === fixture.host.cursor(for: .nearBottomCorner, fixedSide: fixture.fixedSide),
    "the layout-triggered refresh never applied the retargeted band cursor"
  )
}

@Test @MainActor func menuPanelStaleExitResolvesTheLivePointerNotTheEventLocation() async throws {
  let screen = try #require(NSScreen.main)
  let fixture = await CursorRoutingFixture(screen: screen)
  defer { fixture.tearDown() }
  try await fixture.activateWindow()
  let bandPoint = fixture.bandExpectations[0].point
  let interiorPoint = CGPoint(
    x: fixture.host.bounds.midX,
    y: fixture.host.bounds.midY
  )

  NSCursor.arrow.set()
  fixture.setSyntheticLivePointer(atHostPoint: bandPoint)
  let bandAdmission = await fixture.awaitInputHitAdmission(atHostPoint: bandPoint)
  try #require(
    bandAdmission.admitted,
    "band input hit was never admitted to this window: \(bandAdmission.diagnostic)"
  )
  fixture.hover(atHostPoint: bandPoint)
  try #require(NSCursor.current === NSCursor.resizeLeftRight)
  fixture.resetObservations()
  NSCursor.arrow.set()
  fixture.exit(atHostPoint: interiorPoint)
  await fixture.drainMainQueue()
  #expect(
    NSCursor.current === NSCursor.resizeLeftRight,
    "a stale exit did not restore the cursor the live pointer still justifies"
  )
  #expect(
    fixture.window.dispatchedTypes.contains(.mouseExited),
    "band exit delivery changed"
  )

  fixture.setSyntheticLivePointer(atHostPoint: interiorPoint)
  let interiorAdmission = await fixture.awaitInputHitAdmission(atHostPoint: interiorPoint)
  try #require(
    interiorAdmission.admitted,
    "interior input hit was never admitted to this window: \(interiorAdmission.diagnostic)"
  )
  NSCursor.resizeLeftRight.set()
  fixture.exit(atHostPoint: bandPoint)
  await fixture.drainMainQueue()
  #expect(
    NSCursor.current === NSCursor.arrow,
    "an actual exit away from the band never relinquished the resize cursor"
  )
}

@Test @MainActor func menuPanelExitOutsideTheWindowRelinquishes() async throws {
  let screen = try #require(NSScreen.main)
  let fixture = await CursorRoutingFixture(screen: screen)
  defer { fixture.tearDown() }
  try await fixture.activateWindow()
  let bandPoint = fixture.bandExpectations[0].point

  NSCursor.arrow.set()
  fixture.setSyntheticLivePointer(atHostPoint: bandPoint)
  fixture.hover(atHostPoint: bandPoint)
  try #require(NSCursor.current === NSCursor.resizeLeftRight)

  fixture.setSyntheticLivePointerInWindow(CGPoint(x: -60, y: 40))
  fixture.exit(atHostPoint: bandPoint)
  #expect(
    NSCursor.current === NSCursor.arrow,
    "an exit with the live pointer outside the window left the resize cursor sticky"
  )
}

@Test @MainActor func menuPanelExitOutsideTheWindowDuringDragKeepsTheHandleCursor() async throws {
  let screen = try #require(NSScreen.main)
  let fixture = await CursorRoutingFixture(screen: screen)
  defer { fixture.tearDown() }
  let fullWidth = fixture.host.bounds.width
  let startHostPoint = CGPoint(x: fullWidth - 2, y: 2)
  let startScreenPoint = fixture.window.convertPoint(
    toScreen: fixture.host.convert(startHostPoint, to: nil)
  )

  fixture.mouseDown(atHostPoint: startHostPoint)
  try #require(fixture.controller.isTracking, "drag exit fixture never began a resize")
  fixture.drag(toScreenPoint: CGPoint(x: startScreenPoint.x, y: startScreenPoint.y - 30))
  try #require(NSCursor.current === NSCursor.resizeUpDown)

  fixture.setSyntheticLivePointerInWindow(CGPoint(x: -60, y: 40))
  NSCursor.arrow.set()
  fixture.exit(atHostPoint: CGPoint(x: fullWidth - 2, y: 2))
  #expect(
    NSCursor.current === NSCursor.resizeUpDown,
    "an exit during an owned drag left the handle cursor relinquishable"
  )
  #expect(fixture.controller.isTracking, "the exit ended the resize interaction")
}

@Test @MainActor func menuPanelReleaseOverControlInLagStripRelinquishes() async throws {
  let screen = try #require(NSScreen.main)
  let fixture = await CursorRoutingFixture(screen: screen)
  defer { fixture.tearDown() }
  #expect(fixture.fixedSide == .right)
  #expect(fixture.host.bounds.width == 420)
  #expect(fixture.window.frame.width == 420)
  let fullWidth = fixture.host.bounds.width
  let startHostPoint = CGPoint(x: fullWidth - 2, y: 2)
  let startScreenPoint = fixture.window.convertPoint(
    toScreen: fixture.host.convert(startHostPoint, to: nil)
  )
  let draggedScreenPoint = CGPoint(x: startScreenPoint.x, y: startScreenPoint.y - 30)

  fixture.mouseDown(atHostPoint: startHostPoint)
  try #require(fixture.controller.isTracking, "control lag fixture never began a resize")
  fixture.drag(toScreenPoint: draggedScreenPoint)
  fixture.host.frame = CGRect(
    x: 0,
    y: 0,
    width: fullWidth - 2,
    height: fixture.host.bounds.height
  )
  #expect(fixture.host.bounds.width == 418)
  #expect(fixture.window.frame.width == 420)
  let control = NSButton(frame: CGRect(x: fullWidth - 6, y: 0, width: 6, height: 60))
  control.isEnabled = true
  fixture.content.addSubview(control)
  defer { control.removeFromSuperview() }
  #expect(
    !fixture.host.bounds.contains(
      fixture.host.convert(
        fixture.window.convertPoint(fromScreen: draggedScreenPoint),
        from: nil
      )
    ),
    "the control lag premise needs the release point outside the lagging host bounds"
  )
  fixture.mouseUp(atScreenPoint: draggedScreenPoint)
  #expect(fixture.commits.count == 1)
  #expect(
    NSCursor.current === NSCursor.arrow,
    "a release over an enabled control in the lag strip kept the resize cursor"
  )
}

@Test @MainActor func menuPanelReleaseOverLaggingHostBoundsDoesNotRelinquish() async throws {
  let screen = try #require(NSScreen.main)
  let fixture = await CursorRoutingFixture(screen: screen)
  defer { fixture.tearDown() }
  #expect(fixture.fixedSide == .right, "lag fixture lost its right-anchored side")
  #expect(fixture.host.bounds.width == 420, "lag fixture host must start at the native 420 width")
  #expect(fixture.window.frame.width == 420, "lag fixture window must start at 420")
  let fullWidth = fixture.host.bounds.width
  let startHostPoint = CGPoint(x: fullWidth - 2, y: 2)
  let startScreenPoint = fixture.window.convertPoint(
    toScreen: fixture.host.convert(startHostPoint, to: nil)
  )
  let draggedScreenPoint = CGPoint(x: startScreenPoint.x, y: startScreenPoint.y - 30)
  let startingHeight = fixture.window.frame.height

  fixture.mouseDown(atHostPoint: startHostPoint)
  try #require(fixture.controller.isTracking, "release fixture never began a resize")
  fixture.drag(toScreenPoint: draggedScreenPoint)
  #expect(fixture.window.frame.height != startingHeight)
  #expect(fixture.window.frame.width == 420, "the height drag changed the window width")

  fixture.host.frame = CGRect(
    x: 0,
    y: 0,
    width: fullWidth - 2,
    height: fixture.host.bounds.height
  )
  #expect(fixture.host.bounds.width == 418, "the lagging host must be 418 wide")
  #expect(fixture.window.frame.width == 420, "the lagging host must trail the 420 window")
  #expect(
    fixture.window.frame.contains(draggedScreenPoint),
    "the lag premise needs the release point inside the window"
  )
  #expect(
    !fixture.host.bounds.contains(
      fixture.host.convert(
        fixture.window.convertPoint(fromScreen: draggedScreenPoint),
        from: nil
      )
    ),
    "the lag premise needs the release point outside the lagging host bounds"
  )
  fixture.mouseUp(atScreenPoint: draggedScreenPoint)
  #expect(fixture.commits.count == 1, "the lagged release did not commit")

  #expect(
    NSCursor.current !== NSCursor.arrow,
    "a release inside the window but outside lagging host bounds relinquished the cursor"
  )
}

@Test @MainActor func menuPanelReleaseOutsideTheWindowStillRelinquishes() async throws {
  let screen = try #require(NSScreen.main)
  let fixture = await CursorRoutingFixture(screen: screen)
  defer { fixture.tearDown() }
  let fullWidth = fixture.host.bounds.width
  let startHostPoint = CGPoint(x: fullWidth - 1, y: 2)
  let startScreenPoint = fixture.window.convertPoint(
    toScreen: fixture.host.convert(startHostPoint, to: nil)
  )
  fixture.mouseDown(atHostPoint: startHostPoint)
  try #require(fixture.controller.isTracking, "outside release fixture never began a resize")
  fixture.drag(toScreenPoint: CGPoint(x: startScreenPoint.x, y: startScreenPoint.y - 60))
  let outsideScreenPoint = CGPoint(x: fixture.window.frame.minX - 40, y: startScreenPoint.y - 60)
  #expect(
    !fixture.window.frame.contains(outsideScreenPoint),
    "the outside premise needs the release point beyond the window"
  )
  fixture.mouseUp(atScreenPoint: outsideScreenPoint)
  #expect(fixture.commits.count == 1)
  #expect(
    NSCursor.current === NSCursor.arrow,
    "a release outside the window no longer relinquishes the resize cursor"
  )
}

@Test @MainActor func menuPanelReleaseOverEnabledControlStillRelinquishes() async throws {
  let screen = try #require(NSScreen.main)
  let fixture = await CursorRoutingFixture(screen: screen)
  defer { fixture.tearDown() }
  let fullWidth = fixture.host.bounds.width
  let startHostPoint = CGPoint(x: fullWidth - 1, y: 2)
  let startScreenPoint = fixture.window.convertPoint(
    toScreen: fixture.host.convert(startHostPoint, to: nil)
  )
  let draggedScreenPoint = CGPoint(x: startScreenPoint.x, y: startScreenPoint.y - 30)

  fixture.mouseDown(atHostPoint: startHostPoint)
  try #require(fixture.controller.isTracking, "control release fixture never began a resize")
  fixture.drag(toScreenPoint: draggedScreenPoint)
  let control = NSButton(frame: CGRect(x: fullWidth - 40, y: 0, width: 40, height: 40))
  control.isEnabled = true
  fixture.content.addSubview(control)
  defer { control.removeFromSuperview() }
  #expect(
    fixture.host.usableHandle(
      at: fixture.window.convertPoint(fromScreen: draggedScreenPoint),
      in: fixture.window,
      fixedSide: fixture.fixedSide
    ) == nil,
    "the control premise needs an enabled control under the release point"
  )
  fixture.mouseUp(atScreenPoint: draggedScreenPoint)
  #expect(fixture.commits.count == 1)
  #expect(
    NSCursor.current === NSCursor.arrow,
    "a release over an enabled control no longer relinquishes the resize cursor"
  )
}

@Test @MainActor func menuPanelBandHitIsOwnedByTheInstalledResizeHost() async throws {
  let screen = try #require(NSScreen.main)
  let fixture = await CursorRoutingFixture(screen: screen)
  defer { fixture.tearDown() }
  try await fixture.activateWindow()
  try #require(
    fixture.host.usableHandle(
      at: fixture.host.convert(fixture.bandExpectations[0].point, to: nil),
      in: fixture.window,
      fixedSide: fixture.fixedSide
    ) != nil,
    "the fixture never aligned an eligible band handle"
  )

  for (name, point, _) in fixture.bandExpectations {
    #expect(
      fixture.contentHit(atHostPoint: point) === fixture.host,
      "\(name) band hit did not reach the resize host"
    )
  }
  let bounds = fixture.host.bounds
  #expect(
    fixture.contentHit(atHostPoint: CGPoint(x: bounds.midX, y: bounds.midY))
      === fixture.content,
    "the interior hit no longer reaches the content"
  )
  #expect(
    fixture.contentHit(atHostPoint: CGPoint(x: bounds.midX, y: bounds.minY + 20))
      === fixture.content,
    "content just above the bottom band no longer receives its hit"
  )
}

@Test @MainActor func menuPanelBandHitHonorsSuperviewCoordinates() async throws {
  let screen = try #require(NSScreen.main)
  let fixture = await CursorRoutingFixture(screen: screen)
  defer { fixture.tearDown() }
  try await fixture.activateWindow()
  fixture.host.frame = fixture.host.frame.insetBy(dx: 20, dy: 12)
  try #require(
    fixture.host.frame.origin != .zero,
    "the offset premise needs the host inset from its superview origin"
  )

  for (name, point, _) in fixture.bandExpectations {
    let windowPoint = fixture.host.convert(point, to: nil)
    let superview = try #require(fixture.content.superview)
    let superPoint = superview.convert(windowPoint, from: nil)
    #expect(
      fixture.host.hitTest(superPoint) === fixture.host,
      "\(name) band hit ignored the superview coordinate contract"
    )
    #expect(
      fixture.contentHit(atHostPoint: point) === fixture.host,
      "\(name) band hit did not survive the host superview offset"
    )
    #expect(
      fixture.host.hitTest(point) == nil,
      "\(name) band hit accepted host-local coordinates as superview coordinates"
    )
  }
}

@Test @MainActor func menuPanelBandHitYieldsToEnabledControlsAndGlyphs() async throws {
  let screen = try #require(NSScreen.main)
  let fixture = await CursorRoutingFixture(screen: screen)
  defer { fixture.tearDown() }
  try await fixture.activateWindow()
  let sidePoint = fixture.bandExpectations[0].point
  let bottomPoint = fixture.bandExpectations[1].point

  let control = NSButton(frame: CGRect(x: sidePoint.x, y: sidePoint.y - 20, width: 60, height: 40))
  control.isEnabled = true
  fixture.content.addSubview(control, positioned: .below, relativeTo: fixture.host)
  defer { control.removeFromSuperview() }
  #expect(
    control.frame.contains(sidePoint),
    "the control premise needs the enabled control under the band point"
  )
  #expect(
    fixture.contentHit(atHostPoint: sidePoint) === control,
    "an enabled control under the band no longer receives the hit"
  )

  let disabled = NSButton(
    frame: CGRect(x: bottomPoint.x - 30, y: bottomPoint.y - 20, width: 60, height: 40)
  )
  disabled.isEnabled = false
  fixture.content.addSubview(disabled, positioned: .below, relativeTo: fixture.host)
  defer { disabled.removeFromSuperview() }
  #expect(
    fixture.contentHit(atHostPoint: bottomPoint) === fixture.host,
    "a disabled control under the band stopped the host from owning the hit"
  )

  let textView = NSTextView(frame: CGRect(x: 0, y: 0, width: 200, height: 24))
  textView.string = "Handle"
  textView.isEditable = false
  textView.isSelectable = false
  textView.isRichText = false
  fixture.content.addSubview(textView, positioned: .below, relativeTo: fixture.host)
  defer { textView.removeFromSuperview() }
  let manager = try #require(textView.layoutManager)
  let container = try #require(textView.textContainer)
  manager.ensureLayout(for: container)
  let glyphRect = manager.boundingRect(
    forGlyphRange: NSRange(location: 0, length: 1), in: container
  )
  try #require(!glyphRect.isEmpty, "the glyph premise never laid out a glyph")
  let textContainerOrigin = textView.textContainerOrigin
  let glyphCenter = CGPoint(
    x: glyphRect.midX + textContainerOrigin.x,
    y: glyphRect.midY + textContainerOrigin.y
  )
  let target = CGPoint(x: bottomPoint.x, y: bottomPoint.y + 2)
  let targetInContent = fixture.host.convert(target, to: fixture.content)
  let placedCenter = textView.convert(glyphCenter, to: fixture.content)
  textView.frame.origin = CGPoint(
    x: textView.frame.origin.x + targetInContent.x - placedCenter.x,
    y: textView.frame.origin.y + targetInContent.y - placedCenter.y
  )
  let movedCenter = textView.convert(glyphCenter, to: fixture.content)
  #expect(
    abs(movedCenter.x - targetInContent.x) <= 0.5
      && abs(movedCenter.y - targetInContent.y) <= 0.5,
    "the glyph premise never placed the glyph centre on the band target"
  )
  let targetInWindow = fixture.host.convert(target, to: nil)
  let textPoint = CGPoint(
    x: textView.convert(targetInWindow, from: nil).x - textContainerOrigin.x,
    y: textView.convert(targetInWindow, from: nil).y - textContainerOrigin.y
  )
  #expect(
    manager.glyphIndex(for: textPoint, in: container) < manager.numberOfGlyphs
      && glyphRect.contains(textPoint),
    "the glyph-containment premise does not hold at the band target"
  )
  #expect(
    fixture.host.usableHandle(
      at: fixture.host.convert(target, to: nil),
      in: fixture.window,
      fixedSide: fixture.fixedSide
    ) == nil,
    "the glyph premise no longer obstructs the resize handle"
  )
}

@Test @MainActor func menuPanelUninstalledHostStopsOwningBandHits() async throws {
  let screen = try #require(NSScreen.main)
  let fixture = await CursorRoutingFixture(screen: screen)
  defer { fixture.tearDown() }
  try await fixture.activateWindow()
  let sidePoint = fixture.bandExpectations[0].point
  #expect(
    fixture.contentHit(atHostPoint: sidePoint) === fixture.host,
    "the installed premise needs the host to own the band hit"
  )
  fixture.host.uninstall()
  #expect(
    fixture.contentHit(atHostPoint: sidePoint) !== fixture.host,
    "an uninstalled host still owned the band hit"
  )
}

@Test @MainActor func menuPanelObstructionProbeHonorsContentSuperviewCoordinates() async throws {
  let screen = try #require(NSScreen.main)
  let fixture = await CursorRoutingFixture(screen: screen)
  defer { fixture.tearDown() }
  try await fixture.activateWindow()
  let bottomPoint = fixture.bandExpectations[1].point
  let control = NSButton(
    frame: CGRect(x: bottomPoint.x - 30, y: bottomPoint.y - 20, width: 60, height: 40)
  )
  control.isEnabled = true
  fixture.content.addSubview(control, positioned: .below, relativeTo: fixture.host)
  defer { control.removeFromSuperview() }

  fixture.content.frame = fixture.content.frame.offsetBy(dx: 0, dy: 24)
  let superview = try #require(fixture.content.superview)
  try #require(
    superview.convert(fixture.content.bounds, from: fixture.content) != fixture.content.bounds,
    "the content-origin premise needs the content root away from its superview origin"
  )
  #expect(
    fixture.host.usableHandle(
      at: fixture.host.convert(bottomPoint, to: nil),
      in: fixture.window,
      fixedSide: fixture.fixedSide
    ) == nil,
    "the obstruction probe missed an enabled control under a content root at a nonzero origin"
  )
  fixture.host.invalidateResizeCursorRegions()
  let advertisedUnderMovedContent = fixture.host.cursorRegistrations().contains {
    $0.rect.contains(bottomPoint)
  }
  #expect(
    !advertisedUnderMovedContent,
    "the native margin map advertised an enabled control under a moved content root"
  )
  #expect(
    fixture.contentHit(atHostPoint: bottomPoint) === control,
    "an enabled control under the band lost the hit once the content root moved"
  )
}

@Test @MainActor func menuPanelDirectCursorUpdateKeepsTheHandleCursorDuringDrag() async throws {
  let screen = try #require(NSScreen.main)
  let fixture = await CursorRoutingFixture(screen: screen)
  defer { fixture.tearDown() }
  try await fixture.activateWindow()
  let bounds = fixture.host.bounds
  let interiorPoint = CGPoint(x: bounds.midX, y: bounds.midY)
  let startPoint = fixture.bandExpectations[1].point

  NSCursor.arrow.set()
  let interiorEvent = try #require(fixture.cursorUpdateEvent(atHostPoint: interiorPoint))
  fixture.host.cursorUpdate(with: interiorEvent)
  #expect(
    NSCursor.current === NSCursor.arrow,
    "an interior native cursorUpdate forced a resize cursor"
  )

  fixture.mouseDown(atHostPoint: startPoint)
  try #require(
    fixture.controller.isTracking,
    "the direct cursorUpdate premise never began a resize"
  )
  let handle = try #require(fixture.controller.currentHandle, "the owned drag lost its handle")
  let expected = fixture.host.cursor(for: handle, fixedSide: fixture.fixedSide)
  NSCursor.arrow.set()
  let draggedPoint = CGPoint(x: startPoint.x, y: startPoint.y + 24)
  let draggedEvent = try #require(fixture.cursorUpdateEvent(atHostPoint: draggedPoint))
  fixture.host.cursorUpdate(with: draggedEvent)
  #expect(
    NSCursor.current === expected,
    "a native cursorUpdate during an owned drag dropped the handle cursor"
  )
}

@Test @MainActor func menuPanelDisabledResizePassesBandHitsThroughToContent() async throws {
  let screen = try #require(NSScreen.main)
  let fixture = await CursorRoutingFixture(screen: screen, canResize: false)
  defer { fixture.tearDown() }
  try await fixture.activateWindow()

  for (name, point, _) in fixture.bandExpectations {
    #expect(
      fixture.contentHit(atHostPoint: point) === fixture.content,
      "\(name) band hit was captured while resizing is disabled"
    )
  }
}

@Test @MainActor func menuPanelHiddenResizeHostStopsOwningBandHits() async throws {
  let screen = try #require(NSScreen.main)
  let fixture = await CursorRoutingFixture(screen: screen)
  defer { fixture.tearDown() }
  try await fixture.activateWindow()
  let sidePoint = fixture.bandExpectations[0].point
  let windowPoint = fixture.host.convert(sidePoint, to: nil)
  let contentSuperview = try #require(fixture.content.superview)
  let superPoint = contentSuperview.convert(windowPoint, from: nil)
  #expect(
    fixture.host.hitTest(superPoint) === fixture.host,
    "the visible premise needs the host to own its band"
  )

  fixture.host.isHidden = true
  #expect(
    fixture.host.hitTest(superPoint) == nil,
    "a hidden host still classified its band as a hit"
  )
  #expect(
    fixture.contentHit(atHostPoint: sidePoint) === fixture.content,
    "a hidden host still captured the band hit"
  )
  fixture.host.isHidden = false
  try #require(
    fixture.host.hitTest(superPoint) === fixture.host,
    "unhiding the host never restored its band hit"
  )

  fixture.host.removeFromSuperview()
  let ancestor = NSView(frame: fixture.content.bounds)
  fixture.content.addSubview(ancestor)
  ancestor.addSubview(fixture.host)
  let ancestorPoint = ancestor.convert(windowPoint, from: nil)
  #expect(
    fixture.host.hitTest(ancestorPoint) === fixture.host,
    "a reparented host stopped owning its band"
  )
  ancestor.isHidden = true
  #expect(
    fixture.host.hitTest(ancestorPoint) == nil,
    "a hidden ancestor still classified the host band as a hit"
  )
  #expect(
    fixture.contentHit(atHostPoint: sidePoint) === fixture.content,
    "a hidden ancestor still let the host capture the band hit"
  )
}

@Test func menuPanelResizeMarginTilesTheParentInteractionBorder() throws {
  let outer = CGRect(x: 100, y: 200, width: 420, height: 430)
  for fixedSide in [MenuPanelFixedSide.right, .left] {
    let layout = try #require(
      MenuPanelResizeGeometry.layout(in: outer, fixedSide: fixedSide)
    )
    let body = layout.bodyBounds
    #expect(layout.outerBounds == outer)
    #expect(layout.fixedSide == fixedSide)
    #expect(body.maxY == outer.maxY)
    #expect(body.minY - outer.minY == 3, "the painted body did not give up the bottom margin")
    #expect(body.width == outer.width - 3)
    #expect(body.height == outer.height - 3)
    switch fixedSide {
    case .left:
      #expect(body.minX == outer.minX)
      #expect(outer.maxX - body.maxX == 3, "the free side is not the right edge")
    case .right:
      #expect(body.maxX == outer.maxX)
      #expect(body.minX - outer.minX == 3, "the free side is not the left edge")
    }

    var coveredArea: CGFloat = 0
    for region in layout.marginRegions {
      #expect(region.rect.minX >= outer.minX && region.rect.maxX <= outer.maxX)
      #expect(region.rect.minY >= outer.minY && region.rect.maxY <= outer.maxY)
      #expect(
        region.rect.intersection(body).isEmpty,
        "a margin region reached inside the painted body"
      )
      coveredArea += region.rect.width * region.rect.height
    }
    for first in layout.marginRegions.indices {
      for second in layout.marginRegions.indices where second > first {
        #expect(
          layout.marginRegions[first].rect.intersection(layout.marginRegions[second].rect)
            .isEmpty,
          "the interaction border was covered twice"
        )
      }
    }
    let marginArea = outer.width * outer.height - body.width * body.height
    #expect(abs(coveredArea - marginArea) <= 0.5, "the interaction border left a gap")

    let paintedBottom = CGPoint(x: outer.midX, y: body.minY - 2)
    #expect(outer.contains(paintedBottom))
    #expect(layout.handle(at: paintedBottom) == .nearBottomCorner)
    let paintedSide = CGPoint(
      x: fixedSide == .left ? body.maxX + 2 : body.minX - 2,
      y: outer.midY
    )
    #expect(outer.contains(paintedSide))
    #expect(layout.handle(at: paintedSide) == .farSide)
    #expect(layout.handle(at: CGPoint(x: body.midX, y: body.midY)) == nil)
    #expect(
      layout.handle(at: CGPoint(x: outer.midX, y: outer.maxY + 1)) == nil,
      "the interaction border escaped the parent frame"
    )
  }
}

@Test @MainActor func menuPanelMarginDragKeepsTheRawPointerDelta() async throws {
  let screen = try #require(NSScreen.main)
  let fixture = await CursorRoutingFixture(screen: screen)
  defer { fixture.tearDown() }
  try await fixture.activateWindow()
  let layout = try #require(
    await fixture.awaitPublishedLayout(),
    "the parent never published its interaction border"
  )
  let parent = fixture.window.frame
  let clickPoint = CGPoint(x: layout.bodyBounds.midX, y: layout.bodyBounds.minY - 2)
  #expect(layout.handle(at: clickPoint) == .nearBottomCorner)
  #expect(
    fixture.contentHit(atHostPoint: CGPoint(x: layout.bodyBounds.midX, y: layout.bodyBounds.midY))
      !== fixture.host,
    "the margin premise needs the painted body in front of the host"
  )
  let observation = await fixture.awaitInputHitAdmission(atHostPoint: clickPoint)
  try #require(
    observation.admitted,
    "the painted-border margin never accepted input: \(observation.diagnostic)"
  )

  let expected = fixture.host.cursor(for: .nearBottomCorner, fixedSide: fixture.fixedSide)
  fixture.setSyntheticLivePointer(atHostPoint: clickPoint)
  NSCursor.arrow.set()
  fixture.hover(atHostPoint: clickPoint)
  #expect(
    NSCursor.current === expected,
    "hovering the painted-border margin never resolved the band cursor"
  )

  let startScreen = fixture.window.convertPoint(
    toScreen: fixture.host.convert(clickPoint, to: nil)
  )
  let startingHeight = parent.height
  let startingWidth = parent.width
  fixture.mouseDown(atHostPoint: clickPoint)
  try #require(fixture.controller.isTracking, "the painted-border margin never began a resize")
  let draggedScreen = CGPoint(x: startScreen.x, y: startScreen.y - 30)
  fixture.drag(toScreenPoint: draggedScreen)
  #expect(
    abs(fixture.window.frame.height - (startingHeight + 30)) <= 1,
    "the margin drag did not keep the raw vertical delta"
  )
  #expect(fixture.window.frame.width == startingWidth, "the bottom margin drag changed the width")
  fixture.mouseUp(atScreenPoint: draggedScreen)
  #expect(fixture.commits.count == 1)
  #expect(!fixture.controller.isTracking, "the released margin drag stayed tracking")
}

@Test @MainActor func menuPanelMarginCornerOwnsTheCornerHandle() async throws {
  let screen = try #require(NSScreen.main)
  let fixture = await CursorRoutingFixture(screen: screen)
  defer { fixture.tearDown() }
  try await fixture.activateWindow()
  let layout = try #require(
    await fixture.awaitPublishedLayout(),
    "the parent never published its interaction border"
  )
  let parent = fixture.window.frame
  let clickPoint = CGPoint(
    x: fixture.fixedSide == .left ? layout.bodyBounds.maxX + 2 : layout.bodyBounds.minX - 2,
    y: layout.bodyBounds.minY - 2
  )
  #expect(layout.handle(at: clickPoint) == .farBottomCorner)
  let observation = await fixture.awaitInputHitAdmission(atHostPoint: clickPoint)
  try #require(
    observation.admitted,
    "the corner margin never accepted input: \(observation.diagnostic)"
  )

  let startScreen = fixture.window.convertPoint(
    toScreen: fixture.host.convert(clickPoint, to: nil)
  )
  let startingWidth = parent.width
  let startingHeight = parent.height
  fixture.mouseDown(atHostPoint: clickPoint)
  try #require(fixture.controller.isTracking, "the corner margin never began a resize")
  try #require(
    fixture.controller.currentHandle == .farBottomCorner,
    "the corner margin did not resolve the corner handle"
  )
  fixture.drag(
    toScreenPoint: CGPoint(
      x: startScreen.x + (fixture.fixedSide == .right ? -20 : 20),
      y: startScreen.y
    )
  )
  #expect(
    abs(fixture.window.frame.width - (startingWidth + 20)) <= 1,
    "the corner margin drag did not keep the raw horizontal delta"
  )
  #expect(
    fixture.window.frame.height == startingHeight,
    "the corner margin drag changed the height without a vertical delta"
  )
}

@Test @MainActor func menuPanelMarginCornerZeroMotionKeepsTheSize() async throws {
  let screen = try #require(NSScreen.main)
  let fixture = await CursorRoutingFixture(screen: screen)
  defer { fixture.tearDown() }
  try await fixture.activateWindow()
  let layout = try #require(
    await fixture.awaitPublishedLayout(),
    "the parent never published its interaction border"
  )
  let parent = fixture.window.frame
  let clickPoint = CGPoint(
    x: fixture.fixedSide == .left ? layout.bodyBounds.maxX + 2 : layout.bodyBounds.minX - 2,
    y: layout.bodyBounds.minY - 2
  )
  let startScreen = fixture.window.convertPoint(
    toScreen: fixture.host.convert(clickPoint, to: nil)
  )
  fixture.mouseDown(atHostPoint: clickPoint)
  try #require(fixture.controller.isTracking, "the corner margin never began a resize")
  fixture.mouseUp(atScreenPoint: startScreen)
  #expect(fixture.commits.count == 1, "the zero-motion margin release did not commit")
  #expect(
    abs(fixture.window.frame.width - parent.width) <= 0.5
      && abs(fixture.window.frame.height - parent.height) <= 0.5,
    "a zero-motion corner margin release changed the panel size"
  )
}

@Test @MainActor func menuPanelMarginStandsDownWhenAForeignChildAppears() async throws {
  let screen = try #require(NSScreen.main)
  let fixture = await CursorRoutingFixture(screen: screen)
  defer { fixture.tearDown() }
  try await fixture.activateWindow()
  let layout = try #require(
    await fixture.awaitPublishedLayout(),
    "the parent never published its interaction border"
  )
  let parent = fixture.window.frame
  let clickPoint = CGPoint(x: layout.bodyBounds.midX, y: layout.bodyBounds.minY - 2)

  let foreign = makeForeignChild(above: parent)
  fixture.window.addChildWindow(foreign, ordered: .above)
  defer { releaseForeignChild(foreign, from: fixture.window) }
  foreign.orderFrontRegardless()

  let boundary = await fixture.awaitApplicationUpdateBoundary()
  try #require(boundary, "the application never reached a real update boundary")
  #expect(
    fixture.attachedChildWindows().count == 1,
    "the resize layer attached a window of its own"
  )
  fixture.mouseDown(atHostPoint: clickPoint)
  #expect(!fixture.controller.isTracking, "a foreign child left the margin grab live")
}

@Test @MainActor func menuPanelMarginStandsDownWhenAVisibleChildIsAttached() async throws {
  let screen = try #require(NSScreen.main)
  let fixture = await CursorRoutingFixture(screen: screen)
  defer { fixture.tearDown() }
  try await fixture.activateWindow()
  let layout = try #require(
    await fixture.awaitPublishedLayout(),
    "the parent never published its interaction border"
  )
  let parent = fixture.window.frame
  let clickPoint = CGPoint(x: layout.bodyBounds.midX, y: layout.bodyBounds.minY - 2)

  let foreign = makeForeignChild(above: parent)
  defer { releaseForeignChild(foreign, from: fixture.window) }
  foreign.orderFrontRegardless()
  fixture.window.addChildWindow(foreign, ordered: .above)

  let boundary = await fixture.awaitApplicationUpdateBoundary()
  try #require(boundary, "the application never reached a real update boundary")
  #expect(
    fixture.attachedChildWindows().count == 1,
    "an already-visible foreign child made the resize layer attach a window"
  )
  fixture.mouseDown(atHostPoint: clickPoint)
  #expect(!fixture.controller.isTracking, "an attached visible child left the margin grab live")
}

@Test @MainActor func menuPanelForeignArrivalDuringAMarginDragCancelsFirst() async throws {
  let screen = try #require(NSScreen.main)
  let fixture = await CursorRoutingFixture(screen: screen)
  defer { fixture.tearDown() }
  try await fixture.activateWindow()
  let layout = try #require(
    await fixture.awaitPublishedLayout(),
    "the parent never published its interaction border"
  )
  let parent = fixture.window.frame
  let clickPoint = CGPoint(x: layout.bodyBounds.midX, y: layout.bodyBounds.minY - 2)
  let startScreen = fixture.window.convertPoint(
    toScreen: fixture.host.convert(clickPoint, to: nil)
  )
  let startingHeight = parent.height
  fixture.mouseDown(atHostPoint: clickPoint)
  try #require(fixture.controller.isTracking, "the margin never began a resize")
  fixture.drag(toScreenPoint: CGPoint(x: startScreen.x, y: startScreen.y - 20))
  try #require(
    fixture.window.frame.height > startingHeight,
    "the margin drag never moved the panel before the foreign child arrived"
  )

  let foreign = makeForeignChild(above: parent)
  defer { releaseForeignChild(foreign, from: fixture.window) }
  fixture.window.addChildWindow(foreign, ordered: .above)
  foreign.orderFrontRegardless()
  let boundary = await fixture.awaitApplicationUpdateBoundary()
  try #require(boundary, "the application never reached a real update boundary")

  #expect(!fixture.controller.isTracking, "a foreign arrival left the margin drag tracking")
  #expect(fixture.commits.isEmpty, "a foreign arrival committed a margin drag")
  #expect(
    abs(fixture.window.frame.height - startingHeight) <= 1,
    "a foreign arrival did not restore the panel geometry the drag started from"
  )
}

@Test @MainActor func menuPanelMarginFollowsLifecycleAndOwnership() async throws {
  let screen = try #require(NSScreen.main)
  let fixture = await CursorRoutingFixture(screen: screen)
  defer { fixture.tearDown() }
  try await fixture.activateWindow()
  let layout = try #require(
    await fixture.awaitPublishedLayout(),
    "the parent never published its interaction border"
  )
  #expect(layout.outerBounds == fixture.host.bounds, "the published border left the parent frame")
  let clickPoint = CGPoint(x: layout.bodyBounds.midX, y: layout.bodyBounds.minY - 2)
  let clickScreen = fixture.window.convertPoint(
    toScreen: fixture.host.convert(clickPoint, to: nil)
  )

  fixture.setCanResize(false)
  await fixture.drainMainQueue()
  #expect(
    fixture.controller.publishedLayout != nil,
    "disabling resize dropped the painted interaction border"
  )
  fixture.mouseDown(atHostPoint: clickPoint)
  #expect(!fixture.controller.isTracking, "a disabled resizer began a margin drag")

  fixture.setCanResize(true)
  await fixture.drainMainQueue()
  fixture.mouseDown(atHostPoint: clickPoint)
  try #require(fixture.controller.isTracking, "the re-enabled resizer never began a margin drag")
  fixture.mouseUp(atScreenPoint: clickScreen)
  #expect(fixture.commits.count == 1)

  let keyTaker = CursorRoutingDispatchSpyWindow(
    contentRect: CGRect(
      x: fixture.window.frame.minX + 40,
      y: fixture.window.frame.minY + 40,
      width: 120,
      height: 120
    ),
    styleMask: .borderless,
    backing: .buffered,
    defer: false
  )
  keyTaker.isReleasedWhenClosed = false
  var isKeyTakerReleased = false
  func releaseKeyTaker() {
    guard !isKeyTakerReleased else { return }
    isKeyTakerReleased = true
    keyTaker.orderOut(nil)
    keyTaker.close()
  }
  defer { releaseKeyTaker() }
  keyTaker.makeKeyAndOrderFront(nil)
  let resignDeadline = ContinuousClock.now + .seconds(2)
  while fixture.window.isKeyWindow, ContinuousClock.now < resignDeadline {
    try? await Task.sleep(for: .milliseconds(20))
  }
  try #require(!fixture.window.isKeyWindow, "the panel never resigned key to the other window")
  #expect(!fixture.controller.isTracking, "resigning key left a margin drag open")
  releaseKeyTaker()

  try await fixture.activateWindow()
  let revived = try #require(
    await fixture.awaitPublishedLayout(),
    "the interaction border never returned after re-keying"
  )
  #expect(revived.fixedSide == fixture.fixedSide)
  fixture.host.uninstall()
  await fixture.drainMainQueue()
  #expect(
    fixture.attachedChildWindows().isEmpty,
    "uninstall left a resize child window attached"
  )
  #expect(
    fixture.controller.publishedLayout == nil,
    "uninstall kept the interaction border published"
  )
}

@Test @MainActor func menuPanelMarginCaptureSurvivesLosingTheBorderUnderThePointer() async throws {
  let screen = try #require(NSScreen.main)
  let fixture = await CursorRoutingFixture(screen: screen)
  defer { fixture.tearDown() }
  try await fixture.activateWindow()
  let layout = try #require(
    await fixture.awaitPublishedLayout(),
    "the parent never published its interaction border"
  )
  let parent = fixture.window.frame
  let clickPoint = CGPoint(x: layout.bodyBounds.midX, y: layout.bodyBounds.minY - 2)
  let startScreen = fixture.window.convertPoint(
    toScreen: fixture.host.convert(clickPoint, to: nil)
  )
  let startingHeight = parent.height
  fixture.mouseDown(atHostPoint: clickPoint)
  try #require(fixture.controller.isTracking, "the margin never began a resize")
  let insideBodyTarget = CGPoint(x: layout.bodyBounds.midX, y: layout.bodyBounds.minY + 30)
  try #require(
    insideBodyTarget.y - layout.bodyBounds.minY >= MenuPanelResizeGeometry.edgeThickness,
    "the capture drag destination must clear the border rim"
  )
  let insideBodyPoint = fixture.window.convertPoint(
    toScreen: fixture.host.convert(insideBodyTarget, to: nil)
  )
  try #require(
    startingHeight - (insideBodyPoint.y - startScreen.y)
      >= MenuPanelResizeGeometry.minimumContentSize.height,
    "the capture drag destination must stay inside the unconstrained raw shrink range"
  )
  fixture.drag(toScreenPoint: insideBodyPoint)
  #expect(
    abs(fixture.window.frame.height - (startingHeight - (insideBodyPoint.y - startScreen.y)))
      <= 1,
    "the margin drag did not keep its raw delta once the pointer left the border"
  )
  let minimumHeight = MenuPanelResizeGeometry.minimumContentSize.height
  let clampedScreen = CGPoint(
    x: insideBodyPoint.x,
    y: startScreen.y + (startingHeight - minimumHeight) + 30
  )
  try #require(
    screen.visibleFrame.contains(clampedScreen),
    "the clamped drag destination must stay on screen"
  )
  fixture.drag(toScreenPoint: clampedScreen)
  #expect(
    abs(fixture.window.frame.height - minimumHeight) <= 1,
    "the clamped drag did not stop at the minimum height"
  )
  #expect(fixture.controller.isTracking, "the clamped drag dropped the interaction")
  let currentHostPoint = fixture.host.convert(
    fixture.window.convertPoint(fromScreen: clampedScreen),
    from: nil
  )
  let currentLayout = try #require(
    MenuPanelResizeGeometry.layout(in: fixture.host.bounds, fixedSide: fixture.fixedSide),
    "the current host bounds no longer form a resize layout"
  )
  #expect(
    currentLayout.bodyBounds.contains(currentHostPoint),
    "the clamped drag did not leave the pointer inside the current body"
  )
  #expect(
    MenuPanelResizeGeometry.handle(
      at: currentHostPoint, in: fixture.host.bounds, fixedSide: fixture.fixedSide
    ) == nil,
    "the clamped drag left the pointer on the current painted border"
  )
  fixture.mouseUp(atScreenPoint: clampedScreen)
  #expect(fixture.commits.count == 1, "a release inside the painted body never finished the resize")
  #expect(!fixture.controller.isTracking, "the release inside the body left the interaction open")
}

@Test @MainActor func menuPanelMarginDisableCancelsTheLiveDrag() async throws {
  let screen = try #require(NSScreen.main)
  let fixture = await CursorRoutingFixture(screen: screen)
  defer { fixture.tearDown() }
  try await fixture.activateWindow()
  let layout = try #require(
    await fixture.awaitPublishedLayout(),
    "the parent never published its interaction border"
  )
  let parent = fixture.window.frame
  let clickPoint = CGPoint(x: layout.bodyBounds.midX, y: layout.bodyBounds.minY - 2)
  fixture.mouseDown(atHostPoint: clickPoint)
  try #require(fixture.controller.isTracking, "the margin never began a resize")
  fixture.setCanResize(false)
  await fixture.drainMainQueue()
  #expect(!fixture.controller.isTracking, "disabling the resizer left the margin drag tracking")
  #expect(fixture.commits.isEmpty, "disabling the resizer committed a size")
  #expect(
    abs(fixture.window.frame.height - parent.height) <= 1,
    "disabling the resizer did not restore the panel geometry"
  )
  #expect(fixture.attachedChildWindows().isEmpty, "disabling the resizer attached a child window")
}

@Test @MainActor func menuPanelMarginFollowsACrossAnchorFlip() async throws {
  let screen = try #require(NSScreen.main)
  let fixture = await CursorRoutingFixture(screen: screen)
  defer { fixture.tearDown() }
  try await fixture.activateWindow()
  let startLayout = try #require(
    await fixture.awaitPublishedLayout(),
    "the parent never published its interaction border"
  )
  #expect(fixture.fixedSide == .right, "the flip premise needs the right-anchored side")
  #expect(startLayout.fixedSide == .right)

  let startPoint = fixture.bandExpectations[0].point
  fixture.mouseDown(atHostPoint: startPoint)
  try #require(fixture.controller.isTracking, "the flip drag never began")
  let statusWindow = try #require(
    fixture.statusButton.window,
    "the flip premise needs the status button in its own window"
  )
  let statusFrame = statusWindow.convertToScreen(
    fixture.statusButton.convert(fixture.statusButton.bounds, to: nil)
  )
  let startScreen = fixture.window.convertPoint(
    toScreen: fixture.host.convert(startPoint, to: nil)
  )
  let targetScreen = CGPoint(x: statusFrame.midX + 6, y: startScreen.y)
  let hostScreenBefore = fixture.window.convertToScreen(
    fixture.host.convert(fixture.host.bounds, to: nil)
  )
  print(
    "DIAG before screen=\(screen.frame) visible=\(screen.visibleFrame) "
      + "window=\(fixture.window.frame) hostScreen=\(hostScreenBefore) "
      + "outer=\(startLayout.outerBounds) body=\(startLayout.bodyBounds) "
      + "startHost=\(startPoint) startScreen=\(startScreen) status=\(statusFrame) "
      + "target=\(targetScreen) bands=\(fixture.bandExpectations.count)"
  )
  fixture.drag(toScreenPoint: targetScreen)
  print(
    "DIAG after window=\(fixture.window.frame) "
      + "hostScreen=\(fixture.window.convertToScreen(fixture.host.convert(fixture.host.bounds, to: nil))) "
      + "side=\(String(describing: fixture.controller.currentFixedSide)) "
      + "isTracking=\(fixture.controller.isTracking) commits=\(fixture.commits)"
  )
  let flippedSide = fixture.controller.currentFixedSide
  try #require(
    flippedSide == .left,
    "the free-edge drag never crossed the anchor: side \(String(describing: flippedSide))"
  )

  await fixture.drainMainQueue()
  let flippedLayout = try #require(
    fixture.controller.publishedLayout,
    "the anchor flip never published an interaction border"
  )
  #expect(flippedLayout.fixedSide == .left, "the painted border did not follow the flipped anchor")
  #expect(
    flippedLayout.outerBounds.maxX - flippedLayout.bodyBounds.maxX == 3,
    "the flipped anchor kept the inset on the anchored edge"
  )
  #expect(
    flippedLayout.bodyBounds.minX == flippedLayout.outerBounds.minX,
    "the flipped anchor moved the painted body off its anchored left edge"
  )
  let clippedBounds = fixture.host.bounds.intersection(fixture.host.visibleRect)
  try #require(!clippedBounds.isEmpty, "the flip premise needs a visible host region")
  try #require(
    clippedBounds != fixture.host.bounds,
    "the flip premise must exercise a clipped visible region"
  )
  #expect(
    fixture.host.bounds.contains(clippedBounds),
    "the clipped capture region is not contained in the host bounds"
  )
  #expect(
    fixture.host.visibleRect.contains(clippedBounds),
    "the clipped capture region is not contained in the visible region"
  )
  #expect(
    fixture.host.cursorRegistrations() == [
      MenuPanelResizeCursorRegistration(
        rect: clippedBounds,
        handle: .farSide,
        fixedSide: .left
      )
    ],
    "the native cursor map kept the pre-flip side while the drag was still captured"
  )
  fixture.host.updateTrackingAreas()
  let captureAreas = fixture.host.trackingAreas.filter {
    $0.options.contains(.cursorUpdate) && (($0.owner as? MenuPanelResizeHostView) === fixture.host)
  }
  #expect(
    captureAreas.map(\.rect) == [clippedBounds],
    "the installed capture area does not cover the clipped visible region"
  )
}

@Test @MainActor func menuPanelNativeCursorRegistrationsTrackThePaintedMarginAndCapture() async throws
{
  let screen = try #require(NSScreen.main)
  let fixture = await CursorRoutingFixture(screen: screen)
  defer { fixture.tearDown() }
  try await fixture.activateWindow()
  let layout = try #require(
    await fixture.awaitPublishedLayout(),
    "the parent never published its interaction border"
  )

  let admittedRegions = MenuPanelResizeGeometry.cursorRegions(
    in: fixture.host.bounds,
    fixedSide: layout.fixedSide
  )
  let hoverRegistrations = fixture.host.cursorRegistrations()
  #expect(hoverRegistrations.count == admittedRegions.count)
  #expect(hoverRegistrations.allSatisfy { $0.fixedSide == layout.fixedSide })
  #expect(
    hoverRegistrations.map(\.rect) == admittedRegions.map(\.rect),
    "the native map stopped matching the admitted seven-point cursor regions"
  )
  #expect(
    abs(layout.bodyBounds.minY - layout.outerBounds.minY - 3) <= 0.0001,
    "the painted bottom margin stopped being three points"
  )
  let admittedBandProbe = CGPoint(
    x: fixture.host.bounds.midX,
    y: fixture.host.bounds.minY + 6
  )
  #expect(
    admittedRegions.contains { $0.rect.contains(admittedBandProbe) },
    "the admitted seven-point band lost its cursor coverage"
  )
  #expect(
    !layout.marginRegions.contains { $0.rect.contains(admittedBandProbe) },
    "the painted three-point margin grew into the admitted band"
  )

  let bottomPoint = CGPoint(x: layout.bodyBounds.midX, y: layout.bodyBounds.minY - 2)
  let startScreen = fixture.window.convertPoint(
    toScreen: fixture.host.convert(bottomPoint, to: nil)
  )
  fixture.mouseDown(atHostPoint: bottomPoint)
  try #require(fixture.controller.isTracking, "the margin never began a resize")
  #expect(
    fixture.host.cursorRegistrations() == [
      MenuPanelResizeCursorRegistration(
        rect: fixture.host.bounds,
        handle: .nearBottomCorner,
        fixedSide: layout.fixedSide
      )
    ],
    "a zero-motion capture kept the hover rectangles on the native map"
  )

  fixture.mouseUp(atScreenPoint: startScreen)
  #expect(!fixture.controller.isTracking, "the released margin drag stayed tracking")
  let releasedRegistrations = fixture.host.cursorRegistrations()
  #expect(releasedRegistrations.count == admittedRegions.count)
  #expect(releasedRegistrations.allSatisfy { $0.fixedSide == layout.fixedSide })
  let keptCaptureRect = releasedRegistrations.contains { $0.rect == fixture.host.bounds }
  #expect(
    !keptCaptureRect,
    "the released capture left its whole-bounds rectangle on the native map"
  )
}

@Test @MainActor func menuPanelCursorUpdateLeavesThePaintedMarginToTheNativeHost() async throws {
  let screen = try #require(NSScreen.main)
  let fixture = await CursorRoutingFixture(screen: screen)
  defer { fixture.tearDown() }
  try await fixture.activateWindow()
  let layout = try #require(
    await fixture.awaitPublishedLayout(),
    "the parent never published its interaction border"
  )

  let marginPoint = CGPoint(x: layout.bodyBounds.midX, y: layout.bodyBounds.minY - 2)
  #expect(
    layout.handle(at: marginPoint) != nil,
    "the cursor routing premise needs a painted-margin point"
  )
  #expect(
    fixture.host.routesCursorToNativeOwner(
      at: fixture.host.convert(marginPoint, to: nil),
      in: fixture.window
    ),
    "the painted margin consumed its cursorUpdate instead of leaving it to the native host"
  )

  let insidePoint = CGPoint(x: layout.bodyBounds.midX, y: layout.outerBounds.minY + 5)
  #expect(
    layout.handle(at: insidePoint) == nil,
    "the inside-band premise needs a point outside the painted margin"
  )
  #expect(
    MenuPanelResizeGeometry.handle(
      at: insidePoint,
      in: layout.outerBounds,
      fixedSide: layout.fixedSide
    ) == .nearBottomCorner,
    "the inside-band premise needs the seven-point rim outside the painted margin"
  )
  #expect(
    fixture.host.routesCursorToNativeOwner(
      at: fixture.host.convert(insidePoint, to: nil),
      in: fixture.window
    ),
    "the admitted inside rim stopped delegating to the native host"
  )
  fixture.host.updateTrackingAreas()
  #expect(
    fixture.host.trackingAreas.contains {
      $0.owner === fixture.host && $0.options.contains(.cursorUpdate)
        && $0.rect.contains(insidePoint)
    },
    "the admitted inside rim has no installed owned native cursor area"
  )

  let startScreen = fixture.window.convertPoint(
    toScreen: fixture.host.convert(marginPoint, to: nil)
  )
  fixture.mouseDown(atHostPoint: marginPoint)
  try #require(fixture.controller.isTracking, "the margin never began a resize")
  #expect(
    !fixture.host.routesCursorToNativeOwner(
      at: fixture.host.convert(marginPoint, to: nil),
      in: fixture.window
    ),
    "a captured drag handed its cursorUpdate to the native host"
  )
  fixture.mouseUp(atScreenPoint: startScreen)
  #expect(!fixture.controller.isTracking, "the released margin drag stayed tracking")

  let control = NSButton(
    frame: CGRect(
      x: marginPoint.x - 30,
      y: marginPoint.y - 20,
      width: 60,
      height: 40
    )
  )
  control.isEnabled = true
  fixture.content.addSubview(control)
  defer { control.removeFromSuperview() }
  fixture.host.invalidateResizeCursorRegions()
  #expect(
    !fixture.host.routesCursorToNativeOwner(
      at: fixture.host.convert(marginPoint, to: nil),
      in: fixture.window
    ),
    "an enabled control under the painted margin still routed its cursor to the native host"
  )
}

@Test @MainActor func menuPanelNativeCursorRegistrationsStandDownWhenNotEligible() async throws {
  let screen = try #require(NSScreen.main)
  let fixture = await CursorRoutingFixture(screen: screen)
  defer { fixture.tearDown() }
  try await fixture.activateWindow()
  let layout = try #require(
    await fixture.awaitPublishedLayout(),
    "the parent never published its interaction border"
  )
  let bottomPoint = CGPoint(x: layout.bodyBounds.midX, y: layout.bodyBounds.minY - 2)

  fixture.mouseDown(atHostPoint: bottomPoint)
  try #require(fixture.controller.isTracking, "the margin never began a resize")
  #expect(
    fixture.host.cursorRegistrations().count == 1,
    "the eligible capture stopped advertising its handle"
  )

  fixture.setCanResize(false)
  #expect(
    fixture.host.cursorRegistrations().isEmpty,
    "a disabled resizer kept advertising the captured handle"
  )
  await fixture.drainMainQueue()
  #expect(!fixture.controller.isTracking, "disabling the resizer left the drag tracking")

  fixture.setCanResize(true)
  await fixture.drainMainQueue()
  #expect(
    fixture.host.cursorRegistrations().count
      == MenuPanelResizeGeometry.cursorRegions(
        in: fixture.host.bounds,
        fixedSide: layout.fixedSide
      ).count,
    "the re-enabled resizer never restored its painted margin"
  )

  let foreign = makeForeignChild(above: fixture.window.frame)
  fixture.window.addChildWindow(foreign, ordered: .above)
  foreign.orderFrontRegardless()
  #expect(
    fixture.host.cursorRegistrations().isEmpty,
    "a visible foreign child left the native margin advertised"
  )
  let commitsBeforeForeignGrab = fixture.commits.count
  fixture.mouseDown(atHostPoint: bottomPoint)
  #expect(
    !fixture.controller.isTracking,
    "a foreign child left a stale registration grabbing the margin"
  )
  #expect(fixture.commits.count == commitsBeforeForeignGrab)
  releaseForeignChild(foreign, from: fixture.window)
  #expect(
    fixture.host.cursorRegistrations().count
      == MenuPanelResizeGeometry.cursorRegions(
        in: fixture.host.bounds,
        fixedSide: layout.fixedSide
      ).count,
    "the released foreign child never restored the painted margin"
  )

  fixture.window.orderOut(nil)
  await fixture.drainMainQueue()
  #expect(
    fixture.host.cursorRegistrations().isEmpty,
    "a hidden parent kept advertising its painted margin"
  )

  fixture.window.orderFront(nil)
  try await fixture.activateWindow()
  await fixture.drainMainQueue()
  #expect(
    fixture.host.cursorRegistrations().count
      == MenuPanelResizeGeometry.cursorRegions(
        in: fixture.host.bounds,
        fixedSide: layout.fixedSide
      ).count,
    "the repainted parent never restored its native margin"
  )

  fixture.host.uninstall()
  #expect(
    fixture.host.cursorRegistrations().isEmpty,
    "an uninstalled host kept advertising its painted margin"
  )
}

@Test @MainActor func menuPanelMarginTeardownLeavesNoOwnedChildren() async throws {
  let screen = try #require(NSScreen.main)
  let fixture = await CursorRoutingFixture(screen: screen)
  defer { fixture.tearDown() }
  try await fixture.activateWindow()
  try #require(
    await fixture.awaitPublishedLayout() != nil,
    "the parent never published its interaction border"
  )

  fixture.window.orderOut(nil)
  await fixture.drainMainQueue()
  #expect(
    fixture.attachedChildWindows().isEmpty,
    "hiding the panel attached a resize child window"
  )

  fixture.host.uninstall()
  await fixture.drainMainQueue()
  #expect(
    fixture.attachedChildWindows().isEmpty,
    "uninstall attached a resize child window"
  )
  #expect(
    fixture.controller.publishedLayout == nil,
    "uninstall kept the interaction border published"
  )
}

private final class AppUpdateBoundaryCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0

  func increment() {
    lock.lock()
    value &+= 1
    lock.unlock()
  }

  var count: Int {
    lock.lock()
    defer { lock.unlock() }
    return value
  }
}

@MainActor
private func makeForeignChild(above parentFrame: CGRect) -> NSPanel {
  let panel = NSPanel(
    contentRect: CGRect(x: parentFrame.minX, y: parentFrame.minY - 40, width: 120, height: 30),
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false
  )
  panel.isOpaque = false
  panel.backgroundColor = .clear
  panel.hasShadow = false
  panel.isReleasedWhenClosed = false
  panel.animationBehavior = .none
  return panel
}

@MainActor
private func releaseForeignChild(_ panel: NSPanel, from parent: NSWindow) {
  parent.removeChildWindow(panel)
  panel.orderOut(nil)
  panel.close()
}

@MainActor
private final class CursorRoutingDispatchSpyWindow: NSWindow {
  private(set) var dispatchedTypes: [NSEvent.EventType] = []
  var syntheticMouseLocation: CGPoint?

  override var canBecomeKey: Bool { true }

  override var mouseLocationOutsideOfEventStream: NSPoint {
    syntheticMouseLocation ?? super.mouseLocationOutsideOfEventStream
  }

  override func sendEvent(_ event: NSEvent) {
    dispatchedTypes.append(event.type)
    super.sendEvent(event)
  }

  func resetDispatchedTypes() {
    dispatchedTypes.removeAll()
  }
}

@MainActor
private final class CursorRoutingTrackingChild: NSView {
  private(set) var mouseMovedCount = 0
  private var hoverTrackingArea: NSTrackingArea?

  override var acceptsFirstResponder: Bool { true }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverTrackingArea {
      removeTrackingArea(hoverTrackingArea)
    }
    let area = NSTrackingArea(
      rect: .zero,
      options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(area)
    hoverTrackingArea = area
  }

  override func mouseMoved(with event: NSEvent) {
    mouseMovedCount += 1
    NSCursor.arrow.set()
    super.mouseMoved(with: event)
  }

  func resetMouseMovedCount() {
    mouseMovedCount = 0
  }
}

@MainActor
private final class CursorRoutingFixture {
  let window: CursorRoutingDispatchSpyWindow
  let content: CursorRoutingTrackingChild
  let host: MenuPanelResizeHostView
  let statusWindow: NSWindow
  let statusButton: NSStatusBarButton
  let geometryStore: MenuPanelGeometryStore
  let controller = MenuPanelResizeController()
  private(set) var fixedSide: MenuPanelFixedSide = .right
  private(set) var commits: [CGSize] = []
  private let preferredSize: CGSize
  private var eventNumber = 24_000
  private var lastHoveredCursorArea: NSTrackingArea?
  private var isTornDown = false

  init(
    screen: NSScreen,
    contentSize: CGSize = CGSize(width: 420, height: 430),
    canResize: Bool = true
  ) async {
    let frame = CGRect(
      x: (screen.visibleFrame.midX - contentSize.width / 2).rounded(),
      y: (screen.visibleFrame.midY - contentSize.height / 2).rounded(),
      width: contentSize.width,
      height: contentSize.height
    )
    preferredSize = contentSize
    window = CursorRoutingDispatchSpyWindow(
      contentRect: frame,
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    content = CursorRoutingTrackingChild(frame: CGRect(origin: .zero, size: contentSize))
    host = MenuPanelResizeHostView(controller: controller)
    host.frame = content.bounds
    let statusRoot = NSView(frame: CGRect(x: 0, y: 0, width: 80, height: 40))
    statusButton = NSStatusBarButton(frame: CGRect(x: 10, y: 6, width: 34, height: 22))
    statusRoot.addSubview(statusButton)
    let statusWindow = NSWindow(
      contentRect: CGRect(x: frame.maxX - 10, y: frame.maxY + 14, width: 80, height: 40),
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    statusWindow.contentView = statusRoot
    self.statusWindow = statusWindow
    geometryStore = MenuPanelGeometryStore(windows: { [statusWindow] })

    host.configure(
      geometryStore: geometryStore,
      preferredSize: contentSize,
      canResize: canResize,
      onCommit: { [weak self] size in self?.commits.append(size) }
    )
    content.addSubview(host)
    window.contentView = content
    window.makeKeyAndOrderFront(nil)
    host.installIfNeeded()
    content.updateTrackingAreas()
    #expect(window.makeFirstResponder(content), "fixture content never accepted first responder")
    await settle()
    alignStatusButton()
    await settle()
  }

  var bandExpectations: [(name: String, point: CGPoint, cursor: NSCursor)] {
    let bounds = host.bounds
    let farEdgeX = fixedSide == .left ? bounds.maxX - 3 : bounds.minX + 3
    return [
      (
        "side",
        CGPoint(x: farEdgeX, y: bounds.midY),
        host.cursor(for: .farSide, fixedSide: fixedSide)
      ),
      (
        "bottom",
        CGPoint(x: bounds.midX, y: bounds.minY + 2),
        host.cursor(for: .nearBottomCorner, fixedSide: fixedSide)
      ),
      (
        "corner",
        CGPoint(x: farEdgeX, y: bounds.minY + 2),
        host.cursor(for: .farBottomCorner, fixedSide: fixedSide)
      ),
    ]
  }

  private func send(_ type: NSEvent.EventType, atHostPoint point: CGPoint) {
    eventNumber += 1
    guard
      let event = NSEvent.mouseEvent(
        with: type,
        location: host.convert(point, to: nil),
        modifierFlags: [],
        timestamp: TimeInterval(eventNumber) / 100,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: eventNumber,
        clickCount: 1,
        pressure: type == .leftMouseUp ? 0 : 1
      )
    else {
      Issue.record("could not create \(type) event")
      return
    }
    NSApplication.shared.sendEvent(event)
  }

  private func send(_ type: NSEvent.EventType, atScreenPoint point: CGPoint) {
    send(type, atHostPoint: host.convert(window.convertPoint(fromScreen: point), from: nil))
  }

  func nativeCursorUpdate(atHostPoint point: CGPoint) {
    host.updateTrackingAreas()
    let previousArea = lastHoveredCursorArea
    let area = host.trackingAreas.first {
      $0.options.contains(.cursorUpdate) && $0.rect.contains(point)
        && ($0.owner as? MenuPanelResizeHostView) === host
    }
    lastHoveredCursorArea = area
    guard
      host.window === window,
      area != nil || previousArea != nil,
      let event = cursorUpdateEvent(atHostPoint: point)
    else { return }
    host.cursorUpdate(with: event)
  }

  func hover(atHostPoint point: CGPoint) {
    setSyntheticLivePointer(atHostPoint: point)
    eventNumber += 1
    guard
      let event = NSEvent.mouseEvent(
        with: .mouseMoved,
        location: host.convert(point, to: nil),
        modifierFlags: [],
        timestamp: TimeInterval(eventNumber) / 100,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: eventNumber,
        clickCount: 1,
        pressure: 1
      )
    else {
      Issue.record("could not create mouseMoved event")
      return
    }
    NSApplication.shared.sendEvent(event)
    nativeCursorUpdate(atHostPoint: point)
  }

  func exit(atHostPoint point: CGPoint) {
    eventNumber += 1
    guard
      let event = NSEvent.enterExitEvent(
        with: .mouseExited,
        location: host.convert(point, to: nil),
        modifierFlags: [],
        timestamp: TimeInterval(eventNumber) / 100,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: eventNumber,
        trackingNumber: 0,
        userData: nil
      )
    else {
      Issue.record("could not create mouseExited event")
      return
    }
    NSApplication.shared.sendEvent(event)
  }

  func mouseDown(atHostPoint point: CGPoint) {
    send(.leftMouseDown, atHostPoint: point)
  }

  func drag(toScreenPoint point: CGPoint) {
    send(.leftMouseDragged, atScreenPoint: point)
  }

  func mouseUp(atScreenPoint point: CGPoint) {
    send(.leftMouseUp, atScreenPoint: point)
  }

  func cursorUpdateEvent(atHostPoint point: CGPoint) -> NSEvent? {
    eventNumber += 1
    return NSEvent.enterExitEvent(
      with: .cursorUpdate,
      location: host.convert(point, to: nil),
      modifierFlags: [],
      timestamp: TimeInterval(eventNumber) / 100,
      windowNumber: window.windowNumber,
      context: nil,
      eventNumber: eventNumber,
      trackingNumber: 0,
      userData: nil
    )
  }

  func setSyntheticLivePointer(atHostPoint point: CGPoint?) {
    window.syntheticMouseLocation = point.map { host.convert($0, to: nil) }
  }

  func setCanResize(_ canResize: Bool) {
    host.configure(
      geometryStore: geometryStore,
      preferredSize: preferredSize,
      canResize: canResize,
      onCommit: { [weak self] size in self?.commits.append(size) }
    )
  }

  func attachedChildWindows() -> [NSWindow] {
    window.childWindows ?? []
  }

  func awaitPublishedLayout(timeout: Duration = .seconds(2)) async -> MenuPanelResizeLayout? {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
      if let layout = controller.publishedLayout { return layout }
      host.layoutSubtreeIfNeeded()
      try? await Task.sleep(for: .milliseconds(20))
    }
    return controller.publishedLayout
  }

  func postApplicationUpdateBoundary() {
    guard
      let event = NSEvent.otherEvent(
        with: .applicationDefined,
        location: .zero,
        modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: 0,
        context: nil,
        subtype: 0,
        data1: 0,
        data2: 0
      )
    else {
      Issue.record("could not build an application update boundary event")
      return
    }
    NSApplication.shared.postEvent(event, atStart: false)
  }

  func awaitApplicationUpdateBoundary(timeout: Duration = .seconds(2)) async -> Bool {
    let counter = AppUpdateBoundaryCounter()
    let token = NotificationCenter.default.addObserver(
      forName: NSApplication.didUpdateNotification,
      object: nil,
      queue: .main
    ) { _ in counter.increment() }
    defer { NotificationCenter.default.removeObserver(token) }
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
      if counter.count > 0 { return true }
      postApplicationUpdateBoundary()
      try? await Task.sleep(for: .milliseconds(20))
    }
    return counter.count > 0
  }

  func mouseEvent(
    _ type: NSEvent.EventType,
    atScreenPoint point: CGPoint,
    window: NSWindow
  ) -> NSEvent? {
    eventNumber += 1
    let location = window.convertPoint(fromScreen: point)
    switch type {
    case .mouseEntered, .mouseExited:
      return NSEvent.enterExitEvent(
        with: type,
        location: location,
        modifierFlags: [],
        timestamp: TimeInterval(eventNumber) / 100,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: eventNumber,
        trackingNumber: 0,
        userData: nil
      )
    default:
      return NSEvent.mouseEvent(
        with: type,
        location: location,
        modifierFlags: [],
        timestamp: TimeInterval(eventNumber) / 100,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: eventNumber,
        clickCount: 1,
        pressure: type == .leftMouseUp ? 0 : 1
      )
    }
  }

  func setSyntheticLivePointerInWindow(_ point: CGPoint?) {
    window.syntheticMouseLocation = point
  }

  struct InputHitObservation {
    let hostPoint: CGPoint
    let windowPoint: CGPoint
    let screenPoint: CGPoint
    let topmostWindowNumber: Int
    let ownWindowNumber: Int
    let inBounds: Bool

    var admitted: Bool { topmostWindowNumber == ownWindowNumber && inBounds }

    var diagnostic: String {
      "host \(hostPoint) window \(windowPoint) screen \(screenPoint) "
        + "topmost \(topmostWindowNumber) own \(ownWindowNumber) inBounds \(inBounds)"
    }
  }

  func observeInputHit(atHostPoint point: CGPoint) -> InputHitObservation {
    let windowPoint = host.convert(point, to: nil)
    let screenPoint = window.convertPoint(toScreen: windowPoint)
    return InputHitObservation(
      hostPoint: point,
      windowPoint: windowPoint,
      screenPoint: screenPoint,
      topmostWindowNumber: NSWindow.windowNumber(at: screenPoint, belowWindowWithWindowNumber: 0),
      ownWindowNumber: window.windowNumber,
      inBounds: host.bounds.contains(point)
    )
  }

  func awaitInputHitAdmission(atHostPoint point: CGPoint) async -> InputHitObservation {
    let deadline = ContinuousClock.now + .seconds(1.5)
    var observation = observeInputHit(atHostPoint: point)
    while !observation.admitted, ContinuousClock.now < deadline {
      try? await Task.sleep(for: .milliseconds(50))
      observation = observeInputHit(atHostPoint: point)
    }
    return observation
  }

  func activateWindow() async throws {
    try #require(NSApplication.shared.isActive, "the fixture application lost activation")
    window.makeKeyAndOrderFront(nil)
    let deadline = ContinuousClock.now + .seconds(2)
    while !window.isKeyWindow, ContinuousClock.now < deadline {
      try #require(NSApplication.shared.isActive, "the fixture application lost activation")
      try? await Task.sleep(for: .milliseconds(50))
    }
    try #require(
      NSApplication.shared.isActive && window.isKeyWindow,
      "the guarded cursor refresh needs the fixture window to be the active key window"
    )
  }

  func resetObservations() {
    window.resetDispatchedTypes()
    content.resetMouseMovedCount()
  }

  func contentHit(atHostPoint point: CGPoint) -> NSView? {
    guard let contentView = window.contentView else { return nil }
    let windowPoint = host.convert(point, to: nil)
    let superPoint = contentView.superview.map { $0.convert(windowPoint, from: nil) }
    return contentView.hitTest(superPoint ?? windowPoint)
  }

  func drainMainQueue() async {
    for _ in 0..<4 {
      host.layoutSubtreeIfNeeded()
      await Task.yield()
    }
  }

  func tearDown() {
    guard !isTornDown else { return }
    isTornDown = true
    host.uninstall()
    window.contentView = nil
    window.orderOut(nil)
    NSCursor.arrow.set()
  }

  private func alignStatusButton() {
    let panel = window.frame
    statusWindow.setFrameOrigin(
      CGPoint(x: panel.maxX - statusButton.frame.maxX, y: statusWindow.frame.origin.y)
    )
    guard let statusLabelFrame = geometryStore.cachedStatusButton?.screenFrame else {
      fixedSide = .right
      return
    }
    fixedSide =
      MenuPanelResizeGeometry.anchoredSide(
        panelFrame: panel,
        statusLabelFrame: statusLabelFrame
      ) ?? .right
  }

  private func settle() async {
    for _ in 0..<5 {
      host.layoutSubtreeIfNeeded()
      await Task.yield()
    }
  }
}

@Test @MainActor func menuPanelModernCursorAreasCarryTheAdmittedSpecAndRetainOnEqualUpdate()
  async throws
{
  let screen = try #require(NSScreen.main)
  let fixture = await CursorRoutingFixture(screen: screen)
  defer { fixture.tearDown() }
  try await fixture.activateWindow()
  await fixture.drainMainQueue()

  func cursorAreas() -> [NSTrackingArea] {
    fixture.host.trackingAreas.filter { $0.options.contains(.cursorUpdate) }
  }

  let specs = fixture.host.cursorRegistrations(fresh: true)
  try #require(!specs.isEmpty, "the admitted host published no modern cursor spec")
  let areas = cursorAreas()
  #expect(areas.count == specs.count, "the installed areas do not match the admitted spec")
  #expect(
    areas.map(\.rect) == specs.map(\.rect),
    "the installed areas do not carry the clipped admitted rects"
  )
  for area in areas {
    #expect(area.owner === fixture.host, "an admitted area was installed for another owner")
    #expect(
      area.options.contains(.cursorUpdate),
      "an admitted area stopped carrying cursorUpdate"
    )
    #expect(
      area.options.contains(.mouseEnteredAndExited),
      "an admitted area stopped carrying entered and exited"
    )
    #expect(area.options.contains(.mouseMoved), "an admitted area stopped carrying mouseMoved")
    #expect(
      area.options.contains(.activeInKeyWindow),
      "an admitted area stopped deferring native activity to key and active"
    )
    #expect(
      !area.options.contains(.activeAlways),
      "an admitted area bypassed key and active gating"
    )
    #expect(area.userInfo == nil, "an admitted area carried unexpected user info")
  }

  let identities = areas.map { ObjectIdentifier($0) }
  fixture.host.updateTrackingAreas()
  #expect(
    cursorAreas().map { ObjectIdentifier($0) } == identities,
    "an equal spec rebuilt its areas instead of retaining them"
  )
  #expect(
    fixture.host.cursorRegistrations(fresh: true) == specs,
    "an equal update changed the admitted spec"
  )
}

@Test @MainActor func menuPanelModernCursorAreasReplaceForGeometryAndStationaryObstructions()
  async throws
{
  let screen = try #require(NSScreen.main)
  let fixture = await CursorRoutingFixture(screen: screen)
  defer { fixture.tearDown() }
  try await fixture.activateWindow()
  await fixture.drainMainQueue()

  func cursorAreas() -> [NSTrackingArea] {
    fixture.host.trackingAreas.filter { $0.options.contains(.cursorUpdate) }
  }

  let bounds = fixture.host.bounds
  let initialSpecs = fixture.host.cursorRegistrations(fresh: true)
  try #require(!initialSpecs.isEmpty, "the admitted host published no modern cursor spec")

  let sideBandPoint = CGPoint(
    x: fixture.fixedSide == .left ? bounds.maxX - 6 : bounds.minX + 6,
    y: bounds.midY
  )
  let control = NSButton(
    frame: CGRect(
      x: sideBandPoint.x - (fixture.fixedSide == .left ? 50 : 10),
      y: sideBandPoint.y - 20,
      width: 60,
      height: 40
    )
  )
  control.isEnabled = true
  fixture.content.addSubview(control, positioned: .below, relativeTo: fixture.host)
  try #require(
    fixture.contentHit(atHostPoint: sideBandPoint) === control,
    "the obstruction premise needs an enabled control under the admitted rim"
  )
  let controlRect = fixture.host.convert(control.bounds, from: control)

  fixture.setCanResize(true)
  await fixture.drainMainQueue()

  let obstructedSpecs = fixture.host.cursorRegistrations(fresh: true)
  let obstructedAreas = cursorAreas()
  #expect(
    obstructedSpecs.count > initialSpecs.count,
    "a stationary enabled control never split the admitted rim"
  )
  #expect(
    obstructedAreas.map(\.rect) == obstructedSpecs.map(\.rect),
    "the obstruction refresh installed a different area set"
  )
  #expect(
    obstructedAreas.allSatisfy { !$0.rect.intersects(controlRect) },
    "an installed area still covered the enabled control"
  )

  control.removeFromSuperview()
  fixture.setCanResize(true)
  await fixture.drainMainQueue()
  #expect(
    fixture.host.cursorRegistrations(fresh: true) == initialSpecs,
    "removing the control never restored the admitted rim spec"
  )
  #expect(
    cursorAreas().map(\.rect) == initialSpecs.map(\.rect),
    "removing the control never restored the admitted rim areas"
  )

  let textView = NSTextView(frame: CGRect(x: 0, y: 0, width: 200, height: 24))
  textView.string = "Handle"
  textView.isEditable = false
  textView.isSelectable = false
  textView.isRichText = false
  fixture.content.addSubview(textView, positioned: .below, relativeTo: fixture.host)
  let manager = try #require(textView.layoutManager)
  let container = try #require(textView.textContainer)
  manager.ensureLayout(for: container)
  let glyphRect = manager.boundingRect(
    forGlyphRange: NSRange(location: 0, length: 1), in: container
  )
  try #require(!glyphRect.isEmpty, "the glyph premise never laid out a glyph")
  let bottomBandPoint = CGPoint(x: bounds.midX, y: bounds.minY + 6)
  let textContainerOrigin = textView.textContainerOrigin
  let targetInContent = fixture.host.convert(bottomBandPoint, to: fixture.content)
  let placedCenter = textView.convert(
    CGPoint(
      x: glyphRect.midX + textContainerOrigin.x,
      y: glyphRect.midY + textContainerOrigin.y
    ),
    to: fixture.content
  )
  textView.frame.origin = CGPoint(
    x: textView.frame.origin.x + targetInContent.x - placedCenter.x,
    y: textView.frame.origin.y + targetInContent.y - placedCenter.y
  )
  try #require(
    fixture.host.usableHandle(
      at: fixture.host.convert(bottomBandPoint, to: nil),
      in: fixture.window,
      fixedSide: fixture.fixedSide
    ) == nil,
    "the glyph premise no longer obstructs the admitted bottom rim"
  )

  fixture.setCanResize(true)
  await fixture.drainMainQueue()
  let glyphSpecs = fixture.host.cursorRegistrations(fresh: true)
  #expect(
    glyphSpecs != initialSpecs,
    "a stationary laid-out glyph never changed the admitted rim spec"
  )
  #expect(
    cursorAreas().map(\.rect) == glyphSpecs.map(\.rect),
    "the glyph refresh installed a different area set"
  )
  textView.removeFromSuperview()
  fixture.setCanResize(true)
  await fixture.drainMainQueue()

  let shrunk = CGRect(
    origin: .zero,
    size: CGSize(width: bounds.width - 40, height: bounds.height - 40)
  )
  fixture.host.frame = shrunk
  fixture.host.needsLayout = true
  fixture.host.layoutSubtreeIfNeeded()
  await fixture.drainMainQueue()
  let resizedSpecs = fixture.host.cursorRegistrations(fresh: true)
  try #require(!resizedSpecs.isEmpty, "the resized host published no modern cursor spec")
  #expect(
    resizedSpecs.allSatisfy { shrunk.contains($0.rect) },
    "a resized host published rim areas outside its own bounds"
  )
  #expect(
    cursorAreas().map(\.rect) == resizedSpecs.map(\.rect),
    "the resized host installed a stale area set"
  )
}

@Test @MainActor func menuPanelModernCursorAreasFollowCaptureAndHoverRestore()
  async throws
{
  let screen = try #require(NSScreen.main)
  let fixture = await CursorRoutingFixture(screen: screen)
  defer { fixture.tearDown() }
  try await fixture.activateWindow()
  await fixture.drainMainQueue()

  func cursorAreas() -> [NSTrackingArea] {
    fixture.host.trackingAreas.filter { $0.options.contains(.cursorUpdate) }
  }

  let bounds = fixture.host.bounds
  let bandPoint = CGPoint(x: bounds.midX, y: bounds.minY + 6)
  let hoverSpecs = fixture.host.cursorRegistrations(fresh: true)
  try #require(hoverSpecs.count > 1, "the admitted host never published more than one rim piece")
  try #require(
    fixture.host.usableHandle(
      at: fixture.host.convert(bandPoint, to: nil),
      in: fixture.window,
      fixedSide: fixture.fixedSide
    ) == .nearBottomCorner,
    "the capture premise needs an admitted bottom rim point"
  )

  fixture.mouseDown(atHostPoint: bandPoint)
  try #require(fixture.controller.isTracking, "the admitted rim never began a resize")
  fixture.host.updateTrackingAreas()
  await fixture.drainMainQueue()

  let captureHandle = try #require(fixture.controller.currentHandle, "the capture lost its handle")
  let captureSpecs = fixture.host.cursorRegistrations(fresh: true)
  let clip = bounds.intersection(fixture.host.visibleRect)
  #expect(captureSpecs.count == 1, "a captured host published more than one area spec")
  #expect(captureSpecs.first?.handle == captureHandle, "the captured area lost its handle")
  #expect(captureSpecs.first?.rect == clip, "the captured area stopped covering the clipped host")
  let captureAreas = cursorAreas()
  #expect(captureAreas.count == 1, "a captured host installed more than one area")
  #expect(
    captureAreas.first?.rect == clip,
    "the installed capture area does not cover the clipped host"
  )

  let startScreen = fixture.window.convertPoint(
    toScreen: fixture.host.convert(bandPoint, to: nil)
  )
  fixture.mouseUp(atScreenPoint: startScreen)
  #expect(!fixture.controller.isTracking, "the released rim drag stayed tracking")
  fixture.host.updateTrackingAreas()
  await fixture.drainMainQueue()

  let restoredSpecs = fixture.host.cursorRegistrations(fresh: true)
  #expect(restoredSpecs != captureSpecs, "the released host kept its capture area spec")
  #expect(restoredSpecs.count > 1, "the released host never restored its split rim spec")
  #expect(
    restoredSpecs.contains { $0.handle == .nearBottomCorner },
    "the released host never restored its bottom rim piece"
  )
  #expect(
    cursorAreas().map(\.rect) == restoredSpecs.map(\.rect),
    "the released host installed a stale area set"
  )
}

@Test @MainActor func menuPanelModernCursorAreasRemoveWhenStructurallyIneligible()
  async throws
{
  let screen = try #require(NSScreen.main)
  let fixture = await CursorRoutingFixture(screen: screen)
  defer { fixture.tearDown() }
  try await fixture.activateWindow()
  await fixture.drainMainQueue()

  func cursorAreas() -> [NSTrackingArea] {
    fixture.host.trackingAreas.filter { $0.options.contains(.cursorUpdate) }
  }

  let installedSpecs = fixture.host.cursorRegistrations(fresh: true)
  try #require(!installedSpecs.isEmpty, "the admitted host published no modern cursor spec")
  try #require(
    cursorAreas().count == installedSpecs.count,
    "the admitted host never installed its modern cursor areas"
  )

  fixture.host.isHidden = true
  await fixture.drainMainQueue()
  #expect(
    fixture.host.cursorRegistrations().isEmpty,
    "a hidden host still published a modern cursor spec"
  )
  #expect(cursorAreas().isEmpty, "a hidden host kept its modern cursor areas")

  fixture.host.isHidden = false
  await fixture.drainMainQueue()
  #expect(
    fixture.host.cursorRegistrations() == installedSpecs,
    "an unhidden host never restored its modern cursor spec"
  )
  #expect(
    cursorAreas().count == installedSpecs.count,
    "an unhidden host never restored its modern cursor areas"
  )

  fixture.host.uninstall()
  await fixture.drainMainQueue()
  #expect(
    fixture.host.cursorRegistrations().isEmpty,
    "a detached host still published a modern cursor spec"
  )
  #expect(cursorAreas().isEmpty, "a detached host kept its modern cursor areas")
}

@Test @MainActor func menuPanelModernCursorOwnershipDefersToActivityWithoutLosingAreas()
  async throws
{
  let screen = try #require(NSScreen.main)
  let fixture = await CursorRoutingFixture(screen: screen)
  defer { fixture.tearDown() }
  defer {
    if !NSApplication.shared.isActive {
      NSApplication.shared.activate(ignoringOtherApps: true)
    }
  }
  let originalActivationPolicy = NSApplication.shared.activationPolicy()
  NSApplication.shared.setActivationPolicy(.accessory)
  defer { NSApplication.shared.setActivationPolicy(originalActivationPolicy) }
  try #require(
    NSApplication.shared.activationPolicy() == .accessory,
    "the accessory activation policy premise never took effect"
  )
  try await fixture.activateWindow()
  await fixture.drainMainQueue()

  func cursorAreas() -> [NSTrackingArea] {
    fixture.host.trackingAreas.filter { $0.options.contains(.cursorUpdate) }
  }

  let admittedSpecs = fixture.host.cursorRegistrations(fresh: true)
  try #require(!admittedSpecs.isEmpty, "the admitted host published no modern cursor spec")
  let identities = cursorAreas().map { ObjectIdentifier($0) }

  NSApplication.shared.deactivate()
  let inactiveDeadline = ContinuousClock.now + .seconds(2)
  while NSApplication.shared.isActive, ContinuousClock.now < inactiveDeadline {
    try? await Task.sleep(for: .milliseconds(50))
  }
  try #require(
    !NSApplication.shared.isActive,
    "the fixture application could not leave the active state"
  )
  await fixture.drainMainQueue()
  #expect(
    cursorAreas().map { ObjectIdentifier($0) } == identities,
    "inactivity removed the admitted modern cursor areas"
  )
  #expect(
    fixture.host.cursorRegistrations(fresh: true) == admittedSpecs,
    "inactivity changed the admitted modern cursor spec"
  )

  let bounds = fixture.host.bounds
  let bandPoint = CGPoint(x: bounds.midX, y: bounds.minY + 6)
  let event = try #require(
    fixture.cursorUpdateEvent(atHostPoint: bandPoint),
    "could not build the inactive cursorUpdate"
  )
  NSCursor.arrow.set()
  fixture.host.cursorUpdate(with: event)
  #expect(
    NSCursor.current === NSCursor.arrow,
    "an inactive cursorUpdate still resolved a resize cursor"
  )

  fixture.host.isHidden = true
  await fixture.drainMainQueue()
  #expect(cursorAreas().isEmpty, "a hidden inactive host kept its modern cursor areas")
  fixture.host.isHidden = false
  await fixture.drainMainQueue()
  #expect(
    cursorAreas().count == admittedSpecs.count,
    "a fresh inactive installation never published its modern cursor areas"
  )

  NSApplication.shared.activate(ignoringOtherApps: true)
  let activeDeadline = ContinuousClock.now + .seconds(2)
  while !NSApplication.shared.isActive, ContinuousClock.now < activeDeadline {
    try? await Task.sleep(for: .milliseconds(50))
  }
  try #require(
    NSApplication.shared.isActive,
    "the fixture application never returned to the active state"
  )
}

@Test @MainActor func menuPanelModernCursorDiscardsStaleAreaWorkAcrossReattachment()
  async throws
{
  let screen = try #require(NSScreen.main)
  let fixture = await CursorRoutingFixture(screen: screen)
  defer { fixture.tearDown() }
  try await fixture.activateWindow()
  await fixture.drainMainQueue()

  func cursorAreas() -> [NSTrackingArea] {
    fixture.host.trackingAreas.filter { $0.options.contains(.cursorUpdate) }
  }

  let bounds = fixture.host.bounds
  let attachedSpecs = fixture.host.cursorRegistrations(fresh: true)
  try #require(!attachedSpecs.isEmpty, "the admitted host published no modern cursor spec")

  let narrowed = CGRect(
    origin: .zero,
    size: CGSize(width: bounds.width - 60, height: bounds.height - 20)
  )
  fixture.host.invalidateResizeCursorRegions()
  fixture.host.frame = narrowed
  fixture.host.uninstall()
  fixture.host.installIfNeeded()
  await fixture.drainMainQueue()

  let reattachedSpecs = fixture.host.cursorRegistrations(fresh: true)
  try #require(
    !reattachedSpecs.isEmpty,
    "the reattached host never published a modern cursor spec"
  )
  try #require(
    reattachedSpecs != attachedSpecs,
    "the reattachment premise needs a different admitted geometry"
  )
  let areas = cursorAreas()
  #expect(
    areas.map(\.rect) == reattachedSpecs.map(\.rect),
    "the reattached host installed a stale area set"
  )
  #expect(
    areas.allSatisfy { fixture.host.bounds.contains($0.rect) },
    "reattachment installed areas from the previous geometry"
  )
  #expect(
    Set(areas.map { ObjectIdentifier($0) }).count == areas.count,
    "reattachment installed duplicate modern cursor areas"
  )
  #expect(
    areas.allSatisfy { $0.owner === fixture.host },
    "reattachment left an area owned by another view"
  )
}

@Test @MainActor func menuPanelModernCursorCallbackPreservesAdmittedAndNativeContentOwnership()
  async throws
{
  let screen = try #require(NSScreen.main)
  let fixture = await CursorRoutingFixture(screen: screen)
  defer { fixture.tearDown() }
  try await fixture.activateWindow()
  await fixture.drainMainQueue()

  try #require(
    NSApplication.shared.isActive && fixture.window.isKeyWindow,
    "the callback premise needs the fixture application active in its key window"
  )
  try #require(
    fixture.geometryStore.cachedStatusButton != nil,
    "the callback premise needs the anchored status button geometry"
  )

  let contentOwner = MenuPanelCursorContentOwnerView(frame: fixture.host.frame)
  fixture.host.removeFromSuperview()
  fixture.window.contentView = contentOwner
  contentOwner.addSubview(fixture.host)
  fixture.host.frame = contentOwner.bounds
  fixture.host.installIfNeeded()
  fixture.window.invalidateCursorRects(for: contentOwner)
  try #require(
    fixture.host.superview === contentOwner && contentOwner.window === fixture.window,
    "the callback premise needs a real native content owner holding the host"
  )
  let bounds = fixture.host.bounds
  let bandPoint = CGPoint(
    x: fixture.fixedSide == .left ? bounds.maxX - 6 : bounds.minX + 6,
    y: bounds.midY
  )
  try #require(
    fixture.host.usableHandle(
      at: fixture.host.convert(bandPoint, to: nil),
      in: fixture.window,
      fixedSide: fixture.fixedSide
    ) == .farSide,
    "the callback premise needs an admitted far side point"
  )
  let bodyPoint = CGPoint(x: bounds.midX, y: bounds.midY)
  try #require(
    fixture.host.usableHandle(
      at: fixture.host.convert(bodyPoint, to: nil),
      in: fixture.window,
      fixedSide: fixture.fixedSide
    ) == nil,
    "the body premise needs a point outside the admitted rim"
  )

  let bandEvent = try #require(
    fixture.cursorUpdateEvent(atHostPoint: bandPoint),
    "could not build the admitted band cursorUpdate"
  )
  try #require(
    bandEvent.window === fixture.window,
    "the band cursorUpdate premise needs the fixture window attached to the event"
  )
  NSCursor.arrow.set()
  fixture.host.cursorUpdate(with: bandEvent)
  #expect(
    NSCursor.current === NSCursor.resizeLeftRight,
    "an admitted band callback never set its own resize cursor"
  )

  let bodyEvent = try #require(
    fixture.cursorUpdateEvent(atHostPoint: bodyPoint),
    "could not build the body cursorUpdate"
  )
  try #require(
    bodyEvent.window === fixture.window,
    "the body cursorUpdate premise needs the fixture window attached to the event"
  )
  fixture.host.cursorUpdate(with: bodyEvent)
  #expect(
    NSCursor.current === NSCursor.arrow,
    "a body callback never released the owned resize cursor"
  )

  try #require(
    !contentOwner.bodyCursorRect.contains(fixture.host.convert(bandPoint, to: contentOwner))
      && contentOwner.bodyCursorRect.contains(fixture.host.convert(bodyPoint, to: contentOwner)),
    "the native content owner premise needs the body point inside its own policy"
  )
  contentOwner.bodyCursor = .iBeam
  fixture.window.resetCursorRects()
  contentOwner.cursorUpdate(with: bodyEvent)
  #expect(
    NSCursor.current === NSCursor.iBeam,
    "the native content owner never applied its own body cursor policy"
  )
  #expect(contentOwner.bodyCursorUpdates > 0, "the native content owner never received a body update")

  NSCursor.iBeam.set()
  fixture.host.cursorUpdate(with: bodyEvent)
  #expect(
    NSCursor.current === NSCursor.iBeam,
    "a body callback replaced the content's own cursor"
  )
  #expect(
    contentOwner.bodyCursorRect.contains(fixture.host.convert(bodyPoint, to: contentOwner)),
    "the native content owner premise lost its body coverage"
  )
}

@MainActor
private final class MenuPanelAnchorEventLog {
  private(set) var entries: [String] = []

  func reset() { entries.removeAll() }
  func record(_ entry: String) { entries.append(entry) }
  func firstIndex(where matches: (String) -> Bool) -> Int? { entries.firstIndex(where: matches) }
}

@MainActor
private final class MenuPanelAnchorRecordingRoot: NSView {
  private let log: MenuPanelAnchorEventLog
  var onHostAttach: (() -> Void)?

  init(frame: NSRect, log: MenuPanelAnchorEventLog) {
    self.log = log
    super.init(frame: frame)
  }

  required init?(coder: NSCoder) { nil }

  override func addSubview(_ view: NSView) {
    attach(view)
    super.addSubview(view)
  }

  override func addSubview(
    _ view: NSView,
    positioned place: NSWindow.OrderingMode,
    relativeTo otherView: NSView?
  ) {
    attach(view)
    super.addSubview(view, positioned: place, relativeTo: otherView)
  }

  private func attach(_ view: NSView) {
    guard view.superview !== self else { return }
    log.record("attach:\(type(of: view))")
    guard view is MenuPanelResizeHostView else { return }
    onHostAttach?()
    onHostAttach = nil
  }
}

@MainActor
private final class MenuPanelAnchorFixture {
  let log: MenuPanelAnchorEventLog
  let window: NSWindow
  let root: MenuPanelAnchorRecordingRoot
  let anchor: MenuPanelResizeInstallationView
  let controller: MenuPanelResizeController
  let statusWindow: NSWindow
  let statusButton: NSStatusBarButton
  let geometryStore: MenuPanelGeometryStore
  let preferredSize: CGSize
  private(set) var commits: [CGSize] = []
  private var eventNumber = 30_000
  private var isTornDown = false
  private var frameObservation: NSObjectProtocol?

  init(screen: NSScreen, contentSize: CGSize = CGSize(width: 420, height: 430)) {
    let frame = CGRect(
      x: (screen.visibleFrame.midX - contentSize.width / 2).rounded(),
      y: (screen.visibleFrame.midY - contentSize.height / 2).rounded(),
      width: contentSize.width,
      height: contentSize.height
    )
    let eventLog = MenuPanelAnchorEventLog()
    log = eventLog
    preferredSize = contentSize
    window = NSWindow(
      contentRect: frame,
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    root = MenuPanelAnchorRecordingRoot(
      frame: CGRect(origin: .zero, size: contentSize),
      log: eventLog
    )
    let resizeController = MenuPanelResizeController()
    controller = resizeController
    anchor = MenuPanelResizeInstallationView(controller: resizeController)
    let statusRoot = NSView(frame: CGRect(x: 0, y: 0, width: 80, height: 40))
    statusButton = NSStatusBarButton(frame: CGRect(x: 10, y: 6, width: 34, height: 22))
    statusRoot.addSubview(statusButton)
    let statusWindow = NSWindow(
      contentRect: CGRect(x: frame.maxX - 10, y: frame.maxY + 14, width: 80, height: 40),
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    statusWindow.contentView = statusRoot
    self.statusWindow = statusWindow
    geometryStore = MenuPanelGeometryStore(windows: { [statusWindow] })

    window.contentView = root
    anchor.frame = root.bounds
    root.addSubview(anchor)
    window.makeKeyAndOrderFront(nil)
    configure()
    alignStatusButton()
    frameObservation = NotificationCenter.default.addObserver(
      forName: NSWindow.didResizeNotification,
      object: window,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        let frame = self.window.frame
        self.log.record(
          "frame:\(Int(frame.width.rounded()))x\(Int(frame.height.rounded()))"
        )
      }
    }
  }

  var host: MenuPanelResizeHostView { anchor.host }

  func configure(canResize: Bool = true) {
    anchor.configure(
      geometryStore: geometryStore,
      preferredSize: preferredSize,
      canResize: canResize,
      onCommit: { [weak self] size in self?.commits.append(size) }
    )
  }

  func settle() async {
    for _ in 0..<6 {
      anchor.layoutSubtreeIfNeeded()
      root.layoutSubtreeIfNeeded()
      await Task.yield()
    }
  }

  func mouseDown(atHostPoint point: CGPoint) {
    send(.leftMouseDown, atHostPoint: point)
  }

  func drag(toScreenPoint point: CGPoint) {
    eventNumber += 1
    guard
      let event = NSEvent.mouseEvent(
        with: .leftMouseDragged,
        location: window.convertPoint(fromScreen: point),
        modifierFlags: [],
        timestamp: TimeInterval(eventNumber) / 100,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: eventNumber,
        clickCount: 1,
        pressure: 1
      )
    else {
      Issue.record("could not create drag event")
      return
    }
    NSApplication.shared.sendEvent(event)
  }

  func tearDown() {
    guard !isTornDown else { return }
    isTornDown = true
    if let frameObservation {
      NotificationCenter.default.removeObserver(frameObservation)
      self.frameObservation = nil
    }
    anchor.dismantle()
    window.orderOut(nil)
    window.contentView = nil
    NSCursor.arrow.set()
  }

  private func send(_ type: NSEvent.EventType, atHostPoint point: CGPoint) {
    eventNumber += 1
    guard
      let event = NSEvent.mouseEvent(
        with: type,
        location: host.convert(point, to: nil),
        modifierFlags: [],
        timestamp: TimeInterval(eventNumber) / 100,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: eventNumber,
        clickCount: 1,
        pressure: 1
      )
    else {
      Issue.record("could not create \(type) event")
      return
    }
    NSApplication.shared.sendEvent(event)
  }

  private func alignStatusButton() {
    let panel = window.frame
    statusWindow.setFrameOrigin(
      CGPoint(x: panel.maxX - statusButton.frame.maxX, y: statusWindow.frame.origin.y)
    )
  }
}

@Test @MainActor func menuPanelAnchorRetainsTopmostDirectRootHostOnEqualUpdate() async throws {
  let screen = try #require(NSScreen.main)
  let fixture = MenuPanelAnchorFixture(screen: screen)
  defer { fixture.tearDown() }
  await fixture.settle()

  let host = fixture.host
  try #require(
    host.superview === fixture.root,
    "the anchor never attached its host to the window content root"
  )
  #expect(
    fixture.root.subviews.last === host,
    "the retained host is not the topmost direct child of the content root"
  )
  #expect(host.frame == fixture.root.bounds, "the host frame does not match the root bounds")
  #expect(
    host.autoresizingMask == [.width, .height],
    "the retained host does not resize with its content root"
  )
  let childCount = fixture.root.subviews.count
  let areaIdentities = host.trackingAreas
    .filter { $0.options.contains(.cursorUpdate) }
    .map { ObjectIdentifier($0) }
  try #require(!areaIdentities.isEmpty, "the retained host installed no modern cursor areas")

  fixture.log.reset()
  fixture.configure()
  fixture.anchor.layout()
  await fixture.settle()

  #expect(
    fixture.log.entries.contains { $0.hasPrefix("attach:") } == false,
    "an equal update removed and readded a view in the content root"
  )
  #expect(
    host.trackingAreas
      .filter { $0.options.contains(.cursorUpdate) }
      .map { ObjectIdentifier($0) } == areaIdentities,
    "an equal update replaced the retained modern cursor areas"
  )
  #expect(fixture.host === host, "an equal update replaced the retained host")
  #expect(host.superview === fixture.root, "an equal update reattached the host elsewhere")
  #expect(
    fixture.root.subviews.count == childCount,
    "an equal update churned the content root hierarchy"
  )
  #expect(
    fixture.root.subviews.last === host,
    "an equal update left another view above the retained host"
  )
}

@Test @MainActor func menuPanelAnchorReconcilesRootBoundsSizeAndOrigin() async throws {
  let screen = try #require(NSScreen.main)
  let fixture = MenuPanelAnchorFixture(screen: screen)
  defer { fixture.tearDown() }
  await fixture.settle()

  let host = fixture.host
  fixture.root.setBoundsSize(CGSize(width: 520, height: 470))
  fixture.anchor.layout()
  await fixture.settle()
  #expect(host.frame == fixture.root.bounds, "the host never followed a resized content root")

  fixture.root.setBoundsOrigin(CGPoint(x: 7, y: 5))
  fixture.anchor.layout()
  await fixture.settle()
  #expect(host.frame == fixture.root.bounds, "the host never followed a shifted content root")
  #expect(fixture.host === host, "a bounds change replaced the retained host")
}

@Test @MainActor func menuPanelAnchorHiddenIsReversibleAndDismantleIsPermanent() async throws {
  let screen = try #require(NSScreen.main)
  let fixture = MenuPanelAnchorFixture(screen: screen)
  defer { fixture.tearDown() }
  await fixture.settle()

  let host = fixture.host
  try #require(host.superview === fixture.root, "the anchor never attached its host")

  fixture.anchor.isHidden = true
  await fixture.settle()
  #expect(host.superview == nil, "a hidden anchor kept its host attached to the content root")

  fixture.anchor.isHidden = false
  await fixture.settle()
  #expect(host.superview === fixture.root, "unhiding the anchor never reattached the retained host")
  #expect(fixture.host === host, "unhiding the anchor replaced the retained host")

  fixture.anchor.dismantle()
  await fixture.settle()
  #expect(host.superview == nil, "a dismantled anchor kept its host attached")

  fixture.anchor.layout()
  await fixture.settle()
  #expect(host.superview == nil, "a dismantled anchor reattached its host from a late layout")
  fixture.anchor.dismantle()
  #expect(host.superview == nil, "a repeated dismantle reattached its host")
}

@Test @MainActor func menuPanelAnchorMigratesAfterCancellingCaptureAndRollingBackOldWindow()
  async throws
{
  let screen = try #require(NSScreen.main)
  let fixture = MenuPanelAnchorFixture(screen: screen)
  defer { fixture.tearDown() }
  await fixture.settle()

  let host = fixture.host
  let previousRoot = fixture.root
  let originalFrame = fixture.window.frame
  let bandPoint = CGPoint(x: host.bounds.midX, y: host.bounds.minY + 6)
  fixture.mouseDown(atHostPoint: bandPoint)
  try #require(fixture.controller.isTracking, "the admitted rim never began a resize")
  fixture.drag(
    toScreenPoint: CGPoint(x: originalFrame.midX, y: originalFrame.minY + 80)
  )
  try #require(fixture.window.frame != originalFrame, "the drag never moved the panel frame")

  let destinationWindow = NSWindow(
    contentRect: CGRect(x: originalFrame.minX + 40, y: originalFrame.minY + 40, width: 400, height: 400),
    styleMask: .borderless,
    backing: .buffered,
    defer: false
  )
  let destinationRoot = MenuPanelAnchorRecordingRoot(
    frame: CGRect(origin: .zero, size: CGSize(width: 400, height: 400)),
    log: fixture.log
  )
  destinationWindow.contentView = destinationRoot
  destinationWindow.orderFrontRegardless()
  defer {
    destinationWindow.orderOut(nil)
    destinationWindow.contentView = nil
  }

  fixture.log.reset()
  fixture.anchor.removeFromSuperview()
  destinationRoot.addSubview(fixture.anchor)
  await fixture.settle()

  #expect(!fixture.controller.isTracking, "a live capture survived the anchor migration")
  #expect(fixture.window.frame == originalFrame, "the old window never rolled back during migration")
  try #require(host.superview === destinationRoot, "the host never migrated to the new content root")
  #expect(host.frame == destinationRoot.bounds, "the migrated host took the wrong root bounds")
  #expect(previousRoot.subviews.contains(host) == false, "the host stayed in the previous root")

  let rollbackIndex = try #require(
    fixture.log.firstIndex { $0.hasPrefix("frame:") },
    "migration never observed the old-window rollback"
  )
  let attachIndex = try #require(
    fixture.log.firstIndex { $0 == "attach:MenuPanelResizeHostView" },
    "migration never observed the new-root host attach"
  )
  #expect(
    rollbackIndex < attachIndex,
    "the new attachment acquired before the old window rolled back"
  )
}

@Test @MainActor func menuPanelAnchorCompletesAutomaticUninstallExactlyOnce() async throws {
  let screen = try #require(NSScreen.main)
  let fixture = MenuPanelAnchorFixture(screen: screen)
  defer { fixture.tearDown() }
  await fixture.settle()

  let host = fixture.host
  let originalFrame = fixture.window.frame
  let bandPoint = CGPoint(x: host.bounds.midX, y: host.bounds.minY + 6)
  fixture.mouseDown(atHostPoint: bandPoint)
  try #require(fixture.controller.isTracking, "the admitted rim never began a resize")
  fixture.drag(
    toScreenPoint: CGPoint(x: originalFrame.midX, y: originalFrame.minY + 90)
  )
  try #require(fixture.window.frame != originalFrame, "the drag never moved the panel frame")

  fixture.log.reset()
  host.removeFromSuperview()
  host.uninstall()
  host.completeNativeDetachment()
  #expect(
    fixture.window.frame == originalFrame,
    "explicit completion never rolled back the automatically uninstalled window"
  )
  let rollbacks = fixture.log.entries.filter { $0.hasPrefix("frame:") }.count
  #expect(rollbacks == 1, "explicit completion restored the old window \(rollbacks) times")

  fixture.anchor.layout()
  try #require(host.superview === fixture.root, "the anchor never reattached its host")
  try #require(host.isInstalled, "the reattached host never installed again")
  let owner = try #require(
    fixture.controller.currentPresentationOwnerID,
    "the reattached host never reclaimed presentation"
  )

  await fixture.settle()
  host.completeNativeDetachment()
  let repeated = fixture.log.entries.filter { $0.hasPrefix("frame:") }.count
  #expect(repeated == 1, "a repeated completion restored the old window again")
  #expect(
    fixture.controller.currentPresentationOwnerID == owner,
    "a queued release from the previous attachment replaced the newer owner"
  )
  #expect(
    fixture.log.entries.filter { $0.hasPrefix("frame:") }.count == 1,
    "a queued release from the previous attachment restored the window over the newer one"
  )
}

@Test @MainActor func menuPanelAnchorMigratesWhenTheContentRootIsReplaced() async throws {
  let screen = try #require(NSScreen.main)
  let fixture = MenuPanelAnchorFixture(screen: screen)
  defer { fixture.tearDown() }
  await fixture.settle()

  let host = fixture.host
  let previousRoot = fixture.root
  let replacementRoot = MenuPanelAnchorRecordingRoot(frame: previousRoot.frame, log: fixture.log)

  fixture.anchor.removeFromSuperview()
  fixture.window.contentView = replacementRoot
  replacementRoot.addSubview(fixture.anchor)
  await fixture.settle()

  try #require(
    host.superview === replacementRoot,
    "the host never followed a replaced content root"
  )
  #expect(host.frame == replacementRoot.bounds, "the migrated host took the wrong root bounds")
  #expect(previousRoot.subviews.contains(host) == false, "the host stayed in the replaced root")
  #expect(
    replacementRoot.subviews.last === host,
    "the migrated host is not the topmost child of the replacement root"
  )
  #expect(fixture.host === host, "a content root replacement replaced the retained host")
}

@Test(arguments: [false, true]) @MainActor
func menuPanelAnchorOverlappingLateCallbacksPreserveTheNewerOwner(pendingRelease: Bool) async throws {
  let screen = try #require(NSScreen.main)
  let fixture = MenuPanelAnchorFixture(screen: screen)
  defer { fixture.tearDown() }
  await fixture.settle()

  let olderHost = fixture.host
  try #require(olderHost.superview === fixture.root, "the first anchor never attached its host")

  if pendingRelease {
    olderHost.uninstall()
    try #require(!olderHost.isInstalled, "the older host did not enter pending detachment")
  }

  let newerAnchor = MenuPanelResizeInstallationView(controller: fixture.controller)
  newerAnchor.frame = fixture.root.bounds
  fixture.root.addSubview(newerAnchor)
  newerAnchor.configure(
    geometryStore: fixture.geometryStore,
    preferredSize: fixture.preferredSize,
    canResize: true,
    onCommit: { _ in }
  )
  await fixture.settle()
  let newerHost = newerAnchor.host
  try #require(newerHost.superview === fixture.root, "the second anchor never attached its host")
  #expect(
    fixture.window.acceptsMouseMovedEvents,
    "the newer anchor never claimed the mouse-move policy"
  )
  let newerOwner = try #require(
    fixture.controller.currentPresentationOwnerID,
    "the newer anchor never claimed the controller presentation"
  )

  fixture.anchor.configure(
    geometryStore: fixture.geometryStore,
    preferredSize: CGSize(width: 360, height: 360),
    canResize: true,
    onCommit: { _ in }
  )
  fixture.anchor.layout()
  fixture.anchor.dismantle()
  await fixture.settle()

  #expect(olderHost.superview == nil, "the dismantled anchor kept its own host attached")
  #expect(
    newerHost.superview === fixture.root,
    "a late callback from the older anchor detached the newer host"
  )
  #expect(
    fixture.window.acceptsMouseMovedEvents,
    "a late callback from the older anchor restored mouse-move policy under the newer owner"
  )
  #expect(newerHost.isInstalled, "a late callback from the older anchor uninstalled the newer host")
  #expect(
    fixture.controller.currentPresentationOwnerID == newerOwner,
    "a late callback from the older anchor replaced the newer controller owner"
  )

  newerAnchor.dismantle()
  await fixture.settle()
  #expect(
    fixture.controller.currentPresentationOwnerID == nil,
    "dismantling the newer anchor left its presentation owner behind"
  )
}

@Test @MainActor func menuPanelAnchorDetachesWhenItLeavesTheContentHierarchy() async throws {
  let screen = try #require(NSScreen.main)
  let fixture = MenuPanelAnchorFixture(screen: screen)
  defer { fixture.tearDown() }
  await fixture.settle()

  let host = fixture.host
  try #require(host.superview === fixture.root, "the anchor never attached its host")
  try #require(host.isInstalled, "the anchor host never installed")

  fixture.anchor.removeFromSuperview()
  await fixture.settle()

  #expect(
    host.superview == nil,
    "an anchor outside the content hierarchy kept its host attached to the root"
  )
  #expect(
    !host.isInstalled,
    "an anchor outside the content hierarchy kept its host installed"
  )
  #expect(
    fixture.controller.currentPresentationOwnerID == nil,
    "an anchor outside the content hierarchy kept the controller presentation"
  )
}

@Test @MainActor func menuPanelAnchorDeniesInstallationWhenRequiredAuthorityVanishes() async throws {
  let screen = try #require(NSScreen.main)
  let frame = CGRect(
    x: (screen.visibleFrame.midX - 210).rounded(),
    y: (screen.visibleFrame.midY - 215).rounded(),
    width: 420,
    height: 430
  )
  let window = NSWindow(
    contentRect: frame,
    styleMask: .borderless,
    backing: .buffered,
    defer: false
  )
  let root = MenuPanelAnchorRecordingRoot(
    frame: CGRect(origin: .zero, size: CGSize(width: 420, height: 430)),
    log: MenuPanelAnchorEventLog()
  )
  window.contentView = root
  defer {
    window.orderOut(nil)
    window.contentView = nil
  }

  let controller = MenuPanelResizeController()
  let host = MenuPanelResizeHostView(controller: controller)
  var authority: MenuPanelResizeInstallationAuthority? = MenuPanelResizeInstallationAuthority()
  host.adoptInstallationAuthority(try #require(authority))
  root.addSubview(host)
  authority = nil
  window.makeKeyAndOrderFront(nil)

  host.configure(
    geometryStore: nil,
    preferredSize: CGSize(width: 420, height: 430),
    canResize: true,
    onCommit: { _ in }
  )
  host.installIfNeeded()

  #expect(
    !host.isInstalled,
    "a vanished required installation authority still allowed installation"
  )
  #expect(
    controller.currentPresentationOwnerID == nil,
    "a vanished required installation authority still claimed presentation"
  )
}

@Test @MainActor func menuPanelAnchorRejectsAStaleTargetAfterAnAttachCalloutChangesTheRoot()
  async throws
{
  let screen = try #require(NSScreen.main)
  let fixture = MenuPanelAnchorFixture(screen: screen)
  defer { fixture.tearDown() }
  await fixture.settle()

  let host = fixture.host
  let staleRoot = fixture.root
  try #require(host.superview === staleRoot, "the anchor never attached its host")

  let replacement = MenuPanelAnchorRecordingRoot(frame: staleRoot.frame, log: fixture.log)
  staleRoot.onHostAttach = { [weak fixture] in
    guard let fixture else { return }
    fixture.window.contentView = replacement
    replacement.addSubview(fixture.anchor)
  }

  host.removeFromSuperview()
  fixture.anchor.layout()
  await fixture.settle()

  #expect(
    host.superview === fixture.window.contentView,
    "the anchor installed its host into the stale captured root"
  )
  #expect(
    host.superview === replacement,
    "the anchor never followed the content root replaced during its own attach callout"
  )
  #expect(host.isInstalled, "the host never installed in the replacement content root")
}

@Test @MainActor func menuPanelAnchorRecoversPendingSameRootOwnerBeforeQueuedRelease()
  async throws
{
  let screen = try #require(NSScreen.main)
  let fixture = MenuPanelAnchorFixture(screen: screen)
  defer { fixture.tearDown() }
  await fixture.settle()

  let host = fixture.host
  let previousOwner = try #require(fixture.controller.currentPresentationOwnerID)
  host.uninstall()
  try #require(host.superview === fixture.root)
  try #require(!host.isInstalled)
  try #require(fixture.controller.currentPresentationOwnerID == previousOwner)

  fixture.anchor.layout()
  let newOwner = try #require(fixture.controller.currentPresentationOwnerID)
  #expect(newOwner != previousOwner, "same-root reconciliation never replaced the pending owner")
  #expect(host.isInstalled, "same-root reinstallation revoked its own authority")
  #expect(fixture.root.subviews.last === host)

  await fixture.settle()
  #expect(
    fixture.controller.currentPresentationOwnerID == newOwner,
    "the old queued release changed the recovered owner"
  )
  #expect(host.isInstalled, "the old queued release uninstalled the recovered host")
  #expect(fixture.window.acceptsMouseMovedEvents)
}

@MainActor
final class MenuPanelCursorContentOwnerView: NSView {
  var bodyCursor: NSCursor?
  private(set) var bodyCursorUpdates = 0

  var bodyCursorRect: CGRect { bounds.insetBy(dx: 7, dy: 7) }

  override func resetCursorRects() {
    super.resetCursorRects()
    let body = bodyCursorRect
    guard let bodyCursor, body.width > 0, body.height > 0 else { return }
    addCursorRect(body, cursor: bodyCursor)
  }

  override func cursorUpdate(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    guard let bodyCursor, bodyCursorRect.contains(point) else {
      super.cursorUpdate(with: event)
      return
    }
    bodyCursorUpdates += 1
    bodyCursor.set()
  }
}
