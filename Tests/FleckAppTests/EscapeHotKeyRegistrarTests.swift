import Carbon
import FleckCore
import Testing

@testable import FleckApp

@Test @MainActor
func escapeRegistrarRequestsExactMasksKeyAndOptions() throws {
  let cases: [(DictationModifierKey?, [UInt32])] = [
    (nil, [0]),
    (.function, [0]),
    (.leftOption, [0, 2048]),
    (.rightOption, [0, 2048]),
    (.leftControl, [0, 4096]),
    (.rightControl, [0, 4096]),
    (.leftCommand, [0, 256]),
    (.rightCommand, [0, 256]),
  ]

  for (modifier, masks) in cases {
    let probe = EscapeCarbonProbe()
    let registrar = EscapeHotKeyRegistrar(operations: probe.operations)
    try registrar.register(modifier: modifier)

    #expect(probe.registrations.map(\.keyCode) == Array(repeating: 53, count: masks.count))
    #expect(probe.registrations.map(\.modifiers) == masks)
    #expect(probe.registrations.map(\.options) == Array(repeating: 0, count: masks.count))
    #expect(probe.registrations.allSatisfy {
      $0.hotKeyID.signature == EscapeHotKeyRegistrar.signature
    })
    try registrar.unregister()
  }
}

@Test @MainActor
func escapeRegistrarUsesFreshIDsAndRejectsStaleUnknownAndInvalidatedEvents() throws {
  let probe = EscapeCarbonProbe()
  let registrar = EscapeHotKeyRegistrar(operations: probe.operations)
  var deliveries = 0
  registrar.eventHandler = { deliveries += 1 }

  try registrar.register(modifier: .rightOption)
  let firstIDs = probe.registrations.map(\.hotKeyID)
  try registrar.register(modifier: .rightOption)
  #expect(probe.registrations.count == 2)
  #expect(throws: GlobalHoldShortcut.RegistrationError.activeSession) {
    try registrar.register(modifier: .leftControl)
  }
  #expect(registrar.handleHotKeyID(firstIDs[0]) == noErr)
  #expect(registrar.handleHotKeyID(firstIDs[1]) == noErr)
  #expect(deliveries == 2)
  #expect(registrar.handleHotKeyID(EventHotKeyID(
    signature: EscapeHotKeyRegistrar.signature,
    id: firstIDs[1].id + 1
  )) == eventNotHandledErr)
  #expect(registrar.handleHotKeyID(EventHotKeyID(signature: 0, id: firstIDs[0].id))
    == eventNotHandledErr)

  try registrar.unregister()
  #expect(registrar.handleHotKeyID(firstIDs[0]) == eventNotHandledErr)
  try registrar.register(modifier: .rightOption)
  let secondIDs = Array(probe.registrations.suffix(2).map(\.hotKeyID))
  #expect(Set(firstIDs.map(\.id)).isDisjoint(with: Set(secondIDs.map(\.id))))
  #expect(registrar.handleHotKeyID(firstIDs[1]) == eventNotHandledErr)
  #expect(registrar.handleHotKeyID(secondIDs[1]) == noErr)
}

@Test @MainActor
func escapeRegistrarInstallAndRegistrationFailuresAreTransactional() throws {
  let installFailure = EscapeCarbonProbe()
  installFailure.installResult = (-50, nil)
  let unavailable = EscapeHotKeyRegistrar(operations: installFailure.operations)
  #expect(throws: GlobalHoldShortcut.RegistrationError.system(-50)) {
    try unavailable.register(modifier: .rightOption)
  }
  #expect(installFailure.registrations.isEmpty)

  let missingHandler = EscapeCarbonProbe()
  missingHandler.installResult = (noErr, nil)
  let missingHandlerRegistrar = EscapeHotKeyRegistrar(operations: missingHandler.operations)
  #expect(throws: GlobalHoldShortcut.RegistrationError.system(OSStatus(eventInternalErr))) {
    try missingHandlerRegistrar.register()
  }
  #expect(missingHandler.registrations.isEmpty)

  let firstFailure = EscapeCarbonProbe()
  firstFailure.registrationResults = [(-51, true)]
  let firstRegistrar = EscapeHotKeyRegistrar(operations: firstFailure.operations)
  #expect(throws: GlobalHoldShortcut.RegistrationError.system(-51)) {
    try firstRegistrar.register(modifier: .rightOption)
  }
  #expect(firstFailure.unregistered.count == 1)
  #expect(firstRegistrar.handleHotKeyID(firstFailure.registrations[0].hotKeyID)
    == eventNotHandledErr)

  let nilHandle = EscapeCarbonProbe()
  nilHandle.registrationResults = [(noErr, false)]
  let nilRegistrar = EscapeHotKeyRegistrar(operations: nilHandle.operations)
  #expect(throws: GlobalHoldShortcut.RegistrationError.system(OSStatus(eventInternalErr))) {
    try nilRegistrar.register()
  }

  let secondFailure = EscapeCarbonProbe()
  secondFailure.registrationResults = [(noErr, true), (-52, false)]
  let secondRegistrar = EscapeHotKeyRegistrar(operations: secondFailure.operations)
  #expect(throws: GlobalHoldShortcut.RegistrationError.system(-52)) {
    try secondRegistrar.register(modifier: .rightControl)
  }
  #expect(secondFailure.unregistered.count == 1)
  #expect(secondFailure.registrations.allSatisfy {
    secondRegistrar.handleHotKeyID($0.hotKeyID) == eventNotHandledErr
  })

  let rollbackFailure = EscapeCarbonProbe()
  rollbackFailure.registrationResults = [(noErr, true), (-53, false)]
  rollbackFailure.unregisterResults = [-54]
  let rollbackRegistrar = EscapeHotKeyRegistrar(operations: rollbackFailure.operations)
  #expect(throws: GlobalHoldShortcut.RegistrationError.system(-54)) {
    try rollbackRegistrar.register(modifier: .rightCommand)
  }
}

@Test @MainActor
func escapeRegistrarCleanupAttemptsEveryHandleAndBlocksWhileCleanupRemains() throws {
  let probe = EscapeCarbonProbe()
  probe.unregisterResults = [-61, noErr, -62]
  let registrar = EscapeHotKeyRegistrar(operations: probe.operations)
  try registrar.register(modifier: .leftCommand)
  let activeIDs = probe.registrations.map(\.hotKeyID)

  #expect(throws: GlobalHoldShortcut.RegistrationError.system(-61)) {
    try registrar.unregister()
  }
  #expect(probe.unregistered.count == 2)
  #expect(activeIDs.allSatisfy { registrar.handleHotKeyID($0) == eventNotHandledErr })
  #expect(throws: GlobalHoldShortcut.RegistrationError.system(-62)) {
    try registrar.register(modifier: .leftCommand)
  }
  #expect(probe.registrations.count == 2)

  try registrar.register(modifier: .leftCommand)
  #expect(probe.registrations.count == 4)
}

@MainActor
private final class EscapeCarbonProbe {
  struct Registration {
    let keyCode: UInt32
    let modifiers: UInt32
    let hotKeyID: EventHotKeyID
    let options: OptionBits
    let reference: EventHotKeyRef
  }

  var installResult: (OSStatus, EventHandlerRef?) = (noErr, OpaquePointer(bitPattern: 900))
  var registrationResults: [(OSStatus, Bool)] = []
  var unregisterResults: [OSStatus] = []
  private(set) var registrations: [Registration] = []
  private(set) var unregistered: [EventHotKeyRef] = []
  private(set) var removedHandlers: [EventHandlerRef] = []

  var operations: EscapeHotKeyRegistrar.Operations {
    EscapeHotKeyRegistrar.Operations(
      installHandler: { [self] _, _ in installResult },
      removeHandler: { [self] reference in
        removedHandlers.append(reference)
        return noErr
      },
      registerHotKey: { [self] keyCode, modifiers, hotKeyID, options in
        let index = registrations.count
        let result = index < registrationResults.count
          ? registrationResults[index]
          : (noErr, true)
        let reference = OpaquePointer(bitPattern: 1_000 + index)!
        registrations.append(Registration(
          keyCode: keyCode,
          modifiers: modifiers,
          hotKeyID: hotKeyID,
          options: options,
          reference: reference
        ))
        return (result.0, result.1 ? reference : nil)
      },
      unregisterHotKey: { [self] reference in
        let index = unregistered.count
        unregistered.append(reference)
        return index < unregisterResults.count ? unregisterResults[index] : noErr
      }
    )
  }
}
