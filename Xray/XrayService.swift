//
//  XrayService.swift
//  Xray
//
//  Created by pan on 2025/9/19.
//

import Foundation
import Network
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "XrayService")

/// Coordinates app-level Xray operations without owning VPN lifecycle state.
struct XrayService {
    private let coreClient = XrayCoreClient.shared
    private let configurationBuilder = XrayConfigurationBuilder()

    // MARK: - Diagnostics

    /// Builds and runs a latency test through the current share link.
    func measureLatency() async throws -> Int {
        guard
            let shareLink = AppGroupStore.loadString(forKey: "configLink"),
            !shareLink.isEmpty
        else {
            throw NSError(
                domain: "XrayService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "没有可用的配置"]
            )
        }

        let configurationData = try await configurationBuilder
            .makeLatencyTestConfigurationData(from: shareLink)
        guard let configurationJSON = String(data: configurationData, encoding: .utf8) else {
            throw NSError(
                domain: "XrayService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "无法将配置数据转换为字符串"]
            )
        }

        let configurationFileURL = try SharedConfigurationFileStore.write(configurationJSON)
        guard let socksPort = AppGroupStore.loadPort(forKey: "socks5Port") else {
            throw NSError(
                domain: "XrayService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "无法从 UserDefaults 加载端口"]
            )
        }

        return try await coreClient.measureLatency(
            configurationFileURL: configurationFileURL,
            timeout: AppConstants.pingTimeout,
            targetURL: AppConstants.pingURL,
            proxyURL: URL(string: "socks5://127.0.0.1:\(socksPort.rawValue)")!
        )
    }

    /// Fetches the installed Xray Core version.
    func fetchCoreVersion() async throws -> String {
        try await coreClient.fetchCoreVersion()
    }

    /// Reads cumulative TUN traffic from the local Metrics HTTP endpoint.
    func fetchTrafficStatistics(
        on metricsPort: NWEndpoint.Port
    ) async -> (downlinkBytes: Int, uplinkBytes: Int)? {
        guard let endpointURL = URL(string: "http://127.0.0.1:\(metricsPort.rawValue)/debug/vars") else {
            return nil
        }

        do {
            let (responseData, response) = try await URLSession.shared.data(from: endpointURL)
            guard
                let httpResponse = response as? HTTPURLResponse,
                (200 ..< 300).contains(httpResponse.statusCode),
                let responseJSON = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                let stats = responseJSON["stats"] as? [String: Any],
                let inboundStats = stats["inbound"] as? [String: Any],
                let tunStats = inboundStats["tun-in"] as? [String: Any],
                let downlinkBytes = tunStats["downlink"] as? NSNumber,
                let uplinkBytes = tunStats["uplink"] as? NSNumber
            else {
                return nil
            }

            return (downlinkBytes: downlinkBytes.intValue, uplinkBytes: uplinkBytes.intValue)
        } catch {
            logger.error("获取流量统计失败: \(error.localizedDescription)")
            return nil
        }
    }

    /// Allocates the named local ports required by the SOCKS and Metrics services.
    func allocateLocalPorts() async -> LocalServicePorts {
        await coreClient.allocateLocalPorts()
    }
}
