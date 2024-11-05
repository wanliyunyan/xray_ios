//
//  VPNModePicker.swift
//  Xray
//
//  Created by pan on 2024/11/5.
//

import SwiftUI

enum VPNMode: String {
    case global = "全局"
    case nonGlobal = "非全局"
}

struct VPNModePicker: View {
    @State private var selectedMode: VPNMode = .nonGlobal // 默认选择非全局模式
    @EnvironmentObject var packetTunnelManager: PacketTunnelManager

    var body: some View {
        VStack(alignment: .leading) {
            Text("路由模式:")
                .font(.headline)
            Picker("模式", selection: $selectedMode) {
                Text(VPNMode.nonGlobal.rawValue).tag(VPNMode.nonGlobal)
                Text(VPNMode.global.rawValue).tag(VPNMode.global)
            }
            .pickerStyle(SegmentedPickerStyle())
            .onChange(of: selectedMode) { oldMode, newMode in
                saveModeToUserDefaults(newMode)
                
                // 检查 VPN 是否已连接，并在切换模式时重启
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
        .onAppear {
            loadModeFromUserDefaults()
        }
    }

    // MARK: - Save and Load Mode to/from UserDefaults
    private func saveModeToUserDefaults(_ mode: VPNMode) {
        Util.saveToUserDefaults(value: mode.rawValue, key: "VPNMode")
    }

    private func loadModeFromUserDefaults() {
        if let modeString = Util.loadFromUserDefaults(key: "VPNMode"),
           let mode = VPNMode(rawValue: modeString) {
            selectedMode = mode
        } else {
            selectedMode = .nonGlobal // 如果没有存储的值，默认选择非全局模式
        }
    }
}
