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

    var body: some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                InfoRow(label: "ID:", text: idText)
                InfoRow(label: "IP地址:", text: Util.maskIPAddress(ipText))
                InfoRow(label: "端口:", text: portText)
            }
            .padding()

            Spacer()

            VPNControlView(sock5Text: "10808", connectIfValidPort: { port in
                await connectVPN(port: port)
            })

            // 从剪贴板粘贴按钮，两侧留白
            HStack {
                Spacer() // 添加左侧空白
                Button("从剪贴板粘贴") {
                    handlePasteFromClipboard()
                }
                .buttonStyle(ActionButtonStyle(color: .blue))
                .padding(.horizontal) // 为按钮两侧添加适当的内边距
                Spacer() // 添加右侧空白
            }
            .padding(.top, 20)

            // 版本号居中显示
            HStack {
                Spacer() // 左侧空白
                VersionView() // 版本号视图
                Spacer() // 右侧空白
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            loadDataFromUserDefaults()
        }
    }

    // MARK: - VPN Connection
    private func connectVPN(port: Int) async {
        do {
            if clipboardText.isEmpty {
                guard let savedContent = Util.loadFromUserDefaults(key: "clipboardContent"), !savedContent.isEmpty else {
                    throw NSError(domain: "ContentView", code: 0, userInfo: [NSLocalizedDescriptionKey: "没有可用的配置，且剪贴板内容为空"])
                }
                clipboardText = savedContent
            }
            
            // 生成合并后的配置数据
            let configData = try Configuration().buildConfigurationData(inboundPort: port, config: clipboardText)
            
            // 将配置数据转换为字符串
            guard let mergedConfigString = String(data: configData, encoding: .utf8) else {
                throw NSError(domain: "ConfigDataError", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法将配置数据转换为字符串"])
            }
            
            try await packetTunnelManager.start(config: mergedConfigString, port: port)
        } catch {
            print("连接 VPN 时出错: \(error.localizedDescription)")
        }
    }

    // MARK: - UserDefaults Handling
    private func loadDataFromUserDefaults() {
        if let content = Util.loadFromUserDefaults(key: "clipboardContent") {
            Util.parseContent(content, idText: &idText, ipText: &ipText, portText: &portText)
        }
    }

    // MARK: - Clipboard Handling
    private func handlePasteFromClipboard() {
        if let clipboardContent = Util.pasteFromClipboard() {
            let storedContent = Util.loadFromUserDefaults(key: "clipboardContent")
            if clipboardContent != storedContent {
                clipboardText = clipboardContent
                Util.saveToUserDefaults(value: clipboardContent, key: "clipboardContent")
                Util.parseContent(clipboardContent, idText: &idText, ipText: &ipText, portText: &portText)
            }
        }
    }
}
