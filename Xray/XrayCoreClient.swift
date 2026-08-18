//
//  XrayCoreClient.swift
//  Xray
//
//  Created by pan on 2026/8/17.
//

import Darwin
import Foundation

enum XrayCoreClientError: LocalizedError, Equatable, Sendable {
    case emptyShareLink
    case missingConvertedConfiguration
    case missingVersion
    case invalidLatency
    case missingAllocatedPorts
    case invalidAllocatedPorts
    case duplicateAllocatedPorts
    case allocatedPortUnavailable(UInt16)

    var errorDescription: String? {
        switch self {
        case .emptyShareLink:
            "无效的配置字符串"
        case .missingConvertedConfiguration:
            "解析 Xray JSON 失败"
        case .missingVersion:
            "LibXray 未返回版本号"
        case .invalidLatency:
            "LibXray 未返回有效延迟"
        case .missingAllocatedPorts:
            "LibXray 未返回本地服务端口"
        case .invalidAllocatedPorts:
            "LibXray 返回了无效的本地服务端口"
        case .duplicateAllocatedPorts:
            "LibXray 返回了重复的本地服务端口"
        case .allocatedPortUnavailable(let port):
            "本地端口 \(port) 已被占用"
        }
    }
}

/// SOCKS 和 Metrics 服务使用的具名本地端口。
struct LocalServicePorts: Equatable, Sendable {
    let socksPort: UInt16
    let metricsPort: UInt16

    static let defaultValue = LocalServicePorts(
        socksPort: AppConstants.defaultSocksPort.rawValue,
        metricsPort: AppConstants.defaultMetricsPort.rawValue
    )
}

/// 以异步方式访问当前进程中的 LibXray API。
actor XrayCoreClient {
    static let shared = XrayCoreClient()

    /// 将分享链接转换为 LibXray 返回的基础 Xray JSON。
    func convertShareLinkToXrayJSON(_ shareLink: String) throws -> Data {
        guard !shareLink.isEmpty else {
            throw XrayCoreClientError.emptyShareLink
        }

        guard let configuration = try LibXrayRuntime.invoke(
            method: "convertShareLinksToXrayJson",
            payload: ["text": shareLink]
        ) else {
            throw XrayCoreClientError.missingConvertedConfiguration
        }

        return try JSONSerialization.data(withJSONObject: configuration)
    }

    /// 返回已安装的 Xray Core 版本。
    func fetchCoreVersion() throws -> String {
        let data = try LibXrayRuntime.invoke(method: "xrayVersion")
        guard let version = data?["version"] as? String, !version.isEmpty else {
            throw XrayCoreClientError.missingVersion
        }
        return version
    }

    /// 分配 App 所需的两个本地端口。
    func allocateLocalPorts() throws -> LocalServicePorts {
        let responseData = try LibXrayRuntime.invoke(
            method: "getFreePorts",
            payload: ["count": 2]
        )
        guard let portNumbers = responseData?["ports"] as? [Int], portNumbers.count == 2 else {
            throw XrayCoreClientError.missingAllocatedPorts
        }

        let ports = portNumbers.compactMap(UInt16.init(exactly:))
        guard ports.count == 2, ports.allSatisfy({ $0 != 0 }) else {
            throw XrayCoreClientError.invalidAllocatedPorts
        }
        guard ports[0] != ports[1] else {
            throw XrayCoreClientError.duplicateAllocatedPorts
        }

        guard LocalPortAvailabilityChecker.canBindTCP(ports[0]),
              LocalPortAvailabilityChecker.canBindUDP(ports[0])
        else {
            throw XrayCoreClientError.allocatedPortUnavailable(ports[0])
        }
        guard LocalPortAvailabilityChecker.canBindTCP(ports[1]) else {
            throw XrayCoreClientError.allocatedPortUnavailable(ports[1])
        }

        return LocalServicePorts(socksPort: ports[0], metricsPort: ports[1])
    }

    /// 通过指定的本地 SOCKS 代理执行 LibXray 延迟请求。
    func measureLatency(
        configurationFileURL: URL,
        timeout: Int,
        targetURL: URL,
        proxyURL: URL
    ) throws -> Int {
        let responseData = try LibXrayRuntime.invoke(
            method: "ping",
            payload: [
                "configPath": configurationFileURL.path,
                "timeout": timeout,
                "url": targetURL.absoluteString,
                "proxy": proxyURL.absoluteString,
            ]
        )

        guard let delayMilliseconds = responseData?["delay"] as? Int else {
            throw XrayCoreClientError.invalidLatency
        }
        return delayMilliseconds
    }
}

private enum LocalPortAvailabilityChecker {
    static func canBindTCP(_ port: UInt16) -> Bool {
        canBind(port, socketType: SOCK_STREAM, protocol: IPPROTO_TCP)
    }

    static func canBindUDP(_ port: UInt16) -> Bool {
        canBind(port, socketType: SOCK_DGRAM, protocol: IPPROTO_UDP)
    }

    private static func canBind(
        _ port: UInt16,
        socketType: Int32,
        protocol protocolValue: Int32
    ) -> Bool {
        let socketDescriptor = socket(AF_INET, socketType, protocolValue)
        guard socketDescriptor >= 0 else {
            return false
        }
        defer { close(socketDescriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(
                    socketDescriptor,
                    $0,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                ) == 0
            }
        }
    }
}
