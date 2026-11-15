#if os(macOS)
  import AppKit
  import Combine
  import CoreGraphics
  import SwiftUI

  enum MenuPanelFixedSide: Equatable {
    case left
    case right
  }

  enum MenuPanelResizeHandle: Equatable {
    case farSide
    case farBottomCorner
    case nearBottomCorner

    var changesWidth: Bool {
      self != .nearBottomCorner
    }

    var changesHeight: Bool {
      self != .farSide
    }
  }

  struct MenuPanelResizeLayout: Equatable {
    struct Region: Equatable {
      let rect: CGRect
      let handle: MenuPanelResizeHandle
    }

    let outerBounds: CGRect
    let bodyBounds: CGRect
    let fixedSide: MenuPanelFixedSide
    let marginRegions: [Region]

    func handle(at point: CGPoint) -> MenuPanelResizeHandle? {
      guard outerBounds.contains(point) else { return nil }
      return marginRegions.first { $0.rect.contains(point) }?.handle
    }

    var swiftUIBodyInsets: EdgeInsets {
      EdgeInsets(
        top: outerBounds.maxY - bodyBounds.maxY,
        leading: bodyBounds.minX - outerBounds.minX,
        bottom: bodyBounds.minY - outerBounds.minY,
        trailing: outerBounds.maxX - bodyBounds.maxX
      )
    }
  }

  enum MenuPanelResizeBodyPolicy: Equatable {
    case unready
    case inset(MenuPanelResizeLayout)
  }

  struct MenuPanelResizeCursorRegistration: Equatable {
    let rect: CGRect
    let handle: MenuPanelResizeHandle
    let fixedSide: MenuPanelFixedSide
  }

  struct MenuPanelFrameInsets: Equatable {
    var top: CGFloat
    var left: CGFloat
    var bottom: CGFloat
    var right: CGFloat

    static let zero = MenuPanelFrameInsets(top: 0, left: 0, bottom: 0, right: 0)

    var horizontal: CGFloat { left + right }
    var vertical: CGFloat { top + bottom }
  }

  struct MenuPanelResizeSnapshot: Equatable {
    var initialPointer: CGPoint
    var initialFrame: CGRect
    var initialContentSize: CGSize
    var frameInsets: MenuPanelFrameInsets
    var visibleFrame: CGRect
    var statusLabelFrame: CGRect
    var fixedSide: MenuPanelFixedSide
  }

  struct MenuPanelResizeProposal: Equatable {
    let contentSize: CGSize
    let frame: CGRect
    let isLegalPreference: Bool
    let fixedSide: MenuPanelFixedSide
  }

  enum MenuPanelResizeGeometry {
    static let minimumContentSize = CGSize(width: 380, height: 300)
    static let edgeThickness: CGFloat = 7
    static let cornerExtent: CGFloat = 18

    private static func isValid(_ rect: CGRect) -> Bool {
      !rect.isNull && !rect.isInfinite && !rect.isEmpty
    }

    private static func isValid(_ size: CGSize) -> Bool {
      size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }

    private static func isValid(_ insets: MenuPanelFrameInsets) -> Bool {
      [insets.top, insets.left, insets.bottom, insets.right].allSatisfy {
        $0.isFinite && $0 >= 0
      }
    }

    static func containedFrame(frame: CGRect, visibleFrame: CGRect) -> CGRect? {
      guard !frame.isNull, !frame.isInfinite, !frame.isEmpty,
        !visibleFrame.isNull, !visibleFrame.isInfinite, !visibleFrame.isEmpty,
        frame.origin.x.isFinite, frame.origin.y.isFinite,
        frame.width.isFinite, frame.height.isFinite,
        frame.minX.isFinite, frame.maxX.isFinite,
        frame.minY.isFinite, frame.maxY.isFinite,
        visibleFrame.origin.x.isFinite, visibleFrame.origin.y.isFinite,
        visibleFrame.width.isFinite, visibleFrame.height.isFinite,
        visibleFrame.minX.isFinite, visibleFrame.maxX.isFinite,
        visibleFrame.minY.isFinite, visibleFrame.maxY.isFinite,
        frame.width > 0, frame.height > 0,
        visibleFrame.width > 0, visibleFrame.height > 0
      else { return nil }

      let width = min(frame.width, visibleFrame.width)
      let height = min(frame.height, visibleFrame.height)
      let x = min(
        max(frame.minX, visibleFrame.minX),
        visibleFrame.maxX - width
      )
      let top = min(
        max(frame.maxY, visibleFrame.minY + height),
        visibleFrame.maxY
      )
      return CGRect(x: x, y: top - height, width: width, height: height)
    }

    static func fixedSide(
      panelFrame: CGRect,
      statusLabelFrame: CGRect
    ) -> MenuPanelFixedSide? {
      guard isValid(panelFrame), isValid(statusLabelFrame) else { return nil }
      let iconX = statusLabelFrame.midX
      return abs(iconX - panelFrame.minX) < abs(iconX - panelFrame.maxX) ? .left : .right
    }

    static func anchoredSide(
      panelFrame: CGRect,
      statusLabelFrame: CGRect
    ) -> MenuPanelFixedSide? {
      guard isValid(panelFrame), isValid(statusLabelFrame) else { return nil }
      if panelFrame.minX == statusLabelFrame.minX { return .left }
      if panelFrame.maxX == statusLabelFrame.maxX { return .right }
      return nil
    }

    static func presentation(
      contentSize: CGSize,
      inheritedFrame: CGRect,
      frameInsets: MenuPanelFrameInsets,
      visibleFrame: CGRect,
      statusLabelFrame: CGRect,
      preferredSide: MenuPanelFixedSide?
    ) -> MenuPanelResizeProposal? {
      guard isValid(contentSize), isValid(inheritedFrame), isValid(frameInsets),
        isValid(visibleFrame), isValid(statusLabelFrame),
        statusLabelFrame.minX >= visibleFrame.minX,
        statusLabelFrame.maxX <= visibleFrame.maxX
      else { return nil }

      let nearestSide = fixedSide(
        panelFrame: inheritedFrame,
        statusLabelFrame: statusLabelFrame
      ) ?? .right
      let requestedSide = preferredSide ?? nearestSide
      let otherSide: MenuPanelFixedSide = requestedSide == .left ? .right : .left
      let side: MenuPanelFixedSide
      if supportsStableMinimum(
        side: requestedSide,
        frameInsets: frameInsets,
        visibleFrame: visibleFrame,
        statusLabelFrame: statusLabelFrame
      ) {
        side = requestedSide
      } else if supportsStableMinimum(
        side: otherSide,
        frameInsets: frameInsets,
        visibleFrame: visibleFrame,
        statusLabelFrame: statusLabelFrame
      ) {
        side = otherSide
      } else {
        let requestedRoom = availableContentWidth(
          side: requestedSide,
          frameInsets: frameInsets,
          visibleFrame: visibleFrame,
          statusLabelFrame: statusLabelFrame
        )
        let otherRoom = availableContentWidth(
          side: otherSide,
          frameInsets: frameInsets,
          visibleFrame: visibleFrame,
          statusLabelFrame: statusLabelFrame
        )
        side = requestedRoom >= otherRoom ? requestedSide : otherSide
      }

      let fixedTop = min(inheritedFrame.maxY, visibleFrame.maxY)
      let maximumWidth = availableContentWidth(
        side: side,
        frameInsets: frameInsets,
        visibleFrame: visibleFrame,
        statusLabelFrame: statusLabelFrame
      )
      let maximumHeight = fixedTop - visibleFrame.minY - frameInsets.vertical
      guard maximumWidth > 0, maximumHeight > 0 else { return nil }

      let width = maximumWidth >= minimumContentSize.width
        ? min(max(contentSize.width, minimumContentSize.width), maximumWidth)
        : min(contentSize.width, maximumWidth)
      let height = maximumHeight >= minimumContentSize.height
        ? min(max(contentSize.height, minimumContentSize.height), maximumHeight)
        : min(contentSize.height, maximumHeight)
      return makeProposal(
        contentSize: CGSize(width: width, height: height),
        fixedTop: fixedTop,
        fixedSide: side,
        frameInsets: frameInsets,
        statusLabelFrame: statusLabelFrame
      )
    }

    static func handle(
      at point: CGPoint,
      in bounds: CGRect,
      fixedSide: MenuPanelFixedSide
    ) -> MenuPanelResizeHandle? {
      guard bounds.contains(point) else { return nil }
      let farEdgeX = fixedSide == .left ? bounds.maxX : bounds.minX
      let isBottomStrip = point.y <= bounds.minY + edgeThickness
      let isFarStrip =
        fixedSide == .left
        ? point.x >= bounds.maxX - edgeThickness
        : point.x <= bounds.minX + edgeThickness
      if isBottomStrip {
        return abs(point.x - farEdgeX) <= cornerExtent ? .farBottomCorner : .nearBottomCorner
      }
      if isFarStrip {
        return point.y - bounds.minY <= cornerExtent ? .farBottomCorner : .farSide
      }
      return nil
    }

    static let bodyMargin: CGFloat = 3

    static func layout(
      in bounds: CGRect,
      fixedSide: MenuPanelFixedSide
    ) -> MenuPanelResizeLayout? {
      guard isValid(bounds), bounds.minX.isFinite, bounds.minY.isFinite,
        bounds.maxX.isFinite, bounds.maxY.isFinite,
        bounds.size.width > bodyMargin, bounds.size.height > bodyMargin
      else { return nil }

      let bodyBounds: CGRect
      switch fixedSide {
      case .left:
        bodyBounds = CGRect(
          x: bounds.minX,
          y: bounds.minY + bodyMargin,
          width: bounds.width - bodyMargin,
          height: bounds.height - bodyMargin
        )
      case .right:
        bodyBounds = CGRect(
          x: bounds.minX + bodyMargin,
          y: bounds.minY + bodyMargin,
          width: bounds.width - bodyMargin,
          height: bounds.height - bodyMargin
        )
      }

      return MenuPanelResizeLayout(
        outerBounds: bounds,
        bodyBounds: bodyBounds,
        fixedSide: fixedSide,
        marginRegions: partitionedRegions(
          in: bounds,
          fixedSide: fixedSide,
          bottomThickness: bodyMargin,
          farThickness: bodyMargin,
          farStart: fixedSide == .left ? bounds.maxX - bodyMargin : bounds.minX
        )
      )
    }

    static func cursorRegions(
      in bounds: CGRect,
      fixedSide: MenuPanelFixedSide
    ) -> [MenuPanelResizeLayout.Region] {
      guard isValid(bounds), bounds.minX.isFinite, bounds.minY.isFinite,
        bounds.maxX.isFinite, bounds.maxY.isFinite,
        bounds.size.width > 0, bounds.size.height > 0
      else { return [] }
      let bottomThickness =
        min((bounds.minY + edgeThickness).nextUp, bounds.maxY) - bounds.minY
      let farStart = fixedSide == .left
        ? max(bounds.minX, bounds.maxX - edgeThickness)
        : bounds.minX
      let farThickness: CGFloat
      switch fixedSide {
      case .left:
        farThickness = bounds.maxX - farStart
      case .right:
        farThickness = min((bounds.minX + edgeThickness).nextUp, bounds.maxX) - bounds.minX
      }
      guard bottomThickness > 0, farThickness > 0 else { return [] }
      return partitionedRegions(
        in: bounds,
        fixedSide: fixedSide,
        bottomThickness: bottomThickness,
        farThickness: farThickness,
        farStart: farStart
      )
    }

    private static func partitionedRegions(
      in bounds: CGRect,
      fixedSide: MenuPanelFixedSide,
      bottomThickness: CGFloat,
      farThickness: CGFloat,
      farStart: CGFloat
    ) -> [MenuPanelResizeLayout.Region] {
      let cornerWidth = min(cornerExtent, bounds.width)
      let cornerMinX: CGFloat
      let cornerMaxX: CGFloat
      let nearMinX: CGFloat
      let nearMaxX: CGFloat
      switch fixedSide {
      case .left:
        cornerMaxX = bounds.maxX
        cornerMinX = bounds.maxX - cornerWidth
        nearMinX = bounds.minX
        nearMaxX = cornerMinX
      case .right:
        cornerMinX = bounds.minX
        cornerMaxX = min((bounds.minX + cornerWidth).nextUp, bounds.maxX)
        nearMinX = cornerMaxX
        nearMaxX = bounds.maxX
      }

      var regions: [MenuPanelResizeLayout.Region] = []
      if nearMaxX > nearMinX {
        regions.append(
          MenuPanelResizeLayout.Region(
            rect: CGRect(
              x: nearMinX,
              y: bounds.minY,
              width: nearMaxX - nearMinX,
              height: bottomThickness
            ),
            handle: .nearBottomCorner
          )
        )
      }
      regions.append(
        MenuPanelResizeLayout.Region(
          rect: CGRect(
            x: cornerMinX,
            y: bounds.minY,
            width: cornerMaxX - cornerMinX,
            height: bottomThickness
          ),
          handle: .farBottomCorner
        )
      )

      let sideBottom = bounds.minY + bottomThickness
      let cornerSideTop = min((bounds.minY + cornerExtent).nextUp, bounds.maxY)
      let cornerSideHeight = cornerSideTop - sideBottom
      if cornerSideHeight > 0 {
        regions.append(
          MenuPanelResizeLayout.Region(
            rect: CGRect(
              x: farStart,
              y: sideBottom,
              width: farThickness,
              height: cornerSideHeight
            ),
            handle: .farBottomCorner
          )
        )
      }
      let farSideBottom = sideBottom + max(cornerSideHeight, 0)
      if bounds.maxY > farSideBottom {
        regions.append(
          MenuPanelResizeLayout.Region(
            rect: CGRect(
              x: farStart,
              y: farSideBottom,
              width: farThickness,
              height: bounds.maxY - farSideBottom
            ),
            handle: .farSide
          )
        )
      }
      return regions
    }

    static func edgeRects(
      in bounds: CGRect,
      fixedSide: MenuPanelFixedSide
    ) -> [CGRect] {
      guard !bounds.isEmpty else { return [] }
      let farEdgeX = fixedSide == .left ? bounds.maxX - edgeThickness : bounds.minX
      return [
        CGRect(x: farEdgeX, y: bounds.minY, width: edgeThickness, height: bounds.height),
        CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: edgeThickness),
      ]
    }

    static func proposal(
      snapshot: MenuPanelResizeSnapshot,
      pointer: CGPoint,
      handle: MenuPanelResizeHandle,
      currentSide: MenuPanelFixedSide? = nil
    ) -> MenuPanelResizeProposal? {
      guard isValid(snapshot.initialFrame), isValid(snapshot.initialContentSize),
        isValid(snapshot.frameInsets), isValid(snapshot.visibleFrame),
        isValid(snapshot.statusLabelFrame), pointer.x.isFinite, pointer.y.isFinite,
        snapshot.initialPointer.x.isFinite, snapshot.initialPointer.y.isFinite,
        abs(
          snapshot.initialFrame.width
            - snapshot.initialContentSize.width - snapshot.frameInsets.horizontal
        ) <= 0.5,
        abs(
          snapshot.initialFrame.height
            - snapshot.initialContentSize.height - snapshot.frameInsets.vertical
        ) <= 0.5,
        snapshot.initialFrame.minX >= snapshot.visibleFrame.minX,
        snapshot.initialFrame.maxX <= snapshot.visibleFrame.maxX,
        snapshot.initialFrame.minY >= snapshot.visibleFrame.minY,
        snapshot.initialFrame.maxY <= snapshot.visibleFrame.maxY
      else { return nil }

      let initialSide = snapshot.fixedSide
      guard anchoredSide(
        panelFrame: snapshot.initialFrame,
        statusLabelFrame: snapshot.statusLabelFrame
      ) == initialSide else { return nil }

      var fixedSide = currentSide ?? initialSide
      if handle.changesWidth {
        let horizontalInsets = snapshot.frameInsets.horizontal
        let buttonWidth = snapshot.statusLabelFrame.width
        guard buttonWidth > horizontalInsets,
          supportsStableMinimum(
            side: .left,
            frameInsets: snapshot.frameInsets,
            visibleFrame: snapshot.visibleFrame,
            statusLabelFrame: snapshot.statusLabelFrame
          ) || supportsStableMinimum(
            side: .right,
            frameInsets: snapshot.frameInsets,
            visibleFrame: snapshot.visibleFrame,
            statusLabelFrame: snapshot.statusLabelFrame
          )
        else { return nil }

        let hysteresis = min(4, buttonWidth / 4)
        let destination: MenuPanelFixedSide?
        switch fixedSide {
        case .left where pointer.x < snapshot.statusLabelFrame.midX - hysteresis:
          destination = .right
        case .right where pointer.x > snapshot.statusLabelFrame.midX + hysteresis:
          destination = .left
        default:
          destination = nil
        }
        if let destination,
          supportsStableMinimum(
            side: destination,
            frameInsets: snapshot.frameInsets,
            visibleFrame: snapshot.visibleFrame,
            statusLabelFrame: snapshot.statusLabelFrame
          )
        {
          fixedSide = destination
        }
      }

      let deltaY = pointer.y - snapshot.initialPointer.y
      let fixedTop = snapshot.initialFrame.maxY
      let availableContentWidth = availableContentWidth(
        side: fixedSide,
        frameInsets: snapshot.frameInsets,
        visibleFrame: snapshot.visibleFrame,
        statusLabelFrame: snapshot.statusLabelFrame
      )
      let availableContentHeight = max(
        0,
        fixedTop - snapshot.visibleFrame.minY - snapshot.frameInsets.vertical
      )
      let maximumWidth = availableContentWidth
      let maximumHeight = availableContentHeight
      let minimumHeight = min(minimumContentSize.height, maximumHeight)

      let requestedWidth: CGFloat
      if handle.changesWidth {
        let button = snapshot.statusLabelFrame
        let grabDistance = snapshot.fixedSide == .left
          ? snapshot.initialFrame.maxX - snapshot.initialPointer.x
          : snapshot.initialPointer.x - snapshot.initialFrame.minX
        let distanceFromButton = max(button.minX - pointer.x, pointer.x - button.maxX, 0)
        let effectiveGrab = min(grabDistance, distanceFromButton)
        let requestedFrameWidth = fixedSide == .left
          ? max(button.width, pointer.x + effectiveGrab - button.minX)
          : max(button.width, button.maxX - pointer.x + effectiveGrab)
        requestedWidth = requestedFrameWidth - snapshot.frameInsets.horizontal
      } else {
        requestedWidth = snapshot.initialContentSize.width
      }
      let requestedHeight = handle.changesHeight
        ? snapshot.initialContentSize.height - deltaY
        : snapshot.initialContentSize.height
      let minimumWidth = handle.changesWidth
        ? snapshot.statusLabelFrame.width - snapshot.frameInsets.horizontal
        : min(minimumContentSize.width, maximumWidth)
      guard maximumWidth >= minimumWidth, minimumWidth > 0 else { return nil }
      let width = min(max(requestedWidth, minimumWidth), maximumWidth)
      let height = min(max(requestedHeight, minimumHeight), maximumHeight)
      return makeProposal(
        contentSize: CGSize(width: width, height: height),
        fixedTop: fixedTop,
        fixedSide: fixedSide,
        frameInsets: snapshot.frameInsets,
        statusLabelFrame: snapshot.statusLabelFrame
      )
    }

    static func releaseProposal(
      snapshot: MenuPanelResizeSnapshot,
      pointer: CGPoint,
      handle: MenuPanelResizeHandle,
      currentSide: MenuPanelFixedSide
    ) -> MenuPanelResizeProposal? {
      guard let transient = proposal(
        snapshot: snapshot,
        pointer: pointer,
        handle: handle,
        currentSide: currentSide
      ) else { return nil }
      let maximumWidth = availableContentWidth(
        side: transient.fixedSide,
        frameInsets: snapshot.frameInsets,
        visibleFrame: snapshot.visibleFrame,
        statusLabelFrame: snapshot.statusLabelFrame
      )
      let maximumHeight = snapshot.initialFrame.maxY - snapshot.visibleFrame.minY
        - snapshot.frameInsets.vertical
      guard maximumWidth >= minimumContentSize.width,
        maximumHeight >= minimumContentSize.height
      else { return nil }
      return makeProposal(
        contentSize: CGSize(
          width: min(max(transient.contentSize.width, minimumContentSize.width), maximumWidth),
          height: min(max(transient.contentSize.height, minimumContentSize.height), maximumHeight)
        ),
        fixedTop: snapshot.initialFrame.maxY,
        fixedSide: transient.fixedSide,
        frameInsets: snapshot.frameInsets,
        statusLabelFrame: snapshot.statusLabelFrame
      )
    }

    static func supportsStableMinimum(
      side: MenuPanelFixedSide,
      frameInsets: MenuPanelFrameInsets,
      visibleFrame: CGRect,
      statusLabelFrame: CGRect
    ) -> Bool {
      guard isValid(frameInsets), isValid(visibleFrame), isValid(statusLabelFrame) else {
        return false
      }
      guard statusLabelFrame.minX >= visibleFrame.minX,
        statusLabelFrame.maxX <= visibleFrame.maxX
      else { return false }
      return availableContentWidth(
        side: side,
        frameInsets: frameInsets,
        visibleFrame: visibleFrame,
        statusLabelFrame: statusLabelFrame
      ) >= minimumContentSize.width
    }

    private static func availableContentWidth(
      side: MenuPanelFixedSide,
      frameInsets: MenuPanelFrameInsets,
      visibleFrame: CGRect,
      statusLabelFrame: CGRect
    ) -> CGFloat {
      let availableFrameWidth = side == .left
        ? visibleFrame.maxX - statusLabelFrame.minX
        : statusLabelFrame.maxX - visibleFrame.minX
      return max(0, availableFrameWidth - frameInsets.horizontal)
    }

    private static func makeProposal(
      contentSize: CGSize,
      fixedTop: CGFloat,
      fixedSide: MenuPanelFixedSide,
      frameInsets: MenuPanelFrameInsets,
      statusLabelFrame: CGRect
    ) -> MenuPanelResizeProposal {
      let frameSize = CGSize(
        width: contentSize.width + frameInsets.horizontal,
        height: contentSize.height + frameInsets.vertical
      )
      let fixedX = fixedSide == .left ? statusLabelFrame.minX : statusLabelFrame.maxX
      return MenuPanelResizeProposal(
        contentSize: contentSize,
        frame: CGRect(
          x: fixedSide == .left ? fixedX : fixedX - frameSize.width,
          y: fixedTop - frameSize.height,
          width: frameSize.width,
          height: frameSize.height
        ),
        isLegalPreference: contentSize.width >= minimumContentSize.width
          && contentSize.height >= minimumContentSize.height,
        fixedSide: fixedSide
      )
    }
  }

  enum MenuPanelResizePublicationTiming: Equatable {
    case immediate
    case deferred
  }

  struct MenuPanelResizeInteractionIdentity: Equatable {
    let ownerID: UUID
    let revision: Int

    var successor: Self {
      Self(ownerID: ownerID, revision: revision &+ 1)
    }
  }

  enum MenuPanelResizePointerInput {
    static func canonicalPoint(from representation: CGEvent?) -> CGPoint? {
      validated(representation?.unflippedLocation)
    }

    static func validated(_ point: CGPoint?) -> CGPoint? {
      guard let point, point.x.isFinite, point.y.isFinite else { return nil }
      return point
    }
  }

  @MainActor
  final class MenuPanelResizeController: ObservableObject {
    @Published private(set) var effectiveContentSize: CGSize?
    @Published private(set) var publishedBodyPolicy = MenuPanelResizeBodyPolicy.unready
    private var desiredEffectiveContentSize: CGSize?
    private var desiredBodyPolicy = MenuPanelResizeBodyPolicy.unready
    private(set) var completedPreferenceSize: CGSize?
    private(set) var isTracking = false
    private var snapshot: MenuPanelResizeSnapshot?
    private var handle: MenuPanelResizeHandle?
    private var proposal: MenuPanelResizeProposal?
    private var lastPointer: CGPoint?
    private var interactionRevision = 0
    private var isPublishingContentSize = false
    private var needsContentSizePublication = false
    private var isPublishingBodyPolicy = false
    private var needsBodyPolicyPublication = false
    private var presentationOwnerID: UUID?
    private var relinquishPresentation: (@MainActor () -> Void)?
    private(set) var currentFixedSide: MenuPanelFixedSide?

    var publishedLayout: MenuPanelResizeLayout? {
      guard case let .inset(layout) = publishedBodyPolicy else { return nil }
      return layout
    }

    var initialFrame: CGRect? { snapshot?.initialFrame }
    var initialContentSize: CGSize? { snapshot?.initialContentSize }
    var currentProposal: MenuPanelResizeProposal? { proposal }
    var currentHandle: MenuPanelResizeHandle? { handle }

    @discardableResult
    func begin(
      snapshot: MenuPanelResizeSnapshot,
      handle: MenuPanelResizeHandle,
      ownerID: UUID? = nil
    ) -> Bool {
      guard presentationOwnerID == ownerID, !isTracking,
        !snapshot.initialFrame.isEmpty,
        !snapshot.visibleFrame.isEmpty,
        !snapshot.statusLabelFrame.isEmpty,
        MenuPanelResizeGeometry.proposal(
          snapshot: snapshot,
          pointer: snapshot.initialPointer,
          handle: handle,
          currentSide: snapshot.fixedSide
        ) != nil,
        MenuPanelResizeGeometry.supportsStableMinimum(
          side: snapshot.fixedSide,
          frameInsets: snapshot.frameInsets,
          visibleFrame: snapshot.visibleFrame,
          statusLabelFrame: snapshot.statusLabelFrame
        )
      else { return false }
      interactionRevision &+= 1
      let revision = interactionRevision
      self.snapshot = snapshot
      self.handle = handle
      proposal = nil
      lastPointer = snapshot.initialPointer
      currentFixedSide = snapshot.fixedSide
      completedPreferenceSize = nil
      isTracking = true
      setDesiredContentSize(snapshot.initialContentSize, publication: .immediate)
      return presentationOwnerID == ownerID && isTracking && interactionRevision == revision
    }

    @discardableResult
    func update(
      pointer: CGPoint,
      statusLabelFrame: CGRect?,
      visibleFrame: CGRect?,
      ownerID: UUID? = nil,
      canonicalize: (MenuPanelResizeProposal) -> MenuPanelResizeProposal? = { $0 }
    ) -> MenuPanelResizeProposal? {
      guard presentationOwnerID == ownerID, isTracking,
        let snapshot, let handle, let currentFixedSide,
        statusLabelFrame == snapshot.statusLabelFrame,
        visibleFrame == snapshot.visibleFrame
      else { return nil }
      let revision = interactionRevision
      guard let proposed = MenuPanelResizeGeometry.proposal(
        snapshot: snapshot,
        pointer: pointer,
        handle: handle,
        currentSide: currentFixedSide
      ), let proposal = canonicalize(proposed) else { return nil }
      guard presentationOwnerID == ownerID, isTracking,
        interactionRevision == revision
      else { return nil }
      interactionRevision &+= 1
      let publishedRevision = interactionRevision
      self.proposal = proposal
      lastPointer = pointer
      self.currentFixedSide = proposal.fixedSide
      setDesiredContentSize(proposal.contentSize, publication: .immediate)
      guard presentationOwnerID == ownerID, isTracking,
        interactionRevision == publishedRevision
      else { return nil }
      return proposal
    }

    func cancelIfGeometryChanged(
      statusLabelFrame: CGRect?,
      visibleFrame: CGRect?
    ) {
      guard let snapshot,
        statusLabelFrame == snapshot.statusLabelFrame,
        visibleFrame == snapshot.visibleFrame
      else {
        cancel()
        return
      }
    }

    func matchesGeometry(
      statusLabelFrame: CGRect?,
      visibleFrame: CGRect?
    ) -> Bool {
      guard let snapshot else { return false }
      return statusLabelFrame == snapshot.statusLabelFrame
        && visibleFrame == snapshot.visibleFrame
    }

    @discardableResult
    func finish() -> CGSize? {
      guard let snapshot, let proposal else { return nil }
      return finish(
        statusLabelFrame: snapshot.statusLabelFrame,
        visibleFrame: snapshot.visibleFrame,
        currentFrame: proposal.frame
      )?.contentSize
    }

    @discardableResult
    func finish(
      statusLabelFrame: CGRect?,
      visibleFrame: CGRect?,
      currentFrame: CGRect,
      ownerID: UUID? = nil,
      canonicalize: (MenuPanelResizeProposal) -> MenuPanelResizeProposal? = { $0 }
    ) -> MenuPanelResizeProposal? {
      let revision = interactionRevision
      guard presentationOwnerID == ownerID,
        isTracking, let snapshot, let handle, let proposal, let lastPointer,
        let currentFixedSide,
        statusLabelFrame == snapshot.statusLabelFrame,
        visibleFrame == snapshot.visibleFrame,
        currentFrame == proposal.frame,
        let finalProposal = MenuPanelResizeGeometry.releaseProposal(
          snapshot: snapshot,
          pointer: lastPointer,
          handle: handle,
          currentSide: currentFixedSide
        ).flatMap(canonicalize)
      else { return nil }
      guard presentationOwnerID == ownerID, isTracking,
        interactionRevision == revision
      else { return nil }
      interactionRevision &+= 1
      let completedRevision = interactionRevision
      isTracking = false
      self.handle = nil
      self.proposal = finalProposal
      self.currentFixedSide = finalProposal.fixedSide
      completedPreferenceSize = finalProposal.contentSize
      setDesiredContentSize(finalProposal.contentSize, publication: .immediate)
      guard presentationOwnerID == ownerID, !isTracking,
        interactionRevision == completedRevision
      else { return nil }
      return finalProposal
    }

    @discardableResult
    func cancel() -> CGRect? {
      cancelSnapshot()?.initialFrame
    }

    @discardableResult
    func cancelSnapshot(
      ownerID: UUID? = nil,
      publication: MenuPanelResizePublicationTiming = .immediate
    ) -> MenuPanelResizeSnapshot? {
      guard presentationOwnerID == ownerID, isTracking else { return nil }
      let snapshot = snapshot
      interactionRevision &+= 1
      isTracking = false
      self.snapshot = nil
      handle = nil
      proposal = nil
      lastPointer = nil
      currentFixedSide = nil
      completedPreferenceSize = nil
      setDesiredContentSize(nil, publication: publication)
      return snapshot
    }

    func isOwned(by ownerID: UUID) -> Bool {
      isTracking && presentationOwnerID == ownerID
    }

    var isUnownedTracking: Bool {
      isTracking && presentationOwnerID == nil
    }

    @discardableResult
    func claimPresentation(
      ownerID: UUID,
      onRelinquish: (@MainActor () -> Void)? = nil,
      publication: MenuPanelResizePublicationTiming = .immediate
    ) -> Bool {
      if presentationOwnerID == ownerID {
        if let onRelinquish { relinquishPresentation = onRelinquish }
        return true
      }
      let previousRelinquish = relinquishPresentation
      relinquishPresentation = nil
      previousRelinquish?()
      presentationOwnerID = ownerID
      relinquishPresentation = onRelinquish
      clearInteractionState(publication: publication)
      return presentationOwnerID == ownerID
    }

    @discardableResult
    func setPresentationRelinquish(
      ownerID: UUID,
      _ handler: @escaping @MainActor () -> Void
    ) -> Bool {
      guard presentationOwnerID == ownerID else { return false }
      relinquishPresentation = handler
      return true
    }

    @discardableResult
    func releasePresentation(
      ownerID: UUID,
      publication: MenuPanelResizePublicationTiming = .immediate
    ) -> Bool {
      guard presentationOwnerID == ownerID else { return false }
      let relinquish = relinquishPresentation
      relinquishPresentation = nil
      relinquish?()
      guard presentationOwnerID == ownerID else { return false }
      presentationOwnerID = nil
      clearInteractionState(publication: publication)
      return presentationOwnerID == nil
    }

    func isPresentationOwner(_ ownerID: UUID) -> Bool {
      presentationOwnerID == ownerID
    }

    var currentPresentationOwnerID: UUID? { presentationOwnerID }

    func interactionIdentity(ownerID: UUID) -> MenuPanelResizeInteractionIdentity? {
      guard presentationOwnerID == ownerID else { return nil }
      return MenuPanelResizeInteractionIdentity(ownerID: ownerID, revision: interactionRevision)
    }

    func presentationContentSize(ownerID: UUID) -> CGSize? {
      guard presentationOwnerID == ownerID else { return nil }
      return desiredEffectiveContentSize
    }

    @discardableResult
    func setPresentationContentSize(
      _ size: CGSize?,
      ownerID: UUID? = nil,
      publication: MenuPanelResizePublicationTiming = .immediate
    ) -> Bool {
      guard presentationOwnerID == ownerID else { return false }
      if (isTracking || completedPreferenceSize != nil), desiredEffectiveContentSize != size {
        interactionRevision &+= 1
      }
      let revision = interactionRevision
      setDesiredContentSize(size, publication: publication)
      return presentationOwnerID == ownerID && interactionRevision == revision
    }

    @discardableResult
    func publishPresentationContentSize(ownerID: UUID? = nil) -> Bool {
      guard presentationOwnerID == ownerID else { return false }
      let revision = interactionRevision
      publishDesiredContentSize()
      return presentationOwnerID == ownerID && interactionRevision == revision
    }

    @discardableResult
    func setPresentationLayout(
      _ layout: MenuPanelResizeLayout?,
      ownerID: UUID? = nil,
      publication: MenuPanelResizePublicationTiming = .immediate
    ) -> Bool {
      setPresentationBodyPolicy(
        layout.map(MenuPanelResizeBodyPolicy.inset) ?? .unready,
        ownerID: ownerID,
        publication: publication
      )
    }

    @discardableResult
    func setPresentationBodyPolicy(
      _ policy: MenuPanelResizeBodyPolicy,
      ownerID: UUID? = nil,
      publication: MenuPanelResizePublicationTiming = .immediate
    ) -> Bool {
      guard presentationOwnerID == ownerID else { return false }
      setDesiredBodyPolicy(policy, publication: publication)
      return presentationOwnerID == ownerID
    }

    @discardableResult
    func publishPresentationLayout(ownerID: UUID? = nil) -> Bool {
      guard presentationOwnerID == ownerID else { return false }
      publishDesiredBodyPolicy()
      return presentationOwnerID == ownerID
    }

    @discardableResult
    func cancelCompletion(ownerID: UUID? = nil) -> MenuPanelResizeSnapshot? {
      guard presentationOwnerID == ownerID,
        !isTracking, completedPreferenceSize != nil
      else { return nil }
      let snapshot = snapshot
      interactionRevision &+= 1
      self.snapshot = nil
      proposal = nil
      lastPointer = nil
      currentFixedSide = nil
      completedPreferenceSize = nil
      setDesiredContentSize(nil, publication: .immediate)
      return snapshot
    }

    @discardableResult
    func clearCompletion(
      preferredSize: CGSize? = nil,
      ownerID: UUID? = nil
    ) -> Bool {
      guard presentationOwnerID == ownerID, !isTracking else { return false }
      interactionRevision &+= 1
      let revision = interactionRevision
      snapshot = nil
      proposal = nil
      lastPointer = nil
      currentFixedSide = nil
      completedPreferenceSize = nil
      if preferredSize == nil || desiredEffectiveContentSize == preferredSize {
        _ = setPresentationContentSize(
          nil,
          ownerID: ownerID,
          publication: .immediate
        )
      }
      return presentationOwnerID == ownerID && interactionRevision == revision
    }

    private func clearInteractionState(publication: MenuPanelResizePublicationTiming) {
      interactionRevision &+= 1
      isTracking = false
      snapshot = nil
      handle = nil
      proposal = nil
      lastPointer = nil
      currentFixedSide = nil
      completedPreferenceSize = nil
      desiredEffectiveContentSize = nil
      desiredBodyPolicy = .unready
      switch publication {
      case .immediate:
        publishDesiredContentSize()
        publishDesiredBodyPolicy()
      case .deferred:
        needsContentSizePublication = false
        needsBodyPolicyPublication = false
      }
    }

    private func setDesiredBodyPolicy(
      _ policy: MenuPanelResizeBodyPolicy,
      publication: MenuPanelResizePublicationTiming
    ) {
      desiredBodyPolicy = policy
      if publication == .immediate {
        publishDesiredBodyPolicy()
      } else {
        needsBodyPolicyPublication = false
      }
    }

    private func publishDesiredBodyPolicy() {
      guard !isPublishingBodyPolicy else {
        needsBodyPolicyPublication = true
        return
      }
      isPublishingBodyPolicy = true
      defer { isPublishingBodyPolicy = false }
      repeat {
        needsBodyPolicyPublication = false
        if publishedBodyPolicy != desiredBodyPolicy {
          publishedBodyPolicy = desiredBodyPolicy
        }
      } while needsBodyPolicyPublication
    }

    private func setDesiredContentSize(
      _ size: CGSize?,
      publication: MenuPanelResizePublicationTiming
    ) {
      desiredEffectiveContentSize = size
      if publication == .immediate {
        publishDesiredContentSize()
      } else {
        needsContentSizePublication = false
      }
    }

    private func publishDesiredContentSize() {
      guard !isPublishingContentSize else {
        needsContentSizePublication = true
        return
      }
      isPublishingContentSize = true
      defer { isPublishingContentSize = false }
      repeat {
        needsContentSizePublication = false
        if effectiveContentSize != desiredEffectiveContentSize {
          effectiveContentSize = desiredEffectiveContentSize
        }
      } while needsContentSizePublication
    }
  }

  struct MenuPanelStatusButtonSourceIdentity: Equatable {
    fileprivate let token: UUID
  }

  struct MenuPanelStatusButtonGeometry: Equatable {
    let sourceIdentity: MenuPanelStatusButtonSourceIdentity
    let screenFrame: CGRect
  }

  @MainActor
  final class MenuPanelGeometryStore: ObservableObject {
    typealias WindowProvider = @MainActor () -> [NSWindow]

    private let windows: WindowProvider
    private weak var cachedButton: NSStatusBarButton?
    private weak var cachedWindow: NSWindow?
    private weak var cachedAttachment: NSView?
    private var cachedSourceIdentity: MenuPanelStatusButtonSourceIdentity?
    private(set) var rememberedFixedSide: MenuPanelFixedSide?

    init(windows: @escaping WindowProvider = { NSApplication.shared.windows }) {
      self.windows = windows
    }

    var statusLabelFrame: CGRect? { cachedStatusButton?.screenFrame }

    var cachedStatusButton: MenuPanelStatusButtonGeometry? {
      guard let button = cachedButton,
        let window = cachedWindow,
        let attachment = cachedAttachment,
        windows().contains(where: { $0 === window }),
        button.window === window,
        button.superview === attachment,
        let contentView = window.contentView,
        button === contentView || button.isDescendant(of: contentView),
        let sourceIdentity = cachedSourceIdentity,
        let screenFrame = screenFrame(for: button, in: window)
      else {
        clearCache()
        return nil
      }
      return geometry(
        sourceIdentity: sourceIdentity,
        screenFrame: screenFrame
      )
    }

    func rememberCompletedSide(_ side: MenuPanelFixedSide) {
      rememberedFixedSide = side
    }

    func resolveStatusButton() -> MenuPanelStatusButtonGeometry? {
      var matches: [(NSStatusBarButton, NSWindow, NSView, CGRect)] = []
      for window in windows() {
        guard let contentView = window.contentView else { continue }
        var pending = [contentView]
        while let view = pending.popLast() {
          if let button = view as? NSStatusBarButton,
            button.window === window,
            let attachment = button.superview,
            let screenFrame = screenFrame(for: button, in: window)
          {
            matches.append((button, window, attachment, screenFrame))
          }
          pending.append(contentsOf: view.subviews)
        }
      }
      guard matches.count == 1, let match = matches.first else {
        clearCache()
        return nil
      }
      let sourceIdentity: MenuPanelStatusButtonSourceIdentity
      if cachedButton === match.0,
        cachedWindow === match.1,
        cachedAttachment === match.2,
        let cachedSourceIdentity
      {
        sourceIdentity = cachedSourceIdentity
      } else {
        sourceIdentity = MenuPanelStatusButtonSourceIdentity(token: UUID())
      }
      cachedButton = match.0
      cachedWindow = match.1
      cachedAttachment = match.2
      cachedSourceIdentity = sourceIdentity
      return geometry(
        sourceIdentity: sourceIdentity,
        screenFrame: match.3
      )
    }

    private func screenFrame(
      for button: NSStatusBarButton,
      in window: NSWindow
    ) -> CGRect? {
      guard !button.bounds.isNull, !button.bounds.isInfinite, !button.bounds.isEmpty else {
        return nil
      }
      let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
      guard !frame.isNull, !frame.isInfinite, !frame.isEmpty else { return nil }
      return frame
    }

    private func geometry(
      sourceIdentity: MenuPanelStatusButtonSourceIdentity,
      screenFrame: CGRect
    ) -> MenuPanelStatusButtonGeometry {
      MenuPanelStatusButtonGeometry(
        sourceIdentity: sourceIdentity,
        screenFrame: screenFrame
      )
    }

    private func clearCache() {
      cachedButton = nil
      cachedWindow = nil
      cachedAttachment = nil
      cachedSourceIdentity = nil
    }
  }

  private struct MenuPanelGeometryStoreKey: EnvironmentKey {
    static let defaultValue: MenuPanelGeometryStore? = nil
  }

  extension EnvironmentValues {
    var menuPanelGeometryStore: MenuPanelGeometryStore? {
      get { self[MenuPanelGeometryStoreKey.self] }
      set { self[MenuPanelGeometryStoreKey.self] = newValue }
    }
  }

  @MainActor
  final class MenuPanelResizeInstallationView: NSView {
    struct Configuration {
      let geometryStore: MenuPanelGeometryStore?
      let preferredSize: CGSize
      let canResize: Bool
      let onCommit: (CGSize) -> Void
    }

    let host: MenuPanelResizeHostView
    private let authority: MenuPanelResizeInstallationAuthority
    private(set) var isDismantled = false
    private var configuration: Configuration?
    private var reconciliationRevision = 0
    private var isReconciling = false
    private var hasQueuedReconciliation = false

    init(controller: MenuPanelResizeController) {
      host = MenuPanelResizeHostView(controller: controller)
      let authority = MenuPanelResizeInstallationAuthority()
      self.authority = authority
      super.init(frame: .zero)
      authority.anchor = self
      host.adoptInstallationAuthority(authority)
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(
      geometryStore: MenuPanelGeometryStore?,
      preferredSize: CGSize,
      canResize: Bool,
      onCommit: @escaping (CGSize) -> Void
    ) {
      guard !isDismantled else { return }
      configuration = Configuration(
        geometryStore: geometryStore,
        preferredSize: preferredSize,
        canResize: canResize,
        onCommit: onCommit
      )
      reconciliationRevision &+= 1
      reconcileAttachment()
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      reconciliationRevision &+= 1
      reconcileAttachment()
    }

    override func layout() {
      super.layout()
      reconciliationRevision &+= 1
      reconcileAttachment()
    }

    override func viewDidHide() {
      super.viewDidHide()
      reconciliationRevision &+= 1
      reconcileAttachment()
    }

    override func viewDidUnhide() {
      super.viewDidUnhide()
      reconciliationRevision &+= 1
      reconcileAttachment()
    }

    func attachmentRevoked() {
      reconciliationRevision &+= 1
      queueReconciliation()
    }

    func dismantle() {
      guard !isDismantled else { return }
      isDismantled = true
      authority.revoke()
      detachHost()
      host.abandonInstallationAuthority()
    }

    private func reconcileAttachment() {
      guard !isDismantled else {
        detachHost()
        return
      }
      guard !isReconciling else {
        reconciliationRevision &+= 1
        queueReconciliation()
        return
      }
      isReconciling = true
      defer { isReconciling = false }
      let revision = reconciliationRevision
      guard !isHiddenOrHasHiddenAncestor, let target = authority.authorizesAnchor() else {
        detachHost()
        return
      }
      applyConfiguration()
      guard isCurrentTarget(target, revision: revision) else {
        queueReconciliation()
        return
      }
      attachHost(in: target, revision: revision)
      guard isCurrentTarget(target, revision: revision) else {
        queueReconciliation()
        return
      }
    }

    private func isCurrentTarget(
      _ target: (window: NSWindow, root: NSView),
      revision: Int
    ) -> Bool {
      guard revision == reconciliationRevision, !isDismantled,
        !isHiddenOrHasHiddenAncestor, let current = authority.authorizesAnchor()
      else { return false }
      return current.window === target.window && current.root === target.root
    }

    private func queueReconciliation() {
      guard !hasQueuedReconciliation, !isDismantled else { return }
      hasQueuedReconciliation = true
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.hasQueuedReconciliation = false
        self.reconcileAttachment()
      }
    }

    private func applyConfiguration() {
      guard let configuration else { return }
      host.configure(
        geometryStore: configuration.geometryStore,
        preferredSize: configuration.preferredSize,
        canResize: configuration.canResize,
        onCommit: configuration.onCommit
      )
    }

    private func attachHost(
      in target: (window: NSWindow, root: NSView),
      revision: Int
    ) {
      let root = target.root
      host.isHidden = isHiddenOrHasHiddenAncestor
      guard isCurrentTarget(target, revision: revision) else { return }
      if host.superview === root {
        if host.frame != root.bounds {
          host.frame = root.bounds
          guard isCurrentTarget(target, revision: revision) else { return }
        }
        if root.subviews.last !== host {
          root.addSubview(host, positioned: .above, relativeTo: nil)
          guard isCurrentTarget(target, revision: revision) else { return }
        }
        if !host.isInstalled, isCurrentTarget(target, revision: revision) {
          host.installIfNeeded()
        }
        return
      }
      host.uninstall()
      guard isCurrentTarget(target, revision: revision) else { return }
      host.completeNativeDetachment()
      guard isCurrentTarget(target, revision: revision) else { return }
      if host.superview != nil {
        host.removeFromSuperview()
        guard isCurrentTarget(target, revision: revision) else { return }
      }
      host.frame = root.bounds
      guard isCurrentTarget(target, revision: revision) else { return }
      host.autoresizingMask = [.width, .height]
      root.addSubview(host, positioned: .above, relativeTo: nil)
      guard isCurrentTarget(target, revision: revision) else { return }
      if !host.isInstalled {
        host.installIfNeeded()
      }
    }

    private func detachHost() {
      host.isHidden = false
      host.uninstall()
      host.completeNativeDetachment()
      if host.superview != nil {
        host.removeFromSuperview()
      }
    }
  }

  @MainActor
  final class MenuPanelResizeInstallationAuthority {
    weak var anchor: MenuPanelResizeInstallationView?
    private(set) var capturedOwnerID: UUID?
    private(set) weak var capturedWindow: NSWindow?
    private(set) var isRevoked = false

    func capture(ownerID: UUID, window: NSWindow) {
      capturedOwnerID = ownerID
      capturedWindow = window
    }

    func revoke() {
      guard !isRevoked else { return }
      isRevoked = true
      anchor?.attachmentRevoked()
    }

    func revoke(ownerID: UUID) {
      guard capturedOwnerID == ownerID else { return }
      revoke()
    }

    func captured(ownerID: UUID, window: NSWindow?) -> Bool {
      capturedOwnerID == ownerID && capturedWindow === window
    }

    func authorizesAnchor() -> (window: NSWindow, root: NSView)? {
      guard !isRevoked, let anchor, !anchor.isDismantled,
        !anchor.isHiddenOrHasHiddenAncestor,
        let window = anchor.window, let root = window.contentView,
        root !== anchor, anchor.isDescendant(of: root), !root.isDescendant(of: anchor)
      else { return nil }
      return (window, root)
    }

    func authorizes(_ host: MenuPanelResizeHostView) -> (window: NSWindow, root: NSView)? {
      guard let target = authorizesAnchor(), host.superview === target.root,
        host !== anchor, !target.root.isDescendant(of: host)
      else { return nil }
      return target
    }
  }

  struct MenuPanelResizeInstaller: NSViewRepresentable {
    let controller: MenuPanelResizeController
    let geometryStore: MenuPanelGeometryStore?
    let preferredSize: CGSize
    let canResize: Bool
    let onCommit: (CGSize) -> Void

    func makeNSView(context: Context) -> MenuPanelResizeInstallationView {
      let view = MenuPanelResizeInstallationView(controller: controller)
      view.configure(
        geometryStore: geometryStore,
        preferredSize: preferredSize,
        canResize: canResize,
        onCommit: onCommit
      )
      return view
    }

    func updateNSView(_ view: MenuPanelResizeInstallationView, context: Context) {
      view.configure(
        geometryStore: geometryStore,
        preferredSize: preferredSize,
        canResize: canResize,
        onCommit: onCommit
      )
    }

    static func dismantleNSView(_ view: MenuPanelResizeInstallationView, coordinator: ()) {
      view.dismantle()
    }
  }

  struct ReorderAwareMenuPanelResizeInstaller: View {
    @ObservedObject var dragSession: ReorderDropSession
    let controller: MenuPanelResizeController
    let geometryStore: MenuPanelGeometryStore?
    let preferredSize: CGSize
    let canResize: Bool
    let onCommit: (CGSize) -> Void

    var body: some View {
      MenuPanelResizeInstaller(
        controller: controller,
        geometryStore: geometryStore,
        preferredSize: preferredSize,
        canResize: canResize && !dragSession.isDragging,
        onCommit: onCommit
      )
    }
  }

  enum MenuPanelResizeBeginReadiness {
    case ready(
      snapshot: MenuPanelResizeSnapshot,
      handle: MenuPanelResizeHandle,
      ownerID: UUID,
      statusButtonSource: MenuPanelStatusButtonSourceIdentity
    )
    case reconciling
    case blocked
  }

  @MainActor
  final class MenuPanelResizeHostView: NSView {
    typealias FallbackVisibleFrameProvider = @MainActor (NSWindow) -> CGRect?

    private let controller: MenuPanelResizeController
    private let fallbackVisibleFrameProvider: FallbackVisibleFrameProvider
    private var attachmentID: UUID?
    private weak var geometryStore: MenuPanelGeometryStore?
    private weak var installedWindow: NSWindow?
    private var monitor: Any?
    private var cursorTrackingAreas: [NSTrackingArea] = []
    private var visibilityObservation: NSKeyValueObservation?
    private var foreignChildrenObservation: NSObjectProtocol?
    private var knownForeignChildren: Set<ObjectIdentifier> = []
    private var previousAcceptsMouseMovedEvents: Bool?
    private var preferredSize = CGSize.zero
    private var hasPreferredSize = false
    private var canResize = false
    private var onCommit: (CGSize) -> Void = { _ in }
    private var cursor: NSCursor?
    private lazy var leftFixedCornerCursor = diagonalCursor(rotatedClockwise: true)
    private lazy var rightFixedCornerCursor = diagonalCursor(rotatedClockwise: false)
    private var activeStatusButtonSource: MenuPanelStatusButtonSourceIdentity?
    private var alignedStatusButtonSource: MenuPanelStatusButtonSourceIdentity?
    private var alignedStatusButtonFrame: CGRect?
    private var alignedVisibleFrame: CGRect?
    private var alignedFixedSide: MenuPanelFixedSide?
    private var alignedFrame: CGRect?
    private var presentationTop: CGFloat?
    private var pendingExternalPreference = false
    private var isPresented = false
    private var isApplyingFrame = false
    private var installationRevision = 0
    private var stateRevision = 0
    private var queuedRevision: Int?
    private var queuedCursorRefreshInstallation: Int?
    private var queuedLayoutPublication: Int?
    private var cachedHoverCursorRegistrations: [MenuPanelResizeCursorRegistration]?
    private weak var installationAuthority: MenuPanelResizeInstallationAuthority?
    private var hasRequiredInstallationAuthority = false
    private var isInstallationAbandoned = false
    private var pendingNativeReleaseOwner: UUID?
    private var suppressedRevocationOwners: Set<UUID> = []
    private var installedCursorAreaSpecs: [MenuPanelResizeCursorRegistration] = []
    private var cursorAreaRevision = 0
    private var cursorAreaRefreshInstallation: Int?
    private var isReconcilingCursorAreas = false
    private var isProbingContent = false

    var isInstalled: Bool { monitor != nil && installedWindow != nil }
    private var ownsTracking: Bool {
      attachmentID.map { controller.isOwned(by: $0) } ?? false
    }
    private var ownsPresentation: Bool {
      attachmentID.map(controller.isPresentationOwner) ?? false
    }

    init(
      controller: MenuPanelResizeController,
      fallbackVisibleFrameProvider: FallbackVisibleFrameProvider? = nil
    ) {
      self.controller = controller
      self.fallbackVisibleFrameProvider = fallbackVisibleFrameProvider ?? { window in
        Self.publicFallbackVisibleFrame(for: window)
      }
      super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? {
      guard !isProbingContent, isInstalled, ownsPresentation,
        let window = installedWindow, self.window === window, window.isVisible,
        !isHiddenOrHasHiddenAncestor, isLiveResizeEligible(in: window),
        let fixedSide = alignedFixedSide, let superview
      else { return nil }
      let location = convert(point, from: superview)
      guard bounds.contains(location),
        usableHandle(at: convert(location, to: nil), in: window, fixedSide: fixedSide) != nil
      else { return nil }
      return self
    }

    override func viewDidHide() {
      super.viewDidHide()
      invalidateResizeCursorRegions()
    }

    override func viewDidUnhide() {
      super.viewDidUnhide()
      invalidateResizeCursorRegions()
    }

    override func resetCursorRects() {
      super.resetCursorRects()
    }

    func cursorRegistrations(fresh: Bool = false) -> [MenuPanelResizeCursorRegistration] {
      guard let window = installedWindow, self.window === window,
        structurallyCursorEligible(in: window)
      else { return [] }
      if ownsTracking, let handle = controller.currentHandle,
        let fixedSide = controller.currentFixedSide
      {
        let clip = bounds.intersection(visibleRect)
        guard !clip.isNull, clip.width > 0, clip.height > 0 else { return [] }
        return [
          MenuPanelResizeCursorRegistration(
            rect: clip,
            handle: handle,
            fixedSide: fixedSide
          )
        ]
      }
      return hoverCursorRegistrations(in: window, fresh: fresh)
    }

    private func hoverCursorRegistrations(
      in window: NSWindow,
      fresh: Bool = false
    ) -> [MenuPanelResizeCursorRegistration] {
      if !fresh, let cachedHoverCursorRegistrations {
        return cachedHoverCursorRegistrations
      }
      let clip = bounds.intersection(visibleRect)
      guard let fixedSide = controller.currentFixedSide ?? alignedFixedSide, !clip.isEmpty
      else {
        cachedHoverCursorRegistrations = []
        return []
      }
      let regions = MenuPanelResizeGeometry.cursorRegions(in: bounds, fixedSide: fixedSide)
      let marginRects = regions.map { $0.rect.intersection(clip) }
        .filter { !$0.isNull && $0.width > 0 && $0.height > 0 }
      let obstructions = obstructingResizeRects(in: window, clippedTo: marginRects)
      let registrations = regions.flatMap {
        region -> [MenuPanelResizeCursorRegistration] in
        let clipped = region.rect.intersection(clip)
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return [] }
        var pieces = [clipped]
        for obstruction in obstructions {
          pieces = pieces.flatMap { subtracting(obstruction, from: $0) }
        }
        return pieces.map {
          MenuPanelResizeCursorRegistration(
            rect: $0,
            handle: region.handle,
            fixedSide: fixedSide
          )
        }
      }
      cachedHoverCursorRegistrations = registrations
      return registrations
    }

    private func obstructingResizeRects(in window: NSWindow, clippedTo clips: [CGRect]) -> [CGRect] {
      guard let contentView = window.contentView else { return [] }
      var rects: [CGRect] = []
      var pending: [NSView] = [contentView]
      while let view = pending.popLast() {
        guard !view.isHiddenOrHasHiddenAncestor else { continue }
        pending.append(contentsOf: view.subviews)
        if let control = view as? NSControl, !(control is NSScroller), control.isEnabled {
          for clip in clips {
            if let rect = hostRect(control.bounds, of: control, clippedTo: clip, in: window) {
              rects.append(rect)
            }
          }
          continue
        }
        if let textView = view as? NSTextView {
          for clip in clips {
            rects.append(contentsOf: glyphRects(in: textView, clippedTo: clip, in: window))
          }
        }
      }
      return rects
    }

    private func glyphRects(
      in textView: NSTextView,
      clippedTo clip: CGRect,
      in window: NSWindow
    ) -> [CGRect] {
      guard let manager = textView.layoutManager, let container = textView.textContainer,
        let visibleClip = hostRect(textView.bounds, of: textView, clippedTo: clip, in: window)
      else { return [] }
      let containerClip = textView.convert(convert(visibleClip, to: nil), from: nil).offsetBy(
        dx: -textView.textContainerOrigin.x,
        dy: -textView.textContainerOrigin.y
      )
      let glyphRange = manager.glyphRange(forBoundingRect: containerClip, in: container)
      guard glyphRange.length > 0 else { return [] }
      var rects: [CGRect] = []
      for index in glyphRange.location..<NSMaxRange(glyphRange) {
        let glyphBounds = manager.boundingRect(
          forGlyphRange: NSRange(location: index, length: 1),
          in: container
        )
        guard glyphBounds.width > 0, glyphBounds.height > 0 else { continue }
        let containerRect = glyphBounds.offsetBy(
          dx: textView.textContainerOrigin.x,
          dy: textView.textContainerOrigin.y
        )
        guard let rect = hostRect(containerRect, of: textView, clippedTo: clip, in: window) else {
          continue
        }
        rects.append(rect)
      }
      return rects
    }

    private func hostRect(
      _ rect: CGRect,
      of view: NSView,
      clippedTo clip: CGRect,
      in window: NSWindow
    ) -> CGRect? {
      guard view.window === window else { return nil }
      let visible = rect.intersection(view.visibleRect)
      guard !visible.isNull, visible.width > 0, visible.height > 0 else { return nil }
      let clipped = convert(view.convert(visible, to: nil), from: nil).intersection(clip)
      guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return nil }
      return clipped
    }

    private func subtracting(_ cut: CGRect, from rect: CGRect) -> [CGRect] {
      let overlap = rect.intersection(cut)
      guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { return [rect] }
      return [
        CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: overlap.minY - rect.minY),
        CGRect(x: rect.minX, y: overlap.maxY, width: rect.width, height: rect.maxY - overlap.maxY),
        CGRect(
          x: rect.minX,
          y: overlap.minY,
          width: overlap.minX - rect.minX,
          height: overlap.height
        ),
        CGRect(
          x: overlap.maxX,
          y: overlap.minY,
          width: rect.maxX - overlap.maxX,
          height: overlap.height
        ),
      ].filter { $0.width > 0 && $0.height > 0 }
    }

    private func structurallyCursorEligible(in window: NSWindow) -> Bool {
      isInstalled && ownsPresentation && installedWindow === window && self.window === window
        && window.isVisible && !isHiddenOrHasHiddenAncestor
        && isLiveResizeEligible(in: window)
    }

    private func nativeCursorOwnerEligible(in window: NSWindow) -> Bool {
      structurallyCursorEligible(in: window) && window.isKeyWindow
        && NSApplication.shared.isActive
    }

    override func updateTrackingAreas() {
      super.updateTrackingAreas()
      reconcileCursorTrackingAreas()
    }

    private func reconcileCursorTrackingAreas() {
      guard !isReconcilingCursorAreas else {
        cursorAreaRevision &+= 1
        requestCursorAreaRefresh()
        return
      }
      isReconcilingCursorAreas = true
      defer { isReconcilingCursorAreas = false }
      let installation = installationRevision
      guard let attachment = attachmentID, let window = installedWindow,
        isInstalled, controller.isPresentationOwner(attachment),
        installedWindow === window, self.window === window
      else {
        removeCursorTracking()
        return
      }
      let revision = cursorAreaRevision
      let specs = cursorRegistrations(fresh: true)
      guard revision == cursorAreaRevision, installation == installationRevision,
        controller.isPresentationOwner(attachment),
        installedWindow === window, self.window === window
      else {
        requestCursorAreaRefresh()
        return
      }
      installCursorTrackingAreas(specs)
    }

    private func requestCursorAreaRefresh() {
      let installation = installationRevision
      guard cursorAreaRefreshInstallation != installation else { return }
      cursorAreaRefreshInstallation = installation
      DispatchQueue.main.async { [weak self] in
        guard let self, self.cursorAreaRefreshInstallation == installation,
          self.installationRevision == installation
        else { return }
        self.cursorAreaRefreshInstallation = nil
        self.reconcileCursorTrackingAreas()
      }
    }

    private func installCursorTrackingAreas(
      _ specs: [MenuPanelResizeCursorRegistration]
    ) {
      let stillAttached = cursorTrackingAreas.allSatisfy { area in
        trackingAreas.contains { $0 === area }
      }
      if stillAttached, installedCursorAreaSpecs == specs {
        return
      }
      removeCursorTracking()
      cursorTrackingAreas = specs.map {
        NSTrackingArea(
          rect: $0.rect,
          options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeInKeyWindow],
          owner: self,
          userInfo: nil
        )
      }
      installedCursorAreaSpecs = specs
      for area in cursorTrackingAreas {
        addTrackingArea(area)
      }
    }

    override func mouseMoved(with event: NSEvent) {
      super.mouseMoved(with: event)
      updateHoverCursor(from: event)
    }

    override func cursorUpdate(with event: NSEvent) {
      guard let attachmentID, let window = installedWindow,
        controller.isPresentationOwner(attachmentID), event.window === window,
        nativeCursorOwnerEligible(in: window)
      else {
        if cursor != nil { resetCursor() }
        super.cursorUpdate(with: event)
        return
      }
      guard updateCursor(for: event, in: window) else {
        super.cursorUpdate(with: event)
        return
      }
      scheduleCursorRefresh()
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      installIfNeeded()
    }

    override func layout() {
      super.layout()
      reconcileNativePresentation()
    }

    override func setFrameSize(_ newSize: NSSize) {
      let geometryChanged = frame.size != newSize
      super.setFrameSize(newSize)
      if geometryChanged {
        refreshResizeLayout()
        scheduleCursorRefresh()
      }
    }

    func configure(
      geometryStore: MenuPanelGeometryStore?,
      preferredSize: CGSize,
      canResize: Bool,
      onCommit: @escaping (CGSize) -> Void
    ) {
      let geometryStoreChanged = self.geometryStore !== geometryStore
      let preferredSizeChanged = hasPreferredSize && self.preferredSize != preferredSize
      self.geometryStore = geometryStore
      self.preferredSize = preferredSize
      hasPreferredSize = true
      self.canResize = canResize
      self.onCommit = onCommit
      if preferredSizeChanged {
        pendingExternalPreference = true
      }
      if geometryStoreChanged || preferredSizeChanged || !canResize {
        invalidateQueuedWork()
      }
      reconcileNativePresentation()
    }

    func adoptInstallationAuthority(_ authority: MenuPanelResizeInstallationAuthority) {
      hasRequiredInstallationAuthority = true
      installationAuthority = authority
    }

    func abandonInstallationAuthority() {
      isInstallationAbandoned = true
      installationAuthority = nil
    }

    func completeNativeDetachment() {
      guard let token = pendingNativeReleaseOwner else { return }
      releasePendingNativeDetachment(matching: token)
    }

    private func releasePendingNativeDetachment(matching token: UUID) {
      guard pendingNativeReleaseOwner == token else { return }
      pendingNativeReleaseOwner = nil
      guard controller.isPresentationOwner(token) else { return }
      let released = suppressNativeRevocation(ownerID: token) {
        controller.releasePresentation(ownerID: token, publication: .deferred)
      }
      guard released else { return }
      deferObservablePublication()
    }

    private func deferObservablePublication() {
      DispatchQueue.main.async { [weak self, controller] in
        guard controller.currentPresentationOwnerID == nil else { return }
        withExtendedLifetime(self) {}
        _ = controller.publishPresentationContentSize()
        _ = controller.publishPresentationLayout()
      }
    }

    private func signalExternalHandoff(
      ownerID: UUID,
      window: NSWindow?,
      authority: MenuPanelResizeInstallationAuthority?
    ) {
      guard let authority, authority.captured(ownerID: ownerID, window: window) else {
        return
      }
      authority.revoke(ownerID: ownerID)
      if pendingNativeReleaseOwner == ownerID {
        pendingNativeReleaseOwner = nil
      }
    }

    private func suppressNativeRevocation<Result>(
      ownerID: UUID,
      _ operation: () -> Result
    ) -> Result {
      let inserted = suppressedRevocationOwners.insert(ownerID).inserted
      defer {
        if inserted { suppressedRevocationOwners.remove(ownerID) }
      }
      return operation()
    }

    private func isAuthorizedForInstallation() -> Bool {
      guard !isInstallationAbandoned else { return false }
      guard hasRequiredInstallationAuthority else { return true }
      guard let installationAuthority else { return false }
      return installationAuthority.authorizes(self) != nil
    }

    func installIfNeeded() {
      guard isAuthorizedForInstallation() else {
        uninstall()
        return
      }
      guard installedWindow !== window else {
        if let window, window.isVisible, !isPresented {
          isPresented = true
          presentationTop = nil
          invalidateQueuedWork()
        }
        reconcileNativePresentation()
        return
      }
      uninstall()
      if hasRequiredInstallationAuthority {
        completeNativeDetachment()
        guard isAuthorizedForInstallation() else { return }
      }
      guard let window else { return }
      installedWindow = window
      let attachmentID = UUID()
      self.attachmentID = attachmentID
      installationRevision &+= 1
      isPresented = window.isVisible
      invalidateQueuedWork()
      acquirePresentation(ownerID: attachmentID, window: window)
    }

    func uninstall() {
      let oldAttachmentID = attachmentID
      let oldWindow = installedWindow
      let controller = controller
      let wasPresentationOwner = oldAttachmentID.map(controller.isPresentationOwner) ?? false
      if let oldAttachmentID, wasPresentationOwner {
        suppressNativeRevocation(ownerID: oldAttachmentID) {
          makeOwnedNativeCleanup(ownerID: oldAttachmentID, window: oldWindow)()
        }
        _ = controller.setPresentationRelinquish(
          ownerID: oldAttachmentID,
          makeDeferredRelinquishHandler(
            ownerID: oldAttachmentID,
            window: oldWindow,
            geometryStore: geometryStore,
            fallbackVisibleFrameProvider: fallbackVisibleFrameProvider
          )
        )
        pendingNativeReleaseOwner = oldAttachmentID
      }
      installationRevision &+= 1
      invalidateQueuedWork()
      installedWindow = nil
      attachmentID = nil
      activeStatusButtonSource = nil
      clearAlignment()
      presentationTop = nil
      isPresented = false
      guard let oldAttachmentID else { return }
      if wasPresentationOwner {
        DispatchQueue.main.async { [self] in
          self.releasePendingNativeDetachment(matching: oldAttachmentID)
        }
      } else {
        removeNativeHooksWithoutRestoringWindow(oldWindow)
      }
    }

    private func acquirePresentation(ownerID: UUID, window: NSWindow) {
      guard isAuthorizedForInstallation() else { return }
      guard controller.claimPresentation(ownerID: ownerID, publication: .deferred),
        attachmentID == ownerID, installedWindow === window, self.window === window
      else { return }
      installationAuthority?.capture(ownerID: ownerID, window: window)
      guard isAuthorizedForInstallation() else {
        uninstall()
        return
      }

      isPresented = window.isVisible
      if !isPresented { presentationTop = nil }
      let previousAcceptsMouseMovedEvents = window.acceptsMouseMovedEvents
      self.previousAcceptsMouseMovedEvents = previousAcceptsMouseMovedEvents
      window.acceptsMouseMovedEvents = true
      let monitor = NSEvent.addLocalMonitorForEvents(
        matching: [
          .leftMouseDown, .leftMouseDragged, .leftMouseUp,
          .mouseMoved, .mouseExited, .cursorUpdate, .keyDown,
        ]
      ) { [weak self] event in
        guard let self else { return event }
        return self.handle(event)
      }
      self.monitor = monitor
      installWindowObservers(for: window)
      installVisibilityObservation(for: window, ownerID: ownerID)
      installForeignChildObservation(for: window)
      _ = controller.setPresentationRelinquish(
        ownerID: ownerID,
        makeRelinquishHandler(ownerID: ownerID, window: window)
      )
      invalidateQueuedWork()
      reconcileNativePresentation()
    }

    private func makeRelinquishHandler(
      ownerID: UUID,
      window: NSWindow
    ) -> @MainActor () -> Void {
      let cleanup = makeOwnedNativeCleanup(ownerID: ownerID, window: window)
      let rollback = makeDeferredRelinquishHandler(
        ownerID: ownerID,
        window: window,
        geometryStore: geometryStore,
        fallbackVisibleFrameProvider: fallbackVisibleFrameProvider
      )
      return {
        cleanup()
        rollback()
      }
    }

    private func makeOwnedNativeCleanup(
      ownerID: UUID,
      window: NSWindow?
    ) -> @MainActor () -> Void {
      let monitor = monitor
      let visibilityObservation = visibilityObservation
      let previousAcceptsMouseMovedEvents = previousAcceptsMouseMovedEvents
      let authority = installationAuthority
      return { [weak self, weak controller, weak window] in
        guard controller?.isPresentationOwner(ownerID) == true else { return }
        if let self, !self.suppressedRevocationOwners.contains(ownerID) {
          self.signalExternalHandoff(ownerID: ownerID, window: window, authority: authority)
        }
        if let monitor { NSEvent.removeMonitor(monitor) }
        visibilityObservation?.invalidate()
        if let self {
          self.removeWindowObservers(for: window)
          self.removeForeignChildObservation()
          self.monitor = nil
          self.visibilityObservation = nil
          self.previousAcceptsMouseMovedEvents = nil
          self.activeStatusButtonSource = nil
          self.clearAlignment()
          self.presentationTop = nil
          self.invalidateQueuedWork()
          self.removeCursorTracking()
          self.resetCursor()
          self.invalidateResizeCursorRegions()
        } else {
          NSCursor.arrow.set()
        }
        if let window,
          let previousAcceptsMouseMovedEvents,
          window.acceptsMouseMovedEvents != previousAcceptsMouseMovedEvents
        {
          window.acceptsMouseMovedEvents = previousAcceptsMouseMovedEvents
        }
      }
    }

    private func makeDeferredRelinquishHandler(
      ownerID: UUID,
      window: NSWindow?,
      geometryStore: MenuPanelGeometryStore?,
      fallbackVisibleFrameProvider: @escaping FallbackVisibleFrameProvider
    ) -> @MainActor () -> Void {
      let authority = installationAuthority
      return { [weak self, weak controller, weak window, weak geometryStore] in
        if let self, !self.suppressedRevocationOwners.contains(ownerID) {
          self.signalExternalHandoff(ownerID: ownerID, window: window, authority: authority)
        }
        let snapshot = controller?.cancelSnapshot(
          ownerID: ownerID,
          publication: .deferred
        )
        if let snapshot, let window {
          Self.restore(
            snapshot: snapshot,
            in: window,
            geometryStore: geometryStore,
            fallbackVisibleFrameProvider: fallbackVisibleFrameProvider
          )
        }
      }
    }

    private func installWindowObservers(for window: NSWindow) {
      let center = NotificationCenter.default
      center.addObserver(
        self,
        selector: #selector(windowResignedKey),
        name: NSWindow.didResignKeyNotification,
        object: window
      )
      center.addObserver(
        self,
        selector: #selector(windowWillClose),
        name: NSWindow.willCloseNotification,
        object: window
      )
      center.addObserver(
        self,
        selector: #selector(windowPresented),
        name: NSWindow.didBecomeKeyNotification,
        object: window
      )
      center.addObserver(
        self,
        selector: #selector(windowGeometryChanged),
        name: NSWindow.didMoveNotification,
        object: window
      )
      center.addObserver(
        self,
        selector: #selector(windowGeometryChanged),
        name: NSWindow.didResizeNotification,
        object: window
      )
      center.addObserver(
        self,
        selector: #selector(windowGeometryChanged),
        name: NSWindow.didChangeScreenNotification,
        object: window
      )
      center.addObserver(
        self,
        selector: #selector(windowGeometryChanged),
        name: NSApplication.didChangeScreenParametersNotification,
        object: nil
      )
    }

    private func installForeignChildObservation(for window: NSWindow) {
      knownForeignChildren = visibleForeignChildren(of: window)
      foreignChildrenObservation = NotificationCenter.default.addObserver(
        forName: NSApplication.didUpdateNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.reconcileForeignChildrenBoundary()
        }
      }
    }

    private func visibleForeignChildren(of window: NSWindow) -> Set<ObjectIdentifier> {
      Set(
        (window.childWindows ?? [])
          .filter { $0.isVisible }
          .map(ObjectIdentifier.init)
      )
    }

    private func reconcileForeignChildrenBoundary() {
      guard let window = installedWindow, self.window === window else {
        knownForeignChildren = []
        return
      }
      let current = visibleForeignChildren(of: window)
      guard current != knownForeignChildren else { return }
      knownForeignChildren = current
      refreshResizeLayout()
    }

    private func removeForeignChildObservation() {
      if let foreignChildrenObservation {
        NotificationCenter.default.removeObserver(foreignChildrenObservation)
      }
      foreignChildrenObservation = nil
      knownForeignChildren = []
    }

    private func installVisibilityObservation(for window: NSWindow, ownerID: UUID) {
      visibilityObservation = window.observe(\.isVisible, options: [.old, .new]) {
        [weak self, weak controller, weak window] _, change in
        MainActor.assumeIsolated {
          guard let self, let window,
            self.attachmentID == ownerID,
            self.installedWindow === window,
            self.window === window,
            controller?.isPresentationOwner(ownerID) == true,
            let isVisible = change.newValue,
            change.oldValue != isVisible
          else { return }
          self.isPresented = isVisible
          self.presentationTop = nil
          self.invalidateQueuedWork()
          if isVisible {
            self.reconcileNativePresentation()
          } else {
            self.scheduleReconcile()
          }
        }
      }
    }

    private func removeWindowObservers(for window: NSWindow?) {
      let center = NotificationCenter.default
      center.removeObserver(
        self,
        name: NSWindow.didResignKeyNotification,
        object: window
      )
      center.removeObserver(
        self,
        name: NSWindow.willCloseNotification,
        object: window
      )
      center.removeObserver(
        self,
        name: NSWindow.didBecomeKeyNotification,
        object: window
      )
      center.removeObserver(
        self,
        name: NSWindow.didMoveNotification,
        object: window
      )
      center.removeObserver(
        self,
        name: NSWindow.didResizeNotification,
        object: window
      )
      center.removeObserver(
        self,
        name: NSWindow.didChangeScreenNotification,
        object: window
      )
      center.removeObserver(
        self,
        name: NSApplication.didChangeScreenParametersNotification,
        object: nil
      )
    }

    private func removeNativeHooksWithoutRestoringWindow(_ window: NSWindow?) {
      removeForeignChildObservation()
      invalidateResizeCursorRegions()
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
      visibilityObservation?.invalidate()
      visibilityObservation = nil
      removeWindowObservers(for: window)
      previousAcceptsMouseMovedEvents = nil
      removeCursorTracking()
      cursor = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
      reconcileForeignChildrenBoundary()
      guard let attachmentID, controller.isPresentationOwner(attachmentID),
        let window = installedWindow,
        event.window === window
      else { return event }
      guard window.isVisible else {
        resetCursor()
        return event
      }
      let canonicalPointer: CGPoint?
      switch event.type {
      case .leftMouseDown:
        guard isLiveResizeEligible(in: window) else { return event }
        canonicalPointer = MenuPanelResizePointerInput.canonicalPoint(from: event.cgEvent)
      case .leftMouseDragged, .leftMouseUp:
        guard controller.isOwned(by: attachmentID) else { return event }
        guard isLiveResizeEligible(in: window) else {
          cancelAndRestore(in: window)
          return nil
        }
        canonicalPointer = MenuPanelResizePointerInput.canonicalPoint(from: event.cgEvent)
      default:
        canonicalPointer = nil
      }
      switch event.type {
      case .leftMouseDown:
        guard let canonicalPointer else { return event }
        return begin(pointer: canonicalPointer, in: window) ? nil : event
      case .leftMouseDragged:
        guard let canonicalPointer else {
          cancelAndRestore(in: window)
          return nil
        }
        update(pointer: canonicalPointer, in: window)
        return nil
      case .leftMouseUp:
        guard let canonicalPointer else {
          cancelAndRestore(in: window)
          return nil
        }
        finish(pointer: canonicalPointer, in: window)
        return nil
      case .keyDown where event.keyCode == 53 && ownsTracking:
        cancelAndRestore(in: window)
        return nil
      case .cursorUpdate:
        guard ownsTracking else { return event }
        let handled = updateCursor(for: event, in: window)
        guard handled else { return event }
        scheduleCursorRefresh()
        return nil
      case .mouseExited:
        prepareHoverCursorRelease(in: window)
        return event
      default:
        return event
      }
    }

    func beginReadiness(
      at locationInWindow: CGPoint,
      in window: NSWindow
    ) -> MenuPanelResizeBeginReadiness {
      guard isLiveResizeEligible(in: window) else { return .blocked }
      if queuedRevision != nil, alignedFrame != window.frame { return .reconciling }
      guard let attachmentID,
        controller.isPresentationOwner(attachmentID),
        let statusButton = geometryStore?.resolveStatusButton(),
        let screen = window.screen,
        statusButton.sourceIdentity == alignedStatusButtonSource,
        statusButton.screenFrame == alignedStatusButtonFrame,
        screen.visibleFrame == alignedVisibleFrame,
        window.frame == alignedFrame,
        let fixedSide = MenuPanelResizeGeometry.anchoredSide(
          panelFrame: window.frame,
          statusLabelFrame: statusButton.screenFrame
        ),
        fixedSide == alignedFixedSide,
        let handle = usableHandle(at: locationInWindow, in: window, fixedSide: fixedSide)
      else { return .blocked }
      let contentRect = window.contentRect(forFrameRect: window.frame)
      let insets = MenuPanelFrameInsets(
        top: window.frame.maxY - contentRect.maxY,
        left: contentRect.minX - window.frame.minX,
        bottom: contentRect.minY - window.frame.minY,
        right: window.frame.maxX - contentRect.maxX
      )
      let snapshot = MenuPanelResizeSnapshot(
        initialPointer: window.convertPoint(toScreen: locationInWindow),
        initialFrame: window.frame,
        initialContentSize: contentRect.size,
        frameInsets: insets,
        visibleFrame: screen.visibleFrame,
        statusLabelFrame: statusButton.screenFrame,
        fixedSide: fixedSide
      )
      return .ready(
        snapshot: snapshot,
        handle: handle,
        ownerID: attachmentID,
        statusButtonSource: statusButton.sourceIdentity
      )
    }

    private func begin(
      pointer: CGPoint,
      in window: NSWindow
    ) -> Bool {
      let readiness = beginReadiness(
        at: window.convertPoint(fromScreen: pointer),
        in: window
      )
      guard case let .ready(initialSnapshot, handle, ownerID, statusButtonSource) = readiness
      else { return false }
      var snapshot = initialSnapshot
      snapshot.initialPointer = pointer
      guard controller.begin(snapshot: snapshot, handle: handle, ownerID: ownerID) else {
        return false
      }
      invalidateQueuedWork()
      activeStatusButtonSource = statusButtonSource
      setCursor(cursor(for: handle, fixedSide: snapshot.fixedSide))
      invalidateResizeCursorRegions()
      return true
    }

    private func isCurrentInteraction(
      _ identity: MenuPanelResizeInteractionIdentity,
      in window: NSWindow
    ) -> Bool {
      attachmentID == identity.ownerID && installedWindow === window && self.window === window
        && controller.interactionIdentity(ownerID: identity.ownerID) == identity
    }

    private func update(pointer: CGPoint, in window: NSWindow) {
      guard let attachmentID,
        let interaction = controller.interactionIdentity(ownerID: attachmentID)
      else { return }
      guard let statusLabelFrame = activeStatusButtonFrame(),
        let screen = window.screen,
        controller.update(
          pointer: pointer,
          statusLabelFrame: statusLabelFrame,
          visibleFrame: screen.visibleFrame,
          ownerID: attachmentID,
          canonicalize: {
            self.applyNativeProposal(
              $0,
              in: window,
              on: screen,
              statusLabelFrame: statusLabelFrame,
              displayImmediately: false
            )
          }
        ) != nil
      else {
        cancelAndRestore(in: window, expectedInteraction: interaction)
        return
      }
      guard isCurrentInteraction(interaction.successor, in: window) else { return }
      if let handle = controller.currentHandle,
        let fixedSide = controller.currentFixedSide
      {
        setCursor(cursor(for: handle, fixedSide: fixedSide))
      }
      refreshResizeLayout()
    }

    private func finish(pointer: CGPoint, in window: NSWindow) {
      guard let attachmentID,
        let interaction = controller.interactionIdentity(ownerID: attachmentID)
      else { return }
      let endingStatusButton = geometryStore?.resolveStatusButton()
      guard endingStatusButton?.sourceIdentity == activeStatusButtonSource,
        let statusLabelFrame = endingStatusButton?.screenFrame,
        let screen = window.screen,
        controller.update(
          pointer: pointer,
          statusLabelFrame: statusLabelFrame,
          visibleFrame: screen.visibleFrame,
          ownerID: attachmentID,
          canonicalize: {
            self.applyNativeProposal(
              $0,
              in: window,
              on: screen,
              statusLabelFrame: statusLabelFrame
            )
          }
        ) != nil
      else {
        cancelAndRestore(in: window, expectedInteraction: interaction)
        return
      }
      let updatedInteraction = interaction.successor
      guard isCurrentInteraction(updatedInteraction, in: window) else { return }
      guard let final = controller.finish(
        statusLabelFrame: statusLabelFrame,
        visibleFrame: screen.visibleFrame,
        currentFrame: window.frame,
        ownerID: attachmentID,
        canonicalize: {
          self.applyNativeProposal(
            $0,
            in: window,
            on: screen,
            statusLabelFrame: statusLabelFrame
          )
        }
      ) else {
        cancelAndRestore(in: window, expectedInteraction: updatedInteraction)
        return
      }
      let completedInteraction = updatedInteraction.successor
      guard isCurrentInteraction(completedInteraction, in: window) else { return }
      let adoptedEffectiveSize = controller.setPresentationContentSize(
        final.contentSize,
        ownerID: attachmentID
      )
      guard isCurrentInteraction(completedInteraction, in: window),
        window.isVisible, isLiveResizeEligible(in: window),
        activeStatusButtonFrame() == statusLabelFrame,
        window.frame == final.frame,
        window.contentRect(forFrameRect: window.frame).size == final.contentSize,
        adoptedEffectiveSize,
        controller.presentationContentSize(ownerID: attachmentID) == final.contentSize,
        isCurrentInteraction(completedInteraction, in: window)
      else {
        cancelAndRestore(
          in: window,
          expectedInteraction: completedInteraction,
          completion: true
        )
        return
      }
      geometryStore?.rememberCompletedSide(final.fixedSide)
      activeStatusButtonSource = nil
      alignedStatusButtonSource = endingStatusButton?.sourceIdentity
      alignedStatusButtonFrame = statusLabelFrame
      alignedVisibleFrame = screen.visibleFrame
      alignedFixedSide = final.fixedSide
      alignedFrame = final.frame
      onCommit(final.contentSize)
      refreshResizeLayout()
      let interactionAfterCommit = isCurrentInteraction(completedInteraction, in: window)
      let clearedCompletion =
        interactionAfterCommit
        && controller.clearCompletion(preferredSize: preferredSize, ownerID: attachmentID)
      let interactionAfterClear =
        clearedCompletion && isCurrentInteraction(completedInteraction.successor, in: window)
      guard interactionAfterCommit, clearedCompletion, interactionAfterClear else { return }
      invalidateQueuedWork()
      scheduleReconcile()
      updateCursorAfterFinish(pointer: pointer, in: window)
      scheduleCursorRefresh()
      invalidateResizeCursorRegions()
    }

    private func updateCursorAfterFinish(pointer: CGPoint, in window: NSWindow) {
      let locationInWindow = window.convertPoint(fromScreen: pointer)
      let insideHost = bounds.contains(convert(locationInWindow, from: nil))
      let insideWindow = window.frame.contains(pointer)
      let laggingStrip = !insideHost && insideWindow
      if laggingStrip, !contentObstructsResize(at: locationInWindow, in: window) {
        return
      }
      updateCursor(at: locationInWindow, in: window)
    }

    private func cancelAndRestore(
      in window: NSWindow,
      publication: MenuPanelResizePublicationTiming = .immediate,
      expectedInteraction: MenuPanelResizeInteractionIdentity? = nil,
      completion: Bool = false
    ) {
      guard let attachmentID,
        let interaction = expectedInteraction ?? controller.interactionIdentity(ownerID: attachmentID),
        isCurrentInteraction(interaction, in: window)
      else { return }
      let snapshot = completion
        ? controller.cancelCompletion(ownerID: interaction.ownerID)
        : controller.cancelSnapshot(ownerID: interaction.ownerID, publication: publication)
      let rollbackInteraction = snapshot == nil ? interaction : interaction.successor
      guard isCurrentInteraction(rollbackInteraction, in: window) else { return }
      if let snapshot {
        restore(
          snapshot: snapshot,
          in: window,
          ownerID: interaction.ownerID,
          publication: publication,
          expectedInteraction: rollbackInteraction
        )
      }
      guard isCurrentInteraction(rollbackInteraction, in: window) else { return }
      activeStatusButtonSource = nil
      resetCursor()
      invalidateResizeCursorRegions()
    }

    private func isLiveResizeEligible(in window: NSWindow) -> Bool {
      canResize && !pendingExternalPreference && window.attachedSheet == nil
        && window.childWindows?.contains(where: \.isVisible) != true
    }

    @objc private func windowWillClose() {
      invalidateResizeCursorRegions()
      guard ownsPresentation else { return }
      isPresented = false
      presentationTop = nil
      invalidateQueuedWork()
      if let installedWindow {
        cancelAndRestore(in: installedWindow, publication: .deferred)
      }
      scheduleReconcile()
    }

    @objc private func windowResignedKey() {
      invalidateResizeCursorRegions()
      guard ownsPresentation else { return }
      isPresented = false
      presentationTop = nil
      invalidateQueuedWork()
      let window = installedWindow
      if ownsTracking {
        // A hidden window is a transient hide; the deferred visibility
        // reconcile cancels the drag only if the window stays hidden.
        if let window, window.isVisible {
          cancelAndRestore(in: window, publication: .deferred)
        }
      } else if let window {
        cancelAndRestore(in: window, publication: .deferred)
      }
      scheduleReconcile()
    }

    @objc private func windowPresented() {
      guard ownsPresentation else { return }
      isPresented = true
      presentationTop = nil
      invalidateQueuedWork()
      reconcileNativePresentation()
    }

    @objc private func windowGeometryChanged() {
      guard ownsPresentation, !isApplyingFrame else { return }
      invalidateQueuedWork()
      reconcileNativePresentation()
    }

    @discardableResult
    private func updateCursor(for event: NSEvent, in window: NSWindow) -> Bool {
      updateCursor(at: event.locationInWindow, in: window)
    }

    private func updateHoverCursor(from event: NSEvent) {
      guard let window = installedWindow, event.window === window,
        let attachmentID, controller.isPresentationOwner(attachmentID), window.isVisible
      else { return }
      if controller.isOwned(by: attachmentID) {
        updateCursor(at: event.locationInWindow, in: window)
        return
      }
      guard let resolved = hoverCursor(at: event.locationInWindow, in: window) else {
        resetCursor(in: window)
        return
      }
      setCursor(resolved)
      scheduleCursorRefresh()
    }

    private func prepareHoverCursorRelease(in window: NSWindow) {
      guard let attachmentID, installedWindow === window, self.window === window,
        controller.isPresentationOwner(attachmentID)
      else { return }
      guard window.isVisible else {
        resetCursor()
        return
      }
      let liveLocation = window.mouseLocationOutsideOfEventStream
      let livePointer = window.convertPoint(toScreen: liveLocation)
      guard window.frame.contains(livePointer) else {
        if controller.isOwned(by: attachmentID) {
          updateCursor(at: liveLocation, in: window)
          return
        }
        resetCursor(in: window)
        return
      }
      scheduleCursorRefresh()
    }

    private func resolvedLayout() -> MenuPanelResizeLayout? {
      guard let fixedSide = controller.currentFixedSide ?? alignedFixedSide else { return nil }
      return MenuPanelResizeGeometry.layout(in: bounds, fixedSide: fixedSide)
    }

    private func refreshResizeLayout() {
      guard isInstalled, ownsPresentation, isPresented,
        let window = installedWindow, self.window === window,
        let attachmentID, controller.isPresentationOwner(attachmentID)
      else {
        invalidateResizeCursorRegions()
        return
      }
      publishResizeLayout(ownerID: attachmentID)
      invalidateResizeCursorRegions()
      if !isLiveResizeEligible(in: window), ownsTracking {
        cancelAndRestore(in: window)
      }
    }

    private func publishResizeLayout(ownerID: UUID) {
      guard controller.setPresentationBodyPolicy(
        resolvedBodyPolicy(),
        ownerID: ownerID,
        publication: .deferred
      ) else { return }
      let installation = installationRevision
      guard queuedLayoutPublication != installation else { return }
      queuedLayoutPublication = installation
      DispatchQueue.main.async { [weak self] in
        guard let self, self.installationRevision == installation else { return }
        self.queuedLayoutPublication = nil
        guard let attachmentID = self.attachmentID,
          self.controller.isPresentationOwner(attachmentID)
        else {
          _ = self.controller.publishPresentationLayout()
          return
        }
        _ = self.controller.publishPresentationLayout(ownerID: attachmentID)
      }
    }

    private func resolvedBodyPolicy() -> MenuPanelResizeBodyPolicy {
      guard let layout = resolvedLayout() else { return .unready }
      return .inset(layout)
    }

    func invalidateResizeCursorRegions() {
      cachedHoverCursorRegistrations = nil
      cursorAreaRevision &+= 1
      requestCursorAreaRefresh()
    }

    private func scheduleCursorRefresh() {
      let installation = installationRevision
      guard queuedCursorRefreshInstallation != installation else { return }
      queuedCursorRefreshInstallation = installation
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.applyQueuedCursorRefresh(installation: installation)
      }
    }

    private func applyQueuedCursorRefresh(installation: Int) {
      guard queuedCursorRefreshInstallation == installation else {
        return
      }
      queuedCursorRefreshInstallation = nil
      guard installationRevision == installation else {
        return
      }
      guard NSApplication.shared.isActive else {
        return
      }
      guard let window = installedWindow, self.window === window, window.isVisible else {
        return
      }
      guard let attachmentID,
        controller.isPresentationOwner(attachmentID),
        !controller.isOwned(by: attachmentID)
      else {
        return
      }
      let location = window.mouseLocationOutsideOfEventStream
      let pointer = window.convertPoint(toScreen: location)
      let topmostWindowNumber = NSWindow.windowNumber(
        at: pointer,
        belowWindowWithWindowNumber: 0
      )
      guard topmostWindowNumber == window.windowNumber else {
        return
      }
      guard bounds.contains(convert(location, from: nil)) else {
        return
      }
      guard let resolved = hoverCursor(at: location, in: window) else {
        resetCursor(in: window)
        return
      }
      setCursor(resolved)
    }

    @discardableResult
    private func updateCursor(at locationInWindow: CGPoint, in window: NSWindow) -> Bool {
      if let attachmentID, controller.isOwned(by: attachmentID),
        let handle = controller.currentHandle,
        let fixedSide = controller.currentFixedSide
      {
        setCursor(cursor(for: handle, fixedSide: fixedSide))
        return true
      }
      guard let resolved = hoverCursor(at: locationInWindow, in: window) else {
        resetCursor(in: window)
        return false
      }
      setCursor(resolved)
      return true
    }

    private func hoverCursor(at locationInWindow: CGPoint, in window: NSWindow) -> NSCursor? {
      guard isLiveResizeEligible(in: window),
        let statusLabelFrame = geometryStore?.cachedStatusButton?.screenFrame,
        let fixedSide = MenuPanelResizeGeometry.anchoredSide(
          panelFrame: window.frame,
          statusLabelFrame: statusLabelFrame
        ),
        let handle = usableHandle(at: locationInWindow, in: window, fixedSide: fixedSide)
      else { return nil }
      return cursor(for: handle, fixedSide: fixedSide)
    }

    func usableHandle(
      at locationInWindow: CGPoint,
      in window: NSWindow,
      fixedSide: MenuPanelFixedSide
    ) -> MenuPanelResizeHandle? {
      guard let handle = MenuPanelResizeGeometry.handle(
        at: convert(locationInWindow, from: nil),
        in: bounds,
        fixedSide: fixedSide
      ) else { return nil }
      guard !contentObstructsResize(at: locationInWindow, in: window) else { return nil }
      return handle
    }

    func routesCursorToNativeOwner(
      at locationInWindow: CGPoint,
      in window: NSWindow
    ) -> Bool {
      guard !ownsTracking, installedWindow === window, self.window === window else { return false }
      let location = convert(locationInWindow, from: nil)
      return cursorRegistrations().contains { $0.rect.contains(location) }
    }

    private func contentObstructsResize(
      at locationInWindow: CGPoint,
      in window: NSWindow
    ) -> Bool {
      guard let contentView = window.contentView else { return false }
      isProbingContent = true
      defer { isProbingContent = false }
      let contentPoint =
        contentView.superview.map { $0.convert(locationInWindow, from: nil) }
        ?? contentView.convert(locationInWindow, from: nil)
      var hit = contentView.hitTest(contentPoint)
      while let view = hit {
        if let scroller = view as? NSScroller {
          hit = scroller.superview
          continue
        }
        if let control = view as? NSControl, control.isEnabled { return true }
        if let textView = view as? NSTextView,
          let manager = textView.layoutManager, let container = textView.textContainer
        {
          let point = textView.convert(locationInWindow, from: nil)
          let textPoint = CGPoint(
            x: point.x - textView.textContainerOrigin.x,
            y: point.y - textView.textContainerOrigin.y
          )
          if textPoint.x >= 0, point.x < textView.bounds.maxX - textView.textContainerOrigin.x {
            let glyph = manager.glyphIndex(for: textPoint, in: container)
            if glyph < manager.numberOfGlyphs,
              manager.boundingRect(
                forGlyphRange: NSRange(location: glyph, length: 1), in: container
              ).contains(textPoint)
            { return true }
          }
        }
        hit = view.superview
      }
      return false
    }

    private func activeStatusButtonFrame() -> CGRect? {
      guard let statusButton = geometryStore?.cachedStatusButton,
        statusButton.sourceIdentity == activeStatusButtonSource
      else { return nil }
      return statusButton.screenFrame
    }

    private func invalidateQueuedWork() {
      stateRevision &+= 1
      queuedRevision = nil
    }

    private func reconcileNativePresentation() {
      guard !isApplyingFrame else { return }
      reconcilePresentation(publication: .deferred, preparesHiddenWindow: true)
      scheduleReconcile()
    }

    private func scheduleReconcile() {
      let revision = stateRevision
      guard queuedRevision != revision else { return }
      queuedRevision = revision
      let installation = installationRevision
      DispatchQueue.main.async { [weak self] in
        guard let self,
          self.installationRevision == installation,
          self.queuedRevision == revision
        else { return }
        self.queuedRevision = nil
        self.reconcilePresentation(publication: .deferred, preparesHiddenWindow: false)
        if let attachmentID = self.attachmentID {
          _ = self.controller.publishPresentationContentSize(ownerID: attachmentID)
        } else {
          _ = self.controller.publishPresentationContentSize()
        }
      }
    }

    private func reconcilePresentation(
      publication: MenuPanelResizePublicationTiming,
      preparesHiddenWindow: Bool
    ) {
      defer {
        if let attachmentID, controller.isPresentationOwner(attachmentID) {
          publishResizeLayout(ownerID: attachmentID)
        }
        invalidateResizeCursorRegions()
      }
      guard let window = installedWindow, let attachmentID else {
        if pendingExternalPreference, controller.isUnownedTracking {
          controller.cancelSnapshot(publication: publication)
        }
        pendingExternalPreference = false
        return
      }
      guard controller.isPresentationOwner(attachmentID) else { return }
      if !isLiveResizeEligible(in: window) || !window.isVisible {
        if controller.isOwned(by: attachmentID) {
          cancelAndRestore(in: window, publication: publication)
        }
        if pendingExternalPreference {
          _ = controller.setPresentationContentSize(
            nil,
            ownerID: attachmentID,
            publication: publication
          )
          pendingExternalPreference = false
        }
      }
      let ownsTracking = controller.isOwned(by: attachmentID)
      guard self.window === window, superview != nil,
        !isHiddenOrHasHiddenAncestor, !bounds.isEmpty, hasPreferredSize
      else {
        if ownsTracking && !preparesHiddenWindow {
          cancelAndRestore(in: window, publication: publication)
        }
        return
      }
      let isVisible = isPresented && window.isVisible
      if !isVisible && !preparesHiddenWindow {
        if ownsTracking {
          cancelAndRestore(in: window, publication: publication)
        }
        return
      }

      if ownsTracking {
        let statusButton = geometryStore?.cachedStatusButton
        guard let screen = window.screen,
          statusButton?.sourceIdentity == activeStatusButtonSource,
          controller.matchesGeometry(
            statusLabelFrame: statusButton?.screenFrame,
            visibleFrame: screen.visibleFrame
          )
        else {
          if isVisible {
            cancelAndRestore(in: window, publication: publication)
          }
          return
        }
        if let proposal = controller.currentProposal {
          applyFrame(proposal.frame, to: window)
        }
        return
      }
      guard !controller.isTracking else { return }
      guard let screen = window.screen,
        let statusButton = geometryStore?.cachedStatusButton ?? geometryStore?.resolveStatusButton()
      else {
        applyOwnedContainedFallback(
          frame: window.frame,
          to: window,
          ownerID: attachmentID,
          publication: publication
        )
        return
      }

      guard let insets = frameInsets(for: window) else {
        applyOwnedContainedFallback(
          frame: window.frame,
          to: window,
          ownerID: attachmentID,
          publication: publication
        )
        return
      }
      let inheritedFrame = window.frame
      if !isVisible || presentationTop == nil { presentationTop = inheritedFrame.maxY }
      var topFrame = inheritedFrame
      topFrame.origin.y = (presentationTop ?? inheritedFrame.maxY) - inheritedFrame.height
      let requestedSize = alignedFrame == nil
        ? preferredSize
        : controller.presentationContentSize(ownerID: attachmentID) ?? preferredSize
      guard let placement = MenuPanelResizeGeometry.presentation(
        contentSize: requestedSize,
        inheritedFrame: topFrame,
        frameInsets: insets,
        visibleFrame: screen.visibleFrame,
        statusLabelFrame: statusButton.screenFrame,
        preferredSide: geometryStore?.rememberedFixedSide
      ) else {
        applyOwnedContainedFallback(
          frame: window.frame,
          to: window,
          ownerID: attachmentID,
          publication: publication
        )
        return
      }
      applyFrame(placement.frame, to: window)
      _ = controller.setPresentationContentSize(
        placement.contentSize == preferredSize ? nil : placement.contentSize,
        ownerID: attachmentID,
        publication: publication
      )
      alignedStatusButtonSource = statusButton.sourceIdentity
      alignedStatusButtonFrame = statusButton.screenFrame
      alignedVisibleFrame = screen.visibleFrame
      alignedFixedSide = placement.fixedSide
      alignedFrame = placement.frame
      updateTrackingAreas()
      invalidateResizeCursorRegions()
    }

    private func restore(
      snapshot: MenuPanelResizeSnapshot,
      in window: NSWindow,
      ownerID: UUID,
      publication: MenuPanelResizePublicationTiming = .immediate,
      expectedInteraction: MenuPanelResizeInteractionIdentity? = nil
    ) {
      guard expectedInteraction.map({ isCurrentInteraction($0, in: window) }) ?? true else { return }
      if let statusButton = geometryStore?.resolveStatusButton(),
        let screen = window.screen,
        let insets = frameInsets(for: window),
        let placement = MenuPanelResizeGeometry.presentation(
          contentSize: snapshot.initialContentSize,
          inheritedFrame: snapshot.initialFrame,
          frameInsets: insets,
          visibleFrame: screen.visibleFrame,
          statusLabelFrame: statusButton.screenFrame,
          preferredSide: snapshot.fixedSide
      )
      {
        guard expectedInteraction.map({ isCurrentInteraction($0, in: window) }) ?? true else { return }
        applyFrame(placement.frame, to: window)
      } else {
        applyOwnedContainedFallback(
          frame: snapshot.initialFrame,
          to: window,
          ownerID: ownerID,
          publication: publication,
          expectedInteraction: expectedInteraction
        )
      }
    }

    private static func restore(
      snapshot: MenuPanelResizeSnapshot,
      in window: NSWindow,
      geometryStore: MenuPanelGeometryStore?,
      fallbackVisibleFrameProvider: FallbackVisibleFrameProvider
    ) {
      let contentRect = window.contentRect(forFrameRect: window.frame)
      let insets = MenuPanelFrameInsets(
        top: window.frame.maxY - contentRect.maxY,
        left: contentRect.minX - window.frame.minX,
        bottom: contentRect.minY - window.frame.minY,
        right: window.frame.maxX - contentRect.maxX
      )
      if let statusButton = geometryStore?.resolveStatusButton(),
        let screen = window.screen,
        let placement = MenuPanelResizeGeometry.presentation(
          contentSize: snapshot.initialContentSize,
          inheritedFrame: snapshot.initialFrame,
          frameInsets: insets,
          visibleFrame: screen.visibleFrame,
          statusLabelFrame: statusButton.screenFrame,
          preferredSide: snapshot.fixedSide
        )
      {
        if window.frame != placement.frame {
          window.setFrame(placement.frame, display: true, animate: false)
        }
      } else if let visibleFrame = fallbackVisibleFrameProvider(window),
        let containedFrame = MenuPanelResizeGeometry.containedFrame(
          frame: snapshot.initialFrame,
          visibleFrame: visibleFrame
        )
      {
        if window.frame != containedFrame {
          window.setFrame(containedFrame, display: true, animate: false)
        }
      }
    }

    @discardableResult
    private func applyOwnedContainedFallback(
      frame: CGRect,
      to window: NSWindow,
      ownerID: UUID,
      publication: MenuPanelResizePublicationTiming,
      expectedInteraction: MenuPanelResizeInteractionIdentity? = nil
    ) -> Bool {
      guard controller.isPresentationOwner(ownerID),
        expectedInteraction.map({ isCurrentInteraction($0, in: window) }) ?? true,
        let visibleFrame = fallbackVisibleFrameProvider(window),
        let containedFrame = MenuPanelResizeGeometry.containedFrame(
          frame: frame,
          visibleFrame: visibleFrame
        )
      else { return false }

      let contentSize = window.contentRect(forFrameRect: containedFrame).size
      guard contentSize.width.isFinite, contentSize.height.isFinite,
        contentSize.width > 0, contentSize.height > 0,
        expectedInteraction.map({ isCurrentInteraction($0, in: window) }) ?? true,
        applyFrame(containedFrame, to: window),
        controller.isPresentationOwner(ownerID),
        expectedInteraction.map({ isCurrentInteraction($0, in: window) }) ?? true
      else { return false }
      clearAlignment()
      presentationTop = containedFrame.maxY
      return controller.setPresentationContentSize(
        contentSize == preferredSize ? nil : contentSize,
        ownerID: ownerID,
        publication: publication
      )
    }

    private static func publicFallbackVisibleFrame(for window: NSWindow) -> CGRect? {
      let candidates = [window.screen, NSScreen.main] + NSScreen.screens.map(Optional.some)
      for screen in candidates.compactMap({ $0 }) {
        let visibleFrame = screen.visibleFrame
        if MenuPanelResizeGeometry.containedFrame(
          frame: visibleFrame,
          visibleFrame: visibleFrame
        ) != nil {
          return visibleFrame
        }
      }
      return nil
    }

    private func frameInsets(for window: NSWindow) -> MenuPanelFrameInsets? {
      let frame = window.frame
      guard !frame.isNull, !frame.isInfinite, !frame.isEmpty else { return nil }
      let contentRect = window.contentRect(forFrameRect: frame)
      let insets = MenuPanelFrameInsets(
        top: frame.maxY - contentRect.maxY,
        left: contentRect.minX - frame.minX,
        bottom: contentRect.minY - frame.minY,
        right: frame.maxX - contentRect.maxX
      )
      guard [insets.top, insets.left, insets.bottom, insets.right].allSatisfy({
        $0.isFinite && $0 >= 0
      }) else { return nil }
      return insets
    }

    private func applyNativeProposal(
      _ proposal: MenuPanelResizeProposal,
      in window: NSWindow,
      on screen: NSScreen,
      statusLabelFrame: CGRect,
      displayImmediately: Bool = true
    ) -> MenuPanelResizeProposal? {
      guard ownsTracking, let handle = controller.currentHandle else { return nil }
      let visibleFrame = screen.visibleFrame
      let frame = screen.backingAlignedRect(proposal.frame, options: .alignAllEdgesOutward)
      let contentSize = window.contentRect(forFrameRect: frame).size
      let isLegalPreference = contentSize.width >= MenuPanelResizeGeometry.minimumContentSize.width
        && contentSize.height >= MenuPanelResizeGeometry.minimumContentSize.height
      let hasFixedEdge = switch proposal.fixedSide {
      case .left: frame.minX == statusLabelFrame.minX
      case .right: frame.maxX == statusLabelFrame.maxX
      }
      guard frame.maxY == proposal.frame.maxY,
        hasFixedEdge,
        handle.changesWidth || frame.width == proposal.frame.width,
        handle.changesHeight || frame.height == proposal.frame.height,
        MenuPanelResizeGeometry.containedFrame(
          frame: frame,
          visibleFrame: visibleFrame
        ) == frame,
        contentSize.width.isFinite, contentSize.height.isFinite,
        contentSize.width > 0, contentSize.height > 0,
        !proposal.isLegalPreference || isLegalPreference
      else { return nil }
      applyFrame(frame, to: window, displayImmediately: displayImmediately)
      let nativeFrame = window.frame
      let nativeContentSize = window.contentRect(forFrameRect: nativeFrame).size
      let nativeHasFixedEdge = switch proposal.fixedSide {
      case .left: nativeFrame.minX == statusLabelFrame.minX
      case .right: nativeFrame.maxX == statusLabelFrame.maxX
      }
      let nativeIsLegalPreference =
        nativeContentSize.width >= MenuPanelResizeGeometry.minimumContentSize.width
        && nativeContentSize.height >= MenuPanelResizeGeometry.minimumContentSize.height
      guard ownsTracking, installedWindow === window, self.window === window,
        window.isVisible, isLiveResizeEligible(in: window),
        activeStatusButtonFrame() == statusLabelFrame,
        window.screen === screen, screen.visibleFrame == visibleFrame,
        nativeFrame == frame || nativeFrame == frame.integral,
        nativeFrame.maxY == frame.maxY, nativeHasFixedEdge,
        handle.changesWidth || nativeFrame.width == proposal.frame.width,
        handle.changesHeight || nativeFrame.height == proposal.frame.height,
        MenuPanelResizeGeometry.containedFrame(
          frame: nativeFrame,
          visibleFrame: visibleFrame
        ) == nativeFrame,
        nativeContentSize.width.isFinite, nativeContentSize.height.isFinite,
        nativeContentSize.width > 0, nativeContentSize.height > 0,
        !proposal.isLegalPreference || nativeIsLegalPreference
      else { return nil }
      return MenuPanelResizeProposal(
        contentSize: nativeContentSize,
        frame: nativeFrame,
        isLegalPreference: nativeIsLegalPreference,
        fixedSide: proposal.fixedSide
      )
    }

    @discardableResult
    private func applyFrame(
      _ frame: CGRect,
      to window: NSWindow,
      displayImmediately: Bool = true
    ) -> Bool {
      guard window.frame != frame else { return true }
      isApplyingFrame = true
      window.setFrame(frame, display: displayImmediately, animate: false)
      isApplyingFrame = false
      refreshResizeLayout()
      return window.frame == frame
    }

    private func clearAlignment() {
      alignedStatusButtonSource = nil
      alignedStatusButtonFrame = nil
      alignedVisibleFrame = nil
      alignedFixedSide = nil
      alignedFrame = nil
    }

    func cursor(
      for handle: MenuPanelResizeHandle,
      fixedSide: MenuPanelFixedSide
    ) -> NSCursor {
      switch handle {
      case .farSide:
        return .resizeLeftRight
      case .nearBottomCorner:
        return .resizeUpDown
      case .farBottomCorner:
        return fixedSide == .left ? leftFixedCornerCursor : rightFixedCornerCursor
      }
    }

    private func diagonalCursor(rotatedClockwise: Bool) -> NSCursor {
      let source = NSCursor.resizeLeftRight.image
      let sourceSize = source.size
      guard sourceSize.width > 0, sourceSize.height > 0 else { return .resizeLeftRight }
      let scale: CGFloat = 2
      let side = (hypot(sourceSize.width, sourceSize.height) + 4).rounded(.up)
      let pixels = Int(side * scale)
      guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      ), let context = NSGraphicsContext(bitmapImageRep: representation)
      else { return .resizeLeftRight }
      representation.size = NSSize(width: side, height: side)
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = context
      context.cgContext.scaleBy(x: scale, y: scale)
      context.cgContext.translateBy(x: side / 2, y: side / 2)
      context.cgContext.rotate(by: (rotatedClockwise ? -45 : 45) * .pi / 180)
      context.cgContext.translateBy(x: -sourceSize.width / 2, y: -sourceSize.height / 2)
      source.draw(
        in: NSRect(origin: .zero, size: sourceSize),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
      )
      context.flushGraphics()
      NSGraphicsContext.restoreGraphicsState()
      let image = NSImage(size: NSSize(width: side, height: side))
      image.addRepresentation(representation)
      image.isTemplate = false
      return NSCursor(image: image, hotSpot: NSPoint(x: side / 2, y: side / 2))
    }

    private func setCursor(_ cursor: NSCursor) {
      self.cursor = cursor
      cursor.set()
    }

    private func resetCursor(in window: NSWindow) {
      guard cursor != nil else { return }
      resetCursor()
      if let contentView = window.contentView {
        window.invalidateCursorRects(for: contentView)
      }
    }

    private func resetCursor() {
      guard let ownedCursor = cursor else { return }
      cursor = nil
      guard NSCursor.current === ownedCursor else { return }
      NSCursor.arrow.set()
    }

    private func removeCursorTracking() {
      guard !cursorTrackingAreas.isEmpty else { return }
      for area in cursorTrackingAreas {
        removeTrackingArea(area)
      }
      cursorTrackingAreas = []
      installedCursorAreaSpecs = []
    }
  }
#endif
