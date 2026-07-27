// swift-tools-version: 6.0

import PackageDescription
import Foundation

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let infoPlistPath = packageRoot
    .appendingPathComponent("Sources/MenuBarNotesApp/Info.plist").path
let enhancedCandidateEnabled =
    ProcessInfo.processInfo.environment["MOTES_ENHANCED_CANDIDATE"] == "1"

let packageDependencies: [Package.Dependency] = [
    .package(
        url: "https://github.com/FluidInference/FluidAudio.git",
        exact: "0.15.5"
    ),
]
var appDependencies: [Target.Dependency] = ["MenuBarNotesCore"]
var coreSwiftSettings: [SwiftSetting] = []
var appSwiftSettings: [SwiftSetting] = []
var appTestSwiftSettings: [SwiftSetting] = []

if enhancedCandidateEnabled {
    appDependencies.append(
        .product(name: "FluidAudio", package: "FluidAudio")
    )
    appSwiftSettings.append(
        .define(
            "CLEAN_DICTATION_ENHANCED_CANDIDATE",
            .when(configuration: .debug)
        )
    )
    coreSwiftSettings.append(
        .define(
            "CLEAN_DICTATION_ENHANCED_CANDIDATE",
            .when(configuration: .debug)
        )
    )
    appTestSwiftSettings.append(
        .define(
            "CLEAN_DICTATION_ENHANCED_CANDIDATE",
            .when(configuration: .debug)
        )
    )
}

let package = Package(
    name: "Motes",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MenuBarNotesCore", targets: ["MenuBarNotesCore"]),
        .executable(name: "Motes", targets: ["MenuBarNotesApp"]),
    ],
    dependencies: packageDependencies,
    targets: [
        .target(
            name: "MenuBarNotesCore",
            swiftSettings: coreSwiftSettings
        ),
        .executableTarget(
            name: "MenuBarNotesApp",
            dependencies: appDependencies,
            exclude: ["Info.plist"],
            resources: [.process("Resources")],
            swiftSettings: appSwiftSettings,
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", infoPlistPath,
                ])
            ]
        ),
        .testTarget(
            name: "MenuBarNotesCoreTests",
            dependencies: ["MenuBarNotesCore"]
        ),
        .testTarget(
            name: "MenuBarNotesAppTests",
            dependencies: ["MenuBarNotesApp"],
            swiftSettings: appTestSwiftSettings
        ),
    ]
)
