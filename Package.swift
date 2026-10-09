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
        .package(url: "https://github.com/hotcodepush-team/core-ios.git", revision: "55c52d20b1a8ba79dd207042221bf68b0b54a8eb")
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
