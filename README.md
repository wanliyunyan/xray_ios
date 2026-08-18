# Xray iOS

English documentation: [README.en.md](README.en.md)

一个基于 SwiftUI、Network Extension 和 [LibXray](https://github.com/wanliyunyan/LibXray) 的 iOS Xray TUN 示例应用。

这是一个面向开发者的最小可运行示例，不是开箱即用的商业 VPN 客户端。应用从 VLESS 分享链接生成 Xray 配置，通过 `PacketTunnel` 扩展接管系统流量，并提供基础的路由、诊断、资源管理和配置分享功能。

## 功能

- 从剪贴板导入分享链接。
- 使用摄像头扫描二维码导入分享链接。
- 显示节点 ID、服务器地址和端口；IPv4 地址在界面中会脱敏显示。
- 通过 iOS `PacketTunnelProvider` 启动和停止 Xray TUN。
- 支持两种路由模式：
  - **全局代理**：TCP/UDP 流量最终交给代理出站。
  - **智能分流**：安装 geo 文件后，广告域名阻断，中国和私有域名/IP 直连，其余流量走代理；没有 geo 文件时跳过依赖 geo 的规则。
- 下载、替换和清理 `geoip.dat`、`geosite.dat`。
- 显示通过 Xray Metrics 读取的上下行流量。
- 使用 `https://1.1.1.1` 测试代理延迟。
- 生成当前分享链接的二维码用于分享。
- 显示内置 Xray Core 版本。

## 环境要求

- iOS 17.0 或更高版本。
- macOS 和 Xcode 16 或更高版本。
- 可安装并运行 Network Extension 的真实 iPhone。模拟器不能完整验证 Packet Tunnel 和摄像头扫码流程。
- Apple Developer 账号，以及 Network Extension 和 App Groups 能力对应的签名权限。

工程通过 Swift Package Manager 引入 LibXray：

- Repository: `https://github.com/wanliyunyan/LibXray.git`
- Minimum version: `26.7.28`

## 构建与签名

1. 克隆仓库并打开 `Xray.xcodeproj`。

   ```bash
   git clone https://github.com/wanliyunyan/xray_ios.git
   cd xray_ios
   open Xray.xcodeproj
   ```

2. 修改根目录的 [`Config.xcconfig`](Config.xcconfig)，设置你自己的应用标识：

   ```xcconfig
   APP_ID = com.example.Xray
   ```

   `APP_ID` 会同时用于主 App、Packet Tunnel 扩展、App Group 和 VPN Provider 标识。主 App 和 `PacketTunnel` 两个 Target 必须使用同一个标识前缀。

3. 在 Xcode 的 **Signing & Capabilities** 中为两个 Target 配置你自己的 Team 和签名资料，并确认包含：

   - `Network Extensions`：`Packet Tunnel Provider`
   - `App Groups`：`group.$(APP_ID)`

   当前工程文件中的 Team ID 仅是原作者的开发配置，不能直接用于你的账号。

4. 选择 `Xray` Scheme 和已连接的 iPhone，构建并运行。首次启动时，系统会请求 VPN 配置许可；扫码功能首次使用时会请求摄像头权限。

## 运行测试

仓库包含不依赖真实 Packet Tunnel 的单元测试，可在 iOS 模拟器中运行：

```bash
xcodebuild test \
  -project Xray.xcodeproj \
  -scheme Xray \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  CODE_SIGNING_ALLOWED=NO
```

如果本机没有名为 `iPhone 16 Pro` 的模拟器，请将 destination 改为已安装的设备名称。单元测试覆盖端口会话状态、VPN 生命周期状态、流量解析、分享链接解析和 geo 文件事务；Packet Tunnel 启停、`utun` 文件描述符及摄像头仍需在真机验证。

## 使用流程

1. 准备一个分享链接。当前仓库明确验证过的是 VLESS，例如：

   ```text
   vless://<uuid>@<host>:<port>?security=none&encryption=none&type=tcp
   ```

2. 打开右上角的更多菜单，使用系统提供的 **粘贴** 操作，或选择 **扫描二维码**。链接会保存到 App Group 的 `UserDefaults`，下次打开应用可以直接使用上次配置。

3. 根据需要选择 **全局代理** 或 **智能分流** 模式。

4. 在首次使用智能分流模式前，从右上角更多菜单进入 **中国大陆分流资源** 下载文件。应用会从以下地址下载文件，并保存到 App Group 共享目录：

   - `geoip.dat`: `Loyalsoldier/v2ray-rules-dat`
   - `geosite.dat`: `v2fly/domain-list-community` 发布的 `dlc.dat`（下载后重命名为 `geosite.dat`）

5. 点击连接。应用会生成包含 TUN、DNS、路由、统计和 Metrics 的 Xray JSON，把配置传递给 Packet Tunnel 扩展，由扩展注入系统创建的 `utun` 文件描述符后启动 Xray。

6. 连接后可以查看连接时长和上下行流量。Ping 由主 App 进程中的 LibXray 使用独立 SOCKS 配置完成，VPN 的 Xray 则运行在 Packet Tunnel 扩展进程中。VPN 连接时界面会隐藏手动刷新入口，建议在未连接时执行延迟测试。

7. 从右上角更多菜单选择 **分享当前配置**，可以把当前链接以二维码形式展示。更新或清空 geo 文件后，如果 VPN 已连接，应用会自动重启隧道以加载新资源。

## 工作原理

```text
分享链接
   │
   ▼
XrayCoreClient
   └─ LibXray.convertShareLinksToXrayJson
   │
   ▼
XrayConfigurationBuilder
   ├─ TUN 入站（tun-in）
   ├─ Metrics HTTP 服务（127.0.0.1:<动态端口>）
   ├─ 路由、DNS、统计和 geo 资源环境变量
   └─ proxy / direct / block 出站
   │
   ▼
PacketTunnelManager.startVPNTunnel(options:)
   │
   ▼
PacketTunnelProvider
   ├─ 配置 IPv4/IPv6 默认路由和 DNS
   ├─ 查找 Network Extension 创建的 utun FD
   ├─ 注入 env.xray.tun.fd
   └─ LibXrayRuntime.start → isXrayRunning
   ```

主 App 和扩展使用同一个 App Group。分享链接和本地服务端口保存在 App Group 的 `UserDefaults` 中；延迟测试配置写入 App Group 根目录的 `config.json`；Packet Tunnel 的运行配置通过 `startVPNTunnel(options:)` 一次性传递，不会落盘。geo 资源位于 `Library/Application Support/Xray/assets`。

## 注意事项与已知限制

- 这是示例工程，未提供节点订阅、配置编辑器、后台更新、日志界面或多配置管理。
- 当前只明确测试过 VLESS 分享链接；VMess、Trojan、Shadowsocks 等格式是否可用取决于 LibXray 的转换实现，仓库没有提供对应测试保证。
- Network Extension 需要正确的 App ID、Provisioning Profile、Capabilities 和用户授权；签名配置错误时应用无法建立隧道。
- geo 文件和 Ping 都需要网络访问。geo 下载地址指向 GitHub；Ping 的目标地址固定为 `https://1.1.1.1`，超时时间为 30 秒。
- VPN 使用 IPv4 `10.131.0.2/30`、IPv6 `fd00:131::2/126` 和 MTU 1500，并把默认路由交给隧道；系统 VPN 配置同时设置了 `excludeLocalNetworks = true`。
- 当前代码没有在 IPv6-only 网络上进行完整验证；如果遇到 IPv6 环境问题，请重点检查 `PacketTunnelProvider.makeTunnelNetworkSettings()` 和 Xray TUN 配置。
- 切换路由模式、更新 geo 文件或清空 geo 文件时，已连接的 VPN 会重启。
- 分享链接通常包含节点凭据，并会持久化到 App Group 的 `UserDefaults`；延迟测试还会在 App Group 根目录生成 `config.json`。请勿在不受信任的测试设备上导入生产凭据。
- 仓库当前没有声明开源许可证。发布或二次分发前，请先确认项目作者和 LibXray 的许可证要求。

## 目录结构

```text
.
├── Xray/                         # SwiftUI 主 App、配置构建和 VPN 管理
│   ├── DashboardView.swift
│   ├── AppSessionState.swift
│   ├── VPNLifecycleState.swift
│   ├── XrayConfigurationBuilder.swift
│   ├── XrayCoreClient.swift
│   ├── PacketTunnelManager.swift
│   ├── XrayService.swift
│   ├── AppGroupStore.swift
│   ├── ShareLinkParser.swift
│   ├── SharedConfigurationFileStore.swift
│   ├── IPAddressFormatter.swift
│   ├── VPNConnectionControlView.swift
│   ├── VPNRoutingModePickerView.swift
│   ├── GeoAssetDownloadView.swift
│   ├── GeoAssetService.swift
│   ├── LatencyTestView.swift
│   ├── TrafficStatistics.swift
│   ├── TrafficStatisticsView.swift
│   ├── QRCodeScannerView.swift
│   ├── ConfigurationShareView.swift
│   ├── ConnectionDurationView.swift
│   ├── LabeledValueRow.swift
│   ├── PrimaryActionButtonStyle.swift
│   ├── XrayVersionView.swift
│   └── XrayApp.swift
├── PacketTunnel/                 # Network Extension，负责 utun 和 Xray 生命周期
│   └── PacketTunnelProvider.swift
├── Shared/                       # 主 App 与扩展共享的运行时和常量
│   ├── LibXrayRuntime.swift
│   └── AppConstants.swift
├── XrayTests/                    # 可在 iOS 模拟器运行的单元测试
│   ├── AppSessionStateTests.swift
│   ├── VPNLifecycleStateTests.swift
│   ├── TrafficStatisticsParserTests.swift
│   ├── ShareLinkParserTests.swift
│   └── GeoAssetServiceTests.swift
├── Config.xcconfig               # APP_ID 和构建配置
└── Xray.xcodeproj/               # Xcode 工程和共享 Scheme
    ├── project.pbxproj
    └── xcshareddata/xcschemes/Xray.xcscheme
```

## 代码格式化

项目使用 SwiftFormat，可执行：

```bash
swiftformat . --swift-version 6
```
