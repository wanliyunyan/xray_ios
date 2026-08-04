//
//  Constant.swift
//  Xray
//
//  Created by pan on 2024/9/14.
//

import Foundation
import Network

/// App 与 Packet Tunnel 扩展共享的标识、默认值和存储目录。
public enum Constant {
    /// 从主 App 的 `Info.plist` 读取应用标识。
    ///
    /// 该值用于派生 App Group 和 Packet Tunnel 扩展标识。构建配置未提供 `APP_ID`
    /// 时返回 `"unknown"`，便于尽早暴露配置问题。
    public static let packageName = Bundle.main.infoDictionary?["APP_ID"] as? String ?? "unknown"
}

public extension Constant {
    // MARK: - Identifiers and Defaults

    /// App 与 Packet Tunnel 扩展共同访问的 App Group 标识。
    static let groupName = "group.\(Constant.packageName)"

    /// `NETunnelProviderProtocol` 使用的 Packet Tunnel 扩展 Bundle Identifier。
    static let tunnelName = "\(Constant.packageName).PacketTunnel"

    /// LibXray Ping 流程使用的默认本地 SOCKS5 端口。
    static let socks5Port: NWEndpoint.Port = 10808

    /// Xray Metrics HTTP 服务使用的默认监听端口。
    static let trafficPort: NWEndpoint.Port = 49227

    /// 延迟测试访问的目标地址。
    static let pingUrl: String = "https://1.1.1.1"

    /// LibXray Ping 请求的超时时间，单位为秒。
    static let timeout: Int = 30

    /// 主 App 通过 `startVPNTunnel(options:)` 传给扩展的原始 JSON 配置键。
    static let tunnelConfigurationOptionKey = "xrayConfig"

    // MARK: - Shared Storage

    /// 确保目录存在并返回原 URL。
    ///
    /// 创建失败意味着 App 与扩展无法继续共享配置或 geo 资源，因此直接终止进程，
    /// 避免后续以不完整环境启动 Xray。
    private static func createDirectory(at url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) == false else {
            return url
        }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        } catch {
            fatalError(error.localizedDescription)
        }
        return url
    }

    /// App Group 内 Xray 数据的根目录。
    ///
    /// 目录结构固定为 `Library/Application Support/Xray`，主 App 和 Packet Tunnel
    /// 扩展通过相同路径访问运行配置和资源文件。
    static let homeDirectory: URL = {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupName) else {
            fatalError("无法加载共享文件路径")
        }
        let url = containerURL.appendingPathComponent("Library/Application Support/Xray")
        return createDirectory(at: url)
    }()

    /// 存放 `geoip.dat`、`geosite.dat` 等 Xray 资源文件的共享目录。
    static let assetDirectory = createDirectory(at: homeDirectory.appending(component: "assets", directoryHint: .isDirectory))

    /// 存放 LibXray 校验和运行所需 JSON 配置的共享目录。
    static let configDirectory = createDirectory(at: homeDirectory.appending(component: "configs", directoryHint: .isDirectory))
}
