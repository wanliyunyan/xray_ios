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
        
        guard let config = options?["config"] as? NSString as? String else {
            return
        }
        
        do {
            // 启动 Xray 核心进程
            try self.startXray(config: config)
            // 启动 SOCKS5 隧道
            try self.startSocks5Tunnel()
        } catch {
            throw error
        }
    }
    
    // 启动 Xray 核心的方法
    private func startXray(config:String) throws {

        // 创建文件
        let fileUrl = try createConfigFile(with: config)
        
        // 创建一个 RunXrayRequest 对象，用于指定 Xray 核心的运行配置
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
        }
    }
    
    // 启动 SOCKS5 隧道的方法
    private func startSocks5Tunnel() throws {
        // 在全局队列中异步执行 SOCKS5 隧道启动任务
        DispatchQueue.global(qos: .userInitiated).async {
            // 启动 文档是这么写的 但是不知道为什么没有打印
            Socks5Tunnel.run(withConfig: .string(content: Constant.socks5Config)) { code in
                if code == 0 {
                    print("Tun2Socks 启动成功")
                } else {
                    print("Tun2Socks 启动失败，错误代码: \(code)")
                }
            }
        }
    }
    
    // 停止隧道的方法 没发现这个方法有什么用处
    override func stopTunnel(with reason: NEProviderStopReason) async {
        // 停止 SOCKS5 隧道
        Socks5Tunnel.quit()

        // 停止 Xray 核心
        LibXrayStopXray()

        // 通知系统 VPN 已关闭
        self.cancelTunnelWithError(nil)
    }
    
    // 创建配置文件
    private func createConfigFile(with content: String, fileName: String = "config.json") throws -> URL {
        // 获取默认的文件管理器实例，用于处理文件操作。
        let manager = FileManager.default
        
        // 获取应用沙盒中的 "Documents" 目录的 URL。
        // ".documentDirectory" 表示 Documents 目录，".userDomainMask" 限定为用户的主目录下。
        let documentDirectory = manager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        // 在 "Documents" 目录中创建一个文件路径，并追加文件名。
        let fileUrl = documentDirectory.appendingPathComponent(fileName)
        
        // 检查文件是否已经存在。如果文件不存在，则创建它。
        if !manager.fileExists(atPath: fileUrl.path) {
            // 使用初始数据创建文件。`createFile` 返回一个布尔值，表示文件是否创建成功。
            let createSuccess = manager.createFile(atPath: fileUrl.path, contents: nil, attributes: nil)
            
            // 输出文件创建结果到调试控制台，方便开发者确认文件是否成功创建。
            debugPrint("文件创建结果: \(createSuccess)")
        }
        
        // 将传入的内容写入文件，覆盖已有内容。
        // `atomically` 参数指定是否应将内容写入临时文件，并在写入成功后替换原文件，以确保文件完整性。
        try content.write(to: fileUrl, atomically: false, encoding: .utf8)
        
        // 返回文件的 URL，以便调用者可以进一步操作该文件。
        return fileUrl
    }
}
