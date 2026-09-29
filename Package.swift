// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HotcodepushCapacitorLiveUpdates",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(
            name: "HotcodepushCapacitorLiveUpdates",
            targets: ["HotCodePushPlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "8.0.0")
    ],
    targets: [
        .target(
            name: "HotCodePushCore",
            path: "ios/Sources/HotCodePushCore"),
        .target(
            name: "HotCodePushPlugin",
            dependencies: [
                "HotCodePushCore",
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm")
            ],
            path: "ios/Sources/HotCodePushPlugin",
            resources: [.copy("PrivacyInfo.xcprivacy")]),
        .testTarget(
            name: "HotCodePushCoreTests",
            dependencies: ["HotCodePushCore"],
            path: "ios/Tests/HotCodePushCoreTests")
    ]
)
