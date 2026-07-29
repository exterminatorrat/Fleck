#if os(macOS)
  import CoreGraphics
  import FleckCore

  enum ModifierKeyTransition: Equatable, Sendable {
    case pressed(DictationModifierKey)
    case released(DictationModifierKey)
  }

  enum ModifierMonitorState: Equatable, Hashable, Sendable {
    case stopped
    case unauthorized
    case running
    case failed
  }

  @MainActor
  protocol ModifierKeyMonitoring: AnyObject {
    var transitionHandler: ((ModifierKeyTransition) -> Void)? { get set }
    var stateHandler: ((ModifierMonitorState) -> Void)? { get set }
    var accessGranted: Bool { get }
    func start() throws
    func stop()
    func requestAccess() -> Bool
  }

  @MainActor
  final class ModifierKeyEventTap: ModifierKeyMonitoring {
    enum MonitorError: Error {
      case unauthorized
      case tapCreationFailed
    }

    struct KeyState {
      let modifier: DictationModifierKey
      private var isDown = false
      private var isSynchronized = true

      init(modifier: DictationModifierKey) {
        self.modifier = modifier
      }

      mutating func synchronize(isDown: Bool) {
        self.isDown = isDown
        isSynchronized = !isDown
      }

      mutating func receiveFlagChange() -> ModifierKeyTransition? {
        isDown.toggle()
        if !isSynchronized {
          if !isDown { isSynchronized = true }
          return nil
        }
        return isDown ? .pressed(modifier) : .released(modifier)
      }
    }

    @MainActor
    final class DisabledTapRecovery {
      private var didAttemptReenable = false

      func recover(
        stateHandler: (ModifierMonitorState) -> Void,
        synchronize: () -> Void,
        reenable: () -> Bool
      ) -> Bool {
        guard !didAttemptReenable else { return false }
        didAttemptReenable = true
        stateHandler(.stopped)
        synchronize()
        guard reenable() else { return false }
        didAttemptReenable = false
        stateHandler(.running)
        return true
      }

      func reset() {
        didAttemptReenable = false
      }
    }

    var transitionHandler: ((ModifierKeyTransition) -> Void)?
    var stateHandler: ((ModifierMonitorState) -> Void)?

    var accessGranted: Bool {
      CGPreflightListenEventAccess()
    }

    private static let eventMask =
      CGEventMask(1) << CGEventType.flagsChanged.rawValue

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var keyStates = DictationModifierKey.allCases.map(KeyState.init)
    private let disabledTapRecovery = DisabledTapRecovery()

    func start() throws {
      guard tap == nil else { return }
      guard accessGranted else {
        stateHandler?(.unauthorized)
        throw MonitorError.unauthorized
      }
      guard
        let tap = CGEvent.tapCreate(
          tap: .cgSessionEventTap,
          place: .headInsertEventTap,
          options: .listenOnly,
          eventsOfInterest: Self.eventMask,
          callback: Self.callback,
          userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
      else {
        stateHandler?(.failed)
        throw MonitorError.tapCreationFailed
      }
      guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
        CFMachPortInvalidate(tap)
        stateHandler?(.failed)
        throw MonitorError.tapCreationFailed
      }

      self.tap = tap
      runLoopSource = source
      disabledTapRecovery.reset()
      synchronizePhysicalState()
      CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
      CGEvent.tapEnable(tap: tap, enable: true)
      stateHandler?(.running)
    }

    func stop() {
      teardown()
      stateHandler?(.stopped)
    }

    func requestAccess() -> Bool {
      CGRequestListenEventAccess()
    }

    private func synchronizePhysicalState() {
      for index in keyStates.indices {
        let modifier = keyStates[index].modifier
        keyStates[index].synchronize(
          isDown: CGEventSource.keyState(
            .combinedSessionState,
            key: CGKeyCode(Self.virtualKey(for: modifier))
          )
        )
      }
    }

    private func receive(type: CGEventType, keyCode: UInt32?) {
      if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        recoverDisabledTap()
        return
      }
      guard type == .flagsChanged else { return }
      guard
        let keyCode,
        let modifier = Self.modifier(forVirtualKey: keyCode),
        let index = keyStates.firstIndex(where: { $0.modifier == modifier }),
        let transition = keyStates[index].receiveFlagChange()
      else { return }
      transitionHandler?(transition)
    }

    private func recoverDisabledTap() {
      guard let tap else {
        fail()
        return
      }
      guard disabledTapRecovery.recover(
        stateHandler: { [weak self] state in
          self?.stateHandler?(state)
        },
        synchronize: { [weak self] in
          self?.synchronizePhysicalState()
        },
        reenable: {
          CGEvent.tapEnable(tap: tap, enable: true)
          return CGEvent.tapIsEnabled(tap: tap)
        }
      ) else {
        fail()
        return
      }
    }

    private func fail() {
      teardown()
      stateHandler?(.failed)
    }

    private func teardown() {
      if let runLoopSource {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
      }
      if let tap {
        CFMachPortInvalidate(tap)
      }
      runLoopSource = nil
      tap = nil
      disabledTapRecovery.reset()
    }

    nonisolated static func modifier(
      forVirtualKey keyCode: UInt32
    ) -> DictationModifierKey? {
      switch keyCode {
      case 0x3F: .function
      case 0x37: .leftCommand
      case 0x36: .rightCommand
      case 0x3A: .leftOption
      case 0x3D: .rightOption
      case 0x3B: .leftControl
      case 0x3E: .rightControl
      default: nil
      }
    }

    private static func virtualKey(for modifier: DictationModifierKey) -> UInt32 {
      switch modifier {
      case .function: 0x3F
      case .leftCommand: 0x37
      case .rightCommand: 0x36
      case .leftOption: 0x3A
      case .rightOption: 0x3D
      case .leftControl: 0x3B
      case .rightControl: 0x3E
      }
    }

    private static let callback: CGEventTapCallBack = {
      _, type, event, userInfo in
      guard let userInfo else { return Unmanaged.passUnretained(event) }
      let monitor = Unmanaged<ModifierKeyEventTap>.fromOpaque(userInfo)
        .takeUnretainedValue()
      let keyCode =
        type == .flagsChanged
        ? UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        : nil
      MainActor.assumeIsolated {
        monitor.receive(type: type, keyCode: keyCode)
      }
      return Unmanaged.passUnretained(event)
    }

    isolated deinit {
      transitionHandler = nil
      stateHandler = nil
      teardown()
    }
  }
#endif
