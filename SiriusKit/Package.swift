// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SiriusKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "SiriusKit",
            targets: ["SiriusKit"]
        ),
        .library(
            name: "SiriusKitClient",
            targets: ["SiriusKitClient"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.33.3"),
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.15.1"),
        .package(url: "https://github.com/apple/swift-asn1.git", from: "1.5.1"),
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.3.0"),
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.63.2"),
    ],
    targets: [
        .target(
            name: "SiriusKitCore",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "SwiftASN1", package: "swift-asn1"),
                .product(name: "Atomics", package: "swift-atomics"),
            ],
            path: "Sources/SiriusKitCore",
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins"),
            ]
        ),
        .target(
            name: "SiriusKit",
            dependencies: [
                "SiriusKitCore",
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "SwiftASN1", package: "swift-asn1"),
                .product(name: "Atomics", package: "swift-atomics"),
            ],
            path: "Sources/SiriusKit",
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins"),
            ]
        ),
        .target(
            name: "SiriusKitClient",
            dependencies: [
                "SiriusKitCore",
                .product(name: "Atomics", package: "swift-atomics"),
            ],
            path: "Sources/SiriusKitClient",
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins"),
            ]
        ),
        .testTarget(
            name: "SiriusKitTests",
            dependencies: ["SiriusKit"]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
