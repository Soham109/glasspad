// swift-tools-version: 6.0
import PackageDescription

// The menu bar app as a SwiftPM executable, so it builds without Xcode.
// scripts/build-mac.sh wraps the binary into build/Glasspad.app.
let package = Package(
    name: "GlasspadMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Glasspad", targets: ["Glasspad"]),
    ],
    dependencies: [
        .package(path: "../../Packages/GlasspadKit"),
        .package(path: "../../Packages/GlasspadMacCore"),
        .package(path: "../../Packages/GlasspadMacros"),
    ],
    targets: [
        .executableTarget(
            name: "Glasspad",
            dependencies: [
                .product(name: "GlasspadKit", package: "GlasspadKit"),
                .product(name: "GlasspadMacCore", package: "GlasspadMacCore"),
                .product(name: "GlasspadMacros", package: "GlasspadMacros"),
            ],
            linkerSettings: [
                .linkedFramework("ServiceManagement"),
                .linkedFramework("CoreImage"),
            ]
        ),
        // Debug-only snapshot harness: draws every screen with fixed fake state, in light and
        // dark, to PNGs in /tmp/gpmac. Skipped unless GLASSPAD_SNAPSHOTS=1 (see the file).
        .testTarget(
            name: "GlasspadMacSnapshots",
            dependencies: [
                "Glasspad",
                .product(name: "GlasspadKit", package: "GlasspadKit"),
                .product(name: "GlasspadMacCore", package: "GlasspadMacCore"),
                .product(name: "GlasspadMacros", package: "GlasspadMacros"),
            ],
            path: "Tests/GlasspadMacSnapshots"
        ),
    ]
)
