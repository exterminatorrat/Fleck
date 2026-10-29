#if os(macOS)
import AppKit
import FleckCore
import Testing

@testable import FleckApp

@Test @MainActor func successfulPersistenceRendersOnlyExistingStandbyWithoutActions() throws {
  let panel = DictationCapsulePanel()
  let controller = DictationCapsuleController(panel: panel, automaticallyAdvancesLivePill: false)
  controller.setReduceMotionOverrideForTesting(true)
  controller.setPanelVisibilitySuppressedForTesting(true)
  defer { controller.dismiss() }
  let captureID = UUID()
  let noteID = UUID()
  let chooser = DictationCapsuleChooser(ambiguity: .init(captureID: captureID, choices: [
    .init(destination: .init(noteID: noteID, title: "Synthetic Projects"), contextHint: "Synthetic"),
  ]))
  for status in [DictationCapsuleStatus.saved(destination: "Inbox"),
    .savedWithoutCleanup(destination: "Inbox")]
  {
    controller.render(.init(status: status, sessionID: captureID,
      cleanupOutcome: .usedRaw, cleanupFallbackProvenance: .serviceFallback),
      action: .undo, chooser: chooser)
    let host = try #require(panel.contentView)
    host.layoutSubtreeIfNeeded()
    #expect(controller.currentContext.status == .idle)
    #expect(controller.fleckPillModel.state == .standby)
    #expect(controller.fleckPillModel.frame.expansion == 0)
    #expect(!controller.fleckPillModel.needsAnimation)
    #expect(controller.presentationModel.action == nil)
    #expect(controller.presentationModel.chooser == nil)
    #expect(controller.currentChooser == nil)
    #expect(controller.errorPresentationModel.presentation == nil)
    #expect(panel.frame.size == DictationCapsuleController.livePillHostSize)
    #expect(!panel.hasShadow)
    let titles = try #require(host.menu).items.map(\.title)
    for absent in ["Dock Left", "Dock Right", "Undo", "Choose note", "Dismiss"] {
      #expect(!titles.contains(absent))
    }
    #expect(DictationCapsulePresentation(status: status, action: .undo,
      chooser: chooser, context: .init(status: status, sessionID: captureID)).visibleText == nil)
  }
}

@Test @MainActor func capsuleRejectsLegacyPlacementsAtEveryControllerEntryPoint() {
  let controller = DictationCapsuleController(automaticallyAdvancesLivePill: false)
  controller.setPanelVisibilitySuppressedForTesting(true)
  defer { controller.dismiss() }
  for legacy in [DictationCapsuleDock.left, .right] {
    controller.presentIdle(dock: legacy, onOpenFleck: {}, onDockChanged: { _ in })
    #expect(controller.currentDock == .bottom)
    #expect(controller.fleckPillModel.usesFixedHost)
    controller.setDock(legacy)
    #expect(controller.currentDock == .bottom)
    #expect(controller.presentationModel.dock == .bottom)
  }
}

@Test func supportedPillFramesStayBottomCenteredAcrossDisplayOriginsAndSizes() {
  for visible in [
    CGRect(x: 0, y: 0, width: 800, height: 600),
    CGRect(x: 100, y: 80, width: 1_440, height: 900),
    CGRect(x: -1_920, y: -400, width: 1_920, height: 1_080),
    CGRect(x: 2_000, y: 700, width: 3_008, height: 1_692),
  ] {
    let compact = DictationCapsuleController.livePillFrame(in: visible)
    let recovery = DictationCapsuleController.errorSurfaceFrame(for: .bottom, in: visible)
    #expect(compact.midX == visible.midX)
    #expect(recovery.midX == visible.midX)
    #expect(compact.minY == visible.minY)
    #expect(recovery.minY == compact.minY)
    #expect(visible.contains(compact))
    #expect(visible.contains(recovery))
  }
}

@Test @MainActor func supportedPillStatesKeepActualAnchorAndCaptureWhenRequested() async throws {
  let directory = ProcessInfo.processInfo.environment["FLECK_PILL_PLACEMENT_CAPTURE_DIR"]
    .map { URL(fileURLWithPath: $0, isDirectory: true) }
  if let directory {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }
  let errorProbeIdentifiers = [
    "fleck-error-surface",
    "fleck-error-message",
    "fleck-rail-recovery",
    "fleck-error-action-label",
  ]
  func collectErrorProbeFrames(in root: NSView) -> [(identifier: String, frame: CGRect)] {
    var frames: [(identifier: String, frame: CGRect)] = []
    func collect(from view: NSView) {
      if let identifier = view.identifier?.rawValue,
        errorProbeIdentifiers.contains(identifier)
      {
        frames.append((identifier, view.convert(view.bounds, to: root)))
      }
      for child in view.subviews { collect(from: child) }
    }
    collect(from: root)
    return frames
  }
  var observations: [[String: Any]] = []
  for appearance in [FleckThemeAppearance.light, .dark] {
    for profile in ["standard", "reduced-motion", "contrast-and-opaque"] {
      let reducedMotion = profile == "reduced-motion"
      let opaque = profile == "contrast-and-opaque"
      let panel = DictationCapsulePanel()
      panel.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
      let theme = FleckThemeSnapshot.resolve(colorTheme: .monochrome, mode: .system,
        systemAppearance: appearance, reduceTransparency: opaque, increasedContrast: opaque)
      let controller = DictationCapsuleController(panel: panel,
        automaticallyAdvancesLivePill: false, reduceMotionProvider: { reducedMotion }, theme: theme,
        announcementPoster: { _, _ in })
      controller.setPanelVisibilitySuppressedForTesting(true)
      controller.setReduceMotionOverrideForTesting(reducedMotion)
      controller.setAccessibilityEnvironmentOverridesForTesting(reduceTransparency: opaque,
        increasedContrast: opaque)
      defer { controller.dismiss() }
      controller.presentIdle(dock: .bottom, onOpenFleck: {}, onDockChanged: { _ in })
      let sessionID = UUID()
      let destination = DictationDestination(noteID: UUID(), title: "Inbox")
      let chooser = DictationCapsuleChooser(ambiguity: .init(captureID: sessionID, choices: [
        .init(destination: .init(noteID: UUID(), title: "Synthetic Projects"), contextHint: "Synthetic"),
      ]))
      let scenarios: [(String, DictationCapsuleStatus, DictationPhase?, DictationPipelineStage?, DictationCapsuleAction?, DictationCapsuleChooser?)] = [
        ("standby", .idle, nil, nil, nil, nil),
        ("arming", .arming, .arming, .capture, nil, nil),
        ("listening", .listening, .listening(mode: .smartCapture, engine: .standard), .capture, nil, nil),
        ("listening-hands-free", .listening, .listening(mode: .smartCapture, engine: .standard), .capture, nil, nil),
        ("listening-focused", .listening, .listening(mode: .focused, engine: .standard), .capture, nil, nil),
        ("finalizing", .finalizing, .finalizing, .capture, nil, nil),
        ("polishing", .cleaning, .cleaning, .polish, nil, nil),
        ("routing", .routing, .routing, .organize, nil, nil),
        ("saving", .saving, .routing, .save, nil, nil),
        ("saved", .saved(destination: "Inbox"), nil, .save, nil, nil),
        ("saved-undo", .saved(destination: "Inbox"), nil, .save, .undo, nil),
        ("saved-chooser", .saved(destination: "Inbox"), nil, .save, nil, chooser),
        ("saved-undo-chooser", .saved(destination: "Inbox"), nil, .save, .undo, chooser),
        ("saved-raw", .savedWithoutCleanup(destination: "Inbox"), nil, .save, nil, nil),
        ("used-original", .savedWithoutCleanup(destination: "Inbox"), nil, .save, nil, nil),
        ("save-recovery", .failed("Synthetic save failure"), nil, .save, .copy, nil),
        ("routing-recovery", .routingFailure(status: "Needs attention", message: "Synthetic route failure"), nil, .organize, .openDestination, chooser),
        ("no-speech", .noSpeech, nil, .capture, nil, nil),
        ("microphone-recovery", .failed("Synthetic permission failure"), nil, .capture, nil, nil),
        ("repairing", .repairingModel, nil, .polish, nil, nil),
        ("repair-recovery", .failed("Synthetic repair failure"), nil, .polish, .openHistory, nil),
      ]
      for (name, status, phase, stage, action, routeChooser) in scenarios {
        let mode: DictationMode = name == "listening-focused" ? .focused : .smartCapture
        let failureKind: DictationCapsuleFailureKind? = switch name {
        case "save-recovery": .save
        case "microphone-recovery": .microphoneAccess
        case "repair-recovery": .modelRepair
        default: nil
        }
        let context = DictationCapsuleContext(status: status, sessionID: sessionID,
          mode: mode, isHandsFree: name == "listening-hands-free", pipelineStage: stage,
          cleanupOutcome: name == "used-original" ? .usedRaw : nil,
          cleanupFallbackProvenance: name == "used-original" ? .serviceFallback : nil,
          failureStage: name.hasSuffix("recovery") ? stage : nil,
          failureKind: failureKind)
        let event = phase.map { phase in
          DictationCoordinatorEvent(phase: phase, terminal: nil,
            context: .init(sessionID: sessionID, mode: mode, destination: destination,
              pipelineStage: stage ?? .capture, cleanupOutcome: nil, failureStage: nil))
        }
        controller.render(context, action: action, chooser: routeChooser, coordinatorEvent: event)
        controller.presentationModel.setListeningHover(name == "listening-hands-free")
        controller.fleckPillModel.tick(at: ProcessInfo.processInfo.systemUptime + 1,
          displayedEnergy: 0.25, reduceMotion: reducedMotion)
        for _ in 0..<5 { await Task.yield() }
        let host = try #require(panel.contentView)
        host.layoutSubtreeIfNeeded()
        let screen = try #require(panel.screen ?? NSScreen.main ?? NSScreen.screens.first)
        let isRecovery = controller.errorPresentationModel.presentation != nil
        let presentation = DictationCapsulePresentation(status: status, action: action,
          chooser: routeChooser, context: context)
        let expected: CGRect
        if isRecovery {
          expected = DictationCapsuleController.errorSurfaceFrame(for: .bottom, in: screen.visibleFrame)
        } else if controller.fleckPillModel.usesFixedHost {
          expected = DictationCapsuleController.livePillFrame(in: screen.visibleFrame)
        } else {
          expected = DictationCapsuleController.frame(for: .bottom,
            size: DictationCapsuleController.size(for: status, measuredWidth: presentation.measuredWidth,
              widthCeiling: presentation.widthCeiling), in: screen.visibleFrame)
        }
        let errorProbes = collectErrorProbeFrames(in: host)
        let errorProbeCountMetadata = errorProbeIdentifiers.map { identifier in
          "\(identifier)=\(errorProbes.filter { $0.identifier == identifier }.count)"
        }.joined(separator: ", ")
        let errorProbeFrameMetadata = errorProbes
          .map { "\($0.identifier)=\($0.frame)" }
          .joined(separator: ", ")
        let placementDiagnostic = [
          "state=\(name)",
          "appearance=\(appearance)",
          "profile=\(profile)",
          "scale=\(screen.backingScaleFactor)",
          "logicalExpected=\(expected)",
          "panelFrame=\(panel.frame)",
          "hostFrame=\(host.frame)",
          "hostBounds=\(host.bounds)",
          "errorProbeCounts={\(errorProbeCountMetadata)}",
          "errorProbeFrames={\(errorProbeFrameMetadata)}",
        ].joined(separator: " ")
        #expect(panel.frame == expected, Comment(rawValue: placementDiagnostic))
        #expect(host.bounds.size == expected.size, Comment(rawValue: placementDiagnostic))
        #expect(controller.currentDock == .bottom)
        if case .saved = status {
          #expect(controller.currentContext.status == .idle)
          #expect(controller.fleckPillModel.state == .standby)
          #expect(controller.fleckPillModel.frame.expansion == 0)
          #expect(!controller.fleckPillModel.needsAnimation)
          #expect(controller.presentationModel.action == nil)
          #expect(controller.currentChooser == nil)
        }
        observations.append(["name": name, "appearance": String(describing: appearance),
          "profile": profile, "x": panel.frame.minX, "y": panel.frame.minY,
          "width": panel.frame.width, "height": panel.frame.height,
          "screenMidX": screen.visibleFrame.midX, "screenMinY": screen.visibleFrame.minY,
          "backingScale": screen.backingScaleFactor,
          "logicalExpectedFrame": String(describing: expected),
          "panelFrame": String(describing: panel.frame),
          "hostFrame": String(describing: host.frame),
          "hostBounds": String(describing: host.bounds),
          "errorProbeCounts": errorProbeCountMetadata,
          "errorProbeFrames": errorProbeFrameMetadata])
        if let directory {
          let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
          host.cacheDisplay(in: host.bounds, to: bitmap)
          let data = try #require(bitmap.representation(using: .png, properties: [:]))
          try data.write(to: directory.appendingPathComponent("\(appearance)-\(profile)-\(name).png"))
        }
      }
    }
  }
  if let directory {
    try JSONSerialization.data(withJSONObject: observations, options: [.prettyPrinted, .sortedKeys])
      .write(to: directory.appendingPathComponent("actual-panel-geometry.json"))
  }
}
#endif
