import Foundation
import Observation
import SwiftCrossUI
import DefaultBackend
import CWindowsPlatform
import WinSDK

@main
struct ClashRemoteWindowsApp: App {
    @State private var ui = WindowsSession()
    var body: some Scene {
        WindowGroup("Clash Remote") { WorkspaceView(ui: ui) }.defaultSize(width: 1240, height: 840)
    }
}

enum WorkspacePage: String, CaseIterable {
    case overview = "总览", nodes = "节点", subscriptions = "订阅", rules = "规则"
    case control = "设备控制", profile = "本地配置", settings = "设置", devices = "路由器"
    var icon: String {
        switch self {
        case .overview: "▦"
        case .nodes: "◇"
        case .subscriptions: "▤"
        case .rules: "⑂"
        case .control: "▣"
        case .profile: "☷"
        case .settings: "⚙"
        case .devices: "+"
        }
    }
}

@Observable @MainActor
final class WindowsSession {
    let state: AppState
    let preferences: AppPreferences
    let demo: Bool
    var page: WorkspacePage = .overview
    var theme = "mintCat"
    var started = false
    var editingDevice: RouterDevice?
    init() {
        demo = CommandLine.arguments.contains("--demo") || CommandLine.arguments.contains("--ui-smoke-test")
        let defaults = demo ? UserDefaults(suiteName: "ClashRemote.Demo")! : .standard
        preferences = AppPreferences(defaults: defaults)
        state = AppState(preferences: preferences, loadStoredData: !demo)
        theme = defaults.string(forKey: "appearance.theme") ?? "mintCat"
        if demo { seedPreview() }
    }
    var available: Bool { !demo && state.isConnected && !state.isBusy && !state.isConnecting }
    var background: Color { color(theme == "graphite" ? 0x171e26 : 0xf0f6f2) }
    var sidebar: Color { color(theme == "graphite" ? 0x202a34 : 0xe6f0e9) }
    var card: Color { color(theme == "graphite" ? 0x26333e : 0xfffffc) }
    var ink: Color { color(theme == "graphite" ? 0xe0f0ea : 0x203e37) }
    var muted: Color { color(theme == "graphite" ? 0xa1b6bd : 0x7c958d) }
    var accent: Color { color(["mintCat": 0x238c73, "aqua": 0x247caa, "graphite": 0x74c7ac, "lavender": 0x8a6bb2, "sand": 0xad7d39][theme] ?? 0x238c73) }
    var spacing: Int { preferences.density == .compact ? 12 : 18 }
    func color(_ hex: Int) -> Color { Color(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255) }
    func go(_ page: WorkspacePage) { self.page = page; if !demo { preferences.lastSection = page.rawValue } }
    func begin() async {
        guard !started else { return }; started = true
        if demo {
            if CommandLine.arguments.contains("--ui-smoke-test") {
                var visited: [String] = []
                let resultPath = ProcessInfo.processInfo.environment["CLASHREMOTE_UI_SMOKE_RESULT"]
                    ?? FileManager.default.temporaryDirectory.appendingPathComponent("ClashRemote-ui-smoke.json").path
                for next in WorkspacePage.allCases {
                    page = next
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    visited.append(next.rawValue)
                    let progress: [String: Any] = ["completed": false, "pages": visited]
                    if let data = try? JSONSerialization.data(withJSONObject: progress) {
                        try? data.write(to: URL(fileURLWithPath: resultPath), options: .atomic)
                    }
                }
                let result: [String: Any] = ["completed": true, "pages": visited]
                if let data = try? JSONSerialization.data(withJSONObject: result) {
                    try? data.write(to: URL(fileURLWithPath: resultPath), options: .atomic)
                }
                ExitProcess(0)
            }
            return
        }
        if preferences.startupPage == .nodes { page = .nodes }
        if preferences.startupPage == .lastUsed { page = WorkspacePage(rawValue: preferences.lastSection) ?? .overview }
        if preferences.autoConnect { await state.connect() }
    }
    func saveTheme(_ value: String) { theme = value; if !demo { UserDefaults.standard.set(value, forKey: "appearance.theme") } }
    func open(_ url: URL) { cr_open_url(url.absoluteString) }
    func seedPreview() {
        let device = RouterDevice(name: "Rax3000M", host: "192.0.2.1", password: "")
        state.devices = [device]; state.selectedID = device.id; state.connectedDeviceID = device.id
        state.snapshot.status.running = true; state.snapshot.status.hostname = "OpenWrt Router"
        state.snapshot.status.coreType = "Mihomo"; state.snapshot.status.configPath = "/etc/openclash/config/home.yaml"
        state.snapshot.traffic = TrafficSnapshot(up: "246 KB/s", down: "8.42 MB/s", upTotal: "2.14 GB", downTotal: "18.6 GB", connections: 128, cpu: "3%", mem: "64.2 MB")
        let nodes = [ProxyItem(name: "新加坡 · Singapore 01", type: "Shadowsocks", lastDelay: 42), ProxyItem(name: "日本 · Tokyo 02", type: "VMess", lastDelay: 78), ProxyItem(name: "台湾 · Taipei 01", type: "Trojan", lastDelay: 56)]
        state.snapshot.groups = [ProxyGroup(name: "节点选择", type: "Selector", now: nodes[0].name, nodes: nodes, selectable: true)]
        state.snapshot.rules = [ClashRule(type: "DOMAIN-SUFFIX", payload: "example.com", proxy: "DIRECT"), ClashRule(type: "MATCH", payload: "", proxy: "节点选择")]
        for n in 0..<60 {
            let x = Double(n)
            let down = (5.0 + 2.0 * sin(x / 5.0) + sin(x / 2.0)) * 1_000_000.0
            let up = (0.25 + 0.1 * sin(x / 7.0)) * 1_000_000.0
            let date = Date().addingTimeInterval((x - 59.0) * 5.0)
            state.trafficHistory.append(TrafficSample(date: date, download: down, upload: up))
        }
    }
}

struct WorkspaceView: View {
    let ui: WindowsSession
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            sidebar
            ScrollView {
                VStack(alignment: .leading, spacing: ui.spacing) {
                    HStack {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(ui.page.rawValue).font(.system(size: 27).weight(.bold))
                            Text(ui.state.selectedDevice.map { $0.displayAddress + "  ·  " + $0.plugin.title } ?? "添加路由器，开始管理局域网代理").foregroundColor(ui.muted).font(.system(size: 12))
                        }
                        Spacer()
                        Button(ui.state.isConnected ? "刷新" : "连接") {
                            Task { if ui.state.isConnected { await ui.state.refresh(full: true) } else { await ui.state.connect() } }
                        }.disabled(ui.demo || ui.state.selectedDevice == nil || ui.state.isConnecting || ui.state.isBusy)
                    }.padding(.bottom, 8)
                    if ui.demo { Text("界面预览 · 示例数据 · 设备操作已停用").foregroundColor(ui.accent) }
                    if let error = ui.state.lastError { Text(error).foregroundColor(.red) }
                    if let notice = ui.state.notice { Text(notice.text).foregroundColor(ui.muted) }
                    page
                }.padding(24).frame(maxWidth: .infinity, alignment: .topLeading)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.background(ui.background).foregroundColor(ui.ink)
        .font(.system(size: 14 * Double(ui.preferences.textSize.scale)))
        .task { await ui.begin() }
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                if let url = Bundle.module.url(forResource: "CatLogo", withExtension: "png") { Image(url).resizable().frame(width: 38, height: 38).cornerRadius(9) }
                Text("Clash Remote").fontWeight(.bold)
            }.padding(.bottom, 20)
            ForEach(WorkspacePage.allCases.filter { $0 != .devices }, id: \.rawValue) { item in
                Button(action: { ui.go(item) }) {
                    HStack(spacing: 14) { Text(item.icon).frame(width: 20); Text(item.rawValue); Spacer() }
                        .padding(10).frame(width: 196).background(ui.page == item ? ui.card : ui.sidebar).cornerRadius(10)
                }.buttonStyle(.plain)
            }
            HStack { Text("路由器").foregroundColor(ui.muted); Spacer(); Button("+") { ui.editingDevice = nil; ui.go(.devices) }.disabled(ui.demo) }.padding(.top, 20)
            ForEach(ui.state.devices, id: \.id) { device in
                Button(action: { if !ui.demo { ui.state.select(device.id) } }) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("▣  " + device.name).fontWeight(.semibold)
                        if ui.preferences.showDeviceAddress { Text(device.plugin.title + " · " + device.displayAddress).font(.system(size: 11)).foregroundColor(ui.muted) }
                    }.padding(10).frame(width: 196, alignment: .leading).background(ui.state.selectedID == device.id ? ui.card : ui.sidebar).cornerRadius(12)
                }.buttonStyle(.plain)
            }
            Spacer()
            Text(ui.state.isConnecting ? "◌  正在连接…" : ui.state.isConnected ? "●  设备已连接" : "○  设备未连接").font(.system(size: 12)).foregroundColor(ui.state.isConnected ? ui.accent : ui.muted)
            Button("管理设备") { ui.go(.devices) }.disabled(ui.demo)
        }.padding(16).frame(width: 250).frame(maxHeight: .infinity, alignment: .topLeading).background(ui.sidebar)
    }
    @ViewBuilder var page: some View {
        switch ui.page {
        case .overview: OverviewPage(ui: ui)
        case .nodes: NodesPage(ui: ui)
        case .subscriptions: SubscriptionsPage(ui: ui)
        case .rules: RulesPage(ui: ui)
        case .control: ControlPage(ui: ui)
        case .profile: ProfilePage(ui: ui)
        case .settings: PreferencesPage(ui: ui)
        case .devices: DevicesPage(ui: ui)
        }
    }
}

struct Panel<Content: View>: View {
    let ui: WindowsSession
    let title: String
    let content: Content
    init(_ title: String, ui: WindowsSession, @ViewBuilder content: () -> Content) { self.title = title; self.ui = ui; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: ui.spacing) { if !title.isEmpty { Text(title).fontWeight(.semibold) }; content }
            .padding(18).frame(maxWidth: .infinity, alignment: .topLeading).background(ui.card).cornerRadius(14)
    }
}
struct Metric: View {
    let title: String; let value: String; let detail: String; let ui: WindowsSession
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12)).foregroundColor(ui.muted)
            Text(value.isEmpty ? "—" : value).font(.system(size: 23).weight(.semibold))
            Text(detail).font(.system(size: 11)).foregroundColor(ui.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct OverviewPage: View {
    let ui: WindowsSession
    var state: AppState { ui.state }
    var body: some View {
        VStack(spacing: ui.spacing) {
            HStack(alignment: .top, spacing: ui.spacing) {
                Panel("当前代理", ui: ui) {
                    Text(state.activeNode?.leafName ?? "等待连接").font(.system(size: 21).weight(.semibold))
                    Text(state.snapshot.status.running ? "●  代理运行中" : "○  代理未启动").foregroundColor(ui.accent)
                    if let url = Bundle.module.url(forResource: "CatNetworkIllustration", withExtension: "png") { Image(url).resizable().frame(height: 130) }
                    Text("本机  ─────  " + (state.selectedDevice?.name ?? "路由器") + "  ─────  节点").font(.system(size: 12)).foregroundColor(ui.muted)
                    HStack { Button(state.snapshot.status.running ? "停止代理" : "启动代理") { state.setRunning(!state.snapshot.status.running) }.disabled(!ui.available); Button("切换节点") { ui.go(.nodes) } }
                }
                Panel("流量趋势 · 最近 5 分钟", ui: ui) {
                    HStack { Text("↓ " + (state.snapshot.traffic.down.isEmpty ? "—" : state.snapshot.traffic.down)).foregroundColor(ui.accent); Text("↑ " + (state.snapshot.traffic.up.isEmpty ? "—" : state.snapshot.traffic.up)).foregroundColor(ui.color(0xae7d32)) }.font(.system(size: 12))
                    if state.trafficHistory.count > 1 { TrafficPlot(samples: state.trafficHistory, ui: ui).frame(height: 210) }
                    else { Text("连接后显示实时流量").foregroundColor(ui.muted).frame(height: 210) }
                }
            }
            Panel("", ui: ui) {
                HStack(spacing: 20) {
                    Metric(title: "↓ 下载速率", value: state.snapshot.traffic.down, detail: "累计 " + state.snapshot.traffic.downTotal, ui: ui)
                    Metric(title: "↑ 上传速率", value: state.snapshot.traffic.up, detail: "累计 " + state.snapshot.traffic.upTotal, ui: ui)
                    Metric(title: "活动连接", value: String(state.snapshot.traffic.connections), detail: "当前设备", ui: ui)
                    Metric(title: "核心内存", value: state.snapshot.traffic.mem, detail: state.snapshot.status.coreType, ui: ui)
                }
            }
            HStack(alignment: .top, spacing: ui.spacing) {
                ModePanel(ui: ui)
                Panel("设备守护", ui: ui) {
                    Text(state.deviceFailover.running ? "●  设备守护运行中" : "设备守护未运行")
                    Text(state.deviceFailover.installed ? "每 \(state.deviceFailover.interval) 秒检测" : "可在设备控制中安装和管理").foregroundColor(ui.muted)
                    Button("管理守护") { ui.go(.control) }
                }
            }
            HStack { Button("订阅  ·  \(state.snapshot.subscriptions.count) 个来源") { ui.go(.subscriptions) }; Button("分流规则  ·  \(state.snapshot.rules.count) 条") { ui.go(.rules) }; Button("本地配置  ·  筛选与自动切换") { ui.go(.profile) } }
        }
    }
}
struct ModePanel: View {
    let ui: WindowsSession
    var body: some View {
        Panel("代理模式", ui: ui) {
            HStack(spacing: 10) {
                ForEach(RuleMode.allCases, id: \.rawValue) { mode in
                    Button(action: { ui.state.setRuleMode(mode) }) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text((ui.state.snapshot.status.ruleMode == mode ? "●  " : "○  ") + mode.title).fontWeight(.semibold)
                            Text(mode.hint).font(.system(size: 11)).foregroundColor(ui.muted)
                        }.padding(12).frame(width: 124, alignment: .leading).background(ui.background).cornerRadius(10)
                    }.buttonStyle(.plain).disabled(!ui.available)
                }
            }
        }
    }
}
struct TrafficPlot: View {
    let samples: [TrafficSample]; let ui: WindowsSession
    var peak: Double { max(1, samples.map { max($0.upload, $0.download) }.max() ?? 1) * 1.1 }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(TrafficRate.format(peak)).font(.system(size: 10)).foregroundColor(ui.muted)
            ZStack {
                TrafficLine(values: samples.map(\.download), ceiling: peak, area: true).fill(ui.accent.opacity(0.13))
                TrafficLine(values: samples.map(\.download), ceiling: peak).stroke(ui.accent, style: StrokeStyle(width: 2))
                TrafficLine(values: samples.map(\.upload), ceiling: peak).stroke(ui.color(0xae7d32), style: StrokeStyle(width: 1.5))
            }
            HStack { Text(samples.first?.date.formatted(date: .omitted, time: .shortened) ?? ""); Spacer(); Text(samples.last?.date.formatted(date: .omitted, time: .shortened) ?? "") }.font(.system(size: 10)).foregroundColor(ui.muted)
        }
    }
}
struct TrafficLine: Shape {
    let values: [Double]; let ceiling: Double; var area = false
    func path(in bounds: Path.Rect) -> Path {
        guard values.count > 1 else { return Path() }
        var result = Path()
        for (index, value) in values.enumerated() {
            let point = SIMD2<Double>(bounds.x + bounds.width * Double(index) / Double(values.count - 1), bounds.y + bounds.height * (1 - max(0, value) / ceiling))
            result = index == 0 ? result.move(to: point) : result.addLine(to: point)
        }
        if area { result = result.addLine(to: SIMD2(bounds.x + bounds.width, bounds.y + bounds.height)).addLine(to: SIMD2(bounds.x, bounds.y + bounds.height)).addLine(to: SIMD2(bounds.x, bounds.y + bounds.height * (1 - values[0] / ceiling))) }
        return result
    }
}
