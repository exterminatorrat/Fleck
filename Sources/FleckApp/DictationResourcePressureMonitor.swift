#if os(macOS) && CLEAN_DICTATION_ENHANCED_CANDIDATE
import AppKit
import Dispatch
import Foundation

struct DictationMemoryPressureEvent: OptionSet, Sendable {
  let rawValue: UInt

  static let normal = Self(rawValue: DispatchSource.MemoryPressureEvent.normal.rawValue)
  static let warning = Self(rawValue: DispatchSource.MemoryPressureEvent.warning.rawValue)
  static let critical = Self(rawValue: DispatchSource.MemoryPressureEvent.critical.rawValue)
}

@MainActor
struct DictationMemoryPressureSourceAdapter {
  let install: (@escaping @Sendable (DictationMemoryPressureEvent) -> Void) -> Void
  let activate: () -> Void
  let cancel: () -> Void
}

@MainActor
final class DictationResourcePressureMonitor {
  private enum SystemSignal: Sendable {
    case thermal
    case power
    case willSleep
    case didWake
  }

  private let processNotificationCenter: NotificationCenter
  private let workspaceNotificationCenter: NotificationCenter
  private let makeMemoryPressureSource: @MainActor () -> DictationMemoryPressureSourceAdapter
  private let snapshot: @MainActor () -> DictationResourceSnapshot
  private var memoryPressureSource: DictationMemoryPressureSourceAdapter?
  private var processObserverTokens: [NSObjectProtocol] = []
  private var workspaceObserverTokens: [NSObjectProtocol] = []
  private var onForceCold: (@MainActor @Sendable () async -> Void)?
  private var memoryPressure: DictationMemoryPressure = .normal
  private var generation: UInt64 = 0
  private var isStarted = false

  init(
    processNotificationCenter: NotificationCenter = .default,
    workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
    makeMemoryPressureSource: @escaping @MainActor () -> DictationMemoryPressureSourceAdapter = {
      DictationResourcePressureMonitor.makeProductionMemoryPressureSource()
    },
    snapshot: @escaping @MainActor () -> DictationResourceSnapshot = {
      DictationResourceSnapshot.current()
    }
  ) {
    self.processNotificationCenter = processNotificationCenter
    self.workspaceNotificationCenter = workspaceNotificationCenter
    self.makeMemoryPressureSource = makeMemoryPressureSource
    self.snapshot = snapshot
  }

  func start(onForceCold: @escaping @MainActor @Sendable () async -> Void) {
    guard !isStarted else { return }

    generation &+= 1
    let activeGeneration = generation
    isStarted = true
    self.onForceCold = onForceCold

    let source = makeMemoryPressureSource()
    source.install { [weak self] event in
      Task { @MainActor [weak self] in
        self?.handle(memoryPressureEvent: event, generation: activeGeneration)
      }
    }
    memoryPressureSource = source
    source.activate()

    processObserverTokens.append(observe(
      on: processNotificationCenter,
      ProcessInfo.thermalStateDidChangeNotification,
      signal: .thermal,
      generation: activeGeneration
    ))
    processObserverTokens.append(observe(
      on: processNotificationCenter,
      Notification.Name.NSProcessInfoPowerStateDidChange,
      signal: .power,
      generation: activeGeneration
    ))
    workspaceObserverTokens.append(observe(
      on: workspaceNotificationCenter,
      NSWorkspace.willSleepNotification,
      signal: .willSleep,
      generation: activeGeneration
    ))
    workspaceObserverTokens.append(observe(
      on: workspaceNotificationCenter,
      NSWorkspace.didWakeNotification,
      signal: .didWake,
      generation: activeGeneration
    ))
  }

  func stop() {
    guard isStarted else { return }

    isStarted = false
    generation &+= 1
    memoryPressureSource?.cancel()
    memoryPressureSource = nil
    for observerToken in processObserverTokens {
      processNotificationCenter.removeObserver(observerToken)
    }
    processObserverTokens.removeAll()
    for observerToken in workspaceObserverTokens {
      workspaceNotificationCenter.removeObserver(observerToken)
    }
    workspaceObserverTokens.removeAll()
    onForceCold = nil
  }

  func currentSnapshot() -> DictationResourceSnapshot {
    let current = snapshot()
    return DictationResourceSnapshot(
      reclaimableMemoryBytes: current.reclaimableMemoryBytes,
      memoryPressure: memoryPressure,
      thermalPressure: current.thermalPressure,
      lowPowerMode: current.lowPowerMode
    )
  }

  private func observe(
    on notificationCenter: NotificationCenter,
    _ name: Notification.Name,
    signal: SystemSignal,
    generation: UInt64
  ) -> NSObjectProtocol {
    notificationCenter.addObserver(
      forName: name,
      object: nil,
      queue: nil
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.handle(signal: signal, generation: generation)
      }
    }
  }

  private func handle(
    memoryPressureEvent event: DictationMemoryPressureEvent,
    generation: UInt64
  ) {
    guard isActive(generation) else { return }

    if event.contains(.critical) {
      memoryPressure = .critical
    } else if event.contains(.warning) {
      memoryPressure = .warning
    } else {
      memoryPressure = .normal
    }

    if memoryPressure != .normal {
      requestForceCold(generation: generation)
    }
  }

  private func handle(signal: SystemSignal, generation: UInt64) {
    guard isActive(generation) else { return }

    switch signal {
    case .thermal:
      let thermalPressure = currentSnapshot().thermalPressure
      if thermalPressure == .serious || thermalPressure == .critical {
        requestForceCold(generation: generation)
      }
    case .power:
      if currentSnapshot().lowPowerMode {
        requestForceCold(generation: generation)
      }
    case .willSleep, .didWake:
      requestForceCold(generation: generation)
    }
  }

  private func requestForceCold(generation: UInt64) {
    Task { @MainActor [weak self] in
      guard let self,
            isActive(generation),
            let onForceCold
      else {
        return
      }
      await onForceCold()
    }
  }

  private func isActive(_ generation: UInt64) -> Bool {
    isStarted && self.generation == generation
  }

  private static func makeProductionMemoryPressureSource()
    -> DictationMemoryPressureSourceAdapter
  {
    let source = DispatchSource.makeMemoryPressureSource(
      eventMask: [.normal, .warning, .critical],
      queue: .main
    )
    return DictationMemoryPressureSourceAdapter(
      install: { handler in
        source.setEventHandler {
          handler(DictationMemoryPressureEvent(rawValue: source.data.rawValue))
        }
      },
      activate: {
        source.activate()
      },
      cancel: {
        source.cancel()
      }
    )
  }
}
#endif
