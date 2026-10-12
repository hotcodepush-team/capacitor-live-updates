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
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "8.0.0"),
        .package(url: "https://github.com/hotcodepush-team/core-ios.git", revision: "e6fbe041b7a780730cb5aadc40cce778264cf57e")
    ],
    targets: [
        .target(
            name: "HotCodePushPlugin",
            dependencies: [
                .product(name: "HotCodePushCore", package: "core-ios"),
                .product(name: "Capacitor", package: "capacitor-swift-pm", condition: .when(platforms: [.iOS])),
                .product(name: "Cordova", package: "capacitor-swift-pm", condition: .when(platforms: [.iOS]))
            ],
            path: "ios/Sources/HotCodePushPlugin",
            resources: [.copy("PrivacyInfo.xcprivacy")])
    ]
)
