import Foundation

struct DictationDiagnosticObservation: Equatable, Sendable {
  let captureID: UUID
  let revision: UInt64
  let diagnostics: DictationRuntimeMeasurements.Diagnostics
}

final class DictationDiagnosticExporter: @unchecked Sendable {
  enum Status: String, Equatable, Sendable {
    case ready
    case sinkFailure = "sink_failure"
  }

  private let parentDirectory: URL
  private let maximumCaptureCount: Int
  private let reportFailure: @Sendable (Status) -> Void
  private let queue = DispatchQueue(label: "com.fleck.dictation-diagnostic-export")
  private var runDirectory: URL?
  private var ordinals: [UUID: Int] = [:]
  private var revisions: [UUID: UInt64] = [:]
  private var status = Status.ready

  init(
    parentDirectory: URL,
    maximumCaptureCount: Int = 128,
    reportFailure: @escaping @Sendable (Status) -> Void = { _ in }
  ) {
    self.parentDirectory = parentDirectory
    self.maximumCaptureCount = min(max(0, maximumCaptureCount), 128)
    self.reportFailure = reportFailure
  }

  static func configured(
    environment: [String: String],
    reportFailure: @escaping @Sendable (Status) -> Void = { _ in
      FileHandle.standardError.write(Data("fleck_dictation_diagnostics=sink_failure\n".utf8))
    }
  ) -> DictationDiagnosticExporter? {
    guard let path = environment["FLECK_DICTATION_DIAGNOSTICS_DIR"],
      !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return nil }
    return DictationDiagnosticExporter(
      parentDirectory: URL(fileURLWithPath: path),
      reportFailure: reportFailure
    )
  }

  func submit(_ observation: DictationDiagnosticObservation) {
    queue.async { [self] in export(observation) }
  }

  func currentStatus() async -> Status {
    await withCheckedContinuation { continuation in
      queue.async { [self] in continuation.resume(returning: status) }
    }
  }

  private func export(_ observation: DictationDiagnosticObservation) {
    guard status == .ready else { return }
    let ordinal: Int
    if let existing = ordinals[observation.captureID] {
      guard observation.revision > (revisions[observation.captureID] ?? 0) else { return }
      ordinal = existing
    } else {
      guard ordinals.count < maximumCaptureCount else { return }
      ordinal = ordinals.count + 1
      ordinals[observation.captureID] = ordinal
    }

    do {
      let directory = try resolvedRunDirectory()
      let file = directory.appendingPathComponent(
        String(format: "capture-%03d.json", ordinal)
      )
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(observation.diagnostics).write(to: file, options: .atomic)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: file.path
      )
      revisions[observation.captureID] = observation.revision
    } catch {
      status = .sinkFailure
      reportFailure(.sinkFailure)
    }
  }

  private func resolvedRunDirectory() throws -> URL {
    if let runDirectory { return runDirectory }
    try FileManager.default.createDirectory(
      at: parentDirectory,
      withIntermediateDirectories: true
    )
    let created = parentDirectory.appendingPathComponent(
      "run-\(UUID().uuidString.lowercased())",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: created,
      withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700]
    )
    runDirectory = created
    return created
  }
}
