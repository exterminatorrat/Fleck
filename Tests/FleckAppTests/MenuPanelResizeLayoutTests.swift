import CoreGraphics
import Testing

@testable import FleckApp

private let menuPanelResizeLayoutSides: [MenuPanelFixedSide] = [.left, .right]

private func menuPanelResizeLayoutArea(_ rect: CGRect) -> CGFloat {
  guard !rect.isNull, !rect.isInfinite else { return 0 }
  return rect.width * rect.height
}

private func menuPanelResizeLayoutRectsAlmostEqual(_ first: CGRect, _ second: CGRect) -> Bool {
  abs(first.minX - second.minX) <= 0.000_000_001
    && abs(first.minY - second.minY) <= 0.000_000_001
    && abs(first.width - second.width) <= 0.000_000_001
    && abs(first.height - second.height) <= 0.000_000_001
}

private func menuPanelResizeLayoutRegions(
  containing point: CGPoint,
  in layout: MenuPanelResizeLayout
) -> [MenuPanelResizeLayout.Region] {
  layout.marginRegions.filter { $0.rect.contains(point) }
}

private func menuPanelResizeLayoutRegionHandle(
  at point: CGPoint,
  in layout: MenuPanelResizeLayout
) -> MenuPanelResizeHandle? {
  let regions = menuPanelResizeLayoutRegions(containing: point, in: layout)
  #expect(
    regions.count == 1,
    "expected exactly one margin region at \(point), found \(regions.count)"
  )
  return regions.first?.handle
}

private func menuPanelResizeLayoutCheckCoreGeometry(
  _ layout: MenuPanelResizeLayout,
  outer: CGRect,
  fixedSide: MenuPanelFixedSide
) {
  let body = layout.bodyBounds
  #expect(layout.outerBounds == outer)
  #expect(layout.fixedSide == fixedSide)
  #expect(body.maxY == outer.maxY)
  #expect(body.minY - outer.minY == 3)
  #expect(body.width == outer.width - 3)
  #expect(body.height == outer.height - 3)
  switch fixedSide {
  case .left:
    #expect(body.minX == outer.minX)
    #expect(outer.maxX - body.maxX == 3)
  case .right:
    #expect(outer.maxX == body.maxX)
    #expect(body.minX - outer.minX == 3)
  }
  #expect(body.width > 0)
  #expect(body.height > 0)
  #expect(!body.isNull && !body.isInfinite)
}

private func menuPanelResizeLayoutCheckMarginTiling(
  _ layout: MenuPanelResizeLayout,
  outer: CGRect
) {
  let body = layout.bodyBounds
  #expect(!layout.marginRegions.isEmpty)
  var summedArea: CGFloat = 0
  for region in layout.marginRegions {
    let rect = region.rect
    #expect(!rect.isNull && !rect.isInfinite)
    #expect(rect.width > 0 && rect.height > 0)
    #expect(rect.minX >= outer.minX && rect.maxX <= outer.maxX)
    #expect(rect.minY >= outer.minY && rect.maxY <= outer.maxY)
    #expect(menuPanelResizeLayoutArea(rect.intersection(body)) <= 0.000_001)
    summedArea += menuPanelResizeLayoutArea(rect)
  }
  for firstIndex in layout.marginRegions.indices {
    for secondIndex in layout.marginRegions.indices where secondIndex > firstIndex {
      let overlap = layout.marginRegions[firstIndex].rect.intersection(
        layout.marginRegions[secondIndex].rect
      )
      #expect(menuPanelResizeLayoutArea(overlap) <= 0.000_001)
    }
  }
  let expectedArea = menuPanelResizeLayoutArea(outer) - menuPanelResizeLayoutArea(body)
  #expect(abs(summedArea - expectedArea) <= 0.000_001)
}

private func menuPanelResizeLayoutCheckMarginCoverage(
  _ layout: MenuPanelResizeLayout,
  outer: CGRect,
  fixedSide: MenuPanelFixedSide
) {
  let body = layout.bodyBounds
  var probes: [CGPoint] = [
    CGPoint(x: outer.minX + 1, y: outer.minY + 1),
    CGPoint(x: outer.midX, y: outer.minY + 1),
    CGPoint(x: outer.maxX - 1, y: outer.minY + 1),
  ]
  let freeEdgeX: CGFloat = fixedSide == .left ? outer.maxX - 1 : outer.minX + 1
  probes.append(CGPoint(x: freeEdgeX, y: body.minY + 1))
  probes.append(CGPoint(x: freeEdgeX, y: outer.midY))
  probes.append(CGPoint(x: freeEdgeX, y: outer.maxY - 1))
  for probe in probes {
    #expect(outer.contains(probe))
    #expect(!body.contains(probe))
    #expect(menuPanelResizeLayoutRegions(containing: probe, in: layout).count == 1)
  }
}

private func menuPanelResizeLayoutCheckBodyHasNoMargin(_ layout: MenuPanelResizeLayout) {
  let body = layout.bodyBounds
  let probes: [CGPoint] = [
    CGPoint(x: body.midX, y: body.midY),
    CGPoint(x: body.minX + 1, y: body.minY + 1),
    CGPoint(x: body.maxX - 1, y: body.minY + 1),
    CGPoint(x: body.minX + 1, y: body.maxY - 1),
    CGPoint(x: body.maxX - 1, y: body.maxY - 1),
  ]
  for probe in probes {
    #expect(body.contains(probe))
    #expect(!layout.marginRegions.contains { $0.rect.contains(probe) })
  }
}

private func menuPanelResizeLayoutCheckOutsidePaintProbes(
  _ layout: MenuPanelResizeLayout,
  outer: CGRect,
  fixedSide: MenuPanelFixedSide
) {
  let body = layout.bodyBounds
  let bottomProbe = CGPoint(x: outer.midX, y: body.minY - 2)
  let sideProbe = CGPoint(
    x: fixedSide == .left ? body.maxX + 2 : body.minX - 2,
    y: outer.midY
  )
  for probe in [bottomProbe, sideProbe] {
    #expect(outer.contains(probe))
    #expect(!body.contains(probe))
    #expect(menuPanelResizeLayoutRegions(containing: probe, in: layout).count == 1)
  }
}

private func menuPanelResizeLayoutCheckHandleAgreement(
  _ layout: MenuPanelResizeLayout,
  outer: CGRect,
  fixedSide: MenuPanelFixedSide
) {
  let body = layout.bodyBounds
  let farEdgeX: CGFloat = fixedSide == .left ? outer.maxX : outer.minX
  let inward: CGFloat = fixedSide == .left ? -1 : 1
  let bottomY = outer.minY + 1
  let bottomProbeXs: [CGFloat] = [
    outer.minX + 1,
    outer.midX,
    farEdgeX + inward * 19,
    farEdgeX + inward * 18,
    farEdgeX + inward * 17,
    farEdgeX + inward * 0.5,
  ]
  for x in bottomProbeXs where x > outer.minX && x < outer.maxX {
    let probe = CGPoint(x: x, y: bottomY)
    let expected = MenuPanelResizeGeometry.handle(
      at: probe, in: outer, fixedSide: fixedSide
    )
    #expect(expected != nil)
    #expect(menuPanelResizeLayoutRegionHandle(at: probe, in: layout) == expected)
  }
  let freeEdgeX: CGFloat = fixedSide == .left ? outer.maxX - 1 : outer.minX + 1
  let sideProbeYs: [CGFloat] = [
    body.minY + 1,
    outer.minY + 18,
    outer.minY + 20,
    outer.midY,
    outer.maxY - 1,
  ]
  for y in sideProbeYs {
    let probe = CGPoint(x: freeEdgeX, y: y)
    let expected = MenuPanelResizeGeometry.handle(
      at: probe, in: outer, fixedSide: fixedSide
    )
    #expect(expected != nil)
    #expect(menuPanelResizeLayoutRegionHandle(at: probe, in: layout) == expected)
  }
}

private func menuPanelResizeLayoutCheckCornerJunctions(
  _ layout: MenuPanelResizeLayout,
  outer: CGRect,
  fixedSide: MenuPanelFixedSide
) {
  let farEdgeX: CGFloat = fixedSide == .left ? outer.maxX : outer.minX
  let inward: CGFloat = fixedSide == .left ? -1 : 1
  let bottomY = outer.minY + 1
  let bottomBoundaryX = farEdgeX + inward * 18
  let bottomBoundaryProbes: [CGFloat] = [
    bottomBoundaryX.nextDown,
    bottomBoundaryX,
    bottomBoundaryX.nextUp,
  ]
  for x in bottomBoundaryProbes {
    let probe = CGPoint(x: x, y: bottomY)
    let expected = MenuPanelResizeGeometry.handle(
      at: probe, in: outer, fixedSide: fixedSide
    )
    #expect(expected != nil)
    #expect(menuPanelResizeLayoutRegionHandle(at: probe, in: layout) == expected)
  }
  let freeEdgeX: CGFloat = fixedSide == .left ? outer.maxX - 1 : outer.minX + 1
  let sideBoundaryY = outer.minY + 18
  let sideBoundaryProbes: [CGFloat] = [
    sideBoundaryY.nextDown,
    sideBoundaryY,
    sideBoundaryY.nextUp,
  ]
  for y in sideBoundaryProbes {
    let probe = CGPoint(x: freeEdgeX, y: y)
    let expected = MenuPanelResizeGeometry.handle(
      at: probe, in: outer, fixedSide: fixedSide
    )
    #expect(expected != nil)
    #expect(menuPanelResizeLayoutRegionHandle(at: probe, in: layout) == expected)
  }
}

@Test func menuPanelResizeLayoutInsetsBottomAndFreeSideForBothAnchors() throws {
  let outer = CGRect(x: 100.25, y: 200.5, width: 380, height: 300)
  for side in menuPanelResizeLayoutSides {
    let layout = try #require(
      MenuPanelResizeGeometry.layout(in: outer, fixedSide: side)
    )
    menuPanelResizeLayoutCheckCoreGeometry(layout, outer: outer, fixedSide: side)
    menuPanelResizeLayoutCheckMarginTiling(layout, outer: outer)
    menuPanelResizeLayoutCheckMarginCoverage(layout, outer: outer, fixedSide: side)
    menuPanelResizeLayoutCheckBodyHasNoMargin(layout)
    menuPanelResizeLayoutCheckOutsidePaintProbes(layout, outer: outer, fixedSide: side)
  }
}

@Test func menuPanelResizeLayoutPreservesGeometryAcrossTranslationAndScreenEdges() throws {
  let base = CGRect(x: 317.25, y: -410.5, width: 380, height: 300)
  let offsets = [
    CGVector(dx: 0, dy: 0),
    CGVector(dx: -500.75, dy: 250.25),
    CGVector(dx: 1024, dy: 33.5),
  ]
  for side in menuPanelResizeLayoutSides {
    let baseLayout = try #require(
      MenuPanelResizeGeometry.layout(in: base, fixedSide: side)
    )
    for offset in offsets {
      let translatedOuter = base.offsetBy(dx: offset.dx, dy: offset.dy)
      let translatedLayout = try #require(
        MenuPanelResizeGeometry.layout(in: translatedOuter, fixedSide: side)
      )
      menuPanelResizeLayoutCheckCoreGeometry(
        translatedLayout, outer: translatedOuter, fixedSide: side
      )
      #expect(menuPanelResizeLayoutRectsAlmostEqual(
        translatedLayout.bodyBounds,
        baseLayout.bodyBounds.offsetBy(dx: offset.dx, dy: offset.dy)
      ))
      #expect(translatedLayout.marginRegions.count == baseLayout.marginRegions.count)
      for baseRegion in baseLayout.marginRegions {
        let expectedRect = baseRegion.rect.offsetBy(dx: offset.dx, dy: offset.dy)
        #expect(translatedLayout.marginRegions.contains { translatedRegion in
          translatedRegion.handle == baseRegion.handle
            && menuPanelResizeLayoutRectsAlmostEqual(translatedRegion.rect, expectedRect)
        })
      }
    }
  }
  for origin in [CGPoint.zero, CGPoint(x: 1024, y: 0), CGPoint(x: 0, y: 25)] {
    let outer = CGRect(origin: origin, size: CGSize(width: 380, height: 300))
    for side in menuPanelResizeLayoutSides {
      let layout = try #require(
        MenuPanelResizeGeometry.layout(in: outer, fixedSide: side)
      )
      menuPanelResizeLayoutCheckCoreGeometry(layout, outer: outer, fixedSide: side)
      menuPanelResizeLayoutCheckMarginTiling(layout, outer: outer)
    }
  }
}

@Test func menuPanelResizeLayoutMarginRegionsTileOuterMinusBody() throws {
  let outers = [
    CGRect(x: 0, y: 0, width: 380, height: 300),
    CGRect(x: -219.5, y: -88.25, width: 512.75, height: 641.5),
    CGRect(x: 900, y: 40, width: 380.5, height: 300.5),
  ]
  for outer in outers {
    for side in menuPanelResizeLayoutSides {
      let layout = try #require(
        MenuPanelResizeGeometry.layout(in: outer, fixedSide: side)
      )
      menuPanelResizeLayoutCheckCoreGeometry(layout, outer: outer, fixedSide: side)
      menuPanelResizeLayoutCheckMarginTiling(layout, outer: outer)
      menuPanelResizeLayoutCheckMarginCoverage(layout, outer: outer, fixedSide: side)
    }
  }
}

@Test func menuPanelResizeLayoutPaintedBodyHasNoReservedMargin() throws {
  let outer = CGRect(x: 48.5, y: -72, width: 380, height: 300)
  for side in menuPanelResizeLayoutSides {
    let layout = try #require(
      MenuPanelResizeGeometry.layout(in: outer, fixedSide: side)
    )
    menuPanelResizeLayoutCheckBodyHasNoMargin(layout)
    menuPanelResizeLayoutCheckOutsidePaintProbes(layout, outer: outer, fixedSide: side)
  }
}

@Test func menuPanelResizeLayoutRegionHandlesMatchExistingHandleMap() throws {
  let outer = CGRect(x: 120.75, y: 210.25, width: 380, height: 300)
  for side in menuPanelResizeLayoutSides {
    let layout = try #require(
      MenuPanelResizeGeometry.layout(in: outer, fixedSide: side)
    )
    menuPanelResizeLayoutCheckHandleAgreement(layout, outer: outer, fixedSide: side)
    menuPanelResizeLayoutCheckCornerJunctions(layout, outer: outer, fixedSide: side)
  }
}

@Test func menuPanelResizeLayoutCornerJunctionClassificationIsHalfOpenAtTheRects() throws {
  let outer = CGRect(x: 0, y: 0, width: 380, height: 300)
  for side in menuPanelResizeLayoutSides {
    let layout = try #require(
      MenuPanelResizeGeometry.layout(in: outer, fixedSide: side)
    )
    let farEdgeX: CGFloat = side == .left ? outer.maxX : outer.minX
    let inward: CGFloat = side == .left ? -1 : 1
    let bottomBoundaryX = farEdgeX + inward * 18
    let bottomY = outer.minY + 1
    let bottomBoundary = CGPoint(x: bottomBoundaryX, y: bottomY)
    let bottomInside = CGPoint(x: bottomBoundaryX.nextUp, y: bottomY)
    let bottomOutside = CGPoint(x: bottomBoundaryX.nextDown, y: bottomY)
    #expect(
      MenuPanelResizeGeometry.handle(at: bottomBoundary, in: outer, fixedSide: side)
        == .farBottomCorner
    )
    switch side {
    case .left:
      #expect(
        MenuPanelResizeGeometry.handle(at: bottomInside, in: outer, fixedSide: side)
          == .farBottomCorner
      )
      #expect(
        MenuPanelResizeGeometry.handle(at: bottomOutside, in: outer, fixedSide: side)
          == .nearBottomCorner
      )
    case .right:
      #expect(
        MenuPanelResizeGeometry.handle(at: bottomInside, in: outer, fixedSide: side)
          == .nearBottomCorner
      )
      #expect(
        MenuPanelResizeGeometry.handle(at: bottomOutside, in: outer, fixedSide: side)
          == .farBottomCorner
      )
    }
    let freeEdgeX: CGFloat = side == .left ? outer.maxX - 1 : outer.minX + 1
    let sideBoundaryY = outer.minY + 18
    let sideBoundary = CGPoint(x: freeEdgeX, y: sideBoundaryY)
    let sideInside = CGPoint(x: freeEdgeX, y: sideBoundaryY.nextDown)
    let sideOutside = CGPoint(x: freeEdgeX, y: sideBoundaryY.nextUp)
    #expect(
      MenuPanelResizeGeometry.handle(at: sideBoundary, in: outer, fixedSide: side)
        == .farBottomCorner
    )
    #expect(
      MenuPanelResizeGeometry.handle(at: sideInside, in: outer, fixedSide: side)
        == .farBottomCorner
    )
    #expect(
      MenuPanelResizeGeometry.handle(at: sideOutside, in: outer, fixedSide: side)
        == .farSide
    )
    for probe in [bottomBoundary, bottomInside, bottomOutside, sideBoundary, sideInside,
      sideOutside]
    {
      #expect(
        menuPanelResizeLayoutRegionHandle(at: probe, in: layout)
          == MenuPanelResizeGeometry.handle(at: probe, in: outer, fixedSide: side)
      )
    }
  }
}

@Test func menuPanelResizeLayoutRejectsInvalidAndTooSmallBounds() {
  #expect(MenuPanelResizeGeometry.layout(in: .null, fixedSide: .left) == nil)
  #expect(MenuPanelResizeGeometry.layout(in: .infinite, fixedSide: .right) == nil)
  #expect(
    MenuPanelResizeGeometry.layout(
      in: CGRect(x: CGFloat.nan, y: 0, width: 380, height: 300), fixedSide: .left
    ) == nil
  )
  #expect(
    MenuPanelResizeGeometry.layout(
      in: CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 300), fixedSide: .right
    ) == nil
  )
  #expect(
    MenuPanelResizeGeometry.layout(
      in: CGRect(x: 0, y: 0, width: 380, height: CGFloat.nan), fixedSide: .left
    ) == nil
  )
  #expect(
    MenuPanelResizeGeometry.layout(
      in: CGRect(x: 0, y: 0, width: 0, height: 300), fixedSide: .left
    ) == nil
  )
  #expect(
    MenuPanelResizeGeometry.layout(
      in: CGRect(x: 0, y: 0, width: 3, height: 300), fixedSide: .left
    ) == nil
  )
  #expect(
    MenuPanelResizeGeometry.layout(
      in: CGRect(x: 0, y: 0, width: 380, height: 3), fixedSide: .right
    ) == nil
  )
  #expect(
    MenuPanelResizeGeometry.layout(
      in: CGRect(x: 0, y: 0, width: -380, height: 300), fixedSide: .left
    ) == nil
  )
  #expect(
    MenuPanelResizeGeometry.layout(
      in: CGRect(x: 0, y: 0, width: 380, height: -300), fixedSide: .right
    ) == nil
  )
  #expect(
    MenuPanelResizeGeometry.layout(
      in: CGRect(x: 0, y: 0, width: 380, height: 0), fixedSide: .right
    ) == nil
  )
  #expect(
    MenuPanelResizeGeometry.layout(
      in: CGRect(x: 0, y: 0, width: 380.5, height: 300), fixedSide: .left
    ) != nil
  )
}

private func menuPanelResizeLayoutCursorRegions(
  containing point: CGPoint,
  regions: [MenuPanelResizeLayout.Region]
) -> [MenuPanelResizeLayout.Region] {
  regions.filter { $0.rect.contains(point) }
}

private func menuPanelResizeLayoutCursorRegionHandle(
  at point: CGPoint,
  regions: [MenuPanelResizeLayout.Region]
) -> MenuPanelResizeHandle? {
  let matches = menuPanelResizeLayoutCursorRegions(containing: point, regions: regions)
  #expect(
    matches.count <= 1,
    "expected at most one cursor region at \(point), found \(matches.count)"
  )
  return matches.first?.handle
}

private func menuPanelResizeLayoutCheckCursorAgreement(
  at probes: [CGPoint],
  outer: CGRect,
  fixedSide: MenuPanelFixedSide,
  regions: [MenuPanelResizeLayout.Region]
) {
  for probe in probes {
    let admitted = MenuPanelResizeGeometry.handle(at: probe, in: outer, fixedSide: fixedSide)
    let covered = menuPanelResizeLayoutCursorRegionHandle(at: probe, regions: regions)
    #expect(
      covered == admitted,
      "cursor region \(String(describing: covered)) disagrees with admission \(String(describing: admitted)) at \(probe)"
    )
    if admitted != nil {
      #expect(outer.contains(probe))
    }
  }
}

private func menuPanelResizeLayoutCheckCursorDisjointness(
  _ regions: [MenuPanelResizeLayout.Region],
  outer: CGRect
) {
  #expect(!regions.isEmpty)
  for region in regions {
    let rect = region.rect
    #expect(!rect.isNull && !rect.isInfinite)
    #expect(rect.width > 0 && rect.height > 0)
    #expect(rect.minX >= outer.minX && rect.maxX <= outer.maxX)
    #expect(rect.minY >= outer.minY && rect.maxY <= outer.maxY)
  }
  for firstIndex in regions.indices {
    for secondIndex in regions.indices where secondIndex > firstIndex {
      let overlap = regions[firstIndex].rect.intersection(regions[secondIndex].rect)
      #expect(menuPanelResizeLayoutArea(overlap) <= 0.000_001)
    }
  }
}

@Test func menuPanelResizeLayoutCursorRegionsCoverTheAdmittedBandPastThePaintMargin() throws {
  let outers = [
    CGRect(x: 120.75, y: 210.25, width: 380, height: 300),
    CGRect(x: 0, y: 0, width: 380, height: 300),
    CGRect(x: -219.5, y: -88.25, width: 512.75, height: 641.5),
  ]
  for outer in outers {
    for side in menuPanelResizeLayoutSides {
      let layout = try #require(
        MenuPanelResizeGeometry.layout(in: outer, fixedSide: side)
      )
      let regions = MenuPanelResizeGeometry.cursorRegions(in: outer, fixedSide: side)
      menuPanelResizeLayoutCheckCursorDisjointness(regions, outer: outer)
      let farEdgeX: CGFloat = side == .left ? outer.maxX : outer.minX
      let inward: CGFloat = side == .left ? -1 : 1
      let bottomProbe = CGPoint(x: outer.midX, y: outer.minY + 6)
      let sideProbe = CGPoint(x: farEdgeX + inward * 6, y: outer.midY)
      for probe in [bottomProbe, sideProbe] {
        let admitted = MenuPanelResizeGeometry.handle(
          at: probe, in: outer, fixedSide: side
        )
        #expect(admitted != nil)
        #expect(
          menuPanelResizeLayoutCursorRegionHandle(at: probe, regions: regions) == admitted
        )
      }
      #expect(menuPanelResizeLayoutRegions(containing: bottomProbe, in: layout).isEmpty)
    }
  }
}

@Test func menuPanelResizeLayoutCursorRegionsMatchAdmissionAtBandAndCornerCuts() throws {
  let outers = [
    CGRect(x: 120.75, y: 210.25, width: 380, height: 300),
    CGRect(x: -219.5, y: -88.25, width: 512.75, height: 641.5),
  ]
  for outer in outers {
    for side in menuPanelResizeLayoutSides {
      let regions = MenuPanelResizeGeometry.cursorRegions(in: outer, fixedSide: side)
      menuPanelResizeLayoutCheckCursorDisjointness(regions, outer: outer)
      let farEdgeX: CGFloat = side == .left ? outer.maxX : outer.minX
      let inward: CGFloat = side == .left ? -1 : 1
      let bottomCut = outer.minY + 7
      let cornerCut = outer.minY + 18
      let farColumnCut = farEdgeX + inward * 7
      let cornerEdgeCut = farEdgeX + inward * 18
      let nearFarColumnX = farEdgeX + inward * 1
      let towardEdgeX = inward < 0 ? farColumnCut.nextUp : farColumnCut.nextDown
      let awayFromEdgeX = inward < 0 ? farColumnCut.nextDown : farColumnCut.nextUp
      var probes: [CGPoint] = []
      for y in [bottomCut.nextDown, bottomCut, bottomCut.nextUp] {
        probes.append(CGPoint(x: outer.midX, y: y))
        probes.append(CGPoint(x: nearFarColumnX, y: y))
      }
      for x in [towardEdgeX, farColumnCut, awayFromEdgeX] {
        probes.append(CGPoint(x: x, y: outer.midY))
      }
      for x in [cornerEdgeCut.nextDown, cornerEdgeCut, cornerEdgeCut.nextUp] {
        probes.append(CGPoint(x: x, y: outer.minY + 1))
      }
      for y in [cornerCut.nextDown, cornerCut, cornerCut.nextUp] {
        probes.append(CGPoint(x: nearFarColumnX, y: y))
      }
      menuPanelResizeLayoutCheckCursorAgreement(
        at: probes, outer: outer, fixedSide: side, regions: regions
      )
      #expect(
        MenuPanelResizeGeometry.handle(
          at: CGPoint(x: outer.midX, y: bottomCut), in: outer, fixedSide: side
        ) == .nearBottomCorner
      )
      #expect(
        MenuPanelResizeGeometry.handle(
          at: CGPoint(x: outer.midX, y: bottomCut.nextUp), in: outer, fixedSide: side
        ) == nil
      )
      #expect(
        MenuPanelResizeGeometry.handle(
          at: CGPoint(x: nearFarColumnX, y: bottomCut), in: outer, fixedSide: side
        ) == .farBottomCorner
      )
      #expect(
        MenuPanelResizeGeometry.handle(
          at: CGPoint(x: nearFarColumnX, y: cornerCut), in: outer, fixedSide: side
        ) == .farBottomCorner
      )
      #expect(
        MenuPanelResizeGeometry.handle(
          at: CGPoint(x: nearFarColumnX, y: cornerCut.nextUp), in: outer, fixedSide: side
        ) == .farSide
      )
      #expect(
        MenuPanelResizeGeometry.handle(
          at: CGPoint(x: farColumnCut, y: outer.midY), in: outer, fixedSide: side
        ) == .farSide
      )
      #expect(
        MenuPanelResizeGeometry.handle(
          at: CGPoint(x: awayFromEdgeX, y: outer.midY), in: outer, fixedSide: side
        ) == nil
      )
    }
  }
}

@Test func menuPanelResizeLayoutCursorRegionsCoverEveryAdmittedProbeExactlyOnce() throws {
  let outer = CGRect(x: 120.75, y: 210.25, width: 380, height: 300)
  let xs: [CGFloat] = [
    outer.minX + 0.5, outer.minX + 6.5, outer.minX + 7.5, outer.minX + 17.5,
    outer.minX + 18.5, outer.midX, outer.maxX - 18.5, outer.maxX - 17.5,
    outer.maxX - 7.5, outer.maxX - 6.5, outer.maxX - 0.5,
  ]
  let ys: [CGFloat] = [
    outer.minY + 0.5, outer.minY + 6.5, outer.minY + 7.5, outer.minY + 17.5,
    outer.minY + 18.5, outer.midY, outer.maxY - 0.5,
  ]
  for side in menuPanelResizeLayoutSides {
    let regions = MenuPanelResizeGeometry.cursorRegions(in: outer, fixedSide: side)
    for x in xs {
      for y in ys {
        let probe = CGPoint(x: x, y: y)
        let admitted = MenuPanelResizeGeometry.handle(
          at: probe, in: outer, fixedSide: side
        )
        let matches = menuPanelResizeLayoutCursorRegions(
          containing: probe, regions: regions
        )
        if let admitted {
          #expect(matches.count == 1)
          #expect(matches.first?.handle == admitted)
        } else {
          #expect(matches.isEmpty)
        }
      }
    }
  }
}

@Test func menuPanelResizeLayoutPaintedMarginRegionsStayAtThreePoints() throws {
  let outer = CGRect(x: 0, y: 0, width: 380, height: 300)
  let cornerTop = (outer.minY + MenuPanelResizeGeometry.cornerExtent).nextUp
  let cornerMaxX = (outer.minX + MenuPanelResizeGeometry.cornerExtent).nextUp
  func expectedRects(for side: MenuPanelFixedSide) -> [CGRect] {
    switch side {
    case .left:
      return [
        CGRect(x: 0, y: 0, width: 362, height: 3),
        CGRect(x: 362, y: 0, width: 18, height: 3),
        CGRect(x: 377, y: 3, width: 3, height: cornerTop - 3),
        CGRect(x: 377, y: cornerTop, width: 3, height: outer.maxY - cornerTop),
      ]
    case .right:
      return [
        CGRect(x: cornerMaxX, y: 0, width: outer.maxX - cornerMaxX, height: 3),
        CGRect(x: 0, y: 0, width: cornerMaxX, height: 3),
        CGRect(x: 0, y: 3, width: 3, height: cornerTop - 3),
        CGRect(x: 0, y: cornerTop, width: 3, height: outer.maxY - cornerTop),
      ]
    }
  }
  for side in menuPanelResizeLayoutSides {
    let layout = try #require(
      MenuPanelResizeGeometry.layout(in: outer, fixedSide: side)
    )
    let rects = layout.marginRegions.map(\.rect)
    let handles = layout.marginRegions.map(\.handle)
    let wanted = expectedRects(for: side)
    #expect(handles == [.nearBottomCorner, .farBottomCorner, .farBottomCorner, .farSide])
    #expect(rects.count == wanted.count)
    for (rect, want) in zip(rects, wanted) {
      #expect(menuPanelResizeLayoutRectsAlmostEqual(rect, want))
    }
  }
}

@Test func menuPanelResizeLayoutCursorRegionsRejectInvalidBoundsAndClampSmallOnes() {
  #expect(MenuPanelResizeGeometry.cursorRegions(in: .null, fixedSide: .left).isEmpty)
  #expect(MenuPanelResizeGeometry.cursorRegions(in: .infinite, fixedSide: .right).isEmpty)
  #expect(
    MenuPanelResizeGeometry.cursorRegions(
      in: CGRect(x: CGFloat.nan, y: 0, width: 380, height: 300), fixedSide: .left
    ).isEmpty
  )
  #expect(
    MenuPanelResizeGeometry.cursorRegions(
      in: CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 300), fixedSide: .right
    ).isEmpty
  )
  #expect(
    MenuPanelResizeGeometry.cursorRegions(
      in: CGRect(x: 0, y: 0, width: 380, height: 0), fixedSide: .left
    ).isEmpty
  )
  #expect(
    MenuPanelResizeGeometry.cursorRegions(
      in: CGRect(x: 0, y: 0, width: -380, height: 300), fixedSide: .left
    ).isEmpty
  )
  let smallOuters = [
    CGRect(x: 0, y: 0, width: 5, height: 5),
    CGRect(x: 12.5, y: -4.5, width: 4, height: 20),
    CGRect(x: 12.5, y: -4.5, width: 4, height: 12),
  ]
  for outer in smallOuters {
    for side in menuPanelResizeLayoutSides {
      let regions = MenuPanelResizeGeometry.cursorRegions(in: outer, fixedSide: side)
      menuPanelResizeLayoutCheckCursorDisjointness(regions, outer: outer)
      let farEdgeX: CGFloat = side == .left ? outer.maxX : outer.minX
      let inward: CGFloat = side == .left ? -1 : 1
      let probes = [
        CGPoint(x: outer.minX + 0.5, y: outer.minY + 0.5),
        CGPoint(x: farEdgeX + inward * 0.5, y: outer.maxY - 0.5),
        CGPoint(x: farEdgeX + inward * 0.5, y: min(outer.minY + 9.5, outer.maxY - 0.5)),
      ]
      menuPanelResizeLayoutCheckCursorAgreement(
        at: probes, outer: outer, fixedSide: side, regions: regions
      )
      for probe in probes {
        #expect(
          menuPanelResizeLayoutCursorRegionHandle(at: probe, regions: regions) != nil,
          "small bounds left \(probe) uncovered"
        )
      }
    }
  }
}
