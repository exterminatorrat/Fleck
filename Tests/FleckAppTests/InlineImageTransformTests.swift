#if os(macOS)
import AppKit
import Testing

@testable import FleckApp

@Suite("InlineImageTransform")
struct InlineImageTransformTests {
  @Test(
    arguments: [
      (CGSize(width: 100, height: 50), 0.0, CGSize(width: 100, height: 50)),
      (CGSize(width: 100, height: 50), 90.0, CGSize(width: 50, height: 100)),
      (CGSize(width: 100, height: 50), 180.0, CGSize(width: 100, height: 50)),
      (CGSize(width: 100, height: 50), 270.0, CGSize(width: 50, height: 100)),
      (
        CGSize(width: 100, height: 40),
        45.0,
        CGSize(width: 98.99494936611666, height: 98.99494936611666)
      ),
    ]
  )
  func rotatedBoundsMatchTheAxisAlignedEnvelope(
    size: CGSize,
    degrees: Double,
    expected: CGSize
  ) {
    let transform = InlineImageTransform(size: size, rotationDegrees: degrees)
    expectClose(transform.rotatedSize, expected)
    let layout = transform.layout(centeredAt: CGPoint(x: 200, y: 100))
    expectClose(layout.bounds.size, expected)
    expectClose(layout.bounds.midX, 200)
    expectClose(layout.bounds.midY, 100)
  }

  @Test func layoutBoundsStayCenteredOnTheImageCenter() {
    let layout = InlineImageTransform(size: CGSize(width: 100, height: 50), rotationDegrees: 90)
      .layout(centeredAt: CGPoint(x: 200, y: 100))
    expectClose(layout.bounds.origin, CGPoint(x: 175, y: 50))
    expectClose(layout.bounds.size, CGSize(width: 50, height: 100))
  }

  @Test func eightHandlesSitOnCornersAndEdgeMidpoints() throws {
    let layout = InlineImageTransform(size: CGSize(width: 100, height: 50))
      .layout(centeredAt: CGPoint(x: 200, y: 100))

    #expect(layout.handleCenters.count == 8)
    let expected: [InlineImageHandle: CGPoint] = [
      .topLeft: CGPoint(x: 150, y: 75),
      .top: CGPoint(x: 200, y: 75),
      .topRight: CGPoint(x: 250, y: 75),
      .right: CGPoint(x: 250, y: 100),
      .bottomRight: CGPoint(x: 250, y: 125),
      .bottom: CGPoint(x: 200, y: 125),
      .bottomLeft: CGPoint(x: 150, y: 125),
      .left: CGPoint(x: 150, y: 100),
    ]
    for (handle, point) in expected {
      expectClose(try #require(layout.handleCenters[handle]), point)
    }
    #expect(layout.corners.count == 4)
    expectClose(layout.corners[0], CGPoint(x: 150, y: 75))
    expectClose(layout.corners[1], CGPoint(x: 250, y: 75))
    expectClose(layout.corners[2], CGPoint(x: 250, y: 125))
    expectClose(layout.corners[3], CGPoint(x: 150, y: 125))
  }

  @Test func handlePositionsFollowRotationAroundTheCenter() throws {
    let layout = InlineImageTransform(size: CGSize(width: 100, height: 50), rotationDegrees: 90)
      .layout(centeredAt: CGPoint(x: 200, y: 100))

    let expected: [InlineImageHandle: CGPoint] = [
      .topLeft: CGPoint(x: 225, y: 50),
      .top: CGPoint(x: 225, y: 100),
      .topRight: CGPoint(x: 225, y: 150),
      .right: CGPoint(x: 200, y: 150),
      .bottomRight: CGPoint(x: 175, y: 150),
      .bottom: CGPoint(x: 175, y: 100),
      .bottomLeft: CGPoint(x: 175, y: 50),
      .left: CGPoint(x: 200, y: 50),
    ]
    for (handle, point) in expected {
      expectClose(try #require(layout.handleCenters[handle]), point)
    }
    expectClose(layout.corners[0], CGPoint(x: 225, y: 50))
    expectClose(layout.corners[2], CGPoint(x: 175, y: 150))
  }

  @Test func rotationHandleSitsAboveTheTopMidpoint() throws {
    let upright = InlineImageTransform(size: CGSize(width: 100, height: 50))
      .layout(centeredAt: CGPoint(x: 200, y: 100))
    expectClose(upright.rotationHandleCenter, CGPoint(x: 200, y: 53))

    let quarterTurn = InlineImageTransform(
      size: CGSize(width: 100, height: 50),
      rotationDegrees: 90
    )
    .layout(centeredAt: CGPoint(x: 200, y: 100))
    expectClose(quarterTurn.rotationHandleCenter, CGPoint(x: 247, y: 100))
  }

  @Test func hitTestingUsesGenerousHandleTargets() {
    let layout = InlineImageTransform(size: CGSize(width: 100, height: 50))
      .layout(centeredAt: CGPoint(x: 200, y: 100))

    #expect(layout.hitTarget(at: CGPoint(x: 150, y: 75)) == .resize(.topLeft))
    #expect(layout.hitTarget(at: CGPoint(x: 144, y: 69)) == .resize(.topLeft))
    #expect(layout.hitTarget(at: CGPoint(x: 260, y: 100)) == .resize(.right))
    #expect(layout.hitTarget(at: CGPoint(x: 200, y: 53)) == .rotate)
    #expect(layout.hitTarget(at: CGPoint(x: 200, y: 63)) == .rotate)
    #expect(layout.hitTarget(at: CGPoint(x: 200, y: 100)) == .body)
    #expect(layout.hitTarget(at: CGPoint(x: 200, y: 20)) == .none)
    #expect(layout.hitTarget(at: CGPoint(x: 135, y: 60)) == .none)
  }

  @Test func rotatedContainmentUsesTheRotatedRectangleNotItsBounds() {
    let layout = InlineImageTransform(size: CGSize(width: 100, height: 50), rotationDegrees: 45)
      .layout(centeredAt: CGPoint(x: 200, y: 100))

    #expect(layout.bounds.contains(CGPoint(x: 250, y: 150)))
    #expect(layout.hitTarget(at: CGPoint(x: 250, y: 150)) == .none)
    #expect(layout.hitTarget(at: CGPoint(x: 200, y: 100)) == .body)
  }

  @Test func hitTestingRejectsNonFiniteInput() {
    let layout = InlineImageTransform(size: CGSize(width: 100, height: 50))
      .layout(centeredAt: CGPoint(x: 200, y: 100))

    #expect(layout.hitTarget(at: CGPoint(x: CGFloat.nan, y: 100)) == .none)
    #expect(layout.hitTarget(at: CGPoint(x: 150, y: 75), hitRadius: CGFloat.nan) == .none)
    #expect(layout.hitTarget(at: CGPoint(x: 150, y: 75), hitRadius: -1) == .none)
  }

  @Test func cornerResizePreservesRatioAndAnchorsOppositeCorner() throws {
    let original = InlineImageTransform(size: CGSize(width: 100, height: 50))
    let preview = try #require(
      original.resizePreview(
        dragging: .bottomRight,
        pointerDelta: CGSize(width: 50, height: 10),
        center: CGPoint(x: 200, y: 100)
      )
    )

    expectClose(preview.transform.size, CGSize(width: 150, height: 75))
    #expect(preview.transform.rotationDegrees == 0)
    expectClose(preview.anchor, CGPoint(x: 150, y: 75))
    expectClose(preview.center, CGPoint(x: 225, y: 112.5))
    expectClose(preview.layout.corners[0], CGPoint(x: 150, y: 75))
  }

  @Test func cornerResizeFollowsTheDominantPointerAxis() throws {
    let preview = try #require(
      InlineImageTransform(size: CGSize(width: 100, height: 50)).resizePreview(
        dragging: .bottomRight,
        pointerDelta: CGSize(width: 10, height: 40),
        center: CGPoint(x: 200, y: 100)
      )
    )

    expectClose(preview.transform.size, CGSize(width: 180, height: 90))
    expectClose(preview.center, CGPoint(x: 240, y: 120))
  }

  @Test func sideResizeChangesOneDimensionAndAnchorsOppositeEdge() throws {
    let original = InlineImageTransform(size: CGSize(width: 100, height: 50))
    let center = CGPoint(x: 200, y: 100)

    let right = try #require(
      original.resizePreview(
        dragging: .right,
        pointerDelta: CGSize(width: 40, height: 30),
        center: center
      )
    )
    expectClose(right.transform.size, CGSize(width: 140, height: 50))
    expectClose(right.anchor, CGPoint(x: 150, y: 100))
    expectClose(right.center, CGPoint(x: 220, y: 100))

    let top = try #require(
      original.resizePreview(
        dragging: .top,
        pointerDelta: CGSize(width: 30, height: 20),
        center: center
      )
    )
    expectClose(top.transform.size, CGSize(width: 100, height: 30))
    expectClose(top.anchor, CGPoint(x: 200, y: 125))
    expectClose(top.center, CGPoint(x: 200, y: 110))
  }

  @Test func rotatedResizeKeepsOppositeAnchorFixed() throws {
    let preview = try #require(
      InlineImageTransform(size: CGSize(width: 100, height: 50), rotationDegrees: 90)
        .resizePreview(
          dragging: .right,
          pointerDelta: CGSize(width: 0, height: 30),
          center: CGPoint(x: 200, y: 100)
        )
    )

    expectClose(preview.transform.size, CGSize(width: 130, height: 50))
    #expect(preview.transform.rotationDegrees == 90)
    expectClose(preview.anchor, CGPoint(x: 200, y: 50))
    expectClose(preview.center, CGPoint(x: 200, y: 115))
  }

  @Test(
    arguments: [
      (0.0, 0.0),
      (-45.0, 315.0),
      (360.0, 0.0),
      (725.0, 5.0),
      (450.0, 90.0),
      (-720.0, 0.0),
      (Double.nan, 0.0),
      (Double.infinity, 0.0),
    ]
  )
  func rotationNormalizesIntoOneClockwiseTurn(input: Double, expected: Double) {
    #expect(InlineImageTransform.normalizedRotation(input) == expected)
    #expect(
      InlineImageTransform(size: CGSize(width: 10, height: 10), rotationDegrees: input)
        .rotationDegrees == expected
    )
  }

  @Test func rotationPreviewTracksPointerAndPreservesSize() throws {
    let original = InlineImageTransform(size: CGSize(width: 100, height: 50))

    let above = try #require(
      original.rotationPreview(pointer: CGPoint(x: 0, y: -100), center: .zero)
    )
    #expect(above.transform.rotationDegrees == 0)
    expectClose(above.transform.size, CGSize(width: 100, height: 50))

    let right = try #require(
      original.rotationPreview(pointer: CGPoint(x: 100, y: 0), center: .zero)
    )
    #expect(right.transform.rotationDegrees == 90)
    expectClose(try #require(right.handleCenters[.topLeft]), CGPoint(x: 25, y: -50))
    expectClose(right.rotationHandleCenter, CGPoint(x: 47, y: 0))
  }

  @Test func rotationPreviewSnapsToFifteenDegreesUnlessDisabled() throws {
    let original = InlineImageTransform(size: CGSize(width: 100, height: 50))
    let pointerAngle = -43.0 * Double.pi / 180
    let pointer = CGPoint(x: 100 * cos(pointerAngle), y: 100 * sin(pointerAngle))

    let snapped = try #require(original.rotationPreview(pointer: pointer, center: .zero))
    #expect(snapped.transform.rotationDegrees == 45)

    let free = try #require(
      original.rotationPreview(pointer: pointer, center: .zero, snapDegrees: nil)
    )
    expectClose(free.transform.rotationDegrees, 47)
  }

  @Test func sideResizeStopsAtTheMinimumDimension() throws {
    let original = InlineImageTransform(size: CGSize(width: 100, height: 50))
    let center = CGPoint(x: 200, y: 100)

    let right = try #require(
      original.resizePreview(
        dragging: .right,
        pointerDelta: CGSize(width: -200, height: 0),
        center: center
      )
    )
    expectClose(right.transform.size, CGSize(width: 24, height: 50))
    expectClose(right.center, CGPoint(x: 162, y: 100))

    let top = try #require(
      original.resizePreview(
        dragging: .top,
        pointerDelta: CGSize(width: 0, height: 500),
        center: center
      )
    )
    expectClose(top.transform.size, CGSize(width: 100, height: 24))
    expectClose(top.center, CGPoint(x: 200, y: 113))
  }

  @Test func cornerResizeKeepsRatioAtTheMinimumDimension() throws {
    let preview = try #require(
      InlineImageTransform(size: CGSize(width: 100, height: 50)).resizePreview(
        dragging: .bottomRight,
        pointerDelta: CGSize(width: -500, height: -500),
        center: CGPoint(x: 200, y: 100)
      )
    )

    expectClose(preview.transform.size, CGSize(width: 48, height: 24))
    expectClose(
      preview.transform.size.width / preview.transform.size.height,
      2
    )
  }

  @Test func tinyOriginalsLoadWithoutUpscaling() throws {
    let transform = InlineImageTransform(size: CGSize(width: 10, height: 8))

    #expect(transform.isValid)
    expectClose(transform.size, CGSize(width: 10, height: 8))
    expectClose(transform.rotatedSize, CGSize(width: 10, height: 8))

    let layout = transform.layout(centeredAt: CGPoint(x: 50, y: 50))
    expectClose(try #require(layout.handleCenters[.topLeft]), CGPoint(x: 45, y: 46))
    expectClose(try #require(layout.handleCenters[.bottomRight]), CGPoint(x: 55, y: 54))
    let stationary = try #require(transform.resizePreview(
      dragging: .bottomRight, pointerDelta: .zero, center: CGPoint(x: 50, y: 50)
    ))
    #expect(stationary.transform == transform)
  }

  @Test func invalidExternalDimensionsAreRejectedSeparatelyFromTheDragFloor() {
    #expect(!InlineImageTransform(size: CGSize(width: 0, height: 50)).isValid)
    #expect(!InlineImageTransform(size: CGSize(width: 50, height: 0)).isValid)
    #expect(!InlineImageTransform(size: CGSize(width: -5, height: 10)).isValid)
    #expect(!InlineImageTransform(size: CGSize(width: CGFloat.nan, height: 10)).isValid)
    #expect(!InlineImageTransform(size: CGSize(width: 10, height: CGFloat.infinity)).isValid)
    #expect(InlineImageTransform(size: CGSize(width: 1, height: 1)).isValid)

    let invalid = InlineImageTransform(size: CGSize(width: CGFloat.nan, height: CGFloat.nan))
    #expect(invalid.size == .zero)
    #expect(invalid.rotatedSize == .zero)
    #expect(
      invalid.resizePreview(
        dragging: .right,
        pointerDelta: CGSize(width: 10, height: 0),
        center: .zero
      ) == nil
    )
    #expect(invalid.rotationPreview(pointer: CGPoint(x: 10, y: 0), center: .zero) == nil)
    #expect(!invalid.contains(.zero, centeredAt: .zero))
  }

  @Test func nonFiniteDragInputsProduceNoPreview() {
    let transform = InlineImageTransform(size: CGSize(width: 100, height: 50))
    let center = CGPoint(x: 200, y: 100)

    #expect(
      transform.resizePreview(
        dragging: .bottomRight,
        pointerDelta: CGSize(width: CGFloat.nan, height: 0),
        center: center
      ) == nil
    )
    #expect(
      transform.resizePreview(
        dragging: .bottomRight,
        pointerDelta: CGSize(width: 0, height: CGFloat.infinity),
        center: center
      ) == nil
    )
    #expect(
      transform.resizePreview(
        dragging: .bottomRight,
        pointerDelta: .zero,
        center: CGPoint(x: CGFloat.nan, y: 100)
      ) == nil
    )
    #expect(
      transform.rotationPreview(pointer: CGPoint(x: CGFloat.nan, y: 0), center: center) == nil
    )
    #expect(
      transform.rotationPreview(pointer: center, center: center) == nil
    )
    #expect(
      transform.rotationPreview(
        pointer: CGPoint(x: 210, y: 100),
        center: CGPoint(x: CGFloat.infinity, y: 100)
      ) == nil
    )
  }

  @Test func previewsDoNotMutateTheOriginalTransform() throws {
    let original = InlineImageTransform(size: CGSize(width: 100, height: 50), rotationDegrees: 30)
    let center = CGPoint(x: 10, y: 20)

    _ = try #require(
      original.resizePreview(
        dragging: .bottomRight,
        pointerDelta: CGSize(width: 20, height: 10),
        center: center
      )
    )
    _ = try #require(
      original.rotationPreview(pointer: CGPoint(x: 10, y: 0), center: center)
    )

    #expect(
      original == InlineImageTransform(size: CGSize(width: 100, height: 50), rotationDegrees: 30)
    )
  }

  private func expectClose(
    _ actual: Double,
    _ expected: Double,
    tolerance: Double = 0.000001,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    #expect(
      abs(actual - expected) <= tolerance,
      "\(actual) differs from \(expected)",
      sourceLocation: sourceLocation
    )
  }

  private func expectClose(
    _ actual: CGPoint,
    _ expected: CGPoint,
    tolerance: Double = 0.000001,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    expectClose(
      Double(actual.x),
      Double(expected.x),
      tolerance: tolerance,
      sourceLocation: sourceLocation
    )
    expectClose(
      Double(actual.y),
      Double(expected.y),
      tolerance: tolerance,
      sourceLocation: sourceLocation
    )
  }

  private func expectClose(
    _ actual: CGSize,
    _ expected: CGSize,
    tolerance: Double = 0.000001,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    expectClose(
      Double(actual.width),
      Double(expected.width),
      tolerance: tolerance,
      sourceLocation: sourceLocation
    )
    expectClose(
      Double(actual.height),
      Double(expected.height),
      tolerance: tolerance,
      sourceLocation: sourceLocation
    )
  }
}
#endif
