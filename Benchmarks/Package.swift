// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "swift-test-doubles-benchmarks",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(name: "swift-test-doubles", path: "..")
    ],
    targets: [
        .target(
            name: "BenchmarkFixtures",
            swiftSettings: [
                .enableExperimentalFeature("CoroutineAccessors")
            ]
        ),
        .executableTarget(
            name: "TestDoublesBenchmarks",
            dependencies: [
                "BenchmarkFixtures",
                .product(
                    name: "TestDoubles",
                    package: "swift-test-doubles"
                )
            ],
            swiftSettings: [
                .enableExperimentalFeature("CoroutineAccessors")
            ]
        )
    ]
)
