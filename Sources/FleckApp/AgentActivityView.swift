#if os(macOS)
  import AppKit
  import SwiftUI
  import FleckCore

  enum AgentPresentation {
    static func visibleNoteIDs(
      in workspace: Workspace,
      activeProfiles: [AgentProfileCapabilities] = []
    ) -> Set<UUID> {
      Set(
        activeProfiles.flatMap {
          AgentCapabilityPolicy.authorizationSnapshot(
            for: $0,
            workspace: workspace
          ).readableNoteIDs
        }
      )
    }

  }

  struct AgentSharingPresentation {
    static let sharedBadgeAccessibilityLabel = "Shared with agents"

    static func isShared(
      noteID: UUID,
      activeProfiles: [AgentProfileCapabilities],
      workspace: Workspace
    ) -> Bool {
      AgentCapabilityPresentation.isShared(
        noteID: noteID,
        activeProfiles: activeProfiles,
        workspace: workspace
      )
    }
  }

  enum AgentActivityClearPresentation {
    static let requiresConfirmation = true
  }

  final class AgentActivityScroller: NSScroller {
    static let visualKnobWidth: CGFloat = 4
    static let visualMinimumKnobLength: CGFloat = 24
    static let visualTrailingInset: CGFloat = 3
    static let visualTrackInset: CGFloat = 3

    private var heldVisualKnobLength: CGFloat?
    private var heldVisualKnobOrigin: (initial: CGFloat, proportional: CGFloat)?
    var knobColor = NSColor.secondaryLabelColor {
      didSet { needsDisplay = true }
    }

    override class var isCompatibleWithOverlayScrollers: Bool { true }

    var visualKnobRect: NSRect {
      visualKnobGeometry.rect
    }

    private var visualKnobGeometry: (rect: NSRect, proportionalY: CGFloat) {
      let width = min(Self.visualKnobWidth, bounds.width)
      let trackInset = min(Self.visualTrackInset, bounds.height / 2)
      let track = bounds.insetBy(dx: 0, dy: trackInset)
      guard width > 0, track.height > 0 else { return (.zero, 0) }

      let proportion = min(max(knobProportion, 0), 1)
      let naturalLength = track.height * proportion
      let length = min(
        track.height,
        heldVisualKnobLength ?? floor(max(Self.visualMinimumKnobLength, naturalLength))
      )
      let position = min(max(CGFloat(doubleValue), 0), 1)
      let travel = track.height - length
      let proportionalY = isFlipped
        ? track.minY + travel * position
        : track.maxY - length - travel * position
      let trailingInset = min(Self.visualTrailingInset, bounds.width - width)
      let x = bounds.maxX - trailingInset - width
      var y = proportionalY

      if let heldOrigin = heldVisualKnobOrigin {
        let translatedY = proportionalY == heldOrigin.proportional
          ? heldOrigin.initial
          : heldOrigin.initial + (proportionalY - heldOrigin.proportional)
        let maximumY = track.maxY - length
        if translatedY.isFinite, track.minY.isFinite, maximumY.isFinite {
          y = min(max(translatedY, track.minY), maximumY)
        }
      } else if heldVisualKnobLength == nil {
        let native = rect(for: .knob)
        let minimumY = max(native.minY, track.minY)
        let maximumY = min(native.maxY - length, track.maxY - length)
        let finiteGeometry = [
          bounds.minX, bounds.minY, bounds.maxX, bounds.maxY, bounds.width, bounds.height,
          track.minY, track.maxY, width, length, knobProportion, CGFloat(doubleValue),
          x, x + width, proportionalY, native.minX, native.minY, native.maxX, native.maxY,
          native.width, native.height, minimumY, maximumY,
        ].allSatisfy { $0.isFinite }
        if finiteGeometry, bounds.width > 0, bounds.height > 0,
          native.width > 0, native.height >= length,
          native.minX <= x, x + width <= native.maxX, minimumY <= maximumY
        {
          let projectedY = min(max(proportionalY, minimumY), maximumY)
          if projectedY != proportionalY {
            y = projectedY
          }
        }
      }

      return (
        NSRect(x: x, y: y, width: width, height: length),
        proportionalY
      )
    }

    override func drawKnob() {
      let rect = visualKnobRect
      guard !rect.isEmpty else { return }
      knobColor.withAlphaComponent(0.7).setFill()
      NSBezierPath(
        roundedRect: rect,
        xRadius: Self.visualKnobWidth / 2,
        yRadius: Self.visualKnobWidth / 2
      ).fill()
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}

    override func mouseDown(with event: NSEvent) {
      guard testPart(event.locationInWindow) == .knob else {
        super.mouseDown(with: event)
        return
      }

      withHeldVisualKnobGeometry {
        super.mouseDown(with: event)
      }
    }

    func withHeldVisualKnobGeometry(_ body: () -> Void) {
      let initial = visualKnobGeometry
      heldVisualKnobLength = initial.rect.height
      heldVisualKnobOrigin = nil
      if initial.rect.minY.isFinite, initial.proportionalY.isFinite,
        initial.rect.minY != initial.proportionalY
      {
        heldVisualKnobOrigin = (initial.rect.minY, initial.proportionalY)
      }
      defer {
        heldVisualKnobLength = nil
        heldVisualKnobOrigin = nil
        needsDisplay = true
      }
      body()
    }
  }

  struct AgentActivityScrollViewConfigurator: NSViewRepresentable {
    @Environment(\.fleckThemeSnapshot) private var theme

    func makeNSView(context: Context) -> AgentActivityScrollViewConfigurationView {
      let view = AgentActivityScrollViewConfigurationView()
      view.updateKnobColor(theme.nsColor(.textSecondary))
      return view
    }

    func updateNSView(_ view: AgentActivityScrollViewConfigurationView, context: Context) {
      view.updateKnobColor(theme.nsColor(.textSecondary))
    }
  }

  final class AgentActivityScrollViewConfigurationView: NSView {
    private var knobColor = NSColor.secondaryLabelColor

    override func viewDidMoveToSuperview() {
      super.viewDidMoveToSuperview()
      configureScrollView()
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      configureScrollView()
    }

    override func layout() {
      super.layout()
      configureScrollView()
    }

    func configureScrollView() {
      guard let scrollView = enclosingScrollView else { return }
      scrollView.drawsBackground = false
      scrollView.hasVerticalScroller = true
      scrollView.autohidesScrollers = true
      scrollView.scrollerStyle = .overlay
      var scrollerInsets = scrollView.scrollerInsets
      scrollerInsets.right = 2
      scrollView.scrollerInsets = scrollerInsets
      if let scroller = scrollView.verticalScroller as? AgentActivityScroller {
        scroller.knobColor = knobColor
      } else {
        let scroller = AgentActivityScroller()
        scroller.knobColor = knobColor
        scrollView.verticalScroller = scroller
        scrollView.reflectScrolledClipView(scrollView.contentView)
      }
    }

    func updateKnobColor(_ color: NSColor) {
      knobColor = color
      configureScrollView()
    }
  }

  struct AgentActivityDiffLine: Equatable {
    enum Kind: Equatable {
      case unchanged
      case removed
      case added
    }

    let kind: Kind
    let text: String

    var marker: String {
      switch kind {
      case .unchanged: " "
      case .removed: "-"
      case .added: "+"
      }
    }

    var accessibilityLabel: String {
      let description =
        switch kind {
        case .unchanged: "Unchanged"
        case .removed: "Removed"
        case .added: "Added"
        }
      return text.isEmpty ? "\(description) empty line" : "\(description): \(text)"
    }
  }

  enum AgentActivityLineDiff {
    private static let maximumLineCount = 400
    private static let maximumUTF8ByteCount = 1024 * 1024

    static func lines(before: String, after: String) -> [AgentActivityDiffLine]? {
      guard before.utf8.count + after.utf8.count <= maximumUTF8ByteCount else {
        return nil
      }
      let beforeLines = splitLines(before)
      let afterLines = splitLines(after)
      guard beforeLines.count + afterLines.count <= maximumLineCount else {
        return nil
      }

      var removals = Set<Int>()
      var insertions = Set<Int>()
      for change in afterLines.difference(from: beforeLines) {
        switch change {
        case .remove(let offset, _, _): removals.insert(offset)
        case .insert(let offset, _, _): insertions.insert(offset)
        }
      }

      var lines: [AgentActivityDiffLine] = []
      var beforeIndex = 0
      var afterIndex = 0
      while beforeIndex < beforeLines.count || afterIndex < afterLines.count {
        if beforeIndex < beforeLines.count, removals.contains(beforeIndex) {
          lines.append(.init(kind: .removed, text: beforeLines[beforeIndex]))
          beforeIndex += 1
        } else if afterIndex < afterLines.count, insertions.contains(afterIndex) {
          lines.append(.init(kind: .added, text: afterLines[afterIndex]))
          afterIndex += 1
        } else if beforeIndex < beforeLines.count, afterIndex < afterLines.count {
          lines.append(.init(kind: .unchanged, text: beforeLines[beforeIndex]))
          beforeIndex += 1
          afterIndex += 1
        } else if beforeIndex < beforeLines.count {
          lines.append(.init(kind: .removed, text: beforeLines[beforeIndex]))
          beforeIndex += 1
        } else {
          lines.append(.init(kind: .added, text: afterLines[afterIndex]))
          afterIndex += 1
        }
      }
      return lines
    }

    private static func splitLines(_ text: String) -> [String] {
      guard !text.isEmpty else { return [] }
      let normalized = text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
      return normalized.components(separatedBy: "\n")
    }
  }

  struct AgentActivityRowPresentation: Identifiable {
    let record: AgentActivityRecord
    let integrationName: String
    let noteTitle: String
    let operationDescription: String
    let timestamp: Date
    let beforeText: String
    let afterText: String
    let diffLines: [AgentActivityDiffLine]?
    let canUndo: Bool

    var id: UUID { record.changeID }

    init(
      record: AgentActivityRecord,
      activeNote: Note?,
      activeProfileIDs: Set<UUID>
    ) {
      self.record = record
      integrationName = Self.actorName(record.actor)
      noteTitle = record.noteTitle
      operationDescription = Self.operationName(record.operation)
      timestamp = record.createdAt
      beforeText = record.patch.beforeText
      afterText = record.patch.afterText
      diffLines = AgentActivityLineDiff.lines(
        before: record.patch.beforeText,
        after: record.patch.afterText
      )
      canUndo =
        activeNote.map { (try? AgentUndoEngine.draft(inverting: record.patch, in: $0.body)) != nil }
        ?? false
    }

    var copiedDetails: String {
      """
      \(integrationName) \(operationDescription.lowercased()) in \(noteTitle)
      \(timestamp.formatted(date: .abbreviated, time: .standard))
      Before: \(beforeText)
      After: \(afterText)
      """
    }

    private static func actorName(_ actor: AgentActivityActor) -> String {
      switch actor {
      case .integration(_, let displayName): displayName
      case .localUser: "Fleck"
      }
    }

    private static func operationName(_ operation: AgentActivityOperation) -> String {
      switch operation {
      case .appendText: "Appended text"
      case .insertText: "Inserted text"
      case .replaceLines: "Replaced lines"
      case .addTask: "Added task"
      case .renameTask: "Renamed task"
      case .setTaskState: "Updated task"
      case .removeTask: "Removed task"
      case .undoChange: "Undid change"
      }
    }
  }

  struct AgentActivityView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.fleckThemeSnapshot) private var theme
    let onOpenNote: (UUID) -> Void
    let onDismiss: () -> Void
    @State private var showsClearConfirmation = false

    var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text("Agent Activity").font(.title2.weight(.semibold))
          Spacer()
          Button("Clear Activity", role: .destructive) {
            showsClearConfirmation = true
          }
          .disabled(appState.agentActivity.isEmpty)
          Button("Done") {
            onDismiss()
          }
          .keyboardShortcut(.cancelAction)
          .accessibilityLabel("Close Agent Activity")
        }
        .padding(.horizontal, 18)

        if appState.agentActivity.isEmpty {
          ContentUnavailableView(
            "No Agent Activity",
            systemImage: "point.3.connected.trianglepath.dotted",
            description: Text("Changes made by authorized integrations appear here.")
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .padding(.horizontal, 18)
          .padding(.bottom, 18)
        } else {
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
              ForEach(rows) { row in
                activityRow(row)
              }
            }
            .padding(.horizontal, 18)
            .background(AgentActivityScrollViewConfigurator())
          }
          .padding(.bottom, 18)
        }
      }
      .padding(.top, 18)
      .task { appState.refreshAgentActivity() }
      .confirmationDialog(
        "Clear Agent Activity?",
        isPresented: $showsClearConfirmation
      ) {
        Button("Clear Activity", role: .destructive) {
          appState.clearAgentActivity()
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Visible patches are removed. Retry-protection tombstones remain until expiry.")
      }
    }

    private var rows: [AgentActivityRowPresentation] {
      let profiles = Set(appState.agentProfiles.map(\.id))
      return appState.agentActivity.map { record in
        AgentActivityRowPresentation(
          record: record,
          activeNote: appState.workspace.notes.first { $0.id == record.noteID },
          activeProfileIDs: profiles
        )
      }
    }

    private func activityRow(_ row: AgentActivityRowPresentation) -> some View {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text(row.integrationName).font(.headline)
          Text("· \(row.noteTitle)").foregroundStyle(theme.color(.textSecondary))
          Spacer()
          Text(row.timestamp, style: .relative)
            .font(.caption)
            .foregroundStyle(theme.color(.caption))
        }
        Text(row.operationDescription).font(.callout)
        if let lines = row.diffLines {
          diff(lines)
        } else {
          patch("Before", row.beforeText)
          patch("After", row.afterText)
          Text("This change is too large to display as a line diff.")
            .font(.caption2)
            .foregroundStyle(theme.color(.caption))
        }
        HStack {
          Button("Open Note") {
            onOpenNote(row.record.noteID)
          }
          Button("Copy Details") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(row.copiedDetails, forType: .string)
          }
          Spacer()
          Button("Undo") {
            Task { await appState.undoAgentChange(row.record) }
          }
          .disabled(!row.canUndo)
        }
      }
      .padding(12)
      .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    private func diff(_ lines: [AgentActivityDiffLine]) -> some View {
      VStack(alignment: .leading, spacing: 3) {
        Text("Changes")
          .font(.caption.weight(.medium))
          .foregroundStyle(theme.color(.caption))
        if lines.isEmpty {
          Text("—")
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(theme.color(.caption))
        } else {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(lines.indices, id: \.self) { index in
              diffLine(lines[index])
            }
          }
          .clipShape(RoundedRectangle(cornerRadius: 6))
          .textSelection(.enabled)
        }
      }
    }

    private func diffLine(_ line: AgentActivityDiffLine) -> some View {
      HStack(alignment: .top, spacing: 6) {
        Text(line.marker)
          .font(.system(.caption, design: .monospaced).weight(.semibold))
          .frame(width: 10, alignment: .center)
        Text(line.text.isEmpty ? " " : line.text)
          .font(.system(.caption, design: .monospaced))
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .foregroundStyle(diffColor(line.kind))
      .padding(.horizontal, 6)
      .padding(.vertical, 1)
      .background(diffBackground(line.kind))
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(line.accessibilityLabel)
    }

    private func diffColor(_ kind: AgentActivityDiffLine.Kind) -> Color {
      switch kind {
      case .unchanged: theme.color(.textSecondary)
      case .removed: theme.color(.error)
      case .added: theme.color(.success)
      }
    }

    private func diffBackground(_ kind: AgentActivityDiffLine.Kind) -> Color {
      let opacity = theme.increasedContrast ? 0.20 : 0.10
      return switch kind {
      case .unchanged: .clear
      case .removed: theme.color(.error).opacity(opacity)
      case .added: theme.color(.success).opacity(opacity)
      }
    }

    private func patch(_ label: String, _ text: String) -> some View {
      VStack(alignment: .leading, spacing: 2) {
        Text(label)
          .font(.caption.weight(.medium))
          .foregroundStyle(theme.color(.caption))
        Text(text.isEmpty ? "—" : text)
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
      }
    }
  }
#endif
