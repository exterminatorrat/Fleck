import Foundation
import Testing
import FleckCore

@testable import FleckApp

@Test func captureFirstStopOriginKeepsTypedInstantAndPhysicalProjection() {
  let instant = ContinuousClock().now

  #expect(DictationStopOrigin.physicalRelease(instant).instant == instant)
  #expect(DictationStopOrigin.physicalRelease(instant).physicalReleaseAt == instant)
  #expect(DictationStopOrigin.handsFreeKeyPress(instant).instant == instant)
  #expect(DictationStopOrigin.handsFreeKeyPress(instant).physicalReleaseAt == nil)
  #expect(DictationStopOrigin.toolbarAction(instant).instant == instant)
  #expect(DictationStopOrigin.toolbarAction(instant).physicalReleaseAt == nil)
}

@Test func captureFirstMeasurementAllowsReleaseBeforeDelayedSourceStart() {
  let press = ContinuousClock().now
  let release = press.advanced(by: .milliseconds(200))
  let processor = release.advanced(by: .milliseconds(20))
  let source = processor.advanced(by: .milliseconds(1))
  let partial = source.advanced(by: .milliseconds(1))

  let measurements = DictationRuntimeMeasurements()
    .recording(.physicalPress, at: press)
    .recording(.physicalRelease, at: release)
    .recording(.processorStarted, at: processor)
    .recording(.sourceStartRequested, at: source)
    .recording(.firstMeaningfulPartial, at: partial)

  #expect(measurements.integrity == .valid)
  #expect(measurements.physicalReleaseAt == release)
  #expect(measurements.sourceStartRequestedAt == source)
}

@Test func captureFirstMeasurementRejectsRealCausalReversal() {
  let press = ContinuousClock().now
  let source = press.advanced(by: .milliseconds(2))
  let processor = source.advanced(by: .milliseconds(1))

  let measurements = DictationRuntimeMeasurements()
    .recording(.physicalPress, at: press)
    .recording(.sourceStartRequested, at: source)
    .recording(.processorStarted, at: processor)

  #expect(measurements.integrity == .nonMonotonicClock)
  #expect(measurements.processorStartedAt == nil)
}

@Test func captureFeedbackReadinessMeasurementPreservesFirstObservation() {
  let start = ContinuousClock().now
  let source = start.advanced(by: .milliseconds(1))
  let firstReady = start.advanced(by: .milliseconds(2))
  let repeatedReady = start.advanced(by: .milliseconds(3))
  let final = start.advanced(by: .milliseconds(4))

  let measurements = DictationRuntimeMeasurements.empty
    .recording(.sourceStartRequested, at: source)
    .recording(.audioReadyObserved, at: firstReady)
    .recording(.audioReadyObserved, at: repeatedReady)
    .recording(.asrFinal, at: final)

  #expect(measurements.integrity == .valid)
  #expect(measurements.audioReadyObservedAt == firstReady)

  let overlaid = DictationRuntimeMeasurements.empty.overlaying(measurements)
  #expect(overlaid.audioReadyObservedAt == firstReady)

  let terminal = measurements.terminal()
    .recording(.audioReadyObserved, at: repeatedReady)
    .overlaying(DictationRuntimeMeasurements(audioReadyObservedAt: repeatedReady))
  #expect(terminal == measurements.terminal())
}

@Test func captureFeedbackReadinessMeasurementRejectsCausalReversal() {
  let start = ContinuousClock().now
  let beforeSource = DictationRuntimeMeasurements.empty
    .recording(.sourceStartRequested, at: start.advanced(by: .milliseconds(2)))
    .recording(.audioReadyObserved, at: start.advanced(by: .milliseconds(1)))
  let afterFinal = DictationRuntimeMeasurements.empty
    .recording(.audioReadyObserved, at: start.advanced(by: .milliseconds(2)))
    .recording(.asrFinal, at: start.advanced(by: .milliseconds(1)))

  #expect(beforeSource.integrity == .nonMonotonicClock)
  #expect(beforeSource.audioReadyObservedAt == nil)
  #expect(afterFinal.integrity == .nonMonotonicClock)
  #expect(afterFinal.asrFinalAt == nil)
}

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

@Test func dictationDiagnosticsProjectionSerializesAllowlistedStagesAndExplicitNulls() throws {
  let origin = ContinuousClock().now
  let measurements = DictationRuntimeMeasurements(
    physicalPressAt: origin,
    coordinatorEventReceivedAt: origin,
    phasePublishedAt: origin,
    firstInputBufferAt: origin.advanced(by: .milliseconds(4))
  )
    .recording(loadDisposition: .cold)
    .recording(outcome: .failed)
    .recording(failure: .missingInput)

  let projection = measurements.diagnostics
  let data = try JSONEncoder().encode(projection)
  let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  let stages = try #require(object["stages"] as? [String: Any])

  #expect(Set(object.keys) == [
    "schemaVersion", "integrity", "outcome", "failure", "loadDisposition", "stages",
  ])
  #expect(Set(stages.keys) == Set(DictationRuntimeMeasurements.Stage.allCases.map(\.rawValue)))
  #expect(object["schemaVersion"] as? Int == 1)
  #expect(object["integrity"] as? String == "valid")
  #expect(object["outcome"] as? String == "failed")
  #expect(object["failure"] as? String == "missing_input")
  #expect(object["loadDisposition"] as? String == "cold")
  #expect(stages.count == DictationRuntimeMeasurements.Stage.allCases.count)
  #expect(stages["physical_press"] as? Double == 0)
  #expect(stages["first_input_buffer"] as? Double == 4)
  #expect(stages["asr_final"] is NSNull)

}

@Test func dictationDiagnosticsRoundTripNormalizesHostileAndMissingStageKeys() throws {
  let payload = Data(#"""
    {
      "schemaVersion": 1,
      "integrity": "valid",
      "outcome": "failed",
      "failure": null,
      "loadDisposition": "warm",
      "stages": {
        "physical_press": 12.5,
        "dictated_secret": 99
      }
    }
    """#.utf8)

  let decoded = try JSONDecoder().decode(
    DictationRuntimeMeasurements.Diagnostics.self,
    from: payload
  )
  let encoded = try JSONEncoder().encode(decoded)
  let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
  let stages = try #require(object["stages"] as? [String: Any])

  #expect(decoded.schemaVersion == 1)
  #expect(decoded.integrity == .valid)
  #expect(decoded.outcome == .failed)
  #expect(decoded.failure == nil)
  #expect(decoded.loadDisposition == .warm)
  #expect(Set(stages.keys) == Set(DictationRuntimeMeasurements.Stage.allCases.map(\.rawValue)))
  #expect(stages["physical_press"] as? Double == 12.5)
  #expect(stages["asr_final"] is NSNull)
  #expect(stages["dictated_secret"] == nil)

  let invalidPayload = Data(
    String(decoding: payload, as: UTF8.self)
      .replacingOccurrences(of: #""integrity": "valid""#, with: #""integrity": "non_monotonic_clock""#)
      .utf8
  )
  let invalid = try JSONDecoder().decode(
    DictationRuntimeMeasurements.Diagnostics.self,
    from: invalidPayload
  )
  #expect(invalid.stages.values.allSatisfy { $0 == nil })
}

@Test func dictationDiagnosticsMetadataAndStagesKeepFirstWriteOverlayAndTerminalFencing() {
  let origin = ContinuousClock().now
  let initial = DictationRuntimeMeasurements.empty
    .recording(.coordinatorEventReceived, at: origin)
    .recording(outcome: .failed)
    .recording(failure: .permissionDenied)
    .recording(loadDisposition: .cold)
  let incoming = DictationRuntimeMeasurements(
    phasePublishedAt: origin.advanced(by: .milliseconds(2)),
    modelReadyAt: origin.advanced(by: .milliseconds(3)),
    outcome: .succeeded,
    failure: .modelLoadFailure,
    loadDisposition: .warm
  )
  let merged = initial.overlaying(incoming)
  let terminal = merged.terminal()
    .recording(.asrFinal, at: origin.advanced(by: .milliseconds(4)))
    .recording(outcome: .cancelled)
    .recording(failure: .bufferLimit)
    .recording(loadDisposition: .warm)

  #expect(merged.phasePublishedAt == origin.advanced(by: .milliseconds(2)))
  #expect(merged.modelReadyAt == origin.advanced(by: .milliseconds(3)))
  #expect(merged.outcome == .failed)
  #expect(merged.failure == .permissionDenied)
  #expect(merged.loadDisposition == .cold)
  #expect(terminal == merged.terminal())

  let invalid = DictationRuntimeMeasurements(
    integrity: .nonMonotonicClock,
    physicalPressAt: origin
  ).diagnostics
  #expect(invalid.stages.values.allSatisfy { $0 == nil })

  let unknownFailure = DictationRuntimeMeasurements.empty.resolving(
    outcome: .failed,
    failure: nil
  )
  #expect(unknownFailure.failure == nil)
}

@Test func processorMeasurementsUseContinuousClockInstantsAndDeriveLegacyDurations() {
  let start = ContinuousClock().now
  let measurements = DictationRuntimeMeasurements(
    processorStartedAt: start,
    sourceStartRequestedAt: start.advanced(by: .milliseconds(1)),
    firstMeaningfulPartialAt: start.advanced(by: .milliseconds(10)),
    stopRequestedAt: start.advanced(by: .milliseconds(20)),
    asrFinalAt: start.advanced(by: .milliseconds(50)),
    dictionaryCompletedAt: start.advanced(by: .milliseconds(60)),
    cleanupDecisionCompletedAt: start.advanced(by: .milliseconds(100)),
    cancellationRequestedAt: start.advanced(by: .milliseconds(110)),
    cancellationDrainedAt: start.advanced(by: .milliseconds(125))
  )

  #expect(measurements.integrity == .valid)
  #expect(measurements.firstMeaningfulPartialMilliseconds == 10)
  #expect(measurements.finalASRMilliseconds == 30)
  #expect(measurements.cleanupMilliseconds == 40)
  #expect(measurements.stopToInsertionMilliseconds == nil)
  #expect(measurements.cancellationMilliseconds == 15)

  let reversed = DictationRuntimeMeasurements(
    stopRequestedAt: start.advanced(by: .seconds(1)),
    asrFinalAt: start
  )
  #expect(reversed.finalASRMilliseconds == nil)
  let invalid = DictationRuntimeMeasurements(
    integrity: .nonMonotonicClock,
    processorStartedAt: start,
    firstMeaningfulPartialAt: start.advanced(by: .milliseconds(1))
  )
  #expect(invalid.firstMeaningfulPartialMilliseconds == nil)
}

@Test func physicalGestureReceiptRejectsLateTimestampAfterTerminalCancellation() {
  let start = ContinuousClock().now
  let accepted = DictationRuntimeMeasurements.empty
    .recording(.routingRequested, at: start)
  let backward = accepted.recording(
    .routingDecision,
    at: start.advanced(by: .milliseconds(-1))
  )
  let equal = accepted.recording(.routingDecision, at: start)
  let repeated = equal.recording(
    .routingDecision,
    at: start.advanced(by: .milliseconds(2))
  )
  let terminal = accepted.terminal()
  let late = terminal.recording(
    .routingDecision,
    at: start.advanced(by: .milliseconds(1))
  )
  let physical = DictationRuntimeMeasurements.empty
    .recording(.physicalPress, at: start)
    .recording(.physicalRelease, at: start.advanced(by: .milliseconds(10)))
  let processor = DictationRuntimeMeasurements(
    processorStartedAt: start.advanced(by: .milliseconds(1)),
    sourceStartRequestedAt: start.advanced(by: .milliseconds(2)),
    firstMeaningfulPartialAt: start.advanced(by: .milliseconds(3)),
    stopRequestedAt: start.advanced(by: .milliseconds(10))
  )
  let overlaid = physical.overlaying(processor)
  let backwards = physical.overlaying(DictationRuntimeMeasurements(
    processorStartedAt: start.advanced(by: .milliseconds(4)),
    sourceStartRequestedAt: start.advanced(by: .milliseconds(3))
  ))
  let firstWrite = overlaid.overlaying(DictationRuntimeMeasurements(
    processorStartedAt: start.advanced(by: .milliseconds(2))
  ))
  let terminalOverlay = physical.terminal().overlaying(processor)
  let propagated = physical.overlaying(DictationRuntimeMeasurements(
    integrity: .nonMonotonicClock,
    processorStartedAt: start.advanced(by: .milliseconds(1))
  ))

  #expect(backward.integrity == .nonMonotonicClock)
  #expect(backward.routingDecisionAt == nil)
  #expect(equal.routingDecisionAt == start)
  #expect(repeated == equal)
  #expect(late == terminal)
  #expect(overlaid.integrity == .valid)
  #expect(overlaid.processorStartedAt == start.advanced(by: .milliseconds(1)))
  #expect(overlaid.physicalReleaseAt == start.advanced(by: .milliseconds(10)))
  #expect(overlaid.stopRequestedAt == start.advanced(by: .milliseconds(10)))
  #expect(backwards.integrity == .nonMonotonicClock)
  #expect(backwards.processorStartedAt == start.advanced(by: .milliseconds(4)))
  #expect(backwards.sourceStartRequestedAt == nil)
  #expect(firstWrite == overlaid)
  #expect(terminalOverlay == physical.terminal())
  #expect(propagated.integrity == .nonMonotonicClock)
  #expect(propagated.processorStartedAt == start.advanced(by: .milliseconds(1)))
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

    func finish(stopOrigin: DictationStopOrigin) async throws -> DictationProcessingResult {
      _ = stopOrigin
      return DictationProcessingResult(
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
