// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ClipPlusMac",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "ClipPlusMac",
            targets: ["ClipPlusMac"]
        )
    ],
    targets: [
        .executableTarget(
            name: "ClipPlusMac"
        ),
        .testTarget(
            name: "ClipPlusMacTests",
            dependencies: ["ClipPlusMac"]
        )
    ]
)
