// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "LocalDictationCandidateAdapters",
  platforms: [.macOS(.v14)],
  products: [
    .library(
      name: "LocalDictationCandidateProtocol",
      targets: ["LocalDictationCandidateProtocol"]
    ),
    .executable(
      name: "local-dictation-candidate",
      targets: ["LocalDictationCandidateCLI"]
    ),
  ],
  targets: [
    .target(name: "LocalDictationCandidateProtocol"),
    .target(
      name: "LocalDictationCandidateRunner",
      dependencies: ["LocalDictationCandidateProtocol"]
    ),
    .executableTarget(
      name: "LocalDictationCandidateCLI",
      dependencies: [
        "LocalDictationCandidateProtocol",
        "LocalDictationCandidateRunner",
      ]
    ),
    .testTarget(
      name: "LocalDictationCandidateAdaptersTests",
      dependencies: [
        "LocalDictationCandidateProtocol",
        "LocalDictationCandidateRunner",
        "LocalDictationCandidateCLI",
      ]
    ),
  ]
)
