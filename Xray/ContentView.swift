//
//  ContentView.swift
//  Xray
//
//  Created by pan on 2024/9/14.
//

import LibXray
import SwiftUI

// MARK: - 数据模型

/// 用于封装 Ping 请求参数的结构体，符合 Codable 协议，方便与 JSON 编解码。
struct PingRequest: Codable {
    var datDir: String?
    var configPath: String?
    var timeout: Int?
    var url: String?
    var proxy: String?
}

// MARK: - 主视图

/// 整个应用的核心主视图，负责展示和管理用户粘贴、二维码扫描、VPN 连接、流量统计、分享等功能模块。
@MainActor
struct ContentView: View {
    // MARK: - 环境对象

    /// 全局共享的 `PacketTunnelManager`，用于获取和更新当前 VPN 的连接状态。
    @EnvironmentObject var packetTunnelManager: PacketTunnelManager

    // MARK: - 本地状态

    /// 保存剪贴板的内容（例如 VMess / VLESS 配置链接）。
    @State private var clipboardText: String = ""

    /// 从配置内容中解析出的 ID。
    @State private var idText: String = ""

    /// 从配置内容中解析出的 IP 地址或域名。
    @State private var ipText: String = ""

    /// 从配置内容中解析出的端口号（如远程服务器端口）。
    @State private var portText: String = ""

    /// Xray 配置文件的路径（若使用本地存储或文件管理可用）。
    @State private var path: String = ""

    /// 控制 “分享配置” 弹窗是否显示。
    @State private var isShowingShareModal = false

    /// 控制当剪贴板为空时是否显示提示 Alert。
    @State private var showClipboardEmptyAlert = false

    /// 用于显示或存储当前的 Ping 速度（ms）。
    @State private var pingSpeed: Int = 0

    /// 用于在界面上显示 SOCKS 端口（本地代理端口）。
    @State private var sock5Port: String = ""

    /// 用于在界面上显示流量统计端口。
    @State private var trafficPort: String = ""

    /// 扫描到的二维码内容。
    @State private var scannedCode: String? = nil

    /// 控制二维码扫描器视图是否显示。
    @State private var isShowingScanner = false

    // MARK: - 主布局

    var body: some View {
        VStack(alignment: .leading) {
            // 顶部区域：展示配置信息、连接时长、流量统计等
            VStack(alignment: .leading) {
                Text("vps信息:")
                    .font(.headline)

                InfoRow(label: "ID:", text: idText)
                InfoRow(label: "IP地址:", text: Util.maskIPAddress(ipText))
                InfoRow(label: "端口:", text: portText)

                // 显示当前的 VPN 连接时长
                ConnectedDurationView()

                // 显示当前流量统计（上行、下行）
                TrafficStatsView()

                // 本机端口信息
                Text("本机端口:")
                    .font(.headline)
                HStack {
                    Text("Sock5: \(sock5Port)")
                    Spacer()
                    Text("流量: \(trafficPort)")
                }

                // Ping 测速视图
                PingView().environmentObject(PacketTunnelManager.shared)

                // 选择 VPN 工作模式（全局 / 非全局等）
                VPNModePickerView()
            }
            .padding()

            // 下载相关视图（如果有需要展示或触发下载逻辑）
            DownloadView()

            // 中间操作区：包含粘贴、扫描和分享按钮
            HStack {
                // 粘贴按钮
                Button(action: {
                    handlePasteFromClipboard()
                }) {
                    HStack {
                        Image(systemName: "clipboard")
                            .resizable()
                            .frame(width: 30, height: 30)
                        Text("粘贴")
                    }
                }

                Spacer()

                // 扫描按钮
                Button(action: {
                    isShowingScanner = true
                }) {
                    HStack {
                        Image(systemName: "qrcode.viewfinder")
                            .resizable()
                            .frame(width: 30, height: 30)
                        Text("扫描")
                    }
                }

                Spacer()

                // 分享按钮
                Button(action: {
                    isShowingShareModal = true
                }) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                            .resizable()
                            .frame(width: 30, height: 30)
                        Text("分享")
                    }
                }
            }
            .padding(.horizontal)

            // 底部区域：VPN 控制视图（连接 / 断开 / 连接中...）
            VPNControlView {
                await connectVPN()
            }

            // 底部显示版本号
            HStack {
                Spacer()
                VersionView()
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // 在视图出现时执行的逻辑
        .onAppear {
            loadDataFromUserDefaults()
            fetchFreePorts()
        }
        // 弹出分享配置的模态视图
        .sheet(isPresented: $isShowingShareModal) {
            ShareModalView(isShowing: $isShowingShareModal)
        }
        // 剪贴板为空时提示
        .alert(isPresented: $showClipboardEmptyAlert) {
            Alert(
                title: Text("剪贴板为空"),
                message: Text("没有从剪贴板获取到内容"),
                dismissButton: .default(Text("确定"))
            )
        }
        // 扫描二维码视图
        .sheet(isPresented: $isShowingScanner) {
            QRCodeScannerView(scannedCode: $scannedCode)
                .onChange(of: scannedCode) { _, newCode in
                    if let code = newCode {
                        handleScannedCode(code)
                    }
                }
        }
    }

    // MARK: - VPN 连接操作

    /// 执行异步的 VPN 连接操作。若失败则在控制台打印错误信息。
    private func connectVPN() async {
        do {
            try await packetTunnelManager.start()
        } catch {
            print("连接 VPN 时出错: \(error.localizedDescription)")
        }
    }

    // MARK: - UserDefaults 相关

    /// 从 UserDefaults 中读取上一次保存的配置链接，并解析其中的 ID、IP、端口信息。
    private func loadDataFromUserDefaults() {
        if let content = Util.loadFromUserDefaults(key: "configLink") {
            Util.parseContent(content, idText: &idText, ipText: &ipText, portText: &portText)
        }
    }

    // MARK: - 剪贴板处理

    /// 从剪贴板读取配置内容，若非空则保存至 UserDefaults 并更新相关字段；否则弹出提示。
    private func handlePasteFromClipboard() {
        if let clipboardContent = Util.pasteFromClipboard(), !clipboardContent.isEmpty {
            // 若粘贴板内容与之前保存的不同，则更新
            let storedContent = Util.loadFromUserDefaults(key: "configLink")
            if clipboardContent != storedContent {
                clipboardText = clipboardContent
                Util.saveToUserDefaults(value: clipboardContent, key: "configLink")
                Util.parseContent(clipboardContent, idText: &idText, ipText: &ipText, portText: &portText)
            }
        } else {
            print("剪贴板内容为空")
            showClipboardEmptyAlert = true
        }
    }

    // MARK: - 二维码扫描

    /// 处理扫描到的二维码内容，与剪贴板处理逻辑相似，将其保存并解析。
    ///
    /// - Parameter code: 扫描到的二维码字符串。
    private func handleScannedCode(_ code: String) {
        print("扫描到的二维码内容: \(code)")
        clipboardText = code
        Util.saveToUserDefaults(value: clipboardText, key: "configLink")
        Util.parseContent(clipboardText, idText: &idText, ipText: &ipText, portText: &portText)
        isShowingScanner = false
    }

    // MARK: - 本地端口获取

    /// 向 `LibXray` 请求可用的两个空闲端口号，并保存在 UserDefaults 中，同时更新页面显示。
    private func fetchFreePorts() {
        // 1. 从 LibXray 获取两个空闲端口 (Base64 编码的字符串)
        let freePortsBase64String = LibXrayGetFreePorts(2)

        // 2. 解析 Base64 并转为 JSON 字符串
        guard
            let decodedData = Data(base64Encoded: freePortsBase64String),
            let decodedString = String(data: decodedData, encoding: .utf8)
        else {
            print("Base64 解码失败")
            return
        }

        // 3. 解析 JSON 并提取端口
        do {
            if let jsonObject = try JSONSerialization.jsonObject(with: Data(decodedString.utf8), options: []) as? [String: Any],
               let success = jsonObject["success"] as? Bool, success,
               let dataDict = jsonObject["data"] as? [String: Any],
               let ports = dataDict["ports"] as? [Int], ports.count == 2
            {
                // 4. 保存端口到 UserDefaults，并更新本地状态
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
