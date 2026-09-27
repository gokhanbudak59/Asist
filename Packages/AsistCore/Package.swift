// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AsistCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "AsistCore", targets: ["AsistCore"])
    ],
    targets: [
        .target(
            name: "AsistCore",
            path: "Sources/AsistCore"
        ),
        .testTarget(
            name: "AsistCoreTests",
            dependencies: ["AsistCore"],
            path: "Tests/AsistCoreTests"
        )
    ]
)
