//
//  ConnectedDurationView.swift
//  Xray
//
//  Created by pan on 2024/9/23.
//

import Foundation
import SwiftUI

struct ConnectedDurationView: View {
    
    @EnvironmentObject private var packetTunnelManager: PacketTunnelManager
    
    var body: some View {
        LabeledContent {
            if let status = packetTunnelManager.status, status == .connected {
                if let connectedDate = packetTunnelManager.connectedDate {
                    TimelineView(.periodic(from: Date(), by: 1.0)) { context in
                        Text(connectedDateString(connectedDate: connectedDate, current: context.date))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                } else {
                    Text("00:00")
                }
            } else {
                Text("00:00")
            }
        } label: {
            Text("连接时长").font(.headline)
        }
    }
    
    private func connectedDateString(connectedDate: Date, current: Date) -> String {
        let duration = Int64(abs(current.distance(to: connectedDate)))
        let hs = duration / 3600
        let ms = duration % 3600 / 60
        let ss = duration % 60
        if hs <= 0 {
            return String(format: "%02d:%02d", ms, ss)
        } else {
            return String(format: "%02d:%02d:%02d", hs, ms, ss)
        }
    }
}
