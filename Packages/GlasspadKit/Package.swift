// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GlasspadKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GlasspadKit", targets: ["GlasspadKit"]),
    ],
    targets: [
        .target(name: "GlasspadKit"),
        .testTarget(name: "GlasspadKitTests", dependencies: ["GlasspadKit"]),
    ]
)
