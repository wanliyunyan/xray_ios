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
    
    private var cancellables = Set<AnyCancellable>()
    
    @Published private var manager: NETunnelProviderManager?
    
    static let shared = PacketTunnelManager()
    
    var status: NEVPNStatus? {
        manager?.connection.status
    }
    
    init() {
        Task {
            await setupManager()
        }
    }
    
    private func setupManager() async {
        self.manager = await loadTunnelProviderManager()
        
        if let connection = manager?.connection {
            NotificationCenter.default.publisher(for: .NEVPNStatusDidChange, object: connection)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                .store(in: &cancellables)
        }
    }
    
    private func loadTunnelProviderManager() async -> NETunnelProviderManager? {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            if let existingManager = managers.first(where: {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == Constant.tunnelName
            }) {
                return existingManager
            } else {
                let manager = NETunnelProviderManager()
                let configuration = NETunnelProviderProtocol()
                configuration.providerBundleIdentifier = Constant.tunnelName
                configuration.serverAddress = "localhost"
                configuration.excludeLocalNetworks = true
                
                manager.localizedDescription = "Xray"
                manager.protocolConfiguration = configuration
                manager.isEnabled = true
                
                try await manager.saveToPreferences()
                try await manager.loadFromPreferences()
                
                return manager
            }
        } catch {
            print("加载 TunnelProviderManager 失败: \(error.localizedDescription)")
            return nil
        }
    }
    
    func start(config: String, port: Int) async throws {
        guard let manager = self.manager else {
            throw NSError(domain: "PacketTunnelManager", code: 0, userInfo: nil)
        }

        // 启动 VPN 并传递配置和端口号
        try manager.connection.startVPNTunnel(options: [
            "config": config as NSString,
            "port": port as NSNumber
        ])
    }
    
    func stop() {
        manager?.connection.stopVPNTunnel()
    }
}
