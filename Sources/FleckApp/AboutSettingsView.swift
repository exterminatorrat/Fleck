#if os(macOS)
  import AppKit
  import SwiftUI

  @MainActor
  struct AboutSettingsView: View {
    let identity: BuildIdentity
    @ObservedObject private var updateController: AppUpdateController
    @Environment(\.settingsSearchRequest) private var searchRequest
    @State private var copyConfirmation: String?
    @State private var isMetadataExpanded = false

    init(
      identity: BuildIdentity = .current(),
      updateController: AppUpdateController? = nil
    ) {
      self.identity = identity
      self.updateController = updateController ?? AppUpdateController()
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        if identity.isPackaged {
          SettingsPreferenceRow(
            "Product version",
            detail: "The version of this Fleck build."
          ) {
            Text(identity.productVersion ?? "Unavailable")
              .textSelection(.enabled)
          }
          .settingsSearchAnchor(.aboutProductVersion, request: searchRequest)
          SettingsPreferenceRow(
            "Build",
            detail: identity.readableBuildDate ?? identity.buildDate ?? "Date unavailable"
          ) {
            Text("#\(identity.buildNumber ?? "Unavailable")")
              .monospacedDigit()
              .textSelection(.enabled)
          }
          .settingsSearchAnchor(.aboutBuild, request: searchRequest)
          SettingsPreferenceRow(
            "Source",
            detail: "Exact source revision captured before packaging."
          ) {
            Text(identity.shortSourceCommit ?? "Unavailable")
              .font(.system(.body, design: .monospaced))
              .textSelection(.enabled)
          }
          .settingsSearchAnchor(.aboutSource, request: searchRequest)
          SettingsPreferenceRow(
            "Candidate status",
            detail: "Packaging identity is separate from acceptance."
          ) {
            Text(identity.candidateStatus ?? "Unavailable")
              .multilineTextAlignment(.trailing)
              .textSelection(.enabled)
          }
          .settingsSearchAnchor(.aboutCandidateStatus, request: searchRequest)
        } else {
          SettingsPreferenceRow(
            "Build",
            detail: "This build has no packaged version information."
          ) {
            Text("Unpackaged development build")
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
          }
          .settingsSearchAnchor(.aboutBuild, request: searchRequest)
        }

        SettingsPreferenceRow(
          "Updates",
          detail: updateController.statusText
        ) {
          Button("Check for Updates…") {
            updateController.checkForUpdates()
          }
          .disabled(!updateController.canCheckForUpdates)
          .accessibilityIdentifier("settings-about-check-for-updates")
          .accessibilityHint("Checks signed release information without downloading or installing an update")
        }

        Text("Update checks report signed release information only. Automatic installation is unavailable.")
          .font(.caption)
          .foregroundStyle(.secondary)

        DisclosureGroup("Full build metadata", isExpanded: $isMetadataExpanded) {
          Text(identity.copyText)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .padding(.top, 6)
            .accessibilityLabel("Full build metadata")
            .accessibilityIdentifier("settings-about-metadata-content")
            .background(SettingsSearchProbe(identifier: "settings-about-metadata-content"))
        }
        .disclosureGroupStyle(SettingsDisclosureGroupStyle())
        .settingsSearchAnchor(.aboutMetadata, request: searchRequest)

        HStack(spacing: 10) {
          Button("Copy Build Info", systemImage: "doc.on.doc") {
            copyBuildInfo()
          }
          .keyboardShortcut("c", modifiers: [.command, .shift])
          .accessibilityLabel("Copy build information")
          .accessibilityHint("Copies complete build metadata without local paths or personal data")
          .settingsSearchAnchor(.aboutCopyBuildInfo, request: searchRequest)

          if let copyConfirmation {
            Label(copyConfirmation, systemImage: "checkmark.circle.fill")
              .font(.caption)
              .foregroundStyle(.secondary)
              .accessibilityLabel(copyConfirmation)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .onChange(of: searchRequest?.id, initial: true) { _, _ in
        if searchRequest?.anchor == .aboutMetadata {
          isMetadataExpanded = true
        }
      }
    }

    private func copyBuildInfo() {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(identity.copyText, forType: .string)
      copyConfirmation = "Build info copied"
    }
  }
#endif
