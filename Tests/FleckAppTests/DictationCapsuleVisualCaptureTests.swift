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
  private func captureVisualState(
    _ name: String,
    controller: DictationCapsuleController,
    size: CGSize,
    directory: URL?
  ) throws {
    guard let host = controller.panel.contentView else {
      Issue.record("Expected a hosted Fleck rail for \(name)")
      return
    }
    controller.panel.setFrame(CGRect(origin: .zero, size: size), display: false)
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    #expect(controller.panel.frame.size == size)
    #expect(host.bounds.size == size)

    let imageRep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: imageRep)
    #expect(imageRep.pixelsWide > 0)
    #expect(imageRep.pixelsHigh > 0)

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
    let panel = DictationCapsulePanel()
    let controller = DictationCapsuleController(panel: panel)
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
      host.frame = CGRect(origin: .zero, size: panel.frame.size)
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
    let terminalContext = DictationCapsuleContext(
      status: .saved(destination: String(repeating: "Quarterly planning ", count: 8)),
      detailText: "Captured in Inbox",
      compactDetailText: "Inbox"
    )
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
      status: terminalContext.status,
      action: .undo,
      chooser: terminalChooser,
      context: terminalContext
    )
    let sizes = activeSizes + [
      DictationCapsuleController.size(
        for: terminalContext.status,
        measuredWidth: terminalPresentation.measuredWidth,
        widthCeiling: terminalPresentation.widthCeiling
      )
    ]
    #expect(terminalPresentation.measuredWidth > DictationCapsuleController.activeSize.width)
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
    let panel = DictationCapsulePanel()
    let controller = DictationCapsuleController(panel: panel)
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
      let expectedCenteredFrame = DictationCapsuleController.frame(
        for: .bottom,
        size: panel.frame.size,
        in: screen.visibleFrame
      )
      let presentation = DictationCapsulePresentation(
        status: context.status,
        action: action,
        chooser: chooser,
        context: context
      )
      let declaredSize = DictationCapsuleController.size(
        for: context.status,
        measuredWidth: presentation.measuredWidth,
        widthCeiling: presentation.widthCeiling
      )
      let declaredCenteredFrame = DictationCapsuleController.frame(
        for: .bottom,
        size: declaredSize,
        in: screen.visibleFrame
      )
      observations.append([
        "scenario": scenario,
        "phase": phase,
        "hasAction": action != nil,
        "hasChooser": chooser != nil,
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
      let presentation = DictationCapsulePresentation(
        status: context.status,
        action: action,
        chooser: chooser,
        context: context
      )
      let declaredSize = DictationCapsuleController.size(
        for: context.status,
        measuredWidth: presentation.measuredWidth,
        widthCeiling: presentation.widthCeiling
      )
      #expect(abs(panel.frame.midX - screen.visibleFrame.midX) <= 0.5)
      #expect(abs(panel.frame.width - declaredSize.width) <= 0.5)
      #expect(abs(panel.frame.height - declaredSize.height) <= 0.5)
      #expect(abs(host.bounds.width - declaredSize.width) <= 0.5)
      #expect(abs(host.bounds.height - declaredSize.height) <= 0.5)
      #expect(host.bounds.contains(probeUnion))
      for frame in probeFrames {
        #expect(host.bounds.contains(frame))
      }
      if case .saved = context.status {
        let terminalText = try visualFrame("fleck-terminal-text", in: host)
        #expect(terminalText.width > 0)
        #expect(host.bounds.contains(terminalText))
      }
      if chooser != nil {
        let chooserFrame = try visualFrame("fleck-rail-chooser", in: host)
        #expect(chooserFrame.width > 0)
        #expect(chooserFrame.height > 0)
        #expect(host.bounds.contains(chooserFrame))
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

    let shortSaved = DictationCapsuleContext(status: .saved(destination: "Inbox"))
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

    let captureID = UUID()
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
      ambiguity: .init(captureID: UUID(), choices: [])
    )
    controller.render(shortSaved, chooser: keepInboxChooser)
    try await settleAndRecord(
      "saved-keep-inbox",
      screen: selectedScreen,
      context: shortSaved,
      chooser: keepInboxChooser
    )

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
    panel.appearance = NSAppearance(named: .darkAqua)
    let controller = DictationCapsuleController(panel: panel, markLoader: markLoader)
    defer { controller.dismiss() }

    func render(
      _ name: String,
      context: DictationCapsuleContext,
      size: CGSize? = nil,
      action: DictationCapsuleAction? = nil,
      seedSyntheticWaveform: Bool = false
    ) throws {
      controller.panel.orderOut(nil)
      controller.render(context, action: action)
      if seedSyntheticWaveform {
        prepareSyntheticWaveformFixture(for: controller)
      }
      controller.panel.contentView?.appearance = NSAppearance(named: .darkAqua)
      try captureVisualState(
        name,
        controller: controller,
        size: size ?? DictationCapsuleController.size(for: context.status),
        directory: captureDirectory
      )
    }

    try render(
      "idle-bottom",
      context: DictationCapsuleContext(status: .idle),
      size: DictationCapsuleController.idleSize
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
        size: DictationCapsuleController.size(for: .arming),
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
        feedbackController.render(.arming)
        feedbackController.panel.contentView?.appearance = NSAppearance(named: appearance)
        try captureVisualState(
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
        try captureVisualState(
          "capture-feedback-listening-quiet-\(appearanceName)-\(dock.rawValue)",
          controller: feedbackController,
          size: DictationCapsuleController.listeningSize,
          directory: captureDirectory
        )
        prepareSyntheticWaveformFixture(for: feedbackController)
        try captureVisualState(
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
        feedbackController.waveformModel.beginListening()
        feedbackController.panel.contentView?.appearance = NSAppearance(named: appearance)
        try captureVisualState(
          "single-row-smart-capture-listening-quiet-\(appearanceName)-\(dock.rawValue)",
          controller: feedbackController,
          size: DictationCapsuleController.size(for: smartCapture.status),
          directory: captureDirectory
        )
        prepareSyntheticWaveformFixture(for: feedbackController)
        try captureVisualState(
          "single-row-smart-capture-listening-live-\(appearanceName)-\(dock.rawValue)",
          controller: feedbackController,
          size: DictationCapsuleController.size(for: smartCapture.status),
          directory: captureDirectory
        )
        feedbackController.presentationModel.setListeningHover(true)
        for _ in 0..<5 { await Task.yield() }
        feedbackController.panel.contentView?.layoutSubtreeIfNeeded()
        try captureVisualState(
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
        feedbackController.waveformModel.beginListening()
        feedbackController.panel.contentView?.appearance = NSAppearance(named: appearance)
        try captureVisualState(
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
    try render(
      "listening-right-option-held-bottom",
      context: heldListening,
      size: DictationCapsuleController.listeningSize
    )
    prepareSyntheticWaveformFixture(for: controller)
    try captureVisualState(
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
      size: DictationCapsuleController.listeningSize
    )
    prepareSyntheticWaveformFixture(for: controller)
    try captureVisualState(
      "listening-hands-free-bottom-seeded",
      controller: controller,
      size: DictationCapsuleController.listeningSize,
      directory: captureDirectory
    )
    controller.presentationModel.setListeningHover(true)
    try captureVisualState(
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
    try render(
      "polishing-smart-capture-bottom",
      context: smartPolishing
    )

    try render(
      "saved-undo-bottom",
      context: visualCaptureContext(.saved(destination: "Inbox")),
      size: DictationCapsuleController.savedSize,
      action: .undo
    )
    try render(
      "saved-original-bottom",
      context: visualCaptureContext(.savedWithoutCleanup(destination: "Inbox")),
      size: DictationCapsuleController.savedWithoutCleanupSize
    )
    try render(
      "save-failure-recovery-bottom",
      context: visualCaptureContext(
        .failed("save failed"),
        stage: .save,
        failureStage: .save,
        failureKind: .save
      ),
      size: DictationCapsuleController.failureSize,
      action: .openDestination
    )
    try render(
      "no-speech-bottom",
      context: visualCaptureContext(.noSpeech),
      size: DictationCapsuleController.noSpeechSize
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
      controller.waveformModel.receive(level: level)
      try await Task.sleep(for: .milliseconds(80))
      try captureVisualState(
        String(format: "frame-%03d", index), controller: controller,
        size: DictationCapsuleController.listeningSize, directory: directory
      )
    }
    for dock in [DictationCapsuleDock.left, .right] {
      controller.setDock(dock)
      controller.waveformModel.receive(level: 0.20)
      controller.presentationModel.setListeningHover(true)
      try await Task.sleep(for: .milliseconds(80))
      try captureVisualState("listening-\(dock.rawValue)-controls", controller: controller,
        size: DictationCapsuleController.listeningSize, directory: directory)
    }
    controller.render(visualCaptureContext(.cleaning, stage: .polish))
    #expect(controller.waveformModel.energy == 0)
    try captureVisualState("processing", controller: controller,
      size: DictationCapsuleController.activeSize, directory: directory)
    controller.dismiss()
    #expect(controller.waveformModel.energy == 0)
  }
#endif
