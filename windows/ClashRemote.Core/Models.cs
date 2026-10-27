using System.Text.Json;
using System.Text.Json.Serialization;

namespace ClashRemote.Core;

public sealed record RouterProfile
{
    public Guid Id { get; init; } = Guid.NewGuid();
    public string Name { get; init; } = "OpenWrt";
    public string Address { get; init; } = "http://192.168.1.1";
    public string Username { get; init; } = "root";
    public string ProtectedPassword { get; init; } = "";
    public int ControllerPort { get; init; } = 9090;
    public bool ControllerUseHttps { get; init; }
    public string ProtectedSecret { get; init; } = "";
    public override string ToString() => Name;
    [JsonIgnore] public Uri BaseUri => ValidateAddress(Address);

    public static Uri ValidateAddress(string address)
    {
        if (!address.Contains("://")) address = "http://" + address;
        if (!Uri.TryCreate(address.Trim().TrimEnd('/') + "/", UriKind.Absolute, out var uri)
            || uri.Scheme is not ("http" or "https") || string.IsNullOrEmpty(uri.Host)
            || !string.IsNullOrEmpty(uri.UserInfo) || uri.AbsolutePath != "/" || uri.Query.Length > 0 || uri.Fragment.Length > 0)
            throw new ArgumentException("请输入路由器地址，例如 http://192.168.1.1 或 https://router:443，不要附加后台路径。");
        return uri;
    }
}

public sealed record RouterStatus(bool Running, bool Enabled, string Hostname, string Model, string Core,
    string Mode, string Capture, string ConfigPath, int ControllerPort);
public sealed record ProxyNode(string Name, string Type, int? Delay, bool? Alive);
public sealed record ProxyGroup(string Name, string Type, string Selected, IReadOnlyList<ProxyNode> Nodes)
{
    public bool CanSelect => Type.Equals("Selector", StringComparison.OrdinalIgnoreCase);
    public override string ToString() => $"{Name}  ·  {Selected}";
}
public sealed record ConnectionRow(string Id, string Source, string Destination, string Network,
    string Rule, string Chain, long Upload, long Download);
public sealed record ConnectionsSnapshot(long Upload, long Download, IReadOnlyList<ConnectionRow> Rows);
public sealed record RuleRow(string Type, string Payload, string Proxy);
public sealed record ConfigFile(string Name, string Path, bool Current)
{
    public override string ToString() => (Current ? "● " : "") + Name;
}
public sealed record Subscription(string Section, string Name, string Address, bool Enabled, string UserAgent);
public sealed record ProviderRow(string Name, string Type, string UpdatedAt);

public static class JsonExtensions
{
    public static JsonElement Field(this JsonElement e, string key) =>
        e.ValueKind == JsonValueKind.Object && e.TryGetProperty(key, out var value) ? value : default;
    public static string Text(this JsonElement e) => e.ValueKind switch
    {
        JsonValueKind.String => e.GetString() ?? "",
        JsonValueKind.Number or JsonValueKind.True or JsonValueKind.False => e.ToString(),
        _ => ""
    };
    public static bool Flag(this JsonElement e) => e.Text().ToLowerInvariant() is "true" or "1" or "yes" or "on";
    public static long Number(this JsonElement e, long fallback = 0) => long.TryParse(e.Text(), out var n) ? n : fallback;
    public static IEnumerable<JsonElement> Items(this JsonElement e) => e.ValueKind == JsonValueKind.Array ? e.EnumerateArray() : [];
    public static IEnumerable<JsonProperty> Properties(this JsonElement e) => e.ValueKind == JsonValueKind.Object ? e.EnumerateObject() : [];
}
