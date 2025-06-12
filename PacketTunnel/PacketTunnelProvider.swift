//
//  PacketTunnelProvider.swift
//  PacketTunnel
//
//  Created by pan on 2024/9/14.
//

import LibXray
import Network
import NetworkExtension
import os
import Tun2SocksKit

// MARK: - Logger

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "PacketTunnelProvider")

// MARK: - PacketTunnelProvider

/// 核心的 VPN 扩展入口类。通过重写 `startTunnel`、`stopTunnel` 来管理自定义隧道的创建与销毁。
/// 内部包含了启动 Xray、设置网络环境以及启动 Socks5 隧道的完整逻辑。
class PacketTunnelProvider: NEPacketTunnelProvider {
    // MARK: - 常量

    /// 虚拟网络接口的 MTU 值，可根据实际环境进行调整。
    let MTU = 8500

    // MARK: - 隧道生命周期

    /// 在创建或启用隧道时调用，用于启动 Xray 核心、配置虚拟网卡并启动 Tun2SocksKit（Socks5 隧道）。
    ///
    /// - Parameter options: 传递给隧道的键值对信息，通常包含 `sock5Port` 和 `path` 等。
    /// - Throws: 若缺失必要信息或启动过程中发生错误，抛出相应的错误。
    override func startTunnel(options: [String: NSObject]? = nil) async throws {
        // 1. 从 options 中提取 SOCKS5 端口与配置文件路径
        guard let sock5Port = options?["sock5Port"] as? Int else {
            throw NSError(domain: "PacketTunnel", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "缺少 SOCKS5 端口配置"])
        }

        guard let path = options?["path"] as? String else {
            throw NSError(domain: "PacketTunnel", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "缺少配置路径"])
        }

        do {
            // 2. 启动 Xray 核心
            try startXray(path: path)

            // 3. 设置隧道网络（虚拟网卡、路由、DNS 等）
            try await setTunnelNetworkSettings()

            // 4. 启动 SOCKS5 隧道（Tun2SocksKit）
            try startSocks5Tunnel(serverPort: sock5Port)

        } catch {
            Logger().error("启动服务时发生错误: \(error.localizedDescription)")
            throw error
        }
    }

    /// 在隧道停止时调用，可在此处释放所有资源、停止相关服务（如 Xray、Tun2SocksKit）。
    ///
    /// - Parameter reason: 系统定义的停止原因，通常可以根据实际需求进行相应处理。
    override func stopTunnel(with reason: NEProviderStopReason) async {
        // 1. 停止 SOCKS5 隧道
        Socks5Tunnel.quit()

        // 2. 停止 Xray 核心
        LibXrayStopXray()

        // 3.输出日志
        Logger().info("隧道停止, 原因: \(reason.rawValue)")
    }

    // MARK: - 启动 Xray

    /// 启动 Xray 核心进程，向其传递相关配置和内存限制。
    ///
    /// - Parameter path: 已生成的 Xray 配置文件路径。
    /// - Throws: 当编码请求或底层调用出现错误时，抛出相应错误。
    private func startXray(path: String) throws {
        do {
            // 1. 构造请求base64字符串
            var error: NSError?
            let base64String = LibXrayNewXrayRunRequest(
                Constant.assetDirectory.path,
                path,
                &error
            )

            if let err = error {
                throw err
            }

            // 2. 调用 LibXrayRunXray 以启动 Xray 核心
            LibXrayRunXray(base64String)
        } catch {
            Logger().error("Xray调用异常: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - 启动 Socks5 隧道（Tun2SocksKit）

    /// 使用 Tun2SocksKit 启动 Socks5 隧道，将指定端口的 SOCKS5 流量引导进虚拟网卡。
    ///
    /// - Parameter port: SOCKS5 服务所监听的端口号，默认为 10808。
    /// - Throws: 若配置字符串生成或启动过程中发生错误，抛出相应错误。
    private func startSocks5Tunnel(serverPort port: Int = 10808) throws {
        // 1. 构造 Socks5 隧道配置
        let socks5Config = """
        tunnel:
          mtu: \(MTU)

        socks5:
          port: \(port)
          address: 127.0.0.1
          udp: 'udp'

        misc:
          task-stack-size: 20480
          connect-timeout: 5000
          read-write-timeout: 60000
          log-file: stderr
          log-level: debug
          limit-nofile: 65535
        """

        // 2. 启动隧道
        Socks5Tunnel.run(withConfig: .string(content: socks5Config)) { code in
            if code == 0 {
                Logger().info("Tun2Socks启动成功")
            } else {
                Logger().error("Tun2Socks启动失败，代码: \(code)")
            }
        }
    }

    // MARK: - 配置虚拟网卡

    /// 配置隧道网络设置，如本地虚拟网卡 IP、路由、DNS 服务器等，并应用到当前隧道。
    ///
    /// - Throws: 当网络设置应用失败时，抛出相应错误。
    func setTunnelNetworkSettings() async throws {
        // 1. 创建基础的 NetworkSettings
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "fd00::1")
        settings.mtu = NSNumber(value: MTU)

        // 2. 配置 IPv4 设置
        settings.ipv4Settings = {
            // - addresses：本地虚拟网卡 IP（客户端侧）
            // - subnetMasks：对应的掩码
            let ipv4 = NEIPv4Settings(
                addresses: ["198.18.0.1"],
                subnetMasks: ["255.255.255.0"]
            )

            let defaultV4Route = NEIPv4Route(
                destinationAddress: "0.0.0.0",
                subnetMask: "0.0.0.0"
            )
            defaultV4Route.gatewayAddress = "198.18.0.1"

            ipv4.includedRoutes = [defaultV4Route]
            ipv4.excludedRoutes = []
            return ipv4
        }()

        // 3. 配置 IPv6 设置
        settings.ipv6Settings = {
            let ipv6 = NEIPv6Settings(
                addresses: ["fd6e:a81b:704f:1211::1"],
                networkPrefixLengths: [64]
            )

            let defaultV6Route = NEIPv6Route(
                destinationAddress: "::",
                networkPrefixLength: 0
            )
            defaultV6Route.gatewayAddress = "fd6e:a81b:704f:1211::1"

            ipv6.includedRoutes = [defaultV6Route]
            ipv6.excludedRoutes = []
            return ipv6
        }()

        // 4. 配置 DNS 服务器
        let dnsSettings = NEDNSSettings(servers: [
            "1.1.1.1", // Cloudflare DNS (IPv4)
            "8.8.8.8", // Google DNS (IPv4)
            "2606:4700:4700::1111", // Cloudflare DNS (IPv6)
            "2001:4860:4860::8888", // Google DNS (IPv6)
        ])
        // matchDomains = [""] 表示所有域名都走此 DNS
        dnsSettings.matchDomains = [""]

        settings.dnsSettings = dnsSettings

        // 5. 应用新建的网络设置
        try await setTunnelNetworkSettings(settings)
    }
}
