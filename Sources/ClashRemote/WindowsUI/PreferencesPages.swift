import Foundation
import SwiftCrossUI
import CWindowsPlatform

struct ProfilePage: View {
    let ui: WindowsSession
    @State private var keywords = ""
    @State private var whitelist = ""
    @State private var threshold = "180"
    @State private var subName = ""
    @State private var subURL = ""
    @State private var saved = ""
    @State private var clearConfirmed = false
    var body: some View {
        VStack(spacing: ui.spacing) {
            Panel("节点筛选", ui: ui) {
                Text("排除关键词（每行一个）").foregroundColor(ui.muted)
                TextEditor(text: $keywords).frame(height: 110)
                HStack {
                    ForEach(RegionExclusion.allCases, id: \.rawValue) { region in
                        Toggle(region.label, isOn: Binding(get: { ui.state.profile.regionExclusions.contains(region) }, set: { if $0 { ui.state.profile.regionExclusions.insert(region) } else { ui.state.profile.regionExclusions.remove(region) }; ui.state.persistProfile() }))
                    }
                }
                Toggle("启用订阅来源白名单", isOn: Binding(get: { ui.state.profile.providerWhitelistEnabled }, set: { ui.state.profile.providerWhitelistEnabled = $0; ui.state.persistProfile() }))
                TextField("来源关键词，以逗号分隔", text: $whitelist)
                HStack { Text("自动切换延迟阈值（ms）"); TextField("180", text: $threshold).frame(width: 100) }
                Choice("客户端检测间隔（秒）", AppState.failoverIntervals.map(String.init), value: Binding(get: { String(ui.state.autoFailoverInterval) }, set: { if let n = Int($0) { ui.state.autoFailoverInterval = n } }))
                HStack { Button("保存本地配置") { save() }; Button("同步筛选到设备") { save(); if saved == "已保存" { ui.state.syncFilterToRouter() } }.disabled(!ui.available) }
                if !saved.isEmpty { Text(saved).foregroundColor(ui.muted) }
            }.disabled(ui.demo)
            Panel("屏蔽列表", ui: ui) {
                ForEach(ui.state.profile.blockedNodes, id: \.self) { name in HStack { Text(name); Spacer(); Button("解除") { ui.state.unblockNode(name) }.disabled(ui.demo) } }
                ForEach(ui.state.profile.blockedKeywords, id: \.self) { keyword in HStack { Text("关键词：" + keyword); Spacer(); Button("解除") { ui.state.unblockKeyword(keyword) }.disabled(ui.demo) } }
                if ui.state.blockedCount == 0 { Text("暂无屏蔽项").foregroundColor(ui.muted) }
                Button(clearConfirmed ? "确认清空屏蔽列表" : "清空屏蔽列表") { if clearConfirmed { ui.state.clearBlocklist(); clearConfirmed = false } else { clearConfirmed = true } }.disabled(ui.demo || ui.state.blockedCount == 0)
            }
            Panel("本地订阅收藏", ui: ui) {
                ForEach(ui.state.profile.subscriptions, id: \.id) { sub in
                    HStack {
                        Toggle(sub.name, isOn: Binding(get: { ui.state.profile.subscriptions.first { $0.id == sub.id }?.enabled ?? false }, set: { value in if let i = ui.state.profile.subscriptions.firstIndex(where: { $0.id == sub.id }) { ui.state.profile.subscriptions[i].enabled = value; ui.state.persistProfile() } }))
                        Spacer(); Button("移除收藏") { ui.state.profile.subscriptions.removeAll { $0.id == sub.id }; ui.state.persistProfile() }
                    }
                }
                HStack { TextField("名称", text: $subName); TextField("https:// 订阅地址", text: $subURL); Button("收藏") { addSubscription() } }
                Button("同步订阅到当前设备") { ui.state.syncSubscriptionsToRouter() }.disabled(!ui.available)
            }.disabled(ui.demo)
            Panel("本地域名规则", ui: ui) {
                Text("在“规则”页面添加收藏，在此按需同步。").foregroundColor(ui.muted)
                ForEach(ui.state.profile.domainRules, id: \.id) { rule in HStack { Text(rule.ruleLine); Spacer(); Button("移除收藏") { ui.state.profile.domainRules.removeAll { $0.id == rule.id }; ui.state.persistProfile() } } }
                Button("同步域名规则到全部已保存设备") { ui.state.syncDomainRulesToAllRouters() }.disabled(ui.state.devices.isEmpty || ui.state.isBusy)
            }.disabled(ui.demo)
        }.onAppear { keywords = ui.state.profile.filterKeywords.joined(separator: "\n"); whitelist = ui.state.profile.providerWhitelist.joined(separator: ", "); threshold = String(ui.state.profile.failoverThreshold) }
    }
    func save() {
        guard let ms = Int(threshold), (0...60000).contains(ms) else { saved = "延迟阈值须为 0–60000 ms"; return }
        ui.state.profile.filterKeywords = keywords.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        ui.state.profile.providerWhitelist = whitelist.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        ui.state.profile.failoverThreshold = ms; ui.state.persistProfile(); saved = "已保存"
    }
    func addSubscription() {
        guard !subName.isEmpty, let url = URL(string: subURL), ["http", "https"].contains(url.scheme ?? ""), url.host != nil else { saved = "请填写收藏名称与有效的订阅地址"; return }
        ui.state.profile.subscriptions.append(LocalSubscription(name: subName, url: subURL)); ui.state.persistProfile(); subName = ""; subURL = ""
    }
}

struct PreferencesPage: View {
    let ui: WindowsSession
    var body: some View {
        VStack(spacing: ui.spacing) {
            Panel("外观", ui: ui) {
                Choice("主题", ["薄荷猫", "水蓝", "深石墨", "薰衣草", "暖沙"], value: Binding(get: { themeLabels[ui.theme] ?? "薄荷猫" }, set: { title in ui.saveTheme(themeLabels.first { $0.value == title }?.key ?? "mintCat") }))
                Choice("文字大小", AppTextSize.allCases.map(\.title), value: Binding(get: { ui.preferences.textSize.title }, set: { title in if let size = AppTextSize.allCases.first(where: { $0.title == title }) { ui.preferences.textSize = size } }))
                Choice("界面密度", InterfaceDensity.allCases.map(\.title), value: Binding(get: { ui.preferences.density.title }, set: { title in if let density = InterfaceDensity.allCases.first(where: { $0.title == title }) { ui.preferences.density = density } }))
                Toggle("显示设备地址", isOn: Binding(get: { ui.preferences.showDeviceAddress }, set: { ui.preferences.showDeviceAddress = $0 }))
                Toggle("显示节点协议", isOn: Binding(get: { ui.preferences.showNodeProtocol }, set: { ui.preferences.showNodeProtocol = $0 }))
            }
            Panel("启动与刷新", ui: ui) {
                Toggle("启动时自动连接", isOn: Binding(get: { ui.preferences.autoConnect }, set: { ui.preferences.autoConnect = $0 }))
                Choice("启动页面", StartupPage.allCases.map(\.title), value: Binding(get: { ui.preferences.startupPage.title }, set: { title in if let page = StartupPage.allCases.first(where: { $0.title == title }) { ui.preferences.startupPage = page } }))
                Choice("数据刷新", RefreshInterval.allCases.map(\.title), value: Binding(get: { ui.preferences.refreshInterval.title }, set: { title in if let interval = RefreshInterval.allCases.first(where: { $0.title == title }) { ui.preferences.refreshInterval = interval; ui.state.updatePollingFrequency() } }))
                Toggle("窗口置顶", isOn: Binding(get: { ui.preferences.alwaysOnTop }, set: { ui.preferences.alwaysOnTop = $0; cr_window_topmost($0 ? 1 : 0) }))
                Button("恢复默认设置") { ui.preferences.reset(); ui.state.updatePollingFrequency(); cr_window_topmost(0) }
            }.disabled(ui.demo)
            Panel("Clash Remote · Windows", ui: ui) {
                Text("SwiftCrossUI / WinUI 3").fontWeight(.semibold)
                Text("原生 Swift 业务逻辑 · OpenClash / 猫猫 · 局域网直连").foregroundColor(ui.muted)
                Button("打开项目仓库") { ui.open(URL(string: "https://github.com/DrADCalcium/ClashRemote")!) }
            }
        }
    }
    var themeLabels: [String: String] { ["mintCat": "薄荷猫", "aqua": "水蓝", "graphite": "深石墨", "lavender": "薰衣草", "sand": "暖沙"] }
}
