import Foundation

struct DynamicDestinationRouter: DestinationRouting {
  private let foundationIsAvailable: @Sendable () -> Bool
  private let foundationRouter: any DestinationRouting
  private let localRouter: any DestinationRouting

  init(
    foundationIsAvailable: @escaping @Sendable () -> Bool,
    foundationRouter: any DestinationRouting,
    localRouter: any DestinationRouting
  ) {
    self.foundationIsAvailable = foundationIsAvailable
    self.foundationRouter = foundationRouter
    self.localRouter = localRouter
  }

  func route(
    transcript: String,
    candidates: [DictationRoutingCandidate],
    inboxID: UUID?
  ) async -> DictationRoutingDecision {
    guard !Task.isCancelled else { return .inbox }
    if let destinationID = FoundationModelDictation.exactTitleDestinationID(
      transcript: transcript,
      candidates: candidates
    ) {
      return .resolved(destinationID)
    }

    let decision: DictationRoutingDecision
    if foundationIsAvailable() {
      decision = await foundationRouter.route(
        transcript: transcript,
        candidates: candidates,
        inboxID: inboxID
      )
    } else {
      decision = await localRouter.route(
        transcript: transcript,
        candidates: candidates,
        inboxID: inboxID
      )
    }

    guard !Task.isCancelled else { return .inbox }
    switch decision {
    case .resolved(let destinationID):
      guard destinationID != inboxID,
        candidates.contains(where: { $0.destination.noteID == destinationID })
      else { return .inbox }
      return decision
    case .ambiguous(let choices):
      guard (2...4).contains(choices.count),
        Set(choices.map(\.destination.noteID)).count == choices.count,
        choices.allSatisfy({ choice in
          choice.destination.noteID != inboxID
            && candidates.contains(where: { $0.destination == choice.destination })
            && choice.contextHint == DictationRoutingChoice.boundedContextHint(
              from: choice.contextHint
            )
        })
      else { return .inbox }
      return decision
    case .inbox:
      return .inbox
    }
  }

}
