import Foundation

struct BuildIdentity: Equatable, Sendable {
  let productVersion: String?
  let buildNumber: String?
  let bundleVersion: String?
  let buildID: String?
  let buildDate: String?
  let sourceCommit: String?
  let sourceTree: String?
  let flavor: String?
  let configuration: String?
  let candidateStatus: String?
  let baselineManifestSHA256: String?
  let baselineRecordID: String?
  let baselineRegistryStatus: String?
  let inputBuildID: String?
  let inputManifestSHA256: String?
  let bundleIdentifier: String?

  static func current(bundle: Bundle = .main) -> BuildIdentity {
    BuildIdentity(
      infoDictionary: bundle.infoDictionary,
      bundleIdentifier: bundle.bundleIdentifier
    )
  }

  init(infoDictionary: [String: Any]?, bundleIdentifier: String?) {
    let info = infoDictionary ?? [:]
    let requiredKeys = [
      "FleckVersion",
      "FleckBuildNumber",
      "CFBundleVersion",
      "FleckBuildID",
      "FleckBuildDate",
      "FleckSourceCommit",
      "FleckSourceTree",
      "FleckBuildFlavor",
      "FleckBuildConfiguration",
      "FleckCandidateStatus",
      "FleckBaselineManifestSHA256",
      "FleckBaselineRecordID",
      "FleckBaselineRegistryStatus",
    ]
    let values = Dictionary(uniqueKeysWithValues: requiredKeys.compactMap { key in
      (info[key] as? String).map { (key, $0) }
    })
    let packaged = values.count == requiredKeys.count

    productVersion = packaged ? values["FleckVersion"] : nil
    buildNumber = packaged ? values["FleckBuildNumber"] : nil
    bundleVersion = packaged ? values["CFBundleVersion"] : nil
    buildID = packaged ? values["FleckBuildID"] : nil
    buildDate = packaged ? values["FleckBuildDate"] : nil
    sourceCommit = packaged ? values["FleckSourceCommit"] : nil
    sourceTree = packaged ? values["FleckSourceTree"] : nil
    flavor = packaged ? values["FleckBuildFlavor"] : nil
    configuration = packaged ? values["FleckBuildConfiguration"] : nil
    candidateStatus = packaged ? values["FleckCandidateStatus"] : nil
    baselineManifestSHA256 = packaged ? values["FleckBaselineManifestSHA256"] : nil
    baselineRecordID = packaged ? values["FleckBaselineRecordID"] : nil
    baselineRegistryStatus = packaged ? values["FleckBaselineRegistryStatus"] : nil
    inputBuildID = packaged ? info["FleckInputBuildID"] as? String : nil
    inputManifestSHA256 = packaged ? info["FleckInputManifestSHA256"] as? String : nil
    self.bundleIdentifier = bundleIdentifier ?? info["CFBundleIdentifier"] as? String
  }

  var isPackaged: Bool { buildID != nil }

  var readableBuildDate: String? {
    guard let buildDate,
      let date = ISO8601DateFormatter().date(from: buildDate)
    else { return nil }
    var style = Date.FormatStyle(date: .abbreviated, time: .shortened)
      .locale(Locale(identifier: "en_US_POSIX"))
    style.timeZone = TimeZone(secondsFromGMT: 0)!
    return date.formatted(style) + " UTC"
  }

  var shortSourceCommit: String? {
    sourceCommit.map { String($0.prefix(12)) }
  }

  var copyText: String {
    guard isPackaged else {
      return [
        "Fleck",
        "Build: Unpackaged development build",
        "Bundle identifier: \(bundleIdentifier ?? "Unavailable")",
      ].joined(separator: "\n")
    }
    var fields: [(String, String?)] = [
      ("Product version", productVersion),
      ("Build number", buildNumber),
      ("Bundle version", bundleVersion),
      ("Build ID", buildID),
      ("Build date (UTC)", buildDate),
      ("Source commit", sourceCommit),
      ("Source tree", sourceTree),
      ("Flavor", flavor),
      ("Configuration", configuration),
      ("Candidate status", candidateStatus),
      ("Baseline manifest SHA-256", baselineManifestSHA256),
      ("Baseline record", baselineRecordID),
      ("Baseline registry status", baselineRegistryStatus),
      ("Input build ID", inputBuildID),
      ("Input app manifest SHA-256", inputManifestSHA256),
      ("Bundle identifier", bundleIdentifier),
    ]
    fields.removeAll { $0.1 == nil }
    return fields.map { "\($0.0): \($0.1!)" }.joined(separator: "\n")
  }
}
