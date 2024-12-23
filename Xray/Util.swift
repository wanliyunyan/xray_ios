//
//  Util.swift
//  Xray
//
//  Created by pan on 2024/9/20.
//

import Foundation
import SwiftUI

enum Util {
    static func saveToUserDefaults(value: String, key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    static func loadFromUserDefaults(key: String) -> String? {
        UserDefaults.standard.string(forKey: key)
    }

    static func pasteFromClipboard() -> String? {
        if let clipboardContent = UIPasteboard.general.string, !clipboardContent.isEmpty {
            return clipboardContent
        }
        return nil
    }

    static func parseContent(_ content: String, idText: inout String, ipText: inout String, portText: inout String) {
        if let url = URLComponents(string: content) {
            ipText = url.host ?? ""
            idText = url.user ?? ""
            portText = url.port.map(String.init) ?? ""
        }
    }

    static func maskIPAddress(_ ipAddress: String) -> String {
        let components = ipAddress.split(separator: ".")
        return components.count == 4 ? "*.*.*." + components[3] : ipAddress
    }

    static func createConfigFile(with content: String, fileName: String = "config.json") throws -> URL {
        guard let sharedContainerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Constant.groupName) else {
            throw NSError(domain: "无法找到 App Group 容器", code: 1, userInfo: nil)
        }

        // 在共享容器中创建文件路径
        let fileUrl = sharedContainerURL.appendingPathComponent(fileName)

        // 将内容写入文件
        try content.write(to: fileUrl, atomically: true, encoding: .utf8)

        return fileUrl
    }
}
