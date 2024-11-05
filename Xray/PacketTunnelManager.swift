//
//  PacketTunnelManager.swift
//  Xray
//
//  Created by pan on 2024/9/14.
//

@preconcurrency import NetworkExtension
import Combine

@MainActor
final class PacketTunnelManager: ObservableObject {
    
    private var cancellables = Set<AnyCancellable>()
    
    @Published private var manager: NETunnelProviderManager?
    
    static let shared = PacketTunnelManager()
    
    var status: NEVPNStatus? {
        manager?.connection.status
    }
    
    var connectedDate: Date? {
        manager?.connection.connectedDate
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
    
    func start() async throws {
        guard let manager = self.manager else {
            throw NSError(domain: "PacketTunnelManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "Manager 未初始化"])
        }

        // 从 UserDefaults 加载端口并尝试转换为 Int
        guard let sock5PortString = Util.loadFromUserDefaults(key: "sock5Port"),
              let sock5Port = Int(sock5PortString)  else {
            throw NSError(domain: "ConfigurationError", code: 0, userInfo: [NSLocalizedDescriptionKey: "无法从 UserDefaults 加载端口或端口格式不正确"])
        }
        
        guard let config = Util.loadFromUserDefaults(key: "configLink") else {
            throw NSError(domain: "ContentView", code: 0, userInfo: [NSLocalizedDescriptionKey: "没有可用的配置"])
        }
        
        // 构建配置数据并生成配置文件 URL
        let configData = try Configuration().buildConfigurationData(config: config)
        
        guard let mergedConfigString = String(data: configData, encoding: .utf8) else {
            throw NSError(domain: "ConfigDataError", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法将配置数据转换为字符串"])
        }
        let fileUrl = try Util.createConfigFile(with: mergedConfigString)
        
        // 启动 VPN 并传递配置和端口号
        try manager.connection.startVPNTunnel(options: [
            "sock5Port": sock5Port as NSNumber,
            "path": fileUrl.path() as NSString,
        ])
    }
    
    func stop() {
        manager?.connection.stopVPNTunnel()
    }
    

    func restart() async throws {

        stop()
        
        while manager?.connection.status == .disconnecting || manager?.connection.status == .connected {
            try await Task.sleep(nanoseconds: 500_000_000) // 等待0.5秒
        }
        
        try await start()
    }
}
