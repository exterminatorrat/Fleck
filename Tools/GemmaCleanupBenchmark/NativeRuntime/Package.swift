// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GemmaCleanupNativeRuntime",
    platforms: [.macOS(.v14)],
    products: [
        .executable(
            name: "gemma-cleanup-helper",
            targets: ["GemmaCleanupHelper"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/ml-explore/mlx-swift-lm.git",
            revision: "bd4b7434e6bdb588c7ef55706ff8904cb7fd4c57"
        ),
        .package(
            url: "https://github.com/huggingface/swift-transformers.git",
            exact: "1.3.0"
        ),
    ],
    targets: [
        .executableTarget(
            name: "GemmaCleanupHelper",
            dependencies: [
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ]
        ),
        .testTarget(
            name: "GemmaCleanupHelperTests",
            dependencies: ["GemmaCleanupHelper"]
        ),
    ]
)
