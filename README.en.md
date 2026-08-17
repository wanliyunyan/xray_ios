# Xray iOS

A minimal iOS example that combines SwiftUI, Network Extension, and [LibXray](https://github.com/wanliyunyan/LibXray) to run Xray in a TUN-based Packet Tunnel.

This repository is intended for developers and is not a production-ready VPN client. The app converts a VLESS share link into an Xray configuration, starts Xray inside a `PacketTunnel` extension, and exposes basic routing, diagnostics, asset management, and configuration sharing.

## Features

- Import a share link from the clipboard.
- Scan a QR code with the camera.
- Show the node ID, server address, and port; IPv4 addresses are masked in the UI.
- Start and stop Xray TUN through an iOS `PacketTunnelProvider`.
- Two routing modes:
  - **Global**: TCP/UDP traffic ultimately uses the proxy outbound.
  - **Non-global**: with geo assets installed, ad domains are blocked, China/private domains and IPs use direct access, and the remaining traffic uses the proxy. Geo-dependent rules are skipped when assets are absent.
- Download, replace, and remove `geoip.dat` and `geosite.dat`.
- Display upload/download totals from Xray Metrics.
- Measure proxy latency through `https://1.1.1.1`.
- Render the current share link as a QR code.
- Display the embedded Xray Core version.

## Requirements

- macOS and Xcode.
- A physical iPhone for complete Packet Tunnel and camera testing. The simulator cannot fully validate these flows.
- An Apple Developer account with signing permissions for Network Extension and App Groups.

The project uses Swift Package Manager for LibXray:

- Repository: `https://github.com/wanliyunyan/LibXray.git`
- Minimum version: `26.7.28`

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

## Usage

1. Prepare a share link. The repository has explicitly been tested with VLESS, for example:

   ```text
   vless://<uuid>@<host>:<port>?security=none&encryption=none&type=tcp
   ```

2. Tap **Paste** or **Scan**. The link is stored in the App Group `UserDefaults`, so the last configuration is available the next time the app opens.

3. Choose **Global** or **Non-global** routing.

4. Before using Non-global routing for the first time, tap **Geo files**. The app downloads and stores the following files in the shared App Group directory:

   - `geoip.dat` from `Loyalsoldier/v2ray-rules-dat`
   - `geosite.dat` from the `dlc.dat` release in `v2fly/domain-list-community` (renamed after download)

5. Tap Connect. The app builds an Xray JSON configuration containing TUN, DNS, routing, statistics, and Metrics settings, then passes it to the Packet Tunnel extension. The extension injects the `utun` file descriptor created by Network Extension and starts Xray.

6. Once connected, the app shows connection duration and traffic totals. Ping shares the LibXray runtime with Xray; the manual refresh control is hidden while the VPN is connected, so latency tests are best run while disconnected.

7. Tap **Share** to display the current link as a QR code. When geo files are updated or removed, a connected tunnel is restarted so Xray reloads the resources.

## How it works

```text
Share link
   │
   ▼
LibXray.convertShareLinksToXrayJson
   │
   ▼
XrayConfigurationBuilder
   ├─ TUN inbound (tun-in)
   ├─ Metrics HTTP service (127.0.0.1:<dynamic port>)
   ├─ routing, DNS, statistics, and geo asset environment
   └─ proxy / direct / block outbounds
   │
   ▼
PacketTunnelManager.startVPNTunnel(options:)
   │
   ▼
PacketTunnelProvider
   ├─ Configure IPv4/IPv6 default routes and DNS
   ├─ Find the utun FD created by Network Extension
   ├─ Inject env.xray.tun.fd
   └─ testXray → runXray → getXrayState
   ```

The app and extension share configuration, ports, and geo assets through the same App Group. Runtime configs are stored under `Library/Application Support/Xray/configs`; assets are stored under `Library/Application Support/Xray/assets`.

## Limitations and troubleshooting

- This is an example project. It does not provide subscriptions, a configuration editor, background updates, an in-app log viewer, or multi-profile management.
- Only VLESS share links are explicitly covered by the repository's testing history. Support for VMess, Trojan, Shadowsocks, and other formats depends on LibXray's converter and is not guaranteed here.
- Network Extension requires a matching App ID, provisioning profile, capabilities, and user authorization. Incorrect signing configuration prevents the tunnel from starting.
- Geo downloads and Ping require network access. Geo files come from GitHub; Ping always targets `https://1.1.1.1` with a 30-second timeout.
- The tunnel uses IPv4 `10.131.0.2/30`, IPv6 `fd00:131::2/126`, and MTU 1500. It installs default IPv4/IPv6 routes and sets `excludeLocalNetworks = true` in the system VPN configuration.
- The current code has not been fully validated on IPv6-only networks. For IPv6 issues, inspect `PacketTunnelProvider.makeTunnelNetworkSettings()` and the Xray TUN configuration.
- Changing the routing mode or updating/removing geo assets restarts an active VPN tunnel.
- No open-source license is declared in this repository. Check with the project author and review LibXray's license before distributing or embedding the code.

## Project layout

```text
.
├── Xray/                         # SwiftUI app, configuration, and VPN management
│   ├── DashboardView.swift
│   ├── XrayConfigurationBuilder.swift
│   ├── PacketTunnelManager.swift
│   ├── XrayService.swift
│   ├── VPNConnectionControlView.swift
│   ├── VPNRoutingModePickerView.swift
│   ├── GeoAssetDownloadView.swift
│   ├── LatencyTestView.swift
│   ├── TrafficStatisticsView.swift
│   ├── QRCodeScannerView.swift
│   └── ConfigurationShareView.swift
├── PacketTunnel/                 # Network Extension and Xray lifecycle
│   └── PacketTunnelProvider.swift
├── Shared/                       # Runtime and constants shared by both targets
│   ├── LibXrayRuntime.swift
│   └── AppConstants.swift
├── Config.xcconfig               # APP_ID and build configuration
└── Xray.xcodeproj
```

## Formatting

The project uses SwiftFormat:

```bash
swiftformat . --swift-version 6
```
