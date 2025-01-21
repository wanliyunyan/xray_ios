//
//  Util.swift
//  Xray
//
//  Created by pan on 2024/9/20.
//

import Foundation
import SwiftUI

/// 一个通用的工具枚举，包含项目中常用的用户偏好存取、剪贴板读取、配置写入等功能。
enum Util {
    // MARK: - UserDefaults

    /// 将字符串存储到用户默认（UserDefaults）中。
    ///
    /// - Parameters:
    ///   - value: 需要存储的字符串值。
    ///   - key: 存储时对应的键名。
    static func saveToUserDefaults(value: String, key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    /// 从用户默认（UserDefaults）中读取字符串。
    ///
    /// - Parameter key: 存储时使用的键名。
    /// - Returns: 如果存在并且类型匹配，则返回对应的字符串；否则返回 `nil`。
    static func loadFromUserDefaults(key: String) -> String? {
        UserDefaults.standard.string(forKey: key)
    }

    // MARK: - 剪贴板操作

    /// 从系统剪贴板读取字符串内容。
    ///
    /// - Returns: 若剪贴板中存在非空字符串，则返回该字符串；否则返回 `nil`。
    static func pasteFromClipboard() -> String? {
        if let clipboardContent = UIPasteboard.general.string, !clipboardContent.isEmpty {
            return clipboardContent
        }
        return nil
    }

    // MARK: - 字符串解析

    /// 解析给定的 URL 字符串，从中提取 id、host (IP)、端口号等信息。
    ///
    /// - Parameters:
    ///   - content: 待解析的内容（通常是一个含有 URL 协议头的字符串）。
    ///   - idText: 用于承接解析后的用户标识部分（通常为 URL 的 user 字段）。
    ///   - ipText: 用于承接解析后的 IP 地址或域名（通常为 URL 的 host 字段）。
    ///   - portText: 用于承接解析后的端口号字符串（如果有）。
    static func parseContent(_ content: String,
                             idText: inout String,
                             ipText: inout String,
                             portText: inout String)
    {
        if let urlComponents = URLComponents(string: content) {
            ipText = urlComponents.host ?? ""
            idText = urlComponents.user ?? ""
            portText = urlComponents.port.map(String.init) ?? ""
        }
    }

    // MARK: - IP 地址处理

    /// 对 IP 地址进行部分掩码处理，例如将 `192.168.1.100` 转换为 `*.*.*.100`。
    ///
    /// - Parameter ipAddress: 完整的 IP 地址字符串。
    /// - Returns: 掩码处理后的 IP 地址，用于隐藏除最后一段以外的信息。如果不符合 IPv4 格式则返回原字符串。
    static func maskIPAddress(_ ipAddress: String) -> String {
        let components = ipAddress.split(separator: ".")
        guard components.count == 4 else { return ipAddress }
        return "*.*.*." + components[3]
    }

    // MARK: - 文件写入

    /// 在 App Group 容器内创建或覆盖指定文件，并将内容写入其中。
    ///
    /// - Parameters:
    ///   - content: 文件内容（一般为字符串形式的 JSON 或其他配置信息）。
    ///   - fileName: 写入的文件名（默认为 "config.json"）。
    /// - Returns: 写入成功后生成的文件 URL。
    /// - Throws: 当无法获取 App Group 容器 URL 或文件写入失败时，抛出相应错误。
    static func createConfigFile(with content: String, fileName: String = "config.json") throws -> URL {
        // 1. 获取共享容器 URL
        guard let sharedContainerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Constant.groupName
        ) else {
            throw NSError(
                domain: "AppGroupError",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "无法找到 App Group 容器"]
            )
        }

        // 2. 在共享容器中创建或获取文件路径
        let fileUrl = sharedContainerURL.appendingPathComponent(fileName)

        // 3. 将内容写入指定文件
        try content.write(to: fileUrl, atomically: true, encoding: .utf8)

        return fileUrl
    }
}
