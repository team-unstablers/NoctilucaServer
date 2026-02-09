// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NoctilucaFrameworks",
    platforms: [
        .macOS(.v14),
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "NoctilucaServerFrameworks",
            type: .dynamic,
            targets: ["NoctilucaServerFrameworks"]
        ),
        .library(
            name: "NoctilucaClientFrameworks",
            type: .dynamic,
            targets: ["NoctilucaClientFrameworks"]
        ),
    ],
    targets: [
        // Binary Targets
        .binaryTarget(name: "WebP", path: "WebP.xcframework"),
        .binaryTarget(name: "WebPDecoder", path: "WebPDecoder.xcframework"),
        .binaryTarget(name: "SharpYuv", path: "SharpYuv.xcframework"),

        // Wrapper Targets
        .target(
            name: "NoctilucaServerFrameworks",
            dependencies: ["WebP", "SharpYuv"],
            path: "Sources/NoctilucaServerFrameworks",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-all_load"])]
        ),
        .target(
            name: "NoctilucaClientFrameworks",
            dependencies: ["WebPDecoder", "SharpYuv"],
            path: "Sources/NoctilucaClientFrameworks",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-all_load"])]
        ),
    ]
)
