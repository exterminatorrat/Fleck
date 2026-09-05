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
#endif
