# ClashRemote：SwiftOpenUI Windows 移植

`windows-port` 分支保留原项目 Swift 页面与业务逻辑，通过 SwiftOpenUI 的 BackendWin32 运行。完整应用已在 Windows x64 编译、链接并完成逐页切换冒烟检查。它与 `windows-swiftcrossui` 分支独立。

本轮实现了原界面依赖的一批缺失 API，尚未达到与 macOS 逐像素一致。原版基线为 `c5d8831`；此前 Windows 平台桥接基线为 `c232398`。

## 构建和启动

已验证环境：Windows x64、Swift 6.4.1、Visual Studio 2022 Desktop C++、Windows SDK 10.0.26100.0。

```powershell
powershell -NoProfile -File .\scripts\build-windows.ps1
.\.build\x86_64-unknown-windows-msvc\debug\ClashRemote.exe
```

脚本自动加载 C++/Swift 环境，下载 [codelynx/SwiftOpenUI](https://github.com/codelynx/SwiftOpenUI) 固定提交 `4afcacda74dec9e0bae18403c4427b05c8586943` 到 `.build/SwiftOpenUI-pinned`，依次应用两个补丁：

- `patches/swiftopenui-swift64-winsdk.patch`：Swift 6.4 下 WinSDK 头文件、类型及 DPI 宏兼容。
- `patches/swiftopenui-windows-api.patch`：本轮新增的共享 API 和 Win32 行为实现。

重复构建会检查补丁是否已应用。`SWIFTOPENUI_PATH` 可指向相同提交的本地克隆。直接运行 `swift build` 不会替你应用补丁，请优先使用脚本。使用 `--build-system native` 绕过 Swift 6.4 本机默认引擎的资源目录 Touch 问题；该开关已被 Swift 标为弃用。

演示模式 `ClashRemote.exe --demo` 使用样例数据，不读取保存的路由器列表或写回设备/本地配置。普通启动保留原项目的实际连接行为。

## 本轮 API 实现

| 范围 | 实现 |
| --- | --- |
| 按钮 | SwiftUI 形态的自定义 ButtonStyle、Configuration、role、按压状态；鼠标/键盘按下反馈与动作；switch 外观和 tint |
| 布局 | AnyLayout、HStackLayout、VStackLayout；ViewBuilder 形态的 LazyVStack/LazyVGrid；自适应列数随宽度重排、最大列宽；分栏样式；CGFloat 间距重载 |
| 文本和输入 | 日期 Text、ContentUnavailableView；纵向多行 TextField、行数范围、密码样式和原生输入范围；minimumScaleFactor 随宽度缩小并恢复字体 |
| 绘图 | Path 二次曲线转三次曲线、currentPoint、圆角参数、非零环绕命中测试；默认 Shape 填充、stroke 重载；图片插值 |
| 交互 | contentShape 的原生命中区域、onHover 进入/离开、右键及 Shift+F10 菜单、菜单箭头可见性、radioGroup |
| 外观与辅助功能 | brightness 可见反馈、背景形状、彩色删除线、controlSize、配色环境；MSAA 名称/值/提示/状态/角色与组合元素 |

补丁位于仓库内，可以审阅和重新应用；未把修改隐藏在本地构建缓存里。`@MainActor` 适配保留在应用视图代码中，Windows 暂用 Swift 5 语言模式，因此仍有将来 Swift 6 严格并发模式下需要处理的警告。macOS 继续使用 Apple SwiftUI/AppKit/Charts，本轮没有进行 macOS 编译回归。

## 检查

```powershell
# 独立 Win32 API 测试包，不依赖 macOS 专用的应用测试
powershell -NoProfile -File .\scripts\build-windows.ps1 -APITests

# 原网络/加密实现 + 本机模拟 HTTP 服务
python .\scripts\test-windows-core.py

# 原应用七个页面与设备编辑窗口的切换冒烟检查
$env:CLASHREMOTE_UI_SMOKE_RESULT="$PWD\windows-openui-smoke-result.json"
.\.build\x86_64-unknown-windows-msvc\debug\ClashRemote.exe --ui-smoke-test
```

API 测试实际创建隐藏的 HWND 并发送原生消息。10 项覆盖二次曲线、曲线/空洞命中、横纵布局、自适应网格重排、MSAA 字符串、悬停回调、键盘按压和单次触发、多行/密码输入、字体缩放恢复、窄窗口分栏。日志为 `windows-api-tests.log`。

核心测试实际执行原项目 Swift 代码的 CNG 已知向量、流量数字解析、WinHTTP 重定向/Cookie/UTF-8、模拟 LuCI/ubus 登录和协议拒绝。5 项全部通过。模拟服务只监听 `127.0.0.1` 随机端口，不访问真实路由器。未通过 Python 入口启动时，两项网络测试会明确跳过。

UI 冒烟检查使用样例数据，依次切换总览、节点、订阅、规则、设备控制、本地配置、设置，并打开设备编辑器；成功后 JSON 的 `completed` 为 true、`pages` 含八项，进程返回 0。这证明各分支能够在 Win32 中创建并切换，不能替代截图比对、鼠标操作验收或真实路由器测试。

## 打包

```powershell
powershell -NoProfile -File .\scripts\package-windows.ps1
```

输出 `dist/ClashRemote-SwiftOpenUI-win-x64.zip`，包含 EXE、资源、Swift runtime DLL 和许可。解压后从同一文件夹运行 EXE，不要只复制 EXE。可用 `-SwiftRuntimePath` 指定其他 Swift runtime 目录。重新打包前请移走已有的同名输出目录，避免混入旧 DLL。使用系统 Win32 控件，无需 Windows App Runtime。已在本机使用仅含系统目录的 PATH 检查打包程序；未在全新 Windows 系统上验证。

## 已知差异

- `firstTextBaseline` 暂映射到底边对齐；字体、系统图标、控件尺寸与 macOS 存在差异，未完成逐像素复刻。
- brightness 使用黑/白透明层混合，彩色删除线按原生文本行高绘制，与 SwiftUI 的精确效果可能不同。
- MSAA 属性与组合已接入，尚未实现完整 UI Automation 自定义提供者；未进行屏幕阅读器人工验收。
- 日期 relative/timer 在视图重建时计算，不提供独立的实时刷新定时器。
- Builder 形态的 Lazy 容器当前一次创建子项，不是按可见区域虚拟化；大量节点的性能待测。
- Windows 流量图沿用 Canvas 折线替代 Apple Charts；窗口位置/尺寸记忆尚未实现；AppStorage 跨视图同步与重启仍待验收。
- OpenClash 服务启停、重启、规则/直连/全局切换保留原项目逻辑与 Windows 网络桥接，但本轮没有连接真实路由器验证。
