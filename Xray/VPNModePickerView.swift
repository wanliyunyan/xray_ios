//
//  VPNModePickerView.swift
//  Xray
//
//  Created by pan on 2024/11/5.
//

import os
import SwiftUI

// MARK: - Logger

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "VPNMode")

/// VPN 的流量路由模式。
///
/// 原始值直接用于界面显示和 App Group 持久化，`Configuration.buildRoute()` 根据保存值决定
/// 是否注入 geo 分流规则。
enum VPNMode: String {
    /// 不添加国内直连或广告阻断规则，TCP/UDP 流量最终使用代理出站。
    case global = "全局"

    /// geo 资源可用时，国内和私有流量直连、广告阻断，其余流量使用代理出站。
    case nonGlobal = "非全局"
}

/// 提供全局和非全局路由模式选择，并与 App Group 偏好保持同步。
///
/// 视图出现时恢复上次选择；用户切换后立即持久化。如果 VPN 已连接，会等待隧道重启，
/// 使 `Configuration` 重新构建路由规则并交给新的 Packet Tunnel 实例。
struct VPNModePickerView: View {
    /// 当前选择的路由模式；没有有效持久化值时默认非全局。
    @State private var selectedMode: VPNMode = .nonGlobal

    /// 提供连接状态和重启能力。
    @EnvironmentObject var packetTunnelManager: PacketTunnelManager

    /// 构建分段选择器，并处理模式变化和初始恢复。
    var body: some View {
        VStack(alignment: .leading) {
            Text("路由模式:")
                .font(.headline)

            Picker("模式", selection: $selectedMode) {
                Text(VPNMode.nonGlobal.rawValue)
                    .tag(VPNMode.nonGlobal)
                Text(VPNMode.global.rawValue)
                    .tag(VPNMode.global)
            }
            .pickerStyle(SegmentedPickerStyle())
            .onChange(of: selectedMode) { _, newMode in
                // 先持久化新模式，确保随后的 restart 使用最新路由选择。
                saveModeToUserDefaults(newMode)

                if packetTunnelManager.status == .connected {
                    // 只有运行中的 Xray 需要重启；未连接时下次启动自然读取新值。
                    Task {
                        do {
                            try await packetTunnelManager.restart()
                            logger.info("VPN 已成功重启")
                        } catch {
                            logger.error("VPN 重启失败：\(error.localizedDescription)")
                        }
                    }
                }
            }
        }
        .onAppear {
            loadModeFromUserDefaults()
        }
    }

    // MARK: - Persistence

    /// 将当前路由模式保存到 App Group 偏好。
    ///
    /// - Parameter mode: 用户刚选择的模式，按枚举原始中文值保存。
    private func saveModeToUserDefaults(_ mode: VPNMode) {
        UtilStore.saveString(value: mode.rawValue, key: "VPNMode")
    }

    /// 从 App Group 偏好恢复已保存的路由模式。
    ///
    /// 字符串缺失或无法转换为 `VPNMode` 时回退为 `.nonGlobal`，保证配置构建始终有确定值。
    private func loadModeFromUserDefaults() {
        if let modeString = UtilStore.loadString(key: "VPNMode"),
           let mode = VPNMode(rawValue: modeString)
        {
            selectedMode = mode
        } else {
            selectedMode = .nonGlobal
        }
    }
}
