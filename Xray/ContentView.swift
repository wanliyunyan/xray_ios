//
//  ContentView.swift
//  Xray
//
//  Created by pan on 2024/9/14.
//

import SwiftUI

@MainActor
struct ContentView: View {
    @EnvironmentObject var packetTunnelManager: PacketTunnelManager // 监听 PacketTunnelManager 的状态
    @State private var clipboardText: String = ""
    @State private var idText: String = ""
    @State private var ipText: String = ""
    @State private var portText: String = ""

    var body: some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                Text("vps信息:").font(.headline)
                InfoRow(label: "ID:", text: idText)
                InfoRow(label: "IP地址:", text: Util.maskIPAddress(ipText))
                InfoRow(label: "端口:", text: portText)
                
                ConnectedDurationView()
                
                TrafficStatsView(trafficPort: Constant.trafficPort)

            }
            .padding()

            Spacer()
            
            VPNControlView(sock5Text: Constant.sock5Port,trafficPortText: Constant.trafficPort, connectIfValidPort: { sock5Port,trafficPort  in
                await connectVPN(sock5Port:sock5Port,trafficPort:trafficPort)
            })

            // 从剪贴板粘贴按钮
            HStack {
                Button("从剪贴板粘贴") {
                    handlePasteFromClipboard()
                }
                .buttonStyle(ActionButtonStyle(color: .blue))
                .padding(.horizontal)
            }
            .padding(.top, 20)

            // 版本号显示
            HStack {
                Spacer()
                VersionView()
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            loadDataFromUserDefaults()
        }
    }

    // MARK: - VPN Connection
    private func connectVPN(sock5Port: Int,trafficPort:Int) async {
        do {
            if clipboardText.isEmpty {
                guard let savedContent = Util.loadFromUserDefaults(key: "clipboardContent"), !savedContent.isEmpty else {
                    throw NSError(domain: "ContentView", code: 0, userInfo: [NSLocalizedDescriptionKey: "没有可用的配置，且剪贴板内容为空"])
                }
                clipboardText = savedContent
            }
            
            let configData = try Configuration().buildConfigurationData(inboundPort: sock5Port, trafficPort:trafficPort ,config: clipboardText)
            
            guard let mergedConfigString = String(data: configData, encoding: .utf8) else {
                throw NSError(domain: "ConfigDataError", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法将配置数据转换为字符串"])
            }
            
            try await packetTunnelManager.start(sock5Port: sock5Port, config: mergedConfigString)
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
