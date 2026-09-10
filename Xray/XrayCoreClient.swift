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
    case missingVersion
    case invalidLatency
    case latencyMeasurementFailed(String)
    case missingAllocatedPorts
    case invalidAllocatedPorts
    case allocatedPortUnavailable(UInt16)

    var errorDescription: String? {
        switch self {
        case .emptyShareLink:
            "无效的配置字符串"
        case .missingVersion:
            "LibXray 未返回版本号"
        case .invalidLatency:
            "LibXray 未返回有效延迟"
        case .latencyMeasurementFailed(let message):
            message
        case .missingAllocatedPorts:
            "LibXray 未返回本地服务端口"
        case .invalidAllocatedPorts:
            "LibXray 返回了无效的本地服务端口"
        case .allocatedPortUnavailable(let port):
            "本地端口 \(port) 已被占用"
        }
    }
}

/// Metrics 服务使用的本地端口。
struct LocalServicePorts: Equatable, Sendable {
    let metricsPort: UInt16

    static let defaultValue = LocalServicePorts(
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

        return try LibXrayRuntime.convertShareLinksToXrayJSON(shareLink)
    }

    /// 返回已安装的 Xray Core 版本。
    func fetchCoreVersion() throws -> String {
        let version = try LibXrayRuntime.coreVersion()
        guard !version.isEmpty else {
            throw XrayCoreClientError.missingVersion
        }
        return version
    }

    /// 分配 Metrics HTTP 服务所需的本地端口。
    func allocateLocalPorts() throws -> LocalServicePorts {
        let portNumbers = try LibXrayRuntime.freePorts(count: 1)
        guard portNumbers.count == 1 else {
            throw XrayCoreClientError.missingAllocatedPorts
        }

        let ports = portNumbers.compactMap(UInt16.init(exactly:))
        guard ports.count == 1, ports[0] != 0 else {
            throw XrayCoreClientError.invalidAllocatedPorts
        }

        guard LocalPortAvailabilityChecker.canBindTCP(ports[0]) else {
            throw XrayCoreClientError.allocatedPortUnavailable(ports[0])
        }

        return LocalServicePorts(metricsPort: ports[0])
    }

    /// 使用 LibXray `pingBatch` 对单个出站配置执行延迟测试。
    func measureLatency(
        configurationJSON: String,
        timeout: Int,
        targetURL: URL
    ) throws -> Int {
        let results = try LibXrayRuntime.pingBatch(
            configurations: [
                LibXrayPingConfiguration(
                    xrayJSON: configurationJSON,
                    outboundTag: "proxy"
                ),
            ],
            timeout: timeout,
            targetURL: targetURL
        )

        return try Self.parseLatency(from: results)
    }

    /// 解析单节点 `pingBatch` 响应，并将单项失败转换为可展示的业务错误。
    static func parseLatency(from results: [LibXrayPingResult]) throws -> Int {
        guard results.count == 1, let result = results.first else {
            throw XrayCoreClientError.invalidLatency
        }

        guard result.success else {
            let message = result.error?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw XrayCoreClientError.latencyMeasurementFailed(
                message.flatMap { $0.isEmpty ? nil : $0 } ?? "延迟测试失败"
            )
        }

        guard result.delay >= 0 else {
            throw XrayCoreClientError.invalidLatency
        }
        return result.delay
    }
}

private enum LocalPortAvailabilityChecker {
    static func canBindTCP(_ port: UInt16) -> Bool {
        canBind(port, socketType: SOCK_STREAM, protocol: IPPROTO_TCP)
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
