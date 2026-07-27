#if os(macOS)
  import Carbon
  import MenuBarNotesCore

  @MainActor
  protocol ShortcutHoldHandling: AnyObject {
    func beginShortcut(editor: (any FocusedDictationEditing)?)
    func endShortcut() async
    func cancel() async
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
      case conflict(OSStatus)
      case system(OSStatus)
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
    private var isPressed = false

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
        Task { @MainActor [weak self] in
          await self?.receive(id: id, pressed: pressed)
        }
      }
    }

    func configure(_ shortcut: DictationShortcut) throws {
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

    func receive(id: UInt32, pressed: Bool) async {
      if id == Self.primaryID {
        guard primaryRegistered else { return }
        if pressed {
          guard !isPressed else { return }
          isPressed = true
          handler?.beginShortcut(editor: editorProvider())
          registerEscape()
        } else {
          guard isPressed else { return }
          isPressed = false
          await handler?.endShortcut()
          unregisterEscape()
        }
        return
      }

      guard id == Self.escapeID, pressed, isPressed else { return }
      isPressed = false
      await handler?.cancel()
      unregisterEscape()
    }

    func uninstall() {
      isPressed = false
      if primaryRegistered {
        registrar.unregister(id: Self.primaryID)
        primaryRegistered = false
      }
      unregisterEscape()
      registrar.eventHandler = nil
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
          Task { @MainActor in
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
