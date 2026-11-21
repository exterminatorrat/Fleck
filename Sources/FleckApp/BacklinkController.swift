import Combine
import Foundation
import FleckCore

@MainActor
final class BacklinkController: ObservableObject {
  typealias Build = @Sendable ([Note]) async -> BacklinkIndex

  @Published private(set) var index = BacklinkIndex()
  @Published private(set) var isExpanded = false

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

  @discardableResult
  func refresh(liveNotes: [Note]) -> Task<Void, Never> {
    task?.cancel()
    generation &+= 1
    let requestGeneration = generation
    let operation = build
    let refreshTask = Task { [weak self] in
      let result = await operation(liveNotes)
      guard let self,
        !Task.isCancelled,
        self.generation == requestGeneration,
        !self.index.isEmpty || !result.isEmpty
      else {
        return
      }
      self.index = result
    }
    task = refreshTask
    return refreshTask
  }

  func incoming(to noteID: UUID?) -> [BacklinkSource] {
    noteID.map(index.incoming(to:)) ?? []
  }

  func toggleDisclosure() {
    isExpanded.toggle()
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
