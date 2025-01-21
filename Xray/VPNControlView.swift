//
//  VPNControlView.swift
//  Xray
//
//  Created by pan on 2024/9/20.
//

import Foundation
import SwiftUI

/// 一个用于管理和展示 VPN 连接状态及操作（连接 / 断开）的视图。
struct VPNControlView: View {
    // MARK: - 环境变量

    /// 通过 EnvironmentObject 获取到全局的 PacketTunnelManager，用于读写 VPN 的连接状态。
    @EnvironmentObject var packetTunnelManager: PacketTunnelManager

    // MARK: - 外部依赖

    /// 一个异步方法，用于发起 VPN 连接操作。
    /// - 注意：您可以在外部实现此方法，以包含必要的端口或参数，并在此处传入。
    var connect: () async -> Void

    // MARK: - 主视图

    var body: some View {
        VStack {
            vpnControlButton()
        }
        .padding()
    }

    // MARK: - 辅助视图构建

    /// 根据 PacketTunnelManager 的当前状态来返回不同的操作按钮或提示。
    ///
    /// - Returns: 不同状态对应的 `View`，包括 “连接” 按钮、“断开” 按钮、加载进度视图、或错误提示文本。
    @ViewBuilder
    private func vpnControlButton() -> some View {
        switch packetTunnelManager.status {
        case .connected:
            // 已连接：显示“断开”按钮
            Button("断开") {
                packetTunnelManager.stop()
            }
            .buttonStyle(ActionButtonStyle(color: .red))
            .frame(maxWidth: .infinity, alignment: .center)

        case .disconnected:
            // 已断开：显示“连接”按钮
            Button("连接") {
                Task {
                    await connect()
                }
            }
            .buttonStyle(ActionButtonStyle(color: .green))
            .frame(maxWidth: .infinity, alignment: .center)

        case .connecting, .reasserting:
            // 连接中或重新连接中：显示加载进度
            VStack {
                ProgressView("连接中...")
            }
            .frame(maxWidth: .infinity, alignment: .center)

        case .disconnecting:
            // 断开中：显示加载进度
            VStack {
                ProgressView("断开中...")
            }
            .frame(maxWidth: .infinity, alignment: .center)

        case .invalid, .none:
            // 无效或无法获取的状态
            Text("无法获取 VPN 状态")
                .frame(maxWidth: .infinity, alignment: .center)

        @unknown default:
            // 未来可能出现的新状态
            Text("未知状态")
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}
