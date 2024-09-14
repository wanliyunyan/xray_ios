//
//  PacketTunnelManager.swift
//  Xray
//
//  Created by pan on 2024/9/14.
//

import NetworkExtension
import Combine

@MainActor
final class PacketTunnelManager: ObservableObject {
    
    private var cancel: Set<AnyCancellable> = []
    
    @Published private var manager: NETunnelProviderManager?
    
    static let shared: PacketTunnelManager = PacketTunnelManager()
    
    var status: NEVPNStatus? {
        manager?.connection.status
    }
    
    init() {
        Task(priority: .userInitiated) {
            cancel.removeAll()
            manager = await loadTunnelProviderManager()
            
            NotificationCenter.default
                .publisher(for: .NEVPNStatusDidChange)
                .receive(on: DispatchQueue.main)
                .sink { [unowned self] _ in objectWillChange.send() }
                .store(in: &cancel)
        }
    }
    
    private func loadTunnelProviderManager() async -> NETunnelProviderManager? {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            if let firstManager = managers.first(where: {
                guard let config = $0.protocolConfiguration as? NETunnelProviderProtocol else { return false }
                return config.providerBundleIdentifier == Constant.TunnelName
            }) {
                return firstManager
            } else {
                let configuration = NETunnelProviderProtocol()
                configuration.providerBundleIdentifier = Constant.TunnelName
                configuration.serverAddress = "localhost"
                configuration.providerConfiguration = [:]
                configuration.excludeLocalNetworks = true
                
                let manager = NETunnelProviderManager()
                manager.localizedDescription = "Xray"
                manager.protocolConfiguration = configuration
                manager.isEnabled = true

                try await manager.saveToPreferences()
                
                return await loadTunnelProviderManager()
            }
        } catch {
            return nil
        }
    }
    
    func start() async throws {
        try manager?.connection.startVPNTunnel(options: [
            "config": Constant.xrayConfig as NSString
        ])
    }
    
    func stop() {
        manager?.connection.stopVPNTunnel()
    }
}
