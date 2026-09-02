#if os(macOS)
  import SwiftUI
  import FleckCore

  struct TrashView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onDone: () -> Void

    var body: some View {
      VStack(spacing: 0) {
        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text("Trash")
              .font(.title2.weight(.semibold))
            Text("Deleted notes are kept on this Mac for 30 days.")
              .font(.callout)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Button("Done", action: onDone)
          .keyboardShortcut(.defaultAction)
        }
        .padding()

        Divider()

        if appState.trashedNotes.isEmpty {
          ContentUnavailableView(
            "Trash is Empty",
            systemImage: "trash",
            description: Text("Notes you delete will appear here for 30 days.")
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          List(appState.trashedNotes) { trashedNote in
            HStack(spacing: 12) {
              VStack(alignment: .leading, spacing: 4) {
                Text(trashedNote.note.displayTitle)
                  .font(.headline)
                  .lineLimit(1)
                Text(deletionDescription(for: trashedNote))
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              Button("Restore") {
                appState.restore(trashedNote)
              }
            }
            .padding(.vertical, 4)
            .transition(
              .opacity.combined(
                with: .offset(x: motion.offset)
              )
            )
          }
          .animation(motion.standard, value: appState.trashedNotes.map(\.id))
        }

        if let error = appState.saveError {
          Text("Could not update Trash: \(error)")
            .font(.caption)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.bottom, 10)
        }
      }
      .task {
        await appState.refreshTrash()
      }
    }

    private var motion: AppMotion {
      AppMotion(reduceMotion: reduceMotion)
    }

    private func deletionDescription(for trashedNote: TrashedNote) -> String {
      let deletionDate = trashedNote.deletedAt.formatted(date: .abbreviated, time: .shortened)
      let expiry = trashedNote.deletedAt.addingTimeInterval(30 * 24 * 60 * 60)
      let daysRemaining = max(0, Int(ceil(expiry.timeIntervalSinceNow / (24 * 60 * 60))))
      let dayLabel = daysRemaining == 1 ? "day" : "days"
      return "Deleted \(deletionDate) · \(daysRemaining) \(dayLabel) remaining"
    }
  }
#endif
