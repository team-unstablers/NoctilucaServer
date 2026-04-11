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
        .library(
            name: "NoctilucaLibVPX",
            type: .dynamic,
            targets: ["NoctilucaLibVPX"]
        ),
        .library(
            name: "NoctilucaLibVPXDecoder",
            type: .dynamic,
            targets: ["NoctilucaLibVPXDecoder"]
        ),
    ],
    targets: [
        // Binary Targets
        .binaryTarget(name: "WebP", path: "WebP.xcframework"),
        .binaryTarget(name: "WebPDecoder", path: "WebPDecoder.xcframework"),
        .binaryTarget(name: "SharpYuv", path: "SharpYuv.xcframework"),
        
        .binaryTarget(name: "VPX", path: "VPX.xcframework"),
        .binaryTarget(name: "VPXDecoder", path: "VPXDecoder.xcframework"),

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
        
        .target(
            name: "NoctilucaLibVPXShim",
            dependencies: ["VPX"],
            path: "Sources/NoctilucaLibVPXShim",
            publicHeadersPath: "include",
            cSettings: [
                // VPX.xcframework's headers are not automatically exposed to
                // C-language targets via SwiftPM's binaryTarget dependency, so
                // point clang at the `Headers/` directory of the universal
                // macOS slice. `vpx_config.h` dispatches between the arm64
                // and x86_64 variants via `__aarch64__` / `__x86_64__`, so a
                // single include path works for both architectures.
                .headerSearchPath("../../VPX.xcframework/macos-arm64_x86_64/VPX.framework/Versions/A/Headers"),
            ]
        ),
        .target(
            name: "NoctilucaLibVPX",
            dependencies: ["VPX", "NoctilucaLibVPXShim"],
            path: "Sources/NoctilucaLibVPX",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-all_load"])]
        ),
        .target(
            name: "NoctilucaLibVPXDecoderShim",
            dependencies: ["VPXDecoder"],
            path: "Sources/NoctilucaLibVPXDecoderShim",
            publicHeadersPath: "include",
            cSettings: [
                // Mirror of NoctilucaLibVPXShim's approach — SwiftPM does not
                // propagate binaryTarget headers to C targets, so point clang
                // at the universal macOS slice's Headers directory. vpx_config.h
                // dispatches between arm64 and x86_64 via `__aarch64__` /
                // `__x86_64__`, so a single include path covers both archs.
                .headerSearchPath("../../VPXDecoder.xcframework/macos-arm64_x86_64/VPXDecoder.framework/Versions/A/Headers"),
            ]
        ),
        .target(
            name: "NoctilucaLibVPXDecoder",
            dependencies: ["VPXDecoder", "NoctilucaLibVPXDecoderShim"],
            path: "Sources/NoctilucaLibVPXDecoder",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-all_load"])]
        ),
    ]
)
