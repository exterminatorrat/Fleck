import Foundation
import Testing
@testable import FleckApp

@Test func dictationDiagnosticExporterDisabledModeDoesNoDiskWork() {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("FleckDiagnosticsDisabled-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let exporter = DictationDiagnosticExporter.configured(
    environment: ["UNRELATED_DIAGNOSTICS_DIR": root.path]
  )

  #expect(exporter == nil)
  #expect(!FileManager.default.fileExists(atPath: root.path))
}

@Test func dictationDiagnosticExporterWritesOnlyExistingContentFreeProjection() async throws {
  let root = diagnosticExporterTestRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let captureID = UUID()
  let start = ContinuousClock().now
  let diagnostics = DictationRuntimeMeasurements(
    processorStartedAt: start,
    firstMeaningfulPartialAt: start.advanced(by: .milliseconds(25)),
    outcome: .succeeded,
    loadDisposition: .warm
  ).diagnostics
  let exporter = try #require(DictationDiagnosticExporter.configured(
    environment: ["FLECK_DICTATION_DIAGNOSTICS_DIR": root.path]
  ))

  exporter.submit(.init(captureID: captureID, revision: 1, diagnostics: diagnostics))
  _ = await exporter.currentStatus()

  let runDirectory = try #require(try diagnosticRunDirectories(in: root).only)
  let files = try FileManager.default.contentsOfDirectory(
    at: runDirectory,
    includingPropertiesForKeys: nil
  )
  #expect(files.map(\.lastPathComponent) == ["capture-001.json"])
  let data = try Data(contentsOf: files[0])
  let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  #expect(Set(object.keys) == [
    "schemaVersion", "integrity", "outcome", "failure", "loadDisposition", "stages",
  ])
  let stages = try #require(object["stages"] as? [String: Any])
  #expect(stages["first_meaningful_partial"] as? Double == 25)
  #expect(stages["asr_final"] is NSNull)
  let encoded = String(decoding: data, as: UTF8.self)
  #expect(!encoded.contains(captureID.uuidString))
  #expect(!encoded.localizedCaseInsensitiveContains("transcript"))
  #expect(!encoded.localizedCaseInsensitiveContains("audioData"))
  #expect(!encoded.localizedCaseInsensitiveContains("samples"))
  #expect(!encoded.localizedCaseInsensitiveContains("note"))
  #expect(!encoded.localizedCaseInsensitiveContains("error"))
  #expect(!encoded.localizedCaseInsensitiveContains("vocabulary"))
  #expect(!encoded.localizedCaseInsensitiveContains("destination"))
  let permissions = try #require(
    FileManager.default.attributesOfItem(atPath: runDirectory.path)[.posixPermissions] as? NSNumber
  )
  #expect(permissions.intValue & 0o777 == 0o700)
}

@Test func dictationDiagnosticExporterKeepsSubmissionOrdinalsBoundsAndNewestRevision() async throws {
  let root = diagnosticExporterTestRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let exporter = DictationDiagnosticExporter(
    parentDirectory: root,
    maximumCaptureCount: 2
  )
  let firstID = UUID()
  let secondID = UUID()
  let ignoredID = UUID()
  let start = ContinuousClock().now
  let terminal = DictationRuntimeMeasurements(
    cancellationRequestedAt: start,
    outcome: .cancelled
  ).diagnostics
  let drained = DictationRuntimeMeasurements(
    cancellationRequestedAt: start,
    cancellationDrainedAt: start.advanced(by: .milliseconds(40)),
    outcome: .cancelled
  ).diagnostics
  let succeeded = DictationRuntimeMeasurements(outcome: .succeeded).diagnostics

  exporter.submit(.init(captureID: firstID, revision: 1, diagnostics: terminal))
  exporter.submit(.init(captureID: secondID, revision: 1, diagnostics: succeeded))
  exporter.submit(.init(captureID: firstID, revision: 2, diagnostics: drained))
  exporter.submit(.init(captureID: firstID, revision: 1, diagnostics: terminal))
  exporter.submit(.init(captureID: ignoredID, revision: 1, diagnostics: succeeded))
  _ = await exporter.currentStatus()

  let runDirectory = try #require(try diagnosticRunDirectories(in: root).only)
  let files = try FileManager.default.contentsOfDirectory(
    at: runDirectory,
    includingPropertiesForKeys: nil
  ).sorted { $0.lastPathComponent < $1.lastPathComponent }
  #expect(files.map(\.lastPathComponent) == ["capture-001.json", "capture-002.json"])
  let first = try JSONDecoder().decode(
    DictationRuntimeMeasurements.Diagnostics.self,
    from: Data(contentsOf: files[0])
  )
  let second = try JSONDecoder().decode(
    DictationRuntimeMeasurements.Diagnostics.self,
    from: Data(contentsOf: files[1])
  )
  #expect(first.stages["cancellation_drained"]! == 40)
  #expect(second.outcome == .succeeded)
}

@Test func dictationDiagnosticExporterContainsWriteFailureBehindFixedStatus() async throws {
  let root = diagnosticExporterTestRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  try Data("occupied".utf8).write(to: root)
  let exporter = DictationDiagnosticExporter(parentDirectory: root)

  exporter.submit(.init(
    captureID: UUID(),
    revision: 1,
    diagnostics: DictationRuntimeMeasurements(outcome: .succeeded).diagnostics
  ))

  #expect(await exporter.currentStatus() == .sinkFailure)
}

@Test func configuredDictationDiagnosticExporterReportsSinkFailureOnlyOnce() async throws {
  let root = diagnosticExporterTestRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  try Data("occupied".utf8).write(to: root)
  let reporter = DiagnosticFailureReporterProbe()
  let reportFailure: @Sendable (DictationDiagnosticExporter.Status) -> Void = {
    reporter.record($0)
  }
  let configured = DictationDiagnosticExporter.configured(
    environment: ["FLECK_DICTATION_DIAGNOSTICS_DIR": root.path],
    reportFailure: reportFailure
  )
  let exporter = try #require(configured)
  let diagnostics = DictationRuntimeMeasurements(outcome: .succeeded).diagnostics

  exporter.submit(.init(captureID: UUID(), revision: 1, diagnostics: diagnostics))
  exporter.submit(.init(captureID: UUID(), revision: 1, diagnostics: diagnostics))
  _ = await exporter.currentStatus()

  #expect(reporter.statuses == [.sinkFailure])
}

private func diagnosticExporterTestRoot() -> URL {
  FileManager.default.temporaryDirectory
    .appendingPathComponent("FleckDiagnosticExporter-\(UUID().uuidString)", isDirectory: true)
}

private func diagnosticRunDirectories(in root: URL) throws -> [URL] {
  try FileManager.default.contentsOfDirectory(
    at: root,
    includingPropertiesForKeys: [.isDirectoryKey]
  ).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
}

private extension Array {
  var only: Element? { count == 1 ? self[0] : nil }
}

private final class DiagnosticFailureReporterProbe: @unchecked Sendable {
  private let lock = NSLock()
  private var recordedStatuses: [DictationDiagnosticExporter.Status] = []

  var statuses: [DictationDiagnosticExporter.Status] {
    lock.withLock { recordedStatuses }
  }

  func record(_ status: DictationDiagnosticExporter.Status) {
    lock.withLock { recordedStatuses.append(status) }
  }
}
