// swift-tools-version: 6.0

import PackageDescription
import Foundation

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let infoPlistPath = packageRoot
    .appendingPathComponent("Sources/MenuBarNotesApp/Info.plist").path
let enhancedCandidateEnabled =
    ProcessInfo.processInfo.environment["MOTES_ENHANCED_CANDIDATE"] == "1"

var packageDependencies: [Package.Dependency] = [
    .package(
        url: "https://github.com/modelcontextprotocol/swift-sdk.git",
        revision: "a0ae212ebf6eab5f754c3129608bc5557637e605"
    ),
]
var appDependencies: [Target.Dependency] = [
    "MenuBarNotesCore",
    "MenuBarNotesAgentProtocol",
]
var appExcludes = [
    "Info.plist",
    "Resources",
    "EnhancedModelManager.swift",
    "EnhancedSpeechCapture.swift",
]
var appResources: [Resource] = []
var coreSwiftSettings: [SwiftSetting] = []
var appSwiftSettings: [SwiftSetting] = []
var appTestSwiftSettings: [SwiftSetting] = []

if enhancedCandidateEnabled {
    packageDependencies.append(
        .package(path: "Packages/MotesEnhancedCandidateDependencies")
    )
    appDependencies.append(
        .product(
            name: "MotesEnhancedCandidateDependencies",
            package: "MotesEnhancedCandidateDependencies"
        )
    )
    appExcludes = ["Info.plist"]
    appResources.append(.process("Resources"))
    let requested = SwiftSetting.define(
        "CLEAN_DICTATION_ENHANCED_CANDIDATE_REQUESTED"
    )
    coreSwiftSettings.append(requested)
    appSwiftSettings.append(requested)
    appTestSwiftSettings.append(requested)
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
        .library(
            name: "MenuBarNotesAgentProtocol",
            targets: ["MenuBarNotesAgentProtocol"]
        ),
        .executable(name: "Motes", targets: ["MenuBarNotesApp"]),
    ],
    dependencies: packageDependencies,
    targets: [
        .target(
            name: "MenuBarNotesCore",
            swiftSettings: coreSwiftSettings
        ),
        .target(
            name: "MenuBarNotesAgentProtocol",
            dependencies: ["MenuBarNotesCore"]
        ),
        .executableTarget(
            name: "MenuBarNotesApp",
            dependencies: appDependencies,
            exclude: appExcludes,
            resources: appResources,
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
            name: "MenuBarNotesAgentProtocolTests",
            dependencies: ["MenuBarNotesAgentProtocol", "MenuBarNotesCore"]
        ),
        .testTarget(
            name: "MenuBarNotesAppTests",
            dependencies: ["MenuBarNotesApp"],
            swiftSettings: appTestSwiftSettings
        ),
    ]
)
