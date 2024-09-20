//
//  PacketTunnelProvider.swift
//  PacketTunnel
//
//  Created by pan on 2024/9/14.
//

import NetworkExtension
import LibXray
import Tun2SocksKit
import os

// 定义一个 Swift 中的结构体，用于运行 Xray 配置
struct RunXrayRequest: Codable {
    var datDir: String?
    var configPath: String?
    var maxMemory: Int64?
}

// PacketTunnelProvider 是 NEPacketTunnelProvider 的子类，
// 负责处理网络包的隧道提供。
class PacketTunnelProvider: NEPacketTunnelProvider {
    
    // 开始隧道的方法，会在创建隧道时调用
    override func startTunnel(options: [String : NSObject]? = nil) async throws {
        // 创建网络设置对象，设置隧道的远程地址
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "254.1.1.1")
        settings.mtu = 1500
        
        // 设置 IPv4 地址、掩码和路由
        settings.ipv4Settings = {
            let settings = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.0.0"])
            settings.includedRoutes = [NEIPv4Route.default()]
            settings.excludedRoutes = [NEIPv4Route(destinationAddress: "0.0.0.0", subnetMask: "255.0.0.0")]
            return settings
        }()
        
        // 设置 IPv6 地址、掩码和路由
        settings.ipv6Settings = {
            let settings = NEIPv6Settings(addresses: ["fd6e:a81b:704f:1211::1"], networkPrefixLengths: [64])
            settings.includedRoutes = [NEIPv6Route.default()]
            settings.excludedRoutes = [NEIPv6Route(destinationAddress: "::", networkPrefixLength: 128)]
            return settings
        }()
        
        // 设置 DNS 服务器
        settings.dnsSettings = NEDNSSettings(servers: ["8.8.8.8", "114.114.114.114"])
        
        // 应用设置到隧道
        try await self.setTunnelNetworkSettings(settings)
        
        guard let config = options?["config"] as? String else {
            return
        }
        
        guard let port = options?["port"] as? Int else {
            return
        }
        
        do {
            // 启动 Xray 核心进程
            try self.startXray(inboundPort: port,config: config)
            // 启动 SOCKS5 隧道
            try self.startSocks5Tunnel(serverPort: port)
        } catch {
            os_log("启动服务时发生错误: %{public}@", error.localizedDescription)
            throw error
        }
    }
    
    // 启动 Xray 核心的方法
    private func startXray(inboundPort:Int = 10808,config: String) throws {
        
        // 生成合并后的配置数据
        let configData = try Configuration().buildConfigurationData(inboundPort: inboundPort, config: config)
        
        // 将配置数据转换为字符串
        guard let mergedConfigString = String(data: configData, encoding: .utf8) else {
            throw NSError(domain: "ConfigDataError", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法将配置数据转换为字符串"])
        }

        let fileUrl = try createConfigFile(with: mergedConfigString)

        // 创建 RunXrayRequest
        let request = RunXrayRequest(datDir: nil, configPath: fileUrl.path, maxMemory: 0)
        
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
          mtu: 1500

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
    
    // 停止隧道的方法 没发现这个方法有什么用处
    override func stopTunnel(with reason: NEProviderStopReason) async {
        // 停止 SOCKS5 隧道
        Socks5Tunnel.quit()

        // 停止 Xray 核心
        LibXrayStopXray()
    }
    
    // 创建配置文件
    private func createConfigFile(with content: String, fileName: String = "config.json") throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileUrl = tempDirectory.appendingPathComponent(fileName)
        
        // 写入内容，若文件不存在会自动创建
        try content.write(to: fileUrl, atomically: true, encoding: .utf8)
        
        return fileUrl
    }
}

struct Configuration {

    func buildConfigurationData(inboundPort: Int, config: String) throws -> Data {
        var configuration: [String: Any] = [:]
        configuration["inbounds"] = [try self.buildInbound(inboundPort: inboundPort)]
        
        // 获取 dataDict
        let dataDict = try self.buildOutInbound(config: config)
        
        // 合并 inbound 和 dataDict
        dataDict.forEach { configuration[$0.key] = $0.value }
        
        return try JSONSerialization.data(withJSONObject: configuration, options: .prettyPrinted)
    }
    
    private func buildInbound(inboundPort: Int) throws -> [String: Any] {
        var inbound: [String: Any] = [:]
        inbound["listen"] = "127.0.0.1"
        inbound["protocol"] = "socks"
        inbound["settings"] = [
            "udp": true
        ]
        inbound["port"] = inboundPort
        return inbound
    }

    private func buildOutInbound(config: String) throws -> [String: Any] {
        // 将传入的 config 字符串进行 Base64 编码并转换为 Xray JSON
        guard let configData = config.data(using: .utf8) else {
            throw NSError(domain: "InvalidConfig", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的配置字符串"])
        }
        let base64EncodedConfig = configData.base64EncodedString()
        let xrayJsonString = LibXrayConvertShareLinksToXrayJson(base64EncodedConfig)

        // 解码 Xray JSON 字符串
        guard let decodedData = Data(base64Encoded: xrayJsonString),
              let decodedString = String(data: decodedData, encoding: .utf8),
              let jsonData = decodedString.data(using: .utf8),
              let jsonDict = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any],
              let success = jsonDict["success"] as? Bool, success,
              let dataDict = jsonDict["data"] as? [String: Any] else {
            throw NSError(domain: "InvalidXrayJson", code: -1, userInfo: [NSLocalizedDescriptionKey: "解析 Xray JSON 失败"])
        }

        return dataDict
    }
}
