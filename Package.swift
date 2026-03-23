// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "swift-test-doubles",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "TestDoubles", targets: ["TestDoubles"]),
    ],
    dependencies: [
        .package(url: "https://github.com/tevelee/Echo.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "TestDoubles",
            dependencies: ["Echo"]
        ),
        .testTarget(
            name: "TestDoublesTests",
            dependencies: ["TestDoubles"]
        ),
    ]
)
