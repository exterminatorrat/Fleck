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
    guard let chunks = DictationFilingPlan.hostChunks(in: transcript) else {
      return await routeSingle(transcript: transcript, candidates: candidates, inboxID: inboxID)
    }

    var fragments: [DictationFilingPlan.Fragment] = []
    var wholeCaptureDecision: DictationRoutingDecision?
    for chunk in chunks {
      let decision = await routeSingle(
        transcript: chunk,
        candidates: candidates,
        inboxID: inboxID
      )
      guard !Task.isCancelled else { return .inbox }
      guard case .resolved(let destinationID) = decision else {
        if chunks.count == 1 { return decision }
        return await routeSingle(transcript: transcript, candidates: candidates, inboxID: inboxID)
      }
      if chunks.count == 1 { wholeCaptureDecision = decision }
      fragments.append(.init(text: chunk, destinationID: destinationID))
    }

    guard !Task.isCancelled else { return .inbox }
    if let plan = DictationFilingPlan.make(
      text: transcript,
      fragments: fragments,
      candidates: candidates,
      inboxID: inboxID
    ), plan.isValid(against: candidates) {
      return .filing(plan)
    }
    if let wholeCaptureDecision { return wholeCaptureDecision }
    return await routeSingle(transcript: transcript, candidates: candidates, inboxID: inboxID)
  }

  private func routeSingle(
    transcript: String,
    candidates: [DictationRoutingCandidate],
    inboxID: UUID?
  ) async -> DictationRoutingDecision {
    guard !Task.isCancelled else { return .inbox }
    if let destinationID = FoundationModelDictation.exactTitleDestinationID(
      transcript: transcript,
      candidates: candidates
    ) {
      guard destinationID != inboxID,
        candidates.contains(where: { $0.destination.noteID == destinationID })
      else { return .inbox }
      return .resolved(destinationID)
    }
    let cueChoices = Self.leadingDestinationCueChoices(
      transcript: transcript,
      candidates: candidates,
      inboxID: inboxID
    )
    if !cueChoices.isEmpty { return .ambiguous(cueChoices) }

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
      guard (1...4).contains(choices.count),
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
    case .filing:
      return .inbox
    }
  }

  private static func leadingDestinationCueChoices(
    transcript: String,
    candidates: [DictationRoutingCandidate],
    inboxID: UUID?
  ) -> [DictationRoutingChoice] {
    let words = transcript.split(whereSeparator: { !$0.isLetter })
    guard words.count >= 2,
      words[0].lowercased() == "for",
      let cue = englishWord(String(words[1]))
    else { return [] }

    let eligibleIDs = Set(FoundationModelDictation.eligibleDestinations(
      from: candidates.map(\.destination)
    ).map(\.noteID))
    var seenIDs = Set<UUID>()
    var choices: [DictationRoutingChoice] = []
    for candidate in candidates {
      guard choices.count < 4,
        candidate.destination.noteID != inboxID,
        eligibleIDs.contains(candidate.destination.noteID),
        seenIDs.insert(candidate.destination.noteID).inserted,
        let title = singleEnglishWord(candidate.destination.title),
        cue.prefix(2) == title.prefix(2),
        soundexCode(cue) == soundexCode(title)
      else { continue }
      choices.append(.init(
        destination: candidate.destination,
        contextHint: DictationRoutingChoice.boundedContextHint(from: candidate.semanticContext)
      ))
    }
    return choices
  }

  private static func singleEnglishWord(_ title: String) -> String? {
    let words = title.split(whereSeparator: \Character.isWhitespace)
    guard words.count == 1 else { return nil }
    return englishWord(String(words[0]))
  }

  private static func englishWord(_ value: String) -> String? {
    let value = value.lowercased()
    guard value.count >= 3,
      value.unicodeScalars.allSatisfy({ (97...122).contains($0.value) })
    else { return nil }
    return value
  }

  private static func soundexCode(_ word: String) -> String {
    var characters = word.makeIterator()
    guard let first = characters.next() else { return "" }
    var result = String(first)
    var previous = soundexDigit(first)
    while let character = characters.next(), result.count < 4 {
      let digit = soundexDigit(character)
      if let digit, digit != previous { result.append(digit) }
      previous = digit
    }
    return result.padding(toLength: 4, withPad: "0", startingAt: 0)
  }

  private static func soundexDigit(_ character: Character) -> Character? {
    switch character {
    case "b", "f", "p", "v": "1"
    case "c", "g", "j", "k", "q", "s", "x", "z": "2"
    case "d", "t": "3"
    case "l": "4"
    case "m", "n": "5"
    case "r": "6"
    default: nil
    }
  }
}
