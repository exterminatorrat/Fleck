#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing

@testable import FleckApp

private struct FleckErrorButtonCapture: View {
  let title: String
  let phase: FleckErrorButtonPhase
  let interaction: FleckErrorButtonInteraction

  var body: some View {
    Button(title, action: {})
      .buttonStyle(FleckErrorActionStyle(
        phase: phase,
        title: title,
        interaction: interaction,
        increaseContrast: false
      ))
  }
}

private struct FleckErrorButtonMidstateCapture: View {
  let feedback: FleckErrorButtonFeedback

  var body: some View {
    ZStack {
      FleckErrorButtonCanvas(feedback: feedback, increaseContrast: false, reduceMotion: true)
      Text("Try again")
        .font(.system(size: FleckErrorGeometry.actionSize, weight: .regular))
        .foregroundStyle(Color(
          .sRGB,
          red: feedback.color.red,
          green: feedback.color.green,
          blue: feedback.color.blue,
          opacity: 1
        ))
        .lineLimit(1)
        .fixedSize()
        .position(
          x: FleckErrorLayout.approved.buttonFaceWidth / 2,
          y: FleckErrorLayout.approved.actionLabelCenterY
        )
    }
    .frame(
      width: FleckErrorLayout.approved.buttonFaceWidth,
      height: FleckErrorLayout.approved.buttonFaceHeight
    )
  }
}

@MainActor
private func bitmapCapture(of view: NSView, scale: CGFloat) throws -> NSBitmapImageRep {
  view.layoutSubtreeIfNeeded()
  let bounds = view.bounds
  let image = try #require(NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: max(1, Int((bounds.width * scale).rounded(.up))),
    pixelsHigh: max(1, Int((bounds.height * scale).rounded(.up))),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  ))
  image.size = bounds.size
  view.cacheDisplay(in: bounds, to: image)
  #expect(image.pixelsWide == max(1, Int((bounds.width * scale).rounded(.up))))
  #expect(image.pixelsHigh == max(1, Int((bounds.height * scale).rounded(.up))))
  return image
}

@MainActor
private func compositeCapture(
  _ image: NSBitmapImageRep,
  red: CGFloat,
  green: CGFloat,
  blue: CGFloat
) throws -> NSBitmapImageRep {
  let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
  let context = try #require(CGContext(
    data: nil,
    width: image.pixelsWide,
    height: image.pixelsHigh,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  ))
  let background = try #require(CGColor(
    colorSpace: colorSpace,
    components: [red, green, blue, 1]
  ))
  let bounds = CGRect(x: 0, y: 0, width: image.pixelsWide, height: image.pixelsHigh)
  context.setFillColor(background)
  context.fill(bounds)
  context.draw(try #require(image.cgImage), in: bounds)
  let composite = NSBitmapImageRep(cgImage: try #require(context.makeImage()))
  composite.size = image.size
  return composite
}

@MainActor
private func saveCapture(
  of view: NSView,
  name: String,
  scale: CGFloat,
  backgroundRed: CGFloat,
  backgroundGreen: CGFloat,
  backgroundBlue: CGFloat,
  to directory: URL
) throws {
  let image = try compositeCapture(
    bitmapCapture(of: view, scale: scale),
    red: backgroundRed,
    green: backgroundGreen,
    blue: backgroundBlue
  )
  let data = try #require(image.representation(using: .png, properties: [:]))
  try data.write(to: directory.appendingPathComponent("\(name).png"))
}

@Test @MainActor
func FleckErrorNativeCaptureMatrixWritesOffscreenPNGsWhenRequested() throws {
  guard let path = ProcessInfo.processInfo.environment["FLECK_ERROR_V3_CAPTURE_DIRECTORY"]
  else { return }
  let directory = URL(fileURLWithPath: path, isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

  let appearances: [(String, NSAppearance.Name, CGFloat, CGFloat, CGFloat)] = [
    ("dark-bg", .darkAqua, 7.0 / 255, 8.0 / 255, 11.0 / 255),
    ("bright-bg", .aqua, 246.0 / 255, 246.0 / 255, 246.0 / 255),
  ]
  let scales: [(String, CGFloat)] = [("1x", 1), ("1.5x", 1.5)]
  let errors: [(String, DictationCapsuleContext, DictationCapsuleAction?, FleckErrorKind)] = [
    (
      "microphone",
      DictationCapsuleContext(
        status: .failed("Microphone permission denied."),
        failureStage: .capture,
        failureKind: .microphoneAccess
      ),
      nil,
      .microphone
    ),
    (
      "dictation",
      DictationCapsuleContext(status: .failed("No usable transcription is available."), failureStage: .capture),
      nil,
      .dictation
    ),
    (
      "insertion",
      DictationCapsuleContext(
        status: .failed("Unable to insert dictated text."),
        sessionID: UUID(),
        failureStage: .save,
        failureProvenance: .insertion,
        failureKind: .save
      ),
      .copy,
      .insertion
    ),
    (
      "no-speech",
      DictationCapsuleContext(status: .noSpeech),
      nil,
      .noSpeech
    ),
    (
      "used-original-reference-fixture",
      DictationCapsuleContext(
        status: .savedWithoutCleanup(destination: "Inbox"),
        cleanupOutcome: .usedRaw,
        cleanupFallbackProvenance: .serviceFallback
      ),
      nil,
      .usedOriginal
    ),
    (
      "repairing",
      DictationCapsuleContext(status: .repairingModel),
      nil,
      .repairing
    ),
    (
      "attention",
      DictationCapsuleContext(
        status: .routingFailure(status: "Destination unavailable", message: "Could not route dictation.")
      ),
      .openDestination,
      .attention
    ),
    (
      "speech-recognition-access",
      DictationCapsuleContext(
        status: .failed("Speech recognition access is unavailable."),
        failureStage: .capture,
        failureKind: .speechRecognitionAccess
      ),
      nil,
      .speechRecognition
    ),
    (
      "persistence-copy",
      DictationCapsuleContext(
        status: .failed("Unable to save dictated text."),
        failureStage: .save,
        failureProvenance: .persistence,
        failureKind: .save
      ),
      .copy,
      .attention
    ),
    (
      "persistence-history",
      DictationCapsuleContext(
        status: .failed("Unable to save dictated text."),
        failureStage: .save,
        failureProvenance: .persistence,
        failureKind: .save
      ),
      .openHistory,
      .attention
    ),
    (
      "model-repair-failure",
      DictationCapsuleContext(
        status: .failed("The model could not be repaired."),
        failureStage: .polish,
        failureKind: .modelRepair
      ),
      .openHistory,
      .attention
    ),
  ]
  for kind in FleckErrorKind.allCases {
    #expect(errors.contains { $0.3 == kind })
  }

  for (errorName, context, action, kind) in errors {
    for (appearanceName, appearance, red, green, blue) in appearances {
      for (scaleName, scale) in scales {
        let panel = DictationCapsulePanel()
        panel.appearance = NSAppearance(named: appearance)
        let controller = DictationCapsuleController(panel: panel)
        controller.render(context, action: action)
        panel.orderOut(nil)
        if errorName == "used-original-reference-fixture" {
          #expect(controller.currentContext.status == .idle)
          #expect(controller.errorPresentationModel.presentation == nil)
          #expect(panel.frame.size != DictationCapsuleController.errorSurfaceSize)
          controller.errorPresentationModel.reconcile(
            context: context,
            action: action,
            entryFrame: nil,
            animated: false,
            reduceMotion: true
          )
          panel.setFrame(
            NSRect(origin: panel.frame.origin, size: DictationCapsuleController.errorSurfaceSize),
            display: false
          )
        }
        let host = try #require(panel.contentView)
        host.appearance = NSAppearance(named: appearance)
        host.layoutSubtreeIfNeeded()
        #expect(!panel.isVisible)
        #expect(abs(panel.frame.width - DictationCapsuleController.errorSurfaceSize.width) < 1)
        #expect(abs(panel.frame.height - DictationCapsuleController.errorSurfaceSize.height) < 1)
        #expect(controller.errorPresentationModel.presentation?.kind == kind)
        try saveCapture(
          of: host,
          name: "synthetic-offscreen-error-\(errorName)-\(appearanceName)-\(scaleName)",
          scale: scale,
          backgroundRed: red,
          backgroundGreen: green,
          backgroundBlue: blue,
          to: directory
        )
        controller.dismiss()
      }
    }
  }

  let phases: [(
    FleckErrorKind,
    [(phase: FleckErrorButtonPhase, interaction: FleckErrorButtonInteraction, title: String, name: String)]
  )] = [
    (.microphone, [
      (.default, .idle, "Settings", "default"),
      (.default, .hover, "Settings", "hover"),
      (.default, .focus, "Settings", "focus"),
      (.default, .pressed, "Settings", "pressed"),
      (.pending, .idle, "Opening…", "pending"),
    ]),
    (.dictation, [
      (.default, .idle, "Try again", "default"),
      (.default, .hover, "Try again", "hover"),
      (.default, .focus, "Try again", "focus"),
      (.default, .pressed, "Try again", "pressed"),
      (.pending, .idle, "Opening…", "pending"),
    ]),
    (.noSpeech, [
      (.default, .idle, "Try again", "default"),
      (.default, .hover, "Try again", "hover"),
      (.default, .focus, "Try again", "focus"),
      (.default, .pressed, "Try again", "pressed"),
      (.pending, .idle, "Opening…", "pending"),
    ]),
    (.attention, [
      (.default, .idle, "Destination", "default"),
      (.default, .hover, "Destination", "hover"),
      (.default, .focus, "Destination", "focus"),
      (.default, .pressed, "Destination", "pressed"),
      (.pending, .idle, "Destination", "pending"),
    ]),
    (.attention, [
      (.default, .idle, "Copy", "copy-default"),
      (.default, .hover, "Copy", "copy-hover"),
      (.default, .focus, "Copy", "copy-focus"),
      (.default, .pressed, "Copy", "copy-pressed"),
      (.pending, .idle, "Copying…", "copy-pending"),
      (.copied, .idle, "Copied", "copy-copied"),
      (.copyFailed, .idle, "Try again", "copy-failed"),
    ]),
    (.insertion, [
      (.default, .idle, "Copy text", "default"),
      (.default, .hover, "Copy text", "hover"),
      (.default, .focus, "Copy text", "focus"),
      (.default, .pressed, "Copy text", "pressed"),
      (.pending, .idle, "Copying…", "pending"),
      (.copied, .idle, "Copied", "copied"),
      (.copyFailed, .idle, "Try again", "copyFailed"),
      (.copyFailed, .hover, "Try again", "copyFailed-hover"),
      (.copyFailed, .focus, "Try again", "copyFailed-focus"),
      (.copyFailed, .pressed, "Try again", "copyFailed-pressed"),
    ]),
  ]

  let buttonSize = CGSize(
    width: CGFloat(FleckErrorLayout.approved.buttonWidth),
    height: CGFloat(FleckErrorLayout.approved.buttonHeight)
  )
  for (kind, kindPhases) in phases {
    for (phase, interaction, title, stateName) in kindPhases {
      for (appearanceName, appearance, red, green, blue) in appearances {
        for (scaleName, scale) in scales {
          let button = NSHostingView(rootView: FleckErrorButtonCapture(
            title: title,
            phase: phase,
            interaction: interaction
          ))
          button.frame = CGRect(origin: .zero, size: buttonSize)
          button.appearance = NSAppearance(named: appearance)
          try saveCapture(
            of: button,
            name: "synthetic-offscreen-button-\(kind)-\(stateName)-\(appearanceName)-\(scaleName)",
            scale: scale,
            backgroundRed: red,
            backgroundGreen: green,
            backgroundBlue: blue,
            to: directory
          )
        }
      }
    }
  }

  let midstate = FleckErrorGeometry.interpolatedButtonFeedback(
    from: .copyFailed,
    to: .hover,
    progress: 0.5
  )
  let midstateSize = CGSize(
    width: CGFloat(FleckErrorLayout.approved.buttonFaceWidth),
    height: CGFloat(FleckErrorLayout.approved.buttonFaceHeight)
  )
  for (appearanceName, appearance, red, green, blue) in appearances {
    for (scaleName, scale) in scales {
      let button = NSHostingView(rootView: FleckErrorButtonMidstateCapture(feedback: midstate))
      button.frame = CGRect(origin: .zero, size: midstateSize)
      button.appearance = NSAppearance(named: appearance)
      try saveCapture(
        of: button,
        name: "synthetic-offscreen-button-insertion-copyFailed-hover-midpoint-\(appearanceName)-\(scaleName)",
        scale: scale,
        backgroundRed: red,
        backgroundGreen: green,
        backgroundBlue: blue,
        to: directory
      )
    }
  }
}

@Test @MainActor
func FleckErrorCaptureBackgroundVariantsContainDistinctPixels() throws {
  let button = NSHostingView(rootView: FleckErrorButtonCapture(
    title: "Settings",
    phase: .default,
    interaction: .idle
  ))
  button.frame = CGRect(
    origin: .zero,
    size: CGSize(
      width: FleckErrorLayout.approved.buttonFaceWidth,
      height: FleckErrorLayout.approved.buttonFaceHeight
    )
  )
  let source = try bitmapCapture(of: button, scale: 1)
  let dark = try compositeCapture(source, red: 7.0 / 255, green: 8.0 / 255, blue: 11.0 / 255)
  let bright = try compositeCapture(
    source,
    red: 246.0 / 255,
    green: 246.0 / 255,
    blue: 246.0 / 255
  )
  #expect(dark.pixelsWide == bright.pixelsWide)
  #expect(dark.pixelsHigh == bright.pixelsHigh)
  var differingPixels = 0
  for y in 0..<dark.pixelsHigh {
    for x in 0..<dark.pixelsWide {
      let darkColor = try #require(dark.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
      let brightColor = try #require(bright.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
      if abs(darkColor.redComponent - brightColor.redComponent) > 0.01
        || abs(darkColor.greenComponent - brightColor.greenComponent) > 0.01
        || abs(darkColor.blueComponent - brightColor.blueComponent) > 0.01
      {
        differingPixels += 1
      }
    }
  }
  #expect(differingPixels > 0)
}
#endif
