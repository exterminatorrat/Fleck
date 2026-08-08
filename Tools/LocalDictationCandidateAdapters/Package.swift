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
    .testTarget(
      name: "LocalDictationCandidateAdaptersTests",
      dependencies: ["LocalDictationCandidateProtocol"]
    ),
  ]
)
