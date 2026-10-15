// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GlasspadMacros",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GlasspadMacros", targets: ["GlasspadMacros"]),
    ],
    targets: [
        .target(
            name: "GlasspadMacros",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("UserNotifications"),
            ]
        ),
        .testTarget(
            name: "GlasspadMacrosTests",
            dependencies: ["GlasspadMacros"]
        ),
    ]
)
