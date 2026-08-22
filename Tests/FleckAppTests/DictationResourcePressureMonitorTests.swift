#if os(macOS) && CLEAN_DICTATION_ENHANCED_CANDIDATE
import AppKit
import Dispatch
import Foundation
import Testing

@testable import FleckApp

@MainActor
private final class MemoryPressureSourceProbe {
  private(set) var installCount = 0
  private(set) var activateCount = 0
  private(set) var cancelCount = 0
  private var handler: (@Sendable (DictationMemoryPressureEvent) -> Void)?

  func adapter() -> DictationMemoryPressureSourceAdapter {
    DictationMemoryPressureSourceAdapter(
      install: { [weak self] handler in
        self?.installCount += 1
        self?.handler = handler
      },
      activate: { [weak self] in
        self?.activateCount += 1
      },
      cancel: { [weak self] in
        self?.cancelCount += 1
      }
    )
  }

  func emit(_ event: DictationMemoryPressureEvent) {
    handler?(event)
  }
}

@MainActor
private final class SnapshotProbe {
  var value: DictationResourceSnapshot

  init(_ value: DictationResourceSnapshot) {
    self.value = value
  }
}

@MainActor
private final class ForceColdProbe {
  private(set) var callCount = 0
  private(set) var startedCount = 0
  private(set) var completedCount = 0
  var waitsForRelease = false
  private var releaseContinuation: CheckedContinuation<Void, Never>?

  func call() async {
    callCount += 1
    startedCount += 1
    if waitsForRelease {
      await withCheckedContinuation { continuation in
        releaseContinuation = continuation
      }
    }
    completedCount += 1
  }

  func release() {
    releaseContinuation?.resume()
    releaseContinuation = nil
  }
}

@MainActor
private func drainMonitorTasks() async {
  for _ in 0..<3 {
    await Task.yield()
  }
}

@MainActor
private func makeMonitor(
  source: MemoryPressureSourceProbe,
  snapshot: SnapshotProbe,
  processNotificationCenter: NotificationCenter = NotificationCenter(),
  workspaceNotificationCenter: NotificationCenter = NotificationCenter()
) -> DictationResourcePressureMonitor {
  DictationResourcePressureMonitor(
    processNotificationCenter: processNotificationCenter,
    workspaceNotificationCenter: workspaceNotificationCenter,
    makeMemoryPressureSource: { source.adapter() },
    snapshot: { snapshot.value }
  )
}

@Test @MainActor
func currentSnapshotUsesLatestMemoryPressureAndFreshInjectedData() async {
  let source = MemoryPressureSourceProbe()
  let snapshot = SnapshotProbe(
    DictationResourceSnapshot(
      reclaimableMemoryBytes: 1,
      thermalPressure: .nominal,
      lowPowerMode: false
    )
  )
  let monitor = makeMonitor(source: source, snapshot: snapshot)
  monitor.start(onForceCold: {})

  #expect(monitor.currentSnapshot() == DictationResourceSnapshot(
    reclaimableMemoryBytes: 1,
    memoryPressure: .normal,
    thermalPressure: .nominal,
    lowPowerMode: false
  ))

  snapshot.value = DictationResourceSnapshot(
    reclaimableMemoryBytes: 2,
    thermalPressure: .fair,
    lowPowerMode: true
  )
  source.emit(.warning)
  await drainMonitorTasks()

  #expect(monitor.currentSnapshot() == DictationResourceSnapshot(
    reclaimableMemoryBytes: 2,
    memoryPressure: .warning,
    thermalPressure: .fair,
    lowPowerMode: true
  ))

  snapshot.value = DictationResourceSnapshot(
    reclaimableMemoryBytes: 3,
    thermalPressure: .serious,
    lowPowerMode: false
  )
  source.emit([.normal, .warning, .critical])
  await drainMonitorTasks()

  #expect(monitor.currentSnapshot() == DictationResourceSnapshot(
    reclaimableMemoryBytes: 3,
    memoryPressure: .critical,
    thermalPressure: .serious,
    lowPowerMode: false
  ))
}

@Test @MainActor
func warningAndCriticalMemoryPressureRequestForceColdWithCriticalPrecedence() async {
  let source = MemoryPressureSourceProbe()
  let snapshot = SnapshotProbe(DictationResourceSnapshot(reclaimableMemoryBytes: 1))
  let forceCold = ForceColdProbe()
  let monitor = makeMonitor(source: source, snapshot: snapshot)
  monitor.start { await forceCold.call() }

  source.emit(.warning)
  await drainMonitorTasks()
  #expect(forceCold.callCount == 1)

  source.emit([.normal, .warning, .critical])
  await drainMonitorTasks()
  #expect(forceCold.callCount == 2)
  #expect(monitor.currentSnapshot().memoryPressure == .critical)
}

@Test @MainActor
func normalMemoryPressureRestoresStateWithoutForceCold() async {
  let source = MemoryPressureSourceProbe()
  let snapshot = SnapshotProbe(DictationResourceSnapshot(reclaimableMemoryBytes: 1))
  let forceCold = ForceColdProbe()
  let monitor = makeMonitor(source: source, snapshot: snapshot)
  monitor.start { await forceCold.call() }

  source.emit(.critical)
  await drainMonitorTasks()
  source.emit(.normal)
  await drainMonitorTasks()

  #expect(forceCold.callCount == 1)
  #expect(monitor.currentSnapshot().memoryPressure == .normal)
}

@Test @MainActor
func seriousAndCriticalThermalStateRequestForceColdButNominalAndFairDoNot() async {
  let source = MemoryPressureSourceProbe()
  let snapshot = SnapshotProbe(DictationResourceSnapshot(reclaimableMemoryBytes: 1))
  let forceCold = ForceColdProbe()
  let center = NotificationCenter()
  let monitor = makeMonitor(
    source: source,
    snapshot: snapshot,
    processNotificationCenter: center
  )
  monitor.start { await forceCold.call() }

  for thermalPressure in [DictationThermalPressure.nominal, .fair] {
    snapshot.value = DictationResourceSnapshot(
      reclaimableMemoryBytes: 1,
      thermalPressure: thermalPressure
    )
    center.post(name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
    await drainMonitorTasks()
  }
  #expect(forceCold.callCount == 0)

  for thermalPressure in [DictationThermalPressure.serious, .critical] {
    snapshot.value = DictationResourceSnapshot(
      reclaimableMemoryBytes: 1,
      thermalPressure: thermalPressure
    )
    center.post(name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
    await drainMonitorTasks()
  }
  #expect(forceCold.callCount == 2)
}

@Test @MainActor
func lowPowerEnabledRequestsForceColdButDisabledDoesNot() async {
  let source = MemoryPressureSourceProbe()
  let snapshot = SnapshotProbe(DictationResourceSnapshot(reclaimableMemoryBytes: 1))
  let forceCold = ForceColdProbe()
  let center = NotificationCenter()
  let monitor = makeMonitor(
    source: source,
    snapshot: snapshot,
    processNotificationCenter: center
  )
  monitor.start { await forceCold.call() }

  snapshot.value = DictationResourceSnapshot(reclaimableMemoryBytes: 1, lowPowerMode: false)
  center.post(name: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil)
  await drainMonitorTasks()
  #expect(forceCold.callCount == 0)

  snapshot.value = DictationResourceSnapshot(reclaimableMemoryBytes: 1, lowPowerMode: true)
  center.post(name: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil)
  await drainMonitorTasks()
  #expect(forceCold.callCount == 1)
}

@Test @MainActor
func processSignalsAreObservedOnlyOnProcessNotificationCenter() async {
  let source = MemoryPressureSourceProbe()
  let snapshot = SnapshotProbe(DictationResourceSnapshot(reclaimableMemoryBytes: 1))
  let forceCold = ForceColdProbe()
  let processCenter = NotificationCenter()
  let workspaceCenter = NotificationCenter()
  let monitor = makeMonitor(
    source: source,
    snapshot: snapshot,
    processNotificationCenter: processCenter,
    workspaceNotificationCenter: workspaceCenter
  )
  monitor.start { await forceCold.call() }

  #expect(
    Notification.Name.NSProcessInfoPowerStateDidChange.rawValue
      == "NSProcessInfoPowerStateDidChangeNotification"
  )

  snapshot.value = DictationResourceSnapshot(
    reclaimableMemoryBytes: 1,
    thermalPressure: .serious,
    lowPowerMode: true
  )
  workspaceCenter.post(name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
  workspaceCenter.post(name: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil)
  await drainMonitorTasks()
  #expect(forceCold.callCount == 0)

  processCenter.post(name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
  await drainMonitorTasks()
  #expect(forceCold.callCount == 1)

  processCenter.post(name: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil)
  await drainMonitorTasks()
  #expect(forceCold.callCount == 2)
}

@Test @MainActor
func willSleepAndDidWakeEachRequestForceCold() async {
  let source = MemoryPressureSourceProbe()
  let snapshot = SnapshotProbe(DictationResourceSnapshot(reclaimableMemoryBytes: 1))
  let forceCold = ForceColdProbe()
  let workspaceCenter = NotificationCenter()
  let monitor = makeMonitor(
    source: source,
    snapshot: snapshot,
    workspaceNotificationCenter: workspaceCenter
  )
  monitor.start { await forceCold.call() }

  workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
  workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
  await drainMonitorTasks()

  #expect(forceCold.callCount == 2)
}

@Test @MainActor
func workspaceSignalsAreObservedOnlyOnWorkspaceNotificationCenter() async {
  let source = MemoryPressureSourceProbe()
  let snapshot = SnapshotProbe(DictationResourceSnapshot(reclaimableMemoryBytes: 1))
  let forceCold = ForceColdProbe()
  let processCenter = NotificationCenter()
  let workspaceCenter = NotificationCenter()
  let monitor = makeMonitor(
    source: source,
    snapshot: snapshot,
    processNotificationCenter: processCenter,
    workspaceNotificationCenter: workspaceCenter
  )
  monitor.start { await forceCold.call() }

  processCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
  processCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
  await drainMonitorTasks()
  #expect(forceCold.callCount == 0)

  workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
  workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
  await drainMonitorTasks()
  #expect(forceCold.callCount == 2)
}

@Test @MainActor
func startTwiceCreatesOneSourceAndObserverSet() async {
  let source = MemoryPressureSourceProbe()
  let snapshot = SnapshotProbe(DictationResourceSnapshot(reclaimableMemoryBytes: 1))
  let firstForceCold = ForceColdProbe()
  let secondForceCold = ForceColdProbe()
  let workspaceCenter = NotificationCenter()
  let monitor = makeMonitor(
    source: source,
    snapshot: snapshot,
    workspaceNotificationCenter: workspaceCenter
  )
  monitor.start { await firstForceCold.call() }
  monitor.start { await secondForceCold.call() }

  #expect(source.installCount == 1)
  #expect(source.activateCount == 1)

  source.emit(.warning)
  workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
  await drainMonitorTasks()

  #expect(firstForceCold.callCount == 2)
  #expect(secondForceCold.callCount == 0)
}

@Test @MainActor
func stopTwiceCancelsOnceRemovesObserversAndIgnoresPostStopEvents() async {
  let source = MemoryPressureSourceProbe()
  let snapshot = SnapshotProbe(DictationResourceSnapshot(reclaimableMemoryBytes: 1))
  let forceCold = ForceColdProbe()
  let processCenter = NotificationCenter()
  let workspaceCenter = NotificationCenter()
  let monitor = makeMonitor(
    source: source,
    snapshot: snapshot,
    processNotificationCenter: processCenter,
    workspaceNotificationCenter: workspaceCenter
  )
  monitor.start { await forceCold.call() }

  monitor.stop()
  monitor.stop()
  source.emit(.critical)
  processCenter.post(name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
  processCenter.post(name: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil)
  workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
  workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
  await drainMonitorTasks()

  #expect(source.cancelCount == 1)
  #expect(forceCold.callCount == 0)
}

@Test @MainActor
func queuedCallbackBeforeStopIsGenerationFenced() async {
  let source = MemoryPressureSourceProbe()
  let snapshot = SnapshotProbe(DictationResourceSnapshot(reclaimableMemoryBytes: 1))
  let forceCold = ForceColdProbe()
  let monitor = makeMonitor(source: source, snapshot: snapshot)
  monitor.start { await forceCold.call() }

  source.emit(.warning)
  monitor.stop()
  await drainMonitorTasks()

  #expect(forceCold.callCount == 0)
}

@Test @MainActor
func forceColdRequestAwaitsCallbackCompletion() async {
  let source = MemoryPressureSourceProbe()
  let snapshot = SnapshotProbe(DictationResourceSnapshot(reclaimableMemoryBytes: 1))
  let forceCold = ForceColdProbe()
  forceCold.waitsForRelease = true
  let monitor = makeMonitor(source: source, snapshot: snapshot)
  monitor.start { await forceCold.call() }

  source.emit(.warning)
  await drainMonitorTasks()
  #expect(forceCold.startedCount == 1)
  #expect(forceCold.completedCount == 0)

  forceCold.release()
  await drainMonitorTasks()
  #expect(forceCold.completedCount == 1)
}
#endif
