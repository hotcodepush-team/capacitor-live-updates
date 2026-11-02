// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HotcodepushCapacitorLiveUpdates",
    platforms: [.iOS(.v15)],
    products: [
        .library(
            name: "HotcodepushCapacitorLiveUpdates",
            targets: ["HotCodePushPlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "8.0.0")
    ],
    targets: [
        .binaryTarget(
            name: "HotCodePushCore",
            url: "https://github.com/hotcodepush-team/core-ios/releases/download/0.4.0/HotCodePushCore.xcframework.zip",
            checksum: "0ac3338f1f8e0e2c4c79cf5cb00d70a078fd25a17e2586fc7ff1edee7166d941"),
        .target(
            name: "HotCodePushPlugin",
            dependencies: [
                "HotCodePushCore",
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm")
            ],
            path: "ios/Sources/HotCodePushPlugin",
            resources: [.copy("PrivacyInfo.xcprivacy")])
    ]
)
