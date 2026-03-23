// swift-tools-version: 6.0

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "swift-test-doubles",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "TestDoubles", targets: ["TestDoubles"]),
    ],
    dependencies: [
        .package(name: "Echo", path: "../echo-spike"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
    ],
    targets: [
        // Runtime library — depends on Echo for existential container manipulation
        .target(
            name: "TestDoubles",
            dependencies: ["Echo", "TestDoublesMacros"]
        ),

        // Macro plugin — generates @convention(thin) witness thunks
        .macro(
            name: "TestDoublesMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),

        // Tests
        .testTarget(
            name: "TestDoublesTests",
            dependencies: ["TestDoubles", "Echo"]
        ),
    ]
)
