import AppKit
import Darwin
import Foundation
import FleckAgentProtocol
import FleckCore
import Testing

@testable import FleckApp

@Test @MainActor func agentIPCRejectsUnsupportedVersionWithCorrelation() async throws {
  let requestID = UUID()
  let calls = LockedCounter()
  let server = AgentIPCServer(
    endpointURL: temporarySocketURL(),
    execute: { _, _, _ in
      calls.increment()
      return .sharedNotes(notes: [])
    }
  )
  let response = await server.response(
    to: AgentWireRequest(
      protocolVersion: 3,
      requestID: requestID,
      profileID: UUID(),
      credentialBase64: Data(repeating: 0, count: 32).base64EncodedString(),
      command: .listSharedNotes
    )
  )

  #expect(response.requestID == requestID)
  #expect(response.protocolVersion == AgentWireResponse.currentProtocolVersion)
  #expect(response.error?.code == .protocolVersionUnsupported)
  #expect(response.error?.recoveryAction?.contains("update Fleck") == true)
  #expect(calls.value == 0)
}

@Test @MainActor func agentIPCv1RejectsCapabilityDiscoveryBeforeCredentialOrService()
  async
{
  let calls = LockedCounter()
  let server = AgentIPCServer(
    endpointURL: temporarySocketURL(),
    execute: { _, _, _ in
      calls.increment()
      return .sharedNotes(notes: [])
    }
  )
  let response = await server.response(
    to: AgentWireRequest(
      protocolVersion: 1,
      requestID: UUID(),
      profileID: UUID(),
      credentialBase64: "not-base64",
      command: .getCapabilities
    )
  )

  #expect(response.protocolVersion == 1)
  #expect(response.error?.code == .protocolVersionUnsupported)
  #expect(calls.value == 0)
}

@Test(arguments: [1, 2])
@MainActor func agentIPCAcceptsSupportedVersionsAndEchoesThem(_ version: Int)
  async
{
  let requestID = UUID()
  let server = AgentIPCServer(
    endpointURL: temporarySocketURL(),
    execute: { _, _, command in
      switch command {
      case .getCapabilities:
        return .capabilities(
          summary: AgentCapabilitySummary(
            grantRevision: 4,
            availableCapabilities: [.listNotes]
          )
        )
      default:
        return .sharedNotes(notes: [])
      }
    }
  )
  let response = await server.response(
    to: AgentWireRequest(
      protocolVersion: version,
      requestID: requestID,
      profileID: UUID(),
      credentialBase64: Data(repeating: 0, count: 32).base64EncodedString(),
      command: version == 1 ? .listSharedNotes : .getCapabilities
    )
  )

  #expect(response.protocolVersion == version)
  #expect(response.requestID == requestID)
  #expect(response.error == nil)
}

@Test @MainActor func agentIPCCanonicalCredentialGatePrecedesService() async {
  let calls = LockedCounter()
  let server = AgentIPCServer(
    endpointURL: temporarySocketURL(),
    execute: { _, _, _ in
      calls.increment()
      return .sharedNotes(notes: [])
    }
  )

  for credential in [
    "",
    Data(repeating: 1, count: 31).base64EncodedString(),
    Data(repeating: 1, count: 32).base64EncodedString() + "\n",
  ] {
    let response = await server.response(
      to: AgentWireRequest(
        requestID: UUID(),
        profileID: UUID(),
        credentialBase64: credential,
        command: .listSharedNotes
      )
    )
    #expect(response.error?.code == .invalidPayload)
  }
  #expect(calls.value == 0)
}

@Test @MainActor func agentIPCMapsUnexpectedErrorsWithoutLeakingText() async {
  let secret = "credential-and-/private/path"
  let server = AgentIPCServer(
    endpointURL: temporarySocketURL(),
    execute: { _, _, _ in throw SecretFailure(message: secret) }
  )
  let response = await server.response(to: validRequest())
  let encoded = try! JSONEncoder().encode(response)
  let text = String(decoding: encoded, as: UTF8.self)

  #expect(response.error?.code == .internalSaveFailure)
  #expect(!text.contains(secret))
  #expect(!text.contains("/private/path"))
}

@Test @MainActor func agentIPCServiceErrorsRemainStructured() async {
  let expected = AgentWorkspaceError(
    code: .revisionConflict,
    recoveryAction: "Reload the note."
  )
  let server = AgentIPCServer(
    endpointURL: temporarySocketURL(),
    execute: { _, _, _ in throw expected }
  )

  let response = await server.response(to: validRequest())
  #expect(response.error == expected)
}

@Test @MainActor func oversizedSuccessBecomesCorrelatedStructuredFailure() async throws {
  let request = validRequest()
  let page = AgentNotePage(
    noteID: UUID(),
    title: "Large",
    revision: 1,
    body: String(repeating: "x", count: AgentWireFraming.maximumFrameBytes),
    startLine: 1,
    endLine: 1,
    totalLineCount: 1,
    nextLine: nil,
    modifiedAt: Date(timeIntervalSince1970: 0)
  )
  let server = AgentIPCServer(
    endpointURL: temporarySocketURL(),
    execute: { _, _, _ in .note(page: page) }
  )

  let response = await server.response(to: request)
  let frame = try AgentWireFraming.encode(response)
  #expect(response.requestID == request.requestID)
  #expect(response.error?.code == .responseTooLarge)
  #expect(frame.count <= AgentWireFraming.maximumFrameBytes + 4)
}

@Test @MainActor func agentIPCEnforcesLimitsAndRepeatSafeLifecycle() throws {
  let root = temporaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let server = AgentIPCServer(
    endpointURL: root.appendingPathComponent("bridge/fleck.sock"),
    maximumActiveClients: 8,
    idleReadTimeout: 10,
    execute: { _, _, _ in .sharedNotes(notes: []) }
  )

  #expect(server.maximumActiveClients == 8)
  #expect(server.idleReadTimeout == 10)
  server.stop()
  server.stop()
  try server.start()
  try server.start()
  server.stop()
  server.stop()
}

@Test @MainActor func agentIPCPeerLookupMustSucceedForMatchingUser() {
  let matching = AgentIPCServer(
    endpointURL: temporarySocketURL(),
    effectiveUID: 501,
    peerUID: { _ in 501 },
    execute: { _, _, _ in .sharedNotes(notes: []) }
  )
  let mismatched = AgentIPCServer(
    endpointURL: temporarySocketURL(),
    effectiveUID: 501,
    peerUID: { _ in 502 },
    execute: { _, _, _ in .sharedNotes(notes: []) }
  )
  let failed = AgentIPCServer(
    endpointURL: temporarySocketURL(),
    effectiveUID: 501,
    peerUID: { _ in throw SecretFailure(message: "peer failure") },
    execute: { _, _, _ in .sharedNotes(notes: []) }
  )

  #expect(matching.peerIsAllowed(7))
  #expect(!mismatched.peerIsAllowed(7))
  #expect(!failed.peerIsAllowed(7))
}

@Test @MainActor func agentIPCSocketUsesPrivateModesAndOwnedShutdown() throws {
  let root = temporaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let socketURL = root.appendingPathComponent("bridge/fleck.sock")
  let server = AgentIPCServer(
    endpointURL: socketURL,
    execute: { _, _, _ in .sharedNotes(notes: []) }
  )
  try server.start()
  var parent = stat()
  var socketStatus = stat()
  #expect(lstat(socketURL.deletingLastPathComponent().path, &parent) == 0)
  #expect(lstat(socketURL.path, &socketStatus) == 0)
  #expect(parent.st_mode & 0o777 == 0o700)
  #expect(socketStatus.st_mode & 0o777 == 0o600)

  server.stop()
  #expect(lstat(socketURL.path, &socketStatus) == -1)
  #expect(errno == ENOENT)
}

@Test @MainActor func agentIPCShutdownPreservesReplacedLeaf() throws {
  let root = temporaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let socketURL = root.appendingPathComponent("bridge/fleck.sock")
  let server = AgentIPCServer(
    endpointURL: socketURL,
    execute: { _, _, _ in .sharedNotes(notes: []) }
  )
  try server.start()
  #expect(Darwin.unlink(socketURL.path) == 0)
  try Data("replacement".utf8).write(to: socketURL)

  server.stop()
  #expect(try String(contentsOf: socketURL, encoding: .utf8) == "replacement")
}

@Test @MainActor func agentIPCTransactsOverSameUserSocket() async throws {
  let root = temporaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let socketURL = root.appendingPathComponent("bridge/fleck.sock")
  let calls = LockedCounter()
  let server = AgentIPCServer(
    endpointURL: socketURL,
    execute: { _, credential, _ in
      #expect(credential == Data(repeating: 3, count: 32))
      calls.increment()
      return .sharedNotes(notes: [])
    }
  )
  try server.start()
  defer { server.stop() }

  let response = try await Task.detached {
    try transact(validRequest(), at: socketURL)
  }.value
  #expect(response.requestID != UUID())
  #expect(response.result == .sharedNotes(notes: []))
  #expect(calls.value == 1)
}

@Test @MainActor func agentIPCRejectsPeerLookupFailureBeforeAuthorization()
  async throws
{
  let root = temporaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let socketURL = root.appendingPathComponent("bridge/fleck.sock")
  let calls = LockedCounter()
  let server = AgentIPCServer(
    endpointURL: socketURL,
    peerUID: { _ in throw SecretFailure(message: "peer lookup") },
    execute: { _, _, _ in
      calls.increment()
      return .sharedNotes(notes: [])
    }
  )
  try server.start()
  defer { server.stop() }

  let closed = try await Task.detached {
    let descriptor = try connectedSocket(to: socketURL)
    defer { Darwin.close(descriptor) }
    return readAfterDelay(descriptor)
  }.value
  #expect(closed)
  #expect(calls.value == 0)
}

@Test @MainActor func agentIPCRejectsSaturatedAndIdleClients() async throws {
  let root = temporaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let socketURL = root.appendingPathComponent("bridge/fleck.sock")
  let server = AgentIPCServer(
    endpointURL: socketURL,
    maximumActiveClients: 1,
    idleReadTimeout: 0.05,
    execute: { _, _, _ in .sharedNotes(notes: []) }
  )
  try server.start()
  defer { server.stop() }

  let outcomes = try await Task.detached {
    let first = try connectedSocket(to: socketURL)
    defer { Darwin.close(first) }
    usleep(20_000)
    let second = try connectedSocket(to: socketURL)
    defer { Darwin.close(second) }
    let saturatedClosed = readAfterDelay(second, microseconds: 20_000)
    let idleClosed = readAfterDelay(first, microseconds: 80_000)
    return (saturatedClosed, idleClosed)
  }.value
  #expect(outcomes.0)
  #expect(outcomes.1)
}

@Test @MainActor func agentIPCRejectsOversizedPrefixWithoutService() async throws {
  let root = temporaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let socketURL = root.appendingPathComponent("bridge/fleck.sock")
  let calls = LockedCounter()
  let server = AgentIPCServer(
    endpointURL: socketURL,
    execute: { _, _, _ in
      calls.increment()
      return .sharedNotes(notes: [])
    }
  )
  try server.start()
  defer { server.stop() }

  let closed = try await Task.detached {
    let descriptor = try connectedSocket(to: socketURL)
    defer { Darwin.close(descriptor) }
    var length = UInt32(AgentWireFraming.maximumFrameBytes + 1).bigEndian
    let header = withUnsafeBytes(of: &length) { Data($0) }
    _ = header.withUnsafeBytes {
      Darwin.write(descriptor, $0.baseAddress, $0.count)
    }
    return readAfterDelay(descriptor)
  }.value
  #expect(closed)
  #expect(calls.value == 0)
}

@Test @MainActor func disconnectedWriterDoesNotStopLaterRequests() async throws {
  let root = temporaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let socketURL = root.appendingPathComponent("bridge/fleck.sock")
  let server = AgentIPCServer(
    endpointURL: socketURL,
    execute: { _, _, _ in .sharedNotes(notes: []) }
  )
  try server.start()
  defer { server.stop() }

  try await Task.detached {
    let descriptor = try connectedSocket(to: socketURL)
    let frame = try AgentWireFraming.encode(validRequest())
    _ = frame.withUnsafeBytes {
      Darwin.write(descriptor, $0.baseAddress, $0.count)
    }
    Darwin.close(descriptor)
    usleep(30_000)
  }.value

  let response = try await Task.detached {
    try transact(validRequest(), at: socketURL)
  }.value
  #expect(response.result == .sharedNotes(notes: []))
}

@Test @MainActor func nonReadingLargeResponseCannotBlockStopOrRestart()
  async throws
{
  let root = temporaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let socketURL = root.appendingPathComponent("bridge/fleck.sock")
  let calls = LockedCounter()
  let writeStarted = LockedFlag()
  let page = AgentNotePage(
    noteID: UUID(),
    title: "Large",
    revision: 1,
    body: String(repeating: "x", count: 1_000_000),
    startLine: 1,
    endLine: 1,
    totalLineCount: 1,
    nextLine: nil,
    modifiedAt: Date(timeIntervalSince1970: 0)
  )
  let server = AgentIPCServer(
    endpointURL: socketURL,
    peerUID: { descriptor in
      let flags = fcntl(descriptor, F_GETFL)
      _ = fcntl(descriptor, F_SETFL, flags & ~O_NONBLOCK)
      var sendBytes: Int32 = 4_096
      _ = setsockopt(
        descriptor,
        SOL_SOCKET,
        SO_SNDBUF,
        &sendBytes,
        socklen_t(MemoryLayout<Int32>.size)
      )
      return geteuid()
    },
    responseWriteWillBegin: { writeStarted.set() },
    execute: { _, _, _ in
      calls.increment()
      return calls.value == 1
        ? .note(page: page)
        : .sharedNotes(notes: [])
    }
  )
  try server.start()

  let descriptor = try await Task.detached {
    let descriptor = try connectedSocket(
      to: socketURL,
      receiveBufferBytes: 4_096
    )
    try writeRequest(validRequest(), to: descriptor)
    return descriptor
  }.value
  for _ in 0..<100 where calls.value == 0 {
    try await Task.sleep(for: .milliseconds(2))
  }
  for _ in 0..<100 where !writeStarted.value {
    try await Task.sleep(for: .milliseconds(2))
  }
  #expect(writeStarted.value)

  let stopped = LockedFlag()
  Task.detached {
    server.stop()
    stopped.set()
  }
  for _ in 0..<40 where !stopped.value {
    try await Task.sleep(for: .milliseconds(5))
  }
  let stoppedPromptly = stopped.value
  Darwin.close(descriptor)
  if !stoppedPromptly {
    for _ in 0..<100 where !stopped.value {
      try await Task.sleep(for: .milliseconds(5))
    }
  }
  #expect(stoppedPromptly)

  try server.start()
  defer { server.stop() }
  let response = try await Task.detached {
    try transact(validRequest(), at: socketURL)
  }.value
  #expect(response.result == .sharedNotes(notes: []))
}

@Test @MainActor func stopDuringServicePreventsLateDescriptorWrite() async throws {
  let root = temporaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let socketURL = root.appendingPathComponent("bridge/fleck.sock")
  let gate = ServiceGate()
  let writes = LockedCounter()
  let server = AgentIPCServer(
    endpointURL: socketURL,
    responseWriter: { data, offset, _ in
      writes.increment()
      return data.count - offset
    },
    execute: { _, _, _ in
      await gate.execute()
      return .sharedNotes(notes: [])
    }
  )
  try server.start()

  let descriptor = try await Task.detached {
    let descriptor = try connectedSocket(to: socketURL)
    let frame = try AgentWireFraming.encode(validRequest())
    _ = frame.withUnsafeBytes {
      Darwin.write(descriptor, $0.baseAddress, $0.count)
    }
    return descriptor
  }.value
  await gate.waitUntilStarted()

  server.stop()
  Darwin.close(descriptor)
  gate.release()
  try await Task.sleep(for: .milliseconds(10))
  #expect(writes.value == 0)
}

@Test @MainActor func canceledReadSourceCannotConsumeReusedDescriptor() async throws {
  let root = temporaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let socketURL = root.appendingPathComponent("bridge/fleck.sock")
  let cancellationEntered = DispatchSemaphore(value: 0)
  let allowCancellation = DispatchSemaphore(value: 0)
  let cancellationCompleted = DispatchSemaphore(value: 0)
  let cancellationTouchedReplacement = LockedFlag()
  let stopGate = OneShotFlag()
  let replacement = DescriptorReplacement(marker: 0xA5)
  let server = AgentIPCServer(
    endpointURL: socketURL,
    peerUID: { descriptor in
      replacement.capture(descriptor)
      return geteuid()
    },
    descriptorCloser: { replacement.closeOrReplace($0) },
    stopWillCancelSources: {
      guard stopGate.take() else { return }
      cancellationEntered.signal()
      allowCancellation.wait()
    },
    sourceCancellationDidComplete: { descriptor in
      guard descriptor == replacement.target else { return }
      let readReplacement = replacement.readMarker() == 0xA5
      let wroteReplacement = replacement.writeIfInstalled(0xCC)
      if readReplacement || wroteReplacement {
        cancellationTouchedReplacement.set()
      }
      cancellationCompleted.signal()
    },
    execute: { _, _, _ in .sharedNotes(notes: []) }
  )
  try server.start()

  let descriptor = try await Task.detached {
    try connectedSocket(to: socketURL)
  }.value
  for _ in 0..<100 where replacement.target == -1 {
    try await Task.sleep(for: .milliseconds(2))
  }
  #expect(replacement.target >= 0)

  let stopped = DispatchSemaphore(value: 0)
  Task.detached {
    server.stop()
    stopped.signal()
  }
  let entered = await Task.detached {
    waitForSemaphore(cancellationEntered)
  }.value
  #expect(entered)
  var trigger: UInt8 = 1
  #expect(Darwin.write(descriptor, &trigger, 1) == 1)
  try await Task.sleep(for: .milliseconds(10))
  allowCancellation.signal()
  let didStop = await Task.detached {
    waitForSemaphore(stopped)
  }.value
  #expect(didStop)
  Darwin.close(descriptor)

  let didCancel = await Task.detached {
    waitForSemaphore(cancellationCompleted)
  }.value
  #expect(didCancel)
  #expect(!cancellationTouchedReplacement.value)
  #expect(replacement.readMarker() == 0xA5)
  #expect(replacement.roundTrips(0x5A))
}

@Test @MainActor func agentIPCRuntimeWaitsForReadinessAndOwnsOneListener()
  async throws
{
  let root = temporaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let socketURL = root.appendingPathComponent("bridge/fleck.sock")
  let server = AgentIPCServer(
    endpointURL: socketURL,
    execute: { _, _, _ in .sharedNotes(notes: []) }
  )
  let gate = ReadinessGate()
  var runtime: AgentIPCRuntime? = AgentIPCRuntime(
    server: server,
    waitUntilReady: { await gate.wait() }
  )
  #expect(runtime != nil)

  await Task.yield()
  #expect(!FileManager.default.fileExists(atPath: socketURL.path))
  gate.open()
  for _ in 0..<100 where !FileManager.default.fileExists(atPath: socketURL.path) {
    try await Task.sleep(for: .milliseconds(2))
  }
  #expect(FileManager.default.fileExists(atPath: socketURL.path))

  runtime = nil
  #expect(!FileManager.default.fileExists(atPath: socketURL.path))
}

@Test @MainActor func agentIPCRuntimeTerminationBeforeReadinessNeverBinds()
  async throws
{
  let root = temporaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let socketURL = root.appendingPathComponent("bridge/fleck.sock")
  let server = AgentIPCServer(
    endpointURL: socketURL,
    execute: { _, _, _ in .sharedNotes(notes: []) }
  )
  let gate = ReadinessGate()
  var runtime: AgentIPCRuntime? = AgentIPCRuntime(
    server: server,
    waitUntilReady: { await gate.wait() }
  )
  #expect(runtime != nil)
  await Task.yield()

  runtime = nil
  gate.open()
  try await Task.sleep(for: .milliseconds(10))
  #expect(!FileManager.default.fileExists(atPath: socketURL.path))
}

@Test @MainActor func agentIPCRuntimeDoesNotBindWhenStartupIsUnavailable()
  async throws
{
  let root = temporaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let socketURL = root.appendingPathComponent("bridge/fleck.sock")
  let server = AgentIPCServer(
    endpointURL: socketURL,
    execute: { _, _, _ in .sharedNotes(notes: []) }
  )
  let runtime = AgentIPCRuntime(
    server: server,
    waitUntilReady: {},
    canStart: { false }
  )
  _ = runtime

  try await Task.sleep(for: .milliseconds(10))

  #expect(!FileManager.default.fileExists(atPath: socketURL.path))
}

@Test @MainActor func appTerminationBeforeReadinessPermanentlyPreventsBind()
  async throws
{
  let root = temporaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let socketURL = root.appendingPathComponent("bridge/fleck.sock")
  let server = AgentIPCServer(
    endpointURL: socketURL,
    execute: { _, _, _ in .sharedNotes(notes: []) }
  )
  let gate = ReadinessGate()
  let notifications = NotificationCenter()
  let runtime = AgentIPCRuntime(
    server: server,
    waitUntilReady: { await gate.wait() },
    notificationCenter: notifications
  )
  _ = runtime
  await Task.yield()

  notifications.post(
    name: NSApplication.willTerminateNotification,
    object: nil
  )
  gate.open()
  try await Task.sleep(for: .milliseconds(10))
  #expect(!FileManager.default.fileExists(atPath: socketURL.path))
}

@Test @MainActor func agentIPCRejectsUnsafeParentAndPreservesForeignLeaf() throws {
  let root = temporaryRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let real = root.appendingPathComponent("real", isDirectory: true)
  let link = root.appendingPathComponent("link", isDirectory: true)
  try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
  try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
  let symlinkServer = AgentIPCServer(
    endpointURL: link.appendingPathComponent("fleck.sock"),
    execute: { _, _, _ in .sharedNotes(notes: []) }
  )
  #expect(throws: (any Error).self) { try symlinkServer.start() }

  let bridge = root.appendingPathComponent("bridge", isDirectory: true)
  try FileManager.default.createDirectory(at: bridge, withIntermediateDirectories: true)
  let leaf = bridge.appendingPathComponent("fleck.sock")
  try Data("preserve".utf8).write(to: leaf)
  let regularServer = AgentIPCServer(
    endpointURL: leaf,
    execute: { _, _, _ in .sharedNotes(notes: []) }
  )
  #expect(throws: (any Error).self) { try regularServer.start() }
  #expect(try String(contentsOf: leaf, encoding: .utf8) == "preserve")
}

private func validRequest() -> AgentWireRequest {
  AgentWireRequest(
    requestID: UUID(),
    profileID: UUID(),
    credentialBase64: Data(repeating: 3, count: 32).base64EncodedString(),
    command: .listSharedNotes
  )
}

private func temporaryRoot() -> URL {
  URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent(
    "fleck-ipc-\(UUID().uuidString)",
    isDirectory: true
  )
}

private func temporarySocketURL() -> URL {
  temporaryRoot().appendingPathComponent("bridge/fleck.sock")
}

private func connectedSocket(
  to url: URL,
  receiveBufferBytes: Int32? = nil
) throws -> Int32 {
  let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
  guard descriptor >= 0 else { throw SecretFailure(message: "socket") }
  if var receiveBufferBytes {
    _ = setsockopt(
      descriptor,
      SOL_SOCKET,
      SO_RCVBUF,
      &receiveBufferBytes,
      socklen_t(MemoryLayout<Int32>.size)
    )
  }
  var timeout = timeval(tv_sec: 1, tv_usec: 0)
  _ = setsockopt(
    descriptor,
    SOL_SOCKET,
    SO_RCVTIMEO,
    &timeout,
    socklen_t(MemoryLayout<timeval>.size)
  )
  var address = sockaddr_un()
  address.sun_family = sa_family_t(AF_UNIX)
  let bytes = Array(url.path.utf8) + [0]
  withUnsafeMutablePointer(to: &address.sun_path) { pointer in
    pointer.withMemoryRebound(to: UInt8.self, capacity: 104) {
      for (index, byte) in bytes.enumerated() {
        $0[index] = byte
      }
    }
  }
  let length = socklen_t(MemoryLayout<sa_family_t>.size + bytes.count)
  let result = withUnsafePointer(to: &address) { pointer in
    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      Darwin.connect(descriptor, $0, length)
    }
  }
  guard result == 0 else {
    Darwin.close(descriptor)
    throw SecretFailure(message: "connect")
  }
  return descriptor
}

private func transact(
  _ request: AgentWireRequest,
  at socketURL: URL
) throws -> AgentWireResponse {
  let descriptor = try connectedSocket(to: socketURL)
  defer { Darwin.close(descriptor) }
  try writeRequest(request, to: descriptor)
  let header = try readExactly(4, from: descriptor)
  let length = header.reduce(UInt32.zero) { ($0 << 8) | UInt32($1) }
  let payload = try readExactly(Int(length), from: descriptor)
  var frame = header + payload
  guard
    let response = try AgentWireFraming.decodeFrame(
      AgentWireResponse.self,
      from: &frame
    )
  else {
    throw SecretFailure(message: "decode")
  }
  return response
}

private func writeRequest(
  _ request: AgentWireRequest,
  to descriptor: Int32
) throws {
  let requestFrame = try AgentWireFraming.encode(request)
  let written = requestFrame.withUnsafeBytes {
    Darwin.write(descriptor, $0.baseAddress, $0.count)
  }
  guard written == requestFrame.count else {
    throw SecretFailure(message: "write")
  }
}

private func readExactly(_ count: Int, from descriptor: Int32) throws -> Data {
  var data = Data()
  while data.count < count {
    var buffer = [UInt8](repeating: 0, count: count - data.count)
    let received = Darwin.read(descriptor, &buffer, buffer.count)
    guard received > 0 else { throw SecretFailure(message: "read") }
    data.append(buffer, count: received)
  }
  return data
}

private func readAfterDelay(
  _ descriptor: Int32,
  microseconds: useconds_t = 20_000
) -> Bool {
  usleep(microseconds)
  var byte: UInt8 = 0
  return Darwin.read(descriptor, &byte, 1) == 0
}

private func waitForSemaphore(_ semaphore: DispatchSemaphore) -> Bool {
  semaphore.wait(timeout: .now() + 1) == .success
}

private struct SecretFailure: Error {
  let message: String
}

private final class LockedCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0

  var value: Int { lock.withLock { count } }
  func increment() { lock.withLock { count += 1 } }
}

private final class LockedFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var state = false

  var value: Bool { lock.withLock { state } }
  func set() { lock.withLock { state = true } }
}

private final class OneShotFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var available = true

  func take() -> Bool {
    lock.withLock {
      defer { available = false }
      return available
    }
  }
}

private final class DescriptorReplacement: @unchecked Sendable {
  private let lock = NSLock()
  private let marker: UInt8
  private var targetDescriptor: Int32 = -1
  private var replacementDescriptor: Int32 = -1
  private var peerDescriptor: Int32 = -1

  init(marker: UInt8) {
    self.marker = marker
  }

  deinit {
    if replacementDescriptor >= 0 {
      Darwin.close(replacementDescriptor)
    }
    if peerDescriptor >= 0 {
      Darwin.close(peerDescriptor)
    }
  }

  var target: Int32 { lock.withLock { targetDescriptor } }

  func capture(_ descriptor: Int32) {
    lock.withLock { targetDescriptor = descriptor }
  }

  func closeOrReplace(_ descriptor: Int32) {
    let shouldReplace = lock.withLock {
      descriptor == targetDescriptor && replacementDescriptor == -1
    }
    guard shouldReplace else {
      Darwin.shutdown(descriptor, SHUT_RDWR)
      Darwin.close(descriptor)
      return
    }

    var pair = [Int32](repeating: -1, count: 2)
    let pairResult = socketpair(AF_UNIX, SOCK_STREAM, 0, &pair)
    Darwin.shutdown(descriptor, SHUT_RDWR)
    Darwin.close(descriptor)
    guard
      pairResult == 0,
      dup2(pair[0], descriptor) == descriptor
    else {
      if pair[0] >= 0 { Darwin.close(pair[0]) }
      if pair[1] >= 0 { Darwin.close(pair[1]) }
      return
    }
    Darwin.close(pair[0])
    let flags = fcntl(descriptor, F_GETFL)
    _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)
    var marker = marker
    _ = Darwin.write(pair[1], &marker, 1)
    lock.withLock {
      replacementDescriptor = descriptor
      peerDescriptor = pair[1]
    }
  }

  func readMarker() -> UInt8? {
    let descriptor = lock.withLock { replacementDescriptor }
    guard descriptor >= 0 else { return nil }
    var byte: UInt8 = 0
    return Darwin.read(descriptor, &byte, 1) == 1 ? byte : nil
  }

  func writeIfInstalled(_ byte: UInt8) -> Bool {
    let descriptor = lock.withLock { replacementDescriptor }
    guard descriptor >= 0 else { return false }
    var byte = byte
    return Darwin.write(descriptor, &byte, 1) == 1
  }

  func roundTrips(_ byte: UInt8) -> Bool {
    let descriptors = lock.withLock {
      (replacementDescriptor, peerDescriptor)
    }
    guard descriptors.0 >= 0, descriptors.1 >= 0 else { return false }
    var outgoing = byte
    guard Darwin.write(descriptors.0, &outgoing, 1) == 1 else { return false }
    var incoming: UInt8 = 0
    return Darwin.read(descriptors.1, &incoming, 1) == 1
      && incoming == byte
  }
}

@MainActor
private final class ServiceGate {
  private var started = false
  private var startWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseWaiter: CheckedContinuation<Void, Never>?

  func execute() async {
    started = true
    let waiters = startWaiters
    startWaiters.removeAll()
    for waiter in waiters {
      waiter.resume()
    }
    await withCheckedContinuation { releaseWaiter = $0 }
  }

  func waitUntilStarted() async {
    guard !started else { return }
    await withCheckedContinuation { startWaiters.append($0) }
  }

  func release() {
    releaseWaiter?.resume()
    releaseWaiter = nil
  }
}

@MainActor
private final class ReadinessGate {
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    guard !isOpen else { return }
    await withCheckedContinuation { waiters.append($0) }
  }

  func open() {
    isOpen = true
    let current = waiters
    waiters.removeAll()
    for waiter in current {
      waiter.resume()
    }
  }
}
