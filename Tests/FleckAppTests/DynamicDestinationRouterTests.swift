import Foundation
import FleckCore
import Testing

@testable import FleckApp

@Test func dynamicDestinationRouterExactTitleMatchInvokesNeitherSemanticRouter() async {
  let inbox = dynamicCandidate(title: "Inbox", context: "General captures")
  let chemistry = dynamicCandidate(title: "Chemistry", context: "Lab reports")
  let foundation = DynamicDestinationRouterProbe(result: chemistry.destination.noteID)
  let local = DynamicDestinationRouterProbe(result: chemistry.destination.noteID)
  let router = DynamicDestinationRouter(
    foundationIsAvailable: { true },
    foundationRouter: foundation,
    localRouter: local
  )

  let destination = await router.route(
    transcript: "Save this chemistry note.",
    candidates: [inbox, chemistry],
    inboxID: inbox.destination.noteID
  )

  #expect(destination == chemistry.destination.noteID)
  #expect(await foundation.callCount == 0)
  #expect(await local.callCount == 0)
}

@Test func dynamicDestinationRouterSelectsTheLiveSemanticRouterAndPreservesContext() async {
  let availability = DynamicDestinationAvailability(false)
  let inbox = dynamicCandidate(title: "Inbox", context: "General captures")
  let project = dynamicCandidate(title: "Project Delta", context: "Launch plans and deadlines")
  let candidates = [inbox, project]
  let foundation = DynamicDestinationRouterProbe(result: project.destination.noteID)
  let local = DynamicDestinationRouterProbe(result: project.destination.noteID)
  let router = DynamicDestinationRouter(
    foundationIsAvailable: { availability.value },
    foundationRouter: foundation,
    localRouter: local
  )

  #expect(await router.route(
    transcript: "Prepare the launch checklist.",
    candidates: candidates,
    inboxID: inbox.destination.noteID
  ) == project.destination.noteID)
  #expect(await local.candidates == candidates)
  #expect(await foundation.callCount == 0)

  availability.value = true

  #expect(await router.route(
    transcript: "Review the launch schedule.",
    candidates: candidates,
    inboxID: inbox.destination.noteID
  ) == project.destination.noteID)
  #expect(await foundation.candidates == candidates)
  #expect(await local.callCount == 1)
}

@Test func dynamicDestinationRouterFoundationFailureAndMalformedResultReturnInbox() async {
  let inbox = dynamicCandidate(title: "Inbox")
  let project = dynamicCandidate(title: "Project Delta")
  let candidates = [inbox, project]
  let local = DynamicDestinationRouterProbe(result: project.destination.noteID)
  let failingFoundation = FoundationModelDictation(
    osMajorVersion: { 26 },
    cleanupGenerator: { _, _ in "unused" },
    routingGenerator: { _, _ in throw DynamicDestinationRouterTestError.failed }
  )
  let failingRouter = DynamicDestinationRouter(
    foundationIsAvailable: { true },
    foundationRouter: failingFoundation,
    localRouter: local
  )

  #expect(await failingRouter.route(
    transcript: "Prepare the launch checklist.",
    candidates: candidates,
    inboxID: inbox.destination.noteID
  ) == inbox.destination.noteID)

  let malformedFoundation = DynamicDestinationRouterProbe(result: UUID())
  let malformedRouter = DynamicDestinationRouter(
    foundationIsAvailable: { true },
    foundationRouter: malformedFoundation,
    localRouter: local
  )
  #expect(await malformedRouter.route(
    transcript: "Review the launch schedule.",
    candidates: candidates,
    inboxID: inbox.destination.noteID
  ) == inbox.destination.noteID)
  #expect(await local.callCount == 0)
}

@Test func dynamicDestinationRouterCancellationReturnsInboxAfterSelectedRouterFinishes() async {
  let inbox = dynamicCandidate(title: "Inbox")
  let project = dynamicCandidate(title: "Project Delta")
  let gate = DynamicDestinationRouterGate()
  let local = DynamicDestinationRouterBlockingProbe(
    result: project.destination.noteID,
    gate: gate
  )
  let router = DynamicDestinationRouter(
    foundationIsAvailable: { false },
    foundationRouter: DynamicDestinationRouterProbe(result: project.destination.noteID),
    localRouter: local
  )
  let task = Task {
    await router.route(
      transcript: "Prepare the launch checklist.",
      candidates: [inbox, project],
      inboxID: inbox.destination.noteID
    )
  }
  await gate.waitUntilStarted()

  task.cancel()
  await gate.release()

  #expect(await task.value == inbox.destination.noteID)
}

private func dynamicCandidate(
  title: String,
  context: String = ""
) -> DictationRoutingCandidate {
  DictationRoutingCandidate(
    destination: .init(noteID: UUID(), title: title),
    semanticContext: context
  )
}

private actor DynamicDestinationRouterProbe: DestinationRouting {
  let result: UUID?
  private(set) var callCount = 0
  private(set) var candidates: [DictationRoutingCandidate] = []

  init(result: UUID?) {
    self.result = result
  }

  func route(
    transcript _: String,
    candidates: [DictationRoutingCandidate],
    inboxID _: UUID?
  ) async -> UUID? {
    callCount += 1
    self.candidates = candidates
    return result
  }
}

private struct DynamicDestinationRouterBlockingProbe: DestinationRouting {
  let result: UUID?
  let gate: DynamicDestinationRouterGate

  func route(
    transcript _: String,
    candidates _: [DictationRoutingCandidate],
    inboxID _: UUID?
  ) async -> UUID? {
    await gate.wait()
    return result
  }
}

private actor DynamicDestinationRouterGate {
  private var started = false
  private var continuation: CheckedContinuation<Void, Never>?

  func wait() async {
    started = true
    await withCheckedContinuation { continuation = $0 }
  }

  func waitUntilStarted() async {
    while !started { await Task.yield() }
  }

  func release() {
    continuation?.resume()
    continuation = nil
  }
}

private final class DynamicDestinationAvailability: @unchecked Sendable {
  var value: Bool

  init(_ value: Bool) {
    self.value = value
  }
}

private enum DynamicDestinationRouterTestError: Error {
  case failed
}
