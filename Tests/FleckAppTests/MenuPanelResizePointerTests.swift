import AppKit
import CoreGraphics
import Testing

@testable import FleckApp

@Test func resizeCanonicalPointerRejectsAbsentRepresentationAndNonfiniteValues() {
  #expect(MenuPanelResizePointerInput.canonicalPoint(from: nil) == nil)
  #expect(MenuPanelResizePointerInput.validated(nil) == nil)
  for point in [
    CGPoint(x: CGFloat.nan, y: 120), CGPoint(x: -420, y: CGFloat.nan),
    CGPoint(x: CGFloat.infinity, y: -180), CGPoint(x: -420, y: -CGFloat.infinity),
  ] {
    #expect(MenuPanelResizePointerInput.validated(point) == nil)
  }
  #expect(MenuPanelResizePointerInput.validated(.zero) == .zero)
}

@Test func resizeCanonicalPointerPreservesNegativeGlobalAxesAndFixedEdges() throws {
  let start = try #require(MenuPanelResizePointerInput.validated(CGPoint(x: -480, y: -180)))
  let end = try #require(MenuPanelResizePointerInput.validated(CGPoint(x: -504, y: -196)))
  #expect(start == CGPoint(x: -480, y: -180))
  #expect(end == CGPoint(x: -504, y: -196))
  let snapshot = MenuPanelResizeSnapshot(
    initialPointer: start,
    initialFrame: CGRect(x: -500, y: -200, width: 500, height: 430),
    initialContentSize: CGSize(width: 500, height: 430),
    frameInsets: .zero,
    visibleFrame: CGRect(x: -1_200, y: -700, width: 2_400, height: 1_700),
    statusLabelFrame: CGRect(x: -34, y: 240, width: 34, height: 22),
    fixedSide: .right
  )
  let proposal = try #require(MenuPanelResizeGeometry.proposal(
    snapshot: snapshot, pointer: end, handle: .farBottomCorner
  ))
  #expect(proposal.frame == CGRect(x: -524, y: -216, width: 524, height: 446))
  #expect(proposal.frame.maxX == snapshot.initialFrame.maxX)
  #expect(proposal.frame.maxY == snapshot.initialFrame.maxY)
}

@Test @MainActor func resizeCanonicalPointerDoesNotChangeWhenWindowFrameMoves() throws {
  let representation = try #require(CGEvent(
    mouseEventSource: nil, mouseType: .leftMouseUp,
    mouseCursorPosition: CGPoint(x: -504, y: 196), mouseButton: .left
  ))
  let point = try #require(MenuPanelResizePointerInput.canonicalPoint(from: representation))
  #expect(point.x == -504)
  let window = NSWindow(
    contentRect: CGRect(x: -500, y: -200, width: 500, height: 430),
    styleMask: .borderless, backing: .buffered, defer: false
  )
  let localBefore = window.convertPoint(fromScreen: point)
  window.setFrame(CGRect(x: -524, y: -216, width: 524, height: 446), display: false)
  let localAfter = window.convertPoint(fromScreen: point)
  #expect(localAfter == CGPoint(x: localBefore.x + 24, y: localBefore.y + 16))
  #expect(MenuPanelResizePointerInput.canonicalPoint(from: representation) == point)
}
