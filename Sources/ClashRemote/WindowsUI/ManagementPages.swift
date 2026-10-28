import Foundation
import SwiftCrossUI

struct Choice: View {
    let title: String; let options: [String]; let value: Binding<String>
    init(_ title: String, _ options: [String], value: Binding<String>) { self.title = title; self.options = options; self.value = value }
    var body: some View {
        HStack { Text(title); Spacer(); Picker(of: options, selection: Binding<String?>(get: { value.wrappedValue }, set: { if let next = $0 { value.wrappedValue = next } })).frame(width: 200) }
    }
}

struct DevicesPage: View {
    let ui: WindowsSession
    @State private var name = ""
    @State private var host = ""
    @State private var port = "80"
    @State private var username = "root"
    @State private var password = ""
    @State private var https = false
    @State private var plugin = "OpenClash"
    @State private var error = ""
    @State private var deleting: UUID?
    var body: some View {
        VStack(spacing: ui.spacing) {
            Panel("已保存的设备", ui: ui) {
                if ui.state.devices.isEmpty { Text("还没有设备，请在下方添加。").foregroundColor(ui.muted) }
                ForEach(ui.state.devices, id: \.id) { device in
                    HStack {
                        VStack(alignment: .leading) { Text(device.name).fontWeight(.semibold); Text(device.displayAddress + " · " + device.plugin.title).foregroundColor(ui.muted) }
                        Spacer()
                        Button("连接") { ui.state.select(device.id) }
                        Button("编辑") { ui.editingDevice = device; load(device) }
                        Button(deleting == device.id ? "确认删除" : "删除") { if deleting == device.id { ui.state.deleteDevice(device.id); deleting = nil } else { deleting = device.id } }
                    }
                }
            }
            Panel(ui.editingDevice == nil ? "添加路由器" : "编辑路由器", ui: ui) {
                TextField("设备名称", text: $name)
                HStack { TextField("路由器 IP 或主机名", text: $host); TextField("端口", text: $port).frame(width: 100) }
                Choice("插件", ["OpenClash", "猫猫"], value: $plugin)
                Toggle("使用 HTTPS", isOn: $https)
                TextField("用户名", text: $username)
                SecureField("密码", text: $password)
                if !error.isEmpty { Text(error).foregroundColor(.red) }
                HStack {
                    Button("保存并连接") { save() }
                    Button("清空 / 新建设备") { ui.editingDevice = nil; name = ""; host = ""; port = "80"; username = "root"; password = ""; error = "" }
                }
            }
        }.disabled(ui.demo || ui.state.isBusy)
    }
    func load(_ d: RouterDevice) { name = d.name; host = d.host; port = String(d.port); username = d.username; password = d.password; https = d.useHTTPS; plugin = d.plugin.title; error = "" }
    func save() {
        let address = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !address.isEmpty,
              !address.contains("://"), !address.contains("/"), !address.contains(" "),
              let number = Int(port), (1...65535).contains(number) else { error = "请填写名称、纯 IP / 主机名，以及 1–65535 的端口。"; return }
        let d = RouterDevice(id: ui.editingDevice?.id ?? UUID(), name: name, host: address, port: number, useHTTPS: https, username: username, password: password, plugin: plugin == "猫猫" ? .maomao : .openclash)
        if ui.editingDevice == nil {
            ui.state.addDevice(d)
        } else {
            ui.state.updateDevice(d)
            if ui.state.selectedID != d.id { ui.state.select(d.id) }
            else if ui.state.connectedDeviceID != d.id { Task { await ui.state.connect() } }
        }
        ui.editingDevice = nil; password = ""; error = ""; ui.go(.overview)
    }
}

struct NodesPage: View {
    let ui: WindowsSession
    @State private var query = ""
    @State private var groupName = ""
    @State private var sort = "原始顺序"
    @State private var region = "全部地区"
    var group: ProxyGroup? { ui.state.snapshot.groups.first { $0.name == groupName } ?? ui.state.preferredPolicyGroup() ?? ui.state.snapshot.groups.first }
    var nodes: [ProxyItem] {
        guard let group else { return [] }
        var result = group.nodes.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        if region != "全部地区" { result = result.filter { NodeRegion.of($0.name).rawValue == region } }
        if sort == "延迟优先" { result.sort { (ui.state.delay(for: $0.name) ?? $0.lastDelay ?? Int.max) < (ui.state.delay(for: $1.name) ?? $1.lastDelay ?? Int.max) } }
        return result
    }
    var body: some View {
        VStack(spacing: ui.spacing) {
            Panel("策略组与节点", ui: ui) {
                Choice("策略组", ui.state.snapshot.groups.map(\.name), value: Binding(get: { group?.name ?? "" }, set: { groupName = $0 }))
                HStack { TextField("搜索节点", text: $query); Button(ui.state.pingingAll ? "正在测速…" : "全部测速") { ui.state.pingGroup(nodes.map(\.name)) }.disabled(!ui.available || ui.state.pingingAll) }
                HStack { Choice("排序", ["原始顺序", "延迟优先"], value: $sort); Choice("地区", ["全部地区", "香港", "新加坡", "其它"], value: $region) }
                Text("当前：" + (group?.now ?? "—") + "  ·  \(nodes.count) 个节点").foregroundColor(ui.muted)
            }
            if nodes.isEmpty { Panel("", ui: ui) { Text("暂无匹配节点，请连接设备或修改筛选条件。").foregroundColor(ui.muted) } }
            ForEach(Array(stride(from: 0, to: nodes.count, by: 3)), id: \.self) { start in
                HStack(alignment: .top, spacing: ui.spacing) {
                    ForEach(Array(nodes[start..<min(start + 3, nodes.count)]), id: \.name) { node in
                        NodeCard(ui: ui, node: node, group: group)
                    }
                }
            }
            Panel("自动切换", ui: ui) {
                Toggle("启用客户端自动切换", isOn: Binding(get: { ui.state.autoFailoverEnabled }, set: { ui.state.autoFailoverEnabled = $0 })).disabled(ui.demo)
                Toggle("固定当前节点（仅超时才切换）", isOn: Binding(get: { ui.state.pinnedNode }, set: { ui.state.setPinnedNode($0) })).disabled(ui.demo)
                Text("客户端需保持运行；独立设备守护在“设备控制”中管理。").font(.system(size: 12)).foregroundColor(ui.muted)
            }
        }
    }
}
struct NodeCard: View {
    let ui: WindowsSession; let node: ProxyItem; let group: ProxyGroup?
    var body: some View {
        Panel("", ui: ui) {
            Text((group?.now == node.name ? "●  " : "") + node.name).fontWeight(.semibold).lineLimit(2)
            if ui.preferences.showNodeProtocol { Text(node.typeLabel).font(.system(size: 11)).foregroundColor(ui.muted) }
            Text(ui.state.delay(for: node.name).map { "\($0) ms" } ?? node.lastDelay.map { "\($0) ms" } ?? "未测速").foregroundColor(ui.accent)
            HStack {
                Button("选择") { if let group { ui.state.selectNode(group: group.name, name: node.name) } }.disabled(!ui.available || group?.allowsManualSelect != true)
                Button("测速") { ui.state.ping(node.name) }.disabled(!ui.available || ui.state.testingNodes.contains(node.name))
            }
            Button(ui.state.isBlocked(node.name) ? "解除屏蔽" : "屏蔽自动切换") { if ui.state.isBlocked(node.name) { ui.state.unblockNode(node.name) } else { ui.state.blockNode(node.name) } }.disabled(ui.demo)
        }
    }
}

struct ControlPage: View {
    let ui: WindowsSession
    var state: AppState { ui.state }
    @State private var confirmUninstall = false
    var body: some View {
        VStack(spacing: ui.spacing) {
            Panel("OpenClash 服务", ui: ui) {
                Text(state.snapshot.status.running ? "●  服务正在运行" : "○  服务未运行").foregroundColor(ui.accent)
                HStack { Button("启动") { state.setRunning(true) }; Button("停止") { state.setRunning(false) }; Button("重启") { state.restart() } }.disabled(!ui.available)
            }
            ModePanel(ui: ui)
            Panel("流量接管", ui: ui) {
                HStack { ForEach(RunCapture.allCases, id: \.rawValue) { mode in Button((RunCapture.from(runMode: state.snapshot.status.runMode) == mode ? "● " : "") + mode.title) { state.setCapture(mode) } } }
                Toggle("域名嗅探", isOn: Binding(get: { state.snapshot.status.metaSniffer }, set: { state.toggleSetting("meta_sniffer", value: $0) }))
                if state.selectedDevice?.plugin == .openclash {
                    Toggle("绕过中国大陆", isOn: Binding(get: { state.snapshot.status.chinaIPRoute }, set: { state.setChinaIPRoute($0) }))
                    Toggle("尊重规则", isOn: Binding(get: { state.snapshot.status.respectRules }, set: { state.toggleSetting("respect_rules", value: $0) }))
                    Toggle("海外模式", isOn: Binding(get: { state.snapshot.status.oversea }, set: { state.toggleSetting("oversea", value: $0) }))
                }
            }.disabled(!ui.available)
            Panel("配置文件", ui: ui) {
                if state.snapshot.configs.isEmpty { Text("尚未读取到配置文件").foregroundColor(ui.muted) }
                ForEach(state.snapshot.configs, id: \.id) { file in
                    HStack { Text(file.name); Spacer(); Text(file.current ? "使用中" : "").foregroundColor(ui.accent); Button("切换") { state.switchConfig(file) }.disabled(!ui.available || file.current); Button("更新") { state.updateSubscription(named: file.name) }.disabled(!ui.available) }
                }
            }
            Panel("设备守护", ui: ui) {
                Text(state.deviceFailover.running ? "●  正在运行" : state.deviceFailover.installed ? "已安装，未运行" : "未安装")
                Text(state.deviceFailover.detail).foregroundColor(ui.muted)
                HStack {
                    Button("安装 / 更新") { state.installDeviceFailover() }
                    Button("立即检测") { state.probeDeviceFailoverNow() }.disabled(!state.deviceFailover.installed)
                    Button(confirmUninstall ? "确认卸载" : "卸载") { if confirmUninstall { state.uninstallDeviceFailover(); confirmUninstall = false } else { confirmUninstall = true } }.disabled(!state.deviceFailover.installed)
                }.disabled(!ui.available)
                Toggle("启用设备守护", isOn: Binding(get: { state.deviceFailover.enabled }, set: { state.setDeviceFailoverEnabled($0) })).disabled(!ui.available || !state.deviceFailover.installed)
                Choice("检测间隔", ["5", "15", "30"], value: Binding(get: { String(state.deviceFailover.interval) }, set: { if let n = Int($0) { state.setDeviceFailoverInterval(n) } })).disabled(!ui.available || !state.deviceFailover.installed)
                HStack { Button("刷新状态") { Task { await state.refreshDeviceFailover(); await state.refreshDeviceFailoverHistory() } }.disabled(!ui.available); if let url = state.deviceFailoverPanelURL { Button("打开设备守护面板") { ui.open(url) }.disabled(ui.demo) } }
                if !state.deviceFailover.log.isEmpty { Text(state.deviceFailover.log).font(.system(size: 12)).lineLimit(12) }
            }
            Panel("切换历史", ui: ui) {
                if state.displayedFailoverHistory.isEmpty { Text("暂无记录").foregroundColor(ui.muted) }
                ForEach(Array(state.displayedFailoverHistory.prefix(30)), id: \.id) { event in Text(event.at.formatted(date: .omitted, time: .shortened) + "  " + event.from + " → " + event.to + "  \(event.delay) ms").font(.system(size: 12)) }
            }
        }
    }
}

struct SubscriptionsPage: View {
    let ui: WindowsSession
    @State private var editing: String?
    @State private var name = ""
    @State private var address = ""
    @State private var agent = "clash.meta"
    @State private var enabled = true
    @State private var deleting: String?
    @State private var error = ""
    var body: some View {
        VStack(spacing: ui.spacing) {
            Panel("设备订阅", ui: ui) {
                if ui.state.snapshot.subscriptions.isEmpty { Text("尚未读取到订阅").foregroundColor(ui.muted) }
                ForEach(ui.state.snapshot.subscriptions, id: \.id) { sub in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(sub.name + (sub.enabled ? "  ·  已启用" : "  ·  已停用")).fontWeight(.semibold)
                        Text(sub.address).foregroundColor(ui.muted).lineLimit(1)
                        HStack {
                            Button("编辑") { editing = sub.section; name = sub.name; address = sub.address; agent = sub.userAgent; enabled = sub.enabled }
                            Button("更新") { ui.state.updateSubscription(named: sub.name) }
                            Button(deleting == sub.id ? "确认删除" : "删除") { if deleting == sub.id { ui.state.deleteSubscription(sub); deleting = nil } else { deleting = sub.id } }
                        }.disabled(!ui.available)
                    }.padding(.bottom, 10)
                }
            }
            Panel(editing == nil ? "添加订阅" : "编辑订阅", ui: ui) {
                TextField("订阅名称", text: $name); TextField("https:// 订阅地址", text: $address); TextField("User-Agent", text: $agent)
                Toggle("启用", isOn: $enabled)
                if !error.isEmpty { Text(error).foregroundColor(.red) }
                HStack {
                    Button("保存并更新设备") { save() }.disabled(!ui.available)
                    Button("新建") { editing = nil; name = ""; address = ""; error = "" }
                }
            }
        }
    }
    func save() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: address), ["https", "http"].contains(url.scheme ?? ""), url.host != nil else { error = "请填写名称和有效的 HTTP/HTTPS 订阅地址。"; return }
        ui.state.saveSubscription(Subscription(section: editing ?? "", name: name, address: address, enabled: enabled, userAgent: agent), isNew: editing == nil); error = ""
    }
}

struct RulesPage: View {
    let ui: WindowsSession
    @State private var query = ""
    @State private var domain = ""
    @State private var target = "DIRECT"
    @State private var result = ""
    @State private var page = 0
    var matches: [ClashRule] { ui.state.snapshot.rules.filter { query.isEmpty || $0.line.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        VStack(spacing: ui.spacing) {
            Panel("域名规则", ui: ui) {
                HStack { TextField("example.com", text: $domain); Button("匹配检查") { result = ui.state.matchRule(host: domain)?.line ?? "未找到匹配规则" } }
                Choice("目标策略", ["DIRECT", "REJECT"] + ui.state.snapshot.groups.map(\.name).filter { !["DIRECT", "REJECT"].contains($0) }, value: $target)
                HStack {
                    Button("添加到当前设备") { ui.state.addRule(domain: domain, proxy: target) }.disabled(!ui.available || domain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("收藏到本地配置") { ui.state.profile.domainRules.append(LocalDomainRule(domain: domain, proxy: target)); ui.state.persistProfile(); result = "已保存到本地配置" }.disabled(ui.demo || domain.isEmpty)
                }
                if !result.isEmpty { Text(result).foregroundColor(ui.muted) }
            }
            Panel("设备规则 · \(matches.count) 条", ui: ui) {
                TextField("搜索规则、域名或策略", text: $query).onChange(of: query) { page = 0 }
                ForEach(Array(matches.dropFirst(page * 100).prefix(100).enumerated()), id: \.offset) { item in Text(item.element.line).font(.system(size: 12)).lineLimit(2) }
                HStack { Button("上一页") { page -= 1 }.disabled(page == 0); Text("第 \(page + 1) 页"); Button("下一页") { page += 1 }.disabled((page + 1) * 100 >= matches.count) }
            }
        }
    }
}
