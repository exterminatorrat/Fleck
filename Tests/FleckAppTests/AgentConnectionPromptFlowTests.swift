import Foundation
import Testing

@testable import FleckApp

@Suite("AgentConnectionPromptFlow")
struct AgentConnectionPromptFlowTests {
  @Test @MainActor
  func preparesConnectorAndValidatesNewProfileBeforeReturningPrompt() async throws {
    let harness = PromptFlowHarness()
    let flow = harness.makeFlow()
    var validatedNewProfile = false
    let prompt = await flow.prepare(for: .codex) { profile, isNew in
      validatedNewProfile = isNew && profile == harness.newProfile
      return validatedNewProfile
    }
    #expect(prompt?.contains(harness.newProfile.id.uuidString) == true)
    #expect(harness.operations == ["load", "prepare", "load", "create"])
    #expect(validatedNewProfile)
    #expect(flow.status == .ready)
    #expect(!flow.isInFlight)
  }

  @Test @MainActor
  func existingProfilesRequireExplicitScopeReviewWithoutCreatingDuplicates() async {
    let harness = PromptFlowHarness()
    harness.profiles = [harness.newProfile, harness.profile()]
    let flow = harness.makeFlow()
    let prompt = await flow.prepare(for: .codex) { _, _ in true }
    #expect(prompt == nil)
    #expect(flow.status == .selectProfile)
    #expect(harness.operations == ["load"])
  }

  @Test @MainActor
  func selectedProfileIsReusedWithoutChangingItsGrants() async {
    let harness = PromptFlowHarness()
    harness.profiles = [harness.newProfile]
    let flow = harness.makeFlow()
    var validatedExistingProfile = false
    let prompt = await flow.prepare(for: .codex, profileID: harness.newProfile.id) { profile, isNew in
      validatedExistingProfile = !isNew && profile == harness.newProfile
      return validatedExistingProfile
    }
    #expect(prompt != nil)
    #expect(validatedExistingProfile)
    #expect(harness.operations == ["load", "prepare"])
  }

  @Test @MainActor
  func revokedForeignAndMissingProfilesCannotProducePrompts() async {
    let harness = PromptFlowHarness()
    let revoked = harness.profile(revoked: true)
    let foreign = harness.profile(name: "Claude Code")
    harness.profiles = [revoked, foreign]
    let flow = harness.makeFlow()
    for id in [revoked.id, foreign.id, UUID()] {
      let prompt = await flow.prepare(for: .codex, profileID: id) { _, _ in true }
      #expect(prompt == nil)
      #expect(flow.status == .unavailable)
    }
    #expect(harness.operations == ["load", "load", "load"])
  }

  @Test @MainActor
  func changedScopeCannotProducePrompt() async {
    let harness = PromptFlowHarness()
    let flow = harness.makeFlow()
    let prompt = await flow.prepare(for: .codex) { _, _ in false }
    #expect(prompt == nil)
    #expect(flow.status == .scopeChanged)
  }

  @Test @MainActor
  func concurrentRequestsDoNotPrepareOrCreateTwice() async {
    let harness = PromptFlowHarness()
    let (started, signal) = AsyncStream<Void>.makeStream()
    var iterator = started.makeAsyncIterator()
    var continuation: CheckedContinuation<Void, Never>?
    harness.prepareOperation = {
      signal.yield(())
      await withCheckedContinuation { continuation = $0 }
    }
    let flow = harness.makeFlow()
    let first = Task { await flow.prepare(for: .codex) { _, _ in true } }
    _ = await iterator.next()
    let second = await flow.prepare(for: .claudeCode) { _, _ in true }
    #expect(second == nil)
    #expect(flow.isInFlight)
    continuation?.resume()
    signal.finish()
    #expect(await first.value != nil)
    #expect(harness.operations == ["load", "prepare", "load", "create"])
  }

  @Test @MainActor
  func manualCreationDuringHelperPreparationDoesNotCreateAnotherProfile() async {
    let harness = PromptFlowHarness()
    harness.prepareOperation = {
      harness.profiles.append(harness.newProfile)
    }
    let flow = harness.makeFlow()
    let prompt = await flow.prepare(for: .codex) { _, _ in true }
    #expect(prompt == nil)
    #expect(flow.status == .selectProfile)
    #expect(harness.operations == ["load", "prepare", "load"])
    #expect(harness.profiles.count == 1)
  }

  @Test @MainActor
  func cancellationDuringHelperPreparationDoesNotCreateProfile() async {
    let harness = PromptFlowHarness()
    let (started, signal) = AsyncStream<Void>.makeStream()
    var iterator = started.makeAsyncIterator()
    var continuation: CheckedContinuation<Void, Never>?
    harness.prepareOperation = {
      signal.yield(())
      await withCheckedContinuation { continuation = $0 }
    }
    let flow = harness.makeFlow()
    let task = Task { await flow.prepare(for: .codex) { _, _ in true } }
    _ = await iterator.next()
    task.cancel()
    continuation?.resume()
    signal.finish()
    #expect(await task.value == nil)
    #expect(flow.status == .cancelled)
    #expect(harness.operations == ["load", "prepare"])
  }

  @Test @MainActor
  func helperFailureDoesNotCreateProfileAndFailureTextIsSanitized() async {
    let harness = PromptFlowHarness()
    harness.prepareOperation = { throw PromptFlowFailure.unavailable }
    let flow = harness.makeFlow()
    let prompt = await flow.prepare(for: .codex) { _, _ in true }
    #expect(prompt == nil)
    #expect(flow.status == .failure)
    #expect(harness.operations == ["load", "prepare"])
    #expect(flow.status.message?.contains("private") == false)
  }

  @Test @MainActor
  func rejectsUnexpectedProfileReturnedByCreation() async {
    let harness = PromptFlowHarness()
    harness.newProfile = harness.profile(name: "Generic CLI")
    let flow = harness.makeFlow()
    let prompt = await flow.prepare(for: .codex) { _, _ in true }
    #expect(prompt == nil)
    #expect(flow.status == .unavailable)
  }
}

private enum PromptFlowFailure: Error {
  case unavailable
}

@MainActor
private final class PromptFlowHarness {
  var profiles: [AgentIntegrationProfile] = []
  var newProfile = AgentIntegrationProfile(
    id: UUID(), displayName: "Codex", createdAt: Date(), lastConnectedAt: nil, revokedAt: nil
  )
  var operations: [String] = []
  var prepareOperation: (() async throws -> Void)?

  func profile(name: String = "Codex", revoked: Bool = false) -> AgentIntegrationProfile {
    AgentIntegrationProfile(
      id: UUID(), displayName: name, createdAt: Date(), lastConnectedAt: nil,
      revokedAt: revoked ? Date() : nil
    )
  }

  func makeFlow() -> AgentConnectionPromptFlow {
    AgentConnectionPromptFlow(
      prepareConnector: {
        self.operations.append("prepare")
        try await self.prepareOperation?()
        return URL(fileURLWithPath: "/Applications/Fleck/connector")
      },
      loadProfiles: {
        self.operations.append("load")
        return self.profiles
      },
      createProfile: { _ in
        self.operations.append("create")
        self.profiles.append(self.newProfile)
        return self.newProfile
      }
    )
  }
}
