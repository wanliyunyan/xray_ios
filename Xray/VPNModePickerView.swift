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

/// VPN 工作模式枚举，定义了两种主要的路由模式：
///
/// - `global`（全局模式）：所有流量都会通过 VPN 进行转发，适用于需要全局代理的场景。
/// - `nonGlobal`（非全局模式）：仅特定流量通过 VPN，其它流量直接访问互联网，适合分流需求。
///
/// 该枚举用于控制 VPN 的路由行为，方便用户根据需求选择合适的模式。
enum VPNMode: String {
    case global = "全局"
    case nonGlobal = "非全局"
}

/// 该视图用于让用户选择 VPN 的路由模式（全局或非全局）。
///
/// 使用场景包括应用内设置界面，用户可通过该视图切换 VPN 工作模式。
///
/// 视图会自动将用户选择的模式保存到 `UserDefaults`，以便下次启动时恢复设置。
///
/// 当用户切换模式且当前 VPN 已连接时，视图会自动触发 VPN 重启操作，确保新模式生效。
struct VPNModePickerView: View {
    // MARK: - 属性

    /// 当前选中的 VPN 模式，与 `UserDefaults` 中存储的值保持同步。
    /// 视图初始化时会从 `UserDefaults` 读取上一次保存的模式，用户切换时会更新该值并持久化。
    @State private var selectedMode: VPNMode = .nonGlobal

    /// 从环境中获取全局的 PacketTunnelManager，用于判断 VPN 状态并在必要时重启。
    @EnvironmentObject var packetTunnelManager: PacketTunnelManager

    // MARK: - 主视图

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
            // 当用户切换 Picker 的值时，立即执行以下逻辑
            .onChange(of: selectedMode) { _, newMode in
                // 保存用户新选择的模式到 UserDefaults，确保设置持久化
                saveModeToUserDefaults(newMode)

                // 如果当前 VPN 已处于连接状态，则重启 VPN 以应用新的路由模式
                if packetTunnelManager.status == .connected {
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
        // 视图出现时，从 UserDefaults 读取用户上一次选择的 VPN 模式。
        .onAppear {
            loadModeFromUserDefaults()
        }
    }

    // MARK: - UserDefaults 读写

    /// 通过 `UtilStore` 封装的方法将用户选择的 VPN 模式字符串持久化存储到 UserDefaults。
    ///
    /// 该方法确保用户的选择在应用重启后依然有效，提供良好的用户体验。
    ///
    /// - Parameter mode: 当前选中的 VPN 模式。
    private func saveModeToUserDefaults(_ mode: VPNMode) {
        UtilStore.saveString(value: mode.rawValue, key: "VPNMode")
    }

    /// 从 UserDefaults 中加载先前保存的 VPN 模式字符串，并转换为枚举类型。
    ///
    /// 如果未找到已保存的值，则默认设置为非全局模式（`nonGlobal`）。
    /// 该方法保证视图初始化时 `selectedMode` 有合理的默认值，避免状态不一致。
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
