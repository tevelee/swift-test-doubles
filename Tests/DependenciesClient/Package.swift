// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "DependenciesClient",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(
            path: "../..",
            traits: ["StubbableMacros"]
        ),
        .package(
            url: "https://github.com/pointfreeco/swift-dependencies",
            from: "1.12.0"
        )
    ],
    targets: [
        .target(
            name: "DependenciesClientFixtures",
            dependencies: [
                .product(
                    name: "Dependencies",
                    package: "swift-dependencies"
                ),
                .product(
                    name: "TestDoubles",
                    package: "swift-test-doubles"
                ),
                .product(
                    name: "TestDoublesMacros",
                    package: "swift-test-doubles"
                )
            ]
        ),
        .testTarget(
            name: "DependenciesClientTests",
            dependencies: [
                "DependenciesClientFixtures",
                .product(
                    name: "DependenciesTestSupport",
                    package: "swift-dependencies"
                )
            ]
        )
    ]
)
