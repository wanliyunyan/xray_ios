//
//  VPNRoutingModePickerView.swift
//  Xray
//
//  Created by pan on 2024/11/5.
//

import os
import SwiftUI

// MARK: - 日志

private let logger = Logger(subsystem: AppConstants.loggingSubsystem, category: "VPNRoutingModePickerView")

/// VPN 的流量路由模式。
///
/// 原始值用于 App Group 持久化，`XrayConfigurationBuilder` 根据保存值决定是否注入 geo 分流规则；
/// 界面使用更直观的名称展示。
enum VPNRoutingMode: String, CaseIterable, Sendable {
    /// 不添加中国大陆直连或广告阻断规则，TCP/UDP 流量最终使用代理出站。
    case global = "全局"

    /// geo 资源可用时，中国大陆和私有流量直连、广告阻断，其余流量使用代理出站。
    case nonGlobal = "非全局"

    /// 面向用户的模式名称；原始值继续用于兼容已有偏好设置。
    var displayName: String {
        switch self {
        case .global:
            "全局代理"
        case .nonGlobal:
            "智能分流"
        }
    }

    /// 当前模式的简短流量说明。
    var summary: String {
        switch self {
        case .global:
            "所有流量均通过 VPN"
        case .nonGlobal:
            "中国大陆直连，其余流量通过 VPN"
        }
    }
}

/// 提供全局和非全局路由模式选择，并与 App Group 偏好保持同步。
///
/// 视图出现时恢复上次选择；用户切换后立即持久化。如果 VPN 已连接，会等待隧道重启，
/// 使 `XrayConfigurationBuilder` 重新构建路由规则并交给新的 Packet Tunnel 实例。
struct VPNRoutingModePickerView: View {
    /// 当前选择的路由模式；没有有效持久化值时默认非全局。
    @State private var selectedMode: VPNRoutingMode

    /// 应用路由模式期间禁用选择器，避免多个隧道重启流程交叉。
    @State private var isApplyingMode = false
    @State private var isRestartErrorPresented = false
    @State private var restartErrorMessage = ""

    /// 提供连接状态和重启能力。
    @Environment(PacketTunnelManager.self) private var packetTunnelManager

    init() {
        let savedValue = AppGroupStore.loadString(forKey: "VPNMode")
        _selectedMode = State(initialValue: savedValue.flatMap(VPNRoutingMode.init(rawValue:)) ?? .nonGlobal)
    }

    /// 构建紧凑的菜单选择器，并处理模式变化和初始恢复。
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                modeDescription
                Spacer(minLength: 12)
                modeMenu
            }

            VStack(alignment: .leading, spacing: 10) {
                modeDescription
                modeMenu
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: selectedMode) { oldMode, newMode in
            applyModeChange(from: oldMode, to: newMode)
        }
        .alert("路由模式切换失败", isPresented: $isRestartErrorPresented) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(restartErrorMessage)
        }
    }

    private var modeDescription: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("路由模式")
                .font(.headline)
            Text(selectedMode.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var modeMenu: some View {
        HStack(spacing: 8) {
            if isApplyingMode {
                ProgressView()
                    .controlSize(.small)
            }

            Menu {
                Picker("路由模式", selection: $selectedMode) {
                    ForEach(VPNRoutingMode.allCases, id: \.self) { mode in
                        Text(mode.displayName)
                            .tag(mode)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selectedMode.displayName)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .disabled(isApplyingMode)
            .accessibilityLabel("路由模式")
            .accessibilityValue(selectedMode.displayName)
        }
    }

    /// 保存新模式；VPN 正在运行时重启隧道以立即应用路由规则。
    private func applyModeChange(from oldMode: VPNRoutingMode, to newMode: VPNRoutingMode) {
        saveSelectedMode(newMode)

        guard packetTunnelManager.lifecycleState.isConnected else {
            return
        }

        isApplyingMode = true
        Task { @MainActor in
            defer { isApplyingMode = false }
            do {
                try await packetTunnelManager.restart()
                logger.info("VPN 已成功重启")
            } catch {
                saveSelectedMode(oldMode)
                selectedMode = oldMode
                restartErrorMessage = "切换路由模式失败，已恢复为\(oldMode.displayName)。\n\(error.localizedDescription)"
                isRestartErrorPresented = true
                logger.error("VPN 重启失败：\(error.localizedDescription)")
            }
        }
    }

    // MARK: - 持久化

    /// 将当前路由模式保存到 App Group 偏好。
    ///
    /// - Parameter mode: 用户刚选择的模式，按枚举原始中文值保存。
    private func saveSelectedMode(_ mode: VPNRoutingMode) {
        AppGroupStore.saveString(mode.rawValue, forKey: "VPNMode")
    }

}
