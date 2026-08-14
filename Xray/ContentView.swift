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

/// 应用主界面，集中展示节点信息、诊断数据、配置导入和 VPN 控制。
///
/// 该视图是用户操作入口，负责协调以下功能：
/// - 从 App Group 偏好恢复上次使用的分享链接并展示节点摘要；
/// - 通过剪贴板或二维码导入新的分享链接；
/// - 为 Ping SOCKS 入站和 Metrics 服务分配端口并持久化；
/// - 组合连接时长、累计流量、Ping、路由模式和 geo 文件管理子视图；
/// - 调用 `PacketTunnelManager` 启动或停止系统 VPN；
/// - 展示当前配置的分享二维码和底层 Xray Core 版本。
@MainActor
struct ContentView: View {
    /// 提供空闲端口分配能力。
    private let xrayManager = XrayManager()

    // MARK: - State

    /// 全局 VPN 管理器，驱动连接控制并向子视图提供系统状态。
    @EnvironmentObject var packetTunnelManager: PacketTunnelManager

    /// 最近一次从剪贴板或二维码导入的原始分享链接。
    @State private var clipboardText: String = ""

    /// 从分享链接 `user` 字段解析出的节点用户标识。
    @State private var idText: String = ""

    /// 从分享链接 `host` 字段解析出的服务器地址或域名。
    @State private var ipText: String = ""

    /// 从分享链接解析出的远端服务器端口。
    @State private var portText: String = ""

    /// 控制分享配置 Sheet 的显示状态。
    @State private var isShowingShareModal = false

    /// 控制剪贴板无有效文本时的提示 Alert。
    @State private var showClipboardEmptyAlert = false

    /// Ping 配置中本地 SOCKS 入站使用的端口。
    @State private var socks5Port: NWEndpoint.Port = Constant.socks5Port

    /// Xray Metrics HTTP 服务和流量查询共同使用的端口。
    @State private var trafficPort: NWEndpoint.Port = Constant.trafficPort

    /// 二维码扫描器最近返回的原始文本。
    @State private var scannedCode: String? = nil

    /// 控制二维码扫描器 Sheet 的显示状态。
    @State private var isShowingScanner = false

    // MARK: - Body

    /// 组合节点信息、诊断区、配置操作区和 VPN 控制区。
    var body: some View {
        VStack(alignment: .leading) {
            // 顶部信息区：节点摘要、连接指标、本地端口和路由模式。
            VStack(alignment: .leading) {
                Text("vps信息:")
                    .font(.headline)

                InfoRow(label: "ID:", text: idText)
                InfoRow(label: "IP地址:", text: Util.maskIPAddress(ipText))
                InfoRow(label: "端口:", text: portText)

                // 连接相关数据拆分为独立视图，各自只监听所需状态。
                ConnectedDurationView()
                TrafficStatsView()

                Text("本机端口:")
                    .font(.headline)
                HStack {
                    Text("Socks5: \(socks5Port.rawValue)")
                    Spacer()
                    Text("流量: \(trafficPort.rawValue)")
                }

                PingView().environmentObject(PacketTunnelManager.shared)
                VPNModePickerView()
            }
            .padding()

            // geoip/geosite 资源下载与清理入口。
            DownloadView()

            // 配置操作区：剪贴板导入、摄像头扫描和二维码分享。
            HStack {
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

            // 根据系统连接状态显示连接、断开或进度控件。
            VPNControlView {
                await connectVPN()
            }

            // 底部展示当前 LibXray 内置的 Xray Core 版本。
            HStack {
                Spacer()
                VersionView()
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            // 恢复节点摘要，并为 Ping 与 Metrics 分配一组本地空闲端口。
            // 端口同时写入 App Group，保证后续配置构建和查询使用相同值。
            loadDataFromUserDefaults()
            let ports = xrayManager.fetchFreePorts()
            UtilStore.savePort(value: ports[0], key: "socks5Port")
            UtilStore.savePort(value: ports[1], key: "trafficPort")
            socks5Port = ports[0]
            trafficPort = ports[1]
        }
        .sheet(isPresented: $isShowingShareModal) {
            // 分享视图从 App Group 读取当前链接并生成二维码。
            ShareModalView(isShowing: $isShowingShareModal)
        }
        .alert(isPresented: $showClipboardEmptyAlert) {
            Alert(
                title: Text("剪贴板为空"),
                message: Text("没有从剪贴板获取到内容"),
                dismissButton: .default(Text("确定"))
            )
        }
        .sheet(isPresented: $isShowingScanner) {
            // 扫描结果变化后立即保存、解析并关闭扫描器。
            QRCodeScannerView(scannedCode: $scannedCode)
                .onChange(of: scannedCode) { _, newCode in
                    if let code = newCode {
                        handleScannedCode(code)
                    }
                }
        }
    }

    // MARK: - Actions

    /// 启动 VPN，并记录无法启动的原因。
    ///
    /// 具体配置构建、冲突检查和系统启动由 `PacketTunnelManager.start()` 完成。这里捕获错误，
    /// 防止按钮触发的异步任务把异常传播出 SwiftUI 事件边界。
    private func connectVPN() async {
        do {
            try await packetTunnelManager.start()
        } catch {
            logger.error("连接 VPN 时出错: \(error.localizedDescription)")
        }
    }

    /// 恢复上次保存的分享链接，并更新节点摘要。
    ///
    /// 偏好中没有 `configLink` 时保持空状态；存在时只解析用于展示的 user、host 和 port，
    /// 不在此处调用 LibXray 或验证完整节点配置。
    private func loadDataFromUserDefaults() {
        if let content = UtilStore.loadString(key: "configLink") {
            Util.parseContent(content, idText: &idText, ipText: &ipText, portText: &portText)
        }
    }

    /// 导入剪贴板中的分享链接。
    ///
    /// 只有非空且与已保存内容不同的字符串才会写入 App Group 并重新解析摘要，避免重复更新
    /// SwiftUI 状态。剪贴板为空或不包含字符串时记录日志，并显示用户提示。
    private func handlePasteFromClipboard() {
        if let clipboardContent = Util.pasteFromClipboard(), !clipboardContent.isEmpty {
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

    /// 保存并解析扫描到的分享链接，然后关闭扫描器。
    ///
    /// - Parameter code: AVFoundation 从二维码中读取的原始分享链接文本。
    /// - Note: 与剪贴板导入不同，扫码结果会直接覆盖当前配置，因为每次扫描都代表明确选择。
    private func handleScannedCode(_ code: String) {
        logger.info("扫描到的二维码内容: \(code)")
        clipboardText = code
        UtilStore.saveString(value: clipboardText, key: "configLink")
        Util.parseContent(clipboardText, idText: &idText, ipText: &ipText, portText: &portText)
        isShowingScanner = false
    }
}
