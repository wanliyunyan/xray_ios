//
//  LatencyTestView.swift
//  Xray
//
//  Created by pan on 2024/9/30.
//

import os
import SwiftUI

// MARK: - 日志

private let logger = Logger(subsystem: AppConstants.loggingSubsystem, category: "LatencyTestView")

/// 执行并显示当前分享配置的代理延迟测试。
///
/// 测试由 LibXray 使用独立 SOCKS 入站配置完成，不依赖已启动的 Packet Tunnel。视图首次出现
/// 时自动测试一次；VPN 未连接时显示手动刷新入口，连接期间隐藏刷新入口，避免与正在运行的
/// Xray 实例竞争底层运行时。
struct LatencyTestView: View {
    /// 负责构建 Ping 配置、调用 LibXray 并解析毫秒延迟。
    private let xrayService = XrayService()

    // MARK: - 状态

    /// 提供 VPN 状态，用于决定是否允许手动重新执行 Ping。
    @Environment(PacketTunnelManager.self) private var packetTunnelManager

    /// 延迟测试依赖的 SOCKS 端口准备状态。
    @Environment(AppSessionState.self) private var appSessionState

    /// 最近一次成功测试得到的延迟，单位为毫秒。
    @State private var latencyMilliseconds: Int = 0

    /// 是否至少成功取得过一次结果，用于区分零值占位和真实显示状态。
    @State private var hasLatencyResult = false

    /// 当前是否有 Ping 任务执行，用于显示固定尺寸的加载指示器。
    @State private var isTesting = false

    /// 根据加载状态、测试结果和 VPN 状态组合延迟文本与刷新入口。
    var body: some View {
        VStack {
            HStack {
                Text("Ping(\(AppConstants.pingURL.absoluteString)):")
                if isTesting {
                    ProgressView()
                        .frame(width: 24, height: 24)
                } else if hasLatencyResult {
                    Text("\(latencyMilliseconds)")
                        .foregroundStyle(latencyColor(for: latencyMilliseconds))
                        .font(.headline)
                }
                Text("ms")
                    .foregroundStyle(.primary)
                if !packetTunnelManager.lifecycleState.isConnected {
                    // Packet Tunnel 未运行时允许重新占用 LibXray 运行时执行测试。
                    Button {
                        Task {
                            await runLatencyTest()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 24))
                    }
                    .disabled(!appSessionState.areLocalPortsReady || isTesting)
                    .accessibilityLabel("重新测试延迟")
                }
            }
        }
        .task(id: testContext) {
            guard
                testContext.canRunAutomatically,
                !hasLatencyResult
            else {
                return
            }
            await runLatencyTest()
        }
    }

    // MARK: - 操作

    private var testContext: LatencyTestContext {
        LatencyTestContext(
            areLocalPortsReady: appSessionState.areLocalPortsReady,
            lifecycleState: packetTunnelManager.lifecycleState
        )
    }

    /// 异步执行延迟测试，并同步加载状态和最后一次成功结果。
    ///
    /// 方法立即进入加载状态并调用 `XrayService.measureLatency()`。成功时同时更新延迟和
    /// 已获取标记；失败时保留上一次成功值并记录错误。任务结束后无论成败都会关闭加载指示器。
    private func runLatencyTest() async {
        guard appSessionState.areLocalPortsReady, !isTesting else {
            return
        }

        isTesting = true
        defer { isTesting = false }

        do {
            let measuredLatency = try await xrayService.measureLatency()
            try Task.checkCancellation()
            latencyMilliseconds = measuredLatency
            hasLatencyResult = true
        } catch is CancellationError {
            return
        } catch {
            logger.error("Ping 请求失败: \(error.localizedDescription)")
        }
    }

    /// 按延迟区间返回状态颜色。
    ///
    /// - Parameter latencyMilliseconds: 当前延迟，单位为毫秒。
    /// - Returns:
    ///   - `0`：黑色，表示尚无有效结果；
    ///   - `< 1000`：绿色，表示延迟相对较低；
    ///   - `1000 ..< 5000`：黄色，表示连接较慢；
    ///   - `>= 5000`：红色，表示连接很慢或接近超时。
    private func latencyColor(for latencyMilliseconds: Int) -> Color {
        if latencyMilliseconds == 0 {
            return .black
        }
        switch latencyMilliseconds {
        case ..<1000:
            return .green
        case 1000 ..< 5000:
            return .yellow
        default:
            return .red
        }
    }
}

private struct LatencyTestContext: Equatable {
    let areLocalPortsReady: Bool
    let lifecycleState: VPNLifecycleState

    var canRunAutomatically: Bool {
        areLocalPortsReady && lifecycleState == .disconnected
    }
}
