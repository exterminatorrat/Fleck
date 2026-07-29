// swift-tools-version: 6.0

import PackageDescription
import Foundation

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let infoPlistPath = packageRoot
    .appendingPathComponent("Sources/FleckApp/Info.plist").path
let enhancedCandidateEnabled =
    ProcessInfo.processInfo.environment["FLECK_ENHANCED_CANDIDATE"] == "1"

var packageDependencies: [Package.Dependency] = [
    .package(
        url: "https://github.com/modelcontextprotocol/swift-sdk.git",
        revision: "a0ae212ebf6eab5f754c3129608bc5557637e605"
    ),
]
var appDependencies: [Target.Dependency] = [
    "FleckCore",
    "FleckAgentProtocol",
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
        .package(path: "Packages/FleckEnhancedCandidateDependencies")
    )
    appDependencies.append(
        .product(
            name: "FleckEnhancedCandidateDependencies",
            package: "FleckEnhancedCandidateDependencies"
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
    name: "Fleck",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FleckCore", targets: ["FleckCore"]),
        .library(
            name: "FleckAgentProtocol",
            targets: ["FleckAgentProtocol"]
        ),
        .executable(name: "Fleck", targets: ["FleckApp"]),
        .executable(name: "fleck-agent", targets: ["FleckAgentBridge"]),
    ],
    dependencies: packageDependencies,
    targets: [
        .target(
            name: "FleckCore",
            swiftSettings: coreSwiftSettings
        ),
        .target(
            name: "FleckAgentProtocol",
            dependencies: ["FleckCore"]
        ),
        .executableTarget(
            name: "FleckApp",
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
        .executableTarget(
            name: "FleckAgentBridge",
            dependencies: [
                "FleckCore",
                "FleckAgentProtocol",
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),
        .testTarget(
            name: "FleckCoreTests",
            dependencies: ["FleckCore"]
        ),
        .testTarget(
            name: "FleckAgentProtocolTests",
            dependencies: ["FleckAgentProtocol", "FleckCore"]
        ),
        .testTarget(
            name: "FleckAppTests",
            dependencies: ["FleckApp"],
            swiftSettings: appTestSwiftSettings
        ),
        .testTarget(
            name: "FleckAgentBridgeTests",
            dependencies: ["FleckAgentBridge"]
        ),
    ]
)
