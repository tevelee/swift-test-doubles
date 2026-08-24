// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "RuntimeConsumerClient",
    platforms: [.macOS(.v10_15)],
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
            ],
            // Swift 6.3.3's Linux frontend crashes in LoadableByAddress when it
            // batches this external-consumer suite. Compile each primary file
            // separately until that toolchain bug is fixed.
            swiftSettings: [
                .unsafeFlags(["-disable-batch-mode"])
            ]
        )
    ]
)
