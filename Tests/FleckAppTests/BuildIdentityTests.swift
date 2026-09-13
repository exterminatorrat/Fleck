import Foundation
import Testing

@testable import FleckApp

private func packagedInfo() -> [String: Any] {
  [
    "CFBundleIdentifier": "com.harryjin.fleck",
    "CFBundleVersion": "1.2.3",
    "FleckVersion": "1.0.0-beta.1",
    "FleckBuildNumber": "10204",
    "FleckBuildID": "4c6bf7d2-406f-4d2a-b4ea-0927f0378666",
    "FleckBuildDate": "2026-09-11T14:30:00Z",
    "FleckSourceCommit": "0123456789abcdef0123456789abcdef01234567",
    "FleckSourceTree": "89abcdef0123456789abcdef0123456789abcdef",
    "FleckBuildFlavor": "corrected",
    "FleckBuildConfiguration": "Debug",
    "FleckCandidateStatus": "Candidate - not accepted",
    "FleckBaselineManifestSHA256": String(repeating: "a", count: 64),
    "FleckBaselineRecordID": "fixture-accepted",
    "FleckBaselineRegistryStatus": "active",
    "FleckInputBuildID": "17198fcc-995c-4333-a0c5-2598e2aa538b",
    "FleckInputManifestSHA256": String(repeating: "b", count: 64),
  ]
}

@Test func BuildIdentityReadsCompletePackagedMetadata() {
  let identity = BuildIdentity(
    infoDictionary: packagedInfo(),
    bundleIdentifier: "com.harryjin.fleck"
  )

  #expect(identity.isPackaged)
  #expect(identity.productVersion == "1.0.0-beta.1")
  #expect(identity.buildNumber == "10204")
  #expect(identity.bundleVersion == "1.2.3")
  #expect(identity.shortSourceCommit == "0123456789ab")
  #expect(identity.readableBuildDate?.contains("2026") == true)
  #expect(identity.inputBuildID == "17198fcc-995c-4333-a0c5-2598e2aa538b")
}

@Test func BuildIdentityRequiresCompleteStampForPackagedClaims() {
  var incomplete = packagedInfo()
  incomplete.removeValue(forKey: "FleckBuildID")
  let identity = BuildIdentity(
    infoDictionary: incomplete,
    bundleIdentifier: "com.harryjin.fleck"
  )

  #expect(!identity.isPackaged)
  #expect(identity.productVersion == nil)
  #expect(identity.buildNumber == nil)
  #expect(identity.copyText.contains("Unpackaged development build"))
  #expect(!identity.copyText.contains("10204"))
}

@Test func BuildIdentityCopyContainsFullMetadataWithoutLocalContext() {
  let identity = BuildIdentity(infoDictionary: packagedInfo(), bundleIdentifier: nil)
  let copied = identity.copyText

  #expect(copied.contains("Product version: 1.0.0-beta.1"))
  #expect(copied.contains("Build ID: 4c6bf7d2-406f-4d2a-b4ea-0927f0378666"))
  #expect(copied.contains("Source commit: 0123456789abcdef0123456789abcdef01234567"))
  #expect(copied.contains("Input build ID: 17198fcc-995c-4333-a0c5-2598e2aa538b"))
  #expect(copied.contains("Bundle identifier: com.harryjin.fleck"))
  #expect(!copied.contains("/Users/"))
  #expect(!copied.localizedCaseInsensitiveContains("branch"))
  #expect(!copied.localizedCaseInsensitiveContains("environment"))
}

@Test func BuildIdentityDoesNotInventMissingOptionalRepackMetadata() {
  var ordinaryInfo = packagedInfo()
  ordinaryInfo.removeValue(forKey: "FleckInputBuildID")
  ordinaryInfo.removeValue(forKey: "FleckInputManifestSHA256")
  let identity = BuildIdentity(infoDictionary: ordinaryInfo, bundleIdentifier: nil)

  #expect(identity.isPackaged)
  #expect(identity.inputBuildID == nil)
  #expect(!identity.copyText.contains("Input build ID"))
  #expect(!identity.copyText.contains("Input app manifest SHA-256"))
}

@Test func BuildIdentityAboutSettingsUsesNativeAccessibleCopyAndInjection() throws {
  let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let about = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/AboutSettingsView.swift"),
    encoding: .utf8
  )
  let settings = try String(
    contentsOf: repository.appendingPathComponent("Sources/FleckApp/SettingsView.swift"),
    encoding: .utf8
  )

  #expect(about.contains("let identity: BuildIdentity"))
  #expect(about.contains("Button(\"Copy Build Info\", systemImage: \"doc.on.doc\")"))
  #expect(about.contains(".keyboardShortcut(\"c\", modifiers: [.command, .shift])"))
  #expect(about.contains(".accessibilityLabel(\"Copy build information\")"))
  #expect(about.contains(".textSelection(.enabled)"))
  #expect(about.contains("Build info copied"))
  #expect(settings.contains("case about = \"About\""))
  #expect(settings.contains("AboutSettingsView(identity: buildIdentity)"))
}
