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

/// 管理 Packet Tunnel 系统配置、连接状态和启停流程的应用级单例。
///
/// 该类型通过 `NETunnelProviderManager` 与 NetworkExtension 交互，主要职责包括：
/// - 从系统偏好加载当前扩展的 VPN 配置，不存在时创建并保存；
/// - 监听 `NEVPNStatusDidChange` 并通知 SwiftUI 刷新连接状态；
/// - 启动前构建最新 Xray TUN JSON，并通过启动参数传给 Packet Tunnel 扩展；
/// - 检测其他正在运行的 Tunnel Provider，避免同时启用多个 VPN 配置；
/// - 提供停止和等待完全断开后的重启能力。
@MainActor
final class PacketTunnelManager: ObservableObject {
    // MARK: - Shared Instance

    /// App 内唯一的 VPN 管理实例，所有视图共享同一份系统连接状态。
    static let shared = PacketTunnelManager()

    // MARK: - State

    /// 保存 VPN 状态通知订阅，使订阅生命周期与单例一致。
    private var cancellables = Set<AnyCancellable>()

    /// 当前扩展对应的系统 VPN 配置。
    ///
    /// 配置异步加载完成前为 `nil`。属性变化由 `@Published` 通知界面，连接对象内部的
    /// `status` 变化则由 `NEVPNStatusDidChange` 订阅手动转发。
    @Published private var manager: NETunnelProviderManager?

    /// 当前 VPN 连接状态；系统配置尚未加载时为 `nil`。
    ///
    /// 常见状态包括 `.disconnected`、`.connecting`、`.connected`、`.reasserting` 和
    /// `.disconnecting`，界面据此选择操作按钮或加载提示。
    var status: NEVPNStatus? {
        manager?.connection.status
    }

    /// 当前连接成功的时间；尚未连接或系统未提供时间时为 `nil`。
    var connectedDate: Date? {
        manager?.connection.connectedDate
    }

    // MARK: - Initialization

    /// 创建单例后异步加载系统配置并安装状态监听。
    ///
    /// 初始化保持私有，防止多个实例分别持有不同的 `NETunnelProviderManager`。
    private init() {
        Task {
            await setupManager()
        }
    }

    // MARK: - Manager Setup

    /// 加载或创建系统 VPN 配置，并将连接状态变化转发给 SwiftUI。
    ///
    /// `NETunnelProviderSession.status` 不是 `@Published` 属性，因此需要监听系统通知并显式
    /// 发送 `objectWillChange`。通知限定到当前 connection，避免其他 VPN 的状态变化触发刷新。
    private func setupManager() async {
        manager = await loadTunnelProviderManager()

        if let connection = manager?.connection {
            NotificationCenter.default
                .publisher(for: .NEVPNStatusDidChange, object: connection)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                .store(in: &cancellables)
        }
    }

    /// 复用当前扩展的系统配置；不存在时创建并保存一份新配置。
    ///
    /// 查找时使用 `providerBundleIdentifier == AppConstants.tunnelName`，避免误用其他应用或旧扩展
    /// 的配置。新配置使用 `localhost` 作为系统要求的展示地址，排除局域网流量，并启用后
    /// 立即保存、重新加载，确保系统返回可启动的持久化对象。
    ///
    /// - Returns: 可用的 `NETunnelProviderManager`；加载或保存失败时记录日志并返回 `nil`。
    private func loadTunnelProviderManager() async -> NETunnelProviderManager? {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()

            if let existingManager = managers.first(where: {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == AppConstants.tunnelName
            }) {
                return existingManager
            } else {
                let manager = NETunnelProviderManager()
                let configuration = NETunnelProviderProtocol()
                configuration.providerBundleIdentifier = AppConstants.tunnelName
                configuration.serverAddress = "localhost"
                configuration.excludeLocalNetworks = true

                manager.localizedDescription = "Xray"
                manager.protocolConfiguration = configuration
                manager.isEnabled = true

                try await saveAndLoad(manager: manager)
                return manager
            }
        } catch {
            logger.error("加载或创建 TunnelProviderManager 失败: \(error.localizedDescription)")
            return nil
        }
    }

    /// 保存系统 VPN 配置并重新加载，使最新设置生效。
    ///
    /// NetworkExtension 在保存后仍可能保留旧的内存状态，因此必须紧接着调用
    /// `loadFromPreferences()`，再使用同一对象启动连接。
    ///
    /// - Parameter manager: 需要持久化和刷新的系统 VPN 配置。
    /// - Throws: 保存或重新加载失败时，包装为带本地化描述的 `PacketTunnelManager` 错误。
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

    // MARK: - VPN Conflict Handling

    /// 检查是否已有 Tunnel Provider 正在连接或已连接。
    ///
    /// 方法重新读取系统中的全部 `NETunnelProviderManager`，只把 `.connecting` 和
    /// `.connected` 视为冲突；读取失败时记录日志并按“无冲突”处理，让当前启动流程继续。
    ///
    /// - Returns: 存在活动 Tunnel Provider 时返回 `true`。
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

    /// 提示用户前往系统设置切换当前使用的 VPN 配置。
    ///
    /// NetworkExtension 不允许应用静默替换另一个正在使用的 VPN。方法从当前活动窗口查找
    /// 根控制器并显示系统 `UIAlertController`；找不到可呈现窗口时仅记录错误。
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

    // MARK: - Tunnel Control

    /// 构建当前分享链接的运行配置，并启动 Packet Tunnel。
    ///
    /// 启动流程：
    /// 1. 确认系统 VPN 配置已经完成异步初始化；
    /// 2. 检查其他 Tunnel Provider，存在冲突时提示用户并结束本次启动；
    /// 3. 重新保存并加载当前配置，避免系统仍处于待更新状态；
    /// 4. 从 App Group 偏好读取最新分享链接；
    /// 5. 生成包含 TUN、Metrics、Routing 和 DNS 的运行 JSON；
    /// 6. 通过 `AppConstants.tunnelConfigurationOptionKey` 将原始 JSON Data 传给扩展。
    ///
    /// utun 文件描述符此时尚不存在，不能由主 App 写进配置；扩展应用网络设置后会自行注入。
    ///
    /// - Throws: Manager 未初始化、配置缺失或构建失败、系统偏好保存失败，或
    ///   `startVPNTunnel` 拒绝启动时抛出错误。
    func start() async throws {
        guard let manager else {
            throw NSError(domain: "PacketTunnelManager", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Manager 未初始化"])
        }

        // 1. 已有活动 VPN 时交由用户在系统中确认切换。
        if await checkOtherVPNs() {
            logger.info("检测到其他 VPN 正在运行")
            showSwitchVPNAlert()
            return
        }

        // 2. 启动前重新加载，避免系统配置仍处于待更新状态。
        try await saveAndLoad(manager: manager)

        // 3. 使用最近一次粘贴或扫描并持久化的分享链接。
        guard let configLink = AppGroupStore.loadString(key: "configLink") else {
            throw NSError(domain: "DashboardView", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "没有可用的配置"])
        }

        // 4. 构建原始运行配置；utun FD 只能由扩展在启动后注入。
        let configData = try XrayConfigurationBuilder().buildRunConfigurationData(configLink: configLink)

        // 5. JSON Data 作为一次性启动参数传递，不写入系统 VPN 协议配置。
        do {
            try manager.connection.startVPNTunnel(options: [
                AppConstants.tunnelConfigurationOptionKey: configData as NSData,
            ])
            logger.info("VPN 尝试启动")
        } catch let error as NSError {
            logger.error("连接 VPN 时出错: \(error.localizedDescription), 错误代码: \(error.code)")
            throw error
        }
    }

    /// 请求系统停止当前 VPN 连接。
    ///
    /// 该 API 是异步状态转换的起点，调用返回时状态可能仍为 `.disconnecting`。
    func stop() {
        manager?.connection.stopVPNTunnel()
    }

    /// 等待当前连接完全停止后重新启动，使最新配置生效。
    ///
    /// `stopVPNTunnel()` 不提供 async 完成回调，因此每 0.5 秒检查一次系统状态。只有状态离开
    /// `.connected` 和 `.disconnecting` 后才重新执行完整启动流程，避免旧扩展尚未退出时启动
    /// 新实例。
    ///
    /// - Throws: 等待任务被取消，或后续 `start()` 失败时抛出错误。
    func restart() async throws {
        stop()

        while manager?.connection.status == .disconnecting
            || manager?.connection.status == .connected
        {
            try await Task.sleep(nanoseconds: 500_000_000)
        }

        try await start()
    }
}
