// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "GlasspadMacCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GlasspadMacCore", targets: ["GlasspadMacCore"]),
    ],
    dependencies: [
        .package(path: "../GlasspadKit"),
    ],
    targets: [
        .target(
            name: "GlasspadMacCore",
            dependencies: [.product(name: "GlasspadKit", package: "GlasspadKit")],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("Security"),
            ]
        ),
        .testTarget(
            name: "GlasspadMacCoreTests",
            dependencies: ["GlasspadMacCore"]
        ),
    ]
)
