//
//  XrayApp.swift
//  Xray
//
//  Created by pan on 2024/9/14.
//

import SwiftUI

/// Xray iOS 应用入口。
///
/// 根视图注入全局 `PacketTunnelManager`，使主界面及其子视图共享同一份 VPN 系统状态。
@main
struct XrayApp: App {
    /// 创建唯一窗口场景并安装应用级环境对象。
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(PacketTunnelManager.shared)
        }
    }
}
