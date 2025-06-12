//
//  PingView.swift
//  Xray
//
//  Created by pan on 2024/9/30.
//

import Combine
import Foundation
import LibXray
import Network
import os
import SwiftUI

// MARK: - Logger

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "PingView")

/// 一个用于测试网络延迟（Ping）的视图，展示并记录从服务器返回的网速信息。
struct PingView: View {
    // MARK: - 环境变量

    /// 自定义的 PacketTunnelManager，用于管理代理隧道的连接状态。
    @EnvironmentObject var packetTunnelManager: PacketTunnelManager

    // MARK: - 本地状态

    /// 记录最新一次获取到的 Ping 值（单位 ms）。
    @State private var pingSpeed: Int = 0
    /// 标记是否已经成功获取到 Ping 数据。
    @State private var isPingFetched: Bool = false
    /// 标记是否正在加载（请求中）。
    @State private var isLoading: Bool = false

    // MARK: - 主视图

    var body: some View {
        VStack {
            // 如果正在请求数据，显示加载提示
            if isLoading {
                Text("正在获取网速...")
            } else {
                HStack {
                    if isPingFetched {
                        Text("Ping网速:")
                        Text("\(pingSpeed)")
                            .foregroundColor(pingSpeedColor(pingSpeed))
                            .font(.headline)
                        Text("ms").foregroundColor(.black)
                    }
                    if packetTunnelManager.status != .connected {
                        Text("点击获取网速")
                            .foregroundColor(.blue)
                            .onTapGesture {
                                requestPing()
                            }
                    }
                }
            }
        }
    }

    // MARK: - 业务逻辑

    /// 请求 Ping 测试逻辑，包含获取配置、生成请求并调用 LibXrayPing。
    ///
    /// 调用此函数后，将首先显示加载状态，等待异步的 Ping 测试完成或出现错误。
    /// 若成功，将更新 `pingSpeed` 和 `isPingFetched`，并关闭加载状态。
    private func requestPing() {
        // 显示加载动画
        isLoading = true

        Task {
            do {
                // 1. 从 UserDefaults 或其他地方读取配置信息
                guard let savedContent = Util.loadFromUserDefaults(key: "configLink"),
                      !savedContent.isEmpty
                else {
                    throw NSError(
                        domain: "PingView",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "没有可用的配置，且剪贴板内容为空"]
                    )
                }

                // 2. 生成配置文件的最终字符串
                let configData = try Configuration().buildPingConfigurationData(config: savedContent)
                guard let mergedConfigString = String(data: configData, encoding: .utf8) else {
                    throw NSError(
                        domain: "PingView",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "无法将配置数据转换为字符串"]
                    )
                }

                // 3. 将配置字符串写入临时文件
                let fileUrl = try Util.createConfigFile(with: mergedConfigString)

                // 4. 读取 SOCKS5 代理端口
                guard let socks5PortString = Util.loadFromUserDefaults(key: "socks5Port"),
                      let socks5Port = NWEndpoint.Port(socks5PortString)
                else {
                    throw NSError(
                        domain: "ConfigurationError",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "无法从 UserDefaults 加载端口或端口格式不正确"]
                    )
                }

                // 5. 构造 Ping 请求
                let pingRequest = try createPingRequest(
                    configPath: fileUrl.path,
                    socks5Port: socks5Port
                )

                // 6. 将请求转换成 Base64 再调用 LibXrayPing
                let pingBase64String = try JSONEncoder().encode(pingRequest).base64EncodedString()

                // 7. 解析返回结果
                let pingResponseBase64 = LibXrayPing(pingBase64String)

                if let pingResult = await decodePingResponse(base64String: pingResponseBase64) {
                    // 更新本地状态
                    pingSpeed = pingResult
                    isPingFetched = true
                } else {
                    logger.error("Ping 解码失败")
                }
            } catch let error as NSError {
                // 业务逻辑错误提示
                logger.error("Ping 请求失败: \(error.localizedDescription)")
            } catch {
                // 未知错误
                logger.error("发生了未知错误: \(error.localizedDescription)")
            }

            // 隐藏加载动画
            isLoading = false
        }
    }

    /// 根据 `pingSpeed` 值获取不同的颜色。
    ///
    /// - Parameter pingSpeed: 当前的 Ping 值（ms）。
    /// - Returns: 对应的颜色对象。
    private func pingSpeedColor(_ pingSpeed: Int) -> Color {
        // 如果还未获取到 ping 值，保持黑色
        if pingSpeed == 0 {
            return .black
        }
        switch pingSpeed {
        case ..<1000:
            return .green // 0 ~ 999 ms 视为网络相对畅通
        case 1000 ..< 5000:
            return .yellow // 1000 ~ 4999 ms 视为较慢
        default:
            return .red // 超过 5000 ms 视为网络极慢或无法连接
        }
    }

    // MARK: - 辅助方法

    /// 创建一个 `PingRequest` 对象，用于封装需要给后端的完整参数。
    ///
    /// - Parameters:
    ///   - configPath: 配置文件在本地的路径。
    ///   - socks5Port: SOCKS5 代理使用的端口号。
    /// - Throws: 当参数无效时可能抛出错误。
    /// - Returns: 生成的 `PingRequest` 对象。
    @MainActor
    private func createPingRequest(configPath: String, socks5Port: NWEndpoint.Port) throws -> PingRequest {
        PingRequest(
            datDir: Constant.assetDirectory.path, // 数据文件目录
            configPath: configPath, // Xray 配置文件路径
            timeout: 30, // 超时时间（秒）
            url: "https://1.1.1.1", // 用于检测的网络地址
            proxy: "socks5://127.0.0.1:\(socks5Port)" // 使用的代理地址
        )
    }

    /// 解码 Base64 字符串为 JSON，并从中提取 "data" 字段中的网速信息。
    ///
    /// - Parameter base64String: Base64 编码的字符串，包含 Ping 测试结果。
    /// - Returns: 若成功解析，则返回表示 Ping 延迟（ms）的整数；若解析失败，返回 nil。
    @MainActor
    private func decodePingResponse(base64String: String) async -> Int? {
        guard let decodedData = Data(base64Encoded: base64String),
              let decodedString = String(data: decodedData, encoding: .utf8),
              let jsonData = decodedString.data(using: .utf8)
        else {
            logger.error("Base64 解码或字符串转 Data 失败")
            return nil
        }

        do {
            if let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any],
               let success = jsonObject["success"] as? Bool,
               success,
               let data = jsonObject["data"] as? Int
            {
                return data
            }
        } catch {
            logger.error("解析 JSON 失败: \(error.localizedDescription)")
        }

        return nil
    }
}
