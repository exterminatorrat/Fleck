#if os(macOS)
import AppKit
import Combine
import Foundation
import FleckCore
import Testing

@testable import FleckApp

@Test @MainActor func FleckCleanSuccessReturnsToIdleUnlessAChooserNeedsAttention() {
  let chooser = DictationCapsuleChooser(
    ambiguity: .init(
      captureID: UUID(),
      choices: [
        .init(
          destination: .init(noteID: UUID(), title: "Projects"),
          contextHint: "Synthetic roadmap"
        )
      ]
    )
  )
  let controller = DictationCapsuleController(
    panel: DictationCapsulePanel(),
    automaticallyAdvancesLivePill: false
  )
  defer { controller.dismiss() }
  controller.render(
    DictationCapsuleContext(
      status: .saved(destination: "Inbox"),
      cleanupOutcome: .cleaned
    ),
    action: .undo,
    chooser: chooser
  )

  #expect(controller.currentContext.status == .idle)
  #expect(controller.currentChooser == nil)
  #expect(controller.presentationModel.action == nil)
  #expect(controller.errorPresentationModel.presentation == nil)
  #expect(controller.fleckPillModel.usesFixedHost)
  #expect(controller.panel.frame.size == DictationCapsuleController.livePillHostSize)
}

@Test @MainActor func FleckCapsuleShowsChooserOnlyForMatchedTerminalRouteSessions() {
  let captureID = UUID()
  let noteID = UUID()
  let chooser = DictationCapsuleChooser(
    ambiguity: .init(
      captureID: captureID,
      choices: [
        .init(
          destination: .init(noteID: noteID, title: "Projects"),
          contextHint: "Synthetic roadmap"
        )
      ]
    )
  )
  let contexts = [
    DictationCapsuleContext(
      status: .saved(destination: "Projects"),
      sessionID: captureID,
      cleanupOutcome: .cleaned
    ),
    DictationCapsuleContext(
      status: .savedWithoutCleanup(destination: "Projects"),
      sessionID: captureID,
      cleanupOutcome: .usedRaw,
      cleanupFallbackProvenance: .serviceFallback
    ),
    DictationCapsuleContext(
      status: .routingFailure(status: "Needs attention", message: "Retry destination."),
      sessionID: captureID
    ),
  ]
  let controller = DictationCapsuleController(
    panel: DictationCapsulePanel(),
    automaticallyAdvancesLivePill: false
  )
  defer { controller.dismiss() }
  var selections = 0

  for context in contexts {
    controller.render(
      context,
      action: .undo,
      chooser: chooser,
      onChoice: { selectedCaptureID, selectedNoteID in
        if selectedCaptureID == captureID, selectedNoteID == noteID { selections += 1 }
      }
    )

    let withChooser = DictationCapsulePresentation(
      status: context.status,
      action: .undo,
      chooser: chooser,
      context: context
    )
    let withoutChooser = DictationCapsulePresentation(
      status: context.status,
      action: .undo,
      context: context
    )
    let needsRoutingRecovery: Bool = if case .routingFailure = context.status { true } else { false }
    #expect(controller.currentContext.status == (needsRoutingRecovery ? context.status : .idle))
    #expect(controller.currentChooser == (needsRoutingRecovery ? chooser : nil))
    #expect(controller.presentationModel.chooser == (needsRoutingRecovery ? chooser : nil))
    #expect(controller.panel.allowsActions == needsRoutingRecovery)
    #expect(controller.errorPresentationModel.presentation == nil)
    if needsRoutingRecovery {
      #expect(withChooser.widthCeiling > withoutChooser.widthCeiling)
    } else {
      #expect(withChooser.widthCeiling == withoutChooser.widthCeiling)
      #expect(withChooser.visibleText == nil)
    }
    controller.presentationModel.choiceHandler(captureID, noteID)
  }

  #expect(selections == 1)
}

@Test @MainActor func FleckCapsuleRejectsStaleChooserAndKeepsUsedOriginalFallbackVisible() {
  let captureID = UUID()
  let staleSessionID = UUID()
  let noteID = UUID()
  let chooser = DictationCapsuleChooser(
    ambiguity: .init(
      captureID: captureID,
      choices: [
        .init(
          destination: .init(noteID: noteID, title: "Projects"),
          contextHint: "Synthetic roadmap"
        )
      ]
    )
  )
  let controller = DictationCapsuleController(
    panel: DictationCapsulePanel(),
    automaticallyAdvancesLivePill: false
  )
  defer { controller.dismiss() }
  var selections = 0
  let onChoice: @MainActor (UUID, UUID?) -> Void = { _, _ in selections += 1 }
  let staleContext = DictationCapsuleContext(
    status: .saved(destination: "Inbox"),
    detailText: "Stale routing hint",
    compactDetailText: "Stale route",
    sessionID: staleSessionID
  )
  let stalePresentation = DictationCapsulePresentation(
    status: staleContext.status,
    action: .undo,
    chooser: chooser,
    context: staleContext
  )
  let stalePresentationWithoutChooser = DictationCapsulePresentation(
    status: staleContext.status,
    action: .undo,
    context: staleContext
  )

  controller.render(
    staleContext,
    action: .undo,
    chooser: chooser,
    onChoice: onChoice
  )

  #expect(controller.currentContext.status == .idle)
  #expect(controller.currentContext.detailText == nil)
  #expect(controller.currentContext.compactDetailText == nil)
  #expect(controller.currentChooser == nil)
  #expect(controller.presentationModel.chooser == nil)
  #expect(controller.presentationModel.voiceOverLabel == "Fleck dictation ready")
  #expect(stalePresentation.widthCeiling == stalePresentationWithoutChooser.widthCeiling)
  #expect(stalePresentation.secondaryVisibleText == nil)
  #expect(stalePresentation.voiceOverText == "Fleck dictation ready")
  #expect(!controller.panel.allowsActions)
  #expect(controller.errorPresentationModel.presentation == nil)
  controller.selectRoutingChoice(captureID: captureID, noteID: noteID)
  controller.presentationModel.choiceHandler(captureID, noteID)
  #expect(selections == 0)

  let fallbackContext = DictationCapsuleContext(
    status: .savedWithoutCleanup(destination: "Inbox"),
    detailText: "Stale routing failure",
    compactDetailText: "Stale route",
    sessionID: staleSessionID,
    cleanupOutcome: .usedRaw,
    cleanupFallbackProvenance: .serviceFallback
  )
  controller.render(
    fallbackContext,
    action: .undo,
    chooser: chooser,
    onChoice: onChoice
  )

  #expect(controller.currentContext.status == .idle)
  #expect(controller.currentContext.detailText == nil)
  #expect(controller.currentContext.compactDetailText == nil)
  #expect(controller.currentChooser == nil)
  #expect(controller.presentationModel.chooser == nil)
  #expect(controller.presentationModel.voiceOverLabel == "Fleck dictation ready")
  #expect(controller.errorPresentationModel.presentation == nil)
  controller.selectRoutingChoice(captureID: captureID, noteID: noteID)
  controller.presentationModel.choiceHandler(captureID, noteID)
  #expect(selections == 0)
}

@Test @MainActor func FleckSuccessfulPersistenceReturnsToStandbyForEveryCleanupOutcome() {
  let cleanContext = DictationCapsuleContext(
    status: .saved(destination: "Inbox"),
    cleanupOutcome: .cleaned
  )
  let coarseRawContext = DictationCapsuleContext(
    status: .saved(destination: "Inbox")
  )
  let serviceFallbackContext = DictationCapsuleContext(
    status: .savedWithoutCleanup(destination: "Inbox"),
    cleanupOutcome: .usedRaw,
    cleanupFallbackProvenance: .serviceFallback
  )

  for context in [cleanContext, coarseRawContext, serviceFallbackContext] {
    #expect(context.presentationContext(with: nil).status == .idle)
    let presentation = DictationCapsulePresentation(status: context.status, context: context)
    #expect(presentation.visibleText == nil)
    #expect(presentation.voiceOverText == "Fleck dictation ready")
  }
  let failureContext = DictationCapsuleContext(status: .failed("Synthetic save failure"), failureStage: .save)
  #expect(failureContext.presentationContext(with: nil).status == failureContext.status)
}

@Test @MainActor func FleckPillArmingStartsShellExpansionWithoutSyntheticVoiceActivity() {
  let model = FleckPillLivePresentationModel()
  model.presentStandby(at: 10, renderedFrame: nil, animated: false, reduceMotion: false)
  let sessionID = UUID()

  model.presentArming(sessionID: sessionID, at: 11, reduceMotion: false)

  #expect(model.state == .opening)
  #expect(model.frame.expansion == 0)
  #expect(model.needsAnimation)
  #expect(model.frame.energy == 0)
  #expect(model.frame.activationMix == 0)
  #expect(model.frame.processingMix == 0)
  model.tick(at: 11.16, displayedEnergy: 0)
  #expect(model.needsAnimation)
  #expect(model.frame.expansion > 0.2)
  #expect(model.frame.expansion < 1)
  #expect(model.frame.signalOpacity > 0)
  #expect(model.frame.signalOpacity < 0.32)
  #expect(model.frame.energy == 0)
  #expect(model.frame.activationMix == 0)
  model.tick(at: 11.32, displayedEnergy: 0)
  #expect(model.state == .arming)
  #expect(model.frame.expansion == 1)
  #expect(model.frame.energy == 0)
  #expect(model.frame.activationMix == 0)
  #expect(!model.needsAnimation)
}

@Test @MainActor func FleckPillLiveWaveRateDoesNotChangeShellExpansionOrClosing() {
  let model = FleckPillLivePresentationModel()
  let sessionID = UUID()
  model.presentArming(sessionID: sessionID, at: 10, reduceMotion: false)

  model.tick(at: 10.16, displayedEnergy: 0)
  #expect(abs(model.frame.expansion - 0.5) < 0.000001)
  model.tick(at: 10.32, displayedEnergy: 0)
  #expect(model.frame.expansion == 1)

  model.presentStandby(at: 10.32, renderedFrame: model.frame, animated: true, reduceMotion: false)
  #expect(model.state == .closing)
  model.tick(at: 10.48, displayedEnergy: 0)
  #expect(abs(model.frame.expansion - 0.5) < 0.000001)
  model.tick(at: 10.65, displayedEnergy: 0)

  #expect(model.state == .standby)
  #expect(model.frame.expansion == 0)
  #expect(model.frame.phase == 0)
  #expect(!model.needsAnimation)
}

@Test @MainActor
func FleckPillReducedMotionKeepsGeometryStaticAcrossTransitionsAndStopsDecorativeTicks() {
  let model = FleckPillLivePresentationModel()
  let sessionID = UUID()
  model.presentStandby(at: 10, renderedFrame: nil, animated: false, reduceMotion: true)

  model.presentArming(sessionID: sessionID, at: 11, reduceMotion: true)

  #expect(model.state == .arming)
  #expect(model.frame.expansion == 1)
  #expect(model.frame.signalOpacity == 0.32)
  #expect(!model.needsAnimation)
  let armingFrame = model.frame
  let armingGeneration = model.renderGeneration
  model.tick(at: 11.5, displayedEnergy: 0)
  #expect(model.frame == armingFrame)
  #expect(model.renderGeneration == armingGeneration)
  #expect(!model.needsAnimation)

  model.presentListening(
    sessionID: sessionID,
    at: 12,
    displayedEnergy: 0.4,
    reduceMotion: true
  )

  #expect(model.state == .listening)
  #expect(model.frame.expansion == 1)
  #expect(model.frame.signalOpacity == 1)
  #expect(model.frame.activationMix == 0)
  #expect(model.frame.energy == 0.4)
  #expect(model.frame.phase == 0)
  #expect(model.needsAnimation)
  model.tick(at: 12.2, displayedEnergy: 0.8)
  #expect(model.frame.expansion == 1)
  #expect(model.frame.energy == 0.8)
  #expect(model.frame.phase == 0)
  #expect(model.needsAnimation)
  let listeningFrame = model.frame
  let listeningGeneration = model.renderGeneration
  model.tick(at: 42.2, displayedEnergy: 0.8)
  #expect(model.frame == listeningFrame)
  #expect(model.renderGeneration == listeningGeneration)
  #expect(model.needsAnimation)

  var settledListeningFrame = listeningFrame
  settledListeningFrame.energy = 0
  model.tick(at: 42.3, displayedEnergy: 0)
  #expect(model.frame == settledListeningFrame)
  #expect(model.renderGeneration > listeningGeneration)
  #expect(!model.needsAnimation)

  model.presentProcessing(
    sessionID: sessionID,
    at: 42.4,
    renderedFrame: model.frame,
    displayedEnergy: 0.8,
    reduceMotion: true
  )

  #expect(model.state == .processing)
  #expect(model.frame.expansion == 1)
  #expect(model.frame.processingMix == 1)
  #expect(model.frame.glint == 0)
  #expect(model.frame.glintOpacity == 0)
  #expect(!model.needsAnimation)
  let processingFrame = model.frame
  let processingGeneration = model.renderGeneration
  model.tick(at: 52.3, displayedEnergy: 0)
  #expect(model.frame == processingFrame)
  #expect(model.renderGeneration == processingGeneration)
  #expect(!model.needsAnimation)

  model.presentStandby(at: 52.4, renderedFrame: nil, animated: true, reduceMotion: true)

  #expect(model.state == .standby)
  #expect(model.frame.expansion == 0)
  #expect(model.frame.energy == 0)
  #expect(model.frame.phase == 0)
  #expect(model.frame.glint == 0)
  #expect(model.frame.glintOpacity == 0)
  #expect(!model.needsAnimation)
  let standbyGeneration = model.renderGeneration
  model.tick(at: 62.4, displayedEnergy: 1)
  #expect(model.state == .standby)
  #expect(model.frame.expansion == 0)
  #expect(model.renderGeneration == standbyGeneration)
  #expect(!model.needsAnimation)
}

@Test @MainActor func FleckPillSilentCallbacksDoNotPublishUnchangedFrames() {
  for reduceMotion in [false, true] {
    let model = FleckPillLivePresentationModel()
    let sessionID = UUID()
    model.presentListening(
      sessionID: sessionID,
      at: 10,
      displayedEnergy: 0.5,
      reduceMotion: reduceMotion
    )
    model.tick(at: 11, displayedEnergy: 0, reduceMotion: reduceMotion)
    #expect(model.frame.energy == 0)
    #expect(!model.needsAnimation)

    var publicationCount = 0
    let observation = model.objectWillChange.sink { publicationCount += 1 }
    let settledFrame = model.frame
    let settledGeneration = model.renderGeneration
    for index in 1...120 {
      model.presentListening(
        sessionID: sessionID,
        at: 11 + Double(index) / 60,
        displayedEnergy: 0,
        reduceMotion: reduceMotion
      )
    }

    #expect(publicationCount == 0)
    #expect(model.frame == settledFrame)
    #expect(model.renderGeneration == settledGeneration)
    #expect(!model.needsAnimation)

    model.presentListening(
      sessionID: sessionID,
      at: 14,
      displayedEnergy: 0.5,
      reduceMotion: reduceMotion
    )
    #expect(model.frame.energy == 0.5)
    #expect(publicationCount > 0)
    #expect(model.needsAnimation)
    withExtendedLifetime(observation) {}
  }
}

@Test @MainActor func FleckPillChangedFrameTicksPublishOnlyOnce() {
  let model = FleckPillLivePresentationModel()
  model.presentListening(
    sessionID: UUID(),
    at: 10,
    displayedEnergy: 0.5,
    reduceMotion: false
  )
  var frameCount = 0
  var publicationCount = 0
  let frameObservation = model.$frame.dropFirst().sink { _ in frameCount += 1 }
  let objectObservation = model.objectWillChange.sink { publicationCount += 1 }
  let initialGeneration = model.renderGeneration

  for index in 1...120 {
    model.tick(at: 10 + Double(index) / 60, displayedEnergy: 0.5)
  }

  #expect(frameCount == 120)
  #expect(publicationCount == 120)
  #expect(model.renderGeneration == initialGeneration + 120)
  withExtendedLifetime(frameObservation) {}
  withExtendedLifetime(objectObservation) {}
}

@Test @MainActor func FleckPillWavePhasePausesAtSettledSilenceAndResumesContinuously() {
  let model = FleckPillLivePresentationModel()
  let sessionID = UUID()
  model.presentListening(
    sessionID: sessionID,
    at: 10,
    displayedEnergy: 0,
    reduceMotion: false
  )

  model.tick(at: 10.1, displayedEnergy: 0.5)
  #expect(model.frame.phase == 0)
  model.tick(at: 10.2, displayedEnergy: 0.5)
  #expect(abs(model.frame.phase - 0.6075) < 0.000001)
  model.tick(at: 10.3, displayedEnergy: 0.5)
  let phaseBeforeSilence = model.frame.phase
  model.tick(at: 10.4, displayedEnergy: 0)
  let settledPhase = model.frame.phase
  #expect(abs(settledPhase - phaseBeforeSilence - 0.6075) < 0.000001)
  #expect(model.frame.energy == 0)
  #expect(!model.needsAnimation)

  let settledGeneration = model.renderGeneration
  model.tick(at: 30, displayedEnergy: 0)
  #expect(model.frame.phase == settledPhase)
  #expect(model.renderGeneration == settledGeneration)
  #expect(!model.needsAnimation)

  model.tick(at: 30.1, displayedEnergy: 0.5)
  #expect(model.frame.phase == settledPhase)
  model.tick(at: 30.2, displayedEnergy: 0.5)
  #expect(abs(model.frame.phase - settledPhase - 0.6075) < 0.000001)
}

@Test @MainActor func FleckPillLivePhaseMatches6_075AcrossTickCadences() {
  func phaseAfterTicks(interval: TimeInterval, count: Int) -> Double {
    let model = FleckPillLivePresentationModel()
    model.presentListening(
      sessionID: UUID(),
      at: 10,
      displayedEnergy: 0.7,
      reduceMotion: false
    )
    for index in 1...count {
      model.tick(at: 10 + Double(index) * interval, displayedEnergy: 0.7)
    }
    return model.frame.phase
  }

  let sixtyFPSPhase = phaseAfterTicks(interval: 1.0 / 60, count: 24)
  let thirtyFPSPhase = phaseAfterTicks(interval: 1.0 / 30, count: 12)
  let expectedPhase = 6.075 * 0.4

  #expect(FleckPillMotion.wavePhaseRate == 2.7)
  #expect(FleckPillMotion.liveWavePhaseRate == 6.075)
  #expect(abs(sixtyFPSPhase - expectedPhase) < 0.000000001)
  #expect(abs(thirtyFPSPhase - expectedPhase) < 0.000000001)
  #expect(abs(sixtyFPSPhase - thirtyFPSPhase) < 0.000000001)
}

@Test func FleckPillPositiveWavePhaseMovesCarrierRightToLeft() {
  let initial = FleckPillGeometry.waveSamples(energy: 0.7, phase: 0)
  let advanced = FleckPillGeometry.waveSamples(energy: 0.7, phase: 0.405)
  let bestShift =
    (-8...8)
    .map { shift in
      (
        shift: shift,
        difference: (16..<145).reduce(0.0) { total, index in
          total + abs(advanced[index].y - initial[index + shift].y)
        }
      )
    }
    .min { $0.difference < $1.difference }?
    .shift ?? 0

  #expect(bestShift > 0)
}

@Test @MainActor func FleckPillIdleAndHiddenStatesDoNotScheduleTicks() {
  let model = FleckPillLivePresentationModel()
  model.presentStandby(at: 40, renderedFrame: nil, animated: false, reduceMotion: false)
  #expect(model.state == .standby)
  #expect(model.frame.expansion == 0)
  #expect(!model.needsAnimation)
  let standbyGeneration = model.renderGeneration
  model.tick(at: 400, displayedEnergy: 0)
  #expect(model.renderGeneration == standbyGeneration)

  model.hide()
  #expect(model.state == .hidden)
  #expect(!model.needsAnimation)
  let hiddenGeneration = model.renderGeneration
  model.tick(at: 4_000, displayedEnergy: 0)
  #expect(model.renderGeneration == hiddenGeneration)
}

@Test @MainActor func FleckPillListeningBeginsVoiceActivityOnlyForListeningPhase() {
  let model = FleckPillLivePresentationModel()
  let sessionID = UUID()
  model.presentArming(sessionID: sessionID, at: 20, reduceMotion: false)
  model.tick(at: 20.32, displayedEnergy: 0)

  #expect(model.state == .arming)
  #expect(model.frame.energy == 0)
  #expect(model.frame.activationMix == 0)

  model.presentListening(
    sessionID: sessionID,
    at: 20.4,
    displayedEnergy: 0.65,
    reduceMotion: false
  )

  #expect(model.state == .listening)
  #expect(model.frame.energy == 0.65)
  #expect(model.frame.activationMix == 1)
}

@Test @MainActor func FleckPillProcessingUsesLatestConsumedCanvasFrame() {
  let model = FleckPillLivePresentationModel()
  let sessionID = UUID()
  model.presentListening(
    sessionID: sessionID,
    at: 30,
    displayedEnergy: 0.6,
    reduceMotion: false
  )
  let consumedFrame = FleckPillArtworkFrame(
    expansion: 0.87,
    energy: 0.43,
    phase: 7.25,
    activationMix: 0.31,
    processingMix: 0.08,
    signalOpacity: 0.74,
    glint: 0,
    glintOpacity: 0
  )
  model.renderReceipt.record(consumedFrame, generation: 8, sessionID: sessionID)
  model.renderReceipt.record(
    FleckPillArtworkFrame(
      expansion: 0.1,
      energy: 0,
      phase: 0,
      activationMix: 0,
      processingMix: 0,
      signalOpacity: 0,
      glint: 0,
      glintOpacity: 0
    ),
    generation: 7,
    sessionID: UUID()
  )

  model.presentProcessing(
    sessionID: sessionID,
    at: 30.1,
    renderedFrame: model.displayedFrame(for: sessionID),
    displayedEnergy: 0.1,
    reduceMotion: false
  )

  #expect(model.state == .processing)
  #expect(model.frame.expansion == consumedFrame.expansion)
  #expect(model.frame.energy == consumedFrame.energy)
  #expect(model.frame.phase == consumedFrame.phase)
  #expect(model.frame.activationMix == consumedFrame.activationMix)
  #expect(model.frame.signalOpacity == consumedFrame.signalOpacity)
  #expect(model.frame.processingMix == consumedFrame.processingMix)

  model.tick(at: 30.4, displayedEnergy: 0.1)
  #expect(model.frame.energy == consumedFrame.energy)
  #expect(model.frame.phase == consumedFrame.phase)
  #expect(model.frame.processingMix == 1)
}

@Test @MainActor func FleckPillStaleEarlierPhaseDoesNotRewindCurrentSession() {
  let model = FleckPillLivePresentationModel()
  let sessionID = UUID()
  model.presentArming(sessionID: sessionID, at: 40, reduceMotion: false)
  model.presentListening(
    sessionID: sessionID,
    at: 40.4,
    displayedEnergy: 0.5,
    reduceMotion: false
  )
  let listeningFrame = model.frame

  model.presentArming(sessionID: sessionID, at: 40.5, reduceMotion: false)

  #expect(model.state == .listening)
  #expect(model.frame == listeningFrame)
}

@Test @MainActor func DictationCapsuleUsesRealCoordinatorPhasesAndRetainsLegacyFallbacks() throws {
  let panel = DictationCapsulePanel()
  let controller = DictationCapsuleController(
    panel: panel,
    monotonicNow: { 50 },
    automaticallyAdvancesLivePill: false
  )
  controller.setReduceMotionOverrideForTesting(false)
  defer { controller.dismiss() }
  let sessionID = UUID()
  let captureContext = DictationCoordinatorContext(
    sessionID: sessionID,
    mode: .smartCapture,
    pipelineStage: .capture,
    cleanupOutcome: nil,
    failureStage: nil
  )
  let armingEvent = DictationCoordinatorEvent(
    phase: .arming,
    terminal: nil,
    context: captureContext
  )
  controller.render(
    DictationCapsuleContext(
      status: .arming,
      sessionID: sessionID,
      mode: .smartCapture,
      pipelineStage: .capture
    ),
    coordinatorEvent: armingEvent
  )

  #expect(controller.fleckPillModel.state == .opening)
  #expect(controller.fleckPillModel.frame.expansion == 0)
  #expect(controller.fleckPillModel.frame.energy == 0)
  #expect(controller.fleckPillModel.frame.activationMix == 0)

  let listeningEvent = DictationCoordinatorEvent(
    phase: .listening(mode: .smartCapture, engine: .standard),
    terminal: nil,
    context: captureContext
  )
  controller.render(
    DictationCapsuleContext(
      status: .listening,
      sessionID: sessionID,
      mode: .smartCapture,
      pipelineStage: .capture
    ),
    coordinatorEvent: listeningEvent
  )

  #expect(controller.fleckPillModel.state == .listening)
  #expect(controller.fleckPillModel.frame.energy == 0)
  #expect(controller.fleckPillModel.frame.activationMix == 1)

  let terminalEvent = DictationCoordinatorEvent(
    phase: .failed("capture failed"),
    terminal: .failed("capture failed"),
    context: captureContext
  )
  panel.orderOut(nil)
  controller.render(
    DictationCapsuleContext(
      status: .failed("capture failed"),
      sessionID: sessionID,
      mode: .smartCapture,
      pipelineStage: .capture,
      failureStage: .capture
    ),
    coordinatorEvent: terminalEvent
  )
  let failedContext = DictationCapsuleContext(
    status: .failed("capture failed"),
    sessionID: sessionID,
    mode: .smartCapture,
    pipelineStage: .capture,
    failureStage: .capture
  )
  let failedPresentation = DictationCapsulePresentation(status: failedContext.status, context: failedContext)
  #expect(controller.fleckPillModel.state == .hidden)
  #expect(!controller.fleckPillModel.isVisible)
  #expect(!controller.fleckPillModel.needsAnimation)
  #expect(!controller.fleckPillModel.usesFixedHost)
  #expect(controller.errorPresentationModel.presentation?.kind == .dictation)
  #expect(!panel.hasShadow)
  #expect(failedPresentation.visibleText == "Dictation failed")
  #expect(controller.presentationModel.voiceOverLabel == "Dictation failed: capture failed")

  let visibleFrame = try #require(
    panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame
  )
  let expectedErrorFrame = DictationCapsuleController.errorSurfaceFrame(for: .bottom, in: visibleFrame)
  let host = try #require(panel.contentView)
  host.layoutSubtreeIfNeeded()
  let expectedIntegerPanelWidth = CGFloat(
    Int(FleckErrorLayout.approved.canvasWidth.rounded(.up))
  )
  #expect(expectedIntegerPanelWidth == 404)
  #expect(abs(panel.frame.width - expectedIntegerPanelWidth) <= 0.5)
  #expect(abs(panel.frame.height - expectedErrorFrame.height) < 0.5)
  #expect(abs(host.bounds.width - expectedIntegerPanelWidth) <= 0.5)
  #expect(abs(host.bounds.height - expectedErrorFrame.height) < 0.5)

  let hiddenGeneration = controller.fleckPillModel.renderGeneration
  controller.render(
    DictationCapsuleContext(
      status: .listening,
      sessionID: sessionID,
      mode: .smartCapture,
      pipelineStage: .capture
    ),
    coordinatorEvent: listeningEvent
  )
  #expect(controller.currentContext.status == .failed("capture failed"))
  #expect(controller.presentationModel.context.status == .failed("capture failed"))
  #expect(controller.fleckPillModel.renderGeneration == hiddenGeneration)
  #expect(controller.fleckPillModel.state == .hidden)
  #expect(!controller.fleckPillModel.isVisible)
  #expect(!controller.fleckPillModel.needsAnimation)
  #expect(!controller.fleckPillModel.usesFixedHost)
  #expect(!panel.hasShadow)
  #expect(abs(panel.frame.width - expectedIntegerPanelWidth) <= 0.5)
  #expect(abs(panel.frame.height - expectedErrorFrame.height) < 0.5)

  let routingContext = DictationCapsuleContext(
    status: .routingFailure(status: "Routing failed", message: "Destination could not be reached."),
    sessionID: sessionID,
    failureStage: .organize,
    failureKind: .generic
  )
  controller.render(routingContext)
  let routingPresentation = try #require(controller.errorPresentationModel.presentation)
  #expect(routingPresentation.kind == .attention)
  #expect(routingPresentation.message == "Routing failed")
  #expect(routingPresentation.actionTitle == nil)
  #expect(controller.presentationModel.action == nil)
  #expect(FleckErrorLayout.approved.visibleWidth == 384)
  #expect(FleckErrorLayout.approved.visibleHeight == 44)
  #expect(!panel.hasShadow)
  let routingHost = try #require(panel.contentView)
  routingHost.layoutSubtreeIfNeeded()
  #expect(abs(panel.frame.width - expectedIntegerPanelWidth) <= 0.5)
  #expect(abs(panel.frame.height - expectedErrorFrame.height) < 0.5)
  #expect(abs(routingHost.bounds.width - expectedIntegerPanelWidth) <= 0.5)
  #expect(abs(routingHost.bounds.height - expectedErrorFrame.height) < 0.5)

  controller.setDock(.left)
  #expect(controller.fleckPillModel.state == .hidden)
  #expect(!controller.fleckPillModel.usesFixedHost)

  let earlyReleaseSessionID = UUID()
  let earlyReleaseContext = DictationCoordinatorContext(
    sessionID: earlyReleaseSessionID,
    mode: .smartCapture,
    pipelineStage: .capture,
    cleanupOutcome: nil,
    failureStage: nil
  )
  let earlyReleaseArmingEvent = DictationCoordinatorEvent(
    phase: .arming,
    terminal: nil,
    context: earlyReleaseContext
  )
  controller.render(
    DictationCapsuleContext(
      status: .arming,
      sessionID: earlyReleaseSessionID,
      mode: .smartCapture,
      pipelineStage: .capture
    ),
    coordinatorEvent: earlyReleaseArmingEvent
  )
  controller.dismiss()
  controller.presentIdle(dock: .bottom, onOpenFleck: {}, onDockChanged: { _ in })
  #expect(controller.fleckPillModel.state == .standby)

  let delayedReadyEvent = DictationCoordinatorEvent(
    phase: .listening(mode: .smartCapture, engine: .standard),
    terminal: nil,
    context: earlyReleaseContext
  )
  controller.render(
    DictationCapsuleContext(
      status: .listening,
      sessionID: earlyReleaseSessionID,
      mode: .smartCapture,
      pipelineStage: .capture
    ),
    coordinatorEvent: delayedReadyEvent
  )
  #expect(controller.currentContext.status == .idle)
  #expect(controller.fleckPillModel.state == .standby)
}

@Test func FleckPillBottomFrameStaysAttachedAndCentered() {
  let visibleFrame = CGRect(x: 120, y: 240, width: 1_200, height: 900)
  let frame = DictationCapsuleController.livePillFrame(in: visibleFrame)

  #expect(frame.size == DictationCapsuleController.livePillHostSize)
  #expect(frame.midX == visibleFrame.midX)
  #expect(frame.minY == visibleFrame.minY)
}
#endif
