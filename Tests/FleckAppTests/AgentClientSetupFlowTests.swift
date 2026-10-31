import Foundation
import Testing

@testable import FleckApp

@Suite("CursorSetupFlow")
struct AgentClientSetupFlowTests {
  @Test @MainActor
  func createsOnlyWhenNoCursorProfileExistsAndReportsRequestSent() async throws {
    let harness = CursorSetupFlowHarness()
    let flow = harness.makeFlow()
    var validatedNewProfile = false

    await flow.setUp(validateProfile: { profile, isNewProfile in
      validatedNewProfile = isNewProfile && profile.id == harness.createdProfile.id
      return validatedNewProfile
    })

    #expect(flow.status == .requestSent)
    #expect(harness.profileLoadCount == 1)
    #expect(harness.prepareCount == 1)
    #expect(harness.installCount == 1)
    #expect(harness.createCount == 1)
    try #require(harness.openedURLs.count == 1)
    #expect(harness.statusChanges.contains(.profileReady))
    #expect(validatedNewProfile)
    #expect(harness.activeProfiles == [harness.createdProfile])
    #expect(try profileID(in: harness.openedURLs[0]) == harness.createdProfile.id)
  }

  @Test @MainActor
  func existingUniqueCursorProfileRequiresExplicitSelection() async throws {
    let harness = CursorSetupFlowHarness()
    let existingProfile = cursorProfile()
    harness.activeProfiles = [existingProfile]
    harness.helperAlreadyInstalled = true
    let flow = harness.makeFlow()

    await flow.setUp(validateProfile: { _, _ in true })

    #expect(flow.status == .profileSelectionRequired)
    #expect(flow.status.message?.contains("current scope") == true)
    #expect(harness.prepareCount == 0)
    #expect(harness.createCount == 0)
    #expect(harness.openedURLs.isEmpty)

    await flow.setUp(profileID: existingProfile.id, validateProfile: { profile, isNewProfile in
      profile.id == existingProfile.id && !isNewProfile
    })

    #expect(flow.status == .requestSent)
    #expect(harness.prepareCount == 1)
    #expect(harness.installCount == 0)
    #expect(harness.createCount == 0)
    try #require(harness.openedURLs.count == 1)
    #expect(try profileID(in: harness.openedURLs[0]) == existingProfile.id)
  }

  @Test @MainActor
  func multipleCursorProfilesNeverChooseOneAutomatically() async {
    let harness = CursorSetupFlowHarness()
    harness.activeProfiles = [cursorProfile(), cursorProfile()]
    let flow = harness.makeFlow()

    await flow.setUp(validateProfile: { _, _ in true })

    #expect(flow.status == .profileSelectionRequired)
    #expect(harness.prepareCount == 0)
    #expect(harness.createCount == 0)
    #expect(harness.openedURLs.isEmpty)
  }

  @Test @MainActor
  func concurrentTriggersShareOneInFlightSetup() async {
    let harness = CursorSetupFlowHarness()
    let flow = harness.makeFlow()
    let (loadStarted, loadStartedSignal) = AsyncStream<Void>.makeStream()
    var loadStartedIterator = loadStarted.makeAsyncIterator()
    var loadContinuation: CheckedContinuation<[AgentIntegrationProfile], Never>?
    harness.loadOperation = {
      loadStartedSignal.yield(())
      return await withCheckedContinuation { loadContinuation = $0 }
    }
    let firstSetup = Task {
      await flow.setUp(validateProfile: { _, _ in true })
    }

    _ = await loadStartedIterator.next()
    #expect(flow.isInFlight)
    await flow.setUp(validateProfile: { _, _ in true })
    #expect(harness.profileLoadCount == 1)
    #expect(harness.createCount == 0)

    loadStartedSignal.finish()
    loadContinuation?.resume(returning: [])
    await firstSetup.value

    #expect(flow.status == .requestSent)
    #expect(harness.createCount == 1)
    #expect(harness.openedURLs.count == 1)
  }

  @Test @MainActor
  func foreignMissingAndRevokedProfileIDsAreRejectedBeforePreparation() async {
    let harness = CursorSetupFlowHarness()
    let foreignProfile = cursorProfile(name: "Codex")
    let capyProfile = cursorProfile(name: "Capy")
    let revokedProfile = cursorProfile(revokedAt: Date())
    harness.activeProfiles = [foreignProfile, capyProfile, revokedProfile]
    let flow = harness.makeFlow()

    await flow.setUp(profileID: foreignProfile.id, validateProfile: { _, _ in true })
    #expect(flow.status == .profileUnavailable)
    await flow.setUp(profileID: capyProfile.id, validateProfile: { _, _ in true })
    #expect(flow.status == .profileUnavailable)
    await flow.setUp(profileID: revokedProfile.id, validateProfile: { _, _ in true })
    #expect(flow.status == .profileUnavailable)
    await flow.setUp(profileID: UUID(), validateProfile: { _, _ in true })
    #expect(flow.status == .profileUnavailable)

    #expect(harness.prepareCount == 0)
    #expect(harness.createCount == 0)
    #expect(harness.openedURLs.isEmpty)
  }

  @Test @MainActor
  func changedScopeAtHandoffFailsClosed() async {
    let harness = CursorSetupFlowHarness()
    let existingProfile = cursorProfile()
    harness.activeProfiles = [existingProfile]
    let flow = harness.makeFlow()

    await flow.setUp(profileID: existingProfile.id, validateProfile: { _, _ in false })

    #expect(flow.status == .profileScopeChanged)
    #expect(harness.prepareCount == 1)
    #expect(harness.openedURLs.isEmpty)
  }

  @Test @MainActor
  func disappearingSelectedProfileIsNotReplacedWithAnotherCursorProfile() async {
    let harness = CursorSetupFlowHarness()
    let selectedProfile = cursorProfile()
    let otherProfile = cursorProfile()
    harness.activeProfiles = [selectedProfile, otherProfile]
    harness.prepareOperation = {
      harness.activeProfiles = [otherProfile]
      return harness.helperURL
    }
    let flow = harness.makeFlow()

    await flow.setUp(profileID: selectedProfile.id, validateProfile: { profile, _ in
      harness.activeProfiles.contains(where: { $0.id == profile.id })
    })

    #expect(flow.status == .profileScopeChanged)
    #expect(harness.openedURLs.isEmpty)
    #expect(harness.activeProfiles == [otherProfile])
  }

  @Test @MainActor
  func dependencyFailuresUseFixedStatusAndNeverOpenCursor() async {
    let connectorFailure = CursorSetupFlowHarness()
    connectorFailure.prepareFails = true
    let connectorFlow = connectorFailure.makeFlow()
    await connectorFlow.setUp(validateProfile: { _, _ in true })
    #expect(connectorFlow.status == .failure)
    #expect(connectorFlow.status.message?.contains("private") == false)
    #expect(connectorFailure.createCount == 0)
    #expect(connectorFailure.openedURLs.isEmpty)

    let loadFailure = CursorSetupFlowHarness()
    loadFailure.loadFails = true
    let loadFlow = loadFailure.makeFlow()
    await loadFlow.setUp(validateProfile: { _, _ in true })
    #expect(loadFlow.status == .failure)
    #expect(loadFailure.prepareCount == 0)
    #expect(loadFailure.openedURLs.isEmpty)

    let createFailure = CursorSetupFlowHarness()
    createFailure.createFails = true
    let createFlow = createFailure.makeFlow()
    await createFlow.setUp(validateProfile: { _, _ in true })
    #expect(createFlow.status == .failure)
    #expect(createFailure.prepareCount == 1)
    #expect(createFailure.openedURLs.isEmpty)
  }

  @Test @MainActor
  func cancellationBeforeOpenDoesNotCreateOrOpen() async {
    let harness = CursorSetupFlowHarness()
    let existingProfile = cursorProfile()
    harness.activeProfiles = [existingProfile]
    var setupTask: Task<Void, Never>?
    harness.prepareOperation = {
      setupTask?.cancel()
      return harness.helperURL
    }
    let flow = harness.makeFlow()
    setupTask = Task {
      await flow.setUp(
        profileID: existingProfile.id,
        validateProfile: { _, _ in true }
      )
    }

    await setupTask?.value

    #expect(flow.status == .cancelled)
    #expect(harness.createCount == 0)
    #expect(harness.openedURLs.isEmpty)
  }

  @Test @MainActor
  func cancellationAfterCreationKeepsProfileAndRetryDoesNotDuplicate() async {
    let harness = CursorSetupFlowHarness()
    var setupTask: Task<Void, Never>?
    harness.createOperation = {
      harness.activeProfiles.append(harness.createdProfile)
      setupTask?.cancel()
      return harness.createdProfile
    }
    let flow = harness.makeFlow()
    setupTask = Task {
      await flow.setUp(validateProfile: { _, _ in true })
    }

    await setupTask?.value

    #expect(flow.status == .cancelled)
    #expect(harness.activeProfiles == [harness.createdProfile])
    #expect(harness.openedURLs.isEmpty)

    await flow.setUp(validateProfile: { _, _ in true })

    #expect(flow.status == .profileSelectionRequired)
    #expect(harness.createCount == 1)
    #expect(harness.openedURLs.isEmpty)
  }

  @Test @MainActor
  func failedOSOpenUsesManualFallback() async {
    let harness = CursorSetupFlowHarness()
    harness.openResult = false
    let flow = harness.makeFlow()

    await flow.setUp(validateProfile: { _, _ in true })

    #expect(flow.status == .manualFallback)
    #expect(flow.status.message?.contains("manual setup below") == true)
    #expect(harness.activeProfiles == [harness.createdProfile])
    #expect(harness.openedURLs.count == 1)
  }

  @Test @MainActor
  func openRequestDoesNotClaimConnectionAndCanBeRetriedOnSelectedProfile() async throws {
    let harness = CursorSetupFlowHarness()
    let existingProfile = cursorProfile()
    harness.activeProfiles = [existingProfile]
    let flow = harness.makeFlow()

    await flow.setUp(profileID: existingProfile.id, validateProfile: { _, _ in true })
    #expect(flow.status == .requestSent)
    #expect(flow.status.message?.contains("cannot verify acceptance or connection") == true)
    #expect(harness.activeProfiles[0].lastConnectedAt == nil)

    await flow.setUp(profileID: existingProfile.id, validateProfile: { _, _ in true })

    #expect(flow.status == .requestSent)
    try #require(harness.openedURLs.count == 2)
    #expect(try profileID(in: harness.openedURLs[0]) == existingProfile.id)
    #expect(try profileID(in: harness.openedURLs[1]) == existingProfile.id)
    #expect(harness.activeProfiles[0].lastConnectedAt == nil)
  }

  @Test @MainActor
  func unavailableAndUnacceptedPromptRetriesReuseHelperAndProfile() async throws {
    let harness = CursorSetupFlowHarness()
    harness.openResult = false
    let flow = harness.makeFlow()

    await flow.setUp(validateProfile: { _, isNew in isNew })
    #expect(flow.status == .manualFallback)
    #expect(harness.activeProfiles == [harness.createdProfile])
    try #require(harness.activeProfiles.count == 1)

    await flow.setUp(validateProfile: { _, _ in true })
    #expect(flow.status == .profileSelectionRequired)

    harness.openResult = true
    for _ in 0..<2 {
      await flow.setUp(profileID: harness.createdProfile.id) { profile, isNew in
        profile.id == harness.createdProfile.id && !isNew
      }
      #expect(flow.status == .requestSent)
      #expect(harness.activeProfiles[0].lastConnectedAt == nil)
    }

    #expect(harness.installCount == 1)
    #expect(harness.createCount == 1)
    #expect(harness.openedURLs.count == 3)
    #expect(Set(harness.openedURLs).count == 1)
    #expect(harness.activeProfiles == [harness.createdProfile])
  }

  @Test
  func cursorSetupStartsOnlyFromExplicitButtons() throws {
    let testFile = URL(fileURLWithPath: #filePath)
    let sourceRoot = testFile.deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sources/FleckApp")
    let settings = try String(
      contentsOf: sourceRoot.appendingPathComponent("AgentSettingsView.swift"),
      encoding: .utf8
    )
    let appState = try String(
      contentsOf: sourceRoot.appendingPathComponent("AppState.swift"),
      encoding: .utf8
    )
    let cancelStart = try #require(settings.range(of: "private func cancelCursorSetup()"))
    let cancelTail = settings[cancelStart.lowerBound...]
    let cancelEnd = try #require(cancelTail.range(of: "private func integrationRow"))
    let cancelMethod = String(cancelTail[..<cancelEnd.lowerBound])
    let prepareStart = try #require(appState.range(of: "private func prepareCursorHelper()"))
    let prepareTail = appState[prepareStart.lowerBound...]
    let prepareEnd = try #require(prepareTail.range(of: "func cursorManualConfiguration("))
    let prepareMethod = String(prepareTail[..<prepareEnd.lowerBound])
    let cursorSetupStart = try #require(appState.range(of: "func setUpCursor("))
    let cursorSetupTail = appState[cursorSetupStart.lowerBound...]
    let cursorSetupEnd = try #require(
      cursorSetupTail.range(of: "private func prepareCursorHelper()")
    )
    let cursorSetupMethod = String(cursorSetupTail[..<cursorSetupEnd.lowerBound])
    let manualConfigurationStart = try #require(
      appState.range(of: "func cursorManualConfiguration(profileID: UUID)")
    )
    let manualConfigurationTail = appState[manualConfigurationStart.lowerBound...]
    let manualConfigurationEnd = try #require(
      manualConfigurationTail.range(of: "@discardableResult")
    )
    let manualConfigurationMethod = String(
      manualConfigurationTail[..<manualConfigurationEnd.lowerBound]
    )

    #expect(settings.contains("Button(\"Set up in Cursor…\")"))
    #expect(settings.contains("Button(\"Open in Cursor…\")"))
    #expect(settings.contains("Button(\"Copy Cursor JSON\")"))
    #expect(settings.contains("preserve unrelated entries"))
    #expect(settings.contains("appState.setUpCursor("))
    #expect(settings.components(separatedBy: "appState.setUpCursor(").count == 2)
    #expect(!settings.contains(".onAppear { await appState.setUpCursor"))
    #expect(settings.contains("new profiles start with no access"))
    #expect(cancelMethod.contains("cursorSetupTask?.cancel()"))
    #expect(!cancelMethod.contains("cursorSetupTask = nil"))
    #expect(settings.contains("cursorSetupTask = nil"))
    #expect(prepareMethod.contains("await refreshAgentConnectorStatus()"))
    #expect(prepareMethod.contains("await installAgentBridge()"))
    #expect(prepareMethod.contains("AgentBridgeInstaller.live().installedHelperURL"))
    #expect(!prepareMethod.contains("verifiedInstalledHelperURL()"))
    #expect(appState.contains("guard isAgentWorkspaceAvailable else"))
    #expect(cursorSetupMethod.contains("self.isAgentWorkspaceAvailable"))
    #expect(appState.contains("guard await refreshAgentProfiles() else { return nil }"))
    #expect(manualConfigurationMethod.contains("isAgentWorkspaceAvailable"))
    #expect(manualConfigurationMethod.contains("$0.id == profileID"))
    #expect(manualConfigurationMethod.contains("$0.displayName == \"Cursor\""))
    #expect(manualConfigurationMethod.contains("capabilityProfile(profileID) != nil"))
    #expect(settings.contains("if profile.displayName != \"Cursor\""))
  }
}

@MainActor
private final class CursorSetupFlowHarness {
  private enum Failure: Error {
    case injected
  }

  var activeProfiles: [AgentIntegrationProfile] = []
  var createdProfile = cursorProfile()
  let helperURL = URL(fileURLWithPath: "/tmp/Fleck Test/fleck")
  var prepareFails = false
  var loadFails = false
  var createFails = false
  var openResult = true
  var helperAlreadyInstalled = false
  var prepareCount = 0
  var installCount = 0
  var profileLoadCount = 0
  var createCount = 0
  var openedURLs: [URL] = []
  var statusChanges: [CursorSetupStatus] = []
  var prepareOperation: (@MainActor () async throws -> URL)?
  var loadOperation: (@MainActor () async throws -> [AgentIntegrationProfile])?
  var createOperation: (@MainActor () async throws -> AgentIntegrationProfile)?

  func makeFlow() -> CursorSetupFlow {
    CursorSetupFlow(
      prepareConnector: { [unowned self] in
        prepareCount += 1
        if let prepareOperation {
          return try await prepareOperation()
        }
        if prepareFails { throw Failure.injected }
        if !helperAlreadyInstalled {
          installCount += 1
          helperAlreadyInstalled = true
        }
        return helperURL
      },
      loadActiveProfiles: { [unowned self] in
        profileLoadCount += 1
        if let loadOperation {
          return try await loadOperation()
        }
        if loadFails { throw Failure.injected }
        return activeProfiles
      },
      createProfile: { [unowned self] in
        createCount += 1
        if let createOperation {
          return try await createOperation()
        }
        if createFails { throw Failure.injected }
        activeProfiles.append(createdProfile)
        return createdProfile
      },
      openURL: { [unowned self] url in
        openedURLs.append(url)
        return openResult
      },
      statusChanged: { [unowned self] status in
        statusChanges.append(status)
      }
    )
  }
}

private func cursorProfile(
  name: String = "Cursor",
  id: UUID = UUID(),
  revokedAt: Date? = nil,
  lastConnectedAt: Date? = nil
) -> AgentIntegrationProfile {
  AgentIntegrationProfile(
    id: id,
    displayName: name,
    createdAt: Date(timeIntervalSince1970: 1),
    lastConnectedAt: lastConnectedAt,
    revokedAt: revokedAt
  )
}

private func profileID(in installURL: URL) throws -> UUID {
  let components = try #require(
    URLComponents(url: installURL, resolvingAgainstBaseURL: false)
  )
  let configurationValue = try #require(
    components.queryItems?.first(where: { $0.name == "config" })?.value
  )
  let data = try #require(Data(base64Encoded: configurationValue))
  let configuration = try #require(
    JSONSerialization.jsonObject(with: data) as? [String: Any]
  )
  let arguments = try #require(configuration["args"] as? [String])
  #expect(arguments.count == 3)
  let identifier = try #require(arguments.dropFirst(2).first)
  return try #require(UUID(uuidString: identifier))
}
