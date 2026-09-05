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

  struct NoteFileReferenceView: View {
    let references: [NoteFileReferencePresentation]
    let onOpen: (UUID) -> Void
    let onReveal: (UUID) -> Void
    let onLocate: (UUID) -> Void
    let onRemove: (UUID) -> Void

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

        ScrollView(.horizontal, showsIndicators: references.count > 6) {
          LazyHGrid(
            rows: Array(
              repeating: GridItem(.fixed(28), spacing: 6),
              count: references.count > 3 ? 2 : 1
            ),
            spacing: 6
          ) {
            ForEach(references) { reference in
              fileChip(reference)
            }
          }
        }
        .frame(height: references.count > 3 ? 62 : 28)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.quaternary.opacity(0.16))
      .overlay(alignment: .bottom) { Divider().opacity(0.35) }
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
              .frame(maxWidth: 150)
          }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
          reference.isAvailable
            ? "Open \(reference.filename)"
            : "Locate unavailable file \(reference.filename)"
        )

        Menu {
          if reference.isAvailable {
            Button("Open") { onOpen(reference.id) }
            Button("Show in Finder") { onReveal(reference.id) }
          } else {
            Button("Locate…") { onLocate(reference.id) }
          }
          Divider()
          Button("Remove Shortcut", role: .destructive) { onRemove(reference.id) }
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
      .padding(.vertical, 5)
      .background(.regularMaterial, in: Capsule())
      .overlay {
        Capsule().stroke(.separator.opacity(0.35), lineWidth: 0.5)
      }
      .help(reference.isAvailable ? reference.filename : "File unavailable")
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
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
          .frame(width: 16, height: 16)
      }
    }
  }
#endif
