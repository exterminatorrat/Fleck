#if os(macOS)
  import FleckCore
  import SwiftUI

  struct BacklinksView: View {
    let entries: [BacklinkSource]
    let foldersByID: [UUID: String]
    let isExpanded: Bool
    let onToggle: () -> Void
    let onOpen: (UUID) -> Void

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        BacklinksDisclosureButton(
          title: "Linked from \(entries.count)",
          isExpanded: isExpanded,
          onToggle: onToggle
        )
        .frame(height: 22)

        if isExpanded {
          if entries.isEmpty {
            Text("No notes link here")
              .font(.caption)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.vertical, 5)
          } else {
            ScrollView(.vertical) {
              LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(entries) { entry in
                  Button {
                    onOpen(entry.sourceNoteID)
                  } label: {
                    VStack(alignment: .leading, spacing: 3) {
                      HStack(spacing: 5) {
                        Text(entry.sourceDisplayTitle)
                          .font(.callout.weight(.semibold))
                          .lineLimit(1)
                        if let folderID = entry.sourceFolderID,
                          let folderName = foldersByID[folderID]
                        {
                          Text(folderName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if entry.referenceCount > 1 {
                        Text(String(entry.referenceCount) + " references")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                      }
                      Text(entry.excerpt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                  }
                  .buttonStyle(.plain)
                  .accessibilityLabel(entry.sourceDisplayTitle + ", " + entry.excerpt)
                  .accessibilityHint("Open linked note")
                }
              }
            }
            .frame(maxHeight: 150)
          }
        }
      }
      .accessibilityElement(children: .contain)
      .padding(.horizontal, 16)
    }
  }

  private struct BacklinksDisclosureButton: NSViewRepresentable {
    let title: String
    let isExpanded: Bool
    let onToggle: () -> Void

    func makeCoordinator() -> Coordinator {
      Coordinator(onToggle: onToggle)
    }

    func makeNSView(context: Context) -> NSButton {
      let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.toggle))
      button.setButtonType(.momentaryPushIn)
      button.bezelStyle = .inline
      button.alignment = .left
      button.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
      button.isBordered = false
      button.setAccessibilityLabel(title)
      button.setAccessibilityValue(isExpanded ? "Expanded" : "Collapsed")
      return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
      context.coordinator.onToggle = onToggle
      button.title = title
      button.setAccessibilityLabel(title)
      button.setAccessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }

    final class Coordinator: NSObject {
      var onToggle: () -> Void

      init(onToggle: @escaping () -> Void) {
        self.onToggle = onToggle
      }

      @objc func toggle() {
        onToggle()
      }
    }
  }
#endif
