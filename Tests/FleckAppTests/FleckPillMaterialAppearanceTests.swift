#if os(macOS) && DEBUG
import AppKit
import CryptoKit
import Darwin
import Foundation
import FleckCore
import SwiftUI
import Testing

@testable import FleckApp

@Test @MainActor
func FleckPillMaterialRemainsDarkAcrossEveryPoseAndAccessibilityMode() throws {
  func darkShellCoverage(
    frame: FleckPillArtworkFrame,
    layers: FleckPillCanvasLayers,
    colors: FleckRailColors
  ) throws -> Double {
    let shell = FleckPillGeometry.shell(expansion: frame.expansion)
    var shellPath = Path()
    for command in shell.fill.commands {
      switch command {
      case .move(let point):
        shellPath.move(to: CGPoint(x: point.x, y: point.y))
      case .line(let point):
        shellPath.addLine(to: CGPoint(x: point.x, y: point.y))
      case .cubic(let first, let second, let end):
        shellPath.addCurve(
          to: CGPoint(x: end.x, y: end.y),
          control1: CGPoint(x: first.x, y: first.y),
          control2: CGPoint(x: second.x, y: second.y)
        )
      case .close:
        shellPath.closeSubpath()
      }
    }
    let scale = CGFloat(FleckPillGeometry.artworkScale)
    let transform = CGAffineTransform(
      a: scale * CGFloat(shell.shellTransform.scaleX),
      b: 0,
      c: 0,
      d: scale * CGFloat(shell.shellTransform.scaleY),
      tx: scale * CGFloat(8 + shell.shellTransform.translateX),
      ty: scale * CGFloat(12 + shell.shellTransform.translateY)
    )
    let transformedShellPath = shellPath.applying(transform)
    let center = shell.shellTransform.applying(to: FleckPillPoint(x: 112, y: 20))
    let centerX = scale * CGFloat(8 + center.x)
    let renderer = ImageRenderer(content: ZStack {
      Color.white
      FleckPillCanvas(frame: frame, layers: layers, colors: colors)
    }.frame(width: 180, height: 39))
    renderer.scale = 1
    renderer.proposedSize = ProposedViewSize(width: 180, height: 39)
    renderer.isOpaque = true
    renderer.colorMode = .nonLinear
    let image = try #require(renderer.cgImage)
    #expect(image.width == 180)
    #expect(image.height == 39)
    let bitmap = NSBitmapImageRep(cgImage: image)
    var darkPixels = 0
    var interiorPixels = 0
    for y in 0..<bitmap.pixelsHigh {
      for x in 0..<bitmap.pixelsWide {
        guard abs(CGFloat(x) + 0.5 - centerX) <= 4 else { continue }
        guard transformedShellPath.contains(
          CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
        ) else { continue }
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
        interiorPixels += 1
        if color.redComponent < 0.25 && color.greenComponent < 0.25 && color.blueComponent < 0.25 {
          darkPixels += 1
        }
      }
    }
    guard interiorPixels > 0 else { return 0 }
    return Double(darkPixels) / Double(interiorPixels)
  }

  for family in FleckColorTheme.allCases {
    for (mode, appearance) in [(AppTheme.light, FleckThemeAppearance.light), (.dark, .dark)] {
      for reduceTransparency in [false, true] {
        for increasedContrast in [false, true] {
          let theme = FleckThemeSnapshot.resolve(
            colorTheme: family,
            mode: mode,
            systemAppearance: appearance,
            reduceTransparency: reduceTransparency,
            increasedContrast: increasedContrast
          )
          let colors = FleckRailColors(theme: theme)
          let layers = FleckPillCanvasLayers(
            rim: false,
            shoulders: !reduceTransparency,
            signal: false,
            halo: !reduceTransparency && !increasedContrast
          )
          for pose in FleckPillPose.allCases {
            let motionFrame = try FleckPillGeometry.pose(named: pose.rawValue)
            let coverage = try darkShellCoverage(
              frame: motionFrame.artworkFrame,
              layers: layers,
              colors: colors
            )
            #expect(coverage >= 0.8)
          }
        }
      }
    }
  }
}

private struct FleckCapsuleErrorTerminalFixture {
  let name: String
  let context: DictationCapsuleContext
  let action: DictationCapsuleAction?
  let expectedErrorKind: FleckErrorKind?
}

@MainActor
private final class FleckCapsuleAccessibilityEnvironmentEvidence {
  var reduceTransparency: Bool?
  var colorSchemeContrast: ColorSchemeContrast?
}

private struct FleckCapsuleCaptureRect: Encodable {
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

private struct FleckCapsuleCaptureGeometry: Encodable {
  let width: Int
  let height: Int
  let hostBounds: FleckCapsuleCaptureRect
  let messageFrame: FleckCapsuleCaptureRect?
  let actionLabelFrame: FleckCapsuleCaptureRect?
  let terminalTextFrame: FleckCapsuleCaptureRect?
  let messageReadablePixels: Int?
  let actionLabelReadablePixels: Int?
  let terminalTextReadablePixels: Int?
}

private struct FleckCapsuleCaptureRecord: Encodable {
  let file: String
  let themeFamily: String
  let appearance: String
  let observedReduceTransparency: Bool
  let observedColorSchemeContrast: String
  let reduceTransparency: Bool
  let increasedContrast: Bool
  let fixture: String
  let status: String
  let expectedErrorKind: String?
  let actualErrorKind: String?
  let actionTitle: String?
  let contentOpacity: Double?
  let geometry: FleckCapsuleCaptureGeometry
}

private struct FleckCapsuleHostProfile: Encodable {
  let enhancedCandidateUnset: Bool
  let capsuleNativeQA: String
  let nativeCaptureQA: String
  let livePanel: String
  let sequence: String
  let pillCaptureDirectory: String
  let home: String
  let tmpDirectory: String
  let processPID: Int32
}

private struct FleckCapsuleHostBinding: Encodable {
  let validated: Bool
  let stage: String
  let nonce: String
  let ownPID: Int32
  let configSHA256: String
  let pidRecordSHA256: String
}

private struct FleckCapsuleCaptureManifest: Encodable {
  let schemaVersion = 2
  let selector = "FleckCapsuleErrorAndTerminalThemesRenderWithInjectedAccessibility"
  let runID: String
  let hostProfile: FleckCapsuleHostProfile
  let hostBinding: FleckCapsuleHostBinding
  let effectiveProfileSource = "capsule-local-debug-overrides-with-native-environment-fallback"
  let captureControl: String
  let captureCount: Int
  let captures: [FleckCapsuleCaptureRecord]
}

private enum FleckCapsuleErrorTerminalCaptureSupport {
  private static var candidateEvidenceRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("evidence", isDirectory: true)
  }

  static var outputDirectory: URL? {
    checkedOutputDirectory(environment: ProcessInfo.processInfo.environment)
  }

  static var enabled: Bool { outputDirectory != nil }

  private static func checkedOutputDirectory(
    environment: [String: String]
  ) -> URL? {
    guard environment["FLECK_CAPSULE_NATIVE_QA"] == "1",
      let path = environment["FLECK_PILL_CAPTURE_DIRECTORY"],
      path.hasPrefix("/"),
      !path.split(separator: "/").contains("..")
    else { return nil }
    let candidateRootURL = candidateEvidenceRoot.standardizedFileURL
    let candidateRoot = resolvedPath(candidateRootURL)
    guard candidateRoot == candidateRootURL.path else { return nil }
    let basePath = resolvedPath(URL(fileURLWithPath: path, isDirectory: true))
    guard isWithinRoot(basePath, root: candidateRoot) else { return nil }
    let outputPath = resolvedPath(
      URL(fileURLWithPath: basePath, isDirectory: true)
        .appendingPathComponent("native-root-qa", isDirectory: true)
    )
    guard isWithinRoot(outputPath, root: candidateRoot) else { return nil }
    return URL(fileURLWithPath: outputPath, isDirectory: true)
  }

  private static func isWithinRoot(_ path: String, root: String) -> Bool {
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
}

@MainActor
private func fleckCapsuleFrameProbe(_ identifier: String, in host: NSView) -> CGRect? {
  @MainActor func find(in view: NSView) -> NSView? {
    if view.identifier?.rawValue == identifier { return view }
    for subview in view.subviews {
      if let match = find(in: subview) { return match }
    }
    return nil
  }

  guard let probe = find(in: host) else { return nil }
  return host.convert(probe.bounds, from: probe)
}

private func fleckCapsuleBitmapTopOffset(
  frame: CGRect,
  hostBounds: CGRect,
  isFlipped: Bool
) -> CGFloat {
  isFlipped ? frame.minY - hostBounds.minY : hostBounds.maxY - frame.maxY
}

@MainActor
private func fleckCapsuleReadableContentPixels(
  in frame: CGRect,
  image: NSBitmapImageRep,
  hostBounds: CGRect,
  hostIsFlipped: Bool
) -> Int {
  guard hostBounds.width > 0, hostBounds.height > 0,
    frame.width > 0, frame.height > 0,
    hostBounds.contains(frame)
  else { return 0 }
  let scaleX = CGFloat(image.pixelsWide) / hostBounds.width
  let scaleY = CGFloat(image.pixelsHigh) / hostBounds.height
  let imageBounds = CGRect(x: 0, y: 0, width: image.pixelsWide, height: image.pixelsHigh)
  let top = fleckCapsuleBitmapTopOffset(
    frame: frame,
    hostBounds: hostBounds,
    isFlipped: hostIsFlipped
  )
  let pixelFrame = CGRect(
    x: (frame.minX - hostBounds.minX) * scaleX,
    y: top * scaleY,
    width: frame.width * scaleX,
    height: frame.height * scaleY
  ).integral.intersection(imageBounds)
  let minX = max(0, Int(pixelFrame.minX))
  let maxX = min(image.pixelsWide, Int(pixelFrame.maxX))
  let minY = max(0, Int(pixelFrame.minY))
  let maxY = min(image.pixelsHigh, Int(pixelFrame.maxY))
  guard minX < maxX, minY < maxY else { return 0 }

  @MainActor func luminance(x: Int, y: Int) -> Double? {
    guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
      color.alphaComponent >= 0.9
    else { return nil }
    return 0.2126 * Double(color.redComponent)
      + 0.7152 * Double(color.greenComponent)
      + 0.0722 * Double(color.blueComponent)
  }

  let paddingX = max(2, Int(scaleX.rounded(.up)))
  let paddingY = max(2, Int(scaleY.rounded(.up)))
  var backgroundLuminance: [Double] = []
  for y in max(0, minY - paddingY)..<min(image.pixelsHigh, maxY + paddingY) {
    for x in max(0, minX - paddingX)..<min(image.pixelsWide, maxX + paddingX) {
      guard x < minX || x >= maxX || y < minY || y >= maxY,
        let value = luminance(x: x, y: y)
      else { continue }
      backgroundLuminance.append(value)
    }
  }
  guard !backgroundLuminance.isEmpty else { return 0 }
  backgroundLuminance.sort()
  let background = backgroundLuminance[backgroundLuminance.count / 2]
  var readablePixels = 0
  for y in minY..<maxY {
    for x in minX..<maxX {
      if let value = luminance(x: x, y: y), abs(value - background) >= 0.18 {
        readablePixels += 1
      }
    }
  }
  return readablePixels
}

@Test
func FleckCapsuleBitmapRowsRespectNativeHostOrientation() {
  let hostBounds = CGRect(x: 3, y: 11, width: 100, height: 80)
  let frame = CGRect(x: 17, y: 21, width: 20, height: 10)
  let flippedTop = fleckCapsuleBitmapTopOffset(
    frame: frame,
    hostBounds: hostBounds,
    isFlipped: true
  )
  let nonFlippedTop = fleckCapsuleBitmapTopOffset(
    frame: frame,
    hostBounds: hostBounds,
    isFlipped: false
  )
  let incorrectDirectMinY = frame.minY - hostBounds.minY
  #expect(flippedTop == 10)
  #expect(nonFlippedTop == 60)
  #expect(nonFlippedTop != incorrectDirectMinY)
}

@MainActor
private func captureFleckCapsuleErrorTerminalBitmap(
  _ fixture: FleckCapsuleErrorTerminalFixture,
  controller: DictationCapsuleController,
  size: CGSize,
  destination: URL
) throws -> FleckCapsuleCaptureGeometry {
  try #require(!controller.panel.isVisible)
  let expectedContext = fixture.context.presentationContext()
  let expectedAction = expectedContext.status == .idle ? nil : fixture.action
  try #require(controller.currentContext == expectedContext)
  try #require(controller.presentationModel.action == expectedAction)
  let host = try #require(controller.panel.contentView)
  try #require(!host.isHidden)
  host.layoutSubtreeIfNeeded()
  host.displayIfNeeded()
  try #require(abs(controller.panel.frame.width - size.width) < 1)
  try #require(abs(controller.panel.frame.height - size.height) < 1)
  try #require(abs(host.bounds.width - size.width) < 1)
  try #require(abs(host.bounds.height - size.height) < 1)
  try #require(host.bounds.width > 0)
  try #require(host.bounds.height > 0)

  let errorPresentation = controller.errorPresentationModel.presentation
  try #require(errorPresentation?.kind == fixture.expectedErrorKind)
  var messageFrame: CGRect?
  var actionLabelFrame: CGRect?
  let terminalTextFrame: CGRect? = nil
  if let expectedErrorKind = fixture.expectedErrorKind {
    let presentation = try #require(errorPresentation)
    try #require(presentation.kind == expectedErrorKind)
    try #require(presentation.contentOpacity >= 0.98)
    let frame = try #require(fleckCapsuleFrameProbe("fleck-error-message", in: host))
    try #require(frame.width > 0 && frame.height > 0 && host.bounds.contains(frame))
    messageFrame = frame
    if presentation.actionTitle != nil {
      let actionFrame = try #require(fleckCapsuleFrameProbe("fleck-error-action-label", in: host))
      try #require(
        actionFrame.width > 0 && actionFrame.height > 0 && host.bounds.contains(actionFrame)
      )
      actionLabelFrame = actionFrame
    }
  } else {
    try #require(errorPresentation == nil)
    try #require(controller.currentContext.status == .idle)
    try #require(controller.fleckPillModel.state == .standby)
    try #require(controller.presentationModel.action == nil)
    try #require(controller.currentChooser == nil)
    try #require(!controller.panel.allowsActions)
    try #require(fleckCapsuleFrameProbe("fleck-terminal-text", in: host) == nil)
    try #require(fleckCapsuleFrameProbe("fleck-error-message", in: host) == nil)
  }

  let bounds = host.bounds
  let image = try #require(NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: max(1, Int(bounds.width.rounded(.up))),
    pixelsHigh: max(1, Int(bounds.height.rounded(.up))),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  ))
  image.size = bounds.size
  host.cacheDisplay(in: bounds, to: image)
  try #require(image.pixelsWide > 0)
  try #require(image.pixelsHigh > 0)

  let messageReadablePixels = try messageFrame.map { frame in
    let pixels = fleckCapsuleReadableContentPixels(
      in: frame,
      image: image,
      hostBounds: bounds,
      hostIsFlipped: host.isFlipped
    )
    try #require(pixels >= 4)
    return pixels
  }
  let actionLabelReadablePixels = try actionLabelFrame.map { frame in
    let pixels = fleckCapsuleReadableContentPixels(
      in: frame,
      image: image,
      hostBounds: bounds,
      hostIsFlipped: host.isFlipped
    )
    try #require(pixels >= 4)
    return pixels
  }
  let terminalTextReadablePixels = try terminalTextFrame.map { frame in
    let pixels = fleckCapsuleReadableContentPixels(
      in: frame,
      image: image,
      hostBounds: bounds,
      hostIsFlipped: host.isFlipped
    )
    try #require(pixels >= 4)
    return pixels
  }
  try #require(!controller.panel.isVisible)
  let png = try #require(image.representation(using: .png, properties: [:]))
  try png.write(to: destination, options: .atomic)
  return FleckCapsuleCaptureGeometry(
    width: image.pixelsWide,
    height: image.pixelsHigh,
    hostBounds: FleckCapsuleCaptureRect(bounds),
    messageFrame: messageFrame.map(FleckCapsuleCaptureRect.init),
    actionLabelFrame: actionLabelFrame.map(FleckCapsuleCaptureRect.init),
    terminalTextFrame: terminalTextFrame.map(FleckCapsuleCaptureRect.init),
    messageReadablePixels: messageReadablePixels,
    actionLabelReadablePixels: actionLabelReadablePixels,
    terminalTextReadablePixels: terminalTextReadablePixels
  )
}

@Test(.enabled(
  if: FleckCapsuleErrorTerminalCaptureSupport.enabled,
  "Requires FLECK_CAPSULE_NATIVE_QA=1 and scratch FLECK_PILL_CAPTURE_DIRECTORY; no aliases are accepted"
))
@MainActor
func FleckCapsuleErrorAndTerminalThemesRenderWithInjectedAccessibility() async throws {
  let outputDirectory = try #require(FleckCapsuleErrorTerminalCaptureSupport.outputDirectory)
  let enhancedCandidateUnset = Darwin.getenv("FLECK_ENHANCED_CANDIDATE") == nil
  try #require(enhancedCandidateUnset)
  let capsuleNativeQAValue = Darwin.getenv("FLECK_CAPSULE_NATIVE_QA")
  let capsuleNativeQA = String(cString: try #require(capsuleNativeQAValue))
  try #require(capsuleNativeQA == "1")
  let nativeCaptureQAValue = Darwin.getenv("FLECK_NATIVE_CAPTURE_QA")
  let nativeCaptureQA = String(cString: try #require(nativeCaptureQAValue))
  try #require(nativeCaptureQA == "0")
  let livePanelValue = Darwin.getenv("FLECK_PILL_CAPTURE_LIVE_PANEL")
  let livePanel = String(cString: try #require(livePanelValue))
  try #require(livePanel == "0")
  let sequenceValue = Darwin.getenv("FLECK_PILL_CAPTURE_SEQUENCE")
  let sequence = String(cString: try #require(sequenceValue))
  try #require(sequence == "0")
  let pillCaptureDirectoryValue = Darwin.getenv("FLECK_PILL_CAPTURE_DIRECTORY")
  let pillCaptureDirectory = String(
    cString: try #require(pillCaptureDirectoryValue)
  )
  let candidateRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .standardizedFileURL
  let expectedPillDirectory = candidateRoot
    .appendingPathComponent("evidence", isDirectory: true)
    .appendingPathComponent("native-capsule-198-default7-hidden-a11y-v1", isDirectory: true)
    .appendingPathComponent("pill", isDirectory: true)
    .standardizedFileURL
  try #require(pillCaptureDirectory == expectedPillDirectory.path)
  try #require(
    outputDirectory.standardizedFileURL.path
      == expectedPillDirectory.appendingPathComponent("native-root-qa", isDirectory: true)
        .standardizedFileURL.path
  )
  let homeValue = Darwin.getenv("HOME")
  let home = String(cString: try #require(homeValue))
  let tmpDirectoryValue = Darwin.getenv("TMPDIR")
  let tmpDirectory = String(cString: try #require(tmpDirectoryValue))
  let homeURL = URL(fileURLWithPath: home).standardizedFileURL
  let tmpDirectoryURL = URL(fileURLWithPath: tmpDirectory).standardizedFileURL
  try #require(
    home.hasPrefix("/") && homeURL.resolvingSymlinksInPath().standardizedFileURL.path == home
  )
  try #require(
    tmpDirectory.hasPrefix("/")
      && tmpDirectoryURL.resolvingSymlinksInPath().standardizedFileURL.path == tmpDirectory
  )
  let homeRunDirectory = homeURL.deletingLastPathComponent()
  let runComponent = homeRunDirectory.lastPathComponent
  try #require(
    runComponent.range(of: "^pr62-native-[0-9a-f]{32}$", options: .regularExpression) != nil
  )
  let expectedRunDirectory = candidateRoot
    .appendingPathComponent("hidden-capsule198-default7-a11y-v1-control", isDirectory: true)
    .appendingPathComponent("runs", isDirectory: true)
    .appendingPathComponent(runComponent, isDirectory: true)
    .standardizedFileURL
  try #require(homeRunDirectory.standardizedFileURL.path == expectedRunDirectory.path)
  try #require(homeURL.lastPathComponent == "home")
  try #require(
    homeURL.path == expectedRunDirectory.appendingPathComponent("home", isDirectory: true)
      .standardizedFileURL.path
  )
  try #require(
    tmpDirectoryURL.path == expectedRunDirectory.appendingPathComponent("tmp", isDirectory: true)
      .standardizedFileURL.path
  )
  let hostProfile = FleckCapsuleHostProfile(
    enhancedCandidateUnset: enhancedCandidateUnset,
    capsuleNativeQA: capsuleNativeQA,
    nativeCaptureQA: nativeCaptureQA,
    livePanel: livePanel,
    sequence: sequence,
    pillCaptureDirectory: pillCaptureDirectory,
    home: home,
    tmpDirectory: tmpDirectory,
    processPID: Darwin.getpid()
  )
  let processArguments = ProcessInfo.processInfo.arguments
  try #require(processArguments.count >= 2)
  let hostConfigurationFlagIndex = processArguments.count - 2
  let hasHostConfigurationFlag =
    processArguments[hostConfigurationFlagIndex] == "--host-config"
  try #require(hasHostConfigurationFlag)
  let hostConfigurationPath = processArguments[hostConfigurationFlagIndex + 1]
  let hostConfigurationURL = URL(fileURLWithPath: hostConfigurationPath).standardizedFileURL
  let hostConfigurationURLMatchesArgument =
    hostConfigurationPath.hasPrefix("/")
      && hostConfigurationURL.path == hostConfigurationPath
  try #require(hostConfigurationURLMatchesArgument)

  let hostStateDirectoryName = hostConfigurationURL.deletingLastPathComponent()
    .deletingLastPathComponent().lastPathComponent
  let hostStateDirectoryNameIsBounded =
    hostStateDirectoryName.range(
      of: #"^fleck-appkit-test-host\.[A-Za-z0-9]{6}$"#,
      options: .regularExpression
    ) != nil
  try #require(hostStateDirectoryNameIsBounded)
  let hostStageDirectoryURL = tmpDirectoryURL
    .appendingPathComponent(hostStateDirectoryName, isDirectory: true)
    .appendingPathComponent("run", isDirectory: true)
    .standardizedFileURL
  let expectedHostConfigurationURL = hostStageDirectoryURL
    .appendingPathComponent("host-configuration")
    .standardizedFileURL
  let hostConfigurationPathIsBound =
    hostConfigurationURL.path == expectedHostConfigurationURL.path
      && hostConfigurationURL.deletingLastPathComponent().lastPathComponent == "run"
  try #require(hostConfigurationPathIsBound)

  func sameMetadata(_ first: stat, _ second: stat) -> Bool {
    first.st_dev == second.st_dev
      && first.st_ino == second.st_ino
      && first.st_mode == second.st_mode
      && first.st_uid == second.st_uid
      && first.st_gid == second.st_gid
      && first.st_nlink == second.st_nlink
      && first.st_size == second.st_size
      && first.st_mtimespec.tv_sec == second.st_mtimespec.tv_sec
      && first.st_mtimespec.tv_nsec == second.st_mtimespec.tv_nsec
      && first.st_ctimespec.tv_sec == second.st_ctimespec.tv_sec
      && first.st_ctimespec.tv_nsec == second.st_ctimespec.tv_nsec
  }

  func sameDirectoryIdentity(_ first: stat, _ second: stat) -> Bool {
    first.st_dev == second.st_dev
      && first.st_ino == second.st_ino
      && (first.st_mode & S_IFMT) == S_IFDIR
      && (second.st_mode & S_IFMT) == S_IFDIR
      && first.st_uid == second.st_uid
      && first.st_gid == second.st_gid
  }

  func privateDirectoryStatus(_ descriptor: Int32) throws -> stat {
    var information = stat()
    try #require(Darwin.fstat(descriptor, &information) == 0)
    let directoryIsPrivate =
      (information.st_mode & S_IFMT) == S_IFDIR
        && information.st_uid == Darwin.geteuid()
        && (information.st_mode & 0o777) == 0o700
        && (information.st_mode & 0o7000) == 0
    try #require(directoryIsPrivate)
    return information
  }

  func directoryEntryMatches(
    _ name: String,
    relativeTo parentDescriptor: Int32,
    metadata: stat
  ) -> Bool {
    var entry = stat()
    let entryExists = name.withCString {
      Darwin.fstatat(parentDescriptor, $0, &entry, AT_SYMLINK_NOFOLLOW) == 0
    }
    return entryExists && sameMetadata(metadata, entry)
  }

  func openPrivateDirectory(
    relativeTo parentDescriptor: Int32,
    named name: String
  ) throws -> Int32 {
    let descriptor = name.withCString {
      Darwin.openat(
        parentDescriptor,
        $0,
        O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
      )
    }
    try #require(descriptor >= 0)
    do {
      let information = try privateDirectoryStatus(descriptor)
      let entryIsBound = directoryEntryMatches(
        name,
        relativeTo: parentDescriptor,
        metadata: information
      )
      try #require(entryIsBound)
      return descriptor
    } catch {
      _ = Darwin.close(descriptor)
      throw error
    }
  }

  func readBoundedDescriptor(
    _ descriptor: Int32,
    maximumBytes: Int
  ) -> (data: Data, complete: Bool) {
    var bytes = [UInt8](repeating: 0, count: maximumBytes)
    var length = 0
    var complete = true
    while length < bytes.count {
      let amount = bytes.withUnsafeMutableBytes { buffer -> Int in
        guard let baseAddress = buffer.baseAddress else { return -1 }
        return Darwin.read(descriptor, baseAddress.advanced(by: length), buffer.count - length)
      }
      guard amount >= 0 else {
        complete = false
        break
      }
      if amount == 0 { break }
      length += amount
    }
    return (Data(bytes.prefix(length)), complete)
  }

  let candidateControlDirectoryName = "hidden-capsule198-default7-a11y-v1-control"
  let candidateRootComponents = candidateRoot.pathComponents
  let runDirectoryComponents = expectedRunDirectory.pathComponents
  let expectedFactoryRunPath = [candidateControlDirectoryName, "runs", runComponent]
  let runPathStartsAtCandidateRoot =
    Array(
      runDirectoryComponents.prefix(candidateRootComponents.count)
    ) == candidateRootComponents
  let runPathUsesFactoryLayout =
    Array(
      runDirectoryComponents.dropFirst(candidateRootComponents.count)
    ) == expectedFactoryRunPath
  let runDirectoryComponentsAreBounded =
    candidateRoot.path.hasPrefix("/")
      && candidateRootComponents.count > 1
      && candidateRootComponents.count < runDirectoryComponents.count
      && runDirectoryComponents.count <= 64
      && runPathStartsAtCandidateRoot
      && runPathUsesFactoryLayout
      && candidateRootComponents.dropFirst().allSatisfy {
        !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("/")
      }
      && runDirectoryComponents.dropFirst().allSatisfy {
        !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("/")
      }
  try #require(runDirectoryComponentsAreBounded)

  var candidateRootDescriptor = Darwin.open(
    "/",
    O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
  )
  try #require(candidateRootDescriptor >= 0)
  var candidateRootParentDescriptor: Int32?
  defer {
    if candidateRootDescriptor >= 0 { _ = Darwin.close(candidateRootDescriptor) }
    if let candidateRootParentDescriptor {
      _ = Darwin.close(candidateRootParentDescriptor)
    }
  }
  var walkedCandidateRootPath = "/"
  let candidateRootComponentsToOpen = candidateRootComponents.dropFirst()
  for (index, component) in candidateRootComponentsToOpen.enumerated() {
    let nextDescriptor = component.withCString {
      Darwin.openat(
        candidateRootDescriptor,
        $0,
        O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
      )
    }
    try #require(nextDescriptor >= 0)
    let parentDescriptor = candidateRootDescriptor
    candidateRootDescriptor = nextDescriptor
    walkedCandidateRootPath = walkedCandidateRootPath == "/"
      ? "/\(component)"
      : "\(walkedCandidateRootPath)/\(component)"
    if index == candidateRootComponentsToOpen.count - 1 {
      candidateRootParentDescriptor = parentDescriptor
    } else {
      _ = Darwin.close(parentDescriptor)
    }
  }
  let candidateRootPathIsExact = walkedCandidateRootPath == candidateRoot.path
  try #require(candidateRootPathIsExact)
  let candidateRootParent = try #require(candidateRootParentDescriptor)
  let candidateRootName = try #require(candidateRootComponents.last)
  var candidateRootBefore = stat()
  try #require(Darwin.fstat(candidateRootDescriptor, &candidateRootBefore) == 0)
  let candidateRootIsDirectory = (candidateRootBefore.st_mode & S_IFMT) == S_IFDIR
  try #require(candidateRootIsDirectory)

  let candidateControlDescriptor = try openPrivateDirectory(
    relativeTo: candidateRootDescriptor,
    named: candidateControlDirectoryName
  )
  defer { _ = Darwin.close(candidateControlDescriptor) }
  let candidateControlBefore = try privateDirectoryStatus(candidateControlDescriptor)

  let runsDescriptor = try openPrivateDirectory(
    relativeTo: candidateControlDescriptor,
    named: "runs"
  )
  defer { _ = Darwin.close(runsDescriptor) }
  let runsBefore = try privateDirectoryStatus(runsDescriptor)

  let runDescriptor = try openPrivateDirectory(
    relativeTo: runsDescriptor,
    named: runComponent
  )
  defer { _ = Darwin.close(runDescriptor) }
  let runBefore = try privateDirectoryStatus(runDescriptor)

  let homeDescriptor = try openPrivateDirectory(
    relativeTo: runDescriptor,
    named: "home"
  )
  defer { _ = Darwin.close(homeDescriptor) }
  let homeBefore = try privateDirectoryStatus(homeDescriptor)

  let temporaryDescriptor = try openPrivateDirectory(
    relativeTo: runDescriptor,
    named: "tmp"
  )
  defer { _ = Darwin.close(temporaryDescriptor) }
  let temporaryBefore = try privateDirectoryStatus(temporaryDescriptor)

  let stateDescriptor = try openPrivateDirectory(
    relativeTo: temporaryDescriptor,
    named: hostStateDirectoryName
  )
  defer { _ = Darwin.close(stateDescriptor) }
  let stateBefore = try privateDirectoryStatus(stateDescriptor)

  let stageDescriptor = try openPrivateDirectory(
    relativeTo: stateDescriptor,
    named: "run"
  )
  defer { _ = Darwin.close(stageDescriptor) }
  let stageBefore = try privateDirectoryStatus(stageDescriptor)

  func verifyHostDirectoryChain() throws {
    var candidateRootPathDescriptor = Darwin.open(
      "/",
      O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
    )
    try #require(candidateRootPathDescriptor >= 0)
    defer {
      if candidateRootPathDescriptor >= 0 {
        _ = Darwin.close(candidateRootPathDescriptor)
      }
    }
    for component in candidateRootComponents.dropFirst() {
      let nextDescriptor = component.withCString {
        Darwin.openat(
          candidateRootPathDescriptor,
          $0,
          O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
      }
      try #require(nextDescriptor >= 0)
      _ = Darwin.close(candidateRootPathDescriptor)
      candidateRootPathDescriptor = nextDescriptor
    }
    var candidateRootAtPath = stat()
    try #require(Darwin.fstat(candidateRootPathDescriptor, &candidateRootAtPath) == 0)
    let candidateRootPathIsBound =
      sameDirectoryIdentity(candidateRootBefore, candidateRootAtPath)
    try #require(candidateRootPathIsBound)

    var candidateRootAfter = stat()
    try #require(Darwin.fstat(candidateRootDescriptor, &candidateRootAfter) == 0)
    let candidateRootIsBound =
      sameDirectoryIdentity(candidateRootBefore, candidateRootAfter)
        && directoryEntryMatches(
          candidateRootName,
          relativeTo: candidateRootParent,
          metadata: candidateRootAfter
        )
    try #require(candidateRootIsBound)

    let candidateControlAfter = try privateDirectoryStatus(candidateControlDescriptor)
    let candidateControlIsBound =
      sameDirectoryIdentity(candidateControlBefore, candidateControlAfter)
        && directoryEntryMatches(
          candidateControlDirectoryName,
          relativeTo: candidateRootDescriptor,
          metadata: candidateControlAfter
        )
    try #require(candidateControlIsBound)

    let runsAfter = try privateDirectoryStatus(runsDescriptor)
    let runsAreBound =
      sameDirectoryIdentity(runsBefore, runsAfter)
        && directoryEntryMatches(
          "runs",
          relativeTo: candidateControlDescriptor,
          metadata: runsAfter
        )
    try #require(runsAreBound)

    let runAfter = try privateDirectoryStatus(runDescriptor)
    let runIsBound =
      sameDirectoryIdentity(runBefore, runAfter)
        && directoryEntryMatches(
          runComponent,
          relativeTo: runsDescriptor,
          metadata: runAfter
        )
    try #require(runIsBound)

    let homeAfter = try privateDirectoryStatus(homeDescriptor)
    let homeIsBound =
      sameDirectoryIdentity(homeBefore, homeAfter)
        && directoryEntryMatches("home", relativeTo: runDescriptor, metadata: homeAfter)
    try #require(homeIsBound)

    let temporaryAfter = try privateDirectoryStatus(temporaryDescriptor)
    let temporaryIsBound =
      sameDirectoryIdentity(temporaryBefore, temporaryAfter)
        && directoryEntryMatches("tmp", relativeTo: runDescriptor, metadata: temporaryAfter)
    try #require(temporaryIsBound)

    let stateAfter = try privateDirectoryStatus(stateDescriptor)
    let stateIsBound =
      sameDirectoryIdentity(stateBefore, stateAfter)
        && directoryEntryMatches(
          hostStateDirectoryName,
          relativeTo: temporaryDescriptor,
          metadata: stateAfter
        )
    try #require(stateIsBound)

    let stageAfter = try privateDirectoryStatus(stageDescriptor)
    let stageIsBound =
      sameDirectoryIdentity(stageBefore, stageAfter)
        && directoryEntryMatches("run", relativeTo: stateDescriptor, metadata: stageAfter)
    try #require(stageIsBound)
  }
  try verifyHostDirectoryChain()

  func readStageFile(named name: String, maximumBytes: Int) throws -> Data {
    let stageFileNameIsAllowed = name == "host-configuration" || name == "host-process"
    try #require(stageFileNameIsAllowed)
    let descriptor = name.withCString {
      Darwin.openat(stageDescriptor, $0, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
    }
    try #require(descriptor >= 0)
    defer { _ = Darwin.close(descriptor) }

    let parentBefore = try privateDirectoryStatus(stageDescriptor)
    let parentEntryIsBoundBeforeRead = directoryEntryMatches(
      "run",
      relativeTo: stateDescriptor,
      metadata: parentBefore
    )
    try #require(parentEntryIsBoundBeforeRead)

    var fileBefore = stat()
    try #require(Darwin.fstat(descriptor, &fileBefore) == 0)
    let fileMetadataIsAllowed =
      (fileBefore.st_mode & S_IFMT) == S_IFREG
        && fileBefore.st_uid == Darwin.geteuid()
        && fileBefore.st_nlink == 1
        && fileBefore.st_size > 0
        && fileBefore.st_size <= maximumBytes
        && (fileBefore.st_mode & 0o400) != 0
        && (fileBefore.st_mode & 0o022) == 0
        && (fileBefore.st_mode & 0o111) == 0
        && (fileBefore.st_mode & 0o7000) == 0
    try #require(fileMetadataIsAllowed)
    let fileEntryIsBoundBeforeRead = directoryEntryMatches(
      name,
      relativeTo: stageDescriptor,
      metadata: fileBefore
    )
    try #require(fileEntryIsBoundBeforeRead)

    let readResult = readBoundedDescriptor(descriptor, maximumBytes: maximumBytes)
    let contents = readResult.data
    var fileAfter = stat()
    try #require(Darwin.fstat(descriptor, &fileAfter) == 0)
    let fileMetadataIsStable = sameMetadata(fileBefore, fileAfter)
    let fileEntryIsBoundAfterRead = directoryEntryMatches(
      name,
      relativeTo: stageDescriptor,
      metadata: fileAfter
    )
    let boundedReadMatchesFileSize =
      readResult.complete && Int(fileAfter.st_size) == contents.count
    let parentAfter = try privateDirectoryStatus(stageDescriptor)
    let parentMetadataIsStable = sameMetadata(parentBefore, parentAfter)
    let parentEntryIsBoundAfterRead = directoryEntryMatches(
      "run",
      relativeTo: stateDescriptor,
      metadata: parentAfter
    )
    try #require(fileMetadataIsStable)
    try #require(fileEntryIsBoundAfterRead)
    try #require(parentMetadataIsStable)
    try #require(parentEntryIsBoundAfterRead)
    try #require(boundedReadMatchesFileSize)
    return contents
  }

  let hostConfigurationData = try readStageFile(
    named: "host-configuration",
    maximumBytes: 4096
  )
  let hostConfigurationParts = hostConfigurationData.split(
    separator: 0,
    omittingEmptySubsequences: false
  )
  let hostConfigurationHasFiveNULTerminatedFields =
    hostConfigurationParts.count == 6 && hostConfigurationParts.last?.isEmpty == true
  try #require(hostConfigurationHasFiveNULTerminatedFields)
  let hostConfigurationValues = hostConfigurationParts.dropLast().compactMap {
    String(data: Data($0), encoding: .utf8)
  }
  let hostConfigurationIsUTF8 = hostConfigurationValues.count == 5
  try #require(hostConfigurationIsUTF8)
  let hostConfigurationValuesAreNonempty = hostConfigurationValues.allSatisfy { !$0.isEmpty }
  try #require(hostConfigurationValuesAreNonempty)
  let hostNonce = hostConfigurationValues[0]
  let hostNonceIsUUID =
    UUID(uuidString: hostNonce) != nil
      && hostNonce.range(
        of: #"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"#,
        options: .regularExpression
      ) != nil
  try #require(hostNonceIsUUID)
  let expectedHostConfigurationPaths = [
    hostStageDirectoryURL.appendingPathComponent("completion-receipt").path,
    hostStageDirectoryURL.appendingPathComponent("host-process").path,
    hostStageDirectoryURL.appendingPathComponent("host-phase").path,
    hostStageDirectoryURL.appendingPathComponent("host.log").path,
  ]
  let hostConfigurationPathsMatchStage =
    Array(hostConfigurationValues.dropFirst()) == expectedHostConfigurationPaths
  try #require(hostConfigurationPathsMatchStage)

  let hostProcessPID = Darwin.getpid()
  let hostPIDRecord = try readStageFile(named: "host-process", maximumBytes: 128)
  let expectedHostPIDRecord = Data("\(hostNonce)\t\(hostProcessPID)\n".utf8)
  let hostPIDRecordMatchesProcess = hostPIDRecord == expectedHostPIDRecord
  try #require(hostPIDRecordMatchesProcess)
  try verifyHostDirectoryChain()
  let hostConfigurationSHA256 = SHA256.hash(data: hostConfigurationData)
    .map { String(format: "%02x", $0) }
    .joined()
  let hostPIDRecordSHA256 = SHA256.hash(data: hostPIDRecord)
    .map { String(format: "%02x", $0) }
    .joined()

  let runID = UUID().uuidString.lowercased()
  let runDirectory = outputDirectory
    .appendingPathComponent("accessibility-error-terminal", isDirectory: true)
    .appendingPathComponent(runID, isDirectory: true)
  try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)

  let fixtures = [
    FleckCapsuleErrorTerminalFixture(
      name: "saved",
      context: DictationCapsuleContext(
        status: .saved(destination: "Synthetic Inbox"),
        detailText: "Synthetic dictation",
        compactDetailText: "Synthetic dictation",
        sessionID: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
        trigger: .hold,
        mode: .focused,
        pipelineStage: .save
      ),
      action: .undo,
      expectedErrorKind: nil
    ),
    FleckCapsuleErrorTerminalFixture(
      name: "microphone-access",
      context: DictationCapsuleContext(
        status: .failed("Synthetic microphone access failure"),
        detailText: "Synthetic dictation",
        compactDetailText: "Synthetic dictation",
        sessionID: UUID(uuidString: "00000000-0000-4000-8000-000000000008")!,
        trigger: .hold,
        mode: .focused,
        pipelineStage: .capture,
        failureStage: .capture,
        failureKind: .microphoneAccess
      ),
      action: nil,
      expectedErrorKind: .microphone
    ),
    FleckCapsuleErrorTerminalFixture(
      name: "speech-recognition-access",
      context: DictationCapsuleContext(
        status: .failed("Synthetic Speech Recognition access failure"),
        sessionID: UUID(uuidString: "00000000-0000-4000-8000-000000000010")!,
        mode: .focused,
        pipelineStage: .capture,
        failureStage: .capture,
        failureKind: .speechRecognitionAccess
      ),
      action: nil,
      expectedErrorKind: .speechRecognition
    ),
    FleckCapsuleErrorTerminalFixture(
      name: "saved-with-service-fallback",
      context: DictationCapsuleContext(
        status: .savedWithoutCleanup(destination: "Synthetic Inbox"),
        detailText: "Synthetic dictation",
        compactDetailText: "Synthetic dictation",
        sessionID: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
        trigger: .hold,
        mode: .focused,
        pipelineStage: .save,
        cleanupOutcome: .usedRaw,
        cleanupFallbackProvenance: .serviceFallback
      ),
      action: nil,
      expectedErrorKind: nil
    ),
    FleckCapsuleErrorTerminalFixture(
      name: "capture-failure",
      context: DictationCapsuleContext(
        status: .failed("Synthetic capture failure"),
        detailText: "Synthetic dictation",
        compactDetailText: "Synthetic dictation",
        sessionID: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!,
        trigger: .hold,
        mode: .focused,
        pipelineStage: .capture,
        failureStage: .capture,
        failureKind: .generic
      ),
      action: nil,
      expectedErrorKind: .dictation
    ),
    FleckCapsuleErrorTerminalFixture(
      name: "routing-failure",
      context: DictationCapsuleContext(
        status: .routingFailure(
          status: "Synthetic destination unavailable",
          message: "Synthetic routing failure"
        ),
        detailText: "Synthetic dictation",
        compactDetailText: "Synthetic dictation",
        sessionID: UUID(uuidString: "00000000-0000-4000-8000-000000000004")!,
        trigger: .hold,
        mode: .focused,
        pipelineStage: .organize,
        failureStage: .organize,
        failureKind: .generic
      ),
      action: .openDestination,
      expectedErrorKind: .attention
    ),
    FleckCapsuleErrorTerminalFixture(
      name: "save-failure",
      context: DictationCapsuleContext(
        status: .failed("Synthetic persistence failure"),
        detailText: "Synthetic dictation",
        compactDetailText: "Synthetic dictation",
        sessionID: UUID(uuidString: "00000000-0000-4000-8000-000000000005")!,
        trigger: .hold,
        mode: .focused,
        pipelineStage: .save,
        failureStage: .save,
        failureProvenance: .persistence,
        failureKind: .save
      ),
      action: .copy,
      expectedErrorKind: .attention
    ),
    FleckCapsuleErrorTerminalFixture(
      name: "insertion-failure",
      context: DictationCapsuleContext(
        status: .failed("Synthetic insertion failure"),
        detailText: "Synthetic dictation",
        compactDetailText: "Synthetic dictation",
        sessionID: UUID(uuidString: "00000000-0000-4000-8000-000000000009")!,
        trigger: .hold,
        mode: .focused,
        pipelineStage: .save,
        failureStage: .save,
        failureProvenance: .insertion,
        failureKind: .save
      ),
      action: .copy,
      expectedErrorKind: .insertion
    ),
    FleckCapsuleErrorTerminalFixture(
      name: "no-speech",
      context: DictationCapsuleContext(
        status: .noSpeech,
        detailText: "Synthetic dictation",
        compactDetailText: "Synthetic dictation",
        sessionID: UUID(uuidString: "00000000-0000-4000-8000-000000000006")!,
        trigger: .hold,
        mode: .focused,
        pipelineStage: .capture
      ),
      action: nil,
      expectedErrorKind: .noSpeech
    ),
    FleckCapsuleErrorTerminalFixture(
      name: "repairing-model",
      context: DictationCapsuleContext(
        status: .repairingModel,
        detailText: "Synthetic dictation",
        compactDetailText: "Synthetic dictation",
        sessionID: UUID(uuidString: "00000000-0000-4000-8000-000000000007")!,
        trigger: .hold,
        mode: .focused,
        pipelineStage: .capture
      ),
      action: nil,
      expectedErrorKind: .repairing
    ),
  ]
  let families = FleckColorTheme.allCases
  let modes: [(AppTheme, FleckThemeAppearance, NSAppearance.Name, String)] = [
    (.light, .light, .aqua, "light"),
    (.dark, .dark, .darkAqua, "dark"),
  ]
  #expect(families.count == 8)
  #expect(fixtures.count == 10)
  #expect(FleckErrorKind.allCases.filter { $0 != .usedOriginal }.allSatisfy { kind in
    fixtures.contains { $0.expectedErrorKind == kind }
  })

  let frozenNow = ProcessInfo.processInfo.systemUptime
  var captures: [FleckCapsuleCaptureRecord] = []
  for (mode, appearance, nsAppearance, modeName) in modes {
    let initialTheme = FleckThemeSnapshot.resolve(
      colorTheme: .monochrome,
      mode: mode,
      systemAppearance: appearance,
      reduceTransparency: false,
      increasedContrast: false
    )
    let panel = DictationCapsulePanel()
    panel.appearance = NSAppearance(named: nsAppearance)
    let controller = DictationCapsuleController(
      panel: panel,
      monotonicNow: { frozenNow },
      automaticallyAdvancesLivePill: false,
      reduceMotionProvider: { true },
      theme: initialTheme,
      markLoader: { nil },
      announcementPoster: { _, _ in }
    )
    defer { controller.dismiss() }
    controller.setReduceMotionOverrideForTesting(true)
    controller.panel.contentView?.appearance = NSAppearance(named: nsAppearance)
    let environmentEvidence = FleckCapsuleAccessibilityEnvironmentEvidence()
    let observeEnvironment: @MainActor (Bool, ColorSchemeContrast) -> Void = {
      observedTransparency, observedContrast in
      environmentEvidence.reduceTransparency = observedTransparency
      environmentEvidence.colorSchemeContrast = observedContrast
    }
    controller.setAccessibilityEnvironmentOverridesForTesting(
      reduceTransparency: nil,
      increasedContrast: nil,
      observe: observeEnvironment
    )
    controller.panel.contentView?.layoutSubtreeIfNeeded()
    controller.panel.contentView?.displayIfNeeded()
    await Task.yield()
    let inheritedTransparency = try #require(environmentEvidence.reduceTransparency)
    let inheritedContrast = try #require(environmentEvidence.colorSchemeContrast)
    let controlTransparency = !inheritedTransparency
    let controlIncreasedContrast = inheritedContrast != .increased
    let controlContrast: ColorSchemeContrast = controlIncreasedContrast ? .increased : .standard
    controller.setAccessibilityEnvironmentOverridesForTesting(
      reduceTransparency: controlTransparency,
      increasedContrast: controlIncreasedContrast,
      observe: observeEnvironment
    )
    controller.panel.contentView?.layoutSubtreeIfNeeded()
    controller.panel.contentView?.displayIfNeeded()
    await Task.yield()
    try #require(environmentEvidence.reduceTransparency == controlTransparency)
    try #require(environmentEvidence.colorSchemeContrast == controlContrast)
    controller.setAccessibilityEnvironmentOverridesForTesting(
      reduceTransparency: nil,
      increasedContrast: nil,
      observe: observeEnvironment
    )
    controller.panel.contentView?.layoutSubtreeIfNeeded()
    controller.panel.contentView?.displayIfNeeded()
    await Task.yield()
    try #require(environmentEvidence.reduceTransparency == inheritedTransparency)
    try #require(environmentEvidence.colorSchemeContrast == inheritedContrast)

    for family in families {
      for reduceTransparency in [false, true] {
        for increasedContrast in [false, true] {
          let theme = FleckThemeSnapshot.resolve(
            colorTheme: family,
            mode: mode,
            systemAppearance: appearance,
            reduceTransparency: reduceTransparency,
            increasedContrast: increasedContrast
          )
          controller.updateTheme(theme)
          controller.panel.contentView?.appearance = NSAppearance(named: nsAppearance)
          controller.setAccessibilityEnvironmentOverridesForTesting(
            reduceTransparency: reduceTransparency,
            increasedContrast: increasedContrast,
            observe: observeEnvironment
          )
          controller.panel.orderOut(nil)
          controller.panel.contentView?.layoutSubtreeIfNeeded()
          controller.panel.contentView?.displayIfNeeded()
          await Task.yield()

          let expectedContrast: ColorSchemeContrast = increasedContrast ? .increased : .standard
          try #require(environmentEvidence.reduceTransparency == reduceTransparency)
          try #require(environmentEvidence.colorSchemeContrast == expectedContrast)

          for fixture in fixtures {
            do {
              controller.setPanelVisibilitySuppressedForTesting(true)
              defer { controller.setPanelVisibilitySuppressedForTesting(nil) }
              controller.panel.orderOut(nil)
              controller.render(
                fixture.context,
                action: fixture.action,
                onAction: {},
                onChoice: { _, _ in }
              )
              try #require(!controller.panel.isVisible)
              await Task.yield()
              let displayedContext = controller.currentContext
              let displayedAction = controller.presentationModel.action
              let presentation = DictationCapsulePresentation(
                status: displayedContext.status,
                action: displayedAction,
                context: displayedContext
              )
              let captureSize: CGSize
              if fixture.expectedErrorKind != nil {
                captureSize = DictationCapsuleController.errorSurfaceSize
              } else if controller.fleckPillModel.usesFixedHost {
                captureSize = DictationCapsuleController.livePillHostSize
              } else {
                captureSize = DictationCapsuleController.size(
                  for: displayedContext.status,
                  measuredWidth: presentation.measuredWidth,
                  widthCeiling: presentation.widthCeiling
                )
              }
              let fileName = [
                family.rawValue,
                modeName,
                "transparency-\(reduceTransparency)",
                "contrast-\(increasedContrast)",
                fixture.name,
              ].joined(separator: "-") + ".png"
              let destination = runDirectory.appendingPathComponent(fileName)
              let observedReduceTransparency = try #require(environmentEvidence.reduceTransparency)
              let observedColorSchemeContrast = try #require(environmentEvidence.colorSchemeContrast)
              try #require(observedReduceTransparency == reduceTransparency)
              try #require(observedColorSchemeContrast == expectedContrast)
              let geometry = try captureFleckCapsuleErrorTerminalBitmap(
                fixture,
                controller: controller,
                size: captureSize,
                destination: destination
              )
              let errorPresentation = controller.errorPresentationModel.presentation
              captures.append(FleckCapsuleCaptureRecord(
                file: fileName,
                themeFamily: family.rawValue,
                appearance: modeName,
                observedReduceTransparency: observedReduceTransparency,
                observedColorSchemeContrast: String(describing: observedColorSchemeContrast),
                reduceTransparency: reduceTransparency,
                increasedContrast: increasedContrast,
                fixture: fixture.name,
                status: String(describing: displayedContext.status),
                expectedErrorKind: fixture.expectedErrorKind.map { String(describing: $0) },
                actualErrorKind: errorPresentation.map { String(describing: $0.kind) },
                actionTitle: errorPresentation?.actionTitle,
                contentOpacity: errorPresentation?.contentOpacity,
                geometry: geometry
              ))
            }
          }
          controller.setAccessibilityEnvironmentOverridesForTesting(
            reduceTransparency: nil,
            increasedContrast: nil,
            observe: observeEnvironment
          )
          controller.panel.contentView?.layoutSubtreeIfNeeded()
          controller.panel.contentView?.displayIfNeeded()
          await Task.yield()
          try #require(environmentEvidence.reduceTransparency == inheritedTransparency)
          try #require(environmentEvidence.colorSchemeContrast == inheritedContrast)
        }
      }
    }
  }

  let expectedCaptureCount = families.count * modes.count * 2 * 2 * fixtures.count
  try #require(captures.count == expectedCaptureCount)
  try verifyHostDirectoryChain()
  let hostBinding = FleckCapsuleHostBinding(
    validated: true,
    stage: "run",
    nonce: hostNonce,
    ownPID: hostProcessPID,
    configSHA256: hostConfigurationSHA256,
    pidRecordSHA256: hostPIDRecordSHA256
  )
  let manifest = FleckCapsuleCaptureManifest(
    runID: runID,
    hostProfile: hostProfile,
    hostBinding: hostBinding,
    captureControl: "FLECK_CAPSULE_NATIVE_QA=1 plus candidate evidence FLECK_PILL_CAPTURE_DIRECTORY",
    captureCount: captures.count,
    captures: captures
  )
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  try encoder.encode(manifest).write(
    to: runDirectory.appendingPathComponent("manifest.json"),
    options: .atomic
  )
}
#endif
