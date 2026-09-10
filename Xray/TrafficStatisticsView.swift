//
//  TrafficStatisticsView.swift
//  Xray
//
//  Created by pan on 2024/9/24.
//

import Network
import os
import SwiftUI

// MARK: - 日志

private let logger = Logger(subsystem: AppConstants.loggingSubsystem, category: "TrafficStatisticsView")

/// 每秒读取并显示当前 Xray TUN 入站的累计上下行流量。
///
/// 视图使用应用会话统一分配的 Metrics 端口，只在 VPN 为 `.connected` 时请求本地
/// `/debug/vars`。连接后给 Metrics 一个短暂的就绪窗口；串行轮询任务随连接状态、端口
/// 或视图生命周期自动取消。查询失败时保留上一次成功值，连续失败达到阈值后才
/// 记录错误。
struct TrafficStatisticsView: View {
    /// 封装本地 Metrics HTTP 请求与 JSON 解析。
    private let xrayService = XrayService()

    // MARK: - 环境与状态

    /// 用于判断隧道是否已连接，未连接时不发起无效 Metrics 请求。
    @Environment(PacketTunnelManager.self) private var packetTunnelManager

    /// 提供当前进程唯一的 Metrics 端口及其准备状态。
    @Environment(AppSessionState.self) private var appSessionState

    /// 当前 TUN 入站累计下行字节数。
    @State private var downlinkBytes = 0

    /// 当前 TUN 入站累计上行字节数。
    @State private var uplinkBytes = 0

    // MARK: - 主视图

    /// 展示格式化后的累计流量，并安装端口加载和每秒刷新逻辑。
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("流量统计:")
                .font(.headline)
            Text("下行流量: \(formattedByteCount(downlinkBytes))")
            Text("上行流量: \(formattedByteCount(uplinkBytes))")
        }
        .task(id: pollingContext) {
            let context = pollingContext
            guard let metricsPort = context.resolvedMetricsPort else {
                return
            }
            await pollTrafficStatistics(on: metricsPort)
        }
    }

    // MARK: - 辅助方法

    private var pollingContext: TrafficPollingContext {
        TrafficPollingContext(
            isConnected: packetTunnelManager.lifecycleState.isConnected,
            areLocalPortsReady: appSessionState.areLocalPortsReady,
            metricsPort: appSessionState.metricsPort.rawValue
        )
    }

    /// 串行查询 Metrics；连接状态或端口变化时由 SwiftUI 自动取消。
    private func pollTrafficStatistics(on metricsPort: NWEndpoint.Port) async {
        do {
            // Xray 进入 running 后，Metrics HTTP 监听仍可能需要一个很短的就绪窗口。
            try await Task.sleep(for: .seconds(1))
        } catch {
            return
        }

        var failureTracker = TrafficPollingFailureTracker()
        while !Task.isCancelled {
            do {
                let statistics = try await xrayService.fetchTrafficStatistics(
                    on: metricsPort
                )
                failureTracker.recordSuccess()
                if downlinkBytes != statistics.downlinkBytes {
                    downlinkBytes = statistics.downlinkBytes
                }
                if uplinkBytes != statistics.uplinkBytes {
                    uplinkBytes = statistics.uplinkBytes
                }
            } catch {
                guard !isCancellation(error) else {
                    return
                }
                if failureTracker.recordFailure() {
                    let failureCount = failureTracker.consecutiveFailureCount
                    logger.error(
                        "连续 \(failureCount) 次获取流量统计失败: \(error.localizedDescription)"
                    )
                }
            }

            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
        }
    }

    /// 将累计字节数转换为易读单位。
    ///
    /// - Parameter byteCount: 累计字节数。
    /// - Returns: 小于 1 KB 时显示整数 bytes，其余按 1024 进制显示两位小数的 KB、MB 或 GB；
    ///   小于 1 KB 时直接显示整数值。
    private func formattedByteCount(_ byteCount: Int) -> String {
        let bytes = Double(byteCount)

        let kilobyte = 1024.0
        let megabyte = kilobyte * 1024
        let gigabyte = megabyte * 1024

        if bytes >= gigabyte {
            return formatted(bytes / gigabyte, unit: "GB")
        } else if bytes >= megabyte {
            return formatted(bytes / megabyte, unit: "MB")
        } else if bytes >= kilobyte {
            return formatted(bytes / kilobyte, unit: "KB")
        } else {
            return "\(byteCount) bytes"
        }
    }

    private func formatted(_ value: Double, unit: String) -> String {
        let number = value.formatted(.number.precision(.fractionLength(2)))
        return "\(number) \(unit)"
    }

    private func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}

struct TrafficPollingContext: Equatable {
    let isConnected: Bool
    let areLocalPortsReady: Bool
    let metricsPort: UInt16

    var shouldPoll: Bool {
        isConnected && areLocalPortsReady && metricsPort != 0
    }

    var resolvedMetricsPort: NWEndpoint.Port? {
        guard shouldPoll else {
            return nil
        }
        return NWEndpoint.Port(rawValue: metricsPort)
    }
}

struct TrafficPollingFailureTracker {
    private let reportingThreshold: Int
    private(set) var consecutiveFailureCount = 0

    init(reportingThreshold: Int = 3) {
        precondition(reportingThreshold > 0)
        self.reportingThreshold = reportingThreshold
    }

    mutating func recordSuccess() {
        consecutiveFailureCount = 0
    }

    mutating func recordFailure() -> Bool {
        consecutiveFailureCount += 1
        return consecutiveFailureCount == reportingThreshold
    }
}
