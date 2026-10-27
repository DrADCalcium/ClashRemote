# Windows Swift 移植实验

**状态：核心代码在 Windows 编译并通过测试；SwiftOpenUI 完整界面尚未编译通过，没有可交付的桌面 EXE，也尚未实现 UI 一比一复刻。**

## 基线与范围

从原版 `c5d8831`（1.4）重新开始。此前 C# 实现已由 `0841689` 回退；可通过历史提交 `e085ff8` 或本地 `archive/windows-csharp` 分支恢复。`main` 保持原版。

本次保留原 Swift 页面、模型、OpenClash/LuCI/ubus 服务调用和业务逻辑，添加条件编译及必要平台桥接。没有用其他 UI 框架重写页面。

- Windows HTTP 改用 WinHTTP，显式直连，不自动跟随重定向或保存 Cookie；保留 LuCI 登录响应中的多个 Set-Cookie。HTTPS 保持系统证书验证。
- CommonCrypto 调用通过小型 C 桥接转到 Windows CNG，覆盖 MD5、SHA256、HMAC-MD5，原 UFI 签名流程保留。
- AppKit 图片、浏览器打开、窗口置顶增加 Windows 入口；这些界面相关入口还没有运行验证。
- CoreFoundation 布尔计数检测增加 Windows Foundation 实现，避免将 JSON true 作为流量 1。
- AppState 默认参数的对象创建移到主线程初始化器内部。
- macOS 继续使用 SwiftUI/AppKit/Charts 和 Swift 6 模式；Windows 实验使用 Swift 5 语言模式，尚有线程隔离警告。

## 已验证环境

Windows x64；Swift 6.4.1；Visual Studio 2022 C++；Windows SDK 10.0.26100.0。

UI 依赖为 [codelynx/SwiftOpenUI](https://github.com/codelynx/SwiftOpenUI)，固定提交 `4afcacda74dec9e0bae18403c4427b05c8586943`，使用 BackendWin32。这里不是 OpenSwiftUIProject/OpenSwiftUI。

## 复现核心测试

在仓库目录运行：

```powershell
python .\scripts\test-windows-core.py
```

脚本仅在 `127.0.0.1` 随机端口启动模拟 HTTP 服务，运行后关闭；不连接真实路由器、不读取本机设备列表。Python 3 仅用于测试服务。测试代码的会话和密码都是固定的模拟值。

实际执行 5 项 XCTest，全部通过、无跳过：

1. Swift 调用 Windows CNG，匹配 MD5、SHA256、HMAC-MD5 已知向量。
2. 流量计数拒绝布尔、负数、小数，保留 0、1 及 Int64 上界字符串。
3. WinHTTP 返回原始 302 和多条 Cookie，UTF-8 POST、请求头、响应解析正确，Cookie 不自动发送到后续请求。
4. 原 `OpenClashClient.login()` 经 Windows 传输完成模拟 ubus 和 LuCI 登录。
5. 不支持的 URL 协议返回错误。

也可运行 `powershell -NoProfile -File .\scripts\build-windows.ps1 -CoreChecks`。未通过测试服务入口运行时，两项网络测试会明确跳过。日志为 `windows-core-tests.log`。

核心目标直接编译原项目的 AppState、Models（不含外观主题）、Network 和 Store 源文件，不使用重新实现的网络业务替身。模拟服务只用于响应测试请求。

## 复现完整 UI 构建尝试

```powershell
powershell -NoProfile -File .\scripts\build-windows.ps1
```

脚本加载 Visual Studio C++ 环境、定位 Swift，自动下载固定版本 SwiftOpenUI 到忽略的 `.build/SwiftOpenUI-pinned`，并应用 `patches/swiftopenui-swift64-winsdk.patch`。也支持 `SWIFTOPENUI_PATH` 指向同一提交的已有本地克隆。

补丁修复 Swift 6.4 Clang 模块下 WinSDK 类型可见性及 DPI 宏兼容性。SwiftOpenUI、其符号资源、CWin32Bridge 和 BackendWin32 已实际编译通过。使用 `--build-system native`，避开本机新版默认构建引擎对资源目录 Touch 操作的失败。该选项已被 Swift 标为弃用。

**当前上述完整 UI 命令预期失败。** `windows-build.log` 包含完整编译诊断。最后一次构建仍有 259 个去重的源码位置诊断，其中很多是同一缺失接口导致的连带错误，不代表 259 个独立功能缺失。

## 一比一复刻的剩余障碍

| 原代码使用项 | 当前障碍 |
| --- | --- |
| 自定义 ButtonStyle、Configuration、isEnabled 环境 | SwiftOpenUI 的按钮样式契约不同，不能直接套用原样式 |
| AnyLayout、HStackLayout、VStackLayout、自适应网格 | 缺少接口或参数形态不兼容，影响页面布局 |
| Menu、TextField 轴向/行数、日期 Text | 初始化器和行为不兼容 |
| tint、background、contentShape、onHover、accessibility 等 | 部分接口缺失或重载不同，影响颜色、命中区域、交互及辅助功能 |
| Path 二次曲线、圆角参数 | 绘图 API 不完整，原插画不能直接构建 |
| @MainActor 视图与 @Observable 状态 | SwiftOpenUI View/App 协议及回调的线程隔离约定不同 |
| Swift Charts | Windows 无 Apple Charts；已有保留真实采样数据的 Canvas 折线尝试，但轴、填充等尚未达到原图一致 |
| 字体、系统图标、原生控件、窗口偏好 | 还需实际渲染和交互验证；窗口位置/尺寸记忆尚未实现 |

没有为缺失修饰器批量添加“返回 self”的空实现来掩盖错误。AppStorage 桥接提供 UserDefaults 和 SwiftOpenUI State 存储接入，但跨视图同步与重启行为尚未实测。

继续实现原 UI，需要先补齐 SwiftOpenUI 的样式、布局、绘图及线程契约，再逐页编译并验证窗口缩放、主题、字体、图标和交互。当前结果证明了原 Swift 业务层的 Windows 可编译性与部分平台 API 行为，不能证明完整功能或 UI 已移植成功。真实路由器服务启停、模式切换和 macOS 回归尚未测试。
