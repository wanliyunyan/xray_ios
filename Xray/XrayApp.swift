//
//  XrayApp.swift
//  Xray
//
//  Created by pan on 2024/9/14.
//

import SwiftUI
import NetworkExtension

@main
struct MGApp: App {
    
    @UIApplicationDelegateAdaptor var delegate: AppDelegate
    
    @StateObject private var packetTunnelManager = PacketTunnelManager()
    
    var body: some Scene {
        WindowGroup {
            VStack {
                // 动态显示“连接”或“断开”按钮
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
                        ProgressView()  // 状态变化时显示加载指示器
                    }
                }
            }
        }
    }
    
    // 连接 VPN 的方法
    func connectVPN() {
        Task(priority: .high) {
            do {
                try await packetTunnelManager.start()  // 执行连接操作
            } catch {
                debugPrint(error.localizedDescription)  // 如果发生错误，打印错误信息
            }
        }
    }
    
    // 断开 VPN 的方法
    func disconnectVPN() {
        Task(priority: .high) {
            packetTunnelManager.stop()  // 执行断开操作
        }
    }
}
