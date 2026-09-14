#if os(macOS)
  import Carbon
  import FleckCore

  enum DictationShortcutTrigger: Equatable, Sendable {
    case hold
    case doubleTap
    case pointer
  }

  struct DictationShortcutOwnership: Equatable, Sendable {
    let session: DictationShortcutSession
    let trigger: DictationShortcutTrigger
    let mode: DictationMode
    let isHandsFree: Bool
  }

  @MainActor
  protocol ShortcutHoldHandling: AnyObject {
    var canConfigureShortcut: Bool { get }
    func beginShortcut(
      session: DictationShortcutSession,
      editor: (any FocusedDictationEditing)?,
      destination: DictationDestination?,
      physicalGesture: DictationPhysicalGesture
    ) -> Bool
    func beginHandsFreeShortcut(
      session: DictationShortcutSession,
      editor: (any FocusedDictationEditing)?,
      destination: DictationDestination?,
      physicalGesture: DictationPhysicalGesture
    ) -> Bool
    func recordPhysicalRelease(
      _ session: DictationShortcutSession,
      physicalGesture: DictationPhysicalGesture
    )
    func endShortcut(
      _ session: DictationShortcutSession,
      physicalGesture: DictationPhysicalGesture
    ) async
    func finishHandsFreeShortcut(
      _ session: DictationShortcutSession,
      stopOrigin: DictationStopOrigin
    ) async
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
    func register(modifier: DictationModifierKey?) throws
    func unregister() throws
  }

  extension EscapeHotKeyRegistering {
    func register(modifier _: DictationModifierKey?) throws {
      try register()
    }
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
      case escape(DictationShortcutSession)
      case monitorLost
    }

    private struct NormalizedShortcutContext {
      let editor: (any FocusedDictationEditing)?
      let destination: DictationDestination?
      let mode: DictationMode
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
    private(set) var activeOwnership: DictationShortcutOwnership?
    var ownershipHandler: @MainActor (DictationShortcutOwnership?) -> Void
    private var monitorStopExpected = false
    private var escapeRegistered = false
    private var finishRequested = false
    private var cancelRequested = false
    private var physicalPrimaryDown = false
    private var pressStartedAt: ContinuousClock.Instant?
    private var acceptedPressAt: ContinuousClock.Instant?
    private var lastShortRelease: ContinuousClock.Instant?
    private var ignoresReleaseAfterHandsFreeStart = false
    private var deliveryTask: Task<Void, Never>?
    private var pendingDeliveryCount = 0
    private var terminalTask: Task<Void, Never>?
    private var isUninstalled = false
    private var escapeLifecycleIsRuntimeManaged = false
    private(set) var monitorState = ModifierMonitorState.stopped
    private(set) var registeredModifier: DictationModifierKey?

    var canChangeModifier: Bool {
      handler?.canConfigureShortcut == true
        && !physicalPrimaryDown
        && pendingDeliveryCount == 0
        && activeOwnership == nil
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
      ownershipHandler = { _ in }
      monitor.transitionHandler = { [weak self] transition in
        guard let self else { return }
        let instant = self.clock.now
        self.recordPhysicalReleaseIfNeeded(transition, at: instant)
        self.enqueue(.transition(transition, instant))
      }
      monitor.stateHandler = { [weak self] state in
        self?.monitorDidChange(state)
      }
      escapeRegistrar.eventHandler = { [weak self] in
        guard
          let self,
          !self.escapeLifecycleIsRuntimeManaged,
          let session = self.activeOwnership?.session
        else { return }
        self.enqueue(.escape(session))
      }
    }

    func configure(_ modifier: DictationModifierKey) throws {
      guard !isUninstalled else { throw RegistrationError.uninstalled }
      guard handler?.canConfigureShortcut == true else {
        throw RegistrationError.activeSession
      }
      guard pendingDeliveryCount == 0 else { throw RegistrationError.eventDeliveryPending }
      guard activeOwnership == nil else { throw RegistrationError.activeSession }
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
      await Task.yield()
    }

    func waitForTerminalObservation() async {
      await terminalTask?.value
    }

    func prepareRuntimeEscapeCancellation(_ session: DictationShortcutSession) -> Bool {
      guard let ownership = activeOwnership, ownership.session == session else { return false }
      return prepareCancellation(ownership, allowAfterFinish: true)
    }

    func deliverPreparedRuntimeEscapeCancellation(_ session: DictationShortcutSession) async {
      guard
        activeOwnership?.session == session,
        cancelRequested
      else { return }
      await handler?.cancelShortcut(session)
    }

    func takeEscapeRegistrarForRuntime() -> (any EscapeHotKeyRegistering)? {
      guard
        !isUninstalled,
        !escapeLifecycleIsRuntimeManaged,
        !escapeRegistered,
        activeOwnership == nil,
        pendingDeliveryCount == 0
      else { return nil }
      escapeLifecycleIsRuntimeManaged = true
      escapeRegistrar.eventHandler = nil
      return escapeRegistrar
    }

    @discardableResult
    func startPointerHandsFree() -> Bool {
      beginOwnedSession(
        trigger: .pointer,
        isHandsFree: true,
        physicalGesture: .absent
      )
    }

    func finishOwnedHandsFree() async {
      guard let ownership = activeOwnership, ownership.isHandsFree else { return }
      await requestFinish(
        ownership,
        stopOrigin: .toolbarAction(clock.now)
      )
    }

    func cancelOwnedSession() async {
      guard let ownership = activeOwnership else { return }
      await requestCancel(ownership)
    }

    func uninstall() async {
      guard !isUninstalled else { return }
      isUninstalled = true
      registeredModifier = nil
      monitor.transitionHandler = nil
      monitor.stateHandler = nil
      if !escapeLifecycleIsRuntimeManaged {
        escapeRegistrar.eventHandler = nil
      }
      monitorStopExpected = true
      monitor.stop()
      monitorStopExpected = false
      await drainEvents()
      physicalPrimaryDown = false
      clearTapState()
      if let ownership = activeOwnership, handler != nil {
        await requestCancel(ownership)
        await terminalTask?.value
      }
      if activeOwnership != nil {
        activeOwnership = nil
        finishRequested = false
        cancelRequested = false
        ownershipHandler(nil)
      }
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

    private func recordPhysicalReleaseIfNeeded(
      _ transition: ModifierKeyTransition,
      at instant: ContinuousClock.Instant
    ) {
      guard case .released(let modifier) = transition,
        modifier == registeredModifier,
        physicalPrimaryDown,
        !cancelRequested,
        activeOwnership?.isHandsFree == false,
        !ignoresReleaseAfterHandsFreeStart,
        let session = activeOwnership?.session,
        let pressedAt = acceptedPressAt
      else { return }
      handler?.recordPhysicalRelease(
        session,
        physicalGesture: .init(pressedAt: pressedAt, releasedAt: instant)
      )
    }

    private func deliver(_ delivery: Delivery) async {
      defer { pendingDeliveryCount -= 1 }
      switch delivery {
      case .transition(let transition, let instant):
        await receive(transition, at: instant)
      case .escape(let session):
        await receiveEscape(session)
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
      if let ownership = activeOwnership {
        guard ownership.isHandsFree else {
          guard finishRequested, lastShortRelease != nil else { return }
          await terminalTask?.value
          await receiveSelectedPress(at: now)
          return
        }
        guard !cancelRequested else { return }
        lastShortRelease = nil
        ignoresReleaseAfterHandsFreeStart = true
        await requestFinish(
          ownership,
          stopOrigin: .handsFreeKeyPress(now)
        )
        return
      }

      if let lastShortRelease {
        let interval = lastShortRelease.duration(to: now)
        if interval >= .zero, interval <= Self.doubleTapWindow {
          self.lastShortRelease = nil
          if beginOwnedSession(
            trigger: .doubleTap,
            isHandsFree: true,
            physicalGesture: .init(pressedAt: now)
          ) {
            ignoresReleaseAfterHandsFreeStart = true
          }
          return
        }
        self.lastShortRelease = nil
      }

      pressStartedAt = now
      if beginOwnedSession(
        trigger: .hold,
        isHandsFree: false,
        physicalGesture: .init(pressedAt: now)
      ) {
        acceptedPressAt = now
      }
    }

    private func receiveSelectedRelease(at now: ContinuousClock.Instant) async {
      guard !cancelRequested else {
        clearTapState()
        return
      }
      if ignoresReleaseAfterHandsFreeStart {
        ignoresReleaseAfterHandsFreeStart = false
        return
      }
      guard let ownership = activeOwnership else {
        pressStartedAt = nil
        return
      }
      guard !ownership.isHandsFree else {
        pressStartedAt = nil
        return
      }
      let isShort =
        pressStartedAt.map { $0.duration(to: now) < Self.holdThreshold } ?? false
      let physicalGesture = DictationPhysicalGesture(
        pressedAt: acceptedPressAt,
        releasedAt: now
      )
      pressStartedAt = nil
      acceptedPressAt = nil
      lastShortRelease = isShort ? now : nil
      await requestFinish(ownership, physicalGesture: physicalGesture)
    }

    private func receiveEscape(_ session: DictationShortcutSession) async {
      guard
        escapeRegistered,
        let ownership = activeOwnership,
        ownership.session == session
      else { return }
      await requestCancel(ownership, allowAfterFinish: true)
    }

    private func receiveMonitorLoss() async {
      physicalPrimaryDown = false
      clearTapState()
      guard let ownership = activeOwnership else { return }
      await requestCancel(ownership)
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

    private func normalizedShortcutContext() -> NormalizedShortcutContext {
      let editor = editorProvider()
      let focusedEditor = editor?.canBeginFocusedDictation == true ? editor : nil
      return NormalizedShortcutContext(
        editor: focusedEditor,
        destination: focusedEditor == nil ? nil : destinationProvider(),
        mode: focusedEditor == nil ? .smartCapture : .focused
      )
    }

    @discardableResult
    private func beginOwnedSession(
      trigger: DictationShortcutTrigger,
      isHandsFree: Bool,
      physicalGesture: DictationPhysicalGesture
    ) -> Bool {
      guard !isUninstalled, activeOwnership == nil else { return false }
      let context = normalizedShortcutContext()
      let session = DictationShortcutSession(id: UUID())
      let ownership = DictationShortcutOwnership(
        session: session,
        trigger: trigger,
        mode: context.mode,
        isHandsFree: isHandsFree
      )
      activeOwnership = ownership
      finishRequested = false
      cancelRequested = false

      let accepted = if isHandsFree {
        handler?.beginHandsFreeShortcut(
          session: session,
          editor: context.editor,
          destination: context.destination,
          physicalGesture: physicalGesture
        ) == true
      } else {
        handler?.beginShortcut(
          session: session,
          editor: context.editor,
          destination: context.destination,
          physicalGesture: physicalGesture
        ) == true
      }
      guard accepted else {
        activeOwnership = nil
        return false
      }

      registerEscape()
      observeTerminal(session)
      ownershipHandler(ownership)
      return true
    }

    private func requestFinish(
      _ ownership: DictationShortcutOwnership,
      physicalGesture: DictationPhysicalGesture = .absent,
      stopOrigin: DictationStopOrigin? = nil
    ) async {
      guard
        activeOwnership?.session == ownership.session,
        !finishRequested,
        !cancelRequested
      else { return }
      finishRequested = true
      if ownership.isHandsFree {
        guard let stopOrigin else { return }
        await handler?.finishHandsFreeShortcut(
          ownership.session,
          stopOrigin: stopOrigin
        )
      } else {
        await handler?.endShortcut(
          ownership.session,
          physicalGesture: physicalGesture
        )
      }
    }

    private func requestCancel(
      _ ownership: DictationShortcutOwnership,
      allowAfterFinish: Bool = false
    ) async {
      guard prepareCancellation(ownership, allowAfterFinish: allowAfterFinish) else { return }
      await handler?.cancelShortcut(ownership.session)
    }

    private func prepareCancellation(
      _ ownership: DictationShortcutOwnership,
      allowAfterFinish: Bool
    ) -> Bool {
      guard
        activeOwnership?.session == ownership.session,
        !cancelRequested,
        !finishRequested || ownership.isHandsFree || allowAfterFinish
      else { return false }
      cancelRequested = true
      clearTapState()
      return true
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
      guard let ownership = activeOwnership, ownership.session == session else { return }
      let preserveDoubleTap = ownership.trigger == .hold
        && !ownership.isHandsFree
        && finishRequested
        && lastShortRelease != nil
      activeOwnership = nil
      finishRequested = false
      cancelRequested = false
      if preserveDoubleTap {
        pressStartedAt = nil
        ignoresReleaseAfterHandsFreeStart = false
      } else {
        clearTapState()
      }
      unregisterEscape()
      ownershipHandler(nil)
    }

    private func registerEscape() {
      guard !escapeLifecycleIsRuntimeManaged, !escapeRegistered else { return }
      do {
        try escapeRegistrar.register(modifier: registeredModifier)
        escapeRegistered = true
      } catch let error as RegistrationError {
        onRegistrationError(error)
      } catch {
        onRegistrationError(.system(OSStatus(eventInternalErr)))
      }
    }

    private func unregisterEscape() {
      guard !escapeLifecycleIsRuntimeManaged, escapeRegistered else { return }
      escapeRegistered = false
      do {
        try escapeRegistrar.unregister()
      } catch let error as RegistrationError {
        onRegistrationError(error)
      } catch {
        onRegistrationError(.system(OSStatus(eventInternalErr)))
      }
    }

    isolated deinit {
      monitor.transitionHandler = nil
      monitor.stateHandler = nil
      if !escapeLifecycleIsRuntimeManaged {
        escapeRegistrar.eventHandler = nil
      }
      monitor.stop()
      unregisterEscape()
      if let ownership = activeOwnership, let handler {
        Task { @MainActor in
          await handler.cancelShortcut(ownership.session)
        }
      }
    }
  }

  @MainActor
  final class EscapeHotKeyRegistrar: EscapeHotKeyRegistering {
    struct Operations {
      let installHandler:
        @MainActor (EventHandlerUPP, UnsafeMutableRawPointer) -> (OSStatus, EventHandlerRef?)
      let removeHandler: @MainActor (EventHandlerRef) -> OSStatus
      let registerHotKey:
        @MainActor (UInt32, UInt32, EventHotKeyID, OptionBits) ->
          (OSStatus, EventHotKeyRef?)
      let unregisterHotKey: @MainActor (EventHotKeyRef) -> OSStatus

      @MainActor static let live = Operations(
        installHandler: { handler, userData in
          var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
          )
          var reference: EventHandlerRef?
          let status = InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            userData,
            &reference
          )
          return (status, reference)
        },
        removeHandler: { RemoveEventHandler($0) },
        registerHotKey: { keyCode, modifiers, hotKeyID, options in
          var reference: EventHotKeyRef?
          let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            options,
            &reference
          )
          return (status, reference)
        },
        unregisterHotKey: { UnregisterEventHotKey($0) }
      )
    }

    var eventHandler: (() -> Void)?

    static let signature: OSType = 0x4D4F5445
    static let escapeKeyCode: UInt32 = 53
    private static var nextHotKeyID: UInt32 = 1
    private let operations: Operations
    private var eventHandlerRef: EventHandlerRef?
    private var eventHandlerStatus = OSStatus(noErr)
    private var activeRegistrations: [(id: UInt32, reference: EventHotKeyRef)] = []
    private var activeModifiers: [UInt32]?
    private var activeIDs: Set<UInt32> = []
    private var pendingCleanup: [EventHotKeyRef] = []

    init(operations: Operations = .live) {
      self.operations = operations
      let result = operations.installHandler(
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
          let registrar = Unmanaged<EscapeHotKeyRegistrar>.fromOpaque(userData)
            .takeUnretainedValue()
          return MainActor.assumeIsolated {
            registrar.handleHotKeyID(hotKeyID)
          }
        },
        Unmanaged.passUnretained(self).toOpaque()
      )
      eventHandlerStatus = result.0 == noErr && result.1 == nil
        ? OSStatus(eventInternalErr)
        : result.0
      eventHandlerRef = result.1
    }

    func register() throws {
      try register(modifier: nil)
    }

    func register(modifier: DictationModifierKey?) throws {
      let modifiers = Self.modifiers(for: modifier)
      if let activeModifiers {
        guard activeModifiers == modifiers else {
          throw GlobalHoldShortcut.RegistrationError.activeSession
        }
        return
      }
      guard eventHandlerStatus == noErr else {
        throw GlobalHoldShortcut.RegistrationError.system(eventHandlerStatus)
      }
      if !pendingCleanup.isEmpty {
        let references = pendingCleanup
        pendingCleanup.removeAll()
        let cleanupStatus = cleanUp(references)
        guard pendingCleanup.isEmpty else {
          throw GlobalHoldShortcut.RegistrationError.system(cleanupStatus!)
        }
      }

      var staged: [(id: UInt32, reference: EventHotKeyRef)] = []
      let ids = try modifiers.map { _ in try Self.allocateHotKeyID() }
      for (modifierMask, id) in zip(modifiers, ids) {
        let result = operations.registerHotKey(
          Self.escapeKeyCode,
          modifierMask,
          EventHotKeyID(signature: Self.signature, id: id),
          0
        )
        if let reference = result.1 {
          staged.append((id, reference))
        }
        guard result.0 == noErr, result.1 != nil else {
          activeIDs.removeAll()
          let cleanupStatus = cleanUp(staged.map(\.reference))
          throw GlobalHoldShortcut.RegistrationError.system(
            cleanupStatus ?? (result.0 == noErr ? OSStatus(eventInternalErr) : result.0)
          )
        }
      }
      activeRegistrations = staged
      activeModifiers = modifiers
      activeIDs = Set(staged.map(\.id))
    }

    func unregister() throws {
      activeIDs.removeAll()
      let references = activeRegistrations.map(\.reference) + pendingCleanup
      activeRegistrations.removeAll()
      activeModifiers = nil
      pendingCleanup.removeAll()
      if let status = cleanUp(references) {
        throw GlobalHoldShortcut.RegistrationError.system(status)
      }
    }

    func handleHotKeyID(_ hotKeyID: EventHotKeyID) -> OSStatus {
      guard
        hotKeyID.signature == Self.signature,
        activeIDs.contains(hotKeyID.id)
      else { return OSStatus(eventNotHandledErr) }
      eventHandler?()
      return noErr
    }

    private static func modifiers(for modifier: DictationModifierKey?) -> [UInt32] {
      switch modifier {
      case .leftOption, .rightOption:
        [0, UInt32(optionKey)]
      case .leftControl, .rightControl:
        [0, UInt32(controlKey)]
      case .leftCommand, .rightCommand:
        [0, UInt32(cmdKey)]
      case .function, nil:
        [0]
      }
    }

    private static func allocateHotKeyID() throws -> UInt32 {
      guard nextHotKeyID < UInt32.max else {
        throw GlobalHoldShortcut.RegistrationError.system(OSStatus(eventInternalErr))
      }
      defer { nextHotKeyID += 1 }
      return nextHotKeyID
    }

    @discardableResult
    private func cleanUp(_ references: [EventHotKeyRef]) -> OSStatus? {
      var firstFailure: OSStatus?
      for reference in references {
        let status = operations.unregisterHotKey(reference)
        if status != noErr {
          firstFailure = firstFailure ?? status
          pendingCleanup.append(reference)
        }
      }
      return firstFailure
    }

    isolated deinit {
      activeIDs.removeAll()
      for registration in activeRegistrations.map(\.reference) + pendingCleanup {
        _ = operations.unregisterHotKey(registration)
      }
      if let eventHandlerRef {
        _ = operations.removeHandler(eventHandlerRef)
      }
    }
  }
#endif
