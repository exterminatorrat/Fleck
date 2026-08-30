#if os(macOS)
  import Carbon
  import FleckCore

  @MainActor
  protocol ShortcutHoldHandling: AnyObject {
    var canConfigureShortcut: Bool { get }
    func beginShortcut(
      editor: (any FocusedDictationEditing)?,
      destination: DictationDestination?,
      physicalGesture: DictationPhysicalGesture
    ) -> DictationShortcutSession?
    func beginHandsFreeShortcut(
      editor: (any FocusedDictationEditing)?,
      destination: DictationDestination?,
      physicalGesture: DictationPhysicalGesture
    ) -> DictationShortcutSession?
    func endShortcut(
      _ session: DictationShortcutSession,
      physicalGesture: DictationPhysicalGesture
    ) async
    func finishHandsFreeShortcut(_ session: DictationShortcutSession) async
    func cancelShortcut(_ session: DictationShortcutSession) async
    func waitForShortcutTerminal(_ session: DictationShortcutSession) async
  }

  extension DictationCoordinator: ShortcutHoldHandling {}

  @MainActor
  protocol GestureClock: AnyObject {
    var now: ContinuousClock.Instant { get }
  }

  @MainActor
  private final class ContinuousGestureClock: GestureClock {
    private let clock = ContinuousClock()
    var now: ContinuousClock.Instant { clock.now }
  }

  @MainActor
  protocol EscapeHotKeyRegistering: AnyObject {
    var eventHandler: (() -> Void)? { get set }
    func register() throws
    func unregister()
  }

  @MainActor
  final class GlobalHoldShortcut {
    enum RegistrationError: Error, Equatable {
      case activeSession
      case eventDeliveryPending
      case monitorFailed
      case primaryKeyHeld
      case system(OSStatus)
      case unauthorized
      case uninstalled
    }

    private enum Delivery {
      case transition(ModifierKeyTransition, ContinuousClock.Instant)
      case escape
      case monitorLost
    }

    static let holdThreshold = Duration.milliseconds(180)
    static let doubleTapWindow = Duration.milliseconds(320)

    private weak var handler: (any ShortcutHoldHandling)?
    private let editorProvider: @MainActor () -> (any FocusedDictationEditing)?
    private let destinationProvider: @MainActor () -> DictationDestination?
    private let monitor: any ModifierKeyMonitoring
    private let clock: any GestureClock
    private let escapeRegistrar: any EscapeHotKeyRegistering
    private let onRegistrationError: @MainActor (RegistrationError) -> Void
    var monitorStateHandler: @MainActor (ModifierMonitorState) -> Void
    private var monitorStopExpected = false
    private var escapeRegistered = false
    private var escapeCancellationRequested = false
    private var physicalPrimaryDown = false
    private var pressStartedAt: ContinuousClock.Instant?
    private var acceptedPressAt: ContinuousClock.Instant?
    private var lastShortRelease: ContinuousClock.Instant?
    private var acceptedSession: DictationShortcutSession?
    private var handsFreeSession: DictationShortcutSession?
    private var ignoresReleaseAfterHandsFreeStart = false
    private var deliveryTask: Task<Void, Never>?
    private var pendingDeliveryCount = 0
    private var terminalTask: Task<Void, Never>?
    private var isUninstalled = false
    private(set) var monitorState = ModifierMonitorState.stopped
    private(set) var registeredModifier: DictationModifierKey?

    var canChangeModifier: Bool {
      handler?.canConfigureShortcut == true
        && !physicalPrimaryDown
        && pendingDeliveryCount == 0
        && acceptedSession == nil
    }

    init(
      handler: any ShortcutHoldHandling,
      editorProvider: @escaping @MainActor () -> (any FocusedDictationEditing)? = { nil },
      destinationProvider: @escaping @MainActor () -> DictationDestination? = { nil },
      monitor: any ModifierKeyMonitoring = ModifierKeyEventTap(),
      clock: any GestureClock = ContinuousGestureClock(),
      escapeRegistrar: any EscapeHotKeyRegistering = EscapeHotKeyRegistrar(),
      onRegistrationError: @escaping @MainActor (RegistrationError) -> Void = { _ in },
      onMonitorStateChange: @escaping @MainActor (ModifierMonitorState) -> Void = { _ in }
    ) {
      self.handler = handler
      self.editorProvider = editorProvider
      self.destinationProvider = destinationProvider
      self.monitor = monitor
      self.clock = clock
      self.escapeRegistrar = escapeRegistrar
      self.onRegistrationError = onRegistrationError
      monitorStateHandler = onMonitorStateChange
      monitor.transitionHandler = { [weak self] transition in
        guard let self else { return }
        self.enqueue(.transition(transition, self.clock.now))
      }
      monitor.stateHandler = { [weak self] state in
        self?.monitorDidChange(state)
      }
      escapeRegistrar.eventHandler = { [weak self] in
        self?.enqueue(.escape)
      }
    }

    func configure(_ modifier: DictationModifierKey) throws {
      guard !isUninstalled else { throw RegistrationError.uninstalled }
      guard handler?.canConfigureShortcut == true else {
        throw RegistrationError.activeSession
      }
      guard pendingDeliveryCount == 0 else { throw RegistrationError.eventDeliveryPending }
      guard acceptedSession == nil else { throw RegistrationError.activeSession }
      guard !physicalPrimaryDown else { throw RegistrationError.primaryKeyHeld }
      guard monitor.accessGranted else {
        if monitorState != .running {
          publishMonitorState(.unauthorized)
        }
        throw RegistrationError.unauthorized
      }
      guard registeredModifier != modifier || monitorState != .running else { return }

      clearTapState()
      if monitorState == .running {
        registeredModifier = modifier
        return
      }
      let previousModifier = registeredModifier
      do {
        try monitor.start()
        registeredModifier = modifier
      } catch {
        registeredModifier = previousModifier
        if monitorState != .unauthorized {
          publishMonitorState(.failed)
        }
        throw monitorState == .unauthorized
          ? RegistrationError.unauthorized
          : RegistrationError.monitorFailed
      }
    }

    @discardableResult
    func preflightAccess() -> Bool {
      let granted = monitor.accessGranted
      if !granted, monitorState != .running {
        publishMonitorState(.unauthorized)
      }
      return granted
    }

    @discardableResult
    func requestAccess() -> Bool {
      let granted = monitor.requestAccess() && monitor.accessGranted
      if !granted, monitorState != .running {
        publishMonitorState(.unauthorized)
      }
      return granted
    }

    func drainEvents() async {
      await deliveryTask?.value
    }

    func waitForTerminalObservation() async {
      await terminalTask?.value
    }

    func uninstall() async {
      guard !isUninstalled else { return }
      isUninstalled = true
      registeredModifier = nil
      monitor.transitionHandler = nil
      monitor.stateHandler = nil
      escapeRegistrar.eventHandler = nil
      monitorStopExpected = true
      monitor.stop()
      monitorStopExpected = false
      await drainEvents()
      physicalPrimaryDown = false
      clearTapState()
      if let acceptedSession, let handler {
        await handler.cancelShortcut(acceptedSession)
        await terminalTask?.value
      }
      acceptedSession = nil
      handsFreeSession = nil
      unregisterEscape()
      publishMonitorState(.stopped)
    }

    private func enqueue(_ delivery: Delivery) {
      guard !isUninstalled else { return }
      pendingDeliveryCount += 1
      let previous = deliveryTask
      deliveryTask = Task { @MainActor [weak self] in
        await previous?.value
        await self?.deliver(delivery)
      }
    }

    private func deliver(_ delivery: Delivery) async {
      defer { pendingDeliveryCount -= 1 }
      switch delivery {
      case .transition(let transition, let instant):
        await receive(transition, at: instant)
      case .escape:
        await receiveEscape()
      case .monitorLost:
        await receiveMonitorLoss()
      }
    }

    private func receive(
      _ transition: ModifierKeyTransition,
      at instant: ContinuousClock.Instant
    ) async {
      guard let registeredModifier else { return }
      switch transition {
      case .pressed(let modifier):
        guard modifier == registeredModifier, !physicalPrimaryDown else { return }
        physicalPrimaryDown = true
        await receiveSelectedPress(at: instant)
      case .released(let modifier):
        guard modifier == registeredModifier, physicalPrimaryDown else { return }
        physicalPrimaryDown = false
        await receiveSelectedRelease(at: instant)
      }
    }

    private func receiveSelectedPress(at now: ContinuousClock.Instant) async {
      if let handsFreeSession {
        lastShortRelease = nil
        ignoresReleaseAfterHandsFreeStart = true
        await handler?.finishHandsFreeShortcut(handsFreeSession)
        return
      }

      if let lastShortRelease {
        let interval = lastShortRelease.duration(to: now)
        self.lastShortRelease = nil
        if interval >= .zero, interval <= Self.doubleTapWindow {
          guard
            let session = handler?.beginHandsFreeShortcut(
              editor: editorProvider(),
              destination: destinationProvider(),
              physicalGesture: .init(pressedAt: now)
            )
          else { return }
          acceptedSession = session
          handsFreeSession = session
          ignoresReleaseAfterHandsFreeStart = true
          escapeCancellationRequested = false
          registerEscape()
          observeTerminal(session)
          return
        }
      }

      pressStartedAt = now
      guard
        let session = handler?.beginShortcut(
          editor: editorProvider(),
          destination: destinationProvider(),
          physicalGesture: .init(pressedAt: now)
        )
      else { return }
      acceptedSession = session
      acceptedPressAt = now
      escapeCancellationRequested = false
      registerEscape()
      observeTerminal(session)
    }

    private func receiveSelectedRelease(at now: ContinuousClock.Instant) async {
      if ignoresReleaseAfterHandsFreeStart {
        ignoresReleaseAfterHandsFreeStart = false
        return
      }
      guard handsFreeSession == nil, let session = acceptedSession else {
        pressStartedAt = nil
        return
      }
      let isShort =
        pressStartedAt.map { $0.duration(to: now) < Self.holdThreshold } ?? false
      acceptedSession = nil
      pressStartedAt = nil
      escapeCancellationRequested = false
      unregisterEscape()
      await handler?.endShortcut(
        session,
        physicalGesture: .init(
          pressedAt: acceptedPressAt,
          releasedAt: now
        )
      )
      acceptedPressAt = nil
      lastShortRelease = isShort ? now : nil
    }

    private func receiveEscape() async {
      guard
        escapeRegistered,
        !escapeCancellationRequested,
        let acceptedSession
      else { return }
      escapeCancellationRequested = true
      clearTapState()
      await handler?.cancelShortcut(acceptedSession)
    }

    private func receiveMonitorLoss() async {
      physicalPrimaryDown = false
      clearTapState()
      guard let acceptedSession else { return }
      escapeCancellationRequested = true
      await handler?.cancelShortcut(acceptedSession)
    }

    private func monitorDidChange(_ state: ModifierMonitorState) {
      publishMonitorState(state)
      guard
        !isUninstalled,
        !monitorStopExpected,
        state == .failed || state == .unauthorized || state == .stopped
      else { return }
      enqueue(.monitorLost)
    }

    private func publishMonitorState(_ state: ModifierMonitorState) {
      monitorState = state
      monitorStateHandler(state)
    }

    private func clearTapState() {
      lastShortRelease = nil
      pressStartedAt = nil
      acceptedPressAt = nil
      ignoresReleaseAfterHandsFreeStart = false
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
      if handsFreeSession == session {
        handsFreeSession = nil
      }
      escapeCancellationRequested = false
      clearTapState()
      unregisterEscape()
    }

    private func registerEscape() {
      guard !escapeRegistered else { return }
      do {
        try escapeRegistrar.register()
        escapeRegistered = true
      } catch let error as RegistrationError {
        onRegistrationError(error)
      } catch {
        onRegistrationError(.system(OSStatus(eventInternalErr)))
      }
    }

    private func unregisterEscape() {
      guard escapeRegistered else { return }
      escapeRegistrar.unregister()
      escapeRegistered = false
    }

    isolated deinit {
      monitor.transitionHandler = nil
      monitor.stateHandler = nil
      escapeRegistrar.eventHandler = nil
      monitor.stop()
      unregisterEscape()
      if let acceptedSession, let handler {
        Task { @MainActor in
          await handler.cancelShortcut(acceptedSession)
        }
      }
    }
  }

  @MainActor
  private final class EscapeHotKeyRegistrar: EscapeHotKeyRegistering {
    var eventHandler: (() -> Void)?

    private static let signature: OSType = 0x4D4F5445
    private static let escapeID: UInt32 = 2
    private static let escapeKeyCode: UInt32 = 53
    private var eventHandlerRef: EventHandlerRef?
    private var eventHandlerStatus = OSStatus(noErr)
    private var registration: EventHotKeyRef?

    init() {
      var eventType = EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard),
        eventKind: UInt32(kEventHotKeyPressed)
      )
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
          guard
            hotKeyID.signature == EscapeHotKeyRegistrar.signature,
            hotKeyID.id == EscapeHotKeyRegistrar.escapeID
          else {
            return OSStatus(eventNotHandledErr)
          }
          let registrar = Unmanaged<EscapeHotKeyRegistrar>.fromOpaque(userData)
            .takeUnretainedValue()
          MainActor.assumeIsolated {
            registrar.eventHandler?()
          }
          return noErr
        },
        1,
        &eventType,
        Unmanaged.passUnretained(self).toOpaque(),
        &eventHandlerRef
      )
    }

    func register() throws {
      guard registration == nil else { return }
      guard eventHandlerStatus == noErr else {
        throw GlobalHoldShortcut.RegistrationError.system(eventHandlerStatus)
      }
      var reference: EventHotKeyRef?
      let status = RegisterEventHotKey(
        Self.escapeKeyCode,
        0,
        EventHotKeyID(signature: Self.signature, id: Self.escapeID),
        GetApplicationEventTarget(),
        0,
        &reference
      )
      guard status == noErr, let reference else {
        throw GlobalHoldShortcut.RegistrationError.system(status)
      }
      registration = reference
    }

    func unregister() {
      guard let registration else { return }
      UnregisterEventHotKey(registration)
      self.registration = nil
    }

    isolated deinit {
      unregister()
      if let eventHandlerRef {
        RemoveEventHandler(eventHandlerRef)
      }
    }
  }
#endif
