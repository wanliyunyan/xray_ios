//
//  SharedConfigurationFileStore.swift
//  Xray
//
//  Created by pan on 2026/8/17.
//

import Foundation

enum SharedConfigurationFileStoreError: LocalizedError, Equatable, Sendable {
    case missingSharedContainer

    var errorDescription: String? {
        "无法找到 App Group 容器"
    }
}

/// 将 Xray 配置文件写入主 App 与 Packet Tunnel 扩展共享的 App Group 容器。
enum SharedConfigurationFileStore {
    /// 以原子写入方式保存配置 JSON，并返回最终文件位置。
    static func write(
        _ configurationJSON: String,
        fileName: String = "config.json"
    ) throws -> URL {
        guard let sharedContainerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier
        ) else {
            throw SharedConfigurationFileStoreError.missingSharedContainer
        }

        let configurationFileURL = sharedContainerURL.appendingPathComponent(fileName)
        try configurationJSON.write(to: configurationFileURL, atomically: true, encoding: .utf8)
        return configurationFileURL
    }
}
