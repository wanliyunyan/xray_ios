//
//  XrayService.swift
//  Xray
//
//  Created by pan on 2025/9/19.
//

import Foundation
import Network

enum XrayServiceError: LocalizedError, Equatable, Sendable {
    case missingConfiguration
    case invalidConfigurationEncoding
    case missingSocksPort
    case invalidProxyURL

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            "没有可用的配置"
        case .invalidConfigurationEncoding:
            "无法将配置数据转换为字符串"
        case .missingSocksPort:
            "无法加载 SOCKS5 端口"
        case .invalidProxyURL:
            "无法生成 SOCKS5 代理地址"
        }
    }
}

protocol LocalPortAllocating: Sendable {
    func allocateLocalPorts() async throws -> LocalServicePorts
}

/// 协调 App 层的 Xray 操作，但不持有 VPN 生命周期状态。
struct XrayService: LocalPortAllocating, Sendable {
    private let coreClient = XrayCoreClient.shared
    private let configurationBuilder = XrayConfigurationBuilder()

    // MARK: - 诊断

    /// 使用当前分享链接构建并执行延迟测试。
    func measureLatency() async throws -> Int {
        guard
            let shareLink = AppGroupStore.loadString(forKey: "configLink"),
            !shareLink.isEmpty
        else {
            throw XrayServiceError.missingConfiguration
        }

        let configurationData = try await configurationBuilder
            .makeLatencyTestConfigurationData(from: shareLink)
        guard let configurationJSON = String(data: configurationData, encoding: .utf8) else {
            throw XrayServiceError.invalidConfigurationEncoding
        }

        let configurationFileURL = try SharedConfigurationFileStore.write(configurationJSON)
        guard let socksPort = AppGroupStore.loadPort(forKey: "socks5Port") else {
            throw XrayServiceError.missingSocksPort
        }

        guard let proxyURL = URL(string: "socks5://127.0.0.1:\(socksPort.rawValue)") else {
            throw XrayServiceError.invalidProxyURL
        }

        return try await coreClient.measureLatency(
            configurationFileURL: configurationFileURL,
            timeout: AppConstants.pingTimeout,
            targetURL: AppConstants.pingURL,
            proxyURL: proxyURL
        )
    }

    /// 获取已安装的 Xray Core 版本。
    func fetchCoreVersion() async throws -> String {
        try await coreClient.fetchCoreVersion()
    }

    /// 从本地 Metrics HTTP 端点读取 TUN 累计流量。
    func fetchTrafficStatistics(
        on metricsPort: NWEndpoint.Port
    ) async throws -> TrafficStatistics {
        guard let endpointURL = URL(string: "http://127.0.0.1:\(metricsPort.rawValue)/debug/vars") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: endpointURL)
        request.timeoutInterval = 2
        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard
            let httpResponse = response as? HTTPURLResponse,
            (200 ..< 300).contains(httpResponse.statusCode)
        else {
            throw URLError(.badServerResponse)
        }

        return try TrafficStatisticsParser.parse(responseData)
    }

    /// 分配 SOCKS 和 Metrics 服务所需的具名本地端口。
    func allocateLocalPorts() async throws -> LocalServicePorts {
        try await coreClient.allocateLocalPorts()
    }
}
