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

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            "没有可用的配置"
        case .invalidConfigurationEncoding:
            "无法将配置数据转换为字符串"
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

    /// 使用调用方固定的分享链接快照构建并执行延迟测试。
    func measureLatency(for shareLink: String) async throws -> Int {
        let normalizedShareLink = shareLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedShareLink.isEmpty else {
            throw XrayServiceError.missingConfiguration
        }

        let configurationData = try await configurationBuilder
            .makeLatencyTestConfigurationData(from: normalizedShareLink)
        guard let configurationJSON = String(data: configurationData, encoding: .utf8) else {
            throw XrayServiceError.invalidConfigurationEncoding
        }

        return try await coreClient.measureLatency(
            configurationJSON: configurationJSON,
            timeout: AppConstants.pingTimeout,
            targetURL: AppConstants.pingURL
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

    /// 分配 Metrics HTTP 服务所需的本地端口。
    func allocateLocalPorts() async throws -> LocalServicePorts {
        try await coreClient.allocateLocalPorts()
    }
}
