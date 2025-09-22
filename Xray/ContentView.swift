//
//  ContentView.swift
//  Xray
//
//  Created by pan on 2024/9/14.
//

import Network
import os
import SwiftUI

// MARK: - Logger

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ContentView")



// MARK: - 主视图

/// 整个应用的核心主视图，负责展示和管理用户粘贴、二维码扫描、VPN 连接、流量统计、分享等功能模块。
/// 这是用户交互的主要入口，整合了多种功能，提供便捷的操作界面。
@MainActor
struct ContentView: View {
    
    private let xrayManager = XrayManager()
    
    // MARK: - 环境对象

    /// 全局共享的 `PacketTunnelManager`，用于获取和更新当前 VPN 的连接状态。
    @EnvironmentObject var packetTunnelManager: PacketTunnelManager

    // MARK: - 本地状态

    /// 保存最近一次粘贴或扫描的配置内容，用于解析和展示。
    @State private var clipboardText: String = ""

    /// 从配置内容中解析出的 ID，用于展示服务器身份信息。
    @State private var idText: String = ""

    /// 从配置内容中解析出的 IP 地址或域名，用于展示服务器地址信息。
    @State private var ipText: String = ""

    /// 从配置内容中解析出的端口号（如远程服务器端口），用于展示服务器端口信息。
    @State private var portText: String = ""

    /// Xray 配置文件的路径，潜在用于本地存储或文件管理的扩展功能。
    @State private var path: String = ""

    /// 控制 “分享配置” 弹窗是否显示，管理分享界面的展示状态。
    @State private var isShowingShareModal = false

    /// 控制当剪贴板为空时是否显示提示 Alert，提醒用户无有效内容。
    @State private var showClipboardEmptyAlert = false

    /// 用于显示或存储当前的 Ping 速度（ms），用于性能监测和展示。
    @State private var pingSpeed: Int = 0

    /// 用于在界面上显示 SOCKS 端口（本地代理端口），便于用户查看代理端口信息。
    @State private var socks5Port: NWEndpoint.Port = Constant.socks5Port

    /// 用于在界面上显示流量统计端口，便于用户查看流量监控端口信息。
    @State private var trafficPort: NWEndpoint.Port = Constant.trafficPort

    /// 扫描到的二维码内容，暂存扫描结果用于解析和处理。
    @State private var scannedCode: String? = nil

    /// 控制二维码扫描器视图是否显示，管理扫描界面的展示状态。
    @State private var isShowingScanner = false

    // MARK: - 主布局

    var body: some View {
        // 布局分为顶部信息区、中间操作区、底部控制区，分别展示配置信息、操作按钮和 VPN 控制。
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
                    Text("Socks5: \(socks5Port.rawValue)")
                    Spacer()
                    Text("流量: \(trafficPort.rawValue)")
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
            // 启动时会加载配置、随机分配本机端口并保存到 UserDefaults，确保配置和端口信息初始化
            loadDataFromUserDefaults()
            let ports = xrayManager.fetchFreePorts()
            UtilStore.savePort(value: ports[0], key: "socks5Port")
            UtilStore.savePort(value: ports[1], key: "trafficPort")
            socks5Port = ports[0]
            trafficPort = ports[1]
        }
        // 弹出分享配置的模态视图，供用户分享当前配置
        .sheet(isPresented: $isShowingShareModal) {
            ShareModalView(isShowing: $isShowingShareModal)
        }
        // 剪贴板为空时提示，提醒用户无有效内容可粘贴
        .alert(isPresented: $showClipboardEmptyAlert) {
            Alert(
                title: Text("剪贴板为空"),
                message: Text("没有从剪贴板获取到内容"),
                dismissButton: .default(Text("确定"))
            )
        }
        // 扫描二维码视图，允许用户扫描二维码获取配置
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

    /// 执行异步的 VPN 连接操作。若失败则在控制台打印错误信息，并可用于后续错误处理或提示用户。
    private func connectVPN() async {
        do {
            try await packetTunnelManager.start()
        } catch {
            logger.error("连接 VPN 时出错: \(error.localizedDescription)")
        }
    }

    // MARK: - UserDefaults 相关

    /// 从 UserDefaults 中读取上一次保存的配置链接，并解析其中的 ID、IP、端口信息。
    /// 该方法确保应用在重启后自动恢复上次配置，提升用户体验。
    private func loadDataFromUserDefaults() {
        if let content = UtilStore.loadString(key: "configLink") {
            Util.parseContent(content, idText: &idText, ipText: &ipText, portText: &portText)
        }
    }

    // MARK: - 剪贴板处理

    /// 从剪贴板读取配置内容，若非空则保存至 UserDefaults 并更新相关字段；否则弹出提示。
    /// 通过对比新旧内容，避免重复保存和解析，提升效率。
    private func handlePasteFromClipboard() {
        if let clipboardContent = Util.pasteFromClipboard(), !clipboardContent.isEmpty {
            // 若粘贴板内容与之前保存的不同，则更新
            let storedContent = UtilStore.loadString(key: "configLink")
            if clipboardContent != storedContent {
                clipboardText = clipboardContent
                UtilStore.saveString(value: clipboardContent, key: "configLink")
                Util.parseContent(clipboardContent, idText: &idText, ipText: &ipText, portText: &portText)
            }
        } else {
            logger.info("剪贴板内容为空")
            showClipboardEmptyAlert = true
        }
    }

    // MARK: - 二维码扫描

    /// 处理扫描到的二维码内容，与剪贴板处理逻辑相似，将其保存并解析。
    ///
    /// - Parameter code: 扫描到的二维码字符串。
    ///
    /// 此方法与粘贴逻辑保持一致，但来源是二维码扫描，并在保存后关闭扫描器。
    private func handleScannedCode(_ code: String) {
        logger.info("扫描到的二维码内容: \(code)")
        clipboardText = code
        UtilStore.saveString(value: clipboardText, key: "configLink")
        Util.parseContent(clipboardText, idText: &idText, ipText: &ipText, portText: &portText)
        isShowingScanner = false
    }

}
