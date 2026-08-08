import Combine
import Foundation
import FleckCore

@MainActor
final class BacklinkController: ObservableObject {
  typealias Build = @Sendable ([Note]) async -> BacklinkIndex

  @Published private(set) var index = BacklinkIndex()

  private let build: Build
  private var task: Task<Void, Never>?
  private var generation: UInt64 = 0

  init(indexer: BacklinkIndexer = BacklinkIndexer()) {
    build = { notes in
      await indexer.build(liveNotes: notes)
    }
  }

  init(build: @escaping Build) {
    self.build = build
  }

  func refresh(liveNotes: [Note]) {
    task?.cancel()
    generation &+= 1
    let requestGeneration = generation
    let operation = build
    task = Task { [weak self] in
      let result = await operation(liveNotes)
      guard let self,
        !Task.isCancelled,
        self.generation == requestGeneration
      else {
        return
      }
      self.index = result
    }
  }

  func incoming(to noteID: UUID?) -> [BacklinkSource] {
    noteID.map(index.incoming(to:)) ?? []
  }

  func cancel() {
    task?.cancel()
    task = nil
    generation &+= 1
  }

  deinit {
    task?.cancel()
  }
}
