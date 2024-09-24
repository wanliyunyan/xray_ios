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
    @State public var trafficPortText: String  // 新增的本机流量端口文本

    var connectIfValidPort: (Int, Int) async -> Void  // 传入一个方法，带两个端口

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

//            HStack {
//                Text("本机流量端口")
//                    .padding(.leading, 10)
//
//                TextField("输入流量端口号", text: $trafficPortText)
//                    .padding()
//                    .keyboardType(.default)
//                    .background(Color.gray.opacity(0.2))
//                    .cornerRadius(8)
//            }
//            .padding(.top, 10)

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
                    if let sock5Port = Int(sock5Text), let trafficPort = Int(trafficPortText) {
                        await connectIfValidPort(sock5Port, trafficPort)
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
