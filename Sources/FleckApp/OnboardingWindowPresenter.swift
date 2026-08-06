#if os(macOS)
  import AppKit
  import SwiftUI

  enum FleckRootContent: Equatable {
    case loading
    case resumeOnboarding
    case onboarding
    case notes
    case blocked
  }

  enum FleckRootPresentation {
    static func menuBar(for state: OnboardingGateState) -> FleckRootContent {
      switch state {
      case .loading: .loading
      case .required: .resumeOnboarding
      case .complete: .notes
      case .blocked: .blocked
      }
    }

    static func pinned(for state: OnboardingGateState) -> FleckRootContent {
      switch state {
      case .loading: .loading
      case .required: .onboarding
      case .complete: .notes
      case .blocked: .blocked
      }
    }
  }

  struct FleckMenuBarRoot: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var onboarding: OnboardingCoordinator
    @ObservedObject var dictationRuntime: DictationRuntime
    @State private var openedOnboarding = false

    var body: some View {
      Group {
        switch FleckRootPresentation.menuBar(for: onboarding.gateState) {
        case .loading:
          ProgressView("Opening Fleck…")
            .padding(28)
        case .resumeOnboarding:
          OnboardingResumePanel {
            openWindow(id: OnboardingWindowPresenter.windowIdentifier)
          }
        case .notes:
          NotesPanel(dictationRuntime: dictationRuntime)
        case .blocked:
          NotesPanel(dictationRuntime: dictationRuntime)
        case .onboarding:
          EmptyView()
        }
      }
      .background(
        FleckMenuBarPresentationProbe(rootState: panelPresentationRootState)
      )
      .task {
        await onboarding.bootstrap()
        openOnboardingIfNeeded()
      }
      .onChange(of: onboarding.gateState) {
        openOnboardingIfNeeded()
      }
    }

    private func openOnboardingIfNeeded() {
      guard onboarding.gateState == .required, !openedOnboarding else { return }
      openedOnboarding = true
      openWindow(id: OnboardingWindowPresenter.windowIdentifier)
    }

    private var panelPresentationRootState: FleckPanelPresentationRootState {
      switch onboarding.gateState {
      case .loading: .loading
      case .required: .resume
      case .complete: .notes
      case .blocked: .blocked
      }
    }
  }

  struct FleckMenuBarPresentationProbe: NSViewRepresentable {
    let rootState: FleckPanelPresentationRootState

    func makeCoordinator() -> Coordinator {
      Coordinator()
    }

    func makeNSView(context: Context) -> WindowProbeView {
      let view = WindowProbeView()
      view.windowDidChange = { [weak coordinator = context.coordinator] window in
        coordinator?.observe(window: window)
      }
      return view
    }

    func updateNSView(_ view: WindowProbeView, context: Context) {
      context.coordinator.update(rootState: rootState, window: view.window)
    }

    final class WindowProbeView: NSView {
      var windowDidChange: ((NSWindow?) -> Void)?

      override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowDidChange?(window)
      }
    }

    @MainActor
    final class Coordinator: NSObject {
      private let measurement = FleckPanelPresentationMeasurement.shared
      private var rootState: FleckPanelPresentationRootState = .loading
      private weak var observedWindow: NSWindow?
      private var observers: [NSObjectProtocol] = []

      isolated deinit {
        removeObservers()
        measurement.cancel()
      }

      func update(
        rootState: FleckPanelPresentationRootState,
        window: NSWindow?
      ) {
        self.rootState = rootState
        observe(window: window)
      }

      func observe(window: NSWindow?) {
        guard observedWindow !== window else {
          completeIfVisible(window)
          return
        }
        removeObservers()
        observedWindow = window
        guard let window else { return }

        let notificationCenter = NotificationCenter.default
        for name in [
          NSWindow.didBecomeKeyNotification,
          NSWindow.didBecomeMainNotification,
        ] {
          observers.append(
            notificationCenter.addObserver(
              forName: name,
              object: window,
              queue: .main
            ) { [weak self, weak window] _ in
              Task { @MainActor [weak self, weak window] in
                self?.completeIfVisible(window)
              }
            }
          )
        }
        observers.append(
          notificationCenter.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
          ) { [weak self] _ in
            Task { @MainActor [weak self] in
              self?.measurement.cancel()
            }
          }
        )
        observers.append(
          notificationCenter.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
          ) { [weak self] _ in
            Task { @MainActor [weak self] in
              self?.removeObservers()
            }
          }
        )
        completeIfVisible(window)
      }

      private func completeIfVisible(_ window: NSWindow?) {
        guard
          let window,
          window === observedWindow,
          window.level == .statusBar,
          window.isVisible
        else { return }
        measurement.end(rootState: rootState)
      }

      private func removeObservers() {
        for observer in observers {
          NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        observedWindow = nil
        measurement.cancel()
      }
    }
  }

  struct FleckPinnedNotesRoot: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var onboarding: OnboardingCoordinator
    @ObservedObject var dictationRuntime: DictationRuntime

    var body: some View {
      Group {
        switch FleckRootPresentation.pinned(for: onboarding.gateState) {
        case .loading:
          ProgressView("Opening Fleck…")
            .frame(width: 520, height: 430)
        case .onboarding:
          OnboardingFlowView(
            coordinator: onboarding,
            dictationRuntime: dictationRuntime
          )
        case .notes:
          NotesPanel(dictationRuntime: dictationRuntime, isPinned: true, sizing: .container)
        case .blocked:
          NotesPanel(dictationRuntime: dictationRuntime, isPinned: true, sizing: .container)
        case .resumeOnboarding:
          EmptyView()
        }
      }
      .background(
        OnboardingWindowPresenter(
          gateState: onboarding.gateState,
          completedSize: NSSize(
            width: appState.preferences.pinnedPanelWidth,
            height: appState.preferences.pinnedPanelHeight
          ),
          onCompletedResize: { size in
            guard appState.preferences.pinnedPanelWidth != size.width
              || appState.preferences.pinnedPanelHeight != size.height
            else { return }
            appState.updatePreferences {
              $0.pinnedPanelWidth = size.width
              $0.pinnedPanelHeight = size.height
            }
          }
        )
      )
      .task {
        await onboarding.bootstrap()
      }
    }
  }

  struct OnboardingResumePanel: View {
    let resume: () -> Void

    var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        Label("Finish setting up Fleck", systemImage: "sparkles")
          .font(.headline)
        Text("Your place is saved. Continue onboarding to use Fleck.")
          .font(.callout)
          .foregroundStyle(.secondary)
        Button("Resume Onboarding", action: resume)
          .buttonStyle(.borderedProminent)
      }
      .padding(20)
      .frame(width: 320, alignment: .leading)
    }
  }

  struct OnboardingWindowPresenter: NSViewRepresentable {
    nonisolated static let windowIdentifier = "pinned-notes"
    nonisolated static let onboardingTitle = "Welcome to Fleck"
    nonisolated static let completedTitle = "Fleck"
    nonisolated static let defaultSize = NSSize(width: 1_080, height: 700)
    nonisolated static let minimumSize = NSSize(width: 760, height: 520)
    nonisolated static let completedMinimumSize = NSSize(width: 480, height: 320)

    let gateState: OnboardingGateState
    let completedSize: NSSize
    let onCompletedResize: (NSSize) -> Void

    nonisolated static func clampedCompletedSize(
      _ size: NSSize,
      visibleFrame: NSRect
    ) -> NSSize {
      NSSize(
        width: min(max(size.width, completedMinimumSize.width), visibleFrame.width),
        height: min(max(size.height, completedMinimumSize.height), visibleFrame.height)
      )
    }

    @MainActor static func maximumCompletedContentSize(
      for window: NSWindow,
      visibleFrame: NSRect
    ) -> NSSize {
      window.contentRect(forFrameRect: visibleFrame).size
    }

    nonisolated static func clampedCompletedSize(
      _ size: NSSize,
      maximumContentSize: NSSize
    ) -> NSSize {
      NSSize(
        width: min(max(size.width, completedMinimumSize.width), maximumContentSize.width),
        height: min(max(size.height, completedMinimumSize.height), maximumContentSize.height)
      )
    }

    func makeCoordinator() -> Coordinator {
      Coordinator()
    }

    func makeNSView(context _: Context) -> NSView {
      NSView(frame: .zero)
    }

    func updateNSView(_ view: NSView, context: Context) {
      DispatchQueue.main.async {
        context.coordinator.apply(
          gateState: gateState,
          completedSize: completedSize,
          onCompletedResize: onCompletedResize,
          to: view.window
        )
      }
    }

    @MainActor
    final class Coordinator: NSObject {
      private let visibleFrameProvider: (NSWindow) -> NSRect
      private var appliedState: OnboardingGateState?
      private weak var observedWindow: NSWindow?
      private var onCompletedResize: ((NSSize) -> Void)?

      init(
        visibleFrameProvider: @escaping (NSWindow) -> NSRect = { window in
          window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
        }
      ) {
        self.visibleFrameProvider = visibleFrameProvider
      }

      isolated deinit {
        NotificationCenter.default.removeObserver(self)
      }

      func apply(
        gateState: OnboardingGateState,
        completedSize: NSSize,
        onCompletedResize: @escaping (NSSize) -> Void,
        to window: NSWindow?
      ) {
        guard let window else { return }
        observe(window: window, onCompletedResize: onCompletedResize)
        guard appliedState != gateState else { return }
        appliedState = gateState
        switch gateState {
        case .required:
          window.title = OnboardingWindowPresenter.onboardingTitle
          window.contentMinSize = OnboardingWindowPresenter.minimumSize
          window.setContentSize(OnboardingWindowPresenter.defaultSize)
          NSApp.activate(ignoringOtherApps: true)
          window.makeKeyAndOrderFront(nil)
        case .complete:
          window.title = OnboardingWindowPresenter.completedTitle
          window.contentMinSize = OnboardingWindowPresenter.completedMinimumSize
          window.styleMask.insert(.resizable)
          applyCompletedBounds(to: window, requestedSize: completedSize)
        case .loading, .blocked:
          break
        }
      }

      private func observe(
        window: NSWindow,
        onCompletedResize: @escaping (NSSize) -> Void
      ) {
        self.onCompletedResize = onCompletedResize
        guard observedWindow !== window else { return }
        if let observedWindow {
          NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didEndLiveResizeNotification,
            object: observedWindow
          )
          NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didChangeScreenNotification,
            object: observedWindow
          )
        }
        observedWindow = window
        appliedState = nil
        NotificationCenter.default.addObserver(
          self,
          selector: #selector(handleLiveResize(_:)),
          name: NSWindow.didEndLiveResizeNotification,
          object: window
        )
        NotificationCenter.default.addObserver(
          self,
          selector: #selector(handleScreenChange(_:)),
          name: NSWindow.didChangeScreenNotification,
          object: window
        )
      }

      @objc private func handleLiveResize(_ notification: Notification) {
        guard appliedState == .complete,
          let resizedWindow = notification.object as? NSWindow,
          let contentSize = resizedWindow.contentView?.bounds.size
        else { return }
        let clampedSize = applyCompletedBounds(to: resizedWindow, requestedSize: contentSize)
        onCompletedResize?(clampedSize)
      }

      @objc private func handleScreenChange(_ notification: Notification) {
        guard appliedState == .complete,
          let window = notification.object as? NSWindow,
          let contentSize = window.contentView?.bounds.size
        else { return }
        let clampedSize = applyCompletedBounds(to: window, requestedSize: contentSize)
        guard contentSize != clampedSize else { return }
        onCompletedResize?(clampedSize)
      }

      @discardableResult
      private func applyCompletedBounds(
        to window: NSWindow,
        requestedSize: NSSize
      ) -> NSSize {
        let maximumContentSize = OnboardingWindowPresenter.maximumCompletedContentSize(
          for: window,
          visibleFrame: visibleFrameProvider(window)
        )
        let clampedSize = OnboardingWindowPresenter.clampedCompletedSize(
          requestedSize,
          maximumContentSize: maximumContentSize
        )
        window.contentMaxSize = maximumContentSize
        if window.contentView?.bounds.size != clampedSize {
          window.setContentSize(clampedSize)
        }
        fit(window: window, inside: visibleFrameProvider(window))
        return clampedSize
      }

      private func fit(window: NSWindow, inside visibleFrame: NSRect) {
        var frame = window.frame
        frame.origin.x = min(max(frame.origin.x, visibleFrame.minX), visibleFrame.maxX - frame.width)
        frame.origin.y = min(max(frame.origin.y, visibleFrame.minY), visibleFrame.maxY - frame.height)
        window.setFrame(frame, display: true)
      }
    }
  }
#endif
