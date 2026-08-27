//
//  VPNConnectionControlView.swift
//  Xray
//
//  Created by pan on 2024/9/20.
//

import SwiftUI

/// 根据系统 VPN 状态显示连接、断开、进度或错误控件。
///
/// 视图本身不构建配置：连接操作由父视图注入，停止操作直接交给共享的
/// `PacketTunnelManager`。这种拆分让控件只负责状态映射和用户交互。
struct VPNConnectionControlView: View {
    /// 提供当前 VPN 生命周期状态，并执行停止操作。
    @Environment(PacketTunnelManager.self) private var packetTunnelManager

    /// 父视图是否正在执行连接预检或启动流程。
    let isStarting: Bool

    /// 用户点击“连接”时由父视图同步接管请求并持有异步任务。
    let onConnect: @MainActor @Sendable () -> Void

    /// 将状态相关控件放在具有统一内边距的容器中。
    var body: some View {
        connectionControl()
            .padding()
    }

    /// 根据 `NEVPNStatus` 构建唯一的操作控件或状态提示。
    ///
    /// 状态映射：
    /// - `.connected`：红色“断开”按钮；
    /// - `.disconnected`：绿色“连接”按钮；
    /// - `.connecting/.reasserting`：显示连接进度；
    /// - `.disconnecting`：显示断开进度；
    /// - `.invalid/nil`：提示无法取得状态；
    /// - 未来新增状态：显示未知状态，避免遗漏分支。
    ///
    /// - Returns: 与当前系统连接状态对应的 SwiftUI 视图。
    @ViewBuilder
    private func connectionControl() -> some View {
        switch packetTunnelManager.lifecycleState {
        case .connected:
            // 已连接时唯一允许的操作是请求系统停止隧道。
            Button("断开") {
                packetTunnelManager.stop()
            }
            .buttonStyle(PrimaryActionButtonStyle(backgroundColor: .red))
            .frame(maxWidth: .infinity, alignment: .center)

        case .disconnected, .failed:
            if isStarting {
                ProgressView("准备连接...")
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Button("连接", action: onConnect)
                    .buttonStyle(PrimaryActionButtonStyle(backgroundColor: .green))
                    .frame(maxWidth: .infinity, alignment: .center)
            }

        case .connecting, .reasserting:
            // reasserting 表示系统正在重新建立或应用隧道状态。
            VStack {
                ProgressView("连接中...")
            }
            .frame(maxWidth: .infinity, alignment: .center)

        case .disconnecting:
            // 停止是异步状态转换，完成前禁用其他操作。
            VStack {
                ProgressView("断开中...")
            }
            .frame(maxWidth: .infinity, alignment: .center)

        case .loading:
            ProgressView("初始化 VPN...")
                .frame(maxWidth: .infinity, alignment: .center)

        case .invalid:
            Text("无法获取 VPN 状态")
                .frame(maxWidth: .infinity, alignment: .center)

        @unknown default:
            Text("未知状态")
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}
