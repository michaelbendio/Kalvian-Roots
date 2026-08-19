// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "KalvianRootsCore",
  platforms: [
    .macOS(.v13),
    .iOS(.v16),
  ],
  products: [
    .library(name: "KalvianRootsCore", targets: ["KalvianRootsCore"]),
    .executable(name: "KalvianRootsMCP", targets: ["KalvianRootsMCP"]),
  ],
  dependencies: [
    .package(
      url: "https://github.com/modelcontextprotocol/swift-sdk.git",
      revision: "a0ae212ebf6eab5f754c3129608bc5557637e605"
    ),
  ],
  targets: [
    .target(name: "KalvianRootsCore"),
    .target(
      name: "KalvianRootsMCPServer",
      dependencies: [
        "KalvianRootsCore",
        .product(name: "MCP", package: "swift-sdk"),
      ]
    ),
    .executableTarget(
      name: "KalvianRootsMCP",
      dependencies: ["KalvianRootsMCPServer"]
    ),
    .testTarget(
      name: "KalvianRootsCoreTests",
      dependencies: ["KalvianRootsCore"],
      resources: [.copy("Fixtures")]
    ),
    .testTarget(
      name: "KalvianRootsMCPServerTests",
      dependencies: [
        "KalvianRootsMCPServer",
        .product(name: "MCP", package: "swift-sdk"),
      ]
    ),
  ]
)
