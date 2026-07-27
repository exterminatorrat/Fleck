// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Motes",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MenuBarNotesCore", targets: ["MenuBarNotesCore"]),
        .executable(name: "Motes", targets: ["MenuBarNotesApp"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/FluidInference/FluidAudio.git",
            exact: "0.15.5"
        ),
    ],
    targets: [
        .target(name: "MenuBarNotesCore"),
        .executableTarget(
            name: "MenuBarNotesApp",
            dependencies: [
                "MenuBarNotesCore",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "MenuBarNotesCoreTests",
            dependencies: ["MenuBarNotesCore"]
        ),
        .testTarget(
            name: "MenuBarNotesAppTests",
            dependencies: ["MenuBarNotesApp"]
        ),
    ]
)
