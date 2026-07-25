// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MenuBarNotes",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MenuBarNotesCore", targets: ["MenuBarNotesCore"]),
        .executable(name: "MenuBarNotes", targets: ["MenuBarNotesApp"]),
    ],
    targets: [
        .target(name: "MenuBarNotesCore"),
        .executableTarget(
            name: "MenuBarNotesApp",
            dependencies: ["MenuBarNotesCore"]
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
