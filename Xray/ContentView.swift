//
//  ContentView.swift
//  Xray
//
//  Created by pan on 2024/9/14.
//

import SwiftUI
import LibXray

struct PingRequest: Codable {
    var datDir: String?
    var configPath: String?
    var timeout: Int?
    var url: String?
    var proxy: String?
}

@MainActor
struct ContentView: View {
    @EnvironmentObject var packetTunnelManager: PacketTunnelManager
    @State private var clipboardText: String = ""
    @State private var idText: String = ""
    @State private var ipText: String = ""
    @State private var portText: String = ""
    @State private var path: String = ""
    @State private var isShowingShareModal = false // 控制弹窗显示
    @State private var showClipboardEmptyAlert = false // 用于控制显示空剪贴板的提示
    @State private var pingSpeed: Int = 0  // 用于显示网速的状态

    var body: some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                Text("vps信息:").font(.headline)
                InfoRow(label: "ID:", text: idText)
                InfoRow(label: "IP地址:", text: Util.maskIPAddress(ipText))
                InfoRow(label: "端口:", text: portText)

                ConnectedDurationView()

                TrafficStatsView()
                
                PingView().environmentObject(PacketTunnelManager.shared)
            }
            .padding()

            Spacer()

            // 剪贴板和分享配置按钮
            HStack {
                Button("从剪贴板粘贴") {
                    handlePasteFromClipboard()
                }
                .buttonStyle(ActionButtonStyle(color: .blue))

                Spacer() // 在按钮之间添加空隙

                Button("分享配置") {
                    isShowingShareModal = true
                }
                .buttonStyle(ActionButtonStyle(color: .yellow))
            }
            .padding(.horizontal)
            .padding(.top, 20)

            VPNControlView() { 
                await connectVPN()
            }
            
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
            fetchFreePorts()
        }
        // 弹出 ShareButton 作为模态视图
        .sheet(isPresented: $isShowingShareModal) {
            ShareModalView(isShowing: $isShowingShareModal) // 弹出新的视图
        }
        // 提示剪贴板为空
        .alert(isPresented: $showClipboardEmptyAlert) {
            Alert(title: Text("剪贴板为空"), message: Text("没有从剪贴板获取到内容"), dismissButton: .default(Text("确定")))
        }
    }

    // MARK: - VPN Connection
    private func connectVPN() async {
        do {
            if clipboardText.isEmpty {
                guard let savedContent = Util.loadFromUserDefaults(key: "clipboardContent"), !savedContent.isEmpty else {
                    throw NSError(domain: "ContentView", code: 0, userInfo: [NSLocalizedDescriptionKey: "没有可用的配置，且剪贴板内容为空"])
                }
                clipboardText = savedContent
            }

            let configData = try Configuration().buildConfigurationData(config: clipboardText)

            guard let mergedConfigString = String(data: configData, encoding: .utf8) else {
                throw NSError(domain: "ConfigDataError", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法将配置数据转换为字符串"])
            }

            let fileUrl = try Util.createConfigFile(with: mergedConfigString)

            // 启动 VPN
            try await packetTunnelManager.start(path: fileUrl.path)
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
            if !clipboardContent.isEmpty {
                let storedContent = Util.loadFromUserDefaults(key: "clipboardContent")
                if clipboardContent != storedContent {
                    clipboardText = clipboardContent
                    Util.saveToUserDefaults(value: clipboardContent, key: "clipboardContent")
                    Util.parseContent(clipboardContent, idText: &idText, ipText: &ipText, portText: &portText)
                }
            } else {
                print("剪贴板内容为空字符串")
                showClipboardEmptyAlert = true
            }
        } else {
            print("剪贴板内容为空")
            showClipboardEmptyAlert = true // 剪贴板为空时显示提示
        }
    }
    
    // MARK: - Fetch Free Ports
    private func fetchFreePorts() {
        // 调用 LibXray 获取 2 个可用端口的 Base64 字符串
        let freePortsBase64String = LibXrayGetFreePorts(2)

        // 解码 Base64 字符串
        guard let decodedData = Data(base64Encoded: freePortsBase64String),
              let decodedString = String(data: decodedData, encoding: .utf8) else {
            print("Base64 解码失败")
            return
        }

        // 解析 JSON
        do {
            if let jsonObject = try JSONSerialization.jsonObject(with: Data(decodedString.utf8), options: []) as? [String: Any],
               let success = jsonObject["success"] as? Bool, success, // 检查 success 是否为 true
               let data = jsonObject["data"] as? [String: Any],
               let ports = data["ports"] as? [Int], ports.count == 2 {
                
                // 保存端口到 UserDefaults
                Util.saveToUserDefaults(value: String(ports[0]), key: "sock5Port")
                Util.saveToUserDefaults(value: String(ports[1]), key: "trafficPort")
                
                print("获取到的端口: \(ports[0]), \(ports[1])")
            } else {
                print("解析 JSON 失败或未找到所需字段")
            }
        } catch {
            print("JSON 解析错误: \(error.localizedDescription)")
        }
    }

}
