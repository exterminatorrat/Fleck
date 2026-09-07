#if os(macOS)
  import AppKit
  import SwiftUI
  import FleckCore
  import UniformTypeIdentifiers

  enum FolderDragPayload {
    static let noteType = UTType(exportedAs: "com.harryjin.fleck.local-note", conformingTo: .data)
    static let folderType = UTType(exportedAs: "com.harryjin.fleck.local-folder", conformingTo: .data)

    struct FolderValue: Codable, Equatable {
      let folderID: UUID
      let sessionID: UUID
    }

    static func noteProvider(source: NoteDropSource) -> NSItemProvider {
      let data = try! JSONEncoder().encode(source)
      let provider = NSItemProvider()
      provider.registerDataRepresentation(forTypeIdentifier: noteType.identifier, visibility: .ownProcess) {
        completion in
        completion(data, nil)
        return nil
      }
      return provider
    }

    static func notePasteboardItem(source: NoteDropSource) -> NSPasteboardItem {
      let item = NSPasteboardItem()
      item.setData(try! JSONEncoder().encode(source), forType: .init(noteType.identifier))
      return item
    }

    static func noteValue(from data: Data) -> NoteDropSource? {
      try? JSONDecoder().decode(NoteDropSource.self, from: data)
    }

    static func folderProvider(folderID: UUID, sessionID: UUID = UUID()) -> NSItemProvider {
      let provider = NSItemProvider()
      let data = try! JSONEncoder().encode(FolderValue(folderID: folderID, sessionID: sessionID))
      provider.registerDataRepresentation(forTypeIdentifier: folderType.identifier, visibility: .ownProcess) {
        completion in
        completion(data, nil)
        return nil
      }
      return provider
    }

    static func folderValue(from data: Data) -> FolderValue? {
      try? JSONDecoder().decode(FolderValue.self, from: data)
    }

    static func folderID(from data: Data) -> UUID? {
      folderValue(from: data)?.folderID
    }
  }

  // Keep the accepted transaction alive independently of drag presentation.
  // Payload authentication and native move completion may arrive in either order.
  @MainActor final class ReorderDropSession {
    let id: UUID
    let type: UTType
    private let sourceID: UUID
    private let noteSource: NoteDropSource?
    private let matches: (Data) -> Bool
    private enum Phase { case dragging, ended, cancelled, committed }
    private var phase = Phase.dragging
    private var accepted = false
    private var pendingCommit: (() -> Void)?

    var canAcceptDrop: Bool { phase == .dragging && !accepted }

    init(source: NoteDropSource) {
      id = source.dragSessionID
      type = FolderDragPayload.noteType
      sourceID = source.noteID
      noteSource = source
      matches = { FolderDragPayload.noteValue(from: $0) == source }
    }

    init(folder: FolderDragPayload.FolderValue) {
      id = folder.sessionID
      type = FolderDragPayload.folderType
      sourceID = folder.folderID
      noteSource = nil
      matches = { FolderDragPayload.folderValue(from: $0) == folder }
    }

    func acceptDrop(from providers: [NSItemProvider], commit: @escaping () -> Void) -> Task<Void, Never>? {
      guard canAcceptDrop,
        let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(type.identifier) })
      else { return nil }
      accepted = true
      return Task { @MainActor in
        guard phase != .cancelled else { return }
        let results = AsyncStream<Data?> { continuation in
          provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, error in
            continuation.yield(error == nil ? data : nil)
            continuation.finish()
          }
        }
        for await data in results {
          guard let data else { cancel(); return }
          _ = stage(data: data, commit: commit)
          return
        }
      }
    }

    func acceptDrop(data: Data, commit: @escaping () -> Void) -> Bool {
      guard canAcceptDrop else { return false }
      accepted = true
      return stage(data: data, commit: commit)
    }

    func acceptReorder(from providers: [NSItemProvider], interaction: ReorderInteraction,
      currentIDs: @escaping () -> [UUID], currentPinnedIDs: @escaping () -> Set<UUID>,
      move: @escaping (UUID, Int) -> Void) -> Task<Void, Never>? {
      guard let commit = reorderCommit(interaction: interaction, currentIDs: currentIDs,
        currentPinnedIDs: currentPinnedIDs, move: move) else { return nil }
      return acceptDrop(from: providers, commit: commit)
    }

    func acceptReorder(data: Data, interaction: ReorderInteraction,
      currentIDs: @escaping () -> [UUID], currentPinnedIDs: @escaping () -> Set<UUID>,
      move: @escaping (UUID, Int) -> Void) -> Bool {
      guard let commit = reorderCommit(interaction: interaction, currentIDs: currentIDs,
        currentPinnedIDs: currentPinnedIDs, move: move) else { return false }
      return acceptDrop(data: data, commit: commit)
    }

    private func reorderCommit(interaction: ReorderInteraction,
      currentIDs: @escaping () -> [UUID], currentPinnedIDs: @escaping () -> Set<UUID>,
      move: @escaping (UUID, Int) -> Void) -> (() -> Void)? {
      var proposal = interaction
      guard proposal.sessionID == id, proposal.sourceID == sourceID, let targetID = proposal.targetID,
        proposal.pinnedIDs.contains(proposal.sourceID) == proposal.pinnedIDs.contains(targetID),
        proposal.pinnedIDs == currentPinnedIDs(),
        let destination = proposal.consume(currentIDs: currentIDs())
      else { return nil }
      return {
        guard proposal.originalIDs == currentIDs(), proposal.pinnedIDs == currentPinnedIDs() else { return }
        move(proposal.sourceID, destination)
      }
    }

    func acceptNoteTransfer(from providers: [NSItemProvider], source: NoteDropSource,
      targetFolderID: UUID?, currentSourceNotes: @escaping () -> [Note],
      validTargetFolderIDs: @escaping () -> Set<UUID>,
      move: @escaping (NoteDropSource, UUID?) -> Bool) -> Task<Void, Never>? {
      guard let commit = noteTransferCommit(source: source, targetFolderID: targetFolderID,
        currentSourceNotes: currentSourceNotes, validTargetFolderIDs: validTargetFolderIDs,
        move: move) else { return nil }
      return acceptDrop(from: providers, commit: commit)
    }

    func acceptNoteTransfer(data: Data, source: NoteDropSource,
      targetFolderID: UUID?, currentSourceNotes: @escaping () -> [Note],
      validTargetFolderIDs: @escaping () -> Set<UUID>,
      move: @escaping (NoteDropSource, UUID?) -> Bool) -> Bool {
      guard let commit = noteTransferCommit(source: source, targetFolderID: targetFolderID,
        currentSourceNotes: currentSourceNotes, validTargetFolderIDs: validTargetFolderIDs,
        move: move) else { return false }
      return acceptDrop(data: data, commit: commit)
    }

    private func noteTransferCommit(source: NoteDropSource, targetFolderID: UUID?,
      currentSourceNotes: @escaping () -> [Note],
      validTargetFolderIDs: @escaping () -> Set<UUID>,
      move: @escaping (NoteDropSource, UUID?) -> Bool) -> (() -> Void)? {
      let originalNotes = currentSourceNotes()
      guard noteSource == source,
        NoteDropPresentation.isValidTarget(draggedSource: source, targetFolderID: targetFolderID,
          notes: originalNotes, validTargetFolderIDs: validTargetFolderIDs())
      else { return nil }
      let originalIDs = originalNotes.map(\.id)
      let originalPins = Set(originalNotes.filter(\.isPinned).map(\.id))
      return {
        let notes = currentSourceNotes()
        guard notes.map(\.id) == originalIDs, Set(notes.filter(\.isPinned).map(\.id)) == originalPins
        else { return }
        _ = NoteDropPresentation.performLocalDrop(draggedSource: source, providerSource: source,
          targetFolderID: targetFolderID, notes: notes, validTargetFolderIDs: validTargetFolderIDs(),
          move: move)
      }
    }

    func end(operation: NSDragOperation) {
      guard phase == .dragging else { return }
      guard operation == .move else { cancel(); return }
      phase = .ended
      commitIfReady()
    }

    func cancel() {
      guard phase != .committed else { return }
      phase = .cancelled
      pendingCommit = nil
    }

    private func stage(data: Data, commit: @escaping () -> Void) -> Bool {
      guard phase != .cancelled && phase != .committed else { return false }
      guard matches(data) else { cancel(); return false }
      pendingCommit = commit
      commitIfReady()
      return true
    }

    private func commitIfReady() {
      guard phase == .ended, let commit = pendingCommit else { return }
      phase = .committed
      pendingCommit = nil
      commit()
    }
  }

  struct NoteDropSource: Codable, Equatable {
    let noteID: UUID
    let sourceFolderID: UUID?
    let dragSessionID: UUID

    init(noteID: UUID, sourceFolderID: UUID?, dragSessionID: UUID = UUID()) {
      self.noteID = noteID
      self.sourceFolderID = sourceFolderID
      self.dragSessionID = dragSessionID
    }
  }

  // The proposal is disposable; only consume on a validated native drop.
  struct ReorderInteraction: Equatable {
    let sourceID: UUID
    let originalIDs: [UUID]
    let sessionID = UUID()
    var pinnedIDs: Set<UUID> = []
    private(set) var targetID: UUID?
    private(set) var after = false
    private(set) var destination: Int?

    mutating func propose(over targetID: UUID, after: Bool, currentIDs: [UUID]) {
      clearTarget()
      guard originalIDs == currentIDs, currentIDs.contains(sourceID), sourceID != targetID,
        let target = currentIDs.filter({ $0 != sourceID }).firstIndex(of: targetID)
      else { return }
      self.targetID = targetID
      self.after = after
      destination = target + (after ? 1 : 0)
    }

    mutating func clearTarget() {
      targetID = nil
      destination = nil
    }

    mutating func consume(currentIDs: [UUID]) -> Int? {
      defer { clearTarget() }
      guard currentIDs == originalIDs, currentIDs.contains(sourceID) else { return nil }
      return destination
    }
  }

  enum NoteDropPresentation {
    static func performLocalDrop(
      draggedSource: NoteDropSource?, providerSource: NoteDropSource?,
      targetFolderID: UUID?, notes: [Note], validTargetFolderIDs: Set<UUID>,
      move: (NoteDropSource, UUID?) -> Bool
    ) -> Bool {
      guard let draggedSource, draggedSource == providerSource,
        isValidTarget(draggedSource: draggedSource, targetFolderID: targetFolderID,
          notes: notes, validTargetFolderIDs: validTargetFolderIDs)
      else { return false }
      return move(draggedSource, targetFolderID)
    }

    static func isValidTarget(
      draggedSource: NoteDropSource?,
      targetFolderID: UUID?,
      notes: [Note],
      validTargetFolderIDs: Set<UUID>
    ) -> Bool {
      guard let draggedSource,
        let note = notes.first(where: { $0.id == draggedSource.noteID }),
        note.folderID == draggedSource.sourceFolderID
      else { return false }
      if let targetFolderID, !validTargetFolderIDs.contains(targetFolderID) {
        return false
      }
      return draggedSource.sourceFolderID != targetFolderID
    }
  }

  @MainActor enum MenuWindowDropGeometry {
    static func targetRect(for view: NSView, in window: NSWindow) -> NSRect? {
      guard view.window === window, !view.bounds.isEmpty, let contentView = window.contentView else {
        return nil
      }
      var rect = view.convert(view.bounds, to: nil)
      var ancestor = view.superview
      while let current = ancestor {
        if let clip = current as? NSClipView {
          rect = rect.intersection(clip.convert(clip.bounds, to: nil))
        }
        ancestor = current.superview
      }
      rect = rect.intersection(contentView.convert(contentView.bounds, to: nil))
      return rect.isNull || rect.isEmpty ? nil : rect
    }
  }

  @MainActor final class MenuWindowNoteDropCoordinator: ObservableObject {
    private final class FolderTarget {
      weak var view: NSView?
      let id = UUID()
      let canAccept: (Data) -> Bool
      let perform: (Data) -> Bool
      let setHovered: (Bool) -> Void

      init(view: NSView, canAccept: @escaping (Data) -> Bool,
        perform: @escaping (Data) -> Bool, setHovered: @escaping (Bool) -> Void) {
        self.view = view
        self.canAccept = canAccept
        self.perform = perform
        self.setHovered = setHovered
      }
    }

    private enum Target: Equatable {
      case tab
      case folder(UUID)
    }

    private weak var window: NSWindow?
    private var proxy: MenuWindowDropProxy?
    private var source: NoteDropSource?
    private var session: ReorderDropSession?
    private weak var tabController: FluidTabDragController?
    private var folderTargets: [FolderTarget] = []
    private var target: Target?
    private var performedSequence: Int?

    func activate(source: NoteDropSource, session: ReorderDropSession,
      tabController: FluidTabDragController?) {
      clearTarget()
      self.source = source
      self.session = session
      self.tabController = tabController
      performedSequence = nil
    }

    func deactivate(sessionID: UUID) {
      guard source?.dragSessionID == sessionID else { return }
      clearTarget()
      source = nil
      session = nil
      tabController = nil
      performedSequence = nil
    }

    @discardableResult
    func registerFolderTarget(view: NSView, canAccept: @escaping (Data) -> Bool,
      perform: @escaping (Data) -> Bool, setHovered: @escaping (Bool) -> Void) -> UUID {
      let registration = FolderTarget(view: view, canAccept: canAccept,
        perform: perform, setHovered: setHovered)
      folderTargets.append(registration)
      return registration.id
    }

    func unregisterFolderTarget(_ id: UUID) {
      if target == .folder(id) { transition(to: nil) }
      folderTargets.removeAll { $0.id == id }
    }

    func attach(to window: NSWindow) {
      if self.window === window, window.delegate === proxy { return }
      detach()
      let proxy = MenuWindowDropProxy(originalDelegate: window.delegate, coordinator: self)
      self.window = window
      self.proxy = proxy
      window.registerForDraggedTypes([.init(FolderDragPayload.noteType.identifier)])
      window.delegate = proxy
    }

    func detach() {
      clearTarget()
      if let window, window.delegate === proxy {
        window.delegate = proxy?.originalDelegate
      }
      window = nil
      proxy = nil
    }

    func detach(from window: NSWindow) {
      guard self.window === window else { return }
      detach()
    }

    fileprivate func operation(_ sender: any NSDraggingInfo) -> NSDragOperation {
      guard let data = validData(sender), let window else {
        clearTarget()
        return []
      }
      folderTargets.removeAll { $0.view == nil }
      if let folder = folderTargets.last(where: { registration in
        guard let view = registration.view,
          let rect = MenuWindowDropGeometry.targetRect(for: view, in: window)
        else { return false }
        return rect.contains(sender.draggingLocation) && registration.canAccept(data)
      }) {
        transition(to: .folder(folder.id))
        return .move
      }
      if let tabController, let view = tabController.view,
        let rect = MenuWindowDropGeometry.targetRect(for: view, in: window),
        rect.contains(sender.draggingLocation) {
        transition(to: .tab)
        return tabController.operation(sender)
      }
      clearTarget()
      return []
    }

    fileprivate func prepare(_ sender: any NSDraggingInfo) -> Bool {
      guard operation(sender) == .move else { return false }
      sender.animatesToDestination = false
      return true
    }

    fileprivate func perform(_ sender: any NSDraggingInfo) -> Bool {
      guard performedSequence != sender.draggingSequenceNumber,
        operation(sender) == .move,
        let data = validData(sender)
      else { return false }
      let accepted: Bool
      switch target {
      case .tab:
        accepted = tabController?.perform(sender) ?? false
      case .folder(let id):
        accepted = folderTargets.first(where: { $0.id == id })?.perform(data) ?? false
      case nil:
        accepted = false
      }
      if accepted { performedSequence = sender.draggingSequenceNumber }
      return accepted
    }

    fileprivate func clearTarget() { transition(to: nil) }

    private func validData(_ sender: any NSDraggingInfo) -> Data? {
      guard sender.draggingDestinationWindow === window,
        sender.draggingSource is ReorderNativeSource,
        let source, let session,
        session.id == source.dragSessionID,
        session.canAcceptDrop,
        let data = sender.draggingPasteboard.data(
          forType: .init(FolderDragPayload.noteType.identifier)
        ),
        FolderDragPayload.noteValue(from: data) == source
      else { return nil }
      return data
    }

    private func transition(to next: Target?) {
      guard target != next else { return }
      switch target {
      case .tab:
        tabController?.exited()
      case .folder(let id):
        folderTargets.first(where: { $0.id == id })?.setHovered(false)
      case nil:
        break
      }
      target = next
      if case .folder(let id) = next {
        folderTargets.first(where: { $0.id == id })?.setHovered(true)
      }
    }
  }

  final class MenuWindowDropProxy: NSObject, NSWindowDelegate {
    fileprivate weak var originalDelegate: (any NSWindowDelegate)?
    private unowned let coordinator: MenuWindowNoteDropCoordinator
    private var foreignOperation: (sequence: Int, operation: NSDragOperation)?

    init(originalDelegate: (any NSWindowDelegate)?, coordinator: MenuWindowNoteDropCoordinator) {
      self.originalDelegate = originalDelegate
      self.coordinator = coordinator
    }

    override func responds(to selector: Selector!) -> Bool {
      super.responds(to: selector) || originalDelegate?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
      if originalDelegate?.responds(to: selector) == true { return originalDelegate }
      return super.forwardingTarget(for: selector)
    }

    @MainActor @objc func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
      guard !isFleckNote(sender) else { return coordinator.operation(sender) }
      let operation = (originalDelegate as AnyObject?)?.draggingEntered?(sender) ?? []
      foreignOperation = (sender.draggingSequenceNumber, operation)
      return operation
    }

    @MainActor @objc func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
      guard !isFleckNote(sender) else { return coordinator.operation(sender) }
      return (originalDelegate as AnyObject?)?.draggingUpdated?(sender)
        ?? (foreignOperation?.sequence == sender.draggingSequenceNumber
          ? foreignOperation?.operation : nil)
        ?? []
    }

    @MainActor @objc func draggingExited(_ sender: (any NSDraggingInfo)?) {
      if let sender {
        if isFleckNote(sender) {
          coordinator.clearTarget()
        } else {
          (originalDelegate as AnyObject?)?.draggingExited?(sender)
        }
      } else {
        coordinator.clearTarget()
        (originalDelegate as AnyObject?)?.draggingExited?(nil)
      }
      foreignOperation = nil
    }

    @MainActor @objc func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
      guard !isFleckNote(sender) else { return coordinator.prepare(sender) }
      return (originalDelegate as AnyObject?)?.prepareForDragOperation?(sender) ?? true
    }

    @MainActor @objc func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
      guard !isFleckNote(sender) else { return coordinator.perform(sender) }
      return (originalDelegate as AnyObject?)?.performDragOperation?(sender) ?? false
    }

    @MainActor @objc func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
      if let sender {
        if isFleckNote(sender) {
          coordinator.clearTarget()
        } else {
          (originalDelegate as AnyObject?)?.concludeDragOperation?(sender)
        }
      } else {
        coordinator.clearTarget()
        (originalDelegate as AnyObject?)?.concludeDragOperation?(nil)
      }
      foreignOperation = nil
    }

    @MainActor @objc func draggingEnded(_ sender: any NSDraggingInfo) {
      if isFleckNote(sender) {
        coordinator.clearTarget()
      } else {
        (originalDelegate as AnyObject?)?.draggingEnded?(sender)
      }
      foreignOperation = nil
    }

    @MainActor private func isFleckNote(_ sender: any NSDraggingInfo) -> Bool {
      sender.draggingPasteboard.availableType(
        from: [.init(FolderDragPayload.noteType.identifier)]
      ) != nil
    }

  }

  private struct MenuWindowDropInstaller: NSViewRepresentable {
    let coordinator: MenuWindowNoteDropCoordinator

    func makeNSView(context: Context) -> HostView {
      HostView(coordinator: coordinator)
    }

    func updateNSView(_ view: HostView, context: Context) {
      view.installIfNeeded()
    }

    static func dismantleNSView(_ view: HostView, coordinator: ()) {
      view.uninstall()
    }

    final class HostView: NSView {
      private let coordinator: MenuWindowNoteDropCoordinator
      private weak var installedWindow: NSWindow?

      init(coordinator: MenuWindowNoteDropCoordinator) {
        self.coordinator = coordinator
        super.init(frame: .zero)
      }

      required init?(coder: NSCoder) { nil }

      override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installIfNeeded()
      }

      override func hitTest(_ point: NSPoint) -> NSView? { nil }

      func installIfNeeded() {
        guard installedWindow !== window else {
          if let window { coordinator.attach(to: window) }
          return
        }
        if let installedWindow { coordinator.detach(from: installedWindow) }
        installedWindow = window
        if let window { coordinator.attach(to: window) }
      }

      func uninstall() {
        if let installedWindow { coordinator.detach(from: installedWindow) }
        installedWindow = nil
      }
    }
  }

  private struct MenuWindowDropInstallation: ViewModifier {
    let coordinator: MenuWindowNoteDropCoordinator
    let enabled: Bool

    func body(content: Content) -> some View {
      content.background {
        if enabled {
          MenuWindowDropInstaller(coordinator: coordinator)
            .frame(width: 0, height: 0)
        }
      }
    }
  }

  private struct MenuWindowFolderDropAnchor: NSViewRepresentable {
    let coordinator: MenuWindowNoteDropCoordinator
    let canAccept: (Data) -> Bool
    let perform: (Data) -> Bool
    let setHovered: (Bool) -> Void

    func makeNSView(context: Context) -> HostView {
      let view = HostView()
      view.owner = coordinator
      view.update(canAccept: canAccept, perform: perform, setHovered: setHovered)
      view.registrationID = coordinator.registerFolderTarget(
        view: view,
        canAccept: { [weak view] in view?.canAccept($0) ?? false },
        perform: { [weak view] in view?.perform($0) ?? false },
        setHovered: { [weak view] in view?.setHovered($0) }
      )
      return view
    }

    func updateNSView(_ view: HostView, context: Context) {
      view.update(canAccept: canAccept, perform: perform, setHovered: setHovered)
    }

    static func dismantleNSView(_ view: HostView, coordinator: ()) {
      guard let owner = view.owner, let registrationID = view.registrationID else { return }
      owner.unregisterFolderTarget(registrationID)
    }

    final class HostView: NSView {
      weak var owner: MenuWindowNoteDropCoordinator?
      var registrationID: UUID?
      var canAccept: (Data) -> Bool = { _ in false }
      var perform: (Data) -> Bool = { _ in false }
      var setHovered: (Bool) -> Void = { _ in }

      override func hitTest(_ point: NSPoint) -> NSView? { nil }

      func update(canAccept: @escaping (Data) -> Bool,
        perform: @escaping (Data) -> Bool, setHovered: @escaping (Bool) -> Void) {
        self.canAccept = canAccept
        self.perform = perform
        self.setHovered = setHovered
      }
    }
  }

  enum FolderNavigatorFocus {
    static func nextIndex(
      currentIndex: Int,
      direction: MoveCommandDirection,
      count: Int
    ) -> Int {
      guard count > 0 else { return 0 }
      let offset: Int
      switch direction {
      case .up: offset = -1
      case .down: offset = 1
      default: return currentIndex
      }
      return min(max(currentIndex + offset, 0), count - 1)
    }
  }

  enum TabDragReorder {
    static func partitionLocalDestination(
      draggedID: UUID,
      absoluteDestination: Int,
      visibleNotes: [Note]
    ) -> Int? {
      guard let draggedNote = visibleNotes.first(where: { $0.id == draggedID }) else {
        return nil
      }
      let notesAfterRemoval = visibleNotes.filter { $0.id != draggedID }
      let insertion = min(max(absoluteDestination, 0), notesAfterRemoval.count)
      return notesAfterRemoval.prefix(insertion).reduce(into: 0) { count, note in
        if note.isPinned == draggedNote.isPinned {
          count += 1
        }
      }
    }

  }

  enum TabOverflowPresentation {
    static let tabOverflowRailWidth: CGFloat = 56

    static func tabViewportWidth(totalStripWidth: CGFloat) -> CGFloat {
      max(0, totalStripWidth - tabOverflowRailWidth)
    }
  }

  enum FontSizeSubmission {
    static func requestedSize(
      for text: String,
      currentSize: CGFloat?,
      isMixed: Bool
    ) -> CGFloat? {
      guard let size = Double(text), size.isFinite, (1...512).contains(size) else { return nil }
      let requestedSize = CGFloat(size)
      guard isMixed || requestedSize != currentSize else { return nil }
      return requestedSize
    }
  }

  enum FormattingToolbarLayout: Equatable {
    case full
    case compact

    static func presentation(availableWidth: CGFloat) -> Self {
      availableWidth >= 720 ? .full : .compact
    }
  }

  enum NotesPanelSizing: Equatable {
    case storedPreferences
    case container

    static func storedSize(preferred: CGSize, available: CGSize) -> CGSize {
      CGSize(
        width: min(preferred.width, max(available.width, 0)),
        height: min(preferred.height, max(available.height, 0))
      )
    }
  }

  enum PinnedChromeMaterialPolicy: Equatable {
    case liquidGlass
    case legacyMaterial
    case opaque

    static func resolve(
      supportsLiquidGlass: Bool,
      reduceTransparency: Bool,
      increasedContrast: Bool
    ) -> Self {
      if reduceTransparency || increasedContrast { return .opaque }
      return supportsLiquidGlass ? .liquidGlass : .legacyMaterial
    }
  }

  enum NotesPanelBannerCategory: Hashable {
    case captureFailure
    case agentChange
  }

  enum NotesPanelBannerOccurrence: Hashable {
    case captureFailure(message: String, actionPanes: [DictationPrivacyPane])
    case agentChange(changeID: UUID, count: Int)

    var category: NotesPanelBannerCategory {
      switch self {
      case .captureFailure: .captureFailure
      case .agentChange: .agentChange
      }
    }
  }

  enum NotesPanelBannerPolicy {
    static func activeOccurrences(
      captureFailure: NotesPanelBannerOccurrence?,
      routineRecoveryAction _: DictationCapsuleAction?,
      agentChange: NotesPanelBannerOccurrence?
    ) -> Set<NotesPanelBannerOccurrence> {
      Set([captureFailure, agentChange].compactMap { $0 })
    }
  }

  struct NotesPanelBannerDismissalState: Equatable {
    private var dismissedOccurrences = Set<NotesPanelBannerOccurrence>()

    mutating func reconcile(
      activeOccurrences: Set<NotesPanelBannerOccurrence>
    ) {
      dismissedOccurrences.formIntersection(activeOccurrences)
    }

    mutating func forgetDismissedOccurrences(
      in category: NotesPanelBannerCategory
    ) {
      dismissedOccurrences = dismissedOccurrences.filter {
        $0.category != category
      }
    }

    mutating func dismiss(_ occurrence: NotesPanelBannerOccurrence) {
      dismissedOccurrences.insert(occurrence)
    }

    func isPresented(_ occurrence: NotesPanelBannerOccurrence) -> Bool {
      !dismissedOccurrences.contains(occurrence)
    }
  }

  struct NotesPanelBannerCloseButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
      Button(action: action) {
        Image(systemName: "xmark")
          .font(.system(size: 10, weight: .semibold))
          .frame(width: 22, height: 22)
      }
      .buttonStyle(.borderless)
      .help("Dismiss \(label)")
      .accessibilityLabel("Dismiss \(label)")
    }
  }

  struct NotesPanel: View {
    private enum EditorFocus: Hashable {
      case title
      case body
    }

    private enum TabScrollTarget: Hashable {
      case leading
      case trailing
    }

    @EnvironmentObject private var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var dictationRuntime: DictationRuntime
    let isPinned: Bool
    let sizing: NotesPanelSizing
    @StateObject private var editorCommands = EditorCommands()
    @StateObject private var searchController: WorkspaceSearchController
    @StateObject private var noteLinkPickerController: NoteLinkPickerController
    @StateObject private var backlinkController: BacklinkController
    @Namespace private var selectedTabHighlight
    @State private var isImporting = false
    @State private var isExporting = false
    @State private var isShowingTrash = false
    @State private var isShowingDictationHistory = false
    @State private var isShowingAgentActivity = false
    @State private var notePendingDeletion: Note?
    @State private var folderPendingDeletion: Folder?
    @State private var dontAskAgainForDeletion = false
    @State private var notePendingAgentShare: Note?
    @State private var exportDocument: NoteFileDocument?
    @State private var exportType = NoteFileDocument.markdownContentType
    @State private var exportFilename = "Untitled.md"
    @State private var noteDropSource: NoteDropSource?
    @State private var reorderDragSession: ReorderDropSession?
    @StateObject private var fluidTabDrag = FluidTabDragController()
    @StateObject private var menuWindowDrop = MenuWindowNoteDropCoordinator()
    @State private var tabColorPickerNoteID: UUID?
    @State private var activeFolderID: UUID?
    @State private var bannerDismissalState = NotesPanelBannerDismissalState()
    @State private var restoreEditorFocusAfterHide = false
    @State private var searchPointerActivationPending = false
    @FocusState private var editorFocus: EditorFocus?
    private let filePicker: NoteFilePicker

    init(
      dictationRuntime: DictationRuntime,
      isPinned: Bool = false,
      sizing: NotesPanelSizing = .storedPreferences,
      editorCommands: EditorCommands? = nil,
      searchController: WorkspaceSearchController? = nil,
      noteLinkPickerController: NoteLinkPickerController? = nil,
      backlinkController: BacklinkController? = nil,
      filePicker: NoteFilePicker = .live
    ) {
      let searchController = searchController ?? WorkspaceSearchController()
      let noteLinkPickerController = noteLinkPickerController ?? NoteLinkPickerController()
      self.dictationRuntime = dictationRuntime
      self.isPinned = isPinned
      self.sizing = sizing
      _editorCommands = StateObject(wrappedValue: editorCommands ?? EditorCommands())
      _searchController = StateObject(wrappedValue: searchController)
      _noteLinkPickerController = StateObject(wrappedValue: noteLinkPickerController)
      _backlinkController = StateObject(wrappedValue: backlinkController ?? BacklinkController())
      self.filePicker = filePicker
      noteLinkPickerController.setPresentationGuard { !searchController.isPresented }
    }

    var body: some View {
      ZStack {
        if isPinned {
          PinnedWritingSurface()
            .accessibilityHidden(true)
        }
        VStack(spacing: 0) {
          if let migrationError = appState.startupMigrationError {
            migrationFailure(migrationError)
          } else {
            if isPinned {
              pinnedNavigationChrome
            } else {
              header
              folderNavigator
              tabStrip
              Divider().opacity(0.35)
            }
            if let failure = dictationRuntime.captureFailure {
              let occurrence = NotesPanelBannerOccurrence.captureFailure(
                message: failure.message,
                actionPanes: failure.actions.map(\.pane)
              )
              if bannerDismissalState.isPresented(occurrence) {
                HStack(spacing: 8) {
                  Label(failure.message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                  Spacer()
                  ForEach(failure.actions, id: \.pane) { action in
                    Button(action.title) {
                      dictationRuntime.openSystemSettings(action)
                    }
                    .accessibilityLabel(action.title)
                  }
                  NotesPanelBannerCloseButton(
                    label: "dictation capture failure",
                    action: { dismissBanner(occurrence) }
                  )
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.quaternary.opacity(0.35))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Dictation unavailable")
              }
            }
            if let banner = appState.agentBannerPresentation {
              let occurrence = NotesPanelBannerOccurrence.agentChange(
                changeID: banner.feedback.changeID,
                count: banner.count
              )
              if bannerDismissalState.isPresented(occurrence) {
                AgentChangeBanner(
                  presentation: banner,
                  motion: motion,
                  onUndo: { Task { await appState.undoLatestAgentChange() } },
                  onDismiss: { dismissBanner(occurrence) }
                )
                .animation(motion.quick, value: banner)
              }
            }
            scopedEditor
              .frame(minHeight: 80)
              .layoutPriority(1)
            if let error = appState.saveError {
              Text("Could not save: \(error)")
                .font(.caption)
                .foregroundStyle(.red)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let error = appState.noteFileReferenceError {
              Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
        }
        .allowsHitTesting(!searchController.isPresented)
        .allowsHitTesting(!isBlockingOverlayPresented)
        .disabled(searchController.isPresented)
        .disabled(isBlockingOverlayPresented)
        .accessibilityHidden(searchController.isPresented)
        .accessibilityHidden(isBlockingOverlayPresented)
      }
      .frame(
        width: storedPanelSize?.width,
        height: storedPanelSize?.height
      )
      .frame(
        maxWidth: sizing == .container ? .infinity : nil,
        maxHeight: sizing == .container ? .infinity : nil
      )
      .background {
        if !isPinned {
          Rectangle()
            .fill(.ultraThinMaterial)
            .opacity(appState.preferences.panelOpacity)
        }
      }
      .tint(Color(hex: appState.preferences.accentHex) ?? .accentColor)
      .background(
        ShortcutMonitor(shortcuts: appState.preferences.shortcuts, action: performShortcut)
          .frame(width: 0, height: 0)
      )
      .background(
        WorkspaceSearchWindowReader(controller: searchController)
          .frame(width: 0, height: 0)
      )
      .background(
        NoteLinkPickerWindowReader(controller: noteLinkPickerController)
          .frame(width: 0, height: 0)
      )
      .modifier(MenuWindowDropInstallation(
        coordinator: menuWindowDrop,
        enabled: !isPinned
      ))
      .onChange(of: activeBannerOccurrences, initial: true) { _, occurrences in
        bannerDismissalState.reconcile(activeOccurrences: occurrences)
      }
      .onChange(of: appState.workspace.selectedNoteID, initial: true) { _, _ in
        appState.refreshSelectedNoteFileReferences()
      }
      .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
        appState.refreshSelectedNoteFileReferences()
      }
      .onReceive(dictationRuntime.$captureFailure) { failure in
        guard failure == nil else { return }
        bannerDismissalState.forgetDismissedOccurrences(in: .captureFailure)
      }
      .fileImporter(
        isPresented: $isImporting,
        allowedContentTypes: [.plainText, NoteFileDocument.markdownContentType],
        allowsMultipleSelection: true,
        onCompletion: importFiles
      )
      .fileExporter(
        isPresented: $isExporting,
        document: exportDocument,
        contentType: exportType,
        defaultFilename: exportFilename
      ) { result in
        if case .failure(let error) = result {
          appState.saveError = "Export failed: \(error.localizedDescription)"
        }
      }
      .sheet(isPresented: $isShowingDictationHistory) {
        DictationHistoryView(
          history: dictationRuntime.historyController,
          onOpenDestination: openHistoryDestination
        )
      }
      .sheet(isPresented: agentActivitySheetPresentation) {
        agentActivityContent
          .frame(minWidth: 520, minHeight: 380)
      }
      .sheet(item: $notePendingAgentShare) { note in
        AgentNoteAccessEditorView(
          note: note,
          onDismiss: { notePendingAgentShare = nil }
        )
          .environmentObject(appState)
      }
      .onAppear {
        dictationRuntime.registerEditor(editorCommands)
      }
      .onDisappear {
        fluidTabDrag.cancel()
        if let source = noteDropSource {
          menuWindowDrop.deactivate(sessionID: source.dragSessionID)
        }
        if !isPinned { menuWindowDrop.detach() }
        noteDropSource = nil
        dictationRuntime.unregisterEditor(editorCommands)
      }
      .overlay {
        ZStack {
          if isShowingTrash {
            TrashPanelOverlay(
              onDone: { isShowingTrash = false }
            )
            .transition(
              .opacity.combined(
                with: .scale(scale: reduceMotion ? 1 : 0.985)
              )
            )
          }

          if !isPinned && isShowingAgentActivity {
            agentActivityOverlay
          }

          if let folderPendingDeletion {
            FolderDeleteConfirmationOverlay(
              folder: folderPendingDeletion,
              onCancel: { self.folderPendingDeletion = nil },
              onConfirm: { confirmFolderDeletion(folderPendingDeletion) }
            )
            .transition(
              .opacity.combined(
                with: .scale(scale: reduceMotion ? 1 : 0.985)
              )
            )
          }

          if let notePendingDeletion {
            DeleteConfirmationOverlay(
              note: notePendingDeletion,
              dontAskAgain: $dontAskAgainForDeletion,
              onCancel: {
                self.notePendingDeletion = nil
                self.dontAskAgainForDeletion = false
              },
              onConfirm: { confirmDeletion(notePendingDeletion) }
            )
            .transition(
              .opacity.combined(
                with: .scale(scale: reduceMotion ? 1 : 0.985)
              )
            )
          }
        }
        .animation(motion.standard, value: isShowingTrash)
        .animation(motion.standard, value: folderPendingDeletion?.id)
        .animation(motion.standard, value: notePendingDeletion?.id)
      }
      .overlay {
        ZStack {
          if searchController.isPresented && !noteLinkPickerController.isPresented {
            WorkspaceSearchView(
              controller: searchController,
              notes: appState.workspace.notes,
              accent: Color(hex: appState.preferences.accentHex) ?? .accentColor,
              presentationID: searchController.presentationID,
              reduceMotion: reduceMotion,
              currentNoteIDs: {
                Set(appState.workspace.notes.map(\.id))
              },
              onActivate: { noteID in
                guard activateNoteAndScope(noteID) else { return }
              },
              onDismiss: dismissWorkspaceSearch
            )
            .id(searchController.presentationID)
            .zIndex(2)
            .transition(workspaceSearchPresentationTransition)
          }
        }
      }
      .overlay {
        if noteLinkPickerController.isPresented {
          NoteLinkPickerView(
            controller: noteLinkPickerController,
            notes: appState.workspace.notes,
            foldersByID: folderNamesByID,
            accent: Color(hex: appState.preferences.accentHex) ?? .accentColor,
            currentNoteIDs: { Set(appState.workspace.notes.map(\.id)) },
            currentSource: {
              guard let source = visibleSelectedNote else { return nil }
              return (source.id, source.revision)
            },
            onChoose: insertNoteLink
          )
          .zIndex(3)
        }
      }
      .task {
        await appState.waitUntilInitialLoad()
        guard !Task.isCancelled else { return }
        activeFolderID = appState.folderScopeForSelectedNote()
        backlinkController.refresh(liveNotes: appState.workspace.notes)
      }
      .onChange(of: appState.workspace.notes) { _, notes in
        backlinkController.refresh(liveNotes: notes)
      }
      .onChange(of: searchController.isPresented) { _, isPresented in
        if !isPresented {
          searchPointerActivationPending = false
        }
        if isPresented, noteLinkPickerController.isPresented {
          dismissWorkspaceSearch()
        }
      }
      .onChange(of: noteLinkPickerController.isPresented) { _, isPresented in
        if isPresented, searchController.isPresented {
          dismissWorkspaceSearch()
        }
      }
      .onChange(of: appState.workspace.folders) { _, folders in
        guard let activeFolderID,
          !folders.contains(where: { $0.id == activeFolderID })
        else { return }
        self.activeFolderID = nil
      }
      .onChange(of: appState.workspace.selectedNoteID) { oldID, newID in
        guard isShowingTrash, oldID != newID else { return }
        if let newID {
          activeFolderID = appState.folderID(for: newID)
        } else {
          activeFolderID = nil
        }
      }
    }

    private var pinnedNavigationChrome: some View {
      VStack(spacing: 0) {
        header
        folderNavigator
        tabStrip
        Divider().opacity(0.35)
      }
      .modifier(PinnedNavigationChromeSurface())
    }

    private var modifierShortcutPresentation: DictationModifierSettingsPresentation {
      dictationRuntime.modifierShortcutPresentation
    }

    private var activeBannerOccurrences: Set<NotesPanelBannerOccurrence> {
      let captureFailure = dictationRuntime.captureFailure.map {
        NotesPanelBannerOccurrence.captureFailure(
          message: $0.message,
          actionPanes: $0.actions.map(\.pane)
        )
      }
      let agentChange = appState.agentBannerPresentation.map {
        NotesPanelBannerOccurrence.agentChange(
          changeID: $0.feedback.changeID,
          count: $0.count
        )
      }
      return NotesPanelBannerPolicy.activeOccurrences(
        captureFailure: captureFailure,
        routineRecoveryAction: dictationRuntime.recoveryAction,
        agentChange: agentChange
      )
    }

    private func dismissBanner(_ occurrence: NotesPanelBannerOccurrence) {
      withTransaction(Transaction(animation: nil)) {
        bannerDismissalState.dismiss(occurrence)
      }
    }

    private func migrationFailure(
      _ error: FleckProductMigrationError
    ) -> some View {
      VStack(spacing: 12) {
        Image(systemName: "externaldrive.badge.exclamationmark")
          .font(.system(size: 28))
          .foregroundStyle(.orange)
        Text("Fleck needs your help")
          .font(.headline)
        Text(
          "Fleck found both legacy and current note data. Nothing was changed. "
            + "Close Fleck and resolve the two Application Support folders "
            + "before reopening it."
        )
        .font(.callout)
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)
        Text(String(describing: error))
          .font(.caption2.monospaced())
          .foregroundStyle(.tertiary)
          .textSelection(.enabled)
      }
      .padding(24)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .accessibilityElement(children: .combine)
      .accessibilityLabel("Fleck data migration requires attention")
    }

    private var header: some View {
      let backlinkEntries = backlinkController.incoming(to: appState.workspace.selectedNoteID)
      return HStack(spacing: 10) {
        AgentActivityIndicator(
          presentation: appState.agentActivityIndicator
        ) {
          isShowingAgentActivity = true
        }
        Spacer()
        SaveFeedbackView(status: appState.saveStatus, motion: motion)
        Button {
          backlinkController.toggleDisclosure()
        } label: {
          Image(systemName: "link")
            .frame(width: 22, height: 22)
        }
        .accessibilityIdentifier("backlinks-toolbar-button")
        .accessibilityLabel("Backlinks")
        .accessibilityValue(
          backlinkEntries.count == 1
            ? "1 backlink"
            : "\(backlinkEntries.count) backlinks"
        )
        .accessibilityHint("Show notes linking here")
        .help("Backlinks")
        .popover(isPresented: backlinksPopoverPresentation, arrowEdge: .top) {
          BacklinksView(
            entries: backlinkEntries,
            foldersByID: folderNamesByID,
            onOpen: { noteID in
              if backlinkController.isExpanded {
                backlinkController.toggleDisclosure()
              }
              openNoteLink(noteID)
            }
          )
          .frame(width: 320)
        }
        Button {
          let pointerActivation = searchPointerActivationPending
          searchPointerActivationPending = false
          guard !pointerActivation else { return }
          Task { @MainActor in
            await Task.yield()
            guard !searchController.isPresented else { return }
            presentWorkspaceSearch(activation: .keyboard)
          }
        } label: {
          Image(systemName: "magnifyingglass")
            .opacity(searchController.isPresented ? 0 : 1)
            .accessibilityHidden(true)
        }
        .keyboardShortcut("f", modifiers: .command)
        .accessibilityLabel("Search notes")
        .accessibilityHint("Search note titles and bodies")
        .help("Search notes (⌘F)")
        .simultaneousGesture(
          TapGesture().onEnded {
            guard !noteLinkPickerController.isPresented else { return }
            searchPointerActivationPending = true
            presentWorkspaceSearch(activation: .pointer)
          }
        )
        Button {
          appState.addNote(inFolderID: activeFolderID)
        } label: {
          Image(systemName: "plus")
        }
        .keyboardShortcut("t", modifiers: .command)
        .help("New note")

        if isPinned {
          Image(systemName: "pin.fill")
            .frame(width: 22, height: 22)
            .foregroundStyle(.tint)
            .accessibilityLabel("Pinned")
            .help("This window stays open until you close it")
        } else {
          Button {
            presentPersistentWindow {
              openWindow(id: "pinned-notes")
            }
          } label: {
            Image(systemName: "pin")
          }
          .help("Pin notes on screen")
        }

        Button {
          if reduceMotion {
            appState.updatePreferences { $0.showFormattingBar.toggle() }
          } else {
            withAnimation(motion.quick) {
              appState.updatePreferences { $0.showFormattingBar.toggle() }
            }
          }
        } label: {
          Image(systemName: "chevron.up")
            .rotationEffect(
              .degrees(appState.preferences.showFormattingBar ? 0 : 180)
            )
            .animation(
              reduceMotion ? nil : motion.quick,
              value: appState.preferences.showFormattingBar
            )
        }
        .accessibilityLabel(
          appState.preferences.showFormattingBar
            ? "Hide Editor toolbar"
            : "Show Editor toolbar"
        )
        .help(
          appState.preferences.showFormattingBar
            ? "Hide Editor toolbar"
            : "Show Editor toolbar"
        )

        Menu {
          if let note = visibleSelectedNote {
            Button("Add File Shortcut…", systemImage: "paperclip") {
              chooseFile(for: note.id)
            }
            .disabled(!appState.canAddFileReference(noteID: note.id))
            Divider()
          }
          Button("Import…", systemImage: "square.and.arrow.down") {
            isImporting = true
          }
          Divider()
          Button("Export Markdown…") { startExport(.markdown) }
          Button("Export Plain Text…") { startExport(.plainText) }
          Button("Export Rich Text…") { startExport(.richText) }
          Divider()
          Button("Trash…", systemImage: "trash") {
            isShowingTrash = true
          }
          Button("Dictation History", systemImage: "waveform") {
            isShowingDictationHistory = true
          }
          Button("Agent Activity", systemImage: "clock.arrow.circlepath") {
            isShowingAgentActivity = true
          }
          if let note = visibleSelectedNote {
            Button(AgentCapabilityPresentation.manageAgentAccessTitle) {
              notePendingAgentShare = note
            }
          }
        } label: {
          Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("Options")
        .help("Options")

        Button {
          presentPersistentWindow {
            openSettings()
          }
        } label: {
          Image(systemName: "slider.horizontal.3")
        }
        .accessibilityLabel("Customize")
        .help("Customize")
      }
      .buttonStyle(.plain)
      .padding(.horizontal, 14)
      .padding(.vertical, 11)
    }

    private var folderNavigator: some View {
      FolderNavigator(
        draggedSource: $noteDropSource,
        dragSession: $reorderDragSession,
        menuWindowDrop: isPinned ? nil : menuWindowDrop,
        activeFolderID: activeFolderID,
        onSelect: selectFolder,
        onDelete: { folderPendingDeletion = $0 },
        onOpenTrash: { isShowingTrash = true }
      )
      .environmentObject(appState)
    }

    private func selectFolder(_ folderID: UUID?) {
      guard folderID == nil || appState.workspace.folders.contains(where: { $0.id == folderID })
      else { return }
      activeFolderID = folderID
      let visible = appState.visibleNotes(in: folderID)
      guard !visible.contains(where: { $0.id == appState.workspace.selectedNoteID }),
        let first = visible.first
      else { return }
      _ = activateNoteAndScope(first.id)
    }

    private func activateNoteAndScope(_ noteID: UUID) -> Bool {
      guard appState.workspace.notes.contains(where: { $0.id == noteID }) else {
        return false
      }
      activeFolderID = appState.folderID(for: noteID)
      if appState.workspace.selectedNoteID != noteID {
        appState.select(noteID)
      }
      return true
    }

    private func deleteFolder(_ folderID: UUID) {
      let currentFolderID = activeFolderID
      if currentFolderID == folderID {
        activeFolderID = nil
      }
      do {
        try appState.deleteFolder(id: folderID, activeFolderID: currentFolderID)
      } catch {
        if currentFolderID == folderID {
          activeFolderID = folderID
        }
        appState.saveError = "Could not update folder: \(String(describing: error))"
      }
    }

    private func confirmFolderDeletion(_ folder: Folder) {
      folderPendingDeletion = nil
      deleteFolder(folder.id)
    }

    private var tabStrip: some View {
      ScrollViewReader { scrollProxy in
        GeometryReader { proxy in
          let tabViewportWidth = TabOverflowPresentation.tabViewportWidth(totalStripWidth: proxy.size.width)
        HStack(spacing: 0) {
          ZStack(alignment: .trailing) {
            ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: 0) {
                Color.clear
                  .frame(width: 0, height: 0)
                  .id(TabScrollTarget.leading)
                FluidTabStripHost(controller: fluidTabDrag) {
                HStack(spacing: 6) {
                ForEach(visibleNotes) { note in
            Button {
              _ = activateNoteAndScope(note.id)
            } label: {
              HStack(spacing: 4) {
                if note.isPinned {
                  Image(systemName: "pin.fill")
                    .font(.caption2)
                }
                Text(note.displayTitle).lineLimit(1)
                if appState.isSharedWithAnyActiveProfile(note.id) {
                  Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.caption2)
                    .accessibilityLabel(AgentSharingPresentation.sharedBadgeAccessibilityLabel)
                }
              }
              .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
              .padding(.horizontal, 10)
              .padding(.vertical, 6)
              .contentShape(Capsule())
              .background {
                if note.id == appState.workspace.selectedNoteID {
                  Capsule()
                    .fill(tabColor(for: note, opacity: 0.22))
                    .matchedGeometryEffect(id: "selected-tab", in: selectedTabHighlight)
                } else if note.tabColorHex != nil {
                  Capsule()
                    .fill(tabColor(for: note, opacity: 0.10))
                }
              }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("note-tab-\(note.id.uuidString)")
            .modifier(ReorderDragSource(begin: {
              let interaction = ReorderInteraction(sourceID: note.id, originalIDs: visibleNotes.map(\.id),
                pinnedIDs: Set(visibleNotes.filter(\.isPinned).map(\.id)))
              let source = NoteDropSource(
                noteID: note.id,
                sourceFolderID: note.folderID,
                dragSessionID: interaction.sessionID
              )
              let session = ReorderDropSession(source: source)
              reorderDragSession?.cancel()
              reorderDragSession = session
              noteDropSource = source
              fluidTabDrag.prepare(interaction: interaction, session: session,
                currentIDs: { appState.visibleNotes(in: note.folderID).map(\.id) },
                currentPins: { Set(appState.visibleNotes(in: note.folderID).filter(\.isPinned).map(\.id)) },
                move: { id, destination in
                  guard let localDestination = TabDragReorder.partitionLocalDestination(
                    draggedID: id, absoluteDestination: destination,
                    visibleNotes: appState.visibleNotes(in: note.folderID)) else { return }
                  _ = appState.moveNote(id, inFolderID: note.folderID, toVisibleIndex: localDestination)
                }, finish: { if noteDropSource == source { noteDropSource = nil } })
              if !isPinned {
                menuWindowDrop.activate(
                  source: source,
                  session: session,
                  tabController: fluidTabDrag
                )
              }
              return (FolderDragPayload.noteProvider(source: source),
                FolderDragPayload.notePasteboardItem(source: source), { operation in
                session.end(operation: operation)
                fluidTabDrag.ended(sessionID: session.id, operation: operation)
                if !isPinned { menuWindowDrop.deactivate(sessionID: session.id) }
                if noteDropSource == source { noteDropSource = nil }
              })
            }, began: { point in fluidTabDrag.began(at: point) }, moved: { point in fluidTabDrag.moved(to: point) },
              activate: { _ = activateNoteAndScope(note.id) }, noteID: note.id,
              displacement: fluidTabDrag.inside ? fluidTabDrag.preview?.offset(for: note.id) ?? 0 : 0,
              animatesDisplacement: !motion.reduceMotion && fluidTabDrag.animatesDisplacement))
            .transition(
              .opacity.combined(
                with: .offset(x: motion.offset)
              )
            )
            .contextMenu {
              Button(
                note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin"
              ) {
                guard isNoteVisible(note.id) else { return }
                appState.togglePinned(note.id)
              }
              Button("Move Left", systemImage: "arrow.left") {
                move(note, offset: -1)
              }
              Button("Move Right", systemImage: "arrow.right") {
                move(note, offset: 1)
              }
              let moveToFolder: (UUID?) -> Void = { destinationFolderID in
                guard isNoteVisible(note.id),
                  let currentNote = appState.workspace.notes.first(where: { $0.id == note.id })
                else { return }
                _ = appState.moveNote(
                  note.id,
                  fromFolderID: currentNote.folderID,
                  toFolderID: destinationFolderID,
                  activeFolderID: activeFolderID
                )
              }
              Menu("Move to Folder", systemImage: "folder") {
                Button {
                  moveToFolder(nil)
                } label: {
                  HStack {
                    Text("Unfiled")
                    if note.folderID == nil {
                      Spacer()
                      Image(systemName: "checkmark")
                    }
                  }
                }
                .disabled(note.folderID == nil)
                ForEach(appState.workspace.folders, id: \.id) { folder in
                  Button {
                    moveToFolder(folder.id)
                  } label: {
                    HStack {
                      Text(folder.name)
                      if note.folderID == folder.id {
                        Spacer()
                        Image(systemName: "checkmark")
                      }
                    }
                  }
                  .disabled(note.folderID == folder.id)
                }
              }
              Button("Tab Color...", systemImage: "paintpalette") {
                guard isNoteVisible(note.id) else { return }
                tabColorPickerNoteID = note.id
              }
              .accessibilityValue(tabColorAccessibilityValue(for: note.tabColorHex))
              Button(AgentCapabilityPresentation.manageAgentAccessTitle) {
                guard isNoteVisible(note.id) else { return }
                notePendingAgentShare = note
              }
              Divider()
              Button("Move to Trash", systemImage: "trash", role: .destructive) {
                requestDeletion(note)
              }
            }
            .popover(
              isPresented: Binding(
                get: { tabColorPickerNoteID == note.id },
                set: { if !$0 { tabColorPickerNoteID = nil } }
              ),
              arrowEdge: .bottom
            ) {
              tabColorPicker(noteID: note.id)
            }
                }
              }
              .padding(.horizontal, 12)
              .frame(height: 37, alignment: .center)
              .animation(motion.spatial, value: appState.workspace.selectedNoteID)
              .animation(motion.spatial, value: visibleNotes.map(\.id))
              .fixedSize(horizontal: true, vertical: false)
              .frame(minWidth: tabViewportWidth, alignment: .leading)
              }
                Color.clear
                  .frame(width: 0, height: 0)
                  .id(TabScrollTarget.trailing)
              }
            }
          }
          .frame(width: tabViewportWidth, alignment: .leading)

          HStack(spacing: 0) {
            Button {
              scrollProxy.scrollTo(TabScrollTarget.leading, anchor: .leading)
            } label: {
              Image(systemName: "chevron.left")
                .font(.caption)
                .frame(width: 28, height: 28)
                .frame(width: 28, height: 37)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reveal earlier tabs")
            .help("Show earlier tabs")
            .disabled(visibleNotes.isEmpty)

            Button {
              scrollProxy.scrollTo(TabScrollTarget.trailing, anchor: .trailing)
            } label: {
              Image(systemName: "chevron.right")
                .font(.caption)
                .frame(width: 28, height: 28)
                .frame(width: 28, height: 37)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reveal later tabs")
            .help("Show later tabs")
            .disabled(visibleNotes.isEmpty)
          }
          .frame(width: 56, height: 37, alignment: .center)
        }
        }
        .frame(height: 37)
      }
    }

    private var motion: AppMotion {
      AppMotion(reduceMotion: reduceMotion)
    }

    private var workspaceSearchPresentationTransition: AnyTransition {
      switch searchController.presentationKind {
      case .inline:
        return .opacity.combined(
          with: .scale(scale: 0.98, anchor: .topTrailing)
        )
      case .crossfade:
        return .opacity
      case .instant:
        return .identity
      }
    }

    private func presentWorkspaceSearch(activation: WorkspaceSearchActivation) {
      guard !noteLinkPickerController.isPresented else { return }
      let presentation = WorkspaceSearchPresentationKind.resolve(
        activation: activation,
        reduceMotion: reduceMotion
      )
      withAnimation(
        motion.presentationAnimation(for: presentation.interactionSource)
      ) {
        if presentation == .instant {
          searchController.present(for: appState.workspace.selectedNoteID)
        } else {
          searchController.present(
            for: appState.workspace.selectedNoteID,
            presentation: presentation
          )
        }
      }
    }

    private func dismissWorkspaceSearch() {
      guard searchController.isPresented else { return }
      withAnimation(
        searchController.presentationKind.usesAnimatedDismissal ? motion.quick : nil
      ) {
        searchController.dismiss()
      }
    }

    private var backlinksPopoverPresentation: Binding<Bool> {
      Binding(
        get: { backlinkController.isExpanded },
        set: { isPresented in
          guard backlinkController.isExpanded != isPresented else { return }
          backlinkController.toggleDisclosure()
        }
      )
    }

    private func tabColor(for note: Note, opacity: Double) -> Color {
      guard let hex = note.tabColorHex else {
        return Color.accentColor.opacity(opacity)
      }
      let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
      guard cleaned.count == 6, UInt64(cleaned, radix: 16) != nil else {
        return Color.accentColor.opacity(opacity)
      }
      return (Color(hex: hex) ?? .accentColor).opacity(opacity)
    }

    @ViewBuilder
    private func tabColorPicker(noteID: UUID) -> some View {
      if let note = appState.workspace.notes.first(where: { $0.id == noteID }) {
        FleckColorPicker(
          currentHex: note.tabColorHex,
          currentLabel: tabColorAccessibilityValue(for: note.tabColorHex),
          resetTitle: "None",
          onCommit: { hex in commitTabColor(hex, for: noteID) },
          onCancel: { tabColorPickerNoteID = nil }
        )
      } else {
        EmptyView()
      }
    }

    private func commitTabColor(_ hex: String?, for noteID: UUID) {
      guard isNoteVisible(noteID), activateNoteAndScope(noteID) else {
        tabColorPickerNoteID = nil
        return
      }
      appState.setSelectedTabColor(hex)
      tabColorPickerNoteID = nil
    }

    private func tabColorAccessibilityValue(for hex: String?) -> String {
      guard let hex else { return "None" }
      return FleckPaletteOption.paletteName(for: NSColor(hex: hex)) ?? "Custom"
    }

    private func performShortcut(_ action: Shortcut.Action) {
      guard !isBlockingOverlayPresented else { return }
      switch action {
      case .togglePanel:
        NSApp.keyWindow?.orderOut(nil)
      case .newNote:
        appState.addNote(inFolderID: activeFolderID)
      case .closeNote:
        if let note = visibleSelectedNote {
          requestDeletion(note)
        }
      case .nextNote:
        appState.selectAdjacentNote(forward: true, inFolderID: activeFolderID)
      case .previousNote:
        appState.selectAdjacentNote(forward: false, inFolderID: activeFolderID)
      }
    }

    private func requestDeletion(_ note: Note) {
      guard isNoteVisible(note.id) else { return }
      if appState.preferences.confirmBeforeMovingNotesToTrash {
        dontAskAgainForDeletion = false
        notePendingDeletion = note
      } else {
        appState.moveToTrash(note.id, activeFolderID: activeFolderID)
      }
    }

    private func confirmDeletion(_ note: Note) {
      guard isNoteVisible(note.id) else {
        notePendingDeletion = nil
        dontAskAgainForDeletion = false
        return
      }
      let shouldSuppressConfirmation = dontAskAgainForDeletion
      _ = appState.moveToTrash(
        note.id,
        activeFolderID: activeFolderID,
        suppressConfirmation: shouldSuppressConfirmation
      )
      notePendingDeletion = nil
      dontAskAgainForDeletion = false
    }

    private func openHistoryDestination(_ noteID: UUID) {
      if activateNoteAndScope(noteID) {
        isShowingDictationHistory = false
      }
    }

    private func presentPersistentWindow(_ present: () -> Void) {
      NSApp.activate()
      present()
      DispatchQueue.main.async {
        NSApp.activate()
      }
    }

    private func move(_ note: Note, offset: Int) {
      guard isNoteVisible(note.id) else { return }
      guard let index = visibleNotes.firstIndex(where: { $0.id == note.id }) else {
        return
      }
      guard let localDestination = TabDragReorder.partitionLocalDestination(
        draggedID: note.id,
        absoluteDestination: index + offset,
        visibleNotes: visibleNotes
      ) else { return }
      _ = appState.moveNote(
        note.id,
        inFolderID: activeFolderID,
        toVisibleIndex: localDestination
      )
    }

    private func startExport(_ format: NoteExportFormat) {
      guard let note = visibleSelectedNote else { return }
      let export = NoteExport(note: note, format: format)
      exportDocument = NoteFileDocument(data: export.data)
      exportFilename = export.suggestedFilename
      switch format {
      case .plainText: exportType = .plainText
      case .markdown: exportType = NoteFileDocument.markdownContentType
      case .richText: exportType = .rtf
      }
      isExporting = true
    }

    private func importFiles(_ result: Result<[URL], Error>) {
      do {
        for url in try result.get() {
          let accessing = url.startAccessingSecurityScopedResource()
          defer { if accessing { url.stopAccessingSecurityScopedResource() } }
          let note = try NoteImport.note(
            from: Data(contentsOf: url),
            filename: url.lastPathComponent
          )
          appState.importNote(note, intoFolderID: activeFolderID)
        }
        appState.saveError = nil
      } catch {
        appState.saveError = "Import failed: \(error.localizedDescription)"
      }
    }

    private func chooseFile(for noteID: UUID) {
      filePicker.chooseFile(editorCommands.textView?.window) { url in
        Self.completeFileReferenceSelection(url, noteID: noteID, appState: appState)
      }
    }

    static func completeFileReferenceSelection(
      _ url: URL?,
      noteID: UUID,
      appState: AppState
    ) {
      guard let url else { return }
      appState.addFileReference(noteID: noteID, url: url)
    }

    private func openFileReference(_ referenceID: UUID) {
      guard let url = appState.resolveFileReference(referenceID: referenceID) else {
        return
      }
      let didAccess = url.startAccessingSecurityScopedResource()
      NSWorkspace.shared.open(
        url,
        configuration: NSWorkspace.OpenConfiguration()
      ) { _, error in
        Task { @MainActor in
          if didAccess {
            url.stopAccessingSecurityScopedResource()
          }
          if error != nil {
            appState.fileReferenceActionFailed("The file could not be opened.")
          }
        }
      }
    }

    private func revealFileReference(_ referenceID: UUID) {
      guard let url = appState.resolveFileReference(referenceID: referenceID) else {
        return
      }
      let didAccess = url.startAccessingSecurityScopedResource()
      NSWorkspace.shared.activateFileViewerSelecting([url])
      if didAccess {
        url.stopAccessingSecurityScopedResource()
      }
    }

    private func locateFileReference(_ referenceID: UUID) {
      filePicker.chooseFile(editorCommands.textView?.window) { url in
        Self.completeFileReferenceRelink(
          url,
          referenceID: referenceID,
          appState: appState
        )
      }
    }

    static func completeFileReferenceRelink(
      _ url: URL?,
      referenceID: UUID,
      appState: AppState
    ) {
      guard let url else { return }
      appState.relinkFileReference(referenceID: referenceID, url: url)
    }

    static func fileReferenceUndoManager(commands: EditorCommands) -> UndoManager? {
      commands.activeUndoManager
    }

    private var isBlockingOverlayPresented: Bool {
      searchController.isPresented || noteLinkPickerController.isPresented
        || notePendingDeletion != nil || folderPendingDeletion != nil || isShowingTrash
        || isShowingAgentActivity
    }

    private var agentActivitySheetPresentation: Binding<Bool> {
      Binding(
        get: { isPinned && isShowingAgentActivity },
        set: { isShowingAgentActivity = $0 }
      )
    }

    private var agentActivityContent: some View {
      AgentActivityView(
        onOpenNote: { noteID in
          if activateNoteAndScope(noteID) {
            isShowingAgentActivity = false
          }
        },
        onDismiss: { isShowingAgentActivity = false }
      )
      .environmentObject(appState)
    }

    private var agentActivityOverlay: some View {
      ZStack {
        Color.black.opacity(0.28)
          .ignoresSafeArea()
          .accessibilityHidden(true)

        agentActivityContent
          .frame(maxWidth: 520, maxHeight: 400)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
          .clipShape(RoundedRectangle(cornerRadius: 14))
          .shadow(radius: 20, y: 8)
          .accessibilityElement(children: .contain)
          .accessibilityLabel("Agent Activity")
          .padding(8)
      }
    }

    private var folderNamesByID: [UUID: String] {
      Dictionary(uniqueKeysWithValues: appState.workspace.folders.map { ($0.id, $0.name) })
    }

    private func insertNoteLink(targetID: UUID, replacing range: NSRange) {
      guard !searchController.isPresented,
        let sourceID = noteLinkPickerController.presentedSourceNoteID,
        let sourceRevision = noteLinkPickerController.presentedSourceRevision,
        let selectedNote = visibleSelectedNote,
        selectedNote.id == sourceID,
        selectedNote.revision == sourceRevision,
        let target = appState.workspace.notes.first(where: { $0.id == targetID }),
        let textView = editorCommands.textView,
        range.location >= 0,
        NSMaxRange(range) <= (textView.string as NSString).length
      else {
        noteLinkPickerController.dismiss()
        return
      }

      guard editorCommands.insertNoteLink(
        replacing: range,
        label: target.displayTitle,
        targetNoteID: target.id
      ) else {
        noteLinkPickerController.dismiss()
        return
      }
    }

    private func openNoteLink(_ noteID: UUID) {
      guard appState.workspace.notes.contains(where: { $0.id == noteID }) else {
        appState.saveError = "Note unavailable"
        return
      }
      guard activateNoteAndScope(noteID) else {
        appState.saveError = "Note unavailable"
        return
      }
      DispatchQueue.main.async {
        guard self.visibleSelectedNote?.id == noteID,
          let textView = self.editorCommands.textView,
          let window = textView.window
        else { return }
        _ = window.makeFirstResponder(textView)
      }
    }

    private var visibleNotes: [Note] {
      appState.visibleNotes(in: activeFolderID)
    }

    private var visibleSelectedNote: Note? {
      guard let selectedID = appState.workspace.selectedNoteID else { return nil }
      return visibleNotes.first(where: { $0.id == selectedID })
    }

    private func isNoteVisible(_ noteID: UUID) -> Bool {
      visibleNotes.contains(where: { $0.id == noteID })
    }

    private var isEditorVisible: Bool {
      guard let selectedID = appState.workspace.selectedNoteID else { return false }
      return visibleNotes.contains(where: { $0.id == selectedID })
    }

    @ViewBuilder
    private var scopedEditor: some View {
      ZStack {
        editor
          .opacity(isEditorVisible ? 1 : 0)
          .allowsHitTesting(isEditorVisible)
          .accessibilityHidden(!isEditorVisible)

        if visibleNotes.isEmpty {
          VStack(spacing: 10) {
            ContentUnavailableView(
              activeFolderID == nil ? "Unfiled is Empty" : "Folder is Empty",
              systemImage: activeFolderID == nil ? "tray" : "folder",
              description: Text("Create a note here to get started.")
            )
            Button("New note") {
              appState.addNote(inFolderID: activeFolderID)
            }
            .keyboardShortcut("t", modifiers: .command)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .accessibilityElement(children: .contain)
          .accessibilityLabel(
            activeFolderID == nil ? "Unfiled is empty" : "Folder is empty"
          )
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .onChange(of: isEditorVisible) { _, isVisible in
        if isVisible {
          let restoreBodyFocus = restoreEditorFocusAfterHide
          restoreEditorFocusAfterHide = false
          DispatchQueue.main.async {
            guard self.isEditorVisible,
              let textView = self.editorCommands.textView,
              let window = textView.window
            else { return }
            self.editorCommands.refreshFormattingState()
            if restoreBodyFocus {
              _ = window.makeFirstResponder(textView)
            }
          }
        } else {
          let textView = editorCommands.textView
          restoreEditorFocusAfterHide = textView?.window?.firstResponder === textView
          neutralizeHiddenEditor()
        }
      }
    }

    private func neutralizeHiddenEditor() {
      let textView = editorCommands.textView
      editorCommands.cancelFocusedDictation()
      if let window = textView?.window {
        _ = window.makeFirstResponder(nil)
      }
      editorCommands.textView = nil
    }

    private var storedPanelSize: CGSize? {
      guard sizing == .storedPreferences else { return nil }
      let preferred = CGSize(
        width: appState.preferences.panelWidth,
        height: appState.preferences.panelHeight
      )
      let screen = editorCommands.textView?.window?.screen
        ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
        ?? NSScreen.main
      guard let available = screen?.visibleFrame.size,
        available.width > 0,
        available.height > 0
      else { return preferred }
      return NotesPanelSizing.storedSize(preferred: preferred, available: available)
    }

    @ViewBuilder
    private var editor: some View {
      if let note = appState.selectedNote {
        VStack(spacing: 0) {
          DictationShortcutHelpRow(
            presentation: modifierShortcutPresentation,
            onRecovery: {
              Task { @MainActor in
                await dictationRuntime.performModifierShortcutRecovery {
                  dictationRuntime.openSystemSettings($0)
                }
              }
            }
          )
          if appState.preferences.showFormattingBar {
            FormattingBar(
              appState: appState,
              commands: editorCommands,
              dictationRuntime: dictationRuntime,
              isPinned: isPinned,
              isEditorVisible: isEditorVisible,
              isTitleFocused: editorFocus == .title,
              onDelete: {
                if let note = visibleSelectedNote {
                  requestDeletion(note)
                }
              }
            )
            .transition(
              .asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity)
              )
            )
            .animation(reduceMotion ? nil : motion.quick, value: appState.preferences.showFormattingBar)
          }
          if !appState.selectedNoteFileReferences.isEmpty {
            NoteFileReferenceView(
              references: appState.selectedNoteFileReferences,
              onOpen: openFileReference,
              onReveal: revealFileReference,
              onLocate: locateFileReference,
              onRemove: { referenceID in
                appState.removeFileReference(
                  referenceID: referenceID,
                  undoManager: Self.fileReferenceUndoManager(commands: editorCommands)
                )
              }
            )
          }
          NativeRichTextEditor(
            text: note.body,
            richTextRTF: note.richTextRTF,
            title: note.title,
            titleFontFamily: note.titleFontFamily ?? appState.preferences.fontFamily,
            onTitleChange: { title in
              guard visibleSelectedNote?.id == note.id else { return }
              appState.updateSelected(title: title)
            },
            onTitleFocusChange: { isFocused in
              if isFocused {
                editorFocus = .title
              } else if editorFocus == .title {
                editorFocus = nil
              }
            },
            onChange: { body, richTextRTF in
              guard visibleSelectedNote?.id == note.id else { return }
              appState.updateSelected(body: body, richTextRTF: richTextRTF)
            },
            fontFamily: appState.preferences.fontFamily,
            fontSize: appState.preferences.fontSize,
            textColorHex: appState.preferences.editorTextHex,
            backgroundColorHex: appState.preferences.editorBackgroundHex,
            accentColorHex: appState.preferences.accentHex,
            reduceMotion: reduceMotion,
            automaticLists: appState.preferences.automaticLists,
            commands: editorCommands,
            isVisible: isEditorVisible,
            liveNoteIDs: Set(appState.workspace.notes.map(\.id)),
            onRequestNoteLink: { range in
              guard !isBlockingOverlayPresented,
                let source = visibleSelectedNote,
                source.id == note.id
              else { return }
              noteLinkPickerController.present(
                sourceNoteID: source.id,
                replacementRange: range,
                sourceRevision: source.revision
              )
            },
            onOpenNoteLink: openNoteLink,
            onUnavailableNoteLink: { appState.saveError = "Note unavailable" }
          )
          .focused($editorFocus, equals: .body)
          .background(
            EditorCommandVisibilityBoundary(
              appState: appState,
              dictationRuntime: dictationRuntime,
              commands: editorCommands,
              isVisible: isEditorVisible
            )
            .frame(width: 0, height: 0)
          )
          .id(note.id)
          .padding(.vertical, 10)
        }
      }
    }
  }

  private struct EditorCommandVisibilityBoundary: NSViewRepresentable {
    @ObservedObject var appState: AppState
    @ObservedObject var dictationRuntime: DictationRuntime
    let commands: EditorCommands
    let isVisible: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
      context.coordinator.isActive = true
      return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
      let generation = context.coordinator.beginUpdate(isVisible: isVisible)
      guard !isVisible else { return }
      DispatchQueue.main.async {
        guard context.coordinator.isActive,
          context.coordinator.generation == generation,
          !context.coordinator.isVisible
        else { return }
        let textView = commands.textView
        commands.cancelFocusedDictation()
        if let window = textView?.window {
          _ = window.makeFirstResponder(nil)
        }
        commands.textView = nil
      }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
      coordinator.isActive = false
      coordinator.generation &+= 1
    }

    final class Coordinator {
      var isVisible = true
      var isActive = true
      var generation: UInt64 = 0

      func beginUpdate(isVisible: Bool) -> UInt64 {
        generation &+= 1
        self.isVisible = isVisible
        return generation
      }
    }
  }

  private struct FolderNavigator: View {
    private enum FocusedRow: Hashable {
      case unfiled
      case folder(UUID)
      case trash
      case newFolder
    }

    private enum NoteDropTarget: Equatable {
      case unfiled
      case folder(UUID)

      var folderID: UUID? {
        switch self {
        case .unfiled: return nil
        case .folder(let id): return id
        }
      }
    }

    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedRow: FocusedRow?
    @FocusState private var isUnfiledDisclosureFocused: Bool
    @Binding private var draggedSource: NoteDropSource?
    @Binding private var dragSession: ReorderDropSession?
    @State private var editingFolderID: UUID?
    @State private var isCreatingFolder = false
    @State private var folderNameDraft = ""
    @State private var noteDropTarget: NoteDropTarget?
    @State private var folderReorder: ReorderInteraction?
    @State private var isUnfiledHovered = false
    @State private var unfiledInteractionSource: AppInteractionSource = .keyboard
    private let folderNavigatorMaxHeight: CGFloat = 32

    let menuWindowDrop: MenuWindowNoteDropCoordinator?
    let activeFolderID: UUID?
    let onSelect: (UUID?) -> Void
    let onDelete: (Folder) -> Void
    let onOpenTrash: () -> Void

    init(
      draggedSource: Binding<NoteDropSource?>,
      dragSession: Binding<ReorderDropSession?>,
      menuWindowDrop: MenuWindowNoteDropCoordinator?,
      activeFolderID: UUID?,
      onSelect: @escaping (UUID?) -> Void,
      onDelete: @escaping (Folder) -> Void,
      onOpenTrash: @escaping () -> Void
    ) {
      self._draggedSource = draggedSource
      self._dragSession = dragSession
      self.menuWindowDrop = menuWindowDrop
      self.activeFolderID = activeFolderID
      self.onSelect = onSelect
      self.onDelete = onDelete
      self.onOpenTrash = onOpenTrash
    }

    var body: some View {
      VStack(spacing: 3) {
        if isCreatingFolder {
          folderEditor(label: "New folder", focus: .newFolder)
        }

        HStack(spacing: 4) {
          rootRow

          ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 3) {
              ForEach(appState.workspace.folders, id: \.id) { folder in
                folderRow(folder)
              }
            }
            .background(ReorderDragLifecycle(active: folderReorder != nil,
              hasTarget: folderReorder?.targetID != nil
                && folderReorder?.originalIDs == appState.workspace.folders.map(\.id),
              cancel: { folderReorder = nil }))
          }
          .frame(maxWidth: .infinity)
          .frame(maxHeight: folderNavigatorMaxHeight)
          .accessibilityElement(children: .contain)
          .accessibilityLabel("Folders")

          Button {
            beginNewFolder()
          } label: {
            Image(systemName: "folder.badge.plus")
              .frame(width: 24, height: 24)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("New folder")

          Divider()
            .frame(height: 20)

          Button {
            onOpenTrash()
          } label: {
            rowLabel(
              name: "Trash",
              systemImage: "trash",
              count: appState.trashedNotes.count,
              isSelected: false,
              isEmpty: appState.trashedNotes.isEmpty
            )
          }
          .fixedSize(horizontal: true, vertical: false)
          .buttonStyle(.plain)
          .focused($focusedRow, equals: .trash)
          .focusable()
          .accessibilityLabel("Trash")
          .accessibilityIdentifier("folder-trash")
          .accessibilityValue(
            appState.trashedNotes.isEmpty
              ? "Empty"
              : "\(appState.trashedNotes.count) notes"
          )
        }
        .animation(
          motion.allowsSpatialMotion(for: unfiledInteractionSource) ? folderMorphAnimation : nil,
          value: isUnfiledCompact
        )
      }
      .animation(folderMorphAnimation, value: isCreatingFolder)
      .onChange(of: draggedSource) { oldValue, newValue in
        if oldValue != newValue {
          noteDropTarget = nil
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 5)
      .onMoveCommand { direction in
        moveFocus(direction)
      }
      .onDeleteCommand {
        guard case .folder(let id) = focusedRow,
          let folder = appState.workspace.folders.first(where: { $0.id == id })
        else { return }
        onDelete(folder)
      }
      .onChange(of: appState.workspace.folders.map(\.id)) { _, ids in
        if let folderReorder, folderReorder.originalIDs != ids { self.folderReorder = nil }
      }
      .onDisappear { folderReorder = nil }
      .onExitCommand {
        folderReorder = nil
        cancelFolderEditing()
      }
      .onKeyPress(phases: .down) { press in
        guard isF2(press), beginRename() else { return .ignored }
        return .handled
      }
      .onKeyPress(keys: [.return, .space], phases: .down) { _ in
        activateFocusedRow()
        return .handled
      }
    }

    private var rootRow: some View {
      let unfiledNotes = appState.visibleNotes(in: nil)
      return HStack(spacing: 0) {
        Button {
          onSelect(nil)
        } label: {
          rowLabel(
            name: "Unfiled",
            systemImage: "tray",
            count: unfiledNotes.count,
            isSelected: activeFolderID == nil,
            isEmpty: unfiledNotes.isEmpty,
            isDropTarget: isNoteDropTarget(.unfiled),
            isFocused: focusedRow == .unfiled,
            showsName: !isUnfiledCompact,
            revealsName: true
          )
        }
        .buttonStyle(.plain)
        .modifier(
          FolderRowFocusPublisher(onFocusChange: { isFocused in
            updateFocusedRow(.unfiled, isFocused: isFocused)
          })
        )
        .focusable()
        .focused($focusedRow, equals: .unfiled)
        .focusEffectDisabled()
        .accessibilityLabel("Unfiled")
        .accessibilityIdentifier("folder-unfiled")
        .accessibilityValue(unfiledAccessibilityValue)
        .accessibilityAddTraits(activeFolderID == nil ? .isSelected : [])
        .accessibilityAction(named: Text("Toggle Unfiled compact mode")) {
          setUnfiledCompact(!isUnfiledCompact)
        }

        Button {
          let isPointer = NSApp.currentEvent.map {
            [.leftMouseDown, .leftMouseUp].contains($0.type)
          } ?? false
          setUnfiledCompact(!isUnfiledCompact, source: isPointer ? .pointer : .keyboard)
        } label: {
          Image(systemName: "chevron.right")
            .rotationEffect(.degrees(isUnfiledCompact ? 0 : 180))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
          isUnfiledCompact ? "Expand Unfiled" : "Collapse Unfiled"
        )
        .focusable()
        .focused($isUnfiledDisclosureFocused)
        .onKeyPress(keys: [.return, .space], phases: .down) { _ in
          setUnfiledCompact(!isUnfiledCompact)
          return .handled
        }
        .opacity(showsUnfiledDisclosure ? 1 : 0)
        .frame(width: showsUnfiledDisclosure ? 28 : 0, alignment: .leading)
        .clipped()
        .allowsHitTesting(showsUnfiledDisclosure)
        .accessibilityHidden(!showsUnfiledDisclosure)
      }
      .fixedSize(horizontal: true, vertical: false)
      .onHover { isUnfiledHovered = $0 }
      .contentShape(Rectangle())
      .background(nativeNoteDropAnchor(.unfiled))
      .onDrop(
        of: [FolderDragPayload.noteType],
        delegate: noteDropDelegate(.unfiled)
      )
    }

    @ViewBuilder
    private func folderRow(_ folder: Folder) -> some View {
      if editingFolderID == folder.id {
        folderEditor(label: "Folder name", focus: .folder(folder.id))
      } else {
        Button {
          onSelect(folder.id)
        } label: {
          rowLabel(
            name: folder.name,
            systemImage: "folder",
            count: appState.visibleNotes(in: folder.id).count,
            isSelected: activeFolderID == folder.id,
            isEmpty: appState.visibleNotes(in: folder.id).isEmpty,
            isDropTarget: isNoteDropTarget(.folder(folder.id)),
            isFocused: focusedRow == .folder(folder.id)
          )
        }
        .buttonStyle(.plain)
        .modifier(
          FolderRowFocusPublisher(onFocusChange: { isFocused in
            updateFocusedRow(.folder(folder.id), isFocused: isFocused)
          })
        )
        .focusable()
        .focused($focusedRow, equals: .folder(folder.id))
        .focusEffectDisabled()
        .background(nativeNoteDropAnchor(.folder(folder.id)))
        .modifier(ReorderDropTarget(
          destinationID: folder.id, type: FolderDragPayload.folderType,
          interaction: $folderReorder,
          session: $dragSession,
          currentIDs: { appState.workspace.folders.map(\.id) },
          currentPinnedIDs: { [] },
          accepts: { true },
          finish: {},
          move: { id, destination in try? appState.reorderFolder(id: id, to: destination) },
          noteDrop: noteDropDelegate(.folder(folder.id))
        ))
        .modifier(ReorderDragSource(begin: {
          let interaction = ReorderInteraction(sourceID: folder.id,
            originalIDs: appState.workspace.folders.map(\.id))
          let session = ReorderDropSession(folder:
            .init(folderID: folder.id, sessionID: interaction.sessionID))
          dragSession?.cancel()
          dragSession = session
          folderReorder = interaction
          return (FolderDragPayload.folderProvider(folderID: folder.id, sessionID: interaction.sessionID), nil, { operation in
            session.end(operation: operation)
            guard folderReorder?.sessionID == interaction.sessionID else { return }
            folderReorder = nil
          })
        }))
        .contextMenu {
          Button("Move Left", systemImage: "arrow.left") { moveFolder(folder.id, offset: -1) }
          Button("Move Right", systemImage: "arrow.right") { moveFolder(folder.id, offset: 1) }
          Button("Rename", systemImage: "pencil") {
            _ = beginRename(folderID: folder.id)
          }
          Button("Delete", systemImage: "trash", role: .destructive) {
            onDelete(folder)
          }
        }
        .accessibilityLabel(folder.name)
        .accessibilityIdentifier("folder-\(folder.id.uuidString)")
        .accessibilityValue(
          "\(appState.visibleNotes(in: folder.id).count) notes"
            + (activeFolderID == folder.id ? ", Selected" : "")
            + (appState.visibleNotes(in: folder.id).isEmpty ? ", Empty" : "")
            + (isNoteDropTarget(.folder(folder.id)) ? ", Drop target" : "")
        )
        .accessibilityAddTraits(activeFolderID == folder.id ? .isSelected : [])
      }
    }

    private struct FolderActionButtonStyle: ButtonStyle {
      enum Role: Equatable {
        case save
        case cancel
      }

      let role: Role
      let accent: Color
      let motion: AppMotion
      @Environment(\.isEnabled) private var isEnabled

      func makeBody(configuration: Configuration) -> some View {
        let isSave = role == .save
        return configuration.label
          .font(.caption.weight(isSave ? .semibold : .medium))
          .foregroundStyle(isSave ? accent : Color.secondary)
          .frame(height: 22)
          .padding(.horizontal, 8)
          .background(
            isSave
              ? accent.opacity(configuration.isPressed ? 0.24 : 0.16)
              : Color.primary.opacity(configuration.isPressed ? 0.10 : 0.06),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
          )
          .scaleEffect(isEnabled && configuration.isPressed ? motion.pressScale : 1)
          .opacity(isEnabled ? 1 : 0.48)
          .animation(motion.quick, value: configuration.isPressed)
      }
    }

    @ViewBuilder
    private func folderEditor(label: String, focus: FocusedRow) -> some View {
      let accent = Color(hex: appState.preferences.accentHex) ?? .accentColor
      HStack(spacing: 5) {
        TextField(label, text: $folderNameDraft)
          .textFieldStyle(.roundedBorder)
          .focused($focusedRow, equals: focus)
          .onSubmit { commitFolderEditing() }
          .onExitCommand { cancelFolderEditing() }
        Button("Save") { commitFolderEditing() }
          .buttonStyle(FolderActionButtonStyle(role: .save, accent: accent, motion: motion))
          .disabled(
            folderNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          )
          .accessibilityLabel("Save folder name")
        Button("Cancel", role: .cancel) { cancelFolderEditing() }
          .buttonStyle(FolderActionButtonStyle(role: .cancel, accent: accent, motion: motion))
          .accessibilityLabel("Cancel folder name")
      }
      .accessibilityElement(children: .contain)
    }

    private struct FolderRowFocusPublisher: ViewModifier {
      @Environment(\.isFocused) private var isNativeFocused
      let onFocusChange: (Bool) -> Void

      init(onFocusChange: @escaping (Bool) -> Void) {
        self.onFocusChange = onFocusChange
      }

      func body(content: Content) -> some View {
        content.onChange(of: isNativeFocused) { _, isFocused in
          onFocusChange(isFocused)
        }
      }
    }

    @ViewBuilder
    private func rowLabel(
      name: String,
      systemImage: String,
      count: Int,
      isSelected: Bool,
      isEmpty: Bool,
      isDropTarget: Bool = false,
      isFocused: Bool = false,
      showsName: Bool = true,
      revealsName: Bool = false
    ) -> some View {
      HStack(spacing: 7) {
        Image(systemName: systemImage)
          .frame(width: 18)
        if revealsName {
          HStack(spacing: 0) {
            Text(name)
              .lineLimit(1)
              .fixedSize()
              .opacity(showsName ? 1 : 0)
              .frame(width: showsName ? nil : 0, alignment: .leading)
              .clipped()
              .padding(.trailing, showsName ? 7 : 0)
            Spacer(minLength: showsName ? 4 : 2)
          }
        } else {
          Text(name)
            .lineLimit(1)
          Spacer(minLength: 4)
        }
        Text(count, format: .number)
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .frame(minHeight: 24)
      .background(
        isDropTarget
          ? Color.accentColor.opacity(0.28)
          : (isSelected ? Color.accentColor.opacity(0.18) : .clear),
        in: RoundedRectangle(cornerRadius: 6)
      )
      .contentShape(RoundedRectangle(cornerRadius: 6))
      .overlay {
        if isFocused && !isSelected {
          RoundedRectangle(cornerRadius: 6)
            .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
        }
      }
      .accessibilityHint(isEmpty ? "Empty folder" : "")
    }

    private func noteDropDelegate(_ target: NoteDropTarget) -> NoteDropDelegate {
      NoteDropDelegate(
        target: target,
        draggedSource: $draggedSource,
        dropTarget: $noteDropTarget,
        canAccept: { expectedSource, targetFolderID in
          canHighlightNoteDrop(
            expectedSource: expectedSource,
            targetFolderID: targetFolderID
          )
        },
        perform: { providers, targetFolderID, expectedSource in
          handleNoteDrop(
            providers,
            targetFolderID: targetFolderID,
            expectedSource: expectedSource
          )
        }
      )
    }

    @ViewBuilder
    private func nativeNoteDropAnchor(_ target: NoteDropTarget) -> some View {
      if let menuWindowDrop {
        MenuWindowFolderDropAnchor(
          coordinator: menuWindowDrop,
          canAccept: { data in
            guard let source = FolderDragPayload.noteValue(from: data) else { return false }
            return canHighlightNoteDrop(
              expectedSource: source,
              targetFolderID: target.folderID
            )
          },
          perform: { data in
            guard let source = FolderDragPayload.noteValue(from: data) else { return false }
            return handleNoteDrop(
              data,
              targetFolderID: target.folderID,
              expectedSource: source
            )
          },
          setHovered: { hovered in
            if hovered {
              noteDropTarget = target
            } else if noteDropTarget == target {
              noteDropTarget = nil
            }
          }
        )
      }
    }

    private func isNoteDropTarget(_ target: NoteDropTarget) -> Bool {
      guard let draggedSource else { return false }
      return noteDropTarget == target
        && canHighlightNoteDrop(
          expectedSource: draggedSource,
          targetFolderID: target.folderID
        )
    }

    private func canHighlightNoteDrop(
      expectedSource: NoteDropSource,
      targetFolderID: UUID?
    ) -> Bool {
      guard draggedSource == expectedSource, dragSession?.id == expectedSource.dragSessionID,
        dragSession?.canAcceptDrop == true else { return false }
      return NoteDropPresentation.isValidTarget(
        draggedSource: expectedSource,
        targetFolderID: targetFolderID,
        notes: appState.workspace.notes,
        validTargetFolderIDs: Set(appState.workspace.folders.map(\.id))
      )
    }

    private var isUnfiledCompact: Bool {
      appState.preferences.isUnfiledCompact
    }

    private var unfiledAccessibilityValue: String {
      let notes = appState.visibleNotes(in: nil)
      var parts = ["\(notes.count) notes"]
      if activeFolderID == nil { parts.append("Selected") }
      if notes.isEmpty { parts.append("Empty") }
      if isUnfiledCompact { parts.append("Compact") }
      if isNoteDropTarget(.unfiled) { parts.append("Drop target") }
      return parts.joined(separator: ", ")
    }

    private var showsUnfiledDisclosure: Bool {
      !isUnfiledCompact || isUnfiledHovered || focusedRow == .unfiled
        || isUnfiledDisclosureFocused
    }

    private func setUnfiledCompact(
      _ compact: Bool,
      source: AppInteractionSource = .keyboard
    ) {
      unfiledInteractionSource = source
      appState.updatePreferences { $0.isUnfiledCompact = compact }
    }

    private var motion: AppMotion {
      AppMotion(reduceMotion: reduceMotion)
    }

    private var folderMorphAnimation: Animation? {
      reduceMotion ? nil : .smooth(duration: 0.22, extraBounce: 0)
    }

    private func beginNewFolder() {
      editingFolderID = nil
      isCreatingFolder = true
      folderNameDraft = ""
      focusedRow = .newFolder
    }

    private func beginRename(folderID: UUID? = nil) -> Bool {
      let id: UUID?
      if let folderID {
        id = folderID
      } else if case .folder(let focusedID) = focusedRow {
        id = focusedID
      } else {
        id = nil
      }
      guard let id,
        let folder = appState.workspace.folders.first(where: { $0.id == id })
      else { return false }
      isCreatingFolder = false
      editingFolderID = id
      folderNameDraft = folder.name
      focusedRow = .folder(id)
      return true
    }

    private func commitFolderEditing() {
      do {
        if isCreatingFolder {
          _ = try appState.createFolder(named: folderNameDraft)
        } else if let editingFolderID {
          try appState.renameFolder(id: editingFolderID, name: folderNameDraft)
        }
        cancelFolderEditing()
      } catch {
        appState.saveError = "Could not update folder: \(String(describing: error))"
      }
    }

    private func cancelFolderEditing() {
      editingFolderID = nil
      isCreatingFolder = false
      folderNameDraft = ""
      focusedRow = nil
    }

    private func updateFocusedRow(_ row: FocusedRow, isFocused: Bool) {
      if isFocused {
        focusedRow = row
      } else if focusedRow == row {
        focusedRow = nil
      }
    }

    private func activateFocusedRow() {
      switch focusedRow {
      case .unfiled:
        onSelect(nil)
      case .folder(let id):
        onSelect(id)
      case .trash:
        onOpenTrash()
      case .newFolder, nil:
        break
      }
    }

    private func moveFocus(_ direction: MoveCommandDirection) {
      let rows: [FocusedRow] = [.unfiled]
        + appState.workspace.folders.map { .folder($0.id) }
        + [.trash]
      guard !rows.isEmpty else { return }
      let currentIndex = focusedRow.flatMap { rows.firstIndex(of: $0) } ?? 0
      focusedRow = rows[
        FolderNavigatorFocus.nextIndex(
          currentIndex: currentIndex,
          direction: direction,
          count: rows.count
        )
      ]
    }

    private func isF2(_ press: KeyPress) -> Bool {
      press.characters.unicodeScalars.contains { $0.value == UInt32(NSF2FunctionKey) }
    }

    private func handleNoteDrop(
      _ providers: [NSItemProvider],
      targetFolderID: UUID?,
      expectedSource: NoteDropSource
    ) -> Bool {
      noteDropTarget = nil
      defer { if draggedSource == expectedSource { draggedSource = nil } }
      guard draggedSource == expectedSource, let dragSession,
        dragSession.id == expectedSource.dragSessionID
      else { return false }
      let capturedScope = activeFolderID
      return dragSession.acceptNoteTransfer(from: providers, source: expectedSource,
        targetFolderID: targetFolderID,
        currentSourceNotes: { appState.visibleNotes(in: expectedSource.sourceFolderID) },
        validTargetFolderIDs: { Set(appState.workspace.folders.map(\.id)) }
      ) { source, target in
        appState.moveNote(source.noteID, fromFolderID: source.sourceFolderID,
          toFolderID: target, activeFolderID: capturedScope)
      } != nil
    }

    private func handleNoteDrop(
      _ data: Data,
      targetFolderID: UUID?,
      expectedSource: NoteDropSource
    ) -> Bool {
      noteDropTarget = nil
      defer { if draggedSource == expectedSource { draggedSource = nil } }
      guard draggedSource == expectedSource, let dragSession,
        dragSession.id == expectedSource.dragSessionID
      else { return false }
      let capturedScope = activeFolderID
      return dragSession.acceptNoteTransfer(data: data, source: expectedSource,
        targetFolderID: targetFolderID,
        currentSourceNotes: { appState.visibleNotes(in: expectedSource.sourceFolderID) },
        validTargetFolderIDs: { Set(appState.workspace.folders.map(\.id)) }
      ) { source, target in
        appState.moveNote(source.noteID, fromFolderID: source.sourceFolderID,
          toFolderID: target, activeFolderID: capturedScope)
      }
    }

    private struct NoteDropDelegate: DropDelegate {
      let target: NoteDropTarget
      @Binding var draggedSource: NoteDropSource?
      @Binding var dropTarget: NoteDropTarget?
      let canAccept: (NoteDropSource, UUID?) -> Bool
      let perform: ([NSItemProvider], UUID?, NoteDropSource) -> Bool

      private func matchingSource(_ info: DropInfo) -> NoteDropSource? {
        guard let expectedSource = draggedSource,
          info.hasItemsConforming(to: [FolderDragPayload.noteType]),
          canAccept(expectedSource, target.folderID)
        else { return nil }
        return expectedSource
      }

      func validateDrop(info: DropInfo) -> Bool {
        matchingSource(info) != nil
      }

      func dropEntered(info: DropInfo) {
        if matchingSource(info) != nil {
          dropTarget = target
        } else if dropTarget == target {
          dropTarget = nil
        }
      }

      func dropUpdated(info: DropInfo) -> DropProposal? {
        guard matchingSource(info) != nil else { return nil }
        return DropProposal(operation: .move)
      }

      func dropExited(info: DropInfo) {
        if dropTarget == target { dropTarget = nil }
      }

      func performDrop(info: DropInfo) -> Bool {
        guard let expectedSource = matchingSource(info)
        else {
          if dropTarget == target { dropTarget = nil }
          return false
        }
        guard canAccept(expectedSource, target.folderID) else {
          if draggedSource == expectedSource { draggedSource = nil }
          if dropTarget == target { dropTarget = nil }
          return false
        }
        dropTarget = nil
        let accepted = perform(
          info.itemProviders(for: [FolderDragPayload.noteType]),
          target.folderID,
          expectedSource
        )
        if !accepted && draggedSource == expectedSource { draggedSource = nil }
        return accepted
      }
    }

    private func moveFolder(_ id: UUID, offset: Int) {
      guard let index = appState.workspace.folders.firstIndex(where: { $0.id == id }) else { return }
      try? appState.reorderFolder(id: id,
        to: min(max(index + offset, 0), appState.workspace.folders.count - 1))
    }

  }

  struct TrashPanelOverlay: View {
    let onDone: () -> Void

    var body: some View {
      ZStack {
        Color.black.opacity(0.28)
          .ignoresSafeArea()
          .accessibilityHidden(true)

        TrashView(onDone: onDone)
          .frame(maxWidth: 520, maxHeight: 400)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
          .clipShape(RoundedRectangle(cornerRadius: 14))
          .shadow(radius: 20, y: 8)
          .accessibilityElement(children: .contain)
          .accessibilityLabel("Trash")
          .padding(8)

        Button("Close Trash", action: onDone)
          .keyboardShortcut(.cancelAction)
          .frame(width: 0, height: 0)
          .opacity(0)
          .accessibilityHidden(true)
      }
    }
  }

  struct FolderDeleteConfirmationOverlay: View {
    let folder: Folder
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
      ZStack {
        Color.black.opacity(0.28)
          .ignoresSafeArea()
          .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: 16) {
          VStack(alignment: .leading, spacing: 6) {
            Text("Delete \(folder.name)?")
              .font(.headline)
            Text("Notes in this folder move to Unfiled. No notes are deleted.")
              .font(.callout)
              .foregroundStyle(.secondary)
          }

          HStack {
            Spacer()
            Button("Cancel", role: .cancel, action: onCancel)
              .keyboardShortcut(.cancelAction)
            Button("Delete Folder", role: .destructive, action: onConfirm)
              .keyboardShortcut(.defaultAction)
          }
        }
        .padding(20)
        .frame(maxWidth: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 20, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Delete folder confirmation")
      }
    }
  }

  private struct DeleteConfirmationOverlay: View {
    let note: Note
    @Binding var dontAskAgain: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
      ZStack {
        Color.black.opacity(0.28)
          .ignoresSafeArea()

        VStack(alignment: .leading, spacing: 16) {
          VStack(alignment: .leading, spacing: 6) {
            Text("Move “\(note.displayTitle)” to Trash?")
              .font(.headline)
            Text("This note can be restored from Trash for 30 days.")
              .font(.callout)
              .foregroundStyle(.secondary)
          }

          Toggle("Don't ask me again", isOn: $dontAskAgain)
            .toggleStyle(.checkbox)

          HStack {
            Spacer()
            Button("Cancel", role: .cancel, action: onCancel)
              .keyboardShortcut(.cancelAction)
            Button("Confirm", role: .destructive, action: onConfirm)
              .keyboardShortcut(.defaultAction)
          }
        }
        .padding(20)
        .frame(maxWidth: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 20, y: 8)
      }
    }
  }

  func routeFontFamilyAction(
    family: String,
    isTitleFocused: Bool,
    titleMutation: (String) -> Void,
    bodyMutation: (String) -> Void
  ) {
    if isTitleFocused {
      titleMutation(family)
    } else {
      bodyMutation(family)
    }
  }

  struct DictationShortcutHelpRow: View {
    let presentation: DictationModifierSettingsPresentation
    let onRecovery: () -> Void

    var body: some View {
      HStack(spacing: 8) {
        Image(systemName: presentation.recoveryAction == nil
          ? "keyboard"
          : "keyboard.badge.ellipsis")
          .foregroundStyle(.secondary)
        VStack(alignment: .leading, spacing: 1) {
          Text(presentation.statusCopy)
            .font(.caption)
          if let detail = presentation.detailCopy {
            Text(detail)
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
        Spacer(minLength: 8)
        if let title = presentation.recoveryButtonTitle {
          Button(title, action: onRecovery)
            .accessibilityLabel(title)
        }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.quaternary.opacity(0.35))
      .accessibilityElement(children: .contain)
      .accessibilityLabel(presentation.capsuleAccessibilityLabel)
    }
  }

  private struct FormattingBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var appState: AppState
    @ObservedObject var commands: EditorCommands
    @ObservedObject var dictationRuntime: DictationRuntime
    let isPinned: Bool
    let isEditorVisible: Bool
    let isTitleFocused: Bool
    let onDelete: () -> Void
    @State private var fontPickerTarget: FontPickerTarget?
    @State private var isFontPickerPresented = false
    @State private var fontSizeText = ""
    @FocusState private var isFontSizeFocused: Bool
    @State private var isFontSizePickerPresented = false
    @State private var fontSizePickerNoteID: UUID?
    @State private var isForegroundColorPickerPresented = false
    @State private var isBackgroundColorPickerPresented = false

    var body: some View {
      GeometryReader { proxy in
        let presentation = FormattingToolbarLayout.presentation(
          availableWidth: proxy.size.width
        )
        HStack(spacing: presentation == .full ? 8 : 2) {
        Menu {
          Button("Cancel Dictation", role: .destructive) {
            guard isEditorVisible else { return }
            Task { await dictationRuntime.cancel() }
          }
          .disabled(!dictationRuntime.canCancel)
        } label: {
          ToolbarIconLabel(
            systemImage: dictationRuntime.microphoneSymbol,
            isActive: dictationRuntime.isListening
          )
        } primaryAction: {
          guard isEditorVisible,
            dictationRuntime.toolbarPresentation.primaryAction != nil
          else { return }
          Task { await dictationRuntime.toggle() }
        }
        .accessibilityLabel(dictationRuntime.microphoneHelp)
        .accessibilityAction(named: Text("Cancel Dictation")) {
          guard isEditorVisible else { return }
          Task { await dictationRuntime.cancel() }
        }
        .help(dictationRuntime.microphoneHelp)
        if presentation == .full {
          Divider().frame(height: 15)
        }
        Button {
          guard isEditorVisible else { return }
          commands.undo()
        } label: {
          ToolbarIconLabel(systemImage: "arrow.uturn.backward")
        }
        .accessibilityLabel("Undo")
        .keyboardShortcut("z", modifiers: .command)
        Button {
          guard isEditorVisible else { return }
          commands.redo()
        } label: {
          ToolbarIconLabel(systemImage: "arrow.uturn.forward")
        }
        .accessibilityLabel("Redo")
        .keyboardShortcut("z", modifiers: [.command, .shift])
        if presentation == .full {
          Divider().frame(height: 15)
        }
        Button {
          guard isEditorVisible else { return }
          commands.toggleBold()
        } label: {
          ToolbarIconLabel(systemImage: "bold", isActive: commands.isBold)
        }
        .accessibilityLabel("Bold")
        .keyboardShortcut("b", modifiers: .command)
          .accessibilityValue(commands.isBold ? "On" : "Off")
        Button {
          guard isEditorVisible else { return }
          commands.toggleItalic()
        } label: {
          ToolbarIconLabel(systemImage: "italic", isActive: commands.isItalic)
        }
        .accessibilityLabel("Italic")
        .keyboardShortcut("i", modifiers: .command)
          .accessibilityValue(commands.isItalic ? "On" : "Off")
        Button {
          guard isEditorVisible else { return }
          commands.toggleUnderline()
        } label: {
          ToolbarIconLabel(systemImage: "underline", isActive: commands.isUnderlined)
        }
        .accessibilityLabel("Underline")
        .keyboardShortcut("u", modifiers: .command)
        .accessibilityValue(commands.isUnderlined ? "On" : "Off")
        if presentation == .full {
          Button {
            guard isEditorVisible else { return }
            commands.toggleStrikethrough()
          } label: {
            ToolbarIconLabel(systemImage: "strikethrough")
          }
          .accessibilityLabel("Strikethrough")
        }
        Button {
          guard isEditorVisible, let note = appState.selectedNote else { return }
          fontPickerTarget = FontPickerTarget(note: note, isTitle: isFontTitleTarget, commands: commands)
          isFontPickerPresented = fontPickerTarget != nil
        } label: {
          HStack(spacing: 5) {
            Text("Aa")
            if presentation == .full {
              Text(fontFamilyDisplay).lineLimit(1).truncationMode(.tail)
            }
            Image(systemName: "chevron.down").font(.system(size: 8))
          }
          .frame(width: presentation == .full ? 112 : 36)
        }
        .help("Font: \(fontFamilyDisplay)")
        .accessibilityLabel("Font")
        .accessibilityValue(fontFamilyDisplay)
        .popover(isPresented: $isFontPickerPresented, arrowEdge: .bottom) {
          if let target = fontPickerTarget {
            FontFamilyPicker(
              currentFamily: target.isTitle ? target.note.titleFontFamily ?? appState.preferences.fontFamily : commands.currentFontFamily,
              isMixed: target.isTitle ? false : commands.isFontFamilyMixed,
              targetLabel: target.label,
              onCommit: { family in
                _ = target.apply(family, note: appState.selectedNote, isEditorVisible: isEditorVisible, commands: commands,
                  titleMutation: { appState.setTitleFontFamily($0, noteID: target.note.id, undoManager: target.undoManager) })
                isFontPickerPresented = false
              },
              onCancel: { isFontPickerPresented = false }
            )
            .frame(width: 280, height: 320)
          }
        }
        .onChange(of: isFontPickerPresented) { _, presented in
          if !presented { fontPickerTarget = nil }
        }
        .onChange(of: appState.selectedNote) { _, _ in dismissInvalidFontPicker() }
        .onChange(of: isEditorVisible) { _, _ in dismissInvalidFontPicker() }
        if presentation == .full {
          fontSizeField()
        }
        Button {
          guard isEditorVisible else { return }
          isForegroundColorPickerPresented = true
        } label: {
          ToolbarIconLabel(systemImage: "paintpalette")
        }
        .accessibilityLabel("Font Color")
        .accessibilityValue(
          colorAccessibilityValue(
            color: commands.currentForegroundColor,
            isMixed: commands.isForegroundColorMixed,
            emptyName: "Automatic"
          )
        )
        .popover(isPresented: $isForegroundColorPickerPresented, arrowEdge: .bottom) {
          FleckColorPicker(
            currentHex: commands.isForegroundColorMixed
              ? nil
              : FleckColorHex.hex(from: commands.currentForegroundColor),
            currentLabel: colorAccessibilityValue(
              color: commands.currentForegroundColor,
              isMixed: commands.isForegroundColorMixed,
              emptyName: "Automatic"
            ),
            resetTitle: "Automatic",
            onCommit: { hex in
              guard isEditorVisible else {
                isForegroundColorPickerPresented = false
                return
              }
              commands.applyForegroundColor(hex.flatMap { NSColor(hex: $0) })
              isForegroundColorPickerPresented = false
            },
            onCancel: { isForegroundColorPickerPresented = false }
          )
        }
        Button {
          guard isEditorVisible else { return }
          isBackgroundColorPickerPresented = true
        } label: {
          HighlighterMarkerIcon(
            backgroundColor: commands.currentBackgroundColor,
            isMixed: commands.isBackgroundColorMixed
          )
        }
        .accessibilityLabel("Highlight")
        .accessibilityValue(
          colorAccessibilityValue(
            color: commands.currentBackgroundColor,
            isMixed: commands.isBackgroundColorMixed,
            emptyName: "No Highlight"
          )
        )
        .popover(isPresented: $isBackgroundColorPickerPresented, arrowEdge: .bottom) {
          FleckColorPicker(
            currentHex: commands.isBackgroundColorMixed
              ? nil
              : FleckColorHex.hex(from: commands.currentBackgroundColor),
            currentLabel: colorAccessibilityValue(
              color: commands.currentBackgroundColor,
              isMixed: commands.isBackgroundColorMixed,
              emptyName: "No Highlight"
            ),
            resetTitle: "No Highlight",
            fallbackHex: "#FFD600",
            onCommit: { hex in
              guard isEditorVisible else {
                isBackgroundColorPickerPresented = false
                return
              }
              commands.applyBackgroundColor(hex.flatMap { NSColor(hex: $0) })
              isBackgroundColorPickerPresented = false
            },
            onCancel: { isBackgroundColorPickerPresented = false }
          )
        }
        if presentation == .full {
          Menu {
            Button("Disc (•)") {
              guard isEditorVisible else { return }
              commands.applyList(.bullet(.disc))
            }
            Button("Circle (◦)") {
              guard isEditorVisible else { return }
              commands.applyList(.bullet(.circle))
            }
            Button("Square (▪)") {
              guard isEditorVisible else { return }
              commands.applyList(.bullet(.square))
            }
            Button("Dash (–)") {
              guard isEditorVisible else { return }
              commands.applyList(.bullet(.dash))
            }
          } label: {
            ToolbarIconLabel(systemImage: "list.bullet")
          } primaryAction: {
            guard isEditorVisible else { return }
            commands.applyAutomaticList(.bullets)
          }
          .accessibilityLabel("Bullets")
          Menu {
            Button("Decimal (1.)") {
              guard isEditorVisible else { return }
              commands.applyList(.number(.decimal))
            }
            Button("Alphabetic (a.)") {
              guard isEditorVisible else { return }
              commands.applyList(.number(.alphabetic))
            }
            Button("Roman (i.)") {
              guard isEditorVisible else { return }
              commands.applyList(.number(.roman))
            }
          } label: {
            ToolbarIconLabel(systemImage: "list.number")
          } primaryAction: {
            guard isEditorVisible else { return }
            commands.applyAutomaticList(.numbers)
          }
          .accessibilityLabel("Numbers")
          Button {
            guard isEditorVisible else { return }
            commands.applyList(.checklist)
          } label: {
            ToolbarIconLabel(systemImage: "checklist")
          }
          .accessibilityLabel("Checklist")
        } else {
          Menu {
            Button("Font Size…") {
              presentFontSizePicker()
            }
            Divider()
            Button("Strikethrough") {
              guard isEditorVisible else { return }
              commands.toggleStrikethrough()
            }
            Divider()
            Menu("Bullets") {
              Button("Bulleted List") {
                guard isEditorVisible else { return }
                commands.applyAutomaticList(.bullets)
              }
              Divider()
              Button("Disc (•)") {
                guard isEditorVisible else { return }
                commands.applyList(.bullet(.disc))
              }
              Button("Circle (◦)") {
                guard isEditorVisible else { return }
                commands.applyList(.bullet(.circle))
              }
              Button("Square (▪)") {
                guard isEditorVisible else { return }
                commands.applyList(.bullet(.square))
              }
              Button("Dash (–)") {
                guard isEditorVisible else { return }
                commands.applyList(.bullet(.dash))
              }
            }
            Menu("Numbers") {
              Button("Numbered List") {
                guard isEditorVisible else { return }
                commands.applyAutomaticList(.numbers)
              }
              Divider()
              Button("Decimal (1.)") {
                guard isEditorVisible else { return }
                commands.applyList(.number(.decimal))
              }
              Button("Alphabetic (a.)") {
                guard isEditorVisible else { return }
                commands.applyList(.number(.alphabetic))
              }
              Button("Roman (i.)") {
                guard isEditorVisible else { return }
                commands.applyList(.number(.roman))
              }
            }
            Button("Checklist") {
              guard isEditorVisible else { return }
              commands.applyList(.checklist)
            }
          } label: {
            ToolbarIconLabel(systemImage: "ellipsis.circle")
          }
          .accessibilityLabel("More formatting")
          .popover(isPresented: $isFontSizePickerPresented, arrowEdge: .bottom) {
            if let targetNoteID = fontSizePickerNoteID {
              HStack(spacing: 8) {
                fontSizeField(targetNoteID: targetNoteID)
                Button("Done") {
                  applyFontSizeText(targetNoteID: targetNoteID)
                  isFontSizePickerPresented = false
                }
              }
              .padding(12)
            }
          }
        }
        Spacer(minLength: presentation == .full ? nil : 0)
        Button(role: .destructive) {
          guard isEditorVisible else { return }
          onDelete()
        } label: {
          ToolbarIconLabel(systemImage: "trash")
        }
        .accessibilityLabel("Delete")
        .keyboardShortcut("w", modifiers: .command)
        }
        .buttonStyle(CrispToolbarButtonStyle(motion: motion))
        .animation(motion.quick, value: commands.isBold)
        .animation(motion.quick, value: commands.isItalic)
        .animation(motion.quick, value: commands.isUnderlined)
        .padding(.horizontal, presentation == .full ? 16 : 8)
        .padding(.vertical, 9)
      }
      .frame(height: 44)
      .frame(maxWidth: .infinity)
      .modifier(FormattingBarSurface(isPinned: isPinned))
      .padding(.horizontal, 10)
      .padding(.top, 8)
      .disabled(!isEditorVisible)
      .accessibilityElement(children: .contain)
      .accessibilityLabel("Editor toolbar")
      .accessibilityHidden(!isEditorVisible)
      .onChange(of: appState.selectedNote) { _, _ in
        dismissInvalidFontSizePicker()
      }
      .onChange(of: isEditorVisible) { _, _ in
        dismissInvalidFontSizePicker()
      }
      .onChange(of: isFontSizePickerPresented) { _, presented in
        if !presented { fontSizePickerNoteID = nil }
      }
    }

    private var motion: AppMotion {
      AppMotion(reduceMotion: reduceMotion)
    }

    private var fontSizeDisplay: String {
      guard !commands.isFontSizeMixed, let size = commands.currentFontSize else { return "" }
      return String(format: "%.2f", size).replacingOccurrences(of: #"\.00$"#, with: "", options: .regularExpression)
    }

    private func fontSizeField(targetNoteID: UUID? = nil) -> some View {
      TextField("Font size", text: $fontSizeText)
        .textFieldStyle(.roundedBorder)
        .frame(width: 48)
        .focused($isFontSizeFocused)
        .onAppear(perform: syncFontSizeText)
        .onChange(of: commands.currentFontSize) { _, _ in syncFontSizeText() }
        .onChange(of: commands.isFontSizeMixed) { _, _ in syncFontSizeText() }
        .onChange(of: isFontSizeFocused) { wasFocused, isFocused in
          if wasFocused && !isFocused { applyFontSizeText(targetNoteID: targetNoteID) }
        }
        .onSubmit { applyFontSizeText(targetNoteID: targetNoteID) }
        .accessibilityLabel("Font size")
        .accessibilityValue(commands.isFontSizeMixed ? "Mixed" : fontSizeDisplay)
        .accessibilityHint("Enter a size from 1 through 512 points.")
    }

    private var isFontTitleTarget: Bool {
      commands.isTitleEditing || isTitleFocused
    }

    private var currentFontFamily: String? {
      if isFontTitleTarget {
        return appState.selectedNote?.titleFontFamily ?? appState.preferences.fontFamily
      }
      return commands.currentFontFamily
    }

    private var isFontFamilyMixed: Bool {
      isFontTitleTarget ? false : commands.isFontFamilyMixed
    }

    private var fontFamilyDisplay: String {
      isFontFamilyMixed ? "Mixed fonts" : FontFamilyPickerController.displayName(currentFontFamily ?? ".AppleSystemUIFont")
    }

    private func dismissInvalidFontPicker() {
      guard let target = fontPickerTarget else { return }
      if !target.isValid(note: appState.selectedNote, isEditorVisible: isEditorVisible, commands: commands) {
        isFontPickerPresented = false
      }
    }

    private func syncFontSizeText() {
      guard !isFontSizeFocused else { return }
      fontSizeText = fontSizeDisplay
    }

    private func presentFontSizePicker() {
      guard isEditorVisible, let noteID = appState.selectedNote?.id else { return }
      fontSizePickerNoteID = noteID
      syncFontSizeText()
      isFontSizePickerPresented = true
    }

    private func dismissInvalidFontSizePicker() {
      guard isFontSizePickerPresented,
        !isEditorVisible || fontSizePickerNoteID != appState.selectedNote?.id
      else { return }
      isFontSizeFocused = false
      isFontSizePickerPresented = false
    }

    private func applyFontSizeText(targetNoteID: UUID? = nil) {
      guard isEditorVisible,
        targetNoteID == nil || targetNoteID == appState.selectedNote?.id
      else { return }
      if let size = FontSizeSubmission.requestedSize(
        for: fontSizeText,
        currentSize: commands.currentFontSize,
        isMixed: commands.isFontSizeMixed
      ) {
        _ = commands.applyFontSize(size)
      }
      fontSizeText = fontSizeDisplay
    }

    private func colorAccessibilityValue(
      color: NSColor?,
      isMixed: Bool,
      emptyName: String
    ) -> String {
      guard !isMixed else { return "Mixed" }
      guard let color else { return emptyName }
      return FleckPaletteOption.paletteName(for: color) ?? "Custom"
    }
  }

  private struct PinnedNavigationChromeSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    func body(content: Content) -> some View {
      switch materialPolicy {
      case .liquidGlass:
        if #available(macOS 26, *) {
          content.background {
            Rectangle()
              .fill(.clear)
              .glassEffect(.regular, in: Rectangle())
              .allowsHitTesting(false)
          }
        } else {
          content.background(.ultraThinMaterial)
        }
      case .legacyMaterial:
        content.background(.ultraThinMaterial)
      case .opaque:
        content.background(Color(nsColor: .windowBackgroundColor))
      }
    }

    private var materialPolicy: PinnedChromeMaterialPolicy {
      PinnedChromeMaterialPolicy.resolve(
        supportsLiquidGlass: supportsLiquidGlass,
        reduceTransparency: reduceTransparency,
        increasedContrast: colorSchemeContrast == .increased
      )
    }

    private var supportsLiquidGlass: Bool {
      if #available(macOS 26, *) {
        true
      } else {
        false
      }
    }
  }

  private struct FormattingBarSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let isPinned: Bool

    func body(content: Content) -> some View {
      if isPinned && (reduceTransparency || colorSchemeContrast == .increased) {
        content.background {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(nsColor: .windowBackgroundColor))
        }
      } else {
        if #available(macOS 26, *) {
          content.glassEffect(
            Glass.regular.tint(Color.black.opacity(0.18)),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
          )
        } else {
          content
            .background {
              RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                  RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.10))
                }
            }
        }
      }
    }
  }

  private struct PinnedWritingSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> AdaptiveOpaqueSurfaceView {
      AdaptiveOpaqueSurfaceView()
    }

    func updateNSView(_ nsView: AdaptiveOpaqueSurfaceView, context: Context) {
      nsView.updateSurfaceColor()
    }
  }

  final class AdaptiveOpaqueSurfaceView: NSView {
    override var isOpaque: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override init(frame frameRect: NSRect) {
      super.init(frame: frameRect)
      identifier = NSUserInterfaceItemIdentifier("pinnedWritingSurface")
      wantsLayer = true
      updateSurfaceColor()
    }

    required init?(coder: NSCoder) {
      super.init(coder: coder)
      identifier = NSUserInterfaceItemIdentifier("pinnedWritingSurface")
      wantsLayer = true
      updateSurfaceColor()
    }

    override func updateLayer() {
      updateSurfaceColor()
    }

    override func viewDidChangeEffectiveAppearance() {
      super.viewDidChangeEffectiveAppearance()
      needsDisplay = true
    }

    func updateSurfaceColor() {
      effectiveAppearance.performAsCurrentDrawingAppearance {
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
      }
    }
  }

  private struct CrispToolbarButtonStyle: ButtonStyle {
    let motion: AppMotion

    func makeBody(configuration: Configuration) -> some View {
      configuration.label
        .scaleEffect(configuration.isPressed ? motion.pressScale : 1)
        .animation(motion.quick, value: configuration.isPressed)
    }
  }

  private struct SaveFeedbackView: View {
    let status: AppState.SaveStatus
    let motion: AppMotion

    var body: some View {
      ZStack(alignment: .trailing) {
        switch status {
        case .idle:
          Color.clear
        case .saving:
          HStack(spacing: 5) {
            ProgressView()
              .controlSize(.mini)
            Text("Saving")
          }
          .id(status)
          .transition(.opacity)
        case .saved:
          Label("Saved", systemImage: "checkmark")
            .id(status)
            .transition(.opacity)
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      .frame(width: 62, height: 22, alignment: .trailing)
      .animation(motion.quick, value: status)
      .accessibilityElement(children: .combine)
    }
  }

  // Frames never follow presentation offsets: every slot is measured from the
  // original row, so reversing direction cannot chase an animated hit region.
  struct FluidTabReorder: Equatable {
    var interaction: ReorderInteraction
    let frames: [UUID: CGRect]
    let grabOffset: CGFloat
    let spacing: CGFloat = 6
    private(set) var destination: Int

    init?(interaction: ReorderInteraction, frames: [UUID: CGRect], pointerX: CGFloat) {
      guard let source = frames[interaction.sourceID], source.width > 0,
        interaction.originalIDs.allSatisfy({ frames[$0] != nil }),
        let index = interaction.originalIDs.firstIndex(of: interaction.sourceID)
      else { return nil }
      self.interaction = interaction
      self.frames = frames
      grabOffset = pointerX - source.minX
      destination = index
    }

    private var remaining: [UUID] { interaction.originalIDs.filter { $0 != interaction.sourceID } }
    private var sourceFrame: CGRect { frames[interaction.sourceID]! }
    private func slotX(_ index: Int) -> CGFloat {
      frames[interaction.originalIDs[0]]!.minX
        + remaining.prefix(index).reduce(0) { $0 + frames[$1]!.width + spacing }
    }
    var slotFrame: CGRect {
      CGRect(x: slotX(destination), y: sourceFrame.minY, width: sourceFrame.width, height: sourceFrame.height)
    }
    mutating func update(pointerX: CGFloat) {
      let pinned = interaction.pinnedIDs.contains(interaction.sourceID)
      let pinnedCount = remaining.filter { interaction.pinnedIDs.contains($0) }.count
      let allowed = pinned ? 0...pinnedCount : pinnedCount...remaining.count
      let left = pointerX - grabOffset
      destination = allowed.min { abs(slotX($0) - left) < abs(slotX($1) - left) }!
      interaction.clearTarget()
      if destination < remaining.count,
        interaction.pinnedIDs.contains(remaining[destination]) == pinned {
        interaction.propose(over: remaining[destination], after: false, currentIDs: interaction.originalIDs)
      } else if destination > 0, interaction.pinnedIDs.contains(remaining[destination - 1]) == pinned {
        interaction.propose(over: remaining[destination - 1], after: true, currentIDs: interaction.originalIDs)
      }
    }
    func offset(for id: UUID) -> CGFloat {
      guard id != interaction.sourceID, let original = frames[id], let index = remaining.firstIndex(of: id)
      else { return 0 }
      let newX = slotX(index) + (index >= destination ? sourceFrame.width + spacing : 0)
      return newX - original.minX
    }
    func isValid(ids: [UUID], pins: Set<UUID>, frames liveFrames: [UUID: CGRect],
      backingScaleFactor: CGFloat = 1) -> Bool {
      let backingPixel = 1 / max(1, backingScaleFactor)
      return ids == interaction.originalIDs && pins == interaction.pinnedIDs
        && ids.allSatisfy { id in
          guard let frozen = frames[id]?.size, let live = liveFrames[id]?.size else { return false }
          return abs(frozen.width - live.width) <= backingPixel
            && abs(frozen.height - live.height) <= backingPixel
        }
    }
    static func scrollDelta(pointerX: CGFloat, viewport: ClosedRange<CGFloat>) -> CGFloat {
      guard viewport.contains(pointerX) else { return 0 }
      let edge: CGFloat = min(32, (viewport.upperBound - viewport.lowerBound) / 3)
      if pointerX < viewport.lowerBound + edge { return -10 * (1 - (pointerX - viewport.lowerBound) / edge) }
      if pointerX > viewport.upperBound - edge { return 10 * (1 - (viewport.upperBound - pointerX) / edge) }
      return 0
    }
  }

  @MainActor final class FluidTabDragController: ObservableObject {
    @Published private(set) var preview: FluidTabReorder?
    @Published private(set) var inside = false
    private(set) var animatesDisplacement = true
    weak var view: FluidTabDestinationView?
    private var session: ReorderDropSession?
    private var currentIDs: (() -> [UUID])?
    private var currentPins: (() -> Set<UUID>)?
    private var move: ((UUID, Int) -> Void)?
    private var finish: (() -> Void)?
    private var timer: Timer?
    private var nativePoint: NSPoint?
    private var viewportSize: NSSize?
    private var accepted = false
    private weak var sourceView: ReorderSourceHostingView?

    private var pendingInteraction: ReorderInteraction?

    func prepare(interaction: ReorderInteraction, session: ReorderDropSession,
      currentIDs: @escaping () -> [UUID], currentPins: @escaping () -> Set<UUID>,
      move: @escaping (UUID, Int) -> Void, finish: @escaping () -> Void) {
      cancel()
      pendingInteraction = interaction
      self.session = session
      self.currentIDs = currentIDs
      self.currentPins = currentPins
      self.move = move
      self.finish = finish
    }

    // Native dragging items already contain the visible tab snapshot here.
    func began(at pointer: NSPoint) {
      guard let interaction = pendingInteraction, let view, let window = view.window else { return }
      let localPointer = view.convert(window.convertPoint(fromScreen: pointer), from: nil)
      let frames = view.sourceFrames()
      guard let initial = FluidTabReorder(interaction: interaction, frames: frames, pointerX: localPointer.x)
      else { cancel(); return }
      guard let sourceView = view.sourceView(for: interaction.sourceID) else { cancel(); return }
      viewportSize = view.enclosingScrollView?.contentView.bounds.size
      preview = initial
      self.sourceView = sourceView
      setInside(true)
      nativePoint = pointer
    }

    private var valid: Bool {
      guard let preview, let currentIDs, let currentPins else { return false }
      return preview.isValid(ids: currentIDs(), pins: currentPins(), frames: view?.sourceFrames() ?? [:],
        backingScaleFactor: view?.window?.backingScaleFactor ?? 1)
        && viewportSize == view?.enclosingScrollView?.contentView.bounds.size
    }

    func moved(to point: NSPoint) {
      nativePoint = point
      guard !accepted, preview != nil else { return }
      guard valid else {
        cancel()
        return
      }
      guard let view, let window = view.window,
        let clip = view.enclosingScrollView?.contentView else { return }
      let windowPoint = window.convertPoint(fromScreen: point)
      let nextInside = clip.bounds.contains(clip.convert(windowPoint, from: nil))
      setInside(nextInside)
      if nextInside {
        var next = preview
        next?.update(pointerX: view.convert(windowPoint, from: nil).x)
        if preview != next { preview = next }
        startTimer()
      } else {
        stopTimer()
      }
    }

    func operation(_ sender: any NSDraggingInfo) -> NSDragOperation {
      guard let view, let window = view.window else { return [] }
      moved(to: window.convertPoint(toScreen: sender.draggingLocation))
      let isValid = valid
      let canAccept = session?.canAcceptDrop == true
      let sourcePresent = sender.draggingSource != nil
      let payloadPresent = sender.draggingPasteboard.availableType(
        from: [.init(FolderDragPayload.noteType.identifier)]
      ) != nil
      return isValid && inside && canAccept && sourcePresent && payloadPresent ? .move : []
    }

    func exited() {
      setInside(false)
      stopTimer()
    }

    func perform(_ sender: any NSDraggingInfo) -> Bool {
      let requestedOperation = operation(sender)
      let data = sender.draggingPasteboard.data(
        forType: .init(FolderDragPayload.noteType.identifier)
      )
      guard requestedOperation == .move, let preview, let session, let currentIDs,
        let currentPins, let move,
        let data
      else { return false }
      let didAccept: Bool
      if preview.destination == preview.interaction.originalIDs.firstIndex(of: preview.interaction.sourceID) {
        didAccept = session.acceptDrop(data: data, commit: {})
      } else {
        didAccept = session.acceptReorder(data: data, interaction: preview.interaction,
          currentIDs: currentIDs, currentPinnedIDs: currentPins, move: move)
      }
      guard didAccept else { return false }
      accepted = true
      stopTimer()
      return true
    }

    func ended(sessionID: UUID, operation: NSDragOperation) {
      guard session?.id == sessionID else { return }
      stopTimer()
      reset(animated: !(accepted && operation == .move))
    }
    func cancel() {
      session?.cancel()
      reset()
    }
    private func reset(animated: Bool = true) {
      stopTimer()
      sourceView?.closeNativePreview()
      sourceView?.setDraggingSourceHidden(false)
      sourceView = nil
      animatesDisplacement = animated
      let finish = finish
      self.finish = nil
      currentIDs = nil
      currentPins = nil
      move = nil
      viewportSize = nil
      session = nil
      pendingInteraction = nil
      preview = nil
      inside = false
      accepted = false
      nativePoint = nil
      finish?()
    }
    private func setInside(_ value: Bool) {
      guard inside != value else { return }
      inside = value
      sourceView?.setDraggingSourceHidden(value)
    }
    private func startTimer() {
      guard timer == nil else { return }
      let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated { self?.tick() }
      }
      self.timer = timer
      RunLoop.main.add(timer, forMode: .common)
      RunLoop.main.add(timer, forMode: .eventTracking)
    }
    private func stopTimer() { timer?.invalidate(); timer = nil }
    func tick() {
      guard inside, !accepted, valid, let nativePoint, let view, let window = view.window,
        let scroll = view.enclosingScrollView, let document = scroll.documentView else {
        if !valid {
          cancel()
        } else {
          stopTimer()
        }
        return
      }
      let clip = scroll.contentView
      let point = clip.convert(window.convertPoint(fromScreen: nativePoint), from: nil)
      guard clip.bounds.contains(point) else { exited(); return }
      let delta = FluidTabReorder.scrollDelta(pointerX: point.x, viewport: clip.bounds.minX...clip.bounds.maxX)
      if delta != 0 {
        let x = min(max(clip.bounds.minX + delta, 0), max(0, document.bounds.width - clip.bounds.width))
        // Constraining an NSClipView can leave floating-point rounding residue at an edge.
        // Treat only that numerical noise as unchanged while preserving real subpixel scrolling.
        let coordinateMagnitude = max(1, abs(x), abs(clip.bounds.minX))
        let noiseTolerance = CGFloat.ulpOfOne.squareRoot() * coordinateMagnitude
        guard abs(x - clip.bounds.minX) > noiseTolerance else { return }
        clip.scroll(to: NSPoint(x: x, y: clip.bounds.minY))
        scroll.reflectScrolledClipView(clip)
        var next = preview
        next?.update(pointerX: view.convert(window.convertPoint(fromScreen: nativePoint), from: nil).x)
        if preview != next { preview = next }
      }
    }
  }

  private struct FluidTabStripHost<Content: View>: NSViewRepresentable {
    @ObservedObject var controller: FluidTabDragController
    let content: Content
    init(controller: FluidTabDragController, @ViewBuilder content: () -> Content) {
      self.controller = controller
      self.content = content()
    }
    func makeNSView(context: Context) -> FluidTabDestinationView {
      let view = FluidTabDestinationView(rootView: AnyView(EmptyView()))
      view.sizingOptions = [.intrinsicContentSize]
      view.registerForDraggedTypes([.init(FolderDragPayload.noteType.identifier)])
      view.controller = controller
      controller.view = view
      return view
    }
    func updateNSView(_ view: FluidTabDestinationView, context: Context) {
      view.rootView = AnyView(content.environment(\.self, context.environment))
    }
  }

  final class FluidTabDestinationView: NSHostingView<AnyView> {
    weak var controller: FluidTabDragController?

    func sourceFrames() -> [UUID: CGRect] {
      var frames: [UUID: CGRect] = [:]
      func collect(_ view: NSView) {
        if let source = view as? ReorderSourceHostingView, let noteID = source.noteID {
          frames[noteID] = convert(source.bounds, from: source)
          return
        }
        for child in view.subviews { collect(child) }
      }
      collect(self)
      return frames
    }

    func sourceView(for noteID: UUID) -> ReorderSourceHostingView? {
      func find(_ view: NSView) -> ReorderSourceHostingView? {
        if let source = view as? ReorderSourceHostingView, source.noteID == noteID {
          return source
        }
        return view.subviews.lazy.compactMap(find).first
      }
      return find(self)
    }
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
      controller?.operation(sender) ?? []
    }
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
      controller?.operation(sender) ?? []
    }
    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
      controller?.exited()
    }
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
      let prepared = controller?.operation(sender) == .move
      guard prepared else { return false }
      sender.animatesToDestination = false
      return true
    }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
      controller?.perform(sender) ?? false
    }
  }

  private struct ReorderDropTarget: ViewModifier {
    let destinationID: UUID
    let type: UTType
    @Binding var interaction: ReorderInteraction?
    @Binding var session: ReorderDropSession?
    let currentIDs: () -> [UUID]
    let currentPinnedIDs: () -> Set<UUID>
    let accepts: () -> Bool
    let finish: () -> Void
    let move: (UUID, Int) -> Void
    var noteDrop: (any DropDelegate)? = nil
    @State private var width: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
      content
        .padding(.leading, interaction?.targetID == destinationID && interaction?.after == false ? 3 : 0)
        .padding(.trailing, interaction?.targetID == destinationID && interaction?.after == true ? 3 : 0)
        .animation(AppMotion(reduceMotion: reduceMotion).spatial, value: interaction)
        .background(GeometryReader { geometry in
          Color.clear.onAppear { width = geometry.size.width }
            .onChange(of: geometry.size.width) { _, value in width = value }
        })
        .overlay(alignment: interaction?.after == true ? .trailing : .leading) {
          if interaction?.targetID == destinationID {
            Capsule().fill(Color.accentColor).frame(width: 2, height: 22)
              .offset(x: interaction?.after == true ? 3 : -3)
              .allowsHitTesting(false)
              .accessibilityHidden(true)
          }
        }
        .onDrop(of: noteDrop == nil ? [type] : [type, FolderDragPayload.noteType], delegate: TabDropDelegate(
          destinationID: destinationID, width: width, type: type,
          interaction: $interaction, session: $session, currentIDs: currentIDs,
          currentPinnedIDs: currentPinnedIDs,
          accepts: accepts, finish: finish, move: move, noteDrop: noteDrop
        ))
    }
  }

  private struct TabDropDelegate: DropDelegate {
    let destinationID: UUID
    let width: CGFloat
    let type: UTType
    @Binding var interaction: ReorderInteraction?
    @Binding var session: ReorderDropSession?
    let currentIDs: () -> [UUID]
    let currentPinnedIDs: () -> Set<UUID>
    let accepts: () -> Bool
    let finish: () -> Void
    let move: (UUID, Int) -> Void
    var noteDrop: (any DropDelegate)? = nil

    private var activeNoteDrop: (any DropDelegate)? {
      session?.type == FolderDragPayload.noteType ? noteDrop : nil
    }

    func validateDrop(info: DropInfo) -> Bool {
      if let activeNoteDrop { return activeNoteDrop.validateDrop(info: info) }
      let accepted = session?.canAcceptDrop == true && session?.id == interaction?.sessionID
        && session?.type == type
        && info.hasItemsConforming(to: [type]) && accepts()
      return interaction != nil && interaction?.sourceID != destinationID
        && accepted && interaction?.originalIDs == currentIDs()
    }

    func dropEntered(info: DropInfo) {
      if let activeNoteDrop { activeNoteDrop.dropEntered(info: info); return }
      update(info)
    }

    private func update(_ info: DropInfo) {
      guard validateDrop(info: info) else {
        interaction?.clearTarget()
        return
      }
      interaction?.propose(over: destinationID, after: info.location.x >= width / 2,
        currentIDs: currentIDs())
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
      if let activeNoteDrop { return activeNoteDrop.dropUpdated(info: info) }
      update(info)
      return DropProposal(operation: validateDrop(info: info) ? .move : .forbidden)
    }

    func dropExited(info: DropInfo) {
      if let activeNoteDrop { activeNoteDrop.dropExited(info: info); return }
      if interaction?.targetID == destinationID { interaction?.clearTarget() }
    }

    func performDrop(info: DropInfo) -> Bool {
      if let activeNoteDrop { return activeNoteDrop.performDrop(info: info) }
      update(info)
      guard validateDrop(info: info), let proposal = interaction, let session,
        session.acceptReorder(from: info.itemProviders(for: [type]), interaction: proposal,
          currentIDs: currentIDs, currentPinnedIDs: currentPinnedIDs, move: move) != nil
      else { return false }
      interaction = nil
      finish()
      return true
    }
  }

  // Folders keep SwiftUI's drag source. Note tabs own their left-pointer gesture
  // so AppKit receives the real threshold event and a snapshot captured before hiding.
  private struct ReorderDragSource: ViewModifier {
    let begin: () -> (NSItemProvider, NSPasteboardWriting?, (NSDragOperation) -> Void)
    var began: ((NSPoint) -> Void)? = nil
    var moved: ((NSPoint) -> Void)? = nil
    var activate: (() -> Void)? = nil
    var noteID: UUID? = nil
    var displacement: CGFloat? = nil
    var animatesDisplacement = false

    func body(content: Content) -> some View {
      ReorderDragHost(content: content, begin: begin, began: began, moved: moved,
        activate: activate, noteID: noteID, displacement: displacement,
        animatesDisplacement: animatesDisplacement)
    }
  }

  private struct ReorderDragHost<Content: View>: NSViewRepresentable {
    let content: Content
    let begin: () -> (NSItemProvider, NSPasteboardWriting?, (NSDragOperation) -> Void)
    let began: ((NSPoint) -> Void)?
    let moved: ((NSPoint) -> Void)?
    let activate: (() -> Void)?
    let noteID: UUID?
    let displacement: CGFloat?
    let animatesDisplacement: Bool

    func makeNSView(context: Context) -> ReorderSourceHostingView {
      let view = ReorderSourceHostingView(rootView: AnyView(EmptyView()))
      view.sizingOptions = [.intrinsicContentSize]
      return view
    }

    func updateNSView(_ view: ReorderSourceHostingView, context: Context) {
      view.noteID = noteID
      view.onBegan = began
      view.onMoved = moved
      view.onNativeBegin = noteID == nil ? nil : begin
      view.onPrimaryClick = noteID == nil ? nil : activate
      let dragContent = content.environment(\.self, context.environment)
      if noteID == nil {
        view.rootView = AnyView(
          dragContent.onDrag({ [weak view] in
            let (provider, _, end) = begin()
            view?.onEnd = end
            return provider
          }, preview: {
            dragContent
          })
        )
      } else {
        view.rootView = AnyView(dragContent)
      }
      if let displacement { view.setReorderDisplacement(displacement, animated: animatesDisplacement) }
    }
  }

  final class ReorderSourceHostingView: NSHostingView<AnyView> {
    var noteID: UUID?

    // Keep layout in its original order during hover. AppKit owns the layer
    // transition, including interruption, instead of relying on SwiftUI to
    // animate the frame of a native representable during drag tracking.
    func setReorderDisplacement(_ offset: CGFloat, animated: Bool) {
      wantsLayer = true
      guard let layer else { return }
      let key = "fleck.tab-reorder"
      if layer.transform.m41 == offset && animated { return }
      let from = layer.presentation()?.transform.m41 ?? layer.transform.m41
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      var transform = layer.transform
      transform.m41 = offset
      layer.transform = transform
      layer.removeAnimation(forKey: key)
      if animated && abs(from - offset) > 0.01 {
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = from
        animation.toValue = offset
        animation.duration = AppMotion.standardDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: key)
      }
      CATransaction.commit()
    }

    func setDraggingSourceHidden(_ hidden: Bool) {
      wantsLayer = true
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      layer?.opacity = hidden ? 0 : 1
      CATransaction.commit()
    }

    var onEnd: ((NSDragOperation) -> Void)?
    var onBegan: ((NSPoint) -> Void)?
    var onMoved: ((NSPoint) -> Void)?
    var onNativeBegin: (() -> (NSItemProvider, NSPasteboardWriting?, (NSDragOperation) -> Void))?
    var onPrimaryClick: (() -> Void)?
    #if DEBUG
      var interceptNativeDrag: (([NSDraggingItem], ReorderNativeSource, NSEvent) -> Bool)?
    #endif
    private var pointerDown: (event: NSEvent, point: NSPoint)?
    private var sourceProxy: ReorderNativeSource?

    override func mouseDown(with event: NSEvent) {
      guard noteID != nil, !event.modifierFlags.contains(.control) else {
        pointerDown = nil
        super.mouseDown(with: event)
        return
      }
      pointerDown = (event, convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
      guard noteID != nil else {
        super.mouseDragged(with: event)
        return
      }
      guard let press = pointerDown, sourceProxy == nil else { return }
      let point = convert(event.locationInWindow, from: nil)
      let distance = NSPoint(x: point.x - press.point.x, y: point.y - press.point.y)
      guard distance.x * distance.x + distance.y * distance.y >= 16,
        let onNativeBegin
      else { return }
      pointerDown = nil
      let image = draggingImage()
      guard let preview = ReorderNativePreview(
        image: image, sourceView: self, grabPoint: press.point
      ) else { return }
      let (_, pasteboardWriter, end) = onNativeBegin()
      guard let pasteboardWriter else {
        preview.close()
        end([])
        return
      }
      let item = NSDraggingItem(pasteboardWriter: pasteboardWriter)
      item.setDraggingFrame(bounds, contents: nil)
      let id = UUID()
      let proxy = ReorderNativeSource(
        id: id, source: nil, began: onBegan, preview: preview
      ) { [weak self] operation in
        end(operation)
        if self?.sourceProxy?.id == id { self?.sourceProxy = nil }
      }
      proxy.moved = onMoved
      sourceProxy = proxy
      #if DEBUG
        if interceptNativeDrag?([item], proxy, press.event) == true {
          proxy.end([])
          return
        }
      #endif
      let session = super.beginDraggingSession(with: [item], event: press.event, source: proxy)
      session.animatesToStartingPositionsOnCancelOrFail = false
    }

    override func mouseUp(with event: NSEvent) {
      guard noteID != nil else {
        super.mouseUp(with: event)
        return
      }
      guard pointerDown != nil else { return }
      pointerDown = nil
      let point = convert(event.locationInWindow, from: nil)
      if bounds.contains(point) { onPrimaryClick?() }
    }

    override func rightMouseDown(with event: NSEvent) {
      pointerDown = nil
      super.rightMouseDown(with: event)
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if window == nil { sourceProxy?.closePreview() }
    }

    private func draggingImage() -> NSImage {
      var image = NSImage(size: bounds.size)
      effectiveAppearance.performAsCurrentDrawingAppearance {
        guard let captured = bitmapImageRepForCachingDisplay(in: bounds) else { return }
        cacheDisplay(in: bounds, to: captured)
        image = Self.compositedDraggingImage(
          captured: captured, size: bounds.size, appearance: effectiveAppearance
        ) ?? image
      }
      return image
    }

    static func compositedDraggingImage(captured: NSBitmapImageRep, size: NSSize,
      appearance: NSAppearance) -> NSImage? {
      guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: captured.pixelsWide,
        pixelsHigh: captured.pixelsHigh,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      ) else { return nil }
      representation.size = size
      guard let context = NSGraphicsContext(bitmapImageRep: representation) else { return nil }
      let image = NSImage(size: size)
      let capturedImage = NSImage(size: size)
      capturedImage.addRepresentation(captured)
      appearance.performAsCurrentDrawingAppearance {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let rect = NSRect(origin: .zero, size: size)
        let surface = NSBezierPath(
          roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6
        )
        NSColor.windowBackgroundColor.setFill()
        surface.fill()
        capturedImage.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
          respectFlipped: true, hints: nil)
        NSColor.separatorColor.setStroke()
        surface.lineWidth = 1
        surface.stroke()
        NSGraphicsContext.restoreGraphicsState()
      }
      image.addRepresentation(representation)
      return image
    }

    func closeNativePreview() {
      sourceProxy?.closePreview()
    }

    override func beginDraggingSession(with items: [NSDraggingItem], event: NSEvent,
      source: any NSDraggingSource) -> NSDraggingSession {
      let id = UUID()
      let began = onBegan
      let end = onEnd
      onEnd = nil
      let proxy = ReorderNativeSource(id: id, source: source, began: began) { [weak self] operation in
        end?(operation)
        if self?.sourceProxy?.id == id { self?.sourceProxy = nil }
      }
      proxy.moved = onMoved
      sourceProxy = proxy
      let session = super.beginDraggingSession(with: items, event: event, source: proxy)
      if began != nil {
        session.animatesToStartingPositionsOnCancelOrFail = false
      }
      return session
    }
  }

  @MainActor final class ReorderNativePreview {
    let image: NSImage
    let panel: NSPanel
    private let initialFrame: NSRect
    private let grabOffset: NSPoint
    private var isClosed = false

    init?(image: NSImage, sourceView: NSView, grabPoint: NSPoint) {
      guard let sourceWindow = sourceView.window else { return nil }
      self.image = image
      initialFrame = sourceWindow.convertToScreen(sourceView.convert(sourceView.bounds, to: nil))
      let grabPointOnScreen = sourceWindow.convertPoint(
        toScreen: sourceView.convert(grabPoint, to: nil)
      )
      grabOffset = NSPoint(
        x: grabPointOnScreen.x - initialFrame.minX,
        y: grabPointOnScreen.y - initialFrame.minY
      )
      panel = NSPanel(
        contentRect: initialFrame,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
      )
      panel.isReleasedWhenClosed = false
      panel.backgroundColor = .clear
      panel.isOpaque = false
      panel.hasShadow = false
      panel.ignoresMouseEvents = true
      panel.hidesOnDeactivate = false
      panel.level = NSWindow.Level(rawValue: sourceWindow.level.rawValue + 1)
      let imageView = NSImageView(frame: NSRect(origin: .zero, size: initialFrame.size))
      imageView.image = image
      imageView.imageScaling = .scaleNone
      panel.contentView = imageView
    }

    func show(at point: NSPoint) {
      guard !isClosed else { return }
      panel.setFrameOrigin(NSPoint(x: point.x - grabOffset.x, y: point.y - grabOffset.y))
      panel.orderFrontRegardless()
    }

    func move(to point: NSPoint) {
      guard !isClosed else { return }
      panel.setFrameOrigin(NSPoint(x: point.x - grabOffset.x, y: point.y - grabOffset.y))
    }

    func close() {
      guard !isClosed else { return }
      isClosed = true
      panel.orderOut(nil)
      panel.close()
    }

    deinit {
      MainActor.assumeIsolated {
        panel.orderOut(nil)
        panel.close()
      }
    }
  }

  @MainActor final class ReorderNativeSource: NSObject, NSDraggingSource {
    let id: UUID
    let source: (any NSDraggingSource)?
    let began: ((NSPoint) -> Void)?
    private(set) var preview: ReorderNativePreview?
    private let endHandler: (NSDragOperation) -> Void
    var moved: ((NSPoint) -> Void)?

    init(id: UUID, source: (any NSDraggingSource)?, began: ((NSPoint) -> Void)?,
      preview: ReorderNativePreview? = nil, end: @escaping (NSDragOperation) -> Void) {
      self.id = id
      self.source = source
      self.began = began
      self.preview = preview
      endHandler = end
    }

    func end(_ operation: NSDragOperation) {
      closePreview()
      endHandler(operation)
    }

    func closePreview() {
      preview?.close()
    }

    func draggingSession(_ session: NSDraggingSession,
      sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
      Self.operationMask(for: context)
    }

    static func operationMask(for context: NSDraggingContext) -> NSDragOperation {
      context == .withinApplication ? .move : []
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
      source?.ignoreModifierKeys?(for: session) ?? false
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt point: NSPoint) {
      source?.draggingSession?(session, willBeginAt: point)
      preview?.show(at: point)
      began?(point)
    }

    func draggingSession(_ session: NSDraggingSession, movedTo point: NSPoint) {
      preview?.move(to: point)
      moved?(session.draggingLocation)
      source?.draggingSession?(session, movedTo: point)
    }

    func draggingSession(_ session: NSDraggingSession, endedAt point: NSPoint,
      operation: NSDragOperation) {
      source?.draggingSession?(session, endedAt: point, operation: operation)
      end(operation)
    }
  }

  // Native dragging can end outside every SwiftUI drop target. Watch its lifetime,
  // and scroll only the enclosing strip while a validated proposal is active.
  struct ReorderDragLifecycle: NSViewRepresentable {
    let active: Bool
    let hasTarget: Bool
    let cancel: () -> Void

    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {
      view.cancel = cancel
      view.hasTarget = hasTarget
      view.setActive(active)
    }
    static func dismantleNSView(_ view: DragView, coordinator: ()) { view.setActive(false) }

    final class DragView: NSView {
      var cancel: (() -> Void)?
      var hasTarget = false
      private var timer: Timer?
      private var escapeMonitor: Any?
      override func hitTest(_ point: NSPoint) -> NSView? { nil }

      func setActive(_ active: Bool) {
        guard active else {
          timer?.invalidate()
          timer = nil
          if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
          escapeMonitor = nil
          return
        }
        guard timer == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
          if event.keyCode == 53 {
            self?.end()
          }
          return event
        }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
          MainActor.assumeIsolated { self?.tick() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
      }

      private func end() {
        setActive(false)
        cancel?()
      }

      private func tick() {
        guard let window else {
          end()
          return
        }
        guard hasTarget, let scroll = enclosingScrollView else { return }
        let clip = scroll.contentView
        let point = clip.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        guard clip.bounds.contains(point), let document = scroll.documentView else { return }
        let delta: CGFloat = point.x < clip.bounds.minX + 24 ? -5
          : point.x > clip.bounds.maxX - 24 ? 5 : 0
        guard delta != 0 else { return }
        let x = min(max(clip.bounds.minX + delta, 0), max(0, document.bounds.width - clip.bounds.width))
        clip.scroll(to: NSPoint(x: x, y: clip.bounds.minY))
        scroll.reflectScrolledClipView(clip)
      }
    }
  }

  struct HighlighterMarkerShape: Shape {
    func path(in rect: CGRect) -> Path {
      let stemMinX = rect.minX + rect.width * 0.20
      let stemMaxX = rect.minX + rect.width * 0.80
      let stemTop = rect.minY + rect.height * 0.08
      let shoulderY = rect.minY + rect.height * 0.43
      let bodyBottom = rect.minY + rect.height * 0.57
      let bodyInset = rect.width * 0.08

      var path = Path()
      path.move(to: CGPoint(x: stemMinX, y: stemTop))
      path.addLine(to: CGPoint(x: stemMinX, y: shoulderY))
      path.addLine(
        to: CGPoint(x: stemMinX + bodyInset, y: bodyBottom)
      )
      path.addLine(
        to: CGPoint(x: stemMaxX - bodyInset, y: bodyBottom)
      )
      path.addLine(to: CGPoint(x: stemMaxX, y: shoulderY))
      path.addLine(to: CGPoint(x: stemMaxX, y: stemTop))
      path.move(to: CGPoint(x: stemMinX, y: shoulderY))
      path.addLine(to: CGPoint(x: stemMaxX, y: shoulderY))
      return path
    }
  }

  struct HighlighterMarkerNibShape: Shape {
    func path(in rect: CGRect) -> Path {
      let inkMinX = rect.minX + rect.width * 0.34
      let inkMaxX = rect.minX + rect.width * 0.70
      let inkTop = rect.minY + rect.height * 0.63
      let inkBottom = rect.minY + rect.height * 0.96
      let taperY = inkTop + (inkBottom - inkTop) * 0.38
      let lowerMinX = inkMinX + rect.width * 0.05

      var path = Path()
      path.move(to: CGPoint(x: inkMinX, y: inkTop))
      path.addLine(to: CGPoint(x: inkMaxX, y: inkTop))
      path.addLine(to: CGPoint(x: inkMaxX, y: taperY))
      path.addLine(to: CGPoint(x: lowerMinX, y: inkBottom))
      path.addLine(to: CGPoint(x: inkMinX, y: inkBottom))
      path.closeSubpath()
      return path
    }
  }

  struct HighlighterMarkerIcon: View {
    let inkColor: NSColor

    init(backgroundColor: NSColor?, isMixed: Bool) {
      self.inkColor = (!isMixed ? backgroundColor : nil)
        ?? FleckColorHex.nsColor(from: "#FFD600")!
    }

    var body: some View {
      ZStack {
        HighlighterMarkerNibShape()
          .fill(Color(nsColor: inkColor))
          .overlay {
            HighlighterMarkerNibShape()
              .stroke(.primary, lineWidth: 1.1)
          }
        HighlighterMarkerShape()
          .stroke(
            .primary,
            style: StrokeStyle(lineWidth: 1.15, lineCap: .butt, lineJoin: .miter)
          )
      }
        .frame(width: 20, height: 18)
        .frame(width: 28, height: 26)
        .background(.clear, in: RoundedRectangle(cornerRadius: 5))
        .contentShape(RoundedRectangle(cornerRadius: 5))
    }
  }

  private struct ToolbarIconLabel: View {
    let systemImage: String
    var isActive = false

    var body: some View {
      Image(systemName: systemImage)
        .frame(width: 28, height: 26)
        .background(
          isActive ? Color.accentColor.opacity(0.24) : .clear,
          in: RoundedRectangle(cornerRadius: 5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 5))
    }
  }

#endif
