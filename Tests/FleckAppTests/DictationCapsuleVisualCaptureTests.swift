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
  private func prepareWaveform(for controller: DictationCapsuleController) {
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
    try render(
      "arming-bottom",
      context: DictationCapsuleContext(status: .arming),
      size: DictationCapsuleController.idleSize
    )

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
    prepareWaveform(for: controller)
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
    prepareWaveform(for: controller)
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
