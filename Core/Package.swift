// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SnapFlexCore",
    platforms: [.iOS(.v18), .macOS(.v14)],
    targets: [
        .target(name: "SnapFlexCore"),
        .testTarget(name: "SnapFlexCoreTests", dependencies: ["SnapFlexCore"]),
    ]
)
