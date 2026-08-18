//
//  ConnectionDurationView.swift
//  Xray
//
//  Created by pan on 2024/9/23.
//

import SwiftUI

/// 显示 VPN 当前连接时长，并在连接期间每秒刷新。
///
/// 视图只在状态为 `.connected` 且系统提供 `connectedDate` 时启动 `TimelineView`；其他状态
/// 统一显示 `00:00`。`TimelineView` 只驱动时间文本刷新，不创建额外计时器状态。
struct ConnectionDurationView: View {
    /// 提供 VPN 状态和系统记录的连接建立时间。
    @Environment(PacketTunnelManager.self) private var packetTunnelManager

    /// 根据连接状态选择静态占位时间或每秒更新的持续时间。
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("连接时长:")
                .font(.headline)

            if packetTunnelManager.lifecycleState.isConnected {
                if let connectedDate = packetTunnelManager.connectedDate {
                    // 连接期间每秒重新计算一次显示文本。
                    TimelineView(.periodic(from: Date(), by: 1.0)) { context in
                        Text(formattedDuration(
                            from: connectedDate,
                            to: context.date
                        ))
                        .monospacedDigit()
                    }
                } else {
                    Text("00:00")
                }
            } else {
                Text("00:00")
            }
        }
    }

    /// 计算并格式化连接开始时间到当前时间的间隔。
    ///
    /// - Parameters:
    ///   - startDate: NetworkExtension 记录的连接建立时间。
    ///   - endDate: `TimelineView` 当前刷新时刻。
    /// - Returns: 一小时内为 `mm:ss`，达到一小时后为 `HH:mm:ss`。
    /// - Note: 系统时间变化导致开始时间晚于当前时间时按零处理。
    private func formattedDuration(from startDate: Date, to endDate: Date) -> String {
        let duration = max(0, Int64(startDate.distance(to: endDate)))

        let hours = duration / 3600
        let minutes = (duration % 3600) / 60
        let seconds = duration % 60

        if hours <= 0 {
            return "\(twoDigit(minutes)):\(twoDigit(seconds))"
        } else {
            return "\(twoDigit(hours)):\(twoDigit(minutes)):\(twoDigit(seconds))"
        }
    }

    private func twoDigit(_ value: Int64) -> String {
        value < 10 ? "0\(value)" : String(value)
    }
}
