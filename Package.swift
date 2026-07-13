// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "swift-test-doubles",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "TestDoubles", targets: ["TestDoubles"]),
    ],
    traits: [
        .default(enabledTraits: ["ManualStub", "RuntimeStub"]),
        .trait(name: "ManualStub"),
        .trait(name: "RuntimeStub"),
        .trait(name: "CompiledStub", enabledTraits: ["RuntimeStub"]),
    ],
    dependencies: [
        .package(url: "https://github.com/tevelee/Echo.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "TestDoubles",
            dependencies: [
                "CTestDoublesTrampoline",
                .product(name: "Echo", package: "Echo",
                         condition: .when(traits: ["RuntimeStub"])),
            ],
            swiftSettings: [
                .define("MANUAL_STUB",   .when(traits: ["ManualStub"])),
                .define("RUNTIME_STUB",  .when(traits: ["RuntimeStub"])),
                .define("COMPILED_STUB", .when(traits: ["CompiledStub"])),
            ]
        ),
        .target(
            name: "CTestDoublesTrampoline",
            publicHeadersPath: "include"
        ),
        .testTarget(
            name: "TestDoublesTests",
            dependencies: ["TestDoubles"],
            swiftSettings: [
                .define("MANUAL_STUB",   .when(traits: ["ManualStub"])),
                .define("RUNTIME_STUB",  .when(traits: ["RuntimeStub"])),
                .define("COMPILED_STUB", .when(traits: ["CompiledStub"])),
            ]
        ),
    ]
)
