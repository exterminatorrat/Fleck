import Foundation
import Testing
import UniformTypeIdentifiers

@testable import FleckApp

@Test func tabStripConstrainsItsOverflowViewport() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let source = try String(
    contentsOf: root.appendingPathComponent("Sources/FleckApp/NotesPanel.swift"),
    encoding: .utf8
  )

  #expect(source.contains("TabViewportTrailingEdgePreferenceKey"))
  #expect(source.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
  #expect(source.contains("value: proxy.frame(in: .named(\"tab-strip\")).maxX"))
  #expect(!source.contains("tabViewportTrailingEdge = proxy.size.width - 28"))
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
  let first = UUID()
  let second = UUID()
  let third = UUID()
  var ids = [first, second, third]
  let metadata = [first: "first", second: "second", third: "third"]
  let selectedID = first

  func move(_ id: UUID, to destination: Int) {
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
  #expect(
    TabDragReorder.performLiveMove(
      draggedID: first,
      over: third,
      currentNoteIDs: { ids },
      move: move
    )
  )
  #expect(
    TabDragReorder.performLiveMove(
      draggedID: third,
      over: second,
      currentNoteIDs: { ids },
      move: move
    )
  )

  #expect(ids == [third, second, first])
  #expect(metadata[first] == "first")
  #expect(metadata[second] == "second")
  #expect(metadata[third] == "third")
  #expect(selectedID == first)
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
