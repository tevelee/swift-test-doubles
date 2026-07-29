// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "ManualOnlyClient",
    dependencies: [
        .package(path: "../..", traits: [])
    ],
    targets: [
        .testTarget(
            name: "ManualOnlyClientTests",
            dependencies: [
                .product(
                    name: "TestDoubles",
                    package: "swift-test-doubles"
                )
            ]
        )
    ]
)
