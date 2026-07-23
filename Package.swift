// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "swift-test-doubles",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v16),
        .visionOS(.v1),
        .watchOS(.v9)
    ],
    products: [
        .library(name: "TestDoubles", targets: ["TestDoubles"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/tevelee/Echo.git",
            "0.0.4" ..< "0.1.0"
        ),
        .package(
            url: "https://github.com/pointfreeco/swift-issue-reporting",
            from: "2.0.0"
        )
    ],
    targets: [
        .target(
            name: "TestDoubles",
            dependencies: [
                "CTestDoublesTrampoline",
                .product(name: "Echo", package: "Echo"),
                .product(name: "IssueReporting", package: "swift-issue-reporting")
            ]
        ),
        .target(
            name: "CTestDoublesTrampoline",
            publicHeadersPath: "include"
        ),
        .target(
            name: "TestDoublesFixtures",
            path: "Tests/TestDoublesFixtures"
        ),
        .target(
            name: "TestDoublesResilientFixtures",
            path: "Tests/TestDoublesResilientFixtures",
            swiftSettings: [
                .unsafeFlags(["-enable-library-evolution"])
            ]
        ),
        .target(
            name: "TestDoublesReadFixtures",
            path: "Tests/TestDoublesReadFixtures",
            swiftSettings: [
                .enableExperimentalFeature("CoroutineAccessors")
            ]
        ),
        .testTarget(
            name: "TestDoublesTests",
            dependencies: [
                "TestDoubles",
                "TestDoublesFixtures",
                "TestDoublesResilientFixtures",
                .product(name: "IssueReportingTestSupport", package: "swift-issue-reporting")
            ]
        ),
        .testTarget(
            name: "TestDoublesReadTests",
            dependencies: [
                "TestDoubles",
                "TestDoublesReadFixtures"
            ],
            path: "Tests/TestDoublesReadTests",
            swiftSettings: [
                .enableExperimentalFeature("CoroutineAccessors")
            ]
        ),
        .testTarget(
            name: "TestDoublesWasmTests",
            dependencies: [
                "TestDoubles"
            ]
        ),
        // A standalone executable, not a test target: SwiftPM links every
        // test target into one shared binary, and the rest of the test
        // suite intentionally isn't wasm-safe (see AsyncStackSpyForwardingTests.swift
        // and ConcurrencyTests.swift). This is what actually runs under a
        // WASI runtime in CI to prove the ManualStub story end-to-end rather
        // than only compile it. See Scripts/validate-wasm.sh.
        .executableTarget(
            name: "WasmDemo",
            dependencies: [
                "TestDoubles"
            ]
        )
    ],
    // Tools version 6.3 already defaults to this; pinned explicitly so a
    // future tools-version bump can't silently change the language mode.
    swiftLanguageModes: [.v6]
)
