//
//  TrafficStatsView.swift
//  Xray
//
//  Created by pan on 2024/9/24.
//

import Foundation
import LibXray
import Network
import os
import SwiftUI

// MARK: - Logger

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "TrafficStatsView")

/// 一个显示网络流量统计信息的视图，包含下行和上行流量，并每秒更新一次。
struct TrafficStatsView: View {
    // MARK: - 环境与状态

    /// 通过 @EnvironmentObject 监听应用内的 PacketTunnelManager，用于获取 VPN/隧道的连接状态。
    @EnvironmentObject var packetTunnelManager: PacketTunnelManager

    /// 记录当前的下行流量（单位字节，字符串类型便于处理和显示）。
    @State private var downlinkTraffic: String = "0"

    /// 记录当前的上行流量（单位字节，字符串类型便于处理和显示）。
    @State private var uplinkTraffic: String = "0"

    /// 保存将用于流量查询的字符串，Base64 编码后传给 LibXray 进行通信。
    @State private var base64TrafficString: String = ""

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
            // 视图出现时，初始化流量查询所需的字符串
            do {
                try initializeTrafficString()
            } catch {
                // 您可以在此处使用 Alert 或其他方式提示用户错误信息
                logger.error("初始化流量字符串失败: \(error.localizedDescription)")
            }
        }
        .onReceive(timer) { _ in
            // 仅在隧道状态为已连接时才进行流量查询
            if packetTunnelManager.status == .connected {
                updateTrafficStats()
            }
        }
    }

    // MARK: - 初始化与更新流量

    /// 初始化 Base64 编码后的流量查询字符串，仅执行一次。
    ///
    /// - Throws: 当无法从 UserDefaults 中获取或解析端口数据时抛出错误。
    private func initializeTrafficString() throws {
        // 1. 从 UserDefaults 加载流量端口号字符串
        guard let trafficPortString = Util.loadFromUserDefaults(key: "trafficPort"),
              let trafficPort = NWEndpoint.Port(trafficPortString)
        else {
            throw NSError(
                domain: "ConfigurationError",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "无法从 UserDefaults 加载端口或端口格式不正确"]
            )
        }

        // 2. 组装可访问的流量查询地址，例如: http://127.0.0.1:xxxx/debug/vars
        let trafficQueryString = "http://127.0.0.1:\(trafficPort)/debug/vars"

        // 3. 转为 Data 并进行 Base64 编码
        if let trafficData = trafficQueryString.data(using: .utf8) {
            base64TrafficString = trafficData.base64EncodedString()
        } else {
            logger.error("无法将字符串转换为 Data")
        }
    }

    /// 每秒执行一次，向 Xray 查询最新的流量统计信息，并更新本地状态。
    private func updateTrafficStats() {
        // 1. 使用已保存的 base64TrafficString 向 LibXray 发送查询请求
        let responseBase64 = LibXrayQueryStats(base64TrafficString)

        // 2. 对返回结果做 Base64 解码
        guard let decodedData = Data(base64Encoded: responseBase64),
              let decodedString = String(data: decodedData, encoding: .utf8)
        else {
            logger.error("无法解码 LibXrayQueryStats 返回的数据")
            return
        }

        // 3. 对解码后的 JSON 进行二次解析，并提取上下行流量
        parseXrayResponse(decodedString)
    }

    // MARK: - 响应解析

    /// 将从 LibXray 返回的 JSON 字符串解析为字典结构，并提取所需的下行、上行流量信息。
    ///
    /// - Parameter response: Xray 返回的 JSON 字符串（解码后）。
    private func parseXrayResponse(_ response: String) {
        // 1. 将字符串转换为 JSON Data
        guard let jsonData = response.data(using: .utf8) else {
            logger.error("无法将响应字符串转换为 JSON Data")
            return
        }

        do {
            // 2. 将 JSON Data 转换为字典结构
            guard let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] else {
                logger.error("JSON 对象不是字典类型")
                return
            }

            // 3. 判断 success 是否为 1，表示请求成功
            guard let success = jsonObject["success"] as? Int, success == 1 else {
                logger.error("解析失败: success 字段不是 1")
                return
            }

            // 4. 获取 "data" 字段并确保其为字符串
            guard let dataValue = jsonObject["data"] else {
                logger.error("在 JSON 对象中找不到 data 字段")
                return
            }

            guard let dataString = dataValue as? String else {
                logger.error("data 字段不是字符串类型")
                return
            }

            // 5. 对 data 字段内嵌套的字符串再进行一次 JSON 解析
            guard let nestedJsonData = dataString.data(using: .utf8) else {
                logger.error("无法将 data 字符串转换为 Data")
                return
            }

            guard let dataDict = try JSONSerialization.jsonObject(with: nestedJsonData, options: []) as? [String: Any] else {
                logger.error("无法解析嵌套的 JSON 数据")
                return
            }

            // 6. 读取 "stats -> inbound -> socks" 对象
            guard let stats = dataDict["stats"] as? [String: Any],
                  let inbound = stats["inbound"] as? [String: Any],
                  let socks = inbound["socks"] as? [String: Any]
            else {
                logger.error("在 dataDict 中找不到 stats 或 inbound 或 socks 节点")
                return
            }

            // 7. 分别获取下行和上行流量，并转换为字符串存储
            guard let socksDownlink = socks["downlink"] as? Int,
                  let socksUplink = socks["uplink"] as? Int
            else {
                logger.error("无法获取 socks 下行或上行流量字段")
                return
            }

            // 8. 更新视图状态
            downlinkTraffic = String(socksDownlink)
            uplinkTraffic = String(socksUplink)

        } catch {
            logger.error("解析 JSON 时出错: \(error)")
        }
    }

    // MARK: - 辅助方法

    /// 将字节数转换为带有单位的可读字符串格式，如 “x.xx KB”、“x.xx MB” 或 “x.xx GB”。
    ///
    /// - Parameter bytesString: 表示字节数的字符串。如果无法转换为数值，则返回 "0 bytes"。
    /// - Returns: 带有合适单位（bytes、KB、MB 或 GB）的字符串。
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
