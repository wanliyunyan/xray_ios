//
//  VPNModePickerView.swift
//  Xray
//
//  Created by pan on 2024/11/5.
//

import SwiftUI

/// VPN 工作模式枚举：支持“全局”和“非全局”两种模式。
enum VPNMode: String {
    case global = "全局"
    case nonGlobal = "非全局"
}

/// 一个让用户选择 VPN 路由模式（全局/非全局）的视图，
/// 并在切换模式时保存到 UserDefaults，同时若 VPN 已连接则自动重启应用。
struct VPNModePickerView: View {
    // MARK: - 属性

    /// 当前选中的 VPN 模式，默认设置为非全局。
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
                // 将新的模式存储到 UserDefaults
                saveModeToUserDefaults(newMode)

                // 如果当前 VPN 已处于连接状态，则进行重启以应用新的模式
                if packetTunnelManager.status == .connected {
                    Task {
                        do {
                            try await packetTunnelManager.restart()
                            print("VPN 已成功重启")
                        } catch {
                            print("VPN 重启失败：\(error.localizedDescription)")
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

    /// 将用户选择的 VPN 模式保存到 UserDefaults。
    ///
    /// - Parameter mode: 当前选中的 VPN 模式。
    private func saveModeToUserDefaults(_ mode: VPNMode) {
        Util.saveToUserDefaults(value: mode.rawValue, key: "VPNMode")
    }

    /// 从 UserDefaults 读取先前保存的 VPN 模式；如果没有找到，则默认设置为非全局模式。
    private func loadModeFromUserDefaults() {
        if let modeString = Util.loadFromUserDefaults(key: "VPNMode"),
           let mode = VPNMode(rawValue: modeString)
        {
            selectedMode = mode
        } else {
            selectedMode = .nonGlobal
        }
    }
}
