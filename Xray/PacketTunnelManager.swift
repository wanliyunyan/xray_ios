//
//  PacketTunnelManager.swift
//  Xray
//
//  Created by pan on 2024/9/14.
//

@preconcurrency import NetworkExtension
import Observation
import os

// MARK: - 日志

private let logger = Logger(subsystem: AppConstants.loggingSubsystem, category: "PacketTunnelManager")
private let activeShareLinkKey = "activeConfigLink"

/// 管理 Packet Tunnel 系统配置、连接状态和启停流程的应用级实例。
///
/// 该类型通过 `NETunnelProviderManager` 与 NetworkExtension 交互，主要职责包括：
/// - 从系统偏好加载当前扩展的 VPN 配置，不存在时创建并保存；
/// - 监听 `NEVPNStatusDidChange` 并通知 SwiftUI 刷新连接状态；
/// - 启动前构建最新 Xray TUN JSON，并通过启动参数传给 Packet Tunnel 扩展；
/// - 提供停止和等待完全断开后的重启能力。
@MainActor
@Observable
final class PacketTunnelManager {
    // MARK: - 状态

    /// 合并并发初始化请求，避免同时加载或创建多个系统 VPN 配置。
    @ObservationIgnored
    private var managerSetupTask: Task<NETunnelProviderManager?, Never>?

    /// 使用异步通知序列观察系统连接状态。
    @ObservationIgnored
    private var statusObservationTask: Task<Void, Never>?

    /// 防止系统接受启动请求后始终不回报任何活动状态。
    @ObservationIgnored
    private var startAcknowledgementTask: Task<Void, Never>?

    /// 当前扩展对应的系统 VPN 配置。
    @ObservationIgnored
    private var tunnelProviderManager: NETunnelProviderManager?

    /// 跨越异步预检和系统状态确认阶段，阻止重复启动。
    @ObservationIgnored
    private var startGate = VPNStartGate()

    /// 由系统状态和应用正在执行的生命周期操作共同驱动的界面状态。
    private(set) var lifecycleState: VPNLifecycleState = .loading

    /// 当前连接成功的时间；尚未连接或系统未提供时间时为 `nil`。
    private(set) var connectedDate: Date?

    /// 当前 Packet Tunnel 启动时实际使用的分享链接快照。
    private(set) var activeShareLink: String?

    // MARK: - 初始化

    /// 创建应用级实例后异步加载系统配置并安装状态监听。
    init() {
        Task { [weak self] in
            await self?.ensureTunnelManagerIsReady()
        }
    }

    deinit {
        managerSetupTask?.cancel()
        statusObservationTask?.cancel()
        startAcknowledgementTask?.cancel()
    }

    // MARK: - 管理器配置

    /// 加载或创建系统 VPN 配置，并将连接状态变化转发给 SwiftUI。
    ///
    /// `NETunnelProviderSession.status` 不是可观察属性，因此监听系统通知并转换为
    /// `lifecycleState`。通知限定到当前 connection，避免其他 VPN 的状态变化触发刷新。
    @discardableResult
    private func ensureTunnelManagerIsReady() async -> NETunnelProviderManager? {
        if let tunnelProviderManager {
            return tunnelProviderManager
        }

        let setupTask: Task<NETunnelProviderManager?, Never>
        if let managerSetupTask {
            setupTask = managerSetupTask
        } else {
            lifecycleState = .loading
            let newTask = Task { [weak self] in
                await self?.loadTunnelProviderManager()
            }
            managerSetupTask = newTask
            setupTask = newTask
        }

        let loadedManager = await setupTask.value
        managerSetupTask = nil

        guard let loadedManager else {
            lifecycleState = .failed("无法加载 VPN 配置")
            return nil
        }

        guard tunnelProviderManager == nil else {
            return tunnelProviderManager
        }

        tunnelProviderManager = loadedManager
        refreshConnectionState()
        observeStatusChanges(for: loadedManager)
        return loadedManager
    }

    private func observeStatusChanges(for manager: NETunnelProviderManager) {
        statusObservationTask?.cancel()
        let connection = manager.connection
        statusObservationTask = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: .NEVPNStatusDidChange,
                object: connection
            ) {
                guard !Task.isCancelled else {
                    return
                }
                self?.refreshConnectionState()
            }
        }
    }

    /// 复用当前扩展的系统配置；不存在时创建并保存一份新配置。
    ///
    /// 查找时使用 `providerBundleIdentifier == AppConstants.tunnelProviderIdentifier`，避免误用其他应用或旧扩展
    /// 的配置。新配置使用 `localhost` 作为系统要求的展示地址，排除局域网流量，并启用后
    /// 立即保存、重新加载，确保系统返回可启动的持久化对象。
    ///
    /// - Returns: 可用的 `NETunnelProviderManager`；加载或保存失败时记录日志并返回 `nil`。
    private func loadTunnelProviderManager() async -> NETunnelProviderManager? {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()

            if let existingManager = managers.first(where: {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == AppConstants.tunnelProviderIdentifier
            }) {
                return existingManager
            } else {
                let manager = NETunnelProviderManager()
                let configuration = NETunnelProviderProtocol()
                configuration.providerBundleIdentifier = AppConstants.tunnelProviderIdentifier
                configuration.serverAddress = "localhost"
                configuration.excludeLocalNetworks = true

                manager.localizedDescription = "Xray"
                manager.protocolConfiguration = configuration
                manager.isEnabled = true

                try await saveAndReload(manager)
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
    private func saveAndReload(_ manager: NETunnelProviderManager) async throws {
        do {
            manager.isEnabled = true
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
            logger.info("VPN 配置已保存并加载")
        } catch {
            throw PacketTunnelManagerError.preferenceUpdateFailed(error.localizedDescription)
        }
    }

    // MARK: - 隧道控制

    /// 确认系统 VPN 配置可用，并刷新真实状态供界面选择端口准备策略。
    func prepareForConnection() async throws {
        guard await ensureTunnelManagerIsReady() != nil else {
            throw PacketTunnelManagerError.managerUnavailable
        }
        refreshConnectionState()
    }

    /// 构建当前分享链接的运行配置，并启动 Packet Tunnel。
    ///
    /// 启动流程：
    /// 1. 确认系统 VPN 配置已经完成异步初始化；
    /// 2. 对当前分享链接建立不可变快照，后续导入只影响下一次连接；
    /// 3. 重新保存并加载当前配置，避免系统仍处于待更新状态；
    /// 4. 生成包含 TUN、Metrics、Routing 和 DNS 的运行 JSON；
    /// 5. 通过 `AppConstants.tunnelConfigurationOptionKey` 将原始 JSON Data 传给扩展。
    ///
    /// utun 文件描述符此时尚不存在，不能由主 App 写进配置；扩展应用网络设置后会自行注入。
    ///
    /// - Throws: Manager 未初始化、配置缺失或构建失败、系统偏好保存失败，或
    ///   `startVPNTunnel` 拒绝启动时抛出错误。
    func start() async throws {
        guard let tunnelProviderManager = await ensureTunnelManagerIsReady() else {
            throw PacketTunnelManagerError.managerUnavailable
        }

        refreshConnectionState()
        try startGate.begin(from: lifecycleState)

        lifecycleState = .connecting
        do {
            // 1. 在第一次挂起前固定本次连接使用的配置，避免连接过程中导入产生竞态。
            guard
                let shareLink = AppGroupStore.loadString(forKey: "configLink"),
                !shareLink.isEmpty
            else {
                throw PacketTunnelManagerError.missingConfiguration
            }

            // 2. 启动前重新加载，避免系统配置仍处于待更新状态。
            try await saveAndReload(tunnelProviderManager)

            // 3. 构建原始运行配置；utun FD 只能由扩展在启动后注入。
            let configurationData = try await XrayConfigurationBuilder()
                .makeVPNConfigurationData(from: shareLink)

            // 4. JSON Data 作为一次性启动参数传递，不写入系统 VPN 协议配置。
            try tunnelProviderManager.connection.startVPNTunnel(options: [
                AppConstants.tunnelConfigurationOptionKey: configurationData as NSData,
            ])
            setActiveShareLink(shareLink)
            scheduleStartAcknowledgementTimeout()
            logger.info("VPN 尝试启动")
        } catch {
            startGate.cancel()
            startAcknowledgementTask?.cancel()
            startAcknowledgementTask = nil
            lifecycleState = .failed(error.localizedDescription)
            logger.error("连接 VPN 时出错: \(error.localizedDescription)")
            throw error
        }
    }

    /// 请求系统停止当前 VPN 连接。
    ///
    /// 该 API 是异步状态转换的起点，调用返回时状态可能仍为 `.disconnecting`。
    func stop() {
        guard lifecycleState.shouldWaitForStop else {
            return
        }
        startGate.cancel()
        startAcknowledgementTask?.cancel()
        startAcknowledgementTask = nil
        lifecycleState = .disconnecting
        tunnelProviderManager?.connection.stopVPNTunnel()
    }

    /// 等待当前连接完全停止后重新启动，使最新配置生效。
    ///
    /// `stopVPNTunnel()` 不提供 async 完成回调，因此每 0.25 秒检查一次系统状态。只有活动状态
    /// 完全结束后才重新执行完整启动流程，避免旧扩展尚未退出时启动新实例；超过指定时限则
    /// 返回明确的超时错误。
    ///
    /// - Throws: 等待任务被取消，或后续 `start()` 失败时抛出错误。
    func restart(timeout: Duration = .seconds(10)) async throws {
        stop()

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while lifecycleState.shouldWaitForStop {
            guard clock.now < deadline else {
                lifecycleState = .failed(PacketTunnelManagerError.restartTimedOut.localizedDescription)
                throw PacketTunnelManagerError.restartTimedOut
            }
            try await clock.sleep(for: .milliseconds(250))
            refreshConnectionState()
        }

        try await start()
    }

    /// 将 NetworkExtension 状态同步为稳定、可测试的应用生命周期状态。
    private func refreshConnectionState() {
        let systemState = VPNLifecycleState(systemStatus: tunnelProviderManager?.connection.status)
        synchronizeActiveShareLink(for: systemState)
        let nextState = startGate.reconcile(with: systemState)
        if !startGate.isPending {
            startAcknowledgementTask?.cancel()
            startAcknowledgementTask = nil
        }
        if lifecycleState != nextState {
            lifecycleState = nextState
        }

        let nextConnectedDate = tunnelProviderManager?.connection.connectedDate
        if connectedDate != nextConnectedDate {
            connectedDate = nextConnectedDate
        }
    }

    /// 在 App 重启后恢复活动配置，并在隧道完全停止后清除旧快照。
    private func synchronizeActiveShareLink(for systemState: VPNLifecycleState) {
        switch systemState {
        case .connecting, .connected, .reasserting, .disconnecting:
            guard activeShareLink == nil,
                  let persistedShareLink = AppGroupStore.loadString(forKey: activeShareLinkKey),
                  !persistedShareLink.isEmpty
            else {
                return
            }
            activeShareLink = persistedShareLink

        case .invalid, .disconnected:
            guard activeShareLink != nil
                || AppGroupStore.loadString(forKey: activeShareLinkKey) != nil
            else {
                return
            }
            activeShareLink = nil
            AppGroupStore.removeValue(forKey: activeShareLinkKey)

        case .loading, .failed:
            return
        }
    }

    private func setActiveShareLink(_ shareLink: String) {
        if activeShareLink != shareLink {
            activeShareLink = shareLink
        }
        if AppGroupStore.loadString(forKey: activeShareLinkKey) != shareLink {
            AppGroupStore.saveString(shareLink, forKey: activeShareLinkKey)
        }
    }

    private func scheduleStartAcknowledgementTimeout() {
        guard startGate.isPending else {
            return
        }
        startAcknowledgementTask?.cancel()
        startAcknowledgementTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(10))
            } catch {
                return
            }

            guard let self, self.startGate.isPending else {
                return
            }
            self.startGate.cancel()
            self.startAcknowledgementTask = nil
            self.tunnelProviderManager?.connection.stopVPNTunnel()
            self.lifecycleState = .failed(PacketTunnelManagerError.startTimedOut.localizedDescription)
            logger.error("等待系统确认 VPN 启动超时")
        }
    }
}
