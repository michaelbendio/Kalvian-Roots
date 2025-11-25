// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "KalvianRootsCore",
    platforms: [
        .macOS(.v13), .iOS(.v16)
    ],
    products: [
        .library(
            name: "KalvianRootsCore",
            type: .dynamic,   // or .static, doesn't matter
            targets: ["KalvianRootsCore"]
        ),
    ],
    targets: [
        .target(
            name: "KalvianRootsCore",
            path: "Sources/KalvianRootsCore"
        ),
        .testTarget(
            name: "KalvianRootsCoreTests",
            dependencies: ["KalvianRootsCore"],
            path: "Tests/KalvianRootsCoreTests"
        )
    ]
)
