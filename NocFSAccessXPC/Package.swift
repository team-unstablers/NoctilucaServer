// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NocFSAccessXPC",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "NocFSAccessXPC",
            targets: ["NocFSAccessXPC"]
        ),
    ],
    targets: [
        .target(
            name: "NocFSAccessXPC",
            path: "Sources/NocFSAccessXPC"
        ),
    ],
    swiftLanguageModes: [.v6]
)
