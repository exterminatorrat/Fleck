import AppKit
import FleckCore
import Testing

@testable import FleckApp

private func capsuleContext(
  _ status: DictationCapsuleStatus,
  sessionID: UUID = UUID(uuidString: "A4D2C8B4-7C8A-4A6B-B7CC-06C2B3F2C1D1")!,
  mode: DictationMode? = .smartCapture,
  stage: DictationPipelineStage? = .capture,
  cleanup: DictationCleanupOutcome? = nil,
  failureStage: DictationPipelineStage? = nil
) -> DictationCapsuleContext {
  DictationCapsuleContext(
    status: status,
    sessionID: sessionID,
    trigger: .pointer,
    mode: mode,
    isHandsFree: true,
    pipelineStage: stage,
    cleanupOutcome: cleanup,
    failureStage: failureStage
  )
}

@Test @MainActor func DictationAccessibilityUsesApprovedStatusTiersAndCopy() {
  let expected: [(DictationCapsuleStatus, CGSize, String?)] = [
    (.idle, CGSize(width: 46, height: 24), nil),
    (.arming, CGSize(width: 46, height: 24), nil),
    (.listening, CGSize(width: 176, height: 36), nil),
    (.finalizing, CGSize(width: 192, height: 36), "Finishing"),
    (.cleaning, CGSize(width: 192, height: 36), "Polishing"),
    (.routing, CGSize(width: 192, height: 36), "Organizing"),
    (.saving, CGSize(width: 192, height: 36), "Saving"),
    (.saved(destination: "Inbox"), CGSize(width: 264, height: 36), "Saved to Inbox"),
    (
      .savedWithoutCleanup(destination: "Inbox"),
      CGSize(width: 288, height: 36),
      "Saved original to Inbox"
    ),
    (.noSpeech, CGSize(width: 192, height: 36), "No speech heard"),
    (.repairingModel, CGSize(width: 224, height: 36), "Repairing enhanced model"),
    (.failed("Microphone unavailable"), CGSize(width: 264, height: 36), "Dictation failed"),
    (.failed("save failed"), CGSize(width: 264, height: 36), "Dictation failed"),
  ]

  for (status, size, visibleText) in expected {
    #expect(DictationCapsuleController.size(for: status) == size)
    #expect(status.presentation.visibleText == visibleText)
    #expect(!status.presentation.voiceOverText.isEmpty)
  }
}

@Test func DictationAccessibilityKeepsResultWidthsAtTheirCeilings() {
  let destination = String(repeating: "A very long destination ", count: 20)
  let saved = DictationCapsulePresentation(
    status: .saved(destination: destination),
    action: .undo
  )
  let fallback = DictationCapsulePresentation(
    status: .savedWithoutCleanup(destination: destination),
    action: .copy
  )

  #expect(saved.measuredWidth <= saved.widthCeiling)
  #expect(fallback.measuredWidth <= fallback.widthCeiling)
  #expect(saved.visibleText?.contains("…") == true)
  #expect(fallback.visibleText?.contains("…") == true)
  #expect(DictationCapsulePresentation.actionDividerSize == CGSize(width: 1, height: 16))
}

@Test @MainActor func DictationAccessibilityResultSizingUsesControllerFrameSource() {
  let visibleFrame = CGRect(x: 100, y: 200, width: 1_000, height: 800)
  let results: [(DictationCapsuleStatus, DictationCapsuleAction, CGSize)] = [
    (.saved(destination: "Inbox"), .undo, CGSize(width: 264, height: 36)),
    (
      .savedWithoutCleanup(destination: "Inbox"),
      .copy,
      CGSize(width: 288, height: 36)
    ),
  ]

  for (status, action, expectedSize) in results {
    let size = DictationCapsuleController.size(for: status)
    let frame = DictationCapsuleController.frame(
      for: .bottom,
      size: size,
      in: visibleFrame
    )
    let presentation = DictationCapsulePresentation(status: status, action: action)

    #expect(size == expectedSize)
    #expect(frame.size == expectedSize)
    #expect(presentation.widthCeiling == frame.width)
    #expect(presentation.measuredWidth <= frame.width)
  }
}

@Test func DictationAccessibilityUsesAuthoritativePipelineTreatment() {
  let focusedSave = capsuleContext(
    .saving,
    mode: .focused,
    stage: .save
  )
  #expect(FleckRailStageTreatment.forContext(focusedSave) == [
    .complete, .complete, .skipped, .active,
  ])

  let fallbackSave = capsuleContext(
    .saving,
    mode: .smartCapture,
    stage: .save,
    cleanup: .usedRaw
  )
  #expect(FleckRailStageTreatment.forContext(fallbackSave) == [
    .complete, .fallback, .complete, .active,
  ])

  let failed = capsuleContext(
    .failed("save failed"),
    mode: .smartCapture,
    stage: .save,
    failureStage: .organize
  )
  #expect(FleckRailStageTreatment.forContext(failed) == [
    .complete, .complete, .failed, .pending,
  ])
}

@Test func DictationAccessibilityPreservesModeWhenFailureStageMatches() {
  let focused = capsuleContext(
    .failed("save failed"),
    sessionID: UUID(uuidString: "8B49C27B-3CBB-4BA6-9BF3-ADAA0371B7DE")!,
    mode: .focused,
    stage: .save,
    failureStage: .save
  )
  let smart = capsuleContext(
    .failed("save failed"),
    sessionID: UUID(uuidString: "C0A5FD5D-6C93-4CA7-9E1F-5B9D0D6E32DB")!,
    mode: .smartCapture,
    stage: .save,
    failureStage: .save
  )

  #expect(FleckRailStageTreatment.forContext(focused)[2] == .skipped)
  #expect(FleckRailStageTreatment.forContext(smart)[2] == .complete)
  #expect(focused.sessionID != smart.sessionID)
}

@Test func DictationAccessibilityUsesAuthoritativeStagesForMismatchedAndEarlyFailures() {
  let mismatched = capsuleContext(
    .saving,
    mode: .smartCapture,
    stage: .polish
  )
  #expect(FleckRailStageTreatment.forContext(mismatched) == [
    .complete, .active, .pending, .pending,
  ])

  let earlyFailure = capsuleContext(
    .failed("capture failed"),
    mode: .smartCapture,
    stage: .capture,
    failureStage: .capture
  )
  #expect(FleckRailStageTreatment.forContext(earlyFailure) == [
    .failed, .pending, .pending, .pending,
  ])

  let focusedOrganizeFailure = capsuleContext(
    .failed("organize failed"),
    mode: .focused,
    stage: .organize,
    failureStage: .organize
  )
  #expect(FleckRailStageTreatment.forContext(focusedOrganizeFailure) == [
    .complete, .complete, .failed, .pending,
  ])

  let polishFailureWithFallback = capsuleContext(
    .failed("polish failed"),
    mode: .smartCapture,
    stage: .polish,
    cleanup: .usedRaw,
    failureStage: .polish
  )
  #expect(FleckRailStageTreatment.forContext(polishFailureWithFallback) == [
    .complete, .failed, .pending, .pending,
  ])
}

@Test func DictationAccessibilityUsesFailureStageAndPreservesTechnicalDetail() {
  let captureFailure = DictationCapsulePresentation(
    status: .failed("unrelated capture detail"),
    context: capsuleContext(
      .failed("unrelated capture detail"),
      stage: .capture,
      failureStage: .capture
    )
  )
  #expect(captureFailure.visibleText == "Microphone access needed")
  #expect(captureFailure.voiceOverText.contains("unrelated capture detail"))

  let saveFailure = DictationCapsulePresentation(
    status: .failed("unrelated capture detail"),
    context: capsuleContext(
      .failed("unrelated capture detail"),
      stage: .save,
      failureStage: .save
    )
  )
  #expect(saveFailure.visibleText == "Couldn't save")
  #expect(saveFailure.voiceOverText.contains("unrelated capture detail"))

  let unknownFailure = DictationCapsulePresentation(
    status: .failed("permission denied"),
    context: capsuleContext(
      .failed("permission denied"),
      stage: nil,
      failureStage: nil
    )
  )
  #expect(unknownFailure.visibleText == "Dictation failed")
  #expect(unknownFailure.voiceOverText.contains("permission denied"))
}

@Test @MainActor func DictationAccessibilityDrawsStableFourTileFleckMark() {
  #expect(FleckRailMark.frameSize == CGSize(width: 14, height: 14))
  #expect(FleckRailMark.tileIDs == [0, 1, 2, 3])
  #expect(FleckRailMark.tileFrames.count == 4)
  #expect(FleckRailMark.tileFrames.allSatisfy { $0.width == 6 && $0.height == 6 })
  #expect(FleckRailMark.tileFrames[1].minX - FleckRailMark.tileFrames[0].maxX == 2)
  #expect(FleckRailMark.tileFrames[2].minY - FleckRailMark.tileFrames[0].maxY == 2)
  #expect(FleckRailMark.innerHighlightThickness == 1)
}

@Test @MainActor func DictationAccessibilityPreservesFleckTileIdentityAcrossLayouts() {
  #expect(FleckRailMark.tileOrder(reversed: false) == [0, 1, 2, 3])
  #expect(FleckRailMark.tileOrder(reversed: true) == [3, 2, 1, 0])
  #expect(FleckRailMark.layoutFrameSize(for: .mark) == CGSize(width: 14, height: 14))
  #expect(
    FleckRailMark.layoutFrameSize(for: .rail(reversed: false))
      == CGSize(width: 30, height: 14)
  )
  #expect(FleckRailContentOrder.processing(for: .left) == [.mark, .statusText])
  #expect(FleckRailContentOrder.processing(for: .right) == [.statusText, .mark])
}

@Test func DictationAccessibilityFailedTileUsesColorAndShape() {
  #expect(FleckRailStageTreatment.failed.usesFailureColor)
  #expect(FleckRailStageTreatment.failed.usesDiagonal)
  #expect(!FleckRailStageTreatment.pending.usesFailureColor)
  #expect(!FleckRailStageTreatment.pending.usesDiagonal)
}

@Test func DictationAccessibilityPersistentHostLeavesGestureRoutingToDescendants() throws {
  let sourceRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let source = try String(
    contentsOf: sourceRoot.appendingPathComponent("Sources/FleckApp/DictationCapsule.swift"),
    encoding: .utf8
  )
  let host = source.components(separatedBy: "private final class DictationCapsuleHostingView").last ?? ""

  #expect(!host.contains("override func mouseDown"))
  #expect(!host.contains("performDrag(with:"))
  #expect(host.contains("return path.contains(point) ? super.hitTest(point) : nil"))
}

@Test func DictationAccessibilityResolvesContrastSafeFleckColors() {
  let colors = FleckRailColors()
  #expect(colors.accentHex == "#7C6CF2")
  #expect(colors.displayCoreHex == "#7C6CF2")
  #expect(colors.displayLiveHex == "#A79DFF")
  #expect(colors.shellHex == "#17151C")
  #expect(colors.shellOpacity == 0.96)
  #expect(FleckRailColors.contrastRatio(colors.displayCore, against: colors.shell) >= 3)
  #expect(FleckRailColors.contrastRatio(colors.displayLive, against: colors.shell) >= 3)

  let custom = FleckRailColors(accentHex: "#302040")
  #expect(custom.accentHex == "#302040")
  #expect(custom.displayCoreHex != custom.accentHex)
  #expect(FleckRailColors.contrastRatio(custom.displayCore, against: custom.shell) >= 3)
  #expect(FleckRailColors.contrastRatio(custom.displayLive, against: custom.shell) >= 3)
}

@Test func DictationAccessibilityMapsIncreaseContrastWithoutColorDifferentiation() {
  #expect(FleckRailAccessibility.usesIncreasedContrast(.increased))
  #expect(!FleckRailAccessibility.usesIncreasedContrast(.standard))
}

@Test @MainActor func DictationAccessibilityUsesHorizontalDockGeometryWithTenPointInset() {
  let visibleFrame = CGRect(x: 100, y: 200, width: 1_000, height: 800)
  let expectedSize = CGSize(width: 192, height: 36)

  #expect(DictationCapsuleController.edgeInset == 10)
  let bottom = DictationCapsuleController.frame(
    for: .bottom,
    size: expectedSize,
    in: visibleFrame
  )
  let left = DictationCapsuleController.frame(
    for: .left,
    size: expectedSize,
    in: visibleFrame
  )
  let right = DictationCapsuleController.frame(
    for: .right,
    size: expectedSize,
    in: visibleFrame
  )

  #expect(bottom.size == expectedSize)
  #expect(left.size == expectedSize)
  #expect(right.size == expectedSize)
  #expect(bottom.minY == visibleFrame.minY + 10)
  #expect(left.minX == visibleFrame.minX + 10)
  #expect(right.maxX == visibleFrame.maxX - 10)
  #expect(left.midY == visibleFrame.midY)
  #expect(right.midY == visibleFrame.midY)
}

@Test func DictationAccessibilityReduceMotionUsesOpacityOnly() {
  #expect(DictationCapsuleTransition.forReduceMotion(true) == .opacity)
  #expect(DictationCapsuleTransition.forReduceMotion(false) == .scaleAndOpacity)
}

@Test @MainActor func DictationAccessibilityPanelNeverActivatesTheApp() {
  let panel = DictationCapsulePanel()

  #expect(panel.styleMask.contains(.nonactivatingPanel))
  #expect(!panel.canBecomeKey)
  #expect(!panel.canBecomeMain)
  #expect(panel.level == .floating)
  #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
  #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
  #expect(panel.collectionBehavior.contains(.stationary))
}

@Test @MainActor func DictationAccessibilityKeepsOnePanelAndOneSwiftUIRoot() {
  let panel = DictationCapsulePanel()
  let controller = DictationCapsuleController(panel: panel)
  var dockChanges: [DictationCapsuleDock] = []
  controller.presentIdle(
    dock: .bottom,
    onOpenFleck: {},
    onDockChanged: { dockChanges.append($0) }
  )

  let contentIdentity = ObjectIdentifier(panel.contentView!)
  controller.render(.arming)
  controller.render(.listening)
  controller.render(.cleaning)
  controller.render(.saving)
  controller.render(.saved(destination: "Inbox"), action: .undo)
  controller.setDock(.right)

  #expect(ObjectIdentifier(controller.panel) == ObjectIdentifier(panel))
  #expect(ObjectIdentifier(panel.contentView!) == contentIdentity)
  #expect(controller.currentDock == .right)
  #expect(dockChanges.isEmpty)
  controller.dismiss()
}

@Test @MainActor func DictationAccessibilityKeepsDockMenuOnThePersistentHost() {
  let panel = DictationCapsulePanel()
  let controller = DictationCapsuleController(panel: panel)
  var dockChanges: [DictationCapsuleDock] = []
  controller.presentIdle(
    dock: .bottom,
    onOpenFleck: {},
    onDockChanged: { dockChanges.append($0) }
  )

  #expect(panel.contentView?.menu?.items.map(\.title) == [
    "Dock Bottom",
    "Dock Left",
    "Dock Right",
  ])
  panel.contentView?.menu?.performActionForItem(at: 1)
  #expect(controller.currentDock == .left)
  #expect(dockChanges == [.left])
  controller.render(.failed("Unavailable"), action: .copy)
  #expect(controller.panel === panel)
  #expect(!panel.canBecomeKey)
  #expect(!panel.canBecomeMain)
  controller.dismiss()
}

@Test func DictationAccessibilityRecoveryActionsHaveKeyboardAndVoiceOverLabels() {
  let actions: [(DictationCapsuleAction, String)] = [
    (.undo, "Undo"),
    (.copy, "Copy"),
    (.openHistory, "Open Dictation History"),
    (.openDestination, "Open Destination"),
  ]

  for (action, title) in actions {
    #expect(action.title == title)
    #expect(action.accessibilityLabel == title)
  }
}

@Test @MainActor func DictationAccessibilitySelectsTheNearestSupportedDock() {
  let visibleFrame = CGRect(x: 100, y: 200, width: 1_000, height: 800)

  #expect(DictationCapsuleController.nearestDock(
    to: CGPoint(x: visibleFrame.minX, y: visibleFrame.midY),
    in: visibleFrame
  ) == .left)
  #expect(DictationCapsuleController.nearestDock(
    to: CGPoint(x: visibleFrame.maxX, y: visibleFrame.midY),
    in: visibleFrame
  ) == .right)
  #expect(DictationCapsuleController.nearestDock(
    to: CGPoint(x: visibleFrame.midX, y: visibleFrame.minY),
    in: visibleFrame
  ) == .bottom)
}

@Test @MainActor func DictationAccessibilityPrefersKeyboardFocusDisplayOverPointerAndPrimary() {
  let selected = DictationCapsuleController.preferredDisplay(
    keyboardFocus: "keyboard",
    pointer: "pointer",
    primary: "primary"
  )

  #expect(selected == "keyboard")
  #expect(DictationCapsuleController.preferredDisplay(
    keyboardFocus: nil,
    pointer: "pointer",
    primary: "primary"
  ) == "pointer")
}
