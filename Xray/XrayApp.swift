//
//  XrayApp.swift
//  Xray
//
//  Created by pan on 2024/9/14.
//

import SwiftUI

/// 应用内可从主界面进入的独立页面。
enum XrayAppRoute: Hashable {
    case chinaGeoAssets
}

/// Xray iOS 应用入口。
///
/// 根视图注入全局 `PacketTunnelManager`，使主界面及其子视图共享同一份 VPN 系统状态。
@main
@MainActor
struct XrayApp: App {
    @State private var appSessionState = AppSessionState()
    @State private var packetTunnelManager = PacketTunnelManager()

    /// 创建唯一窗口场景并安装应用级环境对象。
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                DashboardView()
                    .navigationDestination(for: XrayAppRoute.self) { route in
                        switch route {
                        case .chinaGeoAssets:
                            GeoAssetDownloadView()
                        }
                    }
            }
                .environment(packetTunnelManager)
                .environment(appSessionState)
        }
    }
}
