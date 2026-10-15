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
    ],
    targets: [
        .executableTarget(
            name: "Glasspad",
            dependencies: [
                .product(name: "GlasspadKit", package: "GlasspadKit"),
                .product(name: "GlasspadMacCore", package: "GlasspadMacCore"),
            ],
            linkerSettings: [
                .linkedFramework("ServiceManagement"),
                .linkedFramework("CoreImage"),
            ]
        ),
    ]
)
