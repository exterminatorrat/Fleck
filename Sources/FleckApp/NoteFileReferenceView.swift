#if os(macOS)
  import AppKit
  import SwiftUI

  @MainActor
  struct NoteFilePicker {
    enum Result: Equatable {
      case accepted(URL)
      case cancelled
      case aborted

      init(response: NSApplication.ModalResponse, url: URL?) {
        if response == .OK, let url {
          self = .accepted(url)
        } else if response == .cancel {
          self = .cancelled
        } else {
          self = .aborted
        }
      }
    }

    @MainActor
    final class Presenter {
      typealias ScheduledWork = @MainActor () -> Void

      private let schedule: (@escaping ScheduledWork) -> Void
      private let present: () -> Result
      private(set) var isPresenting = false

      init(
        schedule: @escaping (@escaping ScheduledWork) -> Void,
        present: @escaping () -> Result
      ) {
        self.schedule = schedule
        self.present = present
      }

      @discardableResult
      func chooseFile(completion: @escaping (Result) -> Void) -> Bool {
        guard !isPresenting else { return false }
        isPresenting = true
        schedule { [self] in
          let result = self.present()
          self.isPresenting = false
          completion(result)
        }
        return true
      }
    }

    let chooseFile: (@escaping (Result) -> Void) -> Bool

    init(presenter: Presenter) {
      chooseFile = presenter.chooseFile
    }

    init(chooseFile: @escaping (@escaping (Result) -> Void) -> Bool) {
      self.chooseFile = chooseFile
    }

    static let live = NoteFilePicker(
      presenter: Presenter(
        schedule: { work in
          Task { @MainActor in work() }
        },
        present: {
          presentLive()
        }
      )
    )

    private static func presentLive() -> Result {
      let panel = NSOpenPanel()
      panel.title = "Choose a File"
      panel.prompt = "Choose"
      panel.canChooseFiles = true
      panel.canChooseDirectories = false
      panel.allowsMultipleSelection = false
      panel.resolvesAliases = true
      NSApp.activate(ignoringOtherApps: true)
      let result = Result(response: panel.runModal(), url: panel.url)
      panel.orderOut(nil)
      return result
    }
  }

  struct NoteFileReferenceLayout {
    struct Item: Identifiable {
      let reference: NoteFileReferencePresentation
      let width: CGFloat

      var id: UUID { reference.id }
    }

    struct Plan {
      let rows: [[Item]]
      let overflow: [NoteFileReferencePresentation]
      let chipAreaWidth: CGFloat
    }

    static let spacing: CGFloat = 6
    private static let addControlWidth: CGFloat = 54
    private static let overflowWidth: CGFloat = 38
    private static let minimumChipWidth: CGFloat = 132
    private static let maximumChipWidth: CGFloat = 220

    static func plan(
      references: [NoteFileReferencePresentation],
      availableWidth: CGFloat
    ) -> Plan {
      let availableChipWidth = max(
        1,
        availableWidth - addControlWidth - spacing
      )
      let fullWidthPlan = pack(references, into: availableChipWidth)
      guard !fullWidthPlan.overflow.isEmpty else { return fullWidthPlan }
      return pack(
        references,
        into: max(1, availableChipWidth - overflowWidth - spacing)
      )
    }

    private static func pack(
      _ references: [NoteFileReferencePresentation],
      into width: CGFloat
    ) -> Plan {
      var row: [Item] = []
      var usedWidth = CGFloat.zero
      var overflow: [NoteFileReferencePresentation] = []

      for (index, reference) in references.enumerated() {
        let itemWidth = min(desiredWidth(for: reference), width)
        let gap = row.isEmpty ? 0 : spacing
        guard usedWidth + gap + itemWidth <= width else {
          overflow.append(contentsOf: references[index...])
          break
        }
        row.append(Item(reference: reference, width: itemWidth))
        usedWidth += gap + itemWidth
      }

      return Plan(
        rows: row.isEmpty ? [] : [row],
        overflow: overflow,
        chipAreaWidth: width
      )
    }

    private static func desiredWidth(
      for reference: NoteFileReferencePresentation
    ) -> CGFloat {
      let estimatedTextWidth = CGFloat(reference.filename.count) * 6.5
      return min(
        maximumChipWidth,
        max(minimumChipWidth, estimatedTextWidth + 66)
      )
    }
  }

  struct NoteFileReferenceView: View {
    enum Action: String, Identifiable {
      case open = "Open"
      case reveal = "Reveal in Finder"
      case locate = "Locate File…"
      case remove = "Remove Shortcut"

      var id: Self { self }
    }

    let references: [NoteFileReferencePresentation]
    let canAdd: Bool
    let onAdd: () -> Void
    let onOpen: (UUID) -> Void
    let onReveal: (UUID) -> Void
    let onLocate: (UUID) -> Void
    let onRemove: (UUID) -> Void

    static func actions(
      for reference: NoteFileReferencePresentation
    ) -> [Action] {
      reference.isAvailable
        ? [.open, .reveal, .locate, .remove]
        : [.locate, .remove]
    }

    var body: some View {
      GeometryReader { geometry in
        let plan = NoteFileReferenceLayout.plan(
          references: references,
          availableWidth: geometry.size.width
        )
        referenceStrip(plan)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 4)
      .frame(height: 40)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.quaternary.opacity(0.16))
      .overlay(alignment: .bottom) { Divider().opacity(0.35) }
    }

    private func referenceStrip(_ plan: NoteFileReferenceLayout.Plan) -> some View {
      HStack(spacing: NoteFileReferenceLayout.spacing) {
        Button(action: onAdd) {
          Label("Add", systemImage: "paperclip")
            .lineLimit(1)
            .frame(width: 48, height: 30)
        }
        .buttonStyle(.plain)
        .font(.caption.weight(.medium))
        .foregroundStyle(.primary)
        .disabled(!canAdd)
        .accessibilityLabel("Add file shortcut")
        .accessibilityHint(
          "File shortcuts stay on this Mac and aren’t included in exports."
        )
        .help("Add a file shortcut. Shortcuts stay on this Mac and aren’t included in exports.")

        ForEach(plan.rows.first ?? []) { item in
          fileChip(item.reference)
            .frame(width: item.width, alignment: .leading)
        }
        if !plan.overflow.isEmpty {
          overflowMenu(plan.overflow)
        }
      }
    }

    private func fileChip(_ reference: NoteFileReferencePresentation) -> some View {
      HStack(spacing: 3) {
        Button {
          reference.isAvailable ? onOpen(reference.id) : onLocate(reference.id)
        } label: {
          HStack(spacing: 5) {
            fileIcon(reference)
            Text(reference.filename)
              .lineLimit(1)
              .truncationMode(.middle)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
          reference.isAvailable
            ? "Open \(reference.filename)"
            : "Locate unavailable file \(reference.filename)"
        )
        .accessibilityValue(reference.isAvailable ? "" : "File unavailable")

        Menu {
          referenceMenuItems(reference)
        } label: {
          Image(systemName: "ellipsis")
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("File actions for \(reference.filename)")
      }
      .font(.caption)
      .padding(.leading, 8)
      .padding(.trailing, 3)
      .frame(height: 30)
      .background(.regularMaterial, in: Capsule())
      .overlay {
        Capsule().stroke(.separator.opacity(0.35), lineWidth: 0.5)
      }
      .help(
        reference.isAvailable
          ? reference.filename
          : "\(reference.filename) is unavailable. Click to locate it."
      )
    }

    private func overflowMenu(
      _ references: [NoteFileReferencePresentation]
    ) -> some View {
      Menu {
        ForEach(references) { reference in
          Menu(
            reference.isAvailable
              ? reference.filename
              : "\(reference.filename) — File unavailable"
          ) {
            referenceMenuItems(reference)
          }
        }
      } label: {
        Text("+\(references.count)")
          .lineLimit(1)
          .font(.caption)
          .frame(width: 34, height: 30)
      }
      .menuStyle(.borderlessButton)
      .fixedSize()
      .accessibilityLabel("\(references.count) more file shortcuts")
      .help("Show more file shortcuts")
    }

    @ViewBuilder
    private func referenceMenuItems(
      _ reference: NoteFileReferencePresentation
    ) -> some View {
      ForEach(Self.actions(for: reference)) { action in
        switch action {
        case .open:
          Button(action.rawValue) { onOpen(reference.id) }
        case .reveal:
          Button(action.rawValue) { onReveal(reference.id) }
        case .locate:
          Button(action.rawValue) { onLocate(reference.id) }
        case .remove:
          Divider()
          Button(action.rawValue, role: .destructive) { onRemove(reference.id) }
        }
      }
    }

    @ViewBuilder
    private func fileIcon(_ reference: NoteFileReferencePresentation) -> some View {
      Image(systemName: reference.isAvailable ? "doc" : "doc.badge.ellipsis")
        .foregroundStyle(.secondary)
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }
  }
#endif
