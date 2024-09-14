//
//  ContentView.swift
//  Xray
//
//  Created by pan on 2024/9/14.
//

import SwiftUI

@MainActor
struct ContentView: View {
    @EnvironmentObject var packetTunnelManager: PacketTunnelManager

    var body: some View {
        VStack {
            if let status = packetTunnelManager.status {
                switch status {
                case .connected:
                    Button("断开") {
                        disconnectVPN()
                    }
                case .disconnected:
                    Button("连接") {
                        connectVPN()
                    }
                default:
                    ProgressView()
                }
            } else {
                Text("无法获取 VPN 状态")
            }
        }
    }

    func connectVPN() {
        Task {
            do {
                try await packetTunnelManager.start()
            } catch {
                debugPrint("连接 VPN 失败: \(error.localizedDescription)")
            }
        }
    }

    func disconnectVPN() {
        packetTunnelManager.stop()
    }
}
