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
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "8.0.0"),
        .package(url: "https://github.com/hotcodepush-team/core-ios.git", revision: "eef5dd0391ae5ffc399ce8c99004b748f6f63283")
    ],
    targets: [
        .target(
            name: "HotCodePushPlugin",
            dependencies: [
                .product(name: "HotCodePushCore", package: "core-ios"),
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm")
            ],
            path: "ios/Sources/HotCodePushPlugin",
            resources: [.copy("PrivacyInfo.xcprivacy")])
    ]
)
