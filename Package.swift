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
        .package(url: "https://github.com/hotcodepush-team/core-ios.git", revision: "a9a36eac37b40e10f7424f22b50f1815063532e4")
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
