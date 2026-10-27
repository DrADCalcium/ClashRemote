using System.Net;
using System.Text;
using System.Text.Json;
using ClashRemote.Core;

if (args.Length == 1 && args[0] == "--serve")
{
    using var fake = new RouterFake { ApiPort = 19180 };
    using var http = new HttpClient(fake);
    using var listener = new HttpListener(); listener.Prefixes.Add("http://127.0.0.1:19180/"); listener.Start();
    Console.WriteLine("Mock OpenClash on http://127.0.0.1:19180 — no real router is contacted");
    while (true)
    {
        var context = await listener.GetContextAsync();
        try
        {
            using var request = new HttpRequestMessage(new HttpMethod(context.Request.HttpMethod), context.Request.Url);
            using var reader = new StreamReader(context.Request.InputStream);
            var body = await reader.ReadToEndAsync();
            if (body.Length > 0) request.Content = new StringContent(body, Encoding.UTF8, (context.Request.ContentType ?? "application/json").Split(';')[0]);
            if (context.Request.Headers["Cookie"] is { } cookie) request.Headers.TryAddWithoutValidation("Cookie", cookie);
            using var response = await http.SendAsync(request);
            context.Response.StatusCode = (int)response.StatusCode;
            if (response.Headers.TryGetValues("Set-Cookie", out var cookies)) foreach (var c in cookies) context.Response.Headers.Add("Set-Cookie", c);
            var bytes = await response.Content.ReadAsByteArrayAsync();
            context.Response.ContentType = "application/json"; context.Response.ContentLength64 = bytes.Length;
            await context.Response.OutputStream.WriteAsync(bytes);
        }
        catch { context.Response.StatusCode = 500; }
        finally { context.Response.Close(); }
    }
}

var passed = 0;
async Task Test(string title, Func<Task> test)
{
    try { await test(); Console.WriteLine("PASS " + title); passed++; }
    catch (Exception e) { Console.Error.WriteLine("FAIL " + title + ": " + e); Environment.ExitCode = 1; }
}
void Assert(bool condition, string message) { if (!condition) throw new Exception(message); }
async Task Throws<T>(Func<Task> work) where T : Exception
{ try { await work(); } catch (T) { return; } throw new Exception("Expected " + typeof(T).Name); }
RouterProfile Profile() => new() { Address = "http://192.168.1.1", Name = "Test" };

await Test("reject credential-bearing and non-HTTP addresses", () =>
{
    foreach (var address in new[] { "file:///C:/secret", "http://user:pass@router", "http://router/cgi-bin/luci", "http://router?key=x", "http://router/#secret" })
    { try { RouterProfile.ValidateAddress(address); throw new Exception("Accepted " + address); } catch (ArgumentException) { } }
    Assert(RouterProfile.ValidateAddress("192.168.1.1").Host == "192.168.1.1", "plain IP"); return Task.CompletedTask;
});
await Test("login uses POST and retains LuCI redirect cookie", async () =>
{
    using var fake = new RouterFake(); using var c = new OpenClashClient(Profile(), "test-password", handler: fake);
    await c.LoginAsync(); var status = await c.GetStatusAsync();
    Assert(status.Running && status.ControllerPort == 9091 && status.Model == "Test Router", "discovery");
    Assert(fake.LoginCount == 1 && fake.CookieObserved, "session/cookie");
    Assert(fake.SecretObserved, "discovered secret used");
});
await Test("reject bad credentials before any service call", async () =>
{
    using var fake = new RouterFake { DenyLogin = true }; using var c = new OpenClashClient(Profile(), "bad", handler: fake);
    await Throws<RouterException>(() => c.LoginAsync()); Assert(fake.ServiceCalls == 0, "service called");
});
await Test("reject missing LuCI auth cookie", async () =>
{
    using var fake = new RouterFake { MissingCookie = true }; using var c = new OpenClashClient(Profile(), "pw", handler: fake);
    await Throws<RouterException>(() => c.LoginAsync());
});
await Test("stopped core keeps router administration reachable", async () =>
{
    using var fake = new RouterFake { Running = false }; using var c = new OpenClashClient(Profile(), "pw", handler: fake);
    await c.LoginAsync(); var status = await c.GetStatusAsync(); Assert(!status.Running && !status.Enabled, "stopped status");
    Assert(fake.ClashCalls == 0, "must not require stopped core API");
});
await Test("service stop and start require observed router state", async () =>
{
    using var fake = new RouterFake(); using var c = new OpenClashClient(Profile(), "pw", handler: fake);
    await c.LoginAsync(); await c.SetServiceAsync("stop"); Assert(!fake.Running, "stop");
    await c.SetServiceAsync("start"); Assert(fake.Running && fake.ServiceCalls == 2, "restart after stop");
});
await Test("rejected service action is not reported successful", async () =>
{
    using var fake = new RouterFake { RejectAction = true }; using var c = new OpenClashClient(Profile(), "pw", handler: fake);
    await c.LoginAsync(); await Throws<RouterException>(() => c.SetServiceAsync("stop")); Assert(fake.Running, "state mutated");
});
await Test("invalid service command cannot reach router", async () =>
{
    using var fake = new RouterFake(); using var c = new OpenClashClient(Profile(), "pw", handler: fake);
    await Throws<ArgumentException>(() => c.SetServiceAsync("stop; reboot")); Assert(fake.ServiceCalls == 0, "invalid command submitted");
});
await Test("mode update persists through LuCI and verifies core", async () =>
{
    using var fake = new RouterFake(); using var c = new OpenClashClient(Profile(), "pw", handler: fake);
    await c.LoginAsync(); await c.SetModeAsync("global"); Assert(fake.Mode == "global", "mode");
    fake.IgnoreMode = true; await Throws<RouterException>(() => c.SetModeAsync("direct"));
});
await Test("node selector path encodes special characters", async () =>
{
    using var fake = new RouterFake(); using var c = new OpenClashClient(Profile(), "pw", handler: fake);
    await c.SelectProxyAsync("HK/日本 #1", "Node A");
    Assert(fake.LastProxyPath.Contains("HK%2F") && fake.LastProxyPath.Contains("%23"), "path was not escaped");
});
await Test("connection counters and chains parse without invented values", async () =>
{
    using var fake = new RouterFake(); using var c = new OpenClashClient(Profile(), "pw", handler: fake);
    var snapshot = await c.GetConnectionsAsync(); Assert(snapshot.Download == 2048 && snapshot.Rows.Single().Destination == "example.org:443", "connections");
});
await Test("config saving creates backup before overwrite", async () =>
{
    using var fake = new RouterFake(); using var c = new OpenClashClient(Profile(), "pw", handler: fake);
    await c.LoginAsync(); await c.SaveConfigAsync(new("a.yaml", "/etc/openclash/config/a.yaml", true), "mode: direct");
    Assert(fake.Writes.Count == 2 && fake.Writes[0].Path.EndsWith(".clashremote.bak") && fake.Writes[0].Data == "mode: rule", "backup");
});
await Test("failed backup prevents config overwrite", async () =>
{
    using var fake = new RouterFake { FailBackup = true }; using var c = new OpenClashClient(Profile(), "pw", handler: fake);
    await c.LoginAsync(); await Throws<RouterException>(() => c.SaveConfigAsync(new("a.yaml", "", false), "mode: direct"));
    Assert(fake.Writes.Count == 0, "wrote config without backup");
});
await Test("config path traversal blocked", async () =>
{
    using var fake = new RouterFake(); using var c = new OpenClashClient(Profile(), "pw", handler: fake);
    await Throws<ArgumentException>(() => c.ReadConfigAsync(new("x", "/etc/openclash/config/../../passwd", false)));
});
await Test("expired read session reauthenticates once", async () =>
{
    using var fake = new RouterFake(); using var c = new OpenClashClient(Profile(), "pw", handler: fake);
    await c.LoginAsync(); fake.ExpireNext = true; await c.GetSubscriptionsAsync(); Assert(fake.LoginCount == 2, "read session not renewed");
});
await Test("expired mutations are not silently replayed", async () =>
{
    using var fake = new RouterFake(); using var c = new OpenClashClient(Profile(), "pw", handler: fake);
    await c.LoginAsync(); fake.ExpireNext = true;
    await Throws<RouterException>(() => c.SaveSubscriptionAsync(new("", "test", "https://example.org/sub", true, "clash.meta")));
    Assert(fake.LoginCount == 1 && fake.Adds == 0, "mutation replayed");
});
await Test("HTML login response is rejected", async () =>
{
    using var fake = new RouterFake { HtmlStatus = true }; using var c = new OpenClashClient(Profile(), "pw", handler: fake);
    await c.LoginAsync(); await Throws<RouterException>(() => c.GetStatusAsync());
});
Console.WriteLine($"{passed} checks passed; exit={Environment.ExitCode}");

sealed class RouterFake : HttpMessageHandler
{
    public bool Running = true, DenyLogin, MissingCookie, RejectAction, IgnoreMode, ExpireNext, HtmlStatus, FailBackup;
    public bool CookieObserved, SecretObserved;
    public int LoginCount, ServiceCalls, ClashCalls, Adds;
    public int ApiPort = 9091;
    public string Mode = "rule", LastProxyPath = "";
    private string selected = "";
    public List<(string Path, string Data)> Writes = [];
    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage r, CancellationToken ct)
    {
        var path = r.RequestUri!.AbsolutePath;
        var body = r.Content == null ? "" : await r.Content.ReadAsStringAsync(ct);
        if (path == "/ubus")
        {
            using var doc = JsonDocument.Parse(body); var p = doc.RootElement.GetProperty("params"); var obj = p[1].GetString(); var method = p[2].GetString(); var args = p[3];
            if (obj == "session") { LoginCount++; return DenyLogin ? Json("{\"result\":[6]}") : Rpc(new { ubus_rpc_session = new string('a',32) }); }
            if (ExpireNext) { ExpireNext = false; return Json("{\"result\":[6]}"); }
            if (obj == "system") return Rpc(new { hostname = "test-router", model = "Test Router" });
            if (obj == "uci" && method == "get") return Rpc(new { values = new Dictionary<string,object> { ["config"] = new { enable = Running ? "1" : "0", cn_port = ApiPort.ToString(), dashboard_password = "fixture-secret", en_mode = "fake-ip", config_path = "/etc/openclash/config/a.yaml" } } });
            if (obj == "file" && method == "read") return Rpc(new { data = "mode: rule" });
            if (obj == "file" && method == "write")
            {
                var target = args.Field("path").Text(); if (FailBackup && target.EndsWith(".bak")) return Json("{\"result\":[7]}");
                Writes.Add((target, args.Field("data").Text()));
            }
            if (method == "add") Adds++;
            return Rpc(new { });
        }
        if (path == "/cgi-bin/luci/")
        {
            if (r.Method != HttpMethod.Post || !body.Contains("luci_password=")) throw new Exception("Login must POST credentials");
            var response = new HttpResponseMessage(HttpStatusCode.Found) { Content = new StringContent("") };
            if (!MissingCookie) response.Headers.Add("Set-Cookie", "sysauth_http=test-cookie; Path=/; HttpOnly");
            return response;
        }
        if (path.Contains("/openclash/"))
        {
            CookieObserved = r.Headers.TryGetValues("Cookie", out var cookies) && cookies.Any(s => s.Contains("test-cookie"));
            var endpoint = path.Split('/').Last();
            if (endpoint == "status") return HtmlStatus ? new(HttpStatusCode.OK) { Content = new StringContent("<html>login</html>") } : Json(JsonSerializer.Serialize(new { clash = Running, core_type = "Meta", cn_port = ApiPort, dase = "fixture-secret" }));
            if (endpoint == "action")
            {
                ServiceCalls++; if (RejectAction) return Json("{\"status\":\"error\"}");
                if (r.Method != HttpMethod.Post) throw new Exception("Mutation must POST");
                Running = !body.Contains("action=stop");
            }
            if (endpoint == "switch_rule_mode" && !IgnoreMode) Mode = body.Split('=')[1];
            return Json("{\"status\":\"success\"}");
        }
        ClashCalls++; SecretObserved = r.Headers.Authorization?.Parameter == "fixture-secret";
        if (path == "/configs") return Json(JsonSerializer.Serialize(new { mode = Mode }));
        if (path.StartsWith("/proxies/"))
        {
            LastProxyPath = r.RequestUri.AbsolutePath;
            if (r.Method == HttpMethod.Put) { selected = JsonDocument.Parse(body).RootElement.GetProperty("name").GetString()!; return new(HttpStatusCode.NoContent); }
            return Json(JsonSerializer.Serialize(new { now = selected }));
        }
        if (path == "/connections") return Json("{\"uploadTotal\":1024,\"downloadTotal\":2048,\"connections\":[{\"id\":\"c1\",\"metadata\":{\"host\":\"example.org\",\"destinationPort\":\"443\",\"sourceIP\":\"192.168.1.2\"},\"chains\":[\"A\"],\"download\":100}]}");
        return Json("{}");
    }
    private static HttpResponseMessage Json(string content) => new(HttpStatusCode.OK) { Content = new StringContent(content, Encoding.UTF8, "application/json") };
    private static HttpResponseMessage Rpc(object content) => Json(JsonSerializer.Serialize(new { result = new object[] { 0, content } }));
}
