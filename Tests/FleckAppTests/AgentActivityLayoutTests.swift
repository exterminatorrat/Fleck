#if os(macOS)
  import AppKit
  import FleckCore
  import Foundation
  import SwiftUI
  import Testing

  @testable import FleckApp

  @Suite("AgentActivityLayout", .serialized)
  struct AgentActivityLayoutTests {
    @Test @MainActor
    func emptyMinimumAndEnlargedLayoutsFillTheirProposal() async throws {
      for size in [NSSize(width: 520, height: 380), NSSize(width: 720, height: 520)] {
        let fixture = try await makeFixture()
        defer { fixture.remove() }
        let hosted = await host(
          state: fixture.state,
          size: size,
          content: .minimum
        )
        defer { hosted.remove() }

        #expect(!hosted.window.isVisible)
        #expect(hosted.activityFrame.origin == .zero)
        #expect(hosted.activityFrame.size == size)
      }
    }

    @Test @MainActor
    func emptyOverlayStaysCenteredAndInsideItsCappedHost() async throws {
      for size in [NSSize(width: 380, height: 300), NSSize(width: 800, height: 430)] {
        let fixture = try await makeFixture()
        defer { fixture.remove() }
        let hosted = await host(
          state: fixture.state,
          size: size,
          content: .overlay
        )
        defer { hosted.remove() }

        #expect(!hosted.window.isVisible)
        let expectedSize = NSSize(
          width: min(520, size.width - 16),
          height: min(400, size.height - 16)
        )
        #expect(hosted.activityFrame.size == expectedSize)
        #expect(abs(hosted.activityFrame.midX - hosted.host.bounds.midX) <= 1)
        #expect(abs(hosted.activityFrame.midY - hosted.host.bounds.midY) <= 1)
        #expect(hosted.host.bounds.contains(hosted.activityFrame))
      }
    }

    @Test @MainActor
    func populatedAndTransitionedEmptyLayoutsPreserveActualContent() async throws {
      let fixture = try await makeFixture(populated: true)
      defer { fixture.remove() }
      let hosted = await host(
        state: fixture.state,
        size: NSSize(width: 520, height: 380),
        content: .minimum
      )
      defer { hosted.remove() }

      #expect(!hosted.window.isVisible)
      #expect(fixture.state.agentActivity.count == 1)
      #expect(hosted.activityFrame == hosted.host.bounds)

      try fixture.activityStore.clearVisibleActivity()
      fixture.state.refreshAgentActivity()
      await settle(hosted.host)

      #expect(fixture.state.agentActivity.isEmpty)
      #expect(hosted.activityFrame == hosted.host.bounds)
    }

    @Test @MainActor
    func capturesHiddenEmptyLayoutsWhenRequested() async throws {
      guard let directory = ProcessInfo.processInfo.environment[
        "FLECK_AGENT_ACTIVITY_CAPTURE_DIR"
      ] else { return }
      let prefix = ProcessInfo.processInfo.environment[
        "FLECK_AGENT_ACTIVITY_CAPTURE_PREFIX"
      ] ?? "agent-activity"

      for (name, size, content, scheme, typeSize, populated) in [
        ("light", NSSize(width: 520, height: 380), ActivityContent.minimum,
          ColorScheme.light, DynamicTypeSize.large, false),
        ("dark", NSSize(width: 520, height: 380), .minimum, .dark, .large, false),
        ("larger-text", NSSize(width: 520, height: 380), .minimum,
          .light, .accessibility5, false),
        ("enlarged", NSSize(width: 720, height: 520), .minimum, .light, .large, false),
        ("overlay-compact", NSSize(width: 380, height: 300), .overlay,
          .light, .large, false),
        ("overlay-large", NSSize(width: 800, height: 430), .overlay,
          .light, .large, false),
        ("populated", NSSize(width: 520, height: 380), .minimum, .light, .large, true),
      ] {
        let fixture = try await makeFixture(populated: populated)
        defer { fixture.remove() }
        let hosted = await host(
          state: fixture.state,
          size: size,
          content: content,
          colorScheme: scheme,
          dynamicTypeSize: typeSize
        )
        defer { hosted.remove() }
        #expect(!hosted.window.isVisible)
        try capture(
          hosted.host,
          at: URL(fileURLWithPath: directory)
            .appendingPathComponent("\(prefix)-\(name).png")
        )
        if populated {
          try fixture.activityStore.clearVisibleActivity()
          fixture.state.refreshAgentActivity()
          await settle(hosted.host)
          try capture(
            hosted.host,
            at: URL(fileURLWithPath: directory)
              .appendingPathComponent("\(prefix)-transitioned-empty.png")
          )
        }
      }
    }

    @MainActor
    private func makeFixture(populated: Bool = false) async throws -> ActivityFixture {
      let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("AgentActivityLayout-\(UUID().uuidString)", isDirectory: true)
      let activityStore = AgentActivityStore(rootURL: root)
      let state = AppState(
        store: LocalStore(rootURL: root),
        saveOperation: { _, _, _, _ in .committed },
        agentActivityStore: activityStore
      )
      await state.waitUntilInitialLoad()
      if populated, let note = state.workspace.notes.first {
        let transaction = PreparedAgentTransaction(
          changeID: UUID(),
          noteID: note.id,
          noteTitle: "Synthetic Note",
          actor: .integration(profileID: UUID(), displayName: "Synthetic Agent"),
          operationID: UUID(),
          createdAt: Date(),
          operation: .appendText,
          patch: AgentTextPatch(
            beforeText: "before",
            afterText: "after",
            range: NSRange(location: 0, length: 0),
            prefixContext: "",
            suffixContext: ""
          ),
          previousRevision: 0,
          resultingRevision: 1,
          resultingBodySHA256: ""
        )
        try activityStore.prepare(transaction)
        try activityStore.commit(
          changeID: transaction.changeID,
          receipt: AgentWriteReceipt(
            changeID: transaction.changeID,
            noteID: note.id,
            previousRevision: 0,
            resultingRevision: 1
          )
        )
        state.refreshAgentActivity()
      }
      return ActivityFixture(root: root, state: state, activityStore: activityStore)
    }

    @MainActor
    private func host(
      state: AppState,
      size: NSSize,
      content: ActivityContent,
      colorScheme: ColorScheme = .light,
      dynamicTypeSize: DynamicTypeSize = .large
    ) async -> HostedActivity {
      let probe = ActivityFrameProbe()
      let activity = AgentActivityView(onOpenNote: { _ in }, onDismiss: {})
        .environmentObject(state)
        .environment(\.colorScheme, colorScheme)
        .environment(\.dynamicTypeSize, dynamicTypeSize)
        .background(ActivityFrameReader(probe: probe))
      let rootView = switch content {
      case .minimum:
        AnyView(activity.frame(minWidth: 520, minHeight: 380))
      case .overlay:
        AnyView(
          ZStack {
            Color.clear
            activity.frame(maxWidth: 520, maxHeight: 400).padding(8)
          }
        )
      }
      let host = NSHostingView(
        rootView: AnyView(
          rootView.background(colorScheme == .dark ? Color.black : Color.white)
        )
      )
      let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.titled],
        backing: .buffered,
        defer: false
      )
      window.contentView = host
      await settle(host)
      return HostedActivity(window: window, host: host, probe: probe)
    }

    @MainActor
    private func settle(_ host: NSView) async {
      for _ in 0..<8 {
        host.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(10))
      }
    }

    @MainActor
    private func capture(_ host: NSView, at destination: URL) throws {
      let representation = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: representation)
      try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try #require(
        representation.representation(using: .png, properties: [:])
      ).write(to: destination)
    }
  }

  private enum ActivityContent {
    case minimum
    case overlay
  }

  @MainActor
  private final class ActivityFrameProbe {
    weak var view: NSView?
  }

  @MainActor
  private struct ActivityFrameReader: NSViewRepresentable {
    let probe: ActivityFrameProbe

    func makeNSView(context: Context) -> NSView {
      let view = NSView()
      probe.view = view
      return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
      probe.view = nsView
    }
  }

  @MainActor
  private struct ActivityFixture {
    let root: URL
    let state: AppState
    let activityStore: AgentActivityStore

    func remove() {
      try? FileManager.default.removeItem(at: root)
    }
  }

  @MainActor
  private struct HostedActivity {
    let window: NSWindow
    let host: NSHostingView<AnyView>
    let probe: ActivityFrameProbe

    var activityFrame: CGRect {
      guard let view = probe.view else { return .null }
      return view.convert(view.bounds, to: host)
    }

    func remove() {
      window.contentView = nil
      window.orderOut(nil)
    }
  }
#endif
