import Darwin
import FleckAgentProtocol
import FleckCore
import Foundation
import Testing

@testable import FleckApp

@Suite("Agent event IPC lifecycle")
struct AgentEventIPCLifecycleTests {
  @Test func v2EventRequestAndPendingReceiptUseTheAuthenticatedWireContract() throws {
    let profileID = UUID(uuidString: "00000000-0000-4000-8000-000000000401")!
    let requestID = UUID(uuidString: "00000000-0000-4000-8000-000000000402")!
    let noteID = UUID(uuidString: "00000000-0000-4000-8000-000000000403")!
    let commandJSON =
      #"{"prepareEventSubscription":{"request":{"event":"note.created","scope":{"note_id":"\#(noteID.uuidString.lowercased())"},"callbackURL":"https://example.test/hook","signingSecret":"whsec_\#(Data(repeating: 0x19, count: 24).base64EncodedString())","ttl":{"milliseconds":60000}}}}"#
    let command = try? JSONDecoder().decode(
      AgentWorkspaceCommand.self, from: Data(commandJSON.utf8))
    #expect(command != nil)
    guard let command else { return }

    let request = AgentWireRequest(
      requestID: requestID,
      profileID: profileID,
      credentialBase64: Data(repeating: 0x27, count: 32).base64EncodedString(),
      command: command
    )
    let frame = try AgentWireFraming.encode(request)
    var input = frame
    let decoded = try #require(AgentWireFraming.decodeFrame(AgentWireRequest.self, from: &input))
    #expect(decoded == request)
    #expect(input.isEmpty)
    #expect(decoded.command.isSupported(wireVersion: 2))
    #expect(!decoded.command.isSupported(wireVersion: 1))
  }

  @Test @MainActor func authenticatedEventCommandCrossesTheIsolatedUnixSocket() async throws {
    let fixture = try await AgentEventIPCFixture()
    defer { fixture.remove() }
    let command = try JSONDecoder().decode(
      AgentWorkspaceCommand.self,
      from: Data(#"{"listEvents":{}}"#.utf8)
    )
    let socketFixture = try makeAgentEventIPCSocketFixture()
    defer { socketFixture.removeDirectoryIfUnchanged() }
    let endpointURL = socketFixture.endpointURL
    let server = AgentIPCServer(endpointURL: endpointURL) { profileID, credential, command in
      try await fixture.commandService.execute(
        profileID: profileID,
        credential: credential,
        command: command
      )
    }
    defer { server.stop() }
    try server.start()

    let profileID = fixture.profileID
    let credential = fixture.credential
    let requestID = UUID()
    let validResponse = try await Task.detached {
      try eventSocketRoundTrip(
        AgentWireRequest(
          requestID: requestID,
          profileID: profileID,
          credentialBase64: credential.base64EncodedString(),
          command: command
        ),
        endpointURL: endpointURL
      )
    }.value
    #expect(validResponse.requestID == requestID)
    #expect(validResponse.protocolVersion == 2)
    #expect(validResponse.error?.code == .invalidOperation)
    #expect(validResponse.result == nil)

    let unauthorizedResponse = try await Task.detached {
      try eventSocketRoundTrip(
        AgentWireRequest(
          requestID: UUID(),
          profileID: profileID,
          credentialBase64: Data(repeating: 0x32, count: 32).base64EncodedString(),
          command: command
        ),
        endpointURL: endpointURL
      )
    }.value
    #expect(unauthorizedResponse.error?.code == .permissionRevoked)
    #expect(!FileManager.default.fileExists(atPath: fixture.subscriptionFileURL.path))
    #expect(fixture.secretStore.writeCount() == 0)
  }

  @Test @MainActor func authenticatedPendingEventCommandCrossesTheIsolatedUnixSocket() async throws
  {
    let fixture = try await AgentEventIPCFixture(enableEventService: true)
    defer { fixture.remove() }
    let command = AgentWorkspaceCommand.prepareEventSubscription(
      request: AgentEventSubscriptionRequest(
        event: .noteUpdated,
        scope: .note(noteID: fixture.noteID),
        callbackURL: "https://example.test/hook",
        signingSecret: "whsec_" + Data(repeating: 0x42, count: 24).base64EncodedString()
      )
    )
    let socketFixture = try makeAgentEventIPCSocketFixture()
    defer { socketFixture.removeDirectoryIfUnchanged() }
    let endpointURL = socketFixture.endpointURL
    let server = AgentIPCServer(endpointURL: endpointURL) { profileID, credential, command in
      try await fixture.commandService.execute(
        profileID: profileID,
        credential: credential,
        command: command
      )
    }
    defer { server.stop() }
    try server.start()

    let profileID = fixture.profileID
    let credential = fixture.credential
    let response = try await Task.detached {
      try eventSocketRoundTrip(
        AgentWireRequest(
          requestID: UUID(),
          profileID: profileID,
          credentialBase64: credential.base64EncodedString(),
          command: command
        ),
        endpointURL: endpointURL
      )
    }.value
    #expect(response.error == nil)
    guard case .pendingEventSubscription(let receipt)? = response.result else {
      Issue.record("Expected an authenticated pending receipt from the event service.")
      return
    }
    #expect(receipt.status == "pending")
    #expect(fixture.secretStore.writeCount() == 1)
    #expect(fixture.secretStore.secretCount() == 1)
  }
}

struct AgentEventIPCSocketFixture {
  let endpointURL: URL
  let directoryURL: URL
  private let device: dev_t
  private let inode: ino_t
  private let uid: uid_t
  private let mode: mode_t

  init(endpointURL: URL, directoryURL: URL, status: stat) {
    self.endpointURL = endpointURL
    self.directoryURL = directoryURL
    device = status.st_dev
    inode = status.st_ino
    uid = status.st_uid
    mode = status.st_mode & 0o7777
  }

  func removeDirectoryIfUnchanged() {
    var currentStatus = stat()
    guard
      directoryURL.path.withCString({ Darwin.lstat($0, &currentStatus) }) == 0,
      currentStatus.st_mode & S_IFMT == S_IFDIR,
      currentStatus.st_dev == device,
      currentStatus.st_ino == inode,
      currentStatus.st_uid == uid,
      currentStatus.st_mode & 0o7777 == mode
    else {
      Issue.record("IPC fixture directory identity changed; cleanup left it untouched.")
      return
    }
    guard directoryURL.path.withCString({ Darwin.rmdir($0) }) == 0 else {
      Issue.record(
        "IPC fixture directory was not empty or could not be removed (errno \(errno))."
      )
      return
    }
  }
}

// Keep socket names under the short packet root while allowing an owned run/tmp below it.
func packetConfiguredTemporaryDirectoryIsPrivate(
  _ configuredRoot: URL,
  beneath root: URL,
  rootStatus: stat
) -> Bool {
  guard configuredRoot.path == root.path || configuredRoot.path.hasPrefix(root.path + "/"),
    canonicalAgentIPCPOSIXPath(configuredRoot.path) == configuredRoot.path
  else { return false }

  func matches(_ lhs: stat, _ rhs: stat) -> Bool {
    lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino
      && lhs.st_uid == rhs.st_uid && lhs.st_mode == rhs.st_mode
  }
  func isPrivate(_ value: stat) -> Bool {
    value.st_mode & S_IFMT == S_IFDIR && value.st_mode & 0o7777 == 0o700
      && value.st_uid == 501 && value.st_dev == rootStatus.st_dev && value.st_ino != 0
  }
  let flags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
  var descriptor = root.path.withCString { Darwin.open($0, flags) }
  guard descriptor >= 0 else { return false }
  defer { Darwin.close(descriptor) }
  var opened = stat()
  guard Darwin.fstat(descriptor, &opened) == 0, matches(opened, rootStatus),
    isPrivate(opened)
  else { return false }

  var current = root
  for component in configuredRoot.pathComponents.dropFirst(root.pathComponents.count) {
    let next = component.withCString { Darwin.openat(descriptor, $0, flags) }
    guard next >= 0 else { return false }
    Darwin.close(descriptor)
    descriptor = next
    current.appendPathComponent(component, isDirectory: true)
    var named = stat()
    guard Darwin.fstat(descriptor, &opened) == 0, isPrivate(opened),
      current.path.withCString({ Darwin.lstat($0, &named) }) == 0,
      matches(opened, named)
    else { return false }
  }
  var finalNamed = stat()
  var finalRoot = stat()
  return configuredRoot.path.withCString({ Darwin.lstat($0, &finalNamed) }) == 0
    && matches(opened, finalNamed)
    && root.path.withCString({ Darwin.lstat($0, &finalRoot) }) == 0
    && matches(rootStatus, finalRoot)
    && canonicalAgentIPCPOSIXPath(configuredRoot.path) == configuredRoot.path
}

func makeAgentEventIPCSocketFixture() throws -> AgentEventIPCSocketFixture {
  let environment = ProcessInfo.processInfo.environment
  guard
    environment["FLECK_IPC_PACKET_MODE"]
      == "current-source-35-body-packet-tmpdir-xctest-host-20261005",
    let packetTemporaryDirectory = environment["FLECK_IPC_PACKET_TMPDIR"],
    let configuredTemporaryDirectory = environment["TMPDIR"]
  else {
    throw AgentEventSocketTestError.unsafeFixtureDirectory
  }
  let root = URL(fileURLWithPath: packetTemporaryDirectory, isDirectory: true)
  let configuredRoot = URL(fileURLWithPath: configuredTemporaryDirectory, isDirectory: true)
  let rootName = root.lastPathComponent
  let token = rootName.hasPrefix("f35-") ? String(rootName.dropFirst("f35-".count)) : ""
  var rootStatus = stat()
  guard
    root.deletingLastPathComponent().path == "/private/tmp",
    rootName.hasPrefix("f35-"),
    token.utf8.count == 12,
    token.utf8.allSatisfy({ ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) }),
    canonicalAgentIPCPOSIXPath(root.path) == root.path,
    root.path.withCString({ Darwin.lstat($0, &rootStatus) }) == 0,
    rootStatus.st_mode & S_IFMT == S_IFDIR,
    rootStatus.st_mode & 0o7777 == 0o700,
    rootStatus.st_uid == 501,
    rootStatus.st_dev != 0,
    rootStatus.st_ino != 0
  else {
    throw AgentEventSocketTestError.unsafeFixtureDirectory
  }
  guard packetConfiguredTemporaryDirectoryIsPrivate(
    configuredRoot, beneath: root, rootStatus: rootStatus
  ) else {
    throw AgentEventSocketTestError.unsafeFixtureDirectory
  }

  let directoryURL = root.appendingPathComponent(
    "fe-\(UUID().uuidString.lowercased())",
    isDirectory: true
  )
  let mkdirResult = directoryURL.path.withCString { Darwin.mkdir($0, mode_t(0o700)) }
  guard mkdirResult == 0 else {
    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
  }

  var directoryStatus = stat()
  guard
    directoryURL.deletingLastPathComponent().path == root.path,
    directoryURL.path.withCString({ Darwin.lstat($0, &directoryStatus) }) == 0,
    directoryStatus.st_mode & S_IFMT == S_IFDIR,
    directoryStatus.st_uid == geteuid(),
    directoryStatus.st_mode & 0o7777 == 0o700,
    directoryStatus.st_dev != 0,
    directoryStatus.st_ino != 0
  else {
    throw AgentEventSocketTestError.unsafeFixtureDirectory
  }

  let endpointURL = directoryURL.appendingPathComponent("e.sock")
  guard endpointURL.path.utf8.count + 1 <= 104 else {
    let fixture = AgentEventIPCSocketFixture(
      endpointURL: endpointURL,
      directoryURL: directoryURL,
      status: directoryStatus
    )
    fixture.removeDirectoryIfUnchanged()
    throw AgentEventSocketTestError.socketPathTooLong
  }
  return AgentEventIPCSocketFixture(
    endpointURL: endpointURL,
    directoryURL: directoryURL,
    status: directoryStatus
  )
}

private enum AgentEventSocketTestError: Error {
  case unsafeFixtureDirectory
  case socketPathTooLong
  case socketCreation
  case connect
  case write
  case read
}

private func eventSocketRoundTrip(
  _ request: AgentWireRequest,
  endpointURL: URL
) throws -> AgentWireResponse {
  let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
  guard descriptor >= 0 else { throw AgentEventSocketTestError.socketCreation }
  defer { Darwin.close(descriptor) }

  var noSigPipe: Int32 = 1
  _ = setsockopt(
    descriptor,
    SOL_SOCKET,
    SO_NOSIGPIPE,
    &noSigPipe,
    socklen_t(MemoryLayout<Int32>.size)
  )
  var timeout = timeval(tv_sec: 5, tv_usec: 0)
  _ = setsockopt(
    descriptor,
    SOL_SOCKET,
    SO_RCVTIMEO,
    &timeout,
    socklen_t(MemoryLayout<timeval>.size)
  )

  var address = sockaddr_un()
  address.sun_family = sa_family_t(AF_UNIX)
  let path = Array(endpointURL.path.utf8)
  guard path.count < MemoryLayout.size(ofValue: address.sun_path) else {
    throw AgentEventSocketTestError.connect
  }
  withUnsafeMutableBytes(of: &address.sun_path) { buffer in
    guard let baseAddress = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
      return
    }
    for (index, byte) in path.enumerated() {
      baseAddress[index] = byte
    }
  }
  let addressLength = socklen_t(MemoryLayout<sa_family_t>.size + path.count + 1)
  let connected = withUnsafePointer(to: &address) { pointer in
    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      Darwin.connect(descriptor, $0, addressLength)
    }
  }
  guard connected == 0 else { throw AgentEventSocketTestError.connect }

  try eventWriteAll(AgentWireFraming.encode(request), to: descriptor)
  let header = try eventReadExactly(4, from: descriptor)
  let length = header.reduce(UInt32.zero) { ($0 << 8) | UInt32($1) }
  guard length > 0, length <= AgentWireFraming.maximumFrameBytes else {
    throw AgentEventSocketTestError.read
  }
  var frame = header
  frame.append(try eventReadExactly(Int(length), from: descriptor))
  guard let response = try AgentWireFraming.decodeFrame(AgentWireResponse.self, from: &frame) else {
    throw AgentEventSocketTestError.read
  }
  return response
}

private func eventWriteAll(_ data: Data, to descriptor: Int32) throws {
  var offset = 0
  while offset < data.count {
    let count = data.withUnsafeBytes { bytes in
      Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
    }
    if count > 0 {
      offset += count
    } else if count < 0, errno == EINTR {
      continue
    } else {
      throw AgentEventSocketTestError.write
    }
  }
}

private func eventReadExactly(_ count: Int, from descriptor: Int32) throws -> Data {
  var data = Data()
  while data.count < count {
    var bytes = [UInt8](repeating: 0, count: count - data.count)
    let readCount = Darwin.read(descriptor, &bytes, bytes.count)
    if readCount > 0 {
      data.append(contentsOf: bytes.prefix(readCount))
    } else if readCount < 0, errno == EINTR {
      continue
    } else {
      throw AgentEventSocketTestError.read
    }
  }
  return data
}
