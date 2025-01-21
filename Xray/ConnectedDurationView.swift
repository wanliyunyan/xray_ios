//
//  ConnectedDurationView.swift
//  Xray
//
//  Created by pan on 2024/9/23.
//

import SwiftUI

/// 一个用于显示 VPN 连接时长的视图，当连接成功后会每秒自动更新显示时间。
struct ConnectedDurationView: View {
    // MARK: - 环境变量

    /// 用于获取当前 VPN（或代理隧道）的状态和连接时间。
    @EnvironmentObject private var packetTunnelManager: PacketTunnelManager

    // MARK: - 主视图

    var body: some View {
        VStack(alignment: .leading) {
            Text("连接时长:")
                .font(.headline) // 标签在上方

            // 当状态为已连接时，显示连接时长；否则默认显示 "00:00"
            if let status = packetTunnelManager.status, status == .connected {
                if let connectedDate = packetTunnelManager.connectedDate {
                    // TimelineView 会在指定时间间隔（此处为每秒）刷新视图
                    TimelineView(.periodic(from: Date(), by: 1.0)) { context in
                        Text(connectedDateString(
                            connectedDate: connectedDate,
                            current: context.date
                        ))
                        .monospacedDigit() // 将数字转化为等宽字体，视觉更整齐
                    }
                } else {
                    Text("00:00") // 若无 connectedDate，视为未获取到有效连接时间
                }
            } else {
                Text("00:00") // 未连接或断开时默认显示 "00:00"
            }
        }
    }

    // MARK: - 辅助方法

    /// 根据连接时间和当前时间，计算并返回格式化后的连接时长字符串。
    ///
    /// - Parameters:
    ///   - connectedDate: 表示 VPN 开始连接的时间。
    ///   - current: 用于对比计算的当前时间（由 `TimelineView` 提供）。
    /// - Returns: 格式形如 "HH:mm:ss" 或 "mm:ss" 的字符串。如果小时数为 0，则仅显示 "mm:ss"。
    private func connectedDateString(connectedDate: Date, current: Date) -> String {
        // 计算绝对时间差（单位：秒）
        let duration = Int64(abs(current.distance(to: connectedDate)))

        // 计算时、分、秒
        let hours = duration / 3600
        let minutes = (duration % 3600) / 60
        let seconds = duration % 60

        // 如果小时数为 0，则仅显示 mm:ss；否则显示 hh:mm:ss
        if hours <= 0 {
            return String(format: "%02d:%02d", minutes, seconds)
        } else {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
    }
}
