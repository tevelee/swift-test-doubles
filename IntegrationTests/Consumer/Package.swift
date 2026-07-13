// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "TestDoublesConsumer",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v16),
        .visionOS(.v1),
        .watchOS(.v9),
    ],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .testTarget(
            name: "TestDoublesConsumerTests",
            dependencies: [
                .product(
                    name: "TestDoubles",
                    package: "swift-test-doubles"
                ),
            ]
        ),
    ]
)
