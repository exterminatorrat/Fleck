import Foundation
import Testing

#if os(macOS)
import Darwin
#endif

@testable import FleckApp

@Test
func gemmaProcessTransportPublishesOnlyRequestLifecycleAndProvesGracefulDrain() async throws {
  let fixture = try GemmaHelperFixture(mode: "normal")
  let transport = fixture.makeTransport(useSandbox: false)
  let request = GemmaProcessTestRequest.make()
  let session = try transport.start(request)

  let expectation = session.terminationExpectation
  #expect(expectation.cleanupRequestID == request.requestID)
  #expect(expectation.cancellationCommandID == "cancel-\(request.requestID)")
  #expect(expectation.shutdownCommandID == "shutdown-\(request.requestID)")

  let events = try await withTimeout {
    var events: [Data] = []
    for try await event in session.events {
      events.append(event)
    }
    return events
  }
  #expect(events.count == 3)
  #expect(events.map { try? wireKind($0) } == ["ready", "started", "completed"])

  let disposition = await session.terminationAcknowledgement(
    for: .graceful(requireCancellationAcknowledgement: false)
  )
  guard case .verified(let proof) = disposition else {
    Issue.record("expected a verified graceful disposition, got \(disposition)")
    return
  }
  #expect(proof.phase == .graceful(requireCancellationAcknowledgement: false))
  #expect(proof.cleanupRequestID == request.requestID)
  #expect(proof.cancellationCommandID == nil)
  #expect(proof.cancellationTargetRequestID == nil)
  #expect(proof.shutdownCommandID == "shutdown-\(request.requestID)")
  #expect(proof.cooperative)
  #expect(!proof.processTerminationMayBeRequired)
  #expect(proof.processExited)
  #expect(proof.outputDrained)

  let commands = try fixture.commands()
  #expect(commands.count == 2)
  #expect(try wireOperation(commands[0]) == "cleanup")
  #expect(try wireOperation(commands[1]) == "shutdown")
  #expect(try wireRequestID(commands[0]) == request.requestID)
  #expect(try wireRequestID(commands[1]) == "shutdown-\(request.requestID)")
  #expect(try wireTargetRequestID(commands[1]) == nil)
  #expect(try fixture.arguments() == ["--model-directory", fixture.modelDirectory.path])
}

@Test
func gemmaProcessTransportRejectsPrematureShutdownAcknowledgement() async throws {
  let fixture = try GemmaHelperFixture(mode: "premature-shutdown-ack")
  defer { fixture.forceKillForTest() }
  let transport = GemmaCleanupProcessTransport(
    helperExecutableURL: fixture.helperExecutableURL,
    modelDirectoryURL: fixture.modelDirectory,
    sandboxExecutableURL: nil,
    timing: .short,
    beforeInitialWrite: {
      _ = fixture.waitForMarkerSynchronously("premature-shutdown-ack")
      usleep(250_000)
    }
  )
  let session = try transport.start(GemmaProcessTestRequest.make())
  let events = try await withTimeout { try await collect(session.events) }
  #expect(events.map { try? wireKind($0) } == ["ready", "started", "completed"])

  let graceful = await session.terminationAcknowledgement(
    for: .graceful(requireCancellationAcknowledgement: false)
  )
  #expect(graceful == .failed(.unverifiable))

  let forced = await session.terminationAcknowledgement(for: .forced)
  guard case .verified(let proof) = forced else {
    Issue.record("premature shutdown acknowledgement did not drain: \(forced)")
    return
  }
  #expect(proof.processExited)
  #expect(proof.outputDrained)
  #expect(try !fixture.processIsAlive())
}

@Test
func gemmaProcessTransportRejectsPrematureCancellationAcknowledgement() async throws {
  let fixture = try GemmaHelperFixture(mode: "premature-cancellation-ack")
  defer { fixture.forceKillForTest() }
  let transport = GemmaCleanupProcessTransport(
    helperExecutableURL: fixture.helperExecutableURL,
    modelDirectoryURL: fixture.modelDirectory,
    sandboxExecutableURL: nil,
    timing: .short,
    beforeInitialWrite: {
      _ = fixture.waitForMarkerSynchronously("premature-cancellation-ack")
      usleep(250_000)
    }
  )
  let session = try transport.start(GemmaProcessTestRequest.make())
  let events = try await withTimeout { try await collect(session.events) }
  #expect(events.map { try? wireKind($0) } == ["ready", "started", "completed"])

  session.requestCancellation()
  let graceful = await session.terminationAcknowledgement(
    for: .graceful(requireCancellationAcknowledgement: true)
  )
  #expect(graceful == .failed(.unverifiable))

  let forced = await session.terminationAcknowledgement(for: .forced)
  guard case .verified(let proof) = forced else {
    Issue.record("premature cancellation acknowledgement did not drain: \(forced)")
    return
  }
  #expect(proof.processExited)
  #expect(proof.outputDrained)
  #expect(try !fixture.processIsAlive())
}

@Test
func gemmaProcessTransportUsesSandboxExecByDefault() async throws {
  let fixture = try GemmaHelperFixture(mode: "normal")
  let transport = fixture.makeTransport(useSandbox: true)
  let session = try transport.start(GemmaProcessTestRequest.make())
  _ = try await collect(session.events)
  let disposition = await session.terminationAcknowledgement(
    for: .graceful(requireCancellationAcknowledgement: false)
  )
  guard case .verified = disposition else {
    Issue.record("expected sandboxed helper to terminate cleanly: \(disposition)")
    return
  }
  #expect(try fixture.arguments() == ["--model-directory", fixture.modelDirectory.path])
}

@Test
func gemmaProcessTransportSendsOneExactCancellationAndKeepsAcknowledgementsPrivate() async throws {
  let fixture = try GemmaHelperFixture(mode: "cancel")
  let transport = fixture.makeTransport(useSandbox: false)
  let request = GemmaProcessTestRequest.make()
  let session = try transport.start(request)
  var iterator = session.events.makeAsyncIterator()

  #expect(try wireKind(try await next(&iterator)) == "ready")
  #expect(try wireKind(try await next(&iterator)) == "started")

  await withTaskGroup(of: Void.self) { group in
    for _ in 0..<8 {
      group.addTask { session.requestCancellation() }
    }
  }

  #expect(try wireKind(try await next(&iterator)) == "cancelled")
  #expect(try await iterator.next() == nil)

  let disposition = await session.terminationAcknowledgement(
    for: .graceful(requireCancellationAcknowledgement: true)
  )
  guard case .verified(let proof) = disposition else {
    Issue.record("expected a verified cancellation disposition, got \(disposition)")
    return
  }
  #expect(proof.cancellationCommandID == "cancel-\(request.requestID)")
  #expect(proof.cancellationTargetRequestID == request.requestID)
  #expect(proof.shutdownCommandID == "shutdown-\(request.requestID)")
  #expect(proof.cooperative)
  #expect(!proof.processTerminationMayBeRequired)
  #expect(proof.processExited)
  #expect(proof.outputDrained)

  let commands = try fixture.commands()
  #expect(commands.count == 3)
  #expect(commands.filter { (try? wireOperation($0)) == "cancel" }.count == 1)
  #expect(try wireRequestID(commands[1]) == "cancel-\(request.requestID)")
  #expect(try wireTargetRequestID(commands[1]) == request.requestID)
}

@Test
func gemmaProcessTransportForceEscalatesOnceAndNeverPublishesLateOutput() async throws {
  let fixture = try GemmaHelperFixture(mode: "ignore-term")
  let transport = fixture.makeTransport(
    useSandbox: false,
    timing: .short
  )
  let session = try transport.start(GemmaProcessTestRequest.make())
  var iterator = session.events.makeAsyncIterator()
  #expect(try wireKind(try await next(&iterator)) == "ready")
  #expect(try wireKind(try await next(&iterator)) == "started")

  let publicFailure = Task {
    do {
      while try await iterator.next() != nil {}
      return false
    } catch {
      return true
    }
  }
  for _ in 0..<8 { session.forceTerminate() }

  #expect(try await withTimeout { await publicFailure.value })
  let disposition = await session.terminationAcknowledgement(for: .forced)
  guard case .verified(let proof) = disposition else {
    Issue.record("expected forced drain proof, got \(disposition)")
    return
  }
  #expect(proof.phase == .forced)
  #expect(proof.cleanupRequestID == "cleanup-test")
  #expect(proof.processExited)
  #expect(proof.outputDrained)
  #expect(try fixture.signalLog() == "TERM")
}

@Test
func gemmaProcessTransportOverlappingGracefulAndForcedWaitsDoNotDeadlock() async throws {
  let fixture = try GemmaHelperFixture(mode: "stall")
  let transport = fixture.makeTransport(
    useSandbox: false,
    timing: .short
  )
  let session = try transport.start(GemmaProcessTestRequest.make())
  var iterator = session.events.makeAsyncIterator()
  _ = try await next(&iterator)
  _ = try await next(&iterator)

  let graceful = Task {
    await session.terminationAcknowledgement(
      for: .graceful(requireCancellationAcknowledgement: false)
    )
  }
  try await Task.sleep(nanoseconds: 20_000_000)
  let forced = Task { await session.terminationAcknowledgement(for: .forced) }
  let forcedDisposition = try await withTimeout { await forced.value }
  let gracefulDisposition = try await withTimeout { await graceful.value }

  guard case .verified(let forcedProof) = forcedDisposition else {
    Issue.record("expected forced proof, got \(forcedDisposition)")
    return
  }
  #expect(forcedProof.processExited)
  #expect(forcedProof.outputDrained)
  #expect(gracefulDisposition == .failed(.unverifiable))
}

@Test
func gemmaProcessTransportGracefulFailureForcesWhenTerminalIsMissing() async throws {
  let fixture = try GemmaHelperFixture(mode: "ignore-term")
  let session = try fixture.makeTransport(
    useSandbox: false,
    timing: .short
  ).start(GemmaProcessTestRequest.make())
  var iterator = session.events.makeAsyncIterator()
  _ = try await next(&iterator)
  _ = try await next(&iterator)

  let gracefulDisposition = try await withTimeout {
    await session.terminationAcknowledgement(
      for: .graceful(requireCancellationAcknowledgement: false)
    )
  }
  #expect(gracefulDisposition == .failed(.unverifiable))
  #expect(try fixture.signalLog() == "TERM")

  let forcedDisposition = await session.terminationAcknowledgement(for: .forced)
  guard case .verified(let proof) = forcedDisposition else {
    Issue.record("missing-terminal graceful failure did not drain: \(forcedDisposition)")
    return
  }
  #expect(proof.processExited)
  #expect(proof.outputDrained)
}

@Test
func gemmaProcessTransportRejectsMalformedTruncatedOversizedExtraAndLateOutput() async throws {
  for mode in ["duplicate", "truncated", "oversized", "extra"] {
    let fixture = try GemmaHelperFixture(mode: mode)
    let transport = fixture.makeTransport(
      useSandbox: false,
      timing: .short
    )
    let session = try transport.start(GemmaProcessTestRequest.make())
    await #expect(throws: Error.self, "mode \(mode)") {
      _ = try await withTimeout {
        try await collect(session.events)
      }
    }
    let disposition = await session.terminationAcknowledgement(for: .forced)
    guard case .verified(let proof) = disposition else {
      Issue.record("mode \(mode) did not drain after failure: \(disposition)")
      continue
    }
    #expect(proof.processExited)
    #expect(proof.outputDrained)
  }

  let lateFixture = try GemmaHelperFixture(mode: "late")
  let lateSession = try lateFixture.makeTransport(
    useSandbox: false,
    timing: .short
  ).start(GemmaProcessTestRequest.make())
  let lateEvents = try await withTimeout { try await collect(lateSession.events) }
  #expect(lateEvents.map { try? wireKind($0) } == ["ready", "started", "completed"])
  #expect(
    await lateSession.terminationAcknowledgement(
      for: .graceful(requireCancellationAcknowledgement: false)
    ) == .failed(.unverifiable)
  )
  let lateDisposition = await lateSession.terminationAcknowledgement(for: .forced)
  guard case .verified(let lateProof) = lateDisposition else {
    Issue.record("late output did not force a verified drain: (lateDisposition)")
    return
  }
  #expect(lateProof.processExited)
  #expect(lateProof.outputDrained)
}

@Test
func gemmaProcessTransportRejectsForeignAndNoncooperativeControlFlags() async throws {
  let foreignFixture = try GemmaHelperFixture(mode: "foreign-control")
  let foreignSession = try foreignFixture.makeTransport(
    useSandbox: false,
    timing: .short
  ).start(GemmaProcessTestRequest.make())
  var foreignIterator = foreignSession.events.makeAsyncIterator()
  _ = try await next(&foreignIterator)
  _ = try await next(&foreignIterator)
  foreignSession.requestCancellation()
  #expect(try wireKind(try await next(&foreignIterator)) == "cancelled")
  #expect(try await foreignIterator.next() == nil)
  try await Task.sleep(nanoseconds: 20_000_000)
  #expect(
    await foreignSession.terminationAcknowledgement(
      for: .graceful(requireCancellationAcknowledgement: true)
    ) == .failed(.unverifiable)
  )
  let foreignDisposition = await foreignSession.terminationAcknowledgement(for: .forced)
  guard case .verified(let foreignProof) = foreignDisposition else {
    Issue.record("foreign control did not force a verified drain: (foreignDisposition)")
    return
  }
  #expect(foreignProof.processExited)
  #expect(foreignProof.outputDrained)

  let noncooperativeFixture = try GemmaHelperFixture(mode: "noncooperative")
  let noncooperativeSession = try noncooperativeFixture.makeTransport(
    useSandbox: false,
    timing: .short
  ).start(GemmaProcessTestRequest.make())
  var noncooperativeIterator = noncooperativeSession.events.makeAsyncIterator()
  _ = try await next(&noncooperativeIterator)
  _ = try await next(&noncooperativeIterator)
  noncooperativeSession.requestCancellation()
  await #expect(throws: Error.self) {
    while try await noncooperativeIterator.next() != nil {}
  }
  let noncooperativeDisposition = await noncooperativeSession.terminationAcknowledgement(
    for: .forced
  )
  guard case .verified(let noncooperativeProof) = noncooperativeDisposition else {
    Issue.record(
      "noncooperative flags did not force a verified drain: (noncooperativeDisposition)"
    )
    return
  }
  #expect(noncooperativeProof.processExited)
  #expect(noncooperativeProof.outputDrained)
}

@Test
func gemmaProcessTransportFailsClosedForEarlyExitAndBrokenPipe() async throws {
  let earlyExit = try GemmaHelperFixture(mode: "early-exit")
  let earlySession = try earlyExit.makeTransport(useSandbox: false).start(
    GemmaProcessTestRequest.make()
  )
  await #expect(throws: Error.self) {
    _ = try await withTimeout { try await collect(earlySession.events) }
  }
  let earlyDisposition = await earlySession.terminationAcknowledgement(for: .forced)
  #expect(earlyDisposition == .failed(.unverifiable))

  let brokenPipe = try GemmaHelperFixture(mode: "close-stdin")
  let brokenSession = try brokenPipe.makeTransport(
    useSandbox: false,
    timing: .short
  ).start(
    GemmaProcessTestRequest.make()
  )
  var brokenIterator = brokenSession.events.makeAsyncIterator()
  _ = try await next(&brokenIterator)
  _ = try await next(&brokenIterator)
  try await withTimeout {
    try await brokenPipe.waitForMarker("stdin-closed")
  }
  brokenSession.requestCancellation()
  await #expect(throws: Error.self) {
    _ = try await withTimeout { try await collect(brokenSession.events) }
  }
  let brokenDisposition = await brokenSession.terminationAcknowledgement(for: .forced)
  guard case .verified(let brokenProof) = brokenDisposition else {
    Issue.record("broken pipe did not force a verified drain: (brokenDisposition)")
    return
  }
  #expect(brokenProof.processExited)
  #expect(brokenProof.outputDrained)
  #expect(try brokenPipe.commands().count == 1)
}

@Test
func gemmaProcessTransportRejectsOversizedStderrWithoutRetainingIt() async throws {
  let fixture = try GemmaHelperFixture(mode: "stderr-large")
  let session = try fixture.makeTransport(useSandbox: false, timing: .short).start(
    GemmaProcessTestRequest.make()
  )
  await #expect(throws: Error.self) {
    _ = try await withTimeout { try await collect(session.events) }
  }
  let disposition = await session.terminationAcknowledgement(for: .forced)
  guard case .verified(let proof) = disposition else {
    Issue.record("stderr overflow did not drain: \(disposition)")
    return
  }
  #expect(proof.processExited)
  #expect(proof.outputDrained)
}

@Test
func gemmaProcessTransportRejectsLaunchFailureSynchronously() {
  let missing = URL(fileURLWithPath: "/tmp/fleck-missing-gemma-helper-\(UUID().uuidString)")
  let transport = GemmaCleanupProcessTransport(
    helperExecutableURL: missing,
    modelDirectoryURL: URL(fileURLWithPath: "/tmp"),
    sandboxExecutableURL: nil
  )
  #expect(throws: Error.self) {
    _ = try transport.start(GemmaProcessTestRequest.make())
  }
}

@Test
func gemmaProcessTransportFailsBeforeLaunchWhenNoSIGPIPECannotBeConfigured() throws {
  let fixture = try GemmaHelperFixture(mode: "normal")
  let transport = GemmaCleanupProcessTransport(
    helperExecutableURL: fixture.helperExecutableURL,
    modelDirectoryURL: fixture.modelDirectory,
    sandboxExecutableURL: nil,
    configureNoSIGPIPE: { _ in -1 }
  )

  #expect(throws: Error.self) {
    _ = try transport.start(GemmaProcessTestRequest.make())
  }
  #expect(try fixture.arguments().isEmpty)
  #expect(
    String(
      decoding: try Data(contentsOf: fixture.modelDirectory.appendingPathComponent("pid")),
      as: UTF8.self
    ).isEmpty
  )
}

@Test
func gemmaProcessTransportRejectsNonCanonicalLaunchPathsBeforeLaunching() throws {
  let fixture = try GemmaHelperFixture(mode: "early-exit")
  let fileManager = FileManager.default
  let helperSymlink = fixture.root.appendingPathComponent("helper-link")
  let modelSymlink = fixture.root.appendingPathComponent("model-link")
  let sandboxSymlink = fixture.root.appendingPathComponent("sandbox-link")
  let ancestorSymlink = fixture.root.appendingPathComponent("ancestor-link")
  let sandboxCopy = fixture.root.appendingPathComponent("sandbox-copy")
  let noExecuteHelper = fixture.root.appendingPathComponent("helper-no-execute.sh")
  try fileManager.createSymbolicLink(
    at: helperSymlink,
    withDestinationURL: fixture.helperExecutableURL
  )
  try fileManager.createSymbolicLink(
    at: modelSymlink,
    withDestinationURL: fixture.modelDirectory
  )
  try fileManager.createSymbolicLink(
    at: sandboxSymlink,
    withDestinationURL: GemmaCleanupProcessTransport.defaultSandboxExecutableURL
  )
  try fileManager.createSymbolicLink(
    at: ancestorSymlink,
    withDestinationURL: fixture.root
  )
  try fileManager.copyItem(
    at: GemmaCleanupProcessTransport.defaultSandboxExecutableURL,
    to: sandboxCopy
  )
  try fileManager.copyItem(at: fixture.helperExecutableURL, to: noExecuteHelper)
  try fileManager.setAttributes(
    [.posixPermissions: NSNumber(value: Int16(0o644))],
    ofItemAtPath: noExecuteHelper.path
  )

  let nonCanonicalHelper = fixture.root
    .appendingPathComponent("model")
    .appendingPathComponent("..")
    .appendingPathComponent("fake-helper.sh")
  let nonCanonicalModel = fixture.root
    .appendingPathComponent("model")
    .appendingPathComponent("..")
    .appendingPathComponent("model")
  let ancestorHelper = ancestorSymlink.appendingPathComponent("fake-helper.sh")
  let ancestorModel = ancestorSymlink.appendingPathComponent("model")
  let ancestorSandbox = ancestorSymlink.appendingPathComponent("sandbox-copy")
  let transports: [(String, GemmaCleanupProcessTransport)] = [
    (
      "helper symlink",
      GemmaCleanupProcessTransport(
        helperExecutableURL: helperSymlink,
        modelDirectoryURL: fixture.modelDirectory,
        sandboxExecutableURL: nil
      )
    ),
    (
      "model symlink",
      GemmaCleanupProcessTransport(
        helperExecutableURL: fixture.helperExecutableURL,
        modelDirectoryURL: modelSymlink,
        sandboxExecutableURL: nil
      )
    ),
    (
      "sandbox symlink",
      GemmaCleanupProcessTransport(
        helperExecutableURL: fixture.helperExecutableURL,
        modelDirectoryURL: fixture.modelDirectory,
        sandboxExecutableURL: sandboxSymlink
      )
    ),
    (
      "non-executable helper",
      GemmaCleanupProcessTransport(
        helperExecutableURL: noExecuteHelper,
        modelDirectoryURL: fixture.modelDirectory,
        sandboxExecutableURL: nil
      )
    ),
    (
      "non-canonical helper",
      GemmaCleanupProcessTransport(
        helperExecutableURL: nonCanonicalHelper,
        modelDirectoryURL: fixture.modelDirectory,
        sandboxExecutableURL: nil
      )
    ),
    (
      "non-canonical model",
      GemmaCleanupProcessTransport(
        helperExecutableURL: fixture.helperExecutableURL,
        modelDirectoryURL: nonCanonicalModel,
        sandboxExecutableURL: nil
      )
    ),
    (
      "model file",
      GemmaCleanupProcessTransport(
        helperExecutableURL: fixture.helperExecutableURL,
        modelDirectoryURL: fixture.modelDirectory.appendingPathComponent("mode"),
        sandboxExecutableURL: nil
      )
    ),
    (
      "helper ancestor symlink",
      GemmaCleanupProcessTransport(
        helperExecutableURL: ancestorHelper,
        modelDirectoryURL: fixture.modelDirectory,
        sandboxExecutableURL: nil
      )
    ),
    (
      "model ancestor symlink",
      GemmaCleanupProcessTransport(
        helperExecutableURL: fixture.helperExecutableURL,
        modelDirectoryURL: ancestorModel,
        sandboxExecutableURL: nil
      )
    ),
    (
      "sandbox ancestor symlink",
      GemmaCleanupProcessTransport(
        helperExecutableURL: fixture.helperExecutableURL,
        modelDirectoryURL: fixture.modelDirectory,
        sandboxExecutableURL: ancestorSandbox
      )
    ),
  ]

  for (_, transport) in transports {
    #expect(throws: Error.self) {
      _ = try transport.start(GemmaProcessTestRequest.make())
    }
  }
  #expect(try fixture.arguments().isEmpty)
}

@Test
func gemmaProcessTransportCleansUpAHelperWhenInitialWriteFailsAsynchronously() async throws {
  let fixture = try GemmaHelperFixture(mode: "startup-close-stdin")
  defer { fixture.forceKillForTest() }
  let request = GemmaProcessTestRequest.make(
    plainPrompt: String(repeating: "x", count: 60_000)
  )
  let transportWithBarrier = GemmaCleanupProcessTransport(
    helperExecutableURL: fixture.helperExecutableURL,
    modelDirectoryURL: fixture.modelDirectory,
    sandboxExecutableURL: nil,
    timing: .short,
    beforeInitialWrite: {
      _ = fixture.waitForMarkerSynchronously("stdin-closed")
    }
  )

  let session = try transportWithBarrier.start(request)
  try await withTimeout {
    try await fixture.waitForMarker("stdin-closed")
  }
  await #expect(throws: Error.self) {
    _ = try await withTimeout { try await collect(session.events) }
  }
  let disposition = await session.terminationAcknowledgement(for: .forced)
  guard case .verified(let proof) = disposition else {
    Issue.record("asynchronous initial write failure did not drain: \(disposition)")
    return
  }
  #expect(proof.processExited)
  #expect(proof.outputDrained)
  try await withTimeout {
    try await fixture.waitForProcessExit()
  }
  #expect(try !fixture.processIsAlive())
}

@Test
func gemmaProcessTransportReturnsBeforeAColdHelperReadsALargeRequest() async throws {
  let fixture = try GemmaHelperFixture(mode: "delayed-read")
  let transport = GemmaCleanupProcessTransport(
    helperExecutableURL: fixture.helperExecutableURL,
    modelDirectoryURL: fixture.modelDirectory,
    sandboxExecutableURL: nil,
    timing: .short,
    beforeInitialWrite: {
      _ = fixture.waitForMarkerSynchronously("stdin-delayed")
      usleep(250_000)
    }
  )
  let request = GemmaProcessTestRequest.make(
    plainPrompt: String(repeating: "x", count: 63_500)
  )
  let startTask = Task.detached {
    try transport.start(request)
  }

  var session: (any GemmaCleanupTransportSession)?
  do {
    session = try await withTimeout(nanoseconds: 100_000_000) {
      try await startTask.value
    }
  } catch {
    Issue.record("start did not return before the delayed helper read: \(error)")
    session = try await withTimeout(nanoseconds: 1_000_000_000) {
      try await startTask.value
    }
  }

  guard let session else { return }
  try await withTimeout {
    try await fixture.waitForMarker("stdin-delayed")
  }
  let cancellationStart = DispatchTime.now().uptimeNanoseconds
  session.requestCancellation()
  let cancellationElapsed = DispatchTime.now().uptimeNanoseconds - cancellationStart
  #expect(cancellationElapsed < 100_000_000)
  session.forceTerminate()
  let disposition = try await withTimeout(nanoseconds: 1_000_000_000) {
    await session.terminationAcknowledgement(for: .forced)
  }
  guard case .verified(let proof) = disposition else {
    Issue.record("delayed-read force did not drain: \(disposition)")
    return
  }
  #expect(proof.processExited)
  #expect(proof.outputDrained)
  try await withTimeout {
    try await fixture.waitForProcessExit()
  }
  #expect(try !fixture.processIsAlive())
}

@Test
func gemmaProcessTransportSerializesStdinCloseAfterAnActualBlockedInitialWrite() async throws {
  let fixture = try GemmaHelperFixture(mode: "blocked-write")
  defer { fixture.forceKillForTest() }
  let transport = GemmaCleanupProcessTransport(
    helperExecutableURL: fixture.helperExecutableURL,
    modelDirectoryURL: fixture.modelDirectory,
    sandboxExecutableURL: nil,
    timing: .short,
    beforeInitialWrite: {
      _ = fixture.waitForMarkerSynchronously("blocked-write-ready")
      fixture.mark("initial-write-entered")
    },
    afterInitialWrite: {
      fixture.mark("initial-write-completed")
    },
    afterInputClose: {
      fixture.mark("stdin-close-completed")
    },
    prepareInputBeforeLaunch: { input in
#if os(macOS)
      let descriptor = input.fileDescriptor
      let originalFlags = fcntl(descriptor, F_GETFL)
      guard originalFlags >= 0,
            fcntl(descriptor, F_SETFL, originalFlags | O_NONBLOCK) == 0
      else {
        throw TestFailure.pipeFillFailed
      }
      defer { _ = fcntl(descriptor, F_SETFL, originalFlags) }

      let filler = Data(repeating: 0, count: 4_096)
      while true {
        let result = filler.withUnsafeBytes { buffer in
          Darwin.write(descriptor, buffer.baseAddress, buffer.count)
        }
        if result >= 0 {
          continue
        }
        guard errno == EAGAIN || errno == EWOULDBLOCK else {
          throw TestFailure.pipeFillFailed
        }
        break
      }
#else
      throw TestFailure.pipeFillFailed
#endif
    }
  )
  let request = GemmaProcessTestRequest.make(
    plainPrompt: String(repeating: "x", count: 65_370)
  )
  let startTime = DispatchTime.now().uptimeNanoseconds
  let session = try transport.start(request)
  let startElapsed = DispatchTime.now().uptimeNanoseconds - startTime
  #expect(startElapsed < 100_000_000)

  var iterator = session.events.makeAsyncIterator()
  #expect(try wireKind(try await next(&iterator)) == "ready")
  try await withTimeout {
    try await fixture.waitForMarker("initial-write-entered")
  }
  #expect(!fixture.markerExists("initial-write-completed"))
  #expect(!fixture.markerExists("stdin-close-completed"))

  let forceTime = DispatchTime.now().uptimeNanoseconds
  session.forceTerminate()
  let forceElapsed = DispatchTime.now().uptimeNanoseconds - forceTime
  #expect(forceElapsed < 100_000_000)
  #expect(!fixture.markerExists("stdin-close-completed"))

  await #expect(throws: Error.self) {
    while try await iterator.next() != nil {}
  }
  let disposition = try await withTimeout(nanoseconds: 1_000_000_000) {
    await session.terminationAcknowledgement(for: .forced)
  }
  guard case .verified(let proof) = disposition else {
    Issue.record("blocked initial write did not force-drain: \(disposition)")
    return
  }
  #expect(proof.processExited)
  #expect(proof.outputDrained)
  try await withTimeout {
    try await fixture.waitForMarker("stdin-close-completed")
  }
  #expect(!fixture.markerExists("initial-write-completed"))
  #expect(try !fixture.processIsAlive())
}

private func collect(
  _ events: AsyncThrowingStream<Data, Error>
) async throws -> [Data] {
  var result: [Data] = []
  for try await event in events {
    result.append(event)
  }
  return result
}

private func next(
  _ iterator: inout AsyncThrowingStream<Data, Error>.AsyncIterator
) async throws -> Data {
  guard let event = try await iterator.next() else {
    throw TestFailure.unexpectedEOF
  }
  return event
}

private func withTimeout<T: Sendable>(
  nanoseconds: UInt64 = 5_000_000_000,
  operation: @escaping @Sendable () async throws -> T
) async throws -> T {
  let race = TimeoutRace<T>()
  return try await withTaskCancellationHandler {
    try await withCheckedThrowingContinuation { continuation in
      race.start(
        operation: operation,
        timeoutNanoseconds: nanoseconds,
        continuation: continuation
      )
    }
  } onCancel: {
    race.cancel()
  }
}

private enum TestFailure: Error {
  case timeout
  case unexpectedEOF
  case pipeFillFailed
}

private final class TimeoutRace<T: Sendable>: @unchecked Sendable {
  private enum Outcome: @unchecked Sendable {
    case success(T)
    case failure(Error)
  }

  private let lock = NSLock()
  private var continuation: CheckedContinuation<T, Error>?
  private var finished = false
  private var operationTask: Task<Void, Never>?
  private var timeoutTask: Task<Void, Never>?

  func start(
    operation: @escaping @Sendable () async throws -> T,
    timeoutNanoseconds: UInt64,
    continuation: CheckedContinuation<T, Error>
  ) {
    lock.lock()
    self.continuation = continuation
    lock.unlock()

    let operationTask = Task { [self] in
      do {
        finish(.success(try await operation()))
      } catch {
        finish(.failure(error))
      }
    }
    install(operationTask, asOperation: true)

    let timeoutTask = Task { [self] in
      do {
        try await Task.sleep(nanoseconds: timeoutNanoseconds)
        finish(.failure(TestFailure.timeout))
      } catch {
        // Cancellation means the other task won the race.
      }
    }
    install(timeoutTask, asOperation: false)
  }

  func cancel() {
    finish(.failure(CancellationError()))
  }

  private func install(
    _ task: Task<Void, Never>,
    asOperation: Bool
  ) {
    let cancel: Bool
    lock.lock()
    if finished {
      cancel = true
    } else {
      if asOperation {
        operationTask = task
      } else {
        timeoutTask = task
      }
      cancel = false
    }
    lock.unlock()
    if cancel {
      task.cancel()
    }
  }

  private func finish(_ outcome: Outcome) {
    let continuation: CheckedContinuation<T, Error>?
    let operationTask: Task<Void, Never>?
    let timeoutTask: Task<Void, Never>?
    lock.lock()
    guard !finished else {
      lock.unlock()
      return
    }
    finished = true
    continuation = self.continuation
    self.continuation = nil
    operationTask = self.operationTask
    timeoutTask = self.timeoutTask
    lock.unlock()

    operationTask?.cancel()
    timeoutTask?.cancel()
    guard let continuation else { return }
    switch outcome {
    case .success(let value): continuation.resume(returning: value)
    case .failure(let error): continuation.resume(throwing: error)
    }
  }
}

private enum GemmaProcessTestRequest {
  static func make(
    requestID: String = "cleanup-test",
    plainPrompt: String = "Return exactly one JSON object with one string member named \"text\"."
  ) -> GemmaCleanupHelperRequest {
    GemmaCleanupHelperRequest(
      schemaVersion: 1,
      operation: "cleanup",
      requestID: requestID,
      baseline: "send the report",
      plainPrompt: plainPrompt,
      maxResponseTokens: 32,
      budgetMilliseconds: 1_000
    )
  }
}

private final class GemmaHelperFixture: @unchecked Sendable {
  let root: URL
  let modelDirectory: URL
  let helperExecutableURL: URL

  init(mode: String) throws {
    let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .resolvingSymlinksInPath()
    root = temporaryDirectory
      .appendingPathComponent("fleck-gemma-process-\(UUID().uuidString)", isDirectory: true)
    modelDirectory = root.appendingPathComponent("model", isDirectory: true)
    helperExecutableURL = root.appendingPathComponent("fake-helper.sh")
    try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
    try Data(mode.utf8).write(to: modelDirectory.appendingPathComponent("mode"))
    try Data().write(to: modelDirectory.appendingPathComponent("commands.jsonl"))
    try Data().write(to: modelDirectory.appendingPathComponent("arguments.log"))
    try Data().write(to: modelDirectory.appendingPathComponent("signals.log"))
    try Data().write(to: modelDirectory.appendingPathComponent("pid"))
    try Data().write(to: modelDirectory.appendingPathComponent("stdin-closed"))
    try FileManager.default.removeItem(
      at: modelDirectory.appendingPathComponent("stdin-closed")
    )
    try Data(Self.script.utf8).write(to: helperExecutableURL)
    try FileManager.default.setAttributes(
      [.posixPermissions: NSNumber(value: Int16(0o755))],
      ofItemAtPath: helperExecutableURL.path
    )
  }

  deinit {
    try? FileManager.default.removeItem(at: root)
  }

  func makeTransport(
    useSandbox: Bool,
    timing: GemmaCleanupProcessTransport.Timing = .live
  ) -> GemmaCleanupProcessTransport {
    GemmaCleanupProcessTransport(
      helperExecutableURL: helperExecutableURL,
      modelDirectoryURL: modelDirectory,
      sandboxExecutableURL: useSandbox
        ? URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        : nil,
      timing: timing
    )
  }

  func commands() throws -> [[String: Any]] {
    try readJSONLines("commands.jsonl")
  }

  func arguments() throws -> [String] {
    String(
      decoding: try Data(contentsOf: modelDirectory.appendingPathComponent("arguments.log")),
      as: UTF8.self
    )
    .split(separator: "\n", omittingEmptySubsequences: true)
    .map(String.init)
  }

  func signalLog() throws -> String {
    String(
      decoding: try Data(contentsOf: modelDirectory.appendingPathComponent("signals.log")),
      as: UTF8.self
    )
  }

  func mark(_ name: String) {
    try? Data().write(to: modelDirectory.appendingPathComponent(name))
  }

  func markerExists(_ name: String) -> Bool {
    FileManager.default.fileExists(
      atPath: modelDirectory.appendingPathComponent(name).path
    )
  }

  func waitForMarker(_ name: String) async throws {
    let marker = modelDirectory.appendingPathComponent(name).path
    let deadline = DispatchTime.now().uptimeNanoseconds + 1_000_000_000
    while !FileManager.default.fileExists(atPath: marker) {
      guard DispatchTime.now().uptimeNanoseconds < deadline else {
        throw TestFailure.timeout
      }
      try await Task.sleep(nanoseconds: 1_000_000)
    }
  }

  func waitForMarkerSynchronously(_ name: String) -> Bool {
    let marker = modelDirectory.appendingPathComponent(name).path
    let deadline = DispatchTime.now().uptimeNanoseconds + 1_000_000_000
    while !FileManager.default.fileExists(atPath: marker) {
      guard DispatchTime.now().uptimeNanoseconds < deadline else {
        return false
      }
      usleep(1_000)
    }
    return true
  }

  func processIsAlive() throws -> Bool {
    let pidData = try Data(contentsOf: modelDirectory.appendingPathComponent("pid"))
    guard let pid = Int32(String(decoding: pidData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)),
          pid > 0
    else { return false }
    #if os(macOS)
    if kill(pid, 0) == 0 { return true }
    return errno == EPERM
    #else
    return false
    #endif
  }

  func waitForProcessExit() async throws {
    let deadline = DispatchTime.now().uptimeNanoseconds + 1_000_000_000
    while try processIsAlive() {
      guard DispatchTime.now().uptimeNanoseconds < deadline else {
        throw TestFailure.timeout
      }
      try await Task.sleep(nanoseconds: 1_000_000)
    }
  }

  func forceKillForTest() {
    guard let pidData = try? Data(contentsOf: modelDirectory.appendingPathComponent("pid")),
          let pid = Int32(String(decoding: pidData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)),
          pid > 0
    else { return }
    #if os(macOS)
    _ = kill(pid, SIGKILL)
    #endif
  }

  private func readJSONLines(_ name: String) throws -> [[String: Any]] {
    let data = try Data(contentsOf: modelDirectory.appendingPathComponent(name))
    return try data.split(separator: 0x0A).map {
      guard let object = try JSONSerialization.jsonObject(with: Data($0)) as? [String: Any] else {
        throw TestFailure.unexpectedEOF
      }
      return object
    }
  }

  private static let script = #"""
#!/bin/sh
set -eu

if [ "$#" -ne 2 ] || [ "$1" != "--model-directory" ]; then
  exit 64
fi

model_directory="$2"
mode=$(cat "$model_directory/mode")
printf '%s\n' "$1" "$2" > "$model_directory/arguments.log"
commands="$model_directory/commands.jsonl"
signals="$model_directory/signals.log"

printf '%s\n' "$$" > "$model_directory/pid"

if [ "$mode" = "startup-close-stdin" ]; then
  trap '' TERM
  exec 0<&-
  /usr/bin/printf '%s\n' '{"schemaVersion":1,"kind":"ready"}'
  /usr/bin/printf '%s\n' 'startup-stderr' >&2
  : > "$model_directory/stdin-closed"
  while :; do :; done
fi

if [ "$mode" = "delayed-read" ]; then
  trap '' TERM
  /usr/bin/printf '%s\n' '{"schemaVersion":1,"kind":"ready"}'
  /usr/bin/printf '%s\n' 'delayed-stderr' >&2
  : > "$model_directory/stdin-delayed"
  /bin/sleep 0.35
fi

if [ "$mode" = "blocked-write" ]; then
  trap '' TERM
  /usr/bin/printf '%s\n' '{"schemaVersion":1,"kind":"ready"}'
  /usr/bin/printf '%s\n' 'blocked-write-stderr' >&2
  : > "$model_directory/blocked-write-ready"
  while :; do :; done
fi

emit_started() {
  /usr/bin/printf '%s\n' '{"schemaVersion":1,"kind":"started","requestID":"'"$1"'"}'
}

emit_completed() {
  /usr/bin/printf '%s\n' '{"schemaVersion":1,"kind":"completed","requestID":"'"$1"'","rawText":"{\"text\":\"cleaned\"}"}'
}

emit_cancelled() {
  /usr/bin/printf '%s\n' '{"schemaVersion":1,"kind":"cancelled","requestID":"'"$1"'","errorCode":"cancelled","cooperative":true,"processTerminationMayBeRequired":false}'
}

emit_cancel_ack() {
  /usr/bin/printf '%s\n' '{"schemaVersion":1,"kind":"cancel-acknowledged","requestID":"'"$1"'","targetRequestID":"'"$2"'","cooperative":true,"processTerminationMayBeRequired":false}'
}

emit_shutdown_ack() {
  /usr/bin/printf '%s\n' '{"schemaVersion":1,"kind":"shutdown-acknowledged","requestID":"'"$1"'","cooperative":true,"processTerminationMayBeRequired":false}'
}

if [ "$mode" = "premature-shutdown-ack" ]; then
  /usr/bin/printf '%s\n' '{"schemaVersion":1,"kind":"ready"}'
  emit_started "cleanup-test"
  emit_completed "cleanup-test"
  emit_shutdown_ack "shutdown-cleanup-test"
  : > "$model_directory/premature-shutdown-ack"
  exit 0
fi

if [ "$mode" = "premature-cancellation-ack" ]; then
  /usr/bin/printf '%s\n' '{"schemaVersion":1,"kind":"ready"}'
  emit_started "cleanup-test"
  emit_completed "cleanup-test"
  emit_cancel_ack "cancel-cleanup-test" "cleanup-test"
  emit_shutdown_ack "shutdown-cleanup-test"
  : > "$model_directory/premature-cancellation-ack"
  exit 0
fi

if [ "$mode" = "ignore-term" ]; then
  trap 'printf TERM >> "$signals"; trap "" TERM; while :; do :; done' TERM
fi

/usr/bin/printf '%s\n' '{"schemaVersion":1,"kind":"ready"}'

while IFS= read -r line; do
  printf '%s\n' "$line" >> "$commands"
  request_id=$(printf '%s\n' "$line" | sed -n 's/.*"requestID":"\([^\"]*\)".*/\1/p')
  target_id=$(printf '%s\n' "$line" | sed -n 's/.*"targetRequestID":"\([^\"]*\)".*/\1/p')

  if printf '%s' "$line" | grep -q '"operation":"cleanup"'; then
    emit_started "$request_id"
    case "$mode" in
      normal|exit-before-command) emit_completed "$request_id"; [ "$mode" = "exit-before-command" ] && exit 0 ;;
      cancel|foreign-control|noncooperative|stall|ignore-term) : ;;
      close-stdin) exec 0<&-; : > "$model_directory/stdin-closed"; while :; do :; done ;;
      duplicate) /usr/bin/printf '%s\n' '{"schemaVersion":1,"kind":"completed","requestID":"'"$request_id"'","requestID":"'"$request_id"'","rawText":"{\"text\":\"bad\"}"}' ;;
      extra) /usr/bin/printf '%s\n' '{"schemaVersion":1,"kind":"completed","requestID":"'"$request_id"'","rawText":"{\"text\":\"bad\"}","extra":true}' ;;
      oversized)
        printf '%s' '{"schemaVersion":1,"kind":"completed","requestID":"'"$request_id"'","rawText":"'
        i=0
        while [ "$i" -lt 66000 ]; do printf x; i=$((i + 1)); done
        printf '%s\n' '"}'
        ;;
      truncated) /usr/bin/printf '%s' '{"schemaVersion":1,"kind":"completed"'; exit 0 ;;
      late) emit_completed "$request_id" ;;
      foreign-control|noncooperative) : ;;
      stderr-large)
        i=0
        while [ "$i" -lt 66000 ]; do printf x >&2; i=$((i + 1)); done
        emit_completed "$request_id"
        ;;
      early-exit) exit 7 ;;
    esac
  elif printf '%s' "$line" | grep -q '"operation":"cancel"'; then
    case "$mode" in
      cancel) emit_cancelled "$target_id"; emit_cancel_ack "$request_id" "$target_id" ;;
      foreign-control)
        emit_cancelled "$target_id"
        /usr/bin/printf '%s\n' '{"schemaVersion":1,"kind":"cancel-acknowledged","requestID":"foreign","targetRequestID":"'"$target_id"'","cooperative":true,"processTerminationMayBeRequired":false}'
        ;;
      noncooperative)
        /usr/bin/printf '%s\n' '{"schemaVersion":1,"kind":"cancelled","requestID":"'"$target_id"'","errorCode":"cancelled","cooperative":true,"processTerminationMayBeRequired":true}'
        ;;
      *) : ;;
    esac
  elif printf '%s' "$line" | grep -q '"operation":"shutdown"'; then
    case "$mode" in
      normal|cancel|foreign-control|noncooperative|exit-before-command|stderr-large) emit_shutdown_ack "$request_id"; exit 0 ;;
      late) emit_shutdown_ack "$request_id"; /usr/bin/printf '%s\n' '{"schemaVersion":1,"kind":"ready"}'; exit 0 ;;
      stall|ignore-term) while :; do :; done ;;
      *) : ;;
    esac
  fi
done

exit 0
"""#
}

private func wireKind(_ data: Data) throws -> String {
  guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        let kind = object["kind"] as? String else {
    throw TestFailure.unexpectedEOF
  }
  return kind
}

private func wireOperation(_ object: [String: Any]) throws -> String {
  guard let operation = object["operation"] as? String else {
    throw TestFailure.unexpectedEOF
  }
  return operation
}

private func wireRequestID(_ object: [String: Any]) throws -> String {
  guard let requestID = object["requestID"] as? String else {
    throw TestFailure.unexpectedEOF
  }
  return requestID
}

private func wireTargetRequestID(_ object: [String: Any]) throws -> String? {
  object["targetRequestID"] as? String
}
