#if os(macOS)
import SwiftUI
import MenuBarNotesCore

struct NotesPanel: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            header
            tabStrip
            Divider().opacity(0.35)
            editor
            if let error = appState.saveError {
                Text("Could not save: \(error)")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 520, height: 430)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(appState.preferences.panelOpacity)
        }
        .tint(Color(hex: appState.preferences.accentHex))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label("Notes", systemImage: "note.text")
                .font(.headline)
            Spacer()
            Button {
                appState.addNote()
            } label: {
                Image(systemName: "plus")
            }
            .keyboardShortcut("t", modifiers: .command)
            .help("New note")

            Button {
                openSettings()
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .help("Customize")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(appState.workspace.notes) { note in
                    Button {
                        appState.select(note.id)
                    } label: {
                        Text(note.displayTitle)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                note.id == appState.workspace.selectedNoteID
                                    ? Color.accentColor.opacity(0.18)
                                    : Color.clear,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 9)
        }
    }

    @ViewBuilder
    private var editor: some View {
        if let note = appState.selectedNote {
            VStack(spacing: 0) {
                if appState.preferences.showFormattingBar {
                    FormattingBar()
                }
                TextField(
                    "Note title",
                    text: Binding(
                        get: { note.title },
                        set: { appState.updateSelected(title: $0) }
                    )
                )
                .textFieldStyle(.plain)
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.top, 12)

                TextEditor(text: Binding(
                    get: { note.body },
                    set: { appState.updateSelected(body: $0) }
                ))
                .font(.custom(appState.preferences.fontFamily, size: appState.preferences.fontSize))
                .scrollContentBackground(.hidden)
                .padding(10)
            }
        }
    }
}

private struct FormattingBar: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 14) {
            Button("Bullets", systemImage: "list.bullet") {
                appState.toggleList(.bullets)
            }
            Button("Numbers", systemImage: "list.number") {
                appState.toggleList(.numbers)
            }
            Spacer()
            Button("Delete", systemImage: "trash", role: .destructive) {
                appState.deleteSelectedNote()
            }
            .keyboardShortcut("w", modifiers: .command)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.thinMaterial)
    }
}

private extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let value = UInt64(cleaned, radix: 16) ?? 0x7C6CF2
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
#endif
