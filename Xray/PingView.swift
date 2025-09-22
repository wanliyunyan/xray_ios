//
//  PingView.swift
//  Xray
//
//  Created by pan on 2024/9/30.
//

import Combine
import Network
import os
import SwiftUI

// MARK: - Logger

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "PingView")

/// 一个用于测试网络延迟（Ping）的视图，展示并记录从服务器返回的网速信息。
struct PingView: View {
    
    private let xrayManager = XrayManager()
    
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
            HStack {
                Text("Ping(\(Constant.pingUrl)):")
                if isLoading {
                    ProgressView()
                        .frame(width: 24, height: 24)
                } else if isPingFetched {
                    Text("\(pingSpeed)")
                        .foregroundColor(pingSpeedColor(pingSpeed))
                        .font(.headline)
                }
                Text("ms").foregroundColor(.black)
                if packetTunnelManager.status != .connected {
                    Image(systemName: "arrow.clockwise")
                        .resizable()
                        .frame(width: 24, height: 24)
                        .foregroundColor(.blue)
                        .onTapGesture {
                            requestPing()
                        }
                }
            }
        }
        .onAppear {
            if !isPingFetched {
                requestPing()
            }
        }
    }

    // MARK: - 业务逻辑

    /// 请求 Ping 测试逻辑，包含获取配置、生成请求并调用 LibXrayPing。
    ///
    /// 调用此函数后，将首先显示加载状态，等待异步的 Ping 测试完成或出现错误。
    /// 若成功，将更新 `pingSpeed` 和 `isPingFetched`，并关闭加载状态。
    private func requestPing() {
        isLoading = true
        Task {
            do {
                let result = try await xrayManager.performPing()
                pingSpeed = result
                isPingFetched = true
            } catch {
                logger.error("Ping 请求失败: \(error.localizedDescription)")
            }
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
}
