#if os(macOS) && DEBUG
import AppKit
import FleckCore
import SwiftUI
import Testing

@testable import FleckApp

@Test @MainActor
func FleckPillQuietSurfaceHasNoDecorativeWhiteRimOrGloss() throws {
  for reduceTransparency in [false, true] {
    let theme = FleckThemeSnapshot.resolve(
      colorTheme: .monochrome,
      mode: .dark,
      systemAppearance: .dark,
      reduceTransparency: reduceTransparency,
      increasedContrast: false
    )
    let colors = FleckRailColors(theme: theme)
    #expect(colors.effectiveShellOpacity == (reduceTransparency ? 1 : FleckRailColors.glassShellOpacity))
    for pose in FleckPillPose.allCases {
      let frame = try FleckPillGeometry.pose(named: pose.rawValue).artworkFrame
      let renderer = ImageRenderer(content: FleckPillCanvas(
        frame: frame,
        layers: FleckPillCanvasLayers(signal: false),
        colors: colors
      ))
      renderer.scale = 2
      renderer.colorMode = .nonLinear
      let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
      if let directory = ProcessInfo.processInfo.environment["FLECK_ERROR_V3_CAPTURE_DIRECTORY"] {
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: directory)
          .appendingPathComponent("quiet-surface-\(pose.rawValue)-opaque-\(reduceTransparency).png"))
      }
      var coveredPixels = 0
      for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
          let pixel = try #require(bitmap.colorAt(x: x, y: y))
          guard pixel.alphaComponent >= 0.5 else { continue }
          coveredPixels += 1
          let composited = max(
            pixel.redComponent,
            max(pixel.greenComponent, pixel.blueComponent)
          ) * pixel.alphaComponent
          #expect(composited < 0.32)
        }
      }
      #expect(coveredPixels > 20)
    }
  }
}

@Test func FleckPillSurfaceStaysNearBlackOverEveryBackdropAndKeepsContentFloors() throws {
  let black = FleckRailRGB(red: 0, green: 0, blue: 0)
  for family in FleckColorTheme.allCases {
    for (mode, appearance) in [(AppTheme.light, FleckThemeAppearance.light), (.dark, .dark)] {
      for reduceTransparency in [false, true] {
        let theme = FleckThemeSnapshot.resolve(
          colorTheme: family,
          mode: mode,
          systemAppearance: appearance,
          reduceTransparency: reduceTransparency,
          increasedContrast: false
        )
        let colors = FleckRailColors(theme: theme)
        let noteSurface = try #require(FleckRailRGB(hex: theme.palette[.editorOpaque]))
        for backdrop in [black, noteSurface] {
          let composited = colors.compositedShell(over: backdrop)
          #expect(
            composited.brightestChannel
              <= FleckRailColors.shellBrightnessCeiling + 1.0 / 255,
            "\(family.rawValue) \(appearance.rawValue) rt\(reduceTransparency) brightest=\(composited.brightestChannel)"
          )
          #expect(FleckRailColors.contrastRatio(colors.primaryText, against: composited) >= 4.5)
          #expect(FleckRailColors.contrastRatio(colors.secondaryText, against: composited) >= 4.5)
          for mark in [colors.displayCore, colors.displayLive, colors.success, colors.warning, colors.failure] {
            #expect(FleckRailColors.contrastRatio(mark, against: composited) >= 3)
          }
        }
        #expect(
          colors.shell.brightestChannel
            <= FleckRailColors.shellSurfaceBrightness + 1.0 / 255
        )
        #expect(FleckRailColors.contrastRatio(colors.primaryText, against: colors.shell) >= 4.5)
        #expect(FleckRailColors.contrastRatio(colors.secondaryText, against: colors.shell) >= 4.5)
        for mark in [colors.displayCore, colors.displayLive, colors.success, colors.warning, colors.failure] {
          #expect(FleckRailColors.contrastRatio(mark, against: colors.shell) >= 3)
        }
      }
    }
  }
}

@Test func FleckPillHairlineMarksTheSurfaceWithoutBecomingARim() throws {
  let black = FleckRailRGB(red: 0, green: 0, blue: 0)
  for family in FleckColorTheme.allCases {
    for (mode, appearance) in [(AppTheme.light, FleckThemeAppearance.light), (.dark, .dark)] {
      let theme = FleckThemeSnapshot.resolve(
        colorTheme: family,
        mode: mode,
        systemAppearance: appearance,
        reduceTransparency: false,
        increasedContrast: false
      )
      let colors = FleckRailColors(theme: theme)
      let noteSurface = try #require(FleckRailRGB(hex: theme.palette[.editorOpaque]))
      for backdrop in [black, noteSurface] {
        let edge = FleckRailColors.contrastRatio(
          colors.hairline(over: backdrop),
          against: backdrop
        )
        if backdrop.luminance < 0.1 {
          #expect(
            FleckRailColors.hairlineContrastBand.contains(edge),
            "\(family.rawValue) \(appearance.rawValue) edge=\(edge)"
          )
        } else {
          #expect(edge >= 3)
        }
      }
    }
  }
}

@Test @MainActor
func FleckPillQuietSurfaceNativeProfileRendersWhenRequested() throws {
  guard let path = ProcessInfo.processInfo.environment["FLECK_ERROR_V3_CAPTURE_DIRECTORY"] else { return }
  let directory = URL(fileURLWithPath: path, isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  for bright in [false, true] {
    for reduceTransparency in [false, true] {
      for increasedContrast in [false, true] {
        let theme = FleckThemeSnapshot.resolve(
          colorTheme: .monochrome,
          mode: bright ? .light : .dark,
          systemAppearance: bright ? .light : .dark,
          reduceTransparency: reduceTransparency,
          increasedContrast: increasedContrast
        )
        let colors = FleckRailColors(theme: theme)
        let noteSurface = try #require(FleckRailRGB(hex: theme.palette[.editorOpaque]))
        let backdrops: [(String, Color)] = [
          ("black", .black),
          (
            "editor",
            Color(
              .sRGB,
              red: noteSurface.red,
              green: noteSurface.green,
              blue: noteSurface.blue
            )
          ),
          ("light", Color(white: 0.965)),
        ]
        let frames = try FleckPillPose.allCases.map {
          try FleckPillGeometry.pose(named: $0.rawValue).artworkFrame
        }
        for (backdropName, backdrop) in backdrops {
          let content = VStack(spacing: 8) {
            ForEach(Array(frames.enumerated()), id: \.offset) { _, frame in
              FleckPillCanvas(frame: frame, colors: colors)
            }
            ForEach([FleckErrorKind.noSpeech, .microphone, .repairing], id: \.self) { kind in
              FleckErrorCanvas(
                presentation: FleckErrorPresentation(kind: kind, phase: .default, dismissal: 0, target: .standby),
                frame: frames[0],
                sourceFrame: nil,
                increaseContrast: increasedContrast,
                reduceTransparency: reduceTransparency,
                colors: colors
              )
            }
          }
          .padding(16)
          .background(backdrop)
          .environment(\.colorScheme, bright ? .light : .dark)
          let renderer = ImageRenderer(content: content)
          renderer.scale = 2
          let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
          let data = try #require(bitmap.representation(using: .png, properties: [:]))
          let name = "synthetic-native-material-\(bright ? "bright" : "dark")-opaque-\(reduceTransparency)-contrast-\(increasedContrast)-backdrop-\(backdropName).png"
          try data.write(to: directory.appendingPathComponent(name))
        }
      }
    }
  }
}

@Test @MainActor
func FleckPillQuietSurfaceNativeRootObservesAccessibilityProfiles() async throws {
  guard let path = ProcessInfo.processInfo.environment["FLECK_ERROR_V3_CAPTURE_DIRECTORY"] else { return }
  let directory = URL(fileURLWithPath: path, isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let scenarios: [(String, DictationCapsuleContext)] = [
    ("standby", .init(status: .idle)),
    ("listening", .init(status: .listening, sessionID: UUID(), mode: .focused, pipelineStage: .capture)),
    ("processing", .init(status: .cleaning, sessionID: UUID(), mode: .focused, pipelineStage: .polish)),
    ("no-speech", .init(status: .noSpeech)),
    ("microphone", .init(status: .failed("Synthetic permission failure"), failureStage: .capture, failureKind: .microphoneAccess)),
    ("repairing", .init(status: .repairingModel)),
  ]
  for bright in [false, true] {
    for opaque in [false, true] {
      for contrast in [false, true] {
        for (name, context) in scenarios {
          let theme = FleckThemeSnapshot.resolve(
            colorTheme: .monochrome, mode: bright ? .light : .dark,
            systemAppearance: bright ? .light : .dark,
            reduceTransparency: opaque, increasedContrast: contrast
          )
          let panel = DictationCapsulePanel()
          panel.appearance = NSAppearance(named: bright ? .aqua : .darkAqua)
          let now = ProcessInfo.processInfo.systemUptime
          let controller = DictationCapsuleController(
            panel: panel, monotonicNow: { now }, automaticallyAdvancesLivePill: false,
            reduceMotionProvider: { true }, theme: theme, announcementPoster: { _, _ in }
          )
          defer { controller.dismiss() }
          controller.setPanelVisibilitySuppressedForTesting(true)
          controller.setReduceMotionOverrideForTesting(true)
          var observedTransparency: Bool?
          var observedContrast: ColorSchemeContrast?
          controller.setAccessibilityEnvironmentOverridesForTesting(
            reduceTransparency: opaque, increasedContrast: contrast,
            observe: { observedTransparency = $0; observedContrast = $1 }
          )
          controller.render(context)
          controller.fleckPillModel.tick(at: now + 1, displayedEnergy: 0.25, reduceMotion: true)
          let host = try #require(panel.contentView)
          for _ in 0..<8 {
            host.layoutSubtreeIfNeeded()
            await Task.yield()
          }
          #expect(!panel.isVisible)
          #expect(controller.currentContext == context.presentationContext())
          #expect(observedTransparency == opaque)
          #expect(observedContrast == (contrast ? .increased : .standard))
          #expect(controller.presentationModel.colors.reduceTransparency == opaque)
          #expect(controller.presentationModel.colors.increasedContrast == contrast)
          let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
          host.cacheDisplay(in: host.bounds, to: bitmap)
          let data = try #require(bitmap.representation(using: .png, properties: [:]))
          let filename = "synthetic-native-root-\(name)-\(bright ? "bright" : "dark")-opaque-\(opaque)-contrast-\(contrast).png"
          try data.write(to: directory.appendingPathComponent(filename))
        }
      }
    }
  }
}

@Test @MainActor
func FleckPillBodyCompositesAtTheShellOpacity() throws {
  let theme = FleckThemeSnapshot.resolve(
    colorTheme: .monochrome,
    mode: .dark,
    systemAppearance: .dark,
    reduceTransparency: false,
    increasedContrast: false
  )
  let colors = FleckRailColors(theme: theme)
  let material = colors.effectiveShellOpacity
  let hairlineCeiling = 1 - (1 - material) * (1 - material * FleckRailColors.hairlineOpacity)
  for pose in [FleckPillPose.standby, .activating, .listening] {
    let frame = try FleckPillGeometry.pose(named: pose.rawValue).artworkFrame
    let renderer = ImageRenderer(content: FleckPillCanvas(
      frame: frame,
      layers: FleckPillCanvasLayers(signal: false),
      colors: colors
    ))
    renderer.scale = 2
    renderer.colorMode = .nonLinear
    let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
    var bodyPixels = 0
    var coveredPixels = 0
    for y in 0..<bitmap.pixelsHigh {
      for x in 0..<bitmap.pixelsWide {
        let pixel = try #require(bitmap.colorAt(x: x, y: y))
        let alpha = Double(pixel.alphaComponent)
        guard alpha > 0 else { continue }
        coveredPixels += 1
        #expect(
          alpha <= hairlineCeiling + 1.5 / 255,
          "pose=\(pose.rawValue) x=\(x) y=\(y) alpha=\(alpha)"
        )
        if abs(alpha - material) <= 1.5 / 255 {
          bodyPixels += 1
        }
      }
    }
    #expect(coveredPixels > 200)
    #expect(bodyPixels > 100)
  }
}

@Test @MainActor
func FleckPillHairlineReadsAsAnEdgeOverABlackNote() throws {
  let theme = FleckThemeSnapshot.resolve(
    colorTheme: .monochrome,
    mode: .dark,
    systemAppearance: .dark,
    reduceTransparency: false,
    increasedContrast: false
  )
  let colors = FleckRailColors(theme: theme)
  let frame = try FleckPillGeometry.pose(named: FleckPillPose.standby.rawValue).artworkFrame
  let renderer = ImageRenderer(content: FleckPillCanvas(
    frame: frame,
    layers: FleckPillCanvasLayers(signal: false),
    colors: colors
  ))
  renderer.scale = 2
  renderer.colorMode = .nonLinear
  let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
  func luminanceOverBlack(x: Int, y: Int) throws -> Double {
    let pixel = try #require(bitmap.colorAt(x: x, y: y))
    let alpha = Double(pixel.alphaComponent)
    return FleckRailRGB(
      red: Double(pixel.redComponent) * alpha,
      green: Double(pixel.greenComponent) * alpha,
      blue: Double(pixel.blueComponent) * alpha
    ).luminance
  }
  var brightest = 0.0
  var brightestRow = 0
  let midX = bitmap.pixelsWide / 2
  for y in 0..<bitmap.pixelsHigh {
    let luminance = try luminanceOverBlack(x: midX, y: y)
    if luminance > brightest {
      brightest = luminance
      brightestRow = y
    }
  }
  let bodyLuminance = try luminanceOverBlack(x: midX, y: brightestRow + 4)
  let contrast = (brightest + 0.05) / (bodyLuminance + 0.05)
  #expect(
    FleckRailColors.hairlineContrastBand.contains(contrast),
    "rendered hairline contrast=\(contrast) row=\(brightestRow)"
  )
}
#endif
