// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RotateApps",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "RotateApps", targets: ["RotateApps"])
    ],
    targets: [
        .executableTarget(
            name: "RotateApps",
            path: "Sources/RotateApps",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
