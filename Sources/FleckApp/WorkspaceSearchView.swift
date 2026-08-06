#if os(macOS)
  import AppKit
  import Combine
  import FleckCore
  import SwiftUI

  @MainActor
  final class WorkspaceSearchController: ObservableObject {
    typealias SearchOperation = @MainActor (
      String,
      [Note],
      Int
    ) async -> [WorkspaceSearchResult]

    enum HighlightDirection {
      case up
      case down
    }

    @Published private(set) var isPresented = false
    @Published var query = ""
    @Published private(set) var results: [WorkspaceSearchResult] = []
    @Published private(set) var highlightedNoteID: UUID?

    private let searchOperation: SearchOperation
    private var searchTask: Task<Void, Never>?
    private var searchGeneration: UInt64 = 0
    private var resultGeneration: UInt64?
    private weak var hostingWindow: NSWindow?
    private var focusOrigin: WorkspaceSearchFocusOrigin?
    private var hasActivatedCurrentPresentation = false

    init(
      searchOperation: @escaping SearchOperation = { query, notes, limit in
        await WorkspaceSearchEngine().search(query: query, in: notes, limit: limit)
      }
    ) {
      self.searchOperation = searchOperation
    }

    var resultCountAccessibilityValue: String {
      switch results.count {
      case 0: "No results"
      case 1: "1 result"
      default: "\(results.count) results"
      }
    }

    func present() {
      guard !isPresented else { return }
      cancelSearch()
      searchGeneration &+= 1
      focusOrigin = WorkspaceSearchFocusOrigin.capture(preferredWindow: hostingWindow)
      query = ""
      results = []
      highlightedNoteID = nil
      resultGeneration = nil
      hasActivatedCurrentPresentation = false
      isPresented = true
    }

    func dismiss() {
      guard isPresented || focusOrigin != nil else { return }
      cancelSearch()
      searchGeneration &+= 1
      isPresented = false
      query = ""
      results = []
      highlightedNoteID = nil
      resultGeneration = nil
      hasActivatedCurrentPresentation = false
      let origin = focusOrigin
      focusOrigin = nil
      origin?.restore()
      if let origin {
        Task { @MainActor in
          for _ in 0..<3 {
            await Task.yield()
          }
          origin.restore()
        }
      }
    }

    func setHostingWindow(_ window: NSWindow?) {
      hostingWindow = window
    }

    func setQuery(_ query: String, in notes: [Note]) {
      self.query = query
      refresh(in: notes)
    }

    func refresh(in notes: [Note]) {
      cancelSearch()
      searchGeneration &+= 1
      let generation = searchGeneration
      resultGeneration = nil
      let requestQuery = query
      let trimmedQuery = requestQuery.trimmingCharacters(in: .whitespacesAndNewlines)

      guard isPresented, !trimmedQuery.isEmpty else {
        results = []
        highlightedNoteID = nil
        return
      }

      let operation = searchOperation
      searchTask = Task { @MainActor [weak self] in
        let results = await operation(requestQuery, notes, 50)
        guard let self,
          !Task.isCancelled,
          self.isPresented,
          self.searchGeneration == generation,
          self.query == requestQuery
        else {
          return
        }
        self.apply(results, generation: generation)
      }
    }

    func moveHighlight(_ direction: HighlightDirection) {
      guard !results.isEmpty else { return }

      guard let highlightedNoteID,
        let currentIndex = results.firstIndex(where: { $0.noteID == highlightedNoteID })
      else {
        self.highlightedNoteID = direction == .up ? results.last?.noteID : results.first?.noteID
        return
      }

      let nextIndex: Int
      switch direction {
      case .up:
        nextIndex = max(0, currentIndex - 1)
      case .down:
        nextIndex = min(results.count - 1, currentIndex + 1)
      }
      self.highlightedNoteID = results[nextIndex].noteID
    }

    func highlight(_ noteID: UUID) {
      guard results.contains(where: { $0.noteID == noteID }) else { return }
      highlightedNoteID = noteID
    }

    func isHighlighted(_ noteID: UUID) -> Bool {
      highlightedNoteID == noteID
    }

    @discardableResult
    func activateResult(
      _ noteID: UUID,
      currentNoteIDs: Set<UUID>,
      activate: (UUID) -> Void
    ) -> Bool {
      guard resultGeneration == searchGeneration,
        currentNoteIDs.contains(noteID),
        results.contains(where: { $0.noteID == noteID })
      else {
        return false
      }
      highlight(noteID)
      return activateHighlighted(currentNoteIDs: currentNoteIDs, activate: activate)
    }

    @discardableResult
    func activateHighlighted(
      currentNoteIDs: Set<UUID>,
      activate: (UUID) -> Void
    ) -> Bool {
      guard isPresented,
        !hasActivatedCurrentPresentation,
        resultGeneration == searchGeneration,
        let noteID = highlightedNoteID,
        currentNoteIDs.contains(noteID),
        results.contains(where: { $0.noteID == noteID })
      else {
        return false
      }

      hasActivatedCurrentPresentation = true
      activate(noteID)
      dismiss()
      return true
    }

    @discardableResult
    func handleKey(
      _ key: KeyEquivalent,
      currentNoteIDs: Set<UUID> = [],
      activate: (UUID) -> Void = { _ in }
    ) -> Bool {
      switch key {
      case .upArrow:
        moveHighlight(.up)
        return true
      case .downArrow:
        moveHighlight(.down)
        return true
      case .return:
        _ = activateHighlighted(currentNoteIDs: currentNoteIDs, activate: activate)
        return true
      case .escape:
        dismiss()
        return true
      default:
        return false
      }
    }

    private func apply(_ results: [WorkspaceSearchResult], generation: UInt64) {
      let results = Array(results.prefix(50))
      let previousHighlight = highlightedNoteID
      self.results = results
      resultGeneration = generation
      if let previousHighlight,
        results.contains(where: { $0.noteID == previousHighlight })
      {
        highlightedNoteID = previousHighlight
      } else {
        highlightedNoteID = results.first?.noteID
      }
    }

    private func cancelSearch() {
      searchTask?.cancel()
      searchTask = nil
    }

    deinit {
      searchTask?.cancel()
    }
  }

  @MainActor
  private final class WorkspaceSearchFocusOrigin {
    weak var window: NSWindow?
    weak var responder: NSResponder?

    init(window: NSWindow, responder: NSResponder) {
      self.window = window
      self.responder = responder
    }

    static func capture(preferredWindow: NSWindow?) -> WorkspaceSearchFocusOrigin? {
      guard let window = preferredWindow ?? NSApp?.keyWindow ?? NSApp?.mainWindow,
        let responder = window.firstResponder
      else {
        return nil
      }
      return WorkspaceSearchFocusOrigin(window: window, responder: responder)
    }

    func restore() {
      guard let window, let responder else { return }
      if let view = responder as? NSView, view.window !== window { return }
      _ = window.makeFirstResponder(responder)
    }
  }

  @MainActor
  final class WorkspaceSearchWindowObserver: NSView {
    let onWindowChange: (NSWindow?) -> Void

    init(onWindowChange: @escaping (NSWindow?) -> Void) {
      self.onWindowChange = onWindowChange
      super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      onWindowChange(window)
    }
  }

  struct WorkspaceSearchWindowReader: NSViewRepresentable {
    let controller: WorkspaceSearchController

    func makeNSView(context: Context) -> WorkspaceSearchWindowObserver {
      WorkspaceSearchWindowObserver { window in
        controller.setHostingWindow(window)
      }
    }

    func updateNSView(_ nsView: WorkspaceSearchWindowObserver, context: Context) {
      controller.setHostingWindow(nsView.window)
    }
  }

  @MainActor
  final class WorkspaceSearchKeyResponder: NSView {
    var noteID: UUID?
    var onKeyDown: (UInt16) -> Bool

    init(noteID: UUID?, onKeyDown: @escaping (UInt16) -> Bool) {
      self.noteID = noteID
      self.onKeyDown = onKeyDown
      super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func keyDown(with event: NSEvent) {
      guard onKeyDown(event.keyCode) else {
        super.keyDown(with: event)
        return
      }
    }
  }

  struct WorkspaceSearchKeyResponderView: NSViewRepresentable {
    let noteID: UUID?
    let onKeyDown: (UInt16) -> Bool

    func makeNSView(context: Context) -> WorkspaceSearchKeyResponder {
      WorkspaceSearchKeyResponder(noteID: noteID, onKeyDown: onKeyDown)
    }

    func updateNSView(_ nsView: WorkspaceSearchKeyResponder, context: Context) {
      nsView.noteID = noteID
      nsView.onKeyDown = onKeyDown
    }
  }

  struct WorkspaceSearchView: View {
    @ObservedObject var controller: WorkspaceSearchController
    let notes: [Note]
    let currentNoteIDs: () -> Set<UUID>
    let onActivate: (UUID) -> Void
    @FocusState private var isQueryFocused: Bool

    var body: some View {
      ZStack(alignment: .top) {
        Color.clear
          .contentShape(Rectangle())
          .onTapGesture {
            controller.dismiss()
          }

        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
              .foregroundStyle(.secondary)
              .accessibilityHidden(true)
            TextField("Search notes", text: $controller.query)
              .textFieldStyle(.roundedBorder)
              .focused($isQueryFocused)
              .accessibilityLabel("Search notes")
              .accessibilityHint("Search note titles and bodies")
              .onKeyPress(.upArrow) {
                _ = controller.handleKey(
                  .upArrow,
                  currentNoteIDs: currentNoteIDs(),
                  activate: onActivate
                )
                return .handled
              }
              .onKeyPress(.downArrow) {
                _ = controller.handleKey(
                  .downArrow,
                  currentNoteIDs: currentNoteIDs(),
                  activate: onActivate
                )
                return .handled
              }
              .onKeyPress(.return) {
                _ = controller.handleKey(
                  .return,
                  currentNoteIDs: currentNoteIDs(),
                  activate: onActivate
                )
                return .handled
              }
              .onKeyPress(.escape) {
                _ = controller.handleKey(
                  .escape,
                  currentNoteIDs: currentNoteIDs(),
                  activate: onActivate
                )
                return .handled
              }

            Button {
              controller.dismiss()
            } label: {
              Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss search")
            .help("Dismiss search")
            .onKeyPress(.upArrow) {
              controller.moveHighlight(.up)
              return .handled
            }
            .onKeyPress(.downArrow) {
              controller.moveHighlight(.down)
              return .handled
            }
            .onKeyPress(.escape) {
              controller.dismiss()
              return .handled
            }
            .background(
              WorkspaceSearchKeyResponderView(noteID: nil) { keyCode in
                switch keyCode {
                case 126:
                  controller.moveHighlight(.up)
                  return true
                case 125:
                  controller.moveHighlight(.down)
                  return true
                case 53:
                  controller.dismiss()
                  return true
                default:
                  return false
                }
              }
            )
          }

          Text(controller.resultCountAccessibilityValue)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Search result count")
            .accessibilityValue(controller.resultCountAccessibilityValue)

          if controller.results.isEmpty {
            Text(controller.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              ? "Type to search notes"
              : "No matching notes")
              .font(.callout)
              .foregroundStyle(.secondary)
              .padding(.vertical, 8)
          } else {
            ScrollViewReader { scrollProxy in
              ScrollView(.vertical) {
                LazyVStack(spacing: 2) {
                  ForEach(controller.results) { result in
                    let isSelected = controller.isHighlighted(result.noteID)
                    Button {
                      _ = controller.activateResult(
                        result.noteID,
                        currentNoteIDs: currentNoteIDs(),
                        activate: onActivate
                      )
                    } label: {
                      VStack(alignment: .leading, spacing: 2) {
                        Text(result.displayTitle)
                          .font(.body.weight(.semibold))
                          .lineLimit(1)
                        Text(result.snippet)
                          .font(.caption)
                          .foregroundStyle(.secondary)
                          .lineLimit(2)
                      }
                      .frame(maxWidth: .infinity, alignment: .leading)
                      .padding(.horizontal, 8)
                      .padding(.vertical, 6)
                      .background(
                        RoundedRectangle(cornerRadius: 6)
                          .fill(isSelected ? Color.accentColor.opacity(0.14) : .clear)
                      )
                    }
                    .buttonStyle(.plain)
                    .focusable()
                    .id(result.noteID)
                    .accessibilityLabel("\(result.displayTitle), \(result.snippet)")
                    .accessibilityValue(isSelected ? "Selected" : "Not selected")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .onKeyPress(.upArrow) {
                      controller.moveHighlight(.up)
                      return .handled
                    }
                    .onKeyPress(.downArrow) {
                      controller.moveHighlight(.down)
                      return .handled
                    }
                    .onKeyPress(.escape) {
                      controller.dismiss()
                      return .handled
                    }
                    .background(
                      WorkspaceSearchKeyResponderView(noteID: result.noteID) { keyCode in
                        switch keyCode {
                        case 126:
                          controller.moveHighlight(.up)
                          return true
                        case 125:
                          controller.moveHighlight(.down)
                          return true
                        case 36:
                          return controller.activateResult(
                            result.noteID,
                            currentNoteIDs: currentNoteIDs(),
                            activate: onActivate
                          )
                        case 53:
                          controller.dismiss()
                          return true
                        default:
                          return false
                        }
                      }
                    )
                  }
                }
              }
              .frame(maxHeight: 220)
              .onChange(of: controller.highlightedNoteID) { _, noteID in
                guard let noteID else { return }
                scrollProxy.scrollTo(noteID, anchor: .center)
              }
            }
          }
        }
        .padding(12)
        .frame(maxWidth: 560, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
          RoundedRectangle(cornerRadius: 12)
            .strokeBorder(.quaternary)
        }
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .padding(.horizontal, 20)
      .padding(.top, 48)
      .onMoveCommand { direction in
        switch direction {
        case .up:
          controller.moveHighlight(.up)
        case .down:
          controller.moveHighlight(.down)
        default:
          break
        }
      }
      .onExitCommand {
        controller.dismiss()
      }
      .onAppear {
        isQueryFocused = true
        controller.refresh(in: notes)
      }
      .onChange(of: controller.query) { _, newQuery in
        controller.setQuery(newQuery, in: notes)
      }
      .onChange(of: notes) { _, newNotes in
        controller.refresh(in: newNotes)
      }
      .onDisappear {
        controller.dismiss()
      }
    }
  }
#endif
