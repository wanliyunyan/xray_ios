//
//  AppGroupStore.swift
//  Xray
//
//  Created by pan on 2025/6/30.
//

import Foundation
import Network

/// App 与 Packet Tunnel 扩展共享的字符串和网络端口存储入口。
enum AppGroupStore {
    /// App Group UserDefaults suite 名称。
    private static let suiteName = AppConstants.appGroupIdentifier

    /// 每次访问时取得共享 suite，避免缓存非 `Sendable` 的 Foundation 引用。
    ///
    /// 项目正确配置 App Group 后该初始化必定成功；使用强制解包让签名或 entitlement 配置
    /// 错误在开发阶段立即暴露，而不是静默回退到标准 UserDefaults。
    private static var userDefaults: UserDefaults {
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("无法加载 App Group UserDefaults: \(suiteName)")
        }
        return userDefaults
    }

    static func saveString(_ value: String, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }

    static func loadString(forKey key: String) -> String? {
        userDefaults.string(forKey: key)
    }

    static func savePort(_ value: NWEndpoint.Port, forKey key: String) {
        userDefaults.set(value.rawValue, forKey: key)
    }

    /// 从已保存的整数恢复网络端口。
    ///
    /// `integer(forKey:)` 在键不存在时返回 0，而端口类型本身允许原始值 0，因此必须先区分
    /// “键不存在”和已保存的整数，再明确拒绝不能作为连接目标使用的端口 0。越界或负数值
    /// 同样返回 `nil`，不会触发整数转换崩溃。
    ///
    static func loadPort(forKey key: String) -> NWEndpoint.Port? {
        guard userDefaults.object(forKey: key) != nil else {
            return nil
        }

        let intValue = userDefaults.integer(forKey: key)
        guard let rawValue = UInt16(exactly: intValue), rawValue != 0 else {
            return nil
        }
        return NWEndpoint.Port(rawValue: rawValue)
    }

    static func removeValue(forKey key: String) {
        userDefaults.removeObject(forKey: key)
    }
}
