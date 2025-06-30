//
//  UtilStore.swift
//  Xray
//
//  Created by pan on 2025/6/30.
//

import Foundation
import Network

enum UtilStore {
    private static let suiteName = "com.wayl.xray"
    private static var userDefaults: UserDefaults {
        return UserDefaults(suiteName: suiteName)!
    }

    /// 将值存储到 UserDefaults
    /// - Parameters:
    ///   - value: 要存储的字符串值
    ///   - key: 存储对应的键
    static func saveString(value: String, key: String) {
        userDefaults.set(value, forKey: key)
    }

    /// 从 UserDefaults 加载值
    /// - Parameter key: 存储的键
    /// - Returns: 对应的字符串值（如果存在）
    static func loadString(key: String) -> String? {
        userDefaults.string(forKey: key)
    }

    /// 将 Bool 值存储到 UserDefaults
    /// - Parameters:
    ///   - value: 要存储的布尔值
    ///   - key: 存储对应的键
    static func saveBool(value: Bool, key: String) {
        userDefaults.set(value, forKey: key)
    }

    /// 从 UserDefaults 加载 Bool 值
    /// - Parameter key: 存储的键
    /// - Returns: 对应的布尔值（如果未设置则为 false）
    static func loadBool(key: String) -> Bool {
        userDefaults.bool(forKey: key)
    }

    static func saveDate(value: Date, key: String) {
        userDefaults.set(value, forKey: key)
    }

    static func loadDate(key: String) -> Date? {
        userDefaults.object(forKey: key) as? Date
    }

    /// 将值存储到 UserDefaults
    /// - Parameters:
    ///   - value: 要存储的字符串值
    ///   - key: 存储对应的键
    static func saveArr(value: [Any], key: String) {
        userDefaults.set(value, forKey: key)
    }

    /// 从 UserDefaults 加载值
    /// - Parameter key: 存储的键
    /// - Returns: 对应的字符串值（如果存在）
    static func loadArr(key: String) -> [Any]? {
        userDefaults.array(forKey: key)
    }

    /// 将任意对象（如字典）保存为 JSON 字符串到 UserDefaults
    static func saveJSONObject(value: [String: Any], key: String) {
        if let data = try? JSONSerialization.data(withJSONObject: value, options: []),
           let jsonString = String(data: data, encoding: .utf8)
        {
            userDefaults.set(jsonString, forKey: key)
        }
    }

    /// 从 UserDefaults 加载 JSON 字符串并转回对象
    static func loadJSONObject(key: String) -> [String: Any]? {
        guard let jsonString = userDefaults.string(forKey: key),
              let data = jsonString.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
              let dictionary = jsonObject as? [String: Any]
        else {
            return nil
        }
        return dictionary
    }

    static func saveCodableObject<T: Codable>(value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            userDefaults.set(data, forKey: key)
        }
    }

    static func loadCodableObject<T: Codable>(key: String, type: T.Type) -> T? {
        guard let data = userDefaults.data(forKey: key),
              let object = try? JSONDecoder().decode(type, from: data)
        else {
            return nil
        }
        return object
    }

    static func saveInt(value: Int, key: String) {
        userDefaults.set(value, forKey: key)
    }

    static func savePort(value: NWEndpoint.Port, key: String) {
        userDefaults.set(value.rawValue, forKey: key)
    }

    static func loadPort(key: String) -> NWEndpoint.Port? {
        let intValue = userDefaults.integer(forKey: key)
        return NWEndpoint.Port(rawValue: UInt16(intValue))
    }

    static func loadInt(key: String) -> Int {
        userDefaults.integer(forKey: key)
    }

    /// 清空 UserDefaults
    static func clear() {
        userDefaults.removePersistentDomain(forName: suiteName)
    }
}
