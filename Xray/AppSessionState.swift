//
//  AppSessionState.swift
//  Xray
//
//  Created by pan on 2026/8/17.
//

import Network
import Observation

/// 本地服务端口在当前 App 进程中的准备方式。
enum LocalPortPreparationStrategy: Equatable, Sendable {
    /// VPN 未运行时生成一组新端口，并写入 App Group。
    case allocateNew

    /// Packet Tunnel 可能仍在运行时恢复其已经使用的 App Group 端口。
    case reusePersisted
}

/// 隔离端口持久化细节，便于会话状态在测试中使用内存实现。
protocol LocalPortStoring: Sendable {
    func loadLocalPorts() -> LocalServicePorts?
    func saveLocalPorts(_ ports: LocalServicePorts)
}

struct AppGroupLocalPortStore: LocalPortStoring {
    func loadLocalPorts() -> LocalServicePorts? {
        guard let metricsPort = AppGroupStore.loadPort(forKey: "trafficPort") else {
            return nil
        }

        return LocalServicePorts(metricsPort: metricsPort.rawValue)
    }

    func saveLocalPorts(_ ports: LocalServicePorts) {
        guard
            ports.metricsPort != 0,
            let metricsPort = NWEndpoint.Port(rawValue: ports.metricsPort)
        else {
            return
        }

        AppGroupStore.savePort(metricsPort, forKey: "trafficPort")
    }
}

/// 应用运行期间共享的临时状态。
///
/// VPN 未运行时，Metrics 端口在每次 App 进程启动时分配一次；Packet Tunnel 仍在运行时则
/// 恢复它已经使用的持久化端口。端口准备完成前不会启动流量查询或 VPN，避免配置监听端口
/// 与请求目标端口不一致。
@MainActor
@Observable
final class AppSessionState {
    @ObservationIgnored
    private let portAllocator: any LocalPortAllocating

    @ObservationIgnored
    private let portStore: any LocalPortStoring

    @ObservationIgnored
    private var portPreparationTask: Task<LocalServicePorts, Error>?

    private(set) var localPorts = LocalServicePorts.defaultValue
    private(set) var areLocalPortsReady = false
    private(set) var isPreparingLocalPorts = false
    private(set) var localPortPreparationError: String?

    var metricsPort: NWEndpoint.Port {
        NWEndpoint.Port(rawValue: localPorts.metricsPort) ?? AppConstants.defaultMetricsPort
    }

    init(
        portAllocator: any LocalPortAllocating = XrayService(),
        portStore: any LocalPortStoring = AppGroupLocalPortStore()
    ) {
        self.portAllocator = portAllocator
        self.portStore = portStore
    }

    /// 根据 VPN 生命周期恢复旧端口或分配并持久化新端口。
    func prepareLocalPorts(using strategy: LocalPortPreparationStrategy) async {
        guard !areLocalPortsReady else {
            return
        }

        if strategy == .reusePersisted {
            guard let persistedPorts = portStore.loadLocalPorts() else {
                return
            }
            applyPreparedPorts(persistedPorts)
            return
        }

        let preparationTask: Task<LocalServicePorts, Error>
        if let portPreparationTask {
            preparationTask = portPreparationTask
        } else {
            isPreparingLocalPorts = true
            localPortPreparationError = nil
            let portAllocator = portAllocator
            let newTask = Task {
                try await portAllocator.allocateLocalPorts()
            }
            portPreparationTask = newTask
            preparationTask = newTask
        }

        let preparationResult = await preparationTask.result
        let wasCancelled = Task.isCancelled
        portPreparationTask = nil
        isPreparingLocalPorts = false

        guard !wasCancelled else {
            return
        }
        guard !areLocalPortsReady else {
            return
        }

        let allocatedPorts: LocalServicePorts
        switch preparationResult {
        case .success(let ports):
            allocatedPorts = ports
        case .failure(let error):
            guard !(error is CancellationError) else {
                return
            }
            localPortPreparationError = error.localizedDescription
            return
        }

        guard applyPreparedPorts(allocatedPorts) else {
            localPortPreparationError = "本地服务端口无效"
            return
        }
        portStore.saveLocalPorts(allocatedPorts)
    }

    @discardableResult
    private func applyPreparedPorts(_ ports: LocalServicePorts) -> Bool {
        guard
            ports.metricsPort != 0,
            NWEndpoint.Port(rawValue: ports.metricsPort) != nil
        else {
            return false
        }

        localPorts = ports
        areLocalPortsReady = true
        localPortPreparationError = nil
        return true
    }
}
