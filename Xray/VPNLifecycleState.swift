//
//  VPNLifecycleState.swift
//  Xray
//
//  Created by pan on 2026/8/17.
//

import NetworkExtension

/// 应用可观察的 Packet Tunnel 生命周期状态。
enum VPNLifecycleState: Equatable, Sendable {
    case loading
    case invalid
    case disconnected
    case connecting
    case connected
    case reasserting
    case disconnecting
    case failed(String)

    init(systemStatus: NEVPNStatus?) {
        switch systemStatus {
        case nil:
            self = .loading
        case .invalid:
            self = .invalid
        case .disconnected:
            self = .disconnected
        case .connecting:
            self = .connecting
        case .connected:
            self = .connected
        case .reasserting:
            self = .reasserting
        case .disconnecting:
            self = .disconnecting
        @unknown default:
            self = .invalid
        }
    }

    var isConnected: Bool {
        self == .connected
    }

    var shouldWaitForStop: Bool {
        switch self {
        case .connected, .connecting, .reasserting, .disconnecting:
            true
        default:
            false
        }
    }

    /// 当前连接已经锁定启动时的配置，后续导入应延迟到下一次连接生效。
    var shouldDeferConfigurationChanges: Bool {
        switch self {
        case .connecting, .connected, .reasserting, .disconnecting:
            true
        default:
            false
        }
    }

    /// VPN 配置加载完成后，决定当前 App 进程应恢复旧端口还是生成新端口。
    var localPortPreparationStrategy: LocalPortPreparationStrategy? {
        switch self {
        case .loading:
            nil
        case .connecting, .connected, .reasserting, .disconnecting, .failed:
            .reusePersisted
        case .invalid, .disconnected:
            .allocateNew
        }
    }
}

/// 防止异步启动流程在系统状态尚未更新时被重复进入。
struct VPNStartGate: Sendable {
    private(set) var isPending = false

    mutating func begin(from lifecycleState: VPNLifecycleState) throws {
        guard !isPending else {
            throw PacketTunnelManagerError.invalidState(.connecting)
        }
        guard lifecycleState == .disconnected else {
            throw PacketTunnelManagerError.invalidState(lifecycleState)
        }
        isPending = true
    }

    mutating func reconcile(with systemState: VPNLifecycleState) -> VPNLifecycleState {
        guard isPending else {
            return systemState
        }

        switch systemState {
        case .loading, .invalid, .disconnected:
            return .connecting
        case .connecting, .connected, .reasserting, .disconnecting, .failed:
            isPending = false
            return systemState
        }
    }

    mutating func cancel() {
        isPending = false
    }
}

enum PacketTunnelManagerError: LocalizedError, Equatable, Sendable {
    case managerUnavailable
    case invalidState(VPNLifecycleState)
    case missingConfiguration
    case preferenceUpdateFailed(String)
    case startTimedOut
    case restartTimedOut

    var errorDescription: String? {
        switch self {
        case .managerUnavailable:
            "VPN 配置尚未初始化完成"
        case .invalidState:
            "当前 VPN 状态不允许执行此操作"
        case .missingConfiguration:
            "没有可用的节点配置"
        case .preferenceUpdateFailed(let message):
            "保存或加载 VPN 配置失败：\(message)"
        case .startTimedOut:
            "等待 VPN 开始连接超时"
        case .restartTimedOut:
            "等待 VPN 断开超时"
        }
    }
}
