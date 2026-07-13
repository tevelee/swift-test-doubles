// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "swift-test-doubles",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v16),
        .visionOS(.v1),
        .watchOS(.v9),
    ],
    products: [
        .library(name: "TestDoubles", targets: ["TestDoubles"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/tevelee/Echo.git",
            revision: "f3a2906ee86916deda3ca3b6b559bf0d0d5e1efc"
        ),
    ],
    targets: [
        .target(
            name: "TestDoubles",
            dependencies: [
                "CTestDoublesTrampoline",
                .product(name: "Echo", package: "Echo"),
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
        .testTarget(
            name: "TestDoublesTests",
            dependencies: ["TestDoubles", "TestDoublesFixtures"]
        ),
    ]
)
