#if os(macOS)
import Testing
@testable import FleckApp

@Test func FleckPillSignalGeometryStaysContinuousAcrossPhaseReversalAndProcessingMorph() {
  let listeningFrame = FleckPillArtworkFrame(
    expansion: 1,
    energy: 0.72,
    phase: 0.37,
    activationMix: 0,
    processingMix: 0,
    signalOpacity: 1,
    glint: 0,
    glintOpacity: 0
  )
  let listening = FleckPillMotion.signalGeometry(listeningFrame)
  var reversedFrame = listeningFrame
  reversedFrame.phase = 0.12
  let reversed = FleckPillMotion.signalGeometry(reversedFrame)

  #expect(listening.points.count == 161)
  #expect(listening.points.first == FleckPillPoint(x: 56, y: 26.4))
  #expect(listening.points.last == FleckPillPoint(x: 168, y: 26.4))
  #expect(listening.points != reversed.points)
  #expect(listening.points.first == reversed.points.first)
  #expect(listening.points.last == reversed.points.last)
  #expect(listening.core.commands.count == 323)
  #expect(listening.scatter.commands.count == 323)
  #expect(listening.waveOpacity == 1)
  #expect(listening.lineOpacity == 0)

  var morphFrame = listeningFrame
  morphFrame.phase = 0.31
  morphFrame.activationMix = 0.42
  morphFrame.processingMix = 0.54
  let morph = FleckPillMotion.signalGeometry(morphFrame)

  #expect(morph.points.count == 161)
  #expect(morph.core.commands.count == 323)
  #expect(morph.line.commands.count == 161)
  #expect(morph.waveOpacity > 0)
  #expect(morph.waveOpacity < 1)
  #expect(morph.lineOpacity == 0.54)

  var processingFrame = listeningFrame
  processingFrame.processingMix = 1
  let processing = FleckPillMotion.signalGeometry(processingFrame)

  #expect(processing.waveOpacity == 0)
  #expect(processing.lineOpacity == 1)
  #expect(processing.line.commands.count == 2)
}
#endif
