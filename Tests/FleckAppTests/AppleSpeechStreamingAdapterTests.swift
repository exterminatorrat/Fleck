import Foundation
import Testing
import FleckCore

@testable import FleckApp

@Test @MainActor
func adapterForwardsSpeechCallbacksWithoutCreatingAudio() async throws {
  let engine = SpeechEngineProbe()
  let adapter = AppleSpeechStreamingAdapter(engine: engine)
  var provisional = [String]()
  try await adapter.start(
    provisional: { provisional.append($0) },
    level: { _ in }
  )
  engine.emitProvisional("First")
  engine.finalText = "First."
  #expect(try await adapter.finish() == "First.")
  #expect(provisional == ["First"])
  #expect(engine.createdAudioSources == 0)
}

@Test @MainActor
func appleSpeechStreamingSourceForwardsExactStopOrigin() async throws {
  let engine = SpeechEngineProbe()
  let adapter = AppleSpeechStreamingAdapter(engine: engine)
  let instant = ContinuousClock().now
  let origin = DictationStopOrigin.physicalRelease(instant)

  #expect(try await adapter.finish(stopOrigin: origin) == "First")
  #expect(engine.stopOrigins == [origin])
}

@Test @MainActor
func dictationDiagnosticsAdapterForwardsEngineMeasurementsAndDefaultsRemainEmpty() {
  let instant = ContinuousClock().now
  let engine = SpeechEngineProbe()
  engine.runtimeMeasurements = DictationRuntimeMeasurements(
    audioStartRequestedAt: instant,
    firstInputBufferAt: instant.advanced(by: .milliseconds(1))
  )
  let adapter = AppleSpeechStreamingAdapter(engine: engine)

  #expect(adapter.runtimeMeasurements == engine.runtimeMeasurements)

  final class DefaultEngine: SpeechEngine {
    let kind: DictationSpeechEngine = .standard
    func start(
      provisional _: @escaping @MainActor @Sendable (String) -> Void,
      level _: @escaping @MainActor @Sendable (Float) -> Void
    ) async throws {}
    func finish() async throws -> String? { nil }
    func cancel() async {}
    func releaseResources() async {}
  }
  #expect(DefaultEngine().runtimeMeasurements == .empty)
}

@MainActor
final class SpeechEngineProbe: SpeechEngine {
  let kind: DictationSpeechEngine = .standard
  var finalText: String?
  var runtimeMeasurements = DictationRuntimeMeasurements.empty
  private var provisional: (@MainActor @Sendable (String) -> Void)?
  private var level: (@MainActor @Sendable (Float) -> Void)?
  private(set) var startCount = 0
  private(set) var finishCount = 0
  private(set) var cancelCount = 0
  private(set) var releaseResourcesCount = 0
  private(set) var stopOrigins: [DictationStopOrigin] = []
  let createdAudioSources = 0

  init(finalText: String? = "First") {
    self.finalText = finalText
  }

  func start(
    provisional: @escaping @MainActor @Sendable (String) -> Void,
    level: @escaping @MainActor @Sendable (Float) -> Void
  ) async throws {
    startCount += 1
    self.provisional = provisional
    self.level = level
  }

  func finish() async throws -> String? {
    finishCount += 1
    return finalText
  }

  func finish(stopOrigin: DictationStopOrigin) async throws -> String? {
    stopOrigins.append(stopOrigin)
    return try await finish()
  }

  func cancel() async {
    cancelCount += 1
  }

  func releaseResources() async {
    releaseResourcesCount += 1
  }

  func emitProvisional(_ text: String) {
    provisional?(text)
  }

  func emitLevel(_ value: Float) {
    level?(value)
  }
}
