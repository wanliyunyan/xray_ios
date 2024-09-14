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
        cancel.removeAll()
        Task {
            self.manager = await self.loadTunnelProviderManager()
            if let connection = manager?.connection {
                NotificationCenter.default
                    .publisher(for: .NEVPNStatusDidChange, object: connection)
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] _ in
                        self?.objectWillChange.send()
                    }
                    .store(in: &cancel)
            }
        }
    }
    
    private func loadTunnelProviderManager() async -> NETunnelProviderManager? {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            if let firstManager = managers.first(where: {
                guard let config = $0.protocolConfiguration as? NETunnelProviderProtocol else { return false }
                return config.providerBundleIdentifier == Constant.tunnelName
            }) {
                return firstManager
            } else {
                let configuration = NETunnelProviderProtocol()
                configuration.providerBundleIdentifier = Constant.tunnelName
                configuration.serverAddress = "localhost"
                configuration.providerConfiguration = [:]
                configuration.excludeLocalNetworks = true
                
                let manager = NETunnelProviderManager()
                manager.localizedDescription = "Xray"
                manager.protocolConfiguration = configuration
                manager.isEnabled = true

                try await manager.saveToPreferences()
                
                // 重新加载配置以获取更新的 `manager`
                return await loadTunnelProviderManager()
            }
        } catch {
            print("加载 TunnelProviderManager 失败: \(error.localizedDescription)")
            return nil
        }
    }
    
    func start() async throws {
        guard let manager = self.manager else {
            throw NSError(domain: "VPN Manager 未初始化", code: 0, userInfo: nil)
        }
        try manager.connection.startVPNTunnel(options: [
            "config": Constant.xrayConfig as NSString
        ])
    }
    
    func stop() {
        manager?.connection.stopVPNTunnel()
    }
}
