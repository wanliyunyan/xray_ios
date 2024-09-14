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

    var body: some View {
        VStack {
            switch packetTunnelManager.status {
            case .connected:
                Button("断开") {
                    disconnectVPN()
                }
                .buttonStyle(ActionButtonStyle(color: .red))
            case .disconnected:
                Button("连接") {
                    connectVPN(with: clipboardText)  // 将剪贴板内容传入
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

            // 增加“从剪贴板粘贴”按钮
            Button("从剪贴板粘贴") {
                pasteFromClipboard()
            }
            .buttonStyle(ActionButtonStyle(color: .blue))
            .padding(.top, 20)

            // 显示剪贴板中的内容
            if !clipboardText.isEmpty {
                Text("剪贴板内容: \(clipboardText)")
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
            }
        }
        .padding()
    }

    // 修改 connectVPN 以传递 clipboardText
    private func connectVPN(with clipboardContent: String) {
        Task {
            do {
                try await packetTunnelManager.start(with: clipboardContent)  // 传递 clipboardContent
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
