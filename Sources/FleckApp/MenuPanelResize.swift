#if os(macOS)
  import AppKit
  import Combine
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
      let isBottomCorner = point.y <= bounds.minY + cornerExtent
      let isNearCorner: Bool
      let isFarCorner: Bool
      let isFarEdge: Bool
      switch fixedSide {
      case .left:
        isNearCorner = point.x <= bounds.minX + cornerExtent
        isFarCorner = point.x >= bounds.maxX - cornerExtent
        isFarEdge = point.x >= bounds.maxX - edgeThickness
      case .right:
        isNearCorner = point.x >= bounds.maxX - cornerExtent
        isFarCorner = point.x <= bounds.minX + cornerExtent
        isFarEdge = point.x <= bounds.minX + edgeThickness
      }
      if isBottomCorner && isFarCorner { return .farBottomCorner }
      if isBottomCorner && isNearCorner { return .nearBottomCorner }
      if isFarEdge && point.y > bounds.minY + cornerExtent { return .farSide }
      return nil
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
          ? max(0, snapshot.initialFrame.maxX - snapshot.initialPointer.x)
          : max(0, snapshot.initialPointer.x - snapshot.initialFrame.minX)
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

  enum MenuPanelResizeObservationInput: UInt8 {
    case mouse = 1
    case escape = 2
  }

  enum MenuPanelResizeObservationPhase: UInt8 {
    case fixturePreflight = 1
    case eventAdmission = 2
  }

  enum MenuPanelResizeObservationReadiness: UInt8 {
    case ready = 1
    case reconciling = 2
    case blocked = 3
  }

  enum MenuPanelResizeObservationGate: UInt8 {
    case owner = 1
    case window = 2
    case visibility = 3
  }

  enum MenuPanelResizeObservationOperation: UInt8 {
    case begin = 1
    case update = 2
    case finish = 3
    case cancel = 4
    case backing = 5
    case relinquish = 6
  }

  enum MenuPanelResizeObservationRejection: UInt8 {
    case none = 0
    case owner = 1
    case alreadyTracking = 2
    case incompleteGeometry = 3
    case proposal = 4
    case minimum = 5
    case missingState = 6
    case changedGeometry = 7
    case canonicalization = 8
    case changedFrame = 9
    case notTracking = 10
    case backingFrame = 11
    case backingAnchor = 12
    case backingContainment = 13
    case backingContent = 14
    case backingPreference = 15
    case deferredOwner = 16
    case emptyInitialFrame = 17
    case emptyVisibleFrame = 18
    case emptyStatusLabelFrame = 19
    case missingSnapshot = 20
    case missingHandle = 21
    case missingFixedSide = 22
    case changedStatusLabelFrame = 23
    case changedVisibleFrame = 24
    case missingProposal = 25
    case missingPointer = 26
    case backingContentWidthNonFinite = 27
    case backingContentHeightNonFinite = 28
    case backingContentWidthNonPositive = 29
    case backingContentHeightNonPositive = 30
    case liveResizeEligibility = 31
    case queuedRevision = 32
    case missingAttachment = 33
    case statusButtonUnavailable = 34
    case screenUnavailable = 35
    case statusButtonSource = 36
    case statusButtonFrame = 37
    case visibleFrame = 38
    case windowFrame = 39
    case fixedSideUnavailable = 40
    case fixedSideMismatch = 41
    case handleUnavailable = 42
  }

  enum MenuPanelResizeObservationOrigin: UInt8 {
    case directAPI = 1
    case mouseDown = 2
    case mouseDrag = 3
    case mouseUp = 4
    case escape = 5
    case eligibilityLoss = 6
    case rejectedFinalFrame = 7
    case windowClose = 8
    case windowKeyLoss = 9
    case visibilityReconcile = 10
    case geometryReconcile = 11
    case ownerReplacement = 12
    case ownerRelease = 13
    case deferredOwnerRelease = 14
  }

  struct MenuPanelResizeObservationTicket: Equatable {
    let sequence: UInt16
    let input: MenuPanelResizeObservationInput
    let inputNumber: Int
  }

  struct MenuPanelResizeObservationIdentity: Equatable {
    let host: ObjectIdentifier
    let window: ObjectIdentifier?
    let controller: ObjectIdentifier
    let attachmentID: UUID?
    let installationRevision: Int
  }

  struct MenuPanelResizeObservationGesture {
    let sequence: UInt16
  }

  struct MenuPanelResizeObservationPendingRelease: Equatable {
    let sequence: UInt16
    let identity: MenuPanelResizeObservationIdentity
    let gestureSequence: UInt16?
  }

  enum MenuPanelResizeObservationInvocation: Equatable {
    case claimReplacement
    case normalRelease
    case queuedPendingRelease(MenuPanelResizeObservationPendingRelease)

    var origin: MenuPanelResizeObservationOrigin {
      switch self {
      case .claimReplacement:
        .ownerReplacement
      case .normalRelease:
        .ownerRelease
      case .queuedPendingRelease:
        .deferredOwnerRelease
      }
    }

    var code: UInt8 {
      switch self {
      case .claimReplacement:
        1
      case .normalRelease:
        2
      case .queuedPendingRelease:
        3
      }
    }

    var pendingSequence: UInt16? {
      guard case let .queuedPendingRelease(token) = self else { return nil }
      return token.sequence
    }
  }

  enum MenuPanelResizeObservationRecord {
    case binding(
      host: ObjectIdentifier,
      window: ObjectIdentifier?,
      controller: ObjectIdentifier,
      attachmentID: UUID?,
      revision: Int,
      bindingTime: Bool
    )
    case attachment(
      host: ObjectIdentifier,
      window: ObjectIdentifier?,
      controller: ObjectIdentifier,
      attachmentID: UUID?,
      oldRevision: Int,
      newRevision: Int,
      installed: Bool
    )
    case ownerTransition(
      controller: ObjectIdentifier,
      previous: UUID?,
      current: UUID?
    )
    case gate(
      identity: MenuPanelResizeObservationIdentity,
      controllerOwnerID: UUID?,
      ticket: MenuPanelResizeObservationTicket?,
      gate: MenuPanelResizeObservationGate,
      passed: Bool
    )
    case outcome(
      identity: MenuPanelResizeObservationIdentity,
      controllerOwnerID: UUID?,
      ticket: MenuPanelResizeObservationTicket?,
      consumed: Bool
    )
    case readiness(
      identity: MenuPanelResizeObservationIdentity,
      controllerOwnerID: UUID?,
      ticket: MenuPanelResizeObservationTicket?,
      phase: MenuPanelResizeObservationPhase,
      result: MenuPanelResizeObservationReadiness,
      rejection: MenuPanelResizeObservationRejection
    )
    case decision(
      identity: MenuPanelResizeObservationIdentity?,
      controller: ObjectIdentifier,
      controllerOwnerID: UUID?,
      ticket: MenuPanelResizeObservationTicket?,
      operation: MenuPanelResizeObservationOperation,
      accepted: Bool,
      rejection: MenuPanelResizeObservationRejection
    )
    case tracking(
      identity: MenuPanelResizeObservationIdentity?,
      controller: ObjectIdentifier,
      controllerOwnerID: UUID?,
      ticket: MenuPanelResizeObservationTicket?,
      gesture: MenuPanelResizeObservationGesture,
      active: Bool,
      origin: MenuPanelResizeObservationOrigin,
      invocation: MenuPanelResizeObservationInvocation?
    )
  }

  @MainActor
  protocol MenuPanelResizeObservationSink: AnyObject {
    var isRecording: Bool { get }
    func markIncomplete()
    func issue(
      _ input: MenuPanelResizeObservationInput,
      inputNumber: Int,
      type: NSEvent.EventType,
      window: NSWindow
    ) -> MenuPanelResizeObservationTicket?
    func record(_ record: MenuPanelResizeObservationRecord)
    func eventCreated(
      _ ticket: MenuPanelResizeObservationTicket,
      type: NSEvent.EventType,
      event: ObjectIdentifier?,
      eventNumber: Int?
    )
    func dispatch(
      _ ticket: MenuPanelResizeObservationTicket,
      event: ObjectIdentifier,
      entering: Bool
    )
    func receive(
      event: ObjectIdentifier,
      host: ObjectIdentifier
    ) -> MenuPanelResizeObservationTicket?
    func beginTracking(
      identity: MenuPanelResizeObservationIdentity?,
      controller: ObjectIdentifier,
      controllerOwnerID: UUID?,
      ticket: MenuPanelResizeObservationTicket?,
      origin: MenuPanelResizeObservationOrigin
    ) -> MenuPanelResizeObservationGesture?
    func markPendingRelease(
      _ identity: MenuPanelResizeObservationIdentity
    ) -> MenuPanelResizeObservationPendingRelease?
    func finishPendingRelease(
      _ token: MenuPanelResizeObservationPendingRelease,
      completed: Bool
    )
    func scheduleReconcile(revision: Int, installationRevision: Int) -> UInt16?
    func finishReconcile(_ token: UInt16, completed: Bool)
  }

  @MainActor
  final class MenuPanelResizeController: ObservableObject {
    @Published private(set) var effectiveContentSize: CGSize?
    private var desiredEffectiveContentSize: CGSize?
    private(set) var completedPreferenceSize: CGSize?
    private(set) var isTracking = false
    private var snapshot: MenuPanelResizeSnapshot?
    private var handle: MenuPanelResizeHandle?
    private var proposal: MenuPanelResizeProposal?
    private var lastPointer: CGPoint?
    private var presentationOwnerID: UUID?
    private var relinquishPresentation: (@MainActor () -> Void)?
    private(set) var currentFixedSide: MenuPanelFixedSide?
    weak var observationSink: (any MenuPanelResizeObservationSink)?
    private var observationHostSinkFactory: (@MainActor () -> (any MenuPanelResizeObservationSink)?)?
    private weak var trackingObservationSink: (any MenuPanelResizeObservationSink)?
    private var observationGesture: MenuPanelResizeObservationGesture?
    private var trackingObservationIdentity: MenuPanelResizeObservationIdentity?
    private var trackingObservationControllerOwnerID: UUID?
    private var activeObservationInvocation: MenuPanelResizeObservationInvocation?

    func bindObservationSink(_ sink: (any MenuPanelResizeObservationSink)?) {
      observationSink = sink
      guard let sink else {
        observationHostSinkFactory = nil
        return
      }
      observationHostSinkFactory = { [weak sink] in sink }
    }

    func observationSinkForNewHost() -> (any MenuPanelResizeObservationSink)? {
      observationHostSinkFactory?()
    }

    fileprivate func recordDecision(
      _ operation: MenuPanelResizeObservationOperation,
      ticket: MenuPanelResizeObservationTicket?,
      accepted: Bool,
      rejection: MenuPanelResizeObservationRejection,
      fallbackSink: (any MenuPanelResizeObservationSink)? = nil,
      observationIdentity: MenuPanelResizeObservationIdentity? = nil,
      controllerOwnerID: UUID? = nil
    ) {
      guard let sink = fallbackSink ?? observationSink, sink.isRecording else { return }
      if ticket != nil && observationIdentity == nil {
        sink.markIncomplete()
        return
      }
      sink.record(
        .decision(
          identity: observationIdentity,
          controller: ObjectIdentifier(self),
          controllerOwnerID: controllerOwnerID,
          ticket: ticket,
          operation: operation,
          accepted: accepted,
          rejection: rejection
        )
      )
    }

    private func recordTrackingClear(
      ticket: MenuPanelResizeObservationTicket?,
      origin: MenuPanelResizeObservationOrigin,
      fallbackSink: (any MenuPanelResizeObservationSink)? = nil
    ) {
      guard let observationGesture,
        let sink = trackingObservationSink ?? fallbackSink ?? observationSink
      else { return }
      if sink.isRecording || fallbackSink === sink {
        if ticket != nil && trackingObservationIdentity == nil {
          sink.markIncomplete()
        } else {
          let invocation = activeObservationInvocation
          sink.record(
            .tracking(
              identity: trackingObservationIdentity,
              controller: ObjectIdentifier(self),
              controllerOwnerID: trackingObservationControllerOwnerID,
              ticket: ticket,
              gesture: observationGesture,
              active: false,
              origin: invocation?.origin ?? origin,
              invocation: invocation
            )
          )
        }
      }
      self.observationGesture = nil
      trackingObservationSink = nil
      trackingObservationIdentity = nil
      trackingObservationControllerOwnerID = nil
    }

    private func pushObservationInvocation(
      _ invocation: MenuPanelResizeObservationInvocation,
      fallbackSink: (any MenuPanelResizeObservationSink)? = nil,
      previous: inout MenuPanelResizeObservationInvocation?
    ) -> Bool {
      guard trackingObservationSink != nil || fallbackSink != nil else { return false }
      previous = activeObservationInvocation
      activeObservationInvocation = invocation
      return true
    }

    var initialFrame: CGRect? { snapshot?.initialFrame }
    var initialContentSize: CGSize? { snapshot?.initialContentSize }
    var currentProposal: MenuPanelResizeProposal? { proposal }
    var currentHandle: MenuPanelResizeHandle? { handle }

    @discardableResult
    func begin(
      snapshot: MenuPanelResizeSnapshot,
      handle: MenuPanelResizeHandle,
      ownerID: UUID? = nil,
      observationTicket: MenuPanelResizeObservationTicket? = nil,
      observationOrigin: MenuPanelResizeObservationOrigin = .directAPI,
      observationIdentity: MenuPanelResizeObservationIdentity? = nil
    ) -> Bool {
      let currentOwnerID = presentationOwnerID
      guard currentOwnerID == ownerID else {
        recordDecision(
          .begin,
          ticket: observationTicket,
          accepted: false,
          rejection: .owner,
          observationIdentity: observationIdentity,
          controllerOwnerID: currentOwnerID
        )
        return false
      }
      guard !isTracking else {
        recordDecision(
          .begin,
          ticket: observationTicket,
          accepted: false,
          rejection: .alreadyTracking,
          observationIdentity: observationIdentity,
          controllerOwnerID: currentOwnerID
        )
        return false
      }
      guard !snapshot.initialFrame.isEmpty else {
        recordDecision(
          .begin,
          ticket: observationTicket,
          accepted: false,
          rejection: .emptyInitialFrame,
          observationIdentity: observationIdentity,
          controllerOwnerID: currentOwnerID
        )
        return false
      }
      guard !snapshot.visibleFrame.isEmpty else {
        recordDecision(
          .begin,
          ticket: observationTicket,
          accepted: false,
          rejection: .emptyVisibleFrame,
          observationIdentity: observationIdentity,
          controllerOwnerID: currentOwnerID
        )
        return false
      }
      guard !snapshot.statusLabelFrame.isEmpty else {
        recordDecision(
          .begin,
          ticket: observationTicket,
          accepted: false,
          rejection: .emptyStatusLabelFrame,
          observationIdentity: observationIdentity,
          controllerOwnerID: currentOwnerID
        )
        return false
      }
      guard MenuPanelResizeGeometry.proposal(
        snapshot: snapshot,
        pointer: snapshot.initialPointer,
        handle: handle,
        currentSide: snapshot.fixedSide
      ) != nil else {
        recordDecision(
          .begin,
          ticket: observationTicket,
          accepted: false,
          rejection: .proposal,
          observationIdentity: observationIdentity,
          controllerOwnerID: currentOwnerID
        )
        return false
      }
      guard MenuPanelResizeGeometry.supportsStableMinimum(
        side: snapshot.fixedSide,
        frameInsets: snapshot.frameInsets,
        visibleFrame: snapshot.visibleFrame,
        statusLabelFrame: snapshot.statusLabelFrame
      ) else {
        recordDecision(
          .begin,
          ticket: observationTicket,
          accepted: false,
          rejection: .minimum,
          observationIdentity: observationIdentity,
          controllerOwnerID: currentOwnerID
        )
        return false
      }
      self.snapshot = snapshot
      self.handle = handle
      proposal = nil
      lastPointer = snapshot.initialPointer
      currentFixedSide = snapshot.fixedSide
      completedPreferenceSize = nil
      setDesiredContentSize(snapshot.initialContentSize, publication: .immediate)
      isTracking = true
      if let observationSink, observationSink.isRecording {
        trackingObservationSink = observationSink
        trackingObservationIdentity = observationIdentity
        trackingObservationControllerOwnerID = currentOwnerID
        self.observationGesture = observationSink.beginTracking(
          identity: observationIdentity,
          controller: ObjectIdentifier(self),
          controllerOwnerID: currentOwnerID,
          ticket: observationTicket,
          origin: observationOrigin
        )
      }
      recordDecision(
        .begin,
        ticket: observationTicket,
        accepted: true,
        rejection: .none,
        observationIdentity: observationIdentity,
        controllerOwnerID: currentOwnerID
      )
      return true
    }

    @discardableResult
    func update(
      pointer: CGPoint,
      statusLabelFrame: CGRect?,
      visibleFrame: CGRect?,
      ownerID: UUID? = nil,
      canonicalize: (MenuPanelResizeProposal) -> MenuPanelResizeProposal? = { $0 },
      observationTicket: MenuPanelResizeObservationTicket? = nil,
      observationIdentity: MenuPanelResizeObservationIdentity? = nil
    ) -> MenuPanelResizeProposal? {
      let currentOwnerID = presentationOwnerID
      guard currentOwnerID == ownerID else {
        recordDecision(
          .update,
          ticket: observationTicket,
          accepted: false,
          rejection: .owner,
          observationIdentity: observationIdentity,
          controllerOwnerID: currentOwnerID
        )
        return nil
      }
      guard let snapshot else {
        recordDecision(
          .update,
          ticket: observationTicket,
          accepted: false,
          rejection: .missingSnapshot,
          observationIdentity: observationIdentity,
          controllerOwnerID: currentOwnerID
        )
        return nil
      }
      guard let handle else {
        recordDecision(
          .update,
          ticket: observationTicket,
          accepted: false,
          rejection: .missingHandle,
          observationIdentity: observationIdentity,
          controllerOwnerID: currentOwnerID
        )
        return nil
      }
      guard let currentFixedSide else {
        recordDecision(
          .update,
          ticket: observationTicket,
          accepted: false,
          rejection: .missingFixedSide,
          observationIdentity: observationIdentity,
          controllerOwnerID: currentOwnerID
        )
        return nil
      }
      guard statusLabelFrame == snapshot.statusLabelFrame else {
        recordDecision(
          .update,
          ticket: observationTicket,
          accepted: false,
          rejection: .changedStatusLabelFrame,
          observationIdentity: observationIdentity,
          controllerOwnerID: currentOwnerID
        )
        return nil
      }
      guard visibleFrame == snapshot.visibleFrame else {
        recordDecision(
          .update,
          ticket: observationTicket,
          accepted: false,
          rejection: .changedVisibleFrame,
          observationIdentity: observationIdentity,
          controllerOwnerID: currentOwnerID
        )
        return nil
      }
      guard let proposed = MenuPanelResizeGeometry.proposal(
        snapshot: snapshot,
        pointer: pointer,
        handle: handle,
        currentSide: currentFixedSide
      ) else {
        recordDecision(
          .update,
          ticket: observationTicket,
          accepted: false,
          rejection: .proposal,
          observationIdentity: observationIdentity,
          controllerOwnerID: currentOwnerID
        )
        return nil
      }
      guard let proposal = canonicalize(proposed) else {
        recordDecision(
          .update,
          ticket: observationTicket,
          accepted: false,
          rejection: .canonicalization,
          observationIdentity: observationIdentity,
          controllerOwnerID: currentOwnerID
        )
        return nil
      }
      self.proposal = proposal
      lastPointer = pointer
      self.currentFixedSide = proposal.fixedSide
      setDesiredContentSize(proposal.contentSize, publication: .immediate)
      recordDecision(
        .update,
        ticket: observationTicket,
        accepted: true,
        rejection: .none,
        observationIdentity: observationIdentity,
        controllerOwnerID: currentOwnerID
      )
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
      canonicalize: (MenuPanelResizeProposal) -> MenuPanelResizeProposal? = { $0 },
      observationTicket: MenuPanelResizeObservationTicket? = nil,
      observationOrigin: MenuPanelResizeObservationOrigin = .directAPI,
      observationIdentity: MenuPanelResizeObservationIdentity? = nil
    ) -> MenuPanelResizeProposal? {
      let currentOwnerID = presentationOwnerID
      guard currentOwnerID == ownerID else {
        recordDecision(
          .finish,
          ticket: observationTicket,
          accepted: false,
          rejection: .owner,
          observationIdentity: observationIdentity,
          controllerOwnerID: currentOwnerID
        )
        return nil
      }
      guard isTracking else {
        recordDecision(
          .finish,
          ticket: observationTicket,
          accepted: false,
          rejection: .notTracking,
          observationIdentity: observationIdentity,
          controllerOwnerID: currentOwnerID
        )
        return nil
      }
      guard let snapshot else {
        recordDecision(
          .finish,
          ticket: observationTicket,
          accepted: false,
          rejection: .missingSnapshot,
          observationIdentity: observationIdentity,
          controllerOwnerID: currentOwnerID
        )
        return nil
      }
      guard let handle else {
        recordDecision(
          .finish,
          ticket: observationTicket,
          accepted: false,
          rejection: .missingHandle,
          observationIdentity: observationIdentity,
          controllerOwnerID: currentOwnerID
        )
        return nil
      }
      guard let proposal else {
        recordDecision(
          .finish,
          ticket: observationTicket,
          accepted: false,
          rejection: .missingProposal,
          observationIdentity: observationIdentity,
          controllerOwnerID: currentOwnerID
        )
        return nil
      }
      guard let lastPointer else {
        recordDecision(
          .finish,
          ticket: observationTicket,
          accepted: false,
          rejection: .missingPointer,
          observationIdentity: observationIdentity,
          controllerOwnerID: currentOwnerID
        )
        return nil
      }
      guard let currentFixedSide else {
        recordDecision(
          .finish,
          ticket: observationTicket,
          accepted: false,
          rejection: .missingFixedSide,
          observationIdentity: observationIdentity,
          controllerOwnerID: currentOwnerID
        )
        return nil
      }
      guard statusLabelFrame == snapshot.statusLabelFrame else {
        recordDecision(
          .finish,
          ticket: observationTicket,
          accepted: false,
          rejection: .changedStatusLabelFrame,
          observationIdentity: observationIdentity,
          controllerOwnerID: currentOwnerID
        )
        return nil
      }
      guard visibleFrame == snapshot.visibleFrame else {
        recordDecision(
          .finish,
          ticket: observationTicket,
          accepted: false,
          rejection: .changedVisibleFrame,
          observationIdentity: observationIdentity,
          controllerOwnerID: currentOwnerID
        )
        return nil
      }
      guard currentFrame == proposal.frame else {
        recordDecision(
          .finish,
          ticket: observationTicket,
          accepted: false,
          rejection: .changedFrame,
          observationIdentity: observationIdentity,
          controllerOwnerID: currentOwnerID
        )
        return nil
      }
      guard let proposed = MenuPanelResizeGeometry.releaseProposal(
        snapshot: snapshot,
        pointer: lastPointer,
        handle: handle,
        currentSide: currentFixedSide
      ) else {
        recordDecision(
          .finish,
          ticket: observationTicket,
          accepted: false,
          rejection: .proposal,
          observationIdentity: observationIdentity,
          controllerOwnerID: currentOwnerID
        )
        return nil
      }
      guard let finalProposal = canonicalize(proposed) else {
        recordDecision(
          .finish,
          ticket: observationTicket,
          accepted: false,
          rejection: .canonicalization,
          observationIdentity: observationIdentity,
          controllerOwnerID: currentOwnerID
        )
        return nil
      }
      isTracking = false
      recordTrackingClear(
        ticket: observationTicket,
        origin: observationOrigin
      )
      self.handle = nil
      self.proposal = finalProposal
      self.currentFixedSide = finalProposal.fixedSide
      completedPreferenceSize = finalProposal.contentSize
      setDesiredContentSize(finalProposal.contentSize, publication: .immediate)
      recordDecision(
        .finish,
        ticket: observationTicket,
        accepted: true,
        rejection: .none,
        observationIdentity: observationIdentity,
        controllerOwnerID: currentOwnerID
      )
      return finalProposal
    }

    @discardableResult
    func cancel() -> CGRect? {
      cancelSnapshot()?.initialFrame
    }

    @discardableResult
    func cancelSnapshot(
      ownerID: UUID? = nil,
      publication: MenuPanelResizePublicationTiming = .immediate,
      observationTicket: MenuPanelResizeObservationTicket? = nil,
      observationOrigin: MenuPanelResizeObservationOrigin = .directAPI,
      fallbackObservationSink: (any MenuPanelResizeObservationSink)? = nil,
      observationIdentity: MenuPanelResizeObservationIdentity? = nil
    ) -> MenuPanelResizeSnapshot? {
      let currentOwnerID = presentationOwnerID
      guard currentOwnerID == ownerID else {
        recordDecision(
          .cancel,
          ticket: observationTicket,
          accepted: false,
          rejection: .owner,
          fallbackSink: fallbackObservationSink,
          observationIdentity: observationIdentity,
          controllerOwnerID: currentOwnerID
        )
        return nil
      }
      guard isTracking else {
        recordDecision(
          .cancel,
          ticket: observationTicket,
          accepted: false,
          rejection: .notTracking,
          fallbackSink: fallbackObservationSink,
          observationIdentity: observationIdentity,
          controllerOwnerID: currentOwnerID
        )
        return nil
      }
      let snapshot = snapshot
      isTracking = false
      recordTrackingClear(
        ticket: observationTicket,
        origin: observationOrigin,
        fallbackSink: fallbackObservationSink
      )
      self.snapshot = nil
      handle = nil
      proposal = nil
      lastPointer = nil
      currentFixedSide = nil
      completedPreferenceSize = nil
      setDesiredContentSize(nil, publication: publication)
      recordDecision(
        .cancel,
        ticket: observationTicket,
        accepted: true,
        rejection: .none,
        fallbackSink: fallbackObservationSink,
        observationIdentity: observationIdentity,
        controllerOwnerID: currentOwnerID
      )
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
      var previousObservationInvocation: MenuPanelResizeObservationInvocation?
      let scopedInvocation = pushObservationInvocation(
        .claimReplacement,
        previous: &previousObservationInvocation
      )
      defer {
        if scopedInvocation { activeObservationInvocation = previousObservationInvocation }
      }
      previousRelinquish?()
      clearInteractionState(
        publication: publication,
        origin: .ownerReplacement
      )
      let observation = observationSink.flatMap { sink in
        sink.isRecording ? sink : nil
      }
      let previousOwnerID: UUID?
      if case .some = observation {
        previousOwnerID = presentationOwnerID
      } else {
        previousOwnerID = nil
      }
      presentationOwnerID = ownerID
      relinquishPresentation = onRelinquish
      if let observation, observation.isRecording {
        observation.record(
          .ownerTransition(
            controller: ObjectIdentifier(self),
            previous: previousOwnerID,
            current: ownerID
          )
        )
      }
      return true
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
      publication: MenuPanelResizePublicationTiming = .immediate,
      observationSink: (any MenuPanelResizeObservationSink)? = nil,
      observationTicket: MenuPanelResizeObservationTicket? = nil,
      observationOrigin: MenuPanelResizeObservationOrigin = .ownerRelease,
      observationIdentity: MenuPanelResizeObservationIdentity? = nil,
      observationInvocation: MenuPanelResizeObservationInvocation? = nil
    ) -> Bool {
      let currentOwnerID = presentationOwnerID
      guard currentOwnerID == ownerID else {
        recordDecision(
          .relinquish,
          ticket: observationTicket,
          accepted: false,
          rejection: .deferredOwner,
          fallbackSink: observationSink,
          observationIdentity: observationIdentity,
          controllerOwnerID: currentOwnerID
        )
        return false
      }
      let relinquish = relinquishPresentation
      relinquishPresentation = nil
      var previousObservationInvocation: MenuPanelResizeObservationInvocation?
      let scopedInvocation = pushObservationInvocation(
        observationInvocation ?? .normalRelease,
        fallbackSink: observationSink,
        previous: &previousObservationInvocation
      )
      defer {
        if scopedInvocation { activeObservationInvocation = previousObservationInvocation }
      }
      relinquish?()
      clearInteractionState(
        publication: publication,
        origin: observationOrigin,
        ticket: observationTicket,
        fallbackSink: observationSink
      )
      presentationOwnerID = nil
      let sink = observationSink ?? self.observationSink
      if let sink, sink.isRecording {
        sink.record(
          .ownerTransition(
            controller: ObjectIdentifier(self),
            previous: ownerID,
            current: nil
          )
        )
      }
      return true
    }

    func isPresentationOwner(_ ownerID: UUID) -> Bool {
      presentationOwnerID == ownerID
    }

    func presentationOwnerEvaluation(for ownerID: UUID) -> (ownerID: UUID?, matches: Bool) {
      let currentOwnerID = presentationOwnerID
      return (currentOwnerID, currentOwnerID == ownerID)
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
      setDesiredContentSize(size, publication: publication)
      return true
    }

    @discardableResult
    func publishPresentationContentSize(ownerID: UUID? = nil) -> Bool {
      guard presentationOwnerID == ownerID else { return false }
      publishDesiredContentSize()
      return true
    }

    @discardableResult
    func cancelCompletion(ownerID: UUID? = nil) -> MenuPanelResizeSnapshot? {
      guard presentationOwnerID == ownerID,
        !isTracking, completedPreferenceSize != nil
      else { return nil }
      let snapshot = snapshot
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
      guard presentationOwnerID == ownerID else { return false }
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
      return true
    }

    private func clearInteractionState(
      publication: MenuPanelResizePublicationTiming,
      origin: MenuPanelResizeObservationOrigin,
      ticket: MenuPanelResizeObservationTicket? = nil,
      fallbackSink: (any MenuPanelResizeObservationSink)? = nil
    ) {
      isTracking = false
      recordTrackingClear(
        ticket: ticket,
        origin: origin,
        fallbackSink: fallbackSink
      )
      snapshot = nil
      handle = nil
      proposal = nil
      lastPointer = nil
      currentFixedSide = nil
      completedPreferenceSize = nil
      setDesiredContentSize(nil, publication: publication)
    }

    private func setDesiredContentSize(
      _ size: CGSize?,
      publication: MenuPanelResizePublicationTiming
    ) {
      desiredEffectiveContentSize = size
      if publication == .immediate { publishDesiredContentSize() }
    }

    private func publishDesiredContentSize() {
      if effectiveContentSize != desiredEffectiveContentSize {
        effectiveContentSize = desiredEffectiveContentSize
      }
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

  struct MenuPanelResizeInstaller: NSViewRepresentable {
    let controller: MenuPanelResizeController
    let geometryStore: MenuPanelGeometryStore?
    let preferredSize: CGSize
    let canResize: Bool
    let onCommit: (CGSize) -> Void

    func makeNSView(context: Context) -> MenuPanelResizeHostView {
      let view = MenuPanelResizeHostView(controller: controller)
      view.configure(
        geometryStore: geometryStore,
        preferredSize: preferredSize,
        canResize: canResize,
        onCommit: onCommit
      )
      return view
    }

    func updateNSView(_ view: MenuPanelResizeHostView, context: Context) {
      view.configure(
        geometryStore: geometryStore,
        preferredSize: preferredSize,
        canResize: canResize,
        onCommit: onCommit
      )
      view.installIfNeeded()
    }

    static func dismantleNSView(_ view: MenuPanelResizeHostView, coordinator: ()) {
      view.uninstall()
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
    private var visibilityObservation: NSKeyValueObservation?
    private var previousAcceptsMouseMovedEvents: Bool?
    private var preferredSize = CGSize.zero
    private var hasPreferredSize = false
    private var canResize = false
    private var onCommit: (CGSize) -> Void = { _ in }
    private var cursor: NSCursor?
    private lazy var leftFixedCornerCursor = diagonalCursor(
      systemSymbolName: "arrow.up.left.and.arrow.down.right"
    )
    private lazy var rightFixedCornerCursor = diagonalCursor(
      systemSymbolName: "arrow.up.right.and.arrow.down.left"
    )
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
    weak var observationSink: (any MenuPanelResizeObservationSink)?

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
      observationSink = controller.observationSinkForNewHost()
      self.fallbackVisibleFrameProvider = fallbackVisibleFrameProvider ?? { window in
        Self.publicFallbackVisibleFrame(for: window)
      }
      super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      installIfNeeded()
    }

    override func layout() {
      super.layout()
      reconcileNativePresentation()
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

    func installIfNeeded() {
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
      guard let window else { return }
      installedWindow = window
      let attachmentID = UUID()
      self.attachmentID = attachmentID
      let observation = observationSink.flatMap { sink in
        sink.isRecording ? sink : nil
      }
      let previousRevision = observation.map { _ in installationRevision }
      installationRevision &+= 1
      if let observation, let previousRevision {
        observation.record(
          .attachment(
            host: ObjectIdentifier(self),
            window: ObjectIdentifier(window),
            controller: ObjectIdentifier(controller),
            attachmentID: attachmentID,
            oldRevision: previousRevision,
            newRevision: installationRevision,
            installed: true
          )
        )
      }
      isPresented = window.isVisible
      invalidateQueuedWork()
      acquirePresentation(ownerID: attachmentID, window: window)
    }

    func uninstall() {
      let oldAttachmentID = attachmentID
      let oldWindow = installedWindow
      let controller = controller
      let oldObservationIdentity: MenuPanelResizeObservationIdentity?
      if let observationSink, observationSink.isRecording {
        oldObservationIdentity = MenuPanelResizeObservationIdentity(
          host: ObjectIdentifier(self),
          window: oldWindow.map(ObjectIdentifier.init),
          controller: ObjectIdentifier(controller),
          attachmentID: oldAttachmentID,
          installationRevision: installationRevision
        )
      } else {
        oldObservationIdentity = nil
      }
      let wasPresentationOwner = oldAttachmentID.map(controller.isPresentationOwner) ?? false
      if let oldAttachmentID, wasPresentationOwner {
        makeOwnedNativeCleanup(ownerID: oldAttachmentID, window: oldWindow)()
        _ = controller.setPresentationRelinquish(
          ownerID: oldAttachmentID,
          makeDeferredRelinquishHandler(
            ownerID: oldAttachmentID,
            window: oldWindow,
            geometryStore: geometryStore,
            fallbackVisibleFrameProvider: fallbackVisibleFrameProvider,
            observationSink: observationSink,
            observationOrigin: .deferredOwnerRelease
          )
        )
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
      if let observationSink, observationSink.isRecording {
        if let oldObservationIdentity {
          observationSink.record(
            .attachment(
              host: oldObservationIdentity.host,
              window: oldObservationIdentity.window,
              controller: oldObservationIdentity.controller,
              attachmentID: oldObservationIdentity.attachmentID,
              oldRevision: oldObservationIdentity.installationRevision,
              newRevision: installationRevision,
              installed: false
            )
          )
        } else {
          observationSink.markIncomplete()
        }
      }
      if wasPresentationOwner {
        let pendingContinuation: (
          sink: any MenuPanelResizeObservationSink,
          token: MenuPanelResizeObservationPendingRelease
        )?
        if let observationSink, observationSink.isRecording {
          if let oldObservationIdentity,
            let token = observationSink.markPendingRelease(oldObservationIdentity)
          {
            pendingContinuation = (sink: observationSink, token: token)
          } else {
            observationSink.markIncomplete()
            pendingContinuation = nil
          }
        } else {
          pendingContinuation = nil
        }
        DispatchQueue.main.async { [self, controller, pendingContinuation] in
          if let pendingContinuation {
            let completed = controller.releasePresentation(
              ownerID: oldAttachmentID,
              publication: .deferred,
              observationSink: pendingContinuation.sink,
              observationOrigin: .deferredOwnerRelease,
              observationIdentity: pendingContinuation.token.identity,
              observationInvocation: .queuedPendingRelease(pendingContinuation.token)
            )
            if completed {
              _ = controller.publishPresentationContentSize()
            }
            pendingContinuation.sink.finishPendingRelease(
              pendingContinuation.token,
              completed: completed
            )
          } else {
            if controller.releasePresentation(
              ownerID: oldAttachmentID,
              publication: .deferred,
              observationIdentity: oldObservationIdentity
            ) {
              _ = controller.publishPresentationContentSize()
            }
          }
          withExtendedLifetime(self) {}
        }
      } else {
        removeNativeHooksWithoutRestoringWindow(oldWindow)
      }
    }

    func bindObservationSink(
      _ sink: (any MenuPanelResizeObservationSink)?,
      window bindingWindow: NSWindow? = nil
    ) {
      observationSink = sink
      controller.bindObservationSink(sink)
      guard let sink, sink.isRecording else { return }
      sink.record(
        .binding(
          host: ObjectIdentifier(self),
          window: (installedWindow ?? bindingWindow).map(ObjectIdentifier.init),
          controller: ObjectIdentifier(controller),
          attachmentID: attachmentID,
          revision: installationRevision,
          bindingTime: installedWindow != nil && attachmentID != nil
        )
      )
    }

    func unbindObservationSink(_ sink: any MenuPanelResizeObservationSink) {
      if observationSink === sink { observationSink = nil }
      if controller.observationSink === sink { controller.bindObservationSink(nil) }
    }

    private func acquirePresentation(ownerID: UUID, window: NSWindow) {
      guard controller.claimPresentation(ownerID: ownerID, publication: .deferred),
        attachmentID == ownerID, installedWindow === window, self.window === window
      else { return }

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
        fallbackVisibleFrameProvider: fallbackVisibleFrameProvider,
        observationSink: observationSink,
        observationOrigin: .ownerReplacement
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
      return { [weak self, weak controller, weak window] in
        guard controller?.isPresentationOwner(ownerID) == true else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        visibilityObservation?.invalidate()
        if let self {
          self.removeWindowObservers(for: window)
          self.monitor = nil
          self.visibilityObservation = nil
          self.previousAcceptsMouseMovedEvents = nil
          self.activeStatusButtonSource = nil
          self.clearAlignment()
          self.presentationTop = nil
          self.invalidateQueuedWork()
          self.resetCursor()
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
      fallbackVisibleFrameProvider: @escaping FallbackVisibleFrameProvider,
      observationSink: (any MenuPanelResizeObservationSink)?,
      observationOrigin: MenuPanelResizeObservationOrigin
    ) -> @MainActor () -> Void {
      return { [weak controller, weak window, weak geometryStore, weak observationSink] in
        let snapshot = controller?.cancelSnapshot(
          ownerID: ownerID,
          publication: .deferred,
          observationOrigin: observationOrigin,
          fallbackObservationSink: observationSink
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
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
      visibilityObservation?.invalidate()
      visibilityObservation = nil
      removeWindowObservers(for: window)
      previousAcceptsMouseMovedEvents = nil
      cursor = nil
    }

    private func recordGate(
      _ gate: MenuPanelResizeObservationGate,
      passed: Bool,
      identity: MenuPanelResizeObservationIdentity?,
      controllerOwnerID: UUID?,
      ticket: MenuPanelResizeObservationTicket?,
      sink: (any MenuPanelResizeObservationSink)?
    ) {
      guard let sink else { return }
      guard let identity else {
        sink.markIncomplete()
        return
      }
      sink.record(.gate(identity: identity,
        controllerOwnerID: controllerOwnerID,
        ticket: ticket,
        gate: gate,
        passed: passed
      ))
    }

    private func recordOutcome(
      _ consumed: Bool,
      identity: MenuPanelResizeObservationIdentity?,
      controllerOwnerID: UUID?,
      ticket: MenuPanelResizeObservationTicket?,
      sink: (any MenuPanelResizeObservationSink)?
    ) {
      guard let sink else { return }
      guard let identity else {
        sink.markIncomplete()
        return
      }
      sink.record(.outcome(identity: identity,
        controllerOwnerID: controllerOwnerID,
        ticket: ticket,
        consumed: consumed
      ))
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
      let observation: (any MenuPanelResizeObservationSink)?
      if let sink = observationSink, sink.isRecording {
        observation = sink
      } else {
        observation = nil
      }
      let attachmentID = self.attachmentID
      let ownerEvaluation = observation.flatMap { _ in
        attachmentID.map { controller.presentationOwnerEvaluation(for: $0) }
      }
      let isPresentationOwner = attachmentID.map {
        ownerEvaluation?.matches ?? controller.isPresentationOwner($0)
      } ?? false
      let controllerOwnerID = ownerEvaluation?.ownerID
      let window: NSWindow?
      if observation != nil || isPresentationOwner {
        window = installedWindow
      } else {
        window = nil
      }
      let identity = observation.map { _ in
        MenuPanelResizeObservationIdentity(
          host: ObjectIdentifier(self),
          window: window.map(ObjectIdentifier.init),
          controller: ObjectIdentifier(controller),
          attachmentID: attachmentID,
          installationRevision: self.installationRevision
        )
      }
      let eventIdentifier: ObjectIdentifier?
      if case .some = observation {
        eventIdentifier = ObjectIdentifier(event)
      } else {
        eventIdentifier = nil
      }
      let ticket: MenuPanelResizeObservationTicket?
      if let observation, let eventIdentifier {
        ticket = observation.receive(
          event: eventIdentifier,
          host: ObjectIdentifier(self)
        )
      } else {
        ticket = nil
      }

      guard let attachmentID else {
        recordGate(
          .owner,
          passed: false,
          identity: identity,
          controllerOwnerID: controllerOwnerID,
          ticket: ticket,
          sink: observation
        )
        recordOutcome(
          false,
          identity: identity,
          controllerOwnerID: controllerOwnerID,
          ticket: ticket,
          sink: observation
        )
        return event
      }
      recordGate(
        .owner,
        passed: isPresentationOwner,
        identity: identity,
        controllerOwnerID: controllerOwnerID,
        ticket: ticket,
        sink: observation
      )
      guard isPresentationOwner else {
        recordOutcome(
          false,
          identity: identity,
          controllerOwnerID: controllerOwnerID,
          ticket: ticket,
          sink: observation
        )
        return event
      }
      guard let window else {
        recordGate(
          .window,
          passed: false,
          identity: identity,
          controllerOwnerID: controllerOwnerID,
          ticket: ticket,
          sink: observation
        )
        recordOutcome(
          false,
          identity: identity,
          controllerOwnerID: controllerOwnerID,
          ticket: ticket,
          sink: observation
        )
        return event
      }
      let isWindowEvent = event.window === window
      recordGate(
        .window,
        passed: isWindowEvent,
        identity: identity,
        controllerOwnerID: controllerOwnerID,
        ticket: ticket,
        sink: observation
      )
      guard isWindowEvent else {
        recordOutcome(
          false,
          identity: identity,
          controllerOwnerID: controllerOwnerID,
          ticket: ticket,
          sink: observation
        )
        return event
      }
      let isVisible = window.isVisible
      recordGate(
        .visibility,
        passed: isVisible,
        identity: identity,
        controllerOwnerID: controllerOwnerID,
        ticket: ticket,
        sink: observation
      )
      guard isVisible else {
        resetCursor()
        recordOutcome(
          false,
          identity: identity,
          controllerOwnerID: controllerOwnerID,
          ticket: ticket,
          sink: observation
        )
        return event
      }
      switch event.type {
      case .leftMouseDown:
        let consumed = begin(
          event,
          in: window,
          observationTicket: ticket,
          observationIdentity: identity
        )
        recordOutcome(
          consumed,
          identity: identity,
          controllerOwnerID: controllerOwnerID,
          ticket: ticket,
          sink: observation
        )
        return consumed ? nil : event
      case .leftMouseDragged:
        guard controller.isOwned(by: attachmentID) else {
          recordOutcome(
            false,
            identity: identity,
            controllerOwnerID: controllerOwnerID,
            ticket: ticket,
            sink: observation
          )
          return event
        }
        guard isLiveResizeEligible(in: window) else {
          cancelAndRestore(
            in: window,
            observationTicket: ticket,
            observationOrigin: .eligibilityLoss,
            observationIdentity: identity
          )
          recordOutcome(
            true,
            identity: identity,
            controllerOwnerID: controllerOwnerID,
            ticket: ticket,
            sink: observation
          )
          return nil
        }
        update(
          event,
          in: window,
          observationTicket: ticket,
          observationIdentity: identity
        )
        recordOutcome(
          true,
          identity: identity,
          controllerOwnerID: controllerOwnerID,
          ticket: ticket,
          sink: observation
        )
        return nil
      case .leftMouseUp:
        guard controller.isOwned(by: attachmentID) else {
          recordOutcome(
            false,
            identity: identity,
            controllerOwnerID: controllerOwnerID,
            ticket: ticket,
            sink: observation
          )
          return event
        }
        guard isLiveResizeEligible(in: window) else {
          cancelAndRestore(
            in: window,
            observationTicket: ticket,
            observationOrigin: .eligibilityLoss,
            observationIdentity: identity
          )
          recordOutcome(
            true,
            identity: identity,
            controllerOwnerID: controllerOwnerID,
            ticket: ticket,
            sink: observation
          )
          return nil
        }
        finish(
          event,
          in: window,
          observationTicket: ticket,
          observationIdentity: identity
        )
        recordOutcome(
          true,
          identity: identity,
          controllerOwnerID: controllerOwnerID,
          ticket: ticket,
          sink: observation
        )
        return nil
      case .keyDown:
        let isEscape = event.keyCode == 53
        guard isEscape else {
          recordOutcome(
            false,
            identity: identity,
            controllerOwnerID: controllerOwnerID,
            ticket: ticket,
            sink: observation
          )
          return event
        }
        guard ownsTracking else {
          recordOutcome(
            false,
            identity: identity,
            controllerOwnerID: controllerOwnerID,
            ticket: ticket,
            sink: observation
          )
          return event
        }
        cancelAndRestore(
          in: window,
          observationTicket: ticket,
          observationOrigin: .escape,
          observationIdentity: identity
        )
        recordOutcome(
          true,
          identity: identity,
          controllerOwnerID: controllerOwnerID,
          ticket: ticket,
          sink: observation
        )
        return nil
      case .mouseMoved, .cursorUpdate:
        updateCursor(for: event, in: window)
        recordOutcome(
          false,
          identity: identity,
          controllerOwnerID: controllerOwnerID,
          ticket: ticket,
          sink: observation
        )
        return event
      case .mouseExited:
        resetCursor()
        recordOutcome(
          false,
          identity: identity,
          controllerOwnerID: controllerOwnerID,
          ticket: ticket,
          sink: observation
        )
        return event
      default:
        recordOutcome(
          false,
          identity: identity,
          controllerOwnerID: controllerOwnerID,
          ticket: ticket,
          sink: observation
        )
        return event
      }
    }

    func beginReadiness(
      at locationInWindow: CGPoint,
      in window: NSWindow
    ) -> MenuPanelResizeBeginReadiness {
      beginReadiness(
        at: locationInWindow,
        in: window,
        phase: .fixturePreflight,
        ticket: nil,
        sourceIdentity: nil
      )
    }

    private func beginReadiness(
      at locationInWindow: CGPoint,
      in window: NSWindow,
      phase: MenuPanelResizeObservationPhase,
      ticket: MenuPanelResizeObservationTicket?,
      sourceIdentity: MenuPanelResizeObservationIdentity?
    ) -> MenuPanelResizeBeginReadiness {
      guard isLiveResizeEligible(in: window) else {
        recordReadiness(
          .blocked,
          rejection: .liveResizeEligibility,
          phase: phase,
          ticket: ticket,
          identity: sourceIdentity,
          window: window,
          attachmentID: nil,
          controllerOwnerID: nil
        )
        return .blocked
      }
      guard queuedRevision == nil else {
        recordReadiness(
          .reconciling,
          rejection: .queuedRevision,
          phase: phase,
          ticket: ticket,
          identity: sourceIdentity,
          window: window,
          attachmentID: nil,
          controllerOwnerID: nil
        )
        return .reconciling
      }
      guard let attachmentID else {
        recordReadiness(
          .blocked,
          rejection: .missingAttachment,
          phase: phase,
          ticket: ticket,
          identity: nil,
          window: window,
          attachmentID: nil,
          controllerOwnerID: nil
        )
        return .blocked
      }
      let ownerEvaluation: (ownerID: UUID?, matches: Bool)?
      if let observationSink, observationSink.isRecording {
        ownerEvaluation = controller.presentationOwnerEvaluation(for: attachmentID)
      } else {
        ownerEvaluation = nil
      }
      guard ownerEvaluation?.matches ?? controller.isPresentationOwner(attachmentID) else {
        recordReadiness(
          .blocked,
          rejection: .owner,
          phase: phase,
          ticket: ticket,
          identity: nil,
          window: window,
          attachmentID: attachmentID,
          controllerOwnerID: ownerEvaluation?.ownerID
        )
        return .blocked
      }
      guard let statusButton = geometryStore?.resolveStatusButton() else {
        recordReadiness(
          .blocked,
          rejection: .statusButtonUnavailable,
          phase: phase,
          ticket: ticket,
          identity: nil,
          window: window,
          attachmentID: attachmentID,
          controllerOwnerID: ownerEvaluation?.ownerID
        )
        return .blocked
      }
      guard let screen = window.screen else {
        recordReadiness(
          .blocked,
          rejection: .screenUnavailable,
          phase: phase,
          ticket: ticket,
          identity: nil,
          window: window,
          attachmentID: attachmentID,
          controllerOwnerID: ownerEvaluation?.ownerID
        )
        return .blocked
      }
      guard statusButton.sourceIdentity == alignedStatusButtonSource else {
        recordReadiness(
          .blocked,
          rejection: .statusButtonSource,
          phase: phase,
          ticket: ticket,
          identity: nil,
          window: window,
          attachmentID: attachmentID,
          controllerOwnerID: ownerEvaluation?.ownerID
        )
        return .blocked
      }
      guard statusButton.screenFrame == alignedStatusButtonFrame else {
        recordReadiness(
          .blocked,
          rejection: .statusButtonFrame,
          phase: phase,
          ticket: ticket,
          identity: nil,
          window: window,
          attachmentID: attachmentID,
          controllerOwnerID: ownerEvaluation?.ownerID
        )
        return .blocked
      }
      guard screen.visibleFrame == alignedVisibleFrame else {
        recordReadiness(
          .blocked,
          rejection: .visibleFrame,
          phase: phase,
          ticket: ticket,
          identity: nil,
          window: window,
          attachmentID: attachmentID,
          controllerOwnerID: ownerEvaluation?.ownerID
        )
        return .blocked
      }
      guard window.frame == alignedFrame else {
        recordReadiness(
          .blocked,
          rejection: .windowFrame,
          phase: phase,
          ticket: ticket,
          identity: nil,
          window: window,
          attachmentID: attachmentID,
          controllerOwnerID: ownerEvaluation?.ownerID
        )
        return .blocked
      }
      guard let fixedSide = MenuPanelResizeGeometry.anchoredSide(
        panelFrame: window.frame,
        statusLabelFrame: statusButton.screenFrame
      ) else {
        recordReadiness(
          .blocked,
          rejection: .fixedSideUnavailable,
          phase: phase,
          ticket: ticket,
          identity: nil,
          window: window,
          attachmentID: attachmentID,
          controllerOwnerID: ownerEvaluation?.ownerID
        )
        return .blocked
      }
      guard fixedSide == alignedFixedSide else {
        recordReadiness(
          .blocked,
          rejection: .fixedSideMismatch,
          phase: phase,
          ticket: ticket,
          identity: nil,
          window: window,
          attachmentID: attachmentID,
          controllerOwnerID: ownerEvaluation?.ownerID
        )
        return .blocked
      }
      guard let handle = MenuPanelResizeGeometry.handle(
        at: convert(locationInWindow, from: nil),
        in: bounds,
        fixedSide: fixedSide
      ) else {
        recordReadiness(
          .blocked,
          rejection: .handleUnavailable,
          phase: phase,
          ticket: ticket,
          identity: nil,
          window: window,
          attachmentID: attachmentID,
          controllerOwnerID: ownerEvaluation?.ownerID
        )
        return .blocked
      }
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
      recordReadiness(
        .ready,
        rejection: .none,
        phase: phase,
        ticket: ticket,
        identity: nil,
        window: window,
        attachmentID: attachmentID,
        controllerOwnerID: ownerEvaluation?.ownerID
      )
      return .ready(
        snapshot: snapshot,
        handle: handle,
        ownerID: attachmentID,
        statusButtonSource: statusButton.sourceIdentity
      )
    }

    private func recordReadiness(
      _ result: MenuPanelResizeObservationReadiness,
      rejection: MenuPanelResizeObservationRejection,
      phase: MenuPanelResizeObservationPhase,
      ticket: MenuPanelResizeObservationTicket?,
      identity sourceIdentity: MenuPanelResizeObservationIdentity?,
      window: NSWindow,
      attachmentID: UUID?,
      controllerOwnerID: UUID?
    ) {
      guard let observationSink, observationSink.isRecording else { return }
      let identity = sourceIdentity ?? MenuPanelResizeObservationIdentity(
        host: ObjectIdentifier(self),
        window: ObjectIdentifier(window),
        controller: ObjectIdentifier(controller),
        attachmentID: attachmentID ?? self.attachmentID,
        installationRevision: installationRevision
      )
      observationSink.record(.readiness(identity: identity,
        controllerOwnerID: controllerOwnerID,
        ticket: ticket,
        phase: phase,
        result: result,
        rejection: rejection
      ))
    }

    private func begin(
      _ event: NSEvent,
      in window: NSWindow,
      observationTicket: MenuPanelResizeObservationTicket?,
      observationIdentity: MenuPanelResizeObservationIdentity?
    ) -> Bool {
      guard case let .ready(snapshot, handle, ownerID, statusButtonSource) = beginReadiness(
        at: event.locationInWindow,
        in: window,
        phase: .eventAdmission,
        ticket: observationTicket,
        sourceIdentity: observationIdentity
      ) else { return false }
      guard controller.begin(
        snapshot: snapshot,
        handle: handle,
        ownerID: ownerID,
        observationTicket: observationTicket,
        observationOrigin: .mouseDown,
        observationIdentity: observationIdentity
      ) else {
        return false
      }
      invalidateQueuedWork()
      activeStatusButtonSource = statusButtonSource
      setCursor(cursor(for: handle, fixedSide: snapshot.fixedSide))
      return true
    }

    private func update(
      _ event: NSEvent,
      in window: NSWindow,
      observationTicket: MenuPanelResizeObservationTicket?,
      observationIdentity: MenuPanelResizeObservationIdentity?
    ) {
      guard let attachmentID,
        let statusLabelFrame = activeStatusButtonFrame(),
        let screen = window.screen,
        let proposal = controller.update(
        pointer: window.convertPoint(toScreen: event.locationInWindow),
        statusLabelFrame: statusLabelFrame,
        visibleFrame: screen.visibleFrame,
        ownerID: attachmentID,
        canonicalize: {
          self.backingAlignedProposal(
            $0,
            in: window,
            on: screen,
            statusLabelFrame: statusLabelFrame,
            observationTicket: observationTicket,
            observationIdentity: observationIdentity,
            controllerOwnerID: attachmentID
          )
        },
        observationTicket: observationTicket,
        observationIdentity: observationIdentity
      ) else {
        cancelAndRestore(
          in: window,
          observationTicket: observationTicket,
          observationOrigin: .mouseDrag,
          observationIdentity: observationIdentity
        )
        return
      }
      applyFrame(proposal.frame, to: window, displayImmediately: false)
      if let handle = controller.currentHandle,
        let fixedSide = controller.currentFixedSide
      {
        setCursor(cursor(for: handle, fixedSide: fixedSide))
      }
    }

    private func finish(
      _ event: NSEvent,
      in window: NSWindow,
      observationTicket: MenuPanelResizeObservationTicket?,
      observationIdentity: MenuPanelResizeObservationIdentity?
    ) {
      let endingStatusButton = geometryStore?.resolveStatusButton()
      guard let attachmentID,
        endingStatusButton?.sourceIdentity == activeStatusButtonSource,
        let statusLabelFrame = endingStatusButton?.screenFrame,
        let screen = window.screen,
        let transient = controller.update(
          pointer: window.convertPoint(toScreen: event.locationInWindow),
          statusLabelFrame: statusLabelFrame,
          visibleFrame: screen.visibleFrame,
          ownerID: attachmentID,
          canonicalize: {
            self.backingAlignedProposal(
              $0,
              in: window,
              on: screen,
              statusLabelFrame: statusLabelFrame,
              observationTicket: observationTicket,
              observationIdentity: observationIdentity,
              controllerOwnerID: attachmentID
            )
          },
          observationTicket: observationTicket,
          observationIdentity: observationIdentity
        )
      else {
        cancelAndRestore(
          in: window,
          observationTicket: observationTicket,
          observationOrigin: .rejectedFinalFrame,
          observationIdentity: observationIdentity
        )
        return
      }
      applyFrame(transient.frame, to: window)
      guard let final = controller.finish(
        statusLabelFrame: statusLabelFrame,
        visibleFrame: screen.visibleFrame,
        currentFrame: window.frame,
        ownerID: attachmentID,
        canonicalize: {
          self.backingAlignedProposal(
            $0,
            in: window,
            on: screen,
            statusLabelFrame: statusLabelFrame,
            observationTicket: observationTicket,
            observationIdentity: observationIdentity,
            controllerOwnerID: attachmentID
          )
        },
        observationTicket: observationTicket,
        observationOrigin: .mouseUp,
        observationIdentity: observationIdentity
      ) else {
        cancelAndRestore(
          in: window,
          observationTicket: observationTicket,
          observationOrigin: .rejectedFinalFrame,
          observationIdentity: observationIdentity
        )
        return
      }
      let adoptedFrame = applyFrame(final.frame, to: window)
      let adoptedContentSize = window.contentRect(forFrameRect: window.frame).size
      let adoptedEffectiveSize = controller.setPresentationContentSize(
        final.contentSize,
        ownerID: attachmentID
      )
      guard adoptedFrame, adoptedContentSize == final.contentSize,
        adoptedEffectiveSize,
        controller.presentationContentSize(ownerID: attachmentID) == final.contentSize
      else {
        let snapshot = controller.cancelCompletion(ownerID: attachmentID)
        activeStatusButtonSource = nil
        if let snapshot {
          restore(snapshot: snapshot, in: window, ownerID: attachmentID)
        }
        resetCursor()
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
      _ = controller.clearCompletion(preferredSize: preferredSize, ownerID: attachmentID)
      invalidateQueuedWork()
      scheduleReconcile()
      updateCursorForCurrentPointer(in: window)
    }

    private func cancelAndRestore(
      in window: NSWindow,
      publication: MenuPanelResizePublicationTiming = .immediate,
      observationTicket: MenuPanelResizeObservationTicket? = nil,
      observationOrigin: MenuPanelResizeObservationOrigin = .directAPI,
      observationIdentity: MenuPanelResizeObservationIdentity? = nil
    ) {
      guard let attachmentID, controller.isPresentationOwner(attachmentID) else { return }
      let snapshot = controller.cancelSnapshot(
        ownerID: attachmentID,
        publication: publication,
        observationTicket: observationTicket,
        observationOrigin: observationOrigin,
        observationIdentity: observationIdentity
      )
      activeStatusButtonSource = nil
      if let snapshot {
        restore(
          snapshot: snapshot,
          in: window,
          ownerID: attachmentID,
          publication: publication
        )
      }
      resetCursor()
    }

    private func isLiveResizeEligible(in window: NSWindow) -> Bool {
      canResize && !pendingExternalPreference && window.attachedSheet == nil
        && window.childWindows?.contains(where: \.isVisible) != true
    }

    @objc private func windowWillClose() {
      guard ownsPresentation else { return }
      isPresented = false
      presentationTop = nil
      invalidateQueuedWork()
      if let installedWindow {
        cancelAndRestore(
          in: installedWindow,
          publication: .deferred,
          observationOrigin: .windowClose
        )
      }
      scheduleReconcile()
    }

    @objc private func windowResignedKey() {
      guard ownsPresentation else { return }
      isPresented = false
      presentationTop = nil
      invalidateQueuedWork()
      let window = installedWindow
      if ownsTracking {
        // A hidden window is a transient hide; the deferred visibility
        // reconcile cancels the drag only if the window stays hidden.
        if let window, window.isVisible {
          cancelAndRestore(
            in: window,
            publication: .deferred,
            observationOrigin: .windowKeyLoss
          )
        }
      } else if let window {
        cancelAndRestore(
          in: window,
          publication: .deferred,
          observationOrigin: .windowKeyLoss
        )
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

    private func updateCursor(for event: NSEvent, in window: NSWindow) {
      if let attachmentID, controller.isOwned(by: attachmentID),
        let handle = controller.currentHandle,
        let fixedSide = controller.currentFixedSide
      {
        setCursor(cursor(for: handle, fixedSide: fixedSide))
        return
      }
      guard isLiveResizeEligible(in: window),
        let statusLabelFrame = geometryStore?.cachedStatusButton?.screenFrame,
        let fixedSide = MenuPanelResizeGeometry.anchoredSide(
          panelFrame: window.frame,
          statusLabelFrame: statusLabelFrame
        ),
        let handle = MenuPanelResizeGeometry.handle(
          at: convert(event.locationInWindow, from: nil),
          in: bounds,
          fixedSide: fixedSide
        )
      else {
        resetCursor()
        return
      }
      setCursor(cursor(for: handle, fixedSide: fixedSide))
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
      let observation: (any MenuPanelResizeObservationSink)?
      if let sink = observationSink, sink.isRecording {
        observation = sink
      } else {
        observation = nil
      }
      let reconcileToken = observation?.scheduleReconcile(
        revision: revision,
        installationRevision: installation
      )
      DispatchQueue.main.async { [weak self, weak observation] in
        guard let self else {
          if let observation, let reconcileToken {
            observation.finishReconcile(reconcileToken, completed: false)
          }
          return
        }
        guard self.installationRevision == installation,
          self.queuedRevision == revision
        else {
          if let observation, let reconcileToken {
            observation.finishReconcile(reconcileToken, completed: false)
          }
          return
        }
        self.queuedRevision = nil
        self.reconcilePresentation(publication: .deferred, preparesHiddenWindow: false)
        if let attachmentID = self.attachmentID {
          _ = self.controller.publishPresentationContentSize(ownerID: attachmentID)
        } else {
          _ = self.controller.publishPresentationContentSize()
        }
        if let observation, let reconcileToken {
          observation.finishReconcile(reconcileToken, completed: true)
        }
      }
    }

    private func reconcilePresentation(
      publication: MenuPanelResizePublicationTiming,
      preparesHiddenWindow: Bool
    ) {
      guard let window = installedWindow, let attachmentID else {
        if pendingExternalPreference, controller.isUnownedTracking {
          controller.cancelSnapshot(
            publication: publication,
            observationOrigin: .visibilityReconcile
          )
        }
        pendingExternalPreference = false
        return
      }
      guard controller.isPresentationOwner(attachmentID) else { return }
      if !isLiveResizeEligible(in: window) || !window.isVisible {
        if controller.isOwned(by: attachmentID) {
          cancelAndRestore(
            in: window,
            publication: publication,
            observationOrigin: .visibilityReconcile
          )
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
          cancelAndRestore(
            in: window,
            publication: publication,
            observationOrigin: .geometryReconcile
          )
        }
        return
      }
      let isVisible = isPresented && window.isVisible
      if !isVisible && !preparesHiddenWindow {
        if ownsTracking {
          cancelAndRestore(
            in: window,
            publication: publication,
            observationOrigin: .visibilityReconcile
          )
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
            cancelAndRestore(
              in: window,
              publication: publication,
              observationOrigin: .geometryReconcile
            )
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
        let statusButton = geometryStore?.resolveStatusButton()
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
    }

    private func restore(
      snapshot: MenuPanelResizeSnapshot,
      in window: NSWindow,
      ownerID: UUID,
      publication: MenuPanelResizePublicationTiming = .immediate
    ) {
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
        applyFrame(placement.frame, to: window)
      } else {
        applyOwnedContainedFallback(
          frame: snapshot.initialFrame,
          to: window,
          ownerID: ownerID,
          publication: publication
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
      publication: MenuPanelResizePublicationTiming
    ) -> Bool {
      guard controller.isPresentationOwner(ownerID),
        let visibleFrame = fallbackVisibleFrameProvider(window),
        let containedFrame = MenuPanelResizeGeometry.containedFrame(
          frame: frame,
          visibleFrame: visibleFrame
        )
      else { return false }

      let contentSize = window.contentRect(forFrameRect: containedFrame).size
      guard contentSize.width.isFinite, contentSize.height.isFinite,
        contentSize.width > 0, contentSize.height > 0,
        applyFrame(containedFrame, to: window),
        controller.isPresentationOwner(ownerID)
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

    private func backingAlignedProposal(
      _ proposal: MenuPanelResizeProposal,
      in window: NSWindow,
      on screen: NSScreen,
      statusLabelFrame: CGRect,
      observationTicket: MenuPanelResizeObservationTicket?,
      observationIdentity: MenuPanelResizeObservationIdentity?,
      controllerOwnerID: UUID
    ) -> MenuPanelResizeProposal? {
      let frame = screen.backingAlignedRect(proposal.frame, options: .alignAllEdgesOutward)
      let contentSize = window.contentRect(forFrameRect: frame).size
      let isLegalPreference = contentSize.width >= MenuPanelResizeGeometry.minimumContentSize.width
        && contentSize.height >= MenuPanelResizeGeometry.minimumContentSize.height
      let hasFixedEdge = switch proposal.fixedSide {
      case .left: frame.minX == statusLabelFrame.minX
      case .right: frame.maxX == statusLabelFrame.maxX
      }
      guard frame.maxY == proposal.frame.maxY else {
        controller.recordDecision(
          .backing,
          ticket: observationTicket,
          accepted: false,
          rejection: .backingFrame,
          observationIdentity: observationIdentity,
          controllerOwnerID: controllerOwnerID
        )
        return nil
      }
      guard hasFixedEdge else {
        controller.recordDecision(
          .backing,
          ticket: observationTicket,
          accepted: false,
          rejection: .backingAnchor,
          observationIdentity: observationIdentity,
          controllerOwnerID: controllerOwnerID
        )
        return nil
      }
      guard MenuPanelResizeGeometry.containedFrame(
        frame: frame,
        visibleFrame: screen.visibleFrame
      ) == frame else {
        controller.recordDecision(
          .backing,
          ticket: observationTicket,
          accepted: false,
          rejection: .backingContainment,
          observationIdentity: observationIdentity,
          controllerOwnerID: controllerOwnerID
        )
        return nil
      }
      guard contentSize.width.isFinite, contentSize.height.isFinite,
        contentSize.width > 0, contentSize.height > 0
      else {
        controller.recordDecision(
          .backing,
          ticket: observationTicket,
          accepted: false,
          rejection: .backingContent,
          observationIdentity: observationIdentity,
          controllerOwnerID: controllerOwnerID
        )
        return nil
      }
      guard !proposal.isLegalPreference || isLegalPreference else {
        controller.recordDecision(
          .backing,
          ticket: observationTicket,
          accepted: false,
          rejection: .backingPreference,
          observationIdentity: observationIdentity,
          controllerOwnerID: controllerOwnerID
        )
        return nil
      }
      let alignedProposal = MenuPanelResizeProposal(
        contentSize: contentSize,
        frame: frame,
        isLegalPreference: isLegalPreference,
        fixedSide: proposal.fixedSide
      )
      controller.recordDecision(
        .backing,
        ticket: observationTicket,
        accepted: true,
        rejection: .none,
        observationIdentity: observationIdentity,
        controllerOwnerID: controllerOwnerID
      )
      return alignedProposal
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
      return window.frame == frame
    }

    private func clearAlignment() {
      alignedStatusButtonSource = nil
      alignedStatusButtonFrame = nil
      alignedVisibleFrame = nil
      alignedFixedSide = nil
      alignedFrame = nil
    }

    private func updateCursorForCurrentPointer(in window: NSWindow) {
      guard let event = NSApp.currentEvent else {
        resetCursor()
        return
      }
      updateCursor(for: event, in: window)
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

    private func diagonalCursor(systemSymbolName: String) -> NSCursor {
      guard let image = NSImage(
        systemSymbolName: systemSymbolName,
        accessibilityDescription: nil
      ) else { return .crosshair }
      return NSCursor(
        image: image,
        hotSpot: NSPoint(x: image.size.width / 2, y: image.size.height / 2)
      )
    }

    private func setCursor(_ cursor: NSCursor) {
      guard self.cursor !== cursor else { return }
      self.cursor = cursor
      cursor.set()
    }

    private func resetCursor() {
      guard cursor != nil else { return }
      cursor = nil
      NSCursor.arrow.set()
    }
  }
#endif
