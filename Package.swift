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
        .package(url: "https://github.com/hotcodepush-team/protocol-ios.git", revision: "dd6236e8bd4b3ada72cec9858489e889c2f981f7")
    ],
    targets: [
        .target(
            name: "HotCodePushPlugin",
            dependencies: [
                .product(name: "HotCodePushProtocol", package: "protocol-ios"),
                .product(name: "Capacitor", package: "capacitor-swift-pm", condition: .when(platforms: [.iOS])),
                .product(name: "Cordova", package: "capacitor-swift-pm", condition: .when(platforms: [.iOS]))
            ],
            path: "ios/Sources/HotCodePushPlugin",
            resources: [.copy("PrivacyInfo.xcprivacy")])
    ]
)
