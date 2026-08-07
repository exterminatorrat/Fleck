#if os(macOS)
  import AppKit
  import Combine
  import FleckCore
  import SwiftUI

  func workspaceSearchHighlightedAttributedString(
    _ text: String,
    query: String,
    accent: Color
  ) -> AttributedString {
    let ranges = workspaceSearchHighlightRanges(in: text, query: query)
    guard !ranges.isEmpty else { return AttributedString(text) }

    var highlighted = AttributedString()
    var cursor = text.startIndex
    for nsRange in ranges {
      guard let range = Range(nsRange, in: text) else { continue }
      if cursor < range.lowerBound {
        highlighted.append(AttributedString(String(text[cursor..<range.lowerBound])))
      }
      var match = AttributedString(String(text[range]))
      match.foregroundColor = accent
      highlighted.append(match)
      cursor = range.upperBound
    }
    if cursor < text.endIndex {
      highlighted.append(AttributedString(String(text[cursor...])))
    }
    return highlighted
  }

  private func workspaceSearchHighlightRanges(
    in text: String,
    query: String
  ) -> [NSRange] {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty, !text.isEmpty else { return [] }

    let source = text as NSString
    var searchRange = NSRange(location: 0, length: source.length)
    var ranges: [NSRange] = []
    while searchRange.length > 0 {
      let match = source.range(
        of: query,
        options: [.caseInsensitive, .diacriticInsensitive],
        range: searchRange,
        locale: Locale(identifier: "en_US_POSIX")
      )
      guard match.location != NSNotFound,
        match.length > 0
      else {
        break
      }
      let range = source.rangeOfComposedCharacterSequences(for: match)
      ranges.append(range)
      let nextLocation = match.location + match.length
      guard nextLocation < source.length else { break }
      searchRange = NSRange(
        location: nextLocation,
        length: source.length - nextLocation
      )
    }
    var coalesced: [NSRange] = []
    for range in ranges {
      guard let last = coalesced.last else {
        coalesced.append(range)
        continue
      }
      if range.location <= NSMaxRange(last) {
        coalesced[coalesced.count - 1] = NSUnionRange(last, range)
      } else {
        coalesced.append(range)
      }
    }
    return coalesced
  }

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
      let countDescription: String
      switch results.count {
      case 0: countDescription = "No results"
      case 1: countDescription = "1 result"
      default: countDescription = "\(results.count) results"
      }
      guard !results.isEmpty, !resultsAreCurrent else { return countDescription }
      return "Updating search results; \(countDescription)"
    }

    var resultsAreCurrent: Bool {
      resultGeneration == searchGeneration
    }

    func present(for noteID: UUID? = nil) {
      guard !isPresented else { return }
      cancelSearch()
      searchGeneration &+= 1
      focusOrigin = WorkspaceSearchFocusOrigin.capture(
        preferredWindow: hostingWindow,
        noteID: noteID
      )
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
          for _ in 0..<12 {
            await Task.yield()
            if origin.restore() { break }
          }
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
      focusOrigin?.markActivated(noteID)
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
    private enum Surface: Equatable {
      case editor
      case title
      case unknown
    }

    weak var window: NSWindow?
    weak var responder: NSResponder?
    weak var fieldEditorOwner: NSView?
    let fieldEditorSelection: NSRange?
    let originalFieldEditorText: String?
    private let surface: Surface
    let noteID: UUID?
    private var activatedNoteID: UUID?

    private init(
      window: NSWindow,
      responder: NSResponder,
      fieldEditorOwner: NSView? = nil,
      fieldEditorSelection: NSRange? = nil,
      originalFieldEditorText: String? = nil,
      surface: Surface = .unknown,
      noteID: UUID? = nil
    ) {
      self.window = window
      self.responder = responder
      self.fieldEditorOwner = fieldEditorOwner
      self.fieldEditorSelection = fieldEditorSelection
      self.originalFieldEditorText = originalFieldEditorText
      self.surface = surface
      self.noteID = noteID
    }

    static func capture(
      preferredWindow: NSWindow?,
      noteID: UUID?
    ) -> WorkspaceSearchFocusOrigin? {
      guard let window = preferredWindow ?? NSApp?.keyWindow ?? NSApp?.mainWindow,
        let responder = window.firstResponder
      else {
        return nil
      }
      if responder is ListAwareTextView {
        return WorkspaceSearchFocusOrigin(
          window: window,
          responder: responder,
          surface: .editor,
          noteID: noteID
        )
      }
      guard let fieldEditor = responder as? NSTextView else {
        return WorkspaceSearchFocusOrigin(
          window: window,
          responder: responder,
          surface: .unknown,
          noteID: noteID
        )
      }
      let fieldEditorOwner = (fieldEditor.delegate as? NSView)
        ?? fieldEditorOwner(for: fieldEditor, in: window.contentView)
      let surface: Surface =
        (fieldEditorOwner as? NSTextField)?.frame.width ?? 0 > 200
          ? .title
          : .unknown
      return WorkspaceSearchFocusOrigin(
        window: window,
        responder: responder,
        fieldEditorOwner: fieldEditorOwner,
        fieldEditorSelection: fieldEditor.selectedRange(),
        originalFieldEditorText: (fieldEditorOwner as? NSTextField)?.stringValue,
        surface: surface,
        noteID: noteID
      )
    }

    func markActivated(_ noteID: UUID) {
      activatedNoteID = noteID
    }

    @discardableResult
    func restore() -> Bool {
      guard let window else { return false }
      let noteChanged = if let noteID, let activatedNoteID {
        noteID != activatedNoteID
      } else {
        false
      }
      let titleChanged = if surface == .title,
        let fieldEditorOwner = fieldEditorOwner as? NSTextField,
        let originalFieldEditorText
      {
        fieldEditorOwner.stringValue != originalFieldEditorText
      } else {
        false
      }
      if noteChanged || titleChanged {
        return restoreSemanticSurface(in: window)
      }
      if let fieldEditorOwner,
        fieldEditorOwner.window === window
      {
        if window.makeFirstResponder(fieldEditorOwner) {
          if let control = fieldEditorOwner as? NSControl {
            guard let fieldEditor = control.currentEditor() as? NSTextView,
              window.firstResponder === fieldEditor
            else {
              return restoreSemanticSurface(in: window)
            }
            if let fieldEditorSelection {
              fieldEditor.setSelectedRange(fieldEditorSelection)
            }
            return true
          }
          if window.firstResponder === fieldEditorOwner { return true }
        }
      }
      if surface == .title {
        return restoreSemanticSurface(in: window)
      }
      if let responder {
        if let view = responder as? NSView, view.window !== window {
          return restoreSemanticSurface(in: window)
        }
        if window.makeFirstResponder(responder), window.firstResponder === responder {
          return true
        }
      }
      return restoreSemanticSurface(in: window)
    }

    private func restoreSemanticSurface(in window: NSWindow) -> Bool {
      let responder: NSResponder?
      switch surface {
      case .editor:
        responder = descendant(in: window.contentView) { view in
          guard let editor = view as? ListAwareTextView,
            editor !== self.responder
          else { return nil }
          return editor
        }
      case .title:
        responder = descendant(in: window.contentView) { view in
          guard let field = view as? NSTextField,
            field.placeholderString == "Note title"
          else {
            return nil
          }
          return field
        }
      case .unknown:
        responder = nil
      }
      guard let responder else { return false }
      guard window.makeFirstResponder(responder) else { return false }
      if let control = responder as? NSControl {
        return control.currentEditor().map { window.firstResponder === $0 } ?? false
      }
      return window.firstResponder === responder
    }

    private func descendant<T: NSView>(
      in view: NSView?,
      matching: (NSView) -> T?
    ) -> T? {
      guard let view else { return nil }
      if let match = matching(view) { return match }
      for subview in view.subviews {
        if let match = descendant(in: subview, matching: matching) {
          return match
        }
      }
      return nil
    }

    private static func fieldEditorOwner(
      for fieldEditor: NSTextView,
      in view: NSView?
    ) -> NSView? {
      guard let view else { return nil }
      if let control = view as? NSControl,
        view.window?.fieldEditor(false, for: control) === fieldEditor
      {
        return control
      }
      for subview in view.subviews {
        if let owner = fieldEditorOwner(for: fieldEditor, in: subview) {
          return owner
        }
      }
      return nil
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

  struct WorkspaceSearchView: View {
    @ObservedObject var controller: WorkspaceSearchController
    let notes: [Note]
    let accent: Color
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
            let resultsAreCurrent = controller.resultsAreCurrent
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
                        Text(
                          workspaceSearchHighlightedAttributedString(
                            result.displayTitle,
                            query: controller.query,
                            accent: accent
                          )
                        )
                          .font(.body.weight(.semibold))
                          .lineLimit(1)
                        Text(
                          workspaceSearchHighlightedAttributedString(
                            result.snippet,
                            query: controller.query,
                            accent: accent
                          )
                        )
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
                    .accessibilityHint(resultsAreCurrent ? "" : "Updating search results")
                    .disabled(!resultsAreCurrent)
                    .opacity(resultsAreCurrent ? 1 : 0.65)
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
