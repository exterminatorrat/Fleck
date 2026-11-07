import Foundation
import FleckAgentProtocol
import FleckCore
import Testing

@testable import FleckAgentBridge

private let requestID = UUID(
  uuidString: "10000000-0000-0000-0000-000000000001"
)!
private let clientProfileID = UUID(
  uuidString: "10000000-0000-0000-0000-000000000002"
)!

@Test func existingSocketConnectsWithoutLaunching() throws {
  var launches = 0
  var written = Data()
  var reads = [try responseFrame(requestID: requestID)]
  let client = AgentIPCClient(
    connect: { _ in 12 },
    launch: { launches += 1 },
    write: { data, _ in written = data },
    read: { _, _ in reads.removeFirst() },
    close: { _ in }
  )

  let response = try client.send(request())

  #expect(response == .sharedNotes(notes: []))
  #expect(launches == 0)
  var buffer = written
  let decoded = try AgentWireFraming.decodeFrame(
    AgentWireRequest.self,
    from: &buffer
  )
  #expect(decoded == request())
}

@Test func missingSocketLaunchesOnceAndWaitsNoMoreThanTenSeconds() {
  var attempts = 0
  var launches = 0
  var now: TimeInterval = 0
  let client = AgentIPCClient(
    readinessTimeout: 10,
    pollInterval: 1,
    connect: { _ in
      attempts += 1
      throw AgentIPCClientError.connectionFailed
    },
    launch: { launches += 1 },
    sleep: { now += $0 },
    now: { now },
    write: { _, _ in },
    read: { _, _ in Data() },
    close: { _ in }
  )

  #expect(throws: AgentIPCClientError.fleckUnavailable) {
    _ = try client.send(request())
  }
  #expect(launches == 1)
  #expect(now == 10)
  #expect(attempts == 11)
}

@Test func missingSocketLaunchesThenConnectsWhenReady() throws {
  var attempts = 0
  var launches = 0
  var reads = [try responseFrame(requestID: requestID)]
  let client = AgentIPCClient(
    connect: { _ in
      attempts += 1
      if attempts == 1 {
        throw AgentIPCClientError.connectionFailed
      }
      return 14
    },
    launch: { launches += 1 },
    sleep: { _ in },
    now: { 0 },
    write: { _, _ in },
    read: { _, _ in reads.removeFirst() },
    close: { _ in }
  )

  _ = try client.send(request())

  #expect(launches == 1)
  #expect(attempts == 2)
}

@Test func partialResponseFramesAreReassembled() throws {
  let frame = try responseFrame(requestID: requestID)
  var reads = [
    Data(frame.prefix(2)),
    Data(frame.dropFirst(2).prefix(7)),
    Data(frame.dropFirst(9)),
  ]
  let client = testClient(read: { _, _ in reads.removeFirst() })

  #expect(try client.send(request()) == .sharedNotes(notes: []))
}

@Test func connectedPeerMustRespondBeforeTheSeparateResponseDeadline() {
  var now: TimeInterval = 0
  let client = AgentIPCClient(
    responseTimeout: 60,
    connect: { _ in 12 },
    launch: {},
    now: { now },
    write: { _, _ in },
    read: { _, _ in
      now = 60
      return Data([0])
    },
    close: { _ in }
  )

  #expect(throws: AgentIPCClientError.responseTimedOut) {
    _ = try client.send(request())
  }
}

@Test func cancellationAfterReaderStartsRejectsResponseAndClosesDescriptor() async throws {
  let frame = try responseFrame(requestID: requestID)
  let gate = AgentIPCClientReadGate()
  let sender = AgentIPCClientSendRunner(readGate: gate, frame: frame)
  let task = Task.detached {
    try await sender.send(request())
  }

  guard gate.waitUntilRead(timeout: 5) else {
    task.cancel()
    gate.releaseFrame()
    _ = await task.result
    Issue.record("The IPC send did not enter its reader before the test timeout")
    return
  }

  task.cancel()
  gate.releaseFrame()
  switch await task.result {
  case .success:
    Issue.record("A cancelled IPC send must not accept a response")
  case .failure(let error):
    #expect(error is CancellationError)
  }
  #expect(gate.closeCount == 1)
}

@Test func partialFramesShareOneOverallResponseDeadline() throws {
  let frame = try responseFrame(requestID: requestID)
  var reads = [
    Data(frame.prefix(2)),
    Data(frame.dropFirst(2).prefix(2)),
  ]
  var now: TimeInterval = 0
  var allowedWaits: [TimeInterval] = []
  let client = AgentIPCClient(
    responseTimeout: 60,
    connect: { _ in 12 },
    launch: {},
    now: { now },
    write: { _, _ in },
    read: { _, remaining in
      allowedWaits.append(remaining)
      now += 40
      return reads.removeFirst()
    },
    close: { _ in }
  )

  #expect(throws: AgentIPCClientError.responseTimedOut) {
    _ = try client.send(request())
  }
  #expect(allowedWaits == [60, 20])
}

@Test func prepareEventSubscriptionUsesLargerBoundedResponseBudget() throws {
  let receipt = AgentEventPendingReceipt(
    subscriptionID: "evt_" + String(repeating: "a", count: 64),
    expiresAt: Date(timeIntervalSince1970: 1_000),
    revision: 1,
    grantRevision: 1
  )
  let frame = try AgentWireFraming.encode(
    AgentWireResponse.success(
      protocolVersion: 2,
      requestID: requestID,
      result: .pendingEventSubscription(receipt: receipt)
    )
  )
  var now: TimeInterval = 0
  var allowedWaits: [TimeInterval] = []
  let client = AgentIPCClient(
    responseTimeout: 60,
    connect: { _ in 12 },
    launch: {},
    now: { now },
    write: { _, _ in },
    read: { _, timeout in
      allowedWaits.append(timeout)
      now = 65
      return frame
    },
    close: { _ in }
  )

  #expect(
    try client.send(prepareEventRequest())
      == .pendingEventSubscription(receipt: receipt)
  )
  #expect(allowedWaits == [120])
}

@Test func prepareEventSubscriptionPreservesStructuredCallerErrors() throws {
  let expected = AgentWorkspaceError(
    code: .permissionRevoked,
    recoveryAction: "Reauthorize the event subscription."
  )
  var reads = [
    try AgentWireFraming.encode(
      AgentWireResponse.failure(
        protocolVersion: 2,
        requestID: requestID,
        error: expected
      )
    )
  ]
  let client = testClient { _, _ in reads.removeFirst() }

  do {
    _ = try client.send(prepareEventRequest())
    Issue.record("Expected the event subscription error")
  } catch let received as AgentWorkspaceError {
    #expect(received == expected)
  }
}

@Test func mismatchedRequestIDAndProtocolNeverExposeAResult() throws {
  let wrongID = UUID(
    uuidString: "10000000-0000-0000-0000-000000000099"
  )!
  var mismatchedID = [try responseFrame(requestID: wrongID)]
  let requestIDClient = testClient { _, _ in mismatchedID.removeFirst() }
  #expect(throws: AgentIPCClientError.responseMismatch) {
    _ = try requestIDClient.send(request())
  }

  var mismatchedVersion = [
    try responseFrame(requestID: requestID, protocolVersion: 1)
  ]
  let versionClient = testClient { _, _ in mismatchedVersion.removeFirst() }
  #expect(throws: AgentIPCClientError.protocolMismatch) {
    _ = try versionClient.send(request())
  }
}

@Test func workspaceFailureRemainsStructured() throws {
  let error = AgentWorkspaceError(
    code: .revisionConflict,
    recoveryAction: "Reread the note."
  )
  var reads = [
    try AgentWireFraming.encode(
      AgentWireResponse.failure(
        protocolVersion: 2,
        requestID: requestID,
        error: error
      )
    )
  ]
  let client = testClient { _, _ in reads.removeFirst() }

  do {
    _ = try client.send(request())
    Issue.record("Expected workspace error")
  } catch let received as AgentWorkspaceError {
    #expect(received == error)
  }
}

@Test func timedOutWriteIsReportedDistinctly() {
  let client = AgentIPCClient(
    connect: { _ in 12 },
    launch: {},
    write: { _, _ in throw AgentIPCClientError.writeTimedOut },
    read: { _, _ in Data() },
    close: { _ in }
  )

  #expect(throws: AgentIPCClientError.writeTimedOut) {
    _ = try client.send(request())
  }
}

@Test func clientComparesResponseVersionWithRequestVersion() throws {
  let request = request(protocolVersion: 2, command: .getCapabilities)
  var reads = [
    try AgentWireFraming.encode(
      AgentWireResponse.success(
        protocolVersion: 1,
        requestID: requestID,
        result: .sharedNotes(notes: [])
      )
    )
  ]
  let client = testClient { _, _ in reads.removeFirst() }

  #expect(throws: AgentIPCClientError.protocolMismatch) {
    _ = try client.send(request)
  }
}

@Test func clientReturnsV2CapabilitySummary() throws {
  let request = request(protocolVersion: 2, command: .getCapabilities)
  let summary = AgentCapabilitySummary(
    grantRevision: 4,
    availableCapabilities: [.listNotes, .readNotes]
  )
  var reads = [
    try AgentWireFraming.encode(
      AgentWireResponse.success(
        protocolVersion: 2,
        requestID: requestID,
        result: .capabilities(summary: summary)
      )
    )
  ]
  let client = testClient { _, _ in reads.removeFirst() }

  #expect(try client.send(request) == .capabilities(summary: summary))
}

@Test func clientRejectsCapabilityResultForV1Request() throws {
  let request = request(protocolVersion: 1, command: .listSharedNotes)
  var reads = [
    try AgentWireFraming.encode(
      AgentWireResponse.success(
        protocolVersion: 1,
        requestID: requestID,
        result: .capabilities(
          summary: AgentCapabilitySummary(
            grantRevision: 4,
            availableCapabilities: [.listNotes]
          )
        )
      )
    )
  ]
  let client = testClient { _, _ in reads.removeFirst() }

  #expect(throws: AgentIPCClientError.invalidFrame) {
    _ = try client.send(request)
  }
}

private func request(
  protocolVersion: Int = AgentWireRequest.currentProtocolVersion,
  command: AgentWorkspaceCommand = .listSharedNotes
) -> AgentWireRequest {
  AgentWireRequest(
    protocolVersion: protocolVersion,
    requestID: requestID,
    profileID: clientProfileID,
    credentialBase64: Data(repeating: 1, count: 32).base64EncodedString(),
    command: command
  )
}

private func prepareEventRequest() -> AgentWireRequest {
  request(
    protocolVersion: 2,
    command: .prepareEventSubscription(
      request: AgentEventSubscriptionRequest(
        event: .noteUpdated,
        scope: .note(noteID: clientProfileID),
        callbackURL: "https://example.test/hook",
        signingSecret:
          "whsec_" + Data(repeating: 0x42, count: 24).base64EncodedString()
      )
    )
  )
}

private func testClient(
  read: @escaping AgentIPCClient.Reader
) -> AgentIPCClient {
  AgentIPCClient(
    connect: { _ in 12 },
    launch: {},
    write: { _, _ in },
    read: read,
    close: { _ in }
  )
}

private actor AgentIPCClientSendRunner {
  private let client: AgentIPCClient

  init(readGate: AgentIPCClientReadGate, frame: Data) {
    client = AgentIPCClient(
      connect: { _ in 12 },
      launch: {},
      write: { _, _ in },
      read: { _, _ in try readGate.read(frame) },
      close: { _ in readGate.recordClose() }
    )
  }

  func send(_ request: AgentWireRequest) throws -> AgentWorkspaceResponse {
    try client.send(request)
  }
}

private final class AgentIPCClientReadGate: @unchecked Sendable {
  private let condition = NSCondition()
  private var readerEntered = false
  private var returnFrame = false
  private var recordedCloseCount = 0

  func read(_ frame: Data) throws -> Data {
    condition.lock()
    readerEntered = true
    condition.broadcast()
    let deadline = Date(timeIntervalSinceNow: 5)
    while !returnFrame {
      guard condition.wait(until: deadline) else {
        condition.unlock()
        throw AgentIPCClientError.responseTimedOut
      }
    }
    condition.unlock()
    return frame
  }

  func waitUntilRead(timeout: TimeInterval) -> Bool {
    condition.lock()
    defer { condition.unlock() }
    let deadline = Date(timeIntervalSinceNow: timeout)
    while !readerEntered {
      guard condition.wait(until: deadline) else { return false }
    }
    return true
  }

  func releaseFrame() {
    condition.lock()
    returnFrame = true
    condition.broadcast()
    condition.unlock()
  }

  func recordClose() {
    condition.lock()
    recordedCloseCount += 1
    condition.unlock()
  }

  var closeCount: Int {
    condition.lock()
    defer { condition.unlock() }
    return recordedCloseCount
  }
}

private func responseFrame(
  requestID: UUID,
  protocolVersion: Int = AgentWireResponse.currentProtocolVersion
) throws -> Data {
  let response = AgentWireResponse.success(
    protocolVersion: protocolVersion,
    requestID: requestID,
    result: .sharedNotes(notes: [])
  )
  let frame = try AgentWireFraming.encode(response)
  guard protocolVersion != AgentWireResponse.currentProtocolVersion else {
    return frame
  }

  let payload = frame.dropFirst(4)
  var object = try #require(
    JSONSerialization.jsonObject(with: payload) as? [String: Any]
  )
  object["protocolVersion"] = protocolVersion
  let modified = try JSONSerialization.data(
    withJSONObject: object,
    options: [.sortedKeys]
  )
  var length = UInt32(modified.count).bigEndian
  var result = withUnsafeBytes(of: &length) { Data($0) }
  result.append(modified)
  return result
}
