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

@Test @MainActor func GlobalHoldShortcutPressesOnceAndIgnoresKeyRepeat() async throws {
  let registrar = HotKeyRegistrarSpy()
  let handler = ShortcutHoldSpy()
  let shortcut = GlobalHoldShortcut(handler: handler, registrar: registrar)
  try shortcut.configure(DictationShortcut(keyCode: 49, carbonModifiers: 768))

  await shortcut.receive(id: GlobalHoldShortcut.primaryID, pressed: true)
  await shortcut.receive(id: GlobalHoldShortcut.primaryID, pressed: true)

  #expect(handler.beginCount == 1)
  #expect(registrar.registrations.last == .init(
    keyCode: GlobalHoldShortcut.escapeKeyCode,
    modifiers: 0,
    id: GlobalHoldShortcut.escapeID
  ))
}

@Test @MainActor func GlobalHoldShortcutShortTapOnlyForwardsOnePressAndRelease() async throws {
  let handler = ShortcutHoldSpy()
  let shortcut = GlobalHoldShortcut(handler: handler, registrar: HotKeyRegistrarSpy())
  try shortcut.configure(DictationShortcut(keyCode: 49, carbonModifiers: 768))

  await shortcut.receive(id: GlobalHoldShortcut.primaryID, pressed: true)
  await shortcut.receive(id: GlobalHoldShortcut.primaryID, pressed: false)
  await shortcut.receive(id: GlobalHoldShortcut.primaryID, pressed: false)

  #expect(handler.beginCount == 1)
  #expect(handler.endCount == 1)
}

@Test @MainActor func GlobalHoldShortcutRegistersEscapeOnlyDuringActiveCapture() async throws {
  let registrar = HotKeyRegistrarSpy()
  let handler = ShortcutHoldSpy()
  let shortcut = GlobalHoldShortcut(handler: handler, registrar: registrar)
  try shortcut.configure(DictationShortcut(keyCode: 49, carbonModifiers: 768))

  #expect(!registrar.isRegistered(GlobalHoldShortcut.escapeID))
  await shortcut.receive(id: GlobalHoldShortcut.primaryID, pressed: true)
  #expect(registrar.isRegistered(GlobalHoldShortcut.escapeID))
  await shortcut.receive(id: GlobalHoldShortcut.primaryID, pressed: false)

  #expect(handler.endCount == 1)
  #expect(!registrar.isRegistered(GlobalHoldShortcut.escapeID))
}

@Test @MainActor func GlobalHoldShortcutEscapeCancelsOnceAndRemovesItsRegistration() async throws {
  let registrar = HotKeyRegistrarSpy()
  let handler = ShortcutHoldSpy()
  let shortcut = GlobalHoldShortcut(handler: handler, registrar: registrar)
  try shortcut.configure(DictationShortcut(keyCode: 49, carbonModifiers: 768))
  await shortcut.receive(id: GlobalHoldShortcut.primaryID, pressed: true)

  await shortcut.receive(id: GlobalHoldShortcut.escapeID, pressed: true)
  await shortcut.receive(id: GlobalHoldShortcut.escapeID, pressed: true)
  await shortcut.receive(id: GlobalHoldShortcut.primaryID, pressed: false)

  #expect(handler.cancelCount == 1)
  #expect(handler.endCount == 0)
  #expect(!registrar.isRegistered(GlobalHoldShortcut.escapeID))
}

@Test @MainActor func GlobalHoldShortcutUnregistersEverythingDuringCleanup() async throws {
  let registrar = HotKeyRegistrarSpy()
  let shortcut = GlobalHoldShortcut(handler: ShortcutHoldSpy(), registrar: registrar)
  try shortcut.configure(DictationShortcut(keyCode: 49, carbonModifiers: 768))
  await shortcut.receive(id: GlobalHoldShortcut.primaryID, pressed: true)

  shortcut.uninstall()

  #expect(registrar.registeredIDs.isEmpty)
  #expect(registrar.unregisteredIDs.contains(GlobalHoldShortcut.primaryID))
  #expect(registrar.unregisteredIDs.contains(GlobalHoldShortcut.escapeID))
}

@MainActor
private final class ShortcutHoldSpy: ShortcutHoldHandling {
  private(set) var beginCount = 0
  private(set) var endCount = 0
  private(set) var cancelCount = 0

  func beginShortcut(editor: (any FocusedDictationEditing)?) {
    beginCount += 1
  }

  func endShortcut() async {
    endCount += 1
  }

  func cancel() async {
    cancelCount += 1
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
  private(set) var registrations: [Registration] = []
  private(set) var registeredIDs = Set<UInt32>()
  private(set) var unregisteredIDs: [UInt32] = []

  func register(keyCode: UInt32, modifiers: UInt32, id: UInt32) throws {
    if let failure { throw failure }
    registrations.append(.init(keyCode: keyCode, modifiers: modifiers, id: id))
    registeredIDs.insert(id)
  }

  func unregister(id: UInt32) {
    registeredIDs.remove(id)
    unregisteredIDs.append(id)
  }

  func isRegistered(_ id: UInt32) -> Bool {
    registeredIDs.contains(id)
  }
}
