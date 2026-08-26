import Foundation
import Testing
import FleckCore

@testable import FleckApp

@Test func updateDisplayIsStablePrefixPlusTail() {
  #expect(DictationTextUpdate(
    generation: 4,
    stableText: "First. ",
    provisionalTail: "Second"
  ).displayText == "First. Second")
}

@Test func resultKeepsBaselineSeparateFromRawRecovery() {
  let result = DictationProcessingResult(
    rawTranscript: "send the report",
    dictionaryBaseline: nil,
    cleanedTranscript: nil,
    insertedText: "send the report",
    cleanupOutcome: .usedRaw,
    measurements: .empty
  )
  #expect(result.dictionaryBaseline == nil)
  #expect(result.insertedText == result.rawTranscript)
}

@Test func productionProcessingBudgetUsesBoundedInsertionAndCleanupWindows() {
  #expect(DictationProcessingBudget.production.insertion == .seconds(4))
  #expect(DictationProcessingBudget.production.cleanup == .milliseconds(3_500))
}

@Test func deadlineUsesStopAsCleanupOriginAndCapsAtInsertion() {
  let stop = ContinuousClock().now
  let insertion = stop.advanced(by: .seconds(5))
  let deadline = DictationDeadline(
    stopInstant: stop,
    insertionDeadline: insertion,
    cleanupBudget: .seconds(3)
  )
  #expect(deadline.stopInstant == stop)
  #expect(deadline.insertionDeadline == insertion)
  #expect(deadline.cleanupDeadline == stop.advanced(by: .seconds(3)))

  let capped = DictationDeadline(
    stopInstant: stop,
    insertionDeadline: stop.advanced(by: .seconds(1)),
    cleanupBudget: .seconds(3)
  )
  #expect(capped.cleanupDeadline == capped.insertionDeadline)
}

@Test func runtimeMeasurementsStartEmpty() {
  let measurements = DictationRuntimeMeasurements.empty
  #expect(measurements.firstMeaningfulPartialMilliseconds == nil)
  #expect(measurements.finalASRMilliseconds == nil)
  #expect(measurements.cleanupMilliseconds == nil)
  #expect(measurements.stopToInsertionMilliseconds == nil)
  #expect(measurements.cancellationMilliseconds == nil)
}

@Test func recognitionContextFiltersDeduplicatesAndBoundsTerms() {
  let terms = [" ", "Fleck", "Fleck"] + (0..<105).map { "term\($0)" }
  let context = DictationRecognitionContext(
    locale: Locale(identifier: "en-US"),
    contextualStrings: terms
  )

  #expect(context.locale.identifier == "en-US")
  #expect(context.contextualStrings.count == 100)
  #expect(context.contextualStrings.first == "Fleck")
  #expect(context.contextualStrings.last == "term98")
  #expect(context.contextualStrings.contains("term99") == false)
  #expect(DictationRecognitionContext.englishDefault.locale.identifier == "en-US")
}

@Test func processingValuesExposeEquatableSendableShapes() {
  func acceptsEquatable<T: Equatable>(_ value: T) {
    _ = value
  }

  func acceptsSendable<T: Sendable>(_ value: T) {
    _ = value
  }

  let context = DictationRecognitionContext.englishDefault
  let configuration = DictationProcessingConfiguration(
    captureID: UUID(),
    mode: .focused,
    recognitionContext: context
  )

  #expect(DictationPreparationIntent.likelyCapture != .immediateCapture)
  #expect(DictationRuntimeSignal.lowPowerMode(true) != .lowPowerMode(false))
  acceptsEquatable(DictationPreparationIntent.likelyCapture)
  acceptsEquatable(DictationRuntimeSignal.memoryWarning)
  acceptsEquatable(context)
  acceptsEquatable(configuration)
  acceptsEquatable(DictationProcessingBudget.production)
  acceptsEquatable(DictationTextUpdate(
    generation: 1,
    stableText: "",
    provisionalTail: ""
  ))
  acceptsEquatable(DictationRuntimeMeasurements.empty)
  acceptsSendable(DictationPreparationIntent.immediateCapture)
  acceptsSendable(DictationRuntimeSignal.didWake)
  acceptsSendable(context)
  acceptsSendable(configuration)
  acceptsSendable(DictationProcessingBudget.production)
  acceptsSendable(DictationTextUpdate(
    generation: 1,
    stableText: "",
    provisionalTail: ""
  ))
  acceptsSendable(DictationRuntimeMeasurements.empty)
}

@Test func protocolSeamsCompileWithoutAudioChunkOperations() {
  @MainActor
  final class ProcessingProbe: DictationProcessing {
    func prepare(for intent: DictationPreparationIntent) async {
      _ = intent
    }

    func begin(
      configuration: DictationProcessingConfiguration,
      level: @escaping @MainActor @Sendable (Float) -> Void
    ) async throws -> any DictationProcessingSession {
      _ = (configuration, level)
      return SessionProbe()
    }

    func handle(_ signal: DictationRuntimeSignal) async {
      _ = signal
    }
  }

  @MainActor
  final class SessionProbe: DictationProcessingSession {
    let updates = AsyncThrowingStream<DictationTextUpdate, Error> { continuation in
      continuation.finish()
    }

    func finish() async throws -> DictationProcessingResult {
      DictationProcessingResult(
        rawTranscript: "",
        dictionaryBaseline: "",
        cleanedTranscript: nil,
        insertedText: "",
        cleanupOutcome: .usedRaw,
        measurements: .empty
      )
    }

    func cancel() async {}
  }

  @MainActor
  final class SpeechSourceProbe: StreamingSpeechSource {
    func start(
      provisional: @escaping @MainActor @Sendable (String) -> Void,
      level: @escaping @MainActor @Sendable (Float) -> Void
    ) async throws {
      _ = (provisional, level)
    }

    func finish() async throws -> String? { nil }
    func cancel() async {}
    func releaseResources() async {}
  }

  struct DictionaryResolverProbe: TranscriptDictionaryResolving {
    func resolve(_ rawTranscript: String) async throws -> PersonalDictionaryResolution {
      PersonalDictionaryResolution(
        baseline: rawTranscript,
        protectedForms: [],
        replacements: 0
      )
    }
  }

  let processing: any DictationProcessing = ProcessingProbe()
  let session: any DictationProcessingSession = SessionProbe()
  let source: any StreamingSpeechSource = SpeechSourceProbe()
  let resolver: any TranscriptDictionaryResolving = DictionaryResolverProbe()
  _ = (processing, session, source, resolver)
}
