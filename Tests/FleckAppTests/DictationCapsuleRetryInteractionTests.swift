#if os(macOS)
import AppKit
import FleckCore
import Testing

@testable import FleckApp

@MainActor
private final class RetryInteractionClock {
  var now = 0.0
}

@MainActor
private func retryNativeEvents(_ controller: DictationCapsuleController, number: Int)
  throws -> (NSView, NSEvent, NSEvent)
{
  let panel = controller.panel
  let host = try #require(panel.contentView)
  host.layoutSubtreeIfNeeded()
  func find(_ view: NSView) -> NSView? {
    if view.identifier?.rawValue == "fleck-rail-recovery" { return view }
    return view.subviews.lazy.compactMap { find($0) }.first
  }
  let probe = try #require(find(host))
  let bounds = probe.convert(probe.bounds, to: host)
  #expect(host.bounds.contains(bounds))
  let point = CGPoint(x: bounds.midX, y: bounds.midY)
  let target = try #require(host.hitTest(host.convert(point, to: host.superview)))
  #expect(target === host.subviews.first)
  let location = host.convert(point, to: nil)
  func event(_ type: NSEvent.EventType, _ offset: Int) throws -> NSEvent {
    try #require(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
      timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
      context: nil, eventNumber: number + offset, clickCount: 1, pressure: 0))
  }
  return (target, try event(.leftMouseDown, 0), try event(.leftMouseUp, 1))
}

@MainActor
private func renderRetryListening(_ controller: DictationCapsuleController, sessionID: UUID) {
  controller.render(.init(status: .listening, sessionID: sessionID,
    mode: .smartCapture, pipelineStage: .capture), coordinatorEvent: .init(
      phase: .listening(mode: .smartCapture, engine: .standard), terminal: nil,
      context: .init(sessionID: sessionID, mode: .smartCapture, pipelineStage: .capture,
        cleanupOutcome: nil, failureStage: nil)))
}

@Test @MainActor func nativeRetryAcceptsVisibleEntryAndRejectsReplacementBetweenPressAndRelease() async throws {
  let clock = RetryInteractionClock()
  let controller = DictationCapsuleController(monotonicNow: { clock.now },
    automaticallyAdvancesLivePill: false, reduceMotionProvider: { false })
  controller.setReduceMotionOverrideForTesting(false)
  defer { controller.dismiss() }
  var tokens: [UInt64] = []
  controller.configureInteraction(onPrimaryClick: {}, onStop: {}, onCancel: {}, onOpenFleck: {},
    onOpenHistory: {}, onOpenSettings: {}, onDismiss: {}, onRecovery: {},
    onErrorRecovery: { tokens.append($0) })
  controller.presentIdle(dock: .bottom, onOpenFleck: {}, onDockChanged: { _ in })
  let sessionID = UUID()
  renderRetryListening(controller, sessionID: sessionID)
  clock.now = 1
  controller.fleckPillModel.tick(at: clock.now, displayedEnergy: 0)
  controller.render(.init(status: .failed("Synthetic first failure"), sessionID: sessionID,
    failureStage: .capture))
  clock.now = 1.17
  for _ in 0..<40 {
    let opacity = controller.errorPresentationModel.presentation?.contentOpacity ?? 0
    if opacity > 0.1 && opacity < 0.98 { break }
    try await Task.sleep(for: .milliseconds(8))
  }
  let opacity = try #require(controller.errorPresentationModel.presentation?.contentOpacity)
  try #require(opacity > 0.1 && opacity < 0.98)
  let (target, down, up) = try retryNativeEvents(controller, number: 900)
  target.mouseDown(with: down)
  target.mouseUp(with: up)
  try #require(tokens.count == 1)
  target.mouseDown(with: down)
  target.mouseUp(with: up)
  #expect(tokens.count == 1)
  controller.errorPresentationModel.finishTransientAction(tokens[0])
  target.mouseDown(with: down)
  let replacement = UUID()
  controller.render(.init(status: .failed("Synthetic replacement failure"), sessionID: replacement,
    failureStage: .capture))
  target.mouseUp(with: up)
  #expect(tokens.count == 1)
  #expect(controller.errorPresentationModel.presentation?.sessionID == replacement)
  #expect(controller.errorPresentationModel.presentation?.phase == .default)
  let (replacementTarget, replacementDown, replacementUp) = try retryNativeEvents(controller, number: 902)
  replacementTarget.mouseDown(with: replacementDown)
  replacementTarget.mouseUp(with: replacementUp)
  #expect(tokens.count == 2)
}

private struct RetryPostedEvent: @unchecked Sendable {
  let event: NSEvent
}

@Test @MainActor func DictationCapsulePostedEventRetryQualification() async throws {
  let application = try #require(NSApp)
  try #require(application.isRunning, "Requires the existing AppKit test host's live NSApplication.run loop")
  let currentPID = ProcessInfo.processInfo.processIdentifier
  let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
  let activationDiagnostic = [
    "isActive=\(application.isActive)",
    "policy=\(String(describing: application.activationPolicy()))",
    "currentPID=\(currentPID)",
    "frontmostIsCurrent=\(frontmostPID.map { $0 == currentPID } ?? false)",
    "frontmostPID=\(String(describing: frontmostPID))",
  ].joined(separator: ", ")
  try #require(application.isActive, Comment(rawValue: activationDiagnostic))
  try #require(application.activationPolicy() == .regular)
  let controller = DictationCapsuleController(automaticallyAdvancesLivePill: false,
    reduceMotionProvider: { true })
  controller.setReduceMotionOverrideForTesting(true)
  defer { controller.dismiss() }
  var acceptedTokens: [UInt64] = []
  var acceptedSessions: [UUID?] = []
  controller.configureInteraction(onPrimaryClick: {}, onStop: {}, onCancel: {}, onOpenFleck: {},
    onOpenHistory: {}, onOpenSettings: {}, onDismiss: {}, onRecovery: {},
    onErrorRecovery: { [weak controller] token in
      acceptedTokens.append(token)
      acceptedSessions.append(controller?.errorPresentationModel.presentation(forActionToken: token)?.sessionID)
    })
  controller.presentIdle(dock: .bottom, onOpenFleck: {}, onDockChanged: { _ in })
  let sessionID = UUID()
  renderRetryListening(controller, sessionID: sessionID)
  controller.render(.init(status: .failed("Synthetic posted-event failure"), sessionID: sessionID,
    failureStage: .capture))
  let panel = controller.panel
  try #require(panel.windowNumber > 0)
  try #require(panel.isVisible && !panel.ignoresMouseEvents)
  try #require(controller.errorPresentationModel.canBeginAction)
  let (_, down, up) = try retryNativeEvents(controller, number: 20_900)
  try #require(down.window === panel && up.window === panel)
  try #require(down.locationInWindow == up.locationInWindow)

  var posted: [NSEvent] = []
  var delivered: [Int] = []
  let monitor = try #require(NSEvent.addLocalMonitorForEvents(
    matching: [.leftMouseDown, .leftMouseUp], handler: { event in
      let observed = RetryPostedEvent(event: event)
      MainActor.assumeIsolated {
        let event = observed.event
        guard let expected = posted.first(where: { $0.eventNumber == event.eventNumber }) else { return }
        #expect(event.eventNumber > 0)
        #expect(event.windowNumber == panel.windowNumber)
        #expect(event.windowNumber == expected.windowNumber)
        #expect(event.window === panel)
        #expect(event.type == expected.type)
        #expect(event.locationInWindow == expected.locationInWindow)
        #expect(event.timestamp == expected.timestamp)
        #expect(event.modifierFlags == expected.modifierFlags)
        #expect(event.clickCount == expected.clickCount)
        delivered.append(event.eventNumber)
      }
      return event
    }))
  defer { NSEvent.removeMonitor(monitor) }

  func post(_ event: NSEvent) async throws {
    try #require(event.windowNumber == panel.windowNumber && event.window === panel)
    try #require(event.eventNumber > 0)
    try #require(!posted.contains(where: { $0.eventNumber == event.eventNumber }))
    posted.append(event)
    application.postEvent(event, atStart: false)
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(2))
    while delivered.count < posted.count && clock.now < deadline {
      try await Task.sleep(for: .milliseconds(5))
    }
    try #require(delivered == posted.map(\.eventNumber), "Every owned event must arrive once, in order, through normal AppKit dispatch")
  }

  try await post(down)
  try #require(controller.errorPresentationModel.isActionPressed)
  try #require(acceptedTokens.isEmpty)
  try await post(up)
  try #require(acceptedTokens.count == 1)
  let token = try #require(acceptedTokens.first)
  #expect(acceptedSessions == [sessionID])
  #expect(controller.errorPresentationModel.presentation(forActionToken: token)?.sessionID == sessionID)
  #expect(controller.errorPresentationModel.presentation?.phase == .pending)
  #expect(!controller.errorPresentationModel.isActionPressed)

  let (_, repeatedDown, repeatedUp) = try retryNativeEvents(controller, number: 20_902)
  try await post(repeatedDown)
  try await post(repeatedUp)
  #expect(acceptedTokens == [token])
  #expect(controller.errorPresentationModel.presentation?.actionToken == token)
  #expect(controller.errorPresentationModel.presentation?.phase == .pending)

  controller.errorPresentationModel.finishTransientAction(token)
  let (_, staleDown, staleUp) = try retryNativeEvents(controller, number: 20_904)
  try await post(staleDown)
  try #require(controller.errorPresentationModel.isActionPressed)
  let pressedGeneration = controller.errorPresentationModel.interactionGeneration
  let replacement = UUID()
  controller.render(.init(status: .failed("Synthetic posted-event replacement"), sessionID: replacement,
    failureStage: .capture))
  try #require(controller.errorPresentationModel.interactionGeneration != pressedGeneration)
  try await post(staleUp)
  #expect(acceptedTokens == [token])
  #expect(controller.errorPresentationModel.presentation(forActionToken: token) == nil)
  #expect(controller.errorPresentationModel.presentation?.sessionID == replacement)
  #expect(controller.errorPresentationModel.presentation?.phase == .default)
  #expect(controller.errorPresentationModel.presentation?.actionToken == nil)

  let (_, replacementDown, replacementUp) = try retryNativeEvents(controller, number: 20_906)
  try await post(replacementDown)
  try #require(controller.errorPresentationModel.isActionPressed)
  try await post(replacementUp)
  try #require(acceptedTokens.count == 2)
  let replacementToken = try #require(acceptedTokens.last)
  #expect(replacementToken != token)
  #expect(acceptedSessions == [sessionID, replacement])
  #expect(controller.errorPresentationModel.presentation(forActionToken: replacementToken)?.sessionID == replacement)
  #expect(controller.errorPresentationModel.presentation?.phase == .pending)
}

@Test @MainActor func DictationCapsuleTransitionResponsivenessWhenRequested() async throws {
  guard let directory = ProcessInfo.processInfo.environment["FLECK_CAPSULE_RESPONSIVENESS_DIR"] else { return }
  let output = URL(fileURLWithPath: directory, isDirectory: true)
  try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
  var samples: [[String: Any]] = []
  for reducedMotion in [false, true] {
    let controller = DictationCapsuleController(automaticallyAdvancesLivePill: false,
      reduceMotionProvider: { reducedMotion })
    controller.setReduceMotionOverrideForTesting(reducedMotion)
    defer { controller.dismiss() }
    var attempts = 0
    var accepted = 0
    controller.configureInteraction(onPrimaryClick: {}, onStop: {}, onCancel: {}, onOpenFleck: {},
      onOpenHistory: {}, onOpenSettings: {}, onDismiss: {}, onRecovery: {},
      onErrorRecovery: { _ in accepted += 1 })
    controller.presentIdle(dock: .bottom, onOpenFleck: {}, onDockChanged: { _ in })
    for cycle in 0..<12 {
      let sessionID = UUID()
      var stateSessionID = sessionID
      renderRetryListening(controller, sessionID: sessionID)
      controller.fleckPillModel.tick(at: ProcessInfo.processInfo.systemUptime + 1, displayedEnergy: 0.3)
      let states: [(String, DictationCapsuleStatus)] = [
        ("failure", .failed("Synthetic failure")), ("arming", .arming),
        ("listening", .listening), ("processing", .cleaning),
        ("success", .saved(destination: "Synthetic")), ("standby", .idle),
      ]
      for (name, status) in states {
        if name == "arming" { stateSessionID = UUID() }
        let stage: DictationPipelineStage = name == "processing" ? .polish
          : name == "success" ? .save : .capture
        let destination = DictationDestination(noteID: UUID(), title: "Synthetic")
        let phase: DictationPhase = switch name {
        case "failure": .failed("Synthetic failure")
        case "arming": .arming
        case "listening": .listening(mode: .smartCapture, engine: .standard)
        case "processing": .cleaning
        case "success": .saved(destination)
        default: .idle
        }
        let terminal: DictationTerminalOutcome? = name == "success"
          ? .saved(mode: .smartCapture, cleanup: .cleaned, destination: destination)
          : name == "failure" ? .failed("Synthetic failure") : nil
        let context = DictationCapsuleContext(status: status, sessionID: stateSessionID,
          mode: .smartCapture, pipelineStage: stage,
          failureStage: name == "failure" ? .capture : nil)
        let event = DictationCoordinatorEvent(phase: phase, terminal: terminal,
          context: .init(sessionID: stateSessionID, mode: .smartCapture, destination: destination,
            pipelineStage: stage, cleanupOutcome: name == "success" ? .cleaned : nil,
            failureStage: name == "failure" ? .capture : nil))
        let started = ProcessInfo.processInfo.systemUptime
        controller.render(context, coordinatorEvent: name == "standby" ? nil : event)
        controller.panel.contentView?.layoutSubtreeIfNeeded()
        samples.append(["cycle": cycle, "state": name, "reducedMotion": reducedMotion,
          "renderAndLayoutMilliseconds": (ProcessInfo.processInfo.systemUptime - started) * 1_000,
          "displayedStatus": String(describing: controller.currentContext.status),
          "panelWidth": controller.panel.frame.width, "panelHeight": controller.panel.frame.height])
        await Task.yield()
      }
    }
    let retrySession = UUID()
    renderRetryListening(controller, sessionID: retrySession)
    controller.fleckPillModel.tick(at: ProcessInfo.processInfo.systemUptime + 1, displayedEnergy: 0)
    let started = ProcessInfo.processInfo.systemUptime
    controller.render(.init(status: .failed("Synthetic retry latency"), sessionID: retrySession,
      failureStage: .capture))
    for attempt in 0..<50 {
      attempts += 1
      let (target, down, up) = try retryNativeEvents(controller, number: 1_000 + attempt * 2)
      target.mouseDown(with: down)
      target.mouseUp(with: up)
      if accepted > 0 { break }
      try await Task.sleep(for: .milliseconds(8))
    }
    samples.append(["state": "native-first-accepted-retry", "reducedMotion": reducedMotion,
      "elapsedMilliseconds": (ProcessInfo.processInfo.systemUptime - started) * 1_000,
      "attempts": attempts, "accepted": accepted,
      "contentOpacity": controller.errorPresentationModel.presentation?.contentOpacity ?? -1])
    #expect(accepted == 1)
  }
  try JSONSerialization.data(withJSONObject: samples, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appendingPathComponent("capsule-transition-responsiveness.json"))
}
#endif
