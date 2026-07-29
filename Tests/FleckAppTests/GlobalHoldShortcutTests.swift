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

@Test @MainActor func coordinatorGateParticipatesInUnifiedReconfigurationGate() throws {
  let fixture = ShortcutFixture()
  try fixture.shortcut.configure(.rightOption)

  fixture.handler.canConfigureShortcut = false

  #expect(!fixture.shortcut.canChangeModifier)
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

@Test @MainActor func reconfigurationRestartsMonitorAndClearsTapState() async throws {
  let fixture = ShortcutFixture()
  try fixture.shortcut.configure(.rightOption)
  fixture.monitor.emit(.pressed(.rightOption))
  fixture.clock.advance(by: .milliseconds(40))
  fixture.monitor.emit(.released(.rightOption))
  await fixture.shortcut.drainEvents()

  try fixture.shortcut.configure(.leftOption)

  #expect(fixture.monitor.startCount == 2)
  #expect(fixture.monitor.stopCount == 1)
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

@MainActor
private final class ShortcutFixture {
  let handler = ShortcutHoldSpy()
  let monitor = ModifierMonitorSpy()
  let escape = EscapeRegistrarSpy()
  let clock = TestGestureClock()
  let shortcut: GlobalHoldShortcut

  init() {
    shortcut = GlobalHoldShortcut(
      handler: handler,
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
    case end
    case handsFreeBegin
    case handsFreeFinish
    case cancel
  }

  var canConfigureShortcut = true
  var acceptsShortcut = true
  var acceptsHandsFree = true
  private(set) var events: [Event] = []
  private var sessions: [UUID: TerminalGate] = [:]
  private var currentSession: DictationShortcutSession?

  var beginCount: Int { events.count { $0 == .begin } }
  var endCount: Int { events.count { $0 == .end } }
  var handsFreeBeginCount: Int { events.count { $0 == .handsFreeBegin } }
  var handsFreeFinishCount: Int { events.count { $0 == .handsFreeFinish } }
  var cancelCount: Int { events.count { $0 == .cancel } }

  func beginShortcut(
    editor: (any FocusedDictationEditing)?,
    destination: DictationDestination?
  ) -> DictationShortcutSession? {
    events.append(.begin)
    guard acceptsShortcut else { return nil }
    return makeSession()
  }

  func beginHandsFreeShortcut(
    editor: (any FocusedDictationEditing)?,
    destination: DictationDestination?
  ) async -> DictationShortcutSession? {
    events.append(.handsFreeBegin)
    guard acceptsHandsFree else { return nil }
    return makeSession()
  }

  func endShortcut(_ session: DictationShortcutSession) async {
    events.append(.end)
    sessions[session.id]?.open()
  }

  func finishHandsFreeShortcut(_ session: DictationShortcutSession) async {
    events.append(.handsFreeFinish)
    sessions[session.id]?.open()
  }

  func cancelShortcut(_ session: DictationShortcutSession) async {
    events.append(.cancel)
    sessions[session.id]?.open()
  }

  func waitForShortcutTerminal(_ session: DictationShortcutSession) async {
    await sessions[session.id]?.wait()
  }

  func completeCurrentTerminal() {
    guard let currentSession else { return }
    sessions[currentSession.id]?.open()
  }

  private func makeSession() -> DictationShortcutSession {
    let session = DictationShortcutSession(id: UUID())
    sessions[session.id] = TerminalGate()
    currentSession = session
    return session
  }
}

@MainActor
private final class ModifierMonitorSpy: ModifierKeyMonitoring {
  var transitionHandler: ((ModifierKeyTransition) -> Void)?
  var stateHandler: ((ModifierMonitorState) -> Void)?
  var accessGranted = true
  var startError: Error?
  private(set) var startCount = 0
  private(set) var stopCount = 0

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
