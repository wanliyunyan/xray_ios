//
//  AppGroupStore.swift
//  Xray
//
//  Created by pan on 2025/6/30.
//

import Foundation
import Network

/// App 与 Packet Tunnel 扩展共享的 UserDefaults 类型化访问入口。
///
/// 所有数据写入 `AppConstants.appGroupIdentifier` 对应的 App Group suite，使主 App 构建的配置、端口和
/// 用户选择可以被扩展相关流程读取。该类型为常用标量、集合、JSON、Codable 和网络端口提供
/// 统一方法，避免各调用点重复创建 suite 或手动转换类型。
enum AppGroupStore {
    /// App Group UserDefaults suite 名称。
    private static let suiteName = AppConstants.appGroupIdentifier

    /// 每次访问时取得共享 suite。
    ///
    /// 项目正确配置 App Group 后该初始化必定成功；使用强制解包让签名或 entitlement 配置
    /// 错误在开发阶段立即暴露，而不是静默回退到标准 UserDefaults。
    private static var userDefaults: UserDefaults {
        UserDefaults(suiteName: suiteName)!
    }

    // MARK: - Primitive Values

    /// 保存字符串值。
    /// - Parameters:
    ///   - value: 需要持久化的字符串。
    ///   - key: App Group 偏好键。
    static func saveString(_ value: String, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }

    /// 读取字符串值。
    /// - Parameter key: App Group 偏好键。
    /// - Returns: 已保存字符串；键不存在或类型不匹配时返回 `nil`。
    static func loadString(forKey key: String) -> String? {
        userDefaults.string(forKey: key)
    }

    /// 保存布尔值。
    /// - Parameters:
    ///   - value: 需要持久化的布尔值。
    ///   - key: App Group 偏好键。
    static func saveBool(_ value: Bool, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }

    /// 读取布尔值。
    /// - Parameter key: App Group 偏好键。
    /// - Returns: 已保存值；键不存在时遵循 UserDefaults 语义返回 `false`。
    static func loadBool(forKey key: String) -> Bool {
        userDefaults.bool(forKey: key)
    }

    /// 保存日期对象。
    /// - Parameters:
    ///   - value: 需要持久化的日期。
    ///   - key: App Group 偏好键。
    static func saveDate(_ value: Date, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }

    /// 读取日期对象。
    /// - Parameter key: App Group 偏好键。
    /// - Returns: 已保存日期；键不存在或类型不匹配时返回 `nil`。
    static func loadDate(forKey key: String) -> Date? {
        userDefaults.object(forKey: key) as? Date
    }

    // MARK: - Collections

    /// 保存数组。
    ///
    /// - Parameters:
    ///   - value: 元素必须是 Property List 支持类型的数组。
    ///   - key: App Group 偏好键。
    static func saveArray(_ value: [Any], forKey key: String) {
        userDefaults.set(value, forKey: key)
    }

    /// 读取数组。
    /// - Parameter key: App Group 偏好键。
    /// - Returns: 已保存数组；键不存在或类型不匹配时返回 `nil`。
    static func loadArray(forKey key: String) -> [Any]? {
        userDefaults.array(forKey: key)
    }

    /// 将字典编码为 JSON 字符串后保存。
    ///
    /// - Parameters:
    ///   - value: 必须可由 `JSONSerialization` 序列化的字典。
    ///   - key: App Group 偏好键。
    /// - Note: 编码或 UTF-8 转换失败时不覆盖原值，也不抛出错误。
    static func saveJSON(_ value: [String: Any], forKey key: String) {
        if let data = try? JSONSerialization.data(withJSONObject: value, options: []),
           let jsonString = String(data: data, encoding: .utf8)
        {
            userDefaults.set(jsonString, forKey: key)
        }
    }

    /// 读取并解析已保存的 JSON 字典。
    ///
    /// - Parameter key: 保存 JSON 字符串的 App Group 偏好键。
    /// - Returns: 成功解析的 `[String: Any]`；键缺失、UTF-8 转换或 JSON 解析失败时返回 `nil`。
    static func loadJSON(forKey key: String) -> [String: Any]? {
        guard let jsonString = userDefaults.string(forKey: key),
              let data = jsonString.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
              let dictionary = jsonObject as? [String: Any]
        else {
            return nil
        }
        return dictionary
    }

    // MARK: - Codable Values

    /// 使用 JSON 编码器保存 Codable 值。
    ///
    /// - Parameters:
    ///   - value: 需要编码的任意 Codable 值。
    ///   - key: App Group 偏好键。
    /// - Note: 编码失败时保持原值，不向调用方抛出错误。
    static func saveCodable<T: Codable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            userDefaults.set(data, forKey: key)
        }
    }

    /// 使用 JSON 解码器恢复指定类型的 Codable 值。
    ///
    /// - Parameters:
    ///   - key: 保存编码 Data 的 App Group 偏好键。
    ///   - type: 目标 Codable 类型，用于泛型推断和解码。
    /// - Returns: 解码成功的对象；数据不存在或格式不匹配时返回 `nil`。
    static func loadCodable<T: Codable>(forKey key: String, as type: T.Type) -> T? {
        guard let data = userDefaults.data(forKey: key),
              let object = try? JSONDecoder().decode(type, from: data)
        else {
            return nil
        }
        return object
    }

    // MARK: - Numeric Values

    /// 保存整数值。
    /// - Parameters:
    ///   - value: 需要持久化的整数。
    ///   - key: App Group 偏好键。
    static func saveInt(_ value: Int, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }

    // MARK: - Network Values

    /// 以原始 UInt16 值保存网络端口。
    ///
    /// - Parameters:
    ///   - value: 需要共享给配置构建或 Metrics 查询的端口。
    ///   - key: App Group 偏好键。
    static func savePort(_ value: NWEndpoint.Port, forKey key: String) {
        userDefaults.set(value.rawValue, forKey: key)
    }

    /// 从已保存的整数恢复网络端口。
    ///
    /// `integer(forKey:)` 在键不存在时返回 0，而 `NWEndpoint.Port(rawValue: 0)` 返回 `nil`，
    /// 因此缺失值可以自然表示为可选端口。方法假设值由 `savePort` 写入并位于 UInt16 范围内。
    ///
    /// - Parameter key: 保存端口原始值的 App Group 偏好键。
    /// - Returns: 有效端口；键不存在或端口为 0 时返回 `nil`。
    static func loadPort(forKey key: String) -> NWEndpoint.Port? {
        let intValue = userDefaults.integer(forKey: key)
        return NWEndpoint.Port(rawValue: UInt16(intValue))
    }

    /// 读取整数值。
    /// - Parameter key: App Group 偏好键。
    /// - Returns: 已保存整数；键不存在时遵循 UserDefaults 语义返回 `0`。
    static func loadInt(forKey key: String) -> Int {
        userDefaults.integer(forKey: key)
    }

    // MARK: - Reset

    /// 清空 App Group 偏好域中的所有键值。
    ///
    /// 该操作会同时移除分享链接、端口、VPN 模式及调用方保存的其他数据，主要用于重置或测试。
    static func removeAll() {
        userDefaults.removePersistentDomain(forName: suiteName)
    }
}
