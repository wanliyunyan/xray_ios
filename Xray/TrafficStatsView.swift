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

/// 每秒读取并显示当前 Xray TUN 入站的累计上下行流量。
///
/// 视图从 App Group 偏好恢复 Metrics 端口，只在 VPN 为 `.connected` 时请求本地
/// `/debug/vars`。查询结果是连接期间的累计字节数，而不是瞬时带宽；查询失败时保留上一次
/// 成功值，等待下一次定时刷新重试。
struct TrafficStatsView: View {
    /// 封装本地 Metrics HTTP 请求与 JSON 解析。
    private let xrayManager = XrayManager()

    // MARK: - 环境与状态

    /// 用于判断隧道是否已连接，未连接时不发起无效 Metrics 请求。
    @EnvironmentObject var packetTunnelManager: PacketTunnelManager

    /// 当前 TUN 入站累计下行字节数，以字符串保存供格式化显示。
    @State private var downlinkTraffic: String = "0"

    /// 当前 TUN 入站累计上行字节数，以字符串保存供格式化显示。
    @State private var uplinkTraffic: String = "0"

    /// 从 App Group 偏好加载的 Metrics HTTP 服务端口。
    @State private var trafficPort: NWEndpoint.Port?

    /// 在主 RunLoop common mode 下每秒触发一次流量刷新。
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // MARK: - 主视图

    /// 展示格式化后的累计流量，并安装端口加载和每秒刷新逻辑。
    var body: some View {
        VStack(alignment: .leading) {
            Text("流量统计:")
                .font(.headline)
            Text("下行流量: \(formatBytes(downlinkTraffic))")
            Text("上行流量: \(formatBytes(uplinkTraffic))")
        }
        .onAppear {
            // Metrics 端口由 ContentView 分配，并用于构建 Xray metrics 配置。
            if let port = UtilStore.loadPort(key: "trafficPort") {
                trafficPort = port
            } else {
                logger.error("无法从 UserDefaults 加载端口或端口格式不正确")
            }
        }
        .onReceive(timer) { _ in
            // Metrics 仅在隧道运行期间可用。
            if packetTunnelManager.status == .connected, let port = trafficPort {
                Task {
                    if let stats = await xrayManager.getTrafficStats(trafficPort: port) {
                        downlinkTraffic = String(stats.downlink)
                        uplinkTraffic = String(stats.uplink)
                    }
                }
            }
        }
    }

    // MARK: - 辅助方法

    /// 将累计字节数字符串转换为易读单位。
    ///
    /// - Parameter bytesString: 十进制字节数字符串。
    /// - Returns: 小于 1 KB 时显示整数 bytes，其余按 1024 进制显示两位小数的 KB、MB 或 GB；
    ///   输入无法转换为数字时返回 `"0 bytes"`。
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
