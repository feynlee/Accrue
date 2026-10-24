// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AccrueKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v18), .watchOS(.v11), .macOS(.v15)],
    products: [
        .library(name: "AccrueKit", targets: ["AccrueKit"]),
    ],
    targets: [
        .target(
            name: "AccrueKit",
            resources: [.copy("Resources/catalog.json")]
        ),
        .testTarget(
            name: "AccrueKitTests",
            dependencies: ["AccrueKit"]
        ),
    ]
)
