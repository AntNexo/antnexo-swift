// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AntNexo",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "AntNexo", targets: ["AntNexo"]),
    ],
    targets: [
        // Plain Foundation: builds and tests on Linux too.
        .target(name: "AntNexoCore"),
        // The Apple layer: WebKit sheet, sign-in, screenshot, public API.
        .target(name: "AntNexo", dependencies: ["AntNexoCore"]),
        .testTarget(name: "AntNexoCoreTests", dependencies: ["AntNexoCore"]),
    ]
)
