//
//  DashboardView.swift
//  Xray
//
//  Created by pan on 2024/9/14.
//

import Network
import os
import SwiftUI

// MARK: - Logger

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "DashboardView")

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
struct DashboardView: View {
    /// 提供空闲端口分配能力。
    private let xrayService = XrayService()

    // MARK: - State

    /// 全局 VPN 管理器，驱动连接控制并向子视图提供系统状态。
    @EnvironmentObject var packetTunnelManager: PacketTunnelManager

    /// 从分享链接 `user` 字段解析出的节点用户标识。
    @State private var nodeIdentifier: String = ""

    /// 从分享链接 `host` 字段解析出的服务器地址或域名。
    @State private var serverHost: String = ""

    /// 从分享链接解析出的远端服务器端口。
    @State private var serverPort: String = ""

    /// 控制分享配置 Sheet 的显示状态。
    @State private var isShareSheetPresented = false

    /// 控制剪贴板无有效文本时的提示 Alert。
    @State private var isClipboardEmptyAlertPresented = false

    /// Ping 配置中本地 SOCKS 入站使用的端口。
    @State private var socksPort: NWEndpoint.Port = AppConstants.defaultSocksPort

    /// Xray Metrics HTTP 服务和流量查询共同使用的端口。
    @State private var metricsPort: NWEndpoint.Port = AppConstants.defaultMetricsPort

    /// 二维码扫描器最近返回的原始文本。
    @State private var scannedShareLink: String?

    /// 控制二维码扫描器 Sheet 的显示状态。
    @State private var isScannerPresented = false

    // MARK: - Body

    /// 组合节点信息、诊断区、配置操作区和 VPN 控制区。
    var body: some View {
        VStack(alignment: .leading) {
            // 顶部信息区：节点摘要、连接指标、本地端口和路由模式。
            VStack(alignment: .leading) {
                Text("vps信息:")
                    .font(.headline)

                LabeledValueRow(label: "ID:", value: nodeIdentifier)
                LabeledValueRow(label: "IP地址:", value: IPAddressFormatter.masked(serverHost))
                LabeledValueRow(label: "端口:", value: serverPort)

                // 连接相关数据拆分为独立视图，各自只监听所需状态。
                ConnectionDurationView()
                TrafficStatisticsView()

                Text("本机端口:")
                    .font(.headline)
                HStack {
                    Text("Socks5: \(socksPort.rawValue)")
                    Spacer()
                    Text("流量: \(metricsPort.rawValue)")
                }

                LatencyTestView()
                VPNRoutingModePickerView()
            }
            .padding()

            // geoip/geosite 资源下载与清理入口。
            GeoAssetDownloadView()

            // 配置操作区：剪贴板导入、摄像头扫描和二维码分享。
            HStack {
                Button(action: {
                    importShareLinkFromClipboard()
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
                    isScannerPresented = true
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
                    isShareSheetPresented = true
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
            VPNConnectionControlView {
                await startVPN()
            }

            // 底部展示当前 LibXray 内置的 Xray Core 版本。
            HStack {
                Spacer()
                XrayVersionView()
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            restoreSavedShareLink()
            Task {
                let allocatedPorts = await xrayService.allocateLocalPorts()
                guard
                    let newSocksPort = NWEndpoint.Port(rawValue: allocatedPorts.socksPort),
                    let newMetricsPort = NWEndpoint.Port(rawValue: allocatedPorts.metricsPort)
                else {
                    logger.error("Xray 返回了无效的本地端口")
                    return
                }

                socksPort = newSocksPort
                metricsPort = newMetricsPort
                AppGroupStore.savePort(newSocksPort, forKey: "socks5Port")
                AppGroupStore.savePort(newMetricsPort, forKey: "trafficPort")
            }
        }
        .sheet(isPresented: $isShareSheetPresented) {
            // 分享视图从 App Group 读取当前链接并生成二维码。
            ConfigurationShareView(isPresented: $isShareSheetPresented)
        }
        .alert(isPresented: $isClipboardEmptyAlertPresented) {
            Alert(
                title: Text("剪贴板为空"),
                message: Text("没有从剪贴板获取到内容"),
                dismissButton: .default(Text("确定"))
            )
        }
        .sheet(isPresented: $isScannerPresented) {
            // 扫描结果变化后立即保存、解析并关闭扫描器。
            QRCodeScannerView(scannedCode: $scannedShareLink)
                .onChange(of: scannedShareLink) { _, newShareLink in
                    if let newShareLink {
                        importShareLinkFromQRCode(newShareLink)
                    }
                }
        }
    }

    // MARK: - Actions

    /// 启动 VPN，并记录无法启动的原因。
    ///
    /// 具体配置构建、冲突检查和系统启动由 `PacketTunnelManager.start()` 完成。这里捕获错误，
    /// 防止按钮触发的异步任务把异常传播出 SwiftUI 事件边界。
    private func startVPN() async {
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
    private func restoreSavedShareLink() {
        if let shareLink = AppGroupStore.loadString(forKey: "configLink") {
            updateNodeSummary(from: shareLink)
        }
    }

    /// 导入剪贴板中的分享链接。
    ///
    /// 只有非空且与已保存内容不同的字符串才会写入 App Group 并重新解析摘要，避免重复更新
    /// SwiftUI 状态。剪贴板为空或不包含字符串时记录日志，并显示用户提示。
    private func importShareLinkFromClipboard() {
        if let clipboardContent = ClipboardService.readString() {
            let storedContent = AppGroupStore.loadString(forKey: "configLink")
            if clipboardContent != storedContent {
                AppGroupStore.saveString(clipboardContent, forKey: "configLink")
                updateNodeSummary(from: clipboardContent)
            }
        } else {
            logger.info("剪贴板内容为空")
            isClipboardEmptyAlertPresented = true
        }
    }

    /// 保存并解析扫描到的分享链接，然后关闭扫描器。
    ///
    /// - Parameter shareLink: AVFoundation 从二维码中读取的原始分享链接文本。
    /// - Note: 与剪贴板导入不同，扫码结果会直接覆盖当前配置，因为每次扫描都代表明确选择。
    private func importShareLinkFromQRCode(_ shareLink: String) {
        logger.info("扫描到的二维码内容: \(shareLink)")
        AppGroupStore.saveString(shareLink, forKey: "configLink")
        updateNodeSummary(from: shareLink)
        scannedShareLink = nil
        isScannerPresented = false
    }

    /// Applies the displayable node details from a saved or newly imported share link.
    private func updateNodeSummary(from shareLink: String) {
        guard let summary = ShareLinkParser.parse(shareLink) else {
            return
        }
        nodeIdentifier = summary.identifier
        serverHost = summary.host
        serverPort = summary.port
    }
}
