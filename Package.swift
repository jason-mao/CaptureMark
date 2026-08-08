// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "CaptureMark",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CaptureMark", targets: ["CaptureMark"])
    ],
    targets: [
        .executableTarget(
            name: "CaptureMark",
            path: "Sources/CaptureMark"
        )
    ]
)
