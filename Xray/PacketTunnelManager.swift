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
    
    func start(with clipboardContent:String?) async throws {
        
        var configContent: String

        if let clipboardContent = clipboardContent, !clipboardContent.isEmpty {
            // 如果传入的 clipboardContent 不为空，则使用它，并保存到本地
            configContent = clipboardContent
            saveClipboardContentToFile(configContent)
        } else {
            // 否则，从本地的 txt 文件中读取
            guard let savedContent = readClipboardContentFromFile(), !savedContent.isEmpty else {
                throw NSError(domain: "VPN Manager", code: 0, userInfo: [NSLocalizedDescriptionKey: "没有可用的配置，且剪贴板内容为空"])
            }
            configContent = savedContent
        }
        
        guard let manager = self.manager else {
            throw NSError(domain: "VPN Manager 未初始化", code: 0, userInfo: nil)
        }
        try manager.connection.startVPNTunnel(options: [
            "config": configContent as NSString
        ])
    }
    
    func stop() {
        manager?.connection.stopVPNTunnel()
    }
    
    // 从本地的 txt 文件中读取剪贴板内容
    private func readClipboardContentFromFile() -> String? {
        let fileName = "clipboardContent.txt"
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent(fileName)
        
        do {
            let savedContent = try String(contentsOf: fileURL, encoding: .utf8)
            print("从文件中读取的剪贴板内容: \(savedContent)")
            return savedContent
        } catch {
            print("读取剪贴板内容失败: \(error.localizedDescription)")
            return nil
        }
    }

    // 保存剪贴板内容到本地的 txt 文件
    private func saveClipboardContentToFile(_ clipboardContent: String) {
        // 定义文件路径，可以将其存放到应用的 Documents 目录
        let fileName = "clipboardContent.txt"
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent(fileName)

        do {
            // 将字符串写入文件
            try clipboardContent.write(to: fileURL, atomically: true, encoding: .utf8)
            print("剪贴板内容已成功保存到文件: \(fileURL.path)")
        } catch {
            print("保存剪贴板内容失败: \(error.localizedDescription)")
        }
    }
}
