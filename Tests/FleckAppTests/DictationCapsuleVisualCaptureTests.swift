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
    isHandsFree: Bool = false,
    stage: DictationPipelineStage? = nil,
    cleanup: DictationCleanupOutcome? = nil,
    failureStage: DictationPipelineStage? = nil,
    failureKind: DictationCapsuleFailureKind? = nil
  ) -> DictationCapsuleContext {
    DictationCapsuleContext(
      status: status,
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
    controller.waveformModel.receive(level: 0.20, now: Date().addingTimeInterval(0.04))
    controller.waveformModel.receive(level: 0.14, now: Date().addingTimeInterval(0.08))
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

  @Test @MainActor
  func DictationCapsuleRendersCapturedContextWithoutCoveringLiveControls() throws {
    let panel = DictationCapsulePanel()
    let controller = DictationCapsuleController(panel: panel)
    defer { controller.dismiss() }

    func frames(
      for context: DictationCapsuleContext,
      size: CGSize,
      adjacentProbe: String
    ) throws -> (context: CGRect, adjacent: CGRect, bounds: CGRect) {
      controller.render(context)
      panel.setFrame(CGRect(origin: .zero, size: size), display: false)
      panel.contentView?.frame = CGRect(origin: .zero, size: size)
      panel.contentView?.layoutSubtreeIfNeeded()
      let host = try #require(panel.contentView)
      let contextProbe = try #require(visualProbe("fleck-rail-context", in: host))
      let adjacent = try #require(visualProbe(adjacentProbe, in: host))
      return (
        contextProbe.convert(contextProbe.bounds, to: host),
        adjacent.convert(adjacent.bounds, to: host),
        host.bounds
      )
    }

    for dock in [DictationCapsuleDock.bottom, .left, .right] {
      controller.setDock(dock)
      let listening = try frames(
        for: .init(
          status: .listening,
          detailText: "Dictating into Travel plans",
          compactDetailText: "Travel plans",
          sessionID: visualCaptureSessionID,
          trigger: .hold,
          mode: .focused,
          pipelineStage: .capture
        ),
        size: DictationCapsuleController.listeningSize,
        adjacentProbe: "fleck-rail-timer"
      )
      #expect(listening.context.width > 0)
      #expect(listening.bounds.contains(listening.context))
      #expect(!listening.context.intersects(listening.adjacent))
    }

    controller.setDock(.bottom)
    let processing = try frames(
      for: .init(
        status: .cleaning,
        detailText: "Smart Capture",
        sessionID: visualCaptureSessionID,
        trigger: .hold,
        mode: .smartCapture,
        pipelineStage: .polish
      ),
      size: DictationCapsuleController.activeSize,
      adjacentProbe: "fleck-rail-mark"
    )
    #expect(processing.context.width > 0)
    #expect(processing.bounds.contains(processing.context))
    #expect(!processing.context.intersects(processing.adjacent))
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
      size: CGSize,
      action: DictationCapsuleAction? = nil
    ) throws {
      controller.panel.orderOut(nil)
      controller.render(context, action: action)
      controller.panel.contentView?.appearance = NSAppearance(named: .darkAqua)
      try captureVisualState(name, controller: controller, size: size, directory: captureDirectory)
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
    ) throws {
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
      }
    }

    try renderCaptureFeedbackMatrix(appearance: .aqua, appearanceName: "light")
    try renderCaptureFeedbackMatrix(appearance: .darkAqua, appearanceName: "dark")

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
        size: DictationCapsuleController.listeningSize
      )
      prepareSyntheticWaveformFixture(for: controller)
    }
    controller.setDock(.bottom)

    let handsFreeListening = visualCaptureContext(
      .listening,
      isHandsFree: true,
      stage: .capture
    )
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

    let polishing = visualCaptureContext(.cleaning, stage: .polish)
    try render(
      "polishing-after-label-delay-bottom",
      context: polishing,
      size: DictationCapsuleController.activeSize
    )
    try await Task.sleep(for: .milliseconds(500))
    for _ in 0..<5 { await Task.yield() }
    controller.presentationModel.setListeningHover(false)
    try captureVisualState(
      "polishing-after-label-delay-bottom-visible",
      controller: controller,
      size: DictationCapsuleController.activeSize,
      directory: captureDirectory
    )
    try render(
      "polishing-smart-capture-bottom",
      context: .init(
        status: .cleaning,
        detailText: "Smart Capture",
        sessionID: visualCaptureSessionID,
        trigger: .hold,
        mode: .smartCapture,
        pipelineStage: .polish
      ),
      size: DictationCapsuleController.activeSize
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
