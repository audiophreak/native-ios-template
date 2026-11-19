// swift-tools-version: 6.0
import PackageDescription

// Only the code generator, pinned exactly. It is run explicitly (ios/scripts/generate-client.sh) and its
// output is committed; nothing in the app's own build depends on it.
let package = Package(
    name: "Generator",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-generator", exact: "1.14.3"),
    ],
    targets: [
        .executableTarget(
            name: "generate",
            dependencies: [.product(name: "swift-openapi-generator", package: "swift-openapi-generator")],
            path: "Sources"
        )
    ]
)
