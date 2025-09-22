//
//  UtilStore.swift
//  Xray
//
//  Created by pan on 2025/6/30.
//

import Foundation
import Network

/// UtilStore 是一个集中式辅助工具，用于在 App Group 的 UserDefaults 中读写多种数据类型（如字符串、布尔值、数组、字典、Codable 对象等）。
/// 通过统一接口，便于跨组件安全、高效地持久化和读取应用数据。
enum UtilStore {
    private static let suiteName = Constant.groupName
    private static var userDefaults: UserDefaults {
        UserDefaults(suiteName: suiteName)!
    }

    /**
     保存字符串到 UserDefaults。

     - Parameters:
        - value: 要存储的字符串值。
        - key: 存储对应的键。
     - Returns:

     - Throws:

     - Note:
     */
    static func saveString(value: String, key: String) {
        userDefaults.set(value, forKey: key)
    }

    /**
     从 UserDefaults 加载字符串。

     - Parameters:
        - key: 存储的键。
     - Returns: 对应的字符串值，如果不存在则返回 nil。

     - Throws:

     - Note:
     */
    static func loadString(key: String) -> String? {
        userDefaults.string(forKey: key)
    }

    /**
     保存布尔值到 UserDefaults。

     - Parameters:
        - value: 要存储的布尔值。
        - key: 存储对应的键。
     - Returns:

     - Throws:

     - Note:
     */
    static func saveBool(value: Bool, key: String) {
        userDefaults.set(value, forKey: key)
    }

    /**
     从 UserDefaults 加载布尔值。

     - Parameters:
        - key: 存储的键。
     - Returns: 对应的布尔值，如果未设置则为 false。

     - Throws:

     - Note:
     */
    static func loadBool(key: String) -> Bool {
        userDefaults.bool(forKey: key)
    }

    /**
     保存日期到 UserDefaults。

     - Parameters:
        - value: 要存储的日期对象。
        - key: 存储对应的键。
     - Returns:

     - Throws:

     - Note:
     */
    static func saveDate(value: Date, key: String) {
        userDefaults.set(value, forKey: key)
    }

    /**
     从 UserDefaults 加载日期。

     - Parameters:
        - key: 存储的键。
     - Returns: 对应的日期对象，如果不存在则返回 nil。

     - Throws:

     - Note:
     */
    static func loadDate(key: String) -> Date? {
        userDefaults.object(forKey: key) as? Date
    }

    /**
     保存数组到 UserDefaults。

     - Parameters:
        - value: 要存储的数组（元素需为 PropertyList 支持的类型）。
        - key: 存储对应的键。
     - Returns:

     - Throws:

     - Note:
     */
    static func saveArr(value: [Any], key: String) {
        userDefaults.set(value, forKey: key)
    }

    /**
     从 UserDefaults 加载数组。

     - Parameters:
        - key: 存储的键。
     - Returns: 对应的数组，如果不存在则返回 nil。

     - Throws:

     - Note:
     */
    static func loadArr(key: String) -> [Any]? {
        userDefaults.array(forKey: key)
    }

    /**
     保存字典为 JSON 字符串到 UserDefaults。

     - Parameters:
        - value: 要存储的字典（可序列化为 JSON）。
        - key: 存储对应的键。
     - Returns:

     - Throws:

     - Note:
     */
    static func saveJSONObject(value: [String: Any], key: String) {
        if let data = try? JSONSerialization.data(withJSONObject: value, options: []),
           let jsonString = String(data: data, encoding: .utf8)
        {
            userDefaults.set(jsonString, forKey: key)
        }
    }

    /**
     从 UserDefaults 加载 JSON 字符串并转为字典对象。

     - Parameters:
        - key: 存储的键。
     - Returns: 对应的字典对象，如果不存在或解析失败则返回 nil。

     - Throws:

     - Note:
     */
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

    /**
     保存 Codable 对象到 UserDefaults。

     - Parameters:
        - value: 要存储的 Codable 类型对象。
        - key: 存储对应的键。
     - Returns:

     - Throws:

     - Note:
     */
    static func saveCodableObject(value: some Codable, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            userDefaults.set(data, forKey: key)
        }
    }

    /**
     从 UserDefaults 加载 Codable 对象。

     - Parameters:
        - key: 存储的键。
        - type: 对象的类型（用于类型推断）。
     - Returns: 对应的 Codable 对象，如果不存在或解析失败则返回 nil。

     - Throws:

     - Note:
     */
    static func loadCodableObject<T: Codable>(key: String, type: T.Type) -> T? {
        guard let data = userDefaults.data(forKey: key),
              let object = try? JSONDecoder().decode(type, from: data)
        else {
            return nil
        }
        return object
    }

    /**
     保存整数到 UserDefaults。

     - Parameters:
        - value: 要存储的整数值。
        - key: 存储对应的键。
     - Returns:

     - Throws:

     - Note:
     */
    static func saveInt(value: Int, key: String) {
        userDefaults.set(value, forKey: key)
    }

    /**
     保存 NWEndpoint.Port 到 UserDefaults。

     - Parameters:
        - value: 要存储的端口（NWEndpoint.Port）。
        - key: 存储对应的键。
     - Returns:

     - Throws:

     - Note:
     */
    static func savePort(value: NWEndpoint.Port, key: String) {
        userDefaults.set(value.rawValue, forKey: key)
    }

    /**
     从 UserDefaults 加载 NWEndpoint.Port。

     - Parameters:
        - key: 存储的键。
     - Returns: 对应的 NWEndpoint.Port，如果不存在或无效则返回 nil。

     - Throws:

     - Note:
     */
    static func loadPort(key: String) -> NWEndpoint.Port? {
        let intValue = userDefaults.integer(forKey: key)
        return NWEndpoint.Port(rawValue: UInt16(intValue))
    }

    /**
     从 UserDefaults 加载整数值。

     - Parameters:
        - key: 存储的键。
     - Returns: 对应的整数值，如果未设置则为 0。

     - Throws:

     - Note:
     */
    static func loadInt(key: String) -> Int {
        userDefaults.integer(forKey: key)
    }

    /**
     清空 UserDefaults（移除所有存储的键值对）。

     - Parameters:

     - Returns:

     - Throws:

     - Note:
     */
    static func clear() {
        userDefaults.removePersistentDomain(forName: suiteName)
    }
}
