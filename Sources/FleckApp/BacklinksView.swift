#if os(macOS)
  import FleckCore
  import SwiftUI

  struct BacklinksView: View {
    let entries: [BacklinkSource]
    let foldersByID: [UUID: String]
    let onOpen: (UUID) -> Void

    static func accessibilityLabel(for entry: BacklinkSource, folderName: String?) -> String {
      [
        entry.sourceDisplayTitle,
        folderName,
        entry.excerpt,
        entry.referenceCount == 1
          ? "1 reference"
          : "\(entry.referenceCount) references",
      ]
      .compactMap { $0 }
      .joined(separator: ", ")
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        Text("Linked from \(entries.count)")
          .font(.headline)
          .accessibilityAddTraits(.isHeader)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.bottom, 6)

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
                let folderName = entry.sourceFolderID.flatMap { foldersByID[$0] }
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
                .accessibilityLabel(Self.accessibilityLabel(for: entry, folderName: folderName))
                .accessibilityHint("Open linked note")
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
#endif
