//
//  VPNControlView.swift
//  Xray
//
//  Created by pan on 2024/9/20.
//

import Foundation
import SwiftUI

struct VPNControlView: View {
    @EnvironmentObject var packetTunnelManager: PacketTunnelManager

    var connect: () async -> Void  // 传入一个方法，带两个端口

    var body: some View {
        VStack {
            vpnControlButton()
        }
        .padding()
    }

    // MARK: - VPN Control Button
    @ViewBuilder
    private func vpnControlButton() -> some View {
        switch packetTunnelManager.status {
        case .connected:
            Button("断开") {
                packetTunnelManager.stop()
            }
            .buttonStyle(ActionButtonStyle(color: .red))
            .frame(maxWidth: .infinity, alignment: .center) // 在内部居中

        case .disconnected:
            Button("连接") {
                Task {
                    await connect()
                }
            }
            .buttonStyle(ActionButtonStyle(color: .green))
            .frame(maxWidth: .infinity, alignment: .center) // 在内部居中

        case .connecting, .reasserting:
            VStack {
                ProgressView("连接中...")
            }
            .frame(maxWidth: .infinity, alignment: .center) // 在内部居中

        case .disconnecting:
            VStack {
                ProgressView("断开中...")
            }
            .frame(maxWidth: .infinity, alignment: .center) // 在内部居中

        case .invalid, .none:
            Text("无法获取 VPN 状态")
                .frame(maxWidth: .infinity, alignment: .center) // 在内部居中

        @unknown default:
            Text("未知状态")
                .frame(maxWidth: .infinity, alignment: .center) // 在内部居中
        }
    }
}
