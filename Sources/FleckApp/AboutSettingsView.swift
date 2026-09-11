#if os(macOS)
  import AppKit
  import SwiftUI

  struct AboutSettingsView: View {
    let identity: BuildIdentity
    @State private var copyConfirmation: String?

    init(identity: BuildIdentity = .current()) {
      self.identity = identity
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        if identity.isPackaged {
          SettingsPreferenceRow(
            "Product version",
            detail: "The readable Fleck product version."
          ) {
            Text(identity.productVersion ?? "Unavailable")
              .textSelection(.enabled)
          }
          SettingsPreferenceRow(
            "Build",
            detail: identity.readableBuildDate ?? identity.buildDate ?? "Date unavailable"
          ) {
            Text("#\(identity.buildNumber ?? "Unavailable")")
              .monospacedDigit()
              .textSelection(.enabled)
          }
          SettingsPreferenceRow(
            "Source",
            detail: "Exact source revision captured before packaging."
          ) {
            Text(identity.shortSourceCommit ?? "Unavailable")
              .font(.system(.body, design: .monospaced))
              .textSelection(.enabled)
          }
          SettingsPreferenceRow(
            "Candidate status",
            detail: "Packaging identity is separate from acceptance."
          ) {
            Text(identity.candidateStatus ?? "Unavailable")
              .multilineTextAlignment(.trailing)
              .textSelection(.enabled)
          }
        } else {
          SettingsPreferenceRow(
            "Build",
            detail: "This executable has no packaged build identity."
          ) {
            Text("Unpackaged development build")
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
          }
        }

        DisclosureGroup("Full build metadata") {
          Text(identity.copyText)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .padding(.top, 6)
            .accessibilityLabel("Full build metadata")
        }

        HStack(spacing: 10) {
          Button("Copy Build Info", systemImage: "doc.on.doc") {
            copyBuildInfo()
          }
          .keyboardShortcut("c", modifiers: [.command, .shift])
          .accessibilityLabel("Copy build information")
          .accessibilityHint("Copies complete build metadata without local paths or personal data")

          if let copyConfirmation {
            Label(copyConfirmation, systemImage: "checkmark.circle.fill")
              .font(.caption)
              .foregroundStyle(.secondary)
              .accessibilityLabel(copyConfirmation)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func copyBuildInfo() {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(identity.copyText, forType: .string)
      copyConfirmation = "Build info copied"
    }
  }
#endif
