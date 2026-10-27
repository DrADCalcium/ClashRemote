using System;
using System.Windows;
using System.Windows.Controls;
using ClashRemote.Core;

namespace ClashRemote.Windows;
public sealed class SubscriptionDialog : Window
{
    public Subscription? Result { get; private set; }
    public SubscriptionDialog(Subscription? sub)
    {
        Title = sub == null ? "添加订阅" : "编辑订阅"; Width = 500; Height = 390; ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        var panel = new StackPanel { Margin = new Thickness(26) }; Content = panel;
        var name = Input("名称", sub?.Name ?? ""); var address = Input("订阅地址", sub?.Address ?? ""); var ua = Input("User-Agent", sub?.UserAgent ?? "clash.meta");
        var enabled = new CheckBox { Content = "启用此订阅", IsChecked = sub?.Enabled ?? true, Margin = new Thickness(0,0,0,16) }; panel.Children.Add(enabled);
        var save = new Button { Content = "保存", IsDefault = true }; panel.Children.Add(save);
        save.Click += (_, _) =>
        {
            if (string.IsNullOrWhiteSpace(name.Text) || !Uri.TryCreate(address.Text, UriKind.Absolute, out var u) || u.Scheme is not ("http" or "https"))
            { MessageBox.Show(this, "请填写名称及有效的 HTTP/HTTPS 订阅地址。"); return; }
            Result = new(sub?.Section ?? "", name.Text.Trim(), address.Text.Trim(), enabled.IsChecked == true, ua.Text.Trim()); DialogResult = true;
        };
        TextBox Input(string label, string value) { panel.Children.Add(new TextBlock { Text = label }); var box = new TextBox { Text = value }; panel.Children.Add(box); return box; }
    }
}
