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

@MainActor
final class SpeechEngineProbe: SpeechEngine {
  let kind: DictationSpeechEngine = .standard
  var finalText: String?
  private var provisional: (@MainActor @Sendable (String) -> Void)?
  private var level: (@MainActor @Sendable (Float) -> Void)?
  private(set) var startCount = 0
  private(set) var finishCount = 0
  private(set) var cancelCount = 0
  private(set) var releaseResourcesCount = 0
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
