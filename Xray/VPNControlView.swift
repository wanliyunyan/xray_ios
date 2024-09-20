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
    @State public var sock5Text: String  // 将默认值传递给子视图

    var connectIfValidPort: (Int) async -> Void  // 传入一个方法

    var body: some View {
        VStack {
            HStack {
                Text("本机sock5端口")
                    .padding(.leading, 10)

                TextField("输入端口号", text: $sock5Text)
                    .padding()
                    .keyboardType(.default)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
            }
            .padding(.top, 20)

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
        case .disconnected:
            Button("连接") {
                Task {
                    if let port = Int(sock5Text) {
                        await connectIfValidPort(port)
                    }
                }
            }
            .buttonStyle(ActionButtonStyle(color: .green))
        case .connecting, .reasserting:
            ProgressView("连接中...")
        case .disconnecting:
            ProgressView("断开中...")
        case .invalid, .none:
            Text("无法获取 VPN 状态")
        @unknown default:
            Text("未知状态")
        }
    }
}
