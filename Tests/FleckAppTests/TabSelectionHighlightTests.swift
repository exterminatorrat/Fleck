import AppKit
import QuartzCore
import SwiftUI
import Testing

@testable import FleckApp

@MainActor private func selectionFixture() -> (
  destination: FluidTabDestinationView,
  first: ReorderSourceHostingView,
  second: ReorderSourceHostingView,
  firstID: UUID,
  secondID: UUID
) {
  let destination = FluidTabDestinationView(rootView: AnyView(EmptyView()))
  destination.frame = NSRect(x: 0, y: 0, width: 320, height: 37)
  let container = NSView(frame: NSRect(x: 17, y: 3, width: 280, height: 31))
  destination.addSubview(container)
  let firstID = UUID()
  let secondID = UUID()
  let first = ReorderSourceHostingView(
    rootView: AnyView(Color.clear.frame(width: 72, height: 27))
  )
  first.noteID = firstID
  first.frame = NSRect(x: 11, y: 2, width: 72, height: 27)
  container.addSubview(first)
  let second = ReorderSourceHostingView(
    rootView: AnyView(Color.clear.frame(width: 126, height: 27))
  )
  second.noteID = secondID
  second.frame = NSRect(x: 89, y: 2, width: 126, height: 27)
  container.addSubview(second)
  return (destination, first, second, firstID, secondID)
}

@MainActor private func selectionAnimation(
  _ destination: FluidTabDestinationView
) throws -> CAAnimationGroup {
  try #require(destination.selectionHighlightLayer.animation(forKey: "fleck.tab-selection") as? CAAnimationGroup)
}

@Test @MainActor
func nativeTabSelectionHighlightSnapsInitiallyThenAnimatesPositionAndBoundsTogether() throws {
  let fixture = selectionFixture()
  let color = NSColor.systemPurple.withAlphaComponent(0.22)

  fixture.destination.updateSelection(noteID: fixture.firstID, color: color, reduceMotion: false)
  #expect(fixture.destination.selectionHighlightLayer.frame == NSRect(x: 28, y: 5, width: 72, height: 27))
  #expect(fixture.destination.selectionHighlightLayer.animationKeys()?.isEmpty != false)

  fixture.destination.updateSelection(noteID: fixture.secondID, color: color, reduceMotion: false)
  let animation = try selectionAnimation(fixture.destination)
  let basicAnimations = (animation.animations ?? []).compactMap { $0 as? CABasicAnimation }
  let keyPaths = Set(basicAnimations.compactMap(\.keyPath))
  #expect(keyPaths == ["position", "bounds"])
  #expect(basicAnimations.allSatisfy { $0.duration == AppMotion.selectionDuration })
  #expect(animation.duration == AppMotion.selectionDuration)
  #expect(fixture.destination.selectionHighlightLayer.frame == NSRect(x: 106, y: 5, width: 126, height: 27))
  #expect(fixture.destination.selectionHighlightLayer.cornerRadius == 13.5)

  let expectedInterruptionOrigin = fixture.destination.selectionHighlightLayer.presentation()?.position
    ?? fixture.destination.selectionHighlightLayer.position
  fixture.destination.updateSelection(noteID: fixture.firstID, color: color, reduceMotion: false)
  let interruptedPosition = try #require(
    selectionAnimation(fixture.destination).animations?.compactMap { $0 as? CABasicAnimation }
      .first { $0.keyPath == "position" }
  )
  #expect(interruptedPosition.fromValue as? CGPoint == expectedInterruptionOrigin)
  #expect(fixture.destination.selectedCapsuleColor(for: fixture.first) != nil)
  #expect(fixture.destination.selectedCapsuleColor(for: fixture.second) == nil)
}

@Test @MainActor
func nativeTabSelectionUsesCenteredLabelFittingSizeInsideThirtySevenPointHost() throws {
  let noteID = UUID()
  let destination = FluidTabDestinationView(rootView: AnyView(EmptyView()))
  destination.frame = NSRect(x: 0, y: 0, width: 120, height: 37)
  let source = ReorderSourceHostingView(rootView: AnyView(
    Button(action: {}) {
      Text("A").lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
  ))
  source.sizingOptions = [.intrinsicContentSize]
  source.noteID = noteID
  let fittingSize = source.fittingSize
  source.frame = NSRect(x: 13, y: 0, width: fittingSize.width, height: 37)
  destination.addSubview(source)

  #expect(source.bounds.height == 37)
  #expect(fittingSize.height == 28)
  #expect(source.labelCapsuleRect == NSRect(x: 0, y: 4.5, width: fittingSize.width, height: 28))
  destination.updateSelection(
    noteID: noteID,
    color: NSColor.systemPurple.withAlphaComponent(0.22),
    reduceMotion: false
  )
  #expect(destination.selectionHighlightLayer.frame == NSRect(
    x: 13, y: 4.5, width: fittingSize.width, height: 28
  ))
}

@Test @MainActor
func unchangedNativeTabSelectionDoesNotRestartMovementAndReduceMotionCancelsIt() throws {
  let fixture = selectionFixture()
  let color = NSColor.systemBlue.withAlphaComponent(0.22)
  fixture.destination.updateSelection(noteID: fixture.firstID, color: color, reduceMotion: false)
  fixture.destination.updateSelection(noteID: fixture.secondID, color: color, reduceMotion: false)
  let initialBeginTime = try selectionAnimation(fixture.destination).beginTime

  fixture.destination.updateSelection(
    noteID: fixture.secondID,
    color: NSColor.systemGreen.withAlphaComponent(0.22),
    reduceMotion: false
  )
  #expect(try selectionAnimation(fixture.destination).beginTime == initialBeginTime)

  fixture.destination.updateSelection(
    noteID: fixture.secondID,
    color: NSColor.systemGreen.withAlphaComponent(0.22),
    reduceMotion: true
  )
  #expect(fixture.destination.selectionHighlightLayer.animationKeys()?.isEmpty != false)
  #expect(fixture.destination.selectionHighlightLayer.frame == NSRect(x: 106, y: 5, width: 126, height: 27))
}

@Test @MainActor
func nativeTabSelectionHandlesMissingDisplacedAndHiddenSources() {
  let fixture = selectionFixture()
  let color = NSColor.systemOrange.withAlphaComponent(0.22)
  fixture.destination.updateSelection(noteID: UUID(), color: color, reduceMotion: false)
  #expect(fixture.destination.selectionHighlightLayer.isHidden)

  fixture.destination.updateSelection(noteID: fixture.firstID, color: color, reduceMotion: false)
  fixture.first.setReorderDisplacement(34, animated: true)
  #expect(fixture.destination.selectionHighlightLayer.position.x == 98)
  #expect(fixture.destination.selectionHighlightLayer.animation(forKey: "fleck.tab-selection") != nil)

  fixture.first.setDraggingSourceHidden(true)
  #expect(fixture.destination.selectionHighlightLayer.opacity == 0)
  fixture.first.setDraggingSourceHidden(false)
  #expect(fixture.destination.selectionHighlightLayer.opacity == 1)
}

@Test @MainActor
func selectedNativeTabDragCompositePaintsCapsuleBehindCapturedContent() throws {
  let size = NSSize(width: 100, height: 37)
  let capsuleRect = NSRect(x: 12, y: 4.5, width: 76, height: 28)
  let capsuleColor = NSColor(calibratedRed: 0.9, green: 0.1, blue: 0.2, alpha: 0.8)
  let foregroundColor = NSColor(calibratedRed: 0.1, green: 0.4, blue: 0.9, alpha: 0.75)
  for scale in [1, 2] {
    for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
      let captured = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width) * scale,
        pixelsHigh: Int(size.height) * scale,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      ))
      captured.size = size
      for y in (16 * scale)..<(21 * scale) {
        for x in (46 * scale)..<(54 * scale) {
          captured.setColor(foregroundColor, atX: x, y: y)
        }
      }
      let appearance = NSAppearance(named: appearanceName) ?? NSAppearance.currentDrawing()
      let selected = try #require(ReorderSourceHostingView.compositedDraggingImage(
        captured: captured,
        size: size,
        appearance: appearance,
        selectedCapsuleColor: capsuleColor,
        selectedCapsuleRect: capsuleRect
      ))
      let selectedRep = try #require(
        selected.representations.first as? NSBitmapImageRep
      )

      #expect(selectedRep !== captured)
      #expect(selectedRep.colorSpace == captured.colorSpace)
      #expect(selectedRep.pixelsWide == captured.pixelsWide)
      #expect(selectedRep.pixelsHigh == captured.pixelsHigh)
      #expect(selected.size == size)
      #expect((captured.colorAt(x: 25 * scale, y: 18 * scale)?.alphaComponent ?? 1) < 0.02)
      #expect((selectedRep.colorAt(x: 4 * scale, y: 18 * scale)?.alphaComponent ?? 1) < 0.02)
      #expect((selectedRep.colorAt(x: 13 * scale, y: 5 * scale)?.alphaComponent ?? 1) < 0.02)

      let blankCapsule = try #require(
        selectedRep.colorAt(x: 25 * scale, y: 18 * scale)?.usingColorSpace(.sRGB)
      )
      let foreground = try #require(
        selectedRep.colorAt(x: 50 * scale, y: 18 * scale)?.usingColorSpace(.sRGB)
      )
      let colorSpace = selectedRep.colorSpace
      let source = try #require(
        captured.colorAt(x: 50 * scale, y: 18 * scale)?.usingColorSpace(colorSpace)
      )
      let backing = try #require(capsuleColor.usingColorSpace(colorSpace))
      let expectedAlpha = source.alphaComponent
        + backing.alphaComponent * (1 - source.alphaComponent)
      let expected = try #require(NSColor(
        colorSpace: colorSpace,
        components: [
          (source.redComponent * source.alphaComponent
            + backing.redComponent * backing.alphaComponent * (1 - source.alphaComponent))
            / expectedAlpha,
          (source.greenComponent * source.alphaComponent
            + backing.greenComponent * backing.alphaComponent * (1 - source.alphaComponent))
            / expectedAlpha,
          (source.blueComponent * source.alphaComponent
            + backing.blueComponent * backing.alphaComponent * (1 - source.alphaComponent))
            / expectedAlpha,
          expectedAlpha,
        ],
        count: 4
      ).usingColorSpace(.sRGB))
      #expect(abs(blankCapsule.alphaComponent - 0.8) < 0.02)
      #expect(abs(foreground.redComponent - expected.redComponent) < 0.02)
      #expect(abs(foreground.greenComponent - expected.greenComponent) < 0.02)
      #expect(abs(foreground.blueComponent - expected.blueComponent) < 0.02)
      #expect(abs(foreground.alphaComponent - expected.alphaComponent) < 0.02)

      let fullRect = try #require(ReorderSourceHostingView.compositedDraggingImage(
        captured: captured,
        size: size,
        appearance: appearance,
        selectedCapsuleColor: capsuleColor
      ))
      let fullRectRep = try #require(fullRect.representations.first as? NSBitmapImageRep)
      #expect((fullRectRep.colorAt(x: 4 * scale, y: 18 * scale)?.alphaComponent ?? 0) > 0.75)
    }
  }
}
