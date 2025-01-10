//
//  TrafficStatsView.swift
//  Xray
//
//  Created by pan on 2024/9/24.
//

import Foundation
import LibXray
import Network
import SwiftUI

struct TrafficStatsView: View {
    @EnvironmentObject var packetTunnelManager: PacketTunnelManager // 监听 PacketTunnelManager 的状态
    @State private var downlinkTraffic: String = "0" // 下行流量
    @State private var uplinkTraffic: String = "0" // 上行流量

    @State private var base64TrafficString: String = "" // 用于保存初始化时的 Base64 编码的 trafficString

    // 定时器：每秒执行一次
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading) {
            Text("流量统计:").font(.headline)
            Text("下行流量: \(formatBytes(downlinkTraffic))") // 显示下行流量
            Text("上行流量: \(formatBytes(uplinkTraffic))") // 显示上行流量
        }
        .onAppear {
            do {
                try initializeTrafficString() // 处理可能抛出的错误
            } catch {
                print("初始化流量字符串失败: \(error.localizedDescription)")
            }
        }
        .onReceive(timer) { _ in
            // 仅在 VPN 连接后获取流量统计
            if packetTunnelManager.status == .connected {
                updateTrafficStats()
            }
        }
    }

    // 初始化 trafficString 并进行 Base64 编码，仅执行一次
    private func initializeTrafficString() throws {
        guard let trafficPortString = Util.loadFromUserDefaults(key: "trafficPort"),
              let trafficPort = NWEndpoint.Port(trafficPortString)
        else {
            throw NSError(domain: "ConfigurationError", code: 0, userInfo: [NSLocalizedDescriptionKey: "无法从 UserDefaults 加载端口或端口格式不正确"])
        }

        if let trafficString = "http://127.0.0.1:\(trafficPort)/debug/vars".data(using: .utf8) {
            base64TrafficString = trafficString.base64EncodedString()
        } else {
            print("字符串编码为 Data 失败")
        }
    }

    // 每秒执行一次的流量统计更新
    private func updateTrafficStats() {
        // 使用已保存的 base64TrafficString
        let res = LibXrayQueryStats(base64TrafficString) // 获取 Xray 的流量统计

        // 解码 Base64 返回的数据
        if let decodedData = Data(base64Encoded: res) {
            // 尝试将解码后的 Data 转换为字符串（假设是文本或 JSON 字符串）
            if let decodedString = String(data: decodedData, encoding: .utf8) {
                parseXrayResponse(decodedString)
            } else {
                print("无法将数据转换为 UTF-8 字符串")
            }
        } else {
            print("Base64 解码失败")
        }
    }

    private func parseXrayResponse(_ response: String) {
        // 尝试将 JSON 字符串转换为字典
        guard let jsonData = response.data(using: .utf8) else {
            print("无法将响应字符串转换为 jsonData")
            return
        }

        do {
            // 将 JSON 数据转换为字典对象
            guard let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] else {
                print("JSON 对象不是字典类型")
                return
            }

            // 检查 success 字段是否为 1
            guard let success = jsonObject["success"] as? Int, success == 1 else {
                print("解析失败：success 字段不是 1")
                return
            }

            // 获取 data 字段并确保其为字符串
            guard let dataValue = jsonObject["data"] else {
                print("jsonObject 中没有找到 data")
                return
            }

            // 如果 data 是字符串类型，尝试将其解析为 JSON
            guard let dataString = dataValue as? String else {
                print("data 不是字符串类型")
                return
            }

            // 将字符串转换为 Data
            guard let nestedJsonData = dataString.data(using: .utf8) else {
                print("无法将 data 字符串转换为 Data")
                return
            }

            // 尝试将字符串中的 JSON 解析为字典
            guard let dataDict = try JSONSerialization.jsonObject(with: nestedJsonData, options: []) as? [String: Any] else {
                print("无法解析嵌套的 JSON 数据")
                return
            }

            // 读取 stats 对象
            guard let stats = dataDict["stats"] as? [String: Any],
                  let inbound = stats["inbound"] as? [String: Any],
                  let socks = inbound["socks"] as? [String: Any]
            else {
                print("在 dataDict 中找不到 stats 或 inbound")
                return
            }

            // 获取 socks 的下行和上行流量
            guard let socksDownlink = socks["downlink"] as? Int,
                  let socksUplink = socks["uplink"] as? Int
            else {
                print("找不到 socks 的下行或上行流量")
                return
            }

            downlinkTraffic = String(socksDownlink)
            uplinkTraffic = String(socksUplink)

        } catch {
            print("解析 JSON 时出错: \(error)")
        }
    }

    // 将字节转换为 MB 或 GB
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
