using System.Text;
using System.IO;
using ClashRemote.Core;
using ClashRemote.Windows;

if (args.Length == 2 && args[0] == "--fixture")
{
    new ProfileStore(args[1]).Save([new RouterProfile { Name = "本机模拟路由器 · 测试专用", Address = "http://127.0.0.1:19180", ControllerPort = 19180, ProtectedPassword = WindowsSecrets.Protect("fixture-password") }]);
    Console.WriteLine("Created local-only integration fixture"); return;
}

var secret = "fixture-password-测试";
var encrypted = WindowsSecrets.Protect(secret);
if (encrypted.Contains(secret) || WindowsSecrets.Unprotect(encrypted) != secret) throw new Exception("DPAPI roundtrip failed");
if (encrypted == WindowsSecrets.Protect(secret)) throw new Exception("Expected randomized encryption");
if (WindowsSecrets.Protect("") != "" || WindowsSecrets.Unprotect("") != "") throw new Exception("Empty credential failed");
Console.WriteLine("PASS Windows current-user DPAPI encryption and decryption");
var dir = Path.Combine(Path.GetTempPath(), "ClashRemote-check-" + Guid.NewGuid().ToString("N"));
try
{
    var store = new ProfileStore(dir);
    if (store.Load().Count != 0) throw new Exception("Expected empty store");
    var p = new RouterProfile { Name = "测试路由器", ProtectedPassword = encrypted };
    store.Save([p]);
    var saved = store.Load().Single();
    var raw = File.ReadAllText(Path.Combine(dir, "devices.json"));
    if (saved.Id != p.Id || WindowsSecrets.Unprotect(saved.ProtectedPassword) != secret || raw.Contains(secret)) throw new Exception("Store roundtrip failed");
    store.Save([]);
    if (store.Load().Count != 0 || File.Exists(Path.Combine(dir,"devices.json.tmp"))) throw new Exception("Atomic save failed");
    Console.WriteLine("PASS Profile storage roundtrip, encrypted persistence, and atomic replacement");
}
finally
{
    // This uniquely named directory contains only fixtures created by this check.
    if (Directory.Exists(dir)) Directory.Delete(dir, true);
}
