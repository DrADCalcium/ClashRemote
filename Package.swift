// swift-tools-version: 6.0
import PackageDescription
import Foundation

#if os(Windows)
let package = Package(
    name: "ClashRemote",
    products: [.executable(name: "ClashRemote", targets: ["ClashRemote"])],
    dependencies: [
        .package(url: "https://github.com/moreSwift/swift-cross-ui.git", revision: "0f3ec3958b79cdc39a1a3e604516b71ab33a9043")
    ],
    targets: [
        .target(name: "CWindowsPlatform", path: "Sources/CWindowsPlatform", publicHeadersPath: "include",
            linkerSettings: [.linkedLibrary("winhttp"), .linkedLibrary("bcrypt"), .linkedLibrary("shell32"), .linkedLibrary("user32")]),
        .executableTarget(name: "ClashRemote", dependencies: ["CWindowsPlatform", .product(name: "SwiftCrossUI", package: "swift-cross-ui"), .product(name: "DefaultBackend", package: "swift-cross-ui")], path: "Sources/ClashRemote",
            exclude: ["Views", "Models/AppTheme.swift", "App/ClashRemoteApp.swift", "App/WorkspacePreviewRenderer.swift", "Resources/node-failover.sh", "Resources/install-on-device.sh", "Resources/ufi-failover-plugin.js"],
            resources: [.copy("Resources/cr-failover.html"), .copy("Resources/CatLogo.png"), .copy("Resources/CatNetworkIllustration.png")]),
        .testTarget(name: "WindowsCoreTests", dependencies: ["ClashRemote"], path: "Tests/WindowsCoreTests")
    ], swiftLanguageModes: [.v5]
)

#else

let package = Package(
    name: "ClashRemote",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "ClashRemote",
            path: "Sources/ClashRemote",
            exclude: [
                "WindowsUI",
                "Resources/node-failover.sh",
                "Resources/install-on-device.sh",
                "Resources/ufi-failover-plugin.js"
            ],
            resources: [
                .copy("Resources/cr-failover.html"),
                .copy("Resources/CatLogo.png"),
                .copy("Resources/CatNetworkIllustration.png")
            ]
        ),
        .testTarget(
            name: "ClashRemoteTests",
            dependencies: ["ClashRemote"]
        )
    ]
)

#endif
