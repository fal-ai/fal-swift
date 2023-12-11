// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FalClient",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .macCatalyst(.v15),
        .tvOS(.v13),
        .watchOS(.v8),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "FalClient",
            targets: ["FalClient"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/nicklockwood/SwiftFormat", from: "0.52.10"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(name: "FalClient"),
        .testTarget(
            name: "FalClientTests",
            dependencies: ["FalClient"]
        ),
        .target(
            name: "FalSampleApp",
            dependencies: ["FalClient"],
            path: "Sources/Samples/FalSampleApp"
        ),
        .target(
            name: "FalCameraSampleApp",
            dependencies: ["FalClient"],
            path: "Sources/Samples/FalCameraSampleApp"
        ),
        .target(
            name: "FalRealtimeSampleApp",
            dependencies: ["FalClient"],
            path: "Sources/Samples/FalRealtimeSampleApp"
        ),
    ]
)
