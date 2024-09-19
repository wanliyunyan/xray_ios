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
    @State private var clipboardText: String = ""
    @State private var portText: String = "10808"  // 默认端口号，使用 String 类型

    var body: some View {
        VStack {
            HStack {
                Text("本机sock5端口")
                    .padding(.leading, 10)

                // 使用 String 绑定到 TextField
                TextField("输入端口号", text: $portText)
                    .padding()
                    .keyboardType(.default) // 允许任何输入
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
            }
            .padding(.top, 20)
            
            switch packetTunnelManager.status {
            case .connected:
                Button("断开") {
                    disconnectVPN()
                }
                .buttonStyle(ActionButtonStyle(color: .red))
            case .disconnected:
                Button("连接") {
                    if let port = Int(portText) {  // 检查端口号是否为有效的整数
                        connectVPN(clipboardContent: clipboardText, port: port)
                    } else {
                        print("端口号无效")
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

            Button("从剪贴板粘贴") {
                pasteFromClipboard()
            }
            .buttonStyle(ActionButtonStyle(color: .blue))
            .padding(.top, 20)

            if !clipboardText.isEmpty {
                Text("剪贴板内容: \(clipboardText)")
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
            }
        }
        .padding()
    }

    private func connectVPN(clipboardContent: String, port: Int) {
        Task {
            do {
                try await packetTunnelManager.start(clipboardContent: clipboardContent, port: port)  // 传递剪贴板内容和端口号
            } catch {
                print("连接 VPN 失败: \(error.localizedDescription)")
            }
        }
    }

    private func disconnectVPN() {
        packetTunnelManager.stop()
    }

    private func pasteFromClipboard() {
        if let clipboardContent = UIPasteboard.general.string {
            clipboardText = clipboardContent
        } else {
            clipboardText = "剪贴板没有内容"
        }
    }
}

struct ActionButtonStyle: ButtonStyle {
    var color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding()
            .background(color)
            .foregroundColor(.white)
            .cornerRadius(8)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}
