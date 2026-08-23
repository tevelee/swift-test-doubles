// swift-tools-version: 6.3

import Foundation
import CompilerPluginSupport
import PackageDescription

// The C++ interop target breaks the WASI SDK's module cache when
// `--build-tests` compiles it alongside everything else; validate-wasm.sh
// sets this to exclude it from that one build.
let includesCxxInteropTarget =
    ProcessInfo.processInfo.environment["TESTDOUBLES_SKIP_CXX_INTEROP"] == nil
let enablesCCoverage =
    ProcessInfo.processInfo.environment["TESTDOUBLES_ENABLE_C_COVERAGE"] == "1"

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
        .library(name: "TestDoubles", targets: ["TestDoubles"]),
        .library(name: "TestDoublesTesting", targets: ["TestDoublesTesting"]),
        .library(name: "TestDoublesMacros", targets: ["TestDoublesMacros"]),
        .plugin(name: "ManualStubGenerator", targets: ["ManualStubGenerator"]),
        .plugin(name: "ManualStubBuildPlugin", targets: ["ManualStubBuildPlugin"])
    ],
    traits: [
        .default(enabledTraits: ["RuntimeStubs"]),
        .trait(
            name: "RuntimeStubs",
            description: "Enables runtime-generated Stub, Spy, and Dummy values."
        ),
        .trait(
            name: "ManualStubGenerator",
            description: "Enables the ManualStubGenerator command plugin."
        ),
        .trait(
            name: "StubbableMacros",
            description: "Enables @Stubbable macros and their SwiftSyntax dependency."
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/tevelee/Echo.git",
            "0.1.1" ..< "0.2.0"
        ),
        .package(
            url: "https://github.com/pointfreeco/swift-issue-reporting",
            from: "2.0.0"
        ),
        .package(
            url: "https://github.com/swiftlang/swift-syntax.git",
            from: "603.0.0-latest",
            traits: [
                .trait(
                    name: "default",
                    condition: .when(traits: ["StubbableMacros"])
                )
            ]
        ),
        .package(
            url: "https://github.com/pointfreeco/swift-macro-testing",
            from: "0.6.5",
            traits: [
                .trait(
                    name: "default",
                    condition: .when(traits: ["StubbableMacros"])
                )
            ]
        )
    ],
    targets: allTargets(
        includesCxxInteropTarget: includesCxxInteropTarget,
        enablesCCoverage: enablesCCoverage
    ),
    // Tools version 6.3 already defaults to this; pinned explicitly so a
    // future tools-version bump can't silently change the language mode.
    swiftLanguageModes: [.v6]
)

private func allTargets(
    includesCxxInteropTarget: Bool,
    enablesCCoverage: Bool
) -> [Target] {
    var targets: [Target] = [
        .target(name: "ManualStubGeneratorCore"),
        .testTarget(
            name: "ManualStubGeneratorCoreTests",
            dependencies: ["ManualStubGeneratorCore"]
        ),
        .executableTarget(
            name: "ManualStubGeneratorTool",
            dependencies: ["ManualStubGeneratorCore"]
        ),
        .plugin(
            name: "ManualStubGenerator",
            capability: .command(
                intent: .custom(
                    verb: "generate-manual-stub",
                    description: "Generate a ManualStub conformer from a protocol declaration."
                ),
                permissions: [.writeToPackageDirectory(reason: "Writes the generated Swift conformer you request.")]
            ),
            dependencies: [
                .target(
                    name: "ManualStubGeneratorTool",
                    condition: .when(traits: ["ManualStubGenerator"])
                )
            ]
        ),
        .plugin(
            name: "ManualStubBuildPlugin",
            capability: .buildTool(),
            dependencies: ["ManualStubGeneratorTool"]
        ),
        .target(
            name: "TestDoublesMacros",
            dependencies: [
                "TestDoubles",
                .target(
                    name: "TestDoublesStubbableMacros",
                    condition: .when(traits: ["StubbableMacros"])
                )
            ],
            swiftSettings: [
                .define(
                    "TESTDOUBLES_STUBBABLE_MACROS",
                    .when(traits: ["StubbableMacros"])
                )
            ]
        ),
        .macro(
            name: "TestDoublesStubbableMacros",
            dependencies: [
                "ManualStubGeneratorCore",
                .product(
                    name: "SwiftCompilerPlugin",
                    package: "swift-syntax",
                    condition: .when(traits: ["StubbableMacros"])
                ),
                .product(
                    name: "SwiftDiagnostics",
                    package: "swift-syntax",
                    condition: .when(traits: ["StubbableMacros"])
                ),
                .product(
                    name: "SwiftSyntax",
                    package: "swift-syntax",
                    condition: .when(traits: ["StubbableMacros"])
                ),
                .product(
                    name: "SwiftSyntaxMacros",
                    package: "swift-syntax",
                    condition: .when(traits: ["StubbableMacros"])
                )
            ],
            swiftSettings: [
                .define(
                    "TESTDOUBLES_STUBBABLE_MACROS",
                    .when(traits: ["StubbableMacros"])
                )
            ]
        ),
        .target(
            name: "TestDoubles",
            dependencies: [
                "InternalRuntimeContract",
                .target(
                    name: "TestDoublesRuntime",
                    condition: .when(traits: ["RuntimeStubs"])
                ),
                .target(
                    name: "TestDoublesRuntimeSupport",
                    condition: .when(traits: ["RuntimeStubs"])
                ),
                .product(name: "IssueReporting", package: "swift-issue-reporting")
            ],
            swiftSettings: [
                .define(
                    "TESTDOUBLES_RUNTIME_STUBS",
                    .when(traits: ["RuntimeStubs"])
                )
            ]
        ),
        .target(
            name: "TestDoublesTesting",
            dependencies: [
                "TestDoubles",
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
            publicHeadersPath: "include",
            cSettings: enablesCCoverage
                ? [.unsafeFlags(["-fprofile-instr-generate", "-fcoverage-mapping"])]
                : []
        ),
        .target(
            name: "TestDoublesFixtures",
            path: "Tests/TestDoublesFixtures"
        ),
        .target(
            name: "ManualStubGeneratorIntegrationFixtures",
            dependencies: ["TestDoubles"],
            path: "Tests/ManualStubGeneratorIntegrationFixtures"
        ),
        .target(
            name: "ManualStubBuildPluginIntegrationFixtures",
            dependencies: ["TestDoubles"],
            path: "Tests/ManualStubBuildPluginIntegrationFixtures",
            plugins: [.plugin(name: "ManualStubBuildPlugin")]
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
            dependencies: ["TestDoublesResilientFixtures"],
            path: "Tests/TestDoublesReadFixtures",
            swiftSettings: [
                .enableExperimentalFeature("CoroutineAccessors")
            ]
        ),
        .testTarget(
            name: "TestDoublesTests",
            dependencies: [
                "TestDoubles",
                "TestDoublesTesting",
                "TestDoublesRuntime",
                "TestDoublesRuntimeMetadata",
                "TestDoublesRuntimeSupport",
                "InternalRuntimeContract",
                "ManualStubBuildPluginIntegrationFixtures",
                "ManualStubGeneratorIntegrationFixtures",
                "TestDoublesFixtures",
                "TestDoublesResilientFixtures",
                .target(
                    name: "TestDoublesMacros",
                    condition: .when(traits: ["StubbableMacros"])
                ),
                .product(
                    name: "IssueReportingTestSupport",
                    package: "swift-issue-reporting",
                    // MacroTesting's SnapshotTesting dependency also provides
                    // this module name through XCTestDynamicOverlay.
                    moduleAliases: [
                        "IssueReportingTestSupport": "TestDoublesIssueReportingTestSupport"
                    ]
                )
            ],
            swiftSettings: [
                .define(
                    "TESTDOUBLES_STUBBABLE_MACROS",
                    .when(traits: ["StubbableMacros"])
                )
            ]
        ),
        .testTarget(
            name: "TestDoublesMacroTests",
            dependencies: [
                .target(
                    name: "TestDoublesStubbableMacros",
                    condition: .when(traits: ["StubbableMacros"])
                ),
                .product(
                    name: "MacroTesting",
                    package: "swift-macro-testing",
                    moduleAliases: [
                        "IssueReporting": "MacroTestingIssueReporting"
                    ],
                    condition: .when(traits: ["StubbableMacros"])
                ),
                .product(
                    name: "IssueReporting",
                    package: "swift-issue-reporting",
                    condition: .when(traits: ["StubbableMacros"])
                )
            ],
            swiftSettings: [
                .define(
                    "TESTDOUBLES_STUBBABLE_MACROS",
                    .when(traits: ["StubbableMacros"])
                )
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
                "TestDoublesReadFixtures",
                "TestDoublesResilientFixtures"
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
                "TestDoublesResilientFixtures",
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
    ]
    if includesCxxInteropTarget {
        // Separate target: only one with `.interoperabilityMode(.Cxx)` can import it.
        targets.append(
            .target(
                name: "TestDoublesCxxInteropFixtures",
                path: "Tests/TestDoublesCxxInteropFixtures",
                publicHeadersPath: "include"
            ))
        targets.append(
            .testTarget(
                name: "TestDoublesCxxInteropTests",
                dependencies: [
                    "TestDoubles",
                    "TestDoublesCxxInteropFixtures"
                ],
                path: "Tests/TestDoublesCxxInteropTests",
                swiftSettings: [.interoperabilityMode(.Cxx)]
            ))
    }
    return targets
}
