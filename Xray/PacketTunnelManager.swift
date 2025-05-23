//
//  PacketTunnelManager.swift
//  Xray
//
//  Created by pan on 2024/9/14.
//

import Combine
@preconcurrency import NetworkExtension
import os
import UIKit

// MARK: - Logger

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "PacketTunnelManager")

/// 一个单例类，用于管理自定义 VPN（或网络隧道）的连接状态、配置加载与保存等功能。
///
/// 通过 `NETunnelProviderManager` 与系统交互，实现启动、停止和重启 VPN。
/// 在初始化时，会自动加载或创建对应的 VPN 配置，并监听其连接状态。
@MainActor
final class PacketTunnelManager: ObservableObject {
    // MARK: - 公有静态属性

    /// 全局单例，用于在 App 内统一管理 VPN。
    static let shared = PacketTunnelManager()

    // MARK: - 私有属性

    /// 用于存储任意符合 Combine 取消协议的对象，用以在 deinit 时解除订阅或取消任务。
    private var cancellables = Set<AnyCancellable>()

    /// 当前的 `NETunnelProviderManager` 实例，负责具体的 VPN 配置与连接。
    @Published private var manager: NETunnelProviderManager?

    // MARK: - 计算属性

    /// 返回当前 VPN 的连接状态，如果尚未初始化或无可用配置则返回 nil。
    var status: NEVPNStatus? {
        manager?.connection.status
    }

    /// 返回当前 VPN 的连接开始时间（`connectedDate`），如果尚未连接或无可用配置则为 nil。
    var connectedDate: Date? {
        manager?.connection.connectedDate
    }

    // MARK: - 初始化

    /// 构造函数，在创建单例时自动调用 `setupManager()` 来加载或创建 VPN 配置。
    private init() {
        Task {
            await setupManager()
        }
    }

    // MARK: - 配置初始化与监听

    /// 初始化并设置 VPN 的基础配置，若成功则监听连接状态的变化。
    private func setupManager() async {
        // 尝试加载或新建 `NETunnelProviderManager`
        manager = await loadTunnelProviderManager()

        // 监听 VPN 连接状态变化（当 status 改变时，通过 Combine 通知界面刷新）
        if let connection = manager?.connection {
            NotificationCenter.default
                .publisher(for: .NEVPNStatusDidChange, object: connection)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    // 手动触发 SwiftUI 界面刷新
                    self?.objectWillChange.send()
                }
                .store(in: &cancellables)
        }
    }

    // MARK: - Manager 加载或创建

    /// 从系统加载所有自定义的 TunnelProviderManager，如无可用则创建新的。
    ///
    /// - Returns: 返回加载或新建的 `NETunnelProviderManager`。
    /// - Throws: 若在加载过程中出现系统错误，可能抛出异常（已在方法内捕获并返回 nil）。
    private func loadTunnelProviderManager() async -> NETunnelProviderManager? {
        do {
            // 尝试从系统中加载所有可用的 NETunnelProviderManager
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()

            // 如果已存在与我们指定的 providerBundleIdentifier 相符的 manager，直接复用
            if let existingManager = managers.first(where: {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == Constant.tunnelName
            }) {
                return existingManager
            } else {
                // 否则创建一个全新的 manager 并配置相关参数
                let manager = NETunnelProviderManager()
                let configuration = NETunnelProviderProtocol()
                configuration.providerBundleIdentifier = Constant.tunnelName
                configuration.serverAddress = "localhost"
                configuration.excludeLocalNetworks = true

                manager.localizedDescription = "Xray"
                manager.protocolConfiguration = configuration
                manager.isEnabled = true

                // 保存并加载配置，确保系统识别此 VPN
                try await saveAndLoad(manager: manager)
                return manager
            }
        } catch {
            logger.error("加载或创建 TunnelProviderManager 失败: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - 保存并加载配置

    /// 将给定的 `NETunnelProviderManager` 保存到系统偏好并重新加载，以使配置生效。
    ///
    /// - Parameter manager: 要保存的 `NETunnelProviderManager` 实例。
    /// - Throws: 如果保存或加载流程出现错误则抛出。
    private func saveAndLoad(manager: NETunnelProviderManager) async throws {
        do {
            manager.isEnabled = true
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
            logger.info("VPN 配置已保存并加载")
        } catch {
            throw NSError(
                domain: "PacketTunnelManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "保存或加载配置失败: \(error.localizedDescription)"]
            )
        }
    }

    // MARK: - 检查其他 VPN

    /// 检测系统中是否有其他的自定义 VPN 在连接或正在连接中。
    ///
    /// - Returns: 如果检测到其他 VPN 正在连接/已连接，则返回 `true`；否则为 `false`。
    private func checkOtherVPNs() async -> Bool {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            for manager in managers {
                let status = manager.connection.status
                if status == .connected || status == .connecting {
                    logger.info("检测到其他 VPN 正在运行: \(manager.localizedDescription ?? "未知")")
                    return true
                }
            }
        } catch {
            logger.error("检查其他 VPN 状态失败: \(error.localizedDescription)")
        }
        return false
    }

    /// 当检测到有其他 VPN 正在使用时，弹出系统原生弹窗提示用户进行切换。
    private func showSwitchVPNAlert() {
        DispatchQueue.main.async {
            let alert = UIAlertController(
                title: "切换 VPN 配置",
                message: "系统检测到其他 VPN 配置正在使用，请前往设置切换到当前配置。",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "确定", style: .default, handler: nil))

            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootViewController = windowScene
                  .windows.first(where: { $0.isKeyWindow })?
                  .rootViewController
            else {
                logger.error("未找到活动的 UIWindowScene 或 rootViewController")
                return
            }
            rootViewController.present(alert, animated: true, completion: nil)
        }
    }

    // MARK: - VPN 操作

    /// 启动 VPN，并传入必要的配置信息与端口。
    ///
    /// - Throws: 当无法初始化 manager、或端口 / 配置读取失败、或启动出错时，抛出相应错误。
    func start() async throws {
        guard let manager = manager else {
            throw NSError(domain: "PacketTunnelManager", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Manager 未初始化"])
        }

        // 1. 检查是否有其他 VPN 正在运行
        if await checkOtherVPNs() {
            logger.info("检测到其他 VPN 正在运行")
            showSwitchVPNAlert()
            return
        }

        // 2. 保存并加载当前配置，以防止配置处于更新状态而无法启动
        try await saveAndLoad(manager: manager)

        // 3. 从 UserDefaults 加载 SOCKS 端口和配置链接
        guard let sock5PortString = Util.loadFromUserDefaults(key: "sock5Port"),
              let sock5Port = Int(sock5PortString)
        else {
            throw NSError(domain: "ConfigurationError", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "无法从 UserDefaults 加载端口或端口格式不正确"])
        }

        guard let config = Util.loadFromUserDefaults(key: "configLink") else {
            throw NSError(domain: "ContentView", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "没有可用的配置"])
        }

        // 4. 构建 Xray 配置文件内容并写入 App Group 容器
        let configData = try Configuration().buildRunConfigurationData(config: config)
        guard let mergedConfigString = String(data: configData, encoding: .utf8) else {
            throw NSError(domain: "ConfigDataError", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "无法将配置数据转换为字符串"])
        }
        let fileUrl = try Util.createConfigFile(with: mergedConfigString)

        // 5. 确认配置文件存在
        guard FileManager.default.fileExists(atPath: fileUrl.path) else {
            throw NSError(domain: "PacketTunnelManager", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "配置文件不存在: \(fileUrl.path)"])
        }

        // 6. 正式启动 VPN，传入 SOCKS 端口和配置文件路径
        do {
            try manager.connection.startVPNTunnel(options: [
                "sock5Port": sock5Port as NSNumber,
                "path": fileUrl.path as NSString,
            ])
            logger.info("VPN 尝试启动")
        } catch let error as NSError {
            logger.error("连接 VPN 时出错: \(error.localizedDescription), 错误代码: \(error.code)")
            throw error
        }
    }

    /// 停止 VPN 连接。
    func stop() {
        manager?.connection.stopVPNTunnel()
    }

    /// 重启 VPN（先停止再启动），可用于更新配置后重新生效。
    ///
    /// - Throws: 若在停止或启动过程中出现错误，则可能抛出异常。
    func restart() async throws {
        // 1. 先停止 VPN
        stop()

        // 2. 等待 VPN 真正停用（状态从 disconnecting / connected 过渡到 disconnected）
        while manager?.connection.status == .disconnecting
            || manager?.connection.status == .connected
        {
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 秒
        }

        // 3. 重新启动
        try await start()
    }
}
