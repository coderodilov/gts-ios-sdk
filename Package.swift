// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GtsSdk",
    platforms: [
        .iOS(.v13),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "GtsSdk",
            targets: ["GtsSdk"]
        )
    ],
    targets: [
        .target(
            name: "GtsSdk",
            path: "Sources/GtsSdk"
        ),
        .testTarget(
            name: "GtsSdkTests",
            dependencies: ["GtsSdk"],
            path: "Tests/GtsSdkTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
