// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FalClient",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .macCatalyst(.v15),
        .tvOS(.v15),
        .watchOS(.v8),
    ],
    products: [
        .library(
            name: "FalClient",
            targets: ["FalClient"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/nnabeyang/swift-msgpack.git", from: "0.3.3"),
        .package(url: "https://github.com/Quick/Quick.git", from: "7.3.0"),
        .package(url: "https://github.com/Quick/Nimble.git", from: "13.0.0"),
    ],
    targets: [
        .target(
            name: "FalClient",
            dependencies: [
                .product(name: "SwiftMsgpack", package: "swift-msgpack"),
            ],
            path: "Sources/FalClient"
        ),
        .testTarget(
            name: "FalClientTests",
            dependencies: [
                "FalClient",
                .product(name: "Quick", package: "quick"),
                .product(name: "Nimble", package: "nimble"),
            ],
            path: "Tests/FalClientTests"
        ),
    ]
)
