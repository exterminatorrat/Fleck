import Foundation
import MenuBarNotesCore
import Testing

@testable import MenuBarNotesApp

@Test @MainActor func GlobalHoldShortcutDoesNotRegisterAnUnassignedShortcut() throws {
  let registrar = HotKeyRegistrarSpy()
  let shortcut = GlobalHoldShortcut(handler: ShortcutHoldSpy(), registrar: registrar)

  try shortcut.configure(DictationShortcut())

  #expect(registrar.registrations.isEmpty)
}

@Test @MainActor func GlobalHoldShortcutRegistersTheExactChosenChord() throws {
  let registrar = HotKeyRegistrarSpy()
  let shortcut = GlobalHoldShortcut(handler: ShortcutHoldSpy(), registrar: registrar)

  try shortcut.configure(DictationShortcut(keyCode: 49, carbonModifiers: 768))

  #expect(registrar.registrations == [
    .init(keyCode: 49, modifiers: 768, id: GlobalHoldShortcut.primaryID)
  ])
}

@Test @MainActor func GlobalHoldShortcutSurfacesRegistrationConflicts() {
  let registrar = HotKeyRegistrarSpy()
  registrar.failure = .conflict(-9876)
  let shortcut = GlobalHoldShortcut(handler: ShortcutHoldSpy(), registrar: registrar)

  #expect(throws: GlobalHoldShortcut.RegistrationError.conflict(-9876)) {
    try shortcut.configure(DictationShortcut(keyCode: 49, carbonModifiers: 768))
  }
}

@Test @MainActor func GlobalHoldShortcutRestoresTheOldChordWhenReplacementConflicts() throws {
  let registrar = HotKeyRegistrarSpy()
  let shortcut = GlobalHoldShortcut(handler: ShortcutHoldSpy(), registrar: registrar)
  let old = DictationShortcut(keyCode: 49, carbonModifiers: 768)
  let replacement = DictationShortcut(keyCode: 36, carbonModifiers: 256)
  try shortcut.configure(old)
  registrar.failingKeyCodes.insert(36)

  #expect(throws: GlobalHoldShortcut.RegistrationError.conflict(-9876)) {
    try shortcut.configure(replacement)
  }

  #expect(shortcut.registeredShortcut == old)
  #expect(registrar.isRegistered(GlobalHoldShortcut.primaryID))
  #expect(registrar.registrations.last == .init(
    keyCode: 49,
    modifiers: 768,
    id: GlobalHoldShortcut.primaryID
  ))
}

@Test @MainActor func GlobalHoldShortcutCanRetryAReplacementAfterItsConflictClears() throws {
  let registrar = HotKeyRegistrarSpy()
  let shortcut = GlobalHoldShortcut(handler: ShortcutHoldSpy(), registrar: registrar)
  let old = DictationShortcut(keyCode: 49, carbonModifiers: 768)
  let replacement = DictationShortcut(keyCode: 36, carbonModifiers: 256)
  try shortcut.configure(old)
  registrar.failingKeyCodes.insert(36)
  #expect(throws: GlobalHoldShortcut.RegistrationError.conflict(-9876)) {
    try shortcut.configure(replacement)
  }

  registrar.failingKeyCodes.remove(36)
  try shortcut.configure(replacement)

  #expect(shortcut.registeredShortcut == replacement)
  #expect(registrar.registrations.last == .init(
    keyCode: 36,
    modifiers: 256,
    id: GlobalHoldShortcut.primaryID
  ))
}

@Test @MainActor func GlobalHoldShortcutRegistrarPathSerializesRapidPressAndRelease() async throws {
  let registrar = HotKeyRegistrarSpy()
  let handler = ShortcutHoldSpy()
  let shortcut = GlobalHoldShortcut(handler: handler, registrar: registrar)
  try shortcut.configure(DictationShortcut(keyCode: 49, carbonModifiers: 768))

  registrar.emit(id: GlobalHoldShortcut.primaryID, pressed: true)
  registrar.emit(id: GlobalHoldShortcut.primaryID, pressed: false)
  await shortcut.drainEvents()

  #expect(handler.events == [.begin, .end])
  #expect(registrar.isRegistered(GlobalHoldShortcut.escapeID))
  await handler.completeTerminal()
  await shortcut.waitForTerminalObservation()
  #expect(!registrar.isRegistered(GlobalHoldShortcut.escapeID))
}

@Test @MainActor func GlobalHoldShortcutPressesOnceAndIgnoresRegistrarKeyRepeat() async throws {
  let registrar = HotKeyRegistrarSpy()
  let handler = ShortcutHoldSpy()
  let shortcut = GlobalHoldShortcut(handler: handler, registrar: registrar)
  try shortcut.configure(DictationShortcut(keyCode: 49, carbonModifiers: 768))

  registrar.emit(id: GlobalHoldShortcut.primaryID, pressed: true)
  registrar.emit(id: GlobalHoldShortcut.primaryID, pressed: true)
  await shortcut.drainEvents()

  #expect(handler.beginCount == 1)
  #expect(registrar.registrations.last == .init(
    keyCode: GlobalHoldShortcut.escapeKeyCode,
    modifiers: 0,
    id: GlobalHoldShortcut.escapeID
  ))
}

@Test @MainActor func GlobalHoldShortcutRejectedPressCannotEndOrCancelAnotherCapture() async throws {
  let registrar = HotKeyRegistrarSpy()
  let handler = ShortcutHoldSpy()
  handler.acceptsShortcut = false
  let shortcut = GlobalHoldShortcut(handler: handler, registrar: registrar)
  try shortcut.configure(DictationShortcut(keyCode: 49, carbonModifiers: 768))

  registrar.emit(id: GlobalHoldShortcut.primaryID, pressed: true)
  registrar.emit(id: GlobalHoldShortcut.escapeID, pressed: true)
  registrar.emit(id: GlobalHoldShortcut.primaryID, pressed: false)
  await shortcut.drainEvents()

  #expect(handler.beginCount == 1)
  #expect(handler.endCount == 0)
  #expect(handler.cancelCount == 0)
  #expect(!registrar.isRegistered(GlobalHoldShortcut.escapeID))
}

@Test @MainActor func GlobalHoldShortcutFailureWhileHeldRemovesEscapeWithoutEndingAgain() async throws {
  let registrar = HotKeyRegistrarSpy()
  let handler = ShortcutHoldSpy()
  let shortcut = GlobalHoldShortcut(handler: handler, registrar: registrar)
  try shortcut.configure(DictationShortcut(keyCode: 49, carbonModifiers: 768))
  registrar.emit(id: GlobalHoldShortcut.primaryID, pressed: true)
  await shortcut.drainEvents()

  await handler.completeTerminal()
  await shortcut.waitForTerminalObservation()
  registrar.emit(id: GlobalHoldShortcut.primaryID, pressed: false)
  await shortcut.drainEvents()

  #expect(handler.endCount == 0)
  #expect(!registrar.isRegistered(GlobalHoldShortcut.escapeID))
}

@Test @MainActor func GlobalHoldShortcutEscapeStaysRegisteredUntilCancellationTerminates() async throws {
  let registrar = HotKeyRegistrarSpy()
  let handler = ShortcutHoldSpy()
  let shortcut = GlobalHoldShortcut(handler: handler, registrar: registrar)
  try shortcut.configure(DictationShortcut(keyCode: 49, carbonModifiers: 768))
  registrar.emit(id: GlobalHoldShortcut.primaryID, pressed: true)
  registrar.emit(id: GlobalHoldShortcut.escapeID, pressed: true)
  registrar.emit(id: GlobalHoldShortcut.escapeID, pressed: true)
  await shortcut.drainEvents()

  #expect(handler.cancelCount == 1)
  #expect(registrar.isRegistered(GlobalHoldShortcut.escapeID))
  await handler.completeTerminal()
  await shortcut.waitForTerminalObservation()

  #expect(!registrar.isRegistered(GlobalHoldShortcut.escapeID))
}

@Test @MainActor func GlobalHoldShortcutRejectsReconfigurationWhileItOwnsASession() async throws {
  let registrar = HotKeyRegistrarSpy()
  let handler = ShortcutHoldSpy()
  let shortcut = GlobalHoldShortcut(handler: handler, registrar: registrar)
  try shortcut.configure(DictationShortcut(keyCode: 49, carbonModifiers: 768))
  registrar.emit(id: GlobalHoldShortcut.primaryID, pressed: true)
  await shortcut.drainEvents()

  #expect(throws: GlobalHoldShortcut.RegistrationError.activeSession) {
    try shortcut.configure(DictationShortcut(keyCode: 36, carbonModifiers: 256))
  }
  #expect(registrar.registrations.first == .init(
    keyCode: 49,
    modifiers: 768,
    id: GlobalHoldShortcut.primaryID
  ))
}

@Test @MainActor func GlobalHoldShortcutRejectsReconfigurationWhileRejectedPressIsHeld() async throws {
  let registrar = HotKeyRegistrarSpy()
  let handler = ShortcutHoldSpy()
  handler.acceptsShortcut = false
  let shortcut = GlobalHoldShortcut(handler: handler, registrar: registrar)
  try shortcut.configure(DictationShortcut(keyCode: 49, carbonModifiers: 768))
  registrar.emit(id: GlobalHoldShortcut.primaryID, pressed: true)
  await shortcut.drainEvents()

  #expect(throws: GlobalHoldShortcut.RegistrationError.primaryKeyHeld) {
    try shortcut.configure(DictationShortcut(keyCode: 36, carbonModifiers: 256))
  }

  #expect(registrar.registrations == [
    .init(keyCode: 49, modifiers: 768, id: GlobalHoldShortcut.primaryID)
  ])
  #expect(registrar.isRegistered(GlobalHoldShortcut.primaryID))
}

@Test @MainActor func GlobalHoldShortcutRejectsConfigureBeforeQueuedPressDelivery() async throws {
  let registrar = HotKeyRegistrarSpy()
  let handler = ShortcutHoldSpy()
  handler.acceptsShortcut = false
  let shortcut = GlobalHoldShortcut(handler: handler, registrar: registrar)
  try shortcut.configure(DictationShortcut(keyCode: 49, carbonModifiers: 768))

  registrar.emit(id: GlobalHoldShortcut.primaryID, pressed: true)
  #expect(throws: GlobalHoldShortcut.RegistrationError.eventDeliveryPending) {
    try shortcut.configure(DictationShortcut(keyCode: 36, carbonModifiers: 256))
  }
  #expect(registrar.registrations == [
    .init(keyCode: 49, modifiers: 768, id: GlobalHoldShortcut.primaryID)
  ])

  await shortcut.drainEvents()
  registrar.emit(id: GlobalHoldShortcut.primaryID, pressed: false)
  await shortcut.drainEvents()
  try shortcut.configure(DictationShortcut(keyCode: 36, carbonModifiers: 256))

  #expect(registrar.registrations.last == .init(
    keyCode: 36,
    modifiers: 256,
    id: GlobalHoldShortcut.primaryID
  ))
}

@Test @MainActor func GlobalHoldShortcutUninstallCancelsItsOwnedSessionAndCleansRegistrations() async throws {
  let registrar = HotKeyRegistrarSpy()
  let handler = ShortcutHoldSpy()
  handler.completesWhenCancelled = true
  let shortcut = GlobalHoldShortcut(handler: handler, registrar: registrar)
  try shortcut.configure(DictationShortcut(keyCode: 49, carbonModifiers: 768))
  registrar.emit(id: GlobalHoldShortcut.primaryID, pressed: true)
  await shortcut.drainEvents()

  await shortcut.uninstall()

  #expect(handler.cancelCount == 1)
  #expect(registrar.registeredIDs.isEmpty)
  #expect(registrar.unregisteredIDs.contains(GlobalHoldShortcut.primaryID))
  #expect(registrar.unregisteredIDs.contains(GlobalHoldShortcut.escapeID))
}

@Test @MainActor func GlobalHoldShortcutMarksUninstalledBeforeQueuedDeliveryDrain() async throws {
  let registrar = HotKeyRegistrarSpy()
  let handler = ShortcutHoldSpy()
  let cancellationGate = TerminalGate()
  handler.cancellationGate = cancellationGate
  handler.completesWhenCancelled = true
  let shortcut = GlobalHoldShortcut(handler: handler, registrar: registrar)
  try shortcut.configure(DictationShortcut(keyCode: 49, carbonModifiers: 768))
  registrar.emit(id: GlobalHoldShortcut.primaryID, pressed: true)
  await shortcut.drainEvents()

  registrar.emit(id: GlobalHoldShortcut.escapeID, pressed: true)
  let uninstall = Task { await shortcut.uninstall() }
  await cancellationGate.waitUntilWaiting()

  #expect(throws: GlobalHoldShortcut.RegistrationError.uninstalled) {
    try shortcut.configure(DictationShortcut(keyCode: 36, carbonModifiers: 256))
  }
  await cancellationGate.openGate()
  await uninstall.value

  #expect(registrar.registeredIDs.isEmpty)
}

@Test @MainActor func GlobalHoldShortcutRejectsConfigurationAfterUninstall() async throws {
  let registrar = HotKeyRegistrarSpy()
  let shortcut = GlobalHoldShortcut(handler: ShortcutHoldSpy(), registrar: registrar)
  try shortcut.configure(DictationShortcut(keyCode: 49, carbonModifiers: 768))
  await shortcut.uninstall()

  #expect(throws: GlobalHoldShortcut.RegistrationError.uninstalled) {
    try shortcut.configure(DictationShortcut(keyCode: 36, carbonModifiers: 256))
  }

  #expect(registrar.registrations == [
    .init(keyCode: 49, modifiers: 768, id: GlobalHoldShortcut.primaryID)
  ])
  #expect(registrar.registeredIDs.isEmpty)
}

@Test @MainActor func GlobalHoldShortcutDeinitCancelsItsOwnedSessionAndCleansRegistrations() async throws {
  let registrar = HotKeyRegistrarSpy()
  let handler = ShortcutHoldSpy()
  handler.completesWhenCancelled = true
  var shortcut: GlobalHoldShortcut? = GlobalHoldShortcut(handler: handler, registrar: registrar)
  try shortcut?.configure(DictationShortcut(keyCode: 49, carbonModifiers: 768))
  registrar.emit(id: GlobalHoldShortcut.primaryID, pressed: true)
  await shortcut?.drainEvents()

  shortcut = nil
  await Task.yield()
  await Task.yield()

  #expect(handler.cancelCount == 1)
  #expect(registrar.registeredIDs.isEmpty)
}

@MainActor
private final class ShortcutHoldSpy: ShortcutHoldHandling {
  enum Event: Equatable {
    case begin, end, cancel
  }

  private let session = DictationShortcutSession(id: UUID())
  private let terminal = TerminalGate()
  var acceptsShortcut = true
  var cancellationGate: TerminalGate?
  var completesWhenCancelled = false
  private(set) var events: [Event] = []

  var beginCount: Int { events.count { $0 == .begin } }
  var endCount: Int { events.count { $0 == .end } }
  var cancelCount: Int { events.count { $0 == .cancel } }

  func beginShortcut(editor: (any FocusedDictationEditing)?) -> DictationShortcutSession? {
    events.append(.begin)
    return acceptsShortcut ? session : nil
  }

  func endShortcut(_ session: DictationShortcutSession) async {
    events.append(.end)
  }

  func cancelShortcut(_ session: DictationShortcutSession) async {
    events.append(.cancel)
    if let cancellationGate { await cancellationGate.wait() }
    if completesWhenCancelled { await terminal.openGate() }
  }

  func waitForShortcutTerminal(_ session: DictationShortcutSession) async {
    await terminal.wait()
  }

  func completeTerminal() async {
    await terminal.openGate()
  }
}

@MainActor
private final class HotKeyRegistrarSpy: GlobalHotKeyRegistering {
  struct Registration: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let id: UInt32
  }

  var eventHandler: ((UInt32, Bool) -> Void)?
  var failure: GlobalHoldShortcut.RegistrationError?
  var failingKeyCodes = Set<UInt32>()
  private(set) var registrations: [Registration] = []
  private(set) var registeredIDs = Set<UInt32>()
  private(set) var unregisteredIDs: [UInt32] = []

  func register(keyCode: UInt32, modifiers: UInt32, id: UInt32) throws {
    if let failure { throw failure }
    if failingKeyCodes.contains(keyCode) {
      throw GlobalHoldShortcut.RegistrationError.conflict(-9876)
    }
    registrations.append(.init(keyCode: keyCode, modifiers: modifiers, id: id))
    registeredIDs.insert(id)
  }

  func unregister(id: UInt32) {
    registeredIDs.remove(id)
    unregisteredIDs.append(id)
  }

  func emit(id: UInt32, pressed: Bool) {
    eventHandler?(id, pressed)
  }

  func isRegistered(_ id: UInt32) -> Bool {
    registeredIDs.contains(id)
  }
}

private actor TerminalGate {
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private var waitingObservers: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    guard !isOpen else { return }
    let observers = waitingObservers
    waitingObservers = []
    observers.forEach { $0.resume() }
    await withCheckedContinuation { waiters.append($0) }
  }

  func waitUntilWaiting() async {
    guard waiters.isEmpty else { return }
    await withCheckedContinuation { waitingObservers.append($0) }
  }

  func openGate() {
    isOpen = true
    let pending = waiters
    waiters = []
    pending.forEach { $0.resume() }
  }
}
