// swift-tools-version: 6.0
import PackageDescription
import Foundation

let coreChecks = ProcessInfo.processInfo.environment["CLASHREMOTE_CORE_CHECKS"] == "1"
var dependencies: [Package.Dependency] = []
var appDependencies: [Target.Dependency] = []
var platformTargets: [Target] = []
#if os(Windows)
if !coreChecks {
if let local = ProcessInfo.processInfo.environment["SWIFTOPENUI_PATH"] {
    dependencies.append(.package(name: "SwiftOpenUI", path: local))
} else {
    dependencies.append(.package(url: "https://github.com/codelynx/SwiftOpenUI.git", revision: "4afcacda74dec9e0bae18403c4427b05c8586943"))
}
appDependencies = [.product(name: "SwiftOpenUI", package: "SwiftOpenUI"), .product(name: "BackendWin32", package: "SwiftOpenUI"), "CWindowsPlatform"]
}
platformTargets.append(.target(name: "CWindowsPlatform", path: "Sources/CWindowsPlatform", publicHeadersPath: "include", linkerSettings: [.linkedLibrary("winhttp"), .linkedLibrary("bcrypt"), .linkedLibrary("shell32"), .linkedLibrary("user32")]))
#endif

#if os(Windows)
let windowsLanguageModes: [SwiftLanguageMode] = [.v5]
#else
let windowsLanguageModes: [SwiftLanguageMode] = [.v6]
#endif

let package = Package(
    name: "ClashRemote", platforms: [.macOS(.v14)], dependencies: dependencies,
    targets: platformTargets + (coreChecks ? [
        .target(name: "ClashRemoteCore", dependencies: ["CWindowsPlatform"], path: "Sources/ClashRemote",
            exclude: ["Views", "Models/AppTheme.swift", "App/ClashRemoteApp.swift", "App/WorkspacePreviewRenderer.swift", "Resources/CatLogo.png", "Resources/CatNetworkIllustration.png", "Resources/node-failover.sh", "Resources/install-on-device.sh", "Resources/ufi-failover-plugin.js"],
            resources: [.copy("Resources/cr-failover.html")]),
        .testTarget(name: "WindowsCoreTests", dependencies: ["ClashRemoteCore"], path: "Tests/WindowsCoreTests")
    ] : [
        .executableTarget(name: "ClashRemote", dependencies: appDependencies, path: "Sources/ClashRemote",
            exclude: ["Resources/node-failover.sh", "Resources/install-on-device.sh", "Resources/ufi-failover-plugin.js"],
            resources: [.copy("Resources/cr-failover.html"), .copy("Resources/CatLogo.png"), .copy("Resources/CatNetworkIllustration.png")]),
        .testTarget(name: "ClashRemoteTests", dependencies: ["ClashRemote"], path: "Tests/ClashRemoteTests")
    ]), swiftLanguageModes: windowsLanguageModes
)
