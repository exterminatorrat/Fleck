import Foundation
import FleckCore
import Testing

@testable import FleckApp

@Test func modifierVirtualKeyCodesKeepPhysicalSidesDistinct() {
  #expect(ModifierKeyEventTap.modifier(forVirtualKey: 0x3F) == .function)
  #expect(ModifierKeyEventTap.modifier(forVirtualKey: 0x37) == .leftCommand)
  #expect(ModifierKeyEventTap.modifier(forVirtualKey: 0x36) == .rightCommand)
  #expect(ModifierKeyEventTap.modifier(forVirtualKey: 0x3A) == .leftOption)
  #expect(ModifierKeyEventTap.modifier(forVirtualKey: 0x3D) == .rightOption)
  #expect(ModifierKeyEventTap.modifier(forVirtualKey: 0x3B) == .leftControl)
  #expect(ModifierKeyEventTap.modifier(forVirtualKey: 0x3E) == .rightControl)
  #expect(ModifierKeyEventTap.modifier(forVirtualKey: 0x00) == nil)
}

@Test func heldModifierMustReturnNeutralBeforeActivation() {
  var state = ModifierKeyEventTap.KeyState(modifier: .rightOption)
  state.synchronize(isDown: true)

  #expect(state.receiveFlagChange() == nil)
  #expect(state.receiveFlagChange() == .pressed(.rightOption))
  #expect(state.receiveFlagChange() == .released(.rightOption))
}

@Test @MainActor func onlySelectedPhysicalSideStartsASession() async throws {
  let fixture = ShortcutFixture()
  try fixture.shortcut.configure(.rightOption)

  fixture.monitor.emit(.pressed(.leftOption))
  fixture.monitor.emit(.released(.leftOption))
  fixture.monitor.emit(.released(.rightOption))
  fixture.monitor.emit(.pressed(.rightOption))
  await fixture.shortcut.drainEvents()

  #expect(fixture.handler.beginCount == 1)
}

@Test @MainActor func duplicateModifierTransitionsAreIgnored() async throws {
  let fixture = ShortcutFixture()
  try fixture.shortcut.configure(.rightOption)

  fixture.monitor.emit(.pressed(.rightOption))
  fixture.monitor.emit(.pressed(.rightOption))
  fixture.clock.advance(by: .milliseconds(200))
  fixture.monitor.emit(.released(.rightOption))
  fixture.monitor.emit(.released(.rightOption))
  await fixture.shortcut.drainEvents()

  #expect(fixture.handler.events == [.begin, .end])
}

@Test @MainActor func shortSingleTapCreatesNoHandsFreeCapture() async throws {
  let fixture = ShortcutFixture()
  try fixture.shortcut.configure(.rightOption)

  fixture.monitor.emit(.pressed(.rightOption))
  fixture.clock.advance(by: .milliseconds(50))
  fixture.monitor.emit(.released(.rightOption))
  await fixture.shortcut.drainEvents()

  #expect(fixture.handler.events == [.begin, .end])
  #expect(fixture.handler.handsFreeBeginCount == 0)
}

@Test @MainActor func holdDelegatesBeginAndEndExactlyOnce() async throws {
  let fixture = ShortcutFixture()
  try fixture.shortcut.configure(.rightOption)

  fixture.monitor.emit(.pressed(.rightOption))
  fixture.clock.advance(by: .milliseconds(180))
  fixture.monitor.emit(.released(.rightOption))
  await fixture.shortcut.drainEvents()

  #expect(fixture.handler.beginCount == 1)
  #expect(fixture.handler.endCount == 1)
  #expect(fixture.handler.handsFreeBeginCount == 0)
}

@Test @MainActor
func physicalGestureReceiptPreservesPressAndReleaseAcrossQueuedDelivery() async throws {
  let fixture = ShortcutFixture()
  let deliveryGate = TerminalGate()
  fixture.handler.endGate = deliveryGate
  try fixture.shortcut.configure(.rightOption)

  let firstPress = fixture.clock.now
  fixture.monitor.emit(.pressed(.rightOption))
  fixture.clock.advance(by: .milliseconds(200))
  fixture.monitor.emit(.released(.rightOption))
  while fixture.handler.endCount == 0 { await Task.yield() }

  fixture.clock.advance(by: .milliseconds(50))
  let queuedPress = fixture.clock.now
  fixture.monitor.emit(.pressed(.rightOption))
  fixture.clock.advance(by: .milliseconds(30))
  let queuedRelease = fixture.clock.now
  fixture.monitor.emit(.released(.rightOption))
  fixture.clock.advance(by: .seconds(2))

  deliveryGate.open()
  await fixture.shortcut.drainEvents()

  #expect(fixture.handler.beginGestures == [
    .init(pressedAt: firstPress),
    .init(pressedAt: queuedPress),
  ])
  #expect(fixture.handler.endGestures.last == .init(
    pressedAt: queuedPress,
    releasedAt: queuedRelease
  ))
}

@Test @MainActor
func physicalGestureReceiptReachesHandlerBeforeQueuedEndDelivery() async throws {
  let fixture = ShortcutFixture()
  try fixture.shortcut.configure(.rightOption)
  fixture.monitor.emit(.pressed(.rightOption))
  await fixture.shortcut.drainEvents()
  let press = try #require(fixture.handler.beginGestures.last?.pressedAt)

  fixture.clock.advance(by: .milliseconds(179))
  let release = fixture.clock.now
  fixture.monitor.emit(.released(.rightOption))

  #expect(fixture.handler.events == [.begin, .releaseReceipt])
  #expect(fixture.handler.releaseGestures == [
    .init(pressedAt: press, releasedAt: release)
  ])
  await fixture.shortcut.drainEvents()
  #expect(fixture.handler.events == [.begin, .releaseReceipt, .end])
}

@Test @MainActor func doubleTapStartsHandsFreeAndLaterPressFinishesIt() async throws {
  let fixture = ShortcutFixture()
  try fixture.shortcut.configure(.rightOption)

  fixture.monitor.emit(.pressed(.rightOption))
  fixture.clock.advance(by: .milliseconds(40))
  fixture.monitor.emit(.released(.rightOption))
  fixture.clock.advance(by: .milliseconds(320))
  fixture.monitor.emit(.pressed(.rightOption))
  fixture.monitor.emit(.released(.rightOption))
  await fixture.shortcut.drainEvents()

  #expect(fixture.handler.beginCount == 1)
  #expect(fixture.handler.endCount == 1)
  #expect(fixture.handler.handsFreeBeginCount == 1)
  #expect(fixture.handler.handsFreeFinishCount == 0)

  fixture.monitor.emit(.pressed(.rightOption))
  fixture.monitor.emit(.released(.rightOption))
  await fixture.shortcut.drainEvents()

  #expect(fixture.handler.handsFreeFinishCount == 1)
}

@Test @MainActor func captureFirstHandsFreeStopPreservesPhysicalKeyDownAcrossQueueing() async throws {
  let fixture = ShortcutFixture()
  try fixture.shortcut.configure(.rightOption)
  await fixture.startHandsFree()

  fixture.clock.advance(by: .milliseconds(75))
  let stoppingPress = fixture.clock.now
  fixture.monitor.emit(.pressed(.rightOption))
  fixture.clock.advance(by: .seconds(1))
  fixture.monitor.emit(.released(.rightOption))
  await fixture.shortcut.drainEvents()

  #expect(fixture.handler.handsFreeStopOrigins == [.handsFreeKeyPress(stoppingPress)])
}

@Test @MainActor func tapOutsideDoubleTapWindowStartsANewHold() async throws {
  let fixture = ShortcutFixture()
  try fixture.shortcut.configure(.rightOption)

  fixture.monitor.emit(.pressed(.rightOption))
  fixture.clock.advance(by: .milliseconds(40))
  fixture.monitor.emit(.released(.rightOption))
  fixture.clock.advance(by: .milliseconds(321))
  fixture.monitor.emit(.pressed(.rightOption))
  await fixture.shortcut.drainEvents()

  #expect(fixture.handler.beginCount == 2)
  #expect(fixture.handler.handsFreeBeginCount == 0)
}

@Test @MainActor func escapeCancelsOwnedHoldSession() async throws {
  let fixture = ShortcutFixture()
  try fixture.shortcut.configure(.rightOption)
  fixture.monitor.emit(.pressed(.rightOption))
  await fixture.shortcut.drainEvents()

  fixture.escape.emit()
  await fixture.shortcut.drainEvents()

  #expect(fixture.handler.cancelCount == 1)
}

@Test @MainActor func escapeCancelsOwnedHandsFreeSession() async throws {
  let fixture = ShortcutFixture()
  try fixture.shortcut.configure(.rightOption)
  await fixture.startHandsFree()

  fixture.escape.emit()
  await fixture.shortcut.drainEvents()

  #expect(fixture.handler.cancelCount == 1)
}

@Test @MainActor func monitorFailureClearsTapAndCancelsOnlyOwnedSession() async throws {
  let fixture = ShortcutFixture()
  try fixture.shortcut.configure(.rightOption)

  fixture.monitor.emit(.pressed(.rightOption))
  fixture.clock.advance(by: .milliseconds(40))
  fixture.monitor.emit(.released(.rightOption))
  fixture.monitor.publish(.failed)
  await fixture.shortcut.drainEvents()

  fixture.clock.advance(by: .milliseconds(20))
  fixture.monitor.emit(.pressed(.rightOption))
  await fixture.shortcut.drainEvents()

  #expect(fixture.handler.beginCount == 2)
  #expect(fixture.handler.handsFreeBeginCount == 0)

  fixture.monitor.publish(.failed)
  await fixture.shortcut.drainEvents()
  #expect(fixture.handler.cancelCount == 1)
}

@Test @MainActor func unexpectedMonitorStopCancelsOwnedHandsFreeSession() async throws {
  let fixture = ShortcutFixture()
  try fixture.shortcut.configure(.rightOption)
  await fixture.startHandsFree()

  fixture.monitor.publish(.stopped)
  await fixture.shortcut.drainEvents()

  #expect(fixture.handler.cancelCount == 1)
}

@Test @MainActor func successfulTapRecoveryCancelsOwnedHoldAndSuppressesRelease()
  async throws
{
  let fixture = ShortcutFixture()
  try fixture.shortcut.configure(.rightOption)
  fixture.monitor.emit(.pressed(.rightOption))
  await fixture.shortcut.drainEvents()

  #expect(fixture.monitor.recoverDisabledTap())
  await fixture.shortcut.drainEvents()
  fixture.monitor.emit(.released(.rightOption))
  await fixture.shortcut.drainEvents()

  #expect(fixture.handler.cancelCount == 1)
  #expect(fixture.handler.endCount == 0)
  #expect(fixture.shortcut.registeredModifier == .rightOption)
  #expect(fixture.shortcut.monitorState == .running)
}

@Test @MainActor func successfulTapRecoveryCancelsOwnedHandsFreeSession() async throws {
  let fixture = ShortcutFixture()
  try fixture.shortcut.configure(.rightOption)
  await fixture.startHandsFree()

  #expect(fixture.monitor.recoverDisabledTap())
  await fixture.shortcut.drainEvents()

  #expect(fixture.handler.cancelCount == 1)
  #expect(fixture.handler.handsFreeFinishCount == 0)
  #expect(fixture.shortcut.registeredModifier == .rightOption)
  #expect(fixture.shortcut.monitorState == .running)
}

@Test @MainActor func twoSuccessfulTapRecoveriesEachResetThenResume() {
  let monitor = ModifierMonitorSpy()
  var states: [ModifierMonitorState] = []
  monitor.stateHandler = { states.append($0) }

  #expect(monitor.recoverDisabledTap())
  #expect(monitor.recoverDisabledTap())

  #expect(states == [.stopped, .running, .stopped, .running])
}

@Test @MainActor func failedTapReenablePublishesResetThenFailure() {
  let monitor = ModifierMonitorSpy()
  var states: [ModifierMonitorState] = []
  monitor.stateHandler = { states.append($0) }

  #expect(!monitor.recoverDisabledTap(succeeds: false))

  #expect(states == [.stopped, .failed])
}

@Test @MainActor func tapRecoveryRejectsRecursiveAttemptWithinOneCallback() {
  let recovery = ModifierKeyEventTap.DisabledTapRecovery()
  var nestedRecovery: Bool?

  let recovered = recovery.recover(
    stateHandler: { _ in },
    synchronize: {},
    reenable: {
      nestedRecovery = recovery.recover(
        stateHandler: { _ in },
        synchronize: {},
        reenable: { true }
      )
      return true
    }
  )

  #expect(recovered)
  #expect(nestedRecovery == false)
}

@Test func modifierMonitorStatesContainNoKeyboardEventData() {
  let states: [ModifierMonitorState] = [
    .stopped,
    .unauthorized,
    .running,
    .failed,
  ]

  #expect(Set(states).count == 4)
}

@Test @MainActor func reconfigurationGateCoversQueuedPressPhysicalPressAndSession()
  async throws
{
  let fixture = ShortcutFixture()
  try fixture.shortcut.configure(.rightOption)
  #expect(fixture.shortcut.canChangeModifier)

  fixture.monitor.emit(.pressed(.rightOption))
  #expect(!fixture.shortcut.canChangeModifier)
  #expect(throws: GlobalHoldShortcut.RegistrationError.eventDeliveryPending) {
    try fixture.shortcut.configure(.leftOption)
  }

  await fixture.shortcut.drainEvents()
  #expect(!fixture.shortcut.canChangeModifier)
  #expect(throws: GlobalHoldShortcut.RegistrationError.activeSession) {
    try fixture.shortcut.configure(.leftOption)
  }

  fixture.handler.completeCurrentTerminal()
  await fixture.shortcut.waitForTerminalObservation()
  #expect(!fixture.shortcut.canChangeModifier)

  fixture.monitor.emit(.released(.rightOption))
  await fixture.shortcut.drainEvents()
  #expect(fixture.shortcut.canChangeModifier)
}

@Test @MainActor func coordinatorGateRejectsConfigurationBeforeMonitorMutation() throws {
  let fixture = ShortcutFixture()
  try fixture.shortcut.configure(.rightOption)
  fixture.handler.canConfigureShortcut = false
  fixture.monitor.accessGranted = false

  #expect(!fixture.shortcut.canChangeModifier)
  #expect(throws: GlobalHoldShortcut.RegistrationError.activeSession) {
    try fixture.shortcut.configure(.leftOption)
  }
  #expect(fixture.shortcut.registeredModifier == .rightOption)
  #expect(fixture.monitor.startCount == 1)
  #expect(fixture.monitor.stopCount == 0)
}

@Test @MainActor func deniedMonitoringLeavesExistingConfigurationRunning() throws {
  let fixture = ShortcutFixture()
  try fixture.shortcut.configure(.rightOption)
  fixture.monitor.accessGranted = false

  #expect(throws: GlobalHoldShortcut.RegistrationError.unauthorized) {
    try fixture.shortcut.configure(.leftOption)
  }
  #expect(fixture.shortcut.registeredModifier == .rightOption)
  #expect(fixture.monitor.stopCount == 0)
}

@Test @MainActor func runningMonitorChangesSemanticModifierWithoutRestart() async throws {
  let fixture = ShortcutFixture()
  try fixture.shortcut.configure(.rightOption)
  fixture.monitor.emit(.pressed(.rightOption))
  fixture.clock.advance(by: .milliseconds(40))
  fixture.monitor.emit(.released(.rightOption))
  await fixture.shortcut.drainEvents()

  try fixture.shortcut.configure(.leftOption)

  #expect(fixture.shortcut.registeredModifier == .leftOption)
  #expect(fixture.monitor.startCount == 1)
  #expect(fixture.monitor.stopCount == 0)
  fixture.clock.advance(by: .milliseconds(20))
  fixture.monitor.emit(.pressed(.leftOption))
  await fixture.shortcut.drainEvents()
  #expect(fixture.handler.handsFreeBeginCount == 0)
}

@Test @MainActor func uninstallStopsMonitorEscapeAndOwnedSession() async throws {
  let fixture = ShortcutFixture()
  try fixture.shortcut.configure(.rightOption)
  fixture.monitor.emit(.pressed(.rightOption))
  await fixture.shortcut.drainEvents()

  await fixture.shortcut.uninstall()

  #expect(fixture.handler.cancelCount == 1)
  #expect(fixture.monitor.stopCount == 1)
  #expect(fixture.escape.unregisterCount == 1)
  #expect(fixture.monitor.transitionHandler == nil)
  #expect(fixture.escape.eventHandler == nil)
}

@Test @MainActor func configurationAfterUninstallIsRejected() async throws {
  let fixture = ShortcutFixture()
  try fixture.shortcut.configure(.rightOption)
  await fixture.shortcut.uninstall()

  #expect(throws: GlobalHoldShortcut.RegistrationError.uninstalled) {
    try fixture.shortcut.configure(.leftOption)
  }
}

@Test @MainActor func pointerStartClaimsPointerOwnershipAndBeginsHandsFreeOnce() throws {
  let fixture = ShortcutFixture()

  #expect(fixture.shortcut.startPointerHandsFree())
  #expect(fixture.handler.handsFreeBeginCount == 1)
  let session = try #require(fixture.handler.lastSession)
  #expect(fixture.shortcut.activeOwnership == DictationShortcutOwnership(
    session: session,
    trigger: .pointer,
    mode: .smartCapture,
    isHandsFree: true
  ))
}

@Test @MainActor func rejectedPointerStartClearsProvisionalOwnershipWithoutPublishing() {
  let fixture = ShortcutFixture()
  fixture.handler.acceptsHandsFree = false
  var published: [DictationShortcutOwnership?] = []
  fixture.shortcut.ownershipHandler = { published.append($0) }

  #expect(!fixture.shortcut.startPointerHandsFree())
  #expect(fixture.handler.handsFreeBeginCount == 1)
  #expect(fixture.shortcut.activeOwnership == nil)
  #expect(published.isEmpty)
}

@Test @MainActor func pointerOwnershipRejectsCompetingPointerAndKeyboardStarts() async throws {
  let fixture = ShortcutFixture()
  fixture.handler.autoCompleteTerminal = false
  try fixture.shortcut.configure(.rightOption)

  #expect(fixture.shortcut.startPointerHandsFree())
  #expect(!fixture.shortcut.startPointerHandsFree())

  fixture.monitor.emit(.pressed(.rightOption))
  await fixture.shortcut.drainEvents()
  #expect(fixture.handler.beginCount == 0)
  #expect(fixture.handler.handsFreeBeginCount == 1)
  #expect(fixture.handler.handsFreeFinishCount == 1)

  fixture.monitor.emit(.released(.rightOption))
  await fixture.shortcut.drainEvents()
  fixture.monitor.emit(.pressed(.rightOption))
  fixture.monitor.emit(.released(.rightOption))
  await fixture.shortcut.drainEvents()
  #expect(fixture.handler.beginCount == 0)
  #expect(fixture.handler.handsFreeBeginCount == 1)
  #expect(fixture.handler.handsFreeFinishCount == 1)
}

@Test @MainActor func finishOwnedHandsFreeDispatchesOnceAndRetainsOwnershipUntilTerminal()
  async throws
{
  let fixture = ShortcutFixture()
  fixture.handler.autoCompleteTerminal = false
  var published: [DictationShortcutOwnership?] = []
  fixture.shortcut.ownershipHandler = { published.append($0) }

  #expect(fixture.shortcut.startPointerHandsFree())
  let ownership = try #require(fixture.shortcut.activeOwnership)
  await fixture.shortcut.finishOwnedHandsFree()
  await fixture.shortcut.finishOwnedHandsFree()

  #expect(fixture.handler.handsFreeFinishCount == 1)
  #expect(fixture.shortcut.activeOwnership == ownership)
  #expect(fixture.escape.unregisterCount == 0)

  fixture.handler.completeCurrentTerminal()
  await fixture.shortcut.waitForTerminalObservation()
  #expect(fixture.shortcut.activeOwnership == nil)
  #expect(fixture.escape.unregisterCount == 1)
  #expect(published == [ownership, nil])
}

@Test @MainActor func escapeAfterFinishPendingDispatchesOneCancel() async throws {
  let fixture = ShortcutFixture()
  fixture.handler.autoCompleteTerminal = false
  #expect(fixture.shortcut.startPointerHandsFree())

  await fixture.shortcut.finishOwnedHandsFree()
  fixture.escape.emit()
  fixture.escape.emit()
  await fixture.shortcut.drainEvents()

  #expect(fixture.handler.handsFreeFinishCount == 1)
  #expect(fixture.handler.cancelCount == 1)
  #expect(fixture.shortcut.activeOwnership != nil)

  fixture.handler.completeCurrentTerminal()
  await fixture.shortcut.waitForTerminalObservation()
}

@Test @MainActor func escapeAfterHoldReleaseFinishPendingDispatchesOneCancelUntilTerminal()
  async throws
{
  let fixture = ShortcutFixture()
  fixture.handler.autoCompleteTerminal = false
  try fixture.shortcut.configure(.rightOption)

  fixture.monitor.emit(.pressed(.rightOption))
  fixture.clock.advance(by: .milliseconds(200))
  fixture.monitor.emit(.released(.rightOption))
  await fixture.shortcut.drainEvents()

  #expect(fixture.handler.endCount == 1)
  #expect(fixture.handler.cancelCount == 0)
  #expect(fixture.shortcut.activeOwnership != nil)

  fixture.escape.emit()
  fixture.escape.emit()
  await fixture.shortcut.drainEvents()

  #expect(fixture.handler.endCount == 1)
  #expect(fixture.handler.cancelCount == 1)
  #expect(fixture.shortcut.activeOwnership != nil)

  fixture.handler.completeCurrentTerminal()
  await fixture.shortcut.waitForTerminalObservation()
  #expect(fixture.shortcut.activeOwnership == nil)
}

@Test @MainActor func uninstallAfterFinishPendingDispatchesCancelAndWaitsForTerminal()
  async throws
{
  let fixture = ShortcutFixture()
  fixture.handler.autoCompleteTerminal = false
  #expect(fixture.shortcut.startPointerHandsFree())

  await fixture.shortcut.finishOwnedHandsFree()
  let uninstallTask = Task { @MainActor in
    await fixture.shortcut.uninstall()
  }
  for _ in 0..<100 where fixture.handler.cancelCount == 0 {
    await Task.yield()
  }

  #expect(fixture.handler.handsFreeFinishCount == 1)
  #expect(fixture.handler.cancelCount == 1)
  #expect(fixture.shortcut.activeOwnership != nil)

  fixture.handler.completeCurrentTerminal()
  await uninstallTask.value
  #expect(fixture.shortcut.activeOwnership == nil)
  #expect(fixture.escape.unregisterCount == 1)
}

@Test @MainActor func selectedModifierPressFinishesPointerSessionAndIgnoresRelease() async throws {
  let fixture = ShortcutFixture()
  fixture.handler.autoCompleteTerminal = false
  try fixture.shortcut.configure(.rightOption)
  #expect(fixture.shortcut.startPointerHandsFree())

  fixture.monitor.emit(.pressed(.rightOption))
  fixture.monitor.emit(.released(.rightOption))
  await fixture.shortcut.drainEvents()
  #expect(fixture.handler.handsFreeFinishCount == 1)
  #expect(fixture.handler.endCount == 0)

  fixture.monitor.emit(.pressed(.rightOption))
  fixture.monitor.emit(.released(.rightOption))
  await fixture.shortcut.drainEvents()
  #expect(fixture.handler.handsFreeFinishCount == 1)
  #expect(fixture.handler.endCount == 0)

  fixture.handler.completeCurrentTerminal()
  await fixture.shortcut.waitForTerminalObservation()
}

@Test @MainActor func escapeCancelsPointerSessionExactlyOnce() async throws {
  let fixture = ShortcutFixture()
  fixture.handler.autoCompleteTerminal = false
  #expect(fixture.shortcut.startPointerHandsFree())

  fixture.escape.emit()
  fixture.escape.emit()
  await fixture.shortcut.drainEvents()

  #expect(fixture.handler.cancelCount == 1)
  fixture.handler.completeCurrentTerminal()
  await fixture.shortcut.waitForTerminalObservation()
}

@Test @MainActor func cancelOwnedSessionCancelsPointerSessionExactlyOnce() async throws {
  let fixture = ShortcutFixture()
  fixture.handler.autoCompleteTerminal = false
  #expect(fixture.shortcut.startPointerHandsFree())

  await fixture.shortcut.cancelOwnedSession()
  await fixture.shortcut.cancelOwnedSession()

  #expect(fixture.handler.cancelCount == 1)
  fixture.handler.completeCurrentTerminal()
  await fixture.shortcut.waitForTerminalObservation()
}

@Test @MainActor func terminalObservationClearsPointerOwnershipEscapeAndTapState() async throws {
  let fixture = ShortcutFixture()
  fixture.handler.autoCompleteTerminal = false
  try fixture.shortcut.configure(.rightOption)
  #expect(fixture.shortcut.startPointerHandsFree())
  await fixture.shortcut.finishOwnedHandsFree()

  fixture.handler.completeCurrentTerminal()
  await fixture.shortcut.waitForTerminalObservation()

  #expect(fixture.shortcut.activeOwnership == nil)
  #expect(fixture.escape.unregisterCount == 1)

  fixture.monitor.emit(.pressed(.rightOption))
  await fixture.shortcut.drainEvents()
  #expect(fixture.handler.beginCount == 1)
  await fixture.shortcut.cancelOwnedSession()
  fixture.handler.completeCurrentTerminal()
  await fixture.shortcut.waitForTerminalObservation()
}

@Test @MainActor func pointerModeUsesOneNormalizedEditorDestinationSnapshot() {
  let editor = ShortcutEditorSpy(canBeginFocusedDictation: true)
  let destination = DictationDestination(noteID: UUID(), title: "Work")
  let fixture = ShortcutFixture(
    editorProvider: { editor },
    destinationProvider: { destination }
  )

  #expect(fixture.shortcut.startPointerHandsFree())
  #expect((fixture.handler.lastEditor as AnyObject?) === editor)
  #expect(fixture.handler.lastDestination == destination)
  #expect(fixture.shortcut.activeOwnership?.mode == .focused)
}

@Test @MainActor func firstArmingEventsSynchronouslySeeTransactionalOwnership() async throws {
  let hold = ShortcutFixture()
  try hold.shortcut.configure(.rightOption)
  var holdArming: DictationShortcutOwnership?
  hold.handler.onArming = { holdArming = hold.shortcut.activeOwnership }
  hold.monitor.emit(.pressed(.rightOption))
  await hold.shortcut.drainEvents()
  #expect(holdArming?.trigger == .hold)
  #expect(holdArming?.mode == .smartCapture)
  #expect(holdArming?.isHandsFree == false)
  await hold.shortcut.cancelOwnedSession()
  await hold.shortcut.waitForTerminalObservation()

  let doubleTap = ShortcutFixture()
  try doubleTap.shortcut.configure(.rightOption)
  doubleTap.monitor.emit(.pressed(.rightOption))
  doubleTap.clock.advance(by: .milliseconds(40))
  doubleTap.monitor.emit(.released(.rightOption))
  await doubleTap.shortcut.drainEvents()
  await doubleTap.shortcut.waitForTerminalObservation()
  var doubleTapArming: DictationShortcutOwnership?
  doubleTap.handler.onArming = { doubleTapArming = doubleTap.shortcut.activeOwnership }
  doubleTap.clock.advance(by: .milliseconds(100))
  doubleTap.monitor.emit(.pressed(.rightOption))
  await doubleTap.shortcut.drainEvents()
  #expect(doubleTapArming?.trigger == .doubleTap)
  #expect(doubleTapArming?.mode == .smartCapture)
  #expect(doubleTapArming?.isHandsFree == true)
  await doubleTap.shortcut.cancelOwnedSession()
  await doubleTap.shortcut.waitForTerminalObservation()

  let pointer = ShortcutFixture()
  var pointerArming: DictationShortcutOwnership?
  pointer.handler.onArming = { pointerArming = pointer.shortcut.activeOwnership }
  #expect(pointer.shortcut.startPointerHandsFree())
  #expect(pointerArming?.trigger == .pointer)
  #expect(pointerArming?.mode == .smartCapture)
  #expect(pointerArming?.isHandsFree == true)
  await pointer.shortcut.cancelOwnedSession()
  await pointer.shortcut.waitForTerminalObservation()
}

@MainActor
private final class ShortcutFixture {
  let handler = ShortcutHoldSpy()
  let monitor = ModifierMonitorSpy()
  let escape = EscapeRegistrarSpy()
  let clock = TestGestureClock()
  let shortcut: GlobalHoldShortcut

  init(
    editorProvider: @escaping @MainActor () -> (any FocusedDictationEditing)? = { nil },
    destinationProvider: @escaping @MainActor () -> DictationDestination? = { nil }
  ) {
    shortcut = GlobalHoldShortcut(
      handler: handler,
      editorProvider: editorProvider,
      destinationProvider: destinationProvider,
      monitor: monitor,
      clock: clock,
      escapeRegistrar: escape
    )
  }

  func startHandsFree() async {
    monitor.emit(.pressed(.rightOption))
    clock.advance(by: .milliseconds(40))
    monitor.emit(.released(.rightOption))
    clock.advance(by: .milliseconds(100))
    monitor.emit(.pressed(.rightOption))
    monitor.emit(.released(.rightOption))
    await shortcut.drainEvents()
  }
}

@MainActor
private final class ShortcutHoldSpy: ShortcutHoldHandling {
  enum Event: Equatable {
    case begin
    case releaseReceipt
    case end
    case handsFreeBegin
    case handsFreeFinish
    case cancel
  }

  var canConfigureShortcut = true
  var acceptsShortcut = true
  var acceptsHandsFree = true
  var autoCompleteTerminal = true
  var onArming: (() -> Void)?
  private(set) var events: [Event] = []
  private(set) var beginGestures: [DictationPhysicalGesture] = []
  private(set) var releaseGestures: [DictationPhysicalGesture] = []
  private(set) var endGestures: [DictationPhysicalGesture] = []
  private(set) var handsFreeStopOrigins: [DictationStopOrigin] = []
  var endGate: TerminalGate?
  private var sessions: [UUID: TerminalGate] = [:]
  private var currentSession: DictationShortcutSession?

  private(set) var lastEditor: (any FocusedDictationEditing)?
  private(set) var lastDestination: DictationDestination?

  var lastSession: DictationShortcutSession? { currentSession }

  var beginCount: Int { events.count { $0 == .begin } }
  var endCount: Int { events.count { $0 == .end } }
  var handsFreeBeginCount: Int { events.count { $0 == .handsFreeBegin } }
  var handsFreeFinishCount: Int { events.count { $0 == .handsFreeFinish } }
  var cancelCount: Int { events.count { $0 == .cancel } }

  func beginShortcut(
    session: DictationShortcutSession,
    editor: (any FocusedDictationEditing)?,
    destination: DictationDestination?,
    physicalGesture: DictationPhysicalGesture
  ) -> Bool {
    events.append(.begin)
    beginGestures.append(physicalGesture)
    lastEditor = editor
    lastDestination = destination
    onArming?()
    guard acceptsShortcut else { return false }
    store(session)
    return true
  }

  func beginHandsFreeShortcut(
    session: DictationShortcutSession,
    editor: (any FocusedDictationEditing)?,
    destination: DictationDestination?,
    physicalGesture: DictationPhysicalGesture
  ) -> Bool {
    events.append(.handsFreeBegin)
    beginGestures.append(physicalGesture)
    lastEditor = editor
    lastDestination = destination
    onArming?()
    guard acceptsHandsFree else { return false }
    store(session)
    return true
  }

  func recordPhysicalRelease(
    _ session: DictationShortcutSession,
    physicalGesture: DictationPhysicalGesture
  ) {
    events.append(.releaseReceipt)
    releaseGestures.append(physicalGesture)
  }

  func endShortcut(
    _ session: DictationShortcutSession,
    physicalGesture: DictationPhysicalGesture
  ) async {
    events.append(.end)
    endGestures.append(physicalGesture)
    await endGate?.wait()
    if autoCompleteTerminal { sessions[session.id]?.open() }
  }

  func finishHandsFreeShortcut(
    _ session: DictationShortcutSession,
    stopOrigin: DictationStopOrigin
  ) async {
    events.append(.handsFreeFinish)
    handsFreeStopOrigins.append(stopOrigin)
    if autoCompleteTerminal { sessions[session.id]?.open() }
  }

  func cancelShortcut(_ session: DictationShortcutSession) async {
    events.append(.cancel)
    if autoCompleteTerminal { sessions[session.id]?.open() }
  }

  func waitForShortcutTerminal(_ session: DictationShortcutSession) async {
    await sessions[session.id]?.wait()
  }

  func completeCurrentTerminal() {
    guard let currentSession else { return }
    sessions[currentSession.id]?.open()
  }

  private func store(_ session: DictationShortcutSession) {
    sessions[session.id] = TerminalGate()
    currentSession = session
  }
}

@MainActor
private final class ShortcutEditorSpy: FocusedDictationEditing {
  var canBeginFocusedDictation: Bool

  init(canBeginFocusedDictation: Bool) {
    self.canBeginFocusedDictation = canBeginFocusedDictation
  }

  func beginFocusedDictation() -> Bool { true }
  func updateFocusedDictation(provisionalText: String) {}
  func commitFocusedDictation(text: String) -> FocusedDictationCommitReceipt? {
    FocusedDictationCommitReceipt()
  }
  func cancelFocusedDictation() {}
  func rollbackCommittedFocusedDictation(_ receipt: FocusedDictationCommitReceipt) -> Bool {
    true
  }
  func finalizeCommittedFocusedDictation(_ receipt: FocusedDictationCommitReceipt) {}
}

@MainActor
private final class ModifierMonitorSpy: ModifierKeyMonitoring {
  var transitionHandler: ((ModifierKeyTransition) -> Void)?
  var stateHandler: ((ModifierMonitorState) -> Void)?
  var accessGranted = true
  var startError: Error?
  private(set) var startCount = 0
  private(set) var stopCount = 0
  private let disabledTapRecovery = ModifierKeyEventTap.DisabledTapRecovery()

  func start() throws {
    startCount += 1
    if let startError { throw startError }
    stateHandler?(.running)
  }

  func stop() {
    stopCount += 1
    stateHandler?(.stopped)
  }

  func requestAccess() -> Bool {
    accessGranted
  }

  func emit(_ transition: ModifierKeyTransition) {
    transitionHandler?(transition)
  }

  func publish(_ state: ModifierMonitorState) {
    stateHandler?(state)
  }

  func recoverDisabledTap(succeeds: Bool = true) -> Bool {
    let recovered = disabledTapRecovery.recover(
      stateHandler: { [weak self] state in
        self?.stateHandler?(state)
      },
      synchronize: {},
      reenable: { succeeds }
    )
    if !recovered {
      disabledTapRecovery.reset()
      stateHandler?(.failed)
    }
    return recovered
  }
}

@MainActor
private final class EscapeRegistrarSpy: EscapeHotKeyRegistering {
  var eventHandler: (() -> Void)?
  private(set) var registerCount = 0
  private(set) var unregisterCount = 0

  func register() throws {
    registerCount += 1
  }

  func unregister() {
    unregisterCount += 1
  }

  func emit() {
    eventHandler?()
  }
}

@MainActor
private final class TestGestureClock: GestureClock {
  private(set) var now = ContinuousClock().now

  func advance(by duration: Duration) {
    now = now.advanced(by: duration)
  }
}

private final class TerminalGate: @unchecked Sendable {
  private let lock = NSLock()
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    let shouldWait = lock.withLock {
      if isOpen { return false }
      return true
    }
    guard shouldWait else { return }
    await withCheckedContinuation { continuation in
      lock.withLock {
        if isOpen {
          continuation.resume()
        } else {
          waiters.append(continuation)
        }
      }
    }
  }

  func open() {
    let pending = lock.withLock {
      isOpen = true
      defer { waiters.removeAll() }
      return waiters
    }
    pending.forEach { $0.resume() }
  }
}
