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
  ],
  targets: [
    .target(name: "LocalDictationCandidateProtocol"),
    .target(
      name: "LocalDictationCandidateRunner",
      dependencies: ["LocalDictationCandidateProtocol"]
    ),
    .testTarget(
      name: "LocalDictationCandidateAdaptersTests",
      dependencies: [
        "LocalDictationCandidateProtocol",
        "LocalDictationCandidateRunner",
      ]
    ),
  ]
)
