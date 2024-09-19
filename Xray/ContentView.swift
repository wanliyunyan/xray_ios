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
    @State private var idText: String = ""
    @State private var ipText: String = ""
    @State private var portText: String = ""
    @State private var sock5Text: String = "10808"  // 默认端口号，使用 String 类型

    var body: some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                InfoRow(label: "ID:", text: idText)
                InfoRow(label: "IP地址:", text: maskIPAddress(ipText))
                InfoRow(label: "端口:", text: portText)

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
            }
            .padding()

            Spacer() // Pushes the buttons to the bottom

            VStack {
                vpnControlButton()
                
                Button("从剪贴板粘贴") {
                    pasteFromClipboard()
                }
                .buttonStyle(ActionButtonStyle(color: .blue))
                .padding(.top, 20)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            loadDataFromUserDefaults()
        }
    }

    // MARK: - VPN Control Button
    @ViewBuilder
    private func vpnControlButton() -> some View {
        switch packetTunnelManager.status {
        case .connected:
            Button("断开") {
                disconnectVPN()
            }
            .buttonStyle(ActionButtonStyle(color: .red))
        case .disconnected:
            Button("连接") {
                connectIfValidPort()
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

    // MARK: - VPN Connection
    private func connectIfValidPort() {
        Task {
            if let port = Int(sock5Text) {
                do {
                    try await connectVPN(clipboardContent: clipboardText, port: port)
                } catch {
                    print("连接 VPN 失败: \(error.localizedDescription)")
                }
            } else {
                print("端口号无效")
            }
        }
    }

    private func connectVPN(clipboardContent: String, port: Int) async throws {
        var configContent = clipboardContent

        if configContent.isEmpty {
            guard let savedContent = loadFromUserDefaults(key: "clipboardContent"), !savedContent.isEmpty else {
                throw NSError(domain: "ContentView", code: 0, userInfo: [NSLocalizedDescriptionKey: "没有可用的配置，且剪贴板内容为空"])
            }
            configContent = savedContent
        }

        try await packetTunnelManager.start(config: configContent, port: port)
    }

    private func disconnectVPN() {
        packetTunnelManager.stop()
    }

    // MARK: - UserDefaults Handling
    private func loadDataFromUserDefaults() {
        if let content = loadFromUserDefaults(key: "clipboardContent") {
            parseContent(content)
        }
    }

    private func pasteFromClipboard() {
        if let clipboardContent = UIPasteboard.general.string {
            clipboardText = clipboardContent
            saveToUserDefaults(value: clipboardContent, key: "clipboardContent")
            parseContent(clipboardContent)
        } else {
            clipboardText = "剪贴板没有内容"
        }
    }

    private func saveToUserDefaults(value: String, key: String) {
        UserDefaults.standard.set(value, forKey: key)
        print("已保存到 UserDefaults")
    }

    private func loadFromUserDefaults(key: String) -> String? {
        return UserDefaults.standard.string(forKey: key)
    }

    // MARK: - Parsing
    private func parseContent(_ content: String) {
        if let url = URLComponents(string: content) {
            ipText = url.host ?? ""
            idText = url.user ?? ""
            portText = url.port.map(String.init) ?? ""
        }
    }

    // MARK: - Mask IP Address
    private func maskIPAddress(_ ipAddress: String) -> String {
        let components = ipAddress.split(separator: ".")
        return components.count == 4 ? "*.*.*." + components[3] : ipAddress
    }
}

// MARK: - Reusable View for Rows
struct InfoRow: View {
    var label: String
    var text: String

    var body: some View {
        HStack {
            Text(label)
                .font(.headline)
            Text(text)
                .padding()
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
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
