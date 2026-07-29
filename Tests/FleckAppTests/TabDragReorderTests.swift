import Foundation
import Testing

@testable import FleckApp

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
