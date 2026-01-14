# Adding SwiftNIO Dependency to Kalvian Roots

The HTTP server implementation requires SwiftNIO to be added as a package dependency. Follow these steps to add it to the Xcode project:

## Steps to Add SwiftNIO

1. **Open the project in Xcode**
   - Open `Kalvian Roots.xcodeproj` in Xcode

2. **Add Package Dependency**
   - Select the project in the navigator (top-level "Kalvian Roots")
   - Select the "Kalvian Roots" target
   - Go to the "General" tab
   - Scroll down to "Frameworks, Libraries, and Embedded Content"
   - Click the "+" button
   - Choose "Add Package Dependency..."

3. **Add SwiftNIO Package**
   - Enter the SwiftNIO repository URL: `https://github.com/apple/swift-nio.git`
   - Click "Add Package"
   - For version rules, choose "Up to Next Major Version" with minimum version `2.62.0`
   - Click "Add Package"

4. **Select Package Products**
   - In the package products selection dialog, check the following products:
     - ✅ NIOCore
     - ✅ NIOPosix
     - ✅ NIOHTTP1
   - Make sure they're added to the "Kalvian Roots" target
   - Click "Add Package"

5. **Build the Project**
   - Press Cmd+B to build the project
   - The server files should now compile successfully

## Alternative: Using Swift Package Manager Directly

If you prefer to use Swift Package Manager directly, you can create a Package.swift file:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KalvianRoots",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "KalvianRoots",
            targets: ["KalvianRoots"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.62.0"),
    ],
    targets: [
        .target(
            name: "KalvianRoots",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
            ],
            path: "Kalvian Roots"
        ),
    ]
)
```

However, since this is an existing Xcode project, the first method (adding through Xcode) is recommended.

## Verification

After adding SwiftNIO, verify the server works:

1. Build and run the app on macOS
2. Check the console for: "🌐 HTTP server started on port 8080"
3. Access the server via your Tailscale IP: `http://[your-tailscale-ip]:8080`

## Troubleshooting

If you encounter build errors:
- Make sure you're building for macOS (not iOS) when testing the server
- Ensure all three SwiftNIO products are added (NIOCore, NIOPosix, NIOHTTP1)
- Clean the build folder (Shift+Cmd+K) and rebuild

## Note on iOS

The HTTP server is only available on macOS. The iOS app will compile and run normally without the server functionality.