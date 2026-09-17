import AppKit
import Combine
import FleckCore
import SwiftUI
import Testing

@testable import FleckApp

@Test func menuPanelAnchorUsesNearestIconSideAndBreaksTiesToTheRight() {
  let panel = CGRect(x: 100, y: 100, width: 600, height: 430)

  #expect(
    MenuPanelResizeGeometry.fixedSide(
      panelFrame: panel,
      statusLabelFrame: CGRect(x: 80, y: 700, width: 20, height: 20)
    ) == .left
  )
  #expect(
    MenuPanelResizeGeometry.fixedSide(
      panelFrame: panel,
      statusLabelFrame: CGRect(x: 700, y: 700, width: 20, height: 20)
    ) == .right
  )
  #expect(
    MenuPanelResizeGeometry.fixedSide(
      panelFrame: panel,
      statusLabelFrame: CGRect(x: 390, y: 700, width: 20, height: 20)
    ) == .right
  )
  #expect(MenuPanelResizeGeometry.fixedSide(panelFrame: panel, statusLabelFrame: .zero) == nil)
}

@Test func menuPanelAlignmentGeometryPinsTheActualButtonBorderFromInheritedOffsets() throws {
  let screen = CGRect(x: -1_440, y: 23, width: 1_440, height: 877)
  let button = CGRect(x: -720, y: 878, width: 32, height: 22)
  let insets = MenuPanelFrameInsets(top: 12, left: 6, bottom: 8, right: 6)
  let inherited = CGRect(x: -1_050, y: 310, width: 612, height: 452)

  let left = try #require(
    MenuPanelResizeGeometry.presentation(
      contentSize: CGSize(width: 600, height: 430),
      inheritedFrame: inherited,
      frameInsets: insets,
      visibleFrame: screen,
      statusLabelFrame: button,
      preferredSide: .left
    )
  )
  #expect(left.fixedSide == .left)
  #expect(left.frame.minX == button.minX)
  #expect(left.frame.maxY == inherited.maxY)
  #expect(left.contentSize == CGSize(width: 600, height: 430))

  let right = try #require(
    MenuPanelResizeGeometry.presentation(
      contentSize: CGSize(width: 600, height: 430),
      inheritedFrame: inherited,
      frameInsets: insets,
      visibleFrame: screen,
      statusLabelFrame: button,
      preferredSide: .right
    )
  )
  #expect(right.fixedSide == .right)
  #expect(right.frame.maxX == button.maxX)
  #expect(right.frame.maxY == inherited.maxY)
  #expect(right.contentSize == CGSize(width: 600, height: 430))

  let constrained = try #require(
    MenuPanelResizeGeometry.presentation(
      contentSize: CGSize(width: 800, height: 430),
      inheritedFrame: CGRect(x: 100, y: 100, width: 800, height: 430),
      frameInsets: .zero,
      visibleFrame: CGRect(x: 0, y: 0, width: 700, height: 900),
      statusLabelFrame: CGRect(x: 500, y: 880, width: 34, height: 22),
      preferredSide: .left
    )
  )
  #expect(constrained.fixedSide == .right)
  #expect(constrained.contentSize.width == 534)
  #expect(constrained.frame.maxX == 534)
}

@Test func menuPanelPresentationPreservesLargePreferencesWithinEitherUsableSide() throws {
  let visibleFrame = CGRect(x: -2_000, y: -500, width: 3_000, height: 1_600)
  let statusLabelFrame = CGRect(x: -500, y: 1_080, width: 40, height: 22)
  let insets = MenuPanelFrameInsets(top: 12, left: 6, bottom: 8, right: 10)
  let inheritedFrame = CGRect(x: -1_000, y: 180, width: 1_216, height: 920)
  let preferredSize = CGSize(width: 1_200, height: 900)

  for side in [MenuPanelFixedSide.left, .right] {
    let proposal = try #require(
      MenuPanelResizeGeometry.presentation(
        contentSize: preferredSize,
        inheritedFrame: inheritedFrame,
        frameInsets: insets,
        visibleFrame: visibleFrame,
        statusLabelFrame: statusLabelFrame,
        preferredSide: side
      )
    )
    #expect(proposal.contentSize == preferredSize)
    #expect(proposal.frame.maxY == inheritedFrame.maxY)
    #expect(proposal.frame.size == CGSize(width: 1_216, height: 920))
    #expect(proposal.isLegalPreference)
    #expect(MenuPanelResizeGeometry.containedFrame(
      frame: proposal.frame,
      visibleFrame: visibleFrame
    ) == proposal.frame)
    switch side {
    case .left:
      #expect(proposal.frame.minX == statusLabelFrame.minX)
    case .right:
      #expect(proposal.frame.maxX == statusLabelFrame.maxX)
    }
  }
}

@Test func menuPanelLargeFractionalProposalsAndReleasesUseScreenBoundsForEveryHandle() throws {
  let visibleFrame = CGRect(x: -2_000, y: -500, width: 4_000, height: 2_000)
  let insets = MenuPanelFrameInsets(top: 12, left: 6, bottom: 8, right: 10)
  let initialContentSize = CGSize(width: 900.25, height: 820.5)
  let frameSize = CGSize(width: 916.25, height: 840.5)
  let fixedTop: CGFloat = 1_200.5

  for side in [MenuPanelFixedSide.left, .right] {
    let button = side == .left
      ? CGRect(x: -500, y: 1_450, width: 40, height: 22)
      : CGRect(x: 500, y: 1_450, width: 40, height: 22)
    let frame = CGRect(
      x: side == .left ? button.minX : button.maxX - frameSize.width,
      y: fixedTop - frameSize.height,
      width: frameSize.width,
      height: frameSize.height
    )

    for handle in [
      MenuPanelResizeHandle.farSide,
      .farBottomCorner,
      .nearBottomCorner,
    ] {
      let changesWidth = handle != .nearBottomCorner
      let changesHeight = handle != .farSide
      let initialPointer = CGPoint(
        x: handle == .nearBottomCorner
          ? (side == .left ? frame.minX + 0.625 : frame.maxX - 0.625)
          : (side == .left ? frame.maxX - 0.625 : frame.minX + 0.625),
        y: changesHeight ? frame.minY + 0.625 : frame.minY + 200.625
      )
      let snapshot = MenuPanelResizeSnapshot(
        initialPointer: initialPointer,
        initialFrame: frame,
        initialContentSize: initialContentSize,
        frameInsets: insets,
        visibleFrame: visibleFrame,
        statusLabelFrame: button,
        fixedSide: side
      )
      let pointer = CGPoint(
        x: initialPointer.x + (changesWidth ? (side == .left ? 180.375 : -180.375) : 0),
        y: initialPointer.y - (changesHeight ? 90.375 : 0)
      )
      let expectedSize = CGSize(
        width: initialContentSize.width + (changesWidth ? 180.375 : 0),
        height: initialContentSize.height + (changesHeight ? 90.375 : 0)
      )

      let proposal = try #require(
        MenuPanelResizeGeometry.proposal(
          snapshot: snapshot,
          pointer: pointer,
          handle: handle,
          currentSide: side
        )
      )
      let release = try #require(
        MenuPanelResizeGeometry.releaseProposal(
          snapshot: snapshot,
          pointer: pointer,
          handle: handle,
          currentSide: side
        )
      )

      for result in [proposal, release] {
        #expect(result.contentSize == expectedSize)
        #expect(result.contentSize.width > 800)
        #expect(result.contentSize.height > 800)
        #expect(result.frame.maxY == fixedTop)
        #expect(result.isLegalPreference)
        #expect(MenuPanelResizeGeometry.containedFrame(
          frame: result.frame,
          visibleFrame: visibleFrame
        ) == result.frame)
        switch side {
        case .left:
          #expect(result.frame.minX == button.minX)
        case .right:
          #expect(result.frame.maxX == button.maxX)
        }
      }
    }
  }
}

@Test func menuPanelLargeOvershootsStopAtUsableSideAndBottomBounds() throws {
  let visibleFrame = CGRect(x: -2_000, y: -500, width: 4_000, height: 2_000)
  let insets = MenuPanelFrameInsets(top: 12, left: 6, bottom: 8, right: 10)
  let initialContentSize = CGSize(width: 900, height: 820)
  let frameSize = CGSize(width: 916, height: 840)
  let fixedTop: CGFloat = 1_400
  let expectedContentSize = CGSize(width: 3_484, height: 1_880)

  for side in [MenuPanelFixedSide.left, .right] {
    let button = side == .left
      ? CGRect(x: -1_500, y: 1_450, width: 40, height: 22)
      : CGRect(x: 1_460, y: 1_450, width: 40, height: 22)
    let frame = CGRect(
      x: side == .left ? button.minX : button.maxX - frameSize.width,
      y: fixedTop - frameSize.height,
      width: frameSize.width,
      height: frameSize.height
    )
    let snapshot = MenuPanelResizeSnapshot(
      initialPointer: CGPoint(
        x: side == .left ? frame.maxX - 0.625 : frame.minX + 0.625,
        y: frame.minY + 0.625
      ),
      initialFrame: frame,
      initialContentSize: initialContentSize,
      frameInsets: insets,
      visibleFrame: visibleFrame,
      statusLabelFrame: button,
      fixedSide: side
    )
    let overshoot = CGPoint(
      x: side == .left ? visibleFrame.maxX + 1_000 : visibleFrame.minX - 1_000,
      y: visibleFrame.minY - 1_000
    )
    let transient = try #require(
      MenuPanelResizeGeometry.proposal(
        snapshot: snapshot,
        pointer: overshoot,
        handle: .farBottomCorner,
        currentSide: side
      )
    )
    let release = try #require(
      MenuPanelResizeGeometry.releaseProposal(
        snapshot: snapshot,
        pointer: overshoot,
        handle: .farBottomCorner,
        currentSide: side
      )
    )

    for result in [transient, release] {
      #expect(result.contentSize == expectedContentSize)
      #expect(result.contentSize.width > 800)
      #expect(result.contentSize.height > 800)
      #expect(result.frame.minY == visibleFrame.minY)
      #expect(result.frame.maxY == fixedTop)
      #expect(result.isLegalPreference)
      switch side {
      case .left:
        #expect(result.frame.minX == button.minX)
        #expect(result.frame.maxX == visibleFrame.maxX)
      case .right:
        #expect(result.frame.minX == visibleFrame.minX)
        #expect(result.frame.maxX == button.maxX)
      }
    }
  }
}

@Test func menuPanelSettingsRangesRetainLargeStoredValuesWithoutFixedCaps() {
  #expect(
    MenuPanelSettingsSizePolicy.range(
      minimum: 380,
      storedValue: 1_240.5,
      usableDisplayDimensions: [900, 1_100]
    ) == 380...1_240.5
  )
  #expect(
    MenuPanelSettingsSizePolicy.range(
      minimum: 300,
      storedValue: 920.25,
      usableDisplayDimensions: [1_080, 800]
    ) == 300...1_080
  )
  #expect(
    MenuPanelSettingsSizePolicy.range(
      minimum: 380,
      storedValue: 600,
      usableDisplayDimensions: [.nan, .infinity, -1]
    ) == 380...600
  )
  #expect(MenuPanelSettingsSizePolicy.label(for: 1_240.5).hasSuffix(" pt"))
  #expect(MenuPanelSettingsSizePolicy.label(for: .greatestFiniteMagnitude).hasSuffix(" pt"))
}

@Test func menuPanelSmallScreenPresentationLeavesTheLargeStoredPreferenceUntouched() {
  let storedPreference = CGSize(width: 1_240.5, height: 920.25)
  let presentedSize = NotesPanelSizing.storedSize(
    preferred: storedPreference,
    available: CGSize(width: 700, height: 600)
  )

  #expect(presentedSize == CGSize(width: 700, height: 600))
  #expect(storedPreference == CGSize(width: 1_240.5, height: 920.25))
}

@Test func menuPanelAlignmentGeometryContainsFramesAcrossScreenChanges() throws {
  let visibleFrame = CGRect(x: -1_000, y: -200, width: 800, height: 600)

  let outside = try #require(
    MenuPanelResizeGeometry.containedFrame(
      frame: CGRect(x: 500, y: 700, width: 600, height: 500),
      visibleFrame: visibleFrame
    )
  )
  #expect(outside == CGRect(x: -800, y: -100, width: 600, height: 500))

  let oversized = try #require(
    MenuPanelResizeGeometry.containedFrame(
      frame: CGRect(x: -1_500, y: -500, width: 1_200, height: 900),
      visibleFrame: visibleFrame
    )
  )
  #expect(oversized == visibleFrame)
}

@Test func menuPanelAlignmentGeometryContainedFramePreservesAndClampsTop() throws {
  let visibleFrame = CGRect(x: -400, y: -100, width: 900, height: 700)

  let preserved = try #require(
    MenuPanelResizeGeometry.containedFrame(
      frame: CGRect(x: -200, y: 150, width: 500, height: 300),
      visibleFrame: visibleFrame
    )
  )
  #expect(preserved == CGRect(x: -200, y: 150, width: 500, height: 300))

  let clampedBelow = try #require(
    MenuPanelResizeGeometry.containedFrame(
      frame: CGRect(x: -200, y: -500, width: 500, height: 300),
      visibleFrame: visibleFrame
    )
  )
  #expect(clampedBelow == CGRect(x: -200, y: -100, width: 500, height: 300))

  let clampedAbove = try #require(
    MenuPanelResizeGeometry.containedFrame(
      frame: CGRect(x: -200, y: 500, width: 500, height: 300),
      visibleFrame: visibleFrame
    )
  )
  #expect(clampedAbove == CGRect(x: -200, y: 300, width: 500, height: 300))
}

@Test func menuPanelAlignmentGeometryContainedFrameRejectsInvalidGeometry() {
  let valid = CGRect(x: 0, y: 0, width: 800, height: 600)
  #expect(MenuPanelResizeGeometry.containedFrame(frame: .null, visibleFrame: valid) == nil)
  #expect(MenuPanelResizeGeometry.containedFrame(frame: .infinite, visibleFrame: valid) == nil)
  #expect(
    MenuPanelResizeGeometry.containedFrame(
      frame: CGRect(x: CGFloat.nan, y: 0, width: 500, height: 400),
      visibleFrame: valid
    ) == nil
  )
  #expect(
    MenuPanelResizeGeometry.containedFrame(
      frame: CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 400),
      visibleFrame: valid
    ) == nil
  )
  #expect(
    MenuPanelResizeGeometry.containedFrame(
      frame: CGRect(x: 0, y: 0, width: 500, height: 400),
      visibleFrame: CGRect(x: 0, y: 0, width: 0, height: 600)
    ) == nil
  )
  #expect(
    MenuPanelResizeGeometry.containedFrame(
      frame: CGRect(x: 0, y: 0, width: 500, height: 400),
      visibleFrame: CGRect(x: 0, y: -CGFloat.infinity, width: 800, height: 600)
    ) == nil
  )
}

@Test func menuPanelFlipGeometryTapersTheGrabAndSwitchesWithoutTranslation() throws {
  var snapshot = try #require(resizeSnapshot(fixedSide: .left))
  snapshot.statusLabelFrame = CGRect(x: 580, y: 880, width: 40, height: 20)
  snapshot.initialFrame = CGRect(x: 580, y: 100, width: 600, height: 430)
  snapshot.initialPointer = CGPoint(x: 1_174, y: 100)
  let midpoint = snapshot.statusLabelFrame.midX
  let hysteresis = min(4, snapshot.statusLabelFrame.width / 4)

  let unchanged = try #require(
    MenuPanelResizeGeometry.proposal(
      snapshot: snapshot,
      pointer: snapshot.initialPointer,
      handle: .farSide,
      currentSide: .left
    )
  )
  #expect(unchanged.contentSize.width == snapshot.initialContentSize.width)
  #expect(unchanged.frame == snapshot.initialFrame)

  var rightSnapshot = snapshot
  rightSnapshot.fixedSide = .right
  rightSnapshot.initialFrame = CGRect(x: 20, y: 100, width: 600, height: 430)
  rightSnapshot.initialPointer = CGPoint(x: 26, y: 100)
  let unchangedRight = try #require(
    MenuPanelResizeGeometry.proposal(
      snapshot: rightSnapshot,
      pointer: rightSnapshot.initialPointer,
      handle: .farSide,
      currentSide: .right
    )
  )
  #expect(unchangedRight.frame == rightSnapshot.initialFrame)

  let leftEquality = try #require(
    MenuPanelResizeGeometry.proposal(
      snapshot: snapshot,
      pointer: CGPoint(x: midpoint - hysteresis, y: 100),
      handle: .farSide,
      currentSide: .left
    )
  )
  #expect(leftEquality.fixedSide == .left)
  #expect(leftEquality.frame.minX == snapshot.statusLabelFrame.minX)
  #expect(leftEquality.frame.maxX == snapshot.statusLabelFrame.maxX)
  #expect(leftEquality.frame.minY == snapshot.initialFrame.minY)
  #expect(leftEquality.frame.height == snapshot.initialFrame.height)

  let leftRetained = try #require(
    MenuPanelResizeGeometry.proposal(
      snapshot: snapshot,
      pointer: CGPoint(x: midpoint - hysteresis + 1, y: 100),
      handle: .farSide,
      currentSide: .left
    )
  )
  #expect(leftRetained.fixedSide == .left)

  let switchedRight = try #require(
    MenuPanelResizeGeometry.proposal(
      snapshot: snapshot,
      pointer: CGPoint(x: midpoint - hysteresis - 1, y: 100),
      handle: .farSide,
      currentSide: .left
    )
  )
  #expect(switchedRight.fixedSide == .right)
  #expect(switchedRight.frame.minX == snapshot.statusLabelFrame.minX)
  #expect(switchedRight.frame.maxX == snapshot.statusLabelFrame.maxX)
  #expect(switchedRight.frame.minY == snapshot.initialFrame.minY)
  #expect(switchedRight.frame.height == snapshot.initialFrame.height)

  let rightEquality = try #require(
    MenuPanelResizeGeometry.proposal(
      snapshot: snapshot,
      pointer: CGPoint(x: midpoint + hysteresis, y: 100),
      handle: .farSide,
      currentSide: .right
    )
  )
  #expect(rightEquality.fixedSide == .right)
  #expect(rightEquality.frame.minX == snapshot.statusLabelFrame.minX)
  #expect(rightEquality.frame.maxX == snapshot.statusLabelFrame.maxX)
  #expect(rightEquality.frame.minY == snapshot.initialFrame.minY)
  #expect(rightEquality.frame.height == snapshot.initialFrame.height)

  let rightRetained = try #require(
    MenuPanelResizeGeometry.proposal(
      snapshot: snapshot,
      pointer: CGPoint(x: midpoint + hysteresis - 1, y: 100),
      handle: .farSide,
      currentSide: .right
    )
  )
  #expect(rightRetained.fixedSide == .right)

  let switchedLeft = try #require(
    MenuPanelResizeGeometry.proposal(
      snapshot: snapshot,
      pointer: CGPoint(x: midpoint + hysteresis + 1, y: 100),
      handle: .farSide,
      currentSide: .right
    )
  )
  #expect(switchedLeft.fixedSide == .left)
  #expect(switchedLeft.frame.minX == snapshot.statusLabelFrame.minX)
  #expect(switchedLeft.frame.maxX == snapshot.statusLabelFrame.maxX)
  #expect(switchedLeft.frame.minY == snapshot.initialFrame.minY)
  #expect(switchedLeft.frame.height == snapshot.initialFrame.height)

  var previousWidth: CGFloat?
  for x in stride(from: CGFloat(560), through: 640, by: 0.25) {
    let proposal = try #require(
      MenuPanelResizeGeometry.proposal(
        snapshot: snapshot,
        pointer: CGPoint(x: x, y: 100),
        handle: .farSide,
        currentSide: x < midpoint ? .right : .left
      )
    )
    if let previousWidth {
      #expect(abs(proposal.frame.width - previousWidth) <= 0.5)
    }
    previousWidth = proposal.frame.width
    #expect(proposal.frame.minX >= snapshot.visibleFrame.minX)
    #expect(proposal.frame.maxX <= snapshot.visibleFrame.maxX)
  }
}

@Test @MainActor func menuPanelFlipControllerReversesWithinOneGestureAndRestoresOnCancel() throws {
  var snapshot = try #require(resizeSnapshot(fixedSide: .left))
  snapshot.statusLabelFrame = CGRect(x: 580, y: 880, width: 40, height: 20)
  snapshot.initialFrame = CGRect(x: 580, y: 100, width: 600, height: 430)
  snapshot.initialPointer = CGPoint(x: 1_174, y: 100)
  let controller = MenuPanelResizeController()

  #expect(controller.begin(snapshot: snapshot, handle: .farBottomCorner))
  let right = try #require(
    controller.update(
      pointer: CGPoint(x: 590, y: 70),
      statusLabelFrame: snapshot.statusLabelFrame,
      visibleFrame: snapshot.visibleFrame
    )
  )
  #expect(right.fixedSide == .right)
  #expect(right.frame.maxY == snapshot.initialFrame.maxY)
  #expect(right.contentSize.height == 460)

  let left = try #require(
    controller.update(
      pointer: CGPoint(x: 610, y: 60),
      statusLabelFrame: snapshot.statusLabelFrame,
      visibleFrame: snapshot.visibleFrame
    )
  )
  #expect(left.fixedSide == .left)
  #expect(left.frame.maxY == snapshot.initialFrame.maxY)
  #expect(left.contentSize.height == 470)

  let rightAgain = try #require(
    controller.update(
      pointer: CGPoint(x: 590, y: 50),
      statusLabelFrame: snapshot.statusLabelFrame,
      visibleFrame: snapshot.visibleFrame
    )
  )
  #expect(rightAgain.fixedSide == .right)
  #expect(controller.currentFixedSide == .right)
  #expect(controller.cancel() == snapshot.initialFrame)
  #expect(controller.effectiveContentSize == nil)
}

@Test func menuPanelFlipGeometryNearCornerNeverFlipsAndFarCornerKeepsTop() throws {
  var snapshot = try #require(resizeSnapshot(fixedSide: .left))
  snapshot.statusLabelFrame = CGRect(x: 580, y: 880, width: 40, height: 20)
  snapshot.initialFrame = CGRect(x: 580, y: 100, width: 600, height: 430)
  snapshot.initialPointer = CGPoint(x: 580, y: 100)

  let near = try #require(
    MenuPanelResizeGeometry.proposal(
      snapshot: snapshot,
      pointer: CGPoint(x: -1_000, y: 40),
      handle: .nearBottomCorner,
      currentSide: .left
    )
  )
  #expect(near.fixedSide == .left)
  #expect(near.contentSize == CGSize(width: 600, height: 490))
  #expect(near.frame.minX == snapshot.statusLabelFrame.minX)
  #expect(near.frame.maxY == snapshot.initialFrame.maxY)

  snapshot.initialPointer = CGPoint(x: 1_174, y: 100)
  let far = try #require(
    MenuPanelResizeGeometry.proposal(
      snapshot: snapshot,
      pointer: CGPoint(x: 590, y: 40),
      handle: .farBottomCorner,
      currentSide: .left
    )
  )
  #expect(far.fixedSide == .right)
  #expect(far.contentSize.height == 490)
  #expect(far.frame.maxY == snapshot.initialFrame.maxY)
  #expect(far.frame.maxX == snapshot.statusLabelFrame.maxX)
}

@Test func menuPanelFlipGeometryHandlesInsetsCapsAndRejectedDestinations() throws {
  var snapshot = MenuPanelResizeSnapshot(
    initialPointer: CGPoint(x: 1_168, y: 100),
    initialFrame: CGRect(x: 580, y: 100, width: 600, height: 452),
    initialContentSize: CGSize(width: 588, height: 430),
    frameInsets: MenuPanelFrameInsets(top: 16, left: 6, bottom: 6, right: 6),
    visibleFrame: CGRect(x: 0, y: 0, width: 1_200, height: 900),
    statusLabelFrame: CGRect(x: 580, y: 880, width: 40, height: 20),
    fixedSide: .left
  )
  let band = try #require(
    MenuPanelResizeGeometry.proposal(
      snapshot: snapshot,
      pointer: CGPoint(x: 590, y: 100),
      handle: .farSide,
      currentSide: .left
    )
  )
  #expect(band.fixedSide == .right)
  #expect(band.frame.minX == snapshot.statusLabelFrame.minX)
  #expect(band.frame.maxX == snapshot.statusLabelFrame.maxX)
  #expect(band.contentSize.width == 28)

  snapshot.visibleFrame = CGRect(x: 570, y: 0, width: 630, height: 900)
  snapshot.statusLabelFrame = CGRect(x: 580, y: 880, width: 40, height: 20)
  let rejected = try #require(
    MenuPanelResizeGeometry.proposal(
      snapshot: snapshot,
      pointer: CGPoint(x: 590, y: 100),
      handle: .farSide,
      currentSide: .left
    )
  )
  #expect(rejected.fixedSide == .left)
  #expect(rejected.frame.minX == snapshot.statusLabelFrame.minX)
  #expect(rejected.frame.maxX == snapshot.statusLabelFrame.maxX)

  snapshot.frameInsets = MenuPanelFrameInsets(top: 16, left: 20, bottom: 6, right: 20)
  #expect(
    MenuPanelResizeGeometry.proposal(
      snapshot: snapshot,
      pointer: CGPoint(x: 800, y: 100),
      handle: .farSide,
      currentSide: .left
    ) == nil
  )
}

@Test @MainActor func menuPanelFlipControllerReleasesAtMinimumAndRemembersUnchangedSizeSide() throws {
  var snapshot = MenuPanelResizeSnapshot(
    initialPointer: CGPoint(x: 954, y: 100),
    initialFrame: CGRect(x: 580, y: 100, width: 380, height: 430),
    initialContentSize: CGSize(width: 380, height: 430),
    frameInsets: .zero,
    visibleFrame: CGRect(x: 0, y: 0, width: 1_200, height: 900),
    statusLabelFrame: CGRect(x: 580, y: 880, width: 40, height: 20),
    fixedSide: .left
  )
  let controller = MenuPanelResizeController()
  #expect(controller.begin(snapshot: snapshot, handle: .farSide))
  let transient = try #require(
    controller.update(
      pointer: CGPoint(x: 590, y: 100),
      statusLabelFrame: snapshot.statusLabelFrame,
      visibleFrame: snapshot.visibleFrame
    )
  )
  #expect(transient.contentSize.width == 40)
  #expect(transient.fixedSide == .right)
  let final = try #require(
    controller.finish(
      statusLabelFrame: snapshot.statusLabelFrame,
      visibleFrame: snapshot.visibleFrame,
      currentFrame: transient.frame
    )
  )
  #expect(final.contentSize == snapshot.initialContentSize)
  #expect(final.fixedSide == .right)
  #expect(final.frame.maxX == snapshot.statusLabelFrame.maxX)
  #expect(final.frame.width == 380)
  #expect(controller.completedPreferenceSize == snapshot.initialContentSize)
  let geometryStore = MenuPanelGeometryStore(windows: { [] })
  geometryStore.rememberCompletedSide(final.fixedSide)
  #expect(geometryStore.rememberedFixedSide == .right)

  controller.clearCompletion()
  snapshot.initialFrame = final.frame
  snapshot.initialPointer = CGPoint(x: final.frame.minX + 6, y: 100)
  snapshot.fixedSide = .right
  #expect(controller.begin(snapshot: snapshot, handle: .farSide))
  let belowMinimum = try #require(
    controller.update(
      pointer: CGPoint(x: 610, y: 100),
      statusLabelFrame: snapshot.statusLabelFrame,
      visibleFrame: snapshot.visibleFrame
    )
  )
  #expect(belowMinimum.contentSize.width == 40)
  let returnedLeft = try #require(
    controller.finish(
      statusLabelFrame: snapshot.statusLabelFrame,
      visibleFrame: snapshot.visibleFrame,
      currentFrame: belowMinimum.frame
    )
  )
  #expect(returnedLeft.fixedSide == .left)
  #expect(returnedLeft.contentSize.width == 380)
  #expect(returnedLeft.frame.minX == snapshot.statusLabelFrame.minX)
}

@Test @MainActor func menuPanelFlipControllerCancelsAfterMultipleFlipsAndGeometryInvalidation() throws {
  var snapshot = try #require(resizeSnapshot(fixedSide: .left))
  snapshot.statusLabelFrame = CGRect(x: 580, y: 880, width: 40, height: 20)
  snapshot.initialFrame = CGRect(x: 580, y: 100, width: 600, height: 430)
  snapshot.initialPointer = CGPoint(x: 1_174, y: 100)
  let controller = MenuPanelResizeController()

  #expect(controller.begin(snapshot: snapshot, handle: .farSide))
  #expect(
    controller.update(
      pointer: CGPoint(x: 590, y: 100),
      statusLabelFrame: snapshot.statusLabelFrame,
      visibleFrame: snapshot.visibleFrame
    )?.fixedSide == .right
  )
  #expect(
    controller.update(
      pointer: CGPoint(x: 610, y: 100),
      statusLabelFrame: snapshot.statusLabelFrame,
      visibleFrame: snapshot.visibleFrame
    )?.fixedSide == .left
  )
  controller.cancelIfGeometryChanged(
    statusLabelFrame: snapshot.statusLabelFrame,
    visibleFrame: snapshot.visibleFrame.offsetBy(dx: -1, dy: 0)
  )
  #expect(!controller.isTracking)
  #expect(controller.effectiveContentSize == nil)
  #expect(controller.completedPreferenceSize == nil)
}

@Test @MainActor func menuPanelFlipControllerRejectsCleanupFromAnotherHostOwner() throws {
  let snapshot = try #require(resizeSnapshot(fixedSide: .left))
  let controller = MenuPanelResizeController()
  let oldAttachment = UUID()
  let newAttachment = UUID()
  #expect(controller.claimPresentation(ownerID: oldAttachment))
  #expect(controller.begin(snapshot: snapshot, handle: .farSide, ownerID: oldAttachment))
  #expect(controller.cancelSnapshot(ownerID: UUID()) == nil)
  #expect(controller.isOwned(by: oldAttachment))
  #expect(
    controller.cancelSnapshot(ownerID: oldAttachment)?.initialFrame == snapshot.initialFrame
  )
  #expect(!controller.isTracking)

  #expect(controller.claimPresentation(ownerID: newAttachment))
  #expect(controller.begin(snapshot: snapshot, handle: .farSide, ownerID: newAttachment))
  #expect(controller.cancelSnapshot(ownerID: oldAttachment) == nil)
  #expect(controller.isOwned(by: newAttachment))
  _ = controller.cancelSnapshot(ownerID: newAttachment)

  #expect(
    controller.setPresentationContentSize(
      CGSize(width: 500, height: 430),
      ownerID: newAttachment
    )
  )
  #expect(!controller.setPresentationContentSize(nil, ownerID: oldAttachment))
  #expect(
    controller.presentationContentSize(ownerID: newAttachment)
      == CGSize(width: 500, height: 430)
  )
  #expect(controller.presentationContentSize(ownerID: oldAttachment) == nil)
}

@Test @MainActor func menuPanelFlipControllerPresentationOwnerSurvivesNilOverride() throws {
  let snapshot = try #require(resizeSnapshot(fixedSide: .left))
  let controller = MenuPanelResizeController()
  let oldAttachment = UUID()
  let newAttachment = UUID()

  #expect(controller.claimPresentation(ownerID: oldAttachment))
  #expect(controller.claimPresentation(ownerID: newAttachment))
  #expect(controller.setPresentationContentSize(nil, ownerID: newAttachment))
  #expect(
    !controller.setPresentationContentSize(
      CGSize(width: 500, height: 430),
      ownerID: oldAttachment
    )
  )
  #expect(!controller.begin(snapshot: snapshot, handle: .farSide, ownerID: oldAttachment))
  #expect(controller.begin(snapshot: snapshot, handle: .farSide, ownerID: newAttachment))
}

@Test @MainActor func menuPanelFlipControllerNewClaimCancelsAnOldActiveGesture() throws {
  let snapshot = try #require(resizeSnapshot(fixedSide: .left))
  let controller = MenuPanelResizeController()
  let oldAttachment = UUID()
  let newAttachment = UUID()

  #expect(controller.claimPresentation(ownerID: oldAttachment))
  #expect(controller.begin(snapshot: snapshot, handle: .farSide, ownerID: oldAttachment))
  _ = controller.update(
    pointer: CGPoint(x: 740, y: 100),
    statusLabelFrame: snapshot.statusLabelFrame,
    visibleFrame: snapshot.visibleFrame,
    ownerID: oldAttachment
  )
  #expect(controller.isTracking)
  #expect(controller.effectiveContentSize == CGSize(width: 640, height: 430))

  #expect(controller.claimPresentation(ownerID: newAttachment))
  #expect(!controller.isTracking)
  #expect(controller.effectiveContentSize == nil)
  #expect(controller.cancelSnapshot(ownerID: oldAttachment) == nil)
  #expect(controller.begin(snapshot: snapshot, handle: .farSide, ownerID: newAttachment))
}

@Test @MainActor func menuPanelFlipControllerStagesDesiredSizeUntilOwnerFlush() {
  let controller = MenuPanelResizeController()
  let attachment = UUID()
  #expect(controller.claimPresentation(ownerID: attachment, publication: .deferred))
  #expect(
    controller.setPresentationContentSize(
      CGSize(width: 500, height: 430),
      ownerID: attachment,
      publication: .deferred
    )
  )
  #expect(
    controller.setPresentationContentSize(
      CGSize(width: 520, height: 440),
      ownerID: attachment,
      publication: .deferred
    )
  )
  #expect(controller.presentationContentSize(ownerID: attachment) == CGSize(width: 520, height: 440))
  #expect(controller.effectiveContentSize == nil)
  #expect(controller.publishPresentationContentSize(ownerID: attachment))
  #expect(controller.effectiveContentSize == CGSize(width: 520, height: 440))
}

@Test @MainActor func menuPanelFlipControllerDefaultsToImmediateSizePublication() {
  let controller = MenuPanelResizeController()
  let attachment = UUID()
  #expect(controller.claimPresentation(ownerID: attachment))
  #expect(
    controller.setPresentationContentSize(
      CGSize(width: 500, height: 430),
      ownerID: attachment
    )
  )
  #expect(controller.presentationContentSize(ownerID: attachment) == CGSize(width: 500, height: 430))
  #expect(controller.effectiveContentSize == CGSize(width: 500, height: 430))
}

@Test @MainActor func menuPanelFlipControllerRejectsStaleOwnerDeferredFlush() {
  let controller = MenuPanelResizeController()
  let oldAttachment = UUID()
  let newAttachment = UUID()
  #expect(controller.claimPresentation(ownerID: oldAttachment, publication: .deferred))
  #expect(
    controller.setPresentationContentSize(
      CGSize(width: 500, height: 430),
      ownerID: oldAttachment,
      publication: .deferred
    )
  )
  #expect(controller.claimPresentation(ownerID: newAttachment, publication: .deferred))
  #expect(
    controller.setPresentationContentSize(
      CGSize(width: 540, height: 450),
      ownerID: newAttachment,
      publication: .deferred
    )
  )
  #expect(!controller.publishPresentationContentSize(ownerID: oldAttachment))
  #expect(controller.effectiveContentSize == nil)
  #expect(controller.publishPresentationContentSize(ownerID: newAttachment))
  #expect(controller.effectiveContentSize == CGSize(width: 540, height: 450))
}

@Test @MainActor func menuPanelFlipControllerRollsBackARejectedFinalAdoption() throws {
  let snapshot = try #require(resizeSnapshot(fixedSide: .right))
  let controller = MenuPanelResizeController()
  let attachment = UUID()
  #expect(controller.claimPresentation(ownerID: attachment))
  #expect(controller.begin(snapshot: snapshot, handle: .farSide, ownerID: attachment))
  let transient = try #require(
    controller.update(
      pointer: CGPoint(x: 60, y: 100),
      statusLabelFrame: snapshot.statusLabelFrame,
      visibleFrame: snapshot.visibleFrame,
      ownerID: attachment
    )
  )
  _ = try #require(
    controller.finish(
      statusLabelFrame: snapshot.statusLabelFrame,
      visibleFrame: snapshot.visibleFrame,
      currentFrame: transient.frame,
      ownerID: attachment
    )
  )
  #expect(
    controller.cancelCompletion(ownerID: attachment)?.initialFrame == snapshot.initialFrame
  )
  #expect(controller.completedPreferenceSize == nil)
  #expect(controller.effectiveContentSize == nil)
}

@Test func rightPinnedFarAndNearBottomCornersChangeOnlyApprovedAxes() throws {
  let snapshot = try #require(resizeSnapshot(fixedSide: .right))

  let far = try #require(
    MenuPanelResizeGeometry.proposal(
      snapshot: snapshot,
      pointer: CGPoint(x: 60, y: 70),
      handle: .farBottomCorner
    )
  )
  #expect(far.contentSize == CGSize(width: 640, height: 460))
  #expect(far.frame == CGRect(x: 60, y: 70, width: 640, height: 460))

  let near = try #require(
    MenuPanelResizeGeometry.proposal(
      snapshot: snapshot,
      pointer: CGPoint(x: 660, y: 70),
      handle: .nearBottomCorner
    )
  )
  #expect(near.contentSize == CGSize(width: 600, height: 460))
  #expect(near.frame == CGRect(x: 100, y: 70, width: 600, height: 460))
}

@Test func mirroredLeftPinnedHandlesKeepTopAndIconSideFixed() throws {
  let snapshot = try #require(resizeSnapshot(fixedSide: .left))

  let side = try #require(
    MenuPanelResizeGeometry.proposal(
      snapshot: snapshot,
      pointer: CGPoint(x: 740, y: 300),
      handle: .farSide
    )
  )
  #expect(side.contentSize == CGSize(width: 640, height: 430))
  #expect(side.frame == CGRect(x: 100, y: 100, width: 640, height: 430))

  let far = try #require(
    MenuPanelResizeGeometry.proposal(
      snapshot: snapshot,
      pointer: CGPoint(x: 740, y: 70),
      handle: .farBottomCorner
    )
  )
  #expect(far.contentSize == CGSize(width: 640, height: 460))
  #expect(far.frame.minX == snapshot.initialFrame.minX)
  #expect(far.frame.maxY == snapshot.initialFrame.maxY)
}

@Test func resizeClampsFromFixedEdgesWithoutPostClampTranslation() throws {
  var snapshot = try #require(resizeSnapshot(fixedSide: .right))
  snapshot.visibleFrame = CGRect(x: 50, y: 50, width: 680, height: 500)

  let proposal = try #require(
    MenuPanelResizeGeometry.proposal(
      snapshot: snapshot,
      pointer: CGPoint(x: -500, y: -500),
      handle: .farBottomCorner
    )
  )

  #expect(proposal.contentSize == CGSize(width: 650, height: 480))
  #expect(proposal.frame == CGRect(x: 50, y: 50, width: 650, height: 480))
  #expect(proposal.frame.maxX == snapshot.initialFrame.maxX)
  #expect(proposal.frame.maxY == snapshot.initialFrame.maxY)
}

@Test func resizeAccountsForFrameContentInsets() throws {
  let snapshot = MenuPanelResizeSnapshot(
    initialPointer: CGPoint(x: 100, y: 100),
    initialFrame: CGRect(x: 100, y: 100, width: 612, height: 452),
    initialContentSize: CGSize(width: 600, height: 430),
    frameInsets: MenuPanelFrameInsets(top: 16, left: 6, bottom: 6, right: 6),
    visibleFrame: CGRect(x: 0, y: 0, width: 1_200, height: 900),
    statusLabelFrame: CGRect(x: 692, y: 880, width: 20, height: 20),
    fixedSide: .right
  )

  let proposal = try #require(
    MenuPanelResizeGeometry.proposal(
      snapshot: snapshot,
      pointer: CGPoint(x: 60, y: 70),
      handle: .farBottomCorner
    )
  )

  #expect(proposal.contentSize == CGSize(width: 640, height: 460))
  #expect(proposal.frame == CGRect(x: 60, y: 70, width: 652, height: 482))
  #expect(proposal.frame.maxX == snapshot.initialFrame.maxX)
  #expect(proposal.frame.maxY == snapshot.initialFrame.maxY)
}

@Test @MainActor func constrainedScreensContainThePanelAndDoNotProduceSavableIllegalSizes() throws {
  var snapshot = try #require(resizeSnapshot(fixedSide: .left))
  snapshot.visibleFrame = CGRect(x: 100, y: 250, width: 300, height: 280)

  let proposal = try #require(
    MenuPanelResizeGeometry.presentation(
      contentSize: snapshot.initialContentSize,
      inheritedFrame: snapshot.initialFrame,
      frameInsets: snapshot.frameInsets,
      visibleFrame: snapshot.visibleFrame,
      statusLabelFrame: snapshot.statusLabelFrame,
      preferredSide: snapshot.fixedSide
    )
  )

  #expect(proposal.frame == snapshot.visibleFrame)
  #expect(proposal.contentSize == snapshot.visibleFrame.size)
  #expect(!proposal.isLegalPreference)
  #expect(!MenuPanelResizeController().begin(snapshot: snapshot, handle: .farBottomCorner))
}

@Test func resizeHitTestingExposesOnlyThreeMirroredRegionsWithCornerPriority() {
  let bounds = CGRect(x: 0, y: 0, width: 600, height: 430)

  #expect(MenuPanelResizeGeometry.handle(at: CGPoint(x: 599, y: 200), in: bounds, fixedSide: .left) == .farSide)
  #expect(MenuPanelResizeGeometry.handle(at: CGPoint(x: 599, y: 1), in: bounds, fixedSide: .left) == .farBottomCorner)
  #expect(MenuPanelResizeGeometry.handle(at: CGPoint(x: 1, y: 1), in: bounds, fixedSide: .left) == .nearBottomCorner)
  #expect(MenuPanelResizeGeometry.handle(at: CGPoint(x: 1, y: 200), in: bounds, fixedSide: .left) == nil)
  #expect(MenuPanelResizeGeometry.handle(at: CGPoint(x: 300, y: 1), in: bounds, fixedSide: .left) == nil)
  #expect(MenuPanelResizeGeometry.handle(at: CGPoint(x: 1, y: 1), in: bounds, fixedSide: .right) == .farBottomCorner)
  #expect(MenuPanelResizeGeometry.handle(at: CGPoint(x: 599, y: 1), in: bounds, fixedSide: .right) == .nearBottomCorner)
}

@Test func resizeHitTestingUsesContiguousBottomCornersAndSevenPointSideEdges() {
  let bounds = CGRect(x: 0, y: 0, width: 600, height: 430)

  for fixedSide in [MenuPanelFixedSide.left, .right] {
    func nearX(_ distance: CGFloat) -> CGFloat {
      fixedSide == .left ? bounds.minX + distance : bounds.maxX - distance
    }
    func farX(_ distance: CGFloat) -> CGFloat {
      fixedSide == .left ? bounds.maxX - distance : bounds.minX + distance
    }

    for y in [CGFloat(7), 8, 18] {
      for distance in [CGFloat(7), 8, 18] {
        #expect(
          MenuPanelResizeGeometry.handle(
            at: CGPoint(x: nearX(distance), y: y),
            in: bounds,
            fixedSide: fixedSide
          ) == .nearBottomCorner
        )
        #expect(
          MenuPanelResizeGeometry.handle(
            at: CGPoint(x: farX(distance), y: y),
            in: bounds,
            fixedSide: fixedSide
          ) == .farBottomCorner
        )
      }
      #expect(
        MenuPanelResizeGeometry.handle(
          at: CGPoint(x: nearX(19), y: y),
          in: bounds,
          fixedSide: fixedSide
        ) == nil
      )
      #expect(
        MenuPanelResizeGeometry.handle(
          at: CGPoint(x: farX(19), y: y),
          in: bounds,
          fixedSide: fixedSide
        ) == nil
      )
      #expect(
        MenuPanelResizeGeometry.handle(
          at: CGPoint(x: bounds.midX, y: y),
          in: bounds,
          fixedSide: fixedSide
        ) == nil
      )
    }

    #expect(
      MenuPanelResizeGeometry.handle(
        at: CGPoint(x: farX(7), y: 18),
        in: bounds,
        fixedSide: fixedSide
      ) == .farBottomCorner
    )
    #expect(
      MenuPanelResizeGeometry.handle(
        at: CGPoint(x: farX(7), y: 19),
        in: bounds,
        fixedSide: fixedSide
      ) == .farSide
    )
    for distance in [CGFloat(8), 18, 19] {
      #expect(
        MenuPanelResizeGeometry.handle(
          at: CGPoint(x: farX(distance), y: 19),
          in: bounds,
          fixedSide: fixedSide
        ) == nil
      )
    }
    for distance in [CGFloat(7), 8, 18, 19] {
      #expect(
        MenuPanelResizeGeometry.handle(
          at: CGPoint(x: nearX(distance), y: 19),
          in: bounds,
          fixedSide: fixedSide
        ) == nil
      )
    }
  }
}

@Test @MainActor func resizeControllerCancelsWhenAnchorOrScreenChangesAndPersistsOnlyAtEnd() throws {
  let snapshot = try #require(resizeSnapshot(fixedSide: .right))
  let controller = MenuPanelResizeController()
  #expect(controller.begin(snapshot: snapshot, handle: .farBottomCorner))
  #expect(controller.update(pointer: CGPoint(x: 60, y: 70), statusLabelFrame: snapshot.statusLabelFrame, visibleFrame: snapshot.visibleFrame)?.contentSize == CGSize(width: 640, height: 460))
  #expect(controller.effectiveContentSize == CGSize(width: 640, height: 460))
  #expect(controller.completedPreferenceSize == nil)

  controller.cancelIfGeometryChanged(
    statusLabelFrame: snapshot.statusLabelFrame.offsetBy(dx: 1, dy: 0),
    visibleFrame: snapshot.visibleFrame
  )
  #expect(!controller.isTracking)
  #expect(controller.effectiveContentSize == nil)

  #expect(controller.begin(snapshot: snapshot, handle: .farBottomCorner))
  _ = controller.update(pointer: CGPoint(x: 60, y: 70), statusLabelFrame: snapshot.statusLabelFrame, visibleFrame: snapshot.visibleFrame)
  #expect(controller.finish() == CGSize(width: 640, height: 460))
  #expect(controller.completedPreferenceSize == CGSize(width: 640, height: 460))
  controller.clearCompletion()
  #expect(controller.effectiveContentSize == nil)
}

@Test @MainActor func statusButtonResolverIgnoresOffWindowZeroSizedViewsAndReadsLivePublicGeometry() throws {
  let expectedFrame = CGRect(x: 700, y: 880, width: 34, height: 22)
  let fixture = PublicStatusButtonFixture(screenFrame: expectedFrame)
  let unusedLabelReader = NSView(frame: .zero)
  let resolver = MenuPanelGeometryStore(windows: { [fixture.window] })

  let resolved = try #require(resolver.resolveStatusButton())
  #expect(resolved.screenFrame == expectedFrame)
  #expect(resolver.statusLabelFrame == expectedFrame)

  fixture.button.frame.origin.x += 7
  let liveFrame = fixture.window.convertToScreen(
    fixture.button.convert(fixture.button.bounds, to: nil)
  )
  #expect(resolver.cachedStatusButton?.screenFrame == liveFrame)
  withExtendedLifetime(unusedLabelReader) {}
}

@Test @MainActor func statusButtonResolverFailsClosedForMissingOrAmbiguousPublicButtons() {
  let first = PublicStatusButtonFixture(
    screenFrame: CGRect(x: 700, y: 880, width: 34, height: 22)
  )
  let second = PublicStatusButtonFixture(
    screenFrame: CGRect(x: 740, y: 880, width: 34, height: 22)
  )

  #expect(MenuPanelGeometryStore(windows: { [] }).resolveStatusButton() == nil)
  #expect(
    MenuPanelGeometryStore(windows: { [first.window, second.window] })
      .resolveStatusButton() == nil
  )
}

@Test @MainActor func statusButtonResolverRejectsDetachedReparentedReplacedAndDeallocatedSources() throws {
  let expectedFrame = CGRect(x: 700, y: 880, width: 34, height: 22)
  let fixture = PublicStatusButtonFixture(
    screenFrame: expectedFrame
  )
  let windowProvider = StatusWindowProvider(
    windows: [fixture.window]
  )
  let resolver = MenuPanelGeometryStore(windows: { windowProvider.windows })
  let initial = try #require(resolver.resolveStatusButton())

  fixture.detachButton()
  #expect(resolver.cachedStatusButton == nil)
  fixture.reparentButton()
  let reparented = try #require(resolver.resolveStatusButton())
  #expect(reparented.screenFrame == expectedFrame)
  #expect(reparented.sourceIdentity != initial.sourceIdentity)

  fixture.replaceButtonAtSameFrame()
  #expect(resolver.cachedStatusButton == nil)
  let replaced = try #require(resolver.resolveStatusButton())
  #expect(replaced.screenFrame == reparented.screenFrame)
  #expect(replaced.sourceIdentity != reparented.sourceIdentity)

  let deallocationProvider = StatusWindowProvider(windows: [])
  let deallocationResolver = MenuPanelGeometryStore(
    windows: { deallocationProvider.windows }
  )
  let weakButton = WeakStatusButtonReference()
  autoreleasepool {
    let temporary = PublicStatusButtonFixture(screenFrame: expectedFrame)
    deallocationProvider.windows = [temporary.window]
    _ = deallocationResolver.resolveStatusButton()
    weakButton.value = temporary.button
    deallocationProvider.windows.removeAll()
    temporary.detachButton()
    temporary.window.contentView = nil
  }
  #expect(weakButton.value == nil)
  #expect(deallocationResolver.cachedStatusButton == nil)
}

@Test @MainActor func statusButtonResolverRejectsOwnerReplacementEvenAtTheSameScreenFrame() throws {
  let expectedFrame = CGRect(x: 700, y: 880, width: 34, height: 22)
  let original = PublicStatusButtonFixture(screenFrame: expectedFrame)
  let replacementOwner = PublicStatusButtonFixture(screenFrame: expectedFrame)
  let windowProvider = StatusWindowProvider(windows: [original.window])
  let resolver = MenuPanelGeometryStore(windows: { windowProvider.windows })
  let initial = try #require(resolver.resolveStatusButton())

  replacementOwner.detachButton()
  original.moveButton(to: replacementOwner)
  windowProvider.windows = [replacementOwner.window]

  #expect(resolver.cachedStatusButton == nil)
  let moved = try #require(resolver.resolveStatusButton())
  #expect(moved.screenFrame == expectedFrame)
  #expect(moved.sourceIdentity != initial.sourceIdentity)
}

@Test @MainActor func statusButtonResolverCachedReadsAvoidRecursiveWindowTreeDiscovery() throws {
  let fixture = PublicStatusButtonFixture(
    screenFrame: CGRect(x: 700, y: 880, width: 34, height: 22),
    countsSubviewReads: true
  )
  var windowProviderCalls = 0
  let resolver = MenuPanelGeometryStore(windows: {
    windowProviderCalls += 1
    return [fixture.window]
  })

  _ = try #require(resolver.resolveStatusButton())
  let discoverySubviewReads = try #require(fixture.countingRoot?.subviewReads)
  #expect(discoverySubviewReads > 0)
  for _ in 0..<20 {
    _ = try #require(resolver.cachedStatusButton)
  }
  #expect(fixture.countingRoot?.subviewReads == discoverySubviewReads)
  #expect(windowProviderCalls == 21)
}

@Test func statusButtonResolverSourceUsesOnlyPublicAppKitTraversal() throws {
  let root = menuPanelRepositoryRoot()
  let source = try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/MenuPanelResize.swift"),
    encoding: .utf8
  )
  let appSource = try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/FleckApp.swift"),
    encoding: .utf8
  )

  #expect(source.contains("NSApplication.shared.windows"))
  #expect(source.contains("view as? NSStatusBarButton"))
  #expect(source.contains("window.contentView"))
  #expect(!source.contains("NSClassFromString"))
  #expect(!source.contains("accessibilityHitTest"))
  #expect(!source.contains("MenuPanelStatusLabelGeometryReader"))
  #expect(!appSource.contains("MenuPanelStatusLabelGeometryReader"))
}

@Test @MainActor func resizeBridgeInstallsWithoutReplacingTheDropDelegateAndSkipsPinnedPanels() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let state = AppState(store: LocalStore(rootURL: root), saveOperation: { _, _, _, _ in .committed })
  await state.waitUntilInitialLoad()
  let runtime = DictationRuntime(appState: state, applicationSupportURL: root)

  let menuHost = NSHostingView(
    rootView: NotesPanel(dictationRuntime: runtime).environmentObject(state)
  )
  let menuWindow = NSWindow(
    contentRect: CGRect(x: 0, y: 0, width: 800, height: 430),
    styleMask: .titled,
    backing: .buffered,
    defer: false
  )
  menuWindow.contentView = menuHost
  menuWindow.makeKeyAndOrderFront(nil)
  await settleResizeHost(menuHost)
  let resizeHost = try #require(
    resizeDescendants(in: menuHost, as: MenuPanelResizeHostView.self).first
  )
  #expect(resizeHost.isInstalled)
  #expect(menuWindow.delegate is MenuWindowDropProxy)

  let pinnedHost = NSHostingView(
    rootView: NotesPanel(
      dictationRuntime: runtime,
      isPinned: true,
      sizing: .container
    ).environmentObject(state)
  )
  let pinnedWindow = NSWindow(
    contentRect: CGRect(x: 0, y: 0, width: 800, height: 430),
    styleMask: .titled,
    backing: .buffered,
    defer: false
  )
  pinnedWindow.contentView = pinnedHost
  await settleResizeHost(pinnedHost)
  #expect(resizeDescendants(in: pinnedHost, as: MenuPanelResizeHostView.self).isEmpty)
  #expect(!(pinnedWindow.delegate is MenuWindowDropProxy))

  menuWindow.contentView = nil
  resizeHost.uninstall()
  #expect(!resizeHost.isInstalled)
  menuWindow.orderOut(nil)
  pinnedWindow.contentView = nil
  pinnedWindow.orderOut(nil)
  await runtime.shutdown()
}

@Test @MainActor func resizeHostProcessesRealLocalMonitorEventsAndRestoresWindowConfiguration() async throws {
  let screen = try #require(NSScreen.main)
  let initialFrame = CGRect(
    x: screen.visibleFrame.midX - 300,
    y: screen.visibleFrame.midY - 215,
    width: 600,
    height: 430
  )
  let window = NSWindow(
    contentRect: initialFrame,
    styleMask: .borderless,
    backing: .buffered,
    defer: false
  )
  window.acceptsMouseMovedEvents = false
  let controller = MenuPanelResizeController()
  let statusButton = PublicStatusButtonFixture(
    screenFrame: CGRect(x: initialFrame.maxX - 34, y: initialFrame.maxY + 20, width: 34, height: 22)
  )
  let geometryStore = MenuPanelGeometryStore(windows: { [statusButton.window] })
  var committed: [CGSize] = []
  let host = MenuPanelResizeHostView(controller: controller)
  host.configure(
    geometryStore: geometryStore,
    preferredSize: initialFrame.size,
    canResize: true,
    onCommit: { committed.append($0) }
  )
  window.contentView = host
  window.orderFront(nil)
  host.installIfNeeded()
  await settleResizeHost(host)
  #expect(window.isVisible)
  #expect(host.isInstalled)
  #expect(window.acceptsMouseMovedEvents)

  sendResizeMouseEvent(.mouseMoved, at: CGPoint(x: 1, y: 200), to: window, number: 1)
  sendResizeMouseEvent(.leftMouseDown, at: CGPoint(x: 300, y: 200), to: window, number: 2)
  #expect(!controller.isTracking)
  #expect(window.frame == initialFrame)
  #expect(committed.isEmpty)

  sendResizeMouseEvent(.leftMouseDown, at: CGPoint(x: 1, y: 200), to: window, number: 3)
  #expect(controller.isTracking)
  let dragScreenPoint = window.convertPoint(toScreen: CGPoint(x: -39, y: 200))
  sendResizeMouseEvent(.leftMouseDragged, atScreen: dragScreenPoint, to: window, number: 4)
  #expect(window.frame.maxX == initialFrame.maxX)
  #expect(window.frame.maxY == initialFrame.maxY)
  #expect(window.frame.width == 640)
  sendResizeMouseEvent(.leftMouseUp, atScreen: dragScreenPoint, to: window, number: 5)
  #expect(!controller.isTracking)
  #expect(committed == [CGSize(width: 640, height: 430)])
  sendResizeMouseEvent(.leftMouseUp, atScreen: dragScreenPoint, to: window, number: 6)
  #expect(committed.count == 1)

  window.orderOut(nil)
  sendResizeMouseEvent(.leftMouseDown, at: CGPoint(x: 1, y: 200), to: window, number: 7)
  #expect(!controller.isTracking)
  #expect(committed.count == 1)

  host.uninstall()
  #expect(!host.isInstalled)
  #expect(!window.acceptsMouseMovedEvents)
  window.orderFront(nil)
  sendResizeMouseEvent(.leftMouseDown, at: CGPoint(x: 1, y: 200), to: window, number: 8)
  #expect(!controller.isTracking)
  #expect(committed.count == 1)
  window.contentView = nil
  window.orderOut(nil)
}

@Test @MainActor func menuPanelHostedFractionalResizeAdoptsNativeGeometryOnceAndStaysStable() async throws {
  let screen = try #require(NSScreen.main)
  var eventNumber = 100
  var completedCases = 0
  let sideMargin: CGFloat = 40
  let topMargin: CGFloat = 40

  for fixedSide in [MenuPanelFixedSide.left, .right] {
    for handle in [
      MenuPanelResizeHandle.farSide,
      .farBottomCorner,
      .nearBottomCorner,
    ] {
      let buttonFrame = CGRect(
        x: fixedSide == .left
          ? screen.visibleFrame.minX + sideMargin
          : screen.visibleFrame.maxX - sideMargin - 34,
        y: screen.visibleFrame.maxY + 2,
        width: 34,
        height: 22
      )
      let initialFrame = CGRect(
        x: fixedSide == .left ? buttonFrame.minX : buttonFrame.maxX - 540,
        y: screen.visibleFrame.maxY - topMargin - 430,
        width: 540,
        height: 430
      )
      let window = NSWindow(
        contentRect: initialFrame,
        styleMask: .borderless,
        backing: .buffered,
        defer: false
      )
      let statusButton = PublicStatusButtonFixture(screenFrame: buttonFrame)
      let geometryStore = MenuPanelGeometryStore(windows: { [statusButton.window] })
      geometryStore.rememberCompletedSide(fixedSide)
      let controller = MenuPanelResizeController()
      var commits: [(CGSize, CGRect)] = []
      let host = MenuPanelResizeHostView(controller: controller)
      host.configure(
        geometryStore: geometryStore,
        preferredSize: initialFrame.size,
        canResize: true,
        onCommit: { commits.append(($0, window.frame)) }
      )
      window.contentView = host
      window.orderFront(nil)
      host.installIfNeeded()
      defer {
        host.uninstall()
        window.contentView = nil
        window.orderOut(nil)
      }
      await settleResizeHost(host)
      let startingFrame = window.frame
      let anchoredButtonFrame = try #require(geometryStore.cachedStatusButton?.screenFrame)

      let changesWidth = handle != .nearBottomCorner
      let changesHeight = handle != .farSide
      let availableWidth = fixedSide == .left
        ? screen.visibleFrame.maxX - anchoredButtonFrame.minX
        : anchoredButtonFrame.maxX - screen.visibleFrame.minX
      let widthWhole = min(
        CGFloat(160),
        floor(availableWidth - startingFrame.width - 1.375)
      )
      let heightWhole = min(
        CGFloat(80),
        floor(startingFrame.minY - screen.visibleFrame.minY - 1.375)
      )
      try #require(widthWhole >= 0)
      try #require(heightWhole >= 0)
      let widthDelta = widthWhole + 0.375
      let heightDelta = heightWhole + 0.375
      let nearX: CGFloat = fixedSide == .left ? 0.625 : startingFrame.width - 0.625
      let farX: CGFloat = fixedSide == .left ? startingFrame.width - 0.625 : 0.625
      let mouseDown = CGPoint(
        x: handle == .nearBottomCorner ? nearX : farX,
        y: changesHeight ? 0.625 : 200.625
      )
      var release = window.convertPoint(toScreen: mouseDown)
      if changesWidth {
        release.x += fixedSide == .left ? widthDelta : -widthDelta
      }
      if changesHeight { release.y -= heightDelta }

      sendResizeMouseEvent(.leftMouseDown, at: mouseDown, to: window, number: eventNumber)
      eventNumber += 1
      sendResizeMouseEvent(.leftMouseDragged, atScreen: release, to: window, number: eventNumber)
      eventNumber += 1
      sendResizeMouseEvent(.leftMouseUp, atScreen: release, to: window, number: eventNumber)
      eventNumber += 1

      #expect(commits.count == 1)
      let committed = try #require(commits.first)
      let retainedFrame = window.frame
      let retainedContentSize = window.contentRect(forFrameRect: retainedFrame).size
      let rawTargetSize = CGSize(
        width: startingFrame.width + (changesWidth ? widthDelta : 0),
        height: startingFrame.height + (changesHeight ? heightDelta : 0)
      )
      let rawTargetFrame = CGRect(
        x: fixedSide == .left
          ? anchoredButtonFrame.minX
          : anchoredButtonFrame.maxX - rawTargetSize.width,
        y: startingFrame.maxY - rawTargetSize.height,
        width: rawTargetSize.width,
        height: rawTargetSize.height
      )
      let expectedFrame = screen.backingAlignedRect(
        rawTargetFrame,
        options: .alignAllEdgesOutward
      )
      let expectedContentSize = window.contentRect(forFrameRect: expectedFrame).size
      #expect(retainedFrame == expectedFrame)
      #expect(retainedContentSize == expectedContentSize)
      #expect(committed.0 == expectedContentSize)
      #expect(committed.1 == expectedFrame)
      #expect(retainedFrame.maxY == startingFrame.maxY)
      if fixedSide == .left {
        #expect(retainedFrame.minX == anchoredButtonFrame.minX)
      } else {
        #expect(retainedFrame.maxX == anchoredButtonFrame.maxX)
      }
      if !changesWidth { #expect(retainedFrame.width == startingFrame.width) }
      if !changesHeight { #expect(retainedFrame.height == startingFrame.height) }

      await settleResizeHost(host)
      #expect(commits.count == 1)
      #expect(window.frame == retainedFrame)
      #expect(window.contentRect(forFrameRect: window.frame).size == retainedContentSize)
      completedCases += 1
    }
  }

  #expect(completedCases == 6)
}

@Test @MainActor func resizeMonitorConsumesHandledEventsAndForwardsOrdinaryClicks() async throws {
  let screen = try #require(NSScreen.main)
  let initialFrame = CGRect(
    x: screen.visibleFrame.midX - 300,
    y: screen.visibleFrame.midY - 215,
    width: 600,
    height: 430
  )
  let window = NSWindow(
    contentRect: initialFrame,
    styleMask: .borderless,
    backing: .buffered,
    defer: false
  )
  let receiver = ResizeEventRecordingView(frame: CGRect(origin: .zero, size: initialFrame.size))
  let controller = MenuPanelResizeController()
  let statusButton = PublicStatusButtonFixture(
    screenFrame: CGRect(x: initialFrame.maxX - 34, y: initialFrame.maxY + 20, width: 34, height: 22)
  )
  let geometryStore = MenuPanelGeometryStore(windows: { [statusButton.window] })
  var committed: [CGSize] = []
  let host = MenuPanelResizeHostView(controller: controller)
  host.frame = receiver.bounds
  host.autoresizingMask = [.width, .height]
  host.configure(
    geometryStore: geometryStore,
    preferredSize: initialFrame.size,
    canResize: true,
    onCommit: { committed.append($0) }
  )
  receiver.addSubview(host)
  window.contentView = receiver
  window.orderFront(nil)
  #expect(window.makeFirstResponder(receiver))
  host.installIfNeeded()
  await settleResizeHost(host)
  defer {
    host.uninstall()
    window.contentView = nil
    window.orderOut(nil)
  }

  sendResizeMouseEvent(.leftMouseDown, at: CGPoint(x: 300, y: 200), to: window, number: 20)
  sendResizeMouseEvent(.leftMouseUp, at: CGPoint(x: 300, y: 200), to: window, number: 21)
  #expect(receiver.received == [.leftMouseDown, .leftMouseUp])
  #expect(!controller.isTracking)
  receiver.received.removeAll()

  sendResizeMouseEvent(.leftMouseDown, at: CGPoint(x: 1, y: 200), to: window, number: 22)
  let sideDragScreenPoint = window.convertPoint(toScreen: CGPoint(x: -19, y: 200))
  sendResizeMouseEvent(.leftMouseDragged, atScreen: sideDragScreenPoint, to: window, number: 23)
  sendResizeMouseEvent(.leftMouseUp, atScreen: sideDragScreenPoint, to: window, number: 24)
  #expect(receiver.received.isEmpty)
  #expect(committed == [CGSize(width: 620, height: 430)])
  await settleResizeHost(host)

  sendResizeMouseEvent(.leftMouseDown, at: CGPoint(x: 1, y: 1), to: window, number: 25)
  let cornerDragScreenPoint = window.convertPoint(toScreen: CGPoint(x: -19, y: -19))
  sendResizeMouseEvent(.leftMouseDragged, atScreen: cornerDragScreenPoint, to: window, number: 26)
  sendResizeMouseEvent(.leftMouseUp, atScreen: cornerDragScreenPoint, to: window, number: 27)
  #expect(receiver.received.isEmpty)
  #expect(committed == [CGSize(width: 620, height: 430), CGSize(width: 640, height: 450)])
  await settleResizeHost(host)

  sendResizeMouseEvent(.leftMouseDown, at: CGPoint(x: 1, y: 200), to: window, number: 28)
  #expect(controller.isTracking)
  sendResizeEscapeEvent(to: window, number: 29)
  #expect(!controller.isTracking)
  #expect(receiver.received.isEmpty)
  #expect(committed.count == 2)

  host.uninstall()
  receiver.received.removeAll()
  sendResizeMouseEvent(.leftMouseDown, at: CGPoint(x: 300, y: 200), to: window, number: 30)
  sendResizeMouseEvent(.leftMouseUp, at: CGPoint(x: 300, y: 200), to: window, number: 31)
  #expect(receiver.received == [.leftMouseDown, .leftMouseUp])
}

@Test @MainActor func resizeCommitRejectsChangedOrMissingAnchorAfterLastDragEvent() async throws {
  let screen = try #require(NSScreen.main)
  let initialFrame = CGRect(
    x: screen.visibleFrame.midX - 300,
    y: screen.visibleFrame.midY - 215,
    width: 600,
    height: 430
  )
  let initialAnchor = CGRect(
    x: initialFrame.maxX - 34,
    y: initialFrame.maxY + 20,
    width: 34,
    height: 22
  )

  for changesAnchor in [true, false] {
    let window = NSWindow(
      contentRect: initialFrame,
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    let controller = MenuPanelResizeController()
    let statusButton = PublicStatusButtonFixture(screenFrame: initialAnchor)
    let geometryStore = MenuPanelGeometryStore(windows: { [statusButton.window] })
    var committed: [CGSize] = []
    let host = MenuPanelResizeHostView(controller: controller)
    host.configure(
      geometryStore: geometryStore,
      preferredSize: initialFrame.size,
      canResize: true,
      onCommit: { committed.append($0) }
    )
    window.contentView = host
    window.orderFront(nil)
    host.installIfNeeded()
    await settleResizeHost(host)
    defer {
      host.uninstall()
      window.contentView = nil
      window.orderOut(nil)
    }

    sendResizeMouseEvent(.leftMouseDown, at: CGPoint(x: 1, y: 200), to: window, number: 40)
    let dragScreenPoint = window.convertPoint(toScreen: CGPoint(x: -19, y: 200))
    sendResizeMouseEvent(.leftMouseDragged, atScreen: dragScreenPoint, to: window, number: 41)
    #expect(controller.isTracking)
    #expect(window.frame.width == 620)

    if changesAnchor {
      statusButton.button.frame.origin.x += 1
    } else {
      statusButton.detachButton()
    }
    sendResizeMouseEvent(.leftMouseUp, atScreen: dragScreenPoint, to: window, number: 42)
    #expect(!controller.isTracking)
    #expect(committed.isEmpty)
    #expect(
      window.frame == (changesAnchor ? initialFrame.offsetBy(dx: 1, dy: 0) : initialFrame)
    )
  }
}

@Test @MainActor func resizeHostFreshBeginDiscoveryRejectsAmbiguityIntroducedAfterAttach() async throws {
  let screen = try #require(NSScreen.main)
  let initialFrame = CGRect(
    x: screen.visibleFrame.midX - 300,
    y: screen.visibleFrame.midY - 215,
    width: 600,
    height: 430
  )
  let window = NSWindow(
    contentRect: initialFrame,
    styleMask: .borderless,
    backing: .buffered,
    defer: false
  )
  let receiver = ResizeEventRecordingView(frame: CGRect(origin: .zero, size: initialFrame.size))
  let firstStatusButton = PublicStatusButtonFixture(
    screenFrame: CGRect(x: initialFrame.maxX - 34, y: initialFrame.maxY + 20, width: 34, height: 22)
  )
  let statusWindowProvider = StatusWindowProvider(windows: [firstStatusButton.window])
  let geometryStore = MenuPanelGeometryStore(windows: { statusWindowProvider.windows })
  let controller = MenuPanelResizeController()
  let host = MenuPanelResizeHostView(controller: controller)
  host.frame = receiver.bounds
  host.autoresizingMask = [.width, .height]
  host.configure(
    geometryStore: geometryStore,
    preferredSize: initialFrame.size,
    canResize: true,
    onCommit: { _ in Issue.record("Ambiguous status buttons committed a resize") }
  )
  receiver.addSubview(host)
  window.contentView = receiver
  window.orderFront(nil)
  #expect(window.makeFirstResponder(receiver))
  host.installIfNeeded()
  await settleResizeHost(host)
  defer {
    host.uninstall()
    window.contentView = nil
    window.orderOut(nil)
  }
  _ = try #require(geometryStore.cachedStatusButton)

  let secondStatusButton = PublicStatusButtonFixture(
    screenFrame: CGRect(x: initialFrame.maxX + 48, y: initialFrame.maxY + 20, width: 34, height: 22)
  )
  statusWindowProvider.windows.append(secondStatusButton.window)
  sendResizeMouseEvent(.leftMouseDown, at: CGPoint(x: 1, y: 200), to: window, number: 45)
  sendResizeMouseEvent(.leftMouseUp, at: CGPoint(x: 1, y: 200), to: window, number: 46)

  #expect(!controller.isTracking)
  #expect(window.frame == initialFrame)
  #expect(receiver.received == [.leftMouseDown, .leftMouseUp])
}

@Test @MainActor func resizeHostFreshEndDiscoveryRejectsAmbiguityAndSameFrameReplacement() async throws {
  let screen = try #require(NSScreen.main)

  for mutation in ResizeEndStatusMutation.allCases {
    let initialFrame = CGRect(
      x: screen.visibleFrame.midX - 300,
      y: screen.visibleFrame.midY - 215,
      width: 600,
      height: 430
    )
    let window = NSWindow(
      contentRect: initialFrame,
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    let statusButton = PublicStatusButtonFixture(
      screenFrame: CGRect(x: initialFrame.maxX - 34, y: initialFrame.maxY + 20, width: 34, height: 22)
    )
    let statusWindowProvider = StatusWindowProvider(windows: [statusButton.window])
    let geometryStore = MenuPanelGeometryStore(windows: { statusWindowProvider.windows })
    let controller = MenuPanelResizeController()
    var committed: [CGSize] = []
    let host = MenuPanelResizeHostView(controller: controller)
    host.configure(
      geometryStore: geometryStore,
      preferredSize: initialFrame.size,
      canResize: true,
      onCommit: { committed.append($0) }
    )
    window.contentView = host
    window.orderFront(nil)
    host.installIfNeeded()
    await settleResizeHost(host)
    defer {
      host.uninstall()
      window.contentView = nil
      window.orderOut(nil)
    }

    sendResizeMouseEvent(.leftMouseDown, at: CGPoint(x: 1, y: 200), to: window, number: 47)
    let dragScreenPoint = window.convertPoint(toScreen: CGPoint(x: -19, y: 200))
    sendResizeMouseEvent(.leftMouseDragged, atScreen: dragScreenPoint, to: window, number: 48)
    #expect(controller.isTracking)
    #expect(window.frame.width == 620)

    var additionalStatusButton: PublicStatusButtonFixture?
    switch mutation {
    case .ambiguity:
      additionalStatusButton = PublicStatusButtonFixture(
        screenFrame: CGRect(x: initialFrame.maxX + 48, y: initialFrame.maxY + 20, width: 34, height: 22)
      )
      statusWindowProvider.windows.append(try #require(additionalStatusButton?.window))
    case .buttonReplacement:
      statusButton.replaceButtonAtSameFrame()
    case .ownerReplacement:
      additionalStatusButton = PublicStatusButtonFixture(
        screenFrame: CGRect(x: initialFrame.maxX - 34, y: initialFrame.maxY + 20, width: 34, height: 22)
      )
      try #require(additionalStatusButton).detachButton()
      statusButton.moveButton(to: try #require(additionalStatusButton))
      statusWindowProvider.windows = [try #require(additionalStatusButton?.window)]
    }
    sendResizeMouseEvent(.leftMouseUp, atScreen: dragScreenPoint, to: window, number: 49)

    #expect(!controller.isTracking)
    #expect(committed.isEmpty)
    #expect(window.frame == initialFrame)
    withExtendedLifetime(additionalStatusButton) {}
  }
}

@Test @MainActor func retainedNoteAndFolderDragSessionsReenableHostedResizeAfterEndOrCancel() async throws {
  let screen = try #require(NSScreen.main)

  for kind in [ResizeDragKind.note, .folder] {
    for operation in [NSDragOperation.move, []] {
      let (session, data) = try reorderSessionFixture(kind: kind)
      var transactionCommits = 0
      if operation == .move {
        #expect(session.acceptDrop(data: data) { transactionCommits += 1 })
        #expect(!session.canAcceptDrop)
        #expect(session.isDragging)
      }
      let initialFrame = CGRect(
        x: screen.visibleFrame.midX - 300,
        y: screen.visibleFrame.midY - 215,
        width: 600,
        height: 430
      )
      let window = NSWindow(
        contentRect: initialFrame,
        styleMask: .borderless,
        backing: .buffered,
        defer: false
      )
      let controller = MenuPanelResizeController()
      let statusButton = PublicStatusButtonFixture(
        screenFrame: CGRect(
          x: initialFrame.maxX - 34,
          y: initialFrame.maxY + 20,
          width: 34,
          height: 22
        )
      )
      let geometryStore = MenuPanelGeometryStore(windows: { [statusButton.window] })
      var resizeCommits: [CGSize] = []
      let hostingView = NSHostingView(
        rootView: ReorderAwareMenuPanelResizeInstaller(
          dragSession: session,
          controller: controller,
          geometryStore: geometryStore,
          preferredSize: initialFrame.size,
          canResize: true,
          onCommit: { resizeCommits.append($0) }
        )
      )
      window.contentView = hostingView
      window.orderFront(nil)
      await settleResizeHost(hostingView)
      let resizeHost = try #require(
        resizeDescendants(in: hostingView, as: MenuPanelResizeHostView.self).first
      )
      defer {
        resizeHost.uninstall()
        window.contentView = nil
        window.orderOut(nil)
      }

      sendResizeMouseEvent(.leftMouseDown, at: CGPoint(x: 1, y: 200), to: window, number: 50)
      sendResizeMouseEvent(.leftMouseUp, at: CGPoint(x: 1, y: 200), to: window, number: 51)
      #expect(!controller.isTracking)
      #expect(resizeCommits.isEmpty)
      #expect(window.frame == initialFrame)

      session.end(operation: operation)
      #expect(!session.isDragging)
      #expect(transactionCommits == (operation == .move ? 1 : 0))
      await settleResizeHost(hostingView)

      sendResizeMouseEvent(.leftMouseDown, at: CGPoint(x: 1, y: 200), to: window, number: 52)
      let dragScreenPoint = window.convertPoint(toScreen: CGPoint(x: -19, y: 200))
      sendResizeMouseEvent(.leftMouseDragged, atScreen: dragScreenPoint, to: window, number: 53)
      sendResizeMouseEvent(.leftMouseUp, atScreen: dragScreenPoint, to: window, number: 54)
      #expect(resizeCommits == [CGSize(width: 620, height: 430)])
      #expect(window.frame.maxX == initialFrame.maxX)
      #expect(window.frame.maxY == initialFrame.maxY)
      withExtendedLifetime(session) {}
    }
  }
}

@Test @MainActor func menuPanelHostedFirstPlacementAndReopenAlignActualButtonBorders() async throws {
  let screen = try #require(NSScreen.main)
  let initialWidth = min(CGFloat(600), screen.visibleFrame.width / 2)
  let buttonFrame = CGRect(
    x: screen.visibleFrame.midX - 17,
    y: screen.visibleFrame.maxY + 2,
    width: 34,
    height: 22
  )

  for side in [MenuPanelFixedSide.left, .right] {
    let initialFrame = CGRect(
      x: screen.visibleFrame.midX - 420,
      y: screen.visibleFrame.midY - 215,
      width: initialWidth,
      height: 430
    )
    let window = NSWindow(
      contentRect: initialFrame,
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    let statusButton = PublicStatusButtonFixture(screenFrame: buttonFrame)
    let geometryStore = MenuPanelGeometryStore(windows: { [statusButton.window] })
    geometryStore.rememberCompletedSide(side)
    let host = MenuPanelResizeHostView(controller: MenuPanelResizeController())
    host.configure(
      geometryStore: geometryStore,
      preferredSize: initialFrame.size,
      canResize: true,
      onCommit: { _ in }
    )
    window.contentView = host
    #expect(!window.isVisible)
    #expect(window.frame.maxY == initialFrame.maxY)
    #expect(window.frame.size == initialFrame.size)
    if side == .left {
      #expect(window.frame.minX == buttonFrame.minX)
    } else {
      #expect(window.frame.maxX == buttonFrame.maxX)
    }
    window.makeKeyAndOrderFront(nil)
    #expect(window.frame.maxY == initialFrame.maxY)
    #expect(window.frame.size == initialFrame.size)
    if side == .left {
      #expect(window.frame.minX == buttonFrame.minX)
    } else {
      #expect(window.frame.maxX == buttonFrame.maxX)
    }
    host.installIfNeeded()
    await settleResizeHost(host)

    let firstTop = initialFrame.maxY
    #expect(window.frame.maxY == firstTop)
    if side == .left {
      #expect(window.frame.minX == buttonFrame.minX)
    } else {
      #expect(window.frame.maxX == buttonFrame.maxX)
    }

    window.orderOut(nil)
    let reopenFrame = CGRect(
      x: initialFrame.minX + 90,
      y: initialFrame.minY - 30,
      width: initialFrame.width,
      height: initialFrame.height
    )
    window.setFrame(reopenFrame, display: false)
    #expect(!window.isVisible)
    #expect(window.frame.maxY == reopenFrame.maxY)
    #expect(window.frame.size == reopenFrame.size)
    if side == .left {
      #expect(window.frame.minX == buttonFrame.minX)
    } else {
      #expect(window.frame.maxX == buttonFrame.maxX)
    }
    window.makeKeyAndOrderFront(nil)
    #expect(window.frame.maxY == reopenFrame.maxY)
    #expect(window.frame.size == reopenFrame.size)
    if side == .left {
      #expect(window.frame.minX == buttonFrame.minX)
    } else {
      #expect(window.frame.maxX == buttonFrame.maxX)
    }
    host.installIfNeeded()
    await settleResizeHost(host)
    #expect(window.frame.maxY == reopenFrame.maxY)
    if side == .left {
      #expect(window.frame.minX == buttonFrame.minX)
    } else {
      #expect(window.frame.maxX == buttonFrame.maxX)
    }

    host.uninstall()
    window.contentView = nil
    window.orderOut(nil)
  }
}

@Test @MainActor func menuPanelHostedHiddenAttachObservesLiveVisibilityAtAcquisition() async throws {
  let screen = try #require(NSScreen.main)
  let initialWidth = min(CGFloat(600), screen.visibleFrame.width / 2)
  let buttonFrame = CGRect(
    x: screen.visibleFrame.midX - 17,
    y: screen.visibleFrame.maxY + 2,
    width: 34,
    height: 22
  )
  let initialFrame = CGRect(
    x: buttonFrame.maxX - initialWidth + 60,
    y: screen.visibleFrame.midY - 215,
    width: initialWidth,
    height: 430
  )
  let window = NSWindow(
    contentRect: initialFrame,
    styleMask: .borderless,
    backing: .buffered,
    defer: false
  )
  let statusButton = PublicStatusButtonFixture(screenFrame: buttonFrame)
  let geometryStore = MenuPanelGeometryStore(windows: { [statusButton.window] })
  geometryStore.rememberCompletedSide(.right)
  let host = MenuPanelResizeHostView(controller: MenuPanelResizeController())
  host.configure(
    geometryStore: geometryStore,
    preferredSize: initialFrame.size,
    canResize: true,
    onCommit: { _ in }
  )

  #expect(!window.isVisible)
  window.contentView = host
  #expect(window.frame.maxX == buttonFrame.maxX)
  #expect(window.frame.maxY == initialFrame.maxY)
  #expect(window.frame.size == initialFrame.size)
  window.makeKeyAndOrderFront(nil)
  #expect(window.frame.maxX == buttonFrame.maxX)
  #expect(window.frame.maxY == initialFrame.maxY)
  #expect(window.frame.size == initialFrame.size)
  await settleResizeHost(host)

  #expect(host.isInstalled)
  #expect(window.frame.maxX == buttonFrame.maxX)
  #expect(window.frame.maxY == initialFrame.maxY)
  #expect(window.frame.size == initialFrame.size)

  host.uninstall()
  window.contentView = nil
  window.orderOut(nil)
}

@Test @MainActor func menuPanelHostedNativeCorrectionDefersLatestObservableSize() async throws {
  let screen = try #require(NSScreen.main)
  let buttonFrame = CGRect(
    x: screen.visibleFrame.minX + 466,
    y: screen.visibleFrame.maxY + 2,
    width: 34,
    height: 22
  )
  let initialFrame = CGRect(
    x: buttonFrame.maxX - 800,
    y: screen.visibleFrame.midY - 215,
    width: 800,
    height: 430
  )
  let expectedFrame = CGRect(
    x: screen.visibleFrame.minX,
    y: initialFrame.minY,
    width: 500,
    height: 430
  )
  let window = NSWindow(
    contentRect: initialFrame,
    styleMask: .borderless,
    backing: .buffered,
    defer: false
  )
  let statusButton = PublicStatusButtonFixture(screenFrame: buttonFrame)
  let geometryStore = MenuPanelGeometryStore(windows: { [statusButton.window] })
  geometryStore.rememberCompletedSide(.right)
  let controller = MenuPanelResizeController()
  var publications: [CGSize?] = []
  let observation = controller.$effectiveContentSize.dropFirst().sink {
    publications.append($0)
  }
  let host = MenuPanelResizeHostView(controller: controller)
  host.configure(
    geometryStore: geometryStore,
    preferredSize: initialFrame.size,
    canResize: true,
    onCommit: { _ in }
  )

  window.contentView = host
  #expect(!window.isVisible)
  #expect(window.frame == expectedFrame)
  #expect(controller.effectiveContentSize == nil)
  #expect(publications.isEmpty)
  window.makeKeyAndOrderFront(nil)
  #expect(window.frame == expectedFrame)
  #expect(controller.effectiveContentSize == nil)
  #expect(publications.isEmpty)

  window.setContentSize(CGSize(width: 450, height: 410))
  #expect(window.frame == expectedFrame)
  #expect(controller.effectiveContentSize == nil)
  #expect(publications.isEmpty)

  await settleResizeHost(host)
  #expect(controller.effectiveContentSize == CGSize(width: 500, height: 430))
  #expect(publications == [CGSize(width: 500, height: 430)])

  withExtendedLifetime(observation) {}
  host.uninstall()
  window.contentView = nil
  window.orderOut(nil)
}

@Test @MainActor func menuPanelHostedTransientHideShowDoesNotCancelTracking() async throws {
  let screen = try #require(NSScreen.main)
  let initialFrame = CGRect(
    x: screen.visibleFrame.midX - 300,
    y: screen.visibleFrame.midY - 215,
    width: 600,
    height: 430
  )
  let window = NSWindow(
    contentRect: initialFrame,
    styleMask: .borderless,
    backing: .buffered,
    defer: false
  )
  let statusButton = PublicStatusButtonFixture(
    screenFrame: CGRect(
      x: initialFrame.maxX - 34,
      y: initialFrame.maxY + 20,
      width: 34,
      height: 22
    )
  )
  let geometryStore = MenuPanelGeometryStore(windows: { [statusButton.window] })
  let controller = MenuPanelResizeController()
  let host = MenuPanelResizeHostView(controller: controller)
  host.configure(
    geometryStore: geometryStore,
    preferredSize: initialFrame.size,
    canResize: true,
    onCommit: { _ in }
  )
  window.contentView = host
  window.makeKeyAndOrderFront(nil)
  await settleResizeHost(host)

  sendResizeMouseEvent(.leftMouseDown, at: CGPoint(x: 1, y: 200), to: window, number: 80)
  let dragPoint = window.convertPoint(toScreen: CGPoint(x: -19, y: 200))
  sendResizeMouseEvent(.leftMouseDragged, atScreen: dragPoint, to: window, number: 81)
  #expect(controller.isTracking)
  #expect(window.frame.width == 620)

  window.orderOut(nil)
  window.makeKeyAndOrderFront(nil)
  await settleResizeHost(host)

  #expect(controller.isTracking)
  #expect(window.frame.width == 620)
  sendResizeEscapeEvent(to: window, number: 82)
  #expect(!controller.isTracking)

  host.uninstall()
  window.contentView = nil
  window.orderOut(nil)
}

@Test @MainActor func menuPanelHostedRecreatedHostRejectsStaleCleanupAndReconcilesFeedback() async throws {
  let screen = try #require(NSScreen.main)
  let buttonFrame = CGRect(
    x: screen.visibleFrame.midX - 17,
    y: screen.visibleFrame.maxY + 2,
    width: 34,
    height: 22
  )
  let initialFrame = CGRect(
    x: buttonFrame.maxX - 600,
    y: screen.visibleFrame.midY - 215,
    width: 600,
    height: 430
  )
  let window = NSWindow(
    contentRect: initialFrame,
    styleMask: .borderless,
    backing: .buffered,
    defer: false
  )
  let statusButton = PublicStatusButtonFixture(screenFrame: buttonFrame)
  let geometryStore = MenuPanelGeometryStore(windows: { [statusButton.window] })
  geometryStore.rememberCompletedSide(.right)
  let controller = MenuPanelResizeController()
  let firstHost = MenuPanelResizeHostView(controller: controller)
  firstHost.configure(
    geometryStore: geometryStore,
    preferredSize: initialFrame.size,
    canResize: true,
    onCommit: { _ in }
  )
  window.contentView = firstHost
  window.orderFront(nil)
  firstHost.installIfNeeded()
  await settleResizeHost(firstHost)

  window.contentView = nil
  firstHost.uninstall()
  let secondHost = MenuPanelResizeHostView(controller: controller)
  secondHost.configure(
    geometryStore: geometryStore,
    preferredSize: initialFrame.size,
    canResize: true,
    onCommit: { _ in }
  )
  window.contentView = secondHost
  secondHost.installIfNeeded()
  await settleResizeHost(secondHost)
  #expect(secondHost.isInstalled)
  #expect(window.frame.maxX == buttonFrame.maxX)

  window.setFrame(window.frame.offsetBy(dx: -80, dy: -20), display: true)
  await settleResizeHost(secondHost)
  #expect(window.frame.maxX == buttonFrame.maxX)
  #expect(window.frame.maxY == initialFrame.maxY)

  sendResizeMouseEvent(.leftMouseDown, at: CGPoint(x: 1, y: 200), to: window, number: 60)
  #expect(controller.isTracking)
  firstHost.uninstall()
  await Task.yield()
  #expect(controller.isTracking)
  sendResizeEscapeEvent(to: window, number: 61)
  #expect(!controller.isTracking)

  secondHost.uninstall()
  window.contentView = nil
  window.orderOut(nil)
}

@Test @MainActor func menuPanelHostedSameHostReattachUsesNewAttachmentOwnership() async throws {
  let screen = try #require(NSScreen.main)
  let buttonFrame = CGRect(
    x: screen.visibleFrame.midX - 17,
    y: screen.visibleFrame.maxY + 2,
    width: 34,
    height: 22
  )
  let frame = CGRect(
    x: buttonFrame.maxX - 600,
    y: screen.visibleFrame.midY - 215,
    width: 600,
    height: 430
  )
  let firstWindow = NSWindow(
    contentRect: frame,
    styleMask: .borderless,
    backing: .buffered,
    defer: false
  )
  let secondWindow = NSWindow(
    contentRect: frame,
    styleMask: .borderless,
    backing: .buffered,
    defer: false
  )
  firstWindow.acceptsMouseMovedEvents = false
  secondWindow.acceptsMouseMovedEvents = false
  let statusButton = PublicStatusButtonFixture(screenFrame: buttonFrame)
  let geometryStore = MenuPanelGeometryStore(windows: { [statusButton.window] })
  geometryStore.rememberCompletedSide(.right)
  let controller = MenuPanelResizeController()
  let host = MenuPanelResizeHostView(controller: controller)
  host.configure(
    geometryStore: geometryStore,
    preferredSize: frame.size,
    canResize: true,
    onCommit: { _ in }
  )

  firstWindow.contentView = host
  firstWindow.orderFront(nil)
  host.installIfNeeded()
  await settleResizeHost(host)
  #expect(firstWindow.acceptsMouseMovedEvents)
  firstWindow.contentView = nil
  firstWindow.orderOut(nil)

  secondWindow.contentView = host
  secondWindow.orderFront(nil)
  host.installIfNeeded()
  await settleResizeHost(host)
  #expect(host.isInstalled)
  #expect(!firstWindow.acceptsMouseMovedEvents)
  #expect(secondWindow.acceptsMouseMovedEvents)
  #expect(secondWindow.frame.maxX == buttonFrame.maxX)
  sendResizeMouseEvent(.leftMouseDown, at: CGPoint(x: 1, y: 200), to: secondWindow, number: 65)
  #expect(controller.isTracking)
  await Task.yield()
  #expect(controller.isTracking)
  sendResizeEscapeEvent(to: secondWindow, number: 66)
  #expect(!controller.isTracking)

  host.uninstall()
  await Task.yield()
  #expect(!secondWindow.acceptsMouseMovedEvents)
  secondWindow.contentView = nil
  secondWindow.orderOut(nil)
}

@Test @MainActor func menuPanelHostedTrackingFeedbackUsesCachedButtonAndCancelsMissingSource() async throws {
  let screen = try #require(NSScreen.main)
  let initialFrame = CGRect(
    x: screen.visibleFrame.midX - 300,
    y: screen.visibleFrame.midY - 215,
    width: 600,
    height: 430
  )
  let window = NSWindow(
    contentRect: initialFrame,
    styleMask: .borderless,
    backing: .buffered,
    defer: false
  )
  let statusButton = PublicStatusButtonFixture(
    screenFrame: CGRect(
      x: initialFrame.maxX - 34,
      y: initialFrame.maxY + 20,
      width: 34,
      height: 22
    ),
    countsSubviewReads: true
  )
  let geometryStore = MenuPanelGeometryStore(windows: { [statusButton.window] })
  let controller = MenuPanelResizeController()
  var commits = 0
  let host = MenuPanelResizeHostView(controller: controller)
  host.configure(
    geometryStore: geometryStore,
    preferredSize: initialFrame.size,
    canResize: true,
    onCommit: { _ in commits += 1 }
  )
  window.contentView = host
  window.orderFront(nil)
  host.installIfNeeded()
  await settleResizeHost(host)
  sendResizeMouseEvent(.leftMouseDown, at: CGPoint(x: 1, y: 200), to: window, number: 67)
  #expect(controller.isTracking)
  let readsAfterFreshBegin = try #require(statusButton.countingRoot?.subviewReads)

  let dragPoint = window.convertPoint(toScreen: CGPoint(x: -19, y: 200))
  sendResizeMouseEvent(.leftMouseDragged, atScreen: dragPoint, to: window, number: 68)
  await settleResizeHost(host)
  #expect(statusButton.countingRoot?.subviewReads == readsAfterFreshBegin)
  #expect(controller.isTracking)

  statusButton.detachButton()
  host.needsLayout = true
  host.layoutSubtreeIfNeeded()
  await settleResizeHost(host)
  #expect(!controller.isTracking)
  #expect(commits == 0)

  host.uninstall()
  window.contentView = nil
  window.orderOut(nil)
}

@Test @MainActor func menuPanelHostedImmediateEligibilityLossCancelsConsumedGesture() async throws {
  let screen = try #require(NSScreen.main)
  let initialFrame = CGRect(
    x: screen.visibleFrame.midX - 300,
    y: screen.visibleFrame.midY - 215,
    width: 600,
    height: 430
  )
  let window = NSWindow(
    contentRect: initialFrame,
    styleMask: .borderless,
    backing: .buffered,
    defer: false
  )
  let statusButton = PublicStatusButtonFixture(
    screenFrame: CGRect(
      x: initialFrame.maxX - 34,
      y: initialFrame.maxY + 20,
      width: 34,
      height: 22
    )
  )
  let geometryStore = MenuPanelGeometryStore(windows: { [statusButton.window] })
  let controller = MenuPanelResizeController()
  var commits: [CGSize] = []
  let host = MenuPanelResizeHostView(controller: controller)
  host.configure(
    geometryStore: geometryStore,
    preferredSize: initialFrame.size,
    canResize: true,
    onCommit: { commits.append($0) }
  )
  window.contentView = host
  window.orderFront(nil)
  host.installIfNeeded()
  await settleResizeHost(host)

  let dragPoint = window.convertPoint(toScreen: CGPoint(x: -19, y: 200))
  sendResizeMouseEvent(.leftMouseDown, at: CGPoint(x: 1, y: 200), to: window, number: 69)
  sendResizeMouseEvent(.leftMouseDragged, atScreen: dragPoint, to: window, number: 70)
  #expect(controller.isTracking)
  host.configure(
    geometryStore: geometryStore,
    preferredSize: initialFrame.size,
    canResize: false,
    onCommit: { commits.append($0) }
  )
  sendResizeMouseEvent(.leftMouseUp, atScreen: dragPoint, to: window, number: 71)
  #expect(!controller.isTracking)
  #expect(commits.isEmpty)
  #expect(window.frame == initialFrame)

  host.configure(
    geometryStore: geometryStore,
    preferredSize: initialFrame.size,
    canResize: true,
    onCommit: { commits.append($0) }
  )
  await settleResizeHost(host)
  let child = NSWindow(
    contentRect: CGRect(x: initialFrame.midX, y: initialFrame.midY, width: 120, height: 80),
    styleMask: .borderless,
    backing: .buffered,
    defer: false
  )
  sendResizeMouseEvent(.leftMouseDown, at: CGPoint(x: 1, y: 200), to: window, number: 72)
  #expect(controller.isTracking)
  window.addChildWindow(child, ordered: .above)
  child.orderFront(nil)
  sendResizeMouseEvent(.leftMouseDragged, atScreen: dragPoint, to: window, number: 73)
  #expect(!controller.isTracking)
  #expect(commits.isEmpty)
  #expect(window.frame == initialFrame)

  window.removeChildWindow(child)
  child.orderOut(nil)
  host.uninstall()
  window.contentView = nil
  window.orderOut(nil)
}

@Test @MainActor func menuPanelHostedOverlappingReplacementOwnsFrameAndWindowConfiguration() async throws {
  let screen = try #require(NSScreen.main)
  let initialFrame = CGRect(
    x: screen.visibleFrame.midX - 300,
    y: screen.visibleFrame.midY - 215,
    width: 600,
    height: 430
  )
  let window = NSWindow(
    contentRect: initialFrame,
    styleMask: .borderless,
    backing: .buffered,
    defer: false
  )
  window.acceptsMouseMovedEvents = false
  let root = ResizeEventRecordingView(frame: CGRect(origin: .zero, size: initialFrame.size))
  let statusButton = PublicStatusButtonFixture(
    screenFrame: CGRect(
      x: initialFrame.maxX - 34,
      y: initialFrame.maxY + 20,
      width: 34,
      height: 22
    )
  )
  let geometryStore = MenuPanelGeometryStore(windows: { [statusButton.window] })
  let controller = MenuPanelResizeController()
  var oldCommits: [CGSize] = []
  var newCommits: [CGSize] = []
  let firstHost = MenuPanelResizeHostView(controller: controller)
  firstHost.frame = root.bounds
  firstHost.autoresizingMask = [.width, .height]
  firstHost.configure(
    geometryStore: geometryStore,
    preferredSize: initialFrame.size,
    canResize: true,
    onCommit: { oldCommits.append($0) }
  )
  root.addSubview(firstHost)
  window.contentView = root
  window.orderFront(nil)
  firstHost.installIfNeeded()
  await settleResizeHost(root)
  #expect(window.acceptsMouseMovedEvents)

  let dragPoint = window.convertPoint(toScreen: CGPoint(x: -19, y: 200))
  sendResizeMouseEvent(.leftMouseDown, at: CGPoint(x: 1, y: 200), to: window, number: 74)
  sendResizeMouseEvent(.leftMouseDragged, atScreen: dragPoint, to: window, number: 75)
  #expect(controller.isTracking)
  #expect(window.frame.width == 620)

  let secondHost = MenuPanelResizeHostView(controller: controller)
  secondHost.frame = root.bounds
  secondHost.autoresizingMask = [.width, .height]
  secondHost.configure(
    geometryStore: geometryStore,
    preferredSize: CGSize(width: 500, height: 430),
    canResize: true,
    onCommit: { newCommits.append($0) }
  )
  root.addSubview(secondHost)
  secondHost.installIfNeeded()
  firstHost.configure(
    geometryStore: geometryStore,
    preferredSize: CGSize(width: 650, height: 430),
    canResize: true,
    onCommit: { oldCommits.append($0) }
  )
  await settleResizeHost(root)

  #expect(!controller.isTracking)
  #expect(oldCommits.isEmpty)
  #expect(newCommits.isEmpty)
  #expect(window.frame.width == 500)
  #expect(window.frame.maxX == initialFrame.maxX)
  #expect(controller.effectiveContentSize == nil)
  #expect(window.acceptsMouseMovedEvents)

  sendResizeMouseEvent(.leftMouseDown, at: CGPoint(x: 1, y: 200), to: window, number: 76)
  #expect(controller.isTracking)
  sendResizeEscapeEvent(to: window, number: 77)
  #expect(!controller.isTracking)

  sendResizeMouseEvent(.leftMouseDown, at: CGPoint(x: -99, y: 200), to: window, number: 78)
  sendResizeMouseEvent(.leftMouseUp, at: CGPoint(x: -99, y: 200), to: window, number: 79)
  #expect(!controller.isTracking)
  #expect(window.frame.width == 500)
  #expect(controller.effectiveContentSize == nil)

  firstHost.uninstall()
  #expect(window.acceptsMouseMovedEvents)
  secondHost.uninstall()
  await Task.yield()
  #expect(!window.acceptsMouseMovedEvents)

  window.contentView = nil
  window.orderOut(nil)
}

@Test @MainActor func menuPanelHostedScreenFallbackHoldsUntilOwnedAnchorRecovery() async throws {
  let screen = try #require(NSScreen.main)
  let buttonFrame = CGRect(
    x: screen.visibleFrame.maxX - 34,
    y: screen.visibleFrame.maxY + 2,
    width: 34,
    height: 22
  )
  let initialFrame = CGRect(
    x: buttonFrame.maxX - 600,
    y: screen.visibleFrame.midY - 215,
    width: 600,
    height: 430
  )
  let fallbackVisibleFrame = CGRect(
    x: screen.visibleFrame.minX + 20,
    y: screen.visibleFrame.maxY - 370,
    width: 420,
    height: 320
  )
  let window = NSWindow(
    contentRect: initialFrame,
    styleMask: .borderless,
    backing: .buffered,
    defer: false
  )
  window.acceptsMouseMovedEvents = false
  let root = ResizeEventRecordingView(frame: CGRect(origin: .zero, size: initialFrame.size))
  let statusButton = PublicStatusButtonFixture(screenFrame: buttonFrame)
  let oldWindows = StatusWindowProvider(windows: [statusButton.window])
  let newWindows = StatusWindowProvider(windows: [])
  let oldGeometryStore = MenuPanelGeometryStore(windows: { oldWindows.windows })
  let newGeometryStore = MenuPanelGeometryStore(windows: { newWindows.windows })
  oldGeometryStore.rememberCompletedSide(.right)
  newGeometryStore.rememberCompletedSide(.right)
  let controller = MenuPanelResizeController()
  var oldCommits = 0
  var newCommits = 0
  let firstHost = MenuPanelResizeHostView(
    controller: controller,
    fallbackVisibleFrameProvider: { _ in fallbackVisibleFrame }
  )
  firstHost.frame = root.bounds
  firstHost.autoresizingMask = [.width, .height]
  firstHost.configure(
    geometryStore: oldGeometryStore,
    preferredSize: initialFrame.size,
    canResize: true,
    onCommit: { _ in oldCommits += 1 }
  )
  root.addSubview(firstHost)
  window.contentView = root
  window.orderFront(nil)
  firstHost.installIfNeeded()
  await settleResizeHost(root)

  sendResizeMouseEvent(.leftMouseDown, at: CGPoint(x: 1, y: 200), to: window, number: 83)
  let dragPoint = window.convertPoint(toScreen: CGPoint(x: -19, y: 200))
  sendResizeMouseEvent(.leftMouseDragged, atScreen: dragPoint, to: window, number: 84)
  #expect(controller.isTracking)
  oldWindows.windows = []
  sendResizeEscapeEvent(to: window, number: 85)
  #expect(!controller.isTracking)
  #expect(window.frame == fallbackVisibleFrame)
  #expect(controller.effectiveContentSize == fallbackVisibleFrame.size)

  oldWindows.windows = [statusButton.window]
  firstHost.configure(
    geometryStore: oldGeometryStore,
    preferredSize: initialFrame.size,
    canResize: true,
    onCommit: { _ in oldCommits += 1 }
  )
  await settleResizeHost(root)
  #expect(window.frame.maxX == buttonFrame.maxX)
  #expect(window.frame.maxY == fallbackVisibleFrame.maxY)
  #expect(window.frame.size == initialFrame.size)
  #expect(controller.effectiveContentSize == nil)

  sendResizeMouseEvent(.leftMouseDown, at: CGPoint(x: 1, y: 200), to: window, number: 86)
  let secondDragPoint = window.convertPoint(toScreen: CGPoint(x: -19, y: 200))
  sendResizeMouseEvent(.leftMouseDragged, atScreen: secondDragPoint, to: window, number: 87)
  #expect(controller.isTracking)
  oldWindows.windows = []

  let secondHost = MenuPanelResizeHostView(
    controller: controller,
    fallbackVisibleFrameProvider: { _ in fallbackVisibleFrame }
  )
  secondHost.frame = root.bounds
  secondHost.autoresizingMask = [.width, .height]
  secondHost.configure(
    geometryStore: newGeometryStore,
    preferredSize: CGSize(width: 800, height: 430),
    canResize: true,
    onCommit: { _ in newCommits += 1 }
  )
  root.addSubview(secondHost)
  secondHost.installIfNeeded()
  await settleResizeHost(root)

  #expect(!controller.isTracking)
  #expect(window.frame == fallbackVisibleFrame)
  #expect(
    controller.effectiveContentSize
      == window.contentRect(forFrameRect: fallbackVisibleFrame).size
  )
  #expect(oldCommits == 0)
  #expect(newCommits == 0)
  #expect(oldGeometryStore.rememberedFixedSide == .right)
  #expect(newGeometryStore.rememberedFixedSide == .right)

  secondHost.configure(
    geometryStore: newGeometryStore,
    preferredSize: CGSize(width: 800, height: 430),
    canResize: true,
    onCommit: { _ in newCommits += 1 }
  )
  await settleResizeHost(root)
  #expect(window.frame == fallbackVisibleFrame)
  #expect(controller.effectiveContentSize == fallbackVisibleFrame.size)

  firstHost.configure(
    geometryStore: oldGeometryStore,
    preferredSize: CGSize(width: 700, height: 430),
    canResize: true,
    onCommit: { _ in oldCommits += 1 }
  )
  await settleResizeHost(root)
  #expect(window.frame == fallbackVisibleFrame)
  #expect(controller.effectiveContentSize == fallbackVisibleFrame.size)
  #expect(oldCommits == 0)
  #expect(newCommits == 0)

  newWindows.windows = [statusButton.window]
  secondHost.configure(
    geometryStore: newGeometryStore,
    preferredSize: CGSize(width: 800, height: 430),
    canResize: true,
    onCommit: { _ in newCommits += 1 }
  )
  await settleResizeHost(root)
  #expect(window.frame.maxX == buttonFrame.maxX)
  #expect(window.frame.maxY == fallbackVisibleFrame.maxY)
  #expect(window.frame.size == CGSize(width: 800, height: 430))
  #expect(controller.effectiveContentSize == nil)
  #expect(newGeometryStore.rememberedFixedSide == .right)
  #expect(oldCommits == 0)
  #expect(newCommits == 0)

  firstHost.uninstall()
  secondHost.uninstall()
  window.contentView = nil
  window.orderOut(nil)
}

@Test @MainActor func menuPanelHostedFlipReleaseAppliesMinimumBeforeOneCommitAndForwardsEvents() async throws {
  let screen = try #require(NSScreen.main)
  let initialWidth = min(CGFloat(600), screen.visibleFrame.width / 2)
  let buttonFrame = CGRect(
    x: screen.visibleFrame.midX - 17,
    y: screen.visibleFrame.maxY + 2,
    width: 34,
    height: 22
  )
  let initialFrame = CGRect(
    x: buttonFrame.minX,
    y: screen.visibleFrame.midY - 215,
    width: initialWidth,
    height: 430
  )
  let window = NSWindow(
    contentRect: initialFrame,
    styleMask: .borderless,
    backing: .buffered,
    defer: false
  )
  let receiver = ResizeEventRecordingView(frame: CGRect(origin: .zero, size: initialFrame.size))
  let statusButton = PublicStatusButtonFixture(screenFrame: buttonFrame)
  let geometryStore = MenuPanelGeometryStore(windows: { [statusButton.window] })
  geometryStore.rememberCompletedSide(.left)
  let controller = MenuPanelResizeController()
  var commits: [(CGSize, CGRect, CGSize?)] = []
  let host = MenuPanelResizeHostView(controller: controller)
  host.frame = receiver.bounds
  host.autoresizingMask = [.width, .height]
  host.configure(
    geometryStore: geometryStore,
    preferredSize: initialFrame.size,
    canResize: true,
    onCommit: { commits.append(($0, window.frame, controller.effectiveContentSize)) }
  )
  receiver.addSubview(host)
  window.contentView = receiver
  window.orderFront(nil)
  #expect(window.makeFirstResponder(receiver))
  host.installIfNeeded()
  await settleResizeHost(host)

  sendResizeMouseEvent(.leftMouseDown, at: CGPoint(x: 300, y: 200), to: window, number: 70)
  sendResizeMouseEvent(.leftMouseUp, at: CGPoint(x: 300, y: 200), to: window, number: 71)
  #expect(receiver.received == [.leftMouseDown, .leftMouseUp])
  receiver.received.removeAll()

  sendResizeMouseEvent(
    .leftMouseDown,
    at: CGPoint(x: host.bounds.maxX - 1, y: host.bounds.midY),
    to: window,
    number: 72
  )
  let rightFlipScreenPoint = window.convertPoint(toScreen: CGPoint(x: 10, y: 200))
  sendResizeMouseEvent(.leftMouseDragged, atScreen: rightFlipScreenPoint, to: window, number: 73)
  #expect(window.frame.minX == buttonFrame.minX)
  #expect(window.frame.maxX == buttonFrame.maxX)
  sendResizeMouseEvent(.leftMouseUp, atScreen: rightFlipScreenPoint, to: window, number: 74)

  #expect(commits.count == 1)
  #expect(commits.first?.0 == CGSize(width: 380, height: 430))
  #expect(commits.first?.1.maxX == buttonFrame.maxX)
  #expect(commits.first?.1.width == 380)
  #expect(commits.first?.2 == CGSize(width: 380, height: 430))
  #expect(geometryStore.rememberedFixedSide == .right)
  #expect(receiver.received.isEmpty)
  sendResizeMouseEvent(.leftMouseUp, atScreen: rightFlipScreenPoint, to: window, number: 75)
  #expect(commits.count == 1)

  host.configure(
    geometryStore: geometryStore,
    preferredSize: CGSize(width: 380, height: 430),
    canResize: true,
    onCommit: { commits.append(($0, window.frame, controller.effectiveContentSize)) }
  )
  await settleResizeHost(host)
  sendResizeMouseEvent(.leftMouseDown, at: CGPoint(x: 1, y: 200), to: window, number: 76)
  let leftFlipScreenPoint = window.convertPoint(toScreen: CGPoint(x: 370, y: 200))
  sendResizeMouseEvent(.leftMouseDragged, atScreen: leftFlipScreenPoint, to: window, number: 77)
  #expect(window.frame.minX == buttonFrame.minX)
  #expect(window.frame.maxX == buttonFrame.maxX)
  sendResizeMouseEvent(.leftMouseUp, atScreen: leftFlipScreenPoint, to: window, number: 78)
  #expect(commits.count == 2)
  #expect(commits.last?.0 == CGSize(width: 380, height: 430))
  #expect(commits.last?.1.minX == buttonFrame.minX)
  #expect(commits.last?.1.width == 380)
  #expect(commits.last?.2 == CGSize(width: 380, height: 430))
  #expect(geometryStore.rememberedFixedSide == .left)

  host.uninstall()
  window.contentView = nil
  window.orderOut(nil)
}

@Test @MainActor func notesPanelConstrainedNoOpResizePreservesStoredPreferenceAndRealResizeSavesOnce() async throws {
  let screen = try #require(NSScreen.main)
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let saveProbe = MenuPanelPreferenceSaveProbe()
  let state = AppState(
    store: LocalStore(rootURL: root),
    saveOperation: { _, preferences, _, _ in
      await saveProbe.record(preferences)
      return .committed
    }
  )
  await state.waitUntilInitialLoad()
  let storedSize = CGSize(width: 1_240, height: screen.visibleFrame.height + 200)
  state.preferences.panelWidth = storedSize.width
  state.preferences.panelHeight = storedSize.height

  let buttonFrame = CGRect(
    x: screen.visibleFrame.midX - 17,
    y: screen.visibleFrame.maxY + 2,
    width: 34,
    height: 22
  )
  let statusButton = PublicStatusButtonFixture(screenFrame: buttonFrame)
  let geometryStore = MenuPanelGeometryStore(windows: { [statusButton.window] })
  geometryStore.rememberCompletedSide(.right)
  let runtime = DictationRuntime(appState: state, applicationSupportURL: root)
  let panel = NotesPanel(dictationRuntime: runtime, sizing: .storedPreferences)
    .environmentObject(state)
    .environment(\.menuPanelGeometryStore, geometryStore)
  let host = NSHostingView(rootView: panel)
  let initialWindowSize = CGSize(
    width: min(500, screen.visibleFrame.width),
    height: min(500, screen.visibleFrame.height)
  )
  let window = NSWindow(
    contentRect: CGRect(
      x: screen.visibleFrame.midX - initialWindowSize.width / 2,
      y: screen.visibleFrame.midY - initialWindowSize.height / 2,
      width: initialWindowSize.width,
      height: initialWindowSize.height
    ),
    styleMask: .borderless,
    backing: .buffered,
    defer: false
  )
  window.contentView = host
  window.orderFront(nil)
  defer {
    window.contentView = nil
    window.orderOut(nil)
  }
  await settleResizeHost(host)

  let resizeHost = try #require(
    resizeDescendants(in: host, as: MenuPanelResizeHostView.self).first
  )
  let displayedSize = window.contentRect(forFrameRect: window.frame).size
  #expect(displayedSize != storedSize)
  #expect(displayedSize.width > MenuPanelResizeGeometry.minimumContentSize.width + 40)
  #expect(displayedSize.height >= MenuPanelResizeGeometry.minimumContentSize.height)
  let fixedSide = try #require(
    MenuPanelResizeGeometry.anchoredSide(
      panelFrame: window.frame,
      statusLabelFrame: buttonFrame
    )
  )

  func farSidePointInWindow() -> CGPoint {
    resizeHost.convert(
      CGPoint(
        x: fixedSide == .left ? resizeHost.bounds.maxX - 1 : resizeHost.bounds.minX + 1,
        y: resizeHost.bounds.midY
      ),
      to: nil
    )
  }

  var eventNumber = 90
  func send(_ type: NSEvent.EventType, at point: CGPoint) {
    eventNumber += 1
    sendResizeMouseEvent(type, at: point, to: window, number: eventNumber)
  }
  func send(_ type: NSEvent.EventType, atScreen point: CGPoint) {
    eventNumber += 1
    sendResizeMouseEvent(type, atScreen: point, to: window, number: eventNumber)
  }

  var start = farSidePointInWindow()
  send(.leftMouseDown, at: start)
  send(.leftMouseUp, at: start)
  await settleResizeHost(host)
  try await Task.sleep(for: .milliseconds(400))
  #expect(await saveProbe.preferences().isEmpty)
  #expect(state.preferences.panelWidth == Double(storedSize.width))
  #expect(state.preferences.panelHeight == Double(storedSize.height))
  #expect(geometryStore.rememberedFixedSide == fixedSide)

  start = farSidePointInWindow()
  let startOnScreen = window.convertPoint(toScreen: start)
  let roundTripInward = CGPoint(
    x: startOnScreen.x + (fixedSide == .left ? -40 : 40),
    y: startOnScreen.y
  )
  send(.leftMouseDown, at: start)
  send(.leftMouseDragged, atScreen: roundTripInward)
  let intermediateSize = window.contentRect(forFrameRect: window.frame).size
  #expect(intermediateSize.width < displayedSize.width)
  #expect(intermediateSize.width >= MenuPanelResizeGeometry.minimumContentSize.width)
  send(.leftMouseDragged, atScreen: startOnScreen)
  send(.leftMouseUp, atScreen: startOnScreen)
  await settleResizeHost(host)
  #expect(window.contentRect(forFrameRect: window.frame).size == displayedSize)
  try await Task.sleep(for: .milliseconds(400))
  #expect(await saveProbe.preferences().isEmpty)
  #expect(state.preferences.panelWidth == Double(storedSize.width))
  #expect(state.preferences.panelHeight == Double(storedSize.height))
  #expect(geometryStore.rememberedFixedSide == fixedSide)

  start = farSidePointInWindow()
  let finalStartOnScreen = window.convertPoint(toScreen: start)
  let inward = CGPoint(
    x: finalStartOnScreen.x + (fixedSide == .left ? -40 : 40),
    y: finalStartOnScreen.y
  )
  send(.leftMouseDown, at: start)
  send(.leftMouseDragged, atScreen: inward)
  send(.leftMouseUp, atScreen: inward)
  await settleResizeHost(host)
  let savedPreferences = try await waitForMenuPanelPreferenceSaves(saveProbe, count: 1)
  let finalSize = window.contentRect(forFrameRect: window.frame).size
  #expect(savedPreferences.count == 1)
  #expect(savedPreferences[0].panelWidth == Double(finalSize.width))
  #expect(savedPreferences[0].panelHeight == Double(finalSize.height))
  #expect(finalSize.width < displayedSize.width)
  #expect(finalSize.width >= MenuPanelResizeGeometry.minimumContentSize.width)
  #expect(state.preferences.panelWidth == Double(finalSize.width))
  #expect(state.preferences.panelHeight == Double(finalSize.height))
  #expect(geometryStore.rememberedFixedSide == fixedSide)
  await runtime.shutdown()
}

@Test @MainActor func menuPanelHostedMouseUpUsesFreshScreenPointer() async throws {
  let screen = try #require(NSScreen.main)
  let initialFrame = CGRect(
    x: screen.visibleFrame.midX - 300,
    y: screen.visibleFrame.midY - 215,
    width: 600,
    height: 430
  )
  let window = NSWindow(
    contentRect: initialFrame,
    styleMask: .borderless,
    backing: .buffered,
    defer: false
  )
  let buttonFrame = CGRect(
    x: initialFrame.maxX - 34,
    y: initialFrame.maxY + 20,
    width: 34,
    height: 22
  )
  let statusButton = PublicStatusButtonFixture(screenFrame: buttonFrame)
  let geometryStore = MenuPanelGeometryStore(windows: { [statusButton.window] })
  var committed: [CGSize] = []
  let host = MenuPanelResizeHostView(controller: MenuPanelResizeController())
  host.configure(
    geometryStore: geometryStore,
    preferredSize: initialFrame.size,
    canResize: true,
    onCommit: { committed.append($0) }
  )
  window.contentView = host
  window.orderFront(nil)
  host.installIfNeeded()
  await settleResizeHost(host)

  let dragPoint = CGPoint(x: initialFrame.minX - 39, y: initialFrame.minY + 200)
  let releasePoint = CGPoint(x: initialFrame.minX - 59, y: initialFrame.minY + 200)
  sendResizeMouseEvent(.leftMouseDown, at: CGPoint(x: 1, y: 200), to: window, number: 80)
  sendResizeMouseEvent(.leftMouseDragged, atScreen: dragPoint, to: window, number: 81)
  #expect(window.frame.width == 640)
  sendResizeMouseEvent(.leftMouseUp, atScreen: releasePoint, to: window, number: 82)
  #expect(committed == [CGSize(width: 660, height: 430)])
  #expect(window.frame.maxX == buttonFrame.maxX)

  host.uninstall()
  window.contentView = nil
  window.orderOut(nil)
}

@Test @MainActor func menuPanelHostedRejectedFinalFrameRestoresWithoutCommit() async throws {
  let screen = try #require(NSScreen.main)
  let initialWidth = min(CGFloat(600), screen.visibleFrame.width / 2)
  let buttonFrame = CGRect(
    x: screen.visibleFrame.midX - 17,
    y: screen.visibleFrame.maxY + 2,
    width: 34,
    height: 22
  )
  let initialFrame = CGRect(
    x: buttonFrame.minX,
    y: screen.visibleFrame.midY - 215,
    width: initialWidth,
    height: 430
  )
  let window = FinalFrameRejectingWindow(
    contentRect: initialFrame,
    styleMask: .borderless,
    backing: .buffered,
    defer: false
  )
  let statusButton = PublicStatusButtonFixture(screenFrame: buttonFrame)
  let geometryStore = MenuPanelGeometryStore(windows: { [statusButton.window] })
  geometryStore.rememberCompletedSide(.left)
  let controller = MenuPanelResizeController()
  var committed: [CGSize] = []
  let host = MenuPanelResizeHostView(controller: controller)
  host.configure(
    geometryStore: geometryStore,
    preferredSize: initialFrame.size,
    canResize: true,
    onCommit: { committed.append($0) }
  )
  window.contentView = host
  window.orderFront(nil)
  host.installIfNeeded()
  await settleResizeHost(host)

  let bandPoint = CGPoint(x: buttonFrame.minX + 10, y: initialFrame.minY + 200)
  sendResizeMouseEvent(
    .leftMouseDown,
    at: CGPoint(x: host.bounds.maxX - 1, y: host.bounds.midY),
    to: window,
    number: 83
  )
  sendResizeMouseEvent(.leftMouseDragged, atScreen: bandPoint, to: window, number: 84)
  window.rejectedFrame = CGRect(
    x: buttonFrame.maxX - 380,
    y: initialFrame.minY,
    width: 380,
    height: 430
  )
  sendResizeMouseEvent(.leftMouseUp, atScreen: bandPoint, to: window, number: 85)
  #expect(committed.isEmpty)
  #expect(window.frame == initialFrame)
  #expect(geometryStore.rememberedFixedSide == .left)
  #expect(controller.effectiveContentSize == nil)

  host.uninstall()
  window.contentView = nil
  window.orderOut(nil)
}

@Test func notesPanelResizeGateObservesLiveReorderPhaseInsteadOfRetainedReference() throws {
  let source = try String(
    contentsOf: menuPanelRepositoryRoot()
      .appendingPathComponent("Sources/FleckApp/NotesPanel.swift"),
    encoding: .utf8
  )
  let availability = try #require(
    source.components(separatedBy: "private var allowsMenuPanelResize").last?
      .components(separatedBy: "private var preferredMenuPanelSize").first
  )
  #expect(!availability.contains("reorderDragSession == nil"))
  #expect(source.contains("if let reorderDragSession {"))
  #expect(source.contains("ReorderAwareMenuPanelResizeInstaller("))
}

@Test @MainActor func externalPreferredSizeChangeCancelsAnActiveGesture() async throws {
  let snapshot = try #require(resizeSnapshot(fixedSide: .left))
  let controller = MenuPanelResizeController()
  let host = MenuPanelResizeHostView(controller: controller)
  host.configure(
    geometryStore: nil,
    preferredSize: snapshot.initialContentSize,
    canResize: true,
    onCommit: { _ in }
  )
  #expect(controller.begin(snapshot: snapshot, handle: .farSide))
  host.configure(
    geometryStore: nil,
    preferredSize: CGSize(width: 500, height: 430),
    canResize: true,
    onCommit: { _ in }
  )
  await Task.yield()
  #expect(!controller.isTracking)
  #expect(controller.effectiveContentSize == nil)
}

@Test @MainActor func menuPanelCornerCursorsAreReusedAndSwitchWithTheFixedSide() {
  let host = MenuPanelResizeHostView(controller: MenuPanelResizeController())
  let left = host.cursor(for: .farBottomCorner, fixedSide: .left)
  let right = host.cursor(for: .farBottomCorner, fixedSide: .right)

  #expect(host.cursor(for: .farBottomCorner, fixedSide: .left) === left)
  #expect(host.cursor(for: .farBottomCorner, fixedSide: .right) === right)
  #expect(left !== right)
  #expect(host.cursor(for: .farSide, fixedSide: .left) === NSCursor.resizeLeftRight)
  #expect(host.cursor(for: .nearBottomCorner, fixedSide: .right) === NSCursor.resizeUpDown)
}

@Test @MainActor func menuPanelHostedLiveDragDefersDisplayButReleaseAndCancelDoNot() async throws {
  let screen = try #require(NSScreen.main)
  let buttonFrame = CGRect(
    x: screen.visibleFrame.maxX - 40 - 34,
    y: screen.visibleFrame.maxY + 2,
    width: 34,
    height: 22
  )
  let initialFrame = CGRect(
    x: buttonFrame.maxX - 520,
    y: screen.visibleFrame.maxY - 500,
    width: 520,
    height: 400
  )
  let window = DisplayRecordingWindow(
    contentRect: initialFrame,
    styleMask: .borderless,
    backing: .buffered,
    defer: false
  )
  window.displayImmediatelyFlags.removeAll()
  let statusButton = PublicStatusButtonFixture(screenFrame: buttonFrame)
  let geometryStore = MenuPanelGeometryStore(windows: { [statusButton.window] })
  geometryStore.rememberCompletedSide(.right)
  let controller = MenuPanelResizeController()
  var committed: [CGSize] = []
  let host = MenuPanelResizeHostView(controller: controller)
  host.configure(
    geometryStore: geometryStore,
    preferredSize: CGSize(width: 600, height: 430),
    canResize: true,
    onCommit: { committed.append($0) }
  )
  window.contentView = host
  window.orderFront(nil)
  host.installIfNeeded()
  defer {
    host.uninstall()
    window.contentView = nil
    window.orderOut(nil)
  }
  await settleResizeHost(host)

  #expect(window.displayImmediatelyFlags.contains(true))
  window.displayImmediatelyFlags.removeAll()

  var eventNumber = 4_000
  let startingFrame = window.frame
  sendResizeMouseEvent(
    .leftMouseDown,
    at: CGPoint(x: 0.625, y: 200.625),
    to: window,
    number: eventNumber
  )
  eventNumber += 1
  sendResizeMouseEvent(
    .leftMouseDragged,
    atScreen: CGPoint(x: startingFrame.minX - 40.375, y: startingFrame.minY + 200.625),
    to: window,
    number: eventNumber
  )
  eventNumber += 1
  #expect(window.displayImmediatelyFlags.last == false)
  sendResizeMouseEvent(
    .leftMouseUp,
    atScreen: CGPoint(x: startingFrame.minX - 60.375, y: startingFrame.minY + 200.625),
    to: window,
    number: eventNumber
  )
  eventNumber += 1
  #expect(window.displayImmediatelyFlags.last == true)
  #expect(committed.count == 1)

  let committedFrame = window.frame
  await settleResizeHost(host)
  #expect(window.frame == committedFrame)
  window.displayImmediatelyFlags.removeAll()
  sendResizeMouseEvent(
    .leftMouseDown,
    at: CGPoint(x: 0.625, y: 200.625),
    to: window,
    number: eventNumber
  )
  eventNumber += 1
  #expect(controller.isTracking)
  sendResizeMouseEvent(
    .leftMouseDragged,
    atScreen: CGPoint(x: committedFrame.minX - 20.375, y: committedFrame.minY + 200.625),
    to: window,
    number: eventNumber
  )
  eventNumber += 1
  #expect(window.displayImmediatelyFlags.last == false)
  sendResizeEscapeEvent(to: window, number: eventNumber)
  #expect(window.displayImmediatelyFlags.last == true)
  #expect(window.frame == committedFrame)
  #expect(committed.count == 1)
}

private func resizeSnapshot(fixedSide: MenuPanelFixedSide) -> MenuPanelResizeSnapshot? {
  MenuPanelResizeSnapshot(
    initialPointer: fixedSide == .right
      ? CGPoint(x: 100, y: 100)
      : CGPoint(x: 700, y: 100),
    initialFrame: CGRect(x: 100, y: 100, width: 600, height: 430),
    initialContentSize: CGSize(width: 600, height: 430),
    frameInsets: .zero,
    visibleFrame: CGRect(x: 0, y: 0, width: 1_200, height: 900),
    statusLabelFrame: fixedSide == .right
      ? CGRect(x: 680, y: 880, width: 20, height: 20)
      : CGRect(x: 100, y: 880, width: 20, height: 20),
    fixedSide: fixedSide
  )
}

private enum ResizeDragKind {
  case note
  case folder
}

private enum ResizeEndStatusMutation: CaseIterable {
  case ambiguity
  case buttonReplacement
  case ownerReplacement
}

@MainActor
private func reorderSessionFixture(kind: ResizeDragKind) throws -> (ReorderDropSession, Data) {
  switch kind {
  case .note:
    let source = NoteDropSource(noteID: UUID(), sourceFolderID: nil)
    return (ReorderDropSession(source: source), try JSONEncoder().encode(source))
  case .folder:
    let source = FolderDragPayload.FolderValue(folderID: UUID(), sessionID: UUID())
    return (ReorderDropSession(folder: source), try JSONEncoder().encode(source))
  }
}

private func menuPanelRepositoryRoot() -> URL {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
}

@MainActor
private final class ResizeEventRecordingView: NSView {
  var received: [NSEvent.EventType] = []

  override var acceptsFirstResponder: Bool { true }

  override func mouseDown(with event: NSEvent) {
    received.append(event.type)
  }

  override func mouseDragged(with event: NSEvent) {
    received.append(event.type)
  }

  override func mouseUp(with event: NSEvent) {
    received.append(event.type)
  }

  override func keyDown(with event: NSEvent) {
    received.append(event.type)
  }
}

@MainActor
private final class FinalFrameRejectingWindow: NSWindow {
  var rejectedFrame: CGRect?

  override func setFrame(_ frameRect: NSRect, display flag: Bool, animate: Bool) {
    guard frameRect != rejectedFrame else { return }
    super.setFrame(frameRect, display: flag, animate: animate)
  }
}

@MainActor
private final class DisplayRecordingWindow: NSWindow {
  var displayImmediatelyFlags: [Bool] = []

  override func setFrame(_ frameRect: NSRect, display flag: Bool, animate: Bool) {
    displayImmediatelyFlags.append(flag)
    super.setFrame(frameRect, display: flag, animate: animate)
  }
}

@MainActor
private final class PublicStatusButtonFixture {
  let window: NSWindow
  let root: NSView
  private(set) var container: NSView
  private(set) var button: NSStatusBarButton
  let countingRoot: CountingSubviewReadsView?

  init(screenFrame: CGRect, countsSubviewReads: Bool = false) {
    let windowFrame = CGRect(
      x: screenFrame.minX - 10,
      y: screenFrame.minY - 6,
      width: max(screenFrame.width + 20, 80),
      height: max(screenFrame.height + 12, 40)
    )
    window = NSWindow(
      contentRect: windowFrame,
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    if countsSubviewReads {
      let countingRoot = CountingSubviewReadsView(
        frame: CGRect(origin: .zero, size: windowFrame.size)
      )
      root = countingRoot
      self.countingRoot = countingRoot
    } else {
      root = NSView(frame: CGRect(origin: .zero, size: windowFrame.size))
      countingRoot = nil
    }
    container = NSView(frame: root.bounds)
    button = NSStatusBarButton(
      frame: CGRect(
        x: 10,
        y: 6,
        width: screenFrame.width,
        height: screenFrame.height
      )
    )
    container.addSubview(button)
    root.addSubview(container)
    window.contentView = root
  }

  func detachButton() {
    button.removeFromSuperview()
  }

  func reparentButton() {
    let replacement = NSView(frame: root.bounds)
    button.removeFromSuperview()
    replacement.addSubview(button)
    root.addSubview(replacement)
    container = replacement
  }

  func replaceButtonAtSameFrame() {
    let replacement = NSStatusBarButton(frame: button.frame)
    button.removeFromSuperview()
    container.addSubview(replacement)
    button = replacement
  }

  func moveButton(to fixture: PublicStatusButtonFixture) {
    button.removeFromSuperview()
    button.frame = fixture.button.frame
    fixture.container.addSubview(button)
  }
}

@MainActor
private final class CountingSubviewReadsView: NSView {
  private(set) var subviewReads = 0

  override var subviews: [NSView] {
    get {
      subviewReads += 1
      return super.subviews
    }
    set { super.subviews = newValue }
  }
}

@MainActor
private final class StatusWindowProvider {
  var windows: [NSWindow]

  init(windows: [NSWindow]) {
    self.windows = windows
  }
}

private actor MenuPanelPreferenceSaveProbe {
  private var savedPreferences: [AppPreferences] = []

  func record(_ preferences: AppPreferences) {
    savedPreferences.append(preferences)
  }

  func preferences() -> [AppPreferences] {
    savedPreferences
  }
}

private func waitForMenuPanelPreferenceSaves(
  _ probe: MenuPanelPreferenceSaveProbe,
  count: Int
) async throws -> [AppPreferences] {
  let deadline = ContinuousClock.now + .seconds(2)
  while await probe.preferences().count < count, ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(10))
  }
  return await probe.preferences()
}

@MainActor
private final class WeakStatusButtonReference {
  weak var value: NSStatusBarButton?
}

@MainActor
private func sendResizeMouseEvent(
  _ type: NSEvent.EventType,
  at location: CGPoint,
  to window: NSWindow,
  number: Int
) {
  guard let event = NSEvent.mouseEvent(
    with: type,
    location: location,
    modifierFlags: [],
    timestamp: TimeInterval(number) / 100,
    windowNumber: window.windowNumber,
    context: nil,
    eventNumber: number,
    clickCount: 1,
    pressure: type == .leftMouseUp ? 0 : 1
  ) else {
    Issue.record("Could not create \(type) event")
    return
  }
  NSApplication.shared.sendEvent(event)
}

@MainActor
private func sendResizeMouseEvent(
  _ type: NSEvent.EventType,
  atScreen location: CGPoint,
  to window: NSWindow,
  number: Int
) {
  sendResizeMouseEvent(
    type,
    at: window.convertPoint(fromScreen: location),
    to: window,
    number: number
  )
}

@MainActor
private func sendResizeEscapeEvent(to window: NSWindow, number: Int) {
  guard let event = NSEvent.keyEvent(
    with: .keyDown,
    location: .zero,
    modifierFlags: [],
    timestamp: TimeInterval(number) / 100,
    windowNumber: window.windowNumber,
    context: nil,
    characters: "\u{1B}",
    charactersIgnoringModifiers: "\u{1B}",
    isARepeat: false,
    keyCode: 53
  ) else {
    Issue.record("Could not create Escape event")
    return
  }
  NSApplication.shared.sendEvent(event)
}

@MainActor
private func resizeDescendants<T: NSView>(in view: NSView, as type: T.Type) -> [T] {
  var matches: [T] = []
  if let match = view as? T { matches.append(match) }
  for child in view.subviews {
    matches.append(contentsOf: resizeDescendants(in: child, as: type))
  }
  return matches
}

@MainActor
private func settleResizeHost(_ view: NSView) async {
  for _ in 0..<5 {
    view.layoutSubtreeIfNeeded()
    await Task.yield()
  }
}
