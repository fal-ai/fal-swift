// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FalClient",
    platforms: [
        .iOS(.v16),
        .macOS(.v12),
        .macCatalyst(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
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
        .package(url: "https://github.com/fumoboy007/msgpack-swift.git", from: "2.0.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "FalClient",
            dependencies: [
                .product(name: "DMMessagePack", package: "msgpack-swift")
            ],
            path: "Sources/FalClient"
        ),
        .testTarget(
            name: "FalClientTests",
            dependencies: ["FalClient"],
            path: "Tests/FalClientTests"
        )
    ]
)
