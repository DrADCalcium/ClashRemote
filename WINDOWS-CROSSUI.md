# Clash Remote · SwiftCrossUI Windows 预览版

从刚 fork 的原始提交 `c5d8831` 新建 `windows-swiftcrossui` 分支。Windows 界面以 SwiftCrossUI / WinUI 3 重写，保留原 Swift 的 AppState、设备存储、OpenClash / 猫猫网络与业务实现。

## 使用

解压整个文件夹，运行 `ClashRemote.exe`。Swift 运行库和资源文件随包提供，不需要安装 Swift 开发工具。

此预览版依赖 **Windows App Runtime 1.5-preview1（x64）**。这是固定版本 swift-winui 所依赖的运行时；本机的 1.7 / 1.8 不能替代它。若尚未安装，请先运行包内 `prerequisites/windowsappruntimeinstall-x64.exe`（如果提供），或从微软下载：[x64 安装程序](https://aka.ms/windowsappsdk/1.5/1.5.240205001-preview1/windowsappruntimeinstall-x64.exe)。安装程序须保留有效的 Microsoft Corporation 数字签名。

界面“路由器”区域点击 `+`，填写设备名称、纯 IP / 主机名、LuCI 端口、用户名和密码，选择 OpenClash 或猫猫后保存连接。使用当前 Windows 账户的应用数据目录保存设备与配置；设备密码沿用原项目的本地 JSON 存储方式。

可选命令：

```powershell
.\ClashRemote.exe --demo           # 示例数据预览，不连接路由器
.\ClashRemote.exe --ui-smoke-test  # 依次创建八个页面，保存结果后退出
```

## 页面与功能

- 总览：当前节点、服务状态、上下行速率、流量折线、连接数、内存、规则/全局/直连切换。
- 节点：策略组选择、搜索、地区筛选、延迟排序、单节点/批量测速、选择节点、屏蔽与自动切换。
- 设备控制：启动、停止、重启，流量接管方式，嗅探等设置，配置切换和更新，设备守护管理及切换历史。
- 订阅：读取、添加、编辑、删除、更新设备订阅。
- 规则：检索、匹配检查、添加设备规则、收藏到本地。
- 本地配置：筛选、地区排除、来源白名单、阈值、屏蔽列表、订阅收藏、本地域名规则及同步。
- 设置：文字大小、密度、信息显示、启动页面、自动连接、刷新间隔、窗口置顶、五种主题配色。
- 路由器：多设备添加、编辑、连接和删除。

示例模式禁止设备操作；总览中的模拟流量仅用于预览。常规模式中的折线使用设备真实采样。

## 构建

已验证 Windows x64、Swift 6.4.1、Visual Studio 2022 C++ 和 Windows SDK 10.0.26100.0。Windows 分支采用 Swift 5 语言模式。原 macOS 界面仍由原 SwiftUI 文件构建，尚未在本次环境验证 macOS 构建。

```powershell
powershell -NoProfile -File .\scripts\build-windows.ps1
python .\scripts\test-windows-core.py
powershell -NoProfile -File .\scripts\package-windows.ps1 -SkipBuild
```

`build-windows.ps1 -Tests` 也可运行测试；通过 Python 入口会启动并关闭仅监听 `127.0.0.1` 随机端口的模拟路由器，启用全部网络测试。直接运行 Swift 测试时，没有模拟服务的用例会明确跳过。

固定 [SwiftCrossUI](https://github.com/moreSwift/swift-cross-ui) 提交 `0f3ec3958b79cdc39a1a3e604516b71ab33a9043`。依赖锁定文件位于 `Package.resolved`。未沿用 SwiftOpenUI 的兼容层或修改其框架。WinHTTP 和 Windows CNG 平台桥接经过移入复核，用于替代 Apple Network / CommonCrypto API。

构建脚本会加载 VS C++ 环境，使用 SwiftPM native 构建引擎避开本机默认引擎的资源目录问题。native 选项已被 Swift 标为弃用，后续工具链升级需要复核。未安装 GTK 的检测警告不影响 WinUI 后端。

## 验证与限制

6 项自动测试覆盖：加密已知向量、流量计数边界、HTTP 302 和多 Cookie、UTF-8 请求、原 OpenClash 登录、服务启动/停止/重启与三种模式切换。服务测试验证请求、Cookie 与 API 密钥，并检查模拟设备刷新后的状态。测试只连接本机模拟服务，真实路由器尚未联调。

`--ui-smoke-test` 实际启动 WinUI，依次创建总览、节点、订阅、规则、设备控制、本地配置、设置和路由器页面；各页停留一段时间，让布局和异步刷新完成。结果写入临时目录的 `ClashRemote-ui-smoke.json`，可用环境变量 `CLASHREMOTE_UI_SMOKE_RESULT` 指定结果文件；完成时 `completed` 为 true，`pages` 包含八页。它能检查页面创建和切换崩溃，不能代替鼠标、键盘或真实设备测试。

目前是可运行的开发预览版，包内程序采用 debug 构建并移除调试信息。总览已实际显示并目视检查，保留原版侧栏、卡片、猫图和配色。原生控件、字体、图标和图表细节仍有差异，尚未达到逐像素一致。自动化鼠标检查受当前桌面激活失败影响，其他页面的控件交互还需补充验证。

窗口尺寸/位置记忆尚未移植。WinUI 后端的最小窗口尺寸限制尚未实现，窗口过窄时可能出现内容拥挤。主题目前保留配色切换，未复刻原版每种主题的独立布局。系统区域信息读取仍有上游警告，时间显示可能沿用英文格式。

运行包在当前已安装所需 WinUI 运行时的机器上验证；尚未在全新 Windows 虚拟机验证。首次使用请保留同目录全部 DLL 和两个 `.resources` 文件夹。
