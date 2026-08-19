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
    .target(
      name: "QwenASRSpikeContract",
      path: "Spikes/QwenASR/Sources/QwenASRSpikeContract"
    ),
    .target(
      name: "NemotronASRSpikeContract",
      path: "Spikes/NemotronASR/Sources/NemotronASRSpikeContract"
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
        "QwenASRSpikeContract",
        "NemotronASRSpikeContract",
      ]
    ),
  ]
)
