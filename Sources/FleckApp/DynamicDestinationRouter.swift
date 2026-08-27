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
  ) async -> UUID? {
    guard !Task.isCancelled else { return inboxID }
    if let destinationID = FoundationModelDictation.exactTitleDestinationID(
      transcript: transcript,
      candidates: candidates
    ) {
      return destinationID
    }

    let destinationID: UUID?
    if foundationIsAvailable() {
      destinationID = await foundationRouter.route(
        transcript: transcript,
        candidates: candidates,
        inboxID: inboxID
      )
    } else {
      destinationID = await localRouter.route(
        transcript: transcript,
        candidates: candidates,
        inboxID: inboxID
      )
    }

    guard !Task.isCancelled,
      let destinationID,
      candidates.contains(where: { $0.destination.noteID == destinationID })
    else { return inboxID }
    return destinationID
  }
}
