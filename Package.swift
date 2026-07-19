// swift-tools-version:5.9

// Trimmed to the SwiftTerm library product. Upstream also declares executable targets
// (SwiftTermFuzz, Termcast) and benchmark/doc tooling that pull in external package
// dependencies (swift-argument-parser, swift-docc-plugin); Xcode resolves a package
// manifest whole, so a consumer linking only the library still fetches them. The extra
// products and their dependencies are removed here rather than merely left unlinked.
// On an upstream sync, re-apply this trim if the manifest conflicts.

import PackageDescription

let package = Package(
    name: "SwiftTerm",
    platforms: [
        .iOS(.v14),
        .macOS(.v11),
        .tvOS(.v13),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "SwiftTerm",
            targets: ["SwiftTerm"]
        ),
    ],
    targets: [
        .target(
            name: "SwiftTerm",
            path: "Sources/SwiftTerm",
            // Shaders.metal is excluded, not shipped: Xcode sends a package's .metal
            // resources to the Metal compiler even under a copy rule, which requires the
            // Metal Toolchain that a plain (non-Metal) build host may not carry. The Metal
            // renderer is a throwing opt-in (`setUseMetal`, off by default); without the
            // shader resource that call fails cleanly and rendering stays on the default
            // CoreGraphics path.
            exclude: ["Mac/README.md", "Apple/Metal/Shaders.metal"]
        ),
        .testTarget(
            name: "SwiftTermTests",
            dependencies: ["SwiftTerm"],
            path: "Tests/SwiftTermTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
