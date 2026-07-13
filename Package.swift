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
        .trait(name: "DynamicReplacement"),
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
                .target(name: "CTestDoublesTrampoline",
                        condition: .when(traits: ["RuntimeStub"])),
                .product(name: "Echo", package: "Echo",
                         condition: .when(traits: ["RuntimeStub"])),
            ],
            swiftSettings: [
                .define("MANUAL_STUB",   .when(traits: ["ManualStub"])),
                .define("RUNTIME_STUB",  .when(traits: ["RuntimeStub"])),
                .define("COMPILED_STUB", .when(traits: ["CompiledStub"])),
                .define("DYNAMIC_REPLACEMENT", .when(traits: ["DynamicReplacement"])),
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
            dependencies: ["TestDoubles", "TestDoublesFixtures"],
            swiftSettings: [
                .define("MANUAL_STUB",   .when(traits: ["ManualStub"])),
                .define("RUNTIME_STUB",  .when(traits: ["RuntimeStub"])),
                .define("COMPILED_STUB", .when(traits: ["CompiledStub"])),
                .define("DYNAMIC_REPLACEMENT", .when(traits: ["DynamicReplacement"])),
            ]
        ),
    ]
)
