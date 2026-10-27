#if os(macOS)
  import AppKit
  import Foundation
  import FleckCore
  import Testing

  @testable import FleckApp

  private let visualCaptureSessionID = UUID(uuidString: "56B8F4D6-19F4-4EA0-8AC4-2AB87A9F0D61")!

  @MainActor
  private func visualCaptureContext(
    _ status: DictationCapsuleStatus,
    detailText: String? = nil,
    compactDetailText: String? = nil,
    isHandsFree: Bool = false,
    stage: DictationPipelineStage? = nil,
    cleanup: DictationCleanupOutcome? = nil,
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
      failureStage: failureStage,
      failureKind: failureKind
    )
  }

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
  private func captureVisualState(
    _ name: String,
    controller: DictationCapsuleController,
    size: CGSize? = nil,
    directory: URL?
  ) throws {
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
    let expectedFrame = controller.fleckPillModel.usesFixedHost
      ? DictationCapsuleController.livePillFrame(in: screen.visibleFrame)
      : DictationCapsuleController.frame(
        for: controller.currentDock,
        size: DictationCapsuleController.size(
          for: renderedContext.status,
          measuredWidth: presentation.measuredWidth,
          widthCeiling: presentation.widthCeiling
        ),
        in: screen.visibleFrame
      )
    let panelFrame = controller.panel.frame
    #expect(abs(panelFrame.minX - expectedFrame.minX) <= 0.5)
    #expect(abs(panelFrame.minY - expectedFrame.minY) <= 0.5)
    #expect(abs(panelFrame.width - expectedFrame.width) <= 0.5)
    #expect(abs(panelFrame.height - expectedFrame.height) <= 0.5)
    if let size { #expect(panelFrame.size == size) }
    #expect(host.bounds.size == panelFrame.size)
    host.layoutSubtreeIfNeeded()

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
    let start = Date()
    controller.waveformModel.reset()
    controller.waveformModel.beginListening(at: start)
    controller.waveformModel.receive(level: 0.20, now: start.addingTimeInterval(0.04))
    controller.waveformModel.receive(level: 0.14, now: start.addingTimeInterval(0.08))
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

  @Test @MainActor
  func DictationCapsuleActiveModesStaySingleRowWithoutCoveringLiveControls() throws {
    let panel = DictationCapsulePanel()
    let controller = DictationCapsuleController(panel: panel)
    defer { controller.dismiss() }

    func host(for context: DictationCapsuleContext) throws -> NSView {
      controller.render(context)
      #expect(!controller.fleckPillModel.usesFixedHost)
      let host = try #require(panel.contentView)
      host.layoutSubtreeIfNeeded()
      return host
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
      let focusedTimer = try visualFrame("fleck-rail-timer", in: focusedHost)
      #expect(abs(focusedWaveform.midX - focusedHost.bounds.midX) <= 0.5)
      #expect(focusedHost.bounds.contains(focusedWaveform))
      #expect(focusedHost.bounds.contains(focusedTimer))
      #expect(!focusedWaveform.intersects(focusedTimer))

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
      let smartTimer = try visualFrame("fleck-rail-timer", in: smartHost)
      #expect(abs(smartWaveform.midX - smartHost.bounds.midX) <= 0.5)
      #expect(smartHost.bounds.contains(smartWaveform))
      #expect(smartHost.bounds.contains(smartTimer))
      #expect(!smartWaveform.intersects(smartTimer))
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
      timer: CGRect,
      stop: CGRect,
      cancel: CGRect
    ) {
      let host = try #require(panel.contentView)
      host.layoutSubtreeIfNeeded()
      return (
        host.bounds,
        try visualFrame("fleck-rail-mark", in: host),
        try visualFrame("fleck-rail-waveform", in: host),
        try visualFrame("fleck-rail-timer", in: host),
        try visualFrame("fleck-rail-stop", in: host),
        try visualFrame("fleck-rail-cancel", in: host)
      )
    }

    func expectSamePlacement(
      _ first: (
        bounds: CGRect,
        mark: CGRect,
        waveform: CGRect,
        timer: CGRect,
        stop: CGRect,
        cancel: CGRect
      ),
      _ second: (
        bounds: CGRect,
        mark: CGRect,
        waveform: CGRect,
        timer: CGRect,
        stop: CGRect,
        cancel: CGRect
      )
    ) {
      for (lhs, rhs) in [
        (first.bounds, second.bounds),
        (first.mark, second.mark),
        (first.timer, second.timer),
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
      #expect(!controller.fleckPillModel.usesFixedHost)
      #expect(abs(panel.frame.width - DictationCapsuleController.listeningSize.width) <= 0.5)
      #expect(abs(panel.frame.height - 36) <= 0.5)
      #expect(
        controller.presentationModel.voiceOverLabel
          == "Dictation listening. Dictating into Quarterly planning and launch readiness notes"
      )

      controller.waveformModel.reset()
      controller.waveformModel.beginListening()
      let quiet = try listeningFrames()
      #expect(visualProbe("fleck-rail-context", in: try #require(panel.contentView)) == nil)
      #expect(abs(quiet.waveform.midX - quiet.bounds.midX) <= 0.5)
      #expect(abs(quiet.mark.midY - quiet.waveform.midY) <= 0.5)
      #expect(abs(quiet.timer.midY - quiet.waveform.midY) <= 0.5)
      for frame in [quiet.mark, quiet.waveform, quiet.timer] {
        #expect(quiet.bounds.contains(frame))
      }
      #expect(!quiet.mark.intersects(quiet.waveform))
      #expect(!quiet.waveform.intersects(quiet.timer))
      #expect(quiet.stop.size == CGSize(width: 28, height: 28))
      #expect(quiet.cancel.size == CGSize(width: 28, height: 28))
      #expect(quiet.timer.contains(quiet.stop))
      #expect(quiet.timer.contains(quiet.cancel))
      #expect(!quiet.stop.intersects(quiet.cancel))

      let shellFrame = panel.frame
      controller.presentationModel.setListeningHover(true)
      let hovered = try listeningFrames()
      expectSamePlacement(quiet, hovered)
      #expect(panel.frame == shellFrame)

      controller.presentationModel.setListeningHover(false)
      let now = Date()
      controller.waveformModel.receive(level: 0.20, now: now.addingTimeInterval(0.04))
      let loud = try listeningFrames()
      expectSamePlacement(quiet, loud)

      controller.waveformModel.reset()
      controller.waveformModel.beginListening()
      let rested = try listeningFrames()
      expectSamePlacement(quiet, rested)
    }

    let contextTextPairs: [(String?, String?)] = [
      ("Dictating into Inbox", nil),
      (nil, "Inbox"),
    ]
    for (detailText, compactDetailText) in contextTextPairs {
      panel.orderOut(nil)
      let context = DictationCapsuleContext(
        status: .listening,
        detailText: detailText,
        compactDetailText: compactDetailText,
        sessionID: UUID(),
        trigger: .hold,
        mode: .smartCapture,
        pipelineStage: .capture
      )
      controller.render(context, coordinatorEvent: visualCoordinatorEvent(for: context))
      #expect(DictationCapsuleController.size(for: controller.currentContext.status).height == 36)
      #expect(panel.frame.size == DictationCapsuleController.livePillHostSize)
      #expect(visualProbe("fleck-rail-context", in: try #require(panel.contentView)) == nil)
    }

    panel.orderOut(nil)
    let listeningWithoutDetail = DictationCapsuleContext(
      status: .listening,
      sessionID: UUID(),
      trigger: .hold,
      mode: .smartCapture,
      pipelineStage: .capture
    )
    controller.render(
      listeningWithoutDetail,
      coordinatorEvent: visualCoordinatorEvent(for: listeningWithoutDetail)
    )
    #expect(panel.frame.size == DictationCapsuleController.livePillHostSize)

    let progress: [(DictationCapsuleStatus, DictationPipelineStage)] = [
      (.finalizing, .capture),
      (.cleaning, .polish),
      (.routing, .organize),
      (.saving, .save),
    ]
    for (status, stage) in progress {
      panel.orderOut(nil)
      let context = DictationCapsuleContext(
        status: status,
        detailText: "Smart Capture",
        compactDetailText: "Smart Capture",
        sessionID: listeningWithoutDetail.sessionID,
        trigger: .hold,
        mode: .smartCapture,
        pipelineStage: stage
      )
      controller.render(context, coordinatorEvent: visualCoordinatorEvent(for: context))
      #expect(panel.frame.size == DictationCapsuleController.livePillHostSize)
      let host = try #require(panel.contentView)
      host.layoutSubtreeIfNeeded()
      #expect(visualProbe("fleck-rail-context", in: host) == nil)
      #expect(visualProbe("fleck-rail-mark", in: host) == nil)
      #expect(controller.fleckPillModel.state == .processing)
    }

    panel.orderOut(nil)
    let cleaning = DictationCapsuleContext(
      status: .cleaning,
      sessionID: UUID(),
      trigger: .hold,
      mode: .smartCapture,
      pipelineStage: .polish
    )
    controller.render(cleaning, coordinatorEvent: visualCoordinatorEvent(for: cleaning))
    #expect(panel.frame.size == DictationCapsuleController.livePillHostSize)
  }

  @Test func DictationCapsuleSingleRowFramesClampInsideSmallOffsetVisibleFrames() {
    let chooser = DictationCapsuleChooser(
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
    let savedStatuses: [DictationCapsuleStatus] = [
      .saved(destination: String(repeating: "Quarterly planning ", count: 8)),
      .savedWithoutCleanup(destination: String(repeating: "Quarterly planning ", count: 8)),
    ]
    let savedPresentations = savedStatuses.map {
      DictationCapsulePresentation(status: $0, action: .undo, chooser: chooser)
    }
    #expect(savedPresentations.allSatisfy { $0.visibleText == nil })
    #expect(savedPresentations.allSatisfy { $0.voiceOverText == "Fleck dictation ready" })
    #expect(savedPresentations.allSatisfy { $0.measuredWidth <= DictationCapsuleController.idleSize.width })
    #expect(savedStatuses.allSatisfy { DictationCapsuleController.size(for: $0) == DictationCapsuleController.idleSize })
    #expect(DictationCapsuleDock.allCases == [.bottom])

    let failure = DictationCapsulePresentation(
      status: .failed("Destination unavailable"),
      action: .openDestination
    )
    let visibleFrames = [
      CGRect(x: -1_280, y: 37, width: 120, height: 44),
      CGRect(x: 640, y: 280, width: 320, height: 90),
    ]

    for visibleFrame in visibleFrames {
      let standbyFrame = DictationCapsuleController.livePillFrame(in: visibleFrame)
      #expect(visibleFrame.contains(standbyFrame))
      #expect(standbyFrame.width == min(180, visibleFrame.width))
      #expect(standbyFrame.height == min(39, visibleFrame.height))
      #expect(standbyFrame.midX == visibleFrame.midX)
      #expect(standbyFrame.minY == visibleFrame.minY)

      let failureFrame = DictationCapsuleController.frame(
        for: .bottom,
        status: .failed("Destination unavailable"),
        measuredWidth: failure.measuredWidth,
        in: visibleFrame
      )
      #expect(visibleFrame.contains(failureFrame))
      #expect(failureFrame.width == min(failure.measuredWidth, visibleFrame.width))
      #expect(failureFrame.height == min(DictationCapsuleController.failureSize.height, visibleFrame.height))
      #expect(failureFrame.minY == visibleFrame.minY + min(10, max((visibleFrame.height - failureFrame.height) / 2, 0)))
    }
  }

  @Test @MainActor
  func DictationCapsuleLiveArtworkRequiresMatchingNonterminalCoordinatorEvents() throws {
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
    try captureVisualState(
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
        let sessionID = UUID()
        for status in statuses {
          panel.orderOut(nil)
          controller.setDock(dock)
          let context = DictationCapsuleContext(
            status: status,
            detailText: "Synthetic captured destination",
            compactDetailText: "Synthetic context",
            sessionID: sessionID,
            trigger: .doubleTap,
            mode: mode,
            isHandsFree: true
          )
          controller.render(context, coordinatorEvent: visualCoordinatorEvent(for: context))
          let host = try #require(panel.contentView)
          host.layoutSubtreeIfNeeded()
          #expect(visualProbe("fleck-rail-context", in: host) == nil)
          #expect(panel.frame.size == DictationCapsuleController.livePillHostSize)
          #expect(panel.frame.height == DictationCapsuleController.livePillHostSize.height)
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
      controller.render(listening, coordinatorEvent: visualCoordinatorEvent(for: listening))
      controller.presentationModel.setListeningHover(true)
      let host = try #require(panel.contentView)
      host.layoutSubtreeIfNeeded()
      let signal = FleckPillMotion.signalGeometry(controller.fleckPillModel.frame)
      let signalMinX = try #require(signal.points.map(\.x).min())
      let signalMaxX = try #require(signal.points.map(\.x).max())
      let signalCenterX = (Double(host.bounds.width) - FleckPillGeometry.canvasSize.width) / 2
        + FleckPillGeometry.artworkScale * (8 + (signalMinX + signalMaxX) / 2)
      let stop = try visualFrame("fleck-rail-stop", in: host)
      let cancel = try visualFrame("fleck-rail-cancel", in: host)
      #expect(panel.frame.size == DictationCapsuleController.livePillHostSize)
      #expect(visualProbe("fleck-rail-context", in: host) == nil)
      #expect(abs(signalCenterX - Double(host.bounds.midX)) <= 0.5)
      #expect(visualProbe("fleck-rail-waveform", in: host) == nil)
      #expect(stop.size == CGSize(width: 28, height: 28))
      #expect(cancel.size == CGSize(width: 28, height: 28))
      #expect(host.bounds.contains(stop))
      #expect(host.bounds.contains(cancel))
      #expect(!stop.intersects(cancel))
      #expect(controller.presentationModel.voiceOverLabel == "Dictation listening. \(detail)")
      try captureVisualState(
        "focused-listening-live-artwork",
        controller: controller,
        size: DictationCapsuleController.livePillHostSize,
        directory: nil
      )

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
      controller.render(processing, coordinatorEvent: visualCoordinatorEvent(for: processing))
      host.layoutSubtreeIfNeeded()
      #expect(panel.frame.size == DictationCapsuleController.livePillHostSize)
      #expect(visualProbe("fleck-rail-context", in: host) == nil)
      #expect(visualProbe("fleck-rail-mark", in: host) == nil)
      #expect(controller.fleckPillModel.state == .processing)
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
      let renderedContext = controller.currentContext
      let renderedAction = controller.presentationModel.action
      let renderedChooser = controller.currentChooser
      let usesFixedHost = controller.fleckPillModel.usesFixedHost
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
      let expectedCenteredFrame = usesFixedHost
        ? DictationCapsuleController.livePillFrame(in: screen.visibleFrame)
        : DictationCapsuleController.frame(
          for: .bottom,
          size: panel.frame.size,
          in: screen.visibleFrame
        )
      let presentation = DictationCapsulePresentation(
        status: renderedContext.status,
        action: renderedAction,
        chooser: renderedChooser,
        context: renderedContext
      )
      let declaredCenteredFrame: CGRect
      if usesFixedHost {
        declaredCenteredFrame = DictationCapsuleController.livePillFrame(in: screen.visibleFrame)
      } else {
        let declaredSize = DictationCapsuleController.size(
          for: renderedContext.status,
          measuredWidth: presentation.measuredWidth,
          widthCeiling: presentation.widthCeiling
        )
        declaredCenteredFrame = DictationCapsuleController.frame(
          for: .bottom,
          size: declaredSize,
          in: screen.visibleFrame
        )
      }
      let declaredSize = declaredCenteredFrame.size
      observations.append([
        "scenario": scenario,
        "phase": phase,
        "inputStatus": String(describing: context.status),
        "requestedHasAction": action != nil,
        "requestedHasChooser": chooser != nil,
        "renderedStatus": String(describing: renderedContext.status),
        "usesFixedHost": usesFixedHost,
        "hasAction": renderedAction != nil,
        "hasChooser": renderedChooser != nil,
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
        "hasProbeUnion": probeUnion != nil,
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
      let host = try #require(panel.contentView)
      let imageRep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: imageRep)
      #expect(imageRep.pixelsWide > 0)
      #expect(imageRep.pixelsHigh > 0)
      if let sessionID = controller.fleckPillModel.sessionID {
        let snapshot = try #require(controller.fleckPillModel.renderReceipt.snapshot(for: sessionID))
        #expect(snapshot.sessionID == sessionID)
        #expect(snapshot.generation == controller.fleckPillModel.renderGeneration)
      } else if controller.fleckPillModel.state == .standby {
        #expect(hasBrightPixel(in: host.bounds, imageRep: imageRep, hostedBy: host))
      }
      guard let outputDirectory else { return }
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
      let renderedContext = controller.currentContext
      let renderedAction = controller.presentationModel.action
      let renderedChooser = controller.currentChooser
      let usesFixedHost = controller.fleckPillModel.usesFixedHost
      let probeFrames = visualDescendants(of: host).compactMap { view -> CGRect? in
        guard view.identifier?.rawValue.hasPrefix("fleck-") == true else { return nil }
        let frame = view.convert(view.bounds, to: host)
        return frame.width > 0 && frame.height > 0 ? frame : nil
      }
      let probeUnion = probeFrames.reduce(nil as CGRect?) { partial, frame in
        partial?.union(frame) ?? frame
      }
      let presentation = DictationCapsulePresentation(
        status: renderedContext.status,
        action: renderedAction,
        chooser: renderedChooser,
        context: renderedContext
      )
      let expectedFrame = usesFixedHost
        ? DictationCapsuleController.livePillFrame(in: screen.visibleFrame)
        : DictationCapsuleController.frame(
          for: .bottom,
          size: DictationCapsuleController.size(
            for: renderedContext.status,
            measuredWidth: presentation.measuredWidth,
            widthCeiling: presentation.widthCeiling
          ),
          in: screen.visibleFrame
        )
      let declaredSize = expectedFrame.size
      #expect(abs(panel.frame.midX - screen.visibleFrame.midX) <= 0.5)
      #expect(abs(panel.frame.width - declaredSize.width) <= 0.5)
      #expect(abs(panel.frame.height - declaredSize.height) <= 0.5)
      #expect(abs(host.bounds.width - declaredSize.width) <= 0.5)
      #expect(abs(host.bounds.height - declaredSize.height) <= 0.5)
      if let probeUnion {
        #expect(host.bounds.contains(probeUnion))
      } else if let sessionID = controller.fleckPillModel.sessionID {
        let snapshot = try #require(controller.fleckPillModel.renderReceipt.snapshot(for: sessionID))
        #expect(snapshot.sessionID == sessionID)
        #expect(snapshot.generation == controller.fleckPillModel.renderGeneration)
      } else {
        let imageRep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: imageRep)
        #expect(controller.fleckPillModel.state == .standby)
        #expect(hasBrightPixel(in: host.bounds, imageRep: imageRep, hostedBy: host))
      }
      for frame in probeFrames {
        #expect(host.bounds.contains(frame))
      }
      switch context.status {
      case .saved, .savedWithoutCleanup:
        #expect(renderedContext.status == .idle)
        #expect(renderedAction == nil)
        #expect(renderedChooser == nil)
        #expect(controller.fleckPillModel.usesFixedHost)
        #expect(presentation.visibleText == nil)
        #expect(presentation.voiceOverText == "Fleck dictation ready")
        #expect(!panel.allowsActions)
      default:
        break
      }
      if renderedChooser != nil {
        let chooserFrame = try visualFrame("fleck-rail-chooser", in: host)
        #expect(chooserFrame.width > 0)
        #expect(chooserFrame.height > 0)
        #expect(host.bounds.contains(chooserFrame))
      }
      #expect(abs(panel.frame.origin.y - expectedFrame.origin.y) <= 0.5)
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
      controller.render(context, coordinatorEvent: visualCoordinatorEvent(for: context))
      try await settleAndRecord(name, screen: selectedScreen, context: context)
    }

    let shortSaved = DictationCapsuleContext(status: .saved(destination: "Inbox"))
    controller.render(shortSaved)
    try await settleAndRecord("saved-inbox", screen: selectedScreen, context: shortSaved)

    let savedChooser = DictationCapsuleChooser(
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
    let longSaved = DictationCapsuleContext(
      status: .saved(destination: String(repeating: "Quarterly planning ", count: 8)),
      detailText: "Captured in Inbox",
      compactDetailText: "Inbox"
    )
    controller.render(longSaved, action: .undo, chooser: savedChooser)
    try await settleAndRecord(
      "saved-long-title-undo-chooser-cleared",
      screen: selectedScreen,
      context: longSaved,
      action: .undo,
      chooser: savedChooser
    )

    let rawSaved = DictationCapsuleContext(
      status: .savedWithoutCleanup(
        destination: String(repeating: "Quarterly planning ", count: 8)
      )
    )
    controller.render(rawSaved, action: .copy, chooser: savedChooser)
    try await settleAndRecord(
      "saved-original-copy-chooser-cleared",
      screen: selectedScreen,
      context: rawSaved,
      action: .copy,
      chooser: savedChooser
    )

    let routingContext = DictationCapsuleContext(
      status: .routing,
      sessionID: UUID(),
      trigger: .hold,
      mode: .smartCapture,
      pipelineStage: .organize
    )
    controller.render(
      routingContext,
      coordinatorEvent: visualCoordinatorEvent(for: routingContext)
    )
    try await settleAndRecord("routing", screen: selectedScreen, context: routingContext)

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
    ) throws {
      controller.panel.orderOut(nil)
      controller.render(
        context,
        action: action,
        chooser: chooser,
        coordinatorEvent: visualCoordinatorEvent(for: context)
      )
      if seedSyntheticWaveform {
        prepareSyntheticWaveformFixture(for: controller)
      }
      controller.panel.contentView?.appearance = NSAppearance(named: .darkAqua)
      try captureVisualState(
        name,
        controller: controller,
        size: size,
        directory: captureDirectory
      )
    }

    try render(
      "idle-bottom",
      context: DictationCapsuleContext(status: .idle),
      size: DictationCapsuleController.livePillHostSize
    )

    func renderStarting(_ dock: DictationCapsuleDock) throws {
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
      try captureVisualState(
        "arming-\(dock.rawValue)",
        controller: startingController,
        size: DictationCapsuleController.startingSize,
        directory: captureDirectory
      )
    }

    for dock in DictationCapsuleDock.allCases {
      try renderStarting(dock)
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
        let arming = visualCaptureContext(.arming, stage: .capture)
        feedbackController.render(
          arming,
          coordinatorEvent: visualCoordinatorEvent(for: arming)
        )
        feedbackController.panel.contentView?.appearance = NSAppearance(named: appearance)
        try captureVisualState(
          "capture-feedback-admitted-arming-\(appearanceName)-\(dock.rawValue)",
          controller: feedbackController,
          size: DictationCapsuleController.livePillHostSize,
          directory: captureDirectory
        )

        let listening = visualCaptureContext(
          .listening,
          stage: .capture
        )
        feedbackController.render(
          listening,
          coordinatorEvent: visualCoordinatorEvent(for: listening)
        )
        feedbackController.panel.contentView?.appearance = NSAppearance(named: appearance)
        try captureVisualState(
          "capture-feedback-listening-quiet-\(appearanceName)-\(dock.rawValue)",
          controller: feedbackController,
          size: DictationCapsuleController.livePillHostSize,
          directory: captureDirectory
        )
        prepareSyntheticWaveformFixture(for: feedbackController)
        try captureVisualState(
          "capture-feedback-listening-synthetic-live-\(appearanceName)-\(dock.rawValue)",
          controller: feedbackController,
          size: DictationCapsuleController.livePillHostSize,
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
        feedbackController.render(
          smartCapture,
          coordinatorEvent: visualCoordinatorEvent(for: smartCapture)
        )
        feedbackController.waveformModel.reset()
        feedbackController.waveformModel.beginListening()
        feedbackController.panel.contentView?.appearance = NSAppearance(named: appearance)
        try captureVisualState(
          "single-row-smart-capture-listening-quiet-\(appearanceName)-\(dock.rawValue)",
          controller: feedbackController,
          size: DictationCapsuleController.livePillHostSize,
          directory: captureDirectory
        )
        prepareSyntheticWaveformFixture(for: feedbackController)
        try captureVisualState(
          "single-row-smart-capture-listening-live-\(appearanceName)-\(dock.rawValue)",
          controller: feedbackController,
          size: DictationCapsuleController.livePillHostSize,
          directory: captureDirectory
        )
        feedbackController.presentationModel.setListeningHover(true)
        for _ in 0..<5 { await Task.yield() }
        feedbackController.panel.contentView?.layoutSubtreeIfNeeded()
        try captureVisualState(
          "single-row-smart-capture-listening-hover-\(appearanceName)-\(dock.rawValue)",
          controller: feedbackController,
          size: DictationCapsuleController.livePillHostSize,
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
        feedbackController.render(
          longTitleContext,
          coordinatorEvent: visualCoordinatorEvent(for: longTitleContext)
        )
        feedbackController.waveformModel.reset()
        feedbackController.waveformModel.beginListening()
        feedbackController.panel.contentView?.appearance = NSAppearance(named: appearance)
        try captureVisualState(
          "focused-long-title-header-free-\(appearanceName)-\(dock.rawValue)",
          controller: feedbackController,
          size: DictationCapsuleController.livePillHostSize,
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
    try render(
      "listening-right-option-held-bottom",
      context: heldListening,
      size: DictationCapsuleController.livePillHostSize
    )
    prepareSyntheticWaveformFixture(for: controller)
    try captureVisualState(
      "listening-right-option-held-bottom-seeded",
      controller: controller,
      size: DictationCapsuleController.livePillHostSize,
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
    for dock in DictationCapsuleDock.allCases {
      controller.setDock(dock)
      try render(
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
    controller.waveformModel.beginListening()
    try render(
      "listening-hands-free-bottom",
      context: handsFreeListening,
      size: DictationCapsuleController.livePillHostSize
    )
    prepareSyntheticWaveformFixture(for: controller)
    try captureVisualState(
      "listening-hands-free-bottom-seeded",
      controller: controller,
      size: DictationCapsuleController.livePillHostSize,
      directory: captureDirectory
    )
    controller.presentationModel.setListeningHover(true)
    try captureVisualState(
      "listening-hands-free-hover-stop-cancel-bottom",
      controller: controller,
      size: DictationCapsuleController.livePillHostSize,
      directory: captureDirectory
    )

    let polishing = visualCaptureContext(
      .cleaning,
      detailText: "Smart Capture",
      compactDetailText: "Smart Capture",
      stage: .polish
    )
    try render(
      "polishing-after-label-delay-bottom",
      context: polishing
    )
    try await Task.sleep(for: .milliseconds(500))
    for _ in 0..<5 { await Task.yield() }
    controller.presentationModel.setListeningHover(false)
    try captureVisualState(
      "polishing-after-label-delay-bottom-visible",
      controller: controller,
      size: DictationCapsuleController.livePillHostSize,
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
    try render(
      "polishing-smart-capture-bottom",
      context: smartPolishing
    )

    let savedChooser = DictationCapsuleChooser(
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
    try render(
      "saved-undo-chooser-cleared-bottom",
      context: visualCaptureContext(.saved(destination: "Inbox")),
      size: DictationCapsuleController.livePillHostSize,
      action: .undo,
      chooser: savedChooser
    )
    try render(
      "saved-original-copy-chooser-cleared-bottom",
      context: visualCaptureContext(.savedWithoutCleanup(destination: "Inbox")),
      size: DictationCapsuleController.livePillHostSize,
      action: .copy,
      chooser: savedChooser
    )
    try render(
      "save-failure-recovery-bottom",
      context: visualCaptureContext(
        .failed("save failed"),
        stage: .save,
        failureStage: .save,
        failureKind: .save
      ),
      action: .openDestination
    )
    try render(
      "no-speech-bottom",
      context: visualCaptureContext(.noSpeech)
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
    let listening = visualCaptureContext(.listening, isHandsFree: true, stage: .capture)
    controller.render(listening, coordinatorEvent: visualCoordinatorEvent(for: listening))
    controller.panel.orderOut(nil)
    // Synthetic RMS only. No microphone session or notes are created by this fixture.
    var levels = [Float](repeating: 0, count: 10)
    levels += [0.006, 0.02, 0.08, 0.20, 0.08, 0.03]
    levels += [Float](repeating: 0, count: 12)
    for _ in 0..<4 { levels += [0.02, 0.06, 0.04, 0.10] }
    levels += [Float](repeating: 0, count: 16)
    for (index, level) in levels.enumerated() {
      controller.waveformModel.receive(level: level)
      try await Task.sleep(for: .milliseconds(80))
      try captureVisualState(
        String(format: "frame-%03d", index), controller: controller,
        size: DictationCapsuleController.livePillHostSize, directory: directory
      )
    }
    controller.setDock(.bottom)
    controller.waveformModel.receive(level: 0.20)
    controller.presentationModel.setListeningHover(true)
    try await Task.sleep(for: .milliseconds(80))
    try captureVisualState("listening-bottom-controls", controller: controller,
      size: DictationCapsuleController.livePillHostSize, directory: directory)
    let processing = visualCaptureContext(.cleaning, stage: .polish)
    controller.render(processing, coordinatorEvent: visualCoordinatorEvent(for: processing))
    #expect(controller.waveformModel.energy == 0)
    try captureVisualState("processing", controller: controller,
      size: DictationCapsuleController.livePillHostSize, directory: directory)
    controller.dismiss()
    #expect(controller.waveformModel.energy == 0)
  }
#endif
