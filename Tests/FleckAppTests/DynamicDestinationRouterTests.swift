import Foundation
import FleckCore
import Testing

@testable import FleckApp

@Test func dynamicDestinationRouterValidatesAmbiguousPayload() async {
  let inbox = dynamicCandidate(title: "Inbox")
  let alpha = dynamicCandidate(title: "Alpha", context: "alpha context")
  let beta = dynamicCandidate(title: "Beta", context: "beta context")
  let valid: DictationRoutingDecision = .ambiguous([
    .init(destination: alpha.destination, contextHint: "alpha context"),
    .init(destination: beta.destination, contextHint: "beta context"),
  ])
  let router = DynamicDestinationRouter(
    foundationIsAvailable: { false },
    foundationRouter: DynamicDestinationRouterProbe(result: .inbox),
    localRouter: DynamicDestinationRouterProbe(result: valid)
  )

  #expect(await router.route(
    transcript: "Choose a destination",
    candidates: [inbox, alpha, beta],
    inboxID: inbox.destination.noteID
  ) == valid)

  let malformed = DynamicDestinationRouter(
    foundationIsAvailable: { false },
    foundationRouter: DynamicDestinationRouterProbe(result: .inbox),
    localRouter: DynamicDestinationRouterProbe(result: .ambiguous([
      .init(destination: alpha.destination, contextHint: "alpha context"),
      .init(destination: alpha.destination, contextHint: "duplicate"),
    ]))
  )
  #expect(await malformed.route(
    transcript: "Choose a destination",
    candidates: [inbox, alpha, beta],
    inboxID: inbox.destination.noteID
  ) == .inbox)

  for invalid in [
    DictationRoutingDecision.ambiguous([
      .init(destination: inbox.destination, contextHint: "inbox"),
      .init(destination: beta.destination, contextHint: "beta"),
    ]),
    .ambiguous([
      .init(destination: alpha.destination, contextHint: String(repeating: "x", count: 161)),
      .init(destination: beta.destination, contextHint: "beta"),
    ]),
  ] {
    let invalidRouter = DynamicDestinationRouter(
      foundationIsAvailable: { false },
      foundationRouter: DynamicDestinationRouterProbe(result: .inbox),
      localRouter: DynamicDestinationRouterProbe(result: invalid)
    )
    #expect(await invalidRouter.route(
      transcript: "Choose a destination",
      candidates: [inbox, alpha, beta],
      inboxID: inbox.destination.noteID
    ) == .inbox)
  }
}

@Test func dynamicDestinationRouterAcceptsSingleBoundedAmbiguity() async {
  let inbox = dynamicCandidate(title: "Inbox")
  let alpha = dynamicCandidate(title: "Alpha", context: "alpha context")
  let decision: DictationRoutingDecision = .ambiguous([
    .init(destination: alpha.destination, contextHint: "alpha context"),
  ])
  let router = DynamicDestinationRouter(
    foundationIsAvailable: { false },
    foundationRouter: DynamicDestinationRouterProbe(result: .inbox),
    localRouter: DynamicDestinationRouterProbe(result: decision)
  )

  #expect(await router.route(
    transcript: "Choose a destination",
    candidates: [inbox, alpha],
    inboxID: inbox.destination.noteID
  ) == decision)
}

@Test func dynamicDestinationRouterDoesNotSuggestFromNonleadingPhoneticPlural() async {
  let inbox = dynamicCandidate(title: "Inbox")
  let fleck = dynamicCandidate(title: "Fleck")
  let local = DynamicDestinationRouterProbe(result: .inbox)
  let router = DynamicDestinationRouter(
    foundationIsAvailable: { false },
    foundationRouter: DynamicDestinationRouterProbe(result: .inbox),
    localRouter: local
  )

  #expect(await router.route(
    transcript: "I noticed flags in the settings UI",
    candidates: [inbox, fleck],
    inboxID: inbox.destination.noteID
  ) == .inbox)
  #expect(await local.callCount == 1)
}

@Test func dynamicDestinationRouterDoesNotSuggestPhoneticTitleWithDifferentPrefix() async {
  let inbox = dynamicCandidate(title: "Inbox")
  let fleck = dynamicCandidate(title: "Fleck")
  let local = DynamicDestinationRouterProbe(result: .inbox)
  let router = DynamicDestinationRouter(
    foundationIsAvailable: { false },
    foundationRouter: DynamicDestinationRouterProbe(result: .inbox),
    localRouter: local
  )

  #expect(await router.route(
    transcript: "For black I feel like we need to work on the settings UI",
    candidates: [inbox, fleck],
    inboxID: inbox.destination.noteID
  ) == .inbox)
  #expect(await local.callCount == 1)
}

@Test func dynamicDestinationRouterReturnsAmbiguityForPhoneticCollisions() async {
  let inbox = dynamicCandidate(title: "Inbox")
  let fleck = dynamicCandidate(title: "Fleck", context: "Fleck workspace")
  let flick = dynamicCandidate(title: "Flick", context: "Film notes")
  let local = DynamicDestinationRouterProbe(result: .inbox)
  let router = DynamicDestinationRouter(
    foundationIsAvailable: { false },
    foundationRouter: DynamicDestinationRouterProbe(result: .inbox),
    localRouter: local
  )

  #expect(await router.route(
    transcript: "For Flag I feel like we need to work on the settings UI",
    candidates: [inbox, fleck, flick],
    inboxID: inbox.destination.noteID
  ) == .ambiguous([
    .init(destination: fleck.destination, contextHint: "Fleck workspace"),
    .init(destination: flick.destination, contextHint: "Film notes"),
  ]))
  #expect(await local.callCount == 0)
}

@Test func dynamicDestinationRouterExactTitleMatchInvokesNeitherSemanticRouter() async {
  let inbox = dynamicCandidate(title: "Inbox", context: "General captures")
  let chemistry = dynamicCandidate(title: "Chemistry", context: "Lab reports")
  let foundation = DynamicDestinationRouterProbe(result: .resolved(chemistry.destination.noteID))
  let local = DynamicDestinationRouterProbe(result: .resolved(chemistry.destination.noteID))
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

  #expect(destination == .resolved(chemistry.destination.noteID))
  #expect(await foundation.callCount == 0)
  #expect(await local.callCount == 0)
}

@Test func dynamicDestinationRouterSelectsTheLiveSemanticRouterAndPreservesContext() async {
  let availability = DynamicDestinationAvailability(false)
  let inbox = dynamicCandidate(title: "Inbox", context: "General captures")
  let project = dynamicCandidate(title: "Project Delta", context: "Launch plans and deadlines")
  let candidates = [inbox, project]
  let foundation = DynamicDestinationRouterProbe(result: .resolved(project.destination.noteID))
  let local = DynamicDestinationRouterProbe(result: .resolved(project.destination.noteID))
  let router = DynamicDestinationRouter(
    foundationIsAvailable: { availability.value },
    foundationRouter: foundation,
    localRouter: local
  )

  #expect(await router.route(
    transcript: "Prepare the launch checklist.",
    candidates: candidates,
    inboxID: inbox.destination.noteID
  ) == .resolved(project.destination.noteID))
  #expect(await local.candidates == candidates)
  #expect(await foundation.callCount == 0)

  availability.value = true

  #expect(await router.route(
    transcript: "Review the launch schedule.",
    candidates: candidates,
    inboxID: inbox.destination.noteID
  ) == .resolved(project.destination.noteID))
  #expect(await foundation.candidates == candidates)
  #expect(await local.callCount == 1)
}

@Test func dynamicDestinationRouterFoundationFailureAndMalformedResultReturnInbox() async {
  let inbox = dynamicCandidate(title: "Inbox")
  let project = dynamicCandidate(title: "Project Delta")
  let candidates = [inbox, project]
  let local = DynamicDestinationRouterProbe(result: .resolved(project.destination.noteID))
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
  ) == .inbox)

  let malformedFoundation = DynamicDestinationRouterProbe(result: .resolved(UUID()))
  let malformedRouter = DynamicDestinationRouter(
    foundationIsAvailable: { true },
    foundationRouter: malformedFoundation,
    localRouter: local
  )
  #expect(await malformedRouter.route(
    transcript: "Review the launch schedule.",
    candidates: candidates,
    inboxID: inbox.destination.noteID
  ) == .inbox)
  #expect(await local.callCount == 0)
}

@Test func dynamicDestinationRouterCancellationReturnsInboxAfterSelectedRouterFinishes() async {
  let inbox = dynamicCandidate(title: "Inbox")
  let project = dynamicCandidate(title: "Project Delta")
  let gate = DynamicDestinationRouterGate()
  let local = DynamicDestinationRouterBlockingProbe(
    result: .resolved(project.destination.noteID),
    gate: gate
  )
  let router = DynamicDestinationRouter(
    foundationIsAvailable: { false },
    foundationRouter: DynamicDestinationRouterProbe(result: .resolved(project.destination.noteID)),
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

  #expect(await task.value == .inbox)
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
  let result: DictationRoutingDecision
  private(set) var callCount = 0
  private(set) var candidates: [DictationRoutingCandidate] = []

  init(result: DictationRoutingDecision) {
    self.result = result
  }

  func route(
    transcript _: String,
    candidates: [DictationRoutingCandidate],
    inboxID _: UUID?
  ) async -> DictationRoutingDecision {
    callCount += 1
    self.candidates = candidates
    return result
  }
}

private struct DynamicDestinationRouterBlockingProbe: DestinationRouting {
  let result: DictationRoutingDecision
  let gate: DynamicDestinationRouterGate

  func route(
    transcript _: String,
    candidates _: [DictationRoutingCandidate],
    inboxID _: UUID?
  ) async -> DictationRoutingDecision {
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
