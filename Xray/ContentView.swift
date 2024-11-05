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
    @State private var clipboardText: String = "" // 剪切板
    @State private var idText: String = "" // id
    @State private var ipText: String = "" // ip
    @State private var portText: String = "" // 端口
    @State private var path: String = "" // 配置地址
    @State private var isShowingShareModal = false // 控制弹窗显示
    @State private var showClipboardEmptyAlert = false // 用于控制显示空剪贴板的提示
    @State private var pingSpeed: Int = 0  // 用于显示网速的状态
    @State private var sock5Port: String = "" // 显示 sock5Port
    @State private var trafficPort: String = "" // 显示 trafficPort
    @State private var scannedCode: String? = nil // 扫描到的二维码内容
    @State private var isShowingScanner = false // 控制二维码扫描器显示

    var body: some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                Text("vps信息:").font(.headline)
                InfoRow(label: "ID:", text: idText)
                InfoRow(label: "IP地址:", text: Util.maskIPAddress(ipText))
                InfoRow(label: "端口:", text: portText)

                ConnectedDurationView()

                TrafficStatsView()

                Text("本机端口:").font(.headline)
                HStack {
                    Text("Sock5: \(sock5Port)")
                    Spacer() // 添加一个 Spacer，在两者之间创建空隙
                    Text("流量: \(trafficPort)")
                }

                PingView().environmentObject(PacketTunnelManager.shared)
                
                
            }
            .padding()

            DownloadView()
            HStack {
                Button(action: {
                    handlePasteFromClipboard()
                }) {
                    HStack {
                        Image(systemName: "clipboard") // 使用剪贴板图标
                            .resizable()
                            .frame(width: 30, height: 30)
                        Text("粘贴") // 添加汉字说明
                    }
                }

                Spacer() // 在按钮之间添加空隙

                Button(action: {
                    isShowingScanner = true
                }) {
                    HStack {
                        Image(systemName: "qrcode.viewfinder") // 使用二维码扫描图标
                            .resizable()
                            .frame(width: 30, height: 30)
                        Text("扫描") // 添加汉字说明
                    }
                }

                Spacer() // 在按钮之间添加空隙

                Button(action: {
                    isShowingShareModal = true
                }) {
                    HStack {
                        Image(systemName: "square.and.arrow.up") // 使用分享图标
                            .resizable()
                            .frame(width: 30, height: 30)
                        Text("分享") // 添加汉字说明
                    }
                }

            }
            .padding(.horizontal)

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
        // 弹出二维码扫描器
        .sheet(isPresented: $isShowingScanner) {
            QRCodeScannerView(scannedCode: $scannedCode)
                .onChange(of: scannedCode) { _, newState in
                    if let code = newState {
                        print(code)
                        clipboardText = code
                        Util.saveToUserDefaults(value: clipboardText, key: "configLink")
                        Util.parseContent(clipboardText, idText: &idText, ipText: &ipText, portText: &portText)
                        isShowingScanner = false // 扫描完成后立即关闭弹窗
                    }
                }
        }
    }

    // MARK: - VPN Connection
    private func connectVPN() async {
        do {
            try await packetTunnelManager.start()
        } catch {
            print("连接 VPN 时出错: \(error.localizedDescription)")
        }
    }

    // MARK: - UserDefaults Handling
    private func loadDataFromUserDefaults() {
        if let content = Util.loadFromUserDefaults(key: "configLink") {
            Util.parseContent(content, idText: &idText, ipText: &ipText, portText: &portText)
        }
    }

    // MARK: - Clipboard Handling
    private func handlePasteFromClipboard() {
        if let clipboardContent = Util.pasteFromClipboard() {
            if !clipboardContent.isEmpty {
                let storedContent = Util.loadFromUserDefaults(key: "configLink")
                if clipboardContent != storedContent {
                    clipboardText = clipboardContent
                    Util.saveToUserDefaults(value: clipboardContent, key: "configLink")
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
        let freePortsBase64String = LibXrayGetFreePorts(2)

        guard let decodedData = Data(base64Encoded: freePortsBase64String),
              let decodedString = String(data: decodedData, encoding: .utf8) else {
            print("Base64 解码失败")
            return
        }

        do {
            if let jsonObject = try JSONSerialization.jsonObject(with: Data(decodedString.utf8), options: []) as? [String: Any],
               let success = jsonObject["success"] as? Bool, success,
               let data = jsonObject["data"] as? [String: Any],
               let ports = data["ports"] as? [Int], ports.count == 2 {
                Util.saveToUserDefaults(value: String(ports[0]), key: "sock5Port")
                Util.saveToUserDefaults(value: String(ports[1]), key: "trafficPort")
                sock5Port = String(ports[0])
                trafficPort = String(ports[1])
                print("获取到的端口: \(ports[0]), \(ports[1])")
            } else {
                print("解析 JSON 失败或未找到所需字段")
            }
        } catch {
            print("JSON 解析错误: \(error.localizedDescription)")
        }
    }

}
