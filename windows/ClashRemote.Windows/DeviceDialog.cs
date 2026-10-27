using System;
using System.Windows;
using System.Windows.Controls;
using ClashRemote.Core;

namespace ClashRemote.Windows;
public sealed class DeviceDialog : Window
{
    public RouterProfile? Result { get; private set; }
    public DeviceDialog(RouterProfile? original)
    {
        Title = original == null ? "添加 OpenClash 路由器" : "编辑设备"; Width = 460; Height = 670; ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        var panel = new StackPanel { Margin = new Thickness(26) }; Content = panel;
        var name = Input("设备名称", original?.Name ?? "OpenWrt");
        var address = Input("路由器管理地址", original?.Address ?? "http://192.168.1.1");
        var user = Input("用户名", original?.Username ?? "root");
        panel.Children.Add(new TextBlock { Text = "登录密码" });
        var password = new PasswordBox(); panel.Children.Add(password);
        var port = Input("Mihomo 控制端口（连接后会自动读取）", (original?.ControllerPort ?? 9090).ToString());
        var tls = new CheckBox { Content = "Mihomo 控制接口使用 HTTPS", IsChecked = original?.ControllerUseHttps ?? false, Margin = new Thickness(0,0,0,12) }; panel.Children.Add(tls);
        panel.Children.Add(new TextBlock { Text = "Secret（可选，连接后会自动读取）" });
        var secret = new PasswordBox(); panel.Children.Add(secret);
        if (original != null)
        {
            password.Password = WindowsSecrets.Unprotect(original.ProtectedPassword);
            secret.Password = WindowsSecrets.Unprotect(original.ProtectedSecret);
        }
        panel.Children.Add(new TextBlock { Text = "凭据使用当前 Windows 账户加密，仅保存在本机。\n使用 HTTP 时，请在可信局域网中连接。", TextWrapping = TextWrapping.Wrap, Foreground = System.Windows.Media.Brushes.SlateGray, Margin = new Thickness(0,4,0,14) });
        var save = new Button { Content = "保存设备", Style = (Style)FindResource("Primary"), IsDefault = true };
        panel.Children.Add(save);
        save.Click += (_, _) =>
        {
            try
            {
                if (string.IsNullOrWhiteSpace(name.Text) || string.IsNullOrWhiteSpace(user.Text)) throw new ArgumentException("名称和用户名不能为空。");
                var uri = RouterProfile.ValidateAddress(address.Text);
                if (!int.TryParse(port.Text, out var n) || n < 1 || n > 65535) throw new ArgumentException("控制端口应在 1–65535 之间。");
                Result = new RouterProfile { Id = original?.Id ?? Guid.NewGuid(), Name = name.Text.Trim(), Address = uri.AbsoluteUri.TrimEnd('/'), Username = user.Text.Trim(), ControllerPort = n, ControllerUseHttps = tls.IsChecked == true,
                    ProtectedPassword = WindowsSecrets.Protect(password.Password), ProtectedSecret = WindowsSecrets.Protect(secret.Password) };
                DialogResult = true;
            }
            catch (Exception e) { MessageBox.Show(this, e.Message, "无法保存", MessageBoxButton.OK, MessageBoxImage.Warning); }
        };
        TextBox Input(string label, string value)
        {
            panel.Children.Add(new TextBlock { Text = label });
            var input = new TextBox { Text = value }; panel.Children.Add(input); return input;
        }
    }
}
