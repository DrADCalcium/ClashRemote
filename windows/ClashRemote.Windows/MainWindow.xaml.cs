using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using ClashRemote.Core;
using Forms = System.Windows.Forms;

namespace ClashRemote.Windows;
public partial class MainWindow : Window
{
    private readonly ProfileStore store = new(Environment.GetCommandLineArgs().FirstOrDefault(a => a.StartsWith("--data-dir=", StringComparison.Ordinal))?[11..]);
    private List<RouterProfile> profiles = [];
    private OpenClashClient? client;
    private RouterProfile? connectedProfile;
    private RouterStatus? status;
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromSeconds(3) };
    private CancellationTokenSource lifetime = new();
    private readonly Forms.NotifyIcon tray = new();
    private bool busy;
    private bool exiting;
    private bool ready;
    private IReadOnlyList<RuleRow> rules = [];
    private ConfigFile? loadedFile;
    private bool? loadedProviderKind;
    private long previousUp, previousDown;
    private DateTime previousTime;

    public MainWindow()
    {
        InitializeComponent();
        Loaded += async (_, _) =>
        {
            ready = true;
            try { profiles = store.Load(); UpdateDevices(); }
            catch { StatusText.Text = "无法读取设备配置。原文件已保留，请检查本机配置文件。"; }
            await Task.CompletedTask;
        };
        timer.Tick += async (_, _) => { if (!busy && client != null && IsVisible) await RunAsync(RefreshAsync, quiet: true); };
        timer.Start();
        tray.Icon = System.Drawing.Icon.ExtractAssociatedIcon(Environment.ProcessPath!) ?? System.Drawing.SystemIcons.Application;
        tray.Text = "Clash Remote · 未连接";
        tray.Visible = true;
        tray.DoubleClick += (_, _) => Dispatcher.Invoke(ShowWindow);
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("打开 Clash Remote", null, (_, _) => Dispatcher.Invoke(ShowWindow));
        menu.Items.Add(new Forms.ToolStripSeparator());
        foreach (var (label, action) in new[] { ("启动 OpenClash", "start"), ("停止 OpenClash", "stop"), ("重启 OpenClash", "restart") })
            menu.Items.Add(label, null, (_, _) => Dispatcher.InvokeAsync(async () => await ChangeServiceAsync(action)));
        menu.Items.Add(new Forms.ToolStripSeparator());
        foreach (var (label, mode) in new[] { ("规则模式", "rule"), ("直连模式", "direct"), ("全局模式", "global") })
            menu.Items.Add(label, null, (_, _) => Dispatcher.InvokeAsync(async () => await ChangeModeAsync(mode)));
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("退出", null, (_, _) => Dispatcher.Invoke(() => { exiting = true; Close(); }));
        tray.ContextMenuStrip = menu;
        FilePicker.SelectionChanged += (_, _) => { loadedFile = null; ConfigEditor.IsReadOnly = true; ConfigEditor.Text = "选择配置后点击读取；保存不会自动应用。"; };
    }

    private void ShowWindow() { Show(); WindowState = WindowState.Normal; Activate(); }
    private void UpdateDevices(Guid? select = null)
    {
        DeviceList.ItemsSource = null; DeviceList.ItemsSource = profiles;
        DeviceList.SelectedItem = profiles.FirstOrDefault(p => p.Id == select) ?? profiles.FirstOrDefault();
    }
    private void AddDevice(object sender, RoutedEventArgs e) => EditDeviceCore(null);
    private void EditDevice(object sender, RoutedEventArgs e) { if (DeviceList.SelectedItem is RouterProfile p) EditDeviceCore(p); }
    private void EditDeviceCore(RouterProfile? original)
    {
        if (busy) return;
        try
        {
            var dialog = new DeviceDialog(original) { Owner = this };
            if (dialog.ShowDialog() != true || dialog.Result is not { } result) return;
            if (original != null) profiles.Remove(original);
            profiles.Add(result); store.Save(profiles); Disconnect(); UpdateDevices(result.Id);
        }
        catch (Exception ex) { Error(ex); }
    }
    private void RemoveDevice(object sender, RoutedEventArgs e)
    {
        if (busy || DeviceList.SelectedItem is not RouterProfile p) return;
        if (!Confirm($"移除本机保存的「{p.Name}」？路由器配置不会被修改。")) return;
        try { profiles.Remove(p); store.Save(profiles); Disconnect(); UpdateDevices(); } catch (Exception ex) { Error(ex); }
    }
    private void DeviceSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!ready || busy) return;
        if (DeviceList.SelectedItem is RouterProfile p && p.Id != connectedProfile?.Id) Disconnect();
    }
    private async void ConnectClick(object sender, RoutedEventArgs e)
    {
        if (busy || DeviceList.SelectedItem is not RouterProfile p) return;
        Disconnect();
        await RunAsync(async ct =>
        {
            StatusText.Text = "正在登录路由器…";
            var next = new OpenClashClient(p, WindowsSecrets.Unprotect(p.ProtectedPassword), WindowsSecrets.Unprotect(p.ProtectedSecret));
            try { await next.LoginAsync(ct); }
            catch { next.Dispose(); throw; }
            client = next; connectedProfile = p;
            DeviceTitle.Text = p.Name; DeviceSubtitle.Text = p.BaseUri.Authority;
            await RefreshAsync(ct);
        });
    }
    private void DisconnectClick(object sender, RoutedEventArgs e) { if (!busy) Disconnect(); }
    private void Disconnect()
    {
        lifetime.Cancel(); lifetime.Dispose(); lifetime = new();
        client?.Dispose(); client = null; connectedProfile = null; status = null;
        previousTime = default;
        NodesGrid.ItemsSource = null; ConnectionsGrid.ItemsSource = null; RulesGrid.ItemsSource = null;
        ProvidersGrid.ItemsSource = null; SubscriptionsGrid.ItemsSource = null; GroupPicker.ItemsSource = null; FilePicker.ItemsSource = null;
        loadedFile = null; loadedProviderKind = null; rules = [];
        ConfigEditor.IsReadOnly = true; ConfigEditor.Text = "选择配置后点击读取；保存不会自动应用。";
        LogBox.Clear(); ServiceValue.Text = TrafficValue.Text = ConnectionsValue.Text = ModeValue.Text = ConfigValue.Text = CaptureValue.Text = CoreValue.Text = "—";
        ServiceHint.Text = "等待连接"; RateValue.Text = "等待流量数据"; LastUpdated.Text = "未连接";
        DeviceTitle.Text = "连接你的路由器"; DeviceSubtitle.Text = "选择设备并点击连接";
        StatusText.Text = "尚未连接 · 所有数据均来自实际设备"; tray.Text = "Clash Remote · 未连接";
    }
    private async Task RunAsync(Func<CancellationToken, Task> action, bool quiet = false)
    {
        if (busy) return;
        busy = true; Tabs.IsEnabled = false; ConnectButton.IsEnabled = false; DeviceList.IsEnabled = false;
        try { await action(lifetime.Token); }
        catch (OperationCanceledException) { if (!exiting) StatusText.Text = "请求已取消或超时，请刷新确认设备状态。"; }
        catch (Exception ex)
        {
            StatusText.Text = "操作未完成：" + FriendlyError(ex);
            if (quiet) LastUpdated.Text = "刷新失败 · " + DateTime.Now.ToString("HH:mm:ss"); else Error(ex);
        }
        finally { busy = false; Tabs.IsEnabled = true; ConnectButton.IsEnabled = true; DeviceList.IsEnabled = true; }
    }
    private static string FriendlyError(Exception e) => e is System.Net.Http.HttpRequestException ? "无法连接路由器或控制端口，请检查网络、地址和证书。" : e.Message;
    private void Error(Exception e) => MessageBox.Show(this, FriendlyError(e), "Clash Remote", MessageBoxButton.OK, MessageBoxImage.Warning);
    private bool Confirm(string text) => MessageBox.Show(this, text, "确认操作", MessageBoxButton.YesNo, MessageBoxImage.Question) == MessageBoxResult.Yes;
    private OpenClashClient RequireClient() => client ?? throw new InvalidOperationException("请先连接路由器。");

    private async Task RefreshAsync(CancellationToken ct)
    {
        var c = RequireClient(); var s = await c.GetStatusAsync(ct); status = s;
        ServiceValue.Text = s.Running ? "运行中" : "已停止";
        ServiceHint.Text = s.Enabled ? "插件启用" : "插件关闭";
        ModeValue.Text = "当前模式 · " + ModeTitle(s.Mode); ConfigValue.Text = s.ConfigPath;
        CaptureValue.Text = "当前接管方式 · " + s.Capture; CoreValue.Text = $"{s.Core}  ·  控制端口 {s.ControllerPort}";
        DeviceSubtitle.Text = $"{s.Hostname}  ·  {s.Model}";
        StatusText.Text = s.Running ? "已连接 · OpenClash 正在运行" : "已连接 · OpenClash 已停止，可以在「设备控制」中重新启动";
        tray.Text = ("Clash Remote · " + (s.Running ? ModeTitle(s.Mode) : "已停止"));
        if (s.Running)
        {
            try
            {
                if (Tabs.SelectedIndex is 0 or 3) await LoadConnectionsAsync(ct);
                if (Tabs.SelectedIndex == 2) await LoadNodesAsync(ct);
            }
            catch (Exception ex) when (ex is System.Net.Http.HttpRequestException or RouterException)
            {
                TrafficValue.Text = ConnectionsValue.Text = "—"; RateValue.Text = "控制接口不可用";
                ConnectionsGrid.ItemsSource = null; NodesGrid.ItemsSource = null;
                StatusText.Text = "路由器已连接，服务正在运行，但 Mihomo 控制接口不可用。请检查控制端口及 Secret。";
            }
        }
        else
        {
            TrafficValue.Text = ConnectionsValue.Text = "—"; RateValue.Text = "服务已停止";
            previousTime = default; ConnectionsGrid.ItemsSource = null; NodesGrid.ItemsSource = null; GroupPicker.ItemsSource = null;
        }
        LastUpdated.Text = "更新于 " + DateTime.Now.ToString("HH:mm:ss");
    }
    private static string ModeTitle(string mode) => mode.ToLowerInvariant() switch { "rule" => "规则", "direct" => "直连", "global" => "全局", _ => "未知" };
    private async void RefreshClick(object sender, RoutedEventArgs e) => await RunAsync(RefreshAsync);
    private async void ServiceClick(object sender, RoutedEventArgs e) => await ChangeServiceAsync((string)((Button)sender).Tag);
    private async Task ChangeServiceAsync(string action)
    {
        if (busy || client == null) return;
        if (action != "start" && !Confirm(action == "stop" ? "停止路由器上的 OpenClash？这会影响局域网当前代理连接。" : "重启路由器上的 OpenClash？当前代理连接可能短暂中断。")) return;
        await RunAsync(async ct => { StatusText.Text = "正在执行服务操作并等待状态确认，请稍候…"; await RequireClient().SetServiceAsync(action, ct); await RefreshAsync(ct); });
    }
    private async void ModeClick(object sender, RoutedEventArgs e) => await ChangeModeAsync((string)((Button)sender).Tag);
    private async Task ChangeModeAsync(string mode)
    {
        await RunAsync(async ct => { await RequireClient().SetModeAsync(mode, ct); await RefreshAsync(ct); });
    }
    private async void CaptureClick(object sender, RoutedEventArgs e)
    {
        if (!Confirm("切换流量接管方式可能重启服务并中断当前连接，继续吗？")) return;
        await RunAsync(async ct => { await RequireClient().SetCaptureAsync((string)((Button)sender).Tag, ct); await RefreshAsync(ct); });
    }
    private async void TabChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!ready || busy || client == null || e.Source != Tabs) return;
        await RunAsync(async ct =>
        {
            switch (Tabs.SelectedIndex)
            {
                case 0: case 1: await RefreshAsync(ct); break;
                case 2: await LoadNodesAsync(ct); break;
                case 3: await LoadConnectionsAsync(ct); break;
                case 4: await LoadRulesAsync(ct); break;
                case 5: await LoadProfilesAsync(ct); break;
                case 6: await LoadLogAsync(ct); break;
            }
        });
    }
    private async Task LoadNodesAsync(CancellationToken ct)
    {
        var selected = (GroupPicker.SelectedItem as ProxyGroup)?.Name;
        var selectedNode = (NodesGrid.SelectedItem as ProxyNode)?.Name;
        var groups = await RequireClient().GetGroupsAsync(ct);
        GroupPicker.ItemsSource = groups; GroupPicker.SelectedItem = groups.FirstOrDefault(g => g.Name == selected) ?? groups.FirstOrDefault();
        SetNodes();
        if (GroupPicker.SelectedItem is ProxyGroup group) NodesGrid.SelectedItem = group.Nodes.FirstOrDefault(n => n.Name == selectedNode);
    }
    private void GroupChanged(object sender, SelectionChangedEventArgs e) { if (ready) SetNodes(); }
    private void SetNodes()
    {
        if (GroupPicker.SelectedItem is not ProxyGroup group) return;
        NodesGrid.ItemsSource = group.Nodes;
        GroupHint.Text = group.CanSelect ? "当前：" + group.Selected : "此组由内核自动选择，可测速";
    }
    private async void NodesRefresh(object sender, RoutedEventArgs e) => await RunAsync(LoadNodesAsync);
    private async void SelectNode(object sender, RoutedEventArgs e)
    {
        if (GroupPicker.SelectedItem is not ProxyGroup g || NodesGrid.SelectedItem is not ProxyNode n) return;
        if (!g.CanSelect) { StatusText.Text = "只有 Selector 策略组可以手动选节点。"; return; }
        await RunAsync(async ct => { await RequireClient().SelectProxyAsync(g.Name, n.Name, ct); await LoadNodesAsync(ct); StatusText.Text = "节点已切换并确认"; });
    }
    private async void TestNode(object sender, RoutedEventArgs e)
    {
        if (NodesGrid.SelectedItem is not ProxyNode n) return;
        await RunAsync(async ct => { var delay = await RequireClient().TestDelayAsync(n.Name, ct); await LoadNodesAsync(ct); StatusText.Text = $"{n.Name} · {delay} ms"; });
    }
    private async void TestGroup(object sender, RoutedEventArgs e)
    {
        if (GroupPicker.SelectedItem is not ProxyGroup group) return;
        await RunAsync(async ct =>
        {
            using var limit = new SemaphoreSlim(4);
            var ok = 0; var failed = 0;
            await Task.WhenAll(group.Nodes.Select(async n =>
            {
                await limit.WaitAsync(ct);
                try { await RequireClient().TestDelayAsync(n.Name, ct); Interlocked.Increment(ref ok); }
                catch (Exception ex) when (ex is RouterException or System.Net.Http.HttpRequestException) { Interlocked.Increment(ref failed); }
                finally { limit.Release(); }
            }));
            await LoadNodesAsync(ct); StatusText.Text = $"测速完成 · 成功 {ok}，失败 {failed}";
        });
    }
    private async Task LoadConnectionsAsync(CancellationToken ct)
    {
        var snapshot = await RequireClient().GetConnectionsAsync(ct); var now = DateTime.UtcNow;
        var selected = (ConnectionsGrid.SelectedItem as ConnectionRow)?.Id;
        ConnectionsGrid.ItemsSource = snapshot.Rows; ConnectionsGrid.SelectedItem = snapshot.Rows.FirstOrDefault(r => r.Id == selected); ConnectionsValue.Text = snapshot.Rows.Count.ToString();
        TrafficValue.Text = Bytes(snapshot.Download) + " / " + Bytes(snapshot.Upload);
        var seconds = (now - previousTime).TotalSeconds;
        if (previousTime != default && seconds > 0 && snapshot.Download >= previousDown && snapshot.Upload >= previousUp)
            RateValue.Text = $"↓ {Bytes((long)((snapshot.Download - previousDown) / seconds))}/s   ↑ {Bytes((long)((snapshot.Upload - previousUp) / seconds))}/s";
        else RateValue.Text = "正在采集速率…";
        previousUp = snapshot.Upload; previousDown = snapshot.Download; previousTime = now;
    }
    private static string Bytes(long value)
    {
        double n = value; var units = new[] { "B", "KB", "MB", "GB", "TB" }; var i = 0;
        while (n >= 1024 && i < units.Length - 1) { n /= 1024; i++; }
        return $"{n:0.#} {units[i]}";
    }
    private async void ConnectionsRefresh(object sender, RoutedEventArgs e) => await RunAsync(LoadConnectionsAsync);
    private async void CloseConnection(object sender, RoutedEventArgs e)
    {
        if (ConnectionsGrid.SelectedItem is not ConnectionRow row || !Confirm("关闭所选连接？该连接上的传输会中断。")) return;
        await RunAsync(async ct => { await RequireClient().CloseConnectionAsync(row.Id, ct); await LoadConnectionsAsync(ct); });
    }
    private async void CloseAllConnections(object sender, RoutedEventArgs e)
    {
        if (!Confirm("关闭全部代理连接？所有当前传输都可能中断。")) return;
        await RunAsync(async ct => { await RequireClient().CloseConnectionAsync(null, ct); await LoadConnectionsAsync(ct); });
    }
    private async Task LoadRulesAsync(CancellationToken ct) { rules = await RequireClient().GetRulesAsync(ct); FilterRules(); }
    private void SearchRules(object sender, TextChangedEventArgs e) { if (ready) FilterRules(); }
    private void FilterRules() { var q = RuleSearch.Text.Trim(); RulesGrid.ItemsSource = rules.Where(r => (r.Type + r.Payload + r.Proxy).Contains(q, StringComparison.OrdinalIgnoreCase)).ToArray(); }
    private async void RulesRefresh(object sender, RoutedEventArgs e) => await RunAsync(LoadRulesAsync);
    private async void ProvidersRefresh(object sender, RoutedEventArgs e) => await RunAsync(async ct =>
    { var kind = RuleProviders.IsChecked == true; ProvidersGrid.ItemsSource = await RequireClient().GetProvidersAsync(kind, ct); loadedProviderKind = kind; });
    private async void UpdateProvider(object sender, RoutedEventArgs e)
    {
        if (ProvidersGrid.SelectedItem is not ProviderRow row || loadedProviderKind is not bool kind) return;
        await RunAsync(async ct => { await RequireClient().UpdateProviderAsync(kind, row.Name, ct); ProvidersGrid.ItemsSource = await RequireClient().GetProvidersAsync(kind, ct); StatusText.Text = "集合已更新"; });
    }
    private async Task LoadProfilesAsync(CancellationToken ct)
    {
        var c = RequireClient(); SubscriptionsGrid.ItemsSource = await c.GetSubscriptionsAsync(ct);
        var files = await c.GetFilesAsync(ct); FilePicker.ItemsSource = files; FilePicker.SelectedItem = files.FirstOrDefault(f => f.Current) ?? files.FirstOrDefault();
    }
    private async void ProfilesRefresh(object sender, RoutedEventArgs e) => await RunAsync(LoadProfilesAsync);
    private async void AddSubscription(object sender, RoutedEventArgs e) => await EditSubscriptionCoreAsync(null);
    private async void EditSubscription(object sender, RoutedEventArgs e) { if (SubscriptionsGrid.SelectedItem is Subscription sub) await EditSubscriptionCoreAsync(sub); }
    private async Task EditSubscriptionCoreAsync(Subscription? sub)
    {
        if (busy || client == null) return;
        var dialog = new SubscriptionDialog(sub) { Owner = this };
        if (dialog.ShowDialog() != true || dialog.Result is not { } value) return;
        await RunAsync(async ct => { await RequireClient().SaveSubscriptionAsync(value, ct); await LoadProfilesAsync(ct); StatusText.Text = "订阅已保存，未自动更新或重启"; });
    }
    private async void DeleteSubscription(object sender, RoutedEventArgs e)
    {
        if (SubscriptionsGrid.SelectedItem is not Subscription sub || !Confirm($"删除路由器上的订阅「{sub.Name}」？")) return;
        await RunAsync(async ct => { await RequireClient().DeleteSubscriptionAsync(sub, ct); await LoadProfilesAsync(ct); });
    }
    private async void UpdateSubscription(object sender, RoutedEventArgs e)
    {
        if (SubscriptionsGrid.SelectedItem is not Subscription sub || !Confirm("更新所选订阅？OpenClash 可能重新载入配置并中断连接。")) return;
        await RunAsync(async ct => { await RequireClient().UpdateSubscriptionAsync(sub.Name, ct); StatusText.Text = "已提交订阅更新，请稍后刷新配置及日志确认完成。"; });
    }
    private async void SwitchConfig(object sender, RoutedEventArgs e)
    {
        if (FilePicker.SelectedItem is not ConfigFile file || !Confirm($"切换到 {file.Name}？服务可能重启。")) return;
        await RunAsync(async ct => { await RequireClient().SwitchConfigAsync(file, ct); await LoadProfilesAsync(ct); await RefreshAsync(ct); });
    }
    private async void ReadConfig(object sender, RoutedEventArgs e)
    {
        if (FilePicker.SelectedItem is not ConfigFile file) return;
        await RunAsync(async ct => { ConfigEditor.Text = await RequireClient().ReadConfigAsync(file, ct); loadedFile = file; ConfigEditor.IsReadOnly = false; });
    }
    private async void SaveConfig(object sender, RoutedEventArgs e)
    {
        if (loadedFile is not { } file || !Confirm($"保存到路由器的 {file.Name}？原文件将备份为 .clashremote.bak。本程序不校验 YAML，保存不会自动应用。")) return;
        var text = ConfigEditor.Text;
        await RunAsync(async ct => { await RequireClient().SaveConfigAsync(file, text, ct); StatusText.Text = "配置已备份并保存，尚未应用"; });
    }
    private async Task LoadLogAsync(CancellationToken ct) { LogBox.Text = await RequireClient().GetLogAsync(ct); LogBox.ScrollToEnd(); }
    private async void LogClick(object sender, RoutedEventArgs e) => await RunAsync(LoadLogAsync);
    private void OpenRouter(object sender, RoutedEventArgs e)
    {
        if (DeviceList.SelectedItem is not RouterProfile p) return;
        try { Launch(new Uri(p.BaseUri, "cgi-bin/luci/admin/services/openclash/client")); } catch (Exception ex) { Error(ex); }
    }
    private void OpenPanel(object sender, RoutedEventArgs e)
    { try { Launch(RequireClient().PanelUri); } catch (Exception ex) { Error(ex); } }
    private static void Launch(Uri uri) => Process.Start(new ProcessStartInfo(uri.AbsoluteUri) { UseShellExecute = true });
    private void TopmostOn(object sender, RoutedEventArgs e) => Topmost = true;
    private void TopmostOff(object sender, RoutedEventArgs e) => Topmost = false;
    protected override void OnClosing(CancelEventArgs e)
    {
        if (!exiting && TrayOnClose.IsChecked == true) { e.Cancel = true; Hide(); return; }
        exiting = true; timer.Stop(); lifetime.Cancel(); tray.Visible = false; tray.Dispose(); client?.Dispose();
        base.OnClosing(e);
    }
}
