// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "TestDoublesConsumer",
    platforms: [.macOS(.v13)],
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
