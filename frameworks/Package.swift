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
            name: "NoctilucaWebPEncoder",
            type: .dynamic,
            targets: ["NoctilucaWebPEncoder"]
        ),
        .library(
            name: "NoctilucaWebPDecoder",
            type: .dynamic,
            targets: ["NoctilucaWebPDecoder"]
        ),
    ],
    targets: [
        // Binary Targets
        .binaryTarget(name: "WebP", path: "WebP.xcframework"),
        .binaryTarget(name: "WebPDecoder", path: "WebPDecoder.xcframework"),
        .binaryTarget(name: "SharpYuv", path: "SharpYuv.xcframework"),

        // Wrapper Targets
        .target(
            name: "NoctilucaWebPEncoder",
            dependencies: ["WebP", "SharpYuv"],
            path: "Sources/NoctilucaServerFrameworks",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-all_load"])]
        ),
        .target(
            name: "NoctilucaWebPDecoder",
            dependencies: ["WebPDecoder", "SharpYuv"],
            path: "Sources/NoctilucaClientFrameworks",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-all_load"])]
        ),
    ]
)
