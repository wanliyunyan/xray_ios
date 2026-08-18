//
//  DashboardView.swift
//  Xray
//
//  Created by pan on 2024/9/14.
//

import os
import SwiftUI

// MARK: - 日志

private let logger = Logger(subsystem: AppConstants.loggingSubsystem, category: "DashboardView")

/// 应用主界面，集中展示节点信息、诊断数据、配置导入和 VPN 控制。
///
/// 该视图是用户操作入口，负责协调以下功能：
/// - 从 App Group 偏好恢复上次使用的分享链接并展示节点摘要；
/// - 通过剪贴板或二维码导入新的分享链接；
/// - 为 Ping SOCKS 入站和 Metrics 服务分配端口并持久化；
/// - 组合连接时长、累计流量、Ping、路由模式和中国分流资源入口；
/// - 调用 `PacketTunnelManager` 启动或停止系统 VPN；
/// - 展示当前配置的分享二维码和底层 Xray Core 版本。
@MainActor
struct DashboardView: View {
    // MARK: - 状态

    /// 全局 VPN 管理器，驱动连接控制并向子视图提供系统状态。
    @Environment(PacketTunnelManager.self) private var packetTunnelManager

    /// 提供当前进程唯一的 SOCKS 与 Metrics 端口。
    @Environment(AppSessionState.self) private var appSessionState

    /// 从分享链接解析出的节点摘要。
    @State private var nodeSummary = NodeSummary.empty

    /// 当前节点摘要对应的分享链接，用于在节点真正切换时重置 Ping 结果。
    @State private var displayedShareLink = ""

    /// 连接期间导入、将在下一次连接生效的节点摘要。
    @State private var pendingNodeSummary: NodeSummary?

    /// 通过校验、可以生成二维码的分享配置；为 nil 时不展示分享页。
    @State private var configurationToShare: ConfigurationShareItem?

    /// 控制导入结果或 VPN 操作错误提示。
    @State private var isOperationAlertPresented = false

    @State private var operationAlertTitle = ""
    @State private var operationAlertMessage = ""

    /// 二维码扫描器最近返回的原始文本。
    @State private var scannedShareLink: String?

    /// 控制二维码扫描器 Sheet 的显示状态。
    @State private var isScannerPresented = false

    // MARK: - 视图主体

    /// 组合节点信息、诊断区、配置操作区和 VPN 控制区。
    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                // 顶部信息区：节点摘要、连接指标、本地端口和路由模式。
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("vps信息:")
                            .font(.headline)

                        LabeledValueRow(label: "ID:", value: nodeSummary.identifier)
                        LabeledValueRow(label: "IP地址:", value: IPAddressFormatter.masked(nodeSummary.host))
                        LabeledValueRow(label: "端口:", value: nodeSummary.port)

                        if let pendingNodeSummary {
                            PendingNodeNotice(summary: pendingNodeSummary)
                        }
                    }

                    // 连接相关数据拆分为独立视图，各自只监听所需状态。
                    ConnectionDurationView()
                    TrafficStatisticsView()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("本机端口:")
                            .font(.headline)
                        LocalPortSummary(
                            socksPort: appSessionState.socksPort.rawValue,
                            metricsPort: appSessionState.metricsPort.rawValue
                        )
                    }

                    LatencyTestView()
                        .id(displayedShareLink)
                    VPNRoutingModePickerView()
                }
                .padding()

            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.bottom)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                // 连接操作与版本信息固定在页面底部，不随上方内容滚动。
                VPNConnectionControlView {
                    await startVPN()
                }

                XrayVersionView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 8)
            }
            .background(Color(uiColor: .systemBackground))
        }
        .navigationTitle("Xray")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    PasteButton(payloadType: String.self, onPaste: importFirstShareLink(from:))
                        .accessibilityLabel("从剪贴板导入")

                    Button("扫描二维码", systemImage: "qrcode.viewfinder") {
                        isScannerPresented = true
                    }

                    Divider()

                    Button("分享当前配置", systemImage: "square.and.arrow.up") {
                        presentConfigurationShare()
                    }

                    Divider()

                    NavigationLink(value: XrayAppRoute.chinaGeoAssets) {
                        Label("中国大陆分流资源", systemImage: "globe.asia.australia")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("更多操作")
            }
        }
        .onAppear {
            synchronizeDisplayedConfiguration()
        }
        .onChange(of: packetTunnelManager.lifecycleState) {
            synchronizeDisplayedConfiguration()
        }
        .onChange(of: packetTunnelManager.activeShareLink) {
            synchronizeDisplayedConfiguration()
        }
        .task(id: packetTunnelManager.lifecycleState) {
            guard let strategy = packetTunnelManager.lifecycleState.localPortPreparationStrategy else {
                return
            }
            await appSessionState.prepareLocalPorts(using: strategy)
        }
        .sheet(item: $configurationToShare) { configuration in
            ConfigurationShareView(shareLink: configuration.shareLink)
        }
        .alert(operationAlertTitle, isPresented: $isOperationAlertPresented) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(operationAlertMessage)
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

    // MARK: - 操作

    /// 仅在已保存配置存在且可以解析时打开二维码分享页。
    private func presentConfigurationShare() {
        guard
            let storedShareLink = AppGroupStore.loadString(forKey: "configLink")?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !storedShareLink.isEmpty,
            ShareLinkParser.parse(storedShareLink) != nil
        else {
            presentAlert(
                title: "没有可分享的配置",
                message: "请先通过粘贴或扫描二维码导入节点配置。"
            )
            return
        }

        configurationToShare = ConfigurationShareItem(shareLink: storedShareLink)
    }

    /// 生命周期处于活动阶段，或仍保留活动配置快照时，新配置只能在下次连接生效。
    private var shouldDeferConfigurationChanges: Bool {
        packetTunnelManager.lifecycleState.shouldDeferConfigurationChanges
            || packetTunnelManager.activeShareLink != nil
    }

    /// 启动 VPN，并记录无法启动的原因。
    ///
    /// 具体配置构建、冲突检查和系统启动由 `PacketTunnelManager.start()` 完成。这里捕获错误，
    /// 防止按钮触发的异步任务把异常传播出 SwiftUI 事件边界。
    private func startVPN() async {
        do {
            try await packetTunnelManager.prepareForConnection()
        } catch {
            presentAlert(title: "VPN 操作失败", message: error.localizedDescription)
            return
        }

        guard let strategy = packetTunnelManager.lifecycleState.localPortPreparationStrategy else {
            presentAlert(title: "VPN 操作失败", message: "VPN 配置尚未初始化完成")
            return
        }
        await appSessionState.prepareLocalPorts(using: strategy)
        guard appSessionState.areLocalPortsReady else {
            presentAlert(
                title: "VPN 操作失败",
                message: appSessionState.localPortPreparationError ?? "无法准备本地服务端口"
            )
            return
        }

        do {
            try await packetTunnelManager.start()
        } catch {
            logger.error("连接 VPN 时出错: \(error.localizedDescription)")
            presentAlert(title: "VPN 操作失败", message: error.localizedDescription)
        }
    }

    /// 根据 VPN 是否仍在运行，分别展示实际活动节点和待生效节点。
    ///
    /// 偏好中没有 `configLink` 时保持原状态。连接期间优先使用管理器记录的启动快照；若保存的
    /// 链接已经变化，则将其作为待生效节点。隧道停止后，保存的链接立即成为当前节点。
    private func synchronizeDisplayedConfiguration() {
        guard
            let savedShareLink = AppGroupStore.loadString(forKey: "configLink"),
            let savedSummary = ShareLinkParser.parse(savedShareLink)
        else {
            return
        }

        guard
            shouldDeferConfigurationChanges,
            let activeShareLink = packetTunnelManager.activeShareLink,
            let activeSummary = ShareLinkParser.parse(activeShareLink)
        else {
            displayedShareLink = savedShareLink
            nodeSummary = savedSummary
            pendingNodeSummary = nil
            return
        }

        displayedShareLink = activeShareLink
        nodeSummary = activeSummary
        pendingNodeSummary = activeShareLink == savedShareLink ? nil : savedSummary
    }

    /// 从系统粘贴结果中选择第一个非空分享链接。
    private func importFirstShareLink(from pastedStrings: [String]) {
        guard let shareLink = pastedStrings.first(where: { !$0.isEmpty }) else {
            return
        }
        importShareLink(shareLink)
    }

    /// 校验并保存由系统粘贴控件或二维码扫描器提供的分享链接。
    private func importShareLink(_ shareLink: String) {
        let normalizedShareLink = shareLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let summary = ShareLinkParser.parse(normalizedShareLink) else {
            presentAlert(title: "配置导入失败", message: "粘贴或扫描的内容不是有效的分享链接")
            return
        }

        let storedShareLink = AppGroupStore.loadString(forKey: "configLink")
        let didChangeStoredConfiguration = normalizedShareLink != storedShareLink
        if didChangeStoredConfiguration {
            AppGroupStore.saveString(normalizedShareLink, forKey: "configLink")
        }

        if shouldDeferConfigurationChanges {
            let activeShareLink = packetTunnelManager.activeShareLink ?? displayedShareLink
            if normalizedShareLink != activeShareLink {
                pendingNodeSummary = summary
                if didChangeStoredConfiguration {
                    presentAlert(
                        title: "节点已保存",
                        message: "当前 VPN 仍使用连接时的节点，新节点将在下次连接时生效。"
                    )
                }
                return
            }
        }

        displayedShareLink = normalizedShareLink
        nodeSummary = summary
        pendingNodeSummary = nil
    }

    /// 保存并解析扫描到的分享链接，然后关闭扫描器。
    ///
    /// - Parameter shareLink: AVFoundation 从二维码中读取的原始分享链接文本。
    /// - Note: 与剪贴板导入不同，扫码结果会直接覆盖当前配置，因为每次扫描都代表明确选择。
    private func importShareLinkFromQRCode(_ shareLink: String) {
        importShareLink(shareLink)
        scannedShareLink = nil
        isScannerPresented = false
    }

    private func presentAlert(title: String, message: String) {
        operationAlertTitle = title
        operationAlertMessage = message
        isOperationAlertPresented = true
    }
}

private struct ConfigurationShareItem: Identifiable {
    let shareLink: String

    var id: String { shareLink }
}

private struct LocalPortSummary: View {
    let socksPort: UInt16
    let metricsPort: UInt16

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                Text("延迟测试: \(socksPort)")
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 16)
                Text("流量统计: \(metricsPort)")
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("延迟测试: \(socksPort)")
                Text("流量统计: \(metricsPort)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PendingNodeNotice: View {
    let summary: NodeSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("新节点将在下次连接时生效", systemImage: "clock.arrow.circlepath")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)

            Text("\(IPAddressFormatter.masked(summary.host)):\(summary.port)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}
