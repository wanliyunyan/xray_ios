//
//  ContentView.swift
//  Xray
//
//  Created by pan on 2024/9/14.
//

import Foundation
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var packetTunnelManager: PacketTunnelManager

    var body: some View {
        VStack {
            if let status = packetTunnelManager.status {
                switch status {
                case .connected:
                    Button("断开") {
                        disconnectVPN()
                    }
                case .disconnected:
                    Button("连接") {
                        connectVPN()
                    }
                default:
                    ProgressView()
                }
            }
        }
    }

    func connectVPN() {
        Task {
            do {
                try await packetTunnelManager.start()
            } catch {
                debugPrint(error.localizedDescription)
            }
        }
    }

    func disconnectVPN() {
        Task {
            packetTunnelManager.stop()
        }
    }
}
