#if os(macOS) && DEBUG
import AppKit
import CryptoKit
import Foundation
import FleckCore
import SwiftUI
import Testing

  @testable import FleckApp

  private enum FleckPillCaptureSupport {
    static let directory = ProcessInfo.processInfo.environment["FLECK_PILL_CAPTURE_DIRECTORY"]
      .map(URL.init(fileURLWithPath:))
    static let sequenceEnabled = ProcessInfo.processInfo.environment["FLECK_PILL_CAPTURE_SEQUENCE"] == "1"
    static let livePanelEnabled = ProcessInfo.processInfo.environment["FLECK_PILL_CAPTURE_LIVE_PANEL"] == "1"

    static let sourceFiles = [
      "Sources/FleckApp/FleckApp.swift",
      "Sources/FleckApp/FleckPillCanvas.swift",
      "Sources/FleckApp/FleckPillDebugHarness.swift",
      "Sources/FleckApp/FleckPillGeometry.swift",
      "Sources/FleckApp/FleckPillMotion.swift",
      "Tests/FleckAppTests/FleckPillFixtureTests.swift",
      "Tests/FleckAppTests/FleckPillMotionTests.swift",
      "Tests/FleckAppTests/FleckPillVisualCaptureTests.swift",
    ]

    @MainActor
    static func nativeImage(_ view: FleckPillCanvas, scale: Int) throws -> (CGImage, Data) {
      let renderer = ImageRenderer(content: view)
      renderer.scale = CGFloat(scale)
      renderer.proposedSize = ProposedViewSize(width: 180, height: 39)
      renderer.isOpaque = true
      renderer.colorMode = .nonLinear
      let image = try #require(renderer.cgImage)
      #expect(image.width == 180 * scale)
      #expect(image.height == 39 * scale)
      let bitmap = NSBitmapImageRep(cgImage: image)
      let data = try #require(bitmap.representation(using: .png, properties: [:]))
      return (image, data)
    }

    static func write(_ data: Data, to url: URL) throws {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try data.write(to: url, options: .atomic)
    }

    static func sourceIdentity() throws -> [String: Any] {
      let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
      func git(_ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = root
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
          let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        else {
          throw CocoaError(.fileReadUnknown)
        }
        return value
      }
      let files = try sourceFiles.map { path -> [String: String] in
        let data = try Data(contentsOf: root.appendingPathComponent(path))
        return ["path": path, "sha256": SHA256.hash(data: data).hexString]
      }
      let runner = try #require(Bundle.main.executableURL)
      return [
        "commit": try git(["rev-parse", "HEAD"]),
        "commitTree": try git(["rev-parse", "HEAD^{tree}"]),
        "worktreeStatus": try git(["status", "--short", "--untracked-files=all"]),
        "sourceFiles": files,
        "testRunnerExecutable": [
          "path": runner.path,
          "sha256": try SHA256.hash(data: Data(contentsOf: runner)).hexString,
        ],
        "buildConfiguration": "DEBUG",
      ]
    }

    static func findAccessibilityElement(_ value: Any?, identifier: String) -> NSObject? {
      guard let element = value as? NSObject else { return nil }
      let identifierSelector = NSSelectorFromString("accessibilityIdentifier")
      let childrenSelector = NSSelectorFromString("accessibilityChildren")
      let name = element.responds(to: identifierSelector)
        ? element.perform(identifierSelector)?.takeUnretainedValue() as? String
        : nil
      if name == identifier { return element }
      let children = element.responds(to: childrenSelector)
        ? element.perform(childrenSelector)?.takeUnretainedValue() as? [Any]
        : nil
      for child in children ?? [] {
        if let found = findAccessibilityElement(child, identifier: identifier) { return found }
      }
      return nil
    }

    @MainActor
    static func settle(_ view: NSView) async {
      for _ in 0..<12 {
        view.layoutSubtreeIfNeeded()
        await Task.yield()
      }
    }
  }

  private extension Digest {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
  }

  private struct FleckPillShellMask: View {
    let frame: FleckPillMotionFrame

    var body: some View {
      Canvas(opaque: false) { context, _ in
        let shell = FleckPillGeometry.shell(expansion: frame.expansion)
        var path = Path()
        for command in shell.fill.commands {
          switch command {
          case .move(let point):
            path.move(to: CGPoint(x: point.x, y: point.y))
          case .line(let point):
            path.addLine(to: CGPoint(x: point.x, y: point.y))
          case .cubic(let first, let second, let end):
            path.addCurve(
              to: CGPoint(x: end.x, y: end.y),
              control1: CGPoint(x: first.x, y: first.y),
              control2: CGPoint(x: second.x, y: second.y)
            )
          case .close:
            path.closeSubpath()
          }
        }
        let transform = CGAffineTransform(a: 0.75, b: 0, c: 0, d: 0.75, tx: 6, ty: 9)
        context.fill(path.applying(transform), with: .color(.white))
      }
      .frame(width: 180, height: 39)
    }
  }

  private struct FleckPillLivePreview: View {
    @ObservedObject var model: FleckPillDebugHarnessModel

    var body: some View {
      FleckPillCanvas(frame: model.frame, layers: model.layers, backdrop: .dark)
    }
  }

  private enum FleckPillPixelChecks {
    @MainActor
    static func image(_ view: FleckPillShellMask, scale: Int) throws -> NSBitmapImageRep {
      let renderer = ImageRenderer(content: view)
      renderer.scale = CGFloat(scale)
      renderer.proposedSize = ProposedViewSize(width: 180, height: 39)
      return NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
    }

    @MainActor
    static func image(_ view: FleckPillCanvas, scale: Int) throws -> NSBitmapImageRep {
      let (image, _) = try FleckPillCaptureSupport.nativeImage(view, scale: scale)
      return NSBitmapImageRep(cgImage: image)
    }

    static func changedPixels(
      _ first: NSBitmapImageRep,
      _ second: NSBitmapImageRep,
      mask: NSBitmapImageRep
    ) -> (inside: Int, outside: Int) {
      precondition(
        first.pixelsWide == second.pixelsWide && first.pixelsHigh == second.pixelsHigh
          && first.pixelsWide == mask.pixelsWide && first.pixelsHigh == mask.pixelsHigh
      )
      var inside = 0
      var outside = 0
      for y in 2..<(first.pixelsHigh - 2) {
        for x in 2..<(first.pixelsWide - 2) {
          guard let a = first.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
            let b = second.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
          else { continue }
          let difference = max(
            max(
              abs(a.redComponent - b.redComponent),
              abs(a.greenComponent - b.greenComponent)
            ),
            max(
              abs(a.blueComponent - b.blueComponent),
              abs(a.alphaComponent - b.alphaComponent)
            )
          )
          guard difference > 0.015 else { continue }
          if isInsideOrNearMask(x: x, y: y, image: mask, margin: 2) {
            inside += 1
          } else {
            outside += 1
          }
        }
    }
      return (inside, outside)
    }

    static func brightHorizontalBounds(_ image: NSBitmapImageRep) -> ClosedRange<Int>? {
      var minimum = Int.max
      var maximum = Int.min
      for y in 0..<image.pixelsHigh {
        for x in 0..<image.pixelsWide {
          guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
            color.redComponent > 0.2,
            color.greenComponent > 0.2,
            color.blueComponent > 0.2
          else { continue }
          minimum = min(minimum, x)
          maximum = max(maximum, x)
        }
      }
      return minimum <= maximum ? minimum...maximum : nil
    }

    private static func isInsideOrNearMask(
      x: Int,
      y: Int,
      image: NSBitmapImageRep,
      margin: Int
    ) -> Bool {
      for dy in -margin...margin {
        for dx in -margin...margin {
          guard let color = image.colorAt(x: x + dx, y: y + dy)?.usingColorSpace(.deviceRGB) else { continue }
          if color.alphaComponent > 0.01 { return true }
        }
      }
      return false
    }
  }

  @Test @MainActor
  func FleckPillUnblurredWaveCoreUsesRootAndLightTransform() throws {
    var opening = FleckPillMotion.sample(0.75)
    opening.expansion = 0.5
    opening.energy = 1
    opening.phase = 0
    opening.activationMix = 0
    opening.processingMix = 0
    opening.signalOpacity = 1
    let frames: [(
      name: String,
      frame: FleckPillMotionFrame,
      left: ClosedRange<Int>,
      right: ClosedRange<Int>
    )] = [
      (
        name: "listening-anchor",
        frame: FleckPillMotion.sample(FleckPillMotion.anchors[.listening]!),
        left: 135...165,
        right: 375...420
      ),
      (name: "opening-sample", frame: opening, left: 175...230, right: 310...365),
    ]
    let layers = FleckPillCanvasLayers(rim: false, shoulders: false, signal: true, halo: false)
    let scale = 3
    for (sampleIndex, sample) in frames.enumerated() {
      let image = try FleckPillPixelChecks.image(
        FleckPillCanvas(frame: sample.frame, layers: layers, backdrop: .dark),
        scale: scale
      )
      let bounds = try #require(FleckPillPixelChecks.brightHorizontalBounds(image))
      let pixelDiagnostic = [
        "sample=\(sample.name)[\(sampleIndex)]",
        "brightBounds=\(bounds)",
        "image=\(image.pixelsWide)x\(image.pixelsHigh)",
        "scale=\(scale)",
        "expectedLeft=\(sample.left)",
        "expectedRight=\(sample.right)",
      ].joined(separator: " ")
      #expect(
        bounds.lowerBound >= sample.left.lowerBound && bounds.lowerBound <= sample.left.upperBound,
        Comment(rawValue: pixelDiagnostic)
      )
      #expect(
        bounds.upperBound >= sample.right.lowerBound && bounds.upperBound <= sample.right.upperBound,
        Comment(rawValue: pixelDiagnostic)
      )
    }
  }

  @Test @MainActor
  func FleckPillIntermediateOpeningHaloStaysInsideRootViewBoxClip() throws {
    var frame = FleckPillMotion.sample(0.75)
    frame.expansion = 0.5
    frame.energy = 1
    frame.phase = 0
    frame.activationMix = 0
    frame.processingMix = 0
    frame.signalOpacity = 1
    frame.glintOpacity = 0
    let layers = FleckPillCanvasLayers(rim: false, shoulders: false, signal: true, halo: true)
    let withoutSignal = try FleckPillPixelChecks.image(
      FleckPillCanvas(
        frame: frame,
        layers: FleckPillCanvasLayers(rim: false, shoulders: false, signal: false, halo: false),
        backdrop: .dark
      ),
      scale: 3
    )
    let withSignal = try FleckPillPixelChecks.image(
      FleckPillCanvas(frame: frame, layers: layers, backdrop: .dark),
      scale: 3
    )
    let mask = try FleckPillPixelChecks.image(FleckPillShellMask(frame: frame), scale: 3)
    let difference = FleckPillPixelChecks.changedPixels(withoutSignal, withSignal, mask: mask)
    #expect(difference.inside > 0)
    #expect(difference.outside == 0)
  }

  @Test @MainActor
  func FleckPillOpeningAndActiveShoulderBlurStaysInsideIsolatedShell() throws {
    for (time, expansion) in [(0.75, 0.5), (1.5, 1.0)] {
      var frame = FleckPillMotion.sample(time)
      frame.expansion = expansion
      frame.energy = 0
      frame.signalOpacity = 0
      let withoutShoulders = try FleckPillPixelChecks.image(
        FleckPillCanvas(
          frame: frame,
          layers: FleckPillCanvasLayers(rim: false, shoulders: false, signal: false, halo: false),
          backdrop: .dark
        ),
        scale: 3
      )
      let withShoulders = try FleckPillPixelChecks.image(
        FleckPillCanvas(
          frame: frame,
          layers: FleckPillCanvasLayers(rim: false, shoulders: true, signal: false, halo: false),
          backdrop: .dark
        ),
        scale: 3
      )
      let mask = try FleckPillPixelChecks.image(FleckPillShellMask(frame: frame), scale: 3)
      let difference = FleckPillPixelChecks.changedPixels(withoutShoulders, withShoulders, mask: mask)
      #expect(difference.inside > 0)
      #expect(difference.outside == 0)
    }
  }

  @Test(.enabled(if: FleckPillCaptureSupport.directory != nil, "Set FLECK_PILL_CAPTURE_DIRECTORY to save native captures"))
  @MainActor
  func FleckPillFourFrozenStatesRenderAtOneAndThreeTimes() throws {
    let directory = try #require(FleckPillCaptureSupport.directory)
    let panel = DictationCapsulePanel()
    panel.hasShadow = false
    panel.ignoresMouseEvents = true
    panel.isOpaque = false
    panel.backgroundColor = .clear

    for pose in FleckPillPose.allCases {
      let frame = try FleckPillGeometry.pose(named: pose.rawValue)
      for (backdropName, backdrop) in [
        ("dark", FleckPillCanvasBackdrop.dark),
        ("bright", FleckPillCanvasBackdrop.bright),
      ] {
        for scale in [1, 3] {
          let view = FleckPillCanvas(frame: frame, backdrop: backdrop)
          let (_, data) = try FleckPillCaptureSupport.nativeImage(view, scale: scale)
          try FleckPillCaptureSupport.write(
            data,
            to: directory.appendingPathComponent("\(pose.rawValue)-\(backdropName)-\(scale)x-native.png")
          )
        }

        let panelView = NSHostingView(rootView: FleckPillCanvas(frame: frame, backdrop: backdrop))
        panel.setFrame(CGRect(x: 0, y: 0, width: 180, height: 39), display: false)
        panel.contentView = panelView
        panelView.frame = CGRect(x: 0, y: 0, width: 180, height: 39)
        panelView.layoutSubtreeIfNeeded()
        let panelBitmap = try #require(panelView.bitmapImageRepForCachingDisplay(in: panelView.bounds))
        panelView.cacheDisplay(in: panelView.bounds, to: panelBitmap)
        let panelData = try #require(panelBitmap.representation(using: .png, properties: [:]))
        try FleckPillCaptureSupport.write(
          panelData,
          to: directory.appendingPathComponent(
            "panel-\(pose.rawValue)-\(backdropName)-\(panelBitmap.pixelsWide)x\(panelBitmap.pixelsHigh).png"
          )
        )
      }
    }
    let metadata: [String: Any] = [
      "os": ProcessInfo.processInfo.operatingSystemVersionString,
      "swift": "6.3.3",
      "panelBackingScaleFactor": panel.backingScaleFactor,
      "nativeRendererScales": [1, 3],
      "logicalCanvas": [180, 39],
      "states": FleckPillPose.allCases.map(\.rawValue),
      "backdrops": ["dark", "bright"],
      "capture": "SwiftUI ImageRenderer plus a hidden DictationCapsulePanel NSHostingView",
      "sourceIdentity": try FleckPillCaptureSupport.sourceIdentity(),
    ]
    let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
    try FleckPillCaptureSupport.write(metadataData, to: directory.appendingPathComponent("capture-metadata.json"))
  }

  @Test(.enabled(if: FleckPillCaptureSupport.directory != nil, "Set FLECK_PILL_CAPTURE_DIRECTORY to save browser-parity samples"))
  @MainActor
  func FleckPillBrowserParitySamplesRenderAtThreeTimes() throws {
    let directory = try #require(FleckPillCaptureSupport.directory)
      .appendingPathComponent("browser-parity", isDirectory: true)
    let samples: [(name: String, time: Double)] = [
      ("anchor-standby", FleckPillMotion.anchors[.standby]!),
      ("anchor-activating", FleckPillMotion.anchors[.activating]!),
      ("anchor-listening", FleckPillMotion.anchors[.listening]!),
      ("anchor-processing", FleckPillMotion.anchors[.processing]!),
      ("opening-0.84", 0.84),
      ("flattening-6.34", 6.34),
    ]
    let layers: [(name: String, value: FleckPillCanvasLayers)] = [
      ("full", FleckPillCanvasLayers()),
      ("shell-only", FleckPillCanvasLayers(rim: false, shoulders: false, signal: false, halo: false)),
      ("signal-no-halo", FleckPillCanvasLayers(rim: false, shoulders: false, signal: true, halo: false)),
    ]

    for sample in samples {
      for layer in layers {
        let view = FleckPillCanvas(
          frame: FleckPillMotion.sample(sample.time),
          layers: layer.value,
          backdrop: .dark
        )
        let (_, data) = try FleckPillCaptureSupport.nativeImage(view, scale: 3)
        try FleckPillCaptureSupport.write(
          data,
          to: directory.appendingPathComponent("\(sample.name)-\(layer.name).png")
        )
      }
    }

    let metadata: [String: Any] = [
      "capture": "SwiftUI ImageRenderer at 3x on the approved dark background; offline frame samples, not desktop playback",
      "logicalCanvas": [180, 39],
      "backingScale": 3,
      "samples": samples.map { ["name": $0.name, "time": $0.time] },
      "layers": layers.map(\.name),
      "sourceIdentity": try FleckPillCaptureSupport.sourceIdentity(),
    ]
    let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
    try FleckPillCaptureSupport.write(metadataData, to: directory.appendingPathComponent("capture-metadata.json"))
  }

  @Test(.enabled(if: FleckPillCaptureSupport.directory != nil && FleckPillCaptureSupport.sequenceEnabled, "Set FLECK_PILL_CAPTURE_SEQUENCE=1 to record a deterministic sequence"))
  @MainActor
  func FleckPillTenSecondNativeSequenceRendersDeterministically() throws {
    let directory = try #require(FleckPillCaptureSupport.directory)
      .appendingPathComponent("sequence", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for index in 0...300 {
      let time = Double(index) / 30
      let view = FleckPillCanvas(frame: FleckPillMotion.sample(time), backdrop: .dark)
      let (_, data) = try FleckPillCaptureSupport.nativeImage(view, scale: 3)
      try FleckPillCaptureSupport.write(
        data,
        to: directory.appendingPathComponent(String(format: "frame-%04d.png", index))
      )
    }
    #expect((try FileManager.default.contentsOfDirectory(atPath: directory.path)).count == 301)
  }

  @Test(.enabled(
    if: FleckPillCaptureSupport.directory != nil && FleckPillCaptureSupport.livePanelEnabled,
    "Set FLECK_PILL_CAPTURE_DIRECTORY and FLECK_PILL_CAPTURE_LIVE_PANEL=1 to run the offscreen native panel"
  ))
  @MainActor
  func FleckPillDebugPanelTransportAndMonotonicClockCapture() async throws {
    let directory = try #require(FleckPillCaptureSupport.directory)
      .appendingPathComponent("debug-panel", isDirectory: true)
    let sequenceDirectory = directory.appendingPathComponent("sequence", isDirectory: true)
    try FileManager.default.createDirectory(at: sequenceDirectory, withIntermediateDirectories: true)

    let model = FleckPillDebugHarnessModel()
    NSApplication.shared.accessibilitySetValue(
      true,
      forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
    )
    let panel = DictationCapsulePanel()
    panel.hasShadow = false
    panel.ignoresMouseEvents = true
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.setFrame(
      CGRect(x: -1_000, y: -1_000, width: 720, height: 230),
      display: false
    )
    let host = NSHostingView(rootView: FleckPillDebugHarness(model: model))
    host.frame = CGRect(x: 0, y: 0, width: 720, height: 230)
    panel.contentView = host
    panel.orderFrontRegardless()
    defer { panel.orderOut(nil) }
    await FleckPillCaptureSupport.settle(host)

    func press(_ identifier: String) throws {
      let element = try #require(
        FleckPillCaptureSupport.findAccessibilityElement(host, identifier: identifier)
          ?? FleckPillCaptureSupport.findAccessibilityElement(panel, identifier: identifier)
      )
      let action = NSSelectorFromString("accessibilityPerformPress")
      #expect(element.responds(to: action))
      _ = element.perform(action)
    }

    func increment(_ identifier: String) throws {
      let element = try #require(
        FleckPillCaptureSupport.findAccessibilityElement(host, identifier: identifier)
          ?? FleckPillCaptureSupport.findAccessibilityElement(panel, identifier: identifier)
      )
      let action = NSSelectorFromString("accessibilityPerformIncrement")
      #expect(element.responds(to: action))
      _ = element.perform(action)
    }

    try press("fleck-pill-harness-play-pause")
    #expect(model.snapshot.playing)
    try await Task.sleep(for: .milliseconds(120))
    let advancedTime = model.snapshot.time
    #expect(advancedTime > 0)
    try press("fleck-pill-harness-play-pause")
    #expect(!model.snapshot.playing)
    let pausedTime = model.snapshot.time
    try press("fleck-pill-harness-step-back")
    #expect(abs(model.snapshot.time - max(0, pausedTime - 1.0 / 60)) < 0.0001)
    try press("fleck-pill-harness-pose-listening")
    #expect(model.snapshot.time == FleckPillMotion.anchors[.listening])
    #expect(!model.snapshot.playing)
    try increment("fleck-pill-harness-time")
    #expect(model.snapshot.time > FleckPillMotion.anchors[.listening]!)
    try increment("fleck-pill-harness-rate")
    #expect(model.snapshot.rate > 1)
    try press("fleck-pill-harness-loop")
    #expect(model.snapshot.loops)

    let panelBitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: panelBitmap)
    try FleckPillCaptureSupport.write(
      try #require(panelBitmap.representation(using: .png, properties: [:])),
      to: directory.appendingPathComponent("debug-panel-controls.png")
    )

    panel.orderOut(nil)
    panel.setFrame(CGRect(x: -1_000, y: -1_000, width: 180, height: 39), display: false)
    let liveHost = NSHostingView(rootView: FleckPillLivePreview(model: model))
    liveHost.frame = CGRect(x: 0, y: 0, width: 180, height: 39)
    panel.contentView = liveHost
    panel.orderFrontRegardless()
    model.setRate(1)
    model.setLoops(false)
    model.seek(to: 0)
    #expect(model.snapshot.rate == 1)
    #expect(!model.snapshot.loops)
    let start = ProcessInfo.processInfo.systemUptime * 1_000
    model.togglePlayback(at: start)
    var capturedTimes: [Double] = []
    var capturedSegments: [String] = []
    var capturedBitmaps: [NSBitmapImageRep] = []
    for index in 0...300 {
      let target = start + Double(index) / 30 * 1_000
      let remaining = target - ProcessInfo.processInfo.systemUptime * 1_000
      if remaining > 0 {
        try await Task.sleep(for: .nanoseconds(Int64(remaining * 1_000_000)))
      }
      model.tick(at: ProcessInfo.processInfo.systemUptime * 1_000)
      capturedTimes.append(model.snapshot.time)
      capturedSegments.append(model.frame.segment)
      liveHost.layoutSubtreeIfNeeded()
      let bitmap = try #require(liveHost.bitmapImageRepForCachingDisplay(in: liveHost.bounds))
      liveHost.cacheDisplay(in: liveHost.bounds, to: bitmap)
      try #require(!bitmap.isPlanar)
      let snapshot = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: bitmap.pixelsWide,
        pixelsHigh: bitmap.pixelsHigh,
        bitsPerSample: bitmap.bitsPerSample,
        samplesPerPixel: bitmap.samplesPerPixel,
        hasAlpha: bitmap.hasAlpha,
        isPlanar: false,
        colorSpaceName: bitmap.colorSpaceName,
        bytesPerRow: bitmap.bytesPerRow,
        bitsPerPixel: bitmap.bitsPerPixel
      ))
      try #require(snapshot.bitmapData).update(
        from: try #require(bitmap.bitmapData),
        count: bitmap.bytesPerRow * bitmap.pixelsHigh
      )
      capturedBitmaps.append(snapshot)
    }
    for (index, bitmap) in capturedBitmaps.enumerated() {
      try FleckPillCaptureSupport.write(
        try #require(bitmap.representation(using: .png, properties: [:])),
        to: sequenceDirectory.appendingPathComponent(String(format: "frame-%04d.png", index))
      )
    }
    #expect(model.snapshot.time > 9.9)
    #expect(model.snapshot.time <= FleckPillMotion.duration)
    let sampleGaps = capturedTimes.indices.dropFirst().map { index in
      capturedTimes[index] - capturedTimes[index - 1]
    }
    #expect(sampleGaps.allSatisfy { $0 >= 0 })
    let anchorTargets: [(name: String, time: Double, segment: String)] = [
      ("activation-1.00s", 1, "activating"),
      ("listening-2.50s", 2.5, "listening"),
      ("quiet-4.80s", 4.8, "quiet"),
      ("flattening-6.34s", 6.34, "flattening"),
      ("processing-7.10s", 7.1, "processing"),
      ("standby-9.00s", 9, "standby"),
    ]
    let anchorFramesDirectory = directory.appendingPathComponent("anchor-frames", isDirectory: true)
    try FileManager.default.createDirectory(at: anchorFramesDirectory, withIntermediateDirectories: true)
    let sampleTolerance = 0.1
    let anchorSamples: [[String: Any]] = try anchorTargets.map { target in
      let index = try #require(capturedTimes.indices.min {
        abs(capturedTimes[$0] - target.time) < abs(capturedTimes[$1] - target.time)
      })
      let sampledTime = capturedTimes[index]
      let timeError = abs(sampledTime - target.time)
      let segment = capturedSegments[index]
      #expect(timeError <= sampleTolerance)
      #expect(segment == target.segment)
      let imageName = "\(target.name).png"
      try FileManager.default.copyItem(
        at: sequenceDirectory.appendingPathComponent(String(format: "frame-%04d.png", index)),
        to: anchorFramesDirectory.appendingPathComponent(imageName)
      )
      return [
        "targetElapsedTime": target.time,
        "frameIndex": index,
        "sampledModelTime": sampledTime,
        "timeError": timeError,
        "segment": segment,
        "frame": "anchor-frames/\(imageName)",
      ]
    }
    let metadata: [String: Any] = [
      "os": ProcessInfo.processInfo.operatingSystemVersionString,
      "swift": "6.3.3",
      "panel": "offscreen nonactivating DictationCapsulePanel in the Swift test process",
      "capture": "NSHostingView cacheDisplay sampled against real system uptime at a 30 fps target; not a real-time desktop recording or the installed app",
      "captureBuffering": "Each sampled raw bitmap is copied into a distinct in-memory NSBitmapImageRep; PNG encoding and disk writes happen only after clock sampling ends.",
      "frames": 301,
      "targetFrameRate": 30,
      "playbackRate": model.snapshot.rate,
      "loops": model.snapshot.loops,
      "clockSampleDuration": capturedTimes.last! - capturedTimes.first!,
      "largestClockSampleGap": sampleGaps.max() ?? 0,
      "onTargetClockSamples": sampleGaps.filter { $0 <= 1.0 / 30 + 0.02 }.count + 1,
      "capturedModelTimes": capturedTimes,
      "capturedSegments": capturedSegments,
      "anchorSampleTolerance": sampleTolerance,
      "anchorSamples": anchorSamples,
      "logicalPanelSize": [liveHost.bounds.width, liveHost.bounds.height],
      "sourceIdentity": try FleckPillCaptureSupport.sourceIdentity(),
    ]
    let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
    try FleckPillCaptureSupport.write(metadataData, to: directory.appendingPathComponent("capture-metadata.json"))
  }
  private enum FleckPillLiveCompositionFixture: String, CaseIterable, Equatable {
    case standby
    case activating
    case listening
    case processing
    case saved
    case syntheticError = "synthetic-error"

    var sessionID: UUID? {
      switch self {
      case .standby: nil
      case .activating: UUID(uuidString: "00000000-0000-4000-8000-000000000011")!
      case .listening: UUID(uuidString: "00000000-0000-4000-8000-000000000012")!
      case .processing: UUID(uuidString: "00000000-0000-4000-8000-000000000013")!
      case .saved: UUID(uuidString: "00000000-0000-4000-8000-000000000014")!
      case .syntheticError: UUID(uuidString: "00000000-0000-4000-8000-000000000015")!
      }
    }

    var status: DictationCapsuleStatus {
      switch self {
      case .standby: .idle
      case .activating: .arming
      case .listening: .listening
      case .processing: .finalizing
      case .saved: .saved(destination: "Synthetic Inbox")
      case .syntheticError: .failed("Synthetic capture failure")
      }
    }

    var stage: DictationPipelineStage? {
      switch self {
      case .standby: nil
      case .activating, .listening, .processing, .syntheticError: .capture
      case .saved: .save
      }
    }

    var cleanup: DictationCleanupOutcome? { self == .saved ? .cleaned : nil }
    var failureStage: DictationPipelineStage? { self == .syntheticError ? .capture : nil }
    var failureKind: DictationCapsuleFailureKind? { self == .syntheticError ? .generic : nil }

    var expectedPillState: FleckPillLiveState {
      switch self {
      case .standby: .standby
      case .activating: .arming
      case .listening: .listening
      case .processing: .processing
      case .saved, .syntheticError: .hidden
      }
    }

    var contentKind: String {
      switch self {
      case .standby, .activating, .listening, .processing: "live-pill"
      case .saved: "saved-terminal-rail"
      case .syntheticError: "synthetic-error-surface"
      }
    }

    var surfaceProbeIdentifier: String {
      switch self {
      case .standby, .activating, .listening, .processing: "fleck-pill-canvas"
      case .saved: "fleck-terminal-text"
      case .syntheticError: "fleck-error-surface"
      }
    }

    var detailProbeIdentifier: String? {
      self == .syntheticError ? "fleck-error-message" : nil
    }

    var requiresRenderReceipt: Bool {
      self == .activating || self == .listening || self == .processing
    }

    var renderReadiness: String {
      switch self {
      case .standby: "canvas-probe-geometry-only; nil-session receipt lookup unavailable"
      case .activating, .listening, .processing: "current-session-generation-frame-receipt"
      case .saved, .syntheticError: "terminal-surface-probe; no live-pill receipt"
      }
    }
  }

  @MainActor
  private struct FleckPillLiveCompositionBackdrop {
    let name: String
    let color: NSColor
    let rgba: [Double]

    static let allCases = [
      FleckPillLiveCompositionBackdrop(
        name: "light",
        color: NSColor(calibratedWhite: 0.94, alpha: 1),
        rgba: [0.94, 0.94, 0.94, 1]
      ),
      FleckPillLiveCompositionBackdrop(
        name: "dark",
        color: NSColor(calibratedWhite: 0.08, alpha: 1),
        rgba: [0.08, 0.08, 0.08, 1]
      ),
    ]
  }

  private struct FleckPillLiveCompositionRect: Encodable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(_ rect: CGRect) {
      x = Double(rect.origin.x)
      y = Double(rect.origin.y)
      width = Double(rect.width)
      height = Double(rect.height)
    }
  }

  private struct FleckPillLiveCompositionFrame: Encodable {
    let expansion: Double
    let energy: Double
    let phase: Double
    let activationMix: Double
    let processingMix: Double
    let signalOpacity: Double
    let glint: Double
    let glintOpacity: Double

    init(_ frame: FleckPillArtworkFrame) {
      expansion = frame.expansion
      energy = frame.energy
      phase = frame.phase
      activationMix = frame.activationMix
      processingMix = frame.processingMix
      signalOpacity = frame.signalOpacity
      glint = frame.glint
      glintOpacity = frame.glintOpacity
    }
  }

  private struct FleckPillLiveCompositionDrawReceipt: Encodable {
    let sessionID: String
    let generation: UInt64
    let frame: FleckPillLiveCompositionFrame
  }

  private struct FleckPillLiveCompositionRecord: Encodable {
    let file: String
    let fixture: String
    let status: String
    let contentKind: String
    let pillModelState: String
    let pillVisible: Bool
    let backdrop: String
    let backdropRGBA: [Double]
    let hostPID: Int32
    let hostWindowID: Int
    let hostFrame: FleckPillLiveCompositionRect
    let surfaceRectCoordinateSpace: String
    let surfaceProbeIdentifier: String
    let surfaceRect: FleckPillLiveCompositionRect
    let detailProbeIdentifier: String?
    let detailRect: FleckPillLiveCompositionRect?
    let renderReadiness: String
    let renderReceipt: FleckPillLiveCompositionDrawReceipt?
    let backingScaleFactor: Double
    let pixelWidth: Int
    let pixelHeight: Int
  }

  private struct FleckPillLiveCompositionManifest: Encodable {
    let schemaVersion = 1
    let captureID = "fleck-pill-live-component-composition-v1"
    let captureType = "ON-SCREEN COMPONENT COMPOSITION"
    let selector = "FleckAppTests.FleckPillLiveComponentCompositionCapturesSixStatesOnOwnedBackdrops()"
    let sourceRoot: String
    let runDirectory: String
    let evidenceDirectory: String
    let outputDirectory: String
    let homeDirectory: String
    let temporaryDirectory: String
    let profile = "monochrome-dark-standard-transparency-reduce-motion"
    let captureCount: Int
    let captures: [FleckPillLiveCompositionRecord]
    let limitation = "Synthetic controller composition only; not full-app transport or active dictation proof."
  }

  private struct FleckPillLiveCompositionPaths {
    let sourceRoot: URL
    let runDirectory: URL
    let evidenceDirectory: URL
    let outputDirectory: URL
    let homeDirectory: URL
    let temporaryDirectory: URL
  }

  private struct FleckPillLiveCompositionArtifact {
    let data: Data
    let record: FleckPillLiveCompositionRecord
  }

  private enum FleckPillLiveCompositionCaptureSupport {
    static let manifestName = "capsule-live-composition.json"
    static let backdropNames = ["light", "dark"]

    static var enabled: Bool {
      let environment = ProcessInfo.processInfo.environment
      return environment["FLECK_NATIVE_CAPTURE_QA"] == "1"
        && environment["FLECK_EDITOR_EVIDENCE_DIR"]?.isEmpty == false
    }

    static var pngNames: [String] {
      FleckPillLiveCompositionFixture.allCases.flatMap { fixture in
        backdropNames.map { "\(fixture.rawValue)-\($0).png" }
      }
    }

    static func validatePaths() throws -> FleckPillLiveCompositionPaths {
      let environment = ProcessInfo.processInfo.environment
      try #require(environment["FLECK_NATIVE_CAPTURE_QA"] == "1")
      let evidencePath = try #require(environment["FLECK_EDITOR_EVIDENCE_DIR"])
      let homePath = try #require(environment["HOME"])
      let temporaryPath = try #require(environment["TMPDIR"])
      let evidence = URL(fileURLWithPath: evidencePath, isDirectory: true)
      let home = URL(fileURLWithPath: homePath, isDirectory: true)
      let temporary = URL(fileURLWithPath: temporaryPath, isDirectory: true)
      try #require(evidence.path == evidencePath && home.path == homePath && temporary.path == temporaryPath)
      let run = evidence.deletingLastPathComponent()
      try #require(evidence.lastPathComponent == "evidence")
      try #require(home.lastPathComponent == "home" && temporary.lastPathComponent == "tmp")
      try #require(home.deletingLastPathComponent() == run)
      try #require(temporary.deletingLastPathComponent() == run)
      for directory in [run, evidence, home, temporary] {
        try validatePrivateDirectory(directory)
      }

      let source = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .standardizedFileURL
      let sourceAttributes = try FileManager.default.attributesOfItem(atPath: source.path)
      try #require(sourceAttributes[.type] as? FileAttributeType == .typeDirectory)
      try #require(source.resolvingSymlinksInPath().standardizedFileURL.path == source.path)
      try #require(evidence.path != source.path && !evidence.path.hasPrefix(source.path + "/"))

      let output = evidence.appendingPathComponent("capsule-live-composition", isDirectory: true)
      try requireAbsent(output)
      return FleckPillLiveCompositionPaths(
        sourceRoot: source,
        runDirectory: run,
        evidenceDirectory: evidence,
        outputDirectory: output,
        homeDirectory: home,
        temporaryDirectory: temporary
      )
    }

    static func createOutputDirectory(_ paths: FleckPillLiveCompositionPaths) throws {
      try validatePrivateDirectory(paths.runDirectory)
      try validatePrivateDirectory(paths.evidenceDirectory)
      try validatePrivateDirectory(paths.homeDirectory)
      try validatePrivateDirectory(paths.temporaryDirectory)
      try requireAbsent(paths.outputDirectory)
      try FileManager.default.createDirectory(
        at: paths.outputDirectory,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )
      try validatePrivateDirectory(paths.outputDirectory)
    }

    static func write(_ data: Data, named name: String, to paths: FleckPillLiveCompositionPaths) throws {
      try #require(pngNames.contains(name) || name == manifestName)
      try validatePrivateDirectory(paths.outputDirectory)
      let destination = paths.outputDirectory.appendingPathComponent(name)
      try requireAbsent(destination)
      try data.write(to: destination, options: .withoutOverwriting)
    }

    @MainActor
    static func capture(
      _ fixture: FleckPillLiveCompositionFixture,
      backdrop: FleckPillLiveCompositionBackdrop
    ) async throws -> FleckPillLiveCompositionArtifact {
      let theme = FleckThemeSnapshot.resolve(
        colorTheme: .monochrome,
        mode: .dark,
        systemAppearance: .dark,
        reduceTransparency: false,
        increasedContrast: false
      )
      let panel = DictationCapsulePanel()
      panel.appearance = NSAppearance(named: .darkAqua)
      let controller = DictationCapsuleController(
        panel: panel,
        monotonicNow: { 50 },
        automaticallyAdvancesLivePill: false,
        reduceMotionProvider: { true },
        theme: theme,
        markLoader: { nil },
        announcementPoster: { _, _ in }
      )
      controller.setReduceMotionOverrideForTesting(true)
      controller.setPanelVisibilitySuppressedForTesting(true)
      controller.setAccessibilityEnvironmentOverridesForTesting(
        reduceTransparency: false,
        increasedContrast: false
      )
      controller.configureInteraction(
        onPrimaryClick: {}, onStop: {}, onCancel: {}, onOpenFleck: {},
        onOpenHistory: {}, onOpenSettings: {}, onDismiss: {}, onRecovery: {},
        onErrorRecovery: { _ in }
      )
      try render(fixture, on: controller)
      try #require(controller.currentContext.status == fixture.status)
      try #require(controller.fleckPillModel.state == fixture.expectedPillState)
      try #require(controller.fleckPillModel.isVisible == (fixture.expectedPillState != .hidden))
      try #require(!controller.panel.isVisible)

      let content = try #require(controller.panel.contentView)
      let size = controller.panel.frame.size
      let screen = try #require(NSScreen.main)
      let frame = CGRect(
        x: screen.visibleFrame.midX - size.width / 2,
        y: screen.visibleFrame.midY - size.height / 2,
        width: size.width,
        height: size.height
      )
      try #require(size.width > 0 && size.height > 0 && screen.visibleFrame.contains(frame))
      let host = NSView(frame: CGRect(origin: .zero, size: size))
      host.wantsLayer = true
      host.layer?.backgroundColor = backdrop.color.cgColor
      host.layer?.isOpaque = true
      try #require(backdrop.color.alphaComponent == 1 && host.layer?.backgroundColor?.alpha == 1)
      controller.panel.orderOut(nil)
      controller.panel.contentView = nil
      content.frame = host.bounds
      content.autoresizingMask = [.width, .height]
      host.addSubview(content)

      var hostWindow: NSWindow?
      defer {
        hostWindow?.orderOut(nil)
        controller.dismiss()
        hostWindow?.contentView = nil
        hostWindow?.close()
      }
      let window = NSWindow(
        contentRect: frame,
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
      )
      hostWindow = window
      window.isReleasedWhenClosed = false
      window.level = .floating
      window.appearance = NSAppearance(named: .darkAqua)
      window.backgroundColor = backdrop.color
      window.isOpaque = true
      window.hasShadow = false
      window.contentView = host
      window.orderFrontRegardless()
      try #require(window.isVisible && window.windowNumber > 0)
      try #require(window.screen?.visibleFrame.contains(window.frame) == true)
      try #require(host.subviews.count == 1 && host.subviews.first === content)

      await FleckPillCaptureSupport.settle(host)
      host.displayIfNeeded()
      content.displayIfNeeded()
      try #require(controller.currentContext.status == fixture.status)
      try #require(controller.fleckPillModel.state == fixture.expectedPillState)
      try #require(controller.fleckPillModel.isVisible == (fixture.expectedPillState != .hidden))
      try #require(controller.presentationModel.context.status == fixture.status)
      try #require((controller.errorPresentationModel.presentation != nil) == (fixture == .syntheticError))
      try #require(window.isVisible && window.windowNumber > 0)
      let surfaceRect = try Self.probeRect(
        fixture.surfaceProbeIdentifier,
        in: host,
        window: window
      )
      let detailRect = try fixture.detailProbeIdentifier.map {
        try Self.probeRect($0, in: host, window: window)
      }
      if let detailRect { try #require(surfaceRect.contains(detailRect)) }
      let renderSnapshot: FleckPillRenderSnapshot?
      if fixture.requiresRenderReceipt {
        renderSnapshot = try await Self.waitForCurrentRenderReceipt(
          controller,
          sessionID: try #require(fixture.sessionID),
          host: host,
          content: content
        )
      } else {
        renderSnapshot = nil
      }

      let scale = window.backingScaleFactor
      try #require(scale.isFinite && scale > 0)
      let image = try await hostedNativeWindowCapture(window)
      try #require(image.pixelsWide == Int(window.frame.width * scale))
      try #require(image.pixelsHigh == Int(window.frame.height * scale))
      let data = try #require(image.representation(using: .png, properties: [:]))
      let filename = "\(fixture.rawValue)-\(backdrop.name).png"
      let visible = controller.fleckPillModel.isVisible
      if let renderSnapshot {
        let sessionID = try #require(fixture.sessionID)
        let currentSnapshotValue = controller.fleckPillModel.renderReceipt.snapshot(for: sessionID)
        let currentSnapshot = try #require(currentSnapshotValue)
        try #require(currentSnapshot == renderSnapshot)
        try #require(
          currentSnapshot.generation == controller.fleckPillModel.renderGeneration
            && controller.fleckPillModel.sessionID == currentSnapshot.sessionID
            && currentSnapshot.frame == controller.fleckPillModel.frame
        )
      }
      let renderReceipt: FleckPillLiveCompositionDrawReceipt?
      if let renderSnapshot {
        renderReceipt = FleckPillLiveCompositionDrawReceipt(
          sessionID: try #require(fixture.sessionID).uuidString,
          generation: renderSnapshot.generation,
          frame: FleckPillLiveCompositionFrame(renderSnapshot.frame)
        )
      } else {
        renderReceipt = nil
      }
      let record = FleckPillLiveCompositionRecord(
        file: filename,
        fixture: fixture.rawValue,
        status: String(describing: controller.currentContext.status),
        contentKind: fixture.contentKind,
        pillModelState: String(describing: controller.fleckPillModel.state),
        pillVisible: visible,
        backdrop: backdrop.name,
        backdropRGBA: backdrop.rgba,
        hostPID: ProcessInfo.processInfo.processIdentifier,
        hostWindowID: window.windowNumber,
        hostFrame: FleckPillLiveCompositionRect(window.frame),
        surfaceRectCoordinateSpace: "owned-window-content-host bounds",
        surfaceProbeIdentifier: fixture.surfaceProbeIdentifier,
        surfaceRect: FleckPillLiveCompositionRect(surfaceRect),
        detailProbeIdentifier: fixture.detailProbeIdentifier,
        detailRect: detailRect.map(FleckPillLiveCompositionRect.init),
        renderReadiness: fixture.renderReadiness,
        renderReceipt: renderReceipt,
        backingScaleFactor: Double(scale),
        pixelWidth: image.pixelsWide,
        pixelHeight: image.pixelsHigh
      )
      return FleckPillLiveCompositionArtifact(data: data, record: record)
    }

    @MainActor
    private static func waitForCurrentRenderReceipt(
      _ controller: DictationCapsuleController,
      sessionID: UUID,
      host: NSView,
      content: NSView
    ) async throws -> FleckPillRenderSnapshot {
      let clock = ContinuousClock()
      let deadline = clock.now.advanced(by: .seconds(2))
      var matchingSnapshot: FleckPillRenderSnapshot?
      while matchingSnapshot == nil && clock.now < deadline {
        host.layoutSubtreeIfNeeded()
        content.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        content.displayIfNeeded()
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
      return try #require(matchingSnapshot)
    }

    @MainActor
    private static func probeRect(
      _ identifier: String,
      in host: NSView,
      window: NSWindow
    ) throws -> CGRect {
      var matches: [NSView] = []
      func find(in view: NSView) {
        if view.identifier?.rawValue == identifier { matches.append(view) }
        for subview in view.subviews { find(in: subview) }
      }
      find(in: host)
      try #require(matches.count == 1)
      let probe = try #require(matches.first)
      try #require(probe.window === window && !probe.isHiddenOrHasHiddenAncestor)
      let rect = host.convert(probe.bounds, from: probe)
      try #require(
        rect.minX.isFinite && rect.minY.isFinite
          && rect.width.isFinite && rect.height.isFinite
          && rect.maxX.isFinite && rect.maxY.isFinite
      )
      try #require(rect.width > 0 && rect.height > 0 && host.bounds.contains(rect))
      return rect
    }

    @MainActor
    private static func render(
      _ fixture: FleckPillLiveCompositionFixture,
      on controller: DictationCapsuleController
    ) throws {
      guard let sessionID = fixture.sessionID else {
        controller.presentIdle(
          dock: .bottom,
          accessibilityLabel: "Synthetic QA",
          onOpenFleck: {},
          onDockChanged: { _ in }
        )
        return
      }
      let destination = fixture == .saved
        ? DictationDestination(noteID: sessionID, title: "Synthetic Inbox")
        : nil
      let stage = try #require(fixture.stage)
      let context = DictationCapsuleContext(
        status: fixture.status,
        sessionID: sessionID,
        trigger: .hold,
        mode: .smartCapture,
        pipelineStage: stage,
        cleanupOutcome: fixture.cleanup,
        failureStage: fixture.failureStage,
        failureKind: fixture.failureKind
      )
      let coordinatorContext = DictationCoordinatorContext(
        sessionID: sessionID,
        mode: .smartCapture,
        destination: destination,
        pipelineStage: stage,
        cleanupOutcome: fixture.cleanup,
        failureStage: fixture.failureStage
      )
      let phase: DictationPhase
      let terminal: DictationTerminalOutcome?
      switch fixture {
      case .standby:
        return
      case .activating:
        phase = .arming
        terminal = nil
      case .listening:
        phase = .listening(mode: .smartCapture, engine: .standard)
        terminal = nil
      case .processing:
        phase = .finalizing
        terminal = nil
      case .saved:
        phase = .saved(try #require(destination))
        terminal = .saved(mode: .smartCapture, cleanup: .cleaned, destination: destination)
      case .syntheticError:
        phase = .failed("Synthetic capture failure")
        terminal = .failed("Synthetic capture failure")
      }
      controller.render(
        context,
        coordinatorEvent: DictationCoordinatorEvent(
          phase: phase,
          terminal: terminal,
          context: coordinatorContext
        )
      )
    }

    private static func validatePrivateDirectory(_ url: URL) throws {
      let path = url.path
      try #require(path.hasPrefix("/"))
      try #require(url.standardizedFileURL.path == path)
      try #require(url.resolvingSymlinksInPath().standardizedFileURL.path == path)
      let attributes = try FileManager.default.attributesOfItem(atPath: path)
      try #require(attributes[.type] as? FileAttributeType == .typeDirectory)
      try #require((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
      try #require(attributes[.ownerAccountName] as? String == NSUserName())
    }

    private static func requireAbsent(_ url: URL) throws {
      try #require(!FileManager.default.fileExists(atPath: url.path))
      try #require((try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) == nil)
    }

  }

  @Test(
    .timeLimit(.minutes(5)),
    .enabled(
      if: FleckPillLiveCompositionCaptureSupport.enabled,
      "Requires FLECK_NATIVE_CAPTURE_QA=1 and explicit FLECK_EDITOR_EVIDENCE_DIR"
    )
  )
  @MainActor
  func FleckPillLiveComponentCompositionCapturesSixStatesOnOwnedBackdrops() async throws {
    try #require(FleckPillLiveCompositionFixture.allCases.count == 6)
    try #require(FleckPillLiveCompositionCaptureSupport.pngNames.count == 12)
    let paths = try FleckPillLiveCompositionCaptureSupport.validatePaths()
    try #require(CGPreflightScreenCaptureAccess())
    try FleckPillLiveCompositionCaptureSupport.createOutputDirectory(paths)

    var artifacts: [FleckPillLiveCompositionArtifact] = []
    for fixture in FleckPillLiveCompositionFixture.allCases {
      for backdrop in FleckPillLiveCompositionBackdrop.allCases {
        artifacts.append(
          try await FleckPillLiveCompositionCaptureSupport.capture(fixture, backdrop: backdrop)
        )
      }
    }
    try #require(artifacts.count == 12)

    let manifest = FleckPillLiveCompositionManifest(
      sourceRoot: paths.sourceRoot.path,
      runDirectory: paths.runDirectory.path,
      evidenceDirectory: paths.evidenceDirectory.path,
      outputDirectory: paths.outputDirectory.path,
      homeDirectory: paths.homeDirectory.path,
      temporaryDirectory: paths.temporaryDirectory.path,
      captureCount: artifacts.count,
      captures: artifacts.map(\.record)
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    for artifact in artifacts {
      try FleckPillLiveCompositionCaptureSupport.write(
        artifact.data,
        named: artifact.record.file,
        to: paths
      )
    }
    try FleckPillLiveCompositionCaptureSupport.write(
      try encoder.encode(manifest),
      named: FleckPillLiveCompositionCaptureSupport.manifestName,
      to: paths
    )
    let expectedFiles = (
      FleckPillLiveCompositionCaptureSupport.pngNames
        + [FleckPillLiveCompositionCaptureSupport.manifestName]
    ).sorted()
    let actualFiles = try FileManager.default.contentsOfDirectory(
      atPath: paths.outputDirectory.path
    ).sorted()
    try #require(actualFiles == expectedFiles)
  }
#endif
