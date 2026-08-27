import Foundation
import Testing
@testable import GemmaCleanupHelper

private actor RecordingEngine: GemmaCleanupEngine {
    private(set) var requests: [GemmaCleanupGenerationRequest] = []
    var result = "raw model output"
    var waitForCancellation = false

    func generate(
        _ request: GemmaCleanupGenerationRequest,
        cancellation: GemmaCleanupCancellation
    ) async throws -> String {
        requests.append(request)
        if waitForCancellation {
            while !cancellation.isCancellationRequested {
                await Task.yield()
            }
            try cancellation.check()
        }
        return result
    }

    func recordedRequests() -> [GemmaCleanupGenerationRequest] {
        requests
    }

    func setResult(_ value: String) {
        result = value
    }

    func setWaitForCancellation(_ value: Bool) {
        waitForCancellation = value
    }
}

private actor NonCooperativeEngine: GemmaCleanupEngine {
    private var continuation: CheckedContinuation<String, Never>?
    private var cancellation: GemmaCleanupCancellation?
    private var generationStarted = false
    private var shutdownCalled = false

    func generate(
        _ request: GemmaCleanupGenerationRequest,
        cancellation: GemmaCleanupCancellation
    ) async throws -> String {
        self.cancellation = cancellation
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.generationStarted = true
        }
    }

    func release(with result: String = "released") {
        continuation?.resume(returning: result)
        continuation = nil
    }

    func isGenerationStarted() -> Bool {
        generationStarted
    }

    func isCancellationRequested() -> Bool {
        cancellation?.isCancellationRequested == true
    }

    func isShutdownCalled() -> Bool {
        shutdownCalled
    }

    func shutdown() async {
        shutdownCalled = true
    }
}

private final class AsyncSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var signaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        lock.lock()
        guard !signaled else {
            lock.unlock()
            return
        }
        signaled = true
        let pending = waiters
        waiters.removeAll()
        lock.unlock()
        pending.forEach { $0.resume() }
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if signaled {
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    func value() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return signaled
    }
}

private final class BlockingRegistrationCheckpoint: @unchecked Sendable {
    let entered = AsyncSignal()
    private let release = DispatchSemaphore(value: 0)

    func pause() {
        entered.signal()
        release.wait()
    }

    func releaseCheckpoint() {
        release.signal()
    }
}

private actor ManualDeadlineWaiter {
    private var waiter: CheckedContinuation<Bool, Never>?
    private var waitingContinuation: CheckedContinuation<Void, Never>?
    private var fired = false
    private var cancelled = false

    func wait(until _: ContinuousClock.Instant) async -> Bool {
        await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                if fired {
                    continuation.resume(returning: true)
                } else if cancelled {
                    continuation.resume(returning: false)
                } else {
                    waiter = continuation
                    waitingContinuation?.resume()
                    waitingContinuation = nil
                }
            }
        }, onCancel: {
            Task { await self.cancelWaiter() }
        })
    }

    func waitUntilWaiting() async {
        if waiter != nil || fired || cancelled {
            return
        }
        await withCheckedContinuation { continuation in
            if waiter != nil || fired || cancelled {
                continuation.resume()
            } else {
                waitingContinuation = continuation
            }
        }
    }

    func fire() {
        fired = true
        waiter?.resume(returning: true)
        waiter = nil
        waitingContinuation?.resume()
        waitingContinuation = nil
    }

    func wasCancelled() -> Bool {
        cancelled
    }

    private func cancelWaiter() {
        cancelled = true
        waiter?.resume(returning: false)
        waiter = nil
        waitingContinuation?.resume()
        waitingContinuation = nil
    }
}

private actor CooperativeStalledEngine: GemmaCleanupEngine {
    private let started: AsyncSignal
    private var continuation: CheckedContinuation<String, Error>?

    init(started: AsyncSignal) {
        self.started = started
    }

    func generate(
        _: GemmaCleanupGenerationRequest,
        cancellation: GemmaCleanupCancellation
    ) async throws -> String {
        started.signal()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
            }
        }, onCancel: {
            Task { await self.cancelGeneration() }
        })
    }

    private func cancelGeneration() {
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }
}

private actor EventStore {
    private var events: [GemmaCleanupEvent] = []

    func append(_ event: GemmaCleanupEvent) {
        events.append(event)
    }

    func snapshot() -> [GemmaCleanupEvent] {
        events
    }
}

private actor AcknowledgementStore {
    private var acknowledgement: GemmaCancellationAcknowledgement?

    func store(_ acknowledgement: GemmaCancellationAcknowledgement) {
        self.acknowledgement = acknowledgement
    }

    func value() -> GemmaCancellationAcknowledgement? {
        acknowledgement
    }
}

private actor CompletionStore {
    private var completed = false

    func markCompleted() {
        completed = true
    }

    func value() -> Bool {
        completed
    }
}

private func request(
    _ requestID: String = "request-1",
    baseline: String = "one two",
    plainPrompt: String = "clean one two",
    maxResponseTokens: Int = 4,
    budgetMilliseconds: UInt64 = 1_000
) -> GemmaCleanupRequest {
    GemmaCleanupRequest(
        requestID: requestID,
        baseline: baseline,
        plainPrompt: plainPrompt,
        maxResponseTokens: maxResponseTokens,
        budgetMilliseconds: budgetMilliseconds
    )
}

private func terminalEvents(
    from stream: AsyncStream<GemmaCleanupEvent>,
    requestID: String
) async -> [GemmaCleanupEvent] {
    var events: [GemmaCleanupEvent] = []
    for await event in stream {
        events.append(event)
        if event.requestID == requestID && event.kind.isTerminal {
            break
        }
    }
    return events
}

@Suite("GemmaCleanupHelperTests")
struct GemmaCleanupHelperTests {
    @Test func routeOperationUsesExistingBoundedGenerationRuntime() async throws {
        let line = """
        {"schemaVersion":1,"operation":"route","requestID":"route-1","baseline":"Fleck project update","plainPrompt":"Return one destination identifier.","maxResponseTokens":8,"budgetMilliseconds":1000}
        """
        let decoded = try GemmaCleanupProtocol.decodeRequestLine(line)
        let routeRequest: GemmaCleanupRequest
        switch decoded {
        case .route(let request):
            routeRequest = request
        default:
            Issue.record("route operation did not decode as route generation")
            return
        }

        let engine = RecordingEngine()
        let runtime = GemmaCleanupRuntime(engine: engine)
        let eventsTask = Task { await terminalEvents(from: runtime.events, requestID: "route-1") }

        _ = try runtime.start(routeRequest)
        let events = await eventsTask.value
        let requests = await engine.recordedRequests()

        #expect(requests.count == 1)
        #expect(requests.first?.baseline == "Fleck project update")
        #expect(requests.first?.plainPrompt == "Return one destination identifier.")
        #expect(requests.first?.maxResponseTokens == 8)
        #expect(events.contains { $0.kind == .completed && $0.rawText == "raw model output" })
    }

    @Test func routePreservesStrictFieldAndOperationValidation() {
        let routeWithExtraField = """
        {"schemaVersion":1,"operation":"route","requestID":"route-extra","baseline":"one","plainPrompt":"route one","maxResponseTokens":1,"budgetMilliseconds":1000,"unexpected":true}
        """
        #expect(throws: GemmaCleanupError(.unknownField)) {
            try GemmaCleanupProtocol.decodeRequestLine(routeWithExtraField)
        }

        let duplicateRouteField = """
        {"schemaVersion":1,"operation":"route","requestID":"route-a","requestID":"route-b","baseline":"one","plainPrompt":"route one","maxResponseTokens":1,"budgetMilliseconds":1000}
        """
        #expect(throws: GemmaCleanupError(.duplicateJSONKey)) {
            try GemmaCleanupProtocol.decodeRequestLine(duplicateRouteField)
        }

        let unknownOperation = """
        {"schemaVersion":1,"operation":"classify","requestID":"unknown"}
        """
        #expect(throws: GemmaCleanupError(.invalidRequest)) {
            try GemmaCleanupProtocol.decodeRequestLine(unknownOperation)
        }
    }

    @Test func oneRequestZeroRetriesAndExactTokenCapForwarding() async throws {
        let engine = RecordingEngine()
        let runtime = GemmaCleanupRuntime(engine: engine)
        let eventsTask = Task { await terminalEvents(from: runtime.events, requestID: "request-1") }

        _ = try runtime.start(request(maxResponseTokens: 50))
        let events = await eventsTask.value
        let requests = await engine.recordedRequests()

        #expect(requests.count == 1)
        #expect(requests.first?.maxResponseTokens == 34)
        #expect(events.contains { $0.kind == .completed && $0.rawText == "raw model output" })
    }

    @Test func rejectsLexicalInputOverEightyTokens() {
        let baseline = Array(repeating: "word", count: 81).joined(separator: " ")
        #expect(throws: GemmaCleanupError.self) {
            try request(baseline: baseline).validatedGenerationRequest()
        }
    }

    @Test func acceptsEightyTokenBaselineWithLongFixedPromptAndCapsOutput() async throws {
        let baseline = Array(repeating: "word", count: 80).joined(separator: " ")
        let fixedPrompt = Array(repeating: "instruction", count: 81).joined(separator: " ")
        let engine = RecordingEngine()
        let runtime = GemmaCleanupRuntime(engine: engine)
        let eventsTask = Task { await terminalEvents(from: runtime.events, requestID: "eighty") }

        _ = try runtime.start(
            request(
                "eighty",
                baseline: baseline,
                plainPrompt: fixedPrompt,
                maxResponseTokens: 200
            )
        )
        _ = await eventsTask.value

        let forwarded = await engine.recordedRequests().first
        #expect(forwarded?.inputLexicalTokenCount == 80)
        #expect(forwarded?.maxResponseTokens == min(200, 112, 128))
    }

    @Test func rejectsDuplicateKeysAndOversizedLinesBeforeDecode() {
        let duplicate = """
        {"schemaVersion":1,"operation":"cleanup","requestID":"a","requestID":"b","baseline":"one","plainPrompt":"one","maxResponseTokens":1,"budgetMilliseconds":1000}
        """
        #expect(throws: GemmaCleanupError.self) {
            try GemmaCleanupProtocol.decodeRequestLine(duplicate)
        }

        let oversized = String(repeating: "x", count: GemmaCleanupLimits.maxLineBytes + 1)
        #expect(throws: GemmaCleanupError.self) {
            try GemmaCleanupProtocol.decodeRequestLine(oversized)
        }
    }

    @Test func oversizedRawOutputBecomesBoundedFailure() async throws {
        let engine = RecordingEngine()
        await engine.setResult(String(repeating: "x", count: GemmaCleanupLimits.maxLineBytes))
        let runtime = GemmaCleanupRuntime(engine: engine)
        let eventsTask = Task { await terminalEvents(from: runtime.events, requestID: "large") }

        _ = try runtime.start(request("large"))
        let events = await eventsTask.value

        #expect(
            events.contains {
                $0.kind == .failed
                    && $0.errorCode == GemmaCleanupError.Code.outputTooLarge.rawValue
                    && $0.rawText == nil
            })
    }

    @Test func deadlineBeforeGenerationDoesNotCallEngine() async throws {
        let engine = RecordingEngine()
        let runtime = GemmaCleanupRuntime(engine: engine)
        let eventsTask = Task { await terminalEvents(from: runtime.events, requestID: "deadline") }

        _ = try runtime.start(request("deadline", budgetMilliseconds: 0))
        let events = await eventsTask.value

        #expect((await engine.recordedRequests()).isEmpty)
        #expect(
            events.contains {
                $0.kind == .failed
                    && $0.errorCode == GemmaCleanupError.Code.deadlineExceeded.rawValue
                })
    }

    @Test func independentDeadlineCancelsStalledEngineAsDeadlineFailure() async throws {
        let started = AsyncSignal()
        let engine = CooperativeStalledEngine(started: started)
        let deadlineWaiter = ManualDeadlineWaiter()
        let runtime = GemmaCleanupRuntime(
            engine: engine,
            hooks: GemmaCleanupRuntimeHooks(
                deadlineWaiter: { deadline in
                    await deadlineWaiter.wait(until: deadline)
                }
            )
        )
        let eventsTask = Task {
            await terminalEvents(from: runtime.events, requestID: "deadline-stalled")
        }

        _ = try runtime.start(request("deadline-stalled"))
        await started.wait()
        await deadlineWaiter.waitUntilWaiting()
        await deadlineWaiter.fire()

        let events = await eventsTask.value
        #expect(
            events.contains {
                $0.kind == .failed
                    && $0.requestID == "deadline-stalled"
                    && $0.errorCode == GemmaCleanupError.Code.deadlineExceeded.rawValue
            })
        #expect(!(events.contains { $0.kind == .cancelled }))
        #expect(!(events.contains { $0.kind == .completed }))
        #expect(events.filter { $0.requestID == "deadline-stalled" && $0.kind.isTerminal }.count == 1)
    }

    @Test func nonCooperativeDeadlineWaitsForDrainBeforeTerminalFailure() async throws {
        let engine = NonCooperativeEngine()
        let deadlineWaiter = ManualDeadlineWaiter()
        let runtime = GemmaCleanupRuntime(
            engine: engine,
            hooks: GemmaCleanupRuntimeHooks(
                deadlineWaiter: { deadline in
                    await deadlineWaiter.wait(until: deadline)
                }
            )
        )
        let store = EventStore()
        let eventsTask = Task {
            for await event in runtime.events {
                await store.append(event)
                if event.requestID == "deadline-blocked" && event.kind.isTerminal {
                    break
                }
            }
            return await store.snapshot()
        }

        _ = try runtime.start(request("deadline-blocked"))
        while !(await engine.isGenerationStarted()) {
            await Task.yield()
        }
        await deadlineWaiter.waitUntilWaiting()
        await deadlineWaiter.fire()
        while !(await engine.isCancellationRequested()) {
            await Task.yield()
        }

        let beforeRelease = await store.snapshot()
        #expect(!(beforeRelease.contains { $0.requestID == "deadline-blocked" && $0.kind.isTerminal }))
        #expect(!(beforeRelease.contains { $0.kind == .cancelAcknowledged }))

        await engine.release()
        let afterRelease = await eventsTask.value
        #expect(
            afterRelease.contains {
                $0.requestID == "deadline-blocked"
                    && $0.kind == .failed
                    && $0.errorCode == GemmaCleanupError.Code.deadlineExceeded.rawValue
            })
        #expect(!(afterRelease.contains { $0.kind == .cancelled }))
        #expect(!(afterRelease.contains { $0.kind == .completed }))
    }

    @Test func atomicRegistrationAllowsConcurrentCancellationBeforeStarted() async throws {
        let registration = BlockingRegistrationCheckpoint()
        let drainStarted = AsyncSignal()
        let engine = RecordingEngine()
        let runtime = GemmaCleanupRuntime(
            engine: engine,
            hooks: GemmaCleanupRuntimeHooks(
                registrationCheckpoint: { registration.pause() },
                cancellationDrainStarted: { drainStarted.signal() }
            )
        )
        let store = EventStore()
        let eventsTask = Task {
            for await event in runtime.events {
                await store.append(event)
                if event.kind == .cancelAcknowledged && event.targetRequestID == "atomic-cancel" {
                    break
                }
            }
        }
        let startTask = Task.detached {
            try runtime.start(request("atomic-cancel"))
        }

        await registration.entered.wait()
        let cancellationTask = Task {
            await runtime.cancel(requestID: "cancel-atomic", targetRequestID: "atomic-cancel")
        }
        await drainStarted.wait()

        let beforeRelease = await store.snapshot()
        #expect(!(beforeRelease.contains { $0.kind == .started }))
        #expect(!(beforeRelease.contains { $0.requestID == "atomic-cancel" && $0.kind.isTerminal }))
        #expect(!(beforeRelease.contains { $0.kind == .cancelAcknowledged }))

        registration.releaseCheckpoint()
        _ = try await startTask.value
        let acknowledgement = await cancellationTask.value
        _ = await eventsTask.value

        let afterRelease = await store.snapshot()
        #expect(acknowledgement.accepted)
        #expect(acknowledgement.cooperative)
        #expect(afterRelease.contains { $0.kind == .started && $0.requestID == "atomic-cancel" })
        #expect(afterRelease.filter { $0.requestID == "atomic-cancel" && $0.kind == .cancelled }.count == 1)
        #expect(
            afterRelease.contains {
                $0.kind == .cancelAcknowledged
                    && $0.requestID == "cancel-atomic"
                    && $0.targetRequestID == "atomic-cancel"
            })
    }

    @Test func atomicRegistrationAllowsConcurrentShutdownToDrainAndFinish() async throws {
        let registration = BlockingRegistrationCheckpoint()
        let drainStarted = AsyncSignal()
        let engine = RecordingEngine()
        let runtime = GemmaCleanupRuntime(
            engine: engine,
            hooks: GemmaCleanupRuntimeHooks(
                registrationCheckpoint: { registration.pause() },
                shutdownDrainStarted: { drainStarted.signal() }
            )
        )
        let store = EventStore()
        let streamCompletion = CompletionStore()
        let eventsTask = Task {
            for await event in runtime.events {
                await store.append(event)
            }
            await streamCompletion.markCompleted()
        }
        let startTask = Task.detached {
            try runtime.start(request("atomic-shutdown"))
        }

        await registration.entered.wait()
        let shutdownTask = Task {
            await runtime.shutdown(requestID: "shutdown-atomic")
        }
        await drainStarted.wait()

        let beforeRelease = await store.snapshot()
        #expect(!(await streamCompletion.value()))
        #expect(!(beforeRelease.contains { $0.requestID == "atomic-shutdown" && $0.kind.isTerminal }))
        #expect(!(beforeRelease.contains { $0.kind == .shutdownAcknowledged }))

        registration.releaseCheckpoint()
        _ = try await startTask.value
        await shutdownTask.value
        _ = await eventsTask.value

        let afterRelease = await store.snapshot()
        #expect(await streamCompletion.value())
        #expect(afterRelease.contains { $0.kind == .started && $0.requestID == "atomic-shutdown" })
        #expect(afterRelease.contains { $0.requestID == "atomic-shutdown" && $0.kind == .cancelled })
        #expect(afterRelease.contains { $0.requestID == "shutdown-atomic" && $0.kind == .shutdownAcknowledged })
        #expect(afterRelease.last?.kind == .shutdownAcknowledged)
    }

    @Test func callerCancellationIsCooperativeAndSuppressesLateTerminalOutput() async throws {
        let engine = RecordingEngine()
        await engine.setWaitForCancellation(true)
        let runtime = GemmaCleanupRuntime(engine: engine)
        let stream = runtime.events
        let eventsTask = Task { await terminalEvents(from: stream, requestID: "cancelled") }
        let handle = try runtime.start(request("cancelled"))

        let acknowledgement = await handle.cancel()
        let events = await eventsTask.value

        #expect(acknowledgement.accepted)
        #expect(acknowledgement.cooperative)
        #expect(!acknowledgement.processTerminationMayBeRequired)
        #expect(events.filter { $0.requestID == "cancelled" && $0.kind.isTerminal }.count == 1)
        #expect(events.contains { $0.kind == .cancelled })
        #expect(!(events.contains { $0.kind == .completed }))
    }

    @Test func nonCooperativeCancellationHasNoAckBeforeDrain() async throws {
        let engine = NonCooperativeEngine()
        let drainStarted = AsyncSignal()
        let deadlineWaiter = ManualDeadlineWaiter()
        let runtime = GemmaCleanupRuntime(
            engine: engine,
            hooks: GemmaCleanupRuntimeHooks(
                cancellationDrainStarted: { drainStarted.signal() },
                deadlineWaiter: { deadline in
                    await deadlineWaiter.wait(until: deadline)
                }
            )
        )
        let store = EventStore()
        let eventsTask = Task {
            for await event in runtime.events {
                await store.append(event)
                if event.kind == .cancelAcknowledged && event.targetRequestID == "blocked" {
                    break
                }
            }
        }
        let acknowledgementStore = AcknowledgementStore()

        let handle = try runtime.start(request("blocked"))
        while !(await engine.isGenerationStarted()) {
            await Task.yield()
        }
        await deadlineWaiter.waitUntilWaiting()
        let cancellationTask = Task {
            let acknowledgement = await handle.cancel()
            await acknowledgementStore.store(acknowledgement)
        }
        await drainStarted.wait()

        let beforeRelease = await store.snapshot()
        #expect(await acknowledgementStore.value() == nil)
        #expect(!(beforeRelease.contains { $0.requestID == "blocked" && $0.kind.isTerminal }))
        #expect(!(beforeRelease.contains { $0.kind == .cancelAcknowledged }))

        await engine.release()
        _ = await cancellationTask.value
        _ = await eventsTask.value

        let afterRelease = await store.snapshot()
        let acknowledgement = await acknowledgementStore.value()
        #expect(acknowledgement?.accepted == true)
        #expect(acknowledgement?.cooperative == true)
        #expect(acknowledgement?.processTerminationMayBeRequired == false)
        #expect(await deadlineWaiter.wasCancelled())
        #expect(afterRelease.filter { $0.requestID == "blocked" && $0.kind == .cancelled }.count == 1)
        #expect(
            afterRelease.contains {
                $0.kind == .cancelAcknowledged
                    && $0.requestID == "cancel-blocked"
                    && $0.targetRequestID == "blocked"
            })
    }

    @Test func shutdownAcknowledgesAndPreventsLateTerminalOutput() async throws {
        let engine = RecordingEngine()
        await engine.setWaitForCancellation(true)
        let runtime = GemmaCleanupRuntime(engine: engine)
        let stream = runtime.events
        let eventsTask = Task {
            var events: [GemmaCleanupEvent] = []
            for await event in stream {
                events.append(event)
            }
            return events
        }

        _ = try runtime.start(request("active"))
        await runtime.shutdown(requestID: "shutdown")
        let events = await eventsTask.value

        #expect(events.contains { $0.requestID == "active" && $0.kind == .cancelled })
        #expect(events.contains { $0.requestID == "shutdown" && $0.kind == .shutdownAcknowledged })
        #expect(!(events.contains { $0.kind == .completed }))
        #expect(events.last?.kind == .shutdownAcknowledged)
    }

    @Test func nonCooperativeShutdownWaitsForDrainBeforeAckAndStreamFinish() async throws {
        let engine = NonCooperativeEngine()
        let drainStarted = AsyncSignal()
        let deadlineWaiter = ManualDeadlineWaiter()
        let runtime = GemmaCleanupRuntime(
            engine: engine,
            hooks: GemmaCleanupRuntimeHooks(
                shutdownDrainStarted: { drainStarted.signal() },
                deadlineWaiter: { deadline in
                    await deadlineWaiter.wait(until: deadline)
                }
            )
        )
        let store = EventStore()
        let streamCompletionStore = CompletionStore()
        let eventsTask = Task {
            for await event in runtime.events {
                await store.append(event)
            }
            await streamCompletionStore.markCompleted()
        }
        let completionStore = CompletionStore()

        _ = try runtime.start(request("shutdown-active"))
        while !(await engine.isGenerationStarted()) {
            await Task.yield()
        }
        await deadlineWaiter.waitUntilWaiting()
        let shutdownTask = Task {
            await runtime.shutdown(requestID: "shutdown")
            await completionStore.markCompleted()
        }
        await drainStarted.wait()

        let beforeRelease = await store.snapshot()
        #expect(!(await completionStore.value()))
        #expect(!(await streamCompletionStore.value()))
        #expect(!(await engine.isShutdownCalled()))
        #expect(
            !(beforeRelease.contains {
                $0.requestID == "shutdown-active" && $0.kind.isTerminal
            })
        )
        #expect(!(beforeRelease.contains { $0.kind == .shutdownAcknowledged }))

        await engine.release()
        _ = await shutdownTask.value
        _ = await eventsTask.value

        let afterRelease = await store.snapshot()
        #expect(await completionStore.value())
        #expect(await streamCompletionStore.value())
        #expect(await engine.isShutdownCalled())
        #expect(await deadlineWaiter.wasCancelled())
        #expect(afterRelease.contains { $0.requestID == "shutdown-active" && $0.kind == .cancelled })
        #expect(afterRelease.contains { $0.requestID == "shutdown" && $0.kind == .shutdownAcknowledged })
        #expect(
            afterRelease.first {
                $0.requestID == "shutdown" && $0.kind == .shutdownAcknowledged
            }?.processTerminationMayBeRequired == false
        )
        #expect(afterRelease.last?.kind == .shutdownAcknowledged)
        #expect(!(afterRelease.contains { $0.kind == .completed }))
    }

    @Test func canonicalLocalModelDirectoryGateRejectsRelativeSymlinkAndMissingConfig() throws {
        let root = URL(filePath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let model = root.appendingPathComponent("model")
        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
        try Data("{\"model_type\":\"gemma3_text\"}".utf8).write(
            to: model.appendingPathComponent("config.json"))

        #expect(try GemmaModelDirectory.validate(path: model.path).url.path == model.path)
        #expect(throws: GemmaCleanupError.self) {
            try GemmaModelDirectory.validate(path: "relative/model")
        }

        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: model)
        #expect(throws: GemmaCleanupError.self) {
            try GemmaModelDirectory.validate(path: link.path)
        }

        let missingConfig = root.appendingPathComponent("missing-config")
        try FileManager.default.createDirectory(at: missingConfig, withIntermediateDirectories: true)
        #expect(throws: GemmaCleanupError.self) {
            try GemmaModelDirectory.validate(path: missingConfig.path)
        }
    }

    @Test func eventJSONLPreservesRawTextAndSanitizesErrors() throws {
        let raw = "line one\nline \"two\""
        let line = try GemmaCleanupProtocol.encodeEventLine(
            .completed(requestID: "request-1", rawText: raw)
        )

        #expect(line.hasSuffix("\n"))
        #expect(line.dropLast().contains("\\n"))
        #expect(try GemmaCleanupProtocol.decodeEventLine(line).rawText == raw)

        let errorLine = try GemmaCleanupProtocol.encodeEventLine(
            .failed(requestID: "request-1", errorCode: .generationFailed)
        )
        #expect(!errorLine.contains("model") && !errorLine.contains("line one"))
    }
}
