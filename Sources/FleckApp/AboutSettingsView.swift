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
            AboutSelectableText(
              text: identity.productVersion ?? "Unavailable", label: "Product version"
            )
          }
          .settingsSearchAnchor(.aboutProductVersion, request: searchRequest)
          SettingsPreferenceRow(
            "Build",
            detail: identity.readableBuildDate ?? identity.buildDate ?? "Date unavailable"
          ) {
            AboutSelectableText(text: "#\(identity.buildNumber ?? "Unavailable")", label: "Build")
              .monospacedDigit()
          }
          .settingsSearchAnchor(.aboutBuild, request: searchRequest)
          SettingsPreferenceRow(
            "Source",
            detail: "Exact source revision captured before packaging."
          ) {
            AboutSelectableText(text: identity.shortSourceCommit ?? "Unavailable", label: "Source")
              .font(.system(.body, design: .monospaced))
          }
          .settingsSearchAnchor(.aboutSource, request: searchRequest)
          SettingsPreferenceRow(
            "Candidate status",
            detail: "Packaging identity is separate from acceptance."
          ) {
            AboutSelectableText(
              text: identity.candidateStatus ?? "Unavailable", label: "Candidate status"
            )
              .multilineTextAlignment(.trailing)
          }
          .settingsSearchAnchor(.aboutCandidateStatus, request: searchRequest)
        } else {
          SettingsPreferenceRow(
            "Build",
            detail: "This build has no packaged version information."
          ) {
            AboutSelectableText(text: "Unpackaged development build", label: "Build")
              .foregroundStyle(.secondary)
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
          AboutSelectableText(text: identity.copyText, label: "Full build metadata")
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .padding(.top, 6)
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

  private struct AboutSelectableText: View {
    let text: String
    let label: String

    var body: some View {
      Text(text)
        .textSelection(.enabled)
        .accessibilityRepresentation {
          Text(text)
            .textSelection(.disabled)
            .accessibilityLabel(label)
            .accessibilityValue(text)
        }
    }
  }
#endif
