// Protocol port of DonVitsch/ClashRemote (MIT), Network/OpenClashClient.swift and OpenClashService.swift.
using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace ClashRemote.Core;

public sealed class RouterException(string message) : Exception(message);
public sealed class OpenClashClient : IDisposable
{
    private const string ZeroSession = "00000000000000000000000000000000";
    private readonly RouterProfile profile;
    private readonly string password;
    private readonly HttpClient http;
    private readonly SemaphoreSlim loginGate = new(1, 1);
    private string session = "";
    private string cookie = "";
    private int requestId;
    public int ControllerPort { get; private set; }
    private string secret;
    public Uri PanelUri => new(new UriBuilder(profile.ControllerUseHttps ? "https" : "http", profile.BaseUri.Host, ControllerPort).Uri, "ui/");

    public OpenClashClient(RouterProfile profile, string password, string secret = "", HttpMessageHandler? handler = null)
    {
        _ = profile.BaseUri;
        if (profile.ControllerPort is < 1 or > 65535) throw new ArgumentException("控制端口必须在 1–65535 之间。");
        this.profile = profile;
        this.password = password;
        this.secret = secret;
        ControllerPort = profile.ControllerPort;
        http = new HttpClient(handler ?? new HttpClientHandler
        {
            UseProxy = false, AllowAutoRedirect = false, UseCookies = false,
            AutomaticDecompression = DecompressionMethods.All
        }) { Timeout = TimeSpan.FromSeconds(25) };
    }

    private static JsonElement Parse(string text)
    {
        try { using var doc = JsonDocument.Parse(text); return doc.RootElement.Clone(); }
        catch (JsonException) { throw new RouterException("路由器未返回 JSON。请检查 LuCI 登录状态、管理地址及插件版本。"); }
    }

    private async Task<JsonElement> RpcRawAsync(string sid, string obj, string method, object parameters, CancellationToken ct)
    {
        var payload = new { jsonrpc = "2.0", id = Interlocked.Increment(ref requestId), method = "call",
            @params = new object[] { sid, obj, method, parameters } };
        using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(profile.BaseUri, "ubus"))
        { Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json") };
        using var response = await http.SendAsync(request, ct);
        if (!response.IsSuccessStatusCode) throw new RouterException($"ubus HTTP {(int)response.StatusCode}，请检查路由器是否启用 ubus HTTP 接口。");
        var json = Parse(await response.Content.ReadAsStringAsync(ct));
        if (json.Field("error").ValueKind == JsonValueKind.Object) throw new RouterException("ubus 请求被拒绝，请检查 rpcd 权限。");
        var result = json.Field("result").Items().ToArray();
        if (result.Length == 0) throw new RouterException("ubus 响应缺少 result。");
        var code = result[0].Number(-1);
        if (code != 0) throw new UbusException(code);
        return result.Length > 1 ? result[1] : Parse("{}");
    }

    private sealed class UbusException(long code) : Exception($"ubus 错误 {code}") { public long Code { get; } = code; }

    public async Task LoginAsync(CancellationToken ct = default)
    {
        await loginGate.WaitAsync(ct);
        try
        {
            session = cookie = "";
            JsonElement login;
            try { login = await RpcRawAsync(ZeroSession, "session", "login", new { username = profile.Username, password }, ct); }
            catch (UbusException) { throw new RouterException("登录失败：用户名、密码错误或账户没有 ubus 权限。"); }
            var sid = login.Field("ubus_rpc_session").Text();
            if (sid.Length != 32 || !sid.All(Uri.IsHexDigit)) throw new RouterException("登录失败：路由器未返回有效会话。");
            using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(profile.BaseUri, "cgi-bin/luci/"))
            { Content = new FormUrlEncodedContent(new Dictionary<string, string> { ["luci_username"] = profile.Username, ["luci_password"] = password }) };
            using var response = await http.SendAsync(request, ct);
            if ((int)response.StatusCode >= 400) throw new RouterException($"LuCI 登录失败（HTTP {(int)response.StatusCode}）。");
            var cookies = new List<string>();
            if (response.Headers.TryGetValues("Set-Cookie", out var values))
                foreach (var value in values)
                {
                    var pair = value.Split(';')[0];
                    if (pair.StartsWith("sysauth=") || pair.StartsWith("sysauth_http=") || pair.StartsWith("sysauth_https=")) cookies.Add(pair);
                }
            if (cookies.Count == 0) throw new RouterException("LuCI 未返回登录 Cookie。请确认管理地址正确、账号有 LuCI 登录权限。");
            cookie = string.Join("; ", cookies);
            session = sid;
        }
        finally { loginGate.Release(); }
    }

    public async Task<JsonElement> UbusAsync(string obj, string method, object parameters, CancellationToken ct = default)
    {
        if (session.Length == 0) await LoginAsync(ct);
        try { return await RpcRawAsync(session, obj, method, parameters, ct); }
        catch (UbusException e) when (e.Code == 6)
        {
            // Read requests may be retried after authentication; mutations must not be replayed.
            if (method is not ("get" or "board" or "read" or "list"))
                throw new RouterException("会话失效，操作未自动重试。请重新连接后核对状态。");
            await LoginAsync(ct);
            try { return await RpcRawAsync(session, obj, method, parameters, ct); }
            catch (UbusException) { throw new RouterException("ubus 权限不足，请检查 rpcd ACL。"); }
        }
        catch (UbusException e) { throw new RouterException(e.Message + "，请检查 rpcd ACL 和插件是否已安装。"); }
    }

    public async Task<JsonElement> LuCIAsync(string endpoint, Dictionary<string, string>? fields = null, bool mutation = false, CancellationToken ct = default)
    {
        if (session.Length == 0) await LoginAsync(ct);
        var values = fields == null ? new Dictionary<string, string>() : new(fields);
        var path = "cgi-bin/luci/admin/services/openclash/" + endpoint;
        if (!mutation && values.Count > 0) path += "?" + await new FormUrlEncodedContent(values).ReadAsStringAsync(ct);
        using var request = new HttpRequestMessage(mutation ? HttpMethod.Post : HttpMethod.Get, new Uri(profile.BaseUri, path));
        request.Headers.Add("Cookie", cookie);
        if (mutation) request.Content = new FormUrlEncodedContent(values);
        using var response = await http.SendAsync(request, ct);
        if ((int)response.StatusCode is 401 or 403 || (int)response.StatusCode is >= 300 and < 400)
            throw new RouterException("LuCI 会话或表单令牌失效，请重新连接后重试。");
        if (!response.IsSuccessStatusCode) throw new RouterException($"OpenClash 接口 {endpoint} 返回 HTTP {(int)response.StatusCode}。请检查插件版本。");
        var text = await response.Content.ReadAsStringAsync(ct);
        var json = string.IsNullOrWhiteSpace(text) ? Parse("{}") : Parse(text);
        var state = json.Field("status").Text();
        if (state is "error" or "failed" or "failure" || json.Field("success").ValueKind == JsonValueKind.False)
            throw new RouterException($"OpenClash 拒绝了 {endpoint} 操作，请检查路由器日志。");
        return json;
    }

    public async Task<JsonElement> ClashAsync(string path, HttpMethod? method = null, object? payload = null, CancellationToken ct = default)
    {
        var baseUri = new UriBuilder(profile.ControllerUseHttps ? "https" : "http", profile.BaseUri.Host, ControllerPort).Uri;
        using var request = new HttpRequestMessage(method ?? HttpMethod.Get, new Uri(baseUri, path.TrimStart('/')));
        if (secret.Length > 0) request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", secret);
        if (payload != null) request.Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");
        using var response = await http.SendAsync(request, ct);
        if (!response.IsSuccessStatusCode) throw new RouterException($"Mihomo 接口返回 HTTP {(int)response.StatusCode}。请检查服务状态、控制端口和 Secret。");
        var text = await response.Content.ReadAsStringAsync(ct);
        return string.IsNullOrWhiteSpace(text) ? Parse("{}") : Parse(text);
    }

    public async Task<RouterStatus> GetStatusAsync(CancellationToken ct = default)
    {
        var status = await LuCIAsync("status", ct: ct);
        var uci = (await UbusAsync("uci", "get", new { config = "openclash" }, ct)).Field("values").Field("config");
        var discoveredPort = status.Field("cn_port").Number(uci.Field("cn_port").Number(profile.ControllerPort));
        if (discoveredPort is > 0 and <= 65535) ControllerPort = (int)discoveredPort;
        var discoveredSecret = status.Field("dase").Text();
        if (discoveredSecret.Length == 0) discoveredSecret = uci.Field("dashboard_password").Text();
        if (discoveredSecret.Length > 0) secret = discoveredSecret;
        var board = await UbusAsync("system", "board", new { }, ct);
        var mode = uci.Field("proxy_mode").Text();
        if (mode.Length == 0) mode = "unknown";
        if (status.Field("clash").Flag())
        {
            try { mode = (await ClashAsync("configs", ct: ct)).Field("mode").Text(); }
            catch (HttpRequestException) { }
            catch (RouterException) { }
        }
        return new(status.Field("clash").Flag(), uci.Field("enable").Flag(), board.Field("hostname").Text(),
            board.Field("model").Text(), status.Field("core_type").Text(), mode,
            uci.Field("en_mode").Text(), uci.Field("config_path").Text(), ControllerPort);
    }

    public async Task SetServiceAsync(string action, CancellationToken ct = default)
    {
        if (action is not ("start" or "stop" or "restart")) throw new ArgumentException("无效服务操作。");
        await LuCIAsync("action", new() { ["action"] = action }, true, ct);
        var expected = action != "stop";
        for (var attempt = 0; attempt < 45; attempt++)
        {
            await Task.Delay(TimeSpan.FromSeconds(2), ct);
            var s = await GetStatusAsync(ct);
            if (s.Running == expected && s.Enabled == expected) return;
        }
        throw new RouterException("已发送服务命令，但 90 秒内未确认目标状态。请刷新并查看 OpenClash 日志，不要重复点击。");
    }

    public async Task SetModeAsync(string mode, CancellationToken ct = default)
    {
        if (mode is not ("rule" or "global" or "direct")) throw new ArgumentException("无效代理模式。");
        await LuCIAsync("switch_rule_mode", new() { ["rule_mode"] = mode }, true, ct);
        var actual = (await ClashAsync("configs", ct: ct)).Field("mode").Text();
        if (!string.Equals(actual, mode, StringComparison.OrdinalIgnoreCase)) throw new RouterException("模式修改后核对不一致，请刷新状态。");
    }

    public async Task SetCaptureAsync(string capture, CancellationToken ct = default)
    {
        if (capture is not ("" or "-tun" or "-mix")) throw new ArgumentException("无效运行方式。");
        await LuCIAsync("switch_run_mode", new() { ["run_mode"] = capture }, true, ct);
    }

    public async Task<IReadOnlyList<ProxyGroup>> GetGroupsAsync(CancellationToken ct = default)
    {
        var proxies = (await ClashAsync("proxies", ct: ct)).Field("proxies");
        return proxies.Properties().Where(p => p.Value.Field("all").ValueKind == JsonValueKind.Array).Select(p =>
            new ProxyGroup(p.Name, p.Value.Field("type").Text(), p.Value.Field("now").Text(),
                p.Value.Field("all").Items().Select(n =>
                {
                    var name = n.Text(); var node = proxies.Field(name);
                    var history = node.Field("history").Items().LastOrDefault();
                    int? delay = history.Field("delay").ValueKind == JsonValueKind.Undefined ? null : (int)history.Field("delay").Number();
                    return new ProxyNode(name, node.Field("type").Text(), delay,
                        node.Field("alive").ValueKind == JsonValueKind.Undefined ? null : node.Field("alive").Flag());
                }).ToArray())).ToArray();
    }

    public async Task SelectProxyAsync(string group, string node, CancellationToken ct = default)
    {
        await ClashAsync("proxies/" + Uri.EscapeDataString(group), HttpMethod.Put, new { name = node }, ct);
        var actual = (await ClashAsync("proxies/" + Uri.EscapeDataString(group), ct: ct)).Field("now").Text();
        if (actual != node) throw new RouterException("节点选择后核对不一致，请刷新节点列表。");
    }

    public async Task<int> TestDelayAsync(string name, CancellationToken ct = default)
    {
        var j = await ClashAsync("proxies/" + Uri.EscapeDataString(name) + "/delay?timeout=5000&url=" + Uri.EscapeDataString("https://www.gstatic.com/generate_204"), ct: ct);
        return (int)j.Field("delay").Number(-1);
    }

    public async Task<ConnectionsSnapshot> GetConnectionsAsync(CancellationToken ct = default)
    {
        var j = await ClashAsync("connections", ct: ct);
        var rows = j.Field("connections").Items().Select(c =>
        {
            var m = c.Field("metadata"); var host = m.Field("host").Text();
            if (host.Length == 0) host = m.Field("destinationIP").Text();
            return new ConnectionRow(c.Field("id").Text(), m.Field("sourceIP").Text(), host + ":" + m.Field("destinationPort").Text(),
                m.Field("network").Text(), c.Field("rule").Text() + " " + c.Field("rulePayload").Text(),
                string.Join(" → ", c.Field("chains").Items().Select(x => x.Text())), c.Field("upload").Number(), c.Field("download").Number());
        }).ToArray();
        return new(j.Field("uploadTotal").Number(), j.Field("downloadTotal").Number(), rows);
    }
    public async Task CloseConnectionAsync(string? id, CancellationToken ct = default) =>
        _ = await ClashAsync("connections" + (id == null ? "" : "/" + Uri.EscapeDataString(id)), HttpMethod.Delete, ct: ct);
    public async Task<IReadOnlyList<RuleRow>> GetRulesAsync(CancellationToken ct = default) =>
        (await ClashAsync("rules", ct: ct)).Field("rules").Items().Select(r => new RuleRow(r.Field("type").Text(), r.Field("payload").Text(), r.Field("proxy").Text())).ToArray();

    public async Task<string> GetLogAsync(CancellationToken ct = default)
    {
        var j = await UbusAsync("file", "read", new { path = "/tmp/openclash.log" }, ct);
        return string.Join('\n', j.Field("data").Text().Split('\n').TakeLast(600));
    }

    public async Task<IReadOnlyList<ConfigFile>> GetFilesAsync(CancellationToken ct = default)
    {
        var j = await LuCIAsync("config_file_list", ct: ct);
        var current = j.Field("current_config").Text();
        return j.Field("config_files").Items().Select(f => new ConfigFile(f.Field("name").Text(), f.Field("path").Text(),
            current == f.Field("path").Text() || current.EndsWith("/" + f.Field("name").Text(), StringComparison.Ordinal) || current == f.Field("name").Text())).ToArray();
    }
    public async Task SwitchConfigAsync(ConfigFile file, CancellationToken ct = default) =>
        _ = await LuCIAsync("switch_config", new() { ["config_file"] = file.Path.Length == 0 ? file.Name : file.Path }, true, ct);
    public async Task UpdateSubscriptionAsync(string name, CancellationToken ct = default) =>
        _ = await LuCIAsync("update_config", new() { ["filename"] = name }, true, ct);
    public async Task<IReadOnlyList<Subscription>> GetSubscriptionsAsync(CancellationToken ct = default) =>
        (await UbusAsync("uci", "get", new { config = "openclash" }, ct)).Field("values").Properties()
            .Where(p => p.Value.Field(".type").Text() == "config_subscribe")
            .Select(p => new Subscription(p.Name, p.Value.Field("name").Text(), p.Value.Field("address").Text(), p.Value.Field("enabled").Flag(), p.Value.Field("sub_ua").Text())).ToArray();
    public async Task SaveSubscriptionAsync(Subscription sub, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(sub.Name) || sub.Name.IndexOfAny(['/','\\','\r','\n']) >= 0) throw new ArgumentException("订阅名称不能为空或包含路径分隔符。");
        if (!Uri.TryCreate(sub.Address, UriKind.Absolute, out var u) || u.Scheme is not ("http" or "https")) throw new ArgumentException("订阅地址必须为 HTTP 或 HTTPS。");
        var values = new Dictionary<string, string> { ["name"] = sub.Name, ["address"] = sub.Address, ["enabled"] = sub.Enabled ? "1" : "0", ["sub_ua"] = sub.UserAgent };
        if (sub.Section.Length == 0) await UbusAsync("uci", "add", new { config = "openclash", type = "config_subscribe", values }, ct);
        else await UbusAsync("uci", "set", new { config = "openclash", section = sub.Section, values }, ct);
        await UbusAsync("uci", "commit", new { config = "openclash" }, ct);
    }
    public async Task DeleteSubscriptionAsync(Subscription sub, CancellationToken ct = default)
    {
        await UbusAsync("uci", "delete", new { config = "openclash", section = sub.Section }, ct);
        await UbusAsync("uci", "commit", new { config = "openclash" }, ct);
    }
    private static string ConfigPath(ConfigFile f)
    {
        var path = f.Path.Length == 0 ? "/etc/openclash/config/" + f.Name : f.Path;
        if (!path.StartsWith("/etc/openclash/config/", StringComparison.Ordinal) || path.Contains("..") || path.Contains('\0')) throw new ArgumentException("只允许读写 OpenClash 配置目录中的文件。");
        return path;
    }
    public async Task<string> ReadConfigAsync(ConfigFile f, CancellationToken ct = default) =>
        (await UbusAsync("file", "read", new { path = ConfigPath(f) }, ct)).Field("data").Text();
    public async Task SaveConfigAsync(ConfigFile f, string content, CancellationToken ct = default)
    {
        var path = ConfigPath(f);
        var original = await ReadConfigAsync(f, ct);
        await UbusAsync("file", "write", new { path = path + ".clashremote.bak", data = original }, ct);
        await UbusAsync("file", "write", new { path, data = content }, ct);
    }
    public async Task<IReadOnlyList<ProviderRow>> GetProvidersAsync(bool rules, CancellationToken ct = default) =>
        (await ClashAsync("providers/" + (rules ? "rules" : "proxies"), ct: ct)).Field("providers").Properties()
            .Select(p => new ProviderRow(p.Name, p.Value.Field("type").Text(), p.Value.Field("updatedAt").Text())).ToArray();
    public async Task UpdateProviderAsync(bool rules, string name, CancellationToken ct = default) =>
        _ = await ClashAsync("providers/" + (rules ? "rules/" : "proxies/") + Uri.EscapeDataString(name), HttpMethod.Put, ct: ct);
    public void Dispose() { http.Dispose(); loginGate.Dispose(); }
}
