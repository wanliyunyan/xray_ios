//
//  AppConstants.swift
//  Xray
//
//  Created by pan on 2024/9/14.
//

import Foundation
import Network

/// App Group 共享目录不可用时返回的可恢复错误。
public enum AppGroupDirectoryError: LocalizedError, Equatable, Sendable {
    case containerUnavailable(identifier: String)
    case pathIsNotDirectory(path: String)
    case directoryCreationFailed(path: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .containerUnavailable(let identifier):
            "无法访问 App Group 容器 \(identifier)。请检查主 App 与 Packet Tunnel 的 App Groups capability、entitlement 和签名配置。"
        case .pathIsNotDirectory(let path):
            "共享存储路径已被同名文件占用：\(path)"
        case .directoryCreationFailed(let path, let reason):
            "无法创建共享存储目录 \(path)：\(reason)"
        }
    }
}

/// App 与 Packet Tunnel 扩展共享的标识、默认值和存储目录。
public enum AppConstants {
    /// 从主 App 的 `Info.plist` 读取应用标识。
    ///
    /// 该值用于派生 App Group 和 Packet Tunnel 扩展标识。构建配置未提供 `APP_ID`
    /// 时返回 `"unknown"`，便于尽早暴露配置问题。
    public static let applicationIdentifier = Bundle.main.infoDictionary?["APP_ID"] as? String ?? "unknown"
}

public extension AppConstants {
    // MARK: - 标识符与默认值

    /// App 与 Packet Tunnel 扩展共同访问的 App Group 标识。
    static let appGroupIdentifier = "group.\(AppConstants.applicationIdentifier)"

    /// `NETunnelProviderProtocol` 使用的 Packet Tunnel 扩展 Bundle Identifier。
    static let tunnelProviderIdentifier = "\(AppConstants.applicationIdentifier).PacketTunnel"

    /// 统一日志子系统；测试环境缺少 Bundle Identifier 时回退到应用标识。
    static let loggingSubsystem = Bundle.main.bundleIdentifier ?? applicationIdentifier

    /// LibXray Ping 流程使用的默认本地 SOCKS5 端口。
    static let defaultSocksPort: NWEndpoint.Port = 10808

    /// Xray Metrics HTTP 服务使用的默认监听端口。
    static let defaultMetricsPort: NWEndpoint.Port = 49227

    /// 延迟测试访问的目标地址。
    static let pingURL: URL = {
        guard let url = URL(string: "https://1.1.1.1") else {
            preconditionFailure("无效的 Ping URL")
        }
        return url
    }()

    /// LibXray Ping 请求的超时时间，单位为秒。
    static let pingTimeout: Int = 30

    /// 主 App 通过 `startVPNTunnel(options:)` 传给扩展的原始 JSON 配置键。
    static let tunnelConfigurationOptionKey = "xrayConfig"

    // MARK: - 共享存储

    /// 确保目录存在并返回原 URL，失败时由调用方决定如何展示或终止当前操作。
    private static func createDirectory(at url: URL, fileManager: FileManager) throws -> URL {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw AppGroupDirectoryError.pathIsNotDirectory(path: url.path)
            }
            return url
        }

        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        } catch {
            throw AppGroupDirectoryError.directoryCreationFailed(
                path: url.path,
                reason: error.localizedDescription
            )
        }
        return url
    }

    /// App Group 内 Xray 数据的根目录。
    ///
    /// 目录结构固定为 `Library/Application Support/Xray`，主 App 和 Packet Tunnel
    /// 扩展通过相同路径访问运行配置和资源文件。
    static func xrayDirectoryURL(
        fileManager: FileManager = .default,
        containerURL: URL? = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier
        )
    ) throws -> URL {
        guard let containerURL else {
            throw AppGroupDirectoryError.containerUnavailable(identifier: appGroupIdentifier)
        }
        let url = containerURL.appendingPathComponent("Library/Application Support/Xray")
        return try createDirectory(at: url, fileManager: fileManager)
    }

    /// 存放 `geoip.dat`、`geosite.dat` 等 Xray 资源文件的共享目录。
    static func assetDirectoryURL(fileManager: FileManager = .default) throws -> URL {
        try createDirectory(
            at: xrayDirectoryURL(fileManager: fileManager)
                .appending(component: "assets", directoryHint: .isDirectory),
            fileManager: fileManager
        )
    }
}
