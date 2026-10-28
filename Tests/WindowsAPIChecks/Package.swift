// swift-tools-version: 6.0
import PackageDescription
import Foundation
let dependency = ProcessInfo.processInfo.environment["SWIFTOPENUI_PATH"] ?? "../../.build/SwiftOpenUI-pinned"
let package = Package(name: "WindowsAPIChecks", dependencies: [.package(name: "SwiftOpenUI", path: dependency)], targets: [
    .testTarget(name: "WindowsDesktopAPITests", dependencies: [.product(name: "SwiftOpenUI", package: "SwiftOpenUI"), .product(name: "BackendWin32", package: "SwiftOpenUI"), .product(name: "CDesktopCompatibility", package: "SwiftOpenUI")], path: "Tests")
], swiftLanguageModes: [.v5])
