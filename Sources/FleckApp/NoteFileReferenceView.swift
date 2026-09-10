#if os(macOS)
  import AppKit
  import SwiftUI

  @MainActor
  struct NoteFilePicker {
    let chooseFile: (NSWindow?, @escaping (URL?) -> Void) -> Void

    static let live = NoteFilePicker { window, completion in
      let panel = NSOpenPanel()
      panel.title = "Choose a File"
      panel.prompt = "Choose"
      panel.canChooseFiles = true
      panel.canChooseDirectories = false
      panel.allowsMultipleSelection = false
      panel.resolvesAliases = true
      let finish: (NSApplication.ModalResponse) -> Void = { response in
        completion(response == .OK ? panel.url : nil)
      }
      if let window {
        panel.beginSheetModal(for: window, completionHandler: finish)
      } else {
        panel.begin(completionHandler: finish)
      }
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
    private static let overflowWidth: CGFloat = 76
    private static let minimumChipWidth: CGFloat = 132
    private static let maximumChipWidth: CGFloat = 220

    static func plan(
      references: [NoteFileReferencePresentation],
      availableWidth: CGFloat
    ) -> Plan {
      let fullWidthPlan = pack(references, into: max(1, availableWidth))
      guard !fullWidthPlan.overflow.isEmpty else { return fullWidthPlan }
      return pack(
        references,
        into: max(1, availableWidth - overflowWidth - spacing)
      )
    }

    private static func pack(
      _ references: [NoteFileReferencePresentation],
      into width: CGFloat
    ) -> Plan {
      var rows = [[Item](), [Item]()]
      var usedWidths = [CGFloat.zero, .zero]
      var overflow: [NoteFileReferencePresentation] = []

      for reference in references {
        let itemWidth = min(desiredWidth(for: reference), width)
        guard let rowIndex = rows.indices.first(where: { index in
          let gap = rows[index].isEmpty ? 0 : spacing
          return usedWidths[index] + gap + itemWidth <= width
        }) else {
          overflow.append(reference)
          continue
        }
        if !rows[rowIndex].isEmpty {
          usedWidths[rowIndex] += spacing
        }
        rows[rowIndex].append(Item(reference: reference, width: itemWidth))
        usedWidths[rowIndex] += itemWidth
      }

      return Plan(
        rows: rows.filter { !$0.isEmpty },
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
    let onOpen: (UUID) -> Void
    let onReveal: (UUID) -> Void
    let onLocate: (UUID) -> Void
    let onRemove: (UUID) -> Void

    @State private var renderedRowCount = 1

    static func actions(
      for reference: NoteFileReferencePresentation
    ) -> [Action] {
      reference.isAvailable
        ? [.open, .reveal, .locate, .remove]
        : [.locate, .remove]
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 5) {
          Image(systemName: "paperclip")
          Text("Files")
          Text("\(references.count)")
            .foregroundStyle(.tertiary)
          Image(systemName: "info.circle")
            .foregroundStyle(.tertiary)
            .help("File shortcuts stay on this Mac and aren’t included in exports.")
            .accessibilityLabel("About file shortcuts")
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)

        GeometryReader { geometry in
          let plan = NoteFileReferenceLayout.plan(
            references: references,
            availableWidth: geometry.size.width
          )
          referenceGrid(plan)
            .onChange(of: plan.rows.count, initial: true) { _, count in
              renderedRowCount = max(1, count)
            }
        }
        .frame(
          height: CGFloat(renderedRowCount) * 36
            + CGFloat(renderedRowCount - 1) * NoteFileReferenceLayout.spacing
        )
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.quaternary.opacity(0.16))
      .overlay(alignment: .bottom) { Divider().opacity(0.35) }
    }

    private func referenceGrid(_ plan: NoteFileReferenceLayout.Plan) -> some View {
      HStack(alignment: .top, spacing: NoteFileReferenceLayout.spacing) {
        VStack(alignment: .leading, spacing: NoteFileReferenceLayout.spacing) {
          ForEach(Array(plan.rows.enumerated()), id: \.offset) { _, row in
            HStack(spacing: NoteFileReferenceLayout.spacing) {
              ForEach(row) { item in
                fileChip(item.reference)
                  .frame(width: item.width, alignment: .leading)
              }
            }
          }
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
            VStack(alignment: .leading, spacing: 0) {
              Text(reference.filename)
                .lineLimit(1)
                .truncationMode(.middle)
              if !reference.isAvailable {
                Text("File unavailable")
                  .font(.caption2)
                  .foregroundStyle(.tertiary)
              }
            }
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
      .frame(height: 34)
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
        Label("\(references.count) more", systemImage: "ellipsis.circle")
          .lineLimit(1)
          .font(.caption)
          .frame(width: 70, height: 34)
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
      if let url = reference.url {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
          .resizable()
          .scaledToFit()
          .frame(width: 16, height: 16)
          .overlay(alignment: .bottomTrailing) {
            Image(systemName: "arrow.up.right")
              .font(.system(size: 6, weight: .bold))
              .foregroundStyle(.secondary)
              .padding(1)
              .background(.regularMaterial, in: Circle())
              .offset(x: 2, y: 2)
          }
      } else {
        Image(systemName: "doc.badge.ellipsis")
          .foregroundStyle(.secondary)
          .frame(width: 16, height: 16)
      }
    }
  }
#endif
