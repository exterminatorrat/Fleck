import AppKit
import FleckCore
import Testing
@testable import FleckApp

@Suite
struct DictationFilingPlanTests {
  @Test
  func routesLosslessChunksToDistinctDestinations() async throws {
    let text = "Plan alpha.  Buy 🧭!\nFinish."
    let chunks = try #require(DictationFilingPlan.hostChunks(in: text))
    #expect(chunks == ["Plan alpha.  ", "Buy 🧭!\n", "Finish."])

    let firstID = UUID()
    let secondID = UUID()
    let candidates = [
      candidate(id: firstID, title: "Ideas", body: "existing first note"),
      candidate(id: secondID, title: "Shopping", body: "existing second note"),
    ]
    let route = DeterministicRouter(decisions: [
      chunks[0]: .resolved(firstID),
      chunks[1]: .resolved(secondID),
      chunks[2]: .resolved(firstID),
    ])
    let router = DynamicDestinationRouter(
      foundationIsAvailable: { false },
      foundationRouter: route,
      localRouter: route
    )

    let decision = await router.route(transcript: text, candidates: candidates, inboxID: nil)
    guard case .filing(let plan) = decision else {
      Issue.record("Expected a validated filing plan")
      return
    }
    #expect(plan.text == text)
    #expect(plan.outputs.map(\.text) == ["Plan alpha.  Finish.", "Buy 🧭!\n"])
    #expect(plan.outputs.map(\.destinationID) == [firstID, secondID])
    #expect(plan.isValid(against: candidates))
  }

  @Test
  func hostChunkingPreservesUnicodeAndCapsChunkCount() throws {
    let text = String(repeating: "😀e\u{301}.  ", count: 12)
    let chunks = try #require(DictationFilingPlan.hostChunks(in: text))
    #expect(chunks.count <= 8)
    #expect(chunks.joined() == text)
  }

  @Test
  func planRejectsCanonicallyEquivalentButByteDifferentFragments() throws {
    let text = "Café. Next."
    let chunks = try #require(DictationFilingPlan.hostChunks(in: text))
    let decomposed = "Cafe\u{301}. "
    #expect(chunks[0] == decomposed)
    let firstID = UUID()
    let secondID = UUID()
    let candidates = [
      candidate(id: firstID, title: "First", body: "first"),
      candidate(id: secondID, title: "Second", body: "second"),
    ]
    #expect(DictationFilingPlan.make(
      text: text,
      fragments: [
        .init(text: decomposed, destinationID: firstID),
        .init(text: chunks[1], destinationID: secondID),
      ],
      candidates: candidates
    ) == nil)
  }

  @MainActor
  @Test
  func discoversMarkdownAndStyledHeadingsWithSectionEnds() throws {
    let markdown = "Intro\n\n# Plans\nA.\n\n## Notes\nB.\n\n# Next\nC."
    let markdownHeadings = DictationSectionInsertion.headings(
      in: Note(body: markdown),
      defaults: NoteTextAppendDefaults()
    )
    #expect(markdownHeadings.map(\.title) == ["Plans", "Notes", "Next"])
    let nextHeadingOffset = try #require(markdown.range(of: "# Next")?.lowerBound)
      .utf16Offset(in: markdown)
    #expect(markdownHeadings[0].insertionUTF16Offset == nextHeadingOffset)
    #expect(markdownHeadings[1].insertionUTF16Offset == nextHeadingOffset)

    let fenced = "# Real\n```swift\n# Fake\n```\n## Actual\n"
    let fencedHeadings = DictationSectionInsertion.headings(
      in: Note(body: fenced),
      defaults: NoteTextAppendDefaults()
    )
    #expect(fencedHeadings.map(\.title) == ["Real", "Actual"])

    let setext = "Plans\n=====\nBody\nNotes\n---\nTail"
    let setextHeadings = DictationSectionInsertion.headings(
      in: Note(body: setext),
      defaults: NoteTextAppendDefaults()
    )
    #expect(setextHeadings.map(\.title) == ["Plans", "Notes"])
    #expect(setextHeadings.map(\.level) == [1, 2])

    let defaults = NoteTextAppendDefaults(fontFamily: "Helvetica Neue", fontSize: 17)
    let styledBody = "Styled\nBody\n# Markdown\nTail"
    let attributed = NSMutableAttributedString(
      string: styledBody,
      attributes: defaults.attributes
    )
    let styledRange = NSRange(location: 0, length: "Styled\n".utf16.count)
    attributed.addAttribute(
      .font,
      value: NSFontManager.shared.convert(
        NSFont.systemFont(ofSize: defaults.fontSize * 1.75),
        toHaveTrait: .boldFontMask
      ),
      range: styledRange
    )
    let paragraph = NSMutableParagraphStyle()
    paragraph.paragraphSpacingBefore = 12
    paragraph.paragraphSpacing = 8
    attributed.addAttribute(.paragraphStyle, value: paragraph, range: styledRange)
    let rtf = try NoteRichTextCodec.encode(attributed)
    let styledHeadings = DictationSectionInsertion.headings(
      in: Note(body: styledBody, richTextRTF: rtf),
      defaults: defaults
    )
    #expect(styledHeadings.map(\.title) == ["Styled", "Markdown"])
    #expect(styledHeadings[0].level == 1)
  }

  @MainActor
  @Test
  func insertionAndDigestBoundRemovalPreserveCapturedText() throws {
    let defaults = NoteTextAppendDefaults()
    let body = "Existing paragraph."
    let original = NSMutableAttributedString(string: body, attributes: defaults.attributes)
    original.addAttribute(
      .font,
      value: NSFontManager.shared.convert(defaults.font, toHaveTrait: .boldFontMask),
      range: NSRange(location: 0, length: "Existing".utf16.count)
    )
    let note = Note(body: body, richTextRTF: try NoteRichTextCodec.encode(original))
    let text = "🧭 New capture."
    let insertion = try DictationSectionInsertion.inserting(
      text,
      into: note,
      atUTF16Offset: note.body.utf16.count,
      defaults: defaults
    )
    let inserted = (insertion.body as NSString).substring(
      with: NSRange(location: insertion.location, length: insertion.length)
    )
    #expect(inserted == "\n\n\(text)")
    #expect(insertion.digest == DictationFilingPlan.digest(inserted))

    let updatedNote = Note(body: insertion.body, richTextRTF: insertion.richTextRTF)
    let removal = try DictationSectionInsertion.removing(
      range: NSRange(location: insertion.location, length: insertion.length),
      digest: insertion.digest,
      from: updatedNote,
      defaults: defaults
    )
    #expect(removal.body == note.body)
    let insertedAttributed = try NoteRichTextCodec.decode(insertion.richTextRTF)
    let insertedBoldFont = try #require(
      insertedAttributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    )
    let insertedRegularFont = try #require(
      insertedAttributed.attribute(
        .font,
        at: "Existing".utf16.count,
        effectiveRange: nil
      ) as? NSFont
    )
    #expect(NSFontManager.shared.traits(of: insertedBoldFont).contains(.boldFontMask))
    #expect(!NSFontManager.shared.traits(of: insertedRegularFont).contains(.boldFontMask))
    let restored = try NoteRichTextCodec.decode(removal.richTextRTF)
    let restoredBoldFont = try #require(
      restored.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    )
    let restoredRegularFont = try #require(
      restored.attribute(.font, at: "Existing".utf16.count, effectiveRange: nil) as? NSFont
    )
    #expect(NSFontManager.shared.traits(of: restoredBoldFont).contains(.boldFontMask))
    #expect(!NSFontManager.shared.traits(of: restoredRegularFont).contains(.boldFontMask))
  }

  @MainActor
  @Test
  func mismatchedRichTextIsRejectedForHeadingDiscoveryAndInsertion() throws {
    let defaults = NoteTextAppendDefaults()
    let staleRTF = try NoteRichTextCodec.encode(NSAttributedString(
      string: "Different body",
      attributes: defaults.attributes
    ))
    let note = Note(body: "# Current heading", richTextRTF: staleRTF)
    #expect(DictationSectionInsertion.headings(in: note, defaults: defaults).isEmpty)

    var rejected = false
    do {
      _ = try DictationSectionInsertion.inserting(
        "Capture",
        into: note,
        atUTF16Offset: note.body.utf16.count,
        defaults: defaults
      )
    } catch {
      rejected = true
    }
    #expect(rejected)
  }

  @Test
  func missingOrDuplicateHeadingsFallBackToWholeCaptureRoute() async throws {
    let text = "Please discuss the roadmap."
    let noteID = UUID()
    let route = DeterministicRouter(decisions: [text: .resolved(noteID)])
    let router = DynamicDestinationRouter(
      foundationIsAvailable: { false },
      foundationRouter: route,
      localRouter: route
    )
    let withoutHeadings = [candidate(id: noteID, title: "Notes", body: "existing body")]
    #expect(await router.route(
      transcript: text,
      candidates: withoutHeadings,
      inboxID: nil
    ) == .resolved(noteID))

    let body = "# Roadmap\nFirst.\n\n# Roadmap\nSecond."
    let secondHeading = try #require(body.range(
      of: "# Roadmap",
      range: body.index(after: body.startIndex)..<body.endIndex
    ))
    let secondLocation = secondHeading.lowerBound.utf16Offset(in: body)
    let duplicateHeadings = [
      heading(location: 0, title: "Roadmap", level: 1, insertion: secondLocation),
      heading(location: secondLocation, title: "Roadmap", level: 1, insertion: body.utf16.count),
    ]
    let duplicateCandidate = candidate(
      id: noteID,
      title: "Notes",
      body: body,
      headings: duplicateHeadings
    )
    #expect(await router.route(
      transcript: text,
      candidates: [duplicateCandidate],
      inboxID: nil
    ) == .resolved(noteID))
  }

  @Test
  func planRejectsUnknownAndStaleDestinations() throws {
    let body = "# Roadmap\nCurrent notes."
    let noteID = UUID()
    let section = heading(
      location: 0,
      title: "Roadmap",
      level: 1,
      insertion: body.utf16.count
    )
    let current = candidate(
      id: noteID,
      title: "Notes",
      body: body,
      revision: 7,
      headings: [section]
    )
    let text = "Roadmap update."
    let fragments = [DictationFilingPlan.Fragment(text: text, destinationID: noteID)]
    let plan = try #require(DictationFilingPlan.make(
      text: text,
      fragments: fragments,
      candidates: [current]
    ))
    #expect(plan.outputs[0].bodyDigest == DictationFilingPlan.digest(body))
    #expect(plan.isValid(against: [current]))

    let changedBodyText = body + "\nChanged."
    let changedSection = heading(
      location: 0,
      title: "Roadmap",
      level: 1,
      insertion: changedBodyText.utf16.count
    )
    let changedBody = candidate(
      id: noteID,
      title: "Notes",
      body: changedBodyText,
      revision: 7,
      headings: [changedSection]
    )
    let changedRevision = candidate(
      id: noteID,
      title: "Notes",
      body: body,
      revision: 8,
      headings: [section]
    )
    let changedHeadings = candidate(id: noteID, title: "Notes", body: body, revision: 7)
    #expect(!plan.isValid(against: [changedBody]))
    #expect(!plan.isValid(against: [changedRevision]))
    #expect(!plan.isValid(against: [changedHeadings]))

    let unknown = DictationFilingPlan.Fragment(text: text, destinationID: UUID())
    #expect(DictationFilingPlan.make(
      text: text,
      fragments: [unknown],
      candidates: [current]
    ) == nil)
  }

  @Test
  func planRejectsDuplicatedOrOmittedSourceFragments() throws {
    let text = "First sentence. Second sentence."
    let chunks = try #require(DictationFilingPlan.hostChunks(in: text))
    #expect(chunks.count == 2)
    let noteID = UUID()
    let candidate = candidate(id: noteID, title: "Notes", body: "existing body")
    let duplicated = [
      DictationFilingPlan.Fragment(text: chunks[0], destinationID: noteID),
      DictationFilingPlan.Fragment(text: chunks[0], destinationID: noteID),
    ]
    let omitted = [
      DictationFilingPlan.Fragment(text: chunks[0], destinationID: noteID),
    ]
    #expect(DictationFilingPlan.make(
      text: text,
      fragments: duplicated,
      candidates: [candidate]
    ) == nil)
    #expect(DictationFilingPlan.make(
      text: text,
      fragments: omitted,
      candidates: [candidate]
    ) == nil)
  }

  @Test
  func oneNotePlanAllowsAppendFragmentsBesideUniqueHeading() throws {
    let text = "Roadmap\n\nAdditional details"
    let chunks = try #require(DictationFilingPlan.hostChunks(in: text))
    #expect(chunks == ["Roadmap\n\n", "Additional details"])
    #expect(chunks.allSatisfy { !$0.allSatisfy(\.isWhitespace) })

    let body = "# Roadmap\nExisting notes."
    let noteID = UUID()
    let candidate = candidate(
      id: noteID,
      title: "Notes",
      body: body,
      headings: [heading(
        location: 0,
        title: "Roadmap",
        level: 1,
        insertion: body.utf16.count
      )]
    )
    let plan = try #require(DictationFilingPlan.make(
      text: text,
      fragments: chunks.map { .init(text: $0, destinationID: noteID) },
      candidates: [candidate]
    ))
    #expect(plan.outputs.count == 2)
    #expect(plan.outputs[0].heading?.title == "Roadmap")
    #expect(plan.outputs[0].text == chunks[0])
    #expect(plan.outputs[1].heading == nil)
    #expect(plan.outputs[1].text == chunks[1])
  }

  @Test
  func oversizedCaptureCannotCreateAHostPlan() {
    #expect(DictationFilingPlan.hostChunks(in: String(repeating: "x", count: 16_385)) == nil)
  }

  @Test
  func unresolvedChunkFallsBackToWholeCaptureRoute() async throws {
    let text = "First sentence. Second sentence."
    let chunks = try #require(DictationFilingPlan.hostChunks(in: text))
    let resolvedID = UUID()
    let route = DeterministicRouter(decisions: [
      chunks[0]: .resolved(resolvedID),
      chunks[1]: .inbox,
      text: .resolved(resolvedID),
    ])
    let router = DynamicDestinationRouter(
      foundationIsAvailable: { false },
      foundationRouter: route,
      localRouter: route
    )
    let candidates = [candidate(id: resolvedID, title: "Notes", body: "body")]
    #expect(await router.route(transcript: text, candidates: candidates, inboxID: nil) == .resolved(resolvedID))
  }

  @Test
  func singleRouteProviderCannotInjectAFilingPlan() async throws {
    let text = "First sentence. Second sentence."
    let chunks = try #require(DictationFilingPlan.hostChunks(in: text))
    let firstID = UUID()
    let secondID = UUID()
    let candidates = [
      candidate(id: firstID, title: "Alpha", body: "first body"),
      candidate(id: secondID, title: "Beta", body: "second body"),
    ]
    let fragments = [
      DictationFilingPlan.Fragment(text: chunks[0], destinationID: firstID),
      DictationFilingPlan.Fragment(text: chunks[1], destinationID: secondID),
    ]
    let injected = try #require(DictationFilingPlan.make(
      text: text,
      fragments: fragments,
      candidates: candidates
    ))
    let route = DeterministicRouter(decisions: Dictionary(
      uniqueKeysWithValues: (chunks + [text]).map { ($0, .filing(injected)) }
    ))
    let router = DynamicDestinationRouter(
      foundationIsAvailable: { false },
      foundationRouter: route,
      localRouter: route
    )
    #expect(await router.route(transcript: text, candidates: candidates, inboxID: nil) == .inbox)
  }

  @Test
  func cancelledRouteDoesNotContinueIntoSingleRouteProvider() async {
    let id = UUID()
    let text = "A route that must not start."
    let candidate = candidate(id: id, title: "Notes", body: "body")
    let route = DeterministicRouter(decisions: [text: .resolved(id)])
    let router = DynamicDestinationRouter(
      foundationIsAvailable: { false },
      foundationRouter: route,
      localRouter: route
    )
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return await router.route(transcript: text, candidates: [candidate], inboxID: nil)
    }
    #expect(await task.value == .inbox)
  }

  private func candidate(
    id: UUID,
    title: String,
    body: String,
    revision: UInt64 = 1,
    headings: [DictationRoutingHeading] = []
  ) -> DictationRoutingCandidate {
    DictationRoutingCandidate(
      destination: DictationDestination(noteID: id, title: title),
      semanticContext: body,
      contentRevision: revision,
      headings: headings
    )
  }

  private func heading(
    location: Int,
    title: String,
    level: Int,
    insertion: Int
  ) -> DictationRoutingHeading {
    DictationRoutingHeading(
      id: DictationFilingPlan.headingID(location: location, title: title, level: level),
      title: title,
      level: level,
      insertionUTF16Offset: insertion
    )
  }
}

private struct DeterministicRouter: DestinationRouting {
  let decisions: [String: DictationRoutingDecision]

  func route(
    transcript: String,
    candidates _: [DictationRoutingCandidate],
    inboxID _: UUID?
  ) async -> DictationRoutingDecision {
    decisions[transcript] ?? .inbox
  }
}
