#if os(macOS)
  import AppKit
  import FleckCore
  import SwiftUI

  enum DictationCapsuleStatus: Equatable {
    case idle
    case listening
    case finalizing
    case cleaning
    case routing
    case saved(destination: String)
    case savedWithoutCleanup(destination: String)
    case repairingModel
    case failed(String)

    var presentation: DictationCapsulePresentation {
      switch self {
      case .idle:
        .init(
          visibleText: nil,
          voiceOverText: "Fleck dictation ready",
          symbolName: "waveform",
          visualMode: .idle
        )
      case .listening:
        .init(
          visibleText: nil,
          voiceOverText: "Dictation listening",
          symbolName: "waveform",
          visualMode: .listening
        )
      case .finalizing:
        .init(
          visibleText: "Finishing",
          voiceOverText: "Finishing dictation",
          symbolName: "ellipsis.circle",
          visualMode: .progress
        )
      case .cleaning:
        .init(
          visibleText: "Cleaning up",
          voiceOverText: "Cleaning up dictation",
          symbolName: "sparkles",
          visualMode: .progress
        )
      case .routing:
        .init(
          visibleText: "Finding note",
          voiceOverText: "Finding a note for dictation",
          symbolName: "arrow.triangle.branch",
          visualMode: .progress
        )
      case .saved(let destination):
        .init(
          visibleText: "Saved to \(destination)",
          voiceOverText: "Dictation saved to \(destination)",
          symbolName: "checkmark.circle.fill",
          visualMode: .success,
          isSuccess: true
        )
      case .savedWithoutCleanup(let destination):
        .init(
          visibleText: "Saved to \(destination) without cleanup",
          voiceOverText: "Dictation saved to \(destination) without cleanup",
          symbolName: "exclamationmark.triangle.fill",
          visualMode: .warning,
          isSuccess: true
        )
      case .repairingModel:
        .init(
          visibleText: "Repairing enhanced model",
          voiceOverText: "Repairing enhanced dictation model",
          symbolName: "wrench.and.screwdriver.fill",
          visualMode: .progress
        )
      case .failed(let message):
        .init(
          visibleText: "Dictation failed",
          voiceOverText: "Dictation failed: \(message)",
          symbolName: "exclamationmark.circle.fill",
          visualMode: .failure
        )
      }
    }
  }

  enum DictationCapsuleVisualMode: Equatable {
    case idle
    case listening
    case progress
    case success
    case warning
    case failure
  }

  struct DictationCapsulePresentation: Equatable {
    let visibleText: String?
    let voiceOverText: String
    let symbolName: String
    let visualMode: DictationCapsuleVisualMode
    var isSuccess = false
  }

  struct DictationCapsuleChoice: Equatable, Identifiable {
    private static let visibleContextLimit = 48

    let id: UUID
    let title: String
    let contextHint: String
    let showsContextHint: Bool
    let currentDestinationTitle: String
    let isCurrentDestination: Bool

    var menuTitle: String {
      guard showsContextHint, !contextHint.isEmpty else { return title }
      let prefix = String(contextHint.prefix(Self.visibleContextLimit))
      let suffix = contextHint.count > Self.visibleContextLimit ? "…" : ""
      return "\(title) — \(prefix)\(suffix)"
    }

    var accessibilityLabel: String {
      let action = isCurrentDestination
        ? "Retry saving dictation in \(title)"
        : "Move dictation to \(title)"
      guard !contextHint.isEmpty else { return action }
      return "\(action). Context: \(contextHint)"
    }

    var accessibilityHint: String {
      if isCurrentDestination {
        return "Retries completion for this saved dictation in \(title)."
      }
      return "Moves this saved dictation from \(currentDestinationTitle) to \(title)."
    }
  }

  struct DictationCapsuleChooser: Equatable {
    let captureID: UUID
    let choices: [DictationCapsuleChoice]
    let allowsKeepInInbox: Bool
    let keepInboxTitle = "Keep in Inbox"
    let keepInboxAccessibilityLabel = "Keep dictation in Inbox"

    var menuAccessibilityHint: String {
      if allowsKeepInInbox {
        return "Choose a note for this saved dictation or keep it in Inbox."
      }
      return "Choose a note for this saved dictation."
    }

    init(
      ambiguity: DictationRoutingAmbiguity,
      currentDestinationID: UUID? = nil,
      currentDestinationTitle: String = "Inbox",
      allowsKeepInInbox: Bool = true
    ) {
      captureID = ambiguity.captureID
      self.allowsKeepInInbox = allowsKeepInInbox
      let supported = Array(ambiguity.choices.prefix(4))
      let titleCounts = Dictionary(grouping: supported) {
        Self.normalizedTitle($0.destination.title)
      }.mapValues(\.count)
      choices = supported.map { choice in
        let title = Self.displayTitle(choice.destination.title)
        return DictationCapsuleChoice(
          id: choice.destination.noteID,
          title: title,
          contextHint: choice.contextHint,
          showsContextHint: titleCounts[Self.normalizedTitle(title), default: 0] > 1,
          currentDestinationTitle: Self.displayTitle(currentDestinationTitle),
          isCurrentDestination: choice.destination.noteID == currentDestinationID
        )
      }
    }

    private static func displayTitle(_ title: String) -> String {
      let normalized = title.split(whereSeparator: \Character.isWhitespace)
        .joined(separator: " ")
      return normalized.isEmpty ? "Untitled" : normalized
    }

    private static func normalizedTitle(_ title: String) -> String {
      displayTitle(title).lowercased()
    }
  }

  enum DictationCapsuleTransition: Equatable {
    case opacity
    case scaleAndOpacity

    static func forReduceMotion(_ reduceMotion: Bool) -> Self {
      reduceMotion ? .opacity : .scaleAndOpacity
    }
  }

  enum DictationWaveformRefreshSchedule {
    static func interval(reduceMotion: Bool) -> TimeInterval {
      reduceMotion ? 1 / 15 : 1 / 30
    }
  }

  enum DictationCapsuleAction: Equatable {
    case undo
    case copy
    case openHistory
    case openDestination

    var title: String {
      switch self {
      case .undo: "Undo"
      case .copy: "Copy"
      case .openHistory: "Open Dictation History"
      case .openDestination: "Open Destination"
      }
    }

    var accessibilityLabel: String { title }
  }

  final class DictationCapsulePanel: NSPanel {
    var allowsActions = false

    init() {
      super.init(
        contentRect: .zero,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: true
      )
      level = .floating
      collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
      isFloatingPanel = true
      hidesOnDeactivate = false
      isReleasedWhenClosed = false
      isMovableByWindowBackground = false
      isOpaque = false
      backgroundColor = .clear
      hasShadow = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
  }

  private final class DictationCapsuleObserverToken: @unchecked Sendable {
    let value: NSObjectProtocol

    init(_ value: NSObjectProtocol) {
      self.value = value
    }
  }

  @MainActor
  final class DictationCapsuleController {
    static let idleSize = CGSize(width: 40, height: 26)
    static let listeningSize = CGSize(width: 196, height: 32)
    static let activeSize = CGSize(width: 280, height: 32)
    static let edgeInset: CGFloat = 24

    let panel: DictationCapsulePanel
    let waveformModel: DictationWaveformModel
    private(set) var currentDock = DictationCapsuleDock.bottom
    private(set) var currentChooser: DictationCapsuleChooser?
    private var currentStatus = DictationCapsuleStatus.idle
    private var currentAction: DictationCapsuleAction?
    private var currentActionHandler: @MainActor () -> Void = {}
    private var currentChoiceHandler: @MainActor (UUID, UUID?) -> Void = { _, _ in }
    private var contentGeneration: UInt64 = 0
    private var currentScreen: NSScreen?
    private var onOpenFleck: (@MainActor () -> Void)?
    private var onDockChanged: (@MainActor (DictationCapsuleDock) -> Void)?
    private var screenParametersObserver: DictationCapsuleObserverToken?

    init(
      panel: DictationCapsulePanel = DictationCapsulePanel(),
      waveformModel: DictationWaveformModel = DictationWaveformModel()
    ) {
      self.panel = panel
      self.waveformModel = waveformModel
      screenParametersObserver = DictationCapsuleObserverToken(
        NotificationCenter.default.addObserver(
          forName: NSApplication.didChangeScreenParametersNotification,
          object: nil,
          queue: .main
        ) { [weak self] _ in
          Task { @MainActor [weak self] in
            self?.redockAfterScreenChange()
          }
        }
      )
    }

    func presentIdle(
      dock: DictationCapsuleDock,
      onOpenFleck: @escaping @MainActor () -> Void,
      onDockChanged: @escaping @MainActor (DictationCapsuleDock) -> Void
    ) {
      currentDock = dock
      currentStatus = .idle
      waveformModel.reset()
      currentAction = nil
      currentActionHandler = {}
      currentChooser = nil
      currentChoiceHandler = { _, _ in }
      self.onOpenFleck = onOpenFleck
      self.onDockChanged = onDockChanged
      installContent(status: .idle, action: nil, chooser: nil, onAction: {})
      applyCurrentFrame(animated: panel.isVisible)
      panel.orderFrontRegardless()
    }

    func render(
      _ status: DictationCapsuleStatus,
      action: DictationCapsuleAction? = nil,
      chooser: DictationCapsuleChooser? = nil,
      onAction: @escaping @MainActor () -> Void = {},
      onChoice: @escaping @MainActor (UUID, UUID?) -> Void = { _, _ in }
    ) {
      let wasListening = currentStatus == .listening
      currentStatus = status
      if status == .listening {
        if !wasListening {
          waveformModel.beginListening()
        }
      } else {
        waveformModel.reset()
      }
      currentAction = action
      currentActionHandler = onAction
      currentChooser = chooser
      currentChoiceHandler = onChoice
      installContent(
        status: status,
        action: action,
        chooser: chooser,
        onAction: onAction
      )
      applyCurrentFrame(animated: panel.isVisible)
      panel.orderFrontRegardless()
    }

    func setDock(_ dock: DictationCapsuleDock) {
      currentDock = dock
      installContent(
        status: currentStatus,
        action: currentAction,
        chooser: currentChooser,
        onAction: currentActionHandler
      )
      applyCurrentFrame(animated: panel.isVisible)
    }

    func dismiss() {
      waveformModel.reset()
      contentGeneration &+= 1
      currentChooser = nil
      currentChoiceHandler = { _, _ in }
      panel.allowsActions = false
      panel.orderOut(nil)
    }

    func selectRoutingChoice(captureID: UUID, noteID: UUID?) {
      guard
        let currentChooser,
        currentChooser.captureID == captureID
      else { return }
      let isValidChoice = noteID.map { noteID in
        currentChooser.choices.contains(where: { $0.id == noteID })
      } ?? currentChooser.allowsKeepInInbox
      guard isValidChoice else { return }
      currentChoiceHandler(captureID, noteID)
    }

    func updateAudioLevel(_ level: Float) {
      guard currentStatus == .listening, panel.isVisible else { return }
      waveformModel.receive(level: level)
    }

    static func size(for status: DictationCapsuleStatus) -> CGSize {
      switch status {
      case .idle:
        idleSize
      case .listening:
        listeningSize
      case .finalizing, .cleaning, .routing, .saved, .savedWithoutCleanup,
        .repairingModel, .failed:
        activeSize
      }
    }

    static func frame(
      for dock: DictationCapsuleDock,
      in visibleFrame: CGRect
    ) -> CGRect {
      frame(for: dock, size: idleSize, in: visibleFrame)
    }

    static func nearestDock(
      to point: CGPoint,
      in visibleFrame: CGRect
    ) -> DictationCapsuleDock {
      let bottomDistance = abs(point.y - visibleFrame.minY)
      let leftDistance = abs(point.x - visibleFrame.minX)
      let rightDistance = abs(point.x - visibleFrame.maxX)
      if bottomDistance <= leftDistance, bottomDistance <= rightDistance {
        return .bottom
      }
      return leftDistance <= rightDistance ? .left : .right
    }

    static func preferredDisplay<T>(
      keyboardFocus: T?,
      pointer: T?,
      primary: T?
    ) -> T? {
      keyboardFocus ?? pointer ?? primary
    }

    private func activeScreen() -> NSScreen? {
      let pointer = NSEvent.mouseLocation
      let pointerScreen = NSScreen.screens.first { $0.frame.contains(pointer) }
      return Self.preferredDisplay(
        keyboardFocus: NSScreen.main,
        pointer: pointerScreen,
        primary: NSScreen.screens.first
      )
    }

    private static func frame(
      for dock: DictationCapsuleDock,
      size: CGSize,
      in visibleFrame: CGRect
    ) -> CGRect {
      var orientedSize =
        dock == .bottom
        ? size
        : CGSize(width: size.height, height: size.width)
      orientedSize.width = min(orientedSize.width, max(visibleFrame.width, 0))
      orientedSize.height = min(orientedSize.height, max(visibleFrame.height, 0))
      let horizontalInset = min(
        edgeInset,
        max((visibleFrame.width - orientedSize.width) / 2, 0)
      )
      let verticalInset = min(
        edgeInset,
        max((visibleFrame.height - orientedSize.height) / 2, 0)
      )
      let origin: CGPoint
      switch dock {
      case .bottom:
        origin = CGPoint(
          x: visibleFrame.midX - orientedSize.width / 2,
          y: visibleFrame.minY + verticalInset
        )
      case .left:
        origin = CGPoint(
          x: visibleFrame.minX + horizontalInset,
          y: visibleFrame.midY - orientedSize.height / 2
        )
      case .right:
        origin = CGPoint(
          x: visibleFrame.maxX - horizontalInset - orientedSize.width,
          y: visibleFrame.midY - orientedSize.height / 2
        )
      }
      return CGRect(origin: origin, size: orientedSize)
    }

    private func installContent(
      status: DictationCapsuleStatus,
      action: DictationCapsuleAction?,
      chooser: DictationCapsuleChooser?,
      onAction: @escaping @MainActor () -> Void
    ) {
      contentGeneration &+= 1
      let generation = contentGeneration
      panel.allowsActions = action != nil || chooser?.choices.isEmpty == false
      let view = AnyView(
        DictationCapsuleView(
          presentation: status.presentation,
          dock: currentDock,
          waveformModel: waveformModel,
          action: action,
          chooser: chooser,
          onAction: onAction,
          onChoice: { [weak self] captureID, noteID in
            guard let self, self.contentGeneration == generation else { return }
            self.selectRoutingChoice(captureID: captureID, noteID: noteID)
          },
          onOpenFleck: onOpenFleck
        )
      )
      if status == .idle {
        panel.contentView = DictationCapsuleIdleHostingView(
          rootView: view,
          onOpenFleck: { [weak self] in self?.onOpenFleck?() },
          onDragEnded: { [weak self] in self?.finishDrag() },
          onDockSelected: { [weak self] dock in self?.selectDock(dock) }
        )
      } else {
        panel.contentView = NSHostingView(rootView: view)
      }
    }

    private func applyCurrentFrame(animated: Bool) {
      guard let screen = resolvedScreen() else { return }
      currentScreen = screen
      let size = Self.size(for: currentStatus)
      let finalFrame = Self.frame(
        for: currentDock,
        size: size,
        in: screen.visibleFrame
      )
      let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
      guard animated else {
        panel.setFrame(finalFrame, display: true)
        panel.alphaValue = 1
        return
      }
      if reduceMotion {
        panel.alphaValue = 0
        panel.setFrame(finalFrame, display: true)
      }
      NSAnimationContext.runAnimationGroup { context in
        context.duration = reduceMotion ? 0.08 : 0.12
        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
        panel.animator().alphaValue = 1
        if !reduceMotion {
          panel.animator().setFrame(finalFrame, display: true)
        }
      }
    }

    private func finishDrag() {
      let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
      guard let screen = screen(containing: center) ?? resolvedScreen() else {
        return
      }
      selectDock(Self.nearestDock(to: center, in: screen.visibleFrame), on: screen)
    }

    private func selectDock(
      _ dock: DictationCapsuleDock,
      on screen: NSScreen? = nil
    ) {
      currentDock = dock
      if let screen { currentScreen = screen }
      installContent(
        status: currentStatus,
        action: currentAction,
        chooser: currentChooser,
        onAction: currentActionHandler
      )
      applyCurrentFrame(animated: true)
      onDockChanged?(dock)
    }

    private func resolvedScreen() -> NSScreen? {
      if let currentScreen, NSScreen.screens.contains(where: { $0 === currentScreen }) {
        return currentScreen
      }
      return panel.screen ?? activeScreen()
    }

    private func screen(containing point: CGPoint) -> NSScreen? {
      NSScreen.screens.first { $0.frame.contains(point) }
    }

    private func redockAfterScreenChange() {
      let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
      currentScreen = screen(containing: center) ?? activeScreen()
      applyCurrentFrame(animated: false)
    }

    deinit {
      if let screenParametersObserver {
        NotificationCenter.default.removeObserver(screenParametersObserver.value)
      }
    }
  }

  private struct DictationCapsuleView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let presentation: DictationCapsulePresentation
    let dock: DictationCapsuleDock
    @ObservedObject var waveformModel: DictationWaveformModel
    let action: DictationCapsuleAction?
    let chooser: DictationCapsuleChooser?
    let onAction: @MainActor () -> Void
    let onChoice: @MainActor (UUID, UUID?) -> Void
    let onOpenFleck: (@MainActor () -> Void)?

    var body: some View {
      content
        .rotationEffect(dock == .bottom ? .zero : .degrees(90))
      .foregroundStyle(.primary)
      .padding(.horizontal, presentation.visualMode == .idle ? 8 : 10)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background {
        if reduceTransparency {
          Capsule().fill(Color(nsColor: .windowBackgroundColor))
        } else {
          Capsule().fill(.regularMaterial)
        }
      }
      .accessibilityElement(children: action == nil && chooser == nil ? .ignore : .contain)
      .accessibilityLabel(presentation.voiceOverText)
      .accessibilityAction(named: Text("Open Fleck")) {
        guard presentation.visibleText == nil else { return }
        onOpenFleck?()
      }
    }

    @ViewBuilder
    private var content: some View {
      switch presentation.visualMode {
      case .listening:
        listeningContent
      case .progress:
        HStack(spacing: 8) {
          progressDots
          statusText
          chooserMenu
          actionButton
        }
      case .idle, .success, .warning, .failure:
        HStack(spacing: 8) {
          Image(systemName: presentation.symbolName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(iconColor)
          statusText
          chooserMenu
          actionButton
        }
      }
    }

    private var listeningContent: some View {
      TimelineView(
        .periodic(
          from: .now,
          by: DictationWaveformRefreshSchedule.interval(reduceMotion: reduceMotion)
        )
      ) { context in
        HStack(spacing: 9) {
          Circle()
            .fill(Color.accentColor)
            .frame(width: 6, height: 6)
          HStack(alignment: .center, spacing: 3) {
            ForEach(
              Array(
                waveformModel.barLevels(
                  at: context.date,
                  reduceMotion: reduceMotion
                ).enumerated()
              ),
              id: \.offset
            ) { _, level in
              Capsule()
                .fill(Color.accentColor)
                .frame(width: 3, height: 4 + (level * 15))
            }
          }
          Text(waveformModel.elapsedText(at: context.date))
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .frame(width: 34, alignment: .trailing)
        }
      }
    }

    private var progressDots: some View {
      Image(systemName: "ellipsis")
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(Color.accentColor)
        .symbolEffect(
          .variableColor.iterative,
          options: .repeating,
          isActive: !reduceMotion
        )
        .frame(width: 18)
    }

    @ViewBuilder
    private var statusText: some View {
      if let visibleText = presentation.visibleText {
        Text(visibleText)
          .font(.system(size: 12, weight: .semibold))
          .lineLimit(1)
      }
    }

    @ViewBuilder
    private var actionButton: some View {
      if let action {
        Button(action.title, action: onAction)
          .buttonStyle(.borderless)
          .font(.system(size: 11, weight: .semibold))
          .accessibilityLabel(action.accessibilityLabel)
      }
    }

    @ViewBuilder
    private var chooserMenu: some View {
      if let chooser, !chooser.choices.isEmpty {
        Menu("Choose note") {
          ForEach(chooser.choices) { choice in
            Button(choice.menuTitle) {
              onChoice(chooser.captureID, choice.id)
            }
            .accessibilityLabel(choice.accessibilityLabel)
            .accessibilityHint(choice.accessibilityHint)
          }
          if chooser.allowsKeepInInbox {
            Divider()
            Button(chooser.keepInboxTitle) {
              onChoice(chooser.captureID, nil)
            }
            .accessibilityLabel(chooser.keepInboxAccessibilityLabel)
            .accessibilityHint("Leaves this saved dictation in Inbox.")
          }
        }
        .menuStyle(.borderlessButton)
        .font(.system(size: 11, weight: .semibold))
        .accessibilityLabel("Choose note")
        .accessibilityHint(chooser.menuAccessibilityHint)
      }
    }

    private var iconColor: Color {
      switch presentation.visualMode {
      case .success:
        .green
      case .warning:
        .orange
      case .failure:
        .red
      case .idle, .listening, .progress:
        .accentColor
      }
    }
  }

  @MainActor
  private final class DictationCapsuleIdleHostingView: NSView {
    private let onOpenFleck: @MainActor () -> Void
    private let onDragEnded: @MainActor () -> Void
    private let onDockSelected: @MainActor (DictationCapsuleDock) -> Void

    init(
      rootView: AnyView,
      onOpenFleck: @escaping @MainActor () -> Void,
      onDragEnded: @escaping @MainActor () -> Void,
      onDockSelected: @escaping @MainActor (DictationCapsuleDock) -> Void
    ) {
      self.onOpenFleck = onOpenFleck
      self.onDragEnded = onDragEnded
      self.onDockSelected = onDockSelected
      super.init(frame: .zero)
      let hostingView = NSHostingView(rootView: rootView)
      hostingView.translatesAutoresizingMaskIntoConstraints = false
      addSubview(hostingView)
      NSLayoutConstraint.activate([
        hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
        hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
        hostingView.topAnchor.constraint(equalTo: topAnchor),
        hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
      ])
      menu = makeDockMenu()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
      guard let window else { return }
      let start = window.frame.origin
      window.performDrag(with: event)
      let end = window.frame.origin
      let movement = hypot(end.x - start.x, end.y - start.y)
      if movement < 4 {
        onOpenFleck()
      } else {
        onDragEnded()
      }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
      bounds.contains(point) ? self : nil
    }

    private func makeDockMenu() -> NSMenu {
      let menu = NSMenu()
      for (title, action) in [
        ("Dock Bottom", #selector(dockBottom)),
        ("Dock Left", #selector(dockLeft)),
        ("Dock Right", #selector(dockRight)),
      ] {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
      }
      return menu
    }

    @objc private func dockBottom() {
      onDockSelected(.bottom)
    }

    @objc private func dockLeft() {
      onDockSelected(.left)
    }

    @objc private func dockRight() {
      onDockSelected(.right)
    }
  }
#endif
