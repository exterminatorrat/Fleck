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
  let captured = try #require(NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: 80,
    pixelsHigh: 40,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  ))
  captured.size = NSSize(width: 40, height: 20)
  let appearance = NSAppearance(named: .aqua) ?? NSAppearance.currentDrawing()
  let plain = try #require(ReorderSourceHostingView.compositedDraggingImage(
    captured: captured, size: captured.size, appearance: appearance
  ))
  let selected = try #require(ReorderSourceHostingView.compositedDraggingImage(
    captured: captured,
    size: captured.size,
    appearance: appearance,
    selectedCapsuleColor: NSColor.systemRed.withAlphaComponent(0.8),
    selectedCapsuleRect: NSRect(x: 0, y: 4.5, width: 40, height: 11)
  ))
  let plainRep = try #require(plain.representations.first as? NSBitmapImageRep)
  let selectedRep = try #require(selected.representations.first as? NSBitmapImageRep)
  let plainCenter = try #require(plainRep.colorAt(x: 40, y: 20)?.usingColorSpace(.sRGB))
  let selectedCenter = try #require(selectedRep.colorAt(x: 40, y: 20)?.usingColorSpace(.sRGB))
  let plainEdge = try #require(plainRep.colorAt(x: 40, y: 2)?.usingColorSpace(.sRGB))
  let selectedEdge = try #require(selectedRep.colorAt(x: 40, y: 2)?.usingColorSpace(.sRGB))

  #expect(selectedCenter.greenComponent < plainCenter.greenComponent)
  #expect(selectedCenter.blueComponent < plainCenter.blueComponent)
  #expect(abs(selectedEdge.redComponent - plainEdge.redComponent) < 0.01)
  #expect(abs(selectedEdge.greenComponent - plainEdge.greenComponent) < 0.01)
  #expect(abs(selectedEdge.blueComponent - plainEdge.blueComponent) < 0.01)
}
