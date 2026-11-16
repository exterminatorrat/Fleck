import Foundation

/// Resolves the note a link points at to the title it currently carries.
public struct NoteLinkTargetTitles: Equatable, Sendable {
  private let titlesByID: [UUID: String]

  public init(titlesByID: [UUID: String] = [:]) {
    self.titlesByID = titlesByID
  }

  public init(notes: [Note]) {
    titlesByID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0.displayTitle) })
  }

  public func title(for noteID: UUID) -> String? {
    titlesByID[noteID]
  }

  public var liveNoteIDs: Set<UUID> {
    Set(titlesByID.keys)
  }
}

/// A parsed link together with what its target is called right now.
public struct NoteLinkDrift: Equatable, Sendable {
  public let link: NoteLink
  public let currentTitle: String?

  public init(link: NoteLink, currentTitle: String?) {
    self.link = link
    self.currentTitle = currentTitle
  }

  public var isLive: Bool { currentTitle != nil }

  /// The written label no longer matches the live title, so the sentence says one thing and the
  /// link opens another. A missing target is a different state and is not reported as drift.
  public var isStale: Bool {
    guard let currentTitle else { return false }
    return link.label.trimmingCharacters(in: .whitespacesAndNewlines)
      != currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

public enum NoteLinkInspector {
  public static func driftStates(
    in body: String,
    titles: NoteLinkTargetTitles
  ) -> [NoteLinkDrift] {
    NoteLinkParser.links(in: body).map { link in
      NoteLinkDrift(link: link, currentTitle: titles.title(for: link.targetNoteID))
    }
  }

  /// Rewrites every label that differs from its live target title, leaving destinations, other
  /// links, and surrounding text untouched. Returns the body unchanged when nothing is stale.
  public static func relabeledBody(
    _ body: String,
    titles: NoteLinkTargetTitles
  ) -> (body: String, changedLinkCount: Int) {
    let stale = driftStates(in: body, titles: titles).filter(\.isStale)
    guard !stale.isEmpty else { return (body, 0) }
    let result = NSMutableString(string: body)
    for state in stale.reversed() {
      guard let currentTitle = state.currentTitle else { continue }
      result.replaceCharacters(
        in: state.link.labelRange,
        with: NoteLinkFormatter.escapeLabel(currentTitle)
      )
    }
    return (result as String, stale.count)
  }
}
