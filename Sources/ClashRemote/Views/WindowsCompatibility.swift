#if os(Windows)
import Foundation
import SwiftOpenUI
import CWindowsPlatform

// Narrow bridges for platform APIs; view hierarchies remain in the original Swift files.
extension Font {
    typealias Weight = FontWeight
    typealias Design = FontDesign
    typealias TextStyle = Font
    func monospacedDigit() -> Font {
        if case .custom(let size, let weight, _) = self { return .system(size: size, weight: weight, design: .monospaced) }
        return .system(size: pointSize, design: .monospaced)
    }
}
extension State {
    init(initialValue: Value) { self.init(wrappedValue: initialValue) }
}

struct NSImage {
    let url: URL
    init?(contentsOf url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        self.url = url
    }
}
extension Image { init(nsImage: NSImage) { self.init(filePath: nsImage.url.path) } }

@propertyWrapper
struct AppStorage<Value: RawRepresentable>: AnyStateStorageProvider where Value.RawValue == String {
    @State private var value: Value
    private let key: String
    init(wrappedValue: Value, _ key: String) {
        self.key = key
        self._value = State(initialValue: UserDefaults.standard.string(forKey: key).flatMap(Value.init(rawValue:)) ?? wrappedValue)
    }
    var wrappedValue: Value {
        get { value }
        nonmutating set { value = newValue; UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
    var anyStorage: AnyStateStorage { _value.anyStorage }
    var projectedValue: Binding<Value> { Binding(get: { wrappedValue }, set: { wrappedValue = $0 }) }
}

@MainActor

struct WindowPreferences: View {
    let alwaysOnTop: Bool
    var rememberFrame: Bool? = nil
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onAppear { cr_window_topmost(alwaysOnTop ? 1 : 0) }
            .onChange(of: alwaysOnTop) { _, value in cr_window_topmost(value ? 1 : 0) }
    }
}
#endif

import Foundation
#if canImport(AppKit)
import AppKit
#endif
enum PlatformBrowser {
    static func open(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #elseif os(Windows)
        cr_open_url(url.absoluteString)
        #endif
    }
}

#if os(Windows)
import WinSDK
@MainActor
enum WindowsPreview {
    static func seed(_ state: AppState) {
        let device = RouterDevice(name: "Rax3000M", host: "192.0.2.1", password: "")
        state.devices = [device]; state.selectedID = device.id; state.connectedDeviceID = device.id
        state.snapshot.status.running = true
        state.snapshot.status.hostname = "OpenWrt Router"
        state.snapshot.status.coreType = "Mihomo"
        state.snapshot.status.configPath = "/etc/openclash/config/home.yaml"
        state.snapshot.traffic = TrafficSnapshot(up: "246 KB/s", down: "8.42 MB/s", upTotal: "2.14 GB", downTotal: "18.6 GB", connections: 128, cpu: "3%", mem: "64.2 MB")
        let nodes = [ProxyItem(name: "新加坡 Singapore 01", type: "Shadowsocks", lastDelay: 42), ProxyItem(name: "日本 Tokyo 02", type: "VMess", lastDelay: 78)]
        state.snapshot.groups = [ProxyGroup(name: "节点选择", type: "Selector", now: nodes[0].name, nodes: nodes, selectable: true)]
        for n in 0..<60 {
            let x = Double(n)
            let download = (5.0 + 2.0 * sin(x / 5.0) + sin(x / 2.0)) * 1_000_000.0
            let upload = (0.25 + 0.1 * sin(x / 7.0)) * 1_000_000.0
            state.trafficHistory.append(TrafficSample(date: Date().addingTimeInterval((x-59)*5), download: download, upload: upload))
        }
    }
    static func smoke(section: Binding<WorkspaceSection>, addingDevice: Binding<Bool>) {
        Task { @MainActor in
            var visited: [String] = []
            let path = ProcessInfo.processInfo.environment["CLASHREMOTE_UI_SMOKE_RESULT"] ?? FileManager.default.temporaryDirectory.appendingPathComponent("ClashRemote-openui-smoke.json").path
            func save(_ complete: Bool) {
                let result: [String: Any] = ["completed": complete, "pages": visited]
                if let data = try? JSONSerialization.data(withJSONObject: result) { try? data.write(to: URL(fileURLWithPath: path), options: .atomic) }
            }
            save(false)
            for page in WorkspaceSection.allCases {
                section.wrappedValue = page
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                visited.append(page.rawValue); save(false)
            }
            addingDevice.wrappedValue = true
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            visited.append("设备编辑器"); save(true)
            ExitProcess(0)
        }
    }
}
#endif
