import Foundation
import Testing
import UniformTypeIdentifiers

@testable import FleckApp
import FleckCore

@Test func tabStripAllocatesItsActualOverflowViewportAtSupportedWidths() throws {
  #expect(TabOverflowPresentation.tabViewportWidth(totalStripWidth: 380) == 352)
  #expect(TabOverflowPresentation.tabViewportWidth(totalStripWidth: 520) == 492)

  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let source = try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/NotesPanel.swift"),
    encoding: .utf8
  )
  let tabStrip = try #require(
    source.components(separatedBy: "private var tabStrip").last?
      .components(separatedBy: "private var motion").first
  )
  let scrollViewport = try #require(
    tabStrip.components(separatedBy: "ScrollView(.horizontal, showsIndicators: false)").last?
      .components(separatedBy: "if hasHiddenTrailingTabs").first
  )
  let tabContent = try #require(
    scrollViewport.components(separatedBy: "HStack(spacing: 6) {").last?
      .components(separatedBy: ".padding(.horizontal, 12)").first
  )

  #expect(tabStrip.contains("GeometryReader { proxy in"))
  #expect(tabStrip.contains("TabOverflowPresentation.tabViewportWidth(totalStripWidth: proxy.size.width)"))
  #expect(tabStrip.contains(".frame(width: tabViewportWidth, alignment: .leading)"))
  #expect(tabStrip.contains(".frame(height: 37)"))
  #expect(tabStrip.contains("visibleTrailingEdge: tabViewportWidth"))
  #expect(scrollViewport.contains(".coordinateSpace(name: \"tab-scroll-viewport\")"))
  #expect(tabContent.contains("Color.clear"))
  #expect(tabContent.contains(".frame(width: 0, height: 0)"))
  #expect(tabContent.contains("value: proxy.frame(in: .named(\"tab-scroll-viewport\")).minX - 6"))
  #expect(!tabContent.contains("value: proxy.frame(in: .named(\"tab-scroll-viewport\")).maxX"))
  #expect(!tabContent.contains("}\n              .background {\n                GeometryReader"))
  #expect(!tabStrip.contains("TabViewportTrailingEdgePreferenceKey"))
  #expect(!tabStrip.contains(".coordinateSpace(name: \"tab-strip\")"))
  #expect(!tabStrip.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
}

@Test func liveTabDragResolvesLeftAndRightDestinations() {
  let first = UUID()
  let second = UUID()
  let third = UUID()
  let ids = [first, second, third]

  #expect(
    TabDragReorder.destinationIndex(
      draggedID: first,
      over: third,
      in: ids
    ) == 2
  )
  #expect(
    TabDragReorder.destinationIndex(
      draggedID: third,
      over: first,
      in: ids
    ) == 0
  )
}

@Test func liveTabDragIgnoresInvalidAndSameTabTargets() {
  let first = UUID()
  let second = UUID()
  let missing = UUID()
  let ids = [first, second]

  #expect(
    TabDragReorder.destinationIndex(
      draggedID: nil,
      over: second,
      in: ids
    ) == nil
  )
  #expect(
    TabDragReorder.destinationIndex(
      draggedID: first,
      over: first,
      in: ids
    ) == nil
  )
  #expect(
    TabDragReorder.destinationIndex(
      draggedID: missing,
      over: second,
      in: ids
    ) == nil
  )
  #expect(
    TabDragReorder.destinationIndex(
      draggedID: first,
      over: missing,
      in: ids
    ) == nil
  )
}

@Test func liveTabDragResolvesEachHoverAgainstCurrentOrder() {
  let first = UUID()
  let second = UUID()
  let third = UUID()
  var ids = [first, second, third]
  var moves: [(UUID, Int)] = []

  func move(_ id: UUID, to destination: Int) {
    moves.append((id, destination))
    let source = ids.firstIndex(of: id)!
    ids.insert(ids.remove(at: source), at: destination)
  }

  #expect(
    TabDragReorder.performLiveMove(
      draggedID: first,
      over: second,
      currentNoteIDs: { ids },
      move: move
    )
  )
  #expect(ids == [second, first, third])

  #expect(
    TabDragReorder.performLiveMove(
      draggedID: first,
      over: third,
      currentNoteIDs: { ids },
      move: move
    )
  )
  #expect(ids == [second, third, first])
  #expect(moves.count == 2)
}

@Test func liveTabDragUsesPanelPrivateMoveOperation() {
  let firstPanelType = TabDragReorder.makeContentType()
  let secondPanelType = TabDragReorder.makeContentType()
  let provider = TabDragReorder.itemProvider(for: UUID(), contentType: firstPanelType)

  #expect(firstPanelType != secondPanelType)
  #expect(provider.hasItemConformingToTypeIdentifier(firstPanelType.identifier))
  #expect(!provider.hasItemConformingToTypeIdentifier(secondPanelType.identifier))
  #expect(!provider.hasItemConformingToTypeIdentifier("public.text"))
  if case .move = TabDragReorder.dropOperation {
    // Expected native reorder operation.
  } else {
    Issue.record("Tab dragging must propose a move operation")
  }
}

@Test func beginningTabDragSelectsTheDraggedIdentityBeforeProvidingIt() {
  let noteID = UUID()
  let contentType = TabDragReorder.makeContentType()
  var selectedIDs: [UUID] = []

  let provider = TabDragReorder.beginDrag(
    noteID: noteID,
    contentType: contentType,
    select: { selectedIDs.append($0) }
  )

  #expect(selectedIDs == [noteID])
  #expect(provider.hasItemConformingToTypeIdentifier(contentType.identifier))
  #expect(!provider.hasItemConformingToTypeIdentifier("public.text"))
}

@Test func liveTabDragRetainsIdentityAndCurrentOrderAcrossLeftAndRightHovers() {
  let first = Note(
    title: "First", body: "first body", richTextRTF: Data([1]), tabColorHex: "#FF4245",
    createdAt: .distantPast, modifiedAt: .distantPast, isPinned: true, agentAccess: true, revision: 1
  )
  let second = Note(
    title: "Second", body: "second body", richTextRTF: Data([2]), tabColorHex: "#FFD600",
    createdAt: .distantFuture, modifiedAt: .distantFuture, revision: 2
  )
  let third = Note(
    title: "Third", body: "third body", richTextRTF: Data([3]), tabColorHex: "#0091FF",
    createdAt: .now, modifiedAt: .now, agentAccess: true, revision: 3
  )
  var workspace = Workspace(notes: [first, second, third], selectedNoteID: first.id)

  func move(_ id: UUID, to destination: Int) {
    workspace.moveNote(id: id, to: destination)
  }

  #expect(
    TabDragReorder.performLiveMove(
      draggedID: first.id,
      over: second.id,
      currentNoteIDs: { workspace.notes.map(\.id) },
      move: move
    )
  )
  #expect(
    TabDragReorder.performLiveMove(
      draggedID: first.id,
      over: third.id,
      currentNoteIDs: { workspace.notes.map(\.id) },
      move: move
    )
  )
  #expect(
    TabDragReorder.performLiveMove(
      draggedID: third.id,
      over: second.id,
      currentNoteIDs: { workspace.notes.map(\.id) },
      move: move
    )
  )

  #expect(workspace.notes == [third, second, first])
  #expect(workspace.notes.map(\.id) == [third.id, second.id, first.id])
  #expect(workspace.selectedNoteID == first.id)
}

@Test func tabOverflowShowsOnlyWhenTrailingContentExceedsVisibleEdge() {
  #expect(
    !TabOverflowPresentation.hasHiddenTrailingContent(
      contentTrailingEdge: 100,
      visibleTrailingEdge: 100
    )
  )
  #expect(
    !TabOverflowPresentation.hasHiddenTrailingContent(
      contentTrailingEdge: 99,
      visibleTrailingEdge: 100
    )
  )
  #expect(
    TabOverflowPresentation.hasHiddenTrailingContent(
      contentTrailingEdge: 101,
      visibleTrailingEdge: 100
    )
  )
}

@Test func tabOverflowDoesNotInferHiddenTrailingContentFromLeadingOffset() {
  #expect(
    !TabOverflowPresentation.hasHiddenTrailingContent(
      contentTrailingEdge: 180,
      visibleTrailingEdge: 180
    )
  )
}

@Test func tabOverflowHidesWhenTheRealLastTabTrailingEdgeIsRevealed() {
  #expect(
    !TabOverflowPresentation.hasHiddenTrailingContent(
      contentTrailingEdge: 492,
      visibleTrailingEdge: 492
    )
  )
}
