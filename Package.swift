// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MultiClip",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "MultiClip",
            path: "Sources/MultiClip",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Network"),
                .linkedFramework("CryptoKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("CoreGraphics")
            ]
        )
    ],
    swiftLanguageVersions: [.v5]
)
