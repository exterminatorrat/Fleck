#if os(macOS)
import AppKit
import Foundation

struct InlineImageTransform: Equatable, Sendable {
  static let minimumDragDimension: CGFloat = 24
  static let rotationSnapDegrees: Double = 15

  let size: CGSize
  let rotationDegrees: Double

  init(size: CGSize, rotationDegrees: Double = 0) {
    self.size = CGSize(
      width: Self.validatedDimension(size.width),
      height: Self.validatedDimension(size.height)
    )
    self.rotationDegrees = Self.normalizedRotation(rotationDegrees)
  }

  var isValid: Bool {
    size.width > 0 && size.height > 0
  }

  var rotatedSize: CGSize {
    guard isValid else { return .zero }
    let (cosine, sine) = inlineImageTrig(rotationRadians)
    return CGSize(
      width: size.width * abs(cosine) + size.height * abs(sine),
      height: size.width * abs(sine) + size.height * abs(cosine)
    )
  }

  func fitting(availableWidth: CGFloat) -> InlineImageTransform {
    guard isValid, availableWidth.isFinite, availableWidth > 0 else { return self }
    let scale = min(1, availableWidth / rotatedSize.width)
    return InlineImageTransform(
      size: CGSize(width: size.width * scale, height: size.height * scale),
      rotationDegrees: rotationDegrees
    )
  }

  func layout(centeredAt center: CGPoint) -> InlineImageEditingLayout {
    InlineImageEditingLayout(transform: self, center: center)
  }

  func contains(_ point: CGPoint, centeredAt center: CGPoint) -> Bool {
    guard isValid,
      point.x.isFinite,
      point.y.isFinite,
      center.x.isFinite,
      center.y.isFinite
    else { return false }
    let local = inlineImageRotate(
      CGPoint(x: point.x - center.x, y: point.y - center.y),
      radians: -rotationRadians
    )
    return abs(local.x) <= size.width / 2 && abs(local.y) <= size.height / 2
  }

  func resizePreview(
    dragging handle: InlineImageHandle,
    pointerDelta: CGSize,
    center: CGPoint
  ) -> InlineImageResizePreview? {
    guard isValid,
      pointerDelta.width.isFinite,
      pointerDelta.height.isFinite,
      center.x.isFinite,
      center.y.isFinite
    else { return nil }

    if pointerDelta.width == 0, pointerDelta.height == 0 {
      let layout = layout(centeredAt: center)
      let anchor = inlineImageRotatedPoint(
        CGPoint(x: -handle.horizontalSign * size.width / 2, y: -handle.verticalSign * size.height / 2),
        radians: rotationRadians,
        around: center
      )
      return InlineImageResizePreview(layout: layout, anchor: anchor)
    }

    let radians = rotationRadians
    let localDelta = inlineImageRotate(
      CGPoint(x: pointerDelta.width, y: pointerDelta.height),
      radians: -radians
    )
    let horizontalSign = handle.horizontalSign
    let verticalSign = handle.verticalSign
    var width = size.width + horizontalSign * localDelta.x
    var height = size.height + verticalSign * localDelta.y

    if handle.isCorner {
      let widthScale = width / size.width
      let heightScale = height / size.height
      let scale = abs(widthScale - 1) >= abs(heightScale - 1) ? widthScale : heightScale
      let minimumScale = max(
        Self.minimumDragDimension / size.width,
        Self.minimumDragDimension / size.height
      )
      let appliedScale = max(scale, minimumScale)
      width = size.width * appliedScale
      height = size.height * appliedScale
    } else if horizontalSign != 0 {
      width = max(width, Self.minimumDragDimension)
    } else {
      height = max(height, Self.minimumDragDimension)
    }

    let anchor = inlineImageRotatedPoint(
      CGPoint(
        x: -horizontalSign * size.width / 2,
        y: -verticalSign * size.height / 2
      ),
      radians: radians,
      around: center
    )
    let offset = inlineImageRotate(
      CGPoint(x: horizontalSign * width / 2, y: verticalSign * height / 2),
      radians: radians
    )
    let nextCenter = CGPoint(x: anchor.x + offset.x, y: anchor.y + offset.y)
    let transform = InlineImageTransform(
      size: CGSize(width: width, height: height),
      rotationDegrees: rotationDegrees
    )
    return InlineImageResizePreview(
      layout: transform.layout(centeredAt: nextCenter),
      anchor: anchor
    )
  }

  func rotationPreview(
    pointer: CGPoint,
    center: CGPoint,
    snapDegrees: Double? = InlineImageTransform.rotationSnapDegrees
  ) -> InlineImageEditingLayout? {
    guard isValid,
      pointer.x.isFinite,
      pointer.y.isFinite,
      center.x.isFinite,
      center.y.isFinite
    else { return nil }
    let dx = Double(pointer.x - center.x)
    let dy = Double(pointer.y - center.y)
    guard dx != 0 || dy != 0 else { return nil }
    var degrees = atan2(dy, dx) * 180 / .pi + 90
    if let snapDegrees, snapDegrees.isFinite, snapDegrees > 0 {
      degrees = (degrees / snapDegrees).rounded() * snapDegrees
    }
    return InlineImageTransform(size: size, rotationDegrees: degrees)
      .layout(centeredAt: center)
  }

  static func normalizedRotation(_ degrees: Double) -> Double {
    guard degrees.isFinite else { return 0 }
    let remainder = degrees.truncatingRemainder(dividingBy: 360)
    let positive = remainder < 0 ? remainder + 360 : remainder
    return positive == 0 ? 0 : positive
  }

  private var rotationRadians: Double {
    rotationDegrees * .pi / 180
  }

  private static func validatedDimension(_ value: CGFloat) -> CGFloat {
    value.isFinite ? max(0, value) : 0
  }
}

enum InlineImageHandle: CaseIterable, Hashable, Sendable {
  case topLeft
  case top
  case topRight
  case right
  case bottomRight
  case bottom
  case bottomLeft
  case left

  var isCorner: Bool {
    switch self {
    case .topLeft, .topRight, .bottomRight, .bottomLeft:
      true
    case .top, .right, .bottom, .left:
      false
    }
  }

  var horizontalSign: CGFloat {
    switch self {
    case .topLeft, .left, .bottomLeft:
      -1
    case .top, .bottom:
      0
    case .topRight, .right, .bottomRight:
      1
    }
  }

  var verticalSign: CGFloat {
    switch self {
    case .topLeft, .top, .topRight:
      -1
    case .left, .right:
      0
    case .bottomLeft, .bottom, .bottomRight:
      1
    }
  }
}

enum InlineImageResizeDirection: CaseIterable, Hashable, Sendable {
  case right
  case topRight
  case top
  case topLeft
  case left
  case bottomLeft
  case bottom
  case bottomRight

  init(horizontalSign: CGFloat, verticalSign: CGFloat, rotationDegrees: Double) {
    let rotated = inlineImageRotate(
      CGPoint(x: horizontalSign, y: verticalSign),
      radians: rotationDegrees * .pi / 180
    )
    guard rotated.x.isFinite, rotated.y.isFinite else {
      self = InlineImageResizeDirection(horizontalSign: horizontalSign, verticalSign: verticalSign)
      return
    }
    let screenDegrees = atan2(Double(-rotated.y), Double(rotated.x)) * 180 / .pi
    let count = Self.allCases.count
    let octant = Int((screenDegrees / 45).rounded()) % count
    self = Self.allCases[(octant + count) % count]
  }

  var screenAngleDegrees: Double {
    Double(Self.allCases.firstIndex(of: self) ?? 0) * 45
  }

  private init(horizontalSign: CGFloat, verticalSign: CGFloat) {
    switch (horizontalSign, verticalSign) {
    case (0, -1): self = .top
    case (1, -1): self = .topRight
    case (1, 0): self = .right
    case (1, 1): self = .bottomRight
    case (0, 1): self = .bottom
    case (-1, 1): self = .bottomLeft
    case (-1, 0): self = .left
    default: self = .topLeft
    }
  }
}

extension InlineImageHandle {
  func resizeDirection(rotationDegrees: Double) -> InlineImageResizeDirection {
    InlineImageResizeDirection(
      horizontalSign: horizontalSign,
      verticalSign: verticalSign,
      rotationDegrees: rotationDegrees
    )
  }
}

enum InlineImageHitTarget: Equatable, Sendable {
  case resize(InlineImageHandle)
  case rotate
  case body
  case none
}

struct InlineImageEditingLayout: Equatable, Sendable {
  static let handleSize: CGFloat = 8
  static let handleHitRadius: CGFloat = 11
  static let handleCursorRectRadius: CGFloat = handleHitRadius * 0.7
  static let rotationHandleOffset: CGFloat = 22
  static let rotationHandleRadius: CGFloat = 9
  static let rotationGlyphSide: CGFloat = 12

  let transform: InlineImageTransform
  let center: CGPoint
  let corners: [CGPoint]
  let handleCenters: [InlineImageHandle: CGPoint]
  let rotationHandleCenter: CGPoint

  init(transform: InlineImageTransform, center: CGPoint, rotationHandleCenter: CGPoint? = nil) {
    self.transform = transform
    self.center = center
    let radians = transform.rotationDegrees * .pi / 180
    let halfWidth = transform.size.width / 2
    let halfHeight = transform.size.height / 2
    let place: (CGFloat, CGFloat) -> CGPoint = { horizontal, vertical in
      let offset = inlineImageRotate(
        CGPoint(x: horizontal * halfWidth, y: vertical * halfHeight),
        radians: radians
      )
      return CGPoint(x: center.x + offset.x, y: center.y + offset.y)
    }
    corners = [
      place(-1, -1),
      place(1, -1),
      place(1, 1),
      place(-1, 1),
    ]
    handleCenters = Dictionary(
      uniqueKeysWithValues: InlineImageHandle.allCases.map { handle in
        (handle, place(handle.horizontalSign, handle.verticalSign))
      }
    )
    let rotationOffset = inlineImageRotate(
      CGPoint(x: 0, y: -(halfHeight + Self.rotationHandleOffset)),
      radians: radians
    )
    self.rotationHandleCenter = rotationHandleCenter ?? CGPoint(
      x: center.x + rotationOffset.x,
      y: center.y + rotationOffset.y
    )
  }

  var bounds: CGRect {
    let size = transform.rotatedSize
    return CGRect(
      x: center.x - size.width / 2,
      y: center.y - size.height / 2,
      width: size.width,
      height: size.height
    )
  }

  func hitTarget(
    at point: CGPoint,
    hitRadius: CGFloat = InlineImageEditingLayout.handleHitRadius
  ) -> InlineImageHitTarget {
    guard transform.isValid,
      point.x.isFinite,
      point.y.isFinite,
      hitRadius.isFinite,
      hitRadius >= 0
    else { return .none }
    var nearest: InlineImageHitTarget?
    var nearestDistance = CGFloat.infinity
    for handle in InlineImageHandle.allCases {
      guard let handleCenter = handleCenters[handle] else { continue }
      let distance = inlineImageDistance(handleCenter, point)
      if distance <= hitRadius && distance < nearestDistance {
        nearest = .resize(handle)
        nearestDistance = distance
      }
    }
    let rotationDistance = inlineImageDistance(rotationHandleCenter, point)
    if rotationDistance <= hitRadius && rotationDistance < nearestDistance {
      nearest = .rotate
    }
    if let nearest { return nearest }
    return transform.contains(point, centeredAt: center) ? .body : .none
  }
}

struct InlineImageResizePreview: Equatable, Sendable {
  let layout: InlineImageEditingLayout
  let anchor: CGPoint

  var transform: InlineImageTransform { layout.transform }
  var center: CGPoint { layout.center }
}

private func inlineImageTrig(_ radians: Double) -> (cosine: CGFloat, sine: CGFloat) {
  let cosine = cos(radians)
  let sine = sin(radians)
  return (
    abs(cosine) < 1e-12 ? 0 : CGFloat(cosine),
    abs(sine) < 1e-12 ? 0 : CGFloat(sine)
  )
}

private func inlineImageRotate(_ point: CGPoint, radians: Double) -> CGPoint {
  let (cosine, sine) = inlineImageTrig(radians)
  return CGPoint(
    x: point.x * cosine - point.y * sine,
    y: point.x * sine + point.y * cosine
  )
}

private func inlineImageRotatedPoint(
  _ point: CGPoint,
  radians: Double,
  around center: CGPoint
) -> CGPoint {
  let rotated = inlineImageRotate(point, radians: radians)
  return CGPoint(x: center.x + rotated.x, y: center.y + rotated.y)
}

private func inlineImageDistance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
  let dx = first.x - second.x
  let dy = first.y - second.y
  return (dx * dx + dy * dy).squareRoot()
}
#endif
