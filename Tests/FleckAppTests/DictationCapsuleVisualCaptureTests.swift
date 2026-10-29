#if os(macOS)
  import AppKit
  import Foundation
  import FleckCore
  import SwiftUI
  import Testing

  @testable import FleckApp

  private let visualCaptureSessionID = UUID(uuidString: "56B8F4D6-19F4-4EA0-8AC4-2AB87A9F0D61")!

  @MainActor
  private final class VisualCaptureClock {
    var now: TimeInterval = 50
  }

  @MainActor
  private func visualCaptureContext(
    _ status: DictationCapsuleStatus,
    detailText: String? = nil,
    compactDetailText: String? = nil,
    isHandsFree: Bool = false,
    stage: DictationPipelineStage? = nil,
    cleanup: DictationCleanupOutcome? = nil,
    cleanupFallbackProvenance: DictationCleanupFallbackProvenance? = nil,
    failureStage: DictationPipelineStage? = nil,
    failureKind: DictationCapsuleFailureKind? = nil
  ) -> DictationCapsuleContext {
    DictationCapsuleContext(
      status: status,
      detailText: detailText,
      compactDetailText: compactDetailText,
      sessionID: visualCaptureSessionID,
      trigger: isHandsFree ? .doubleTap : .hold,
      mode: .smartCapture,
      isHandsFree: isHandsFree,
      pipelineStage: stage,
      cleanupOutcome: cleanup,
      cleanupFallbackProvenance: cleanupFallbackProvenance,
      failureStage: failureStage,
      failureKind: failureKind
    )
  }

  @MainActor
  private func captureVisualState(
    _ name: String,
    controller: DictationCapsuleController,
    size: CGSize? = nil,
    directory: URL?
  ) async throws {
    guard let host = controller.panel.contentView else {
      Issue.record("Expected a hosted Fleck rail for \(name)")
      return
    }
    let screen = try #require(controller.panel.screen ?? NSScreen.main ?? NSScreen.screens.first)
    let renderedContext = controller.currentContext
    let presentation = DictationCapsulePresentation(
      status: renderedContext.status,
      action: controller.presentationModel.action,
      chooser: controller.currentChooser,
      context: renderedContext
    )
    let expectedFrame: CGRect
    if controller.errorPresentationModel.presentation != nil {
      expectedFrame = DictationCapsuleController.errorSurfaceFrame(
        for: controller.currentDock,
        in: screen.visibleFrame
      )
    } else if controller.fleckPillModel.usesFixedHost {
      expectedFrame = DictationCapsuleController.livePillFrame(in: screen.visibleFrame)
    } else {
      expectedFrame = DictationCapsuleController.frame(
        for: controller.currentDock,
        size: DictationCapsuleController.size(
          for: renderedContext.status,
          measuredWidth: presentation.measuredWidth,
          widthCeiling: presentation.widthCeiling
        ),
        in: screen.visibleFrame
      )
    }
    let panelFrame = controller.panel.frame
    #expect(abs(panelFrame.minX - expectedFrame.minX) <= 0.5)
    #expect(abs(panelFrame.minY - expectedFrame.minY) <= 0.5)
    #expect(abs(panelFrame.width - expectedFrame.width) <= 0.5)
    #expect(abs(panelFrame.height - expectedFrame.height) <= 0.5)
    if let size { #expect(panelFrame.size == size) }
    #expect(host.bounds.size == panelFrame.size)
    host.layoutSubtreeIfNeeded()

    if controller.fleckPillModel.isVisible,
      let sessionID = controller.fleckPillModel.sessionID
    {
      let clock = ContinuousClock()
      let deadline = clock.now.advanced(by: .seconds(2))
      var matchingSnapshot: FleckPillRenderSnapshot?
      while matchingSnapshot == nil && clock.now < deadline {
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        if let snapshot = controller.fleckPillModel.renderReceipt.snapshot(for: sessionID),
          controller.fleckPillModel.sessionID == sessionID,
          snapshot.sessionID == sessionID,
          snapshot.generation == controller.fleckPillModel.renderGeneration,
          snapshot.frame == controller.fleckPillModel.frame
        {
          matchingSnapshot = snapshot
          break
        }
        try await Task.sleep(for: .milliseconds(16))
      }
      _ = try #require(matchingSnapshot)
    }

    let imageRep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: imageRep)
    #expect(imageRep.pixelsWide > 0)
    #expect(imageRep.pixelsHigh > 0)
    if let sessionID = controller.fleckPillModel.sessionID {
      let snapshot = try #require(controller.fleckPillModel.renderReceipt.snapshot(for: sessionID))
      #expect(snapshot.sessionID == sessionID)
      #expect(snapshot.generation == controller.fleckPillModel.renderGeneration)
      #expect(hasBrightPixel(in: host.bounds, imageRep: imageRep, hostedBy: host))
    } else if controller.fleckPillModel.state == .standby {
      #expect(hasBrightPixel(in: host.bounds, imageRep: imageRep, hostedBy: host))
    }

    guard let directory else { return }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let destination = directory.appendingPathComponent("\(name).png")
    try #require(
      imageRep.representation(using: .png, properties: [:])
    ).write(to: destination)
  }

  @MainActor
  private func prepareSyntheticWaveformFixture(for controller: DictationCapsuleController) {
    let start = ProcessInfo.processInfo.systemUptime - 0.08
    controller.waveformModel.reset()
    controller.waveformModel.beginListening(monotonicNow: start)
    controller.waveformModel.receive(level: 0.20, monotonicNow: start + 0.04)
    controller.waveformModel.receive(level: 0.14, monotonicNow: start + 0.08)
  }

  @MainActor
  private func visualProbe(
    _ identifier: String,
    in view: NSView
  ) -> NSView? {
    if view.identifier?.rawValue == identifier { return view }
    for subview in view.subviews {
      if let match = visualProbe(identifier, in: subview) { return match }
    }
    return nil
  }

  @MainActor
  private func visualFrame(_ identifier: String, in host: NSView) throws -> CGRect {
    let probe = try #require(visualProbe(identifier, in: host))
    return probe.convert(probe.bounds, to: host)
  }

  @MainActor
  private func canonicalFleckMarkImage() -> NSImage? {
    let sourceRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let markDirectory = sourceRoot.appendingPathComponent("Assets", isDirectory: true)
    guard
      case .image(let image) = FleckMark.load(
        template: true,
        resourceURL: markDirectory,
        isPackagedApp: true
      )
    else {
      return nil
    }
    return image
  }

  @MainActor
  private func visualDescendants(of view: NSView) -> [NSView] {
    view.subviews + view.subviews.flatMap(visualDescendants)
  }

  @MainActor
  private func captureLivePillArtwork(
    _ name: String,
    frame: FleckPillArtworkFrame,
    directory: URL?
  ) throws {
    let renderer = ImageRenderer(content: FleckPillCanvas(frame: frame, backdrop: .dark))
    renderer.proposedSize = ProposedViewSize(width: 180, height: 39)
    renderer.isOpaque = true
    renderer.colorMode = .nonLinear
    let image = try #require(renderer.cgImage)
    #expect(image.width == 180)
    #expect(image.height == 39)
    let bitmap = NSBitmapImageRep(cgImage: image)
    let visiblePixels = (0..<bitmap.pixelsHigh).reduce(into: 0) { count, y in
      for x in 0..<bitmap.pixelsWide {
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
        if max(color.redComponent, color.greenComponent, color.blueComponent) > 0.06 {
          count += 1
        }
      }
    }
    #expect(visiblePixels > 0)
    guard let directory else { return }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let destination = directory.appendingPathComponent("synthetic-offscreen-\(name).png")
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: destination)
  }

  @Test @MainActor
  func DictationCapsuleActiveModesStaySingleRowWithoutCoveringLiveControls() throws {
    let panel = DictationCapsulePanel()
    let controller = DictationCapsuleController(panel: panel)
    defer { controller.dismiss() }

    func host(for context: DictationCapsuleContext) throws -> NSView {
      controller.render(context)
      let size = DictationCapsuleController.size(for: context.status)
      panel.setFrame(CGRect(origin: .zero, size: size), display: false)
      panel.contentView?.frame = CGRect(origin: .zero, size: size)
      panel.contentView?.layoutSubtreeIfNeeded()
      return try #require(panel.contentView)
    }

    for dock in DictationCapsuleDock.allCases {
      controller.setDock(dock)
      let focused = DictationCapsuleContext(
        status: .listening,
        detailText: "Dictating into Travel plans",
        compactDetailText: "Travel plans",
        sessionID: visualCaptureSessionID,
        trigger: .hold,
        mode: .focused,
        pipelineStage: .capture
      )
      let focusedHost = try host(for: focused)
      #expect(DictationCapsuleController.size(for: focused.status).height == 36)
      #expect(visualProbe("fleck-rail-context", in: focusedHost) == nil)
      let focusedWaveform = try visualFrame("fleck-rail-waveform", in: focusedHost)
      let focusedActions = try visualFrame("fleck-rail-actions", in: focusedHost)
      #expect(abs(focusedWaveform.midX - focusedHost.bounds.midX) <= 0.5)
      #expect(focusedHost.bounds.contains(focusedWaveform))
      #expect(focusedHost.bounds.contains(focusedActions))
      #expect(!focusedWaveform.intersects(focusedActions))
      #expect(visualProbe("fleck-rail-elapsed", in: focusedHost) == nil)

      let smartCapture = DictationCapsuleContext(
        status: .listening,
        detailText: "Smart Capture",
        compactDetailText: "Smart Capture",
        sessionID: UUID(),
        trigger: .doubleTap,
        mode: .smartCapture,
        isHandsFree: true,
        pipelineStage: .capture
      )
      let smartHost = try host(for: smartCapture)
      #expect(DictationCapsuleController.size(for: smartCapture.status).height == 36)
      #expect(visualProbe("fleck-rail-context", in: smartHost) == nil)
      let smartWaveform = try visualFrame("fleck-rail-waveform", in: smartHost)
      let smartActions = try visualFrame("fleck-rail-actions", in: smartHost)
      #expect(abs(smartWaveform.midX - smartHost.bounds.midX) <= 0.5)
      #expect(smartHost.bounds.contains(smartWaveform))
      #expect(smartHost.bounds.contains(smartActions))
      #expect(!smartWaveform.intersects(smartActions))
      #expect(visualProbe("fleck-rail-elapsed", in: smartHost) == nil)
    }

    controller.setDock(.bottom)
    let focusedProcessing = DictationCapsuleContext(
      status: .cleaning,
      detailText: "Dictating into Travel plans",
      compactDetailText: "Travel plans",
      sessionID: visualCaptureSessionID,
      trigger: .hold,
      mode: .focused,
      pipelineStage: .polish
    )
    let focusedProcessingHost = try host(for: focusedProcessing)
    #expect(DictationCapsuleController.size(for: focusedProcessing.status).height == 36)
    #expect(visualProbe("fleck-rail-context", in: focusedProcessingHost) == nil)
    let focusedMark = try visualFrame("fleck-rail-mark", in: focusedProcessingHost)
    #expect(focusedProcessingHost.bounds.contains(focusedMark))

    let smartProcessing = DictationCapsuleContext(
      status: .cleaning,
      detailText: "Smart Capture",
      sessionID: UUID(),
      trigger: .hold,
      mode: .smartCapture,
      pipelineStage: .polish
    )
    let smartProcessingHost = try host(for: smartProcessing)
    let mark = try visualFrame("fleck-rail-mark", in: smartProcessingHost)
    #expect(DictationCapsuleController.size(for: smartProcessing.status).height == 36)
    #expect(visualProbe("fleck-rail-context", in: smartProcessingHost) == nil)
    #expect(smartProcessingHost.bounds.contains(mark))
  }

  @Test @MainActor func DictationCapsuleLivePillRendersBottomStandbyArmingListeningAndProcessing() async throws {
    let panel = DictationCapsulePanel()
    panel.appearance = NSAppearance(named: .darkAqua)
    let clock = VisualCaptureClock()
    let controller = DictationCapsuleController(
      panel: panel,
      monotonicNow: { clock.now },
      automaticallyAdvancesLivePill: false
    )
    controller.setReduceMotionOverrideForTesting(false)
    defer { controller.dismiss() }
    controller.presentIdle(dock: .bottom, onOpenFleck: {}, onDockChanged: { _ in })
    let outputDirectory = ProcessInfo.processInfo.environment["FLECK_PILL_LIVE_CAPTURE_DIRECTORY"]
      .map { URL(fileURLWithPath: $0, isDirectory: true) }

    #expect(controller.fleckPillModel.state == .standby)
    try await captureVisualState(
      "live-pill-bottom-standby",
      controller: controller,
      size: DictationCapsuleController.livePillHostSize,
      directory: nil
    )
    try captureLivePillArtwork(
      "live-pill-bottom-standby",
      frame: controller.fleckPillModel.frame,
      directory: outputDirectory
    )

    let sessionID = visualCaptureSessionID
    let coordinatorContext = DictationCoordinatorContext(
      sessionID: sessionID,
      mode: .smartCapture,
      pipelineStage: .capture,
      cleanupOutcome: nil,
      failureStage: nil
    )
    controller.render(
      visualCaptureContext(.arming, stage: .capture),
      coordinatorEvent: DictationCoordinatorEvent(
        phase: .arming,
        terminal: nil,
        context: coordinatorContext
      )
    )
    controller.fleckPillModel.tick(at: clock.now + 0.16, displayedEnergy: 0)
    #expect(controller.fleckPillModel.state == .opening)
    #expect(controller.fleckPillModel.frame.energy == 0)
    #expect(controller.fleckPillModel.frame.activationMix == 0)
    try await captureVisualState(
      "live-pill-bottom-arming",
      controller: controller,
      size: DictationCapsuleController.livePillHostSize,
      directory: nil
    )
    #expect(
      controller.fleckPillModel.displayedFrame(for: sessionID)
        == controller.fleckPillModel.frame
    )
    try captureLivePillArtwork(
      "live-pill-bottom-arming",
      frame: controller.fleckPillModel.frame,
      directory: outputDirectory
    )

    clock.now += 0.16
    controller.render(
      visualCaptureContext(.listening, stage: .capture),
      coordinatorEvent: DictationCoordinatorEvent(
        phase: .listening(mode: .smartCapture, engine: .standard),
        terminal: nil,
        context: coordinatorContext
      )
    )
    #expect(controller.fleckPillModel.state == .listening)
    #expect(controller.fleckPillModel.frame.energy == 0)
    #expect(controller.fleckPillModel.frame.activationMix == 1)
    try await captureVisualState(
      "live-pill-bottom-listening-quiet",
      controller: controller,
      size: DictationCapsuleController.livePillHostSize,
      directory: nil
    )
    try captureLivePillArtwork(
      "live-pill-bottom-listening-quiet",
      frame: controller.fleckPillModel.frame,
      directory: outputDirectory
    )

    controller.updateAudioLevel(0.2)
    #expect(controller.fleckPillModel.frame.energy > 0)
    clock.now += 0.16
    controller.fleckPillModel.tick(
      at: clock.now,
      displayedEnergy: controller.fleckPillModel.frame.energy
    )
    try await captureVisualState(
      "live-pill-bottom-listening-active",
      controller: controller,
      size: DictationCapsuleController.livePillHostSize,
      directory: nil
    )
    try captureLivePillArtwork(
      "live-pill-bottom-listening-active",
      frame: controller.fleckPillModel.frame,
      directory: outputDirectory
    )
    let consumedListeningFrame = try #require(
      controller.fleckPillModel.displayedFrame(for: sessionID)
    )
    #expect(consumedListeningFrame.energy > 0)

    let processingContext = DictationCoordinatorContext(
      sessionID: sessionID,
      mode: .smartCapture,
      pipelineStage: .polish,
      cleanupOutcome: .pending,
      failureStage: nil
    )
    controller.render(
      visualCaptureContext(.cleaning, stage: .polish, cleanup: .pending),
      coordinatorEvent: DictationCoordinatorEvent(
        phase: .cleaning,
        terminal: nil,
        context: processingContext
      )
    )
    #expect(controller.fleckPillModel.state == .processing)
    #expect(controller.fleckPillModel.frame.expansion == consumedListeningFrame.expansion)
    #expect(controller.fleckPillModel.frame.energy == consumedListeningFrame.energy)
    #expect(controller.fleckPillModel.frame.phase == consumedListeningFrame.phase)
    clock.now += 0.16
    controller.fleckPillModel.tick(at: clock.now, displayedEnergy: consumedListeningFrame.energy)
    try await captureVisualState(
      "live-pill-bottom-processing",
      controller: controller,
      size: DictationCapsuleController.livePillHostSize,
      directory: nil
    )
    try captureLivePillArtwork(
      "live-pill-bottom-processing",
      frame: controller.fleckPillModel.frame,
      directory: outputDirectory
    )
  }

  @Test @MainActor func DictationCapsuleSingleRowActiveLayoutKeepsCenteredGeometry() throws {
    let mark = try #require(canonicalFleckMarkImage())
    let panel = DictationCapsulePanel()
    let controller = DictationCapsuleController(panel: panel, markLoader: { mark })
    defer { controller.dismiss() }
    let listeningContext = DictationCapsuleContext(
      status: .listening,
      detailText: "Dictating into Quarterly planning and launch readiness notes",
      compactDetailText: "Quarterly planning and launch readiness notes",
      sessionID: visualCaptureSessionID,
      trigger: .doubleTap,
      mode: .smartCapture,
      isHandsFree: true,
      pipelineStage: .capture
    )
    #expect(
      DictationCapsuleController.size(for: listeningContext.status)
        == DictationCapsuleController.listeningSize
    )

    func listeningFrames() throws -> (
      bounds: CGRect,
      mark: CGRect,
      waveform: CGRect,
      actions: CGRect,
      stop: CGRect,
      cancel: CGRect
    ) {
      let host = try #require(panel.contentView)
      host.frame = CGRect(origin: .zero, size: panel.frame.size)
      host.layoutSubtreeIfNeeded()
      return (
        host.bounds,
        try visualFrame("fleck-rail-mark", in: host),
        try visualFrame("fleck-rail-waveform", in: host),
        try visualFrame("fleck-rail-actions", in: host),
        try visualFrame("fleck-rail-stop", in: host),
        try visualFrame("fleck-rail-cancel", in: host)
      )
    }

    func expectSamePlacement(
      _ first: (
        bounds: CGRect,
        mark: CGRect,
        waveform: CGRect,
        actions: CGRect,
        stop: CGRect,
        cancel: CGRect
      ),
      _ second: (
        bounds: CGRect,
        mark: CGRect,
        waveform: CGRect,
        actions: CGRect,
        stop: CGRect,
        cancel: CGRect
      )
    ) {
      for (lhs, rhs) in [
        (first.bounds, second.bounds),
        (first.mark, second.mark),
        (first.actions, second.actions),
        (first.stop, second.stop),
        (first.cancel, second.cancel),
      ] {
        #expect(abs(lhs.minX - rhs.minX) <= 0.5)
        #expect(abs(lhs.minY - rhs.minY) <= 0.5)
        #expect(abs(lhs.width - rhs.width) <= 0.5)
        #expect(abs(lhs.height - rhs.height) <= 0.5)
      }
      #expect(abs(first.waveform.midX - second.waveform.midX) <= 0.5)
      #expect(abs(first.waveform.midY - second.waveform.midY) <= 0.5)
    }

    for dock in DictationCapsuleDock.allCases {
      panel.orderOut(nil)
      controller.setDock(dock)
      controller.render(listeningContext)
      #expect(abs(panel.frame.width - DictationCapsuleController.listeningSize.width) <= 0.5)
      #expect(abs(panel.frame.height - 36) <= 0.5)
      #expect(
        controller.presentationModel.voiceOverLabel
          == "Dictation listening. Dictating into Quarterly planning and launch readiness notes"
      )

      controller.waveformModel.reset()
      controller.waveformModel.beginListening(monotonicNow: ProcessInfo.processInfo.systemUptime)
      let quiet = try listeningFrames()
      #expect(visualProbe("fleck-rail-context", in: try #require(panel.contentView)) == nil)
      #expect(abs(quiet.waveform.midX - quiet.bounds.midX) <= 0.5)
      #expect(abs(quiet.mark.midY - quiet.waveform.midY) <= 0.5)
      #expect(abs(quiet.actions.midY - quiet.waveform.midY) <= 0.5)
      for frame in [quiet.mark, quiet.waveform, quiet.actions] {
        #expect(quiet.bounds.contains(frame))
      }
      #expect(!quiet.mark.intersects(quiet.waveform))
      #expect(!quiet.waveform.intersects(quiet.actions))
      #expect(visualProbe("fleck-rail-elapsed", in: try #require(panel.contentView)) == nil)
      #expect(quiet.stop.size == CGSize(width: 28, height: 28))
      #expect(quiet.cancel.size == CGSize(width: 28, height: 28))
      #expect(quiet.actions.contains(quiet.stop))
      #expect(quiet.actions.contains(quiet.cancel))
      #expect(!quiet.stop.intersects(quiet.cancel))

      let shellFrame = panel.frame
      controller.presentationModel.setListeningHover(true)
      let hovered = try listeningFrames()
      expectSamePlacement(quiet, hovered)
      #expect(panel.frame == shellFrame)

      controller.presentationModel.setListeningHover(false)
      controller.waveformModel.receive(level: 0.20, monotonicNow: ProcessInfo.processInfo.systemUptime)
      let loud = try listeningFrames()
      expectSamePlacement(quiet, loud)

      controller.waveformModel.reset()
      controller.waveformModel.beginListening(monotonicNow: ProcessInfo.processInfo.systemUptime)
      let rested = try listeningFrames()
      expectSamePlacement(quiet, rested)
    }

    let contextTextPairs: [(String?, String?)] = [
      ("Dictating into Inbox", nil),
      (nil, "Inbox"),
    ]
    for (detailText, compactDetailText) in contextTextPairs {
      panel.orderOut(nil)
      controller.render(DictationCapsuleContext(
        status: .listening,
        detailText: detailText,
        compactDetailText: compactDetailText,
        sessionID: UUID(),
        trigger: .hold,
        mode: .smartCapture,
        pipelineStage: .capture
      ))
      #expect(DictationCapsuleController.size(for: controller.currentContext.status).height == 36)
      #expect(abs(panel.frame.height - 36) <= 0.5)
      #expect(visualProbe("fleck-rail-context", in: try #require(panel.contentView)) == nil)
    }

    panel.orderOut(nil)
    controller.render(DictationCapsuleContext(
      status: .listening,
      sessionID: UUID(),
      trigger: .hold,
      mode: .smartCapture,
      pipelineStage: .capture
    ))
    #expect(panel.frame.size == DictationCapsuleController.listeningSize)

    let progress: [(DictationCapsuleStatus, DictationPipelineStage)] = [
      (.finalizing, .capture),
      (.cleaning, .polish),
      (.routing, .organize),
      (.saving, .save),
    ]
    for (status, stage) in progress {
      panel.orderOut(nil)
      controller.render(DictationCapsuleContext(
        status: status,
        detailText: "Smart Capture",
        compactDetailText: "Smart Capture",
        sessionID: visualCaptureSessionID,
        trigger: .hold,
        mode: .smartCapture,
        pipelineStage: stage
      ))
      #expect(DictationCapsuleController.size(for: controller.currentContext.status).height == 36)
      #expect(abs(panel.frame.width - DictationCapsuleController.activeSize.width) <= 0.5)
      #expect(abs(panel.frame.height - 36) <= 0.5)
      let host = try #require(panel.contentView)
      host.frame = CGRect(origin: .zero, size: panel.frame.size)
      host.layoutSubtreeIfNeeded()
      let mark = try visualFrame("fleck-rail-mark", in: host)
      #expect(visualProbe("fleck-rail-context", in: host) == nil)
      #expect(host.bounds.contains(mark))
    }

    panel.orderOut(nil)
    controller.render(DictationCapsuleContext(
      status: .cleaning,
      sessionID: visualCaptureSessionID,
      trigger: .hold,
      mode: .smartCapture,
      pipelineStage: .polish
    ))
    #expect(panel.frame.size == DictationCapsuleController.activeSize)
  }

  @Test @MainActor func DictationCapsuleSingleRowFramesClampInsideSmallOffsetVisibleFrames() {
    let activeSizes = [
      DictationCapsuleController.size(for: .listening),
      DictationCapsuleController.size(for: .cleaning),
    ]
    #expect(activeSizes == [CGSize(width: 176, height: 36), CGSize(width: 192, height: 36)])
    let terminalChooser = DictationCapsuleChooser(
      ambiguity: .init(
        captureID: UUID(),
        choices: [
          .init(
            destination: .init(noteID: UUID(), title: "Projects"),
            contextHint: "Synthetic roadmap"
          )
        ]
      )
    )
    let terminalPresentation = DictationCapsulePresentation(
      status: .idle,
      action: .undo,
      chooser: terminalChooser
    )
    let sizes = activeSizes + [
      DictationCapsuleController.size(
        for: .idle,
        measuredWidth: terminalPresentation.measuredWidth,
        widthCeiling: terminalPresentation.widthCeiling
      )
    ]
    #expect(terminalPresentation.visibleText == nil)
    #expect(terminalPresentation.widthCeiling == DictationCapsuleController.idleSize.width)
    #expect(terminalPresentation.measuredWidth == DictationCapsuleController.idleSize.width)
    let visibleFrames = [
      CGRect(x: -1_280, y: 37, width: 120, height: 44),
      CGRect(x: 640, y: 280, width: 320, height: 90),
    ]

    for visibleFrame in visibleFrames {
      for size in sizes {
        for dock in DictationCapsuleDock.allCases {
          let frame = DictationCapsuleController.frame(
            for: dock,
            size: size,
            in: visibleFrame
          )
          #expect(visibleFrame.contains(frame))
          #expect(frame.width == min(size.width, visibleFrame.width))
          #expect(frame.height == min(size.height, visibleFrame.height))
          switch dock {
          case .bottom:
            #expect(abs(frame.midX - visibleFrame.midX) <= 0.5)
            #expect(
              frame.minY
                == visibleFrame.minY
                  + min(10, max((visibleFrame.height - frame.height) / 2, 0))
            )
          case .left:
            #expect(
              frame.minX
                == visibleFrame.minX
                  + min(10, max((visibleFrame.width - frame.width) / 2, 0))
            )
            #expect(abs(frame.midY - visibleFrame.midY) <= 0.5)
          case .right:
            #expect(
              frame.maxX
                == visibleFrame.maxX
                  - min(10, max((visibleFrame.width - frame.width) / 2, 0))
            )
            #expect(abs(frame.midY - visibleFrame.midY) <= 0.5)
          }
        }
      }
    }
  }

  @Test @MainActor
  func DictationCapsuleBothModesOmitActiveHeaders() throws {
    let panel = DictationCapsulePanel()
    let controller = DictationCapsuleController(panel: panel)
    defer { controller.dismiss() }
    let statuses: [DictationCapsuleStatus] = [
      .listening, .finalizing, .cleaning, .routing, .saving,
    ]
    for mode in [DictationMode.focused, .smartCapture] {
      for dock in DictationCapsuleDock.allCases {
        for status in statuses {
          panel.orderOut(nil)
          controller.setDock(dock)
          controller.render(DictationCapsuleContext(
            status: status,
            detailText: "Synthetic captured destination",
            compactDetailText: "Synthetic context",
            sessionID: visualCaptureSessionID,
            trigger: .doubleTap,
            mode: mode,
            isHandsFree: true
          ))
          let host = try #require(panel.contentView)
          host.layoutSubtreeIfNeeded()
          #expect(visualProbe("fleck-rail-context", in: host) == nil)
          #expect(panel.frame.size == DictationCapsuleController.size(for: status))
          #expect(panel.frame.height == 36)
        }
      }
    }
  }

  @Test @MainActor func DictationCapsuleFocusedDestinationStaysCompactWithoutVisualHeader() throws {
    let panel = DictationCapsulePanel()
    let controller = DictationCapsuleController(panel: panel)
    defer { controller.dismiss() }
    let detail = "Dictating into Quarterly planning and launch readiness notes"
    let compactDetail = "Quarterly planning and launch readiness notes"

    for dock in DictationCapsuleDock.allCases {
      panel.orderOut(nil)
      controller.setDock(dock)
      let listening = DictationCapsuleContext(
        status: .listening,
        detailText: detail,
        compactDetailText: compactDetail,
        sessionID: UUID(),
        trigger: .doubleTap,
        mode: .focused,
        isHandsFree: true,
        pipelineStage: .capture
      )
      controller.render(listening)
      controller.presentationModel.setListeningHover(true)
      let host = try #require(panel.contentView)
      host.layoutSubtreeIfNeeded()
      let waveform = try visualFrame("fleck-rail-waveform", in: host)
      let stop = try visualFrame("fleck-rail-stop", in: host)
      let cancel = try visualFrame("fleck-rail-cancel", in: host)
      #expect(panel.frame.size == DictationCapsuleController.listeningSize)
      #expect(visualProbe("fleck-rail-context", in: host) == nil)
      #expect(abs(waveform.midX - host.bounds.midX) <= 0.5)
      #expect(stop.size == CGSize(width: 28, height: 28))
      #expect(cancel.size == CGSize(width: 28, height: 28))
      #expect(host.bounds.contains(stop))
      #expect(host.bounds.contains(cancel))
      #expect(controller.presentationModel.voiceOverLabel == "Dictation listening. \(detail)")

      panel.orderOut(nil)
      let processing = DictationCapsuleContext(
        status: .cleaning,
        detailText: detail,
        compactDetailText: compactDetail,
        sessionID: listening.sessionID,
        trigger: .doubleTap,
        mode: .focused,
        isHandsFree: true,
        pipelineStage: .polish
      )
      controller.render(processing)
      host.layoutSubtreeIfNeeded()
      let mark = try visualFrame("fleck-rail-mark", in: host)
      #expect(panel.frame.size == DictationCapsuleController.activeSize)
      #expect(visualProbe("fleck-rail-context", in: host) == nil)
      #expect(host.bounds.contains(mark))
      #expect(
        DictationCapsulePresentation(status: processing.status, context: processing)
          .voiceOverText == "Polishing dictation. \(detail)"
      )
    }
  }

  @Test @MainActor func DictationCapsuleSettledBottomPanelsStayCenteredOnTheirActualScreen()
    async throws
  {
    let outputDirectory = ProcessInfo.processInfo.environment["FLECK_PACKET_C_CAPTURE_DIR"]
      .map { URL(fileURLWithPath: $0, isDirectory: true) }
    if let outputDirectory {
      try FileManager.default.createDirectory(
        at: outputDirectory,
        withIntermediateDirectories: true
      )
    }
    let mark = try #require(canonicalFleckMarkImage())
    let panel = DictationCapsulePanel()
    let controller = DictationCapsuleController(panel: panel, markLoader: { mark })
    defer { controller.dismiss() }
    let initialScreen = try #require(panel.screen ?? NSScreen.main ?? NSScreen.screens.first)
    var observations: [[String: Any]] = []

    func rectRecord(_ rect: CGRect) -> [String: Double] {
      [
        "x": Double(rect.origin.x),
        "y": Double(rect.origin.y),
        "width": Double(rect.width),
        "height": Double(rect.height),
        "midX": Double(rect.midX),
        "midY": Double(rect.midY),
      ]
    }

    func record(
      _ scenario: String,
      phase: String,
      screen: NSScreen,
      context: DictationCapsuleContext,
      action: DictationCapsuleAction?,
      chooser: DictationCapsuleChooser?
    ) throws {
      let host = try #require(panel.contentView)
      let probes = visualDescendants(of: host).compactMap { view -> (String, CGRect)? in
        guard let identifier = view.identifier?.rawValue, identifier.hasPrefix("fleck-") else {
          return nil
        }
        let frame = view.convert(view.bounds, to: host)
        guard frame.width > 0, frame.height > 0 else { return nil }
        return (identifier, frame)
      }
      let probeUnion = probes.map { $0.1 }.reduce(nil as CGRect?) { partial, frame in
        partial?.union(frame) ?? frame
      }
      let probeUnionInScreen = probeUnion.map {
        panel.convertToScreen(host.convert($0, to: nil))
      }
      let displayedContext = controller.currentContext
      let displayedAction = controller.presentationModel.action
      let pillHasChooser = visualDescendants(of: host).contains {
        $0.identifier?.rawValue == "fleck-rail-chooser"
      }
      let expectedCenteredFrame = DictationCapsuleController.frame(
        for: .bottom,
        size: panel.frame.size,
        in: screen.visibleFrame
      )
      let presentation = DictationCapsulePresentation(
        status: displayedContext.status,
        action: displayedAction,
        context: displayedContext
      )
      let usesLivePillHost = controller.currentDock == .bottom
        && controller.fleckPillModel.usesFixedHost
      let usesErrorSurface = controller.errorPresentationModel.presentation != nil
      let declaredSize: CGSize
      if usesErrorSurface {
        declaredSize = DictationCapsuleController.errorSurfaceSize
      } else if usesLivePillHost {
        declaredSize = DictationCapsuleController.livePillHostSize
      } else {
        declaredSize = DictationCapsuleController.size(
          for: displayedContext.status,
          measuredWidth: presentation.measuredWidth,
          widthCeiling: presentation.widthCeiling
        )
      }
      let declaredCenteredFrame = DictationCapsuleController.frame(
        for: .bottom,
        size: declaredSize,
        in: screen.visibleFrame
      )
      observations.append([
        "scenario": scenario,
        "phase": phase,
        "requestedStatus": String(describing: context.status),
        "displayedStatus": String(describing: displayedContext.status),
        "hasAction": displayedAction != nil,
        "usesErrorSurface": usesErrorSurface,
        "hasChooser": pillHasChooser,
        "hasRouteContext": chooser != nil,
        "screenFrame": rectRecord(screen.frame),
        "screenVisibleFrame": rectRecord(screen.visibleFrame),
        "panelFrame": rectRecord(panel.frame),
        "panelMidXDelta": Double(panel.frame.midX - screen.visibleFrame.midX),
        "panelOriginXDeltaFromExpected": Double(
          panel.frame.origin.x - expectedCenteredFrame.origin.x
        ),
        "panelMinSize": [
          "width": Double(panel.minSize.width),
          "height": Double(panel.minSize.height),
        ],
        "hostBounds": rectRecord(host.bounds),
        "hostBoundsInScreen": rectRecord(
          panel.convertToScreen(host.convert(host.bounds, to: nil))
        ),
        "probeUnionContainedInHost": probeUnion.map { host.bounds.contains($0) } ?? false,
        "probeUnion": probeUnion.map { rectRecord($0) as Any } ?? NSNull(),
        "probeUnionInScreen": probeUnionInScreen.map { rectRecord($0) as Any } ?? NSNull(),
        "declaredSize": [
          "width": Double(declaredSize.width),
          "height": Double(declaredSize.height),
        ],
        "declaredCenteredFrame": rectRecord(declaredCenteredFrame),
        "expectedCenteredFrame": rectRecord(expectedCenteredFrame),
        "probes": probes.map {
          ["identifier": $0.0, "frame": rectRecord($0.1)] as [String: Any]
        },
      ])
    }

    func capture(_ scenario: String) throws {
      guard let outputDirectory, let host = panel.contentView else { return }
      let imageRep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: imageRep)
      let data = try #require(imageRep.representation(using: .png, properties: [:]))
      try data.write(to: outputDirectory.appendingPathComponent("\(scenario)-settled.png"))
    }

    func settleAndRecord(
      _ scenario: String,
      screen: NSScreen,
      context: DictationCapsuleContext,
      action: DictationCapsuleAction? = nil,
      chooser: DictationCapsuleChooser? = nil
    ) async throws {
      try record(
        scenario,
        phase: "before-layout",
        screen: screen,
        context: context,
        action: action,
        chooser: chooser
      )
      panel.contentView?.layoutSubtreeIfNeeded()
      try record(
        scenario,
        phase: "after-layout",
        screen: screen,
        context: context,
        action: action,
        chooser: chooser
      )
      try await Task.sleep(for: .milliseconds(250))
      for _ in 0..<5 { await Task.yield() }
      panel.contentView?.layoutSubtreeIfNeeded()
      try record(
        scenario,
        phase: "settled",
        screen: screen,
        context: context,
        action: action,
        chooser: chooser
      )
      try capture(scenario)
      let host = try #require(panel.contentView)
      let probeFrames = visualDescendants(of: host).compactMap { view -> CGRect? in
        guard view.identifier?.rawValue.hasPrefix("fleck-") == true else { return nil }
        let frame = view.convert(view.bounds, to: host)
        return frame.width > 0 && frame.height > 0 ? frame : nil
      }
      let probeUnion = try #require(probeFrames.reduce(nil as CGRect?) { partial, frame in
        partial?.union(frame) ?? frame
      })
      let displayedContext = controller.currentContext
      let displayedAction = controller.presentationModel.action
      let presentation = DictationCapsulePresentation(
        status: displayedContext.status,
        action: displayedAction,
        context: displayedContext
      )
      let usesLivePillHost = controller.currentDock == .bottom
        && controller.fleckPillModel.usesFixedHost
      let usesErrorSurface = controller.errorPresentationModel.presentation != nil
      let declaredSize: CGSize
      if usesErrorSurface {
        declaredSize = DictationCapsuleController.errorSurfaceSize
      } else if usesLivePillHost {
        declaredSize = DictationCapsuleController.livePillHostSize
      } else {
        declaredSize = DictationCapsuleController.size(
          for: displayedContext.status,
          measuredWidth: presentation.measuredWidth,
          widthCeiling: presentation.widthCeiling
        )
      }
      let frameTolerance: CGFloat = usesErrorSurface ? 1 : 0.5
      #expect(abs(panel.frame.midX - screen.visibleFrame.midX) <= 0.5)
      #expect(abs(panel.frame.width - declaredSize.width) <= frameTolerance)
      #expect(abs(panel.frame.height - declaredSize.height) <= frameTolerance)
      #expect(abs(host.bounds.width - declaredSize.width) <= frameTolerance)
      #expect(abs(host.bounds.height - declaredSize.height) <= frameTolerance)
      #expect(host.bounds.contains(probeUnion))
      for frame in probeFrames {
        #expect(host.bounds.contains(frame))
      }
      if case .saved = context.status {
        #expect(displayedContext.status == context.presentationContext(with: chooser).status)
        #expect(visualProbe("fleck-terminal-text", in: host) == nil)
        #expect(displayedContext.status == .idle)
        #expect(visualProbe("fleck-compact-saved-text", in: host) == nil)
      }
      if chooser != nil {
        #expect(controller.currentChooser == nil)
        #expect(visualProbe("fleck-rail-chooser", in: host) == nil)
      }
      if usesErrorSurface {
        #expect(visualProbe("fleck-error-surface", in: host) != nil)
      }
      if displayedContext.status == .idle, action != nil || chooser != nil {
        #expect(presentation.visibleText == nil)
        #expect(controller.errorPresentationModel.presentation == nil)
        #expect(controller.presentationModel.action == nil)
        #expect(controller.panel.frame.size == DictationCapsuleController.livePillHostSize)
        #expect(visualProbe("fleck-rail-recovery", in: host) == nil)
      }
    }

    controller.presentIdle(dock: .bottom, onOpenFleck: {}, onDockChanged: { _ in })
    let selectedScreen = panel.screen ?? initialScreen
    try await settleAndRecord(
      "idle",
      screen: selectedScreen,
      context: DictationCapsuleContext(status: .idle)
    )

    let sessionID = UUID()
    let compactContexts = [
      ("arming", DictationCapsuleContext(status: .arming, sessionID: sessionID)),
      ("listening", DictationCapsuleContext(
        status: .listening,
        sessionID: sessionID,
        trigger: .hold,
        mode: .smartCapture,
        pipelineStage: .capture
      )),
      ("finalizing", DictationCapsuleContext(
        status: .finalizing,
        sessionID: sessionID,
        trigger: .hold,
        mode: .smartCapture,
        pipelineStage: .capture
      )),
      ("cleaning", DictationCapsuleContext(
        status: .cleaning,
        sessionID: sessionID,
        trigger: .hold,
        mode: .smartCapture,
        pipelineStage: .polish
      )),
    ]
    for (name, context) in compactContexts {
      controller.render(context)
      try await settleAndRecord(name, screen: selectedScreen, context: context)
    }

    let captureID = UUID()
    let shortSaved = DictationCapsuleContext(
      status: .saved(destination: "Inbox"),
      sessionID: captureID
    )
    controller.render(shortSaved)
    try await settleAndRecord("saved-inbox", screen: selectedScreen, context: shortSaved)

    let longSaved = DictationCapsuleContext(
      status: .saved(destination: String(repeating: "Quarterly planning ", count: 8)),
      detailText: "Captured in Inbox",
      compactDetailText: "Inbox"
    )
    controller.render(longSaved)
    try await settleAndRecord("saved-long-title", screen: selectedScreen, context: longSaved)

    controller.render(shortSaved, action: .undo)
    try await settleAndRecord(
      "saved-undo",
      screen: selectedScreen,
      context: shortSaved,
      action: .undo
    )

    let noteID = UUID()
    let chooser = DictationCapsuleChooser(
      ambiguity: .init(
        captureID: captureID,
        choices: [
          .init(
            destination: .init(noteID: noteID, title: "Projects"),
            contextHint: "Synthetic roadmap"
          )
        ]
      )
    )
    controller.render(shortSaved, chooser: chooser)
    try await settleAndRecord(
      "saved-chooser",
      screen: selectedScreen,
      context: shortSaved,
      chooser: chooser
    )

    controller.render(shortSaved, action: .undo, chooser: chooser)
    try await settleAndRecord(
      "saved-undo-chooser",
      screen: selectedScreen,
      context: shortSaved,
      action: .undo,
      chooser: chooser
    )

    let keepInboxChooser = DictationCapsuleChooser(
      ambiguity: .init(captureID: captureID, choices: []),
      allowsKeepInInbox: true
    )
    controller.render(shortSaved, chooser: keepInboxChooser)
    try await settleAndRecord(
      "saved-keep-inbox",
      screen: selectedScreen,
      context: shortSaved,
      chooser: keepInboxChooser
    )

    let persistenceFailure = DictationCapsuleContext(
      status: .failed("Unable to save dictated text."),
      failureStage: .save,
      failureProvenance: .persistence,
      failureKind: .save
    )
    let terminalScenarios: [(String, DictationCapsuleContext, DictationCapsuleAction?)] = [
      ("hosted-synthetic-no-speech", DictationCapsuleContext(status: .noSpeech), nil),
      (
        "hosted-synthetic-used-original",
        DictationCapsuleContext(
          status: .savedWithoutCleanup(destination: "Inbox"),
          cleanupOutcome: .usedRaw,
          cleanupFallbackProvenance: .serviceFallback
        ),
        nil
      ),
      ("hosted-synthetic-repairing", DictationCapsuleContext(status: .repairingModel), nil),
      (
        "hosted-synthetic-microphone",
        DictationCapsuleContext(
          status: .failed("Microphone permission denied."),
          failureStage: .capture,
          failureKind: .microphoneAccess
        ),
        nil
      ),
      (
        "hosted-synthetic-dictation",
        DictationCapsuleContext(
          status: .failed("No usable transcription is available."),
          failureStage: .capture
        ),
        nil
      ),
      (
        "hosted-synthetic-insertion",
        DictationCapsuleContext(
          status: .failed("Unable to insert dictated text."),
          sessionID: UUID(),
          failureStage: .save,
          failureProvenance: .insertion,
          failureKind: .save
        ),
        .copy
      ),
      (
        "hosted-synthetic-routing-attention",
        DictationCapsuleContext(
          status: .routingFailure(status: "Needs attention", message: "The destination did not save.")
        ),
        .openDestination
      ),
      (
        "hosted-synthetic-speech-recognition-access",
        DictationCapsuleContext(
          status: .failed("Speech recognition access is unavailable."),
          failureStage: .capture,
          failureKind: .speechRecognitionAccess
        ),
        nil
      ),
      ("hosted-synthetic-persistence-copy", persistenceFailure, .copy),
      ("hosted-synthetic-persistence-history", persistenceFailure, .openHistory),
      (
        "hosted-synthetic-model-repair-failure",
        DictationCapsuleContext(
          status: .failed("The model could not be repaired."),
          failureStage: .polish,
          failureKind: .modelRepair
        ),
        .openHistory
      ),
    ]
    for (scenario, context, action) in terminalScenarios {
      controller.render(context, action: action)
      try await settleAndRecord(
        scenario,
        screen: selectedScreen,
        context: context,
        action: action
      )
    }

    if let outputDirectory {
      let data = try JSONSerialization.data(
        withJSONObject: observations,
        options: [.prettyPrinted, .sortedKeys]
      )
      try data.write(to: outputDirectory.appendingPathComponent("panel-position-observations.json"))
    }
  }

  @Test @MainActor func DictationCapsuleVisualCaptureWritesRailStateMatrixWhenRequested() async throws {
    let captureDirectory = ProcessInfo.processInfo.environment["FLECK_RAIL_CAPTURE_DIR"]
      .map { URL(fileURLWithPath: $0, isDirectory: true) }
    let sourceRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let markDirectory = sourceRoot.appendingPathComponent("Assets", isDirectory: true)
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
    panel.appearance = NSAppearance(named: .darkAqua)
    let controller = DictationCapsuleController(panel: panel, markLoader: markLoader)
    defer { controller.dismiss() }

    func render(
      _ name: String,
      context: DictationCapsuleContext,
      size: CGSize? = nil,
      action: DictationCapsuleAction? = nil,
      chooser: DictationCapsuleChooser? = nil,
      seedSyntheticWaveform: Bool = false
    ) async throws {
      controller.panel.orderOut(nil)
      controller.render(context, action: action, chooser: chooser)
      if seedSyntheticWaveform {
        prepareSyntheticWaveformFixture(for: controller)
      }
      controller.panel.contentView?.appearance = NSAppearance(named: .darkAqua)
      let displayedContext = controller.currentContext
      let displayedAction = controller.presentationModel.action
      let presentation = DictationCapsulePresentation(
        status: displayedContext.status,
        action: displayedAction,
        context: displayedContext
      )
      let captureSize: CGSize
      if let size {
        captureSize = size
      } else if controller.errorPresentationModel.presentation != nil {
        captureSize = DictationCapsuleController.errorSurfaceSize
      } else if controller.currentDock == .bottom
        && controller.fleckPillModel.usesFixedHost
      {
        captureSize = DictationCapsuleController.livePillHostSize
      } else {
        captureSize = DictationCapsuleController.size(
          for: displayedContext.status,
          measuredWidth: presentation.measuredWidth,
          widthCeiling: presentation.widthCeiling
        )
      }
      try await captureVisualState(
        "synthetic-offscreen-\(name)",
        controller: controller,
        size: captureSize,
        directory: captureDirectory
      )
      if displayedContext.status == .idle, action != nil || chooser != nil {
        #expect(presentation.visibleText == nil)
        #expect(controller.errorPresentationModel.presentation == nil)
        let host = try #require(controller.panel.contentView)
        #expect(controller.presentationModel.action == nil)
        #expect(controller.currentChooser == nil)
        #expect(visualProbe("fleck-rail-recovery", in: host) == nil)
        #expect(visualProbe("fleck-rail-chooser", in: host) == nil)
        #expect(controller.panel.frame.size == DictationCapsuleController.livePillHostSize)
      }
    }

    try await render(
      "idle-bottom",
      context: DictationCapsuleContext(status: .idle)
    )

    func renderStarting(_ dock: DictationCapsuleDock) async throws {
      let startingPanel = DictationCapsulePanel()
      startingPanel.appearance = NSAppearance(named: .darkAqua)
      let startingController = DictationCapsuleController(
        panel: startingPanel,
        markLoader: markLoader
      )
      defer { startingController.dismiss() }
      startingController.presentIdle(dock: dock, onOpenFleck: {}, onDockChanged: { _ in })
      startingController.render(.arming)
      startingController.panel.contentView?.appearance = NSAppearance(named: .darkAqua)
      try await captureVisualState(
        "arming-\(dock.rawValue)",
        controller: startingController,
        size: DictationCapsuleController.size(for: .arming),
        directory: captureDirectory
      )
    }

    for dock in DictationCapsuleDock.allCases {
      try await renderStarting(dock)
    }

    func renderCaptureFeedbackMatrix(
      appearance: NSAppearance.Name,
      appearanceName: String
    ) async throws {
      for dock in DictationCapsuleDock.allCases {
        let feedbackPanel = DictationCapsulePanel()
        feedbackPanel.appearance = NSAppearance(named: appearance)
        let feedbackController = DictationCapsuleController(
          panel: feedbackPanel,
          markLoader: markLoader
        )
        defer { feedbackController.dismiss() }
        feedbackController.presentIdle(
          dock: dock,
          onOpenFleck: {},
          onDockChanged: { _ in }
        )
        feedbackController.render(.arming)
        feedbackController.panel.contentView?.appearance = NSAppearance(named: appearance)
        try await captureVisualState(
          "capture-feedback-starting-\(appearanceName)-\(dock.rawValue)",
          controller: feedbackController,
          size: DictationCapsuleController.size(for: .arming),
          directory: captureDirectory
        )

        feedbackController.render(visualCaptureContext(
          .listening,
          stage: .capture
        ))
        feedbackController.panel.contentView?.appearance = NSAppearance(named: appearance)
        try await captureVisualState(
          "capture-feedback-listening-quiet-\(appearanceName)-\(dock.rawValue)",
          controller: feedbackController,
          size: DictationCapsuleController.listeningSize,
          directory: captureDirectory
        )
        prepareSyntheticWaveformFixture(for: feedbackController)
        try await captureVisualState(
          "capture-feedback-listening-synthetic-live-\(appearanceName)-\(dock.rawValue)",
          controller: feedbackController,
          size: DictationCapsuleController.listeningSize,
          directory: captureDirectory
        )

        let smartCapture = visualCaptureContext(
          .listening,
          detailText: "Smart Capture",
          compactDetailText: "Smart Capture",
          isHandsFree: true,
          stage: .capture
        )
        feedbackController.panel.orderOut(nil)
        feedbackController.render(smartCapture)
        feedbackController.waveformModel.reset()
        feedbackController.waveformModel.beginListening(monotonicNow: ProcessInfo.processInfo.systemUptime)
        feedbackController.panel.contentView?.appearance = NSAppearance(named: appearance)
        try await captureVisualState(
          "single-row-smart-capture-listening-quiet-\(appearanceName)-\(dock.rawValue)",
          controller: feedbackController,
          size: DictationCapsuleController.size(for: smartCapture.status),
          directory: captureDirectory
        )
        prepareSyntheticWaveformFixture(for: feedbackController)
        try await captureVisualState(
          "single-row-smart-capture-listening-live-\(appearanceName)-\(dock.rawValue)",
          controller: feedbackController,
          size: DictationCapsuleController.size(for: smartCapture.status),
          directory: captureDirectory
        )
        feedbackController.presentationModel.setListeningHover(true)
        for _ in 0..<5 { await Task.yield() }
        feedbackController.panel.contentView?.layoutSubtreeIfNeeded()
        try await captureVisualState(
          "single-row-smart-capture-listening-hover-\(appearanceName)-\(dock.rawValue)",
          controller: feedbackController,
          size: DictationCapsuleController.size(for: smartCapture.status),
          directory: captureDirectory
        )
        feedbackController.presentationModel.setListeningHover(false)
        feedbackController.panel.orderOut(nil)
        let longTitleContext = DictationCapsuleContext(
          status: .listening,
          detailText: "Dictating into Quarterly planning and launch readiness notes",
          compactDetailText: "Quarterly planning and launch readiness notes",
          sessionID: UUID(),
          trigger: .hold,
          mode: .focused,
          pipelineStage: .capture
        )
        feedbackController.render(longTitleContext)
        feedbackController.waveformModel.reset()
        feedbackController.waveformModel.beginListening(monotonicNow: ProcessInfo.processInfo.systemUptime)
        feedbackController.panel.contentView?.appearance = NSAppearance(named: appearance)
        try await captureVisualState(
          "focused-long-title-header-free-\(appearanceName)-\(dock.rawValue)",
          controller: feedbackController,
          size: DictationCapsuleController.size(for: longTitleContext.status),
          directory: captureDirectory
        )
      }
    }

    try await renderCaptureFeedbackMatrix(appearance: .aqua, appearanceName: "light")
    try await renderCaptureFeedbackMatrix(appearance: .darkAqua, appearanceName: "dark")

    let heldListening = visualCaptureContext(
      .listening,
      isHandsFree: false,
      stage: .capture
    )
    try await render(
      "listening-right-option-held-bottom",
      context: heldListening,
      size: DictationCapsuleController.listeningSize
    )
    prepareSyntheticWaveformFixture(for: controller)
    try await captureVisualState(
      "listening-right-option-held-bottom-seeded",
      controller: controller,
      size: DictationCapsuleController.listeningSize,
      directory: captureDirectory
    )

    let focusedListening = DictationCapsuleContext(
      status: .listening,
      detailText: "Dictating into Travel plans",
      compactDetailText: "Travel plans",
      sessionID: visualCaptureSessionID,
      trigger: .hold,
      mode: .focused,
      pipelineStage: .capture
    )
    for dock in [DictationCapsuleDock.bottom, .left, .right] {
      controller.setDock(dock)
      try await render(
        "listening-focused-destination-\(dock.rawValue)",
        context: focusedListening,
        seedSyntheticWaveform: true
      )
    }
    controller.setDock(.bottom)

    let handsFreeListening = visualCaptureContext(
      .listening,
      isHandsFree: true,
      stage: .capture
    )
    controller.waveformModel.reset()
    controller.waveformModel.beginListening(monotonicNow: ProcessInfo.processInfo.systemUptime)
    try await render(
      "listening-hands-free-bottom",
      context: handsFreeListening,
      size: DictationCapsuleController.listeningSize
    )
    prepareSyntheticWaveformFixture(for: controller)
    try await captureVisualState(
      "listening-hands-free-bottom-seeded",
      controller: controller,
      size: DictationCapsuleController.listeningSize,
      directory: captureDirectory
    )
    controller.presentationModel.setListeningHover(true)
    try await captureVisualState(
      "listening-hands-free-hover-stop-cancel-bottom",
      controller: controller,
      size: DictationCapsuleController.listeningSize,
      directory: captureDirectory
    )

    let polishing = visualCaptureContext(
      .cleaning,
      detailText: "Smart Capture",
      compactDetailText: "Smart Capture",
      stage: .polish
    )
    try await render(
      "polishing-after-label-delay-bottom",
      context: polishing
    )
    try await Task.sleep(for: .milliseconds(500))
    for _ in 0..<5 { await Task.yield() }
    controller.presentationModel.setListeningHover(false)
    try await captureVisualState(
      "polishing-after-label-delay-bottom-visible",
      controller: controller,
      size: DictationCapsuleController.size(for: polishing.status),
      directory: captureDirectory
    )
    let smartPolishing = DictationCapsuleContext(
      status: .cleaning,
      detailText: "Smart Capture",
      sessionID: visualCaptureSessionID,
      trigger: .hold,
      mode: .smartCapture,
      pipelineStage: .polish
    )
    try await render(
      "polishing-smart-capture-bottom",
      context: smartPolishing
    )
    try await render(
      "finalizing-bottom",
      context: visualCaptureContext(.finalizing, stage: .capture)
    )
    try await render(
      "routing-bottom",
      context: visualCaptureContext(.routing, stage: .organize)
    )
    try await render(
      "saving-bottom",
      context: visualCaptureContext(.saving, stage: .save)
    )

    try await render(
      "saved-undo-bottom",
      context: visualCaptureContext(.saved(destination: "Inbox")),
      action: .undo
    )
    try await render(
      "saved-original-bottom",
      context: visualCaptureContext(
        .savedWithoutCleanup(destination: "Inbox"),
        stage: .save,
        cleanup: .usedRaw
      )
    )
    try await render(
      "saved-service-fallback-bottom",
      context: visualCaptureContext(
        .savedWithoutCleanup(destination: "Inbox"),
        stage: .save,
        cleanup: .usedRaw,
        cleanupFallbackProvenance: .serviceFallback
      )
    )
    try await render(
      "saved-raw-without-service-fallback-bottom",
      context: visualCaptureContext(
        .saved(destination: "Inbox"),
        stage: .save,
        cleanup: .usedRaw
      )
    )
    try await render(
      "save-failure-recovery-bottom",
      context: visualCaptureContext(
        .failed("save failed"),
        stage: .save,
        failureStage: .save,
        failureKind: .save
      ),
      action: .openDestination
    )
    try await render(
      "routing-failure-recovery-bottom",
      context: visualCaptureContext(
        .routingFailure(status: "Destination unavailable", message: "Could not route dictation."),
        stage: .organize,
        failureStage: .organize,
        failureKind: .generic
      ),
      action: .openDestination
    )
    try await render(
      "model-repairing-bottom",
      context: visualCaptureContext(.repairingModel, stage: .capture)
    )
    try await render(
      "no-speech-bottom",
      context: visualCaptureContext(.noSpeech)
    )
    try await render(
      "dictation-failure-bottom",
      context: visualCaptureContext(
        .failed("Recognition failed"),
        stage: .capture,
        failureStage: .capture,
        failureKind: .speechRecognitionAccess
      )
    )
    try await render(
      "quiet-saved-undo-bottom",
      context: visualCaptureContext(
        .idle,
        stage: .save
      ),
      action: .undo
    )
    let quietCaptureID = UUID()
    let quietChooser = DictationCapsuleChooser(
      ambiguity: .init(
        captureID: quietCaptureID,
        choices: [
          .init(
            destination: .init(noteID: UUID(), title: "Projects"),
            contextHint: "Synthetic roadmap"
          )
        ]
      )
    )
    try await render(
      "quiet-saved-undo-and-routing-choice-bottom",
      context: visualCaptureContext(
        .idle,
        stage: .save
      ),
      action: .undo,
      chooser: quietChooser
    )
  }

  @Test @MainActor func waveformPolishNativeTraceCaptureWhenRequested() async throws {
    guard let path = ProcessInfo.processInfo.environment["FLECK_WAVEFORM_CAPTURE_DIR"] else { return }
    let directory = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let panel = DictationCapsulePanel()
    panel.appearance = NSAppearance(named: .darkAqua)
    let controller = DictationCapsuleController(panel: panel)
    defer { controller.dismiss() }
    controller.render(visualCaptureContext(.listening, isHandsFree: true, stage: .capture))
    controller.panel.orderOut(nil)
    // Synthetic RMS only. No microphone session or notes are created by this fixture.
    var levels = [Float](repeating: 0, count: 10)
    levels += [0.006, 0.02, 0.08, 0.20, 0.08, 0.03]
    levels += [Float](repeating: 0, count: 12)
    for _ in 0..<4 { levels += [0.02, 0.06, 0.04, 0.10] }
    levels += [Float](repeating: 0, count: 16)
    for (index, level) in levels.enumerated() {
      controller.waveformModel.receive(level: level, monotonicNow: ProcessInfo.processInfo.systemUptime)
      try await Task.sleep(for: .milliseconds(80))
      try await captureVisualState(
        String(format: "frame-%03d", index), controller: controller,
        size: DictationCapsuleController.listeningSize, directory: directory
      )
    }
    for dock in [DictationCapsuleDock.left, .right] {
      controller.setDock(dock)
      controller.waveformModel.receive(level: 0.20, monotonicNow: ProcessInfo.processInfo.systemUptime)
      controller.presentationModel.setListeningHover(true)
      try await Task.sleep(for: .milliseconds(80))
      try await captureVisualState("listening-\(dock.rawValue)-controls", controller: controller,
        size: DictationCapsuleController.listeningSize, directory: directory)
    }
    controller.render(visualCaptureContext(.cleaning, stage: .polish))
    #expect(controller.waveformModel.energy == 0)
    try await captureVisualState("processing", controller: controller,
      size: DictationCapsuleController.activeSize, directory: directory)
    controller.dismiss()
    #expect(controller.waveformModel.energy == 0)
  }

#if DEBUG
  private enum DictationCapsuleNativeQASupport {
    struct Marker: Encodable {
      let phase: String
      let sessionNonce: UUID
      let monotonicUptime: TimeInterval
      let reduceMotion: Bool
    }

    static var outputDirectory: URL? {
      checkedOutputDirectory(environment: ProcessInfo.processInfo.environment)
    }

    static var enabled: Bool {
      outputDirectory != nil
    }

    static func isEnabled(
      environment: [String: String],
      homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
      return checkedOutputDirectory(environment: environment, homeDirectory: homeDirectory) != nil
    }

    private static func checkedOutputDirectory(
      environment: [String: String],
      homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL? {
      guard environment["FLECK_CAPSULE_NATIVE_QA"] == "1",
        let path = environment["FLECK_PILL_CAPTURE_DIRECTORY"],
        path.hasPrefix("/"),
        !path.split(separator: "/").contains("..")
      else { return nil }
      let scratchRoot = resolvedPath(homeDirectory.appendingPathComponent(
        ".capy/work/fleck-fluidity-loop",
        isDirectory: true
      ))
      let basePath = resolvedPath(URL(fileURLWithPath: path, isDirectory: true))
      guard isWithinScratch(basePath, root: scratchRoot) else { return nil }
      let outputPath = resolvedPath(
        URL(fileURLWithPath: basePath, isDirectory: true)
          .appendingPathComponent("native-root-qa", isDirectory: true)
      )
      guard isWithinScratch(outputPath, root: scratchRoot) else { return nil }
      return URL(fileURLWithPath: outputPath, isDirectory: true)
    }

    private static func isWithinScratch(_ path: String, root: String) -> Bool {
      path == root || path.hasPrefix(root + "/")
    }

    private static func resolvedPath(_ url: URL) -> String {
      var ancestor = url.standardizedFileURL
      var missingComponents: [String] = []
      let fileManager = FileManager.default
      while ancestor.path != "/",
        !fileManager.fileExists(atPath: ancestor.path),
        (try? fileManager.destinationOfSymbolicLink(atPath: ancestor.path)) == nil
      {
        missingComponents.append(ancestor.lastPathComponent)
        ancestor.deleteLastPathComponent()
      }
      var resolved = ancestor.resolvingSymlinksInPath().standardizedFileURL
      for component in missingComponents.reversed() {
        resolved.appendPathComponent(component, isDirectory: true)
      }
      return resolved.standardizedFileURL.path
    }

    static func write(_ markers: [Marker], to url: URL) throws {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      var data = Data()
      for marker in markers {
        data.append(try encoder.encode(marker))
        data.append(0x0A)
      }
      try data.write(to: url, options: .atomic)
    }
  }

  @Test
  func DictationCapsuleNativeQAGateRequiresExactOptInAndScratchOutput() {
    let home = URL(fileURLWithPath: "/tmp/fleck-native-qa-home", isDirectory: true)
    let outputPath = home.appendingPathComponent(
      ".capy/work/fleck-fluidity-loop/run",
      isDirectory: true
    ).path
    let output = ["FLECK_PILL_CAPTURE_DIRECTORY": outputPath]
    #expect(!DictationCapsuleNativeQASupport.isEnabled(environment: [:], homeDirectory: home))
    #expect(!DictationCapsuleNativeQASupport.isEnabled(environment: output, homeDirectory: home))
    #expect(!DictationCapsuleNativeQASupport.isEnabled(
      environment: output.merging(["FLECK_CAPSULE_NATIVE_QA": "true"]) { _, new in new },
      homeDirectory: home
    ))
    #expect(!DictationCapsuleNativeQASupport.isEnabled(
      environment: [
        "FLECK_CAPSULE_NATIVE_QA": "1",
        "FLECK_PILL_CAPTURE_DIRECTORY": "/tmp/outside",
      ],
      homeDirectory: home
    ))
    #expect(DictationCapsuleNativeQASupport.isEnabled(
      environment: output.merging(["FLECK_CAPSULE_NATIVE_QA": "1"]) { _, new in new },
      homeDirectory: home
    ))
  }

  @Test
  func DictationCapsuleNativeQAGateRejectsResolvedEscapes() throws {
    let home = FileManager.default.temporaryDirectory
      .appendingPathComponent("FleckNativeQAGate-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: home) }

    let scratchRoot = home.appendingPathComponent(
      ".capy/work/fleck-fluidity-loop",
      isDirectory: true
    )
    let outsideDirectory = home.appendingPathComponent("outside", isDirectory: true)
    try FileManager.default.createDirectory(at: scratchRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      at: scratchRoot.appendingPathComponent("escape", isDirectory: true),
      withDestinationURL: outsideDirectory
    )

    func gateAllows(_ path: String) -> Bool {
      DictationCapsuleNativeQASupport.isEnabled(
        environment: [
          "FLECK_CAPSULE_NATIVE_QA": "1",
          "FLECK_PILL_CAPTURE_DIRECTORY": path,
        ],
        homeDirectory: home
      )
    }

    #expect(gateAllows(scratchRoot.appendingPathComponent("new/child", isDirectory: true).path))
    #expect(!gateAllows(scratchRoot.appendingPathComponent("escape/new-child", isDirectory: true).path))
    #expect(!gateAllows(scratchRoot.path + "/../fleck-fluidity-loop-sibling/child"))
    #expect(!gateAllows(scratchRoot.path + "-sibling/child"))
  }

  @Test
  func DictationCapsuleNativeQAGateRejectsEscapingDerivedOutputDirectory() throws {
    let home = FileManager.default.temporaryDirectory
      .appendingPathComponent("FleckNativeQADerivedGate-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: home) }

    let scratchRoot = home.appendingPathComponent(
      ".capy/work/fleck-fluidity-loop",
      isDirectory: true
    )
    let baseDirectory = scratchRoot.appendingPathComponent("run", isDirectory: true)
    let missingChildBase = scratchRoot.appendingPathComponent("run-without-child", isDirectory: true)
    let outsideDirectory = home.appendingPathComponent("outside", isDirectory: true)
    try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: missingChildBase, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      at: baseDirectory.appendingPathComponent("native-root-qa", isDirectory: true),
      withDestinationURL: outsideDirectory
    )

    func environment(for base: URL) -> [String: String] {
      [
        "FLECK_CAPSULE_NATIVE_QA": "1",
        "FLECK_PILL_CAPTURE_DIRECTORY": base.path,
      ]
    }

    #expect(!DictationCapsuleNativeQASupport.isEnabled(
      environment: environment(for: baseDirectory),
      homeDirectory: home
    ))
    #expect(DictationCapsuleNativeQASupport.isEnabled(
      environment: environment(for: missingChildBase),
      homeDirectory: home
    ))
  }

  @Test
  func DictationCapsuleNativeQADriverUsesFencedMonotonicWaveformPath() throws {
    let source = try String(contentsOfFile: #filePath, encoding: .utf8)
    let driverStart = try #require(source.range(of:
      "\n  func DictationCapsuleNativeQAProductionRootSequence() async throws {"
    ))
    let driverSource = source[driverStart.lowerBound...]
    let driverEnd = try #require(driverSource.range(of: "\n  }\n#endif"))
    let driver = driverSource[..<driverEnd.lowerBound]

    #expect(driver.contains(
      "controller.updateAudioLevel(level)\n        #expect(controller.waveformModel.energy > 0)"
    ))
    #expect(driver.contains(
      "controller.updateAudioLevel(0.58)\n      #expect(controller.waveformModel.energy > 0)"
    ))
    #expect(driver.contains(
      "controller.updateAudioLevel(0.4)\n      #expect(controller.waveformModel.energy > 0)"
    ))
    #expect(!driver.contains("controller.waveformModel.receive(level:"))

    let checkedDirectory = try #require(driver.range(of:
      "let directory = try #require(DictationCapsuleNativeQASupport.outputDirectory)"
    ))
    let createDirectory = try #require(driver.range(of:
      "FileManager.default.createDirectory(at: directory"
    ))
    let panel = try #require(driver.range(of: "let panel = DictationCapsulePanel()"))
    #expect(checkedDirectory.lowerBound < createDirectory.lowerBound)
    #expect(createDirectory.lowerBound < panel.lowerBound)
    #expect(!driver.contains(".appendingPathComponent(\"native-root-qa\""))
    #expect(driver.contains("let markerURL = directory.appendingPathComponent"))
    #expect(driver.contains("write(markers, to: markerURL)"))
  }

  @Test @MainActor
  func DictationWaveformAcceptsSamplesOnItsMonotonicClock() {
    let model = DictationWaveformModel()
    let start: TimeInterval = 100
    model.beginListening(monotonicNow: start)
    model.receive(level: 0.72, monotonicNow: start + 0.04, reduceMotion: false)

    #expect(model.energy > 0)
    #expect(model.displayedEnergy(monotonicNow: start + 0.04) > 0)
  }

  @Test
  func DictationCapsuleReduceMotionOverridePreservesEnvironmentByDefault() {
    #expect(!DictationCapsuleReduceMotionOverride.resolve(override: nil, fallback: false))
    #expect(DictationCapsuleReduceMotionOverride.resolve(override: nil, fallback: true))
    #expect(!DictationCapsuleReduceMotionOverride.resolve(override: false, fallback: true))
    #expect(DictationCapsuleReduceMotionOverride.resolve(override: true, fallback: false))
  }

  @Test(.enabled(
    if: DictationCapsuleNativeQASupport.enabled,
    "Requires FLECK_CAPSULE_NATIVE_QA=1 and a scratch FLECK_PILL_CAPTURE_DIRECTORY"
  ))
  @MainActor
  func DictationCapsuleNativeQAProductionRootSequence() async throws {
    let directory = try #require(DictationCapsuleNativeQASupport.outputDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let markerURL = directory.appendingPathComponent("run-\(UUID().uuidString).jsonl")
    var markers: [DictationCapsuleNativeQASupport.Marker] = []

    func sessionID(_ index: Int) -> UUID {
      UUID(uuidString: "00000000-0000-4000-8000-00000000000\(index)")!
    }

    func mark(_ phase: String, sessionID: UUID, reduceMotion: Bool) {
      markers.append(.init(
        phase: phase,
        sessionNonce: sessionID,
        monotonicUptime: ProcessInfo.processInfo.systemUptime,
        reduceMotion: reduceMotion
      ))
    }

    func hold(
      _ phase: String,
      sessionID: UUID,
      reduceMotion: Bool,
      milliseconds: Int
    ) async throws {
      mark("\(phase).begin", sessionID: sessionID, reduceMotion: reduceMotion)
      try await Task.sleep(for: .milliseconds(milliseconds))
      mark("\(phase).end", sessionID: sessionID, reduceMotion: reduceMotion)
    }

    for reduceMotion in [false, true] {
      let panel = DictationCapsulePanel()
      panel.hasShadow = false
      panel.ignoresMouseEvents = true
      panel.isOpaque = false
      panel.backgroundColor = .clear
      let controller = DictationCapsuleController(
        panel: panel,
        monotonicNow: { ProcessInfo.processInfo.systemUptime },
        automaticallyAdvancesLivePill: true,
        reduceMotionProvider: { reduceMotion },
        markLoader: { nil },
        announcementPoster: { _, _ in }
      )
      defer { controller.dismiss() }
      controller.setReduceMotionOverrideForTesting(reduceMotion)
      controller.configureInteraction(
        onPrimaryClick: {},
        onStop: {},
        onCancel: {},
        onOpenFleck: {},
        onOpenHistory: {},
        onOpenSettings: {},
        onDismiss: {},
        onRecovery: {},
        onErrorRecovery: { _ in }
      )
      controller.presentIdle(
        dock: .bottom,
        accessibilityLabel: "Synthetic QA",
        onOpenFleck: {},
        onDockChanged: { _ in }
      )

      func render(
        _ status: DictationCapsuleStatus,
        phase: DictationPhase,
        sessionID: UUID,
        stage: DictationPipelineStage,
        destination: DictationDestination? = nil,
        cleanupOutcome: DictationCleanupOutcome? = nil,
        terminal: DictationTerminalOutcome? = nil,
        failureStage: DictationPipelineStage? = nil,
        failureKind: DictationCapsuleFailureKind? = nil
      ) {
        let context = DictationCapsuleContext(
          status: status,
          sessionID: sessionID,
          mode: .smartCapture,
          pipelineStage: stage,
          cleanupOutcome: cleanupOutcome,
          failureStage: failureStage,
          failureKind: failureKind
        )
        let coordinatorContext = DictationCoordinatorContext(
          sessionID: sessionID,
          mode: .smartCapture,
          destination: destination,
          pipelineStage: stage,
          cleanupOutcome: cleanupOutcome,
          failureStage: failureStage
        )
        controller.render(
          context,
          coordinatorEvent: DictationCoordinatorEvent(
            phase: phase,
            terminal: terminal,
            context: coordinatorContext
          )
        )
      }

      let idleSession = sessionID(0)
      mark("standby.start", sessionID: idleSession, reduceMotion: reduceMotion)
      try await hold("standby", sessionID: idleSession, reduceMotion: reduceMotion, milliseconds: 900)

      let captureSession = sessionID(1)
      render(.arming, phase: .arming, sessionID: captureSession, stage: .capture)
      #expect(controller.fleckPillModel.state == (reduceMotion ? .arming : .opening))
      try await hold("arming", sessionID: captureSession, reduceMotion: reduceMotion, milliseconds: 360)
      render(
        .listening,
        phase: .listening(mode: .smartCapture, engine: .standard),
        sessionID: captureSession,
        stage: .capture
      )
      mark("listening.start", sessionID: captureSession, reduceMotion: reduceMotion)
      #expect(controller.fleckPillModel.state == .listening)
      for (index, level) in [Float(0.16), 0.72, 0.28].enumerated() {
        controller.updateAudioLevel(level)
        #expect(controller.waveformModel.energy > 0)
        try await hold(
          "listening.level-\(index)",
          sessionID: captureSession,
          reduceMotion: reduceMotion,
          milliseconds: 360
        )
      }
      render(.finalizing, phase: .finalizing, sessionID: captureSession, stage: .capture)
      #expect(controller.fleckPillModel.state == .processing)
      try await hold("finalizing", sessionID: captureSession, reduceMotion: reduceMotion, milliseconds: 360)
      render(.cleaning, phase: .cleaning, sessionID: captureSession, stage: .polish)
      try await hold("cleaning", sessionID: captureSession, reduceMotion: reduceMotion, milliseconds: 240)
      render(.routing, phase: .routing, sessionID: captureSession, stage: .organize)
      try await hold("routing", sessionID: captureSession, reduceMotion: reduceMotion, milliseconds: 240)

      let destination = DictationDestination(noteID: captureSession, title: "Synthetic")
      render(
        .saved(destination: "Synthetic"),
        phase: .saved(destination),
        sessionID: captureSession,
        stage: .save,
        destination: destination,
        cleanupOutcome: .cleaned,
        terminal: .saved(mode: .smartCapture, cleanup: .cleaned, destination: destination)
      )
      try await hold("completion", sessionID: captureSession, reduceMotion: reduceMotion, milliseconds: 360)
      controller.render(DictationCapsuleContext(status: .idle))
      try await hold("completion-return", sessionID: captureSession, reduceMotion: reduceMotion, milliseconds: 360)

      let interruptedArmingSession = sessionID(2)
      render(.arming, phase: .arming, sessionID: interruptedArmingSession, stage: .capture)
      try await hold("arming-interruption", sessionID: interruptedArmingSession, reduceMotion: reduceMotion, milliseconds: 80)
      controller.render(DictationCapsuleContext(status: .idle))
      try await hold("arming-return", sessionID: interruptedArmingSession, reduceMotion: reduceMotion, milliseconds: 360)

      let interruptedListeningSession = sessionID(3)
      render(.arming, phase: .arming, sessionID: interruptedListeningSession, stage: .capture)
      render(
        .listening,
        phase: .listening(mode: .smartCapture, engine: .standard),
        sessionID: interruptedListeningSession,
        stage: .capture
      )
      mark("listening-interruption.start", sessionID: interruptedListeningSession, reduceMotion: reduceMotion)
      controller.updateAudioLevel(0.58)
      #expect(controller.waveformModel.energy > 0)
      try await hold("listening-interruption", sessionID: interruptedListeningSession, reduceMotion: reduceMotion, milliseconds: 240)
      controller.render(DictationCapsuleContext(status: .idle))
      try await hold("listening-close", sessionID: interruptedListeningSession, reduceMotion: reduceMotion, milliseconds: 360)

      let replacedSession = sessionID(4)
      render(.arming, phase: .arming, sessionID: replacedSession, stage: .capture)
      try await hold("session-replacement-start", sessionID: replacedSession, reduceMotion: reduceMotion, milliseconds: 80)
      let replacementSession = sessionID(5)
      render(.arming, phase: .arming, sessionID: replacementSession, stage: .capture)
      mark("session-replacement-arming", sessionID: replacementSession, reduceMotion: reduceMotion)
      render(
        .listening,
        phase: .listening(mode: .smartCapture, engine: .standard),
        sessionID: replacementSession,
        stage: .capture
      )
      try await hold("session-replacement-listening", sessionID: replacementSession, reduceMotion: reduceMotion, milliseconds: 360)
      controller.render(DictationCapsuleContext(status: .idle))
      try await hold("session-replacement-close", sessionID: replacementSession, reduceMotion: reduceMotion, milliseconds: 360)

      let failureSession = sessionID(6)
      render(.arming, phase: .arming, sessionID: failureSession, stage: .capture)
      try await hold("failure-arming", sessionID: failureSession, reduceMotion: reduceMotion, milliseconds: 80)
      render(
        .listening,
        phase: .listening(mode: .smartCapture, engine: .standard),
        sessionID: failureSession,
        stage: .capture
      )
      try await hold("failure-listening", sessionID: failureSession, reduceMotion: reduceMotion, milliseconds: 80)
      let failureMessage = "Synthetic capture failure"
      render(
        .failed(failureMessage),
        phase: .failed(failureMessage),
        sessionID: failureSession,
        stage: .capture,
        terminal: .failed(failureMessage),
        failureStage: .capture,
        failureKind: .generic
      )
      try await hold("error-entry", sessionID: failureSession, reduceMotion: reduceMotion, milliseconds: 400)
      #expect(controller.errorPresentationModel.presentation?.kind == .dictation)
      #expect(controller.errorPresentationModel.presentation?.actionTitle == "Try again")
      let retryToken = try #require(controller.errorPresentationModel.beginAction())
      #expect(controller.errorPresentationModel.presentation(forActionToken: retryToken) != nil)
      mark("retry-action", sessionID: failureSession, reduceMotion: reduceMotion)

      let retrySession = sessionID(7)
      render(.arming, phase: .arming, sessionID: retrySession, stage: .capture)
      try await hold("retry-arming", sessionID: retrySession, reduceMotion: reduceMotion, milliseconds: 360)
      render(
        .listening,
        phase: .listening(mode: .smartCapture, engine: .standard),
        sessionID: retrySession,
        stage: .capture
      )
      mark("retry-listening.start", sessionID: retrySession, reduceMotion: reduceMotion)
      controller.updateAudioLevel(0.4)
      #expect(controller.waveformModel.energy > 0)
      try await hold("retry-listening", sessionID: retrySession, reduceMotion: reduceMotion, milliseconds: 360)
      controller.render(DictationCapsuleContext(status: .idle))
      try await hold("retry-return", sessionID: retrySession, reduceMotion: reduceMotion, milliseconds: 360)

      let savedSession = sessionID(8)
      controller.render(DictationCapsuleContext(
        status: .savedWithoutCleanup(destination: "Synthetic"),
        sessionID: savedSession,
        mode: .smartCapture,
        pipelineStage: .polish,
        cleanupOutcome: .usedRaw,
        cleanupFallbackProvenance: .serviceFallback
      ))
      #expect(controller.currentContext.status == .idle)
      #expect(controller.errorPresentationModel.presentation == nil)
      #expect(controller.presentationModel.action == nil)
      #expect(controller.currentChooser == nil)
      #expect(!controller.panel.allowsActions)
      #expect(controller.fleckPillModel.state == .standby)
      try await hold("raw-save-standby", sessionID: savedSession, reduceMotion: reduceMotion, milliseconds: 600)

      controller.render(DictationCapsuleContext(status: .idle))
      let wakeSession = sessionID(9)
      try await hold("idle-before-wake", sessionID: wakeSession, reduceMotion: reduceMotion, milliseconds: 2_000)
      render(.arming, phase: .arming, sessionID: wakeSession, stage: .capture)
      mark("idle-wake", sessionID: wakeSession, reduceMotion: reduceMotion)
      try await hold("wake-arming", sessionID: wakeSession, reduceMotion: reduceMotion, milliseconds: 360)
    }

    try DictationCapsuleNativeQASupport.write(markers, to: markerURL)
  }
#endif


  @MainActor
  private func visualCoordinatorEvent(
    for context: DictationCapsuleContext
  ) -> DictationCoordinatorEvent? {
    guard let sessionID = context.sessionID else { return nil }
    let mode = context.mode ?? .smartCapture
    let phase: DictationPhase
    let fallbackStage: DictationPipelineStage
    switch context.status {
    case .arming:
      phase = .arming
      fallbackStage = .capture
    case .listening:
      phase = .listening(mode: mode, engine: .standard)
      fallbackStage = .capture
    case .finalizing:
      phase = .finalizing
      fallbackStage = .capture
    case .cleaning:
      phase = .cleaning
      fallbackStage = .polish
    case .routing:
      phase = .routing
      fallbackStage = .organize
    case .saving:
      phase = .routing
      fallbackStage = .save
    default:
      return nil
    }
    return DictationCoordinatorEvent(
      phase: phase,
      terminal: nil,
      context: DictationCoordinatorContext(
        sessionID: sessionID,
        mode: mode,
        pipelineStage: context.pipelineStage ?? fallbackStage,
        cleanupOutcome: context.cleanupOutcome,
        failureStage: context.failureStage
      )
    )
  }

  @MainActor
  private func hasBrightPixel(
    in frame: CGRect,
    imageRep: NSBitmapImageRep,
    hostedBy host: NSView,
    threshold: CGFloat = 0.35
  ) -> Bool {
    let scaleX = CGFloat(imageRep.pixelsWide) / host.bounds.width
    let scaleY = CGFloat(imageRep.pixelsHigh) / host.bounds.height
    let minimumX = max(0, Int(floor(frame.minX * scaleX)))
    let maximumX = min(imageRep.pixelsWide, Int(ceil(frame.maxX * scaleX)))
    let minimumY = max(0, Int(floor(frame.minY * scaleY)))
    let maximumY = min(imageRep.pixelsHigh, Int(ceil(frame.maxY * scaleY)))
    for y in minimumY..<maximumY {
      for x in minimumX..<maximumX {
        guard let color = imageRep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
          continue
        }
        if max(color.redComponent, color.greenComponent, color.blueComponent) > threshold {
          return true
        }
      }
    }
    return false
  }

  @Test @MainActor
  func DictationCapsuleLiveArtworkRequiresMatchingNonterminalCoordinatorEvents() async throws {
    let panel = DictationCapsulePanel()
    let controller = DictationCapsuleController(panel: panel)
    defer { controller.dismiss() }
    controller.presentIdle(dock: .bottom, onOpenFleck: {}, onDockChanged: { _ in })

    let sessionID = UUID()
    let listening = DictationCapsuleContext(
      status: .listening,
      sessionID: sessionID,
      mode: .smartCapture,
      pipelineStage: .capture
    )
    let matchingEvent = try #require(visualCoordinatorEvent(for: listening))
    controller.render(listening, coordinatorEvent: matchingEvent)
    #expect(controller.fleckPillModel.state == .listening)
    #expect(controller.fleckPillModel.sessionID == sessionID)
    try await captureVisualState(
      "matching-session-live-pill",
      controller: controller,
      size: DictationCapsuleController.livePillHostSize,
      directory: nil
    )

    let otherSessionID = UUID()
    let mismatchedEvent = DictationCoordinatorEvent(
      phase: .listening(mode: .smartCapture, engine: .standard),
      terminal: nil,
      context: DictationCoordinatorContext(
        sessionID: otherSessionID,
        mode: .smartCapture,
        pipelineStage: .capture,
        cleanupOutcome: nil,
        failureStage: nil
      )
    )
    controller.render(listening, coordinatorEvent: mismatchedEvent)
    #expect(controller.currentContext.status == .listening)
    #expect(controller.fleckPillModel.state == .hidden)
    #expect(!controller.fleckPillModel.usesFixedHost)

    controller.render(listening, coordinatorEvent: matchingEvent)
    #expect(controller.currentContext.status == .listening)
    #expect(controller.fleckPillModel.state == .hidden)

    let message = "Unable to save dictation."
    let failed = DictationCapsuleContext(
      status: .failed(message),
      sessionID: sessionID,
      mode: .smartCapture,
      pipelineStage: .save,
      failureStage: .save,
      failureKind: .save
    )
    let terminalEvent = DictationCoordinatorEvent(
      phase: .failed(message),
      terminal: .failed(message),
      context: DictationCoordinatorContext(
        sessionID: sessionID,
        mode: .smartCapture,
        pipelineStage: .save,
        cleanupOutcome: nil,
        failureStage: .save
      )
    )
    controller.render(failed, coordinatorEvent: terminalEvent)
    #expect(controller.currentContext.status == .failed(message))
    #expect(controller.fleckPillModel.state == .hidden)
    #expect(!controller.fleckPillModel.usesFixedHost)
  }
#endif
