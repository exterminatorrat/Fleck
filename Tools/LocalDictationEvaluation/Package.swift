// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "LocalDictationEvaluation",
  platforms: [.macOS(.v14)],
  products: [
    .library(
      name: "LocalDictationEvaluation",
      targets: ["LocalDictationEvaluation"]
    ),
    .executable(
      name: "local-dictation-evaluation",
      targets: ["LocalDictationEvaluationCLI"]
    ),
  ],
  targets: [
    .target(name: "LocalDictationEvaluation"),
    .executableTarget(
      name: "LocalDictationEvaluationCLI",
      dependencies: ["LocalDictationEvaluation"]
    ),
    .testTarget(
      name: "LocalDictationEvaluationTests",
      dependencies: ["LocalDictationEvaluation"]
    ),
  ]
)
