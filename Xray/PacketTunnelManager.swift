//
//  PacketTunnelManager.swift
//  Xray
//
//  Created by pan on 2024/9/14.
//

import Combine
import NetworkExtension
import os
import UIKit

// MARK: - Logger

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "PacketTunnelManager")

/// 一个单例类，用于管理自定义 VPN（或网络隧道）的连接状态、配置加载与保存等功能。
///
/// 该类负责管理 VPN 的整个生命周期，包括配置的初始化、状态的监听、VPN 的启动与停止等操作。
/// 它通过 `NETunnelProviderManager` 与系统进行交互，实现 VPN 的启动、停止和重启。
/// 在初始化时，会自动加载已有配置，若无则创建新配置，并持续监听 VPN 连接状态的变化，
/// 以便于界面实时更新和状态管理。
@MainActor
final class PacketTunnelManager: ObservableObject {
    
    /// 用于生成 Xray 配置请求字符串，辅助构建运行时所需的配置数据。
    private let xrayManager = XrayManager()
    
    // MARK: - 公有静态属性

    /// 全局单例，用于在 App 内统一管理 VPN。
    static let shared = PacketTunnelManager()

    // MARK: - 私有属性

    /// 用于存储任意符合 Combine 取消协议的对象，用以在 deinit 时解除订阅或取消任务。
    private var cancellables = Set<AnyCancellable>()

    /// VPN 的核心配置载体，保存启动所需的全部信息，包括协议配置、连接状态等。
    @Published private var manager: NETunnelProviderManager?

    // MARK: - 计算属性

    /// 返回当前 VPN 的连接状态，如果尚未初始化或无可用配置则返回 nil。
    ///
    /// 不同状态的应用场景：
    /// - `.connected`：VPN 已成功连接，网络流量已通过隧道。
    /// - `.connecting`：VPN 正在尝试连接中，等待建立隧道。
    /// - `.disconnected`：VPN 未连接，处于空闲状态。
    /// - `.disconnecting`：VPN 正在断开连接。
    /// - `.invalid`：VPN 配置无效或不可用。
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
    ///
    /// 该方法既会尝试加载已有的 VPN 配置，也会在没有配置时自动创建新的配置，
    /// 并通过通知中心监听 VPN 连接状态变化，以便及时更新界面和内部状态。
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
    /// 除了加载已有配置外，还会自动初始化配置参数，如 `serverAddress` 和 `excludeLocalNetworks`，
    /// 确保新建的 VPN 配置符合预期。
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
    /// 保存到系统偏好后必须立即 reload，以确保配置立即生效，避免配置不同步导致的启动失败。
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
    /// 该检查是为了避免多个 VPN 同时运行导致的冲突和连接异常，保证当前 VPN 配置的唯一性。
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
    ///
    /// 这是系统层级的交互提示，提醒用户手动切换 VPN 配置，避免多 VPN 冲突。
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
    /// 启动流程说明：
    /// 1. 检查是否有其他 VPN 正在运行，避免冲突。
    /// 2. 保存并加载当前配置，确保配置同步。
    /// 3. 从 UserDefaults 加载 SOCKS 端口和配置链接。
    /// 4. 构建 Xray 配置文件内容并转换为 base64 字符串。
    /// 5. 通过系统 API 启动 VPN 隧道，传入相关配置参数。
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
        guard let socks5Port = UtilStore.loadPort(key: "socks5Port")
        else {
            throw NSError(
                domain: "PacketTunnelManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "无法从 UserDefaults 加载端口或端口格式不正确"]
            )
        }

        guard let configLink = UtilStore.loadString(key: "configLink") else {
            throw NSError(domain: "ContentView", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "没有可用的配置"])
        }

        // 4. 构建 Xray 配置文件内容并写入 App Group 容器
        let configData = try Configuration().buildRunConfigurationData(configLink: configLink)
        guard let mergedConfigString = String(data: configData, encoding: .utf8) else {
            throw NSError(domain: "ConfigDataError", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "无法将配置数据转换为字符串"])
        }

        let base64String = try xrayManager.makeRunFromJSONRequest(
            datDir: Constant.assetDirectory.path,
            configJSON: mergedConfigString
        )
        
        // 5. 正式启动 VPN，传入 SOCKS 端口和配置文件路径
        do {
            try manager.connection.startVPNTunnel(options: [
                "socks5Port": NSNumber(value: socks5Port.rawValue),
                "base64String": base64String as NSString,
            ])
            logger.info("VPN 尝试启动")
        } catch let error as NSError {
            logger.error("连接 VPN 时出错: \(error.localizedDescription), 错误代码: \(error.code)")
            throw error
        }
    }

    /// 停止 VPN 连接。
    ///
    /// 通过调用系统 API 停止隧道连接，释放相关资源。
    func stop() {
        manager?.connection.stopVPNTunnel()
    }

    /// 重启 VPN（先停止再启动），可用于更新配置后重新生效。
    ///
    /// 该方法通过等待 VPN 状态从断开中或已连接状态切换到断开状态后再重新启动，
    /// 避免竞态条件和连接冲突，确保重启过程顺利。
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
