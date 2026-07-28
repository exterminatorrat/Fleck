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
            revision: "19600a485baa4998812e4654b70d2bab8f2c9949"
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
