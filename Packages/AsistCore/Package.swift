// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AsistCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "AsistCore", targets: ["AsistCore"]),
        // CI only (simulator smoke test): writes a realistic asist-data.json. The app never links it.
        .executable(name: "AsistSeed", targets: ["AsistSeed"])
    ],
    targets: [
        .target(
            name: "AsistCore",
            path: "Sources/AsistCore"
        ),
        .executableTarget(
            name: "AsistSeed",
            dependencies: ["AsistCore"],
            path: "Sources/AsistSeed"
        ),
        .testTarget(
            name: "AsistCoreTests",
            dependencies: ["AsistCore"],
            path: "Tests/AsistCoreTests"
        )
    ]
)
