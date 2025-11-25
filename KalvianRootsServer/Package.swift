// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "KalvianRootsServer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Run", targets: ["Run"])
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.90.0"),
        .package(path: "../KalvianRootsCore")
    ],
    targets: [
        .target(
            name: "KalvianRootsServer",
            dependencies: [
                .product(name: "KalvianRootsCore", package: "KalvianRootsCore"),
                .product(name: "Vapor", package: "vapor")
            ],
            path: "Sources/App"
        ),
        .executableTarget(
            name: "Run",
            dependencies: ["KalvianRootsServer"],
            path: "Sources/Run"
        )
    ]
)
