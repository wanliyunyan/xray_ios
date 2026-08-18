//
//  TrafficStatistics.swift
//  Xray
//
//  Created by pan on 2026/8/17.
//

import Foundation

/// Xray TUN 入站累计流量。
struct TrafficStatistics: Equatable, Sendable {
    let downlinkBytes: Int
    let uplinkBytes: Int
}

/// 将 Xray Metrics `/debug/vars` 响应转换为应用使用的流量模型。
enum TrafficStatisticsParser {
    static func parse(_ data: Data) throws -> TrafficStatistics {
        let response = try JSONDecoder().decode(MetricsResponse.self, from: data)
        return TrafficStatistics(
            downlinkBytes: response.stats.inbound.tunnel.downlink,
            uplinkBytes: response.stats.inbound.tunnel.uplink
        )
    }
}

private struct MetricsResponse: Decodable {
    let stats: MetricsStats
}

private struct MetricsStats: Decodable {
    let inbound: InboundMetrics
}

private struct InboundMetrics: Decodable {
    let tunnel: TunnelMetrics

    enum CodingKeys: String, CodingKey {
        case tunnel = "tun-in"
    }
}

private struct TunnelMetrics: Decodable {
    let downlink: Int
    let uplink: Int
}
