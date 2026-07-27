#if os(macOS)
  import Carbon
  import MenuBarNotesCore

  @MainActor
  protocol ShortcutHoldHandling: AnyObject {
    func beginShortcut(editor: (any FocusedDictationEditing)?) -> DictationShortcutSession?
    func endShortcut(_ session: DictationShortcutSession) async
    func cancelShortcut(_ session: DictationShortcutSession) async
    func waitForShortcutTerminal(_ session: DictationShortcutSession) async
  }

  extension DictationCoordinator: ShortcutHoldHandling {}

  @MainActor
  protocol GlobalHotKeyRegistering: AnyObject {
    var eventHandler: ((UInt32, Bool) -> Void)? { get set }
    func register(keyCode: UInt32, modifiers: UInt32, id: UInt32) throws
    func unregister(id: UInt32)
  }

  @MainActor
  final class GlobalHoldShortcut {
    enum RegistrationError: Error, Equatable {
      case activeSession
      case conflict(OSStatus)
      case eventDeliveryPending
      case primaryKeyHeld
      case system(OSStatus)
      case uninstalled
    }

    static let primaryID: UInt32 = 1
    static let escapeID: UInt32 = 2
    static let escapeKeyCode: UInt32 = 53

    private weak var handler: (any ShortcutHoldHandling)?
    private let editorProvider: @MainActor () -> (any FocusedDictationEditing)?
    private let registrar: any GlobalHotKeyRegistering
    private let onRegistrationError: @MainActor (RegistrationError) -> Void
    private var primaryRegistered = false
    private var escapeRegistered = false
    private var physicalPrimaryDown = false
    private var escapeCancellationRequested = false
    private var acceptedSession: DictationShortcutSession?
    private var deliveryTask: Task<Void, Never>?
    private var pendingDeliveryCount = 0
    private var terminalTask: Task<Void, Never>?
    private var isUninstalled = false

    init(
      handler: any ShortcutHoldHandling,
      editorProvider: @escaping @MainActor () -> (any FocusedDictationEditing)? = { nil },
      registrar: any GlobalHotKeyRegistering = CarbonHotKeyRegistrar(),
      onRegistrationError: @escaping @MainActor (RegistrationError) -> Void = { _ in }
    ) {
      self.handler = handler
      self.editorProvider = editorProvider
      self.registrar = registrar
      self.onRegistrationError = onRegistrationError
      registrar.eventHandler = { [weak self] id, pressed in
        self?.enqueue(id: id, pressed: pressed)
      }
    }

    func configure(_ shortcut: DictationShortcut) throws {
      guard !isUninstalled else { throw RegistrationError.uninstalled }
      guard pendingDeliveryCount == 0 else { throw RegistrationError.eventDeliveryPending }
      guard acceptedSession == nil else { throw RegistrationError.activeSession }
      guard !physicalPrimaryDown else { throw RegistrationError.primaryKeyHeld }
      if primaryRegistered {
        registrar.unregister(id: Self.primaryID)
        primaryRegistered = false
      }
      guard shortcut.isEnabled, let keyCode = shortcut.keyCode else { return }
      try registrar.register(
        keyCode: keyCode,
        modifiers: shortcut.carbonModifiers,
        id: Self.primaryID
      )
      primaryRegistered = true
    }

    func drainEvents() async {
      await deliveryTask?.value
    }

    func waitForTerminalObservation() async {
      await terminalTask?.value
    }

    func uninstall() async {
      registrar.eventHandler = nil
      isUninstalled = true
      await drainEvents()
      physicalPrimaryDown = false
      if let acceptedSession, let handler {
        await handler.cancelShortcut(acceptedSession)
        await terminalTask?.value
      }
      unregisterAll()
    }

    private func enqueue(id: UInt32, pressed: Bool) {
      guard !isUninstalled else { return }
      pendingDeliveryCount += 1
      let previous = deliveryTask
      deliveryTask = Task { @MainActor [weak self] in
        await previous?.value
        await self?.deliver(id: id, pressed: pressed)
      }
    }

    private func deliver(id: UInt32, pressed: Bool) async {
      defer { pendingDeliveryCount -= 1 }
      await receive(id: id, pressed: pressed)
    }

    private func receive(id: UInt32, pressed: Bool) async {
      if id == Self.primaryID {
        guard primaryRegistered else { return }
        if pressed {
          guard !physicalPrimaryDown else { return }
          physicalPrimaryDown = true
          guard let session = handler?.beginShortcut(editor: editorProvider()) else { return }
          acceptedSession = session
          escapeCancellationRequested = false
          registerEscape()
          observeTerminal(session)
        } else {
          guard physicalPrimaryDown else { return }
          physicalPrimaryDown = false
          guard let acceptedSession else { return }
          await handler?.endShortcut(acceptedSession)
        }
        return
      }

      guard
        id == Self.escapeID,
        pressed,
        escapeRegistered,
        !escapeCancellationRequested,
        let acceptedSession
      else { return }
      escapeCancellationRequested = true
      await handler?.cancelShortcut(acceptedSession)
    }

    private func observeTerminal(_ session: DictationShortcutSession) {
      guard let handler else { return }
      terminalTask = Task { @MainActor [weak self] in
        await handler.waitForShortcutTerminal(session)
        guard !Task.isCancelled else { return }
        self?.terminalReached(session)
      }
    }

    private func terminalReached(_ session: DictationShortcutSession) {
      guard acceptedSession == session else { return }
      acceptedSession = nil
      escapeCancellationRequested = false
      unregisterEscape()
    }

    private func registerEscape() {
      guard !escapeRegistered else { return }
      do {
        try registrar.register(
          keyCode: Self.escapeKeyCode,
          modifiers: 0,
          id: Self.escapeID
        )
        escapeRegistered = true
      } catch let error as RegistrationError {
        onRegistrationError(error)
      } catch {
        onRegistrationError(.system(OSStatus(eventInternalErr)))
      }
    }

    private func unregisterEscape() {
      guard escapeRegistered else { return }
      registrar.unregister(id: Self.escapeID)
      escapeRegistered = false
    }

    private func unregisterAll() {
      if primaryRegistered {
        registrar.unregister(id: Self.primaryID)
        primaryRegistered = false
      }
      unregisterEscape()
    }

    isolated deinit {
      registrar.eventHandler = nil
      unregisterAll()
      if let acceptedSession, let handler {
        Task { @MainActor in
          await handler.cancelShortcut(acceptedSession)
        }
      }
    }
  }

  @MainActor
  private final class CarbonHotKeyRegistrar: GlobalHotKeyRegistering {
    var eventHandler: ((UInt32, Bool) -> Void)?

    private static let signature: OSType = 0x4D4F5445
    private var eventHandlerRef: EventHandlerRef?
    private var eventHandlerStatus: OSStatus = noErr
    private var registrations: [UInt32: EventHotKeyRef] = [:]

    init() {
      var eventTypes = [
        EventTypeSpec(
          eventClass: OSType(kEventClassKeyboard),
          eventKind: UInt32(kEventHotKeyPressed)
        ),
        EventTypeSpec(
          eventClass: OSType(kEventClassKeyboard),
          eventKind: UInt32(kEventHotKeyReleased)
        ),
      ]
      eventHandlerStatus = InstallEventHandler(
        GetApplicationEventTarget(),
        { _, event, userData in
          guard let event, let userData else { return OSStatus(eventNotHandledErr) }
          var hotKeyID = EventHotKeyID()
          let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
          )
          guard status == noErr else { return status }
          guard hotKeyID.signature == CarbonHotKeyRegistrar.signature else {
            return OSStatus(eventNotHandledErr)
          }
          let registrar = Unmanaged<CarbonHotKeyRegistrar>.fromOpaque(userData)
            .takeUnretainedValue()
          let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
          MainActor.assumeIsolated {
            registrar.eventHandler?(hotKeyID.id, pressed)
          }
          return noErr
        },
        eventTypes.count,
        &eventTypes,
        Unmanaged.passUnretained(self).toOpaque(),
        &eventHandlerRef
      )
    }

    func register(keyCode: UInt32, modifiers: UInt32, id: UInt32) throws {
      guard eventHandlerStatus == noErr else {
        throw GlobalHoldShortcut.RegistrationError.system(eventHandlerStatus)
      }
      var reference: EventHotKeyRef?
      let status = RegisterEventHotKey(
        keyCode,
        modifiers,
        EventHotKeyID(signature: Self.signature, id: id),
        GetApplicationEventTarget(),
        0,
        &reference
      )
      guard status == noErr, let reference else {
        if status == eventHotKeyExistsErr {
          throw GlobalHoldShortcut.RegistrationError.conflict(status)
        }
        throw GlobalHoldShortcut.RegistrationError.system(status)
      }
      registrations[id] = reference
    }

    func unregister(id: UInt32) {
      guard let reference = registrations.removeValue(forKey: id) else { return }
      UnregisterEventHotKey(reference)
    }

    isolated deinit {
      for reference in registrations.values {
        UnregisterEventHotKey(reference)
      }
      if let eventHandlerRef {
        RemoveEventHandler(eventHandlerRef)
      }
    }
  }
#endif
