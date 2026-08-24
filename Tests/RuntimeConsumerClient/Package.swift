// swift-tools-version: 6.3

import PackageDescription
import Foundation

let minimalRuntimeConsumerTests =
    ProcessInfo.processInfo.environment[
        "TESTDOUBLES_MINIMAL_RUNTIME_CONSUMER_TESTS"
    ] == "1"

let excludedConsumerTests =
    minimalRuntimeConsumerTests
    ? [
        "AsyncStreamControllerConsumerTests.swift",
        "ClosureArgumentConsumerTests.swift",
        "ExistentialArgumentConsumerTests.swift",
        "NestedValueConsumerTests.swift",
        "PointerConsumerTests.swift",
        "RuntimeConsumerClientTests.swift"
    ]
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
