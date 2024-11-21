//
//  PacketTunnelManager.swift
//  Xray
//
//  Created by pan on 2024/9/14.
//

@preconcurrency import NetworkExtension
import Combine
import UIKit

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

    /// 初始化并设置 VPN 配置
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

    /// 加载或创建 VPN 配置
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

                try await saveAndLoad(manager: manager)
                return manager
            }
        } catch {
            print("加载或创建 TunnelProviderManager 失败: \(error.localizedDescription)")
            return nil
        }
    }

    /// 保存并加载 VPN 配置
    private func saveAndLoad(manager: NETunnelProviderManager) async throws {
        do {
            manager.isEnabled = true
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
            print("VPN 配置已保存并加载")
        } catch {
            throw NSError(domain: "PacketTunnelManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "保存或加载配置失败: \(error.localizedDescription)"])
        }
    }

    /// 检查是否有其他 VPN 配置正在运行
    private func checkOtherVPNs() async -> Bool {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            for manager in managers {
                if manager.connection.status == .connected || manager.connection.status == .connecting {
                    print("检测到其他 VPN 正在运行: \(manager.localizedDescription ?? "未知")")
                    return true
                }
            }
        } catch {
            print("检查其他 VPN 状态失败: \(error.localizedDescription)")
        }
        return false
    }

    /// 显示切换 VPN 配置的提示
    private func showSwitchVPNAlert() {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: "切换 VPN 配置", message: "系统检测到其他 VPN 配置正在使用，请前往设置切换到当前配置。", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "确定", style: .default, handler: nil))

            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootViewController = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
                print("未找到活动的 UIWindowScene 或 rootViewController")
                return
            }
            rootViewController.present(alert, animated: true, completion: nil)
        }
    }


    /// 启动 VPN
    func start() async throws {
        guard let manager = self.manager else {
            throw NSError(domain: "PacketTunnelManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "Manager 未初始化"])
        }

        // 检查是否有其他 VPN 正在运行
        if await checkOtherVPNs() {
            print("检测到其他 VPN 正在运行")
            showSwitchVPNAlert()
            return
        }

        // 启用并加载配置
        try await saveAndLoad(manager: manager)

        // 从 UserDefaults 加载端口和配置
        guard let sock5PortString = Util.loadFromUserDefaults(key: "sock5Port"),
              let sock5Port = Int(sock5PortString) else {
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

        // 检查配置文件是否存在
        guard FileManager.default.fileExists(atPath: fileUrl.path) else {
            throw NSError(domain: "PacketTunnelManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "配置文件不存在: \(fileUrl.path)"])
        }

        // 启动 VPN 并传递配置和端口号
        do {
            try manager.connection.startVPNTunnel(options: [
                "sock5Port": sock5Port as NSNumber,
                "path": fileUrl.path as NSString,
            ])
            print("VPN 启动成功")
        } catch let error as NSError {
            print("连接 VPN 时出错: \(error.localizedDescription), 错误代码: \(error.code)")
            throw error
        }
    }

    /// 停止 VPN
    func stop() {
        manager?.connection.stopVPNTunnel()
    }

    /// 重启 VPN
    func restart() async throws {
        stop()

        // 等待 VPN 停止
        while manager?.connection.status == .disconnecting || manager?.connection.status == .connected {
            try await Task.sleep(nanoseconds: 500_000_000) // 等待 0.5 秒
        }

        try await start()
    }
}
