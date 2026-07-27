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
            "0.1.1" ..< "0.2.0"
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
                "InternalRuntimeContract",
                "TestDoublesRuntime",
                "TestDoublesRuntimeSupport",
                .product(name: "IssueReporting", package: "swift-issue-reporting")
            ]
        ),
        .target(
            name: "TestDoublesRuntime",
            dependencies: [
                "InternalRuntimeContract",
                "TestDoublesRuntimeMetadata",
                "TestDoublesRuntimeSupport",
                "CTestDoublesTrampoline",
                .product(name: "Echo", package: "Echo"),
                .product(
                    name: "EchoRuntimeReflection",
                    package: "Echo"
                ),
                .product(
                    name: "EchoRuntimeSupport",
                    package: "Echo"
                )
            ]
        ),
        .target(
            name: "TestDoublesRuntimeMetadata",
            dependencies: [
                "InternalRuntimeContract",
                "TestDoublesRuntimeSupport",
                "CTestDoublesTrampoline",
                .product(name: "Echo", package: "Echo"),
                .product(
                    name: "EchoRuntimeReflection",
                    package: "Echo"
                )
            ]
        ),
        .target(
            name: "TestDoublesRuntimeSupport",
            dependencies: ["CTestDoublesTrampoline"]
        ),
        .target(name: "InternalRuntimeContract"),
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
                "TestDoublesRuntime",
                "TestDoublesRuntimeMetadata",
                "TestDoublesRuntimeSupport",
                "InternalRuntimeContract",
                "TestDoublesFixtures",
                "TestDoublesResilientFixtures",
                .product(name: "IssueReportingTestSupport", package: "swift-issue-reporting")
            ]
        ),
        .testTarget(
            name: "TestDoublesInternalTests",
            dependencies: [
                "TestDoubles",
                "InternalRuntimeContract"
            ],
            path: "Tests/TestDoublesInternalTests"
        ),
        .testTarget(
            name: "TestDoublesRuntimeIntegrationTests",
            dependencies: [
                "TestDoubles",
                "TestDoublesRuntime"
            ],
            path: "Tests/TestDoublesRuntimeIntegrationTests"
        ),
        .testTarget(
            name: "InternalRuntimeContractTests",
            dependencies: ["InternalRuntimeContract"],
            path: "Tests/InternalRuntimeContractTests"
        ),
        .testTarget(
            name: "TestDoublesReadTests",
            dependencies: [
                "TestDoubles",
                "TestDoublesRuntime",
                "TestDoublesRuntimeMetadata",
                "InternalRuntimeContract",
                "TestDoublesReadFixtures"
            ],
            path: "Tests/TestDoublesReadTests",
            swiftSettings: [
                .enableExperimentalFeature("CoroutineAccessors")
            ]
        ),
        .testTarget(
            name: "TestDoublesRuntimeTests",
            dependencies: [
                "TestDoublesRuntime",
                "TestDoublesRuntimeMetadata",
                "TestDoublesRuntimeSupport",
                "TestDoublesFixtures",
                .product(name: "Echo", package: "Echo"),
                .product(
                    name: "EchoRuntimeReflection",
                    package: "Echo"
                ),
                .product(
                    name: "EchoRuntimeSupport",
                    package: "Echo"
                )
            ],
            path: "Tests/TestDoublesRuntimeTests"
        ),
        .testTarget(
            name: "TestDoublesWasmTests",
            dependencies: [
                "TestDoubles"
            ]
        ),
        // A minimal C++ foreign reference type fixture, kept in its own
        // target because only a target with `.interoperabilityMode(.Cxx)`
        // can import it. Proves the Echo 0.1.17 CEcho build fix
        // (CXX_FOREIGN_REFERENCE_FEASIBILITY.md) end to end: before it, any
        // target enabling C++ interop anywhere in its dependency graph could
        // not depend on TestDoubles at all.
        .target(
            name: "TestDoublesCxxInteropFixtures",
            path: "Tests/TestDoublesCxxInteropFixtures",
            publicHeadersPath: "include"
        ),
        .testTarget(
            name: "TestDoublesCxxInteropTests",
            dependencies: [
                "TestDoubles",
                "TestDoublesCxxInteropFixtures"
            ],
            path: "Tests/TestDoublesCxxInteropTests",
            swiftSettings: [.interoperabilityMode(.Cxx)]
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
        ),
        // A small native runtime smoke executable. CI cross-builds it for
        // Android x86_64, pushes the result to an emulator, and executes it
        // there. Unlike WasmDemo, this deliberately exercises the fabricated
        // Stub path, including its executable witness veneer.
        .executableTarget(
            name: "AndroidRuntimeDemo",
            dependencies: [
                "TestDoubles"
            ]
        )
    ],
    // Tools version 6.3 already defaults to this; pinned explicitly so a
    // future tools-version bump can't silently change the language mode.
    swiftLanguageModes: [.v6]
)
