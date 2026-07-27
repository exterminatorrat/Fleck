// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MotesEnhancedCandidateDependencies",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "MotesEnhancedCandidateDependencies",
            targets: ["MotesEnhancedCandidateDependencies"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/FluidInference/FluidAudio.git",
            exact: "0.15.5"
        ),
    ],
    targets: [
        .target(
            name: "MotesEnhancedCandidateDependencies",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        ),
    ]
)
