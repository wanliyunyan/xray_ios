# Xray iOS

A minimal iOS example that combines SwiftUI, Network Extension, and [LibXray](https://github.com/wanliyunyan/LibXray) to run Xray in a TUN-based Packet Tunnel.

This repository is intended for developers and is not a production-ready VPN client. The app converts a VLESS share link into an Xray configuration, starts Xray inside a `PacketTunnel` extension, and exposes basic routing, diagnostics, asset management, and configuration sharing.

## Features

- Import a share link from the clipboard.
- Scan a QR code with the camera.
- Show the node ID, server address, and port; IPv4 addresses are masked in the UI.
- Start and stop Xray TUN through an iOS `PacketTunnelProvider`.
- Two routing modes:
  - **Global Proxy** (`全局代理`): TCP/UDP traffic ultimately uses the proxy outbound.
  - **Smart Routing** (`智能分流`): with geo assets installed, ad domains are blocked, China/private domains and IPs use direct access, and the remaining traffic uses the proxy. Geo-dependent rules are skipped when assets are absent.
- Download, replace, and remove `geoip.dat` and `geosite.dat`.
- Display cumulative upload and download totals for the TUN inbound through Xray Metrics.
- Measure proxy latency through `https://cp.cloudflare.com/` when a configuration is available and the VPN is fully disconnected.
- Render the most recently saved share link as a QR code.
- Display the embedded Xray Core version.

## Requirements

- iOS 17.0 or later.
- macOS and Xcode 16 or later.
- A physical iPhone for complete Packet Tunnel and camera testing. The simulator cannot fully validate these flows.
- An Apple Developer account with signing permissions for Network Extension and App Groups.

The project uses Swift Package Manager for LibXray:

- Repository: `https://github.com/wanliyunyan/LibXray.git`

## Build and signing

1. Clone the repository and open `Xray.xcodeproj`.

   ```bash
   git clone https://github.com/wanliyunyan/xray_ios.git
   cd xray_ios
   open Xray.xcodeproj
   ```

2. Edit [`Config.xcconfig`](Config.xcconfig) and set an application identifier you control:

   ```xcconfig
   APP_ID = com.example.Xray
   ```

   `APP_ID` is used to derive the app bundle identifier, Packet Tunnel bundle identifier, App Group, and VPN provider identifier. Both targets must use the same prefix.

3. In Xcode's **Signing & Capabilities**, select your Team and provisioning profiles for both targets, and confirm these capabilities are present:

   - `Network Extensions`: `Packet Tunnel Provider`
   - `App Groups`: `group.$(APP_ID)`

   The Team ID currently committed in the project belongs to the original development setup and will not work for another developer account.

4. Select the `Xray` scheme and a connected iPhone, then build and run. iOS asks for VPN authorization on first use; camera permission is requested the first time QR scanning is opened.

## Running tests

The repository includes unit tests that do not require a real Packet Tunnel and can run in an iOS Simulator. First, list the available test destinations:

```bash
xcodebuild -project Xray.xcodeproj -scheme Xray -showdestinations
```

Choose a device with `platform:iOS Simulator` and replace `<SIMULATOR_ID>` below with its `id`:

```bash
xcodebuild test \
  -project Xray.xcodeproj \
  -scheme Xray \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_ID>' \
  CODE_SIGNING_ALLOWED=NO
```

Tests cover the unified LibXray API and configuration generation, empty configuration handling, local port session state, VPN lifecycle state, traffic parsing and polling policy, share-link parsing, and geo file transactions. Some tests invoke the actual LibXray runtime. Packet Tunnel startup, the `utun` file descriptor, and camera behavior still require a physical device.

## Usage

1. Prepare a share link. The repository has explicitly been tested with VLESS, for example:

   ```text
   vless://<uuid>@<host>:<port>?security=none&encryption=none&type=tcp
   ```

2. Open the top-right More menu and use the system **Paste** action or select **Scan QR Code** (`扫描二维码`). The link is stored in the App Group `UserDefaults`, so the last configuration is available the next time the app opens.

   If the VPN is connecting, connected, reasserting, or disconnecting, an imported node is marked as pending and takes effect on the next connection. The current connection keeps using the node selected at startup.

3. Choose **Global Proxy** (`全局代理`) or **Smart Routing** (`智能分流`).

4. Before using Smart Routing for the first time, open **China Routing Assets** (`中国大陆分流资源`) from the top-right More menu. The app downloads and stores the following files in the shared App Group directory:

   - `geoip.dat` from `Loyalsoldier/v2ray-rules-dat`
   - `geosite.dat` from the `dlc.dat` release in `v2fly/domain-list-community` (renamed after download)

5. Tap Connect. The app builds an Xray JSON configuration containing TUN, DNS, routing, statistics, and Metrics settings, then passes it to the Packet Tunnel extension. The extension injects the `utun` file descriptor created by Network Extension and starts Xray.

6. Once connected, the app shows connection duration and cumulative upload/download totals for the TUN inbound. Latency tests start only when a configuration is available and the VPN is fully disconnected. A test runs automatically if the current node has no successful result yet; the refresh button also allows a manual test. While connected, the app displays any existing latency result and hides the refresh control.

7. Choose **Share Current Configuration** (`分享当前配置`) from the top-right More menu to display the most recently saved link as a QR code. If a new node was imported during a connection, the QR code contains that pending node, which may differ from the node currently in use. When geo files are updated or removed, a connected tunnel is restarted so Xray reloads the resources.

## How it works

```text
PacketTunnelManager.start()
   ├─ Capture the share link for this connection
   ├─ XrayConfigurationBuilder.makeVPNConfigurationData(from:)
   │   ├─ XrayCoreClient.convertShareLinkToXrayJSON(_:)
   │   │   └─ LibXrayRuntime.convertShareLinksToXrayJSON(_:)
   │   ├─ TUN inbound (tun-in)
   │   ├─ Metrics HTTP service (127.0.0.1:<dynamic port>)
   │   ├─ routing, DNS, statistics, and geo asset environment
   │   └─ proxy / direct / block outbounds
   └─ connection.startVPNTunnel(options:)
   │
   ▼
PacketTunnelProvider.startTunnel(options:completionHandler:)
   ├─ Configure IPv4/IPv6 default routes and DNS
   ├─ Find the utun FD created by Network Extension
   ├─ Inject env.xray.tun.fd
   └─ LibXrayRuntime.start(configJSON:) → LibXrayRuntime.isXrayRunning()
```

`LibXrayRuntime` wraps configuration conversion, startup, shutdown, and state queries in JSON requests with `apiVersion: 3`, sent through the unified `LibXrayInvoke` entry point. Latency tests use LibXray `pingBatch` with outbound JSON in the main app process, while the VPN's Xray instance runs in the Packet Tunnel extension process.

The app and extension use the same App Group. Share links and the Metrics port are stored in the App Group's `UserDefaults`; both latency-test and Packet Tunnel runtime configurations are passed as in-memory JSON and are not persisted. Geo assets are stored under `Library/Application Support/Xray/assets`.

## Limitations and troubleshooting

- This is an example project. It does not provide subscriptions, a configuration editor, background updates, an in-app log viewer, or multi-profile management.
- Only VLESS share links are explicitly covered by the repository's testing history. Support for VMess, Trojan, Shadowsocks, and other formats depends on LibXray's converter and is not guaranteed here.
- Network Extension requires a matching App ID, provisioning profile, capabilities, and user authorization. Incorrect signing configuration prevents the tunnel from starting.
- Geo downloads and Ping require network access. Geo files come from GitHub; Ping always targets `https://cp.cloudflare.com/` with a 30-second timeout.
- If a Metrics query times out, the app keeps the last successful values and retries automatically. It logs one application error after three consecutive failures and resets the failure count after a successful query. The system's `URLSession` may still log individual timeouts.
- The tunnel uses IPv4 `10.131.0.2/30`, IPv6 `fd00:131::2/126`, and MTU 1500. It installs default IPv4/IPv6 routes and sets `excludeLocalNetworks = true` in the system VPN configuration.
- The current code has not been fully validated on IPv6-only networks. For IPv6 issues, inspect `PacketTunnelProvider.makeTunnelNetworkSettings()` and the Xray TUN configuration.
- Changing the routing mode or updating/removing geo assets restarts an active VPN tunnel.
- Share links commonly contain server credentials and are persisted in the App Group's `UserDefaults`. Do not import production credentials on an untrusted test device.
- No open-source license is declared in this repository. Check with the project author and review LibXray's license before distributing or embedding the code.

## Project layout

Main directories and selected core files:

```text
.
├── Xray/                         # SwiftUI app, configuration, and VPN management
│   ├── DashboardView.swift        # Import, node display, and connection controls
│   ├── XrayConfigurationBuilder.swift
│   ├── XrayCoreClient.swift       # Asynchronous LibXray access
│   ├── PacketTunnelManager.swift  # System VPN configuration and lifecycle
│   └── XrayService.swift          # Latency tests and Metrics queries
├── PacketTunnel/                 # Network Extension and Xray lifecycle
│   └── PacketTunnelProvider.swift
├── Shared/                       # Runtime and constants shared by both targets
│   ├── LibXrayRuntime.swift
│   └── AppConstants.swift
├── XrayTests/                    # Unit tests that run in an iOS Simulator
│   └── LibXrayRuntimeTests.swift  # LibXray API, configuration, and empty input tests
├── Config.xcconfig               # APP_ID and build configuration
└── Xray.xcodeproj/               # Xcode project and shared scheme
    ├── project.pbxproj
    └── xcshareddata/xcschemes/Xray.xcscheme
```

## Formatting

The project uses SwiftFormat:

```bash
swiftformat . --swift-version 6
```
