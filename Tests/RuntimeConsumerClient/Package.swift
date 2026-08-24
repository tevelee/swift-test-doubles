// swift-tools-version: 6.3

import PackageDescription
import Foundation

let excludedConsumerTests =
    ProcessInfo.processInfo.environment[
        "TESTDOUBLES_EXCLUDE_STREAM_CONSUMER_TESTS"
    ] == "1"
    ? ["AsyncStreamControllerConsumerTests.swift"]
    : []

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
            exclude: excludedConsumerTests
        )
    ]
)
