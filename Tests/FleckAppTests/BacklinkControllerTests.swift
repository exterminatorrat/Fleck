import Foundation
import Testing

@testable import FleckApp
@testable import FleckCore

@Test @MainActor func BacklinkControllerRejectsSupersededResults() async {
  let firstSnapshot = Note(id: UUID(), title: "First")
  let secondSnapshot = Note(id: UUID(), title: "Second")
  let firstIndex = makeBacklinkIndex(sourceID: firstSnapshot.id)
  let secondIndex = makeBacklinkIndex(sourceID: secondSnapshot.id)
  let gate = BacklinkBuildGate()
  let controller = BacklinkController(build: { notes in
    await gate.build(notes)
  })

  controller.refresh(liveNotes: [firstSnapshot])
  await gate.waitUntilStarted(for: firstSnapshot.id)
  controller.refresh(liveNotes: [secondSnapshot])
  await gate.waitUntilStarted(for: secondSnapshot.id)
  await gate.complete(secondSnapshot.id, with: secondIndex)
  await gate.complete(firstSnapshot.id, with: firstIndex)
  await yieldToMainActor()

  #expect(controller.index == secondIndex)
}

@Test @MainActor func BacklinkControllerCancellationKeepsPublishedIndex() async {
  let publishedSnapshot = Note(id: UUID(), title: "Published")
  let blockedSnapshot = Note(id: UUID(), title: "Blocked")
  let publishedIndex = makeBacklinkIndex(sourceID: publishedSnapshot.id)
  let blockedIndex = makeBacklinkIndex(sourceID: blockedSnapshot.id)
  let gate = BacklinkBuildGate()
  let controller = BacklinkController(build: { notes in
    await gate.build(notes)
  })

  controller.refresh(liveNotes: [publishedSnapshot])
  await gate.waitUntilStarted(for: publishedSnapshot.id)
  await gate.complete(publishedSnapshot.id, with: publishedIndex)
  await yieldToMainActor()
  #expect(controller.index == publishedIndex)

  controller.refresh(liveNotes: [blockedSnapshot])
  await gate.waitUntilStarted(for: blockedSnapshot.id)
  controller.cancel()
  await gate.complete(blockedSnapshot.id, with: blockedIndex)
  await yieldToMainActor()

  #expect(controller.index == publishedIndex)
}

@MainActor
private func yieldToMainActor() async {
  for _ in 0..<4 {
    await Task.yield()
  }
}

private func makeBacklinkIndex(sourceID: UUID) -> BacklinkIndex {
  let targetID = UUID()
  let source = BacklinkSource(
    sourceNoteID: sourceID,
    sourceDisplayTitle: "Source",
    sourceFolderID: nil,
    targetNoteID: targetID,
    excerpt: "excerpt",
    referenceCount: 1,
    sourceModifiedAt: Date(timeIntervalSince1970: 1)
  )
  return BacklinkIndex(incomingByTarget: [targetID: [source]])
}

private actor BacklinkBuildGate {
  private var pending: [UUID: CheckedContinuation<BacklinkIndex, Never>] = [:]
  private var started = Set<UUID>()
  private var startWaiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]

  func build(_ notes: [Note]) async -> BacklinkIndex {
    let requestID = notes[0].id
    started.insert(requestID)
    let waiters = startWaiters.removeValue(forKey: requestID) ?? []
    for waiter in waiters {
      waiter.resume()
    }
    return await withCheckedContinuation { continuation in
      pending[requestID] = continuation
    }
  }

  func waitUntilStarted(for requestID: UUID) async {
    guard !started.contains(requestID) else { return }
    await withCheckedContinuation { continuation in
      startWaiters[requestID, default: []].append(continuation)
    }
  }

  func complete(_ requestID: UUID, with index: BacklinkIndex) {
    pending.removeValue(forKey: requestID)?.resume(returning: index)
  }
}
