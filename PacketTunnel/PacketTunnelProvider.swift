//
//  PacketTunnelProvider.swift
//  PacketTunnel
//
//  Created by pan on 2024/9/14.
//

import LibXray
import NetworkExtension
import os
import Tun2SocksKit

// 定义一个 Swift 中的结构体，用于运行 Xray 配置
struct RunXrayRequest: Codable {
    var datDir: String?
    var configPath: String?
    var maxMemory: Int64?
}

class PacketTunnelProvider: NEPacketTunnelProvider {
    let MTU = 8500

    // 开始隧道的方法，会在创建隧道时调用
    override func startTunnel(options: [String: NSObject]? = nil) async throws {
        guard let sock5Port = options?["sock5Port"] as? Int else {
            throw NSError(domain: "PacketTunnel", code: -1, userInfo: [NSLocalizedDescriptionKey: "缺少 SOCKS5 端口配置"])
        }

        guard let path = options?["path"] as? String else {
            throw NSError(domain: "PacketTunnel", code: -1, userInfo: [NSLocalizedDescriptionKey: "缺少配置路径"])
        }

        do {
            // 启动 Xray 核心进程
            try startXray(path: path)

            // 设置隧道网络
            try await setTunnelNetworkSettings()

            // 启动 SOCKS5 隧道
            try startSocks5Tunnel(serverPort: sock5Port)
        } catch {
            os_log("启动服务时发生错误: %{public}@", error.localizedDescription)
            throw error
        }
    }

    // 启动 Xray 核心的方法
    private func startXray(path: String) throws {
        // 创建 RunXrayRequest
        let request = RunXrayRequest(datDir: Constant.assetDirectory.path, configPath: path, maxMemory: 50 * 1024 * 1024)

        // 将 RunXrayRequest 对象编码为 JSON 数据并启动 Xray 核心
        do {
            // 使用 JSONEncoder 编码请求对象为 JSON 数据
            let jsonData = try JSONEncoder().encode(request)

            // 将 JSON 数据转换为 Base64 编码的字符串
            let base64String = jsonData.base64EncodedString()

            // 将 Base64 编码后的字符串传递给 LibXrayRunXray 方法以启动 Xray 核心
            LibXrayRunXray(base64String)
        } catch {
            // 处理编码过程中可能发生的错误
            NSLog("编码 RunXrayRequest 失败: \(error.localizedDescription)")
            throw error
        }
    }

    // 启动 SOCKS5 隧道的方法
    private func startSocks5Tunnel(serverPort port: Int = 10808) throws {
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
        Socks5Tunnel.run(withConfig: .string(content: socks5Config)) { code in
            if code == 0 {
                os_log("Tun2Socks 启动成功")
            } else {
                os_log("Tun2Socks 启动失败，错误代码: %{public}d", code)
            }
        }
    }

    func setTunnelNetworkSettings() async throws {
        // 1. 创建网络设置对象
        //    tunnelRemoteAddress 通常写服务器实际分配给你的隧道地址，也可以是 IPv4 or IPv6
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "fd00::1")
        
        // 2. 设置 MTU
        settings.mtu = NSNumber(value: MTU)
        
        // 3. 配置 IPv4
        settings.ipv4Settings = {
            // - addresses：本地虚拟网卡 IP（客户端侧）
            // - subnetMasks：对应的掩码
            let ipv4 = NEIPv4Settings(
                addresses: ["198.18.0.1"],
                subnetMasks: ["255.255.255.0"]
            )
            
            // 包含路由
            // 下面演示如何显式地对默认路由设置 gatewayAddress
            let defaultV4Route = NEIPv4Route(
                destinationAddress: "0.0.0.0",
                subnetMask: "0.0.0.0"
            )
            defaultV4Route.gatewayAddress = "198.18.0.1"
            
            ipv4.includedRoutes = [defaultV4Route]
            ipv4.excludedRoutes = []
            
            return ipv4
        }()
        
        // 4. 配置 IPv6
        settings.ipv6Settings = {
            // addresses 与 networkPrefixLengths 要成对匹配
            let ipv6 = NEIPv6Settings(
                addresses: ["fd6e:a81b:704f:1211::1"],
                networkPrefixLengths: [64]
            )
            
            // 同理为 IPv6 默认路由添加网关地址
            let defaultV6Route = NEIPv6Route(
                destinationAddress: "::",
                networkPrefixLength: 0
            )
            defaultV6Route.gatewayAddress = "fd6e:a81b:704f:1211::1"
            
            ipv6.includedRoutes = [defaultV6Route]
            ipv6.excludedRoutes = []
            
            return ipv6
        }()
        
        // 5. 配置 DNS
        //    matchDomains = [""] 表示将所有域名都走隧道 DNS
        let dnsSettings = NEDNSSettings(servers: [
            "1.1.1.1",              // Cloudflare DNS (IPv4)
            "8.8.8.8",              // Google DNS (IPv4)
            "2606:4700:4700::1111", // Cloudflare DNS (IPv6)
            "2001:4860:4860::8888"  // Google DNS (IPv6)
        ])
        dnsSettings.matchDomains = [""]   // 必要！确保所有域名都走隧道
        
        settings.dnsSettings = dnsSettings

        // 5. 应用到隧道
        try await setTunnelNetworkSettings(settings)
    }


    // 停止隧道的方法 没发现这个方法有什么用处
    override func stopTunnel(with _: NEProviderStopReason) async {
        // 停止 SOCKS5 隧道
        Socks5Tunnel.quit()

        // 停止 Xray 核心
        LibXrayStopXray()
    }
}
