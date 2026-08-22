import Foundation

#if os(macOS) && arch(arm64)
import MLXLLM
import MLXLMCommon
import Tokenizers
#endif

struct GemmaCleanupError: Error, Equatable, Sendable {
    enum Code: String, Codable, Equatable, Sendable {
        case unsupportedPlatform = "unsupported-platform"
        case invalidModelPath = "invalid-model-path"
        case modelConfigMissing = "model-config-missing"
        case modelConfigInvalid = "model-config-invalid"
        case modelLoadFailed = "model-load-failed"
        case invalidJSON = "invalid-json"
        case duplicateJSONKey = "duplicate-json-key"
        case unknownField = "unknown-field"
        case invalidRequest = "invalid-request"
        case lineTooLarge = "line-too-large"
        case inputTooLarge = "input-too-large"
        case maxResponseTokensInvalid = "max-response-tokens-invalid"
        case budgetInvalid = "budget-invalid"
        case deadlineExceeded = "deadline-exceeded"
        case cancelled = "cancelled"
        case generationFailed = "generation-failed"
        case outputTooLarge = "output-too-large"
        case duplicateRequestID = "duplicate-request-id"
        case shutdown = "shutdown"
        case protocolViolation = "protocol-violation"
    }

    let code: Code

    init(_ code: Code) {
        self.code = code
    }
}

extension GemmaCleanupError: CustomStringConvertible {
    var description: String {
        code.rawValue
    }
}

enum GemmaCleanupLimits {
    static let maxLineBytes = 64 * 1024
    static let maxBaselineBytes = 16 * 1024
    static let maxPromptBytes = 32 * 1024
    static let maxRequestIDBytes = 128
    static let maxLexicalInputTokens = 80
    static let absoluteMaxResponseTokens = 128
    static let maxBudgetMilliseconds: UInt64 = 60_000
}

struct GemmaCleanupRequest: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let requestID: String
    let baseline: String
    let plainPrompt: String
    let maxResponseTokens: Int
    let budgetMilliseconds: UInt64

    init(
        schemaVersion: Int = 1,
        requestID: String,
        baseline: String,
        plainPrompt: String,
        maxResponseTokens: Int,
        budgetMilliseconds: UInt64
    ) {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.baseline = baseline
        self.plainPrompt = plainPrompt
        self.maxResponseTokens = maxResponseTokens
        self.budgetMilliseconds = budgetMilliseconds
    }

    func validatedGenerationRequest() throws -> GemmaCleanupGenerationRequest {
        guard schemaVersion == 1, Self.isValidRequestID(requestID) else {
            throw GemmaCleanupError(.invalidRequest)
        }
        guard !baseline.isEmpty, !plainPrompt.isEmpty else {
            throw GemmaCleanupError(.invalidRequest)
        }
        guard Data(baseline.utf8).count <= GemmaCleanupLimits.maxBaselineBytes,
            Data(plainPrompt.utf8).count <= GemmaCleanupLimits.maxPromptBytes
        else {
            throw GemmaCleanupError(.inputTooLarge)
        }

        let baselineLexicalCount = Self.lexicalTokenCount(baseline)
        guard baselineLexicalCount <= GemmaCleanupLimits.maxLexicalInputTokens else {
            throw GemmaCleanupError(.invalidRequest)
        }
        guard maxResponseTokens > 0 else {
            throw GemmaCleanupError(.maxResponseTokensInvalid)
        }
        guard budgetMilliseconds <= GemmaCleanupLimits.maxBudgetMilliseconds else {
            throw GemmaCleanupError(.budgetInvalid)
        }

        let responseCap = min(
            maxResponseTokens,
            baselineLexicalCount + 32,
            GemmaCleanupLimits.absoluteMaxResponseTokens
        )
        guard responseCap > 0 else {
            throw GemmaCleanupError(.maxResponseTokensInvalid)
        }

        let deadline = ContinuousClock().now.advanced(
            by: .milliseconds(Int64(budgetMilliseconds)))
        return GemmaCleanupGenerationRequest(
            requestID: requestID,
            baseline: baseline,
            plainPrompt: plainPrompt,
            inputLexicalTokenCount: baselineLexicalCount,
            maxResponseTokens: responseCap,
            deadline: deadline
        )
    }

    static func isValidRequestID(_ value: String) -> Bool {
        guard !value.isEmpty, Data(value.utf8).count <= GemmaCleanupLimits.maxRequestIDBytes else {
            return false
        }
        return value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 48...57, 65...90, 97...122, 45, 46, 95:
                true
            default:
                false
            }
        }
    }

    private static func lexicalTokenCount(_ value: String) -> Int {
        value.split(whereSeparator: { $0.isWhitespace }).count
    }
}

struct GemmaCleanupGenerationRequest: Equatable, Sendable {
    let requestID: String
    let baseline: String
    let plainPrompt: String
    let inputLexicalTokenCount: Int
    let maxResponseTokens: Int
    let deadline: ContinuousClock.Instant
}

final class GemmaCleanupCancellation: @unchecked Sendable {
    private enum Reason: Equatable {
        case caller
        case deadline
    }

    private let lock = NSLock()
    private var reason: Reason?

    var isCancellationRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return reason != nil
    }

    var isCallerCancellationRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return reason == .caller
    }

    var isDeadlineExceeded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return reason == .deadline
    }

    func requestCancellation() {
        lock.lock()
        if reason == nil {
            reason = .caller
        }
        lock.unlock()
    }

    func requestDeadlineCancellation() {
        lock.lock()
        if reason == nil {
            reason = .deadline
        }
        lock.unlock()
    }

    func check() throws {
        lock.lock()
        let reason: Reason?
        if self.reason == .deadline {
            reason = Reason.deadline
        } else if self.reason == .caller {
            reason = Reason.caller
        } else {
            reason = nil
        }
        lock.unlock()

        switch reason {
        case .deadline:
            throw GemmaCleanupError(.deadlineExceeded)
        case .caller:
            throw GemmaCleanupError(.cancelled)
        case nil:
            if Task.isCancelled {
                throw GemmaCleanupError(.cancelled)
            }
        }
    }
}

protocol GemmaCleanupEngine: Sendable {
    func generate(
        _ request: GemmaCleanupGenerationRequest,
        cancellation: GemmaCleanupCancellation
    ) async throws -> String

    func shutdown() async
}

extension GemmaCleanupEngine {
    func shutdown() async {}
}

struct GemmaCleanupRuntimeHooks: Sendable {
    let registrationCheckpoint: (@Sendable () -> Void)?
    let cancellationDrainStarted: (@Sendable () -> Void)?
    let shutdownDrainStarted: (@Sendable () -> Void)?
    let deadlineWaiter: @Sendable (ContinuousClock.Instant) async -> Bool

    init(
        registrationCheckpoint: (@Sendable () -> Void)? = nil,
        cancellationDrainStarted: (@Sendable () -> Void)? = nil,
        shutdownDrainStarted: (@Sendable () -> Void)? = nil,
        deadlineWaiter: @escaping @Sendable (ContinuousClock.Instant) async -> Bool =
            GemmaCleanupRuntimeHooks.defaultDeadlineWaiter
    ) {
        self.registrationCheckpoint = registrationCheckpoint
        self.cancellationDrainStarted = cancellationDrainStarted
        self.shutdownDrainStarted = shutdownDrainStarted
        self.deadlineWaiter = deadlineWaiter
    }

    private static func defaultDeadlineWaiter(
        until deadline: ContinuousClock.Instant
    ) async -> Bool {
        do {
            try await ContinuousClock().sleep(until: deadline)
            return true
        } catch {
            return false
        }
    }
}

struct GemmaCancellationAcknowledgement: Equatable, Sendable {
    let accepted: Bool
    let cooperative: Bool
    let processTerminationMayBeRequired: Bool
}

struct GemmaCleanupEvent: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Equatable, Sendable {
        case ready
        case started
        case completed
        case failed
        case cancelled
        case cancelAcknowledged = "cancel-acknowledged"
        case shutdownAcknowledged = "shutdown-acknowledged"

        var isTerminal: Bool {
            switch self {
            case .ready, .started:
                false
            case .completed, .failed, .cancelled, .cancelAcknowledged, .shutdownAcknowledged:
                true
            }
        }
    }

    let schemaVersion: Int
    let kind: Kind
    let requestID: String?
    let targetRequestID: String?
    let rawText: String?
    let errorCode: String?
    let cooperative: Bool?
    let processTerminationMayBeRequired: Bool?

    init(
        schemaVersion: Int = 1,
        kind: Kind,
        requestID: String? = nil,
        targetRequestID: String? = nil,
        rawText: String? = nil,
        errorCode: String? = nil,
        cooperative: Bool? = nil,
        processTerminationMayBeRequired: Bool? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.requestID = requestID
        self.targetRequestID = targetRequestID
        self.rawText = rawText
        self.errorCode = errorCode
        self.cooperative = cooperative
        self.processTerminationMayBeRequired = processTerminationMayBeRequired
    }

    var isTerminal: Bool {
        kind.isTerminal
    }

    static func ready() -> Self {
        Self(kind: .ready)
    }

    static func started(requestID: String) -> Self {
        Self(kind: .started, requestID: requestID)
    }

    static func completed(requestID: String, rawText: String) -> Self {
        Self(kind: .completed, requestID: requestID, rawText: rawText)
    }

    static func failed(
        requestID: String?, errorCode: GemmaCleanupError.Code
    ) -> Self {
        Self(kind: .failed, requestID: requestID, errorCode: errorCode.rawValue)
    }

    static func cancelled(
        requestID: String,
        processTerminationMayBeRequired: Bool = false
    ) -> Self {
        Self(
            kind: .cancelled,
            requestID: requestID,
            errorCode: GemmaCleanupError.Code.cancelled.rawValue,
            cooperative: true,
            processTerminationMayBeRequired: processTerminationMayBeRequired
        )
    }

    static func cancelAcknowledged(
        requestID: String,
        targetRequestID: String,
        accepted: Bool,
        processTerminationMayBeRequired: Bool
    ) -> Self {
        Self(
            kind: .cancelAcknowledged,
            requestID: requestID,
            targetRequestID: targetRequestID,
            cooperative: accepted,
            processTerminationMayBeRequired: processTerminationMayBeRequired
        )
    }

    static func shutdownAcknowledged(
        requestID: String,
        processTerminationMayBeRequired: Bool
    ) -> Self {
        Self(
            kind: .shutdownAcknowledged,
            requestID: requestID,
            cooperative: true,
            processTerminationMayBeRequired: processTerminationMayBeRequired
        )
    }
}

enum GemmaSupervisorRequest: Sendable {
    case cleanup(GemmaCleanupRequest)
    case cancel(requestID: String, targetRequestID: String)
    case shutdown(requestID: String)
}

private struct GemmaWireRequest: Decodable {
    let schemaVersion: Int
    let operation: String
    let requestID: String?
    let targetRequestID: String?
    let baseline: String?
    let plainPrompt: String?
    let maxResponseTokens: Int?
    let budgetMilliseconds: UInt64?
}

private enum JSONDuplicateKeyScannerError: Error {
    case invalid
    case duplicate
}

private struct JSONDuplicateKeyScanner {
    private let bytes: [UInt8]
    private var index = 0

    init(data: Data) {
        self.bytes = Array(data)
    }

    mutating func validate() throws {
        skipWhitespace()
        try readValue()
        skipWhitespace()
        guard index == bytes.count else {
            throw JSONDuplicateKeyScannerError.invalid
        }
    }

    private mutating func readValue() throws {
        guard let byte = current else {
            throw JSONDuplicateKeyScannerError.invalid
        }
        switch byte {
        case 0x7B:
            try readObject()
        case 0x5B:
            try readArray()
        case 0x22:
            _ = try readString()
        case 0x74:
            try readLiteral(Array("true".utf8))
        case 0x66:
            try readLiteral(Array("false".utf8))
        case 0x6E:
            try readLiteral(Array("null".utf8))
        case 0x2D, 0x30...0x39:
            readNumber()
        default:
            throw JSONDuplicateKeyScannerError.invalid
        }
    }

    private mutating func readObject() throws {
        try consume(0x7B)
        skipWhitespace()
        var keys = Set<String>()
        if consumeIfPresent(0x7D) {
            return
        }

        while true {
            skipWhitespace()
            guard current == 0x22 else {
                throw JSONDuplicateKeyScannerError.invalid
            }
            let key = try readString()
            guard keys.insert(key).inserted else {
                throw JSONDuplicateKeyScannerError.duplicate
            }
            skipWhitespace()
            try consume(0x3A)
            skipWhitespace()
            try readValue()
            skipWhitespace()
            if consumeIfPresent(0x7D) {
                return
            }
            try consume(0x2C)
        }
    }

    private mutating func readArray() throws {
        try consume(0x5B)
        skipWhitespace()
        if consumeIfPresent(0x5D) {
            return
        }

        while true {
            skipWhitespace()
            try readValue()
            skipWhitespace()
            if consumeIfPresent(0x5D) {
                return
            }
            try consume(0x2C)
        }
    }

    private mutating func readString() throws -> String {
        let start = index
        try consume(0x22)
        while let byte = current {
            switch byte {
            case 0x22:
                index += 1
                let raw = Data(bytes[start..<index])
                guard let value = try? JSONSerialization.jsonObject(
                    with: raw,
                    options: [.fragmentsAllowed]
                ) as? String else {
                    throw JSONDuplicateKeyScannerError.invalid
                }
                return value
            case 0x5C:
                index += 1
                guard current != nil else {
                    throw JSONDuplicateKeyScannerError.invalid
                }
                index += 1
            case 0x00...0x1F:
                throw JSONDuplicateKeyScannerError.invalid
            default:
                index += 1
            }
        }
        throw JSONDuplicateKeyScannerError.invalid
    }

    private mutating func readLiteral(_ literal: [UInt8]) throws {
        guard bytes[index...].starts(with: literal) else {
            throw JSONDuplicateKeyScannerError.invalid
        }
        index += literal.count
    }

    private mutating func readNumber() {
        if current == 0x2D {
            index += 1
        }
        while let byte = current, (0x30...0x39).contains(byte) {
            index += 1
        }
        if current == 0x2E {
            index += 1
            while let byte = current, (0x30...0x39).contains(byte) {
                index += 1
            }
        }
        if current == 0x65 || current == 0x45 {
            index += 1
            if current == 0x2B || current == 0x2D {
                index += 1
            }
            while let byte = current, (0x30...0x39).contains(byte) {
                index += 1
            }
        }
    }

    private mutating func consume(_ expected: UInt8) throws {
        guard consumeIfPresent(expected) else {
            throw JSONDuplicateKeyScannerError.invalid
        }
    }

    @discardableResult
    private mutating func consumeIfPresent(_ expected: UInt8) -> Bool {
        guard current == expected else {
            return false
        }
        index += 1
        return true
    }

    private mutating func skipWhitespace() {
        while let byte = current, byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
            index += 1
        }
    }

    private var current: UInt8? {
        guard index < bytes.count else {
            return nil
        }
        return bytes[index]
    }
}

enum GemmaCleanupProtocol {
    static func decodeRequestLine(_ line: String) throws -> GemmaSupervisorRequest {
        try decodeRequestData(Data(line.utf8))
    }

    static func decodeRequestData(_ data: Data) throws -> GemmaSupervisorRequest {
        guard data.count <= GemmaCleanupLimits.maxLineBytes else {
            throw GemmaCleanupError(.lineTooLarge)
        }
        try preflightJSON(data)
        let wire: GemmaWireRequest
        do {
            wire = try JSONDecoder().decode(GemmaWireRequest.self, from: data)
        } catch {
            throw GemmaCleanupError(.invalidJSON)
        }
        guard wire.schemaVersion == 1 else {
            throw GemmaCleanupError(.invalidRequest)
        }

        switch wire.operation {
        case "cleanup":
            try requireKeys(
                data,
                allowed: [
                    "schemaVersion", "operation", "requestID", "baseline", "plainPrompt",
                    "maxResponseTokens", "budgetMilliseconds",
                ]
            )
            guard let requestID = wire.requestID,
                let baseline = wire.baseline,
                let plainPrompt = wire.plainPrompt,
                let maxResponseTokens = wire.maxResponseTokens,
                let budgetMilliseconds = wire.budgetMilliseconds,
                GemmaCleanupRequest.isValidRequestID(requestID)
            else {
                throw GemmaCleanupError(.invalidRequest)
            }
            return .cleanup(
                GemmaCleanupRequest(
                    schemaVersion: wire.schemaVersion,
                    requestID: requestID,
                    baseline: baseline,
                    plainPrompt: plainPrompt,
                    maxResponseTokens: maxResponseTokens,
                    budgetMilliseconds: budgetMilliseconds
                )
            )
        case "cancel":
            try requireKeys(
                data,
                allowed: ["schemaVersion", "operation", "requestID", "targetRequestID"]
            )
            guard let requestID = wire.requestID,
                let targetRequestID = wire.targetRequestID,
                GemmaCleanupRequest.isValidRequestID(requestID),
                GemmaCleanupRequest.isValidRequestID(targetRequestID)
            else {
                throw GemmaCleanupError(.invalidRequest)
            }
            return .cancel(requestID: requestID, targetRequestID: targetRequestID)
        case "shutdown":
            try requireKeys(data, allowed: ["schemaVersion", "operation", "requestID"])
            guard let requestID = wire.requestID,
                GemmaCleanupRequest.isValidRequestID(requestID)
            else {
                throw GemmaCleanupError(.invalidRequest)
            }
            return .shutdown(requestID: requestID)
        default:
            throw GemmaCleanupError(.invalidRequest)
        }
    }

    static func encodeEventLine(_ event: GemmaCleanupEvent) throws -> String {
        let data = try JSONEncoder().encode(event)
        let line = String(decoding: data, as: UTF8.self) + "\n"
        guard Data(line.utf8).count <= GemmaCleanupLimits.maxLineBytes else {
            throw GemmaCleanupError(.lineTooLarge)
        }
        return line
    }

    static func decodeEventLine(_ line: String) throws -> GemmaCleanupEvent {
        let data = Data(line.utf8)
        guard data.count <= GemmaCleanupLimits.maxLineBytes else {
            throw GemmaCleanupError(.lineTooLarge)
        }
        try preflightJSON(data)
        try requireKeys(
            data,
            allowed: [
                "schemaVersion", "kind", "requestID", "targetRequestID", "rawText", "errorCode",
                "cooperative", "processTerminationMayBeRequired",
            ]
        )
        do {
            return try JSONDecoder().decode(GemmaCleanupEvent.self, from: data)
        } catch {
            throw GemmaCleanupError(.invalidJSON)
        }
    }

    private static func preflightJSON(_ data: Data) throws {
        var scanner = JSONDuplicateKeyScanner(data: data)
        do {
            try scanner.validate()
        } catch JSONDuplicateKeyScannerError.duplicate {
            throw GemmaCleanupError(.duplicateJSONKey)
        } catch {
            throw GemmaCleanupError(.invalidJSON)
        }
        guard (try? JSONSerialization.jsonObject(with: data)) != nil else {
            throw GemmaCleanupError(.invalidJSON)
        }
    }

    private static func requireKeys(_ data: Data, allowed: Set<String>) throws {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GemmaCleanupError(.invalidJSON)
        }
        guard Set(object.keys).isSubset(of: allowed) else {
            throw GemmaCleanupError(.unknownField)
        }
    }
}

struct GemmaModelDirectory: Equatable, Sendable {
    let url: URL

    private init(url: URL) {
        self.url = url
    }

    static func validate(path: String) throws -> GemmaModelDirectory {
        #if os(macOS) && arch(arm64)
        guard !path.isEmpty, Data(path.utf8).count <= GemmaCleanupLimits.maxPromptBytes,
            path.hasPrefix("/"), !path.contains("://")
        else {
            throw GemmaCleanupError(.invalidModelPath)
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains(where: { $0 == "." || $0 == ".." }) else {
            throw GemmaCleanupError(.invalidModelPath)
        }

        let url = URL(fileURLWithPath: path, isDirectory: true)
        let standardized = url.standardizedFileURL
        guard url.path == standardized.path,
            standardized.resolvingSymlinksInPath().path == standardized.path
        else {
            throw GemmaCleanupError(.invalidModelPath)
        }
        let values = try standardized.resourceValues(forKeys: [
            .isDirectoryKey, .isSymbolicLinkKey, .isAliasFileKey,
        ])
        guard values.isDirectory == true,
            values.isSymbolicLink != true,
            values.isAliasFile != true
        else {
            throw GemmaCleanupError(.invalidModelPath)
        }

        let configurationURL = standardized.appendingPathComponent("config.json", isDirectory: false)
        guard FileManager.default.fileExists(atPath: configurationURL.path) else {
            throw GemmaCleanupError(.modelConfigMissing)
        }
        let configurationValues = try configurationURL.resourceValues(forKeys: [
            .isRegularFileKey, .isSymbolicLinkKey, .isAliasFileKey,
        ])
        guard configurationValues.isRegularFile == true,
            configurationValues.isSymbolicLink != true,
            configurationValues.isAliasFile != true
        else {
            throw GemmaCleanupError(.modelConfigInvalid)
        }

        guard let data = try? Data(contentsOf: configurationURL), data.count <= 1_024 * 1_024,
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let modelType = object["model_type"] as? String,
            modelType == "gemma3_text" || modelType == "gemma3"
        else {
            throw GemmaCleanupError(.modelConfigInvalid)
        }
        return GemmaModelDirectory(url: standardized)
        #else
        throw GemmaCleanupError(.unsupportedPlatform)
        #endif
    }
}

final class GemmaCleanupRequestHandle: @unchecked Sendable {
    let requestID: String
    private let cancellation: @Sendable () async -> GemmaCancellationAcknowledgement

    init(
        requestID: String,
        cancellation: @escaping @Sendable () async -> GemmaCancellationAcknowledgement
    ) {
        self.requestID = requestID
        self.cancellation = cancellation
    }

    func cancel() async -> GemmaCancellationAcknowledgement {
        await cancellation()
    }
}

private enum GemmaGenerationResult: Sendable {
    case completed(String)
    case failed(GemmaCleanupError.Code)
    case cancelled
}

private final class GemmaStartGate: @unchecked Sendable {
    private let lock = NSLock()
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if released {
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    func release() {
        lock.lock()
        guard !released else {
            lock.unlock()
            return
        }
        released = true
        let pending = waiters
        waiters.removeAll()
        lock.unlock()
        pending.forEach { $0.resume() }
    }
}

private final class GemmaRequestExecution: @unchecked Sendable {
    let cancellation = GemmaCleanupCancellation()
    let startGate = GemmaStartGate()
}

private final class GemmaActiveRequest: @unchecked Sendable {
    let execution: GemmaRequestExecution
    let task: Task<GemmaGenerationResult, Never>
    let completionTask: Task<Void, Never>
    let deadlineTask: Task<Void, Never>

    init(
        execution: GemmaRequestExecution,
        task: Task<GemmaGenerationResult, Never>,
        completionTask: Task<Void, Never>,
        deadlineTask: Task<Void, Never>
    ) {
        self.execution = execution
        self.task = task
        self.completionTask = completionTask
        self.deadlineTask = deadlineTask
    }
}

final class GemmaCleanupRuntime: @unchecked Sendable {
    let events: AsyncStream<GemmaCleanupEvent>

    private let engine: any GemmaCleanupEngine
    private let hooks: GemmaCleanupRuntimeHooks
    private let continuation: AsyncStream<GemmaCleanupEvent>.Continuation
    private let lock = NSLock()
    private var active: [String: GemmaActiveRequest] = [:]
    private var terminalRequestIDs = Set<String>()
    private var shuttingDown = false

    init(
        engine: any GemmaCleanupEngine,
        hooks: GemmaCleanupRuntimeHooks = GemmaCleanupRuntimeHooks()
    ) {
        self.engine = engine
        self.hooks = hooks
        let pair = AsyncStream<GemmaCleanupEvent>.makeStream()
        self.events = pair.stream
        self.continuation = pair.continuation
        pair.continuation.yield(.ready())
    }

    func start(_ request: GemmaCleanupRequest) throws -> GemmaCleanupRequestHandle {
        let generationRequest = try request.validatedGenerationRequest()
        let execution = GemmaRequestExecution()
        let engine = self.engine
        let deadlineWaiter = hooks.deadlineWaiter

        lock.lock()
        guard !shuttingDown else {
            lock.unlock()
            throw GemmaCleanupError(.shutdown)
        }
        guard active[request.requestID] == nil, !terminalRequestIDs.contains(request.requestID) else {
            lock.unlock()
            throw GemmaCleanupError(.duplicateRequestID)
        }

        let task = Task { [weak self, execution] () -> GemmaGenerationResult in
            await execution.startGate.wait()
            guard let self else { return .failed(.generationFailed) }
            do {
                try self.checkBeforeGeneration(
                    generationRequest,
                    cancellation: execution.cancellation
                )
                let rawText = try await engine.generate(
                    generationRequest,
                    cancellation: execution.cancellation
                )
                try self.checkAfterGeneration(
                    generationRequest,
                    cancellation: execution.cancellation
                )
                let completed = GemmaCleanupEvent.completed(
                    requestID: generationRequest.requestID,
                    rawText: rawText
                )
                guard (try? GemmaCleanupProtocol.encodeEventLine(completed)) != nil else {
                    return .failed(.outputTooLarge)
                }
                return .completed(rawText)
            } catch let error as GemmaCleanupError {
                return error.code == .cancelled ? .cancelled : .failed(error.code)
            } catch is CancellationError {
                return execution.cancellation.isDeadlineExceeded
                    ? .failed(.deadlineExceeded)
                    : .cancelled
            } catch {
                return execution.cancellation.isDeadlineExceeded
                    ? .failed(.deadlineExceeded)
                    : .failed(.generationFailed)
            }
        }
        let completionTask = Task { [weak self, execution, task] in
            let result = await task.value
            guard let self else { return }
            let event: GemmaCleanupEvent
            switch result {
            case .completed(let rawText):
                event = .completed(requestID: generationRequest.requestID, rawText: rawText)
            case .failed(let errorCode):
                event = .failed(requestID: generationRequest.requestID, errorCode: errorCode)
            case .cancelled:
                event = execution.cancellation.isDeadlineExceeded
                    ? .failed(
                        requestID: generationRequest.requestID,
                        errorCode: .deadlineExceeded
                    )
                    : .cancelled(requestID: generationRequest.requestID)
            }
            await self.finish(
                requestID: generationRequest.requestID,
                execution: execution,
                event: event
            )
        }
        let deadlineTask = Task { [execution, task] in
            await execution.startGate.wait()
            guard !Task.isCancelled else { return }
            guard await deadlineWaiter(generationRequest.deadline) else { return }
            guard !Task.isCancelled else { return }
            execution.cancellation.requestDeadlineCancellation()
            task.cancel()
        }
        let activeRequest = GemmaActiveRequest(
            execution: execution,
            task: task,
            completionTask: completionTask,
            deadlineTask: deadlineTask
        )
        active[request.requestID] = activeRequest
        lock.unlock()

        hooks.registrationCheckpoint?()
        continuation.yield(.started(requestID: request.requestID))
        execution.startGate.release()

        return GemmaCleanupRequestHandle(requestID: request.requestID) { [weak self] in
            guard let self else {
                return GemmaCancellationAcknowledgement(
                    accepted: false,
                    cooperative: false,
                    processTerminationMayBeRequired: false
                )
            }
            return await self.cancel(
                requestID: "cancel-\(request.requestID)",
                targetRequestID: request.requestID
            )
        }
    }

    @discardableResult
    func cancel(
        requestID: String,
        targetRequestID: String
    ) async -> GemmaCancellationAcknowledgement {
        guard let snapshot = beginCancellation(targetRequestID: targetRequestID) else {
            emitRejectedCancellation(
                requestID: requestID,
                targetRequestID: targetRequestID
            )
            return GemmaCancellationAcknowledgement(
                accepted: false,
                cooperative: false,
                processTerminationMayBeRequired: false
            )
        }

        snapshot.task.cancel()
        hooks.cancellationDrainStarted?()
        _ = await snapshot.task.value
        await snapshot.completionTask.value
        await snapshot.deadlineTask.value
        guard canAcknowledgeCancellation(targetRequestID: targetRequestID) else {
            return GemmaCancellationAcknowledgement(
                accepted: false,
                cooperative: false,
                processTerminationMayBeRequired: false
            )
        }

        continuation.yield(
            .cancelAcknowledged(
                requestID: requestID,
                targetRequestID: targetRequestID,
                accepted: true,
                processTerminationMayBeRequired: false
            )
        )
        return GemmaCancellationAcknowledgement(
            accepted: true,
            cooperative: true,
            processTerminationMayBeRequired: false
        )
    }

    private struct CancellationSnapshot: @unchecked Sendable {
        let task: Task<GemmaGenerationResult, Never>
        let completionTask: Task<Void, Never>
        let deadlineTask: Task<Void, Never>
    }

    private func beginCancellation(targetRequestID: String) -> CancellationSnapshot? {
        lock.lock()
        guard !shuttingDown,
            let activeRequest = active[targetRequestID]
        else {
            lock.unlock()
            return nil
        }
        activeRequest.execution.cancellation.requestCancellation()
        lock.unlock()
        return CancellationSnapshot(
            task: activeRequest.task,
            completionTask: activeRequest.completionTask,
            deadlineTask: activeRequest.deadlineTask
        )
    }

    private func canAcknowledgeCancellation(targetRequestID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !shuttingDown && terminalRequestIDs.contains(targetRequestID)
    }

    private func emitRejectedCancellation(requestID: String, targetRequestID: String) {
        lock.lock()
        let canEmit = !shuttingDown
        lock.unlock()
        guard canEmit else { return }
        continuation.yield(
            .cancelAcknowledged(
                requestID: requestID,
                targetRequestID: targetRequestID,
                accepted: false,
                processTerminationMayBeRequired: false
            )
        )
    }

    func reportProtocolError(
        _ error: GemmaCleanupError,
        requestID: String? = nil
    ) {
        lock.lock()
        guard !shuttingDown else {
            lock.unlock()
            return
        }
        let safeRequestID: String?
        if let requestID,
            !active.keys.contains(requestID),
            !terminalRequestIDs.contains(requestID),
            GemmaCleanupRequest.isValidRequestID(requestID)
        {
            safeRequestID = requestID
            terminalRequestIDs.insert(requestID)
        } else {
            safeRequestID = nil
        }
        lock.unlock()
        continuation.yield(.failed(requestID: safeRequestID, errorCode: error.code))
    }

    private struct ShutdownSnapshot: @unchecked Sendable {
        let activeRequests: [(String, GemmaActiveRequest)]
        let tasks: [Task<GemmaGenerationResult, Never>]
        let completionTasks: [Task<Void, Never>]
        let deadlineTasks: [Task<Void, Never>]
    }

    func shutdown(requestID: String) async {
        guard let snapshot = beginShutdown() else {
            return
        }

        snapshot.deadlineTasks.forEach { $0.cancel() }
        snapshot.tasks.forEach { $0.cancel() }
        hooks.shutdownDrainStarted?()
        for task in snapshot.tasks {
            _ = await task.value
        }
        for task in snapshot.completionTasks {
            await task.value
        }
        for task in snapshot.deadlineTasks {
            await task.value
        }
        guard snapshot.activeRequests.allSatisfy({ hasTerminalRequestID($0.0) }) else {
            return
        }
        await engine.shutdown()
        continuation.yield(
            .shutdownAcknowledged(
                requestID: requestID,
                processTerminationMayBeRequired: false
            )
        )
        continuation.finish()
    }

    private func beginShutdown() -> ShutdownSnapshot? {
        lock.lock()
        guard !shuttingDown else {
            lock.unlock()
            return nil
        }
        shuttingDown = true
        let activeRequests = active.sorted { $0.key < $1.key }
        for (_, activeRequest) in activeRequests {
            activeRequest.execution.cancellation.requestCancellation()
        }
        let tasks = activeRequests.map { $0.value.task }
        let completionTasks = activeRequests.map { $0.value.completionTask }
        let deadlineTasks = activeRequests.map { $0.value.deadlineTask }
        lock.unlock()
        return ShutdownSnapshot(
            activeRequests: activeRequests,
            tasks: tasks,
            completionTasks: completionTasks,
            deadlineTasks: deadlineTasks
        )
    }

    private func hasTerminalRequestID(_ requestID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return terminalRequestIDs.contains(requestID)
    }

    private func checkBeforeGeneration(
        _ request: GemmaCleanupGenerationRequest,
        cancellation: GemmaCleanupCancellation
    ) throws {
        try cancellation.check()
        guard ContinuousClock().now < request.deadline else {
            throw GemmaCleanupError(.deadlineExceeded)
        }
    }

    private func checkAfterGeneration(
        _ request: GemmaCleanupGenerationRequest,
        cancellation: GemmaCleanupCancellation
    ) throws {
        try cancellation.check()
        guard ContinuousClock().now < request.deadline else {
            throw GemmaCleanupError(.deadlineExceeded)
        }
    }

    private func finish(
        requestID: String,
        execution: GemmaRequestExecution,
        event: GemmaCleanupEvent
    ) async {
        guard let terminal = takeTerminal(
            requestID: requestID,
            execution: execution,
            event: event
        ) else {
            return
        }
        terminal.activeRequest.deadlineTask.cancel()
        await terminal.activeRequest.deadlineTask.value
        continuation.yield(terminal.event)
    }

    private func takeTerminal(
        requestID: String,
        execution: GemmaRequestExecution,
        event: GemmaCleanupEvent
    ) -> (activeRequest: GemmaActiveRequest, event: GemmaCleanupEvent)? {
        lock.lock()
        guard let activeRequest = active[requestID], activeRequest.execution === execution else {
            lock.unlock()
            return nil
        }
        active.removeValue(forKey: requestID)
        let terminalEvent: GemmaCleanupEvent = activeRequest.execution.cancellation.isCallerCancellationRequested
            ? .cancelled(requestID: requestID)
            : event
        terminalRequestIDs.insert(requestID)
        lock.unlock()
        return (activeRequest: activeRequest, event: terminalEvent)
    }
}

#if os(macOS) && arch(arm64)
private struct LocalTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let upstream = try await Tokenizers.AutoTokenizer.from(modelFolder: directory)
        return LocalTokenizerAdapter(upstream)
    }
}

private struct LocalTokenizerAdapter: MLXLMCommon.Tokenizer {
    private let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) {
        self.upstream = upstream
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(
                messages: messages,
                tools: tools,
                additionalContext: additionalContext
            )
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}

actor MLXGemmaCleanupEngine: GemmaCleanupEngine {
    private var container: MLXLMCommon.ModelContainer?

    private init(container: MLXLMCommon.ModelContainer) {
        self.container = container
    }

    static func load(directory: GemmaModelDirectory) async throws -> MLXGemmaCleanupEngine {
        do {
            let container = try await LLMModelFactory.shared.loadContainer(
                from: directory.url,
                using: LocalTokenizerLoader()
            )
            return MLXGemmaCleanupEngine(container: container)
        } catch {
            throw GemmaCleanupError(.modelLoadFailed)
        }
    }

    func generate(
        _ request: GemmaCleanupGenerationRequest,
        cancellation: GemmaCleanupCancellation
    ) async throws -> String {
        try cancellation.check()
        guard ContinuousClock().now < request.deadline else {
            throw GemmaCleanupError(.deadlineExceeded)
        }
        guard let container else {
            throw GemmaCleanupError(.shutdown)
        }

        let parameters = GenerateParameters(
            maxTokens: request.maxResponseTokens,
            temperature: 0.0,
            topP: 1.0,
            topK: 0,
            seed: 0
        )
        let generation = try await container.perform { context in
            let messages: [[String: any Sendable]] = [[
                "role": "user",
                "content": request.plainPrompt,
            ]]
            _ = try context.tokenizer.applyChatTemplate(messages: messages)
            let input = try await context.processor.prepare(
                input: UserInput(prompt: request.plainPrompt)
            )
            let iterator = try TokenIterator(
                input: input,
                model: context.model,
                parameters: parameters
            )
            return generateTokenTask(
                promptTokenCount: input.text.tokens.size,
                modelConfiguration: context.configuration,
                tokenizer: context.tokenizer,
                iterator: iterator
            )
        }

        var tokenIDs: [Int] = []
        do {
            for await item in generation.0 {
                try cancellation.check()
                guard ContinuousClock().now < request.deadline else {
                    throw GemmaCleanupError(.deadlineExceeded)
                }
                if case .token(let token) = item {
                    tokenIDs.append(token)
                }
            }
        } catch {
            generation.1.cancel()
            await generation.1.value
            throw error
        }
        await generation.1.value
        try cancellation.check()
        guard ContinuousClock().now < request.deadline else {
            throw GemmaCleanupError(.deadlineExceeded)
        }
        let rawText = await container.decode(tokenIds: tokenIDs)
        try cancellation.check()
        return rawText
    }

    func shutdown() async {
        container = nil
    }
}
#endif
