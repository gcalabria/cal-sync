// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CalSync",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "CalSync",
            path: "Sources/CalSync",
            exclude: ["Info.plist"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("EventKit"),
            ]
        )
    ]
)
