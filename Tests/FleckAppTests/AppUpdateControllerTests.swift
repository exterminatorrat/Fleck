import Foundation
import Testing

#if canImport(CryptoKit)
import CryptoKit
#endif

@testable import FleckApp

private let fixturePublicKey = "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c"
private let currentBuildID = "4c6bf7d2-406f-4d2a-b4ea-0927f0378666"

private func buildIdentityInfo(
  buildNumber: String = "10204",
  bundleVersion: String = "2.2.3"
) -> [String: Any] {
  [
    "CFBundleIdentifier": "com.harryjin.fleck",
    "CFBundleVersion": bundleVersion,
    "FleckVersion": "1.6.0-beta.1",
    "FleckBuildNumber": buildNumber,
    "FleckBuildID": currentBuildID,
    "FleckBuildDate": "2026-09-11T14:30:00Z",
    "FleckSourceCommit": String(repeating: "a", count: 40),
    "FleckSourceTree": String(repeating: "b", count: 40),
    "FleckBuildFlavor": "corrected",
    "FleckBuildConfiguration": "Debug",
    "FleckCandidateStatus": "Candidate - not accepted",
    "FleckBaselineManifestSHA256": String(repeating: "c", count: 64),
    "FleckBaselineRecordID": "fixture-accepted",
    "FleckBaselineRegistryStatus": "active",
  ]
}

private func updateInfoDictionary() -> [String: Any] {
  [
    "SUFeedURL": "https://github.com/exterminatorrat/fleck/update-fixture.xml",
    "SUPublicEDKey": data(hex: fixturePublicKey)!.base64EncodedString(),
    "SURequireSignedFeed": true,
    "SUVerifyUpdateBeforeExtraction": true,
    "SUSignedFeedFailureExpirationInterval": NSNumber(value: 0),
    "SUEnableAutomaticChecks": false,
    "SUAutomaticallyUpdate": false,
    "SUAllowsAutomaticUpdates": false,
    "SUEnableSystemProfiling": false,
    "SUEnableJavaScript": false,
    "SUShowReleaseNotes": false,
  ]
}

private func identity() -> BuildIdentity {
  BuildIdentity(
    infoDictionary: buildIdentityInfo(),
    bundleIdentifier: "com.harryjin.fleck"
  )
}

private func currentUpdateIdentity() -> AppUpdateCurrentIdentity? {
  AppUpdateCurrentIdentity(identity())
}

private func candidate(
  productVersion: String = "1.6.0",
  bundleVersion: String = "2.2.4",
  buildID: String = "17198fcc-995c-4333-a0c5-2598e2aa538b",
  bundleIdentifier: String = "com.harryjin.fleck",
  buildFlavor: String = "corrected",
  minimumSystemVersion: String? = "13.0",
  channel: String? = nil,
  fileURL: URL? = URL(
    string: "https://github.com/exterminatorrat/fleck/releases/download/test-fixture/Fleck.zip"
  ),
  contentLength: UInt64 = 128,
  enclosureSignature: String? = Data(repeating: 0, count: 64).base64EncodedString(),
  installationType: String? = "application",
  isDeltaUpdate: Bool = false,
  isInformationOnlyUpdate: Bool = false,
  supportsCurrentOS: Bool = true,
  supportsArm64: Bool = true,
  hardwareRequirements: Set<String> = [],
  feedSignatureValidated: Bool = true,
  itemFeedSignatureValidated: Bool = true
) -> AppUpdateCandidateMetadata {
  AppUpdateCandidateMetadata(
    productVersion: productVersion,
    bundleVersion: bundleVersion,
    buildID: buildID,
    bundleIdentifier: bundleIdentifier,
    buildFlavor: buildFlavor,
    minimumSystemVersion: minimumSystemVersion,
    channel: channel,
    fileURL: fileURL,
    contentLength: contentLength,
    enclosureSignature: enclosureSignature,
    installationType: installationType,
    isDeltaUpdate: isDeltaUpdate,
    isInformationOnlyUpdate: isInformationOnlyUpdate,
    supportsCurrentOS: supportsCurrentOS,
    supportsArm64: supportsArm64,
    hardwareRequirements: hardwareRequirements,
    feedSignatureValidated: feedSignatureValidated,
    itemFeedSignatureValidated: itemFeedSignatureValidated
  )
}

private func data(hex: String) -> Data? {
  let bytes = Array(hex.utf8)
  guard bytes.count.isMultiple(of: 2) else { return nil }
  var result: [UInt8] = []
  result.reserveCapacity(bytes.count / 2)
  for index in stride(from: 0, to: bytes.count, by: 2) {
    guard let byte = UInt8(String(decoding: bytes[index..<(index + 2)], as: UTF8.self), radix: 16) else {
      return nil
    }
    result.append(byte)
  }
  return Data(result)
}

@MainActor
private final class MockUpdateChecker: AppUpdateInformationChecking {
  var canCheckForUpdates = true
  private(set) var startCount = 0
  private var completion: (@MainActor (AppUpdateProbeResult) -> Void)?

  func startInformationCheck(
    completion: @escaping @MainActor (AppUpdateProbeResult) -> Void
  ) {
    startCount += 1
    self.completion = completion
  }

  func finish(_ result: AppUpdateProbeResult) {
    completion?(result)
  }
}

@Test func AppUpdateConfigurationRequiresTheExactSecurityPolicy() {
  let valid = updateInfoDictionary()
  #expect(AppUpdateConfiguration(infoDictionary: valid) != nil)

  var wrongBooleanType = valid
  wrongBooleanType["SURequireSignedFeed"] = 1
  #expect(AppUpdateConfiguration(infoDictionary: wrongBooleanType) == nil)

  var wrongBooleanValue = valid
  wrongBooleanValue["SUEnableAutomaticChecks"] = true
  #expect(AppUpdateConfiguration(infoDictionary: wrongBooleanValue) == nil)

  var wrongExpiryType = valid
  wrongExpiryType["SUSignedFeedFailureExpirationInterval"] = false
  #expect(AppUpdateConfiguration(infoDictionary: wrongExpiryType) == nil)

  var wrongExpiryValue = valid
  wrongExpiryValue["SUSignedFeedFailureExpirationInterval"] = NSNumber(value: 1)
  #expect(AppUpdateConfiguration(infoDictionary: wrongExpiryValue) == nil)

  var wrongKey = valid
  wrongKey["SUPublicEDKey"] = Data(repeating: 0, count: 31).base64EncodedString()
  #expect(AppUpdateConfiguration(infoDictionary: wrongKey) == nil)
}

@Test func AppUpdateErrorPolicyFindsSparkleSignatureErrorsInABoundedChain() {
  let sparkleDomain = "test.sparkle"
  let signatureError = NSError(domain: sparkleDomain, code: 3001)
  let validationError = NSError(domain: sparkleDomain, code: 3002)
  let wrappedError = NSError(
    domain: "test.wrapper",
    code: 1,
    userInfo: [NSUnderlyingErrorKey: signatureError]
  )

  #expect(
    AppUpdateErrorPolicy.containsSparkleSignatureFailure(
      in: wrappedError,
      domain: sparkleDomain
    )
  )
  #expect(
    AppUpdateErrorPolicy.containsSparkleSignatureFailure(
      in: validationError,
      domain: sparkleDomain
    )
  )
  #expect(
    !AppUpdateErrorPolicy.containsSparkleSignatureFailure(
      in: NSError(domain: sparkleDomain, code: 3003),
      domain: sparkleDomain
    )
  )
  #expect(
    !AppUpdateErrorPolicy.containsSparkleSignatureFailure(
      in: NSError(domain: "test.other", code: 3001),
      domain: sparkleDomain
    )
  )

  var tooDeep = signatureError
  for depth in 0..<8 {
    tooDeep = NSError(
      domain: "test.wrapper.\(depth)",
      code: depth,
      userInfo: [NSUnderlyingErrorKey: tooDeep]
    )
  }
  #expect(
    !AppUpdateErrorPolicy.containsSparkleSignatureFailure(
      in: tooDeep,
      domain: sparkleDomain
    )
  )
}

@Test func AppUpdateErrorPolicyFindsCancellationInAnUnderlyingError() {
  let cancellation = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
  let wrappedCancellation = NSError(
    domain: "test.wrapper",
    code: 1,
    userInfo: [NSUnderlyingErrorKey: cancellation]
  )

  #expect(AppUpdateErrorPolicy.containsCancellation(in: cancellation))
  #expect(AppUpdateErrorPolicy.containsCancellation(in: wrappedCancellation))
  #expect(
    AppUpdateErrorPolicy.containsCancellation(
      in: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
    )
  )
  #expect(!AppUpdateErrorPolicy.containsCancellation(in: NSError(domain: "test.other", code: 1)))
}

@Test func AppUpdatePendingResultPolicyPreservesFailuresAndCancellationAgainstLaterSuccess() {
  let information = AppUpdateInformation(productVersion: "1.6.0", bundleVersion: "2.2.4")
  #expect(!AppUpdatePendingResultPolicy.allowsUpdateCandidate(after: .verificationFailure))
  #expect(AppUpdatePendingResultPolicy.allowsUpdateCandidate(after: .error))
  #expect(AppUpdatePendingResultPolicy.allowsUpdateCandidate(after: nil))
  #expect(
    AppUpdatePendingResultPolicy.keepsExistingFailureOrCancellation(
      .verificationFailure,
      over: .current
    )
  )
  #expect(
    AppUpdatePendingResultPolicy.keepsExistingFailureOrCancellation(.error, over: .current)
  )
  #expect(
    AppUpdatePendingResultPolicy.keepsExistingFailureOrCancellation(
      .error,
      over: .updateAvailable(information)
    )
  )
  #expect(
    AppUpdatePendingResultPolicy.keepsExistingFailureOrCancellation(
      .cancelled,
      over: .updateAvailable(information)
    )
  )
  #expect(
    !AppUpdatePendingResultPolicy.keepsExistingFailureOrCancellation(
      .error,
      over: .verificationFailure
    )
  )
  #expect(
    !AppUpdatePendingResultPolicy.keepsExistingFailureOrCancellation(
      .current,
      over: .error
    )
  )
}

@Test @MainActor func AppUpdateControllerMapsCancellationToAnHonestNonInstallState() {
  let checker = MockUpdateChecker()
  let controller = AppUpdateController(
    infoDictionary: updateInfoDictionary(),
    identity: identity(),
    checkerFactory: { _, _ in checker }
  )

  controller.checkForUpdates()
  checker.finish(.cancelled)

  #expect(controller.state == .cancelled)
  #expect(controller.statusText == "The update check was cancelled.")
}

@Test func AppUpdateAppcastPolicyRejectsDuplicateStableItemVersionsAsAmbiguous() {
  #expect(!AppUpdateAppcastPolicy.hasAmbiguousDuplicateItemVersions(["2.2.4", "2.2.3"]))
  #expect(AppUpdateAppcastPolicy.hasAmbiguousDuplicateItemVersions(["2.2.4", "2.2.4"]))
}

@Test func AppUpdateConfigurationRestrictsFeedOwnershipAndURLShape() {
  let invalidURLs = [
    "http://github.com/exterminatorrat/fleck/feed.xml",
    "https://github.com.evil.invalid/exterminatorrat/fleck/feed.xml",
    "https://attacker@github.com/exterminatorrat/fleck/feed.xml",
    "https://github.com/exterminatorrat/fleck/feed.xml?token=value",
    "https://github.com/exterminatorrat/fleck/%2e%2e/feed.xml",
    "https://github.com/other/fleck/feed.xml",
    "https://raw.githubusercontent.com/exterminatorrat/fleck/main",
  ]

  for url in invalidURLs {
    var info = updateInfoDictionary()
    info["SUFeedURL"] = url
    #expect(AppUpdateConfiguration(infoDictionary: info) == nil)
  }

  var rawFeed = updateInfoDictionary()
  rawFeed["SUFeedURL"] = "https://raw.githubusercontent.com/exterminatorrat/fleck/main/feed.xml"
  #expect(AppUpdateConfiguration(infoDictionary: rawFeed) != nil)
}

@Test func AppUpdateIdentityRequiresCanonicalVersionBuildAndBundleIdentity() {
  #expect(currentUpdateIdentity() != nil)
  #expect(AppUpdateBundleVersion.bundleVersion(for: 10_204) == "2.2.3")
  #expect(AppUpdateBundleVersion.buildNumber(for: "2.2.3") == 10_204)
  #expect(AppUpdateBundleVersion.buildNumber(for: "02.2.3") == nil)
  #expect(AppUpdateSemanticVersion("1.6.0-beta.1")! < AppUpdateSemanticVersion("1.6.0-beta.2")!)
  #expect(AppUpdateSemanticVersion("1.6.0")! > AppUpdateSemanticVersion("1.6.0-beta.2")!)
  #expect(AppUpdateSemanticVersion("01.6.0") == nil)
  #expect(AppUpdateSemanticVersion("1.6.0-beta.01") == nil)
  #expect(AppUpdateSemanticVersion("1.6.0+build.1") == nil)

  let mismatchedMapping = BuildIdentity(
    infoDictionary: buildIdentityInfo(buildNumber: "10", bundleVersion: "2.2.3"),
    bundleIdentifier: "com.harryjin.fleck"
  )
  #expect(AppUpdateCurrentIdentity(mismatchedMapping) == nil)

  let wrongBundle = BuildIdentity(
    infoDictionary: buildIdentityInfo(),
    bundleIdentifier: "com.example.other"
  )
  #expect(AppUpdateCurrentIdentity(wrongBundle) == nil)
}

@Test @MainActor func AppUpdateControllerIsInertUntilAnExplicitCheckAndSingleFlight() {
  let checker = MockUpdateChecker()
  var factoryCalls = 0
  let controller = AppUpdateController(
    infoDictionary: updateInfoDictionary(),
    identity: identity(),
    checkerFactory: { _, _ in
      factoryCalls += 1
      return checker
    }
  )

  #expect(controller.state == .idle)
  #expect(controller.canCheckForUpdates)
  #expect(factoryCalls == 0)
  #expect(checker.startCount == 0)

  controller.checkForUpdates()
  #expect(controller.state == .checking)
  #expect(factoryCalls == 1)
  #expect(checker.startCount == 1)
  #expect(!controller.canCheckForUpdates)

  controller.checkForUpdates()
  #expect(factoryCalls == 1)
  #expect(checker.startCount == 1)

  let information = AppUpdateInformation(productVersion: "1.6.0", bundleVersion: "2.2.4")
  checker.finish(.updateAvailable(information))
  #expect(controller.state == .newVersionAvailable(information))
  #expect(
    controller.statusText
      == "Version 1.6.0 is listed in signed update information; "
        + "its artifact, architecture, and extraction have not been verified."
  )
  #expect(controller.canCheckForUpdates)
}

@Test @MainActor func AppUpdateControllerIgnoresStaleAndRepeatedCallbacks() {
  var checkers: [MockUpdateChecker] = []
  let controller = AppUpdateController(
    infoDictionary: updateInfoDictionary(),
    identity: identity(),
    checkerFactory: { _, _ in
      let checker = MockUpdateChecker()
      checkers.append(checker)
      return checker
    }
  )

  controller.checkForUpdates()
  let firstChecker = checkers[0]
  firstChecker.finish(.current)
  #expect(controller.state == .current)
  #expect(controller.statusText == "No newer compatible release is listed in the signed feed.")

  controller.checkForUpdates()
  #expect(checkers.count == 2)
  firstChecker.finish(.error)
  #expect(controller.state == .checking)

  checkers[1].finish(.error)
  #expect(controller.state == .error("The update check failed."))
}

@Test @MainActor func AppUpdateControllerRejectsInvalidConfigurationOrIdentityWithoutCreatingChecker() {
  var factoryCalls = 0
  var invalidInfo = updateInfoDictionary()
  invalidInfo.removeValue(forKey: "SUFeedURL")
  let invalidConfiguration = AppUpdateController(
    infoDictionary: invalidInfo,
    identity: identity(),
    checkerFactory: { _, _ in
      factoryCalls += 1
      return MockUpdateChecker()
    }
  )

  #expect(!invalidConfiguration.canCheckForUpdates)
  #expect(invalidConfiguration.state == .unavailable("Update checking is unavailable."))
  invalidConfiguration.checkForUpdates()
  #expect(factoryCalls == 0)

  let incompleteIdentity = BuildIdentity(infoDictionary: [:], bundleIdentifier: "com.harryjin.fleck")
  let invalidIdentity = AppUpdateController(
    infoDictionary: updateInfoDictionary(),
    identity: incompleteIdentity,
    checkerFactory: { _, _ in
      factoryCalls += 1
      return MockUpdateChecker()
    }
  )
  #expect(!invalidIdentity.canCheckForUpdates)
  invalidIdentity.checkForUpdates()
  #expect(factoryCalls == 0)
}

@Test func AppUpdateCandidatePolicyRequiresAuthenticatedSupportedStableApplicationArchives() throws {
  let current = try #require(currentUpdateIdentity())
  let valid = candidate()
  #expect(
    AppUpdateCandidatePolicy.assess(valid, against: current)
      == .newer(AppUpdateInformation(productVersion: "1.6.0", bundleVersion: "2.2.4"))
  )

  let olderStable = candidate(productVersion: "1.5.0", bundleVersion: "2.2.2")
  #expect(AppUpdateCandidatePolicy.assess(olderStable, against: current) == .notNewer)

  let malformed = [
    candidate(productVersion: "1.6.0-beta.0", bundleVersion: "2.2.4"),
    candidate(productVersion: "1.6.0-beta.2", channel: "stable"),
    candidate(productVersion: "1.6.0-beta.2", bundleVersion: "2.2.3"),
    candidate(productVersion: "1.6.0-beta.1", bundleVersion: "2.2.4"),
    candidate(buildID: "not-a-uuid"),
    candidate(bundleIdentifier: "com.example.other"),
    candidate(buildFlavor: "other"),
    candidate(channel: "beta"),
    candidate(fileURL: URL(string: "https://example.invalid/Fleck.zip")),
    candidate(contentLength: 0),
    candidate(enclosureSignature: nil),
    candidate(installationType: "package"),
    candidate(isDeltaUpdate: true),
    candidate(isInformationOnlyUpdate: true),
    candidate(feedSignatureValidated: false),
    candidate(itemFeedSignatureValidated: false),
    candidate(minimumSystemVersion: nil),
    candidate(minimumSystemVersion: "unknown"),
    candidate(minimumSystemVersion: "14.0.0-beta.1"),
  ]
  for item in malformed {
    #expect(AppUpdateCandidatePolicy.assess(item, against: current) == .verificationFailure)
  }

  #expect(
    AppUpdateCandidatePolicy.assess(candidate(supportsCurrentOS: false), against: current)
      == .incompatible
  )
  #expect(
    AppUpdateCandidatePolicy.assess(candidate(supportsArm64: false), against: current)
      == .incompatible
  )
  #expect(
    AppUpdateCandidatePolicy.assess(candidate(hardwareRequirements: ["x86_64"]), against: current)
      == .incompatible
  )
}

@Test func AppUpdateCandidatePolicyAcceptsOperatingSystemVersionFormats() throws {
  let current = try #require(currentUpdateIdentity())
  let expected = AppUpdateCandidateAssessment.newer(
    AppUpdateInformation(productVersion: "1.6.0", bundleVersion: "2.2.4")
  )
  for minimumOS in ["13", "13.0", "13.0.0", "14.2.1"] {
    #expect(
      AppUpdateCandidatePolicy.assess(
        candidate(minimumSystemVersion: minimumOS),
        against: current
      ) == expected
    )
  }
  for minimumOS in ["", "13.", "13..0", "13.0.0.1", "013.0", "13.-1", "13.0-beta.1"] {
    #expect(
      AppUpdateCandidatePolicy.assess(
        candidate(minimumSystemVersion: minimumOS),
        against: current
      ) == .verificationFailure
    )
  }
}

@Test func AppUpdateNoUpdateRequiresSupportedAuthenticatedMetadataProvingNoNewerItem() {
  let current = currentUpdateIdentity()!
  let latestStableListed = candidate(productVersion: "1.5.0", bundleVersion: "2.2.2")
  let latestStableAssessment = AppUpdateCandidatePolicy.assess(latestStableListed, against: current)
  #expect(
    AppUpdateNoUpdatePolicy.result(
      reason: .newerThanLatestVersion,
      candidate: latestStableAssessment,
      feedCandidates: [latestStableAssessment]
    ) == .current
  )

  #expect(
    AppUpdateNoUpdatePolicy.result(
      reason: .unknown,
      candidate: latestStableAssessment,
      feedCandidates: [latestStableAssessment]
    ) == .error
  )
  #expect(
    AppUpdateNoUpdatePolicy.result(
      reason: .incompatible,
      candidate: latestStableAssessment,
      feedCandidates: [latestStableAssessment]
    ) == .error
  )
  #expect(
    AppUpdateNoUpdatePolicy.result(
      reason: .latestVersion,
      candidate: nil,
      feedCandidates: []
    ) == .error
  )
  #expect(
    AppUpdateNoUpdatePolicy.result(
      reason: .newerThanLatestVersion,
      candidate: .incompatible,
      feedCandidates: [.incompatible]
    ) == .error
  )
  #expect(
    AppUpdateNoUpdatePolicy.result(
      reason: .latestVersion,
      candidate: .verificationFailure,
      feedCandidates: [.verificationFailure]
    ) == .verificationFailure
  )
  #expect(
    AppUpdateNoUpdatePolicy.result(
      reason: .latestVersion,
      candidate: .newer(AppUpdateInformation(productVersion: "1.6.0", bundleVersion: "2.2.4")),
      feedCandidates: [
        .notNewer,
        .newer(AppUpdateInformation(productVersion: "1.6.0", bundleVersion: "2.2.4")),
      ]
    ) == .error
  )
}

#if canImport(CryptoKit)
@Test func RFC8032PublicFixtureSignatureSanityNotSparkleFeedVerification() throws {
  let publicKeyBytes = try #require(data(hex: fixturePublicKey))
  let signature = try #require(
    data(
      hex: "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00"
    )
  )
  let publicKey = try #require(
    try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyBytes)
  )
  let message = Data([0x72])
  #expect(publicKey.isValidSignature(signature, for: message))
  #expect(!publicKey.isValidSignature(signature, for: Data([0x73])))
  var changedSignature = signature
  changedSignature[0] ^= 1
  #expect(!publicKey.isValidSignature(changedSignature, for: message))

  let otherPublicKeyBytes = try #require(
    data(hex: "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
  )
  let otherPublicKey = try #require(
    try? Curve25519.Signing.PublicKey(rawRepresentation: otherPublicKeyBytes)
  )
  #expect(!otherPublicKey.isValidSignature(signature, for: message))
}
#endif
