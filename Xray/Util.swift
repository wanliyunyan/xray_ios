//
//  Util.swift
//  Xray
//
//  Created by pan on 2024/9/20.
//

import SwiftUI

/// 提供分享链接导入、摘要解析、地址脱敏和共享配置文件写入等无状态工具。
///
/// 所有方法均为静态方法，不持有界面或业务状态。用户偏好的实际存取集中在 `UtilStore`，
/// 此处只处理系统剪贴板、URLComponents 解析和文件系统操作。
enum Util {
    // MARK: - Clipboard

    /// 读取系统剪贴板中的非空字符串。
    ///
    /// - Returns: 剪贴板当前字符串；内容不存在或为空字符串时返回 `nil`。
    /// - Note: 该方法用于用户主动点击“粘贴”后的读取，不在后台自动访问剪贴板。
    static func pasteFromClipboard() -> String? {
        if let clipboardContent = UIPasteboard.general.string, !clipboardContent.isEmpty {
            return clipboardContent
        }
        return nil
    }

    // MARK: - Link Parsing

    /// 从分享链接中提取用户标识、主机和端口，用于主界面摘要展示。
    ///
    /// 方法只使用标准 `URLComponents` 读取通用 URL 字段，不负责验证 VLESS 等协议的完整
    /// 参数。无法解析时保持传入状态不变；可解析但某字段缺失时把对应文本设置为空字符串。
    ///
    /// - Parameters:
    ///   - content: 用户粘贴或扫描得到的完整分享链接。
    ///   - idText: 接收 URL `user` 字段的可变字符串。
    ///   - ipText: 接收 URL `host` 字段的可变字符串。
    ///   - portText: 接收 URL `port` 字段的可变字符串。
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

    /// 隐藏 IPv4 地址的前三段，仅保留最后一段用于区分节点。
    ///
    /// - Parameter ipAddress: 完整 IPv4、IPv6 地址或域名字符串。
    /// - Returns: IPv4 转换为 `*.*.*.<last>`；不是四段形式时原样返回。
    /// - Note: 该方法只做界面脱敏，不验证每段是否位于 `0...255`。
    static func maskIPAddress(_ ipAddress: String) -> String {
        let components = ipAddress.split(separator: ".")
        guard components.count == 4 else { return ipAddress }
        return "*.*.*." + components[3]
    }

    // MARK: - Shared Files

    /// 在 App Group 容器根目录创建或覆盖配置文件。
    ///
    /// 内容以 UTF-8 原子写入，避免 LibXray 在写入过程中读到部分 JSON。该方法主要用于
    /// Ping 配置；Packet Tunnel 的最终运行配置由 `LibXrayRuntime.writeConfig` 写到专用目录。
    ///
    /// - Parameters:
    ///   - content: 需要写入的完整文本，通常为 Xray JSON。
    ///   - fileName: 共享容器根目录中的文件名，默认 `config.json`。
    /// - Returns: 成功写入后的文件 URL。
    /// - Throws: App Group 容器不可用时抛出 `AppGroupError`；写入失败时抛出文件系统错误。
    static func createConfigFile(with content: String, fileName: String = "config.json") throws -> URL {
        // 1. 使用与 Packet Tunnel 扩展相同的 App Group 容器。
        guard let sharedContainerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Constant.groupName
        ) else {
            throw NSError(
                domain: "AppGroupError",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "无法找到 App Group 容器"]
            )
        }

        // 2. 文件位于共享容器根目录，重复写入时原子覆盖旧内容。
        let fileUrl = sharedContainerURL.appendingPathComponent(fileName)
        try content.write(to: fileUrl, atomically: true, encoding: .utf8)

        return fileUrl
    }
}
