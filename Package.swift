// swift-tools-version: 6.0
import PackageDescription

// Zuno delivery SDK for iOS apps. It talks to the integrator's own backend,
// which holds the tenant API key and forwards calls to Zuno; see README.md.
//
// macOS is listed alongside iOS purely so `swift test` runs on the host without a
// simulator — nothing here touches UIKit.
let package = Package(
    name: "ZunoSDK",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
    ],
    products: [
        .library(name: "ZunoSDK", targets: ["ZunoSDK"]),
    ],
    targets: [
        .target(name: "ZunoSDK"),
        .testTarget(name: "ZunoSDKTests", dependencies: ["ZunoSDK"]),
    ]
)
