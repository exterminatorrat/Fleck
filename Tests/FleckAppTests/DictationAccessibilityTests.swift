import AppKit
import FleckCore
import SwiftUI
import Testing

@testable import FleckApp

private func capsuleContext(
  _ status: DictationCapsuleStatus,
  sessionID: UUID = UUID(uuidString: "A4D2C8B4-7C8A-4A6B-B7CC-06C2B3F2C1D1")!,
  mode: DictationMode? = .smartCapture,
  stage: DictationPipelineStage? = .capture,
  cleanup: DictationCleanupOutcome? = nil,
  failureStage: DictationPipelineStage? = nil,
  failureKind: DictationCapsuleFailureKind? = nil
) -> DictationCapsuleContext {
  DictationCapsuleContext(
    status: status,
    sessionID: sessionID,
    trigger: .pointer,
    mode: mode,
    isHandsFree: true,
    pipelineStage: stage,
    cleanupOutcome: cleanup,
    failureStage: failureStage,
    failureKind: failureKind
  )
}

private final class LayoutProbeView: NSView {
  let probeIdentifier: String

  init(identifier: String) {
    self.probeIdentifier = identifier
    super.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

private struct LayoutProbe: NSViewRepresentable {
  let identifier: String

  func makeNSView(context: Context) -> LayoutProbeView {
    LayoutProbeView(identifier: identifier)
  }

  func updateNSView(_ nsView: LayoutProbeView, context: Context) {}
}

@MainActor
private func descendants(of view: NSView) -> [NSView] {
  view.subviews + view.subviews.flatMap(descendants)
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
  let results: [(
    shortStatus: DictationCapsuleStatus,
    longStatus: DictationCapsuleStatus,
    action: DictationCapsuleAction,
    ceiling: CGSize
  )] = [
    (
      .saved(destination: "Inbox"),
      .saved(destination: String(repeating: "Long destination ", count: 20)),
      .undo,
      CGSize(width: 264, height: 36)
    ),
    (
      .savedWithoutCleanup(destination: "Inbox"),
      .savedWithoutCleanup(destination: String(repeating: "Long destination ", count: 20)),
      .copy,
      CGSize(width: 288, height: 36)
    ),
    (
      .failed("short technical detail"),
      .failed("long technical detail"),
      .copy,
      CGSize(width: 264, height: 36)
    ),
    (
      .noSpeech,
      .noSpeech,
      .copy,
      CGSize(width: 192, height: 36)
    ),
  ]

  for (shortStatus, longStatus, action, expectedSize) in results {
    let shortPresentation = DictationCapsulePresentation(status: shortStatus, action: action)
    let shortFrame = DictationCapsuleController.frame(
      for: .bottom,
      status: shortStatus,
      measuredWidth: shortPresentation.measuredWidth,
      in: visibleFrame
    )
    let longPresentation = DictationCapsulePresentation(status: longStatus, action: action)
    let longMeasuredWidth: CGFloat = {
      switch longStatus {
      case .failed, .noSpeech:
        expectedSize.width + 100
      default:
        longPresentation.measuredWidth
      }
    }()
    let longFrame = DictationCapsuleController.frame(
      for: .bottom,
      status: longStatus,
      measuredWidth: longMeasuredWidth,
      in: visibleFrame
    )

    #expect(shortFrame.height == expectedSize.height)
    if case .noSpeech = shortStatus {
      #expect(shortFrame.width == expectedSize.width)
    } else {
      #expect(shortFrame.width < expectedSize.width)
    }
    #expect(longFrame.size == expectedSize)
    if case .noSpeech = shortStatus {
      #expect(shortPresentation.measuredWidth <= expectedSize.width)
    } else {
      #expect(shortPresentation.measuredWidth < expectedSize.width)
    }
    #expect(longPresentation.measuredWidth <= expectedSize.width)
  }

  let noSpeechCeiling = DictationCapsuleController.noSpeechSize.width
  let clampedNoSpeechFrame = DictationCapsuleController.frame(
    for: .bottom,
    status: .noSpeech,
    measuredWidth: noSpeechCeiling + 100,
    in: visibleFrame
  )
  #expect(clampedNoSpeechFrame.width == noSpeechCeiling)

  let fixedStatuses: [DictationCapsuleStatus] = [
    .idle, .arming, .listening, .finalizing, .cleaning, .routing, .saving, .repairingModel,
  ]
  for status in fixedStatuses {
    #expect(
      DictationCapsuleController.frame(
        for: .bottom,
        status: status,
        measuredWidth: 1,
        in: visibleFrame
      ).size == DictationCapsuleController.size(for: status)
    )
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

  let failureWithoutProvenance = capsuleContext(
    .failed("unattributed failure"),
    mode: .focused,
    stage: .capture,
    cleanup: .usedRaw,
    failureStage: nil
  )
  #expect(FleckRailStageTreatment.forContext(failureWithoutProvenance) == [
    .pending, .pending, .pending, .pending,
  ])
}

@Test func DictationAccessibilityUsesFailureStageAndPreservesTechnicalDetail() {
  #expect(DictationCapsuleContext(status: .idle).failureKind == nil)

  let captureFailure = DictationCapsulePresentation(
    status: .failed("unrelated capture detail"),
    context: capsuleContext(
      .failed("unrelated capture detail"),
      stage: .capture,
      failureStage: .capture
    )
  )
  #expect(captureFailure.visibleText == "Dictation failed")
  #expect(captureFailure.voiceOverText.contains("unrelated capture detail"))

  let microphoneFailure = DictationCapsulePresentation(
    status: .failed("unrelated microphone detail"),
    context: capsuleContext(
      .failed("unrelated microphone detail"),
      stage: .capture,
      failureStage: .capture,
      failureKind: .microphoneAccess
    )
  )
  #expect(microphoneFailure.visibleText == "Microphone access needed")
  #expect(microphoneFailure.voiceOverText.contains("unrelated microphone detail"))

  let saveFailure = DictationCapsulePresentation(
    status: .failed("unrelated capture detail"),
    context: capsuleContext(
      .failed("unrelated capture detail"),
      stage: .save,
      failureStage: .save,
      failureKind: .save
    )
  )
  #expect(saveFailure.visibleText == "Couldn't save")
  #expect(saveFailure.voiceOverText.contains("unrelated capture detail"))

  let modelRepairFailure = DictationCapsulePresentation(
    status: .failed("model repair detail"),
    context: capsuleContext(
      .failed("model repair detail"),
      stage: .capture,
      failureStage: .capture,
      failureKind: .modelRepair
    )
  )
  #expect(modelRepairFailure.visibleText == "Model repair failed")
  #expect(modelRepairFailure.voiceOverText.contains("model repair detail"))

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
  #expect(FleckRailContentOrder.markAndContent(for: .left) == [.mark, .statusText])
  #expect(FleckRailContentOrder.markAndContent(for: .right) == [.statusText, .mark])
  #expect(FleckRailContentOrder.listening(for: .left) == [.mark, .waveform, .timer])
  #expect(FleckRailContentOrder.listening(for: .right) == [.timer, .waveform, .mark])
  #expect(FleckRailContentOrder.terminal(for: .left, includesAction: true) == [
    .mark, .terminalGlyph, .statusText, .divider, .action,
  ])
  #expect(FleckRailContentOrder.terminal(for: .right, includesAction: true) == [
    .action, .divider, .statusText, .terminalGlyph, .mark,
  ])
  #expect(FleckRailContentOrder.terminal(for: .left, includesAction: false) == [
    .mark, .terminalGlyph, .statusText,
  ])
  #expect(FleckRailContentOrder.terminal(for: .right, includesAction: false) == [
    .statusText, .terminalGlyph, .mark,
  ])
}

@Test @MainActor func DictationAccessibilityPlacesMarkAtEachOuterDockEdge() {
  func placedFrames(
    for dock: DictationCapsuleDock
  ) -> (mark: CGRect, content: CGRect)? {
    let root = FleckRailLayout(
      order: FleckRailContentOrder.markAndContent(for: dock),
      spacing: 7
    ) {
      LayoutProbe(identifier: "mark")
        .frame(width: 14, height: 14)
      LayoutProbe(identifier: "content")
        .frame(width: 40, height: 20)
    }
    let hostingView = NSHostingView(rootView: root)
    hostingView.frame = CGRect(x: 0, y: 0, width: 100, height: 40)
    hostingView.layoutSubtreeIfNeeded()
    guard
      let mark = descendants(of: hostingView)
        .compactMap({ $0 as? LayoutProbeView })
        .first(where: { $0.probeIdentifier == "mark" }),
      let content = descendants(of: hostingView)
        .compactMap({ $0 as? LayoutProbeView })
        .first(where: { $0.probeIdentifier == "content" })
    else {
      return nil
    }
    return (
      mark: mark.convert(mark.bounds, to: hostingView),
      content: content.convert(content.bounds, to: hostingView)
    )
  }

  guard let left = placedFrames(for: .left), let right = placedFrames(for: .right) else {
    Issue.record("Expected both custom-layout probe views to be rendered")
    return
  }
  #expect(left.mark.minX < left.content.minX)
  #expect(right.mark.maxX > right.content.maxX)
}

@Test func DictationAccessibilityInstallsOnePersistentFleckMarkSubtree() throws {
  let sourceRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let source = try String(
    contentsOf: sourceRoot.appendingPathComponent("Sources/FleckApp/DictationCapsule.swift"),
    encoding: .utf8
  )
  #expect(source.components(separatedBy: "FleckRailMark(").count - 1 == 1)
  #expect(source.contains("private var railMark"))
}

@Test func DictationAccessibilityFailedTileUsesColorAndShape() {
  #expect(FleckRailStageTreatment.failed.usesFailureColor)
  #expect(FleckRailStageTreatment.failed.usesDiagonal)
  #expect(!FleckRailStageTreatment.pending.usesFailureColor)
  #expect(!FleckRailStageTreatment.pending.usesDiagonal)
}

@Test @MainActor func DictationAccessibilityPersistentHostLeavesGestureRoutingToDescendants() {
  let panel = DictationCapsulePanel()
  let controller = DictationCapsuleController(panel: panel)
  var actions = 0
  controller.presentIdle(
    dock: .bottom,
    onOpenFleck: {},
    onDockChanged: { _ in }
  )
  controller.render(.saved(destination: "Inbox"), action: .undo) {
    actions += 1
  }

  panel.setFrame(CGRect(x: 0, y: 0, width: 264, height: 36), display: false)
  panel.contentView?.frame = CGRect(x: 0, y: 0, width: 264, height: 36)
  panel.contentView?.layoutSubtreeIfNeeded()
  let host = panel.contentView!
  let descendant = host.subviews.first
  let hit = host.hitTest(NSPoint(x: host.bounds.midX, y: host.bounds.midY))

  #expect(descendant != nil)
  #expect(hit != nil)
  #expect(hit !== host)
  if let descendant {
    #expect(hit === descendant || hit?.isDescendant(of: descendant) == true)
  }
  host.layoutSubtreeIfNeeded()
  let performClick = #selector(NSButton.performClick(_:))
  guard let actionButton = descendants(of: host)
    .first(where: { $0.responds(to: performClick) })
  else {
    Issue.record("Expected the rendered Undo action button to be discoverable")
    controller.dismiss()
    return
  }
  let actionFrame = actionButton.convert(actionButton.bounds, to: host)
  let actionHit = host.hitTest(NSPoint(x: actionFrame.midX, y: actionFrame.midY))
  #expect(actionHit != nil)
  #expect(actionHit !== host)
  #expect(
    actionHit === actionButton
      || actionHit?.isDescendant(of: actionButton) == true
      || actionButton.isDescendant(of: actionHit ?? host)
  )
  #expect(actionButton.responds(to: performClick))
  #expect(actions == 0)
  _ = actionButton.perform(performClick, with: nil)
  #expect(actions == 1)
  controller.dismiss()
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
