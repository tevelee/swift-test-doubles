// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "swift-test-doubles",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v16),
        .visionOS(.v1)
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
        .testTarget(
            name: "TestDoublesTests",
            dependencies: [
                "TestDoubles",
                "TestDoublesFixtures",
                "TestDoublesResilientFixtures",
                .product(name: "IssueReportingTestSupport", package: "swift-issue-reporting")
            ]
        )
    ],
    // Tools version 6.3 already defaults to this; pinned explicitly so a
    // future tools-version bump can't silently change the language mode.
    swiftLanguageModes: [.v6]
)
