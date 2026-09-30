//
//  AppSessionState.swift
//  Xray
//
//  Created by pan on 2026/8/17.
//

import Foundation
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
    private var portPreparation: PortPreparation?

    private struct PortPreparation {
        let id = UUID()
        let task: Task<LocalServicePorts, Error>
        var waiters: Set<UUID> = []
    }

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
        guard !Task.isCancelled, !areLocalPortsReady else {
            return
        }

        if strategy == .reusePersisted {
            guard let persistedPorts = portStore.loadLocalPorts() else {
                return
            }
            applyPreparedPorts(persistedPorts)
            return
        }

        // 底层同步调用可能无法立即响应取消。保留句柄并等它结束后再重试，
        // 避免新旧分配同时运行；旧等待者只能清理自己的批次。
        while let preparation = portPreparation, preparation.task.isCancelled {
            _ = await preparation.task.result
            if portPreparation?.id == preparation.id {
                portPreparation = nil
                isPreparingLocalPorts = false
            }
            guard !Task.isCancelled, !areLocalPortsReady else {
                return
            }
        }

        if portPreparation == nil {
            isPreparingLocalPorts = true
            localPortPreparationError = nil
            let portAllocator = portAllocator
            let newTask = Task {
                try Task.checkCancellation()
                let ports = try await portAllocator.allocateLocalPorts()
                try Task.checkCancellation()
                return ports
            }
            portPreparation = PortPreparation(task: newTask)
        }

        guard let preparation = portPreparation else { return }
        let waiterID = UUID()
        portPreparation?.waiters.insert(waiterID)
        let preparationResult = await withTaskCancellationHandler {
            await preparation.task.result
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelPortPreparationWaiter(waiterID, preparationID: preparation.id)
            }
        }

        guard portPreparation?.id == preparation.id else {
            return
        }
        portPreparation?.waiters.remove(waiterID)
        if portPreparation?.waiters.isEmpty == true {
            portPreparation = nil
            isPreparingLocalPorts = false
        }

        guard !Task.isCancelled, !preparation.task.isCancelled, !areLocalPortsReady else {
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

    private func cancelPortPreparationWaiter(_ waiterID: UUID, preparationID: UUID) {
        guard portPreparation?.id == preparationID else { return }
        portPreparation?.waiters.remove(waiterID)
        if portPreparation?.waiters.isEmpty == true {
            portPreparation?.task.cancel()
        }
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
