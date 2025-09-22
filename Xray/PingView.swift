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
    /// 负责执行 ping 请求的管理器，封装了网络延迟测试的具体实现。
    private let xrayManager = XrayManager()

    // MARK: - 环境变量

    /// 管理 VPN 隧道连接状态的对象，控制视图中刷新按钮的可用性和显示逻辑。
    @EnvironmentObject var packetTunnelManager: PacketTunnelManager

    // MARK: - 本地状态

    /// 保存最新的网络延迟值（单位：毫秒），用于界面显示。
    @State private var pingSpeed: Int = 0
    /// 标识是否已经成功获取到 Ping 测试结果，避免重复请求。
    @State private var isPingFetched: Bool = false
    /// 控制加载动画的显示状态，指示当前是否正在进行网络请求。
    @State private var isLoading: Bool = false

    // MARK: - 主视图

    /// 视图的主 UI 结构，包含显示 Ping 值、加载指示器以及刷新按钮。
    /// 根据当前状态动态展示不同的内容，提供用户交互以触发 Ping 请求。
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

    /// 执行 Ping 测试的异步方法，调用 XrayManager 进行网络延迟测量。
    /// 成功时更新 `pingSpeed` 和 `isPingFetched` 状态，失败时记录错误日志。
    /// 同时控制加载动画的显示与隐藏。
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

    /// 根据传入的 Ping 延迟值返回对应的颜色，用于界面视觉反馈。
    /// 延迟较低返回绿色，适中返回黄色，过高返回红色，未获取到返回黑色。
    /// - Parameter pingSpeed: 当前的 Ping 延迟值（毫秒）
    /// - Returns: 对应的颜色对象
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
