#if os(macOS)
  import AppKit
  import FleckCore
  import Testing

  @testable import FleckApp

  @Test @MainActor func startingFeedbackIsVisibleAndTruthful() {
    let presentation = DictationCapsulePresentation(status: .arming)

    #expect(presentation.visibleText == "Starting")
    #expect(presentation.voiceOverText == "Starting dictation")
    #expect(presentation.visualMode == .arming)
    #expect(
      DictationCapsuleController.size(for: .arming).width
        > DictationCapsuleController.size(for: .idle).width
    )
  }

  @Test @MainActor func startingFeedbackRendersImmediatelyAcrossSupportedDocks() throws {
    #expect(
      DictationCapsuleMotion.contentDuration(
        from: .idle,
        to: .arming,
        reduceMotion: false
      ) == 0
    )
    #expect(
      DictationCapsuleMotion.contentDuration(
        from: .idle,
        to: .arming,
        reduceMotion: true
      ) == 0
    )
    #expect(
      DictationCapsuleMotion.shellDuration(
        from: .idle,
        to: .arming,
        reduceMotion: true
      ) == 0
    )

    for dock in DictationCapsuleDock.allCases {
      let panel = DictationCapsulePanel()
      let controller = DictationCapsuleController(panel: panel, markLoader: { nil })
      controller.presentIdle(dock: dock, onOpenFleck: {}, onDockChanged: { _ in })
      controller.render(.arming)
      #expect(controller.presentationModel.voiceOverLabel == "Starting dictation")
      #expect(!controller.fleckPillModel.usesFixedHost)
      #expect(panel.frame.size == DictationCapsuleController.startingSize)
      let host = try #require(panel.contentView)
      host.layoutSubtreeIfNeeded()

      let descendants = allDescendants(of: host)
      let startingText = descendants.first {
        $0.identifier?.rawValue == "fleck-rail-starting-text"
      }
      #expect(
        startingText != nil,
        "Expected visible Starting text at the bottom dock"
      )
      if let startingText {
        #expect(
          try hasBrightPixel(in: startingText, hostedBy: host),
          "Expected painted Starting text at the bottom dock"
        )
      }
      #expect(
        !descendants.contains { $0.identifier?.rawValue == "fleck-rail-waveform" },
        "Starting must not show a waveform at the bottom dock"
      )
      controller.dismiss()
    }
  }

  @MainActor
  private func allDescendants(of view: NSView) -> [NSView] {
    view.subviews + view.subviews.flatMap(allDescendants)
  }

  @MainActor
  private func hasBrightPixel(
    in startingText: NSView,
    hostedBy host: NSView
  ) throws -> Bool {
    let frame = startingText.convert(startingText.bounds, to: host)
    let imageRep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: imageRep)
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
        if min(color.redComponent, color.greenComponent, color.blueComponent) > 0.6 {
          return true
        }
      }
    }
    return false
  }
#endif
