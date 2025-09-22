//
//  TrafficStatsView.swift
//  Xray
//
//  Created by pan on 2024/9/24.
//

import Network
import os
import SwiftUI

// MARK: - Logger

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "TrafficStatsView")

/// 一个显示网络流量统计信息的视图，包含下行和上行流量，并每秒更新一次。
struct TrafficStatsView: View {
    private let xrayManager = XrayManager()

    // MARK: - 环境与状态

    /// 通过 @EnvironmentObject 监听应用内的 PacketTunnelManager，用于获取 VPN/隧道的连接状态。
    @EnvironmentObject var packetTunnelManager: PacketTunnelManager

    /// 记录当前的下行流量（单位字节，字符串类型便于处理和显示）。
    @State private var downlinkTraffic: String = "0"

    /// 记录当前的上行流量（单位字节，字符串类型便于处理和显示）。
    @State private var uplinkTraffic: String = "0"

    /// 保存从 UserDefaults 加载的流量端口号。
    @State private var trafficPort: NWEndpoint.Port?

    /// 定时器：每隔 1 秒触发一次，用于刷新流量数据。
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // MARK: - 主视图

    var body: some View {
        VStack(alignment: .leading) {
            Text("流量统计:")
                .font(.headline)
            Text("下行流量: \(formatBytes(downlinkTraffic))")
            Text("上行流量: \(formatBytes(uplinkTraffic))")
        }
        .onAppear {
            // 视图出现时，加载流量端口号
            if let port = UtilStore.loadPort(key: "trafficPort") {
                trafficPort = port
            } else {
                logger.error("无法从 UserDefaults 加载端口或端口格式不正确")
            }
        }
        .onReceive(timer) { _ in
            // 仅在隧道状态为已连接且 trafficPort 有效时才进行流量查询
            if packetTunnelManager.status == .connected, let port = trafficPort {
                if let stats = xrayManager.getTrafficStats(trafficPort: port) {
                    downlinkTraffic = String(stats.downlink)
                    uplinkTraffic = String(stats.uplink)
                }
            }
        }
    }

    // MARK: - 辅助方法

    /**
     将字节数转换为带有单位的可读字符串格式，如 “x.xx KB”、“x.xx MB” 或 “x.xx GB”。

     - Parameters:
       - bytesString: 表示字节数的字符串。如果无法转换为数值，则返回 "0 bytes"。

     - Returns:
       带有合适单位（bytes、KB、MB 或 GB）的字符串。

     - Throws:

     - Note:
       如果 bytesString 不能转换为数值，则返回 "0 bytes"。例如，输入 "2048" 返回 "2.00 KB"。
     */
    private func formatBytes(_ bytesString: String) -> String {
        guard let bytes = Double(bytesString) else { return "0 bytes" }

        let kilobyte = 1024.0
        let megabyte = kilobyte * 1024
        let gigabyte = megabyte * 1024

        if bytes >= gigabyte {
            return String(format: "%.2f GB", bytes / gigabyte)
        } else if bytes >= megabyte {
            return String(format: "%.2f MB", bytes / megabyte)
        } else if bytes >= kilobyte {
            return String(format: "%.2f KB", bytes / kilobyte)
        } else {
            return "\(Int(bytes)) bytes"
        }
    }
}
