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
                HStack {
                    Text("ID:")
                        .font(.headline)
                    Text(idText)
                        .padding()
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                }

                HStack {
                    Text("IP地址:")
                        .font(.headline)
                    Text(maskIPAddress(ipText))
                        .padding()
                    Spacer()
                }

                HStack {
                    Text("端口:")
                        .font(.headline)
                    Text(portText)
                        .padding()
                    Spacer()
                }

                HStack {
                    Text("本机sock5端口")
                        .padding(.leading, 10)

                    // 使用 String 绑定到 TextField
                    TextField("输入端口号", text: $sock5Text)
                        .padding()
                        .keyboardType(.default) // 允许任何输入
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                }
                .padding(.top, 20)

                if !clipboardText.isEmpty {
                    Text("剪贴板内容: \(clipboardText)")
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                }
            }
            .padding()

            Spacer() // Pushes the buttons down to the bottom

            VStack {
                switch packetTunnelManager.status {
                case .connected:
                    Button("断开") {
                        disconnectVPN()
                    }
                    .buttonStyle(ActionButtonStyle(color: .red))
                case .disconnected:
                    Button("连接") {
                        Task {
                            if let port = Int(sock5Text) {  // 检查端口号是否为有效的整数
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
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            parseDataFromFile()  // 视图加载时执行解析操作
        }
    }

    // 将 connectVPN 方法标记为 async，因为它调用了异步方法
    private func connectVPN(clipboardContent: String, port: Int) async throws {
        var configContent = clipboardContent

        // 如果剪贴板内容为空，则从本地文件读取配置
        if configContent.isEmpty {
            guard let savedContent = readClipboardContentFromFile(), !savedContent.isEmpty else {
                throw NSError(domain: "VPN Manager", code: 0, userInfo: [NSLocalizedDescriptionKey: "没有可用的配置，且剪贴板内容为空"])
            }
            configContent = savedContent
        } else {
            // 保存剪贴板内容到本地
            saveClipboardContentToFile(configContent)
        }

        // 异步调用 packetTunnelManager 的 start 方法
        try await packetTunnelManager.start(config: configContent, port: port)
    }

    private func disconnectVPN() {
        packetTunnelManager.stop()
    }

    private func parseDataFromFile() {
        let fileName = "clipboardContent.txt"
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent(fileName)

        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            print("文件内容: \(content)")

            // 解析 vless 格式的字符串
            if let url = URLComponents(string: content) {
                if let host = url.host {
                    ipText = host
                }
                
                if let idQuery = url.user {
                    idText = idQuery
                }
                
                if let port = url.port {
                    portText = String(port)
                }
            }
        } catch {
            print("读取文件失败: \(error.localizedDescription)")
        }
    }
    
    private func maskIPAddress(_ ipAddress: String) -> String {
        let components = ipAddress.split(separator: ".")
        guard components.count == 4 else {
            return ipAddress // Return the original IP if it's not in the correct format
        }
        return "*.*.*." + components[3]
    }
    
    private func pasteFromClipboard() {
        if let clipboardContent = UIPasteboard.general.string {
            clipboardText = clipboardContent
        } else {
            clipboardText = "剪贴板没有内容"
        }
    }
    
    private func readClipboardContentFromFile() -> String? {
        let fileName = "clipboardContent.txt"
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent(fileName)
        
        do {
            let savedContent = try String(contentsOf: fileURL, encoding: .utf8)
            print("从文件中读取的剪贴板内容: \(savedContent)")
            return savedContent
        } catch {
            print("读取剪贴板内容失败: \(error.localizedDescription)")
            return nil
        }
    }

    private func saveClipboardContentToFile(_ clipboardContent: String) {
        let fileName = "clipboardContent.txt"
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent(fileName)

        do {
            try clipboardContent.write(to: fileURL, atomically: true, encoding: .utf8)
            print("剪贴板内容已成功保存到文件: \(fileURL.path)")
        } catch {
            print("保存剪贴板内容失败: \(error.localizedDescription)")
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
