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

@MainActor
private func renderedActionButton(in host: NSView) -> NSView? {
  let performClick = #selector(NSButton.performClick(_:))
  return descendants(of: host).first { $0.responds(to: performClick) }
}

@MainActor
private func renderedView(with identifier: String, in host: NSView) -> NSView? {
  descendants(of: host).first { $0.identifier?.rawValue == identifier }
}

@MainActor
private func brightPixelBounds<Content: View>(
  of content: Content,
  size: CGSize,
  threshold: CGFloat = 0.05
) throws -> CGRect? {
  let host = NSHostingView(rootView: content)
  host.frame = CGRect(origin: .zero, size: size)
  host.layoutSubtreeIfNeeded()
  let imageRep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
  host.cacheDisplay(in: host.bounds, to: imageRep)
  let scaleX = CGFloat(imageRep.pixelsWide) / size.width
  let scaleY = CGFloat(imageRep.pixelsHigh) / size.height
  var bounds: CGRect?
  for y in 0..<imageRep.pixelsHigh {
    for x in 0..<imageRep.pixelsWide {
      guard let color = imageRep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
        max(color.redComponent, color.greenComponent, color.blueComponent) > threshold
      else { continue }
      let pixel = CGRect(
        x: CGFloat(x) / scaleX,
        y: CGFloat(y) / scaleY,
        width: 1 / scaleX,
        height: 1 / scaleY
      )
      bounds = bounds?.union(pixel) ?? pixel
    }
  }
  return bounds
}

@Test @MainActor func DictationAccessibilityKeepsActiveProgressTileAtCrispBaseSize() throws {
  let padding: CGFloat = 10
  let activeTile = 1
  let painted = try #require(
    try brightPixelBounds(
      of: FleckRailMark(
        layout: .rail(reversed: false),
        treatments: [.pending, .active, .pending, .pending]
      )
      .padding(padding)
      .background(Color.black),
      size: CGSize(
        width: FleckRailMark.railFrameSize.width + padding * 2,
        height: FleckRailMark.railFrameSize.height + padding * 2
      ),
      threshold: 0.8
    )
  )
  let expected = FleckRailMark.railTileFrames[activeTile].offsetBy(
    dx: padding,
    dy: padding
  )
  #expect(painted.width <= expected.width + 0.5)
  #expect(painted.height <= expected.height + 0.5)
  #expect(abs(painted.midX - expected.midX) <= 0.5)
  #expect(abs(painted.midY - expected.midY) <= 0.5)
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
  let savedShort = DictationCapsulePresentation(
    status: .saved(destination: "Inbox"),
    action: .undo
  )
  let savedLong = DictationCapsulePresentation(
    status: .saved(destination: String(repeating: "Long destination ", count: 20)),
    action: .undo
  )
  let savedShortFrame = DictationCapsuleController.frame(
    for: .bottom,
    status: .saved(destination: "Inbox"),
    measuredWidth: savedShort.measuredWidth,
    in: visibleFrame
  )
  let savedLongFrame = DictationCapsuleController.frame(
    for: .bottom,
    status: .saved(destination: String(repeating: "Long destination ", count: 20)),
    measuredWidth: savedLong.measuredWidth,
    in: visibleFrame
  )
  #expect(savedShortFrame.width < DictationCapsuleController.savedSize.width)
  #expect(savedLongFrame.size == DictationCapsuleController.savedSize)

  let savedOriginalShort = DictationCapsulePresentation(
    status: .savedWithoutCleanup(destination: "Inbox"),
    action: .copy
  )
  let savedOriginalLong = DictationCapsulePresentation(
    status: .savedWithoutCleanup(destination: String(repeating: "Long destination ", count: 20)),
    action: .copy
  )
  let savedOriginalShortFrame = DictationCapsuleController.frame(
    for: .bottom,
    status: .savedWithoutCleanup(destination: "Inbox"),
    measuredWidth: savedOriginalShort.measuredWidth,
    in: visibleFrame
  )
  let savedOriginalLongFrame = DictationCapsuleController.frame(
    for: .bottom,
    status: .savedWithoutCleanup(destination: String(repeating: "Long destination ", count: 20)),
    measuredWidth: savedOriginalLong.measuredWidth,
    in: visibleFrame
  )
  #expect(savedOriginalShortFrame.width < DictationCapsuleController.savedWithoutCleanupSize.width)
  #expect(savedOriginalLongFrame.size == DictationCapsuleController.savedWithoutCleanupSize)

  let failure = DictationCapsulePresentation(
    status: .failed("technical capture detail"),
    action: .copy
  )
  let failureFrame = DictationCapsuleController.frame(
    for: .bottom,
    status: .failed("technical capture detail"),
    measuredWidth: failure.measuredWidth,
    in: visibleFrame
  )
  #expect(failure.measuredWidth < DictationCapsuleController.failureSize.width)
  #expect(failureFrame.width == failure.measuredWidth)

  let noSpeech = DictationCapsulePresentation(status: .noSpeech)
  let noSpeechFrame = DictationCapsuleController.frame(
    for: .bottom,
    status: .noSpeech,
    measuredWidth: noSpeech.measuredWidth,
    in: visibleFrame
  )
  #expect(noSpeech.measuredWidth < DictationCapsuleController.noSpeechSize.width)
  #expect(noSpeechFrame.width == noSpeech.measuredWidth)

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

@Test @MainActor func DictationAccessibilityDrawsStableFourTileProgressRail() {
  #expect(FleckRailMark.frameSize == CGSize(width: 14, height: 14))
  #expect(FleckRailMark.tileIDs == [0, 1, 2, 3])
  #expect(FleckRailMark.tileFrames.count == 4)
  #expect(FleckRailMark.tileFrames.allSatisfy { $0.width == 6 && $0.height == 6 })
  #expect(FleckRailMark.tileFrames[1].minX - FleckRailMark.tileFrames[0].maxX == 2)
  #expect(FleckRailMark.tileFrames[2].minY - FleckRailMark.tileFrames[0].maxY == 2)
  #expect(FleckRailMark.innerHighlightThickness == 1)
}

@Test @MainActor func DictationAccessibilityKeepsPaintedProgressTilesInsideDeclaredFrame() throws {
  let padding: CGFloat = 10
  let frame = CGRect(
    x: padding,
    y: padding,
    width: FleckRailMark.railFrameSize.width,
    height: FleckRailMark.railFrameSize.height
  )
  let canvasSize = CGSize(
    width: frame.width + padding * 2,
    height: frame.height + padding * 2
  )

  for activeTile in FleckRailMark.tileIDs {
    let renderedBounds = try brightPixelBounds(
      of: FleckRailMark(
        color: .white,
        activeTile: activeTile,
        layout: .rail(reversed: false)
      )
      .padding(padding)
      .background(Color.black),
      size: canvasSize
    )
    let painted = try #require(renderedBounds)
    #expect(painted.minX >= frame.minX - 0.5)
    #expect(painted.maxX <= frame.maxX + 0.5)
    #expect(painted.minY >= frame.minY - 0.5)
    #expect(painted.maxY <= frame.maxY + 0.5)
    #expect(abs(painted.midX - frame.midX) <= 0.5)
    #expect(abs(painted.midY - frame.midY) <= 0.5)
  }
}

@Test @MainActor func DictationAccessibilityLoadsCanonicalTemplateMarkAtTinyRailSize() {
  let sourceRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let markDirectory = sourceRoot.appendingPathComponent("website/public", isDirectory: true)
  guard case .image(let image) = FleckMark.load(
    template: true,
    resourceURL: markDirectory,
    isPackagedApp: true
  ) else {
    Issue.record("Expected the canonical packaged Fleck mark")
    return
  }
  #expect(image.isTemplate)
  #expect(image.size == NSSize(width: 18, height: 18))
  #expect(FleckRailIdentityMark.frameSize == CGSize(width: 18, height: 18))
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
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.horizontal, 8)
    .frame(width: 100, height: 40)
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
  #expect(abs(left.mark.minX - 8) < 0.1)
  #expect(abs(right.mark.maxX - 92) < 0.1)
}

@Test @MainActor func DictationAccessibilityAnchorsIdentityAndListeningToRailEdges() {
  let sourceRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let markDirectory = sourceRoot.appendingPathComponent("website/public", isDirectory: true)
  let markLoader: @MainActor () -> NSImage? = {
    guard case .image(let image) = FleckMark.load(
      template: true,
      resourceURL: markDirectory,
      isPackagedApp: true
    ) else {
      return nil
    }
    return image
  }
  let panel = DictationCapsulePanel()
  let controller = DictationCapsuleController(panel: panel, markLoader: markLoader)
  defer { controller.dismiss() }

  func probeFrame(_ identifier: String, size: CGSize) -> CGRect? {
    panel.setFrame(CGRect(origin: .zero, size: size), display: false)
    panel.contentView?.frame = CGRect(origin: .zero, size: size)
    panel.contentView?.layoutSubtreeIfNeeded()
    guard let host = panel.contentView,
      let probe = renderedView(with: identifier, in: host)
    else {
      return nil
    }
    return probe.convert(probe.bounds, to: host)
  }

  controller.render(.idle)
  guard let idleMark = probeFrame(
    "fleck-rail-mark",
    size: DictationCapsuleController.idleSize
  ) else {
    Issue.record("Expected the canonical idle mark probe")
    return
  }
  #expect(abs(idleMark.midX - 23) < 0.1)
  #expect(abs(idleMark.midY - 12) < 0.1)

  let listening = DictationCapsuleContext(
    status: .listening,
    sessionID: UUID(uuidString: "B1D2B13B-6D48-4D13-8D90-81DE8E54C6AC")!,
    trigger: .hold,
    mode: .smartCapture,
    isHandsFree: false,
    pipelineStage: .capture
  )
  controller.render(listening)
  guard let bottomMark = probeFrame(
    "fleck-rail-mark",
    size: DictationCapsuleController.listeningSize
  ), let bottomWaveform = probeFrame(
    "fleck-rail-waveform",
    size: DictationCapsuleController.listeningSize
  ), let bottomTimer = probeFrame(
    "fleck-rail-timer",
    size: DictationCapsuleController.listeningSize
  ), let bottomElapsed = probeFrame(
    "fleck-rail-elapsed",
    size: DictationCapsuleController.listeningSize
  ) else {
    Issue.record("Expected the bottom listening probes")
    return
  }
  #expect(abs(bottomMark.minX - 8) < 0.1)
  #expect(abs(bottomMark.midY - 18) < 0.1)
  #expect(abs(bottomWaveform.midX - 88) < 0.1)
  #expect(abs(bottomTimer.maxX - 168) < 0.1)
  #expect(abs(bottomElapsed.maxX - 168) < 0.1)
  #expect(bottomMark.maxX < bottomWaveform.minX)
  #expect(bottomWaveform.maxX < bottomTimer.minX)

  controller.setDock(.left)
  controller.render(listening)
  guard let leftMark = probeFrame(
    "fleck-rail-mark",
    size: DictationCapsuleController.listeningSize
  ), let leftWaveform = probeFrame(
    "fleck-rail-waveform",
    size: DictationCapsuleController.listeningSize
  ), let leftTimer = probeFrame(
    "fleck-rail-timer",
    size: DictationCapsuleController.listeningSize
  ), let leftElapsed = probeFrame(
    "fleck-rail-elapsed",
    size: DictationCapsuleController.listeningSize
  ) else {
    Issue.record("Expected the left listening probes")
    return
  }
  #expect(abs(leftMark.minX - 8) < 0.1)
  #expect(abs(leftMark.midY - 18) < 0.1)
  #expect(abs(leftWaveform.midX - 88) < 0.1)
  #expect(abs(leftTimer.maxX - 168) < 0.1)
  #expect(abs(leftElapsed.maxX - 168) < 0.1)
  #expect(leftMark.maxX < leftWaveform.minX)
  #expect(leftWaveform.maxX < leftTimer.minX)

  controller.setDock(.right)
  controller.render(listening)
  guard let rightMark = probeFrame(
    "fleck-rail-mark",
    size: DictationCapsuleController.listeningSize
  ), let rightWaveform = probeFrame(
    "fleck-rail-waveform",
    size: DictationCapsuleController.listeningSize
  ), let rightTimer = probeFrame(
    "fleck-rail-timer",
    size: DictationCapsuleController.listeningSize
  ), let rightElapsed = probeFrame(
    "fleck-rail-elapsed",
    size: DictationCapsuleController.listeningSize
  ) else {
    Issue.record("Expected the right listening probes")
    return
  }
  #expect(abs(rightMark.maxX - 168) < 0.1)
  #expect(abs(rightWaveform.midX - 88) < 0.1)
  #expect(abs(rightTimer.minX - 8) < 0.1)
  #expect(abs(rightElapsed.maxX - 66) < 0.1)
  #expect(rightTimer.maxX < rightWaveform.minX)
  #expect(rightWaveform.maxX < rightMark.minX)
}

@Test @MainActor func DictationAccessibilityMirrorsRenderedTerminalFramesAtDockEdges() {
  typealias TerminalFrames = (
    mark: CGRect,
    glyph: CGRect,
    text: CGRect,
    divider: CGRect,
    action: CGRect
  )

  func placedFrames(for dock: DictationCapsuleDock) -> TerminalFrames? {
    let root = FleckRailLayout(
      order: FleckRailContentOrder.markAndContent(for: dock),
      spacing: 7
    ) {
      LayoutProbe(identifier: "mark")
        .frame(width: 14, height: 14)
      FleckRailTerminalLayout(
        elements: [.terminalGlyph, .statusText, .divider, .action],
        order: FleckRailContentOrder.terminalCluster(
          for: dock,
          includesAction: true
        ),
        spacing: 7
      ) {
        LayoutProbe(identifier: "glyph")
          .frame(width: 14, height: 14)
        LayoutProbe(identifier: "text")
          .frame(width: 56, height: 20)
        LayoutProbe(identifier: "divider")
          .frame(width: 1, height: 16)
        LayoutProbe(identifier: "action")
          .frame(
            width: DictationCapsulePresentation.actionWidth(for: .copy),
            height: 20
          )
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.horizontal, 8)
    .frame(width: 200, height: 40)

    let hostingView = NSHostingView(rootView: root)
    hostingView.frame = CGRect(x: 0, y: 0, width: 200, height: 40)
    hostingView.layoutSubtreeIfNeeded()

    func frame(for identifier: String) -> CGRect? {
      guard let probe = descendants(of: hostingView)
        .compactMap({ $0 as? LayoutProbeView })
        .first(where: { $0.probeIdentifier == identifier })
      else {
        return nil
      }
      return probe.convert(probe.bounds, to: hostingView)
    }

    guard
      let mark = frame(for: "mark"),
      let glyph = frame(for: "glyph"),
      let text = frame(for: "text"),
      let divider = frame(for: "divider"),
      let action = frame(for: "action")
    else {
      return nil
    }
    return (mark, glyph, text, divider, action)
  }

  guard let left = placedFrames(for: .left), let right = placedFrames(for: .right) else {
    Issue.record("Expected every terminal element to be rendered")
    return
  }

  #expect(abs(left.mark.minX - 8) < 0.1)
  #expect(left.mark.maxX < left.glyph.minX)
  #expect(left.glyph.maxX < left.text.minX)
  #expect(left.text.maxX < left.divider.minX)
  #expect(left.divider.maxX < left.action.minX)

  #expect(abs(right.mark.maxX - 192) < 0.1)
  #expect(right.action.minX < right.divider.minX)
  #expect(right.divider.minX < right.text.minX)
  #expect(right.text.minX < right.glyph.minX)
  #expect(right.glyph.minX < right.mark.minX)
}

@Test @MainActor func DictationAccessibilityCentersProcessingRailBeforeAndAfterLabelDelay() async {
  let sourceRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let markDirectory = sourceRoot.appendingPathComponent("website/public", isDirectory: true)
  let markLoader: @MainActor () -> NSImage? = {
    guard case .image(let image) = FleckMark.load(
      template: true,
      resourceURL: markDirectory,
      isPackagedApp: true
    ) else {
      return nil
    }
    return image
  }
  let panel = DictationCapsulePanel()
  let controller = DictationCapsuleController(panel: panel, markLoader: markLoader)
  defer { controller.dismiss() }
  let context = DictationCapsuleContext(
    status: .cleaning,
    sessionID: UUID(uuidString: "905A0F05-0D5A-46D0-88AF-7CD49E1E0A9D")!,
    mode: .smartCapture,
    pipelineStage: .polish
  )
  controller.render(context)

  func frame(for identifier: String) -> CGRect? {
    panel.setFrame(
      CGRect(origin: .zero, size: DictationCapsuleController.activeSize),
      display: false
    )
    panel.contentView?.frame = CGRect(
      origin: .zero,
      size: DictationCapsuleController.activeSize
    )
    panel.contentView?.layoutSubtreeIfNeeded()
    guard let host = panel.contentView,
      let rendered = renderedView(with: identifier, in: host)
    else {
      return nil
    }
    return rendered.convert(rendered.bounds, to: host)
  }

  guard let hiddenMark = frame(for: "fleck-rail-mark") else {
    Issue.record("Expected the centered hidden processing rail")
    return
  }
  #expect(abs(hiddenMark.midX - DictationCapsuleController.activeSize.width / 2) < 0.1)
  #expect(frame(for: "fleck-rail-processing-text") == nil)

  try? await Task.sleep(for: .milliseconds(500))
  for _ in 0..<5 { await Task.yield() }
  guard let visibleMark = frame(for: "fleck-rail-mark"),
    let visibleText = frame(for: "fleck-rail-processing-text")
  else {
    Issue.record("Expected the visible processing label and rail")
    return
  }
  let cluster = visibleMark.union(visibleText)
  #expect(abs(cluster.midX - DictationCapsuleController.activeSize.width / 2) < 0.1)
  #expect(visibleMark.maxX < visibleText.minX)
}

@Test @MainActor func DictationAccessibilityFitsHandsFreeHoverActionsInTrailingZone() {
  let sourceRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let markDirectory = sourceRoot.appendingPathComponent("website/public", isDirectory: true)
  let markLoader: @MainActor () -> NSImage? = {
    guard case .image(let image) = FleckMark.load(
      template: true,
      resourceURL: markDirectory,
      isPackagedApp: true
    ) else {
      return nil
    }
    return image
  }
  let panel = DictationCapsulePanel()
  let controller = DictationCapsuleController(panel: panel, markLoader: markLoader)
  defer { controller.dismiss() }
  controller.render(
    DictationCapsuleContext(
      status: .listening,
      sessionID: UUID(uuidString: "7D044D5B-5A32-46AA-A51F-BFAE2CFBF66C")!,
      trigger: .doubleTap,
      mode: .smartCapture,
      isHandsFree: true,
      pipelineStage: .capture
    )
  )
  controller.presentationModel.setListeningHover(true)
  let size = DictationCapsuleController.listeningSize
  panel.setFrame(CGRect(origin: .zero, size: size), display: false)
  panel.contentView?.frame = CGRect(origin: .zero, size: size)
  panel.contentView?.layoutSubtreeIfNeeded()
  guard let host = panel.contentView,
    let stop = renderedView(with: "fleck-rail-stop", in: host),
    let cancel = renderedView(with: "fleck-rail-cancel", in: host),
    let timer = renderedView(with: "fleck-rail-timer", in: host)
  else {
    Issue.record("Expected the hands-free hover action probes")
    return
  }
  let stopFrame = stop.convert(stop.bounds, to: host)
  let cancelFrame = cancel.convert(cancel.bounds, to: host)
  let timerFrame = timer.convert(timer.bounds, to: host)
  #expect(stopFrame.size == CGSize(width: 28, height: 28))
  #expect(cancelFrame.size == CGSize(width: 28, height: 28))
  #expect(abs(stopFrame.minX - 110) < 0.1)
  #expect(abs(cancelFrame.maxX - 168) < 0.1)
  #expect(abs(timerFrame.maxX - 168) < 0.1)
}

@Test func DictationAccessibilityKeepsPersistentProgressAndCanonicalMarkSubtrees() throws {
  let sourceRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let source = try String(
    contentsOf: sourceRoot.appendingPathComponent("Sources/FleckApp/DictationCapsule.swift"),
    encoding: .utf8
  )
  #expect(source.components(separatedBy: "FleckRailMark(").count - 1 == 1)
  #expect(source.components(separatedBy: "FleckRailIdentityMark(").count - 1 == 1)
  #expect(source.contains("FleckMark.load(template: true)"))
  #expect(source.contains("private var identityMark"))
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

@Test @MainActor func DictationAccessibilityAdaptiveActionContentFitsHostedControllerFrames() {
  let visibleFrame = CGRect(x: 100, y: 200, width: 1_000, height: 800)
  let panel = DictationCapsulePanel()
  let controller = DictationCapsuleController(panel: panel)

  controller.presentIdle(
    dock: .bottom,
    onOpenFleck: {},
    onDockChanged: { _ in }
  )

  func assertActionFits(
    status: DictationCapsuleStatus,
    action: DictationCapsuleAction
  ) {
    controller.render(status, action: action)
    let presentation = DictationCapsulePresentation(status: status, action: action)
    let frame = DictationCapsuleController.frame(
      for: .bottom,
      status: status,
      measuredWidth: presentation.measuredWidth,
      in: visibleFrame
    )
    panel.setFrame(CGRect(origin: .zero, size: frame.size), display: false)
    panel.contentView?.frame = CGRect(origin: .zero, size: frame.size)
    panel.contentView?.layoutSubtreeIfNeeded()
    guard let host = panel.contentView, let actionButton = renderedActionButton(in: host) else {
      Issue.record("Expected the rendered action button in the hosted \(status) result")
      return
    }
    let actionFrame = actionButton.convert(actionButton.bounds, to: host)
    #expect(frame.width == controller.panel.frame.width)
    #expect(actionFrame.width > 0)
    #expect(actionFrame.width <= DictationCapsulePresentation.actionWidth(for: action))
    #expect(actionFrame.minX >= host.bounds.minX)
    #expect(actionFrame.maxX <= host.bounds.maxX)
    #expect(actionFrame.minY >= host.bounds.minY)
    #expect(actionFrame.maxY <= host.bounds.maxY)
  }

  assertActionFits(
    status: .failed("technical failure detail"),
    action: .copy
  )
  assertActionFits(
    status: .saved(destination: String(repeating: "Long destination ", count: 20)),
    action: .undo
  )
  controller.dismiss()
}

@Test @MainActor func DictationAccessibilityRecoveryActionsFitFailureFramesOnEveryDock() {
  let visibleFrame = CGRect(x: 100, y: 200, width: 1_000, height: 800)
  let panel = DictationCapsulePanel()
  let controller = DictationCapsuleController(panel: panel)

  controller.presentIdle(
    dock: .bottom,
    onOpenFleck: {},
    onDockChanged: { _ in }
  )

  let failureContext = DictationCapsuleContext(
    status: .failed("save detail"),
    sessionID: UUID(),
    trigger: .pointer,
    mode: .smartCapture,
    isHandsFree: true,
    pipelineStage: .save,
    failureStage: .save,
    failureKind: .save
  )
  let requiredFailureCopies = [
    DictationCapsulePresentation(
      status: .failed("microphone detail"),
      context: DictationCapsuleContext(
        status: .failed("microphone detail"),
        failureStage: .capture,
        failureKind: .microphoneAccess
      )
    ).visibleText,
    DictationCapsulePresentation(
      status: failureContext.status,
      context: failureContext
    ).visibleText,
  ]
  #expect(requiredFailureCopies == ["Microphone access needed", "Couldn't save"])

  for dock in [DictationCapsuleDock.bottom, .left, .right] {
    for action in [DictationCapsuleAction.openHistory, .openDestination] {
      controller.setDock(dock)
      controller.render(failureContext, action: action)
      let presentation = DictationCapsulePresentation(
        status: failureContext.status,
        action: action,
        context: failureContext
      )
      let frame = DictationCapsuleController.frame(
        for: dock,
        status: failureContext.status,
        measuredWidth: presentation.measuredWidth,
        in: visibleFrame
      )
      panel.setFrame(CGRect(origin: .zero, size: frame.size), display: false)
      panel.contentView?.frame = CGRect(origin: .zero, size: frame.size)
      panel.contentView?.layoutSubtreeIfNeeded()
      guard let host = panel.contentView else {
        Issue.record("Expected the persistent hosted failure frame")
        continue
      }
      for identifier in [
        "fleck-rail-mark",
        "fleck-terminal-glyph",
        "fleck-terminal-text",
        "fleck-terminal-divider",
        "fleck-rail-recovery",
      ] {
        guard let rendered = renderedView(with: identifier, in: host) else {
          Issue.record("Expected rendered \(identifier) for \(action) at \(dock)")
          continue
        }
        let renderedFrame = rendered.convert(rendered.bounds, to: host)
        #expect(renderedFrame.width > 0)
        #expect(renderedFrame.height > 0)
        #expect(renderedFrame.minX >= host.bounds.minX)
        #expect(renderedFrame.maxX <= host.bounds.maxX)
        #expect(renderedFrame.minY >= host.bounds.minY)
        #expect(renderedFrame.maxY <= host.bounds.maxY)
      }
      #expect(presentation.measuredWidth < DictationCapsuleController.failureSize.width)
      #expect(action.title == action.accessibilityLabel)
      #expect(DictationCapsulePresentation.actionWidth(for: action) < 100)
      #expect(action.accessibilityLabel.contains("Open"))
    }
  }
  controller.dismiss()
}

@Test @MainActor func DictationAccessibilityNoSpeechWithoutActionFitsHostedFrame() {
  let panel = DictationCapsulePanel()
  let controller = DictationCapsuleController(panel: panel)

  controller.render(.noSpeech, action: nil)
  let presentation = DictationCapsulePresentation(status: .noSpeech, action: nil)
  let expectedSize = DictationCapsuleController.size(
    for: .noSpeech,
    measuredWidth: presentation.measuredWidth
  )
  #expect(abs(panel.frame.width - expectedSize.width) < 0.1)
  #expect(panel.frame.width <= DictationCapsuleController.noSpeechSize.width)

  guard let host = panel.contentView else {
    Issue.record("Expected the persistent no-speech host")
    controller.dismiss()
    return
  }
  host.frame = CGRect(origin: .zero, size: panel.frame.size)
  host.layoutSubtreeIfNeeded()

  let identifiers = [
    "fleck-rail-mark",
    "fleck-terminal-glyph",
    "fleck-terminal-text",
  ]
  for identifier in identifiers {
    guard let rendered = renderedView(with: identifier, in: host) else {
      Issue.record("Expected rendered no-speech view with identifier \(identifier)")
      continue
    }
    let frame = rendered.convert(rendered.bounds, to: host)
    #expect(frame.width > 0)
    #expect(frame.height > 0)
    #expect(frame.minX >= host.bounds.minX)
    #expect(frame.maxX <= host.bounds.maxX)
    #expect(frame.minY >= host.bounds.minY)
    #expect(frame.maxY <= host.bounds.maxY)
    #expect(rendered.hitTest(NSPoint(x: rendered.bounds.midX, y: rendered.bounds.midY)) == nil)
  }
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

@Test func DictationAccessibilityUsesExactRestrainedMotionTimings() {
  #expect(DictationCapsuleMotion.acknowledgement == 0)
  #expect(DictationCapsuleMotion.colorAndOpacity == 0.09)
  #expect(DictationCapsuleMotion.tileMorph == 0.14)
  #expect(DictationCapsuleMotion.contentExit == 0.07)
  #expect(DictationCapsuleMotion.shellSettle == 0.12)
  #expect((0.10...0.12).contains(DictationCapsuleMotion.result))
  #expect(DictationCapsuleMotion.dockSnap == 0.18)
  #expect(
    DictationCapsuleMotion.transitionDuration(
      from: .idle,
      to: .arming,
      reduceMotion: false
    ) == DictationCapsuleMotion.acknowledgement
  )
  #expect(
    DictationCapsuleMotion.transitionDuration(
      from: .idle,
      to: .listening,
      reduceMotion: false
    ) == DictationCapsuleMotion.colorAndOpacity
  )
  #expect(
    DictationCapsuleMotion.transitionDuration(
      from: .listening,
      to: .cleaning,
      reduceMotion: false
    ) == DictationCapsuleMotion.tileMorph
  )
  #expect(
    DictationCapsuleMotion.transitionDuration(
      from: .cleaning,
      to: .saved(destination: "Inbox"),
      reduceMotion: false
    ) == DictationCapsuleMotion.result
  )
  #expect(
    DictationCapsuleMotion.transitionDuration(
      from: .saved(destination: "Inbox"),
      to: .idle,
      reduceMotion: false
    ) == DictationCapsuleMotion.contentExit
  )
  #expect(
    DictationCapsuleMotion.transitionDuration(
      from: .listening,
      to: .cleaning,
      reduceMotion: true
    ) == DictationCapsuleMotion.reduceMotionCrossfade
  )
  #expect(
    DictationCapsuleMotion.transitionDuration(
      from: .listening,
      to: .listening,
      reduceMotion: false,
      dockChange: true
    ) == DictationCapsuleMotion.dockSnap
  )
}

@Test func DictationAccessibilitySeparatesTerminalContentExitFromShellSettle() {
  #expect(
    DictationCapsuleMotion.contentDuration(
      from: .cleaning,
      to: .saved(destination: "Inbox"),
      reduceMotion: false
    ) == DictationCapsuleMotion.result
  )
  #expect(
    DictationCapsuleMotion.contentDuration(
      from: .saved(destination: "Inbox"),
      to: .idle,
      reduceMotion: false
    ) == DictationCapsuleMotion.contentExit
  )
  #expect(
    DictationCapsuleMotion.shellDuration(
      from: .saved(destination: "Inbox"),
      to: .idle,
      reduceMotion: false
    ) == DictationCapsuleMotion.shellSettle
  )
  #expect(
    DictationCapsuleMotion.contentDuration(
      from: .saved(destination: "Inbox"),
      to: .idle,
      reduceMotion: true
    ) == DictationCapsuleMotion.reduceMotionCrossfade
  )
  #expect(
    DictationCapsuleMotion.shellDuration(
      from: .saved(destination: "Inbox"),
      to: .idle,
      reduceMotion: true
    ) == DictationCapsuleMotion.reduceMotionCrossfade
  )
}

@Test @MainActor func DictationAccessibilityKeepsProcessingLabelSlotFencedUntilTheDelay() async {
  let gate = AccessibilitySleepGate()
  let model = DictationCapsulePresentationModel(
    processingLabelSleeper: { _ in await gate.wait() }
  )
  model.update(
    context: DictationCapsuleContext(status: .cleaning),
    action: nil,
    onAction: {}
  )
  await gate.waitUntilWaiting()
  #expect(!model.showsProcessingLabel)
  #expect(DictationCapsuleMotion.processingLabelDelay == .milliseconds(450))
  await gate.resume()
  for _ in 0..<10 { await Task.yield() }
  #expect(model.showsProcessingLabel)
}

@Test @MainActor func DictationAccessibilityFencesProcessingLabelToCurrentGeneration() async {
  let gate = AccessibilitySleepGate()
  let session = UUID(uuidString: "E58D9D42-35BC-43A5-AB26-1C346DDFAF78")!
  let model = DictationCapsulePresentationModel(
    processingLabelSleeper: { _ in await gate.wait() }
  )
  model.update(
    context: DictationCapsuleContext(
      status: .cleaning,
      sessionID: session,
      mode: .smartCapture,
      pipelineStage: .polish
    ),
    action: nil,
    onAction: {}
  )
  await gate.waitUntilWaiting()
  #expect(!model.showsProcessingLabel)
  let oldGeneration = model.presentationGeneration

  model.update(
    context: DictationCapsuleContext(
      status: .saved(destination: "Inbox"),
      sessionID: session,
      mode: .smartCapture
    ),
    action: nil,
    onAction: {}
  )
  #expect(model.presentationGeneration > oldGeneration)
  await gate.resume()
  for _ in 0..<10 { await Task.yield() }

  #expect(!model.showsProcessingLabel)
  #expect(model.voiceOverLabel.contains("Saved to Inbox"))
}

@Test @MainActor func DictationAccessibilityCoalescesListeningAndTerminalAnnouncements() {
  let session = UUID(uuidString: "A90D9C4F-6B1E-4C34-8F33-4C88D18B1375")!
  var announcements: [String] = []
  let model = DictationCapsulePresentationModel(
    announcementHandler: { announcements.append($0) }
  )
  #expect(model.voiceOverLabel == "Fleck dictation ready")

  model.update(
    context: DictationCapsuleContext(
      status: .listening,
      sessionID: session,
      mode: .smartCapture,
      isHandsFree: true,
      pipelineStage: .capture
    ),
    action: nil,
    onAction: {}
  )
  #expect(model.voiceOverLabel == "Dictation listening")
  #expect(announcements == ["Dictation listening"])
  let listeningGeneration = model.presentationGeneration
  model.update(
    context: DictationCapsuleContext(
      status: .listening,
      sessionID: session,
      mode: .smartCapture,
      isHandsFree: true,
      pipelineStage: .capture
    ),
    action: nil,
    onAction: {}
  )
  #expect(model.voiceOverLabel == "Dictation listening")
  #expect(model.presentationGeneration > listeningGeneration)

  model.update(
    context: DictationCapsuleContext(
      status: .cleaning,
      sessionID: session,
      mode: .smartCapture,
      pipelineStage: .polish
    ),
    action: nil,
    onAction: {}
  )
  #expect(model.voiceOverLabel == "Dictation listening")
  model.update(
    context: DictationCapsuleContext(
      status: .saved(destination: "Inbox"),
      sessionID: session,
      mode: .smartCapture
    ),
    action: nil,
    onAction: {}
  )
  #expect(model.voiceOverLabel == "Saved to Inbox")
  #expect(announcements == ["Dictation listening", "Saved to Inbox"])
}

@Test @MainActor func DictationAccessibilityPostsCoalescedAnnouncementsFromThePersistentPanel() {
  let firstSession = UUID(uuidString: "A90D9C4F-6B1E-4C34-8F33-4C88D18B1375")!
  let panel = DictationCapsulePanel()
  var postedElements: [ObjectIdentifier] = []
  var postedText: [String] = []
  let controller = DictationCapsuleController(
    panel: panel,
    announcementPoster: { window, text in
      postedElements.append(ObjectIdentifier(window))
      postedText.append(text)
    }
  )
  let listening = DictationCapsuleContext(
    status: .listening,
    sessionID: firstSession,
    mode: .smartCapture,
    isHandsFree: true,
    pipelineStage: .capture
  )
  controller.render(listening)
  controller.render(listening)
  controller.render(
    DictationCapsuleContext(
      status: .cleaning,
      sessionID: firstSession,
      mode: .smartCapture,
      pipelineStage: .polish
    )
  )
  controller.render(
    DictationCapsuleContext(
      status: .saved(destination: "Inbox"),
      sessionID: firstSession,
      mode: .smartCapture
    )
  )
  controller.render(
    DictationCapsuleContext(
      status: .saved(destination: "Inbox"),
      sessionID: firstSession,
      mode: .smartCapture
    )
  )
  controller.render(
    DictationCapsuleContext(
      status: .saved(destination: "Inbox"),
      sessionID: firstSession,
      mode: .smartCapture,
      pipelineStage: .save
    )
  )
  controller.render(
    DictationCapsuleContext(
      status: .saved(destination: "Archive"),
      sessionID: firstSession,
      mode: .smartCapture
    )
  )
  controller.render(.idle)
  controller.render(
    DictationCapsuleContext(
      status: .listening,
      sessionID: UUID(uuidString: "E58D9D42-35BC-43A5-AB26-1C346DDFAF78")!,
      mode: .smartCapture,
      isHandsFree: true,
      pipelineStage: .capture
    )
  )

  #expect(postedElements == Array(repeating: ObjectIdentifier(panel), count: 4))
  #expect(postedText == [
    "Dictation listening",
    "Saved to Inbox",
    "Saved to Archive",
    "Dictation listening",
  ])
  controller.dismiss()
}

@Test @MainActor func DictationAccessibilityRejectsStaleWaveformLevelsAfterSessionChange() {
  let firstSession = UUID(uuidString: "A90D9C4F-6B1E-4C34-8F33-4C88D18B1375")!
  let secondSession = UUID(uuidString: "E58D9D42-35BC-43A5-AB26-1C346DDFAF78")!
  let panel = DictationCapsulePanel()
  let controller = DictationCapsuleController(panel: panel)

  controller.render(
    DictationCapsuleContext(
      status: .listening,
      sessionID: firstSession,
      mode: .smartCapture,
      isHandsFree: true,
      pipelineStage: .capture
    )
  )
  let firstGeneration = controller.presentationModel.presentationGeneration
  controller.updateAudioLevel(0.20, presentationGeneration: firstGeneration)
  #expect(controller.waveformModel.energy > 0)

  controller.render(
    DictationCapsuleContext(
      status: .listening,
      sessionID: secondSession,
      mode: .smartCapture,
      isHandsFree: true,
      pipelineStage: .capture
    )
  )
  let secondGeneration = controller.presentationModel.presentationGeneration
  #expect(secondGeneration > firstGeneration)
  #expect(controller.waveformModel.energy == 0)

  controller.updateAudioLevel(0.20, presentationGeneration: firstGeneration)
  #expect(controller.waveformModel.energy == 0)
  controller.updateAudioLevel(0.20, presentationGeneration: secondGeneration)
  #expect(controller.waveformModel.energy > 0)
  controller.dismiss()
}

private actor AccessibilitySleepGate {
  private var waiting = false
  private var waiter: CheckedContinuation<Void, Never>?
  private var waitingObserver: CheckedContinuation<Void, Never>?

  func wait() async {
    waiting = true
    waitingObserver?.resume()
    waitingObserver = nil
    await withCheckedContinuation { continuation in
      waiter = continuation
    }
    waiting = false
  }

  func waitUntilWaiting() async {
    if waiting { return }
    await withCheckedContinuation { continuation in
      waitingObserver = continuation
    }
  }

  func resume() {
    waiter?.resume()
    waiter = nil
  }
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
    "Open Fleck",
    "Dictation History",
    "Dictation Settings",
    "Dock Bottom",
    "Dock Left",
    "Dock Right",
  ])
  panel.contentView?.menu?.performActionForItem(at: 4)
  #expect(controller.currentDock == .left)
  #expect(dockChanges == [.left])
  controller.render(.failed("Unavailable"), action: .copy)
  #expect(controller.panel === panel)
  #expect(!panel.canBecomeKey)
  #expect(!panel.canBecomeMain)
  controller.dismiss()
}

@Test @MainActor func DictationAccessibilityChooserRemainsCaptureBoundAndNonactivating() {
  let panel = DictationCapsulePanel()
  let controller = DictationCapsuleController(panel: panel)
  let firstCaptureID = UUID()
  let secondCaptureID = UUID()
  let noteID = UUID()
  var selections: [(UUID, UUID?)] = []
  let chooser = DictationCapsuleChooser(
    ambiguity: .init(
      captureID: firstCaptureID,
      choices: [
        .init(
          destination: .init(noteID: noteID, title: "Projects"),
          contextHint: "Roadmap"
        )
      ]
    )
  )

  controller.render(
    .saved(destination: "Inbox"),
    chooser: chooser,
    onChoice: { selections.append(($0, $1)) }
  )

  #expect(panel.allowsActions)
  #expect(!panel.canBecomeKey)
  #expect(!panel.canBecomeMain)
  controller.selectRoutingChoice(captureID: firstCaptureID, noteID: noteID)
  controller.selectRoutingChoice(captureID: firstCaptureID, noteID: nil)
  #expect(selections.count == 2)
  #expect(selections[0].0 == firstCaptureID)
  #expect(selections[0].1 == noteID)
  #expect(selections[1].0 == firstCaptureID)
  #expect(selections[1].1 == nil)

  controller.render(
    .saved(destination: "Inbox"),
    chooser: .init(
      ambiguity: .init(captureID: secondCaptureID, choices: chooser.choices.map {
        .init(
          destination: .init(noteID: $0.id, title: $0.title),
          contextHint: $0.contextHint
        )
      })
    ),
    onChoice: { selections.append(($0, $1)) }
  )
  controller.selectRoutingChoice(captureID: firstCaptureID, noteID: noteID)
  #expect(selections.count == 2)
  controller.selectRoutingChoice(captureID: secondCaptureID, noteID: noteID)
  #expect(selections.last?.0 == secondCaptureID)

  controller.render(
    .saved(destination: "Projects"),
    chooser: .init(
      ambiguity: .init(
        captureID: secondCaptureID,
        choices: [
          .init(
            destination: .init(noteID: noteID, title: "Projects"),
            contextHint: "Roadmap"
          )
        ]
      ),
      currentDestinationID: noteID,
      currentDestinationTitle: "Projects",
      allowsKeepInInbox: false
    ),
    onChoice: { selections.append(($0, $1)) }
  )
  let movedSelectionCount = selections.count
  controller.selectRoutingChoice(captureID: secondCaptureID, noteID: nil)
  #expect(selections.count == movedSelectionCount)
}

@Test @MainActor func DictationAccessibilityChooserSurvivesDockReinstallationWithUndo() {
  let panel = DictationCapsulePanel()
  let controller = DictationCapsuleController(panel: panel)
  let captureID = UUID()
  let noteID = UUID()
  var selectedCaptureID: UUID?
  let chooser = DictationCapsuleChooser(
    ambiguity: .init(
      captureID: captureID,
      choices: [
        .init(
          destination: .init(noteID: noteID, title: "Projects"),
          contextHint: "Roadmap"
        )
      ]
    )
  )

  controller.render(
    .saved(destination: "Inbox"),
    action: .undo,
    chooser: chooser,
    onChoice: { captureID, _ in selectedCaptureID = captureID }
  )
  controller.setDock(.left)
  controller.selectRoutingChoice(captureID: captureID, noteID: noteID)

  #expect(panel.allowsActions)
  #expect(selectedCaptureID == captureID)
  #expect(!panel.canBecomeKey)
  #expect(!panel.canBecomeMain)
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

@Test func DictationAccessibilityPointerGestureCommitsOnlyBelowFourPoints() {
  var click = FleckRailPointerGesture()
  click.mouseDown(at: CGPoint(x: 10, y: 10), consumed: false)
  click.mouseDragged(to: CGPoint(x: 13, y: 12))
  #expect(click.mouseUp(at: CGPoint(x: 13, y: 12)) == .primaryClick)

  var threshold = FleckRailPointerGesture()
  threshold.mouseDown(at: CGPoint(x: 10, y: 10), consumed: false)
  threshold.mouseDragged(to: CGPoint(x: 14, y: 10))
  #expect(threshold.mouseUp(at: CGPoint(x: 14, y: 10)) == .drag)

  var consumed = FleckRailPointerGesture()
  consumed.mouseDown(at: CGPoint(x: 10, y: 10), consumed: true)
  consumed.mouseDragged(to: CGPoint(x: 30, y: 30))
  #expect(consumed.mouseUp(at: CGPoint(x: 30, y: 30)) == .none)
}

@Test @MainActor func DictationAccessibilityRuntimeMapsAuthoritativeContext() {
  let id = UUID(uuidString: "E871F2A0-5B1B-45BE-9D61-2B27E31C6324")!
  let ownership = DictationShortcutOwnership(
    session: DictationShortcutSession(id: id),
    trigger: .pointer,
    mode: .smartCapture,
    isHandsFree: true
  )
  let event = DictationCoordinatorEvent(
    phase: .failed("Unable to save dictation."),
    terminal: .failed("Unable to save dictation."),
    context: DictationCoordinatorContext(
      sessionID: id,
      mode: .smartCapture,
      pipelineStage: .save,
      cleanupOutcome: .cleaned,
      failureStage: .save
    )
  )

  let context = DictationRuntime.capsuleContext(for: event, ownership: ownership)
  #expect(context.status == .failed("Unable to save dictation."))
  #expect(context.sessionID == id)
  #expect(context.trigger == .pointer)
  #expect(context.mode == DictationMode.smartCapture)
  #expect(context.isHandsFree)
  #expect(context.pipelineStage == DictationPipelineStage.save)
  #expect(context.failureStage == DictationPipelineStage.save)
  #expect(context.failureKind == DictationCapsuleFailureKind.save)
}

@Test @MainActor func DictationAccessibilityMapsArmingNoSpeechAndMissingDestination() {
  let id = UUID(uuidString: "D5F9D8A0-6F3A-4FA0-BBB4-7A3E86F5031C")!
  let ownership = DictationShortcutOwnership(
    session: DictationShortcutSession(id: id),
    trigger: .pointer,
    mode: .smartCapture,
    isHandsFree: true
  )
  let arming = DictationRuntime.capsuleContext(
    for: .init(
      phase: .arming,
      terminal: nil,
      context: DictationCoordinatorContext(
        sessionID: id,
        mode: .smartCapture,
        pipelineStage: .capture,
        cleanupOutcome: nil,
        failureStage: nil
      )
    ),
    ownership: ownership
  )
  #expect(arming.status == .arming)
  #expect(arming.sessionID == id)
  #expect(arming.trigger == .pointer)
  #expect(arming.isHandsFree)

  let noSpeech = DictationRuntime.capsuleContext(
    for: .init(
      phase: .idle,
      terminal: .noSpeech,
      context: DictationCoordinatorContext(
        sessionID: id,
        mode: .smartCapture,
        pipelineStage: .capture,
        cleanupOutcome: nil,
        failureStage: nil
      )
    ),
    ownership: ownership
  )
  #expect(noSpeech.status == .noSpeech)
  #expect(noSpeech.status.presentation.visualMode == .warning)

  let missingDestination = DictationRuntime.capsuleContext(
    for: .init(
      phase: .idle,
      terminal: .saved(mode: .smartCapture, cleanup: .cleaned, destination: nil),
      context: DictationCoordinatorContext(
        sessionID: id,
        mode: .smartCapture,
        pipelineStage: .save,
        cleanupOutcome: .cleaned,
        failureStage: nil
      )
    ),
    ownership: ownership
  )
  #expect(missingDestination.status == .saved(destination: "your notes"))

  let fallback = DictationRuntime.capsuleContext(
    for: .init(
      phase: .idle,
      terminal: .saved(mode: .smartCapture, cleanup: .usedRaw, destination: nil),
      context: DictationCoordinatorContext(
        sessionID: id,
        mode: .smartCapture,
        pipelineStage: .save,
        cleanupOutcome: .usedRaw,
        failureStage: nil
      )
    ),
    ownership: ownership
  )
  #expect(fallback.status == .savedWithoutCleanup(destination: "your notes"))
}

@Test @MainActor func DictationAccessibilityContextMenuKeepsDismissAndRecoveryAfterBaseItems() {
  let panel = DictationCapsulePanel()
  let controller = DictationCapsuleController(panel: panel)
  controller.presentIdle(dock: .bottom, onOpenFleck: {}, onDockChanged: { _ in })
  controller.configureInteraction(
    onPrimaryClick: {},
    onStop: {},
    onCancel: {},
    onOpenFleck: {},
    onOpenHistory: {},
    onOpenSettings: {},
    onDismiss: {},
    onRecovery: {}
  )
  controller.render(.failed("Unable to save dictation."), action: .copy)

  #expect(panel.contentView?.menu?.items.map(\.title) == [
    "Open Fleck",
    "Dictation History",
    "Dictation Settings",
    "Dock Bottom",
    "Dock Left",
    "Dock Right",
    "Dismiss",
    "Copy",
  ])
  controller.presentIdle(dock: .bottom, onOpenFleck: {}, onDockChanged: { _ in })
  #expect(panel.contentView?.menu?.items.map(\.title) == [
    "Open Fleck",
    "Dictation History",
    "Dictation Settings",
    "Dock Bottom",
    "Dock Left",
    "Dock Right",
  ])
  controller.dismiss()
}

@Test @MainActor func DictationAccessibilityIdleShellRoutesOnePrimaryClick() {
  let panel = DictationCapsulePanel()
  let controller = DictationCapsuleController(panel: panel)
  var primaryClicks = 0
  controller.presentIdle(dock: .bottom, onOpenFleck: {}, onDockChanged: { _ in })
  controller.configureInteraction(
    onPrimaryClick: { primaryClicks += 1 },
    onStop: {},
    onCancel: {},
    onOpenFleck: {},
    onOpenHistory: {},
    onOpenSettings: {},
    onDismiss: {},
    onRecovery: {}
  )

  let host = panel.contentView!
  host.frame = CGRect(origin: .zero, size: DictationCapsuleController.idleSize)
  host.layoutSubtreeIfNeeded()
  let eventHost = host.subviews.first!
  let point = NSPoint(x: host.bounds.midX, y: host.bounds.midY)
  let mouseDown = NSEvent.mouseEvent(
    with: .leftMouseDown,
    location: point,
    modifierFlags: [],
    timestamp: 0,
    windowNumber: 0,
    context: nil,
    eventNumber: 1,
    clickCount: 1,
    pressure: 0
  )!
  let mouseUp = NSEvent.mouseEvent(
    with: .leftMouseUp,
    location: point,
    modifierFlags: [],
    timestamp: 0,
    windowNumber: 0,
    context: nil,
    eventNumber: 2,
    clickCount: 1,
    pressure: 0
  )!
  eventHost.mouseDown(with: mouseDown)
  eventHost.mouseUp(with: mouseUp)
  #expect(primaryClicks == 1)
  controller.dismiss()
}

@Test @MainActor func DictationAccessibilityIdleDragTogglesIndicatorsOnlyAfterThreshold() {
  let panel = DictationCapsulePanel()
  let controller = DictationCapsuleController(panel: panel)
  controller.presentIdle(dock: .bottom, onOpenFleck: {}, onDockChanged: { _ in })

  let host = panel.contentView!
  host.frame = CGRect(origin: .zero, size: DictationCapsuleController.idleSize)
  host.layoutSubtreeIfNeeded()
  let eventHost = host.subviews.first!
  let start = NSPoint(x: host.bounds.midX, y: host.bounds.midY)
  let down = NSEvent.mouseEvent(
    with: .leftMouseDown,
    location: start,
    modifierFlags: [],
    timestamp: 0,
    windowNumber: 0,
    context: nil,
    eventNumber: 3,
    clickCount: 1,
    pressure: 0
  )!
  let smallDrag = NSEvent.mouseEvent(
    with: .leftMouseDragged,
    location: NSPoint(x: start.x + 3, y: start.y),
    modifierFlags: [],
    timestamp: 0,
    windowNumber: 0,
    context: nil,
    eventNumber: 4,
    clickCount: 1,
    pressure: 0
  )!
  let thresholdDrag = NSEvent.mouseEvent(
    with: .leftMouseDragged,
    location: NSPoint(x: start.x + 4, y: start.y),
    modifierFlags: [],
    timestamp: 0,
    windowNumber: 0,
    context: nil,
    eventNumber: 5,
    clickCount: 1,
    pressure: 0
  )!
  let up = NSEvent.mouseEvent(
    with: .leftMouseUp,
    location: NSPoint(x: start.x + 4, y: start.y),
    modifierFlags: [],
    timestamp: 0,
    windowNumber: 0,
    context: nil,
    eventNumber: 6,
    clickCount: 1,
    pressure: 0
  )!

  eventHost.mouseDown(with: down)
  eventHost.mouseDragged(with: smallDrag)
  #expect(!controller.presentationModel.showsDockIndicators)
  #expect(renderedView(with: "fleck-dock-indicators", in: host) == nil)
  eventHost.mouseDragged(with: thresholdDrag)
  #expect(controller.presentationModel.showsDockIndicators)
  host.layoutSubtreeIfNeeded()
  guard let indicators = renderedView(with: "fleck-dock-indicators", in: host) else {
    Issue.record("Expected rendered dock indicators after the drag threshold")
    controller.dismiss()
    return
  }
  #expect(indicators.bounds.width > 0)
  #expect(indicators.bounds.height > 0)
  #expect(indicators.hitTest(NSPoint(x: indicators.bounds.midX, y: indicators.bounds.midY)) == nil)
  eventHost.mouseUp(with: up)
  #expect(!controller.presentationModel.showsDockIndicators)
  host.layoutSubtreeIfNeeded()
  #expect(renderedView(with: "fleck-dock-indicators", in: host) == nil)
  controller.dismiss()
}

@Test @MainActor func DictationAccessibilityIdleHitTestMatchesRoundedShell() {
  let panel = DictationCapsulePanel()
  let controller = DictationCapsuleController(panel: panel)
  controller.presentIdle(dock: .bottom, onOpenFleck: {}, onDockChanged: { _ in })
  let host = panel.contentView!
  host.frame = CGRect(origin: .zero, size: DictationCapsuleController.idleSize)
  host.layoutSubtreeIfNeeded()

  #expect(host.hitTest(NSPoint(x: host.bounds.midX, y: host.bounds.midY)) != nil)
  #expect(host.hitTest(NSPoint(x: host.bounds.minX, y: host.bounds.minY)) == nil)
  #expect(host.hitTest(NSPoint(x: host.bounds.maxX + 1, y: host.bounds.midY)) == nil)
  controller.dismiss()
}

@Test @MainActor func DictationAccessibilityHostedButtonsConsumeTheirExactRegions() {
  let panel = DictationCapsulePanel()
  let controller = DictationCapsuleController(panel: panel)
  var primaryClicks = 0
  var stopActions = 0
  var cancelActions = 0
  var dismissActions = 0
  var recoveryActions = 0
  controller.presentIdle(dock: .bottom, onOpenFleck: {}, onDockChanged: { _ in })
  controller.configureInteraction(
    onPrimaryClick: { primaryClicks += 1 },
    onStop: { stopActions += 1 },
    onCancel: { cancelActions += 1 },
    onOpenFleck: {},
    onOpenHistory: {},
    onOpenSettings: {},
    onDismiss: { dismissActions += 1 },
    onRecovery: { recoveryActions += 1 }
  )

  let listening = DictationCapsuleContext(
    status: .listening,
    sessionID: UUID(),
    trigger: .pointer,
    mode: .smartCapture,
    isHandsFree: true,
    pipelineStage: .capture
  )
  controller.render(listening)
  guard let host = panel.contentView else {
    Issue.record("Expected the persistent listening host")
    return
  }
  host.frame = CGRect(origin: .zero, size: DictationCapsuleController.listeningSize)
  host.layoutSubtreeIfNeeded()
  guard let eventHost = host.subviews.first else {
    Issue.record("Expected the event host")
    return
  }

  func click(identifier: String, eventNumber: Int) {
    guard let probe = renderedView(with: identifier, in: host) else {
      Issue.record("Expected rendered action probe \(identifier)")
      return
    }
    let frame = probe.convert(probe.bounds, to: eventHost)
    let point = NSPoint(x: frame.midX, y: frame.midY)
    #expect(probe.hitTest(NSPoint(x: probe.bounds.midX, y: probe.bounds.midY)) == nil)
    let down = NSEvent.mouseEvent(
      with: .leftMouseDown,
      location: point,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: panel.windowNumber,
      context: nil,
      eventNumber: eventNumber,
      clickCount: 1,
      pressure: 0
    )!
    let up = NSEvent.mouseEvent(
      with: .leftMouseUp,
      location: point,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: panel.windowNumber,
      context: nil,
      eventNumber: eventNumber + 1,
      clickCount: 1,
      pressure: 0
    )!
    eventHost.mouseDown(with: down)
    eventHost.mouseUp(with: up)
  }

  click(identifier: "fleck-rail-stop", eventNumber: 98)
  #expect(primaryClicks == 1)
  #expect(stopActions == 0)
  primaryClicks = 0
  controller.presentationModel.setListeningHover(true)
  host.layoutSubtreeIfNeeded()
  click(identifier: "fleck-rail-stop", eventNumber: 100)
  #expect(stopActions == 1)
  #expect(cancelActions == 0)
  #expect(primaryClicks == 0)

  controller.render(listening)
  controller.presentationModel.setListeningHover(true)
  host.layoutSubtreeIfNeeded()
  click(identifier: "fleck-rail-cancel", eventNumber: 102)
  #expect(stopActions == 1)
  #expect(cancelActions == 1)
  #expect(primaryClicks == 0)

  controller.render(.saved(destination: "Inbox"), action: .undo) {
    recoveryActions += 1
  }
  host.frame = CGRect(origin: .zero, size: DictationCapsuleController.savedSize)
  host.layoutSubtreeIfNeeded()
  click(identifier: "fleck-rail-recovery", eventNumber: 104)
  #expect(recoveryActions == 1)
  #expect(dismissActions == 0)
  #expect(primaryClicks == 0)
  controller.dismiss()
}

@Test @MainActor func DictationAccessibilityActionsAreConditionalByContext() {
  let idle = DictationCapsuleContext(
    status: .idle
  )
  let handsFreeListening = DictationCapsuleContext(
    status: .listening,
    mode: .smartCapture,
    isHandsFree: true
  )
  let holdListening = DictationCapsuleContext(
    status: .listening,
    trigger: .hold,
    mode: .smartCapture,
    isHandsFree: false
  )
  let processing = DictationCapsuleContext(
    status: .cleaning,
    mode: .smartCapture
  )
  let repairing = DictationCapsuleContext(
    status: .repairingModel,
    mode: .smartCapture
  )
  let saved = DictationCapsuleContext(
    status: .saved(destination: "Inbox"),
    mode: .smartCapture
  )
  let noSpeech = DictationCapsuleContext(status: .noSpeech)
  let failed = DictationCapsuleContext(status: .failed("save failed"))

  #expect(FleckRailAccessibility.actions(for: idle).isEmpty)
  #expect(FleckRailAccessibility.actions(for: handsFreeListening) == [.stop, .cancel])
  #expect(FleckRailAccessibility.actions(for: holdListening).isEmpty)
  #expect(FleckRailAccessibility.actions(for: processing).isEmpty)
  #expect(FleckRailAccessibility.actions(for: repairing).isEmpty)
  #expect(FleckRailAccessibility.actions(for: saved) == [.dismiss])
  #expect(FleckRailAccessibility.actions(for: noSpeech) == [.dismiss])
  #expect(FleckRailAccessibility.actions(for: failed) == [.dismiss])
}

@Test @MainActor func DictationAccessibilityDragRightClickRestoresDockedFrame() {
  let panel = DictationCapsulePanel()
  let controller = DictationCapsuleController(panel: panel)
  var primaryClicks = 0
  var stopActions = 0
  var cancelActions = 0
  controller.presentIdle(dock: .bottom, onOpenFleck: {}, onDockChanged: { _ in })
  controller.configureInteraction(
    onPrimaryClick: { primaryClicks += 1 },
    onStop: { stopActions += 1 },
    onCancel: { cancelActions += 1 },
    onOpenFleck: {},
    onOpenHistory: {},
    onOpenSettings: {},
    onDismiss: {},
    onRecovery: {}
  )

  guard let host = panel.contentView, let eventHost = host.subviews.first else {
    Issue.record("Expected the persistent event host")
    return
  }
  host.frame = CGRect(origin: .zero, size: DictationCapsuleController.idleSize)
  host.layoutSubtreeIfNeeded()
  let originalFrame = panel.frame
  let start = NSPoint(x: host.bounds.midX, y: host.bounds.midY)
  let down = NSEvent.mouseEvent(
    with: .leftMouseDown,
    location: start,
    modifierFlags: [],
    timestamp: 0,
    windowNumber: panel.windowNumber,
    context: nil,
    eventNumber: 200,
    clickCount: 1,
    pressure: 0
  )!
  let thresholdDrag = NSEvent.mouseEvent(
    with: .leftMouseDragged,
    location: NSPoint(x: start.x + 4, y: start.y),
    modifierFlags: [],
    timestamp: 0,
    windowNumber: panel.windowNumber,
    context: nil,
    eventNumber: 201,
    clickCount: 1,
    pressure: 0
  )!
  let drag = NSEvent.mouseEvent(
    with: .leftMouseDragged,
    location: NSPoint(x: start.x + 12, y: start.y),
    modifierFlags: [],
    timestamp: 0,
    windowNumber: panel.windowNumber,
    context: nil,
    eventNumber: 202,
    clickCount: 1,
    pressure: 0
  )!
  let rightDown = NSEvent.mouseEvent(
    with: .rightMouseDown,
    location: NSPoint(x: start.x + 12, y: start.y),
    modifierFlags: [],
    timestamp: 0,
    windowNumber: panel.windowNumber,
    context: nil,
    eventNumber: 203,
    clickCount: 1,
    pressure: 0
  )!

  eventHost.mouseDown(with: down)
  eventHost.mouseDragged(with: thresholdDrag)
  eventHost.mouseDragged(with: drag)
  #expect(controller.presentationModel.showsDockIndicators)
  #expect(panel.frame != originalFrame)
  let menu = eventHost.menu
  let parentMenu = host.menu
  eventHost.menu = nil
  host.menu = nil
  eventHost.rightMouseDown(with: rightDown)
  eventHost.menu = menu
  host.menu = parentMenu

  let lateUp = NSEvent.mouseEvent(
    with: .leftMouseUp,
    location: NSPoint(x: start.x + 12, y: start.y),
    modifierFlags: [],
    timestamp: 0,
    windowNumber: panel.windowNumber,
    context: nil,
    eventNumber: 204,
    clickCount: 1,
    pressure: 0
  )!
  eventHost.mouseUp(with: lateUp)

  #expect(panel.frame == originalFrame)
  #expect(controller.currentDock == .bottom)
  #expect(!controller.presentationModel.showsDockIndicators)
  host.layoutSubtreeIfNeeded()
  #expect(renderedView(with: "fleck-dock-indicators", in: host) == nil)
  #expect(primaryClicks == 0)
  #expect(stopActions == 0)
  #expect(cancelActions == 0)
  controller.dismiss()
}

@Test func DictationAccessibilityFailureKindAdapterKeepsConciseCopyPure() {
  #expect(
    DictationCapsuleFailureKind.resolve(
      message: DictationFailure.permissionDenied.localizedDescription,
      failureStage: .capture
    ) == .microphoneAccess
  )
  #expect(
    DictationCapsuleFailureKind.resolve(
      message: "Any persistence detail",
      failureStage: .save
    ) == .save
  )
  #expect(
    DictationCapsuleFailureKind.resolve(
      message: "Checksum mismatch",
      failureStage: nil,
      isModelRepair: true
    ) == .modelRepair
  )
  #expect(
    DictationCapsuleFailureKind.resolve(
      message: "A technical detail",
      failureStage: .capture
    ) == nil
  )
}

@Test func DictationAccessibilityPersonalDictionaryExposesSearchRowsTransfersAndPreviewActions()
  throws
{
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let settingsSource = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/SettingsView.swift"),
    encoding: .utf8
  )

  for label in [
    "Personal dictionary filter",
    "Add a new vocabulary word or phrase",
    "Search vocabulary",
    "Clear vocabulary search",
    "Edit \\(entry.preferredForm)",
    "Enable \\(entry.preferredForm)",
    "Approve \\(suggestion.preferredForm)",
    "Edit and approve \\(suggestion.preferredForm)",
    "Dismiss \\(suggestion.preferredForm)",
    "Export complete personal dictionary",
    "Export visible entries as CSV",
    "Import personal dictionary",
    "Confirm dictionary import",
    "Cancel dictionary import",
  ] {
    #expect(settingsSource.contains("accessibilityLabel(\"\(label)\")"))
  }
  #expect(settingsSource.contains("accessibilityLabel(\"Word or phrase\")"))
  #expect(settingsSource.contains("accessibilityLabel(\"Correct from\")"))
  #expect(settingsSource.contains("accessibilityLabel(\"Delete vocabulary word\")"))
  #expect(settingsSource.contains("accessibilityHint(\"Searches saved words and corrections\")"))
  #expect(!settingsSource.contains(".searchable("))
  #expect(settingsSource.contains(".accessibilityValue("))
  #expect(settingsSource.contains(".accessibilityHint("))
  #expect(settingsSource.contains(".focusable()"))
  #expect(settingsSource.contains(".keyboardShortcut(.defaultAction)"))
  #expect(settingsSource.contains("accessibilityImportLabel"))
}

@Test func DictationAccessibilityImportPreviewExposesStatusAndErrorInsideTheSheet() throws {
  let previewSource = try personalDictionaryImportPreviewSource()

  #expect(previewSource.contains("if let errorMessage = viewModel.errorMessage"))
  #expect(previewSource.contains("else if let statusMessage = viewModel.statusMessage"))
  #expect(previewSource.contains("accessibilityLabel(\"Dictionary import error\")"))
  #expect(previewSource.contains("accessibilityLabel(\"Dictionary import status\")"))
}

@Test func DictationAccessibilitySuggestionEditExposesStatusAndErrorInsideTheSheet() throws {
  let settingsSource = try settingsViewSource()
  let editSource = try personalDictionarySuggestionEditSource(settingsSource)

  #expect(settingsSource.contains("errorMessage: viewModel.errorMessage"))
  #expect(settingsSource.contains("statusMessage: viewModel.statusMessage"))
  #expect(editSource.contains("if let errorMessage"))
  #expect(editSource.contains("else if let statusMessage"))
  #expect(editSource.contains("accessibilityLabel(\"Suggestion edit error\")"))
  #expect(editSource.contains("accessibilityLabel(\"Suggestion edit status\")"))
  #expect(editSource.contains("accessibilityValue(errorMessage)"))
  #expect(editSource.contains("accessibilityValue(statusMessage)"))
}

@Test func DictationAccessibilityImportPreviewRendersConflictsOutsideTheChangeBranch() throws {
  let previewLines = try personalDictionaryImportPreviewSource().split(
    separator: "\n",
    omittingEmptySubsequences: false
  )
  let changesCondition = try #require(previewLines.first {
    $0.contains("if viewModel.importPreviewRows.isEmpty")
  })
  let conflictsLoop = try #require(previewLines.first {
    $0.contains("ForEach(viewModel.importConflictRows)")
  })

  #expect(
    changesCondition.prefix { $0 == " " }.count
      == conflictsLoop.prefix { $0 == " " }.count
  )
}

private func personalDictionaryImportPreviewSource() throws -> String {
  let settingsSource = try settingsViewSource()
  let start = try #require(settingsSource.range(
    of: "private struct PersonalDictionaryImportPreviewSheet"
  ))
  let end = try #require(settingsSource.range(
    of: "private struct PersonalDictionaryTransferDocument",
    range: start.upperBound..<settingsSource.endIndex
  ))
  return String(settingsSource[start.lowerBound..<end.lowerBound])
}

private func personalDictionarySuggestionEditSource(_ settingsSource: String) throws -> String {
  let start = try #require(settingsSource.range(
    of: "private struct PersonalDictionarySuggestionEditSheet"
  ))
  let end = try #require(settingsSource.range(
    of: "private struct PersonalDictionaryImportPreviewSheet",
    range: start.upperBound..<settingsSource.endIndex
  ))
  return String(settingsSource[start.lowerBound..<end.lowerBound])
}

private func settingsViewSource() throws -> String {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  return try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/SettingsView.swift"),
    encoding: .utf8
  )
}
