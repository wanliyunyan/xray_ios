//
//  XrayApp.swift
//  Xray
//
//  Created by pan on 2024/9/14.
//

import NetworkExtension
import SwiftUI

@main
struct XrayApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(PacketTunnelManager.shared)
        }
    }
}
