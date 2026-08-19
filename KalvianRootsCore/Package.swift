// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "KalvianRootsCore",
  platforms: [
    .macOS(.v13),
    .iOS(.v16),
  ],
  products: [
    .library(name: "KalvianRootsCore", targets: ["KalvianRootsCore"])
  ],
  targets: [
    .target(name: "KalvianRootsCore"),
    .testTarget(
      name: "KalvianRootsCoreTests",
      dependencies: ["KalvianRootsCore"],
      resources: [.copy("Fixtures")]
    ),
  ]
)
