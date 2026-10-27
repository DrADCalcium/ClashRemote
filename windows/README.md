# Clash Remote for Windows

Windows 10/11 x64 的 OpenClash 遥控器。基于 [DonVitsch/ClashRemote](https://github.com/DonVitsch/ClashRemote) 的 LuCI、UCI、ubus 与 Mihomo 协议逻辑移植，使用 C# / .NET 9 / WPF 重写。原有 macOS 源码保留在仓库中，MIT 许可及原作者版权保留。

## 使用

解压便携包并运行 `ClashRemote.exe`。自包含发行包不要求另外安装 .NET；不需要管理员权限、本机代理内核或额外的路由器代理程序。

1. 添加设备：填写路由器 LuCI 地址、账号、密码。管理地址与 Mihomo 控制端口分开填写。
2. 连接：通过 `/ubus` 登录及 LuCI Cookie 认证，读取 OpenClash 状态、控制端口和 Secret。
3. 在设备控制页启停、重启 OpenClash；总览页切换规则、直连、全局模式。
4. 默认关闭窗口收起到托盘；从托盘菜单退出。后台隐藏时暂停轮询。

## 已实现

- 多设备保存；密码与手工填写的 Secret 使用 Windows DPAPI 当前账户加密。
- 真正的 OpenClash 服务启动、停止、重启，发送命令后轮询路由器状态确认。服务停止后 LuCI 连接仍可用于重新启动。
- 规则、直连、全局模式，并核对 Mihomo 的实际模式。
- 增强、TUN、Mix 接管方式。
- 策略组、Selector 节点选择、单节点和当前组测速（最多 4 个并发）。
- 累计流量、实际计数差值速率、连接列表、关闭指定或全部连接。
- 规则检索、代理集合与规则集合更新。
- 订阅增删改、提交更新；配置切换、读取与编辑。保存前写入 `.clashremote.bak`，保存不自动应用。
- OpenClash 日志最后 600 行、内置面板和路由器管理页入口、托盘快捷操作、窗口置顶。

## 兼容与边界

- 第一版针对 **OpenClash**；原项目的猫猫/UFI、设备端自动故障转移脚本、五套主题尚未移植。
- 路由器须提供 LuCI、ubus HTTP 与相应 rpcd ACL。配置与日志读写需要 `file` RPC 权限；使用无权限账户会显示错误。
- 当前依赖原项目使用的 OpenClash LuCI 接口，包括 `action`、`switch_rule_mode`、`switch_run_mode`、`config_file_list`、`update_config`。旧插件或定制 LuCI 可能缺少这些接口；不会把直连伪装成服务已停止。
- 服务操作会影响整个路由器的代理连接；停止、重启、切配置等操作有界面确认。
- 管理地址与 Mihomo 控制接口的 HTTP/HTTPS 设置相互独立；控制接口默认 HTTP，可在设备设置中启用 HTTPS。
- 配置编辑没有 YAML 语法校验，保存不代表配置可用；应用前应在 OpenClash 检查。备份位于路由器配置文件旁。
- 更新订阅的成功提示只表示命令已提交，须刷新配置和日志确认完成。
- `devices.json` 在 `%LOCALAPPDATA%\ClashRemote.Windows`；备份到其他 Windows 账户无法直接解密密码。
- LAN 请求绕过系统代理，HTTPS 验证证书。HTTP 仅适合可信局域网；没有禁用证书验证的选项。
- 此程序为原生管理客户端，未内嵌 Zashboard；可以打开路由器已安装的面板。功能不宣称与 Zashboard 完全等价。

## 构建与验证

安装 .NET 9 SDK（含 Windows Desktop targeting pack），在 Windows 上执行：

```powershell
./windows/build.ps1
# 仅需在已安装 .NET 9 Desktop Runtime 的机器运行的较小版本：
./windows/build.ps1 -FrameworkDependent
```

输出 `windows/artifacts/ClashRemote-win-x64.zip`。`windows/ClashRemote.Tests` 是无需额外测试框架依赖的协议回归检查，通过可控 HTTP 模拟器验证登录、服务启停及确认、会话过期、模式确认、URL 编码、配置备份和失败分支。模拟通过不等于真实路由器或干净 Windows 实测通过。

开发集成检查可运行 `dotnet run --project windows/ClashRemote.Tests -- --serve`，仅在本机 `127.0.0.1:19180` 提供模拟路由器。应用参数 `--data-dir=<独立目录>` 可隔离测试配置，避免触及日常设备列表。模拟器不应部署到实际网络。

## 来源

原项目及协议参考：`Sources/ClashRemote/Network/OpenClashClient.swift`、`OpenClashService.swift`。Windows 使用原项目图标资源。查看仓库根目录 `LICENSE`。
