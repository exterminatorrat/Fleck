#if os(macOS)
import Combine
import Foundation

struct FleckPillRenderSnapshot: Equatable, Sendable {
  let frame: FleckPillArtworkFrame
  let generation: UInt64
  let sessionID: UUID?
}

final class FleckPillRenderReceipt: @unchecked Sendable {
  private let lock = NSLock()
  private var lastSnapshot: FleckPillRenderSnapshot?

  func record(_ frame: FleckPillArtworkFrame, generation: UInt64, sessionID: UUID?) {
    lock.lock()
    defer { lock.unlock() }
    guard generation >= (lastSnapshot?.generation ?? 0) else { return }
    lastSnapshot = FleckPillRenderSnapshot(
      frame: frame,
      generation: generation,
      sessionID: sessionID
    )
  }

  func snapshot(for sessionID: UUID) -> FleckPillRenderSnapshot? {
    lock.lock()
    defer { lock.unlock() }
    guard lastSnapshot?.sessionID == sessionID else { return nil }
    return lastSnapshot
  }
}

enum FleckPillLiveState: Equatable {
  case hidden
  case standby
  case opening
  case arming
  case listening
  case processing
  case closing
}

@MainActor
final class FleckPillLivePresentationModel: ObservableObject {
  private struct Tween {
    let from: Double
    let to: Double
    let start: TimeInterval
    let duration: TimeInterval

    func value(at now: TimeInterval) -> Double {
      guard duration > 0 else { return to }
      let progress = FleckPillGeometry.smooth((now - start) / duration)
      return FleckPillGeometry.mix(from, to, progress)
    }

  }

  @Published private(set) var frame = FleckPillArtworkFrame(
    expansion: 0,
    energy: 0,
    phase: 0,
    activationMix: 0,
    processingMix: 0,
    signalOpacity: 0,
    glint: 0,
    glintOpacity: 0
  )
  @Published private(set) var state: FleckPillLiveState = .hidden

  let renderReceipt = FleckPillRenderReceipt()
  private(set) var sessionID: UUID?
  private(set) var renderGeneration: UInt64 = 0
  private(set) var lifecycleGeneration: UInt64 = 0
  private var currentPhaseRank = -1
  private var expansionTween: Tween?
  private var signalOpacityTween: Tween?
  private var activationTween: Tween?
  private var processingTween: Tween?
  private var accumulatedPhase = 0.0
  private var phaseUpdateAt: TimeInterval?
  private var processingStartedAt: TimeInterval?
  private var frozenEnergy: Double = 0
  private var frozenPhase: Double = 0
  private var closesToStandby = false
  private var reduceMotionEnabled = false

  var isVisible: Bool { state != .hidden }

  var usesFixedHost: Bool {
    switch state {
    case .standby, .opening, .arming, .listening, .processing:
      true
    case .closing:
      closesToStandby
    case .hidden:
      false
    }
  }

  var needsAnimation: Bool {
    if reduceMotionEnabled { return state == .listening && frame.energy > 0 }
    return expansionTween != nil
      || signalOpacityTween != nil
      || activationTween != nil
      || processingTween != nil
      || state == .processing
      || (state == .listening && frame.energy > 0)
  }

  func displayedFrame(for sessionID: UUID) -> FleckPillArtworkFrame? {
    renderReceipt.snapshot(for: sessionID)?.frame
  }

  func presentStandby(
    at now: TimeInterval,
    renderedFrame: FleckPillArtworkFrame?,
    animated: Bool,
    reduceMotion: Bool
  ) {
    if let renderedFrame { frame = renderedFrame }
    tick(at: now, displayedEnergy: frame.energy, reduceMotion: reduceMotion)
    if state == .standby, sessionID == nil { return }
    lifecycleGeneration &+= 1
    sessionID = nil
    currentPhaseRank = -1
    accumulatedPhase = 0
    phaseUpdateAt = nil
    processingStartedAt = nil
    activationTween = nil
    processingTween = nil
    closesToStandby = true
    if !animated || !isVisible || reduceMotion {
      frame = closedFrame(expansion: 0)
      expansionTween = nil
      signalOpacityTween = nil
      state = .standby
      publish()
      return
    }
    expansionTween = Tween(from: frame.expansion, to: 0, start: now, duration: 0.32)
    signalOpacityTween = Tween(from: frame.signalOpacity, to: 0, start: now, duration: 0.32)
    state = .closing
    publish()
  }

  func presentArming(
    sessionID: UUID,
    at now: TimeInterval,
    reduceMotion: Bool
  ) {
    guard acceptPhase(sessionID: sessionID, rank: 0) else { return }
    tick(at: now, displayedEnergy: 0, reduceMotion: reduceMotion)
    let isNewSession = self.sessionID != sessionID
    if isNewSession {
      if state != .standby, !(state == .closing && closesToStandby), !isVisible {
        frame = closedFrame(expansion: 0)
      }
      self.sessionID = sessionID
      currentPhaseRank = -1
      accumulatedPhase = 0
      phaseUpdateAt = nil
      processingStartedAt = nil
      frame.energy = 0
      frame.phase = 0
      frame.activationMix = 0
      frame.processingMix = 0
      frame.glint = 0
      frame.glintOpacity = 0
    }
    if !isNewSession && (state == .arming || state == .opening) { return }
    lifecycleGeneration &+= 1
    currentPhaseRank = 0
    closesToStandby = false
    if reduceMotion {
      state = .arming
      expansionTween = nil
      signalOpacityTween = nil
      frame.expansion = 1
      frame.signalOpacity = 0.32
    } else {
      state = .opening
      expansionTween = Tween(from: frame.expansion, to: 1, start: now, duration: 0.32)
      signalOpacityTween = Tween(from: frame.signalOpacity, to: 0.32, start: now, duration: 0.32)
    }
    activationTween = nil
    processingTween = nil
    phaseUpdateAt = nil
    processingStartedAt = nil
    frozenEnergy = 0
    frozenPhase = 0
    frame.energy = 0
    frame.phase = 0
    frame.activationMix = 0
    frame.processingMix = 0
    frame.glint = 0
    frame.glintOpacity = 0
    publish()
  }

  func presentListening(
    sessionID: UUID,
    at now: TimeInterval,
    displayedEnergy: Double,
    reduceMotion: Bool
  ) {
    guard acceptPhase(sessionID: sessionID, rank: 1) else { return }
    tick(at: now, displayedEnergy: displayedEnergy, reduceMotion: reduceMotion)
    if self.sessionID == sessionID, state == .listening {
      return
    }
    var nextFrame = frame
    let isNewSession = self.sessionID != sessionID
    if isNewSession {
      if state != .standby, !(state == .closing && closesToStandby), !isVisible {
        nextFrame = closedFrame(expansion: 0)
      }
      self.sessionID = sessionID
      currentPhaseRank = -1
      accumulatedPhase = 0
      phaseUpdateAt = nil
      nextFrame.energy = 0
      nextFrame.phase = 0
      nextFrame.activationMix = 0
      nextFrame.processingMix = 0
      nextFrame.glint = 0
      nextFrame.glintOpacity = 0
    }
    lifecycleGeneration &+= 1
    currentPhaseRank = 1
    state = .listening
    closesToStandby = false
    if reduceMotion {
      expansionTween = nil
      nextFrame.expansion = 1
    } else if expansionTween == nil || nextFrame.expansion < 1 {
      expansionTween = Tween(from: nextFrame.expansion, to: 1, start: now, duration: 0.32)
    }
    processingStartedAt = nil
    processingTween = nil
    nextFrame.energy = FleckPillGeometry.clamp(displayedEnergy)
    phaseUpdateAt = !reduceMotion && nextFrame.energy > 0 ? now : nil
    nextFrame.phase = 0
    nextFrame.activationMix = reduceMotion ? 0 : 1
    nextFrame.processingMix = 0
    nextFrame.glint = 0
    nextFrame.glintOpacity = 0
    if reduceMotion {
      activationTween = nil
      signalOpacityTween = nil
      nextFrame.signalOpacity = 1
    } else {
      activationTween = Tween(from: 1, to: 0, start: now, duration: 0.28)
      signalOpacityTween = Tween(from: nextFrame.signalOpacity, to: 1, start: now, duration: 0.28)
    }
    if nextFrame != frame { frame = nextFrame }
    publish()
  }

  func presentProcessing(
    sessionID: UUID,
    at now: TimeInterval,
    renderedFrame: FleckPillArtworkFrame?,
    displayedEnergy: Double,
    reduceMotion: Bool
  ) {
    guard acceptPhase(sessionID: sessionID, rank: 2) else { return }
    tick(at: now, displayedEnergy: displayedEnergy, reduceMotion: reduceMotion)
    if self.sessionID == sessionID, state == .processing {
      return
    }
    let wasArming = state == .arming || state == .opening
    if self.sessionID != sessionID {
      frame = closedFrame(expansion: 0)
      self.sessionID = sessionID
      currentPhaseRank = -1
      accumulatedPhase = 0
      phaseUpdateAt = nil
    }
    lifecycleGeneration &+= 1
    currentPhaseRank = 2
    state = .processing
    closesToStandby = false
    let consumed = renderedFrame ?? (wasArming ? frame : nil)
    if let consumed {
      frame = consumed
    } else {
      frame.energy = 0
      frame.phase = 0
      frame.activationMix = 0
    }
    frozenEnergy = renderedFrame.map { FleckPillGeometry.clamp($0.energy) } ?? 0
    frozenPhase = frame.phase
    frame.energy = frozenEnergy
    processingStartedAt = now
    phaseUpdateAt = nil
    activationTween = nil
    if reduceMotion {
      expansionTween = nil
      processingTween = nil
      signalOpacityTween = nil
      frame.expansion = 1
      frame.activationMix = 0
      frame.processingMix = 1
      frame.signalOpacity = 1
      frame.glint = 0
      frame.glintOpacity = 0
    } else {
      processingTween = Tween(from: frame.processingMix, to: 1, start: now, duration: 0.28)
      if expansionTween == nil || frame.expansion < 1 {
        expansionTween = Tween(from: frame.expansion, to: 1, start: now, duration: 0.32)
      }
      signalOpacityTween = Tween(from: frame.signalOpacity, to: 1, start: now, duration: 0.28)
    }
    publish()
  }

  func close(
    at now: TimeInterval,
    renderedFrame: FleckPillArtworkFrame?,
    reduceMotion: Bool
  ) {
    guard isVisible else { return }
    if state == .closing, !closesToStandby { return }
    if let renderedFrame { frame = renderedFrame }
    tick(at: now, displayedEnergy: frame.energy, reduceMotion: reduceMotion)
    if reduceMotion {
      hide()
      return
    }
    lifecycleGeneration &+= 1
    closesToStandby = false
    state = .closing
    sessionID = nil
    currentPhaseRank = -1
    phaseUpdateAt = nil
    processingStartedAt = nil
    activationTween = nil
    processingTween = nil
    expansionTween = Tween(from: frame.expansion, to: 0, start: now, duration: 0.32)
    signalOpacityTween = Tween(from: frame.signalOpacity, to: 0, start: now, duration: 0.32)
    publish()
  }

  func hide() {
    lifecycleGeneration &+= 1
    sessionID = nil
    currentPhaseRank = -1
    accumulatedPhase = 0
    phaseUpdateAt = nil
    processingStartedAt = nil
    expansionTween = nil
    signalOpacityTween = nil
    activationTween = nil
    processingTween = nil
    closesToStandby = false
    frame = closedFrame(expansion: 0)
    state = .hidden
    publish()
  }

  func tick(at now: TimeInterval, displayedEnergy: Double, reduceMotion: Bool? = nil) {
    if let reduceMotion { reduceMotionEnabled = reduceMotion }
    let previousFrame = frame
    let previousState = state
    var nextFrame = frame
    if reduceMotionEnabled {
      expansionTween = nil
      signalOpacityTween = nil
      activationTween = nil
      processingTween = nil
      phaseUpdateAt = nil
      switch state {
      case .opening, .arming:
        if state != .arming { state = .arming }
        nextFrame.expansion = 1
        nextFrame.energy = 0
        nextFrame.phase = 0
        nextFrame.activationMix = 0
        nextFrame.processingMix = 0
        nextFrame.signalOpacity = 0.32
        nextFrame.glint = 0
        nextFrame.glintOpacity = 0
      case .listening:
        nextFrame.expansion = 1
        nextFrame.energy = FleckPillGeometry.clamp(displayedEnergy)
        nextFrame.phase = accumulatedPhase
        nextFrame.activationMix = 0
        nextFrame.processingMix = 0
        nextFrame.signalOpacity = 1
        nextFrame.glint = 0
        nextFrame.glintOpacity = 0
      case .processing:
        nextFrame.expansion = 1
        nextFrame.energy = frozenEnergy
        nextFrame.phase = frozenPhase
        nextFrame.activationMix = 0
        nextFrame.processingMix = 1
        nextFrame.signalOpacity = 1
        nextFrame.glint = 0
        nextFrame.glintOpacity = 0
      case .closing:
        if closesToStandby {
          state = .standby
          accumulatedPhase = 0
          processingStartedAt = nil
          nextFrame = closedFrame(expansion: 0)
        } else {
          hide()
          return
        }
      case .hidden, .standby:
        break
      }
      if nextFrame != frame { frame = nextFrame }
      if frame != previousFrame || state != previousState { publish() }
      return
    }
    if let tween = expansionTween {
      nextFrame.expansion = tween.value(at: now)
      if now - tween.start >= tween.duration { expansionTween = nil }
    }
    if let tween = signalOpacityTween {
      nextFrame.signalOpacity = tween.value(at: now)
      if now - tween.start >= tween.duration { signalOpacityTween = nil }
    }
    if let tween = activationTween {
      nextFrame.activationMix = tween.value(at: now)
      if now - tween.start >= tween.duration { activationTween = nil }
    }
    if let tween = processingTween {
      nextFrame.processingMix = tween.value(at: now)
      if now - tween.start >= tween.duration { processingTween = nil }
    }
    switch state {
    case .listening:
      let energy = FleckPillGeometry.clamp(displayedEnergy)
      if nextFrame.energy > 0, let phaseUpdateAt {
        accumulatedPhase += FleckPillMotion.liveWavePhaseRate * max(now - phaseUpdateAt, 0)
      }
      phaseUpdateAt = energy > 0 ? now : nil
      nextFrame.energy = energy
      nextFrame.phase = accumulatedPhase
    case .processing:
      nextFrame.energy = frozenEnergy
      nextFrame.phase = frozenPhase
      if let processingStartedAt {
        let glint = FleckPillMotion.processingGlint(at: now - processingStartedAt)
        nextFrame.glint = glint.position
        nextFrame.glintOpacity = glint.opacity
      }
    case .arming, .opening:
      nextFrame.energy = 0
      nextFrame.phase = 0
      nextFrame.activationMix = 0
      nextFrame.processingMix = 0
      nextFrame.glint = 0
      nextFrame.glintOpacity = 0
    case .closing:
      nextFrame.energy = 0
      nextFrame.glintOpacity = 0
    case .hidden, .standby:
      break
    }
    if state == .opening, expansionTween == nil {
      state = .arming
    } else if state == .closing, expansionTween == nil, signalOpacityTween == nil {
      if closesToStandby {
        state = .standby
        nextFrame.energy = 0
        nextFrame.phase = 0
        accumulatedPhase = 0
        phaseUpdateAt = nil
        nextFrame.activationMix = 0
        nextFrame.processingMix = 0
        nextFrame.glint = 0
        nextFrame.glintOpacity = 0
      } else {
        hide()
        return
      }
    }
    if nextFrame != frame { frame = nextFrame }
    if frame != previousFrame || state != previousState { publish() }
  }

  private func acceptPhase(sessionID: UUID, rank: Int) -> Bool {
    guard self.sessionID == nil || self.sessionID == sessionID else { return true }
    return rank >= currentPhaseRank
  }

  private func closedFrame(expansion: Double) -> FleckPillArtworkFrame {
    FleckPillArtworkFrame(
      expansion: expansion,
      energy: 0,
      phase: 0,
      activationMix: 0,
      processingMix: 0,
      signalOpacity: 0,
      glint: 0,
      glintOpacity: 0
    )
  }

  private func publish() {
    renderGeneration &+= 1
  }
}
#endif
