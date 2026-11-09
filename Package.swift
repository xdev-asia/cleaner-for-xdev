// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CleanerKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "CleanerKit", targets: ["CleanerKit"]),
    ],
    targets: [
        .target(name: "CleanerKit"),
        .testTarget(name: "CleanerKitTests", dependencies: ["CleanerKit"]),
    ]
)
