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
        
        do {
            // 启动 Xray 核心进程
            try self.startXray(config: config)
            // 启动 SOCKS5 隧道
            try self.startSocks5Tunnel()
        } catch {
            os_log("启动服务时发生错误: %{public}@", error.localizedDescription)
            throw error
        }
    }
    
    // 启动 Xray 核心的方法
    private func startXray(config: String) throws {
        // 将传入的 config 字符串进行 Base64 编码并转换为 Xray JSON
        guard let configData = config.data(using: .utf8) else { return }
        let base64EncodedConfig = configData.base64EncodedString()
        let xrayJsonString = LibXrayConvertShareLinksToXrayJson(base64EncodedConfig)

        // 解码 Xray JSON 字符串
        guard let decodedData = Data(base64Encoded: xrayJsonString),
              let decodedString = String(data: decodedData, encoding: .utf8),
              let jsonData = decodedString.data(using: .utf8),
              let jsonDict = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any],
              let success = jsonDict["success"] as? Bool, success,
              let dataDict = jsonDict["data"] as? [String: Any] else {
            return
        }
        
        // 将 data 合并到 xrayConfig
        let xrayConfigString = Constant.xrayConfig
        guard let xrayConfigData = xrayConfigString.data(using: .utf8),
              var xrayConfigJson = try? JSONSerialization.jsonObject(with: xrayConfigData, options: []) as? [String: Any] else {
            return
        }
        
        dataDict.forEach { xrayConfigJson[$0.key] = $0.value }

        // 将合并后的 JSON 转为字符串并创建配置文件
        guard let mergedConfigData = try? JSONSerialization.data(withJSONObject: xrayConfigJson, options: [.prettyPrinted]),
              let mergedConfigString = String(data: mergedConfigData, encoding: .utf8) else {
            return
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
    private func startSocks5Tunnel() throws {
        Socks5Tunnel.run(withConfig: .string(content: Constant.socks5Config)) { code in
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
