@MainActor
final class AppleSpeechStreamingAdapter: StreamingSpeechSource {
  private let engine: any SpeechEngine

  init(engine: any SpeechEngine) {
    self.engine = engine
  }

  func start(
    provisional: @escaping @MainActor @Sendable (String) -> Void,
    level: @escaping @MainActor @Sendable (Float) -> Void
  ) async throws {
    try await engine.start(provisional: provisional, level: level)
  }

  func finish() async throws -> String? {
    try await engine.finish()
  }

  func cancel() async {
    await engine.cancel()
  }

  // Used only for start-failure cleanup. AppleSpeechCapture.finish/cancel
  // already release their AppleSpeechSession before returning.
  func releaseResources() async {
    await engine.releaseResources()
  }
}
