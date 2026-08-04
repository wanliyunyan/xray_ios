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

/// 执行并显示当前分享配置的代理延迟测试。
///
/// 测试由 LibXray 使用独立 SOCKS 入站配置完成，不依赖已启动的 Packet Tunnel。视图首次出现
/// 时自动测试一次；VPN 未连接时显示手动刷新入口，连接期间隐藏刷新入口，避免与正在运行的
/// Xray 实例竞争底层运行时。
struct PingView: View {
    /// 负责构建 Ping 配置、调用 LibXray 并解析毫秒延迟。
    private let xrayManager = XrayManager()

    // MARK: - State

    /// 提供 VPN 状态，用于决定是否允许手动重新执行 Ping。
    @EnvironmentObject var packetTunnelManager: PacketTunnelManager

    /// 最近一次成功测试得到的延迟，单位为毫秒。
    @State private var pingSpeed: Int = 0

    /// 是否至少成功取得过一次结果，用于区分零值占位和真实显示状态。
    @State private var isPingFetched: Bool = false

    /// 当前是否有 Ping 任务执行，用于显示固定尺寸的加载指示器。
    @State private var isLoading: Bool = false

    /// 根据加载状态、测试结果和 VPN 状态组合延迟文本与刷新入口。
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
                    // Packet Tunnel 未运行时允许重新占用 LibXray 运行时执行测试。
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
            // 首次出现自动测试；已有成功结果时避免因父视图刷新重复请求。
            if !isPingFetched {
                requestPing()
            }
        }
    }

    // MARK: - Actions

    /// 异步执行延迟测试，并同步加载状态和最后一次成功结果。
    ///
    /// 方法立即进入加载状态，然后创建主 Actor 继承任务调用 `XrayManager.performPing()`。
    /// 成功时同时更新延迟和已获取标记；失败时保留上一次成功值并记录错误。任务结束后无论
    /// 成败都会关闭加载指示器。
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

    /// 按延迟区间返回状态颜色。
    ///
    /// - Parameter pingSpeed: 当前延迟，单位为毫秒。
    /// - Returns:
    ///   - `0`：黑色，表示尚无有效结果；
    ///   - `< 1000`：绿色，表示延迟相对较低；
    ///   - `1000 ..< 5000`：黄色，表示连接较慢；
    ///   - `>= 5000`：红色，表示连接很慢或接近超时。
    private func pingSpeedColor(_ pingSpeed: Int) -> Color {
        if pingSpeed == 0 {
            return .black
        }
        switch pingSpeed {
        case ..<1000:
            return .green
        case 1000 ..< 5000:
            return .yellow
        default:
            return .red
        }
    }
}
