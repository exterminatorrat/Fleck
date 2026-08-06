import OSLog

internal enum FleckPerformanceSignposts {
  static let subsystem = "com.harryjin.fleck"
  static let category = "performance"
  static let logger = Logger(subsystem: subsystem, category: category)
  static let signposter = OSSignposter(
    subsystem: subsystem,
    category: category
  )

  static let launch = StaticString("launch")
  static let snapshotLoad = StaticString("snapshot-load")
  static let searchQuery = StaticString("search-query")
  static let noteSwitch = StaticString("note-switch")
  static let snapshotSave = StaticString("snapshot-save")
  static let panelPresentation = StaticString("panel-presentation")
  static let activationPreferenceSynchronization = StaticString("activation-preference-sync")

  @MainActor
  static func measureActivationPreferenceSynchronization(_ work: () -> Void) {
    let start = DispatchTime.now().uptimeNanoseconds
    let intervalState = signposter.beginInterval(activationPreferenceSynchronization)
    work()
    let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - start
    signposter.endInterval(activationPreferenceSynchronization, intervalState)
    let elapsedMilliseconds = Double(elapsedNanoseconds) / 1_000_000
    logger.info(
      "activation_preference_sync elapsed_ms=\(elapsedMilliseconds, privacy: .public)"
    )
  }
}

@MainActor
enum FleckPanelPresentationRootState: String, Equatable {
  case loading
  case notes
  case blocked
  case resume
}

@MainActor
struct FleckPanelPresentationMeasurementSample: Equatable {
  let elapsedMilliseconds: Double
  let rootState: FleckPanelPresentationRootState
}

@MainActor
final class FleckPanelPresentationMeasurement {
  static let shared = FleckPanelPresentationMeasurement()

  private let now: () -> UInt64
  private let completionSink: (FleckPanelPresentationMeasurementSample) -> Void
  private var beganAt: UInt64?
  private var intervalState: OSSignpostIntervalState?

  init(
    now: @escaping () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
    completionSink: @escaping (FleckPanelPresentationMeasurementSample) -> Void = { _ in }
  ) {
    self.now = now
    self.completionSink = completionSink
  }

  @discardableResult
  func begin() -> Bool {
    guard beganAt == nil, intervalState == nil else { return false }
    beganAt = now()
    intervalState = FleckPerformanceSignposts.signposter.beginInterval(
      FleckPerformanceSignposts.panelPresentation
    )
    return true
  }

  @discardableResult
  func end(rootState: FleckPanelPresentationRootState) -> Bool {
    guard let beganAt, let intervalState else { return false }
    let endedAt = now()
    let elapsedNanoseconds = endedAt >= beganAt ? endedAt - beganAt : 0
    self.beganAt = nil
    self.intervalState = nil
    FleckPerformanceSignposts.signposter.endInterval(
      FleckPerformanceSignposts.panelPresentation,
      intervalState
    )
    let sample = FleckPanelPresentationMeasurementSample(
      elapsedMilliseconds: Double(elapsedNanoseconds) / 1_000_000,
      rootState: rootState
    )
    FleckPerformanceSignposts.logger.info(
      "panel_presentation elapsed_ms=\(sample.elapsedMilliseconds, privacy: .public) root_state=\(sample.rootState.rawValue, privacy: .public)"
    )
    completionSink(sample)
    return true
  }

  @discardableResult
  func cancel() -> Bool {
    guard let intervalState else { return false }
    beganAt = nil
    self.intervalState = nil
    FleckPerformanceSignposts.signposter.endInterval(
      FleckPerformanceSignposts.panelPresentation,
      intervalState
    )
    return true
  }
}
