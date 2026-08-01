// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "RuntimeConsumerClient",
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .target(
            name: "ConsumerFixtures",
            swiftSettings: [
                .unsafeFlags(["-enable-library-evolution"])
            ]
        ),
        .testTarget(
            name: "RuntimeConsumerClientTests",
            dependencies: [
                "ConsumerFixtures",
                .product(
                    name: "TestDoubles",
                    package: "swift-test-doubles"
                )
            ]
        )
    ]
)
